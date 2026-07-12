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
    // 가입은 이제 계정만 만든다 — 팀 메타데이터(team_id)는 보내지 않는다(트리거가 팀을 만들지 않으므로).
    #expect(!bodyText.contains("\"team_id\""))
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

// MARK: - ACD-F2: startWork 멱등화(큐 재재생 409 소멸)

@Test
func startWorkPostsIdempotentlyWithOnConflictAndIgnoreDuplicates() async throws {
    // 재현: 큐 재재생으로 이미 닫힌 동일 id 세션에 다시 POST 되면 유니크 위반(409)이 났다.
    // work_sessions POST 는 on_conflict=id 쿼리 + Prefer: resolution=ignore-duplicates 로 멱등해야
    // 이미 있는 id 를 서버가 조용히 무시한다(stopWork fallback 과 동일 패턴).
    let testHost = "start-work-idempotent-test"
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

    let sessionPost = try #require(URLProtocolStub.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/work_sessions" && $0.httpMethod == "POST"
    })
    let postURL = try #require(sessionPost.url)
    let queryItems = try #require(URLComponents(url: postURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(queryItems.contains(URLQueryItem(name: "on_conflict", value: "id")))
    let prefer = try #require(sessionPost.value(forHTTPHeaderField: "Prefer"))
    #expect(prefer.contains("resolution=ignore-duplicates"))
    #expect(prefer.contains("return=minimal"))
}

@Test
func fetchTeamStatusesIncludesCurrentAndWeeklyDurations() async throws {
    let testHost = "team-hours-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let statuses = try await service.fetchTeamStatuses(accessToken: "access-token", teamID: URLProtocolStub.stubTeamID)

    #expect(statuses.count == 1)
    #expect(statuses.first?.name == "영식")
    #expect(statuses.first?.status == .working)
    #expect(statuses.first?.currentSessionStartedAt != nil)
    #expect(statuses.first?.weeklyDurationSeconds == 7200)
    // C1: 활성·주간·상태 세 GET을 병렬 발사한다 — 두 종류의 세션 조회가 모두 나가야 한다(직렬→병렬, 회수 불변).
    let sessionRequests = URLProtocolStub.requests(forHost: testHost).filter {
        $0.url?.path == "/rest/v1/work_sessions"
    }
    #expect(sessionRequests.contains { $0.url?.query?.contains("ended_at=is.null") == true })
    #expect(sessionRequests.contains { $0.url?.query?.contains("ended_at=not.is.null") == true })
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

// MARK: - C4: 주간 라이브 클리핑(진행 세션의 주 경계 귀속)

@Test
func liveWeeklyDurationClipsCurrentSessionAtWeekStart() {
    // now = 월요일 01:00 KST. 세션은 일요일 23:00 KST 시작(주 경계 전 1시간 포함, 총 2시간 진행).
    // 이번 주 기여는 월요일 00:00 이후 1시간뿐이어야 한다(지난 주 1시간은 새 주로 새지 않는다).
    let iso = ISO8601DateFormatter()
    let now = iso.date(from: "2026-07-06T01:00:00+09:00")!
    let started = iso.date(from: "2026-07-05T23:00:00+09:00")!
    let member = TeamMemberStatus(
        id: "u", name: "n", status: .working, updatedAt: nil,
        currentSessionStartedAt: started, weeklyDurationSeconds: 0,
        lastSeenAt: now
    )
    #expect(member.liveWeeklyDurationSeconds(now: now) == 3_600)
}

@Test
func liveWeeklyDurationCountsFullSessionWhenWithinWeek() {
    // 주 경계를 넘지 않은 진행 세션은 클리핑 없이 전부 이번 주 기여로 센다.
    let iso = ISO8601DateFormatter()
    let now = iso.date(from: "2026-07-08T12:00:00+09:00")!   // 수요일
    let started = iso.date(from: "2026-07-08T10:00:00+09:00")! // 같은 날 2시간 전
    let member = TeamMemberStatus(
        id: "u", name: "n", status: .working, updatedAt: nil,
        currentSessionStartedAt: started, weeklyDurationSeconds: 100,
        lastSeenAt: now
    )
    #expect(member.liveWeeklyDurationSeconds(now: now) == 100 + 7_200)
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
func lookupTeamByCodePostsRPCWithAnonBearerAndNormalizes() async throws {
    let testHost = "lookup-code-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    // 소문자·공백 섞인 입력을 넣어도 정규화("X7K2M9Q4")된 코드만 서버로 나가야 한다.
    let preview = try await service.lookupTeamByCode(code: "x7k2 m9q4")

    #expect(preview == TeamJoinPreview(
        teamID: "10000000-0000-0000-0000-000000000001",
        name: "아잉팀",
        weeklyGoalHours: 40,
        memberCount: 3
    ))
    let rpcRequest = try #require(URLProtocolStub.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/rpc/lookup_team_by_code"
    })
    #expect(rpcRequest.httpMethod == "POST")
    // 가입 전에도 쓰이므로 accessToken 없이 anonKey 를 Bearer 로 사용한다.
    #expect(rpcRequest.value(forHTTPHeaderField: "Authorization") == "Bearer anon-test-key")
    // 전송 본문은 정규화된 코드여야 한다(대문자화 + 공백/하이픈 제거).
    #expect(URLProtocolStub.bodyText(forHost: testHost).contains(#""code":"X7K2M9Q4""#))
}

