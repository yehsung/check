import AppKit
import AVFoundation
import SwiftUI
import Combine
import Observation
#if ALKKAGI_PLAYGROUND
import AlkkagiCore
#else
import CheckCore
#endif

struct AlkkagiPlayerProfile: Equatable {
    let name: String
    var characterID: String? = nil
}

// 판 화면(왼쪽 판 · 오른쪽 열). 판 그림 · 감속 · 방향 화살 · 멈칫 · 소리 · 주사율 걸음 · 조준 입력은 손대지 않는다(SPEC v1.1 §5.9).
// 오른쪽 열은 기존 1:1 판 게임 꼴(§5.5 — 뒤집기 `ReversiMatchSide`): 상대 카드 · 내 카드 · 상태 카드(관전자 수 칩) · 돌 수 카드 ·
// [기권](빨간 띠 + `GomokuResignGuard`). 판 중 대화 카드는 판 화면에서 뺐다(§0 #11 · VC-10 · D23 — `AlkkagiChatPanel` 은
// 되살리기용으로 남긴다: 돌 수 카드 아래에 다시 넣으면 된다). 끝나면 오른쪽 열에 결과 카드(§5.6), 판 위엔 돌을 덜 가리는
// 얇은 띠(D21 — 옛 겹 카드 · 아래 [로비로] 는 없다). 독립 실행기(§5.10)는 로컬 연습만 — 온라인 부분은 앱 빌드에서만 컴파일된다.
@MainActor
struct AlkkagiGameView: View {
    var onReturn: (() -> Void)? = nil
    var me = AlkkagiPlayerProfile(name: "플레이어 1")
    var opponent = AlkkagiPlayerProfile(name: "플레이어 2")
    #if !ALKKAGI_PLAYGROUND
    var onlineStore: AlkkagiOnlineStore? = nil
    /// 스냅샷 전용: [기권] 자리를 확인 상태로 그린다. 앱은 false.
    var previewConfirmResign = false
    #endif
    @State private var model: AlkkagiLocalModel
    /// 손 안내 횟수를 기억할 곳(창 루트가 `.standard` 를 넣는다 — 시험 · 스냅숏은 nil 이라 표준 스위트에 쓰지 않는다).
    var guideDefaults: UserDefaults? = nil

    #if ALKKAGI_PLAYGROUND
    init(onReturn: (() -> Void)? = nil, me: AlkkagiPlayerProfile = AlkkagiPlayerProfile(name: "플레이어 1"),
         opponent: AlkkagiPlayerProfile = AlkkagiPlayerProfile(name: "플레이어 2"),
         model: AlkkagiLocalModel = AlkkagiLocalModel()) {
        self.onReturn = onReturn
        self.me = me
        self.opponent = opponent
        _model = State(initialValue: model)
    }
    #else
    /// `model` 은 렌더 시험이 판 값을 넣는 입구다(앱은 기본값 — 창마다 새 모델).
    init(onReturn: (() -> Void)? = nil, me: AlkkagiPlayerProfile = AlkkagiPlayerProfile(name: "플레이어 1"),
         opponent: AlkkagiPlayerProfile = AlkkagiPlayerProfile(name: "플레이어 2"),
         onlineStore: AlkkagiOnlineStore? = nil, model: AlkkagiLocalModel = AlkkagiLocalModel()) {
        self.onReturn = onReturn
        self.me = me
        self.opponent = opponent
        self.onlineStore = onlineStore
        _model = State(initialValue: model)
    }
    #endif
    @GestureState private var dragIsActive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 판 걸음은 화면 주사율에 맞춘다(120Hz 타이머는 60 · 75 · 144Hz 화면과 박자가 어긋나 규칙적으로 끊긴다 —
    /// 메모 game-frame-rate-judder). 창 컨트롤러가 주사율 감시를 환경으로 준다. 없으면(독립 실행기 · 시험) 60.
    #if !ALKKAGI_PLAYGROUND
    /// 창 컨트롤러가 넣는다(창마다 자기 감시). 뷰 타입을 바꾸지 않으려고 환경이 아니라 속성이다.
    var frameRateMonitor: MiniGameFrameRateMonitor?
    private var frameInterval: Double { MiniGameFrameRate.minimumInterval(forRefreshRate: frameRateMonitor?.refreshHz ?? MiniGameFrameRate.baselineFPS) }
    #else
    private var frameInterval: Double { 1.0 / 60 }
    #endif
    private var boardSide: CGFloat { AlkkagiDrawing.boardSide }

    /// 온라인 판에서 판 화면이 읽는 사실(평범한 값). 독립 실행기에는 온라인이 없어 늘 nil 이다.
    private struct OnlineFacts {
        var isPlacing: Bool
        var isFinished: Bool
        var concealed: Bool
        var currentPlayer: AlkkagiGame.Player
        var myReady: Bool
        var opponentReady: Bool
        var black: AlkkagiPlayerProfile
        var white: AlkkagiPlayerProfile
    }

    private var online: OnlineFacts? {
        #if ALKKAGI_PLAYGROUND
        return nil
        #else
        guard let state = onlineStore?.state else { return nil }
        return OnlineFacts(
            isPlacing: state.phase == .placing,
            isFinished: state.phase == .finished,
            concealed: state.phase == .placing || (state.phase == .finished && (!state.myReady || !state.opponentReady)),
            currentPlayer: state.currentPlayer, myReady: state.myReady, opponentReady: state.opponentReady,
            black: AlkkagiPlayerProfile(name: state.black.displayName, characterID: state.black.characterID),
            white: AlkkagiPlayerProfile(name: state.white.displayName, characterID: state.white.characterID))
        #endif
    }

    private var isOnline: Bool {
        #if ALKKAGI_PLAYGROUND
        false
        #else
        onlineStore != nil
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BoardGameLayout.headerSpacing) {
            header.frame(height: BoardGameLayout.headerHeight)
            BoardGameMatchLayout {
                board
            } sidebar: {
                sidebar
            }
        }
        .padding(BoardGameLayout.contentPadding)
        .frame(width: BoardGameLayout.contentSize.width, height: BoardGameLayout.contentSize.height)
        .background(CheckTheme.background)
        .foregroundStyle(CheckTheme.primaryText)
        .preferredColorScheme(.dark)
        #if !ALKKAGI_PLAYGROUND
        .onAppear { model.attachOnline(onlineStore) }
        #endif
        .onAppear { if let guideDefaults, model.guideDefaults == nil { model.guideDefaults = guideDefaults } }
        .background {
            TimelineView(.animation(minimumInterval: frameInterval)) { context in
                Color.clear.onChange(of: context.date) { _, _ in model.tick() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in model.cancelAim() }
        .onExitCommand { model.cancelAim() }
        .onChange(of: dragIsActive) { _, active in
            if !active { model.finishGesture() }
        }
    }

    // MARK: 머리글(§5.2 — 뒤집기 `ReversiHeader` 꼴, 높이 40)

    #if ALKKAGI_PLAYGROUND
    private static let headerIcon = "circle.hexagongrid.fill"
    private static let headerTitle = "1:1 알까기"
    private static let headerSubtitle = "연습 판"
    #else
    private static var headerIcon: String { AlkkagiEntryIcon.resolved }
    private static let headerTitle = AlkkagiText.title
    #endif

    private var headerSubtitle: String {
        #if ALKKAGI_PLAYGROUND
        Self.headerSubtitle
        #else
        isOnline ? AlkkagiText.subtitle : AlkkagiText.practiceSubtitle
        #endif
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(CheckTheme.accent.opacity(0.18))
                Image(systemName: Self.headerIcon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.headerTitle).font(.title3.weight(.bold))
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            Spacer(minLength: 12)
            #if !ALKKAGI_PLAYGROUND
            // 판 중: 판돈 칩(옛 판 — 판돈 없음 — 이면 없음). [게임 목록] 은 없다(닫기는 빨간 점 — DF#48).
            if let stake = onlineStore?.state?.stake {
                ChessStakeChip(stake: stake)
            }
            #endif
            // 소리 단추는 손맛이라 남긴다.
            Button { model.soundEnabled.toggle() } label: {
                Image(systemName: model.soundEnabled ? "speaker.wave.2" : "speaker.slash").frame(width: 22, height: 22)
            }.buttonStyle(.plain).accessibilityLabel(model.soundEnabled ? "소리 끄기" : "소리 켜기")
            #if ALKKAGI_PLAYGROUND
            Picker("감속", selection: Binding(get: { model.game.physics }, set: { model.game.physics = $0 })) {
                Text("A 원래").tag(AlkkagiGame.Physics.ice)
                Text("B 바둑판(정함)").tag(AlkkagiGame.Physics.board)
                Text("C 무겁게").tag(AlkkagiGame.Physics.heavy)
            }.pickerStyle(.segmented).frame(width: 300)
            Toggle("멈칫", isOn: Binding(get: { model.hitStopEnabled }, set: { model.hitStopEnabled = $0 }))
                .toggleStyle(.checkbox)
            #endif
            if !isOnline {
                Button { model.restart() } label: { Label("새 판", systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered).keyboardShortcut("r", modifiers: .command).alkkagiTooltip("새 판 시작 (⌘R)")
                // 연습 판 머리의 돌아오는 단추(§5.2 — 옛 [게임 목록]).
                if let onReturn {
                    #if ALKKAGI_PLAYGROUND
                    Button(action: onReturn) { Label("로비로", systemImage: "chevron.left") }.buttonStyle(.bordered)
                    #else
                    ChessActionButton(title: AlkkagiText.backToLobby, icon: "chevron.left", style: .outline, height: 30,
                                      action: onReturn)
                    #endif
                }
            }
        }
    }

    // MARK: 오른쪽 열

    @ViewBuilder
    private var sidebar: some View {
        #if ALKKAGI_PLAYGROUND
        localSide
        #else
        if let onlineStore, let state = onlineStore.state {
            AlkkagiMatchSide(store: onlineStore, match: state, showsConfirmPreview: previewConfirmResign) {
                VStack(spacing: BoardGameLayout.matchSideSpacing) {
                    playerCard(model.myColor.opponent)
                    playerCard(model.myColor)
                }
            } status: {
                statusCard
            }
        } else {
            localSide
        }
        #endif
    }

    /// 로컬 연습(한 맥 둘이) 오른쪽 열 — 두 카드 · 상태 카드 · 돌 수 카드(대화 카드 자리, D23).
    private var localSide: some View {
        VStack(alignment: .leading, spacing: BoardGameLayout.matchSideSpacing) {
            VStack(spacing: BoardGameLayout.matchSideSpacing) {
                playerCard(model.myColor.opponent)
                playerCard(model.myColor)
            }
            statusCard
                .fixedSize(horizontal: false, vertical: true)
            AlkkagiStoneCountCard(black: model.game.remaining(.black), white: model.game.remaining(.white),
                                  shots: model.game.shotCount)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func playerCard(_ player: AlkkagiGame.Player) -> some View {
        let facts = online
        let currentPlayer = facts?.currentPlayer ?? model.game.currentPlayer
        let finished = facts.map(\.isFinished) ?? (model.game.phase == .finished)
        let simultaneousPlacement = facts?.isPlacing == true
        let concealedLayout = facts?.concealed == true
        let isMe = player == model.myColor
        let ready = isMe ? facts?.myReady == true : facts?.opponentReady == true
        let active = simultaneousPlacement ? !ready : (currentPlayer == player && !finished)
        let peer = player == .black ? facts?.black : facts?.white
        let profile = peer ?? (player == .black ? me : opponent)
        let detail: String
        if concealedLayout && !isMe {
            detail = "\(player.title) 배치 비공개"
        } else {
            detail = model.game.phase == .placing ? "\(player.title) 배치 \(model.game.placedCount(player))/5" : "\(player.title) \(model.game.remaining(player))개"
        }
        let message = AlkkagiGuideText.cardMessage(simultaneousPlacement: simultaneousPlacement, ready: ready, isMe: isMe,
                                                   isOnline: isOnline, active: active,
                                                   placing: model.game.phase == .placing)
        return BoardGamePlayerCard(name: profile.name, stoneColor: player == .black ? .black : .white,
                                   stoneText: detail, isTurn: active, isMe: player == model.myColor) {
            playerPortrait(profile)
        } message: {
            Text(message)
                .font(.caption).foregroundStyle(active ? CheckTheme.working : CheckTheme.secondaryText)
        } clock: {
            if active {
                AlkkagiTurnClock(model: model)
            }
        }
        .frame(height: BoardGameLayout.playerCardHeight)
    }

    @ViewBuilder
    private func playerPortrait(_ profile: AlkkagiPlayerProfile) -> some View {
#if !ALKKAGI_PLAYGROUND
        if let characterID = profile.characterID {
            CharacterPortrait(characterID: characterID)
        } else {
            Image(systemName: "person.crop.circle").resizable().scaledToFit().foregroundStyle(CheckTheme.secondaryText)
        }
#else
        Image(systemName: "person.crop.circle").resizable().scaledToFit().foregroundStyle(CheckTheme.secondaryText)
#endif
    }

    // MARK: 판(§5.9 — 그림은 그대로)

    /// 판은 다른 1:1 판 게임과 같은 칸을 꽉 채운다(제보 #12 '판을 더 크게' — 0.3.80 은 사방 24pt 를 남겨 560pt).
    /// 판 두께(아래 12pt)와 떨어지는 돌은 칸 밖 여백(창 안쪽 20pt)에 그린다.
    private var board: some View {
        playSurface
            .background(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.25))
                        .frame(width: boardSide, height: boardSide + 12)
                    Canvas { context, _ in
                        AlkkagiDrawing.falling(model.falls, context: context, scale: boardSide / AlkkagiGame.boardSize,
                                               origin: CGPoint(x: AlkkagiDrawing.fallMargin, y: AlkkagiDrawing.fallMargin),
                                               reduced: reduceMotion)
                    }
                    .frame(width: boardSide + AlkkagiDrawing.fallMargin * 2, height: boardSide + AlkkagiDrawing.fallMargin * 2)
                    .offset(x: -AlkkagiDrawing.fallMargin, y: -AlkkagiDrawing.fallMargin)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: BoardGameLayout.boardSide, height: BoardGameLayout.boardSide, alignment: .topLeading)
            .offset(shakeOffset)
            .overlay(alignment: .top) { resultBand }
            .overlay { guideOverlay }
    }

    // MARK: 판 위 안내(대표 #d_cjxnVZpLHWw5 C안 — "뭘 하라는건지 모르겠어")

    /// 숨겨 놓기: 판 **가운데 빈 띠**(두 진영 사이 — 돌이 못 오는 곳)에 큰 안내 한 줄.
    /// 쏘기 차례: 손이 내 돌을 뒤로 당기고 날아갈 쪽을 화살로 보여 준다(돌을 잡으면 사라지고, 몇 번 쏘고 나면 더 안 나온다).
    @ViewBuilder
    private var guideOverlay: some View {
        if let hint = model.pullHintStone {
            AlkkagiPullHint(stone: hint, mine: model.guideSide, reduced: reduceMotion)
                .frame(width: boardSide, height: boardSide)
                .allowsHitTesting(false)
        }
        if let text = model.guideBandText {
            Text(text)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .frame(height: 40)
                .background(Capsule().fill(CheckTheme.accent.opacity(0.92)))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                .allowsHitTesting(false)
        }
    }

    private var shakeOffset: CGSize {
        guard !reduceMotion else { return .zero }
        let recoil = model.launchRecoil
        return CGSize(width: sin(model.time * 155) * model.jolt * 3.5 + recoil.x,
                      height: cos(model.time * 183) * model.jolt * 2.6 + recoil.y)
    }

    private var playSurface: some View {
        Canvas { context, size in
            AlkkagiDrawing.board(context: context, size: size)
            let scale = size.width / AlkkagiGame.boardSize
            if model.game.phase == .placing {
                AlkkagiGuideDrawing.zones(context: context, size: size, mine: model.game.currentPlayer)
            }
            for stone in model.game.stones where stone.isPlaced && !stone.isOut {
                AlkkagiDrawing.stone(stone, context: context, scale: scale,
                    selected: stone.id == model.selectedID, pull: model.pull,
                    launch: model.launch, hits: model.hits, trails: !reduceMotion)
            }
            if let selected = model.selectedStone, model.game.phase == .aiming {
                AlkkagiDrawing.aim(stone: selected, pull: model.pull, context: context, scale: scale)
            }
            if model.guideIsMyAim {
                AlkkagiGuideDrawing.myStones(context: context, scale: scale, stones: model.game.stones, mine: model.guideSide)
            }
            if let preview = model.placementPoint, let id = model.dragPlacementID,
               let stone = model.game.stones.first(where: { $0.id == id }) {
                var layer = context
                layer.opacity = 0.65
                AlkkagiDrawing.disc(center: CGPoint(x: preview.x * scale, y: preview.y * scale),
                    radius: AlkkagiGame.stoneRadius * scale, player: stone.owner, context: layer)
                let tint = model.game.canPlace(stoneID: id, at: preview) ? CheckTheme.accent : CheckTheme.danger
                let radius = AlkkagiGame.stoneRadius * scale + 3
                context.stroke(Path(ellipseIn: CGRect(x: preview.x * scale - radius, y: preview.y * scale - radius,
                                                     width: radius * 2, height: radius * 2)), with: .color(tint), lineWidth: 2)
            }
            AlkkagiDrawing.effects(model.hits, context: context, scale: scale, reduced: reduceMotion)
        }
        .frame(width: boardSide, height: boardSide)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 7)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .updating($dragIsActive) { _, active, _ in active = true }
            .onChanged { value in
                let scale = AlkkagiGame.boardSize / boardSide
                model.aim(start: AlkkagiVector(x: value.startLocation.x * scale, y: value.startLocation.y * scale),
                    translation: AlkkagiVector(x: value.translation.width * scale, y: value.translation.height * scale))
            }.onEnded { _ in model.release() })
        .accessibilityLabel("알까기 바둑판")
        .accessibilityValue(model.status)
    }

