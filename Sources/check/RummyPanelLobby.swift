import SwiftUI
import CheckCore

// MARK: - 아잉 큐브 로비·방 (2판 설계서 §3 — 시안 B "둘러앉은 탁자")
//
// 두 열 [사람·순위 탭 440 | 오른쪽 740]. 로비와 방은 **같은 화면**이다 — 오른쪽 탁자가 '새 탁자' ↔ '내 탁자' 로 갈린다.
//   · 왼쪽 사람 탭 = **초대할 수 있는 사람이 위**(서버 순서 그대로) → 지금 바쁜 사람(게임 중·집중, 흐리게) →
//     '업데이트가 필요한 사람 N명' 은 바닥에 **접혀** 있다(눌러야 펼친다).
//   · [초대] 는 방이 없어도 살아 있다 — 누르면 고른 판돈·공개 여부로 탁자를 열고 그 사람을 부른다(`RummyInviteQueue`).
//   · 오른쪽 위 = 탁자(가운데 판돈, 둘레에 의자 넷 — 나는 아래). 방이면 판돈 × 인원 = 상금 · 등수 분배 · 남은 시간 · [시작]·[나가기].
//   · 오른쪽 아래 = **받은 초대 + 공개 방 한 목록**(카드 한 줄). 없으면 카드 대신 한 줄짜리 안내로 접고 탁자가 그만큼 커진다.
//   · 내 전적은 머리글 칩에 있다(따로 빈 카드를 두지 않는다).
// 버튼을 끄는 판단은 "서버가 어차피 거절할 것"만 본다(구버전·게임 중·집중·가득 참). 나머지 거절은 서버 문구(`notice`)가 말한다.

enum RummyLobbyText {
    static let newTable = "새 탁자"
    static let myTable = "내 탁자"
    static let newTableHint = "[초대]를 누르거나 탁자를 열어요"
    static let openTable = "탁자 열기"
    static let readyHeader = "초대 가능"
    static let busyHeader = "지금은 바빠요"
    static let calling = "부르는 중"
    static let waitingAnswer = "답 기다리는 중"
    static let seated = "앉음"
    static let me = "나"
    static let take = "앉기"
    static let joinEmpty = "받은 초대나 열린 공개 탁자가 생기면 여기에 떠요"

    static func outdatedFold(_ count: Int, expanded: Bool) -> String {
        expanded ? "업데이트가 필요한 사람 \(count)명 접기" : "업데이트가 필요한 사람 \(count)명"
    }

    static let outdatedHint = "새 버전이면 같이 할 수 있어요"

    static func called(by name: String) -> String { "\(name)님이 불렀어요" }

    static func publicTable(of name: String) -> String { "\(name)님의 공개 탁자" }

    static func freeSeats(_ count: Int) -> String { "빈자리 \(count)" }

    static func pot(stake: Int, players: Int) -> String { "\(stake) × \(players)명 = \(stake * players)" }

    static func startWith(_ players: Int) -> String { "\(players)명으로 시작" }

    static func closesIn(_ seconds: Int) -> String { "\(RummyText.clock(seconds)) 뒤 닫혀요" }

    static func stakeCaption(_ stake: Int) -> String { "판돈 \(stake) · 끝나면 등수대로 · 한 차례 60초" }
}

// MARK: - 초대 줄(방 없이 [초대] · 한 판 더)

/// 방이 없을 때 누른 [초대] · 결과의 [한 판 더] 가 남긴 '부를 사람' 줄. 방이 서면(내가 방장) 한 사람씩 `invite` 를 보낸다.
/// 스토어 동작은 한 번에 하나(`isWorking`)라 끝날 때마다(`isWorking` 이 내려갈 때) 다음 사람을 부른다.
@MainActor
@Observable
final class RummyInviteQueue {
    private(set) var pending: [UUID] = []

    enum Step: Equatable {
        case wait
        case invite(UUID)
        case skip(UUID)
        case drop
    }

