import Foundation
#if os(iOS) && canImport(WidgetKit)
import WidgetKit
#endif

/// 위젯 타임라인 새로고침 어댑터. WidgetKit 은 iOS 층에만 둔다 — 스토어는 이 함수를 주입받을 뿐이다.
@MainActor
package enum MobileWidgetTimelines {
    package static func reloadAll() {
        #if os(iOS) && canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
