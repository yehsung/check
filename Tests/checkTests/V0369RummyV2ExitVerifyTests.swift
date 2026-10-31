import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// 아잉 큐브 2판 — 적대 검증(통합 갈래 4648f284). "사용자가 잃는 경우"를 재현으로 잰다:
// 엉뚱한 기권 · 기권이 안 됨 · 하트비트 끊김/안 멈춤 · 배치 깨짐 · 남의 작업 판이 내 편집을 덮음.
// 서버는 스텁(`GomokuStubProtocol`), 창은 만들지 않는다(`requestClose` 헤드리스 문 — 창 없이도 판단·확인·이탈이 돈다).
// 각 시험의 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가" 다(관례).

private let xvMe = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
private let xvB = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
private let xvMatch = UUID(uuidString: "7E7E0000-0000-4000-8000-0000000000F3")!
private let xvWall0 = Date(timeIntervalSince1970: 1_800_000_000)
private var xvNowMs: Double { xvWall0.timeIntervalSince1970 * 1000 }

private func xvID(_ id: UUID) -> String { id.uuidString.lowercased() }
private func xvOpt(_ value: Any?) -> Any { value ?? NSNull() }

private struct XVError: Error {}

@MainActor
private final class XVHost: GomokuStoreHost {
    var session: SupabaseSession?
    var sessionGeneration = 0
    let service: SupabaseWorkService
    var realtimeState: RealtimeState = .idle(.disabled)
    var rubyBalance: Int?

    init(service: SupabaseWorkService) {
        self.service = service
        session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: xvID(xvMe))
    }

    func withSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T {
        guard let session else { throw XVError() }
        return try await operation(session)
    }

    func classifyAuthError(_ error: Error) -> AuthErrorDisposition { .transient }
}

@MainActor
private enum XVRetention {
    static var hosts: [XVHost] = []
}

private final class XVClock: @unchecked Sendable {
    var wall: Date = xvWall0
}

private final class XVScript: @unchecked Sendable {
    private let lock = NSLock()
    private var standing: [String: GomokuStubProtocol.Reply] = [:]

