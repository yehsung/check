#if os(iOS)
import CheckCore
import SwiftUI

// 아잉 마작 폰 화면(1.0.18 — 맥 0.3.76 과 같은 서버 · 같은 코어 스토어 · 루비 판돈 3/5/10 · 대표 "한 판에 전부" #d_xB6BJcn2nsCq).
// 입구 하나: 판(루비 판 · 연습판 — **가로**, `GamesMahjongTableView`) 또는 로비(세로). 고르기는 `GamesMahjongScreenRule` 한 곳.
// 로비 = 머리(전적 · [혼자 연습] · [규칙]) · 내 방(자리 넷 · [시작] · [나가기]) 또는 [방 만들기] · 받은 초대 · 공개 방 · 사람([초대]) · 순위.
// 상태 · 판정은 전부 코어 `MahjongStore` 다. 이 파일은 그리기와 누름만 한다.
struct GamesMahjongScreen: View {
    let store: GamesStore
    @State private var sheet: GamesMahjongSheet?

    var body: some View {
        let mahjong = store.mahjong
        let screen = GamesMahjongScreenRule.of(mahjong, dismissedMatchID: store.mahjongDismissedMatchID)
        Group {
            switch screen {
            case .table:
                GamesMahjongTableView(store: store, onRules: { sheet = .rules })
            case .lobby:
                lobby
            case .unavailable:
                VStack(spacing: 10) {
                    Image(systemName: GamesMahjongPhoneText.entrySymbol)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(MobileTheme.label2)
                    Text(mahjong.availability == .updateRequired ? GamesMahjongText.updateRequired : GamesMahjongText.unavailable)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .navigationTitle(GamesMahjongText.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.mahjongScreenDidAppear() }
        .onDisappear { store.mahjongScreenDidDisappear() }
        .onChange(of: mahjong.phase) { _, phase in
            if phase == .playing, sheet == .createRoom || sheet == .practice { sheet = nil }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .createRoom: GamesMahjongCreateRoomSheet(store: store)
            case .practice: GamesMahjongPracticeSheet(store: store)
            case .rules: GamesMahjongRulesSheet()
            }
        }
    }

    private var lobby: some View {
        let mahjong = store.mahjong
        let blockedBy = store.mahjongEntryBlock
        return ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                Text(GamesMahjongText.subtitle)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                if let notice = mahjong.notice {
                    InlineNotice(text: notice, kind: .info)
                }
                if let blockedBy, let line = ChessPhoneText.entryBlockHint(playing: blockedBy.text, blocked: .mahjong) {
                    InlineNotice(text: line, kind: .info)
                }
                header
                SectionHeader(GamesMahjongPhoneText.roomTitle)
                InsetGroup { GamesMahjongRoomCard(store: store, blockedBy: blockedBy, onCreate: { sheet = .createRoom },
                                                  onPractice: { sheet = .practice }) }
                let invites = mahjong.visibleInvites
                if !invites.isEmpty {
                    SectionHeader(GamesMahjongText.invitesTitle)
                    ForEach(invites) { room in
                        InsetGroup { GamesMahjongJoinCard(store: store, room: room, invited: true, blockedBy: blockedBy) }
                    }
                }
                let rooms = mahjong.publicRooms.filter { room in !invites.contains(where: { $0.id == room.id }) }
                if !rooms.isEmpty {
                    SectionHeader(GamesMahjongText.publicRoomsTitle)
                    ForEach(rooms) { room in
                        InsetGroup { GamesMahjongJoinCard(store: store, room: room, invited: false, blockedBy: blockedBy) }
                    }
                }
                SectionHeader(GamesMahjongText.usersTab)
                InsetGroup { users }
                GamesMahjongRankingSection(store: store)
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, MobileTheme.rowSpacing)
        }
        .refreshable { mahjong.handleSignal() }
    }

