import AppKit
import SwiftUI
import CheckCore

// MARK: - 1:1 길건너 창 화면 (SPEC v1.3 §9)
//
// `CheckCrossyDuelWindowController` 가 담는 화면이다: 로비(상대 고르기 · 순위 탭 · 내 전적 · 받은/보낸 신청) → 대결(준비 →
// 카운트다운 3·2·1 → 판 → 결과). 상태·동작은 전부 `CrossyDuelStore`(CheckCore)에 있고 여기는 **그리기와 탭 전달**만 한다.
//
// 이 화면이 지키는 약속(테트리스 화면에서 물려받은 것 + 길건너에서 새로 생긴 것):
//   · **Picker/Menu/TextField 를 쓰지 않는다**(ImageRenderer 가 노란 상자로 그리거나 아무것도 안 그린다). 전부 Button + Shape.
//   · ★ **판(`store.duel`)은 관찰 대상이 아니다.** 판 값(내 점수 · 죽음 · 부활 · 남은 시간 · 상대 점수)은 잎 뷰의 `TimelineView`
//     안에서 `store.raceSnapshot()` 하나로 읽는다(경주 띠 · 캔버스 · 죽은 횟수 · 상대 상태). 틱마다 `store.tick()`(인자 없이 —
//     v1.1 CC-1 단조 시계)을 부르는 곳은 캔버스 잎 하나다. 창이 숨어도 판은 스토어의 판 루프가 민다(테트리스 D10).
//   · 3D 판은 `CrossyScene.mac()`(잎 `@StateObject` 로 한 번) + `CrossySceneView` 만 쓴다 — **`CrossyGameView` 는 쓰지 않는다**
//     (허브 콜백이 솔로 라운드 토큰·순위·daily_crossy 로 샌다, MX:18·142). SCNView 는 countdown·playing·finished 에서만
//     마운트한다(v1.1 CC-26 — 로비 창 시험이 SCNView 를 실제 창에 올리지 않게).
//   · 경주 트랙의 상대 점수는 스냅숏 `opponentScore`(이미 프레임·DB max 가 된 값, §8.4) 그대로 — 화면은 그 값만 그린다.
//   · 문구는 `CrossyDuelText`(화면 글자)와 `CrossyDuelNoticeText`(안내·결과 사유, 코어) 두 표에만 있다.

/// 로비 왼쪽 열의 탭 — 상대 고르기 · 순위.
enum CrossyDuelLobbyTab: Equatable { case users, ranking }

// MARK: - 창 루트

struct CrossyDuelPanel: View {
    /// 창 콘텐츠 좌표 이름(캔버스 프레임을 창 기준으로 잴 때).
    nonisolated static let coordinateSpace = "crossy-duel-panel"

    let store: CrossyDuelStore
    /// 내 얼굴을 읽는 문(앱 배선이 WorkTimerStore 에서 읽는다 — 체스·테트리스와 같은 얼굴 값).
    var me: @MainActor () -> ChessPlayerFace = { ChessPlayerFace.fallback }
    /// 사람 아바타의 캐릭터 한 표를 읽는 곳. nil 이면 이니셜 대신 착용값(`characterHint`)으로 떨어진다.
    var safety: WorkTimerStore? = nil
    /// 스냅샷 전용: 목록을 ScrollView 대신 클립으로 그린다(ImageRenderer 는 ScrollView 안을 못 그린다). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false
    /// 스냅샷 전용: 판돈 창을 이 상대에게 띄운 채로 그린다. 앱은 nil.
    var previewStakeTarget: CrossyDuelUser? = nil
    /// 스냅샷 전용: 판돈 창에서 이 판돈을 고른 상태로. 앱은 nil.
    var previewStakeSelection: CrossyDuelStake? = nil
    /// 스냅샷 전용: [기권] 자리를 확인 상태로. 앱은 false.
    var previewConfirmResign: Bool = false
    /// 스냅샷 전용: 로비 탭. 앱은 nil(화면 @State 가 정한다).
    var previewLobbyTab: CrossyDuelLobbyTab? = nil
    /// 스냅샷 전용: 3D 판 대신 그릴 그림(오프스크린 `SCNRenderer` 로 찍은 344×356 장). **ImageRenderer 는 SCNView 를 빈 칸으로
    /// 그린다**(MC:91) — 이 그림이 있으면 SCNView 를 아예 마운트하지 않는다. 앱은 nil.
    var previewCanvas: CGImage? = nil
    /// 스냅샷 전용: 사람 아바타 캐릭터 표(스토어 없이 그리는 렌더 시험이 앱과 같은 얼굴을 보게). 앱은 nil — 루트의
    /// `.appUserAvatarCharacters(from: safety)` 가 표를 건다.
    var previewCharacters: AppUserCharacterDirectory? = nil
    /// 시험 전용: 캔버스가 실제로 놓인 자리(창 콘텐츠 좌표). 앱은 nil.
    var onCanvasFrame: (@MainActor (CGRect) -> Void)? = nil
    /// 이 창 자기 주사율(v1.1 CC-5 — 컨트롤러가 `.frameRate(_:)` 로 넣는다). nil 이면 공용 값.
    var frameRateMonitor: MiniGameFrameRateMonitor? = nil

