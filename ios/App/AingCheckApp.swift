import CheckMobileKit
import SwiftUI
import UIKit

/// aing-check iOS 앱 진입점. **껍데기만 둔다** — 화면과 스토어는 패키지 모듈(CheckMobileKit)에 있다.
@main
struct AingCheckApp: App {
    @UIApplicationDelegateAdaptor(AingCheckAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            CheckMobileRootView()
        }
    }
}

/// 푸시 등록 자리(D9). 지금은 아무것도 등록하지 않는다.
///
/// 순서(D9 에서 채운다): 로그인 → `UNUserNotificationCenter.requestAuthorization` →
/// `UIApplication.registerForRemoteNotifications()` → 아래 콜백의 토큰(hex 소문자)을
/// `register_device(p_apns_token:, p_apns_env:)` 로 보낸다. 토큰이 바뀌면 같은 콜백이 다시 온다.
/// 권한 거부·로그아웃은 `unregister_device` 로 정리한다(서버 계약 1.4).
@MainActor
final class AingCheckAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // D9: let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // D9: 시뮬레이터·권한 없음에서 온다. 조용히 넘기고 다음 실행 때 다시 시도한다.
    }
}