@Test
func lookupTeamByCodeReturnsNilOnMiss() async throws {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://lookup-code-miss")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let preview = try await service.lookupTeamByCode(code: "NOSUCHXX")

    #expect(preview == nil)
}

@Test
func joinTeamPostsRPCWithAccessTokenAndDecodesTeam() async throws {
    let testHost = "join-code-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let joined = try await service.joinTeam(accessToken: "access-token", code: "aing-team")

    #expect(joined?.teamID == "10000000-0000-0000-0000-000000000001")
    #expect(joined?.goalHours == 40)
    let rpcRequest = try #require(URLProtocolStub.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/rpc/join_team"
    })
    #expect(rpcRequest.httpMethod == "POST")
    // 로그인 토큰을 Bearer 로 사용한다(합류는 authenticated 전용).
    #expect(rpcRequest.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
    #expect(URLProtocolStub.bodyText(forHost: testHost).contains(#""code":"AINGTEAM""#))
}

@Test
func joinTeamReturnsNilOnMiss() async throws {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://join-code-miss")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let joined = try await service.joinTeam(accessToken: "access-token", code: "NOSUCHXX")

    #expect(joined == nil)
}

@Test
func createTeamPostsRPCAndDecodesInviteCode() async throws {
    let testHost = "create-team-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let created = try await service.createTeam(accessToken: "access-token", name: "새로운 팀", goalHours: 50)

    #expect(created.teamID == "10000000-0000-0000-0000-000000000001")
    #expect(created.inviteCode == "X7K2M9Q4")
    #expect(created.goalHours == 50)
    let rpcRequest = try #require(URLProtocolStub.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/rpc/create_team"
    })
    #expect(rpcRequest.httpMethod == "POST")
    #expect(rpcRequest.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
    // 팀명/목표시간이 snake_case 본문으로 전송되어야 한다.
    let bodyText = URLProtocolStub.bodyText(forHost: testHost)
    #expect(bodyText.contains("\"team_name\":\"새로운 팀\""))
    #expect(bodyText.contains("\"goal_hours\":50"))
}

@Test
func fetchMyInviteCodeDecodesCodeForOwner() async throws {
    let testHost = "invite-code-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let code = try await service.fetchMyInviteCode(accessToken: "access-token")

    #expect(code == "AINGTEAM")
    let rpcRequest = try #require(URLProtocolStub.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/rpc/my_team_invite_code"
    })
    #expect(rpcRequest.httpMethod == "POST")
    #expect(rpcRequest.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
}

@Test
func fetchMyInviteCodeReturnsNilForNonOwner() async throws {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://invite-code-member")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let code = try await service.fetchMyInviteCode(accessToken: "access-token")

    #expect(code == nil)
}

// MARK: - K: 팀 리그

@Test
func fetchTeamLeaderboardDecodesEntriesWithBearer() async throws {
    let testHost = "leaderboard-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let entries = try await service.fetchTeamLeaderboard(accessToken: "access-token")

    // 3팀 픽스처가 그대로 디코드된다(서비스는 정렬하지 않고 원본 순서를 유지 — 정렬은 store 책임).
    #expect(entries.count == 3)
    let myTeam = try #require(entries.first { $0.id == URLProtocolStub.stubTeamID })
    #expect(myTeam.name == "아잉팀")
    #expect(myTeam.weeklyGoalHours == 40)
    #expect(myTeam.totalSeconds == 72000)
    #expect(myTeam.workingCount == 3)
    // member_count 도 디코드되어 1인당 평균(총합 ÷ 인원)이 계산된다.
    #expect(myTeam.memberCount == 3)
    #expect(myTeam.averageSeconds == 24000)

    let rpcRequest = try #require(URLProtocolStub.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/rpc/team_weekly_leaderboard"
    })
    #expect(rpcRequest.httpMethod == "POST")
    // 로그인 토큰을 Bearer 로 사용해 호출한다(anon 이 아니라 authenticated 전용 RPC).
    #expect(rpcRequest.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
}