    /// 끝난 판 위의 얇은 띠(높이 44 · 판 위쪽 · 반투명 · 입력을 막지 않는다 — D21). 온라인은 내 기준 결과, 연습은 승리한 돌.
    @ViewBuilder
    private var resultBand: some View {
        if let band = resultBandText {
            Text(band.title)
                .font(.headline.weight(.bold))
                .foregroundStyle(band.tint)
                .padding(.horizontal, 22)
                .frame(height: 44)
                .background(Capsule().fill(CheckTheme.panelElevated.opacity(0.82)))
                .overlay(Capsule().stroke(band.tint.opacity(0.55), lineWidth: 1))
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
        }
    }

    private var resultBandText: (title: String, tint: Color)? {
        #if !ALKKAGI_PLAYGROUND
        if let onlineStore {
            guard onlineStore.state?.phase == .finished else { return nil }
            let tint: Color = switch onlineStore.outcome {
            case .win?: CheckTheme.working
            case .loss?: CheckTheme.danger
            default: CheckTheme.offWork
            }
            return (AlkkagiText.outcomeTitle(onlineStore.outcome), tint)
        }
        #endif
        guard model.game.phase == .finished else { return nil }
        return (model.resultTitle, CheckTheme.accent)
    }

    // MARK: 상태 카드

    /// 상태 카드: 안내 줄 > 놓친 차례 경고(주황) > 배치/차례 안내(§5.5) · 오른쪽 위 관전자 수 칩(관전 스위치가 꺼지면 숨김 — VC-6).
    /// 배치 중엔 돌 고르기 · [배치 완료] 를 같이 둔다(판 진행 — 그대로).
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(statusHeadline.text).font(.headline)
                    .foregroundStyle(statusHeadline.tint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if model.selectedID != nil {
                    Text("힘 \(Int(model.power * 100))%")
                        .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(CheckTheme.accent)
                }
                #if !ALKKAGI_PLAYGROUND
                if let onlineStore, onlineStore.spectatorFeaturesEnabled {
                    WatcherCountChip(count: onlineStore.spectatorCount, height: 16)
                }
                #endif
            }.frame(minHeight: 20)
            if model.game.phase == .placing {
                HStack(spacing: 12) {
                    ForEach(model.game.stones.filter { $0.owner == model.game.currentPlayer }) { stone in
                        Button { model.placementID = stone.id } label: {
                            AlkkagiStoneSymbol(player: stone.owner).frame(width: 28, height: 28)
                                .opacity(stone.isPlaced ? 0.4 : 1)
                                .padding(3)
                                .overlay(Circle().stroke(model.placementID == stone.id ? CheckTheme.accent : .clear, lineWidth: 2))
                        }.buttonStyle(.plain).disabled(!model.canInteract)
                            .accessibilityLabel("\(stone.owner.title) \(stone.id % 5 + 1)번 돌 선택")
                    }
                    Spacer()
                    Button(placementButtonTitle) { model.confirmPlacement() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.game.placedCount(model.game.currentPlayer) < 5 || !model.canInteract)
                }
                Text(isOnline ? "30초 동안 동시에 배치해요. 둘 다 준비하거나 시간이 끝날 때까지 상대 배치는 보이지 않아요."
                     : "내 영역에 돌 5개를 놓거나 옮겨 주세요. 시간이 끝나면 남은 돌은 자동 배치해요.")
                    .font(.caption2).foregroundStyle(CheckTheme.secondaryText)
            }
        }
        .padding(12)
        // 오목 상태 상자처럼 지금 상태 색으로 칠한다(내 차례 초록 · 기다림 회색 · 경고 주황 — 대표 #d_cjxnVZpLHWw5).
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(CheckTheme.panel.opacity(0.85))
                RoundedRectangle(cornerRadius: 16).fill(statusHeadline.tint.opacity(0.12))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(statusHeadline.tint.opacity(0.45), lineWidth: 1.5))
    }

    private var placementButtonTitle: String {
        #if !ALKKAGI_PLAYGROUND
        if onlineStore?.state?.myReady == true { return "준비 완료" }
        #endif
        return "배치 완료 (\(model.game.placedCount(model.game.currentPlayer))/5)"
    }

    private var statusHeadline: (text: String, tint: Color) {
        #if !ALKKAGI_PLAYGROUND
        if let onlineStore {
            if let notice = onlineStore.notice { return (notice, CheckTheme.pending) }
            if let warning = onlineStore.missedTurnWarning,
               let text = AlkkagiNoticeText.missedTurn(mine: warning.mine, forfeitAfter: warning.forfeitAfter) {
                return (text, CheckTheme.pending)
            }
        }
        #endif
        if let notice = model.notice { return (notice, CheckTheme.pending) }
        #if !ALKKAGI_PLAYGROUND
        if let onlineStore, onlineStore.isMyTurn, onlineStore.state?.phase != .finished {
            return (model.status, CheckTheme.working)
        }
        #endif
        return (model.status, CheckTheme.secondaryText)
    }
}

// MARK: - 차례 시계(잎)

