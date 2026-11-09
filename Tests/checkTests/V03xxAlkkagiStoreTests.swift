import Foundation
import Testing
@testable import check
@testable import CheckCore

// 1:1 알까기 v2 코어 — 와이어 · 스토어 표면 · 문구 표 · 몸통(SPEC v1.1 §3.7 · §4 · §7.2 C 줄). **모양이 아니라 결과를 잰다.**
//
// 서버는 스텁 `AlkkagiServing`(호출을 기록하고 정해 둔 응답을 돌려준다 — host 가 없어 네트워크 0). 응답 JSON 은 SPEC §3.7 모양을 손으로 적은
// 픽스처다(T/Fixtures/alkkagi-rpc) — S 하네스 원문이 오면 통합(T)이 같은 이름으로 바꿔 끼우고 계약 시험(V03xxAlkkagiFixtureContractTests)이
// 원문으로 다시 잰다. 각 시험 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가"이고, 단언마다 결함 변이에서 갈리는 기준선 짝을 둔다.
// 다섯 규칙(§4.3)은 규칙마다 '기준선(창 닫힘) · 결함 자리(보임+가림) · 대조(보임+안 가림)' 또는 '합쳐짐 · 없음' 짝으로 잰다.
// 맨 끝 묶음은 0.3.80 독립 실행기 온라인 시험 23개를 v2 이름으로 옮긴 판 진행 보존 그물이다(§4.6).

// MARK: - 시험대

@MainActor
private final class AKStubService: AlkkagiServing {
    var calls: [AlkkagiCall] = []
    var handler: (AlkkagiCall) throws -> AlkkagiResponse

    init(_ handler: @escaping (AlkkagiCall) throws -> AlkkagiResponse) { self.handler = handler }

    func call(_ call: AlkkagiCall) async throws -> AlkkagiResponse {
        calls.append(call)
        return try handler(call)
    }
}

private let akNow: Double = 1_800_000_000_000
private let akMe = "00000000-0000-4000-8000-000000000001"
private let akMinsu = "00000000-0000-4000-8000-000000000002"
private let akJiwoo = "00000000-0000-4000-8000-000000000003"
private let akMatch = "00000000-0000-4000-8000-0000000000aa"

private func akDecode(_ object: [String: Any], snake: Bool = false) throws -> AlkkagiResponse {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    let decoder = JSONDecoder()
    if snake { decoder.keyDecodingStrategy = .convertFromSnakeCase }
    return try decoder.decode(AlkkagiResponse.self, from: data)
}

private func akPeer(_ id: String, _ name: String) -> [String: Any] {
    ["id": id, "display_name": name, "avatar_url": NSNull(), "character_id": "aing", "busy": false]
}

private func akUser(_ id: String, _ name: String, working: Bool = false, inMatch: Bool = false,
                    capable: Bool = true, focus: Bool = false) -> [String: Any] {
    ["id": id, "display_name": name, "avatar_url": NSNull(), "character_id": "aing",
     "is_working": working, "in_match": inMatch, "capable": capable, "focus_mode": focus]
}

/// SPEC §3.7 LOBBY(전체 로비). `light` 면 가벼운 로비(users [] · record null · matches []).
private func akLobby(light: Bool = false, doorOpen: Bool = true, ruby: Int = 100,
                     protocolVersion: Int = 2, users: [[String: Any]]? = nil) -> [String: Any] {
    [
        "status": "ok", "protocol": protocolVersion, "server_now_ms": akNow,
        "me": akPeer(akMe, "나"), "state": NSNull(),
        "incoming": [["id": akMatch, "opponent": akPeer(akMinsu, "민수"), "stake": 5, "expires_at_ms": akNow + 60_000]],
        "outgoing": NSNull(), "ruby_balance": ruby, "stakes": [3, 5, 10], "door_open": doorOpen,
        "record": light ? NSNull() : ["wins": 3, "losses": 1, "draws": 2] as [String: Any],
        "users": light ? [] : (users ?? [akUser(akMinsu, "민수", working: true), akUser(akJiwoo, "지우", inMatch: true)]),
        "matches": light ? [] : [["id": "00000000-0000-4000-8000-0000000000bb", "black": akPeer(akJiwoo, "지우"),
                                  "white": akPeer(akMinsu, "민수"), "stake": 10, "shot_count": 4, "watchers": 2,
                                  "accepted_at_ms": akNow - 90_000]],
    ]
}

private func akStone(_ id: Int, _ owner: String, _ x: Double, _ y: Double) -> [String: Any] {
    ["id": id, "owner": owner, "position": ["x": x, "y": y], "velocity": ["x": 0, "y": 0], "is_out": false, "is_placed": true]
}

/// SPEC §3.7 STATE(28키 — v1 19키 + v2 덧붙임). 조준 · 흑 차례 · 나는 흑.
private func akState(phase: String = "aiming", result: Any = NSNull(), reason: Any = NSNull(),
                     myColor: String = "black", stake: Any = 5, myMissed: Int = 0, watchers: Int = 2) -> [String: Any] {
    let stones = (0..<5).map { akStone($0, "black", -0.4 + Double($0) * 0.2, 0.6) }
        + (5..<10).map { akStone($0, "white", -0.4 + Double($0 - 5) * 0.2, -0.6) }
    return [
        "id": akMatch, "revision": 7, "phase": phase, "current_player": "black", "my_color": myColor,
        "black": akPeer(akMe, "나"), "white": akPeer(akMinsu, "민수"), "stones": stones,
        "deadline_ms": akNow + 30_000, "shot_count": 3, "result": result, "finish_reason": reason, "shot": NSNull(),
        "chat_seq": 0, "chat": [], "muted": false, "placement_revision": 1, "my_ready": true, "opponent_ready": true,
        "stake": stake, "accepted_at_ms": akNow - 60_000, "my_missed_turns": myMissed, "opponent_missed_turns": 0,
        "forfeit_after": 3, "settled": phase == "finished", "ruby_balance": 95, "watchers": watchers, "grace_ms": 2000,
    ]
}

// MARK: - 시험대 둘째 벌(몸통 — 멈춤 · 경로별 대기열 · 시계 · 루비 미러 호스트)

/// 대본 서버. 전역 대기열(멈춤 포함) → RPC 별 대기열(마지막 하나는 남는다) → 대체 응답 순서로 답한다.
/// 판 규칙을 흉내 내지 않는다 — 정해 둔 응답만 돌려준다. 멈춘 요청은 취소돼도 늦게 답할 수 있다(실제 네트워크처럼).
@MainActor
final class AKScript: AlkkagiServing {
    enum Reply {
        case response(AlkkagiResponse)
        case failure(AlkkagiServiceError)
        case suspended
    }

    private var queue: [Reply]
    private var routes: [String: [AlkkagiResponse]] = [:]
    var fallback: ((AlkkagiCall) -> AlkkagiResponse?)?
    private var continuations: [Int: CheckedContinuation<AlkkagiResponse, any Error>] = [:]
    private var activeCalls = 0
    private(set) var calls: [AlkkagiCall] = []
    private(set) var maxConcurrentCalls = 0
    private(set) var cancelledRequests: Set<Int> = []

    init(_ queue: [Reply] = [], fallback: ((AlkkagiCall) -> AlkkagiResponse?)? = nil) {
        self.queue = queue
        self.fallback = fallback
    }

    func enqueue(_ reply: Reply) { queue.append(reply) }
    func route(_ rpc: String, _ responses: AlkkagiResponse...) { routes[rpc, default: []].append(contentsOf: responses) }
    func isSuspended(_ index: Int) -> Bool { continuations[index] != nil }
    func count(_ rpc: String) -> Int { calls.filter { $0.rpcName == rpc }.count }
    var lobbyCalls: [Bool] { calls.compactMap { if case let .lobby(users) = $0 { users } else { nil } } }

    func call(_ call: AlkkagiCall) async throws -> AlkkagiResponse {
        let index = calls.count
        calls.append(call)
        activeCalls += 1
        maxConcurrentCalls = max(maxConcurrentCalls, activeCalls)
        defer { activeCalls -= 1 }
        let reply: Reply
        if !queue.isEmpty {
            reply = queue.removeFirst()
        } else if var list = routes[call.rpcName], let first = list.first {
            if list.count > 1 { list.removeFirst(); routes[call.rpcName] = list }
            reply = .response(first)
        } else if let made = fallback?(call) {
            reply = .response(made)
        } else {
            Issue.record("대본에 없는 요청 \(index): \(call)")
            throw AlkkagiServiceError.invalidResponse
        }
        switch reply {
        case let .response(response): return response
        case let .failure(error): throw error
        case .suspended:
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuations[index] = $0 }
            } onCancel: {
                Task { @MainActor in self.cancelledRequests.insert(index) }
            }
        }
    }

    func resume(_ index: Int, returning response: AlkkagiResponse) {
        guard let continuation = continuations.removeValue(forKey: index) else {
            Issue.record("요청 \(index) 는 멈춰 있지 않다")
            return
        }
        continuation.resume(returning: response)
    }

    func finish() {
        let pending = Array(continuations.values)
        continuations.removeAll()
        for continuation in pending { continuation.resume(throwing: CancellationError()) }
    }
}

@MainActor
final class AKClock {
    var milliseconds: Double
    var date: Date { Date(timeIntervalSince1970: milliseconds / 1000) }
    init(milliseconds: Double = AK.nowMs) { self.milliseconds = milliseconds }
    func advance(_ seconds: Double) { milliseconds += seconds * 1000 }
}

