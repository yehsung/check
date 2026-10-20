import Foundation
import Testing
@testable import CheckCore

// v0.3.60 — 1:1 테트리스 클라 코어(`TetrisWire` · `duelRPC` · `TetrisDuelStore`) 계약. **모양이 아니라 결과를 잰다.**
//
// 서버는 스텁이다(`GomokuStubProtocol` — 호스트별 스크립트). 판 보고(`tetris_report`)는 작은 흉내 서버(`TDServer`)가
// 받는다: seq 를 저장하고(이하면 stale), 첫 보고를 준비로 적고, 둘째 준비면 start_at = 지금 + 3초, 탑아웃이면 상대 승으로
// 닫는다 — 설계서 §2.4 의 순서 그대로. 실서버 왕복(정규화·시간 경과)은 하네스·두 계정 e2e 몫이다.
//
// 호스트는 `WorkTimerStore` 가 아니라 이 파일의 작은 `TDHost` 다(스토어가 실제로 읽는 멤버만 — `GomokuStoreHost`).
// 시계는 **둘 다 주입**이다: 벽시계(`clock` — 서버 시각 보정·신청 만료)와 단조 시계(`uptime` — 판 시계·보고 간격).
// 판 루프·폴링 루프는 3,600초로 재우고 `tick(now:)` · `pollTick(at:)` 을 직접 밟는다(결정적).
//
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례).

// MARK: - 하네스

private let tdMe = "00000000-0000-0000-0000-0000000000a1"
private let tdRival = "00000000-0000-0000-0000-0000000000b2"
private let tdMatch = "7e7e0000-0000-4000-8000-000000000060"
private let tdWall0 = Date(timeIntervalSince1970: 1_800_000_000)
private var tdNowMs: Double { tdWall0.timeIntervalSince1970 * 1000 }

private struct TDError: Error {}

/// nil 을 JSON null 로.
private func tdOpt(_ value: Any?) -> Any { value ?? NSNull() }

/// 테트리스 스토어가 빌리는 호스트(세션·서비스·루비 미러). `withSessionRetry` 는 재시도 없이 한 번 부른다.
@MainActor
private final class TDHost: GomokuStoreHost {
    var session: SupabaseSession?
    var sessionGeneration = 0
    let service: SupabaseWorkService
    var realtimeState: RealtimeState = .idle(.disabled)
    var rubyBalance: Int?

    init(service: SupabaseWorkService, userID: String) {
        self.service = service
        session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
    }

    func withSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T {
        guard let session else { throw TDError() }
        return try await operation(session)
    }

    func classifyAuthError(_ error: Error) -> AuthErrorDisposition { .transient }
}

@MainActor
private enum TDRetention {
    /// 스토어는 호스트를 **약참조**로 든다(제품 계약). 테스트가 버리면 host 가 nil 이 되어 요청이 한 건도 안 나간다.
    static var hosts: [TDHost] = []
}

/// 주입 시계 둘. 격리 없는 참조 타입이라 스토어의 시계 클로저가 그대로 잡는다(테스트는 메인 액터에서만 만진다).
private final class TDClock: @unchecked Sendable {
    var uptime: TimeInterval = 1_000
    var wall: Date = tdWall0
}

/// 판 한 사람(상태 응답의 `me`·`opponent`).
private struct TDPlayer {
    var id: String
    var name: String
    var ready = false
    var seq = 0
    var board: String?
    var lines = 0
    var sent = 0
    var applied = 0
    var pending = 0
    var lastSeenMs: Double?
    var toppedOut = false

    var json: [String: Any] {
        ["id": id, "display_name": name, "avatar_url": NSNull(), "character": NSNull(),
         "ready": ready, "seq": seq, "board": tdOpt(board), "lines": lines, "garbage_sent": sent,
         "garbage_applied": applied, "pending": pending, "last_seen_ms": tdOpt(lastSeenMs),
         "topped_out": toppedOut]
    }
}

/// §2.5 상태 한 벌(서버 `tetris__state` 와 같은 키).
private func tdState(_ status: String = "active", id: String = tdMatch, seed: Int? = 4_242, stake: Int = 3,
                     nowMs: Double = tdNowMs,
                     startAtMs: Double? = nil, me: TDPlayer = TDPlayer(id: tdMe, name: "나"),
                     opponent: TDPlayer = TDPlayer(id: tdRival, name: "라이벌"),
                     result: String? = nil, winner: String? = nil, endReason: String? = nil,
                     ruby: Int = 97) -> [String: Any] {
    ["match_id": id, "status": status, "stake": stake, "seed": tdOpt(seed),
     "server_now_ms": nowMs, "accepted_at_ms": nowMs - 2_000,
     "start_at_ms": tdOpt(startAtMs), "ready_deadline_ms": nowMs + 28_000,
     "max_end_ms": tdOpt(startAtMs.map { $0 + 480_000 }),
     "finished_at_ms": tdOpt(status == "finished" ? nowMs : nil),
     "me": me.json, "opponent": opponent.json,
     "result": tdOpt(result), "winner": tdOpt(winner), "end_reason": tdOpt(endReason),
     "ruby_balance": ruby]
}

private func tdJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func tdEnvelope(_ status: String = "ok", state: [String: Any]) -> String {
    tdJSON(["status": status, "state": state])
}

private func tdDecode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: Data(text.utf8))
}

/// 모양만 아는 PGRST202 본문(`serviceError` 가 "schema cache" 를 보고 `.databaseSchemaMissing` 으로 접는다).
private func tdPGRST202(_ function: String) -> String {
    #"{"code":"PGRST202","details":"Searched for the function public."# + function
        + #" with parameters, but no matches were found in the schema cache.","hint":null,"#
        + #""message":"Could not find the function public."# + function + #" in the schema cache"}"#
}

private let tdDeadlockBody = #"{"code":"40P01","details":null,"hint":null,"message":"deadlock detected"}"#

/// rpc 이름별 응답 스크립트: 줄 세운 응답이 먼저, 그다음 응답기, 그다음 고정 응답. 없으면 nil(→ `[]` 200 — 디코드 실패).
private final class TDScript: @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [String: [GomokuStubProtocol.Reply]] = [:]
    private var standing: [String: GomokuStubProtocol.Reply] = [:]
    private var responders: [String: @Sendable (String) -> GomokuStubProtocol.Reply] = [:]

    func enqueue(_ rpc: String, _ body: String, status: Int = 200, delay: TimeInterval = 0) {
        lock.lock()
        queued[rpc, default: []].append(GomokuStubProtocol.Reply(status: status, body: body, delay: delay))
        lock.unlock()
    }

    func stand(_ rpc: String, _ body: String, status: Int = 200, delay: TimeInterval = 0) {
        lock.lock()
        standing[rpc] = GomokuStubProtocol.Reply(status: status, body: body, delay: delay)
        lock.unlock()
    }

    func respond(_ rpc: String, _ make: @escaping @Sendable (String) -> GomokuStubProtocol.Reply) {
        lock.lock()
        responders[rpc] = make
        lock.unlock()
    }

    var handler: GomokuStubProtocol.Handler {
        { [self] rpc, body, _ in self.reply(rpc, body) }
    }

    private func reply(_ rpc: String, _ body: String) -> GomokuStubProtocol.Reply? {
        lock.lock()
        if var line = queued[rpc], !line.isEmpty {
            let next = line.removeFirst()
            queued[rpc] = line
            lock.unlock()
            return next
        }
        let make = responders[rpc]
        let fixed = standing[rpc]
        lock.unlock()
        return make.map { $0(body) } ?? fixed
    }
}

