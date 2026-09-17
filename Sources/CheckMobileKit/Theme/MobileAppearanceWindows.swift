#if os(iOS)
import os
import UIKit

/// 화면 모드를 **앱의 모든 창**에 건다(`UIWindow.overrideUserInterfaceStyle`).
///
/// 트레이트는 창에서 아래로 흐른다 — 루트 SwiftUI 화면 · SwiftUI 시트 · 확인 창 · UIKit 으로 띄운 `UIHostingController`(알림 설명 시트) ·
/// 공유 시트가 그 창의 자식이라 한 번에 같은 모드가 된다. `MobileTheme` 은 동적 `UIColor` 라 트레이트가 바뀌는 즉시 다시 칠한다(재실행 없음).
///
/// SwiftUI 루트의 `preferredColorScheme` 대신 창인 이유(w9 실측, iOS 26.5 시뮬레이터 — 지금 탭 · 대화 · 설명 시트 · 키보드 · 실행 중 세 방향 전환):
/// 두 방식의 화면은 같았다. 다만 `preferredColorScheme` 은 창이 아니라 호스팅 컨트롤러에 걸려(창 override=0) 키보드 · 텍스트 효과 창
/// (`UITextEffectsWindow` — 로그인 뒤 암호 저장 창이 붙는 곳)은 UIKit 이 주 창을 보고 맞춰 주기를 기대야 하고, nil 로 되돌릴 때 iOS 버전별
/// 결함 이력이 있다(배포 대상 18 은 시뮬레이터가 없어 못 쟀다). 창에 직접 걸면 생기는 창마다 우리가 명시로 건다(로그 `changed=UITextEffectsWindow`).
///
/// - 시스템 모드 = `.unspecified`(창이 기기 설정을 그대로 따른다).
/// - 지금 있는 창 + 앞으로 보이게 되는 창(`didBecomeVisibleNotification` — SwiftUI 가 첫 창을 띄우는 순간 · 키보드와 함께 뜨는 창) + 모드 변경.
@MainActor
package enum MobileAppearanceWindows {
    nonisolated static let logger = Logger(subsystem: "com.yehsung.aingcheck", category: "appearance")

    enum Reason: String {
        case install, change, visible
    }

    private static weak var store: MobileAppearanceStore?
    private static var visibilityObserver: NSObjectProtocol?

    package static func style(for mode: MobileAppearanceMode) -> UIUserInterfaceStyle {
        switch mode {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// 앱 델리게이트 didFinishLaunching(창이 생기기 전)에서 한 번. 다시 불리면 지금 창에 다시 걸기만 한다.
    package static func install(store newStore: MobileAppearanceStore) {
        store = newStore
        newStore.onChange = { mode in applyToAllWindows(mode, reason: .change) }
        if visibilityObserver == nil {
            visibilityObserver = NotificationCenter.default.addObserver(
                forName: UIWindow.didBecomeVisibleNotification,
                object: nil,
                queue: .main
            ) { _ in
                // 알림 객체(창)는 보내지 않고 전부 다시 훑는다 — 창은 몇 개뿐이고 이미 같은 값인 창은 건너뛴다.
                MainActor.assumeIsolated {
                    guard let mode = store?.mode else { return }
                    applyToAllWindows(mode, reason: .visible)
                }
            }
        }
        applyToAllWindows(newStore.mode, reason: .install)
    }

    static func applyToAllWindows(_ mode: MobileAppearanceMode, reason: Reason) {
        let style = style(for: mode)
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        var changed: [String] = []
        for window in windows where window.overrideUserInterfaceStyle != style {
            window.overrideUserInterfaceStyle = style
            changed.append(String(describing: type(of: window)))
        }
        guard reason != .visible || !changed.isEmpty else { return }
        logger.notice("apply mode=\(mode.rawValue, privacy: .public) reason=\(reason.rawValue, privacy: .public) windows=\(windows.count, privacy: .public) changed=\(changed.joined(separator: ","), privacy: .public)")
    }
}
#endif