/// 루비 미러만 보는 호스트(서비스는 쓰지 않는다 — 스토어는 스텁 `AlkkagiServing` 으로 부른다). 스토어는 약참조로 든다.
@MainActor
final class AKHost: GomokuStoreHost {
    var session: SupabaseSession? = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: AK.blackID)
    var sessionGeneration = 0
    let service: SupabaseWorkService
    var realtimeState: RealtimeState = .idle(.disabled)
    var rubyBalance: Int?

    /// `hostName` 은 `GomokuStubProtocol` 이 응답을 고르는 열쇠(시험마다 다르게 — 운영 주소에 닿지 않는다).
    init(hostName: String = "alkkagi-v2-host.invalid") {
        service = SupabaseWorkService(projectURL: URL(string: "http://\(hostName)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    }

    func withSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T {
        guard let session else { throw AlkkagiServiceError.unavailable }
        return try await operation(session)
    }

    func classifyAuthError(_ error: Error) -> AuthErrorDisposition { .transient }
}

/// 스위프트로 세우는 판 · 응답(돌은 판 진행 타입 그대로 — 0.3.80 독립 실행기 픽스처 꼴에 v2 칸을 더했다).
@MainActor
enum AK {
    static let nowMs: Double = 1_000_000
    static let blackID = "00000000-0000-4000-8000-000000000001"
    static let whiteID = "00000000-0000-4000-8000-000000000002"
    static let thirdID = "00000000-0000-4000-8000-000000000003"
    static let matchID = UUID(uuidString: "00000000-0000-4000-8000-000000000010")!
    static let nextMatchID = UUID(uuidString: "00000000-0000-4000-8000-000000000011")!
    static let inviteID = UUID(uuidString: "00000000-0000-4000-8000-000000000020")!
    static let black = AlkkagiPeer(id: blackID, displayName: "Black")
    static let white = AlkkagiPeer(id: whiteID, displayName: "White")

    static func vector(_ x: Double, _ y: Double) -> AlkkagiVector { AlkkagiVector(x: x, y: y) }

    static func match(myColor: AlkkagiGame.Player = .black, phase: AlkkagiMatchPhase = .aiming,
                      current: AlkkagiGame.Player = .black, revision: Int = 7, id: UUID = matchID,
                      stake: Int? = 5, shotCount: Int = 0, deadlineMs: Double? = nowMs + 30_000,
                      graceMs: Double? = nil, watchers: Int? = nil, ruby: Int? = nil,
                      result: AlkkagiMatchResult? = nil, reason: String? = nil) -> AlkkagiMatch {
        var stones = AlkkagiGame().stones
        if phase != .placing {
            for index in stones.indices { stones[index].isPlaced = true }
        }
        if phase == .placing { stones.removeAll { $0.owner != myColor } }
        var finishedResult = result
        if phase == .finished, finishedResult == nil { finishedResult = .black }
        return AlkkagiMatch(id: id.uuidString.lowercased(), revision: revision, phase: phase,
                            currentPlayer: current, myColor: myColor, black: black, white: white, stones: stones,
                            deadlineMs: phase == .finished ? nil : deadlineMs, shotCount: shotCount,
                            result: finishedResult, finishReason: phase == .finished ? (reason ?? "ring_out") : reason,
                            stake: stake, myMissedTurns: 0, opponentMissedTurns: 0, forfeitAfter: 3,
                            settled: phase == .finished, rubyBalance: ruby, watchers: watchers, graceMs: graceMs)
    }

    /// 쏜 돌이 `stoneID` 인 쏘기 기록(초기 돌 = 지금 판 돌).
    static func shot(by stoneID: Int, on match: AlkkagiMatch) -> AlkkagiShot {
        AlkkagiShot(id: "shot-\(stoneID)-\(match.revision)", stoneID: stoneID, pull: vector(0, 80),
                    startedAtMs: nowMs, steps: 2_400, initialStones: match.stones)
    }

    static func invite(id: UUID = inviteID, from peer: AlkkagiPeer = white, stake: Int = 5,
                       expiresAtMs: Double = nowMs + 60_000) -> AlkkagiInvite {
        AlkkagiInvite(id: id.uuidString.lowercased(), opponent: peer, expiresAtMs: expiresAtMs, stake: stake)
    }

    static func user(_ id: String, _ name: String, working: Bool = true) -> AlkkagiLobbyUser {
        AlkkagiLobbyUser(id: id, displayName: name, isWorking: working)
    }

    /// 봉투 하나. `state` 가 있으면 `me` 는 그 판의 내 색 사람.
    static func response(_ state: AlkkagiMatch? = nil, status: AlkkagiRPCStatus = .ok, serverNowMs: Double = nowMs,
                         incoming: [AlkkagiInvite]? = nil, outgoing: AlkkagiInvite? = nil,
                         users: [AlkkagiLobbyUser]? = nil, record: AlkkagiRecord? = nil, ruby: Int? = nil,
                         doorOpen: Bool? = nil, need: Int? = nil, have: Int? = nil, side: String? = nil) -> AlkkagiResponse {
        let me = state.map { $0.myColor == .black ? black : white } ?? black
        return AlkkagiResponse(status: status, serverNowMs: serverNowMs, me: me, users: users, incoming: incoming,
                               outgoing: outgoing, state: state, rubyBalance: ruby, doorOpen: doorOpen, record: record,
                               need: need, have: have, side: side)
    }

    /// 전체 로비(사람 · 전적 · 문 열림).
    static func lobby(users: [AlkkagiLobbyUser] = [user(whiteID, "White")], incoming: [AlkkagiInvite] = [],
                      outgoing: AlkkagiInvite? = nil, ruby: Int = 100, serverNowMs: Double = nowMs,
                      state: AlkkagiMatch? = nil) -> AlkkagiResponse {
        AlkkagiResponse(status: .ok, serverNowMs: serverNowMs, me: black, users: users, incoming: incoming,
                        outgoing: outgoing, state: state, rubyBalance: ruby, stakes: [3, 5, 10], doorOpen: true,
                        record: AlkkagiRecord(wins: 1, losses: 0, draws: 0), matches: [])
    }

    static func store(_ script: AKScript, clock: AKClock = AKClock(), pollSeconds: Double = 3_600) -> AlkkagiOnlineStore {
        let store = AlkkagiOnlineStore(service: script, clock: { clock.date }, pollSeconds: pollSeconds)
        store.outsidePollStepSeconds = 3_600
        return store
    }
}

/// 비동기 상태가 올 때까지(상한) 기다린다 — 안 오면 빨강.
@MainActor
func akEventually(timeout: Duration = .milliseconds(800), _ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !predicate(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(1))
    }
    try #require(predicate(), "기다린 상태가 \(timeout) 안에 오지 않았다")
}

/// 손 픽스처(T/Fixtures/alkkagi-rpc — S 원문이 오면 같은 이름으로 바뀐다)를 운영 디코더(snake 접기)로 읽는다.
func akFixture(_ name: String) throws -> AlkkagiResponse {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/alkkagi-rpc/\(name).json")
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(AlkkagiResponse.self, from: Data(contentsOf: url))
}

// MARK: - 시험

@MainActor
@Suite(.serialized)
struct V03xxAlkkagiStoreTests {
    // MARK: 와이어

    /// 없으면: 앱이 계속 protocol 1 로 부르거나 판돈을 싣지 않아도 초록이다(서버 v2 는 둘 다 `unsupported_client` · `invalid`).
    @Test
    func requestBodiesCarryProtocolTwoAndTheStake() throws {
        let opponent = try #require(UUID(uuidString: akMinsu))
        func keys(_ call: AlkkagiCall) throws -> [String: Any] {
            let data = try JSONEncoder().encode(call.parameters)
            return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let challenge = try keys(.challenge(opponentID: opponent, stake: 5, actionID: UUID()))
        #expect(challenge["p_protocol"] as? Int == 2)
        #expect(challenge["p_stake"] as? Int == 5)
        #expect(Set(challenge.keys) == ["p_protocol", "p_opponent", "p_action_id", "p_stake"])
        // 기준선: 로비 · 순위 본문에는 판돈이 없다(키가 새면 서버 이름 인자 호출이 PGRST202).
        #expect(Set(try keys(.lobby(users: false)).keys) == ["p_protocol", "p_users"])
        #expect(Set(try keys(.ranking).keys) == ["p_protocol"])
        #expect(Set(try keys(.watchLive(matchID: opponent)).keys) == ["p_protocol", "p_match_id"])

        // RPC 15 — 새 셋이 이름표에 있다.
        #expect(AlkkagiOnlineWire.RPC.all.count == 15 && Set(AlkkagiOnlineWire.RPC.all).count == 15)
        #expect(AlkkagiCall.ranking.rpcName == "alkkagi_ranking")
        #expect(AlkkagiCall.watch(matchID: nil).rpcName == "alkkagi_watch")
        #expect(AlkkagiCall.watchLive(matchID: nil).rpcName == "alkkagi_watch_live")
        // 서버 어휘 넷이 열거로 산다 · 모르는 값은 unknown(기준선).
        for raw in ["blackout", "target_focused", "target_outdated", "insufficient"] {
            #expect(AlkkagiRPCStatus(rawValue: raw) != nil, "\(raw) 가 열거에 없다")
        }
        #expect(AlkkagiRPCStatus(rawValue: "muted") == nil, "서버가 안 내는 muted 가 남았다")
    }

    /// 없으면: v2 로비 키(사람 상태 · 전적 · 대결 중 · 문 · 잔액)를 디코더가 버려도 초록이다 — 두 디코더(원문 · snake 접기) 모두.
    @Test(arguments: [false, true])
    func lobbyV2KeysSurviveDecoding(snake: Bool) throws {
        let full = try akDecode(akLobby(), snake: snake)
        #expect(full.protocolVersion == 2 && full.doorOpen == true && full.rubyBalance == 100 && full.stakes == [3, 5, 10])
        #expect(full.record == AlkkagiRecord(wins: 3, losses: 1, draws: 2))
        let users = try #require(full.users)
        #expect(users.map(\.displayName) == ["민수", "지우"])
        #expect(users[0].isWorking && users[0].canBeChallenged)
        #expect(users[1].inMatch && !users[1].canBeChallenged)
        #expect(full.incoming?.first?.stake == 5)
        let live = try #require(full.matches?.first)
        #expect(live.stake == 10 && live.watchers == 2 && live.shotCount == 4 && live.acceptedAt != nil)
        // 기준선: 가벼운 로비는 record 가 nil(0 이 아니다) · 사람 0.
        let light = try akDecode(akLobby(light: true), snake: snake)
        #expect(light.record == nil && light.users?.isEmpty == true && light.matches?.isEmpty == true)
    }

    /// 없으면: WATCH(내 색 없음)를 STATE 로 읽다 디코딩이 통째 실패하거나, RANKING 의 `me`(순위 줄)를 PEER 로 읽어 실패해도 초록이다.
    /// 돌(`AlkkagiGame.Stone`)은 판 진행 타입이라(§4.6 경계) 운영 디코더(snake 접기)로만 읽힌다 — 판이 실린 응답은 그 디코더로 잰다.
    @Test(arguments: [false, true])
    func oneEnvelopeRoutesStateWatchAndRanking(snake rankingSnake: Bool) throws {
        let snake = true
        let mine = try akDecode(["status": "ok", "protocol": 2, "server_now_ms": akNow, "state": akState()], snake: snake)
        let state = try #require(mine.state)
        #expect(mine.watch == nil)
        #expect(state.stake == 5 && state.watchers == 2 && state.graceMs == 2000 && state.forfeitAfter == 3)
        #expect(state.rubyBalance == 95 && state.myMissedTurns == 0 && state.settled == false)

        var watch = akState()
        for key in ["my_color", "chat_seq", "chat", "muted", "placement_revision", "my_ready", "opponent_ready",
                    "my_missed_turns", "opponent_missed_turns", "ruby_balance", "grace_ms", "settled", "accepted_at_ms"] {
            watch.removeValue(forKey: key)
        }
        watch["black_ready"] = true
        watch["white_ready"] = false
        watch["stones"] = []
        watch["black_missed_turns"] = 1
        watch["white_missed_turns"] = 0
        watch["finished_at_ms"] = NSNull()
        let watched = try akDecode(["status": "ok", "protocol": 2, "server_now_ms": akNow, "state": watch], snake: snake)
        let spectated = try #require(watched.watch)
        #expect(watched.state == nil)
        #expect(spectated.stones.isEmpty && spectated.blackReady && !spectated.whiteReady && spectated.watchers == 2)
        #expect(spectated.blackMissedTurns == 1 && spectated.stake == 5)

        let ranking = try akDecode([
            "status": "ok", "server_now_ms": akNow, "record_since_ms": NSNull(),
            "me": ["rank": NSNull(), "wins": 0, "losses": 0, "draws": 0, "points": 0],
            "rows": [["rank": 1, "id": akMinsu.uppercased(), "display_name": "민수", "avatar_url": NSNull(),
                      "character_id": "aing", "wins": 4, "losses": 1, "draws": 0, "points": 3],
                     ["rank": 2, "display_name": "id 없는 줄"]],
        ], snake: rankingSnake)
        let board = try #require(ranking.ranking)
        #expect(ranking.me == nil, "순위 me 가 PEER 자리로 샜다")
        #expect(board.entries.map(\.id) == [akMinsu], "깨진 줄을 버리지 않았거나 id 를 소문자로 접지 않았다")
        #expect(board.entries.first?.points == 3 && board.me?.rank == nil && board.recordSince == nil)
        // 기준선: 로비는 순위가 아니다.
        #expect(try akDecode(akLobby(), snake: rankingSnake).ranking == nil)
    }

    // MARK: 스토어

    /// 없으면(VC-8): 서버 옛판 · 함수 없음 · 문 닫힘이 모두 "업데이트"로 보여도, 또는 그 반대여도 초록이다 — 여섯 갈래 접기.
    @Test
    func availabilityFoldsSixWays() async throws {
        func fold(_ make: @escaping () throws -> AlkkagiResponse) async -> AlkkagiAvailability {
            let store = AlkkagiOnlineStore(service: AKStubService { _ in try make() })
            await store.refreshLobby()
            return store.availability
        }
        #expect(await fold { try akDecode(akLobby(protocolVersion: 1)) } == .serverMissing)          // ① 서버 옛판
        #expect(await fold { throw AlkkagiServiceError.serverMissing } == .serverMissing)            // ② PGRST202
        #expect(await fold { try akDecode(akLobby(doorOpen: false)) } == .serverMissing)            // ③ 문 닫힘
        #expect(await fold { AlkkagiResponse(status: .unsupportedClient, serverNowMs: akNow, doorOpen: false) }
                == .serverMissing)                                                                   // ④
        #expect(await fold { AlkkagiResponse(status: .unsupportedClient, serverNowMs: akNow, doorOpen: true) }
                == .updateRequired)                                                                  // ⑤ 내 build 모자람
        #expect(await fold { try akDecode(akLobby()) } == .available)                               // ⑥
    }

    /// 없으면: 팝오버의 가벼운 로비(users [] · record null)가 창 로비의 사람 · 전적 · 대결 중을 지워도 초록이다.
    @Test
    func lightLobbyDoesNotOverwriteUsersRecordOrLiveMatches() async throws {
        var light = false
        var emptyFull = false
        let store = AlkkagiOnlineStore(service: AKStubService { call in
            if case .lobby(false) = call { return try akDecode(akLobby(light: true)) }
            #expect(!light, "가벼운 로비를 부르려 했는데 전체 로비가 나갔다")
            return try akDecode(akLobby(users: emptyFull ? [] : nil))
        })
        await store.refreshLobby()
        #expect(store.users.count == 2 && store.record != nil && store.liveMatches.count == 1 && store.hasLoadedLobby)
        #expect(store.rubyBalance == 100)

        light = true
        store.handleSignal()                       // 창이 안 보이면 신호는 가벼운 로비(p_users false)를 부른다
        await store.refreshMatch()
        #expect(store.users.count == 2, "가벼운 로비가 사람 목록을 지웠다")
        #expect(store.record == AlkkagiRecord(wins: 3, losses: 1, draws: 2), "가벼운 로비가 전적을 지웠다")
        #expect(store.liveMatches.count == 1)

        // 기준선: **전체** 로비가 빈 사람을 주면 지운다(덮지 않는 규칙이 가벼운 로비에만 걸린다).
        light = false
        emptyFull = true
        await store.refreshLobby()
        #expect(store.users.isEmpty)
    }

    /// 없으면(VC-5): 정산 뒤 늦게 닿은 옛 응답(서버 시각이 앞섬)이 잔액을 되감아도 초록이다.
    @Test
    func lateRubyResponsesDoNotRewindTheBalance() {
        let store = AlkkagiOnlineStore()
        store.applyRuby(105, serverNowMs: 2_000)
        store.applyRuby(95, serverNowMs: 1_000)
        #expect(store.rubyBalance == 105, "먼저 만든 응답의 95 가 105 를 되감았다")
        // 기준선: 서버 시각이 없는 응답은 그대로 옮긴다 · 더 늦은 응답도 옮긴다.
        store.applyRuby(90, serverNowMs: 3_000)
        #expect(store.rubyBalance == 90)
        store.applyRuby(80, serverNowMs: nil)
        #expect(store.rubyBalance == 80)
    }

    /// 없으면: 결과 카드의 승패 · 루비 줄이 내 색을 안 보고 서버 result 만 읽어도(흑이 이기면 늘 승) 초록이다.
    @Test
    func outcomeAndRubyDeltaAreFromMyPointOfView() throws {
        func scene(result: String, reason: String, myColor: String, stake: Any = 5) throws -> AlkkagiOnlineStore {
            let store = AlkkagiOnlineStore()
            store.state = try #require(try akDecode(["status": "ok", "protocol": 2, "server_now_ms": akNow,
                                                     "state": akState(phase: "finished", result: result, reason: reason,
                                                                      myColor: myColor, stake: stake)], snake: true).state)
            return store
        }
        let win = try scene(result: "black", reason: "ring_out", myColor: "black")
        #expect(win.outcome == .win && win.rubyDelta == DuelFee.winnerNet(stake: 5) && win.endReason == .ringOut)
        let loss = try scene(result: "black", reason: "ring_out", myColor: "white")
        #expect(loss.outcome == .loss && loss.rubyDelta == -5)                     // 기준선: 같은 판, 색만 다름
        let voided = try scene(result: "draw", reason: "void", myColor: "white")
        #expect(voided.outcome == .draw && voided.rubyDelta == 0 && voided.endReason == .void)
        let legacy = try scene(result: "white", reason: "timeout", myColor: "white", stake: NSNull())
        #expect(legacy.outcome == .win && legacy.rubyDelta == nil, "옛 판(판돈 없음)에 루비 줄이 섰다")
        #expect(try scene(result: "black", reason: "rollback", myColor: "black").endReason == .unknown)
        // 진행 판은 결과가 없다 · 관전자 수 칩은 STATE watchers 를 따른다(판이 없으면 0, VC-6).
        let live = AlkkagiOnlineStore()
        #expect(live.spectatorCount == 0)
        live.state = try #require(try akDecode(["status": "ok", "protocol": 2, "server_now_ms": akNow,
                                                "state": akState(myMissed: 1, watchers: 2)], snake: true).state)
        #expect(live.outcome == nil && live.rubyDelta == nil && live.spectatorCount == 2 && live.defersMegaphoneBanner)
        #expect(live.missedTurnWarning?.mine == 1 && live.missedTurnWarning?.forfeitAfter == 3)
        live.state = nil
        #expect(live.spectatorCount == 0 && !live.defersMegaphoneBanner && live.missedTurnWarning == nil)
    }

    /// 없으면: 로비 순서가 서버 순서 그대로이거나, 차단한 사람 · 지금 내 판과 같은 신청이 목록 · 배너에 남아도 초록이다.
    @Test
    func visibleListsSortAndFilter() throws {
        let store = AlkkagiOnlineStore()
        store.users = [
            AlkkagiLobbyUser(id: "e", displayName: "구버전", isCapable: false),
            AlkkagiLobbyUser(id: "d", displayName: "대결중", inMatch: true),
            AlkkagiLobbyUser(id: "c", displayName: "하늘", isWorking: false),
            AlkkagiLobbyUser(id: "b", displayName: "가람", isWorking: false),
            AlkkagiLobbyUser(id: "a", displayName: "근무", isWorking: true),
            AlkkagiLobbyUser(id: "f", displayName: "집중", isWorking: true, isFocused: true),
        ]
        #expect(store.visibleUsers.map(\.id) == ["a", "b", "c", "d", "e", "f"])
        store.hiddenPeerIDs = ["B"]                                        // 대소문자 무시
        #expect(store.visibleUsers.map(\.id) == ["a", "c", "d", "e", "f"])

        let peer = AlkkagiPeer(id: "x", displayName: "엑스")
        store.incoming = [AlkkagiInvite(id: akMatch.uppercased(), opponent: peer, expiresAtMs: akNow + 60_000, stake: 5),
                          AlkkagiInvite(id: "other", opponent: peer, expiresAtMs: akNow + 60_000, stake: 3)]
        #expect(store.visibleIncoming?.stake == 5)                          // 기준선: 판이 없으면 첫 신청
        store.state = try #require(try akDecode(["status": "ok", "protocol": 2, "server_now_ms": akNow,
                                                 "state": akState()], snake: true).state)
        #expect(store.visibleIncomingInvites.map(\.id) == ["other"], "지금 내 판과 같은 신청이 남았다")
    }

    /// 없으면(VC-17): 문구가 길건너 출처에서 갈라져도 초록이다 — 공유 status 는 게임 이름만 다르고, 다른 곳은 SPEC §4.4 표가 정한 곳뿐.
    @Test
    func noticeTextIsCrossyTextWithTheGameNameSwapped() {
        func crossy(_ s: AlkkagiRPCStatus) -> CrossyDuelRPCStatus? { CrossyDuelRPCStatus(rawValue: s.rawValue) }
        func swap(_ text: String?) -> String? { text?.replacingOccurrences(of: "1:1 알까기", with: "1:1 길건너") }
        let all: [AlkkagiRPCStatus] = [.ok, .stale, .invalid, .busy, .expired, .forbidden, .blackout, .insufficient,
                                       .notSignedIn, .unsupportedClient, .notFound, .notPending, .notActive,
                                       .alreadyPending, .targetBusy, .targetFocused, .targetOutdated, .rateLimited, .unknown]
        // SPEC §4.4 표가 길건너와 다르게 정한 곳(알까기만 있는 forbidden · rate_limited 는 길건너에 없어 비교하지 않는다).
        let cancelOwn: Set<AlkkagiRPCStatus> = [.stale]
        let respondOwn: Set<AlkkagiRPCStatus> = [.targetOutdated]
        var compared = 0
        for status in all {
            guard let other = crossy(status) else { continue }
            compared += 1
            #expect(swap(AlkkagiNoticeText.challenge(status, need: 5, have: 2)) == CrossyDuelNoticeText.challenge(other, need: 5, have: 2),
                    "challenge \(status.rawValue)")
            if !cancelOwn.contains(status) {
                #expect(swap(AlkkagiNoticeText.cancel(status)) == CrossyDuelNoticeText.cancel(other), "cancel \(status.rawValue)")
            }
            for accept in [true, false] where !respondOwn.contains(status) {
                #expect(swap(AlkkagiNoticeText.respond(accept: accept, status, side: "challenger"))
                        == CrossyDuelNoticeText.respond(accept: accept, other, side: "challenger"), "respond \(status.rawValue)")
            }
            #expect(swap(AlkkagiNoticeText.resign(status)) == CrossyDuelNoticeText.resign(other), "resign \(status.rawValue)")
        }
        #expect(compared == 17)
        // 표가 정한 차이 — 기준선 짝(길건너 글자와 갈린다).
        #expect(AlkkagiNoticeText.cancel(.stale) == AlkkagiNoticeText.finishedInvite)
        #expect(CrossyDuelNoticeText.cancel(.stale) == CrossyDuelNoticeText.tryAgain)
        #expect(AlkkagiNoticeText.respond(accept: true, .targetOutdated) == "상대 앱이 1:1 알까기를 아직 몰라요")
        #expect(AlkkagiNoticeText.cancel(.forbidden) == AlkkagiNoticeText.finishedInvite)
        #expect(AlkkagiNoticeText.respond(accept: true, .forbidden) == "받을 수 없는 신청이에요")
        #expect(AlkkagiNoticeText.move(.forbidden) == "상대 차례예요" && AlkkagiNoticeText.move(.stale) == nil)
        // 문 닫힘이면 '곧 열려요', 열렸는데 내 build 가 모자라면 '업데이트'(VC-8).
        #expect(AlkkagiNoticeText.challenge(.unsupportedClient, doorOpen: false) == "1:1 알까기는 곧 열려요")
        #expect(AlkkagiNoticeText.challenge(.unsupportedClient, doorOpen: true) == AlkkagiNoticeText.updateMine)
        // 끝 사유 · 놓친 차례(§4.4).
        #expect(AlkkagiNoticeText.endReason(.ringOut, outcome: .draw) == "마지막 돌이 함께 나가 무승부예요")
        #expect(AlkkagiNoticeText.endReason(.timeout, outcome: .loss) == "차례를 세 번 넘겨 졌어요")
        #expect(AlkkagiNoticeText.missedTurn(mine: 1, forfeitAfter: 3) == "시간이 지나 차례가 넘어갔어요 · 두 번 더 넘기면 져요")
        #expect(AlkkagiNoticeText.missedTurn(mine: 2, forfeitAfter: 3) == "시간이 지나 차례가 넘어갔어요 · 한 번 더 넘기면 져요")
        #expect(AlkkagiNoticeText.missedTurn(mine: 0, forfeitAfter: 3) == nil)
        // 화면 낱말: '대전'·'초대'·'참가비'·'💎' 0.
        let words = [AlkkagiNoticeText.gameName, AlkkagiNoticeText.updateMine, AlkkagiNoticeText.unavailable,
                     AlkkagiNoticeText.finishedMatch, AlkkagiNoticeText.resignWarning]
            + all.map { AlkkagiNoticeText.challenge($0) } + all.compactMap { AlkkagiNoticeText.respond(accept: false, $0) }
        for banned in ["대전", "초대", "참가비", "💎"] {
            #expect(!words.contains { $0.contains(banned) }, "'\(banned)' 이 문구에 있다")
        }
    }
}

