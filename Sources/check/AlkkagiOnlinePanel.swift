import SwiftUI
#if ALKKAGI_PLAYGROUND
import AlkkagiCore
#else
import CheckCore
#endif

@MainActor
struct AlkkagiOnlinePanel: View {
    @Bindable var store: AlkkagiOnlineStore
    var onReturn: (() -> Void)? = nil
    @State private var showsPractice = false

    var body: some View {
        Group {
            if showsPractice {
                AlkkagiGameView(onReturn: { showsPractice = false })
            } else if store.state != nil {
                AlkkagiGameView(onReturn: onReturn, onlineStore: store)
            } else {
                lobby
            }
        }
        .onAppear { store.windowDidShow() }
        .onDisappear { store.windowDidHide() }
    }

    private var lobby: some View {
        VStack(alignment: .leading, spacing: BoardGameLayout.headerSpacing) {
            HStack(spacing: 10) {
                Image(systemName: "circle.lefthalf.filled").foregroundStyle(CheckTheme.accent)
                Text("1:1 알까기").font(.title2.weight(.bold))
                Text("비공개 동시 배치 30초, 한 수 30초").font(.caption).foregroundStyle(CheckTheme.secondaryText)
                Spacer()
                Button("로컬 연습") { showsPractice = true }.buttonStyle(.bordered)
                Button { Task { await store.refreshLobby() } } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }.buttonStyle(.bordered).disabled(store.isLoading)
                if let onReturn {
                    Button(action: onReturn) { Label("게임 목록", systemImage: "chevron.left") }.buttonStyle(.bordered)
                }
            }.frame(height: BoardGameLayout.headerHeight)
            HStack(alignment: .top, spacing: BoardGameLayout.columnSpacing) {
                BoardGameChatCard {
                    HStack {
                        Text("상대 고르기").font(.headline)
                        Spacer()
                        Text("참가비 없는 대전").font(.caption).foregroundStyle(CheckTheme.secondaryText)
                    }
                    if let notice = store.notice {
                        Text(notice).font(.caption).foregroundStyle(CheckTheme.pending).fixedSize(horizontal: false, vertical: true)
                    }
                    if store.users.isEmpty {
                        Text(store.isLoading ? "상대를 불러오고 있어요" : "지금 초대할 수 있는 상대가 없어요")
                            .font(.callout).foregroundStyle(CheckTheme.secondaryText)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(store.users, id: \.id) { peer in
                                    HStack(spacing: 12) {
                                        portrait(peer.characterID).frame(width: 42, height: 42)
                                        Text(peer.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                                        Spacer()
                                        Button("도전") { Task { await store.challenge(opponentID: peer.id) } }
                                            .buttonStyle(.borderedProminent)
                                            .disabled(peer.busy == true || store.isBusy || store.outgoing != nil)
                                            .accessibilityLabel("\(peer.displayName)님에게 알까기 도전")
                                    }
                                    .padding(10).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                }.frame(width: 740)
                VStack(spacing: 12) {
                    BoardGameChatCard {
                        Text("받은 신청").font(.headline)
                        if store.incoming.isEmpty {
                            Text("받은 신청이 없어요").font(.caption).foregroundStyle(CheckTheme.secondaryText)
                            Spacer(minLength: 0)
                        } else {
                            ScrollView {
                                VStack(spacing: 12) {
                                    ForEach(store.incoming, id: \.id) { invite in
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack(spacing: 10) {
                                                portrait(invite.opponent.characterID).frame(width: 36, height: 36)
                                                Text(invite.opponent.displayName).font(.callout.weight(.bold))
                                                Spacer()
                                                inviteClock(invite.expiresAtMs)
                                            }
                                            HStack {
                                                Button("거절") { Task { await store.respond(inviteID: invite.id, accept: false) } }
                                                    .buttonStyle(.bordered)
                                                Spacer()
                                                Button("수락하고 시작") { Task { await store.respond(inviteID: invite.id, accept: true) } }
                                                    .buttonStyle(.borderedProminent)
                                            }.disabled(store.isBusy)
                                        }.padding(10).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                        }
                    }
                    BoardGameChatCard {
                        Text("보낸 신청").font(.headline)
                        if let invite = store.outgoing {
                            HStack {
                                Text(invite.opponent.displayName).font(.callout.weight(.semibold))
                                Spacer()
                                inviteClock(invite.expiresAtMs)
                            }
                            Text("상대가 수락하면 돌 배치를 시작해요").font(.caption).foregroundStyle(CheckTheme.secondaryText)
                            Button("신청 취소") { Task { await store.cancelChallenge() } }
                                .buttonStyle(.bordered).disabled(store.isBusy)
                        } else {
                            Text("보낸 신청이 없어요").font(.caption).foregroundStyle(CheckTheme.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }.frame(height: 180)
                }.frame(maxWidth: .infinity)
            }.frame(height: BoardGameLayout.bodyHeight)
        }
        .padding(BoardGameLayout.contentPadding)
        .frame(width: BoardGameLayout.contentSize.width, height: BoardGameLayout.contentSize.height)
        .background(CheckTheme.background).foregroundStyle(CheckTheme.primaryText).preferredColorScheme(.dark)
    }

    private func inviteClock(_ expiresAt: Double) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text("\(max(0, Int(ceil((expiresAt - store.estimatedServerNowMs) / 1_000))))초")
                .font(.caption.monospacedDigit()).foregroundStyle(CheckTheme.secondaryText)
        }
    }

    @ViewBuilder
    private func portrait(_ characterID: String?) -> some View {
#if !ALKKAGI_PLAYGROUND
        if let characterID { CharacterPortrait(characterID: characterID) }
        else { Image(systemName: "person.crop.circle").resizable().scaledToFit() }
#else
        Image(systemName: "person.crop.circle").resizable().scaledToFit().foregroundStyle(CheckTheme.secondaryText)
#endif
    }
}
