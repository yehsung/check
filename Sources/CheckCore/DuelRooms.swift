// 1:1 대기방(아잉 큐브처럼) — 맥 1:1 여섯 게임 공용 방(서버 duel-rooms 20261112120000).
//
// 방 = **상대를 정하지 않은 신청**. 방장이 게임 · 판돈을 골라 열면 그 게임 로비 '기다리는 방'에 뜨고, 누구든 [참가]하면 서버가
// 한 트랜잭션에서 그 게임의 신청(방장) + 수락(참가자)으로 판을 세운다 — 판돈 · 정산 · 전적 · 대국 중 판정은 각 게임 것 그대로다.
// 대표 결정 #d_xydpun7g29KO "추천안대로 만들기": 도전 남김 · 방장이 판돈 · 들어오면 바로 시작 · 맥 여섯 게임 한 번에 · 폰 다음 판.
//
// 이 스토어가 지키는 것:
//  ① 방장 기기는 방이 열려 있는 동안 창과 상관없이 숨(`duel_room_ping`)을 쉰다(20초 · 게임 초인종이 오면 바로) — 앱이 꺼지면
//     서버가 75초 뒤 목록에서 빼고 매분 훑기가 닫는다.
//  ② 숨이 '시작됨 + 판 id' 를 돌려주면 그 방마다 **한 번** `onRoomStarted` — 앱이 그 판을 이 기기가 연 판으로 받아 창을 연다
//     (게임 스토어의 '이 기기가 연 판' 장부 · GameDeviceLedger). 참가자는 `join` 이 ok 면 `onJoined`.
//  ③ 응답 상태는 모르는 값이 와도 죽지 않는다(.unknown). 문이 닫혀 있으면(unsupported_client · door_open 거짓) 방 칸을 감춘다.
import Foundation
import Observation

/// 방을 열 수 있는 게임(서버 `duel_rooms_games()` 와 같은 글자).
package enum DuelRoomGame: String, CaseIterable, Sendable, Hashable {
    case gomoku, chess, tetris, reversi, crossyDuel = "crossy_duel", alkkagi

    /// 사용자에게 보이는 짧은 이름(다른 게임 방을 열어 두었을 때 한 줄에 쓴다).
    package var title: String {
        switch self {
        case .gomoku: "오목"
        case .chess: "체스"
        case .tetris: "테트리스"
        case .reversi: "아잉 뒤집기"
        case .crossyDuel: "1:1 길건너"
        case .alkkagi: "1:1 알까기"
        }
    }
}

package struct DuelRoomHost: Decodable, Equatable, Sendable {
    package var userID: String
    package var displayName: String
    package var avatarURL: String?
    package var character: String?

    package init(userID: String, displayName: String, avatarURL: String? = nil, character: String? = nil) {
        self.userID = userID
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.character = character
    }

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id", displayName = "display_name", avatarURL = "avatar_url", character
    }
}

package struct DuelRoom: Decodable, Equatable, Identifiable, Sendable {
    package var id: String
    package var gameRaw: String
    package var stake: Int
    package var status: String
    package var createdMs: Double
    package var seenMs: Double?
    package var expiresMs: Double?
    package var matchID: String?
    package var closeReason: String?
    package var host: DuelRoomHost?

    package var game: DuelRoomGame? { DuelRoomGame(rawValue: gameRaw) }
    package var isOpen: Bool { status == "open" }
    package var isStarted: Bool { status == "started" && !(matchID ?? "").isEmpty }

    package init(id: String, game: DuelRoomGame, stake: Int, status: String = "open", createdMs: Double,
                 seenMs: Double? = nil, expiresMs: Double? = nil, matchID: String? = nil, closeReason: String? = nil,
                 host: DuelRoomHost? = nil) {
        self.id = id
        self.gameRaw = game.rawValue
        self.stake = stake
        self.status = status
        self.createdMs = createdMs
        self.seenMs = seenMs
        self.expiresMs = expiresMs
        self.matchID = matchID
        self.closeReason = closeReason
        self.host = host
    }

    private enum CodingKeys: String, CodingKey {
        case id, gameRaw = "game", stake, status, createdMs = "created_ms", seenMs = "seen_ms", expiresMs = "expires_ms"
        case matchID = "match_id", closeReason = "close_reason", host
    }
}

