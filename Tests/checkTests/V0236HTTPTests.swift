import Foundation
import Testing
@testable import check

// MARK: - v0.2.36 HTTP/Service 전용 스텁
//
// 공유 URLProtocolStub 을 고치지 않는 이유(재설정 스위트와 같은 결정):
// (1) 그 파일은 이 트랙의 소유가 아니다(동시에 다른 트랙이 편집 중이다).
// (2) 이 스위트는 "같은 경로가 첫 호출엔 5xx/429, 다음 호출엔 200" 같은 **호출 차수 의존** 응답과
//     PATCH 의 representation 본문(0행/1행)을 시나리오별로 쥐어야 하는데, 공유 스텁은 그 축이 없다.
// 호스트 이름이 시나리오를 고르는 규약은 공유 스텁과 같다(전부 "v0236-" 접두어라 다른 스위트와 못 섞인다).
final class V0236HTTPURLProtocol: URLProtocol {
    static let userID = "00000000-0000-0000-0000-000000000002"
    static let teamID = "10000000-0000-0000-0000-000000000001"
    /// 이 맥이 닫으려는 **내** 세션(= stop 경로가 항상 들고 있는 fallbackSessionID).
    static let mySessionID = "44440000-0000-0000-0000-000000000001"
    /// 그 사이 다른 맥이 연 **새** 세션. 어떤 발신 요청도 이 id 를 입에 올리면 안 된다.
    static let otherSessionID = "44440000-0000-0000-0000-000000000002"

    // 실측 GoTrue 본문 모양 그대로(msg/message 폴딩이 실제로 일어나는 조건을 재현해야 게이트가 검증된다).
    static let gotrue503Body = #"{"code":503,"msg":"Service temporarily unavailable"}"#
    static let gotrue429GenericBody = #"{"code":429,"error_code":"over_request_rate_limit","msg":"Request rate limit reached"}"#
    static let gotrue429SecondsBody = #"{"code":429,"error_code":"over_email_send_rate_limit","msg":"For security purposes, you can only request this after 51 seconds."}"#
    static let invalidGrantBody = #"{"error":"invalid_grant","error_description":"Invalid Refresh Token: Already Used"}"#

    private nonisolated(unsafe) static var recorded: [(request: URLRequest, body: String)] = []
    private static let stateLock = NSLock()

    static func requests(forHost host: String) -> [URLRequest] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return recorded.map(\.request).filter { $0.url?.host == host }
    }

    /// 요청-본문 쌍(발사 순서). "발신 요청 전수 검사"가 쿼리와 본문을 함께 봐야 해서 쌍으로 돌려준다.
    static func exchanges(forHost host: String) -> [(request: URLRequest, body: String)] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return recorded.filter { $0.request.url?.host == host }
    }

    /// 그 호스트+경로의 몇 번째 호출인지(현재 요청 포함). "첫 갱신만 5xx" 시나리오의 축이다.
    private static func callCount(host: String, path: String) -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return recorded.filter { $0.request.url?.host == host && $0.request.url?.path == path }.count
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        Self.stateLock.lock()
        Self.recorded.append((request: request, body: Self.bodyText(from: request)))
        Self.stateLock.unlock()

        let (statusCode, body) = Self.outcome(
            host: host,
            path: path,
            method: request.httpMethod ?? "",
            count: Self.callCount(host: host, path: path)
        )
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func outcome(host: String, path: String, method: String, count: Int) -> (Int, String) {
        if path == "/auth/v1/token" {
            // 첫 grant 만 장애를 주고 다음은 성공시킨다 — "일시 장애 후 다음 주기의 재시도가 산다"의 재현.
            if host.contains("refresh-503"), count == 1 { return (503, gotrue503Body) }
            if host.contains("refresh-429"), count == 1 { return (429, gotrue429GenericBody) }
            if host.contains("invalid-grant") { return (400, invalidGrantBody) }
            return (200, """
            {
              "access_token": "refreshed-access",
              "refresh_token": "refresh-2",
              "user": { "id": "\(userID)" }
            }
            """)
        }
        if path == "/auth/v1/recover", host.contains("reset-ratelimit") {
            return (429, gotrue429SecondsBody)
        }
        if path == "/rest/v1/work_sessions", method == "PATCH" {
            // 사유 컬럼이 없는 구스키마 서버 재현: 첫 PATCH(auto_closed_* null 포함)만 PGRST204 로 거절 —
            // withoutNewColumns 가 잔재 정리를 뺀 본문으로 재시도해 되돌리기 자체는 살아남아야 한다.
            if host.contains("reopen-legacy"), count == 1 {
                return (400, #"{"code":"PGRST204","message":"Could not find the 'auto_closed_at' column of 'work_sessions' in the schema cache"}"#)
            }
            // 정상 마감: id 필터가 내 열린 세션 1행을 명중한다(representation).
            if host.contains("stop-normal") {
                return (200, """
                [
                  {
                    "id": "\(mySessionID)",
                    "user_id": "\(userID)",
                    "started_at": "2026-08-24T20:00:00Z",
                    "ended_at": "2026-08-24T21:00:00Z",
                    "duration_seconds": 3600
                  }
                ]
                """)
            }
            // 내 세션은 서버에 없고 다른 맥의 새 세션만 열려 있다 → id 필터라 무엇도 안 맞는 0행.
            return (200, "[]")
        }
        if path == "/rest/v1/work_sessions", method == "POST" {
            return (201, "")
        }
        return (200, "[]")
    }

    private static func bodyText(from request: URLRequest) -> String {
        if let body = request.httpBody {
            return String(decoding: body, as: UTF8.self)
        }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private func v0236Service(host: String) -> SupabaseWorkService {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [V0236HTTPURLProtocol.self]
    return SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: configuration)
    )
}

