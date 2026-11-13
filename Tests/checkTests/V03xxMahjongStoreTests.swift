@testable import CheckCore
import Foundation
import Testing

// 아잉 마작 스토어 표면 시험(갈래 C1 — SPEC §4.5). 스텁 서버 장면(로비 → 방 → 시작 → 차례 → … → 판 끝) · 리버시 적대 검증
// 여섯 장면 · 깨우기 · 요청 마감은 C2 가 이 파일에 더한다. 여기서는 네트워크 없이 `applyState` 의 칸 나눔과 가드만 잰다.

@MainActor
@Suite("아잉 마작 스토어 표면 — 칸 나눔 · 결정 키 접기 · 늦은 응답 가드")
struct V03xxMahjongStoreTests {
    private static func decode(_ text: String) throws -> MahjongStatePayload {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MahjongStatePayload.self, from: Data(text.utf8))
    }

    private static func turnState(seq: Int, decisionSeq: Int?, handIndex: Int = 3, status: String = "active") -> String {
        let decision = decisionSeq.map {
            #"{"kind":"turn","seq":\#(seq),"decision_seq":\#($0),"started_ms":1000,"deadline_ms":6000,"bank_ms":20000,"#
                + #""discard":[0,4],"riichi":[0,4],"tsumo":false,"ankan":[],"kakan":[],"kyuushu":false}"#
        } ?? "null"
        return #"{"match":{"id":"m-1","status":"\#(status)","seq":\#(seq),"hand_index":\#(handIndex),"phase":"turn"},"#
            + #""my_seat":0,"my_hand":[0,4],"my_decision":\#(decision),"server_now_ms":1000}"#
    }

    @Test("서버 state 는 match 에만 · 연습 칸과 따로 · table 한 길 · 단계 playing")
    func serverStateLandsInMatchOnly() throws {
        // 없으면: 연습판과 서버 방이 한 칸을 나눠 써서 연습 중 온 방 응답이 연습 탁자를 덮는다(CC-02).
        let store = MahjongStore()
        #expect(store.applyState(try Self.decode(Self.turnState(seq: 5, decisionSeq: 2))) == .applied)
        #expect(store.match?.match?.id == "m-1")
        #expect(store.practice == nil && !store.isPractice)
        #expect(store.table == store.match)
        #expect(store.phase == .playing)
        // 연습판 id 는 서버 경로로 못 들어온다(가드 (g)).
        let practice = try Self.decode(Self.turnState(seq: 9, decisionSeq: 1).replacingOccurrences(of: "m-1", with: "ai-1"))
        #expect(store.applyState(practice) == .ignored)
        #expect(store.match?.match?.id == "m-1")
    }

    @Test("결정 키가 바뀌면 리치 무장을 접는다 — 같은 키 state 가 다시 오면 무장 유지(기준선)")
    func riichiArmFoldsOnDecisionKeyChange() throws {
        // 없으면: 무장한 채 시간 초과되면 다음 차례 클릭이 원치 않은 리치(−1000·손 잠김)가 된다(CC-03).
        let store = MahjongStore()
        store.applyState(try Self.decode(Self.turnState(seq: 5, decisionSeq: 2)))
        store.armRiichi()
        #expect(store.riichiArmed)
        // 기준선: 같은 결정 키(decision_seq 2) — 무장 유지.
        store.applyState(try Self.decode(Self.turnState(seq: 5, decisionSeq: 2)))
        #expect(store.riichiArmed)
        // 새 결정(decision_seq 3) — 접힌다.
        store.applyState(try Self.decode(Self.turnState(seq: 7, decisionSeq: 3)))
        #expect(!store.riichiArmed)
        // 결정이 없어져도 접힌다.
        store.armRiichi()
        #expect(store.riichiArmed)
        store.applyState(try Self.decode(Self.turnState(seq: 8, decisionSeq: nil)))
        #expect(!store.riichiArmed)
    }

    @Test("늦은 응답 — 낮은 seq · 이전 국 · 판이 된 id 의 forming 응답은 버린다(ⓔ)")
    func lateResponsesAreIgnored() throws {
        // 없으면: 망 재정렬로 늦게 온 옛 state 가 화면을 되돌리거나, 판이 된 방에 늦은 방 응답이 와 방 화면으로 돌아간다(V2-04).
        let store = MahjongStore()
        store.applyState(try Self.decode(Self.turnState(seq: 10, decisionSeq: 4, handIndex: 3)))
        #expect(store.applyState(try Self.decode(Self.turnState(seq: 9, decisionSeq: 4, handIndex: 3))) == .ignored)
        #expect(store.applyState(try Self.decode(Self.turnState(seq: 12, decisionSeq: 4, handIndex: 2))) == .ignored)
        #expect(store.applyState(try Self.decode(Self.turnState(seq: 11, decisionSeq: 5, status: "forming"))) == .ignored)
        #expect(store.match?.match?.seq == 10)
        #expect(store.phase == .playing)
        // 기준선: 더 새 seq 는 들어간다.
        #expect(store.applyState(try Self.decode(Self.turnState(seq: 11, decisionSeq: 5))) == .applied)
        #expect(store.match?.match?.seq == 11)
    }

    @Test("창이 탁자를 보인다 = 보임 && 안 가려짐(ⓐ)")
    func windowShowingTableNeedsVisibleAndUnoccluded() {
        // 없으면: 가려진 창(전체 화면 앱)을 보이는 것으로 쳐 내 차례 말풍선이 죽는다(CC-01 · V2-01).
        let store = MahjongStore()
        #expect(!store.isWindowShowingTable)
        store.windowDidShow()
        #expect(store.isWindowShowingTable)
        store.windowOcclusionDidChange(visible: false)
        #expect(store.isWindowVisible && !store.isWindowShowingTable)
        store.windowOcclusionDidChange(visible: true)
        #expect(store.isWindowShowingTable)
        store.windowDidHide()
        #expect(!store.isWindowShowingTable)
    }
}

// MARK: - 하네스(C2) — 스텁 서버 · 호스트 · 장면 픽스처(`Fixtures/mahjong-scenes` — 한 판 이야기를 같은 id·시각·seq 로 잇는
// C2 픽스처. 모양은 `V03xxMahjongFixtureContractTests.sceneFixturesStayInsideTheRealShape` 가 실응답 62 안에 묶는다.
// 실응답 원문은 `Fixtures/mahjong-rpc` — 아래 `V03xxMahjongStoreRealResponseTests` 가 스토어에 그대로 먹인다)
//
// 서버는 오목 `GomokuStubProtocol`(호스트별 스크립트) · defaults 는 `GomokuTestDefaults` 격리. 벽시계는 주입, 폴링 루프는 3,600초로
// 재우고 `pollTick(at:)`·`checkWake(at:)` 를 직접 밟는다(`timersEnabled = false`). 각 시험 첫 줄 주석은 "없으면 어떤 결함이 초록인가".

let mjA = "00000000-0000-0000-0000-0000000000a1"
let mjB = "00000000-0000-0000-0000-0000000000b2"
let mjD = "00000000-0000-0000-0000-0000000000d4"
let mjRoom = "7e7e0000-0000-4000-8000-0000000000aa"
let mjT0Ms: Double = 1_800_000_000_000
func mjDate(ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1_000) }
func mjTile(_ id: Int) -> MahjongTile { MahjongTile(id: id)! }

struct MJStubError: Error {}

@MainActor
final class MJHost: GomokuStoreHost {
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
        guard let session else { throw MJStubError() }
        return try await operation(session)
    }

    func classifyAuthError(_ error: Error) -> AuthErrorDisposition { .transient }
}

@MainActor
enum MJRetention { static var hosts: [MJHost] = [] }

final class MJClock: @unchecked Sendable { var now = mjDate(ms: mjT0Ms) }

/// rpc 별 응답: 줄 세운 것이 먼저, 그다음 고정. 없으면 nil(`[]` 200 — 디코드 실패).
final class MJServer: @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [String: [GomokuStubProtocol.Reply]] = [:]
    private var standing: [String: GomokuStubProtocol.Reply] = [:]

    func set(_ rpc: String, _ body: String, status: Int = 200, delay: TimeInterval = 0) {
        lock.lock()
        standing[rpc] = GomokuStubProtocol.Reply(status: status, body: body, delay: delay)
        lock.unlock()
    }

    func enqueue(_ rpc: String, _ body: String, status: Int = 200, delay: TimeInterval = 0) {
        lock.lock()
        queued[rpc, default: []].append(GomokuStubProtocol.Reply(status: status, body: body, delay: delay))
        lock.unlock()
    }

    func handler() -> GomokuStubProtocol.Handler {
        { [self] rpc, _, _ in
            lock.lock()
            defer { lock.unlock() }
            if var line = queued[rpc], !line.isEmpty {
                let reply = line.removeFirst()
                queued[rpc] = line
                return reply
            }
            return standing[rpc]
        }
    }
}

