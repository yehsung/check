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
        userID: "00000000-0000-0000-0000-000000000002"
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
