#if os(iOS)
import CheckCore
import SwiftUI

/// 아잉 큐브 결과(설계서 §6 — 레인 C 가 이 파일을 채운다).
/// 입력: `store` · `inviteQueue`([한 판 더] = `match.rematchInvitees`, 같은 판돈·공개 여부로 `inviteQueue.createAndInvite`). [나가기]는 `store.rummy.dismissResult()`.
struct GamesRummyResultView: View {
    let store: GamesStore
    let inviteQueue: RummyInviteQueue

    var body: some View {
        VStack(spacing: 12) {
            Text(GamesRummyText.placeholder("결과 · 자리 \(store.rummy.match?.seats?.count ?? 0)"))
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
            Button(GamesRummyText.toLobby) { store.rummy.dismissResult() }
            Spacer()
        }
        .padding(.horizontal, MobileTheme.sideMargin)
    }
}
#endif
