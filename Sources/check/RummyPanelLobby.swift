import SwiftUI
import CheckCore

// MARK: - 아잉 큐브 로비·방 (설계서 §5)
//
// 두 열 [사람·순위 탭 440 | 오른쪽 740]. 로비와 방은 **같은 화면**이다 — 오른쪽 위 카드만 '방 만들기' ↔ '내 방' 으로 갈린다.
//   · 왼쪽 사람 탭 = 위 '공개 방'(빈자리 있는 방 [참가]) + 아래 사람 목록(상태 칩 · 내가 방장일 때 [초대]).
//   · 오른쪽 = 방 카드(판돈 칩 · 공개 여부 · 자리 4칸 · 남은 시간 · [시작] · [나가기]) 또는 방 만들기(판돈 3·5·10 · 공개 토글 ·
//     [방 만들기]) / 받은 초대 [참가]·[거절] / 내 전적.
// 버튼을 끄는 판단은 "서버가 어차피 거절할 것"만 본다(구버전·게임 중·집중·가득 참). 나머지 거절은 서버 문구(`notice`)가 말한다.

struct RummyLobbyView: View {
    let store: RummyStore
    let scene: RummyScene
    let tab: RummyLobbyTab
    let onSelectTab: (RummyLobbyTab) -> Void
    let onLeaveRoom: () -> Void
    let clipsOverflowInsteadOfScroll: Bool

    var body: some View {
        HStack(alignment: .top, spacing: RummyWindowLayout.columnSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                RummyLobbyTabs(selected: tab, onSelect: onSelectTab)
                    .frame(height: RummyWindowLayout.lobbyTabHeight)
                switch tab {
                case .users:
                    RummyPeopleColumn(store: store, scene: scene, clips: clipsOverflowInsteadOfScroll)
                case .ranking:
                    RummyRankList(scene: scene, clips: clipsOverflowInsteadOfScroll)
                }
            }
            .frame(width: RummyWindowLayout.lobbyListWidth, height: RummyWindowLayout.bodyHeight, alignment: .top)
            .clipped()
            VStack(spacing: RummyWindowLayout.sideSpacing) {
                Group {
                    if let room = scene.myRoom {
                        RummyRoomCard(store: store, scene: scene, room: room, onLeave: onLeaveRoom)
                    } else {
                        RummyCreateCard(store: store, scene: scene)
                    }
                }
                .frame(height: RummyWindowLayout.roomCardHeight)
                RummyInvitesCard(store: store, scene: scene, clips: clipsOverflowInsteadOfScroll)
                    .frame(height: RummyWindowLayout.invitesHeight)
                RummyRecordCard(scene: scene)
                    .frame(height: RummyWindowLayout.recordHeight)
            }
            .frame(width: RummyWindowLayout.lobbySideWidth, height: RummyWindowLayout.bodyHeight, alignment: .top)
        }
    }
}

// MARK: - 탭

private struct RummyLobbyTabs: View {
    let selected: RummyLobbyTab
    let onSelect: (RummyLobbyTab) -> Void

    var body: some View {
        HStack(spacing: 6) {
            tab(.users, title: RummyText.usersTab, icon: "person.2.fill")
            tab(.ranking, title: RummyText.rankTab, icon: "trophy.fill")
            Spacer(minLength: 4)
        }
    }

