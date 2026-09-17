#if os(iOS)
import CheckCore
import SwiftUI

// 기반 공용 부품(SPEC-ios-build §1-2). 전부 `MobileTheme` 토큰만 쓰고, 글자는 Dynamic Type 텍스트 스타일이라
// 큰 글자에서 잘리지 않고 줄바꿈한다. 탭 작업자는 고치지 말고 조합한다(모양을 바꿔야 하면 "기반 수정 요청").

/// 카드(반경 16 · 안쪽 여백 16 · 다크에서 가는 선).
package struct AingCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    package init(padding: CGFloat = MobileTheme.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    package var body: some View {
        // 여러 자식을 넘겨도 카드 하나에 담는다(VStack 없이 수정자를 걸면 자식마다 카드가 따로 생긴다 — 데모 스크린샷 실측).
        VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
            content
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: MobileTheme.cardRadius, style: .continuous)
                    .fill(MobileTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MobileTheme.cardRadius, style: .continuous)
                    .stroke(MobileTheme.separator, lineWidth: 1)
            )
    }
}

/// 섹션 머리: 제목 + (선택) 오른쪽 버튼.
package struct SectionHeader: View {
    private let title: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    package init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    package var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(MobileTheme.primaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MobileTheme.accent)
            }
        }
    }
}

/// 아바타: 원격 이미지(AsyncImage — URLCache) → 없거나 실패하면 이니셜 원. 해시색은 맥 `CheckTheme.avatarColor(for:)` 와 같은 규칙.
package struct AvatarView: View {
    private let name: String
    private let url: URL?
    private let size: CGFloat

    package init(name: String, url: URL?, size: CGFloat = 36) {
        self.name = name
        self.url = url
        self.size = size
    }

    package var body: some View {
        Group {
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        InitialAvatar(name: name, size: size)
                    }
                }
            } else {
                InitialAvatar(name: name, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(Text("\(name) 프로필 사진"))
    }
}

/// 이니셜 원(맥 `InitialAvatar` 와 같은 모양: 첫 글자 · 해시색 그라데이션 · 흰 18% 테두리).
package struct InitialAvatar: View {
    let name: String
    let size: CGFloat

    package init(name: String, size: CGFloat) {
        self.name = name
        self.size = size
    }

    package static func initial(of name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1))
    }

    package var body: some View {
        let color = CheckTheme.avatarColor(for: name)
        Text(Self.initial(of: name))
            .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle().fill(LinearGradient(colors: [color, color.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// 센터 배지("서울"/"부산"). 모르는 값·nil 은 아무것도 그리지 않는다(코어 `CenterLabel` 규칙).
package struct CenterBadge: View {
    private let serverValue: String?

    package init(_ serverValue: String?) {
        self.serverValue = serverValue
    }

    package var body: some View {
        if let label = CenterLabel.display(serverValue) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(MobileTheme.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(MobileTheme.cardElevated))
                .overlay(Capsule().stroke(MobileTheme.separator, lineWidth: 0.5))
                .accessibilityLabel(Text("\(label)센터"))
        }
    }
}

/// 루비 잔액. nil 은 "–"(모른다 — 0 으로 지어내지 않는다).
package struct RubyLabel: View {
    private let count: Int?
    private let style: Font.TextStyle

    package init(_ count: Int?, style: Font.TextStyle = .subheadline) {
        self.count = count
        self.style = style
    }

    package var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "diamond.fill")
                .foregroundStyle(MobileTheme.ruby)
                .imageScale(.small)
            Text(count.map { "\($0)" } ?? "–")
                .font(MobileTheme.number(style))
                .monospacedDigit()
                .foregroundStyle(MobileTheme.primaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(count.map { "루비 \($0)개" } ?? "루비 잔액 모름"))
    }
}

/// 빈 상태(아이콘 · 제목 · 설명 · 선택 버튼).
package struct EmptyStateView: View {
    private let systemImage: String
    private let title: String
    private let message: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    package init(systemImage: String, title: String, message: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    package var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(MobileTheme.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(MobileTheme.primaryText)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(AingPrimaryButtonStyle(fillsWidth: false))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
    }
}

/// 주 버튼: accent 채움 + `onAccent` 글자(라이트·다크 모두 대비 4.5:1 — `.borderedProminent` 는 다크에서 흰 글자라 모자라다).
package struct AingPrimaryButtonStyle: ButtonStyle {
    private let fillsWidth: Bool
    @Environment(\.isEnabled) private var isEnabled

    package init(fillsWidth: Bool = true) {
        self.fillsWidth = fillsWidth
    }

    package func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(MobileTheme.onAccent)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MobileTheme.accent))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 한 줄 안내(오류·정보). 원인과 할 일을 말하는 문장을 넣는다.
package struct InlineNotice: View {
    package enum Kind: Sendable { case info, warning, error }

    private let text: String
    private let kind: Kind

    package init(text: String, kind: Kind = .info) {
        self.text = text
        self.kind = kind
    }

    private var tint: Color {
        switch kind {
        case .info: return MobileTheme.accent
        case .warning: return MobileTheme.pending
        case .error: return MobileTheme.danger
        }
    }

    private var symbol: String {
        switch kind {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    package var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(MobileTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

/// 불러오는 중 한 줄.
package struct LoadingRow: View {
    private let text: String

    package init(_ text: String = "불러오는 중…") {
        self.text = text
    }

    package var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text)
                .font(.subheadline)
                .foregroundStyle(MobileTheme.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// 상대 시각("방금" · "5분 전" · "어제" …). `now` 는 스토어 시계에서 받는다(1분마다 다시 그리려면 부모가 TimelineView 로 감싼다).
package struct RelativeTimeText: View {
    private let date: Date
    private let now: Date

    package init(_ date: Date, now: Date) {
        self.date = date
        self.now = now
    }

    package var body: some View {
        Text(MobileRelativeTime.text(for: date, now: now))
            .monospacedDigit()
    }
}
#endif
