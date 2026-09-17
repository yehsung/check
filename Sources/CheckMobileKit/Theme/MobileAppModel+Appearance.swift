import Foundation
#if DEBUG
import notify
#endif

/// 앱 델리게이트(ios/App/AppDelegate.swift)가 부르는 화면 모드 공개 전달.
public extension MobileAppModel {
    /// didFinishLaunching 에서 한 번(창이 생기기 전 — 첫 창이 보이는 순간부터 고른 모드로 그린다). 루트 화면 onAppear 도 다시 부른다(두 번째부터는
    /// 지금 창에 다시 걸기만). DEBUG 데모에서는 실행 중 바꾸기 훅(`MobileAppearanceDemo`)도 건다.
    func installAppearance() {
        #if os(iOS)
        MobileAppearanceWindows.install(store: appearance)
        #if DEBUG
        if context.isDemo { MobileAppearanceDemo.listen(store: appearance) }
        #endif
        #endif
    }
}

#if DEBUG
/// 데모(시뮬레이터) 전용: 화면을 누르지 않고 실행 중 모드를 바꾼다 —
/// `xcrun simctl spawn <기기> notifyutil -p com.yehsung.aingcheck.demo.appearance.dark` (light · system 도).
/// 설정 화면의 행을 누른 것과 같은 `MobileAppearanceStore.select` 경로다.
@MainActor
package enum MobileAppearanceDemo {
    package static let notificationPrefix = "com.yehsung.aingcheck.demo.appearance."
    private static var tokens: [Int32] = []

    package static func listen(store: MobileAppearanceStore) {
        guard tokens.isEmpty else { return }
        for mode in MobileAppearanceMode.allCases {
            var token: Int32 = 0
            let status = notify_register_dispatch(notificationPrefix + mode.rawValue, &token, DispatchQueue.main) { [weak store] _ in
                MainActor.assumeIsolated { store?.select(mode) }
            }
            if status == 0 { tokens.append(token) }
        }
    }
}
#endif
