#if os(iOS)
import CheckCore
import SwiftUI

// 사람 행 문법(시안 B): 이니셜 틴트 원 + 오른쪽 아래 상태 점 + **이름 뒤** 센터 배지. 상태 칩("근무 중" 칩)은 쓰지 않는다 —
// 이유가 필요할 때만(연결 끊김) 회색·앰버 부제로 말한다.

/// 상태 점(8pt — 초록 근무 중 · 앰버 연결 끊김/대기 · 청회색 근무 안 함).
package struct StatusDot: View {
    private let status: PresenceStatus
    private let size: CGFloat

    package init(_ status: PresenceStatus, size: CGFloat = 8) {
        self.status = status
        self.size = size
    }

    package static func color(_ status: PresenceStatus) -> Color {
        switch status {
        case .working: return MobileTheme.workingDot
        case .pending: return MobileTheme.pendingDot
        case .off: return MobileTheme.offWorkDot
        }
    }

    package var body: some View {
        Circle()
            .fill(Self.color(status))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 다른 사람의 아바타: 사진(있으면) 또는 이니셜 틴트 원 + 오른쪽 아래 상태 점.
///
/// - `colorSeed`: 이니셜 색을 고르는 글자(기본 = 이름 — 맥 `CheckTheme.avatarColor(for:)` 와 같은 해시). 같은 사람이 화면마다
///   같은 색이 되게 이름을 넘긴다.
/// - `status`: nil·`.off` 는 점 없음(시안 B — 근무 안 함은 점을 그리지 않는다). `.working` 초록 · `.pending` 앰버.
/// - `ringColor`: 점 둘레 틈 색 = 아바타가 놓인 면(카드 위 `surface`, 내 행 틴트 위라도 카드 색이면 된다).
/// - 크기는 `AvatarView` 와 같은 규칙으로 글자를 따라 커진다(`MobileAvatarScale`).
package struct PersonAvatar: View {
    private let name: String
    private let colorSeed: String
    private let status: PresenceStatus?
    private let url: URL?
    private let baseSize: CGFloat
    private let ringColor: Color
    private let scalesWithText: Bool
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    package init(
        name: String,
        colorSeed: String? = nil,
        status: PresenceStatus? = nil,
        url: URL? = nil,
        size: CGFloat = 32,
        ringColor: Color = MobileTheme.surface,
        scalesWithText: Bool = true
    ) {
        self.name = name
        self.colorSeed = colorSeed ?? name
        self.status = status
        self.url = url
        self.baseSize = size
        self.ringColor = ringColor
        self.scalesWithText = scalesWithText
    }

    private var size: CGFloat {
        scalesWithText ? MobileAvatarScale.side(base: baseSize, textScale: textScale) : baseSize
    }

    package var body: some View {
        let size = self.size
        ZStack(alignment: .bottomTrailing) {
            face(size: size)
                .frame(width: size, height: size)
                .clipShape(Circle())
            if let status, status != .off {
                let dot = min(13, max(9, size * 0.3))
                StatusDot(status, size: dot)
                    .overlay(Circle().strokeBorder(ringColor, lineWidth: 2).padding(-2))
                    .offset(x: 1, y: 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    @ViewBuilder
    private func face(size: CGFloat) -> some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    InitialAvatar(name: name, size: size, colorSeed: colorSeed)
                }
            }
        } else {
            InitialAvatar(name: name, size: size, colorSeed: colorSeed)
        }
    }

    private var accessibilityText: String {
        switch status {
        case .working: return "\(name), 근무 중"
        case .pending: return "\(name), 연결 끊김"
        case .off, nil: return name
        }
    }
}

/// 이름 줄: 이름 + (센터 배지) + 칩('나' · '우리 팀' · '비공개'). 센터 배지는 **늘 이름 뒤**(아바타 아래·부제에 두지 않는다).
///
/// 순위 탭·게임 탭·지금 탭·메시지가 모두 이 한 벌을 쓴다(같은 이름 줄이 화면마다 다른 부품으로 그려지던 결함 —
/// 비평 4b). 한 줄에 들어가면 이름 뒤에 배지, 안 들어가면(긴 이름) 이름을 줄바꿈하고 배지를 아래 줄로 — 잘라 먹지
/// 않는다. 접근성 글자 크기에서는 늘 아래 줄로 내린다(실측: 가로로 몰면 이름이 한 글자씩 꺾였다).
package struct PersonName: View {
    /// 이름 뒤 칩. 센터 배지는 칩이 아니라 늘 먼저 오는 배지다.
    package enum Chip: Hashable, Sendable {
        /// '나'(파랑).
        case me
        /// '우리 팀' 같은 파랑 강조 칩.
        case accent(String)
        /// '비공개' 같은 회색 칩.
        case muted(String)
    }

    private let name: String
    private let center: String?
    private let chips: [Chip]
    private let font: Font
    private let onTint: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameters:
    ///   - center: 센터 **서버 값**(`CenterLabel` 규약 — 모르는 값·nil 은 배지를 그리지 않는다).
    ///   - isMe: `chips` 앞에 '나' 칩을 넣는 줄임.
    ///   - onTint: 파랑 틴트 행(내 행) 안이면 true — 다크에서 파랑 칩을 테두리형으로 바꾼다(틴트 위 틴트가 3.5:1).
    package init(
        _ name: String,
        center: String? = nil,
        isMe: Bool = false,
        chips: [Chip] = [],
        font: Font = MobileTheme.rowTitle,
        onTint: Bool = false
    ) {
        self.name = name
        self.center = center
        self.chips = isMe ? [.me] + chips : chips
        self.font = font
        self.onTint = onTint
    }

    package var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stacked
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 6) {
                    nameText.lineLimit(1)
                    badges
                }
                stacked
            }
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 2) {
            nameText.fixedSize(horizontal: false, vertical: true)
            if hasBadges { HStack(spacing: 6) { badges } }
        }
    }

    private var nameText: some View {
        Text(name)
            .font(font)
            .foregroundStyle(MobileTheme.label)
    }

    private var hasBadges: Bool { !chips.isEmpty || CenterLabel.display(center) != nil }

    /// 파랑 칩을 테두리형으로 — 틴트 행 안 + 다크에서만(시안 B 다크 보정).
    private var outlinesAccent: Bool { onTint && colorScheme == .dark }

    @ViewBuilder
    private var badges: some View {
        CenterBadge(center)
        ForEach(chips, id: \.self) { chip in
            switch chip {
            case .me:
                MeChip(outlined: outlinesAccent)
            case .accent(let text):
                AingChip(text: text, tint: MobileTheme.accent, background: MobileTheme.accentTint,
                         outlined: outlinesAccent, size: .small, border: MobileTheme.accentLine)
            case .muted(let text):
                AingChip(text: text, tint: MobileTheme.label2, background: MobileTheme.fill,
                         outlined: false, size: .small)
            }
        }
    }
}

