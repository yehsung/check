import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 아잉 큐브 2판 후속 수리 넷(설계서 v2 §6 · App Nap · 판 중 업데이트 확인 · 판 화면 루비 잔액).
// 서버는 스텁(`GomokuStubProtocol`), 창은 만들지 않는다(`requestClose` 헤드리스 문). 저장소는 격리 defaults(`CheckTestScratch`)뿐 —
// 실제 Preferences 를 건드리지 않는다. 각 시험의 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가" 다(관례).

private let egMe = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
private let egB = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
private let egMatch = UUID(uuidString: "7E7E0000-0000-4000-8000-0000000000E6")!
private let egWall0 = Date(timeIntervalSince1970: 1_800_000_000)
private var egNowMs: Double { egWall0.timeIntervalSince1970 * 1000 }
private let egStillsDir =
    "/private/tmp/claude-501/-Users-yesung-check/3ea4b359-81d2-4630-ad1f-7675d460adec/scratchpad/v2f/stills"

private func egID(_ id: UUID) -> String { id.uuidString.lowercased() }
private func egOpt(_ value: Any?) -> Any { value ?? NSNull() }

private struct EGError: Error {}

@MainActor
private final class EGHost: GomokuStoreHost {
    var session: SupabaseSession?
    var sessionGeneration = 0
    let service: SupabaseWorkService
    var realtimeState: RealtimeState = .idle(.disabled)
    var rubyBalance: Int?

    init(service: SupabaseWorkService) {
        self.service = service
        session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: egID(egMe))
    }

    func withSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T {
        guard let session else { throw EGError() }
        return try await operation(session)
    }

    func classifyAuthError(_ error: Error) -> AuthErrorDisposition { .transient }
}

@MainActor
private enum EGRetention {
    static var hosts: [EGHost] = []
}

