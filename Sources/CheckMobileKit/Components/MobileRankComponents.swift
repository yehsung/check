#if os(iOS)
import SwiftUI

// 순위 공용 부품 — 순위 탭(리그·AI 토큰·미니게임)과 게임 탭(미니게임 오늘 순위)이 **같은 순위를 같은 모양으로** 그린다.
// 시안 B: 1–3 금·은·동 원 24(짙은 숫자) · 나머지는 원 없이 흐린 숫자 · 내 행 = 파랑 6% + '나' 칩. 메달 규칙은 모든 순위판에서 같다
// (AI 토큰 탭도 1–3 메달 — 비평 "순위 배지").

/// 순위 숫자 원(24 · 둥근 숫자). 1·2·3위는 메달 원 + 짙은 글자(색만으로 말하지 않는다 — 숫자는 늘 있다), 나머지는 원 없이 `label2`.
package struct RankBadge: View {
    private let rank: Int
    private let usesMedals: Bool
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 24

    package init(rank: Int, usesMedals: Bool = true) {
        self.rank = rank
        self.usesMedals = usesMedals
    }

    package var body: some View {
        let medal = usesMedals ? RankMedal.medal(rank: rank) : nil
        Text("\(rank)")
            .font(MobileTheme.roundedNumber(.footnote, weight: .bold))
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundStyle(medal?.ink ?? MobileTheme.label2)
            .frame(width: size, height: size)
            .background {
                if let medal { Circle().fill(medal.fill) }
            }
            .accessibilityHidden(true)
    }
}

/// 메달 색(토큰 `gold` · `silver` · `bronze` + 짙은 잉크 — 숫자는 `MobileThemePalette` 한 곳).
package enum RankMedal {
    package struct Medal {
        package let fill: Color
        package let ink: Color
    }

    package static let gold = MobileTheme.gold
    package static let silver = MobileTheme.silver
    package static let bronze = MobileTheme.bronze

    package static func medal(rank: Int) -> Medal? {
        switch rank {
        case 1: return Medal(fill: MobileTheme.gold, ink: color(MobileThemePalette.goldInk))
        case 2: return Medal(fill: MobileTheme.silver, ink: color(MobileThemePalette.silverInk))
        case 3: return Medal(fill: MobileTheme.bronze, ink: color(MobileThemePalette.bronzeInk))
        default: return nil
        }
    }

    package static func color(rank: Int) -> Color? {
        medal(rank: rank)?.fill
    }

    private static func color(_ pair: MobileThemePalette.Pair) -> Color {
        Color(red: pair.light.r, green: pair.light.g, blue: pair.light.b)
    }
}

/// 어제 1등 왕관 원(32 · 금 바탕 · 짙은 왕관). 행: 왕관 원 + 이름·점수 + `RubyGain(_, suffix: "받음", style: .chip)`.
package struct CrownBadge: View {
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 32

    package init() {}

    package var body: some View {
        Image(systemName: "crown.fill")
            .font(.system(size: diameter * 0.5, weight: .bold))
            .foregroundStyle(MobileTheme.crownInk)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(MobileTheme.gold))
            .accessibilityHidden(true)
    }
}

/// 작은 캡슐 칩("우리 팀" · "비공개" · "목표 달성"). 뜻 색 틴트 + 같은 색 글자. `outlined` 는 틴트 행 안에서 테두리형.
///
/// 높이 두 벌만 있다(그 사이 값을 만들지 않는다 — 순위 탭과 게임 탭이 각자 18pt 칩을 따로 만들어 같은 이름 줄이
/// 화면마다 다른 높이로 보였다):
/// - `.regular` 22pt · 13pt semibold · 좌우 8(시안 `.b-chip`) — 카드 안 상태 칩.
/// - `.small` 18pt · 11pt bold · 좌우 6(시안 `.b-me-chip`) — **이름 줄**. `CenterBadge` 와 같은 키라 이름 뒤에서 높이가 맞는다.
package struct AingChip: View {
    package enum Size: Sendable {
        case regular
        case small

        var font: Font {
            switch self {
            case .regular: return .system(.caption, weight: .semibold)
            case .small: return .system(.caption2, weight: .bold)
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular: return 8
            case .small: return 6
            }
        }

        var minHeight: CGFloat {
            switch self {
            case .regular: return 22
            case .small: return 18
            }
        }
    }

    private let text: String
    private let tint: Color
    private let background: Color?
    private let outlined: Bool
    private let size: Size
    private let border: Color?

    /// - Parameters:
    ///   - tint: 글자 색(뜻 색 — 파랑 accent · 초록 working · 앰버 pending · 회색 label2).
    ///   - background: 칩 바탕. nil 이면 글자 색 14%(회색 글자면 `MobileTheme.fill` 을 넘긴다).
    ///   - border: 테두리형 선 색. nil 이면 글자 색 38%(파랑 칩은 `MobileTheme.accentLine` 을 넘긴다 — 다크 보정값).
    package init(
        text: String,
        tint: Color = MobileTheme.accent,
        background: Color? = nil,
        outlined: Bool = false,
        size: Size = .regular,
        border: Color? = nil
    ) {
        self.text = text
        self.tint = tint
        self.background = background
        self.outlined = outlined
        self.size = size
        self.border = border
    }

    package var body: some View {
        Text(text)
            .font(size.font)
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, size.horizontalPadding)
            .frame(minHeight: size.minHeight)
            .background {
                if outlined {
                    Capsule().strokeBorder(border ?? tint.opacity(0.38), lineWidth: 1)
                } else {
                    Capsule().fill(background ?? tint.opacity(0.14))
                }
            }
            .fixedSize()
    }
}

/// 순위 한 행의 면. **내 행(내 팀)** 은 파랑 6% 칠(시안 `.b-mine` — 테두리 없음). 남의 행은 면이 없다(인셋 그룹 안의 행).
/// - `standsAlone`: 행마다 카드인 옛 목록(순위 탭)이면 남의 행도 카드 면을 그린다 — 탭 담당이 인셋 그룹으로 옮기면 false.
package struct RankRowSurface: ViewModifier {
    package static let highlightFill = 0.06

    private let isMine: Bool
    private let standsAlone: Bool
    private let padding: CGFloat
    private let cornerRadius: CGFloat

    package init(isMine: Bool, standsAlone: Bool, padding: CGFloat, cornerRadius: CGFloat) {
        self.isMine = isMine
        self.standsAlone = standsAlone
        self.padding = padding
        self.cornerRadius = cornerRadius
    }

    package func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background {
                ZStack {
                    if standsAlone { shape.fill(MobileTheme.surface) }
                    if isMine { shape.fill(MobileTheme.accent.opacity(Self.highlightFill)) }
                }
            }
    }
}

extension View {
    /// `RankRowSurface` 를 건다.
    package func rankRowSurface(isMine: Bool, standsAlone: Bool, padding: CGFloat = 12, cornerRadius: CGFloat = 14) -> some View {
        modifier(RankRowSurface(isMine: isMine, standsAlone: standsAlone, padding: padding, cornerRadius: cornerRadius))
    }
}
#endif
