import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.30 — 메시지 읽음·근무 밖 수신 테스트가 함께 쓰는 **스텁 네트워크와 스토어 조립**.
//
// 호스트별로 경로 응답을 스크립트하고 요청을 **URL 째로** 기록한다(로그아웃 scope 처럼 쿼리까지 봐야 하는 단언이 있다).
// 테스트마다 고유 호스트라 병렬 스위트가 서로의 기록·응답을 덮지 않는다. 기존 스텁(URLProtocolStub·GomokuStubProtocol)을
// 고치지 않고 새로 두는 이유는 소유다 — 그 파일들은 이 작업의 것이 아니다.
//
// 스텁이 못 잡는 것(서버 정규화·실제 시간 경과·배달)은 X1 계약 픽스처와 두 계정 e2e 몫이다.

/// 호스트별 스크립트 URLProtocol(메시지 읽음 스위트 전용).
final class MessageReadStubProtocol: URLProtocol {
    struct Reply: Sendable {
        var status: Int = 200
        var body: String
        var delay: TimeInterval = 0
        /// 열릴 때까지 응답을 붙잡는 문(m-fix F6). 벽시계 지연(`delay`)은 전체 스위트 부하에서 뒤에 띄운 요청이 전선에
        /// 오르기도 전에 풀려 "늦게 온 옛 응답" 순서가 뒤집힌다 — 도착 순서를 테스트가 **정하게** 하려면 이것을 쓴다.
        var gate: MessageReadStubGate? = nil
    }

    struct Call: Sendable {
        let url: URL
        let method: String
        let body: String

        var path: String { url.path }
        /// `/rest/v1/rpc/<name>` 이면 name, 아니면 경로 그대로.
        var rpc: String {
            let prefix = "/rest/v1/rpc/"
            return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
        }
        var json: [String: Any] {
            (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        }
    }

    /// (호출, 같은 rpc 의 몇 번째 호출인가 0부터) → 응답. nil 이면 기본 응답(아래 `defaultReply`).
    typealias Handler = @Sendable (_ call: Call, _ index: Int) -> Reply?

    private static let lock = NSLock()
    private nonisolated(unsafe) static var handlers: [String: Handler] = [:]
    private nonisolated(unsafe) static var callsByHost: [String: [Call]] = [:]

    static func register(host: String, handler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        handlers[host] = handler
        callsByHost[host] = []
    }

    static func calls(host: String) -> [Call] {
        lock.lock()
        defer { lock.unlock() }
        return callsByHost[host] ?? []
    }

    static func calls(host: String, rpc: String) -> [Call] {
        calls(host: host).filter { $0.rpc == rpc }
    }

    static func count(host: String, rpc: String) -> Int {
        calls(host: host, rpc: rpc).count
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MessageReadStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// 스크립트하지 않은 경로의 응답. 인자 없는 목록 RPC 가 많아 `[]` 가 가장 흔한 정상 응답이다.
    /// 요약·읽음 RPC 는 **없는 서버**(404 PGRST202)가 기본이다 — 스크립트를 잊은 테스트가 "읽음을 아는 빈 서버"로
    /// 조용히 초록이 되지 않게.
    static func defaultReply(for call: Call) -> Reply {
        switch call.rpc {
        case "message_history_with_reads", "message_unread_summary", "mark_messages_read":
            return MessageReadFixture.missingFunction(call.rpc)
        default:
            return Reply(body: "[]")
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let call = Call(url: request.url!, method: request.httpMethod ?? "GET", body: Self.bodyText(from: request))
        Self.lock.lock()
        let index = (Self.callsByHost[host] ?? []).filter { $0.rpc == call.rpc }.count
        Self.callsByHost[host, default: []].append(call)
        let handler = Self.handlers[host]
        Self.lock.unlock()

        let reply = handler?(call, index) ?? Self.defaultReply(for: call)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let delivery = MessageReadStubDelivery(proto: self, response: response, data: Data(reply.body.utf8))
        if let gate = reply.gate {
            gate.whenOpen { DispatchQueue.global().async { delivery.run() } }
        } else if reply.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { delivery.run() }
        } else {
            delivery.run()
        }
    }

    override func stopLoading() {}

    private static func bodyText(from request: URLRequest) -> String {
        if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: size)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// 응답 문(m-fix F6). `open()` 전에 도착한 요청의 응답은 붙잡혀 있다가 열리는 순간 한꺼번에 나간다.
final class MessageReadStubGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var pending: [@Sendable () -> Void] = []

    init() {}

    func open() {
        lock.lock()
        isOpen = true
        let waiting = pending
        pending = []
        lock.unlock()
        waiting.forEach { $0() }
    }

    func whenOpen(_ work: @escaping @Sendable () -> Void) {
        lock.lock()
        if isOpen {
            lock.unlock()
            work()
            return
        }
        pending.append(work)
        lock.unlock()
    }
}

private final class MessageReadStubDelivery: @unchecked Sendable {
    let proto: MessageReadStubProtocol
    let response: HTTPURLResponse
    let data: Data

