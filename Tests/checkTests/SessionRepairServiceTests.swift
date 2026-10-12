import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 2026-10-09 복구 조각 전용 스텁
//
// 공유 URLProtocolStub 을 고치지 않는 이유는 V0236HTTPURLProtocol 머리 주석과 같다:
// (1) 그 파일은 이 트랙의 소유가 아니다(동시에 다른 트랙이 편집 중이다).
// (2) 이 스위트는 **representation 본문(1행/0행)** 을 시나리오별로 쥐어야 한다 — 공유 스텁의
//     POST /rest/v1/work_sessions 는 `Data()` 한 가지뿐이라 "행이 돌아왔는가" 를 가를 축이 없다.
// 호스트 이름이 시나리오를 고르는 규약은 두 스텁과 같다(전부 "repair-" 접두어라 다른 스위트와 못 섞인다).
final class SessionRepairURLProtocol: URLProtocol {
    static let userID = "00000000-0000-0000-0000-000000000002"
    static let teamID = "10000000-0000-0000-0000-000000000001"
    static let sessionID = "44440000-0000-0000-0000-000000000001"
    /// 서버가 돌려주는 id 는 **대문자가 섞여 올 수 있다**(uuid 표기는 서버·클라가 서로 다르게 쓴다).
    /// 신원 비교가 소문자 규약이므로 반환값이 소문자로 접히는지를 이 모양만이 가른다.
    static let serverReturnedID = "44440000-0000-0000-0000-0000000000AA"

    private nonisolated(unsafe) static var recorded: [(request: URLRequest, body: String)] = []
    private static let stateLock = NSLock()

    static func exchanges(forHost host: String) -> [(request: URLRequest, body: String)] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return recorded.filter { $0.request.url?.host == host }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        Self.stateLock.lock()
        Self.recorded.append((request: request, body: Self.bodyText(from: request)))
        Self.stateLock.unlock()

        let (statusCode, body) = Self.outcome(host: host, path: path, method: request.httpMethod ?? "")
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

    private static func row(id: String, endedAt: String?) -> String {
        let tail = endedAt.map { #""ended_at": "\#($0)", "duration_seconds": 3600"# } ?? #""ended_at": null"#
        return #"{"id": "\#(id)", "user_id": "\#(userID)", "started_at": "2026-10-09T00:00:00Z", \#(tail)}"#
    }

    private static func outcome(host: String, path: String, method: String) -> (Int, String) {
        if path == "/rest/v1/work_sessions", method == "POST" {
            // ignore-duplicates 가 arbiter(id) 충돌을 삼킨 경우 = 0행. 사고를 만든 오독이 여기였다.
            if host.contains("insert-empty") { return (201, "[]") }
            return (201, "[\(row(id: serverReturnedID, endedAt: nil))]")
        }
        if path == "/rest/v1/work_sessions", method == "PATCH" {
            if host.contains("reopen-none") { return (200, "[]") }
            return (200, "[\(row(id: serverReturnedID, endedAt: nil))]")
        }
        if path == "/rest/v1/work_sessions", method == "GET" {
            // 열린 행 + since 이후에 끝난 닫힌 행 — 겹칠 수 있는 두 모양을 같은 응답에 섞어 둔다.
            return (200, "[\(row(id: sessionID, endedAt: nil)),\(row(id: serverReturnedID, endedAt: "2026-10-09T01:00:00Z"))]")
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

    static func service(host: String) -> SupabaseWorkService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionRepairURLProtocol.self]
        return SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: configuration)
        )
    }
}

/// 서비스 계층 3단계: 세션 신원을 **서버가 받아 준 행**에서 얻고, 복구 쓰기는 공유 셀을 건드리지 않는다.
@Suite struct SupabaseWorkServiceSessionRepairTests {
    static let startedAt = ISO8601DateFormatter().date(from: "2026-10-09T00:00:00Z")!
    static let endedAt = ISO8601DateFormatter().date(from: "2026-10-09T01:00:00Z")!

    private func queryItems(_ request: URLRequest) throws -> [URLQueryItem] {
        let url = try #require(request.url)
        return try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    }

