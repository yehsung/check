import SwiftUI
import CheckCore

// MARK: - 1:1 알까기 창 루트(SPEC v1.1 §5)
//
// `CheckAlkkagiWindowController` 가 담는 화면이다: 로비(상대 고르기 · 순위 · 내 전적 · 지금 대결 중 · 신청 — §5.3) →
// 판(`AlkkagiGameView` — 판 그림·손맛 그대로, 오른쪽 열은 §5.5) → 결과(§5.6), 그리고 남의 판 관전(§5.7)과 연습 판.
// 상태·동작은 전부 `AlkkagiOnlineStore`(CheckCore)에 있고 여기는 **그리기와 탭 전달**만 한다.
//
// 이 화면이 지키는 약속(뒤집기 `ReversiPanel` 과 같다):
//   · **보임 통지는 창 컨트롤러만 한다**(DF#46). 패널이 `onAppear`/`onDisappear` 로 `windowDidShow`/`windowDidHide` 를 부르면
//     로비↔판 전환마다 불려 `isWindowVisible` 이 거짓으로 남을 수 있다 — 그 일은 창의 show/최소화/되살림/닫기 통지가 한다.
//   · Picker/Menu/TextField 를 쓰지 않는다(ImageRenderer 가 못 그린다). 덮개는 **한 번에 하나**(규칙 → 판돈).
//   · 창 루트 짝: 말풍선 층(`.checkTooltipLayer()`) + 사람 아바타 캐릭터 표(`.appUserAvatarCharacters(from: safety)`).
//   · 독립 실행기(§5.10)는 이 파일을 빌드하지 않는다(로컬 연습만).

struct AlkkagiOnlinePanel: View {
    @Bindable var store: AlkkagiOnlineStore
    /// 사람 아바타의 캐릭터 한 표를 읽는 곳(앱 배선이 `WorkTimerStore` 를 넘긴다 — T).
    var safety: WorkTimerStore? = nil
    /// 창 컨트롤러가 넣는 주사율 감시 — 판 화면(`AlkkagiGameView`)에 그대로 넘긴다.
    var frameRateMonitor: MiniGameFrameRateMonitor?
    /// 스냅샷 전용: 목록을 ScrollView 대신 클립으로 그린다(ImageRenderer 는 ScrollView 안을 못 그린다). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false
    /// 스냅샷 전용: 판돈 창을 이 상대에게 띄운 채로 그린다. 앱은 nil.
    var previewStakeTarget: AlkkagiLobbyUser? = nil
    /// 스냅샷 전용: 규칙 창을 띄운 채로 그린다. 앱은 false.
    var previewRules: Bool = false
    /// 스냅샷 전용: 판 [기권] 자리를 확인 상태로 그린다. 앱은 false.
    var previewConfirmResign: Bool = false
    /// 스냅샷 전용: 판 화면 모델(렌더 시험이 `attachOnline` 을 미리 붙여 넣는다 — ImageRenderer 는 onAppear 를 믿을 수 없다).
    var previewModel: AlkkagiLocalModel? = nil
    /// 스냅샷 전용: 사람 아바타 캐릭터 표(길건너 `previewCharacters` 꼴). 앱은 nil — `.appUserAvatarCharacters(from: safety)` 가 표를 건다.
    var previewCharacters: AppUserCharacterDirectory? = nil

    @State private var showsPractice = false
    @State private var rulesVisible = false
    /// [도전]을 누른 상대 — 판돈 창이 이 값으로 열린다. nil 이면 닫혀 있다.
    @State private var stakeTarget: AlkkagiLobbyUser?