    private func tab(_ value: RummyLobbyTab, title: String, icon: String) -> some View {
        let isOn = selected == value
        return Button { onSelect(value) } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(isOn ? CheckTheme.accent : CheckTheme.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: RummyWindowLayout.lobbyTabHeight)
                .background(Capsule().fill(isOn ? CheckTheme.accent.opacity(0.20) : Color.white.opacity(0.04)))
                .overlay(Capsule().stroke(isOn ? CheckTheme.accent.opacity(0.55) : CheckTheme.border, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - 사람 탭(공개 방 + 사람)

private struct RummyPeopleColumn: View {
    let store: RummyStore
    let scene: RummyScene
    let clips: Bool

    private var publicRooms: [RummyRoom] { scene.lobby?.publicRooms ?? [] }
    private var users: [RummyLobbyUser] { scene.lobby?.users ?? [] }
    private var inRoom: Bool { scene.myRoom != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 공개 방 — 최대 3줄만 보인다(넘치면 사람 목록이 눌리지 않게 잘린다).
            VStack(alignment: .leading, spacing: RummyWindowLayout.lobbyRowSpacing) {
                Label(RummyText.publicRoomsTitle, systemImage: "door.left.hand.open")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckTheme.secondaryText)
                if publicRooms.isEmpty {
                    Text(RummyText.noPublicRooms)
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                } else {
                    ForEach(publicRooms.prefix(3)) { room in
                        RummyPublicRoomRow(room: room, isEnabled: canJoin(room), onJoin: { store.join(room.id) })
                            .frame(height: RummyWindowLayout.lobbyRowHeight)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tetrisDuelCard(padding: 12)

            VStack(alignment: .leading, spacing: 8) {
                Text(RummyText.peopleCaption(inRoom: inRoom, amHost: scene.amHost))
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                if users.isEmpty {
                    Text(emptyText)
                        .font(.callout)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    RummyScrollBox(clips: clips) {
                        VStack(spacing: RummyWindowLayout.lobbyRowSpacing) {
                            // 서버 정렬 그대로(근무 중 → 가능 → 이름). 여기서 다시 줄 세우지 않는다.
                            ForEach(users) { user in
                                RummyPersonRow(user: user, action: action(for: user),
                                               onInvite: { store.invite(user.id) })
                                    .frame(height: RummyWindowLayout.lobbyRowHeight)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tetrisDuelCard()
        }
    }

    private var emptyText: String {
        switch scene.availability {
        case .updateRequired: return scene.notice ?? RummyText.updateRequired
        case .serverMissing: return RummyText.serverMissing
        case .available: return scene.lobby == nil ? RummyText.loadingUsers : RummyText.emptyUsers
        }
    }

    /// [참가] — 이미 방에 있거나 가득 찬 방만 끈다.
    private func canJoin(_ room: RummyRoom) -> Bool {
        guard !inRoom, !scene.isWorking, scene.availability == .available else { return false }
        let joined = room.seats?.filter { $0.state == .joined }.count ?? 0
        return joined < (room.maxSeats ?? 4)
    }

    /// 사람 행 오른쪽: 방장이면 [초대](이미 방에 있으면 '초대함'·'참가함'), 아니면 아무것도.
    private func action(for user: RummyLobbyUser) -> RummyPersonRow.Action {
        guard scene.amHost, let room = scene.myRoom else { return .hidden }
        if let seat = room.seats?.first(where: { $0.userId == user.id }) {
            switch seat.state {
            case .joined: return .tag(RummyText.joined)
            case .invited: return .tag(RummyText.invited)
            default: break
            }
        }
        let canInvite = user.capable != false && user.inMatch != true && user.focusMode != true && !scene.isWorking
        return .invite(enabled: canInvite)
    }
}

private struct RummyPublicRoomRow: View {
    let room: RummyRoom
    let isEnabled: Bool
    let onJoin: () -> Void

    var body: some View {
        let joined = room.seats?.filter { $0.state == .joined }.count ?? 0
        HStack(spacing: 12) {
            CheckAvatarView(name: room.host?.displayName ?? "?", userID: room.host?.id.uuidString.lowercased(),
                            avatarURL: room.host?.avatarUrl.flatMap(URL.init(string:)), size: 32,
                            characterHint: room.host?.character)
            VStack(alignment: .leading, spacing: 3) {
                Text(RummyText.roomOf(room.host?.displayName ?? "?"))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    RummyChip(text: RummyText.stake(room.stake), tint: CheckTheme.pending)
                    RummyChip(text: RummyText.seats(joined, max: room.maxSeats ?? 4))
                }
            }
            Spacer(minLength: 8)
            TetrisDuelActionButton(title: RummyText.join, height: 28, isEnabled: isEnabled, action: onJoin)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}

struct RummyPersonRow: View {
    enum Action: Equatable {
        case hidden
        case invite(enabled: Bool)
        case tag(String)
    }

    let user: RummyLobbyUser
    let action: Action
    let onInvite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CheckAvatarView(name: user.displayName ?? "?", userID: user.id.uuidString.lowercased(),
                            avatarURL: user.avatarUrl.flatMap(URL.init(string:)), size: 32,
                            characterHint: user.character)
            VStack(alignment: .leading, spacing: 3) {
                Text(user.displayName ?? "?")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                RummyChip(text: status.text, tint: status.tint)
            }
            Spacer(minLength: 8)
            switch action {
            case .hidden:
                EmptyView()
            case .invite(let enabled):
                TetrisDuelActionButton(title: RummyText.invite, icon: "paperplane.fill", height: 28,
                                       isEnabled: enabled, action: onInvite)
            case .tag(let text):
                RummyChip(text: text, tint: CheckTheme.working)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }

    /// 상태 칩: 구버전 > 게임 중 > 집중 > 근무 중 > 쉬는 중.
    private var status: (text: String, tint: Color) {
        if user.capable == false { return ("업데이트 필요", CheckTheme.pending) }
        if user.inMatch == true { return ("게임 중", CheckTheme.accent) }
        if user.focusMode == true { return ("집중", CheckTheme.aiToken) }
        if user.isWorking == true { return ("근무 중", CheckTheme.working) }
        return ("쉬는 중", CheckTheme.secondaryText)
    }
}

// MARK: - 순위 탭

private struct RummyRankList: View {
    let scene: RummyScene
    let clips: Bool

    var body: some View {
        let rows = scene.ranking?.rows ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(RummyText.rankHeader).font(.caption).foregroundStyle(CheckTheme.secondaryText)
                Spacer()
                if let me = scene.ranking?.me {
                    Text("내 순위 \(RummyText.rank(me.rank)) · \(RummyText.record(games: me.games, wins: me.wins))")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
            }
            if rows.isEmpty {
                Text(RummyText.emptyRanking)
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                RummyScrollBox(clips: clips) {
                    VStack(spacing: RummyWindowLayout.lobbyRowSpacing) {
                        // 순위·배열 순서 모두 서버 것(재정렬 금지).
                        ForEach(rows) { row in
                            HStack(spacing: 12) {
                                Text(row.rank.map(String.init) ?? "—")
                                    .font(.callout.weight(.heavy))
                                    .monospacedDigit()
                                    .frame(width: 28)
                                CheckAvatarView(name: row.displayName ?? "?", userID: row.id.uuidString.lowercased(),
                                                avatarURL: row.avatarUrl.flatMap(URL.init(string:)), size: 30,
                                                characterHint: row.character)
                                Text(row.displayName ?? "?").font(.callout.weight(.semibold)).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(RummyText.record(games: row.games, wins: row.wins))
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(CheckTheme.secondaryText)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.04)))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tetrisDuelCard()
    }
}

// MARK: - 방 만들기

private struct RummyCreateCard: View {
    let store: RummyStore
    let scene: RummyScene

    private var stakes: [Int] { scene.lobby?.stakes ?? [3, 5, 10] }
    private var selected: Int { store.selectedStake }
    private var isPublic: Bool { store.createPublic }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(RummyText.createTitle, systemImage: "plus.square.on.square")
                .font(.headline)
            HStack(spacing: 10) {
                Text(RummyText.stakeLabel).font(.callout.weight(.semibold)).frame(width: 64, alignment: .leading)
                ForEach(stakes, id: \.self) { stake in
                    let isOn = stake == selected
                    Button { store.selectedStake = stake } label: {
                        HStack(spacing: 5) {
                            RubyIcon(size: 13)
                            Text("\(stake)").font(.callout.weight(.heavy)).monospacedDigit()
                        }
                        .foregroundStyle(isOn ? Color.white : CheckTheme.primaryText)
                        .frame(width: 84, height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isOn ? CheckTheme.accent : Color.white.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isOn ? Color.clear : CheckTheme.border, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Text(RummyText.publicLabel).font(.callout.weight(.semibold)).frame(width: 64, alignment: .leading)
                Button { store.createPublic.toggle() } label: {
                    HStack(spacing: 8) {
                        ZStack(alignment: isPublic ? .trailing : .leading) {
                            Capsule().fill(isPublic ? CheckTheme.working : Color.white.opacity(0.18))
                                .frame(width: 38, height: 22)
                            Circle().fill(Color.white).frame(width: 18, height: 18).padding(2)
                        }
                        Text(isPublic ? RummyText.publicOn : RummyText.publicOff)
                            .font(.callout)
                            .foregroundStyle(CheckTheme.primaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            Text(RummyText.createHint)
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
            if let notice = scene.notice {
                RummyNoticeLine(text: notice)
            }
            Spacer(minLength: 0)
            TetrisDuelActionButton(title: RummyText.createButton, icon: "plus", height: 38, fullWidth: true,
                                   isEnabled: !scene.isWorking && scene.availability == .available,
                                   action: { store.createRoom() })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tetrisDuelCard()
    }
}

// MARK: - 내 방

private struct RummyRoomCard: View {
    let store: RummyStore
    let scene: RummyScene
    let room: RummyRoom
    let onLeave: () -> Void

    private var maxSeats: Int { room.maxSeats ?? 4 }
    private var joinedCount: Int { room.seats?.filter { $0.state == .joined }.count ?? 0 }

    /// 자리 4칸: 참가자(seat_no 순, 방장 먼저) → 초대 중 → 빈자리.
    private var slots: [RummyRoomSeat?] {
        let seats = room.seats ?? []
        let joined = seats.filter { $0.state == .joined }.sorted { ($0.seatNo ?? 9) < ($1.seatNo ?? 9) }
        let invited = seats.filter { $0.state == .invited }
        var result: [RummyRoomSeat?] = Array((joined + invited).prefix(maxSeats))
        while result.count < maxSeats { result.append(nil) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(RummyText.myRoomTitle, systemImage: "square.grid.2x2.fill").font(.headline)
                RummyChip(text: RummyText.stake(room.stake), tint: CheckTheme.pending)
                RummyChip(text: room.isPublic == true ? RummyText.publicOn : RummyText.publicOff,
                          tint: room.isPublic == true ? CheckTheme.working : CheckTheme.secondaryText)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "hourglass")
                    RummyCountdownLeaf(remaining: scene.roomRemaining(store), fixedNow: scene.fixedNow,
                                       label: RummyText.clock, urgentBelow: 60)
                }
                .font(.callout.weight(.semibold))
            }
            HStack(spacing: 10) {
                ForEach(Array(slots.enumerated()), id: \.offset) { _, seat in
                    RummyRoomSlot(seat: seat, isHost: seat?.userId == room.host?.id)
                        .frame(maxWidth: .infinity)
                        .frame(height: RummyWindowLayout.roomSeatHeight)
                }
            }
            RummyNoticeLine(text: scene.notice ?? (scene.amHost ? RummyText.startHintHost : RummyText.startHintGuest))
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                TetrisDuelActionButton(title: RummyText.leave, icon: "rectangle.portrait.and.arrow.right",
                                       tint: CheckTheme.danger, style: .outline, height: 38, fullWidth: true,
                                       isEnabled: !scene.isWorking, action: onLeave)
                if scene.amHost {
                    TetrisDuelActionButton(title: RummyText.start, icon: "play.fill", tint: CheckTheme.working,
                                           height: 38, fullWidth: true,
                                           isEnabled: joinedCount >= 2 && !scene.isWorking,
                                           action: { store.startGame() })
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tetrisDuelCard()
    }
}

private struct RummyRoomSlot: View {
    let seat: RummyRoomSeat?
    let isHost: Bool

    var body: some View {
        VStack(spacing: 6) {
            if let seat {
                CheckAvatarView(name: seat.displayName ?? "?", userID: seat.userId.uuidString.lowercased(),
                                avatarURL: seat.avatarUrl.flatMap(URL.init(string:)), size: 40,
                                characterHint: seat.character)
                    .opacity(seat.state == .invited ? 0.5 : 1)
                Text(seat.displayName ?? "?").font(.callout.weight(.semibold)).lineLimit(1)
                if isHost {
                    RummyChip(text: RummyText.hostTag, tint: CheckTheme.pending)
                } else if seat.state == .invited {
                    RummyChip(text: RummyText.invitedTag)
                } else {
                    RummyChip(text: RummyText.joinedTag, tint: CheckTheme.working)
                }
            } else {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(CheckTheme.border)
                    .frame(width: 40, height: 40)
                Text(RummyText.emptySeat).font(.callout).foregroundStyle(CheckTheme.secondaryText)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(seat?.state == .joined ? CheckTheme.working.opacity(0.45) : CheckTheme.border, lineWidth: 1))
    }
}

// MARK: - 받은 초대 · 내 전적

private struct RummyInvitesCard: View {
    let store: RummyStore
    let scene: RummyScene
    let clips: Bool

    var body: some View {
        let invites = scene.lobby?.invites ?? []
        VStack(alignment: .leading, spacing: 8) {
            Label(RummyText.invitesTitle, systemImage: "envelope.fill").font(.headline)
            if invites.isEmpty {
                Text(RummyText.noInvites)
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                RummyScrollBox(clips: clips) {
                    VStack(spacing: 8) {
                        ForEach(invites) { room in
                            RummyInviteRow(room: room, canJoin: scene.myRoom == nil && !scene.isWorking,
                                           onJoin: { store.join(room.id) }, onDecline: { store.decline(room.id) })
                                .frame(height: 56)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tetrisDuelCard()
    }
}

private struct RummyInviteRow: View {
    let room: RummyRoom
    let canJoin: Bool
    let onJoin: () -> Void
    let onDecline: () -> Void

    var body: some View {
        let joined = room.seats?.filter { $0.state == .joined }.count ?? 0
        HStack(spacing: 12) {
            CheckAvatarView(name: room.host?.displayName ?? "?", userID: room.host?.id.uuidString.lowercased(),
                            avatarURL: room.host?.avatarUrl.flatMap(URL.init(string:)), size: 34,
                            characterHint: room.host?.character)
            VStack(alignment: .leading, spacing: 3) {
                Text(RummyText.inviteFrom(room.host?.displayName ?? "?"))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    RummyChip(text: RummyText.stake(room.stake), tint: CheckTheme.pending)
                    RummyChip(text: RummyText.seats(joined, max: room.maxSeats ?? 4))
                }
            }
            Spacer(minLength: 8)
            TetrisDuelActionButton(title: RummyText.decline, style: .outline, height: 30, action: onDecline)
            TetrisDuelActionButton(title: RummyText.join, tint: CheckTheme.working, height: 30, isEnabled: canJoin,
                                   action: onJoin)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CheckTheme.accent.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.accent.opacity(0.4),
                                                                              lineWidth: 1))
    }
}

private struct RummyRecordCard: View {
    let scene: RummyScene

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill").font(.title3).foregroundStyle(CheckTheme.pending)
            VStack(alignment: .leading, spacing: 2) {
                Text(RummyText.recordTitle).font(.caption).foregroundStyle(CheckTheme.secondaryText)
                Text(RummyText.record(games: scene.lobby?.me?.games, wins: scene.lobby?.me?.wins))
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(.horizontal, RummyWindowLayout.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CheckTheme.panel.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}

struct RummyNoticeLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
            Text(text).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(CheckTheme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
