#if os(iOS)
import SwiftUI

// 목록(`List`) 한 절의 행들이 이어져 **`AingCard`·`InsetGroup` 한 장과 같은 모양**(반경 `MobileTheme.groupRadius` · surface · 테두리 없음)이
// 되게 하는 행 조각. 밀어서 삭제(`swipeActions`)처럼 `List` 가 꼭 필요한 탭(지금 탭 할 일)이 스크롤 카드 탭(순위·게임·나)과 같은 카드를 그린다.
//
// 시스템 `insetGrouped` 절 모양을 쓰지 않는 이유: 셀을 시스템 반경으로 잘라 조각 모서리가 탭마다 달라 보였다(통합 검증 corners-L-a.png).
// 쓰는 법: 절의 행마다 `.cardSegmentRow(_:)` — 배경은 투명, 행 여백 0, 조각을 뒤에 그린다.
// 자리 계산(`CardSegmentPosition`)은 순수 규칙 파일(`MobileComponentRules.swift`)에 있다. 구분선은 0.5pt · 글자 시작점부터(시안 B).

/// 카드 조각 한 장(채움만 — 시안 B 인셋 그룹은 테두리가 없다). 끝이 아닌 조각은 아래에 안쪽 구분선을 긋는다.
package struct CardSegmentBackground: View {
    private let position: CardSegmentPosition
    private let showsDivider: Bool
    private let dividerLeading: CGFloat
    @Environment(\.displayScale) private var displayScale

    package init(_ position: CardSegmentPosition, showsDivider: Bool = false, dividerLeading: CGFloat = MobileTheme.cardPadding) {
        self.position = position
        self.showsDivider = showsDivider
        self.dividerLeading = dividerLeading
    }

    package var body: some View {
        let radius = MobileTheme.groupRadius
        let top = position.roundsTop ? radius : 0
        let bottom = position.roundsBottom ? radius : 0
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: bottom, topTrailingRadius: top,
            style: .continuous
        )
        ZStack(alignment: .bottomLeading) {
            shape.fill(MobileTheme.surface)
            if showsDivider, !position.roundsBottom {
                Rectangle()
                    .fill(MobileTheme.separator)
                    .frame(height: max(MobileTheme.hairline, 1 / max(displayScale, 1)))
                    .padding(.leading, dividerLeading)
            }
        }
    }
}

extension View {
    /// 이 행을 카드 조각으로 그린다. **`.listStyle(.grouped)` 목록에서 쓴다** — `insetGrouped` 는 셀 자체를 시스템 반경(약 18~26pt)으로
    /// 잘라 이 조각의 16pt 모서리와 테두리가 가려졌다(int-fix 실측 zoom-after2-L-now). grouped 는 셀이 화면 폭이라 자르지 않는다.
    /// - 행 여백 0 · 시스템 행 배경·구분선 없음 · 좌우 `MobileTheme.sideMargin` 바깥 여백 · 안쪽 여백은 `padding`.
    /// - Parameter separatorVisible: 다음 행과의 안쪽 구분선(끝·단독 조각은 늘 없음). `dividerLeading` 은 카드 왼쪽에서 선이 시작하는 곳.
    package func cardSegmentRow(
        _ position: CardSegmentPosition,
        padding: EdgeInsets = EdgeInsets(top: 10, leading: MobileTheme.cardPadding, bottom: 10, trailing: MobileTheme.cardPadding),
        separatorVisible: Bool = true,
        dividerLeading: CGFloat = MobileTheme.cardPadding
    ) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardSegmentBackground(position, showsDivider: separatorVisible, dividerLeading: dividerLeading))
            .padding(.horizontal, MobileTheme.sideMargin)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// 카드가 아닌 행(안내 띠 · 빈 상태 카드)을 grouped 목록에서 다른 탭과 같은 좌우 여백으로 둔다.
    package func cardListPlainRow(top: CGFloat = 6, bottom: CGFloat = 6) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: MobileTheme.sideMargin, bottom: bottom, trailing: MobileTheme.sideMargin))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
#endif
