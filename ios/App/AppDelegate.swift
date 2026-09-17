import CheckMobileKit
import UIKit

/// `UIApplicationDelegate` 어댑터 — 앱 모델을 만들고, 원격 알림 콜백을 모델(→ PushCoordinator)로 넘긴다.
/// 본문은 D9(푸시 받기)가 소유한다. 알림 센터 delegate·카테고리 등록은 PushCoordinator 안에서 한다.
@MainActor
final class AingCheckAppDelegate: NSObject, UIApplicationDelegate {
    /// 앱 실행 동안 하나. DEBUG 빌드의 `-AingCheckDemo YES` 면 데모 조립이다.
    /// `lazy` 인 이유: 델리게이트 init 은 메인 액터 밖에서 불릴 수 있어 기본값 식에서 메인 액터 함수를 부르지 않는다.
    lazy var model: MobileAppModel = MobileAppModel.bootstrap()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        model.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        model.didFailToRegisterForRemoteNotifications(error: error)
    }
}
