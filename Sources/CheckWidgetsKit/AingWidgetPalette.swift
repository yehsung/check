import Foundation

/// 위젯 색 숫자(플랫폼 무관). 위젯 모듈은 앱 모듈(CheckMobileKit)을 링크하지 않으므로 앱 토큰(`MobileThemePalette`)의 **같은 값**을
/// 여기 적는다 — `NowWidgetTests` 가 두 표가 글자까지 같은지 잰다(한쪽만 바뀌면 빨강).
///
/// w15 기반: 방향 B 토큰으로 옮겼다. 위젯 바탕은 `widgetBackground`(흰색 / 남색 #232633), 반투명 토큰(글자 2단 · 채움)은 그 바탕 위에
/// 겹친 불투명 값이다(위젯은 단색 칠만 쓴다 — 렌더링 모드 대응은 위젯 담당).
package enum AingWidgetPalette {
    package struct Pair: Equatable, Sendable {
        package let light: UInt32
        package let dark: UInt32
    }

    /// = `MobileThemePalette.widgetBackground`.
    package static let background = Pair(light: 0xFFFFFF, dark: 0x232633)
    /// = `fill` 을 위젯 바탕에 겹친 값.
    package static let cardElevated = Pair(light: 0xEFEFF0, dark: 0x373A45)
    /// = `label` 을 위젯 바탕에 겹친 값.
    package static let primaryText = Pair(light: 0x0B0B10, dark: 0xF4F4F5)
    /// = `label2` 를 위젯 바탕에 겹친 값.
    package static let secondaryText = Pair(light: 0x6F6F74, dark: 0xA3A5AF)
    package static let working = Pair(light: 0x127A51, dark: 0x59E0A1)
    package static let offWork = Pair(light: 0x666E7D, dark: 0x94ADCC)
    package static let pending = Pair(light: 0x9A5B00, dark: 0xFFB854)
    package static let accent = Pair(light: 0x1864CF, dark: 0x54ABFF)
    /// = `fill` 을 위젯 바탕에 겹친 값(막대 트랙).
    package static let track = Pair(light: 0xEFEFF0, dark: 0x373A45)

    /// 0xRRGGBB → (r, g, b) 0…1.
    package static func components(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}
