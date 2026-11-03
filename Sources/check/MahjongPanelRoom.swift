import SwiftUI
import CheckCore

// MARK: - 아잉 마작 방 · 방 만들기 · 연습 시작 · 방 띠 (SPEC §5.8 · 카드 ③)
//
// 방 = 큐브 탁자(`RummyTableStage`, internal — 그대로)에 의자 넷(앉은 순서, 바람은 아직 없음).
// **[시작]은 방장이고 4명일 때만**(카드 ③ — 스토어 `canStart` 하나), "4명이 모여야 시작해요" · "앱을 끈 사람은 시작할 때 빠져요"(D34).
// 방에서도 [혼자 연습] — 연습 탁자 위에 방 띠(`store.roomBand`)가 서고, 넷째가 앉으면 띠가 "4명이 모였어요 [시작]"(방장)으로 바뀐다.

struct MahjongRoomCard: View {
    let store: MahjongStore
    let me: ChessPlayerFace
    let onCreate: () -> Void
    let onPractice: () -> Void

    /// 앉은 방(forming) — 판 state 가 먼저, 없으면 로비 me.room.
    private var formingMatch: MahjongStateMatch? {
        guard let match = store.match?.match, match.matchStatus == .forming else { return nil }
        return match
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if formingMatch != nil || store.lobbyRoom != nil {
                roomContent
            } else {
                emptyContent
            }
        }
        .padding(MahjongWindowLayout.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MahjongCardBackground())
    }

    // MARK: 방이 있을 때

    private var chairs: [RummyTableChair] {
        let myID = store.host?.session?.userID.lowercased()
        var list: [RummyTableChair] = []
        if let members = store.match?.members, formingMatch != nil {
            for member in members {
                let id = member.user?.id?.lowercased()
                list.append(RummyTableChair(
                    kind: .person, userID: id.flatMap(UUID.init(uuidString:)), name: member.user?.displayName ?? "?",
                    avatarURL: member.user?.avatarUrl, character: member.user?.character,
                    tag: member.isHost == true ? MahjongText.hostTag
                        : (member.state == "joined" ? MahjongText.joinedTag : MahjongText.invitedTag),
                    isHost: member.isHost == true, isMe: id != nil && id == myID, dimmed: member.state != "joined"))
            }
        } else if let room = store.lobbyRoom {
            for seat in room.seats ?? [] {
                let id = seat.user?.id?.lowercased()
                let isHost = id != nil && id == room.host?.id?.lowercased()
                list.append(RummyTableChair(
                    kind: .person, userID: id.flatMap(UUID.init(uuidString:)), name: seat.user?.displayName ?? "?",
                    avatarURL: seat.user?.avatarUrl, character: seat.user?.character,
                    tag: isHost ? MahjongText.hostTag : (seat.isJoined ? MahjongText.joinedTag : MahjongText.invitedTag),
                    isHost: isHost, isMe: id != nil && id == myID, dimmed: !seat.isJoined))
            }
        }
        // 앉은 사람 먼저(앉은 순서), 초대 중은 뒤.
        let joined = list.filter { !$0.dimmed } + list.filter(\.dimmed)
        let padded = Array(joined.prefix(4))
            + Array(repeating: RummyTableChair(kind: .empty, name: MahjongText.emptySeat), count: max(0, 4 - joined.count))
        return padded
    }

    private var stake: Int? { formingMatch?.stake ?? store.lobbyRoom?.stake }
    private var format: MahjongFormat? {
        formingMatch?.formatKind ?? store.lobbyRoom?.formatKind
    }
    private var isPublic: Bool { formingMatch?.isPublic ?? store.lobbyRoom?.isPublic ?? false }
    private var joinedCount: Int {
        if formingMatch != nil { return store.match?.members?.filter { $0.state == "joined" }.count ?? 0 }
        return store.lobbyRoom?.joinedCount ?? 0
    }

    private var roomContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(MahjongText.myRoomTitle).font(.headline)
                MahjongChip(text: MahjongText.format(format), tint: CheckTheme.accent)
                MahjongChip(text: isPublic ? MahjongText.publicOn : MahjongText.publicOff, tint: CheckTheme.secondaryText)
                MahjongChip(text: MahjongText.seats(joinedCount), tint: joinedCount == 4 ? CheckTheme.working : CheckTheme.secondaryText)
                Spacer()
                if let expires = MahjongClockMath.local(formingMatch?.roomExpiresMs ?? store.lobbyRoom?.expiresAtMs, store: store) {
                    MahjongTick(store: store, interval: 1) { now in
                        Text("남은 \(MahjongText.remaining(max(0, Int(expires.timeIntervalSince(now)))))")
                            .font(.caption.monospacedDigit()).foregroundStyle(CheckTheme.secondaryText)
                    }
                }
            }
            RummyTableStage(chairs: chairs, inviteHint: store.isHost) {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Text(MahjongText.stakeLabel)
                        RubyIcon(size: 13)
                        Text("\(stake ?? 0)").fontWeight(.bold)
                    }
                    .font(.callout)
                    Text(MahjongText.split(stake: stake ?? 0)).font(.caption2).foregroundStyle(Color.white.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: MahjongWindowLayout.tableStageHeight)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(joinedCount == 4 ? (store.isHost ? MahjongNoticeText.fourGathered : MahjongText.waitingHost)
                     : MahjongText.needFour)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(joinedCount == 4 ? CheckTheme.working : CheckTheme.primaryText)
                Text(MahjongText.unseenDrop).font(.caption).foregroundStyle(CheckTheme.secondaryText)
                if let notice = store.notice {
                    Text(notice).font(.caption).foregroundStyle(CheckTheme.pending).lineLimit(2)
                }
            }
            HStack(spacing: 8) {
                if store.isHost {
                    MahjongCapsuleButton(title: MahjongText.start, tint: CheckTheme.working,
                                         isEnabled: store.canStart && !store.isWorking) {
                        Task { await store.start() }
                    }
                    .frame(width: 140)
                }
                if store.practice != nil {
                    // 방 띠의 [방 보기]로 나왔으면 하던 연습판으로 돌아가는 길(CC-02).
                    MahjongCapsuleButton(title: MahjongText.practiceViewButton, tint: CheckTheme.working, filled: false) {
                        store.showPractice()
                    }
                    .frame(width: 120)
                } else {
                    MahjongCapsuleButton(title: MahjongText.practice, tint: CheckTheme.working, filled: false, action: onPractice)
                        .frame(width: 120)
                }
                Spacer()
                MahjongCapsuleButton(title: MahjongText.leave, tint: CheckTheme.danger, filled: false,
                                     isEnabled: !store.isWorking) {
                    Task { await store.leaveRoom() }
                }
                .frame(width: 100)
            }
        }
    }

    // MARK: 방이 없을 때

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(MahjongText.createTitle).font(.headline)
            RummyTableStage(chairs: [RummyTableChair(kind: .person, name: me.name, character: me.characterID, isMe: true)]
                + Array(repeating: RummyTableChair(kind: .empty, name: MahjongText.emptySeat), count: 3),
                inviteHint: false) {
                Text(MahjongText.needFour).font(.callout.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: MahjongWindowLayout.tableStageHeight)
            Text(MahjongText.noRoomHint).font(.caption).foregroundStyle(CheckTheme.secondaryText).lineLimit(2)
            if let notice = store.notice {
                Text(notice).font(.caption).foregroundStyle(CheckTheme.pending).lineLimit(2)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                MahjongCapsuleButton(title: MahjongText.createTitle, isEnabled: !store.isWorking, action: onCreate)
                    .frame(width: 160)
                MahjongCapsuleButton(title: MahjongText.practice, tint: CheckTheme.working, filled: false, action: onPractice)
                    .frame(width: 120)
                Spacer()
            }
        }
    }
}

