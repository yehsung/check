#if os(iOS)
import CheckCore
import SwiftUI

/// 미니게임 순위 머리의 **[오늘 | 역대] 전환**(맥 0.3.67 → 폰 1.0.15). 맥 `MiniGameBoardScopePicker` 의 폰판이다.
///
/// 글자는 코어 한 벌이다 — 칸 이름은 `MiniGameBoardScope.label`("오늘" · "역대"), 보이스오버 이름은 `boardTitle`
/// ("오늘 순위" · "역대 순위"). 두 자만 읽어 주면 **무엇을 고르는지 안 들린다**(맥이 같은 이유로 판 이름을 준다).
///
/// 모양 결정(맥의 까닭을 폰 토큰으로 옮긴 것)
/// · **한 캡슐 안의 두 칸**이다. 떨어진 칩 둘로 두면 머리 오른쪽에 서는 다른 알약들(순위 탭의 '게임 고르기' ·
///   기간 넘기기)과 같은 물건으로 읽혀, 누르면 목록이 열릴 것처럼 보인다.
/// · 겉 알약은 그 둘과 같은 회색(`MobileTheme.fill` · 보이는 높이 30)이고 **고른 칸만** 틴트 채움 + 선이다 —
///   이 저장소 규약("화면당 채운 버튼은 하나")에서 전환은 주요 동작이 아니다.
/// · **누름 영역은 44pt.** 보이는 칸이 26 이라 세로 패딩 9 로 벌리고 같은 값의 음수 패딩으로 레이아웃을 되돌린다
///   (`RankingsGameMenu` 가 7/30 으로 쓰는 그 수법) — 머리글을 키우지 않으면서 손가락 몫을 준다.
/// · `.disabled()` 를 쓰지 않는다. 같은 쪽을 다시 눌러도 허브가 아무 일도 안 하고(`selectBoardScope` 의 첫 가드),
///   비활성 요소는 보이스오버 목록에서 사라져 "지금 무엇을 보고 있나"를 들을 수 없게 된다.
struct GamesBoardScopePicker: View {
    let selected: MiniGameBoardScope
    let select: (MiniGameBoardScope) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MiniGameBoardScope.allCases) { scope in
                segment(scope)
            }
        }
        .padding(2)
        .background(Capsule().fill(MobileTheme.fill))
        .fixedSize()
    }

    private func segment(_ scope: MiniGameBoardScope) -> some View {
        let isSelected = scope == selected
        return Button { select(scope) } label: {
            Text(scope.label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? MobileTheme.accent : MobileTheme.label2)
                .padding(.horizontal, 12)
                .frame(minHeight: 26)
                .background(Capsule().fill(isSelected ? MobileTheme.accentTint : Color.clear))
                .overlay(Capsule().strokeBorder(isSelected ? MobileTheme.accentLine : Color.clear, lineWidth: 1))
                .padding(.vertical, 9)
                .contentShape(Capsule())
                .padding(.vertical, -9)
        }
        .buttonStyle(.plain)
        // 두 자("오늘")만으로는 무엇을 고르는지 안 들린다 — 보이스오버에는 판 이름을 준다(맥과 같다).
        .accessibilityLabel(Text(scope.boardTitle))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
