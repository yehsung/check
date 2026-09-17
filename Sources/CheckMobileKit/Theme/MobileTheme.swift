#if os(iOS)
import SwiftUI
import UIKit

/// 폰 디자인 토큰 — 재디자인 방향 B(`b2.html` 토큰 표). **뷰는 이 토큰만 쓴다** — 색·치수를 뷰에 리터럴로 적지 않는다.
///
/// 이름은 시안 변수와 한 줄씩 맞춘다: `--b-bg` → `background` · `--b-surface` → `surface` · `--b-label-2` → `label2` …
/// 숫자는 `MobileThemePalette`(플랫폼 무관 — `BaseThemeTests` 가 대비와 맥 색 일치를 잰다). 반투명 토큰은 색 객체도 반투명이라
/// 아래 면에 겹쳐 그려진다(시안 rgba 와 같다).
///
/// 색은 뜻으로만: 초록 = 근무 중·달성 · 앰버 = 연결 끊김·대기 · 파랑 = 선택·진행·주요 동작 · 빨강 = 위험·기권 · 보라 = AI 토큰 ·
/// 청회색 = 근무 안 함. 토글·할 일 체크·제보 칩에 초록 금지, 이월 배지는 회색(`fill` + `label2`).
package enum MobileTheme {
    // MARK: 바탕·표면
    package static let background = color(MobileThemePalette.background)
    package static let surface = color(MobileThemePalette.surface)
    package static let surface2 = color(MobileThemePalette.surface2)
    package static let fill = color(MobileThemePalette.fill)
    package static let fill2 = color(MobileThemePalette.fill2)
    package static let separator = color(MobileThemePalette.separator)
    package static let glass = color(MobileThemePalette.glass)
    package static let glassLine = color(MobileThemePalette.glassLine)
    package static let bubbleIn = color(MobileThemePalette.bubbleIn)

    // MARK: 글자
    package static let label = color(MobileThemePalette.label)
    package static let label2 = color(MobileThemePalette.label2)
    /// 선·기호 전용(글자 금지 — 글자는 `label3Text`).
    package static let label3 = color(MobileThemePalette.label3)
    package static let label3Text = color(MobileThemePalette.label3Text)

    // MARK: 뜻 색
    package static let accent = color(MobileThemePalette.accent)
    package static let accentFill = color(MobileThemePalette.accentFill)
    package static let accentTint = color(MobileThemePalette.accentTint)
    package static let accentLine = color(MobileThemePalette.accentLine)
    package static let onAccentFill = color(MobileThemePalette.onAccentFill)
    package static let tabSelected = color(MobileThemePalette.tabSelected)
    package static let working = color(MobileThemePalette.working)
    package static let workingDot = color(MobileThemePalette.workingDot)
    package static let workingTint = color(MobileThemePalette.workingTint)
    package static let offWork = color(MobileThemePalette.offWork)
    package static let offWorkDot = color(MobileThemePalette.offWorkDot)
    package static let pending = color(MobileThemePalette.pending)
    package static let pendingDot = color(MobileThemePalette.pendingDot)
    package static let pendingTint = color(MobileThemePalette.pendingTint)
    package static let danger = color(MobileThemePalette.danger)
    package static let dangerTint = color(MobileThemePalette.dangerTint)
    package static let aiToken = color(MobileThemePalette.aiToken)
    package static let badge = color(MobileThemePalette.badge)

    // MARK: 메달
    package static let gold = color(MobileThemePalette.gold)
    package static let silver = color(MobileThemePalette.silver)
    package static let bronze = color(MobileThemePalette.bronze)
    package static let crownInk = color(MobileThemePalette.crownInk)

    // MARK: 그라디언트(뜻으로만 — '우리 팀' 게이지 · 로그인 버튼 · 나무판)
    package static let gaugeGradient = LinearGradient(colors: MobileThemePalette.gaugeStops.map(fixed), startPoint: .leading, endPoint: .trailing)
    package static let startGradient = LinearGradient(colors: MobileThemePalette.startStops.map(fixed), startPoint: .topLeading, endPoint: .bottomTrailing)
    package static let woodGradient = LinearGradient(colors: MobileThemePalette.woodStops.map(fixed), startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: 위젯
    package static let widgetBackground = color(MobileThemePalette.widgetBackground)

    // MARK: 치수(4pt 계단 · 모서리는 .continuous)

    /// 인셋 그룹·카드 모서리(22).
    package static let groupRadius: CGFloat = 22
    /// 캐릭터 타일 모서리(16).
    package static let tileRadius: CGFloat = 16
    /// 카드 안 2차 상자 · 입력칸 모서리(12).
    package static let innerRadius: CGFloat = 12
    /// 위젯 모서리(22).
    package static let widgetRadius: CGFloat = 22
    /// 카드 좌우 바깥 여백(16).
    package static let sideMargin: CGFloat = 16
    /// 큰 제목·섹션 머리 좌우 여백(20).
    package static let titleMargin: CGFloat = 20
    /// 카드 안쪽 여백(16).
    package static let cardPadding: CGFloat = 16
    /// 카드 사이 · 카드 안 줄 사이(12).
    package static let rowSpacing: CGFloat = 12
    /// 4pt 계단.
    package static let space1: CGFloat = 4
    package static let space2: CGFloat = 8
    package static let space3: CGFloat = 12
    package static let space4: CGFloat = 16
    package static let space5: CGFloat = 20
    package static let space6: CGFloat = 24
    package static let space8: CGFloat = 32
    /// 행 높이: 한 줄 44 · 두 줄 56 · 미니게임 48 · 팀 리그 64.
    package static let rowHeight: CGFloat = 44
    package static let rowHeightTwoLine: CGFloat = 56
    /// 구분선 두께(0.5pt).
    package static let hairline: CGFloat = 0.5

    // MARK: 글꼴 — Dynamic Type 을 따르는 텍스트 스타일만(고정 pt 금지). 시안 크기 ↔ 스타일:
    // 큰 제목 34 = .largeTitle · 섹션 19 = .title3 bold · 행 이름 16 = .callout semibold · 부제 13 = .footnote · 칩 11 = .caption2 semibold.

    /// 숫자(SF Pro + `.monospacedDigit()` 를 뷰에서 함께 건다).
    package static func number(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .default, weight: weight)
    }

    /// 게임 점수 · 순위 원 · 이니셜 전용 둥근 숫자.
    package static func roundedNumber(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }

    /// 큰 제목(화면 머리).
    package static func title(_ style: Font.TextStyle = .title2) -> Font {
        .system(style, design: .default, weight: .bold)
    }

    /// 섹션 머리(19 bold).
    package static let sectionTitle = Font.system(.title3, design: .default, weight: .bold)
    /// 행 이름(16 semibold).
    package static let rowTitle = Font.system(.callout, design: .default, weight: .semibold)
    /// 행 부제(13).
    package static let rowSubtitle = Font.footnote
    /// 칩 글자(11 semibold).
    package static let chip = Font.system(.caption2, design: .default, weight: .semibold)

    // MARK: 내부

    private static func color(_ pair: MobileThemePalette.Pair) -> Color {
        Color(uiColor: UIColor { traits in ui(traits.userInterfaceStyle == .dark ? pair.dark : pair.light) })
    }

    private static func fixed(_ rgb: MobileThemePalette.RGB) -> Color {
        Color(uiColor: ui(rgb))
    }

    /// UIKit 색(토큰 → 외관별). 시스템 부품(탭 막대 모양 등)에 넘길 때.
    package static func uiColor(_ pair: MobileThemePalette.Pair) -> UIColor {
        UIColor { traits in ui(traits.userInterfaceStyle == .dark ? pair.dark : pair.light) }
    }

    private static func ui(_ rgb: MobileThemePalette.RGB) -> UIColor {
        UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: rgb.alpha)
    }
}

/// 크기를 고정 pt 로 주되 Dynamic Type 을 따라 키우는 글꼴(타이머 48 · 위젯 큰 수처럼 텍스트 스타일에 없는 크기).
package struct ScaledFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    package init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    package func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// `size`pt 를 기본으로 `style` 배율을 따라 커지는 글꼴. 예: 지금 탭 타이머 `.scaledFont(size: 48, weight: .semibold)`.
    package func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, relativeTo style: Font.TextStyle = .largeTitle) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design, relativeTo: style))
    }
}
#endif