/// 차례 시계 — **잎 뷰**. 남은 초는 이 안의 TimelineView 틱에서만 읽는다(오목 `GomokuTurnClock` 과 같은 꼴).
/// 온라인 판의 남은 초는 `서버 마감 − 서버 보정 시각`이라 관찰 값이 아니다 — 판 화면 본문에서 읽으면 링은 관찰 값이 바뀔 때
/// (판 조회 3초 박자 + 왕복)만 다시 그려져, 초가 3~4초씩 끊겨 줄었다(대표 11-10 "초 줄어드는게 막 3~4초 단위로 끊기면서").
/// 연습 판은 모델이 5Hz 로 판을 나아가게 해(관찰 값) 원래도 매끄럽다 — 같은 잎이 그대로 그린다.
struct AlkkagiTurnClock: View {
    let model: AlkkagiLocalModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: !model.clockTicks)) { _ in
            let remaining = model.remainingSeconds
            BoardGameClockRing(remaining: remaining, duration: 30, tint: AlkkagiLocalModel.clockTint(remaining))
        }
    }
}

// MARK: - 돌 수 카드(§5.5 — 대화 카드 자리 · D23)

/// 판 위에 남은 돌 수와 쏜 횟수(뒤집기 '돌 수 · 수 기록' 카드의 제목 줄 꼴). 온라인은 STATE 값만 쓴다(서버 칸을 더하지 않는다).
struct AlkkagiStoneCountCard: View {
    let black: Int
    let white: Int
    let shots: Int

    static let title = "돌 수"
    static func countsLine(black: Int, white: Int) -> String { "흑 \(black) · 백 \(white)" }
    static func shotsLine(_ shots: Int) -> String { "쏜 횟수 \(shots)번" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                Text(Self.title).font(.headline)
                Spacer(minLength: 4)
                BoardGameStoneDot(color: .black, size: 11)
                BoardGameStoneDot(color: .white, size: 11)
                Text(Self.countsLine(black: black, white: white))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Text(Self.shotsLine(shots))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(CheckTheme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CheckTheme.panel.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}

#if !ALKKAGI_PLAYGROUND
// MARK: - 판 중 오른쪽 열(§5.5) · 결과 카드(§5.6)

/// 온라인 판의 오른쪽 열. 진행 중: 두 카드 · 상태 카드 · 돌 수 카드 · [기권] 줄. 끝남: 두 카드 · 결과 카드 · 돌 수 카드.
/// 기권 가드는 뒤집기·길건너와 같다(`GomokuResignGuard` — 화면이 막 나타난 1초 안의 누름 무시 · 확인 6초 뒤 접힘 ·
/// `.focusable(false)` · 판 id · 창 보임이 바뀌면 다시 잼).
struct AlkkagiMatchSide<Players: View, Status: View>: View {
    let store: AlkkagiOnlineStore
    let match: AlkkagiMatch
    /// 스냅샷 전용 확인 상태. 앱은 false.
    var showsConfirmPreview = false
    @ViewBuilder let players: Players
    @ViewBuilder let status: Status

    @State private var confirmResign = false
    /// 이 화면(이 판)이 나타난 시각 — [기권] 누름 판정의 기준.
    @State private var shownAt: Date?

    private var showsConfirm: Bool { confirmResign || showsConfirmPreview }

    /// 판 위에 남은 돌 수(STATE 값만 — 숨긴 배치 중에도 다섯에서 나간 돌만 뺀다).
    static func remaining(_ match: AlkkagiMatch, _ player: AlkkagiGame.Player) -> Int {
        max(0, 5 - match.stones.filter { $0.owner == player && $0.isOut }.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BoardGameLayout.matchSideSpacing) {
            players
            if match.phase == .finished {
                AlkkagiResultCard(store: store, match: match)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                status
                    .fixedSize(horizontal: false, vertical: true)
            }
            AlkkagiStoneCountCard(black: Self.remaining(match, .black), white: Self.remaining(match, .white),
                                  shots: match.shotCount)
            Spacer(minLength: 0)
            if match.phase != .finished {
                actionRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { shownAt = GomokuResignGuard.clock() }
        .onChange(of: match.id) { _, _ in
            shownAt = GomokuResignGuard.clock()
            confirmResign = false
        }
        .onChange(of: match.phase) { _, _ in confirmResign = false }
        .onChange(of: store.isWindowVisible) { _, visible in
            confirmResign = false
            if visible { shownAt = GomokuResignGuard.clock() }
        }
        // 확인이 아무 선택 없이 오래 서 있으면 스스로 접는다(다음 누름 하나가 곧 기권이 되지 않게).
        .task(id: confirmResign) {
            guard confirmResign else { return }
            try? await Task.sleep(for: .seconds(GomokuResignGuard.confirmTimeout))
            guard !Task.isCancelled else { return }
            confirmResign = false
        }
    }

    /// 확인 단계 경고 줄(판돈 판 "기권하면 판돈을 잃어요" · 옛 판 "기권하면 이번 판은 져요" — VC-17).
    static func resignWarning(stake: Int?) -> String {
        stake == nil ? AlkkagiNoticeText.resignHelp : AlkkagiNoticeText.resignWarning
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(showsConfirm ? Self.resignWarning(stake: match.stake) : AlkkagiText.closeKeepsMatch)
                .font(.caption.weight(showsConfirm ? .bold : .regular))
                .foregroundStyle(showsConfirm ? CheckTheme.danger : CheckTheme.secondaryText)
                .lineLimit(1)
            if showsConfirm {
                HStack(spacing: 8) {
                    ChessActionButton(title: AlkkagiNoticeText.confirmResign, icon: "flag.fill", tint: CheckTheme.danger,
                                      height: 34, fullWidth: true, isEnabled: !store.isBusy) {
                        confirmResign = false
                        Task { await store.resign() }
                    }
                    // 스페이스·↩ 로 눌리지 않는다 — 키보드 탐색이 켜진 맥에서 다른 키가 기권이 되면 안 된다.
                    .focusable(false)
                    ChessActionButton(title: AlkkagiNoticeText.keepPlaying, tint: CheckTheme.offWork, style: .outline,
                                      height: 34, fullWidth: true) {
                        confirmResign = false
                    }
                    .focusable(false)
                }
            } else {
                ChessActionButton(title: AlkkagiNoticeText.resign, icon: "flag", tint: CheckTheme.danger, style: .outline,
                                  height: 34, fullWidth: true, isEnabled: !store.isBusy) {
                    // 화면이 막 나타난 직후의 누름(로비 [수락] 더블클릭의 두 번째 누름)은 이 화면을 보고 누른 것이 아니다.
                    guard GomokuResignGuard.acceptsTap(shownAt: shownAt, now: GomokuResignGuard.clock()) else { return }
                    confirmResign = true
                }
                .focusable(false)
                .checkTooltip(Self.resignWarning(stake: match.stake))
            }
        }
    }
}

/// 결과 카드(= `ReversiResultCard` 꼴 — §5.6): 아이콘(승 trophy 초록 · 패 xmark 빨강 · 무 equal 회색) · 제목 · 사유 ·
/// "쏜 횟수 N번" · 루비 줄("+N"/"−N"/"0 · 판돈을 돌려받았어요" — 옛 판이면 없음) · 카드 안 [로비로] **한 번**.
struct AlkkagiResultCard: View {
    let store: AlkkagiOnlineStore
    let match: AlkkagiMatch

    private var outcome: AlkkagiOutcome? { store.outcome }

    private var tint: Color {
        switch outcome {
        case .win?: return CheckTheme.working
        case .loss?: return CheckTheme.danger
        default: return CheckTheme.offWork
        }
    }

    private var icon: String {
        switch outcome {
        case .win?: return "trophy.fill"
        case .loss?: return "xmark.circle.fill"
        default: return "equal.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AlkkagiText.outcomeTitle(outcome))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(tint)
                    Text(AlkkagiNoticeText.endReason(store.endReason, outcome: outcome))
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if let delta = store.rubyDelta {
                    HStack(spacing: 4) {
                        RubyIcon(size: 18)
                        Text(AlkkagiText.rubyLine(delta))
                            .font(delta == 0 ? .callout.weight(.bold) : .title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(delta > 0 ? CheckTheme.working
                                             : (delta < 0 ? CheckTheme.danger : CheckTheme.secondaryText))
                            .lineLimit(1)
                    }
                }
            }
            Text(AlkkagiStoneCountCard.shotsLine(match.shotCount))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            ChessActionButton(title: AlkkagiText.backToLobby, icon: "chevron.left", style: .outline,
                              height: 32, fullWidth: true) { store.backToLobby() }
                .focusable(false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chessCard()
    }
}
#endif

private struct AlkkagiStoneSymbol: View {
    let player: AlkkagiGame.Player
    var body: some View {
        Canvas { context, size in
            AlkkagiDrawing.disc(center: CGPoint(x: size.width / 2, y: size.height / 2),
                               radius: size.width * 0.43, player: player, context: context)
        }
    }
}

/// 판 중 대화 카드(0.3.80 모양). 판 화면에서는 뺐다(§0 #11 · VC-10 · D23) — 되살릴 때 돌 수 카드 아래에 다시 넣는다.
/// 결재 카드 '알림' 렌더(0.3.80 모양)가 이 부품을 그대로 그린다.
@MainActor
struct AlkkagiChatPanel: View {
    @Bindable var model: AlkkagiLocalModel
    @State private var editorRenderedEmpty: Bool?

    var body: some View {
        BoardGameChatCard {
            HStack {
                Text("대화").font(.subheadline.weight(.bold))
                Spacer()
                Text(model.isOnline ? "대결 대화" : "로컬 대화").font(.caption2).foregroundStyle(CheckTheme.secondaryText)
                Button { model.toggleChatMute() } label: {
                    Image(systemName: model.chatMuted ? "bell.slash.fill" : "bell.fill")
                }.buttonStyle(.plain).alkkagiTooltip("상대 말 숨기기")
            }
            if !model.isOnline {
                Picker("지금 말하는 돌", selection: $model.chatSender) {
                    Text("흑돌").tag(AlkkagiGame.Player.black)
                    Text("백돌").tag(AlkkagiGame.Player.white)
                }.pickerStyle(.segmented)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if model.messages.isEmpty {
                            Text("아직 나눈 말이 없어요").font(.caption).foregroundStyle(CheckTheme.secondaryText).padding(.top, 20)
                        }
                        ForEach(model.messages) { message in
                            if let sender = message.sender {
                                if !model.chatMuted || sender == model.chatSender {
                                    BoardGameChatBubble(body: message.body, isMine: sender == model.chatSender,
                                        oppositeInset: 56, accent: CheckTheme.accent, primaryText: CheckTheme.primaryText)
                                        .id(message.id)
                                }
                            } else {
                                Text(message.body).font(.caption2).foregroundStyle(CheckTheme.secondaryText)
                                    .frame(maxWidth: .infinity).padding(.vertical, 4).id(message.id)
                            }
                        }
                    }.frame(maxWidth: .infinity)
                }
                .onChange(of: model.messages.last?.id) { _, _ in
                    if let id = model.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4), spacing: 5) {
                ForEach(GomokuQuickPhrase.allCases, id: \.rawValue) { phrase in
                    Button { model.sendQuick(phrase) } label: {
                        Text(phrase.text).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                            .foregroundStyle(CheckTheme.primaryText).frame(maxWidth: .infinity).frame(height: 24)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(CheckTheme.border))
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10).fill(CheckTheme.fieldFill)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CheckTheme.border))
                    if CheckEditorPlaceholder.isVisible(storeText: model.chatDraft, editorRenderedEmpty: editorRenderedEmpty) {
                        Text("메시지 입력 · ↩ 전송").font(.caption).foregroundStyle(CheckTheme.secondaryText)
                            .padding(.horizontal, CheckEditorMetrics.inset.width).padding(.vertical, CheckEditorMetrics.inset.height)
                    }
                    CheckTextEditor(text: $model.chatDraft, sendsOnReturn: true,
                        canSendNow: { model.canSendChat }, onSend: send,
                        onRenderedEmptyChange: { editorRenderedEmpty = $0 })
                }.frame(height: 40)
                Button(action: send) {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill").font(.system(size: 10, weight: .bold))
                        Text("보내기").font(.caption.weight(.bold))
                    }.foregroundStyle(.white).frame(width: 68, height: 32)
                }
                    .buttonStyle(.plain).background(CheckTheme.accent.opacity(model.canSendChat ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 10))
                    .disabled(!model.canSendChat).keyboardShortcut(.return, modifiers: .command).accessibilityLabel("보내기")
            }
            if model.chatLength >= 80 {
                Text("\(model.chatLength)/100").font(.caption2).foregroundStyle(model.chatLength > 100 ? CheckTheme.danger : CheckTheme.secondaryText)
            }
        }
    }
    private func send() { CheckEditorSend.commitThenSend { model.sendChat() } }
}

