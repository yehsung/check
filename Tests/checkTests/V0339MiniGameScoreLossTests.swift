import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.39 — 맥 미니게임 제출 경로에서 **점수가 사라지던** 갈래의 재현. 수리 전 main 에서는 7건 전부 빨갛다(3회 연속 실행으로
// 확인 — 기준선이 초록이면 그 테스트는 아무것도 재지 않는다, `comparison-baseline-must-differ`). 수리(제출 인편 · 왕복 중 가드)
// 뒤에는 전부 초록이어야 한다 — 이 파일이 "고쳤다"의 증명이다. 각 테스트 머리에 어느 코드 줄이 점수를 버렸는지 적어 두었다.
//
// 재는 방식: 서버 응답을 **테스트가 여는 게이트**로 만든다(`V0339GateURLProtocol`). 토큰 요청·제출은
// 테스트가 `release` 하기 전엔 답이 안 나가므로 "왕복 중에 다른 일이 끼어드는" 순서를 지연 시간이
// 아니라 호출 순서로 만든다 — 벽시계로 재면 부하에서 뒤집힌다.
//
// ⚠️ 이 파일은 **수리 전 기준선에서도 컴파일되어야 한다**(기준선에서 빨간지를 실행으로 확인하는 파일이다). 그래서 수리가
//    더한 API(`miniGamePendingSubmits` 등)를 참조하지 않고, 관측은 전부 스텁이 기록한 요청과 옛 프로퍼티로만 한다.
//    수리 뒤 새 API 를 직접 재는 테스트는 `V0339MiniGamePendingSubmitTests` 에 있다.
//
// UserDefaults 는 전부 `CheckTestScratch` 를 거친다(직접 `UserDefaults(suiteName:)` 을 쓰면
// ~/Library/Preferences 를 오염시켜 게이트가 빨개진다).

private let slUserID = "00000000-0000-0000-0000-000000000002"

// MARK: - 게이트식 스텁

/// 토큰 요청(`minigame_start_round`)과 제출(`minigame_submit_score`)은 **보류**하고, 나머지(순위·어제 1등 등)는
/// 즉시 `[]` 로 답한다. 보류된 요청은 테스트가 `release`/`fail` 로 하나씩 연다 — 그래서 "요청 A 가 나간 뒤,
/// 응답이 오기 전에 B 가 끼어든다"를 sleep 없이 만든다.
///
/// 응답은 전역 큐의 `@Sendable` 클로저에서 보낸다. URLProtocol 은 Sendable 이 아니라(unavailable — `@unchecked` 도 경고다)
/// `self` 를 직접 캡처하지 않고 `GateDelivery` 상자에 담아 넘긴다 — `URLProtocolStub.StubDelivery` 와 같은 장치.
final class V0339GateURLProtocol: URLProtocol {
    private static let lock = NSLock()
    // ⚠️ 호스트별로 센다. 전역으로 두면 병렬로 도는 다른 테스트가 같은 프로토콜 클래스를 공유해 서로를 민다
    //    (V0317 의 RoundRaceURLProtocol 이 실제로 그렇게 빨개졌다).
    private nonisolated(unsafe) static var logByHost: [String: [(path: String, body: String)]] = [:]
    private nonisolated(unsafe) static var heldByHost: [String: [(path: String, proto: V0339GateURLProtocol)]] = [:]
    fileprivate var isStopped = false

    static func reset(host: String) {
        lock.lock(); logByHost[host] = []; heldByHost[host] = []; lock.unlock()
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [V0339GateURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// 지금까지 이 호스트로 나간 요청 경로(도착 순).
    static func paths(host: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return (logByHost[host] ?? []).map(\.path)
    }

    /// 경로에 `containing` 이 든 요청의 본문을 JSON 사전으로(도착 순). 키 순서에 기대지 않으려고 파싱한다.
    static func bodies(host: String, containing: String) -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return (logByHost[host] ?? [])
            .filter { $0.path.contains(containing) }
            .compactMap { entry in
                guard let data = entry.body.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                return object
            }
    }

    static func count(host: String, containing: String) -> Int {
        paths(host: host).filter { $0.contains(containing) }.count
    }

    /// 아직 답을 안 준 요청 수(경로 부분 일치).
    static func heldCount(host: String, containing: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return (heldByHost[host] ?? []).filter { $0.path.contains(containing) }.count
    }

    /// 보류 중인 요청 가운데 **가장 오래된** 하나를 이 JSON 으로 연다. 없었으면 false.
    @discardableResult
    static func release(host: String, containing: String, json: String, status: Int = 200) -> Bool {
        guard let proto = take(host: host, containing: containing) else { return false }
        proto.deliver(json: json, status: status)
        return true
    }

    /// 보류 중인 요청을 **전부** 같은 JSON 으로 연다. 연 개수를 돌려준다.
    @discardableResult
    static func releaseAll(host: String, containing: String, json: String) -> Int {
        var opened = 0
        while release(host: host, containing: containing, json: json) { opened += 1 }
        return opened
    }

    /// 보류 중인 가장 오래된 요청을 **전송 실패**로 끝낸다(오프라인·연결 끊김).
    @discardableResult
    static func fail(host: String, containing: String, code: URLError.Code = .networkConnectionLost) -> Bool {
        guard let proto = take(host: host, containing: containing) else { return false }
        proto.deliverFailure(code: code)
        return true
    }

    private static func take(host: String, containing: String) -> V0339GateURLProtocol? {
        lock.lock(); defer { lock.unlock() }
        var held = heldByHost[host] ?? []
        guard let index = held.firstIndex(where: { $0.path.contains(containing) }) else { return nil }
        let entry = held.remove(at: index)
        heldByHost[host] = held
        return entry.proto
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let host = request.url?.host ?? ""
        let body = Self.readBody(request)
        Self.lock.lock()
        Self.logByHost[host, default: []].append((path, body))
        let hold = path.contains("minigame_start_round") || path.contains("minigame_submit_score")
        if hold { Self.heldByHost[host, default: []].append((path, self)) }
        Self.lock.unlock()
        if !hold { deliver(json: "[]", status: 200) }
    }

    override func stopLoading() { isStopped = true }

    private static func readBody(_ request: URLRequest) -> String {
        if let data = request.httpBody { return String(data: data, encoding: .utf8) ?? "" }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open(); defer { stream.close() }
        var data = Data()
        let size = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buffer, maxLength: size)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func deliver(json: String, status: Int) {
        let delivery = GateDelivery(self)
        DispatchQueue.global().async { delivery.send(json: json, status: status) }
    }

    private func deliverFailure(code: URLError.Code) {
        let delivery = GateDelivery(self)
        DispatchQueue.global().async { delivery.fail(code: code) }
    }

    /// 프로토콜 인스턴스를 전역 큐로 나르는 상자. 프로토콜 자신은 Sendable 이 될 수 없어(NSObject 계열의 unavailable 적합성)
    /// `@Sendable` 클로저가 `self` 를 잡으면 경고다 — 상자 하나로 잡아 옮긴다. 상태는 `isStopped` 읽기뿐이라 경합해도 무해하다.
    private final class GateDelivery: @unchecked Sendable {
        let proto: V0339GateURLProtocol
        init(_ proto: V0339GateURLProtocol) { self.proto = proto }

        func send(json: String, status: Int) {
            guard !proto.isStopped, let url = proto.request.url else { return }
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            proto.client?.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
            proto.client?.urlProtocol(proto, didLoad: Data(json.utf8))
            proto.client?.urlProtocolDidFinishLoading(proto)
        }

        func fail(code: URLError.Code) {
            guard !proto.isStopped else { return }
            proto.client?.urlProtocol(proto, didFailWithError: URLError(code))
        }
    }
}

// MARK: - 공통 준비

/// `function` 은 호출한 테스트에서 받아 이어 넘긴다(안 넘기면 스위트 이름이 이 헬퍼로 굳어 전부 한 스위트다).
@MainActor
private func slStore(host: String, function: String = #function) -> WorkTimerStore {
    V0339GateURLProtocol.reset(host: host)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: V0339GateURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: CheckTestScratch.defaults(host, function: function)
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: slUserID)
    // 실사용 모양: 플래피를 골라 창을 열어 둔 채 논다(제출 성공 뒤 순위 재조회 경로까지 지나가게).
    store.miniGameKind = .flappy
    store.isMiniGamePanelVisible = true
    return store
}

/// 선발급이 끝난 상태를 만든다(창을 열 때 받아 둔 토큰).
@MainActor
private func slArm(_ store: WorkTimerStore, token: String, kind: MiniGameKind = .flappy) {
    store.miniGameRoundToken = token
    store.miniGameRoundTokenKind = kind
    store.miniGameRoundTokenAt = Date()
}

/// 조건이 참이 될 때까지 10ms 간격으로 기다린다(상한까지). 참이 되면 바로 돌아오므로 초록 실행은 빠르다.
@MainActor
private func slWait(upTo seconds: Double = 3, until condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

/// 아무 일도 안 일어나야 하는 구간을 흘려보낸다(V0317 의 tkSettle 과 같은 300ms).
@MainActor
private func slSettle() async {
    for _ in 0..<60 { try? await Task.sleep(for: .milliseconds(5)) }
}

/// 이 토큰이 스토어에 **채택됐는가** — 들고 있거나(다음 판용), 제출 본문에 실렸거나(끝나 있던 판이 가져갔다).
/// 두 모양을 다 받는 이유: 수리 뒤에는 토큰을 기다리던 점수가 도착한 토큰을 **바로 가져가** 제출하므로 `miniGameRoundToken`
/// 에는 머물지 않는다. 기준선(수리 전)은 슬롯에만 남기므로 앞 조건으로 잡힌다 — 어느 쪽이든 "도착했고 쓰였다"다.
@MainActor
private func slAdopted(host: String, store: WorkTimerStore, token: String) -> Bool {
    store.miniGameRoundToken == token
        || V0339GateURLProtocol.bodies(host: host, containing: "minigame_submit_score")
            .contains { ($0["p_token"] as? String) == token }
}

/// 보류된 토큰 요청을 열어 스토어가 `token` 을 채택하게 한다.
///
/// 한 번 여는 것으로 끝나지 않는 이유: 응답을 처리한 쪽이 **다시 요청을 낼 수 있다**(토큰 없음 경로의 선발급,
/// 세대가 밀린 응답 뒤의 재요청). 그 요청은 Task 라 `release` 를 부른 순간엔 아직 보류 목록에 없다 —
/// 첫 실행에서 실제로 그렇게 "영영 안 열린 요청"이 남아 ①의 전제가 공허하게 깨졌다. 그래서 채택될 때까지
/// 몇 번 되풀이한다. 아무 요청도 안 나오면(고친 뒤라면 그럴 수 있다) 상한만 쓰고 돌아온다.
@MainActor
private func slDeliverToken(host: String, store: WorkTimerStore, token: String, attempts: Int = 5) async -> Bool {
    for _ in 0..<attempts {
        _ = await slWait(upTo: 0.3) { V0339GateURLProtocol.heldCount(host: host, containing: "minigame_start_round") >= 1 }
        V0339GateURLProtocol.releaseAll(host: host, containing: "minigame_start_round", json: slToken(token))
        if await slWait(upTo: 0.3, until: { slAdopted(host: host, store: store, token: token) }) { return true }
    }
    return slAdopted(host: host, store: store, token: token)
}

private func slSubmits(host: String, score: Int) -> [[String: Any]] {
    V0339GateURLProtocol.bodies(host: host, containing: "minigame_submit_score")
        .filter { ($0["p_score"] as? Int) == score }
}

private let slSubmitOK = #"{"status":"ok","best_score":3,"plays":1,"improved":true}"#
private let slSubmitTooFast = #"{"status":"too_fast","need_seconds":10,"elapsed_seconds":1.2}"#
private let slSubmitTokenUsed = #"{"status":"token_used"}"#
private func slToken(_ token: String) -> String { #"{"status":"ok","token":"\#(token)"}"# }

// MARK: - ① 판이 끝났는데 토큰이 없다 → 점수를 버린다

/// `recordMiniGameScore` 의 `guard let token = miniGameRoundToken … else { … return }` — 안내 한 줄과
/// 다음 판을 위한 선발급만 남기고 **이 판의 점수는 어디에도 두지 않았다.** 토큰이 몇백 ms 뒤에 도착해도
/// 그 점수는 이미 없었다. 서버가 재는 경과는 단조증가라, 점수를 들고 있다가 토큰이 오면 보내는 길이 있다.
@MainActor
@Test("토큰이 늦게 도착한 판의 점수는 토큰이 온 뒤에라도 제출된다")
func aScoreRecordedBeforeItsTokenArrivesIsSubmittedOnceTheTokenLands() async {
    let host = "v0339-b1-late-token"
    let store = slStore(host: host)
    #expect(store.miniGameRoundToken == nil)

    // 판 시작 → 토큰 요청이 나간다(보류). 즉사 판은 이 왕복이 끝나기 전에 끝난다.
    store.beginMiniGameRound(kind: .flappy)
    #expect(await slWait { V0339GateURLProtocol.heldCount(host: host, containing: "minigame_start_round") >= 1 },
            "전제: 판 시작이 토큰을 요청했다")

    // 즉사. 토큰은 아직 없다.
    store.recordMiniGameScore(kind: .flappy, score: 5)
    #expect(store.miniGameSubmitNotice != nil, "전제: 토큰 없음 안내가 떴다(V0317 ①)")

    // 이제 토큰이 온다. 보류된 요청이 하나든(판 시작) 둘이든(토큰 없음 경로의 선발급까지) 전부 같은 토큰으로 연다 —
    // 어느 세대가 채택되든 "토큰이 도착했다"가 전제다.
    #expect(await slDeliverToken(host: host, store: store, token: "tok-late"), "전제: 토큰이 도착해 채택됐다")

    // 핵심: 판이 끝나 있던 점수 5 가 그 토큰으로 나가는가.
    let landed = await slWait(upTo: 2) { !slSubmits(host: host, score: 5).isEmpty }
    #expect(landed,
            Comment(rawValue: "토큰이 도착했는데 판이 끝나 있던 점수는 어디에도 없다 — 제출 \(V0339GateURLProtocol.count(host: host, containing: "minigame_submit_score"))건, 토큰 없음 안내만 남았다"))
}

// MARK: - ② 제출이 네트워크로 실패한다 → catch 가 점수를 버린다

/// `performSubmitMiniGameScore` 의 `catch`: 로그 한 줄 · 안내 · 선발급. **점수는 안 남겼다.** 연결이 끊긴
/// 순간의 판은 서버에 닿지도 못했으니 토큰도 안 죽었다 — 재시도할 수 있는 점수인데 재시도 주체가 없었다.
@MainActor
@Test("네트워크로 죽은 제출은 재시도된다")
func aSubmitThatDiesOnTheNetworkIsRetried() async {
    let host = "v0339-b2-network"
    let store = slStore(host: host)
    slArm(store, token: "tok-A")

    store.recordMiniGameScore(kind: .flappy, score: 7)
    #expect(await slWait { V0339GateURLProtocol.heldCount(host: host, containing: "minigame_submit_score") == 1 },
            "전제: 제출이 나갔다")

    // 연결 끊김. URLError 는 classifyAuthError 에서 .transient — catch 의 일반 경로로 간다.
    V0339GateURLProtocol.fail(host: host, containing: "minigame_submit_score")
    #expect(await slWait { store.miniGameSubmitNotice != nil }, "전제: 실패 안내가 떴다(catch 가 돌았다)")

    // 다음 토큰이 온다(기준선은 catch 에서 선발급을 낸다). 안 냈더라도 tok-A 는 서버에 닿지 않았으니 그대로 쓸 수 있다 —
    // 그래서 여기서는 채택을 전제로 삼지 않는다(고친 코드는 인편이 살아 있는 동안 요청을 안 낸다).
    _ = await slDeliverToken(host: host, store: store, token: "tok-B")

    let retried = await slWait(upTo: 2) { slSubmits(host: host, score: 7).count >= 2 }
    #expect(retried,
            Comment(rawValue: "네트워크로 죽은 제출이 재시도되지 않는다 — 점수 7 의 제출 \(slSubmits(host: host, score: 7).count)건(첫 시도뿐), 들고 있는 토큰 \(store.miniGameRoundToken ?? "nil")"))
}

