import SwiftUI
import CheckCore

// MARK: - 아잉 마작 로비 (SPEC §5.8)
//
// 머리글(아이콘·제목·전적 캡슐 "평균 N.NN등 · M판"(10판 전 "M판 · 10판부터 순위")·루비 칩·[혼자 연습]·[규칙])
// + 두 열 [사람·순위 탭 440 | 오른쪽 740 = 탁자 카드(방 또는 방 만들기) + 받은 초대·공개 방 카드 줄]. 숫자는 큐브 그대로.
// 관전 없음(카드 ④) — 로비에 '지금 대국 중' 목록·[관전] 단추가 없다.

struct MahjongLobbyHeader: View {
    let store: MahjongStore
    var cramped = false
    let onPractice: () -> Void
    let onRules: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: MahjongEntryIcon.resolved)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(CheckTheme.pending)
                .frame(width: 36, height: 36)
                .background(Circle().fill(CheckTheme.pending.opacity(0.16)))
            VStack(alignment: .leading, spacing: 1) {
                Text(MahjongText.title).font(.title3.weight(.bold))
                Text(cramped ? MahjongText.crampedNotice : MahjongText.subtitle)
                    .font(.caption)
                    .foregroundStyle(cramped ? CheckTheme.pending : CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            MahjongChip(text: MahjongText.record(avg: store.record?.avgRank, games: store.record?.games ?? 0),
                        tint: CheckTheme.accent)
            HStack(spacing: 4) {
                RubyIcon(size: 13)
                Text("\(store.rubyBalance ?? store.host?.rubyBalance ?? 0)")
                    .font(.callout.weight(.bold).monospacedDigit())
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(CheckTheme.fieldFill))
            MahjongCapsuleButton(title: MahjongText.practice, tint: CheckTheme.working, filled: false, height: 30,
                                 action: onPractice)
                .frame(width: 104)
            MahjongCapsuleButton(title: MahjongText.rules, tint: CheckTheme.secondaryText, filled: false, height: 30,
                                 action: onRules)
                .frame(width: 70)
        }
    }
}

struct MahjongLobbyView: View {
    let store: MahjongStore
    let me: ChessPlayerFace
    let tab: MahjongLobbyTab
    let onSelectTab: (MahjongLobbyTab) -> Void
    let onCreate: () -> Void
    let onPractice: () -> Void
    var clipsOverflowInsteadOfScroll = false

    private var joinables: [MahjongRoom] {
        let mine = store.match?.match?.id
        let invites = store.visibleInvites
        let invited = Set(invites.map(\.id))
        let publicRooms = store.publicRooms.filter { !invited.contains($0.id) && $0.id.uuidString.lowercased() != mine?.lowercased() }
        return invites + publicRooms
    }

    var body: some View {
        let joinables = joinables
        HStack(alignment: .top, spacing: MahjongWindowLayout.columnSpacing) {
            leftColumn
                .frame(width: MahjongWindowLayout.lobbyListWidth, height: MahjongWindowLayout.bodyHeight, alignment: .top)
            VStack(spacing: MahjongWindowLayout.sideSpacing) {
                MahjongRoomCard(store: store, me: me, onCreate: onCreate, onPractice: onPractice)
                    .frame(height: MahjongWindowLayout.tableCardHeight(hasJoinables: !joinables.isEmpty))
                joinRow(joinables)
            }
            .frame(width: MahjongWindowLayout.lobbySideWidth, height: MahjongWindowLayout.bodyHeight, alignment: .top)
        }
    }