@MainActor
@Observable
final class AlkkagiLocalModel {
    var game = AlkkagiGame()
    var selectedID: Int?
    var pull = AlkkagiVector(x: 0, y: 0)
    var placementID: Int? = 0
    var dragPlacementID: Int?
    var placementPoint: AlkkagiVector?
    var notice: String?
    fileprivate var hits: [AlkkagiHit] = []
    fileprivate var falls: [AlkkagiFall] = []
    fileprivate var launch: AlkkagiLaunch?
    var time = 0.0
    var jolt = 0.0
    var soundEnabled = true
    var chatDraft = ""
    var chatSender: AlkkagiGame.Player = .black
    var chatMuted = false
    #if !ALKKAGI_PLAYGROUND
    /// 온라인 판(앱만 — 독립 실행기는 로컬 연습만, SPEC §5.10).
    var onlineStore: AlkkagiOnlineStore?
    #endif
    fileprivate var messages: [AlkkagiLocalMessage] = []
    @ObservationIgnored private var lastTime: TimeInterval?
    @ObservationIgnored private var clockTime = 0.0
    @ObservationIgnored private let feedback = AlkkagiFeedback()
    /// 렌더 시험 전용 — 울린 소리(세기 · 판 밖 · 가로 위치)를 엿듣는다. 앱은 nil.
    @ObservationIgnored var soundTap: ((Double, AlkkagiFeedback.Kind, Double) -> Void)?
    @ObservationIgnored private var powerBand = 0
    @ObservationIgnored private var messageSequence = 0
    @ObservationIgnored private var gestureIsActive = false
    @ObservationIgnored private var ignoresCurrentGesture = false
    @ObservationIgnored private var onlineRevision = -1
    @ObservationIgnored private var onlineMatchID: String?
    @ObservationIgnored private var onlineChatSeq = -1
    @ObservationIgnored private var onlineReplayElapsed = 0.0
    /// 온라인 굴림 재생(제보 #9 '버벅임'): 이 판에서 **화면 시계로** 되살리는 쏘기 id(쏜 사람은 내 예측 id = 서버 shot id).
    /// 굴림은 매 프레임 화면 걸음(dt)으로 나아간다 — 0.3.80 은 프레임마다 서버 시각(응답마다 다시 잰 시계 차)에 맞춰 그려,
    /// 받는 사람은 쏜 순간 0.2~0.5초를 건너뛰고(순간이동), 시계 차가 흔들리면 멈칫 · 건너뜀이 났다.
    /// 서버 시각은 **뒤처짐**만 잰다 — 뒤처졌으면 최대 1.5배로 따라잡고(앞서면 그대로), 끝난 판이 먼저 와도 남은 굴림을
    /// 2배로 마저 굴린 뒤 받는다. 결과 자리는 서버와 같은 물리라 그대로 이어진다.
    @ObservationIgnored private var replayShotID: String?
    /// 굴림이 끝나기 전에 온 '굴림 뒤' 판(revision) — 남은 굴림을 마저 굴린 뒤 받는다.
    @ObservationIgnored private var deferredRevision: Int?
    /// 멈칫(히트스톱): 세게 부딪힌 순간 시뮬레이션을 아주 잠깐 세운다. 남은 멈춤 초.
    @ObservationIgnored private var hitStop = 0.0
    /// 이번 한 수에 쓴 멈춤 합(상한 `maxHitStopPerShot` — 연쇄 충돌이 판을 끌지 않게).
    @ObservationIgnored private var hitStopSpent = 0.0
    var hitStopEnabled = true
    static let maxHitStopPerShot = 0.16
    /// 서버보다 이만큼(초)까지 뒤처진 굴림은 처음부터 보여 주며 따라잡는다. 넘는 만큼만 소리 없이 건너뛴다(신호를 놓쳐 늦게 안 판).
    static let maxReplayLag = 0.6
    /// 뒤처졌을 때 더 도는 비율(0.5 = 1.5배).
    static let replayCatchUpRate = 0.5
    /// 끝난 판이 먼저 왔을 때 마저 굴리는 비율(1.0 = 2배)과 그렇게 기다려 줄 남은 굴림 상한(초).
    static let replayDrainRate = 1.0
    static let maxReplayDrain = 1.2

    #if ALKKAGI_PLAYGROUND
    var isOnline: Bool { false }
    var myColor: AlkkagiGame.Player { .black }
    var canInteract: Bool { true }
    #else
    var isOnline: Bool { onlineStore != nil }
    var myColor: AlkkagiGame.Player { onlineStore?.state?.myColor ?? .black }
    var canInteract: Bool { onlineStore.map { $0.canPlace || $0.canShoot } ?? true }
    #endif
    var selectedStone: AlkkagiGame.Stone? { game.stones.first { $0.id == selectedID && $0.isPlaced && !$0.isOut } }
    var power: Double { min(1, pull.length / AlkkagiGame.maxPull) }
    var remainingSeconds: Double {
        #if !ALKKAGI_PLAYGROUND
        if let onlineStore { return onlineStore.remainingSeconds }
        #endif
        return game.phase == .placing ? game.placementRemaining : game.turnRemaining
    }
    static func clockTint(_ remaining: Double) -> Color {
        remaining <= 5 ? CheckTheme.danger : (remaining <= 10 ? CheckTheme.pending : CheckTheme.working)
    }
    /// 차례 시계(`AlkkagiTurnClock`)의 TimelineView 를 돌릴지 — 온라인 판은 서버 시각으로 흐르니 창이 보일 때만 돈다.
    /// 연습 판은 모델 틱(5Hz)이 판을 바꿔 다시 그리니 돌릴 필요가 없다.
    var clockTicks: Bool {
        #if !ALKKAGI_PLAYGROUND
        if let onlineStore { return onlineStore.isWindowVisible }
        #endif
        return false
    }
    var launchRecoil: AlkkagiVector {
        guard let launch else { return AlkkagiVector(x: 0, y: 0) }
        return launch.direction * (-sin(launch.age * 38) * exp(-launch.age * 17) * launch.power * 6)
    }
    // MARK: 안내(대표 #d_cjxnVZpLHWw5 C안)

    /// 손 안내를 몇 번 쏠 때까지 보여 주나(이 기기에서 쏜 횟수 — 익숙해지면 사라진다).
    static let pullHintShotLimit = 3
    static let pullHintShotsKey = "check.alkkagi.pullHintShots"
    /// 손 안내 횟수를 기억할 곳. 앱은 창이 `.standard` 를 넣고(`AlkkagiGameView.guideDefaults`), 시험은 시험 전용 스위트를 넣는다.
    /// nil 이면 이 판에서만 센다(표준 스위트에 쓰지 않는다 — 시험 잔재 사고, PreferencesLeakGateTests).
    @ObservationIgnored var guideDefaults: UserDefaults? {
        didSet { pullHintShots = guideDefaults?.integer(forKey: Self.pullHintShotsKey) ?? pullHintShots }
    }
    /// 손 안내를 본 채로 쏜 횟수.
    private(set) var pullHintShots = 0

    /// 숨겨 놓기에서 내가 아직 준비 전인가.
    var guideIsMyPlacing: Bool {
        guard game.phase == .placing else { return false }
        #if !ALKKAGI_PLAYGROUND
        if let onlineStore { return onlineStore.state?.myReady == false }
        #endif
        return true
    }

    /// 쏘기 차례가 나고 아직 돌을 안 잡았는가.
    var guideIsMyAim: Bool {
        guard game.phase == .aiming, selectedID == nil else { return false }
        #if !ALKKAGI_PLAYGROUND
        if let onlineStore { return onlineStore.isMyTurn }
        #endif
        return true
    }

    /// 손 안내를 붙일 내 돌(판 가운데에 가장 가까운 돌) — 안내가 필요 없으면 nil.
    var pullHintStone: AlkkagiGame.Stone? {
        guard guideIsMyAim, pullHintShots < Self.pullHintShotLimit else { return nil }
        return AlkkagiGuideDrawing.hintStone(game.stones, mine: guideSide)
    }

    /// 안내가 가리키는 쪽 — 온라인은 나, 연습 판(한 맥 둘이)은 지금 차례인 쪽.
    var guideSide: AlkkagiGame.Player { isOnline ? myColor : game.currentPlayer }

    var guideBandText: String? {
        guard guideIsMyPlacing else { return nil }
        return AlkkagiGuideText.band(side: game.currentPlayer, placed: game.placedCount(game.currentPlayer))
    }

    /// 쐈다 — 손 안내를 보던 중이면 한 번 센다.
    private func countPullHintShot(hinted: Bool) {
        guard hinted, pullHintShots < Self.pullHintShotLimit else { return }
        pullHintShots += 1
        guideDefaults?.set(pullHintShots, forKey: Self.pullHintShotsKey)
    }