// MARK: - ③ 제출 왕복 중에 세션 세대가 바뀐다 → 안내도 없이 버린다

/// `performSubmitMiniGameScore` 의 `guard generation == sessionGeneration else { return }` — 응답이 거절이든
/// 오류든 **아무 말 없이** 끝났다(catch 쪽에도 같은 가드가 있다).
///
/// ⚠️ 실사용 빈도는 낮다: `sessionGeneration` 을 올리는 곳은 `signOut()` 과 `clearPersistedSession()` 둘뿐이고
///    둘 다 세션을 nil 로 만든다(로그아웃·강제 로그아웃). 즉 이 가드가 실제로 걸리는 순간엔 알릴 화면도
///    재제출할 세션도 없다 — 가드는 계정 전환 부수효과 차단용으로 **있어야 한다.** 이 테스트는 가드의
///    글자 그대로의 행동("세대만 바뀌고 세션은 그대로")을 재며, 고칠 값어치는 ①②④⑤보다 낮다.
///    그래도 남기는 이유: 같은 계정으로 다시 로그인한 사람은 그 판의 점수를 되찾을 길이 없었다.
@MainActor
@Test("제출 왕복 중 세대가 바뀌어도 거절은 알리거나 점수를 남긴다")
func aGenerationBumpDuringTheSubmitRoundTripStillReportsTheRejection() async {
    let host = "v0339-b3-generation"
    let store = slStore(host: host)
    slArm(store, token: "tok-A")

    store.recordMiniGameScore(kind: .flappy, score: 9)
    #expect(await slWait { V0339GateURLProtocol.heldCount(host: host, containing: "minigame_submit_score") == 1 },
            "전제: 제출이 나갔다")

    // 왕복 중에 세대가 바뀐다(세션은 그대로 — 가드의 조건만 참이 되게).
    store.sessionGeneration += 1
    V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score", json: slSubmitTooFast)

    let heard = await slWait(upTo: 1.5) {
        store.miniGameSubmitNotice != nil || slSubmits(host: host, score: 9).count >= 2
    }
    #expect(heard,
            Comment(rawValue: "세대가 밀린 응답은 거절이었는데 안내도 재시도도 없다 — notice=\(store.miniGameSubmitNotice ?? "nil"), 제출 \(slSubmits(host: host, score: 9).count)건"))
}