@MainActor
final class MJTally {
    var presents = 0
    var attentionRequests = 0
    var attentions: [MahjongAttention] = []
    var invites: [UUID] = []
    var finished = 0
    func kinds(_ kind: MahjongAttention.Kind) -> Int { attentions.filter { $0.kind == kind }.count }
}

@MainActor
struct MJDevice {
    let store: MahjongStore
    let stub: String
    let clock: MJClock
    let tally: MJTally
    let host: MJHost
    func calls(_ rpc: String) -> [GomokuStubProtocol.Call] { GomokuStubProtocol.calls(host: stub, rpc: "mahjong_\(rpc)") }
    func count(_ rpc: String) -> Int { calls(rpc).count }
}

/// 같은 사람(`me`)의 기기 하나 — 자기 스텁 호스트 · 자기 장부 defaults(= 다른 맥).
@MainActor
func mjDevice(_ label: String, me: String = mjA, server: MJServer, ledger: UserDefaults? = nil) -> MJDevice {
    let stub = "mj-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: stub, handler: server.handler())
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(stub)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
    let host = MJHost(service: service, me: me)
    MJRetention.hosts.append(host)
    let clock = MJClock()
    let store = MahjongStore(clock: { clock.now })
    store.deviceLedger.defaults = ledger ?? GomokuTestDefaults.make("mj")
    store.pollStepSeconds = 3_600
    store.timersEnabled = false
    store.attach(host: host)
    let tally = MJTally()
    store.presentWindow = { tally.presents += 1 }
    store.requestAttention = { tally.attentionRequests += 1 }
    store.onAttention = { tally.attentions.append($0) }
    store.onInviteArrived = { tally.invites.append($0.id) }
    store.onMatchFinished = { tally.finished += 1 }
    return MJDevice(store: store, stub: stub, clock: clock, tally: tally, host: host)
}

@MainActor
func mjWait(_ seconds: Double = 2, _ condition: @MainActor () -> Bool) async {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(2)) }
}

/// 초인종 한 번이 끝까지 돈다.
@MainActor
func mjRing(_ store: MahjongStore) async {
    store.handleSignal()
    await mjWait { store.syncTask == nil && store.stateInFlightID == nil }
}

enum MJFixture {
    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/mahjong-scenes", isDirectory: true)
    /// S2 하네스 실응답 원문(바이트 그대로).
    static let realDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/mahjong-rpc", isDirectory: true)

    static func real(_ name: String) throws -> MahjongActionResponse {
        try decoder().decode(MahjongActionResponse.self, from: Data(contentsOf: realDir.appendingPathComponent("\(name).json")))
    }

    static func realText(_ name: String) throws -> String {
        try String(contentsOf: realDir.appendingPathComponent("\(name).json"), encoding: .utf8)
    }

    static func text(_ name: String) throws -> String {
        try String(contentsOf: dir.appendingPathComponent("\(name).json"), encoding: .utf8)
    }

    static func object(_ name: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(text(name).utf8)) as? [String: Any] ?? [:]
    }

    /// 원문 한 벌을 고친 응답 원문(`state` 안을 고칠 땐 `edit` 이 top["state"] 를 다룬다).
    static func mutated(_ name: String, _ edit: (inout [String: Any]) -> Void) throws -> String {
        var top = try object(name)
        edit(&top)
        return String(decoding: try JSONSerialization.data(withJSONObject: top, options: [.sortedKeys]), as: UTF8.self)
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func response(_ text: String) throws -> MahjongActionResponse {
        try decoder().decode(MahjongActionResponse.self, from: Data(text.utf8))
    }

    static func state(_ name: String) throws -> MahjongStatePayload {
        try #require(try response(text(name)).state, "\(name): state 없음")
    }

    static func state(text: String) throws -> MahjongStatePayload {
        try #require(try response(text).state, "state 없음")
    }
}

/// `top["state"][key…]` 를 고친다.
func mjEditState(_ top: inout [String: Any], _ edit: (inout [String: Any]) -> Void) {
    var state = top["state"] as? [String: Any] ?? [:]
    edit(&state)
    top["state"] = state
}

func mjEditNested(_ dict: inout [String: Any], _ key: String, _ edit: (inout [String: Any]) -> Void) {
    var inner = dict[key] as? [String: Any] ?? [:]
    edit(&inner)
    dict[key] = inner
}

// MARK: - 스텁 장면(C2)

@MainActor
@Suite("아잉 마작 스토어 — 스텁 서버 장면 · 늦은 응답 가드 · 리버시 적대 검증 여섯 장면", .serialized)
struct V03xxMahjongStoreSceneTests {
    @Test("장면 — 로비 → 방 → 넷 → 시작 → 버림 → 울기 프롬프트 → 패스 → window_closed(조용히) → 국 끝 → 다음 국 → 판 끝 → 로비",
          .gomokuDefaultsCleanup)
    func fullMatchScene() async throws {
        // 없으면: 요청 본문 키·결정 낡음 눈금·장부 적기·판 끝 콜백 중 하나가 어긋나도 표면 시험은 초록이다(스텁 왕복이 없다).
        let server = MJServer()
        server.set("mahjong_lobby", try MJFixture.text("mahjong_lobby__ok"))
        let a = mjDevice("scene", server: server)
        let s = a.store
        await mjRing(s)
        #expect(s.phase == .lobby && s.availability == .available && s.rubyBalance == 100)

        server.set("mahjong_create", try MJFixture.text("mahjong_create__ok"))
        s.selectedStake = .five
        await s.createRoom()
        let create = try #require(a.calls("create").first?.json)
        #expect(create["p_stake"] as? Int == 5 && create["p_format"] as? String == "tonpuu")
        #expect(create["p_public"] as? Bool == false && create["p_protocol"] as? Int == MahjongWire.protocolVersion)
        #expect(s.phase == .room && s.ownsMatch(mjRoom) && s.isHost && !s.canStart)

        server.set("mahjong_state", try MJFixture.text("mahjong_state__room_three"))
        await mjRing(s)
        #expect(!s.canStart && s.notice == nil)
        server.set("mahjong_state", try MJFixture.text("mahjong_state__room_four"))
        await mjRing(s)
        #expect(s.canStart && s.notice == MahjongNoticeText.fourGathered)

        server.set("mahjong_start", try MJFixture.text("mahjong_start__ok"))
        await s.start()
        #expect(s.phase == .playing && s.rubyBalance == 95 && a.tally.presents == 1)
        guard case .turn(let turn)? = s.myDecision else { Issue.record("내 차례가 아니다"); return }
        #expect(turn.discard.contains(mjTile(129)))

        server.set("mahjong_act", try MJFixture.text("mahjong_act__ok"))
        await s.discard(mjTile(129))
        let act = try #require(a.calls("act").first?.json)
        #expect(act["p_action"] as? String == "discard" && act["p_tiles"] as? [Int] == [129])
        #expect(act["p_expected_seq"] as? Int == 2 && act["p_match_id"] as? String == mjRoom)
        #expect(s.myDecision == nil && !s.isWorking)
        #expect(s.match?.seats?[0].discards?.map(\.tile.id) == [129], "버린 패는 응답 뒤에야 강으로(①)")

        server.set("mahjong_state", try MJFixture.text("mahjong_state__call_prompt"))
        await mjRing(s)
        guard case .call(let call)? = s.myDecision else { Issue.record("울기 프롬프트가 없다"); return }
        #expect(call.windowId == 3 && call.pon == [[mjTile(109), mjTile(110)]])

        server.set("mahjong_call", try MJFixture.text("mahjong_call__window_closed"))
        await s.passCall()
        let answer = try #require(a.calls("call").first?.json)
        #expect(answer["p_action"] as? String == "pass" && answer["p_window_id"] as? Int == 3)
        #expect(s.myDecision == nil && s.notice == nil, "window_closed 는 문구 없이 프롬프트만 내린다(가드 (e))")
        #expect(!s.isAnsweringCall)

        server.set("mahjong_state", try MJFixture.text("mahjong_state__hand_end"))
        await mjRing(s)
        #expect(s.match?.lastHand?.kind == "win" && s.match?.match?.phase == "hand_end" && s.phase == .playing)
        server.set("mahjong_state", try MJFixture.text("mahjong_state__next_hand"))
        await mjRing(s)
        #expect(s.match?.match?.handIndex == 1)

        let lobbiesBefore = a.count("lobby")
        server.set("mahjong_state", try MJFixture.text("mahjong_state__finished"))
        await mjRing(s)
        #expect(s.phase == .finished && a.tally.finished == 1 && !s.ownsMatch(mjRoom))
        await mjWait { a.count("lobby") > lobbiesBefore }
        #expect(a.count("lobby") > lobbiesBefore, "정산을 처음 본 순간 로비 다시 읽기(⑯)")
        await mjRing(s)
        #expect(a.tally.finished == 1, "판 끝 콜백은 한 번")
    }