    /// 전적 한 줄 · [혼자 연습] · [규칙].
    private var header: some View {
        let mahjong = store.mahjong
        return InsetGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text(GamesMahjongText.record(avg: mahjong.record?.avgRank, games: mahjong.record?.games ?? 0))
                    .font(.headline)
                    .monospacedDigit()
                HStack(spacing: 10) {
                    AingButton(mahjong.practice != nil ? GamesMahjongText.practiceViewButton : GamesMahjongText.practice,
                               systemImage: "person.fill", kind: .tinted, size: .md, fillsWidth: true) {
                        if mahjong.practice != nil { mahjong.showPractice() } else { sheet = .practice }
                    }
                    AingButton(GamesMahjongText.rules, systemImage: "book", kind: .gray, size: .md, fillsWidth: true) { sheet = .rules }
                }
                Text(GamesMahjongPhoneText.practiceHelp)
                    .font(.caption)
                    .foregroundStyle(MobileTheme.label3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MobileTheme.cardPadding)
        }
    }

    @ViewBuilder
    private var users: some View {
        let mahjong = store.mahjong
        let users = mahjong.visibleUsers
        if users.isEmpty {
            Text(mahjong.users.isEmpty && mahjong.record == nil ? GamesMahjongText.loadingUsers : GamesMahjongText.emptyUsers)
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MobileTheme.cardPadding)
        } else {
            ForEach(Array(users.enumerated()), id: \.element.id) { offset, user in
                GamesMahjongUserRow(store: store, user: user, isLast: offset == users.count - 1, onCreate: { sheet = .createRoom })
            }
        }
    }
}

enum GamesMahjongSheet: String, Identifiable {
    case createRoom, practice, rules
    var id: String { rawValue }
}

// MARK: - 내 방

/// 내 방(앉은 forming 방 — 판 state 가 먼저, 없으면 로비 me.room) 또는 [방 만들기].
struct GamesMahjongRoomCard: View {
    let store: GamesStore
    let blockedBy: GamesBusyGame?
    let onCreate: () -> Void
    let onPractice: () -> Void

    private struct Chair: Identifiable {
        let id: String
        let name: String
        let avatarURL: String?
        let character: String?
        let tag: String
        let joined: Bool
    }

