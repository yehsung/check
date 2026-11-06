import Foundation
import Observation
import Testing
@testable import CheckCore

// 1:1 길건너 스토어(`CrossyDuelStore`) 계약 — SPEC v1.3 §8.3 · §3.1 · §10.2 C 줄. **모양이 아니라 결과를 잰다.**
//
// 서버는 스텁이다(`GomokuStubProtocol` — 호스트별 스크립트). 판 보고·상태는 작은 흉내 서버(`CDServer`)가 받는다:
// seq 이하면 stale · 첫 보고 = 준비 · 둘째 준비면 start_at = 지금 + 3초 · 점수는 누계로 저장. 상대 쪽 값과 정산은 시험이 직접 고친다.
// 실서버 왕복(정규화 · 시간 경과 · 잠금)은 하네스(S) · 두 기기 프로브 몫이다(메모리 stub-tests-hide-roundtrip-bugs) —
// 서버 응답 **모양**은 S 픽스처 원문(T/Fixtures/crossy-duel-rpc)을 직접 옮겨 따로 잰다(아래 '픽스처' 시험).
// 시계는 둘 다 주입이다(벽시계 `clock` · 단조 `uptime`). 판 루프 · 폴링 루프는 3,600초로 재우고 `tick` · `pollTick` 을 직접 밟는다.
// 각 시험의 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가"이고, 단언마다 결함 변이에서 갈리는 기준선 짝을 둔다.

// MARK: - 시험대(프레임 시험도 같이 쓴다)

struct CDError: Error {}

private func cdOpt(_ value: Any?) -> Any { value ?? NSNull() }

func cdJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

func cdDecode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: Data(text.utf8))
}

/// 주입 시계 둘(벽 · 단조). `advance` 는 둘을 같이 민다(서버 시각도 벽시계를 따른다).
final class CDClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _wall = Date(timeIntervalSince1970: 1_800_000_000)
    private var _uptime: TimeInterval = 1_000
    /// 기기 시계 어긋남(초) — 스토어가 보는 벽시계에만 더한다(서버 시각은 참값).
    var skew: TimeInterval = 0

    var wall: Date {
        get { lock.lock(); defer { lock.unlock() }; return _wall }
        set { lock.lock(); _wall = newValue; lock.unlock() }
    }

    var uptime: TimeInterval {
        get { lock.lock(); defer { lock.unlock() }; return _uptime }
        set { lock.lock(); _uptime = newValue; lock.unlock() }
    }

    var deviceWall: Date { wall.addingTimeInterval(skew) }
    var nowMs: Double { wall.timeIntervalSince1970 * 1000 }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        _wall = _wall.addingTimeInterval(seconds)
        _uptime += seconds
        lock.unlock()
    }
}

@MainActor
final class CDHost: GomokuStoreHost {
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
        guard let session else { throw CDError() }
        return try await operation(session)
    }

    /// 나르던 작업 취소(URLSession 취소 · CancellationError)는 앱처럼 `.cancelled` 로 접는다.
    func classifyAuthError(_ error: Error) -> AuthErrorDisposition {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return .cancelled }
        return .transient
    }
}

@MainActor
enum CDRetention {
    /// 스토어는 호스트를 약참조로 든다 — 시험이 버리면 요청이 한 건도 안 나간다.
    static var hosts: [CDHost] = []
}

/// rpc 이름별 응답: 줄 세운 응답 → 응답기 → 고정 응답. 없으면 nil(→ `[]` 200 — 디코드 실패).
final class CDScript: @unchecked Sendable {
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

/// 판의 한 사람(흉내 서버 칸).
struct CDSide {
    var id: String
    var name: String
    var ready = false
    var seq = 0
    var score = 0
    var deaths = 0
    var lastSeenMs: Double?

    func json() -> [String: Any] {
        ["id": id, "display_name": name, "avatar_url": NSNull(), "character": "aing", "ready": ready, "seq": seq,
         "score": score, "deaths": deaths, "goal_at_ms": NSNull(), "last_seen_ms": cdOpt(lastSeenMs)]
    }
}

/// `crossy_duel_report` · `crossy_duel_state` 흉내(§6.4 의 순서 일부): seq 이하면 stale · 첫 보고 = 준비 ·
/// 둘째 준비면 start_at = 지금 + 3초 · 점수·죽음은 누계로 저장. 정산은 시험이 `finish` 로 한다.
final class CDServer: @unchecked Sendable {
    enum Frames { case on, off, missing }

    private let lock = NSLock()
    let clock: CDClock
    var matchID = CDRig.matchID
    var status = "active"
    var stake = 5
    var seed: Int? = 4_242
    var goal = 100
    var startAtMs: Double?
    var acceptedAtMs: Double
    var me = CDSide(id: CDRig.me, name: "나")
    var opponent = CDSide(id: CDRig.rival, name: "라이벌", ready: true)
    var result: String?
    var winner: String?
    var endReason: String?
    var finalScores: (me: Int, opponent: Int)?
    var myDevice: String? = "this"
    var frames: Frames = .on
    var reportReplyStatus: String?
    var reports: [[String: Any]] = []

    init(clock: CDClock) {
        self.clock = clock
        acceptedAtMs = clock.nowMs
    }

    func edit(_ change: (CDServer) -> Void) {
        lock.lock()
        change(self)
        lock.unlock()
    }

    func finish(winner: String?, reason: String, finalMe: Int, finalOpponent: Int) {
        edit {
            $0.status = "finished"
            $0.winner = winner
            $0.result = winner == nil ? "draw" : (winner == CDRig.me ? "challenger_win" : "opponent_win")
            $0.endReason = reason
            $0.finalScores = (finalMe, finalOpponent)
        }
    }

    /// 지금 판 상태(§6.5 STATE — 키 집합 그대로. `frames == .missing` 이면 1차 서버처럼 frames · checkpoint_ms 가 없다).
    func state() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return stateLocked()
    }