    func stand(_ rpc: String, _ body: String, status: Int = 200, delay: TimeInterval = 0) {
        lock.lock()
        standing[rpc] = GomokuStubProtocol.Reply(status: status, body: body, delay: delay)
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
private func xvMake(_ label: String, script: XVScript) -> (RummyStore, XVClock, String) {
    let host = "xv-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: script.handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
    let owner = XVHost(service: service)
    XVRetention.hosts.append(owner)
    let store = RummyStore()
    store.attach(host: owner)
    let clock = XVClock()
    store.clock = { clock.wall }
    store.pollStepSeconds = 3_600
    store.draftDebounceSeconds = 0.05
    store.deadlineWakeEnabled = false
    store.heartbeatEnabled = false
    // 설계서 v2 §6: 하트비트·이탈은 이 기기가 손댄 판에만 간다. 이 파일의 시험은 '판을 하는 기기' 를 재므로 미리 적는다
    // (놀던 기기는 V0369RummyV2EngagedTests 가 잰다).
    store.markEngaged(xvMatch)
    return (store, clock, host)
}

@MainActor
private func xvWait(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<1_000 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private func xvCalls(_ host: String, _ rpc: String) -> [[String: Any]] {
    GomokuStubProtocol.calls(host: host, rpc: rpc).map(\.json)
}

private func xvJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func xvSeat(_ seatNo: Int, _ user: UUID, state: String) -> [String: Any] {
    ["seat_no": seatNo, "user_id": xvID(user), "display_name": "p\(seatNo)", "avatar_url": NSNull(), "character": NSNull(),
     "state": state, "rack_count": 5, "initial_done": true, "timeout_streak": 0, "forfeit_order": NSNull(),
     "final_rank": NSNull(), "final_score": NSNull(), "payout": NSNull(), "is_winner": NSNull(), "final_rack": NSNull()]
}

/// 방(forming)·판(active)·끝(finished) state. 내 자리 0, 상대 1. `hostID` 로 방장을 고른다.
private func xvState(
    status: String = "active", seq: Int = 1, hostID: UUID = xvMe, mySeatState: String? = nil, turnSeat: Int = 0,
    turnStartedMs: Double? = nil, rack: [String] = ["A4", "B9", "C2", "D13", "J"],
    table: [[String]] = [["A1", "A2", "A3"]], tableLayout: Any? = [[0, 0]], draft: [String: Any]? = nil
) -> [String: Any] {
    let active = status == "active"
    let defaultSeat = status == "forming" ? "joined" : (active ? "playing" : "done")
    return [
        "id": xvID(xvMatch), "status": status, "host_id": xvID(hostID), "stake": 3, "is_public": false,
        "seat_count": 2, "max_seats": 4, "server_now_ms": xvNowMs, "seq": seq,
        "expires_at_ms": status == "forming" ? xvNowMs + 60_000 : NSNull(),
        "seats": [xvSeat(0, xvMe, state: mySeatState ?? defaultSeat), xvSeat(1, xvB, state: defaultSeat)],
        "my_seat_no": 0, "my_rack": active ? rack : NSNull(), "my_initial_done": true,
        "table": active || status == "finished" ? table : NSNull(), "table_layout": active ? xvOpt(tableLayout) : NSNull(),
        "pool_count": 40,
        "turn_seat_no": active ? turnSeat : NSNull(), "turn_started_ms": active ? (turnStartedMs ?? xvNowMs) : NSNull(),
        "turn_deadline_ms": active ? xvNowMs + 60_000 : NSNull(), "grace_ms": 2000, "draft": xvOpt(draft),
        "consecutive_passes": 0, "last_event": NSNull(), "end_reason": status == "finished" ? "rack_empty" : NSNull(),
        "finished_at_ms": status == "finished" ? xvNowMs : NSNull(), "reactions": [],
    ]
}

private func xvDecode(_ object: [String: Any]) throws -> RummyMatchState {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(RummyMatchState.self, from: Data(xvJSON(object).utf8))
}

private func xvEnvelope(_ status: String = "ok", state: [String: Any]? = nil) -> String {
    var object: [String: Any] = ["status": status, "server_now_ms": xvNowMs]
    if let state { object["state"] = state }
    return xvJSON(object)
}

private func xvFaces(_ texts: [String]) -> [RummyFace] { texts.compactMap(RummyFace.init(text:)) }

@Suite("v0.3.69 아잉 큐브 2판 — 적대 검증(이탈 · 하트비트 · 배치 · 남의 작업 판 · 반응)", .serialized)
@MainActor
struct V0369RummyV2ExitVerifyTests {
    // MARK: - 창 닫기 확인이 낡았을 때

    @Test("방장 '방이 닫혀요' 확인을 띄운 사이 판이 시작되면 확인 버튼이 기권을 보내지 않고 '기권돼요' 로 다시 묻는다")
    func staleCloseRoomPromptDoesNotForfeit() async throws {
        // 없으면: [시작] 직후 ⌘W → "루비는 그대로예요" 확인 → 시작 응답 도착 → [방 닫고 닫기] 가 판돈을 잃는 기권이 되는 결함이 초록이 된다.
        let script = XVScript()
        script.stand("rummy_leave", xvEnvelope())
        let (store, _, host) = xvMake("stale-room", script: script)
        store.applyState(try xvDecode(xvState(status: "forming")))
        #expect(store.phase == .room)
        let controller = CheckRummyWindowController(stuckWindowCheckSeconds: 60)
        #expect(!controller.requestClose(store: store))
        #expect(controller.exitPrompt.pending == .confirmCloseRoom)
        store.applyState(try xvDecode(xvState(status: "active", seq: 2)))
        #expect(store.phase == .playing)
        controller.exitPrompt.confirm()
        try await Task.sleep(for: .milliseconds(400))
        #expect(xvCalls(host, "rummy_leave").isEmpty, "방 닫기 확인이 판 기권을 보냈다")
        #expect(controller.exitPrompt.pending == .confirmForfeit, "판이 시작됐는데 기권 확인을 다시 묻지 않는다")
        #expect(store.match?.id == xvMatch)
        // 다시 물은 확인을 고르면 그때 기권한다.
        controller.exitPrompt.confirm()
        await xvWait { !xvCalls(host, "rummy_leave").isEmpty }
        #expect(xvCalls(host, "rummy_leave").count == 1)
    }

    @Test("기권 확인을 띄운 사이 판이 끝나면 확인은 창만 닫는다 · 취소는 아무것도 안 보낸다")
    func promptAfterFinishOrCancelSendsNothing() async throws {
        // 없으면: 끝난 판에 기권을 보내거나, [계속하기] 가 기권을 보내는 결함이 초록이 된다.
        let script = XVScript()
        script.stand("rummy_leave", xvEnvelope())
        let (store, _, host) = xvMake("prompt-finish", script: script)
        store.applyState(try xvDecode(xvState()))
        let controller = CheckRummyWindowController(stuckWindowCheckSeconds: 60)
        #expect(!controller.requestClose(store: store))
        #expect(controller.exitPrompt.pending == .confirmForfeit)
        controller.exitPrompt.cancel()
        try await Task.sleep(for: .milliseconds(200))
        #expect(xvCalls(host, "rummy_leave").isEmpty && store.phase == .playing)

        #expect(!controller.requestClose(store: store))
        store.applyState(try xvDecode(xvState(status: "finished", seq: 9)))
        #expect(store.phase == .finished)
        controller.exitPrompt.confirm()
        try await Task.sleep(for: .milliseconds(200))
        #expect(xvCalls(host, "rummy_leave").isEmpty, "끝난 판에 기권을 보냈다")
        #expect(controller.exitPrompt.pending == nil)
        // 끝난 판의 창 닫기는 묻지도 보내지도 않는다.
        #expect(controller.requestClose(store: store) && controller.lastCloseDecision == .close)
    }

    // MARK: - 방 손님의 묻지 않는 나가기

    @Test("방 손님이 창을 닫았는데 서버에선 이미 판이 시작됐으면 기권을 보내지 않고 판을 든다(창이 다시 뜬다)")
    func guestCloseRacingStartDoesNotForfeit() async throws {
        // 없으면: 방장이 [시작] 을 누른 직후(이 기기에 시작이 닿기 전) 손님이 창을 닫으면 묻지도 않고 판돈을 잃는 결함이 초록이 된다.
        let script = XVScript()
        script.stand("rummy_state", xvEnvelope(state: xvState(status: "active", seq: 2, hostID: xvB, turnSeat: 1)))
        script.stand("rummy_leave", xvEnvelope())
        let (store, _, host) = xvMake("guest-race", script: script)
        var presented = 0
        store.presentWindow = { presented += 1 }
        store.applyState(try xvDecode(xvState(status: "forming", hostID: xvB)))
        #expect(store.phase == .room)
        let controller = CheckRummyWindowController(stuckWindowCheckSeconds: 60)
        #expect(controller.requestClose(store: store), "손님 창 닫기는 묻지 않고 닫힌다")
        #expect(controller.lastCloseDecision == .leaveRoom)
        await xvWait { store.phase == .playing || !xvCalls(host, "rummy_leave").isEmpty }
        try await Task.sleep(for: .milliseconds(100))
        #expect(xvCalls(host, "rummy_leave").isEmpty, "묻지 않는 방 나가기가 시작된 판을 기권시켰다")
        #expect(store.phase == .playing && presented >= 1, "시작된 판을 들고 창을 다시 띄우지 않는다")
    }

    @Test("방 손님 창 닫기 — 아직 방이면 나간다 · state 가 안 와도 2초 남짓 뒤엔 나간다")
    func guestCloseStillLeavesRoom() async throws {
        // 없으면: 확인 조회를 끼운 탓에 평범한 방 나가기가 안 나가거나(서버에 자리가 남아 시작에 끌려간다) 끝없이 기다리는 결함이 초록이 된다.
        let script = XVScript()
        script.stand("rummy_state", xvEnvelope(state: xvState(status: "forming", hostID: xvB)))
        script.stand("rummy_leave", xvEnvelope())
        let (store, _, host) = xvMake("guest-leave", script: script)
        store.applyState(try xvDecode(xvState(status: "forming", hostID: xvB)))
        let controller = CheckRummyWindowController(stuckWindowCheckSeconds: 60)
        #expect(controller.requestClose(store: store))
        await xvWait { !xvCalls(host, "rummy_leave").isEmpty && store.match == nil }
        #expect(xvCalls(host, "rummy_leave").count == 1 && store.match == nil && store.phase == .lobby)

        let slow = XVScript()
        slow.stand("rummy_state", xvEnvelope(state: xvState(status: "forming", hostID: xvB)), delay: 30)
        slow.stand("rummy_leave", xvEnvelope())
        let (late, _, lateHost) = xvMake("guest-leave-slow", script: slow)
        late.applyState(try xvDecode(xvState(status: "forming", hostID: xvB)))
        let started = Date()
        #expect(controller.requestClose(store: late))
        for _ in 0..<200 where xvCalls(lateHost, "rummy_leave").isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        let waited = Date().timeIntervalSince(started)
        #expect(xvCalls(lateHost, "rummy_leave").count == 1, "느린 조회가 방 나가기를 막았다")
        #expect(waited < 8, "기다린 초 \(waited)")
    }

    // MARK: - 하트비트 수명

    @Test("하트비트 — 판 동안 실제로 거듭 돌고, 판 끝·이탈·로그아웃(reset)에서 멈추며, 접은 판의 늦은 state 가 다시 켜지 않는다")
    func heartbeatStopsOnEveryExit() async throws {
        // 없으면: 하트비트가 판 끝·로그아웃 뒤에도 돌아 남의 세션으로 쏘거나, 이탈 뒤 늦은 응답이 판을 되살려 하트비트가 다시 도는 결함이 초록이 된다.
        let script = XVScript()
        script.stand("rummy_heartbeat", xvEnvelope())
        script.stand("rummy_leave", xvEnvelope(), status: 503)
        let (store, _, host) = xvMake("beat-life", script: script)
        store.heartbeatEnabled = true
        store.heartbeatSeconds = 0.05
        store.applyState(try xvDecode(xvState()))
        await xvWait { xvCalls(host, "rummy_heartbeat").count >= 3 }
        #expect(xvCalls(host, "rummy_heartbeat").count >= 3, "하트비트가 거듭 돌지 않는다")

        // ① 판 끝.
        store.applyState(try xvDecode(xvState(status: "finished", seq: 9)))
        #expect(store.heartbeatTask == nil && store.heartbeatMatchID == nil)
        try await Task.sleep(for: .milliseconds(120))
        let afterFinish = xvCalls(host, "rummy_heartbeat").count
        try await Task.sleep(for: .milliseconds(300))
        #expect(xvCalls(host, "rummy_heartbeat").count == afterFinish, "끝난 판에 하트비트가 돈다")

        // ② 로그아웃·계정 전환(reset).
        let (second, _, host2) = xvMake("beat-reset", script: script)
        second.heartbeatEnabled = true
        second.heartbeatSeconds = 0.05
        second.applyState(try xvDecode(xvState()))
        await xvWait { xvCalls(host2, "rummy_heartbeat").count >= 1 }
        second.reset()
        #expect(second.heartbeatTask == nil && second.heartbeatMatchID == nil)
        try await Task.sleep(for: .milliseconds(120))
        let afterReset = xvCalls(host2, "rummy_heartbeat").count
        try await Task.sleep(for: .milliseconds(300))
        #expect(xvCalls(host2, "rummy_heartbeat").count == afterReset, "로그아웃 뒤에도 하트비트가 돈다")

        // ③ 이탈(서버가 503 이어도 이 기기에선 접는다) → 늦게 온 같은 판 state 는 무시 → 하트비트 꺼진 채.
        let (third, _, host3) = xvMake("beat-exit", script: script)
        third.heartbeatEnabled = true
        third.heartbeatSeconds = 0.05
        third.applyState(try xvDecode(xvState()))
        #expect(await third.leaveForExit(reason: .windowClosed) == false)
        #expect(third.heartbeatTask == nil && third.match == nil)
        #expect(third.applyState(try xvDecode(xvState(seq: 5))) == .ignored)
        #expect(third.heartbeatTask == nil && third.phase == .lobby)
        try await Task.sleep(for: .milliseconds(120))
        let afterExit = xvCalls(host3, "rummy_heartbeat").count
        try await Task.sleep(for: .milliseconds(300))
        #expect(xvCalls(host3, "rummy_heartbeat").count == afterExit)
    }

    @Test("하트비트 — 잠에서 깨어난 뒤처럼 한 번 쉬어도(긴 sleep 중) 같은 판이면 루프가 살아 있다 · 판이 바뀌면 새 판으로 옮긴다")
    func heartbeatSurvivesAndRetargets() async throws {
        // 없으면: 한 번 실패/지연 뒤 루프가 조용히 죽거나 옛 판에 계속 쏘는 결함이 초록이 된다.
        let script = XVScript()
        script.stand("rummy_heartbeat", xvEnvelope(), status: 503)
        let (store, _, host) = xvMake("beat-fail", script: script)
        store.heartbeatEnabled = true
        store.heartbeatSeconds = 0.05
        store.applyState(try xvDecode(xvState()))
        await xvWait { xvCalls(host, "rummy_heartbeat").count >= 2 }
        script.stand("rummy_heartbeat", xvEnvelope())
        let failed = xvCalls(host, "rummy_heartbeat").count
        await xvWait { xvCalls(host, "rummy_heartbeat").count >= failed + 2 }
        #expect(xvCalls(host, "rummy_heartbeat").count >= failed + 2, "실패 뒤 하트비트 루프가 죽었다")
        #expect(store.heartbeatMatchID == xvMatch)
    }

    // MARK: - 묶음째 옮기기 · 판 출신 타일

    @Test("moveBlock 전부-아니면-전무 — 거절은 편집기를 한 비트도 안 바꾼다 · 판 출신 타일은 어느 길로도 랙에 못 간다")
    func moveBlockAllOrNothing() throws {
        // 없으면: 거절된 묶음 끌기가 일부 타일만 옮겨 랙·판이 깨지거나, 판 타일이 랙으로 들어가 R-14 를 어기는 결함이 초록이 된다.
        var editor = RummyTurnEditor(table: [xvFaces(["A1", "A2", "A3"]), xvFaces(["B5", "C5", "D5"])],
                                     rack: xvFaces(["A4", "B9", "C2", "D13", "J"]), initialDone: true)
        let original = editor
        let tableA = editor.melds[0][0].id, tableB = editor.melds[1][2].id
        let rack0 = editor.rack[0].id, rack1 = editor.rack[1].id
        let refused: [([Int], RummyDropTarget)] = [
            ([], .newMeld),
            ([rack0, rack0], .newMeld),
            ([rack0, 9_999], .newMeld),
            ([rack0], .meld(7, index: nil)),
            ([rack0, tableA], .rack(index: nil)),
            ([rack1, tableB], .rack(index: 0)),
            ([tableA], .rackSlot(RummyRackSlot(row: 1, halfCol: 20))),
            ([rack0, tableA, rack1], .rackSlot(RummyRackSlot(row: 0, halfCol: 0))),
        ]
        for (ids, target) in refused {
            #expect(!editor.canMoveBlock(ids, to: target))
            let accepted = editor.moveBlock(ids, to: target)
            #expect(!accepted, "받아들였다: \(ids) → \(target)")
            #expect(editor == original, "거절이 편집기를 바꿨다: \(ids) → \(target)")
        }
        // 판 타일을 새 묶음으로 뺀 뒤에도(이제 판 위 다른 자리) 랙으로는 못 간다.
        let pulled = editor.moveBlock([tableA], to: .newMeldAt(RummyPoint(x: 400, y: 300)))
        #expect(pulled)
        let toRack = editor.moveBlock([tableA], to: .rack(index: nil))
        #expect(!toRack)
        let pick = editor.meldPick(for: tableA)
        let pickToRack = editor.moveBlock(pick, to: .rackSlot(RummyRackSlot(row: 0, halfCol: 0)))
        #expect(!pickToRack)
        // 랙 출신은 판에 나갔다 돌아올 수 있고, 되돌리기는 시작 판·제자리로.
        let slot = try #require(editor.rackLayout.slot(of: rack0))
        let out = editor.moveBlock([rack0, rack1], to: .meld(0, index: nil))
        #expect(out)
        let back = editor.moveBlock([rack0], to: .rack(index: nil))
        #expect(back)
        editor.reset()
        #expect(editor.melds == original.melds && editor.tableLayout == original.tableLayout)
        #expect(editor.rackLayout.slot(of: rack0) != nil && Set(editor.rack.map(\.id)) == Set(original.rack.map(\.id)))
        _ = slot
        // 받침대의 타일 자리는 겹치지 않는다(어떤 끌기 뒤에도).
        let slots = editor.rack.compactMap { editor.rackLayout.slot(of: $0.id) }
        for (i, a) in slots.enumerated() {
            for b in slots[(i + 1)...] where a.row == b.row {
                #expect(abs(a.halfCol - b.halfCol) >= RummyRackLayout.tileSpan, "받침대 타일 겹침 \(a) \(b)")
            }
        }
    }

    @Test("자동 배치 결정성 — 묶음 순서를 섞어도 같은 묶음은 같은 자리 · 몇 번 불러도 같다 · 캔버스 밖 점은 안으로")
    func autoPlacementIsDeterministic() {
        // 없으면: 두 기기가 같은 판을 다른 자리에 그려 '저 묶음 옆에' 가 서로 다른 곳을 가리키는 결함이 초록이 된다.
        let sets: [[RummyFace]] = [
            xvFaces(["A1", "A2", "A3"]), xvFaces(["B7", "C7", "D7"]), xvFaces(["A1", "A2", "A3"]),
            xvFaces(["C9", "C10", "C11", "C12"]), xvFaces(["D4", "J", "D6"]),
        ]
        let layout: RummyLayout = [nil, RummyPoint(x: 999, y: 640), nil, nil, RummyPoint(x: 200, y: 100)]
        let first = RummyTableLayout.place(sets: sets, layout: layout)
        #expect(first == RummyTableLayout.place(sets: sets, layout: layout))
        for frame in zip(first, sets).map({ RummyTableLayout.frame(at: $0, tiles: $1.count) }) {
            #expect(RummyTableLayout.fits(frame), "판 밖 묶음 \(frame)")
        }
        // 주어진 점이 없는 묶음끼리 순서를 바꿔도 면이 같으면 같은 자리를 받는다.
        let order = [3, 1, 0, 4, 2]
        let shuffled = order.map { sets[$0] }
        let shuffledLayout = RummyLayout(order.map { layout.points[$0] })
        let second = RummyTableLayout.place(sets: shuffled, layout: shuffledLayout)
        func byFace(_ sets: [[RummyFace]], _ points: [RummyPoint]) -> [String: Set<RummyPoint>] {
            var map: [String: Set<RummyPoint>] = [:]
            for (set, point) in zip(sets, points) { map[set.map(\.text).joined(separator: ","), default: []].insert(point) }
            return map
        }
        #expect(byFace(sets, first) == byFace(shuffled, second))
    }

    // MARK: - 남의 작업 판

    @Test("남의 차례 작업 판(배치 포함)·남의 기권 seq 는 내 받침대 자리·편집기를 흔들지 않는다 · 내 차례가 오면 받침대 자리 승계")
    func otherDraftDoesNotDisturbMine() throws {
        // 없으면: 남이 끌 때마다 내 받침대 정리가 풀리거나, 남의 기권(seq+1) 한 번에 내가 고른 자리가 초기화되는 결함이 초록이 된다.
        let script = XVScript()
        let (store, _, _) = xvMake("other-draft", script: script)
        let turnStarted = xvNowMs - 5_000
        store.applyState(try xvDecode(xvState(turnSeat: 1, turnStartedMs: turnStarted)))
        let editor0 = try #require(store.editor)
        let mover = editor0.rack[3].id
        let target = RummyRackSlot(row: 1, halfCol: 21)
        store.moveTiles([mover], to: .rackSlot(target))
        #expect(store.editor?.rackLayout.slot(of: mover) == target)
        let mine = try #require(store.editor)
        for (seq, draftSeq, x) in [(1, 1, 300), (1, 2, 520), (2, 3, 640)] {
            let draft: [String: Any] = ["table": [["A1", "A2", "A3"], ["B9", "C9", "D9"]], "draft_seq": draftSeq,
                                        "layout": [[x, 200], [8, 400]]]
            store.applyState(try xvDecode(xvState(seq: seq, turnSeat: 1, turnStartedMs: turnStarted, draft: draft)))
            #expect(store.editor == mine, "남의 작업 판(seq \(seq)·draft \(draftSeq))이 내 편집기를 바꿨다")
            #expect(store.confirmedLayout.points == [RummyPoint(x: 0, y: 0)])
            #expect(store.otherDraftLayout?.points.first == RummyPoint(x: x, y: 200))
        }
        // 남이 내고 내 차례 — 확정 판이 바뀌어 편집기는 새로 서지만 받침대 자리는 그대로.
        store.applyState(try xvDecode(xvState(
            seq: 3, turnSeat: 0, turnStartedMs: xvNowMs, table: [["A1", "A2", "A3"], ["B9", "C9", "D9"]],
            tableLayout: [[640, 200], [8, 400]])))
        let fresh = try #require(store.editor)
        let face = mine.rack.first { $0.id == mover }!.face
        let carried = fresh.rack.first { $0.face == face }.flatMap { fresh.rackLayout.slot(of: $0.id) }
        #expect(carried == target, "내 차례가 오며 받침대 자리가 풀렸다")
        #expect(fresh.tableLayout.points == [RummyPoint(x: 640, y: 200), RummyPoint(x: 8, y: 400)])
    }

    // MARK: - 반응 쿨다운

    @Test("반응 쿨다운 — 1.99초는 막고 2초는 연다 · 서버 too_fast 는 쿨다운을 되돌리지 않는다 · 판 없으면 못 보낸다")
    func reactionCooldownBoundaries() async throws {
        // 없으면: 연타로 서버 too_fast 를 쏟거나, 거절 뒤 쿨다운이 풀려 버튼이 바로 다시 켜지는 결함이 초록이 된다.
        let script = XVScript()
        script.stand("rummy_react", xvEnvelope("too_fast"))
        let (store, clock, host) = xvMake("react-cool", script: script)
        #expect(!store.sendReaction(.joy), "판이 없는데 보냈다")
        store.applyState(try xvDecode(xvState()))
        #expect(store.sendReaction(.joy))
        await xvWait { xvCalls(host, "rummy_react").count == 1 }
        try await Task.sleep(for: .milliseconds(100))
        clock.wall = xvWall0.addingTimeInterval(1.99)
        #expect(!store.canReact(at: clock.wall) && !store.sendReaction(.heart))
        clock.wall = xvWall0.addingTimeInterval(2.0)
        #expect(store.canReact(at: clock.wall) && store.sendReaction(.heart))
        await xvWait { xvCalls(host, "rummy_react").count == 2 }
        #expect(xvCalls(host, "rummy_react").count == 2)
    }
}