@MainActor
private func v0236Store(host: String) -> WorkTimerStore {
    let suiteName = "check-v0236-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return WorkTimerStore(
        service: v0236Service(host: host),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )
}

private func v0236QueryItems(_ request: URLRequest) throws -> [URLQueryItem] {
    let url = try #require(request.url)
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
}

// MARK: - 스위트

@Suite struct V0236HTTPTests {

    // MARK: F2 — serviceError 상태코드 게이트(5xx/429 는 본문 메시지 폴딩보다 먼저)

    /// H2 의 심장: GoTrue 5xx 는 본문에 msg 가 있어도 .authMessage(=fatal)가 아니라
    /// .invalidResponse(5xx)(=transient)여야 한다. 429 도 같은 이유로 .rateLimited 다.
    @Test func serviceErrorGates5xxBeforeBodyMessageFolding() async {
        let service = v0236Service(host: "v0236-unit")

        let body503 = Data(V0236HTTPURLProtocol.gotrue503Body.utf8)
        #expect(await service.serviceError(statusCode: 503, data: body503) == .invalidResponse(503))
        // 500/502 도 같은 게이트를 지난다(무료플랜 일시정지는 코드가 고정돼 있지 않다).
        #expect(await service.serviceError(statusCode: 502, data: body503) == .invalidResponse(502))
    }

    @Test func serviceErrorGates429ToRateLimitedWithParsedSeconds() async {
        let service = v0236Service(host: "v0236-unit")

        // 초를 담은 본문 → 그 초. 파서는 passwordRecoveryError 와 **같은 것**을 쓴다(갈리면 경로별로 초가 달라진다).
        let withSeconds = Data(V0236HTTPURLProtocol.gotrue429SecondsBody.utf8)
        #expect(await service.serviceError(statusCode: 429, data: withSeconds) == .rateLimited(retryAfterSeconds: 51))
        // 초가 없는 본문/빈 본문 → nil (0으로 지어내면 재시도 버튼이 바로 열려 429 를 다시 부른다).
        let generic = Data(V0236HTTPURLProtocol.gotrue429GenericBody.utf8)
        #expect(await service.serviceError(statusCode: 429, data: generic) == .rateLimited(retryAfterSeconds: nil))
        #expect(await service.serviceError(statusCode: 429, data: Data()) == .rateLimited(retryAfterSeconds: nil))
    }

