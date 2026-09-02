import Foundation
import Observation
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
    store.signupTeamCode = "AINGTEAM"
    // 미리보기가 확인된 상태(가입 버튼 활성 조건).
    store.joinPreview = TeamJoinPreview(teamID: "10000000-0000-0000-0000-000000000001", name: "아잉팀", weeklyGoalHours: 40, memberCount: 3)

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
    #expect(URLProtocolStub.bodyText(forHost: testHost).contains(#""code":"AINGTEAM""#))
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
    store.signupTeamCode = "AINGTEAM"

    await store.performPreviewTeamCode()

    #expect(store.joinPreview == TeamJoinPreview(
        teamID: "10000000-0000-0000-0000-000000000001",
        name: "아잉팀",
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
    store.signupTeamCode = "AINGTEAM"

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
    #expect(store.myTeamInviteCode == "AINGTEAM")
}

@MainActor
@Test
func memberMembershipAlsoLoadsInviteCode() async {
    // B2: 참여코드는 이제 owner 뿐 아니라 소속 팀원 누구나 로드한다(코드가 곧 열쇠 — 팀원도 새 동료 초대).
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

    // 역할은 member 지만(owner 아님) 참여코드는 로드된다.
    #expect(!store.isTeamOwner)
    #expect(store.teamRole == "member")
    #expect(store.myTeamInviteCode == "AINGTEAM")
}

// FIX: loadMyInviteCode 일시 실패(취소/네트워크)는 try? 로 nil 을 삼켜 코드 버튼을 깜빡 지우지 않는다 —
// throw 시 기존 myTeamInviteCode 를 유지(대입 스킵)하고, 정상 0행일 때만 nil 로 확정한다.
@MainActor
@Test
func inviteCodeFetchFailureKeepsExistingCode() async {
    let testHost = "invite-code-fails"
    let store = makeStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    store.myTeamInviteCode = "OLDCODE1" // 이미 로드돼 있던 참여코드.

    // refreshTeamMeta: 멤버십은 정상(member/40h)이지만 my_team_invite_code RPC 는 500 으로 throw 한다.
    await store.refreshTeamMeta()

    // 일시 실패라 기존 코드를 유지한다(nil 로 깜빡 지우지 않음). 팀 목표 등 나머지는 정상 반영.
    #expect(store.myTeamInviteCode == "OLDCODE1")
    #expect(store.teamGoalSeconds == 40 * 3600)
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
        TeamLeaderboardEntry(id: URLProtocolStub.stubTeamID, name: "아잉팀", weeklyGoalHours: 40, totalSeconds: 72000, workingCount: 3, memberCount: 3)
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

// MARK: - B3: 팀 목표 팀원 수정 (updateTeamGoal / 팀 메타 스로틀)

@MainActor
@Test
func updateTeamGoalSucceedsAndAppliesServerValue() async {
    let testHost = "update-goal-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: GoalRPCURLProtocol.session()
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.currentTeamID = URLProtocolStub.stubTeamID
    // 서버 반영값으로 덮이는지 보이려 다른 값으로 미리 오염시킨다.
    store.teamGoalSeconds = 10 * 3600
    let genBefore = store.teamGoalWriteGeneration

    let ok = await store.updateTeamGoal(hours: 37)

    #expect(ok)
    // 서버가 에코한 새 목표(37시간)가 초 단위로 반영된다.
    #expect(store.teamGoalSeconds == 37 * 3600)
    #expect(store.syncMessage == "주간 목표 변경됨")
    // 성공 시 목표 write 세대가 +1 되어, 이후 도착하는 낡은 멤버십 응답이 목표를 되돌리지 못한다.
    #expect(store.teamGoalWriteGeneration == genBefore + 1)
    // 중복 방지 플래그는 완료 후 해제된다.
    #expect(!store.isUpdatingTeamGoal)
    let paths = GoalRPCURLProtocol.requests(forHost: testHost).compactMap { $0.url?.path }
    #expect(paths.contains("/rest/v1/rpc/set_team_weekly_goal"))
}

@MainActor
@Test
func updateTeamGoalRejectsOutOfRangeWithoutRequest() async {
    let testHost = "update-goal-range-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: GoalRPCURLProtocol.session()
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamGoalSeconds = 40 * 3600

    let tooHigh = await store.updateTeamGoal(hours: 200)
    let tooLow = await store.updateTeamGoal(hours: 0)

    #expect(!tooHigh)
    #expect(!tooLow)
    // 범위(1~168) 밖은 네트워크로 나가지 않고 목표도 그대로 유지된다.
    #expect(store.teamGoalSeconds == 40 * 3600)
    #expect(GoalRPCURLProtocol.requests(forHost: testHost).isEmpty)
}

@MainActor
@Test
func updateTeamGoalReportsFailureAndKeepsGoalOnServerError() async {
    // host 에 "fail" 이 들어가면 GoalRPCURLProtocol 이 500(본문 없음) 을 돌려 실패 경로를 재현한다.
    let testHost = "update-goal-fail-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: GoalRPCURLProtocol.session()
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamGoalSeconds = 40 * 3600

    let ok = await store.updateTeamGoal(hours: 50)

    #expect(!ok)
    // 실패 시 목표는 그대로 유지되고, 변경 실패 안내가 뜬다.
    #expect(store.teamGoalSeconds == 40 * 3600)
    #expect(store.syncMessage == "목표 변경 실패")
    #expect(!store.isUpdatingTeamGoal)
}

@MainActor
@Test
func refreshTeamMetaIfStaleThrottlesWithinWindow() async {
    // 팝오버 열 때 60초 스로틀로 멤버십을 재조회해 팀원이 바꾼 목표를 반영한다.
    // team-hours-test 픽스처는 목표 40시간(member)을 돌려준다.
    let store = makeStubStore(host: "team-hours-test")
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    // 재조회로 덮이는지 보이려 다른 값으로 오염시킨다.
    store.teamGoalSeconds = 10 * 3600
    let t0 = Date(timeIntervalSince1970: 100_000)

    // 첫 호출: distantPast 이후라 발사된다(스로틀 시각이 t0 로 갱신).
    store.refreshTeamMetaIfStale(now: t0)
    #expect(store.lastTeamMetaRefreshAt == t0)
    var applied = false
    for _ in 0..<200 {
        if store.teamGoalSeconds == 40 * 3600 { applied = true; break }
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(applied)

    // 스로틀 안(30초 뒤): 재발사하지 않는다 — 타임스탬프도 목표도 그대로.
    store.teamGoalSeconds = 99
    store.refreshTeamMetaIfStale(now: t0.addingTimeInterval(30))
    #expect(store.lastTeamMetaRefreshAt == t0)
    try? await Task.sleep(for: .milliseconds(30))
    #expect(store.teamGoalSeconds == 99)

    // 스로틀 지난 뒤(61초): 다시 발사되어 서버 목표(40시간)로 재수렴한다.
    store.refreshTeamMetaIfStale(now: t0.addingTimeInterval(61))
    #expect(store.lastTeamMetaRefreshAt == t0.addingTimeInterval(61))
    var reapplied = false
    for _ in 0..<200 {
        if store.teamGoalSeconds == 40 * 3600 { reapplied = true; break }
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(reapplied)
}

@MainActor
@Test
func refreshTeamMetaIfStaleSkipsWhenSignedOutOrTeamless() {
    // 로그인 안 됨/무소속이면 재조회를 발사하지 않는다(스로틀 시각도 건드리지 않는다).
    let signedOut = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedDefaults()
    )
    defer { signedOut.tickerTask?.cancel() }
    signedOut.refreshTeamMetaIfStale(now: Date())
    #expect(signedOut.lastTeamMetaRefreshAt == .distantPast)

    let teamless = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedDefaults()
    )
    defer { teamless.tickerTask?.cancel() }
    teamless.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "u")
    teamless.currentTeamID = nil
    teamless.refreshTeamMetaIfStale(now: Date())
    #expect(teamless.lastTeamMetaRefreshAt == .distantPast)
}

@MainActor
@Test
func teammateTickerRunsOnlyWhilePopoverPresented() {
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

    // 팝오버 닫힘: 팀원이 근무중이어도 초침 티커를 돌리지 않는다(숨김 상태 매초 재평가 낭비 방지).
    store.stopTimerIfIdle()
    #expect(store.tickerTask == nil)

    // 팝오버 열림: 팀원 초침을 위해 티커를 재개한다(setMenuPresented 가 내부에서 게이팅을 재평가).
    store.setMenuPresented(true)
    #expect(store.tickerTask != nil)

    // 팀원이 모두 근무종료면 팝오버가 열려 있어도 티커를 정지한다.
    store.teamMembers = []
    store.stopTimerIfIdle()
    #expect(store.tickerTask == nil)

    // 팝오버가 닫히면 티커 재평가만 하고 계속 정지 상태를 유지한다.
    store.setMenuPresented(false)
    #expect(store.tickerTask == nil)
}

