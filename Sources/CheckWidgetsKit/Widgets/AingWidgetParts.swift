#if os(iOS)
import CheckMobileShared
import SwiftUI
import WidgetKit

// 위젯 부품(시안 B 위젯 보드). 위젯 확장은 앱 부품(CheckMobileKit)을 링크하지 않는다 — 초상 · 이니셜 원 · 막대 · 체크 원 · 칩을
// 여기 file 밖 internal 로 둔다(통합 때 앱 부품과 같은 규칙인지 `WidgetDesignTests` 가 숫자로 대조).
//
// 렌더링 모드: 원색(`.fullColor`)은 `AingWidgetColors`(위젯 바탕에 겹친 불투명 토큰), 틴트·투명(`.accented`)은 시스템이 색을 버리고
// 불투명도만 남긴다 — 그래서 `AingWidgetInk` 가 모드를 보고 흰색 + 위계 불투명도로 바꾼다. 뜻을 가진 채움(상태 글자 · 점 · 진행 막대 ·
// 체크된 원 · 앱에서 추가)만 `widgetAccentable()` 로 틴트 색을 받는다.

// MARK: - 색

enum AingWidgetColors {
    static let background = color(AingWidgetPalette.background)
    static let elevated = color(AingWidgetPalette.cardElevated)
    static let primary = color(AingWidgetPalette.primaryText)
    static let secondary = color(AingWidgetPalette.secondaryText)
    static let tertiaryText = color(AingWidgetPalette.tertiaryText)
    static let tertiarySymbol = color(AingWidgetPalette.tertiarySymbol)
    static let separator = color(AingWidgetPalette.separator)
    static let surface2 = color(AingWidgetPalette.surface2)
    static let working = color(AingWidgetPalette.working)
    static let workingDot = color(AingWidgetPalette.workingDot)
    static let offWork = color(AingWidgetPalette.offWork)
    static let offWorkDot = color(AingWidgetPalette.offWorkDot)
    static let pending = color(AingWidgetPalette.pending)
    static let pendingDot = color(AingWidgetPalette.pendingDot)
    static let accent = color(AingWidgetPalette.accent)
    static let accentFill = color(AingWidgetPalette.accentFill)
    static let track = color(AingWidgetPalette.track)
    static let avatarInks = AingWidgetPalette.avatarInks.map(color)

    static func color(_ pair: AingWidgetPalette.Pair) -> Color {
        let light = ui(pair.light), dark = ui(pair.dark)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    private static func ui(_ hex: UInt32) -> UIColor {
        let c = AingWidgetPalette.components(hex)
        return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
    }
}

/// 렌더링 모드에 맞춘 글자·선 색. 원색은 토큰 그대로, 틴트·투명은 흰색 + 위계 불투명도.
struct AingWidgetInk {
    let accented: Bool

    init(_ mode: WidgetRenderingMode) {
        accented = mode == .accented
    }

    var primary: Color { accented ? .white : AingWidgetColors.primary }
    var secondary: Color { accented ? .white.opacity(AingWidgetPalette.Accented.secondaryText) : AingWidgetColors.secondary }
    var tertiaryText: Color { accented ? .white.opacity(AingWidgetPalette.Accented.tertiaryText) : AingWidgetColors.tertiaryText }
    var symbol: Color { accented ? .white.opacity(AingWidgetPalette.Accented.symbol) : AingWidgetColors.tertiarySymbol }
    var separator: Color { accented ? .white.opacity(AingWidgetPalette.Accented.separator) : AingWidgetColors.separator }
    var fill: Color { accented ? .white.opacity(AingWidgetPalette.Accented.fill) : AingWidgetColors.elevated }
    var track: Color { accented ? .white.opacity(AingWidgetPalette.Accented.track) : AingWidgetColors.track }

    /// 뜻 색 글자(틴트 모드에서는 `widgetAccentable` 과 함께 틴트 색이 된다).
    func state(_ status: WidgetSnapshot.WorkState) -> Color {
        if accented { return .white }
        switch status {
        case .working: return AingWidgetColors.working
        case .disconnected: return AingWidgetColors.pending
        case .off: return AingWidgetColors.offWork
        }
    }

    func dot(_ status: WidgetSnapshot.WorkState) -> Color {
        if accented { return status == .off ? .white.opacity(AingWidgetPalette.Accented.symbol) : .white }
        switch status {
        case .working: return AingWidgetColors.workingDot
        case .disconnected: return AingWidgetColors.pendingDot
        case .off: return AingWidgetColors.offWorkDot
        }
    }
}

// MARK: - 글꼴

/// 시안 px 크기를 텍스트 스타일 배율로 키운다(위젯 칸 상한 xxLarge 까지 — `AingWidgetContainer`).
private struct AingScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    func aingFont(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle) -> some View {
        modifier(AingScaledFont(size: size, weight: weight, relativeTo: style))
    }
}

// MARK: - 초상