    var body: some View {
        let mahjong = store.mahjong
        let forming = mahjong.match?.match.flatMap { $0.matchStatus == .forming ? $0 : nil }
        if forming != nil || mahjong.lobbyRoom != nil {
            roomContent(forming: forming)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(GamesMahjongPhoneText.roomEmpty)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                AingButton(GamesMahjongText.createTitle, systemImage: "plus", kind: .filled, size: .md, fillsWidth: true, action: onCreate)
                    .disabled(mahjong.isWorking || blockedBy != nil || mahjong.availability != .available)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MobileTheme.cardPadding)
        }
    }

    private func chairs(forming: MahjongStateMatch?) -> [Chair] {
        let mahjong = store.mahjong
        var list: [Chair] = []
        if forming != nil, let members = mahjong.match?.members {
            for (index, member) in members.enumerated() where member.state == "joined" || member.state == "invited" {
                list.append(Chair(id: member.user?.id ?? "member-\(index)", name: member.user?.displayName ?? "?",
                                  avatarURL: member.user?.avatarUrl, character: member.user?.character,
                                  tag: member.isHost == true ? GamesMahjongText.hostTag
                                      : (member.state == "joined" ? GamesMahjongText.joinedTag : GamesMahjongText.invitedTag),
                                  joined: member.state == "joined"))
            }
        } else if let room = mahjong.lobbyRoom {
            for (index, seat) in (room.seats ?? []).enumerated() {
                let isHost = seat.user?.id?.lowercased() != nil && seat.user?.id?.lowercased() == room.host?.id?.lowercased()
                list.append(Chair(id: seat.user?.id ?? "seat-\(index)", name: seat.user?.displayName ?? "?",
                                  avatarURL: seat.user?.avatarUrl, character: seat.user?.character,
                                  tag: isHost ? GamesMahjongText.hostTag : (seat.isJoined ? GamesMahjongText.joinedTag : GamesMahjongText.invitedTag),
                                  joined: seat.isJoined))
            }
        }
        return list.filter(\.joined) + list.filter { !$0.joined }
    }

    private func roomContent(forming: MahjongStateMatch?) -> some View {
        let mahjong = store.mahjong
        let stake = forming?.stake ?? mahjong.lobbyRoom?.stake ?? 0
        let format = forming?.formatKind ?? mahjong.lobbyRoom?.formatKind
        let isPublic = forming?.isPublic ?? mahjong.lobbyRoom?.isPublic ?? false
        let seated = chairs(forming: forming)
        let joined = seated.filter(\.joined).count
        let expiresMs = forming?.roomExpiresMs ?? mahjong.lobbyRoom?.expiresAtMs
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                GamesMahjongChip(text: GamesMahjongText.format(format), tint: MobileTheme.accent)
                GamesMahjongChip(text: isPublic ? GamesMahjongText.publicOn : GamesMahjongText.publicOff, tint: MobileTheme.label2)
                GamesMahjongChip(text: GamesMahjongText.seats(joined), tint: joined == 4 ? MobileTheme.working : MobileTheme.label2)
                Spacer(minLength: 4)
                if let expiresMs {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let left = Int((expiresMs / 1_000 + mahjong.serverClockOffset) - mahjong.clock().timeIntervalSince1970)
                        Text("남은 \(GamesMahjongText.remaining(max(0, left)))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(MobileTheme.label2)
                    }
                }
            }
            HStack(spacing: 4) {
                GamesStakeLine(stake: stake, prefix: GamesMahjongText.stakeLabel)
                Text(" · " + GamesMahjongText.split(stake: stake))
            }
            .font(.footnote)
            .foregroundStyle(MobileTheme.label2)
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { index in
                    if index < seated.count {
                        let chair = seated[index]
                        HStack(spacing: 10) {
                            PersonAvatar(name: chair.name, colorSeed: chair.id, url: chair.avatarURL.flatMap(URL.init(string:)),
                                         userID: chair.id, size: 30, characterHint: chair.character)
                            PersonName(chair.name)
                            Spacer(minLength: 4)
                            Text(chair.tag)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(chair.joined ? MobileTheme.working : MobileTheme.label2)
                        }
                        .frame(height: 40)
                        .opacity(chair.joined ? 1 : 0.6)
                    } else {
                        HStack(spacing: 10) {
                            Circle().strokeBorder(MobileTheme.label3, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .frame(width: 30, height: 30)
                            Text(GamesMahjongText.emptySeat).font(.subheadline).foregroundStyle(MobileTheme.label3)
                            Spacer()
                        }
                        .frame(height: 40)
                    }
                }
            }
            Text(joined == 4 ? (mahjong.isHost ? MahjongNoticeText.fourGathered : GamesMahjongText.waitingHost) : GamesMahjongText.needFour)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(joined == 4 ? MobileTheme.working : MobileTheme.label)
            Text(GamesMahjongText.unseenDrop)
                .font(.caption)
                .foregroundStyle(MobileTheme.label2)
            HStack(spacing: 10) {
                if mahjong.isHost {
                    AingButton(GamesMahjongText.start, kind: .filled, size: .md, fillsWidth: true) {
                        Task { await mahjong.start() }
                    }
                    .disabled(!mahjong.canStart || mahjong.isWorking || blockedBy != nil)
                }
                AingButton(mahjong.practice != nil ? GamesMahjongText.practiceViewButton : GamesMahjongText.practice,
                           kind: .tinted, size: .md, fillsWidth: true) {
                    if mahjong.practice != nil { mahjong.showPractice() } else { onPractice() }
                }
                AingButton(GamesMahjongText.leave, kind: .destructive, size: .md, fillsWidth: true) {
                    Task { await mahjong.leaveRoom() }
                }
                .disabled(mahjong.isWorking)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MobileTheme.cardPadding)
    }
}

// MARK: - 받은 초대 · 공개 방

struct GamesMahjongJoinCard: View {
    let store: GamesStore
    let room: MahjongRoom
    let invited: Bool
    let blockedBy: GamesBusyGame?

