#if os(iOS)
import CheckCore
import SwiftUI

/// 아잉 큐브 로비·순위(설계서 §5 — 레인 A 가 이 파일을 채운다).
/// 입력: `store`(`store.rummy` · `store.rummyEntryBlock` · `store.context`) · `inviteQueue`(방 없이 [초대]는 `inviteQueue.invite(id, store: store.rummy)`) · `tab`(사람 | 순위).
struct GamesRummyLobbyView: View {
    let store: GamesStore
    let inviteQueue: RummyInviteQueue
    @Binding var tab: GamesRummyLobbyTab

    var body: some View {
        VStack(spacing: 12) {
            Picker(GamesRummyText.title, selection: $tab) {
                ForEach(GamesRummyLobbyTab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(GamesRummyText.placeholder("로비 \(tab.title) · 사람 \(store.rummy.lobby?.users?.count ?? 0) · 받은 초대 \(store.rummy.incomingInvites.count) · 공개 방 \(store.rummy.lobby?.publicRooms?.count ?? 0) · 순위 \(store.rummy.ranking?.rows?.count ?? 0)"))
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
            Spacer()
        }
        .padding(.horizontal, MobileTheme.sideMargin)
    }
}
#endif