// MARK: - ④ 서버가 too_fast 로 거절한다 → 버린다 (같은 토큰으로 나중에 보내면 통과할 점수인데도)

/// 서버 계약(`20260914010000_minigame_round_token.sql` §minigame_submit_score): `too_fast` 는 **토큰을 소모하기
/// 전에** 돌아온다(`used_at` 갱신은 그 아래 줄이다). 경과는 `clock_timestamp() - started_at` 이라 시간이 갈수록
/// 커지므로 같은 토큰으로 나중에 다시 보내면 통과한다.
///
/// 기준선은 두 번 죽였다: ㉠ `recordMiniGameScore` 가 제출 전에 토큰을 비웠고 ㉡ 거절 뒤 곧장
/// `prefetchMiniGameRoundToken` 을 불러 **새 토큰을 청했다** — 서버의 `minigame_start_round` 는
/// `(user_id, game)` 당 미사용 행을 갈아 끼우므로(`on conflict … do update set id = gen_random_uuid(), started_at = now()`)
/// 그 요청이 나가는 순간 아직 쓸 수 있던 tok-A 가 서버에서 죽는다.
@MainActor
@Test("too_fast 거절은 토큰과 점수를 남겨 두고 새 토큰을 청하지 않는다")
func aTooFastRejectionKeepsTheTokenAndTheScoreForALaterRetry() async {
    let host = "v0339-b4-too-fast"
    let store = slStore(host: host)
    slArm(store, token: "tok-A")

    store.recordMiniGameScore(kind: .flappy, score: 29)
    #expect(await slWait { V0339GateURLProtocol.heldCount(host: host, containing: "minigame_submit_score") == 1 },
            "전제: 제출이 나갔다")
    V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score", json: slSubmitTooFast)
    #expect(await slWait { store.miniGameSubmitNotice != nil }, "전제: 거절 안내가 떴다(응답이 처리됐다)")

    // ㉡ 새 토큰 요청이 나가면 안 된다 — 서버가 미사용 행을 갈아 끼워 tok-A 가 죽는다.
    let askedAgain = await slWait(upTo: 0.7) { V0339GateURLProtocol.count(host: host, containing: "minigame_start_round") >= 1 }
    #expect(!askedAgain,
            "too_fast 뒤에 새 토큰을 청했다 — 서버는 미사용 행을 갈아 끼우므로 아직 살아 있던 tok-A 가 이 요청으로 죽는다")

    // ㉠ 점수가 살아 있다: 같은 토큰으로 재제출이 나갔거나, 스토어가 그 토큰을 그대로 들고 있다.
    // 재제출은 백오프(첫 단 2초) 뒤에 나가므로 그만큼은 기다려 준다 — 그 숫자는 서버가 준 값이 아니라 클라의 고정 간격이다.
    let retried = await slWait(upTo: 3) {
        slSubmits(host: host, score: 29).filter { ($0["p_token"] as? String) == "tok-A" }.count >= 2
    }
    let stillHeld = store.miniGameRoundToken == "tok-A" && store.miniGameRoundTokenKind == .flappy
    #expect(retried || stillHeld,
            Comment(rawValue: "too_fast 로 거절된 점수 29 와 토큰 tok-A 가 둘 다 사라졌다 — 재제출 \(retried), 보유 토큰 \(store.miniGameRoundToken ?? "nil")"))
}