    private var activeStakeTarget: AlkkagiLobbyUser? { stakeTarget ?? previewStakeTarget }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .modifier(AlkkagiPreviewCharacters(directory: previewCharacters))
            // 덮개는 **한 번에 하나**다 — 규칙 → 판돈 순(판·연습 화면에선 판돈 창이 서지 않는다).
            if rulesVisible || previewRules {
                AlkkagiRulesPrompt(onClose: { rulesVisible = false })
            } else if store.state == nil, !showsPractice, let target = activeStakeTarget {
                AlkkagiStakePrompt(store: store, target: target, onClose: { stakeTarget = nil })
            }
        }
        .frame(width: BoardGameLayout.contentSize.width, height: BoardGameLayout.contentSize.height,
               alignment: .topLeading)
        .background(CheckTheme.background)
        .foregroundStyle(CheckTheme.primaryText)
        // 툴팁 말풍선 레이어 — 창 루트 하나(판 화면 · 연습 화면 · 로비 · 덮개 모두 이 안쪽).
        .checkTooltipLayer()
        // 사람 아바타의 캐릭터 한 표. nil 이면 빈 표 = 모르는 사람은 착용값·그마저 없으면 이니셜.
        .appUserAvatarCharacters(from: safety)
        .onChange(of: store.state?.id) { _, id in
            // 판이 시작되면 로비가 사라진다 — 열려 있던 판돈 창을 들고 있으면 로비로 돌아올 때 되살아난다.
            stakeTarget = nil
            if id != nil { showsPractice = false }
        }
    }

    @ViewBuilder
    private var content: some View {
        if showsPractice {
            paced(AlkkagiGameView(onReturn: { showsPractice = false }))
        } else if store.state != nil {
            paced(gameView)
        } else {
            VStack(alignment: .leading, spacing: ReversiWindowLayout.headerSpacing) {
                AlkkagiLobbyHeader(store: store,
                                   onPractice: { showsPractice = true },
                                   onRules: { rulesVisible = true })
                    .frame(height: ReversiWindowLayout.headerHeight)
                Group {
                    // 관전은 로비 자리에 선다(다수 4/4 — §5.7).
                    if let watched = store.watched {
                        AlkkagiSpectateView(store: store, watch: watched)
                    } else {
                        lobby
                    }
                }
                .frame(width: ReversiWindowLayout.innerSize.width, height: ReversiWindowLayout.bodyHeight,
                       alignment: .topLeading)
            }
            .padding(ReversiWindowLayout.contentPadding)
        }
    }

    private var gameView: AlkkagiGameView {
        var view = previewModel.map { AlkkagiGameView(onlineStore: store, model: $0) } ?? AlkkagiGameView(onlineStore: store)
        view.previewConfirmResign = previewConfirmResign
        return view
    }

    private func paced(_ view: AlkkagiGameView) -> AlkkagiGameView {
        var view = view
        view.frameRateMonitor = frameRateMonitor
        return view
    }

    /// 로비는 **세 열**이다: 상대 목록 420 · 순위 340 · 오른쪽 400(뒤집기 상수 그대로 — §5.3).
    private var lobby: some View {
        HStack(alignment: .top, spacing: ReversiWindowLayout.columnSpacing) {
            DuelRoomsLobbyColumn(game: .alkkagi) {
                AlkkagiOpponentList(store: store, clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll,
                                    onChallenge: { stakeTarget = $0 })
            }
                .frame(width: ReversiWindowLayout.lobbyUsersWidth, height: ReversiWindowLayout.bodyHeight,
                       alignment: .top)
                .clipped()
            AlkkagiRankColumn(store: store, clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                .frame(width: ReversiWindowLayout.lobbyRankWidth, height: ReversiWindowLayout.bodyHeight,
                       alignment: .top)
                .clipped()
            AlkkagiLobbySide(store: store, clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                .frame(width: ReversiWindowLayout.lobbySideWidth, height: ReversiWindowLayout.bodyHeight,
                       alignment: .top)
                .clipped()
        }
    }
}

/// 스냅샷 전용 캐릭터 표(있을 때만 — 안쪽 환경이 창 루트의 표를 덮는다).
private struct AlkkagiPreviewCharacters: ViewModifier {
    let directory: AppUserCharacterDirectory?

    func body(content: Content) -> some View {
        if let directory {
            content.environment(\.appUserCharacters, directory)
        } else {
            content
        }
    }
}

// MARK: - 로비 머리글(§5.2 — 뒤집기 `ReversiHeader` 꼴, 높이 40)

/// 왼쪽: 38pt 원 아이콘 · 제목 · 부제. 오른쪽: 전적 캡슐 · 루비 칩(large) · [연습하기](로비에서만 — 관전 중엔 숨김) · [규칙].
/// [새로고침] · [게임 목록] 은 없다(새로고침은 실패 상태의 [다시 불러오기], 닫기는 빨간 점 — DF#4).
private struct AlkkagiLobbyHeader: View {
    let store: AlkkagiOnlineStore
    var onPractice: () -> Void = {}
    var onRules: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(CheckTheme.accent.opacity(0.18))
                Image(systemName: AlkkagiEntryIcon.resolved)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(AlkkagiText.title).font(.title3.weight(.bold))
                Text(AlkkagiText.subtitle)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            Spacer(minLength: 12)
            HStack(spacing: 5) {
                Image(systemName: "flag.checkered")
                Text(AlkkagiRecordSource.headerLine(store)).monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(CheckTheme.border, lineWidth: 1))
            .checkTooltip(AlkkagiText.rankHelp)
            RubyBalanceChip(balance: store.rubyBalance, large: true)
                .checkTooltip(AlkkagiText.myRubyHelp)
            if store.watched == nil {
                ChessActionButton(title: AlkkagiText.practiceButton, icon: "figure.2", style: .outline, height: 30,
                                  action: onPractice)
                    .checkTooltip(AlkkagiText.practiceHelp)
            }
            ChessActionButton(title: AlkkagiText.rulesButton, icon: "book.fill", style: .outline, height: 30,
                              action: onRules)
                .checkTooltip(AlkkagiText.rulesHelp)
        }
    }
}