@MainActor
@Test
func selfWorkingKeepsTickerRegardlessOfPopover() {
    // 내가 근무중이면 팝오버 상태와 무관하게 티커를 항상 유지한다(12h 확인/마일스톤/라벨).
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedDefaults()
    )
    defer { store.tickerTask?.cancel() }
    store.startedAt = Date(timeIntervalSinceNow: -60)

    store.stopTimerIfIdle()
    #expect(store.tickerTask != nil)

    // 팝오버가 닫혀 있어도 근무중이면 유지.
    store.setMenuPresented(false)
    store.stopTimerIfIdle()
    #expect(store.tickerTask != nil)
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
    #expect(store.pendingItems.map(\.operation) == [.stop(durationSeconds: 100)])

    await store.refreshTeamStatus()

    #expect(store.startedAt == nil)
    #expect(store.pendingItems.map(\.operation) == [.stop(durationSeconds: 100)])
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
    store.pendingItems = [
        PendingWorkItem(
            id: UUID(),
            operation: .stop(durationSeconds: 50),
            sessionID: "50000000-0000-0000-0000-0000000000aa",
            sessionStartedAt: Date(timeIntervalSince1970: 2000),
            endedAt: Date(timeIntervalSince1970: 2050)
        )
    ]

    await store.retryPendingSync()
    #expect(store.pendingItems.map(\.operation) == [.stop(durationSeconds: 50)])

    URLProtocolStub.patchWorkSessionsShouldFail = false
    await store.retryPendingSync()
    #expect(store.pendingItems.isEmpty)
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
    store.teamName = "아잉팀"
    store.teamGoalSeconds = 40 * 3600
    store.teamRole = "owner"
    store.myTeamInviteCode = "AINGTEAM"
    store.teamDirectory = [TeamDirectoryEntry(id: "t", name: "n")]
    store.selectedSignupTeamID = "t"
    store.signupTeamCode = "AINGTEAM"
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
    store.pendingItems = [
        PendingWorkItem(id: UUID(), operation: .start, sessionID: "s", sessionStartedAt: Date(), endedAt: nil)
    ]
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
    #expect(store.pendingItems.isEmpty)
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
    func rapidStartStopSerializesBothOperationsInOrder() async {
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

        // FIFO 큐는 빠른 시작→종료를 붕괴시키지 않고 순서대로 재생한다(단일 슬롯이 .start 를 삼키던 이전
        // 동작을 대체 — in-flight 중 반대 조작/오프라인 세션 유실을 막기 위한 의도된 변경).
        // 시작(working)과 종료(off_work) 상태 전이가 각각 정확히 한 번, 그 순서로 나가고 큐는 완전히 비워진다.
        #expect(workingUpserts.count == 1)
        #expect(offWorkUpserts.count == 1)
        let firstWorking = statusUpsertBodies.firstIndex { $0.contains(#""status":"working""#) }
        let firstOffWork = statusUpsertBodies.firstIndex { $0.contains(#""status":"off_work""#) }
        if let firstWorking, let firstOffWork {
            #expect(firstWorking < firstOffWork)
        }
        #expect(store.pendingItems.isEmpty)
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
        #expect(!store.pendingItems.isEmpty)
    }

    /// 요청이 스텁에 기록될 때까지 기다린다(지연 응답 호스트에서 '왕복 중' 시점을 잡기 위한 동기화 지점).
    /// 기록은 startLoading 에서 일어나고 응답 전달만 responseDelay 만큼 늦으므로, true 를 받은 직후가
    /// 그 요청의 in-flight 구간 한복판이다.
    private func waitForRequest(
        host: String,
        timeout: Duration = .seconds(3),
        where predicate: @escaping (URLRequest) -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock().now + timeout
        while ContinuousClock().now < deadline {
            if URLProtocolStub.requests(forHost: host).contains(where: predicate) { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    @Test
    func autoCloseDoesNotOverwriteWorkStartedDuringItsRoundTrip() async {
        // 회귀 지점: 자리 비움 자동 마감은 stopWork RPC **이전**에만 근무 상태 write 세대를 봤다. 왕복(수백 ms)
        // 사이에 사용자가 [근무 시작]을 누르면 응답 도착 시 startedAt/currentSessionID 를 nil 로 되돌리고
        // "자리 비움으로 자동 근무종료됨" + [되돌리기] 를 띄웠다 — 방금 만든 세션은 서버에 열린 채 추적을 잃고
        // (팀원 화면 '근무중' 고착), 그 배너를 누르면 옛 세션으로 갈아치워져 타이머가 몇 시간 과거로 점프했다.
        // 지연 접두어 호스트를 쓴다 — delayedHosts 는 다른 스위트가 defer 로 통째로 비워 in-flight 창이
        // 소리 없이 0이 되고, 그러면 이 테스트가 '레이스를 재현하지 못한 채' 통과해 버린다.
        let testHost = "delayed-abandoned-session-race"

        let store = makeStubStore(host: testHost)
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
            store.syncTask?.cancel()
        }

        let refresh = Task { await store.refreshTeamStatus() }
        // 자동 마감 stopWork 의 첫 요청(열린 세션 PATCH)이 날아간 순간을 잡는다 — 응답은 아직 오지 않았다.
        let sawStopPatch = await waitForRequest(host: testHost) {
            $0.url?.path == "/rest/v1/work_sessions"
                && $0.httpMethod == "PATCH"
                && $0.url?.query?.contains("ended_at=is.null") == true
        }
        #expect(sawStopPatch)

        // 사용자가 '오프' 표시를 보고 근무를 시작한다(세대 +1).
        let manualStart = Date()
        store.start(now: manualStart)
        let newSessionID = store.currentSessionID
        await refresh.value

        // 자동 마감 응답이 도착해도 방금 시작한 근무를 되돌리지 않는다.
        #expect(store.startedAt == manualStart)
        #expect(store.currentSessionID == newSessionID)
        #expect(store.snapshot.isWorking)
        #expect(store.syncMessage != "자리 비움으로 자동 근무종료됨")
        // 되돌리기 배너도 뜨지 않는다 — 뜨면 옛 세션으로 현 세션을 갈아치우는 두 번째 사고가 이어진다.
        #expect(store.lastAutoClosedSessionID == nil)
        #expect(!store.canUndoAutoClose())

        await store.syncTask?.value
    }

    @Test
    func undoAutoCloseDoesNotOverwriteWorkStartedDuringItsRoundTrip() async {
        // 회귀 지점: performUndoAutoClose 의 startedAt 가드는 reopenSession RPC **이전**에만 있었다.
        // 왕복 중 [근무 시작]을 누르면 응답 도착 시 startedAt/currentSessionID 가 자동 마감된 옛 세션으로
        // 교체돼 큰 타이머가 몇 시간 전으로 점프하고, 방금 만든 세션은 서버에 열린 채 방치됐다.
        let testHost = "delayed-abandoned-session-undo-race"

        let store = makeStubStore(host: testHost)
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
            store.syncTask?.cancel()
        }

        // 자동 마감이 끝나 되돌리기 대상이 준비된 상태를 만든다.
        await store.refreshTeamStatus()
        #expect(store.canUndoAutoClose())
        let oldStart = store.lastAutoClosedStartedAt

        let undo = Task { await store.performUndoAutoClose() }
        // 재개 PATCH(id=eq.<옛 세션>)가 날아간 순간을 잡는다 — 응답은 아직 오지 않았다.
        let sawReopenPatch = await waitForRequest(host: testHost) {
            $0.url?.path == "/rest/v1/work_sessions"
                && $0.httpMethod == "PATCH"
                && $0.url?.query?.contains("id=eq.50000000-0000-0000-0000-000000000001") == true
        }
        #expect(sawReopenPatch)

        let manualStart = Date()
        store.start(now: manualStart)
        let newSessionID = store.currentSessionID
        await undo.value

        // 재개 응답이 도착해도 옛 세션으로 갈아치우지 않는다(타이머가 과거로 점프하지 않는다).
        #expect(store.startedAt == manualStart)
        #expect(store.startedAt != oldStart)
        #expect(store.currentSessionID == newSessionID)
        #expect(store.snapshot.isWorking)
        // 되돌리기 대상은 정리돼 배너가 남지 않는다.
        #expect(store.lastAutoClosedSessionID == nil)
        #expect(!store.canUndoAutoClose())

        await store.syncTask?.value
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
    #expect(store.pendingItems.isEmpty)
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
    #expect(store.pendingItems.isEmpty)
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
    // 기준시각은 주 한복판(KST 화요일 낮)으로 고정한다 — 벽시계면 KST 월요일 00시대에 세션 구간이
    // 주 시작으로 클리핑돼 라이브 주간 단언이 시각 의존으로 깨진다.
    let now = URLProtocolStub.weeklyFixtureNow
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

@MainActor
@Test
func reloginRestoresSessionIDSoHeartbeatResumes() async {
    // 회귀 지점: 토큰 만료 강제 로그아웃은 currentSessionID 만 지우고 진행 중 근무(startedAt)와 큐는 일부러
    // 남긴다(clearPersistedSession). 같은 계정으로 재로그인하면 서버는 여전히 '근무중', 로컬도 startedAt 이
    // 살아 있어 applyRemoteOwnStatus 가 (.working, .some) → default 로 빠지며 세션ID 를 복원하지 않았다.
    // 그러면 sendHeartbeatIfWorking 이 매 폴링마다 조용히 반환해 생존신호가 영영 끊기고(팀원 화면 '자리비움'),
    // 10분 뒤 내 앱의 스캐빈저가 내 세션을 로그아웃 시각으로 마감해 그 뒤 근무가 통째로 유실됐다.
    let testHost = "relogin-heartbeat-test"
    let userID = "00000000-0000-0000-0000-000000000002"
    let store = makeStubStore(host: testHost, userID: userID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    let sessionStart = Date().addingTimeInterval(-3_600)
    // 강제 로그아웃 직후의 로컬 상태: 근무는 그대로 흐르는데 세션ID 만 비어 있다.
    store.startedAt = sessionStart
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    store.currentSessionID = nil
    store.pendingItems = []
    // 재로그인 후 첫 폴링이 가져온 서버 스냅샷: 내 세션은 여전히 열려 있다.
    let serverSessionID = "30000000-0000-0000-0000-000000000009"
    store.teamMembers = [
        TeamMemberStatus(
            id: userID,
            name: "영식",
            status: .working,
            updatedAt: Date(),
            currentSessionStartedAt: sessionStart,
            weeklyDurationSeconds: 0,
            todayDurationSeconds: 0,
            avatarURL: nil,
            lastSeenAt: Date(),
            activeSessionID: serverSessionID
        )
    ]

    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    // 진행 중 근무는 건드리지 않고 세션ID 만 되살린다.
    #expect(store.startedAt == sessionStart)
    #expect(store.currentSessionID == serverSessionID)

    await store.sendHeartbeatIfWorking()
    let bodies = zip(URLProtocolStub.requests(forHost: testHost), URLProtocolStub.bodies(forHost: testHost))
        .filter { $0.0.url?.path == "/rest/v1/work_statuses" && $0.0.httpMethod == "POST" }
        .map { $0.1 }
    #expect(bodies.count == 1)
    #expect(bodies.first?.contains(#""active_session_id":"\#(serverSessionID)""#) == true)

    // 계약 변경(v0.2.15/D2): 로컬 세션ID 가 서버의 열린 세션과 다르면 **서버 쪽이 진실**이다. 부분 유니크 인덱스
    // (work_sessions_one_open_per_user)상 사용자당 열린 세션은 하나뿐이라, 내 id 는 이미 닫힌 세션을 가리킨다.
    // 예전엔 로컬 id 를 지켰는데(가로채기 금지), 그러면 하트비트가 닫힌 id 를 계속 갱신해 서버의 열린 세션은
    // 신호가 끊긴 채 방치되고 타이머만 계속 흘렀다. 이제 재흡수하고 '내가 연 세션이 아님' 표식을 세운다.
    store.currentSessionID = "local-session"
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    #expect(store.currentSessionID == serverSessionID)
    #expect(store.adoptedRemoteSession)
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
    #expect(!store.canUndoAutoClose())

    await store.refreshTeamStatus()

    #expect(store.startedAt == nil)
    #expect(store.syncMessage == "자리 비움으로 자동 근무종료됨")
    #expect(store.canUndoAutoClose())
    #expect(store.lastAutoClosedSessionID == "50000000-0000-0000-0000-000000000001")
    let closedWithPatch = URLProtocolStub.requests(forHost: testHost).contains {
        $0.url?.path == "/rest/v1/work_sessions" && $0.httpMethod == "PATCH"
    }
    #expect(closedWithPatch)

    await store.performUndoAutoClose()

    #expect(store.startedAt != nil)
    #expect(store.currentSessionID == "50000000-0000-0000-0000-000000000001")
    #expect(!store.canUndoAutoClose())
    #expect(store.snapshot.isWorking)
}

// MARK: - R1: 자리 비움 자동 마감 임계는 백스톱과 **같은 계약**에서 나온다

@MainActor
@Test
func autoCloseFixturesStraddleTheContractThreshold() {
    // 아래 두 호스트가 '계약 안/밖'을 실제로 가르는지 여기서 못 박는다. 스텁은 @MainActor 격리된 상수를
    // 읽을 수 없어 리터럴을 쓰므로, 파생 관계는 이 테스트가 유일하게 지킨다 — 이게 없으면 임계가 바뀔 때
    // 픽스처가 조용히 한쪽으로 넘어가 아래 두 테스트가 아무것도 검증하지 않게 된다.
    #expect(URLProtocolStub.signalGapInsideContract < WorkTimerStore.adoptedReclaimStaleSeconds)
    #expect(URLProtocolStub.signalGapOutsideContract > WorkTimerStore.adoptedReclaimStaleSeconds)
    #expect(URLProtocolStub.staleTodaySessionSignalGap > WorkTimerStore.adoptedReclaimStaleSeconds)
    // 3분 낮잠은 이 앱 자신의 잠자기 유예 계약 한가운데다 — "정상 근무"로 인정되는 구간이라는 뜻이다.
    #expect(URLProtocolStub.ownerNapSignalGap < WorkTimerStore.sleepGraceSeconds)
}

@MainActor
@Test
func ownerMacTakingThreeMinuteNapIsNotAutoClosedByAnotherMac() async {
    // **R1 의 재현 조건 그대로.** 맥 A 는 살아 있다 — 뚜껑을 3분 닫은 것뿐이고, 이 앱의 계약상 5분 이하
    // 잠자기는 근무 연속으로 인정된다(sleepGraceSeconds). 그런데 자동 마감 임계만 90초로 하드코딩돼 있어
    // **맥 B 를 켜는 것만으로** A 의 살아 있는 세션이 마감됐다(실측: PATCH 1건, ended_at = 180.9초 전,
    // "자리 비움으로 자동 근무종료됨"). 그 뒤 A 의 근무는 통째로 유실된다.
    // 이제 임계가 백스톱과 같은 상수(adoptedReclaimStaleSeconds = 7분)라 3분 낮잠은 계약 안이다.
    let testHost = URLProtocolStub.ownerNapHost
    let store = makeStubStore(host: testHost)
    // 픽스처와 같은 '지금'을 주입한다. 이 호스트군은 신호 공백을 임계 바로 옆에 두므로, 픽스처 생성과
    // 스토어 판정 사이의 지연(전체 스위트에선 60초를 넘는다)이 그대로 공백에 더해져 '계약 안'이 밖으로
    // 넘어간다 — 시각을 고정하지 않으면 이 R1 단언이 무작위로 빨개진다.
    pinClock(store, to: URLProtocolStub.ownerSignalFixture(forHost: testHost)!.now)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    await store.refreshTeamStatus()

    // 마감이 일어나지 않았다 — 세션 쓰기(PATCH/POST)가 한 건도 없어야 한다.
    let wroteSession = URLProtocolStub.requests(forHost: testHost).contains {
        $0.url?.path == "/rest/v1/work_sessions" && $0.httpMethod != "GET"
    }
    #expect(!wroteSession)
    #expect(store.syncMessage != "자리 비움으로 자동 근무종료됨")
    #expect(store.lastAutoClosedSessionID == nil)
    #expect(!store.canUndoAutoClose())

    // 대신 정상 경로가 이어진다: B 는 A 의 세션을 흡수해 **미러링**한다(하트비트는 보내지 않는다).
    #expect(store.startedAt != nil)
    #expect(store.adoptedRemoteSession)
    #expect(store.currentSessionID == "51000000-0000-0000-0000-000000000001")
}

@MainActor
@Test
func autoCloseThresholdFollowsTheBackstopContractOnBothSides() async {
    // 두 임계(주장=백스톱 / 마감=여기)가 **한 상수에서** 나온다는 것을 경계 양쪽으로 고정한다.
    // 임계를 다시 하드코딩으로 갈라 놓으면 이 두 단언 중 하나가 반드시 깨진다.
    let underHost = URLProtocolStub.autoCloseUnderThresholdHost
    let underStore = makeStubStore(host: underHost)
    // 시각 고정(옆 R1 테스트와 같은 이유). 공백이 임계 -60초라, 메인 액터 점유로 판정이 60초만 밀려도
    // '계약 안'이 '계약 밖'으로 넘어가 이 단언이 무작위로 빨개진다(실제로 관측했다).
    pinClock(underStore, to: URLProtocolStub.ownerSignalFixture(forHost: underHost)!.now)
    defer {
        underStore.tickerTask?.cancel()
        underStore.refreshTask?.cancel()
    }
    await underStore.refreshTeamStatus()
    // 임계 -60초: 계약 안 = 살아 있는 근무다. 마감 금지.
    #expect(underStore.lastAutoClosedSessionID == nil)
    #expect(underStore.syncMessage != "자리 비움으로 자동 근무종료됨")

    // **대조군**: 진짜 방치(임계 +60초)는 여전히 마감되고 되돌리기가 제공돼야 한다. 이 짝이 없으면
    // "임계를 무한대로 키우면 통과"하는 가짜 수리를 걸러낼 수 없다.
    let overHost = URLProtocolStub.autoCloseOverThresholdHost
    let overStore = makeStubStore(host: overHost)
    pinClock(overStore, to: URLProtocolStub.ownerSignalFixture(forHost: overHost)!.now)
    defer {
        overStore.tickerTask?.cancel()
        overStore.refreshTask?.cancel()
    }
    await overStore.refreshTeamStatus()
    #expect(overStore.syncMessage == "자리 비움으로 자동 근무종료됨")
    #expect(overStore.lastAutoClosedSessionID == "51000000-0000-0000-0000-000000000001")
    #expect(overStore.canUndoAutoClose())
    #expect(overStore.startedAt == nil)
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
    #expect(!store.canUndoAutoClose())
}

// MARK: - 되돌리기 배너 수명(유예 만료 · 새 근무 시작 · 근무중 되돌리기 금지)

@MainActor
@Test
func autoCloseUndoExpiresAfterGraceWindow() async throws {
    // 회귀 지점: canUndoAutoClose 가 lastAutoClosedSessionID != nil 하나뿐이던 시절엔 배너가 로그아웃 전까지
    // 모든 팝오버에 상주했다. 이제는 자동 마감 후 유예(10분)가 지나면 스스로 사라진다.
    let testHost = "abandoned-session-test"
    let store = makeStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    await store.refreshTeamStatus()
    let closedAt = try #require(store.lastAutoClosedAt)

    #expect(store.canUndoAutoClose(now: closedAt.addingTimeInterval(WorkTimerStore.autoCloseUndoWindowSeconds - 1)))
    #expect(!store.canUndoAutoClose(now: closedAt.addingTimeInterval(WorkTimerStore.autoCloseUndoWindowSeconds + 1)))

    // 유예를 넘겨 누르면 되돌리지 않고 잔여 대상만 정리한다(배너가 다음 렌더에서 사라진다).
    store.lastAutoClosedAt = Date().addingTimeInterval(-(WorkTimerStore.autoCloseUndoWindowSeconds + 60))
    #expect(store.undoAutoClose() == nil)
    #expect(store.lastAutoClosedSessionID == nil)
    #expect(store.lastAutoClosedStartedAt == nil)
    #expect(store.lastAutoClosedAt == nil)
}

@MainActor
@Test
func startingNewWorkClearsAutoCloseUndo() async {
    // 회귀 지점: 배너를 무시하고 새 근무를 시작한 뒤 [되돌리기]를 누르면 진행 중 세션이 옛 세션으로 갈아치워졌다.
    // 이제 start() 가 되돌리기 대상을 즉시 끊고, 근무중에는 조건 자체가 거짓이다.
    let testHost = "abandoned-session-test"
    let store = makeStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    await store.refreshTeamStatus()
    #expect(store.canUndoAutoClose())

    store.start()
    #expect(store.lastAutoClosedSessionID == nil)
    #expect(!store.canUndoAutoClose())
    // 종료해도 되살아나지 않는다(옛 세션은 영구히 무효).
    store.stop()
    #expect(!store.canUndoAutoClose())
}

@MainActor
@Test
func undoAutoCloseRefusesWhileWorking() async {
    // 회귀 지점: performUndoAutoClose 에 startedAt 가드가 없어 진행 중 세션의 startedAt/currentSessionID 를
    // 옛 세션으로 덮었다(타이머가 과거로 점프 + 새 세션이 서버에 열린 채 방치).
    let testHost = "abandoned-session-test"
    let store = makeStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    await store.refreshTeamStatus()
    let oldSessionID = store.lastAutoClosedSessionID
    #expect(oldSessionID != nil)

    // 되돌리기 대상을 남긴 채로 근무를 시작한 상태를 인위적으로 만든다(서버 복구 경로 모사).
    let liveStart = Date().addingTimeInterval(-120)
    store.startedAt = liveStart
    store.currentSessionID = "99999999-0000-0000-0000-000000000009"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 120)

    await store.performUndoAutoClose()

    // 진행 중 세션은 그대로고, 되돌리기 대상만 정리된다.
    #expect(store.startedAt == liveStart)
    #expect(store.currentSessionID == "99999999-0000-0000-0000-000000000009")
    #expect(store.lastAutoClosedSessionID == nil)
    #expect(!store.canUndoAutoClose())
}

@MainActor
@Test
func undoAutoCloseSubtractsRestoredSessionFromTodayAccumulation() async {
    // 회귀 지점: 자동 마감 뒤 정상 폴링 1회가 accumulatedSeconds 를 서버 오늘 합계(= 방금 마감된 세션 **포함**)로
    // 채운 상태에서 [되돌리기]를 누르면, 그 세션이 다시 진행 세션이 되는데도 누적에서 빠지지 않아
    // todayDuration 이 같은 구간을 두 번 셌다(메뉴바 라벨·팝오버 큰 타이머·캐릭터 오버레이가 일제히 약 2배).
    let testHost = "abandoned-session-test"
    let store = makeStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    // **시각 고정(옆 테스트와 같은 이유).** 예전엔 벽시계 now 를 쓰고 시작점만 자정으로 clamp 했는데,
    // 그러면 KST 00:00~00:01 에 돌 때 closedSeconds 가 60 미만이 되어 마지막 부등식
    // (todayDuration < closedSeconds*2 − 60)이 **성립 불가**가 된다(우변이 todayDuration 이하로 내려간다).
    // 계약은 멀쩡한데 하루 중 1분짜리 창에서만 빨개지는 잠복 지뢰였다 — 옆 테스트의 17분 창과 같은 부류다.
    let now = URLProtocolStub.staleTodayFixture(forHost: URLProtocolStub.staleTodayNoonHost)!.now
    pinClock(store, to: now)
    let dayStart = TeamWeeklyGoal.koreanDayStart(for: now)
    let sessionStart = max(dayStart, now.addingTimeInterval(-7_200))
    let closedSeconds = max(0, Int(now.timeIntervalSince(sessionStart)))

    // '자동 마감 → 폴링 1회 반영' 직후 상태: 누적이 방금 마감된 세션까지 포함한다.
    store.startedAt = nil
    store.accumulatedSeconds = closedSeconds
    store.accumulatedDayStart = dayStart
    store.snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: closedSeconds)
    store.lastAutoClosedSessionID = "50000000-0000-0000-0000-000000000001"
    store.lastAutoClosedStartedAt = sessionStart
    store.lastAutoClosedAt = now
    store.lastAutoClosedSeconds = closedSeconds

    await store.performUndoAutoClose()

    #expect(store.startedAt == sessionStart)
    // 재개된 세션 몫은 진행분으로만 세어야 한다 — 누적에는 남지 않는다.
    #expect(store.accumulatedSeconds == 0)
    // 오늘 누적은 이어져야 한다(2배로 뛰면 안 된다). 테스트 전체 실행이 느려도 흔들리지 않게
    // 스토어가 실제로 쓰는 표시 기준시각(displayNow)으로 기대값을 만든다.
    #expect(store.todayDuration == max(0, Int(store.displayNow.timeIntervalSince(sessionStart))))
    #expect(store.todayDuration < closedSeconds * 2 - 60)
    #expect(store.lastAutoClosedSeconds == 0)
}

/// 주입 시계를 세우는 **유일한 관용구**: clock 과 displayNow 를 함께 맞춘다.
/// displayNow 는 티커가 clock() 으로 채우는 표시 캐시다. 시계만 갈아 끼우고 이 값을 실시각으로 두면
/// todayDuration 의 '오늘' 판정(accumulatedDayStart >= koreanDayStart(displayNow))이 **다른 날**을 봐서
/// 누적 기여가 통째로 0 이 된다 — 계약은 멀쩡한데 테스트만 거짓으로 빨개지는(또는 0==0 으로 조용히
/// 통과해 버리는) 지점이라, 두 값을 한 곳에서 함께 세운다.
@MainActor
private func pinClock(_ store: WorkTimerStore, to now: Date) {
    store.clock = { now }
    store.displayNow = now
}

/// 자동 마감 '오늘 몫' 계약을 **고정된 시각**에서 통째로 검증한다(호스트별 배치만 다르다).
///
/// 시각을 주입하는 이유: 이 계약은 KST 자정 클리핑을 지나므로 결과가 "지금이 자정에서 얼마나 떨어졌는가"에
/// 좌우된다. 예전엔 픽스처도 단언도 벽시계(Date())를 따로 읽어서, KST 00:00~02:00 에 돌리면
///   (1) '2시간 전 시작'이 자정으로 잘려 기대 몫이 0 근처로 붕괴하고(→ `< 몫*2 − 60` 이 성립 불가),
///   (2) 픽스처 생성 시각(워커 스레드)과 스토어 판정 시각(메인 액터, 전체 스위트에서 수십 초 밀린다)의
///       차이가 클리핑이 걸린 순간 그대로 오차가 되어 ±3초 허용치를 넘겼다.
/// 결과는 매일 밤 확정 실패였다(23:47 통과 / 00:13·00:14·00:20 실패). 시계를 주입하면 픽스처와 스토어가
/// 같은 '지금'을 쓰므로 그 축이 사라지고, 허용치도 ±3초에서 **정확한 등호**로 조일 수 있다(단언 강화).
/// - Parameter sessionLiesInsideToday: 마감된 세션 구간이 **오늘 안에** 있는 배치인가.
///   `todayDuration < 몫*2 − 60` 은 그 배치에서만 뜻이 있는 **크기 위생 점검**이다(세션이 자정을 가로지르면
///   '오늘 라이브'는 자정부터 재는데 '오늘 몫'은 자정 이후 조각만이라, 계약이 멀쩡해도 부등식이 성립하지
///   않는다). 예전엔 이 구분 없이 모든 실행에 걸어 두어 매일 밤 00시대에 확정 실패했다 —
///   부등식을 약화시키는 대신, **그것이 뜻을 갖는 배치**를 명시하고 거기서는 그대로 강하게 건다.
@MainActor
private func assertAutoCloseAddsClosedPortionAndUndoRestoresIt(
    host: String,
    sessionLiesInsideToday: Bool = true
) async {
    let fixture = URLProtocolStub.staleTodayFixture(forHost: host)!
    let store = makeStubStore(host: host)
    // 픽스처와 **같은** '지금'. 이 한 줄이 이 테스트의 벽시계 의존을 통째로 없앤다.
    pinClock(store, to: fixture.now)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    await store.refreshTeamStatus()

    #expect(store.startedAt == nil)
    #expect(store.canUndoAutoClose())
    // 계약: 마감분의 '오늘 몫' = 마지막 신호 − max(세션 시작, KST 자정).
    let expected = max(
        0,
        Int(fixture.lastSeenAt.timeIntervalSince(max(fixture.sessionStart, fixture.koreanDayStart)))
    )
    #expect(store.accumulatedSeconds == expected)
    #expect(store.lastAutoClosedSeconds == expected)
    #expect(store.todayDuration == expected)

    await store.performUndoAutoClose()

    // 되돌리면 그 몫은 누적에서 빠지고 진행분으로만 센다 → 오늘 누적은 그대로 이어진다(2배 금지).
    #expect(store.accumulatedSeconds == 0)
    #expect(store.startedAt != nil)
    let restored = store.startedAt ?? store.displayNow
    let liveExpected = max(
        0,
        Int(store.displayNow.timeIntervalSince(max(restored, TeamWeeklyGoal.koreanDayStart(for: store.displayNow))))
    )
    #expect(store.todayDuration == liveExpected)
    guard sessionLiesInsideToday else { return }
    #expect(expected > 0, "이 배치는 '오늘 몫'이 0 이라 아래 크기 단언이 공허해진다")
    #expect(store.todayDuration < expected * 2 - 60)
    // 이중 계상 회귀(되돌리기가 누적에서 몫을 빼지 않던 버그)가 만들던 **바로 그 값**을 못 박는다.
    // 위 등호 단언과 겹치지만, 무엇이 틀렸을 때 이 테스트가 빨개지는지가 실패 메시지에 그대로 남는다.
    #expect(store.todayDuration != expected + liveExpected)
}

@MainActor
@Test
func autoCloseAddsClosedSessionToTodayAccumulationAndUndoRestoresIt() async {
    // 자동 마감은 마감한 세션의 '오늘 몫'을 누적에 더해야 한다(서버 스냅샷의 today 는 마감 **전** 값이라
    // 그 세션이 빠져 있다). 그래야 마감 직후 표시가 세션 몫만큼 꺼지지 않고, 이어서 도착할 폴링값과도 같아진다.
    // 그리고 되돌리기는 그 몫을 정확히 도로 뺀다(폴링 전에 눌러도 이중 계상 없음).
    // 기준 배치: KST 정오 고정 — 자정 클리핑이 개입하지 않는다.
    await assertAutoCloseAddsClosedPortionAndUndoRestoresIt(host: URLProtocolStub.staleTodayNoonHost)
}

@MainActor
@Test
func autoCloseAddsClosedSessionToTodayAccumulationJustAfterMidnight() async {
    // **위 테스트가 매일 밤 무너지던 그 시간대에서, 같은 계약이 그대로 성립함을 보인다.**
    // KST 00:45 고정 + 00:05 에 시작한 세션(= 자정 뒤 시작). 벽시계로 돌던 시절엔 이 시간대에
    // '2시간 전 시작'이 자정으로 잘려 기대 몫이 붕괴했지만, 계약 자체는 아무 문제가 없었다 —
    // 무너진 것은 테스트의 기대값 계산이었다는 사실을 이 테스트가 고정한다.
    await assertAutoCloseAddsClosedPortionAndUndoRestoresIt(host: URLProtocolStub.staleTodayAfterMidnightHost)
}

/// **하루 전 구간 스윕.** 같은 시나리오(2시간 세션 + 8분 신호 두절)를 KST 자정으로부터 0분~1439분의
/// 여러 지점에 놓고 계약이 **전부** 성립하는지 본다. 검증자가 실제로 실패를 관측한 분(13·14·20)과
/// 통과를 관측한 분(1427 = 23:47)을 명시로 포함한다 — 이 스윕이 있으면 "그 시각에 돌려야만 드러나는"
/// 회귀가 매 실행마다 잡힌다(벽시계로 돌던 시절엔 하루에 한 번, 그것도 밤에만 드러났다).
/// 세션이 자정을 가로지르는 지점(0~119분)에서는 크기 위생 부등식이 뜻을 잃으므로 값 계약만 본다
/// (그 배치의 크기 계약은 autoCloseTodayPortionIsClipped… 가 별도로 못 박는다).
@MainActor
@Test(arguments: [0, 5, 8, 13, 14, 20, 59, 119, 120, 121, 180, 360, 720, 1080, 1427, 1439])
func autoCloseTodayPortionContractHoldsAtEveryPositionOfTheKoreanDay(minutesAfterMidnight: Int) async {
    await assertAutoCloseAddsClosedPortionAndUndoRestoresIt(
        host: URLProtocolStub.staleTodaySweepHost(minutesAfterMidnight: minutesAfterMidnight),
        // 2시간 전 시작이 오늘 안에 온전히 들어오는 것은 02:00(=120분) 이후다.
        sessionLiesInsideToday: minutesAfterMidnight >= 120
    )
}

@MainActor
@Test
func autoCloseTodayPortionIsClippedToZeroWhenTheClosedRunBelongsToYesterday() async {
    // KST 00:05 고정. 세션은 어제 22:05 에 시작했고 신호는 어제 23:57 에 끊겼다 —
    // 마감된 구간이 **전부 어제**라 '오늘 몫'은 0 이 정답이다(클리핑 규칙 그 자체).
    // 이 배치에서 클리핑이 없으면 어제 근무 1시간 52분이 통째로 오늘 표시에 얹힌다.
    let host = URLProtocolStub.staleTodayMidnightHost
    let fixture = URLProtocolStub.staleTodayFixture(forHost: host)!
    let store = makeStubStore(host: host)
    pinClock(store, to: fixture.now)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    await store.refreshTeamStatus()

    // 전제: 이 배치는 실제로 자정을 가로지른다(픽스처가 조용히 바뀌면 아래 단언이 공허해진다).
    #expect(fixture.sessionStart < fixture.koreanDayStart)
    #expect(fixture.lastSeenAt < fixture.koreanDayStart)

    #expect(store.startedAt == nil)
    #expect(store.canUndoAutoClose())
    #expect(store.accumulatedSeconds == 0)
    #expect(store.lastAutoClosedSeconds == 0)
    #expect(store.todayDuration == 0)

    await store.performUndoAutoClose()

    // 되돌리면 세션이 다시 흐르지만, 오늘 표시는 **자정 이후분만**이다(= 5분).
    let sinceMidnight = Int(fixture.now.timeIntervalSince(fixture.koreanDayStart))
    #expect(store.startedAt == fixture.sessionStart)
    #expect(store.accumulatedSeconds == 0)
    #expect(store.todayDuration == sinceMidnight)
    // 클리핑이 빠지면 이 값이 된다(어제 몫까지 오늘로 계상) — 그 값이 아님을 못 박는다.
    #expect(store.todayDuration < Int(fixture.now.timeIntervalSince(fixture.sessionStart)))
}

// MARK: - 방치 세션 서버 자동 마감(클라 스캐빈저 폴백)

@MainActor
@Test
func scavengerFiresRPCWhenTeamMemberStaleOverTenMinutes() async {
    let testHost = "scavenge-fire-test"
    let store = makeStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    let now = Date()
    // 다른 팀원이 11분째 신호 끊김 → stale(>90초)이면서 방치(>10분) 조건 충족.
    store.teamMembers = [
        TeamMemberStatus(
            id: "other", name: "동료", status: .working, updatedAt: nil,
            currentSessionStartedAt: now.addingTimeInterval(-3600),
            lastSeenAt: now.addingTimeInterval(-11 * 60)
        )
    ]
    store.lastScavengeAt = .distantPast

    store.scavengeAbandonedTeamSessionsIfNeeded(now: now)

    // 스로틀 타임스탬프가 즉시 갱신되고, 정리 RPC 가 fire-and-forget 으로 발사된다.
    #expect(store.lastScavengeAt == now)
    var fired = false
    for _ in 0..<200 {
        if URLProtocolStub.requests(forHost: testHost).contains(where: {
            $0.url?.path == "/rest/v1/rpc/close_abandoned_work_sessions" && $0.httpMethod == "POST"
        }) {
            fired = true
            break
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(fired)
}

@MainActor
@Test
func scavengerRespectsFiveMinuteThrottle() async {
    let testHost = "scavenge-throttle-test"
    let store = makeStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    let now = Date()
    store.teamMembers = [
        TeamMemberStatus(
            id: "other", name: "동료", status: .working, updatedAt: nil,
            currentSessionStartedAt: now.addingTimeInterval(-3600),
            lastSeenAt: now.addingTimeInterval(-11 * 60)
        )
    ]
    // 마지막 발사가 4분 전 → 5분 스로틀 안이라 재발사하지 않는다.
    let lastFire = now.addingTimeInterval(-4 * 60)
    store.lastScavengeAt = lastFire

    store.scavengeAbandonedTeamSessionsIfNeeded(now: now)

    // 스로틀에 막혀 타임스탬프도 그대로고 RPC 요청도 나가지 않는다.
    #expect(store.lastScavengeAt == lastFire)
    try? await Task.sleep(for: .milliseconds(30))
    #expect(!URLProtocolStub.requests(forHost: testHost).contains {
        $0.url?.path == "/rest/v1/rpc/close_abandoned_work_sessions"
    })
}

@MainActor
@Test
func scavengerDoesNotFireWithoutStaleMember() async {
    let testHost = "scavenge-fresh-test"
    let store = makeStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    let now = Date()
    // 신호가 신선한 근무중 팀원(활성) → 발사 대상 아님.
    store.teamMembers = [
        TeamMemberStatus(
            id: "other", name: "동료", status: .working, updatedAt: nil,
            currentSessionStartedAt: now.addingTimeInterval(-3600),
            lastSeenAt: now.addingTimeInterval(-30)
        )
    ]
    store.lastScavengeAt = .distantPast

    store.scavengeAbandonedTeamSessionsIfNeeded(now: now)

    #expect(store.lastScavengeAt == .distantPast)
    try? await Task.sleep(for: .milliseconds(30))
    #expect(!URLProtocolStub.requests(forHost: testHost).contains {
        $0.url?.path == "/rest/v1/rpc/close_abandoned_work_sessions"
    })
}

@MainActor
@Test
func scavengerDoesNotFireForStaleUnderTenMinutes() async {
    let testHost = "scavenge-under-threshold-test"
    let store = makeStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    let now = Date()
    // 신호가 5분 끊겨 stale(연결 끊김 칩)이긴 하지만 방치 임계(10분)에는 못 미친다 → 발사 대상 아님.
    store.teamMembers = [
        TeamMemberStatus(
            id: "other", name: "동료", status: .working, updatedAt: nil,
            currentSessionStartedAt: now.addingTimeInterval(-3600),
            lastSeenAt: now.addingTimeInterval(-5 * 60)
        )
    ]
    store.lastScavengeAt = .distantPast

    store.scavengeAbandonedTeamSessionsIfNeeded(now: now)

    #expect(store.lastScavengeAt == .distantPast)
    try? await Task.sleep(for: .milliseconds(30))
    #expect(!URLProtocolStub.requests(forHost: testHost).contains {
        $0.url?.path == "/rest/v1/rpc/close_abandoned_work_sessions"
    })
}

@MainActor
@Test
func scavengerJudgesSelfStaleBySameRule() async {
    let testHost = "scavenge-self-test"
    let store = makeStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    let now = Date()
    // 자기 자신이 다른 기기에서 11분째 신호 끊김 — 자기/타인을 가리지 않고 동일 규칙으로 발사 대상이다.
    store.teamMembers = [
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-000000000002", name: "나", status: .working, updatedAt: nil,
            currentSessionStartedAt: now.addingTimeInterval(-3600),
            lastSeenAt: now.addingTimeInterval(-11 * 60)
        )
    ]
    store.lastScavengeAt = .distantPast

    store.scavengeAbandonedTeamSessionsIfNeeded(now: now)

    #expect(store.lastScavengeAt == now)
    var fired = false
    for _ in 0..<200 {
        if URLProtocolStub.requests(forHost: testHost).contains(where: {
            $0.url?.path == "/rest/v1/rpc/close_abandoned_work_sessions" && $0.httpMethod == "POST"
        }) {
            fired = true
            break
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(fired)
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
    #expect(store.pendingItems.map(\.operation) == [.stop(durationSeconds: 3600)])
    #expect(store.pendingItems.first?.endedAt == sleepAt) // 덮은 시각으로 마감
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
    #expect(store.pendingItems.isEmpty)
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
    #expect(store.pendingItems.first?.endedAt == t0.addingTimeInterval(12 * 3600))
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

    // KST 자정 클리핑이 개입하지 않도록 정오(자정+12h)에 고정한다 — 세션 시작이 오늘 자정 이후임을 보장.
    let now = TeamWeeklyGoal.koreanDayStart(for: Date()).addingTimeInterval(12 * 3600)
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

    // KST 자정 클리핑이 개입하지 않도록 정오(자정+12h)에 고정한다 — 세션 시작이 오늘 자정 이후임을 보장.
    let now = TeamWeeklyGoal.koreanDayStart(for: Date()).addingTimeInterval(12 * 3600)
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
    // ★ v0.2.34: 축하의 종류가 `.milestone` → `.goalAchieved` 로 갈렸다. 실사용 신고
    //   "주간 목표 달성이 1시간 근무와 똑같아 보인다"의 원인이 정확히 이 한 줄이었다(같은 폴짝·같은 색종이).
    //   **여전히 onReactionTrigger 채널이다**(onRewardTrigger 가 아니다) — 이 감지는 비근무 사용자의
    //   폴링에서도 도는데, 팀원의 달성 때문에 숨긴 캐릭터가 8초 팝업으로 튀어나오면 안 된다.
    store.teamMembers = [worked(41 * 3_600)]
    store.detectTeamReactions()
    #expect(events.filter { $0 == .goalAchieved }.count == 1)
    #expect(events.contains(.milestone) == false, "주간 목표는 시간 마일스톤과 같은 연출을 쓰지 않는다")

    // 완료 유지 상태에선 재축하하지 않는다.
    store.detectTeamReactions()
    #expect(events.filter { $0 == .goalAchieved }.count == 1)
}

/// 주간 목표는 1인당 약속이므로 축하도 1인당 평균으로 판정한다(리그 표시와 같은 규약).
/// 회귀 방지: 예전엔 팀원 주간 "합계"를 1인당 목표와 견줘, 인원이 많을수록 일찍 축하가 터졌다
/// (5명 × 12시간 = 60시간 합계 ≥ 40시간 목표 → 각자 12시간뿐인데 달성 축하).
@MainActor
@Test
func teamGoalCelebrationUsesPerMemberAverageNotTeamTotal() {
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

    func member(_ id: String, _ seconds: Int) -> TeamMemberStatus {
        TeamMemberStatus(
            id: id, name: id, status: .offWork, updatedAt: nil,
            currentSessionStartedAt: nil, weeklyDurationSeconds: seconds
        )
    }

    // 첫 로드(전이 seed): 5명 각자 1시간.
    store.teamMembers = (1...5).map { member("m\($0)", 3_600) }
    store.detectTeamReactions()
    #expect(events.isEmpty)

    // 5명 각자 12시간 = 합계 60시간(> 목표 40시간)이지만 1인당 평균은 12시간이라 아직 미달 — 축하 없음.
    store.teamMembers = (1...5).map { member("m\($0)", 12 * 3_600) }
    store.detectTeamReactions()
    #expect(store.teamWeeklyAverageSeconds() == 12 * 3_600)
    #expect(events.filter { $0 == .goalAchieved }.isEmpty)

    // 각자 41시간이 되어 1인당 평균이 목표를 넘어서면 그때 1회 축하한다.
    store.teamMembers = (1...5).map { member("m\($0)", 41 * 3_600) }
    store.detectTeamReactions()
    #expect(events.filter { $0 == .goalAchieved }.count == 1)
}

// MARK: - 트랙 B: 저장 라벨 / 큐 정합성 / 자정 클리핑 / 취소 안전화

@MainActor
@Test
func refreshMenuBarTitleGuardsRedundantAssignment() {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedDefaults()
    )
    defer { store.tickerTask?.cancel() }

    // 비근무 초기값은 "오프".
    #expect(store.menuBarTitle == "오프")

    // 상태가 그대로면 재계산해도 동일 문자열이라 대입을 스킵해 관찰자를 발화시키지 않는다.
    let firedOnSame = ObservationFlag()
    withObservationTracking { _ = store.menuBarTitle } onChange: { firedOnSame.value = true }
    store.refreshMenuBarTitle()
    #expect(!firedOnSame.value)

    // 근무로 전이하면 문자열이 바뀌므로 관찰자가 발화하고, 라벨은 todayDuration 파생값이 된다.
    let now = TeamWeeklyGoal.koreanDayStart(for: Date()).addingTimeInterval(12 * 3600)
    store.startedAt = now.addingTimeInterval(-3_661) // 1시간 1분 1초
    store.displayNow = now
    // v0.2.38 M1: 메뉴바 라벨은 팝오버 시계(displayNow)가 아니라 store.clock() 기준으로 계산한다
    // (닫힌 팝오버에서 displayNow 는 얼어 있는데 라벨은 매초 살아야 하므로). 그래서 시계도 같은 now 로 고정한다.
    pinClock(store, to: now)
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)

    let firedOnChange = ObservationFlag()
    withObservationTracking { _ = store.menuBarTitle } onChange: { firedOnChange.value = true }
    store.refreshMenuBarTitle()
    #expect(firedOnChange.value)
    #expect(store.menuBarTitle == "01:01")
}

