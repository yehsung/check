import Foundation

actor SupabaseWorkService {
    let projectURL: URL
    let anonKey: String?
    let session: URLSession
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    let dateFormatter = ISO8601DateFormatter()

    /// 폴링 전용 세션. 요청 15초/리소스 30초 타임아웃(30초 폴링·90초 신선도 규약과 정합).
    /// 앱 전역 .shared 대신 전용 구성을 써 무한 대기·백그라운드 재시도가 티커/폴링 주기와 어긋나지 않게 한다.
    static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    init(
        projectURL: URL = SupabaseConfig.projectURL,
        anonKey: String? = SupabaseConfig.anonKey(),
        session: URLSession = SupabaseWorkService.defaultSession
    ) {
        self.projectURL = projectURL
        self.anonKey = anonKey
        self.session = session
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        let body = SignInRequest(email: email, password: password)
        let data = try await send(
            path: "/auth/v1/token",
            method: "POST",
            queryItems: [URLQueryItem(name: "grant_type", value: "password")],
            body: body,
            accessToken: nil,
            prefer: nil
        )
        let response = try decoder.decode(SignInResponse.self, from: data)
        return SupabaseSession(accessToken: response.accessToken, refreshToken: response.refreshToken, userID: response.user.id)
    }

    /// 계정만 만든다. 팀 합류/생성은 가입 성공 후 스토어가 join_team/create_team 을 명시적으로 호출한다
    /// (트리거는 더 이상 팀을 만들지 않으므로 team_id 메타데이터를 보내지 않는다).
    func signUp(email: String, password: String, displayName: String) async throws -> SupabaseSession? {
        let body = SignUpRequest(email: email, password: password, data: ["display_name": displayName])
        let data = try await send(
            path: "/auth/v1/signup",
            method: "POST",
            body: body,
            accessToken: nil,
            prefer: nil
        )
        let response = try decoder.decode(SignUpResponse.self, from: data)
        guard let accessToken = response.accessToken else {
            return nil
        }
        return SupabaseSession(accessToken: accessToken, refreshToken: response.refreshToken, userID: response.user.id)
    }

    func refreshSession(refreshToken: String) async throws -> SupabaseSession {
        let body = RefreshSessionRequest(refreshToken: refreshToken)
        let data = try await send(
            path: "/auth/v1/token",
            method: "POST",
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: body,
            accessToken: nil,
            prefer: nil
        )
        let response = try decoder.decode(SignInResponse.self, from: data)
        return SupabaseSession(accessToken: response.accessToken, refreshToken: response.refreshToken, userID: response.user.id)
    }

    func fetchTeamStatuses(accessToken: String, teamID: String, now: Date = Date()) async throws -> [TeamMemberStatus] {
        // work_statuses·활성·주간 세 GET을 병렬 발사한다. 각 요청은 network await 에서 액터를 놓으므로
        // 직렬 3연속 왕복이 아니라 실제로 겹쳐 폴링 경로 지연을 줄인다.
        async let statusBytes = send(
            path: "/rest/v1/work_statuses",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "user_id,status,updated_at,last_seen_at,active_session_id,profiles(display_name,email,avatar_url)"),
                URLQueryItem(name: "team_id", value: "eq.\(teamID)"),
                URLQueryItem(name: "order", value: "updated_at.desc")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        async let activeRows = fetchActiveSessions(accessToken: accessToken, teamID: teamID)
        async let weeklyRows = fetchWeeklySessions(accessToken: accessToken, teamID: teamID, now: now)

        let rows = try decoder.decode([WorkStatusRow].self, from: try await statusBytes)
        let activeSessions = try await activeRows
        let weeklySessions = try await weeklyRows
        let activeByUser = Dictionary(grouping: activeSessions, by: \.userId)
        let weeklyByUser = weeklyDurations(from: weeklySessions, now: now)
        let todayByUser = todayDurations(from: weeklySessions, now: now)
        return rows.map { row in
            let activeStartedAt = activeByUser[row.userId]?.compactMap { parseDate($0.startedAt) }.min()
            let avatarURL = (row.profiles?.avatarUrl).flatMap { URL(string: $0) }
            return TeamMemberStatus(
                id: row.userId,
                name: row.profiles?.displayName ?? row.profiles?.email ?? "팀원",
                status: row.status == "working" ? .working : .offWork,
                updatedAt: row.updatedAt.flatMap(parseDate),
                currentSessionStartedAt: activeStartedAt,
                weeklyDurationSeconds: weeklyByUser[row.userId, default: 0],
                todayDurationSeconds: todayByUser[row.userId, default: 0],
                avatarURL: avatarURL,
                lastSeenAt: row.lastSeenAt.flatMap(parseDate),
                activeSessionID: row.activeSessionId
            )
        }
    }

    private func fetchActiveSessions(accessToken: String, teamID: String) async throws -> [WorkSessionRow] {
        let data = try await send(
            path: "/rest/v1/work_sessions",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "id,user_id,started_at,ended_at,duration_seconds"),
                URLQueryItem(name: "team_id", value: "eq.\(teamID)"),
                URLQueryItem(name: "ended_at", value: "is.null")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode([WorkSessionRow].self, from: data)
    }

    private func fetchWeeklySessions(accessToken: String, teamID: String, now: Date) async throws -> [WorkSessionRow] {
        let data = try await send(
            path: "/rest/v1/work_sessions",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "id,user_id,started_at,ended_at,duration_seconds"),
                URLQueryItem(name: "team_id", value: "eq.\(teamID)"),
                URLQueryItem(name: "ended_at", value: "not.is.null"),
                // 경계 걸친 세션(예: 일요일 23시~월요일 1시)을 놓치지 않도록 '주와 겹침' 기준으로 조회한다.
                // started_at gte 는 주 시작 이전에 시작한 세션을 통째로 누락시키는 실버그였다.
                URLQueryItem(name: "ended_at", value: "gte.\(dateFormatter.string(from: weekStart(for: now)))")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode([WorkSessionRow].self, from: data)
    }

    private func weeklyDurations(from rows: [WorkSessionRow], now: Date) -> [String: Int] {
        let window = weekStart(for: now)
        return rows.reduce(into: [:]) { totals, row in
            let contribution = clippedContribution(for: row, windowStart: window, now: now)
            guard contribution > 0 else {
                return
            }
            totals[row.userId, default: 0] += contribution
        }
    }

    private func todayDurations(from rows: [WorkSessionRow], now: Date) -> [String: Int] {
        let dayStart = TeamWeeklyGoal.koreanDayStart(for: now)
        return rows.reduce(into: [:]) { totals, row in
            let contribution = clippedContribution(for: row, windowStart: dayStart, now: now)
            guard contribution > 0 else {
                return
            }
            totals[row.userId, default: 0] += contribution
        }
    }

    /// 세션 구간 [started, ended] 를 [windowStart, now] 로 클리핑한 기여 시간(초).
    /// 저장된 duration_seconds 가 아니라 타임스탬프 구간을 써서 경계에 걸친 세션의 부분만 귀속한다.
    /// contribution = max(0, min(ended, now) − max(started, windowStart)).
    private func clippedContribution(for row: WorkSessionRow, windowStart: Date, now: Date) -> Int {
        guard let started = parseDate(row.startedAt), let ended = row.endedAt.flatMap(parseDate) else {
            return 0
        }
        let clippedStart = max(started, windowStart)
        let clippedEnd = min(ended, now)
        return max(0, Int(clippedEnd.timeIntervalSince(clippedStart)))
    }

    private func weekStart(for now: Date) -> Date {
        TeamWeeklyGoal.koreanWeekStart(for: now)
    }

    private func parseDate(_ value: String) -> Date? {
        dateFormatter.date(from: value)
    }

    func startWork(accessToken: String, teamID: String, userID: String, sessionID: String, startedAt: Date = Date()) async throws {
        // 큐 재재생으로 이미 닫힌 동일 id 세션에 다시 POST 돼도 무해하도록 멱등화한다(stopWork fallback 과 동일 패턴).
        // on_conflict=id + resolution=ignore-duplicates 로 중복 id 는 서버가 조용히 무시한다(409 소멸).
        try await sendNoBody(
            path: "/rest/v1/work_sessions",
            method: "POST",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            body: StartSessionRequest(
                id: sessionID,
                teamId: teamID,
                userId: userID,
                startedAt: dateFormatter.string(from: startedAt)
            ),
            accessToken: accessToken,
            prefer: "resolution=ignore-duplicates,return=minimal"
        )
        try await upsertStatus(accessToken: accessToken, teamID: teamID, userID: userID, status: "working", activeSessionID: sessionID)
    }

    func stopWork(accessToken: String, teamID: String, userID: String, startedAt: Date, endedAt: Date, durationSeconds: Int, fallbackSessionID: String) async throws {
        let patched = try await send(
            path: "/rest/v1/work_sessions",
            method: "PATCH",
            queryItems: [
                URLQueryItem(name: "team_id", value: "eq.\(teamID)"),
                URLQueryItem(name: "user_id", value: "eq.\(userID)"),
                URLQueryItem(name: "ended_at", value: "is.null")
            ],
            body: StopSessionRequest(
                endedAt: dateFormatter.string(from: endedAt),
                durationSeconds: max(0, durationSeconds)
            ),
            accessToken: accessToken,
            prefer: "return=representation"
        )
        let updatedRows = (try? decoder.decode([WorkSessionRow].self, from: patched)) ?? []
        if updatedRows.isEmpty {
            try await sendNoBody(
                path: "/rest/v1/work_sessions",
                method: "POST",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                body: CompletedSessionRequest(
                    id: fallbackSessionID,
                    teamId: teamID,
                    userId: userID,
                    startedAt: dateFormatter.string(from: startedAt),
                    endedAt: dateFormatter.string(from: endedAt),
                    durationSeconds: max(0, durationSeconds)
                ),
                accessToken: accessToken,
                prefer: "resolution=ignore-duplicates,return=minimal"
            )
        }
        try await upsertStatus(accessToken: accessToken, teamID: teamID, userID: userID, status: "off_work", activeSessionID: nil)
    }

    /// 근무중 생존신호. work_statuses.last_seen_at(+updated_at)을 현재 시각으로 갱신한다.
    /// upsertStatus 를 재사용하므로 active_session_id 도 유지된다.
    func heartbeat(accessToken: String, teamID: String, userID: String, sessionID: String) async throws {
        try await upsertStatus(accessToken: accessToken, teamID: teamID, userID: userID, status: "working", activeSessionID: sessionID)
    }

    /// 방치 세션 서버 자동 마감 RPC. close_abandoned_work_sessions() 를 로그인 토큰으로 호출하고
    /// 마감된 세션 수(int)를 돌려받는다. 서버 cron 이 주 경로이고 이건 클라 스캐빈저 폴백에서 쓴다.
    /// 스칼라 int 반환 RPC 라 PostgREST 가 본문에 숫자 하나(예: 3)를 준다 — 그대로 파싱한다(빈/비정상 응답은 0).
    func closeAbandonedSessions(accessToken: String) async throws -> Int {
        let data = try await send(
            path: "/rest/v1/rpc/close_abandoned_work_sessions",
            method: "POST",
            body: EmptyBody(),
            accessToken: accessToken,
            prefer: nil
        )
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(text) ?? 0
    }

    /// 자동 마감한 세션을 되돌린다. ended_at/duration_seconds 를 null 로 재개하고 상태를 working 으로 복구.
    /// 유니크 인덱스(work_sessions_one_open_per_user)상 다른 열린 세션이 없을 때만 안전하다.
    func reopenSession(accessToken: String, teamID: String, userID: String, sessionID: String) async throws {
        try await sendNoBody(
            path: "/rest/v1/work_sessions",
            method: "PATCH",
            queryItems: [
                URLQueryItem(name: "team_id", value: "eq.\(teamID)"),
                URLQueryItem(name: "id", value: "eq.\(sessionID)")
            ],
            body: ReopenSessionRequest(),
            accessToken: accessToken,
            prefer: "return=minimal"
        )
        try await upsertStatus(accessToken: accessToken, teamID: teamID, userID: userID, status: "working", activeSessionID: sessionID)
    }

    func uploadAvatar(accessToken: String, userID: String, imageData: Data) async throws -> String {
        _ = try await sendData(
            path: "/storage/v1/object/avatars/\(userID).jpg",
            method: "POST",
            body: imageData,
            contentType: "image/jpeg",
            accessToken: accessToken,
            extraHeaders: ["x-upsert": "true"]
        )
        let cacheBuster = Int(Date().timeIntervalSince1970)
        let avatarURL = "\(projectURL.absoluteString)/storage/v1/object/public/avatars/\(userID).jpg?v=\(cacheBuster)"
        try await sendNoBody(
            path: "/rest/v1/profiles",
            method: "PATCH",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(userID)")],
            body: AvatarUpdateRequest(avatarUrl: avatarURL),
            accessToken: accessToken,
            prefer: "return=minimal"
        )
        return avatarURL
    }

    func signOut(accessToken: String) async {
        _ = try? await send(
            path: "/auth/v1/logout",
            method: "POST",
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
    }

    /// 팀 코드 정규화: 대문자화 후 공백/하이픈 제거. 클라에서도 적용해 정규화된 코드만 서버로 보낸다.
    static func normalizeInviteCode(_ code: String) -> String {
        code.uppercased().filter { !$0.isWhitespace && $0 != "-" }
    }

    /// 팀 코드 미리보기. lookup_team_by_code(code) RPC 를 anon Bearer(accessToken 없이)로 호출한다.
    /// 가입 전에도 쓰이므로 로그인 토큰이 필요 없다. 못 찾으면 nil.
    func lookupTeamByCode(code: String) async throws -> TeamJoinPreview? {
        let data = try await send(
            path: "/rest/v1/rpc/lookup_team_by_code",
            method: "POST",
            body: InviteCodeRequest(code: Self.normalizeInviteCode(code)),
            accessToken: nil,
            prefer: nil
        )
        let rows = try decoder.decode([TeamJoinPreviewRow].self, from: data)
        guard let row = rows.first else {
            return nil
        }
        return TeamJoinPreview(
            teamID: row.teamId,
            name: row.name,
            weeklyGoalHours: row.weeklyGoalHours,
            memberCount: row.memberCount
        )
    }

    /// 코드로 팀 합류. join_team(code) RPC 를 로그인 토큰으로 호출한다. 불일치/비로그인은 0행 → nil.
    func joinTeam(accessToken: String, code: String) async throws -> (teamID: String, name: String, goalHours: Int)? {
        let data = try await send(
            path: "/rest/v1/rpc/join_team",
            method: "POST",
            body: InviteCodeRequest(code: Self.normalizeInviteCode(code)),
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([JoinTeamRow].self, from: data)
        guard let row = rows.first else {
            return nil
        }
        return (teamID: row.teamId, name: row.name, goalHours: row.weeklyGoalHours)
    }

    /// 새 팀 만들기. create_team(team_name, goal_hours) RPC 를 로그인 토큰으로 호출하고 참여코드를 함께 받는다.
    func createTeam(accessToken: String, name: String, goalHours: Int) async throws -> (teamID: String, name: String, inviteCode: String, goalHours: Int) {
        let data = try await send(
            path: "/rest/v1/rpc/create_team",
            method: "POST",
            body: CreateTeamRequest(teamName: name, goalHours: goalHours),
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([CreateTeamRow].self, from: data)
        guard let row = rows.first else {
            throw SupabaseWorkServiceError.invalidResponse(200)
        }
        return (teamID: row.teamId, name: row.name, inviteCode: row.inviteCode, goalHours: row.weeklyGoalHours)
    }

    /// 내 팀 참여코드(소속 팀원 전체 공개). my_team_invite_code() RPC 를 로그인 토큰으로 호출한다.
    /// 코드가 곧 열쇠이므로 owner 뿐 아니라 팀원 누구나 조회해 새 동료를 초대할 수 있다. 무소속이면 nil.
    func fetchMyInviteCode(accessToken: String) async throws -> String? {
        let data = try await send(
            path: "/rest/v1/rpc/my_team_invite_code",
            method: "POST",
            body: EmptyBody(),
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([InviteCodeRow].self, from: data)
        return rows.first?.inviteCode
    }

    /// 팀 주간 목표시간 변경(팀원 누구나). set_team_weekly_goal(goal_hours) RPC 를 로그인 토큰으로 호출하고
    /// 서버가 반영한 새 목표시간(정수, 시간)을 돌려받는다. 범위(1~168) 최종 검증은 서버가 담당한다.
    func setTeamWeeklyGoal(accessToken: String, goalHours: Int) async throws -> Int {
        let data = try await send(
            path: "/rest/v1/rpc/set_team_weekly_goal",
            method: "POST",
            body: SetTeamGoalRequest(goalHours: goalHours),
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([SetTeamGoalRow].self, from: data)
        guard let row = rows.first else {
            throw SupabaseWorkServiceError.invalidResponse(200)
        }
        return row.weeklyGoalHours
    }

    /// 팀 리그(이번 주 팀별 총 근무시간). team_weekly_leaderboard() RPC 를 로그인 토큰으로 호출한다.
    /// RPC 는 모든 팀의 총합/목표/인원/근무중 인원만 반환하며 invite_code 는 노출하지 않는다.
    func fetchTeamLeaderboard(accessToken: String) async throws -> [TeamLeaderboardEntry] {
        let data = try await send(
            path: "/rest/v1/rpc/team_weekly_leaderboard",
            method: "POST",
            body: EmptyBody(),
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([TeamLeaderboardRow].self, from: data)
        return rows.map {
            TeamLeaderboardEntry(
                id: $0.teamId,
                name: $0.teamName,
                weeklyGoalHours: $0.weeklyGoalHours,
                totalSeconds: $0.totalSeconds,
                workingCount: $0.workingCount,
                // member_count 를 안 내려주는 구버전 RPC 는 nil → 0(평균 0명 가드).
                memberCount: $0.memberCount ?? 0
            )
        }
    }

    /// 로그인 후 내 팀을 확정한다. 소속이 없으면 nil.
    /// 목표시간(goalHours)은 teams.weekly_goal_hours 를 그대로 읽어 온다(같은 쿼리라 추가 요청 없음).
    /// 누락/null 이면 기본 목표(60시간)로 폴백한다.
    func fetchOwnMembership(accessToken: String, userID: String) async throws -> (teamID: String, teamName: String, goalHours: Int, role: String)? {
        let data = try await send(
            path: "/rest/v1/memberships",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "team_id,role,teams(name,weekly_goal_hours)"),
                URLQueryItem(name: "user_id", value: "eq.\(userID)"),
                // 다중 소속일 때 '주 팀' 선택 규칙을 서버 함수(가입 먼저 → team_id 순)와 통일한다.
                URLQueryItem(name: "order", value: "joined_at.asc,team_id.asc"),
                URLQueryItem(name: "limit", value: "1")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([MembershipRow].self, from: data)
        guard let row = rows.first else {
            return nil
        }
        return (
            teamID: row.teamId,
            teamName: row.teams?.name ?? "팀",
            goalHours: row.teams?.weeklyGoalHours ?? TeamWeeklyGoal.defaultGoalHours,
            role: row.role ?? "member"
        )
    }

    /// 내 이번 달 AI 토큰 사용량을 서버 원장에 upsert 한다. (user_id, month) 충돌 시 merge-duplicates 로 갱신한다.
    /// 반환 없음(return=minimal) — 표시는 별도 fetchTokenBoard 로 다시 읽는다. usage.month 는 D1 이 계산한 KST 'YYYY-MM'.
    func upsertTokenUsage(accessToken: String, userID: String, usage: TokenUsageMonthly) async throws {
        try await sendNoBody(
            path: "/rest/v1/token_usage_monthly",
            method: "POST",
            queryItems: [URLQueryItem(name: "on_conflict", value: "user_id,month")],
            body: TokenUsageUpsertRequest(
                userId: userID,
                month: usage.month,
                claudeInput: usage.claudeInput,
                claudeOutput: usage.claudeOutput,
                claudeCacheRead: usage.claudeCacheRead,
                claudeCacheCreation: usage.claudeCacheCreation,
                codexInput: usage.codexInput,
                codexOutput: usage.codexOutput,
                total: usage.total,
                todayTotal: usage.todayTotal,
                todayDate: usage.todayDate
            ),
            accessToken: accessToken,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    /// 이번 달 토큰 사용량 순위를 조회한다(앱 사용자 전체 공개). token_usage_board(p_month) RPC 를 로그인 토큰으로
    /// 호출한다 — 팀 무관 전체 사용자 행을 profiles 와 조인해 이름/아바타까지 담아 돌려주므로(행 자체 완결), 팀원 목록
    /// 결합이 필요 없다. 서버가 총합 내림차순으로 정렬해 주지만 신뢰하지 않고 클라가 다시 정렬한다.
    func fetchTokenBoard(accessToken: String, month: String) async throws -> [TokenBoardRow] {
        let data = try await send(
            path: "/rest/v1/rpc/token_usage_board",
            method: "POST",
            body: TokenBoardRequest(pMonth: month),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode([TokenBoardRow].self, from: data)
    }

    // MARK: - 콕찌르기 / 토큰 사용량 공개 설정

    /// 대상에게 콕 찌르기. poke_user(p_to) RPC 를 로그인 토큰으로 호출한다. 근무중 게이트·60초 쿨타임은 서버가 강제한다.
    /// 반환은 jsonb 단일 객체(배열 아님)라 PokeSendResponse 로 직접 디코드한다({status, retry_after_seconds?}).
    func sendPoke(accessToken: String, to userID: String) async throws -> PokeSendResponse {
        let data = try await send(
            path: "/rest/v1/rpc/poke_user",
            method: "POST",
            body: PokeSendRequest(pTo: userID),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(PokeSendResponse.self, from: data)
    }

    /// 내게 온 미소비 찔림을 원자적으로 수신+소비한다. take_pokes() RPC 를 로그인 토큰으로 호출한다(인자 없음 → EmptyBody).
    /// 반환 행은 보낸이 표시명/아바타 + 찔린 시각 epoch 초를 담는다(클라가 Date 로 복원해 신선도 필터).
    func takePokes(accessToken: String) async throws -> [TakenPokeRow] {
        let data = try await send(
            path: "/rest/v1/rpc/take_pokes",
            method: "POST",
            body: EmptyBody(),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode([TakenPokeRow].self, from: data)
    }

    /// 콕찌르기 대상 디렉토리(앱 사용자 전체, 본인 제외 + 근무중 여부). app_user_directory() RPC 를 로그인 토큰으로 호출한다.
    func fetchPokeDirectory(accessToken: String) async throws -> [PokeDirectoryRow] {
        let data = try await send(
            path: "/rest/v1/rpc/app_user_directory",
            method: "POST",
            body: EmptyBody(),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode([PokeDirectoryRow].self, from: data)
    }

    /// 내 토큰 사용량 공개 여부 조회. profiles 자기 행의 token_usage_public 을 GET 한다. 행/컬럼 누락 시 기본 공개(true) 폴백.
    func fetchTokenUsagePublic(accessToken: String, userID: String) async throws -> Bool {
        let data = try await send(
            path: "/rest/v1/profiles",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(userID)"),
                URLQueryItem(name: "select", value: "token_usage_public")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([ProfilePrivacyRow].self, from: data)
        return rows.first?.tokenUsagePublic ?? true
    }

    /// 내 토큰 사용량 공개 여부 갱신. profiles 자기 행을 PATCH 한다(RLS 로 본인 행만 허용). 반환 없음(return=minimal).
    func updateTokenUsagePublic(accessToken: String, userID: String, isPublic: Bool) async throws {
        try await sendNoBody(
            path: "/rest/v1/profiles",
            method: "PATCH",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(userID)")],
            body: ProfilePrivacyUpdateRequest(tokenUsagePublic: isPublic),
            accessToken: accessToken,
            prefer: "return=minimal"
        )
    }

    private func upsertStatus(accessToken: String, teamID: String, userID: String, status: String, activeSessionID: String?) async throws {
        try await sendNoBody(
            path: "/rest/v1/work_statuses",
            method: "POST",
            queryItems: [URLQueryItem(name: "on_conflict", value: "team_id,user_id")],
            body: StatusUpsertRequest(
                teamId: teamID,
                userId: userID,
                status: status,
                activeSessionId: activeSessionID,
                lastSeenAt: dateFormatter.string(from: Date()),
                updatedAt: dateFormatter.string(from: Date())
            ),
            accessToken: accessToken,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

}