    @Test("요청 표 (c)(d) — 같은 seq·같은 국은 더 늦게 보낸 요청이 이긴다 · 다른 판의 옛 표는 버린다")
    func requestTicketOrdersSameSeqAndOtherMatch() throws {
        // 없으면: seq 가 안 오르는 방(forming)에서 먼저 보낸 조회가 늦게 와 막 바뀐 방을 되돌린다.
        let s = MahjongStore()
        let four = try MJFixture.state("mahjong_state__room_four")
        let three = try MJFixture.state("mahjong_state__room_three")
        #expect(s.applyState(four, requestedSince: 0, ticket: 5, predatesWrite: false) == .applied)
        #expect(s.applyState(three, requestedSince: 0, ticket: 3, predatesWrite: false) == .ignored)
        #expect(MahjongStore.joinedCount(s.match) == 4)
        // 기준선: 더 늦게 보낸 요청(표 7)은 같은 seq 라도 들어간다.
        #expect(s.applyState(three, requestedSince: 0, ticket: 7, predatesWrite: false) == .applied)
        #expect(MahjongStore.joinedCount(s.match) == 3)
        // (d) 다른 판의 옛 표.
        var other = four
        other.match?.id = "7e7e0000-0000-4000-8000-0000000000bb"
        #expect(s.applyState(other, requestedSince: 0, ticket: 6, predatesWrite: false) == .ignored)
        #expect(s.applyState(other, requestedSince: 0, ticket: 8, predatesWrite: false) == .applied)
    }