/// withObservationTracking 의 @Sendable onChange 에서 발화 여부를 기록하기 위한 참조 박스.
/// 관찰 알림은 MainActor 의 willSet 에서 동기 발화하므로 실제 경합은 없다.
private final class ObservationFlag: @unchecked Sendable {
    var value = false
}

@MainActor
@Test
func todayDurationClipsAtKoreanMidnightAndClampsNegative() {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedDefaults()
    )
    defer { store.tickerTask?.cancel() }

    let midnight = TeamWeeklyGoal.koreanDayStart(for: Date())
    let now = midnight.addingTimeInterval(30 * 60) // 오늘 KST 00:30
    // 세션이 어제 22:00 에 시작됐어도 오늘 표시는 자정 이후 30분만 센다(부풀림/오발화 방지).
    store.startedAt = midnight.addingTimeInterval(-2 * 3600)
    store.displayNow = now
    #expect(store.todayDuration == 30 * 60)

    // 시계 되돌림(시작시각이 미래)이면 음수 대신 0 으로 클램프한다.
    store.startedAt = now.addingTimeInterval(600)
    #expect(store.todayDuration == 0)
}

@MainActor
@Test
func offlineQueueDrainsStartStopStartInOrder() async {
    let testHost = "queue-drain-test"
    let store = makeStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    let t1 = Date(timeIntervalSince1970: 5_000)
    let t2 = Date(timeIntervalSince1970: 5_100)
    let t3 = Date(timeIntervalSince1970: 6_000)
    let sessionA = "aaaaaaaa-0000-0000-0000-000000000001"
    let sessionB = "bbbbbbbb-0000-0000-0000-000000000002"
    // 오프라인에서 시작→종료→재시작이 쌓인 3항목(단일 슬롯이었다면 앞 두 개가 유실됐을 상황).
    store.pendingItems = [
        PendingWorkItem(id: UUID(), operation: .start, sessionID: sessionA, sessionStartedAt: t1, endedAt: nil),
        PendingWorkItem(id: UUID(), operation: .stop(durationSeconds: 100), sessionID: sessionA, sessionStartedAt: t1, endedAt: t2),
        PendingWorkItem(id: UUID(), operation: .start, sessionID: sessionB, sessionStartedAt: t3, endedAt: nil)
    ]

    await store.retryPendingSync()

    #expect(store.pendingItems.isEmpty)

    let requests = URLProtocolStub.requests(forHost: testHost)
    let bodies = URLProtocolStub.bodies(forHost: testHost)
    // 상태 전이가 start→stop→start 순서 그대로 재생된다.
    let statusStream = zip(requests, bodies)
        .filter { $0.0.url?.path == "/rest/v1/work_statuses" && $0.0.httpMethod == "POST" }
        .map { $0.1.contains(#""status":"working""#) ? "working" : "off_work" }
    #expect(statusStream == ["working", "off_work", "working"])
    // 두 시작이 붕괴되지 않고 각자의 세션ID로 재생됐다(오프라인 복구 정합성).
    let sessionPostBodies = zip(requests, bodies)
        .filter { $0.0.url?.path == "/rest/v1/work_sessions" && $0.0.httpMethod == "POST" }
        .map { $0.1 }
    #expect(sessionPostBodies.contains { $0.contains(sessionA) })
    #expect(sessionPostBodies.contains { $0.contains(sessionB) })
}

// 지연 응답 스텁은 프로세스 전역이라 서로 덮어쓴다. in-flight 레이스 재현 테스트는 직렬 스위트로 격리한다.
@Suite(.serialized)
@MainActor
struct QueueInFlightTests {
    @Test
    func inFlightStopPreservesConcurrentRestart() async {
        let testHost = "inflight-restart-race"
        URLProtocolStub.delayedHosts = [testHost]
        defer { URLProtocolStub.delayedHosts = [] }

        let store = makeStubStore(host: testHost)
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        // 근무중 상태를 직접 세팅(초기 시작 sync 를 배제).
        store.startedAt = Date(timeIntervalSince1970: 7_000)
        store.currentSessionID = "70000000-0000-0000-0000-000000000001"
        store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 100)

        // 종료 → 종료 sync 가 지연으로 in-flight 인 사이에 재시작한다.
        store.stop(now: Date(timeIntervalSince1970: 7_100))
        try? await Task.sleep(for: .milliseconds(20))
        store.start(now: Date(timeIntervalSince1970: 7_200))

        await store.syncTask?.value

        // 재시작이 유실되지 않아 큐가 완전히 비고 로컬은 근무중을 유지한다.
        #expect(store.pendingItems.isEmpty)
        #expect(store.startedAt != nil)

        // 서버에도 off_work 다음 working 순서로 반영됐다(단일 슬롯이었다면 working 이 유실됐을 상황).
        let requests = URLProtocolStub.requests(forHost: testHost)
        let bodies = URLProtocolStub.bodies(forHost: testHost)
        let statusStream = zip(requests, bodies)
            .filter { $0.0.url?.path == "/rest/v1/work_statuses" && $0.0.httpMethod == "POST" }
            .map { $0.1.contains(#""status":"working""#) ? "working" : "off_work" }
        #expect(statusStream == ["off_work", "working"])
    }

    @Test
    func cancelledActivationKeepsSessionSignedIn() async {
        let testHost = "cancel-activation-race"
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

        // 활성화 도중 .task 취소(팝오버 빨리 닫기)를 재현한다.
        let activate = Task { await store.activateStoredSession() }
        try? await Task.sleep(for: .milliseconds(20))
        activate.cancel()
        await activate.value

        // 취소(URLError.cancelled)는 조용히 무시 — 세션이 강제 로그아웃되지 않고 토큰도 유지된다.
        #expect(store.isSignedIn)
        #expect(defaults.string(forKey: WorkTimerStore.accessTokenKey) != nil)
    }

    // FIX: 목표 write 세대 토큰 — updateTeamGoal 성공 뒤 도착하는 '낡은' in-flight 멤버십 응답이 새 목표를
    // 되돌리지 않는다(실증 스냅백 80h→40h 차단). refreshTeamMeta 가 fetch 발사 전 세대를 캡처하고, 응답 반영 시
    // 세대가 바뀌었으면 teamGoalSeconds 대입만 스킵하는지 검증한다.
    @Test
    func delayedMembershipDoesNotRevertNewlyWrittenGoal() async {
        let testHost = "goal-write-generation-race"
        URLProtocolStub.delayedHosts = [testHost]
        URLProtocolStub.responseDelay = 0.2
        defer {
            URLProtocolStub.delayedHosts = []
            URLProtocolStub.responseDelay = 0.15
        }

        let store = makeStubStore(host: testHost)
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        // 서버가 곧 되돌리려 할 옛 목표(기본 멤버십 응답도 40h 를 돌려준다).
        store.teamGoalSeconds = 40 * 3600

        // 1) 멤버십 재조회를 in-flight 로 띄운다(응답 0.2s 지연). 이 fetch 는 발사 시점의 목표 write 세대(0)를 캡처한다.
        let refresh = Task { await store.refreshTeamMeta() }
        try? await Task.sleep(for: .milliseconds(40)) // fetch 가 발사되어 세대 0 을 캡처하도록 양보.

        // 2) 그 사이 사용자가 목표를 80h 로 바꿔 성공한다(updateTeamGoal 성공 효과 = teamGoalSeconds 갱신 + 세대 +1).
        //    지연 멤버십(40h)이 write '뒤에' 도착하는 순서를 결정적으로 재현하려, 같은 지연 호스트로 나가는 write 효과를 직접 반영한다.
        store.teamGoalSeconds = 80 * 3600
        store.teamGoalWriteGeneration += 1

        // 3) 지연된 멤버십 응답(40h)이 도착한다. 세대가 바뀌었으므로 teamGoalSeconds 대입만 스킵되어야 한다(스냅백 없음).
        await refresh.value
        #expect(store.teamGoalSeconds == 80 * 3600)
        // 목표만 스킵하고 팀명/역할은 최신 서버값으로 반영한다(부분 반영).
        #expect(store.teamName == "아잉팀")
        #expect(store.teamRole == "member")
    }
}

// MARK: - FIX-B: 적대적 검증 후속 수정 회귀 테스트

// B-F1: 유휴 refresh 루프가 유휴→근무 전이에 다음 슬라이스에서 즉시 깨어나 하트비트를 보낸다.
@MainActor
@Test
func idleRefreshLoopWakesWithinOneSliceWhenWorkStarts() async {
    let testHost = "idle-to-working-wake"
    let store = makeStubStore(host: testHost)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    // 유휴(비근무·팝오버 닫힘·큐 없음)라 refresh 루프는 느린 주기로 진입한다.
    #expect(!store.refreshLoopIsFast)
    // 느린 주기(300s=10×30s)를 짧은 슬라이스로 축소해 실시간 대기 없이 슬라이스-깨어남을 검증한다.
    store.refreshLoopSliceSeconds = 0.05

    store.startStatusRefreshLoop()
    // 루프가 느린 슬라이스 sleep 에 먼저 진입하도록 한 슬라이스보다 짧게 양보한다.
    try? await Task.sleep(for: .milliseconds(10))

    // 유휴 중 근무 시작(startedAt 주입) → 다음 슬라이스 경계에서 fast 로 감지되어 즉시 하트비트가 나가야 한다.
    store.startedAt = Date()
    store.currentSessionID = "wake-session"
    #expect(store.refreshLoopIsFast)

    // 전이 후 ≤1슬라이스 안에 working 하트비트 upsert 가 나타나는지 폴링한다(수정 전엔 최대 300s 지연).
    var heartbeatSent = false
    for _ in 0..<200 {
        let sent = zip(URLProtocolStub.requests(forHost: testHost), URLProtocolStub.bodies(forHost: testHost))
            .contains {
                $0.0.url?.path == "/rest/v1/work_statuses"
                    && $0.0.httpMethod == "POST"
                    && $0.1.contains(#""active_session_id":"wake-session""#)
            }
        if sent {
            heartbeatSent = true
            break
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(heartbeatSent)
}

// B-F3: 첫 활성화가 confirmMembership 실패(네트워크/취소)로 끝난 뒤, 재오픈 activateStoredSession 이 멤버십을 재확정한다.
@MainActor
@Test
func reopenReconfirmsMembershipWhenFirstActivationFailed() async {
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
    // 첫 활성화가 confirmMembership 실패로 끝난 상태를 재현한다: hasActivatedStoredSession 은 이미 래치됐지만
    // 멤버십은 미확정이고 팀이 비어 있다(팀 있는 유저가 TeamlessPanel 로 갇히던 결함의 전제).
    store.hasActivatedStoredSession = true
    store.membershipConfirmed = false
    store.currentTeamID = nil

    // 팝오버 재오픈 → activateStoredSession fast path. 미확정 멤버십을 재확정해 팀을 복원해야 한다.
    await store.activateStoredSession()

    #expect(store.membershipConfirmed)
    #expect(store.currentTeamID == "10000000-0000-0000-0000-000000000001")
    #expect(store.teamRole == "member")
}

// B-F4: refresh grant 5xx/429 는 일시 장애(.transient)로 분류해 세션을 유지한다. 400/401 계열은 fatal 유지.
@MainActor
@Test
func classifyAuthErrorTreatsServerErrorsAsTransientAndClientErrorsAsFatal() {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    func isTransient(_ error: SupabaseWorkServiceError) -> Bool {
        if case .transient = store.classifyAuthError(error) { return true }
        return false
    }
    func isFatal(_ error: SupabaseWorkServiceError) -> Bool {
        if case .fatal = store.classifyAuthError(error) { return true }
        return false
    }
    // Supabase 무료플랜 일시정지(5xx)/레이트리밋(429)은 일시 장애 → 세션 유지(재시도).
    #expect(isTransient(.invalidResponse(500)))
    #expect(isTransient(.invalidResponse(503)))
    #expect(isTransient(.invalidResponse(429)))
    // 400/401 계열은 fatal 유지(진짜 만료·잘못된 요청은 로그아웃 대상).
    #expect(isFatal(.invalidResponse(400)))
    #expect(isFatal(.invalidResponse(401)))
    #expect(isFatal(.sessionExpired))
}

// B-F5: 어제 누적 + 자정 넘긴 세션이 오늘 표시를 부풀리거나 새 날 마일스톤을 오발화시키지 않는다.
@MainActor
@Test
func accumulatedFromPreviousDayDoesNotInflateTodayAfterMidnight() {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: isolatedDefaults()
    )
    defer { store.tickerTask?.cancel() }
    var events: [ReactionKind] = []
    store.onReactionTrigger = { events.append($0) }

    let todayMidnight = TeamWeeklyGoal.koreanDayStart(for: Date())
    let yesterdayMidnight = TeamWeeklyGoal.koreanDayStart(for: todayMidnight.addingTimeInterval(-3600))
    // 어제 3시간 근무를 누적하고 스탬프는 어제로.
    store.accumulatedSeconds = 3 * 3600
    store.accumulatedDayStart = yesterdayMidnight
    // 어제 23:00 재출근한 세션이 자정을 넘겨 이어지고, 지금은 오늘 00:00:05 첫 틱 상황.
    store.startedAt = todayMidnight.addingTimeInterval(-3600)
    store.displayNow = todayMidnight.addingTimeInterval(5)

    // 어제 누적(3h)은 오늘 표시에 섞이지 않는다 — 자정 이후 경과분(5초)만 오늘로 센다.
    #expect(store.todayDuration == 5)

    // 자정 첫 틱 상황에서 마일스톤이 오발화하지 않는다(오늘 누적이 1h 미만).
    store.evaluateTimeMilestones(now: store.displayNow)
    #expect(events.isEmpty)
}

// B-F6: 자정 넘김 stop() 은 로컬 누적에 오늘분만 가산하고(표시 점프 방지), 서버 전송 duration 은 세션 전체를 유지한다.
@MainActor
@Test
func stopAcrossMidnightAddsOnlyTodayPortionLocally() {
    let store = makeStubStore(host: "stop-midnight-clip")
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    let todayMidnight = TeamWeeklyGoal.koreanDayStart(for: Date())
    let startYesterday = todayMidnight.addingTimeInterval(-3600) // 어제 23:00
    let stopToday = todayMidnight.addingTimeInterval(3600)       // 오늘 01:00
    store.startedAt = startYesterday
    store.currentSessionID = "midnight-session"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3599)

    store.stop(now: stopToday)

    // 로컬 누적은 오늘 자정 이후분(1시간=3600초)만 더해 표시가 세션 전체(7200)로 점프하지 않는다.
    #expect(store.accumulatedSeconds == 3600)
    #expect(store.snapshot.elapsedSeconds == 3600)
    #expect(store.accumulatedDayStart == todayMidnight)
    // 서버 전송 duration 은 세션 전체(2시간=7200)를 유지한다(서버가 타임스탬프로 클리핑).
    #expect(store.pendingItems.map(\.operation) == [.stop(durationSeconds: 7200)])
}

// B-F7: 스토어가 해제되면 티커 루프가 좀비로 남지 않고 다음 웨이크에서 종료된다.
@MainActor
@Test
func tickerLoopTerminatesWhenStoreDeallocated() async {
    final class DoneFlag: @unchecked Sendable { var done = false }
    let flag = DoneFlag()
    weak var weakStore: WorkTimerStore?

    var task: Task<Void, Never>?
    do {
        let store = WorkTimerStore(
            environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
            defaults: isolatedDefaults()
        )
        weakStore = store
        store.startTimer()
        task = store.tickerTask
    }
    #expect(task != nil)

    // 티커 완료를 감시(좀비면 영영 완료 안 됨 — 누수되지만 테스트를 막지 않는다).
    Task { @MainActor in
        await task?.value
        flag.done = true
    }

    // 마지막 강참조가 사라졌으므로 스토어는 해제됐어야 한다(좀비 판정의 전제부터 검증).
    #expect(weakStore == nil)

    // guard let self 패턴이면 self 소멸 후 다음 웨이크(≤~1.2s)에서 루프가 종료된다. 좀비면 완료되지 않아 타임아웃.
    var terminated = false
    for _ in 0..<60 {
        if flag.done {
            terminated = true
            break
        }
        try? await Task.sleep(for: .milliseconds(100))
    }
    #expect(terminated)
}

// 지연 응답 스텁은 프로세스 전역이라 서로 덮어쓴다. in-flight 레이스 재현 테스트는 직렬 스위트로 격리한다.
@Suite(.serialized)
@MainActor
struct FixBSyncRaceTests {
    // B-F2: 드레인 in-flight 중 clearPersistedSession(세대+1) 이 와도, 서버 실행이 끝난 항목은 큐에서 제거된다
    // (수정 전엔 세대 가드가 removeFirst 앞이라 완료 항목이 잔류 → 재로그인 후 이중 재생 409).
    @Test
    func drainedItemIsRemovedEvenIfSessionClearedMidFlight() async {
        let testHost = "drain-clear-race"
        URLProtocolStub.delayedHosts = [testHost]
        defer { URLProtocolStub.delayedHosts = [] }

        let store = makeStubStore(host: testHost)
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        store.pendingItems = [
            PendingWorkItem(
                id: UUID(),
                operation: .stop(durationSeconds: 50),
                sessionID: "aaaaaaaa-0000-0000-0000-000000000001",
                sessionStartedAt: Date(timeIntervalSince1970: 2000),
                endedAt: Date(timeIntervalSince1970: 2050)
            )
        ]

        // 드레인을 발사하고 서버 실행이 in-flight 인 사이에 세션을 비운다(세대+1).
        store.enqueueSync()
        try? await Task.sleep(for: .milliseconds(60))
        store.clearPersistedSession()

        await store.syncTask?.value

        // 서버 실행이 완료된 항목은 세대 증가와 무관하게 큐에서 제거되어, 재로그인 후 이중 재생되지 않는다.
        #expect(store.pendingItems.isEmpty)
    }

    // B-F8: refreshTeamStatus 취소는 syncMessage='동기화 실패' 헛경보를 남기지 않는다.
    @Test
    func cancelledTeamRefreshDoesNotLeaveFailureMessage() async {
        let testHost = "cancel-refresh-msg"
        URLProtocolStub.delayedHosts = [testHost]
        defer { URLProtocolStub.delayedHosts = [] }

        let store = makeStubStore(host: testHost)
        defer {
            store.tickerTask?.cancel()
            store.refreshTask?.cancel()
        }
        store.syncMessage = "동기화됨"

        let refresh = Task { await store.refreshTeamStatus() }
        // 요청이 in-flight 인 사이에 취소한다(팝오버 빨리 닫기 재현).
        try? await Task.sleep(for: .milliseconds(20))
        refresh.cancel()
        await refresh.value

        // 취소는 실패 문구를 남기지 않는다(수정 전엔 authMessage 폴백으로 '동기화 실패' 표기).
        #expect(store.syncMessage != "동기화 실패")
    }
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
        defaults: isolatedDefaults(),
        // ★ 토큰 스토어를 반드시 주입한다(v0.2.39). 폴링 루프가 팝오버 **닫힘** 가지에서
        //   refreshTokenUsageInBackgroundIfDue 를 부르게 되면서, 근무 중 루프를 도는 테스트가 기본값
        //   TokenUsageStore.shared 를 그대로 쓰면 **실제 홈**(~/.claude · ~/.codex ≈ 1,600 파일)을 순회하고
        //   그 결과가 테스트 러너의 UserDefaults.standard 에 영속된다(TokenUsageStore.shared 주석이 경고하는 그 오염).
        //   실측: idleRefreshLoopWakesWithinOneSliceWhenWorkStarts 가 shared.scanCount 를 1 로 올렸다.
        tokenUsage: inertTokenStore()
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
    // 세션을 직접 주입하는 테스트는 로그인 흐름(confirmMembership)을 건너뛰므로 팀도 직접 확정한다.
    store.currentTeamID = URLProtocolStub.stubTeamID
    return store
}

/// 스캔이 절대 실홈을 건드리지 않는 토큰 스토어(빈 임시 홈 · 임시 캐시 · 격리 defaults).
@MainActor
private func inertTokenStore() -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    let tag = UUID().uuidString
    return TokenUsageStore(
        defaults: isolatedDefaults(),
        homeDirectory: tmp.appendingPathComponent("check-tests-token-home-\(tag)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-tests-token-cache-\(tag).json", isDirectory: false),
        notificationCenter: NotificationCenter()
    )
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "check-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

// MARK: - D2: 팀원 이번 달 AI 토큰 보드 (토글/로드/업로드 게이트/초기화)

@MainActor
@Test
func toggleTokenBoardOpensClosesAndIsMutuallyExclusiveWithLeaderboard() {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://token-toggle-test")!,
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.currentTeamID = URLProtocolStub.stubTeamID

    // 리그가 열린 상태에서 토큰 보드를 열면 리그가 닫힌다(상호 배타).
    store.isLeaderboardVisible = true
    store.toggleTokenBoard()
    #expect(store.isTokenBoardVisible)
    #expect(!store.isLeaderboardVisible)

    // 반대로 리그를 열면 토큰 보드가 닫힌다.
    store.toggleLeaderboard()
    #expect(store.isLeaderboardVisible)
    #expect(!store.isTokenBoardVisible)

    // 다시 토큰 보드를 토글하면 닫힌다.
    store.toggleTokenBoard()   // open (leaderboard closes)
    store.toggleTokenBoard()   // close
    #expect(!store.isTokenBoardVisible)
}

@MainActor
@Test
func performLoadTokenBoardLoadsRPCRowsSortedByTotal() async {
    let testHost = "token-board-load-test"
    // 전체 공개 RPC 응답: 이름/아바타 포함(행 자체 완결). 타팀 사용자(u2)도 포함돼 팀 무관 전체가 보인다.
    // 서버 정렬을 신뢰하지 않는지 보이려 원본은 total 오름차순(u2 50 → u1 100)으로 준다 — 클라가 내림차순으로 재정렬해야 한다.
    TokenBoardURLProtocol.setResponse(
        """
        [
          {"user_id": "u2", "display_name": "타팀민수", "avatar_url": null, "claude_input": 50, "claude_output": 0, "claude_cache_read": 0, "claude_cache_creation": 0, "codex_input": 0, "codex_output": 0, "total": 50},
          {"user_id": "u1", "display_name": "영식", "avatar_url": "https://example.com/u1.jpg", "claude_input": 100, "claude_output": 0, "claude_cache_read": 0, "claude_cache_creation": 0, "codex_input": 0, "codex_output": 0, "total": 100}
        ]
        """,
        forHost: testHost
    )
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "u1")
    store.currentTeamID = URLProtocolStub.stubTeamID
    // 팀원 목록과 무관하게(전체 공개) RPC 행만으로 보드가 채워진다.
    #expect(store.tokenBoardLoaded == false)

    await store.performLoadTokenBoard()

    // RPC 두 행 그대로, total 내림차순(u1 100 → u2 50). 이름/아바타는 행에서 온다.
    #expect(store.tokenBoard.count == 2)
    #expect(store.tokenBoard.map(\.userID) == ["u1", "u2"])
    #expect(store.tokenBoard[0].total == 100)
    #expect(store.tokenBoard[0].name == "영식")
    #expect(store.tokenBoard[0].avatarURL == URL(string: "https://example.com/u1.jpg"))
    #expect(store.tokenBoard[1].total == 50)
    // 성공 로드 후 플래그가 서 빈 목록 문구 판정(로드 전/실패와 구분)이 가능해진다.
    #expect(store.tokenBoardLoaded)
}

@MainActor
@Test
func uploadTokenUsageGateThrottlesAndChangeGates() async {
    let testHost = "token-upload-gate-test"
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.currentTeamID = URLProtocolStub.stubTeamID

    func postCount() -> Int {
        URLProtocolStub.requests(forHost: testHost).filter {
            $0.url?.path == "/rest/v1/token_usage_device_monthly" && $0.httpMethod == "POST"
        }.count
    }

    let t0 = Date(timeIntervalSince1970: 1_000_000)
    let usageA = TokenUsageMonthly(month: "2026-07", claudeInput: 100)
    let usageB = TokenUsageMonthly(month: "2026-07", claudeInput: 200)
    let usageZero = TokenUsageMonthly(month: "2026-07")  // total 0

    // 1) 최초: 변경(nil→A) + distantPast 대비 60초 경과 → 업로드.
    await store.uploadTokenUsageIfNeeded(usage: usageA, now: t0)
    #expect(postCount() == 1)

    // 2) 같은 값 + 30초(<60) → 스킵.
    await store.uploadTokenUsageIfNeeded(usage: usageA, now: t0.addingTimeInterval(30))
    #expect(postCount() == 1)

    // 3) 값이 바뀌었지만 여전히 <60초 → 스킵(두 조건 모두 필요).
    await store.uploadTokenUsageIfNeeded(usage: usageB, now: t0.addingTimeInterval(30))
    #expect(postCount() == 1)

    // 4) 값 변경 + 60초 경과 → 업로드.
    await store.uploadTokenUsageIfNeeded(usage: usageB, now: t0.addingTimeInterval(70))
    #expect(postCount() == 2)

    // 5) 60초 지났어도 값이 안 바뀌면 → 스킵.
    await store.uploadTokenUsageIfNeeded(usage: usageB, now: t0.addingTimeInterval(140))
    #expect(postCount() == 2)

    // 6) nil / 총합 0 은 올리지 않는다(빈 행을 만들 필요 없음 — 보드가 0 으로 채운다).
    await store.uploadTokenUsageIfNeeded(usage: nil, now: t0.addingTimeInterval(200))
    await store.uploadTokenUsageIfNeeded(usage: usageZero, now: t0.addingTimeInterval(300))
    #expect(postCount() == 2)

    // 7) 6필드 총합(=200)은 그대로여도 오늘분(todayTotal)만 바뀌면 변경으로 감지해 업로드한다.
    //    게이트는 TokenUsageMonthly 전체 Equatable 비교라 todayTotal/todayDate 변화도 자동으로 잡힌다(설계 5 확인).
    let usageBToday = TokenUsageMonthly(month: "2026-07", claudeInput: 200, todayTotal: 5, todayDate: "2026-07-14")
    await store.uploadTokenUsageIfNeeded(usage: usageBToday, now: t0.addingTimeInterval(360))
    #expect(postCount() == 3)
}

// 수집 끔(profiles.token_usage_collect=false)이면 앱이 아예 올리지 않는다.
// 실효는 서버 트리거가 내지만(구버전 클라도 함께 막힌다), 이 게이트가 없으면 그 사람 맥이 30초마다
// 서버가 버릴 값을 계속 왕복시킨다. 대조군으로 '수집 켬이면 그대로 올라간다'를 함께 고정해,
// 게이트가 전원의 업로드를 죽이는 방향으로 잘못 서지 않게 한다.
@MainActor
@Test
func uploadTokenUsageSkipsEntirelyWhenCollectionIsOff() async {
    let testHost = "token-collect-off-test"
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.currentTeamID = URLProtocolStub.stubTeamID

    func postCount() -> Int {
        URLProtocolStub.requests(forHost: testHost).filter {
            $0.url?.path.hasPrefix("/rest/v1/token_usage") == true && $0.httpMethod == "POST"
        }.count
    }

    let t0 = Date(timeIntervalSince1970: 2_000_000)
    let usage = TokenUsageMonthly(month: "2026-08", claudeInput: 100)

    // 수집 끔 → 옛 표·새 표 어느 쪽으로도 나가지 않는다.
    store.tokenUsageCollect = false
    await store.uploadTokenUsageIfNeeded(usage: usage, now: t0)
    #expect(postCount() == 0)

    // 대조군: 다시 켜면 그대로 올라간다(게이트가 한 방향으로만 막는다는 증거).
    store.tokenUsageCollect = true
    await store.uploadTokenUsageIfNeeded(usage: usage, now: t0.addingTimeInterval(70))
    #expect(postCount() > 0)
}

@MainActor
@Test
func uploadTokenUsageAlsoRewritesLegacyLedger() async {
    // 옛 표(token_usage_monthly)도 함께 갱신한다 — 새 표 마이그레이션이 아직 적용되지 않은 사이에도 사용량이
    // 멈추지 않게 하고(옛 표는 이미 있다), v0.2.10 으로 되돌아간 맥과 표시가 이어지게 하기 위함이다.
    // 단 그 행을 **깎지 않을 때만** 쓴다 — 그래서 쓰기 전에 현재 값을 GET 으로 읽는다(아래 다른 테스트가 실증).
    let testHost = "token-dual-write-test"
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.currentTeamID = URLProtocolStub.stubTeamID

    let usage = TokenUsageMonthly(month: "2026-07", claudeInput: 12_000_000, todayTotal: 7, todayDate: "2026-07-26")
    await store.uploadTokenUsageIfNeeded(usage: usage, now: Date(timeIntervalSince1970: 2_000_000))

    let pairs = zip(URLProtocolStub.requests(forHost: testHost), URLProtocolStub.bodies(forHost: testHost))
    let posts = pairs.filter { $0.0.httpMethod == "POST" }
    let paths = posts.compactMap { $0.0.url?.path }
    // 두 표 모두 갱신한다 — 옛 표를 먼저 보내, 새 표 마이그레이션이 아직 없더라도 사용량이 멈추지 않게 한다.
    #expect(paths == ["/rest/v1/token_usage_monthly", "/rest/v1/token_usage_device_monthly"])
    #expect(posts.first?.0.url?.query?.contains("on_conflict=user_id,month") == true)
    // 덮어쓰기 전 현재 값을 읽는 GET 이 옛 표 POST 앞에 정확히 한 번 간다(깎기 금지 게이트).
    let legacyGets = URLProtocolStub.requests(forHost: testHost).filter {
        $0.url?.path == "/rest/v1/token_usage_monthly" && $0.httpMethod == "GET"
    }
    #expect(legacyGets.count == 1)

    let legacyBody = posts.first?.1 ?? ""
    // 옛 표 본문은 v0.2.10 과 같은 모양이어야 한다(device_id 없음 — 그 표의 키는 (user_id, month)).
    #expect(!legacyBody.contains("device_id"))
    #expect(legacyBody.contains("\"total\":12000000"))
    #expect(legacyBody.contains("\"month\":\"2026-07\""))
    #expect(legacyBody.contains("\"today_total\":7"))
    // 새 표 본문에는 기기 식별자가 함께 실린다(합산 키).
    #expect(posts.count >= 2 && posts[1].1.contains("\"device_id\":\"\(store.deviceID)\""))
}

@MainActor
@Test
func uploadTokenUsageKeepsBiggerLegacyLedgerOfAnotherMac() async {
    // 회귀 지점(결함1 과도기): 옛 표는 키가 (user_id, month) 라 맥 2대가 한 행을 공유한다. 아직 v0.2.10 인
    // 주력 맥이 그 달 200M 을 올려 둔 행을, v0.2.11 인 보조 맥이 팝오버를 열자마자 자기 2M 으로 덮어썼다.
    // 그러면 보드의 '큰 쪽(기기 합산 vs 옛 행)' 비교에서 옛 값 자체가 2M 이 되어 주력 맥의 200M 이 순위에서
    // 사라지고, 어느 맥을 마지막에 열었느냐에 따라 200M ↔ 2M 로 널뛴다(= v0.2.10 시절 증상 그대로).
    // 이제는 쓰기 전에 현재 값을 읽어, 내 값이 더 작으면 옛 표를 건드리지 않는다.
    let testHost = "legacy-bigger-token-test"
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.currentTeamID = URLProtocolStub.stubTeamID

    // 이 맥(보조)의 이번 달 누적은 2M — 스텁이 돌려주는 옛 행(200M)보다 작다.
    let usage = TokenUsageMonthly(month: "2026-07", claudeInput: 2_000_000, todayTotal: 4, todayDate: "2026-07-26")
    await store.uploadTokenUsageIfNeeded(usage: usage, now: Date(timeIntervalSince1970: 4_000_000))

    let requests = URLProtocolStub.requests(forHost: testHost)
    // 옛 표에는 **쓰지 않는다**(읽기만) — 주력 맥의 200M 이 그대로 남는다.
    #expect(!requests.contains { $0.url?.path == "/rest/v1/token_usage_monthly" && $0.httpMethod == "POST" })
    #expect(requests.contains { $0.url?.path == "/rest/v1/token_usage_monthly" && $0.httpMethod == "GET" })
    // 새 기기별 표에는 정상적으로 올린다(합산은 서버 보드가 한다) — 옛 표를 건너뛴다고 업로드가 멈추면 안 된다.
    #expect(requests.contains { $0.url?.path == "/rest/v1/token_usage_device_monthly" && $0.httpMethod == "POST" })
    // 업로드가 성공했으므로 게이트 값도 갱신된다(다음 주기에 같은 값으로 재시도하지 않는다).
    #expect(store.lastUploadedUsage == usage)
}

@MainActor
@Test
func tokenUploadSurfacesMissingDeviceTableSchema() async {
    // 회귀 지점(결함3): 마이그레이션을 적용하지 않은 채 v0.2.11 을 배포하면 새 표 업로드가 404(PGRST205)로
    // 전량 실패하는데, 예전엔 모든 실패를 catch 가 조용히 삼켜 docs/release.md 가 지시한 신호("DB 스키마 필요")가
    // 화면에 뜨는 경로 자체가 없었다(순위 조회는 옛 RPC 라 멀쩡해 실패를 시사하는 표시가 아무것도 없었다).
    let testHost = "device-table-missing"
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.syncMessage = "동기화됨"

    let usage = TokenUsageMonthly(month: "2026-07", claudeInput: 100)
    await store.uploadTokenUsageIfNeeded(usage: usage, now: Date(timeIntervalSince1970: 3_000_000))

    #expect(store.syncMessage == "DB 스키마 필요")
    // 옛 표 갱신은 먼저 성공했으므로 그 사이에도 사용량은 멈추지 않는다.
    #expect(URLProtocolStub.requests(forHost: testHost).contains {
        $0.url?.path == "/rest/v1/token_usage_monthly" && $0.httpMethod == "POST"
    })
    // 실패했으므로 마지막 업로드 값은 갱신되지 않는다 — 60초 뒤 같은 값으로 재시도되고, 뒤늦게 push 해도 자가 복구된다.
    #expect(store.lastUploadedUsage == nil)
}

@MainActor
@Test
func signOutClearsTokenBoardState() {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://token-signout-test")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.isTokenBoardVisible = true
    store.tokenBoardLoaded = true
    store.tokenBoard = [
        TokenBoardEntry(userID: "u1", name: "영식", avatarURL: nil, total: 100, claudeInput: 100, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0)
    ]
    store.lastUploadedUsage = TokenUsageMonthly(month: "2026-07", claudeInput: 100)
    store.lastTokenUploadAt = Date()

    store.signOut()

    // 로그아웃 시 보드 상태와 업로드 게이트가 모두 초기화되어야 한다(리그와 동일 규약).
    #expect(store.tokenBoard.isEmpty)
    #expect(!store.isTokenBoardVisible)
    #expect(!store.tokenBoardLoaded)
    #expect(store.lastUploadedUsage == nil)
    #expect(store.lastTokenUploadAt == .distantPast)
}

// MARK: - 콕찌르기 / 토큰 사용량 공개 설정 (스토어 계층)

@MainActor
@Test
func togglePokePanelIsMutuallyExclusiveWithLeaderboardAndTokenBoard() {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://poke-toggle-test")!,
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
    store.currentTeamID = URLProtocolStub.stubTeamID

    // 리그가 열린 상태에서 콕찌르기를 열면 리그·토큰 보드가 닫힌다(3자 상호 배타).
    store.isLeaderboardVisible = true
    store.isTokenBoardVisible = true
    store.togglePokePanel()
    #expect(store.isPokePanelVisible)
    #expect(!store.isLeaderboardVisible)
    #expect(!store.isTokenBoardVisible)

    // 반대로 리그를 열면 콕찌르기가 닫힌다.
    store.toggleLeaderboard()
    #expect(store.isLeaderboardVisible)
    #expect(!store.isPokePanelVisible)

    // 토큰 보드를 열어도 콕찌르기는 닫힌 상태 유지.
    store.togglePokePanel()   // open (리그 닫힘)
    #expect(store.isPokePanelVisible)
    store.toggleTokenBoard()
    #expect(store.isTokenBoardVisible)
    #expect(!store.isPokePanelVisible)

    // 다시 토글하면 닫히고 안내가 비워진다.
    store.togglePokePanel()   // open
    store.pokeNotice = "무언가"
    store.togglePokePanel()   // close
    #expect(!store.isPokePanelVisible)
    #expect(store.pokeNotice == nil)
}

/// 회귀: 콕찌르기 실패 안내는 **어느 경로로 나가든** 지워져야 한다. [내 기록]/리그/토큰 보드로 빠져나가면
/// 예전엔 pokeNotice 가 남아, 콕찌르기로 되돌아온 새 화면 상단에 아무 것도 누르지 않았는데 낡은
/// 주황 경고줄이 그대로 떴다(v0.2.11 에서 헤더에 [내 기록] 버튼이 생기며 처음 열린 경로).
@MainActor
@Test
func leavingPokePanelByAnyRouteClearsNotice() {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://poke-notice-clear-test")!,
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
    store.currentTeamID = URLProtocolStub.stubTeamID

    // (1) [내 기록]으로 이탈 → 안내가 지워지고, 되돌아와도 깨끗하다.
    store.togglePokePanel()
    store.pokeNotice = "자리비움 상태에는 찌를 수 없어요"
    store.toggleInsightsPanel()
    #expect(!store.isPokePanelVisible)
    #expect(store.pokeNotice == nil)
    store.toggleInsightsPanel()   // 내 기록 닫기
    store.togglePokePanel()       // 콕찌르기 재진입
    #expect(store.isPokePanelVisible)
    #expect(store.pokeNotice == nil)

    // (2) 리그로 이탈.
    store.pokeNotice = "지금은 찌를 수 없어요"
    store.toggleLeaderboard()
    #expect(!store.isPokePanelVisible)
    #expect(store.pokeNotice == nil)

    // (3) 토큰 보드로 이탈.
    store.togglePokePanel()
    store.pokeNotice = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"
    store.toggleTokenBoard()
    #expect(!store.isPokePanelVisible)
    #expect(store.pokeNotice == nil)
}

@MainActor
@Test
func sendPokeGatesWhenNotWorkingAndFiresNoRequest() {
    let testHost = "poke-gate-test"
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    // startedAt == nil(비근무) → 선게이트로 요청 없이 안내만.
    store.sendPoke(to: "target")

    #expect(store.pokeNotice == "근무 중일 때만 콕 찌를 수 있어요")
    #expect(store.pokeCooldownUntil["target"] == nil)
    // poke_user RPC 요청이 실제로 나가지 않았다(클라 선게이트).
    let pokeRequests = URLProtocolStub.requests(forHost: testHost).filter {
        $0.url?.path == "/rest/v1/rpc/poke_user"
    }
    #expect(pokeRequests.isEmpty)
}

@MainActor
@Test
func sendPokeOkMirrorsCooldownWindow() async throws {
    let testHost = "poke-ok-test"
    TokenBoardURLProtocol.setResponse(#"{"status":"ok"}"#, forHost: testHost)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
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
    // 근무중으로 두어 선게이트를 통과시킨다(sync 는 발사하지 않도록 startedAt 만 직접 세팅).
    store.startedAt = Date()
    store.pokeNotice = "이전 안내"

    let sentAt = Date()
    store.sendPoke(to: "target")

    // 응답(ok) 반영은 Task 라 pokeCooldownUntil 이 채워질 때까지 폴링한다.
    var mirrored = false
    for _ in 0..<200 {
        if store.pokeCooldownUntil["target"] != nil {
            mirrored = true
            break
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(mirrored)
    #expect(store.pokeNotice == nil)  // ok → 안내 해제
    // 쿨타임 만료 시각은 응답 도착 시각 + 60초다. 벽시계 잔여로 재면 테스트 병렬 실행 지연에 그대로 흔들리므로
    // (발사 시각 기준) 하한만 엄격히 보고 상한은 넉넉히 둔다 — 검증 대상은 '60초를 미러링했는가'다.
    let until = try #require(store.pokeCooldownUntil["target"])
    #expect(until.timeIntervalSince(sentAt) >= 60)
    #expect(until.timeIntervalSince(sentAt) <= 60 + 300)
}

@MainActor
@Test
func sendPokeCooldownResponseMirrorsRetryAfter() async throws {
    let testHost = "poke-cooldown-test"
    TokenBoardURLProtocol.setResponse(#"{"status":"cooldown","retry_after_seconds":25}"#, forHost: testHost)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
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
    store.startedAt = Date()

    let sentAt = Date()
    store.sendPoke(to: "target")

    var mirrored = false
    for _ in 0..<200 {
        if store.pokeCooldownUntil["target"] != nil {
            mirrored = true
            break
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(mirrored)
    // 서버가 준 retry_after_seconds(25) 만큼 쿨타임을 미러링한다. 벽시계 잔여가 아니라 만료 시각으로 본다 —
    // 병렬 실행으로 응답 반영이 늦어져도 '25초를 미러링했는가'라는 검증 의도는 흔들리지 않는다.
    let until = try #require(store.pokeCooldownUntil["target"])
    #expect(until.timeIntervalSince(sentAt) >= 25)
    #expect(until.timeIntervalSince(sentAt) <= 25 + 300)
}

@MainActor
@Test
func sendPokeTargetNotWorkingShowsNoticeAndReloadsDirectory() async {
    let testHost = "poke-target-off-test"
    TokenBoardURLProtocol.setResponse(#"{"status":"target_not_working"}"#, forHost: testHost)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
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
    // 내가 근무중이라 선게이트를 통과한다(대상 자리비움은 서버가 최종 판정).
    store.startedAt = Date()

    store.sendPoke(to: "target")

    // target_not_working 응답 → 안내 문구 + 디렉토리 재조회(app_user_directory) 발사(낡은 근무중 배지 교정).
    var noticed = false
    var reloaded = false
    for _ in 0..<400 {
        if store.pokeNotice == "자리비움 상태에는 찌를 수 없어요" { noticed = true }
        if TokenBoardURLProtocol.lastURL(forHost: testHost)?.path == "/rest/v1/rpc/app_user_directory" {
            reloaded = true
        }
        if noticed && reloaded { break }
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(noticed)
    #expect(reloaded)
    // 대상 자리비움은 쿨타임과 무관하므로 쿨타임 미러링이 없다.
    #expect(store.pokeCooldownUntil["target"] == nil)
}

@Test
func pokeSendOutcomeMapsAllStatuses() {
    #expect(PokeSendOutcome(response: PokeSendResponse(status: "ok")) == .ok)
    #expect(PokeSendOutcome(response: PokeSendResponse(status: "cooldown", retryAfterSeconds: 25))
        == .cooldown(retryAfterSeconds: 25))
    #expect(PokeSendOutcome(response: PokeSendResponse(status: "not_working")) == .notWorking)
    #expect(PokeSendOutcome(response: PokeSendResponse(status: "target_not_working")) == .targetNotWorking)
    #expect(PokeSendOutcome(response: PokeSendResponse(status: "invalid")) == .invalid)
    // 미지의 status 는 안전하게 invalid 로 폴백한다.
    #expect(PokeSendOutcome(response: PokeSendResponse(status: "누락된값")) == .invalid)
}

@MainActor
@Test
func setTokenUsagePublicRevertsOnFailure() async {
    let testHost = "privacy-toggle-fail-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: PokeFailingURLProtocol.session()
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
    #expect(store.tokenUsagePublic == true)  // 기본 공개.

    // 비공개로 낙관 대입 → PATCH 500 실패 → 이전 값(true)으로 원복.
    store.setTokenUsagePublic(false)
    #expect(store.tokenUsagePublic == false)  // 낙관 대입 즉시 반영.

    var reverted = false
    for _ in 0..<200 {
        if store.tokenUsagePublic == true {
            reverted = true
            break
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(reverted)
}

@Test
func freshReceivedPokesFiltersByHourFreshnessBoundary() {
    // 기준 now.
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let epoch = Int(now.timeIntervalSince1970)
    let rows = [
        // 방금(신선) — 표시.
        TakenPokeRow(id: "fresh", fromUser: "u1", fromDisplayName: "영식", fromAvatarUrl: nil, createdEpoch: epoch - 10),
        // 정확히 1시간 경계(<=3600) — 포함.
        TakenPokeRow(id: "edge", fromUser: "u2", fromDisplayName: "민수", fromAvatarUrl: nil, createdEpoch: epoch - 3600),
        // 1시간 하고 1초 지남(>3600) — 제외.
        TakenPokeRow(id: "stale", fromUser: "u3", fromDisplayName: "지현", fromAvatarUrl: nil, createdEpoch: epoch - 3601)
    ]

    let fresh = WorkTimerStore.freshReceivedPokes(rows: rows, now: now)

    #expect(fresh.map(\.id) == ["fresh", "edge"])
    #expect(fresh.first?.fromName == "영식")
    #expect(fresh.first?.createdAt == Date(timeIntervalSince1970: TimeInterval(epoch - 10)))
}

/// setTokenUsagePublic 실패(원복) 검증 전용 프로토콜: 모든 요청에 500 을 돌려준다(PATCH profiles 를 실패시킨다).
final class PokeFailingURLProtocol: URLProtocol {
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PokeFailingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - v0.2.11 개인 기록 / 토큰 월 이동 / 근무 write 세대 토큰 / 넛지 자동시작

@MainActor
@Test
func toggleInsightsPanelIsMutuallyExclusiveWithOtherThreePanels() {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://insights-toggle-test")!,
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
    store.currentTeamID = URLProtocolStub.stubTeamID

    // 리그·토큰·찌르기가 모두 열린 상태에서 개인 기록을 열면 셋 다 닫힌다(4자 상호 배타).
    store.isLeaderboardVisible = true
    store.isTokenBoardVisible = true
    store.isPokePanelVisible = true
    store.toggleInsightsPanel()
    #expect(store.isInsightsPanelVisible)
    #expect(!store.isLeaderboardVisible)
    #expect(!store.isTokenBoardVisible)
    #expect(!store.isPokePanelVisible)

    // 반대 방향도 각각 성립해야 한다.
    store.toggleLeaderboard()
    #expect(store.isLeaderboardVisible)
    #expect(!store.isInsightsPanelVisible)

    store.toggleInsightsPanel()
    store.toggleTokenBoard()
    #expect(store.isTokenBoardVisible)
    #expect(!store.isInsightsPanelVisible)

    store.toggleInsightsPanel()
    #expect(!store.isTokenBoardVisible)
    store.togglePokePanel()
    #expect(store.isPokePanelVisible)
    #expect(!store.isInsightsPanelVisible)

    // 같은 버튼을 다시 누르면 닫힌다.
    store.toggleInsightsPanel()
    store.toggleInsightsPanel()
    #expect(!store.isInsightsPanelVisible)
}

@MainActor
@Test
func retroBannerShowsOncePerWeekAndIsConsumedBySeenMark() {
    let defaults = isolatedDefaults()
    let store = WorkTimerStore(
        service: SupabaseWorkService(
            projectURL: URL(string: "http://retro-banner-test")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        ),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    // 회고가 없으면 배너도 없다.
    store.evaluateRetroBanner()
    #expect(!store.showsRetroBanner)

    store.retro = WeeklyRetro(
        weekStart: Date(timeIntervalSince1970: 1_800_000_000),
        totalSeconds: 7_200,
        goalSeconds: 40 * 3_600,
        previousWeekSeconds: 3_600,
        sessionCount: 2,
        busiestDayIndex: 0,
        busiestDaySeconds: 7_200
    )
    store.evaluateRetroBanner()
    #expect(store.showsRetroBanner)

    // 본 것으로 기록하면 즉시 내려가고, 이번 주에는 다시 뜨지 않는다(주당 1회).
    store.markRetroBannerSeen()
    #expect(!store.showsRetroBanner)
    #expect(defaults.string(forKey: WorkTimerStore.retroBannerShownWeekKey) == RetroWeekKey.current())
    store.evaluateRetroBanner()
    #expect(!store.showsRetroBanner)
}

@MainActor
@Test
func retroBannerIsConsumedWhenDrawnSoItDoesNotReturnOnEveryPopoverOpen() {
    // 회귀 지점: 배너를 띄우는 경로(evaluateRetroBanner)가 '이번 주 봤음' 키를 기록하지 않아, 사용자가 [보기]나
    // X 를 누르지 않으면 팝오버를 열 때마다(setMenuPresented → evaluateRetroBanner) 같은 배너가 되살아났다.
    // '주당 1회' 계약 위반일 뿐 아니라, '배너는 한 번에 하나(retro > update)' 규칙 때문에 회고가 상주하는 동안
    // 새 버전 안내 배너(앱 안에서 업데이트로 가는 유일한 경로)가 그 주 내내 한 번도 뜨지 못했다.
    let defaults = isolatedDefaults()
    let store = WorkTimerStore(
        service: SupabaseWorkService(
            projectURL: URL(string: "http://retro-banner-once-test")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        ),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.retro = WeeklyRetro(
        weekStart: Date(timeIntervalSince1970: 1_800_000_000),
        totalSeconds: 7_200,
        goalSeconds: 40 * 3_600,
        previousWeekSeconds: 3_600,
        sessionCount: 2,
        busiestDayIndex: 0,
        busiestDaySeconds: 7_200
    )
    // 개인 기록은 이미 이번 주 기준으로 받아 둔 상태(팝오버 오픈 훅이 재조회 대신 배너 판정만 하게 한다).
    store.insightsLoaded = true
    store.insightsWeekKey = RetroWeekKey.current()
    #expect(!store.needsInsightsReload)

    // 1) 월요일 첫 팝오버 — 배너가 뜬다. 아직 화면에 그려지기 전이라 이번 주 몫은 소비되지 않았다.
    store.setMenuPresented(true)
    #expect(store.showsRetroBanner)
    #expect(defaults.string(forKey: store.retroBannerShownWeekKeyForCurrentUser) == nil)

    // 뷰가 실제로 배너를 그리면(onAppear) 그때 이번 주 몫을 소비한다. 보고 있는 배너를 도중에 걷어내진 않는다.
    store.markRetroBannerDisplayed()
    #expect(store.showsRetroBanner)
    #expect(defaults.string(forKey: store.retroBannerShownWeekKeyForCurrentUser) == RetroWeekKey.current())
    store.evaluateRetroBanner()
    #expect(store.showsRetroBanner)

    // 2) 아무것도 누르지 않고 팝오버를 닫는다 → 배너는 이번 팝오버의 안내였으므로 내려간다.
    store.setMenuPresented(false)
    #expect(!store.showsRetroBanner)

    // 3) 다시 열어도(몇 번을 반복해도) 같은 주에는 두 번 다시 뜨지 않는다 — 그 자리를 새 버전 안내가 쓴다.
    for _ in 0..<3 {
        store.setMenuPresented(true)
        #expect(!store.showsRetroBanner)
        store.setMenuPresented(false)
        #expect(!store.showsRetroBanner)
    }
}

@MainActor
@Test
func retroBannerSurvivesAPopoverWhereAMoreUrgentBannerTookItsPlace() {
    // 소비는 '판정'이 아니라 '표시' 시점이다 — 더 급한 배너(12시간 확인 등)가 그 자리를 이겨 회고가 화면에
    // 뜨지도 못한 팝오버에서 이번 주 안내를 잃으면 안 된다(밀린 배너는 다음 팝오버에 뜬다는 계약).
    let defaults = isolatedDefaults()
    let store = WorkTimerStore(
        service: SupabaseWorkService(
            projectURL: URL(string: "http://retro-banner-yield-test")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        ),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.retro = WeeklyRetro(
        weekStart: Date(timeIntervalSince1970: 1_800_000_000),
        totalSeconds: 7_200,
        goalSeconds: 40 * 3_600,
        previousWeekSeconds: 3_600,
        sessionCount: 2,
        busiestDayIndex: 0,
        busiestDaySeconds: 7_200
    )
    store.insightsLoaded = true
    store.insightsWeekKey = RetroWeekKey.current()

    // 첫 팝오버: 자격은 갖췄지만 더 급한 배너에 밀려 뷰가 회고 배너를 그리지 않았다(onAppear 미호출).
    store.setMenuPresented(true)
    #expect(store.showsRetroBanner)
    store.setMenuPresented(false)
    #expect(defaults.string(forKey: store.retroBannerShownWeekKeyForCurrentUser) == nil)

    // 다음 팝오버에서 다시 올라온다.
    store.setMenuPresented(true)
    #expect(store.showsRetroBanner)
}

@MainActor
@Test
func openingInsightsPanelBeforeRetroArrivesDoesNotBurnThisWeeksBanner() {
    // 회귀 지점: [내 기록] 버튼(toggleInsightsPanel)이 회고 유무와 무관하게 markRetroBannerSeen() 을 불러,
    // 첫 조회가 실패해 retro 가 아직 nil 인 상태에서 패널을 열기만 해도 이번 주 배너 키가 소진됐다.
    // 그 뒤 네트워크가 복구돼 회고가 도착해도 그 주 내내 "지난주 기록이 준비됐어요" 배너가 뜨지 않았다.
    let defaults = isolatedDefaults()
    let store = WorkTimerStore(
        service: SupabaseWorkService(
            projectURL: URL(string: "http://retro-banner-empty-panel-test")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        ),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    // 아직 회고를 못 받은 상태(오프라인·첫 조회 실패)에서 [내 기록]을 열어 본다.
    #expect(store.retro == nil)
    store.toggleInsightsPanel()
    #expect(store.isInsightsPanelVisible)
    // 빈 패널을 열어 본 것만으로 이번 주 안내를 잃으면 안 된다.
    #expect(defaults.string(forKey: WorkTimerStore.retroBannerShownWeekKey) == nil)

    // 패널을 닫고 뒤늦게 회고가 도착하면 배너가 정상적으로 뜬다.
    store.toggleInsightsPanel()
    #expect(!store.isInsightsPanelVisible)
    store.retro = WeeklyRetro(
        weekStart: Date(timeIntervalSince1970: 1_800_000_000),
        totalSeconds: 7_200,
        goalSeconds: 40 * 3_600,
        previousWeekSeconds: 3_600,
        sessionCount: 2,
        busiestDayIndex: 0,
        busiestDaySeconds: 7_200
    )
    store.evaluateRetroBanner()
    #expect(store.showsRetroBanner)

    // 반대로 회고가 실제로 있을 때 패널을 열면 그때는 소비된다(패널 안 회고 카드와 중복 안내 방지).
    store.toggleInsightsPanel()
    #expect(store.isInsightsPanelVisible)
    #expect(!store.showsRetroBanner)
    #expect(defaults.string(forKey: WorkTimerStore.retroBannerShownWeekKey) == RetroWeekKey.current())
}

@MainActor
@Test
func retroBannerNeverStacksOnTopOfOpenInsightsPanelAndViewKeepsItOpen() {
    // 회귀 지점: 개인 기록 패널을 연 채 새 주 첫 팝오버를 열면 배너가 그 위에 겹쳐 뜨고, [보기] 가 단순
    // toggle 이라 보고 있던 패널을 오히려 닫아 버렸다(팀 목록으로 되돌아감).
    let defaults = isolatedDefaults()
    let store = WorkTimerStore(
        service: SupabaseWorkService(
            projectURL: URL(string: "http://retro-banner-open-panel-test")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        ),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    store.retro = WeeklyRetro(
        weekStart: Date(timeIntervalSince1970: 1_800_000_000),
        totalSeconds: 7_200,
        goalSeconds: 40 * 3_600,
        previousWeekSeconds: 3_600,
        sessionCount: 2,
        busiestDayIndex: 0,
        busiestDaySeconds: 7_200
    )
    store.isInsightsPanelVisible = true

    // 패널이 이미 열려 있으면 배너를 띄우지 않는다(회고 카드가 패널 안에 상시 있어 중복이다).
    store.evaluateRetroBanner()
    #expect(!store.showsRetroBanner)
    #expect(defaults.string(forKey: WorkTimerStore.retroBannerShownWeekKey) == RetroWeekKey.current())

    // 그래도 배너가 떠 있는 상태에서 [보기] 를 누르면(뷰의 액션 경로) 패널은 열린 채로 유지된다.
    store.showsRetroBanner = true
    store.openInsightsPanel()
    #expect(store.isInsightsPanelVisible)
    #expect(!store.showsRetroBanner)

    // 닫혀 있을 때의 [보기] 는 평소대로 패널을 연다.
    store.isInsightsPanelVisible = false
    store.showsRetroBanner = true
    store.openInsightsPanel()
    #expect(store.isInsightsPanelVisible)
    #expect(!store.showsRetroBanner)
}

@MainActor
@Test
func stepTokenBoardMonthReloadsBoardForMovedMonthAndClampsFuture() async {
    let testHost = "token-month-step-test"
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.tokenBoard = [
        TokenBoardEntry(userID: "u1", name: "영식", avatarURL: nil, total: 100, claudeInput: 100, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0)
    ]
    store.tokenBoardLoaded = true

    let currentMonth = TokenUsageMonthKey.current()
    #expect(store.tokenBoardMonth == currentMonth)

    // 현재 월에서 미래로는 못 간다 — 값도 안 바뀌고 요청도 발사되지 않는다.
    let before = URLProtocolStub.requests(forHost: testHost).count
    store.stepTokenBoardMonth(by: 1)
    #expect(store.tokenBoardMonth == currentMonth)
    #expect(URLProtocolStub.requests(forHost: testHost).count == before)
    #expect(store.tokenBoardLoaded)

    // 과거로 한 칸 — 보드를 비우고 로드 전 상태로 되돌린 뒤 그 달로 다시 조회한다.
    let previousMonth = TokenUsageMonthKey.current(
        TeamWeeklyGoal.kstCalendar.date(byAdding: .month, value: -1, to: Date())!
    )
    store.stepTokenBoardMonth(by: -1)
    #expect(store.tokenBoardMonth == previousMonth)
    #expect(store.tokenBoard.isEmpty)
    #expect(!store.tokenBoardLoaded)

    // 실제 조회가 이동한 달로 나가는지(하드코딩된 이번 달이 아닌지) 요청 본문으로 확인한다.
    await store.performLoadTokenBoard()
    let bodies = URLProtocolStub.bodies(forHost: testHost)
    #expect(bodies.contains { $0.contains("\"p_month\":\"\(previousMonth)\"") })

    // 패널을 닫으면 이번 달로 되돌아간다(다음에 열 때 늘 현재 달부터).
    store.isTokenBoardVisible = true
    store.toggleTokenBoard()
    #expect(!store.isTokenBoardVisible)
    #expect(store.tokenBoardMonth == currentMonth)
    #expect(store.tokenBoard.isEmpty)
    #expect(!store.tokenBoardLoaded)
}

@MainActor
@Test
func everyTokenBoardCloseRouteResetsMonthToCurrent() {
    // 회귀 지점: 뷰의 뒤로 버튼과 다른 패널 열기가 isTokenBoardVisible 만 직접 껐던 탓에, 보던 과거 달이
    // 남아 다음에 열면 과거 달이 그대로 떴다. 이제 모든 닫기 경로가 closeTokenBoard() 를 지난다.
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    let currentMonth = TokenUsageMonthKey.current()
    let pastMonth = TokenBoardMonthNavigator.step(currentMonth, by: -2)

    func openBoardOnPastMonth() {
        store.isTokenBoardVisible = true
        store.tokenBoardMonth = pastMonth
        store.tokenBoard = [
            TokenBoardEntry(userID: "u1", name: "영식", avatarURL: nil, total: 100, claudeInput: 100, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0)
        ]
        store.tokenBoardLoaded = true
    }

    // (1) 뒤로 버튼 경로.
    openBoardOnPastMonth()
    store.closeTokenBoard()
    #expect(!store.isTokenBoardVisible)
    #expect(store.tokenBoardMonth == currentMonth)
    #expect(store.tokenBoard.isEmpty)
    #expect(!store.tokenBoardLoaded)

    // (2) 다른 패널로 넘어가는 경로 3종도 같은 정리를 거친다.
    openBoardOnPastMonth()
    store.toggleLeaderboard()
    #expect(store.tokenBoardMonth == currentMonth)

    openBoardOnPastMonth()
    store.togglePokePanel()
    #expect(store.tokenBoardMonth == currentMonth)

    openBoardOnPastMonth()
    store.toggleInsightsPanel()
    #expect(store.tokenBoardMonth == currentMonth)
}

@MainActor
@Test
func tokenBoardOpenAfterMonthRolloverShowsCurrentMonth() async {
    // 회귀 지점: tokenBoardMonth 는 스토어 init 때 한 번만 잡히고, 닫기 경로 closeTokenBoard() 는
    // "이미 현재 달"이면 조기 반환해 아무것도 정리하지 않는다. 그래서 6월에 보드를 열었다 닫고
    // 앱을 켜 둔 채 7월이 되면 (tokenBoardMonth=6월, tokenBoardLoaded=true, 6월 행) 이 그대로 살아,
    // 다시 열 때 "불러오는 중…"조차 없이 지난달 순위가 그려지고 재조회마저 p_month=지난달로 나갔다.
    // 이제 여는 경로도 현재 달로 재동기화한다.
    let testHost = "token-board-month-rollover-test"
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.currentTeamID = URLProtocolStub.stubTeamID

    let currentMonth = TokenUsageMonthKey.current()
    let lastMonth = TokenBoardMonthNavigator.step(currentMonth, by: -1)

    // 달이 바뀐 직후 상태를 그대로 만든다: 지난달에 열어 성공 로드하고 닫은 스토어(그 달엔 닫기가 조기 반환했다).
    store.tokenBoardMonth = lastMonth
    store.tokenBoard = [
        TokenBoardEntry(userID: "u1", name: "지난달영식", avatarURL: nil, total: 100, claudeInput: 100, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0)
    ]
    store.tokenBoardLoaded = true
    store.isTokenBoardVisible = false

    store.toggleTokenBoard()

    #expect(store.isTokenBoardVisible)
    #expect(store.tokenBoardMonth == currentMonth)
    #expect(store.tokenBoard.isEmpty)   // 지난달 행이 '이번 달인 척' 남지 않는다.
    #expect(!store.tokenBoardLoaded)
    #expect(store.tokenBoardLoading)    // 첫 프레임부터 "불러오는 중…"이 뜬다.

    await store.performLoadTokenBoard()
    let bodies = URLProtocolStub.bodies(forHost: testHost)
    #expect(bodies.contains { $0.contains("\"p_month\":\"\(currentMonth)\"") })
    #expect(!bodies.contains { $0.contains("\"p_month\":\"\(lastMonth)\"") })
}

@MainActor
@Test
func staleTeamStatusResponseDoesNotUndoJustPressedStop() {
    let testHost = "work-write-generation-test"
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
        store.syncTask?.cancel()
    }
    let userID = "00000000-0000-0000-0000-000000000002"
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
    store.currentTeamID = URLProtocolStub.stubTeamID

    let sessionStart = Date().addingTimeInterval(-3_600)
    // 이미 발사돼 날아오는 중인 팀 상태 응답의 내용: 서버는 아직 '근무중'으로 알고 있다.
    store.teamMembers = [
        TeamMemberStatus(
            id: userID,
            name: "영식",
            status: .working,
            updatedAt: Date(),
            currentSessionStartedAt: sessionStart,
            weeklyDurationSeconds: 0,
            todayDurationSeconds: 0,
            avatarURL: nil,
            lastSeenAt: Date(),
            activeSessionID: "30000000-0000-0000-0000-000000000001"
        )
    ]
    // refreshTeamStatus 가 fetch 를 발사하기 직전에 캡처했을 세대 값.
    let capturedGeneration = store.workStateWriteGeneration

    // 응답이 도착하기 전에 사용자가 '근무 종료'를 눌렀다.
    store.startedAt = sessionStart
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
    store.stop()
    #expect(store.startedAt == nil)
    #expect(store.workStateWriteGeneration == capturedGeneration + 1)
    // 미반영 큐는 이미 드레인됐다고 두어 흡수 게이트가 아니라 세대 토큰만 검증하게 한다.
    store.pendingItems = []

    // 낡은 응답 반영: 세대가 어긋나므로 내 상태 흡수를 건너뛰어야 한다(근무가 되살아나면 결함 재발).
    store.applyRemoteOwnStatus(writeGeneration: capturedGeneration)
    #expect(store.startedAt == nil)
    #expect(!store.snapshot.isWorking)

    // 대조군: 최신 세대의 응답은 정상 흡수한다(가드가 복구 경로 자체를 막는 것이 아님).
    store.applyRemoteOwnStatus(writeGeneration: store.workStateWriteGeneration)
    #expect(store.startedAt == sessionStart)
    #expect(store.snapshot.isWorking)
}

@MainActor
@Test
func deviceIDSurvivesRelaunchAndSignOut() {
    let defaults = isolatedDefaults()
    func makeStore() -> WorkTimerStore {
        WorkTimerStore(
            service: SupabaseWorkService(
                projectURL: URL(string: "http://nudge-persist-test")!,
                anonKey: "anon-test-key",
                session: URLSession(configuration: .stubbed)
            ),
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: defaults
        )
    }

    let store = makeStore()
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    // 기기 식별자는 최초 실행에서 생성된다(맥별 토큰 원장 분리 키).
    #expect(!store.deviceID.isEmpty)
    let firstDeviceID = store.deviceID

    // 재실행(같은 defaults)에서도 같은 값이 유지돼야 한다.
    let relaunched = makeStore()
    defer {
        relaunched.tickerTask?.cancel()
        relaunched.refreshTask?.cancel()
    }
    #expect(relaunched.deviceID == firstDeviceID)

    // 로그아웃은 계정 상태만 지운다 — 기기 식별자는 이 맥의 것이라 살아남는다.
    relaunched.signOut()
    #expect(relaunched.deviceID == firstDeviceID)
}

@MainActor
@Test
func signOutClearsInsightsAndTokenBoardMonth() {
    let store = WorkTimerStore(
        service: SupabaseWorkService(
            projectURL: URL(string: "http://insights-signout-test")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        ),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.isInsightsPanelVisible = true
    store.insightsLoaded = true
    store.showsRetroBanner = true
    store.retro = WeeklyRetro(
        weekStart: Date(timeIntervalSince1970: 1_800_000_000),
        totalSeconds: 7_200,
        goalSeconds: 3_600,
        previousWeekSeconds: 0,
        sessionCount: 1,
        busiestDayIndex: 0,
        busiestDaySeconds: 7_200
    )
    store.heatmap = WorkRhythmHeatmap.build(
        sessions: [
            WorkSessionRow(
                id: "s1",
                userId: "me",
                startedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3_600)),
                endedAt: ISO8601DateFormatter().string(from: Date()),
                durationSeconds: 3_600
            )
        ],
        now: Date()
    )
    store.tokenBoardMonth = TokenBoardMonthNavigator.step(TokenUsageMonthKey.current(), by: -2)

    store.signOut()

    // 세션이 사라지면 개인 기록/회고/월 위치도 초기화된다(리그·토큰 보드와 동일 규약).
    #expect(!store.isInsightsPanelVisible)
    #expect(!store.insightsLoaded)
    #expect(!store.showsRetroBanner)
    #expect(store.retro == nil)
    #expect(store.heatmap == .empty)
    #expect(store.tokenBoardMonth == TokenUsageMonthKey.current())
}

@MainActor
@Test
func insightsAreRecomputedWhenWeekRollsOverWhileAppStaysOpen() async {
    // 회귀 지점: 첫 성공 로드에서 insightsLoaded 가 영구화돼, '내 기록' 패널을 직접 열지 않는 한 loadInsights 는
    // 앱 실행당 딱 1회만 돌았다. WeeklyRetro 는 호출 시점의 now 로 '지난주'를 정하므로, 앱을 켜 둔 채 주가 바뀌면
    // store.retro 가 이전 주에 고정되고 evaluateRetroBanner 는 그 고정값만 봐서 월요일 회고 배너가 영영 안 떴다.
    let testHost = "insights-week-rollover-test"
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.currentTeamID = URLProtocolStub.stubTeamID

    // 아직 한 번도 못 받았으면 당연히 재계산 대상.
    #expect(store.needsInsightsReload)

    // 성공 로드가 '어느 주 기준인지'를 남긴다(스텁 work_sessions 픽스처).
    await store.performLoadInsights()
    #expect(store.insightsLoaded)
    #expect(store.insightsWeekKey == RetroWeekKey.current())

    // 같은 주에 팝오버를 다시 열면 조용히 넘어간다(불필요한 재조회 없음).
    #expect(!store.needsInsightsReload)

    // 주가 넘어가면(앱을 켜 둔 채 월요일) 반드시 다시 계산한다 — 낡은 주의 retro 로 배너 판정이 굳지 않게.
    store.insightsWeekKey = "2020-W01"
    #expect(store.needsInsightsReload)

    // 로그아웃은 주 키까지 비운다(다음 로그인의 첫 팝오버가 처음부터 다시 계산하도록).
    store.signOut()
    #expect(store.insightsWeekKey == nil)
}

@MainActor
@Test
func retroGoalFollowsTeamGoalConfirmedAfterInsightsLoad() async {
    // 회귀 지점: teamGoalSeconds 는 영속되지 않아 기본값(40시간)으로 시작하고 confirmMembership 응답에서야
    // 서버값이 된다. 콜드 런치 첫 팝오버에서는 인사이트 응답이 그보다 먼저 도착할 수 있는데, 그렇게 계산된
    // retro 는 insightsWeekKey 가 찍혀 그 주 내내 재계산 대상에서 빠졌다 — 목표 20시간 팀에서 25시간을
    // 일하고도 "목표 40시간 중 62% · 15시간 부족" 이 뜨는 이유였다.
    let testHost = "retro-goal-late-test"
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")

    // 멤버십 확정 전(기본 목표 40시간) 상태에서 회고가 먼저 계산된 상황을 재현한다: 지난주 25시간.
    store.insightsLoaded = true
    store.retro = WeeklyRetro(
        weekStart: TeamWeeklyGoal.koreanWeekStart(for: Date()).addingTimeInterval(-7 * 86_400),
        totalSeconds: 25 * 3_600,
        goalSeconds: TeamWeeklyGoal.defaultGoalSeconds,
        previousWeekSeconds: 0,
        sessionCount: 5,
        busiestDayIndex: 1,
        busiestDaySeconds: 8 * 3_600
    )
    #expect(store.retro?.metGoal == false)

    // 뒤늦게 도착한 멤버십 응답이 팀 목표를 20시간으로 확정한다 → 회고 목표선도 함께 따라가야 한다.
    store.teamGoalSeconds = 20 * 3_600
    store.reconcileInsightsGoal()
    #expect(store.retro?.goalSeconds == 20 * 3_600)
    #expect(store.retro?.metGoal == true)
    // 목표 외 집계는 그대로다(세션을 다시 받아 오지 않는다 — 사본으로 목표선만 갈아 끼운다).
    #expect(store.retro?.totalSeconds == 25 * 3_600)
    #expect(store.retro?.sessionCount == 5)
    #expect(store.retro?.busiestDayIndex == 1)

    // 값이 같으면 아무것도 하지 않는다(무의미한 재대입으로 뷰를 흔들지 않는다).
    let before = store.retro
    store.reconcileInsightsGoal()
    #expect(store.retro == before)

    // 실제 경로에서도 이어진다: 멤버십 응답(스텁 40시간)이 도착하면 회고가 그 목표로 정렬된다.
    store.currentTeamID = URLProtocolStub.stubTeamID
    await store.confirmMembership()
    #expect(store.teamGoalSeconds == 40 * 3_600)
    #expect(store.retro?.goalSeconds == 40 * 3_600)
    #expect(store.retro?.metGoal == false)
}

@MainActor
@Test
func insightsIncludeTheRunningSessionThatCrossedTheWeekBoundary() async {
    // 서버 조회는 완료 세션만 준다(ended_at not null). 주말을 넘겨 아직 끝나지 않은 근무(일요일 밤 시작 →
    // 이번 주까지 진행 중)의 지난주 몫이 통째로 빠지면 패널이 지난주를 실제보다 짧게 말한다.
    // 이 호스트는 work_sessions GET 에 빈 배열을 준다 = 완료 세션 0건 계정.
    let testHost = "insights-first-day-test"
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.currentTeamID = URLProtocolStub.stubTeamID

    // (a) 근무 중이 아니면 지난주 기록이 없다고 말한다(회고 카드와 같은 문장).
    await store.performLoadInsights()
    #expect(store.insightsLoaded)
    #expect(store.heatmap.totalSeconds == 0)
    #expect(
        InsightsEmptyMessage.text(hasLoaded: store.insightsLoaded, hasFailed: store.insightsFailed,
                                  totalSeconds: store.heatmap.totalSeconds) == InsightsEmptyMessage.noRetro
    )

    // (b) 지난주 마지막 한 시간(일요일 23:00)에 [근무 시작]을 눌러 아직 끝나지 않았다면, 그 한 시간만 들어온다.
    //     실제 시계로 도는 경로라 주 경계에서 역산해 픽스처를 만든다(언제 돌려도 결과가 같다).
    let weekBoundary = WorkInsightsWeekWindow.lastWeek(now: Date())!.end   // 이번 주 월요일 00:00
    store.startedAt = weekBoundary.addingTimeInterval(-3_600)
    await store.performLoadInsights()

    #expect(store.heatmap.totalSeconds == 3_600)
    #expect(store.heatmap.buckets[6][23] == 3_600)   // 일요일 23시 한 칸
    // 이번 주로 넘어간 구간은 히트맵에 들어오지 않는다(창이 지난주뿐이다).
    #expect(store.heatmap.buckets[0][0] == 0)
    // 회고도 같은 주·같은 클리핑이라 합이 정확히 일치한다.
    #expect(store.retro?.totalSeconds == store.heatmap.totalSeconds)
    // 보여 줄 기록이 생겼으니 자리 문구가 아니라 본문을 그린다.
    #expect(
        InsightsEmptyMessage.text(hasLoaded: store.insightsLoaded, hasFailed: store.insightsFailed,
                                  totalSeconds: store.heatmap.totalSeconds) == nil
    )
    // (c) 근무를 끝내면(startedAt 이 nil) 진행분은 다시 빠진다 — 완료 행이 서버에서 오기 전 이중 계상 금지.
    store.startedAt = nil
    await store.performLoadInsights()
    #expect(store.heatmap.totalSeconds == 0)
}

@MainActor
@Test
func insightsLoadFailureIsDistinguishableFromLoading() async {
    // 회귀 지점: performLoadInsights 의 catch 가 아무 상태도 세우지 않아, 조회가 실패해도 패널이
    // "불러오는 중…" 그대로 멈춰 있었다(진행중과 실패가 같은 문구 + 패널 안 재시도 경로 없음).
    let testHost = "insights-fetch-fails"
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.currentTeamID = URLProtocolStub.stubTeamID

    // 로드 전에는 실패 표시가 없다 — 첫 프레임은 "불러오는 중…".
    #expect(!store.insightsFailed)
    #expect(
        InsightsEmptyMessage.text(hasLoaded: store.insightsLoaded, hasFailed: store.insightsFailed, totalSeconds: 0)
            == InsightsEmptyMessage.loading
    )

    await store.performLoadInsights()

    // 실패는 실패로 보인다(문구가 갈리고 재시도 버튼이 붙는다).
    #expect(!store.insightsLoaded)
    #expect(store.insightsFailed)
    #expect(
        InsightsEmptyMessage.text(hasLoaded: store.insightsLoaded, hasFailed: store.insightsFailed, totalSeconds: 0)
            == InsightsEmptyMessage.loadFailed
    )
    // 실패해도 동기화 문구는 흔들지 않는다(패널 본문에서만 알린다 — 기존 규약 유지).
    #expect(store.syncMessage != InsightsEmptyMessage.loadFailed)
    // 실패 상태여도 다음 재오픈에서 다시 시도한다.
    #expect(store.needsInsightsReload)

    // 로그아웃은 실패 표시까지 비운다(다음 로그인의 첫 팝오버가 "불러오는 중…"부터 시작하도록).
    store.signOut()
    #expect(!store.insightsFailed)
}

@MainActor
@Test
func insightsRetrySucceedsAndClearsFailure() async {
    // [다시 시도] 경로: 재시도가 시작되면 실패 표시가 즉시 내려가고(다시 "불러오는 중…"), 성공하면 그대로 유지된다.
    let testHost = "insights-retry-test"
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.insightsFailed = true

    await store.performLoadInsights()

    #expect(store.insightsLoaded)
    #expect(!store.insightsFailed)
    #expect(
        InsightsEmptyMessage.text(hasLoaded: true, hasFailed: false, totalSeconds: store.heatmap.totalSeconds) == nil
            || store.heatmap.totalSeconds == 0
    )
}

/// 지난주 회고/히트맵 픽스처(주 경계 스테일 검증용) — 값 자체는 중요하지 않고 '비어 있지 않다'는 사실만 쓴다.
@MainActor
private func seedInsightsSnapshot(_ store: WorkTimerStore, weekKey: String) {
    var seeded = WorkRhythmHeatmap.empty
    // 지난주 월요일 09~16시를 꽉 채우고 17시엔 40분 — 한 주짜리 히트맵이라 한 칸은 3600초를 넘을 수 없다.
    for hour in 9...16 { seeded.buckets[0][hour] = 3_600 }
    seeded.buckets[0][17] = 2_400
    seeded.totalSeconds = 8 * 3_600 + 2_400   // 8시간 40분
    store.heatmap = seeded
    store.retro = WeeklyRetro(
        weekStart: TeamWeeklyGoal.koreanWeekStart(for: Date()).addingTimeInterval(-14 * 86_400),
        totalSeconds: 31_200,
        goalSeconds: 40 * 3_600,
        previousWeekSeconds: 0,
        sessionCount: 12,
        busiestDayIndex: 1,
        busiestDaySeconds: 8 * 3_600
    )
    store.insightsLoaded = true
    store.insightsWeekKey = weekKey
}

@MainActor
@Test
func staleWeekInsightsAreDiscardedWhenReloadFails() async {
    // 회귀 지점: 앱을 켜 둔 채 주가 바뀌면 store.retro 는 '지지난주' 집계로 고정된다. 재계산이 실패하면
    // 예전엔 실패 플래그만 세우고 낡은 retro/heatmap 을 그대로 뒀는데, 뷰는 (로드 완료 + 누적>0) 이면
    // 실패 문구도 [다시 시도]도 없이 본문을 그리고 회고 카드에는 대상 주 날짜가 없다 — 2주 전 합계가
    // "지난주 8시간 40분 / 세션 12회"로 지난주인 척 표시됐고 사용자가 스테일임을 알 단서가 없었다.
    let testHost = "insights-fetch-fails"
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.currentTeamID = URLProtocolStub.stubTeamID

    // 지난주에 계산해 둔 스냅샷을 들고 주말을 넘긴 상태(주 키가 지금 주와 어긋난다).
    seedInsightsSnapshot(store, weekKey: "2020-01-06")
    store.showsRetroBanner = true
    #expect(store.needsInsightsReload)

    // 월요일 아침 첫 팝오버 — 네트워크 실패.
    await store.performLoadInsights()

    // 낡은 주 기준 값은 남지 않는다(지지난주 합계가 '지난주'로 그려질 여지 자체를 없앤다).
    #expect(store.retro == nil)
    #expect(store.heatmap.totalSeconds == 0)
    #expect(store.insightsWeekKey == nil)
    #expect(!store.insightsLoaded)
    #expect(store.insightsFailed)
    // 화면은 0건 실패와 같은 경로로 떨어진다 — 실패 문구 + [다시 시도].
    #expect(
        InsightsEmptyMessage.text(
            hasLoaded: store.insightsLoaded,
            hasFailed: store.insightsFailed,
            totalSeconds: store.heatmap.totalSeconds
        ) == InsightsEmptyMessage.loadFailed
    )
    // 보여 줄 회고가 없으니 "지난주 기록이 준비됐어요" 배너도 내린다(이번 주 키는 소비하지 않는다).
    #expect(!store.showsRetroBanner)
    #expect(store.defaults.string(forKey: store.retroBannerShownWeekKeyForCurrentUser) != RetroWeekKey.current())
    #expect(store.needsInsightsReload)
}

@MainActor
@Test
func sameWeekInsightsSnapshotSurvivesLoadFailure() async {
    // 반대 방향 고정: 주가 바뀌지 않았다면 실패가 직전 스냅샷을 지우지 않는다(같은 주 값이라 여전히 사실이다).
    let testHost = "insights-fetch-fails"
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.currentTeamID = URLProtocolStub.stubTeamID

    seedInsightsSnapshot(store, weekKey: RetroWeekKey.current())
    let before = store.retro

    await store.performLoadInsights()

    #expect(store.retro == before)
    #expect(store.heatmap.totalSeconds == 31_200)
    #expect(store.insightsLoaded)
    #expect(store.insightsFailed)
    // 보여 줄 기록이 남아 있으므로 본문을 계속 그린다(기존 규약 유지).
    #expect(
        InsightsEmptyMessage.text(
            hasLoaded: store.insightsLoaded,
            hasFailed: store.insightsFailed,
            totalSeconds: store.heatmap.totalSeconds
        ) == nil
    )
}

@MainActor
@Test
func stepTokenBoardMonthShowsLoadingTextInsteadOfSyncStatus() async {
    // 회귀 지점: 월 이동이 tokenBoardLoaded 를 false 로 되돌리는 사이, 빈 목록 자리에 순위도 로딩 문구도 아닌
    // store.syncMessage("동기화됨")가 떴다. 개인 기록 패널에서 이미 금지한 패턴인데 월 이동으로 반복 노출됐다.
    let testHost = "token-month-loading-test"
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.syncMessage = "동기화됨"
    store.tokenBoardLoaded = true
    store.isTokenBoardVisible = true

    // 로드가 끝난 상태에서는 진행중 표시가 없다.
    #expect(!store.tokenBoardLoading)

    // ‹ 로 지난달 이동 — 목록을 비우는 그 프레임부터 진행중이어야 한다(Task 발사 전 동기 세팅).
    store.stepTokenBoardMonth(by: -1)
    #expect(!store.tokenBoardLoaded)
    #expect(store.tokenBoardLoading)
    #expect(
        TokenBoardEmptyMessage.text(
            hasLoaded: store.tokenBoardLoaded,
            isLoading: store.tokenBoardLoading,
            fallbackStatus: store.syncMessage,
            isCurrentMonth: false
        ) == TokenBoardEmptyMessage.loading
    )

    // 조회가 끝나면(성공이든 실패든) 진행중 표시는 반드시 내려간다.
    await store.performLoadTokenBoard()
    #expect(!store.tokenBoardLoading)

    // 진행중이 아닌데도 비어 있으면(첫 오픈 실패 등) 기존대로 동기화 상태 문구를 쓴다 — 계약 불변.
    #expect(
        TokenBoardEmptyMessage.text(hasLoaded: false, isLoading: false, fallbackStatus: "동기화됨")
            == "동기화됨"
    )
    // 로드 완료 후 문구는 달에 따라 갈린다(불변).
    #expect(TokenBoardEmptyMessage.text(hasLoaded: true, isLoading: false, fallbackStatus: "동기화됨") == TokenBoardEmptyMessage.noUploads)
    #expect(TokenBoardEmptyMessage.text(hasLoaded: true, isLoading: false, fallbackStatus: "동기화됨", isCurrentMonth: false) == TokenBoardEmptyMessage.noPastRecords)
}

@MainActor
@Test
func tokenBoardLoadFailureShowsFailureTextInsteadOfSyncMessage() async {
    // 회귀 지점: 월 이동 중 조회가 실패하면 (로드 전 + 진행중 아님 + 빈 목록) 조합이 남아, 본문 자리에
    // syncMessage("동기화됨"·"근무 재개됨" 등 무관한 문구)가 그대로 떴다(재시도 수단도 없었다).
    let testHost = "token-board-fails"
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.syncMessage = "동기화됨"
    store.isTokenBoardVisible = true
    store.tokenBoardLoaded = true
    store.tokenBoard = [
        TokenBoardEntry(userID: "u1", name: "영식", avatarURL: nil, total: 100, claudeInput: 100, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0)
    ]

    // ‹ 로 지난달 이동 — 첫 프레임은 "불러오는 중…"(기존 규약).
    store.stepTokenBoardMonth(by: -1)
    #expect(store.tokenBoardLoading)
    #expect(!store.tokenBoardFailed)

    await store.performLoadTokenBoard()

    // 실패는 실패로 보인다 — 동기화 문구가 아니라 실패 문구 + [다시 시도].
    #expect(!store.tokenBoardLoaded)
    #expect(!store.tokenBoardLoading)
    #expect(store.tokenBoardFailed)
    #expect(
        TokenBoardEmptyMessage.text(
            hasLoaded: store.tokenBoardLoaded,
            isLoading: store.tokenBoardLoading,
            hasFailed: store.tokenBoardFailed,
            fallbackStatus: store.syncMessage,
            isCurrentMonth: false
        ) == TokenBoardEmptyMessage.loadFailed
    )
    // 실패해도 동기화 문구 자체는 흔들지 않는다(패널 본문에서만 알린다 — 기존 규약 유지).
    #expect(store.syncMessage == "동기화됨")

    // 재조회가 시작되면 실패 표시가 즉시 내려가고 다시 "불러오는 중…"으로 돌아간다([다시 시도] 경로).
    store.stepTokenBoardMonth(by: -1)
    #expect(!store.tokenBoardFailed)
    #expect(store.tokenBoardLoading)

    // 로그아웃은 실패 표시까지 비운다(다음 로그인의 첫 오픈이 "불러오는 중…"부터 시작하도록).
    store.tokenBoardFailed = true
    store.signOut()
    #expect(!store.tokenBoardFailed)

    // 조회가 시작조차 되지 않은 상태(로그인 전 등)에서는 기존대로 상태 문구를 쓴다 — 계약 불변.
    #expect(
        TokenBoardEmptyMessage.text(hasLoaded: false, isLoading: false, hasFailed: false, fallbackStatus: "로그인 필요")
            == "로그인 필요"
    )
}

@MainActor
@Test
func retroBannerSeenMarkIsScopedToAccount() {
    // 회귀 지점: '이번 주 봤음' 키가 계정과 무관한 전역 키라, 같은 맥에서 A 가 배너를 소비하고 로그아웃하면
    // 같은 주에 로그인한 B 가 그 주 내내 회고 배너를 한 번도 못 받았다(로그아웃은 이 키를 지우지 않는다).
    let defaults = isolatedDefaults()
    func makeStore() -> WorkTimerStore {
        WorkTimerStore(
            service: SupabaseWorkService(
                projectURL: URL(string: "http://retro-account-scope-test")!,
                anonKey: "anon-test-key",
                session: URLSession(configuration: .stubbed)
            ),
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: defaults
        )
    }
    let retro = WeeklyRetro(
        weekStart: Date(timeIntervalSince1970: 1_800_000_000),
        totalSeconds: 7_200,
        goalSeconds: 40 * 3_600,
        previousWeekSeconds: 3_600,
        sessionCount: 2,
        busiestDayIndex: 0,
        busiestDaySeconds: 7_200
    )

    // A 계정: 배너를 받고 소비한다.
    let storeA = makeStore()
    defer {
        storeA.tickerTask?.cancel()
        storeA.refreshTask?.cancel()
    }
    storeA.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "user-a")
    storeA.retro = retro
    storeA.evaluateRetroBanner()
    #expect(storeA.showsRetroBanner)
    storeA.markRetroBannerSeen()
    #expect(!storeA.showsRetroBanner)
    // 기록은 계정별 키에 남는다(전역 키를 오염시키지 않는다).
    #expect(defaults.string(forKey: "\(WorkTimerStore.retroBannerShownWeekKey).user-a") == RetroWeekKey.current())
    storeA.evaluateRetroBanner()
    #expect(!storeA.showsRetroBanner)

    // 같은 맥·같은 주에 B 계정으로 갈아타면 B 는 자기 회고를 정상적으로 받는다.
    storeA.signOut()
    let storeB = makeStore()
    defer {
        storeB.tickerTask?.cancel()
        storeB.refreshTask?.cancel()
    }
    storeB.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "user-b")
    storeB.retro = retro
    storeB.evaluateRetroBanner()
    #expect(storeB.showsRetroBanner)
    storeB.markRetroBannerSeen()
    #expect(defaults.string(forKey: "\(WorkTimerStore.retroBannerShownWeekKey).user-b") == RetroWeekKey.current())

    // A 로 되돌아와도 같은 주에 두 번 뜨지는 않는다(계정별 기록이 그대로 살아 있다).
    let storeARelogin = makeStore()
    defer {
        storeARelogin.tickerTask?.cancel()
        storeARelogin.refreshTask?.cancel()
    }
    storeARelogin.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "user-a")
    storeARelogin.retro = retro
    storeARelogin.evaluateRetroBanner()
    #expect(!storeARelogin.showsRetroBanner)
}

