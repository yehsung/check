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
        #if os(iOS)
        // 화면 꺼짐 방지의 주인은 이 스토어다 — 게임 탭을 한 번도 안 열었어도(다른 탭에서 판이 시작돼도) 값이 따라간다.
        installIdleTimerSink { GamesSystemIdleTimer.apply(disabled: $0) }
        #endif
    }

    // MARK: 자리 API

    package func appDidBecomeActive() {
        isAppActive = true
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
    }

    /// 탭 배지: 만료 안 된 받은 오목 신청 수.
    package var badgeCount: Int { context.gomoku.pendingIncomingInvites.count }

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
    }

    /// 오목 화면이 사라졌다(뒤로 · 다른 탭으로 · 로그아웃). 폴링만 멈춘다. 결과 화면인 채로 떠나면 코어가 그 판에서 나간다.
    package func gomokuScreenDidDisappear() {
        guard isGomokuScreenVisible else { return }
        isGomokuScreenVisible = false
        context.gomoku.windowDidHide()
    }

    /// 대국 중이라 화면이 꺼지면 안 된다(`UIApplication.isIdleTimerDisabled`, SPEC-ios §3.5). 앱이 active 이고 끝나지 않은 판이 있을 때.
    /// **어느 화면에 있든 같다**(오목 화면 밖 — 게임 첫 화면 · 다른 탭 — 에서도 판이 도는 동안은 켠다).
    package var wantsIdleTimerDisabled: Bool {
        guard isAppActive, context.session.isSignedIn, let match = context.gomoku.match else { return false }
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
