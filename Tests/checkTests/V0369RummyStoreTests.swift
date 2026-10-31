import Foundation
import Testing
@testable import CheckCore

// v0.3.69 — 아잉 큐브(rummy) 클라 코어(`RummyWire` · `RummyStore`) 계약. **모양이 아니라 결과를 잰다.**
//
// 서버는 스텁이다(`GomokuStubProtocol` — 호스트별 스크립트). 응답 JSON 은 설계서 §3.5·§3.7 모양을 손으로 옮긴 것이고,
// S 갈래의 실서버 출력(`Fixtures/rummy/server/*.json`, 통합 때 복사)도 디코드 시험에 들어간다. 실서버 왕복(정규화·시간 판정)은
// 하네스·두 계정 e2e 몫이다.
//
// 호스트는 이 파일의 작은 `RKHost` 다(스토어가 실제로 읽는 멤버만 — `GomokuStoreHost`). 벽시계는 주입이고, 폴링 루프는
// 3,600초로 재우고 `pollTick(at:)` · `checkDeadline(at:)` 을 직접 밟는다(결정적). 마감 깨우기는 끈다.
// 작업 상태 디바운스만 실제 시간(0.05초)이다 — 디바운스·합치기 자체가 시험 대상이라서.
//
// **편집기(RummyTurnEditor)의 끌기·판정은 R 갈래 몫이다.** 갈래 작업 중에는 그것에 기대는 시험을 `.enabled(if: rkEditorReady)` 로
// 묶었다가, 통합(rummy-r 합류)에서 풀었다 — 이제는 진짜 판정으로 **늘** 돈다. 편집기가 다시 자리표시로 퇴행하면 건너뛰는 대신
// `editorIsReal` 이 빨개진다(건너뜀이 초록으로 보이는 함정을 막는다).
//
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례).

// MARK: - 하네스

private let rkMe = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
private let rkB = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
private let rkC = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!
private let rkMatch = UUID(uuidString: "7E7E0000-0000-4000-8000-000000000068")!
private let rkOther = UUID(uuidString: "7E7E0000-0000-4000-8000-000000000069")!
private let rkWall0 = Date(timeIntervalSince1970: 1_800_000_000)
private var rkNowMs: Double { rkWall0.timeIntervalSince1970 * 1000 }
private let rkRack = ["A10", "A11", "A12", "B5", "C9", "J", "D1", "D2", "B13", "C1", "A3", "B7", "C7", "D7"]

private func rkID(_ id: UUID) -> String { id.uuidString.lowercased() }
private func rkOpt(_ value: Any?) -> Any { value ?? NSNull() }
private func rkFaces(_ texts: [String]) -> [RummyFace] { texts.compactMap(RummyFace.init(text:)) }

/// 편집기(R 갈래)가 채워졌는가 — 랙 타일을 새 세트로 끌 수 있으면 채워진 것이다.
private let rkEditorReady: Bool = {
    var editor = RummyTurnEditor(table: [], rack: [RummyFace(color: 0, number: 1)], initialDone: true)
    guard let tile = editor.rack.first else { return false }
    return editor.move(tile.id, to: .newMeld)
}()

private struct RKError: Error {}

@MainActor
private final class RKHost: GomokuStoreHost {
    var session: SupabaseSession?
    var sessionGeneration = 0
    let service: SupabaseWorkService
    var realtimeState: RealtimeState = .idle(.disabled)
    var rubyBalance: Int?

    init(service: SupabaseWorkService) {
        self.service = service
        session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: rkID(rkMe))
    }

    func withSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T {
        guard let session else { throw RKError() }
        return try await operation(session)
    }

    func classifyAuthError(_ error: Error) -> AuthErrorDisposition { .transient }
}

@MainActor
private enum RKRetention {
    /// 스토어는 호스트를 **약참조**로 든다. 시험이 버리면 요청이 한 건도 안 나간다.
    static var hosts: [RKHost] = []
}

private final class RKClock: @unchecked Sendable {
    var wall: Date = rkWall0
}

/// rpc 이름별 응답 스크립트: 줄 세운 응답이 먼저, 그다음 고정 응답. 없으면 nil(→ `[]` 200 — 디코드 실패).
private final class RKScript: @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [String: [GomokuStubProtocol.Reply]] = [:]
    private var standing: [String: GomokuStubProtocol.Reply] = [:]

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

    var handler: GomokuStubProtocol.Handler {
        { [self] rpc, _, _ in self.reply(rpc) }
    }

    private func reply(_ rpc: String) -> GomokuStubProtocol.Reply? {
        lock.lock()
        defer { lock.unlock() }
        if var line = queued[rpc], !line.isEmpty {
            let next = line.removeFirst()
            queued[rpc] = line
            return next
        }
        return standing[rpc]
    }
}

@MainActor
private final class RKTally {
    var presents = 0
    var dismisses = 0
    var attentionRequests = 0
    var attentions: [String] = []
    var arrived: [UUID] = []
    var finished = 0
}

@MainActor
private func rkMake(_ label: String, script: RKScript) -> (RummyStore, RKClock, String, RKTally) {
    let host = "v0368-rk-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: script.handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
    let owner = RKHost(service: service)
    RKRetention.hosts.append(owner)
    let store = RummyStore()
    store.attach(host: owner)
    let clock = RKClock()
    store.clock = { clock.wall }
    store.pollStepSeconds = 3_600
    store.draftDebounceSeconds = 0.05
    store.deadlineWakeEnabled = false
    let tally = RKTally()
    store.presentWindow = { tally.presents += 1 }
    store.dismissWindow = { tally.dismisses += 1 }
    store.requestAttention = { tally.attentionRequests += 1 }
    store.onAttention = { tally.attentions.append($0) }
    store.onInviteArrived = { tally.arrived.append($0.id) }
    store.onMatchFinished = { tally.finished += 1 }
    return (store, clock, host, tally)
}