@MainActor
@Test
func signInLoadsInsightsSoRetroBannerShowsInTheSamePopoverSession() async {
    // 회귀 지점: 개인 기록(히트맵/회고) 자동 로드의 유일한 진입점이 팝오버 오픈 훅(setMenuPresented →
    // needsInsightsReload)뿐이었다. 그런데 팝오버 표시 알림은 뷰 identity 1회(onAppear)라, **팝오버를 연 채
    // 로그인하는 정상 동선**에서는 그 훅이 비로그인 시점에 이미 지나가 performLoadInsights 의 session 가드에서
    // 즉시 반환된다. signIn 성공 경로도 insights 를 부르지 않고 30초 refresh 루프에도 항목이 없어,
    // insightsLoaded 는 false 로 남고 evaluateRetroBanner 가 한 번도 호출되지 않았다 — 사용자가 스스로 열 수 없는
    // '지난주 회고 배너'가 팝오버를 닫았다 다시 열기 전까지 뜨지 않았다.
    let testHost = "signin-retro-banner-test"
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

    // 팝오버가 열린 채 로그인 화면을 보고 있는 상태(오픈 훅은 비로그인이라 아무것도 못 받는다).
    store.setMenuPresented(true)
    #expect(!store.insightsLoaded)
    #expect(!store.showsRetroBanner)

    store.email = "member@example.com"
    store.password = "team-password"
    await store.signIn()?.value

    #expect(store.isSignedIn)
    // 로그인 경로가 내 완료 세션 조회를 실제로 발사한다.
    let sessionQueries = URLProtocolStub.requests(forHost: testHost)
        .filter { $0.url?.path == "/rest/v1/work_sessions" }
        .compactMap { $0.url?.query }
    #expect(sessionQueries.contains { $0.contains("ended_at=not.is.null") })
    #expect(store.insightsLoaded)
    // 지난주 근무가 있는 계정이라 회고가 계산되고, 그 배너가 같은 팝오버 세션에서 바로 뜬다.
    #expect(store.retro != nil)
    #expect(store.showsRetroBanner)
}

