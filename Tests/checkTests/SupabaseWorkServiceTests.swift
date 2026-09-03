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

    // 픽스처와 같은 고정 기준시각을 주입한다 — 벽시계를 쓰면 KST 월요일 00~02시에 주 클리핑으로 0이 된다.
    let statuses = try await service.fetchTeamStatuses(
        accessToken: "access-token",
        teamID: URLProtocolStub.stubTeamID,
        now: URLProtocolStub.weeklyFixtureNow
    )

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
func heartbeatKeepsTheLegacyStatusBodyByteIdenticalAndWritesDeviceClaimSeparately() async throws {
    // **하위호환 제1원칙의 단일 고정점.** work_statuses 는 프로덕션에 아직 살아 있는 v0.2.10 클라가 쓰는 표다.
    // 이번 수리로 기기 식별자를 **그 본문에 끼워 넣었다면** 두 가지가 동시에 깨졌다:
    //   (1) 구버전이 device 를 안 보내므로 내가 써 둔 값이 그대로 눌러앉아 서버가 "이 맥이 소유"라고 거짓말하고,
    //   (2) 폴링 직전에 내가 매번 덮어써 남의 흔적이 지워지는 문제(= 규칙이 죽는 진짜 원인)는 그대로 남는다.
    // 그래서 기기 주장은 **다른 표·다른 요청**으로 나가고, 이 본문의 필드 집합은 한 글자도 바뀌지 않는다.
    let testHost = "status-body-contract"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    // 스토어의 하트비트 한 주기가 서비스에 내리는 두 호출(sendHeartbeatIfWorking 과 같은 순서).
    try await service.heartbeat(
        accessToken: "access-token",
        teamID: URLProtocolStub.stubTeamID,
        userID: "00000000-0000-0000-0000-000000000002",
        sessionID: "30000000-0000-0000-0000-000000000001"
    )
    try await service.upsertStatusDevice(
        accessToken: "access-token",
        teamID: URLProtocolStub.stubTeamID,
        userID: "00000000-0000-0000-0000-000000000002",
        deviceID: "THIS-MAC",
        sessionID: "30000000-0000-0000-0000-000000000001",
        openedSession: true
    )

    let paired = zip(URLProtocolStub.requests(forHost: testHost), URLProtocolStub.bodies(forHost: testHost))
    let statusBody = try #require(paired.first { $0.0.url?.path == "/rest/v1/work_statuses" }?.1)
    let json = try #require(
        try JSONSerialization.jsonObject(with: Data(statusBody.utf8)) as? [String: Any]
    )
    // 필드 집합이 v0.2.10 이 보내던 그대로다 — 하나라도 늘면 구버전과 같은 행을 공유할 수 없게 된다.
    #expect(
        Set(json.keys) == ["team_id", "user_id", "status", "active_session_id", "last_seen_at", "updated_at"]
    )
    #expect(!statusBody.contains("device"))

    // 기기 주장은 별도 표로 나가고, 충돌 키에 device_id 가 들어가야 맥 2대가 서로의 행을 덮지 않는다.
    let claim = try #require(URLProtocolStub.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/work_status_devices" && $0.httpMethod == "POST"
    })
    #expect(claim.url?.query?.contains("on_conflict=team_id,user_id,device_id") == true)
    // 주장 강도(이 맥이 세션을 직접 열었는가)는 **반드시 본문에 실린다**. 빠지면 PostgREST
    // merge-duplicates 가 그 컬럼을 건드리지 않아 옛 값이 눌러앉고, 상대 맥은 낡은 강도로 반납을 판정한다.
    let claimBody = try #require(paired.first { $0.0.url?.path == "/rest/v1/work_status_devices" }?.1)
    #expect(claimBody.contains(#""opened_session":true"#))
}

@Test
func fetchTeamStatusesAttachesDeviceClaimsToTheMatchingMember() async throws {
    // 기기별 소유 주장(work_status_devices)이 팀 상태 행에 결합돼야 반납 규칙이 볼 것이 생긴다.
    // 결합이 조용히 끊기면 규칙은 컴파일도 되고 테스트도 통과하는데 프로덕션에서만 영원히 침묵한다.
    let testHost = "device-claim-join-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let members = try await service.fetchTeamStatuses(
        accessToken: "access-token",
        teamID: URLProtocolStub.stubTeamID
    )

    let mine = try #require(members.first { $0.id == "00000000-0000-0000-0000-000000000002" })
    let claim = try #require(mine.deviceClaims.first)
    #expect(mine.deviceClaims.count == 1)
    #expect(claim.deviceID == "AAAA-OTHER-MAC")
    // 세션 ID 가 함께 와야 '남의 맥이 살아 있다'와 '남의 맥이 **내 세션에** 살아 있다'를 가를 수 있다.
    #expect(claim.sessionID == "30000000-0000-0000-0000-000000000001")
    // 소수초가 붙는 timestamptz 도 읽혀야 한다(parseDate 경유 — 여기서 nil 이 되면 '전진' 판정이 통째로 죽는다).
    #expect(claim.lastSeenAt != nil)
    // 주장 강도도 함께 와야 한다. 이 결합이 끊기면 모든 주장이 '약함'으로 읽혀 반납이 다시 사전식
    // device_id 동전 던지기로 되돌아간다(= 절반의 배치에서 진짜 소유자가 물러난다).
    #expect(claim.openedSession)

    // 조회 select 에 opened_session 이 들어가야 서버가 그 컬럼을 돌려준다(빠지면 항상 nil→약함이 된다).
    let selectItem = try #require(
        URLComponents(url: (URLProtocolStub.requests(forHost: testHost).first {
            $0.url?.path == "/rest/v1/work_status_devices"
        })!.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "select" }
    )
    #expect(selectItem.value?.contains("opened_session") == true)

    // 조회는 팀 범위 GET 한 건이다(같은 계정의 **다른 맥** 행을 봐야 하므로 자기 행만으로는 부족하다).
    let deviceRequest = try #require(URLProtocolStub.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/work_status_devices"
    })
    #expect(deviceRequest.httpMethod == "GET")
    let items = try #require(URLComponents(url: deviceRequest.url!, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(items.contains(URLQueryItem(name: "team_id", value: "eq.\(URLProtocolStub.stubTeamID)")))
}

@Test
func deviceClaimWithoutOpenedSessionColumnDecodesAsWeak() async throws {
    // 컬럼이 아직 없는 서버(마이그레이션 적용 전/중)는 이 키를 아예 돌려주지 않는다. non-optional 로 받았다면
    // **행 전체가 디코드 실패**로 사라져 기기 주장이 통째로 없어지고, 반납 규칙이 컴파일도 되고 테스트도
    // 통과하면서 프로덕션에서만 영원히 침묵한다. 없으면 '모른다' = 약함으로 읽는 것이 유일하게 안전한 해석이다.
    let testHost = "legacy-device-claim-no-column"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let members = try await service.fetchTeamStatuses(
        accessToken: "access-token",
        teamID: URLProtocolStub.stubTeamID
    )

    let mine = try #require(members.first { $0.id == "00000000-0000-0000-0000-000000000002" })
    let claim = try #require(mine.deviceClaims.first)
    #expect(claim.deviceID == "AAAA-OTHER-MAC")
    #expect(!claim.openedSession)
}

@Test
func missingDeviceTableDoesNotBreakTeamStatusPolling() async throws {
    // **하위호환의 핵심.** 이 릴리스의 마이그레이션이 아직 적용되지 않은 서버에서 work_status_devices 는
    // 404(PGRST205)다. 그 실패가 팀 상태 폴링 전체를 던지면 팀 목록·내 세션 복구·원격 종료 반영이 통째로
    // 멈춰, 새 기능 하나를 위해 앱의 심장을 서버 배포 순서에 인질로 잡게 된다.
    // 그래서 이 조회의 실패만은 삼키고 '주장 없음 = 판정 불가'로 떨어뜨린다(소유권은 백스톱 7분이 맡는다).
    let testHost = "status-device-table-missing"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let members = try await service.fetchTeamStatuses(
        accessToken: "access-token",
        teamID: URLProtocolStub.stubTeamID
    )

    // 폴링은 멀쩡하다 — 팀 행도, 진행 세션도 그대로 온다.
    let mine = try #require(members.first { $0.id == "00000000-0000-0000-0000-000000000002" })
    #expect(mine.status == .working)
    #expect(mine.currentSessionStartedAt != nil)
    // 다만 주장은 비어 있다. **빈 배열은 '다른 맥 없음'이 아니라 '모른다'** 다.
    #expect(mine.deviceClaims.isEmpty)
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

// MARK: - B1: 리그 0시간 팀 숨김 (filteredForDisplay)

@Test
func filteredForDisplayHidesZeroHourOtherTeams() {
    // 0시간 타팀은 리그에서 숨긴다. 근무한 팀만 남고 정렬(1인당 평균 내림차순)은 그대로.
    let entries = [
        TeamLeaderboardEntry(id: "a", name: "가팀", weeklyGoalHours: 60, totalSeconds: 0, workingCount: 0, memberCount: 3),
        TeamLeaderboardEntry(id: "b", name: "나팀", weeklyGoalHours: 60, totalSeconds: 36000, workingCount: 1, memberCount: 1),
        TeamLeaderboardEntry(id: "c", name: "다팀", weeklyGoalHours: 60, totalSeconds: 30000, workingCount: 0, memberCount: 2)
    ]
    let shown = entries.filteredForDisplay(myTeamID: nil)
    // 0시간 가팀은 빠지고, 평균 내림차순(나팀 36000 > 다팀 15000)으로 정렬된다.
    #expect(shown.map(\.id) == ["b", "c"])
}

@Test
func filteredForDisplayKeepsMyTeamEvenAtZeroHours() {
    // 내 팀은 0시간이어도 리그에 유지한다(내 팀이 사라지는 혼란 방지). 0시간 타팀만 숨긴다.
    let entries = [
        TeamLeaderboardEntry(id: "mine", name: "우리팀", weeklyGoalHours: 60, totalSeconds: 0, workingCount: 0, memberCount: 3),
        TeamLeaderboardEntry(id: "other", name: "남팀", weeklyGoalHours: 60, totalSeconds: 0, workingCount: 0, memberCount: 2),
        TeamLeaderboardEntry(id: "busy", name: "일하는팀", weeklyGoalHours: 60, totalSeconds: 36000, workingCount: 1, memberCount: 1)
    ]
    let shown = entries.filteredForDisplay(myTeamID: "mine")
    // 0시간 남팀은 빠지고, 0시간이어도 내 팀은 남는다. 정렬: 일하는팀(36000) > 우리팀(0).
    #expect(shown.map(\.id) == ["busy", "mine"])
}

@Test
func filteredForDisplayWithAllZeroKeepsOnlyMyTeamAndDropsAllWhenTeamless() {
    // 전부 0: 내 팀만 남는다. 무소속(myTeamID nil)이면 전부 숨겨 빈 배열.
    let entries = [
        TeamLeaderboardEntry(id: "mine", name: "우리팀", weeklyGoalHours: 60, totalSeconds: 0, workingCount: 0, memberCount: 3),
        TeamLeaderboardEntry(id: "other", name: "남팀", weeklyGoalHours: 60, totalSeconds: 0, workingCount: 0, memberCount: 2)
    ]
    #expect(entries.filteredForDisplay(myTeamID: "mine").map(\.id) == ["mine"])
    #expect(entries.filteredForDisplay(myTeamID: nil).isEmpty)
}

@Test
func filteredForDisplayOnEmptyReturnsEmpty() {
    let entries: [TeamLeaderboardEntry] = []
    #expect(entries.filteredForDisplay(myTeamID: "mine").isEmpty)
    #expect(entries.filteredForDisplay(myTeamID: nil).isEmpty)
}

// MARK: - B3: 팀 주간 목표 수정 (set_team_weekly_goal RPC)

@Test
func setTeamWeeklyGoalPostsRPCWithBearerAndDecodesNewGoal() async throws {
    let testHost = "set-goal-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: GoalRPCURLProtocol.session()
    )

    let newGoal = try await service.setTeamWeeklyGoal(accessToken: "access-token", goalHours: 37)

    // 서버가 반영한 새 목표시간(에코)이 그대로 디코드된다.
    #expect(newGoal == 37)
    let rpcRequest = try #require(GoalRPCURLProtocol.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/rpc/set_team_weekly_goal"
    })
    #expect(rpcRequest.httpMethod == "POST")
    // 로그인 토큰을 Bearer 로 사용한다(authenticated 전용 RPC).
    #expect(rpcRequest.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
    // 목표시간이 snake_case 본문(goal_hours)으로 전송된다.
    #expect(GoalRPCURLProtocol.bodyText(forHost: testHost).contains(#""goal_hours":37"#))
}

