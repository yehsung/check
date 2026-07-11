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
        displayName: "영식",
        teamID: "10000000-0000-0000-0000-000000000001"
    )

    #expect(session?.userID == "00000000-0000-0000-0000-000000000002")
    let requests = URLProtocolStub.requests(forHost: testHost)
    #expect(requests.contains { $0.url?.path == "/auth/v1/signup" })
    let bodyText = URLProtocolStub.bodyText(forHost: testHost)
    #expect(bodyText.contains("\"email\":\"member@example.com\""))
    #expect(bodyText.contains("\"password\":\"team-password\""))
    #expect(bodyText.contains("\"display_name\":\"영식\""))
    // 선택한 팀이 가입 메타데이터로 전송되어야 한다(트리거가 이 팀으로 멤버십을 만든다).
    #expect(bodyText.contains("\"team_id\":\"10000000-0000-0000-0000-000000000001\""))
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
        _ = try await service.signUp(email: "member@example.com", password: "team-password", displayName: "영식", teamID: "10000000-0000-0000-0000-000000000001")
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
        teamID: "10000000-0000-0000-0000-000000000001",
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

    let statuses = try await service.fetchTeamStatuses(accessToken: "access-token", teamID: URLProtocolStub.stubTeamID)

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
    let statuses = try await service.fetchTeamStatuses(accessToken: "access-token", teamID: URLProtocolStub.stubTeamID, now: now)

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
        _ = try await service.fetchTeamStatuses(accessToken: "access-token", teamID: URLProtocolStub.stubTeamID)
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

    // 경계 걸친 세션을 놓치지 않도록 '주와 겹침'(ended_at >= 주 시작) 기준으로 조회해야 한다.
    let expectedStart = "gte.\(expectedKoreanWeekStartString(for: Date()))"
    _ = try await service.fetchTeamStatuses(accessToken: "access-token", teamID: URLProtocolStub.stubTeamID)

    let weeklyRequest = URLProtocolStub.requests(forHost: testHost).last {
        $0.url?.path == "/rest/v1/work_sessions"
            && $0.url?.query?.contains("ended_at=not.is.null") == true
    }
    let weeklyURL = try #require(weeklyRequest?.url)
    let queryItems = try #require(URLComponents(url: weeklyURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(queryItems.contains(URLQueryItem(name: "ended_at", value: expectedStart)))
    // 옛 필터(started_at gte)는 주 시작 이전에 시작한 경계 세션을 누락시키므로 더 이상 쓰지 않는다.
    #expect(!queryItems.contains { $0.name == "started_at" })
}

private func expectedKoreanWeekStartString(for date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    calendar.firstWeekday = 2
    let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    return ISO8601DateFormatter().string(from: weekStart)
}

// MARK: - D6: 주간/오늘 경계 클리핑

@Test
func weeklyDurationClipsSessionCrossingWeekStart() async throws {
    // 일요일 23시(KST)~월요일 1시(KST) 세션. 저장 duration 은 2시간이지만 이번 주 기여는 월요일 이후 1시간뿐.
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://week-boundary-clip")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let now = ISO8601DateFormatter().date(from: "2026-07-08T12:00:00Z")!
    let statuses = try await service.fetchTeamStatuses(accessToken: "access-token", teamID: URLProtocolStub.stubTeamID, now: now)

    #expect(statuses.count == 1)
    #expect(statuses.first?.weeklyDurationSeconds == 3600)
    // 세션이 오늘(수요일) 이전에 끝났으므로 오늘 기여는 0.
    #expect(statuses.first?.todayDurationSeconds == 0)
}

@Test
func todayDurationClipsSessionCrossingDayStart() async throws {
    // 어제 23시(KST)~오늘 1시(KST) 세션. 저장 duration 은 2시간이지만 오늘 기여는 자정 이후 1시간뿐.
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://day-boundary-clip")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let now = ISO8601DateFormatter().date(from: "2026-07-08T12:00:00Z")!
    let statuses = try await service.fetchTeamStatuses(accessToken: "access-token", teamID: URLProtocolStub.stubTeamID, now: now)

    #expect(statuses.count == 1)
    #expect(statuses.first?.todayDurationSeconds == 3600)
    // 세션 전체가 이번 주 안에 있으므로 주간 기여는 2시간 전부.
    #expect(statuses.first?.weeklyDurationSeconds == 7200)
}

// MARK: - D2: last_seen_at 파싱

