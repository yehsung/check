import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 지금 탭 테스트 도우미(D3). 기반 도우미(`BaseStub` 등)는 고치지 않고 여기서 조합한다.

/// 손으로 미는 타이머(디바운스 1.5초 · 주기 60초·5분 · 되돌리기 5초를 기다리지 않는다).
@MainActor
final class NowManualScheduler: TodoSyncScheduler {
    final class Handle: TodoSyncCancellable {
        var cancelled = false
        func cancel() { cancelled = true }
    }

    private struct Item {
        let due: Double
        let seq: Int
        let handle: Handle
        let action: @MainActor () -> Void
    }

    private(set) var elapsed: Double = 0
    private var items: [Item] = []
    private var seq = 0

    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> any TodoSyncCancellable {
        let handle = Handle()
        seq += 1
        items.append(Item(due: elapsed + seconds, seq: seq, handle: handle, action: action))
        return handle
    }

    /// 시간을 민다(그 사이 만기인 예약을 순서대로 실행 — 실행 중 새로 건 예약도 창 안이면 돈다).
    func advance(_ seconds: Double) {
        let target = elapsed + seconds
        while true {
            items.removeAll { $0.handle.cancelled }
            guard let next = items.filter({ $0.due <= target }).min(by: { ($0.due, $0.seq) < ($1.due, $1.seq) }) else { break }
            items.removeAll { $0.seq == next.seq }
            elapsed = max(elapsed, next.due)
            next.action()
        }
        elapsed = target
    }

    var liveCount: Int { items.filter { !$0.handle.cancelled }.count }
}

/// 테스트 서버의 `todo_sync`(LWW · 전체를 돌려준다). 스텁 스레드에서 불리므로 잠근다.
final class NowFakeTodoServer: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [String: [String: Any]] = [:]
    private var order: [String] = []
    private(set) var callCount = 0
    private(set) var lastChangeIDs: [String] = []
    var watermarkMs: Int64 = 1_789_621_500_000
    var failure: MobileStubResponse?

    func seed(_ item: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        let id = (item["id"] as? String ?? "").lowercased()
        if rows[id] == nil { order.append(id) }
        rows[id] = item
    }

    func row(_ id: String) -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        return rows[id.lowercased()]
    }

    var calls: Int {
        lock.lock(); defer { lock.unlock() }
        return callCount
    }

    var changeIDs: [String] {
        lock.lock(); defer { lock.unlock() }
        return lastChangeIDs
    }

    func respond(_ request: MobileStubRequest) -> MobileStubResponse {
        lock.lock(); defer { lock.unlock() }
        callCount += 1
        if let failure { return failure }
        let body = (try? JSONSerialization.jsonObject(with: Data(request.bodyText.utf8))) as? [String: Any] ?? [:]
        let changes = body["p_changes"] as? [[String: Any]] ?? []
        let since = body["p_since_ms"] as? NSNumber
        lastChangeIDs = changes.compactMap { ($0["id"] as? String)?.lowercased() }
        for change in changes {
            guard let id = (change["id"] as? String)?.lowercased() else { continue }
            let incoming = (change["updated_at_ms"] as? NSNumber)?.int64Value ?? 0
            let existing = (rows[id]?["updated_at_ms"] as? NSNumber)?.int64Value
            if existing == nil || incoming > existing! {
                if rows[id] == nil { order.append(id) }
                rows[id] = change
            }
        }
        watermarkMs += 1000
        let items = order.compactMap { rows[$0] }
        let object: [String: Any] = [
            "status": "ok", "items": items, "watermark_ms": watermarkMs, "rejected": [Any](), "full": since == nil,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return MobileStubResponse(status: 200, body: data)
    }
}

/// 지금 탭 시나리오 서버: 팀 상태(GET 넷) · 멤버십 · 디렉터리 · 목표 · 할 일. 응답은 테스트가 바꿀 수 있다.
final class NowStubServer: @unchecked Sendable {
    static let teamID = "team-now"
    static let me = "u-me"
    static let mint = "u-mint"
    static let lime = "u-lime"
    static let bori = "u-bori"
    static let jadu = "u-jadu"
    static let coral = "u-coral"
    static let morae = "u-morae"
    static let haneul = "u-haneul"

