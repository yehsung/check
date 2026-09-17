@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 게임 탭 테스트 도우미(D6). 기반 도우미(BaseTestSupport)는 고치지 않고 여기서 조합한다.

/// 스텁 서버: RPC 이름(또는 경로)마다 응답 **대기열**을 둔다. 대기열이 비면 기본 응답기를 쓴다.
final class GamesStubServer: @unchecked Sendable {
    typealias Responder = @Sendable (MobileStubRequest) -> MobileStubResponse

    let host: String
    private let lock = NSLock()
    private var queues: [String: [Responder]] = [:]
    private var defaults: [String: Responder] = [:]

    init(label: String = "games") {
        host = BaseStub.makeHost(label)
        MobileStubURLProtocol.register(host: host) { [self] request in self.respond(request) }
    }

    /// 요청 키: RPC 이름, 아니면 경로.
    static func key(_ request: MobileStubRequest) -> String { request.rpcName ?? request.path }

    func setDefault(_ key: String, _ responder: @escaping Responder) {
        lock.lock(); defer { lock.unlock() }
        defaults[key] = responder
    }

    func setDefault(_ key: String, json: String, status: Int = 200) {
        setDefault(key) { _ in .json(json, status: status) }
    }

    func enqueue(_ key: String, _ responder: @escaping Responder) {
        lock.lock(); defer { lock.unlock() }
        queues[key, default: []].append(responder)
    }

    var requests: [MobileStubRequest] { baseRequests(host: host) }

    func requests(_ key: String) -> [MobileStubRequest] {
        requests.filter { Self.key($0) == key }
    }

    private func respond(_ request: MobileStubRequest) -> MobileStubResponse {
        let key = Self.key(request)
        let responder: Responder? = {
            lock.lock(); defer { lock.unlock() }
            if var queue = queues[key], !queue.isEmpty {
                let first = queue.removeFirst()
                queues[key] = queue
                return first
            }
            return defaults[key]
        }()
        if let responder { return responder(request) }
        switch request.rpcName {
        case "client_release": return BaseStub.releaseOK
        case "register_device": return BaseStub.registerOK
        case "unregister_device": return .json(#"{"status":"ok","removed":true}"#)
        default: break
        }
        if request.path == "/auth/v1/logout" { return .json("{}") }
        if request.path == "/rest/v1/memberships" { return BaseStub.membershipOK }
        return .missingFunction(key)
    }
}

/// 로그인된 앱 모델 하나(스텁 서버 · 조작 시계 · 임시 저장소).
@MainActor
final class GamesHarness {
    nonisolated static let userID = "u-games"

    let server: GamesStubServer
    let storage: AingSharedStorage
    let clock: BaseTestClock
    let model: MobileAppModel

    init(label: String = "games") {
        server = GamesStubServer(label: label)
        storage = BaseStub.makeStorage()
        clock = BaseTestClock()
        let fresh = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(24 * 3600), subject: Self.userID)
        server.setDefault("/auth/v1/token") { _ in BaseStub.authResponse(access: fresh, refresh: "r-games", userID: GamesHarness.userID) }
        let environment = MobileEnvironment(
            service: BaseStub.makeService(host: server.host),
            vault: InMemoryTokenVault(),
            storage: storage,
            appInfo: BaseStub.appInfo,
            clock: clock.clock,
            installationID: "11111111-2222-4333-8444-66666666aaaa",
            realtimeTransport: nil,
            runsTimers: false,
            reloadWidgetTimelines: {}
        )
        model = MobileAppModel(environment: environment)
        model.session.clientReleaseTimeoutSeconds = 0   // 벽시계 상한 없음(포화에서 client_release 가 3초를 넘어도 같은 경로)
    }

    var games: GamesStore { model.games }

    /// 사건 장벽(같은 서비스·세션 한 바퀴) — 스토어가 띄운 `Task { }` 의 요청·늦은 응답 처리가 이보다 앞선다.
    func barrier() async {
        await baseBarrier(model.context.service)
    }
    var hub: GamesMiniGameHub { model.games.miniGames }
    var gomoku: GomokuStore { model.gomoku }

    /// 실행 → 로그아웃 상태 → active → 로그인.
    func signIn() async {
        model.start()
        _ = await baseWaitUntil { model.session.phase == .signedOut }
        model.sceneDidBecomeActive()
        await model.session.signIn(email: "games@aing.invalid", password: "pw")
    }