@Test
func fetchTeamStatusesParsesLastSeenAndActiveSession() async throws {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://presence-fetch-test")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let statuses = try await service.fetchTeamStatuses(accessToken: "access-token", teamID: URLProtocolStub.stubTeamID)

    #expect(statuses.count == 1)
    #expect(statuses.first?.lastSeenAt == ISO8601DateFormatter().date(from: "2026-07-01T05:00:00Z"))
    #expect(statuses.first?.activeSessionID == "60000000-0000-0000-0000-000000000001")
}

// MARK: - G: 멀티팀 파라미터화 / 디렉터리 / 멤버십

@Test
func fetchTeamStatusesUsesProvidedTeamIDInQuery() async throws {
    let testHost = "team-id-query-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let teamID = "22222222-3333-4444-5555-666666666666"

    _ = try await service.fetchTeamStatuses(accessToken: "access-token", teamID: teamID)

    // work_statuses 조회가 전달한 팀으로 스코프되어야 한다(더 이상 하드코딩 팀이 아님).
    let statusRequest = URLProtocolStub.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/work_statuses"
    }
    let statusURL = try #require(statusRequest?.url)
    let statusItems = try #require(URLComponents(url: statusURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(statusItems.contains(URLQueryItem(name: "team_id", value: "eq.\(teamID)")))

    // 세션 조회들도 같은 팀으로 스코프되어야 한다.
    let sessionRequest = URLProtocolStub.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/work_sessions"
    }
    let sessionURL = try #require(sessionRequest?.url)
    let sessionItems = try #require(URLComponents(url: sessionURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(sessionItems.contains(URLQueryItem(name: "team_id", value: "eq.\(teamID)")))
}

@Test
func fetchTeamDirectoryPostsRPCWithAnonBearer() async throws {
    let testHost = "team-directory-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let directory = try await service.fetchTeamDirectory()

    #expect(directory == [
        TeamDirectoryEntry(id: "10000000-0000-0000-0000-000000000001", name: "sudo 박수"),
        TeamDirectoryEntry(id: "20000000-0000-0000-0000-000000000002", name: "오목교 브라더스")
    ])
    let rpcRequest = try #require(URLProtocolStub.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/rpc/team_directory"
    })
    #expect(rpcRequest.httpMethod == "POST")
    // accessToken 없이 anonKey 를 Bearer 로 사용해 호출한다.
    #expect(rpcRequest.value(forHTTPHeaderField: "Authorization") == "Bearer anon-test-key")
}

@Test
func fetchOwnMembershipParsesTeamIDAndName() async throws {
    let testHost = "membership-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let membership = try await service.fetchOwnMembership(
        accessToken: "access-token",
        userID: "00000000-0000-0000-0000-000000000002"
    )

    #expect(membership?.teamID == "10000000-0000-0000-0000-000000000001")
    #expect(membership?.teamName == "sudo 박수")
    let request = try #require(URLProtocolStub.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/memberships"
    })
    #expect(request.url?.query?.contains("user_id=eq.00000000-0000-0000-0000-000000000002") == true)
}

@Test
func fetchOwnMembershipReturnsNilWhenNoTeam() async throws {
    let testHost = "no-team-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let membership = try await service.fetchOwnMembership(
        accessToken: "access-token",
        userID: "00000000-0000-0000-0000-000000000002"
    )

    #expect(membership == nil)
}

// MARK: - D7: 이중 시작 409 매핑

@Test
func serviceErrorMapsUniqueSessionViolationToSessionAlreadyOpen() async {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://map-test")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let byConstraint = Data(#"{"code":"23505","message":"duplicate key value violates unique constraint \"work_sessions_one_open_per_user\""}"#.utf8)
    let mappedByConstraint = await service.serviceError(statusCode: 409, data: byConstraint)
    #expect(mappedByConstraint == .sessionAlreadyOpen)

    // 제약명 없이 코드만 와도 매핑된다.
    let byCodeOnly = Data(#"{"code":"23505","message":"duplicate key value violates unique constraint"}"#.utf8)
    let mappedByCode = await service.serviceError(statusCode: 409, data: byCodeOnly)
    #expect(mappedByCode == .sessionAlreadyOpen)
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

    let statuses = try await service.fetchTeamStatuses(accessToken: "access-token", teamID: URLProtocolStub.stubTeamID)

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

    let statuses = try await service.fetchTeamStatuses(accessToken: "access-token", teamID: URLProtocolStub.stubTeamID)

    #expect(statuses.count == 1)
    #expect(statuses.first?.avatarURL == nil)
}