    var status: String {
        #if !ALKKAGI_PLAYGROUND
        if let onlineStore, let state = onlineStore.state {
            if onlineStore.isBusy { return "잠시만 기다려 주세요" }
            if state.phase == .finished { return AlkkagiText.outcomeTitle(onlineStore.outcome) }
            if state.phase == .rolling { return "돌이 멈추면 차례가 바뀌어요" }
            if state.phase == .placing {
                return state.myReady ? AlkkagiGuideText.placedWaiting
                    : AlkkagiGuideText.placing(side: state.myColor, placed: game.placedCount(state.myColor), player: nil)
            }
            if !onlineStore.isMyTurn {
                let peer = state.currentPlayer == .black ? state.black : state.white
                return AlkkagiGuideText.opponentTurn(peer.displayName)
            }
        }
        #endif
        // 연습 판(한 맥 둘이)은 흑 · 백을 글에 넣는다. 온라인은 늘 '나'.
        let player: AlkkagiGame.Player? = isOnline ? nil : game.currentPlayer
        return switch game.phase {
        case .placing: AlkkagiGuideText.placing(side: game.currentPlayer, placed: game.placedCount(game.currentPlayer), player: player)
        // 판의 첫 수(흑)는 힘이 60%까지(선후 맞춤) — 연습 판 · 온라인 판 같은 안내.
        case .aiming: AlkkagiGuideText.aiming(player: player, holding: selectedID != nil, firstShotLimited: game.isFirstShotLimited)
        case .rolling: "돌이 멈추면 차례가 바뀌어요"
        case .finished: resultTitle
        }
    }
    var resultTitle: String {
        switch game.result {
        case .winner(let player): "\(player.title) 승리!"
        case .draw: "멋진 한 판, 무승부!"
        case nil: "한 판 끝!"
        }
    }
    var canSendChat: Bool {
        let text = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        #if !ALKKAGI_PLAYGROUND
        if onlineStore?.isSendingChat == true { return false }
        #endif
        return !text.isEmpty && text.unicodeScalars.count <= 100
    }
    var chatLength: Int { chatDraft.unicodeScalars.count }
    func sendChat() {
        guard canSendChat else { return }
        #if !ALKKAGI_PLAYGROUND
        if let onlineStore {
            let draft = chatDraft
            let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let previous = onlineStore.chat.last?.seq ?? 0
            let myID = myColor == .black ? onlineStore.state?.black.id : onlineStore.state?.white.id
            Task { [weak self] in
                await onlineStore.sendChat(body: body)
                guard let self else { return }
                if self.chatDraft == draft,
                   onlineStore.chat.contains(where: { $0.seq > previous && $0.body == body && $0.senderID == myID }) {
                    self.chatDraft = ""
                }
                self.synchronizeOnline()
            }
            return
        }
        #endif
        appendMessage(chatDraft.trimmingCharacters(in: .whitespacesAndNewlines), sender: chatSender)
        chatDraft = ""
    }
    func sendQuick(_ phrase: GomokuQuickPhrase) {
        #if !ALKKAGI_PLAYGROUND
        if let onlineStore {
            Task { [weak self] in await onlineStore.sendChat(body: phrase.text); self?.synchronizeOnline() }
            return
        }
        #endif
        appendMessage(phrase.text, sender: chatSender)
    }
    func toggleChatMute() {
        #if !ALKKAGI_PLAYGROUND
        if let onlineStore {
            let muted = !chatMuted
            Task { [weak self] in await onlineStore.setMuted(muted); self?.synchronizeOnline() }
            return
        }
        #endif
        chatMuted.toggle()
    }
    private func appendMessage(_ body: String, sender: AlkkagiGame.Player?) {
        messageSequence += 1
        messages.append(AlkkagiLocalMessage(id: messageSequence, sender: sender, body: body))
        if messages.count > 64 { messages.removeFirst(messages.count - 64) }
    }