    private func stateLocked() -> [String: Any] {
        let now = clock.nowMs
        let end = startAtMs.map { $0 + 180_000 }
        var state: [String: Any] = [
            "match_id": matchID, "status": status, "stake": stake, "seed": cdOpt(seed), "server_now_ms": now,
            "accepted_at_ms": acceptedAtMs, "ready_deadline_ms": acceptedAtMs + 30_000, "start_at_ms": cdOpt(startAtMs),
            "end_at_ms": cdOpt(end), "grace_end_ms": cdOpt(end.map { $0 + 2_000 }),
            "finished_at_ms": status == "finished" ? now : NSNull(),
            "goal": goal, "max_duration_seconds": 180,
            "report_ms": frames == .missing ? 2000 : 1000, "heartbeat_ms": 3000, "silence_ms": 15_000, "countdown_ms": 3000,
            "me": me.json(), "opponent": opponent.json(),
            "result": cdOpt(result), "winner": cdOpt(winner), "end_reason": cdOpt(endReason),
            "final": finalScores.map { ["me": $0.me, "opponent": $0.opponent] as Any } ?? NSNull(),
            "my_device": cdOpt(myDevice), "ruby_balance": 95,
        ]
        if frames != .missing {
            state["checkpoint_ms"] = 3000
            let on = frames == .on && status == "active" && myDevice != "other"
            state["frames"] = on ? ["on": true, "topic": "crossy_duel:\(matchID)"] as Any : NSNull()
        }
        return state
    }

    func envelope(_ status: String = "ok") -> String {
        cdJSON(["status": status, "state": state()])
    }

    func report(_ body: String) -> GomokuStubProtocol.Reply {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        lock.lock()
        reports.append(json)
        if let forced = reportReplyStatus {
            let text = cdJSON(["status": forced, "state": stateLocked()])
            lock.unlock()
            return GomokuStubProtocol.Reply(body: text)
        }
        let seq = json["p_seq"] as? Int ?? 0
        let score = json["p_score"] as? Int ?? 0
        let deaths = json["p_deaths"] as? Int ?? 0
        let now = clock.nowMs
        var replyStatus = "ok"
        if status != "active" || seq <= me.seq {
            replyStatus = "stale"
        } else if !me.ready {
            me.ready = true
            me.seq = seq
            me.lastSeenMs = now
            if opponent.ready, startAtMs == nil { startAtMs = now + 3_000 }
        } else {
            me.seq = seq
            me.score = max(me.score, score)
            me.deaths = max(me.deaths, deaths)
            me.lastSeenMs = now
        }
        let text = cdJSON(["status": replyStatus, "state": stateLocked()])
        lock.unlock()
        return GomokuStubProtocol.Reply(body: text)
    }
}

/// 프레임 소켓 스텁 — 연결 · 보내기 · 닫기를 적고, 시험이 사건을 직접 넣는다(`deliver`).
@MainActor
final class CDChannel: CrossyDuelFrameChannel {
    var onEvent: ((CrossyDuelFrameChannelEvent) -> Void)?
    private(set) var connects: [(topic: String, token: String)] = []
    private(set) var sent: [[String: Any]] = []
    private(set) var pushes: [String] = []
    private(set) var disconnects = 0

    func connect(url: URL, apiKey: String, accessToken: String, topic: String) {
        connects.append((topic, accessToken))
    }

    func send(event: String, payload: [String: Any]) {
        if event == CrossyDuelFrame.event { sent.append(payload) }
    }

    func pushAccessToken(_ token: String) { pushes.append(token) }

    func disconnect() { disconnects += 1 }

    func deliver(_ event: CrossyDuelFrameChannelEvent) { onEvent?(event) }
}

@MainActor
final class CDTally {
    var presents = 0
    var attentionRequests = 0
    var attentions: [CrossyDuelAttention] = []
    var arrived: [CrossyDuelInvite] = []
    var finished = 0
    var holding: [Bool] = []
}

/// 스토어 한 벌 + 흉내 서버 + 스텁 채널.
@MainActor
struct CDRig {
    nonisolated static let me = "00000000-0000-0000-0000-0000000000a1"
    nonisolated static let rival = "00000000-0000-0000-0000-0000000000b2"
    nonisolated static let matchID = "c0de0000-0000-4000-8000-0000000000cd"

    let store: CrossyDuelStore
    let clock: CDClock
    let host: String
    let server: CDServer
    let script: CDScript
    let channel: CDChannel
    let tally: CDTally

    static func make(_ label: String, frames: CDServer.Frames = .off, userID: String = CDRig.me) -> CDRig {
        let host = "v03xx-cd-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
        let clock = CDClock()
        let server = CDServer(clock: clock)
        server.frames = frames
        let script = CDScript()
        script.stand("crossy_duel_lobby", cdLobby(clock: clock))
        script.respond("crossy_duel_report") { server.report($0) }
        script.respond("crossy_duel_state") { _ in GomokuStubProtocol.Reply(body: server.envelope()) }
        GomokuStubProtocol.register(host: host, handler: script.handler)
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
        let owner = CDHost(service: service, userID: userID)
        CDRetention.hosts.append(owner)
        let store = CrossyDuelStore(host: owner, clock: { clock.deviceWall }, uptime: { clock.uptime })
        store.pollStepSeconds = 3_600
        store.gameLoopStepSeconds = 3_600
        store.frameJitter = { $0 }
        let channel = CDChannel()
        store.makeFrameChannel = { _ in channel }
        let tally = CDTally()
        store.presentWindow = { tally.presents += 1 }
        store.requestAttention = { tally.attentionRequests += 1 }
        store.onAttention = { tally.attentions.append($0) }
        store.onInviteArrived = { tally.arrived.append($0) }
        store.onMatchFinished = { tally.finished += 1 }
        store.onHoldingActivityChange = { tally.holding.append($0) }
        return CDRig(store: store, clock: clock, host: host, server: server, script: script, channel: channel, tally: tally)
    }

    var reportCount: Int { GomokuStubProtocol.count(host: host, rpc: "crossy_duel_report") }
    var reportBodies: [[String: Any]] { GomokuStubProtocol.calls(host: host, rpc: "crossy_duel_report").map(\.json) }
    func count(_ rpc: String) -> Int { GomokuStubProtocol.count(host: host, rpc: rpc) }
    func calls(_ rpc: String) -> [[String: Any]] { GomokuStubProtocol.calls(host: host, rpc: rpc).map(\.json) }

