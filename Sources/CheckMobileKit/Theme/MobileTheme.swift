#if os(iOS)
import SwiftUI
import UIKit

/// 폰 디자인 토큰(SPEC-ios §3.1). **뷰는 이 토큰만 쓴다** — 색·치수를 뷰에 리터럴로 적지 않는다.
///
/// 색상축은 맥 `CheckTheme` 이 뿌리다: working 초록 · offWork 청회색 · pending 주황 · accent 파랑 · danger 빨강 · aiToken 보라.
/// - 다크: 맥 패널 톤(배경 #1E2029 · 카드 #2B2E3D · 선 흰 14%) + 맥과 같은 상태색.
/// - 라이트: 배경 #F4F6FA · 카드 흰색, 상태색은 흰 카드·배경 위 대비 4.5:1 이상이 되게 한 단계 진하게.
/// 숫자는 `MobileThemePalette`(플랫폼 무관 — `BaseThemeTests` 가 대비와 맥 색 일치를 잰다).
package enum MobileTheme {
    // MARK: 표면
    package static let background = color(MobileThemePalette.background)
    package static let card = color(MobileThemePalette.card)
    /// 카드 안 한 단계 올라온 면(입력칸 · 선택된 세그먼트).
    package static let cardElevated = color(MobileThemePalette.cardElevated)
    package static let separator = dynamic(light: UIColor.black.withAlphaComponent(0.08), dark: UIColor.white.withAlphaComponent(0.14))
    package static let track = dynamic(light: UIColor.black.withAlphaComponent(0.07), dark: UIColor.black.withAlphaComponent(0.28))

    // MARK: 글자
    package static let primaryText = dynamic(light: ui(MobileThemePalette.primaryText.light), dark: UIColor.white.withAlphaComponent(0.94))
    package static let secondaryText = dynamic(light: ui(MobileThemePalette.secondaryText.light), dark: UIColor.white.withAlphaComponent(0.68))
    /// accent 로 채운 면(버튼) 위 글자 — 라이트 흰색 · 다크 짙은 남색(다크 accent 가 밝아 흰 글자는 대비가 모자라다).
    package static let onAccent = color(MobileThemePalette.onAccent)

    // MARK: 상태색(맥 CheckTheme 축)
    package static let working = color(MobileThemePalette.working)
    package static let offWork = color(MobileThemePalette.offWork)
    package static let pending = color(MobileThemePalette.pending)
    package static let accent = color(MobileThemePalette.accent)
    package static let danger = color(MobileThemePalette.danger)
    package static let aiToken = color(MobileThemePalette.aiToken)
    package static let ruby = color(MobileThemePalette.ruby)

    // MARK: 치수(SPEC-ios §3.1)
    package static let cardRadius: CGFloat = 16
    package static let rowSpacing: CGFloat = 12
    package static let sideMargin: CGFloat = 16
    package static let cardPadding: CGFloat = 16

    // MARK: 글꼴 — Dynamic Type 을 따르는 텍스트 스타일만(고정 pt 금지). 숫자는 둥근 디자인 + `.monospacedDigit()`.
    package static func number(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }

    package static func title(_ style: Font.TextStyle = .title2) -> Font {
        .system(style, design: .rounded, weight: .bold)
    }

    // MARK: 내부

    private static func color(_ pair: MobileThemePalette.Pair) -> Color {
        dynamic(light: ui(pair.light), dark: ui(pair.dark))
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }

    private static func ui(_ rgb: MobileThemePalette.RGB) -> UIColor {
        UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }
}
#endif