private final class EGScript: @unchecked Sendable {
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

/// 스토어 하나. `engaged` 가 거짓이면 **놀던 기기**(같은 계정의 다른 맥이 판을 하는 중, 이 맥은 읽기만 했다)다.
@MainActor
private func egMake(_ label: String, script: EGScript, engaged: Bool) -> (RummyStore, EGHost, String) {
    let host = "eg-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: script.handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
    let owner = EGHost(service: service)
    EGRetention.hosts.append(owner)
    let store = RummyStore()
    store.attach(host: owner)
    store.clock = { egWall0 }
    store.pollStepSeconds = 3_600
    store.draftDebounceSeconds = 0.05
    store.deadlineWakeEnabled = false
    store.heartbeatEnabled = true
    store.heartbeatSeconds = 0.05
    if engaged { store.markEngaged(egMatch) }
    return (store, owner, host)
}

@MainActor
private func egWait(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<1_000 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private func egCount(_ host: String, _ rpc: String) -> Int {
    GomokuStubProtocol.calls(host: host, rpc: rpc).count
}

private func egJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func egSeat(_ seatNo: Int, _ user: UUID, state: String) -> [String: Any] {
    ["seat_no": seatNo, "user_id": egID(user), "display_name": seatNo == 0 ? "영식" : "민수", "avatar_url": NSNull(),
     "character": NSNull(), "state": state, "rack_count": 5, "initial_done": true, "timeout_streak": 0,
     "forfeit_order": NSNull(), "final_rank": NSNull(), "final_score": NSNull(), "payout": NSNull(), "is_winner": NSNull(),
     "final_rack": NSNull()]
}

/// 방(forming)·판(active)·끝(finished) state. 내 자리 0(방장 = `hostID`), 상대 1.
private func egState(status: String = "active", seq: Int = 1, hostID: UUID = egMe, turnSeat: Int = 0) -> [String: Any] {
    let active = status == "active"
    let seatState = status == "forming" ? "joined" : (active ? "playing" : "done")
    return [
        "id": egID(egMatch), "status": status, "host_id": egID(hostID), "stake": 5, "is_public": false,
        "seat_count": 2, "max_seats": 4, "server_now_ms": egNowMs, "seq": seq,
        "expires_at_ms": status == "forming" ? egNowMs + 60_000 : NSNull(),
        "seats": [egSeat(0, egMe, state: seatState), egSeat(1, egB, state: seatState)],
        "my_seat_no": 0, "my_rack": active ? ["A4", "B9", "C2", "D13", "J"] : NSNull(), "my_initial_done": true,
        "table": active || status == "finished" ? [["A1", "A2", "A3"]] : NSNull(),
        "table_layout": active ? [[0, 0]] : NSNull(), "pool_count": 40,
        "turn_seat_no": active ? turnSeat : NSNull(), "turn_started_ms": active ? egNowMs : NSNull(),
        "turn_deadline_ms": active ? egNowMs + 60_000 : NSNull(), "grace_ms": 2000, "draft": NSNull(),
        "consecutive_passes": 0, "last_event": NSNull(), "end_reason": status == "finished" ? "rack_empty" : NSNull(),
        "finished_at_ms": status == "finished" ? egNowMs : NSNull(), "reactions": [],
    ]
}

private func egDecode(_ object: [String: Any]) throws -> RummyMatchState {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(RummyMatchState.self, from: Data(egJSON(object).utf8))
}

private func egEnvelope(_ status: String = "ok", state: [String: Any]? = nil, extra: [String: Any] = [:]) -> String {
    var object: [String: Any] = ["status": status, "server_now_ms": egNowMs]
    if let state { object["state"] = state }
    for (key, value) in extra { object[key] = value }
    return egJSON(object)
}

private func egLobby(ruby: Int, active: UUID?) -> String {
    egJSON([
        "status": "ok", "server_now_ms": egNowMs, "stakes": [3, 5, 10], "turn_seconds": 60, "room_ttl_seconds": 600,
        "me": ["ruby_balance": ruby, "games": 3, "wins": 1, "room": NSNull(), "active_match_id": egOpt(active.map(egID))],
        "invites": [], "public_rooms": [], "users": [],
    ])
}

@Suite("v0.3.69 아잉 큐브 2판 후속 — 한 계정 기기 여럿 · App Nap · 판 중 업데이트 · 머리글 루비", .serialized)
@MainActor
struct V0369RummyV2EngagedTests {
    // MARK: - 1. 놀던 기기는 아무것도 보내지 않는다(§6)

    @Test("놀던 기기(engaged 아님) — 판 중 창 닫기·앱 종료·로그아웃·업데이트에서 rummy_leave 0회 · 하트비트 0회 · App Nap 안 쥠")
    func idleDeviceSendsNothing() async throws {
        // 없으면: 테트리스 실측(10-30)처럼 초인종으로 판을 읽기만 한 '놀던 맥' 을 끄거나 로그아웃하면 다른 맥에서 하던 판이 기권되는 결함이 초록이 된다.
        let script = EGScript()
        script.stand("rummy_leave", egEnvelope())
        script.stand("rummy_heartbeat", egEnvelope())
        script.stand("rummy_state", egEnvelope(state: egState()))
        let (store, _, host) = egMake("idle", script: script, engaged: false)
        var holds: [Bool] = []
        store.onHoldingMatchChange = { holds.append($0) }
        // 로비 me.active_match_id → refreshMatch 와 같은 길(초인종으로 읽은 판).
        await store.refreshMatch(id: egMatch)
        #expect(store.phase == .playing && store.match?.id == egMatch && !store.isEngaged(egMatch))
        #expect(store.heartbeatTask == nil && store.heartbeatMatchID == nil, "놀던 기기가 하트비트를 돌린다")
        try await Task.sleep(for: .milliseconds(300))
        await store.heartbeatTick(matchID: egMatch)

        // 창 닫기 — 묻지 않고 그냥 닫힌다.
        let controller = CheckRummyWindowController(stuckWindowCheckSeconds: 60)
        #expect(controller.requestClose(store: store))
        #expect(controller.lastCloseDecision == .close && controller.exitPrompt.pending == nil)
        // 앱 종료 — 이탈 Task 가 없다.
        #expect(RummyExitPolicy.startQuitLeave(store) == nil)
        // 로그아웃 — `signOutLeavingRummy` 의 문(needsExitLeave)이 닫혀 곧바로 signOut 한다.
        #expect(!RummyExitPolicy.needsExitLeave(store))
        // 코어 문도 막혀 있다(누가 불러도 보내지 않는다).
        #expect(await store.leaveForExit(reason: .appQuit))
        #expect(await store.leaveForExit(reason: .signOut))
        #expect(await store.leaveRoomForExit(reason: .windowClosed))
        // 업데이트 — 묻지 않고 곧바로 진행.
        let gate = RummyUpdateGate()
        var proceeded = 0
        gate.request(store: store) { proceeded += 1 }
        #expect(proceeded == 1 && gate.pending == nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(egCount(host, "rummy_leave") == 0, "놀던 기기가 rummy_leave 를 보냈다")
        #expect(egCount(host, "rummy_heartbeat") == 0, "놀던 기기가 하트비트를 보냈다")
        #expect(holds.isEmpty, "놀던 기기가 App Nap 활동을 쥐었다")
        #expect(store.match?.id == egMatch, "놀던 기기가 남의 판을 접었다")
        // 로그아웃·계정 전환(reset)도 아무것도 안 보낸다.
        store.reset()
        try await Task.sleep(for: .milliseconds(150))
        #expect(egCount(host, "rummy_leave") == 0 && egCount(host, "rummy_heartbeat") == 0)
    }

    @Test("놀던 기기의 방(forming) — 손님 창 닫기도 그냥 닫히고 rummy_state·rummy_leave 를 보내지 않는다")
    func idleDeviceRoomCloseSendsNothing() async throws {
        // 없으면: 다른 맥에서 들어간 방을 이 맥 창 닫기가 묻지 않고 나가 버리는 결함이 초록이 된다.
        let script = EGScript()
        script.stand("rummy_leave", egEnvelope())
        script.stand("rummy_state", egEnvelope(state: egState(status: "forming", hostID: egB)))
        let (store, _, host) = egMake("idle-room", script: script, engaged: false)
        store.applyState(try egDecode(egState(status: "forming", hostID: egB)))
        #expect(store.phase == .room)
        let controller = CheckRummyWindowController(stuckWindowCheckSeconds: 60)
        #expect(controller.requestClose(store: store) && controller.lastCloseDecision == .close)
        #expect(!RummyExitPolicy.needsExitLeave(store))
        try await Task.sleep(for: .milliseconds(200))
        #expect(egCount(host, "rummy_leave") == 0 && egCount(host, "rummy_state") == 0 && egCount(host, "rummy_heartbeat") == 0)
        #expect(store.phase == .room)
    }

    @Test("손대면 engaged — 놀던 기기에서 끌기(draft)를 보내는 순간 하트비트·창 닫기 확인·종료 이탈이 선다")
    func draftMakesDeviceEngaged() async throws {
        // 없으면: 놀던 맥에서 이어 하기 시작해도 하트비트가 안 돌아 90초 뒤 끊김 기권되거나, 창 닫기가 묻지 않고 닫히는 결함이 초록이 된다.
        let script = EGScript()
        script.stand("rummy_draft", egEnvelope(extra: ["draft_seq": 2]))
        script.stand("rummy_heartbeat", egEnvelope())
        let (store, _, host) = egMake("adopt", script: script, engaged: false)
        store.applyState(try egDecode(egState()))
        #expect(RummyExitPolicy.closeDecision(for: store) == .close)
        let tile = try #require(store.editor?.rack.first?.id)
        store.moveTile(tile, to: .newMeld)
        await egWait { egCount(host, "rummy_draft") >= 1 }
        #expect(store.isEngaged(egMatch) && store.isHoldingMatch)
        await egWait { egCount(host, "rummy_heartbeat") >= 1 }
        #expect(egCount(host, "rummy_heartbeat") >= 1, "손댄 뒤에도 하트비트가 안 돈다")
        #expect(RummyExitPolicy.closeDecision(for: store) == .confirmForfeit)
        #expect(RummyExitPolicy.needsExitLeave(store))
    }

    @Test("engaged 가 서는 동작 — create·join·start·play·draw·react 각각 보내는 판을 적는다 · 못 앉은 join 은 걷는다")
    func everyWriteMarksEngaged() async throws {
        // 없으면: 이 기기에서 만든 방·누른 [완료]·뽑기·반응 뒤에도 engaged 가 아니어서 창을 닫아도 기권이 안 가는(판이 '플레이 중'으로 남는) 결함이 초록이 된다.
        let script = EGScript()
        script.stand("rummy_create", egEnvelope(state: egState(status: "forming"), extra: ["match_id": egID(egMatch)]))
        let (created, _, _) = egMake("create", script: script, engaged: false)
        created.createRoom()
        await created.actionTask?.value
        #expect(created.isEngaged(egMatch) && created.phase == .room && created.isHoldingMatch)

        let joinOK = EGScript()
        joinOK.stand("rummy_join", egEnvelope(state: egState(status: "forming", hostID: egB)))
        let (joined, _, _) = egMake("join", script: joinOK, engaged: false)
        joined.join(egMatch)
        await joined.actionTask?.value
        #expect(joined.isEngaged(egMatch) && joined.phase == .room)

        let joinFull = EGScript()
        joinFull.stand("rummy_join", egEnvelope("room_full"))
        joinFull.stand("rummy_lobby", egLobby(ruby: 50, active: nil))
        let (full, _, _) = egMake("join-full", script: joinFull, engaged: false)
        full.join(egMatch)
        await full.actionTask?.value
        #expect(!full.isEngaged(egMatch), "못 앉은 방이 engaged 로 남았다")

        let start = EGScript()
        start.stand("rummy_start", egEnvelope(state: egState()))
        let (starter, _, _) = egMake("start", script: start, engaged: false)
        starter.applyState(try egDecode(egState(status: "forming")))
        starter.startGame()
        await starter.actionTask?.value
        #expect(starter.isEngaged(egMatch) && starter.phase == .playing)

        let turn = EGScript()
        turn.stand("rummy_draw", egEnvelope(state: egState(seq: 2, turnSeat: 1)))
        turn.stand("rummy_play", egEnvelope(state: egState(seq: 2, turnSeat: 1)))
        let (drawer, _, _) = egMake("draw", script: turn, engaged: false)
        drawer.applyState(try egDecode(egState()))
        drawer.drawTile()
        await drawer.actionTask?.value
        #expect(drawer.isEngaged(egMatch))
        let (player, _, playHost) = egMake("play", script: turn, engaged: false)
        player.draftDebounceSeconds = 3_600   // 작업 상태 전송이 먼저 적지 않게 — [완료]만 잰다.
        player.applyState(try egDecode(egState()))
        let a4 = try #require(player.editor?.rack.first { $0.face == RummyFace(text: "A4") }?.id)
        player.moveTile(a4, to: .meld(0, index: nil))
        #expect(!player.isEngaged(egMatch), "끌기만으로(아직 안 보냄) engaged 가 됐다")
        player.submitTurn()
        await player.actionTask?.value
        #expect(egCount(playHost, "rummy_play") == 1 && egCount(playHost, "rummy_draft") == 0)
        #expect(player.isEngaged(egMatch))

        let react = EGScript()
        react.stand("rummy_react", egEnvelope())
        let (reactor, _, _) = egMake("react", script: react, engaged: false)
        reactor.applyState(try egDecode(egState(turnSeat: 1)))
        #expect(reactor.sendReaction(.heart))
        #expect(reactor.isEngaged(egMatch))
    }

    @Test("판이 끝나면 지운다 — 끝남·방 닫힘·이탈·[로비로] · 격리 defaults 에 남아 새 스토어(앱 재실행)가 이어받는다")
    func engagedLedgerPersistsAndClears() async throws {
        // 없으면: 앱을 다시 켠 맥이 쥐던 판의 하트비트를 잃어 90초 끊김 기권되거나, 끝난 판 id 가 쌓여 남는 결함이 초록이 된다.
        let defaults = CheckTestScratch.defaults("engaged")
        let key = RummyStore.engagedDefaultsKey
        let script = EGScript()
        script.stand("rummy_leave", egEnvelope())
        script.stand("rummy_heartbeat", egEnvelope())
        let (store, _, _) = egMake("persist", script: script, engaged: false)
        store.engagedDefaults = defaults
        store.markEngaged(egMatch)
        #expect(defaults.stringArray(forKey: key) == [egID(egMatch)])

        // 앱 재실행 — 저장소를 꽂으면 이어받고, 판을 읽으면 하트비트가 바로 선다.
        let (relaunched, _, host2) = egMake("persist-relaunch", script: script, engaged: false)
        relaunched.engagedDefaults = defaults
        #expect(relaunched.isEngaged(egMatch))
        relaunched.applyState(try egDecode(egState()))
        #expect(relaunched.heartbeatMatchID == egMatch && relaunched.isHoldingMatch)
        await egWait { egCount(host2, "rummy_heartbeat") >= 1 }
        // 판 끝 → 지운다(메모리·저장소 둘 다).
        relaunched.applyState(try egDecode(egState(status: "finished", seq: 9)))
        #expect(!relaunched.isEngaged(egMatch) && defaults.stringArray(forKey: key) == [])
        #expect(!relaunched.isHoldingMatch && relaunched.heartbeatMatchID == nil)

        // 방 닫힘(cancelled).
        let (room, _, _) = egMake("persist-cancel", script: script, engaged: true)
        room.engagedDefaults = defaults
        room.applyState(try egDecode(egState(status: "forming")))
        var cancelled = egState(status: "forming", seq: 2)
        cancelled["status"] = "cancelled"
        room.applyState(try egDecode(cancelled))
        #expect(!room.isEngaged(egMatch) && defaults.stringArray(forKey: key) == [])

        // 이탈(leaveForExit).
        let (leaver, _, host4) = egMake("persist-exit", script: script, engaged: true)
        leaver.applyState(try egDecode(egState()))
        #expect(await leaver.leaveForExit(reason: .appQuit))
        #expect(egCount(host4, "rummy_leave") == 1 && !leaver.isEngaged(egMatch) && !leaver.isHoldingMatch)

        // 상한 — 못 지운 것이 쌓여도 오래된 것부터 버린다.
        let (many, _, _) = egMake("persist-cap", script: script, engaged: false)
        for _ in 0..<(RummyStore.engagedLimit + 4) { many.markEngaged(UUID()) }
        #expect(many.engagedMatchIDs.count == RummyStore.engagedLimit)
    }

    // MARK: - 2. App Nap

    @Test("App Nap — engaged 판이 room·playing 인 동안만 활동 하나를 쥐고, 판 끝·이탈·로그아웃(reset)에서 놓는다")
    func appNapActivityFollowsHeldMatch() async throws {
        // 없으면: 창을 가린 채 두면 App Nap 이 하트비트를 늦춰 90초 끊김 기권되거나, 판이 끝난 뒤에도 활동이 남아 배터리를 먹는 결함이 초록이 된다.
        var begun = 0, ended = 0
        let hold = RummyActivityHold(begin: { _ in begun += 1; return NSObject() }, end: { _ in ended += 1 })
        let script = EGScript()
        script.stand("rummy_heartbeat", egEnvelope())
        script.stand("rummy_leave", egEnvelope())
        let (store, _, _) = egMake("nap", script: script, engaged: true)
        store.onHoldingMatchChange = { hold.set($0) }
        store.applyState(try egDecode(egState(status: "forming")))
        #expect(begun == 1 && hold.isHolding)
        store.applyState(try egDecode(egState(seq: 2)))
        #expect(begun == 1, "방 → 판 전환이 활동을 하나 더 쥐었다")
        store.applyState(try egDecode(egState(status: "finished", seq: 9)))
        #expect(ended == 1 && !hold.isHolding)

        let (exiting, _, _) = egMake("nap-exit", script: script, engaged: true)
        exiting.onHoldingMatchChange = { hold.set($0) }
        exiting.applyState(try egDecode(egState()))
        #expect(begun == 2)
        _ = await exiting.leaveForExit(reason: .windowClosed)
        #expect(ended == 2)

        let (signedOut, _, _) = egMake("nap-reset", script: script, engaged: true)
        signedOut.onHoldingMatchChange = { hold.set($0) }
        signedOut.applyState(try egDecode(egState()))
        #expect(begun == 3)
        signedOut.reset()
        #expect(ended == 3 && !signedOut.isHoldingMatch)
        // 같은 값이 두 번 와도 하나만.
        hold.set(true); hold.set(true); hold.set(false); hold.set(false)
        #expect(begun == 4 && ended == 4)
    }

    @Test("App Nap 배선 — 앱이 engaged 저장소·활동 훅을 꽂고, 활동은 잠자기를 막지 않는 .userInitiatedAllowingIdleSystemSleep")
    func appNapWiringContract() throws {
        // 없으면: 코어 훅만 있고 앱이 안 꽂아 App Nap 이 그대로이거나, 활동이 시스템 잠자기까지 막는 결함이 초록이 된다.
        let app = V0317ShopTests.stripped(try V0317ShopTests.source("CheckApp.swift"))
        #expect(app.contains("rummy.engagedDefaults = .standard"))
        #expect(app.contains("let rummyActivity = RummyActivityHold()"))
        #expect(app.contains("rummy.onHoldingMatchChange = { holding in rummyActivity.set(holding) }"))
        let flow = V0317ShopTests.stripped(try V0317ShopTests.source("RummyExitFlow.swift"))
        #expect(flow.contains("ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: reason)"))
        #expect(flow.contains("ProcessInfo.processInfo.endActivity($0)"))
        // 실제 활동 하나를 쥐었다 놓아 본다(창 없음 · 시스템 상태를 남기지 않는다).
        let real = RummyActivityHold()
        real.set(true)
        #expect(real.isHolding)
        real.set(false)
        #expect(!real.isHolding)
    }

    // MARK: - 3. 판 중 업데이트 확인

    @Test("업데이트 판단 표 — engaged 판(내 자리 playing)=기권 확인 · 방=나가기 확인 · 그 밖·놀던 기기=바로")
    func updateDecisionTable() {
        typealias P = RummyExitPolicy
        #expect(P.updateDecision(phase: .playing, mySeatState: .playing, engaged: true) == .confirmForfeit)
        #expect(P.updateDecision(phase: .playing, mySeatState: .forfeit, engaged: true) == .proceed)
        #expect(P.updateDecision(phase: .playing, mySeatState: .playing, engaged: false) == .proceed)
        #expect(P.updateDecision(phase: .room, mySeatState: .joined, engaged: true) == .confirmLeaveRoom)
        #expect(P.updateDecision(phase: .room, mySeatState: .joined, engaged: false) == .proceed)
        #expect(P.updateDecision(phase: .lobby, mySeatState: nil, engaged: true) == .proceed)
        #expect(P.updateDecision(phase: .finished, mySeatState: .done, engaged: true) == .proceed)
        #expect(P.closeDecision(phase: .playing, mySeatState: .playing, amHost: false, engaged: false) == .close)
        #expect(!P.needsExitLeave(phase: .room, mySeatState: .joined, engaged: false))
    }

    @Test("판 중 [지금 업데이트] — 확인을 띄우고, 취소는 아무것도 안 하고, 승인은 기권(rummy_leave) 뒤에 업데이트한다")
    func updateDuringMatchAsksThenForfeits() async throws {
        // 없으면: 판 중 업데이트가 묻지 않고 앱을 꺼 하트비트 90초 뒤 끊김 기권(남은 사람은 90초 기다림)되거나, [계속하기] 가 기권·업데이트를 보내는 결함이 초록이 된다.
        let script = EGScript()
        script.stand("rummy_leave", egEnvelope())
        let (store, _, host) = egMake("update", script: script, engaged: true)
        store.applyState(try egDecode(egState()))
        let gate = RummyUpdateGate()
        var updates = 0
        gate.request(store: store) { updates += 1 }
        #expect(gate.pending == .confirmForfeit && updates == 0)
        gate.cancel()
        try await Task.sleep(for: .milliseconds(150))
        #expect(gate.pending == nil && updates == 0 && egCount(host, "rummy_leave") == 0 && store.phase == .playing)

        gate.request(store: store) { updates += 1 }
        gate.confirm()
        #expect(gate.isLeaving)
        await gate.leaveTask?.value
        #expect(egCount(host, "rummy_leave") == 1 && updates == 1 && !gate.isLeaving)
        #expect(store.match == nil && !store.isHoldingMatch)

        // 묻는 사이 판이 끝났다 — 승인은 보내지 않고 업데이트만.
        let (late, _, lateHost) = egMake("update-finished", script: script, engaged: true)
        late.applyState(try egDecode(egState()))
        gate.request(store: late) { updates += 1 }
        late.applyState(try egDecode(egState(status: "finished", seq: 9)))
        gate.confirm()
        await gate.leaveTask?.value
        #expect(updates == 2 && egCount(lateHost, "rummy_leave") == 0)
        // 스토어가 없으면(미리보기) 그냥 업데이트.
        gate.request(store: nil) { updates += 1 }
        #expect(updates == 3)
    }

    @Test("방에서 [지금 업데이트] — '방에서 나가요' 확인 → 나간 뒤 업데이트 · 묻는 사이 판이 시작됐으면 기권 문구로 다시 묻는다")
    func updateInRoomLeavesOrReasks() async throws {
        // 없으면: "루비는 그대로예요" 를 읽고 누른 버튼이 그새 시작된 판의 기권(판돈 잃음)이 되는 결함이 초록이 된다.
        let script = EGScript()
        script.stand("rummy_state", egEnvelope(state: egState(status: "forming")))
        script.stand("rummy_leave", egEnvelope())
        let (store, _, host) = egMake("update-room", script: script, engaged: true)
        store.applyState(try egDecode(egState(status: "forming")))
        let gate = RummyUpdateGate()
        var updates = 0
        gate.request(store: store) { updates += 1 }
        #expect(gate.pending == .confirmLeaveRoom)
        gate.confirm()
        await gate.leaveTask?.value
        #expect(egCount(host, "rummy_leave") == 1 && updates == 1 && store.phase == .lobby)

        // 확인을 띄운 사이 시작 state 가 닿았다.
        let (racing, _, raceHost) = egMake("update-room-start", script: script, engaged: true)
        racing.applyState(try egDecode(egState(status: "forming")))
        gate.request(store: racing) { updates += 1 }
        racing.applyState(try egDecode(egState(seq: 2)))
        gate.confirm()
        #expect(gate.pending == .confirmForfeit && updates == 1 && egCount(raceHost, "rummy_leave") == 0)
        gate.cancel()

        // 서버에선 이미 시작됐는데 이 기기는 아직 방 — 나가기 전 조회가 판을 들고 기권 확인으로 다시 묻는다.
        let started = EGScript()
        started.stand("rummy_state", egEnvelope(state: egState(seq: 2, hostID: egB, turnSeat: 1)))
        started.stand("rummy_leave", egEnvelope())
        let (guest, _, guestHost) = egMake("update-room-guest", script: started, engaged: true)
        guest.applyState(try egDecode(egState(status: "forming", hostID: egB)))
        gate.request(store: guest) { updates += 1 }
        gate.confirm()
        await gate.leaveTask?.value
        #expect(gate.pending == .confirmForfeit && updates == 1 && egCount(guestHost, "rummy_leave") == 0)
        #expect(guest.phase == .playing)
    }

    @Test("업데이트 배선 — 배너 [지금 업데이트]가 게이트를 거쳐 기존 runUpgrade 로 가고, 메뉴가 아잉 큐브 스토어를 넘긴다")
    func updateBannerWiringContract() throws {
        // 없으면: 게이트·확인 줄은 있는데 배너 버튼이 예전처럼 runUpgrade 를 바로 불러 판 중에도 묻지 않는 결함이 초록이 된다.
        let menu = V0317ShopTests.stripped(try V0317ShopTests.source("CheckMenuView.swift"))
        #expect(menu.contains("rummyGate.request(store: rummy) { runner.runUpgrade() }"))
        #expect(menu.contains("UpdateBanner(versionText: updateBannerVersionText, notes: updateBannerNotes, rummy: store.rummy,"))
        #expect(menu.contains("RummyUpdateConfirmRow(decision: pending, onConfirm: { rummyGate.confirm() }, onCancel: { rummyGate.cancel() })"))
        let banner = try #require(menu.range(of: "private struct UpdateBanner: View {"))
        let rest = menu[banner.upperBound...]
        let end = try #require(rest.range(of: "#endif"))
        let body = String(rest[..<end.lowerBound])
        #expect(body.components(separatedBy: "runner.runUpgrade()").count == 2, "배너에 게이트를 거치지 않는 runUpgrade 가 있다")
    }

    // MARK: - 4. 판 화면 머리글 루비

    @Test("루비 잔액 — 로비에서 안 값을 판 중에도 들고, 판돈 차감(시작)·정산(끝)을 처음 본 순간 로비로 다시 맞춘다")
    func rubyBalanceSurvivesMatchAndRefreshes() async throws {
        // 없으면: 판 화면 머리글 💎 칸이 '—' 로 남거나(판 중엔 로비가 없다), 판돈을 뗀 뒤·정산 뒤에도 옛 잔액을 보이는 결함이 초록이 된다.
        let script = EGScript()
        script.stand("rummy_lobby", egLobby(ruby: 100, active: nil))
        let (store, host, _) = egMake("ruby", script: script, engaged: true)
        await store.refreshLobby()
        #expect(store.rubyBalance == 100 && host.rubyBalance == 100)

        // 시작 — 서버가 판돈 5 를 뗐다.
        script.stand("rummy_lobby", egLobby(ruby: 95, active: egMatch))
        store.applyState(try egDecode(egState()))
        await egWait { store.rubyBalance == 95 }
        #expect(store.phase == .playing && store.rubyBalance == 95, "판돈 차감이 머리글에 안 닿는다")
        // 판 중 다른 state 가 와도 잔액은 남는다.
        store.applyState(try egDecode(egState(seq: 3, turnSeat: 1)))
        #expect(store.rubyBalance == 95)

        // 끝 — 정산으로 10 을 받았다.
        script.stand("rummy_lobby", egLobby(ruby: 105, active: nil))
        store.applyState(try egDecode(egState(status: "finished", seq: 9)))
        await egWait { store.rubyBalance == 105 }
        #expect(store.phase == .finished && store.rubyBalance == 105 && host.rubyBalance == 105, "정산이 머리글에 안 닿는다")

        // 거절 응답의 잔액(insufficient)도 받는다 · 로그아웃은 지운다.
        let refuse = EGScript()
        refuse.stand("rummy_create", egEnvelope("insufficient", extra: ["need": 5, "have": 2, "ruby_balance": 2]))
        let (poor, _, _) = egMake("ruby-poor", script: refuse, engaged: false)
        poor.createRoom()
        await poor.actionTask?.value
        #expect(poor.rubyBalance == 2)
        store.reset()
        #expect(store.rubyBalance == nil)

        // 장면: 로비가 없어도(판 중) 스토어 값이 머리글에 간다.
        let match = try egDecode(egState())
        let scene = RummyScene(phase: .playing, availability: .available, lobby: nil, match: match, editor: nil,
                               isMyTurn: true, otherDraft: nil, notice: nil, isWorking: false, ranking: nil,
                               myUserID: egMe, fixedNow: nil, isPreview: true, rubyBalance: 95)
        #expect(scene.shownRubyBalance == 95)
        var blank = scene
        blank.rubyBalance = nil
        #expect(blank.shownRubyBalance == nil)
    }

    @Test("판 화면 머리글 렌더 — 잔액을 주면 💎 칸이 '—' 와 다르게 그려진다(v2f/stills 에 굽는다)")
    func headerRubyRenders() throws {
        // 없으면: 스토어에 잔액이 있어도 판 화면 머리글이 로비만 읽어 '—' 를 그리는 결함이 초록이 된다.
        let match = try egDecode(egState())
        let editor = RummyTurnEditor(table: [["A1", "A2", "A3"]].map { $0.compactMap(RummyFace.init(text:)) },
                                     rack: ["A4", "B9", "C2", "D13", "J"].compactMap(RummyFace.init(text:)), initialDone: true)
        func render(_ balance: Int?, name: String) throws -> NSBitmapImageRep {
            let panel = RummyPanel(store: RummyStore(), me: { ChessPlayerFace.fallback }, clipsOverflowInsteadOfScroll: true,
                                   previewMatch: match, previewEditor: editor, previewNow: egWall0,
                                   previewMyUserID: egMe, previewRubyBalance: balance)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: panel.fixedSize())
            renderer.scale = 2
            _ = renderer.nsImage
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:])
            else { throw EGError() }
            try? FileManager.default.createDirectory(atPath: egStillsDir, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: "\(egStillsDir)/\(name).png"))
            return bitmap
        }
        _ = try render(nil, name: "rummy2-my-turn-ruby-warmup")   // 첫 렌더는 다르게 나온다(실측) — 굳힌 뒤 비교한다.
        let shown = try render(1_234, name: "rummy2-my-turn-ruby")
        let blank = try render(nil, name: "rummy2-my-turn-ruby-baseline")
        #expect(shown.pixelsWide == blank.pixelsWide && shown.pixelsHigh == blank.pixelsHigh)
        // 머리글 띠(위 70pt)만 달라야 한다 — 판·받침대는 같다.
        func differing(_ rows: Range<Int>) -> Int {
            guard let a = shown.bitmapData, let b = blank.bitmapData else { return -1 }
            let bpr = shown.bytesPerRow
            var count = 0
            for y in rows { for x in 0..<bpr where a[y * bpr + x] != b[y * bpr + x] { count += 1 } }
            return count
        }
        let header = differing(0..<min(140, shown.pixelsHigh))
        let below = differing(200..<shown.pixelsHigh)
        #expect(header > 200, "머리글 💎 칸이 잔액을 그리지 않는다(다른 바이트 \(header))")
        // 아래(판·받침대)는 렌더 잔차(펠트 결·안티에일리어싱)만 — 머리글 차이의 1/4 밑이어야 한다(실측 아래 7,128 바이트).
        #expect(below * 4 < header, "머리글 밖이 크게 달라졌다(머리글 \(header) · 아래 \(below))")
    }
}