    /// 다음 할 일 — 순수 판단(시험이 표로 잰다).
    ///  · 일하는 중이면 기다린다(방 만들기·앞 초대가 떠 있다).
    ///  · 방이 없으면(만들기가 거절됐다) · 방이 forming 이 아니면 · 내가 방장이 아니면 줄을 버린다.
    ///  · 이미 자리가 있는 사람(초대 중·참가)은 건너뛴다.
    static func step(pending: [UUID], isWorking: Bool, roomStatus: RummyMatchStatus?, amHost: Bool,
                     seated: Set<UUID>) -> Step {
        guard let first = pending.first else { return .wait }
        if isWorking { return .wait }
        guard roomStatus == .forming, amHost else { return .drop }
        return seated.contains(first) ? .skip(first) : .invite(first)
    }

    /// 사람 행 [초대]. 내 방이면 바로 초대, 방이 없으면 탁자를 열고 줄에 세운다.
    func invite(_ userID: UUID, store: RummyStore) {
        if store.match?.status == .forming {
            if RummyExitPolicy.amHost(store) { store.invite(userID) }
            return
        }
        guard store.match == nil, !pending.contains(userID) else { return }
        pending.append(userID)
        if pending.count == 1 { store.createRoom() }
        pump(store)
    }

    /// 결과 [한 판 더] — 탁자를 열고(판돈·공개 여부는 호출자가 이미 맞췄다) 지난 판 사람들을 줄에 세운다.
    func createAndInvite(_ userIDs: [UUID], store: RummyStore) {
        pending = userIDs
        store.createRoom()
        if !pending.isEmpty { pump(store) }
    }

    func pump(_ store: RummyStore) {
        while true {
            let seated = Set((store.match?.seats ?? []).map(\.userId))
            switch Self.step(pending: pending, isWorking: store.isWorking, roomStatus: store.match?.status,
                             amHost: RummyExitPolicy.amHost(store), seated: seated) {
            case .wait:
                return
            case .drop:
                pending.removeAll()
                return
            case .skip(let id):
                pending.removeAll { $0 == id }
            case .invite(let id):
                pending.removeAll { $0 == id }
                store.invite(id)
                return
            }
        }
    }
}

extension View {
    /// 창 루트에 한 번: 스토어 동작이 끝날 때 · 판이 바뀔 때 초대 줄을 민다.
    func rummyInviteQueue(_ queue: RummyInviteQueue, store: RummyStore) -> some View {
        onChange(of: store.isWorking) { _, _ in queue.pump(store) }
            .onChange(of: store.match?.id) { _, _ in queue.pump(store) }
    }
}

// MARK: - 로비 화면

struct RummyLobbyView: View {
    let store: RummyStore
    let scene: RummyScene
    let tab: RummyLobbyTab
    let onSelectTab: (RummyLobbyTab) -> Void
    let onLeaveRoom: () -> Void
    let clipsOverflowInsteadOfScroll: Bool
    var me: ChessPlayerFace = .fallback
    var calling: [UUID] = []
    var onInvite: (UUID) -> Void = { _ in }
    var showsOutdated: Bool = false

    /// 받은 초대 + 공개 방 한 목록(초대 먼저 · 서버 순서 · 같은 방은 한 번 · 지금 앉은 방은 뺀다).
    static func joinables(_ scene: RummyScene) -> [RummyJoinable] {
        let mine = scene.myRoom?.id
        let invites = (scene.lobby?.invites ?? []).filter { $0.id != mine }
        let invited = Set(invites.map(\.id))
        let rooms = (scene.lobby?.publicRooms ?? []).filter { $0.id != mine && !invited.contains($0.id) }
        return invites.map { RummyJoinable(room: $0, isInvite: true) } + rooms.map { RummyJoinable(room: $0, isInvite: false) }
    }

    var body: some View {
        let joinables = Self.joinables(scene)
        HStack(alignment: .top, spacing: RummyWindowLayout.columnSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                RummyLobbyTabs(selected: tab, onSelect: onSelectTab)
                    .frame(height: RummyWindowLayout.lobbyTabHeight)
                switch tab {
                case .users:
                    RummyPeopleColumn(scene: scene, clips: clipsOverflowInsteadOfScroll, calling: calling,
                                      onInvite: onInvite, startsExpanded: showsOutdated)
                case .ranking:
                    RummyRankList(scene: scene, clips: clipsOverflowInsteadOfScroll)
                }
            }
            .frame(width: RummyWindowLayout.lobbyListWidth, height: RummyWindowLayout.bodyHeight, alignment: .top)
            .clipped()
            VStack(spacing: RummyWindowLayout.sideSpacing) {
                RummyTableCard(store: store, scene: scene, me: me, onLeave: onLeaveRoom)
                    .frame(height: RummyWindowLayout.tableCardHeight(hasJoinables: !joinables.isEmpty))
                if joinables.isEmpty {
                    RummyJoinEmptyLine()
                        .frame(height: RummyWindowLayout.joinEmptyHeight)
                } else {
                    RummyJoinRow(store: store, scene: scene, joinables: joinables, clips: clipsOverflowInsteadOfScroll)
                        .frame(height: RummyWindowLayout.joinCardHeight)
                }
            }
            .frame(width: RummyWindowLayout.lobbySideWidth, height: RummyWindowLayout.bodyHeight, alignment: .top)
        }
    }
}