// MARK: - 몸통: 다섯 규칙(§4.3 — 메모리 duel-store-alert-doorbell-rules)

extension V03xxAlkkagiStoreTests {
    /// 없으면: 로비 창을 띄운 채 다른 전체 화면 앱에 있는 사람(보임+가림)이 판 시작 · 받은 신청을 못 알아채 준비 30초를 놓쳐도 초록이다.
    /// 셋 짝 — 창 닫힘(기준선) 1 · 보임+가림(결함 자리) 1 · 보임+안 가림(대조) 0. 창 띄우기는 셋 다 판 id 마다 한 번.
    @Test("규칙 ① 말풍선 문 = 안 보임 또는 가림 — 판 시작 · 받은 신청 모두")
    func rule1AttentionDoor() async throws {
        func door(visible: Bool, occluded: Bool) async -> [Int] {
            let script = AKScript([.response(AK.response(incoming: [AK.invite()])),
                                   .response(AK.response(AK.match(phase: .placing))),
                                   .response(AK.response(AK.match(phase: .placing, revision: 8)))],
                                  fallback: { _ in AK.response() })
            let store = AK.store(script)
            defer { store.reset(); script.finish() }
            store.isWindowVisible = visible
            store.isWindowOccluded = occluded
            var arrivals = 0, starts = 0, presents = 0
            store.onInviteArrived = { _ in arrivals += 1 }
            store.onAttention = { if $0.kind == .matchStarted { starts += 1 } }
            store.presentWindow = { presents += 1 }
            await store.refreshLobby()          // 받은 신청
            await store.refreshLobby()          // 판이 섰다
            await store.refreshLobby()          // 같은 판 다음 revision — 또 울지 않는다
            return [arrivals, starts, presents]
        }
        #expect(await door(visible: false, occluded: false) == [1, 1, 1])
        #expect(await door(visible: true, occluded: true) == [1, 1, 1], "가려진 창이 말풍선을 막았다")
        #expect(await door(visible: true, occluded: false) == [0, 0, 1], "보이는 창 위에 말풍선이 겹쳤다")
    }

    /// 없으면: 판 시작의 `presentWindow`(= windowDidShow) 가 가린 창을 '보임'으로 되돌려 말풍선 문이 닫혀도, 또는 숨었던 창의
    /// 옛 가림 기록이 남아 다시 띄운 창이 폴링을 안 해도 초록이다.
    @Test("규칙 ② windowDidShow 는 열린 채 가려진 창의 가림 기록을 안 지운다 · 숨었던 창은 지운다 · 숨기면 지운다")
    func rule2ReshowKeepsOcclusion() async throws {
        // 결함 자리: 보임 → 가림 → 다시 부름 → 가림 그대로 → 판 시작 말풍선 1.
        let script = AKScript(fallback: { _ in AK.response() })
        let store = AK.store(script)
        defer { store.reset(); script.finish() }
        var starts = 0
        store.onAttention = { if $0.kind == .matchStarted { starts += 1 } }
        store.windowDidShow()
        store.windowOcclusionDidChange(visible: false)
        store.windowDidShow()
        #expect(store.isWindowVisible && store.isWindowOccluded, "다시 부른 창이 가림 기록을 지웠다")
        try await akEventually { !store.isLoading }
        script.enqueue(.response(AK.response(AK.match(phase: .placing))))
        await store.refreshLobby()
        #expect(starts == 1)

        // 기준선: 숨은 창에 남은 옛 가림 기록은 처음 뜰 때 지운다 — 그래야 폴링 · 조회가 돈다.
        let hiddenScript = AKScript(fallback: { _ in AK.response() })
        let hidden = AK.store(hiddenScript)
        defer { hidden.reset(); hiddenScript.finish() }
        hidden.windowOcclusionDidChange(visible: false)
        #expect(!hidden.isWindowVisible && hidden.isWindowOccluded)
        hidden.windowDidShow()
        #expect(!hidden.isWindowOccluded, "숨었던 창의 옛 가림 기록이 남았다")
        try await akEventually { hiddenScript.lobbyCalls == [true] && !hidden.isLoading }

        // 대조: 숨기면 가림 기록을 지운다.
        hidden.windowOcclusionDidChange(visible: false)
        hidden.windowDidHide()
        #expect(!hidden.isWindowVisible && !hidden.isWindowOccluded)
    }

    /// 없으면: 판 밖 신청 · 수락 초인종이 도는 로비 조회에 묻혀(합친 부름을 버림) 받은 신청 카드 · 사람 목록이 다음 계기(30초)까지 안 서도 초록이다.
    @Test("규칙 ③ 도는 조회에 온 부름은 끝난 뒤 한 번 더(둘이 와도 한 번) · 합친 부름이 사람 목록을 원하면 그 바퀴는 전체 로비")
    func rule3MergedCallsRunOnceMore() async throws {
        let script = AKScript([.suspended], fallback: { _ in AK.lobby(users: [AK.user(AK.whiteID, "White"),
                                                                            AK.user(AK.thirdID, "Third")]) })
        let store = AK.store(script)
        defer { store.reset(); script.finish() }
        let first = Task { await store.refreshLightLobby() }
        try await akEventually { script.isSuspended(0) }
        let second = Task { await store.refreshLobby() }
        let third = Task { await store.refreshLobby() }
        for _ in 0..<5 { await Task.yield() }
        #expect(script.calls.count == 1 && script.maxConcurrentCalls == 1, "도는 중에 두 번째 조회가 겹쳐 나갔다")
        script.resume(0, returning: AK.response())
        await first.value
        await second.value
        await third.value
        #expect(script.lobbyCalls == [false, true], "합친 부름이 사라졌거나 두 번 돌았다")
        #expect(store.users.count == 2 && store.hasLoadedLobby)

        // 기준선: 합쳐진 부름이 없으면 한 번.
        let lone = AKScript(fallback: { _ in AK.response() })
        let single = AK.store(lone)
        defer { single.reset(); lone.finish() }
        await single.refreshLightLobby()
        #expect(lone.lobbyCalls == [false])
    }