    var body: some View {
        let mahjong = store.mahjong
        let name = room.host?.displayName ?? "?"
        let short = (room.stake.map { need in (store.rubyBalance ?? mahjong.rubyBalance).map { $0 < need } ?? false }) ?? false
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: MobileTheme.space3) {
                PersonAvatar(name: name, colorSeed: room.host?.id ?? room.id.uuidString,
                             url: room.host?.avatarUrl.flatMap(URL.init(string:)), userID: room.host?.id ?? room.id.uuidString,
                             size: 40, characterHint: room.host?.character)
                VStack(alignment: .leading, spacing: 2) {
                    PersonName(invited ? GamesMahjongText.inviteFrom(name) : GamesMahjongText.roomOf(name))
                    HStack(spacing: 6) {
                        GamesMahjongChip(text: GamesMahjongText.format(room.formatKind), tint: MobileTheme.accent)
                        GamesMahjongChip(text: GamesMahjongText.seats(room.joinedCount), tint: MobileTheme.label2)
                        if let stake = room.stake {
                            GamesStakeLine(stake: stake, prefix: GamesMahjongText.stakeLabel)
                                .font(.caption)
                                .foregroundStyle(MobileTheme.label2)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                if invited {
                    AingButton(GamesMahjongText.decline, kind: .gray, size: .md, fillsWidth: true) {
                        Task { await mahjong.decline(roomID: room.id) }
                    }
                    .disabled(mahjong.isWorking)
                }
                AingButton(GamesMahjongText.join, kind: .filled, size: .md, fillsWidth: true) {
                    Task { await mahjong.join(roomID: room.id) }
                }
                .disabled(mahjong.isWorking || blockedBy != nil || short || store.hasLiveMahjongSeat)
            }
            if short {
                Text(CheckCoreShared.shortfallNotice(need: room.stake, have: store.rubyBalance))
                    .font(.caption)
                    .foregroundStyle(MobileTheme.label2)
            }
        }
        .padding(MobileTheme.cardPadding)
    }
}

// MARK: - 사람

struct GamesMahjongUserRow: View {
    let store: GamesStore
    let user: MahjongLobbyUser
    let isLast: Bool
    let onCreate: () -> Void

    var body: some View {
        let mahjong = store.mahjong
        let locked = user.inMatch == true || user.capable == false || user.focusMode == true
        let id = user.id.uuidString.lowercased()
        let isMember = (mahjong.match?.members?.contains { $0.user?.id?.lowercased() == id } ?? false)
            || (mahjong.lobbyRoom?.seats?.contains { $0.user?.id?.lowercased() == id } ?? false)
        let short = (store.rubyBalance ?? mahjong.rubyBalance).map { $0 < mahjong.selectedStake.rawValue } ?? false
        let inRoom = mahjong.match?.match?.matchStatus == .forming || mahjong.lobbyRoom != nil
        GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding + 36 + MobileTheme.space3), minHeight: 56) {
            PersonAvatar(name: user.displayName ?? "?", colorSeed: id, status: user.isWorking == true ? .working : nil,
                         url: user.avatarUrl.flatMap(URL.init(string:)), userID: id, size: 36, characterHint: user.character)
            VStack(alignment: .leading, spacing: 2) {
                PersonName(user.displayName ?? "?")
                HStack(spacing: 4) {
                    if user.inMatch == true { GamesMahjongChip(text: GamesMahjongText.inMatchChip, tint: MobileTheme.pending) }
                    if user.capable == false { GamesMahjongChip(text: GamesMahjongText.outdatedChip, tint: MobileTheme.danger) }
                    if user.focusMode == true { GamesMahjongChip(text: GamesMahjongText.focusChip, tint: MobileTheme.label2) }
                    if user.isWorking == true, !locked { GamesMahjongChip(text: GamesMahjongText.workingChip, tint: MobileTheme.working) }
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if isMember {
                GamesMahjongChip(text: GamesMahjongText.invited, tint: MobileTheme.label2)
            } else {
                AingButton(locked ? "" : GamesMahjongText.invite, systemImage: locked ? GamesMahjongText.lockSymbol : nil,
                           kind: locked ? .gray : .tinted, size: .sm) {
                    if inRoom {
                        Task { await mahjong.invite(userID: user.id) }
                    } else {
                        onCreate()
                    }
                }
                .disabled(locked || short || mahjong.isWorking || (inRoom && !mahjong.isHost) || store.mahjongEntryBlock != nil)
                .fixedSize()
                .accessibilityLabel(Text(locked ? GamesMahjongText.lockedLabel : GamesMahjongText.invite))
            }
        }
    }
}

/// 작은 칩(글자 + 색).
struct GamesMahjongChip: View {
    let text: String
    var tint: Color = MobileTheme.label2

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
            .fixedSize()
    }
}

// MARK: - 순위

struct GamesMahjongRankingSection: View {
    let store: GamesStore

