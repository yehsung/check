import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// 게임 탭에서 쌓는 화면(경로 원소).
package enum GamesDestination: Hashable, Sendable {
    case miniGame(MiniGameKind)
    case gomoku
}

/// 딥링크 한 건을 게임 탭 경로에 옮기는 동작(`GamesStore.routeStep(for:)`). 뷰는 돌려받은 대로 경로만 바꾼다.
package enum GamesRouteStep: Equatable, Sendable {
    case popToRoot
    case push(GamesDestination)
}

/// 게임 탭 스토어(SPEC-ios §3.5) — 탭 자리 API 를 지키고, 두 갈래를 잇는다.
///
/// 1. **미니게임** — `miniGames`(`GamesMiniGameHub`): 오늘 순위 · 로컬 최고 · 라운드 토큰 · 제출. 엔진은 코어 규칙.
/// 2. **1:1 오목** — 코어 `GomokuStore`(context.gomoku, host = 폰 세션). 이 스토어는 **창 수명**을 폰 수명에 옮긴다:
///    맥의 창 표시·숨김(`windowDidShow/Hide`)은 폰에서 "오목 화면이 보이고 앱이 active 인가"다.
///    - 오목 화면이 나타남 → `openWindow`(로비·인박스·진행 판) + active 면 `windowDidShow`(폴링 시작).
///    - 화면이 사라짐 → `windowDidHide`(폴링을 멈추고, 결과 화면이었으면 그 판에서 나간다 — **대국은 서버에서 계속 흐른다**).
///    - 앱이 background → **가림**(`windowOcclusionDidChange(visible: false)`) — 폴링만 멈추고 판에서 나가지 않는다.
///    - 앱이 active 로 돌아옴(화면이 보이는 채) → 가림 해제(또는 `windowDidShow`) + 따라잡기(인박스 + 진행 판의 놓친 수).
///    - 판이 막 시작됨(`presentWindow`) → 앱이 active 면 오목 화면을 연다(신청자가 수락된 순간을 모르면 흑 30초를 흘린다).
/// 3. **AI 대국**(1.0.1) — 규칙·판·서버 차단은 코어(`GomokuStoreAI`, 맥과 한 벌). 이 스토어는 폰 선택기(`aiThinker`)를 코어에 끼우고
///    "오목 화면이 보이고 앱이 active 인가"를 그 선택기의 허락으로 옮긴다 — 떠나면 AI 탐색을 취소하고 돌아오면 다시 생각한다
///    (`GamesGomokuAI.swift` 머리 주석). 사람 시계 멈춤은 위 창 수명(숨김·가림)이 코어에서 이미 한다.
///
/// 탭 배지 = 받은 오목 신청 수(만료 안 된 것). 받은 신청은 인박스가 채운다 — 계기는 앱 active(60초 스로틀) · 실시간
/// 'gomoku' 신호(기반 배선) · 오목 화면.
@MainActor
@Observable
package final class GamesStore {
    @ObservationIgnored package let context: MobileContext
    package let miniGames: GamesMiniGameHub

    /// 오목 화면이 지금 떠 있다(내비게이션에 올라와 보인다).
    package private(set) var isGomokuScreenVisible = false
    /// 앱이 active 다(로그인 상태에서 appDidBecomeActive ~ appDidEnterBackground).
    package private(set) var isAppActive = false
    /// 오목 화면을 열 때 보여 줄 신청·판 id(딥링크 `gomoku/invite/<id>` · `gomoku/match/<id>`). 화면이 한 번 꺼내 쓴다.
    /// 화면이 **이미 보이면** 여기 남기지 않는다(`routeStep(for:)` 이 코어에 바로 넘긴다).
    package var pendingGomokuFocusID: String?

    /// AI 대국의 수 선택기(코어 `aiMoveChooser` 에 끼운다). 사람 대국은 이것을 한 번도 부르지 않는다.
    @ObservationIgnored package let aiThinker = GamesGomokuAIThinker()

    /// 화면 꺼짐 방지를 실제로 거는 곳(iOS 는 init 이 `GamesSystemIdleTimer` 를 단다 · 테스트는 기록용).
    @ObservationIgnored private var idleTimerSink: (@MainActor (Bool) -> Void)?
    /// 마지막으로 싱크에 넘긴 값(같은 값은 다시 넘기지 않는다). 싱크가 없으면 nil.
    @ObservationIgnored package private(set) var appliedIdleTimerDisabled: Bool?

    package init(context: MobileContext) {
        self.context = context
        miniGames = GamesMiniGameHub(context: context)
        // 판이 막 시작됐다(내 신청이 수락됨 · 내가 수락함 · 앱을 다시 켜니 진행 중인 판) — 오목 화면을 연다.
        // 네트워크가 아니라 문을 다는 것이라 init 에서 해도 된다.
        context.gomoku.presentWindow = { [weak self] in self?.presentGomokuScreen() }
        // AI 대국: 코어 기본 선택기(창을 몰라 떠나도 계속 생각한다 — 맥 동작) 대신 화면 수명을 아는 폰 선택기. 문을 다는 것뿐이다.
        context.gomoku.aiMoveChooser = aiThinker.chooser
        aiThinker.isStillNeeded = { [weak gomoku = context.gomoku] board, color in
            guard let gomoku, gomoku.isAIThinking, let game = gomoku.aiGame else { return false }
            return game.board == board && game.aiColor == color
        }
        #if os(iOS)
        // 화면 꺼짐 방지의 주인은 이 스토어다 — 게임 탭을 한 번도 안 열었어도(다른 탭에서 판이 시작돼도) 값이 따라간다.
        installIdleTimerSink { GamesSystemIdleTimer.apply(disabled: $0) }
        #endif
    }

    // MARK: 자리 API

    package func appDidBecomeActive() {
        isAppActive = true
        syncAIThinker()
        // background 로 가며 끝낸 판의 제출이 네트워크로 실패했으면 **같은 토큰으로** 한 번 더(세 게임 모두).
        miniGames.retryPendingSubmitIfAny()
        let gomoku = context.gomoku
        // 받은 신청(탭 배지·첫 화면 카드)의 신선도. 60초 스로틀은 코어가 한다.
        gomoku.refreshInboxIfStale()
        guard isGomokuScreenVisible else { return }
        if gomoku.isWindowVisible {
            // background 에서 '가림'으로 멈춰 둔 폴링을 되살린다(창은 닫힌 적이 없다).
            gomoku.windowOcclusionDidChange(visible: true)
        } else {
            gomoku.windowDidShow()
        }
        // background 동안 놓친 것(신청·수락·상대 수). 서버 시계는 그동안에도 흘렀다.
        Task { await gomoku.catchUp() }
    }

    package func appDidEnterBackground() {
        isAppActive = false
        // AI 탐색은 background 에서 돌지 않는다(돌아오면 처음부터 다시 생각한다).
        syncAIThinker()
        miniGames.appDidEnterBackground()
        // 오목은 **가림**으로 멈춘다(`windowOcclusionDidChange(visible: false)`) — 폴링만 멈추고 창은 닫지 않는다.
        // `windowDidHide` 를 부르면 결과 화면인 채로 잠깐 앱을 나갔을 뿐인데 그 판에서 '나간' 것이 되어(gomoku_leave)
        // 두 사람이 다 나간 판의 인사 채팅이 서버에서 지워진다.
        if isGomokuScreenVisible, context.gomoku.isWindowVisible {
            context.gomoku.windowOcclusionDidChange(visible: false)
        }
    }

    package func reset() {
        miniGames.reset()
        isGomokuScreenVisible = false
        pendingGomokuFocusID = nil
        syncAIThinker()
    }

    /// 탭 배지: 만료 안 된 받은 오목 신청 수.
    package var badgeCount: Int { context.gomoku.pendingIncomingInvites.count }

    /// 게임 탭이 보여 주는 루비 잔액 — **공유 미러**(`context.gomokuHost.rubyBalance`)를 먼저 읽는다(통합 w4/int).
    /// 미러에는 두 쓰기가 모두 온다: 오목 응답 정산(코어 `applyRuby` 가 코어 값과 미러를 함께 적는다) · 나 탭 상점(`shop_state` · 구매 응답은
    /// 미러만 적는다). 코어 값을 먼저 읽으면 나 탭에서 캐릭터를 산 뒤 다음 오목 조회 전까지 옛 잔액이 보였다. 미러를 모르면 코어 값.
    package var rubyBalance: Int? { context.gomokuHost.rubyBalance ?? context.gomoku.rubyBalance }

    /// 오목 로비의 **상대 고르기 목록** — 차단해 숨긴 사람을 걷어낸 것. 화면이 읽는 자리는 여기 하나다.
    ///
    /// 차단 확인 시트가 "사람 찾기와 오목 신청에서 서로 보이지 않아요" 라고 약속하는데, 코어 `users` 는 서버 로비 응답 그대로라
    /// 방금 차단한 사람이 [도전] 버튼과 함께 그대로 서 있었다 — 사용자가 방금 읽은 세 줄 중 한 줄이 눈앞에서 거짓이 된다
    /// (메시지 탭 `filteredDirectory` 와 같은 근거 · 같은 방식).
    /// **거르는 것은 화면이 읽는 이 자리뿐**이다: 코어 목록은 서버가 답한 그대로 둬야 차단이 실패했을 때 그대로 돌아온다.
    /// 서버도 로비 응답에서 서로 차단한 사람을 빼 줘야 **반대쪽**에서도 사라진다(작업 S — `gomoku_lobby`).
    package var gomokuLobbyUsers: [GomokuUser] {
        let hidden = context.links.messages?.hiddenBlockedPeerIDs ?? []
        guard !hidden.isEmpty else { return context.gomoku.users }
        return context.gomoku.users.filter { !hidden.contains($0.id) }
    }

    // MARK: 첫 화면

    /// 게임 탭 첫 화면이 보였다: 카드의 오늘 최고·순위 · 받은 신청.
    package func hubDidAppear() {
        guard context.session.isSignedIn else { return }
        miniGames.refreshSummariesIfStale()
        context.gomoku.refreshInboxIfStale()
    }

    /// 오목 카드의 한 줄 재료: 진행 중인 판이 있는가(서버가 말한 진행 판 id 또는 들고 있는 끝나지 않은 판).
    package var hasActiveGomokuMatch: Bool {
        let gomoku = context.gomoku
        if let match = gomoku.match, !match.isFinished { return true }
        return gomoku.activeMatchID != nil
    }

    // MARK: 오목 화면 수명

    /// 오목 화면이 나타났다.
    package func gomokuScreenDidAppear() {
        let gomoku = context.gomoku
        // 먼저 적는다 — openWindow 가 presentWindow 를 부르고, 그 문이 "이미 보인다"를 봐야 화면을 또 열지 않는다.
        isGomokuScreenVisible = true
        let focus = pendingGomokuFocusID
        pendingGomokuFocusID = nil
        gomoku.openWindow(focusMatchID: focus)
        if isAppActive { gomoku.windowDidShow() }
        syncAIThinker()
    }

    /// 오목 화면이 사라졌다(뒤로 · 다른 탭으로 · 로그아웃). 폴링만 멈춘다. 결과 화면인 채로 떠나면 코어가 그 판에서 나간다.
    package func gomokuScreenDidDisappear() {
        guard isGomokuScreenVisible else { return }
        isGomokuScreenVisible = false
        context.gomoku.windowDidHide()
        syncAIThinker()
    }

    /// AI 선택기의 허락 = 오목 화면이 보이고 앱이 active. 거두면 도는 탐색이 곧바로 취소된다.
    private func syncAIThinker() {
        aiThinker.setAllowed(isGomokuScreenVisible && isAppActive)
    }

    /// 대국 중이라 화면이 꺼지면 안 된다(`UIApplication.isIdleTimerDisabled`, SPEC-ios §3.5). 앱이 active 이고 끝나지 않은 판이 있을 때.
    /// **어느 화면에 있든 같다**(오목 화면 밖 — 게임 첫 화면 · 다른 탭 — 에서도 판이 도는 동안은 켠다).
    ///
    /// AI 판만 예외: 오목 화면이 보일 때만 켠다. 화면을 떠나면 사람 시계가 멈추고 AI 도 생각하지 않는다 — 기다릴 것이 없는데
    /// 다른 탭에서 화면을 켜 둘 까닭이 없다(1:1 은 서버 시계가 흐르므로 그대로다).
    package var wantsIdleTimerDisabled: Bool {
        guard isAppActive, context.session.isSignedIn else { return false }
        // 미니게임: 끝나지 않은 판이 있으면 켠다. **지금까지 미니게임은 아예 보호받지 않았다** — 플래피는 한 판이
        // 30초 남짓이라 자동잠금(최소 30초)에 닿을 일이 없어 드러나지 않았을 뿐이다. 폰은 background 가 곧
        // **판 폐기·무제출**(`GamesMiniGameHub.appDidEnterBackground`)이라 자동잠금이 곧 판 폐기이고, 조각을 세워 두고
        // 생각하는 무입력 구간이 있는 게임(테트리스)이 들어오면 그 구멍이 바로 열린다.
        //
        // ★ **타이밍 바만 뺀다.** 그 판은 **스스로 끝나지 않는다** — `phase` 가 탭을 받을 때까지 `.running` 에 머문다
        // (`TimingBarGame.isPlaying`). 그래서 판을 켜 둔 채 자리를 뜨면 화면이 **영원히** 켜져 있다. 자동잠금이 그
        // 유일한 상한이었고, 여기에 타이밍 바를 넣으면 그 상한이 사라진다. 플래피(새가 떨어져 끝난다)와 테트리스
        // (쌓여서 탑아웃한다)는 방치해도 엔진이 판을 끝내므로 안전하다. 새 게임을 더할 때 이 성질을 확인할 것.
        if let controller = miniGames.controller, controller.isPlaying, controller.kind != .timingBar { return true }
        guard let match = context.gomoku.match else { return false }
        if context.gomoku.isAIMatch { return !match.isFinished && isGomokuScreenVisible }
        return !match.isFinished
    }

    // MARK: 화면 꺼짐 방지(주인은 이 스토어 하나)

    /// 화면 꺼짐 방지 싱크를 단다(첫 한 번만 — 뒤의 호출은 무시). 이후 `wantsIdleTimerDisabled` 가 바뀔 때마다 이 스토어가 넘긴다.
    /// iOS 는 init 이 시스템 대입(`GamesSystemIdleTimer`)을 단다. macOS 테스트는 기록용 싱크를 단다.
    ///
    /// 예전에는 오목 화면(onDisappear 에서 무조건 false · onChange)과 게임 첫 화면(onChange)이 제각각 썼다. 대국 중 [뒤로]로
    /// 오목 화면을 떠나면 false 가 써지고, 첫 화면의 onChange 는 값이 안 바뀌어 다시 쓰지 않아, 같은 상태인데 이동 경로에 따라
    /// 값이 달랐다(games-verify probe-back). 이제 어느 뷰도 이 값을 쓰지 않는다.
    package func installIdleTimerSink(_ sink: @escaping @MainActor (Bool) -> Void) {
        guard idleTimerSink == nil else { return }
        idleTimerSink = sink
        syncIdleTimer()
    }

    /// 지금 값을 싱크에 넘기고, 재료(앱 active · 로그인 · 판)가 바뀌면 다시 불리도록 관찰을 건다(한 줄로 이어지는 관찰 하나).
    private func syncIdleTimer() {
        guard let sink = idleTimerSink else { return }
        let wants = withObservationTracking {
            wantsIdleTimerDisabled
        } onChange: { [weak self] in
            // willSet 에서 불린다 — 값이 실제로 바뀐 뒤에 읽도록 다음 차례로 미룬다.
            Task { @MainActor [weak self] in self?.syncIdleTimer() }
        }
        guard appliedIdleTimerDisabled != wants else { return }
        appliedIdleTimerDisabled = wants
        sink(wants)
    }

    // MARK: 딥링크

    /// 게임 탭이 꺼낸 딥링크(`router.consumePendingRoute(for: .games)`)를 경로 동작으로 바꾼다. 게임 탭 밖 라우트면 nil.
    ///
    /// 오목 라우트에서 **오목 화면이 이미 보이면** 대상 id 를 코어에 바로 넘긴다(`openWindow(focusMatchID:)`). 라우터가 경로를
    /// [오목] → [] → [오목] 으로 한 번에 바꾸면 SwiftUI 는 같은 화면으로 보아 onDisappear/onAppear 를 부르지 않으므로,
    /// `gomokuScreenDidAppear` 에 기대면 대상이 적용되지 않고 남아 나중의 무관한 진입에 쓰였다(games-verify probe-focus).
    /// 경로는 그래도 다시 쌓는다 — 라우터가 비운 경로를 되돌려야 화면이 닫히지 않는다.
    package func routeStep(for route: AingRoute) -> GamesRouteStep? {
        switch route {
        case .games:
            return .popToRoot
        case .miniGame(let game):
            return .push(.miniGame(game == .timing ? .timingBar : .flappy))
        case .gomokuLobby, .gomokuMatch(matchID: nil):
            openGomoku(focusID: nil)
            return .push(.gomoku)
        case .gomokuInvite(let id), .gomokuMatch(matchID: .some(let id)):
            openGomoku(focusID: id)
            return .push(.gomoku)
        default:
            return nil
        }
    }

    private func openGomoku(focusID: String?) {
        guard isGomokuScreenVisible else {
            // 화면이 곧 나타난다(push) — 나타날 때 꺼내 쓴다.
            pendingGomokuFocusID = focusID
            return
        }
        pendingGomokuFocusID = nil
        context.gomoku.openWindow(focusMatchID: focusID)
    }

    private func presentGomokuScreen() {
        guard isAppActive, context.session.isSignedIn, !isGomokuScreenVisible else { return }
        context.router.open(.gomokuMatch(matchID: nil))
    }
}
