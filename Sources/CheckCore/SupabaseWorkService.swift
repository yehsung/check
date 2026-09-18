import Foundation

package actor SupabaseWorkService {
    package nonisolated let projectURL: URL
    package nonisolated let anonKey: String?
    package let session: URLSession
    package let encoder: JSONEncoder
    package let decoder: JSONDecoder
    package let dateFormatter = ISO8601DateFormatter()
    /// 소수초까지 읽는 파싱 전용 포매터. Supabase timestamptz 는 소수초 유무가 섞여 내려오는데
    /// 기본 ISO8601DateFormatter 는 "2026-07-26T04:15:35.634Z" 를 nil 로 돌려준다(실측 확인). 파싱은 이걸 1차로
    /// 시도하고 실패 시 기본 포매터로 폴백한다(parseDate). 출력(string(from:))은 기존대로 dateFormatter 만 쓴다.
    package let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// 폴링 전용 세션. 요청 15초/리소스 30초 타임아웃(30초 폴링·90초 신선도 규약과 정합).
    /// 앱 전역 .shared 대신 전용 구성을 써 무한 대기·백그라운드 재시도가 티커/폴링 주기와 어긋나지 않게 한다.
    ///
    /// **응답 캐시는 끈다**(v0.2.38 Q9). 기본 구성은 매 응답을 URLCache(sqlite)에 쓰는데, 이 세션이 나르는 것은
    /// 30초마다 바뀌는 상태 JSON 뿐이라 캐시 적중이 원리적으로 없다 — 근무 8시간에 디스크 쓰기 ~1,000회만 남는다.
    /// 아바타 이미지는 이 세션이 아니라 `URLSession.shared` 로 받는다(CheckAvatarView) — 그쪽은 디스크 캐시에
    /// 의존하므로 여기 설정과 무관하게 그대로다.
    package static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    #if os(macOS)
    /// `work_tick` 실행 단위 가용성(v0.2.38 S3). 스토어 파일에 저장 프로퍼티를 더하지 않으려고 서비스가 들고 있다 —
    /// 서비스는 스토어당 하나(테스트도 스토어마다 새로 만든다)라 수명이 "이 실행 동안" 과 정확히 같다.
    /// 잠금으로 보호되는 Sendable 클래스라 메인 액터가 await 없이 읽고 쓴다(폴백 판정이 틱마다 도는 자리다).
    /// 맥 전용(dbase-fix): 저장 프로퍼티라 확장 파일로 못 옮겨 여기서 가린다 — 폰 바이너리에 게이트 타입·진단 문구가 실리지 않는다.
    package nonisolated let workTickGate = WorkTickGate()
    #endif

    package init(
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

    package func signIn(email: String, password: String) async throws -> SupabaseSession {
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
    ///
    /// `center`(소속 센터 서버값)는 **display_name 과 같은 자리**에 얹는다 — 가입 트리거
    /// (`handle_check_auth_user`)가 `raw_user_meta_data ->> 'center'` 를 읽어 profiles 에 넣으므로
    /// 왕복이 하나도 늘지 않는다. nil 이면 **키를 아예 싣지 않는다**: 그래야 이 변경 전과 바이트가
    /// 같고(가입 경로는 회귀가 가장 비싼 자리다), 트리거는 없는 키를 null 로 접는다.
    package func signUp(email: String, password: String, displayName: String, center: String? = nil) async throws -> SupabaseSession? {
        var metadata = ["display_name": displayName]
        if let center { metadata["center"] = center }
        let body = SignUpRequest(email: email, password: password, data: metadata)
        let data = try await send(
            path: "/auth/v1/signup",
            method: "POST",
            body: body,
            accessToken: nil,
            prefer: nil
        )
        let response = try decoder.decode(SignUpResponse.self, from: data)
        guard let accessToken = response.accessToken else {
            // 세션 없음 = 확인 메일이 나갔다(가입 확인을 켠 서버). **그 nil 이 코드 화면의 신호다**(SupabaseWorkServiceSignUpOTP).
            //
            // 단, 그 서버는 **이미 인증된 기존 계정**의 가입 시도에도 422 대신 200 + `identities: []` 인 가짜 사용자를 준다
            // (계정 존재를 흘리지 않으려는 GoTrue 의 문서화된 동작). 그걸 nil 로 접으면 스토어가 코드 화면을 띄우고 사용자는
            // 영영 오지 않을 메일을 기다린다. 옛 서버의 422 와 같은 값으로 던져 두 서버 모드의 문구를 같게 한다.
            // 키가 없는 응답(옛 GoTrue·로그인류)은 판정하지 않는다 — 진짜 새 계정은 identities 가 비지 않는다.
            if let identities = response.user.identities, identities.isEmpty {
                throw SupabaseWorkServiceError.emailAlreadyRegistered
            }
            return nil
        }
        return SupabaseSession(accessToken: accessToken, refreshToken: response.refreshToken, userID: response.user.id)
    }

    package func refreshSession(refreshToken: String) async throws -> SupabaseSession {
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

    package func fetchTeamStatuses(accessToken: String, teamID: String, now: Date = Date()) async throws -> [TeamMemberStatus] {
        // work_statuses·활성·주간 세 GET을 병렬 발사한다. 각 요청은 network await 에서 액터를 놓으므로
        // 직렬 3연속 왕복이 아니라 실제로 겹쳐 폴링 경로 지연을 줄인다.
        async let statusBytes = send(
            path: "/rest/v1/work_statuses",
            method: "GET",
            queryItems: [
                // email 은 싣지 않는다(v0.2.38 Q9): 화면 어디에도 쓰지 않는 개인정보를 37행 × 30초로 실어 나르고 있었다.
                // 이름 폴백은 '팀원' 하나다 — ProfileRow.email 은 Optional 로 남겨 옛 응답이 와도 디코드가 깨지지 않는다.
                URLQueryItem(name: "select", value: "user_id,status,updated_at,last_seen_at,active_session_id,profiles(display_name,avatar_url)"),
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
        return assembleTeamStatuses(rows: rows, active: activeSessions, weekly: weeklySessions, devices: devices, now: now)
    }

    /// 행 → `TeamMemberStatus` 조립(fetchTeamStatuses 의 후반을 그대로 떼어 낸 것 — v0.2.38 S3).
    /// **기존 4 GET 경로와 work_tick 경로가 이 한 함수를 부른다.** 스냅샷 조립 로직이 두 벌이 되면 두 경로의
    /// 화면이 언젠가 갈리고, 갈린 쪽은 폴백 중인 맥에서만 보이는 결함이 된다. 인자는 work_tick 응답의 조각 이름과
    /// 1:1 이다(statuses / sessions_active / sessions_weekly / devices) — 조각은 기존 GET 이 주던 행과 같은 모양이라
    /// 여기서는 출처를 구분할 필요가 없다.
    package func assembleTeamStatuses(
        rows: [WorkStatusRow],
        active activeSessions: [WorkSessionRow],
        weekly weeklySessions: [WorkSessionRow],
        devices: [WorkStatusDeviceRow],
        now: Date
    ) -> [TeamMemberStatus] {
        let activeByUser = Dictionary(grouping: activeSessions, by: \.userId)
        let weeklyByUser = weeklyDurations(from: weeklySessions, now: now)
        let todayByUser = todayDurations(from: weeklySessions, now: now)
        let devicesByUser = Dictionary(grouping: devices, by: \.userId)
        return rows.map { row in
            let activeStartedAt = activeByUser[row.userId]?.compactMap { parseDate($0.startedAt) }.min()
            let avatarURL = (row.profiles?.avatarUrl).flatMap { URL(string: $0) }
            return TeamMemberStatus(
                id: row.userId,
                name: row.profiles?.displayName ?? "팀원",
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
                // 주간 합산은 타임스탬프 구간 클리핑(clippedContribution)만 쓴다 — id·duration_seconds 는 읽지 않으므로
                // 싣지 않는다(v0.2.38 Q9; 팀 주간 행은 인당 수십 건이라 이 두 컬럼이 응답의 1/3 이었다).
                URLQueryItem(name: "select", value: "user_id,started_at,ended_at"),
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

    func weekStart(for now: Date) -> Date {
        TeamWeeklyGoal.koreanWeekStart(for: now)
    }

    /// ISO8601 파싱 단일 창구. 소수초 포함("...35.634Z") → 소수초 없음("...35Z") 순으로 시도한다.
    /// 예전엔 기본 포매터 하나만 써서 소수초가 붙은 timestamptz 를 통째로 nil 로 흘렸다(주간/오늘 누적이 조용히 0 이 되는
    /// 잠복 지뢰였다). 테스트에서 직접 고정하려고 internal 로 둔다.
    package func parseDate(_ value: String) -> Date? {
        fractionalDateFormatter.date(from: value) ?? dateFormatter.date(from: value)
    }

    /// PostgREST 오류 본문의 `code`(SQLSTATE 또는 PGRSTxxx). 없거나 본문이 JSON 이 아니면 nil.
    func postgrestErrorCode(in data: Data) -> String? {
        struct Envelope: Decodable { let code: String? }
        return (try? decoder.decode(Envelope.self, from: data))?.code
    }

    package func uploadAvatar(accessToken: String, userID: String, imageData: Data) async throws -> String {
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

    /// 로그아웃. **`scope=local` 이 요점이다**(v0.3.30 · A5) — Supabase Auth 의 기본 scope 는 global 이라, 빼면 이 맥에서
    /// 로그아웃하는 순간 같은 계정의 **다른 기기(다른 맥·폰) 세션까지 전부** 끊긴다. local 은 이 토큰의 세션 하나만 닫는다.
    package func signOut(accessToken: String) async {
        _ = try? await send(
            path: "/auth/v1/logout",
            method: "POST",
            queryItems: [URLQueryItem(name: "scope", value: "local")],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
    }

    /// 팀 코드 정규화: 대문자화 후 공백/하이픈 제거. 클라에서도 적용해 정규화된 코드만 서버로 보낸다.
    package static func normalizeInviteCode(_ code: String) -> String {
        code.uppercased().filter { !$0.isWhitespace && $0 != "-" }
    }

    /// 팀 코드 미리보기. lookup_team_by_code(code) RPC 를 anon Bearer(accessToken 없이)로 호출한다.
    /// 가입 전에도 쓰이므로 로그인 토큰이 필요 없다. 못 찾으면 nil.
    package func lookupTeamByCode(code: String) async throws -> TeamJoinPreview? {
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

    /// 내 팀 참여코드(소속 팀원 전체 공개). my_team_invite_code() RPC 를 로그인 토큰으로 호출한다.
    /// 코드가 곧 열쇠이므로 owner 뿐 아니라 팀원 누구나 조회해 새 동료를 초대할 수 있다. 무소속이면 nil.
    package func fetchMyInviteCode(accessToken: String) async throws -> String? {
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
    package func setTeamWeeklyGoal(accessToken: String, goalHours: Int) async throws -> Int {
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
    package func fetchTeamLeaderboard(accessToken: String) async throws -> [TeamLeaderboardEntry] {
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
                memberCount: $0.memberCount ?? 0,
                // 서버값 → 화면 글자(모르는 값·섞인 팀·구버전 RPC 는 nil = 배지 없음). 리그의 유일한 변환 지점.
                center: CenterLabel.display($0.center)
            )
        }
    }

    /// 로그인 후 내 팀을 확정한다. 소속이 없으면 nil.
    /// 목표시간(goalHours)은 teams.weekly_goal_hours 를 그대로 읽어 온다(같은 쿼리라 추가 요청 없음).
    /// 누락/null 이면 기본 목표(60시간)로 폴백한다.
    package func fetchOwnMembership(accessToken: String, userID: String) async throws -> (teamID: String, teamName: String, goalHours: Int, role: String)? {
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
        return membership(from: row)
    }

    /// 멤버십 행 → 튜플(fetchOwnMembership 의 변환을 떼어 낸 것 — v0.2.38 S3). work_tick 의 `meta.memberships.first`
    /// 가 같은 변환을 지나야 목표 폴백(60시간)·역할 폴백(member)·팀명 폴백("팀")이 두 경로에서 한 글자도 갈리지 않는다.
    package nonisolated func membership(from row: MembershipRow) -> (teamID: String, teamName: String, goalHours: Int, role: String) {
        (
            teamID: row.teamId,
            teamName: row.teams?.name ?? "팀",
            goalHours: row.teams?.weeklyGoalHours ?? TeamWeeklyGoal.defaultGoalHours,
            role: row.role ?? "member"
        )
    }

    /// 개인 기록(근무 리듬 히트맵 · 지난주 회고 · 12주 잔디)의 원천 데이터. 내 완료 세션만 since 이후로 읽는다.
    /// RLS 는 같은 팀 세션 읽기를 허용하므로 본인 행은 당연히 읽히고, user_id 필터로 남의 행은 애초에 안 가져온다.
    /// 시작 시각 **내림차순** + 상한 5000행으로 응답 크기를 묶는다. 조회 창이 13주(12주 잔디)로 넓어지면서 행수가
    /// 2주 시절의 6.5배가 됐고, 어떤 상한이든(우리가 적은 5000 이든, PostgREST 가 서버 설정 max_rows 로 조용히
    /// 잘라 내는 1000 이든 — 호스티드 값은 확인하지 못했고 로컬 config 는 1000) 잘리는 순간이 오면 **어느 쪽 행이
    /// 먼저 사라지느냐**가 문제다. 오름차순이면 가장 최근 주(지난주 회고·히트맵·잔디의 마지막 열)가 먼저 비어
    /// 기존 표시가 통째로 사라지고, 내림차순이면 잔디의 가장 오래된 열부터 비어 새 기능만 옅어진다. 세 계산은
    /// 모두 행 순서에 무관한 합산이라(테스트 insightsComputationIgnoresRowOrder) 정렬 방향은 결과에 영향이 없다.
    package func fetchMySessions(accessToken: String, userID: String, since: Date) async throws -> [WorkSessionRow] {
        let data = try await send(
            path: "/rest/v1/work_sessions",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "id,user_id,started_at,ended_at,duration_seconds"),
                URLQueryItem(name: "user_id", value: "eq.\(userID)"),
                URLQueryItem(name: "ended_at", value: "not.is.null"),
                URLQueryItem(name: "ended_at", value: "gte.\(dateFormatter.string(from: since))"),
                URLQueryItem(name: "order", value: "started_at.desc"),
                URLQueryItem(name: "limit", value: "5000")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode([WorkSessionRow].self, from: data)
    }

    /// 내 일별 토큰 행(기기별)을 since(KST 'YYYY-MM-DD') 이후로 읽는다 — 토큰 잔디의 서버 몫. 자기 행 select 는 RLS 정책으로
    /// 열려 있고 읽기 RPC 는 없다(남의 일별 기록은 어떤 경로로도 나가지 않는다). 합산은 클라(TokenDailyMerge)가 한다.
    /// limit 1000 은 호스티드 PostgREST 의 max_rows 와 같다 — 13주 × 기기 2대 ≈ 180행이라 충분하고, 그 이상은 잘라도
    /// day.desc 정렬이라 **오래된 쪽**이 빠진다(최근 잔디가 먼저 산다).
    package func fetchMyTokenDaily(accessToken: String, userID: String, since: String) async throws -> [TokenUsageDailyRow] {
        let data = try await send(
            path: "/rest/v1/token_usage_device_daily",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "day,device_id,claude_total,codex_total,codex_utc_total,codex_account"),
                URLQueryItem(name: "user_id", value: "eq.\(userID)"),
                URLQueryItem(name: "day", value: "gte.\(since)"),
                URLQueryItem(name: "order", value: "day.desc"),
                URLQueryItem(name: "limit", value: "1000")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode([TokenUsageDailyRow].self, from: data)
    }

    /// 이번 달 토큰 사용량 순위를 조회한다(앱 사용자 전체 공개). token_usage_board(p_month) RPC 를 로그인 토큰으로
    /// 호출한다 — 팀 무관 전체 사용자 행을 profiles 와 조인해 이름/아바타까지 담아 돌려주므로(행 자체 완결), 팀원 목록
    /// 결합이 필요 없다. 서버가 총합 내림차순으로 정렬해 주지만 신뢰하지 않고 클라가 다시 정렬한다.
    package func fetchTokenBoard(accessToken: String, month: String) async throws -> [TokenBoardRow] {
        let data = try await send(
            path: "/rest/v1/rpc/token_usage_board",
            method: "POST",
            body: TokenBoardRequest(pMonth: month),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode([TokenBoardRow].self, from: data)
    }

    // MARK: - 미니게임 순위 (v0.2.46)

    /// 판을 **시작한다**. 서버가 토큰과 시작 시각을 기록하고 토큰을 돌려준다.
    ///
    /// **왜 시작할 때 서버를 부르는가**(2026-09-14, 위조 차단): 예전에는 클라가 `minigame_daily_scores` 에
    /// **직접 upsert** 했다. 그래서 앱 없이 `curl` 한 줄로 아무 점수나 올릴 수 있었고, 상금이 루비가 된
    /// 뒤로는 그 구멍이 곧 재화 발행기였다(두 게임 1등 = 하루 40루비).
    ///
    /// 막는 방식은 **점수 값을 판단하지 않는다** — 그건 언젠가 정직한 사람을 막는다. 대신 "이 판이 실제로
    /// 앱에서 시작됐는가"만 본다. 앱으로 노는 사람은 언제나 토큰이 있고 `curl` 하는 사람은 없다.
    /// 서버는 제출 때 `경과 시간 ≥ 그 점수의 구조적 최소 시간`인지도 본다(게임 상수에서 나오는 물리량이라
    /// 정직한 플레이는 정의상 그걸 못 깬다).
    package func startMiniGameRound(accessToken: String, kind: MiniGameKind) async throws -> MiniGameStartRoundResponse {
        let data = try await send(
            path: "/rest/v1/rpc/minigame_start_round",
            method: "POST",
            body: MiniGameStartRoundRequest(pGame: kind.rawValue),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(MiniGameStartRoundResponse.self, from: data)
    }

    /// 끝난 판의 점수를 **토큰과 함께** 올린다. 한 토큰에 한 점수다(재사용하면 `token_used`).
    /// 최고 유지·판 수 계산은 여전히 서버 몫이고, 클라는 서버가 확정한 값을 그대로 받아 쓴다.
    package func submitMiniGameScore(
        accessToken: String, kind: MiniGameKind, score: Int, token: String
    ) async throws -> MiniGameSubmitScoreResponse {
        let data = try await send(
            path: "/rest/v1/rpc/minigame_submit_score",
            method: "POST",
            body: MiniGameSubmitScoreRequest(pGame: kind.rawValue, pScore: score, pToken: token),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(MiniGameSubmitScoreResponse.self, from: data)
    }

    /// 오늘(day nil → 서버 KST 오늘) 또는 지정한 날의 게임별 순위. minigame_board(p_game, p_day) RPC(앱 사용자 전체 공개,
    /// 공개 꺼진 사람은 본인에게만 보인다). 행 자체 완결(이름/아바타 포함). 정렬은 호출부가 다시 한다.
    package func fetchMiniGameBoard(accessToken: String, kind: MiniGameKind, day: String? = nil) async throws -> [MiniGameBoardEntry] {
        let data = try await send(
            path: "/rest/v1/rpc/minigame_board",
            method: "POST",
            body: MiniGameBoardRequest(pGame: kind.rawValue, pDay: day),
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([MiniGameBoardRow].self, from: data)
        return rows.map { boardRow in
            MiniGameBoardEntry(
                userID: boardRow.userId,
                name: boardRow.displayName ?? "사용자",
                avatarURL: boardRow.avatarUrl.flatMap { URL(string: $0) },
                bestScore: boardRow.bestScore,
                bestAt: boardRow.bestAt.flatMap { parseDate($0) },
                plays: boardRow.plays ?? 0,
                // 서버값 → 화면 글자(모르는 값은 nil = 배지 없음). 이 보드의 유일한 변환 지점.
                center: CenterLabel.display(boardRow.center)
            )
        }
    }

    /// 어제(KST) 1등과 상품 지급 여부. minigame_yesterday_winner(p_game) RPC — 어제 기록이 없으면 0행 → nil.
    package func fetchMiniGameYesterdayWinner(accessToken: String, kind: MiniGameKind) async throws -> MiniGameWinner? {
        let data = try await send(
            path: "/rest/v1/rpc/minigame_yesterday_winner",
            method: "POST",
            body: MiniGameWinnerRequest(pGame: kind.rawValue),
            accessToken: accessToken,
            prefer: nil
        )
        guard let row = try decoder.decode([MiniGameWinnerRow].self, from: data).first else { return nil }
        return MiniGameWinner(
            day: row.day ?? "",
            userID: row.userId,
            name: row.displayName ?? "사용자",
            avatarURL: row.avatarUrl.flatMap { URL(string: $0) },
            score: row.score,
            awarded: row.awarded ?? false,
            center: CenterLabel.display(row.center)
        )
    }

    /// 내 미니게임 순위 공개 여부(profiles.minigame_public). **별도 GET 인 이유는 별명 쿨타임 GET 과 같다** —
    /// 기존 설정 GET 의 select 에 끼우면 컬럼이 없는 서버(마이그레이션 전 창)에서 42703 으로 그 요청 전체가 죽는다.
    /// 컬럼/행이 없으면 nil(호출부가 공개 true 로 본다).
    package func fetchMiniGamePublic(accessToken: String, userID: String) async throws -> Bool? {
        let data = try await send(
            path: "/rest/v1/profiles",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(userID)"),
                URLQueryItem(name: "select", value: "minigame_public")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode([ProfilePrivacyRow].self, from: data).first?.minigamePublic
    }

    /// 내 미니게임 순위 공개 여부 갱신. profiles 자기 행 PATCH(컬럼 단위 UPDATE 권한 필요 — 토큰 공개와 같은 함정).
    package func updateMiniGamePublic(accessToken: String, userID: String, isPublic: Bool) async throws {
        try await sendNoBody(
            path: "/rest/v1/profiles",
            method: "PATCH",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(userID)")],
            body: ProfileMiniGamePublicUpdateRequest(minigamePublic: isPublic),
            accessToken: accessToken,
            prefer: "return=minimal"
        )
    }

    // MARK: - 소속 센터 (v0.3.13)

    /// 내 소속 센터(profiles.center) 서버값. **반드시 별도 GET 이다** — 별명 쿨타임·미니게임 공개와 같은 규약이고,
    /// 여기서 어기면 피해가 더 크다: 기존 설정 GET(fetchTokenUsageSettings)의 select 에 center 를 끼우면
    /// 마이그레이션이 아직 안 간 서버에서 42703 → 그 요청이 통째로 400 이 되어 **토큰 공개·수집·집중 모드까지**
    /// 같이 못 읽는다(1543~1552 가 그 사고를 기록한다). 컬럼/행이 없으면 nil.
    ///
    /// 반환은 **서버값 그대로**(`"seoul"`)다 — 화면 글자로 접는 것은 CenterLabel 한 곳이고, 스토어는 PATCH 로
    /// 되돌려 보낼 값을 들고 있어야 한다.
    package func fetchMyCenter(accessToken: String, userID: String) async throws -> String? {
        let data = try await send(
            path: "/rest/v1/profiles",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(userID)"),
                URLQueryItem(name: "select", value: "center")
            ],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode([ProfileCenterRow].self, from: data).first?.center
    }

    // ★ center 를 **쓰는** 길(PATCH)은 일부러 없다(사장님 지시 2026-09-12). 서버가 `profiles.center` 에
    //   `grant update` 를 주지 않으므로 이 토큰으로 보내는 PATCH 는 어차피 거절된다 — 함수만 남겨 두면
    //   호출부가 '조용히 실패하는 변경'을 만든다. 센터 정정은 운영자 SQL 이 유일한 경로다.

    // MARK: - 콕찌르기 / 토큰 사용량 공개 설정

    /// 착용 캐릭터를 서버에 저장한다. `set_character(p_id)` RPC 를 로그인 토큰으로 호출한다.
    ///
    /// **왜 서버에도 써야 하는가**: 캐릭터가 남에게 보이는 유일한 순간이 **울트라 찌르기**다 —
    /// `take_pokes` 가 보낸이의 `from_character` 를 실어 주고, 받는 쪽 화면을 그 캐릭터가 덮는다.
    /// 로컬(`CharacterSelection`)에만 저장하면 내 화면만 바뀌고 **남에게는 영원히 아잉**으로 보인다.
    ///
    /// **쓰기 경로가 이것뿐이다.** `authenticated` 에게 `profiles.character` 의 update 권한이 없어서
    /// PATCH 우회가 구조적으로 불가능하다(컬럼 단위 grant). 허용 목록도 서버 CHECK 하나가 유일한
    /// 출처이므로 클라가 목록을 다시 적지 않는다 — 모르는 id 는 `unknown_character` 로 돌아온다.
    ///
    /// `id` 가 nil 이면 **기본(아잉)으로 되돌린다**.
    package func setCharacter(accessToken: String, id: String?) async throws -> SetCharacterResponse {
        let data = try await send(
            path: "/rest/v1/rpc/set_character",
            method: "POST",
            body: SetCharacterRequest(pId: id),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(SetCharacterResponse.self, from: data)
    }

    // MARK: - 상점 / 루비 (v0.3.17)

    /// 상점 상태(루비·울트라 잔량 + 캐릭터 가격·보유)를 한 번에 받아 온다. `shop_state()` RPC.
    ///
    /// **왜 한 방인가**: 가격표와 보유 목록과 잔량은 **같은 순간의 것**이어야 한다. 셋을 따로 부르면
    /// 그 사이에 구매가 끼어들어 "가진 돈은 새 값, 보유 목록은 옛 값"인 화면이 만들어진다.
    package func fetchShopState(accessToken: String) async throws -> ShopStateResponse {
        let data = try await send(
            path: "/rest/v1/rpc/shop_state",
            method: "POST",
            body: EmptyBody(),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(ShopStateResponse.self, from: data)
    }

    /// 캐릭터를 산다. `buy_character(p_id)` RPC.
    ///
    /// **잔량 확인·차감·장부·소유 기입이 서버 한 트랜잭션 안에서 끝난다.** 클라는 가격도 잔량도
    /// 판정하지 않는다 — 아래 화면의 비활성화는 헛왕복을 줄이는 장치이지 게이트가 아니다.
    package func buyCharacter(accessToken: String, id: String) async throws -> BuyCharacterResponse {
        let data = try await send(
            path: "/rest/v1/rpc/buy_character",
            method: "POST",
            body: BuyCharacterRequest(pId: id),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(BuyCharacterResponse.self, from: data)
    }

    /// 상대에게 메시지. `send_message(p_to, p_body)` RPC 를 로그인 토큰으로 호출한다.
    ///
    /// **쿨타임이 없다**(v0.2.49 서버 계약). 근무중 게이트·집중 모드·텍스트 난간·200자 상한은 전부 서버가 강제하고,
    /// 아래 클라 게이트는 판정이 아니라 헛왕복 절감 장치다(무료 플랜).
    ///
    /// 응답은 poke_user 와 **같은 jsonb 규약**({status, …})이라 PokeSendResponse 를 그대로 재사용한다 —
    /// too_long/not_text 에 딸려 오는 `max_length` 만 이쪽이 더 읽는다.
    /// 갈리는 것은 도메인 어휘뿐이고 그건 MessageSendOutcome 이 맡는다(그 타입 주석에 이유가 있다).
    ///
    /// **빈 본문·200자 초과는 요청을 아예 내지 않고** 서버와 같은 status 로 즉답한다. 로컬 거절만 throw 로 만들면
    /// 호출부가 같은 실패를 catch 와 switch 두 곳에서 다뤄야 하고, 그 둘은 시간이 지나면 반드시 다른 문구를 낸다.
    /// 보내는 문자열도 원문이 아니라 정규화된 값이다 — 서버도 정규화하지만, 클라가 먼저 하면 NFD 한글이
    /// 서버에서만 6글자로 세어져 거절되는 사고가 사라진다(MessageBody.sanitized 주석의 실측 참고).
    ///
    /// **문자 종류는 여기서 판정하지 않는다.** 이모지 거부(옛 `.unsupportedCharacters`)는 3글자 시절의
    /// 규칙이었고, 지금 그 판정을 클라가 한 벌 더 가지면 서버의 `not_text` 집합과 갈리는 순간이 곧 버그다.
    package func sendMessage(accessToken: String, to userID: String, body: String) async throws -> PokeSendResponse {
        switch MessageBody.validate(body) {
        case .empty:
            return PokeSendResponse(status: "invalid")
        case .tooLong(let maxLength):
            // 서버가 같은 상황에서 실어 주는 키를 클라 즉답도 그대로 실어 준다 — 안 그러면 같은 실패가
            // 로컬이냐 서버냐에 따라 다른 숫자를 말한다(문구를 만드는 자리는 한 곳이어야 한다).
            return PokeSendResponse(status: "too_long", maxLength: maxLength)
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

    /// 최근 12시간 메시지 이력. `message_history(p_hours, p_limit)` RPC 를 로그인 토큰으로 호출한다.
    ///
    /// **take_pokes 와 완전히 다른 성격이다**: 저쪽은 원자 소비(한 번 받으면 사라진다)이고 이쪽은 **읽기 전용**이라
    /// 몇 번을 불러도 같은 것이 온다. 그래서 창을 열 때·[새로고침]·전송 성공·수신 폴링이 새 것을 물어왔을 때
    /// 부담 없이 다시 부를 수 있다(그래도 **폴링을 새로 만들지는 마라** — 무료 플랜이다).
    ///
    /// 인자 범위는 서버가 접는다(hours 1~24 / limit 1~500). 클라도 같은 값으로 한 번 접는 이유는
    /// "서버가 조용히 바꾼 값"과 "클라가 요청한 값"이 갈리면 화면의 안내 문구("12시간")가 거짓이 되기 때문이다.
    ///
    /// 반환은 **오래된 것부터**다(서버 계약). 그래도 스토어가 다시 정렬한다 — 순서가 곧 사용자가 읽는 순서라
    /// 서버 정렬을 신뢰하지 않는 것이 이 저장소의 규약이다(sortedForPokeDisplay 와 같은 근거).
    package func fetchMessageHistory(
        accessToken: String,
        hours: Int = 12,
        limit: Int = 200
    ) async throws -> [MessageHistoryEntry] {
        let data = try await send(
            path: "/rest/v1/rpc/message_history",
            method: "POST",
            body: MessageHistoryRequest(
                pHours: min(24, max(1, hours)),
                pLimit: min(500, max(1, limit))
            ),
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([MessageHistoryRow].self, from: data)
        // 클로저 인자 이름이 `row` 가 **아닌** 이유는 제보 목록과 같다(소스 계약 테스트가 그 문장을 센다).
        return rows.compactMap { historyRow -> MessageHistoryEntry? in
            // 본문이 비면 버린다 — 빈 말풍선은 "누가 뭘 보냈는데 내용이 없다"로 읽혀 사용자가 앱을 의심한다.
            let body = MessageBody.sanitized(historyRow.body ?? "")
            guard MessageBody.hasVisibleContent(body) else { return nil }
            // 상대가 누구인지 모르면 어느 대화에도 넣을 수 없다. 화면은 '묶음'이 곧 구조라 여기서 버린다.
            guard let peer = historyRow.peerUserId, !peer.isEmpty else { return nil }
            // epoch 가 정본이고 ISO 문자열은 폴백이다(TakenPokeRow.createdEpoch 와 같은 근거 — 소수초 파싱 함정).
            guard let createdAt = historyRow.createdEpoch.map({ Date(timeIntervalSince1970: TimeInterval($0)) })
                ?? historyRow.createdAt.flatMap({ parseDate($0) })
            else { return nil }
            return MessageHistoryEntry(
                id: historyRow.id,
                peerUserID: peer,
                // 별명이 없으면(탈퇴·익명화) 말풍선 주인을 "사용자"로 부른다 — 제보 목록과 같은 폴백.
                peerName: historyRow.peerDisplayName.flatMap { $0.isEmpty ? nil : $0 } ?? "사용자",
                peerAvatarURL: historyRow.peerAvatarUrl.flatMap { URL(string: $0) },
                body: body,
                createdAt: createdAt,
                // **is_mine 은 서버가 판정한다.** 클라가 from_user == 내 id 로 다시 세면 세션 세대가 갈리는
                // 창에서 남의 말이 내 말풍선으로 그려진다. 모르면 '받은 것'으로 본다(왼쪽 정렬이 안전한 쪽이다).
                isMine: historyRow.isMine ?? false
            )
        }
    }

    /// 콕찌르기 대상 디렉토리(앱 사용자 전체, 본인 제외 + 근무중 여부). app_user_directory() RPC 를 로그인 토큰으로 호출한다.
    package func fetchPokeDirectory(accessToken: String) async throws -> [PokeDirectoryRow] {
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
    package func fetchTokenUsageSettings(
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

    /// 서버가 아는 최신 릴리스(v0.3.20). `app_latest_release()` RPC 를 **anon Bearer**(accessToken 없이)로 호출한다 —
    /// 로그인 전·로그아웃 상태에서도 업데이트는 알아야 하므로 로그인 토큰에 묶지 않는다(lookupTeamByCode 와 같은 문).
    /// 반환은 jsonb 단일 객체(배열 아님)라 그대로 디코드한다. 함수가 없는 옛 서버(404)·일시 장애(5xx)는 다른 호출과 같이
    /// throw 하고, 호출부(UpdateCheckStore.checkServerNow)가 조용히 삼킨다 — GitHub 경로가 폴백으로 남아 있다.
    package func fetchLatestRelease() async throws -> AppLatestRelease {
        let data = try await send(
            path: "/rest/v1/rpc/app_latest_release",
            method: "POST",
            body: EmptyBody(),
            accessToken: nil,
            prefer: nil
        )
        return try decoder.decode(AppLatestRelease.self, from: data)
    }

    /// 내 토큰 사용량 공개 여부 갱신. profiles 자기 행을 PATCH 한다(RLS 로 본인 행만 허용). 반환 없음(return=minimal).
    package func updateTokenUsagePublic(accessToken: String, userID: String, isPublic: Bool) async throws {
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
    package func setDisplayName(accessToken: String, name: String) async throws -> DisplayNameChangeResponse {
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
    package func fetchDisplayNameChangedAt(accessToken: String, userID: String) async throws -> Date? {
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
    package func sendPasswordResetCode(email: String) async throws {
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
    package func verifyPasswordResetCode(email: String, code: String) async throws -> SupabaseSession {
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
    package func updatePassword(accessToken: String, newPassword: String) async throws {
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
    package static func passwordRecoveryError(_ error: SupabaseWorkServiceError) -> SupabaseWorkServiceError {
        // v0.2.36 부터 공용 매핑의 상태코드 게이트가 429 를 직접 .rateLimited 로 접으므로 이 값으로는
        // 더 이상 오지 않는다. 분기를 지우지 않는 이유는 방어다 — 게이트를 안 지난 채 이 재분류에 들어오는
        // 경로가 생겨도 429 가 인증 오류로 표시되는 회귀만은 막는다(남은 초는 알 길이 없으니 nil).
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
    /// 공용 매핑(serviceError 의 429 게이트)과 이 재분류가 **같은 파서를 공유한다** — 둘이 갈리면 같은 본문의
    /// 남은 초가 경로에 따라 달라진다. 그래서 private 이 아니다.
    package static func retryAfterSeconds(in lowercasedMessage: String) -> Int? {
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

// MARK: - 제보(버그·요청) (v0.2.48)
//
// RPC 여섯(v0.3.14 에 답장 둘이 늘었다) 전부 **로그인 토큰**으로만 부른다. anon 으로 부를 수 있는 문을 열지 않는다 —
// 이 저장소는 이미 anon RPC 유출을 한 번 겪었다(standing risk P0).
//
// **스키마 부재를 여기서 접지 않는다.** 서버가 아직 배포 전이면 PGRST202(404 "… in the schema cache")가
// 공용 매핑을 지나 `.databaseSchemaMissing` 으로 올라가고, 그걸 '실패'와 가르는 일은 호출부(스토어)의 몫이다 —
// 미니게임 보드가 세운 관례 그대로다. 여기서 빈 배열로 접어 버리면 스토어는 "표가 없다"와 "정말 0건이다"를
// 영영 가를 수 없고, 화면은 마이그레이션 전에도 "제보가 없어요"라고 단정한다.
//
// ★ 제보 본문은 사용자가 쓴 글이다. 이 아래 어디에도 `print`/`Logger` 를 붙이지 마라.
extension SupabaseWorkService {
    /// 제보 한 건을 보낸다. `submit_feedback(p_kind, p_body, p_app_version, p_os_version)` → uuid.
    ///
    /// 반환 id 를 **옵셔널로 흘리는** 이유: 화면 어디에도 쓰지 않는 값인데, 스칼라 응답 모양이 조금만
    /// 달라도(문자열이 아니라 객체로 감싸 오는 식) 디코드가 throw 되어 **성공한 전송이 실패로 보인다**.
    /// 그러면 사용자는 같은 글을 두 번 보내고 24시간 상한만 축낸다.
    package func submitFeedback(
        accessToken: String,
        kind: FeedbackKind,
        body: String,
        appVersion: String,
        osVersion: String
    ) async throws -> String? {
        let data = try await send(
            path: "/rest/v1/rpc/submit_feedback",
            method: "POST",
            body: FeedbackSubmitRequest(
                pKind: kind.rawValue,
                pBody: body,
                pAppVersion: appVersion,
                pOsVersion: osVersion
            ),
            accessToken: accessToken,
            prefer: nil
        )
        return try? decoder.decode(String.self, from: data)
    }

    /// 제보 목록. `feedback_list(p_status, p_limit)` — **관리자면 전부, 아니면 자기 것만**이고 그 판정은 서버다.
    /// 미해결 먼저 → 최신순으로 오지만, 정렬을 신뢰하지 않고 호출부가 다시 세운다(미니게임 보드와 같은 규약).
    package func fetchFeedbackList(
        accessToken: String,
        status: FeedbackStatus?,
        limit: Int
    ) async throws -> [FeedbackReport] {
        let data = try await send(
            path: "/rest/v1/rpc/feedback_list",
            method: "POST",
            body: FeedbackListRequest(pStatus: status?.rawValue, pLimit: limit),
            accessToken: accessToken,
            prefer: nil
        )
        let rows = try decoder.decode([FeedbackReportRow].self, from: data)
        // 클로저 인자 이름이 `row` 가 **아닌** 이유: 소스 계약 테스트(assemblyAndApplyFunctionsAreSingleSourced)가
        // 이 파일 안의 문자열 `return rows.map { row in` 이 정확히 1회인지를 세어 "팀 상태 조립이 두 벌이 됐다"를
        // 잡는다. 우리 매핑이 그 문장을 그대로 쓰면 **관계없는 테스트가 빨개지고**, 다음 사람은 그 테스트를 고치려다
        // 진짜 계약을 지운다. 미니게임 보드도 같은 이유로 `boardRow` 를 쓴다.
        return rows.map { reportRow in
            FeedbackReport(
                id: reportRow.id,
                userID: reportRow.userId,
                // 서버가 모르는 종류를 보내면 '요청'으로 접는다. 여기만 접는 이유: kind 는 서버 check 제약이
                // 두 값으로 못 박은 닫힌 집합이라 확장 협상 대상이 아니고(status 와 다른 점), 배지 색 하나만
                // 좌우한다 — 반면 status 를 접으면 처리 상태가 오배달된다(FeedbackStatus.other 주석).
                kind: FeedbackKind(rawValue: reportRow.kind) ?? .request,
                body: reportRow.body,
                status: FeedbackStatus(rawValue: reportRow.status ?? FeedbackStatus.open.rawValue),
                adminNote: reportRow.adminNote,
                // 이 컬럼을 아직 안 내려주는 서버(마이그레이션 전)에서는 nil 이다 — 화면은 답장 본문만
                // 그리고 시각은 말하지 않는다(모르면 침묵한다). 여기서 Date() 로 지어내면 8일 전 답장이
                // '방금'으로 뜬다.
                adminNoteAt: reportRow.adminNoteAt.flatMap { parseDate($0) },
                appVersion: reportRow.appVersion,
                osVersion: reportRow.osVersion,
                createdAt: reportRow.createdAt.flatMap { parseDate($0) },
                updatedAt: reportRow.updatedAt.flatMap { parseDate($0) },
                authorName: reportRow.displayName ?? "사용자",
                authorAvatarURL: reportRow.avatarUrl.flatMap { URL(string: $0) }
            )
        }
    }

    /// 제보 상태를 바꾼다. `set_feedback_status(p_id, p_status, p_note)` — **관리자만**이고, 아니면 서버가
    /// `FEEDBACK_FORBIDDEN` 예외를 던진다(공용 매핑을 지나 `.authMessage("FEEDBACK_FORBIDDEN")` 으로 온다).
    /// 클라의 탭 감춤은 발견성일 뿐 차단이 아니다 — 차단은 언제나 이 RPC 안에서 일어난다.
    package func setFeedbackStatus(
        accessToken: String,
        id: String,
        status: FeedbackStatus,
        note: String?
    ) async throws {
        try await sendNoBody(
            path: "/rest/v1/rpc/set_feedback_status",
            method: "POST",
            body: FeedbackStatusRequest(pId: id, pStatus: status.rawValue, pNote: note),
            accessToken: accessToken,
            prefer: nil
        )
    }

    /// 제보에 **답장을 보낸다**. `reply_feedback(p_id, p_note)` → 서버가 찍은 `admin_note_at`.
    /// 관리자가 아니면 `FEEDBACK_FORBIDDEN`, 빈 답장이면 `FEEDBACK_EMPTY_REPLY`,
    /// 500자 초과면 `FEEDBACK_NOTE_TOO_LONG`, 없는 제보면 `FEEDBACK_NOT_FOUND` 다 —
    /// 넷 다 공용 매핑을 지나 `.authMessage(원문)` 으로 올라가고, 사람 말로 옮기는 일은 `FeedbackFailure` 가 한다.
    ///
    /// ★ **상태는 안 건드린다.** v0.3.14 부터 답장과 상태는 별개의 왕복이다.
    ///
    /// **파싱에 실패해도 throw 하지 않는 이유**(submitFeedback 이 반환 id 를 흘리는 것과 같은 근거):
    /// 여기까지 왔다는 것은 서버가 **이미 답장을 저장했다**는 뜻이다. 스칼라 모양이 조금 달라졌다고
    /// (소수초 자릿수·오프셋 표기) 성공한 전송을 실패로 뒤집으면 관리자는 같은 답장을 다시 보내고,
    /// 그때 서버 트리거는 `is distinct from` 때문에 시각을 안 찍어 화면은 영영 "안 갔다"고 말한다.
    /// 그래서 시각 하나만 이 맥의 시계로 근사한다 — 다음 `feedback_list` 가 서버 값으로 덮는다.
    package func replyFeedback(accessToken: String, id: String, note: String) async throws -> Date {
        let data = try await send(
            path: "/rest/v1/rpc/reply_feedback",
            method: "POST",
            body: FeedbackReplyRequest(pId: id, pNote: note),
            accessToken: accessToken,
            prefer: nil
        )
        return (try? decoder.decode(String.self, from: data)).flatMap { parseDate($0) } ?? Date()
    }

    /// **내 제보에 달린 답장 중 가장 최근 시각**. `feedback_reply_latest()` — 인자 없는 RPC 라 본문은 `{}` 다
    /// (`feedback_open_count` 와 같은 규약: PostgREST 는 본문의 키 집합으로 함수를 고른다).
    ///
    /// 관리자라고 전체를 세지 않는다 — 이건 "내 제보에 답장 왔나"이지 운영 배지가 아니다. 그 판정도 서버다.
    /// 답장이 하나도 없으면 서버가 `null` 을 준다 → nil(없는 것을 지어내지 않는다).
    package func fetchFeedbackReplyLatest(accessToken: String) async throws -> Date? {
        let data = try await send(
            path: "/rest/v1/rpc/feedback_reply_latest",
            method: "POST",
            body: EmptyBody(),
            accessToken: accessToken,
            prefer: nil
        )
        // `null` 이면 디코드가 throw 하고 그게 곧 "없다"는 답이다 — 그 자리에 Date() 를 지어내면
        // 답장을 한 번도 못 받은 사람에게 배너가 뜬다.
        return (try? decoder.decode(String.self, from: data)).flatMap { parseDate($0) }
    }

    /// 미해결 제보 건수. `feedback_open_count()` — 인자 없는 RPC라 본문은 `{}` 다(take_pokes 의 옛 모양과 같은 규약:
    /// PostgREST 는 본문의 **키 집합**으로 함수를 고르므로 빈 객체를 보내야 인자 없는 서명에 맞는다).
    /// 관리자가 아니면 서버가 0 을 돌려준다 — 클라가 판정하지 않는다.
    package func fetchFeedbackOpenCount(accessToken: String) async throws -> Int {
        let data = try await send(
            path: "/rest/v1/rpc/feedback_open_count",
            method: "POST",
            body: EmptyBody(),
            accessToken: accessToken,
            prefer: nil
        )
        return (try? decoder.decode(Int.self, from: data)) ?? 0
    }
}

// MARK: - 1:1 오목 (v0.3.27)

/// 오목 RPC 8개. 경로는 `/rest/v1/rpc/gomoku_*`, 본문은 pSnake 구조체(인코더가 p_snake 로 바꾼다), 전부 `p_protocol` 을 싣는다.
///
/// **판정은 전부 서버 몫이다.** 근무 여부·집중 모드·잔액·차례·시간 초과·금수는 서버가 한 트랜잭션 안에서 본다.
/// 앱의 금수 표시(GomokuRules)는 헛왕복을 줄이는 장치이지 게이트가 아니다 — 서버 gomoku_judge 가 같은 코퍼스로 막는다.
extension SupabaseWorkService {
    package func gomokuLobby(accessToken: String) async throws -> GomokuLobbyResponse {
        try await gomokuRPC("gomoku_lobby", body: GomokuLobbyRequest(), accessToken: accessToken)
    }

    package func gomokuChallenge(accessToken: String, opponentID: String, stake: Int) async throws -> GomokuActionResponse {
        try await gomokuRPC(
            "gomoku_challenge",
            body: GomokuChallengeRequest(pOpponent: opponentID, pStake: stake),
            accessToken: accessToken,
            retriesDeadlockOnce: true
        )
    }

    package func gomokuCancel(accessToken: String, matchID: String) async throws -> GomokuActionResponse {
        try await gomokuRPC(
            "gomoku_cancel", body: GomokuMatchRequest(pMatchId: matchID), accessToken: accessToken,
            retriesDeadlockOnce: true
        )
    }

    package func gomokuRespond(accessToken: String, matchID: String, accept: Bool) async throws -> GomokuActionResponse {
        try await gomokuRPC(
            "gomoku_respond",
            body: GomokuRespondRequest(pMatchId: matchID, pAccept: accept),
            accessToken: accessToken,
            retriesDeadlockOnce: true
        )
    }

    package func gomokuMove(
        accessToken: String, matchID: String, expectedSeq: Int, x: Int, y: Int
    ) async throws -> GomokuActionResponse {
        try await gomokuRPC(
            "gomoku_move",
            body: GomokuMoveRequest(pMatchId: matchID, pExpectedSeq: expectedSeq, pX: x, pY: y),
            accessToken: accessToken,
            retriesDeadlockOnce: true
        )
    }

    package func gomokuResign(accessToken: String, matchID: String) async throws -> GomokuActionResponse {
        try await gomokuRPC(
            "gomoku_resign", body: GomokuMatchRequest(pMatchId: matchID), accessToken: accessToken,
            retriesDeadlockOnce: true
        )
    }

    /// `sinceChatSeq` 는 **기본값을 두지 않는다.** 두면 부르는 자리가 조용히 0 으로 떨어져 매번 판 전체 채팅을
    /// 다시 받고(무료 플랜 왕복), 그 사실이 아무 데서도 안 보인다. 부르는 쪽이 자기 번호를 말해야 한다.
    package func gomokuState(
        accessToken: String, matchID: String, sinceSeq: Int, sinceChatSeq: Int
    ) async throws -> GomokuStateResponse {
        try await gomokuRPC(
            "gomoku_state",
            body: GomokuStateRequest(pMatchId: matchID, pSinceSeq: sinceSeq, pSinceChatSeq: sinceChatSeq),
            accessToken: accessToken
        )
    }

    package func gomokuInbox(accessToken: String) async throws -> GomokuInboxResponse {
        try await gomokuRPC("gomoku_inbox", body: GomokuInboxRequest(), accessToken: accessToken)
    }

    /// 대국 채팅 한 줄 보내기(0.3.28). `kind == .quick` 이면 `body` 는 **코드**(hi·gg…)다.
    ///
    /// **쓰기라서 `retriesDeadlockOnce` 를 켠다.** 교착으로 죽은 트랜잭션은 통째로 되돌아가므로(채팅 행·seq 증가·신호 전부 0)
    /// 재시도는 첫 시도와 같은 요청이고, 그사이 판이 끝났으면 서버가 `not_active` 로 멱등하게 거절한다.
    package func gomokuChatSend(
        accessToken: String, matchID: String, kind: GomokuChatKind, body: String
    ) async throws -> GomokuChatResponse {
        try await gomokuRPC(
            "gomoku_chat_send",
            body: GomokuChatSendRequest(pMatchId: matchID, pKind: kind.rawValue, pBody: body),
            accessToken: accessToken,
            retriesDeadlockOnce: true
        )
    }

    /// **끝난 판에서 나간다**(0.3.28). 둘 다 나간 순간 서버가 그 판 채팅을 즉시 지운다. 멱등이고 초인종은 울리지 않는다.
    ///
    /// 쓰기라서 `retriesDeadlockOnce` 를 켠다 — 교착으로 죽은 트랜잭션은 통째로 되돌아가므로 재시도는 같은 요청이고,
    /// 이미 나간 뒤라면 서버가 멱등하게 같은 ok 를 돌려준다.
    package func gomokuLeave(accessToken: String, matchID: String) async throws -> GomokuLeaveResponse {
        try await gomokuRPC(
            "gomoku_leave", body: GomokuMatchRequest(pMatchId: matchID), accessToken: accessToken,
            retriesDeadlockOnce: true
        )
    }

    /// 이 판 채팅 끄기·켜기(0.3.28). 음소거는 내 화면 설정이 아니라 **서버가 아는 판 상태**다 — 상대에게 티가 나야 한다.
    package func gomokuChatMute(accessToken: String, matchID: String, muted: Bool) async throws -> GomokuChatResponse {
        try await gomokuRPC(
            "gomoku_chat_mute",
            body: GomokuChatMuteRequest(pMatchId: matchID, pMuted: muted),
            accessToken: accessToken,
            retriesDeadlockOnce: true
        )
    }

    /// Postgres 교착(SQLSTATE 40P01). PostgREST 는 500 + 본문 `code` 로 싣는다 — 공용 `send` 의 매핑은 5xx 를
    /// 코드 없이 접으므로, 오목 호출은 본문 코드를 직접 본다(헤더 구성은 `send` 와 같다).
    package static let gomokuDeadlockCode = "40P01"

    /// `retriesDeadlockOnce` — 오목 **쓰기** RPC(challenge·cancel·respond·move·resign)만 켠다. 교착 응답이면 한 번 더 보낸다.
    ///
    /// 왜 한 번 더 보내도 안전한가: 교착으로 죽은 쪽 트랜잭션은 Postgres 가 **통째로 되돌린다**(수·차감·원장·신호 전부 0).
    /// 그래서 재시도는 첫 시도와 같은 요청이고, 그사이 판이 바뀌었으면 서버 가드가 멱등하게 거절한다 —
    /// 착수는 `p_expected_seq` 가 어긋나 stale, 수락·거절·취소는 pending 상태가 아니라 not_pending,
    /// 기권은 진행 중이 아니라 not_active, 신청은 대기 신청 유니크 인덱스로 already_pending 이다.
    /// 교착은 상금 cron 의 등수 순 지갑 잠금과 오목의 uuid 순 잠금이 엇갈릴 때 생긴다(서버 검증 보고 set #2).
    /// 읽기(lobby·inbox·state)는 켜지 않는다 — 실패하면 다음 계기(신호·폴링)가 다시 읽는다.
    private func gomokuRPC<Body: Encodable, Response: Decodable>(
        _ name: String, body: Body, accessToken: String, retriesDeadlockOnce: Bool = false
    ) async throws -> Response {
        guard let anonKey else {
            throw SupabaseWorkServiceError.missingAnonKey
        }
        var request = URLRequest(url: try url(path: "/rest/v1/rpc/\(name)", queryItems: []))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        var attempt = 0
        while true {
            attempt += 1
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            if 200..<300 ~= statusCode {
                return try decoder.decode(Response.self, from: data)
            }
            if retriesDeadlockOnce, attempt == 1, postgrestErrorCode(in: data) == Self.gomokuDeadlockCode {
                continue
            }
            throw serviceError(statusCode: statusCode, data: data)
        }
    }
}
