import Foundation
import Testing
@testable import check

@Test
func signUpSendsEmailAndPasswordToSupabaseAuth() async throws {
    let testHost = "signup-test"

    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let session = try await service.signUp(
        email: "member@example.com",
        password: "team-password",
        displayName: "영식"
    )

    #expect(session?.userID == "00000000-0000-0000-0000-000000000002")
    let requests = URLProtocolStub.requests(forHost: testHost)
    #expect(requests.contains { $0.url?.path == "/auth/v1/signup" })
    let bodyText = URLProtocolStub.bodyText(forHost: testHost)
    #expect(bodyText.contains("\"email\":\"member@example.com\""))
    #expect(bodyText.contains("\"password\":\"team-password\""))
    #expect(bodyText.contains("\"display_name\":\"영식\""))
}

@Test
func signInReportsInvalidLoginCredentials() async throws {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://invalid-login")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    do {
        _ = try await service.signIn(email: "member@example.com", password: "wrong-password")
        Issue.record("signIn should fail with invalidLoginCredentials")
    } catch let error as SupabaseWorkServiceError {
        #expect(error == .invalidLoginCredentials)
    }
}

@Test
func signInReportsEmailNotConfirmed() async throws {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://email-not-confirmed")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    do {
        _ = try await service.signIn(email: "member@example.com", password: "team-password")
        Issue.record("signIn should fail with emailNotConfirmed")
    } catch let error as SupabaseWorkServiceError {
        #expect(error == .emailNotConfirmed)
    }
}

@Test
func signUpReportsInvalidAPIKey() async throws {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://invalid-key")!,
        anonKey: "bad-key",
        session: URLSession(configuration: .stubbed)
    )

    do {
        _ = try await service.signUp(email: "member@example.com", password: "team-password", displayName: "영식")
        Issue.record("signUp should fail with invalidAPIKey")
    } catch let error as SupabaseWorkServiceError {
        #expect(error == .invalidAPIKey)
    }
}

@Test
func startWorkEncodesRestBodiesAsSnakeCase() async throws {
    let testHost = "start-work-test"

    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    try await service.startWork(
        accessToken: "access-token",
        userID: "00000000-0000-0000-0000-000000000002",
        sessionID: "30000000-0000-0000-0000-000000000009"
    )

    let bodyText = URLProtocolStub.bodyText(forHost: testHost)
    #expect(bodyText.contains("\"team_id\""))
    #expect(bodyText.contains("\"user_id\""))
    #expect(bodyText.contains("\"active_session_id\""))
    #expect(!bodyText.contains("\"teamId\""))
    #expect(!bodyText.contains("\"userId\""))
}

@Test
func fetchTeamStatusesIncludesCurrentAndWeeklyDurations() async throws {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://team-hours-test")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let statuses = try await service.fetchTeamStatuses(accessToken: "access-token")

    #expect(statuses.count == 1)
    #expect(statuses.first?.name == "영식")
    #expect(statuses.first?.status == .working)
    #expect(statuses.first?.currentSessionStartedAt != nil)
    #expect(statuses.first?.weeklyDurationSeconds == 7200)
}

@Test
func fetchTeamStatusesSumsOnlyTodaySessionsForTodayDuration() async throws {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://today-hours-test")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let now = ISO8601DateFormatter().date(from: "2026-07-10T12:00:00Z")!
    let statuses = try await service.fetchTeamStatuses(accessToken: "access-token", now: now)

    #expect(statuses.count == 1)
    // Two completed sessions exist (3600s today + 1800s earlier this week).
    #expect(statuses.first?.weeklyDurationSeconds == 5400)
    // Only the session started on the Korean calendar day of `now` is counted.
    #expect(statuses.first?.todayDurationSeconds == 3600)
}

@Test
func fetchTeamStatusesReportsMissingDatabaseSchema() async throws {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://schema-missing")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    do {
        _ = try await service.fetchTeamStatuses(accessToken: "access-token")
        Issue.record("fetchTeamStatuses should fail with databaseSchemaMissing")
    } catch let error as SupabaseWorkServiceError {
        #expect(error == .databaseSchemaMissing)
    }
}

@Test
func weeklySessionsQueryUsesKoreanMondayMidnight() async throws {
    let testHost = "korean-week-current-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let expectedStart = "gte.\(expectedKoreanWeekStartString(for: Date()))"
    _ = try await service.fetchTeamStatuses(accessToken: "access-token")

    let weeklyRequest = URLProtocolStub.requests(forHost: testHost).last {
        $0.url?.path == "/rest/v1/work_sessions"
            && $0.url?.query?.contains("ended_at=not.is.null") == true
    }
    let weeklyURL = try #require(weeklyRequest?.url)
    let queryItems = try #require(URLComponents(url: weeklyURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(queryItems.contains(URLQueryItem(name: "started_at", value: expectedStart)))
}

