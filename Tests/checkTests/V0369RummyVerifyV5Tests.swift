import Foundation
import Testing
@testable import CheckCore

// v0.3.69 아잉 큐브 — 검증 갈래 V5(클라 스토어 세션 논리)가 찾은 결함의 회귀 시험.
//
// 시험 이름 앞의 `V5-Dn` 이 보고서의 결함 id 다. 처음엔 빨강(결함 증거)으로 들어왔고, 고친 뒤 초록으로 남긴다:
//   swift test --filter V0369RummyVerifyV5Tests
//
// 서버 응답은 `Fixtures/rummy/server/*.json`(S 갈래가 하네스에서 실제 RPC 를 불러 뜬 출력)을 **그대로** 쓴다.
// 픽스처에 없는 장면은 실제 픽스처에서 **서버 코드가 바꾸는 칸만** 바꿔 만든다(바꾼 칸과 근거 SQL 줄을 시험마다 적었다).
// 세션 사용자는 픽스처의 d…0001(디시험01, 자리 0 · 방장)이다.

// MARK: - 하네스(V0369RummyStoreTests 의 틀을 베꼈다 — 거기 것은 file-private 이라 못 빌린다)

private let v5Me = "d0000000-0000-4000-8000-000000000001"
private let v5FixtureFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/rummy/server", isDirectory: true)

// 픽스처를 다시 뜨면 판 id 가 바뀐다 — 박아 두지 말고 state_forming 의 id 를 읽는다(모든 픽스처가 같은 판이다).
private let v5MatchID: UUID = {
    let data = try! Data(contentsOf: v5FixtureFolder.appendingPathComponent("state_forming.json"))
    let state = (try! JSONSerialization.jsonObject(with: data) as! [String: Any])["state"] as! [String: Any]
    return UUID(uuidString: state["id"] as! String)!
}()

private func v5Raw(_ name: String) throws -> String {
    try String(contentsOf: v5FixtureFolder.appendingPathComponent("\(name).json"), encoding: .utf8)
}