@Test
func memberMeetsWeeklyGoalWhenLiveWeeklyReachesGoal() {
    // 멤버 행 ✓ 노출 조건 = 라이브 주간 누적이 1인당 목표 이상.
    // 기준시각은 주 한복판(KST 화요일 낮)으로 고정한다 — 벽시계를 쓰면 KST 월요일 00~01시에 진행 세션이
    // 주 시작으로 클리핑돼 '근무중 1시간'이 성립하지 않아 시각 의존 실패가 난다.
    let now = URLProtocolStub.weeklyFixtureNow
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
    // 다중 소속 시 '주 팀' 선택을 서버 함수와 통일: joined_at 먼저, team_id 로 타이브레이크(콤마는 인코딩될 수 있어 조각으로 검사).
    #expect(request.url?.query?.contains("order=joined_at.asc") == true)
    #expect(request.url?.query?.contains("team_id.asc") == true)
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

// MARK: - 방치 세션 서버 자동 마감 RPC

// close_abandoned_work_sessions RPC 는 스칼라 int 를 반환하므로 본문에 숫자 하나만 온다.
// 트랙 소유의 URLProtocolStub.swift 를 건드리지 않도록 스칼라 응답 전용 스텁을 여기서 정의한다.
final class RPCScalarURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var responseBody = "0"

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.append(request)
        let data = Data(Self.responseBody.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RPCScalarURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func requests(forHost host: String) -> [URLRequest] {
        requests.filter { $0.url?.host == host }
    }
}

// set_team_weekly_goal RPC 는 [{"weekly_goal_hours": N}] 배열을 반환한다. URLProtocolStub(트랙 A 소유)이
// 이 경로를 다루지 않으므로(빈 200 → 디코드 실패), 요청 goal_hours 를 그대로 에코하는 전용 스텁을 여기 둔다.
// host 에 "fail" 이 들어가면 500 을 돌려 실패 경로를 재현한다(전역 mutable config 없이 host 로만 분기).
final class GoalRPCURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodiesByHost: [String: [String]] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let bodyText = Self.bodyText(from: request)
        Self.requests.append(request)
        Self.bodiesByHost[host, default: []].append(bodyText)

        let (statusCode, data) = Self.response(host: host, bodyText: bodyText)
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

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GoalRPCURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func requests(forHost host: String) -> [URLRequest] {
        requests.filter { $0.url?.host == host }
    }

    static func bodyText(forHost host: String) -> String {
        bodiesByHost[host, default: []].joined(separator: "\n")
    }

    private static func response(host: String, bodyText: String) -> (Int, Data) {
        if host.contains("fail") {
            // 본문 없는 5xx(Supabase 일시 장애 톤) → serviceError 가 .invalidResponse 로 매핑 → authMessage 는 fallback 사용.
            return (500, Data())
        }
        // 요청 본문의 goal_hours 를 그대로 weekly_goal_hours 로 에코한다(서버 검증·반영을 모사).
        let goal = parseGoalHours(from: bodyText) ?? 37
        return (200, Data("[{\"weekly_goal_hours\": \(goal)}]".utf8))
    }

    private static func parseGoalHours(from bodyText: String) -> Int? {
        guard let data = bodyText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object["goal_hours"] as? Int
    }

    private static func bodyText(from request: URLRequest) -> String {
        if let body = request.httpBody {
            return String(decoding: body, as: UTF8.self)
        }
        guard let stream = request.httpBodyStream else {
            return ""
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

@Test
func closeAbandonedSessionsPostsRPCWithBearerAndDecodesCount() async throws {
    let testHost = "close-abandoned-test"
    RPCScalarURLProtocol.responseBody = "3"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: RPCScalarURLProtocol.session()
    )

    let closed = try await service.closeAbandonedSessions(accessToken: "access-token")

    // 서버가 돌려준 마감 건수(스칼라 int)가 그대로 디코드된다.
    #expect(closed == 3)
    let rpcRequest = try #require(RPCScalarURLProtocol.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/rpc/close_abandoned_work_sessions"
    })
    #expect(rpcRequest.httpMethod == "POST")
    // 로그인 토큰을 Bearer 로 사용한다(authenticated 전용 RPC — 클라 스캐빈저 폴백).
    #expect(rpcRequest.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
}

// MARK: - D2: 팀원 이번 달 AI 토큰 보드 (upsert / fetch / 결합·정렬 / 월 키)

@Test
func upsertTokenUsagePostsMergeDuplicatesWithSnakeCasePayload() async throws {
    let testHost = "token-upsert-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let usage = TokenUsageMonthly(
        month: "2026-07",
        claudeInput: 11, claudeOutput: 22, claudeCacheRead: 33, claudeCacheCreation: 44,
        codexInput: 55, codexOutput: 66,
        todayTotal: 77, todayDate: "2026-07-14"
    )
    try await service.upsertTokenUsage(
        accessToken: "access-token",
        userID: "00000000-0000-0000-0000-000000000002",
        usage: usage,
        deviceID: "mac-studio-1"
    )

    let post = try #require(URLProtocolStub.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/token_usage_device_monthly" && $0.httpMethod == "POST"
    })
    // 이 메서드는 새 표만 담당한다 — 옛 표 갱신은 별도 upsertLegacyTokenUsage 의 몫이라 여기서 섞이면 안 된다
    // (스키마가 아직 없어도 옛 표 갱신은 성공해야 하므로 두 요청은 분리돼 있어야 한다).
    #expect(!URLProtocolStub.requests(forHost: testHost).contains { $0.url?.path == "/rest/v1/token_usage_monthly" })
    // on_conflict=user_id,month,device_id — 기기별 행이라 다른 맥의 행을 덮어쓰지 않는다(합산은 서버 보드 몫).
    let postURL = try #require(post.url)
    let queryItems = try #require(URLComponents(url: postURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(queryItems.contains(URLQueryItem(name: "on_conflict", value: "user_id,month,device_id")))
    #expect(!queryItems.contains(URLQueryItem(name: "on_conflict", value: "user_id,month")))
    let prefer = try #require(post.value(forHTTPHeaderField: "Prefer"))
    #expect(prefer.contains("resolution=merge-duplicates"))
    #expect(prefer.contains("return=minimal"))

    let bodyText = URLProtocolStub.bodyText(forHost: testHost)
    // snake_case 인코딩 + month + total(=6필드 합 231).
    #expect(bodyText.contains("\"user_id\":\"00000000-0000-0000-0000-000000000002\""))
    #expect(bodyText.contains("\"month\":\"2026-07\""))
    #expect(bodyText.contains("\"device_id\":\"mac-studio-1\""))
    #expect(bodyText.contains("\"claude_input\":11"))
    #expect(bodyText.contains("\"claude_output\":22"))
    #expect(bodyText.contains("\"claude_cache_read\":33"))
    #expect(bodyText.contains("\"claude_cache_creation\":44"))
    #expect(bodyText.contains("\"codex_input\":55"))
    #expect(bodyText.contains("\"codex_output\":66"))
    #expect(bodyText.contains("\"total\":231"))
    // 오늘분(오늘 +N 표시용)도 snake_case 로 함께 올라간다.
    #expect(bodyText.contains("\"today_total\":77"))
    #expect(bodyText.contains("\"today_date\":\"2026-07-14\""))
    // camelCase 가 새어 나가지 않는다.
    #expect(!bodyText.contains("\"claudeInput\""))
    #expect(!bodyText.contains("\"todayTotal\""))
    #expect(!bodyText.contains("\"deviceId\""))
}

@Test
func fetchLegacyTokenUsageTotalReadsOwnMonthRow() async throws {
    // 옛 표를 덮어쓰기 전 게이트가 읽는 요청. 아직 v0.2.10 인 다른 맥의 더 큰 누적치를 깎지 않으려면
    // 그 행의 현재 총량을 먼저 알아야 한다(행이 없으면 nil → 덮어쓰기 허용).
    let testHost = "legacy-bigger-total-read"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let total = try await service.fetchLegacyTokenUsageTotal(
        accessToken: "access-token",
        userID: "00000000-0000-0000-0000-000000000002",
        month: "2026-07"
    )
    #expect(total == 200_000_000)

    let get = try #require(URLProtocolStub.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/token_usage_monthly" && $0.httpMethod == "GET"
    })
    let getURL = try #require(get.url)
    let queryItems = try #require(URLComponents(url: getURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(queryItems.contains(URLQueryItem(name: "select", value: "total")))
    #expect(queryItems.contains(URLQueryItem(name: "user_id", value: "eq.00000000-0000-0000-0000-000000000002")))
    #expect(queryItems.contains(URLQueryItem(name: "month", value: "eq.2026-07")))

    // 행이 없는 서버(스텁 기본 픽스처 = 빈 목록)에서는 nil — 호출자는 그때 덮어써도 안전하다.
    let emptyHost = "legacy-empty-total-read"
    let emptyService = SupabaseWorkService(
        projectURL: URL(string: "http://\(emptyHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let missing = try await emptyService.fetchLegacyTokenUsageTotal(
        accessToken: "access-token",
        userID: "00000000-0000-0000-0000-000000000002",
        month: "2026-07"
    )
    #expect(missing == nil)
}

@Test
func upsertLegacyTokenUsageKeepsV0210RequestShape() async throws {
    // 옛 표는 마이그레이션 미적용 구간의 보루이자 v0.2.10 맥과 공유하는 행이라 v0.2.11 도 계속 쓰되,
    // 요청 모양은 v0.2.10 과 정확히 같아야 한다(키가 (user_id, month) 라 device_id 를 실으면 그 표의
    // 컬럼에 없어 400 이 난다). 언제 쓰는지(깎지 않을 때만)는 스토어 쪽 게이트가 정한다.
    let testHost = "token-legacy-upsert-test"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    let usage = TokenUsageMonthly(
        month: "2026-07",
        claudeInput: 11, claudeOutput: 22, claudeCacheRead: 33, claudeCacheCreation: 44,
        codexInput: 55, codexOutput: 66,
        todayTotal: 77, todayDate: "2026-07-14"
    )
    try await service.upsertLegacyTokenUsage(
        accessToken: "access-token",
        userID: "00000000-0000-0000-0000-000000000002",
        usage: usage
    )

    let post = try #require(URLProtocolStub.requests(forHost: testHost).first {
        $0.url?.path == "/rest/v1/token_usage_monthly" && $0.httpMethod == "POST"
    })
    let postURL = try #require(post.url)
    let queryItems = try #require(URLComponents(url: postURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(queryItems.contains(URLQueryItem(name: "on_conflict", value: "user_id,month")))
    let prefer = try #require(post.value(forHTTPHeaderField: "Prefer"))
    #expect(prefer.contains("resolution=merge-duplicates"))
    #expect(prefer.contains("return=minimal"))

    let bodyText = URLProtocolStub.bodyText(forHost: testHost)
    #expect(bodyText.contains("\"user_id\":\"00000000-0000-0000-0000-000000000002\""))
    #expect(bodyText.contains("\"month\":\"2026-07\""))
    #expect(bodyText.contains("\"total\":231"))
    #expect(bodyText.contains("\"today_total\":77"))
    #expect(bodyText.contains("\"today_date\":\"2026-07-14\""))
    // 옛 표에는 device_id 컬럼이 없다 — 실어 보내면 그 표 업로드가 통째로 깨진다.
    #expect(!bodyText.contains("device_id"))
    #expect(!bodyText.contains("deviceId"))
}

