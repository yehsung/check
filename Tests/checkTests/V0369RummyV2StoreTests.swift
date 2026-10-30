import Foundation
import Testing
@testable import CheckCore

// 아잉 큐브 2판 스토어(설계서 v2 §2.4 — 레인 K): 배치 동봉 · 묶음 위치 이동 · 하트비트 · 의도적 이탈 · 반응 · 뽑기 사건 · 받침대 저장.
//
// 서버는 스텁(`GomokuStubProtocol`)이고 응답 state 는 설계서 v2 §1 모양을 손으로 지은 것이다(v1 §3.7 state + `table_layout` ·
// `draft.layout` · `reactions`). 레인 S 실출력이 오면 통합 갈래가 `Fixtures/rummy/v2-synth` 와 함께 대 본다.
// 각 시험의 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가" 다(관례).

private let v2sMe = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
private let v2sB = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
private let v2sMatch = UUID(uuidString: "7E7E0000-0000-4000-8000-0000000000F2")!
private let v2sWall0 = Date(timeIntervalSince1970: 1_800_000_000)
private var v2sNowMs: Double { v2sWall0.timeIntervalSince1970 * 1000 }

private func v2sID(_ id: UUID) -> String { id.uuidString.lowercased() }
private func v2sOpt(_ value: Any?) -> Any { value ?? NSNull() }

private struct V2SError: Error {}

@MainActor
private final class V2SHost: GomokuStoreHost {
    var session: SupabaseSession?
    var sessionGeneration = 0
    let service: SupabaseWorkService
    var realtimeState: RealtimeState = .idle(.disabled)
    var rubyBalance: Int?

    init(service: SupabaseWorkService) {
        self.service = service
        session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: v2sID(v2sMe))
    }

    func withSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T {
        guard let session else { throw V2SError() }
        return try await operation(session)
    }

    func classifyAuthError(_ error: Error) -> AuthErrorDisposition { .transient }
}

@MainActor
private enum V2SRetention {
    static var hosts: [V2SHost] = []
}

private final class V2SClock: @unchecked Sendable {
    var wall: Date = v2sWall0
}

/// rpc 이름별 고정 응답.
private final class V2SScript: @unchecked Sendable {
    private let lock = NSLock()
    private var standing: [String: GomokuStubProtocol.Reply] = [:]

    func stand(_ rpc: String, _ body: String, delay: TimeInterval = 0) {
        lock.lock()
        standing[rpc] = GomokuStubProtocol.Reply(status: 200, body: body, delay: delay)
        lock.unlock()
    }

    var handler: GomokuStubProtocol.Handler {
        { [self] rpc, _, _ in
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.standing[rpc]
        }
    }
}

@MainActor
private func v2sMake(_ label: String, script: V2SScript) -> (RummyStore, V2SClock, String) {
    let host = "v2s-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: script.handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
    let owner = V2SHost(service: service)
    V2SRetention.hosts.append(owner)
    let store = RummyStore()
    store.attach(host: owner)
    let clock = V2SClock()
    store.clock = { clock.wall }
    store.pollStepSeconds = 3_600
    store.draftDebounceSeconds = 0.05
    store.deadlineWakeEnabled = false
    store.heartbeatEnabled = false
    return (store, clock, host)
}