    /// 없으면(VC-19): 판 중 걸음을 폴링 작업 안에서 바로 부르면, 창을 닫는 순간(폴링 취소) 날아가던 판 상태 응답이 버려져도 초록이다.
    @Test("규칙 ④ 판 중 걸음 — 판 상태만 · 폴링이 취소돼도 날아가던 응답은 옮긴다")
    func rule4InMatchStepRunsOutsideCancellation() async throws {
        let live = AK.match()
        let script = AKScript([.response(AK.response(live))], fallback: { _ in AK.response(live) })
        let store = AK.store(script)
        defer { store.reset(); script.finish() }
        store.rankingEnabled = true
        await store.refreshLobby()
        store.isWindowVisible = true
        script.enqueue(.suspended)
        let tick = Task { await store.pollTick(at: Date.distantFuture) }
        try await akEventually { script.isSuspended(1) }
        #expect(script.calls[1] == .state(matchID: AK.matchID, sinceChatSeq: 0))
        tick.cancel()                                          // 창 닫기 = 폴링 작업 취소
        var newer = live
        newer.revision += 1
        newer.currentPlayer = .white
        script.resume(1, returning: AK.response(newer))
        await tick.value
        try await akEventually { store.state?.revision == newer.revision }
        // 판 중 걸음은 로비 · 순위를 부르지 않는다(마감이 다 지난 시각이어도).
        #expect(script.count("alkkagi_lobby") == 1 && script.count("alkkagi_ranking") == 0)
    }

    /// 없으면: 보낸 신청 확인 걸음이 폴링 취소와 함께 버려져 거절 안내 · 카드 걷기가 다음 걸음까지 밀려도 초록이다.
    @Test("규칙 ④ 보낸 신청 걸음 — 5초마다 그 판 상태 · 폴링이 취소돼도 날아가던 응답은 옮긴다")
    func rule4OutgoingStepRunsOutsideCancellation() async throws {
        let clock = AKClock()
        let sent = AK.invite(id: AK.matchID, from: AK.white, stake: 10)
        let script = AKScript([.response(AK.lobby(outgoing: sent))], fallback: { _ in AK.response() })
        let store = AK.store(script, clock: clock)
        defer { store.reset(); script.finish() }
        await store.refreshLobby()
        #expect(store.outgoing?.stake == 10)
        store.isWindowVisible = true
        store.lastLobbyRequestAt = clock.date                  // 로비 걸음은 아직
        script.enqueue(.suspended)
        let tick = Task { await store.pollTick(at: clock.date) }
        try await akEventually { script.isSuspended(1) }
        #expect(script.calls[1] == .state(matchID: AK.matchID, sinceChatSeq: 0))
        tick.cancel()
        script.resume(1, returning: AK.response())             // 대기 신청이 빠졌다(만료 전) = 거절
        await tick.value
        try await akEventually { store.outgoing == nil }
        #expect(store.notice == AlkkagiNoticeText.inviteDeclined)
        // 기준선: 5초가 안 지났으면 다시 부르지 않는다.
        script.enqueue(.response(AK.lobby(outgoing: sent)))
        await store.refreshLobby()
        let before = script.calls.count
        clock.advance(4)
        await store.pollTick(at: clock.date)
        #expect(script.calls.count == before)
        clock.advance(1)
        await store.pollTick(at: clock.date)
        #expect(script.calls.count == before + 1)
    }

    /// 없으면: 로비 걸음이 폴링 취소와 함께 버려져 사람 목록이 비어 있어도 초록이다.
    @Test("규칙 ④ 로비 걸음 — 30초마다 전체 로비 · 폴링이 취소돼도 날아가던 응답은 옮긴다")
    func rule4LobbyStepRunsOutsideCancellation() async throws {
        let clock = AKClock()
        let script = AKScript([.suspended], fallback: { _ in AK.response() })
        let store = AK.store(script, clock: clock)
        defer { store.reset(); script.finish() }
        store.isWindowVisible = true
        let tick = Task { await store.pollTick(at: clock.date) }
        try await akEventually { script.isSuspended(0) }
        #expect(script.calls == [.lobby(users: true)])
        tick.cancel()
        script.resume(0, returning: AK.lobby())
        await tick.value
        try await akEventually { store.hasLoadedLobby }
        #expect(store.users.map(\.id) == [AK.whiteID])
        // 기준선: 30초 안에는 다시 부르지 않는다 · 지나면 부른다.
        clock.advance(29)
        await store.pollTick(at: clock.date)
        #expect(script.lobbyCalls == [true])
        clock.advance(1)
        await store.pollTick(at: clock.date)
        #expect(script.lobbyCalls == [true, true])
    }

    /// 없으면(규칙 ④ 걸음 사이 가드): 첫 걸음 도중 창을 가린 뒤에도 걸음이 끝까지 돌아 가려진 창이 사람 목록을 읽어도 초록이다.
    @Test("규칙 ④ 걸음 사이 가드 — 보낸 신청 걸음 도중 가려지면 로비 걸음 0 · 안 가려지면 1(기준선)")
    func rule4StepsRecheckTheDoorBetweenSteps() async throws {
        func lobbySteps(occludeMidway: Bool) async throws -> Int {
            let sent = AK.invite(id: AK.matchID, from: AK.white, stake: 3)
            let script = AKScript([.response(AK.response(outgoing: sent))], fallback: { _ in AK.response() })
            let store = AK.store(script)
            defer { store.reset(); script.finish() }
            await store.refreshLightLobby()                // outgoing 만 세운다(전체 로비 시각은 비운 채)
            #expect(store.outgoing != nil)
            store.isWindowVisible = true
            script.enqueue(.suspended)
            let index = script.calls.count
            let tick = Task { await store.pollTick(at: Date.distantFuture) }
            try await akEventually { script.isSuspended(index) }
            if occludeMidway { store.windowOcclusionDidChange(visible: false) }
            script.resume(index, returning: AK.response(outgoing: sent))
            await tick.value
            return script.lobbyCalls.filter { $0 }.count
        }
        #expect(try await lobbySteps(occludeMidway: true) == 0, "가려진 창이 로비 걸음을 이어 갔다")
        #expect(try await lobbySteps(occludeMidway: false) == 1)
    }

    /// 없으면: 나르던 작업(창 열기 · 버튼)이 취소되면 그 조회와 거기 합쳐진 초인종 조회까지 사라져도 초록이다.
    @Test("규칙 ⑤ 나르던 작업이 취소돼도 조회는 끝까지 · 합쳐진 부름도 한 번 더 돈다")
    func rule5CarrierCancellationDoesNotDropMergedCalls() async throws {
        let script = AKScript([.suspended], fallback: { _ in AK.response() })
        let store = AK.store(script)
        defer { store.reset(); script.finish() }
        let carrier = Task { await store.refreshLobby() }
        try await akEventually { script.isSuspended(0) }
        let merged = Task { await store.refreshLightLobby() }
        for _ in 0..<5 { await Task.yield() }
        carrier.cancel()
        script.resume(0, returning: AK.lobby(users: [AK.user(AK.whiteID, "White"), AK.user(AK.thirdID, "Third")]))
        await carrier.value
        await merged.value
        #expect(store.users.count == 2, "나르던 작업이 취소되자 날아가던 로비 응답을 버렸다")
        #expect(script.lobbyCalls == [true, false], "합쳐진 부름이 사라졌다")
    }

    // MARK: 폴링 상수

    /// 없으면: 판 밖 걸음이 0.3.80 처럼 3초마다 로비를 읽거나, 순위 · 보낸 신청 주기가 다수 값(60 · 5)에서 벗어나도 초록이다.
    @Test("폴링 상수 — 보낸 신청 5 · 로비 30 · 순위 60 · 메뉴 가벼운 로비 30 · 관전 2")
    func pollingConstantsMatchTheMajority() async throws {
        #expect(AlkkagiOnlineStore.outgoingPollSeconds == 5 && AlkkagiOnlineStore.lobbyPollSeconds == 30)
        #expect(AlkkagiOnlineStore.rankingPollSeconds == 60 && AlkkagiOnlineStore.menuLobbyThrottleSeconds == 30)
        #expect(AlkkagiOnlineStore.watchPollSeconds == 2)
        let clock = AKClock()
        let script = AKScript(fallback: { call in
            if case .ranking = call {
                return AlkkagiResponse(status: .ok, protocolVersion: 1, serverNowMs: AK.nowMs,
                                       ranking: AlkkagiRankingBoard(entries: [], me: nil))
            }
            return AK.lobby()
        })
        let store = AK.store(script, clock: clock)
        defer { store.reset(); script.finish() }
        store.rankingEnabled = true
        store.isWindowVisible = true
        await store.pollTick(at: clock.date)
        #expect(script.lobbyCalls == [true] && script.count("alkkagi_ranking") == 1)
        clock.advance(30)
        await store.pollTick(at: clock.date)
        #expect(script.lobbyCalls == [true, true] && script.count("alkkagi_ranking") == 1)
        clock.advance(30)
        await store.pollTick(at: clock.date)
        #expect(script.count("alkkagi_ranking") == 2)
        // 창이 안 보이면 걸음은 아무것도 안 한다.
        store.isWindowVisible = false
        clock.advance(120)
        let before = script.calls.count
        await store.pollTick(at: clock.date)
        #expect(script.calls.count == before)
        // 메뉴 팝오버: 가벼운 로비(p_users false) · 30초 스로틀.
        store.refreshLobbyIfStale()
        try await akEventually { !store.isLoading && script.calls.count == before + 1 }
        store.refreshLobbyIfStale()
        clock.advance(29)
        store.refreshLobbyIfStale()
        for _ in 0..<5 { await Task.yield() }
        try await akEventually { !store.isLoading }
        #expect(script.lobbyCalls.suffix(1) == [false] && script.calls.count == before + 1)
        clock.advance(1)
        store.refreshLobbyIfStale()
        try await akEventually { !store.isLoading && script.calls.count == before + 2 }
    }
}

// MARK: - 몸통: 판돈 · 루비 · 안내 · VC 항목

extension V03xxAlkkagiStoreTests {
    /// 없으면: 판돈을 고르지 않고(기본 3) 보내거나, 모자람 안내 · 잔액이 앱 전체 칩(host)에 안 옮겨지거나, 칩이 틀렸다는 응답 뒤
    /// 로비를 다시 읽지 않아도 초록이다.
    @Test("판돈 신청 — p_stake · 고른 값 기억 · insufficient 안내와 잔액 미러 · ok 보낸 신청 · already_pending 은 로비 다시")
    func stakeChallengeFlow() async throws {
        let host = AKHost()
        let script = AKScript([
            .response(AK.lobby(ruby: 100)),
            .response(AK.response(status: .insufficient, ruby: 7, need: 10, have: 7)),
            .response(AK.response(outgoing: AK.invite(id: AK.matchID, from: AK.white, stake: 10))),
            .response(AK.response(status: .alreadyPending)),
        ], fallback: { _ in AK.lobby(outgoing: AK.invite(id: AK.matchID, from: AK.white, stake: 10)) })
        let store = AK.store(script)
        store.host = host
        defer { store.reset(); script.finish() }
        await store.refreshLobby()
        #expect(host.rubyBalance == 100 && store.selectedStake == .three)

        await store.challenge(opponentID: AK.whiteID, stake: .ten)
        guard case let .challenge(opponent, stake, _) = script.calls[1] else {
            Issue.record("신청이 나가지 않았다")
            return
        }
        #expect(opponent.uuidString.lowercased() == AK.whiteID && stake == 10 && store.selectedStake == .ten)
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(script.calls[1].parameters)) as? [String: Any]
        #expect(body?["p_stake"] as? Int == 10 && body?["p_protocol"] as? Int == 2)
        #expect(store.notice == "루비 3개 더 필요해요")
        #expect(store.rubyBalance == 7 && host.rubyBalance == 7, "insufficient 봉투의 잔액이 앱 칩으로 안 옮겨졌다")
        #expect(store.outgoing == nil)

        await store.challenge(opponentID: AK.whiteID, stake: .ten)
        #expect(store.outgoing?.stake == 10 && store.notice == "신청을 보냈어요")
        #expect(script.lobbyCalls == [true], "ok 뒤에 로비를 또 읽었다(기준선)")