struct RummyJoinable: Identifiable, Equatable {
    let room: RummyRoom
    let isInvite: Bool
    var id: UUID { room.id }
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

// MARK: - 사람 탭

private struct RummyPeopleColumn: View {
    let scene: RummyScene
    let clips: Bool
    let calling: [UUID]
    let onInvite: (UUID) -> Void
    var startsExpanded: Bool = false

    @State private var expanded = false

    private var users: [RummyLobbyUser] { scene.lobby?.users ?? [] }
    /// 서버 정렬(근무 중 → 가능 → 이름)을 지키며 셋으로 나눈다 — 줄 안에서 다시 줄 세우지 않는다.
    private var ready: [RummyLobbyUser] { users.filter { $0.capable != false && $0.inMatch != true && $0.focusMode != true } }
    private var busy: [RummyLobbyUser] { users.filter { $0.capable != false && ($0.inMatch == true || $0.focusMode == true) } }
    private var outdated: [RummyLobbyUser] { users.filter { $0.capable == false } }
    private var showOutdated: Bool { expanded || startsExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(RummyText.peopleCaption(inRoom: scene.myRoom != nil, amHost: scene.amHost))
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            if users.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 목록은 남은 높이만 차지한다(덮개로 얹어 긴 목록이 아래 '업데이트 필요' 줄을 밀어내지 않게 — 클립 갈래 렌더 포함).
                Color.clear.overlay(alignment: .topLeading) {
                RummyScrollBox(clips: clips) {
                    VStack(alignment: .leading, spacing: RummyWindowLayout.lobbyRowSpacing) {
                        if !ready.isEmpty {
                            sectionHeader(RummyLobbyText.readyHeader, count: ready.count, tint: CheckTheme.working)
                            rows(ready, dimmed: false)
                        }
                        if !busy.isEmpty {
                            sectionHeader(RummyLobbyText.busyHeader, count: busy.count, tint: CheckTheme.secondaryText)
                            rows(busy, dimmed: true)
                        }
                        if showOutdated, !outdated.isEmpty {
                            rows(outdated, dimmed: true)
                        }
                    }
                }
                }
                .clipped()
                if !outdated.isEmpty {
                    RummyOutdatedFold(count: outdated.count, expanded: showOutdated, onToggle: { expanded.toggle() })
                        .frame(height: 40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tetrisDuelCard()
    }

    private func sectionHeader(_ title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text("\(title) \(count)").font(.caption.weight(.bold)).foregroundStyle(tint)
        }
        .padding(.top, 2)
    }

    private func rows(_ list: [RummyLobbyUser], dimmed: Bool) -> some View {
        ForEach(list) { user in
            RummyPersonRow(user: user, action: action(for: user), onInvite: { onInvite(user.id) }, dimmed: dimmed)
                .frame(height: RummyWindowLayout.lobbyRowHeight)
        }
    }

    private var emptyText: String {
        switch scene.availability {
        case .updateRequired: return scene.notice ?? RummyText.updateRequired
        case .serverMissing: return RummyText.serverMissing
        case .available: return scene.lobby == nil ? RummyText.loadingUsers : RummyText.emptyUsers
        }
    }

    /// 사람 행 오른쪽: 방이 없으면 [초대](= 탁자 열고 부르기), 내 방(방장)이면 [초대]·'초대함'·'참가함', 남의 방이면 없음.
    private func action(for user: RummyLobbyUser) -> RummyPersonRow.Action {
        if calling.contains(user.id) { return .tag(RummyLobbyText.calling) }
        let canInvite = user.capable != false && user.inMatch != true && user.focusMode != true && !scene.isWorking
        guard let room = scene.myRoom else {
            guard scene.availability == .available, user.capable != false else { return .hidden }
            return .invite(enabled: canInvite)
        }
        guard scene.amHost else { return .hidden }
        if let seat = room.seats?.first(where: { $0.userId == user.id }) {
            switch seat.state {
            case .joined: return .tag(RummyText.joined)
            case .invited: return .tag(RummyText.invited)
            default: break
            }
        }
        return .invite(enabled: canInvite)
    }
}

/// '업데이트가 필요한 사람 N명' 접힌 줄.
private struct RummyOutdatedFold: View {
    let count: Int
    let expanded: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.app")
                Text(RummyLobbyText.outdatedFold(count, expanded: expanded)).font(.caption.weight(.bold))
                Text(RummyLobbyText.outdatedHint)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2.weight(.bold))
            }
            .foregroundStyle(CheckTheme.pending)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CheckTheme.pending.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    var dimmed: Bool = false

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
        .opacity(dimmed ? 0.55 : 1)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(dimmed ? 0.02 : 0.04)))
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

