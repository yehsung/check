#if os(iOS)
import UIKit

/// 대국 중 화면 꺼짐 방지의 시스템 대입(SPEC-ios §3.5). **부르는 곳은 `GamesStore` 하나다** — 화면(뷰)은 이 값을 쓰지 않는다.
@MainActor
enum GamesSystemIdleTimer {
    static func apply(disabled: Bool) {
        if UIApplication.shared.isIdleTimerDisabled != disabled {
            UIApplication.shared.isIdleTimerDisabled = disabled
        }
    }
}
#endif
