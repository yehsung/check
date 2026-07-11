import Foundation

actor SupabaseWorkService {
    let projectURL: URL
    let anonKey: String?
    let session: URLSession
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    let dateFormatter = ISO8601DateFormatter()

    init(
        projectURL: URL = SupabaseConfig.projectURL,
        anonKey: String? = SupabaseConfig.anonKey(),
        session: URLSession = .shared
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

    func signUp(email: String, password: String, displayName: String, teamID: String) async throws -> SupabaseSession? {
        let body = SignUpRequest(email: email, password: password, data: ["display_name": displayName, "team_id": teamID])
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
        let data = try await send(
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
        let rows = try decoder.decode([WorkStatusRow].self, from: data)
        let activeSessions = try await fetchActiveSessions(accessToken: accessToken, teamID: teamID)
        let weeklySessions = try await fetchWeeklySessions(accessToken: accessToken, teamID: teamID, now: now)
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

    func startWork(accessToken: String, teamID: String, userID: String, sessionID: String) async throws {
        try await sendNoBody(
            path: "/rest/v1/work_sessions",
            method: "POST",
            body: StartSessionRequest(
                id: sessionID,
                teamId: teamID,
                userId: userID,
                startedAt: dateFormatter.string(from: Date())
            ),
            accessToken: accessToken,
            prefer: "return=minimal"
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

    /// 가입 화면 팀 목록. team_directory() RPC 를 anon 토큰으로 호출한다(accessToken 없이 anonKey Bearer).
    /// invite_code 는 RPC 가 반환하지 않으므로 노출되지 않는다.
    func fetchTeamDirectory() async throws -> [TeamDirectoryEntry] {
        let data = try await send(
            path: "/rest/v1/rpc/team_directory",
            method: "POST",
            body: EmptyBody(),
            accessToken: nil,
            prefer: nil
        )
        let rows = try decoder.decode([TeamDirectoryRow].self, from: data)
        return rows.map { TeamDirectoryEntry(id: $0.id, name: $0.name) }
    }

    /// 로그인 후 내 팀을 확정한다. 소속이 없으면 nil.
    func fetchOwnMembership(accessToken: String, userID: String) async throws -> (teamID: String, teamName: String)? {
        let data = try await send(
            path: "/rest/v1/memberships",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "team_id,teams(name)"),
                URLQueryItem(name: "user_id", value: "eq.\(userID)"),
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
        return (teamID: row.teamId, teamName: row.teams?.name ?? "팀")
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