/// `tetris_report` 흉내 서버(§2.4 의 순서): seq 이하면 stale · 첫 보고 = 준비 · 둘째 준비면 start_at = 지금 + 3초 ·
/// 공격 누계는 단조 · 탑아웃이면 상대 승 topout 정산. 상대 쪽 값은 테스트가 직접 고친다(`opponent`).
private final class TDServer: @unchecked Sendable {
    private let lock = NSLock()
    var nowMs: Double = tdNowMs
    var me = TDPlayer(id: tdMe, name: "나")
    var opponent = TDPlayer(id: tdRival, name: "라이벌", ready: true)
    var startAtMs: Double?
    var status = "active"
    var winner: String?
    var endReason: String?
    var seed = 4_242
    var reports: [[String: Any]] = []

    func edit(_ change: (TDServer) -> Void) {
        lock.lock()
        change(self)
        lock.unlock()
    }

    func state() -> [String: Any] {
        tdState(status, seed: seed, nowMs: nowMs, startAtMs: startAtMs, me: me, opponent: opponent,
                result: winner.map { $0 == tdMe ? "opponent_win" : "challenger_win" }, winner: winner,
                endReason: endReason)
    }

    func report(_ body: String) -> GomokuStubProtocol.Reply {
        lock.lock()
        defer { lock.unlock() }
        let args = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        reports.append(args)
        guard status == "active" else { return GomokuStubProtocol.Reply(body: tdEnvelope("stale", state: state())) }
        if !me.ready {
            me.ready = true
            if opponent.ready, startAtMs == nil { startAtMs = nowMs + 3_000 }
        }
        let seq = args["p_seq"] as? Int ?? 0
        guard seq > me.seq else { return GomokuStubProtocol.Reply(body: tdEnvelope("stale", state: state())) }
        me.seq = seq
        me.board = args["p_board"] as? String
        me.lines = args["p_lines"] as? Int ?? me.lines
        me.sent = max(me.sent, args["p_garbage_sent"] as? Int ?? 0)
        me.applied = args["p_garbage_applied"] as? Int ?? me.applied
        me.pending = args["p_pending"] as? Int ?? me.pending
        if args["p_topped_out"] as? Bool == true {
            me.toppedOut = true
            status = "finished"
            winner = tdRival
            endReason = "topout"
        }
        return GomokuStubProtocol.Reply(body: tdEnvelope("ok", state: state()))
    }

    var reportCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return reports.count
    }

    var lastReport: [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return reports.last ?? [:]
    }
}

/// 첫 호출에만 참(스텁 응답기는 URL 로딩 스레드에서 불린다).
private final class TDFirstCall: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}

@MainActor
private final class TDTally {
    var presents = 0
    var attentionRequests = 0
    var attentions: [TetrisDuelAttention] = []
    var arrived: [TetrisDuelInvite] = []
}

/// 스토어 한 벌. 판 루프·폴링 루프는 재우고(3,600초) 시계는 주입한다.
@MainActor
private func tdMake(_ label: String, script: TDScript) -> (TetrisDuelStore, TDClock, String, TDTally) {
    let host = "v0360-td-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: script.handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
    let owner = TDHost(service: service, userID: tdMe)
    TDRetention.hosts.append(owner)
    let store = TetrisDuelStore(host: owner)
    let clock = TDClock()
    store.clock = { clock.wall }
    store.uptime = { clock.uptime }
    store.pollStepSeconds = 3_600
    store.gameLoopStepSeconds = 3_600
    let tally = TDTally()
    store.presentWindow = { tally.presents += 1 }
    store.requestAttention = { tally.attentionRequests += 1 }
    store.onAttention = { tally.attentions.append($0) }
    store.onInviteArrived = { tally.arrived.append($0) }
    return (store, clock, host, tally)
}

/// 나가 있는 보고가 다 돌아올 때까지(응답 끝자락이 다음 보고를 또 낼 수 있어 되풀이한다). 상한은 재개 횟수다.
@MainActor
private func tdSettle(_ store: TetrisDuelStore) async {
    for _ in 0..<200 {
        guard store.reportInFlight, let task = store.reportTask else { return }
        await task.value
    }
}

