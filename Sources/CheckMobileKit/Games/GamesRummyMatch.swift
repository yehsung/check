#if os(iOS)
import CheckCore
import SwiftUI

/// 아잉 큐브 판(설계서 §4 — 레인 B 가 이 파일을 채운다). 칸 자리·보기·누르기 판정은 `GamesRummyBoardGeometry.swift` 의 값으로 짠다.
/// 입력: `store` · `onExit`([나가기] — 기권 확인·놀던 기기는 화면 한 곳이 가른다).
/// 다른 기기 판: `store.rummy.isEngagedInCurrentMatch == false` 면 `GamesRummyText.elsewhereTitle` 안내 카드 + 읽기만(입력은 막지 않는다 — 맥과 같다).
/// 탭 막대는 공용 수단으로만 숨긴다(`.hidesTabBar(for: .rummyMatch)`). 머리 줄이 판 안에 있어 내비 막대도 숨기고, 숨기면 시스템 뒤로 쓸기도 함께 꺼진다.
struct GamesRummyMatchView: View {
    let store: GamesStore
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(GamesRummyText.placeholder("판 · 묶음 \(store.rummy.editor?.melds.count ?? store.rummy.match?.table?.count ?? 0) · 받침대 \(store.rummy.editor?.rack.count ?? 0)장 · 내 차례 \(store.rummy.isMyTurn ? "예" : "아니오") · 이 기기 \(store.rummy.isEngagedInCurrentMatch ? "손댐" : "놀던 기기")"))
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
            Button(GamesRummyText.leave, action: onExit)
            Spacer()
        }
        .padding(.horizontal, MobileTheme.sideMargin)
        .hidesTabBar(for: .rummyMatch)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }
}
#endif