/// 착용 캐릭터 초상(나를 가리키는 자리 — 내 오늘) · 빈 상태 아잉. 표정 = 상태, 링 = 뜻 색(원색만).
/// 틴트·투명에서는 링·발광을 빼고 그림을 흑백으로(시안 "투명 — 초상 흑백").
struct AingWidgetPortrait: View {
    let id: String
    let mood: AingWidgetMood
    let size: CGFloat
    /// 표정을 상태와 따로 줄 때(로그아웃 = 시무룩 아잉). nil 이면 기분의 표정.
    var expression: AingCharacterArt.Expression? = nil
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let accented = renderingMode == .accented
        ZStack {
            Circle().fill(backing(accented: accented))
            if mood == .working, !accented {
                // 안쪽 발광(시안 inset 0 0 s*.25 rgba(47,196,126,.25)).
                Circle()
                    .strokeBorder(AingWidgetColors.workingDot.opacity(0.25), lineWidth: size * 0.16)
                    .blur(radius: size * 0.08)
            }
            art
                .frame(width: size * 0.88, height: size * 0.88)
                // 시안 background-position 50% 62%: 남는 12% 중 62% 만큼 위에서 내려온다.
                .offset(y: size * 0.12 * 0.12)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if let ring = ringColor {
                let width = CGFloat(AingWidgetMood.ringWidth(diameter: Double(size)))
                let gap = CGFloat(AingWidgetMood.ringGap)
                if accented {
                    // 틴트·투명: 바탕이 걷히므로 틈은 비워 두고 링만 강조 색으로(시안 `--ring: transparent` · 링 흰색) —
                    // 흐린 흑백 초상이 유리 위에서 묻히지 않게 테두리가 자리를 잡아 준다.
                    Circle().strokeBorder(Color.white, lineWidth: width).padding(-(gap + width)).widgetAccentable()
                } else {
                    Circle().strokeBorder(AingWidgetColors.background, lineWidth: gap).padding(-gap)
                    Circle().strokeBorder(ring, lineWidth: width).padding(-(gap + width))
                }
            }
        }
        .background {
            if mood == .working, !accented {
                Circle()
                    .fill(AingWidgetColors.workingDot.opacity(0.35))
                    .blur(radius: size * 0.15)
                    .padding(-size * 0.04)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var art: some View {
        if let image = AingCharacterArt.portraitImage(id: id, expression: expression ?? mood.expression) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .widgetAccentedRenderingMode(.desaturated)
                .scaledToFit()
        }
    }

    private func backing(accented: Bool) -> Color {
        if accented { return .white.opacity(AingWidgetPalette.Accented.fill) }
        switch mood {
        case .working: return AingWidgetColors.workingDot.opacity(AingWidgetPalette.workingTintOpacity)
        case .lost: return AingWidgetColors.pendingDot.opacity(AingWidgetPalette.pendingTintOpacity)
        case .off: return AingWidgetColors.elevated
        case .plain: return AingWidgetColors.surface2
        }
    }

    private var ringColor: Color? {
        switch mood {
        case .working: return AingWidgetColors.workingDot
        case .lost: return AingWidgetColors.pendingDot
        case .off: return AingWidgetColors.offWorkDot
        case .plain: return nil
        }
    }
}

// MARK: - 이니셜 원 · 얼굴 더미

/// 다른 사람: 이니셜 틴트 원(맥 해시 색). 틴트·투명에서는 흰 글자 + 옅은 흰 원.
struct AingWidgetInitialAvatar: View {
    let name: String
    let size: CGFloat
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let accented = renderingMode == .accented
        let ink = accented ? Color.white : AingWidgetColors.avatarInks[AingWidgetInitial.paletteIndex(for: name)]
        let tint = accented ? AingWidgetPalette.Accented.fill
            : (colorScheme == .dark ? AingWidgetPalette.avatarTintOpacity.dark : AingWidgetPalette.avatarTintOpacity.light)
        Text(AingWidgetInitial.letter(of: name))
            .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .background(Circle().fill(ink.opacity(tint)))
            .accessibilityHidden(true)
    }
}

/// 다른 사람 얼굴: 착용 캐릭터를 알면 neutral 초상(받침 원 안 — 앱 `PersonCharacterFace` 와 같은 배치), 모르면 이니셜 원.
/// 위젯은 사진을 그리지 않는다(네트워크 없음) — 사진을 올린 사람도 앱의 '사진을 못 불러왔을 때'처럼 캐릭터로 선다.
/// 틴트·투명에서는 받침을 옅은 흰 원으로, 그림을 흑백으로(내 초상 `AingWidgetPortrait` 와 같은 규칙).
struct AingWidgetPersonFace: View {
    let name: String
    /// `WidgetSnapshot.WorkingPerson.knownCharacterID`(이 빌드에 초상이 있는 id 만). nil = 이니셜.
    let characterID: String?
    let size: CGFloat
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if let characterID, let image = AingCharacterArt.portraitImage(id: characterID, expression: .neutral) {
            let accented = renderingMode == .accented
            ZStack {
                Circle().fill(accented ? .white.opacity(AingWidgetPalette.Accented.fill) : AingWidgetColors.surface2)
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .widgetAccentedRenderingMode(.desaturated)
                    .scaledToFit()
                    .frame(width: size * 0.88, height: size * 0.88)
                    .offset(y: size * 0.05)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
        } else {
            AingWidgetInitialAvatar(name: name, size: size)
        }
    }
}