// MARK: - 탁자(새 탁자 · 내 탁자)

/// 탁자 둘레 의자 한 칸의 값.
struct RummyTableChair: Equatable {
    enum Kind: Equatable { case person, empty }
    var kind: Kind
    var userID: UUID?
    var name: String = ""
    var avatarURL: String?
    var character: String?
    var seatNo: Int?
    var tag: String?
    var isHost = false
    var isMe = false
    var dimmed = false

    static let empty = RummyTableChair(kind: .empty)
}

enum RummyTableSeating {
    /// 의자 넷 = [아래(나), 왼, 위, 오른]. 방이면 나를 아래, 앉은 사람을 내 다음 자리부터 시계 방향으로, 그다음 초대 중,
    /// 나머지는 빈 의자. 방이 없으면 나만 아래에 앉는다.
    static func chairs(room: RummyRoom?, me: ChessPlayerFace, myUserID: UUID?) -> [RummyTableChair] {
        guard let room else {
            let mine = RummyTableChair(kind: .person, userID: myUserID, name: me.name,
                                       avatarURL: me.avatarURL?.absoluteString, character: me.characterID,
                                       tag: RummyLobbyText.me, isMe: true)
            return [mine, .empty, .empty, .empty]
        }
        let seats = room.seats ?? []
        let hostID = room.host?.id
        let joined = seats.filter { $0.state == .joined }
        let mineSeat = joined.first { $0.userId == myUserID }
        let mySeatNo = mineSeat?.seatNo ?? 0
        func relative(_ seat: RummyRoomSeat) -> Int { (((seat.seatNo ?? 9) - mySeatNo) % 4 + 4) % 4 }
        func chair(_ seat: RummyRoomSeat) -> RummyTableChair {
            let isMe = seat.userId == myUserID
            let isHost = seat.userId == hostID
            let tag: String
            if seat.state == .invited {
                tag = RummyLobbyText.waitingAnswer
            } else if isMe {
                tag = isHost ? "\(RummyLobbyText.me) · \(RummyText.hostTag)" : RummyLobbyText.me
            } else {
                tag = isHost ? RummyText.hostTag : RummyLobbyText.seated
            }
            return RummyTableChair(kind: .person, userID: seat.userId, name: seat.displayName ?? "?",
                                   avatarURL: seat.avatarUrl, character: seat.character,
                                   seatNo: seat.state == .joined ? seat.seatNo : nil, tag: tag, isHost: isHost,
                                   isMe: isMe, dimmed: seat.state == .invited)
        }
        let bottom = mineSeat.map(chair) ?? .empty
        let others = joined.filter { $0.userId != myUserID }.sorted { relative($0) < relative($1) }
            + seats.filter { $0.state == .invited }
        var around = others.prefix(3).map(chair)
        while around.count < 3 { around.append(.empty) }
        return [bottom] + around
    }
}

private struct RummyTableCard: View {
    let store: RummyStore
    let scene: RummyScene
    let me: ChessPlayerFace
    let onLeave: () -> Void