/// 서버 응답 상태(모르는 값은 .unknown — 디코드가 죽지 않는다).
package enum DuelRoomStatus: String, Sendable {
    case ok, unauthorized, invalid, insufficient, busy, stale, focused, blackout
    case unsupportedClient = "unsupported_client", unsupportedGame = "unsupported_game", notFound = "not_found"
    case roomGone = "room_gone", ownRoom = "own_room", updateRequired = "update_required", hostBusy = "host_busy"
    case unknown
}

package struct DuelRoomsResponse: Decodable, Sendable {
    package var status: DuelRoomStatus
    package var serverNowMs: Double?
    package var stakes: [Int]?
    package var doorOpen: Bool?
    package var rooms: [DuelRoom]?
    package var myRoom: DuelRoom?
    package var room: DuelRoom?
    package var need: Int?
    package var have: Int?
    package var reason: String?
    package var matchID: String?
    package var gameRaw: String?
    package var rubyBalance: Int?

    package init(status: DuelRoomStatus, serverNowMs: Double? = nil, stakes: [Int]? = nil, doorOpen: Bool? = nil,
                 rooms: [DuelRoom]? = nil, myRoom: DuelRoom? = nil, room: DuelRoom? = nil, need: Int? = nil,
                 have: Int? = nil, reason: String? = nil, matchID: String? = nil, game: DuelRoomGame? = nil,
                 rubyBalance: Int? = nil) {
        self.status = status
        self.serverNowMs = serverNowMs
        self.stakes = stakes
        self.doorOpen = doorOpen
        self.rooms = rooms
        self.myRoom = myRoom
        self.room = room
        self.need = need
        self.have = have
        self.reason = reason
        self.matchID = matchID
        self.gameRaw = game?.rawValue
        self.rubyBalance = rubyBalance
    }

    private enum CodingKeys: String, CodingKey {
        case status, serverNowMs = "server_now_ms", stakes, doorOpen = "door_open", rooms, myRoom = "my_room", room
        case need, have, reason, matchID = "match_id", gameRaw = "game", rubyBalance = "ruby_balance"
    }

    package init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = DuelRoomStatus(rawValue: (try? c.decode(String.self, forKey: .status)) ?? "") ?? .unknown
        serverNowMs = try? c.decodeIfPresent(Double.self, forKey: .serverNowMs)
        stakes = try? c.decodeIfPresent([Int].self, forKey: .stakes)
        doorOpen = try? c.decodeIfPresent(Bool.self, forKey: .doorOpen)
        // 방 줄 하나가 깨져도 나머지는 산다.
        if let raw = try? c.decodeIfPresent([FailableRoom].self, forKey: .rooms) {
            rooms = raw.compactMap(\.room)
        }
        myRoom = try? c.decodeIfPresent(DuelRoom.self, forKey: .myRoom)
        room = try? c.decodeIfPresent(DuelRoom.self, forKey: .room)
        need = try? c.decodeIfPresent(Int.self, forKey: .need)
        have = try? c.decodeIfPresent(Int.self, forKey: .have)
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        matchID = try? c.decodeIfPresent(String.self, forKey: .matchID)
        gameRaw = try? c.decodeIfPresent(String.self, forKey: .gameRaw)
        rubyBalance = try? c.decodeIfPresent(Int.self, forKey: .rubyBalance)
    }

    private struct FailableRoom: Decodable {
        let room: DuelRoom?
        init(from decoder: any Decoder) throws { room = try? DuelRoom(from: decoder) }
    }
}