// MARK: - 적대 검증(rummy-v2-fixverify) — 놀던 기기가 스스로 engaged 가 되는 길 · 계정이 바뀐 장부

@Suite("v0.3.69 아잉 큐브 2판 후속 적대 검증 — 놀던 기기는 스스로 손대지 않는다 · 장부는 계정에 묶인다", .serialized)
@MainActor
struct V0369RummyV2FixVerifyTests {
    @Test("놀던 기기가 차례 중간 state(다른 맥의 작업 판)를 처음 읽어도 rummy_draft 0회 · engaged 안 됨 — 손댄 기기(앱 재실행)는 예전처럼 맞춘다")
    func idleDeviceDoesNotRevertOtherDevicesDraft() async throws {
        // 없으면: 놀던 맥이 판을 처음 읽는 순간(초인종·깨어남·앱 실행) 차례 중간 서버 작업 판을 '내 화면과 다르다' 며 시작 판으로
        // 되돌려 보내(다른 맥의 작업을 지우고) 스스로 engaged 가 되어, 그 맥을 끄거나 로그아웃하면 다른 맥의 판이 기권되는 결함이 초록이 된다.
        var midTurn = egState()
        midTurn["draft"] = ["table": [["A1", "A2", "A3", "A4"]], "layout": [[0, 0]], "draft_seq": 3, "at_ms": egNowMs]
        let script = EGScript()
        script.stand("rummy_draft", egEnvelope())
        script.stand("rummy_heartbeat", egEnvelope())
        script.stand("rummy_leave", egEnvelope())
        script.stand("rummy_state", egEnvelope(state: midTurn))
        let (idle, _, idleHost) = egMake("fv-idle-draft", script: script, engaged: false)
        await idle.refreshMatch(id: egMatch)
        #expect(idle.phase == .playing && idle.isMyTurn && idle.editor != nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(egCount(idleHost, "rummy_draft") == 0, "놀던 기기가 다른 맥의 작업 판을 되돌려 보냈다")
        #expect(!idle.isEngaged(egMatch), "놀던 기기가 스스로 engaged 가 됐다")
        #expect(!RummyExitPolicy.needsExitLeave(idle))
        #expect(await idle.leaveForExit(reason: .appQuit))
        #expect(egCount(idleHost, "rummy_leave") == 0 && egCount(idleHost, "rummy_heartbeat") == 0)

        // 비교 기준선: 이 판에 손댄 기기(앱 재실행 — 저장소에서 이어받았다)는 화면에 없는 작업 판을 예전처럼 되돌린다.
        let (owner, _, ownerHost) = egMake("fv-owner-draft", script: script, engaged: true)
        await owner.refreshMatch(id: egMatch)
        await egWait { egCount(ownerHost, "rummy_draft") >= 1 }
        #expect(egCount(ownerHost, "rummy_draft") == 1, "손댄 기기가 화면에 없는 작업 판을 맞추지 않는다")
    }

