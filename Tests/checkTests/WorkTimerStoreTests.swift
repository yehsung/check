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

// MARK: - G: 초대코드 가입/합류/무소속

@MainActor
@Test
func signUpRequiresConfirmedTeamCode() {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    store.email = "new@example.com"
    store.password = "team-password"
    store.displayName = "영식"
    // 코드 모드인데 joinPreview 미확인 → 가입 거부.
    store.isCreateTeamMode = false
    store.joinPreview = nil

    let task = store.signUp()

    #expect(task == nil)
    #expect(store.syncMessage == "팀 코드를 확인해 주세요")
}

@MainActor
@Test
func signUpRequiresTeamNameInCreateMode() {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    store.email = "new@example.com"
    store.password = "team-password"
    store.displayName = "영식"
    // 만들기 모드인데 팀 이름 공백 → 가입 거부.
    store.isCreateTeamMode = true
    store.createTeamName = "   "

    let task = store.signUp()

    #expect(task == nil)
    #expect(store.syncMessage == "팀 이름을 입력해 주세요")
}

@MainActor
@Test
func signUpAutoJoinsWithTeamCodeAfterAccount() async {
    let testHost = "signup-join-test"
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
    store.isCreateTeamMode = false
    store.signupTeamCode = "SUDOPARK"
    // 미리보기가 확인된 상태(가입 버튼 활성 조건).
    store.joinPreview = TeamJoinPreview(teamID: "10000000-0000-0000-0000-000000000001", name: "sudo 박수", weeklyGoalHours: 40, memberCount: 3)

    await store.signUp()?.value

    #expect(store.isSignedIn)
    #expect(store.currentTeamID == "10000000-0000-0000-0000-000000000001")

    // 가입은 계정만 만들고 team_id 메타데이터는 보내지 않는다.
    #expect(!URLProtocolStub.bodyText(forHost: testHost).contains("\"team_id\""))

    // 요청 순서: 계정 가입(/auth/v1/signup) 이 먼저, 그 다음 자동 합류(/rest/v1/rpc/join_team).
    let paths = URLProtocolStub.requests(forHost: testHost).compactMap { $0.url?.path }
    let signupIndex = try? #require(paths.firstIndex(of: "/auth/v1/signup"))
    let joinIndex = try? #require(paths.firstIndex(of: "/rest/v1/rpc/join_team"))
    #expect(signupIndex != nil)
    #expect(joinIndex != nil)
    if let signupIndex, let joinIndex {
        #expect(signupIndex < joinIndex)
    }
    // 합류 본문에 정규화된 코드가 담긴다.
    #expect(URLProtocolStub.bodyText(forHost: testHost).contains(#""code":"SUDOPARK""#))
}

@MainActor
@Test
func signUpCreateModeSetsCreatedTeamCode() async {
    let testHost = "signup-create-test"
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
    store.email = "founder@example.com"
    store.password = "team-password"
    store.displayName = "창립자"
    store.isCreateTeamMode = true
    store.createTeamName = "새로운 팀"
    store.createTeamGoalHours = 50

    await store.signUp()?.value

    #expect(store.isSignedIn)
    // create_team 이 돌려준 참여코드가 공유 안내용으로 보관된다.
    #expect(store.createdTeamCode == "X7K2M9Q4")

    // 요청 순서: 가입(/auth/v1/signup) → 팀 생성(/rest/v1/rpc/create_team). join_team 은 호출하지 않는다.
    let paths = URLProtocolStub.requests(forHost: testHost).compactMap { $0.url?.path }
    #expect(paths.contains("/auth/v1/signup"))
    #expect(paths.contains("/rest/v1/rpc/create_team"))
    #expect(!paths.contains("/rest/v1/rpc/join_team"))

    // dismiss 로 안내를 닫을 수 있다.
    store.dismissCreatedTeamCode()
    #expect(store.createdTeamCode == nil)
}

@MainActor
@Test
func signInWithoutTeamShowsTeamCodePrompt() async {
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

    // 소속 팀이 없는 계정은 로그인은 되지만 팀 데이터는 비고 팀 코드 참여 안내가 뜬다.
    #expect(store.isSignedIn)
    #expect(store.isTeamless)
    #expect(store.currentTeamID == nil)
    #expect(store.teamName == "팀")
    #expect(store.teamMembers.isEmpty)
    #expect(store.syncMessage == "소속 팀이 없어요 — 팀 코드로 참여해 주세요")
}

@MainActor
@Test
func previewTeamCodeSuccessSetsJoinPreview() async {
    let store = WorkTimerStore(
        service: SupabaseWorkService(
            projectURL: URL(string: "http://preview-code-test")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        ),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    store.signupTeamCode = "SUDOPARK"

    await store.performPreviewTeamCode()

    #expect(store.joinPreview == TeamJoinPreview(
        teamID: "10000000-0000-0000-0000-000000000001",
        name: "sudo 박수",
        weeklyGoalHours: 40,
        memberCount: 3
    ))
    #expect(store.joinPreviewMessage == "")
}