@MainActor
@Test
func timedBannerIsPushedByStoreInsteadOfBeingJudgedEverySecond() {
    // 회귀 지점: 팝오버 body 가 canUndoAutoClose(now: displayNow) 를 직접 불러, 배너가 없는 평소 화면에서도
    // 매초 갱신되는 displayNow 를 관찰 등록했다(전체 트리 매초 무효화).
    // 이제 판정 결과만 스토어가 상태로 밀어 넣고, 뷰는 그 상태만 읽는다.
    let store = WorkTimerStore(
        service: SupabaseWorkService(
            projectURL: URL(string: "http://timed-banner-test")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        ),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }
    let now = Date()
    #expect(store.timedBanner == nil)

    // (1) 자리 비움 자동 마감 대상이 생기면 되돌리기 배너가 선다.
    store.lastAutoClosedSessionID = "11111111-2222-3333-4444-555555555555"
    store.lastAutoClosedStartedAt = now.addingTimeInterval(-7_200)
    store.lastAutoClosedAt = now
    store.refreshTimedBanner(now: now)
    #expect(store.timedBanner == .undoAutoClose)

    // 유예(10분)가 지나면 티커가 스스로 내린다 — 뷰가 매초 판정하지 않아도 사라진다.
    store.refreshTimedBanner(now: now.addingTimeInterval(WorkTimerStore.autoCloseUndoWindowSeconds + 1))
    #expect(store.timedBanner == nil)

    // (2) 근무를 시작하면 되돌리기 대상 자체가 끊기고 배너도 함께 사라진다(start 가 되맞춘다).
    store.lastAutoClosedSessionID = "11111111-2222-3333-4444-555555555555"
    store.lastAutoClosedStartedAt = now.addingTimeInterval(-7_200)
    store.lastAutoClosedAt = now
    store.refreshTimedBanner(now: now)
    #expect(store.timedBanner == .undoAutoClose)
    store.start(now: now)
    #expect(store.timedBanner == nil)

    // (3) 배너를 X 로 닫는 경로(clearAutoCloseUndo)도 상태를 즉시 내린다(되돌리기는 비근무 전용이라 먼저 종료).
    store.stop(now: now.addingTimeInterval(1))
    store.lastAutoClosedSessionID = "11111111-2222-3333-4444-555555555555"
    store.lastAutoClosedStartedAt = now.addingTimeInterval(-7_200)
    store.lastAutoClosedAt = Date()
    store.refreshTimedBanner()
    #expect(store.timedBanner == .undoAutoClose)
    store.clearAutoCloseUndo()
    #expect(store.timedBanner == nil)
}

