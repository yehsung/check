import CheckMobileKit
import UIKit

/// `UIApplicationDelegate` 어댑터 — 앱 모델을 만들고, 원격 알림 콜백을 모델(→ PushCoordinator)로 넘긴다.
/// 판단은 패키지(CheckMobileKit/Push)가 한다. 여기는 시스템 콜백을 옮기기만 한다.
@MainActor
final class AingCheckAppDelegate: NSObject, UIApplicationDelegate {
    /// 앱 실행 동안 하나. DEBUG 빌드의 `-AingCheckDemo YES` 면 데모 조립이다.
    /// `lazy` 인 이유: 델리게이트 init 은 메인 액터 밖에서 불릴 수 있어 기본값 식에서 메인 액터 함수를 부르지 않는다.
    lazy var model: MobileAppModel = MobileAppModel.bootstrap()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 알림 센터 delegate 는 **여기서** 붙어야 한다 — 알림을 눌러 앱이 켜지면 응답 콜백이 이 함수 직후에 온다.
        // 카테고리(MESSAGE · GOMOKU_INVITE 수락 · FEEDBACK_REPLY)도 같은 자리에서 등록한다.
        model.installPushNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        model.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        model.didFailToRegisterForRemoteNotifications(error: error)
    }
}