// MARK: - 방 만들기 시트

struct MahjongCreateRoomSheet: View {
    let store: MahjongStore
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(MahjongText.createTitle).font(.title3.weight(.bold))
            labeled(MahjongText.stakeLabel) {
                MahjongChoiceRow(options: MahjongStake.allCases.map { ($0, "\($0.rawValue)") }, selected: store.selectedStake,
                                 onSelect: { store.selectedStake = $0 })
            }
            labeled(MahjongText.formatLabel) {
                MahjongChoiceRow(options: [(MahjongFormat.tonpuu, MahjongText.format(.tonpuu)),
                                           (.hanchan, MahjongText.format(.hanchan))],
                                 selected: store.selectedFormat, onSelect: { store.selectedFormat = $0 })
            }
            labeled(MahjongText.publicLabel) {
                MahjongChoiceRow(options: [(false, MahjongText.publicOff), (true, MahjongText.publicOn)],
                                 selected: store.selectedPublic, onSelect: { store.selectedPublic = $0 })
            }
            Text(MahjongText.split(stake: store.selectedStake.rawValue) + " · " + MahjongText.createHint)
                .font(.caption).foregroundStyle(CheckTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                MahjongCapsuleButton(title: MahjongText.close, tint: CheckTheme.secondaryText, filled: false, action: onClose)
                MahjongCapsuleButton(title: MahjongText.createButton, isEnabled: !store.isWorking) {
                    onClose()
                    Task { await store.createRoom() }
                }
            }
        }
        .padding(20)
        .frame(width: MahjongWindowLayout.sheetWidth)
        .background(RoundedRectangle(cornerRadius: 16).fill(CheckTheme.panelElevated))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckTheme.border, lineWidth: 1))
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(CheckTheme.secondaryText)
            content()
        }
    }
}