    /// 게이트가 4xx 의 의미를 침식하지 않는다: 400 invalid_grant(회전 실패)는 여전히 fatal 쪽 분류다.
    @Test func serviceErrorKeeps4xxContractsIntact() async {
        let service = v0236Service(host: "v0236-unit")

        let invalidGrant = Data(V0236HTTPURLProtocol.invalidGrantBody.utf8)
        #expect(await service.serviceError(statusCode: 400, data: invalidGrant) == .sessionExpired)
        // 401 빈 본문 → sessionExpired (기존 계약 그대로).
        #expect(await service.serviceError(statusCode: 401, data: Data()) == .sessionExpired)
    }

    /// 게이트가 던지는 두 모양이 classifyAuthError 의 transient 분기에 **실제로** 닿는다
    /// (이 다리가 없으면 게이트는 모양만 바꾼 fatal 이다).
    @MainActor @Test func gatedErrorsClassifyAsTransientNotFatal() {
        let store = v0236Store(host: "v0236-classify")

        #expect(store.classifyAuthError(SupabaseWorkServiceError.invalidResponse(503)) == .transient)
        #expect(store.classifyAuthError(SupabaseWorkServiceError.invalidResponse(529)) == .transient)
        #expect(store.classifyAuthError(SupabaseWorkServiceError.rateLimited(retryAfterSeconds: nil)) == .transient)
        // 진짜 만료는 여전히 fatal — 게이트가 로그아웃 자체를 없애는 것이 아니다.
        #expect(store.classifyAuthError(SupabaseWorkServiceError.sessionExpired) == .fatal)
    }

    /// (a) refresh grant 가 503 을 맞아도 강제 로그아웃하지 않고, 다음 주기의 재시도가 살아서 갱신에 성공한다.
    @MainActor @Test func refreshGrant503KeepsSessionAndNextRetrySucceeds() async throws {
        let store = v0236Store(host: "v0236-refresh-503")
        store.session = SupabaseSession(accessToken: "old-access", refreshToken: "refresh-1", userID: V0236HTTPURLProtocol.userID)
        let generationBefore = store.sessionGeneration

        // 만료 토큰 → 갱신 시도 → 스텁의 첫 grant 는 503. 원 오류는 그대로 던져지되 세션은 살아야 한다.
        await #expect(throws: SupabaseWorkServiceError.sessionExpired) {
            _ = try await store.withSessionRetry { session -> String in
                if session.accessToken == "old-access" { throw SupabaseWorkServiceError.sessionExpired }
                return session.accessToken
            }
        }
        #expect(store.session?.refreshToken == "refresh-1")
        #expect(store.sessionGeneration == generationBefore) // clearPersistedSession 은 세대를 올린다 — 안 올랐어야 한다
        #expect(store.syncMessage != "다시 로그인 필요")