    // MARK: 왼쪽 — 사람 · 순위

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            MahjongChoiceRow(options: [(MahjongLobbyTab.users, MahjongText.usersTab), (.ranking, MahjongText.rankTab)],
                             selected: tab, onSelect: onSelectTab)
                .frame(height: MahjongWindowLayout.lobbyTabHeight)
            Group {
                switch tab {
                case .users: usersList
                case .ranking: rankingList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(MahjongWindowLayout.cardPadding)
        .background(MahjongCardBackground())
    }

    @ViewBuilder
    private var usersList: some View {
        let users = store.visibleUsers
        if users.isEmpty {
            Text(MahjongText.emptyUsers)
                .font(.callout)
                .foregroundStyle(CheckTheme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            scrolling {
                VStack(spacing: MahjongWindowLayout.lobbyRowSpacing) {
                    ForEach(users) { user in
                        MahjongUserRow(store: store, user: user, onCreate: onCreate)
                            .frame(height: MahjongWindowLayout.lobbyRowHeight)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var rankingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(MahjongText.rankHeader).font(.caption.weight(.semibold)).foregroundStyle(CheckTheme.secondaryText)
            if let me = store.ranking?.me {
                HStack(spacing: 8) {
                    Text(me.rank.map { "\($0)위" } ?? "—").font(.callout.weight(.bold)).frame(width: 44, alignment: .leading)
                    Text("나").font(.callout.weight(.semibold))
                    Spacer()
                    if me.gamesUntilRanked > 0 {
                        Text("\(me.gamesUntilRanked)\(MahjongText.gamesUntilRanked)")
                            .font(.caption).foregroundStyle(CheckTheme.secondaryText)
                    } else {
                        Text(MahjongText.avgRank(me.avgRank)).font(.caption.weight(.semibold).monospacedDigit())
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(CheckTheme.accent.opacity(0.14)))
            }
            let rows = store.ranking?.rows ?? []
            if rows.isEmpty {
                Text(MahjongText.emptyRanking)
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                scrolling {
                    VStack(spacing: 5) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 8) {
                                Text(MahjongText.rank(row.rank)).font(.callout.weight(.bold).monospacedDigit())
                                    .frame(width: 44, alignment: .leading)
                                CheckAvatarView(name: row.displayName ?? "?", userID: row.userId,
                                                avatarURL: row.avatarUrl.flatMap(URL.init(string:)), size: 26,
                                                characterHint: row.character)
                                Text(row.displayName ?? "?").font(.callout).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(MahjongText.avgRank(row.avgRank)).font(.caption.weight(.semibold).monospacedDigit())
                                Text("\(row.games ?? 0)판").font(.caption).foregroundStyle(CheckTheme.secondaryText)
                                    .frame(width: 40, alignment: .trailing)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 9).fill(CheckTheme.fieldFill))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func scrolling<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if clipsOverflowInsteadOfScroll {
            content().frame(maxHeight: .infinity, alignment: .top).clipped()
        } else {
            ScrollView { content() }.scrollIndicators(.never)
        }
    }

    // MARK: 오른쪽 아래 — 받은 초대 · 공개 방

    @ViewBuilder
    private func joinRow(_ rooms: [MahjongRoom]) -> some View {
        if rooms.isEmpty {
            Text(MahjongText.noJoinables)
                .font(.callout)
                .foregroundStyle(CheckTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: MahjongWindowLayout.joinEmptyHeight)
                .background(MahjongCardBackground())
        } else {
            let invited = Set(store.visibleInvites.map(\.id))
            let cards = HStack(spacing: MahjongWindowLayout.sideSpacing) {
                ForEach(rooms) { room in
                    MahjongJoinCard(store: store, room: room, invited: invited.contains(room.id))
                        .frame(width: MahjongWindowLayout.joinCardWidth, height: MahjongWindowLayout.joinCardHeight)
                }
            }
            Group {
                if clipsOverflowInsteadOfScroll {
                    cards.frame(maxWidth: .infinity, alignment: .leading).clipped()
                } else {
                    ScrollView(.horizontal) { cards }.scrollIndicators(.never)
                }
            }
            .frame(height: MahjongWindowLayout.joinCardHeight)
        }
    }
}

/// 사람 한 줄(56pt): 얼굴 · 이름 · 칩 · [초대]. 방이 없으면 [초대] 가 방 만들기 시트를 먼저 연다.
private struct MahjongUserRow: View {
    let store: MahjongStore
    let user: MahjongLobbyUser
    let onCreate: () -> Void

    private var locked: Bool { user.inMatch == true || user.capable == false || user.focusMode == true }
    private var isMember: Bool {
        let id = user.id.uuidString.lowercased()
        if let members = store.match?.members, members.contains(where: { $0.user?.id?.lowercased() == id }) { return true }
        return store.lobbyRoom?.seats?.contains { $0.user?.id?.lowercased() == id } ?? false
    }
    private var short: Bool {
        guard let balance = store.rubyBalance ?? store.host?.rubyBalance else { return false }
        return balance < store.selectedStake.rawValue
    }

    var body: some View {
        HStack(spacing: 10) {
            CheckAvatarView(name: user.displayName ?? "?", userID: user.id.uuidString.lowercased(),
                            avatarURL: user.avatarUrl.flatMap(URL.init(string:)), size: 36, characterHint: user.character)
            VStack(alignment: .leading, spacing: 3) {
                Text(user.displayName ?? "?").font(.callout.weight(.semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    if user.inMatch == true { MahjongChip(text: MahjongText.inMatchChip, tint: CheckTheme.pending) }
                    if user.capable == false { MahjongChip(text: MahjongText.outdatedChip, tint: CheckTheme.danger) }
                    if user.focusMode == true { MahjongChip(text: MahjongText.focusChip, tint: CheckTheme.aiToken) }
                    if user.isWorking == true, !locked { MahjongChip(text: MahjongText.workingChip, tint: CheckTheme.working) }
                }
            }
            Spacer(minLength: 6)
            if isMember {
                MahjongChip(text: MahjongText.invited, tint: CheckTheme.secondaryText)
            } else {
                MahjongCapsuleButton(title: locked ? "" : MahjongText.invite, systemImage: locked ? MahjongText.lockSymbol : nil,
                                     tint: CheckTheme.accent, height: 28, isEnabled: !locked && !short && !store.isWorking) {
                    if store.match?.match?.matchStatus == .forming || store.lobbyRoom != nil {
                        Task { await store.invite(userID: user.id) }
                    } else {
                        onCreate()
                    }
                }
                .frame(width: 64)
                .accessibilityLabel(locked ? MahjongText.lockedLabel : MahjongText.invite)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(CheckTheme.fieldFill))
        .opacity(short && !isMember ? 0.6 : 1)
    }
}

/// 받은 초대 · 공개 방 카드.
private struct MahjongJoinCard: View {
    let store: MahjongStore
    let room: MahjongRoom
    let invited: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CheckAvatarView(name: room.host?.displayName ?? "?", userID: room.host?.id,
                                avatarURL: room.host?.avatarUrl.flatMap(URL.init(string:)), size: 30,
                                characterHint: room.host?.character)
                VStack(alignment: .leading, spacing: 1) {
                    Text(invited ? MahjongText.inviteFrom(room.host?.displayName ?? "?")
                         : MahjongText.roomOf(room.host?.displayName ?? "?"))
                        .font(.caption.weight(.bold)).lineLimit(1)
                    Text(invited ? MahjongText.invitesTitle : MahjongText.publicRoomsTitle)
                        .font(.caption2).foregroundStyle(CheckTheme.secondaryText)
                }
            }
            HStack(spacing: 5) {
                MahjongChip(text: MahjongText.format(room.formatKind), tint: CheckTheme.accent)
                MahjongChip(text: MahjongText.seats(room.joinedCount), tint: CheckTheme.secondaryText)
            }
            HStack(spacing: 4) {
                Text(MahjongText.stakeLabel).font(.caption)
                RubyIcon(size: 11)
                Text("\(room.stake ?? 0)").font(.caption.weight(.bold))
            }
            .foregroundStyle(CheckTheme.secondaryText)
            if let expires = MahjongClockMath.local(room.expiresAtMs, store: store) {
                MahjongTick(store: store, interval: 1) { now in
                    Text("남은 \(MahjongText.remaining(max(0, Int(expires.timeIntervalSince(now)))))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(CheckTheme.secondaryText)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                MahjongCapsuleButton(title: MahjongText.join, height: 28, isEnabled: !store.isWorking) {
                    Task { await store.join(roomID: room.id) }
                }
                if invited {
                    MahjongCapsuleButton(title: MahjongText.decline, filled: false, height: 28) {
                        Task { await store.decline(roomID: room.id) }
                    }
                }
            }
        }
        .padding(12)
        .background(MahjongCardBackground(tint: invited ? CheckTheme.accent.opacity(0.6) : nil))
    }
}