    init(proto: MessageReadStubProtocol, response: HTTPURLResponse, data: Data) {
        self.proto = proto
        self.response = response
        self.data = data
    }

    func run() {
        proto.client?.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
        proto.client?.urlProtocol(proto, didLoad: data)
        proto.client?.urlProtocolDidFinishLoading(proto)
    }
}

// MARK: - 픽스처 (SPEC-wave1 §1.1 의 JSON 모양 그대로)

enum MessageReadFixture {
    static let me = "00000000-0000-0000-0000-0000000330a1"
    static let peerA = "00000000-0000-0000-0000-0000000330b2"
    static let peerB = "00000000-0000-0000-0000-0000000330c3"
    /// 얼린 기준 시각(초 경계에 딱 맞는 값 — 같은 초 안의 메시지를 만들기 쉽게).
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static func json(_ object: Any) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    static func missingFunction(_ name: String) -> MessageReadStubProtocol.Reply {
        MessageReadStubProtocol.Reply(
            status: 404,
            body: #"{"code":"PGRST202","message":"Could not find the function public.\#(name) in the schema cache"}"#
        )
    }

    /// `message_history_with_reads` 한 행. epoch 는 **초**다(서버 `extract(epoch …)::bigint`).
    static func readsRow(
        id: String,
        peer: String,
        isMine: Bool,
        body: String = "안녕",
        epoch: Int = Int(MessageReadFixture.now.timeIntervalSince1970),
        readByPeer: Bool? = nil,
        unread: Bool? = nil,
        name: String = "상대"
    ) -> [String: Any] {
        [
            "id": id,
            "from_user": isMine ? me : peer,
            "to_user": isMine ? peer : me,
            "body": body,
            "created_at": "2026-09-21T12:00:00.123456+00:00",
            "is_mine": isMine,
            "peer_user_id": peer,
            "peer_display_name": name,
            "peer_avatar_url": NSNull(),
            "created_epoch": epoch,
            "read_by_peer": readByPeer.map { $0 as Any } ?? NSNull(),
            "unread": unread.map { $0 as Any } ?? NSNull()
        ]
    }

    static func historyReply(
        _ rows: [[String: Any]], delay: TimeInterval = 0, gate: MessageReadStubGate? = nil
    ) -> MessageReadStubProtocol.Reply {
        MessageReadStubProtocol.Reply(body: json(rows), delay: delay, gate: gate)
    }

    static func summaryReply(
        _ peers: [(String, Int)], delay: TimeInterval = 0, gate: MessageReadStubGate? = nil
    ) -> MessageReadStubProtocol.Reply {
        let rows: [[String: Any]] = peers.enumerated().map { index, pair in
            ["peer_user_id": pair.0, "count": pair.1, "last_epoch_ms": 1_790_000_000_000 - index * 1000]
        }
        let total = peers.reduce(0) { $0 + $1.1 }
        return MessageReadStubProtocol.Reply(
            body: json(["status": "ok", "total": total, "peers": rows]), delay: delay, gate: gate
        )
    }

    static func markReply(advanced: Bool = true, unread: Int = 0, delay: TimeInterval = 0) -> MessageReadStubProtocol.Reply {
        MessageReadStubProtocol.Reply(
            body: json(["status": "ok", "advanced": advanced, "unread": unread]), delay: delay
        )
    }

