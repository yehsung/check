import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 부하 내성 도우미(harden). **벽시계로 기다리지 않는다.**
//
// 맥+폰 전체 스위트(약 2,800개)는 메인 액터를 포화시킨다 — 480~680초 구간에서 폰 테스트가 무더기로 빨개졌고, 대기가 실패한 뒤
// 배열을 인덱스로 읽은 곳이 테스트 프로세스를 통째로 죽여 뒤의 1천여 개가 돌지 않았다. 원인은 셋이었다.
//   ① 벽시계 마감 대기(`timeout: 5`): 스토어가 메인 액터 차례를 한 번 받기도 전에 마감이 지났다.
//   ② 고정 잠(`Task.sleep(50ms)`) 뒤 "일어났다/안 일어났다" 단언: 50ms 안에 일어날 일이 포화에선 몇 초 뒤에 일어난다.
//   ③ 스텁 지연(`delay: 0.3`)으로 짠 사건 순서: 지연보다 테스트 쪽 사건이 늦게 돌아 순서가 뒤집혔다.
// 여기 도우미는 각각을 ① 재개 횟수 상한 ② 명시 신호·사건 장벽 ③ 응답 붙잡기로 바꾼다.

// MARK: - ① 재개 횟수 대기

/// 대기 한 차례 = 5ms 잠 한 번의 **재개**(맥 V0328 `chatWait` 관용). 벽시계가 아니라 차례로 센다 — 기다리는 쪽도 스토어와 같은 메인
/// 액터 줄에 서므로 포화만큼 함께 늘어난다. 12,000 차례 = 한가할 때 60초 이상(성공 경로는 조건이 서는 즉시 돌아온다).
let baseWaitTurns = 12_000