        await store.challenge(opponentID: AK.whiteID, stake: .ten)
        #expect(store.notice == "이미 보낸 신청이 있어요")
        #expect(script.lobbyCalls == [true, true], "already_pending 뒤에 로비를 다시 읽지 않았다")
    }

    /// 없으면(VC-5): 정산 뒤 늦게 닿은 옛 응답(서버 시각이 앞섬)이 스토어 · 앱 칩(host)을 되감아도 초록이다.
    @Test("루비 미러 — 로비 · 판 상태 잔액이 host 로 · 먼저 만든 늦은 응답은 버린다")
    func rubyMirrorIgnoresLateResponses() async throws {
        let host = AKHost()
        let live = AK.match()
        var settled = AK.match(phase: .finished, revision: 9, ruby: 105)
        settled.result = .black
        let script = AKScript([
            .response(AK.lobby(ruby: 95, serverNowMs: AK.nowMs, state: live)),
            .response(AK.response(settled, serverNowMs: AK.nowMs + 2_000)),
            .response(AK.lobby(ruby: 95, serverNowMs: AK.nowMs + 1_000)),            // 정산 전에 서버가 만든 로비
            .response(AK.lobby(ruby: 90, serverNowMs: AK.nowMs + 3_000)),
        ], fallback: { _ in AK.response() })
        let store = AK.store(script)
        store.host = host
        defer { store.reset(); script.finish() }
        await store.refreshLobby()
        #expect(host.rubyBalance == 95)
        await store.refreshMatch()                            // 판이 끝났다 → 전적 로비가 뒤따른다(정산 전에 만든 응답)
        try await akEventually { !store.isLoading }
        #expect(script.lobbyCalls == [true, false])
        #expect(store.rubyBalance == 105 && host.rubyBalance == 105, "늦은 로비가 상금을 되감았다")
        await store.refreshLobby()
        #expect(store.rubyBalance == 90 && host.rubyBalance == 90)                   // 기준선: 더 새 응답은 옮긴다
    }

    /// 없으면(§4.4): 보낸 신청이 거절 · 만료로 사라져도 안내가 없거나, 판으로 이어진 신청에 '거절' 안내가 서거나, 신청 직전에 나간 로비가
    /// 방금 보낸 신청을 지워도 초록이다.
    @Test("보낸 신청 끝 — 만료 전 빠짐 = 거절 · 만료 뒤 = 응답 없음 · 판이 되면 안내 0 · 신청 전에 나간 로비는 지우지 않는다")
    func outgoingEndNotices() async throws {
        let clock = AKClock()
        let sent = AK.invite(id: AK.matchID, from: AK.white, stake: 5)
        // 만료 뒤 빠짐.
        let expiring = AKScript([.response(AK.lobby(outgoing: sent))],
                                fallback: { _ in AK.lobby(serverNowMs: AK.nowMs + 61_000) })
        let late = AK.store(expiring, clock: clock)
        defer { late.reset(); expiring.finish() }
        await late.refreshLobby()
        clock.advance(61)
        await late.refreshLobby()
        #expect(late.outgoing == nil && late.notice == AlkkagiNoticeText.inviteTimedOut)

        // 판이 됐다(보낸 신청 id = 새 판 id) — 안내 0.
        let became = AKScript([.response(AK.lobby(outgoing: sent)),
                               .response(AK.lobby(state: AK.match(phase: .placing)))],
                              fallback: { _ in AK.response() })
        let match = AK.store(became)
        defer { match.reset(); became.finish() }
        await match.refreshLobby()
        await match.refreshLobby()
        #expect(match.outgoing == nil && match.state != nil && match.notice == nil, "판이 된 신청에 안내가 섰다")

        // 신청 직후 · 그 응답 전에 나간 로비(서버가 신청보다 먼저 읽음)는 방금 보낸 신청을 지우지 않는다.
        let race = AKScript([.response(AK.lobby()), .suspended, .suspended], fallback: { _ in AK.lobby() })
        let racing = AK.store(race)
        defer { racing.reset(); race.finish() }
        await racing.refreshLobby()
        let challenge = Task { await racing.challenge(opponentID: AK.whiteID, stake: .five) }
        try await akEventually { race.isSuspended(1) }
        let lobby = Task { await racing.refreshLobby() }
        try await akEventually { race.isSuspended(2) }
        race.resume(1, returning: AK.response(outgoing: sent))
        await challenge.value
        race.resume(2, returning: AK.lobby())                                     // 신청이 없는 옛 모습
        await lobby.value
        #expect(racing.outgoing?.id == sent.id && racing.notice == "신청을 보냈어요", "먼저 나간 로비가 보낸 신청을 지웠다")
    }

    /// 없으면(VC-16): 상대 계정 삭제로 판이 사라져(state not_found) 판 화면에 갇히거나, 안내가 다음 로비에 지워지거나, 로비를 다시
    /// 읽지 않아 상금이 칩에 안 서도 초록이다.
    @Test("판이 사라짐 — not_found 면 판을 내리고 '이미 끝난 대결이에요' + 전체 로비 · 다음 로비가 안내를 안 지운다")
    func vanishedMatchReturnsToLobby() async throws {
        let live = AK.match()
        let script = AKScript([.response(AK.response(live)),
                               .response(AK.response(status: .notFound)),
                               .response(AK.lobby(ruby: 110))], fallback: { _ in AK.lobby(ruby: 110) })
        let store = AK.store(script)
        defer { store.reset(); script.finish() }
        await store.refreshLobby()
        #expect(store.state != nil)
        await store.refreshMatch()
        try await akEventually { !store.isLoading }
        #expect(store.state == nil, "사라진 판을 들고 있다")
        #expect(store.notice == AlkkagiNoticeText.finishedMatch, "로비 응답이 안내를 지웠다")
        #expect(script.lobbyCalls == [true, true] && store.rubyBalance == 110)
        // 기준선: ok 판 상태는 판을 그대로 둔다.
        let keep = AKScript([.response(AK.response(live)), .response(AK.response(live))])
        let kept = AK.store(keep)
        defer { kept.reset(); keep.finish() }
        await kept.refreshLobby()
        await kept.refreshMatch()
        #expect(kept.state == live)
    }

    /// 없으면(VC-13): 수락과 엇갈린 취소(not_pending · expired · stale)가 로비를 다시 읽지 않아 이미 선 판으로 못 가도 초록이다.
    @Test("취소가 엇갈림 — not_pending · expired · stale 은 전체 로비 다시 · ok 는 아니다(기준선)")
    func crossedCancelRefetchesLobby() async throws {
        for (status, refetch) in [(AlkkagiRPCStatus.notPending, true), (.expired, true), (.stale, true), (.ok, false)] {
            let sent = AK.invite(id: AK.matchID, from: AK.white, stake: 5)
            let script = AKScript([.response(AK.lobby(outgoing: sent)), .response(AK.response(status: status))],
                                  fallback: { _ in AK.lobby(state: AK.match(phase: .placing)) })
            let store = AK.store(script)
            defer { store.reset(); script.finish() }
            await store.refreshLobby()
            await store.cancelChallenge()
            #expect(script.lobbyCalls.count == (refetch ? 2 : 1), "\(status.rawValue)")
            if status == .ok { #expect(store.outgoing == nil && store.notice == "신청을 취소했어요") }
            if status == .stale {
                // 엇갈린 취소 뒤 로비가 이미 선 판을 데려온다 — 그 판이 된 신청에 '거절' 안내를 덧씌우지 않는다.
                #expect(store.state != nil && store.outgoing == nil && store.notice == AlkkagiNoticeText.finishedInvite)
            }
        }
    }

    /// 없으면(VC-20): 내 차례 말풍선이 '상대가 쏴서 넘어온' 때만 울어, 상대가 시간을 넘긴 차례 · 배치 끝(흑)의 첫 차례를 가려진 창에서
    /// 놓쳐도(셋이면 판돈을 잃는다) 초록이다. 'current_player 바뀜'으로 재는 변이는 배치 끝을 놓친다.
    @Test("내 차례 말풍선 — 배치 끝(흑) · 상대 시간 넘김 · 상대 쏘기(이름) 각각 한 번 · 보이는 창은 0")
    func myTurnAttentionOnEveryEntry() async throws {
        func attentions(visible: Bool) async throws -> [AlkkagiAttention] {
            let placing = AK.match(phase: .placing, revision: 1)
            let aim = AK.match(revision: 2)
            var rolling = AK.match(phase: .rolling, revision: 3, shotCount: 1)
            rolling.shot = AK.shot(by: 0, on: rolling)
            let theirs = AK.match(current: .white, revision: 4, shotCount: 1)
            let timedOut = AK.match(revision: 5, shotCount: 1)                       // 상대가 시간을 넘김
            let mineAgain = AK.match(current: .white, revision: 6, shotCount: 1)       // 내가 넘김
            var shotBack = AK.match(revision: 7, shotCount: 2)
            shotBack.shot = AK.shot(by: 5, on: shotBack)                              // 상대(백)가 쐈다
            let replies: [AKScript.Reply] = [placing, aim, rolling, theirs, timedOut, mineAgain, shotBack, shotBack]
                .map { AKScript.Reply.response(AK.response($0)) }
            let script = AKScript(replies, fallback: { _ in AK.response() })
            let store = AK.store(script)
            defer { store.reset(); script.finish() }
            if visible { store.isWindowVisible = true }
            var seen: [AlkkagiAttention] = []
            store.onAttention = { seen.append($0) }
            await store.refreshLobby()
            for _ in 0..<7 { await store.refreshMatch() }
            return seen
        }
        let hidden = try await attentions(visible: false)
        let id = AK.matchID.uuidString.lowercased()
        #expect(hidden == [AlkkagiAttention(kind: .matchStarted, matchID: id, opponentName: "White"),
                           AlkkagiAttention(kind: .myTurn, matchID: id, opponentName: ""),
                           AlkkagiAttention(kind: .myTurn, matchID: id, opponentName: ""),
                           AlkkagiAttention(kind: .myTurn, matchID: id, opponentName: "White")])
        #expect(try await attentions(visible: true).isEmpty, "보이는 창 위에 내 차례 말풍선이 겹쳤다")
    }

    /// 없으면(VC-23): 조준 마감 새로고침이 유예 전(마감 그대로)에 나가 같은 판을 또 읽고, 정작 유예가 끝나 차례가 넘어간 뒤에는
    /// 다음 걸음(3초)까지 기다려도 초록이다. 배치 마감은 유예가 없다(대조).
    @Test("조준 마감 새로고침 = 마감 + grace_ms · 배치 마감은 그대로")
    func aimDeadlineRefreshWaitsForGrace() async throws {
        func refreshedBy(_ phase: AlkkagiMatchPhase, wait: Duration) async throws -> Bool {
            let snapshot = AK.match(phase: phase, deadlineMs: AK.nowMs + 50, graceMs: 700)
            let script = AKScript(fallback: { _ in AK.response(snapshot) })
            let store = AK.store(script)
            defer { store.reset(); script.finish() }
            store.isWindowVisible = true
            await store.refreshLobby()
            try await akEventually { !store.isLoading }
            let base = script.calls.count
            try await Task.sleep(for: wait)
            return script.calls.count > base
        }
        #expect(try await refreshedBy(.aiming, wait: .milliseconds(350)) == false, "유예 전에 마감 새로고침이 나갔다")
        #expect(try await refreshedBy(.aiming, wait: .milliseconds(1_400)) == true, "유예가 끝나도 새로고침이 없다")
        #expect(try await refreshedBy(.placing, wait: .milliseconds(350)) == true)
    }

    /// 없으면: 받은 신청 하나에 대한 응답(수락 실패 · 확인)이 그 신청 하나만 실어 와(`alk_reply` 의 incoming) 다른 받은 신청 카드를
    /// 지워도 초록이다. 로비는 받은 신청 전부를 싣으므로 통째로 바꾼다(기준선).
    @Test("한 판 응답의 incoming 은 고쳐 넣기만 — 다른 받은 신청 카드가 남는다 · 로비는 통째로 바꾼다")
    func singleInviteResponsesMergeIncoming() async throws {
        let first = AK.invite(id: AK.inviteID, from: AK.white, stake: 10)
        let second = AK.invite(id: AK.nextMatchID, from: AK.white, stake: 3)
        let script = AKScript([.response(AK.lobby(incoming: [first, second])),
                               .response(AK.response(status: .insufficient, incoming: [first], ruby: 100, need: 10,
                                                     side: "challenger")),
                               .response(AK.lobby(incoming: [second]))])
        let store = AK.store(script)
        defer { store.reset(); script.finish() }
        await store.refreshLobby()
        await store.respond(inviteID: first.id, accept: true)
        #expect(store.notice == "상대의 루비가 모자라요")
        #expect(Set(store.incoming.map(\.id)) == [first.id, second.id], "한 신청의 응답이 다른 받은 신청 카드를 지웠다")
        await store.refreshLobby()
        #expect(store.incoming.map(\.id) == [second.id])
    }

    /// 없으면(DF#29): 상대 구버전(`target_outdated`)이 내 화면을 '업데이트' · '곧 열려요'로 바꿔도 초록이다.
    @Test("남의 구버전은 내 availability 를 안 바꾼다 · 내 build 가 모자라면 업데이트(기준선)")
    func targetOutdatedKeepsMyAvailability() async throws {
        let script = AKScript([.response(AK.lobby()), .response(AK.response(status: .targetOutdated)),
                               .response(AK.lobby()),
                               .response(AK.response(status: .unsupportedClient, doorOpen: true))])
        let store = AK.store(script)
        defer { store.reset(); script.finish() }
        await store.refreshLobby()
        await store.challenge(opponentID: AK.whiteID, stake: .three)
        #expect(store.availability == .available && store.notice == AlkkagiNoticeText.targetOutdated)
        #expect(script.lobbyCalls == [true, true])
        await store.challenge(opponentID: AK.whiteID, stake: .three)
        #expect(store.availability == .updateRequired && store.notice == AlkkagiNoticeText.updateMine)
    }

    /// 없으면: 순위가 스위치 꺼진 조립(시험 · 미리보기)에서도 서버를 두드리거나, 창이 열릴 때 · 서버에 함수가 없을 때 갈래가 틀려도 초록이다.
    @Test("순위 — 창이 열릴 때 한 번(스위치 켜짐만) · PGRST202 면 rankingUnavailable · 'N위'는 순위 me = 로비 전적일 때만")
    func rankingLoadsWhenTheWindowOpens() async throws {
        let board = try #require(try akFixture("alkkagi_ranking__ok").ranking)
        let script = AKScript(fallback: { call in
            if case .ranking = call { return AlkkagiResponse(status: .ok, serverNowMs: AK.nowMs, ranking: board) }
            return AK.lobby()
        })
        let off = AK.store(script)
        defer { off.reset(); script.finish() }
        off.windowDidShow()
        try await akEventually { !off.isLoading }
        await off.refreshRanking()
        #expect(script.count("alkkagi_ranking") == 0 && off.ranking == nil)

        let onScript = AKScript(fallback: script.fallback)
        let on = AK.store(onScript)
        defer { on.reset(); onScript.finish() }
        on.rankingEnabled = true
        on.windowDidShow()
        try await akEventually { on.ranking != nil && !on.isLoading }
        #expect(onScript.count("alkkagi_ranking") == 1 && on.ranking?.entries.count == 2)
        #expect(board.me?.matches(AlkkagiRecord(wins: 4, losses: 1, draws: 2)) == true)
        #expect(board.me?.matches(AlkkagiRecord(wins: 4, losses: 1, draws: 1)) == false)
        #expect(board.me?.matches(nil) == false)

        let missing = AKScript([.failure(.serverMissing)])
        let gone = AK.store(missing)
        defer { gone.reset(); missing.finish() }
        gone.rankingEnabled = true
        await gone.refreshRanking()
        #expect(gone.rankingUnavailable && gone.ranking == nil && gone.notice == nil)
    }

    /// 없으면: 손 픽스처(§3.7 모양 — S 원문이 오면 바뀐다)로 로비 → 판돈 신청 → 모자람 → 보냄 → 판 → 끝 → [로비로] 를 이으면 어느 칸이
    /// 비거나 갈래가 틀려도 초록이다.
    @Test("픽스처 한 판 — 로비 · 판돈 · insufficient · 보낸 신청 → 배치 · 조준 · 승 · rubyDelta · [로비로]")
    func fixtureFlowFromLobbyToResult() async throws {
        let host = AKHost()
        let clock = AKClock(milliseconds: 1_800_000_000_000)
        let script = AKScript([
            .response(try akFixture("alkkagi_lobby__ok_full")),
            .response(try akFixture("alkkagi_challenge__insufficient")),
            .response(try akFixture("alkkagi_challenge__ok")),
            .response(try akFixture("alkkagi_state__placing")),               // 보낸 신청 확인 → 상대가 받았다
            .response(try akFixture("alkkagi_state__aiming")),
            .response(try akFixture("alkkagi_state__finished_win")),
            .response(try akFixture("alkkagi_lobby__after_win")),             // 끝난 뒤 전적 다시(정산 반영)
            .response(try akFixture("alkkagi_leave__ok")),
            .response(try akFixture("alkkagi_lobby__after_win")),
        ], fallback: { _ in try? akFixture("alkkagi_lobby__ok_light") })
        let store = AK.store(script, clock: clock)
        store.host = host
        defer { store.reset(); script.finish() }
        var finishes = 0
        store.onMatchFinished = { finishes += 1 }
        await store.refreshLobby()
        #expect(store.availability == .available && store.visibleUsers.count == 4 && store.liveMatches.count == 1)
        #expect(store.visibleUsers.map(\.displayName) == ["민수", "지우", "구버전", "집중"])
        #expect(store.record == AlkkagiRecord(wins: 3, losses: 1, draws: 2) && host.rubyBalance == 100)
        #expect(store.visibleIncoming?.stake == 5)

        let minsu = try #require(store.visibleUsers.first?.id)
        await store.challenge(opponentID: minsu, stake: .ten)
        #expect(store.notice == "루비 3개 더 필요해요" && host.rubyBalance == 7)
        await store.challenge(opponentID: minsu, stake: .ten)
        #expect(store.outgoing?.stake == 10 && store.notice == "신청을 보냈어요")

        store.isWindowVisible = true
        clock.advance(5)
        await store.pollTick(at: clock.date)                                 // 보낸 신청 확인 → 판(배치)
        #expect(store.state?.phase == .placing && store.outgoing == nil && store.incoming.isEmpty)
        #expect(store.notice == nil, "판이 된 신청에 거절 안내가 섰거나 판 시작이 앞 안내를 안 지웠다")
        await store.pollTick(at: clock.date)                                 // 판 중 걸음 → 조준
        #expect(store.state?.phase == .aiming && store.spectatorCount == 2 && store.isMyTurn)
        await store.pollTick(at: clock.date)                                 // → 승
        try await akEventually { !store.isLoading }
        #expect(store.outcome == .win && store.endReason == .ringOut && store.rubyDelta == DuelFee.winnerNet(stake: 10))
        #expect(AlkkagiNoticeText.endReason(store.endReason, outcome: store.outcome) == "상대 돌을 모두 판 밖으로 밀어냈어요")
        #expect(host.rubyBalance == 110 && finishes == 1)
        #expect(store.record == AlkkagiRecord(wins: 4, losses: 1, draws: 2), "끝난 판을 지켜본 뒤 전적 로비를 다시 읽지 않았다")
        store.backToLobby()
        try await akEventually { store.state == nil && !store.isLoading && script.calls.count >= 9 }
        #expect(store.hasLoadedLobby && store.users.count == 4 && host.rubyBalance == 110 && store.outcome == nil)
    }
}