    private var room: RummyRoom? { scene.myRoom }
    private var joinedCount: Int { room?.seats?.filter { $0.state == .joined }.count ?? 0 }
    private var canAct: Bool { !scene.isWorking && scene.availability == .available }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
                .frame(height: 26)
            Spacer(minLength: 0)
            RummyTableStage(chairs: RummyTableSeating.chairs(room: room, me: me, myUserID: scene.myUserID),
                            inviteHint: room == nil || scene.amHost) {
                center
            }
            .frame(maxWidth: .infinity)
            .frame(height: RummyWindowLayout.tableStageHeight)
            Spacer(minLength: 0)
            if let line = noticeLine {
                RummyNoticeLine(text: line)
                    .frame(height: 16)
            }
            controls
                .frame(height: 38)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tetrisDuelCard()
    }

    private var noticeLine: String? {
        if let notice = scene.notice { return notice }
        guard room != nil else { return nil }
        return scene.amHost ? RummyText.startHintHost : RummyText.startHintGuest
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            Text(room == nil ? RummyLobbyText.newTable : RummyLobbyText.myTable).font(.headline)
            if let room {
                RummyChip(text: RummyText.stake(room.stake), tint: CheckTheme.pending)
                RummyChip(text: room.isPublic == true ? RummyText.publicOn : RummyText.publicOff,
                          tint: room.isPublic == true ? CheckTheme.working : CheckTheme.secondaryText)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "hourglass")
                    RummyCountdownLeaf(remaining: scene.roomRemaining(store), fixedNow: scene.fixedNow,
                                       label: RummyLobbyText.closesIn, urgentBelow: 60)
                }
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(CheckTheme.accent.opacity(0.12)))
                .overlay(Capsule().stroke(CheckTheme.accent.opacity(0.45), lineWidth: 1))
            } else {
                RummyChip(text: RummyLobbyText.newTableHint)
                Spacer()
            }
        }
    }

    /// 탁자 가운데 — 방이 없으면 판돈 고르기, 방이면 상금(판돈 × 인원)과 등수 분배.
    @ViewBuilder
    private var center: some View {
        if let room {
            let stake = room.stake ?? 0
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    RubyIcon(size: 16)
                    Text(RummyLobbyText.pot(stake: stake, players: max(joinedCount, 1)))
                        .font(.title3.weight(.heavy))
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(Capsule().fill(Color.black.opacity(0.25)))
                .overlay(Capsule().stroke(RummyTableStyle.ruby.opacity(0.8), lineWidth: 2))
                Text(RummyText.split(seatCount: max(joinedCount, 2), stake: stake))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckTheme.secondaryText)
            }
        } else {
            let stakes = scene.lobby?.stakes ?? [3, 5, 10]
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(stakes, id: \.self) { stake in
                        let isOn = stake == store.selectedStake
                        Button { store.selectedStake = stake } label: {
                            HStack(spacing: 5) {
                                RubyIcon(size: 13)
                                Text("\(stake)").font(.callout.weight(.heavy)).monospacedDigit()
                            }
                            .foregroundStyle(CheckTheme.primaryText)
                            .frame(width: 70, height: 34)
                            .background(Capsule().fill(isOn ? RummyTableStyle.ruby.opacity(0.22) : Color.black.opacity(0.25)))
                            .overlay(Capsule().stroke(isOn ? RummyTableStyle.ruby : Color.white.opacity(0.14),
                                                      lineWidth: isOn ? 2 : 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                Text(RummyLobbyText.stakeCaption(store.selectedStake))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckTheme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 10) {
            if room != nil {
                if !scene.amHost {
                    Spacer()
                }
                TetrisDuelActionButton(title: RummyText.leave, icon: "rectangle.portrait.and.arrow.right",
                                       tint: CheckTheme.danger, style: .outline, height: 38,
                                       isEnabled: !scene.isWorking, action: onLeave)
                    .frame(width: 140)
                if scene.amHost {
                    Spacer()
                    TetrisDuelActionButton(title: RummyLobbyText.startWith(joinedCount), icon: "play.fill",
                                           tint: CheckTheme.working, height: 38, fullWidth: true,
                                           isEnabled: joinedCount >= 2 && !scene.isWorking,
                                           action: { store.startGame() })
                        .frame(width: 220)
                }
            } else {
                Button { store.createPublic.toggle() } label: {
                    HStack(spacing: 8) {
                        ZStack(alignment: store.createPublic ? .trailing : .leading) {
                            Capsule().fill(store.createPublic ? CheckTheme.working : Color.white.opacity(0.18))
                                .frame(width: 38, height: 22)
                            Circle().fill(Color.white).frame(width: 18, height: 18).padding(2)
                        }
                        Text(store.createPublic ? RummyText.publicOn : RummyText.publicOff)
                            .font(.callout)
                            .foregroundStyle(CheckTheme.primaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                TetrisDuelActionButton(title: RummyLobbyText.openTable, icon: "plus", height: 38, fullWidth: true,
                                       isEnabled: canAct, action: { store.createRoom() })
                    .frame(width: 220)
            }
        }
    }
}

enum RummyTableStyle {
    /// 루비 분홍(판돈 테두리).
    static let ruby = Color(red: 1.0, green: 0.42, blue: 0.72)
    /// 탁자 펠트(남보라 — 사용자가 고른 테이블 그림의 폴백 톤).
    static let feltTop = Color(red: 0.24, green: 0.22, blue: 0.40)
    static let feltBottom = Color(red: 0.15, green: 0.14, blue: 0.27)
    static let rim = Color(red: 0.33, green: 0.34, blue: 0.43)
}

/// 둥근 탁자 + 둘레 의자 넷([아래, 왼, 위, 오른]).
struct RummyTableStage<Center: View>: View {
    let chairs: [RummyTableChair]
    var inviteHint: Bool = true
    @ViewBuilder let center: Center

    static var ovalSize: CGSize { CGSize(width: 380, height: 128) }
    static var chairSize: CGSize { CGSize(width: 120, height: 88) }

    /// 의자 중심의 탁자 중심 기준 자리(pt).
    static func offset(_ index: Int) -> CGSize {
        let oval = ovalSize
        let chair = chairSize
        switch index {
        case 0: return CGSize(width: 0, height: oval.height / 2 + chair.height / 2 - 18)
        case 1: return CGSize(width: -(oval.width / 2 + chair.width / 2 + 8), height: 0)
        case 2: return CGSize(width: 0, height: -(oval.height / 2 + chair.height / 2 - 18))
        default: return CGSize(width: oval.width / 2 + chair.width / 2 + 8, height: 0)
        }
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [RummyTableStyle.feltTop, RummyTableStyle.feltBottom],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(RummyTableStyle.rim, lineWidth: 9))
                .overlay(Capsule().inset(by: 9).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .frame(width: Self.ovalSize.width, height: Self.ovalSize.height)
            center
            ForEach(Array(chairs.prefix(4).enumerated()), id: \.offset) { index, chair in
                RummyTableChairView(chair: chair, inviteHint: inviteHint)
                    .frame(width: Self.chairSize.width, height: Self.chairSize.height)
                    .offset(Self.offset(index))
            }
        }
    }
}

private struct RummyTableChairView: View {
    let chair: RummyTableChair
    let inviteHint: Bool

    var body: some View {
        VStack(spacing: 4) {
            switch chair.kind {
            case .person:
                ZStack(alignment: .top) {
                    CheckAvatarView(name: chair.name, userID: chair.userID?.uuidString.lowercased(),
                                    avatarURL: chair.avatarURL.flatMap(URL.init(string:)), size: 46,
                                    characterHint: chair.character)
                        .overlay(Circle().stroke(chair.isMe ? CheckTheme.accent : Color.white.opacity(0.25),
                                                 lineWidth: chair.isMe ? 2.5 : 1.5))
                        .opacity(chair.dimmed ? 0.5 : 1)
                    if chair.isHost {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CheckTheme.pending)
                            .offset(y: -12)
                    }
                }
                // 아래 의자(나)는 위가 탁자 가운데라 말풍선을 오른쪽에 세운다.
                .rummyReactionAnchor(seatNo: chair.seatNo, edge: chair.isMe ? .trailing : .top)
                Text(chair.name).font(.caption.weight(.bold)).lineLimit(1)
                if let tag = chair.tag {
                    RummyChip(text: tag, tint: chair.dimmed ? CheckTheme.secondaryText
                                             : (chair.isHost ? CheckTheme.pending : CheckTheme.working))
                }
            case .empty:
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(inviteHint ? CheckTheme.accent.opacity(0.8) : CheckTheme.border)
                    .frame(width: 46, height: 46)
                    .overlay(Image(systemName: "plus").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(inviteHint ? CheckTheme.accent : CheckTheme.secondaryText))
                Text(inviteHint ? RummyText.invite : RummyText.emptySeat)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckTheme.secondaryText)
            }
        }
    }
}

// MARK: - 받은 초대 + 공개 방 한 목록

private struct RummyJoinRow: View {
    let store: RummyStore
    let scene: RummyScene
    let joinables: [RummyJoinable]
    let clips: Bool

    private var canJoin: Bool { scene.myRoom == nil && !scene.isWorking && scene.availability == .available }

    var body: some View {
        RummyScrollBox(axis: .horizontal, clips: clips) {
            HStack(spacing: RummyWindowLayout.sideSpacing) {
                ForEach(joinables) { item in
                    RummyJoinCard(item: item, canJoin: canJoin && !isFull(item.room),
                                  onJoin: { store.join(item.room.id) }, onDecline: { store.decline(item.room.id) })
                        .frame(width: RummyWindowLayout.joinCardWidth, height: RummyWindowLayout.joinCardHeight)
                }
            }
        }
    }

    private func isFull(_ room: RummyRoom) -> Bool {
        (room.seats?.filter { $0.state == .joined }.count ?? 0) >= (room.maxSeats ?? 4)
    }
}

private struct RummyJoinCard: View {
    let item: RummyJoinable
    let canJoin: Bool
    let onJoin: () -> Void
    let onDecline: () -> Void

    private var room: RummyRoom { item.room }
    private var joined: [RummyRoomSeat] { (room.seats ?? []).filter { $0.state == .joined } }

    var body: some View {
        let hostName = room.host?.displayName ?? "?"
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CheckAvatarView(name: hostName, userID: room.host?.id.uuidString.lowercased(),
                                avatarURL: room.host?.avatarUrl.flatMap(URL.init(string:)), size: 32,
                                characterHint: room.host?.character)
                Text(item.isInvite ? RummyLobbyText.called(by: hostName) : RummyLobbyText.publicTable(of: hostName))
                    .font(.callout.weight(.bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                RummyChip(text: RummyText.stake(room.stake), tint: CheckTheme.pending)
                RummyChip(text: item.isInvite ? RummyText.seats(joined.count, max: room.maxSeats ?? 4)
                                              : RummyLobbyText.freeSeats(max(0, (room.maxSeats ?? 4) - joined.count)),
                          tint: item.isInvite ? CheckTheme.secondaryText : CheckTheme.working)
            }
            HStack(spacing: -6) {
                ForEach(joined.prefix(4)) { seat in
                    CheckAvatarView(name: seat.displayName ?? "?", userID: seat.userId.uuidString.lowercased(),
                                    avatarURL: seat.avatarUrl.flatMap(URL.init(string:)), size: 24,
                                    characterHint: seat.character)
                        .overlay(Circle().stroke(CheckTheme.panel, lineWidth: 2))
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if item.isInvite {
                    TetrisDuelActionButton(title: RummyText.join, tint: CheckTheme.working, height: 32, fullWidth: true,
                                           isEnabled: canJoin, action: onJoin)
                    TetrisDuelActionButton(title: RummyText.decline, style: .outline, height: 32, action: onDecline)
                } else {
                    TetrisDuelActionButton(title: RummyLobbyText.take, style: .outline, height: 32, fullWidth: true,
                                           isEnabled: canJoin, action: onJoin)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(item.isInvite ? CheckTheme.accent.opacity(0.10) : CheckTheme.panel.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(item.isInvite ? CheckTheme.accent.opacity(0.55) : CheckTheme.border, lineWidth: item.isInvite ? 1.5 : 1))
    }
}

/// 초대·공개 방이 없을 때 — 빈 카드 대신 한 줄.
private struct RummyJoinEmptyLine: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
            Text(RummyLobbyText.joinEmpty).font(.caption)
            Spacer()
        }
        .foregroundStyle(CheckTheme.secondaryText)
        .padding(.horizontal, RummyWindowLayout.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .foregroundStyle(CheckTheme.border))
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
