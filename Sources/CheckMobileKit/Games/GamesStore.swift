import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// 게임 탭 스토어 — **자리 파일**(D-base 가 만들고 탭 작업자가 통째로 소유한다. SPEC-ios §3.5).
///
/// 자리 API(기반이 부르는 것 — 이름·모양을 지킨다)
/// - `init(context:)` — 앱 모델이 로그인 여부와 무관하게 한 번 만든다. 여기서 네트워크를 부르지 않는다.
/// - `appDidBecomeActive()` — 로그인 상태에서 앱이 active 가 될 때 · active 인 채로 로그인이 끝났을 때.
/// - `appDidEnterBackground()` — 앱이 background 로 갈 때(주기 작업을 멈춘다).
/// - `reset()` — 로그아웃·치명 만료로 세대가 바뀐 직후(계정에 묶인 값을 전부 비운다).
/// - `badgeCount` — 탭 배지. 받은 오목 신청 수(`context.gomoku.pendingIncomingInvites.count` 등).
@MainActor
@Observable
package final class GamesStore {
    @ObservationIgnored package let context: MobileContext
    /// 자리 화면이 마지막으로 꺼낸 딥링크(탭 작업자가 지운다).
    package var lastRoute: AingRoute?

    package init(context: MobileContext) {
        self.context = context
    }

    package func appDidBecomeActive() {}

    package func appDidEnterBackground() {}

    package func reset() {
        lastRoute = nil
    }

    package var badgeCount: Int { 0 }
}