// MARK: - 판 진행 보존(0.3.80 독립 실행기 `AlkkagiOnlineTests` 23개를 v2 이름으로 옮김 — §4.6 경계)
//
// 독립 실행기는 §5.10 에서 온라인 파일을 뺀다(U). 판 진행(배치 · 조준 · 굴림 · 시계 오프셋 · revision · 쏘기 action_id · 대화 ·
// 낡은 응답 버리기)의 회귀 그물은 여기로 옮겨 본 스위트에 둔다. 고친 곳: protocol 2 · p_stake · `muted` 없음 ·
// `challenge(opponentID:stake:)` · 로비 사람 = `AlkkagiLobbyUser` · 끝난 판을 지켜보면 전적 로비가 뒤따름 · 판 밖 걸음 정책(v2).

extension V03xxAlkkagiStoreTests {
    @Test func kept_callsEncodeTheRPCContractAndKeepTheirActionNonce() throws {
        let matchID = AK.matchID
        let opponentID = try #require(UUID(uuidString: AK.whiteID))
        let nonce = UUID(uuidString: "ABCDEF01-2345-4678-9ABC-DEF012345678")!
        let match = matchID.uuidString
        let action = nonce.uuidString
        let cases: [(AlkkagiCall, String, [String: Any])] = [
            (.lobby(users: false), "alkkagi_lobby", ["p_users": false]),
            (.challenge(opponentID: opponentID, stake: 5, actionID: nonce), "alkkagi_challenge",
             ["p_opponent": opponentID.uuidString, "p_action_id": action, "p_stake": 5]),
            (.cancel(matchID: matchID, actionID: nonce), "alkkagi_cancel",
             ["p_match_id": match, "p_action_id": action]),
            (.respond(matchID: matchID, accept: false, actionID: nonce), "alkkagi_respond",
             ["p_match_id": match, "p_accept": false, "p_action_id": action]),
            (.state(matchID: matchID, sinceChatSeq: 41), "alkkagi_state",
             ["p_match_id": match, "p_since_chat_seq": 41]),
            (.place(matchID: matchID, expectedPlacementRevision: 7, stoneID: 2,
                    position: AK.vector(120, 420), actionID: nonce), "alkkagi_place",
             ["p_match_id": match, "p_expected_placement_revision": 7, "p_stone_id": 2,
              "p_x": 120, "p_y": 420, "p_action_id": action]),
            (.ready(matchID: matchID, expectedPlacementRevision: 7, actionID: nonce), "alkkagi_ready",
             ["p_match_id": match, "p_expected_placement_revision": 7, "p_action_id": action]),
            (.shoot(matchID: matchID, expectedRevision: 8, stoneID: 5,
                    pull: AK.vector(-12, 75), actionID: nonce), "alkkagi_shoot",
             ["p_match_id": match, "p_expected_revision": 8, "p_stone_id": 5,
              "p_pull_x": -12, "p_pull_y": 75, "p_action_id": action]),
            (.resign(matchID: matchID, expectedRevision: 9, actionID: nonce), "alkkagi_resign",
             ["p_match_id": match, "p_expected_revision": 9, "p_action_id": action]),
            (.chatSend(matchID: matchID, body: "안녕 👋", actionID: nonce), "alkkagi_chat_send",
             ["p_match_id": match, "p_body": "안녕 👋", "p_action_id": action]),
            (.chatMute(matchID: matchID, muted: true, actionID: nonce), "alkkagi_chat_mute",
             ["p_match_id": match, "p_muted": true, "p_action_id": action]),
            (.leave(matchID: matchID, expectedRevision: 10, actionID: nonce), "alkkagi_leave",
             ["p_match_id": match, "p_expected_revision": 10, "p_action_id": action])
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for (call, rpc, fields) in cases {
            var expected = fields
            expected["p_protocol"] = 2
            let encoded = try encoder.encode(call.parameters)
            let actual = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            #expect(call.rpcName == rpc)
            #expect(NSDictionary(dictionary: actual).isEqual(to: expected), "\(rpc): exact RPC keys and values")
            #expect(try encoder.encode(call.parameters) == encoded, "Re-encoding a retry keeps its nonce")
        }
    }

    @Test func kept_nestedWirePayloadDecodesWithBothProductionDecoderStrategies() throws {
        for convertSnakeCase in [false, true] {
            let decoder = JSONDecoder()
            if convertSnakeCase { decoder.keyDecodingStrategy = .convertFromSnakeCase }
            let response = try decoder.decode(AlkkagiResponse.self, from: Data(keptWireJSON.utf8))
            #expect(response.status == .ok && response.protocolVersion == 2)
            #expect(response.serverNowMs == AK.nowMs)
            #expect(response.me?.displayName == "Black")
            #expect(response.me?.avatarURL == "https://example.invalid/avatar.png")
            #expect(response.users?.first?.characterID == "turtle")
            #expect(response.incoming?.first?.expiresAtMs == AK.nowMs + 60_000)
            let state = try #require(response.state)
            #expect(state.currentPlayer == .black && state.myColor == .black)
            #expect(state.phase == .rolling && state.revision == 7 && state.shotCount == 1)
            #expect(state.deadlineMs == AK.nowMs + 30_000)
            #expect(state.chatSeq == 2 && state.chat.first?.senderID == AK.white.id)
            #expect(state.chat.first?.sentAtMs == AK.nowMs - 10)
            #expect(state.shot?.stoneID == 0 && state.shot?.steps == 720)
            #expect(state.shot?.initialStones.count == 3 && state.shot?.duration == 3)
            #expect(state.canonicalGame != nil && state.shotReplayGame != nil)
        }
    }

    @Test func kept_bothPeersPlaceUsingTheirOwnRevisionAndReadyLocksTheirLayout() async throws {
        for color in AlkkagiGame.Player.allCases {
            var snapshot = AK.match(myColor: color, phase: .placing)
            snapshot.placementRevision = 3
            let service = AKScript([.response(AK.response(snapshot))],
                                       fallback: { _ in AK.response() })
            let store = keptStore(service)
            defer { store.reset(); service.finish() }
            await store.refreshLobby()
            #expect(store.isMyTurn && store.canPlace && !store.canShoot)
            #expect(store.state?.stones.count == 5 && store.state?.stones.allSatisfy { $0.owner == color } == true)
            await store.confirmPlacement()
            await store.place(stoneID: color == .black ? 5 : 0, at: AK.vector(300, 400))
            await store.place(stoneID: color == .black ? 0 : 5, at: AK.vector(.nan, 400))
            #expect(service.calls.count == 1)
            let ownID = color == .black ? 0 : 5
            let position = AK.vector(100, color == .black ? 440 : 160)
            // The other player changes the public revision, without invalidating my pending placement.
            snapshot.revision += 4
            snapshot.opponentReady = true
            service.enqueue(.response(AK.response(snapshot)))
            await store.refreshLobby()
            await store.place(stoneID: ownID, at: position)
            guard case let .place(id, revision, stoneID, sentPosition, _) = service.calls.last else {
                Issue.record("Both colors must be allowed to place during the same phase")
                continue
            }
            #expect(id == AK.matchID && revision == 3 && revision != snapshot.revision)
            #expect(stoneID == ownID && sentPosition == position)
            #expect(store.state == snapshot, "Only a server snapshot commits a placement")
            for index in snapshot.stones.indices { snapshot.stones[index].isPlaced = true }
            snapshot.revision += 1
            snapshot.placementRevision += 1
            service.enqueue(.response(AK.response(snapshot)))
            await store.refreshLobby()
            await store.confirmPlacement()
            guard case let .ready(id, revision, _) = service.calls.last else {
                Issue.record("Five own stones allow ready")
                continue
            }
            #expect(id == AK.matchID && revision == snapshot.placementRevision)
            snapshot.myReady = true
            snapshot.revision += 1
            snapshot.placementRevision += 1
            service.enqueue(.response(AK.response(snapshot)))
            await store.refreshLobby()
            let before = service.calls.count
            await store.place(stoneID: ownID, at: position)
            await store.confirmPlacement()
            #expect(!store.canPlace && !store.canShoot && !store.isMyTurn)
            #expect(service.calls.count == before, "Ready locks this player's layout")
        }
    }

    @Test func kept_opponentPlacementDoesNotInterruptMyPlacementDrag() async throws {
        var snapshot = AK.match(phase: .placing)
        let service = AKScript([.response(AK.response(snapshot))])
        let store = keptStore(service)
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        let model = AlkkagiLocalModel()
        model.soundEnabled = false
        model.attachOnline(store)
        let point = AK.vector(100, 440)
        model.aim(start: point, translation: AK.vector(20, 10))
        let dragged = model.dragPlacementID
        let target = model.placementPoint
        #expect(dragged != nil && target != nil)
        snapshot.revision += 1
        snapshot.opponentReady = true
        service.enqueue(.response(AK.response(snapshot)))
        await store.refreshLobby()
        model.tick(now: 0)
        model.tick(now: 0.01)
        #expect(model.dragPlacementID == dragged && model.placementPoint == target)
        var revealed = AK.match(revision: snapshot.revision + 1)
        revealed.myReady = true
        revealed.opponentReady = true
        service.enqueue(.response(AK.response(revealed)))
        await store.refreshLobby()
        model.tick(now: 0.02)
        #expect(model.dragPlacementID == nil && model.placementPoint == nil)
    }

    @Test func kept_onlyTheFirstAuthoritativeFinishRefreshesMissions() async throws {
        let active = AK.match()
        var finished = active
        finished.phase = .finished
        finished.result = .black
        finished.deadlineMs = nil
        finished.revision += 1
        let service = AKScript([.response(AK.response(active)),
                                    .response(AK.response(finished)),
                                    .response(AK.response(finished)),
                                    .response(AK.response(active))],
                                   fallback: { _ in AK.response() })     // v2: 끝난 판을 지켜보면 전적 로비가 뒤따른다
        let store = keptStore(service)
        var finishes = 0
        store.onMatchFinished = { finishes += 1 }
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        #expect(finishes == 0)
        await store.refreshMatch()
        #expect(finishes == 1)
        await store.refreshMatch()
        await store.refreshMatch()
        #expect(finishes == 1 && store.state?.phase == .finished)
        store.reset()
        service.enqueue(.response(AK.response(active)))
        await store.refreshLobby()
        #expect(finishes == 1, "Resetting the account is not a game result")
        service.enqueue(.response(AK.response(finished)))
        await store.refreshMatch()
        #expect(finishes == 2, "The next account/session keeps its own finish observations")
    }

    @Test func kept_blockedPeersNeverBecomeVisibleOrTriggerAnInvitationNotification() async throws {
        var lobby = AK.response()
        lobby.me = AK.black
        lobby.users = [AK.user(AK.whiteID, "White")]
        lobby.incoming = [AK.invite()]
        lobby.outgoing = AK.invite()
        let service = AKScript([.response(lobby)])
        let store = keptStore(service)
        store.hiddenPeerIDs = [AK.white.id.uppercased()]
        var notifications = 0
        store.onInviteArrived = { _ in notifications += 1 }
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        #expect(store.users.isEmpty && store.incoming.isEmpty && store.outgoing == nil)
        await store.challenge(opponentID: AK.white.id, stake: .three)
        #expect(service.calls.count == 1 && notifications == 0)
    }

    @Test func kept_aimingGatesBothPeersAndSendsOneShotWithTheSuppliedNonce() async throws {
        for shooter in AlkkagiGame.Player.allCases {
            var peers: [(AlkkagiOnlineStore, AKScript)] = []
            defer { for (store, service) in peers { store.reset(); service.finish() } }
            for color in AlkkagiGame.Player.allCases {
                var snapshot = AK.match(myColor: color)
                snapshot.currentPlayer = shooter
                let service = AKScript([.response(AK.response(snapshot)), .suspended],
                                           fallback: { _ in AK.response() })
                let store = keptStore(service)
                peers.append((store, service))
                await store.refreshLobby()
                #expect(store.canShoot == (color == shooter) && !store.canPlace)
                let ownID = color == .black ? 0 : 5
                await store.shoot(stoneID: color == .black ? 5 : 0, pull: AK.vector(0, 80))
                await store.shoot(stoneID: ownID, pull: AK.vector(0, 5))
                await store.shoot(stoneID: ownID, pull: AK.vector(.infinity, 80))
                #expect(service.calls.count == 1)
                let nonce = UUID()
                let pull = AK.vector(12, 80)
                let shot = Task { await store.shoot(stoneID: ownID, pull: pull, actionID: nonce) }
                defer { shot.cancel() }
                if color != shooter {
                    await shot.value
                    #expect(service.calls.count == 1)
                    continue
                }
                try await akEventually { service.isSuspended(1) }
                #expect(store.isBusy && !store.canShoot)
                #expect(store.state == snapshot, "A shot must not optimistically roll or advance the turn")
                #expect(service.calls[1] == .shoot(matchID: AK.matchID,
                                                 expectedRevision: snapshot.revision,
                                                 stoneID: ownID, pull: pull, actionID: nonce))
                await store.shoot(stoneID: ownID, pull: pull)
                #expect(service.calls.count == 2, "A second action cannot race the first")
                service.resume(1, returning: AK.response())
                await shot.value
                #expect(!store.isBusy && store.canShoot)
                #expect(store.state == snapshot)
            }
        }
    }

    @Test func kept_staleBoardRevisionStillMergesChatAndAdvancesOnlyTheChatCursor() async throws {
        var newest = AK.match(revision: 12)
        newest.chatSeq = 2
        newest.chat = [keptMessage(2, "original")]
        var stale = newest
        stale.revision = 11
        stale.currentPlayer = .white
        stale.stones[0].position.x += 20
        stale.chatSeq = 5
        stale.chat = [keptMessage(5, "five"), keptMessage(2, "replacement"),
                      keptMessage(4, "four"), keptMessage(0, "invalid"),
                      keptMessage(6, "beyond cursor"),
                      keptMessage(3, String(repeating: "a", count: 101))]
        var invalidDate = keptMessage(1, "invalid date")
        invalidDate.sentAtMs = .nan
        stale.chat.append(invalidDate)
        let service = AKScript([.response(AK.response(newest)),
                                    .response(AK.response(stale)),
                                    .response(AK.response())])
        let store = keptStore(service)
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        await store.refreshMatch()
        #expect(store.state?.revision == 12 && store.state?.currentPlayer == .black)
        #expect(store.state?.stones == newest.stones)
        #expect(store.chat.map(\.seq) == [2, 4, 5])
        #expect(store.chat.map(\.body) == ["original", "four", "five"])
        #expect(store.state?.chat == store.chat && store.state?.chatSeq == 5)
        await store.refreshMatch()
        #expect(service.calls == [.lobby(users: true), .state(matchID: AK.matchID, sinceChatSeq: 2),
                                  .state(matchID: AK.matchID, sinceChatSeq: 5)])
    }

    @Test func kept_resetIgnoresLateAccountRepliesAndTheirBusyCleanup() async throws {
        let old = AK.match()
        let service = AKScript([.response(AK.response(old)), .suspended,
                                    .response(AK.response(AK.match(myColor: .white))),
                                    .suspended])
        let store = keptStore(service)
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        let oldAction = Task { await store.resign() }
        defer { oldAction.cancel() }
        try await akEventually { service.isSuspended(1) }
        let generation = store.resetGeneration
        store.reset()
        #expect(store.resetGeneration != generation)
        #expect(store.me == nil && store.state == nil && store.chat.isEmpty)
        #expect(!store.isBusy && !store.isLoading && !store.isSendingChat && !store.canShoot)
        await store.refreshLobby()
        #expect(store.me == AK.white, "The injected service survives an account reset")
        let newAction = Task { await store.resign() }
        defer { newAction.cancel() }
        try await akEventually { service.isSuspended(3) }
        var late = AK.response(old)
        late.users = [AK.user(AK.blackID, "Black")]
        late.incoming = [AK.invite()]
        service.resume(1, returning: late)
        await oldAction.value
        #expect(store.me == AK.white && store.state?.myColor == .white)
        #expect(store.users.isEmpty && store.incoming.isEmpty && store.chat.isEmpty)
        #expect(store.isBusy, "An old action's defer must not unlock a new account's action")
        service.resume(3, returning: AK.response())
        await newAction.value
        #expect(!store.isBusy)
    }

    @Test func kept_authenticationLossClearsAccountAndCancelsAnInFlightSync() async throws {
        for failure in [AKScript.Reply.response(AlkkagiResponse(status: .notSignedIn,
                                                            serverNowMs: AK.nowMs)),
                        .failure(.notSignedIn)] {
            let service = AKScript([.response(AK.response(AK.match())),
                                        .suspended, failure])
            let store = keptStore(service)
            defer { store.reset(); service.finish() }
            await store.refreshLobby()
            let refresh = Task { await store.refreshMatch() }
            defer { refresh.cancel() }
            try await akEventually { service.isSuspended(1) }
            await store.sendChat(body: "hello")
            #expect(store.me == nil && store.state == nil && store.chat.isEmpty)
            #expect(!store.isSendingChat && !store.isLoading && !store.canShoot)
            try await akEventually { service.cancelledRequests.contains(1) }
            service.resume(1, returning: AK.response(AK.match()))
            await refresh.value
            #expect(store.me == nil && store.state == nil && store.incoming.isEmpty)
        }
    }

    @Test func kept_aPreviousMatchReplyCannotReplaceTheNewMatchOrItsChat() async throws {
        var previous = AK.match()
        previous.phase = .finished
        previous.result = .black
        previous.chatSeq = 1
        previous.chat = [keptMessage(1, "old")]
        var next = AK.match(id: AK.nextMatchID)
        next.chatSeq = 1
        next.chat = [keptMessage(1, "new")]
        let service = AKScript([.response(AK.response(previous)), .suspended,
                                    .response(AK.response(next))])
        let store = keptStore(service)
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        let oldChat = Task { await store.sendChat(body: "delayed") }
        defer { oldChat.cancel() }
        try await akEventually { service.isSuspended(1) }
        await store.refreshLobby()
        #expect(store.state?.id == next.id && store.chat.map(\.body) == ["new"])
        previous.revision = 999
        previous.chatSeq = 2
        previous.chat.append(keptMessage(2, "late old chat"))
        service.resume(1, returning: AK.response(previous))
        await oldChat.value
        #expect(store.state == next && store.chat == next.chat)
        #expect(!store.isSendingChat)
    }

    @Test func kept_aBurstOfRefreshSignalsProducesOneCoalescedFollowup() async throws {
        let snapshot = AK.match()
        let response = AK.response(snapshot)
        let service = AKScript([.suspended, .response(response), .response(response)])
        let store = keptStore(service)
        defer { store.reset(); service.finish() }
        let refresh = Task { await store.refreshLobby() }
        defer { refresh.cancel() }
        try await akEventually { service.isSuspended(0) }
        for _ in 0..<20 {
            store.handleSignal()
            store.realtimeDidJoin()
            store.systemDidWake()
        }
        #expect(service.calls == [.lobby(users: true)] && service.maxConcurrentCalls == 1)
        service.resume(0, returning: response)
        await refresh.value
        #expect(service.calls == [.lobby(users: true), .lobby(users: false),
                                  .state(matchID: AK.matchID, sinceChatSeq: 0)])
        #expect(service.maxConcurrentCalls == 1 && !store.isLoading)
    }

    @Test func kept_serverClockUsesRequestMidpointAndLateRepliesCannotRewindIt() async throws {
        let clock = AKClock(milliseconds: 10_000)
        let snapshot = AK.match()
        let service = AKScript([.suspended, .suspended,
                                    .response(AK.response(snapshot, serverNowMs: 1_003_100))])
        let store = keptStore(service, clock: clock)
        defer { store.reset(); service.finish() }
        let initial = Task { await store.refreshLobby() }
        defer { initial.cancel() }
        try await akEventually { service.isSuspended(0) }
        clock.milliseconds = 10_200
        service.resume(0, returning: AK.response(snapshot))
        await initial.value
        // Foundation Date rounds sub-millisecond values around its reference epoch.
        #expect(abs(store.estimatedServerNowMs - 1_000_100) < 0.001)
        #expect(abs(store.remainingSeconds - 29.9) < 0.000001)
        clock.milliseconds += 3_000
        #expect(abs(store.remainingSeconds - 26.9) < 0.000001)
        let oldChat = Task { await store.sendChat(body: "late clock") }
        defer { oldChat.cancel() }
        try await akEventually { service.isSuspended(1) }
        await store.refreshMatch()
        let synchronizedNow = store.estimatedServerNowMs
        service.resume(1, returning: AK.response(snapshot, serverNowMs: 900_000))
        await oldChat.value
        #expect(abs(store.estimatedServerNowMs - synchronizedNow) < 0.001)
        #expect(abs(store.remainingSeconds - 26.9) < 0.000001)
    }

    @Test func kept_rollingPausesTheServerClockAndReadingItHasNoSideEffects() async throws {
        let clock = AKClock()
        let decoded = try JSONDecoder().decode(AlkkagiResponse.self, from: Data(keptWireJSON.utf8))
        let snapshot = try #require(decoded.state)
        let service = AKScript([.response(decoded)])
        let store = keptStore(service, clock: clock)
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        #expect(store.remainingSeconds == 30 && !store.canShoot && !store.canPlace)
        clock.milliseconds += 120_000
        for _ in 0..<20 { #expect(store.remainingSeconds == 30) }
        #expect(snapshot.canonicalGame(serverNowMs: clock.milliseconds)?.turnRemaining == 30)
        #expect(store.state == snapshot && service.calls.count == 1)
        #expect(store.state?.phase == .rolling && store.state?.currentPlayer == .black)
    }

    @Test func kept_deadlineExpirationRequestsStateWithoutAdvancingTheTurnLocally() async throws {
        let clock = AKClock()
        var snapshot = AK.match()
        snapshot.deadlineMs = AK.nowMs + 15
        let response = AK.response(snapshot)
        let service = AKScript([.response(response), .response(response), .response(response), .suspended],
                                   fallback: { _ in AK.response() })
        let store = keptStore(service, clock: clock, pollSeconds: 0.05)
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        store.windowDidShow()
        try await akEventually { service.calls.count == 3 && !store.isLoading }
        clock.milliseconds += 60_000
        // This must run before the first 50 ms poll; the deadline is only 15 ms away.
        try await akEventually(timeout: .milliseconds(40)) { service.isSuspended(3) }
        #expect(store.remainingSeconds == 0 && !store.canShoot)
        #expect(store.state == snapshot && store.state?.currentPlayer == .black)
        #expect(store.state?.revision == snapshot.revision && store.state?.shotCount == 0)
        store.windowDidHide()
        service.resume(3, returning: AlkkagiResponse(status: .ok, serverNowMs: clock.milliseconds))
        try await akEventually { !store.isLoading }
        #expect(service.calls.last == .state(matchID: AK.matchID, sinceChatSeq: 0))
        #expect(store.state == snapshot, "Only a later authoritative snapshot may change turns")
    }

    // check 통합(PR #9 를 받으며): 판 중 걸음은 판 상태만 — 로비(사람 목록)를 걸음마다 부르지 않는다.
    @Test func kept_pollingDuringAMatchReadsOnlyTheMatch() async throws {
        let service = AKScript(fallback: { _ in AK.response(AK.match()) })
        let store = keptStore(service, pollSeconds: 0.01)
        defer { store.reset(); service.finish() }
        store.windowDidShow()
        try await akEventually { service.calls.count >= 8 && !store.isLoading }
        store.windowDidHide()
        try await akEventually { !store.isLoading }
        let lobbies = service.calls.filter { if case .lobby = $0 { true } else { false } }.count
        let states = service.calls.filter { if case .state = $0 { true } else { false } }.count
        #expect(lobbies == 1, "창을 열 때 한 번만 — 판 중 걸음은 로비를 부르지 않는다(실제 \(lobbies))")
        #expect(states >= 6)
    }

    // v2(§4.3 · DF#37): 판 밖 걸음은 0.3.80 처럼 걸음마다 가벼운 로비를 읽지 않는다 — 신청은 초인종이 데려오고, 안전망은 전체 로비
    // 30초다(시계를 멈춘 채라 창을 열 때 한 번뿐). 걸음이 빠르게 돌아도 조회는 그 한 번이다.
    @Test func kept_pollingWithoutAMatchRefreshesPeopleAtMostEveryThirtySeconds() async throws {
        let clock = AKClock()
        let service = AKScript(fallback: { _ in AK.response() })
        let store = keptStore(service, clock: clock, pollSeconds: 0.01)
        defer { store.reset(); service.finish() }
        store.windowDidShow()
        try await akEventually { service.calls.count >= 1 && !store.isLoading }
        try await Task.sleep(for: .milliseconds(80))                 // 걸음 여러 번(10ms)
        store.windowDidHide()
        try await akEventually { !store.isLoading }
        #expect(service.calls == [.lobby(users: true)], "판 밖 걸음이 30초 전에 로비를 또 읽었다(\(service.calls.count))")
        clock.advance(30)
        store.windowDidShow()                                        // 창을 다시 열면 한 번 + 30초가 지난 걸음
        try await akEventually { !store.isLoading && service.calls.count >= 2 }
        store.windowDidHide()
        #expect(service.calls.allSatisfy { $0 == .lobby(users: true) })
    }

    // v2: 판 밖 걸음이 조회를 안 하므로 판 중 걸음(박자마다 판 상태)으로 잰다.
    @Test func kept_hidingAndClosingStopPollsAndShowingTwiceDoesNotDuplicateThem() async throws {
        let service = AKScript(fallback: { _ in AK.response(AK.match()) })
        let store = keptStore(service, pollSeconds: 0.01)
        defer { store.reset(); service.finish() }
        store.windowDidShow()
        store.windowDidShow()
        try await akEventually { service.calls.count >= 2 && !store.isLoading }
        store.windowDidHide()
        try await akEventually { !store.isLoading }
        let hiddenCount = service.calls.count
        try await Task.sleep(for: .milliseconds(35))
        #expect(service.calls.count == hiddenCount && !store.isWindowVisible)
        store.windowDidShow()
        try await akEventually { service.calls.count >= hiddenCount + 2 && !store.isLoading }
        store.windowDidClose()
        try await akEventually { !store.isLoading }
        let closedCount = service.calls.count
        try await Task.sleep(for: .milliseconds(35))
        #expect(service.calls.count == closedCount && !store.isWindowVisible)
        #expect(service.maxConcurrentCalls == 1)
    }

    @Test func kept_occlusionStopsPollingAndResetCancelsTheResumedPoll() async throws {
        let service = AKScript(fallback: { _ in AK.response(AK.match()) })
        let store = keptStore(service, pollSeconds: 0.01)
        defer { store.reset(); service.finish() }
        store.windowDidShow()
        try await akEventually { service.calls.count >= 2 && !store.isLoading }
        store.windowOcclusionDidChange(visible: false)
        try await akEventually { !store.isLoading }
        let occludedCount = service.calls.count
        try await Task.sleep(for: .milliseconds(35))
        #expect(store.isWindowVisible && store.isWindowOccluded)
        #expect(service.calls.count == occludedCount)
        service.enqueue(.suspended)
        store.windowOcclusionDidChange(visible: true)
        try await akEventually { service.isSuspended(occludedCount) }
        #expect(!store.isWindowOccluded)
        store.reset()
        try await akEventually { service.cancelledRequests.contains(occludedCount) }
        service.resume(occludedCount, returning: AK.response(AK.match()))
        try await Task.sleep(for: .milliseconds(35))
        #expect(service.calls.count == occludedCount + 1)
        #expect(store.state == nil && !store.isWindowVisible && !store.isLoading)
    }

    @Test func kept_unknownProtocolPhaseResultAndStatusFailClosed() async throws {
        let decoder = JSONDecoder()
        let unknownPhase = try decoder.decode(AlkkagiMatchPhase.self, from: Data("\"future_phase\"".utf8))
        let unknownResult = try decoder.decode(AlkkagiMatchResult.self, from: Data("\"future_result\"".utf8))
        let unknownStatus = try decoder.decode(AlkkagiRPCStatus.self, from: Data("\"future_status\"".utf8))
        #expect(unknownPhase == .unknown && unknownResult == .unknown && unknownStatus == .unknown)
        let valid = AK.match()
        var protocolMismatch = AK.response(valid)
        protocolMismatch.protocolVersion = 1                // v2 앱이 v1 서버를 만남(VC-8 ①)
        var badPhase = valid
        badPhase.phase = unknownPhase
        var badResult = valid
        badResult.phase = .finished
        badResult.result = unknownResult
        for rejected in [protocolMismatch, AK.response(badPhase), AK.response(badResult),
                         AlkkagiResponse(status: unknownStatus, serverNowMs: AK.nowMs),
                         AlkkagiResponse(status: .unsupportedClient, serverNowMs: AK.nowMs)] {
            let service = AKScript([.response(AK.response(valid)), .response(rejected)])
            let store = keptStore(service)
            defer { store.reset(); service.finish() }
            await store.refreshLobby()
            #expect(store.canShoot)
            await store.refreshMatch()
            #expect(store.state == valid && store.notice != nil)
            #expect(!store.canShoot && !store.canPlace)
            await store.shoot(stoneID: 0, pull: AK.vector(0, 80))
            await store.sendChat(body: "must not send")
            #expect(service.calls.count == 2)
        }
    }

    @Test func kept_malformedCheckpointsAreRejectedWithoutReplacingTheLastValidBoard() async throws {
        let valid = AK.match()
        #expect(valid.canonicalGame != nil)
        let corruptions: [(String, (inout AlkkagiMatch) -> Void)] = [
            ("negative revision", { $0.revision = -1 }),
            ("negative chat cursor", { $0.chatSeq = -1 }),
            ("nonfinite deadline", { $0.deadlineMs = .infinity }),
            ("placement exposes opponent stones", { $0.phase = .placing }),
            ("unfinished result", { $0.result = .black }),
            ("missing finished result", { $0.phase = .finished }),
            ("duplicate stone IDs", { $0.stones[1] = $0.stones[0] }),
            ("owner disagrees with stone ID", {
                $0.stones[0] = AlkkagiGame.Stone(id: 0, owner: .white, position: AK.vector(100, 100))
            }),
            ("invalid stone ID", {
                $0.stones[0] = AlkkagiGame.Stone(id: 10, owner: .black, position: AK.vector(100, 400))
            }),
            ("nonfinite position", { $0.stones[0].position.x = .nan }),
            ("nonfinite velocity", { $0.stones[0].velocity.y = .infinity }),
            ("live stone outside board", { $0.stones[0].position.x = -1 }),
            ("moving unplaced stone", {
                $0.stones[0].isPlaced = false
                $0.stones[0].velocity.x = 1
            }),
            ("unplaced ring-out", { $0.stones[0].isPlaced = false; $0.stones[0].isOut = true }),
            ("negative shot count", { $0.shotCount = -1 }),
            ("overflowing shot count", { $0.shotCount = Int.max })
        ]
        for (reason, corrupt) in corruptions {
            var malformed = valid
            corrupt(&malformed)
            #expect(malformed.canonicalGame == nil, "Rejected checkpoint: \(reason)")
            let service = AKScript([.response(AK.response(valid)),
                                        .response(AK.response(malformed))])
            let store = keptStore(service)
            defer { store.reset(); service.finish() }
            await store.refreshLobby()
            await store.refreshMatch()
            #expect(store.state == valid && !store.canShoot && store.notice != nil, "Rejected checkpoint: \(reason)")
        }
    }

    @Test func kept_shotReplayIsDeterministicAndCannotReplaceTheAuthoritativeCheckpoint() async throws {
        let response = try JSONDecoder().decode(AlkkagiResponse.self, from: Data(keptWireJSON.utf8))
        let snapshot = try #require(response.state)
        let service = AKScript([.response(response)])
        let store = keptStore(service)
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        var slower = try #require(store.state?.shotReplayGame)
        var faster = try #require(store.state?.shotReplayGame)
        #expect(slower.phase == .rolling && slower.currentPlayer == .black && slower.shotCount == 1)
        var slowImpacts: [AlkkagiGame.Impact] = []
        var fastImpacts: [AlkkagiGame.Impact] = []
        for _ in 0..<90 { slowImpacts += slower.advance(dt: 1.0 / 30) }
        for _ in 0..<432 { fastImpacts += faster.advance(dt: 1.0 / 144) }
        #expect(slower.phase == .aiming && slower.currentPlayer == .white)
        #expect(slower.result == nil && slower.shotCount == 1)
        #expect(slower.stones.first { $0.id == 5 }?.isOut == true)
        #expect(slower.stones.first { $0.id == 6 }?.isOut == false)
        #expect(slower.phase == faster.phase && slower.currentPlayer == faster.currentPlayer)
        #expect(slower.result == faster.result && slower.shotCount == faster.shotCount)
        #expect(slowImpacts.contains { $0.isRingOut } && slowImpacts.contains { !$0.isRingOut })
        #expect(slowImpacts.count == fastImpacts.count)
        for (slow, fast) in zip(slower.stones, faster.stones) {
            #expect(slow.id == fast.id && slow.isOut == fast.isOut)
            #expect((slow.position - fast.position).length < 1e-8)
            #expect((slow.velocity - fast.velocity).length < 1e-8)
        }
        #expect(store.state == snapshot && store.state?.phase == .rolling)
        #expect(store.remainingSeconds == 30 && service.calls.count == 1)
        var badShot = snapshot
        badShot.shot?.steps = -1
        #expect(badShot.shotReplayGame == nil)
        badShot = snapshot
        badShot.shot?.pull = AK.vector(.nan, 10)
        #expect(badShot.shotReplayGame == nil)
        badShot = snapshot
        badShot.shot?.initialStones.append(snapshot.shot!.initialStones[0])
        #expect(badShot.shotReplayGame == nil)
    }

    @Test func kept_incomingInviteExpiresWhileTheWindowIsClosedWithoutStartingPolls() async throws {
        let clock = AKClock()
        var response = AK.response()
        response.me = AK.black
        response.incoming = [AK.invite(expiresAtMs: AK.nowMs + 20)]
        let expired = AlkkagiResponse(status: .ok, serverNowMs: AK.nowMs + 60_001, incoming: [])
        let service = AKScript([.response(response)], fallback: { _ in expired })
        let store = keptStore(service, clock: clock, pollSeconds: 0.01)
        var notifications = 0
        store.onInviteArrived = { _ in notifications += 1 }
        defer { store.reset(); service.finish() }
        await store.refreshLobby()
        #expect(store.incoming.count == 1 && notifications == 1 && !store.isWindowVisible)
        // A short deadline keeps the test fast; the injected clock crosses the real 60 s lifetime.
        clock.milliseconds += 60_001
        try await akEventually(timeout: .milliseconds(150)) { store.incoming.isEmpty }
        #expect(!store.isWindowVisible && notifications == 1)
        #expect(service.calls.count <= 2, "Local cleanup or one deadline RPC is enough; no hidden-window polling")
        let settledCount = service.calls.count
        try await Task.sleep(for: .milliseconds(35))
        #expect(service.calls.count == settledCount)
    }


    private func keptStore(_ service: AKScript, clock: AKClock = AKClock(), pollSeconds: Double = 0.02) -> AlkkagiOnlineStore {
        let store = AlkkagiOnlineStore(service: service, clock: { clock.date }, pollSeconds: pollSeconds)
        store.outsidePollStepSeconds = pollSeconds
        return store
    }

    private func keptMessage(_ seq: Int, _ body: String) -> AlkkagiChatMessage {
        AlkkagiChatMessage(seq: seq, senderID: AK.white.id, body: body, sentAtMs: AK.nowMs)
    }
}

