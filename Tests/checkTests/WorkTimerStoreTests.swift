import Foundation
import Testing
@testable import check

@MainActor
@Test
func invalidLoginCredentialsDoNotCreateAccount() async {
    let testHost = "invalid-login"
    let defaults = isolatedDefaults()
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )
    store.email = "member@example.com"
    store.password = "wrong-password"

    await store.signIn()?.value

    let paths = URLProtocolStub.requests(forHost: testHost).compactMap { $0.url?.path }
    #expect(paths.contains("/auth/v1/token"))
    #expect(!paths.contains("/auth/v1/signup"))
    #expect(!store.isSignedIn)
    #expect(store.syncMessage == "로그인 정보 오류")
}

@MainActor
@Test
func signUpRequiresDisplayName() {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    store.email = "new@example.com"
    store.password = "team-password"
    store.displayName = " "

    let task = store.signUp()

    #expect(task == nil)
    #expect(store.syncMessage == "이메일, 비밀번호, 별명 필요")
}

@MainActor
@Test
func remoteWorkingMemberKeepsDisplayClockTimerRunning() {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedDefaults()
    )
    defer {
        store.tickerTask?.cancel()
    }
    store.teamMembers = [
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000002",
            name: "ysiig",
            status: .working,
            updatedAt: nil,
            currentSessionStartedAt: Date(timeIntervalSinceNow: -60),
            weeklyDurationSeconds: 0
        )
    ]

    store.stopTimerIfIdle()

    #expect(store.tickerTask != nil)

    store.teamMembers = []
    store.stopTimerIfIdle()

    #expect(store.tickerTask == nil)
}

@MainActor
@Test
func workingMemberWeeklyDurationAdvancesLocally() {
    let now = Date()
    let member = TeamMemberStatus(
        id: "00000000-0000-0000-0000-000000000002",
        name: "ysiig",
        status: .working,
        updatedAt: nil,
        currentSessionStartedAt: now.addingTimeInterval(-90),
        weeklyDurationSeconds: 7_200
    )

    #expect(member.liveWeeklyDurationSeconds(now: now) == 7_290)
}

@MainActor
@Test
func refreshTeamStatusRestoresRemoteOwnSessionStart() async throws {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://team-hours-test")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    store.session = SupabaseSession(
        accessToken: "access-token",
        refreshToken: nil,
        userID: "00000000-0000-0000-0000-000000000002"
    )

    await store.refreshTeamStatus()

    let expectedStart = ISO8601DateFormatter().date(from: "2026-07-01T01:00:00Z")
    #expect(store.startedAt == expectedStart)
    #expect(store.snapshot.isWorking)
    #expect(store.snapshot.elapsedSeconds > 0)
}

@MainActor
@Test
func signInPersistsSessionForNextLaunch() async {
    let defaults = isolatedDefaults()
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://signin-success")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )
    store.email = "member@example.com"
    store.password = "team-password"

    await store.signIn()?.value

    #expect(store.isSignedIn)
    #expect(defaults.string(forKey: WorkTimerStore.emailKey) == "member@example.com")
    #expect(defaults.string(forKey: WorkTimerStore.accessTokenKey) == "signed-in-token")
    #expect(defaults.string(forKey: WorkTimerStore.refreshTokenKey) == "signed-in-refresh-token")
    #expect(defaults.string(forKey: WorkTimerStore.userIDKey) == "00000000-0000-0000-0000-000000000002")
}

@MainActor
@Test
func storedSessionIsRestoredAndRefreshedOnLaunch() async {
    let defaults = isolatedDefaults()
    defaults.set("old-access-token", forKey: WorkTimerStore.accessTokenKey)
    defaults.set("old-refresh-token", forKey: WorkTimerStore.refreshTokenKey)
    defaults.set("00000000-0000-0000-0000-000000000002", forKey: WorkTimerStore.userIDKey)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://restore-session")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )

    #expect(store.isSignedIn)

    await store.activateStoredSession()

    #expect(store.session?.accessToken == "refreshed-token")
    #expect(defaults.string(forKey: WorkTimerStore.accessTokenKey) == "refreshed-token")
    #expect(defaults.string(forKey: WorkTimerStore.refreshTokenKey) == "next-refresh-token")
    #expect(URLProtocolStub.bodyText(forHost: "restore-session").contains(#""refresh_token":"old-refresh-token""#))
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "check-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
