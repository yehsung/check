#if os(iOS)
import CheckCore
import SwiftUI

/// 아잉 큐브 방(설계서 §5 — 레인 A 가 이 파일을 채운다).
/// 입력: `store` · `inviteQueue` · `onExit`([나가기] — 방장 확인·손님 나가기는 화면 한 곳이 가른다).
struct GamesRummyRoomView: View {
    let store: GamesStore
    let inviteQueue: RummyInviteQueue
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(GamesRummyText.placeholder("방 \(store.rummy.myRoom?.seats?.count ?? 0)자리"))
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
            Button(GamesRummyText.leave, action: onExit)
            Spacer()
        }
        .padding(.horizontal, MobileTheme.sideMargin)
    }
}
#endif