@MainActor
func baseWaitUntil(
    turns: Int = baseWaitTurns,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @MainActor () -> Bool
) async -> Bool {
    for _ in 0..<turns {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    if condition() { return true }
    // 통과한 테스트 안의 `_ = await baseWaitUntil` 이 상한까지 돈 것을 로그로 찾을 수 있게(조건이 끝내 안 선 대기).
    print("BASE-WAIT-EXHAUSTED \(sourceLocation.fileID):\(sourceLocation.line) turns=\(turns)")
    return false
}

/// 메인 액터에 이미 줄 선 일을 먼저 돌린다: `turns` 차례 동안 5ms 잠의 재개를 반복한다(조건 없음).
/// 제품 쪽 벽시계 타이머에만 기대는 "안 일어났음"(주입할 시계가 없는 곳)을 재는 창으로만 쓴다 — 창의 길이가 부하와 함께 늘어난다.
@MainActor
func baseYield(turns: Int = 4) async {
    for _ in 0..<turns {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

// MARK: - ② 사건 장벽

/// 장벽 요청이 쓰는 경로. 스텁 기본 응답은 404 — 서비스가 던지고 장벽은 삼킨다. 하네스의 요청 목록은 이 경로를 걸러 낸다.
let baseBarrierPath = "/rest/v1/__test_barrier"

/// 사건 순서 장벽: 같은 서비스 액터·같은 URLSession(델리게이트 큐는 직렬)을 한 바퀴 도는 요청 하나.
///
/// 앞서 떠난 요청은 이보다 먼저 스텁에 기록되고, 앞서 도착한 응답의 이어짐은 이보다 먼저 메인 액터에서 돈다. "안 일어났음"·"늦은 응답을
/// 버렸음"을 고정 잠 대신 이 장벽 **뒤에** 단언한다. 먼저 몇 차례 양보해 이미 줄 선 `Task { }` 가 서비스에 닿게 한다.
@MainActor
func baseBarrier(_ service: SupabaseWorkService, yields: Int = 8) async {
    for _ in 0..<yields { await Task.yield() }
    _ = try? await service.send(path: baseBarrierPath, method: "GET", body: Optional<BaseNoBody>.none, accessToken: nil, prefer: nil)
    for _ in 0..<yields { await Task.yield() }
}

/// 스텁 기록에서 장벽 요청을 뺀 목록.
func baseRequests(host: String) -> [MobileStubRequest] {
    MobileStubURLProtocol.requests(host: host).filter { $0.path != baseBarrierPath }
}

// MARK: - 비동기 문

/// 테스트가 여는 문. 가짜 시스템 콜백·주입한 잠(`MessagesStore.sleep`)이 벽시계 대신 이 문을 기다린다.
final class BaseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var arrivalCount = 0

    /// 문 앞에 도착한 수(열린 뒤 곧바로 지나간 것 포함).
    var arrivals: Int {
        lock.lock(); defer { lock.unlock() }
        return arrivalCount
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            arrivalCount += 1
            if isOpen {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let pending = waiters
        waiters = []
        lock.unlock()
        for waiter in pending { waiter.resume() }
    }
}

// MARK: - ③ 응답 붙잡기

/// 응답 붙잡기: 이 호스트에서 `matches` 가 참인 처음 `limit` 개 요청을 **테스트가 놓아줄 때까지** 붙잡는다.
///
/// 벽시계 지연으로 "이 응답은 저 사건보다 늦게 온다"를 흉내 내면 포화에서 순서가 뒤집힌다. 붙잡으면 순서가 사건으로 정해진다.
/// 붙잡힌 요청은 놓아줄 때 스텁(`MobileStubURLProtocol`)으로 넘어가므로 **스텁 기록에는 놓아준 뒤에 나타난다** — 도착은 `held` 로 센다.
/// 하네스 테어다운(`BaseStub.tearDown`)이 남은 붙잡기를 모두 놓는다.
final class BaseHold: @unchecked Sendable {
    enum Claim {
        case notMine
        case parked
        case passThrough
    }

    let host: String
    private let matches: @Sendable (MobileStubRequest) -> Bool
    private let limit: Int
    private let lock = NSLock()
    private var claimedCount = 0
    private var finishedCount = 0
    private var deliveredCount = 0
    private var isReleased = false
    private var parked: [BaseHoldURLProtocol] = []

    private init(host: String, limit: Int, matches: @escaping @Sendable (MobileStubRequest) -> Bool) {
        self.host = host
        self.limit = limit
        self.matches = matches
    }

    /// 이 호스트의 요청 중 `matches` 가 참인 처음 `limit` 개를 붙잡는다.
    @discardableResult
    static func install(host: String, limit: Int = 1, _ matches: @escaping @Sendable (MobileStubRequest) -> Bool) -> BaseHold {
        let hold = BaseHold(host: host, limit: limit, matches: matches)
        BaseHoldURLProtocol.install(hold)
        return hold
    }

    /// RPC 이름으로 붙잡는다.
    @discardableResult
    static func rpc(_ name: String, host: String, limit: Int = 1) -> BaseHold {
        install(host: host, limit: limit) { $0.rpcName == name }
    }

    /// 도착한(붙잡힌) 요청 수.
    var held: Int {
        lock.lock(); defer { lock.unlock() }
        return claimedCount
    }

    /// 응답을 넘겼거나(성공·실패) 요청이 취소된 수.
    var finished: Int {
        lock.lock(); defer { lock.unlock() }
        return finishedCount
    }

    /// 취소되지 않고 응답(성공·실패)을 클라이언트에 넘긴 수.
    var delivered: Int {
        lock.lock(); defer { lock.unlock() }
        return deliveredCount
    }

    var acceptsMore: Bool {
        lock.lock(); defer { lock.unlock() }
        return claimedCount < limit
    }

    /// 붙잡힌 요청이 `count` 개가 될 때까지(재개 횟수 대기).
    @MainActor
    func waitHeld(_ count: Int = 1, sourceLocation: SourceLocation = #_sourceLocation) async -> Bool {
        await baseWaitUntil(sourceLocation: sourceLocation) { self.held >= count }
    }

    /// 놓아준다(붙잡힌 것은 곧바로 스텁으로, 앞으로 올 것은 붙잡지 않고 통과 — 상한까지는 `held` 로 센다).
    func release() {
        lock.lock()
        isReleased = true
        let list = parked
        parked = []
        lock.unlock()
        for request in list { request.forward() }
    }

    /// 놓아주고, 붙잡혔던 요청의 응답이 모두 URL 로딩 계층에 넘어갈 때까지. 스토어가 그 응답을 메인 액터에서 처리한 것까지 보려면
    /// 그 작업의 핸들을 기다리거나 `baseBarrier` 를 뒤에 둔다.
    @MainActor
    func releaseAndWaitDelivered(sourceLocation: SourceLocation = #_sourceLocation) async -> Bool {
        release()
        return await baseWaitUntil(sourceLocation: sourceLocation) { self.finished >= self.held }
    }

    fileprivate func claim(_ request: BaseHoldURLProtocol, stub: MobileStubRequest) -> Claim {
        guard matches(stub) else { return .notMine }
        lock.lock()
        defer { lock.unlock() }
        guard claimedCount < limit else { return .notMine }
        claimedCount += 1
        if isReleased { return .passThrough }
        parked.append(request)
        return .parked
    }

    /// 붙잡힌 채 취소됐으면 목록에서 빼고 끝난 것으로 센다(true).
    fileprivate func unpark(_ request: BaseHoldURLProtocol) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = parked.firstIndex(where: { $0 === request }) else { return false }
        parked.remove(at: index)
        finishedCount += 1
        return true
    }

    fileprivate func noteFinished(delivered: Bool = false) {
        lock.lock()
        finishedCount += 1
        if delivered { deliveredCount += 1 }
        lock.unlock()
    }
}

/// `BaseHold` 를 스텁 **앞에** 세우는 URL 프로토콜. 붙잡기가 걸린 호스트만 가로채고(`canInit`), 붙잡지 않을 요청은 곧바로 스텁 세션으로
/// 넘긴다. 제품 코드(`MobileStubURLProtocol`)는 건드리지 않는다.
final class BaseHoldURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var holds: [String: [BaseHold]] = [:]
    /// 넘길 때 쓰는 스텁 전용 세션(이 프로토콜은 없다 — 다시 가로채지 않는다).
    private static let forwardSession = MobileStubURLProtocol.makeSession()

    /// 이 프로토콜 → 스텁 순서로 거치는 세션(캐시 없음).
    ///
    /// 요청 타임아웃을 넉넉히 연다: ephemeral 기본 60초는 **벽시계**라, 포화한 전체 스위트에서 붙잡힌 요청이 테스트가 놓기 전에
    /// `timedOut` 으로 끝나 "아직 떠 있다"는 전제가 뒤집혔다(부하 실행 1회차 PushBadgeTests — 복원이 client_release 실패로 넘어감).
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3_600
        configuration.timeoutIntervalForResource = 3_600
        configuration.protocolClasses = [BaseHoldURLProtocol.self, MobileStubURLProtocol.self]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    static func install(_ hold: BaseHold) {
        lock.lock(); defer { lock.unlock() }
        holds[hold.host, default: []].append(hold)
    }

    /// 이 호스트의 붙잡기를 모두 풀고 놓는다(테어다운).
    static func uninstall(host: String) {
        lock.lock()
        let list = holds.removeValue(forKey: host) ?? []
        lock.unlock()
        for hold in list { hold.release() }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        lock.lock()
        let list = holds[host] ?? []
        lock.unlock()
        return list.contains { $0.acceptsMore }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private let stateLock = NSLock()
    private nonisolated(unsafe) var body = Data()
    private nonisolated(unsafe) var forwardTask: URLSessionDataTask?
    private nonisolated(unsafe) var stopped = false
    private nonisolated(unsafe) var owner: BaseHold?

    override func startLoading() {
        let data = Self.bodyData(of: request)
        let url = request.url
        let stub = MobileStubRequest(
            method: request.httpMethod ?? "GET",
            host: url?.host ?? "",
            path: url?.path ?? "",
            query: url?.query ?? "",
            headers: request.allHTTPHeaderFields ?? [:],
            bodyText: String(decoding: data, as: UTF8.self)
        )
        stateLock.lock()
        body = data
        stateLock.unlock()
        let candidates: [BaseHold] = {
            Self.lock.lock(); defer { Self.lock.unlock() }
            return Self.holds[stub.host] ?? []
        }()
        for hold in candidates {
            switch hold.claim(self, stub: stub) {
            case .notMine:
                continue
            case .parked:
                stateLock.lock(); owner = hold; stateLock.unlock()
                return
            case .passThrough:
                stateLock.lock(); owner = hold; stateLock.unlock()
                forward()
                return
            }
        }
        forward()
    }

    /// 스텁 세션으로 넘기고, 받은 응답을 그대로 이 요청의 클라이언트에 옮긴다.
    func forward() {
        stateLock.lock()
        if stopped {
            let hold = owner
            stateLock.unlock()
            hold?.noteFinished()
            return
        }
        var forwarded = request
        forwarded.httpBodyStream = nil
        forwarded.httpBody = body.isEmpty ? nil : body
        let task = Self.forwardSession.dataTask(with: forwarded) { [self] data, response, error in
            self.deliver(data: data, response: response, error: error)
        }
        forwardTask = task
        stateLock.unlock()
        task.resume()
    }

    private func deliver(data: Data?, response: URLResponse?, error: Error?) {
        stateLock.lock()
        let isStopped = stopped
        let hold = owner
        stateLock.unlock()
        defer { hold?.noteFinished(delivered: !isStopped) }
        guard !isStopped else { return }
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if let data {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        stateLock.lock()
        stopped = true
        let task = forwardTask
        let hold = owner
        stateLock.unlock()
        if let task {
            task.cancel()
        } else if let hold {
            _ = hold.unpark(self)
        }
    }

    private static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