    func aim(start: AlkkagiVector, translation: AlkkagiVector) {
        gestureIsActive = true
        guard !ignoresCurrentGesture, canInteract else { return }
        if game.phase == .placing {
            if dragPlacementID == nil {
                dragPlacementID = game.stones.first {
                    $0.owner == game.currentPlayer && $0.isPlaced && !$0.isOut && ($0.position - start).length < AlkkagiGame.stoneRadius * 1.4
                }?.id ?? placementID ?? game.stones.first { $0.owner == game.currentPlayer && !$0.isPlaced }?.id
            }
            guard dragPlacementID != nil else { return }
            placementPoint = start + translation
            notice = nil
            return
        }
        guard game.phase == .aiming else { return }
        if selectedID == nil {
            selectedID = game.stones.first {
                $0.isPlaced && !$0.isOut && $0.owner == game.currentPlayer && ($0.position - start).length < AlkkagiGame.stoneRadius * 1.5
            }?.id
            if selectedID != nil { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
        }
        guard selectedID != nil else { return }
        // 판의 첫 수(흑)는 화살이 60%(당김 81)에서 멈춘다 — 서버도 같은 값으로 줄여 저장한다.
        let limit = game.shotPullLimit
        pull = translation.length > limit ? translation * (limit / translation.length) : translation
        let band = Int(power * 4)
        if band > powerBand { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        powerBand = band
    }
    func release() {
        defer { finishGesture() }
        guard !ignoresCurrentGesture, canInteract else { return }
        if game.phase == .placing {
            guard let id = dragPlacementID, let at = placementPoint else { return }
            #if !ALKKAGI_PLAYGROUND
            if let onlineStore {
                guard game.canPlace(stoneID: id, at: at) else {
                    notice = AlkkagiGuideText.placeRejected
                    return
                }
                Task { [weak self] in await onlineStore.place(stoneID: id, at: at); self?.synchronizeOnline(force: true) }
                return
            }
            #endif
            if game.placeStone(stoneID: id, at: at) {
                placementID = game.stones.first { $0.owner == game.currentPlayer && !$0.isPlaced }?.id
                notice = nil
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            } else {
                notice = AlkkagiGuideText.placeRejected
            }
            return
        }
        guard let id = selectedID, let stone = selectedStone else { return }
        let shotPull = pull
        let actionID = UUID()
        // 손 안내를 보던 차례였나(돌을 잡기 전 — 잡으면 안내는 사라진다). 쏜 뒤 한 번 센다.
        let hinted = pullHintShots < Self.pullHintShotLimit
        if game.shoot(stoneID: id, pull: pull) {
            countPullHintShot(hinted: hinted)
            launch = AlkkagiLaunch(stoneID: id, direction: pull * (-1 / pull.length), power: power)
            hitStop = 0; hitStopSpent = 0
            if soundEnabled { feedback.play(strength: 0.3 + power * 0.6, kind: .flick, horizontal: stone.position.x) }
            soundTap?(0.3 + power * 0.6, .flick, stone.position.x)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            #if !ALKKAGI_PLAYGROUND
            if let onlineStore {
                replayShotID = actionID.uuidString
                deferredRevision = nil
                onlineReplayElapsed = 0
                Task { [weak self] in
                    await onlineStore.shoot(stoneID: id, pull: shotPull, actionID: actionID)
                    self?.synchronizeOnline(force: true)
                }
            }
            #endif
        }
    }
    func cancelAim() {
        if gestureIsActive { ignoresCurrentGesture = true }
        selectedID = nil; pull = AlkkagiVector(x: 0, y: 0); powerBand = 0
        dragPlacementID = nil; placementPoint = nil
    }
    func finishGesture() {
        cancelAim()
        gestureIsActive = false
        ignoresCurrentGesture = false
    }
    func confirmPlacement() {
        #if !ALKKAGI_PLAYGROUND
        if let onlineStore {
            Task { [weak self] in await onlineStore.confirmPlacement(); self?.synchronizeOnline(force: true) }
            return
        }
        #endif
        let old = game
        if game.confirmPlacement() { changed(from: old) }
    }
    func restart() {
        #if !ALKKAGI_PLAYGROUND
        if let onlineStore {
            Task { await onlineStore.leaveFinishedMatch() }
            return
        }
        #endif
        let physics = game.physics   // 새 판도 고른 감속 그대로(독립 실행기의 시안 고르기)
        game.reset(); game.physics = physics; cancelAim(); placementID = 0; notice = nil
        hits = []; falls = []; launch = nil; jolt = 0; lastTime = nil; clockTime = 0
        messages = []; chatDraft = ""; chatSender = .black; messageSequence = 0
    }
    private func changed(from old: AlkkagiGame) {
        guard !isOnline else { return }
        guard old.phase != game.phase || old.currentPlayer != game.currentPlayer else { return }
        cancelAim(); notice = nil; clockTime = 0
        chatSender = game.currentPlayer
        if old.phase == .placing {
            placementID = game.stones.first { $0.owner == game.currentPlayer && !$0.isPlaced }?.id
            if game.phase == .aiming {
                appendMessage("배치를 마쳤어요. 흑돌부터 시작해요!", sender: nil)
            } else {
                appendMessage("\(game.currentPlayer.title) 배치 차례예요", sender: nil)
            }
        } else if old.phase == .aiming && game.phase == .aiming && old.shotCount == game.shotCount {
            appendMessage("\(old.currentPlayer.title)의 시간이 끝나 차례를 넘겼어요", sender: nil)
        }
    }
    func tick(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        defer { lastTime = now }
        guard let lastTime else { return }
        let elapsed = max(0, now - lastTime)
        let dt = min(1.0 / 20, elapsed)
        // 멈칫 중이면 굴림 시간이 흐르지 않는다(효과 나이도 멈춘다 — 흔들림만 계속). 온라인은 멈춘 만큼 서버보다 뒤처지고,
        // 멈춤이 끝나면 뒤처짐 따라잡기(1.5배)가 갚는다.
        var rollDt = dt
        let frozen = hitStop > 0
        if frozen {
            let used = min(hitStop, dt)
            hitStop -= used
            rollDt = dt - used
        }
        var impacts: [AlkkagiGame.Impact] = []
        let old = game
        #if !ALKKAGI_PLAYGROUND
        let onlineStore = self.onlineStore
        #endif
        if isOnline {
            #if !ALKKAGI_PLAYGROUND
            guard let onlineStore else { return }
            synchronizeOnline()
            if game.phase == .rolling, replayShotID != nil {
                var step = rollDt
                if !frozen {
                    if let behind = replayLag(onlineStore) {
                        if behind > Self.maxReplayLag {
                            // 신호를 놓쳐 아주 늦게 안 판 — 넘는 만큼만 소리 · 효과 없이 건너뛴다.
                            _ = advanceReplay(by: behind - Self.maxReplayLag)
                        }
                        if behind > 0.001 { step += min(behind, dt * Self.replayCatchUpRate) }
                    } else if deferredRevision != nil {
                        step += dt * Self.replayDrainRate
                    }
                }
                if step > 0 { impacts = advanceReplay(by: step) }
                if game.phase != .rolling, deferredRevision != nil {
                    deferredRevision = nil
                    synchronizeOnline(force: true)
                }
            }
            #endif
        } else if game.phase == .placing || game.phase == .aiming {
            // 초 단위 UI는 오목과 같이 5Hz로만 갱신한다. 창 밖을 눌러도 제한 시간은 흐른다.
            clockTime += elapsed
            if clockTime >= 0.2 {
                let deadlineExpired = clockTime + 1e-9 >= remainingSeconds
                impacts = game.advance(dt: clockTime)
                clockTime = 0
                if deadlineExpired { cancelAim() }
            }
        } else if game.phase == .rolling, rollDt > 0 {
            impacts = game.advance(dt: rollDt)
        }
        changed(from: old)
        guard !hits.isEmpty || !falls.isEmpty || launch != nil || !impacts.isEmpty || jolt > 0 else { return }
        time += dt
        let ageDt = frozen ? 0 : dt
        if var released = launch { released.age += ageDt; launch = released.age < 0.3 ? released : nil }
        hits = hits.compactMap { var h = $0; h.age += ageDt; return h.age < 0.32 ? h : nil }
        falls = falls.compactMap { var f = $0; f.age += ageDt; return f.age < 0.9 ? f : nil }
        jolt = max(0, jolt - dt * 9)
        for impact in impacts where impact.strength > 0.08 {
            hits.append(AlkkagiHit(position: impact.position, strength: impact.strength, ringOut: impact.isRingOut))
        }
        for stone in game.stones where stone.isOut && old.stones.first(where: { $0.id == stone.id })?.isOut == false {
            let p = stone.position
            let outward = AlkkagiVector(x: p.x < 0 ? -1 : (p.x > AlkkagiGame.boardSize ? 1 : 0),
                                        y: p.y < 0 ? -1 : (p.y > AlkkagiGame.boardSize ? 1 : 0))
            let edge = AlkkagiVector(x: min(AlkkagiGame.boardSize, max(0, p.x)), y: min(AlkkagiGame.boardSize, max(0, p.y)))
            falls.append(AlkkagiFall(position: edge, owner: stone.owner, outward: outward))
        }
        if let impact = impacts.max(by: { $0.strength < $1.strength }), impact.strength > 0.12 {
            jolt = max(jolt, pow(impact.strength, 1.3))
            // 멈칫: 돌끼리 세게(0.3 넘게) 맞은 순간만 — 판 밖으로 나가는 순간 · 약한 스침은 멈추지 않는다. 세기에 비례(30~75ms).
            if hitStopEnabled, !impact.isRingOut, impact.strength > 0.3, hitStopSpent < Self.maxHitStopPerShot {
                let stop = min(Self.maxHitStopPerShot - hitStopSpent, 0.03 + 0.05 * min(1, impact.strength))
                hitStop = max(hitStop, stop)
                hitStopSpent += stop
            }
            if soundEnabled { feedback.play(strength: impact.strength, kind: impact.isRingOut ? .ringOut : .hit, horizontal: impact.position.x) }
            soundTap?(impact.strength, impact.isRingOut ? .ringOut : .hit, impact.position.x)
            if impact.strength > 0.35 { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
        }
    }

    #if !ALKKAGI_PLAYGROUND
    /// 서버 굴림 시각보다 내 화면 굴림이 뒤처진 초(앞서면 음수). 서버가 같은 쏘기를 굴리는 중일 때만 — 아니면 nil.
    private func replayLag(_ store: AlkkagiOnlineStore) -> Double? {
        guard let state = store.state, state.phase == .rolling, let shot = state.shot,
              replayShotID?.caseInsensitiveCompare(shot.id) == .orderedSame, shot.startedAtMs.isFinite else { return nil }
        let serverElapsed = min(shot.duration, max(0, (store.estimatedServerNowMs - shot.startedAtMs) / 1_000))
        let lag = serverElapsed - onlineReplayElapsed
        return lag.isFinite ? lag : nil
    }

    /// 화면 굴림을 `seconds` 만큼 나아가게 한다(0.25초 조각 — 판 진행의 한 번 상한).
    private func advanceReplay(by seconds: Double) -> [AlkkagiGame.Impact] {
        var impacts: [AlkkagiGame.Impact] = []
        var remaining = seconds
        while remaining > 1e-9 && game.phase == .rolling {
            let slice = min(0.25, remaining)
            impacts += game.advance(dt: slice)
            remaining -= slice
            onlineReplayElapsed += slice
        }
        return impacts
    }

    func attachOnline(_ store: AlkkagiOnlineStore?) {
        guard let store else { return }
        onlineStore = store
        synchronizeOnline(force: true)
    }

    private func synchronizeOnline(force: Bool = false) {
        guard let onlineStore, let state = onlineStore.state else { return }
        chatSender = state.myColor
        chatMuted = state.muted
        if onlineMatchID != state.id || onlineChatSeq != state.chatSeq {
            messages = onlineStore.chat.map { message in
                AlkkagiLocalMessage(id: message.seq, sender: message.senderID == state.black.id ? .black : .white, body: message.body)
            }
            onlineChatSeq = state.chatSeq
        }
        guard force || onlineMatchID != state.id || onlineRevision != state.revision else { return }
        // 굴림 뒤 판이 내 굴림보다 먼저 왔다(받는 사람이 따라잡는 중 · 쏜 사람 응답이 늦음) — 같은 쏘기를 마저 굴린 뒤 받는다.
        // 남은 굴림이 길면(`maxReplayDrain` 초 넘게) 기다리지 않고 바로 받는다.
        if state.phase != .rolling, onlineMatchID == state.id, game.phase == .rolling, replayShotID != nil,
           game.shotCount == state.shotCount {
            if deferredRevision == state.revision { return }
            var probe = game
            var left = Self.maxReplayDrain
            while probe.phase == .rolling && left > 0 { _ = probe.advance(dt: 0.25); left -= 0.25 }
            if probe.phase != .rolling {
                deferredRevision = state.revision
                return
            }
        }
        deferredRevision = nil
        // The other player's concealed placement must not interrupt my drag.
        if !force, onlineMatchID == state.id, state.phase == .placing, !state.myReady,
           game.phase == .placing, game.currentPlayer == state.myColor, game.stones == state.stones {
            onlineRevision = state.revision
            return
        }
        cancelAim()
        notice = nil
        // 같은 쏘기를 이미 되살리는 중이면(쏜 사람의 예측 · 굴림 중 revision 만 바뀜) 처음부터 다시 굴리지 않는다.
        let keepsReplay = state.phase == .rolling
            && replayShotID?.caseInsensitiveCompare(state.shot?.id ?? "") == .orderedSame
            && game.shotCount == state.shotCount
        if state.phase == .rolling, !keepsReplay, let replay = state.shotReplayGame {
            game = replay
            replayShotID = state.shot?.id
            onlineReplayElapsed = 0
        } else if !keepsReplay, let canonical = state.canonicalGame(serverNowMs: onlineStore.estimatedServerNowMs) {
            game = canonical
            if state.phase != .rolling { replayShotID = nil }
            onlineReplayElapsed = 0
        }
        onlineMatchID = state.id
        onlineRevision = state.revision
        placementID = game.stones.first { $0.owner == state.myColor && !$0.isPlaced }?.id
    }
    #endif
}

private struct AlkkagiLocalMessage: Identifiable { let id: Int; let sender: AlkkagiGame.Player?; let body: String }
struct AlkkagiHit { let position: AlkkagiVector; let strength: Double; let ringOut: Bool; var age = 0.0 }
struct AlkkagiFall { let position: AlkkagiVector; let owner: AlkkagiGame.Player; let outward: AlkkagiVector; var age = 0.0 }
struct AlkkagiLaunch { let stoneID: Int; let direction: AlkkagiVector; let power: Double; var age = 0.0 }

/// 판 그림(§5.9 — 그대로). 관전 화면(`AlkkagiSpectateView`)도 같은 그림을 쓴다.
enum AlkkagiDrawing {
    /// 판 한 변(pt) — 판 게임 칸 그대로(뒤집기 · 오목과 같은 608). 0.3.80 은 칸 − 48(560).
    static var boardSide: CGFloat { BoardGameLayout.boardSide }
    /// 떨어지는 돌을 판 밖으로 그릴 여백(창 안쪽 여백 20pt 안).
    static let fallMargin: CGFloat = 20

    static func board(context: GraphicsContext, size: CGSize) {
        var layer = context
        let inset = size.width * 0.06
        let cell = (size.width - inset * 2) / 14
        let stars = [(3, 3), (11, 3), (7, 7), (3, 11), (11, 11)].map {
            CGPoint(x: inset + CGFloat($0.0) * cell, y: inset + CGFloat($0.1) * cell)
        }
        BoardGameDrawing.drawBoard(&layer, side: size.width, inset: inset, lines: 15, stars: stars)
    }

    static func stone(_ stone: AlkkagiGame.Stone, context: GraphicsContext, scale: Double,
                      selected: Bool, pull: AlkkagiVector, launch: AlkkagiLaunch?, hits: [AlkkagiHit], trails: Bool) {
        let point = CGPoint(x: stone.position.x * scale, y: stone.position.y * scale)
        let radius = AlkkagiGame.stoneRadius * scale
        if trails, stone.velocity.length > 130 {
            for i in (1...3).reversed() {
                let lag = Double(i) * 0.009
                let p = CGPoint(x: point.x - stone.velocity.x * scale * lag, y: point.y - stone.velocity.y * scale * lag)
                context.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                             with: .color(stone.owner.color.opacity(0.035 * Double(4 - i))))
            }
        }
        var squash = selected ? min(1, pull.length / AlkkagiGame.maxPull) * 0.09 : 0
        var angle = atan2(pull.y, pull.x)
        if let launch, launch.stoneID == stone.id {
            squash += sin(launch.age * 65) * exp(-launch.age * 22) * launch.power * 0.12
            angle = atan2(launch.direction.y, launch.direction.x)
        }
        if let hit = hits.last(where: { !$0.ringOut && $0.age < 0.1 && (stone.position - $0.position).length < 70 }) {
            squash += hit.strength * exp(-hit.age * 28) * 0.16
            angle = atan2(stone.position.y - hit.position.y, stone.position.x - hit.position.x)
        }
        var shaped = context
        if trails {
            squash = min(0.22, max(-0.12, squash))
            shaped.translateBy(x: point.x, y: point.y)
            shaped.rotate(by: .radians(angle))
            shaped.scaleBy(x: 1 - squash, y: 1 / (1 - squash))
            shaped.translateBy(x: -point.x, y: -point.y)
        }
        disc(center: point, radius: radius, player: stone.owner, context: shaped)
        if selected {
            context.stroke(Path(ellipseIn: CGRect(x: point.x - radius - 5, y: point.y - radius - 5, width: radius * 2 + 10, height: radius * 2 + 10)),
                           with: .color(.white.opacity(0.8)), lineWidth: 1.5)
        }
    }

    static func disc(center p: CGPoint, radius r: Double, player: AlkkagiGame.Player, context: GraphicsContext) {
        var layer = context
        BoardGameDrawing.drawStone(&layer, at: p, radius: r, color: player == .black ? .black : .white, opacity: context.opacity)
    }

    static func aim(stone: AlkkagiGame.Stone, pull: AlkkagiVector, context: GraphicsContext, scale: Double) {
        guard pull.length > 2 else { return }
        let center = CGPoint(x: stone.position.x * scale, y: stone.position.y * scale)
        let grip = CGPoint(x: center.x + pull.x * scale, y: center.y + pull.y * scale)
        let direction = pull * (-1 / pull.length)
        let power = min(1, pull.length / AlkkagiGame.maxPull)
        let spread = AlkkagiGame.stoneRadius * scale * 0.8
        var band = Path()
        band.move(to: CGPoint(x: center.x - direction.y * spread, y: center.y + direction.x * spread))
        band.addLine(to: grip)
        band.addLine(to: CGPoint(x: center.x + direction.y * spread, y: center.y - direction.x * spread))
        context.stroke(band, with: .color(stone.owner.darkColor.opacity(0.15)), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        context.stroke(band, with: .color(.white.opacity(0.65 + power * 0.35)), style: StrokeStyle(lineWidth: 1.5 + power, lineCap: .round, lineJoin: .round))
        let gripRadius = 5 + power * 2
        context.stroke(Path(ellipseIn: CGRect(x: grip.x - gripRadius, y: grip.y - gripRadius, width: gripRadius * 2, height: gripRadius * 2)), with: .color(.white), lineWidth: 1.5)
        // 날아갈 방향 — 돌 앞으로 점선 화살. 길이 = 힘(어디서 멈출지는 보여 주지 않는다), 색 = 흰 → 주황 → 빨강.
        let radius = AlkkagiGame.stoneRadius * scale
        let length = (36 + 150 * power) * scale
        let from = CGPoint(x: center.x + direction.x * (radius + 4), y: center.y + direction.y * (radius + 4))
        let to = CGPoint(x: from.x + direction.x * length, y: from.y + direction.y * length)
        let tint: Color = power < 0.6 ? .white : (power < 0.9 ? Color(red: 1, green: 0.72, blue: 0.3) : Color(red: 1, green: 0.38, blue: 0.3))
        var guide = Path(); guide.move(to: from); guide.addLine(to: to)
        context.stroke(guide, with: .color(tint.opacity(0.85)), style: StrokeStyle(lineWidth: 2 + power * 1.5, lineCap: .round, dash: [6, 6]))
        let head = 7 + power * 4
        var arrow = Path()
        arrow.move(to: CGPoint(x: to.x - direction.x * head - direction.y * head * 0.6, y: to.y - direction.y * head + direction.x * head * 0.6))
        arrow.addLine(to: to)
        arrow.addLine(to: CGPoint(x: to.x - direction.x * head + direction.y * head * 0.6, y: to.y - direction.y * head - direction.x * head * 0.6))
        context.stroke(arrow, with: .color(tint.opacity(0.9)), style: StrokeStyle(lineWidth: 2 + power, lineCap: .round, lineJoin: .round))
    }

    static func effects(_ hits: [AlkkagiHit], context: GraphicsContext, scale: Double, reduced: Bool) {
        for hit in hits {
            let t = hit.age / 0.32
            let radius = (8 + t * (18 + hit.strength * 24)) * scale
            let p = CGPoint(x: hit.position.x * scale, y: hit.position.y * scale)
            context.stroke(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                           with: .color(.white.opacity((1 - t) * 0.8)), lineWidth: (1 - t) * 2 + 0.5)
            if !reduced, !hit.ringOut, t < 0.35 {
                // 맞은 순간 번쩍 — 세기만큼 크고 밝게, 0.1초 안에 꺼진다.
                let flash = (6 + hit.strength * 14) * scale * (1 + t)
                context.fill(Path(ellipseIn: CGRect(x: p.x - flash, y: p.y - flash, width: flash * 2, height: flash * 2)),
                             with: .color(.white.opacity((1 - t / 0.35) * (0.25 + 0.5 * hit.strength))))
            }
            if !reduced {
                let sparks = 5 + Int(hit.strength * 6)
                for i in 0..<sparks {
                    let a = Double(i) / Double(sparks) * .pi * 2
                    let d = radius * 1.3
                    context.fill(Path(ellipseIn: CGRect(x: p.x + cos(a) * d - 1.5, y: p.y + sin(a) * d - 1.5, width: 3, height: 3)),
                                 with: .color(.white.opacity((1 - t) * 0.7)))
                }
            }
        }
    }

    static func falling(_ falls: [AlkkagiFall], context: GraphicsContext, scale: Double, origin: CGPoint, reduced: Bool) {
        for fall in falls {
            let t = min(1, fall.age / 0.9)
            let outward = fall.outward.length > 0 ? fall.outward * (1 / fall.outward.length) : AlkkagiVector(x: 0, y: 1)
            // 판 경계를 넘어간 뒤 가속해 아래 층으로 낙하한다. 판 안에서 축소해 지우지 않는다.
            let distance = reduced ? 24 * t : 10 + 40 * t
            let p = CGPoint(x: origin.x + fall.position.x * scale + outward.x * distance,
                            y: origin.y + fall.position.y * scale + outward.y * distance + t * t * 100)
            let radius = AlkkagiGame.stoneRadius * scale * (1 - t * 0.25)
            var layer = context
            layer.opacity = reduced ? 1 - t : 1
            layer.fill(Path(ellipseIn: CGRect(x: p.x - radius * 0.9, y: p.y + 12 + t * 10,
                                             width: radius * 1.8, height: radius * 0.5)), with: .color(.black.opacity((1 - t) * 0.25)))
            if !reduced {
                layer.translateBy(x: p.x, y: p.y)
                layer.rotate(by: .radians(t * 0.7 * (outward.x < 0 ? -1 : 1)))
                layer.scaleBy(x: 1, y: 1 - t * 0.25)
                layer.translateBy(x: -p.x, y: -p.y)
            }
            disc(center: p, radius: radius, player: fall.owner, context: layer)
        }
    }

}

@MainActor
final class AlkkagiFeedback {
    /// 한 번 울릴 소리의 표본(44.1kHz 단음). 렌더 시험이 영상 소리를 만들 때도 이 함수를 쓴다.
    nonisolated static func samples(strength: Double, kind: Kind) -> [Float] {
        let s = min(1, max(0.1, strength))
        var seed: UInt32 = 0x9E37_79B9 ^ UInt32(s * 1_000)
        func noise() -> Double {   // 결정적 잡음(같은 세기 = 같은 소리)
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed >> 8) / Double(1 << 24) * 2 - 1
        }
        switch kind {
        case .hit:
            // 돌끼리 '딱': 2ms 잡음 딸깍 + 어긋난 두 배음(돌 울림) + 세기만큼 낮은 몸통 울림.
            let f1 = 1_750 + 950 * s
            return (0..<5_300).map { i in
                let t = Double(i) / 44_100
                let click = noise() * exp(-t * 1_400) * 0.9
                let ring = sin(2 * .pi * f1 * t) * exp(-t * 60) + 0.55 * sin(2 * .pi * f1 * 2.41 * t) * exp(-t * 95)
                let body = sin(2 * .pi * (150 + 60 * s) * t) * exp(-t * 32) * s * 0.8
                return Float((click + ring * 0.7 + body) * pow(s, 0.8) * 0.2)
            }
        case .flick:
            // 손가락 튕김 '톡': 짧고 낮게.
            return (0..<3_000).map { i in
                let t = Double(i) / 44_100
                let click = noise() * exp(-t * 2_000) * 0.7
                let tone = sin(2 * .pi * (900 + 300 * s) * t) * exp(-t * 110)
                return Float((click + tone * 0.6) * s * 0.18)
            }
        case .ringOut:
            // 판 밖 '또르르 툭': 내려가는 미끄럼 + 0.13초 뒤 아래 판에 떨어지는 둔한 소리.
            return (0..<9_100).map { i in
                let t = Double(i) / 44_100
                let slide = sin(2 * .pi * (620 * t - 1_100 * t * t)) * exp(-t * 26) * 0.6
                let lt = t - 0.13
                let thud = lt > 0 ? (sin(2 * .pi * 110 * lt) * 0.9 + noise() * 0.35) * exp(-lt * 38) : 0
                return Float((slide + thud) * 0.2)
            }
        }
    }

    private var engine: AVAudioEngine?
    private var voices: [AVAudioPlayerNode] = []
    private var voice = 0
    private var lastSound = 0.0

    enum Kind: Sendable { case flick, hit, ringOut }

    func play(strength: Double, kind: Kind, horizontal: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSound > 0.035 else { return }
        lastSound = now
        if engine == nil {
            let audio = AVAudioEngine()
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            for _ in 0..<4 {
                let node = AVAudioPlayerNode(); audio.attach(node)
                audio.connect(node, to: audio.mainMixerNode, format: format); voices.append(node)
            }
            do { try audio.start(); engine = audio } catch { voices = []; return }
        }
        let wave = Self.samples(strength: strength, kind: kind)
        guard !voices.isEmpty, let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(wave.count)),
              let samples = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = buffer.frameCapacity
        for i in wave.indices { samples[i] = wave[i] }
        let node = voices[voice % voices.count]; voice += 1
        node.pan = Float((horizontal / AlkkagiGame.boardSize - 0.5) * 1.4)
        node.scheduleBuffer(buffer, at: nil, options: .interrupts); node.play()
    }
}

private extension AlkkagiGame.Player {
    var title: String { self == .black ? "흑돌" : "백돌" }
    var color: Color { self == .black ? Color(white: 0.15) : Color(white: 0.95) }
    var darkColor: Color { Color(red: 0.19, green: 0.17, blue: 0.14) }
}

extension View {
    /// 말풍선 — 앱은 우리 말풍선(`checkTooltip`), 독립 실행기는 없음. 시스템 말풍선은 쓰지 않는다(V0325 계약).
    @ViewBuilder func alkkagiTooltip(_ text: String) -> some View {
        #if ALKKAGI_PLAYGROUND
        self
        #else
        self.checkTooltip(text)
        #endif
    }
}

// MARK: - 안내(대표 11-10 "어디다 돌 둬야되는지 판 구분도 별로 안되어있고 … 뭘 하라는건지 모르겠어" · #d_cjxnVZpLHWw5 C안)
//
//  · 숨겨 놓기: 돌을 둘 수 있는 **실제** 칸만 파랗게 + 점선(나머지는 어둡게) · 판 가운데 큰 안내 한 줄 · 오른쪽 상자는 오목처럼 큰 글 · 색.
//  · 쏘기 차례: 쏠 수 있는 내 돌마다 초록 고리 · 손이 뒤로 당기고 날아갈 쪽 화살(처음 세 번 쏠 때까지).
//  · 상대 차례: 상대 카드는 '쏘는 중'(옛 '내 차례예요'는 상대 카드에도 떠 헷갈렸다).
//  · 처음 한 번 따라 하기는 로비(`AlkkagiFirstTimeCoach` — 시간이 흐르지 않는 곳).

enum AlkkagiGuideText {
    /// 판 위 '아래 · 위' — 판은 돌리지 않는다(흑은 아래, 백은 위).
    static func sideWord(_ side: AlkkagiGame.Player) -> String { side == .black ? "아래" : "위" }