@MainActor
private func tdWait(_ resumes: Int = 2_000, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<resumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private func tdCount(_ host: String, _ rpc: String) -> Int { GomokuStubProtocol.count(host: host, rpc: rpc) }

private func tdCalls(_ host: String, _ rpc: String) -> [[String: Any]] {
    GomokuStubProtocol.calls(host: host, rpc: rpc).map(\.json)
}

/// 서버 `tetris_lobby` 의 jsonb 모양 그대로(키·중첩 — 20261021120000_tetris_duel.sql §5.1 의 `jsonb_build_object`).
private func tdLobby(incoming: [[String: Any]] = [], outgoing: [String: Any]? = nil, active: String? = nil,
                     users: [[String: Any]]? = nil) -> String {
    tdJSON([
        "status": "ok", "server_now_ms": tdNowMs, "stakes": [3, 5, 10],
        "me": ["ruby_balance": 100, "wins": 2, "losses": 1, "draws": 0,
               "active_match_id": tdOpt(active), "incoming": incoming, "outgoing": tdOpt(outgoing)],
        "users": users ?? [
            ["id": tdRival, "display_name": "라이벌", "avatar_url": NSNull(), "character": "jelly",
             "is_working": true, "in_match": false, "capable": true, "focus_mode": false],
        ],
        "matches": [] as [Any],
    ])
}

private func tdInvite(_ id: String = tdMatch, peerKey: String, stake: Int = 3, expiresMs: Double = tdNowMs + 60_000)
    -> [String: Any] {
    ["match_id": id, peerKey: ["id": tdRival, "display_name": "라이벌"], "stake": stake, "expires_at_ms": expiresMs]
}

/// 진행 중 판을 들고 **시작까지 지난** 스토어(창 보임 · 준비 보고 · 시작 시각 확정 · 판 시계 0.5초).
@MainActor
private func tdStartedStore(_ label: String) async -> (TetrisDuelStore, TDClock, String, TDServer, TDScript) {
    let script = TDScript()
    let server = TDServer()
    script.stand("tetris_lobby", tdLobby(active: tdMatch))
    script.respond("tetris_report") { server.report($0) }
    let (store, clock, host, _) = tdMake(label, script: script)
    store.applyState(try! tdDecode(TetrisStatePayload.self, tdJSON(server.state())))
    store.windowDidShow()
    await tdSettle(store)
    clock.uptime += 3.5
    store.tick()
    await tdSettle(store)
    return (store, clock, host, server, script)
}

// MARK: - 시험

@Suite("v0.3.60 테트리스 대결 — 와이어 · duelRPC · 스토어")
struct V0360TetrisDuelStoreTests {

    // MARK: 와이어

    @Test("와이어: 서버 모양(로비·상태 봉투)을 그대로 읽고, 모르는 status 는 .unknown 으로 접고, 빠진 키는 nil 이다")
    func wireReadsTheServerShapesAndFoldsUnknownStatus() throws {
        // 없으면: 키 이름 하나(`id` 대 `user_id`, `state` 봉투 대 최상위)가 서버와 어긋나도 디코드가 nil 로 조용히 지나간다.
        let lobby = try tdDecode(TetrisLobbyResponse.self, tdLobby(
            incoming: [tdInvite(peerKey: "from")], outgoing: tdInvite("aaaa", peerKey: "to", stake: 10)))
        #expect(lobby.status == .ok)
        #expect(lobby.stakes == [3, 5, 10])
        #expect(lobby.me?.incoming?.first?.from?.id == tdRival)
        #expect(lobby.me?.incoming?.first?.expiresAtMs == tdNowMs + 60_000)
        #expect(lobby.me?.outgoing?.to?.displayName == "라이벌")
        #expect(lobby.me?.outgoing?.stake == 10)
        #expect(lobby.users?.first?.id == tdRival)
        #expect(lobby.users?.first?.focusMode == false && lobby.users?.first?.capable == true)

        let report = try tdDecode(TetrisActionResponse.self, tdEnvelope("stale", state: tdState(
            startAtMs: tdNowMs + 3_000, opponent: TDPlayer(id: tdRival, name: "라이벌", ready: true, seq: 9,
                                                           board: TetrisDuelBoard.emptyText, sent: 4))))
        #expect(report.status == .stale)
        let state = try #require(report.state, "상태가 `state` 키에서 안 읽혔다")
        #expect(state.matchId == tdMatch && state.seed == 4_242 && state.startAtMs == tdNowMs + 3_000)
        #expect(state.opponent?.garbageSent == 4 && state.opponent?.seq == 9 && state.opponent?.ready == true)
        #expect(state.me?.toppedOut == false)

        // ② 모르는 status 는 접는다 — 디코드가 throw 하지 않는다.
        let odd = try tdDecode(TetrisActionResponse.self, #"{"status":"brand_new_reason"}"#)
        #expect(odd.status == .unknown && odd.state == nil)
        #expect(try tdDecode(TetrisLobbyResponse.self, #"{"status":"zzz"}"#).status == .unknown)
        // ① status 만 필수다.
        let bare = try tdDecode(TetrisActionResponse.self, #"{"status":"ok","state":{"match_id":"x"}}"#)
        #expect(bare.state?.matchId == "x" && bare.state?.me == nil && bare.state?.startAtMs == nil)
        #expect(throws: (any Error).self) { try tdDecode(TetrisActionResponse.self, #"{"state":{}}"#) }
        // 비로그인은 체스의 unauthorized 가 아니라 not_signed_in 이다.
        #expect(try tdDecode(TetrisActionResponse.self, #"{"status":"not_signed_in"}"#).status == .notSignedIn)
    }

    @Test("와이어: 요청 본문의 키 집합이 서버 인자 이름과 같고 p_protocol 을 언제나 싣는다(빈 {} 금지)")
    func requestBodiesCarryTheContractKeys() throws {
        // 없으면: 키 하나가 어긋나면 PostgREST 가 함수를 못 찾아(PGRST202) "곧 열려요" 만 영원히 뜬다.
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        func keys(_ value: some Encodable) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any] ?? [:]
        }
        #expect(Set(try keys(TetrisProtocolRequest()).keys) == ["p_protocol"])
        #expect(Set(try keys(TetrisChallengeRequest(pOpponent: tdRival, pStake: 5)).keys)
                == ["p_protocol", "p_opponent", "p_stake"])
        #expect(Set(try keys(TetrisMatchRequest(pMatchId: tdMatch)).keys) == ["p_protocol", "p_match_id"])
        #expect(Set(try keys(TetrisRespondRequest(pMatchId: tdMatch, pAccept: true)).keys)
                == ["p_protocol", "p_match_id", "p_accept"])
        let report = TetrisDuelReport(seq: 7, board: TetrisDuelBoard.emptyText, lines: 3, garbageSent: 2,
                                      garbageApplied: 1, pending: 4, toppedOut: false)
        let body = try keys(TetrisReportRequest(matchID: tdMatch, report: report))
        #expect(Set(body.keys) == ["p_protocol", "p_match_id", "p_seq", "p_board", "p_lines", "p_garbage_sent",
                                   "p_garbage_applied", "p_pending", "p_topped_out"])
        #expect(body["p_protocol"] as? Int == 1 && TetrisWire.protocolVersion == 1)
        #expect(body["p_seq"] as? Int == 7 && body["p_garbage_sent"] as? Int == 2
                && body["p_garbage_applied"] as? Int == 1 && body["p_pending"] as? Int == 4
                && body["p_topped_out"] as? Bool == false)
        #expect((body["p_board"] as? String)?.count == 200)
    }

    // MARK: duelRPC

    @MainActor
    @Test("duelRPC: 쓰기는 40P01 을 한 번만 다시 보낸다 · 두 번째 교착은 던진다 · 로비(읽기)는 다시 보내지 않는다")
    func duelRPCRetriesADeadlockOnceForWritesOnly() async throws {
        // 없으면: 상금 cron 과 엇갈린 교착 한 번에 신청·보고가 "연결을 확인하세요" 로 떨어진다(재시도 = 같은 요청).
        let script = TDScript()
        script.enqueue("tetris_challenge", tdDeadlockBody, status: 500)
        script.stand("tetris_challenge", tdJSON(["status": "ok", "match_id": tdMatch, "expires_at_ms": tdNowMs + 60_000]))
        script.stand("tetris_resign", tdDeadlockBody, status: 500)
        script.stand("tetris_lobby", tdDeadlockBody, status: 500)
        let (store, _, host, _) = tdMake("deadlock", script: script)
        let service = try #require(store.host?.service)

        let ok = try await service.tetrisChallenge(accessToken: "t", opponentID: tdRival, stake: 3)
        #expect(ok.status == .ok && ok.matchId == tdMatch)
        #expect(tdCount(host, "tetris_challenge") == 2, "교착을 다시 보내지 않았다")
        let challenge = try #require(tdCalls(host, "tetris_challenge").last)
        #expect(challenge["p_protocol"] as? Int == 1 && challenge["p_stake"] as? Int == 3)

        await #expect(throws: (any Error).self) {
            _ = try await service.tetrisResign(accessToken: "t", matchID: tdMatch)
        }
        #expect(tdCount(host, "tetris_resign") == 2, "두 번째 교착에서 멈추지 않았다(재시도는 한 번뿐)")

        await #expect(throws: (any Error).self) { _ = try await service.tetrisLobby(accessToken: "t") }
        #expect(tdCount(host, "tetris_lobby") == 1, "읽기 전용 로비가 교착을 다시 보냈다")
    }

    // MARK: 상태 기계

    @MainActor
    @Test("흐름: 로비 → 신청 → (보낸 신청 5초 조회) 수락 → 준비 → 카운트다운 → 판 → 탑아웃 → 결과 → 로비")
    func theWholeFlowFromChallengeToResult() async throws {
        // 없으면: 각 갈래를 따로 재면 초록인데 이어 붙이면 끊기는 자리(수락을 못 봄 · 준비를 안 냄 · 시작을 못 셈)가 숨는다.
        let script = TDScript()
        let server = TDServer()
        script.stand("tetris_lobby", tdLobby())
        script.stand("tetris_challenge", tdJSON(["status": "ok", "match_id": tdMatch, "expires_at_ms": tdNowMs + 60_000,
                                                "ruby_balance": 100, "server_now_ms": tdNowMs]))
        script.respond("tetris_report") { server.report($0) }
        let (store, clock, host, tally) = tdMake("flow", script: script)

        await store.refreshLobby()
        #expect(store.phase == .lobby && store.users.map(\.id) == [tdRival])
        #expect(store.record == TetrisDuelRecord(wins: 2, losses: 1, draws: 0))
        let rival = try #require(store.users.first)
        #expect(rival.canBeChallenged && rival.characterID == "jelly")

        await store.challenge(userID: tdRival, stake: .three)
        let sent = try #require(store.outgoing)
        #expect(sent.id == tdMatch && sent.stake == 3 && sent.peer.displayName == "라이벌")
        #expect(store.notice == "신청을 보냈어요")
        #expect(tdCalls(host, "tetris_challenge").first?["p_opponent"] as? String == tdRival)

        // 보낸 신청 조회는 창이 보일 때만, 5초마다. 상대가 수락했다(서버: active · seed · 둘 다 준비 전).
        server.edit { $0.opponent.ready = false }
        script.stand("tetris_state", tdEnvelope(state: server.state()))
        await store.pollTick(at: clock.wall.addingTimeInterval(60))
        #expect(tdCount(host, "tetris_state") == 0 && tdCount(host, "tetris_lobby") == 1, "창이 안 보이는데 폴링했다")
        store.isWindowVisible = true
        await store.pollTick(at: clock.wall.addingTimeInterval(1))
        #expect(tdCount(host, "tetris_state") == 0, "5초 전에 보낸 신청을 다시 읽었다")
        await store.pollTick(at: clock.wall.addingTimeInterval(6))
        #expect(tdCount(host, "tetris_state") == 1)
        #expect(store.outgoing == nil, "수락된 신청 카드가 남았다")
        #expect(store.match?.id == tdMatch && store.match?.seed == 4_242 && store.match?.isFinished == false)
        #expect(store.phase == .ready)
        #expect(tally.presents == 1 && tally.attentionRequests == 1, "판이 열렸는데 창을 안 띄웠다")
        #expect(tally.attentions.isEmpty, "창이 보이는데 말풍선 문까지 열었다")
        #expect(store.duel?.seed == 4_242 && store.duelMatchID == tdMatch)
        #expect(store.notice == nil, "로비 안내가 판 상태줄을 가린다")

        // 준비 = 첫 보고(창이 보이므로 곧바로). 상대는 아직 준비 전 → 시작 시각 없음.
        store.tick()
        await tdSettle(store)
        #expect(server.reportCount == 1)
        #expect(server.lastReport["p_seq"] as? Int == 1 && server.lastReport["p_topped_out"] as? Bool == false)
        #expect(store.match?.meReady == true && store.match?.startAt == nil)
        #expect(store.phase == .ready)

        // 상대가 준비했다 → 다음 하트비트 응답에 start_at = 지금 + 3초.
        server.edit { $0.opponent.ready = true; $0.startAtMs = $0.nowMs + 3_000 }
        clock.uptime += 1.0
        store.tick()
        await tdSettle(store)
        #expect(server.reportCount == 2)
        #expect(store.phase == .countdown)
        let left = try #require(store.countdownSeconds())
        #expect(abs(left - 3) < 1e-6, "카운트다운이 응답을 받은 단조 시각 + 3초가 아니다: \(left)")

        clock.uptime += 3.2
        store.tick()
        #expect(store.phase == .playing)
        #expect(store.duel?.isLive == true)
        #expect(abs((store.matchElapsedSeconds() ?? -1) - 0.2) < 1e-6)
        await tdSettle(store)

        // 탑아웃 → 곧바로 보고(topped_out) → 서버가 상대 승으로 닫는다 → 결과.
        var lost = try #require(store.duel)
        var t = clock.uptime
        while !lost.toppedOut, t < clock.uptime + 600 {
            t += 0.25
            lost.advance(to: t)
            lost.hardDrop()
        }
        #expect(lost.toppedOut, "전제: 하드드롭만 하면 언젠가 꼭대기에 닿는다")
        store.duel = lost
        clock.uptime = t
        store.tick()
        await tdSettle(store)
        #expect(server.lastReport["p_topped_out"] as? Bool == true)
        let result = try #require(store.match)
        #expect(result.isFinished && result.outcome == .lost && result.endReason == .topout)
        #expect(result.rubyDelta == -3)
        #expect(store.phase == .finished)
        #expect(store.duel?.finished == true, "정산 뒤에도 판이 흐른다")
        await tdWait { tdCount(host, "tetris_lobby") >= 2 }
        #expect(tdCount(host, "tetris_lobby") >= 2, "끝난 순간 전적(로비)을 다시 읽지 않았다")

        // 끝난 뒤로는 보고가 안 나간다.
        let reportsAtEnd = server.reportCount
        clock.uptime += 5
        store.tick()
        await tdSettle(store)
        #expect(server.reportCount == reportsAtEnd, "닫힌 판에 보고를 냈다")

        store.backToLobby()
        #expect(store.phase == .lobby && store.match == nil && store.duel == nil && store.myStats == nil)
        #expect(store.dismissedMatchIDs.contains(tdMatch))
        store.reset()
    }

    @MainActor
    @Test("받은 신청: 로비 배열 → 도착 문 한 번 · 차단한 사람은 화면에서 빠짐 · 수락하면 카드가 전부 걷히고 판이 선다")
    func incomingInvitesAndAccept() async throws {
        // 없으면: 로비를 다시 읽을 때마다 말풍선이 또 뜨거나, 수락 뒤에도 배너가 남아 두 번째 수락을 부른다.
        let script = TDScript()
        let other = "7e7e0000-0000-4000-8000-0000000000aa"
        script.stand("tetris_lobby", tdLobby(incoming: [tdInvite(peerKey: "from", stake: 5),
                                                         tdInvite(other, peerKey: "from", stake: 3)]))
        script.stand("tetris_respond", tdJSON(["status": "ok", "accepted": true, "state": tdState(stake: 5)]))
        let (store, _, host, tally) = tdMake("incoming", script: script)

        await store.refreshLobby()
        await store.refreshLobby()
        #expect(store.incoming.map(\.id) == [tdMatch, other])
        #expect(tally.arrived.map(\.id) == [tdMatch, other], "같은 신청이 두 번 도착했다: \(tally.arrived.map(\.id))")
        #expect(store.visibleIncoming?.id == tdMatch && store.visibleIncoming?.stake == 5)
        #expect(store.incoming.first?.peer.characterID == "jelly", "신청한 사람의 캐릭터를 로비 목록에서 못 빌렸다")
        store.hiddenPeerIDs = [tdRival]
        #expect(store.visibleIncoming == nil && store.visibleIncomingInvites.isEmpty && store.visibleUsers.isEmpty)
        #expect(store.incoming.count == 2, "차단 거울이 코어 목록을 지웠다(파생값만 걸러야 한다)")
        store.hiddenPeerIDs = []

        await store.respond(inviteID: tdMatch, accept: true)
        #expect(tdCalls(host, "tetris_respond").first?["p_accept"] as? Bool == true)
        #expect(store.incoming.isEmpty, "수락 뒤에도 다른 신청 카드가 남았다(서버는 둘이 낀 대기 신청을 전부 닫는다)")
        #expect(store.match?.id == tdMatch && store.match?.stake == 5 && store.phase == .ready)
        #expect(store.notice == nil, "수락 성공을 말했다(판이 곧바로 열린다)")
        #expect(tally.presents >= 1)
        // 창이 안 보이는 사람에게는 말풍선 문도 열린다(판 id 마다 한 번).
        #expect(tally.attentions.map(\.matchID) == [tdMatch])
        store.applyState(try tdDecode(TetrisStatePayload.self, tdJSON(tdState(stake: 5))))
        #expect(tally.attentions.count == 1, "같은 판의 시작을 두 번 알렸다")
        store.reset()
    }

    @MainActor
    @Test("보낸 신청이 거절·만료로 끝나면 카드를 걷고 한 줄 안내 · 모르는 판 상태는 아무것도 바꾸지 않는다")
    func declinedExpiredAndUnknownMatchStatus() async throws {
        // 없으면: 서버가 어휘를 넓히는 날(예: 'paused') 진행 중 판이 '거절된 신청' 갈래로 떨어져 판이 사라진다.
        let script = TDScript()
        script.stand("tetris_challenge", tdJSON(["status": "ok", "match_id": tdMatch, "expires_at_ms": tdNowMs + 60_000]))
        let (store, _, _, _) = tdMake("declined", script: script)
        await store.challenge(userID: tdRival, stake: .five)
        #expect(store.outgoing?.stake == 5)
        store.applyState(try tdDecode(TetrisStatePayload.self, tdJSON(tdState("declined"))))
        #expect(store.outgoing == nil && store.notice == TetrisDuelNoticeText.inviteDeclined)

        await store.challenge(userID: tdRival, stake: .three)
        store.applyState(try tdDecode(TetrisStatePayload.self, tdJSON(tdState("expired"))))
        #expect(store.outgoing == nil && store.notice == TetrisDuelNoticeText.inviteTimedOut)

        // 진행 중 판을 든 채로 모르는 status 가 온다 → 무시.
        store.applyState(try tdDecode(TetrisStatePayload.self, tdJSON(tdState())))
        let before = store.match
        #expect(before != nil)
        let outcome = store.applyState(try tdDecode(TetrisStatePayload.self, tdJSON(tdState("paused"))))
        #expect(outcome == .ignored)
        #expect(store.match == before && store.phase == .ready && store.duel != nil)
        // 모르는 끝난 사유는 nil 로 접되 결과(승패·루비)는 선다.
        store.applyState(try tdDecode(TetrisStatePayload.self, tdJSON(tdState(
            "finished", result: "challenger_win", winner: tdMe, endReason: "meteor_strike"))))
        #expect(store.match?.isFinished == true && store.match?.endReason == nil)
        #expect(store.match?.outcome == .won && store.match?.rubyDelta == DuelFee.winnerNet(stake: 3))
        #expect(store.match?.rubyDelta == 2)
        store.reset()
    }

    @MainActor
    @Test("모르는 status 응답(쓰기) → 일반 실패 문구 · unsupported_client → 업데이트 상태 · PGRST202 → 곧 열려요 · ok 로비가 되살린다")
    func unknownStatusAndAvailabilityStates() async throws {
        // 없으면: 디코드 실패·옛 앱·db push 전 창이 전부 같은 "연결을 확인하세요" 로 뭉개진다.
        let script = TDScript()
        script.enqueue("tetris_challenge", #"{"status":"brand_new_reason"}"#)
        script.enqueue("tetris_lobby", #"{"status":"unsupported_client","server_now_ms":1}"#)
        script.enqueue("tetris_lobby", tdPGRST202("tetris_lobby"), status: 404)
        script.enqueue("tetris_lobby", tdLobby())
        let (store, _, _, _) = tdMake("unknown", script: script)

        await store.challenge(userID: tdRival, stake: .three)
        #expect(store.notice == TetrisDuelNoticeText.tryAgain && store.outgoing == nil)
        #expect(!store.isBusy)

        await store.refreshLobby()
        #expect(store.availability == .updateRequired && store.notice == TetrisDuelNoticeText.updateMine)
        #expect(store.lobbyLoadFailed)
        await store.refreshLobby()
        #expect(store.availability == .serverMissing && store.notice == TetrisDuelNoticeText.unavailable)
        await store.refreshLobby()
        #expect(store.availability == .available && !store.lobbyLoadFailed && store.hasLoadedLobby)
        store.reset()
    }

    // MARK: 준비 · 보고 주기

    @MainActor
    @Test("준비는 창이 화면에 떠 있을 때만 · 숨긴 창에서는 보고 0건 · 창이 뜨는 순간 곧바로")
    func readyWaitsForAVisibleWindow() async throws {
        // 없으면: 잠든 맥·못 띄운 창에서도 준비가 나가 카운트다운이 아무도 안 보는 판을 연다(D4 의 no_show 환불이 죽는다).
        let script = TDScript()
        let server = TDServer()
        script.respond("tetris_report") { server.report($0) }
        script.stand("tetris_lobby", tdLobby(active: tdMatch))
        let (store, clock, _, _) = tdMake("ready", script: script)
        store.applyState(try tdDecode(TetrisStatePayload.self, tdJSON(server.state())))
        #expect(store.phase == .ready && !store.isWindowVisible)
        for _ in 0..<5 {
            clock.uptime += 1.5
            store.tick()
        }
        await tdSettle(store)
        #expect(server.reportCount == 0, "창이 안 보이는데 준비를 냈다")

        store.windowDidShow()
        await tdSettle(store)
        #expect(server.reportCount == 1, "창이 떴는데 준비가 곧바로 안 나갔다")
        #expect(store.phase == .countdown, "상대가 이미 준비했는데 시작 시각을 못 받았다")

        // 한 번 준비한 뒤로는 창을 숨겨도 판이 흐르고 하트비트가 나간다(D10).
        store.windowDidHide()
        clock.uptime += 4
        store.tick()
        await tdSettle(store)
        #expect(store.phase == .playing, "창을 숨겼더니 판이 멈췄다")
        #expect(server.reportCount == 2, "숨긴 창에서 하트비트가 멈췄다 — 15초 뒤 연결 끊김 패")
        store.reset()
    }

    @MainActor
    @Test("보고 주기(주입 시계): 1초 하트비트 · 0.5초엔 없음 · 공격은 0.25초 바닥 뒤 곧바로 · 한 번에 하나만")
    func reportCadenceWithAnInjectedClock() async throws {
        // 없으면: 매 틱 보고(무료 플랜 폭주) · 공격을 1초 하트비트까지 묵힘 · 응답을 안 기다리고 겹쳐 쏘기가 초록으로 지나간다.
        let (store, clock, host, server, script) = await tdStartedStore("cadence")
        #expect(store.phase == .playing)
        let base = server.reportCount
        let t0 = try #require(store.duel?.lastReportAt)

        store.tick(now: t0 + 0.5)
        await tdSettle(store)
        #expect(server.reportCount == base, "1초 전에 하트비트를 냈다")
        store.tick(now: t0 + 1.0)
        await tdSettle(store)
        #expect(server.reportCount == base + 1, "1초에 하트비트가 안 나갔다")
        let heartbeat = server.lastReport["p_seq"] as? Int ?? 0

        // 오른쪽 끝만 빈 4줄 + 세로 I → 하드드롭 한 번에 4줄(공격 4).
        let game = TetrisGame(seed: 4, board: TetrisGame.boardFixture(bottomRows: Array(repeating: "IIIIIIIII.", count: 4)),
                              active: TetrisGame.ActivePiece(piece: .i, rotation: .right, column: 7,
                                                             row: TetrisGame.spawnRow))
        // 판 시계 0.1초에 서 있고, 방금(t0 + 1.0) 하트비트를 낸 판으로 갈아 끼운다(번호는 서버와 같은 heartbeat).
        var fixture = TetrisDuelSession(seed: 4, startedGame: game, startAt: t0 + 0.9, simulated: 0.1)
        fixture.adoptServerSeq(heartbeat - 1)
        _ = fixture.makeReport(at: t0 + 1.0)
        #expect(fixture.seq == heartbeat && fixture.lastReportAt == t0 + 1.0)
        store.duel = fixture
        clock.uptime = t0 + 1.0
        store.hardDrop()
        #expect(store.myStats?.attackSent == 4 && store.myStats?.lines == 4)
        await tdSettle(store)
        #expect(server.reportCount == base + 1, "최소 간격 0.25초 안에 공격 보고를 냈다")
        store.tick(now: t0 + 1.1)
        await tdSettle(store)
        #expect(server.reportCount == base + 1)
        store.tick(now: t0 + 1.25)
        await tdSettle(store)
        #expect(server.reportCount == base + 2, "공격 보고가 0.25초 바닥 뒤 곧바로 안 나갔다")
        #expect(server.lastReport["p_garbage_sent"] as? Int == 4 && server.lastReport["p_lines"] as? Int == 4)
        #expect(server.lastReport["p_seq"] as? Int == heartbeat + 1)
        store.tick(now: t0 + 1.6)
        await tdSettle(store)
        #expect(server.reportCount == base + 2, "같은 누계로 또 곧바로 보냈다")

        // 한 번에 하나: 응답이 0.3초 늦는 동안 몇 번을 불러도 두 번째가 안 나간다.
        script.respond("tetris_report") { body in
            var reply = server.report(body)
            reply.delay = 0.3
            return reply
        }
        store.tick(now: t0 + 2.3)
        await tdWait { tdCount(host, "tetris_report") == base + 3 }     // 요청이 스텁에 닿았다(답은 0.3초 뒤)
        #expect(store.reportInFlight)
        // 여섯 번 부르며 하트비트 간격(1초)을 두 번 넘긴다 — 겹쳐 나가면 여기서 건이 더 나간다.
        // 멎음 문턱(`reportStallSeconds` 3초) 안에서만 부른다: 그 너머는 일부러 버리고 새로 내는 자리다(아래 멎은 보고 시험).
        for step in 1...6 { store.tick(now: t0 + 2.3 + Double(step) * 0.45) }
        #expect(store.reportInFlight, "전제: 아직 첫 보고의 답이 안 왔다")
        await tdSettle(store)
        #expect(!store.reportInFlight)
        #expect(tdCount(host, "tetris_report") == base + 3, "보고가 겹쳐 나갔다(\(tdCount(host, "tetris_report") - base - 3)건 더)")
        store.reset()
    }

    // MARK: 늦은 응답 · 공격 차분

    @MainActor
    @Test("늦은 응답: 보고 응답(새것) 뒤에 도착한 상태 조회(옛것)는 버린다 · 더 새 상태는 받는다 · 리셋 뒤 응답은 버린다")
    func lateResponsesAreDropped() async throws {
        // 없으면: 초인종 조회가 보고보다 늦게 와 상대 판이 한 박자 전으로 되돌아가고, 로그아웃 뒤 응답이 다음 사람 화면에 판을 세운다.
        let (store, clock, host, server, script) = await tdStartedStore("late")
        let boardA = String(repeating: ".", count: 190) + "ZZZZ.ZZZZZ"
        let boardB = String(repeating: ".", count: 180) + "SSSSS.SSSS" + "ZZZZ.ZZZZZ"
        var older = server.state()
        older["opponent"] = TDPlayer(id: tdRival, name: "라이벌", ready: true, seq: 3, board: boardA, lines: 1, sent: 2).json
        script.enqueue("tetris_state", tdEnvelope(state: older), delay: 0.4)
        server.edit { $0.opponent = TDPlayer(id: tdRival, name: "라이벌", ready: true, seq: 5, board: boardB, lines: 3, sent: 4) }

        let stateTask = Task { await store.refreshMatch(id: tdMatch) }
        await tdWait { tdCount(host, "tetris_state") >= 1 }
        clock.uptime += 1.2
        store.tick()
        await tdSettle(store)
        #expect(store.match?.opponentBoard.cells == TetrisDuelBoard.decode(boardB))
        #expect(store.myStats?.pendingGarbage == 4)
        await stateTask.value
        #expect(store.match?.opponentBoard.cells == TetrisDuelBoard.decode(boardB), "옛 상태가 상대 판을 되돌렸다")
        #expect(store.match?.opponentBoard.lines == 3 && store.match?.opponentBoard.attackSent == 4)
        #expect(store.duel?.garbageApplied == 4 && store.myStats?.pendingGarbage == 4)

        // ★ 기준선: 더 새 상태(상대 seq 6)는 받는다 — 위 가드가 상태 조회를 통째로 막는 것이 아니다.
        var newer = server.state()
        newer["opponent"] = TDPlayer(id: tdRival, name: "라이벌", ready: true, seq: 6, board: boardA, lines: 5, sent: 4).json
        script.enqueue("tetris_state", tdEnvelope(state: newer))
        await store.refreshMatch(id: tdMatch)
        #expect(store.match?.opponentBoard.cells == TetrisDuelBoard.decode(boardA))
        #expect(store.match?.opponentBoard.lines == 5)

        // 리셋(로그아웃) 중에 나가 있던 보고의 응답은 아무것도 세우지 않는다.
        script.respond("tetris_report") { body in
            var reply = server.report(body)
            reply.delay = 0.3
            return reply
        }
        clock.uptime += 1.2
        store.tick()
        #expect(store.reportInFlight)
        let inflight = store.reportTask
        store.reset()
        await inflight?.value
        #expect(store.match == nil && store.duel == nil && store.phase == .lobby && store.rubyBalance == nil)
    }

    @MainActor
    @Test("stale 보고 응답도 상태는 사실이다 — 상대 판·공격을 옮기고 서버 seq 를 따라잡아 다음 보고가 그 위로 간다")
    func aStaleReportStillCarriesTheTruth() async throws {
        // 없으면: 서버가 이미 더 큰 seq 를 쥔 채(앱을 다시 열었다 · 다른 길로 낸 보고) 매 보고가 stale 로 버려지고,
        // 그 응답에 실린 상대 판·공격까지 같이 버려져 판이 끝날 때까지 상대가 안 보인다.
        let (store, clock, _, server, script) = await tdStartedStore("stale")
        let boardX = String(repeating: ".", count: 190) + "TTTTTTTT.T"
        var ahead = server.state()
        ahead["me"] = TDPlayer(id: tdMe, name: "나", ready: true, seq: 40).json
        ahead["opponent"] = TDPlayer(id: tdRival, name: "라이벌", ready: true, seq: 9, board: boardX, lines: 2, sent: 3).json
        script.enqueue("tetris_report", tdEnvelope("stale", state: ahead))
        clock.uptime += 1.2
        store.tick()
        await tdSettle(store)
        #expect(store.match?.opponentBoard.cells == TetrisDuelBoard.decode(boardX))
        #expect(store.match?.opponentBoard.lines == 2 && store.myStats?.pendingGarbage == 3)
        #expect(store.duel?.seq == 40, "서버 seq 를 따라잡지 않았다 — 다음 보고도 stale 이다")

        server.edit { $0.me.seq = 40 }
        clock.uptime += 1.2
        store.tick()
        await tdSettle(store)
        #expect(server.lastReport["p_seq"] as? Int == 41)
        store.reset()
    }

    @MainActor
    @Test("다른 판의 늦은 응답(끝남·진행 중 모두)은 살아 있는 판을 갈아 치우지 않는다")
    func aLateStateOfAnotherMatchNeverReplacesTheLiveOne() async throws {
        // 없으면: 지난 판(접지 않은)의 늦은 결과가 오면 판 구동기가 버려지고 화면이 옛 판 결과로 넘어간다 — 살아 있는 판을 잃는다.
        let (store, _, _, _, _) = await tdStartedStore("other")
        let live = try #require(store.duel)
        let generation = store.duelGeneration
        let old = "7e7e0000-0000-4000-8000-0000000000ff"
        for status in ["finished", "active"] {
            let outcome = store.applyState(try tdDecode(TetrisStatePayload.self, tdJSON(tdState(
                status, id: old, seed: 1, result: "draw", endReason: status == "finished" ? "time_cap" : nil))))
            #expect(outcome == .ignored, "\(status) 인 다른 판 응답을 받았다")
        }
        #expect(store.match?.id == tdMatch && store.phase == .playing)
        #expect(store.duelGeneration == generation && store.duel?.seed == live.seed, "살아 있는 판 구동기가 갈렸다")
        // ★ 기준선: 그 판이 끝난 **뒤**라면 다른 판(새 판)을 받는다.
        store.applyState(try tdDecode(TetrisStatePayload.self, tdJSON(tdState(
            "finished", result: "draw", endReason: "time_cap"))))
        #expect(store.phase == .finished)
        #expect(store.applyState(try tdDecode(TetrisStatePayload.self, tdJSON(tdState(id: old, seed: 1)))) == .applied)
        #expect(store.match?.id == old && store.duel?.seed == 1 && store.phase == .ready)
        store.reset()
    }

    @MainActor
    @Test("공격 차분: 같은 누계 응답이 겹쳐도 한 번 · 줄어든 누계는 무시 · 시작 전 공격은 시작 뒤 들어감 · 보고의 garbage_applied")
    func opponentAttackDiffIsIdempotent() async throws {
        // 없으면: 하트비트·초인종이 같은 누계를 두 번 실어 오면 방해 줄이 두 배로 올라간다(또는 시작 전 공격이 사라진다).
        let script = TDScript()
        let server = TDServer()
        script.respond("tetris_report") { server.report($0) }
        script.stand("tetris_lobby", tdLobby(active: tdMatch))
        let (store, clock, _, _) = tdMake("garbage", script: script)
        func apply(seq: Int, sent: Int, startAt: Double? = tdNowMs + 3_000) {
            store.applyState(try! tdDecode(TetrisStatePayload.self, tdJSON(tdState(
                startAtMs: startAt, me: TDPlayer(id: tdMe, name: "나", ready: true),
                opponent: TDPlayer(id: tdRival, name: "라이벌", ready: true, seq: seq, sent: sent)))))
        }
        // 카운트다운 중에 온 공격 2 — 판이 아직 없으니 대기열에 못 들어간다.
        apply(seq: 1, sent: 2)
        #expect(store.phase == .countdown)
        #expect(store.myStats?.pendingGarbage == 0)
        #expect(store.duel?.garbageApplied == 0)
        clock.uptime += 3.1
        store.tick()
        #expect(store.phase == .playing)
        #expect(store.myStats?.pendingGarbage == 2, "시작 전에 온 공격이 시작 뒤에도 안 들어갔다")

        apply(seq: 2, sent: 3)
        apply(seq: 2, sent: 3)
        apply(seq: 3, sent: 3)
        #expect(store.myStats?.pendingGarbage == 3, "같은 누계가 두 번 들어갔다")
        apply(seq: 4, sent: 2)
        #expect(store.myStats?.pendingGarbage == 3, "줄어든 누계가 뭔가를 바꿨다")
        apply(seq: 5, sent: 6)
        #expect(store.myStats?.pendingGarbage == 6)
        #expect(store.duel?.garbageApplied == 6)

        store.isWindowVisible = true
        clock.uptime += 1.5
        store.tick()
        await tdSettle(store)
        #expect(server.lastReport["p_garbage_applied"] as? Int == 6)
        #expect(server.lastReport["p_pending"] as? Int == 6)
        store.reset()
    }

    // MARK: 재개 · 멎은 보고 (리뷰 RV1 · RV2)

    @MainActor
    @Test("재개: 앱을 다시 열고 이미 시작한 판에 돌아오면 서버의 내 판·누계에서 다시 선다 — 받아들인 공격은 다시 안 들어온다")
    func reopeningResumesFromTheServerRow() async throws {
        // 없으면: 껐다 켜면 빈 판에서 다시 시작하고 상대 공격 이력 전부가 대기열에 다시 쌓인다
        // (RV1 실측: garbageApplied=12 · pending=12 · 서버 판 153칸 → 재개한 판 16칸).
        let tall = (Array(repeating: "..........", count: 3) + Array(repeating: "IIIIIIIII.", count: 15)
            + ["GGGGGGG.GG", "GGGGGGG.GG"]).joined()
        let script = TDScript()
        let server = TDServer()
        server.edit {
            $0.startAtMs = tdNowMs - 60_000
            $0.me = TDPlayer(id: tdMe, name: "나", ready: true, seq: 60, board: tall, lines: 30, sent: 7, applied: 12,
                             pending: 3, lastSeenMs: tdNowMs - 500)
            $0.opponent = TDPlayer(id: tdRival, name: "라이벌", ready: true, seq: 70, sent: 12, lastSeenMs: tdNowMs - 300)
        }
        script.respond("tetris_report") { server.report($0) }
        script.stand("tetris_lobby", tdLobby(active: tdMatch))
        let (store, clock, _, _) = tdMake("resume", script: script)
        store.applyState(try tdDecode(TetrisStatePayload.self, tdJSON(server.state())), receivedAt: clock.uptime)
        store.tick()
        let duel = try #require(store.duel)
        #expect(duel.garbageApplied == 12, "서버가 이미 받아들였다고 적은 누계를 0 에서 다시 셌다")
        #expect(duel.game.pendingGarbageLines == 3, "이미 받아들인 공격이 다시 들어왔다(\(duel.game.pendingGarbageLines)줄)")
        #expect(TetrisDuelBoard.encode(duel.game) == tall, "재개한 판이 서버가 들고 있는 내 판이 아니다")
        #expect(store.phase == .playing && store.myStats?.lines == 30 && store.myStats?.attackSent == 7)

        // 다음 보고는 서버 seq 위로 · 누계는 그 값에서 잇는다(창이 안 보여도 — 서버가 이미 준비를 받았다).
        await tdSettle(store)
        #expect(server.lastReport["p_seq"] as? Int == 61)
        #expect(server.lastReport["p_garbage_applied"] as? Int == 12 && server.lastReport["p_garbage_sent"] as? Int == 7)
        #expect(server.lastReport["p_board"] as? String == tall && server.lastReport["p_pending"] as? Int == 3)

        // 그 뒤 상대가 2줄 더 보내면 차분 2만 들어간다.
        server.edit { $0.opponent.sent = 14; $0.opponent.seq = 71 }
        clock.uptime += 1.0
        store.tick()
        await tdSettle(store)
        #expect(store.duel?.garbageApplied == 14 && store.myStats?.pendingGarbage == 5)
        store.reset()

        // ★ 기준선: 시작 전(카운트다운 하트비트)에 적힌 내 행 · 판 중 보고가 없는 행은 재개하지 않는다(새 판으로 연다).
        func row(seq: Int, board: String?, lastSeen: Double?) -> TetrisPlayerRow {
            try! tdDecode(TetrisPlayerRow.self, tdJSON(TDPlayer(id: tdMe, name: "나", ready: true, seq: seq, board: board,
                                                                lastSeenMs: lastSeen).json))
        }
        let start = tdNowMs - 60_000
        #expect(TetrisDuelStore.resumePoint(me: row(seq: 3, board: TetrisDuelBoard.emptyText, lastSeen: start - 1_000),
                                            startAtMs: start) == nil, "카운트다운 중 보고를 판 중 보고로 이었다")
        #expect(TetrisDuelStore.resumePoint(me: row(seq: 0, board: nil, lastSeen: nil), startAtMs: start) == nil)
        #expect(TetrisDuelStore.resumePoint(me: row(seq: 5, board: tall, lastSeen: start + 4_000), startAtMs: nil) == nil)
        #expect(TetrisDuelStore.resumePoint(me: row(seq: 5, board: tall, lastSeen: start + 4_000), startAtMs: start)?
            .elapsedSeconds == 4)
    }

    @MainActor
    @Test("멎은 보고: 답이 3초 없으면 버리고 새로 낸다 — 멎음 15초 안에 네 번 넘게 시도 · 두 번 연달아면 '연결 확인 중' · 돌아오면 내린다")
    func aStalledReportIsAbandonedInsideTheSilenceWindow() async throws {
        // 없으면: 멎은 요청 하나(세션 요청 타임아웃 15초)가 하트비트를 전부 막아, 망이 돌아와도 서버 침묵 판정 15초로
        // 연결 끊김 패가 난다(RV2 실측: 판 시계 16초 동안 보고 0건).
        let (store, clock, host, server, script) = await tdStartedStore("stall")
        #expect(store.phase == .playing)
        let base = tdCount(host, "tetris_report")
        // 지금부터 모든 보고의 답이 실시간 1초 뒤에야 온다(판 시계로는 그사이 15초를 민다).
        script.respond("tetris_report") { body in
            var reply = server.report(body)
            reply.delay = 1.0
            return reply
        }
        for _ in 1...15 {
            clock.uptime += 1.0
            store.tick()
            try? await Task.sleep(for: .milliseconds(10))
        }
        await tdWait { tdCount(host, "tetris_report") >= base + 5 }
        let sent = tdCount(host, "tetris_report") - base
        #expect(sent >= 4, "멎은 동안 판 시계 15초에 보고를 \(sent)번만 시도했다 — 서버 침묵 판정(15초)에 걸린다")
        #expect(sent <= 6, "멎은 보고를 3초도 안 기다리고 버렸다(\(sent)건)")
        #expect(store.connectionTrouble, "보고가 두 번 연달아 멎었는데 '연결 확인 중' 이 안 떴다")

        // 망이 돌아왔다 — 마지막으로 멎은 보고도 3초 뒤 버리고, 새 보고의 답이 곧바로 온다.
        script.respond("tetris_report") { server.report($0) }
        clock.uptime += 3.0
        store.tick()
        await tdSettle(store)
        #expect(tdCount(host, "tetris_report") == base + sent + 1)
        #expect(!store.connectionTrouble && store.reportFailureStreak == 0, "돌아온 답이 '연결 확인 중' 을 안 내렸다")
        #expect(!store.reportInFlight)
        // 멎었던 답들이 늦게 닿아도(실시간 1초) 아무 일도 안 생긴다 — 판 · 흐름 그대로.
        try? await Task.sleep(for: .milliseconds(1_200))
        #expect(!store.reportInFlight && store.phase == .playing && !store.connectionTrouble)
        store.reset()
    }

    @MainActor
    @Test("멎어서 버린 보고의 늦은 답은 옮기지 않는다 — 그 뒤에 낸 보고가 자리를 쥔다")
    func theLateReplyOfAnAbandonedReportIsDropped() async throws {
        // 없으면: 버린 보고의 답이 늦게 닿아 새 보고가 나가 있는 동안 '나가 있음'을 내리고(보고가 겹쳐 나간다),
        // 그 답에 실린 옛 사실로 판을 덮는다.
        let (store, clock, host, server, script) = await tdStartedStore("abandoned")
        let real = String(repeating: ".", count: 190) + "SSSSS.SSSS"
        server.edit { $0.opponent = TDPlayer(id: tdRival, name: "라이벌", ready: true, seq: 5, board: real, lines: 1, sent: 0) }
        // 탐지자: 버린 보고의 답은 seq 를 크게 실어(나 999 · 상대 99) seq 가드로는 못 거르게 한다 — 걸러지면 표(ticket) 덕이다.
        let ghost = String(repeating: ".", count: 190) + "OOOOOOOOO."
        var ghostState = server.state()
        ghostState["me"] = TDPlayer(id: tdMe, name: "나", ready: true, seq: 999).json
        ghostState["opponent"] = TDPlayer(id: tdRival, name: "라이벌", ready: true, seq: 99, board: ghost, lines: 9).json
        let ghostBody = tdEnvelope(state: ghostState)
        let first = TDFirstCall()
        script.respond("tetris_report") { body in
            first.take() ? GomokuStubProtocol.Reply(body: ghostBody, delay: 0.8) : server.report(body)
        }
        let base = tdCount(host, "tetris_report")
        clock.uptime += 1.0
        store.tick()                                   // 하트비트 — 멎는다
        await tdWait { tdCount(host, "tetris_report") == base + 1 }
        #expect(store.reportInFlight)
        clock.uptime += 3.0
        store.tick()                                   // 3초 — 버리고 새로
        await tdSettle(store)
        #expect(tdCount(host, "tetris_report") == base + 2)
        #expect(store.match?.opponentBoard.cells == TetrisDuelBoard.decode(real))
        try? await Task.sleep(for: .milliseconds(1_000))  // 버린 보고의 답이 닿는다
        #expect(store.match?.opponentBoard.cells == TetrisDuelBoard.decode(real), "버린 보고의 늦은 답이 상대 판을 덮었다")
        #expect((store.duel?.seq ?? 0) < 999, "버린 보고의 늦은 답의 seq 를 따라잡았다")
        store.reset()
    }

    // MARK: 초인종 · 기권

    @MainActor
    @Test("초인종: 판 중이면 상태 조회(합쳐서 뒤따르는 한 번까지) · 판 밖이면 로비 · take_pokes 는 없다")
    func doorbellCoalescesAndPicksTheRightRead() async throws {
        // 없으면: 공격마다 울리는 초인종이 조회를 그 수만큼 쌓는다(무료 플랜) — 또는 판 중에 로비만 읽어 공격을 못 받는다.
        let (store, _, host, server, script) = await tdStartedStore("bell")
        script.stand("tetris_state", tdEnvelope(state: server.state()), delay: 0.2)
        let lobbyBefore = tdCount(host, "tetris_lobby")
        store.handleSignal()
        await tdWait { tdCount(host, "tetris_state") >= 1 }
        store.handleSignal()
        store.handleSignal()
        store.handleSignal()
        await tdWait { store.syncTask == nil }
        #expect(tdCount(host, "tetris_state") == 2, "초인종 넷이 \(tdCount(host, "tetris_state"))번의 조회가 됐다(1 + 뒤따르는 1)")
        #expect(tdCount(host, "tetris_lobby") == lobbyBefore, "판 중 초인종이 로비를 읽었다")

        // 판 밖(결과 뒤 로비)에서는 로비를 읽는다.
        server.edit { $0.status = "finished"; $0.winner = tdMe; $0.endReason = "resign" }
        script.stand("tetris_state", tdEnvelope(state: server.state()))
        await store.refreshMatch(id: tdMatch)
        #expect(store.phase == .finished && store.match?.outcome == .won)
        store.backToLobby()
        await tdWait { tdCount(host, "tetris_lobby") > lobbyBefore }
        try? await Task.sleep(for: .milliseconds(150))     // 끝남·[로비로] 의 로비 조회가 다 돌아오게(스텁은 즉시 답한다)
        let lobbyAfter = tdCount(host, "tetris_lobby")
        store.handleSignal()
        await tdWait { tdCount(host, "tetris_lobby") > lobbyAfter }
        #expect(tdCount(host, "tetris_lobby") == lobbyAfter + 1)
        store.reset()
    }

    @MainActor
    @Test("기권: 확인 뒤 한 번 — 결과(패 · −판돈) · 끝난 판에서는 아무것도 안 보낸다 · 창 닫기는 기권이 아니다")
    func resignAndWindowCloseAreDifferentDoors() async throws {
        // 없으면: 창을 닫으면 판이 끝나거나(닫기 = 기권), 기권이 끝난 판에 또 나간다.
        let (store, _, host, server, script) = await tdStartedStore("resign")
        store.windowDidClose()
        #expect(store.match?.isFinished == false && store.phase == .playing, "창을 닫았더니 진행 중 판이 내려갔다")
        #expect(tdCount(host, "tetris_resign") == 0)

        server.edit { $0.status = "finished"; $0.winner = tdRival; $0.endReason = "resign" }
        script.stand("tetris_resign", tdEnvelope(state: server.state()))
        await store.resign()
        #expect(tdCount(host, "tetris_resign") == 1)
        #expect(tdCalls(host, "tetris_resign").first?["p_match_id"] as? String == tdMatch)
        #expect(store.match?.outcome == .lost && store.match?.endReason == .resign && store.match?.rubyDelta == -3)
        #expect(store.phase == .finished && store.notice == nil)
        await store.resign()
        #expect(tdCount(host, "tetris_resign") == 1, "끝난 판에 기권을 또 보냈다")

        // 결과 화면인 채로 창을 닫으면 접힌다(다음에 열면 로비).
        store.windowDidClose()
        #expect(store.phase == .lobby && store.match == nil)
        store.reset()
    }

    @MainActor
    @Test("판 결과의 루비: 승 +(판돈−수수료) · 패 −판돈 · 무 0 — 3·5·10 모두 DuelFee 와 같다")
    func rubyDeltaFollowsDuelFee() throws {
        // 없으면: 결과 카드가 서버 정산(수수료 10%)과 다른 숫자를 말한다.
        let (store, _, _, _) = tdMake("ruby", script: TDScript())
        for (stake, net) in [(3, 2), (5, 4), (10, 8)] {
            for (winner, result, outcome, delta) in [
                (tdMe as String?, "opponent_win", TetrisDuelOutcome.won, net),
                (tdRival as String?, "challenger_win", .lost, -stake),
                (nil, "draw", .draw, 0),
            ] {
                store.reset()
                store.applyState(try tdDecode(TetrisStatePayload.self, tdJSON(tdState(
                    "finished", stake: stake, result: result, winner: winner, endReason: winner == nil ? "time_cap" : "topout"))))
                #expect(store.match?.outcome == outcome, "stake \(stake) \(result)")
                #expect(store.match?.rubyDelta == delta, "stake \(stake) \(result) → \(String(describing: store.match?.rubyDelta))")
            }
        }
        #expect(TetrisDuelEndReason.timeCap.isAlwaysDraw && TetrisDuelEndReason.noShow.isAlwaysDraw)
        #expect(!TetrisDuelEndReason.disconnect.isAlwaysDraw)
        #expect(Set(TetrisDuelEndReason.allCases.map(\.rawValue))
                == ["topout", "resign", "disconnect", "time_cap", "no_show", "abandoned"])
        store.reset()
    }
}
