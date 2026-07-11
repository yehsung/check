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

// MARK: - G: 멀티팀 가입/무소속

@MainActor
@Test
func signUpRequiresTeamSelection() {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    store.email = "new@example.com"
    store.password = "team-password"
    store.displayName = "영식"
    // selectedSignupTeamID 미설정 → 가입 거부.

    let task = store.signUp()

    #expect(task == nil)
    #expect(store.syncMessage == "팀을 선택해 주세요")
}

@MainActor
@Test
func signUpSendsSelectedTeamIDInMetadata() async {
    let testHost = "signup-team-test"
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
    store.email = "member@example.com"
    store.password = "team-password"
    store.displayName = "영식"
    store.selectedSignupTeamID = "20000000-0000-0000-0000-000000000002"

    await store.signUp()?.value

    #expect(store.isSignedIn)
    // 선택한 팀이 가입 메타데이터로 서버에 전달되어야 한다.
    let bodyText = URLProtocolStub.bodyText(forHost: testHost)
    #expect(bodyText.contains("\"team_id\":\"20000000-0000-0000-0000-000000000002\""))
}

@MainActor
@Test
func signInWithoutTeamShowsNoTeamMessage() async {
    let testHost = "no-team-test"
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
    store.email = "member@example.com"
    store.password = "team-password"

    await store.signIn()?.value

    // 소속 팀이 없는 계정은 로그인은 되지만 팀 데이터는 비고 안내 문구가 뜬다.
    #expect(store.isSignedIn)
    #expect(store.currentTeamID == nil)
    #expect(store.teamName == "팀")
    #expect(store.teamMembers.isEmpty)
    #expect(store.syncMessage == "소속 팀이 없어요 — 관리자에게 문의")
}

@MainActor
@Test
func loadTeamDirectoryPopulatesDirectory() async {
    let testHost = "team-directory-store-test"
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
    #expect(store.teamDirectory.isEmpty)

    await store.performLoadTeamDirectory()

    #expect(store.teamDirectory == [
        TeamDirectoryEntry(id: "10000000-0000-0000-0000-000000000001", name: "sudo 박수"),
        TeamDirectoryEntry(id: "20000000-0000-0000-0000-000000000002", name: "오목교 브라더스")
    ])
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
    store.currentTeamID = URLProtocolStub.stubTeamID

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
    store.currentTeamID = URLProtocolStub.stubTeamID

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
    store.currentTeamID = URLProtocolStub.stubTeamID
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
    store.currentTeamID = URLProtocolStub.stubTeamID
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
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "sudo 박수"
    store.teamDirectory = [TeamDirectoryEntry(id: "t", name: "n")]
    store.selectedSignupTeamID = "t"
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
    #expect(store.currentTeamID == nil)
    #expect(store.teamName == "팀")
    #expect(store.teamDirectory.isEmpty)
    #expect(store.selectedSignupTeamID == nil)
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
        store.currentTeamID = URLProtocolStub.stubTeamID

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
        store.currentTeamID = URLProtocolStub.stubTeamID

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
        store.currentTeamID = URLProtocolStub.stubTeamID
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
    store.currentTeamID = URLProtocolStub.stubTeamID
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
    store.currentTeamID = URLProtocolStub.stubTeamID
    // startedAt == nil → 근무중이 아니므로 어떤 요청도 보내지 않고 즉시 리턴해야 한다.

    await store.finishWorkBeforeQuit()

    #expect(store.startedAt == nil)
    #expect(store.pendingOperation == nil)
    #expect(URLProtocolStub.requests(forHost: testHost).isEmpty)
}

// MARK: - D2: presence 판정 + 동결 클램프

@MainActor
@Test
func presenceReportsOffWorkForNonWorkingMember() {
    let member = TeamMemberStatus(
        id: "u", name: "n", status: .offWork, updatedAt: Date(), currentSessionStartedAt: nil
    )
    #expect(member.presence(now: Date()) == .offWork)
}

@MainActor
@Test
func presenceReportsActiveWorkingWhenSignalFresh() {
    let now = Date()
    let member = TeamMemberStatus(
        id: "u", name: "n", status: .working, updatedAt: nil,
        currentSessionStartedAt: now.addingTimeInterval(-120),
        lastSeenAt: now.addingTimeInterval(-30)
    )
    #expect(member.presence(now: now) == .activeWorking)
    #expect(member.currentDurationSeconds(now: now) == 120)
}

@MainActor
@Test
func presenceTreatsMissingSignalAsActive() {
    let now = Date()
    let member = TeamMemberStatus(
        id: "u", name: "n", status: .working, updatedAt: nil,
        currentSessionStartedAt: now.addingTimeInterval(-50)
    )
    #expect(member.presence(now: now) == .activeWorking)
    #expect(member.currentDurationSeconds(now: now) == 50)
}

