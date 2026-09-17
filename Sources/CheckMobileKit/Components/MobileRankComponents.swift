#if os(iOS)
import SwiftUI

// 순위 목록 공용 부품 — 순위 탭(리그·AI 토큰·미니게임)과 게임 탭(미니게임 오늘 순위)이 **같은 순위를 같은 모양으로** 그린다.
// 통합 검증: 같은 "미니게임 오늘 순위"가 순위 탭은 금·은·동 + 짙은 숫자 · 내 행 파란 테두리, 게임 탭은 갈색·청회·보라 + 흰 숫자 ·
// 칩만으로 갈려 있었다(crop-rank-colors-L.png).

/// 순위 숫자 원. 1·2·3위는 메달 색(안의 글자는 늘 숫자 — 색만으로 말하지 않는다), 나머지는 흐린 숫자.
package struct RankBadge: View {
    private let rank: Int
    private let usesMedals: Bool
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 28

    package init(rank: Int, usesMedals: Bool = true) {
        self.rank = rank
        self.usesMedals = usesMedals
    }

    package var body: some View {
        let medal = usesMedals ? RankMedal.color(rank: rank) : nil
        Text("\(rank)")
            .font(MobileTheme.number(.subheadline, weight: .heavy))
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundStyle(medal == nil ? MobileTheme.secondaryText : RankMedal.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(medal ?? MobileTheme.cardElevated))
            .accessibilityHidden(true)
    }
}

/// 메달 색(맥 `MiniGameMedal` 과 같은 숫자). 메달 위 글자는 짙은 잉크 — 금·은 위 흰 글자는 대비가 무너진다.
package enum RankMedal {
    package static let gold = Color(red: 1.00, green: 0.824, blue: 0.290)
    package static let silver = Color(red: 0.839, green: 0.863, blue: 0.902)
    package static let bronze = Color(red: 0.878, green: 0.584, blue: 0.353)
    package static let ink = Color.black.opacity(0.82)

    package static func color(rank: Int) -> Color? {
        switch rank {
        case 1: return gold
        case 2: return silver
        case 3: return bronze
        default: return nil
        }
    }
}

/// 작은 캡슐 칩("나" · "우리 팀" · "비공개" · "루비 +20 받음").
package struct AingChip: View {
    private let text: String
    private let tint: Color

    package init(text: String, tint: Color = MobileTheme.accent) {
        self.text = text
        self.tint = tint
    }

    package var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.16)))
            .fixedSize()
    }
}

/// 순위 한 행의 면. **내 행(내 팀)** 은 accent 옅은 채움 + accent 테두리 — 두 탭 공통 강조 규칙.
/// - `standsAlone`: 행마다 카드인 목록(순위 탭)이면 남의 행도 카드 면·선을 그린다. 한 카드 안에 줄지은 목록(게임 탭)이면 남의 행은 면이 없다.
package struct RankRowSurface: ViewModifier {
    package static let highlightFill = 0.08
    package static let highlightStroke = 0.7
    package static let highlightLineWidth: CGFloat = 1.5

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
            .background(shape.fill(isMine ? MobileTheme.accent.opacity(Self.highlightFill) : (standsAlone ? MobileTheme.card : Color.clear)))
            .overlay(
                shape.stroke(
                    isMine ? MobileTheme.accent.opacity(Self.highlightStroke) : (standsAlone ? MobileTheme.separator : Color.clear),
                    lineWidth: isMine ? Self.highlightLineWidth : 1
                )
            )
    }
}

extension View {
    /// `RankRowSurface` 를 건다.
    package func rankRowSurface(isMine: Bool, standsAlone: Bool, padding: CGFloat = 12, cornerRadius: CGFloat = 14) -> some View {
        modifier(RankRowSurface(isMine: isMine, standsAlone: standsAlone, padding: padding, cornerRadius: cornerRadius))
    }
}
#endif