    /// take_pokes 메시지 행(초 단위 epoch).
    static func takenMessageRow(id: String, from peer: String, epoch: Int, body: String = "밥?") -> [String: Any] {
        [
            "id": id, "from_user": peer, "from_display_name": "상대", "from_avatar_url": NSNull(),
            "created_epoch": epoch, "kind": "message", "body": body, "from_character": NSNull()
        ]
    }
}

// MARK: - 스토어 조립

/// 붙잡아 둔다 — 오목 스토어는 WorkTimerStore 를 약참조하고, 테스트가 튜플을 버리면 곧바로 해제된다(V0327 의 실측).
@MainActor
enum MessageReadTestRetention {
    static var stores: [WorkTimerStore] = []
}

/// 격리 토큰 스토어 — 기본값 `.shared` 는 실제 홈을 훑는다(V0251MessagePeerTests 의 mpTokenStore 주석).
@MainActor
func messageReadTokenStore() -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    let tag = UUID().uuidString
    return TokenUsageStore(
        defaults: GomokuTestDefaults.make("v0330-msg-token"),
        homeDirectory: tmp.appendingPathComponent("v0330-token-home-\(tag)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("v0330-token-cache-\(tag).json", isDirectory: false),
        clock: { MessageReadFixture.now },
        notificationCenter: NotificationCenter()
    )
}

/// 스텁 네트워크에 물린 **로그인** 스토어. 근무는 기본으로 **안 한다**(이 스위트의 주인공이 비근무 사용자다).
/// 시계는 얼린다. `.gomokuDefaultsCleanup` 트레이트를 단 테스트에서 불러야 스위트가 지워진다.
@MainActor
func makeMessageReadStore(
    _ label: String,
    transport: RealtimeTransport? = nil,
    handler: @escaping MessageReadStubProtocol.Handler = { _, _ in nil }
) -> (store: WorkTimerStore, host: String) {
    let host = "v0330-msg-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    MessageReadStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: MessageReadStubProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: GomokuTestDefaults.make("v0330-msg"),
        workspaceNotifications: nil,
        tokenUsage: messageReadTokenStore(),
        realtimeTransport: transport
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: MessageReadFixture.me)
    store.clock = { MessageReadFixture.now }
    store.gomoku.clock = { MessageReadFixture.now }
    // 합치기 창(프로덕션 1초)을 짧게 줄인다 — 창은 여전히 **진짜 잠**이라 한 차례에 몰린 신호는 합쳐진다. 창이 닫히는 순간을
    // 테스트가 정해야 하는 단언은 `MessageReadSleepGate` 로 갈아 끼운다.
    store.messageReadSignalSleep = { _ in try? await Task.sleep(for: .milliseconds(10)) }
    MessageReadTestRetention.stores.append(store)
    return (store, host)
}

/// 합치기 창의 잠을 **테스트가 여는 문**으로 바꾼다(m-fix2). 요청된 초를 적고, `open()` 전에는 깨지 않는다(취소도 무시 —
/// 창 Task 의 취소·세대 가드가 스스로 나가는지를 재기 위해서다). 열린 뒤의 잠은 곧바로 돌아온다.
final class MessageReadSleepGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var requested: [TimeInterval] = []

    init() {}

    /// 지금 문 앞에서 자고 있는 창의 수.
    var sleepers: Int {
        lock.lock()
        defer { lock.unlock() }
        return waiting.count
    }

    /// 지금까지 요청된 잠의 길이(초).
    var requestedSeconds: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }

    var sleep: @Sendable (TimeInterval) async -> Void {
        { [self] seconds in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                requested.append(seconds)
                if isOpen {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                waiting.append(continuation)
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let resumed = waiting
        waiting = []
        lock.unlock()
        resumed.forEach { $0.resume() }
    }
}

/// 조건이 참이 될 때까지 기다린다. 상한은 **재개 횟수**다(V0327 realtimeWait 과 같은 해법 — 전체 스위트 부하에서 벽시계 상한은
/// 스토어의 Task 가 차례를 받기도 전에 끝난다).
@MainActor
func messageReadWait(_ timeout: TimeInterval = 60, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<Int(timeout * 200) {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 스토어가 띄운 메시지·리얼타임 비동기 작업이 전부 끝났는가(부정형 단언 앞에 쓴다).
@MainActor
func messageReadIdle(_ store: WorkTimerStore) -> Bool {
    store.drainInFlight == nil
        && store.realtime.catchUpTask == nil
        && store.messageReadRuntime.activityTask == nil
        && store.messageReadRuntime.activityWindowTask == nil
        && store.messageReadRuntime.markInFlight.isEmpty
        && !store.messageHistoryLoading
}