    var body: some View {
        let mahjong = store.mahjong
        VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
            SectionHeader(GamesMahjongPhoneText.rankingTitle, trailing: .text(GamesMahjongText.rankHeader))
            InsetGroup {
                if let me = mahjong.ranking?.me, me.rank == nil, me.gamesUntilRanked > 0 {
                    Text("\(me.gamesUntilRanked)\(GamesMahjongText.gamesUntilRanked)")
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, MobileTheme.cardPadding)
                        .padding(.top, 10)
                }
                if let rows = mahjong.ranking?.rows, !rows.isEmpty {
                    let shown = Array(rows.prefix(20))
                    ForEach(Array(shown.enumerated()), id: \.offset) { offset, row in
                        GroupRow(divider: offset == shown.count - 1 ? .none : .inset(MobileTheme.cardPadding), minHeight: 48) {
                            Text(GamesMahjongText.rank(row.rank))
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .frame(width: 36, alignment: .leading)
                            PersonAvatar(name: row.displayName ?? "?", colorSeed: row.userId ?? "\(offset)",
                                         url: row.avatarUrl.flatMap(URL.init(string:)), userID: row.userId ?? "\(offset)", size: 28,
                                         characterHint: row.character)
                            PersonName(row.displayName ?? "?")
                            Spacer(minLength: 8)
                            Text(GamesMahjongText.avgRank(row.avgRank))
                                .font(.footnote.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(MobileTheme.label2)
                        }
                    }
                } else {
                    Text(mahjong.rankingUnavailable ? GamesMahjongText.unavailable
                         : (mahjong.ranking == nil ? GamesMahjongText.loadingUsers : GamesMahjongText.emptyRanking))
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(MobileTheme.cardPadding)
                }
            }
        }
        .task { await mahjong.refreshRanking() }
    }
}

// MARK: - 시트

struct GamesMahjongCreateRoomSheet: View {
    let store: GamesStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let mahjong = store.mahjong
        VStack(spacing: 0) {
            SheetHeader(GamesMahjongText.createTitle, subtitle: GamesMahjongText.title, onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.space4) {
                    choice(GamesMahjongText.stakeLabel) {
                        Picker(GamesMahjongText.stakeLabel, selection: Binding(get: { mahjong.selectedStake }, set: { mahjong.selectedStake = $0 })) {
                            ForEach(MahjongStake.allCases, id: \.rawValue) { stake in Text("루비 \(stake.rawValue)").tag(stake) }
                        }
                        .pickerStyle(.segmented)
                    }
                    choice(GamesMahjongText.formatLabel) {
                        Picker(GamesMahjongText.formatLabel, selection: Binding(get: { mahjong.selectedFormat }, set: { mahjong.selectedFormat = $0 })) {
                            Text(GamesMahjongText.format(.tonpuu)).tag(MahjongFormat.tonpuu)
                            Text(GamesMahjongText.format(.hanchan)).tag(MahjongFormat.hanchan)
                        }
                        .pickerStyle(.segmented)
                        Text(GamesMahjongText.formatDetail(mahjong.selectedFormat))
                            .font(.caption)
                            .foregroundStyle(MobileTheme.label2)
                    }
                    choice(GamesMahjongText.publicLabel) {
                        Picker(GamesMahjongText.publicLabel, selection: Binding(get: { mahjong.selectedPublic }, set: { mahjong.selectedPublic = $0 })) {
                            Text(GamesMahjongText.publicOff).tag(false)
                            Text(GamesMahjongText.publicOn).tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    Text(GamesMahjongText.split(stake: mahjong.selectedStake.rawValue) + " · " + GamesMahjongText.createHint)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(MobileTheme.sideMargin)
            }
            AingButton(GamesMahjongText.createButton, kind: .filled, size: .lg, fillsWidth: true) {
                dismiss()
                Task { await mahjong.createRoom() }
            }
            .disabled(mahjong.isWorking || store.mahjongEntryBlock != nil)
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.bottom, MobileTheme.space4)
        }
        .presentationDetents([.medium, .large])
    }

    private func choice<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(MobileTheme.label2)
            content()
        }
    }
}

struct GamesMahjongPracticeSheet: View {
    let store: GamesStore
    @Environment(\.dismiss) private var dismiss
    @State private var format: MahjongFormat = .tonpuu