@Test
func fetchTokenBoardCallsRPCWithMonthAndDecodesNamedRows() async throws {
    let testHost = "token-fetch-test"
    TokenBoardURLProtocol.setResponse(
        """
        [
          {"user_id": "aaaa", "display_name": "영식", "avatar_url": "https://example.com/aaaa.jpg", "claude_input": 100, "claude_output": 200, "claude_cache_read": 300, "claude_cache_creation": 400, "codex_input": 500, "codex_output": 600, "total": 2100},
          {"user_id": "bbbb", "display_name": "민수", "avatar_url": null, "claude_input": 1, "claude_output": 2, "claude_cache_read": 3, "claude_cache_creation": 4, "codex_input": 5, "codex_output": 6, "total": 21}
        ]
        """,
        forHost: testHost
    )
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    let rows = try await service.fetchTokenBoard(accessToken: "access-token", month: "2026-07")

    // 디코드: 두 행 + 총합/이름/아바타(전체 공개 행은 자체 완결).
    #expect(rows.count == 2)
    #expect(rows.first { $0.userId == "aaaa" }?.total == 2100)
    #expect(rows.first { $0.userId == "aaaa" }?.displayName == "영식")
    #expect(rows.first { $0.userId == "aaaa" }?.avatarUrl == "https://example.com/aaaa.jpg")
    #expect(rows.first { $0.userId == "bbbb" }?.avatarUrl == nil)  // null → nil
    #expect(rows.first { $0.userId == "bbbb" }?.codexOutput == 6)

    // 요청: POST /rest/v1/rpc/token_usage_board + body {p_month:"2026-07"}(memberIDs 없음).
    let url = try #require(TokenBoardURLProtocol.lastURL(forHost: testHost))
    #expect(url.path == "/rest/v1/rpc/token_usage_board")
    #expect(TokenBoardURLProtocol.lastMethod(forHost: testHost) == "POST")
    let body = try #require(TokenBoardURLProtocol.lastBody(forHost: testHost))
    #expect(body.contains("\"p_month\":\"2026-07\""))
}

@Test
func fetchTokenBoardEmptyResponseDecodesToNoRows() async throws {
    let testHost = "token-fetch-empty-test"
    TokenBoardURLProtocol.setResponse("[]", forHost: testHost)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    let rows = try await service.fetchTokenBoard(accessToken: "access-token", month: "2026-07")

    // 전체 공개라 대상 열거 없이 항상 RPC 를 호출한다 — 아무도 안 올렸으면 빈 배열(요청은 실제로 나간다).
    #expect(rows.isEmpty)
    #expect(TokenBoardURLProtocol.lastURL(forHost: testHost) != nil)
}

@Test
func toTokenBoardEntriesMapsRowsWithNameAndAvatar() {
    // 전체 공개 행은 자체 완결 — 이름/아바타가 행에서 온다(팀원 목록 결합 없음). URL 파싱과 nil 아바타를 함께 검증한다.
    let rows = [
        TokenBoardRow(userId: "u1", displayName: "영식", avatarUrl: "https://example.com/u1.jpg", claudeInput: 10, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0, total: 10),
        TokenBoardRow(userId: "u3", displayName: "지현", avatarUrl: nil, claudeInput: 0, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 5, total: 5)
    ]

    let entries = rows.toTokenBoardEntries()

    #expect(entries.count == 2)
    #expect(entries.first { $0.userID == "u1" }?.name == "영식")
    #expect(entries.first { $0.userID == "u1" }?.avatarURL == URL(string: "https://example.com/u1.jpg"))
    #expect(entries.first { $0.userID == "u1" }?.total == 10)
    // 아바타 null 행은 avatarURL nil.
    #expect(entries.first { $0.userID == "u3" }?.avatarURL == nil)
    #expect(entries.first { $0.userID == "u3" }?.codexOutput == 5)
}

@Test
func sortedByTotalDescendingBreaksTiesByName() {
    // total 내림차순, 동률이면 이름 오름차순. 등수 배지 없이 이 순서가 곧 순위다.
    let entries = [
        TokenBoardEntry(userID: "u1", name: "나나", avatarURL: nil, total: 0, claudeInput: 0, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0),
        TokenBoardEntry(userID: "u2", name: "가가", avatarURL: nil, total: 0, claudeInput: 0, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0),
        TokenBoardEntry(userID: "u3", name: "다다", avatarURL: nil, total: 100, claudeInput: 100, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0)
    ]

    let sorted = entries.sortedByTotalDescending()

    // 100(다다) 먼저, 그 다음 동률 0 은 이름순(가가 < 나나).
    #expect(sorted.map(\.userID) == ["u3", "u2", "u1"])
}

@Test
func tokenUsageMonthKeyIsKSTYearMonth() {
    // 2026-07-31 15:00 UTC = 2026-08-01 00:00 KST → 월 키는 UTC 가 아니라 KST 기준 "2026-08".
    let utcBoundary = ISO8601DateFormatter().date(from: "2026-07-31T15:00:00Z")!
    #expect(TokenUsageMonthKey.current(utcBoundary) == "2026-08")
    // 한낮은 자명하게 그 달.
    let midJuly = ISO8601DateFormatter().date(from: "2026-07-15T03:00:00Z")!
    #expect(TokenUsageMonthKey.current(midJuly) == "2026-07")
}

@Test
func tokenUsageDayKeyIsKSTYearMonthDay() {
    // 2026-07-13 15:00 UTC = 2026-07-14 00:00 KST → 날짜 키는 UTC 가 아니라 KST 기준 "2026-07-14".
    let utcBoundary = ISO8601DateFormatter().date(from: "2026-07-13T15:00:00Z")!
    #expect(TokenUsageDayKey.current(utcBoundary) == "2026-07-14")
    // 1초 전은 아직 KST 07-13.
    let beforeBoundary = ISO8601DateFormatter().date(from: "2026-07-13T14:59:59Z")!
    #expect(TokenUsageDayKey.current(beforeBoundary) == "2026-07-13")
}

@Test
func tokenBoardRowDecodesTodayFieldsAndFallsBackWhenAbsent() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    // 새 RPC(마이그레이션 후): today_total/today_date 포함 → 그대로 디코드.
    let withToday = """
    [{"user_id":"a","display_name":"영","avatar_url":null,"claude_input":1,"claude_output":0,"claude_cache_read":0,"claude_cache_creation":0,"codex_input":0,"codex_output":0,"total":1,"today_total":123,"today_date":"2026-07-14"}]
    """
    let rows = try decoder.decode([TokenBoardRow].self, from: Data(withToday.utf8))
    #expect(rows.first?.todayTotal == 123)
    #expect(rows.first?.todayDate == "2026-07-14")

    // 옛 RPC(마이그레이션 전): today 컬럼 없음 → decodeIfPresent 로 0/"" 폴백(디코드 실패 없이 호환).
    let withoutToday = """
    [{"user_id":"b","display_name":"민","avatar_url":null,"claude_input":1,"claude_output":0,"claude_cache_read":0,"claude_cache_creation":0,"codex_input":0,"codex_output":0,"total":1}]
    """
    let legacyRows = try decoder.decode([TokenBoardRow].self, from: Data(withoutToday.utf8))
    #expect(legacyRows.first?.todayTotal == 0)
    #expect(legacyRows.first?.todayDate == "")
}

@Test
func toTokenBoardEntriesCarriesTodayFields() {
    // 오늘분(todayTotal/todayDate)이 서버 행 → 표시 엔트리로 그대로 옮겨진다.
    let rows = [
        TokenBoardRow(userId: "u1", displayName: "영", avatarUrl: nil, claudeInput: 0, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0, total: 0, todayTotal: 555, todayDate: "2026-07-14")
    ]
    let entries = rows.toTokenBoardEntries()
    #expect(entries.first?.todayTotal == 555)
    #expect(entries.first?.todayDate == "2026-07-14")
}

@Test
func tokenBoardEntryTodayDeltaShowsOnlyWhenDateMatches() {
    // 판정: todayDate == 현재 KST 날짜면 todayTotal, 아니면 0(어제 이후 안 연 사람도 "오늘 +0"으로 균일 표시).
    let e = TokenBoardEntry(userID: "u", name: "영", avatarURL: nil, total: 100, claudeInput: 100, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0, todayTotal: 42, todayDate: "2026-07-14")
    #expect(e.todayDelta(currentDate: "2026-07-14") == 42)   // 오늘 일치 → 노출
    #expect(e.todayDelta(currentDate: "2026-07-15") == 0)    // 스테일 날짜 → 0
    // 오늘분 미상(빈 날짜)도 0.
    let empty = TokenBoardEntry(userID: "u2", name: "민", avatarURL: nil, total: 0, claudeInput: 0, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0, codexInput: 0, codexOutput: 0)
    #expect(empty.todayDelta(currentDate: "2026-07-14") == 0)
}