    @Test("계정이 바뀌면 앞 계정의 engaged 장부를 쓰지 않는다 — 같은 판의 상대 계정으로 들어와도 rummy_leave·하트비트 0회, 같은 계정은 이어진다")
    func engagedLedgerIsBoundToAccount() async throws {
        // 없으면: 강제 로그아웃(토큰 만료 — 이탈 없음)으로 남은 앞 계정의 engaged 판 id 가, 같은 판의 상대 계정이 이 맥에 들어오면
        // 그대로 맞아 이 맥을 끄거나 로그아웃할 때 손대지 않은 판이 기권되는 결함이 초록이 된다.
        let defaults = CheckTestScratch.defaults("engaged-owner")
        var asB = egState()
        asB["my_seat_no"] = 1
        let script = EGScript()
        script.stand("rummy_heartbeat", egEnvelope())
        script.stand("rummy_leave", egEnvelope())
        script.stand("rummy_state", egEnvelope(state: asB))
        let sessionA = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: egID(egMe))
        let sessionB = SupabaseSession(accessToken: "access-token-b", refreshToken: nil, userID: egID(egB))
        let (store, owner, host) = egMake("fv-account", script: script, engaged: false)
        store.engagedDefaults = defaults
        store.markEngaged(egMatch)                 // A 가 이 맥에서 둔 판
        store.reset()                              // 강제 로그아웃(이탈 없음) — 장부는 남는다(같은 사람 재로그인용)
        owner.session = sessionB                   // 같은 판의 상대 B 가 이 맥에 들어온다
        await store.refreshMatch(id: egMatch)
        #expect(store.phase == .playing && store.match?.id == egMatch)
        #expect(!store.isEngaged(egMatch), "B 가 A 의 장부로 engaged 다")
        #expect(!RummyExitPolicy.needsExitLeave(store))
        #expect(store.heartbeatMatchID == nil && !store.isHoldingMatch)
        #expect(await store.leaveForExit(reason: .signOut))
        try await Task.sleep(for: .milliseconds(200))
        #expect(egCount(host, "rummy_leave") == 0 && egCount(host, "rummy_heartbeat") == 0, "B 의 판에 이탈·하트비트가 갔다")
        // 앱 재실행으로 저장소를 이어받아도 B 에겐 아니다.
        let (relaunched, owner2, _) = egMake("fv-account-relaunch", script: script, engaged: false)
        owner2.session = sessionB
        relaunched.engagedDefaults = defaults
        #expect(!relaunched.isEngaged(egMatch))
        // 같은 계정(A)이 다시 들어오면 이어진다(토큰 만료 강제 로그아웃 뒤 재로그인 — 수리 보고의 의도).
        let (sameA, _, _) = egMake("fv-account-same", script: script, engaged: false)
        sameA.engagedDefaults = defaults
        #expect(sameA.isEngaged(egMatch))
        // B 가 이 맥에서 손대면 장부는 B 의 것으로 새로 열린다(A 의 판 id 는 버린다).
        let other = UUID()
        relaunched.markEngaged(other)
        #expect(relaunched.engagedMatchIDs == [other] && relaunched.isEngaged(other))
    }

    @Test("App Nap — 내 자리가 기권한 뒤 남의 판을 지켜보는 동안은 놓는다(판이 끝날 때까지 쥐지 않는다)")
    func appNapReleasesWhenMySeatForfeits() async throws {
        // 없으면: 시간 초과로 기권된 뒤 판이 끝날 때까지(남은 사람들이 둘 동안) App Nap 을 막는 활동이 남아 배터리를 먹는 결함이 초록이 된다.
        var begun = 0, ended = 0
        let hold = RummyActivityHold(begin: { _ in begun += 1; return NSObject() }, end: { _ in ended += 1 })
        let script = EGScript()
        script.stand("rummy_heartbeat", egEnvelope())
        let (store, _, _) = egMake("fv-nap-forfeit", script: script, engaged: true)
        store.onHoldingMatchChange = { hold.set($0) }
        store.applyState(try egDecode(egState(turnSeat: 1)))
        #expect(begun == 1 && hold.isHolding)
        var spectating = egState(seq: 2, turnSeat: 1)
        var seats = spectating["seats"] as! [[String: Any]]
        seats[0]["state"] = "forfeit"
        spectating["seats"] = seats
        store.applyState(try egDecode(spectating))
        #expect(store.phase == .playing && store.match?.id == egMatch, "기권한 자리는 관전으로 판을 든다")
        #expect(ended == 1 && !hold.isHolding && !store.isHoldingMatch, "기권한 뒤에도 App Nap 활동을 쥐었다")
        #expect(!RummyExitPolicy.needsExitLeave(store))
    }
}