/// 원문 snake 키 판(돌은 서버처럼 `isOut` · `isPlaced`) — 두 디코더 모두로 읽힌다. v2 응답이라 protocol 2.
private let keptWireJSON = """
{
  "status": "ok", "protocol": 2, "server_now_ms": 1000000,
  "me": {
    "id": "00000000-0000-4000-8000-000000000001", "display_name": "Black",
    "avatar_url": "https://example.invalid/avatar.png"
  },
  "users": [{"id": "00000000-0000-4000-8000-000000000002", "display_name": "White", "character_id": "turtle"}],
  "incoming": [{
    "id": "00000000-0000-4000-8000-000000000010", "expires_at_ms": 1060000,
    "opponent": {"id": "00000000-0000-4000-8000-000000000002", "display_name": "White"}
  }],
  "state": {
    "id": "00000000-0000-4000-8000-000000000010", "revision": 7, "phase": "rolling",
    "current_player": "black", "my_color": "black",
    "black": {"id": "00000000-0000-4000-8000-000000000001", "display_name": "Black"},
    "white": {"id": "00000000-0000-4000-8000-000000000002", "display_name": "White"},
    "stones": [
      {"id": 0, "owner": "black", "position": {"x": 300, "y": 460}, "velocity": {"x": 0, "y": 0}, "isOut": false, "isPlaced": true},
      {"id": 5, "owner": "white", "position": {"x": 300, "y": 140}, "velocity": {"x": 0, "y": 0}, "isOut": false, "isPlaced": true},
      {"id": 6, "owner": "white", "position": {"x": 120, "y": 100}, "velocity": {"x": 0, "y": 0}, "isOut": false, "isPlaced": true}
    ],
    "deadline_ms": 1030000, "shot_count": 1, "result": null, "finish_reason": null,
    "chat_seq": 2, "chat": [{"seq": 2, "sender_id": "00000000-0000-4000-8000-000000000002", "body": "hello", "sent_at_ms": 999990}],
    "muted": false,
    "shot": {
      "id": "shot-1", "stone_id": 0, "pull": {"x": 0, "y": 135}, "started_at_ms": 1000000, "steps": 720,
      "initial_stones": [
        {"id": 0, "owner": "black", "position": {"x": 300, "y": 460}, "velocity": {"x": 0, "y": 0}, "isOut": false, "isPlaced": true},
        {"id": 5, "owner": "white", "position": {"x": 300, "y": 140}, "velocity": {"x": 0, "y": 0}, "isOut": false, "isPlaced": true},
        {"id": 6, "owner": "white", "position": {"x": 120, "y": 100}, "velocity": {"x": 0, "y": 0}, "isOut": false, "isPlaced": true}
      ]
    }
  }
}
"""