    func tearDown() async {
        if model.session.isSignedIn { await model.session.signOut() }
        model.gomoku.reset()
        BaseStub.tearDown(host: server.host, storage: storage)
    }

    var violations: [String] { MobileForbiddenCalls.violations(in: server.requests) }

    /// 서버 epoch 밀리초(조작 시계 기준).
    var serverNowMs: Int { Int(clock.now.timeIntervalSince1970 * 1000) }
}

/// 엔진을 프레임 단위로 민다(초 단위 dt). 조건이 참이 되면 멈춘다.
@MainActor
@discardableResult
func gamesDrive(_ controller: GamesPlayController, from start: Date, frames: Int, dt: TimeInterval = 1.0 / 60.0,
                until condition: ((GamesPlayController) -> Bool)? = nil) -> Date {
    var now = start
    for _ in 0..<frames {
        now = now.addingTimeInterval(dt)
        controller.tick(at: now)
        if let condition, condition(controller) { break }
    }
    return now
}

/// 오목 상태 묶음을 JSON 으로 만든다(서버 모양 그대로).
enum GamesGomokuJSON {
    static func user(_ id: String, _ name: String, working: Bool = true, capable: Bool = true, inMatch: Bool = false) -> String {
        #"{"user_id":"\#(id)","display_name":"\#(name)","avatar_url":null,"character":null,"center":"seoul","is_working":\#(working),"capable":\#(capable),"in_match":\#(inMatch)}"#
    }

    static func inbox(nowMs: Int, incoming: [(id: String, name: String, stake: Int)] = [], active: String? = nil) -> String {
        let rows = incoming.map { invite -> String in
            let peer = user("p-" + invite.id, invite.name)
            return #"{"match_id":"\#(invite.id)","challenger":\#(peer),"stake":\#(invite.stake),"invite_expires_ms":\#(nowMs + 60_000)}"#
        }
        let activeValue = active.map { "\"\($0)\"" } ?? "null"
        return #"{"status":"ok","incoming":[\#(rows.joined(separator: ","))],"outgoing":null,"active_match_id":\#(activeValue),"last_finished":null,"ruby_balance":30,"server_now_ms":\#(nowMs)}"#
    }

    static func lobby(nowMs: Int, active: String? = nil) -> String {
        let activeValue = active.map { "\"\($0)\"" } ?? "null"
        return #"{"status":"ok","server_now_ms":\#(nowMs),"stakes":[3,5,10],"turn_seconds":30,"invite_ttl_seconds":60,"auto_abandon_streak":3,"me":{"ruby_balance":30,"wins":2,"losses":1,"draws":0,"active_match_id":\#(activeValue),"outgoing_match_id":null},"users":[\#(user("p-1", "구름빵")),\#(user("p-2", "초코칩", working: false))],"matches":[]}"#
    }

    /// 진행 중(또는 끝난) 판 한 벌. 나는 흑.
    static func state(nowMs: Int, matchID: String, finished: Bool = false, turn: String = "black", moves: [(color: String, notation: String)] = []) -> String {
        let moveRows = moves.enumerated().compactMap { index, move -> String? in
            guard let point = GomokuPoint(notation: move.notation) else { return nil }
            return #"{"seq":\#(index + 1),"color":"\#(move.color)","kind":"move","x":\#(point.x),"y":\#(point.y),"auto":false}"#
        }
        let status = finished ? "finished" : "active"
        let result = finished ? #""black_win""# : "null"
        let reason = finished ? #""resign""# : "null"
        let turnValue = finished ? "null" : "\"\(turn)\""
        let deadline = finished ? "null" : "\(nowMs + 22_000)"
        return #"{"status":"ok","match":{"id":"\#(matchID)","status":"\#(status)","stake":5,"black":"\#(GamesHarness.userID)","white":"p-1","move_count":\#(moves.count),"turn":\#(turnValue),"deadline_ms":\#(deadline),"result":\#(result),"end_reason":\#(reason)},"moves":[\#(moveRows.joined(separator: ","))],"my_color":"black","opponent":\#(user("p-1", "구름빵", inMatch: !finished)),"ruby_balance":30,"server_now_ms":\#(nowMs),"chat":[],"chat_seq":0,"my_muted":false,"opponent_muted":false,"chat_capable":true,"chat_max_len":100,"my_auto_streak":0,"opponent_auto_streak":0}"#
    }
}