// MARK: - ⑤ 서버가 token_used 를 준다 → "점수를 못 올렸어요" (거짓 경보)

/// 서버 계약: `used_at` 은 **점수를 표에 넣기 직전, 같은 트랜잭션 안에서만** 찍힌다. 그러니 `token_used` 는
/// "이 토큰의 점수는 이미 기록됐다"는 뜻이다(클라 불변: 한 토큰에 한 점수). 응답이 유실돼 재전송된 제출이
/// 이 답을 받는데, 기준선은 `else` 가지가 그걸 실패로 묶어 실패 문구를 띄웠다 — 잘 올라간 판을 두고
/// "못 올렸다"고 말하는 거짓 경보다(②를 고쳐 재시도가 생기면 이 답은 정상 경로가 된다).
@MainActor
@Test("token_used 는 이미 기록됐다는 뜻이라 실패 문구를 띄우지 않는다")
func tokenUsedMeansAlreadyRecordedNotAFailure() async {
    let host = "v0339-b5-token-used"
    let store = slStore(host: host)
    slArm(store, token: "tok-A")

    store.recordMiniGameScore(kind: .flappy, score: 29)
    #expect(await slWait { V0339GateURLProtocol.heldCount(host: host, containing: "minigame_submit_score") == 1 },
            "전제: 제출이 나갔다")
    V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score", json: slSubmitTokenUsed)
    await slSettle()

    #expect(store.miniGameSubmitNotice == nil,
            Comment(rawValue: "token_used(이미 기록됨)에 실패 문구를 띄운다 — \"\(store.miniGameSubmitNotice ?? "nil")\""))
}