// MARK: - 확성기 배너 미룸(main 확성기 배너와 합친 뒤 — 버그 개선 세션 요청)

@MainActor
struct V0369RummyMegaphoneDeferralTests {
    @Test("확성기 배너 미룸 — 손댄 판 진행 중(내 자리 playing)만 미룬다 · 놀던 맥·기권 뒤 구경·끝난 판은 안 미룬다")
    func rummyDefersMegaphoneOnlyWhilePlaying() throws {
        // 없으면: 아잉 큐브 판 위로 확성기 배너가 내려와 끌기 중인 타일 위를 덮는다(오목·체스·테트리스는 이미 미룬다).
        let (playing, _, _) = egMake("mg-play", script: EGScript(), engaged: true)
        playing.applyState(try egDecode(egState()))
        #expect(playing.phase == .playing)
        #expect(playing.defersMegaphoneBanner, "내가 하는 판인데 배너를 안 미룬다")
        #expect(MegaphoneBannerDeferral.isDeferred(gomoku: .lobby, chess: .lobby, tetris: .lobby, miniGameRoundLive: false,
                                                   rummyLive: playing.defersMegaphoneBanner))

        let (idle, _, _) = egMake("mg-idle", script: EGScript(), engaged: false)
        idle.applyState(try egDecode(egState()))
        #expect(idle.phase == .playing && !idle.defersMegaphoneBanner, "놀던 맥(engaged 아님)이 배너를 미뤘다")

        var forfeited = egState(seq: 2)
        var seats = try #require(forfeited["seats"] as? [[String: Any]])
        seats[0] = egSeat(0, egMe, state: "forfeit")
        forfeited["seats"] = seats
        forfeited["my_rack"] = NSNull()
        playing.applyState(try egDecode(forfeited))
        #expect(!playing.defersMegaphoneBanner, "기권한 뒤 구경 중인데 배너를 미뤘다")

        playing.applyState(try egDecode(egState(status: "finished", seq: 3)))
        #expect(!playing.defersMegaphoneBanner, "끝난 판인데 배너를 미뤘다")
        // 기준선: 아무 판도 없으면 미루지 않는다.
        #expect(!MegaphoneBannerDeferral.isDeferred(gomoku: .lobby, chess: .lobby, tetris: .lobby, miniGameRoundLive: false))
    }

    @Test("배선 — isMegaphoneBannerDeferred 가 rummy.defersMegaphoneBanner 를 넘긴다(관찰 추적이 판 상태를 읽게)")
    func megaphoneDeferralWiring() throws {
        let src = try String(contentsOf: CheckCoreSourceLayout.repoRoot.appendingPathComponent("Sources/check/WorkTimerStoreMegaphoneBanner.swift"),
                             encoding: .utf8)
        #expect(src.contains("rummyLive: rummy.defersMegaphoneBanner"))
    }
}
