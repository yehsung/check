import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.74 — 테트리스 대결 Broadcast 전환의 **스토어·소켓** 갈래(명세 docs/plan/tetris-broadcast/SPEC.md §4·§6·§8·§9·§10·§16).
// 순수 장부(`TetrisFrameLink`)는 V0374TetrisFramesCoreTests 가 잰다. 여기는 그 장부가 **스토어에 물렸을 때의 결과**를 잰다 —
// 보고가 실제로 몇 건 나가는가 · 상대 판이 무엇을 보이는가 · 공격이 언제 대기열에 들어가는가 · 소켓이 언제 열리고 닫히는가.
//
// ── 하네스: 한 판을 두 스토어로 ──
//   · 흉내 서버 `TFServer`(두 사람 공용 — `TDServer` 의 규칙 + `frames_v` · 서버 스위치 · 관전자 수 · 침묵 15초 · 정산 · 초인종)
//   · 흉내 Realtime `TFRelay` + 스텁 소켓 `TFChannel`(사람마다 하나). 보내는 쪽은 **진짜 봉투**(`RealtimeFrame.broadcast`)를 만들고
//     받는 쪽은 **진짜 해석**(`TetrisFrameWire.event`)을 거친다 — 봉투 모양이 한쪽만 바뀌면 여기서 빨개진다. 유실·지연·뒤집힘·
//     위조·조인 거절·쓰기 거절·한도 초과 닫힘을 주입한다(§16 유실 주입 표).
//   · 두 스토어가 시계 하나(`TFClock` — 단조·벽시계 함께)를 쓰고, 판 루프·폴링 루프는 재우고(3,600초) 걸음(`TFDuo.step`)이 직접 민다.
//   · 보고는 진짜 `SupabaseWorkService` 가 URL 스텁(`GomokuStubProtocol`)으로 서버를 부른다 — 요청 본문의 `p_protocol` 까지 잰다.
//
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례).

// MARK: - 상수

private let tfA = "00000000-0000-0000-0000-0000000000a1"
private let tfB = "00000000-0000-0000-0000-0000000000b2"
private let tfMatch = "7e7e0000-0000-4000-8000-000000000374"
private let tfTopic = "tetris:\(tfMatch)"
private let tfWall0 = Date(timeIntervalSince1970: 1_800_000_000)
private let tfWall0Ms = tfWall0.timeIntervalSince1970 * 1000
private let tfBoardX = String(repeating: ".", count: 190) + "ZZZZ.ZZZZZ"
private let tfBoardY = String(repeating: ".", count: 180) + "SSSSS.SSSS" + "ZZZZ.ZZZZZ"
private let tfBoardZ = String(repeating: ".", count: 170) + "TTTTTTTT.T" + "SSSSS.SSSS" + "ZZZZ.ZZZZZ"
private let tfBoardW = String(repeating: ".", count: 190) + "LLLLLLLLL."

private struct TFError: Error {}

private func tfOpt(_ value: Any?) -> Any { value ?? NSNull() }

private func tfOther(_ user: String) -> String { user == tfA ? tfB : tfA }

private func tfJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func tfDecode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: Data(text.utf8))
}

/// 상대(`u`)가 보낸 프레임 한 장.
private func tfFrame(from sender: String = tfB, s: Int, f: Int, board: String = TetrisDuelBoard.emptyText,
                     lines: Int = 0, g: Int = 0, p: Int = 0, h: Int = 500) -> TetrisFrame {
    TetrisFrame(sender: sender, seq: s, frame: f, board: board, lines: lines, attackSent: g, pending: p, heardAgoMs: h)
}

// MARK: - 시계 · 호스트

/// 단조 시계와 벽시계를 **함께** 민다(두 스토어 · 서버가 같은 시각을 본다).
private final class TFClock: @unchecked Sendable {
    var uptime: TimeInterval = 1_000
    var wall: Date = tfWall0
    var wallMs: Double { wall.timeIntervalSince1970 * 1000 }

    func advance(_ seconds: TimeInterval) {
        uptime += seconds
        wall = wall.addingTimeInterval(seconds)
    }
}

/// 다음 세션 재시도가 끝날 때 갈아 끼울 토큰(만료 흉내 — 스텁 응답기가 URL 스레드에서 적는다).
private final class TFTokens: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: String?
    private var rotateOnState = false
    private var counter = 0

    func armStateRefresh() {
        lock.lock(); rotateOnState = true; lock.unlock()
    }

    /// `tetris_state` 가 서버에 닿았다 — 무장돼 있으면 새 토큰을 준비한다(만료 토큰을 받은 REST 가 갱신하는 흉내).
    func stateCalled() {
        lock.lock()
        defer { lock.unlock() }
        guard rotateOnState else { return }
        rotateOnState = false
        counter += 1
        pending = "fresh-token-\(counter)"
    }

    func take() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let value = pending
        pending = nil
        return value
    }
}

@MainActor
private final class TFHost: GomokuStoreHost {
    var session: SupabaseSession?
    var sessionGeneration = 0
    let service: SupabaseWorkService
    var realtimeState: RealtimeState = .idle(.disabled)
    var rubyBalance: Int?
    let tokens = TFTokens()

    init(service: SupabaseWorkService, userID: String) {
        self.service = service
        session = SupabaseSession(accessToken: "token-\(userID.suffix(2))", refreshToken: nil, userID: userID)
    }

    func withSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T {
        guard let current = session else { throw TFError() }
        let value = try await operation(current)
        if let fresh = tokens.take() {
            session = SupabaseSession(accessToken: fresh, refreshToken: nil, userID: current.userID)
        }
        return value
    }

    func classifyAuthError(_ error: Error) -> AuthErrorDisposition { .transient }
}

@MainActor
private enum TFRetention {
    /// 스토어는 호스트를 **약참조**로 든다. 시험이 버리면 요청이 한 건도 안 나간다.
    static var hosts: [TFHost] = []
}

// MARK: - 흉내 서버

private struct TFPlayer {
    var id: String
    var ready = false
    var seq = 0
    var board: String?
    var lines = 0
    var sent = 0
    var applied = 0
    var pending = 0
    var lastSeenMs: Double?
    var toppedOut = false
    /// 마지막으로 **쓴** 보고의 `p_protocol` ≥ 2 면 1(서버 `tetris_players.frames_v`).
    var framesV = 0

    var json: [String: Any] {
        ["id": id, "display_name": id == tfA ? "가" : "나", "avatar_url": NSNull(), "character": NSNull(),
         "ready": ready, "seq": seq, "board": tfOpt(board), "lines": lines, "garbage_sent": sent,
         "garbage_applied": applied, "pending": pending, "last_seen_ms": tfOpt(lastSeenMs), "topped_out": toppedOut]
    }
}

/// 두 사람 공용 서버. `tetris_report` 의 순서(§2.4 · ONE)를 흉내 낸다: 준비 → seq 비교 → 쓰기(`frames_v` 포함) → 공격이 늘면 상대
/// 초인종 → 탑아웃이면 상대 승 정산. 상태의 `frames` 는 서버 스위치 · 진행 중 · 두 자리 `frames_v` = 1 일 때만 켠다(§12-4).
/// `tetris__due` 흉내: 시작 뒤 한쪽만 15초 넘게 조용하면 그쪽 패(disconnect), 둘 다면 무승부.
private final class TFServer: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var nowMs: Double = tfWall0Ms
    var players: [String: TFPlayer] = [tfA: TFPlayer(id: tfA), tfB: TFPlayer(id: tfB)]
    var startAtMs: Double?
    var status = "active"
    var winner: String?
    var endReason: String?
    var stake = 3
    var rubies: [String: Int] = [tfA: 100, tfB: 100]
    var framesSwitch = true
    var watchers = 0
    var silenceJudge = true
    /// 그 사람의 다음 보고 n건을 500 으로 돌려보낸다(쓰지 않는다).
    var failNextReports: [String: Int] = [:]
    /// 그 사람의 보고 답을 실시간 이만큼 늦게 준다(멎음 흉내 — 서버는 곧바로 받아 적는다).
    var reportDelay: [String: TimeInterval] = [:]
    /// 판 상태 조회 답을 실시간 이만큼 늦게 준다(조회가 도는 동안 다른 일이 겹치는 흉내).
    var stateDelay: TimeInterval = 0
    private var reportsBy: [String: [[String: Any]]] = [:]
    private var reportTimesBy: [String: [Double]] = [:]
    private var stateCallsBy: [String: Int] = [:]
    private var rings: [String] = []

    func edit(_ change: (TFServer) -> Void) {
        lock.lock()
        change(self)
        lock.unlock()
    }

    func setNow(_ ms: Double) {
        lock.lock()
        nowMs = ms
        lock.unlock()
    }

    func player(_ user: String) -> TFPlayer {
        lock.lock()
        defer { lock.unlock() }
        return players[user]!
    }

    func snapshot<T>(_ read: (TFServer) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return read(self)
    }

    func state(for user: String) -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return stateLocked(for: user)
    }

    func reports(of user: String) -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return reportsBy[user] ?? []
    }

    func reportTimes(of user: String) -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        return reportTimesBy[user] ?? []
    }

    func stateCalls(of user: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return stateCallsBy[user] ?? 0
    }

    func popRings() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let out = rings
        rings = []
        return out
    }

    func report(_ body: String, from user: String) -> GomokuStubProtocol.Reply {
        lock.lock()
        defer { lock.unlock() }
        let args = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        reportsBy[user, default: []].append(args)
        reportTimesBy[user, default: []].append(nowMs)
        let delay = reportDelay[user] ?? 0
        if let fail = failNextReports[user], fail > 0 {
            failNextReports[user] = fail - 1
            return GomokuStubProtocol.Reply(status: 500, body: #"{"code":"XX000","details":null,"hint":null,"message":"boom"}"#,
                                            delay: delay)
        }
        dueLocked()
        let other = tfOther(user)
        guard status == "active", var me = players[user] else {
            return GomokuStubProtocol.Reply(body: envelope("stale", stateLocked(for: user)), delay: delay)
        }
        if !me.ready {
            me.ready = true
            if players[other]?.ready == true, startAtMs == nil { startAtMs = nowMs + 3_000 }
        }
        let seq = args["p_seq"] as? Int ?? 0
        guard seq > me.seq else {
            players[user] = me
            return GomokuStubProtocol.Reply(body: envelope("stale", stateLocked(for: user)), delay: delay)
        }
        me.seq = seq
        me.board = args["p_board"] as? String
        me.lines = args["p_lines"] as? Int ?? me.lines
        let sent = max(me.sent, args["p_garbage_sent"] as? Int ?? 0)
        let attacked = sent > me.sent
        me.sent = sent
        me.applied = args["p_garbage_applied"] as? Int ?? me.applied
        me.pending = args["p_pending"] as? Int ?? me.pending
        me.lastSeenMs = nowMs
        me.framesV = (args["p_protocol"] as? Int ?? 1) >= 2 ? 1 : 0
        players[user] = me
        if attacked { rings.append(other) }
        if args["p_topped_out"] as? Bool == true {
            players[user]?.toppedOut = true
            finishLocked(winner: other, reason: "topout")
        }
        return GomokuStubProtocol.Reply(body: envelope("ok", stateLocked(for: user)), delay: delay)
    }

    func stateCall(from user: String) -> GomokuStubProtocol.Reply {
        lock.lock()
        defer { lock.unlock() }
        stateCallsBy[user, default: 0] += 1
        dueLocked()
        return GomokuStubProtocol.Reply(body: envelope("ok", stateLocked(for: user)), delay: stateDelay)
    }

    func lobby(for user: String) -> GomokuStubProtocol.Reply {
        lock.lock()
        defer { lock.unlock() }
        return GomokuStubProtocol.Reply(body: tfJSON([
            "status": "ok", "server_now_ms": nowMs, "stakes": [3, 5, 10],
            "me": ["ruby_balance": rubies[user] ?? 0, "wins": 0, "losses": 0, "draws": 0,
                   "active_match_id": tfOpt(status == "active" ? tfMatch : nil), "incoming": [] as [Any],
                   "outgoing": NSNull()],
            "users": [] as [Any], "matches": [] as [Any],
        ]))
    }

    /// 판을 닫는다(정산 — 승자 +판돈 · 패자 −판돈). 두 사람 모두에게 초인종.
    func finish(winner: String?, reason: String) {
        lock.lock()
        defer { lock.unlock() }
        finishLocked(winner: winner, reason: reason)
    }

    private func finishLocked(winner: String?, reason: String) {
        guard status == "active" else { return }
        status = "finished"
        self.winner = winner
        endReason = reason
        if let winner {
            rubies[winner, default: 0] += stake
            rubies[tfOther(winner), default: 0] -= stake
        }
        rings.append(contentsOf: [tfA, tfB])
    }

    private func dueLocked() {
        guard silenceJudge, status == "active", let start = startAtMs, nowMs > start else { return }
        let silent = players.values.filter { nowMs - max(start, $0.lastSeenMs ?? start) > 15_000 }.map(\.id)
        if silent.count == 2 {
            finishLocked(winner: nil, reason: "disconnect")
        } else if let loser = silent.first {
            finishLocked(winner: tfOther(loser), reason: "disconnect")
        }
    }

    private func stateLocked(for user: String) -> [String: Any] {
        let me = players[user]!
        let opponent = players[tfOther(user)]!
        let finished = status == "finished"
        var state: [String: Any] = [
            "match_id": tfMatch, "status": status, "stake": stake, "seed": 4_242, "server_now_ms": nowMs,
            "accepted_at_ms": tfWall0Ms - 2_000, "start_at_ms": tfOpt(startAtMs), "ready_deadline_ms": tfWall0Ms + 28_000,
            "max_end_ms": tfOpt(startAtMs.map { $0 + 480_000 }), "finished_at_ms": tfOpt(finished ? nowMs : nil),
            "me": me.json, "opponent": opponent.json,
            "result": tfOpt(finished ? (winner == nil ? "draw" : (winner == tfA ? "challenger_win" : "opponent_win")) : nil),
            "winner": tfOpt(winner), "end_reason": tfOpt(endReason), "ruby_balance": rubies[user] ?? 0,
            "watchers": watchers, "my_device": "this",
        ]
        let on = status == "active" && framesSwitch && me.framesV == 1 && opponent.framesV == 1
        state["frames"] = on ? ["on": true, "topic": tfTopic] as [String: Any] : NSNull()
        return state
    }

    private func envelope(_ status: String, _ state: [String: Any]) -> String {
        tfJSON(["status": status, "state": state])
    }
}