    private let lock = NSLock()
    let todo = NowFakeTodoServer()
    private var overrides: [String: MobileStubResponse] = [:]
    private var goalHours = 40

    /// 경로 키("work_statuses" · "memberships" · "rpc.app_user_directory" · "rpc.set_team_weekly_goal" · "work_sessions.active" …)의 응답을 바꾼다.
    func override(_ key: String, _ response: MobileStubResponse?) {
        lock.lock(); defer { lock.unlock() }
        overrides[key] = response
    }

    func respond(_ request: MobileStubRequest, userID: @Sendable () -> String) -> MobileStubResponse {
        let key = Self.key(for: request)
        lock.lock()
        let override = overrides[key]
        lock.unlock()
        if let override { return override }
        switch key {
        case "rpc.client_release": return BaseStub.releaseOK
        case "rpc.register_device": return BaseStub.registerOK
        case "rpc.unregister_device": return .json(#"{"status":"ok","removed":true}"#)
        case "auth.logout": return .json("{}")
        case "memberships":
            lock.lock(); defer { lock.unlock() }
            return .json(#"[{"team_id":"\#(Self.teamID)","role":"member","teams":{"name":"지금팀","weekly_goal_hours":\#(goalHours)}}]"#)
        case "work_statuses": return .json(Self.statuses)
        case "work_sessions.active": return .json(Self.activeSessions)
        case "work_sessions.weekly": return .json(Self.weeklySessions)
        case "rpc.app_user_directory": return .json(Self.directory)
        case "rpc.set_team_weekly_goal":
            let body = (try? JSONSerialization.jsonObject(with: Data(request.bodyText.utf8))) as? [String: Any]
            let hours = (body?["goal_hours"] as? NSNumber)?.intValue ?? 0
            lock.lock(); goalHours = hours; lock.unlock()
            return .json(#"[{"weekly_goal_hours":\#(hours)}]"#)
        case "rpc.todo_sync": return todo.respond(request)
        default: return .missingFunction(key)
        }
    }

    static func key(for request: MobileStubRequest) -> String {
        if let rpc = request.rpcName { return "rpc.\(rpc)" }
        if request.path.hasPrefix("/auth/v1/logout") { return "auth.logout" }
        if request.path.hasPrefix("/auth/v1/token") { return "auth.token" }
        let table = request.path.replacingOccurrences(of: "/rest/v1/", with: "")
        if table == "work_sessions" {
            return request.query.contains("ended_at=is.null") ? "work_sessions.active" : "work_sessions.weekly"
        }
        return table
    }

    // 기준 시각: MobileClock.demoInstant = 2026-09-17 05:05:00Z(14:05 KST, 목요일).
    static let statuses = #"""
    [{"user_id":"u-me","status":"working","updated_at":"2026-09-17T05:04:40Z","last_seen_at":"2026-09-17T05:04:40Z","profiles":{"display_name":"나","avatar_url":null}},
     {"user_id":"u-mint","status":"working","updated_at":"2026-09-17T05:04:10Z","last_seen_at":"2026-09-17T05:04:10Z","profiles":{"display_name":"민트","avatar_url":null}},
     {"user_id":"u-lime","status":"working","updated_at":"2026-09-17T05:04:55Z","last_seen_at":"2026-09-17T05:04:55Z","profiles":{"display_name":"라임","avatar_url":"https://x.invalid/lime.jpg"}},
     {"user_id":"u-bori","status":"working","updated_at":"2026-09-17T04:52:00Z","last_seen_at":"2026-09-17T04:52:00Z","profiles":{"display_name":"보리","avatar_url":null}},
     {"user_id":"u-jadu","status":"offWork","updated_at":"2026-09-17T02:10:00Z","last_seen_at":"2026-09-17T02:10:00Z","profiles":{"display_name":"자두","avatar_url":null}}]
    """#
    static let activeSessions = #"""
    [{"id":"s1","user_id":"u-me","started_at":"2026-09-17T01:20:00Z","ended_at":null},
     {"id":"s2","user_id":"u-mint","started_at":"2026-09-17T00:55:00Z","ended_at":null},
     {"id":"s3","user_id":"u-lime","started_at":"2026-09-17T03:30:00Z","ended_at":null},
     {"id":"s4","user_id":"u-bori","started_at":"2026-09-17T02:00:00Z","ended_at":null}]
    """#
    /// 나: 월 7:40 · 화 7:30 · 수 4:28 · 오늘 새벽 1:25 → 끝난 세션 21.05시간 + 진행 3:45 = 24.8시간(89,280초), 오늘 5:10:00.
    static let weeklySessions = #"""
    [{"user_id":"u-me","started_at":"2026-09-14T00:30:00Z","ended_at":"2026-09-14T08:10:00Z"},
     {"user_id":"u-me","started_at":"2026-09-15T00:50:00Z","ended_at":"2026-09-15T08:20:00Z"},
     {"user_id":"u-me","started_at":"2026-09-16T01:00:00Z","ended_at":"2026-09-16T05:28:00Z"},
     {"user_id":"u-me","started_at":"2026-09-16T23:40:00Z","ended_at":"2026-09-17T01:05:00Z"},
     {"user_id":"u-mint","started_at":"2026-09-15T00:00:00Z","ended_at":"2026-09-15T09:00:00Z"}]
    """#
    static let directory = #"""
    [{"user_id":"u-mint","display_name":"민트","avatar_url":null,"is_working":true,"message_capable":true,"center":"seoul"},
     {"user_id":"u-lime","display_name":"라임","avatar_url":null,"is_working":true,"message_capable":true,"center":null},
     {"user_id":"u-bori","display_name":"보리","avatar_url":null,"is_working":true,"message_capable":true,"center":"busan"},
     {"user_id":"u-coral","display_name":"코랄","avatar_url":null,"is_working":true,"message_capable":true,"center":"busan"},
     {"user_id":"u-morae","display_name":"모래","avatar_url":"https://x.invalid/morae.jpg","is_working":true,"message_capable":true,"center":"seoul"},
     {"user_id":"u-haneul","display_name":"하늘","avatar_url":null,"is_working":true,"message_capable":true,"center":null},
     {"user_id":"u-jadu","display_name":"자두","avatar_url":null,"is_working":false,"message_capable":true,"center":"seoul"},
     {"user_id":"u-gureum","display_name":"구름","avatar_url":null,"is_working":false,"message_capable":true,"center":"seoul"}]
    """#
}

/// 지금 탭 한 벌: 스텁 서버 · 앱 모델(세션·위젯 쓰기 창구) · 손으로 미는 타이머를 꽂은 지금 스토어.
/// 앱 모델의 scenePhase 는 부르지 않는다 — 모델이 가진 자리 스토어들은 가만히 있고, 테스트가 만든 스토어만 움직인다.
@MainActor
final class NowHarness {
    let host: String
    let storage: AingSharedStorage
    let server = NowStubServer()
    let clock = BaseTestClock()
    let vault = InMemoryTokenVault()
    let scheduler = NowManualScheduler()
    let model: MobileAppModel
    let store: NowStore
    private let currentUser = BaseLockedBox(NowStubServer.me)
    /// 위젯 타임라인 새로고침 요청 수(쓰기 창구 · 세션 · 스토어의 touch 가 모두 이 한 함수를 부른다).
    private let reloads = BaseLockedBox(0)
    var widgetReloadCount: Int { reloads.get() }

    /// `seedSnapshot`: 앞 실행이 남긴 위젯 스냅샷 파일(쓰기 창구는 만들 때 파일을 읽는다).
    init(userID: String = NowStubServer.me, runsPeriodicRefresh: Bool = true, seedSnapshot: WidgetSnapshot? = nil) {
        host = BaseStub.makeHost("now")
        storage = BaseStub.makeStorage()
        currentUser.mutate { $0 = userID }
        let server = self.server
        let user = currentUser
        MobileStubURLProtocol.register(host: host) { request in
            server.respond(request, userID: { user.get() })
        }
        vault.write(BaseStub.jwt(exp: clock.now.addingTimeInterval(3600), subject: userID), key: AingKeychain.accessTokenKey)
        vault.write("refresh-1", key: AingKeychain.refreshTokenKey)
        storage.defaults.set(userID, forKey: AingSharedKeys.userID)
        if let seedSnapshot {
            try? WidgetSnapshotCodec.write(seedSnapshot, to: storage.widgetSnapshotURL)
        }
        let reloads = self.reloads
        model = MobileAppModel(environment: MobileEnvironment(
            service: BaseStub.makeService(host: host),
            vault: vault,
            storage: storage,
            appInfo: BaseStub.appInfo,
            clock: clock.clock,
            installationID: "11111111-2222-4333-8444-555555555555",
            realtimeTransport: nil,
            runsTimers: false,
            reloadWidgetTimelines: { reloads.mutate { $0 += 1 } }
        ))
        model.session.clientReleaseTimeoutSeconds = 0   // 벽시계 상한 없음(포화에서 client_release 가 3초를 넘어도 같은 경로)
        store = NowStore(context: model.context, timers: scheduler, runsPeriodicRefresh: runsPeriodicRefresh)
    }

    /// 지금 계정으로 다른 사람이 로그인한다(키체인 복원이 아니라 로그인 흐름 — 세대가 바뀐다).
    func signIn(as userID: String) async {
        let access = BaseStub.jwt(exp: clock.now.addingTimeInterval(3600), subject: userID, salt: "signin-\(userID)")
        server.override("auth.token", BaseStub.authResponse(access: access, refresh: "r-\(userID)", userID: userID))
        currentUser.mutate { $0 = userID }
        await model.session.signIn(email: "\(userID)@x.invalid", password: "pw")
    }

    /// 쉬는 사용자의 팀 상태(근무 안 함 · 세션 없음) — 새로고침마다 값이 같다.
    static let idleStatuses = #"""
    [{"user_id":"u-me","status":"offWork","updated_at":"2026-09-17T03:00:00Z","last_seen_at":"2026-09-17T03:00:00Z","profiles":{"display_name":"나","avatar_url":null}}]
    """#

    /// 나 · 민트가 근무 중이고 마지막 신호가 `seen`(맥은 30초마다 하트비트).
    static func statuses(meSeen: String, mintSeen: String? = nil) -> String {
        let mint = mintSeen ?? meSeen
        return #"""
        [{"user_id":"u-me","status":"working","updated_at":"\#(meSeen)","last_seen_at":"\#(meSeen)","profiles":{"display_name":"나","avatar_url":null}},
         {"user_id":"u-mint","status":"working","updated_at":"\#(mint)","last_seen_at":"\#(mint)","profiles":{"display_name":"민트","avatar_url":null}}]
        """#
    }

    /// 키체인 복원으로 로그인 상태가 될 때까지.
    func launch() async {
        model.start()
        _ = await baseWaitUntil { self.model.session.phase == .signedIn }
    }

    /// active 진입 → 새로고침 · 할 일 동기화가 끝날 때까지.
    func activate() async {
        store.appDidBecomeActive()
        await settle()
    }

    func settle() async {
        await store.refreshTask?.value
        await store.todoSync.runTask?.value
        await store.refreshTask?.value
    }

    var requests: [MobileStubRequest] { baseRequests(host: host) }

    /// 사건 장벽(같은 서비스·세션 한 바퀴).
    func barrier() async {
        await baseBarrier(model.context.service)
    }

    func requests(_ key: String) -> [MobileStubRequest] {
        requests.filter { NowStubServer.key(for: $0) == key }
    }

    var violations: [String] { MobileForbiddenCalls.violations(in: requests) }

    func tearDown() {
        BaseStub.tearDown(host: host, storage: storage)
    }
}