@Test
func teamLeaderboardRowToleratesMissingMemberCount() throws {
    // member_count 를 아직 안 내려주는 구버전 RPC(마이그레이션 미적용) 응답도 디코드되어야 한다.
    // 누락 시 memberCount 는 0 으로 폴백하고 평균은 0명 가드로 0 이 된다(라이브 호환).
    let json = Data(#"[{"team_id":"t","team_name":"레거시","weekly_goal_hours":60,"total_seconds":72000,"working_count":1}]"#.utf8)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let rows = try decoder.decode([TeamLeaderboardRow].self, from: json)
    let row = try #require(rows.first)
    #expect(row.memberCount == nil)
    let entry = TeamLeaderboardEntry(id: row.teamId, name: row.teamName, weeklyGoalHours: row.weeklyGoalHours, totalSeconds: row.totalSeconds, workingCount: row.workingCount, memberCount: row.memberCount ?? 0)
    #expect(entry.memberCount == 0)
    #expect(entry.averageSeconds == 0)
    #expect(entry.goal.progress == 0)
}

@Test
func leaderboardEntryAveragesTotalOverMembersAndGuardsZero() {
    // 1인당 평균 = 총합 ÷ 인원. 게이지 분자·% 는 총합이 아니라 평균 ÷ 1인당 목표다.
    let entry = TeamLeaderboardEntry(id: "t", name: "팀", weeklyGoalHours: 40, totalSeconds: 72000, workingCount: 2, memberCount: 3)
    #expect(entry.averageSeconds == 24000) // 72000/3 = 6시간 40분
    #expect(entry.goal.goalSeconds == 40 * 3600)
    #expect(entry.goal.workedSeconds == 24000)
    #expect(abs(entry.goal.progress - 24000.0 / (40.0 * 3600.0)) < 1e-9) // ≈ 0.1667

    // 인원 0(가드): 0 으로 나누지 않고 평균·진행률 모두 0.
    let empty = TeamLeaderboardEntry(id: "e", name: "빈팀", weeklyGoalHours: 60, totalSeconds: 90000, workingCount: 0, memberCount: 0)
    #expect(empty.averageSeconds == 0)
    #expect(empty.goal.progress == 0)
}

@Test
func leaderboardSortsByAverageDescendingTieByName() {
    // 정렬은 총합이 아니라 1인당 평균 내림차순, 동률이면 이름 오름차순.
    let entries = [
        TeamLeaderboardEntry(id: "a", name: "가팀", weeklyGoalHours: 60, totalSeconds: 90000, workingCount: 0, memberCount: 6), // 평균 15000
        TeamLeaderboardEntry(id: "b", name: "나팀", weeklyGoalHours: 60, totalSeconds: 36000, workingCount: 0, memberCount: 1), // 평균 36000
        TeamLeaderboardEntry(id: "c", name: "다팀", weeklyGoalHours: 60, totalSeconds: 30000, workingCount: 0, memberCount: 2)  // 평균 15000 (가팀과 동률)
    ]
    let sorted = entries.sortedByAverageDescending()
    // 36000 먼저, 그 다음 동률 15000 은 이름순(가팀 < 다팀). 총합 1위(가팀 90000)가 평균으로는 아래로 내려간다.
    #expect(sorted.map(\.id) == ["b", "a", "c"])
}

@Test
func memberMeetsWeeklyGoalWhenLiveWeeklyReachesGoal() {
    // 멤버 행 ✓ 노출 조건 = 라이브 주간 누적이 1인당 목표 이상.
    let now = Date()
    let goal = 40 * 3600
    let met = TeamMemberStatus(id: "1", name: "달성", status: .offWork, updatedAt: nil, currentSessionStartedAt: nil, weeklyDurationSeconds: 40 * 3600)
    #expect(met.hasMetWeeklyGoal(goalSeconds: goal, now: now))
    let below = TeamMemberStatus(id: "2", name: "미달", status: .offWork, updatedAt: nil, currentSessionStartedAt: nil, weeklyDurationSeconds: 40 * 3600 - 1)
    #expect(!below.hasMetWeeklyGoal(goalSeconds: goal, now: now))
    // 근무중이면 현재 세션분까지 더한 라이브 주간으로 판정한다(39.5h + 1h ≥ 40h).
    let working = TeamMemberStatus(id: "3", name: "근무중", status: .working, updatedAt: nil, currentSessionStartedAt: now.addingTimeInterval(-3600), weeklyDurationSeconds: 40 * 3600 - 1800)
    #expect(working.hasMetWeeklyGoal(goalSeconds: goal, now: now))
    // 목표 0(비정상)이면 항상 거짓 — 0 이상으로 잘못 참이 되지 않게 가드한다.
    #expect(!met.hasMetWeeklyGoal(goalSeconds: 0, now: now))
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
    #expect(membership?.teamName == "아잉팀")
    // 임베드된 teams.weekly_goal_hours 를 같은 쿼리로 함께 읽어 온다.
    #expect(membership?.goalHours == 40)
    // 역할(role)도 같은 쿼리로 함께 읽어 온다(owner 판정 → 참여코드 로드에 쓴다).
    #expect(membership?.role == "member")
    let request = try #require(URLProtocolStub.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/memberships"
    })
    #expect(request.url?.query?.contains("user_id=eq.00000000-0000-0000-0000-000000000002") == true)
    // select 가 role, teams(name,weekly_goal_hours)로 확장되어야 한다.
    #expect(request.url?.query?.contains("weekly_goal_hours") == true)
    #expect(request.url?.query?.contains("role") == true)
}

@Test
func fetchOwnMembershipFallsBackToDefaultGoalWhenFieldMissing() async throws {
    let testHost = "membership-no-goal-test"
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
    // weekly_goal_hours 가 누락된 팀은 기본 목표(60시간)로 폴백한다.
    #expect(membership?.goalHours == TeamWeeklyGoal.defaultGoalHours)
    #expect(membership?.goalHours == 60)
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
