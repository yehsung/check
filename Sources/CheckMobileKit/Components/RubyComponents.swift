#if os(iOS)
import SwiftUI

// 루비 = ruby.png 하나, 문법 셋(시안 B "2 · 루비"): 잔량은 파랑 캡슐 속 보석(맥 RubyBalanceChip) · 가격은 맨 보석 + 숫자(모자라면 흐림) ·
// 획득은 초록 +N. 진홍 마름모(SF `diamond.fill`)와 자물쇠 가격표는 쓰지 않는다. 숫자는 모두 `.monospacedDigit()`.

/// 보석 하나. 크기 단계 14 · 17 · 20 · 24(`RubyGlyph.sizes`). 글자 크기를 따라 커진다(`scalesWithText`).
package struct RubyIcon: View {
    private let baseSize: CGFloat
    private let scalesWithText: Bool
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1
    @Environment(\.displayScale) private var displayScale

    package init(size: CGFloat = 17, scalesWithText: Bool = true) {
        self.baseSize = size
        self.scalesWithText = scalesWithText
    }

    private var side: CGFloat {
        scalesWithText ? (baseSize * min(max(textScale, 1), 2)).rounded() : baseSize
    }

    package var body: some View {
        let side = self.side
        ArtImage(MobileArt.ruby(pointSize: side, displayScale: displayScale), size: CGSize(width: side, height: side))
    }
}

/// 루비 잔량 칩. `.small`(높이 24 · 보석 17) · `.large`(34 · 24) · `.glass`(44 유리 알약 — 게임·상점 오른쪽 위).
/// nil 은 "–"(모른다 — 0 으로 지어내지 않는다). `action` 이 있으면 버튼(예: 나 탭 → 상점).
package struct RubyBalanceChip: View {
    package enum Style: Sendable { case small, large, glass }

    private let count: Int?
    private let style: Style
    private let action: (() -> Void)?

    package init(_ count: Int?, style: Style = .small, action: (() -> Void)? = nil) {
        self.count = count
        self.style = style
        self.action = action
    }

    package var body: some View {
        if let action {
            Button(action: action) { chip }
                .buttonStyle(.plain)
                .frame(minHeight: AingButtonMetrics.minimumTarget)
                .contentShape(Rectangle())
        } else {
            chip
        }
    }

    private var chip: some View {
        HStack(spacing: style == .small ? 3 : 4) {
            RubyIcon(size: gemSize)
            Text(count.map { "\($0)" } ?? "–")
                .font(font)
                .monospacedDigit()
                .foregroundStyle(MobileTheme.label)
                .lineLimit(1)
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, trailingPadding)
        .frame(minHeight: height)
        .background(background)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(count.map { "루비 \($0)개" } ?? "루비 잔액 모름"))
    }

    private var gemSize: CGFloat {
        switch style {
        case .small: return 17
        case .large: return 24
        case .glass: return 20
        }
    }

    private var font: Font {
        switch style {
        case .small: return .system(.subheadline, weight: .bold)
        case .large: return .system(.title3, weight: .bold)
        case .glass: return .system(.headline, weight: .semibold)
        }
    }

    private var height: CGFloat {
        switch style {
        case .small: return 24
        case .large: return 34
        case .glass: return 44
        }
    }

    private var leadingPadding: CGFloat { style == .small ? 6 : (style == .large ? 8 : 10) }
    private var trailingPadding: CGFloat { style == .small ? 9 : (style == .large ? 12 : 14) }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .small, .large:
            Capsule()
                .fill(MobileTheme.accentTint)
                .overlay(Capsule().strokeBorder(MobileTheme.accentLine, lineWidth: 1))
        case .glass:
            GlassBackground(shape: Capsule())
        }
    }
}

/// 가격: 맨 보석 + 숫자. 잔량이 모자라면 글자 `label3Text` + 보석 50%(자물쇠 없음).
package struct RubyPrice: View {
    private let price: Int
    private let isShort: Bool
    private let gemSize: CGFloat
    private let style: Font.TextStyle

    /// - Parameter balance: 내 잔량(nil = 모름 → 모자라다고 하지 않는다).
    package init(_ price: Int, balance: Int?, gemSize: CGFloat = 17, style: Font.TextStyle = .subheadline) {
        self.price = price
        self.isShort = RubyPriceRule.isShort(price: price, balance: balance)
        self.gemSize = gemSize
        self.style = style
    }

    /// 모자람을 직접 줄 때(판돈 버튼처럼 잔량이 아닌 다른 판정).
    package init(_ price: Int, isShort: Bool, gemSize: CGFloat = 17, style: Font.TextStyle = .subheadline) {
        self.price = price
        self.isShort = isShort
        self.gemSize = gemSize
        self.style = style
    }

    package var body: some View {
        HStack(spacing: 2) {
            RubyIcon(size: gemSize)
                .opacity(isShort ? 0.5 : 1)
            Text("\(price)")
                .font(.system(style, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isShort ? MobileTheme.label3Text : MobileTheme.label)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(RubyPriceRule.accessibilityText(price: price, isShort: isShort)))
    }
}

/// 획득: 초록 [보석]+N(`.inline`) 또는 틴트 칩(`.chip` — "+20 받음" 같은 꼬리 문구).
package struct RubyGain: View {
    package enum Style: Sendable { case inline, chip }

    private let amount: Int
    private let suffix: String?
    private let style: Style

    package init(_ amount: Int, suffix: String? = nil, style: Style = .inline) {
        self.amount = amount
        self.suffix = suffix
        self.style = style
    }

    package var body: some View {
        HStack(spacing: 3) {
            RubyIcon(size: 17)
            Text("+\(amount)" + (suffix.map { " \($0)" } ?? ""))
                .font(.system(style == .chip ? .footnote : .subheadline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(MobileTheme.working)
                .lineLimit(1)
        }
        .padding(.leading, style == .chip ? 6 : 0)
        .padding(.trailing, style == .chip ? 9 : 0)
        .frame(minHeight: style == .chip ? 24 : nil)
        .background {
            if style == .chip { Capsule().fill(MobileTheme.workingTint) }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("루비 \(amount)개 받음"))
    }
}

/// 예전 잔액 표기(보석 + 숫자). **새 화면은 `RubyBalanceChip` · `RubyPrice` · `RubyGain` 중 뜻에 맞는 것**을 쓴다.
/// 모양만 실제 보석으로 바꿨다(진홍 마름모 기호 제거) — 탭 담당이 옮기기 전까지 기존 화면이 컴파일되게 남긴다.
package struct RubyLabel: View {
    private let count: Int?
    private let style: Font.TextStyle

    package init(_ count: Int?, style: Font.TextStyle = .subheadline) {
        self.count = count
        self.style = style
    }

    package var body: some View {
        HStack(spacing: 3) {
            RubyIcon(size: 17)
            Text(count.map { "\($0)" } ?? "–")
                .font(MobileTheme.number(style))
                .monospacedDigit()
                .foregroundStyle(MobileTheme.label)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(count.map { "루비 \($0)개" } ?? "루비 잔액 모름"))
    }
}
#endif
