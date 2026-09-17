import CheckMobileKit
import SwiftUI

/// aing-check iOS 앱 진입점. **껍데기만 둔다** — 화면과 스토어는 패키지 모듈(CheckMobileKit)에 있다.
///
/// 앱 모델은 앱 델리게이트가 만든다(푸시 토큰 콜백이 같은 모델에 닿아야 한다). 루트 화면은 그 모델 하나를 받는다.
@main
struct AingCheckApp: App {
    @UIApplicationDelegateAdaptor(AingCheckAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MobileRootView(model: appDelegate.model)
        }
    }
}
