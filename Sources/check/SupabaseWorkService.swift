import Foundation

actor SupabaseWorkService {
    let projectURL: URL
    let anonKey: String?
    let session: URLSession
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    let dateFormatter = ISO8601DateFormatter()
    /// 소수초까지 읽는 파싱 전용 포매터. Supabase timestamptz 는 소수초 유무가 섞여 내려오는데
    /// 기본 ISO8601DateFormatter 는 "2026-07-26T04:15:35.634Z" 를 nil 로 돌려준다(실측 확인). 파싱은 이걸 1차로
    /// 시도하고 실패 시 기본 포매터로 폴백한다(parseDate). 출력(string(from:))은 기존대로 dateFormatter 만 쓴다.
    let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

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
        async let deviceRows = fetchStatusDevices(accessToken: accessToken, teamID: teamID)

        let rows = try decoder.decode([WorkStatusRow].self, from: try await statusBytes)
        let activeSessions = try await activeRows
        let weeklySessions = try await weeklyRows
        // **이 조회의 실패만은 삼킨다.** work_status_devices 는 소유권 반납의 '증거'일 뿐이고, 증거의 부재는
        // 아무것도 증명하지 않는다(앱은 그때 기존 백스톱 7분으로 되돌아간다). 반대로 이 실패를 그대로 던지면
        // 마이그레이션이 아직 적용되지 않은 서버에서 팀 상태 폴링 **전체**가 죽어 팀 목록·내 세션 복구·
        // 원격 종료 반영이 통째로 멈춘다 — 새 기능 하나를 위해 앱의 심장을 서버 배포 순서에 인질로 잡는 셈이다.
        // (같은 이유로 임베딩(select=…,work_status_devices(…))도 쓰지 않는다: 표가 없으면 PostgREST 가 관계를
        //  못 찾아 상태 GET 자체를 400 으로 거부한다.)
        let devices = (try? await deviceRows) ?? []
        let activeByUser = Dictionary(grouping: activeSessions, by: \.userId)
        let weeklyByUser = weeklyDurations(from: weeklySessions, now: now)
        let todayByUser = todayDurations(from: weeklySessions, now: now)
        let devicesByUser = Dictionary(grouping: devices, by: \.userId)
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
                activeSessionID: row.activeSessionId,
                deviceClaims: (devicesByUser[row.userId] ?? []).map { device in
                    StatusDeviceClaim(
                        deviceID: device.deviceId,
                        sessionID: device.sessionId,
                        lastSeenAt: device.lastSeenAt.flatMap(parseDate),
                        // 컬럼이 없는 서버/옛 행이면 nil 이다 → false(약함). 모르는 주장을 '이 맥이 세션을
                        // 열었다'로 승격시키면 진짜 소유자가 그 앞에서 물러난다.
                        openedSession: device.openedSession ?? false
                    )
                }
            )
        }
    }

    /// 팀의 기기별 소유 주장 행(work_status_devices)을 읽는다. 팀 범위인 이유는 판정 주체가 '내 행'이더라도
    /// 같은 계정의 **다른 맥**이 남긴 행을 봐야 하기 때문이다(팀 전체라도 인당 1~2행이라 응답이 작다).
    /// 호출자가 실패를 삼키므로(fetchTeamStatuses 주석) 표가 없는 서버에서도 폴링은 그대로 돈다.
    private func fetchStatusDevices(accessToken: String, teamID: String) async throws -> [WorkStatusDeviceRow] {
        let data = try await send(
            path: "/rest/v1/work_status_devices",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "user_id,device_id,session_id,last_seen_at,opened_session"),
                URLQueryItem(name: "team_id", value: "eq.\(teamID)")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode([WorkStatusDeviceRow].self, from: data)
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

    /// ISO8601 파싱 단일 창구. 소수초 포함("...35.634Z") → 소수초 없음("...35Z") 순으로 시도한다.
    /// 예전엔 기본 포매터 하나만 써서 소수초가 붙은 timestamptz 를 통째로 nil 로 흘렸다(주간/오늘 누적이 조용히 0 이 되는
    /// 잠복 지뢰였다). 테스트에서 직접 고정하려고 internal 로 둔다.
    func parseDate(_ value: String) -> Date? {
        fractionalDateFormatter.date(from: value) ?? dateFormatter.date(from: value)
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

    /// 이 맥이 이 세션의 소유자라는 **사실**을 기기별 행으로 남긴다(work_status_devices).
    /// 위 heartbeat 와 별도 요청인 이유: upsertStatus 본문에 device 를 끼워 넣으면 v0.2.10 이 쓰는 그 표에
    /// 새 컬럼이 생기고(구버전은 그 컬럼을 안 보내므로 내가 써 둔 값이 그대로 눌러앉아 "이 맥이 소유"라는
    /// 거짓말을 서버가 하게 된다), 무엇보다 공유 셀은 내가 폴링 직전에 매번 덮어써 남의 흔적을 지운다.
    /// 기기별 행은 내 upsert 가 남의 행을 건드릴 수 없어 증거가 보존된다.
    /// 흡수 상태(다른 맥이 연 세션을 미러링 중)에서는 호출되지 않는다 — 호출부가 그 가드 뒤에 있으므로
    /// 이 표에 행이 있다는 것 자체가 '살아 있는 소유 주장'이다. 반납/종료 시 삭제할 필요도 없다(전진이
    /// 멈추면 자동으로 무효가 된다 — 판정이 신선도가 아니라 전진 여부이기 때문이다).
    /// openedSession 은 '이 맥이 그 세션을 실제로 열었는가'(강한 소유)다. 매 하트비트에 실어 **덮어쓴다** —
    /// 한 번 true 로 쓰고 마는 방식이면, 그 세션이 끝난 뒤 같은 맥이 백스톱으로 다른 세션을 약하게 주장할 때
    /// 옛 true 가 남아 추측이 사실로 승격된다.
    func upsertStatusDevice(
        accessToken: String,
        teamID: String,
        userID: String,
        deviceID: String,
        sessionID: String,
        openedSession: Bool
    ) async throws {
        let stamp = dateFormatter.string(from: Date())
        try await sendNoBody(
            path: "/rest/v1/work_status_devices",
            method: "POST",
            queryItems: [URLQueryItem(name: "on_conflict", value: "team_id,user_id,device_id")],
            body: StatusDeviceUpsertRequest(
                teamId: teamID,
                userId: userID,
                deviceId: deviceID,
                sessionId: sessionID,
                lastSeenAt: stamp,
                updatedAt: stamp,
                openedSession: openedSession
            ),
            accessToken: accessToken,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
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

    /// 개인 기록(근무 리듬 히트맵 · 지난주 회고)의 원천 데이터. 내 완료 세션만 since 이후로 읽는다.
    /// RLS 는 같은 팀 세션 읽기를 허용하므로 본인 행은 당연히 읽히고, user_id 필터로 남의 행은 애초에 안 가져온다.
    /// 시작 시각 오름차순 + 상한 2000행(조회 창인 2주치 개인 세션엔 넉넉하다)으로 응답 크기를 묶는다.
    func fetchMySessions(accessToken: String, userID: String, since: Date) async throws -> [WorkSessionRow] {
        let data = try await send(
            path: "/rest/v1/work_sessions",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "id,user_id,started_at,ended_at,duration_seconds"),
                URLQueryItem(name: "user_id", value: "eq.\(userID)"),
                URLQueryItem(name: "ended_at", value: "not.is.null"),
                URLQueryItem(name: "ended_at", value: "gte.\(dateFormatter.string(from: since))"),
                URLQueryItem(name: "order", value: "started_at.asc"),
                URLQueryItem(name: "limit", value: "2000")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode([WorkSessionRow].self, from: data)
    }

    /// 내 이번 달 AI 토큰 사용량을 기기별 원장에 upsert 한다. (user_id, month, device_id) 충돌 시 merge-duplicates 로 갱신한다.
    /// 원장을 기기별로 쪼갠 이유: 맥 2대에서 같은 계정을 쓰면 (user_id, month) 키로는 나중에 켠 맥이 앞선 맥의 값을
    /// 통째로 덮어써 월 총량이 "합산"이 아니라 "마지막 기기 값"이 됐다. 기기별 행을 따로 두고 합산은 서버 보드가 한다.
    /// 표를 새로 만든 이유(하위호환): 옛 표 token_usage_monthly 의 PK 를 바꾸면 (user_id, month) 유니크가 사라져
    /// 아직 업데이트하지 않은 v0.2.10 클라의 `on_conflict=user_id,month` 업로드가 전부 42P10 으로 실패한다.
    /// 옛 표는 스키마를 그대로 두고(구버전이 계속 정상 업로드), 보드 RPC 가 기기 합산과 옛 행 중 큰 쪽을 쓴다.
    /// 이 앱도 옛 표를 함께 갱신하되 **그 행을 줄이지 않을 때만** 쓴다 — 아래 fetchLegacyTokenUsageTotal/upsertLegacyTokenUsage 참조.
    /// 반환 없음(return=minimal) — 표시는 별도 fetchTokenBoard 로 다시 읽는다. usage.month 는 D1 이 계산한 KST 'YYYY-MM'.
    ///
    /// diagnostics 는 Codex 집계 진단(codex_diag_*)이고 **기본값 nil** 이다. 호출측(WorkTimerStoreSync)은
    /// "<빌드>:<KST 날짜>" 도장당 1회(= 하루 1회)만 값을 채워 보낸다 — nil 이면 본문에서 codex_diag_* 키가 통째로
    /// 빠지고, PostgREST 는 본문에 없는 컬럼을 갱신하지 않으므로 서버에 이미 쌓인 진단값이 매 30초 업로드에
    /// 지워지지 않는다 (TokenUsageUpsertRequest 의 진단 필드 주석 참조).
    /// 그 19개 중 codex_diag_input_at_scan 은 여기서 따로 넘기지 않는다 — 요청 생성자가 아래 usage.codexInput/
    /// codexOutput 에서 파생시킨다(= usage.codexTotal). 행에 실린 Codex 합과 스냅샷이 어긋날 수 없게 하는 장치다.
    /// 진단값은 순위판 RPC 에 실리지 않는다 — 운영자만 DB 에서 본다.
    func upsertTokenUsage(
        accessToken: String,
        userID: String,
        usage: TokenUsageMonthly,
        deviceID: String,
        diagnostics: CodexUsageDiagnostics? = nil
    ) async throws {
        try await sendNoBody(
            path: "/rest/v1/token_usage_device_monthly",
            method: "POST",
            queryItems: [URLQueryItem(name: "on_conflict", value: "user_id,month,device_id")],
            body: TokenUsageUpsertRequest(
                userId: userID,
                month: usage.month,
                deviceId: deviceID,
                claudeInput: usage.claudeInput,
                claudeOutput: usage.claudeOutput,
                claudeCacheRead: usage.claudeCacheRead,
                claudeCacheCreation: usage.claudeCacheCreation,
                codexInput: usage.codexInput,
                codexOutput: usage.codexOutput,
                total: usage.total,
                todayTotal: usage.todayTotal,
                todayDate: usage.todayDate,
                diagnostics: diagnostics
            ),
            accessToken: accessToken,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    /// 옛 표 token_usage_monthly 의 내 이번 달 행 총량을 읽는다(없으면 nil). select=total 한 줄만 읽는다.
    /// 쓰임: 옛 표를 덮어쓰기 **전** 게이트. 그 행이 아직 v0.2.10 인 다른 맥의 더 큰 누적치일 수 있어,
    /// 그때 내 값으로 덮으면 그 맥의 사용량이 순위에서 사라진다(upsertLegacyTokenUsage 주석 참조).
    /// 본인 행 select 는 RLS 정책으로 열려 있다(20260723010000 — upsert 충돌 읽기용으로 이미 필요했다).
    func fetchLegacyTokenUsageTotal(accessToken: String, userID: String, month: String) async throws -> Int? {
        let data = try await send(
            path: "/rest/v1/token_usage_monthly",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "total"),
                URLQueryItem(name: "user_id", value: "eq.\(userID)"),
                URLQueryItem(name: "month", value: "eq.\(month)"),
                URLQueryItem(name: "limit", value: "1")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode([TokenUsageLegacyTotalRow].self, from: data).first?.total
    }

    /// 같은 사용량을 옛 표 token_usage_monthly((user_id, month))에도 그대로 올린다 — v0.2.10 과 완전히 같은 요청이다.
    /// **호출 전 게이트 필수**: 이 표는 키에 device_id 가 없어 맥 2대가 한 행을 공유한다. 아직 v0.2.10 인 주력 맥이
    ///   그 달 누적 200M 을 올려 둔 상태에서 v0.2.11 인 보조 맥이 자기 2M 으로 덮으면, 보드의 '큰 쪽' 규칙이
    ///   비교할 옛 값 자체가 2M 으로 바뀌어(= 기기 합산과 같아져) 주력 맥의 200M 이 순위에서 사라진다.
    ///   그래서 스토어는 fetchLegacyTokenUsageTotal 로 현재 행을 읽어 **줄어들지 않을 때만** 이 함수를 부른다.
    /// 왜 새 표만 쓰지 않는가: 마이그레이션이 아직 적용되지 않은 사이에도 사용량이 멈추지 않게 하고(옛 표는 이미 있다),
    ///   v0.2.10 으로 되돌아간 맥과 같은 행을 공유해 표시가 이어지게 하기 위함이다.
    /// 이중 계상은 없다: 보드가 두 출처를 **더하지 않고** 큰 쪽만 고르며, 옛 행은 어느 기기의 그 달 누적치라
    /// 항상 그 기기의 새 행 이하 ≤ 기기 합산이다(그래서 업로드가 끝난 뒤엔 합산이 이긴다).
    /// v0.2.9 이하가 남긴 과다계상 옛 행(Codex resume 누적 편입)은 이제 클라가 덮어써 정정하지 않는다 —
    /// 대신 보드 RPC 가 "이 사용자가 처음 기기별 행을 올린 시각 이후로 갱신되지 않은 옛 행"을 무시한다
    /// (20260726010000 마이그레이션의 device_first 주석). 덮어쓰기로 정정하려 들면 위의 200M 소실이 되살아난다.
    func upsertLegacyTokenUsage(accessToken: String, userID: String, usage: TokenUsageMonthly) async throws {
        try await sendNoBody(
            path: "/rest/v1/token_usage_monthly",
            method: "POST",
            queryItems: [URLQueryItem(name: "on_conflict", value: "user_id,month")],
            body: TokenUsageLegacyUpsertRequest(
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

    /// 울트라 찌르기. ultra_poke_user(p_to) RPC 를 로그인 토큰으로 호출한다.
    /// **poke_user 의 오버로드가 아니라 다른 이름의 새 함수다** — PostgREST 에서 같은 이름·같은 인자 이름의
    /// 두 함수는 어느 쪽을 부를지 모호해져 요청이 300/404 로 떨어진다. 요청 본문은 poke_user 와 같은
    /// PokeSendRequest({p_to}) 를 재사용하고, 응답도 같은 jsonb 규약(status + 선택 필드)이다.
    /// 응답의 ultra_remaining(오늘 남은 횟수)은 PokeSendResponse 가 함께 디코드한다 — 남은 횟수를 알려고
    /// 따로 GET 을 하나 더 내면 울트라를 안 쓰는 날에도 매 실행마다 왕복이 늘어난다(무료 플랜).
    func sendUltraPoke(accessToken: String, to userID: String) async throws -> PokeSendResponse {
        let data = try await send(
            path: "/rest/v1/rpc/ultra_poke_user",
            method: "POST",
            body: PokeSendRequest(pTo: userID),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(PokeSendResponse.self, from: data)
    }

    /// 상대에게 3글자 메시지. send_message(p_to, p_body) RPC 를 로그인 토큰으로 호출한다.
    /// 근무중 게이트·집중 모드·60초 쿨타임·3글자 상한은 **전부 서버**가 강제한다 — 아래 클라 게이트는 판정이 아니라
    /// 헛왕복 절감 장치다(무료 플랜).
    ///
    /// 응답은 poke_user 와 **문자 그대로 같은 jsonb 규약**({status, retry_after_seconds?})이라 PokeSendResponse 를
    /// 그대로 재사용한다 — ultra_remaining/reset_after_seconds 는 이 RPC 가 안 보내므로 nil 로 남을 뿐 해가 없다.
    /// 갈리는 것은 도메인 어휘뿐이고 그건 MessageSendOutcome 이 맡는다(그 타입 주석에 이유가 있다).
    ///
    /// **빈 본문·3글자 초과는 요청을 아예 내지 않고** 서버와 같은 status 로 즉답한다. 로컬 거절만 throw 로 만들면
    /// 호출부가 같은 실패를 catch 와 switch 두 곳에서 다뤄야 하고, 그 둘은 시간이 지나면 반드시 다른 문구를 낸다.
    /// 보내는 문자열도 원문이 아니라 정규화된 값이다 — 서버도 정규화하지만, 클라가 먼저 하면 NFD 한글이
    /// 서버에서만 6글자로 세어져 거절되는 사고가 사라진다(MessageBody.sanitized 주석의 실측 참고).
    func sendMessage(accessToken: String, to userID: String, body: String) async throws -> PokeSendResponse {
        switch MessageBody.validate(body) {
        case .empty:
            return PokeSendResponse(status: "invalid")
        case .unsupportedCharacters:
            // **MessageSendOutcome 에 전용 케이스를 만들지 않고 invalid 로 접는다.** 텍스트 전용은 서버가 아니라
            // 클라가 강제하는 규칙이라(서버는 이모지를 허용하는 난간만 세운다) 서버는 이 status 를 영원히 안 낸다 —
            // 여기에 케이스를 더하면 스토어의 응답 분기에 **서버에서 절대 오지 않는 가지**가 하나 늘 뿐이다.
            // 사용자에게 이유를 말하는 자리는 응답 분기가 아니라 **입력 단계**다: 화면은 MessageBody.validate 를
            // 직접 불러 .unsupportedCharacters 를 보고 "이모지는 보낼 수 없어요"를 즉시 띄우고 전송을 막는다
            // (사장님 지시 "입력 자체가 애초에 텍스트만 되게"의 자리가 거기다). 여기까지 온 입력은 그 화면 게이트를
            // 우회한 경로뿐이라 invalid 로 충분하다.
            return PokeSendResponse(status: "invalid")
        case .tooLong:
            return PokeSendResponse(status: "too_long")
        case .ok(let normalized):
            let data = try await send(
                path: "/rest/v1/rpc/send_message",
                method: "POST",
                body: SendMessageRequest(pTo: userID, pBody: normalized),
                accessToken: accessToken,
                prefer: nil
            )
            return try decoder.decode(PokeSendResponse.self, from: data)
        }
    }

    /// 내게 온 미소비 찔림을 원자적으로 수신+소비한다. take_pokes(p_message_capable) RPC 를 로그인 토큰으로 호출한다.
    /// 반환 행은 보낸이 표시명/아바타 + 찔린 시각 epoch 초 + 종류/본문을 담는다(클라가 Date 로 복원해 신선도 필터).
    ///
    /// **p_message_capable: true 를 빼면 이 앱도 메시지를 못 받는다.** 서버 기본값이 false 라(구버전 보호)
    /// 메시지 행은 소비되지 않고 서버에 남는다 — 즉 이 한 인자가 기능의 스위치다.
    ///
    /// ── 하위호환: 인자를 모르는 서버(마이그레이션 미적용) ──
    /// PostgREST 는 본문의 키 집합으로 함수를 고르므로, 인자 없는 옛 take_pokes() 만 있는 서버에서는
    /// 이 요청이 PGRST202("… in the schema cache") = .databaseSchemaMissing 으로 죽는다. 그대로 두면
    /// 앱을 먼저 배포하고 db push 가 늦은 창에서 **찔림 수신 전체가 멈춘다**(메시지만이 아니다).
    /// 그래서 그 오류에서만 옛 모양(인자 없음)으로 한 번 더 부른다.
    ///
    /// **성공을 캐시하지 않는 이유**(= 옛 서버로 판정한 뒤 계속 옛 모양만 부르지 않는 이유): 이 앱은
    /// 메뉴바 상주라 몇 주씩 살아 있고, db push 는 그 사이 언제든 끝난다. 한 번의 실패로 옛 모양에
    /// 눌러앉으면 서버가 고쳐진 뒤에도 재시작 전까지 메시지를 영영 못 받는다 — 그 대가가
    /// '아직 안 고쳐진 짧은 창에서 폴링 1회당 요청 2건'보다 훨씬 크다.
    func takePokes(accessToken: String) async throws -> [TakenPokeRow] {
        let data: Data
        do {
            data = try await send(
                path: "/rest/v1/rpc/take_pokes",
                method: "POST",
                body: TakePokesRequest(pMessageCapable: true),
                accessToken: accessToken,
                prefer: nil
            )
        } catch SupabaseWorkServiceError.databaseSchemaMissing {
            // 옛 서버. 이 시점엔 아무것도 소비되지 않았다(함수를 못 찾아 실행 자체가 없었다)므로 재호출이 안전하다.
            data = try await send(
                path: "/rest/v1/rpc/take_pokes",
                method: "POST",
                body: EmptyBody(),
                accessToken: accessToken,
                prefer: nil
            )
        }
        return try decoder.decode([TakenPokeRow].self, from: data)
    }

    /// 울트라 재화 지갑 동기화. `ultra_wallet_sync(p_days_back int default 1)` RPC 를 로그인 토큰으로 호출한다.
    /// 이름은 sync 지만 **읽기 전용이 아니다** — 밑바닥 보정과 미션 적립이 이 호출 안에서 일어난다.
    /// 그래서 "패널을 열 때만" 부르면 근무만 하고 패널을 안 연 사용자의 코인이 영구 소실된다
    /// (호출 지점 4곳의 근거는 WorkTimerStore.UltraSyncReason 주석에 있다).
    ///
    /// 멱등하다: 누적 근무초는 단조증가라 임계를 하루 한 번만 넘고, 적립은 부분 유니크 인덱스가 막는다.
    /// 몇 번을 불러도 장부는 하루 한 줄이다.
    ///
    /// `p_days_back` 기본 1 = **오늘과 어제**. 어제 3시간을 채우고 앱을 껐다 오늘 켠 사용자의 몫을 소급한다.
    ///
    /// ── 하위호환: RPC 가 아직 없는 서버 ──
    /// 브루 배포라 앱이 db push 보다 **먼저** 나가는 창이 실제로 존재한다. 그때 PostgREST 는 PGRST202
    /// (= .databaseSchemaMissing)를 낸다. takePokes 와 같은 관용구로, 다만 재호출할 옛 모양이 없으므로
    /// 전용 오류 `.ultraWalletUnavailable` 로 **접어서** 던진다 — 스토어가 "서버 미배포"와 "네트워크 실패"를
    /// 가를 수 있어야 진단이 성립한다. 그대로 재던지면 두 원인이 같은 문장으로 뭉개진다.
    ///
    /// **fetchTokenUsageSettings 의 select 에 끼워 넣지 않는다.** 잔량 컬럼에는 select grant 가 아예 없어
    /// (밑바닥 보정 전 값 노출 금지) 컬럼을 하나 더하는 순간 42703 으로 토큰 설정까지 못 읽게 된다 —
    /// 이 저장소가 이미 한 번 기록한 사고다(fetchTokenUsageSettings 주석).
    func syncUltraWallet(accessToken: String, daysBack: Int = 1) async throws -> UltraWalletResponse {
        let data: Data
        do {
            data = try await send(
                path: "/rest/v1/rpc/ultra_wallet_sync",
                method: "POST",
                body: UltraWalletSyncRequest(pDaysBack: daysBack),
                accessToken: accessToken,
                prefer: nil
            )
        } catch SupabaseWorkServiceError.databaseSchemaMissing {
            throw SupabaseWorkServiceError.ultraWalletUnavailable
        }
        return try decoder.decode(UltraWalletResponse.self, from: data)
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

    /// 내 토큰 설정 조회. profiles 자기 행의 token_usage_public(공개 여부)과 token_usage_collect(수집 여부)를
    /// **한 번에** GET 한다 — 둘은 독립 설정이고 같은 시점에 필요하므로 요청을 나눌 이유가 없다.
    /// 행/컬럼 누락 시 각각 기본값(공개 true / 수집 true)으로 폴백한다.
    func fetchTokenUsageSettings(
        accessToken: String,
        userID: String
    ) async throws -> (isPublic: Bool, collects: Bool, focusMode: Bool) {
        let data = try await send(
            path: "/rest/v1/profiles",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(userID)"),
                URLQueryItem(name: "select", value: "token_usage_public,token_usage_collect,focus_mode")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([ProfilePrivacyRow].self, from: data)
        return (
            rows.first?.tokenUsagePublic ?? true,
            rows.first?.tokenUsageCollect ?? true,
            rows.first?.focusMode ?? false
        )
    }

    /// 집중 모드(콕찌르기 수신 거부) 갱신. profiles 자기 행을 PATCH 한다 —
    /// 컬럼 단위 UPDATE 권한(20260812090000)이 있어야 통과한다.
    func updateFocusMode(accessToken: String, userID: String, enabled: Bool) async throws {
        try await sendNoBody(
            path: "/rest/v1/profiles",
            method: "PATCH",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(userID)")],
            body: ProfileFocusModeUpdateRequest(focusMode: enabled),
            accessToken: accessToken,
            prefer: "return=minimal"
        )
    }

    /// 이 맥의 앱 버전을 서버에 남긴다. profiles 자기 행의 app_build/app_version 을 PATCH 한다 —
    /// **남이 나에게 메시지를 보낼 수 있는지**를 서버가 이 값으로 판정하기 때문이다(send_message 의 target_outdated).
    /// 컬럼 단위 UPDATE 권한이 있어야 통과한다(focus_mode 와 같은 함정 — 20260804020000 이 표 단위 update 를 회수했다).
    /// 컬럼/권한이 없는 서버에서는 400/403 으로 죽고 호출부가 조용히 삼킨다(다음 기회에 재시도).
    func updateAppVersion(accessToken: String, userID: String, report: AppVersionReport) async throws {
        try await sendNoBody(
            path: "/rest/v1/profiles",
            method: "PATCH",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(userID)")],
            body: ProfileAppVersionUpdateRequest(appBuild: report.build, appVersion: report.version),
            accessToken: accessToken,
            prefer: "return=minimal"
        )
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

    // MARK: - 별명(표시명) 변경

    /// 별명 변경. set_display_name(p_name) RPC 를 로그인 토큰으로 호출한다.
    /// 정규화·길이·중복·쿨타임 판정은 **전부 서버**가 한다(클라 사전 검증은 헛왕복을 줄이는 부수 장치일 뿐).
    /// 반환은 jsonb 단일 객체(배열 아님)라 poke_user 와 같은 방식으로 직접 디코드한다.
    func setDisplayName(accessToken: String, name: String) async throws -> DisplayNameChangeResponse {
        let data = try await send(
            path: "/rest/v1/rpc/set_display_name",
            method: "POST",
            body: SetDisplayNameRequest(pName: name),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(DisplayNameChangeResponse.self, from: data)
    }

    /// 내 별명 쿨타임 기준 시각. **별도 GET 인 이유가 이 설계의 전부다** — 새 컬럼을 기존 설정 GET
    /// (fetchTokenUsageSettings)의 select 에 끼워 넣으면 마이그레이션 미적용 서버에서 42703 이 나
    /// 요청 전체가 400 이 되고, 새 기능 하나 때문에 토큰 공개/수집 설정까지 같이 못 읽는다
    /// (fetchTeamStatuses:110-116 과 같은 규약). 호출부가 try? 로 삼키므로 컬럼이 없는 서버에서도
    /// 아무 일도 일어나지 않는다.
    func fetchDisplayNameChangedAt(accessToken: String, userID: String) async throws -> Date? {
        let data = try await send(
            path: "/rest/v1/profiles",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(userID)"),
                URLQueryItem(name: "select", value: "display_name_changed_at")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        // 반드시 parseDate 다 — 기본 포매터만 쓰면 소수초가 붙은 timestamptz 를 통째로 nil 로 흘린다(:243).
        return try decoder.decode([DisplayNameChangedAtRow].self, from: data)
            .first?.displayNameChangedAt.flatMap(parseDate)
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

// MARK: - 비밀번호 재설정 OTP

/// 브라우저를 거치지 않는 재설정 3단계(recover → verify → PUT user).
/// **왜 OTP 인가**: 재설정 메일의 링크는 `check://auth` 로 리다이렉트되는데 그 스킴을 등록한 앱이 없어
/// 브라우저에 빈 화면만 뜬다(실측: `location: check://auth#error=...`). 링크를 살리려면 URL 스킴 등록 +
/// 브라우저 왕복이 필요하지만, 6자리 코드는 앱 안에서 그대로 끝난다.
extension SupabaseWorkService {
    /// 재설정 코드를 메일로 보낸다. **계정이 없어도 성공한다** — GoTrue 가 계정 존재 여부를 흘리지 않으려고
    /// 항상 200 을 준다. 그러니 "없는 이메일입니다" 같은 응답을 기대하지 마라(화면 문구도 "메일을 보냈어요"로
    /// 통일해야 한다 — 성공/실패로 계정 유무를 추측하게 만들면 서버가 막아 둔 열거 공격을 앱이 다시 연다).
    func sendPasswordResetCode(email: String) async throws {
        do {
            _ = try await send(
                path: "/auth/v1/recover",
                method: "POST",
                body: PasswordResetRequest(email: email),
                accessToken: nil,
                prefer: nil
            )
        } catch let error as SupabaseWorkServiceError {
            throw Self.passwordRecoveryError(error)
        }
    }

    /// 6자리 코드를 검증하고 세션을 받는다. 응답이 로그인과 완전히 같은 모양이라
    /// (`access_token`/`refresh_token`/`user.id`) SignInResponse 를 그대로 재사용한다 — 새 타입을 만들면
    /// 토큰 필드가 하나 늘 때 두 곳을 고쳐야 하고, 안 고친 쪽은 조용히 nil 이 된다.
    func verifyPasswordResetCode(email: String, code: String) async throws -> SupabaseSession {
        do {
            let data = try await send(
                path: "/auth/v1/verify",
                method: "POST",
                body: VerifyOTPRequest(email: email, token: code, type: "recovery"),
                accessToken: nil,
                prefer: nil
            )
            let response = try decoder.decode(SignInResponse.self, from: data)
            return SupabaseSession(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                userID: response.user.id
            )
        } catch let error as SupabaseWorkServiceError {
            throw Self.passwordRecoveryError(error)
        }
    }

    /// 위에서 받은 accessToken 으로 새 비밀번호를 설정한다. 이 토큰은 **일반 로그인 세션과 같은 JWT** 라
    /// 성공하면 그대로 로그인 상태로 이어 붙일 수 있다(스토어가 completeSignIn 으로 처리).
    func updatePassword(accessToken: String, newPassword: String) async throws {
        do {
            _ = try await send(
                path: "/auth/v1/user",
                method: "PUT",
                body: UpdatePasswordRequest(password: newPassword),
                accessToken: accessToken,
                prefer: nil
            )
        } catch let error as SupabaseWorkServiceError {
            throw Self.passwordRecoveryError(error)
        }
    }

    /// 재설정 흐름 전용 **재분류**. 공용 매핑(SupabaseWorkHTTP.serviceError)은 이 흐름의 오류를 모른다 —
    /// 실측한 세 가지가 전부 `.authMessage(영문 원문)` 으로 흘러 메뉴바에 "Token has expired or is invalid"
    /// 같은 영어가 그대로 뜬다. 그 파일은 이 트랙 소유가 아니므로 여기서 메시지 본문만 보고 한 번 더 좁힌다.
    /// (그래서 판정 기준이 status 가 아니라 **문구**다 — 던져진 시점에 status 는 이미 사라졌다.)
    static func passwordRecoveryError(_ error: SupabaseWorkServiceError) -> SupabaseWorkServiceError {
        // 429 인데 본문이 비었거나 JSON 이 아니면 공용 매핑이 .invalidResponse(429) 로 준다.
        // 이건 status 로만 알 수 있는 유일한 경우라 먼저 걷어낸다(남은 초는 알 길이 없으니 nil).
        if case .invalidResponse(429) = error {
            return .rateLimited(retryAfterSeconds: nil)
        }
        guard case let .authMessage(message) = error else {
            return error
        }
        let lowercased = message.lowercased()
        // "For security purposes, you can only request this after N seconds." / "Request rate limit reached"
        // / "Email rate limit exceeded" — 셋 다 429 인데 앞의 하나만 초를 담고 있다.
        if lowercased.contains("rate limit") || lowercased.contains("security purposes") {
            return .rateLimited(retryAfterSeconds: retryAfterSeconds(in: lowercased))
        }
        // 403 otp_expired("Token has expired or is invalid") + 400 validation_failed("Verify requires either a
        // token or a token hash"). 후자는 코드를 빈 값으로 보낸 경우인데, 사용자 입장에선 똑같이 "코드가 안 통했다"다.
        if lowercased.contains("token has expired or is invalid")
            || lowercased.contains("otp_expired")
            || lowercased.contains("verify requires") {
            return .otpInvalidOrExpired
        }
        // 403 bad_jwt("invalid JWT: ...", "invalid claim: missing sub claim"). recovery 토큰이 죽은 것이므로
        // 사용자는 코드부터 다시 받아야 한다. 그냥 두면 영문 JWT 문구가 화면에 뜬다.
        if lowercased.contains("invalid jwt") || lowercased.contains("bad_jwt")
            || lowercased.contains("missing sub claim") {
            return .sessionExpired
        }
        return error
    }

    /// "…after 51 seconds." 에서 51 을 뽑는다. **정규식 대신 뒤에서 훑는** 이유는 문구가 GoTrue 버전마다
    /// 조금씩 달라져 왔기 때문이다("this after N seconds" / "N seconds"). "second" 바로 앞의 숫자 뭉치만
    /// 취하고, 없으면 nil 이다 — 못 뽑았다고 0 을 돌려주면 곧바로 재시도가 열려 429 를 다시 부른다.
    private static func retryAfterSeconds(in lowercasedMessage: String) -> Int? {
        guard let secondRange = lowercasedMessage.range(of: "second") else {
            return nil
        }
        var digits: [Character] = []
        for character in lowercasedMessage[..<secondRange.lowerBound].reversed() {
            if character.isNumber {
                digits.append(character)
            } else if !digits.isEmpty {
                break
            }
        }
        return digits.isEmpty ? nil : Int(String(digits.reversed()))
    }
}