@MainActor
@Test
func previewTeamCodeMissSetsMessage() async {
    let store = WorkTimerStore(
        service: SupabaseWorkService(
            projectURL: URL(string: "http://preview-code-miss")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        ),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    store.signupTeamCode = "NOSUCHXX"

    await store.performPreviewTeamCode()

    #expect(store.joinPreview == nil)
    #expect(store.joinPreviewMessage == "코드를 확인해 주세요")
}

@MainActor
@Test
func previewTeamCodeNormalizesInputInRequest() async {
    let testHost = "preview-normalize-test"
    let store = WorkTimerStore(
        service: SupabaseWorkService(
            projectURL: URL(string: "http://\(testHost)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        ),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    // 공백/소문자 섞인 입력이 정규화되어("X7K2M9Q4") 서버로 나가야 한다.
    store.signupTeamCode = "x7k2 m9q4"

    await store.performPreviewTeamCode()

    #expect(store.joinPreview != nil)
    #expect(URLProtocolStub.bodyText(forHost: testHost).contains(#""code":"X7K2M9Q4""#))
}

@MainActor
@Test
func joinTeamWithCodeJoinsWhenTeamless() async {
    let testHost = "teamless-join-test"
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
    // 무소속 로그인 상태를 직접 세팅.
    store.session = SupabaseSession(
        accessToken: "access-token",
        refreshToken: nil,
        userID: "00000000-0000-0000-0000-000000000002"
    )
    store.currentTeamID = nil
    #expect(store.isTeamless)
    store.signupTeamCode = "SUDOPARK"

    await store.performJoinTeamWithCode()

    // 합류 후 팀이 확정되고, 입력 코드/미리보기는 비워진다.
    #expect(store.currentTeamID == "10000000-0000-0000-0000-000000000001")
    #expect(!store.isTeamless)
    #expect(store.signupTeamCode == "")
    #expect(store.joinPreview == nil)
    let paths = URLProtocolStub.requests(forHost: testHost).compactMap { $0.url?.path }
    #expect(paths.contains("/rest/v1/rpc/join_team"))
}

@MainActor
@Test
func ownerMembershipLoadsInviteCode() async {
    let testHost = "owner-code-test"
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

    await store.confirmMembership()

    // owner 로 확정되면 팀 카드 공유용 참여코드를 로드한다.
    #expect(store.isTeamOwner)
    #expect(store.teamRole == "owner")
    #expect(store.myTeamInviteCode == "SUDOPARK")
}

@MainActor
@Test
func memberMembershipLeavesInviteCodeNil() async {
    let testHost = "team-hours-test"
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

    await store.confirmMembership()

    // member 는 owner 가 아니므로 참여코드를 로드하지 않는다.
    #expect(!store.isTeamOwner)
    #expect(store.teamRole == "member")
    #expect(store.myTeamInviteCode == nil)
}

// MARK: - K: 팀 리그 (로드/정렬/초기화)

@MainActor
@Test
func loadLeaderboardSortsByAverageDescending() async {
    let testHost = "leaderboard-store-test"
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

    await store.performLoadLeaderboard()

    // 목표가 1인당이라 정렬은 총합이 아니라 1인당 평균(총합 ÷ 인원) 내림차순이어야 한다.
    // 평균: 코드 36000/1=36000, 오목교 90000/3=30000, 내 팀 72000/3=24000 → [36000, 30000, 24000].
    #expect(store.leaderboard.count == 3)
    #expect(store.leaderboard.map(\.averageSeconds) == [36000, 30000, 24000])
    // 총합 1위(오목교 90000)는 평균으로는 2위 — 평균 역전이 반영됐다.
    #expect(store.leaderboard.map(\.totalSeconds) == [36000, 90000, 72000])
    #expect(store.leaderboard[1].name == "오목교 브라더스")
    // 내 팀(stubTeamID)은 평균 24000 으로 3위다.
    #expect(store.leaderboard[2].id == URLProtocolStub.stubTeamID)
}

@MainActor
@Test
func toggleLeaderboardOpensAndClosesPage() async {
    let testHost = "leaderboard-toggle-test"
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
    #expect(!store.isLeaderboardVisible)

    // 여는 순간 페이지가 노출되고 순위 로드(Task)가 발사된다.
    store.toggleLeaderboard()
    #expect(store.isLeaderboardVisible)
    // loadLeaderboard 는 Task 를 발사하므로 목록이 채워질 때까지 폴링한다(로그아웃 폴링과 같은 패턴).
    var loaded = false
    for _ in 0..<200 {
        if store.leaderboard.count == 3 {
            loaded = true
            break
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(loaded)

    // 다시 토글하면 페이지가 닫힌다.
    store.toggleLeaderboard()
    #expect(!store.isLeaderboardVisible)
}

@MainActor
@Test
func signOutClearsLeaderboardState() async {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://leaderboard-signout-test")!,
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
    store.isLeaderboardVisible = true
    store.leaderboard = [
        TeamLeaderboardEntry(id: URLProtocolStub.stubTeamID, name: "sudo 박수", weeklyGoalHours: 40, totalSeconds: 72000, workingCount: 3, memberCount: 3)
    ]

    store.signOut()

    // 로그아웃 시 리그 페이지 상태(목록·노출 플래그)가 초기화되어야 한다.
    #expect(store.leaderboard.isEmpty)
    #expect(!store.isLeaderboardVisible)
}

@MainActor
@Test
func myWeeklyGaugeUsesMyRowNotTeamTotal() {
    // 주간 목표 게이지 분자는 팀 총합이 아니라 "내 행" 의 라이브 주간 누적이어야 한다(목표가 1인당이므로).
    let now = Date()
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://my-weekly-gauge-test")!,
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.displayNow = now
    store.teamGoalSeconds = 60 * 3600
    store.teamMembers = [
        TeamMemberStatus(id: "me", name: "나", status: .offWork, updatedAt: nil, currentSessionStartedAt: nil, weeklyDurationSeconds: 12 * 3600 + 30 * 60),
        TeamMemberStatus(id: "other", name: "동료", status: .offWork, updatedAt: nil, currentSessionStartedAt: nil, weeklyDurationSeconds: 40 * 3600)
    ]

    // 내 주간 = 내 행만(12시간 30분) — 팀 총합(52시간 30분)이 아니다.
    #expect(store.myLiveWeeklySeconds == 12 * 3600 + 30 * 60)
    // 게이지 = 내 주간 ÷ 목표(60시간) ≈ 0.208.
    let goal = TeamWeeklyGoal(workedSeconds: store.myLiveWeeklySeconds, goalSeconds: store.teamGoalSeconds)
    #expect(abs(goal.progress - Double(12 * 3600 + 30 * 60) / Double(60 * 3600)) < 1e-9)

    // 내 행을 못 받은 초기엔 오늘 누적(0)으로 폴백한다.
    store.teamMembers = []
    #expect(store.myLiveWeeklySeconds == store.todayDuration)
}

// MARK: - 팀별 주간 목표시간 (teams.weekly_goal_hours 읽기 전용)

@MainActor
@Test
func confirmMembershipAppliesServerWeeklyGoal() async {
    let testHost = "signin-goal-test"
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

    #expect(store.isSignedIn)
    // 서버 픽스처의 weekly_goal_hours=40 이 초 단위 목표로 반영되어야 한다.
    #expect(store.teamGoalSeconds == 40 * 3600)
    // 게이지 계산: 20시간 근무 / 40시간 목표 → 진행률 0.5, 미완료.
    let gauge = TeamWeeklyGoal(workedSeconds: 20 * 3600, goalSeconds: store.teamGoalSeconds)
    #expect(gauge.progress == 0.5)
    #expect(!gauge.isComplete)
}

@MainActor
@Test
func confirmMembershipFallsBackToDefaultWeeklyGoalWhenFieldMissing() async {
    let testHost = "membership-no-goal-test"
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
    // 폴백이 실제로 값을 덮어쓰는지 보이기 위해 다른 값으로 미리 오염시킨다.
    store.teamGoalSeconds = 10 * 3600

    await store.signIn()?.value

    #expect(store.isSignedIn)
    // weekly_goal_hours 누락 팀은 기본 목표(60시간)로 폴백한다.
    #expect(store.teamGoalSeconds == TeamWeeklyGoal.defaultGoalSeconds)
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
    store.teamGoalSeconds = 40 * 3600
    store.teamRole = "owner"
    store.myTeamInviteCode = "SUDOPARK"
    store.teamDirectory = [TeamDirectoryEntry(id: "t", name: "n")]
    store.selectedSignupTeamID = "t"
    store.signupTeamCode = "SUDOPARK"
    store.joinPreview = TeamJoinPreview(teamID: "t", name: "n", weeklyGoalHours: 40, memberCount: 1)
    store.joinPreviewMessage = "확인 중"
    store.isCreateTeamMode = true
    store.createTeamName = "새 팀"
    store.createTeamGoalHours = 30
    store.createdTeamCode = "X7K2M9Q4"
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
    #expect(store.teamGoalSeconds == TeamWeeklyGoal.defaultGoalSeconds)
    #expect(store.teamRole == nil)
    #expect(store.myTeamInviteCode == nil)
    #expect(store.teamDirectory.isEmpty)
    #expect(store.selectedSignupTeamID == nil)
    #expect(store.signupTeamCode == "")
    #expect(store.joinPreview == nil)
    #expect(store.joinPreviewMessage == "")
    #expect(!store.isCreateTeamMode)
    #expect(store.createTeamName == "")
    #expect(store.createTeamGoalHours == 60)
    #expect(store.createdTeamCode == nil)
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
        let bodies = URLProtocolStub.bodies(forHost: testHost)
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
    let bodies = URLProtocolStub.bodies(forHost: testHost)
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

// MARK: - Wave7: 리액션 트리거(스토어 감지)

@MainActor
@Test
func timeMilestoneTriggersOnceWhenTodayCrossesOneHour() {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedDefaults()
    )
    defer { store.tickerTask?.cancel() }
    var events: [ReactionKind] = []
    store.onReactionTrigger = { events.append($0) }

    let now = Date()
    store.startedAt = now.addingTimeInterval(-3_601) // 오늘 누적 1시간 1초
    store.displayNow = now

    store.evaluateTimeMilestones(now: now)
    #expect(events == [.milestone])
    // 같은 날 재평가해도 추가로 터지지 않는다(1일 1회).
    store.evaluateTimeMilestones(now: now)
    #expect(events == [.milestone])
}

@MainActor
@Test
func timeMilestoneAtFourHoursSuppressesBelatedOneHour() {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedDefaults()
    )
    defer { store.tickerTask?.cancel() }
    var events: [ReactionKind] = []
    store.onReactionTrigger = { events.append($0) }

    let now = Date()
    store.startedAt = now.addingTimeInterval(-(4 * 3_600 + 1)) // 이미 4시간 넘김
    store.displayNow = now

    store.evaluateTimeMilestones(now: now)
    // 4시간 축하 한 번만. 1시간 키는 조용히 소비되어 뒤늦게 터지지 않는다.
    #expect(events == [.milestone])
    store.evaluateTimeMilestones(now: now)
    #expect(events == [.milestone])
}

@MainActor
@Test
func detectTeamReactionsEmitsGreetingOnOffToWorkingTransition() {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedDefaults()
    )
    defer { store.tickerTask?.cancel() }
    var events: [ReactionKind] = []
    store.onReactionTrigger = { events.append($0) }
    store.session = SupabaseSession(
        accessToken: "access-token", refreshToken: nil,
        userID: "00000000-0000-0000-0000-000000000002"
    )
    store.currentTeamID = "team-id"
    store.teamGoalSeconds = TeamWeeklyGoal.defaultGoalSeconds

    // 첫 로드: 시드만, 인사 없음.
    store.teamMembers = [
        TeamMemberStatus(id: "other", name: "동료", status: .offWork, updatedAt: nil, currentSessionStartedAt: nil)
    ]
    store.detectTeamReactions()
    #expect(events.isEmpty)

    // offWork→working 전이 → 인사 이벤트.
    store.teamMembers = [
        TeamMemberStatus(id: "other", name: "동료", status: .working, updatedAt: nil, currentSessionStartedAt: nil)
    ]
    store.detectTeamReactions()
    #expect(events == [.greeting(name: "동료")])
}

@MainActor
@Test
func detectTeamReactionsCelebratesTeamGoalCrossingOnce() {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedDefaults()
    )
    defer { store.tickerTask?.cancel() }
    var events: [ReactionKind] = []
    store.onReactionTrigger = { events.append($0) }
    store.session = SupabaseSession(
        accessToken: "access-token", refreshToken: nil,
        userID: "00000000-0000-0000-0000-000000000002"
    )
    store.currentTeamID = "team-id"
    store.teamGoalSeconds = 40 * 3_600

    func worked(_ seconds: Int) -> TeamMemberStatus {
        TeamMemberStatus(
            id: "x", name: "x", status: .offWork, updatedAt: nil,
            currentSessionStartedAt: nil, weeklyDurationSeconds: seconds
        )
    }

    // 첫 로드: 목표 미달(10h/40h) — 전이로 치지 않는다.
    store.teamMembers = [worked(10 * 3_600)]
    store.detectTeamReactions()
    #expect(events.isEmpty)

    // 목표 100% 돌파(41h) — 미완료→완료 전이 시 1회 축하.
    store.teamMembers = [worked(41 * 3_600)]
    store.detectTeamReactions()
    #expect(events.filter { $0 == .milestone }.count == 1)

    // 완료 유지 상태에선 재축하하지 않는다.
    store.detectTeamReactions()
    #expect(events.filter { $0 == .milestone }.count == 1)
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