@MainActor
private func v2sWait(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<1_000 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private func v2sCalls(_ host: String, _ rpc: String) -> [[String: Any]] {
    GomokuStubProtocol.calls(host: host, rpc: rpc).map(\.json)
}

private func v2sJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func v2sSeat(_ seatNo: Int, _ user: UUID, state: String = "playing", rack: Int = 5) -> [String: Any] {
    ["seat_no": seatNo, "user_id": v2sID(user), "display_name": "p\(seatNo)", "avatar_url": NSNull(), "character": NSNull(),
     "state": state, "rack_count": rack, "initial_done": true, "timeout_streak": 0, "forfeit_order": NSNull(),
     "final_rank": NSNull(), "final_score": NSNull(), "payout": NSNull(), "is_winner": NSNull(), "final_rack": NSNull()]
}

/// v2 state(§3.7 + v2 §1.1·§1.3). 내 자리 0.
private func v2sState(
    status: String = "active", seq: Int = 1, turnSeat: Int = 0, turnStartedMs: Double? = nil,
    rack: [String] = ["A4", "B9", "C2", "D13", "J"], table: [[String]] = [["A1", "A2", "A3"]],
    tableLayout: Any? = [[0, 0]], draft: [String: Any]? = nil, reactions: [[String: Any]] = []
) -> [String: Any] {
    let active = status == "active"
    return [
        "id": v2sID(v2sMatch), "status": status, "host_id": v2sID(v2sMe), "stake": 3, "is_public": false,
        "seat_count": 2, "max_seats": 4, "server_now_ms": v2sNowMs, "seq": seq, "expires_at_ms": NSNull(),
        "seats": [v2sSeat(0, v2sMe, state: active ? "playing" : "done"), v2sSeat(1, v2sB, state: active ? "playing" : "done")],
        "my_seat_no": 0, "my_rack": active ? rack : NSNull(), "my_initial_done": true, "table": table,
        "table_layout": v2sOpt(tableLayout), "pool_count": 40,
        "turn_seat_no": active ? turnSeat : NSNull(), "turn_started_ms": active ? (turnStartedMs ?? v2sNowMs) : NSNull(),
        "turn_deadline_ms": active ? v2sNowMs + 60_000 : NSNull(), "grace_ms": 2000, "draft": v2sOpt(draft),
        "consecutive_passes": 0, "last_event": NSNull(), "end_reason": active ? NSNull() : "rack_empty",
        "finished_at_ms": active ? NSNull() : v2sNowMs, "reactions": reactions,
    ]
}

private func v2sDecodeState(_ object: [String: Any]) throws -> RummyMatchState {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(RummyMatchState.self, from: Data(v2sJSON(object).utf8))
}

private func v2sEnvelope(_ status: String = "ok", state: [String: Any]? = nil) -> String {
    var object: [String: Any] = ["status": status, "server_now_ms": v2sNowMs]
    if let state { object["state"] = state }
    return v2sJSON(object)
}

@Suite("v2 아잉 큐브 코어 — 스토어(배치 · 하트비트 · 이탈 · 반응 · 뽑기 · 받침대 저장)", .serialized)
@MainActor
struct V0369RummyV2StoreTests {
    @Test("작업 전송·완료가 p_layout 을 싣는다 · 배치만 바꿔도(moveSet) 작업 전송이 나간다 · 같은 판·배치면 다시 안 보낸다")
    func draftAndPlayCarryLayout() async throws {
        // 없으면: 내가 옮긴 묶음 위치가 서버로 안 가 남들 화면·확정 판에서 제자리로 돌아가는 결함이 초록이 된다.
        let script = V2SScript()
        script.stand("rummy_draft", #"{"status":"ok","draft_seq":1}"#)
        let (store, _, host) = v2sMake("draft", script: script)
        store.applyState(try v2sDecodeState(v2sState()))
        let editor = try #require(store.editor)
        #expect(editor.points == [RummyPoint(x: 0, y: 0)])
        store.moveSet(0, to: RummyPoint(x: 400, y: 400))
        await v2sWait { v2sCalls(host, "rummy_draft").count == 1 && !store.draftInFlight }
        let first = try #require(v2sCalls(host, "rummy_draft").first)
        #expect(first["p_layout"] as? [[Int]] == [[400, 400]])
        #expect(first["p_table"] as? [[String]] == [["A1", "A2", "A3"]])
        // 같은 자리로 다시 옮기면 보낼 것이 없다.
        store.moveSet(0, to: RummyPoint(x: 400, y: 400))
        store.scheduleDraft()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(v2sCalls(host, "rummy_draft").count == 1)
        // 랙 타일을 세트에 붙여 [완료] → rummy_play 도 배치를 싣는다.
        let a4 = try #require(store.editor?.rack.first { $0.face.text == "A4" }?.id)
        store.moveTile(a4, to: .meld(0, index: nil))
        script.stand("rummy_play", v2sEnvelope(state: v2sState(seq: 2, turnSeat: 1, turnStartedMs: v2sNowMs + 1,
                                                                rack: ["B9", "C2", "D13", "J"],
                                                                table: [["A1", "A2", "A3", "A4"]],
                                                                tableLayout: [[400, 400]])))
        store.submitTurn()
        await store.actionTask?.value
        let play = try #require(v2sCalls(host, "rummy_play").first)
        #expect(play["p_layout"] as? [[Int]] == [[400, 400]])
        #expect(store.confirmedLayout.points == [RummyPoint(x: 400, y: 400)])
    }

    @Test("남의 차례: otherDraftLayout 이 draft.layout 을 쓰고 빈 칸은 자동 배치 · 묶음 옮기기는 랙 안만(moveTiles)")
    func otherTurnLayoutAndRackOnlyMoves() throws {
        // 없으면: 남의 작업 판이 내 화면에서 다른 자리에 그려지거나, 남의 차례에 판으로 끌어 놓기가 먹히는 결함이 초록이 된다.
        let (store, _, _) = v2sMake("other", script: V2SScript())
        let draft: [String: Any] = ["table": [["A1", "A2", "A3"], ["B5", "C5", "D5"]], "layout": [[600, 320], NSNull()],
                                    "draft_seq": 2, "at_ms": v2sNowMs]
        store.applyState(try v2sDecodeState(v2sState(turnSeat: 1, draft: draft)))
        let other = try #require(store.otherDraftLayout)
        #expect(other.points[0] == RummyPoint(x: 600, y: 320))
        #expect(other.points[1] == RummyPoint(x: 0, y: 0))
        let editor = try #require(store.editor)
        let ids = editor.rack.prefix(2).map(\.id)
        store.moveTiles(ids, to: .newMeld)
        #expect(store.editor == editor)
        store.moveTiles(ids, to: .rackSlot(RummyRackSlot(row: 1, halfCol: 4)))
        #expect(store.editor?.rackLayout.slot(of: ids[0]) == RummyRackSlot(row: 1, halfCol: 4))
        #expect(store.editor?.rackLayout.slot(of: ids[1]) == RummyRackSlot(row: 1, halfCol: 6))
    }

    @Test("하트비트: room·playing 동안 그 판을 잡고 내리면 놓는다 · 한 번 = rummy_heartbeat{p_protocol, p_match_id}")
    func heartbeatFollowsPhase() async throws {
        // 없으면: 판 중에 하트비트가 안 돌아 창만 가려도 90초 뒤 끊김 기권되거나, 판이 끝난 뒤에도 계속 도는 결함이 초록이 된다.
        let script = V2SScript()
        script.stand("rummy_heartbeat", v2sEnvelope())
        let (store, _, host) = v2sMake("beat", script: script)
        store.heartbeatEnabled = true
        store.heartbeatSeconds = 3_600
        store.applyState(try v2sDecodeState(v2sState()))
        #expect(store.heartbeatMatchID == v2sMatch && store.heartbeatTask != nil)
        await store.heartbeatTick(matchID: v2sMatch)
        let call = try #require(v2sCalls(host, "rummy_heartbeat").first)
        #expect(Set(call.keys) == ["p_protocol", "p_match_id"] && call["p_match_id"] as? String == v2sID(v2sMatch))
        store.applyState(try v2sDecodeState(v2sState(status: "finished", seq: 9)))
        #expect(store.phase == .finished && store.heartbeatMatchID == nil && store.heartbeatTask == nil)
    }

    @Test("leaveForExit: 서버가 늦어도 2초 안에 돌아오고 판을 접는다 · 바로 답하면 true")
    func leaveForExitCapsWait() async throws {
        // 없으면: 앱 종료가 느린 서버를 기다리며 멈추거나, 창을 닫았는데 판이 계속 '플레이 중'으로 남는 결함이 초록이 된다.
        let script = V2SScript()
        // 서버 답은 30초 뒤. 상한은 넉넉히 잰다 — 병렬 스위트(렌더 시험)가 MainActor 를 몇 초씩 쥐면 2초 타이머의 재개가 밀린다
        // (실측 4.3초). 잴 것은 "서버 답을 기다리지 않는다"(≪ 30초)와 "2초 전엔 안 돌아온다" 둘이다.
        script.stand("rummy_leave", v2sEnvelope(), delay: 30)
        let (store, _, host) = v2sMake("exit", script: script)
        store.applyState(try v2sDecodeState(v2sState()))
        let started = Date()
        let confirmed = await store.leaveForExit(reason: .windowClosed)
        let waited = Date().timeIntervalSince(started)
        #expect(!confirmed)
        #expect(waited >= 1.9 && waited < 15, "기다린 초 \(waited)")
        #expect(store.match == nil && store.phase == .lobby && store.dismissedMatchIDs.contains(v2sMatch))
        #expect(v2sCalls(host, "rummy_leave").count == 1)

        let quick = V2SScript()
        quick.stand("rummy_leave", v2sEnvelope())
        let (fast, _, _) = v2sMake("exit-fast", script: quick)
        fast.applyState(try v2sDecodeState(v2sState()))
        #expect(await fast.leaveForExit(reason: .appQuit))
        #expect(fast.match == nil)
        // 판이 없으면 할 일이 없다(true).
        #expect(await fast.leaveForExit(reason: .signOut))
    }

    @Test("반응: 쿨다운 2초 · 내 말풍선은 바로, state 메아리는 삼킴 · 남의 것은 처음 볼 때 한 번 · 모르는 키는 버림")
    func reactionsFlow() async throws {
        // 없으면: 내 이모티콘이 두 번 뜨거나(즉시 + 메아리) 같은 반응이 폴링마다 다시 뜨는 결함이 초록이 된다.
        let script = V2SScript()
        script.stand("rummy_react", v2sEnvelope())
        let (store, clock, host) = v2sMake("react", script: script)
        var heard: [RummyReactionEvent] = []
        store.onReaction = { heard.append($0) }
        store.applyState(try v2sDecodeState(v2sState()))
        #expect(store.sendReaction(.joy))
        #expect(!store.sendReaction(.heart))   // 2초 안
        await v2sWait { v2sCalls(host, "rummy_react").count == 1 }
        #expect(v2sCalls(host, "rummy_react").first?["p_key"] as? String == "joy")
        #expect(heard.map(\.sticker) == [.joy] && heard.first?.isMine == true && heard.first?.seatNo == 0)
        clock.wall = v2sWall0.addingTimeInterval(2.1)
        #expect(store.canReact(at: clock.wall))
        let reactions: [[String: Any]] = [
            ["seat_no": 1, "key": "heart", "at_ms": v2sNowMs + 900],
            ["seat_no": 0, "key": "joy", "at_ms": v2sNowMs + 500],
            ["seat_no": 1, "key": "dance", "at_ms": v2sNowMs + 400],
        ]
        store.applyState(try v2sDecodeState(v2sState(reactions: reactions)))
        store.applyState(try v2sDecodeState(v2sState(reactions: reactions)))
        #expect(heard.map(\.sticker) == [.joy, .heart])
        #expect(store.reactionFeed.map(\.seatNo) == [0, 1])
        #expect(Set(store.reactionFeed.map(\.id)).count == 2)
    }

    @Test("뽑기: 다음 편집기에서 새 면을 찾아 onTileDrawn(타일 id·자리) · 받침대 자리는 앞 차례 그대로 승계")
    func drawFiresEventAndKeepsRack() async throws {
        // 없으면: 뽑기 모션이 엉뚱한 타일을 날리거나, 차례가 넘어갈 때마다 받침대 정렬이 풀리는 결함이 초록이 된다.
        let script = V2SScript()
        let (store, _, _) = v2sMake("draw", script: script)
        var events: [RummyDrawEvent] = []
        store.onTileDrawn = { events.append($0) }
        store.applyState(try v2sDecodeState(v2sState()))
        store.sortRack(.color)
        let sortedSlots = try #require(store.editor?.rackEntries)
        script.stand("rummy_draw", v2sEnvelope(state: v2sState(
            seq: 2, turnSeat: 1, turnStartedMs: v2sNowMs + 5, rack: ["A4", "B9", "C2", "D13", "J", "B10"])))
        store.drawTile()
        await store.actionTask?.value
        let event = try #require(events.first)
        #expect(events.count == 1 && event.serial == 1 && store.lastDraw == event)
        #expect(event.tiles.map(\.face.text) == ["B10"])
        let editor = try #require(store.editor)
        let drawn = try #require(editor.rack.first { $0.id == event.tiles[0].tileID })
        #expect(drawn.face.text == "B10" && editor.rackLayout.slot(of: drawn.id) == event.tiles[0].slot)
        #expect(Array(editor.rackEntries.filter { $0.face.text != "B10" }) == sortedSlots)
        // 차례만 넘어가고 랙이 그대로면 사건이 없다.
        store.applyState(try v2sDecodeState(v2sState(seq: 3, turnSeat: 0, turnStartedMs: v2sNowMs + 9,
                                                      rack: ["A4", "B9", "C2", "D13", "J", "B10"])))
        #expect(events.count == 1)
    }

    @Test("받침대 자리 저장: 판 id 키로 저장 → 새 스토어(앱 재실행)가 복원 → 판이 끝나면 지운다 · rackDefaults nil 이면 안 쓴다")
    func rackLayoutPersistsPerMatch() throws {
        // 없으면: 앱을 다시 켜면 받침대 배치가 처음 순서로 돌아가거나, 끝난 판의 저장값이 Preferences 에 쌓이는 결함이 초록이 된다.
        let suite = CheckTestScratch.suitePath("rummy-rack")
        let defaults = CheckTestScratch.defaults("rummy-rack")
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = RummyStore.rackDefaultsKey(matchID: v2sMatch)
        let (store, _, _) = v2sMake("persist", script: V2SScript())
        store.rackDefaults = defaults
        store.applyState(try v2sDecodeState(v2sState()))
        let ids = try #require(store.editor?.rack.map(\.id))
        store.moveTiles([ids[0]], to: .rackSlot(RummyRackSlot(row: 1, halfCol: 20)))
        let saved = try #require(store.editor?.rackEntries)
        #expect(defaults.data(forKey: key) != nil)

        let (relaunched, _, _) = v2sMake("persist-2", script: V2SScript())
        relaunched.rackDefaults = defaults
        relaunched.applyState(try v2sDecodeState(v2sState()))
        #expect(relaunched.editor?.rackEntries == saved)
        relaunched.applyState(try v2sDecodeState(v2sState(status: "finished", seq: 9)))
        #expect(defaults.data(forKey: key) == nil)

        let (unwired, _, _) = v2sMake("persist-3", script: V2SScript())
        unwired.applyState(try v2sDecodeState(v2sState()))
        unwired.sortRack(.number)
        #expect(defaults.data(forKey: key) == nil)
    }
}