    /// 숨겨 놓기 · 판 가운데 띠.
    static func band(side: AlkkagiGame.Player, placed: Int) -> String {
        "내 진영(\(sideWord(side)) 파란 칸)에 돌 5개를 놓으세요 · \(placed)/5"
    }

    /// 숨겨 놓기 · 오른쪽 상자. `player` 는 연습 판(한 맥 둘이)에서만 — 흑 · 백 차례를 글에 넣는다.
    static func placing(side: AlkkagiGame.Player, placed: Int, player: AlkkagiGame.Player?) -> String {
        let body = "\(sideWord(side)) 파란 칸에 \(player == nil ? "내 " : "")돌 5개를 놓으세요 (\(placed)/5)"
        return player.map { "\($0.title) 차례 — \(body)" } ?? body
    }

    static let placedWaiting = "준비 완료 — 상대가 놓기를 기다려요"
    static let placeRejected = "파란 칸 안에, 다른 돌과 겹치지 않게 놓아 주세요"

    static func opponentTurn(_ name: String) -> String { "\(name)님이 쏠 차례예요 — 기다려 주세요" }

    /// 쏘기 차례 · 오른쪽 상자. 첫 수(흑)는 힘 60% 를 함께 말한다(선후 맞춤).
    static func aiming(player: AlkkagiGame.Player?, holding: Bool, firstShotLimited: Bool) -> String {
        if holding {
            return firstShotLimited ? "첫 수는 힘 60%까지 · 놓으면 반대쪽으로 날아가요 · Esc로 취소"
                : "놓으면 반대쪽으로 날아가요 · Esc로 취소"
        }
        let who = player.map { "\($0.title) 차례" } ?? "내 차례"
        return "\(who) — \(player == nil ? "내 " : "")돌을 뒤로 당겼다 놓으세요\(firstShotLimited ? " (첫 수는 힘 60%까지)" : "")"
    }

    /// 선수 카드 한 줄. 온라인 상대 카드가 차례이면 '쏘는 중'(내 카드만 '내 차례예요').
    static func cardMessage(simultaneousPlacement: Bool, ready: Bool, isMe: Bool, isOnline: Bool, active: Bool,
                            placing: Bool) -> String {
        if simultaneousPlacement { return ready ? "준비 완료" : (isMe ? "돌을 배치해 주세요" : "배치 중") }
        guard active else { return "기다리는 중" }
        if placing { return "돌을 배치해 주세요" }
        return isOnline && !isMe ? "쏘는 중" : "내 차례예요"
    }

    static let handHint = "뒤로 당겼다 놓기"
}

enum AlkkagiGuideDrawing {
    /// 숨겨 놓기에서 돌을 둘 수 있는 칸의 경계(판 좌표) — `AlkkagiGame.canPlace` 와 같은 값(시험이 둘을 맞춰 본다).
    static let blackZoneTop: Double = 320
    static let whiteZoneBottom: Double = 280