    /// 흉내 서버의 지금 상태를 응답처럼 옮긴다.
    @discardableResult
    func applyServerState() -> CrossyDuelStore.StateApplyOutcome {
        store.applyState(try! cdDecode(CrossyDuelStatePayload.self, cdJSON(server.state())), receivedAt: clock.uptime)
    }

    /// 나가 있는 보고가 다 돌아올 때까지(응답 끝자락이 다음 보고를 낼 수 있어 되풀이한다).
    func settle() async {
        for _ in 0..<200 {
            guard store.reportInFlight, let task = store.reportTask else { return }
            await task.value
        }
    }

    /// 수락된 판을 들고 창을 띄워 준비 → 시작(3.5초 뒤) → 판 중까지.
    func startPlaying() async {
        applyServerState()
        store.lastLobbyRequestAt = clock.deviceWall
        store.windowDidShow()
        await settle()
        clock.advance(3.5)
        store.tick()
        await settle()
        #expect(store.phase == .playing)
    }

    /// 앞으로 한 칸(시작 풀밭 — 죽지 않는다)을 넣고 착지할 때까지 판만 민다(보고는 다음 tick 이 판단).
    func hop() {
        store.forward()
        store.duel?.advance(to: clock.uptime + 0.2)
    }
}

/// 서버 `crossy_duel_lobby` jsonb 모양 그대로(§6.5 LOBBY).
func cdLobby(clock: CDClock, incoming: [[String: Any]] = [], outgoing: [String: Any]? = nil, active: String? = nil,
             users: [[String: Any]]? = nil, light: Bool = false) -> String {
    cdJSON([
        "status": "ok", "server_now_ms": clock.nowMs, "stakes": [3, 5, 10], "goal": 100, "max_duration_seconds": 180,
        "me": ["ruby_balance": 100, "wins": cdOpt(light ? nil : 2), "losses": cdOpt(light ? nil : 1),
               "draws": cdOpt(light ? nil : 0),
               "active_match_id": cdOpt(active), "incoming": incoming, "outgoing": cdOpt(outgoing)] as [String: Any],
        "users": light ? [] as [[String: Any]] : (users ?? [
            ["id": CDRig.rival, "display_name": "라이벌", "avatar_url": NSNull(), "character": "jelly",
             "is_working": true, "in_match": false, "capable": true, "focus_mode": false],
        ]),
    ])
}

func cdInvite(_ id: String = CDRig.matchID, peerKey: String, clock: CDClock, stake: Int = 3,
              expiresIn seconds: Double = 60) -> [String: Any] {
    ["match_id": id, peerKey: ["id": CDRig.rival, "display_name": "라이벌"], "stake": stake,
     "expires_at_ms": clock.nowMs + seconds * 1000]
}

private func cdPGRST202(_ function: String) -> String {
    #"{"code":"PGRST202","details":"Searched for the function public."# + function
        + #" with parameters","hint":null,"message":"Could not find the function public."# + function
        + #" in the schema cache"}"#
}

