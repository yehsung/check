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
    store.teamMembers = [worked(41 * 3_600)]
    store.detectTeamReactions()
    #expect(events.filter { $0 == .milestone }.count == 1)

    // 완료 유지 상태에선 재축하하지 않는다.
    store.detectTeamReactions()
    #expect(events.filter { $0 == .milestone }.count == 1)
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
            $0.url?.path == "/rest/v1/token_usage_monthly" && $0.httpMethod == "POST"
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
func sendPokeOkMirrorsCooldownWindow() async {
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
    // 쿨타임 잔여는 대략 60초(방금 now+60 미러). 표시 계산이 창 안에 든다.
    let remaining = store.pokeCooldownRemaining(for: "target", now: Date())
    #expect(remaining >= 58 && remaining <= 60)
}

@MainActor
@Test
func sendPokeCooldownResponseMirrorsRetryAfter() async {
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
    // 서버가 준 retry_after_seconds(25) 만큼 쿨타임을 미러링한다.
    let remaining = store.pokeCooldownRemaining(for: "target", now: Date())
    #expect(remaining >= 23 && remaining <= 25)
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