// MARK: - 강제 로그아웃과 계정에 묶인 로컬 상태(큐 보존 vs 다음 계정 오염 금지)

@MainActor
@Test
func forcedLogoutKeepsPendingQueueForSameAccountRelogin() async {
    // 회귀 지점: 토큰 만료 강제 로그아웃(refresh token 무효/부재)도 clearPersistedSession() 을 타는데, 이 함수가
    // pendingItems/startedAt 을 비우면 오프라인에서 쌓아 둔 근무가 영구 소실된다(큐는 UserDefaults 에 남지 않는
    // 메모리 장부라 복구 수단이 없다). 큐는 강제 로그아웃을 살아남아야 하고, 같은 계정으로 다시 로그인하면
    // 순서대로 재생돼 서버에 기록돼야 한다.
    let testHost = "forced-logout-queue"
    let ownerID = "00000000-0000-0000-0000-000000000002"
    let store = makeStubStore(host: testHost, userID: ownerID)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    // 오프라인 09:00~18:00 근무가 통째로 큐에 쌓인 상태(시작/종료 모두 미전송).
    let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let endedAt = startedAt.addingTimeInterval(9 * 3_600)
    let sessionID = "aaaaaaaa-0000-0000-0000-00000000000a"
    store.pendingItems = [
        PendingWorkItem(
            id: UUID(),
            operation: .start,
            sessionID: sessionID,
            sessionStartedAt: startedAt,
            endedAt: nil,
            ownerUserID: ownerID
        ),
        PendingWorkItem(
            id: UUID(),
            operation: .stop(durationSeconds: 9 * 3_600),
            sessionID: sessionID,
            sessionStartedAt: startedAt,
            endedAt: endedAt,
            ownerUserID: ownerID
        )
    ]

    // 강제 로그아웃 — 큐와 소유 계정이 그대로 남아야 한다.
    store.clearPersistedSession()
    #expect(store.pendingItems.count == 2)
    #expect(store.workStateOwnerUserID == ownerID)

    // 같은 계정으로 재로그인(세션 재주입 + 소유자 확정) → 큐가 살아 있고 드레인이 서버에 재생한다.
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: ownerID)
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.adoptWorkStateOwner(ownerID)
    #expect(store.pendingItems.count == 2)

    await store.retryPendingSync()
    #expect(store.pendingItems.isEmpty)

    let requests = URLProtocolStub.requests(forHost: testHost)
    let bodies = URLProtocolStub.bodies(forHost: testHost)
    let statusStream = zip(requests, bodies)
        .filter { $0.0.url?.path == "/rest/v1/work_statuses" && $0.0.httpMethod == "POST" }
        .map { $0.1.contains(#""status":"working""#) ? "working" : "off_work" }
    #expect(statusStream == ["working", "off_work"])
}

@MainActor
@Test
func reloginWithDifferentAccountDiscardsPreviousOwnerWorkState() {
    // 강제 로그아웃이 큐를 남기더라도, 같은 맥에서 다른 계정이 로그인하면 앞 계정의 근무가 새 계정 이름으로
    // 기록돼선 안 된다(계정 오염). 폐기 시점은 '로그아웃'이 아니라 '다른 계정 로그인'이다.
    let previousOwner = "00000000-0000-0000-0000-00000000000a"
    let store = makeStubStore(host: "relogin-other-account", userID: previousOwner)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    store.pendingItems = [
        PendingWorkItem(
            id: UUID(),
            operation: .stop(durationSeconds: 3_600),
            sessionID: "aaaaaaaa-0000-0000-0000-00000000000a",
            sessionStartedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_003_600),
            ownerUserID: previousOwner
        )
    ]
    store.startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    store.accumulatedSeconds = 4_242
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 4_242)

    store.clearPersistedSession()

    // 다른 계정으로 로그인 — 앞 계정에서 재전송될 수 있는 근거가 하나도 남지 않아야 한다.
    let newOwner = "00000000-0000-0000-0000-00000000000b"
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: newOwner)
    store.adoptWorkStateOwner(newOwner)

    #expect(store.pendingItems.isEmpty)
    #expect(store.startedAt == nil)
    #expect(store.currentSessionID == nil)
    #expect(store.accumulatedSeconds == 0)
    #expect(store.snapshot.status == .offWork)
    #expect(store.snapshot.elapsedSeconds == 0)
    #expect(store.workStateOwnerUserID == newOwner)
}