// MARK: - 연습 시작 시트

struct MahjongPracticeStartSheet: View {
    let store: MahjongStore
    let onClose: () -> Void
    @State private var format: MahjongFormat = .tonpuu

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(MahjongText.practiceTitle).font(.title3.weight(.bold))
            VStack(alignment: .leading, spacing: 6) {
                Text(MahjongText.formatLabel).font(.caption.weight(.semibold)).foregroundStyle(CheckTheme.secondaryText)
                MahjongChoiceRow(options: [(MahjongFormat.tonpuu, MahjongText.format(.tonpuu)),
                                           (.hanchan, MahjongText.format(.hanchan))],
                                 selected: format, onSelect: { format = $0 })
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(MahjongText.practiceTimeLabel).font(.caption.weight(.semibold)).foregroundStyle(CheckTheme.secondaryText)
                MahjongChoiceRow(options: [(false, MahjongText.practiceTimedOff), (true, MahjongText.practiceTimedOn)],
                                 selected: store.practiceTimed, onSelect: { store.practiceTimed = $0 })
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(MahjongText.practiceSeatNote)
                Text(MahjongText.practiceNoRuby)
            }
            .font(.caption).foregroundStyle(CheckTheme.secondaryText)
            HStack(spacing: 8) {
                MahjongCapsuleButton(title: MahjongText.close, tint: CheckTheme.secondaryText, filled: false, action: onClose)
                MahjongCapsuleButton(title: MahjongText.practiceStart, tint: CheckTheme.working) {
                    onClose()
                    store.startPractice(format: format, timed: store.practiceTimed)
                }
            }
        }
        .padding(20)
        .frame(width: MahjongWindowLayout.sheetWidth)
        .background(RoundedRectangle(cornerRadius: 16).fill(CheckTheme.panelElevated))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(CheckTheme.border, lineWidth: 1))
    }
}

// MARK: - 연습 탁자 위 방 띠

/// "방 3/4 · 남은 7:12 · [방 보기]" — 넷째가 앉으면 "4명이 모였어요 [시작]"(방장).
struct MahjongRoomBandView: View {
    let store: MahjongStore
    let band: MahjongRoomBand

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.3.fill").foregroundStyle(band.readyToStart ? CheckTheme.working : CheckTheme.accent)
            if band.readyToStart {
                Text(MahjongText.roomBandReady).font(.callout.weight(.bold)).foregroundStyle(CheckTheme.working)
            } else {
                MahjongTick(store: store, interval: 1) { now in
                    Text(MahjongText.roomBand(joined: band.joined, seconds: max(0, Int(band.expiresAt.timeIntervalSince(now)))))
                        .font(.callout.weight(.semibold).monospacedDigit())
                }
            }
            Spacer(minLength: 6)
            if band.readyToStart, store.isHost {
                MahjongCapsuleButton(title: MahjongText.start, tint: CheckTheme.working, height: 28,
                                     isEnabled: store.canStart && !store.isWorking) {
                    Task { await store.start() }
                }
                .frame(width: 90)
            }
            MahjongCapsuleButton(title: MahjongText.roomViewButton, filled: false, height: 28) { store.showRoom() }
                .frame(width: 90)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Capsule().fill(CheckTheme.panelElevated))
        .overlay(Capsule().stroke(band.readyToStart ? CheckTheme.working : CheckTheme.accent.opacity(0.6),
                                  lineWidth: band.readyToStart ? 2 : 1))
    }
}
