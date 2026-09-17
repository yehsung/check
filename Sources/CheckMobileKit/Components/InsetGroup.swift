#if os(iOS)
import SwiftUI

// 목록은 카드마다 한 장이 아니라 **인셋 그룹 한 장 안의 행**(시안 B). 구분선은 0.5pt · 글자 시작점부터(아이콘·아바타 뒤).

/// 인셋 그룹 카드(반경 22 · surface · 좌우 바깥 여백은 부르는 쪽이 `MobileTheme.sideMargin`). 행 사이 구분선은 `GroupRow` 가 긋는다.
///
///     InsetGroup {
///         GroupRow(divider: .inset(52)) { … }
///         GroupRow(divider: .none) { … }       // 마지막 행
///     }
package struct InsetGroup<Content: View>: View {
    private let content: Content

    package init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous).fill(MobileTheme.surface))
        .clipShape(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous))
    }
}

/// 그룹 안 한 행(최소 44pt · 좌우 16 · 위아래 10). 아래 구분선은 `divider` 로 — 마지막 행은 `.none`.
package struct GroupRow<Content: View>: View {
    package enum Divider: Equatable, Sendable {
        case none
        /// 행 왼쪽에서 이만큼 떨어진 곳(= 글자 시작점)부터. 16 = 기호 없는 행.
        case inset(CGFloat)
    }

    private let divider: Divider
    private let minHeight: CGFloat
    private let padding: EdgeInsets
    private let isHighlighted: Bool
    private let content: Content
    @Environment(\.displayScale) private var displayScale

    /// - Parameters:
    ///   - isHighlighted: 내 행(파랑 틴트 6% — `accentTint` 보다 옅게 · 시안 `.b-mine`).
    package init(
        divider: Divider = .inset(MobileTheme.cardPadding),
        minHeight: CGFloat = MobileTheme.rowHeight,
        padding: EdgeInsets = EdgeInsets(top: 10, leading: MobileTheme.cardPadding, bottom: 10, trailing: MobileTheme.cardPadding),
        isHighlighted: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.divider = divider
        self.minHeight = minHeight
        self.padding = padding
        self.isHighlighted = isHighlighted
        self.content = content()
    }

    package var body: some View {
        HStack(alignment: .center, spacing: MobileTheme.space3) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background(isHighlighted ? MobileTheme.accent.opacity(0.06) : Color.clear)
        .overlay(alignment: .bottom) {
            if case .inset(let leading) = divider {
                Rectangle()
                    .fill(MobileTheme.separator)
                    .frame(height: max(MobileTheme.hairline, 1 / max(displayScale, 1)))
                    .padding(.leading, leading)
            }
        }
    }
}

/// 섹션 머리(시안 `.b-sh`): 제목 19 bold + 오른쪽 보조 글자 또는 링크. 좌우 20 · 위 22 · 아래 8 은 `padded` 로 켠다
/// (카드 안에서 쓰면 끈다).
package struct SectionHeader: View {
    package enum Trailing {
        case none
        /// 보조 글자("남은 4개" · "3/6 보유").
        case text(String)
        /// 링크 버튼("전체 보기").
        case action(String, () -> Void)
    }

    private let title: String
    private let trailing: Trailing
    private let padded: Bool

    package init(_ title: String, trailing: Trailing = .none, padded: Bool = false) {
        self.title = title
        self.trailing = trailing
        self.padded = padded
    }

    /// 예전 모양(제목 + 오른쪽 버튼) — 기존 화면 호환.
    package init(_ title: String, actionTitle: String?, action: (() -> Void)?) {
        self.title = title
        if let actionTitle, let action {
            self.trailing = .action(actionTitle, action)
        } else {
            self.trailing = .none
        }
        self.padded = false
    }

    package var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(MobileTheme.sectionTitle)
                .foregroundStyle(MobileTheme.label)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            switch trailing {
            case .none:
                EmptyView()
            case .text(let text):
                Text(text)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.label2)
            case .action(let label, let action):
                Button(label, action: action)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.accent)
                    .frame(minHeight: AingButtonMetrics.minimumTarget)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, padded ? MobileTheme.titleMargin - MobileTheme.sideMargin : 0)
        .padding(.top, padded ? 22 : 0)
        .padding(.bottom, padded ? 8 : 0)
    }
}

/// 진행 막대(높이 6 · 얇게 4 · 트랙 `fill`). `.accent` 진행(미달) · `.gauge` '우리 팀' 게이지(그라디언트) · `.done` 달성(초록) · `.ai` AI 토큰.
package struct ProgressBar: View {
    package enum Style: String, CaseIterable, Sendable { case accent, gauge, done, ai }

    private let fraction: Double
    private let style: Style
    private let thin: Bool

    package init(_ fraction: Double, style: Style = .accent, thin: Bool = false) {
        self.fraction = ProgressBarRule.clamped(fraction)
        self.style = style
        self.thin = thin
    }

    package var body: some View {
        let height: CGFloat = thin ? 4 : 6
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(MobileTheme.fill)
                if fraction > 0 {
                    Capsule()
                        .fill(fillStyle)
                        .frame(width: max(height, proxy.size.width * fraction))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((fraction * 100).rounded()))%"))
    }

    private var fillStyle: AnyShapeStyle {
        switch style {
        case .accent: return AnyShapeStyle(MobileTheme.accent)
        case .gauge: return AnyShapeStyle(MobileTheme.gaugeGradient)
        case .done: return AnyShapeStyle(MobileTheme.workingDot)
        case .ai: return AnyShapeStyle(MobileTheme.aiToken)
        }
    }
}
#endif