/// '나' 칩(파랑 틴트 · 이름 줄 키 `AingChip.Size.small`). `outlined` 는 틴트 행(내 행) 안에서 쓰는 테두리형
/// (다크에서 틴트 위 틴트가 3.5:1 로 떨어진다).
package struct MeChip: View {
    private let outlined: Bool

    package init(outlined: Bool = false) {
        self.outlined = outlined
    }

    package var body: some View {
        AingChip(text: "나", tint: MobileTheme.accent, background: MobileTheme.accentTint,
                 outlined: outlined, size: .small, border: MobileTheme.accentLine)
            .accessibilityLabel(Text("나"))
    }
}

/// 센터 배지("서울"/"부산") — 높이 18 · 회색 채움 · 11pt semibold · 보조 글자. 모르는 값·nil 은 아무것도 그리지 않는다(코어 `CenterLabel`).
package struct CenterBadge: View {
    private let serverValue: String?

    package init(_ serverValue: String?) {
        self.serverValue = serverValue
    }

    package var body: some View {
        if let label = CenterLabel.display(serverValue) {
            Text(label)
                .font(MobileTheme.chip)
                .foregroundStyle(MobileTheme.label2)
                .padding(.horizontal, 6)
                .frame(minHeight: 18)
                .background(Capsule().fill(MobileTheme.fill))
                .fixedSize()
                .accessibilityLabel(Text("\(label)센터"))
        }
    }
}

/// 이니셜 원(시안 B: 해시색 **틴트 원 + 진한 글자** — 맥 `InitialAvatar` 의 채운 원을 폰 밝기에 맞춘 틴트형).
package struct InitialAvatar: View {
    let name: String
    let size: CGFloat
    let colorSeed: String
    @Environment(\.colorScheme) private var colorScheme

    package init(name: String, size: CGFloat, colorSeed: String? = nil) {
        self.name = name
        self.size = size
        self.colorSeed = colorSeed ?? name
    }

    package static func initial(of name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1))
    }

    package var body: some View {
        let pair = MobileThemePalette.avatarInks[MobileThemePalette.avatarIndex(for: colorSeed)]
        let rgb = colorScheme == .dark ? pair.dark : pair.light
        let ink = Color(red: rgb.r, green: rgb.g, blue: rgb.b)
        let tint = colorScheme == .dark ? MobileThemePalette.avatarTintOpacity.dark : MobileThemePalette.avatarTintOpacity.light
        Text(Self.initial(of: name))
            .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .background(Circle().fill(ink.opacity(tint)))
            .accessibilityHidden(true)
    }
}
#endif