// MARK: - 흉내 Realtime

/// 결정적 난수(xorshift64*) — 유실·뒤집힘 주입이 돌릴 때마다 같다.
private struct TFRandom {
    var state: UInt64

    mutating func next() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return Double((state &* 2_685_821_657_736_338_717) >> 11) / Double(1 << 53)
    }
}

/// 판 전용 채널의 흉내. self:false(보낸 사람에게 안 돌아온다) · 조인 전 송신은 버림 · 연결 번호가 바뀐 소켓엔 배달하지 않는다.
@MainActor
private final class TFRelay {
    enum JoinPolicy { case accept, reject(String) }

    private struct Delivery {
        let at: TimeInterval
        let order: Int
        let to: String
        let connection: Int
        let text: String
        let frameNumber: Int?
    }

    private(set) var channels: [String: TFChannel] = [:]
    private var queue: [Delivery] = []
    private var order = 0
    private var nextConnection = 0
    private var rng = TFRandom(state: 0x9E37_79B9_7F4A_7C15)
    var now: TimeInterval = 0

    // 주입
    var joinPolicy: [String: JoinPolicy] = [:]
    /// 이 사람이 보낸 프레임은 서버가 조용히 버린다(INSERT 정책 거절 — `ack:false` 라 보낸 쪽은 모른다).
    var writeDenied: Set<String> = []
    /// 보낸 사람별 유실 확률 · 지연 · 0~spread 무작위 추가 지연(뒤집힘).
    var dropRate: [String: Double] = [:]
    var delay: [String: TimeInterval] = [:]
    var spread: [String: TimeInterval] = [:]
    /// 보낸 사람별 본문 위조.
    var tamper: [String: ([String: Any]) -> [String: Any]] = [:]
    /// 이 사람은 망이 끊겼다 — 여는 족족 곧바로 닫힌다(조인 답 없음).
    var offline: Set<String> = []

    // 기록
    private(set) var deliveredFrames: [String: [Int]] = [:]
    private(set) var droppedFrames: [String: Int] = [:]

    func attach(_ channel: TFChannel) {
        channels[channel.user] = channel
        channel.relay = self
    }

    func newConnection() -> Int {
        nextConnection += 1
        return nextConnection
    }

    func join(_ channel: TFChannel, connection: Int, topic: String) {
        if offline.contains(channel.user) {
            enqueue(to: channel.user, connection: connection, after: 0, frameNumber: nil,
                    text: tfJSON(["topic": "realtime:\(topic)", "event": "phx_close", "ref": NSNull(),
                                  "payload": [String: Any]()]))
            return
        }
        let payload: [String: Any]
        switch joinPolicy[channel.user] ?? .accept {
        case .accept:
            payload = ["status": "ok", "response": [String: Any]()]
        case .reject(let reason):
            payload = ["status": "error", "response": ["reason": reason]]
        }
        enqueue(to: channel.user, connection: connection, after: 0, frameNumber: nil,
                text: tfJSON(["topic": "realtime:\(topic)", "event": "phx_reply", "ref": "1", "join_ref": "1",
                              "payload": payload]))
    }

    func broadcast(from channel: TFChannel, text: String) {
        let user = channel.user
        guard channel.joined, let topic = channel.topic else { return }        // 조인 전 push 는 서버가 버린다
        if writeDenied.contains(user) || (dropRate[user].map { rng.next() < $0 } ?? false) {
            droppedFrames[user, default: 0] += 1
            return
        }
        guard let receiver = channels[tfOther(user)], receiver.joined, receiver.topic == topic else {
            droppedFrames[user, default: 0] += 1
            return
        }
        var outgoing = text
        let decoded = RealtimeFrame.decodeBroadcastPayload(text: text, channel: topic)
        if let change = tamper[user], let decoded {
            outgoing = RealtimeFrame.broadcast(channel: topic, event: decoded.event, payload: change(decoded.payload),
                                               ref: "99", joinRef: "1")
        }
        let wait = (delay[user] ?? 0) + (spread[user] ?? 0) * rng.next()
        enqueue(to: receiver.user, connection: receiver.connection, after: wait,
                frameNumber: decoded?.payload["f"] as? Int, text: outgoing)
    }

    /// 서버가 이 사람의 채널을 닫는다(텍스트 그대로 — 해석을 거친다).
    func serverSends(_ user: String, _ objects: [[String: Any]]) {
        guard let channel = channels[user] else { return }
        for object in objects {
            enqueue(to: user, connection: channel.connection, after: 0, frameNumber: nil, text: tfJSON(object))
        }
    }

    /// 망이 끊겼다 — 그 소켓에 곧바로 닫힘.
    func dropConnection(_ user: String) {
        guard let channel = channels[user], let topic = channel.topic else { return }
        serverSends(user, [["topic": "realtime:\(topic)", "event": "phx_close", "ref": NSNull(), "payload": [String: Any]()]])
    }

    func pump(until now: TimeInterval) {
        self.now = now
        while let index = queue.indices.filter({ queue[$0].at <= now + 1e-9 })
            .min(by: { (queue[$0].at, queue[$0].order) < (queue[$1].at, queue[$1].order) }) {
            let delivery = queue.remove(at: index)
            guard let channel = channels[delivery.to] else { continue }
            if let number = delivery.frameNumber, channel.connection == delivery.connection {
                deliveredFrames[delivery.to, default: []].append(number)
            }
            channel.receive(text: delivery.text, connection: delivery.connection)
        }
    }

    /// 받는 쪽에 **실제로 뒤집혀** 닿은 쌍의 수(기준선 — 뒤집힘 주입이 정말 일어났는가).
    func inversions(at user: String) -> Int {
        let numbers = deliveredFrames[user] ?? []
        guard numbers.count > 1 else { return 0 }
        return zip(numbers, numbers.dropFirst()).filter { $0.0 > $0.1 }.count
    }

    private func enqueue(to user: String, connection: Int, after wait: TimeInterval, frameNumber: Int?, text: String) {
        order += 1
        queue.append(Delivery(at: now + wait, order: order, to: user, connection: connection, text: text,
                              frameNumber: frameNumber))
    }
}

/// 스텁 프레임 소켓 — 명령을 적고, 보낼 때는 진짜 봉투를 만들고, 받을 때는 진짜 해석을 거친다.
@MainActor
private final class TFChannel: TetrisFrameChannel {
    var onEvent: ((TetrisFrameChannelEvent) -> Void)?
    let user: String
    weak var relay: TFRelay?
    private(set) var connection = 0
    private(set) var topic: String?
    private(set) var joined = false
    private(set) var connects: [(topic: String, token: String, apiKey: String)] = []
    private(set) var sentPayloads: [[String: Any]] = []
    private(set) var pushes: [String] = []
    private(set) var disconnects = 0
    private var ref = 1

    init(user: String) {
        self.user = user
    }

    var isOpen: Bool { topic != nil }

    func connect(url: URL, apiKey: String, accessToken: String, topic: String) {
        connection = relay?.newConnection() ?? connection + 1
        self.topic = topic
        joined = false
        connects.append((topic, accessToken, apiKey))
        relay?.join(self, connection: connection, topic: topic)
    }

    func send(event: String, payload: [String: Any]) {
        guard let topic else { return }
        sentPayloads.append(payload)
        ref += 1
        relay?.broadcast(from: self, text: RealtimeFrame.broadcast(channel: topic, event: event, payload: payload,
                                                                   ref: "\(ref)", joinRef: "1"))
    }

    func pushAccessToken(_ token: String) {
        pushes.append(token)
    }

    func disconnect() {
        disconnects += 1
        topic = nil
        joined = false
        connection = -1
    }

    func receive(text: String, connection: Int) {
        guard connection == self.connection, let topic,
              let event = TetrisFrameWire.event(text: text, topic: topic, joinRef: "1") else { return }
        if event == .transport(.joined) { joined = true }
        onEvent?(event)
    }

    /// 시험이 사건을 곧바로 넣는다(상대 없이 프레임을 꽂는 한 사람 시험).
    func inject(_ event: TetrisFrameChannelEvent) {
        onEvent?(event)
    }
}

// MARK: - 한 판

@MainActor
private final class TFSide {
    let user: String
    let store: TetrisDuelStore
    let channel: TFChannel
    let host: TFHost
    let rpcHost: String

    init(user: String, store: TetrisDuelStore, channel: TFChannel, host: TFHost, rpcHost: String) {
        self.user = user
        self.store = store
        self.channel = channel
        self.host = host
        self.rpcHost = rpcHost
    }

    /// 지금 보고 주기(장부가 없으면 1초 — 스토어가 `considerReport` 에 넣는 값과 같은 함수).
    func interval(at now: TimeInterval) -> TimeInterval {
        store.frameReportInterval(at: now, matchID: tfMatch)
    }
}

/// 한 판 = 서버 하나 + Realtime 흉내 하나 + 스토어 둘(또는 하나 — 상대는 서버 행으로만 산다).
@MainActor
private final class TFDuo {
    let label: String
    let server = TFServer()
    let relay = TFRelay()
    let clock = TFClock()
    private(set) var sides: [String: TFSide] = [:]
    /// 이 사람에게 가는 초인종을 버린다(ring 유실).
    var dropRings: Set<String> = []
    /// 이 사람에게 가는 초인종을 이만큼(단조 초) 늦게 준다 — 프레임이 공격 보고 커밋 · 초인종보다 먼저 닿는 흉내.
    var ringDelay: [String: TimeInterval] = [:]
    private var delayedRings: [(at: TimeInterval, user: String)] = []
    /// 한 사람 시험의 상대(서버 행으로만 사는 B)가 걸음마다 살아 있다고 적는가(끄면 DB last_seen 이 굳는다).
    var scriptedPeerAlive = true
    /// 재시작으로 버린 옛 스토어(끝에 함께 내린다).
    private var retired: [TFSide] = []
    /// 걸음마다 기록한 (시각, 보고 주기) — 사람별.
    private(set) var intervals: [String: [(at: TimeInterval, value: TimeInterval)]] = [:]

    var a: TFSide { sides[tfA]! }
    var b: TFSide { sides[tfB]! }

    init(_ label: String, framesA: Bool = true, framesB: Bool? = true) {
        self.label = label
        sides[tfA] = makeSide(tfA, frames: framesA)
        if let framesB { sides[tfB] = makeSide(tfB, frames: framesB) }
    }