/// 팀 토큰 보드 조회 응답을 호스트별로 캔에 담아 돌려주는 전용 URLProtocol. 호스트 키 + 잠금으로
/// 병렬 테스트가 서로 간섭하지 않게 한다(각 테스트가 고유 호스트를 쓴다). 요청 URL 도 호스트별로 마지막 것만 보관한다.
final class TokenBoardURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var responsesByHost: [String: String] = [:]
    private nonisolated(unsafe) static var lastURLByHost: [String: URL] = [:]
    private nonisolated(unsafe) static var lastMethodByHost: [String: String] = [:]
    private nonisolated(unsafe) static var lastBodyByHost: [String: String] = [:]

    static func setResponse(_ json: String, forHost host: String) {
        lock.lock(); defer { lock.unlock() }
        responsesByHost[host] = json
        lastURLByHost[host] = nil
        lastMethodByHost[host] = nil
        lastBodyByHost[host] = nil
    }

    static func lastURL(forHost host: String) -> URL? {
        lock.lock(); defer { lock.unlock() }
        return lastURLByHost[host]
    }

    static func lastMethod(forHost host: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return lastMethodByHost[host]
    }

    static func lastBody(forHost host: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return lastBodyByHost[host]
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TokenBoardURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// 요청 본문을 문자열로. URLSession 이 httpBody 를 스트림으로 바꿔 넘겨도 읽을 수 있게 스트림 폴백을 둔다.
    private static func bodyText(from request: URLRequest) -> String {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8) ?? ""
        }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    override func startLoading() {
        let host = request.url?.host ?? ""
        Self.lock.lock()
        Self.lastURLByHost[host] = request.url
        Self.lastMethodByHost[host] = request.httpMethod
        Self.lastBodyByHost[host] = Self.bodyText(from: request)
        let json = Self.responsesByHost[host] ?? "[]"
        Self.lock.unlock()

        let data = Data(json.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - 콕찌르기 / 토큰 사용량 공개 설정 (서비스 계층)

@Test
func sendPokeCallsRPCWithTargetAndDecodesOk() async throws {
    let testHost = "poke-send-ok-test"
    // jsonb 단일 객체 응답(배열 아님) — PokeSendResponse 로 직접 디코드.
    TokenBoardURLProtocol.setResponse(#"{"status":"ok"}"#, forHost: testHost)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    let response = try await service.sendPoke(accessToken: "access-token", to: "target-user-id")

    #expect(response.status == "ok")
    #expect(response.retryAfterSeconds == nil)
    #expect(PokeSendOutcome(response: response) == .ok)

    // 요청: POST /rest/v1/rpc/poke_user + body {p_to:"target-user-id"}(snake_case).
    let url = try #require(TokenBoardURLProtocol.lastURL(forHost: testHost))
    #expect(url.path == "/rest/v1/rpc/poke_user")
    #expect(TokenBoardURLProtocol.lastMethod(forHost: testHost) == "POST")
    let body = try #require(TokenBoardURLProtocol.lastBody(forHost: testHost))
    #expect(body.contains("\"p_to\":\"target-user-id\""))
    #expect(!body.contains("\"pTo\""))
}

@Test
func sendPokeDecodesCooldownWithRetryAfter() async throws {
    let testHost = "poke-send-cooldown-test"
    TokenBoardURLProtocol.setResponse(#"{"status":"cooldown","retry_after_seconds":42}"#, forHost: testHost)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    let response = try await service.sendPoke(accessToken: "access-token", to: "target-user-id")

    #expect(response.status == "cooldown")
    #expect(response.retryAfterSeconds == 42)
    #expect(PokeSendOutcome(response: response) == .cooldown(retryAfterSeconds: 42))
}

@Test
func takePokesDecodesReceivedRows() async throws {
    let testHost = "poke-take-test"
    TokenBoardURLProtocol.setResponse(
        """
        [
          {"id": "p1", "from_user": "u1", "from_display_name": "영식", "from_avatar_url": "https://example.com/u1.jpg", "created_epoch": 1721000000},
          {"id": "p2", "from_user": "u2", "from_display_name": "민수", "from_avatar_url": null, "created_epoch": 1721000123}
        ]
        """,
        forHost: testHost
    )
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    let rows = try await service.takePokes(accessToken: "access-token")

    #expect(rows.count == 2)
    #expect(rows.first { $0.id == "p1" }?.fromDisplayName == "영식")
    #expect(rows.first { $0.id == "p1" }?.createdEpoch == 1721000000)
    #expect(rows.first { $0.id == "p2" }?.fromAvatarUrl == nil)

    let url = try #require(TokenBoardURLProtocol.lastURL(forHost: testHost))
    #expect(url.path == "/rest/v1/rpc/take_pokes")
    #expect(TokenBoardURLProtocol.lastMethod(forHost: testHost) == "POST")
}

@Test
func fetchPokeDirectoryDecodesRows() async throws {
    let testHost = "poke-directory-test"
    TokenBoardURLProtocol.setResponse(
        """
        [
          {"user_id": "u1", "display_name": "영식", "avatar_url": "https://example.com/u1.jpg", "is_working": true},
          {"user_id": "u2", "display_name": "민수", "avatar_url": null, "is_working": false}
        ]
        """,
        forHost: testHost
    )
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    let rows = try await service.fetchPokeDirectory(accessToken: "access-token")

    #expect(rows.count == 2)
    #expect(rows.first { $0.userId == "u1" }?.isWorking == true)
    #expect(rows.first { $0.userId == "u2" }?.avatarUrl == nil)

    let url = try #require(TokenBoardURLProtocol.lastURL(forHost: testHost))
    #expect(url.path == "/rest/v1/rpc/app_user_directory")
}

@Test
func fetchTokenUsagePublicDefaultsToTrueOnEmptyResponse() async throws {
    let testHost = "privacy-fetch-empty-test"
    TokenBoardURLProtocol.setResponse("[]", forHost: testHost)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    // 행 누락(빈 배열) → 기본값 폴백(공개 true / 수집 true).
    let settings = try await service.fetchTokenUsageSettings(accessToken: "access-token", userID: "u1")
    #expect(settings.isPublic == true)
    #expect(settings.collects == true)

    let url = try #require(TokenBoardURLProtocol.lastURL(forHost: testHost))
    #expect(url.path == "/rest/v1/profiles")
    #expect(url.query?.contains("id=eq.u1") == true)
    // 두 설정을 한 요청으로 가져온다(요청 수 불변). URLComponents 는 쉼표를 인코딩하지 않는다.
    #expect(url.query?.contains("select=token_usage_public,token_usage_collect") == true)
}

@Test
func fetchTokenUsagePublicDecodesFalse() async throws {
    let testHost = "privacy-fetch-false-test"
    TokenBoardURLProtocol.setResponse(#"[{"token_usage_public": false}]"#, forHost: testHost)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    // token_usage_collect 키가 아예 없는 응답(마이그레이션 미적용 서버) → 수집은 기본 true 로 폴백해야 한다.
    // 여기서 false 로 떨어지면 구서버에서 전원의 업로드가 조용히 멈춘다.
    let settings = try await service.fetchTokenUsageSettings(accessToken: "access-token", userID: "u1")
    #expect(settings.isPublic == false)
    #expect(settings.collects == true)
}

@Test
func fetchTokenUsageSettingsDecodesCollectFalse() async throws {
    let testHost = "collect-fetch-false-test"
    TokenBoardURLProtocol.setResponse(
        #"[{"token_usage_public": true, "token_usage_collect": false}]"#,
        forHost: testHost
    )
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    // 공개는 켜져 있어도 수집만 따로 끌 수 있다(두 설정은 독립).
    let settings = try await service.fetchTokenUsageSettings(accessToken: "access-token", userID: "u1")
    #expect(settings.isPublic == true)
    #expect(settings.collects == false)
}

@Test
func updateTokenUsagePublicPatchesProfileRow() async throws {
    let testHost = "privacy-update-test"
    TokenBoardURLProtocol.setResponse("", forHost: testHost)  // return=minimal → 본문 무시.
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    try await service.updateTokenUsagePublic(accessToken: "access-token", userID: "u1", isPublic: false)

    let url = try #require(TokenBoardURLProtocol.lastURL(forHost: testHost))
    #expect(url.path == "/rest/v1/profiles")
    #expect(url.query?.contains("id=eq.u1") == true)
    #expect(TokenBoardURLProtocol.lastMethod(forHost: testHost) == "PATCH")
    let body = try #require(TokenBoardURLProtocol.lastBody(forHost: testHost))
    #expect(body.contains("\"token_usage_public\":false"))
    #expect(!body.contains("\"tokenUsagePublic\""))
}

// MARK: - 개인 기록(히트맵·회고) 원천 조회 + ISO8601 소수초 파싱

@Test
func fetchMySessionsRequestsOwnCompletedSessionsSinceWindow() async throws {
    let testHost = "my-sessions-test"
    TokenBoardURLProtocol.setResponse(
        """
        [
          {"id": "s1", "user_id": "u1", "started_at": "2026-07-20T01:00:00.123Z", "ended_at": "2026-07-20T04:00:00.456Z", "duration_seconds": 10800},
          {"id": "s2", "user_id": "u1", "started_at": "2026-07-21T02:00:00Z", "ended_at": "2026-07-21T03:00:00Z", "duration_seconds": 3600}
        ]
        """,
        forHost: testHost
    )
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    let since = try #require(ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z"))
    let rows = try await service.fetchMySessions(accessToken: "access-token", userID: "u1", since: since)

    // 디코드: 완료 세션 두 건(히트맵/회고가 쓰는 타임스탬프 원문 그대로).
    #expect(rows.count == 2)
    #expect(rows.first { $0.id == "s1" }?.durationSeconds == 10800)
    #expect(rows.first { $0.id == "s2" }?.endedAt == "2026-07-21T03:00:00Z")

    // 요청: GET /rest/v1/work_sessions + 본인 필터 + 완료 세션 + since 창 + 최신순 + 상한.
    let url = try #require(TokenBoardURLProtocol.lastURL(forHost: testHost))
    #expect(url.path == "/rest/v1/work_sessions")
    #expect(TokenBoardURLProtocol.lastMethod(forHost: testHost) == "GET")
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(items.contains(URLQueryItem(name: "select", value: "id,user_id,started_at,ended_at,duration_seconds")))
    #expect(items.contains(URLQueryItem(name: "user_id", value: "eq.u1")))
    #expect(items.contains(URLQueryItem(name: "ended_at", value: "not.is.null")))
    #expect(items.contains(URLQueryItem(name: "ended_at", value: "gte.2026-07-01T00:00:00Z")))
    // 정렬은 **내림차순**: 조회 창이 13주(12주 잔디)로 넓어져 어떤 상한(우리 limit 이든 서버 max_rows 든)에 걸리면
    // 오름차순에선 가장 최근 주(지난주 회고·히트맵)가 먼저 사라지고, 내림차순에선 잔디의 가장 오래된 열만 옅어진다.
    #expect(items.contains(URLQueryItem(name: "order", value: "started_at.desc")))
    #expect(!items.contains(URLQueryItem(name: "order", value: "started_at.asc")))
    // 상한 5000행: 2000행 시절의 잔재를 남기지 않는다(서버가 더 낮게 자를 수는 있어도 클라가 먼저 자르진 않는다).
    #expect(items.contains(URLQueryItem(name: "limit", value: "5000")))
    #expect(!items.contains(URLQueryItem(name: "limit", value: "2000")))
    // 팀 필터는 걸지 않는다(본인 세션만 보면 되고 RLS 가 나머지를 막는다).
    #expect(!items.contains(where: { $0.name == "team_id" }))
}

@Test
func parseDateAcceptsFractionalSecondsAndFallsBackToPlain() async throws {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://iso-parse-test")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )

    let base = try #require(ISO8601DateFormatter().date(from: "2026-07-26T04:15:35Z"))
    // 소수초 포함(프로덕션 timestamptz 의 실제 형태) — 기본 포매터 하나만 쓰던 시절엔 통째로 nil 이었다.
    let fractionalParsed = await service.parseDate("2026-07-26T04:15:35.634Z")
    let fractional = try #require(fractionalParsed)
    #expect(abs(fractional.timeIntervalSince(base) - 0.634) < 0.005)
    // 소수초 없는 형태도 그대로 폴백 파싱된다(기존 동작 불변).
    let plain = await service.parseDate("2026-07-26T04:15:35Z")
    #expect(plain == base)
    // 형식이 아예 아닌 값은 여전히 nil.
    let garbage = await service.parseDate("어제쯤")
    #expect(garbage == nil)
}

@Test
func fetchTeamStatusesParsesFractionalSecondTimestamps() async throws {
    // 회귀 픽스처: 소수초가 붙은 started_at/last_seen_at 을 못 읽으면 진행 세션 누적이 조용히 0 이 된다.
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://fractional-seconds-test")!,
        anonKey: "anon-test-key",
        session: FractionalSecondsURLProtocol.session()
    )

    let now = Date()
    let statuses = try await service.fetchTeamStatuses(
        accessToken: "access-token",
        teamID: URLProtocolStub.stubTeamID,
        now: now
    )

    let member = try #require(statuses.first { $0.id == "00000000-0000-0000-0000-000000000002" })
    // 소수초 타임스탬프가 nil 로 흐르지 않는다 — 진행 세션 시작/생존신호 모두 살아 있다.
    #expect(member.currentSessionStartedAt != nil)
    #expect(member.lastSeenAt != nil)
    #expect(member.presence(now: now) == .activeWorking)
    // 한 시간 전(소수초 포함) 시작한 진행 세션이므로 라이브 누적은 3600초 근방이어야 한다(파싱 실패 시 0).
    let live = member.currentDurationSeconds(now: now)
    #expect(live >= 3_590 && live <= 3_610)
}

/// 소수초가 붙은 timestamptz 픽스처 전용 스텁. 프로덕션 Supabase 는 "2026-07-26T04:15:35.634Z" 처럼
/// 소수초를 붙여 내려주므로, 실제 디코드 경로(fetchTeamStatuses)로 파싱 회귀를 잡는다.
/// 시각은 now 기준 상대값으로 만들어 stale(>90초) 오판 없이 결정적으로 검증한다.
final class FractionalSecondsURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FractionalSecondsURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// 소수초 포함 ISO8601 문자열. 포매터는 Sendable 이 아니라 정적 보관 대신 호출마다 만든다(스텁이라 비용 무관).
    private static func stamp(_ offset: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date().addingTimeInterval(offset))
    }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let isOpenSessionQuery = request.url?.query?.contains("ended_at=is.null") == true
        let json: String
        if path == "/rest/v1/work_statuses" {
            json = """
            [
              {
                "user_id": "00000000-0000-0000-0000-000000000002",
                "status": "working",
                "updated_at": "\(Self.stamp(-10))",
                "last_seen_at": "\(Self.stamp(-5))",
                "active_session_id": "80000000-0000-0000-0000-000000000001",
                "profiles": { "display_name": "영식", "email": "member@example.com", "avatar_url": null }
              }
            ]
            """
        } else if path == "/rest/v1/work_sessions", isOpenSessionQuery {
            json = """
            [
              {
                "id": "80000000-0000-0000-0000-000000000001",
                "user_id": "00000000-0000-0000-0000-000000000002",
                "started_at": "\(Self.stamp(-3_600))",
                "ended_at": null,
                "duration_seconds": null
              }
            ]
            """
        } else {
            json = "[]"
        }

        let data = Data(json.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - v0.2.18: 리프레시 토큰 만료가 "이미 가입된 이메일"로 오분류되지 않는다(D6-1)

@Test
func refreshTokenErrorClassifiesAsSessionExpiredNotAlreadyRegistered() async {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://classify-test")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )

    // GoTrue 의 리프레시 실패 본문. "Already Used" 의 "already" 가 예전엔 중복 가입 가드에 먼저 걸렸다.
    let refreshBody = #"{"error":"invalid_grant","error_description":"Invalid Refresh Token: Already Used"}"#
        .data(using: .utf8)!
    #expect(await service.serviceError(statusCode: 400, data: refreshBody) == .sessionExpired)

    let refreshBody2 = #"{"message":"refresh_token_not_found"}"#.data(using: .utf8)!
    #expect(await service.serviceError(statusCode: 401, data: refreshBody2) == .sessionExpired)

    // 대조군: 진짜 중복 가입은 그대로 emailAlreadyRegistered 여야 한다(회귀 방지).
    let dupBody = #"{"message":"User already registered"}"#.data(using: .utf8)!
    #expect(await service.serviceError(statusCode: 422, data: dupBody) == .emailAlreadyRegistered)
}

// MARK: - 비밀번호 재설정 OTP (recover → verify → PUT user)

/// 재설정 3경로 전용 스텁. URLProtocolStub(트랙 A 소유)은 /auth/v1/verify 를 모르고 빈 200 을 돌려줘
/// 세션 디코드가 조용히 실패하므로, GoalRPCURLProtocol 과 같은 방식으로 여기 전용 스텁을 둔다.
/// **응답 본문은 전부 2026-08-13 실서버(xfnhfjvubetkdnfkfljg) 실측값이다** — 딱 하나,
/// over_email_send_rate_limit 만은 메일을 실제로 발송해야 재현되는 오류라 GoTrue 원문 문구를 그대로 썼다(보고서 참조).
/// 정적 버퍼는 스위트가 병렬로 도는 동안 여러 워커가 동시에 append 하므로 잠금 아래에서만 만진다.
final class RecoveryOTPURLProtocol: URLProtocol {
    private nonisolated(unsafe) static var requests: [URLRequest] = []
    private nonisolated(unsafe) static var bodiesByHost: [String: [String]] = [:]
    private static let stateLock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        Self.record(request: request, bodyText: Self.bodyText(from: request))

        let (statusCode, json) = Self.response(host: host, path: request.url?.path ?? "")
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecoveryOTPURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func requests(forHost host: String) -> [URLRequest] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return requests.filter { $0.url?.host == host }
    }

    static func bodyText(forHost host: String) -> String {
        stateLock.lock()
        defer { stateLock.unlock() }
        return bodiesByHost[host, default: []].joined(separator: "\n")
    }

    private static func record(request: URLRequest, bodyText: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        requests.append(request)
        bodiesByHost[request.url?.host ?? "", default: []].append(bodyText)
    }

    private static func response(host: String, path: String) -> (Int, String) {
        switch host {
        case "otp-rate-seconds":
            // 메일 발송 간격 제한. 유일하게 남은 초를 담고 있는 본문(미실측 — 실측하려면 메일이 실제로 나간다).
            return (429, #"{"code":429,"error_code":"over_email_send_rate_limit","msg":"For security purposes, you can only request this after 51 seconds."}"#)
        case "otp-rate-generic":
            // 실측(verify 40연타): IP 단위 제한은 초가 **없다**.
            return (429, #"{"code":429,"error_code":"over_request_rate_limit","msg":"Request rate limit reached"}"#)
        case "otp-rate-nobody":
            // 429 인데 JSON 이 아닌 경우(에지/프록시가 가로챈 응답). 공용 매핑이 .invalidResponse(429) 로 준다.
            return (429, "")
        case "otp-expired":
            // 실측: 존재하는 계정+틀린 코드, 없는 계정+아무 코드, 잘못된 type 까지 전부 이 하나로 온다.
            return (403, #"{"code":403,"error_code":"otp_expired","msg":"Token has expired or is invalid"}"#)
        case "otp-empty-token":
            return (400, #"{"code":400,"error_code":"validation_failed","msg":"Verify requires either a token or a token hash"}"#)
        case "otp-weak-password":
            return (422, #"{"code":422,"error_code":"weak_password","msg":"Password should be at least 6 characters.","weak_password":{"reasons":["length"]}}"#)
        case "otp-same-password":
            // 미실측(유효한 recovery 세션이 있어야 재현된다). GoTrue 원문 문구.
            return (422, #"{"code":422,"error_code":"same_password","msg":"New password should be different from the old password."}"#)
        case "otp-bad-jwt":
            // 실측: 잘못된 Bearer 로 PUT /auth/v1/user.
            return (403, #"{"code":403,"error_code":"bad_jwt","msg":"invalid JWT: unable to parse or verify signature, token is malformed: token contains an invalid number of segments"}"#)
        default:
            break
        }
        if path == "/auth/v1/verify" {
            // 실측 성공 응답과 같은 모양(로그인 응답과 동일) — SignInResponse 재사용이 성립하는지의 근거.
            return (200, """
            {
              "access_token": "recovery-access-token",
              "refresh_token": "recovery-refresh-token",
              "token_type": "bearer",
              "expires_in": 3600,
              "user": { "id": "00000000-0000-0000-0000-000000000002" }
            }
            """)
        }
        if path == "/auth/v1/user" {
            return (200, #"{"id":"00000000-0000-0000-0000-000000000002","email":"member@example.com"}"#)
        }
        return (200, "{}")
    }

    private static func bodyText(from request: URLRequest) -> String {
        if let body = request.httpBody {
            return String(decoding: body, as: UTF8.self)
        }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private func recoveryService(host: String) -> SupabaseWorkService {
    SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: RecoveryOTPURLProtocol.session()
    )
}

@Test
func sendPasswordResetCodePostsRecoverWithAnonBearer() async throws {
    let testHost = "otp-recover-ok"
    let service = recoveryService(host: testHost)

    try await service.sendPasswordResetCode(email: "member@example.com")

    let request = try #require(RecoveryOTPURLProtocol.requests(forHost: testHost).first {
        $0.url?.path == "/auth/v1/recover"
    })
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "apikey") == "anon-test-key")
    // 로그인 전 경로라 유저 토큰이 없다 — anon 키가 Bearer 로 나가야 한다(다른 값이면 401 로 죽는다).
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer anon-test-key")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "Prefer") == nil)
    #expect(RecoveryOTPURLProtocol.bodyText(forHost: testHost) == #"{"email":"member@example.com"}"#)
}

@Test
func sendPasswordResetCodeMapsEmailSendRateLimitWithRemainingSeconds() async {
    let service = recoveryService(host: "otp-rate-seconds")

    do {
        try await service.sendPasswordResetCode(email: "member@example.com")
        Issue.record("60초 재발송 제한은 성공으로 흘러선 안 된다")
    } catch let error as SupabaseWorkServiceError {
        // 남은 초를 못 뽑으면 화면이 "잠시 후"밖에 못 말하고, 사용자는 몇 초인지 몰라 계속 눌러 429 를 다시 부른다.
        #expect(error == .rateLimited(retryAfterSeconds: 51))
    } catch {
        Issue.record("예상치 못한 오류: \(error)")
    }
}

@Test
func sendPasswordResetCodeMapsGenericRateLimitWithoutSeconds() async {
    let service = recoveryService(host: "otp-rate-generic")

    do {
        try await service.sendPasswordResetCode(email: "member@example.com")
        Issue.record("IP 단위 429 도 성공으로 흘러선 안 된다")
    } catch let error as SupabaseWorkServiceError {
        // 이 본문엔 초가 없다. 없는 걸 0 으로 지어내면 재시도 버튼이 곧바로 열린다.
        #expect(error == .rateLimited(retryAfterSeconds: nil))
    } catch {
        Issue.record("예상치 못한 오류: \(error)")
    }
}

@Test
func sendPasswordResetCodeMapsBodylessRateLimit() async {
    let service = recoveryService(host: "otp-rate-nobody")

    do {
        try await service.sendPasswordResetCode(email: "member@example.com")
        Issue.record("본문 없는 429 도 성공으로 흘러선 안 된다")
    } catch let error as SupabaseWorkServiceError {
        // 본문이 JSON 이 아니면 공용 매핑이 .invalidResponse(429) 를 준다 — status 로만 알 수 있는 유일한 경우.
        #expect(error == .rateLimited(retryAfterSeconds: nil))
    } catch {
        Issue.record("예상치 못한 오류: \(error)")
    }
}

@Test
func verifyPasswordResetCodePostsRecoveryTypeAndReturnsSession() async throws {
    let testHost = "otp-verify-ok"
    let service = recoveryService(host: testHost)

    let session = try await service.verifyPasswordResetCode(email: "member@example.com", code: "123456")

    // 응답이 로그인과 같은 모양이라 SignInResponse 를 재사용했다 — 토큰 3종이 그대로 살아 나와야 성립한다.
    #expect(session.accessToken == "recovery-access-token")
    #expect(session.refreshToken == "recovery-refresh-token")
    #expect(session.userID == "00000000-0000-0000-0000-000000000002")

    let request = try #require(RecoveryOTPURLProtocol.requests(forHost: testHost).first {
        $0.url?.path == "/auth/v1/verify"
    })
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer anon-test-key")
    let bodyText = RecoveryOTPURLProtocol.bodyText(forHost: testHost)
    #expect(bodyText.contains(#""email":"member@example.com""#))
    #expect(bodyText.contains(#""token":"123456""#))
    // type 이 recovery 가 아니면 서버는 403 otp_expired 를 준다 — 화면엔 "코드가 틀렸다"고 뜨고 원인은 안 보인다.
    #expect(bodyText.contains(#""type":"recovery""#))
}

@Test
func verifyPasswordResetCodeMergesExpiredAndWrongCodeIntoOneError() async {
    let service = recoveryService(host: "otp-expired")

    do {
        _ = try await service.verifyPasswordResetCode(email: "member@example.com", code: "000000")
        Issue.record("틀린 코드는 세션을 내주면 안 된다")
    } catch let error as SupabaseWorkServiceError {
        // 만료와 불일치를 나눌 수 없다(실측: 두 경우 모두 같은 403 otp_expired). 그래서 케이스도 하나다.
        #expect(error == .otpInvalidOrExpired)
    } catch {
        Issue.record("예상치 못한 오류: \(error)")
    }
}

@Test
func verifyPasswordResetCodeMapsEmptyTokenValidationFailure() async {
    let service = recoveryService(host: "otp-empty-token")

    do {
        _ = try await service.verifyPasswordResetCode(email: "member@example.com", code: "")
        Issue.record("빈 코드는 세션을 내주면 안 된다")
    } catch let error as SupabaseWorkServiceError {
        // 서버 문구는 다르지만("Verify requires either a token or a token hash") 사용자 입장에선 같은 사건이다.
        #expect(error == .otpInvalidOrExpired)
    } catch {
        Issue.record("예상치 못한 오류: \(error)")
    }
}

@Test
func updatePasswordPutsUserWithRecoveryBearer() async throws {
    let testHost = "otp-update-ok"
    let service = recoveryService(host: testHost)

    try await service.updatePassword(accessToken: "recovery-access-token", newPassword: "new-team-password")

    let request = try #require(RecoveryOTPURLProtocol.requests(forHost: testHost).first {
        $0.url?.path == "/auth/v1/user"
    })
    #expect(request.httpMethod == "PUT")
    // verify 로 받은 토큰을 안 붙이면 서버는 403 bad_jwt 를 준다 — 비밀번호가 바뀌지 않은 채 흐름만 끝난다.
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer recovery-access-token")
    #expect(request.value(forHTTPHeaderField: "apikey") == "anon-test-key")
    #expect(RecoveryOTPURLProtocol.bodyText(forHost: testHost) == #"{"password":"new-team-password"}"#)
}

@Test
func updatePasswordMapsWeakPasswordRule() async {
    let service = recoveryService(host: "otp-weak-password")

    do {
        try await service.updatePassword(accessToken: "recovery-access-token", newPassword: "12")
        Issue.record("6자 미만 비밀번호가 성공으로 흘러선 안 된다")
    } catch let error as SupabaseWorkServiceError {
        #expect(error == .weakPassword)
    } catch {
        Issue.record("예상치 못한 오류: \(error)")
    }
}

@Test
func updatePasswordMapsSamePasswordReuse() async {
    let service = recoveryService(host: "otp-same-password")

    do {
        try await service.updatePassword(accessToken: "recovery-access-token", newPassword: "same-as-before")
        Issue.record("같은 비밀번호 재사용이 성공으로 흘러선 안 된다")
    } catch let error as SupabaseWorkServiceError {
        // **지금은 .weakPassword 로 뭉개진다** — 공용 매핑(SupabaseWorkHTTP.serviceError)이 "password" 를
        // 포함한 모든 메시지를 그리로 보내는데 그 파일은 이 트랙 소유가 아니다. 매핑 한 줄이 들어오면
        // .samePasswordReuse 가 된다. 둘 다 "비밀번호를 바꿔야 한다"는 같은 계열이라 이 테스트는 양쪽을 통과시킨다
        // (한쪽으로 못 박으면 매핑이 들어오는 순간 무관한 테스트가 빨개진다).
        #expect(error == .weakPassword || error == .samePasswordReuse)
    } catch {
        Issue.record("예상치 못한 오류: \(error)")
    }
}

@Test
func updatePasswordMapsBadJWTToSessionExpired() async {
    let service = recoveryService(host: "otp-bad-jwt")

    do {
        try await service.updatePassword(accessToken: "not-a-jwt", newPassword: "new-team-password")
        Issue.record("죽은 토큰으로 비밀번호가 바뀌면 안 된다")
    } catch let error as SupabaseWorkServiceError {
        // 그냥 두면 "invalid JWT: unable to parse or verify signature…" 가 메뉴바에 영어 그대로 뜬다.
        #expect(error == .sessionExpired)
    } catch {
        Issue.record("예상치 못한 오류: \(error)")
    }
}

// MARK: - 3글자 메시지 (서비스 계층)

private func messageService(host: String) -> SupabaseWorkService {
    SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: TokenBoardURLProtocol.session()
    )
}

@Test
func sendMessageCallsDedicatedRPCWithSnakeCaseBody() async throws {
    let testHost = "msg-send-shape"
    // jsonb 단일 객체 응답(배열 아님) — poke_user 와 같은 규약이라 PokeSendResponse 로 직접 디코드한다.
    TokenBoardURLProtocol.setResponse(#"{"status":"ok"}"#, forHost: testHost)

    let response = try await messageService(host: testHost)
        .sendMessage(accessToken: "access-token", to: "target-user-id", body: "고고")

    #expect(response.status == "ok")
    #expect(MessageSendOutcome(response: response) == .ok)

    // 경로가 정확히 send_message 여야 한다. poke_user 오버로드로 만들면 PostgREST 가 모호해져 300/404 가 된다.
    let url = try #require(TokenBoardURLProtocol.lastURL(forHost: testHost))
    #expect(url.path == "/rest/v1/rpc/send_message")
    #expect(TokenBoardURLProtocol.lastMethod(forHost: testHost) == "POST")
    let body = try #require(TokenBoardURLProtocol.lastBody(forHost: testHost))
    #expect(body.contains("\"p_to\":\"target-user-id\""))
    #expect(body.contains("\"p_body\":\"고고\""))
    // 카멜케이스가 그대로 나가면 서버는 인자를 못 찾아 404 를 내는데, 응답 본문만 보면 원인이 안 보인다.
    #expect(!body.contains("\"pTo\""))
    #expect(!body.contains("\"pBody\""))
}

@Test
func sendMessageClassifiesEveryServerStatus() async throws {
    // 6종을 전부 **HTTP 응답으로** 통과시킨다. 직접 만든 PokeSendResponse 로만 검증하면 디코더 쪽 회귀
    // (스네이크케이스 키·옵셔널 누락)를 원리적으로 못 잡는다 — PokeSendResponse 는 커스텀 init(from:) 을 쓴다.
    let cases: [(String, String, MessageSendOutcome)] = [
        ("msg-status-ok", #"{"status":"ok"}"#, .ok),
        ("msg-status-invalid", #"{"status":"invalid"}"#, .invalid),
        ("msg-status-notworking", #"{"status":"not_working"}"#, .notWorking),
        // 자리비움 게이트(2026-08-14 복원). 이게 .invalid 로 접히면 사용자는 자리 비운 사람에게 보낼 때마다
        // 두루뭉술한 "지금은 보낼 수 없어요"를 보게 된다 — 흔한 경로라 문구 손실이 크다.
        ("msg-status-target-away", #"{"status":"target_not_working"}"#, .targetNotWorking),
        ("msg-status-focused", #"{"status":"target_focused"}"#, .targetFocused),
        ("msg-status-toolong", #"{"status":"too_long"}"#, .tooLong),
        ("msg-status-cooldown", #"{"status":"cooldown","retry_after_seconds":37}"#, .cooldown(retryAfterSeconds: 37)),
        // 서버가 나중에 status 를 하나 더 늘려도 옛 앱은 크래시하지 않고 안전한 문구로 수렴해야 한다.
        ("msg-status-future", #"{"status":"뭔가새로운것"}"#, .invalid)
    ]

    for (testHost, json, expected) in cases {
        TokenBoardURLProtocol.setResponse(json, forHost: testHost)
        let response = try await messageService(host: testHost)
            .sendMessage(accessToken: "access-token", to: "target-user-id", body: "가나다")
        #expect(MessageSendOutcome(response: response) == expected, "\(testHost)")
    }

    // retry_after_seconds 가 없는 cooldown(잘린 응답/옛 서버)도 0초가 아니라 최소 1초 이상으로 수렴해야 한다 —
    // 0 이면 화면이 즉시 재시도 가능으로 보이고, 사용자는 눌러서 또 거절당한다.
    TokenBoardURLProtocol.setResponse(#"{"status":"cooldown"}"#, forHost: "msg-status-cooldown-bare")
    let bare = try await messageService(host: "msg-status-cooldown-bare")
        .sendMessage(accessToken: "access-token", to: "target-user-id", body: "가나다")
    #expect(MessageSendOutcome(response: bare) == .cooldown(retryAfterSeconds: 60))
}

@Test
func sendMessageRejectsEmptyAndTooLongWithoutRoundTrip() async throws {
    let testHost = "msg-local-gate"
    // 요청이 실제로 나갔다면 이 응답(ok)이 돌아와 기대와 어긋나므로, 왕복 여부가 결과로도 드러난다.
    TokenBoardURLProtocol.setResponse(#"{"status":"ok"}"#, forHost: testHost)
    let service = messageService(host: testHost)

    // 공백·개행만 있는 입력은 서버까지 갈 이유가 없다.
    let blank = try await service.sendMessage(accessToken: "access-token", to: "t", body: "  \n\t ")
    #expect(MessageSendOutcome(response: blank) == .invalid)
    #expect(TokenBoardURLProtocol.lastURL(forHost: testHost) == nil)

    // 4글자도 마찬가지다.
    let long = try await service.sendMessage(accessToken: "access-token", to: "t", body: "가나다라")
    #expect(MessageSendOutcome(response: long) == .tooLong)
    #expect(TokenBoardURLProtocol.lastURL(forHost: testHost) == nil)

    // 경계: 앞뒤 공백을 뺀 3글자는 **실제로 나가고**, 나가는 값은 원문이 아니라 정규화된 문자열이다.
    let ok = try await service.sendMessage(accessToken: "access-token", to: "t", body: " 가나다 ")
    #expect(MessageSendOutcome(response: ok) == .ok)
    let url = try #require(TokenBoardURLProtocol.lastURL(forHost: testHost))
    #expect(url.path == "/rest/v1/rpc/send_message")
    let sent = try #require(TokenBoardURLProtocol.lastBody(forHost: testHost))
    #expect(sent.contains("\"p_body\":\"가나다\""))
}

@Test
func takePokesDecodesMessageBodyAndStaysBackwardCompatible() async throws {
    let testHost = "msg-take-test"
    // 3행: (1) 새 서버의 메시지 행, (2) 새 서버의 일반 찌르기(body 는 null),
    //      (3) **마이그레이션 전 서버**의 행 — kind·body 키 자체가 없다.
    TokenBoardURLProtocol.setResponse(
        """
        [
          {"id": "m1", "from_user": "u1", "from_display_name": "영식", "from_avatar_url": null,
           "created_epoch": 1721000000, "kind": "message", "body": "고고"},
          {"id": "p2", "from_user": "u2", "from_display_name": "민수", "from_avatar_url": null,
           "created_epoch": 1721000123, "kind": "normal", "body": null},
          {"id": "p3", "from_user": "u3", "from_display_name": "지현", "from_avatar_url": null,
           "created_epoch": 1721000456}
        ]
        """,
        forHost: testHost
    )

    let rows = try await messageService(host: testHost).takePokes(accessToken: "access-token")

    // 세 행 모두 살아야 한다. body 가 비옵셔널이었다면 (3) 하나 때문에 배열 전체가 throw 되어
    // 그 사이 도착한 찔림이 전부 조용히 소멸한다(수신 즉시 서버에서 소비되므로 되돌릴 방법도 없다).
    #expect(rows.count == 3)

    let message = try #require(rows.first { $0.id == "m1" })
    #expect(message.body == "고고")
    #expect(PokeKind(rawServerValue: message.kind) == .message)

    let poke = try #require(rows.first { $0.id == "p2" })
    #expect(poke.body == nil)
    #expect(PokeKind(rawServerValue: poke.kind) == .normal)

    let legacy = try #require(rows.first { $0.id == "p3" })
    #expect(legacy.kind == nil)
    #expect(legacy.body == nil)
    #expect(PokeKind(rawServerValue: legacy.kind) == .normal)
}

@Test
func messageBodyCountsCharactersTheWayUsersDo() throws {
    // 경계 0/1/3/4.
    #expect(MessageBody.characterCount("") == 0)
    #expect(MessageBody.characterCount("가") == 1)
    #expect(MessageBody.characterCount("가나다") == 3)
    #expect(MessageBody.characterCount("가나다라") == 4)
    #expect(MessageBody.validate("") == .empty)
    #expect(MessageBody.validate("   ") == .empty)
    #expect(MessageBody.validate("가") == .ok("가"))
    #expect(MessageBody.validate("가나다") == .ok("가나다"))
    #expect(MessageBody.validate("가나다라") == .tooLong(maxCharacters: 3))

    // 자모 분해(NFD) 한글. macOS 붙여넣기로 들어오는 형태다 — Swift 는 2글자로 세지만 유니코드 스칼라는 6이라
    // 정규화 없이 보내면 서버 char_length 가 6으로 세어 too_long 을 낸다. 보내는 값이 NFC 여야 한다.
    let decomposed = "\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}"   // "한글"의 NFD
    #expect(decomposed.unicodeScalars.count == 6)
    #expect(MessageBody.characterCount(decomposed) == 2)
    #expect(MessageBody.sanitized(decomposed) == "한글")
    #expect(MessageBody.sanitized(decomposed).unicodeScalars.count == 2)

    // 글자수 세기 자체는 여전히 자소 클러스터 단위다(입력 카운터가 이 값을 쓴다).
    // 다만 **셀 수 있다와 보낼 수 있다는 다르다** — 이모지는 아래 텍스트 전용 게이트에서 거부된다.
    #expect(MessageBody.characterCount("👍") == 1)
    #expect(MessageBody.characterCount("👨‍👩‍👧‍👦") == 1)

    // 앞뒤 공백·개행은 자른다(붙여넣기에 딸려 온 여백으로 거부하면 불친절하다).
    #expect(MessageBody.sanitized("  가나  ") == "가나")
    #expect(MessageBody.sanitized("가나\n") == "가나")
    // 가운데 공백은 사용자가 세는 한 글자라 남긴다.
    #expect(MessageBody.characterCount("가 나") == 3)
}

@Test
func messageBodyAcceptsOnlyTextAndRejectsEmoji() throws {
    // ── 통과해야 하는 것 ──
    // ★ 한글 자모가 막히면 이 기능의 절반(ㅇㅋ·ㅎㅇ)이 죽는다.
    // ★ `^^`·`-_-`·`:)`·`...` 는 서버가 **일부러 살려 둔** 표현이다 — 클라가 이걸 막으면 서버는 받아 주는데
    //   사용자만 못 치는, 방향만 반대인 같은 크기의 어긋남이 된다.
    for text in ["가나다", "ㅇㅋ", "ㅎㅇ", "abc", "123", "밥?", "ㅋㅋㅋ", "ㅠㅠ", "굿!", "OK", "음~", "ok!", "가 나", "1.5",
                 "^^", "-_-", ":)", "...", "a@b", "#ab", "(-:"] {
        #expect(MessageBody.validate(text) == .ok(text), "통과해야 한다: \(text)")
    }
    // 한글 범위 경계: 음절 가(U+AC00)~힣(U+D7A3), 호환 자모 ㄱ(U+3131)~ㅣ(U+3163).
    for text in ["\u{AC00}", "\u{D7A3}", "\u{3131}", "\u{3163}"] {
        #expect(MessageBody.validate(text) == .ok(text), "한글 범위 안이다: \(text.debugDescription)")
    }
    // 조합 자모로 들어와도 NFC 합성으로 음절 범위에 안착한다(옛한글이 아닌 정상 한글).
    #expect(MessageBody.validate("\u{1112}\u{1161}\u{11AB}") == .ok("한"))

    // ── 거부해야 하는 것 ──
    // 이모지 전부(단일·스킨톤·국기·ZWJ 가족·VS16 하트). 이것이 텍스트 전용 게이트의 존재 이유다:
    // 이모지를 받는 순간 Swift 자소 수와 Postgres 코드포인트 수가 갈린다(👨‍👩‍👧‍👦 = 1 vs 7).
    for text in ["👍", "👍🏻", "🇰🇷", "👨‍👩‍👧‍👦", "❤️", "👍👍👍"] {
        #expect(MessageBody.validate(text) == .unsupportedCharacters, "이모지는 거부해야 한다: \(text)")
    }
    // 가운데 개행·탭·제어문자는 **지우지 않고 거부한다** — 지우면 사용자가 안 쓴 말("가나")이 나간다.
    for text in ["가\n나", "가\tb", "가\u{07}나"] {
        #expect(MessageBody.validate(text) == .unsupportedCharacters, "제어문자는 거부해야 한다: \(text.debugDescription)")
    }
    // 기호와 허용 목록 밖 문장부호. 빠진 12자 `< > & \ $ % ` { } [ ] |` 는 마크업·이스케이프·템플릿
    // 의미가 있어 서버가 뺀 것들이라, 클라도 똑같이 막아야 한다.
    for text in ["♥", "＋", "가$", "①", "<b>", "a&b", "${}", "a|b", "a\\b", "[x]", "`x`"] {
        #expect(MessageBody.validate(text) == .unsupportedCharacters, "기호는 거부해야 한다: \(text)")
    }
    // ★ 글자가 아닌데 글자 행세를 하는 것들. 한자·가나·전각 라틴은 카테고리로는 '글자'라, 카테고리 판정으로
    //   열었다면 전부 통과했을 것이다 — 서버는 거부하므로 클라만 통과시키면 not_text 로 되돌아온다.
    // `٣`(아라비아-인도 숫자)까지 포함한다 — 카테고리로는 decimalNumber 라 '숫자'로 통과했을 것이다.
    for text in ["中", "あ", "Ａ", "ｱ", "é", "٣"] {
        #expect(MessageBody.validate(text) == .unsupportedCharacters, "서버 집합 밖 글자다: \(text)")
    }

    // ☠︎ ── 폭 0 채움 문자 3종: 이 저장소가 **실제로 뚫린 적 있는 구멍**이다 ──
    // U+3164(한글 채움)·U+115F(초성 채움)·U+1160(중성 채움)은 셋 다 카테고리가 otherLetter 라
    // "모든 Letter 허용" 방식이면 전부 통과한다. 통과하면 3글자를 이걸로 채운 **빈 말풍선**이 뜨고,
    // 별명에서 이미 같은 수법으로 사칭 사고가 났었다(20260804010000_display_name_change.sql:54-57).
    for value in [0x3164, 0x115F, 0x1160] {
        let filler = String(Unicode.Scalar(UInt32(value))!)
        // 카테고리 방식이었다면 통과했을 문자임을 함께 못 박는다 — 이 단언이 깨지면 위 설명이 낡은 것이다.
        #expect(Unicode.Scalar(UInt32(value))!.properties.generalCategory == .otherLetter)
        // 단독·3연속·정상 글자와의 혼합 모두 거부. 특히 3연속이 `.empty` 가 **아니라**
        // `.unsupportedCharacters` 여야 한다 — trim 이 이 문자들을 지우지 않기 때문이다(실측).
        #expect(MessageBody.validate(filler) == .unsupportedCharacters, "채움 문자 U+\(String(value, radix: 16))")
        #expect(MessageBody.validate(String(repeating: filler, count: 3)) == .unsupportedCharacters)
        #expect(MessageBody.validate("가\(filler)") == .unsupportedCharacters)
    }

    // 한글 음절 범위 바로 바깥(U+D7A4)도 거부된다.
    #expect(MessageBody.validate("\u{D7A4}") == .unsupportedCharacters)
    // 보이지 않는 문자: 가운데에 있으면 거부. (앞뒤는 trim 대상이라 잘려 나간다 — 공백 취급이 일관된다.)
    #expect(MessageBody.validate("가\u{200B}나") == .unsupportedCharacters)
    #expect(MessageBody.validate("\u{202E}가나") == .unsupportedCharacters)

    // ── 검사 순서 ──
    // 길이·문자를 둘 다 어긴 입력은 **문자 쪽**으로 답해야 한다. 길이로 답하면 사용자는 이모지를 줄이다가
    // 계속 거부당한다("3글자까지예요" → 3개로 줄임 → 또 거부).
    #expect(MessageBody.validate("👍👍👍👍") == .unsupportedCharacters)
    #expect(MessageBody.validate("가나다라") == .tooLong(maxCharacters: 3))

    // ── 서버 집합과의 1:1 전수 대조 ──
    // 표본 몇 개가 아니라 **ASCII 인쇄 문자 전부**를 돌린다. 두 집합이 갈리는 사고는 늘 "이 한 글자"에서
    // 나는데, 표본 테스트는 정확히 그 한 글자를 빠뜨린다. 서버 실증값: 문장부호 32자 = 허용 20 + 거부 12.
    let excludedByServer = Set("<>&\\$%`{}[]|".unicodeScalars)
    var allowedCount = 0
    var rejectedCount = 0
    for value in 0x21...0x7E {
        let scalar = Unicode.Scalar(UInt32(value))!
        let isAlphanumeric = (0x30...0x39).contains(value) || (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value)
        if isAlphanumeric { continue }
        let text = String(Character(scalar))
        if excludedByServer.contains(scalar) {
            #expect(MessageBody.validate(text) == .unsupportedCharacters, "서버가 뺀 12자다: \(text)")
            rejectedCount += 1
        } else {
            #expect(MessageBody.validate(text) == .ok(text), "서버가 허용하는 문장부호다: \(text)")
            allowedCount += 1
        }
    }
    #expect(allowedCount == 20)
    #expect(rejectedCount == 12)

    // ── 이 게이트가 사 오는 것: 자소 수 == 코드포인트 수 ──
    // 텍스트만 통과하면 Swift 가 세는 글자와 Postgres char_length 가 세는 글자가 **항상 같다**.
    // 서버/클라 판정이 갈릴 여지가 원리적으로 사라진다.
    for text in ["가나다", "ㅇㅋ", "abc", "밥?", "음~", "가 나"] {
        let normalized = MessageBody.sanitized(text)
        #expect(normalized.count == normalized.unicodeScalars.count, "자소 수와 코드포인트 수가 갈렸다: \(text)")
    }
}

// MARK: - 버전 게이트: take_pokes 인자 · 내 버전 보고 · 디렉토리 수신 가능 여부 (서비스 계층)
//
// v0.2.28 의 실사고에서 나온 트랙이다: 구버전 클라(≤0.2.27)는 모르는 kind 를 normal 로 접는 규약이라
// 3글자 메시지를 평범한 찔림으로 표시했고, take_pokes 는 **서버 원자 소비**라 그 글자는 영영 사라졌다.
// 서버가 메시지 행을 남겨 두고(p_message_capable 기본 false) 새 클라만 가져가는 것이 그 수습인데,
// 그 대가로 **인자 하나를 빠뜨리면 이 앱도 메시지를 못 받는다**. 아래 테스트들이 그 한 인자를 고정한다.

@Test
func takePokesCarriesMessageCapableArgument() async throws {
    let testHost = "take-msg-capable"
    TokenBoardURLProtocol.setResponse("[]", forHost: testHost)

    _ = try await messageService(host: testHost).takePokes(accessToken: "access-token")

    let url = try #require(TokenBoardURLProtocol.lastURL(forHost: testHost))
    #expect(url.path == "/rest/v1/rpc/take_pokes")
    let body = try #require(TokenBoardURLProtocol.lastBody(forHost: testHost))
    // ★ 이 한 줄이 기능의 스위치다. 빠지면 서버가 메시지 행을 남겨 두고, 사용자는 아무 말도 못 받는다.
    #expect(body.contains("\"p_message_capable\":true"))
    // 카멜케이스가 그대로 나가면 PostgREST 는 그 인자를 모르는 함수로 판단해 404 를 낸다.
    #expect(!body.contains("pMessageCapable"))
    // false 로 나가면 증상이 '인자 누락'과 **똑같아서** 원인을 화면에서 구분할 수 없다.
    #expect(!body.contains("\"p_message_capable\":false"))
}

@Test
func takePokesFallsBackWhenServerDoesNotKnowTheArgument() async throws {
    // ① 인자를 모르는 서버(db push 전). 새 모양이 PGRST202 로 죽어도 **찔림 수신 전체가 멈추면 안 된다** —
    //    옛 모양으로 한 번 더 부른다. 이게 없으면 앱 배포와 마이그레이션 사이의 창에서 메시지가 아니라
    //    콕찌르기까지 통째로 사라진다(그 사이 도착분은 서버에 남아 7일 cron 이 지운다).
    let oldHost = "take-old-server"
    let oldRows = try await messageService(host: oldHost, session: TakePokesArgumentURLProtocol.session())
        .takePokes(accessToken: "access-token")

    #expect(oldRows.map(\.id) == ["p1"])
    let oldBodies = TakePokesArgumentURLProtocol.bodies(forHost: oldHost)
    #expect(oldBodies.count == 2)                                  // 새 모양 1 + 폴백 1
    #expect(oldBodies.first?.contains("p_message_capable") == true)
    #expect(oldBodies.last?.contains("p_message_capable") == false) // 폴백은 인자 없는 옛 모양이다

    // ② 인자를 아는 서버에서는 폴백이 **절대 돌지 않는다**. 여기서 2건이 되면 폴백 조건이 너무 넓다는 뜻이고,
    //    그건 폴링마다 요청이 배로 나간다는 말이다(무료 플랜).
    let newHost = "take-new-server"
    let newRows = try await messageService(host: newHost, session: TakePokesArgumentURLProtocol.session())
        .takePokes(accessToken: "access-token")

    #expect(newRows.map(\.id) == ["m1"])
    #expect(newRows.first?.body == "고고")
    #expect(TakePokesArgumentURLProtocol.bodies(forHost: newHost).count == 1)

    // ③ 폴백은 '함수를 못 찾음'에만 붙는다. 그 밖의 실패(권한·네트워크)는 그대로 던져야 한다 —
    //    아니면 실패 한 번이 조용히 요청 두 번이 되고, 그 두 번째가 성공하면 문제가 숨는다.
    let deniedHost = "take-denied"
    await #expect(throws: (any Error).self) {
        _ = try await messageService(host: deniedHost, session: TakePokesArgumentURLProtocol.session())
            .takePokes(accessToken: "access-token")
    }
    #expect(TakePokesArgumentURLProtocol.bodies(forHost: deniedHost).count == 1)
}

@Test
func updateAppVersionPatchesOwnProfileRow() async throws {
    let testHost = "app-version-patch"
    TokenBoardURLProtocol.setResponse("[]", forHost: testHost)

    try await messageService(host: testHost).updateAppVersion(
        accessToken: "access-token",
        userID: "u1",
        report: AppVersionReport(build: 38, version: "0.2.29")
    )

    let url = try #require(TokenBoardURLProtocol.lastURL(forHost: testHost))
    #expect(url.path == "/rest/v1/profiles")
    // ?id=eq.<me> 가 없으면 **남의 행까지 대상**이 된다(RLS 가 막아 주지만 그건 두 번째 방어선이다).
    #expect(url.query?.contains("id=eq.u1") == true)
    #expect(TokenBoardURLProtocol.lastMethod(forHost: testHost) == "PATCH")

    let body = try #require(TokenBoardURLProtocol.lastBody(forHost: testHost))
    #expect(body.contains("\"app_build\":38"))
    #expect(body.contains("\"app_version\":\"0.2.29\""))
    // 카멜케이스로 나가면 PostgREST 는 '그런 컬럼 없음'으로 400 을 내고, 이 맥은 영영 구버전으로 남는다.
    #expect(!body.contains("appBuild"))
    #expect(!body.contains("appVersion"))
}

@Test
func appVersionReportStaysSilentWhenBuildIsNotPlanted() {
    // 정상 빌드(scripts/build-local.sh 가 심은 모양) — 문자열 정수 + 표시 버전.
    #expect(AppVersionReport.fromInfoDictionary(
        ["CFBundleVersion": "38", "CFBundleShortVersionString": "0.2.29"]
    ) == AppVersionReport(build: 38, version: "0.2.29"))
    // 도구에 따라 숫자로 들어오는 plist 도 받는다(못 읽는 것과 모양이 다른 것은 다른 사정이다).
    #expect(AppVersionReport.fromInfoDictionary(["CFBundleVersion": 38]) == AppVersionReport(build: 38, version: ""))

    // ★ 아래가 이 함수의 존재 이유다. **못 읽으면 침묵한다** — 여기서 0 이나 폴백 숫자를 만들어 올리면
    //   서버가 나를 구버전으로 보고 **남이 나에게 메시지를 못 보내게** 만든다(개발 빌드에서 실제로 벌어진다).
    #expect(AppVersionReport.fromInfoDictionary(nil) == nil)                                   // Info.plist 자체가 없음
    #expect(AppVersionReport.fromInfoDictionary([:]) == nil)                                   // 키 없음
    #expect(AppVersionReport.fromInfoDictionary(["CFBundleVersion": "dev"]) == nil)            // 정수가 아님
    #expect(AppVersionReport.fromInfoDictionary(["CFBundleVersion": ""]) == nil)               // 빈 문자열
    #expect(AppVersionReport.fromInfoDictionary(["CFBundleVersion": "0"]) == nil)              // 안 심은 값
    #expect(AppVersionReport.fromInfoDictionary(["CFBundleVersion": "-3"]) == nil)             // 말이 안 되는 값
}

@Test
func pokeDirectoryCarriesMessageCapabilityAndSurvivesItsAbsence() async throws {
    let testHost = "poke-directory-capability"
    // 세 행: (1) 서버 어휘 message_capable, (2) 대체 어휘 can_receive_message,
    //        (3) **컬럼이 없는 서버** — 키 자체가 없다.
    TokenBoardURLProtocol.setResponse(
        """
        [
          {"user_id": "u1", "display_name": "영식", "avatar_url": null, "is_working": true,  "message_capable": true},
          {"user_id": "u2", "display_name": "민수", "avatar_url": null, "is_working": true,  "can_receive_message": false},
          {"user_id": "u3", "display_name": "지현", "avatar_url": null, "is_working": false}
        ]
        """,
        forHost: testHost
    )

    let rows = try await messageService(host: testHost).fetchPokeDirectory(accessToken: "access-token")

    // 세 행 모두 살아야 한다. 비옵셔널이었다면 (3) 하나 때문에 배열 전체가 throw 되어 **콕찌르기 목록이
    // 전원 사라진다** — 새 기능 하나를 위해 기존 기능을 서버 배포 순서에 인질로 잡는 셈이다.
    #expect(rows.count == 3)
    #expect(rows.first { $0.userId == "u1" }?.canReceiveMessage == true)
    #expect(rows.first { $0.userId == "u2" }?.canReceiveMessage == false)
    #expect(rows.first { $0.userId == "u3" }?.canReceiveMessage == nil)   // 모른다 ≠ 못 받는다

    // 표시 엔트리로 옮길 때 '모름'은 **허용**으로 읽는다. false 로 접으면 컬럼이 없는 서버에서 전원의
    // 메시지 버튼이 꺼져 기능이 통째로 멈춘다(클라가 서버에 없는 금지를 발명하는 셈이다).
    let entries = rows.toPokeDirectoryEntries()
    #expect(entries.first { $0.userID == "u1" }?.canReceiveMessage == true)
    #expect(entries.first { $0.userID == "u2" }?.canReceiveMessage == false)
    #expect(entries.first { $0.userID == "u3" }?.canReceiveMessage == true)
    // 기존 필드는 한 톨도 안 변했다(대조군).
    #expect(entries.first { $0.userID == "u3" }?.isWorking == false)
    #expect(entries.first { $0.userID == "u1" }?.name == "영식")
}

@Test
func sendMessageClassifiesTargetOutdated() async throws {
    let testHost = "msg-status-outdated"
    TokenBoardURLProtocol.setResponse(#"{"status":"target_outdated"}"#, forHost: testHost)

    let response = try await messageService(host: testHost)
        .sendMessage(accessToken: "access-token", to: "target-user-id", body: "가나다")

    // .invalid 로 접히면 사용자는 "지금은 보낼 수 없어요"만 보고 **할 수 있는 일이 없다고** 배운다.
    // 실제로는 할 일이 있다: 상대에게 업데이트를 알리는 것.
    #expect(MessageSendOutcome(response: response) == .targetOutdated)
    #expect(MessageSendOutcome(response: response) != .invalid)

    // 대조군: 기존 status 6종의 분류는 한 톨도 안 변했다(새 케이스가 남의 자리를 먹지 않았는지).
    #expect(MessageSendOutcome(response: PokeSendResponse(status: "ok")) == .ok)
    #expect(MessageSendOutcome(response: PokeSendResponse(status: "target_not_working")) == .targetNotWorking)
    #expect(MessageSendOutcome(response: PokeSendResponse(status: "target_focused")) == .targetFocused)
    #expect(MessageSendOutcome(response: PokeSendResponse(status: "too_long")) == .tooLong)
    #expect(MessageSendOutcome(response: PokeSendResponse(status: "not_working")) == .notWorking)
    #expect(MessageSendOutcome(response: PokeSendResponse(status: "뭔가또새로운것")) == .invalid)
}

/// 세션 주입형 오버로드. 기본 messageService 는 TokenBoardURLProtocol 을 쓰는데, 폴백 검증에는
/// **요청마다 다른 응답**(첫 요청 404 → 둘째 200)이 필요해 전용 스텁을 꽂는다.
private func messageService(host: String, session: URLSession) -> SupabaseWorkService {
    SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: session
    )
}

/// take_pokes 인자 폴백 전용 스텁. 시나리오는 **호스트가 고르고**, 응답은 **요청 본문이 고른다** —
/// 전역 가변 카운터로 "첫 요청/둘째 요청"을 나누면 병렬 스위트가 서로의 순번을 먹어 무음으로 뒤집힌다
/// (URLProtocolStub.delayedHosts 주석의 그 사고). 본문 분기는 그 상태가 아예 없다.
final class TakePokesArgumentURLProtocol: URLProtocol {
    private nonisolated(unsafe) static var bodiesByHost: [String: [String]] = [:]
    private static let stateLock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TakePokesArgumentURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func bodies(forHost host: String) -> [String] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return bodiesByHost[host, default: []]
    }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let body = Self.bodyText(from: request)
        Self.stateLock.lock()
        Self.bodiesByHost[host, default: []].append(body)
        Self.stateLock.unlock()

        let (statusCode, json) = Self.outcome(host: host, body: body)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func outcome(host: String, body: String) -> (Int, String) {
        let carriesArgument = body.contains("p_message_capable")
        switch host {
        case "take-old-server":
            // 실제 PGRST202 문구(인자 집합으로 함수를 못 찾은 경우). "schema cache" 를 포함하므로
            // 공용 매핑이 .databaseSchemaMissing 으로 분류한다 — 폴백이 잡는 신호가 바로 이것이다.
            if carriesArgument {
                return (404, #"{"code":"PGRST202","message":"Could not find the function public.take_pokes(p_message_capable) in the schema cache","hint":"Perhaps you meant to call the function public.take_pokes"}"#)
            }
            return (200, #"[{"id":"p1","from_user":"u1","from_display_name":"영식","from_avatar_url":null,"created_epoch":1721000000,"kind":"normal","body":null}]"#)
        case "take-denied":
            // 함수는 있는데 실행 권한이 없는 서버. 폴백이 여기까지 번지면 안 된다.
            return (403, #"{"code":"42501","message":"permission denied for function take_pokes"}"#)
        default:
            return (200, #"[{"id":"m1","from_user":"u1","from_display_name":"영식","from_avatar_url":null,"created_epoch":1721000000,"kind":"message","body":"고고"}]"#)
        }
    }

    private static func bodyText(from request: URLRequest) -> String {
        if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