    @Test("(h) 울기 답 단조 — 답한 창의 answered:null 조회가 늦게 와도 프롬프트가 안 되살아난다(CC-26)")
    func answeredWindowStaysAnswered() async throws {
        // 없으면: 울기 답은 seq 를 안 올려, 망 재정렬로 먼저 처리된 조회가 이미 답한 프롬프트를 되살린다.
        let server = MJServer()
        server.set("mahjong_call", try MJFixture.text("mahjong_state__call_prompt").replacingOccurrences(
            of: #""answered": null"#, with: #""answered": "pass""#))
        let a = mjDevice("mono", server: server)
        let prompt = try MJFixture.state("mahjong_state__call_prompt")
        a.store.applyState(prompt)
        await a.store.passCall()
        guard case .call(let answered)? = a.store.myDecision else { Issue.record("창이 없다"); return }
        #expect(answered.answered == "pass")
        // 늦게 온 answered:null — 같은 seq 라 표가 막지 않도록 새 표로 넣는다.
        a.store.applyState(prompt)
        guard case .call(let late)? = a.store.myDecision else { Issue.record("창이 없다"); return }
        #expect(late.answered == "pass", "답한 창은 되살아나지 않는다")
        // 기준선: 답하지 않은 기기는 같은 원문에서 answered == nil.
        let b = MahjongStore()
        b.applyState(prompt)
        guard case .call(let fresh)? = b.myDecision else { Issue.record("창이 없다"); return }
        #expect(fresh.answered == nil)
    }

    @Test("V2-01 가림 알림 — 보임 + 가림 + 폴링 없음 → 내 차례 말풍선 · 같은 국 둘째 0 · 다음 국 1 · 기준선 보임이면 0",
          .gomokuDefaultsCleanup)
    func occludedWindowStillGetsMyTurn() throws {
        // 없으면: 가려진 창(전체 화면 앱)을 보이는 것으로 쳐 내 차례 말풍선이 죽는다(CC-01 · 리버시 V2-01).
        let server = MJServer()
        let a = mjDevice("v201", server: server)
        a.store.noteOwnsMatch(mjRoom)
        a.store.windowDidShow()
        a.store.applyState(try MJFixture.state("mahjong_state__their_turn"))
        #expect(a.tally.attentions.isEmpty && a.tally.presents == 1, "전제: 보이는 창 — 판 시작은 창만 띄운다")
        a.store.windowOcclusionDidChange(visible: false)
        #expect(a.store.pollTask == nil && !a.store.isWindowShowingTable)
        a.store.applyState(try MJFixture.state("mahjong_state__my_turn_hand2"))
        #expect(a.tally.attentions.map(\.kind) == [.myTurn])
        let second = try MJFixture.state(text: MJFixture.mutated("mahjong_state__my_turn_hand2") { top in
            mjEditState(&top) { st in
                mjEditNested(&st, "match") { $0["seq"] = 18 }
                mjEditNested(&st, "my_decision") { $0["decision_seq"] = 18; $0["seq"] = 18 }
            }
        })
        a.store.applyState(second)
        #expect(a.tally.kinds(.myTurn) == 1, "같은 국 둘째 차례는 새로 띄우지 않는다")
        let nextHand = try MJFixture.state(text: MJFixture.mutated("mahjong_state__my_turn_hand2") { top in
            mjEditState(&top) { st in
                mjEditNested(&st, "match") { $0["seq"] = 30; $0["hand_index"] = 2 }
                mjEditNested(&st, "my_decision") { $0["decision_seq"] = 30; $0["seq"] = 30 }
                st["events"] = [Any]()
            }
        })
        a.store.applyState(nextHand)
        #expect(a.tally.kinds(.myTurn) == 2, "다음 국 첫 차례는 다시 1")
        // 기준선: 보이고 안 가린 창.
        let b = mjDevice("v201b", server: server)
        b.store.noteOwnsMatch(mjRoom)
        b.store.windowDidShow()
        b.store.applyState(try MJFixture.state("mahjong_state__their_turn"))
        b.store.applyState(try MJFixture.state("mahjong_state__my_turn_hand2"))
        #expect(b.tally.attentions.isEmpty)
        b.store.windowDidHide()
    }

    @Test("V2-02 초인종 합치기 — 조회 중 신호 셋 → 조회 정확히 2 · 적용 seq = 스텁 마지막(CC-17)", .gomokuDefaultsCleanup)
    func signalsCoalesceIntoOneTrailingFetch() async throws {
        // 없으면: 합치지 않으면 4번, 뒤따르는 조회를 버리면 1번 — 도는 동안 생긴 사건을 다음 계기까지 모른다.
        let server = MJServer()
        server.enqueue("mahjong_state", try MJFixture.text("mahjong_state__their_turn"), delay: 0.045)
        server.set("mahjong_state", try MJFixture.text("mahjong_state__call_prompt"))
        let a = mjDevice("v202", server: server)
        a.store.applyState(try MJFixture.state("mahjong_start__ok"))
        a.store.handleSignal()
        await mjWait { a.count("state") == 1 }
        a.store.handleSignal()
        a.store.handleSignal()
        a.store.handleSignal()
        await mjWait { a.store.syncTask == nil && a.store.stateInFlightID == nil && a.count("state") >= 2 }
        try await Task.sleep(for: .milliseconds(30))
        #expect(a.count("state") == 2)
        #expect(a.store.match?.match?.seq == 5)
        #expect(a.calls("state").last?.json["p_since_seq"] as? Int == 4, "뒤따르는 조회는 내 seq 이후만")
    }

    @Test("V2-03 폴링 취소 — 창을 닫는 순간에도 날던 조회와 그에 합쳐진 초인종 조회는 끝까지 간다", .gomokuDefaultsCleanup)
    func hidingTheWindowDoesNotKillTheCoalescedFetch() async throws {
        // 없으면: stopPolling 의 취소가 폴링 조회에 닿아 합쳐진 초인종 조회까지 죽는다 — 창도 폴링도 없는 사람이 사건을 모른다.
        let server = MJServer()
        server.enqueue("mahjong_state", try MJFixture.text("mahjong_state__their_turn"), delay: 0.045)
        server.set("mahjong_state", try MJFixture.text("mahjong_state__call_prompt"))
        let a = mjDevice("v203", server: server)
        a.store.applyState(try MJFixture.state("mahjong_start__ok"))
        a.store.pollStepSeconds = 0.01
        a.store.windowDidShow()
        await mjWait { a.count("state") == 1 }
        a.store.handleSignal()
        await mjWait { a.store.syncTask == nil }
        a.store.windowDidHide()
        await mjWait { a.store.match?.match?.seq == 5 }
        #expect(a.store.match?.match?.seq == 5, "합쳐진 초인종 조회가 살아남았다")
        #expect(a.store.pollTask == nil)
    }

    @Test("VR-04 남은 걸음 — 걸음 중 창이 내려가면 다음 조회(순위)를 안 낸다 · 기준선: 그대로면 낸다", .gomokuDefaultsCleanup)
    func remainingStepsStopWhenHidden() async throws {
        // 없으면: 날던 조회가 끝난 뒤 남은 걸음이 창 없이 순위·로비를 계속 부른다.
        let server = MJServer()
        server.set("mahjong_lobby", try MJFixture.text("mahjong_lobby__ok"), delay: 0.045)
        server.set("mahjong_ranking", try MJFixture.text("mahjong_ranking__ok"))
        let a = mjDevice("vr04", server: server)
        a.store.rankingEnabled = true
        a.store.windowDidShow()
        let now = a.clock.now
        let step = Task { await a.store.pollTick(at: now) }
        await mjWait { a.count("lobby") == 1 }
        a.store.windowDidHide()
        await step.value
        #expect(a.count("ranking") == 0)
        // 기준선(지연 없는 서버).
        server.set("mahjong_lobby", try MJFixture.text("mahjong_lobby__ok"))
        let b = mjDevice("vr04b", server: server)
        b.store.rankingEnabled = true
        b.store.windowDidShow()
        await b.store.pollTick(at: b.clock.now)
        #expect(b.count("ranking") == 1 && b.store.ranking?.me?.rank == nil, "10판 미만은 rank null 그대로")
        b.store.windowDidHide()
    }

    @Test("V2-04 늦은 방 응답 — 판으로 든 id 에 늦게 온 forming 응답은 버린다", .gomokuDefaultsCleanup)
    func lateRoomResponseAfterStartIsDropped() async throws {
        // 없으면: [시작] 직전에 나간 방 조회가 늦게 와 판 화면이 방 화면으로 돌아간다.
        let server = MJServer()
        server.enqueue("mahjong_state", try MJFixture.text("mahjong_state__room_four"), delay: 0.045)
        server.set("mahjong_start", try MJFixture.text("mahjong_start__ok"))
        let a = mjDevice("v204", server: server)
        a.store.applyState(try MJFixture.state("mahjong_state__room_four"))
        a.store.handleSignal()
        await mjWait { a.count("state") == 1 }
        await a.store.start()
        #expect(a.store.phase == .playing)
        await mjWait { a.store.syncTask == nil && a.store.stateInFlightID == nil }
        #expect(a.store.phase == .playing && a.store.match?.match?.matchStatus == .active)
    }

    @Test("V2-06/VR-01 쓰기보다 먼저 나간 로비·state 는 잔액을 덮지 않는다 · 기준선: 쓰기 뒤에 나간 로비는 덮는다",
          .gomokuDefaultsCleanup)
    func responsesThatPredateAWriteKeepTheBalance() async throws {
        // 없으면: 쓰기 직전에 나간 로비·state 가 쓰기 전 잔액(100)을 늦게 그려 루비가 되돌아간 것처럼 보인다.
        let server = MJServer()
        server.set("mahjong_lobby", try MJFixture.text("mahjong_lobby__ok"))
        server.set("mahjong_act", try MJFixture.text("mahjong_start__ok"))
        let a = mjDevice("v206", server: server)
        a.store.applyState(try MJFixture.state("mahjong_start__ok"))
        await mjWait { a.count("lobby") == 1 && !a.store.lobbyInFlight }
        #expect(a.store.rubyBalance == 100, "전제: 판이 선 뒤 로비가 잔액을 그렸다")
        // 로비(잔액 100)가 나는 동안 버림(쓰기 — 응답 잔액 95).
        server.enqueue("mahjong_lobby", try MJFixture.text("mahjong_lobby__ok"), delay: 0.045)
        let lobby = Task { await a.store.refreshLobby() }
        await mjWait { a.count("lobby") == 2 }
        await a.store.discard(mjTile(129))
        #expect(a.store.rubyBalance == 95)
        await lobby.value
        #expect(a.store.rubyBalance == 95 && a.host.rubyBalance == 95, "먼저 나간 로비는 잔액을 덮지 않는다")
        // state 도 같다 — 쓰기 전에 나간 더 새 seq 의 state(잔액 100)는 판은 넣되 잔액은 안 덮는다.
        server.enqueue("mahjong_state", try MJFixture.mutated("mahjong_state__their_turn") { top in
            mjEditState(&top) { $0["ruby_balance"] = 100 }
        }, delay: 0.03)
        let poll = Task { await a.store.refreshMatch(id: mjRoom) }
        await mjWait { a.count("state") == 1 }
        await a.store.discard(mjTile(129))
        await poll.value
        #expect(a.store.match?.match?.seq == 4 && a.store.rubyBalance == 95)
        // 기준선: 쓰기 뒤에 나간 로비는 덮는다.
        await a.store.refreshLobby()
        #expect(a.store.rubyBalance == 100)
    }

    @Test("나갔던 방에 다시 참가 — 접은 기록이 새 참가 응답을 막지 않는다 · 나간 방의 늦은 응답은 버린다", .gomokuDefaultsCleanup)
    func rejoiningALeftRoomShowsIt() async throws {
        // 없으면: 방에서 나간 뒤 같은 공개 방에 다시 들어가도 참가 응답이 버려져 방 화면이 안 선다.
        let server = MJServer()
        server.set("mahjong_leave", try MJFixture.text("mahjong_leave__ok_room"))
        server.set("mahjong_join", try MJFixture.text("mahjong_join__ok"))
        let b = mjDevice("rejoin", me: mjB, server: server)
        b.store.applyState(try MJFixture.state("mahjong_state__room_four_b"))
        await b.store.leaveRoom()
        #expect(b.store.phase == .lobby && b.store.match == nil)
        #expect(b.store.applyState(try MJFixture.state("mahjong_state__room_four_b")) == .ignored, "나간 방의 늦은 응답")
        await b.store.join(roomID: UUID(uuidString: mjRoom)!)
        #expect(b.store.phase == .room && b.store.ownsMatch(mjRoom))
    }
}

// MARK: - 결정 · 보조 · 깨우기 · 방 확인(C2)

@MainActor
@Suite("아잉 마작 스토어 — 2단 입력 접기 · 요청 마감 · 자리 비움 · 닫기 안내 · 보조 · 깨우기 · 방 확인 · 가용성", .serialized)
struct V03xxMahjongStoreDecisionTests {
    private static func startWith(riichi: [Int], notBefore: Double? = nil) throws -> MahjongStatePayload {
        try MJFixture.state(text: MJFixture.mutated("mahjong_start__ok") { top in
            mjEditState(&top) { st in
                mjEditNested(&st, "my_decision") { d in
                    d["riichi"] = riichi
                    if let notBefore { d["not_before_ms"] = notBefore }
                }
            }
        })
    }

    @Test("2단 입력 접기(CC-03) — 무장 → 자동 쯔모기리 사건 → 다음 차례: 무장 풀림, 패를 누르면 discard · 치 줄은 창이 바뀌면 접힘",
          .gomokuDefaultsCleanup)
    func twoStageInputsFoldOnDecisionChange() async throws {
        // 없으면: 무장한 채 시간 초과되면 다음 차례 클릭이 원치 않은 리치(−1000·손 잠김)가 되고, 남의 론으로 닫힌 창의 치 줄이 남는다.
        let server = MJServer()
        server.set("mahjong_act", try MJFixture.text("mahjong_act__ok"))
        let a = mjDevice("fold", server: server)
        a.store.applyState(try Self.startWith(riichi: [129]))
        a.store.armRiichi()
        #expect(a.store.riichiArmed)
        let autoDiscard = try MJFixture.mutated("mahjong_state__their_turn") { top in
            mjEditState(&top) { st in
                var events = st["events"] as? [[String: Any]] ?? []
                events[2]["priv"] = ["auto": true]
                st["events"] = events
            }
        }
        a.store.applyState(try MJFixture.state(text: autoDiscard))
        #expect(!a.store.riichiArmed)
        #expect(a.store.notice == MahjongNoticeText.timeoutDiscarded, "내 자동 버림 표지 → 시간 초과 문구")
        let next = try MJFixture.state(text: MJFixture.mutated("mahjong_state__my_turn_hand2") { top in
            mjEditState(&top) { st in mjEditNested(&st, "my_decision") { $0["riichi"] = [129] } }
        })
        a.store.applyState(next)
        #expect(!a.store.riichiArmed)
        await a.store.discard(mjTile(129))
        #expect(a.calls("act").last?.json["p_action"] as? String == "discard")
        // 치 줄: 상가(3) 버림에 조합 둘 → 펼침 → 다음 창(4)이 오면 접힘.
        let chiPrompt = try MJFixture.mutated("mahjong_state__call_prompt") { top in
            mjEditState(&top) { st in
                mjEditNested(&st, "match") { $0["seq"] = 40; $0["hand_index"] = 3 }
                st["events"] = [Any]()
                mjEditNested(&st, "my_decision") { d in
                    d["from_seat"] = 3; d["tile"] = 8; d["pon"] = [Any](); d["chi"] = [[1, 5], [5, 13]]
                }
            }
        }
        let b = mjDevice("fold-b", server: server)
        b.store.applyState(try MJFixture.state(text: chiPrompt))
        await b.store.call(.chi, tiles: [])
        #expect(b.store.chiChoicesOpen && b.count("call") == 0, "조합이 둘이면 보내지 않고 펼친다")
        let nextWindow = try MJFixture.state(text: MJFixture.mutated("mahjong_state__call_prompt") { top in
            mjEditState(&top) { st in
                mjEditNested(&st, "match") { $0["seq"] = 41; $0["hand_index"] = 3 }
                st["events"] = [Any]()
                mjEditNested(&st, "my_decision") { $0["window_id"] = 4 }
            }
        })
        b.store.applyState(nextWindow)
        #expect(!b.store.chiChoicesOpen)
    }

    @Test("어긋난 기준선 — my_decision.riichi 를 진부분집합으로 주면 무장 뒤 고를 수 있는 패도 그 집합뿐", .gomokuDefaultsCleanup)
    func armedRiichiUsesServerSubsetOnly() async throws {
        // 없으면: 로컬 판정(텐파이 유지 버림 전부)을 몰래 써서 서버가 안 준 리치 선언패를 보낸다(MCL:468 ③).
        let server = MJServer()
        server.set("mahjong_act", try MJFixture.text("mahjong_act__ok"))
        let a = mjDevice("subset", server: server)
        a.store.applyState(try Self.startWith(riichi: [129]))
        a.store.armRiichi()
        await a.store.discard(mjTile(1))
        #expect(a.count("act") == 0, "버림 선택지에는 있지만 리치 선택지에는 없는 패")
        await a.store.discard(mjTile(129))
        let body = try #require(a.calls("act").first?.json)
        #expect(body["p_action"] as? String == "riichi" && body["p_tiles"] as? [Int] == [129])
    }

    @Test("요청 마감(CC-06) — 응답 없는 버림 중 새 결정 state → 단추가 풀리고 새 요청이 나간다 · 같은 결정 키면 잠금 유지",
          .gomokuDefaultsCleanup)
    func requestDeadlineAndNewDecisionUnlock() async throws {
        // 없으면: 응답이 안 오는 요청 하나가 공용 세션 15초 동안 단추를 잠가 5초 결정이 저절로 넘어간다.
        let server = MJServer()
        server.enqueue("mahjong_act", try MJFixture.text("mahjong_act__ok"), delay: 30)
        server.set("mahjong_act", try MJFixture.text("mahjong_act__ok"))
        let a = mjDevice("deadline", server: server)
        a.store.requestDeadlineFloor = 0.04
        a.store.requestDeadlineCeiling = 0.04
        a.store.applyState(try MJFixture.state("mahjong_start__ok"))
        let hung = Task { await a.store.discard(mjTile(129)) }
        await mjWait { a.count("act") == 1 }
        #expect(a.store.isWorking)
        a.store.applyState(try MJFixture.state("mahjong_start__ok"))
        #expect(a.store.isWorking, "기준선: 같은 결정 키 state 는 잠금을 안 푼다")
        a.store.applyState(try MJFixture.state("mahjong_state__my_turn_hand2"))
        #expect(!a.store.isWorking, "더 새 결정 키의 state 가 오면 즉시 풀린다")
        await a.store.discard(mjTile(129))
        #expect(a.count("act") == 2)
        await hung.value
        #expect(!a.store.isWorking, "늦게 끝난 옛 요청이 잠금을 되돌리지 않는다")
        // 마감 자체: 응답 없는 요청은 마감(0.3초)에 풀린다.
        server.enqueue("mahjong_act", try MJFixture.text("mahjong_act__ok"), delay: 30)
        let b = mjDevice("deadline-b", server: server)
        b.store.requestDeadlineFloor = 0.03
        b.store.requestDeadlineCeiling = 0.03
        b.store.applyState(try MJFixture.state("mahjong_start__ok"))
        let started = Date()
        await b.store.discard(mjTile(129))
        #expect(Date().timeIntervalSince(started) < 1 && !b.store.isWorking && b.store.myDecision != nil)
    }

    @Test("요청 마감 값 — min(8, max(2, 내 deadline − 지금 + grace))")
    func requestDeadlineFormula() throws {
        // 없으면: 마감이 공용 세션 한도(15초)로 남아 결정보다 오래 단추를 잠근다.
        let clock = MJClock()
        let s = MahjongStore(clock: { clock.now })
        s.applyState(try MJFixture.state("mahjong_start__ok"))   // server_now = T0, 유예 1000
        #expect(abs(s.requestDeadlineSeconds(deadlineMs: mjT0Ms + 5_000) - 6) < 0.001)
        #expect(s.requestDeadlineSeconds(deadlineMs: mjT0Ms + 60_000) == 8)
        #expect(s.requestDeadlineSeconds(deadlineMs: mjT0Ms - 60_000) == 2)
    }

    @Test("자리 비움 짝(CC-10) — 연 기기: hasAwaySeatHere · 말풍선 · 패를 누르면 mahjong_back · 안 연 기기: 셋 다 0",
          .gomokuDefaultsCleanup)
    func awaySeatSurfacesOnlyOnTheOwningDevice() async throws {
        // 없으면: 점·배너·말풍선 중 하나가 빠지거나(짝이 깨짐), 놀던 맥에서도 자리 비움 점이 뜬다.
        let server = MJServer()
        server.set("mahjong_back", try MJFixture.text("mahjong_back__too_fast"))
        let a = mjDevice("away", server: server)
        a.store.noteOwnsMatch(mjRoom)
        a.store.applyState(try MJFixture.state("mahjong_leave__ok_away"))
        #expect(a.store.hasAwaySeatHere && a.tally.kinds(.away) == 1)
        a.store.applyState(try MJFixture.state("mahjong_leave__ok_away"))
        #expect(a.tally.kinds(.away) == 1, "같은 비움은 한 번")
        await a.store.discard(mjTile(1))
        #expect(a.count("back") == 1 && a.count("act") == 0, "손패를 한 번 누르면 복귀(카드 ⑨)")
        #expect(a.store.notice == MahjongNoticeText.backTooFast)
        let b = mjDevice("away-b", server: server)
        b.store.applyState(try MJFixture.state("mahjong_leave__ok_away"))
        #expect(!b.store.hasAwaySeatHere && b.tally.attentions.isEmpty && b.tally.presents == 0)
    }

    @Test("판 중 [나가기] = 자리 비움 — mahjong_leave 를 보내고 장부는 그대로(기권 아님)", .gomokuDefaultsCleanup)
    func leavingTheTableKeepsOwnership() async throws {
        // 없으면: 판 중 나가기가 장부를 지워, 돌아와도 창·말풍선이 다시 안 뜬다.
        let server = MJServer()
        server.set("mahjong_leave", try MJFixture.text("mahjong_leave__ok_away"))
        let a = mjDevice("leave", server: server)
        a.store.noteOwnsMatch(mjRoom)
        a.store.applyState(try MJFixture.state("mahjong_state__their_turn"))
        await a.store.leaveTable()
        #expect(a.count("leave") == 1 && a.store.ownsMatch(mjRoom) && a.store.hasAwaySeatHere)
        #expect(a.store.phase == .playing)
    }

    @Test("닫기 안내(CC-22) — 사람 닫기 1 · 같은 판 두 번째 0 · 프로그램 닫기 0 · 안 연 기기 0", .gomokuDefaultsCleanup)
    func closingTheWindowExplainsOnce() throws {
        // 없으면: 창을 닫으면 판이 끝나는 줄 알고(큐브는 기권) 다시 안 연다 — 차례마다 자동 처리로 흘린다.
        let server = MJServer()
        let a = mjDevice("close", server: server)
        a.store.windowDidClose(byUser: true)
        #expect(a.tally.kinds(.closedWhilePlaying) == 0, "판이 없으면 0")
        a.store.noteOwnsMatch(mjRoom)
        a.store.applyState(try MJFixture.state("mahjong_state__their_turn"))
        a.store.windowDidClose(byUser: false)
        #expect(a.tally.kinds(.closedWhilePlaying) == 0)
        a.store.windowDidClose(byUser: true)
        a.store.windowDidClose(byUser: true)
        #expect(a.tally.kinds(.closedWhilePlaying) == 1)
        let b = mjDevice("close-b", server: server)
        b.store.applyState(try MJFixture.state("mahjong_state__their_turn"))
        b.store.windowDidClose(byUser: true)
        #expect(b.tally.attentions.isEmpty)
    }

    @Test("보조 쯔모기리(CC-19) — 결정 시작 + [0.5, 1.0]초 · 리치 중이면 not_before · 연 판에서만", .gomokuDefaultsCleanup)
    func tsumogiriAidTimingAndOwnership() async throws {
        // 없으면: 즉시 버림이 '선택지 없음(=노텐 등)'을 흘리거나, 놀던 맥이 남의 판을 대신 둔다.
        let server = MJServer()
        server.set("mahjong_act", try MJFixture.text("mahjong_act__ok"))
        let probe = MahjongStore()
        let samples = (0..<200).map { _ in probe.aidJitter() }
        #expect(samples.allSatisfy { (0.5...1.0).contains($0) } && Set(samples).count > 1)
        let a = mjDevice("aid", server: server)
        a.store.aidJitter = { 0.7 }
        a.store.noteOwnsMatch(mjRoom)
        let start = try MJFixture.state("mahjong_start__ok")
        a.store.applyState(start)   // server_now = T0 → 시계 차 0
        guard case .turn(let turn)? = start.myDecision else { Issue.record("차례 없음"); return }
        #expect(a.store.tsumogiriAidDate(turn) == mjDate(ms: mjT0Ms + 700))
        let riichi = try Self.startWith(riichi: [], notBefore: mjT0Ms + 800)
        guard case .turn(let riichiTurn)? = riichi.myDecision else { Issue.record("차례 없음"); return }
        #expect(a.store.tsumogiriAidDate(riichiTurn) == mjDate(ms: mjT0Ms + 800), "리치 중이면 not_before 에 유예 없이")
        // 켜면: 지금 결정에 대해 시작 + 0.7초에 뽑은 패를 버린다(적용 순간 시계 차 0, 그 뒤 시계를 0.67초로).
        a.store.aids.tsumogiri = true
        a.store.applyState(try MJFixture.state("mahjong_start__ok"))   // 같은 state — 보조가 돈다
        a.clock.now = mjDate(ms: mjT0Ms + 670)
        await Task.yield()
        #expect(a.count("act") == 0, "시작 + 0.7초 전에는 보내지 않는다")
        await mjWait { a.count("act") == 1 }
        let body = try #require(a.calls("act").first?.json)
        #expect(body["p_action"] as? String == "discard" && body["p_tiles"] as? [Int] == [129])
        // 안 연 기기.
        let b = mjDevice("aid-b", server: server)
        b.store.aidJitter = { 0.5 }
        b.store.aids.tsumogiri = true
        b.store.applyState(try MJFixture.state("mahjong_start__ok"))
        b.clock.now = mjDate(ms: mjT0Ms + 600)
        try await Task.sleep(for: .milliseconds(40))
        #expect(b.count("act") == 0)
    }

    @Test("보조 — 울지 않음은 론 아닌 프롬프트를 바로 넘김(국이 바뀌면 꺼짐) · 자동 화료는 론을 바로", .gomokuDefaultsCleanup)
    func noCallsAndAutoWin() async throws {
        // 없으면: 보조를 켜도 5초 프롬프트가 매번 떠 판이 늘어지거나, 다음 국까지 '울지 않음'이 남아 원치 않게 못 운다.
        let server = MJServer()
        server.set("mahjong_call", try MJFixture.text("mahjong_call__ok_pass"))
        let a = mjDevice("nocalls", server: server)
        a.store.noteOwnsMatch(mjRoom)
        a.store.applyState(try MJFixture.state("mahjong_state__their_turn"))
        a.store.aids.noCalls = true
        a.store.applyState(try MJFixture.state("mahjong_state__call_prompt"))
        await mjWait { a.count("call") == 1 }
        #expect(a.calls("call").first?.json["p_action"] as? String == "pass")
        a.store.applyState(try MJFixture.state("mahjong_state__next_hand"))
        #expect(!a.store.aids.noCalls, "국이 바뀌면 꺼진다")
        let ron = try MJFixture.mutated("mahjong_state__call_prompt") { top in
            mjEditState(&top) { st in
                mjEditNested(&st, "match") { $0["seq"] = 50; $0["hand_index"] = 5 }
                st["events"] = [Any]()
                mjEditNested(&st, "my_decision") { $0["ron"] = true; $0["window_id"] = 9 }
            }
        }
        a.store.aids.autoWin = true
        a.store.applyState(try MJFixture.state(text: ron))
        await mjWait { a.count("call") == 2 }
        #expect(a.calls("call").last?.json["p_action"] as? String == "ron")
    }

    @Test("깨우기 — 결정 주인 마감+유예+100 · 리치 not_before · 박자 wake_at(새 값으로 다시) · 나머지 backup · 창이 숨어도 · 장부 없는 기기 0 · 재시도 2회",
          .gomokuDefaultsCleanup)
    func wakeTable() async throws {
        // 없으면: 5초 시계를 미는 박자가 없어 판이 매분 백스톱까지 멎거나, 놀던 맥까지 깨어 호출이 세 배가 된다.
        let server = MJServer()
        server.set("mahjong_state", try MJFixture.text("mahjong_start__ok"))
        let a = mjDevice("wake", server: server)
        a.store.noteOwnsMatch(mjRoom)
        a.store.windowDidHide()
        a.store.applyState(try MJFixture.state("mahjong_start__ok"))
        let owner = try #require(a.store.wakeTarget(now: a.clock.now))
        #expect(owner.kind == .decision && owner.at == mjDate(ms: mjT0Ms + 6_100))
        a.store.checkWake(at: mjDate(ms: mjT0Ms + 6_099))
        #expect(a.count("state") == 0)
        a.store.checkWake(at: mjDate(ms: mjT0Ms + 6_100))
        await mjWait { a.count("state") == 1 && a.store.stateInFlightID == nil }
        // 같은 열쇠(응답이 그대로) → 1초 간격 재시도 2번까지.
        a.store.checkWake(at: mjDate(ms: mjT0Ms + 7_000))
        #expect(a.count("state") == 1)
        for (n, at) in [(2, 7_100.0), (3, 8_100.0)] {
            a.store.checkWake(at: mjDate(ms: mjT0Ms + at))
            await mjWait { a.count("state") == n && a.store.stateInFlightID == nil }
        }
        a.store.checkWake(at: mjDate(ms: mjT0Ms + 20_000))
        try await Task.sleep(for: .milliseconds(20))
        #expect(a.count("state") == 3, "재시도 2회 상한")
        // 리치 중: not_before 전이면 그때(유예 없이).
        let r = mjDevice("wake-r", server: server)
        r.store.noteOwnsMatch(mjRoom)
        r.store.applyState(try Self.startWith(riichi: [], notBefore: mjT0Ms + 700))
        #expect(r.store.wakeTarget(now: r.clock.now)?.at == mjDate(ms: mjT0Ms + 700))
        // 박자 자리(C, wake_seat 2) — wake_at, 응답의 새 wake_at 으로 다시.
        let c = mjDevice("wake-c", me: "00000000-0000-0000-0000-0000000000c3", server: server)
        c.store.noteOwnsMatch(mjRoom)
        let beat = try MJFixture.state("mahjong_state__their_turn_c")
        c.store.applyState(beat)
        let beatTarget = try #require(c.store.wakeTarget(now: c.clock.now))
        #expect(beatTarget.kind == .beat && beatTarget.at == c.store.localDate(serverMs: mjT0Ms + 8_100))
        let stepped = try MJFixture.state(text: MJFixture.mutated("mahjong_state__their_turn_c") { top in
            mjEditState(&top) { st in mjEditNested(&st, "match") { $0["wake_at_ms"] = mjT0Ms + 13_100 } }
        })
        c.store.applyState(stepped)
        #expect(c.store.wakeTarget(now: c.clock.now)?.at == c.store.localDate(serverMs: mjT0Ms + 13_100))
        // 나머지(A, 결정 없음·박자 아님) — backup_at.
        let d = mjDevice("wake-d", server: server)
        d.store.noteOwnsMatch(mjRoom)
        d.store.applyState(try MJFixture.state("mahjong_state__their_turn"))
        let backup = try #require(d.store.wakeTarget(now: d.clock.now))
        #expect(backup.kind == .backup && backup.at == d.store.localDate(serverMs: mjT0Ms + 30_100))
        // 장부 없는 기기 — 깨우기 없음.
        let idle = mjDevice("wake-idle", server: server)
        idle.store.applyState(try MJFixture.state("mahjong_start__ok"))
        #expect(idle.store.wakeTarget(now: idle.clock.now) == nil)
        idle.store.checkWake(at: mjDate(ms: mjT0Ms + 60_000))
        try await Task.sleep(for: .milliseconds(20))
        #expect(idle.count("state") == 0)
    }

    @Test("방 확인(CS-03) — joined 방 + 장부: 창이 숨어도 30초마다 state · 장부 없는 기기 0 · 빠짐 문구", .gomokuDefaultsCleanup)
    func roomCheckEveryThirtySeconds() async throws {
        // 없으면: 앱을 켜 둔 사람도 방 단계 접속 증거가 없어 [시작] 때 '안 보인 사람'으로 빠진다(또는 놀던 맥이 대신 증거를 남긴다).
        let server = MJServer()
        server.set("mahjong_join", try MJFixture.text("mahjong_join__ok"))
        server.set("mahjong_state", try MJFixture.text("mahjong_state__room_four_b"))
        let b = mjDevice("room", me: mjB, server: server)
        b.store.windowDidHide()
        await b.store.join(roomID: UUID(uuidString: mjRoom)!)
        #expect(b.store.ownsMatch(mjRoom) && b.store.phase == .room)
        let joinedAt = b.clock.now
        b.store.checkWake(at: joinedAt.addingTimeInterval(29))
        #expect(b.count("state") == 0)
        b.store.checkWake(at: joinedAt.addingTimeInterval(30))
        await mjWait { b.count("state") == 1 }
        #expect(b.count("state") == 1)
        let idle = mjDevice("room-idle", me: mjB, server: server)
        idle.store.applyState(try MJFixture.state("mahjong_state__room_four_b"))
        idle.store.checkWake(at: idle.clock.now.addingTimeInterval(60))
        try await Task.sleep(for: .milliseconds(20))
        #expect(idle.count("state") == 0)
        // 시작 검사에서 빠졌다 — 넷이 모인 방에서 방장 아닌 내가 not_found.
        server.set("mahjong_state", #"{"status":"not_found","server_now_ms":1800000000000}"#)
        await mjRing(b.store)
        #expect(b.store.notice == MahjongNoticeText.droppedAtStart && b.store.phase == .lobby && !b.store.ownsMatch(mjRoom))
    }

    @Test("seats_dropped — 방장: 까닭(reasons)대로 한 줄 · 빠진 사람: 까닭 없는 중립 문구 + 방에서 내림", .gomokuDefaultsCleanup)
    func seatsDroppedNotice() async throws {
        // 없으면: 시작 검사에서 빠진 방장이 방 화면에 남아 [시작]을 계속 누른다.
        let server = MJServer()
        server.set("mahjong_start", try MJFixture.text("mahjong_start__seats_dropped"))
        let a = mjDevice("drop", server: server)
        a.store.applyState(try MJFixture.state("mahjong_state__room_four"))
        await a.store.start()
        #expect(a.store.notice == "자리를 비운 사람이 빠졌어요" && a.store.phase == .room)
        #expect(a.store.notice != MahjongNoticeText.droppedOthers(reasons: ["insufficient"]), "기준선: 까닭이 다르면 다른 줄")
        #expect(MahjongStore.joinedCount(a.store.match) == 3)
        server.set("mahjong_start", try MJFixture.mutated("mahjong_start__seats_dropped") { top in
            top["reasons"] = [mjA: "insufficient"]
        })
        a.store.applyState(try MJFixture.state("mahjong_state__room_four"), requestedSince: 0)
        await a.store.start()
        #expect(a.store.notice == MahjongNoticeText.droppedAtStart && a.store.phase == .lobby)
    }

    @Test("가용성 세 갈래 — 로비 ok · unsupported_client · 함수 없음(PGRST202)", .gomokuDefaultsCleanup)
    func availabilityThreeWays() async throws {
        // 없으면: 서버가 아직 없거나 앱이 옛 버전일 때 '연결 확인'만 되풀이한다.
        let server = MJServer()
        server.enqueue("mahjong_lobby", try MJFixture.text("mahjong_lobby__ok"))
        server.enqueue("mahjong_lobby", #"{"status":"unsupported_client","server_now_ms":1800000000000}"#)
        server.enqueue("mahjong_lobby", #"{"code":"PGRST202","details":"x","hint":null,"message":"Could not find the function public.mahjong_lobby in the schema cache"}"#,
                       status: 404)
        let a = mjDevice("avail", server: server)
        await a.store.refreshLobby()
        #expect(a.store.availability == .available)
        await a.store.refreshLobby()
        #expect(a.store.availability == .updateRequired && a.store.notice == MahjongNoticeText.updateRequired)
        await a.store.refreshLobby()
        #expect(a.store.availability == .serverMissing && a.store.notice == MahjongNoticeText.unavailable)
    }

    @Test("받은 초대 — 모든 기기에 알림(장부 무관) · 같은 초대는 한 번 · 거절은 카드를 바로 걷는다", .gomokuDefaultsCleanup)
    func invitesReachEveryDevice() async throws {
        // 없으면: 장부 규약을 초대에까지 번져 다른 맥에서 받은 초대를 놓친다.
        let server = MJServer()
        server.set("mahjong_lobby", try MJFixture.text("mahjong_lobby__invited"))
        server.set("mahjong_decline", #"{"status":"ok","server_now_ms":1800000000000}"#)
        let b = mjDevice("invite", me: mjB, server: server)
        await mjRing(b.store)
        await mjRing(b.store)
        #expect(b.tally.invites == [UUID(uuidString: mjRoom)!] && b.store.hasIncomingInvite)
        await b.store.decline(roomID: UUID(uuidString: mjRoom)!)
        #expect(b.count("decline") == 1)
    }
}

// MARK: - 실응답 원문을 스토어에(T) — `Fixtures/mahjong-rpc`(S2 하네스 55492, 바이트 그대로). 시청자는 그 응답의 내 자리 주인,
// 벽시계는 그 응답의 server_now_ms. 장면 픽스처(위)와 달리 id·시각·seq 를 고치지 않는다.

@MainActor
@Suite("아잉 마작 스토어 — S2 실응답 원문을 그대로 먹인다(로비·방·시작·차례·울기·비움·국 끝·판 끝)", .serialized)
struct V03xxMahjongStoreRealResponseTests {
    static let host = "0e57a3c9-f9a2-4f0c-b585-d78604e285e5"
    static let room = "46e50796-140c-433d-9de6-6271c3cc8f85"

    func device(_ label: String, me: String, nowMs: Double, server: MJServer) -> MJDevice {
        let d = mjDevice(label, me: me, server: server)
        d.clock.now = mjDate(ms: nowMs)
        return d
    }

    func state(_ name: String) throws -> MahjongStatePayload {
        try #require(try MJFixture.real(name).state, "\(name): state 없음")
    }

    @Test("로비 ok · 초대 — 잔액·가용성·초대 카드가 실응답에서 읽힌다", .gomokuDefaultsCleanup)
    func lobbyFromRealResponses() async throws {
        // 없으면: 로비 원문 칸 하나(초대 방 모양·잔액)가 스토어 경로에서 어긋나도 와이어 디코드 시험만으로는 초록이다.
        let server = MJServer()
        server.set("mahjong_lobby", try MJFixture.realText("mahjong_lobby__ok"))
        let a = device("real-lobby", me: Self.host, nowMs: 1_793_699_161_571, server: server)
        await mjRing(a.store)
        #expect(a.store.phase == .lobby && a.store.availability == .available && a.store.rubyBalance == 100)
        #expect(!a.store.hasIncomingInvite, "기준선: 초대 없는 로비")
        let invites = try MJFixture.decoder().decode(
            MahjongLobbyResponse.self, from: Data(MJFixture.realText("mahjong_lobby__invites").utf8))
        a.store.applyLobby(invites)
        #expect(a.store.hasIncomingInvite && a.store.visibleInvites.map { $0.id.uuidString.lowercased() } == [Self.room])
    }

    @Test("방 — 만들기 → 둘(시작 못 함) → 넷(room_full 응답의 state) → seats_dropped(방장: insufficient 한 줄) → 넷 → 시작 ok",
          .gomokuDefaultsCleanup)
    func roomToStartFromRealResponses() async throws {
        // 없으면: 실서버 방 응답(멤버 상태·방장·seats_dropped 의 uuid 사전)이 스토어의 [시작] 게이트·문구와 어긋나도 모른다.
        let server = MJServer()
        server.set("mahjong_create", try MJFixture.realText("mahjong_create__ok"))
        let a = device("real-room", me: Self.host, nowMs: 1_793_699_161_555, server: server)
        await a.store.createRoom()
        #expect(a.store.phase == .room && a.store.isHost && a.store.ownsMatch(Self.room) && !a.store.canStart)
        server.set("mahjong_state", try MJFixture.realText("mahjong_state__room"))
        await mjRing(a.store)
        #expect(MahjongStore.joinedCount(a.store.match) == 2 && !a.store.canStart)
        let full = try state("mahjong_invite__room_full")
        a.store.applyState(full, requestedSince: 0)
        #expect(MahjongStore.joinedCount(a.store.match) == 4 && a.store.canStart)
        server.set("mahjong_start", try MJFixture.realText("mahjong_start__seats_dropped"))
        await a.store.start()
        #expect(a.store.notice == "루비가 모자란 사람이 빠졌어요" && a.store.phase == .room, "방장: 까닭(insufficient)대로")
        #expect(MahjongStore.joinedCount(a.store.match) == 3 && !a.store.canStart)
        a.store.applyState(full, requestedSince: 0)
        server.set("mahjong_start", try MJFixture.realText("mahjong_start__ok"))
        await a.store.start()
        #expect(a.store.phase == .playing && a.store.rubyBalance == 95 && a.tally.presents == 1)
        #expect(a.store.table?.mySeat == 3 && a.store.myDecision == nil, "방장은 자리 3 — 기가(0)가 아니라 결정 없음")
    }

    @Test("내 차례 — 결정(turn)이 실응답에서 · 뽑은 패를 버리면 expected_seq = 그 state 의 seq · stale 은 말없이", .gomokuDefaultsCleanup)
    func myTurnFromRealResponse() async throws {
        // 없으면: 실서버 결정 칸(discard 목록·seq)이 스토어 결정 해석과 갈라져 단추가 안 켜지거나 엉뚱한 seq 로 보낸다.
        let server = MJServer()
        let mine = try state("mahjong_state__turn_mine")
        let a = device("real-turn", me: "03bfb832-9c03-492f-b401-2cfe07a8e771", nowMs: 1_793_699_167_276, server: server)
        a.store.noteOwnsMatch(try #require(mine.match?.id))
        #expect(a.store.applyState(mine) == .applied)
        guard case .turn(let turn)? = a.store.myDecision else { Issue.record("내 차례가 아니다"); return }
        #expect(turn.discard.contains(mjTile(124)) && turn.discard.count == 14)
        server.set("mahjong_act", try MJFixture.realText("mahjong_act__stale"))
        await a.store.discard(mjTile(124))
        let act = try #require(a.calls("act").first?.json)
        #expect(act["p_tiles"] as? [Int] == [124] && act["p_expected_seq"] as? Int == mine.match?.seq)
        #expect(a.store.notice == nil, "stale 은 실린 state 로 답한다(문구 없음)")
        let other = try state("mahjong_state__turn_other")
        let b = device("real-turn-other", me: "5d419d6e-57a2-4629-8a0d-83b81b16843f", nowMs: 1_793_699_167_277, server: server)
        #expect(b.store.applyState(other) == .applied && b.store.myDecision == nil, "기준선: 남의 차례엔 결정 없음")
    }

    @Test("울기 — 선택지 있는 자리: call 결정(퐁·깡) → 패스 → window_closed 는 말없이 내림 · 없는 자리: 결정 없음", .gomokuDefaultsCleanup)
    func callPromptFromRealResponses() async throws {
        // 없으면: 실서버 울기 결정(창 번호·퐁 조합)과 window_closed 를 스토어가 다르게 읽어 프롬프트가 남거나 문구가 뜬다.
        let server = MJServer()
        let prompt = try state("mahjong_state__claim_option")
        let a = device("real-call", me: "42f407fc-1fe2-4872-a9d7-454dabc83b6a", nowMs: 1_793_699_167_293, server: server)
        a.store.noteOwnsMatch(try #require(prompt.match?.id))
        a.store.applyState(prompt)
        guard case .call(let call)? = a.store.myDecision else { Issue.record("울기 프롬프트가 없다"); return }
        #expect(call.windowId == 1 && call.pon == [[mjTile(133), mjTile(134)]] && call.minkan == [[mjTile(133), mjTile(134), mjTile(135)]])
        server.set("mahjong_call", try MJFixture.realText("mahjong_call__ok"))
        await a.store.passCall()
        let answer = try #require(a.calls("call").first?.json)
        #expect(answer["p_action"] as? String == "pass" && answer["p_window_id"] as? Int == 1)
        #expect(a.store.myDecision == nil && a.store.notice == nil)
        // window_closed 원문은 '다른 창 번호로 보낸 답'이라 실린 state 에 창 1 이 answered:null 로 아직 열려 있다 —
        // 스토어는 문구 없이, 이미 답한 창을 프롬프트로 되살리지 않는다(가드 (e)·(h)).
        let w = device("real-call-closed", me: "42f407fc-1fe2-4872-a9d7-454dabc83b6a", nowMs: 1_793_699_167_293, server: server)
        w.store.noteOwnsMatch(try #require(prompt.match?.id))
        w.store.applyState(prompt)
        server.set("mahjong_call", try MJFixture.realText("mahjong_call__window_closed"))
        await w.store.passCall()
        #expect(w.store.notice == nil)
        if case .call(let held)? = w.store.myDecision { #expect(held.windowId == 1 && held.answered == "pass") }
        let none = try state("mahjong_state__claim_no_option")
        let c = device("real-call-none", me: "01a79352-cba1-400b-9c7b-f4bab3494afc", nowMs: 1_793_699_167_293, server: server)
        c.store.applyState(none)
        #expect(c.store.myDecision == nil && c.store.phase == .playing)
    }

    @Test("자리 비움 — 나가기 응답의 my_away → 이 기기 점·배너 후보 · back ok 로 풀림 · 기준선: 장부 없는 기기 0", .gomokuDefaultsCleanup)
    func awayAndBackFromRealResponses() async throws {
        // 없으면: 실서버 my_away 모양(since·back_ready)이 스토어의 자리 비움 짝과 어긋나 점·배너가 안 켜지거나 안 꺼진다.
        let server = MJServer()
        let me = "021334d5-fb69-4a53-9185-8b68d9d6f9d6"
        let away = try state("mahjong_leave__active")
        let a = device("real-away", me: me, nowMs: 1_793_699_162_617, server: server)
        a.store.noteOwnsMatch(try #require(away.match?.id))
        a.store.applyState(away)
        #expect(a.store.hasAwaySeatHere)
        let idle = device("real-away-idle", me: me, nowMs: 1_793_699_162_617, server: server)
        idle.store.applyState(away)
        #expect(!idle.store.hasAwaySeatHere, "기준선: 이 기기가 연 판이 아니면 0")
        server.set("mahjong_back", try MJFixture.realText("mahjong_back__ok"))
        a.clock.now = mjDate(ms: 1_793_699_172_700)
        await a.store.comeBack()
        #expect(a.calls("back").count == 1 && !a.store.hasAwaySeatHere)
    }

    @Test("국 끝·판 끝 — 론 둘·셋·천화(역 id heavenly 를 아는 이름으로) · finished 는 판 끝 한 번", .gomokuDefaultsCleanup)
    func handAndMatchEndFromRealResponses() async throws {
        // 없으면: 실서버 국 결과(wins 여럿·역 id)를 스토어·문구가 '새 역'으로 접거나 판 끝 콜백이 안 운다.
        let server = MJServer()
        for (name, me, wins) in [("mahjong_state__hand_end_double_ron", "844cbe40-0ee9-44d4-8bd1-b77eaff1b8dc", 2),
                                 ("mahjong_state__hand_end_triple_ron", "b6464e10-3e97-46b5-9fa0-d89c606b9e4a", 3),
                                 ("mahjong_state__hand_end_heavenly", "15d6b80c-ff9e-402e-87dc-c48aecc28be5", 1)] {
            let payload = try state(name)
            let d = device("real-\(wins)", me: me, nowMs: payload.serverNowMs ?? 0, server: server)
            #expect(d.store.applyState(payload) == .applied, "\(name)")
            #expect(d.store.phase == .playing && d.store.match?.lastHand?.kind == "win", "\(name)")
            #expect(d.store.match?.lastHand?.wins?.count == wins, "\(name)")
            for win in d.store.match?.lastHand?.wins ?? [] {
                for yaku in win.yaku ?? [] {
                    #expect(MahjongNoticeText.yakuName(yaku.id) != MahjongNoticeText.newYaku, "\(name): \(yaku.id)")
                }
            }
        }
        let finished = try state("mahjong_state__finished")
        let f = device("real-finished", me: "03364ce8-1ea1-4e35-b88d-bc7b138b8fd7", nowMs: finished.serverNowMs ?? 0, server: server)
        f.store.noteOwnsMatch(try #require(finished.match?.id))
        f.store.applyState(finished)
        #expect(f.store.phase == .finished && f.tally.finished == 1)
        f.store.applyState(finished, requestedSince: 0)
        #expect(f.tally.finished == 1, "판 끝 콜백은 한 번")
    }
}