    /// 숨겨 놓기: 내 칸만 파랗게 + 점선 테두리 + '내 진영' 이름표, 그 밖(상대 칸 + 가운데 빈 띠)은 어둡게.
    static func zones(context: GraphicsContext, size: CGSize, mine: AlkkagiGame.Player) {
        let s = size.width / AlkkagiGame.boardSize
        let blackTop = blackZoneTop * s, whiteBottom = whiteZoneBottom * s
        let lower = CGRect(x: 0, y: blackTop, width: size.width, height: size.height - blackTop)
        let upper = CGRect(x: 0, y: 0, width: size.width, height: whiteBottom)
        let mineRect = mine == .black ? lower : upper
        let theirRect = mine == .black ? upper : lower
        let outside = mine == .black ? CGRect(x: 0, y: 0, width: size.width, height: blackTop)
                                     : CGRect(x: 0, y: whiteBottom, width: size.width, height: size.height - whiteBottom)
        context.fill(Path(outside), with: .color(.black.opacity(0.48)))
        context.fill(Path(mineRect), with: .color(CheckTheme.accent.opacity(0.55)))
        context.stroke(Path(roundedRect: mineRect.insetBy(dx: 4, dy: 4), cornerRadius: 10),
                       with: .color(CheckTheme.accent), style: StrokeStyle(lineWidth: 3, dash: [12, 6]))
        let mineLabel = context.resolve(Text("내 진영").font(.subheadline.weight(.heavy)).foregroundStyle(.white))
        let labelSize = mineLabel.measure(in: CGSize(width: 200, height: 40))
        let labelY = mine == .black ? mineRect.maxY - 22 : mineRect.minY + 22
        let pill = CGRect(x: mineRect.midX - labelSize.width / 2 - 14, y: labelY - labelSize.height / 2 - 5,
                          width: labelSize.width + 28, height: labelSize.height + 10)
        context.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(CheckTheme.accent))
        context.draw(mineLabel, at: CGPoint(x: mineRect.midX, y: labelY))
        let theirLabel = context.resolve(Text("상대 진영").font(.headline.weight(.semibold)).foregroundStyle(.white.opacity(0.6)))
        context.draw(theirLabel, at: CGPoint(x: theirRect.midX, y: theirRect.midY))
    }

    /// 쏘기 차례: 쏠 수 있는 내 돌마다 초록 고리(뒤집기의 '둘 수 있는 곳' 점처럼).
    static func myStones(context: GraphicsContext, scale: Double, stones: [AlkkagiGame.Stone], mine: AlkkagiGame.Player) {
        let r = AlkkagiGame.stoneRadius * scale + 5
        for stone in stones where stone.owner == mine && stone.isPlaced && !stone.isOut {
            let p = CGPoint(x: stone.position.x * scale, y: stone.position.y * scale)
            context.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                           with: .color(CheckTheme.working.opacity(0.9)), lineWidth: 2.5)
        }
    }

    /// 손 안내를 붙일 돌: 판 가운데(가로)에 가장 가까운 내 돌.
    static func hintStone(_ stones: [AlkkagiGame.Stone], mine: AlkkagiGame.Player) -> AlkkagiGame.Stone? {
        stones.filter { $0.owner == mine && $0.isPlaced && !$0.isOut }
            .min { abs($0.position.x - AlkkagiGame.boardSize / 2) < abs($1.position.x - AlkkagiGame.boardSize / 2) }
    }

    /// 손 안내 한 장면. `pullFraction` 0…1 = 손이 당긴 정도(1 = 끝까지), `release` 0…1 = 놓은 뒤 화살이 밝아지는 정도.
    static func pullHint(context: GraphicsContext, scale: Double, stone: AlkkagiGame.Stone, mine: AlkkagiGame.Player,
                         pullFraction: Double, release: Double) {
        // 흑(아래)은 아래로 당겨 위로, 백(위)은 위로 당겨 아래로 쏜다. 판 밖으로 손이 나가지 않게 당김 길이를 줄인다.
        let back: Double = mine == .black ? 1 : -1
        let p = CGPoint(x: stone.position.x * scale, y: stone.position.y * scale)
        let r = AlkkagiGame.stoneRadius * scale
        let room = mine == .black ? (AlkkagiGame.boardSize - stone.position.y) : stone.position.y
        let fullReach = max(24, min(62, room - 18))
        let pullEnd = CGPoint(x: p.x + 18 * scale * pullFraction, y: p.y + back * fullReach * pullFraction * scale)
        // 말풍선은 끝까지 당긴 자리에 고정(손만 움직인다 — 돌 줄 아래라 이웃 돌을 가리지 않는다).
        let fullEnd = CGPoint(x: p.x + 18 * scale, y: p.y + back * fullReach * scale)
        if pullFraction > 0.02 {
            var pullPath = Path()
            pullPath.move(to: p)
            pullPath.addLine(to: pullEnd)
            context.stroke(pullPath, with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 5]))
        }
        // 날아갈 쪽(반대) 화살 — 당긴 반대 방향. 당기기 전에는 기본 방향(상대 쪽 · 조금 비스듬히).
        let dx = pullFraction > 0.02 ? p.x - pullEnd.x : -18 * scale
        let dy = pullFraction > 0.02 ? p.y - pullEnd.y : -back * 62 * scale
        let len = max(1, (dx * dx + dy * dy).squareRoot())
        let ux = dx / len, uy = dy / len
        let start = CGPoint(x: p.x + ux * (r + 6), y: p.y + uy * (r + 6))
        let tip = CGPoint(x: p.x + ux * (r + 78 * scale), y: p.y + uy * (r + 78 * scale))
        let arrow = CheckTheme.working.opacity(0.55 + 0.4 * max(pullFraction, release))
        var flyPath = Path()
        flyPath.move(to: start)
        flyPath.addLine(to: tip)
        context.stroke(flyPath, with: .color(arrow), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        var head = Path()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: tip.x - ux * 14 - uy * 9, y: tip.y - uy * 14 + ux * 9))
        head.addLine(to: CGPoint(x: tip.x - ux * 14 + uy * 9, y: tip.y - uy * 14 - ux * 9))
        head.closeSubpath()
        context.fill(head, with: .color(arrow))
        // 손 · 말풍선(손 옆, 판 안쪽으로)
        let hand = context.resolve(Text(Image(systemName: "hand.point.up.left.fill")).font(.system(size: 30)).foregroundStyle(.white))
        let handAt = CGPoint(x: pullEnd.x + 10, y: pullEnd.y + back * 8)
        context.draw(hand, at: handAt)
        let label = context.resolve(Text(AlkkagiGuideText.handHint).font(.callout.weight(.bold)).foregroundStyle(.black))
        let size = label.measure(in: CGSize(width: 300, height: 40))
        let bubbleAt = CGPoint(x: fullEnd.x + 10, y: fullEnd.y + back * 8)
        let toLeft = bubbleAt.x + 34 + size.width + 20 > AlkkagiGame.boardSize * scale
        let anchor = CGPoint(x: toLeft ? bubbleAt.x - 34 - size.width / 2 - 10 : bubbleAt.x + 34 + size.width / 2 + 10,
                             y: bubbleAt.y)
        let bubble = CGRect(x: anchor.x - size.width / 2 - 10, y: anchor.y - size.height / 2 - 6,
                            width: size.width + 20, height: size.height + 12)
        context.fill(Path(roundedRect: bubble, cornerRadius: bubble.height / 2), with: .color(.white.opacity(0.95)))
        context.draw(label, at: anchor)
    }

    /// 손 안내 움직임(2초 한 바퀴): 0~0.9초 당김 → 1.2초까지 버팀 → 놓음(화살이 밝아지고 손이 돌아간다).
    static func pullHintPhase(_ t: Double) -> (pull: Double, release: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 2.0)
        if cycle < 0.9 {
            let x = cycle / 0.9
            return (x * x * (3 - 2 * x), 0)
        }
        if cycle < 1.2 { return (1, 0) }
        let x = min(1, (cycle - 1.2) / 0.8)
        return (0, 1 - x)
    }
}

/// 손 안내 — 판 위 덮개(입력을 막지 않는다). 동작 줄이기를 켜면 끝까지 당긴 한 장면으로 멈춘다.
struct AlkkagiPullHint: View {
    let stone: AlkkagiGame.Stone
    let mine: AlkkagiGame.Player
    let reduced: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduced)) { context in
            let phase = reduced ? (pull: 1.0, release: 0.0)
                : AlkkagiGuideDrawing.pullHintPhase(context.date.timeIntervalSinceReferenceDate)
            Canvas { canvas, size in
                AlkkagiGuideDrawing.pullHint(context: canvas, scale: size.width / AlkkagiGame.boardSize, stone: stone, mine: mine,
                                             pullFraction: phase.pull, release: phase.release)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 처음 한 번 따라 하기 — 알까기 창을 처음 열 때 로비 위에 한 번(시간이 흐르지 않는 곳). [알겠어요]로 닫으면 다시 저절로 안 뜬다.
/// '봤음'은 UserDefaults 한 키 — 시험은 시험 전용 스위트를 넘긴다(`AlkkagiOnlinePanel.guideDefaults`).
enum AlkkagiFirstTimeCoach {
    static let seenKey = "check.alkkagi.firstTimeCoachSeen"
    static let title = "처음 하는 알까기"
    static let done = "알겠어요"
    static let steps: [(icon: String, title: String, detail: String)] = [
        ("hand.tap.fill", "파란 칸(내 진영)에 내 돌 5개를 숨겨 놓아요", "상대는 둘 다 놓을 때까지 못 봐요 · 30초"),
        ("hand.draw.fill", "내 차례가 오면 내 돌을 뒤로 당겼다 놓아요", "당긴 반대쪽으로 날아가요 · 한 수 30초"),
        ("arrow.up.right.circle.fill", "상대 돌을 판 밖으로 모두 밀어내면 이겨요", "내 돌도 밖으로 나가면 빠져요"),
    ]

    static func hasSeen(_ defaults: UserDefaults) -> Bool { defaults.bool(forKey: seenKey) }
    static func markSeen(_ defaults: UserDefaults) { defaults.set(true, forKey: seenKey) }

    /// 띄울까: 로비가 보일 때만(판 · 연습 · 관전 중엔 시간이 흐른다) · 스냅숏은 `preview` 로만 · 이 창에서 닫았거나 본 적 있으면 안 띄운다.
    static func shows(lobbyVisible: Bool, preview: Bool?, snapshot: Bool, dismissed: Bool, defaults: UserDefaults?) -> Bool {
        guard lobbyVisible else { return false }
        if let preview { return preview }
        guard !snapshot, !dismissed, let defaults else { return false }
        return !hasSeen(defaults)
    }
}

struct AlkkagiFirstTimeCoachCard: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDone)
            VStack(alignment: .leading, spacing: 12) {
                Text(AlkkagiFirstTimeCoach.title).font(.title3.weight(.bold))
                ForEach(Array(AlkkagiFirstTimeCoach.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle().fill(CheckTheme.accent.opacity(0.2))
                            Image(systemName: step.icon).font(.system(size: 16, weight: .bold)).foregroundStyle(CheckTheme.accent)
                        }.frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(index + 1). \(step.title)").font(.subheadline.weight(.semibold))
                            Text(step.detail).font(.caption).foregroundStyle(CheckTheme.secondaryText)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button(action: onDone) {
                        Text(AlkkagiFirstTimeCoach.done)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22).padding(.vertical, 8)
                            .background(Capsule().fill(CheckTheme.accent))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 420)
            .background(RoundedRectangle(cornerRadius: 18).fill(CheckTheme.panelElevated.opacity(0.97)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(CheckTheme.accent.opacity(0.6), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
        }
    }
}