// MARK: - 뿌리 원인: requestMiniGameRoundToken 에 "왕복 중" 가드가 없다

/// `hasUsableMiniGameToken` 은 **들고 있는 토큰**만 본다 — 나가 있는 요청은 모른다. 그래서 응답이 오기 전에
/// `beginMiniGameRound` · `prefetchMiniGameRoundToken` · `selectMiniGame` 가운데 누가 다시 부르면
/// `requestMiniGameRoundToken` 이 세대를 올려 앞 요청의 응답을 무효화하고 요청을 또 냈다.
/// 서버도 앞 행을 갈아 끼우므로(V0317 ⑤) 앞 응답을 버리는 것 자체는 맞다 — 문제는 **두 번째 요청이
/// 나간 것**이다. 진행 중이면 다시 안 내야 한다.
@MainActor
@Test("토큰 요청이 왕복 중이면 다시 부르는 쪽이 요청을 또 내지 않고, 먼저 나간 응답이 채택된다")
func aTokenRequestInFlightIsNotInvalidatedByASecondCaller() async {
    let host = "v0339-root-inflight"
    let store = slStore(host: host)
    #expect(store.miniGameRoundToken == nil)

    // 판 시작 → 요청 R1(보류).
    store.beginMiniGameRound(kind: .flappy)
    #expect(await slWait { V0339GateURLProtocol.heldCount(host: host, containing: "minigame_start_round") == 1 },
            "전제: 판 시작이 토큰을 요청했다")

    // R1 이 돌아오기 전에 선발급이 끼어든다(제출 완료 뒤의 그 호출).
    store.prefetchMiniGameRoundToken(kind: .flappy)
    await slSettle()
    let starts = V0339GateURLProtocol.count(host: host, containing: "minigame_start_round")
    #expect(starts == 1,
            Comment(rawValue: "진행 중인 토큰 요청이 있는데 또 냈다(\(starts)건) — 서버는 앞 행을 갈아 끼우고 클라는 앞 응답을 버린다: 둘 다 죽는 조합이다"))

    // R1 의 응답이 온다 — 채택돼야 한다.
    V0339GateURLProtocol.release(host: host, containing: "minigame_start_round", json: slToken("tok-R1"))
    let adopted = await slWait(upTo: 1) { store.miniGameRoundToken == "tok-R1" }
    #expect(adopted,
            Comment(rawValue: "먼저 나간 요청의 토큰이 버려졌다 — 세대가 뒤 요청에 밀렸다(보유 \(store.miniGameRoundToken ?? "nil"))"))
}