@MainActor
@Test
func forcedLogoutClearsAutoCloseUndoTarget() {
    // 회귀 지점: clearPersistedSession() 이 넛지 스탬프만 비우고 자리 비움 되돌리기 대상
    // (lastAutoClosedSessionID/StartedAt/At)은 남겨, 유예 10분 안에 다른 계정으로 로그인하면 남의
    // "자리 비움으로 근무를 종료했어요 [되돌리기]" 배너가 뜨고 누르면 새 계정 자격으로 앞 계정 세션을
    // 재개하려다 RLS 에서 거부돼 "재개 실패"만 남았다. signOut() 은 clearAutoCloseUndo() 로 이미 막고 있었다.
    let store = makeStubStore(host: "forced-logout-undo")
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
    }

    let now = Date()
    store.lastAutoClosedSessionID = "aaaaaaaa-0000-0000-0000-00000000000b"
    store.lastAutoClosedStartedAt = now.addingTimeInterval(-7_200)
    store.lastAutoClosedAt = now
    store.refreshTimedBanner(now: now)
    #expect(store.timedBanner == .undoAutoClose)

    store.clearPersistedSession()

    #expect(store.lastAutoClosedSessionID == nil)
    #expect(store.lastAutoClosedStartedAt == nil)
    #expect(store.lastAutoClosedAt == nil)
    #expect(!store.canUndoAutoClose())
    #expect(store.timedBanner == nil)

    // 다른 계정으로 재로그인해도 배너가 되살아나지 않는다.
    store.session = SupabaseSession(accessToken: "token-b", refreshToken: nil, userID: "00000000-0000-0000-0000-0000000000bb")
    store.refreshTimedBanner()
    #expect(store.timedBanner == nil)
}

// MARK: - AF: 자리 비움 자동 마감 (v0.2.35 — docs/away-close.md)
//
// 이 스위트가 고정하는 계약은 넷이다.
//  1. **임계는 서버가 소유한다.** 못 받았으면 몇 시간이 지나도 마감하지 않는다(모를 때의 안전한 기본값).
//  2. **판정 기준은 max(로컬 관측, 서버가 계산한 기기 max)** — 로컬 단독이면 "아이맥 켜둔 채 노트북에서
//     작업"이 결정론적으로 매일 오마감된다.
//  3. **closeEligible 을 클라가 무시하면 안 된다.** 클라는 서버 백스톱보다 30분 먼저 발화하므로,
//     서버에만 있는 혼합 함대 면제는 도달조차 못 한다.
//  4. **비소유 맥의 쓰기는 last_input_at 만이다.** session_id/last_seen_at 을 담는 순간 그 행이 소유권
//     판정의 증거로 승격돼 v0.2.16 의 이중 소유 사고로 되돌아간다.

private let awayUserID = "00000000-0000-0000-0000-000000000002"
private let awaySessionID = "20000000-0000-0000-0000-0000000000aa"

@MainActor
private func makeAwayStore(host: String, now: Date) -> WorkTimerStore {
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
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: awayUserID)
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.clock = { now }
    store.inputSessionUsable = { true }
    store.meaningfulIdleSeconds = { 0 }
    return store
}

/// 근무 중 + 서버 판정 재료가 갖춰진 상태를 만든다. threshold 는 **서버가 준 값**이다(클라 상수 아님).
@MainActor
private func armAwayStore(
    _ store: WorkTimerStore,
    now: Date,
    startedAt: Date,
    localInput: Date?,
    remoteInput: Date?,
    closeEligible: Bool = true,
    thresholdSeconds: TimeInterval? = 9_000,
    serverSessionID: String = awaySessionID
) {
    store.startedAt = startedAt
    store.currentSessionID = WorkTimerStore.canonicalSessionID(awaySessionID)
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
    store.lastMeaningfulInputAt = localInput
    store.awayServerSupported = true
    store.awayPolicy = thresholdSeconds.map {
        AwayPolicy(
            closeThresholdSeconds: $0,
            restoreWindowSeconds: 21_600,
            dailyRestoreLimit: 2,
            restoresLeftToday: 2,
            serverNow: now
        )
    }
    store.awayOpenSession = AwayOpenSession(
        sessionID: serverSessionID,
        startedAt: startedAt,
        lastInputAt: remoteInput,
        closeEligible: closeEligible
    )
}

/// docs/away-close.md 2절의 응답을 **문서에 적힌 그대로** 디코드한다. 키 하나가 어긋나면 여기서 죽는다.
@MainActor
@Test
func awaySyncResponseDecodesDocumentedContract() async {
    let json = """
    {
      "status": "ok",
      "serverNow": "2026-08-19T13:51:15.990741+00:00",
      "closeThresholdSeconds": 9000,
      "backstopSeconds": 10800,
      "freezeSeconds": 1800,
      "restoreWindowSeconds": 21600,
      "dailyRestoreLimit": 2,
      "restorableReasons": ["away", "sleep"],
      "restoresUsedToday": 0,
      "restoresLeftToday": 2,
      "openSession": {
        "id": "20000000-0000-0000-0000-0000000000aa",
        "teamId": "10000000-0000-0000-0000-000000000001",
        "startedAt": "2026-08-19T01:00:00+00:00",
        "lastInputAt": "2026-08-19T02:00:00+00:00",
        "closeEligible": true,
        "closeDueAt": "2026-08-19T04:30:00+00:00"
      },
      "restorable": {
        "sessionId": "30000000-0000-0000-0000-0000000000bb",
        "teamId": "10000000-0000-0000-0000-000000000001",
        "startedAt": "2026-08-19T00:00:00+00:00",
        "endedAt": "2026-08-19T02:59:00+00:00",
        "durationSeconds": 10740,
        "autoClosedAt": "2026-08-19T05:29:00+00:00",
        "autoClosedReason": "away",
        "expiresAt": "2026-08-19T08:59:00+00:00",
        "remainingSeconds": 10740
      }
    }
    """
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let response = try! decoder.decode(AwaySyncResponse.self, from: Data(json.utf8))
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://away-decode")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let sync = await service.awaySync(from: response)

    #expect(sync.isOK)
    #expect(sync.policy?.closeThresholdSeconds == 9_000)
    #expect(sync.policy?.restoreWindowSeconds == 21_600)
    #expect(sync.policy?.dailyRestoreLimit == 2)
    #expect(sync.openSession?.sessionID == "20000000-0000-0000-0000-0000000000aa")
    #expect(sync.openSession?.closeEligible == true)
    #expect(sync.openSession?.lastInputAt != nil)
    #expect(sync.restorable?.sessionID == "30000000-0000-0000-0000-0000000000bb")
    #expect(sync.restorable?.reason == .away)
    #expect(sync.restorable?.remainingSeconds == 10_740)
    #expect(sync.restorable?.expiresAt != nil)
}

/// 임계가 없는(혹은 0인) 응답은 **정책 없음**으로 접힌다 = 그 폴링에서 마감 금지.
/// closeEligible 키가 없으면 false 다 — 모르는 자격을 참으로 승격시키면 혼합 함대가 매일 지워진다.
@MainActor
@Test
func awaySyncTreatsMissingPolicyAndEligibilityAsUnknown() async {
    let json = """
    {"status":"ok","openSession":{"id":"20000000-0000-0000-0000-0000000000aa"}}
    """
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let response = try! decoder.decode(AwaySyncResponse.self, from: Data(json.utf8))
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://away-decode-2")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let sync = await service.awaySync(from: response)

    #expect(sync.policy == nil)
    #expect(sync.openSession?.closeEligible == false)
    #expect(sync.restorable == nil)
}

/// 임계 경계는 **배타적**이다(서버 부등호와 같다): 정확히 임계면 살아 있고, 넘겨야 마감된다.
/// 마감 시각은 마지막 입력 시각 그대로(소급)여야 한다 — 지금 시각으로 마감하면 자리 비운 시간이 근무로 남는다.
@MainActor
@Test
func awayCloseFiresOnlyPastServerThresholdAndBacktracksEndedAt() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let start = now.addingTimeInterval(-6 * 3_600)
    let lastInput = now.addingTimeInterval(-9_000)

    let onBoundary = makeAwayStore(host: "away-boundary", now: now)
    armAwayStore(onBoundary, now: now, startedAt: start, localInput: lastInput, remoteInput: nil)
    onBoundary.evaluateAwaySession(now: now)
    #expect(onBoundary.startedAt == start)

    let past = makeAwayStore(host: "away-past", now: now)
    armAwayStore(past, now: now, startedAt: start, localInput: lastInput.addingTimeInterval(-1), remoteInput: nil)
    past.evaluateAwaySession(now: now)
    #expect(past.startedAt == nil)
    #expect(past.syncMessage == "자리 비움으로 자동 근무종료됨")
    let stopped = past.pendingItems.last
    #expect(stopped?.endedAt == lastInput.addingTimeInterval(-1))
    #expect(stopped?.autoCloseReason == .away)
}

/// **서버가 임계를 안 줬으면 마감하지 않는다**(구버전 서버·오프라인·RPC 실패). 사장님 확정 사항이다 —
/// 클라 상수로 두면 계측 후 값을 바꿀 때 브루 지연으로 절반이 옛 값을 쓴다.
@MainActor
@Test
func awayCloseNeverFiresWithoutServerPolicy() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = makeAwayStore(host: "away-nopolicy", now: now)
    armAwayStore(
        store,
        now: now,
        startedAt: now.addingTimeInterval(-12 * 3_600),
        localInput: now.addingTimeInterval(-10 * 3_600),
        remoteInput: nil,
        thresholdSeconds: nil
    )

    store.evaluateAwaySession(now: now)

    #expect(store.startedAt != nil)
    #expect(store.pendingItems.isEmpty)
}

/// closeEligible 이 거짓이면(구버전 맥이 섞인 사용자) 통째로 면제다.
@MainActor
@Test
func awayCloseSkippedWhenServerSaysNotEligible() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = makeAwayStore(host: "away-ineligible", now: now)
    armAwayStore(
        store,
        now: now,
        startedAt: now.addingTimeInterval(-8 * 3_600),
        localInput: now.addingTimeInterval(-5 * 3_600),
        remoteInput: nil,
        closeEligible: false
    )

    store.evaluateAwaySession(now: now)

    #expect(store.startedAt != nil)
}

/// **아이맥 켜둔 채 노트북에서 작업.** 로컬 관측은 3시간 전에 멈췄지만 서버가 든 기기 max 는 1분 전이다 —
/// 로컬 단독으로 판정하면 이 사람은 매일 결정론적으로 오마감된다.
@MainActor
@Test
func awayCloseUsesRemoteDeviceInputWhenLocalIsStale() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = makeAwayStore(host: "away-remote", now: now)
    armAwayStore(
        store,
        now: now,
        startedAt: now.addingTimeInterval(-8 * 3_600),
        localInput: now.addingTimeInterval(-3 * 3_600),
        remoteInput: now.addingTimeInterval(-60)
    )

    store.evaluateAwaySession(now: now)

    #expect(store.startedAt != nil)
    #expect(store.awayLastInputAt() == now.addingTimeInterval(-60))
}

