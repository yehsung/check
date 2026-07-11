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

@MainActor
@Test
func expiredAccessTokenRefreshesAndRetriesSync() async {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://expired-token")!,
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
        accessToken: "old-access-token",
        refreshToken: "old-refresh-token",
        userID: "00000000-0000-0000-0000-000000000002"
    )

    await store.refreshTeamStatus()

    #expect(store.session?.accessToken == "refreshed-token")
    #expect(!store.teamMembers.isEmpty)
}

@MainActor
@Test
func failedStopSyncDoesNotReviveTimerOnRefresh() async {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://stop-fails")!,
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
    let start = Date(timeIntervalSince1970: 1000)
    let end = Date(timeIntervalSince1970: 1100)
    store.startedAt = start
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 100)

    store.stop(now: end)

    #expect(store.startedAt == nil)
    #expect(store.pendingOperation == .stop(durationSeconds: 100))

    await store.refreshTeamStatus()

    #expect(store.startedAt == nil)
    #expect(store.pendingOperation == .stop(durationSeconds: 100))
}

@MainActor
@Test
func retryPendingSyncClearsPendingOperationOnceServerRecovers() async {
    URLProtocolStub.patchWorkSessionsShouldFail = true
    defer { URLProtocolStub.patchWorkSessionsShouldFail = false }

    let service = SupabaseWorkService(
        projectURL: URL(string: "http://retry-toggle")!,
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
    store.pendingOperation = .stop(durationSeconds: 50)
    store.pendingStopStartedAt = Date(timeIntervalSince1970: 2000)
    store.pendingStopEndedAt = Date(timeIntervalSince1970: 2050)

    await store.retryPendingSync()
    #expect(store.pendingOperation == .stop(durationSeconds: 50))

    URLProtocolStub.patchWorkSessionsShouldFail = false
    await store.retryPendingSync()
    #expect(store.pendingOperation == nil)
}

@MainActor
@Test
func signOutClearsSessionStateAndCallsLogout() async {
    let defaults = isolatedDefaults()
    defaults.set("member@example.com", forKey: WorkTimerStore.emailKey)
    defaults.set("영식", forKey: WorkTimerStore.displayNameKey)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://signout-test")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )
    store.session = SupabaseSession(
        accessToken: "access-token",
        refreshToken: "refresh-token",
        userID: "00000000-0000-0000-0000-000000000002"
    )
    store.startedAt = Date()
    store.accumulatedSeconds = 500
    store.teamMembers = [
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000002",
            name: "영식",
            status: .working,
            updatedAt: nil,
            currentSessionStartedAt: nil
        )
    ]
    store.pendingOperation = .start
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 120)
    store.startTimer()

    store.signOut()

    #expect(!store.isSignedIn)
    #expect(store.startedAt == nil)
    #expect(store.accumulatedSeconds == 0)
    #expect(store.teamMembers.isEmpty)
    #expect(store.pendingOperation == nil)
    #expect(store.snapshot == WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0))
    #expect(store.tickerTask == nil)
    #expect(store.syncMessage == "로그인 필요")
    #expect(defaults.string(forKey: WorkTimerStore.emailKey) == "member@example.com")
    #expect(defaults.string(forKey: WorkTimerStore.displayNameKey) == "영식")
    #expect(defaults.string(forKey: WorkTimerStore.accessTokenKey) == nil)

    var loggedOut = false
    for _ in 0..<200 {
        if URLProtocolStub.requests(forHost: "signout-test").contains(where: { $0.url?.path == "/auth/v1/logout" }) {
            loggedOut = true
            break
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(loggedOut)
}

// 지연 응답 스텁(URLProtocolStub.delayedHosts)은 프로세스 전역 상태라 병렬 실행 시 서로 덮어쓴다.
// 인-플라이트 레이스를 실제로 재현하려면 이 세 테스트가 서로 겹치지 않아야 하므로 직렬 스위트로 묶는다.
@Suite(.serialized)
@MainActor
struct SyncRaceTests {
    @Test
    func signOutIgnoresInFlightTeamRefresh() async {
        let testHost = "signout-refresh-race"
        URLProtocolStub.delayedHosts = [testHost]
        defer { URLProtocolStub.delayedHosts = [] }

        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(testHost)")!,
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

        let refresh = Task { await store.refreshTeamStatus() }
        // 지연 응답이 도착하기 전에 로그아웃이 먼저 실행되도록 새로고침 Task가 네트워크 대기에 들어갈 시간을 준다.
        try? await Task.sleep(for: .milliseconds(20))
        store.signOut()
        await refresh.value

        #expect(store.teamMembers.isEmpty)
        #expect(store.tickerTask == nil)
        #expect(!store.isSignedIn)
        #expect(store.syncMessage == "로그인 필요")
    }

    @Test
    func signOutIgnoresInFlightTokenRefresh() async {
        let testHost = "signout-token-race"
        URLProtocolStub.delayedHosts = [testHost]
        defer { URLProtocolStub.delayedHosts = [] }

        let defaults = isolatedDefaults()
        defaults.set("old-access-token", forKey: WorkTimerStore.accessTokenKey)
        defaults.set("old-refresh-token", forKey: WorkTimerStore.refreshTokenKey)
        defaults.set("00000000-0000-0000-0000-000000000002", forKey: WorkTimerStore.userIDKey)
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
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }

        #expect(store.isSignedIn)

        let activate = Task { await store.activateStoredSession() }
        // 토큰 갱신 grant 응답이 도착하기 전에 로그아웃이 먼저 실행되도록 한다.
        try? await Task.sleep(for: .milliseconds(20))
        store.signOut()
        await activate.value

        #expect(!store.isSignedIn)
        #expect(defaults.string(forKey: WorkTimerStore.accessTokenKey) == nil)
    }

    @Test
    func rapidStartStopSerializesToSingleOffWorkUpsert() async {
        let testHost = "start-stop-race"
        URLProtocolStub.delayedHosts = [testHost]
        defer { URLProtocolStub.delayedHosts = [] }

        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(testHost)")!,
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

        store.start(now: Date(timeIntervalSince1970: 3000))
        store.stop(now: Date(timeIntervalSince1970: 3100))

        // 직렬화된 sync 체인이 완전히 끝날 때까지 대기한다(마지막 Task가 이전 Task를 await 한다).
        await store.syncTask?.value

        let requests = URLProtocolStub.requests(forHost: testHost)
        let bodies = URLProtocolStub.bodiesByHost[testHost] ?? []
        let statusUpsertBodies = zip(requests, bodies)
            .filter { $0.0.url?.path == "/rest/v1/work_statuses" && $0.0.httpMethod == "POST" }
            .map { $0.1 }
        let workingUpserts = statusUpsertBodies.filter { $0.contains(#""status":"working""#) }
        let offWorkUpserts = statusUpsertBodies.filter { $0.contains(#""status":"off_work""#) }
        let completedSessionPosts = requests.filter {
            $0.url?.path == "/rest/v1/work_sessions" && $0.httpMethod == "POST"
        }

        #expect(workingUpserts.isEmpty)
        #expect(offWorkUpserts.count == 1)
        #expect(completedSessionPosts.count <= 1)
        #expect(store.pendingOperation == nil)
    }

    @Test
    func finishWorkBeforeQuitReturnsWithinTimeoutWhenSyncStalls() async {
        let testHost = "quit-timeout"
        URLProtocolStub.delayedHosts = [testHost]
        defer { URLProtocolStub.delayedHosts = [] }

        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(testHost)")!,
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
        store.startedAt = Date(timeIntervalSinceNow: -30)
        store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 30)

        // 지연 스텁(요청당 0.15s)보다 짧은 타임아웃을 주면 sync 완료를 기다리지 않고 곧바로 리턴해야 한다.
        let clock = ContinuousClock()
        let start = clock.now
        await store.finishWorkBeforeQuit(timeout: 0.05)
        let elapsed = clock.now - start

        #expect(elapsed < .seconds(3.5))
        // stop()은 로컬 상태를 즉시 반영하지만(퇴근 표시), 네트워크 sync는 타임아웃으로 아직 미완료다.
        #expect(store.startedAt == nil)
        #expect(store.pendingOperation != nil)
    }
}

// MARK: - 종료 시 자동 퇴근 (finishWorkBeforeQuit)

@MainActor
@Test
func finishWorkBeforeQuitSyncsStopWhenWorking() async {
    let testHost = "quit-sync"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
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
    store.startedAt = Date(timeIntervalSinceNow: -120)
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 120)

    await store.finishWorkBeforeQuit()

    #expect(store.startedAt == nil)
    #expect(store.pendingOperation == nil)
    let stopRequests = URLProtocolStub.requests(forHost: testHost)
        .filter { $0.url?.path == "/rest/v1/work_sessions" && $0.httpMethod == "PATCH" }
    #expect(!stopRequests.isEmpty)
    #expect(URLProtocolStub.bodyText(forHost: testHost).contains(#""status":"off_work""#))
}

@MainActor
@Test
func finishWorkBeforeQuitReturnsImmediatelyWhenNotWorking() async {
    let testHost = "quit-idle"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    store.session = SupabaseSession(
        accessToken: "access-token",
        refreshToken: nil,
        userID: "00000000-0000-0000-0000-000000000002"
    )
    // startedAt == nil → 근무중이 아니므로 어떤 요청도 보내지 않고 즉시 리턴해야 한다.

    await store.finishWorkBeforeQuit()

    #expect(store.startedAt == nil)
    #expect(store.pendingOperation == nil)
    #expect(URLProtocolStub.requests(forHost: testHost).isEmpty)
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "check-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