/// 위 가드 부재가 실사용에서 만들던 모양 — 사용자 진단의 순서를 그대로 밟는다:
///
///   판 A 끝 → recordMiniGameScore 가 토큰을 비우고 제출 Task 발사
///   결과 카드를 바로 클릭 → 판 B 시작 → beginMiniGameRound → 토큰 요청 R1(세대 N+1)
///   제출 Task 완료 → (순위 재조회) → prefetchMiniGameRoundToken → 쓸 토큰 없음 → 요청 R2(세대 N+2)
///   R1 응답 도착 → 세대가 밀렸으니 버려짐 → 판 B(즉사)는 그 사이에 끝나 토큰 없음 → 점수 소실(①)
///
/// 각 단계를 게이트로 강제하고, 마지막에 "판 B 의 점수가 제출됐는가"만 묻는다.
///
/// ⚠️ 판 B 시작에 대한 전제는 "요청이 **겹쳐** 나가지 않았다"(≤1)로 둔다 — 기준선은 여기서 R1 을 내고(1건), 수리 뒤에는
///    판 A 의 제출(tok-0)이 끝나기 전엔 그 게임의 `start_round` 를 **아예 내지 않는다**(0건 — 그 요청이 서버에서 tok-0 를
///    갈아 끼워 판 A 의 점수를 죽이기 때문이다). 둘 다 전제는 참이고, 갈리는 것은 그 뒤다.
@MainActor
@Test("짧은 판을 연달아 하면 토큰이 도착하지 못해 둘째 판 점수가 사라진다")
func consecutiveInstantRoundsStarveTheTokenAndLoseTheSecondScore() async {
    let host = "v0339-root-chain"
    let store = slStore(host: host)
    slArm(store, token: "tok-0")   // 창을 열 때 받아 둔 토큰(선발급)

    // 판 A: 쓸 수 있는 토큰이 있어 시작은 요청을 안 낸다(V0317 ⑥). 즉사 → 제출 S(tok-0) 발사, 토큰은 비워진다.
    store.beginMiniGameRound(kind: .flappy)
    store.recordMiniGameScore(kind: .flappy, score: 3)
    #expect(await slWait { V0339GateURLProtocol.heldCount(host: host, containing: "minigame_submit_score") == 1 },
            "전제: 판 A 제출이 나갔다")
    #expect(store.miniGameRoundToken == nil, "전제: 제출하며 토큰을 비웠다")

    // 결과 카드를 바로 클릭 → 판 B 시작. 토큰 요청은 있어도 한 건이어야 한다(기준선 1건 · 수리 뒤 0건 — 머리 주석).
    store.beginMiniGameRound(kind: .flappy)
    await slSettle()
    #expect(V0339GateURLProtocol.heldCount(host: host, containing: "minigame_start_round") <= 1,
            "전제: 판 B 시작이 토큰 요청을 겹쳐 내지 않았다")

    // 제출 S 완료(ok) → 순위 재조회(즉시 []) → 선발급. 여기서 두 번째 요청이 나가면 가설이 성립한 것이다.
    V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score", json: slSubmitOK)
    let secondRequestWentOut = await slWait(upTo: 1) {
        V0339GateURLProtocol.count(host: host, containing: "minigame_start_round") >= 2
    }

    // 가장 오래된 토큰 응답이 온다. 두 번째 요청이 나갔다면 세대가 밀려 버려진다.
    V0339GateURLProtocol.release(host: host, containing: "minigame_start_round", json: slToken("tok-R1"))
    await slSettle()
    let tokenWhenRoundBEnds = store.miniGameRoundToken

    // 판 B 즉사 — 두 번째 요청(있다면)은 아직 안 왔다.
    store.recordMiniGameScore(kind: .flappy, score: 2)
    // 이제 남은 요청도 전부 답한다(늦게라도 토큰은 온다 — 토큰 없음 경로가 또 낸 요청까지 되풀이해 연다).
    _ = await slDeliverToken(host: host, store: store, token: "tok-R2")

    let landed = await slWait(upTo: 2) { !slSubmits(host: host, score: 2).isEmpty }
    #expect(landed,
            Comment(rawValue: "짧은 판을 연달아 하자 둘째 판 점수가 사라졌다 — 판 B 끝 시점 토큰=\(tokenWhenRoundBEnds ?? "nil"), start_round \(V0339GateURLProtocol.count(host: host, containing: "minigame_start_round"))건(제출 완료의 선발급이 판 시작 요청을 무효화했다: \(secondRequestWentOut))"))
    #expect(!secondRequestWentOut,
            "제출 완료 뒤 선발급이 **진행 중인** 판 시작 요청을 무효화하는 두 번째 요청을 냈다 — 왕복 중 가드가 없다")
}
