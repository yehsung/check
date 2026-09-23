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

// MARK: - 라운드 토큰 스텁(호출마다 다른 토큰)

/// `minigame_start_round` 를 **호출마다 다른 토큰**으로 답하게 걸고, 발급된 순서를 담은 상자를 돌려준다.
///
/// ⚠️ 매번 **같은 토큰 문자열**을 주는 스텁으로는 "새 요청이 앞 토큰을 갈아 끼웠다"를 **구조적으로 못 잡는다** —
/// 기준선이 같은 입력이라 갈아 끼워져도 바뀐 것이 없다(저장소 메모 '비교 기준선이 달라야 한다'). 서버는
/// (사용자, 게임)당 미사용 행을 하나만 두고 새 요청마다 갈아 끼우므로(`minigame_rounds_one_open`),
/// 토큰이 하나 더 나갔는지가 곧 **인편이 들고 있던 토큰이 죽었는지**다. 그 사실을 보려면 토큰이 달라야 한다.
///
/// - Returns: 지금까지 발급한 토큰(발급 순서). `prefix` 뒤에 1 부터 번호가 붙는다.
@MainActor
@discardableResult
func gamesServeRoundTokens(_ harness: GamesHarness, prefix: String) -> BaseLockedBox<[String]> {
    let issued = BaseLockedBox<[String]>([])
    harness.server.setDefault("minigame_start_round") { _ in
        var token = ""
        issued.mutate { list in
            token = "\(prefix)-\(list.count + 1)"
            list.append(token)
        }
        return .json(gamesRoundTokenJSON(token))
    }
    return issued
}

/// 서버가 주는 라운드 토큰 응답 한 벌(발급 시각은 하네스 시계와 무관한 고정값 — 나이 판정은 클라가 자기 시계로 한다).
nonisolated func gamesRoundTokenJSON(_ token: String) -> String {
    #"{"status":"ok","token":"\#(token)","expires_at":"2026-09-23T05:35:00Z","server_now":"2026-09-23T05:05:00Z"}"#
}

// MARK: - 대기 예산

/// 한 테스트 몫의 **대기 예산**. `baseWaitUntil` 의 기본 상한(12,000차례)은 초록일 때 보이지 않지만, 대기 하나가
/// 어긋나는 순간 그 한 건이 통째로 84~168초가 된다 — 46건짜리 좁은 필터가 20분짜리가 됐다(실측).
///
/// 두 가지를 바꾼다:
/// ① **상한을 낮춘다.** 이 파일들의 대기는 스텁 왕복 한두 번이고 한가할 때 0.03초다. 2,000차례는 포화된 전체
///    스위트(차례당 7~14ms 로 재 둔 구간)에서도 14~28초라, 실제로 걸리는 시간의 100배 넘는 여유다.
/// ② **한 번 어긋나면 그 테스트의 남은 대기는 짧게 끊는다.** 이미 빨간 테스트에서 뒤의 대기를 더 기다려 봐야
///    얻는 것이 없다(실패 목록은 이미 정해졌다). 0 이 아니라 짧게 두는 이유는 **왜** 어긋났는지가 대기마다
///    달라야 하기 때문이다 — 0 으로 두면 뒤의 대기가 조건을 한 번도 안 보고 실패로 찍힌다.
///
/// 상태는 **인스턴스에** 있다. Swift Testing 은 테스트마다 스위트 인스턴스를 새로 만들므로 이 예산은 테스트
/// 하나 안에서만 공유된다 — 병렬로 도는 옆 테스트의 대기를 끊지 않는다.
final class GamesWaitBudget: @unchecked Sendable {
    /// 실패할 때만 드는 값이다(초록 경로는 조건이 서는 즉시 돌아온다).
    static let turns = 2_000
    /// 이미 어긋난 뒤의 상한.
    static let turnsAfterBreak = 50

    private var broken = false

    @MainActor
    @discardableResult
    func wait(sourceLocation: SourceLocation = #_sourceLocation, _ condition: @MainActor () -> Bool) async -> Bool {
        let ok = await baseWaitUntil(turns: broken ? Self.turnsAfterBreak : Self.turns,
                                     sourceLocation: sourceLocation, condition)
        if !ok { broken = true }
        return ok
    }
}
