#if os(iOS)
import CheckCore
import SwiftUI

/// 미니게임 화면(SPEC-ios §3.5): 머리 줄(최고 · 오늘 순위 · 안내) · 캔버스(논리 292×302 를 폭에 **등비 확대**) · 오늘 순위.
///
/// - 캔버스 어디든 **누르는 순간** = 행동(맥의 마우스 다운 래치와 같다 — 손을 뗄 때 발화하면 점프 게임엔 그 지연이 곧 낙차다).
///   ⚠️ **테트리스는 진행 중일 때만 다르다**: 한 번의 끌기가 여러 칸을 만들고 행동도 셋(좌·우·소프트드롭)이라
///   래치로는 표현이 안 된다 — 그때만 `GamesPlayController` 의 제스처 트래커로 넘긴다. 시작 화면에서는
///   테트리스도 래치가 판을 켠다(트래커로만 받으면 0.25초를 넘겨 천천히 뗀 사람에게 시작이 안 되고, 그건 '고장'으로 읽힌다).
/// - 프레임 상한은 화면 최대 주사율(`UIScreen.maximumFramesPerSecond`)을 코어 `MiniGameFrameRate` 에 넣은 값이다.
/// - 햅틱 네 채널: 판에 먹힌 탭(가볍게) · 하드드롭(단단하게) · 줄소거(묵직하게) · 게임오버·완주(한 번).
///   **이동 걸음·소프트드롭 걸음에는 없다** — L1 소프트드롭이 초당 56회, L5 는 213회라 탭틱 엔진이 낼 수 있는 속도가 아니다.
/// - 앱이 background 로 가거나 화면을 떠나면 판은 끝 — 스토어·허브가 한다(`GamesMiniGameHub.appDidEnterBackground`·
///   `closeScreen`). 기존 두 게임은 제출하지 않고, **테트리스는 여기까지의 점수로 확정 제출한다.**
struct GamesMiniGameScreen: View {
    let store: GamesStore
    let kind: MiniGameKind

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressLatched = false
    @State private var refreshHz = MiniGameFrameRate.baselineFPS
    /// 데모 스크린샷: 판 도중 장면을 멈춰 둔다(DEBUG · 데모에서만 참이 된다).
    @State private var framesFrozen = false
    /// **다 쓴 접촉**의 시작점 — 이 손가락으로는 더 아무 일도 하지 않는다. 들어오는 길이 둘이다:
    /// ① 시작 래치가 판을 켠 그 끌기(안 삼키면 **한 번의 탭이 시작과 회전을 둘 다** 한다 — `action()` 이
    ///    ready → running 으로 바꾼 직후라 이어지는 탭 판정이 그대로 통과한다. 그리고 그 손가락이 한 칸 폭 이상
    ///    흔들리면 새 판 첫 조각이 **곧장 옆으로 간다** — `onEnded` 만 삼키면 그 이동은 안 막힌다).
    /// ② 그 접촉으로 끌던 도중에 판이 끝난 경우(상한·탑아웃). 표시를 안 하면 같은 손가락의 다음 `onChanged` 가
    ///    시작 래치를 때려 **새 판이 저절로 켜진다.**
    ///
    /// 불리언이 아니라 **시작점**인 이유: `onEnded` 는 늘 오지 않는다(시스템 제스처·전화 수신으로 취소되면 안 온다).
    /// 참인 채로 남으면 그다음 **멀쩡한 탭**의 회전이 대신 삼켜진다. 시작점이면 새 접촉은 값이 달라 안 걸린다.
    @State private var swallowsTetrisDragEnd: CGPoint?
    /// 지금 트래커로 넘기고 있는(= 진행 중인 판을 조작하는) 접촉의 시작점. 판이 이 손가락 아래에서 끝났는지를
    /// 이 값으로 알아본다 — `isPlaying` 이 거짓인데 이 시작점이면 **방금 끝난 그 접촉**이다.
    @State private var tetrisPlayContact: CGPoint?

    private var hub: GamesMiniGameHub { store.miniGames }