    var body: some View {
        let mahjong = store.mahjong
        VStack(spacing: 0) {
            SheetHeader(GamesMahjongText.practiceTitle, subtitle: GamesMahjongText.title, onClose: { dismiss() })
            VStack(alignment: .leading, spacing: MobileTheme.space4) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(GamesMahjongText.formatLabel).font(.footnote.weight(.semibold)).foregroundStyle(MobileTheme.label2)
                    Picker(GamesMahjongText.formatLabel, selection: $format) {
                        Text(GamesMahjongText.format(.tonpuu)).tag(MahjongFormat.tonpuu)
                        Text(GamesMahjongText.format(.hanchan)).tag(MahjongFormat.hanchan)
                    }
                    .pickerStyle(.segmented)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(GamesMahjongText.practiceTimeLabel).font(.footnote.weight(.semibold)).foregroundStyle(MobileTheme.label2)
                    Picker(GamesMahjongText.practiceTimeLabel, selection: Binding(get: { mahjong.practiceTimed }, set: { mahjong.practiceTimed = $0 })) {
                        Text(GamesMahjongText.practiceTimedOff).tag(false)
                        Text(GamesMahjongText.practiceTimedOn).tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(GamesMahjongText.practiceSeatNote)
                    Text(GamesMahjongText.practiceNoRuby)
                }
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
                Spacer(minLength: 0)
            }
            .padding(MobileTheme.sideMargin)
            AingButton(GamesMahjongText.practiceStart, kind: .filled, size: .lg, fillsWidth: true) {
                dismiss()
                mahjong.startPractice(format: format, timed: mahjong.practiceTimed)
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.bottom, MobileTheme.space4)
        }
        .presentationDetents([.medium])
    }
}

struct GamesMahjongRulesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(GamesMahjongText.rules, subtitle: GamesMahjongText.title, onClose: { dismiss() })
            Picker(GamesMahjongText.rules, selection: $tab) {
                Text(GamesMahjongText.rules).tag(0)
                Text(GamesMahjongText.yaku).tag(1)
                Text(GamesMahjongText.scoreTable).tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.bottom, MobileTheme.space2)
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.space3) {
                    switch tab {
                    case 0: rules
                    case 1: yaku
                    default: scores
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(MobileTheme.sideMargin)
            }
        }
        .presentationDetents([.large])
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: MobileTheme.space3) {
            ForEach(GamesMahjongRulesText.rules, id: \.title) { line in
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.title).font(.subheadline.weight(.bold))
                    Text(line.detail).font(.footnote).foregroundStyle(MobileTheme.label2).fixedSize(horizontal: false, vertical: true)
                    if !line.example.isEmpty, let tiles = MahjongTiles.parse(line.example) {
                        HStack(spacing: 0) {
                            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                                GamesMahjongTileView(face: MahjongTileFace(tile), size: .discard, cornerLabels: false,
                                                     display: CGSize(width: 22, height: 29))
                            }
                        }
                        .accessibilityHidden(true)
                    }
                }
            }
            Text(GamesMahjongRulesText.footer).font(.caption).foregroundStyle(MobileTheme.label3)
        }
    }

    private var yaku: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(GamesMahjongRulesText.yakuTable, id: \.yaku) { row in
                HStack {
                    Text(row.yaku.koreanName).font(.subheadline)
                    Spacer()
                    Text(row.open.map { "\(row.closed)판 · 울면 \($0)판" } ?? "\(row.closed)판 · 멘젠만")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(MobileTheme.label2)
                }
            }
            Text(GamesMahjongText.yaku + " — 역만").font(.subheadline.weight(.bold)).padding(.top, 8)
            Text(GamesMahjongRulesText.yakumanList.map(\.koreanName).joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scores: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("부 \\ 판").frame(width: 56, alignment: .leading)
                ForEach(GamesMahjongRulesText.hanColumns, id: \.self) { han in
                    Text("\(han)판").frame(maxWidth: .infinity)
                }
            }
            .font(.caption.weight(.bold))
            ForEach(GamesMahjongRulesText.fuRows, id: \.self) { fu in
                HStack {
                    Text("\(fu)부").frame(width: 56, alignment: .leading)
                    ForEach(GamesMahjongRulesText.hanColumns, id: \.self) { han in
                        Text(GamesMahjongScoreCell.text(han: han, fu: fu))
                            .frame(maxWidth: .infinity)
                    }
                }
                .font(.caption.monospacedDigit())
            }
            Text(GamesMahjongScoreCell.caption).font(.caption2).foregroundStyle(MobileTheme.label3).padding(.top, 4)
        }
    }
}
#endif