private func expectedKoreanWeekStartString(for date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    calendar.firstWeekday = 2
    let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    return ISO8601DateFormatter().string(from: weekStart)
}

// MARK: - Avatar tests

// 트랙 A 소유의 URLProtocolStub.swift 를 건드리지 않기 위해 아바타 전용 스텁을 여기서 정의한다.
final class AvatarURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodiesByHost: [String: [Data]] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.append(request)
        Self.bodiesByHost[request.url?.host ?? "", default: []].append(Self.bodyData(from: request))

        let (statusCode, data) = Self.response(for: request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session(forHost host: String) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AvatarURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func requests(forHost host: String) -> [URLRequest] {
        requests.filter { $0.url?.host == host }
    }

    static func bodies(forHost host: String) -> [Data] {
        bodiesByHost[host, default: []]
    }

    private static func response(for request: URLRequest) -> (Int, Data) {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""

        if path == "/rest/v1/work_statuses" {
            return (200, workStatusesData(forHost: host))
        }
        if path == "/rest/v1/work_sessions" {
            return (200, Data("[]".utf8))
        }
        // storage POST 및 profiles PATCH 는 본문을 사용하지 않으므로 빈 200 응답.
        return (200, Data())
    }

    private static func workStatusesData(forHost host: String) -> Data {
        let avatarField = host == "avatar-fetch-null-test"
            ? "null"
            : "\"https://cdn.example.com/avatars/user.jpg?v=123\""
        return Data(
            """
            [
              {
                "user_id": "00000000-0000-0000-0000-000000000002",
                "status": "off_work",
                "updated_at": "2026-07-01T01:00:00Z",
                "active_session_id": null,
                "profiles": {
                  "display_name": "영식",
                  "email": "member@example.com",
                  "avatar_url": \(avatarField)
                }
              }
            ]
            """.utf8
        )
    }

    private static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

@Test
func uploadAvatarUploadsToStorageThenPatchesProfile() async throws {
    let testHost = "avatar-upload-test"
    let userID = "00000000-0000-0000-0000-000000000002"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: AvatarURLProtocol.session(forHost: testHost)
    )

    let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03])

    let avatarURL = try await service.uploadAvatar(
        accessToken: "access-token",
        userID: userID,
        imageData: imageData
    )

    let requests = AvatarURLProtocol.requests(forHost: testHost)
    let storageIndex = try #require(requests.firstIndex {
        $0.url?.path == "/storage/v1/object/avatars/\(userID).jpg"
    })
    let patchIndex = try #require(requests.firstIndex {
        $0.url?.path == "/rest/v1/profiles" && $0.httpMethod == "PATCH"
    })
    // 스토리지 업로드가 프로필 PATCH 보다 먼저 전송되어야 한다.
    #expect(storageIndex < patchIndex)

    let storageRequest = requests[storageIndex]
    #expect(storageRequest.httpMethod == "POST")
    #expect(storageRequest.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
    #expect(storageRequest.value(forHTTPHeaderField: "apikey") == "anon-test-key")
    #expect(storageRequest.value(forHTTPHeaderField: "x-upsert") == "true")
    #expect(storageRequest.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")

    // 스토리지 업로드 본문은 원본 이미지 바이트여야 한다.
    #expect(AvatarURLProtocol.bodies(forHost: testHost).first == imageData)

    let patchRequest = requests[patchIndex]
    #expect(patchRequest.url?.query?.contains("id=eq.\(userID)") == true)
    #expect(patchRequest.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")

    // 반환값 = public URL + 캐시 버스팅 쿼리, 그리고 PATCH 본문에 동일 값이 담긴다.
    #expect(avatarURL.hasPrefix("http://\(testHost)/storage/v1/object/public/avatars/\(userID).jpg?v="))
    let patchData = try #require(AvatarURLProtocol.bodies(forHost: testHost).last)
    let patchFields = try JSONDecoder().decode([String: String].self, from: patchData)
    #expect(patchFields["avatar_url"] == avatarURL)
}

@Test
func fetchTeamStatusesParsesAvatarURL() async throws {
    let testHost = "avatar-fetch-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: AvatarURLProtocol.session(forHost: testHost)
    )

    let statuses = try await service.fetchTeamStatuses(accessToken: "access-token")

    #expect(statuses.count == 1)
    #expect(statuses.first?.avatarURL == URL(string: "https://cdn.example.com/avatars/user.jpg?v=123"))
}

@Test
func fetchTeamStatusesLeavesAvatarURLNilWhenAbsent() async throws {
    let testHost = "avatar-fetch-null-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: AvatarURLProtocol.session(forHost: testHost)
    )

    let statuses = try await service.fetchTeamStatuses(accessToken: "access-token")

    #expect(statuses.count == 1)
    #expect(statuses.first?.avatarURL == nil)
}
