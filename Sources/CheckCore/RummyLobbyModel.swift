import Foundation
import Observation

// 아잉 큐브 로비·방·이탈의 순수 조각 — 맥·폰 공용(0.3.71 맥 `RummyPanelLobby`·`RummyPanelResult`·`RummyExitFlow` 에서 폰 1.0.17 을 위해 옮겼다.
// 동작은 그대로다). 글자는 플랫폼 몫이다(맥 `RummyLobbyText` · 폰 `GamesRummyText`) — 여기는 순서와 판단만 둔다.

// MARK: - 초대 줄(방 없이 [초대] · 한 판 더)

/// 방이 없을 때 누른 [초대] · 결과의 [한 판 더] 가 남긴 '부를 사람' 줄. 방이 서면(내가 방장) 한 사람씩 `invite` 를 보낸다.
/// 스토어 동작은 한 번에 하나(`isWorking`)라 끝날 때마다(`isWorking` 이 내려갈 때) 다음 사람을 부른다.
@MainActor
@Observable
package final class RummyInviteQueue {
    package private(set) var pending: [UUID] = []

    package init() {}

    package enum Step: Equatable, Sendable {
        case wait
        case invite(UUID)
        case skip(UUID)
        case drop
    }

    /// 다음 할 일 — 순수 판단(시험이 표로 잰다).
    ///  · 일하는 중이면 기다린다(방 만들기·앞 초대가 떠 있다).
    ///  · 방이 없으면(만들기가 거절됐다) · 방이 forming 이 아니면 · 내가 방장이 아니면 줄을 버린다.
    ///  · 이미 자리가 있는 사람(초대 중·참가)은 건너뛴다.
    package nonisolated static func step(pending: [UUID], isWorking: Bool, roomStatus: RummyMatchStatus?, amHost: Bool,
                                         seated: Set<UUID>) -> Step {
        guard let first = pending.first else { return .wait }
        if isWorking { return .wait }
        guard roomStatus == .forming, amHost else { return .drop }
        return seated.contains(first) ? .skip(first) : .invite(first)
    }

    /// 사람 행 [초대]. 내 방이면 바로 초대, 방이 없으면 탁자를 열고 줄에 세운다.
    package func invite(_ userID: UUID, store: RummyStore) {
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
    package func createAndInvite(_ userIDs: [UUID], store: RummyStore) {
        pending = userIDs
        store.createRoom()
        if !pending.isEmpty { pump(store) }
    }

    package func pump(_ store: RummyStore) {
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

// MARK: - 탁자 의자

/// 탁자 둘레 의자 한 칸의 값.
package struct RummyTableChair: Equatable, Sendable {
    package enum Kind: Equatable, Sendable { case person, empty }
    package var kind: Kind
    package var userID: UUID?
    package var name: String
    package var avatarURL: String?
    package var character: String?
    package var seatNo: Int?
    package var tag: String?
    package var isHost: Bool
    package var isMe: Bool
    package var dimmed: Bool

    package init(kind: Kind, userID: UUID? = nil, name: String = "", avatarURL: String? = nil, character: String? = nil,
                 seatNo: Int? = nil, tag: String? = nil, isHost: Bool = false, isMe: Bool = false, dimmed: Bool = false) {
        self.kind = kind
        self.userID = userID
        self.name = name
        self.avatarURL = avatarURL
        self.character = character
        self.seatNo = seatNo
        self.tag = tag
        self.isHost = isHost
        self.isMe = isMe
        self.dimmed = dimmed
    }

    package static let empty = RummyTableChair(kind: .empty)
}

package enum RummyTableSeating {
    /// 자리 한 줄의 사실 — 글자로 옮기는 것은 플랫폼 몫이다.
    package struct SeatFacts: Equatable, Sendable {
        package let isMe: Bool
        package let isHost: Bool
        package let isInvited: Bool
    }

    /// 의자 넷 = [아래(나), 왼, 위, 오른]. 방이면 나를 아래, 앉은 사람을 내 다음 자리부터 시계 방향으로, 그다음 초대 중,
    /// 나머지는 빈 의자. 방이 없으면 나(`solo`)만 아래에 앉는다.
    package static func chairs(room: RummyRoom?, myUserID: UUID?, solo: RummyTableChair,
                               chair: (RummyRoomSeat, SeatFacts) -> RummyTableChair) -> [RummyTableChair] {
        guard let room else { return [solo, .empty, .empty, .empty] }
        let seats = room.seats ?? []
        let hostID = room.host?.id
        let joined = seats.filter { $0.state == .joined }
        let mineSeat = joined.first { $0.userId == myUserID }
        let mySeatNo = mineSeat?.seatNo ?? 0
        func relative(_ seat: RummyRoomSeat) -> Int { (((seat.seatNo ?? 9) - mySeatNo) % 4 + 4) % 4 }
        func make(_ seat: RummyRoomSeat) -> RummyTableChair {
            chair(seat, SeatFacts(isMe: seat.userId == myUserID, isHost: seat.userId == hostID,
                                  isInvited: seat.state == .invited))
        }
        let bottom = mineSeat.map(make) ?? .empty
        let others = joined.filter { $0.userId != myUserID }.sorted { relative($0) < relative($1) }
            + seats.filter { $0.state == .invited }
        var around = others.prefix(3).map(make)
        while around.count < 3 { around.append(.empty) }
        return [bottom] + around
    }
}

// MARK: - 한 판 더

extension RummyMatchState {
    /// [한 판 더] 가 부를 사람 — 나 말고, 기권하지 않은 사람(자리 순). 기권한 사람은 나간 사람이라 다시 부르지 않는다.
    package var rematchInvitees: [UUID] {
        (seats ?? []).filter { $0.seatNo != mySeatNo && $0.state != .forfeit }
            .sorted { ($0.seatNo ?? 9) < ($1.seatNo ?? 9) }
            .map(\.userId)
    }
}

// MARK: - 의도적 이탈

/// 창 닫기(폰은 화면 나가기) 판단.
package enum RummyCloseDecision: Equatable, Sendable {
    /// 그냥 닫는다(이탈할 판·방이 없다).
    case close
    /// 손님이 방에서 닫는다 — 묻지 않고 나간다.
    case leaveRoom
    /// 판 중 — "닫으면 기권돼요" 확인.
    case confirmForfeit
    /// 방장이 방에서 닫는다 — "방이 닫혀요" 확인.
    case confirmCloseRoom
}

package enum RummyExitPolicy {
    /// 창 닫기(사람이 누른 닫기만). 순수 판단 — 시험이 표로 잰다. `engaged` = 이 기기가 그 판에 손댔다(§6).
    package nonisolated static func closeDecision(phase: RummyStore.Phase, mySeatState: RummySeatState?, amHost: Bool,
                                                  engaged: Bool = true) -> RummyCloseDecision {
        guard engaged else { return .close }
        switch phase {
        case .playing: return mySeatState == .playing ? .confirmForfeit : .close
        case .room: return amHost ? .confirmCloseRoom : .leaveRoom
        case .lobby, .finished: return .close
        }
    }

    /// 앱 종료·로그아웃 앞에 `rummy_leave` 를 보낼 판·방이 있는가. 이미 기권한 관전자는 보낼 것이 없다.
    package nonisolated static func needsExitLeave(phase: RummyStore.Phase, mySeatState: RummySeatState?,
                                                   engaged: Bool = true) -> Bool {
        guard engaged else { return false }
        switch phase {
        case .room: return true
        case .playing: return mySeatState == .playing
        case .lobby, .finished: return false
        }
    }

    @MainActor
    package static func mySeat(_ store: RummyStore) -> RummyMatchSeat? {
        guard let match = store.match, let mine = match.mySeatNo else { return nil }
        return match.seats?.first { $0.seatNo == mine }
    }

    /// 방장인가 — 판 state 의 방장 id 와 내 자리의 사람 id(화면 `RummyScene.amHost` 와 같은 갈래).
    @MainActor
    package static func amHost(_ store: RummyStore) -> Bool {
        guard let hostID = store.match?.hostId, let seat = mySeat(store) else { return false }
        return seat.userId == hostID
    }

    @MainActor
    package static func closeDecision(for store: RummyStore) -> RummyCloseDecision {
        closeDecision(phase: store.phase, mySeatState: mySeat(store)?.state, amHost: amHost(store),
                      engaged: store.isEngagedInCurrentMatch)
    }

    @MainActor
    package static func needsExitLeave(_ store: RummyStore) -> Bool {
        needsExitLeave(phase: store.phase, mySeatState: mySeat(store)?.state, engaged: store.isEngagedInCurrentMatch)
    }
}