    var body: some View {
        // 캔버스는 **폭이 정한다**(좌우 16 여백 안 폭 × 302/292). 아래 순위 스크롤과 높이를 나눠 갖게 두면 비율 맞춤이
        // 캔버스를 좁혀 양옆에 빈 띠가 생긴다(데모 스크린샷 실측).
        GeometryReader { geo in
            let width = max(0, geo.size.width - MobileTheme.sideMargin * 2)
            let height = width * MiniGameCanvas.logicalHeight / MiniGameCanvas.logicalWidth
            VStack(spacing: MobileTheme.rowSpacing) {
                header
                canvas(width: width)
                    .frame(width: width, height: height)
                // 테트리스만 버튼 줄이 붙는다 — 끌기로 표현할 수 없는 셋(홀드 · 반시계 회전 · 즉시 내리기)이다.
                if kind == .tetris, let controller = hub.controller, controller.kind == kind {
                    tetrisControls(controller, width: width)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !hub.isPublic {
                            InlineNotice(text: GamesMiniGameText.privateNotice, kind: .info)
                                .padding(.bottom, MobileTheme.space2)
                        }
                        rankings
                    }
                    .padding(.bottom, MobileTheme.space6)
                }
                .scrollIndicators(.hidden)
                .gamesDemoScrollAnchor(isDemo: store.context.isDemo)
            }
            // 열 폭을 못 박는다 — 큰 글자에서 자식 하나가 넓어지면 열 전체가 화면 밖으로 밀렸다(AX 스크린샷 실측).
            .frame(width: width)
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, 4)
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar(for: .miniGamePlay)
        .onAppear {
            refreshHz = GamesDisplay.maximumFramesPerSecond
            hub.openScreen(kind)
            applyDemoSeed()
        }
        .onDisappear { hub.closeScreen(kind) }
    }

    // MARK: 머리 줄

    private var header: some View {
        let best = hub.best(for: kind)
        let rank = GamesMiniGameText.rankLine(hub.myRank(kind), knowsBoard: (hub.boards[kind] ?? GamesMiniGameBoard()).knowsPlayerCount)
        return VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    bestLabel(best)
                    Spacer(minLength: 6)
                    rankLabel(rank)
                }
                VStack(alignment: .leading, spacing: 4) {
                    bestLabel(best)
                    rankLabel(rank)
                }
            }
            // 제출 실패·판 끝남은 조용히 삼키지 않는다(맥과 같다 — 삼키면 "잘 놀았는데 순위표에 없다"가 된다).
            if let notice = hub.submitNotice {
                Text(notice)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MobileTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bestLabel(_ best: Int) -> some View {
        Label {
            Text(GamesMiniGameText.bestLine(best)).monospacedDigit()
        } icon: {
            // 트로피는 금(순위 메달 색) — 앰버는 연결 끊김·대기 전용이다.
            Image(systemName: "trophy.fill").foregroundStyle(MobileTheme.gold)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(MobileTheme.label)
    }

    /// 오늘 순위 한 줄. 순위표를 모르면(불러오는 중·실패) 그리지 않는다 — 실패는 아래 순위 카드가 말한다.
    /// 순위가 있으면 공용 순위 원(금은동) — 예전 파랑 글자는 링크처럼 보였다(비평 14~19).
    @ViewBuilder
    private func rankLabel(_ line: String?) -> some View {
        if let rank = hub.myRank(kind) {
            HStack(spacing: 6) {
                Text("오늘")
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.label2)
                RankBadge(rank: rank)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line ?? "오늘 \(rank)위")
        } else if let line {
            Text(line)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(MobileTheme.label2)
        }
    }

    // MARK: 캔버스

    @ViewBuilder
    private func canvas(width: CGFloat) -> some View {
        if let controller = hub.controller, controller.kind == kind {
            TimelineView(.animation(minimumInterval: MiniGameFrameRate.minimumInterval(forRefreshRate: refreshHz),
                                    paused: !controller.isPlaying || framesFrozen)) { context in
                canvasContent(controller)
                    .onChange(of: context.date) { _, now in
                        guard !framesFrozen else { return }
                        controller.tick(at: now)
                    }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CheckTheme.panel))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MobileTheme.separator, lineWidth: 1))
            .contentShape(Rectangle())
            // ⚠️ `.gesture` 는 **이 자리 하나**다. `if kind == .tetris` 로 모디파이어 자체를 갈라 붙이면 뷰 정체성이
            // 갈려 SwiftUI 가 제스처를 다시 만든다 — 갈래는 클로저 **안**에 둔다.
            .gesture(canvasDrag(controller))
            .sensoryFeedback(.impact(weight: .light), trigger: controller.tapSerial)
            .sensoryFeedback(.impact(flexibility: .rigid), trigger: controller.hardDropSerial)
            .sensoryFeedback(.impact(weight: .heavy), trigger: controller.lineClearSerial)
            .sensoryFeedback(.error, trigger: controller.gameOverSerial)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GamesMiniGameText.canvasAccessibility(kind))
            .accessibilityValue(accessibilityValue(controller))
            // 테트리스에는 **직접 조작 트레잇을 걸지 않는다**: 셀이 15~18pt 인 판에서 눈 없이 겨냥하라는 뜻이라
            // 실질 조작이 불가능하다. 두 게임(판 어디든 탭)에는 그대로 둔다.
            .accessibilityAddTraits(kind == .tetris ? [] : [.allowsDirectInteraction])
            // 기본 액션: 진행 중이면 시계 회전, 시작 전·결과면 새 판(구동기가 가른다).
            .accessibilityAction { controller.tap() }
            .accessibilityActions { tetrisAccessibilityActions(controller) }
            // 캔버스 안 글자는 판 배율을 따른다 — 시스템 글자 크기에 끌려가면 판을 넘친다.
            .dynamicTypeSize(...DynamicTypeSize.large)
            // 한 칸 문턱은 **화면 셀 폭**이다(논리 13 × 배율). 폭이 정해지는 첫 프레임에 바로 건넨다.
            .onChange(of: width, initial: true) { _, resolved in
                controller.updateCellWidth(TetrisLayout.cell * resolved / TetrisLayout.logicalSize.width)
            }
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CheckTheme.panel)
        }
    }

    /// 캔버스 위 한 번의 접촉. 갈래는 **'진행 중인가'** 이지 `kind` 가 아니다 — 시작 화면에서는 테트리스도 래치가 판을 켠다.
    private func canvasDrag(_ controller: GamesPlayController) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !framesFrozen else { return }
                // ① 다 쓴 접촉은 **여기서 끝난다** — 판을 켠 손가락의 이동도, 판이 끝난 손가락의 시작 래치도 막는다.
                if kind == .tetris, swallowsTetrisDragEnd == value.startLocation { return }
                // ② 이 접촉이 끌던 판이 방금 끝났다(상한·탑아웃). 같은 손가락이 새 판을 켜면 안 된다 —
                //    켜지면 트래커에 남은 앞 끌기의 축 잠금·소비량으로 첫 조각이 곧장 튄다.
                if kind == .tetris, !controller.isPlaying, tetrisPlayContact == value.startLocation {
                    tetrisPlayContact = nil
                    swallowsTetrisDragEnd = value.startLocation
                    return
                }
                if kind == .tetris, controller.isPlaying {
                    tetrisPlayContact = value.startLocation
                    controller.canvasDragChanged(startLocation: value.startLocation,
                                                 translation: value.translation, at: value.time)
                    return
                }
                guard !pressLatched else { return }
                pressLatched = true
                let wasPlaying = controller.isPlaying
                controller.tap()
                if kind == .tetris, !wasPlaying, controller.isPlaying { swallowsTetrisDragEnd = value.startLocation }
            }
            .onEnded { value in
                pressLatched = false
                guard !framesFrozen, kind == .tetris else { return }
                if tetrisPlayContact == value.startLocation { tetrisPlayContact = nil }
                guard swallowsTetrisDragEnd != value.startLocation else {
                    swallowsTetrisDragEnd = nil
                    return
                }
                guard controller.isPlaying else { return }
                controller.canvasDragEnded(translation: value.translation, at: value.time)
            }
    }

    @ViewBuilder
    private func canvasContent(_ controller: GamesPlayController) -> some View {
        switch kind {
        case .timingBar:
            GamesTimingBarCanvas(game: controller.timing, bestScore: hub.best(for: kind), reduceMotion: reduceMotion)
        case .flappy:
            GamesFlappyCanvas(game: controller.flappy, bestScore: hub.best(for: kind), reduceMotion: reduceMotion)
        case .tetris:
            GamesTetrisCanvas(game: controller.tetris, bestScore: hub.best(for: kind), reduceMotion: reduceMotion)
        }
    }

    private func accessibilityValue(_ controller: GamesPlayController) -> String {
        switch kind {
        case .timingBar:
            if case .finished(let total) = controller.timing.phase { return "총점 \(total)" }
            return controller.isPlaying ? "라운드 \(max(1, controller.timing.round)), 총점 \(controller.timing.total)" : GamesMiniGameText.startAction
        case .flappy:
            if controller.flappy.phase == .result { return "\(controller.flappy.score)점" }
            return controller.isPlaying ? "\(controller.flappy.score)점" : GamesMiniGameText.startAction
        case .tetris:
            // **느린 값만**이다(점수·레벨·줄). 조각·열·행을 넣으면 보이스오버가 자기 말을 끝없이 끊는다 —
            // 조각 자리는 L1 0.355초/칸 · L15 0.00082초/칸으로 바뀐다. 그 값들은 이동 액션 뒤 알림으로 말한다.
            let game = controller.tetris
            if game.phase == .ready { return GamesMiniGameText.startAction }
            return GamesMiniGameText.tetrisValue(score: game.score, level: game.scoreLevel, lines: game.lines)
        }
    }

    // MARK: 테트리스 — 보이스오버 이동 액션

    /// 버튼이 없는 조작만 액션으로 낸다. 홀드·반시계·즉시 내리기는 **이미 진짜 버튼**이라 중복시키지 않는다.
    @ViewBuilder
    private func tetrisAccessibilityActions(_ controller: GamesPlayController) -> some View {
        if kind == .tetris, controller.isPlaying {
            Button(GamesMiniGameText.tetrisMoveLeft) { announceColumn(controller) { $0.moveLeftOneCell() } }
            Button(GamesMiniGameText.tetrisMoveRight) { announceColumn(controller) { $0.moveRightOneCell() } }
            Button(GamesMiniGameText.tetrisSoftDrop) { announceDrop(controller) }
        }
    }

    private func announceColumn(_ controller: GamesPlayController, _ move: (GamesPlayController) -> Void) {
        move(controller)
        guard let column = controller.tetris.active?.cells.map({ $0.column }).min() else { return }
        AccessibilityNotification.Announcement(GamesMiniGameText.tetrisColumnAnnouncement(column + 1)).post()
    }

    private func announceDrop(_ controller: GamesPlayController) {
        let before = controller.tetris.active?.row
        controller.softDropOneCell()
        let moved = controller.tetris.active?.row != before
        AccessibilityNotification.Announcement(GamesMiniGameText.tetrisDropAnnouncement(moved: moved)).post()
    }

    // MARK: 테트리스 — 버튼 줄

    /// 캔버스와 같은 폭 W. [홀드][반시계][즉시 내리기] — 간격 8·16 을 뺀 쓸 폭을 26 : 30 : 44 로 나눈다.
    ///
    /// **확인 대화상자를 넣지 마라**(즉시 내리기에도): L15 부터 20G 라 조각이 스폰과 같은 틱에 접지하고
    /// 락딜레이가 0.50 → 0.16초다 — 확인창 한 번이 그 예산 전부다.
    private func tetrisControls(_ controller: GamesPlayController, width: CGFloat) -> some View {
        let usable = max(0, width - MobileTheme.space2 - MobileTheme.space4)
        return HStack(spacing: 0) {
            TetrisControlButton(title: GamesMiniGameText.tetrisHold, icon: "square.on.square",
                                width: usable * 0.26, isSpent: controller.tetris.holdUsed,
                                firesOnTouchDown: true) { controller.hold() }
            // 죽은 간격이다 — Spacer 는 히트 영역이 없다(버튼 쪽으로 넓히지 마라).
            Spacer(minLength: 0).frame(width: MobileTheme.space2)
            TetrisControlButton(title: GamesMiniGameText.tetrisRotateCounterClockwise, icon: "rotate.left",
                                width: usable * 0.30, firesOnTouchDown: true) { controller.rotate(clockwise: false) }
            Spacer(minLength: 0).frame(width: MobileTheme.space4)
            TetrisControlButton(title: GamesMiniGameText.tetrisHardDrop, icon: "arrow.down.to.line",
                                width: usable * 0.44, firesOnTouchDown: false) { controller.hardDrop() }
        }
        .frame(width: width)
        // 캔버스의 `...large` 상한은 캔버스에만 걸려 있다 — 버튼 줄은 시스템 글자를 그대로 따라가서
        // 접근성 크기에서 화면 밖으로 밀렸다. 여기서 따로 막는다.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    // MARK: 오늘 순위

    @ViewBuilder
    private var rankings: some View {
        let state = hub.boards[kind] ?? GamesMiniGameBoard()
        let myID = store.context.session.session?.userID.lowercased()
        // 정족수 줄은 사람 수를 알 때만 — 불러오지 못했거나 불러오는 중이면 "아무도 안 했어요"라고 말하지 않는다.
        SectionHeader(GamesMiniGameText.rankTitle,
                      trailing: state.knowsPlayerCount ? .text(GamesMiniGameText.quorumCaption(players: state.entries.count)) : .none,
                      padded: true)
            .padding(.top, -18)
        // 어제 1등은 **자기 그룹**(순위 탭과 같은 공용 `ChampionRow`) — '오늘 순위' 첫 행처럼 읽히지 않게 떼어 둔다(시안 B 06).
        if let winner = state.yesterdayWinner {
            ChampionRow(
                caption: GamesMiniGameText.yesterdayChampion,
                name: winner.name,
                center: CenterLabel.serverValue(forDisplay: winner.center),
                score: GamesMiniGameText.score(winner.score),
                awarded: winner.awarded ? GamesMiniGameText.rubyPrizes[0] : nil
            )
            .padding(.bottom, 12)
        }
        InsetGroup {
            if state.entries.isEmpty {
                GroupRow(divider: .none) {
                    switch state.placeholder {
                    case .failed:
                        LoadFailureRow(GamesMiniGameText.failedCaption, isRetrying: state.loading) {
                            Task { await hub.loadBoard(kind, withWinner: true) }
                        }
                    case .loading:
                        LoadingRow(GamesMiniGameText.loadingCaption)
                    case .empty, .rows:
                        Text(GamesMiniGameText.emptyBoard)
                            .font(.subheadline)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                ForEach(Array(state.entries.enumerated()), id: \.element.userID) { index, entry in
                    GamesRankRow(store: store, rank: index + 1, entry: entry, isMe: entry.userID == myID,
                                 isLast: index == state.entries.count - 1)
                }
            }
        }
        Text(GamesMiniGameText.prizeCaption)
            .font(MobileTheme.rowSubtitle)
            .foregroundStyle(MobileTheme.label2)
            .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
    }

    // MARK: 데모

    private func applyDemoSeed() {
        #if DEBUG
        guard let seed = GamesDemoSeed.current(isDemo: store.context.isDemo), let controller = hub.controller else { return }
        switch seed {
        case .playing:
            controller.replaceForTesting(timing: GamesDemoSeed.timingBar(finished: false), flappy: GamesDemoSeed.flappy(finished: false))
            framesFrozen = true
        case .result, .bottom:
            controller.replaceForTesting(timing: GamesDemoSeed.timingBar(finished: true), flappy: GamesDemoSeed.flappy(finished: true))
        default:
            break
        }
        #endif
    }
}

/// 오늘 순위 한 줄 — **순위 탭과 같은 공용 부품**(통합 때 승격: `RankRow`·`RankRowBody`·`RankRowFace`·`PersonName`).
/// 인셋 그룹 안 48pt: 등수 원 · 얼굴(내 행은 착용 캐릭터 초상) · 이름(+ 센터 · '나') · 점수. 구분선 시작점·큰 글자 접힘·
/// 내 행 강조가 두 탭에서 같아진다(비평 4 "같은 데이터 다른 부품").
private struct GamesRankRow: View {
    let store: GamesStore
    let rank: Int
    let entry: MiniGameBoardEntry
    let isMe: Bool
    let isLast: Bool

    private let metrics = RankRowScaledMetrics()
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        RankRow(isMine: isMe, isLast: isLast, dividerInset: metrics.dividerInset(faceBase: 30),
                minHeight: 48, verticalPadding: (7, 7)) {
            RankRowBody(rank: rank, alignment: .center) {
                RankRowFace(name: entry.name, colorSeed: entry.userID, url: entry.avatarURL, userID: entry.userID, base: 30,
                            me: isMe ? GamesMeIdentity.current(store.context).rankFace : nil)
            } content: {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        nameLine
                        score
                    }
                } else {
                    HStack(alignment: .center, spacing: 8) {
                        nameLine
                        Spacer(minLength: 4)
                        score
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var nameLine: some View {
        PersonName(entry.name, center: CenterLabel.serverValue(forDisplay: entry.center), isMe: isMe, onTint: true)
    }

    private var score: some View {
        Text(GamesMiniGameText.score(entry.bestScore))
            .font(MobileTheme.number(.callout, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label)
            .fixedSize()
    }
}

// MARK: - 테트리스 버튼

/// 조작 버튼 한 개 — 아이콘 위(17 semibold) + 글자 아래(caption2) · 높이 48 · **틴트**.
///
/// · **채운 버튼은 하나도 없다**(이 저장소 규약: 화면당 채운 버튼은 하나). 눌림은 **색만** 바꾼다 —
///   스케일 애니메이션을 쓰지 않으므로 reduceMotion 분기 자체가 필요 없다.
/// · 발화 시점이 둘이다. 홀드·반시계는 **터치-다운 래치**(20G 구간에서는 손가락 뗌을 기다릴 여유가 없다),
///   즉시 내리기만 **터치-업 인사이드**(표준 `Button` — 손을 끌어 빼면 취소된다. 잘못 누르면 그 판이 끝난다).
/// · 아이콘 셋(`square.on.square` · `rotate.left` · `arrow.down.to.line`)은 전부 iOS 13 부터 있는 이름이다.
///   **없는 심벌 이름은 경고 없이 빈 칸이 된다** — 이름을 바꾸려면 실재부터 확인해라.
private struct TetrisControlButton: View {
    let title: String
    let icon: String
    let width: CGFloat
    var isSpent = false
    let firesOnTouchDown: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    /// 지금 누르고 있는 접촉의 **시작점**(없으면 nil). 불리언 래치가 아니다.
    ///
    /// ⚠️ `onEnded` 는 늘 오지 않는다 — 시스템 제스처(홈 인디케이터 끌어 올리기·제어 센터)나 전화 수신으로
    /// 취소되면 안 온다. 불리언이면 그 한 번으로 `isPressed` 가 참인 채 굳고, 다음 누름이 `guard !isPressed`
    /// 에 걸려 **그 버튼이 화면을 떠날 때까지 죽는다**(홀드·반시계가 통째로 먹통이 된다).
    /// 시작점이면 새 접촉은 값이 달라 항상 통과한다 — `GamesTetrisGesture` 가 새 접촉을 알아보는 것과 같은 결이다.
    /// 남는 것은 **틴트가 눌린 채 보이는 것뿐**이고(다음 누름이 갈아 끼운다), 그건 버튼이 죽는 것과 비교가 안 된다.
    @State private var pressedContact: CGPoint?

    var body: some View {
        if firesOnTouchDown {
            label
                .modifier(TetrisControlChrome(width: width, isSpent: isSpent, isPressed: pressedContact != nil))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // 같은 접촉의 두 번째 `onChanged` 는 손가락이 움직인 것뿐이다(발화는 접촉당 한 번).
                            guard pressedContact != value.startLocation else { return }
                            pressedContact = value.startLocation
                            action()
                        }
                        .onEnded { _ in pressedContact = nil }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(isSpent ? GamesMiniGameText.tetrisHoldSpent : "")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { action() }
        } else {
            Button(action: action) { label }
                .buttonStyle(TetrisControlButtonStyle(width: width))
                .accessibilityLabel(title)
        }
    }

    private var label: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .accessibilityHidden(true)
            // 접근성 글자 크기에서는 글자를 떨어뜨리고 아이콘만 남긴다(보이스오버 라벨은 그대로다).
            if !typeSize.isAccessibilitySize {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

/// 버튼 판(캡슐 · 48 · 틴트). 눌림·소진을 **색으로만** 말한다.
private struct TetrisControlChrome: ViewModifier {
    /// 48 — `MobileTheme` 의 행 높이 표가 **미니게임 행**으로 이미 정해 둔 값이다(토큰이 아니라 그 표의 주석에 있다:
    /// "한 줄 44 · 두 줄 56 · 미니게임 48 · 팀 리그 64"). 순위 행(`minHeight: 48`)과 같은 수다.
    static let height: CGFloat = 48

    let width: CGFloat
    var isSpent = false
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            // 소진(홀드를 이미 씀)이면 틴트 채움을 없애고 글자·기호를 한 단계 내린다.
            // **`.disabled()` 를 쓰지 않는다**: 이 값은 조각마다 꺼졌다 켜져 판 후반 1.3조각/초로 깜빡이고,
            // 보이스오버가 비활성 요소를 건너뛰어 버튼이 목록에서 사라졌다 나타났다 한다.
            .foregroundStyle(isSpent ? MobileTheme.label2 : MobileTheme.accent)
            .frame(width: width, height: Self.height)
            .background(Capsule().fill(isSpent ? Color.clear : MobileTheme.accentTint))
            .overlay {
                if isSpent { Capsule().strokeBorder(MobileTheme.separator, lineWidth: 1) }
            }
            .opacity(isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// 터치-업 인사이드 버튼(즉시 내리기)의 모양. 눌림은 `ButtonStyle` 이 알려 준다.
private struct TetrisControlButtonStyle: ButtonStyle {
    let width: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(TetrisControlChrome(width: width, isPressed: configuration.isPressed))
    }
}
#endif