@MainActor
private func cdWait(_ resumes: Int = 2_000, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<resumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

// MARK: - 픽스처 원문

private let cdFixtureDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/crossy-duel-rpc", isDirectory: true)

private func cdFixture(_ name: String) throws -> String {
    try String(contentsOf: cdFixtureDirectory.appendingPathComponent(name), encoding: .utf8)
}

// MARK: - 시험

@Suite("V03xx 길건너 1:1 — 스토어(CrossyDuelStore)")
@MainActor
struct V03xxCrossyDuelStoreTests {

    @Test("흐름: 로비 → 신청 → (보낸 신청 5초 조회) 수락 → 준비 문(창 보임) → 카운트다운 → 판 → 상대 막대 = 응답 → 정산 → 결과 → 로비")
    func fullFlow() async throws {
        // 없으면: 각 단계가 따로 초록이어도 잇는 자리(신청 → 판 → 결과 → 로비)에서 판이 안 서거나 결과가 안 내려간다.
        let rig = CDRig.make("flow")
        let store = rig.store
        await store.refreshLobby()
        #expect(store.users.map(\.id) == [CDRig.rival])
        #expect(store.record == CrossyDuelRecord(wins: 2, losses: 1, draws: 0))
        #expect(store.hasLoadedLobby)
        rig.script.enqueue("crossy_duel_challenge", cdJSON([
            "status": "ok", "match_id": CDRig.matchID, "expires_at_ms": rig.clock.nowMs + 60_000,
            "server_now_ms": rig.clock.nowMs]))
        await store.challenge(userID: CDRig.rival, stake: .five)
        #expect(store.outgoing?.id == CDRig.matchID)
        #expect(store.notice == CrossyDuelNoticeText.challenge(.ok))
        #expect(rig.calls("crossy_duel_challenge").first?["p_stake"] as? Int == 5)
        // 창이 보인다(가려지지 않음) → 5초 뒤 보낸 신청 조회가 수락된 판을 데려온다.
        store.lastLobbyRequestAt = rig.clock.deviceWall
        store.windowDidShow()
        rig.clock.advance(5)
        await store.pollTick(at: rig.clock.deviceWall)
        #expect(rig.count("crossy_duel_state") == 1)
        #expect(store.outgoing == nil)
        #expect(store.match?.id == CDRig.matchID)
        #expect(store.phase == .ready)
        #expect(rig.tally.attentions.isEmpty)                    // 창이 보였으니 말풍선 없음
        // 준비 = 첫 보고(창 보임) → 서버가 둘째 준비로 시작 시각을 정한다 → 카운트다운.
        store.tick()
        await rig.settle()
        #expect(rig.reportBodies.first?["p_seq"] as? Int == 1)
        #expect(store.phase == .countdown)
        #expect(store.holdsActivity)
        rig.clock.advance(3.5)
        store.tick()
        await rig.settle()
        #expect(store.phase == .playing)
        // 상대 막대 = 응답 값(보간 없음).
        rig.server.edit { $0.opponent.score = 40; $0.opponent.seq = 5 }
        rig.clock.advance(3)
        store.tick()
        await rig.settle()
        #expect(store.raceSnapshot()?.opponentScore == 40)
        // 정산(서버가 닫음) → 결과 · 루비 · 미션 꼬리 한 번.
        rig.server.finish(winner: CDRig.me, reason: "goal", finalMe: 100, finalOpponent: 40)
        rig.clock.advance(3)
        store.tick()
        await rig.settle()
        #expect(store.phase == .finished)
        #expect(store.match?.outcome == .win)
        #expect(store.match?.rubyDelta == DuelFee.winnerNet(stake: 5))
        #expect(store.match?.endReason == .goal)
        #expect(rig.tally.finished == 1)
        #expect(store.raceSnapshot()?.myScore == 100)
        // 끝난 판엔 더 보고하지 않는다.
        let reports = rig.reportCount
        rig.clock.advance(5)
        store.tick()
        await rig.settle()
        #expect(rig.reportCount == reports)
        store.backToLobby()
        #expect(store.phase == .lobby)
        #expect(store.match == nil)
    }

    @Test("other_device: 보고가 돌려보내지면 곧바로 물러난다 — 구동기·판 루프가 내려가고 안내 한 줄 · 그 뒤 보고 0(ok 판은 계속 보고)")
    func otherDeviceYields() async {
        // 없으면: 같은 계정의 놀던 맥이 진짜 판을 덮어쓰거나, 물러난 뒤에도 판 루프가 보고를 계속 내 서버가 매번 막는다.
        let rig = CDRig.make("other-device")
        await rig.startPlaying()
        rig.server.edit { $0.reportReplyStatus = "other_device"; $0.myDevice = "other" }
        rig.clock.advance(3)
        rig.store.tick()
        await rig.settle()
        #expect(rig.store.playingElsewhere)
        #expect(rig.store.duel == nil)
        #expect(rig.store.notice == CrossyDuelNoticeText.otherDevice)
        #expect(rig.store.yieldedMatchIDs.contains(CDRig.matchID))
        let after = rig.reportCount
        rig.clock.advance(5)
        rig.store.tick()
        await rig.settle()
        #expect(rig.reportCount == after)
        // 기준선: ok 로 답하는 판은 같은 걸음에 보고가 나간다.
        let ok = CDRig.make("other-device-baseline")
        await ok.startPlaying()
        let before = ok.reportCount
        ok.clock.advance(3)
        ok.store.tick()
        await ok.settle()
        #expect(ok.reportCount == before + 1)
        #expect(ok.store.playingElsewhere == false)
    }

    @Test("상태 응답: not_found 는 판을 내림 · unsupported_client → 업데이트 · PGRST202 → 곧 열려요 · ok 로비가 되살린다")
    func availabilityStates() async throws {
        // 없으면: 배포 중간 창(앱이 db push 보다 먼저)에서 '연결 확인' 빨간 줄만 뜨고, 서버가 열린 뒤에도 영영 막힌 채 남는다.
        let rig = CDRig.make("availability")
        await rig.startPlaying()
        rig.server.edit { $0.reportReplyStatus = "not_found" }
        rig.clock.advance(3)
        rig.store.tick()
        await rig.settle()
        #expect(rig.store.match == nil)
        #expect(rig.store.phase == .lobby)
        #expect(rig.store.notice == CrossyDuelNoticeText.finishedMatch)

        rig.script.enqueue("crossy_duel_lobby", cdJSON(["status": "unsupported_client", "server_now_ms": rig.clock.nowMs]))
        await rig.store.refreshLobby()
        #expect(rig.store.availability == .updateRequired)
        #expect(rig.store.notice == CrossyDuelNoticeText.updateMine)
        rig.script.enqueue("crossy_duel_lobby", cdPGRST202("crossy_duel_lobby"), status: 404)
        await rig.store.refreshLobby()
        #expect(rig.store.availability == .serverMissing)
        #expect(rig.store.notice == CrossyDuelNoticeText.unavailable)
        await rig.store.refreshLobby()                               // 고정 응답(ok)
        #expect(rig.store.availability == .available)
    }

    @Test("규칙 ① 말풍선 문 = 보임 && !가림 — 창 닫힘(기준선) 1 · 보임+가림(결함 자리) 1 · 보임+안 가림(대조) 0")
    func attentionDoorNeedsVisibleAndUnoccluded() {
        // 없으면: 로비 창을 띄운 채 다른 전체 화면 앱에 있는 사람은 화면도 폴링도 못 알려 준비 30초를 놓친다(테트리스 11-03 수리).
        func attentions(visible: Bool, occluded: Bool) -> Int {
            let rig = CDRig.make("door-\(visible)-\(occluded)")
            if visible { rig.store.isWindowVisible = true }
            if occluded { rig.store.windowOcclusionDidChange(visible: false) }
            rig.applyServerState()
            return rig.tally.attentions.count
        }
        #expect(attentions(visible: false, occluded: false) == 1)
        #expect(attentions(visible: true, occluded: true) == 1)
        #expect(attentions(visible: true, occluded: false) == 0)
    }

    @Test("규칙 ② windowDidShow 는 가림 기록을 안 지운다(보인 창을 다시 부름) — 숨은 창이 처음 뜨면 지운다(기준선)")
    func windowDidShowKeepsOcclusion() {
        // 없으면: 판 시작의 presentWindow 가 가린 창을 '보임'으로 되돌려 말풍선 문이 닫히고 사람은 판이 열린 것을 모른다.
        let rig = CDRig.make("reshow")
        rig.store.lastLobbyRequestAt = rig.clock.deviceWall
        rig.store.windowDidShow()
        rig.store.windowOcclusionDidChange(visible: false)
        rig.store.windowDidShow()
        #expect(rig.store.isWindowOccluded)
        rig.applyServerState()
        #expect(rig.tally.attentions.count == 1)
        let hidden = CDRig.make("reshow-baseline")
        hidden.store.windowOcclusionDidChange(visible: false)
        hidden.store.lastLobbyRequestAt = hidden.clock.deviceWall
        hidden.store.windowDidShow()
        #expect(hidden.store.isWindowOccluded == false)
    }

    @Test("규칙 ③ lobbyAgain: 도는 중 온 부름은 끝난 뒤 한 번 더(버리면 1회) · 합친 부름이 사람 목록을 원하면 그 바퀴는 전체 로비")
    func lobbyCallsMergeIntoOneMore() async {
        // 없으면: 판 밖 신청·수락 초인종이 도는 로비 조회에 묻혀 받은 신청 카드·메뉴바 점이 다음 계기(30초)까지 안 선다.
        let rig = CDRig.make("lobby-again")
        rig.script.enqueue("crossy_duel_lobby", cdLobby(clock: rig.clock, light: true), delay: 0.3)
        let first = Task { await rig.store.refreshLightLobby() }
        await cdWait { rig.count("crossy_duel_lobby") == 1 }
        await rig.store.refreshLobby()                                // 도는 중 — 합쳐진다
        await rig.store.refreshLobby()                                // 또 — 같은 한 번으로
        await first.value
        #expect(rig.count("crossy_duel_lobby") == 2)
        let bodies = rig.calls("crossy_duel_lobby")
        #expect(bodies.first?["p_users"] as? Bool == false)
        #expect(bodies.last?["p_users"] as? Bool == true)
        #expect(rig.store.users.count == 1)
    }

    @Test("규칙 ④ 폴링 걸음 사이 가드 — 첫 걸음 도중 창이 가려지면 둘째 걸음(로비)은 없다 · 안 가려지면 한다(기준선) · 판 중엔 조회 0")
    func pollStepsRecheckBetweenSteps() async {
        // 없으면: 창을 가린 뒤에도 폴링 걸음이 끝까지 돌아 가려진 창이 30초마다 사람 목록을 읽는다(CS-4 부하).
        func lobbyCalls(occludeMidway: Bool) async -> Int {
            let rig = CDRig.make("poll-guard-\(occludeMidway)")
            rig.store.lastLobbyRequestAt = rig.clock.deviceWall
            rig.store.windowDidShow()
            rig.script.enqueue("crossy_duel_challenge", cdJSON([
                "status": "ok", "match_id": CDRig.matchID, "expires_at_ms": rig.clock.nowMs + 60_000]))
            await rig.store.challenge(userID: CDRig.rival, stake: .three)
            rig.server.edit { $0.status = "pending" }
            rig.script.enqueue("crossy_duel_state", rig.server.envelope(), delay: 0.3)
            rig.clock.advance(31)
            let lobbyBefore = rig.count("crossy_duel_lobby")
            let tick = Task { await rig.store.pollTick(at: rig.clock.deviceWall) }
            await cdWait { rig.count("crossy_duel_state") == 1 }
            if occludeMidway { rig.store.windowOcclusionDidChange(visible: false) }
            await tick.value
            return rig.count("crossy_duel_lobby") - lobbyBefore
        }
        #expect(await lobbyCalls(occludeMidway: true) == 0)
        #expect(await lobbyCalls(occludeMidway: false) >= 1)
        // 판 중 걸음: 보낸 신청 · 로비 조회가 없다(보고가 판 상태를 가져온다).
        let playing = CDRig.make("poll-playing")
        await playing.startPlaying()
        playing.clock.advance(31)
        let before = playing.count("crossy_duel_lobby") + playing.count("crossy_duel_state")
        await playing.store.pollTick(at: playing.clock.deviceWall)
        #expect(playing.count("crossy_duel_lobby") + playing.count("crossy_duel_state") == before)
    }

    @Test("규칙 ⑤ 나르던 작업이 취소돼 접힌 로비 조회 — 합쳐진 부름은 취소 밖으로 넘겨 한 번 더 돈다")
    func cancelledLobbyHandsOffMergedCall() async {
        // 없으면: 폰 `.refreshable` 처럼 나르던 작업이 취소되면 그 조회에 합쳐진 초인종 조회까지 사라진다.
        let rig = CDRig.make("handoff")
        rig.script.enqueue("crossy_duel_lobby", cdLobby(clock: rig.clock), delay: 0.5)
        let carrier = Task { await rig.store.refreshLobby() }
        await cdWait { rig.count("crossy_duel_lobby") == 1 }
        await rig.store.refreshLightLobby()                            // 합쳐진 부름
        carrier.cancel()
        await carrier.value
        await cdWait { rig.count("crossy_duel_lobby") >= 2 && rig.store.hasLoadedLobby }
        #expect(rig.count("crossy_duel_lobby") >= 2)
        #expect(rig.store.hasLoadedLobby)
    }

    @Test("만료 타이머: 받은 신청이 만료되면 visibleIncoming 이 nil 로 바뀌고 관찰자가 깬다(시계를 읽는 화면 없이)")
    func inviteExpiryTimerWakesObservers() async {
        // 없으면: 배너·메뉴바 점이 시계를 읽지 않으므로 만료된 신청이 다음 로비 조회(30초)까지 남는다.
        let rig = CDRig.make("expiry")
        rig.script.stand("crossy_duel_lobby", cdLobby(clock: rig.clock, incoming: [
            cdInvite(peerKey: "from", clock: rig.clock, expiresIn: 0.2)]))
        await rig.store.refreshLightLobby()
        #expect(rig.store.visibleIncoming?.id == CDRig.matchID)         // 기준선: 만료 전엔 있다
        #expect(rig.tally.arrived.count == 1)
        final class Flag: @unchecked Sendable { var fired = false }
        let flag = Flag()
        withObservationTracking({ _ = rig.store.visibleIncoming }, onChange: { flag.fired = true })
        rig.clock.advance(1)
        await cdWait { rig.store.visibleIncoming == nil }
        #expect(rig.store.visibleIncoming == nil)
        #expect(flag.fired)
    }

    @Test("늦은 로비가 지금 판의 신청을 되살리지 않는다(같은 id) · 다른 id 신청은 선다(기준선) · 끝난 판은 진행 중 응답으로 되감기지 않는다")
    func lateResponsesDoNotResurrect() async throws {
        // 없으면: 수락 직후 늦게 온 로비가 방금 판이 된 신청 카드를 다시 세우고, 끝난 판이 옛 진행 중 스냅숏으로 되살아난다.
        let rig = CDRig.make("late")
        rig.applyServerState()
        await rig.store.applyLobby(try cdDecode(CrossyDuelLobbyResponse.self, cdLobby(clock: rig.clock, incoming: [
            cdInvite(peerKey: "from", clock: rig.clock),
            cdInvite("feed0000-0000-4000-8000-000000000001", peerKey: "from", clock: rig.clock)], active: CDRig.matchID)))
        #expect(rig.store.incoming.map(\.id) == ["feed0000-0000-4000-8000-000000000001"])
        #expect(rig.store.visibleIncomingInvites.map(\.id) == ["feed0000-0000-4000-8000-000000000001"])
        // 끝난 판 → 같은 판의 진행 중 응답(seq 가 더 커도)은 무시.
        rig.server.finish(winner: CDRig.rival, reason: "resign", finalMe: 0, finalOpponent: 0)
        rig.applyServerState()
        #expect(rig.store.match?.isFinished == true)
        rig.server.edit { $0.status = "active"; $0.result = nil; $0.winner = nil; $0.endReason = nil; $0.me.seq = 9 }
        #expect(rig.applyServerState() == .ignored)
        #expect(rig.store.match?.isFinished == true)
        #expect(rig.store.phase == .finished)
    }

    @Test("늦은 보고 응답: 같은 판의 내 seq·상대 seq 가 줄어든 스냅숏은 버린다 · 더 새 것은 받는다")
    func olderSnapshotsAreDropped() {
        // 없으면: 체크포인트 응답 뒤 늦게 닿은 옛 상태 조회가 상대 막대를 한 박자 전으로 되돌린다.
        let rig = CDRig.make("seq-guard")
        rig.server.edit { $0.opponent.seq = 5; $0.opponent.score = 30; $0.me.seq = 2; $0.me.ready = true }
        rig.applyServerState()
        #expect(rig.store.match?.opponentScore == 30)
        rig.server.edit { $0.opponent.seq = 4; $0.opponent.score = 20 }
        #expect(rig.applyServerState() == .ignored)
        #expect(rig.store.match?.opponentScore == 30)
        rig.server.edit { $0.opponent.seq = 6; $0.opponent.score = 33 }
        #expect(rig.applyServerState() == .applied)
        #expect(rig.store.match?.opponentScore == 33)
    }

    @Test("재실행 resume: 시작 뒤 보고가 서버에 있으면 그 점수에서 다시 선다 — 첫 보고 p_score ≥ 37(시작 전 보고만 있으면 0)")
    func relaunchResumesFromServerRow() async {
        // 없으면: 판 중 앱을 다시 켜면 빈 판에서 다시 시작해 다음 보고(점수 0)가 서버 단조 가드에 걸린다.
        func scores(seenAfterStart: Bool) async -> (first: Int?, last: Int?) {
            let rig = CDRig.make("resume-\(seenAfterStart)")
            let now = rig.clock.nowMs
            rig.server.edit {
                $0.startAtMs = now - 20_000
                $0.me = CDSide(id: CDRig.me, name: "나", ready: true, seq: 3, score: 37, deaths: 1,
                               lastSeenMs: seenAfterStart ? now - 2_000 : now - 21_000)
            }
            rig.applyServerState()
            rig.clock.advance(0.5)
            rig.store.tick()
            await rig.settle()
            rig.clock.advance(3)
            rig.store.tick()
            await rig.settle()
            let bodies = rig.reportBodies
            return (bodies.first?["p_score"] as? Int, bodies.last?["p_score"] as? Int)
        }
        let resumed = await scores(seenAfterStart: true)
        #expect((resumed.first ?? 0) >= 37)
        #expect(resumed.last == 37)
        // 기준선: 시작 전 보고(준비)만 있는 행은 빈 판에서 연다 — 첫 보고 0. 서버 점수(37)가 크니 그 응답 뒤엔 CC-22 가 그 줄로 세운다.
        let fresh = await scores(seenAfterStart: false)
        #expect(fresh.first == 0)
        #expect(fresh.last == 37)
    }

    @Test("서버 점수가 로컬보다 크면 엔진을 그 줄로(CC-22 — 서버 48 → 줄 48) · 서버가 같으면 그대로(기준선)")
    func serverScoreAheadRestoresEngine() async {
        // 없으면: 로컬 엔진이 서버보다 뒤처진 채 남아 다음 보고가 단조 가드(stale)에 막히고 막대가 영영 멈춘다.
        let rig = CDRig.make("catch-up")
        await rig.startPlaying()
        #expect(rig.store.duel?.game.score == 0)
        rig.server.edit { $0.me.score = 48; $0.me.seq += 1 }
        rig.clock.advance(3)
        rig.store.tick()
        await rig.settle()
        #expect(rig.store.duel?.game.score == 48)
        #expect(rig.store.duel?.game.player.row == 48)
        let same = CDRig.make("catch-up-baseline")
        await same.startPlaying()
        same.clock.advance(3)
        same.store.tick()
        await same.settle()
        #expect(same.store.duel?.game.score == 0)
    }

    @Test("55P03(lock_timeout) 두 번 → connectionTrouble 안 켜짐(실패로 안 셈) · 보통 500 두 번 → 켜짐(기준선)")
    func lockTimeoutIsNotAFailure() async {
        // 없으면: 정산 경합 순간(= 결승선)의 lock_timeout 이 '연결 확인 중'을 띄우고 프레임을 대체 길로 떨군다(CC-21).
        func trouble(code: String) async -> (trouble: Bool, streak: Int, retriedNextStep: Bool) {
            let rig = CDRig.make("lock-\(code)")
            await rig.startPlaying()
            let body = cdJSON(["code": code, "details": NSNull(), "hint": NSNull(), "message": "canceling statement"])
            var retried = false
            for _ in 0..<2 {
                rig.script.enqueue("crossy_duel_report", body, status: 500)
                rig.clock.advance(3)
                rig.store.tick()
                await rig.settle()
                let failedAt = rig.reportCount
                rig.clock.advance(0.3)                                     // 다음 걸음(0.25초 틈 뒤)
                rig.store.tick()
                await rig.settle()
                retried = rig.reportCount == failedAt + 1
                if code != "55P03" { continue }
            }
            return (rig.store.connectionTrouble, rig.store.reportFailureStreak, retried)
        }
        let lock = await trouble(code: "55P03")
        #expect(lock.trouble == false && lock.streak == 0)
        #expect(lock.retriedNextStep)
        let generic = await trouble(code: "XX000")
        #expect(generic.trouble == true && generic.streak == 2)
        #expect(generic.retriedNextStep == false)                       // 보통 실패의 하트비트는 다음 간격(3초)까지 기다린다
    }

    @Test("state goal 99 → updateRequired · 판을 두지 않는다(CC-17) · goal 100 은 둔다(기준선)")
    func mismatchedRulesNeedUpdate() {
        // 없으면: 서버가 목표를 바꾼 날 옛 앱이 100점 엔진으로 달려 엔진·서버가 두 출처를 갖는다(먼저 닿고도 진다).
        let rig = CDRig.make("rules")
        rig.server.edit { $0.goal = 99 }
        #expect(rig.applyServerState() == .ignored)
        #expect(rig.store.availability == .updateRequired)
        #expect(rig.store.duel == nil)
        let ok = CDRig.make("rules-baseline")
        #expect(ok.applyServerState() == .applied)
        #expect(ok.store.availability == .available)
        #expect(ok.store.duel != nil)
    }

    @Test("가벼운 로비(전적 null · users [])는 사람 목록·전적을 덮지 않는다(CS-4) — 같은 모양의 전체 로비(users [])는 덮는다(기준선)")
    func lightLobbyDoesNotOverwrite() async throws {
        // 없으면: 팝오버를 열 때마다 가벼운 응답이 창의 사람 목록을 0명 · 전적을 0승으로 덮는다.
        let rig = CDRig.make("light")
        await rig.store.refreshLobby()
        #expect(rig.store.users.count == 1)
        await rig.store.applyLobby(try cdDecode(CrossyDuelLobbyResponse.self, try cdFixture("crossy_duel_lobby__light.json")))
        #expect(rig.store.users.count == 1)
        #expect(rig.store.record == CrossyDuelRecord(wins: 2, losses: 1, draws: 0))
        #expect(rig.store.rubyBalance == 100)
        #expect(rig.store.incoming.count == 1)                        // 신청은 가벼운 응답에서도 반영
        await rig.store.applyLobby(try cdDecode(CrossyDuelLobbyResponse.self, cdLobby(clock: rig.clock, users: [])))
        #expect(rig.store.users.isEmpty)
        // 팝오버 경로 = 가벼운 로비(p_users false) · 30초 스로틀.
        let menu = CDRig.make("light-menu")
        menu.store.refreshLobbyIfStale()
        menu.store.refreshLobbyIfStale()
        await cdWait { menu.count("crossy_duel_lobby") == 1 }
        #expect(menu.calls("crossy_duel_lobby").map { $0["p_users"] as? Bool } == [false])
    }

    @Test("활동 붙들기: 시작 시각이 오면 onHoldingActivityChange(true) 한 번(CC-10) · 시작 전엔 0(기준선) · 끝나면 false")
    func holdingActivitySignal() async {
        // 없으면: countdown 진입은 소유 변경이 아니라 소유 변경 자리에서만 신호를 내면 App Nap 붙들기가 영영 안 켜진다.
        let rig = CDRig.make("hold")
        rig.applyServerState()
        #expect(rig.tally.holding.isEmpty)                             // 준비 전(시작 모름)
        rig.server.edit { $0.startAtMs = $0.clock.nowMs + 3_000; $0.me.ready = true; $0.me.seq = 1 }
        rig.applyServerState()
        #expect(rig.store.phase == .countdown)
        #expect(rig.tally.holding == [true])
        rig.applyServerState()
        #expect(rig.tally.holding == [true])
        rig.server.finish(winner: nil, reason: "time_cap", finalMe: 3, finalOpponent: 3)
        rig.applyServerState()
        #expect(rig.tally.holding == [true, false])
    }

    @Test("끝난 판 스냅숏 = 굳힌 값(CC-4 · Q3 (가)) — goal 로 진 판은 max(final 95, 로컬 97) = 97 · 3분 끝은 final 95(기준선)")
    func finishedSnapshotUsesSettledScores() {
        // 없으면: 결과 카드와 트랙의 '나' 숫자가 따로 놀거나, 진 판에서 내가 본 점수가 서버의 옛 값으로 줄어든다.
        let opponent = CrossyDuelUser(id: CDRig.rival, displayName: "라이벌")
        let goalLoss = CrossyDuelMatchState(id: "m", stake: 3, opponent: opponent, myServerScore: 95, isFinished: true,
                                            outcome: .loss, endReason: .goal, finalMyScore: 95, finalOpponentScore: 100)
        #expect(CrossyDuelStore.finishedMyScore(match: goalLoss, localScore: 97) == 97)
        var timeCap = goalLoss
        timeCap.endReason = .timeCap
        #expect(CrossyDuelStore.finishedMyScore(match: timeCap, localScore: 97) == 95)
        var goalWin = goalLoss
        goalWin.outcome = .win
        #expect(CrossyDuelStore.finishedMyScore(match: goalWin, localScore: 97) == 95)
        // 스토어 스냅숏이 같은 함수를 읽는다(로컬 엔진 97).
        let store = CrossyDuelStore(uptime: { 500 })
        store.match = goalLoss
        var game = CrossyGame(seed: 1, rules: .duel)
        game.restore(row: 97, score: 97, deaths: 4)
        store.duel = CrossyDuelSession(seed: 1, startedGame: game, startAt: 100)
        #expect(store.raceSnapshot()?.myScore == 97)
        #expect(store.raceSnapshot()?.opponentScore == 100)
        #expect(store.raceSnapshot()?.frozen == true)
        store.match = timeCap
        #expect(store.raceSnapshot()?.myScore == 95)
    }

    @Test("opponentQuiet: 서버 시각끼리 빼고 받은 뒤 흐른 단조 시간을 더한다 — 기기 시계 +30초 어긋남에 안 흔들림(CC-19)")
    func opponentQuietIgnoresDeviceClockSkew() {
        // 없으면: 기기 시계가 30초 앞선 맥은 판 내내 '상대 연결 확인 중'을 띄운다(벽시계 − last_seen).
        func quiet(skew: TimeInterval, after seconds: TimeInterval) -> Bool {
            let rig = CDRig.make("quiet-\(skew)-\(seconds)")
            rig.clock.skew = skew
            let now = rig.clock.nowMs
            rig.server.edit {
                $0.startAtMs = now - 10_000
                $0.me = CDSide(id: CDRig.me, name: "나", ready: true, seq: 1, lastSeenMs: now - 12_000)
                $0.opponent.lastSeenMs = now - 2_000
            }
            rig.applyServerState()
            rig.clock.advance(seconds)
            return rig.store.raceSnapshot()?.opponentQuiet ?? false
        }
        #expect(quiet(skew: 30, after: 0) == false)
        #expect(quiet(skew: 30, after: 5.9) == false)
        #expect(quiet(skew: 30, after: 6.5) == true)
        #expect(quiet(skew: 0, after: 6.5) == true)                    // 기준선: 어긋남이 없어도 같은 답
        #expect(quiet(skew: -30, after: 5.9) == false)
    }

    @Test("픽스처 원문: 끝난 판 일곱 장 → 내 기준 결과 · 끝 사유 · 루비 · 굳힌 점수가 서버 값 그대로(판정은 서버 값만)")
    func finishedFixturesMapToOutcome() throws {
        // 없으면: result 'challenger_win' 을 내 승으로 읽는 변이(내 기준이 아님)나 final 을 무시하는 변이가 스텁 시험만으론 초록이다.
        let expectations: [(String, CrossyDuelOutcome, CrossyDuelEndReason)] = [
            ("crossy_duel_state__finished_goal_loss.json", .loss, .goal),
            ("crossy_duel_state__finished_time_cap_win.json", .win, .timeCap),
            ("crossy_duel_state__finished_time_cap_draw.json", .draw, .timeCap),
            ("crossy_duel_state__finished_resign_win.json", .win, .resign),
            ("crossy_duel_state__finished_disconnect.json", .win, .disconnect),
            ("crossy_duel_state__finished_no_show.json", .draw, .noShow),
            ("crossy_duel_state__finished_void.json", .draw, .void),
        ]
        for (file, outcome, reason) in expectations {
            let response = try cdDecode(CrossyDuelActionResponse.self, try cdFixture(file))
            let state = try #require(response.state)
            let myID = try #require(state.me?.id)
            let rig = CDRig.make("fixture-\(reason.rawValue)-\(outcome)", userID: myID)
            #expect(rig.store.applyState(state) == .applied, "\(file)")
            let match = try #require(rig.store.match)
            #expect(match.outcome == outcome, "\(file)")
            #expect(match.endReason == reason, "\(file)")
            let stake = state.stake ?? 0
            let expectedDelta = outcome == .win ? DuelFee.winnerNet(stake: stake) : (outcome == .loss ? -stake : 0)
            #expect(match.rubyDelta == expectedDelta, "\(file)")
            #expect(match.finalMyScore == state.final?.me && match.finalOpponentScore == state.final?.opponent, "\(file)")
            #expect(rig.store.phase == .finished, "\(file)")
            #expect(rig.store.duel == nil, "\(file)")
        }
        // 기준선: 남의 눈으로 읽으면(winner 가 내가 아님) 같은 승 픽스처가 패로 갈린다.
        let win = try #require(try cdDecode(CrossyDuelActionResponse.self,
                                            try cdFixture("crossy_duel_state__finished_time_cap_win.json")).state)
        let stranger = CDRig.make("fixture-stranger", userID: "ffffffff-0000-4000-8000-000000000000")
        stranger.store.applyState(win)
        #expect(stranger.store.match?.outcome == .loss)
    }

    @Test("픽스처 원문: 진행 중 판(frames 켬) → 장부가 서고 소켓을 연다 · 다른 세션 기기(frames null · my_device other) → 두지 않는다")
    func activeFixturesDriveFramesAndOwnership() throws {
        // 없으면: 실제 서버 모양(frames.topic · my_device)과 스토어의 읽기가 어긋나도 손 픽스처 시험은 초록이다.
        let playing = try #require(try cdDecode(CrossyDuelActionResponse.self,
                                                try cdFixture("crossy_duel_state__playing.json")).state)
        let rig = CDRig.make("fixture-playing", userID: try #require(playing.me?.id))
        rig.store.applyState(playing)
        #expect(rig.store.duel != nil)
        #expect(rig.store.frameLink?.topic == playing.frames?.topic)
        #expect(rig.channel.connects.map(\.topic) == [try #require(playing.frames?.topic)])
        #expect(rig.store.match?.reportMs == 1000)
        let other = try #require(try cdDecode(CrossyDuelActionResponse.self,
                                              try cdFixture("crossy_duel_state__other_device.json")).state)
        let elsewhere = CDRig.make("fixture-other", userID: try #require(other.me?.id))
        elsewhere.store.applyState(other)
        #expect(elsewhere.store.duel == nil)
        #expect(elsewhere.store.playingElsewhere)
        #expect(elsewhere.channel.connects.isEmpty)
        let off = try #require(try cdDecode(CrossyDuelActionResponse.self,
                                            try cdFixture("crossy_duel_state__frames_off.json")).state)
        let switched = CDRig.make("fixture-off", userID: try #require(off.me?.id))
        switched.store.applyState(off)
        #expect(switched.channel.connects.isEmpty)
        #expect(switched.store.frameChangeReportsSuppressed(at: switched.clock.uptime) == false)
    }
}