@MainActor
@Test
func presenceFreezesStaleWorkingAtLastSignal() {
    let now = Date()
    let start = now.addingTimeInterval(-600)
    let seen = now.addingTimeInterval(-200) // 마지막 신호 200초 전(>90초) → stale
    let member = TeamMemberStatus(
        id: "u", name: "n", status: .working, updatedAt: nil,
        currentSessionStartedAt: start, weeklyDurationSeconds: 1_000,
        lastSeenAt: seen
    )
    let frozen = Int(seen.timeIntervalSince(start)) // 400초

    #expect(member.presence(now: now) == .staleWorking(frozenDurationSeconds: frozen))
    // now(600초)가 아니라 마지막 신호 시각(400초)으로 동결되어 죽은 세션이 카운트를 부풀리지 않는다.
    #expect(member.currentDurationSeconds(now: now) == frozen)
    #expect(member.liveWeeklyDurationSeconds(now: now) == 1_000 + frozen)
}

@MainActor
@Test
func presenceFallsBackToUpdatedAtWhenLastSeenNil() {
    let now = Date()
    let start = now.addingTimeInterval(-1_000)
    let updated = now.addingTimeInterval(-300) // >90초 → stale
    let member = TeamMemberStatus(
        id: "u", name: "n", status: .working, updatedAt: updated,
        currentSessionStartedAt: start
    )
    #expect(member.presence(now: now) == .staleWorking(frozenDurationSeconds: Int(updated.timeIntervalSince(start))))
}

// MARK: - D1: 하트비트

@MainActor
@Test
func heartbeatUpsertsLastSeenWhileWorking() async {
    let testHost = "heartbeat-test"
    let store = makeStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    store.startedAt = Date()
    store.currentSessionID = "hb-session"

    await store.sendHeartbeatIfWorking()

    let requests = URLProtocolStub.requests(forHost: testHost)
    let bodies = URLProtocolStub.bodiesByHost[testHost] ?? []
    let upserts = zip(requests, bodies)
        .filter { $0.0.url?.path == "/rest/v1/work_statuses" && $0.0.httpMethod == "POST" }
        .map { $0.1 }
    #expect(upserts.count == 1)
    #expect(upserts.first?.contains(#""status":"working""#) == true)
    #expect(upserts.first?.contains(#""last_seen_at""#) == true)
    #expect(upserts.first?.contains(#""active_session_id":"hb-session""#) == true)
}

@MainActor
@Test
func heartbeatSkippedWhenNotWorking() async {
    let testHost = "heartbeat-idle-test"
    let store = makeStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    store.startedAt = nil
    store.currentSessionID = "hb-session"

    await store.sendHeartbeatIfWorking()

    #expect(URLProtocolStub.requests(forHost: testHost).isEmpty)
}

// MARK: - D3: 본인 죽은 세션 자동 마감 + 되돌리기

@MainActor
@Test
func abandonedOwnSessionIsAutoClosedAndUndoable() async {
    let testHost = "abandoned-session-test"
    let store = makeStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    // 로컬 비근무 + 서버엔 오래된 신호의 열린 세션 → 자동 마감 조건.
    #expect(store.startedAt == nil)
    #expect(!store.canUndoAutoClose)

    await store.refreshTeamStatus()

    #expect(store.startedAt == nil)
    #expect(store.syncMessage == "자리 비움으로 자동 근무종료됨")
    #expect(store.canUndoAutoClose)
    #expect(store.lastAutoClosedSessionID == "50000000-0000-0000-0000-000000000001")
    let closedWithPatch = URLProtocolStub.requests(forHost: testHost).contains {
        $0.url?.path == "/rest/v1/work_sessions" && $0.httpMethod == "PATCH"
    }
    #expect(closedWithPatch)

    await store.performUndoAutoClose()

    #expect(store.startedAt != nil)
    #expect(store.currentSessionID == "50000000-0000-0000-0000-000000000001")
    #expect(!store.canUndoAutoClose)
    #expect(store.snapshot.isWorking)
}

@MainActor
@Test
func liveLocalSessionIsNeverAutoClosedOnRefresh() async {
    // 네트워크가 끊긴 채 앱이 계속 살아 일하던 경우(로컬 startedAt != nil)는 자동 마감 금지.
    let testHost = "abandoned-session-test"
    let store = makeStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    let localStart = Date().addingTimeInterval(-3600)
    store.startedAt = localStart
    store.currentSessionID = "50000000-0000-0000-0000-000000000001"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3600)

    await store.refreshTeamStatus()

    #expect(store.startedAt == localStart)
    #expect(!store.canUndoAutoClose)
}

// MARK: - D4: 잠자기 정책 (5분 유예)

