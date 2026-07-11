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

    func fetchTeamStatuses(accessToken: String) async throws -> [TeamMemberStatus] {
        let data = try await send(
            path: "/rest/v1/work_statuses",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "user_id,status,updated_at,active_session_id,profiles(display_name,email)"),
                URLQueryItem(name: "team_id", value: "eq.\(SupabaseConfig.teamID)"),
                URLQueryItem(name: "order", value: "updated_at.desc")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([WorkStatusRow].self, from: data)
        let activeSessions = try await fetchActiveSessions(accessToken: accessToken)
        let weeklySessions = try await fetchWeeklySessions(accessToken: accessToken)
        let activeByUser = Dictionary(grouping: activeSessions, by: \.userId)
        let weeklyByUser = weeklyDurations(from: weeklySessions)
        return rows.map { row in
            let activeStartedAt = activeByUser[row.userId]?.compactMap { parseDate($0.startedAt) }.min()
            return TeamMemberStatus(
                id: row.userId,
                name: row.profiles?.displayName ?? row.profiles?.email ?? "팀원",
                status: row.status == "working" ? .working : .offWork,
                updatedAt: row.updatedAt.flatMap(parseDate),
                currentSessionStartedAt: activeStartedAt,
                weeklyDurationSeconds: weeklyByUser[row.userId, default: 0]
            )
        }
    }

    private func fetchActiveSessions(accessToken: String) async throws -> [WorkSessionRow] {
        let data = try await send(
            path: "/rest/v1/work_sessions",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "id,user_id,started_at,ended_at,duration_seconds"),
                URLQueryItem(name: "team_id", value: "eq.\(SupabaseConfig.teamID)"),
                URLQueryItem(name: "ended_at", value: "is.null")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode([WorkSessionRow].self, from: data)
    }

    private func fetchWeeklySessions(accessToken: String) async throws -> [WorkSessionRow] {
        let data = try await send(
            path: "/rest/v1/work_sessions",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "id,user_id,started_at,ended_at,duration_seconds"),
                URLQueryItem(name: "team_id", value: "eq.\(SupabaseConfig.teamID)"),
                URLQueryItem(name: "ended_at", value: "not.is.null"),
                URLQueryItem(name: "started_at", value: "gte.\(dateFormatter.string(from: weekStart()))")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode([WorkSessionRow].self, from: data)
    }

    private func weeklyDurations(from rows: [WorkSessionRow]) -> [String: Int] {
        return rows.reduce(into: [:]) { totals, row in
            guard let duration = row.durationSeconds ?? row.endedAt.flatMap(parseDate).map({
                max(0, Int($0.timeIntervalSince(parseDate(row.startedAt) ?? $0)))
            }) else {
                return
            }
            totals[row.userId, default: 0] += duration
        }
    }

    private func weekStart() -> Date {
        TeamWeeklyGoal.koreanWeekStart(for: Date())
    }

    private func parseDate(_ value: String) -> Date? {
        dateFormatter.date(from: value)
    }

    func startWork(accessToken: String, userID: String) async throws {
        let sessionID = UUID().uuidString
        try await sendNoBody(
            path: "/rest/v1/work_sessions",
            method: "POST",
            body: StartSessionRequest(
                id: sessionID,
                teamId: SupabaseConfig.teamID,
                userId: userID,
                startedAt: dateFormatter.string(from: Date())
            ),
            accessToken: accessToken,
            prefer: "return=minimal"
        )
        try await upsertStatus(accessToken: accessToken, userID: userID, status: "working", activeSessionID: sessionID)
    }

    func stopWork(accessToken: String, userID: String, durationSeconds: Int) async throws {
        try await sendNoBody(
            path: "/rest/v1/work_sessions",
            method: "PATCH",
            queryItems: [
                URLQueryItem(name: "team_id", value: "eq.\(SupabaseConfig.teamID)"),
                URLQueryItem(name: "user_id", value: "eq.\(userID)"),
                URLQueryItem(name: "ended_at", value: "is.null")
            ],
            body: StopSessionRequest(
                endedAt: dateFormatter.string(from: Date()),
                durationSeconds: max(0, durationSeconds)
            ),
            accessToken: accessToken,
            prefer: "return=minimal"
        )
        try await upsertStatus(accessToken: accessToken, userID: userID, status: "off_work", activeSessionID: nil)
    }

    private func upsertStatus(accessToken: String, userID: String, status: String, activeSessionID: String?) async throws {
        try await sendNoBody(
            path: "/rest/v1/work_statuses",
            method: "POST",
            queryItems: [URLQueryItem(name: "on_conflict", value: "team_id,user_id")],
            body: StatusUpsertRequest(
                teamId: SupabaseConfig.teamID,
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