/// 겹친 얼굴(시안 margin-left −7 · 둘레 2pt). 둘레를 바탕색으로 칠하지 않고 **다음 얼굴 자리를 도려낸다** — 틴트·투명에서 바탕색 둘레가
/// 흰 고리로 보이지 않게. 얼굴은 `AingWidgetPersonFace`(착용 캐릭터 → 이니셜).
struct AingWidgetFacepile: View {
    let people: [WidgetSnapshot.WorkingPerson]
    let size: CGFloat
    var overlap: CGFloat = 7
    var gap: CGFloat = 2

    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(people.enumerated()), id: \.offset) { index, person in
                AingWidgetPersonFace(name: person.name, characterID: person.knownCharacterID, size: size)
                    .mask {
                        if index < people.count - 1 {
                            AingCutout(offsetX: size - overlap, gap: gap)
                                .fill(style: FillStyle(eoFill: true))
                        } else {
                            Rectangle()
                        }
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

/// 사각형에서 오른쪽 이웃 원(+둘레)을 뺀 모양.
private struct AingCutout: Shape {
    let offsetX: CGFloat
    let gap: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect.insetBy(dx: -gap * 2, dy: -gap * 2))
        path.addEllipse(in: CGRect(x: rect.minX + offsetX - gap, y: rect.minY - gap, width: rect.width + gap * 2, height: rect.height + gap * 2))
        return path
    }
}

// MARK: - 막대 · 점 · 체크 · 칩

/// 이번 주 막대(링 대신 — 틴트에서 트랙과 진행이 한 색이 되어 62%가 꽉 찬 원으로 보였다).
struct AingWidgetBar: View {
    let progress: Double
    let isComplete: Bool
    var height: CGFloat = 5
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let ink = AingWidgetInk(renderingMode)
        GeometryReader { proxy in
            let clamped = min(1, max(0, progress))
            ZStack(alignment: .leading) {
                Capsule().fill(ink.track)
                Capsule()
                    .fill(ink.accented ? Color.white : (isComplete ? AingWidgetColors.workingDot : AingWidgetColors.accent))
                    .frame(width: clamped > 0 ? max(height, proxy.size.width * clamped) : 0)
                    .widgetAccentable()
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct AingWidgetDot: View {
    let status: WidgetSnapshot.WorkState
    var size: CGFloat = 7
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Circle()
            .fill(AingWidgetInk(renderingMode).dot(status))
            .frame(width: size, height: size)
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}

/// 할 일 체크 원(22pt): 빈 원 = 3단 선, 완료 = 파랑 채움 + 흰 체크(틴트·투명에서는 체크를 도려낸 원).
struct AingWidgetCheck: View {
    let isDone: Bool
    var size: CGFloat = 22
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let ink = AingWidgetInk(renderingMode)
        Group {
            if !isDone {
                Circle().strokeBorder(ink.symbol, lineWidth: 1.8)
            } else if ink.accented {
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
                    .widgetAccentable()
            } else {
                Circle()
                    .fill(AingWidgetColors.accentFill)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: size * 0.42, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 회색 칩(이월 배지 "어제" · 남은 개수) — 앰버 금지(시안 B: 이월은 경고가 아니다).
struct AingWidgetChip: View {
    let text: String
    var height: CGFloat = 20
    var fontSize: CGFloat = 11
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let ink = AingWidgetInk(renderingMode)
        Text(text)
            .aingFont(fontSize, .semibold, relativeTo: .caption2)
            .monospacedDigit()
            .foregroundStyle(ink.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, fontSize >= 12 ? 9 : 7)
            .frame(minHeight: height)
            .background(Capsule().fill(ink.fill))
    }
}

// MARK: - 빈 상태

/// 로그아웃 · 할 일 없음 · 0명 · 내 오늘 모름: 캐릭터 + 다음 행동(시안 "칸을 채운다").
struct AingWidgetEmptyState: View {
    enum Layout { case stacked, row }

    let characterID: String
    let mood: AingWidgetMood
    let expression: AingCharacterArt.Expression?
    let title: String
    let hint: String?
    let layout: Layout
    let portraitSize: CGFloat
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let ink = AingWidgetInk(renderingMode)
        switch layout {
        case .stacked:
            VStack(spacing: 8) {
                AingWidgetPortrait(id: characterID, mood: mood, size: portraitSize, expression: expression)
                VStack(spacing: 2) {
                    Text(title)
                        .aingFont(13, .semibold, relativeTo: .footnote)
                        .foregroundStyle(ink.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let hint {
                        Text(hint)
                            .aingFont(12, relativeTo: .caption)
                            .foregroundStyle(ink.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        case .row:
            HStack(spacing: 14) {
                AingWidgetPortrait(id: characterID, mood: mood, size: portraitSize, expression: expression)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .aingFont(15, .bold, relativeTo: .subheadline)
                        .foregroundStyle(ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let hint {
                        Text(hint)
                            .aingFont(13, relativeTo: .footnote)
                            .foregroundStyle(ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}
#endif