    @Test("startWork 가 들어간 행의 id 를 소문자로 돌려준다 · 요청 본문은 그대로다")
    func startWorkReturnsInsertedRowID() async throws {
        let host = "repair-insert-row"
        let service = SessionRepairURLProtocol.service(host: host)

        let inserted = try await service.startWork(
            accessToken: "access-token",
            teamID: SessionRepairURLProtocol.teamID,
            userID: SessionRepairURLProtocol.userID,
            sessionID: SessionRepairURLProtocol.sessionID,
            startedAt: Self.startedAt
        )

        #expect(inserted == SessionRepairURLProtocol.serverReturnedID.lowercased())

        let post = try #require(SessionRepairURLProtocol.exchanges(forHost: host).first {
            $0.request.url?.path == "/rest/v1/work_sessions" && $0.request.httpMethod == "POST"
        })
        // 본문은 v0.2.34 와 **같은 네 키·같은 값**이다 — 바뀌는 것은 Prefer 한 값뿐이다.
        // 글자 비교를 하지 않는 이유: JSONEncoder 의 키 순서는 실행마다 흔들린다(실측 — team_id 가 먼저 왔다).
        // 그래서 파싱해 키 집합과 값을 전수로 본다(키가 하나 더 붙거나 빠지면 빨개진다).
        let bodyJSON = try #require(
            try JSONSerialization.jsonObject(with: Data(post.body.utf8)) as? [String: String]
        )
        #expect(bodyJSON == [
            "id": SessionRepairURLProtocol.sessionID,
            "team_id": SessionRepairURLProtocol.teamID,
            "user_id": SessionRepairURLProtocol.userID,
            "started_at": "2026-10-09T00:00:00Z"
        ])
        #expect(try queryItems(post.request).contains(URLQueryItem(name: "on_conflict", value: "id")))
        let prefer = try #require(post.request.value(forHTTPHeaderField: "Prefer"))
        #expect(prefer.contains("resolution=ignore-duplicates"))
        #expect(prefer.contains("return=representation"))
    }

    @Test("빈 배열은 '내 id 가 이미 있다'다 — 실패가 아니라 정상 경로다(상태 쓰기까지 그대로 나간다)")
    func startWorkTreatsEmptyRepresentationAsAlreadyInserted() async throws {
        let host = "repair-insert-empty"
        let service = SessionRepairURLProtocol.service(host: host)

        // 던지지 않는다. 0행을 "내 세션이 아니다"로 읽으면 여기서 근무가 0초가 됐다.
        let inserted = try await service.startWork(
            accessToken: "access-token",
            teamID: SessionRepairURLProtocol.teamID,
            userID: SessionRepairURLProtocol.userID,
            sessionID: SessionRepairURLProtocol.sessionID,
            startedAt: Self.startedAt
        )
        #expect(inserted == nil)
        #expect(SessionRepairURLProtocol.exchanges(forHost: host).contains {
            $0.request.url?.path == "/rest/v1/work_statuses" && $0.request.httpMethod == "POST"
        }, "0행을 실패로 접으면 상태 쓰기가 사라진다 — 그러면 시작이 통째로 유실된다")
    }

    @Test("reopenSession 은 0행을 성공으로 읽지 않는다(행이 오면 id, 안 오면 nil)")
    func reopenSessionDistinguishesZeroRows() async throws {
        let hit = SessionRepairURLProtocol.service(host: "repair-reopen-row")
        let reopened = try await hit.reopenSession(
            accessToken: "access-token",
            teamID: SessionRepairURLProtocol.teamID,
            userID: SessionRepairURLProtocol.userID,
            sessionID: SessionRepairURLProtocol.sessionID
        )
        #expect(reopened == SessionRepairURLProtocol.serverReturnedID.lowercased())

        let miss = SessionRepairURLProtocol.service(host: "repair-reopen-none")
        let nothing = try await miss.reopenSession(
            accessToken: "access-token",
            teamID: SessionRepairURLProtocol.teamID,
            userID: SessionRepairURLProtocol.userID,
            sessionID: SessionRepairURLProtocol.sessionID
        )
        #expect(nothing == nil, "0행인데 성공으로 보고하면 호출부가 안 살아난 세션으로 타이머를 돌린다")

        let patch = try #require(SessionRepairURLProtocol.exchanges(forHost: "repair-reopen-row").first {
            $0.request.url?.path == "/rest/v1/work_sessions" && $0.request.httpMethod == "PATCH"
        })
        #expect(patch.request.value(forHTTPHeaderField: "Prefer") == "return=representation")
    }

    @Test("stopWork(updateSharedStatus: false) 는 세션 한 행만 고친다 — 기본값은 종전처럼 off_work 를 쓴다")
    func stopWorkCanLeaveSharedStatusAlone() async throws {
        let quiet = "repair-stop-quiet"
        try await SessionRepairURLProtocol.service(host: quiet).stopWork(
            accessToken: "access-token",
            teamID: SessionRepairURLProtocol.teamID,
            userID: SessionRepairURLProtocol.userID,
            startedAt: Self.startedAt,
            endedAt: Self.endedAt,
            durationSeconds: 3600,
            fallbackSessionID: SessionRepairURLProtocol.sessionID,
            updateSharedStatus: false
        )
        // (열린 세션, off_work) = 아무도 못 닫는 세션. 이 쓰기가 나가면 안 된다.
        #expect(!SessionRepairURLProtocol.exchanges(forHost: quiet).contains {
            $0.request.url?.path == "/rest/v1/work_statuses"
        })
        #expect(SessionRepairURLProtocol.exchanges(forHost: quiet).contains {
            $0.request.url?.path == "/rest/v1/work_sessions" && $0.request.httpMethod == "PATCH"
        }, "대조: 세션 PATCH 자체는 나갔다")

        let loud = "repair-stop-loud"
        try await SessionRepairURLProtocol.service(host: loud).stopWork(
            accessToken: "access-token",
            teamID: SessionRepairURLProtocol.teamID,
            userID: SessionRepairURLProtocol.userID,
            startedAt: Self.startedAt,
            endedAt: Self.endedAt,
            durationSeconds: 3600,
            fallbackSessionID: SessionRepairURLProtocol.sessionID
        )
        let status = try #require(SessionRepairURLProtocol.exchanges(forHost: loud).first {
            $0.request.url?.path == "/rest/v1/work_statuses"
        })
        #expect(status.body.contains(#""status":"off_work""#))
    }

    @Test("fetchMyOverlappingSessions 는 user_id 전역으로 겹칠 수 있는 행 전부를 읽는다(팀 필터 없음)")
    func fetchMyOverlappingSessionsIsUserScoped() async throws {
        let host = "repair-overlap"
        let rows = try await SessionRepairURLProtocol.service(host: host).fetchMyOverlappingSessions(
            accessToken: "access-token",
            userID: SessionRepairURLProtocol.userID,
            since: Self.startedAt
        )
        #expect(rows.count == 2)
        #expect(rows.contains { $0.endedAt == nil }, "열린 행이 빠지면 23505 의 범인을 못 찾는다")

        let get = try #require(SessionRepairURLProtocol.exchanges(forHost: host).first {
            $0.request.url?.path == "/rest/v1/work_sessions" && $0.request.httpMethod == "GET"
        })
        let items = try queryItems(get.request)
        #expect(items.contains(URLQueryItem(name: "user_id", value: "eq.\(SessionRepairURLProtocol.userID)")))
        #expect(items.contains(URLQueryItem(name: "or", value: "(ended_at.is.null,ended_at.gte.2026-10-09T00:00:00Z)")))
        #expect(items.contains(URLQueryItem(name: "order", value: "started_at.asc")))
        #expect(items.contains(URLQueryItem(name: "limit", value: "50")))
        // 부분 유니크는 user_id 전역이다(20260701000000:44) — 팀으로 좁히면 범인 행이 조회에서 사라진다.
        #expect(!items.contains { $0.name == "team_id" })
    }

    @Test("insertClosedSession 은 닫힌 한 행만 적는다 — 공유 상태도, 자동 마감 사유도 건드리지 않는다")
    func insertClosedSessionWritesOnlyTheClosedRow() async throws {
        let host = "repair-closed-insert"
        try await SessionRepairURLProtocol.service(host: host).insertClosedSession(
            accessToken: "access-token",
            teamID: SessionRepairURLProtocol.teamID,
            userID: SessionRepairURLProtocol.userID,
            sessionID: SessionRepairURLProtocol.sessionID,
            startedAt: Self.startedAt,
            endedAt: Self.endedAt
        )
        let exchanges = SessionRepairURLProtocol.exchanges(forHost: host)
        #expect(exchanges.count == 1, "요청은 한 건이어야 한다 — 공유 셀 쓰기가 따라붙으면 복구가 남의 근무를 덮는다")
        let post = try #require(exchanges.first)
        #expect(post.request.url?.path == "/rest/v1/work_sessions")
        #expect(post.request.httpMethod == "POST")
        #expect(try queryItems(post.request).contains(URLQueryItem(name: "on_conflict", value: "id")))
        let prefer = try #require(post.request.value(forHTTPHeaderField: "Prefer"))
        #expect(prefer.contains("resolution=ignore-duplicates"))
        #expect(post.body.contains(#""ended_at":"2026-10-09T01:00:00Z""#), "닫힌 행이라야 부분 유니크에 안 걸린다")
        #expect(post.body.contains(#""duration_seconds":3600"#))
        // away/sleep 이 아닌 사유를 달면 restore_auto_closed_session 의 복원 대상에서 빠지면서도 어휘를 어긴다 — nil 이 유일한 답이다.
        #expect(!post.body.contains("auto_closed"))
    }
}
