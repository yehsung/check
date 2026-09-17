import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// 푸시 받기 — **자리 파일**(D-base 가 만들고 D9 가 통째로 소유한다. SPEC-ios §5).
///
/// 자리 API(기반이 부르는 것 — 이름·모양을 지킨다)
/// - `init(context:)` · `appDidBecomeActive()` · `appDidEnterBackground()` · `reset()` — 탭 스토어와 같은 수명 규칙.
/// - `sessionDidSignIn()` — 로그인 상태가 된 순간(실행 복원 포함). 권한 요청 설명 시트·등록을 여기서 시작한다.
/// - `didRegisterForRemoteNotifications(deviceToken:)` / `didFailToRegisterForRemoteNotifications(error:)` —
///   `UIApplicationDelegate` 어댑터(ios/App/AppDelegate.swift)가 `MobileAppModel` 의 public 전달을 거쳐 부른다.
///
/// 기반이 이미 해 둔 것: 토큰 hex → `context.session.updateAPNsToken(_:)`(바뀌면 즉시 register_device, 환경은 Info.plist
/// `AingAPNsEnvironment` — Debug sandbox / Release production). 앱 배지 합은 `context.links.badges.appBadgeTotal`,
/// 지금 보고 있는 대화는 `context.router.visibleConversationPeerID`, 알림 설정 저장은 `context.session.savePushPrefs(_:)`.
/// 더 많은 public 전달이 필요하면 이 폴더에 `public extension MobileAppModel` 파일을 더한다(App 폴더를 고치지 않는다).
@MainActor
@Observable
package final class PushCoordinator {
    @ObservationIgnored package let context: MobileContext

    package init(context: MobileContext) {
        self.context = context
    }

    package func appDidBecomeActive() {}

    package func appDidEnterBackground() {}

    package func reset() {}

    package func sessionDidSignIn() {}

    package func didRegisterForRemoteNotifications(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        context.session.updateAPNsToken(hex)
    }

    package func didFailToRegisterForRemoteNotifications(error: Error) {
        // 시뮬레이터·권한 없음에서 온다. 조용히 넘기고 다음 실행 때 다시 시도한다.
    }
}
