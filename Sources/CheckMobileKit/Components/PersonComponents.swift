#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

// 사람 행 문법(시안 B): 얼굴(사진 → 착용 캐릭터 → 이니셜 틴트 원) + 오른쪽 아래 상태 점 + **이름 뒤** 센터 배지. 상태 칩("근무 중" 칩)은
// 쓰지 않는다 — 이유가 필요할 때만(연결 끊김) 회색·앰버 부제로 말한다.

// MARK: - 기본 아바타 = 착용 캐릭터(2026-09-20 사용자 요청)
//
// 사람 아바타의 우선순위(정본은 코어 `AppUserCharacterDirectory.avatar(for:photoURL:)`):
//   ① 올린 사진 → ② 그 사람의 착용 캐릭터(neutral 초상 · 원형) → ③ 캐릭터를 **모를 때만** 이니셜(첫 조회 전 · 표에 없는 사람 · 이 빌드가
//   모르는 새 캐릭터). 착용값 null 은 아잉이다. 사진을 불러오는 중이거나 실패하면 이니셜이 아니라 캐릭터로 떨어진다(`afterPhotoFailure`).
// 표는 앱 모델의 `AppUserCharacterStore` 가 받고 탭 막대가 이 환경값으로 흘린다 — 호출부는 **사용자 id** 만 넘긴다.
// 시트(`.sheet`)도 띄운 화면의 환경값을 이어받는다. 환경값이 없는 자리(부품 견본 · 미리보기)는 빈 표 = 지금처럼 이니셜.

private struct AppUserCharactersKey: EnvironmentKey {
    static let defaultValue = AppUserCharacterDirectory(knownIDs: AingCharacterArt.knownIDs)
}

extension EnvironmentValues {
    /// 사람 아바타가 찾는 캐릭터 한 표(`MobileTabsView` 가 `AppUserCharacterStore.directory` 를 건다). 기본값은 빈 표(전원 이니셜).
    package var appUserCharacters: AppUserCharacterDirectory {
        get { self[AppUserCharactersKey.self] }
        set { self[AppUserCharactersKey.self] = newValue }
    }
}

/// 사람 아바타의 얼굴 한 벌(판정 결과 → 그림). `PersonAvatar` 와 `AvatarView` 가 같이 쓴다 — 두 부품이 다른 규칙으로 갈리지 않게.
/// 원형 자르기 · 크기 · 상태 점은 부르는 쪽 몫이다(이 뷰는 정사각 `size` 를 채운다).
package struct AppUserAvatarFace: View {
    private let avatar: AppUserAvatar
    private let name: String
    private let colorSeed: String
    private let size: CGFloat

    package init(avatar: AppUserAvatar, name: String, colorSeed: String? = nil, size: CGFloat) {
        self.avatar = avatar
        self.name = name
        self.colorSeed = colorSeed ?? name
        self.size = size
    }

    package var body: some View {
        if case .photo(let url, _) = avatar {
            AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    // 불러오는 중 · 실패: 이니셜이 아니라 그 사람의 캐릭터(모르면 이니셜).
                    still(avatar.afterPhotoFailure)
                }
            }
        } else {
            still(avatar)
        }
    }

    @ViewBuilder
    private func still(_ avatar: AppUserAvatar) -> some View {
        if case .character(let id) = avatar {
            PersonCharacterFace(id: id, size: size)
        } else {
            InitialAvatar(name: name, size: size, colorSeed: colorSeed)
        }
    }
}

/// 다른 사람의 착용 캐릭터 얼굴 — neutral 초상을 받침(surface2) 원 안에(초상 `.plain` 과 같은 배치: 그림 88% · 아래로 5%).
/// 링·발광·표정 변화는 없다(남의 근무 상태는 상태 점이 말한다). `id` 는 이미 이 빌드가 아는 캐릭터다(모르면 호출부가 이니셜을 그린다).
package struct PersonCharacterFace: View {
    private let id: String
    private let size: CGFloat
    @Environment(\.displayScale) private var displayScale

    package init(id: String, size: CGFloat) {
        self.id = id
        self.size = size
    }

    package var body: some View {
        let side = size * 0.88
        ZStack {
            Circle().fill(MobileTheme.surface2)
            ArtImage(
                MobileArt.character(id: id, expression: .neutral, pointSize: side, displayScale: displayScale),
                size: CGSize(width: side, height: side)
            )
            .offset(y: size * 0.05)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

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

/// 다른 사람의 아바타: 사진 → 착용 캐릭터 → 이니셜 틴트 원(`AppUserAvatarFace`) + 오른쪽 아래 상태 점.
///
/// - `userID`: 이 사람의 사용자 id — 환경값 `\.appUserCharacters` 에서 착용 캐릭터를 찾는 열쇠. **모든 호출부가 넘긴다**(기본값이 없는
///   이유 — 빠뜨리면 그 자리만 이니셜로 남는다). 사람이 아닌 자리(팀 줄 · 부품 견본)만 nil.
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
    private let userID: String?
    private let baseSize: CGFloat
    private let ringColor: Color
    private let scalesWithText: Bool
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1
    @Environment(\.appUserCharacters) private var characters

    package init(
        name: String,
        colorSeed: String? = nil,
        status: PresenceStatus? = nil,
        url: URL? = nil,
        userID: String?,
        size: CGFloat = 32,
        ringColor: Color = MobileTheme.surface,
        scalesWithText: Bool = true
    ) {
        self.name = name
        self.colorSeed = colorSeed ?? name
        self.status = status
        self.url = url
        self.userID = userID
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
            AppUserAvatarFace(avatar: characters.avatar(for: userID, photoURL: url), name: name, colorSeed: colorSeed, size: size)
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

    /// 파랑 칩을 테두리형으로 — **틴트 행 안이면 라이트·다크 모두**. 틴트 위 틴트는 라이트 4.46:1 · 다크 3.5:1 로 둘 다 4.5:1 에 못 미친다
    /// (w15 검증 낮음 3 실측: 내 행 accent 6% 위 칩 accentTint 10% → 글자 4.464:1). 테두리형은 칠을 빼 글자가 행 바탕 위에 바로 앉아
    /// 라이트 4.9:1 로 올라간다.
    private var outlinesAccent: Bool { onTint }

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
/// (틴트 위 틴트가 라이트 4.46:1 · 다크 3.5:1 로 둘 다 4.5:1 에 못 미친다 — 내 행 안에서는 라이트·다크 모두 테두리형).
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