/// RPC 다섯. 서명은 서버 초안과 같다(p_protocol 은 맨 뒤).
package enum DuelRoomCall: Equatable, Sendable {
    case list(DuelRoomGame)
    case open(DuelRoomGame, stake: Int)
    case close(roomID: String)
    case ping
    case join(roomID: String)

    package var rpcName: String {
        switch self {
        case .list: "duel_rooms_list"
        case .open: "duel_room_open"
        case .close: "duel_room_close"
        case .ping: "duel_room_ping"
        case .join: "duel_room_join"
        }
    }

    package var body: DuelRoomBody {
        switch self {
        case .list(let game): DuelRoomBody(game: game.rawValue)
        case .open(let game, let stake): DuelRoomBody(game: game.rawValue, stake: stake)
        case .close(let id): DuelRoomBody(room: id)
        case .ping: DuelRoomBody()
        case .join(let id): DuelRoomBody(room: id)
        }
    }
}

package struct DuelRoomBody: Encodable, Equatable, Sendable {
    var game: String?
    var stake: Int?
    var room: String?
    var protocolVersion = DuelRoomStore.protocolVersion

    private enum CodingKeys: String, CodingKey {
        case game = "p_game", stake = "p_stake", room = "p_room", protocolVersion = "p_protocol"
    }

    package func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(game, forKey: .game)
        try c.encodeIfPresent(stake, forKey: .stake)
        try c.encodeIfPresent(room, forKey: .room)
        try c.encode(protocolVersion, forKey: .protocolVersion)
    }
}

@MainActor
package protocol DuelRoomServing {
    func call(_ call: DuelRoomCall) async throws -> DuelRoomsResponse
}

/// 사용자 문구(서버 · 테스트 같은 내부 어휘 없음).
package enum DuelRoomText {
    package static let tabRooms = "방"
    package static let tabPeople = "상대 고르기"
    package static let roomsTitle = "기다리는 방"
    package static let create = "방 만들기"
    package static let createTitle = "방 만들기"
    package static let createHint = "판돈을 정해 방을 열어 두면, 누가 들어오는 순간 바로 대결이 시작돼요."
    package static let createButton = "만들기"
    package static let join = "참가"
    package static let notEnough = "루비 부족"
    package static let myRoomTitle = "내 방"
    package static let myRoomHint = "누가 들어오면 바로 시작해요 · 창을 닫아도 방은 30분 남아요"
    package static let closeRoom = "닫기"
    package static let emptyRooms = "기다리는 방이 없어요 · 방을 만들어 두고 일하세요"
    package static let loading = "방을 불러오는 중…"
    package static let stakeLabel = "판돈"
    package static func otherGameRoom(_ game: DuelRoomGame) -> String { "\(game.title) 방을 열어 두었어요" }
    package static func waiting(seconds: Int) -> String {
        if seconds < 60 { return "방금" }
        return "\(seconds / 60)분째 기다림"
    }
    package static func stakeLine(_ stake: Int) -> String { "\(stake) · 이기면 +\(stake)" }

    /// 상태별 안내(열기 · 참가 · 닫기의 실패).
    package static func notice(_ status: DuelRoomStatus, need: Int? = nil) -> String? {
        switch status {
        case .ok: nil
        case .insufficient: need.map { "루비가 모자라요 · 판돈 \($0)" } ?? "루비가 모자라요"
        case .busy: "대결 중에는 방을 열거나 들어갈 수 없어요"
        case .roomGone: "방이 닫혔어요"
        case .ownRoom: "내가 연 방이에요"
        case .focused: "집중 모드를 끄면 들어갈 수 있어요"
        case .updateRequired, .unsupportedGame, .unsupportedClient: "앱을 업데이트하면 방을 쓸 수 있어요"
        case .blackout: "지금은 대결 신청을 받지 않는 시간이에요"
        case .hostBusy: "방장이 다른 신청을 기다리는 중이에요 · 잠시 뒤에 다시"
        case .notFound, .stale: "방이 바뀌었어요 · 다시 불러올게요"
        case .invalid, .unauthorized, .unknown: "잠시 뒤에 다시 해 주세요"
        }
    }
}