private func v5Object(_ name: String) throws -> [String: Any] {
    let data = Data(try v5Raw(name).utf8)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func v5JSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func v5State(_ object: [String: Any]) throws -> RummyMatchState {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(RummyMatchState.self, from: Data(v5JSON(object).utf8))
}

private func v5Texts(_ table: [[RummyFace]]?) -> [[String]] { (table ?? []).map { $0.map(\.text) } }

private struct V5Error: Error {}

@MainActor
private final class V5Host: GomokuStoreHost {
    var session: SupabaseSession?
    var sessionGeneration = 0
    let service: SupabaseWorkService
    var realtimeState: RealtimeState = .idle(.disabled)
    var rubyBalance: Int?

    init(service: SupabaseWorkService, me: String) {
        self.service = service
        session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    }

    func withSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T {
        guard let session else { throw V5Error() }
        return try await operation(session)
    }

    func classifyAuthError(_ error: Error) -> AuthErrorDisposition { .transient }
}

@MainActor
private enum V5Retention {
    static var hosts: [V5Host] = []
}

private final class V5Script: @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [String: [GomokuStubProtocol.Reply]] = [:]
    private var standing: [String: GomokuStubProtocol.Reply] = [:]

    func enqueue(_ rpc: String, _ body: String, delay: TimeInterval = 0) {
        lock.lock()
        queued[rpc, default: []].append(GomokuStubProtocol.Reply(status: 200, body: body, delay: delay))
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
private final class V5Tally {
    var arrived: [UUID] = []
    var attentions: [String] = []
}

@MainActor
private func v5Make(_ label: String, script: V5Script, me: String = v5Me) -> (RummyStore, String, V5Tally) {
    let host = "v0369-v5-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: script.handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
    let owner = V5Host(service: service, me: me)
    V5Retention.hosts.append(owner)
    let store = RummyStore()
    store.attach(host: owner)
    store.pollStepSeconds = 3_600
    store.draftDebounceSeconds = 0.05
    store.deadlineWakeEnabled = false
    let tally = V5Tally()
    store.onInviteArrived = { tally.arrived.append($0.id) }
    store.onAttention = { tally.attentions.append($0) }
    return (store, host, tally)
}

@MainActor
private func v5Wait(_ resumes: Int = 600, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<resumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private func v5Pause(_ seconds: TimeInterval) async {
    try? await Task.sleep(for: .seconds(seconds))
}

@MainActor
private func v5SettleDraft(_ store: RummyStore) async {
    for _ in 0..<400 {
        if store.draftDebounceTask == nil, !store.draftInFlight { return }
        if let task = store.draftFlushTask, store.draftInFlight { await task.value } else {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

/// 랙의 A10·A11·A12(33점)를 새 세트 하나로 끌어 놓는다(첫 등록 통과 판).
@MainActor
private func v5PlayMeld(_ store: RummyStore) throws {
    let editor = try #require(store.editor)
    let ids = ["A10", "A11", "A12"].compactMap { text in editor.rack.first { $0.face.text == text }?.id }
    try #require(ids.count == 3)
    store.moveTile(ids[0], to: .newMeld)
    let meld = (store.editor?.melds.count ?? 1) - 1
    store.moveTile(ids[1], to: .meld(meld, index: nil))
    store.moveTile(ids[2], to: .meld(meld, index: nil))
}

// MARK: - 시험

@Suite("v0.3.69 아잉 큐브 — V5 스토어 세션 회귀", .serialized)
@MainActor
struct V0369RummyVerifyV5Tests {
    /// V5-D1 — 3~4인 판에서 **차례가 아닌 사람이 기권**하면 서버는 seq 만 +1 하고 차례·마감·작업 판(draft)은 그대로 둔다
    /// (40_engine.sql `rummy__forfeit_apply`: `rummy__log` 가 seq+1, `turn_seat = s.seat_no` 일 때만 `rummy__advance`).
    /// 스토어는 seq 가 바뀌었다는 것만으로 편집기를 시작 판으로 다시 세워 **내 차례 작업을 지우고**, 서버에 남아 있던
    /// 내 작업 판을 시작 판(`[]`)으로 덮어쓴다 — 시간 초과 때 서버가 판정할 판까지 잃는다.
    @Test("V5-D1 남이 기권해 seq 만 올라도 내 차례 작업(편집기·서버 작업 판)이 남고, 다음 작업 상태는 새 seq 로 간다")
    func v5D1ThirdPartyForfeitKeepsMyTurnWork() async throws {
        let script = V5Script()
        script.stand("rummy_draft", try v5Raw("draft_ok"))
        let (store, host, _) = v5Make("d1", script: script)

        let base = try #require(try v5Object("state_active_my_turn")["state"] as? [String: Any])
        store.applyState(try v5State(base))
        #expect(store.isMyTurn)
        try v5PlayMeld(store)
        await v5SettleDraft(store)
        let sentBefore = GomokuStubProtocol.calls(host: host, rpc: "rummy_draft").map(\.json)
        #expect((sentBefore.last?["p_table"] as? [[String]]) == [["A10", "A11", "A12"]])

        // 서버가 실제로 내는 기권 뒤 state: 실제 픽스처에서 seq·자리 2 state·last_event·draft·server_now 만 바꿨다.
        var after = base
        after["seq"] = 2
        after["server_now_ms"] = ((base["server_now_ms"] as? Double) ?? 0) + 5_000
        var seats = try #require(base["seats"] as? [[String: Any]])
        seats[2]["state"] = "forfeit"
        seats[2]["forfeit_order"] = 1
        seats[2]["rack_count"] = 0
        after["seats"] = seats
        after["last_event"] = ["kind": "forfeit", "seat_no": 2, "count": 6, "at_ms": after["server_now_ms"]!]
        after["draft"] = ["table": [["A10", "A11", "A12"]], "draft_seq": 1, "at_ms": base["server_now_ms"]!]
        store.applyState(try v5State(after))
        await v5Pause(0.2)
        await v5SettleDraft(store)

        #expect(store.isMyTurn, "기권한 사람은 차례가 아니었다 — 차례는 여전히 내 것이다")
        #expect(v5Texts(store.editor?.submissionTable) == [["A10", "A11", "A12"]],
                "내가 판에 놓던 세트가 편집기에서 사라졌다")
        let sentAfter = GomokuStubProtocol.calls(host: host, rpc: "rummy_draft").map(\.json).dropFirst(sentBefore.count)
        #expect(!sentAfter.contains { ($0["p_table"] as? [[String]]) == [] },
                "서버에 남아 있던 내 작업 판을 시작 판([])으로 덮어썼다")

        // 같은 차례에 계속 끌면 작업 상태는 **지금 판의 seq(2)** 로 간다 — 편집기가 선 seq(1)로 보내면 서버가 stale 로 버린다.
        let bID = try #require(store.editor?.rack.first { $0.face.text != "A10" }?.id)
        store.moveTile(bID, to: .newMeld)
        await v5Pause(0.2)
        await v5SettleDraft(store)
        let next = GomokuStubProtocol.calls(host: host, rpc: "rummy_draft").map(\.json).dropFirst(sentBefore.count)
        #expect(next.last?["p_expected_seq"] as? Int == 2, "작업 상태가 옛 seq 로 나갔다: \(next.map { $0["p_expected_seq"] ?? "nil" })")
    }

    /// V5-D2 — `stale` 은 "seq 가 바뀌었다" 일 뿐 "차례가 넘어갔다" 가 아니다. 실서버 `play_stale.json` 은 차례가 **여전히 나**
    /// (`turn_seat_no` = `my_seat_no` = 0)인데, 스토어는 status 만 보고 "차례가 이미 넘어갔어요" 를 띄운다.
    /// 실제로 이 응답이 나는 길은 V5-D1 의 남의 기권(seq+1)이다 — 사용자는 아직 시간이 남았는데 차례를 잃었다고 믿는다.
    @Test("V5-D2 완료가 stale 인데 차례가 아직 내 것이면 '판이 바뀌었어요' 를 띄운다('차례가 넘어갔어요' 아님)")
    func v5D2StalePlayWhileStillMyTurnSaysTableChanged() async throws {
        let script = V5Script()
        script.stand("rummy_draft", try v5Raw("draft_ok"))
        script.stand("rummy_play", try v5Raw("play_stale"))
        let (store, _, _) = v5Make("d2", script: script)

        let base = try #require(try v5Object("state_active_my_turn")["state"] as? [String: Any])
        store.applyState(try v5State(base))
        try v5PlayMeld(store)
        store.submitTurn()
        await store.actionTask?.value
        await v5Pause(0.1)

        #expect(store.match?.turnSeatNo == store.match?.mySeatNo)
        #expect(store.isMyTurn)
        #expect(store.notice != RummyNoticeText.turnPassed,
                "차례가 내 것인데 '\(store.notice ?? "nil")' 라고 말한다")
        #expect(store.notice == RummyNoticeText.tableChanged)
    }

    /// V5-D3 — 깨어남(`systemDidWake`)·소켓 재접속(`realtimeDidJoin`)의 따라잡기(`catchUp`)는 로비만 읽는다. 로비가 가리키는
    /// 판 id 가 들고 있는 방 id 와 같으면(`match?.id == mine`) 그 state 를 다시 읽지 않는다 — 방(forming)에 있던 사람이 잠든
    /// 사이 방장이 시작하면, 창이 안 보이는 한 **판 시작을 영영 모른다**(forming 은 마감 깨우기도 없다). 첫 차례가 내 것이면
    /// 60초가 그대로 흘러 시간 초과 벌칙을 받는다.
    @Test("V5-D3 잠 깨기·재접속 따라잡기가 들고 있던 방의 시작(forming→active)을 따라잡는다")
    func v5D3CatchUpFollowsStartOfHeldRoom() async throws {
        let script = V5Script()
        // 시작 뒤 서버 로비: me.room = null, me.active_match_id = 그 판(30_room.sql 286행 — playing · active).
        var lobby = try v5Object("lobby_empty")
        var me = try #require(lobby["me"] as? [String: Any])
        me["active_match_id"] = v5MatchID.uuidString.lowercased()
        lobby["me"] = me
        script.stand("rummy_lobby", v5JSON(lobby))
        script.stand("rummy_state", try v5Raw("state_active_my_turn"))
        let (store, host, _) = v5Make("d3", script: script)

        let forming = try #require(try v5Object("state_forming")["state"] as? [String: Any])
        store.applyState(try v5State(forming))
        #expect(store.phase == .room)

        await store.catchUp()
        await v5Pause(0.1)

        #expect(GomokuStubProtocol.count(host: host, rpc: "rummy_state") >= 1, "따라잡기가 판 state 를 한 번도 안 읽었다")
        #expect(store.match?.status == .active)
        #expect(store.phase == .playing)
    }

    /// V5-D4 — 로비 조회에는 뒤따르는 한 번(합치기)이 없다(`refreshLobby` 가 `lobbyInFlight` 면 그냥 return).
    /// 팝오버 열기·따라잡기의 로비 조회가 나가 있는 동안 초대 초인종이 오면 그 신호는 **버려진다** — 앞 조회는 초대가
    /// 생기기 전 서버를 읽었으므로 배너·말풍선이 다음 계기(30초 스로틀 팝오버·다음 신호)까지 안 뜬다.
    @Test("V5-D4 로비 조회가 도는 중 온 초인종은 끝난 뒤 한 번 더 읽어 새 초대를 알린다")
    func v5D4SignalDuringLobbyFetchIsCoalesced() async throws {
        let script = V5Script()
        let invites = try #require(try v5Object("lobby_with_room_invites_public")["invites"] as? [[String: Any]])
        var withInvite = try v5Object("lobby_empty")
        withInvite["invites"] = invites
        script.enqueue("rummy_lobby", try v5Raw("lobby_empty"), delay: 0.4)
        script.enqueue("rummy_lobby", v5JSON(withInvite))
        // 초대받은 사람(디시험02)으로 본다.
        let (store, host, tally) = v5Make("d4", script: script, me: "d0000000-0000-4000-8000-000000000002")

        let first = Task { await store.refreshLobby() }
        await v5Wait { store.lobbyInFlight }
        #expect(store.lobbyInFlight)
        store.handleSignal()
        await first.value
        await v5Wait { store.syncTask == nil && !store.lobbyInFlight }
        await v5Pause(0.3)

        #expect(GomokuStubProtocol.count(host: host, rpc: "rummy_lobby") == 2, "초인종 뒤 로비를 다시 읽지 않았다")
        #expect(tally.arrived.contains(v5MatchID), "새 초대 말풍선이 안 떴다")
        #expect(store.hasIncomingInvite, "배너·메뉴바 점이 안 섰다")
    }

    /// V5-D5 — `rummy_start` 의 `stale`(30_room.sql 730행: 새 참가자의 지갑 키를 못 잡음 — 다시 시도)을 판의 `stale` 과 같은
    /// 표로 읽어 방장에게 "차례가 이미 넘어갔어요" 를 띄운다. 판은 시작도 안 했다.
    @Test("V5-D5 시작의 stale 은 '잠시 후 다시 시도해 주세요' 다('차례가 넘어갔어요' 아님)")
    func v5D5StartStaleSaysTryAgain() async throws {
        let script = V5Script()
        let forming = try #require(try v5Object("state_forming")["state"] as? [String: Any])
        script.stand("rummy_start", v5JSON(["status": "stale", "state": forming]))
        let (store, _, _) = v5Make("d5", script: script)
        store.applyState(try v5State(forming))

        store.startGame()
        await store.actionTask?.value

        #expect(store.phase == .room)
        #expect(store.notice != RummyNoticeText.turnPassed, "방에서 시작을 눌렀는데 '\(store.notice ?? "nil")'")
        #expect(store.notice == RummyNoticeText.tryAgain)
    }

    /// V5-D6 — 모르는 판 status(서버가 나중에 늘릴 값)를 들면 phase 는 로비로 접히지만 `match` 는 남고, 신호·폴링·따라잡기
    /// 어느 길도 그 판을 다시 읽지 않는다(`syncOnce`·`pollTick` 은 forming/active 만, `applyLobby` 는 id 가 같으면 건너뜀).
    /// 서버가 그 판을 active 로 돌려도 클라는 영영 굳는다. (실픽스처 state_active_my_turn 의 status 만 바꿨다.)
    @Test("V5-D6 모르는 판 status 를 들어도 신호가 오면 그 판을 다시 읽는다(굳지 않는다)")
    func v5D6UnknownMatchStatusIsReread() async throws {
        let script = V5Script()
        var lobby = try v5Object("lobby_empty")
        var me = try #require(lobby["me"] as? [String: Any])
        me["active_match_id"] = v5MatchID.uuidString.lowercased()
        lobby["me"] = me
        script.stand("rummy_lobby", v5JSON(lobby))
        script.stand("rummy_state", try v5Raw("state_active_my_turn"))
        let (store, host, _) = v5Make("d6", script: script)

        var odd = try #require(try v5Object("state_active_my_turn")["state"] as? [String: Any])
        odd["status"] = "paused"
        store.applyState(try v5State(odd))
        #expect(store.match?.status == .unknown)

        store.handleSignal()
        await v5Wait { store.syncTask == nil }
        await v5Pause(0.2)

        #expect(GomokuStubProtocol.count(host: host, rpc: "rummy_state") >= 1, "신호가 와도 그 판을 다시 읽지 않았다")
        #expect(store.match?.status == .active)
    }

    /// V5-D7 — [완료]는 기다리던 작업 상태 디바운스를 걷는다("확정이 작업 상태를 대신한다"). 그런데 그 완료가 **확정되지 않으면**
    /// (5xx·오프라인 실패, 또는 V5-D2 의 stale) 걷어 낸 마지막 끌기는 다시 보내지지 않는다. 서버 작업 판은 그 전 것에 머물고,
    /// 시간 초과 때 서버는 내 화면과 다른 판을 판정한다(R-19) — 유효한 판으로 [완료]를 눌렀는데 옛 작업 판 때문에 벌칙을 받을 수
    /// 있고, 남들은 그동안 내 옛 작업 판을 본다.
    @Test("V5-D7 완료가 실패하면 디바운스로 걷힌 마지막 작업 판을 다시 보낸다")
    func v5D7FailedSubmitResendsLastDraft() async throws {
        let script = V5Script()
        script.stand("rummy_draft", try v5Raw("draft_ok"))
        script.stand("rummy_play", #"{"message":"upstream"}"#, status: 503)
        let (store, host, _) = v5Make("d7", script: script)
        store.draftDebounceSeconds = 0.3

        let base = try #require(try v5Object("state_active_my_turn")["state"] as? [String: Any])
        store.applyState(try v5State(base))
        try v5PlayMeld(store)
        store.submitTurn()   // 디바운스(0.3초)가 터지기 전에 누른다
        await store.actionTask?.value
        await v5Pause(0.6)
        await v5SettleDraft(store)

        #expect(store.isMyTurn)
        #expect(v5Texts(store.editor?.submissionTable) == [["A10", "A11", "A12"]])
        let sent = GomokuStubProtocol.calls(host: host, rpc: "rummy_draft").map(\.json)
        #expect(sent.contains { ($0["p_table"] as? [[String]]) == [["A10", "A11", "A12"]] },
                "화면의 작업 판이 서버 작업 판으로 한 번도 안 갔다(rummy_draft \(sent.count)건)")
    }

    // MARK: 초록이어야 하는 확인(결함 아님 — 같은 자리를 다시 깨뜨리지 않게 남긴다)

    @Test("V5-ok 기기 시계가 10분 앞서도 남은 초는 서버 마감 기준(≈60초)이다")
    func v5TurnRemainingSurvivesDeviceClockSkew() async throws {
        let script = V5Script()
        let (store, _, _) = v5Make("skew", script: script)
        let base = try #require(try v5Object("state_active_my_turn")["state"] as? [String: Any])
        let serverNow = try #require(base["server_now_ms"] as? Double)
        let deadline = try #require(base["turn_deadline_ms"] as? Double)
        let deviceNow = Date(timeIntervalSince1970: serverNow / 1000 + 600)
        store.clock = { deviceNow }
        store.applyState(try v5State(base))
        let remaining = try #require(store.turnRemaining(at: deviceNow))
        #expect(abs(remaining - (deadline - serverNow) / 1000) < 0.01)
    }

    @Test("V5-ok 내 차례 말풍선은 창이 보이면 거르고 안 보이면 낸다")
    func v5TurnAttentionFilteredWhenWindowShown() async throws {
        let script = V5Script()
        let (shown, _, shownTally) = v5Make("att-shown", script: script)
        shown.setWindowVisible(true)
        shown.stopPolling()
        let start = try #require(try v5Object("start_ok")["state"] as? [String: Any])
        var mine = start
        mine["turn_seat_no"] = 0
        shown.applyState(try v5State(mine))
        #expect(shownTally.attentions.isEmpty)

        let (hidden, _, hiddenTally) = v5Make("att-hidden", script: script)
        hidden.applyState(try v5State(mine))
        #expect(hiddenTally.attentions == [RummyNoticeText.myTurnAttention])
    }
}