/// 흡수 세션(다른 맥이 연 세션)은 내 무입력으로 마감하지 않는다. 그 사람은 지금도 일하고 있다.
@MainActor
@Test
func awayCloseSkippedForAdoptedSession() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = makeAwayStore(host: "away-adopted", now: now)
    armAwayStore(
        store,
        now: now,
        startedAt: now.addingTimeInterval(-8 * 3_600),
        localInput: now.addingTimeInterval(-5 * 3_600),
        remoteInput: nil
    )
    store.adoptedRemoteSession = true

    store.evaluateAwaySession(now: now)

    #expect(store.startedAt != nil)
}

/// 서버가 든 열린 세션이 내 세션이 아니면(찢어진 읽기·다른 맥의 세션) 그 판정 재료로 마감하지 않는다.
@MainActor
@Test
func awayCloseSkippedWhenServerSessionDiffers() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = makeAwayStore(host: "away-othersession", now: now)
    armAwayStore(
        store,
        now: now,
        startedAt: now.addingTimeInterval(-8 * 3_600),
        localInput: now.addingTimeInterval(-5 * 3_600),
        remoteInput: nil,
        serverSessionID: "40000000-0000-0000-0000-0000000000cc"
    )

    store.evaluateAwaySession(now: now)

    #expect(store.startedAt != nil)
}

/// 기준 시각이 세션 시작보다 이르면 마감하지 않는다(서버 백스톱의 `started_at <= last_input` 가드와 같은 조건).
/// 없으면 0초 세션이 만들어져 그 근무가 통째로 사라진다.
@MainActor
@Test
func awayCloseSkippedWhenLastInputPrecedesSessionStart() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = makeAwayStore(host: "away-beforestart", now: now)
    armAwayStore(
        store,
        now: now,
        startedAt: now.addingTimeInterval(-3 * 3_600),
        localInput: now.addingTimeInterval(-5 * 3_600),
        remoteInput: nil
    )

    store.evaluateAwaySession(now: now)

    #expect(store.startedAt != nil)
}

/// away 는 long_session 보다 **먼저** 평가된다(더 이른 시각 + 복원 가능한 사유).
/// 순서가 뒤집히면 같은 부재가 long_session 으로 기록되고 그 사유는 복원 대상이 아니다 = 시간이 영구 소실된다.
@MainActor
@Test
func awayEvaluationPrecedesLongSessionInWorkTick() throws {
    let code = strippingSwiftComments(
        try String(contentsOf: awaySourceURL("WorkTimerStore.swift"), encoding: .utf8)
    )
    let away = try #require(code.range(of: "evaluateAwaySession(now: now)"))
    let long = try #require(code.range(of: "evaluateLongSession(now: now)"))
    #expect(away.lowerBound < long.lowerBound)
}

/// 잠자기 마감 시각 = min(뚜껑 닫은 시각, 마지막 의미 있는 입력). 맥은 **항상 무입력 뒤에 잠들기 때문에**
/// 이 한 줄이 없으면 절전 설정 길이만큼 매번 덤이 붙는다.
@MainActor
@Test
func sleepCloseUsesEarlierOfLidAndLastInput() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let start = now.addingTimeInterval(-4 * 3_600)
    let lastInput = now.addingTimeInterval(-3 * 3_600)
    let lidClosed = now.addingTimeInterval(-2 * 3_600)

    let store = makeAwayStore(host: "sleep-accuracy", now: now)
    store.startedAt = start
    store.currentSessionID = WorkTimerStore.canonicalSessionID(awaySessionID)
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
    store.lastMeaningfulInputAt = lastInput
    store.handleSleep(at: lidClosed)

    store.handleWake(at: now)

    #expect(store.startedAt == nil)
    let stopped = store.pendingItems.last
    #expect(stopped?.endedAt == lastInput)
    #expect(stopped?.autoCloseReason == .sleep)
}

/// 입력 관측이 세션 시작보다 이르면 **시작 시각으로 클램프**한다 — 안 하면 duration 이 0이 되어 그 근무가 사라진다.
@MainActor
@Test
func sleepCloseClampsToSessionStart() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let start = now.addingTimeInterval(-2 * 3_600)
    let store = makeAwayStore(host: "sleep-clamp", now: now)
    store.startedAt = start
    store.currentSessionID = WorkTimerStore.canonicalSessionID(awaySessionID)
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
    store.lastMeaningfulInputAt = now.addingTimeInterval(-5 * 3_600)
    store.handleSleep(at: now.addingTimeInterval(-3_600))

    store.handleWake(at: now)

    #expect(store.pendingItems.last?.endedAt == start)
}

/// 입력 전진은 **단조 증가**이고, 화면 잠금/비콘솔에서는 전진하지 않는다
/// (잠그고 자러 간 사람은 잠근 시각에서 멈춘다 — 잠금 화면의 비밀번호 타이핑이 내 근무를 연장하면 안 된다).
@MainActor
@Test
func meaningfulInputAdvancesMonotonicallyAndStopsWhenLocked() {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var idle: TimeInterval = 10
    var usable = true
    let store = makeAwayStore(host: "input-advance", now: now)
    store.meaningfulIdleSeconds = { idle }
    store.inputSessionUsable = { usable }

    #expect(store.advanceMeaningfulInput(now: now) == now.addingTimeInterval(-10))

    // 뒤로 가는 관측(유휴가 더 길어짐)은 무시한다.
    idle = 600
    #expect(store.advanceMeaningfulInput(now: now) == now.addingTimeInterval(-10))

    // 잠금 중에는 전진하지 않는다.
    usable = false
    idle = 0
    now = now.addingTimeInterval(3_600)
    #expect(store.advanceMeaningfulInput(now: now) == now.addingTimeInterval(-3_610))

    // 잠금이 풀리면 다시 전진한다.
    usable = true
    #expect(store.advanceMeaningfulInput(now: now) == now)

    // 관측 자체가 없으면(이벤트 소스가 무한대를 준다) 아무 값도 세우지 않는다 —
    // distantPast 를 세우면 그 값이 '마지막 입력'으로 서버에 올라간다.
    let blind = makeAwayStore(host: "input-blind", now: now)
    blind.meaningfulIdleSeconds = { .infinity }
    #expect(blind.advanceMeaningfulInput(now: now) == nil)
    #expect(blind.lastMeaningfulInputAt == nil)
}

/// 근무 시작은 그 자체가 입력이다. 옛 관측이 남으면 새 세션의 판정 재료가 된다.
@MainActor
@Test
func startStampsMeaningfulInput() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = makeAwayStore(host: "input-on-start", now: now)
    store.lastMeaningfulInputAt = now.addingTimeInterval(-6 * 3_600)

    store.start(now: now)

    #expect(store.lastMeaningfulInputAt == now)
}

/// 하트비트는 **서버가 자리 비움 스키마를 갖고 있다고 확인된 뒤에만** last_input_at 을 싣는다.
/// 브루 배포가 db push 보다 먼저 나가는 창에서 이 컬럼을 보내면 하트비트가 400 이 되고,
/// 10분 뒤 서버가 살아 있는 세션을 방치로 마감한다.
@MainActor
@Test
func heartbeatCarriesLastInputOnlyOnSupportedServer() async {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    let legacyHost = "away-heartbeat-legacy"
    let legacy = makeAwayStore(host: legacyHost, now: now)
    legacy.startedAt = now.addingTimeInterval(-600)
    legacy.currentSessionID = WorkTimerStore.canonicalSessionID(awaySessionID)
    legacy.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
    legacy.awayServerSupported = false
    await legacy.sendHeartbeatIfWorking()
    #expect(!URLProtocolStub.bodyText(forHost: legacyHost).contains("last_input_at"))

    let newHost = "away-heartbeat-new"
    let modern = makeAwayStore(host: newHost, now: now)
    modern.startedAt = now.addingTimeInterval(-600)
    modern.currentSessionID = WorkTimerStore.canonicalSessionID(awaySessionID)
    modern.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
    modern.awayServerSupported = true
    await modern.sendHeartbeatIfWorking()
    let bodies = URLProtocolStub.bodies(forHost: newHost)
    // 두 곳(work_statuses 하트비트 + work_status_devices 기기 행)에 **같은 값**이 실린다.
    #expect(bodies.filter { $0.contains("last_input_at") }.count == 2)
}

/// 흡수 맥(다른 맥이 연 세션을 미러링)은 자기 기기 행에 **last_input_at 만** 쓴다.
/// session_id/last_seen_at 을 함께 보내면 그 행이 소유권 판정의 증거로 승격돼
/// "흡수 맥은 그 세션의 생존신호를 대신 보내지 않는다"는 계약이 깨진다(= 아무도 못 닫는 세션).
@MainActor
@Test
func adoptedMacReportsInputWithoutSessionOrPresence() async {
    let host = "away-adopted-input"
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = makeAwayStore(host: host, now: now)
    store.startedAt = now.addingTimeInterval(-600)
    store.currentSessionID = WorkTimerStore.canonicalSessionID(awaySessionID)
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
    store.adoptedRemoteSession = true
    store.awayServerSupported = true

    await store.sendHeartbeatIfWorking()

    let requests = URLProtocolStub.requests(forHost: host)
    #expect(requests.allSatisfy { $0.url?.path != "/rest/v1/work_statuses" })
    let bodies = URLProtocolStub.bodies(forHost: host)
    #expect(bodies.count == 1)
    let body = bodies.first ?? ""
    #expect(body.contains("last_input_at"))
    #expect(body.contains("device_id"))
    #expect(!body.contains("session_id"))
    #expect(!body.contains("last_seen_at"))
    #expect(!body.contains("opened_session"))
}

/// 자동 마감 사유가 **서버 PATCH 본문까지** 실제로 도달한다. 사유가 안 남으면 복원 RPC 가
/// not_restorable 로 거절해 그 사람은 시간을 되찾을 방법이 없다.
@MainActor
@Test
func autoCloseReasonReachesServerPatchBody() async {
    let host = "away-reason-patch"
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = makeAwayStore(host: host, now: now)
    armAwayStore(
        store,
        now: now,
        startedAt: now.addingTimeInterval(-8 * 3_600),
        localInput: now.addingTimeInterval(-3 * 3_600),
        remoteInput: nil
    )

    store.evaluateAwaySession(now: now)
    await store.retryPendingSync()

    let patched = zip(URLProtocolStub.requests(forHost: host), URLProtocolStub.bodies(forHost: host))
        .filter { $0.0.url?.path == "/rest/v1/work_sessions" && $0.0.httpMethod == "PATCH" }
        .map(\.1)
    #expect(patched.contains { $0.contains("\"auto_closed_reason\":\"away\"") })
}

/// **뚜껑 닫고 나간 사람의 유일한 구제 통로.** 뚜껑을 닫으면 서버 스캐빈저가 10분 뒤 그 세션을
/// 'abandoned' 로 먼저 마감하는데 그 사유는 복원 대상이 아니다 — 깨어난 클라가 사유를 'sleep' 으로
/// 정정하지 않으면 2파의 핵심 이득이 통째로 사라진다(docs/away-close.md 4절).
/// 마감 PATCH 가 0행(= 서버가 이미 닫아 뒀다)일 때만 이 정정이 나간다.
@MainActor
@Test
func sleepReasonIsCorrectedWhenServerClosedTheSessionFirst() async {
    let host = "away-sleep-correction"
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = makeAwayStore(host: host, now: now)
    store.startedAt = now.addingTimeInterval(-4 * 3_600)
    store.currentSessionID = WorkTimerStore.canonicalSessionID(awaySessionID)
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
    store.lastMeaningfulInputAt = now.addingTimeInterval(-3 * 3_600)
    store.handleSleep(at: now.addingTimeInterval(-2 * 3_600))
    store.handleWake(at: now)

    await store.retryPendingSync()

    let sessionPatches = zip(URLProtocolStub.requests(forHost: host), URLProtocolStub.bodies(forHost: host))
        .filter { $0.0.url?.path == "/rest/v1/work_sessions" && $0.0.httpMethod == "PATCH" }
    // ① ended_at 을 **더 이르게만** 당기는 정정(서버 값이 더 늦을 때만 닿도록 gt 필터를 건다).
    #expect(sessionPatches.contains {
        ($0.0.url?.query ?? "").contains("ended_at=gt.") && $0.1.contains("\"auto_closed_reason\":\"sleep\"")
    })
    // ② 서버 값이 이미 더 이르면 사유만 고친다(ended_at 은 손대지 않는다 — 늦추는 것은 위조다).
    #expect(sessionPatches.contains {
        ($0.0.url?.query ?? "").contains("ended_at=not.is.null") && !$0.1.contains("ended_at\":")
    })
}

/// 사용자가 직접 누른 종료는 사유를 남기지 않는다 — 요청 바이트가 v0.2.34 와 같아야 한다
/// (자동 마감과 수동 종료가 팀원 화면에서 구분되면 안 된다는 규약의 코드 쪽 반쪽).
@MainActor
@Test
func manualStopSendsNoAutoCloseColumns() async {
    let host = "away-manual-stop"
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = makeAwayStore(host: host, now: now)
    store.startedAt = now.addingTimeInterval(-3_600)
    store.currentSessionID = WorkTimerStore.canonicalSessionID(awaySessionID)
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)

    store.stop(now: now)
    await store.retryPendingSync()

    #expect(!URLProtocolStub.bodyText(forHost: host).contains("auto_closed"))
}

/// 복원 응답 어휘 전체를 고정한다. 모르는 status 를 성공으로 접으면 열리지도 않은 세션을 근무중으로 그린다.
@MainActor
@Test
func awayRestoreOutcomeMapsEveryDocumentedStatus() async {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://away-restore-map")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    func outcome(_ status: String, usedToday: Int? = nil, limit: Int? = nil, sessionId: String? = nil) async -> AwayRestoreOutcome {
        await service.awayRestoreOutcome(
            from: AwayRestoreResponse(
                status: status,
                sessionId: sessionId,
                startedAt: nil,
                reason: nil,
                restoredAt: nil,
                usedToday: usedToday,
                limit: limit,
                deletedOpenSessions: nil,
                endedAt: nil,
                windowSeconds: nil,
                ageSeconds: nil
            ),
            requestedSessionID: awaySessionID
        )
    }

    #expect(await outcome("ok", sessionId: awaySessionID) == .restored(sessionID: awaySessionID, startedAt: nil))
    // 두 번 누른 사람·두 번째 맥에게 오류를 보이지 않는다(서버가 멱등하게 성공으로 답한다).
    #expect(await outcome("already_open") == .restored(sessionID: awaySessionID, startedAt: nil))
    #expect(await outcome("expired") == .expired)
    #expect(await outcome("limit_reached", usedToday: 2, limit: 2) == .limitReached(usedToday: 2, limit: 2))
    #expect(await outcome("not_found") == .notRestorable(status: "not_found"))
    #expect(await outcome("not_restorable") == .notRestorable(status: "not_restorable"))
    #expect(await outcome("already_restored") == .notRestorable(status: "already_restored"))
    #expect(await outcome("not_member") == .notRestorable(status: "not_member"))
    #expect(await outcome("conflict") == .failed(status: "conflict"))
    #expect(await outcome("invalid") == .failed(status: "invalid"))
    #expect(await outcome("아무도 모르는 값") == .failed(status: "아무도 모르는 값"))
}

/// 복원 후 12시간 앵커는 **복원된 세션의 시작 시각**이다(복원 시각이 아니다).
/// 복원 시각으로 세우면 09:00 시작 → 13:00 마감 → 15:00 복원인 사람의 총 세션이 18시간이 되고
/// 12시간 안전장치가 복원 경로에서 통째로 무력화된다.
@MainActor
@Test
func restoreAnchorsLongSessionToRestoredStart() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let restoredStart = now.addingTimeInterval(-6 * 3_600)
    let closedEndedAt = now.addingTimeInterval(-3 * 3_600)
    let store = makeAwayStore(host: "away-restore-anchor", now: now)
    store.accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: now)
    store.accumulatedSeconds = 3 * 3_600

    store.applyRestoredAwaySession(
        sessionID: awaySessionID.uppercased(),
        startedAt: restoredStart,
        closedEndedAt: closedEndedAt
    )

    #expect(store.startedAt == restoredStart)
    #expect(store.longSessionAnchor == restoredStart)
    // 세션 ID 는 반드시 정규화(소문자)된다 — 대문자로 들고 있으면 다음 폴링이 내 세션을 남의 것으로 읽는다.
    #expect(store.currentSessionID == awaySessionID.lowercased())
    #expect(store.ownsCurrentSessionStrongly)
    #expect(!store.adoptedRemoteSession)
    // 마감이 누적에 더해 둔 그 세션의 오늘 몫을 도로 뺀다(안 빼면 같은 구간을 두 번 센다).
    #expect(store.accumulatedSeconds == 0)
    // 버튼을 누른 것 자체가 사람이 자리에 있다는 증거다 — 안 밀면 다음 틱이 방금 살린 세션을 다시 마감한다.
    #expect(store.lastMeaningfulInputAt == now)
    #expect(store.awayRestorable == nil)
    #expect(!store.awayRestorePromptPending)
}

/// 복귀(자동 시작)의 그 순간이 이 기능의 **유일한 도달 채널**이다. 복원 대상이 있으면 조용히 새 세션을
/// 열지 말고 물어야 한다. 만료된 대상으로는 묻지 않는다(창 판정은 서버 값으로만 한다).
@MainActor
@Test
func autoStartOffersRestoreOnlyWhileWindowIsOpen() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = makeAwayStore(host: "away-autostart-offer", now: now)
    store.awayStateOwnerUserID = awayUserID
    store.awayRestorable = AwayRestorableSession(
        sessionID: awaySessionID,
        startedAt: now.addingTimeInterval(-6 * 3_600),
        endedAt: now.addingTimeInterval(-3 * 3_600),
        autoClosedAt: now.addingTimeInterval(-3 * 3_600),
        reason: .away,
        expiresAt: now.addingTimeInterval(3 * 3_600),
        remainingSeconds: 3 * 3_600
    )

    #expect(store.offerAwayRestoreOnAutoStart(now: now))
    #expect(store.awayRestorePromptPending)

    // 창이 닫혔으면 묻지 않는다(그 세션은 이미 되살릴 수 없다).
    store.dismissAwayRestorePrompt()
    #expect(!store.offerAwayRestoreOnAutoStart(now: now.addingTimeInterval(4 * 3_600)))
    #expect(!store.awayRestorePromptPending)

    // 근무 중이면 물을 일이 없다(복원은 비근무 전용 — 진행 중 세션을 옛 세션으로 덮으면 안 된다).
    store.startedAt = now
    #expect(!store.offerAwayRestoreOnAutoStart(now: now))
}

/// 계정이 바뀌면 배너는 **스스로 침묵한다**. 로그아웃 경로가 이 스토어의 다른 파일에 있어
/// 그쪽이 away 상태 정리를 잊어도 남의 마감이 새 계정 화면에 뜨지 않는다.
@MainActor
@Test
func restorableBannerIsSilentForAnotherAccount() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = makeAwayStore(host: "away-owner-lock", now: now)
    store.awayStateOwnerUserID = awayUserID
    store.awayRestorable = AwayRestorableSession(
        sessionID: awaySessionID,
        startedAt: now.addingTimeInterval(-6 * 3_600),
        endedAt: now.addingTimeInterval(-3 * 3_600),
        autoClosedAt: now.addingTimeInterval(-3 * 3_600),
        reason: .away,
        expiresAt: now.addingTimeInterval(3 * 3_600),
        remainingSeconds: 3 * 3_600
    )
    #expect(store.restorableAwaySession != nil)

    store.session = SupabaseSession(accessToken: "t", refreshToken: nil, userID: "00000000-0000-0000-0000-0000000000ff")

    #expect(store.restorableAwaySession == nil)
    #expect(!store.offerAwayRestoreOnAutoStart(now: now))
}

/// away_sync 가 실패하면(구버전 서버·오프라인) **정책이 비워져 마감이 멈춘다**.
/// 마지막으로 본 임계를 계속 쓰는 쪽이 더 나쁘다 — 서버가 값을 바꿔도 옛 값으로 계속 끊고, 되돌릴 수단이 배포뿐이다.
@MainActor
@Test
func failedAwaySyncStopsClosingInsteadOfKeepingStalePolicy() async {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    // 이 호스트의 /rest/v1/* 는 전부 404 PGRST205 다(= 마이그레이션 미적용 서버).
    let store = makeAwayStore(host: "schema-missing", now: now)
    armAwayStore(
        store,
        now: now,
        startedAt: now.addingTimeInterval(-8 * 3_600),
        localInput: now.addingTimeInterval(-5 * 3_600),
        remoteInput: nil
    )

    await store.refreshAwayStateIfNeeded(now: now)

    #expect(store.awayPolicy == nil)
    #expect(store.awayOpenSession == nil)
    #expect(!store.awayServerSupported)
    store.evaluateAwaySession(now: now)
    #expect(store.startedAt != nil)
}

/// **팀 조회 select 에 last_input_at / auto_closed_reason 을 넣지 않는다**(docs/away-close.md 1·4절).
/// RLS 는 팀 범위라 요청하면 보인다 — 남의 마지막 키 입력 시각을 30초 해상도로 노출하는 것도,
/// 자동 마감과 수동 종료를 팀원이 구분하게 만드는 것도 이 앱이 하기로 한 일이 아니다. 규약으로만 막힌다.
@MainActor
@Test
func teamScopedSelectsNeverRequestInputOrCloseReason() throws {
    let code = strippingSwiftComments(
        try String(contentsOf: awaySourceURL("SupabaseWorkService.swift"), encoding: .utf8)
    )
    for select in code.components(separatedBy: "URLQueryItem(name: \"select\", value: \"").dropFirst() {
        let list = select.components(separatedBy: "\"").first ?? ""
        #expect(!list.contains("last_input_at"))
        #expect(!list.contains("auto_closed"))
    }
}

private func awaySourceURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)          // Tests/checkTests/WorkTimerStoreTests.swift
        .deletingLastPathComponent()          // Tests/checkTests
        .deletingLastPathComponent()          // Tests
        .deletingLastPathComponent()          // (repo root)
        .appendingPathComponent("Sources/check/\(name)")
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다(하우스 규칙 — 안 걷어내면 설명을 지워야 초록이 된다).
/// 문자열 리터럴 안의 `//` 는 남긴다.
private func strippingSwiftComments(_ source: String) -> String {
    var result = ""
    var inString = false
    var inLineComment = false
    var inBlockComment = false
    var previous: Character = " "
    let characters = Array(source)
    var index = 0
    while index < characters.count {
        let c = characters[index]
        let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
        if inLineComment {
            if c == "\n" { inLineComment = false; result.append(c) }
        } else if inBlockComment {
            if c == "*", next == "/" { inBlockComment = false; index += 1 }
        } else if inString {
            if c == "\"", previous != "\\" { inString = false }
            result.append(c)
        } else if c == "/", next == "/" {
            inLineComment = true; index += 1
        } else if c == "/", next == "*" {
            inBlockComment = true; index += 1
        } else if c == "\"" {
            inString = true; result.append(c)
        } else {
            result.append(c)
        }
        previous = c
        index += 1
    }
    return result
}