@MainActor
@Test
func wakeAfterLongSleepAutoStopsAtSleepMoment() async {
    let testHost = "sleep-stop-test"
    let store = makeStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    let sleepAt = Date()
    store.startedAt = sleepAt.addingTimeInterval(-3600)
    store.currentSessionID = "sleep-session"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3600)

    store.handleSleep(at: sleepAt)
    #expect(store.sleepBeganAt == sleepAt)

    store.handleWake(at: sleepAt.addingTimeInterval(6 * 60)) // 6분 > 5분 유예

    #expect(store.startedAt == nil)
    #expect(store.sleepBeganAt == nil)
    #expect(store.syncMessage == "잠자기로 자동 근무종료됨")
    #expect(store.pendingOperation == .stop(durationSeconds: 3600))
    #expect(store.pendingStopEndedAt == sleepAt) // 덮은 시각으로 마감
}

@MainActor
@Test
func wakeWithinGraceKeepsWorking() {
    let store = makeStubStore(host: "sleep-grace-test")
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    let sleepAt = Date()
    store.startedAt = sleepAt.addingTimeInterval(-3600)
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3600)

    store.handleSleep(at: sleepAt)
    store.handleWake(at: sleepAt.addingTimeInterval(3 * 60)) // 3분 ≤ 5분 유예

    #expect(store.startedAt != nil)
    #expect(store.sleepBeganAt == nil)
    #expect(store.pendingOperation == nil)
}

// MARK: - D5: 12시간 확인 (30분 무응답 자동 마감)

@MainActor
@Test
func longSessionPromptAppearsAtTwelveHours() {
    let store = makeStubStore(host: "long-session-prompt")
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    let t0 = Date()
    store.startedAt = t0
    store.longSessionAnchor = t0
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)

    store.evaluateLongSession(now: t0.addingTimeInterval(12 * 3600 - 10))
    #expect(!store.isLongSessionPromptActive)

    store.evaluateLongSession(now: t0.addingTimeInterval(12 * 3600 + 1))
    #expect(store.isLongSessionPromptActive)
    #expect(store.promptShownAt != nil)
}

@MainActor
@Test
func longSessionAutoStopsAfterThirtyMinutesUnconfirmed() {
    let store = makeStubStore(host: "long-session-autostop")
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    let t0 = Date()
    store.startedAt = t0
    store.longSessionAnchor = t0
    store.currentSessionID = "long-session"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)

    store.evaluateLongSession(now: t0.addingTimeInterval(12 * 3600 + 1))
    #expect(store.isLongSessionPromptActive)

    store.evaluateLongSession(now: t0.addingTimeInterval(12 * 3600 + 30 * 60 + 2))

    #expect(store.startedAt == nil)
    #expect(store.syncMessage == "장시간 미확인으로 자동 근무종료됨")
    // 12시간 시점으로 마감된다(30분치는 근무로 인정하지 않음).
    #expect(store.pendingStopEndedAt == t0.addingTimeInterval(12 * 3600))
}

@MainActor
@Test
func confirmStillWorkingDismissesPromptAndKeepsWorking() {
    let store = makeStubStore(host: "long-session-confirm")
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    let t0 = Date()
    store.startedAt = t0
    store.longSessionAnchor = t0
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)

    store.evaluateLongSession(now: t0.addingTimeInterval(12 * 3600 + 1))
    #expect(store.isLongSessionPromptActive)

    store.confirmStillWorking()
    #expect(!store.isLongSessionPromptActive)
    #expect(store.startedAt != nil)

    // 확인으로 카운터가 지금부터 리셋 → 방금 시점에서는 다시 뜨지 않고 마감되지도 않는다.
    store.evaluateLongSession(now: Date())
    #expect(!store.isLongSessionPromptActive)
    #expect(store.startedAt != nil)
}

// MARK: - D7: 이중 시작 친화 문구

@MainActor
@Test
func authMessageForSessionAlreadyOpenIsFriendly() {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    #expect(store.authMessage(for: SupabaseWorkServiceError.sessionAlreadyOpen, fallback: "x") == "이미 다른 곳에서 근무 중이에요")
}

// MARK: - D8: 아바타 업데이트 계약

@MainActor
@Test
func updateAvatarUploadsAndReportsSuccess() async {
    let testHost = "avatar-store-update"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: AvatarURLProtocol.session(forHost: testHost)
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
    store.currentTeamID = URLProtocolStub.stubTeamID

    await store.performAvatarUpdate(imageData: Data([0xFF, 0xD8, 0xFF]))

    #expect(store.syncMessage == "프로필 사진 변경됨")
    let requests = AvatarURLProtocol.requests(forHost: testHost)
    #expect(requests.contains {
        $0.url?.path == "/storage/v1/object/avatars/00000000-0000-0000-0000-000000000002.jpg"
            && $0.httpMethod == "POST"
    })
    #expect(requests.contains {
        $0.url?.path == "/rest/v1/profiles" && $0.httpMethod == "PATCH"
    })
}

@MainActor
private func makeStubStore(host: String, userID: String = "00000000-0000-0000-0000-000000000002") -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
    // 세션을 직접 주입하는 테스트는 로그인 흐름(confirmMembership)을 건너뛰므로 팀도 직접 확정한다.
    store.currentTeamID = URLProtocolStub.stubTeamID
    return store
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "check-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
