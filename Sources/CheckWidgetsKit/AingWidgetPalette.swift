import Foundation

/// 위젯 색 숫자(플랫폼 무관). 위젯 모듈은 앱 모듈(CheckMobileKit)을 링크하지 않으므로 앱 토큰(`MobileThemePalette`)의 **같은 값**을
/// 여기 적는다 — `NowWidgetModelTests` 가 두 표가 글자까지 같은지 잰다(한쪽만 바뀌면 빨강).
package enum AingWidgetPalette {
    package struct Pair: Equatable, Sendable {
        package let light: UInt32
        package let dark: UInt32
    }

    package static let background = Pair(light: 0xF4F6FA, dark: 0x1E2029)
    package static let cardElevated = Pair(light: 0xEDF0F6, dark: 0x353949)
    package static let primaryText = Pair(light: 0x151823, dark: 0xF2F2F3)
    package static let secondaryText = Pair(light: 0x5A6070, dark: 0xBBBCC1)
    package static let working = Pair(light: 0x0E7A4B, dark: 0x59E0A1)
    package static let offWork = Pair(light: 0x4A5E78, dark: 0x94ADCC)
    package static let pending = Pair(light: 0xA15C00, dark: 0xFFB854)
    package static let accent = Pair(light: 0x1765C1, dark: 0x54ABFF)
    package static let track = Pair(light: 0xE3E7EF, dark: 0x2B2E3D)

    /// 0xRRGGBB → (r, g, b) 0…1.
    package static func components(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}