        // 다음 주기: 스텁의 두 번째 grant 는 200 — 같은 refresh token 으로 갱신이 성사되고 작업이 새 토큰으로 재실행된다.
        let token = try await store.withSessionRetry { session -> String in
            if session.accessToken == "old-access" { throw SupabaseWorkServiceError.sessionExpired }
            return session.accessToken
        }
        #expect(token == "refreshed-access")
        #expect(store.session?.accessToken == "refreshed-access")
    }

    /// (b) refresh grant 가 429(레이트리밋)를 맞아도 (a)와 동일하게 세션 유지 + 이후 재시도 생존.
    @MainActor @Test func refreshGrant429KeepsSessionAndNextRetrySucceeds() async throws {
        let store = v0236Store(host: "v0236-refresh-429")
        store.session = SupabaseSession(accessToken: "old-access", refreshToken: "refresh-1", userID: V0236HTTPURLProtocol.userID)
        let generationBefore = store.sessionGeneration

        await #expect(throws: SupabaseWorkServiceError.sessionExpired) {
            _ = try await store.withSessionRetry { session -> String in
                if session.accessToken == "old-access" { throw SupabaseWorkServiceError.sessionExpired }
                return session.accessToken
            }
        }
        #expect(store.session?.refreshToken == "refresh-1")
        #expect(store.sessionGeneration == generationBefore)

        let token = try await store.withSessionRetry { session -> String in
            if session.accessToken == "old-access" { throw SupabaseWorkServiceError.sessionExpired }
            return session.accessToken
        }
        #expect(token == "refreshed-access")
    }

    /// (c) 400 invalid_grant(회전 실패)는 **여전히** 강제 로그아웃이다 — 게이트가 기존 fatal 계약을 넓히지 않았다.
    @MainActor @Test func refreshGrantInvalidGrantStillLogsOut() async {
        let store = v0236Store(host: "v0236-refresh-invalid-grant")
        store.session = SupabaseSession(accessToken: "old-access", refreshToken: "refresh-dead", userID: V0236HTTPURLProtocol.userID)

        await #expect(throws: SupabaseWorkServiceError.sessionExpired) {
            _ = try await store.withSessionRetry { _ -> String in
                throw SupabaseWorkServiceError.sessionExpired
            }
        }
        #expect(store.session == nil)
        #expect(store.syncMessage == "다시 로그인 필요")
    }

    /// (d) 비밀번호 재설정의 429 문구·서버 초 계약 회귀 없음: 게이트가 429 를 .rateLimited 로 직접 접어도
    /// 재설정 화면은 여전히 "이미 보냈어요" + 서버가 준 51초 쿨다운으로 간다.
    @MainActor @Test func passwordResetRateLimitStillShowsAlreadySentWithServerSeconds() async {
        let store = v0236Store(host: "v0236-reset-ratelimit")
        // 시계를 얼려 카운트다운이 흐르지 않게 한다 — 남은 초 단언이 스위트 부하와 무관해진다.
        // 수면은 취소에 반응하는 짧은 폴링이라 테스트 종료 시 배경 Task 가 남지 않는다(아래 cancel 이 내린다).
        let frozen = Date()
        store.clock = { frozen }
        store.passwordResetSleep = { _ in try? await Task.sleep(for: .milliseconds(5)) }

        store.beginPasswordReset(email: "member@example.com")
        await store.requestPasswordResetCode(email: "member@example.com")

        // 429 = "방금 이미 보냈다" — 코드 입력 화면 + 기존 문구 + 서버가 말한 51초가 그대로 쿨다운이 된다.
        #expect(store.passwordResetPhase == .enterCode)
        #expect(store.passwordResetMessage == WorkTimerStore.passwordResetAlreadySentMessage)
        #expect(store.passwordResetResendSeconds == 51)
        store.cancelPasswordReset() // 카운트다운 Task 를 그 자리에서 내린다(잔여 Task 금지)
    }

    // MARK: F6 — stopWork PATCH 의 세션 id 필터(다른 맥의 새 세션 오폭 금지)

    /// (1)+(3) 정상 마감: PATCH 가 id=eq.<내 세션> 필터를 갖고, 1행이 맞으면 폴백 POST 는 없다.
    @Test func stopWorkPatchCarriesSessionIDFilterAndNormalCloseSkipsFallback() async throws {
        let host = "v0236-stop-normal"
        let service = v0236Service(host: host)
        let formatter = ISO8601DateFormatter()
        let startedAt = formatter.date(from: "2026-08-24T20:00:00Z")!
        let endedAt = formatter.date(from: "2026-08-24T21:00:00Z")!

        try await service.stopWork(
            accessToken: "access-token",
            teamID: V0236HTTPURLProtocol.teamID,
            userID: V0236HTTPURLProtocol.userID,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: 3600,
            fallbackSessionID: V0236HTTPURLProtocol.mySessionID
        )

        let requests = V0236HTTPURLProtocol.requests(forHost: host)
        let patch = try #require(requests.first {
            $0.url?.path == "/rest/v1/work_sessions" && $0.httpMethod == "PATCH"
        })
        let query = try v0236QueryItems(patch)
        // 핵심: id 필터. 이것이 없으면 team/user/is.null 만으로 걸려 **다른 맥의 새 세션**이 명중된다.
        #expect(query.contains(URLQueryItem(name: "id", value: "eq.\(V0236HTTPURLProtocol.mySessionID)")))
        // 기존 필터는 그대로 남는다(RLS 밖 방어 + 이미 닫힌 세션 덮어쓰기 금지).
        #expect(query.contains(URLQueryItem(name: "team_id", value: "eq.\(V0236HTTPURLProtocol.teamID)")))
        #expect(query.contains(URLQueryItem(name: "user_id", value: "eq.\(V0236HTTPURLProtocol.userID)")))
        #expect(query.contains(URLQueryItem(name: "ended_at", value: "is.null")))
        // (3) 1행이 맞았으므로 폴백 POST 없음 — 정상 마감 경로 회귀 없음.
        #expect(!requests.contains { $0.url?.path == "/rest/v1/work_sessions" && $0.httpMethod == "POST" })
        // 상태 전환(off_work)은 그대로 나간다.
        #expect(requests.contains { $0.url?.path == "/rest/v1/work_statuses" && $0.httpMethod == "POST" })
    }

    /// (2) 서버엔 다른 맥의 새 세션만 열려 있다: PATCH 는 0행 → 폴백 POST 가 **내** 닫힌 세션을 만들고,
    /// 발신 요청 전수 검사로 남의 세션(otherSessionID)은 어떤 요청도 건드리지 않았음을 확인한다.
    @Test func stopWorkAgainstOnlyAnotherMacsOpenSessionFallsBackWithoutTouchingIt() async throws {
        let host = "v0236-stop-other-open"
        let service = v0236Service(host: host)
        let formatter = ISO8601DateFormatter()
        let startedAt = formatter.date(from: "2026-08-24T20:00:00Z")!
        let endedAt = formatter.date(from: "2026-08-24T21:00:00Z")!

        try await service.stopWork(
            accessToken: "access-token",
            teamID: V0236HTTPURLProtocol.teamID,
            userID: V0236HTTPURLProtocol.userID,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: 3600,
            fallbackSessionID: V0236HTTPURLProtocol.mySessionID
        )

        let exchanges = V0236HTTPURLProtocol.exchanges(forHost: host)
        let sessionWrites = exchanges.filter { $0.request.url?.path == "/rest/v1/work_sessions" }
        #expect(!sessionWrites.isEmpty)
        // 전수 검사: work_sessions 로 나간 모든 요청은 반드시 **내 세션 id 를 명시**한다
        // (PATCH 는 쿼리의 id=eq, POST 는 본문의 "id"). 어느 하나라도 익명이면 남의 세션이 과녁이 된다.
        for (request, body) in sessionWrites {
            switch request.httpMethod {
            case "PATCH":
                let query = try v0236QueryItems(request)
                #expect(query.contains(URLQueryItem(name: "id", value: "eq.\(V0236HTTPURLProtocol.mySessionID)")))
            case "POST":
                #expect(body.contains(#""id":"\#(V0236HTTPURLProtocol.mySessionID)""#))
            default:
                Issue.record("예상 밖의 메서드: \(request.httpMethod ?? "?")")
            }
            // 남의 세션 무접촉 — 쿼리에도 본문에도 그 id 가 없다.
            #expect(request.url?.absoluteString.contains(V0236HTTPURLProtocol.otherSessionID) != true)
            #expect(!body.contains(V0236HTTPURLProtocol.otherSessionID))
        }
        // 0행 → 폴백 POST(on_conflict=id + ignore-duplicates)로 내 닫힌 세션이 만들어진다(기존 흐름 불변).
        let fallback = try #require(sessionWrites.first { $0.request.httpMethod == "POST" })
        let fallbackQuery = try v0236QueryItems(fallback.request)
        #expect(fallbackQuery.contains(URLQueryItem(name: "on_conflict", value: "id")))
        let prefer = try #require(fallback.request.value(forHTTPHeaderField: "Prefer"))
        #expect(prefer.contains("resolution=ignore-duplicates"))
        #expect(fallback.body.contains(#""ended_at":"2026-08-24T21:00:00Z""#))
    }

    /// (4) 잠자기 소급 마감(사유 있음) 경로: correctAutoClose 의 "ended_at 은 **더 이르게만**"(gt 필터) 규약과
    /// 두 PATCH 모두의 세션 id 필터가 그대로다. 사유 정정 PATCH 는 ended_at 을 싣지 않는다.
    @Test func correctAutoCloseKeepsEarlierOnlyContractWithSessionIDFilter() async throws {
        let host = "v0236-stop-sleep-correct"
        let service = v0236Service(host: host)
        let formatter = ISO8601DateFormatter()
        let startedAt = formatter.date(from: "2026-08-24T20:00:00Z")!
        let endedAt = formatter.date(from: "2026-08-24T21:00:00Z")!

        try await service.stopWork(
            accessToken: "access-token",
            teamID: V0236HTTPURLProtocol.teamID,
            userID: V0236HTTPURLProtocol.userID,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: 3600,
            fallbackSessionID: V0236HTTPURLProtocol.mySessionID,
            autoClosedReason: .sleep
        )

        let exchanges = V0236HTTPURLProtocol.exchanges(forHost: host)
        let patches = exchanges.filter {
            $0.request.url?.path == "/rest/v1/work_sessions" && $0.request.httpMethod == "PATCH"
        }
        // 순서: 열린 세션 PATCH(0행) → 폴백 POST → 정정 PATCH(gt) → 사유만 PATCH.
        #expect(patches.count == 3)

        let stopPatchQuery = try v0236QueryItems(try #require(patches.first).request)
        #expect(stopPatchQuery.contains(URLQueryItem(name: "id", value: "eq.\(V0236HTTPURLProtocol.mySessionID)")))
        #expect(stopPatchQuery.contains(URLQueryItem(name: "ended_at", value: "is.null")))

        // 정정 1: 서버 값이 내 값보다 **늦을 때만** 닿는 gt 필터 — "늦추는 것은 위조" 규약의 서버 강제.
        let narrowing = try #require(patches.dropFirst().first)
        let narrowingQuery = try v0236QueryItems(narrowing.request)
        #expect(narrowingQuery.contains(URLQueryItem(name: "id", value: "eq.\(V0236HTTPURLProtocol.mySessionID)")))
        #expect(narrowingQuery.contains(URLQueryItem(name: "user_id", value: "eq.\(V0236HTTPURLProtocol.userID)")))
        #expect(narrowingQuery.contains(URLQueryItem(name: "ended_at", value: "gt.2026-08-24T21:00:00Z")))
        #expect(narrowing.body.contains(#""ended_at":"2026-08-24T21:00:00Z""#))

        // 정정 2(gt 가 0행일 때): 사유만 고치고 ended_at 은 **건드리지 않는다**.
        let reasonOnly = try #require(patches.dropFirst(2).first)
        let reasonQuery = try v0236QueryItems(reasonOnly.request)
        #expect(reasonQuery.contains(URLQueryItem(name: "id", value: "eq.\(V0236HTTPURLProtocol.mySessionID)")))
        #expect(reasonQuery.contains(URLQueryItem(name: "ended_at", value: "not.is.null")))
        #expect(!reasonOnly.body.contains(#""ended_at""#))
        #expect(reasonOnly.body.contains(#""auto_closed_reason":"sleep""#))
    }

    /// [C-1] 소급 정정은 **스캐빈저가 abandoned 로 닫은 행만** 고친다. 필터가 없으면 — 맥 A 잠듦 →
    /// 서버 abandoned 마감 → 맥 B 가 이어받아 근무 후 정당하게 마감(같은 세션 행) — 깨어난 A 의 정정이
    /// gt 필터(시각만 본다)를 통과해 그 정당한 나중 마감을 A 의 잠자기 시각으로 당겨 버린다.
    /// 다른 사유(null 포함)로 닫힌 행은 eq.abandoned 에 걸려 0행 = 무접촉이 된다.
    @Test func correctAutoCloseOnlyTargetsScavengerAbandonedRows() async throws {
        let host = "v0236-stop-sleep-abandoned-filter"
        let service = v0236Service(host: host)
        let formatter = ISO8601DateFormatter()

        try await service.stopWork(
            accessToken: "access-token",
            teamID: V0236HTTPURLProtocol.teamID,
            userID: V0236HTTPURLProtocol.userID,
            startedAt: formatter.date(from: "2026-08-24T20:00:00Z")!,
            endedAt: formatter.date(from: "2026-08-24T21:00:00Z")!,
            durationSeconds: 3600,
            fallbackSessionID: V0236HTTPURLProtocol.mySessionID,
            autoClosedReason: .sleep
        )

        let patches = V0236HTTPURLProtocol.requests(forHost: host).filter {
            $0.url?.path == "/rest/v1/work_sessions" && $0.httpMethod == "PATCH"
        }
        #expect(patches.count == 3)
        let abandonedFilter = URLQueryItem(name: "auto_closed_reason", value: "eq.abandoned")
        // 마감 PATCH(첫 번째)는 **열린** 내 세션을 닫는 요청이라 이 필터가 없어야 한다(있으면 마감 자체가 죽는다).
        #expect(!(try v0236QueryItems(try #require(patches.first)).contains(abandonedFilter)))
        // 정정 두 PATCH(gt / 사유만)는 둘 다 abandoned 행에만 닿는다.
        for correction in patches.dropFirst() {
            #expect(try v0236QueryItems(correction).contains(abandonedFilter))
        }
    }

    // MARK: C-2 — reopenSession 이 자동 마감 잔재(auto_closed_*)를 함께 지운다

    /// [C-2] 되돌리기 PATCH 본문에 네 개의 **명시적 null** 이 실린다(PostgREST 는 키 부재와 null 을
    /// 구분한다 — 키가 빠지면 되살아난 열린 세션이 'abandoned' 꼬리표를 단 채 남는다).
    @Test func reopenSessionResetsAutoCloseRemnantsWithExplicitNulls() async throws {
        let host = "v0236-reopen"
        let service = v0236Service(host: host)

        try await service.reopenSession(
            accessToken: "access-token",
            teamID: V0236HTTPURLProtocol.teamID,
            userID: V0236HTTPURLProtocol.userID,
            sessionID: V0236HTTPURLProtocol.mySessionID
        )

        let exchanges = V0236HTTPURLProtocol.exchanges(forHost: host)
        let patch = try #require(exchanges.first {
            $0.request.url?.path == "/rest/v1/work_sessions" && $0.request.httpMethod == "PATCH"
        })
        let query = try v0236QueryItems(patch.request)
        #expect(query.contains(URLQueryItem(name: "id", value: "eq.\(V0236HTTPURLProtocol.mySessionID)")))
        #expect(query.contains(URLQueryItem(name: "team_id", value: "eq.\(V0236HTTPURLProtocol.teamID)")))
        // 인코딩 바이트 검사: 재개(기존 두 null) + 잔재 정리(새 두 null)가 전부 **명시적 null** 로 나간다.
        #expect(patch.body.contains(#""ended_at":null"#))
        #expect(patch.body.contains(#""duration_seconds":null"#))
        #expect(patch.body.contains(#""auto_closed_at":null"#))
        #expect(patch.body.contains(#""auto_closed_reason":null"#))
        // 상태 복구(working)는 그대로 나간다.
        #expect(exchanges.contains { $0.request.url?.path == "/rest/v1/work_statuses" && $0.request.httpMethod == "POST" })
    }

    /// [C-2 호환] 사유 컬럼이 없는 서버(PGRST204)에서는 잔재 정리를 뺀 본문으로 재시도해
    /// **되돌리기 자체가 죽지 않는다**(stopWork 의 withoutNewColumns 와 같은 결).
    @Test func reopenSessionSurvivesLegacySchemaByDroppingAutoCloseReset() async throws {
        let host = "v0236-reopen-legacy"
        let service = v0236Service(host: host)

        try await service.reopenSession(
            accessToken: "access-token",
            teamID: V0236HTTPURLProtocol.teamID,
            userID: V0236HTTPURLProtocol.userID,
            sessionID: V0236HTTPURLProtocol.mySessionID
        )

        let patches = V0236HTTPURLProtocol.exchanges(forHost: host).filter {
            $0.request.url?.path == "/rest/v1/work_sessions" && $0.request.httpMethod == "PATCH"
        }
        #expect(patches.count == 2)
        // 1차: 잔재 정리 포함(구스키마가 PGRST204 로 거절) → 2차: v0.2.35 와 같은 본문으로 재개만 수행.
        #expect(try #require(patches.first).body.contains(#""auto_closed_at":null"#))
        let retry = try #require(patches.dropFirst().first)
        #expect(!retry.body.contains("auto_closed"))
        #expect(retry.body.contains(#""ended_at":null"#))
        #expect(retry.body.contains(#""duration_seconds":null"#))
    }
}