    @State private var confirmResign = false
    @State private var stakeTarget: CrossyDuelUser?
    @State private var lobbyTab: CrossyDuelLobbyTab = .users

    private var activeStakeTarget: CrossyDuelUser? { stakeTarget ?? previewStakeTarget }
    private var activeTab: CrossyDuelLobbyTab { previewLobbyTab ?? lobbyTab }
    private var myUserID: String? { safety?.session?.userID.lowercased() }

    /// 창 컨트롤러의 주사율 모니터를 끼운다(창 파일의 `CrossyDuelPanel(store:me:safety:)` 생성 글자를 그대로 두려고 따로 뺐다).
    func frameRate(_ monitor: MiniGameFrameRateMonitor?) -> CrossyDuelPanel {
        var copy = self
        copy.frameRateMonitor = monitor
        return copy
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: CrossyDuelWindowLayout.headerSpacing) {
                CrossyDuelHeader(store: store)
                    .frame(height: CrossyDuelWindowLayout.headerHeight)
                content
                    .frame(width: CrossyDuelWindowLayout.innerWidth, height: CrossyDuelWindowLayout.bodyHeight,
                           alignment: .topLeading)
            }
            .padding(CrossyDuelWindowLayout.contentPadding)
            .modifier(CrossyDuelPreviewCharacters(directory: previewCharacters))
            if let target = activeStakeTarget, store.phase == .lobby {
                CrossyDuelStakePrompt(store: store, target: target, initialSelection: previewStakeSelection,
                                      onClose: { stakeTarget = nil })
            }
        }
        .frame(width: CrossyDuelWindowLayout.contentSize.width, height: CrossyDuelWindowLayout.contentSize.height,
               alignment: .topLeading)
        .background(CheckTheme.background)
        .foregroundStyle(CheckTheme.primaryText)
        .coordinateSpace(.named(Self.coordinateSpace))
        // 툴팁 말풍선 레이어 — 창 루트 하나(새 창 루트에는 이 한 줄이 반드시 있어야 말풍선이 뜬다).
        .checkTooltipLayer()
        // 사람 아바타의 캐릭터 한 표(v1.1 CC-7 — 다른 1:1 창과 같은 짝). 빠지면 로비·경주 띠의 남의 얼굴이 이니셜로 떨어진다.
        .appUserAvatarCharacters(from: safety)
        .onChange(of: store.match?.id) { _, _ in
            confirmResign = false
            // 판이 시작되면 로비가 사라진다 — 열려 있던 판돈 창을 들고 있으면 로비로 돌아올 때 되살아난다.
            stakeTarget = nil
        }
        // 기권 확인은 **그 판 그 화면에서 연 것**만 산다.
        .onChange(of: store.phase) { _, _ in confirmResign = false }
        .onChange(of: store.isWindowVisible) { _, _ in confirmResign = false }
        .onChange(of: lobbyTab) { _, tab in
            if tab == .ranking { Task { await store.refreshRanking() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let match = store.match, store.phase != .lobby {
            CrossyDuelMatchView(store: store, match: match, me: me(), myUserID: myUserID,
                                confirmResign: $confirmResign, showsConfirmPreview: previewConfirmResign,
                                previewCanvas: previewCanvas, frameRateMonitor: frameRateMonitor,
                                onCanvasFrame: onCanvasFrame)
        } else {
            CrossyDuelLobbyView(store: store, me: me(), myUserID: myUserID, tab: activeTab,
                                clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll,
                                onSelectTab: { lobbyTab = $0 }, onChallenge: { stakeTarget = $0 })
        }
    }
}

// MARK: - 머리글

private struct CrossyDuelHeader: View {
    let store: CrossyDuelStore

    private var activeMatch: CrossyDuelMatchState? {
        guard let match = store.match, store.phase != .lobby else { return nil }
        return match
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(CheckTheme.accent.opacity(0.18))
                Image(systemName: CrossyDuelEntryIcon.resolved)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(CrossyDuelText.title).font(.title3.weight(.bold))
                Text(CrossyDuelText.subtitle)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            Spacer(minLength: 12)
            if let match = activeMatch {
                if store.connectionTrouble {
                    Label(CrossyDuelText.connectionTrouble, systemImage: "wifi.exclamationmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.danger)
                }
                stakeChip(match.stake)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: CrossyDuelEntryIcon.resolved)
                    Text(recordLine).monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().stroke(CheckTheme.border, lineWidth: 1))
                .checkTooltip(CrossyDuelText.rankHelp)
                RubyBalanceChip(balance: store.rubyBalance, large: true)
                    .checkTooltip("내 루비")
            }
        }
    }

    /// 판 화면 판돈 칩(시안: 머리글 오른쪽 "판돈 5 · 이기면 +5", 순이익 숫자만 주황).
    private func stakeChip(_ stake: Int) -> some View {
        HStack(spacing: 4) {
            Text("\(CrossyDuelText.stakeTitle) \(stake) · 이기면")
            Text("+\(DuelFee.winnerNet(stake: stake))").foregroundStyle(CheckTheme.pending)
        }
        .font(.callout.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().stroke(CheckTheme.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CrossyDuelText.stakeChip(stake))
    }

    /// 전적 캡슐 — 로비 전적이 권위다. 순위 응답의 내 줄이 **같은 전적**일 때만 등수를 덧붙인다(두 출처를 섞지 않는다).
    private var recordLine: String {
        let record = CrossyDuelText.record(store.record)
        guard let mine = store.ranking?.me, let rank = mine.rank, let held = store.record,
              mine.wins == held.wins, mine.losses == held.losses, mine.draws == held.draws
        else { return record }
        return "\(record) · \(rank)위"
    }
}

// MARK: - 공용 조각

/// 스냅샷 전용 캐릭터 표(nil 이면 아무것도 안 한다 — 루트의 표가 그대로 내려간다).
private struct CrossyDuelPreviewCharacters: ViewModifier {
    let directory: AppUserCharacterDirectory?

    func body(content: Content) -> some View {
        if let directory {
            content.environment(\.appUserCharacters, directory)
        } else {
            content
        }
    }
}

extension View {
    /// 1:1 길건너 창 카드 크롬(테트리스·체스 창 카드와 같은 모양).
    func crossyDuelCard(padding: CGFloat = CrossyDuelWindowLayout.cardPadding) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CheckTheme.panel.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}

/// 스크롤 칸. 스냅샷에서는 **클립 갈래**로 그린다 — ImageRenderer 는 ScrollView 안을 못 그린다.
struct CrossyDuelScrollBox<Content: View>: View {
    let clips: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if clips {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct CrossyDuelNoticeLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
            Text(text).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(CheckTheme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
