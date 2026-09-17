import Foundation

/// 폰 색 토큰의 **숫자**(플랫폼 무관 — macOS `swift test` 가 대비를 잰다). 색 객체는 iOS 층 `MobileTheme` 이 이 값으로 만든다.
package enum MobileThemePalette {
    package struct RGB: Equatable, Sendable {
        package let r: Double
        package let g: Double
        package let b: Double

        package init(_ r: Double, _ g: Double, _ b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }

        package init(hex: UInt32) {
            self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
        }

        /// WCAG 상대 휘도.
        package var relativeLuminance: Double {
            func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
        }

        /// WCAG 대비(1…21).
        package func contrast(against other: RGB) -> Double {
            let a = relativeLuminance, b = other.relativeLuminance
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
    }

    /// 한 토큰의 라이트·다크 값.
    package struct Pair: Equatable, Sendable {
        package let light: RGB
        package let dark: RGB
    }

    // 표면
    package static let background = Pair(light: RGB(hex: 0xF4F6FA), dark: RGB(hex: 0x1E2029))
    package static let card = Pair(light: RGB(hex: 0xFFFFFF), dark: RGB(hex: 0x2B2E3D))
    package static let cardElevated = Pair(light: RGB(hex: 0xEDF0F6), dark: RGB(hex: 0x353949))

    // 글자(다크는 흰색 불투명도 — 색 객체 쪽에서 만든다. 여기 dark 값은 카드 위에 합성한 근사치다)
    package static let primaryText = Pair(light: RGB(hex: 0x151823), dark: RGB(0.94 * 1 + 0.06 * 0.169, 0.94 + 0.06 * 0.180, 0.94 + 0.06 * 0.239))
    package static let secondaryText = Pair(light: RGB(hex: 0x5A6070), dark: RGB(0.68 + 0.32 * 0.169, 0.68 + 0.32 * 0.180, 0.68 + 0.32 * 0.239))

    // 상태색 — 다크는 맥 CheckTheme 그대로(`CheckTheme.swift` 의 Color(red:green:blue:) 와 같은 숫자), 라이트는 대비를 맞춘 진한 값.
    package static let working = Pair(light: RGB(hex: 0x0E7A4B), dark: RGB(0.35, 0.88, 0.63))
    package static let offWork = Pair(light: RGB(hex: 0x4A5E78), dark: RGB(0.58, 0.68, 0.80))
    package static let pending = Pair(light: RGB(hex: 0xA15C00), dark: RGB(1.0, 0.72, 0.33))
    package static let accent = Pair(light: RGB(hex: 0x1765C1), dark: RGB(0.33, 0.67, 1.0))
    package static let danger = Pair(light: RGB(hex: 0xC62D33), dark: RGB(1.0, 0.45, 0.46))
    package static let aiToken = Pair(light: RGB(hex: 0x6D3FD1), dark: RGB(0.72, 0.55, 1.0))
    package static let ruby = Pair(light: RGB(hex: 0xC2185B), dark: RGB(hex: 0xFF5C8A))
    /// accent 로 **채운** 면(버튼) 위 글자. 다크의 accent 는 밝은 파랑이라 흰 글자가 2.5:1 로 떨어진다(데모 스크린샷 실측) — 다크는 짙은 글자.
    package static let onAccent = Pair(light: RGB(hex: 0xFFFFFF), dark: RGB(hex: 0x10131C))

    /// 글자로 쓰이는 토큰(대비 4.5:1 검사 대상).
    package static let textTokens: [(name: String, pair: Pair)] = [
        ("primaryText", primaryText), ("secondaryText", secondaryText),
        ("working", working), ("offWork", offWork), ("pending", pending), ("accent", accent),
        ("danger", danger), ("aiToken", aiToken), ("ruby", ruby),
    ]
}