@MainActor
@Observable
package final class DuelRoomStore {
    package nonisolated static let protocolVersion = 1
    /// 방장 숨 간격(서버는 75초 안 본 방을 목록에서 뺀다).
    package nonisolated static let pingSeconds: TimeInterval = 20

    package internal(set) var rooms: [DuelRoomGame: [DuelRoom]] = [:]
    package internal(set) var loadedGames: Set<DuelRoomGame> = []
    /// 내 방(열림 · 막 시작). 시작된 방은 방장 기기가 판을 받아 간 뒤에도 잠깐 남는다(서버 30분).
    package internal(set) var myRoom: DuelRoom?
    /// 문(서버 duel_rooms_min_build). nil = 아직 모름. 거짓이면 방 칸을 감춘다.
    package internal(set) var doorOpen: Bool?
    package internal(set) var stakes: [Int] = [3, 5, 10]
    package internal(set) var isBusy = false
    package var notice: String?
    package var selectedStake = 5

    /// 루비 잔액(앱 미러 — WorkTimerStore 가 넣는다). [참가] · 판돈 버튼을 미리 막는 데만 쓴다(서버가 다시 잰다).
    @ObservationIgnored package var rubyBalanceSource: (@MainActor () -> Int?)?
    package var rubyBalance: Int? { rubyBalanceSource?() }

    /// 방장 기기 — 내 방에 사람이 들어와 판이 섰다(방마다 한 번).
    @ObservationIgnored package var onRoomStarted: (@MainActor (DuelRoomGame, String) -> Void)?
    /// 참가자 — 참가 ok(그 게임 판 id).
    @ObservationIgnored package var onJoined: (@MainActor (DuelRoomGame, String) -> Void)?

    @ObservationIgnored private var service: (any DuelRoomServing)?
    @ObservationIgnored let clock: () -> Date
    @ObservationIgnored private var serverOffsetMs: Double = 0
    @ObservationIgnored private var handledStarts: Set<String> = []
    @ObservationIgnored private var pingTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lastSignalPingAt: Date = .distantPast
    @ObservationIgnored private var pingStep: TimeInterval

    package init(service: (any DuelRoomServing)? = nil, clock: @escaping () -> Date = Date.init,
                 pingSeconds: TimeInterval = DuelRoomStore.pingSeconds) {
        self.service = service
        self.clock = clock
        self.pingStep = pingSeconds
    }

    package var isAvailable: Bool { service != nil && doorOpen == true }
    package var serverNowMs: Double { clock().timeIntervalSince1970 * 1000 + serverOffsetMs }

    package func rooms(for game: DuelRoomGame) -> [DuelRoom] { rooms[game] ?? [] }
    package func myOpenRoom(for game: DuelRoomGame) -> DuelRoom? {
        guard let myRoom, myRoom.isOpen, myRoom.game == game else { return nil }
        return myRoom
    }
    /// 다른 게임에 열어 둔 내 방(이 게임 로비에 한 줄로 알린다).
    package func myOpenRoom(otherThan game: DuelRoomGame) -> DuelRoom? {
        guard let myRoom, myRoom.isOpen, let g = myRoom.game, g != game else { return nil }
        return myRoom
    }

    package func waitedSeconds(_ room: DuelRoom) -> Int { max(0, Int((serverNowMs - room.createdMs) / 1000)) }

    // MARK: 부르기

    package func refresh(_ game: DuelRoomGame) async {
        guard let response = await perform(.list(game)) else { return }
        guard response.status == .ok else { return }
        rooms[game] = response.rooms ?? []
        loadedGames.insert(game)
        if let stakes = response.stakes, !stakes.isEmpty { self.stakes = stakes }
        applyMyRoom(response.myRoom, from: response)
    }

    package func open(_ game: DuelRoomGame, stake: Int) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        guard let response = await perform(.open(game, stake: stake)) else { return }
        guard response.status == .ok else {
            notice = DuelRoomText.notice(response.status, need: response.need ?? stake)
            return
        }
        notice = nil
        selectedStake = stake
        applyMyRoom(response.myRoom, from: response)
    }

    package func closeMyRoom() async {
        guard let room = myRoom, room.isOpen, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        guard let response = await perform(.close(roomID: room.id)) else { return }
        if response.status == .ok || response.status == .notFound {
            applyMyRoom(response.myRoom, from: response)
            if let game = room.game { await refresh(game) }
        }
    }

    package func join(_ room: DuelRoom) async {
        guard !isBusy, let game = room.game else { return }
        isBusy = true
        defer { isBusy = false }
        guard let response = await perform(.join(roomID: room.id)) else { return }
        if response.status == .ok, let matchID = response.matchID, !matchID.isEmpty {
            notice = nil
            rooms[game]?.removeAll { $0.id == room.id }
            onJoined?(game, matchID.lowercased())
            return
        }
        notice = DuelRoomText.notice(response.status, need: response.need ?? room.stake)
        if response.status == .roomGone || response.status == .hostBusy { rooms[game]?.removeAll { $0.id == room.id } }
        await refresh(game)
    }

    package func ping() async {
        guard let response = await perform(.ping), response.status == .ok else { return }
        applyMyRoom(response.myRoom, from: response)
    }

    /// 게임 초인종이 왔다 — 내 방이 열려 있으면 바로 숨을 쉰다(방에 사람이 들어온 신호일 수 있다). 1초에 한 번.
    package func handleGameSignal() {
        guard myRoom?.isOpen == true else { return }
        let now = clock()
        guard now.timeIntervalSince(lastSignalPingAt) >= 1 else { return }
        lastSignalPingAt = now
        Task { [weak self] in await self?.ping() }
    }

    package func attach(service: any DuelRoomServing) {
        reset()
        self.service = service
    }

    package func reset() {
        generation &+= 1
        pingTask?.cancel()
        pingTask = nil
        rooms = [:]
        loadedGames = []
        myRoom = nil
        doorOpen = nil
        notice = nil
        isBusy = false
        handledStarts = []
    }

    // MARK: 안쪽

    private func applyMyRoom(_ room: DuelRoom?, from response: DuelRoomsResponse) {
        myRoom = room
        if let room, room.isStarted, let game = room.game, let matchID = room.matchID,
           handledStarts.insert(room.id).inserted {
            onRoomStarted?(game, matchID.lowercased())
        }
        updatePing()
    }

    private func updatePing() {
        let wantsPing = myRoom?.isOpen == true
        if !wantsPing {
            pingTask?.cancel()
            pingTask = nil
            return
        }
        guard pingTask == nil else { return }
        let gen = generation
        let step = pingStep
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(step)) } catch { return }
                guard let self, gen == self.generation else { return }
                guard self.myRoom?.isOpen == true else { self.pingTask = nil; return }
                await self.ping()
            }
        }
    }

    private func perform(_ call: DuelRoomCall) async -> DuelRoomsResponse? {
        guard let service else { return nil }
        let gen = generation
        let sentMs = clock().timeIntervalSince1970 * 1000
        do {
            let response = try await service.call(call)
            guard gen == generation, !Task.isCancelled else { return nil }
            if let now = response.serverNowMs, now.isFinite, now > 0 {
                let recvMs = clock().timeIntervalSince1970 * 1000
                serverOffsetMs = now - (sentMs + recvMs) / 2
            }
            switch response.status {
            case .unsupportedClient:
                doorOpen = false
            case .ok:
                doorOpen = true
            default:
                break
            }
            return response
        } catch {
            guard gen == generation, !(error is CancellationError) else { return nil }
            notice = DuelRoomText.notice(.unknown)
            return nil
        }
    }
}

// MARK: - 실제 서버

@MainActor
private final class DuelRoomLiveService: DuelRoomServing {
    private weak var host: (any GomokuStoreHost)?

    init(host: any GomokuStoreHost) { self.host = host }

    func call(_ call: DuelRoomCall) async throws -> DuelRoomsResponse {
        guard let host, let userID = host.session?.userID else { throw CancellationError() }
        let generation = host.sessionGeneration
        let service = host.service
        let body = call.body
        let response: DuelRoomsResponse = try await host.withSessionRetry { session in
            guard host.sessionGeneration == generation, session.userID == userID else { throw CancellationError() }
            return try await service.duelRPC(call.rpcName, body: body, accessToken: session.accessToken)
        }
        guard host.sessionGeneration == generation, host.session?.userID == userID else { throw CancellationError() }
        return response
    }
}

extension DuelRoomStore {
    package func attach(host: any GomokuStoreHost) {
        attach(service: DuelRoomLiveService(host: host))
    }
}