@MainActor
private func rkWait(_ resumes: Int = 1_000, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<resumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 실제 시간으로 잠깐 기다린다(디바운스가 **안** 터졌음을 보일 때).
private func rkPause(_ seconds: TimeInterval) async {
    try? await Task.sleep(for: .seconds(seconds))
}

/// 작업 상태 전송이 다 끝날 때까지(디바운스 → 비행 → 뒤따르는 한 번).
@MainActor
private func rkSettleDraft(_ store: RummyStore) async {
    for _ in 0..<400 {
        if store.draftDebounceTask == nil, !store.draftInFlight { return }
        if let task = store.draftFlushTask, store.draftInFlight { await task.value } else {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

private func rkCount(_ host: String, _ rpc: String) -> Int { GomokuStubProtocol.count(host: host, rpc: rpc) }
private func rkCalls(_ host: String, _ rpc: String) -> [[String: Any]] {
    GomokuStubProtocol.calls(host: host, rpc: rpc).map(\.json)
}

private func rkJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func rkDecode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: Data(text.utf8))
}

/// §3.7 seats 한 칸.
private func rkSeat(_ seatNo: Int?, _ user: UUID, _ name: String, state: String, rackCount: Int? = 14,
                    initialDone: Bool = false, finalRank: Int? = nil, finalScore: Int? = nil, payout: Int? = nil,
                    isWinner: Bool? = nil, finalRack: [String]? = nil, forfeitOrder: Int? = nil) -> [String: Any] {
    ["seat_no": rkOpt(seatNo), "user_id": rkID(user), "display_name": name, "avatar_url": NSNull(),
     "character": "jelly", "state": state, "rack_count": rkOpt(rackCount), "initial_done": initialDone,
     "timeout_streak": 0, "forfeit_order": rkOpt(forfeitOrder), "final_rank": rkOpt(finalRank),
     "final_score": rkOpt(finalScore), "payout": rkOpt(payout), "is_winner": rkOpt(isWinner),
     "final_rack": rkOpt(finalRack)]
}

/// §3.7 state 한 벌(키 = 설계서 그대로).
private func rkState(
    _ status: String = "active", id: UUID = rkMatch, seq: Int = 1, turnSeat: Int? = 0, mySeat: Int? = 0,
    myRack: [String]? = rkRack, table: [[String]] = [], draft: [String: Any]? = nil,
    seats: [[String: Any]]? = nil, nowMs: Double = rkNowMs, deadlineMs: Double? = nil,
    expiresMs: Double? = nil, endReason: String? = nil, host: UUID = rkMe, poolCount: Int = 78,
    turnStartedMs: Double? = nil
) -> [String: Any] {
    let defaultSeats: [[String: Any]] = status == "forming"
        ? [rkSeat(0, rkMe, "나", state: "joined", rackCount: 0)]
        : [rkSeat(0, rkMe, "나", state: "playing"), rkSeat(1, rkB, "비", state: "playing")]
    let active = status == "active"
    return [
        "id": rkID(id), "status": status, "host_id": rkID(host), "stake": 5, "is_public": false,
        "seat_count": rkOpt(status == "forming" ? nil : 2), "max_seats": 4, "server_now_ms": nowMs, "seq": seq,
        "expires_at_ms": rkOpt(status == "forming" ? (expiresMs ?? nowMs + 600_000) : nil),
        "seats": seats ?? defaultSeats, "my_seat_no": rkOpt(mySeat),
        "my_rack": rkOpt(active ? myRack : nil), "my_initial_done": false,
        "table": table, "pool_count": poolCount,
        "turn_seat_no": rkOpt(active ? turnSeat : nil), "turn_started_ms": rkOpt(active ? (turnStartedMs ?? nowMs) : nil),
        "turn_deadline_ms": rkOpt(active ? (deadlineMs ?? nowMs + 60_000) : nil), "grace_ms": 2000,
        "draft": rkOpt(draft), "consecutive_passes": 0,
        "last_event": active ? (["kind": "start", "seat_no": 0, "count": 14, "at_ms": nowMs] as [String: Any]) as Any
                             : NSNull() as Any,
        "end_reason": rkOpt(endReason), "finished_at_ms": rkOpt(status == "finished" ? nowMs : nil),
    ]
}

private func rkEnvelope(_ status: String = "ok", state: [String: Any]?, extra: [String: Any] = [:]) -> String {
    var object: [String: Any] = ["status": status]
    if let state { object["state"] = state }
    for (key, value) in extra { object[key] = value }
    return rkJSON(object)
}

/// §3.5 ROOM.
private func rkRoom(_ id: UUID = rkOther, host: UUID = rkB, hostName: String = "비", stake: Int = 5,
                    isPublic: Bool = false, extraSeats: [[String: Any]] = []) -> [String: Any] {
    ["id": rkID(id), "host": ["id": rkID(host), "display_name": hostName, "avatar_url": NSNull(), "character": "jelly"],
     "stake": stake, "is_public": isPublic, "expires_at_ms": rkNowMs + 600_000, "max_seats": 4,
     "seats": [["user_id": rkID(host), "display_name": hostName, "avatar_url": NSNull(), "character": "jelly",
                "state": "joined", "seat_no": 0]] + extraSeats]
}

private func rkUser(_ id: UUID, _ name: String) -> [String: Any] {
    ["id": rkID(id), "display_name": name, "avatar_url": NSNull(), "character": "jelly", "is_working": true,
     "in_match": false, "capable": true, "focus_mode": false]
}

/// §3.5 로비.
private func rkLobby(room: [String: Any]? = nil, active: UUID? = nil, invites: [[String: Any]] = [],
                     publicRooms: [[String: Any]] = [], users: [[String: Any]]? = nil) -> String {
    rkJSON([
        "status": "ok", "server_now_ms": rkNowMs, "stakes": [3, 5, 10], "turn_seconds": 60, "room_ttl_seconds": 600,
        "me": ["ruby_balance": 120, "games": 4, "wins": 1, "room": rkOpt(room), "active_match_id": rkOpt(active.map(rkID))],
        "invites": invites, "public_rooms": publicRooms,
        "users": users ?? [rkUser(rkB, "비"), rkUser(rkC, "씨")],
    ])
}

/// 첫 등록 30점 세트(A10·A11·A12 = 33점)를 끌어 놓는다(편집기가 있을 때만).
@MainActor
private func rkPlayInitialMeld(_ store: RummyStore) {
    guard rkEditorReady, let editor = store.editor else { return }
    let ids = ["A10", "A11", "A12"].compactMap { text in editor.rack.first { $0.face.text == text }?.id }
    guard ids.count == 3 else { return }
    store.moveTile(ids[0], to: .newMeld)
    let meld = (store.editor?.melds.count ?? 1) - 1
    store.moveTile(ids[1], to: .meld(meld, index: nil))
    store.moveTile(ids[2], to: .meld(meld, index: nil))
}

// MARK: - 시험

@Suite("v0.3.69 아잉 큐브 — 와이어 · 스토어", .serialized)
@MainActor
struct V0369RummyStoreTests {
    // MARK: 와이어

    @Test("와이어: RPC 14개의 요청 본문 키 집합이 서버 인자 이름과 같고 p_protocol=1·uuid 소문자·p_table 은 면 배열의 배열")
    func requestBodiesMatchServerArguments() async throws {
        // 없으면: 인자 하나 이름이 어긋나 PostgREST 가 함수를 못 찾는(PGRST202) 결함이 스텁 시험에서 초록이 된다.
        let script = RKScript()
        for rpc in RummyWire.RPC.all { script.stand(rpc, #"{"status":"ok"}"#) }
        let (store, _, host, _) = rkMake("wire", script: script)
        let service = try #require(store.host?.service)
        let table = [rkFaces(["A1", "A2", "A3"]), rkFaces(["J", "B4", "C4"])]
        _ = try await service.rummyLobby(accessToken: "t")
        _ = try await service.rummyCreate(accessToken: "t", stake: 5, isPublic: true)
        _ = try await service.rummyInvite(accessToken: "t", matchID: rkMatch, userID: rkB)
        _ = try await service.rummyJoin(accessToken: "t", matchID: rkMatch)
        _ = try await service.rummyDecline(accessToken: "t", matchID: rkMatch)
        _ = try await service.rummyLeave(accessToken: "t", matchID: rkMatch)
        _ = try await service.rummyStart(accessToken: "t", matchID: rkMatch)
        _ = try await service.rummyState(accessToken: "t", matchID: rkMatch)
        // v2: 배치를 실으면 p_layout 이 붙는다(v2 서버 인자 5개와 같다). 없을 때 키가 빠지는 것은 V0369RummyV2WireTests.
        let layout = RummyLayout([RummyPoint(x: 8, y: 16), RummyPoint(x: 200, y: 16)])
        _ = try await service.rummyDraft(accessToken: "t", matchID: rkMatch, expectedSeq: 7, table: table, layout: layout)
        _ = try await service.rummyPlay(accessToken: "t", matchID: rkMatch, expectedSeq: 7, table: table, layout: layout)
        _ = try await service.rummyDraw(accessToken: "t", matchID: rkMatch, expectedSeq: 7)
        _ = try await service.rummyRanking(accessToken: "t")
        _ = try await service.rummyHeartbeat(accessToken: "t", matchID: rkMatch)
        _ = try await service.rummyReact(accessToken: "t", matchID: rkMatch, key: "joy")

        let expected: [String: Set<String>] = [
            "rummy_lobby": ["p_protocol"],
            "rummy_create": ["p_protocol", "p_stake", "p_public"],
            "rummy_invite": ["p_protocol", "p_match_id", "p_user"],
            "rummy_join": ["p_protocol", "p_match_id"],
            "rummy_decline": ["p_protocol", "p_match_id"],
            "rummy_leave": ["p_protocol", "p_match_id"],
            "rummy_start": ["p_protocol", "p_match_id"],
            "rummy_state": ["p_protocol", "p_match_id"],
            "rummy_draft": ["p_protocol", "p_match_id", "p_expected_seq", "p_table", "p_layout"],
            "rummy_play": ["p_protocol", "p_match_id", "p_expected_seq", "p_table", "p_layout"],
            "rummy_draw": ["p_protocol", "p_match_id", "p_expected_seq"],
            "rummy_ranking": ["p_protocol"],
            "rummy_heartbeat": ["p_protocol", "p_match_id"],
            "rummy_react": ["p_protocol", "p_match_id", "p_key"],
        ]
        #expect(Set(expected.keys) == Set(RummyWire.RPC.all))
        // 표만 맞추면 표와 서버가 같이 틀릴 수 있다 — 실제 마이그레이션의 인자 이름과도 잰다(V0369RummyWireContractTests 의 파서).
        let sql = try rwcMigrationSQL()
        for (rpc, keys) in expected {
            let calls = rkCalls(host, rpc)
            #expect(calls.count == 1, "\(rpc) 호출 수")
            guard let body = calls.first else { continue }
            #expect(Set(body.keys) == keys, "\(rpc) 본문 키")
            #expect(Set(body.keys) == (try rwcSQLArguments(rpc, in: sql)), "\(rpc) 본문 키 ≠ \(rwcMigrationName) 인자 이름")
            #expect(body["p_protocol"] as? Int == 1, "\(rpc) p_protocol")
            if let matchID = body["p_match_id"] as? String { #expect(matchID == rkID(rkMatch)) }
        }
        let create = try #require(rkCalls(host, "rummy_create").first)
        #expect(create["p_stake"] as? Int == 5)
        #expect(create["p_public"] as? Bool == true)
        #expect(rkCalls(host, "rummy_invite").first?["p_user"] as? String == rkID(rkB))
        #expect(rkCalls(host, "rummy_draft").first?["p_table"] as? [[String]] == [["A1", "A2", "A3"], ["J", "B4", "C4"]])
        #expect(rkCalls(host, "rummy_play").first?["p_expected_seq"] as? Int == 7)
    }

    @Test("편집기: 통합 뒤 편집기는 진짜다(끌기가 된다) — 아래 편집기 기대 시험들이 건너뛰지 않고 판정으로 돈다")
    func editorIsReal() {
        // 없으면: 편집기가 자리표시(끌기 늘 false)로 돌아가도 그에 기대는 분기가 조용히 빈 값으로 돌아 초록이 된다.
        #expect(rkEditorReady)
        var editor = RummyTurnEditor(table: [], rack: rkFaces(["A10", "A11", "A12", "B2"]), initialDone: false)
        let tiles = editor.rack
        let first = editor.move(tiles[0].id, to: .newMeld)
        let second = editor.move(tiles[1].id, to: .meld(0, index: nil))
        #expect(first && second)
        #expect(editor.reason != .ok, "두 장 세트는 낼 수 없다")
        let third = editor.move(tiles[2].id, to: .meld(0, index: nil))
        #expect(third)
        #expect(editor.reason == .ok, "A10·A11·A12 = 33점 ≥ 30 — 진짜 판정이면 ok")
        #expect(editor.initialPoints == 33)
    }

    @Test("와이어: §3.5 로비·§3.7 state·순위를 그대로 읽고, 모르는 글자는 .unknown, 빠진 키는 nil 이다")
    func decodesHandFixtures() throws {
        // 없으면: 서버가 키를 늘리거나 새 status 를 보낸 날 디코드가 통째로 throw 해 창이 죽는 결함이 초록이 된다.
        let lobby = try rkDecode(RummyLobby.self, rkLobby(
            room: rkRoom(rkMatch, host: rkMe, hostName: "나"), invites: [rkRoom()],
            publicRooms: [rkRoom(rkOther, isPublic: true)]))
        #expect(lobby.status == .ok)
        #expect(lobby.stakes == [3, 5, 10])
        #expect(lobby.turnSeconds == 60)
        #expect(lobby.roomTtlSeconds == 600)
        #expect(lobby.me?.rubyBalance == 120)
        #expect(lobby.me?.room?.id == rkMatch)
        #expect(lobby.me?.room?.seats?.first?.seatNo == 0)
        #expect(lobby.invites?.first?.host?.displayName == "비")
        #expect(lobby.publicRooms?.first?.isPublic == true)
        #expect(lobby.users?.map(\.id) == [rkB, rkC])
        #expect(lobby.users?.first?.capable == true)

        let draft: [String: Any] = ["table": [["B1", "B2", "B3"]], "draft_seq": 4, "at_ms": rkNowMs]
        let active = try rkDecode(RummyActionResponse.self, rkEnvelope(state: rkState(
            seq: 9, table: [["A1", "A2", "A3"], ["J", "C5", "D5"]], draft: draft)))
        let state = try #require(active.state)
        #expect(state.id == rkMatch)
        #expect(state.status == .active)
        #expect(state.seq == 9)
        #expect(state.myRack == rkFaces(rkRack))
        #expect(state.table == [rkFaces(["A1", "A2", "A3"]), rkFaces(["J", "C5", "D5"])])
        #expect(state.draft?.table == [rkFaces(["B1", "B2", "B3"])])
        #expect(state.draft?.draftSeq == 4)
        #expect(state.graceMs == 2000)
        #expect(state.lastEvent?.kind == "start")
        #expect(state.seats?.count == 2)
        #expect(state.seats?.first?.finalRack == nil)

        let finished = try rkDecode(RummyActionResponse.self, rkEnvelope(state: rkState(
            "finished", seq: 12, seats: [
                rkSeat(0, rkMe, "나", state: "done", rackCount: 0, finalRank: 1, finalScore: 21, payout: 10,
                       isWinner: true, finalRack: []),
                rkSeat(1, rkB, "비", state: "done", rackCount: 3, finalRank: 2, finalScore: -21, payout: 0,
                       isWinner: false, finalRack: ["J", "A1"]),
            ], endReason: "rack_empty")))
        #expect(finished.state?.endReason == .rackEmpty)
        #expect(finished.state?.seats?[1].finalRack == rkFaces(["J", "A1"]))
        #expect(finished.state?.seats?[0].payout == 10)

        let unknown = try rkDecode(RummyActionResponse.self, rkJSON([
            "status": "brand_new", "reason": "brand_new_reason",
            "state": ["id": rkID(rkMatch), "status": "paused", "end_reason": "meteor",
                      "seats": [["user_id": rkID(rkMe), "state": "spectating"]]],
        ]))
        #expect(unknown.status == .unknown)
        #expect(unknown.reason == .unknown)
        #expect(unknown.state?.status == .unknown)
        #expect(unknown.state?.endReason == .unknown)
        #expect(unknown.state?.seats?.first?.state == .unknown)
        #expect(unknown.state?.seq == nil)

        let rejected = try rkDecode(RummyActionResponse.self, rkJSON(["status": "rejected", "reason": "initial_under_30"]))
        #expect(rejected.reason == .initialUnder30)
        let dropped = try rkDecode(RummyActionResponse.self, rkJSON(["status": "seats_dropped", "dropped": [rkID(rkB)]]))
        #expect(dropped.status == .seatsDropped)
        #expect(dropped.dropped == [rkB])

        let ranking = try rkDecode(RummyRanking.self, rkJSON([
            "status": "ok",
            "rows": [["id": rkID(rkB), "display_name": "비", "avatar_url": NSNull(), "character": "jelly",
                      "games": 5, "wins": 3, "rank": 1]],
            "me": ["games": 0, "wins": 0, "rank": NSNull()],
        ]))
        #expect(ranking.rows?.first?.wins == 3)
        #expect(ranking.me?.rank == nil)
    }

    @Test("와이어: 서버 갈래 픽스처(Fixtures/rummy/server — 실서버 출력)가 전부 디코드되고, 스토어가 그 state 를 옳게 읽는다")
    func decodesServerFixturesIfPresent() throws {
        // 없으면: 실서버 출력이 손 픽스처와 다르게 생겼는데(키 이름·중첩·null 자리) 스텁 시험만 초록인 결함이 남는다.
        let candidates = [
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/rummy/server"),
        ]
        // 파일 하나가 응답 하나이거나, `_all.json` 처럼 {이름: 응답} 묶음이다.
        var entries: [(name: String, data: Data)] = []
        for folder in candidates {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension == "json" {
                let data = try Data(contentsOf: file)
                let object = try JSONSerialization.jsonObject(with: data)
                if let map = object as? [String: Any], map["status"] == nil {
                    for (name, value) in map.sorted(by: { $0.key < $1.key }) {
                        entries.append((name, try JSONSerialization.data(withJSONObject: value)))
                    }
                } else {
                    entries.append((file.deletingPathExtension().lastPathComponent, data))
                }
            }
        }
        var states: [String: RummyActionResponse] = [:]
        for (name, data) in entries {
            let text = String(decoding: data, as: UTF8.self)
            let status: RummyRPCStatus?
            if name.contains("lobby") {
                let lobby = try? rkDecode(RummyLobby.self, text)
                status = lobby?.status
                #expect(lobby?.stakes == [3, 5, 10], "로비 판돈: \(name)")
            } else if name.contains("ranking") {
                status = (try? rkDecode(RummyRanking.self, text))?.status
            } else {
                let response = try? rkDecode(RummyActionResponse.self, text)
                status = response?.status
                if let response { states[name] = response }
            }
            #expect(status != nil, "디코드 실패: \(name)")
            #expect(status != .unknown, "모르는 status: \(name)")
        }
        #expect(entries.count == 50, "서버 픽스처 \(entries.count)장(기대 50 — v2 서버 실출력: 1판 장면 43 + v2 장면 7)")

        // 스토어가 실서버 state 를 옳게 읽는가(호스트 없는 스토어 — 내 자리는 my_seat_no 로 찾는다).
        if let mine = states["state_active_my_turn"]?.state {
            let store = RummyStore()
            #expect(store.applyState(mine) == .applied)
            #expect(store.phase == .playing)
            #expect(store.isMyTurn)
            #expect(store.editor?.rackFaces.count == mine.myRack?.count)
            #expect((store.turnRemaining(at: Date()) ?? 0) > 50)
        }
        if let other = states["state_active_other_draft"]?.state {
            let store = RummyStore()
            store.applyState(other)
            #expect(!store.isMyTurn)
            #expect(store.otherDraft != nil)
            #expect(store.otherDraft == other.draft?.table)
        }
        if let finished = states["state_finished"]?.state {
            let store = RummyStore()
            store.applyState(finished)
            #expect(store.phase == .finished)
            #expect(store.editor == nil)
            #expect(finished.endReason != nil && finished.endReason != .unknown)
            #expect(finished.seats?.allSatisfy { $0.finalRank != nil && $0.payout != nil } == true)
        }
        if let forming = states["state_forming"]?.state {
            let store = RummyStore()
            store.applyState(forming)
            #expect(store.phase == .room)
            #expect((store.roomRemaining(at: Date()) ?? 0) > 0)
        }
        if let rejected = states["play_rejected"] {
            #expect(rejected.status == .rejected)
            #expect(rejected.reason != nil && rejected.reason != .unknown)
        }
        if let created = states["create_ok"] {
            #expect(created.matchId != nil || created.state?.id != nil)
        }
    }

    // MARK: 흐름

    @Test("흐름: 로비 → 방 만들기 → 초대 → 참가 신호 → 시작 → 내 차례 완료 → 남의 작업 판 → 끝 → 결과 → 로비")
    func fullFlow() async throws {
        // 없으면: 각 단계가 따로는 초록인데 이어 붙이면 phase·편집기·알림이 어긋나는(시작 뒤 편집기 없음 등) 결함이 남는다.
        let script = RKScript()
        script.stand("rummy_lobby", rkLobby())
        let (store, _, host, tally) = rkMake("flow", script: script)

        await store.refreshLobby()
        #expect(store.phase == .lobby)
        #expect(store.lobby?.users?.count == 2)
        #expect(store.lobby?.me?.wins == 1)

        // 방 만들기 — ok{match_id} 뒤 state 를 읽어 방으로.
        store.selectedStake = 5
        store.createPublic = true
        script.enqueue("rummy_create", rkJSON(["status": "ok", "match_id": rkID(rkMatch)]))
        script.stand("rummy_state", rkEnvelope(state: rkState("forming", seq: 0)))
        script.stand("rummy_lobby", rkLobby(room: rkRoom(rkMatch, host: rkMe, hostName: "나")))
        store.createRoom()
        #expect(store.isWorking)
        await store.actionTask?.value
        #expect(!store.isWorking)
        #expect(store.phase == .room)
        #expect(store.match?.id == rkMatch)
        #expect(rkCalls(host, "rummy_create").first?["p_stake"] as? Int == 5)
        #expect(rkCalls(host, "rummy_create").first?["p_public"] as? Bool == true)
        #expect(abs((store.roomRemaining(at: rkWall0) ?? 0) - 600) < 0.01)

        // 초대 — ok 뒤 방 state 다시(초대 자리가 보인다).
        let invitedSeats = [rkSeat(0, rkMe, "나", state: "joined", rackCount: 0),
                            rkSeat(nil, rkB, "비", state: "invited", rackCount: 0)]
        script.enqueue("rummy_invite", #"{"status":"ok"}"#)
        script.stand("rummy_state", rkEnvelope(state: rkState("forming", seq: 0, seats: invitedSeats)))
        store.invite(rkB)
        await store.actionTask?.value
        #expect(store.notice == RummyNoticeText.invited)
        #expect(store.match?.seats?.count == 2)

        // 비가 참가 — 초인종 한 번이 방 state 를 다시 읽는다.
        let joinedSeats = [rkSeat(0, rkMe, "나", state: "joined", rackCount: 0),
                           rkSeat(1, rkB, "비", state: "joined", rackCount: 0)]
        script.stand("rummy_state", rkEnvelope(state: rkState("forming", seq: 0, seats: joinedSeats)))
        store.handleSignal()
        await rkWait { store.match?.seats?.last?.state == .joined && store.syncTask == nil }
        #expect(store.match?.seats?.last?.seatNo == 1)

        // 시작 — 판으로. 창이 안 보이니 창 띄우기 + 주의 + 말풍선(내 차례).
        script.enqueue("rummy_start", rkEnvelope(state: rkState(seq: 1)))
        store.startGame()
        await store.actionTask?.value
        #expect(store.phase == .playing)
        #expect(store.isMyTurn)
        #expect(store.editor?.rackFaces == rkFaces(rkRack))
        #expect(store.editorKey?.matchID == rkMatch && store.editorKey?.turnSeatNo == 0)
        #expect(store.editorSeq == 1)
        #expect(tally.presents == 1)
        #expect(tally.attentionRequests == 1)
        #expect(tally.attentions == [RummyNoticeText.myTurnAttention])
        #expect(abs((store.turnRemaining(at: rkWall0) ?? 0) - 60) < 0.01)

        // 내 차례 완료 — seq 2(비 차례)로. 편집기는 새 seq 로 다시 선다.
        rkPlayInitialMeld(store)
        let played: [[String]] = rkEditorReady ? [["A10", "A11", "A12"]] : []
        let restRack = rkEditorReady ? Array(rkRack.dropFirst(3)) : rkRack
        script.enqueue("rummy_play", rkEnvelope(state: rkState(seq: 2, turnSeat: 1, myRack: restRack, table: played)))
        store.submitTurn()
        await store.actionTask?.value
        let play = try #require(rkCalls(host, "rummy_play").first)
        #expect(play["p_expected_seq"] as? Int == 1)
        #expect(play["p_table"] as? [[String]] == played)
        #expect(store.match?.seq == 2)
        #expect(!store.isMyTurn)
        #expect(store.editorSeq == 2)
        #expect(Set(store.editor?.rackFaces ?? []) == Set(rkFaces(restRack)))
        #expect(store.otherDraft == nil)

        // 비가 놓는 중 — 남의 작업 판이 보인다.
        let draft: [String: Any] = ["table": played + [["B1", "B2", "B3"]], "draft_seq": 1, "at_ms": rkNowMs]
        script.stand("rummy_state", rkEnvelope(state: rkState(
            seq: 2, turnSeat: 1, myRack: restRack, table: played, draft: draft)))
        store.handleSignal()
        await rkWait { store.otherDraft != nil && store.syncTask == nil }
        #expect(store.otherDraft == played.map(rkFaces) + [rkFaces(["B1", "B2", "B3"])])
        #expect(store.match?.table == played.map(rkFaces))

        // 끝 — 결과로, onMatchFinished 는 한 번.
        let finishedSeats = [
            rkSeat(0, rkMe, "나", state: "done", rackCount: 11, finalRank: 2, finalScore: -60, payout: 0,
                   isWinner: false, finalRack: restRack),
            rkSeat(1, rkB, "비", state: "done", rackCount: 0, finalRank: 1, finalScore: 60, payout: 10,
                   isWinner: true, finalRack: []),
        ]
        let finished = rkState("finished", seq: 3, seats: finishedSeats, endReason: "rack_empty")
        script.stand("rummy_state", rkEnvelope(state: finished))
        store.handleSignal()
        await rkWait { store.phase == .finished && store.syncTask == nil }
        #expect(store.phase == .finished)
        #expect(store.editor == nil)
        #expect(tally.finished == 1)
        store.handleSignal()   // 끝난 판의 초인종은 로비로 간다 — 같은 판을 다시 알리지 않는다.
        await rkWait { store.syncTask == nil }
        #expect(tally.finished == 1)

        // [로비로] — 그 판은 다시 끌려오지 않는다.
        store.dismissResult()
        #expect(store.phase == .lobby)
        #expect(store.match == nil)
        let late = try rkDecode(RummyActionResponse.self, rkEnvelope(state: finished))
        #expect(store.applyState(try #require(late.state)) == .ignored)
        #expect(store.match == nil)
    }

    // MARK: 늦은 응답

    @Test("늦은 응답: 옛 seq · 같은 seq 의 옛 draft_seq · forming 방의 옛 요청 표 · 끝난 판의 진행 중 응답은 버린다")
    func staleSnapshotsAreIgnored() throws {
        // 없으면: 폴링 응답이 완료 응답보다 늦게 닿아 판이 한 차례 전으로 되돌아가는 결함이 초록이 된다.
        let (store, _, _, _) = rkMake("stale", script: RKScript())
        func state(_ object: [String: Any]) throws -> RummyMatchState {
            try #require(try rkDecode(RummyActionResponse.self, rkEnvelope(state: object)).state)
        }
        #expect(store.applyState(try state(rkState(seq: 3, turnSeat: 1))) == .applied)
        #expect(store.applyState(try state(rkState(seq: 2, turnSeat: 0))) == .ignored)
        #expect(store.match?.seq == 3)

        let newer: [String: Any] = ["table": [["B1", "B2", "B3"]], "draft_seq": 5, "at_ms": rkNowMs]
        let older: [String: Any] = ["table": [["B9"]], "draft_seq": 4, "at_ms": rkNowMs]
        #expect(store.applyState(try state(rkState(seq: 3, turnSeat: 1, draft: newer))) == .applied)
        #expect(store.applyState(try state(rkState(seq: 3, turnSeat: 1, draft: older))) == .ignored)
        #expect(store.otherDraft == [rkFaces(["B1", "B2", "B3"])])

        // forming 방은 seq 가 안 오른다 — 요청 표로 가린다.
        let (room, _, _, _) = rkMake("stale-room", script: RKScript())
        let two = [rkSeat(0, rkMe, "나", state: "joined", rackCount: 0), rkSeat(1, rkB, "비", state: "joined", rackCount: 0)]
        #expect(room.applyState(try state(rkState("forming", seq: 0, seats: two)), ticket: 10) == .applied)
        #expect(room.applyState(try state(rkState("forming", seq: 0)), ticket: 9) == .ignored)
        #expect(room.match?.seats?.count == 2)

        // 끝난 판에 진행 중 응답.
        #expect(store.applyState(try state(rkState("finished", seq: 4, endReason: "blocked"))) == .applied)
        #expect(store.applyState(try state(rkState(seq: 4))) == .ignored)
        #expect(store.match?.status == .finished)
    }

    @Test("늦은 응답: reset 뒤에 닿은 로비 응답은 아무것도 채우지 않는다(로그아웃·계정 전환)")
    func responsesAfterResetAreDropped() async throws {
        // 없으면: 로그아웃 직전에 나간 로비가 다음 사람의 화면에 앞 사람의 초대·방을 채우는 결함이 초록이 된다.
        let script = RKScript()
        script.stand("rummy_lobby", rkLobby(invites: [rkRoom()]), delay: 0.3)
        let (store, _, host, tally) = rkMake("reset", script: script)
        let pending = Task { await store.refreshLobby() }
        await rkWait { rkCount(host, "rummy_lobby") == 1 }
        store.reset()
        await pending.value
        #expect(store.lobby == nil)
        #expect(tally.arrived.isEmpty)
        #expect(tally.dismisses == 1)
        #expect(store.phase == .lobby)
    }

    // MARK: 편집기

    @Test("편집기: 같은 seq 면 덮지 않고(작업 보존), seq 가 바뀌면 새 판·랙으로 다시 선다 · 내가 playing 이 아니면 없다")
    func editorRebuildsOnlyWhenSeqChanges() throws {
        // 없으면: 내 draft 의 메아리·5초 폴링이 끌어 놓던 작업을 매번 지우는 결함이 초록이 된다.
        let (store, _, _, _) = rkMake("editor", script: RKScript())
        func state(_ object: [String: Any]) throws -> RummyMatchState {
            try #require(try rkDecode(RummyActionResponse.self, rkEnvelope(state: object)).state)
        }
        store.applyState(try state(rkState(seq: 1, myRack: ["A1", "A2", "A3"])))
        #expect(store.editor?.rackFaces == rkFaces(["A1", "A2", "A3"]))
        // 같은 seq(서버 랙이 달라 보여도 = 다시 세웠다면 드러난다) — 그대로.
        let echo: [String: Any] = ["table": [["A1"]], "draft_seq": 1, "at_ms": rkNowMs]
        store.applyState(try state(rkState(seq: 1, myRack: ["D9"], draft: echo)))
        #expect(store.editor?.rackFaces == rkFaces(["A1", "A2", "A3"]))
        #expect(store.editorSeq == 1)
        // seq 가 바뀌었다 — 새 랙으로.
        store.applyState(try state(rkState(seq: 2, turnSeat: 1, myRack: ["A1", "A2", "A3", "C4"])))
        #expect(store.editorSeq == 2)
        #expect(Set(store.editor?.rackFaces ?? []) == Set(rkFaces(["A1", "A2", "A3", "C4"])))
        // 기권한 자리 — 편집기 없음, 내 차례도 아님.
        let forfeited = [rkSeat(0, rkMe, "나", state: "forfeit", rackCount: 0, forfeitOrder: 1),
                         rkSeat(1, rkB, "비", state: "playing"), rkSeat(2, rkC, "씨", state: "playing")]
        store.applyState(try state(rkState(seq: 3, turnSeat: 0, myRack: nil, seats: forfeited)))
        #expect(store.editor == nil)
        #expect(!store.isMyTurn)
        #expect(store.phase == .playing)
    }

    @Test("편집기: seq 가 바뀌어도 랙 배치를 면 순서로 보존하고 새 타일은 끝에 붙는다")
    func rackArrangementSurvivesSeqChange() throws {
        // 없으면: 차례가 돌 때마다 내가 정리한 랙이 서버 순서로 흐트러지는 결함이 초록이 된다.
        let (store, _, _, _) = rkMake("rack-order", script: RKScript())
        func state(_ object: [String: Any]) throws -> RummyMatchState {
            try #require(try rkDecode(RummyActionResponse.self, rkEnvelope(state: object)).state)
        }
        store.applyState(try state(rkState(seq: 1, myRack: ["C9", "A5", "J", "B3"])))
        let joker = try #require(store.editor?.rack.first { $0.face.isJoker }?.id)
        store.moveTile(joker, to: .rack(index: 0))
        #expect(store.editor?.rackFaces == rkFaces(["J", "C9", "A5", "B3"]))
        store.applyState(try state(rkState(seq: 2, turnSeat: 1, myRack: ["A5", "B3", "C9", "J", "D1"])))
        #expect(store.editor?.rackFaces == rkFaces(["J", "C9", "A5", "B3", "D1"]))
    }

    @Test("편집기: 내 차례가 아니면 판으로 끌기·되돌리기·완료·뽑기를 받지 않는다(랙 정렬만)")
    func notMyTurnRejectsTurnActions() async throws {
        // 없으면: 남의 차례에 완료·뽑기를 보내 서버 not_your_turn 만 쌓는(또는 작업 판을 남의 차례에 보내는) 결함이 초록이 된다.
        let script = RKScript()
        let (store, _, host, _) = rkMake("not-mine", script: script)
        let other = try rkDecode(RummyActionResponse.self, rkEnvelope(state: rkState(seq: 4, turnSeat: 1)))
        store.applyState(try #require(other.state))
        let before = store.editor
        let tile = try #require(store.editor?.rack.first?.id)
        store.moveTile(tile, to: .newMeld)
        store.resetTurn()
        store.submitTurn()
        store.drawTile()
        await rkPause(0.15)
        #expect(store.editor == before)
        #expect(store.actionTask == nil)
        #expect(rkCount(host, "rummy_play") == 0)
        #expect(rkCount(host, "rummy_draw") == 0)
        #expect(rkCount(host, "rummy_draft") == 0)
    }

    // MARK: 작업 상태 전송

    @Test("작업 전송: 차례 중간에 세운 편집기는 서버 작업 판을 내 화면으로 맞춘다 — 디바운스 뒤 한 번, 같은 판은 다시 안 보낸다")
    func draftResyncsAfterDebounceOnce() async throws {
        // 없으면: 앱을 다시 켠 사람의 화면엔 없는 옛 작업 판을 서버가 시간 초과 때 대신 내는 결함이 초록이 된다.
        let script = RKScript()
        script.stand("rummy_draft", rkJSON(["status": "ok", "draft_seq": 3]))
        let (store, _, host, _) = rkMake("draft-resync", script: script)
        // 앱을 다시 켠 **이 판을 하던 기기**(engaged 장부가 저장소에서 이어졌다 — 설계서 v2 §6). 놀던 기기는 되돌리지 않는다
        // (V0369RummyV2FixVerifyTests.idleDeviceDoesNotRevertOtherDevicesDraft).
        store.markEngaged(rkMatch)
        let stale: [String: Any] = ["table": [["A1", "A2", "A3"]], "draft_seq": 2, "at_ms": rkNowMs]
        let mine = try rkDecode(RummyActionResponse.self, rkEnvelope(state: rkState(seq: 6, draft: stale)))
        store.applyState(try #require(mine.state))
        #expect(rkCount(host, "rummy_draft") == 0)   // 디바운스 전
        #expect(store.draftDebounceTask != nil)
        await rkSettleDraft(store)
        await rkWait { rkCount(host, "rummy_draft") == 1 && !store.draftInFlight }
        let call = try #require(rkCalls(host, "rummy_draft").first)
        #expect(call["p_expected_seq"] as? Int == 6)
        #expect(call["p_table"] as? [[String]] == [])
        // 되돌리기를 거듭해도 서버가 든 판과 같으면 다시 보내지 않는다.
        store.resetTurn()
        store.resetTurn()
        await rkPause(0.15)
        await rkSettleDraft(store)
        #expect(rkCount(host, "rummy_draft") == 1)
    }

    @Test("작업 전송: 한 번에 하나만 비행하고, 비행 중 요청은 끝난 뒤 합쳐진다 · stale 이면 실린 state 로 맞춘다")
    func draftSingleFlightAndStale() async throws {
        // 없으면: 끌 때마다 요청이 겹쳐 나가 서버에 순서가 뒤집힌 작업 판이 남는 결함이 초록이 된다.
        let script = RKScript()
        script.enqueue("rummy_draft", rkEnvelope("stale", state: rkState(seq: 7, turnSeat: 1)), delay: 0.3)
        let (store, _, host, _) = rkMake("draft-flight", script: script)
        store.markEngaged(rkMatch)   // 판을 하던 기기(앱 재실행) — 위 시험과 같은 전제(§6)
        let stale: [String: Any] = ["table": [["A1", "A2", "A3"]], "draft_seq": 2, "at_ms": rkNowMs]
        let mine = try rkDecode(RummyActionResponse.self, rkEnvelope(state: rkState(seq: 6, draft: stale)))
        store.applyState(try #require(mine.state))
        await rkWait { store.draftInFlight && rkCount(host, "rummy_draft") == 1 }
        #expect(store.draftInFlight)
        store.flushDraft()
        store.flushDraft()
        #expect(rkCount(host, "rummy_draft") == 1)
        await rkSettleDraft(store)
        #expect(rkCount(host, "rummy_draft") == 1)
        #expect(store.match?.seq == 7)
        #expect(store.editorSeq == 7)
        #expect(!store.isMyTurn)
    }

    @Test("작업 전송: 끌기마다 250ms 디바운스로 합치고, 비행 중 바뀐 것은 끝난 뒤 최신 것 한 번")
    func draftDebouncesMovesAndSendsLatestAfterFlight() async throws {
        // 없으면: 끌기 한 번마다 요청이 나가거나(폭주), 비행 중 마지막 끌기를 잃어 서버가 옛 판으로 시간 초과 판정하는 결함이 초록이 된다.
        let script = RKScript()
        script.stand("rummy_draft", rkJSON(["status": "ok", "draft_seq": 1]))
        let (store, _, host, _) = rkMake("draft-moves", script: script)
        let mine = try rkDecode(RummyActionResponse.self, rkEnvelope(state: rkState(seq: 1)))
        store.applyState(try #require(mine.state))
        rkPlayInitialMeld(store)
        #expect(rkCount(host, "rummy_draft") == 0)
        await rkSettleDraft(store)
        await rkWait { rkCount(host, "rummy_draft") == 1 && !store.draftInFlight }
        #expect(rkCount(host, "rummy_draft") == 1)
        #expect(rkCalls(host, "rummy_draft").last?["p_table"] as? [[String]] == [["A10", "A11", "A12"]])

        // 비행 중 바뀐 것: 느린 응답 하나 → 그 사이 두 번 끌기 → 끝난 뒤 최신 판 한 번.
        script.enqueue("rummy_draft", rkJSON(["status": "ok", "draft_seq": 2]), delay: 0.3)
        let b5 = try #require(store.editor?.rack.first { $0.face.text == "B5" }?.id)
        store.moveTile(b5, to: .newMeld)
        await rkWait { store.draftInFlight }
        store.moveTile(b5, to: .meld(0, index: nil))
        await rkPause(0.1)
        #expect(rkCount(host, "rummy_draft") == 2)
        await rkSettleDraft(store)
        await rkWait { rkCount(host, "rummy_draft") == 3 && !store.draftInFlight }
        #expect(rkCount(host, "rummy_draft") == 3)
        #expect(rkCalls(host, "rummy_draft").last?["p_table"] as? [[String]] == [["A10", "A11", "A12", "B5"]])
    }

    // MARK: 차례 동작

    @Test("완료 거절: rejected 는 이유 문구를 띄우고 같은 seq state 로 맞추되 내 작업은 남긴다 · 뽑기는 seq 를 싣는다")
    func rejectedPlayKeepsWorkAndDrawSendsSeq() async throws {
        // 없으면: 서버가 거절한 판을 고치려는데 편집기가 시작 판으로 날아가거나, 이유 대신 뭉뚱그린 문구가 뜨는 결함이 초록이 된다.
        let script = RKScript()
        script.stand("rummy_draft", rkJSON(["status": "ok", "draft_seq": 1]))
        let (store, _, host, _) = rkMake("rejected", script: script)
        let mine = try rkDecode(RummyActionResponse.self, rkEnvelope(state: rkState(seq: 5)))
        store.applyState(try #require(mine.state))
        rkPlayInitialMeld(store)
        let working = store.editor
        script.enqueue("rummy_play", rkEnvelope("rejected", state: rkState(seq: 5), extra: ["reason": "invalid_meld"]))
        store.submitTurn()
        await store.actionTask?.value
        #expect(rkCount(host, "rummy_play") == 1)
        #expect(store.notice == "맞지 않는 묶음이 있어요.")
        #expect(store.editor == working)
        #expect(store.editorSeq == 5)

        script.enqueue("rummy_draw", rkEnvelope(state: rkState(seq: 6, turnSeat: 1, myRack: rkRack + ["C13"])))
        store.drawTile()
        await store.actionTask?.value
        #expect(rkCalls(host, "rummy_draw").first?["p_expected_seq"] as? Int == 5)
        #expect(store.match?.seq == 6)
        #expect(store.editor?.rackFaces.count == 15)
        #expect(store.notice == nil)
    }

    @Test("완료: 편집기가 이미 거절을 아는 판(내 타일 0장)은 보내지 않고 이유만 띄운다")
    func submitBlockedLocallyWhenEditorRejects() async throws {
        // 없으면: [완료] 연타가 서버 거절만 쌓는(또는 버튼 잠금이 풀리지 않는) 결함이 초록이 된다.
        let script = RKScript()
        let (store, _, host, _) = rkMake("local-block", script: script)
        let mine = try rkDecode(RummyActionResponse.self, rkEnvelope(state: rkState(seq: 1)))
        store.applyState(try #require(mine.state))
        store.submitTurn()
        await rkPause(0.05)
        #expect(rkCount(host, "rummy_play") == 0)
        #expect(store.notice == "내 타일을 1개 이상 내야 해요.")
    }

    // MARK: 알림

    @Test("알림: 초대는 방 id 마다 한 번 · 차단한 방장의 초대·방·사람은 거울에서 빠진다(되살려도 다시 안 알린다)")
    func invitesArriveOnceAndBlockMirror() async throws {
        // 없으면: 30초 폴링마다 같은 초대 말풍선이 다시 뜨거나, 차단한 사람의 초대가 배너에 남는 결함이 초록이 된다.
        let script = RKScript()
        let fromC = rkRoom(rkMatch, host: rkC, hostName: "씨")
        let publicWithC = rkRoom(UUID(), host: rkB, isPublic: true,
                                 extraSeats: [["user_id": rkID(rkC), "state": "joined", "seat_no": 1]])
        script.stand("rummy_lobby", rkLobby(invites: [rkRoom(), fromC], publicRooms: [publicWithC]))
        let (store, _, _, tally) = rkMake("invites", script: script)
        store.setHiddenPeers([rkC])
        await store.refreshLobby()
        #expect(tally.arrived == [rkOther])
        #expect(store.incomingInvites.map(\.id) == [rkOther])
        #expect(store.hasIncomingInvite)
        #expect(store.lobby?.users?.map(\.id) == [rkB])
        #expect(store.lobby?.publicRooms?.isEmpty == true)
        await store.refreshLobby()
        #expect(tally.arrived == [rkOther])
        store.setHiddenPeers([])
        #expect(store.incomingInvites.count == 2)
        #expect(store.lobby?.users?.count == 2)
        #expect(tally.arrived == [rkOther])
        #expect(RummyNoticeText.invitation(try #require(store.incomingInvites.first)) == "비님이 아잉 큐브에 초대했어요 · 판돈 5")
    }

    @Test("알림: 판 시작은 판마다 한 번(창 띄우기), 내 차례 말풍선은 창이 안 보일 때만 차례마다 한 번")
    func startAndTurnAttention() throws {
        // 없으면: 창을 보고 있는데 말풍선이 뜨거나, 5초 폴링마다 같은 차례 말풍선이 되풀이되는 결함이 초록이 된다.
        let (store, _, _, tally) = rkMake("attention", script: RKScript())
        func state(_ object: [String: Any]) throws -> RummyMatchState {
            try #require(try rkDecode(RummyActionResponse.self, rkEnvelope(state: object)).state)
        }
        // 차례가 넘어갈 때마다 서버는 turn_started_ms 를 새로 찍는다(차례 정체성 = 판 · 차례 자리 · 차례 시작 시각).
        store.isWindowVisible = true
        store.applyState(try state(rkState(seq: 1, turnSeat: 1)))
        #expect(tally.presents == 1)
        #expect(tally.attentions.isEmpty)
        store.applyState(try state(rkState(seq: 2, turnSeat: 0, nowMs: rkNowMs + 1_000)))   // 창이 보이는 내 차례 — 말풍선 없음
        #expect(tally.attentions.isEmpty)
        store.isWindowVisible = false
        store.applyState(try state(rkState(seq: 3, turnSeat: 1, nowMs: rkNowMs + 2_000)))
        store.applyState(try state(rkState(seq: 4, turnSeat: 0, nowMs: rkNowMs + 3_000)))
        store.applyState(try state(rkState(seq: 4, turnSeat: 0, draft: ["table": [] as [Any], "draft_seq": 1],
                                           nowMs: rkNowMs + 3_000)))
        #expect(tally.attentions == [RummyNoticeText.myTurnAttention])
        #expect(tally.attentionRequests == 1)
        #expect(tally.presents == 1)
    }

    // MARK: 폴링 · 신호 · 마감

    @Test("폴링: 창이 보일 때만 — 방은 5초마다 state, 로비는 30초 · 가려지거나 숨으면 멈춘다")
    func pollingOnlyWhileVisible() async throws {
        // 없으면: 창을 닫아도 5초 폴링이 계속 돌아 서버를 두드리거나, 방에서 참가자 변화를 못 보는 결함이 초록이 된다.
        let script = RKScript()
        script.stand("rummy_lobby", rkLobby(room: rkRoom(rkMatch, host: rkMe, hostName: "나")))
        script.stand("rummy_state", rkEnvelope(state: rkState("forming", seq: 0)))
        let (store, clock, host, _) = rkMake("poll", script: script)
        let room = try rkDecode(RummyActionResponse.self, rkEnvelope(state: rkState("forming", seq: 0)))
        store.applyState(try #require(room.state))
        await store.pollTick(at: rkWall0)
        #expect(rkCount(host, "rummy_state") == 0)   // 창이 안 보인다

        store.setWindowVisible(true)
        await rkWait { rkCount(host, "rummy_state") == 1 && rkCount(host, "rummy_lobby") == 1 && !store.stateInFlight }
        func tick(_ seconds: TimeInterval) async {
            clock.wall = rkWall0.addingTimeInterval(seconds)
            await store.pollTick(at: clock.wall)
        }
        await tick(4.9)
        #expect(rkCount(host, "rummy_state") == 1)
        await tick(5)
        #expect(rkCount(host, "rummy_state") == 2)
        await tick(30)
        #expect(rkCount(host, "rummy_state") == 3)
        #expect(rkCount(host, "rummy_lobby") == 2)
        store.setWindowOccluded(true)
        await tick(60)
        #expect(rkCount(host, "rummy_state") == 3)
        store.setWindowOccluded(false)
        await tick(60)
        #expect(rkCount(host, "rummy_state") == 4)
        #expect(rkCount(host, "rummy_lobby") == 3)
        store.setWindowVisible(false)
        await tick(120)
        #expect(rkCount(host, "rummy_state") == 4)
        #expect(store.pollTask == nil)
    }

    @Test("신호: 도는 중 온 초인종 다섯 번은 뒤따르는 한 번으로 합친다")
    func signalsCoalesce() async throws {
        // 없으면: 작업 판 초인종(끌기마다)이 남의 화면에서 state 요청 폭주를 일으키는 결함이 초록이 된다.
        let script = RKScript()
        script.stand("rummy_state", rkEnvelope(state: rkState(seq: 1, turnSeat: 1)), delay: 0.2)
        let (store, _, host, _) = rkMake("signals", script: script)
        let other = try rkDecode(RummyActionResponse.self, rkEnvelope(state: rkState(seq: 1, turnSeat: 1)))
        store.applyState(try #require(other.state))
        // 한 번 → 조회가 나가 있는 동안 네 번 더(뒤따르는 한 번으로 합쳐진다).
        store.handleSignal()
        await rkWait { rkCount(host, "rummy_state") == 1 }
        for _ in 0..<4 { store.handleSignal() }
        await rkWait(2_000) { store.syncTask == nil }
        #expect(rkCount(host, "rummy_state") == 2)
    }

    @Test("마감: 마감 + 유예(+0.5초)가 지나면 창과 무관하게 state 를 다시 읽고, 같은 차례면 3초 간격으로 다시")
    func deadlineRefetchesState() async throws {
        // 없으면: 상대가 자리를 비웠을 때 시간 초과 판정(서버 catchup)을 아무도 부르지 않아 판이 멈춘 듯 보이는 결함이 초록이 된다.
        let script = RKScript()
        let (store, clock, host, _) = rkMake("deadline", script: script)
        let other = try rkDecode(RummyActionResponse.self, rkEnvelope(state: rkState(seq: 1, turnSeat: 1)))
        store.applyState(try #require(other.state))
        /// 서버 시계도 같이 흐른다(응답의 server_now_ms = 그 순간).
        /// 같은 차례면 turn_started_ms 는 그대로다(server_now 만 흐른다). 새 차례는 마감 − 60초에 시작했다.
        func check(_ seconds: TimeInterval, seq: Int = 1, turnSeat: Int = 1, deadlineMs: Double = rkNowMs + 60_000) async {
            clock.wall = rkWall0.addingTimeInterval(seconds)
            script.stand("rummy_state", rkEnvelope(state: rkState(
                seq: seq, turnSeat: turnSeat, nowMs: rkNowMs + seconds * 1000, deadlineMs: deadlineMs,
                turnStartedMs: deadlineMs - 60_000)))
            await store.checkDeadline(at: clock.wall)
        }
        await check(62.4)
        #expect(rkCount(host, "rummy_state") == 0)
        await check(62.5)
        #expect(rkCount(host, "rummy_state") == 1)
        await check(64)
        #expect(rkCount(host, "rummy_state") == 1)
        await check(65.5, seq: 2, turnSeat: 0, deadlineMs: rkNowMs + 125_000)
        #expect(rkCount(host, "rummy_state") == 2)
        #expect(store.isMyTurn)
        await check(66, seq: 2, turnSeat: 0, deadlineMs: rkNowMs + 125_000)
        #expect(rkCount(host, "rummy_state") == 2)
        #expect(abs((store.turnRemaining(at: clock.wall) ?? 0) - 59) < 0.01)
    }

    @Test("서버 시계: server_now_ms 로 잰 어긋남이 남은 시간(차례·방)에 들어간다")
    func remainingTimeUsesServerClock() throws {
        // 없으면: 기기 시계가 10초 빠른 맥에서 남은 초가 10초 모자라 보이는(먼저 서두르는) 결함이 초록이 된다.
        let (store, _, _, _) = rkMake("clock", script: RKScript())
        let serverNow = rkNowMs + 10_000   // 서버가 10초 앞선다
        let active = try rkDecode(RummyActionResponse.self, rkEnvelope(state: rkState(
            seq: 1, nowMs: serverNow, deadlineMs: serverNow + 60_000)))
        store.applyState(try #require(active.state))
        #expect(abs((store.turnRemaining(at: rkWall0) ?? 0) - 60) < 0.01)
        #expect(store.turnRemaining(at: rkWall0.addingTimeInterval(90)) == 0)
        #expect(store.roomRemaining(at: rkWall0) == nil)
    }

    // MARK: 방 · 거절 · 리셋

    @Test("방: 시작 seats_dropped 는 문구 + 방 다시 읽기, 내가 빠진 방·닫힌 방은 내리고 한 줄 · 나가기는 그 판을 접는다")
    func roomOutcomes() async throws {
        // 없으면: 시작이 막혔는데 아무 말이 없거나, 닫힌 방 화면에 갇히거나, 기권한 판이 다음 폴링에 되살아나는 결함이 초록이 된다.
        let script = RKScript()
        script.stand("rummy_lobby", rkLobby())
        script.stand("rummy_state", rkEnvelope(state: rkState("forming", seq: 0)))
        let (store, _, host, _) = rkMake("room", script: script)
        func state(_ object: [String: Any]) throws -> RummyMatchState {
            try #require(try rkDecode(RummyActionResponse.self, rkEnvelope(state: object)).state)
        }
        store.applyState(try state(rkState("forming", seq: 0)))
        script.enqueue("rummy_start", rkJSON(["status": "seats_dropped", "dropped": [rkID(rkB)]]))
        store.startGame()
        await store.actionTask?.value
        #expect(store.notice == "루비가 모자라거나 다른 게임 중인 사람이 빠졌어요")
        #expect(rkCount(host, "rummy_state") == 1)
        #expect(store.phase == .room)

        // 비의 방에서 내가 빠졌다.
        let (guest, _, _, _) = rkMake("room-guest", script: RKScript())
        let mine = [rkSeat(0, rkB, "비", state: "joined", rackCount: 0), rkSeat(1, rkMe, "나", state: "joined", rackCount: 0)]
        guest.applyState(try state(rkState("forming", seq: 0, seats: mine, host: rkB)))
        #expect(guest.phase == .room)
        let droppedMe = [rkSeat(0, rkB, "비", state: "joined", rackCount: 0), rkSeat(nil, rkMe, "나", state: "dropped", rackCount: 0)]
        guest.applyState(try state(rkState("forming", seq: 0, seats: droppedMe, host: rkB)))
        #expect(guest.match == nil)
        #expect(guest.phase == .lobby)
        #expect(guest.notice == RummyNoticeText.droppedFromRoom)
        guest.applyState(try state(rkState("forming", seq: 0, seats: mine, host: rkB)))
        guest.applyState(try state(rkState("cancelled", seq: 0, seats: mine, host: rkB)))
        #expect(guest.match == nil)
        #expect(guest.notice == "방이 닫혔어요")

        // 판 기권 — 접고 로비로, 늦은 state 는 무시.
        store.applyState(try state(rkState(seq: 3)))
        #expect(store.phase == .playing)
        script.enqueue("rummy_leave", #"{"status":"ok"}"#)
        store.leave()
        await store.actionTask?.value
        #expect(store.phase == .lobby)
        #expect(store.match == nil)
        #expect(store.editor == nil)
        #expect(store.applyState(try state(rkState(seq: 4))) == .ignored)
        #expect(rkCount(host, "rummy_lobby") == 1)
    }

    @Test("가용성: unsupported_client 는 업데이트 필요, 함수 없음(PGRST202)은 서버 없음 · 거절 문구는 표 그대로")
    func availabilityAndRefusalNotices() async throws {
        // 없으면: 옛 앱이 '잠시 후 다시' 만 되풀이하거나, 배포 중간 창에 연결 오류로 보이는 결함이 초록이 된다.
        let script = RKScript()
        script.enqueue("rummy_lobby", #"{"status":"unsupported_client"}"#)
        script.enqueue("rummy_lobby", #"{"code":"PGRST202","details":"x","hint":null,"message":"Could not find the function public.rummy_lobby in the schema cache"}"#,
                       status: 404)
        script.enqueue("rummy_create", #"{"status":"insufficient","side":"me"}"#)
        let (store, _, _, _) = rkMake("availability", script: script)
        await store.refreshLobby()
        #expect(store.availability == .updateRequired)
        #expect(store.notice == "앱을 업데이트해 주세요")
        await store.refreshLobby()
        #expect(store.availability == .serverMissing)
        store.createRoom()
        await store.actionTask?.value
        #expect(store.notice == "루비가 모자라요")
        #expect(store.match == nil)
    }

    @Test("문구: 설계서 §4.3 문구표 그대로(판정 이유 8 · 상태 10)")
    func noticeTable() {
        // 없으면: 문구가 화면마다 따로 지어져 설계서와 어긋나는 결함이 초록이 된다.
        let reasons: [(RummyTurnReason, String)] = [
            (.malformed, "타일 모양이 이상해요. 되돌리고 다시 놓아 주세요."),
            (.jokerNotReused, "가져온 조커는 이번 차례에 판에 써야 해요."),
            (.tableTileRemoved, "판에 있던 타일은 내 랙으로 가져올 수 없어요."),
            (.tileNotOwned, "내 랙에 없는 타일이에요."),
            (.noTilePlayed, "내 타일을 1개 이상 내야 해요."),
            (.invalidMeld, "맞지 않는 묶음이 있어요."),
            (.initialTableTouched, "첫 등록 차례에는 판에 있던 묶음을 건드릴 수 없어요."),
            (.initialUnder30, "첫 등록은 30점 이상이어야 해요(지금 18점)."),
        ]
        for (reason, text) in reasons {
            #expect(RummyNoticeText.reason(reason, initialPoints: 18) == text)
        }
        #expect(RummyNoticeText.reason(.ok, initialPoints: nil) == nil)
        let statuses: [(RummyRPCStatus, String)] = [
            (.busy, "이미 다른 게임 중이에요"), (.targetBusy, "상대가 다른 게임 중이에요"),
            (.targetOutdated, "상대 앱이 아잉 큐브를 아직 몰라요"), (.targetFocused, "상대가 집중 모드예요"),
            (.insufficient, "루비가 모자라요"), (.roomFull, "방이 가득 찼어요"), (.roomClosed, "방이 닫혔어요"),
            (.notEnoughPlayers, "2명 이상 모여야 시작할 수 있어요"),
            (.seatsDropped, "루비가 모자라거나 다른 게임 중인 사람이 빠졌어요"),
            (.unsupportedClient, "앱을 업데이트해 주세요"),
        ]
        for (status, text) in statuses {
            #expect(RummyNoticeText.status(status, for: .start) == text)
        }
        #expect(RummyNoticeText.myTurnAttention == "아잉 큐브 — 내 차례예요")
    }

    @Test("리셋: 방·판·편집기·초대 장부·창을 전부 비우고 배선 값(rankingEnabled)은 남긴다")
    func resetClearsState() async throws {
        // 없으면: 계정을 바꾼 뒤 앞 사람의 랙·방·초대가 남거나, 순위 스위치가 꺼져 영영 안 켜지는 결함이 초록이 된다.
        let script = RKScript()
        script.stand("rummy_lobby", rkLobby(invites: [rkRoom()]))
        let (store, _, _, tally) = rkMake("reset-all", script: script)
        store.rankingEnabled = true
        await store.refreshLobby()
        let active = try rkDecode(RummyActionResponse.self, rkEnvelope(state: rkState(seq: 2)))
        store.applyState(try #require(active.state))
        #expect(store.editor != nil)
        store.reset()
        #expect(store.phase == .lobby)
        #expect(store.match == nil)
        #expect(store.editor == nil)
        #expect(store.lobby == nil)
        #expect(!store.hasIncomingInvite)
        #expect(store.seenInviteIDs.isEmpty)
        #expect(store.rankingEnabled)
        #expect(tally.dismisses == 1)
    }
}
