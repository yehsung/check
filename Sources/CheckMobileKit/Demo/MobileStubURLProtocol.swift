#if DEBUG
import Foundation

/// 스텁이 받은 요청 한 건(경로 · 메서드 · 쿼리 · 본문).
package struct MobileStubRequest: Sendable, Equatable {
    package let method: String
    package let host: String
    package let path: String
    package let query: String
    package let headers: [String: String]
    package let bodyText: String

    /// `/rest/v1/rpc/<name>` 이면 name.
    package var rpcName: String? {
        let prefix = "/rest/v1/rpc/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }

    /// 쿼리 항목 하나(예: scope=local).
    package func queryValue(_ name: String) -> String? {
        URLComponents(string: "https://x/?\(query)")?.queryItems?.first { $0.name == name }?.value
    }
}

/// 스텁 응답.
package struct MobileStubResponse: Sendable {
    package var status: Int
    package var body: Data
    /// 응답을 늦출 초(경합 재현).
    package var delay: TimeInterval
    /// 값이 있으면 HTTP 응답 대신 이 `URLError` 로 실패한다(오프라인·연결 끊김 재현).
    package var failure: URLError.Code?

    package init(status: Int = 200, body: Data, delay: TimeInterval = 0, failure: URLError.Code? = nil) {
        self.status = status
        self.body = body
        self.delay = delay
        self.failure = failure
    }

    package static func json(_ text: String, status: Int = 200, delay: TimeInterval = 0) -> MobileStubResponse {
        MobileStubResponse(status: status, body: Data(text.utf8), delay: delay)
    }

    /// 네트워크 실패(기본: 인터넷 연결 없음). 서비스는 `URLError` 를 그대로 던진다 — 일시 오류(`AuthErrorRules` .transient).
    package static func networkFailure(_ code: URLError.Code = .notConnectedToInternet, delay: TimeInterval = 0) -> MobileStubResponse {
        MobileStubResponse(status: 0, body: Data(), delay: delay, failure: code)
    }

    /// PostgREST 가 함수·표를 못 찾을 때의 모양(서비스가 `.databaseSchemaMissing` 으로 접는다).
    package static func missingFunction(_ name: String) -> MobileStubResponse {
        .json(#"{"code":"PGRST202","message":"Could not find the function public.\#(name) in the schema cache"}"#, status: 404)
    }
}

/// **호스트별** 스텁 서버(DEBUG 전용 — Release 에서 컴파일되지 않는다). 데모 모드와 `CheckMobileKitTests` 가 함께 쓴다.
///
/// 호스트마다 응답기를 등록하므로 병렬로 도는 테스트가 서로의 응답·기록을 보지 않는다(테스트마다 고유 호스트를 쓴다).
/// 모든 요청은 기록되고, `MobileForbiddenCalls.violations(in:)` 로 폰 금지 호출 0건을 단언한다.
package final class MobileStubURLProtocol: URLProtocol, @unchecked Sendable {
    package typealias Responder = @Sendable (MobileStubRequest) -> MobileStubResponse

    private static let lock = NSLock()
    private nonisolated(unsafe) static var responders: [String: Responder] = [:]
    private nonisolated(unsafe) static var recorded: [String: [MobileStubRequest]] = [:]

    /// 이 호스트의 응답기를 등록한다(같은 호스트면 바꾼다). 기록은 지우지 않는다.
    package static func register(host: String, responder: @escaping Responder) {
        lock.lock(); defer { lock.unlock() }
        responders[host] = responder
    }

    package static func unregister(host: String) {
        lock.lock(); defer { lock.unlock() }
        responders[host] = nil
        recorded[host] = nil
    }

    package static func requests(host: String) -> [MobileStubRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded[host] ?? []
    }

    package static func clearRequests(host: String) {
        lock.lock(); defer { lock.unlock() }
        recorded[host] = []
    }

    /// 이 프로토콜만 거치는 세션(캐시 없음).
    package static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MobileStubURLProtocol.self]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    override package class func canInit(with request: URLRequest) -> Bool { true }

    override package class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private let stateLock = NSLock()
    private nonisolated(unsafe) var stopped = false

    override package func startLoading() {
        let url = request.url
        let host = url?.host ?? ""
        let stubRequest = MobileStubRequest(
            method: request.httpMethod ?? "GET",
            host: host,
            path: url?.path ?? "",
            query: url?.query ?? "",
            headers: request.allHTTPHeaderFields ?? [:],
            bodyText: Self.bodyText(of: request)
        )
        let responder: Responder? = {
            Self.lock.lock(); defer { Self.lock.unlock() }
            Self.recorded[host, default: []].append(stubRequest)
            return Self.responders[host]
        }()
        let response = responder?(stubRequest) ?? .json(#"{"message":"no stub for host"}"#, status: 599)
        let http = HTTPURLResponse(
            url: url ?? URL(string: "https://stub.invalid")!,
            statusCode: response.failure == nil ? response.status : 599,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        let deliver: @Sendable () -> Void = { [self] in
            stateLock.lock()
            let isStopped = stopped
            stateLock.unlock()
            guard !isStopped else { return }
            if let failure = response.failure {
                client?.urlProtocol(self, didFailWithError: URLError(failure))
                return
            }
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        if response.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + response.delay, execute: deliver)
        } else {
            deliver()
        }
    }

    override package func stopLoading() {
        stateLock.lock()
        stopped = true
        stateLock.unlock()
    }

    private static func bodyText(of request: URLRequest) -> String {
        if let body = request.httpBody {
            return String(decoding: body, as: UTF8.self)
        }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// 폰이 **절대 부르면 안 되는** 서버 호출 판정(SPEC-ios §0-2 · ios-inventory §3). 스토어 시나리오 테스트 끝에
/// `#expect(MobileForbiddenCalls.violations(in: MobileStubURLProtocol.requests(host: host)).isEmpty)` 로 단언한다.
package enum MobileForbiddenCalls {
    /// 이름만으로 금지인 RPC.
    package static let forbiddenRPCs: Set<String> = [
        "take_pokes", "work_tick", "close_abandoned_work_sessions", "ultra_wallet_sync", "buy_ultra",
        "poke_user", "ultra_poke_user", "away_sync", "join_team", "create_team",
    ]
    /// 읽기(GET) 말고는 금지인 표(근무·기기 상태·토큰 원장).
    package static let readOnlyTables: Set<String> = [
        "work_sessions", "work_statuses", "work_status_devices",
        "token_usage_device_monthly", "token_usage_device_daily", "token_usage_monthly",
    ]
    /// profiles PATCH 본문에 실리면 금지인 칸(맥 빌드·집중 모드).
    package static let forbiddenProfileColumns: [String] = ["app_build", "app_version", "focus_mode"]

    /// 위반이면 사람이 읽는 한 줄, 아니면 nil.
    package static func violation(_ request: MobileStubRequest) -> String? {
        if let rpc = request.rpcName {
            return forbiddenRPCs.contains(rpc) ? "\(request.method) rpc/\(rpc)" : nil
        }
        let restPrefix = "/rest/v1/"
        guard request.path.hasPrefix(restPrefix) else { return nil }
        let table = String(request.path.dropFirst(restPrefix.count)).split(separator: "/").first.map(String.init) ?? ""
        if readOnlyTables.contains(table), request.method.uppercased() != "GET" {
            return "\(request.method) \(table)"
        }
        if table == "profiles", request.method.uppercased() != "GET" {
            for column in forbiddenProfileColumns where request.bodyText.contains("\"\(column)\"") {
                return "\(request.method) profiles.\(column)"
            }
        }
        return nil
    }

    package static func violations(in requests: [MobileStubRequest]) -> [String] {
        requests.compactMap(violation)
    }
}
#endif
