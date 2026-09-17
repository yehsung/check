#if os(iOS)
import SwiftUI

// 버튼 3단(시안 B): 채움(화면당 하나) · 틴트 · 회색/글자. 보이는 높이 50 / 40 / 30, 캡슐. 누름 영역은 늘 44pt 이상.
// 화면에 채운 버튼은 하나만 둔다 — 보조 동작은 틴트나 글자. '도전' 같은 행 안 동작은 `.tinted` + `.sm`(번개 금지 — 울트라 전용).

/// 버튼 모양. `.buttonStyle(AingButtonStyle(.filled, size: .lg))` 또는 `AingButton(...)`.
package struct AingButtonStyle: ButtonStyle {
    package enum Kind: String, CaseIterable, Sendable {
        /// accentFill + 흰 글자. 화면당 하나.
        case filled
        /// accentTint + accent 글자.
        case tinted
        /// fill(회색) + label 글자.
        case gray
        /// 바탕 없음 + accent 글자(링크형).
        case plain
        /// dangerTint + danger 글자(기권·삭제 확인).
        case destructive
    }

    private let kind: Kind
    private let size: AingButtonMetrics.Size
    private let fillsWidth: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    package init(_ kind: Kind = .filled, size: AingButtonMetrics.Size = .lg, fillsWidth: Bool = false) {
        self.kind = kind
        self.size = size
        self.fillsWidth = fillsWidth
    }

    package func makeBody(configuration: Configuration) -> some View {
        let darkDisabled = !isEnabled && colorScheme == .dark && kind != .plain
        configuration.label
            .font(font)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundStyle(darkDisabled ? MobileTheme.label2 : foreground)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, 4)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: size.height)
            .background(Capsule().fill(darkDisabled ? MobileTheme.fill2 : background))
            .opacity(isEnabled || darkDisabled ? (configuration.isPressed ? 0.75 : 1) : AingButtonMetrics.disabledOpacity)
            .frame(minHeight: AingButtonMetrics.targetHeight(for: size))
            .contentShape(Rectangle())
    }

    private var font: Font {
        switch size {
        case .lg: return .system(.body, weight: .semibold)
        case .md: return .system(.callout, weight: .semibold)
        case .sm: return .system(.subheadline, weight: .semibold)
        }
    }

    private var foreground: Color {
        switch kind {
        case .filled: return MobileTheme.onAccentFill
        case .tinted, .plain: return MobileTheme.accent
        case .gray: return MobileTheme.label
        case .destructive: return MobileTheme.danger
        }
    }

    private var background: Color {
        switch kind {
        case .filled: return MobileTheme.accentFill
        case .tinted: return MobileTheme.accentTint
        case .gray: return MobileTheme.fill
        case .plain: return .clear
        case .destructive: return MobileTheme.dangerTint
        }
    }
}

/// 글자(+ 선택 기호) 버튼 한 줄 조립.
package struct AingButton: View {
    private let title: String
    private let systemImage: String?
    private let kind: AingButtonStyle.Kind
    private let size: AingButtonMetrics.Size
    private let fillsWidth: Bool
    private let isBusy: Bool
    private let action: () -> Void

    /// - Parameter isBusy: 도는 중이면 스피너를 앞에 두고 눌리지 않는다.
    package init(
        _ title: String,
        systemImage: String? = nil,
        kind: AingButtonStyle.Kind = .filled,
        size: AingButtonMetrics.Size = .lg,
        fillsWidth: Bool = false,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.size = size
        self.fillsWidth = fillsWidth
        self.isBusy = isBusy
        self.action = action
    }

    package var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(kind == .filled ? MobileTheme.onAccentFill : MobileTheme.accent)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.medium)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
        }
        .buttonStyle(AingButtonStyle(kind, size: size, fillsWidth: fillsWidth))
        .disabled(isBusy)
    }
}

/// 유리 바탕(원형 도구 버튼 · 알약 · 하단 막대). 라이트 흰 74% · 다크 한 단계 밝은 남색 82% + 가는 테두리 + 그림자.
package struct GlassBackground<S: InsettableShape>: View {
    private let shape: S
    @Environment(\.colorScheme) private var colorScheme

    package init(shape: S) {
        self.shape = shape
    }

    package var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(MobileTheme.glass))
            .overlay(shape.strokeBorder(MobileTheme.glassLine, lineWidth: 0.5))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.07), radius: 7, y: 4)
    }
}

/// 유리 원형 버튼(44pt) — 새 대화 · 설정 · 더보기(…) 같은 오른쪽 위 도구.
package struct GlassCircleButton: View {
    private let systemImage: String
    private let accessibilityLabel: String
    private let action: () -> Void

    package init(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    package var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(MobileTheme.label)
                .frame(width: AingButtonMetrics.minimumTarget, height: AingButtonMetrics.minimumTarget)
                .background(GlassBackground(shape: Circle()))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

/// 유리 알약(44pt 높이) — 안에 무엇이든(루비 잔량은 `RubyBalanceChip(_, style: .glass)` 가 이미 유리다).
package struct GlassPill<Content: View>: View {
    private let content: Content

    package init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    package var body: some View {
        HStack(spacing: 6) { content }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .frame(minHeight: AingButtonMetrics.minimumTarget)
            .background(GlassBackground(shape: Capsule()))
    }
}
#endif