    func makeSide(_ user: String, frames: Bool) -> TFSide {
        let rpcHost = "v0374-tf-\(label)-\(user.suffix(2))-\(UUID().uuidString.prefix(8))".lowercased()
        let server = self.server
        let tokensBox = TFTokensRef()
        GomokuStubProtocol.register(host: rpcHost) { rpc, body, _ in
            switch rpc {
            case "tetris_report":
                return server.report(body, from: user)
            case "tetris_state":
                tokensBox.tokens?.stateCalled()
                return server.stateCall(from: user)
            case "tetris_lobby":
                return server.lobby(for: user)
            default:
                return nil
            }
        }
        let service = SupabaseWorkService(projectURL: URL(string: "http://\(rpcHost)")!, anonKey: "anon-test-key",
                                          session: GomokuStubProtocol.session())
        let host = TFHost(service: service, userID: user)
        tokensBox.tokens = host.tokens
        TFRetention.hosts.append(host)
        let store = TetrisDuelStore(host: host)
        let clock = self.clock
        store.clock = { clock.wall }
        store.uptime = { clock.uptime }
        store.pollStepSeconds = 3_600
        store.gameLoopStepSeconds = 3_600
        store.framesEnabled = frames
        let channel = TFChannel(user: user)
        relay.attach(channel)
        store.makeFrameChannel = { _ in channel }
        store.frameJitter = { $0 }
        return TFSide(user: user, store: store, channel: channel, host: host, rpcHost: rpcHost)
    }

    /// 판 중 앱 재시작 — 그 사람의 스토어·소켓·호스트를 새로 세운다(옛 것은 그대로 버린다 — 프로세스가 죽은 것과 같다).
    func restart(_ user: String) -> TFSide {
        if let old = sides[user] { retired.append(old) }
        let side = makeSide(user, frames: sides[user]?.store.framesEnabled ?? true)
        sides[user] = side
        return side
    }

    var sideList: [TFSide] { [sides[tfA], sides[tfB]].compactMap { $0 } }

    /// 둘 다 판 상태를 받고(수락 직후) 창을 띄워 준비 → 카운트다운 → 판 시작까지.
    func start() async {
        for side in sideList {
            side.store.applyState(try! tfDecode(TetrisStatePayload.self, tfJSON(server.state(for: side.user))),
                                  receivedAt: clock.uptime)
        }
        for side in sideList {
            side.store.windowDidShow()
            await settle()
        }
        await run(4.0)
    }

    /// 한 걸음: 시계 → 두 판 루프 → 보고 왕복 → Realtime 배달 → 초인종 → 그 조회.
    func step(_ seconds: TimeInterval = 0.1, settling: Bool = true) async {
        clock.advance(seconds)
        server.setNow(clock.wallMs)
        if sides[tfB] == nil, scriptedPeerAlive {
            server.edit { $0.players[tfB]?.lastSeenMs = $0.nowMs }        // 한 사람 시험의 상대는 살아 있다
        }
        for side in sideList { side.store.tick() }
        if settling { await settle() }
        relay.pump(until: clock.uptime)
        for user in server.popRings() where !dropRings.contains(user) {
            if let wait = ringDelay[user], wait > 0 {
                delayedRings.append((clock.uptime + wait, user))
                continue
            }
            sides[user]?.store.handleSignal()
        }
        let due = delayedRings.filter { $0.at <= clock.uptime + 1e-9 }
        delayedRings.removeAll { $0.at <= clock.uptime + 1e-9 }
        for ring in due { sides[ring.user]?.store.handleSignal() }
        if settling { await settle() }
        for side in sideList {
            intervals[side.user, default: []].append((clock.uptime, side.interval(at: clock.uptime)))
        }
    }

    func run(_ seconds: TimeInterval, step: TimeInterval = 0.1) async {
        let count = Int((seconds / step).rounded())
        for _ in 0..<count { await self.step(step) }
    }

    /// 나가 있는 보고 · 초인종 조회가 다 돌아올 때까지.
    func settle() async {
        for _ in 0..<400 {
            var waited = false
            for side in sideList {
                if side.store.reportInFlight, let task = side.store.reportTask {
                    await task.value
                    waited = true
                }
                if let task = side.store.syncTask {
                    await task.value
                    waited = true
                }
            }
            if !waited { return }
        }
    }

    /// 지난 `seconds` 초 동안 서버가 받은 그 사람의 보고 수.
    func reports(_ user: String, inLast seconds: TimeInterval) -> Int {
        let from = clock.wallMs - seconds * 1000 + 1
        return server.reportTimes(of: user).filter { $0 >= from }.count
    }

    /// 지난 `seconds` 초 동안 기록한 보고 주기들.
    func intervalValues(_ user: String, inLast seconds: TimeInterval) -> [TimeInterval] {
        (intervals[user] ?? []).filter { $0.at > clock.uptime - seconds }.map(\.value)
    }

    /// 그 사람의 판을 **4줄 지우기 직전**으로 갈아 끼우고 하드드롭 — 공격 4(설계서 공격표).
    func attack(from user: String) {
        let store = sides[user]!.store
        guard let duel = store.duel, let startAt = duel.startAt else {
            Issue.record("공격할 판이 없다")
            return
        }
        let game = TetrisGame(seed: 4, board: TetrisGame.boardFixture(bottomRows: Array(repeating: "IIIIIIIII.", count: 4)),
                              active: TetrisGame.ActivePiece(piece: .i, rotation: .right, column: 7,
                                                             row: TetrisGame.spawnRow))
        var fixture = TetrisDuelSession(seed: 4, startedGame: game, startAt: startAt, simulated: duel.simulated)
        fixture.adoptServerSeq(duel.seq)
        store.duel = fixture
        store.hardDrop()
    }

    /// 두 판을 빈 판으로 갈아 끼운다(입력 없는 판은 판 시작 약 50초 뒤 둘 다 꼭대기에 닿는다 — 긴 시험이 자연 탑아웃으로 끝나지
    /// 않게). seq 는 잇는다. 공격을 주고받기 **전에만** 쓴다(받아들인 누계가 0 으로 돌아간다).
    func clearBoards() {
        for side in sideList {
            guard let duel = side.store.duel, let startAt = duel.startAt else { continue }
            let empty = TetrisGame(seed: UInt64(clamping: duel.seed), board: TetrisGame.emptyBoard(), active: nil,
                                   phase: .are(remaining: TetrisGame.areSeconds))
            var fresh = TetrisDuelSession(seed: duel.seed, startedGame: empty, startAt: startAt, simulated: duel.simulated)
            fresh.adoptServerSeq(duel.seq)
            side.store.duel = fresh
        }
    }

    /// 그 사람의 다음 보고가 나간 걸음까지(체크포인트 직후에 일을 꾸미려고).
    func stepUntilReport(from user: String, limit: TimeInterval = 4) async {
        let before = server.reportTimes(of: user).count
        var waited = 0.0
        while server.reportTimes(of: user).count == before, waited < limit {
            await step()
            waited += 0.1
        }
    }

    func tearDown() {
        for side in sideList + retired { side.store.reset() }
    }
}

/// 스텁 응답기(URL 스레드)가 호스트의 토큰 상자를 늦게 잡게 하는 상자.
private final class TFTokensRef: @unchecked Sendable {
    var tokens: TFTokens?
}

/// 한 사람 시험: 상대(B)는 서버 행으로만 산다(준비 · 프레임 능력 · 살아 있음). A 는 판을 시작하고 프레임 소켓에 join 했다.
@MainActor
private func tfSolo(_ label: String, configure: (TFDuo) -> Void = { _ in }) async -> TFDuo {
    let duo = TFDuo(label, framesB: nil)
    duo.server.edit {
        $0.players[tfB]?.ready = true
        $0.players[tfB]?.framesV = 1
        $0.players[tfB]?.lastSeenMs = tfWall0Ms
    }
    configure(duo)
    await duo.start()
    return duo
}

/// 서버 상태(그 사람 기준)를 그 스토어에 곧바로 넣는다.
@MainActor
private func tfApply(_ duo: TFDuo, _ user: String = tfA, edit: (inout [String: Any]) -> Void = { _ in }) {
    var state = duo.server.state(for: user)
    edit(&state)
    duo.sides[user]?.store.applyState(try! tfDecode(TetrisStatePayload.self, tfJSON(state)), receivedAt: duo.clock.uptime)
}

@MainActor
private func tfWait(_ resumes: Int = 2_000, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<resumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

// MARK: - 시험

@Suite("v0.3.74 테트리스 Broadcast — 스토어 · 프레임 소켓 · 유실 주입")
struct V0374TetrisFramesStoreTests {

    // MARK: 기준 — 양쪽 새 빌드 · 서버 켬

    @MainActor
    @Test("양쪽 새 빌드 · 서버 켬: 프레임이 양쪽에서 확인되면 보고가 3초로 준다 · 상대 판은 프레임이 그린다 · p_protocol 2 는 보고에만")
    func bothNewClientsSettleOnThreeSecondCheckpoints() async throws {
        // 없으면: 소켓만 열고 보고 주기를 안 바꾸거나(이득 0), 보고 아닌 요청까지 2를 실어 계약을 넓히거나, 프레임을 받고도
        // 화면에 안 그리는 배선이 초록으로 지나간다.
        let duo = TFDuo("steady")
        await duo.start()
        #expect(duo.a.store.phase == .playing && duo.b.store.phase == .playing)
        #expect(duo.a.channel.connects.map(\.topic) == [tfTopic] && duo.b.channel.connects.map(\.topic) == [tfTopic],
                "서버가 켠 판에서 판 전용 토픽 하나로 열지 않았다")
        #expect(duo.a.channel.connects.first?.apiKey == "anon-test-key" && duo.a.channel.connects.first?.token == "token-a1")
        await duo.run(8)
        // 결과: 지난 12초 보고가 3초 체크포인트 수준이다(1초면 12건). 그동안 상대 판은 걸음마다 병합 규칙 그대로다 —
        // 마지막 프레임의 s 가 DB seq 이상이면 그 프레임, 아니면(상대 보고가 막 나가 DB 가 한 장 앞섰다) DB 판.
        var frameShown = 0
        for _ in 0..<120 {
            await duo.step()
            let store = duo.a.store
            guard let last = store.frameLink?.lastFrame, let shown = store.match?.opponentBoard.cells else { continue }
            #expect(last.sender == tfB)
            if last.seq >= store.heldOpponentSeq {
                frameShown += 1
                #expect(shown == TetrisDuelBoard.decode(last.board), "프레임이 이기는 걸음에 상대 판이 그 프레임이 아니다")
            }
        }
        #expect(frameShown >= 60, "상대 판을 프레임이 그린 걸음이 \(frameShown)/120 — 체크포인트 응답이 되감는다")
        for user in [tfA, tfB] {
            let sent = duo.reports(user, inLast: 12)
            #expect((3...6).contains(sent), "\(user.suffix(2)): 12초에 보고 \(sent)건 — 3초 체크포인트가 아니다")
            #expect(duo.intervalValues(user, inLast: 12).allSatisfy { $0 == 3 }, "조용한 판에서 1초로 떨어졌다")
        }
        // p_protocol: 보고는 2, 다른 요청은 1 그대로(§11 — tetris_protocol() 은 1).
        #expect(duo.server.reports(of: tfA).allSatisfy { $0["p_protocol"] as? Int == 2 })
        let others = GomokuStubProtocol.calls(host: duo.a.rpcHost).filter { $0.rpc != "tetris_report" }
        #expect(!others.isEmpty && others.allSatisfy { $0.json["p_protocol"] as? Int == 1 },
                "보고 아닌 요청이 p_protocol 1 이 아니다: \(others.map(\.rpc))")
        // 보낸 프레임은 1초 간격이다(초당 4장 상한 · 조용한 판에서 공격 즉시 없음).
        #expect((18...23).contains(duo.a.channel.sentPayloads.count), "20초에 프레임 \(duo.a.channel.sentPayloads.count)장")
        duo.tearDown()
    }

    @MainActor
    @Test("새 ↔ 구 혼합 판(한쪽 p_protocol 1): 서버가 frames 를 안 켜고 양쪽 다 소켓을 안 열고 1초 보고다")
    func aMixedMatchWithAnOldClientStaysOnOneSecond() async throws {
        // 없으면: 서버 협상을 건너뛰고 새 클라가 혼자 소켓을 열거나 3초로 줄여, 구버전 상대의 화면이 3초마다 굳는다.
        let duo = TFDuo("mixed", framesA: true, framesB: false)
        await duo.start()
        await duo.run(12)
        #expect(duo.server.reports(of: tfA).allSatisfy { $0["p_protocol"] as? Int == 2 }, "새 클라가 2를 안 실었다")
        #expect(duo.server.reports(of: tfB).allSatisfy { $0["p_protocol"] as? Int == 1 }, "프레임 끈 클라가 2를 실었다")
        #expect(duo.a.channel.connects.isEmpty && duo.b.channel.connects.isEmpty, "한쪽이 못 하는 판에서 소켓을 열었다")
        #expect(duo.b.store.frameLink == nil, "프레임을 못 여는 기기가 장부를 세웠다")
        #expect(duo.a.store.frameLink?.topic == nil)
        for user in [tfA, tfB] {
            #expect(duo.reports(user, inLast: 10) >= 9, "\(user.suffix(2)): 혼합 판에서 1초 보고가 아니다")
        }
        duo.tearDown()
    }

    // MARK: 유실 주입(§16 표)

    @MainActor
    @Test("프레임 30% 무작위 유실: 표시는 판 끝까지 앞으로만 · 필요하면 1초로 내려온다 · 공격 누계는 양쪽이 같다")
    func thirtyPercentLossKeepsMovingAndAgreesOnAttacks() async throws {
        // 없으면: 유실 구간에서 3초로 버티다 상대 판이 굳거나, 공격 누계가 프레임 쪽으로 새어 두 사람의 대기열이 갈린다.
        let duo = TFDuo("loss30")
        duo.relay.dropRate = [tfA: 0.3, tfB: 0.3]
        await duo.start()
        await duo.run(8)
        duo.clearBoards()
        var seen: [Int] = []
        for second in 0..<30 {
            if second == 10 { duo.attack(from: tfB) }
            await duo.run(1)
            if let f = duo.a.store.frameLink?.lastFrame?.frame { seen.append(f) }
        }
        #expect(Set(seen).count >= 15, "30초 동안 받아들인 프레임이 \(Set(seen).count)장뿐이다 — 표시가 굳었다")
        #expect(seen == seen.sorted(), "받아들인 프레임 번호가 뒤로 갔다")
        #expect((duo.relay.droppedFrames[tfA] ?? 0) >= 5 && (duo.relay.droppedFrames[tfB] ?? 0) >= 5,
                "전제: 유실이 실제로 일어났다")
        #expect(duo.intervalValues(tfA, inLast: 30).contains(1) || duo.intervalValues(tfB, inLast: 30).contains(1),
                "유실 구간에서 1초로 한 번도 안 내려왔다")
        // 공격: 서버 누계 = 받는 쪽 DB 누계 = 받아들인 누계 = 받는 쪽이 서버에 보고한 누계.
        #expect(duo.server.player(tfB).sent == 4)
        #expect(duo.a.store.opponentAttackTotal == 4 && duo.a.store.duel?.garbageApplied == 4)
        #expect(duo.server.player(tfA).applied == 4, "받는 쪽 보고의 garbage_applied 가 서버 누계와 다르다")
        #expect(duo.server.snapshot { $0.status } == "active" && duo.server.snapshot { $0.endReason } == nil,
                "유실 판이 끝났다(\(duo.server.snapshot { $0.endReason ?? "-" }))")
        duo.tearDown()
    }

    @MainActor
    @Test("한쪽 방향 프레임 전부 유실: 양쪽 다 1초 보고다(조건 3·4 — 상대가 내 프레임을 못 듣는다)")
    func oneWayLossPutsBothSidesOnOneSecond() async throws {
        // 없으면(조건 4 가 없으면): A 는 B 의 프레임을 잘 받으니 3초로 줄이는데 B 는 A 를 못 봐 A 의 판이 3초마다 굳는다.
        let duo = TFDuo("oneway")
        duo.relay.dropRate = [tfA: 1.0]
        await duo.start()
        await duo.run(16)
        #expect((duo.relay.deliveredFrames[tfA]?.count ?? 0) >= 5, "전제: A 는 B 의 프레임을 받는다")
        #expect(duo.a.store.frameLink?.conditions(at: duo.clock.uptime).opponentHearsMe == false,
                "B 의 h 가 A 를 들었다고 말한다")
        for user in [tfA, tfB] {
            #expect(duo.intervalValues(user, inLast: 10).allSatisfy { $0 == 1 }, "\(user.suffix(2)) 가 3초로 줄였다")
            #expect(duo.reports(user, inLast: 10) >= 9, "\(user.suffix(2)): 10초에 보고 \(duo.reports(user, inLast: 10))건")
        }
        duo.tearDown()
    }

    @MainActor
    @Test("프레임 2초 지연 · 뒤집힘: 받아들인 프레임은 앞으로만 가고 화면은 그 프레임이다")
    func delayedAndReorderedFramesNeverMoveTheDisplayBack() async throws {
        // 없으면: 늦게 닿은 옛 프레임이 새 판을 덮어 상대 판이 한 박자 뒤로 튄다.
        let duo = TFDuo("reorder")
        duo.relay.delay = [tfB: 2.0]
        duo.relay.spread = [tfB: 1.6]
        await duo.start()
        var accepted: [Int] = []
        for _ in 0..<200 {
            await duo.step()
            guard let frame = duo.a.store.frameLink?.lastFrame else { continue }
            if accepted.last != frame.frame { accepted.append(frame.frame) }
            if frame.seq >= duo.a.store.heldOpponentSeq {
                #expect(duo.a.store.match?.opponentBoard.cells == TetrisDuelBoard.decode(frame.board),
                        "받아들인 프레임이 화면에 없다")
            }
        }
        #expect(duo.relay.inversions(at: tfA) >= 1, "전제: 실제로 뒤집혀 닿은 프레임이 있다")
        #expect(accepted == accepted.sorted() && accepted.count >= 8, "받아들인 프레임이 뒤로 갔다: \(accepted)")
        duo.tearDown()
    }

    @MainActor
    @Test("ring 전부 유실: 프레임 g 힌트로 공격이 약 2초 안에 대기열로 · tetris_state 는 그 값에 한 번")
    func lostRingsAreRecoveredByTheFrameHint() async throws {
        // 없으면(힌트가 없으면): ring 이 사라진 공격은 다음 3초 체크포인트까지 안 들어온다 · (힌트가 매초면) state 가 쌓인다.
        let duo = TFDuo("ringloss")
        duo.dropRings = [tfA]
        await duo.start()
        await duo.run(8)
        await duo.stepUntilReport(from: tfA)         // A 가 막 체크포인트를 냈다 — 다음 체크포인트는 약 3초 뒤
        let statesBefore = duo.server.stateCalls(of: tfA)
        let attackAt = duo.clock.uptime
        duo.attack(from: tfB)
        var absorbedAt: TimeInterval?
        for _ in 0..<40 {
            await duo.step()
            if absorbedAt == nil, duo.a.store.duel?.garbageApplied == 4 { absorbedAt = duo.clock.uptime }
        }
        let delay = try #require(absorbedAt.map { $0 - attackAt }, "4초 안에 공격이 안 들어왔다")
        #expect(delay <= 2.2, "ring 유실 공격이 \(delay)초 뒤에야 들어왔다")
        #expect(duo.server.stateCalls(of: tfA) - statesBefore == 1, "힌트 조회가 \(duo.server.stateCalls(of: tfA) - statesBefore)번")
        await duo.run(6)
        #expect(duo.server.stateCalls(of: tfA) - statesBefore == 1, "같은 g 로 힌트 조회가 또 나갔다")
        duo.tearDown()
    }

    @MainActor
    @Test("ring 이 프레임보다 늦게 닿는 정상 판: 공격 한 번에 tetris_state 는 1회(ring 몫) — 힌트가 1초를 기다려 겹치지 않는다")
    func aLateRingIsNotDoubledByTheHint() async throws {
        // 없으면(힌트 1초 대기가 없으면 — 11-03 뮤턴트 HW 는 순수 장부 시험만 잡았다): 프레임이 공격 보고 커밋 · 초인종보다 먼저 닿을 때마다
        // 힌트 조회가 곧바로 한 번, 뒤이은 ring 이 또 한 번 — 정상 판에서 공격마다 tetris_state 가 두 배가 된다(명세 §6).
        let duo = TFDuo("latering")
        duo.ringDelay = [tfA: 0.5]
        await duo.start()
        await duo.run(8)
        await duo.stepUntilReport(from: tfA)         // A 가 막 체크포인트를 냈다 — 다음 응답은 약 3초 뒤라 그 사이 DB 누계는 ring 만 가져온다
        let statesBefore = duo.server.stateCalls(of: tfA)
        let attackAt = duo.clock.uptime
        duo.attack(from: tfB)
        var absorbedAt: TimeInterval?
        var frameFirst = false
        for _ in 0..<30 {
            await duo.step()
            if !frameFirst, duo.a.store.frameLink?.lastFrame?.attackSent == 4, duo.a.store.opponentAttackTotal == 0 { frameFirst = true }
            if absorbedAt == nil, duo.a.store.duel?.garbageApplied == 4 { absorbedAt = duo.clock.uptime }
        }
        #expect(frameFirst, "전제: 공격을 실은 프레임이 DB 누계(초인종 조회)보다 먼저 닿았다")
        let delay = try #require(absorbedAt.map { $0 - attackAt }, "3초 안에 공격이 안 들어왔다")
        #expect(delay <= 0.8, "늦은 ring(0.5초)이 가져와야 할 공격이 \(delay)초 뒤에야 들어왔다")
        #expect(duo.server.stateCalls(of: tfA) - statesBefore == 1,
                "공격 한 번에 tetris_state 가 \(duo.server.stateCalls(of: tfA) - statesBefore)번 — 힌트가 ring 조회와 겹쳤다")
        duo.tearDown()
    }

    @MainActor
    @Test("프레임 g 가 DB 보다 영구히 큼(위조): 그 값에 tetris_state 한 번 · 대기열은 그대로 · 판 끝까지 늘지 않는다")
    func aForgedAttackTotalAsksOnceAndNeverQueuesGarbage() async throws {
        // 없으면: 위조 프레임이 곧 공격이 되거나(D4 위반), '1초에 한 번' 힌트가 판 끝까지 매초 state 를 친다.
        let duo = TFDuo("forged")
        await duo.start()
        await duo.run(8)
        let statesBefore = duo.server.stateCalls(of: tfA)
        duo.relay.tamper[tfB] = { payload in
            var forged = payload
            forged["g"] = 50
            return forged
        }
        await duo.run(15)
        #expect(duo.server.stateCalls(of: tfA) - statesBefore == 1, "위조 g 에 state 를 \(duo.server.stateCalls(of: tfA) - statesBefore)번")
        #expect(duo.a.store.opponentAttackTotal == 0 && duo.a.store.duel?.garbageApplied == 0
                && duo.a.store.myStats?.pendingGarbage == 0, "프레임 g 가 공격 대기열로 들어갔다")
        #expect(duo.a.store.frameLink?.lastFrame?.attackSent == 50, "전제: 위조 프레임을 받았다")
        // g 를 프레임마다 1씩 올리는 위조(11-03 검토 F1 — '같은 g 에 한 번' 은 값이 늘 새로워 못 막았다: 15초에 13번).
        // 앞 힌트(50)가 풀리지 않았으니(DB 0) 새 값으로도 더 묻지 않는다.
        final class Counter { var value = 50 }
        let counter = Counter()
        duo.relay.tamper[tfB] = { payload in
            var forged = payload
            counter.value += 1
            forged["g"] = counter.value
            return forged
        }
        await duo.run(15)
        #expect(counter.value >= 60, "전제: 위조 g 가 프레임마다 올랐다(\(counter.value))")
        #expect((duo.a.store.frameLink?.lastFrame?.attackSent ?? 0) > 50, "전제: 올라간 위조 프레임을 받았다")
        #expect(duo.server.stateCalls(of: tfA) - statesBefore == 1,
                "프레임마다 올리는 위조 g 에 state 를 \(duo.server.stateCalls(of: tfA) - statesBefore)번")
        duo.tearDown()
    }

    @MainActor
    @Test("ring + 프레임 유실: 공격은 다음 체크포인트 또는 1초 보고 응답으로 3초 안에 들어온다")
    func ringAndFrameLossStillDeliverTheAttackByAReport() async throws {
        // 없으면: 프레임이 끊긴 뒤에도 3초 넘게 버티거나, 응답의 누계 흡수를 프레임 경로가 가려 공격이 안 들어온다.
        let duo = TFDuo("ringframe")
        duo.dropRings = [tfA]
        await duo.start()
        await duo.run(8)
        await duo.stepUntilReport(from: tfA)
        duo.relay.dropRate = [tfB: 1.0]
        let statesBefore = duo.server.stateCalls(of: tfA)
        let attackAt = duo.clock.uptime
        duo.attack(from: tfB)
        var absorbedAt: TimeInterval?
        for _ in 0..<50 {
            await duo.step()
            if absorbedAt == nil, duo.a.store.duel?.garbageApplied == 4 { absorbedAt = duo.clock.uptime }
        }
        let delay = try #require(absorbedAt.map { $0 - attackAt }, "5초 안에 공격이 안 들어왔다")
        #expect(delay <= 3.2, "ring·프레임 유실 공격이 \(delay)초 뒤에야 들어왔다")
        #expect(duo.server.stateCalls(of: tfA) == statesBefore, "전제: 힌트·초인종 없이 보고 응답으로 들어왔다")
        duo.tearDown()
    }

    @MainActor
    @Test("공격 보고 실패 1회: 실패 streak 가 곧바로 1초로 내려 다음 보고가 1초 안에 누계를 싣는다")
    func aFailedAttackReportIsResentWithinOneSecond() async throws {
        // 없으면(조건 5 배선이 없으면): 재시도는 '공격' 사유로 안 잡혀(makeReport 가 먼저 적었다) 3초 체크포인트까지 공격이 안 간다.
        let duo = TFDuo("failonce")
        await duo.start()
        await duo.run(8)
        #expect(duo.b.interval(at: duo.clock.uptime) == 3, "전제: 3초 체크포인트 중이다")
        duo.server.edit { $0.failNextReports[tfB] = 1 }
        let failedAt = duo.clock.wallMs
        duo.attack(from: tfB)
        var landedAt: Double?
        for _ in 0..<30 {
            await duo.step()
            if landedAt == nil, duo.server.player(tfB).sent == 4 { landedAt = duo.clock.wallMs }
        }
        let delay = try #require(landedAt.map { ($0 - failedAt) / 1000 }, "3초 안에 공격 누계가 서버에 안 닿았다")
        #expect(delay <= 1.15, "실패한 공격 보고의 누계가 \(delay)초 뒤에야 닿았다")
        duo.tearDown()
    }

    @MainActor
    @Test("보고 멎음(3초 체크포인트 중): 3초마다 버리고 다시 낸다 — 15초 안 4회 이상 · 그동안 프레임은 보고에 안 묶여 계속 나간다")
    func aStalledReportIsAbandonedAndFramesKeepFlowing() async throws {
        // 없으면: 멎은 보고 하나가 체크포인트 주기(3초)에 멎음 3초를 더해 15초 안 시도가 줄거나, 프레임이 보고를 기다려 같이 멎는다.
        let duo = TFDuo("stall")
        await duo.start()
        await duo.run(8)
        let base = duo.server.reportTimes(of: tfB).count
        let framesBefore = duo.b.channel.sentPayloads.count
        duo.server.edit { $0.reportDelay[tfB] = 1.0 }
        var inFlightSends = 0
        var stalledIntervals: [TimeInterval] = []
        for _ in 1...15 {
            duo.clock.advance(1.0)
            duo.server.setNow(duo.clock.wallMs)
            let sentBefore = duo.b.channel.sentPayloads.count
            let wasInFlight = duo.b.store.reportInFlight
            duo.a.store.tick()
            duo.b.store.tick()
            if wasInFlight, duo.b.channel.sentPayloads.count > sentBefore { inFlightSends += 1 }
            if duo.a.store.reportInFlight, let task = duo.a.store.reportTask { await task.value }
            duo.relay.pump(until: duo.clock.uptime)
            stalledIntervals.append(duo.b.interval(at: duo.clock.uptime))
            try? await Task.sleep(for: .milliseconds(10))
        }
        // 마지막 걸음에 버리고 다시 낸 보고는 URL 스텁에 비동기로 닿는다 — 서버 기록 수가 멈출 때까지 기다린 뒤 센다(부하에서 1건 덜
        // 세어 하한 여유 1이 무너지지 않게 — 11-03 검토 F6. 단언은 그대로다).
        var recorded = -1
        for _ in 0..<40 {
            let now = duo.server.reportTimes(of: tfB).count
            if now == recorded { break }
            recorded = now
            try? await Task.sleep(for: .milliseconds(30))
        }
        let attempts = duo.server.reportTimes(of: tfB).count - base
        #expect(attempts >= 4, "멎은 동안 15초에 보고를 \(attempts)번만 시도했다 — 침묵 판정(15초)에 걸린다")
        #expect(attempts <= 7, "멎은 보고를 3초도 안 기다리고 버렸다(\(attempts)건)")
        #expect(duo.b.channel.sentPayloads.count - framesBefore >= 13, "멎은 동안 프레임이 멈췄다")
        #expect(inFlightSends >= 5, "보고가 나가 있는 동안 프레임을 안 보냈다(\(inFlightSends)번)")
        // 조건 5: 멎어서 버린 보고도 실패로 센다 — 첫 버림 뒤로는 1초다(돌아와도 프레임 3장을 다시 모아야 3초).
        #expect(stalledIntervals.suffix(8).allSatisfy { $0 == 1 }, "멎은 보고를 버리고도 3초로 남았다: \(stalledIntervals)")
        #expect(duo.b.store.connectionTrouble, "멎음이 두 번 이어졌는데 '연결 확인 중' 이 안 떴다")
        duo.server.edit { $0.reportDelay[tfB] = 0 }
        try? await Task.sleep(for: .milliseconds(1_200))
        await duo.run(4)
        #expect(duo.b.store.reportFailureStreak == 0 && !duo.b.store.connectionTrouble)
        duo.tearDown()
    }

    @MainActor
    @Test("join 거절(RLS): 재시도 없이 판 끝까지 1초 · 같은 소켓을 다시 안 연다")
    func aRejectedJoinIsNeverRetried() async throws {
        // 없으면: 초인종 링처럼 cap 간격으로 계속 다시 붙어 판 끝까지 인가 검사(풀 2)를 두드린다.
        let duo = TFDuo("rls")
        duo.relay.joinPolicy[tfA] = .reject("Unauthorized: You do not have permissions to read from this Channel topic: \(tfTopic)")
        await duo.start()
        await duo.run(20)
        #expect(duo.a.channel.connects.count == 1, "거절된 조인을 \(duo.a.channel.connects.count)번 열었다")
        #expect(duo.a.store.frameLink?.socket == .stopped(.unauthorized))
        #expect(!duo.a.store.frameSocketOpen)
        for user in [tfA, tfB] {
            #expect(duo.reports(user, inLast: 10) >= 9, "\(user.suffix(2)) 가 거절된 판에서 1초가 아니다")
        }
        duo.tearDown()
    }

    @MainActor
    @Test("join 성공 + 쓰기만 거절: 양쪽 1초 · 증거 없는 10초 뒤 소켓을 닫고 재시도 3회로 끝낸다")
    func writeDeniedFramesCloseTheSocketAfterTenSeconds() async throws {
        // 없으면: ack:false 라 보내는 쪽은 실패를 모른다 — 판 끝까지 듣는 이 없는 소켓에 쓰고, DB 정지 중엔 인가를 두드린다.
        let duo = TFDuo("writedeny")
        duo.relay.writeDenied = [tfA, tfB]
        await duo.start()
        let matchStart = try #require(duo.a.store.duel?.startAt)
        var closedAt: TimeInterval?
        for _ in 0..<120 {
            await duo.step()
            if closedAt == nil, duo.a.channel.disconnects > 0 { closedAt = duo.clock.uptime }
        }
        let elapsed = try #require(closedAt.map { $0 - matchStart }, "판 시작 뒤 13초 안에 소켓을 안 닫았다")
        #expect((9.95...10.25).contains(elapsed), "판 시작 뒤 \(elapsed)초에 닫았다(10초여야 한다)")
        #expect(duo.a.channel.connects.count == 2, "닫은 뒤 재시도를 안 했다")
        for user in [tfA, tfB] {
            #expect(duo.reports(user, inLast: 10) >= 9, "\(user.suffix(2)): 쓰기 거절 판에서 1초가 아니다")
        }
        duo.clearBoards()
        await duo.run(48, step: 0.2)
        #expect(duo.server.snapshot { $0.status } == "active", "전제: 판이 아직 돈다")
        #expect(duo.a.channel.connects.count == 4, "판당 재시도 3회가 아니다: \(duo.a.channel.connects.count)")
        #expect(duo.a.store.frameLink?.socket == .stopped(.exhausted) && !duo.a.store.frameSocketOpen)
        duo.tearDown()
    }

    @MainActor
    @Test("system 오류 + phx_close(\"Too many messages per second\"): 그 판은 다시 잇지 않고 양쪽 1초")
    func aRateLimitCloseIsNeverRejoined() async throws {
        // 없으면: 프로젝트 전체 한도에 닿은 채널을 다시 붙여 초인종까지 같이 닫히게 한다(§15).
        let duo = TFDuo("ratelimit")
        await duo.start()
        await duo.run(8)
        duo.relay.serverSends(tfA, [
            ["topic": "realtime:\(tfTopic)", "event": "system", "ref": NSNull(),
             "payload": ["status": "error", "message": "Too many messages per second", "extension": "system",
                         "channel": tfTopic]],
            ["topic": "realtime:\(tfTopic)", "event": "phx_close", "ref": NSNull(), "payload": [String: Any]()],
        ])
        await duo.run(15)
        #expect(duo.a.channel.connects.count == 1, "한도 초과로 닫힌 채널을 다시 열었다")
        #expect(duo.a.store.frameLink?.socket == .stopped(.rateLimited))
        #expect(duo.a.channel.disconnects == 1, "닫힘을 두 번 셌다(system 뒤 phx_close)")
        for user in [tfA, tfB] {
            #expect(duo.intervalValues(user, inLast: 10).allSatisfy { $0 == 1 }, "\(user.suffix(2)) 가 1초로 안 돌아왔다")
        }
        duo.tearDown()
    }

    @MainActor
    @Test("서버 스위치 끔: frames null 응답 뒤 소켓을 닫고 1초 · 다시 켜면 새로 연다(롤백 1단계)")
    func theServerSwitchClosesAndReopens() async throws {
        // 없으면: 스위치를 내려도 클라가 들고 있던 토픽으로 계속 보내 롤백 1단계(앱 업데이트 없는 되돌리기)가 안 먹는다.
        let duo = TFDuo("switch")
        await duo.start()
        await duo.run(8)
        duo.server.edit { $0.framesSwitch = false }
        await duo.run(3.3)
        for side in [duo.a, duo.b] {
            #expect(side.channel.disconnects == 1 && !side.store.frameSocketOpen, "\(side.user.suffix(2)) 가 소켓을 안 닫았다")
            #expect(side.interval(at: duo.clock.uptime) == 1)
        }
        await duo.run(8)
        #expect(duo.reports(tfA, inLast: 8) >= 7, "스위치를 끈 판에서 1초가 아니다")
        duo.server.edit { $0.framesSwitch = true }
        await duo.run(10)
        #expect(duo.a.channel.connects.count == 2 && duo.b.channel.connects.count == 2, "다시 켠 스위치에서 새로 안 열었다")
        #expect(duo.a.interval(at: duo.clock.uptime) == 3 && duo.b.interval(at: duo.clock.uptime) == 3)
        duo.tearDown()
    }

    @MainActor
    @Test("관전자 등장 · 이탈: 붙으면 그 판의 대국자는 1초 · 떠나면 프레임 3장 뒤 3초")
    func watchersPutThePlayersBackOnOneSecond() async throws {
        // 없으면(조건 6 이 없으면): 관전 화면(DB 를 2초마다 읽는다)이 3초마다 굳은 판을 본다.
        let duo = TFDuo("watch")
        await duo.start()
        await duo.run(8)
        duo.server.edit { $0.watchers = 1 }
        await duo.run(3.3)
        #expect(duo.a.interval(at: duo.clock.uptime) == 1 && duo.b.interval(at: duo.clock.uptime) == 1,
                "관전자가 붙었는데 3초로 버틴다")
        await duo.run(8)
        #expect(duo.reports(tfA, inLast: 8) >= 7 && duo.reports(tfB, inLast: 8) >= 7)
        #expect(duo.a.channel.disconnects == 0, "관전자 때문에 소켓을 닫았다(닫을 까닭이 없다)")
        duo.server.edit { $0.watchers = 0 }
        await duo.run(6)
        #expect(duo.a.interval(at: duo.clock.uptime) == 3 && duo.b.interval(at: duo.clock.uptime) == 3,
                "관전자가 떠났는데 3초로 안 돌아왔다")
        duo.tearDown()
    }

    @MainActor
    @Test("채널 끊김: 곧바로 1초 · 상대도 2.5초 안에 1초 · 재시도로 다시 붙어 3초로 돌아온다")
    func aLostChannelFallsBackAndRecovers() async throws {
        // 없으면: 끊긴 소켓을 모른 채 3초로 남아 상대 판이 3초씩 굳고, 다시 붙지 않아 판 끝까지 이득이 없다.
        let duo = TFDuo("channelloss")
        await duo.start()
        await duo.run(8)
        // A 의 망이 3초 가까이 끊긴다 — 소켓이 닫히고, 그사이 다시 여는 족족 닫힌다.
        duo.relay.offline = [tfA]
        duo.relay.dropConnection(tfA)
        duo.relay.pump(until: duo.clock.uptime)
        #expect(duo.a.interval(at: duo.clock.uptime) == 1, "끊긴 쪽이 곧바로 1초가 아니다")
        #expect(!duo.a.store.frameSocketOpen && duo.a.channel.disconnects == 1)
        await duo.run(2.6)
        #expect(duo.b.interval(at: duo.clock.uptime) == 1, "상대가 2.5초 안에 1초로 안 내려왔다")
        #expect(duo.reports(tfA, inLast: 2.6) >= 2, "끊긴 쪽이 1초 보고를 안 냈다")
        duo.relay.offline = []
        await duo.run(1.0)
        #expect(duo.a.channel.connects.count == 3, "재시도(1초 · 2초)로 다시 안 붙었다: \(duo.a.channel.connects.count)")
        #expect(duo.a.channel.joined)
        await duo.run(8)
        #expect(duo.a.interval(at: duo.clock.uptime) == 3 && duo.b.interval(at: duo.clock.uptime) == 3,
                "다시 붙은 뒤 3초로 안 돌아왔다")
        duo.tearDown()
    }

    @MainActor
    @Test("판 중 앱 재시작: 서버 행에서 재개 · 공격 이중 적용 없음 · 새 프레임(벽시계 f)을 상대가 곧바로 받는다")
    func restartingMidMatchResumesAndRejoins() async throws {
        // 없으면: 재개한 프로세스의 s 가 옛 프레임 이하라 새 프레임이 버려지거나, 받아들인 공격이 한 번 더 쌓인다.
        let duo = TFDuo("restart")
        await duo.start()
        await duo.run(8)
        duo.attack(from: tfB)
        await duo.run(5)
        #expect(duo.a.store.duel?.garbageApplied == 4 && duo.server.player(tfA).applied == 4, "전제: A 가 공격 4를 받아 보고했다")
        let row = duo.server.player(tfA)
        let restartWallMs = Int(duo.clock.wallMs)
        let fresh = duo.restart(tfA)
        tfApply(duo)
        fresh.store.tick()
        #expect(fresh.store.duel?.garbageApplied == 4, "재개가 받아들인 누계를 0 에서 다시 셌다")
        #expect(fresh.store.duel?.game.pendingGarbageLines == row.pending,
                "받아들인 공격이 다시 들어왔다(\(fresh.store.duel?.game.pendingGarbageLines ?? -1)줄, 서버 \(row.pending)줄)")
        #expect(fresh.channel.connects.count == 1, "재개한 판에서 소켓을 안 열었다")
        await duo.run(8)
        let heardByB = try #require(duo.b.store.frameLink?.lastFrame)
        #expect(heardByB.frame >= restartWallMs, "상대가 재개한 프로세스의 프레임을 안 받았다(f=\(heardByB.frame))")
        #expect(fresh.store.frameLink?.lastFrame?.sender == tfB, "재개한 쪽이 상대 프레임을 못 받는다")
        #expect(duo.server.player(tfA).applied == 4, "재개 뒤 보고의 garbage_applied 가 달라졌다")
        duo.tearDown()
    }

    // MARK: 승패 · 정산

    @MainActor
    @Test("루비 · 승패 · 정산은 프레임과 무관하다 — 같은 판을 프레임 켬 · 끔으로 두 번 돌려 결과가 같다 · 끝난 응답에서 소켓이 닫힌다")
    func settlementDoesNotDependOnFrames() async throws {
        // 없으면: 프레임 경로가 승패·루비에 새어(상대 판이 꼭대기로 보인다 → 이겼다 등) 켬·끔 결과가 갈려도 모른다.
        struct Outcome: Equatable {
            var aOutcome: TetrisDuelOutcome?
            var bOutcome: TetrisDuelOutcome?
            var aDelta: Int?
            var bDelta: Int?
            var reason: TetrisDuelEndReason?
            var rubies: [String: Int]
            var attack: Int
        }
        func play(frames: Bool) async -> (Outcome, TFDuo) {
            let duo = TFDuo("ruby-\(frames)", framesA: frames, framesB: frames)
            await duo.start()
            await duo.run(8)
            duo.attack(from: tfB)
            await duo.run(4)
            var guardSteps = 0
            while duo.a.store.match?.isFinished != true || duo.b.store.match?.isFinished != true, guardSteps < 900 {
                duo.a.store.hardDrop()
                await duo.step()
                guardSteps += 1
            }
            await duo.run(2)
            let outcome = Outcome(aOutcome: duo.a.store.match?.outcome, bOutcome: duo.b.store.match?.outcome,
                                  aDelta: duo.a.store.match?.rubyDelta, bDelta: duo.b.store.match?.rubyDelta,
                                  reason: duo.a.store.match?.endReason, rubies: duo.server.snapshot { $0.rubies },
                                  attack: duo.server.player(tfB).sent)
            return (outcome, duo)
        }
        let (withFrames, on) = await play(frames: true)
        let (withoutFrames, off) = await play(frames: false)
        #expect(withFrames == withoutFrames, "프레임 켬·끔에서 결과가 갈렸다: \(withFrames) vs \(withoutFrames)")
        #expect(withFrames.aOutcome == .lost && withFrames.bOutcome == .won && withFrames.reason == .topout)
        #expect(withFrames.aDelta == -3 && withFrames.bDelta == 3 && withFrames.rubies == [tfA: 97, tfB: 103])
        // ★ 기준선: 두 판은 정말 다른 길로 돌았다(켬 = 소켓·3초, 끔 = 소켓 0).
        #expect(on.a.channel.connects.count == 1 && off.a.channel.connects.isEmpty)
        // 끝난 응답 가지에서 곧바로 닫혔다(`discardDuel` 없이 — 구동기는 결과 화면을 위해 남는다).
        for side in [on.a, on.b] {
            #expect(side.channel.disconnects == 1 && !side.store.frameSocketOpen, "\(side.user.suffix(2)): 끝난 판의 소켓이 남았다")
            #expect(side.store.duel != nil && side.store.frameLink?.finished == true)
        }
        await on.run(3)
        #expect(on.a.channel.connects.count == 1 && on.b.channel.connects.count == 1, "끝난 판에서 소켓을 다시 열었다")
        on.tearDown()
        off.tearDown()
    }

    // MARK: 병합 · 장부 분리 · 상대 연결 표시 (한 사람)

    @MainActor
    @Test("병합: 프레임 s ≥ DB seq 면 판·줄·대기 줄은 프레임 · DB seq 가 크면 DB · 끝난 판도 같은 규칙 · 끝난 뒤 프레임은 버림 · 준비·탑아웃·승패는 DB")
    func theCheckpointMergeKeepsTheFrameBoard() async throws {
        // 없으면: 체크포인트 응답(3초 옛 판)이 매번 상대 판을 되감거나, 끝난 판 결과 화면의 상대 줄 수가 줄어든다.
        let duo = await tfSolo("merge")
        let store = duo.a.store
        #expect(store.frameSocketOpen && duo.a.channel.joined, "전제: 프레임 소켓에 붙었다")
        duo.server.edit { $0.players[tfB]?.seq = 5; $0.players[tfB]?.board = tfBoardY; $0.players[tfB]?.lines = 1 }
        await store.refreshMatch(id: tfMatch)
        #expect(store.match?.opponentBoard.cells == TetrisDuelBoard.decode(tfBoardY))
        let base = Int(duo.clock.wallMs)
        duo.a.channel.inject(.frame(tfFrame(s: 5, f: base, board: tfBoardX, lines: 3, g: 0, p: 2)))
        #expect(store.match?.opponentBoard.cells == TetrisDuelBoard.decode(tfBoardX) && store.match?.opponentBoard.lines == 3)
        #expect(store.match?.opponentBoard.pending == 2)
        // ① 같은 seq 의 DB 응답(체크포인트 — 옛 판)은 되감지 않는다.
        await store.refreshMatch(id: tfMatch)
        #expect(store.match?.opponentBoard.cells == TetrisDuelBoard.decode(tfBoardX), "체크포인트 응답이 상대 판을 되감았다")
        #expect(store.match?.opponentBoard.lines == 3)
        // ② DB seq 가 더 크면 DB 가 이긴다.
        duo.server.edit { $0.players[tfB]?.seq = 6; $0.players[tfB]?.board = tfBoardZ; $0.players[tfB]?.lines = 4 }
        await store.refreshMatch(id: tfMatch)
        #expect(store.match?.opponentBoard.cells == TetrisDuelBoard.decode(tfBoardZ) && store.match?.opponentBoard.lines == 4)
        // ②′ 그 뒤 닿은 **옛 보고 시점의** 프레임(f 는 더 크지만 s 5 < DB 6)은 장부엔 들어가도 화면을 되감지 않는다.
        duo.a.channel.inject(.frame(tfFrame(s: 5, f: base + 1, board: tfBoardX, lines: 3, g: 0)))
        #expect(store.frameLink?.lastFrame?.frame == base + 1, "전제: 장부는 그 프레임을 받았다(f 가 더 크다)")
        #expect(store.match?.opponentBoard.cells == TetrisDuelBoard.decode(tfBoardZ) && store.match?.opponentBoard.lines == 4,
                "DB 보다 옛 보고 시점의 프레임이 상대 판을 되감았다")
        // ③ 그 seq 의 프레임이 오면 다시 프레임. 판 중의 보낸 공격(표시용)은 두 값의 max 다(DB 0 · 프레임 9).
        duo.a.channel.inject(.frame(tfFrame(s: 6, f: base + 2, board: tfBoardW, lines: 5, g: 9)))
        #expect(store.match?.opponentBoard.cells == TetrisDuelBoard.decode(tfBoardW))
        #expect(store.match?.opponentBoard.attackSent == 9, "전제: 판 중엔 프레임의 공격 수가 보인다")
        // ④ 끝난 판: 승패·탑아웃은 DB, 판·줄은 같은 규칙(승자는 끝난 뒤 보고를 안 낸다 — 마지막 프레임이 이긴다).
        duo.server.edit {
            $0.players[tfB]?.toppedOut = true
            $0.players[tfB]?.ready = true
            $0.players[tfB]?.sent = 2
        }
        duo.server.finish(winner: tfA, reason: "topout")
        await store.refreshMatch(id: tfMatch)
        #expect(store.match?.isFinished == true && store.match?.outcome == .won && store.match?.endReason == .topout)
        // 끝난 판의 보낸 공격 수는 DB 행 그대로(정산 정본 — 11-03 검토 F5). 판 중 프레임이 올린 9 가 결과 화면에 남지 않는다.
        #expect(store.match?.opponentBoard.attackSent == 2, "끝난 판 결과의 공격 수가 DB 가 아니다(\(store.match?.opponentBoard.attackSent ?? -1))")
        #expect(store.match?.opponentBoard.toppedOut == true && store.match?.opponentBoard.ready == true, "탑아웃·준비가 DB 가 아니다")
        #expect(store.match?.opponentBoard.cells == TetrisDuelBoard.decode(tfBoardW) && store.match?.opponentBoard.lines == 5,
                "끝난 판 결과의 상대 판·줄이 옛 DB 로 줄었다")
        // ⑤ 끝난 뒤 닿은 프레임은 버린다.
        duo.a.channel.inject(.frame(tfFrame(s: 7, f: base + 3, board: tfBoardX, lines: 9)))
        #expect(store.match?.opponentBoard.cells == TetrisDuelBoard.decode(tfBoardW) && store.match?.opponentBoard.lines == 5,
                "끝난 판에 늦게 닿은 프레임이 결과를 바꿨다")
        duo.tearDown()
    }

    @MainActor
    @Test("heldOpponentSeq 는 프레임으로 안 오른다 — 프레임 수천 장 뒤에도 뒤처진 DB 응답의 공격 누계가 들어간다")
    func framesNeverRaiseTheHeldSequence() async throws {
        // 없으면(§4 ★): 프레임 번호로 그 값을 올리면 그 뒤의 DB 응답 전체가 '옛 스냅숏' 으로 버려져 공격·시작 시각이 사라진다.
        let duo = await tfSolo("held")
        let store = duo.a.store
        duo.server.edit { $0.players[tfB]?.seq = 5 }
        await store.refreshMatch(id: tfMatch)
        #expect(store.heldOpponentSeq == 5)
        let base = Int(duo.clock.wallMs)
        for index in 0..<3_000 {
            duo.a.channel.inject(.frame(tfFrame(s: 5 + index / 500, f: base + index, board: tfBoardX, lines: index / 100,
                                                g: 0)))
        }
        #expect(store.frameLink?.lastFrame?.frame == base + 2_999, "전제: 프레임 3000장을 받았다")
        #expect(store.heldOpponentSeq == 5 && store.opponentAttackTotal == 0, "프레임이 DB 장부를 올렸다")
        // ★ 기준선: DB 장부의 가드는 살아 있다 — 들고 있는 값보다 옛 응답은 버린다.
        var older = duo.server.state(for: tfA)
        var olderOpponent = duo.server.player(tfB)
        olderOpponent.seq = 4
        olderOpponent.sent = 9
        older["opponent"] = olderOpponent.json
        #expect(store.applyState(try tfDecode(TetrisStatePayload.self, tfJSON(older))) == .ignored)
        // 프레임(s 최대 10)보다 뒤처진 DB 응답(seq 6)의 공격 4 는 들어간다.
        duo.server.edit { $0.players[tfB]?.seq = 6; $0.players[tfB]?.sent = 4 }
        await store.refreshMatch(id: tfMatch)
        #expect(store.heldOpponentSeq == 6 && store.opponentAttackTotal == 4, "뒤처진 DB 응답의 공격 누계가 버려졌다")
        store.tick()
        #expect(store.duel?.garbageApplied == 4 && store.myStats?.pendingGarbage == 4)
        duo.tearDown()
    }

    @MainActor
    @Test("상대 연결 표시: 프레임이 오면 DB last_seen 이 5초 넘게 옛것이어도 안 뜬다 · 프레임과 DB 가 다 끊기면 뜬다")
    func opponentPresenceUsesFrameTimes() async throws {
        // 없으면: 3초 체크포인트의 옛 last_seen 으로 "상대 연결 확인 중" 이 깜빡이거나, 끊긴 상대를 프레임 기록이 가린다.
        // 상대는 처음부터 보고를 안 한다(DB last_seen 이 판 시작 전 시각에 굳어 있다 · 서버 침묵 판정은 끈다).
        let duo = await tfSolo("presence") {
            $0.scriptedPeerAlive = false
            $0.server.edit { $0.silenceJudge = false; $0.players[tfB]?.lastSeenMs = tfWall0Ms - 6_000 }
        }
        let store = duo.a.store
        await store.refreshMatch(id: tfMatch)
        #expect((store.opponentSilenceSeconds() ?? 0) >= 5.9, "전제: DB 로는 6초 넘게 조용하다")
        var f = Int(duo.clock.wallMs)
        for _ in 0..<6 {
            f += 1
            duo.a.channel.inject(.frame(tfFrame(s: 1, f: f)))
            await duo.run(1)
            await store.refreshMatch(id: tfMatch)
            #expect((store.opponentSilenceSeconds() ?? 99) < 5, "프레임이 오는데 옛 DB 시각으로 '연결 확인 중' 이 뜬다")
        }
        // 프레임도 끊긴다 — 5초 뒤 뜬다.
        await duo.run(5.2)
        #expect((store.opponentSilenceSeconds() ?? 0) >= 5, "프레임과 보고가 다 끊겼는데 '연결 확인 중' 이 안 뜬다")
        duo.tearDown()
    }

    @MainActor
    @Test("상대 연결 표시: 기기 시계가 뒤로 가도 끊긴 상대를 가리지 않는다 — 프레임 수신 시각은 단조 시계로 잰다")
    func opponentPresenceSurvivesABackwardClockStep() async throws {
        // 없으면(11-03 검토 F2): 프레임 수신 시각을 벽시계로 max 해 두면, 기기 시계가 60초 뒤로 간 뒤 그 시각이 앞날에 남아 프레임·보고가
        // 다 끊긴 상대에게 "상대 연결 확인 중" 이 60초 동안 안 뜬다(사본 프로브: DB 17초 옛것인데 침묵 0).
        let duo = await tfSolo("clockstep") {
            $0.scriptedPeerAlive = false
            $0.server.edit { $0.silenceJudge = false }
        }
        let store = duo.a.store
        var f = Int(duo.clock.wallMs)
        for _ in 0..<4 {
            f += 1
            duo.a.channel.inject(.frame(tfFrame(s: 1, f: f)))
            await duo.run(1)
        }
        await store.refreshMatch(id: tfMatch)
        #expect((store.opponentSilenceSeconds() ?? 99) < 2, "전제: 프레임이 오는 동안은 조용하지 않다")
        #expect((store.opponentLastSeenAt.map { duo.clock.wall.timeIntervalSince($0) } ?? 0) >= 7, "전제: DB 로는 7초 넘게 조용하다")
        // 기기 시계만 60초 뒤로(서버 시계 · 단조 시계는 그대로) — 그 뒤로 프레임도 보고도 없다.
        let clock = duo.clock
        store.clock = { clock.wall.addingTimeInterval(-60) }
        await duo.run(6)
        await store.refreshMatch(id: tfMatch)          // 응답의 server_now_ms 로 시계 차를 다시 잰다
        let silence = try #require(store.opponentSilenceSeconds())
        #expect(silence >= 5, "기기 시계가 뒤로 간 뒤 끊긴 상대의 침묵이 \(silence)초 — '상대 연결 확인 중' 이 안 뜬다")
        duo.tearDown()
    }

    // MARK: 수명 — 닫기 누락 = 연결 누수

    @MainActor
    @Test("판을 떠나는 모든 길이 프레임 소켓을 닫는다 — 로그아웃 · 판 내림 · 다른 기기로 물러남 · 다른 기기가 두는 판 · 끝난 판")
    func everyExitClosesTheFrameSocket() async throws {
        // 없으면: 한 길이라도 닫기를 빠뜨리면 판 전용 소켓이 남아 피크 연결로 잡힌다(§10 — 끝난 판 가지는 discardDuel 을 안 지난다).
        let exits: [(String, @MainActor (TFDuo) -> Void, Bool)] = [
            ("reset", { $0.a.store.reset() }, false),
            ("clearMatch", { $0.a.store.clearMatch() }, false),
            ("otherDevice", { duo in
                let response = try! tfDecode(TetrisActionResponse.self, tfJSON(["status": "other_device",
                                                                                "state": duo.server.state(for: tfA)]))
                duo.a.store.applyReportResult(.success(response), matchID: tfMatch, receivedAt: duo.clock.uptime)
            }, false),
            ("elsewhere", { duo in tfApply(duo) { $0["my_device"] = "other" } }, false),
            ("finished", { duo in
                duo.server.finish(winner: tfB, reason: "resign")
                tfApply(duo)
            }, true),
        ]
        for (name, leave, keepsLink) in exits {
            let duo = await tfSolo("exit-\(name)")
            #expect(duo.a.store.frameSocketOpen && duo.a.channel.isOpen, "\(name): 전제 — 소켓이 열려 있다")
            leave(duo)
            #expect(duo.a.channel.disconnects == 1 && !duo.a.channel.isOpen && !duo.a.store.frameSocketOpen,
                    "\(name): 소켓을 안 닫았다")
            #expect((duo.a.store.frameLink != nil) == keepsLink, "\(name): 장부 수명이 어긋났다")
            await duo.run(3)
            #expect(duo.a.channel.connects.count == 1, "\(name): 떠난 판에서 소켓을 다시 열었다")
            duo.tearDown()
        }
    }

    @MainActor
    @Test("토큰: 판 중 세션 토큰이 바뀌면 access_token 을 한 번 밀어 넣는다 · 만료 거절은 토큰을 새로 받아 한 번만 다시 붙는다")
    func tokenRotationAndExpiredJoin() async throws {
        // 없으면: 판 중 토큰이 바뀐 채 만료 때 채널이 닫히거나, 만료 거절을 옛 토큰으로 되풀이해 인가를 두드린다.
        let duo = await tfSolo("token")
        duo.a.host.session = SupabaseSession(accessToken: "rotated", refreshToken: nil, userID: tfA)
        await duo.run(1)
        #expect(duo.a.channel.pushes == ["rotated"], "바뀐 토큰을 안 밀어 넣었다(또는 여러 번): \(duo.a.channel.pushes)")
        duo.tearDown()

        // 만료: 첫 조인이 'Token has expired' 로 거절된다 → 판 상태 한 번(세션 재시도가 토큰을 새로 받는다) → 새 토큰으로 한 번.
        let expired = await tfSolo("expired") {
            $0.relay.joinPolicy[tfA] = .reject("Token has expired 3 seconds ago")
            $0.a.host.tokens.armStateRefresh()
        }
        await tfWait { expired.a.channel.connects.count >= 2 }
        await expired.run(2)
        let tokens = expired.a.channel.connects.map(\.token)
        #expect(tokens == ["token-a1", "fresh-token-1"], "만료 거절 뒤 새 토큰으로 한 번 다시 붙지 않았다: \(tokens)")
        #expect(expired.server.stateCalls(of: tfA) == 1, "토큰을 새로 받는 조회가 한 번이 아니다")
        await expired.run(10)
        #expect(expired.a.channel.connects.count == 2, "두 번째 만료 뒤에도 또 붙었다")
        #expect(expired.a.store.frameLink?.socket == .stopped(.exhausted))
        #expect(expired.reports(tfA, inLast: 8) >= 7, "만료로 멈춘 판이 1초가 아니다")
        expired.tearDown()

        // 토큰을 새로 받는 조회가 돌았는데도 토큰이 그대로다(REST 는 아직 받아 준다 — 기기 시계 차) → 거절된 토큰으로 다시 붙지 않는다
        // (11-03 검토 F4 — 인가 검사 한 번을 헛쓴다). 두 번째 만료와 같은 결론으로 멈춘다.
        let unchanged = await tfSolo("expired-same") {
            $0.relay.joinPolicy[tfA] = .reject("Token has expired 3 seconds ago")
        }
        await unchanged.run(4)
        #expect(unchanged.server.stateCalls(of: tfA) == 1, "전제: 토큰을 새로 받는 조회가 한 번 돌았다")
        #expect(unchanged.a.channel.connects.map(\.token) == ["token-a1"], "그대로인 토큰으로 다시 붙었다: \(unchanged.a.channel.connects.map(\.token))")
        #expect(unchanged.a.store.frameLink?.socket == .stopped(.exhausted))
        unchanged.tearDown()

        // 토큰을 새로 받는 조회가 **이미 도는 조회와 합쳐졌다**(그 조회가 끝나야 토큰이 바뀐다) → 옛 토큰으로 곧바로 붙지 않고 일반
        // 재시도 한 번으로 미뤄, 그때 새 토큰으로 붙는다(11-03 검토 F4 — 고치기 전에는 옛 토큰으로 붙어 두 번째 만료로 멈췄다).
        let merged = await tfSolo("expired-merged")
        let store = merged.a.store
        #expect(merged.a.channel.joined, "전제: 처음 조인은 받아들여졌다")
        merged.relay.joinPolicy[tfA] = .reject("Token has expired 3 seconds ago")
        merged.relay.dropConnection(tfA)
        var guardSteps = 0
        while store.frameLink?.needsFreshToken != true, guardSteps < 60 {
            await merged.step()
            guardSteps += 1
        }
        guard case .retrying(let retryAt)? = store.frameLink?.socket, store.frameLink?.needsFreshToken == true else {
            Issue.record("전제: 만료 거절 뒤 '토큰을 새로 받아 다시' 재시도가 서지 않았다(\(String(describing: store.frameLink?.socket)))")
            merged.tearDown()
            return
        }
        // 재시도 직전에 판 상태 조회 하나를 느리게 띄운다. 그 조회가 끝날 때 토큰이 바뀐다(그 사이 다른 보고가 토큰을 먼저 가져가지 않게
        // 보고 답도 늦춘다).
        merged.server.edit {
            $0.stateDelay = 0.6
            $0.reportDelay[tfA] = 1.5
        }
        merged.a.host.tokens.armStateRefresh()
        store.requestSync()
        await tfWait { store.stateInFlight }
        #expect(store.stateInFlight, "전제: 판 상태 조회가 돌고 있다")
        let connectsBefore = merged.a.channel.connects.count
        while merged.clock.uptime < retryAt { await merged.step(settling: false) }
        await tfWait { store.frameLink?.socket != .connecting || merged.a.channel.connects.count > connectsBefore }
        #expect(merged.a.channel.connects.count == connectsBefore, "합쳐진 조회가 끝나기 전에 거절된 토큰으로 다시 붙었다")
        merged.relay.joinPolicy[tfA] = .accept
        merged.server.edit {
            $0.stateDelay = 0
            $0.reportDelay[tfA] = 0
        }
        await tfWait { !store.stateInFlight }
        await merged.run(6)
        let mergedTokens = merged.a.channel.connects.map(\.token)
        #expect(mergedTokens.last == "fresh-token-1" && !mergedTokens.dropLast().contains("fresh-token-1"),
                "합쳐진 조회가 받아 온 새 토큰으로 다시 붙지 않았다: \(mergedTokens)")
        #expect(store.frameLink?.socket == .joined && merged.a.channel.joined, "새 토큰으로 다시 붙지 못했다")
        merged.tearDown()
    }

    // MARK: 해석 · 테스트 프로세스 · 초인종 소켓과의 분리

    @MainActor
    @Test("해석: 보내는 봉투와 받는 해석이 한 짝 · 남의 토픽·poke: 는 안 연다 · 테스트 프로세스엔 라이브 소켓이 없다(p_protocol 1)")
    func wireAndTestProcessGuards() throws {
        // 없으면: 봉투 한쪽만 바뀌어도 초록이고, 테스트 프로세스가 실소켓을 열거나 시험 기기가 p_protocol 2 를 흘린다.
        let frame = tfFrame(s: 3, f: 1_800_000_000_123, board: tfBoardX, lines: 2, g: 1, p: 0, h: 800)
        let text = RealtimeFrame.broadcast(channel: tfTopic, event: TetrisFrame.event, payload: frame.payload, ref: "5",
                                           joinRef: "1")
        #expect(TetrisFrameWire.event(text: text, topic: tfTopic, joinRef: "1") == .frame(frame))
        #expect(TetrisFrameWire.event(text: text, topic: "tetris:other", joinRef: "1") == nil, "남의 판 프레임을 받았다")
        var broken = frame.payload
        broken["b"] = "xyz"
        let brokenText = RealtimeFrame.broadcast(channel: tfTopic, event: TetrisFrame.event, payload: broken, ref: "6",
                                                 joinRef: "1")
        #expect(TetrisFrameWire.event(text: brokenText, topic: tfTopic, joinRef: "1") == .rejected(.invalidBoard))
        let joined = tfJSON(["topic": "realtime:\(tfTopic)", "event": "phx_reply", "ref": "1",
                             "payload": ["status": "ok", "response": [String: Any]()]])
        #expect(TetrisFrameWire.event(text: joined, topic: tfTopic, joinRef: "1") == .transport(.joined))
        #expect(TetrisFrameWire.event(text: #"{"topic":"phoenix","event":"phx_reply","ref":"9","payload":{}}"#,
                                      topic: tfTopic, joinRef: "1") == .transport(.heartbeatAck))
        #expect(!TetrisFrameWire.isFrameTopic("poke:\(tfA)") && !TetrisFrameWire.isFrameTopic("tetris:")
                && TetrisFrameWire.isFrameTopic(tfTopic))
        // 테스트 프로세스: 라이브 소켓은 nil → 기본 배선의 스토어는 프레임을 못 연다 → 보고는 1.
        #expect(LiveTetrisFrameChannel() == nil, "테스트 프로세스에서 라이브 프레임 소켓이 태어났다")
        let host = TFHost(service: SupabaseWorkService(projectURL: URL(string: "http://v0374-tf-default")!,
                                                       anonKey: "anon-test-key", session: GomokuStubProtocol.session()),
                          userID: tfA)
        let plain = TetrisDuelStore(host: host)
        plain.framesEnabled = true
        #expect(!plain.framesCapable && plain.frameChannel == nil, "기본 배선이 테스트 프로세스에서 프레임 능력을 말했다")
        // ★ 기준선: 같은 스토어에 소켓을 끼우면 능력이 선다(위 거짓이 스위치 때문이 아니다).
        let wired = TetrisDuelStore(host: host)
        wired.framesEnabled = true
        wired.makeFrameChannel = { _ in TFChannel(user: tfA) }
        #expect(wired.framesCapable)
        wired.framesEnabled = false
        #expect(!wired.framesCapable, "스위치를 꺼도 능력이 남았다")
    }

    @MainActor
    @Test("킬스위치: 리얼타임을 끈 기기는 라이브 소켓 생성기를 부르지도 않는다 → 프레임 능력 없음 · 보고는 p_protocol 1", .gomokuDefaultsCleanup)
    func theRealtimeKillSwitchKeepsTheFrameSocketShut() throws {
        // 없으면(11-03 검토 B2): 기본 소켓 문을 `LiveTetrisFrameChannel()` 하나로 줄여도 스위트가 초록이다(테스트 프로세스의 라이브 소켓은
        // 언제나 nil) — 리얼타임을 끈 사용자가 둘째 소켓을 열고 p_protocol 2 를 보내 상대도 헛되이 연다(명세 §11 "킬스위치가 켜진 기기만").
        let off = GomokuTestDefaults.make("v0374-tf-killswitch-off")
        off.set(false, forKey: RealtimeFeature.defaultsKey)
        let on = GomokuTestDefaults.make("v0374-tf-killswitch-on")
        let stub = TFChannel(user: tfA)
        var made = 0
        let live: @MainActor () -> (any TetrisFrameChannel)? = {
            made += 1
            return stub
        }
        #expect(TetrisDuelStore.defaultFrameChannel(defaults: off, environment: [:], live: live) == nil)
        #expect(made == 0, "킬스위치를 끈 기기에서 라이브 소켓을 만들었다")
        // ★ 기준선: 켠 기기는 만든다(위 0 이 '언제나 안 만든다' 가 아니다).
        #expect(TetrisDuelStore.defaultFrameChannel(defaults: on, environment: [:], live: live) === stub && made == 1)
        // 환경 탈출구(CHECK_REALTIME=0)도 같은 문이다.
        #expect(TetrisDuelStore.defaultFrameChannel(defaults: on, environment: ["CHECK_REALTIME": "0"], live: live) == nil)
        #expect(made == 1)
        // 스토어: 같은 문을 지나면 끈 기기는 능력이 없고(p_protocol 1), 켠 기기는 있다.
        let host = TFHost(service: SupabaseWorkService(projectURL: URL(string: "http://v0374-tf-killswitch")!,
                                                       anonKey: "anon-test-key", session: GomokuStubProtocol.session()),
                          userID: tfA)
        let shut = TetrisDuelStore(host: host)
        shut.defaults = off
        shut.framesEnabled = true
        shut.makeFrameChannel = { TetrisDuelStore.defaultFrameChannel(defaults: $0, environment: [:], live: live) }
        #expect(!shut.framesCapable && made == 1, "킬스위치를 끈 스토어가 프레임 능력을 말했다")
        let open = TetrisDuelStore(host: host)
        open.defaults = on
        open.framesEnabled = true
        open.makeFrameChannel = { TetrisDuelStore.defaultFrameChannel(defaults: $0, environment: [:], live: live) }
        #expect(open.framesCapable && made == 2)
        // 스토어의 기본 문이 바로 이 함수다(주석을 걷고 읽는다 — 기본 문만 따로 줄이는 변형을 막는다).
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/CheckCore/TetrisDuelStore.swift")
        let source = V0317ShopTests.stripped(try String(contentsOf: path, encoding: .utf8))
        let wiring = try #require(source.range(of: "package var makeFrameChannel").map { range -> String in
            let tail = source[range.upperBound...]
            return String(tail[..<(tail.firstIndex(of: "}") ?? tail.endIndex)])      // 기본 문 클로저 본문까지
        })
        #expect(wiring.contains("TetrisDuelStore.defaultFrameChannel(defaults: defaults)"), "스토어 기본 소켓 문이 킬스위치 문을 안 지난다")
        #expect(!wiring.contains("LiveTetrisFrameChannel("), "스토어 기본 소켓 문이 킬스위치를 건너뛰고 라이브 소켓을 만든다")
    }

    @MainActor
    @Test("D3: 프레임 조인이 거절돼도 초인종 소켓(poke:)은 아무 명령도 안 받는다", .gomokuDefaultsCleanup)
    func aRejectedFrameJoinNeverTouchesTheDoorbellSocket() async throws {
        // 없으면: 프레임 실패가 공용 소켓을 끊거나 다시 붙여 찌르기·메시지 초인종까지 흔든다(D3 대안의 위험).
        let rpcHost = "v0374-tf-bell-\(UUID().uuidString.prefix(8))".lowercased()
        let server = TFServer()
        server.edit {
            $0.players[tfA]?.ready = true
            $0.players[tfA]?.framesV = 1
            $0.players[tfB]?.ready = true
            $0.players[tfB]?.framesV = 1
        }
        GomokuStubProtocol.register(host: rpcHost) { rpc, body, _ in
            switch rpc {
            case "tetris_report": return server.report(body, from: tfA)
            case "tetris_state": return server.stateCall(from: tfA)
            case "tetris_lobby": return server.lobby(for: tfA)
            case "chess_lobby": return GomokuStubProtocol.Reply(body: #"{"status":"ok","users":[],"matches":[]}"#)
            case "gomoku_inbox": return GomokuStubProtocol.Reply(body: #"{"status":"ok","incoming":[],"outgoing":null}"#)
            default: return nil
            }
        }
        let service = SupabaseWorkService(projectURL: URL(string: "http://\(rpcHost)")!, anonKey: "anon-test-key",
                                          session: GomokuStubProtocol.session())
        let transport = FakeRealtimeTransport()
        let store = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                                   defaults: GomokuTestDefaults.make("v0374-tf-bell"), workspaceNotifications: nil,
                                   realtimeTransport: transport)
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: tfA)
        store.startRealtimeIfPossible()
        transport.emit(.joined)
        let relay = TFRelay()
        let channel = TFChannel(user: tfA)
        relay.attach(channel)
        relay.joinPolicy[tfA] = .reject("Unauthorized: You do not have permissions to read from this Channel topic: \(tfTopic)")
        store.tetris.framesEnabled = true
        store.tetris.makeFrameChannel = { _ in channel }
        store.tetris.gameLoopStepSeconds = 3_600
        let commandsBefore = transport.commands
        store.tetris.applyState(try tfDecode(TetrisStatePayload.self, tfJSON(server.state(for: tfA))))
        #expect(channel.connects.map(\.topic) == [tfTopic], "전제: 프레임 소켓을 판 토픽으로 열었다")
        relay.pump(until: 0)
        #expect(store.tetris.frameLink?.socket == .stopped(.unauthorized), "전제: 프레임 조인이 거절됐다")
        #expect(transport.commands == commandsBefore, "프레임 거절이 초인종 소켓에 명령을 냈다: \(transport.commands)")
        #expect(store.realtimeState.isSubscribed, "초인종 소켓이 구독을 잃었다")
        store.tetris.reset()
        store.chess.reset()
        store.gomoku.reset()
    }

    @MainActor
    @Test("맥 배선: CheckApp 의 테트리스 배선이 framesEnabled 를 켠다(주석을 걷고 읽는다)")
    func theMacWiringTurnsFramesOn() throws {
        // 없으면: 맥은 언제나 p_protocol 1 · 소켓 0 이라 서버 스위치를 켜도 전환이 일어나지 않는다(스토어 시험은 직접 켜서 초록).
        let app = V0317ShopTests.stripped(try V0317ShopTests.source("CheckApp.swift"))
        let wiring = try #require(app.range(of: "private func wireTetrisDuel()").map { String(app[$0.upperBound...].prefix(900)) })
        #expect(wiring.contains("tetris.framesEnabled = true"), "맥 테트리스 배선에 framesEnabled 가 없다")
        // ★ 기준선: 스토어 기본은 꺼짐이다(위 한 줄이 실제로 일을 한다).
        #expect(TetrisDuelStore().framesEnabled == false)
    }
}
