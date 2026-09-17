import Foundation

// D-base(iOS 0.1): **맥 전용 쓰기**를 한 파일로 뗀 자리. `#if os(macOS)` 라 폰 앱·위젯 바이너리에는 컴파일되지 않는다.
//
// 왜 파일을 가르는가(SPEC-ios §0-2 · ios-inventory §3·§10 R1~R4): 폰이 이 메서드를 **한 번이라도** 부르면 사고가 난다 —
//  · take_pokes 는 원자 소비라 폰이 맥의 찌르기·메시지 말풍선을 훔친다(R3).
//  · profiles.app_build PATCH 는 폰 빌드 번호로 맥 빌드(79~)를 덮어 오목·채팅·Codex 게이트를 틀어 버린다(R1).
//  · work_tick·하트비트·기기 행·세션 PATCH·close_abandoned_work_sessions 는 근무 시간을 위조하거나 남의 세션을 마감한다(R2·R4).
//  · ultra_wallet_sync 는 읽기가 아니라 적립 쓰기이고, buy_ultra·찌르기·토큰 업로드·집중 모드·가입(팀 합류/생성)은 폰 범위 밖이다.
// "부르지 않기로 약속"은 코드 리뷰로만 지켜진다. 컴파일에서 사라지면 약속이 필요 없다 — iOS 에서 이 이름을 부르면
// `value of type 'SupabaseWorkService' has no member …` 로 빌드가 멈춘다.
//
// 맥은 바뀌는 것이 없다: 같은 actor 의 확장이라 격리·접근이 같고, 본문은 SupabaseWorkService.swift 에서 **글자 그대로** 옮겼다.
// 소스 계약 테스트는 두 조각을 `CheckCoreSourceLayout.joinedSplitSource("SupabaseWorkService.swift")` 로 이어 읽는다.
// 폰이 쓰는 읽기·허용 쓰기(메시지·읽음·할 일·오목·상점 캐릭터·별명·아바타·공개 설정·주간 목표)는 원래 파일에 남아 있다.

#if os(macOS)
extension SupabaseWorkService {
    package func startWork(accessToken: String, teamID: String, userID: String, sessionID: String, startedAt: Date = Date()) async throws {
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

    /// autoClosedReason: 자동 마감이면 사유(away/sleep/long_session). 사용자가 누른 종료는 nil 이고,
    /// 그때의 요청 **본문** 바이트는 v0.2.34 와 같다(쿼리에는 v0.2.36 부터 id 필터가 더해졌다 — 아래 주석).
    package func stopWork(
        accessToken: String,
        teamID: String,
        userID: String,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        fallbackSessionID: String,
        autoClosedReason: AutoCloseReason? = nil
    ) async throws {
        let closedStamp = dateFormatter.string(from: Date())
        func patch(includeReason: Bool) async throws -> Data {
            try await send(
                path: "/rest/v1/work_sessions",
                method: "PATCH",
                queryItems: [
                    // ★ 내 세션만 명중해야 한다. id 없이 ended_at=is.null 로만 걸면, 깨어난 맥의 소급
                    //   잠자기 마감이 그 사이 **다른 맥이 연 새 세션**을 잡아 과거 시각으로 덮어 파괴한다.
                    //   0행이 되면 아래 폴백 POST(on_conflict=id)가 내 닫힌 세션을 만드므로 마감은 잃지 않는다.
                    URLQueryItem(name: "id", value: "eq.\(fallbackSessionID)"),
                    URLQueryItem(name: "team_id", value: "eq.\(teamID)"),
                    URLQueryItem(name: "user_id", value: "eq.\(userID)"),
                    URLQueryItem(name: "ended_at", value: "is.null")
                ],
                body: StopSessionRequest(
                    endedAt: dateFormatter.string(from: endedAt),
                    durationSeconds: max(0, durationSeconds),
                    autoClosedAt: includeReason ? closedStamp : nil,
                    autoClosedReason: includeReason ? autoClosedReason?.rawValue : nil
                ),
                accessToken: accessToken,
                prefer: "return=representation"
            )
        }
        var patched = Data()
        if autoClosedReason == nil {
            patched = try await patch(includeReason: false)
        } else {
            // 사유 컬럼이 없는 서버에서 **종료 자체가 실패하면** 그 세션은 영영 열린 채 남는다(팀원 화면
            // '근무중' 고착 + 타이머 계속). 사유는 부가 정보이므로, 못 쓰면 사유 없이 마감하는 쪽이 옳다.
            try await withoutNewColumns(
                { patched = try await patch(includeReason: true) },
                retry: { patched = try await patch(includeReason: false) }
            )
        }
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
                    durationSeconds: max(0, durationSeconds),
                    autoClosedAt: autoClosedReason == nil ? nil : closedStamp,
                    autoClosedReason: autoClosedReason?.rawValue
                ),
                accessToken: accessToken,
                prefer: "resolution=ignore-duplicates,return=minimal"
            )
            // ★ 0행 = 서버가 이 세션을 **이미 닫아 뒀다**(스캐빈저가 먼저 발화했다). 폴백 INSERT 는
            //   on_conflict=id + ignore-duplicates 라 아무것도 하지 않으므로, 사유는 여기서만 고칠 수 있다.
            //   잠자기 경로가 이 갈래로 오는 것이 정상이다: 뚜껑을 닫으면 10분 뒤 서버가 'abandoned' 로
            //   먼저 마감한다. 이 정정이 빠지면 2파의 핵심 이득("뚜껑 닫고 나간 사람의 마감 시각·사유가
            //   실제 잠든 순간과 맞는다")이 통째로 사라진다(docs/away-close.md 4절).
            if let autoClosedReason {
                try? await correctAutoClose(
                    accessToken: accessToken,
                    userID: userID,
                    sessionID: fallbackSessionID,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    reason: autoClosedReason,
                    closedStamp: closedStamp
                )
            }
        }
        try await upsertStatus(accessToken: accessToken, teamID: teamID, userID: userID, status: "off_work", activeSessionID: nil)
    }

    /// 서버가 먼저 닫아 둔 **내** 세션의 자동 마감 사유를 정정한다(그리고 ended_at 은 **더 이르게만** 당긴다).
    ///
    /// 두 요청으로 나뉘는 이유는 "늦추는 것은 위조"라는 규약을 서버 필터로 강제하기 위해서다:
    ///  1. `ended_at=gt.<내 시각>` 필터를 건 PATCH — 서버 값이 내 값보다 **늦을 때만** 닿는다.
    ///  2. 1이 0행이면(서버 값이 이미 더 이르다) 사유만 고친다. ended_at 은 손대지 않는다.
    /// 실패는 삼킨다(호출부의 try?) — 정정은 부가 이득이고, 여기서 던지면 이미 성공한 마감이 큐에서 재생된다.
    ///
    /// **abandoned 만 고친다**(두 PATCH 모두 `auto_closed_reason=eq.abandoned`): 이 정정의 의미는
    /// "스캐빈저가 방치로 닫은 것을 실제 사유·시각으로 되돌린다"까지다. 필터가 없으면 — 맥 A 잠듦 →
    /// 서버 abandoned 마감 → 맥 B 가 백스톱으로 인수해 근무 후 정당하게 마감(같은 세션 행) — 한참 뒤
    /// 깨어난 A 의 소급 정정이 그 **정당한 나중 마감**을 A 의 잠자기 시각으로 당겨 근무를 파괴한다
    /// (gt 필터는 시각만 보므로 이 경우를 못 거른다). handleWake 경로와 v0.2.36 의 수용 지점 정정이
    /// 모두 이 함수를 지나므로, 여기 한 곳의 필터가 두 경로를 함께 봉쇄한다.
    private func correctAutoClose(
        accessToken: String,
        userID: String,
        sessionID: String,
        startedAt: Date,
        endedAt: Date,
        reason: AutoCloseReason,
        closedStamp: String
    ) async throws {
        let narrowed = try await send(
            path: "/rest/v1/work_sessions",
            method: "PATCH",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(sessionID)"),
                URLQueryItem(name: "user_id", value: "eq.\(userID)"),
                URLQueryItem(name: "ended_at", value: "gt.\(dateFormatter.string(from: endedAt))"),
                URLQueryItem(name: "auto_closed_reason", value: "eq.abandoned")
            ],
            body: AutoCloseCorrectionRequest(
                endedAt: dateFormatter.string(from: endedAt),
                durationSeconds: max(0, Int(endedAt.timeIntervalSince(startedAt))),
                autoClosedAt: closedStamp,
                autoClosedReason: reason.rawValue
            ),
            accessToken: accessToken,
            prefer: "return=representation"
        )
        let narrowedRows = (try? decoder.decode([WorkSessionRow].self, from: narrowed)) ?? []
        guard narrowedRows.isEmpty else { return }
        try await sendNoBody(
            path: "/rest/v1/work_sessions",
            method: "PATCH",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(sessionID)"),
                URLQueryItem(name: "user_id", value: "eq.\(userID)"),
                URLQueryItem(name: "ended_at", value: "not.is.null"),
                URLQueryItem(name: "auto_closed_reason", value: "eq.abandoned")
            ],
            body: AutoCloseReasonPatchRequest(autoClosedAt: closedStamp, autoClosedReason: reason.rawValue),
            accessToken: accessToken,
            prefer: "return=minimal"
        )
    }

    /// 근무중 생존신호. work_statuses.last_seen_at(+updated_at)을 현재 시각으로 갱신한다.
    /// upsertStatus 를 재사용하므로 active_session_id 도 유지된다.
    /// lastInputAt: 이 맥이 관측한 마지막 의미 있는 입력 시각(v0.2.35). 같은 요청에 얹으므로 왕복은 그대로 1회다.
    /// **소유 맥은 반드시 sessionID 와 함께 보낸다** — away 자격 판정(away_input_observable)이 "지금 세션을
    /// 소유한 기기 행" 을 요구하므로, 세션을 안 실으면 그 사용자는 조용히 away 마감 대상에서 영원히 빠진다.
    package func heartbeat(accessToken: String, teamID: String, userID: String, sessionID: String, lastInputAt: Date? = nil) async throws {
        try await upsertStatus(
            accessToken: accessToken,
            teamID: teamID,
            userID: userID,
            status: "working",
            activeSessionID: sessionID,
            lastInputAt: lastInputAt
        )
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
    package func upsertStatusDevice(
        accessToken: String,
        teamID: String,
        userID: String,
        deviceID: String,
        sessionID: String,
        openedSession: Bool,
        lastInputAt: Date? = nil
    ) async throws {
        let stamp = dateFormatter.string(from: Date())
        func post(includeInput: Bool) async throws {
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
                    lastInputAt: includeInput ? lastInputAt.map { dateFormatter.string(from: $0) } : nil,
                    openedSession: openedSession
                ),
                accessToken: accessToken,
                prefer: "resolution=merge-duplicates,return=minimal"
            )
        }
        guard lastInputAt != nil else {
            try await post(includeInput: false)
            return
        }
        try await withoutNewColumns({ try await post(includeInput: true) }, retry: { try await post(includeInput: false) })
    }

    /// **비소유 맥**(다른 맥이 연 세션을 미러링 중)이 자기 기기 행에 `last_input_at` 만 쓴다.
    /// 이 한 요청이 없으면 "아이맥에서 시작 → 노트북으로 옮겨 작업"이 결정론적으로 매일 오마감된다:
    /// 소유 맥의 last_input_at 은 얼어붙고, 노트북은 아무것도 보고하지 않아 서버의 max 규칙이 구제하지 못한다.
    ///
    /// **session_id / last_seen_at / opened_session 을 담지 않는 것이 이 함수의 전부다**(StatusDeviceInputRequest
    /// 주석 참조). 담으면 소유권 판정의 증거가 되어 살아 있는 맥의 세션을 서로 뺏는 v0.2.16 사고로 되돌아간다.
    package func reportDeviceInput(
        accessToken: String,
        teamID: String,
        userID: String,
        deviceID: String,
        lastInputAt: Date
    ) async throws {
        try await sendNoBody(
            path: "/rest/v1/work_status_devices",
            method: "POST",
            queryItems: [URLQueryItem(name: "on_conflict", value: "team_id,user_id,device_id")],
            body: StatusDeviceInputRequest(
                teamId: teamID,
                userId: userID,
                deviceId: deviceID,
                lastInputAt: dateFormatter.string(from: lastInputAt)
            ),
            accessToken: accessToken,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    /// 방치 세션 서버 자동 마감 RPC. close_abandoned_work_sessions() 를 로그인 토큰으로 호출하고
    /// 마감된 세션 수(int)를 돌려받는다. 서버 cron 이 주 경로이고 이건 클라 스캐빈저 폴백에서 쓴다.
    /// 스칼라 int 반환 RPC 라 PostgREST 가 본문에 숫자 하나(예: 3)를 준다 — 그대로 파싱한다(빈/비정상 응답은 0).
    package func closeAbandonedSessions(accessToken: String) async throws -> Int {
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

    // MARK: - 자리 비움 자동 마감 (v0.2.35 / docs/away-close.md)

    /// `away_sync()` — **임계값의 유일한 출처**다. 사장님 확정 사항이라 클라에 리터럴을 두지 않는다:
    /// 이 숫자는 실측 없이 정한 값이고 계측 후 SQL 한 줄로 바뀌는데, 브루 지연으로 절반이 옛 값을 쓰면 안 된다.
    ///
    /// 마이그레이션이 아직 안 나간 서버에서는 PGRST202(404)가 오고 공용 매핑이 `.databaseSchemaMissing`
    /// 으로 접는다 — 그것을 `AwaySyncUnavailable` 로 다시 접어 던진다(ultra_wallet_sync 와 같은 관용구).
    /// 스토어는 이 오류를 받으면 정책을 비워 **마감을 멈춘다**: 임계를 모르는 채 리터럴로 마감하는 것이
    /// 이 기능에서 가장 나쁜 실패 모드다.
    package func awaySync(accessToken: String) async throws -> AwaySync {
        let data: Data
        do {
            data = try await send(
                path: "/rest/v1/rpc/away_sync",
                method: "POST",
                body: AwaySyncRequest(),
                accessToken: accessToken,
                prefer: nil
            )
        } catch SupabaseWorkServiceError.databaseSchemaMissing {
            throw AwaySyncUnavailable()
        }
        guard let response = try? decoder.decode(AwaySyncResponse.self, from: data) else {
            throw AwaySyncUnavailable()
        }
        return awaySync(from: response)
    }

    /// 응답 원문 → 도메인. **정책은 임계가 실제로 온 경우에만 만든다** — 0/음수/키 부재는 전부 "모른다"이고,
    /// 모를 때의 안전한 기본값은 "안 끊는다"다.
    package func awaySync(from response: AwaySyncResponse) -> AwaySync {
        let isOK = response.status == "ok"
        var policy: AwayPolicy?
        if let threshold = response.closeThresholdSeconds, threshold > 0 {
            policy = AwayPolicy(
                closeThresholdSeconds: TimeInterval(threshold),
                serverNow: response.serverNow.flatMap(parseDate)
            )
        }
        var open: AwayOpenSession?
        if let payload = response.openSession, let id = payload.id {
            open = AwayOpenSession(
                sessionID: id,
                startedAt: payload.startedAt.flatMap(parseDate),
                lastInputAt: payload.lastInputAt.flatMap(parseDate),
                // 키가 없으면 false. 모르는 자격을 참으로 승격시키면 혼합 함대(구버전 맥이 섞인 사용자)의
                // 살아 있는 근무가 매일 지워진다 — 서버 백스톱의 완화는 클라보다 30분 늦어 도달하지 못한다.
                closeEligible: payload.closeEligible ?? false
            )
        }
        return AwaySync(isOK: isOK, policy: policy, openSession: open)
    }

    // MARK: - 근무 틱 통합 RPC (v0.2.38 S3 / docs/work-tick.md)

    package static let workTickPath = "/rest/v1/rpc/work_tick"

    /// work_tick 요청 조립. 스탬프 형식은 기존 요청과 **같은 포매터**(dateFormatter)다 — `p_seen_at` 은 upsertStatus 의
    /// `last_seen_at`/`updated_at`, `p_since` 는 fetchWeeklySessions 의 `ended_at=gte.` 와 글자 단위로 같아야 한다.
    /// `now` 하나로 세 값을 만든다(기존 경로는 함수마다 `Date()` 를 따로 읽었지만 ms 차이뿐이라 의미가 없다).
    package func makeWorkTickRequest(
        teamID: String?,
        heartbeat: Bool,
        sessionID: String?,
        deviceID: String?,
        openedSession: Bool,
        lastInputAt: Date?,
        includeMeta: Bool,
        now: Date
    ) -> WorkTickRequest {
        WorkTickRequest(
            pTeamId: teamID,
            pHeartbeat: heartbeat,
            pSessionId: sessionID,
            pDeviceId: deviceID,
            pOpenedSession: openedSession,
            pLastInputAt: lastInputAt.map { dateFormatter.string(from: $0) },
            pSeenAt: dateFormatter.string(from: now),
            pSince: dateFormatter.string(from: weekStart(for: now)),
            pIncludeMeta: includeMeta
        )
    }

    /// `work_tick(...)` — 근무 중 30초마다 따로 나가던 하트비트 2 + 팀 상태 GET 4 + away_sync(+ 팀 메타 2)를
    /// **한 번의 POST** 로 보낸다. 전송만 합치고 의미는 바꾸지 않는다: 요청 값은 기존 요청이 싣던 값 그대로
    /// (`WorkTickRequest` 주석), 응답 조각은 기존 디코더로 읽는다(`WorkTickResponse`).
    ///
    /// **공용 `send` 를 쓰지 않고 직접 보내는 이유**: 폴백 규칙이 상태코드·PostgREST 코드로 갈리는데
    /// (404/PGRST202 → 끔, 403/42501 → 끔, 5xx → 연속 3회면 1시간), 공용 매핑은 403 을 `.authMessage(영문)` 로
    /// 접어 상태코드를 잃는다. 헤더 구성은 `send` 와 같다(apikey / Bearer / Accept / Content-Type).
    /// 401 만은 `.sessionExpired` 로 던져 `withSessionRetry` 의 토큰 갱신·재시도를 그대로 탄다.
    /// 인코더의 convertToSnakeCase 가 `pTeamId → p_team_id` 를 만든다(다른 RPC 본문과 같은 규약).
    package func workTick(accessToken: String, request: WorkTickRequest) async throws -> WorkTickResponse {
        guard let anonKey else {
            throw SupabaseWorkServiceError.missingAnonKey
        }
        var urlRequest = URLRequest(url: try url(path: Self.workTickPath, queryItems: []))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(request)

        // URLError(네트워크·취소)는 그대로 전파한다 — 스토어가 취소를 실패로 세지 않게 가르려면 원형이 필요하다.
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw WorkTickFailure.rejected(status: -1, code: nil)
        }
        let code = postgrestErrorCode(in: data)
        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw SupabaseWorkServiceError.sessionExpired
        case 404:
            throw WorkTickFailure.functionMissing(code: code)
        case 403:
            throw WorkTickFailure.forbidden(code: code)
        case 500...:
            throw WorkTickFailure.serverError(status: http.statusCode)
        default:
            // 코드가 상태보다 정확한 경우(프록시가 상태를 바꿔 준 300/406 등)도 같은 문으로 접는다.
            if code == "PGRST202" { throw WorkTickFailure.functionMissing(code: code) }
            if code == "42501" { throw WorkTickFailure.forbidden(code: code) }
            throw WorkTickFailure.rejected(status: http.statusCode, code: code)
        }
        guard let decoded = try? decoder.decode(WorkTickResponse.self, from: data) else {
            throw WorkTickFailure.undecodable
        }
        guard decoded.v == 1 else {
            throw WorkTickFailure.contractMismatch(version: decoded.v)
        }
        return decoded
    }

    /// 자동 마감한 세션을 되돌린다. ended_at/duration_seconds 를 null 로 재개하고 상태를 working 으로 복구.
    /// 유니크 인덱스(work_sessions_one_open_per_user)상 다른 열린 세션이 없을 때만 안전하다.
    /// auto_closed_at/auto_closed_reason 도 함께 null 로 되돌린다 — 남기면 **열린** 세션이 'abandoned'
    /// 사유를 단 채 살아나, 이후의 마감 사유 판정이 죽은 마감의 잔재를 읽는다.
    package func reopenSession(accessToken: String, teamID: String, userID: String, sessionID: String) async throws {
        func patch(resetAutoClose: Bool) async throws {
            try await sendNoBody(
                path: "/rest/v1/work_sessions",
                method: "PATCH",
                queryItems: [
                    URLQueryItem(name: "team_id", value: "eq.\(teamID)"),
                    URLQueryItem(name: "id", value: "eq.\(sessionID)")
                ],
                body: ReopenSessionRequest(resetAutoClose: resetAutoClose),
                accessToken: accessToken,
                prefer: "return=minimal"
            )
        }
        // 사유 컬럼이 없는 서버에서 되돌리기 자체가 죽지 않게 한 겹 막는다(stopWork 와 같은 결).
        // 실서버는 20260809140000 부터 컬럼이 있어 정상 경로는 항상 전자다.
        try await withoutNewColumns(
            { try await patch(resetAutoClose: true) },
            retry: { try await patch(resetAutoClose: false) }
        )
        try await upsertStatus(accessToken: accessToken, teamID: teamID, userID: userID, status: "working", activeSessionID: sessionID)
    }

    /// 코드로 팀 합류. join_team(code) RPC 를 로그인 토큰으로 호출한다. 불일치/비로그인은 0행 → nil.
    package func joinTeam(accessToken: String, code: String) async throws -> (teamID: String, name: String, goalHours: Int)? {
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
    package func createTeam(accessToken: String, name: String, goalHours: Int) async throws -> (teamID: String, name: String, inviteCode: String, goalHours: Int) {
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
    ///
    /// account/accountStatus(v0.2.41): Codex 계정 집계 스냅샷과 마지막 프로브 상태. 둘 다 nil 이면 codex_account_* 키가
    /// 본문에서 통째로 빠져 서버의 마지막 계정값이 보존된다(진단 필드와 같은 옵셔널 규약). 스냅샷 없이 상태만 있으면
    /// status 만 실린다. codex_cache_read 는 **항상** 실린다(로컬 집계라 매번 최신값으로 덮는 것이 맞다).
    ///
    /// antigravity_*(v0.3.12): 이 기기의 그 달 안티그래비티 네 값. 합이 0 이면 네 키가 통째로 빠진다
    /// (TokenUsageAntigravityFields.init?(usage:)). `total` 에는 더하지 않는다 — 그 컬럼은 옛 표와 같은 단위끼리
    /// 견주는 자리이고, 순위판 총합은 서버가 네 컬럼에서 직접 더한다(20260911120000).
    package func upsertTokenUsage(
        accessToken: String,
        userID: String,
        usage: TokenUsageMonthly,
        deviceID: String,
        account: CodexAccountUsage? = nil,
        accountStatus: CodexAccountProbeStatus? = nil,
        diagnostics: CodexUsageDiagnostics? = nil
    ) async throws {
        // v0.2.43(코드 리뷰 P1): 미로그인(3)이면 스냅샷 네 값을 **싣지 않는다**. 스토어는 로그아웃·API 키 전환 뒤에도 마지막 스냅샷을
        // 계속 들고 있는데(CheckCodexAccountUsage 는 status 만 바꾼다), 그것을 status 3 과 함께 실으면 서버가 "스냅샷 있는 미로그인 기기"
        // 라는 어긋난 상태를 본다(구 산식은 그 기기의 반영일 로컬을 계정 위에 얹어 최대 2배 이중 계상). 키를 빼면 서버의 마지막 계정값은
        // 보존되고, 산식 쪽은 서버 가드(스냅샷 없는 status 3 만 계정 밖)가 막는다 — 클라 생략은 그 가드의 짝이지 대체가 아니다.
        let snapshot: CodexAccountUsage? = (accountStatus == .notLoggedIn) ? nil : account
        let accountFields: TokenUsageAccountFields? = (account == nil && accountStatus == nil) ? nil : TokenUsageAccountFields(
            month: snapshot.map { $0.monthTotal(usage.month) },
            lifetime: snapshot?.lifetimeTokens,
            fetchedAt: snapshot.map { dateFormatter.string(from: $0.fetchedAt) },
            lastDay: snapshot?.latestBucketDate(in: usage.month),
            status: accountStatus?.rawValue
        )
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
                codexCacheRead: usage.codexCacheRead,
                account: accountFields,
                // v0.3.12: 합이 0 이면 nil → 본문에서 antigravity_* 네 키가 통째로 빠진다(안 쓰는 사람의 본문은 종전과 동일).
                // 요청은 **늘리지 않는다** — 같은 upsert 한 번에 얹는다(컬럼이 없는 서버면 400 이고, 호출측이 조용히 삼켜 다음 기회에 재시도한다).
                antigravity: TokenUsageAntigravityFields(usage: usage),
                diagnostics: diagnostics
            ),
            accessToken: accessToken,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    /// 스캐너 하트비트. **토큰 값과 무관하게** "스캔이 돌았고 파일을 N개 봤다"만 남긴다.
    /// 필요한 이유: 사용량 업로드는 합계가 0 이면 아예 나가지 않아, 서버에서 "Claude/Codex 를 안 쓴 사람"과
    /// "스캐너가 죽은 사람"이 똑같이 '행 없음'으로 보였다(2026-09-02 에 이 구분이 안 돼 원인 판별이 길어졌다).
    /// 이 요청은 총합과 무관하게 나가므로 last_scan_at 의 유무·신선도가 그 둘을 가른다.
    ///
    /// ★ 본문은 user_id·month·device_id·last_scan_at·scan_files **다섯 개뿐**이다. 토큰 컬럼을 절대 싣지 마라 —
    /// PostgREST 의 upsert 는 본문에 온 컬럼만 SET 하고 본문에 없는 컬럼은 건드리지 않는데
    /// (이 저장소가 created_at 을 보존하는 데 이미 기대는 성질, 20260726010000_token_usage_device.sql:57),
    /// 하트비트는 합계 0 일 때도 나가므로 토큰 컬럼을 0 으로 실으면 **그 기기의 이번 달 누적치를 통째로 0 으로 민다.**
    /// 요청 타입을 TokenUsageUpsertRequest 가 아닌 전용 TokenScanHeartbeatRequest 로 둔 것도 같은 이유다 —
    /// 그 타입은 토큰 컬럼을 갖고 있어 재사용하는 순간 이 위험이 그대로 따라 들어온다.
    /// 나머지(경로·on_conflict·Prefer)는 upsertTokenUsage 와 같은 관용구다 — 행이 없으면 insert 되고,
    /// 있으면 이 두 컬럼만 갱신된다. 시각 포맷도 다른 timestamptz 요청과 같은 dateFormatter(ISO8601)를 쓴다.
    package func sendTokenScanHeartbeat(
        accessToken: String,
        userID: String,
        month: String,
        deviceID: String,
        files: Int,
        scannedAt: Date
    ) async throws {
        try await sendNoBody(
            path: "/rest/v1/token_usage_device_monthly",
            method: "POST",
            queryItems: [URLQueryItem(name: "on_conflict", value: "user_id,month,device_id")],
            body: TokenScanHeartbeatRequest(
                userId: userID,
                month: month,
                deviceId: deviceID,
                lastScanAt: dateFormatter.string(from: scannedAt),
                scanFiles: files
            ),
            accessToken: accessToken,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    /// 일별 표(token_usage_device_daily)에 **배열 본문**으로 upsert 한다(v0.2.41 토큰 잔디). 충돌키 (user_id, day, device_id),
    /// Prefer 는 월 표와 같은 관용구(merge-duplicates + return=minimal — 수집 거부자의 0행도 성공으로 본다).
    /// 호출측(WorkTimerStoreSync.uploadTokenUsageDailyIfNeeded)이 **바뀐 날만** 골라 넘기므로 행 수는 보통 한두 개다.
    /// 빈 배열이면 요청을 **아예 보내지 않는다** — PostgREST 는 빈 배열 upsert 에도 200 을 돌려주지만 30초마다 헛왕복이 될 뿐이다.
    /// 행에 user_id/device_id 가 이미 실려 있어 따로 받지 않는다(같은 값을 두 경로로 받으면 어긋날 자리가 생긴다).
    ///
    /// ★ **키 집합이 같은 행끼리만 한 요청에 담는다**(v0.2.41 리뷰 P0). PostgREST 는 배열 본문의 키 집합이 행마다 다르면
    ///   스키마를 보기도 **전에** 400 PGRST102("All object keys must match")로 **본문 전체**를 거절한다(프로덕션 14.5 실측).
    ///   그런데 codex_account 는 계정 버킷이 없는 날엔 키가 통째로 빠지는 것이 요건이라(TokenUsageDailyUpsertRow 주석 —
    ///   0 을 실으면 다른 기기가 올린 계정값을 밀어 버린다), Codex 를 쓰는 사람의 한 달치에는 '있는 날'과 '없는 날'이 **반드시**
    ///   섞인다. 그 배열을 통째로 보내면 그 사람의 일별 행이 서버에 **단 한 줄도** 올라가지 않고(400 은 조용히 삼켜진다),
    ///   장부도 갱신되지 않아 다음 주기가 같은 혼합 본문을 다시 보내는 영구 고착이 된다.
    ///   그래서 `?columns=` 로 키를 강제하는 대신(그러면 빠진 키가 **null 로 쓰여** 계정값이 지워진다) 키 모양별 묶음으로 갈라
    ///   각각 보낸다. v0.2.43 부터 옵셔널이 넷이다(claude_total · codex_total · codex_utc_total · codex_account — 각 로컬 맵이 덮는
    ///   날에만 값이 있다, TokenUsageDailyUpsertRow 주석) — 묶음은 **정확히 같은 키 집합**끼리, 빈 묶음은 없다.
    ///   v0.3.12 부터 다섯이다(+ antigravity_total) — 최대 32 모양, 실제로는 서너 개.
    ///   첫 묶음이 실패하면 그대로 던져 장부가 갱신되지 않는다(upsert 는 멱등이라 다음 주기가 전부 다시 보내도 안전하다).
    package func upsertTokenUsageDaily(accessToken: String, rows: [TokenUsageDailyUpsertRow]) async throws {
        guard !rows.isEmpty else { return }
        // 묶음 키 = 옵셔널 **다섯**의 유무 비트(claude·codex·utc·account·antigravity 순, v0.3.12). 순서는 결정적으로 둔다 —
        // 키가 많은 묶음부터(비트 내림차순), 계약 테스트·로그가 요청 순서를 읽을 수 있어야 한다.
        // ★ 새 옵셔널을 더할 때마다 **반드시 여기에 비트를 더해라.** 빠뜨리면 키 집합이 다른 행이 한 요청에 섞여
        //   PostgREST 가 본문 **전체**를 400 PGRST102 로 거절하고(스키마를 보기도 전에), 그 사람의 일별 행이 한 줄도
        //   안 올라간 채 장부가 갱신되지 않아 같은 본문을 영원히 다시 보낸다(v0.2.41 리뷰 P0 의 재현).
        func shape(_ r: TokenUsageDailyUpsertRow) -> Int {
            (r.claudeTotal != nil ? 16 : 0) + (r.codexTotal != nil ? 8 : 0) + (r.codexUtcTotal != nil ? 4 : 0)
                + (r.codexAccount != nil ? 2 : 0) + (r.antigravityTotal != nil ? 1 : 0)
        }
        let grouped = Dictionary(grouping: rows, by: shape)
        let groups = grouped.keys.sorted(by: >).map { grouped[$0] ?? [] }
        for group in groups where !group.isEmpty {
            try await sendNoBody(
                path: "/rest/v1/token_usage_device_daily",
                method: "POST",
                queryItems: [URLQueryItem(name: "on_conflict", value: "user_id,day,device_id")],
                body: group,
                accessToken: accessToken,
                prefer: "resolution=merge-duplicates,return=minimal"
            )
        }
    }

    /// 옛 표 token_usage_monthly 의 내 이번 달 행 총량을 읽는다(없으면 nil). select=total 한 줄만 읽는다.
    /// 쓰임: 옛 표를 덮어쓰기 **전** 게이트. 그 행이 아직 v0.2.10 인 다른 맥의 더 큰 누적치일 수 있어,
    /// 그때 내 값으로 덮으면 그 맥의 사용량이 순위에서 사라진다(upsertLegacyTokenUsage 주석 참조).
    /// 본인 행 select 는 RLS 정책으로 열려 있다(20260723010000 — upsert 충돌 읽기용으로 이미 필요했다).
    package func fetchLegacyTokenUsageTotal(accessToken: String, userID: String, month: String) async throws -> Int? {
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
    package func upsertLegacyTokenUsage(accessToken: String, userID: String, usage: TokenUsageMonthly) async throws {
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

    /// 대상에게 콕 찌르기. poke_user(p_to) RPC 를 로그인 토큰으로 호출한다. 근무중 게이트·60초 쿨타임은 서버가 강제한다.
    /// 반환은 jsonb 단일 객체(배열 아님)라 PokeSendResponse 로 직접 디코드한다({status, retry_after_seconds?}).
    package func sendPoke(accessToken: String, to userID: String) async throws -> PokeSendResponse {
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
    package func sendUltraPoke(accessToken: String, to userID: String) async throws -> PokeSendResponse {
        let data = try await send(
            path: "/rest/v1/rpc/ultra_poke_user",
            method: "POST",
            body: PokeSendRequest(pTo: userID),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(PokeSendResponse.self, from: data)
    }

    /// 울트라 찌르기를 산다(루비 → 울트라). `buy_ultra(p_count)` RPC.
    package func buyUltra(accessToken: String, count: Int) async throws -> BuyUltraResponse {
        let data = try await send(
            path: "/rest/v1/rpc/buy_ultra",
            method: "POST",
            body: BuyUltraRequest(pCount: count),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(BuyUltraResponse.self, from: data)
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
    package func takePokes(accessToken: String) async throws -> [TakenPokeRow] {
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
    package func syncUltraWallet(accessToken: String, daysBack: Int = 1) async throws -> UltraWalletResponse {
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

    /// 집중 모드(콕찌르기 수신 거부) 갱신. profiles 자기 행을 PATCH 한다 —
    /// 컬럼 단위 UPDATE 권한(20260812090000)이 있어야 통과한다.
    package func updateFocusMode(accessToken: String, userID: String, enabled: Bool) async throws {
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
    package func updateAppVersion(accessToken: String, userID: String, report: AppVersionReport) async throws {
        try await sendNoBody(
            path: "/rest/v1/profiles",
            method: "PATCH",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(userID)")],
            body: ProfileAppVersionUpdateRequest(appBuild: report.build, appVersion: report.version),
            accessToken: accessToken,
            prefer: "return=minimal"
        )
    }

    /// lastInputAt 은 **하트비트 경로만** 싣는다(같은 요청에 얹으므로 쓰기 비용 증가는 0이다).
    /// nil 이면 Swift 합성 Encodable 이 키를 생략하고 PostgREST merge-duplicates 는 본문에 없는 컬럼을
    /// 건드리지 않는다 — 그래서 start/stop/reopen 경로의 바이트는 이 변경 전과 **한 글자도 다르지 않다**.
    private func upsertStatus(
        accessToken: String,
        teamID: String,
        userID: String,
        status: String,
        activeSessionID: String?,
        lastInputAt: Date? = nil
    ) async throws {
        func post(includeInput: Bool) async throws {
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
                    updatedAt: dateFormatter.string(from: Date()),
                    lastInputAt: includeInput ? lastInputAt.map { dateFormatter.string(from: $0) } : nil
                ),
                accessToken: accessToken,
                prefer: "resolution=merge-duplicates,return=minimal"
            )
        }
        guard lastInputAt != nil else {
            try await post(includeInput: false)
            return
        }
        // ★ 새 컬럼이 없는 서버로 떨어지면 **하트비트 자체가 실패한다** — 그러면 10분 뒤 서버 스캐빈저가
        //   살아 있는 세션을 방치로 마감한다(브루 배포가 db push 보다 먼저 나가는 창은 실재한다).
        //   스토어가 away_sync 응답으로 이 컬럼의 존재를 이미 확인하고 부르지만, 그 게이트가 한 번이라도
        //   새면 사고의 크기가 "타이머 유실"이라 여기서 한 겹 더 막는다.
        try await withoutNewColumns({ try await post(includeInput: true) }, retry: { try await post(includeInput: false) })
    }

    /// 새 컬럼(last_input_at / auto_closed_*)을 모르는 서버에서 요청이 통째로 죽지 않게 하는 1회 재시도.
    /// PostgREST 는 없는 컬럼을 PGRST204("... in the schema cache")로 돌려주고 공용 매핑이 그것을
    /// `.databaseSchemaMissing` 으로 접는다. 400 도 함께 받는 이유는 사유 어휘 제약 위반(23514)처럼
    /// **새로 더한 컬럼 때문에만** 생길 수 있는 거절을 같은 문으로 흡수하기 위해서다.
    private func withoutNewColumns(
        _ attempt: () async throws -> Void,
        retry: () async throws -> Void
    ) async throws {
        do {
            try await attempt()
        } catch SupabaseWorkServiceError.databaseSchemaMissing {
            try await retry()
        } catch SupabaseWorkServiceError.invalidResponse(400) {
            try await retry()
        }
    }
}

/// profiles.app_build / app_version 자기 행 갱신 요청(PATCH).
/// **두 컬럼을 한 요청에 싣는다** — 집중 모드를 따로 보낸 이유(권한이 한쪽에만 있는 서버)가 여기엔 없다:
/// 두 컬럼은 같은 마이그레이션이 함께 만들고 함께 grant 하므로 한쪽만 쓸 수 있는 서버가 존재하지 않는다.
/// 나누면 같은 사실을 알리는 데 왕복이 두 배가 될 뿐이다(무료 플랜).
package struct ProfileAppVersionUpdateRequest: Encodable {
    package let appBuild: Int
    package let appVersion: String
}

// MARK: - work_tick 가용성 게이트 (v0.2.38 S3 / docs/work-tick.md 4.1·4.5)

/// `work_tick` 을 **이 실행 동안** 쓸 수 있는가와, 왜 못 쓰는가. 컴파일 상수 킬스위치(`WorkTimerStore.workTickEnabled`)
/// 뒤의 실행 단위 스위치다. 규칙은 계약 문서 4.5 그대로다:
///  · 404/PGRST202(함수 없음·모르는 키) · 403/42501(실행권 회수) · `v != 1` · 디코드 실패 → **이 실행 동안 끈다**
///  · 5xx·그 밖의 실패 → 연속 3회면 **1시간** 폴백 후 재시도(지속 오류 시 "실패 1 + 폴백 7" 폭주의 상한)
/// 어느 쪽이든 그 틱은 호출부가 기존 경로로 즉시 재수행한다 — 하트비트 유실 창을 만들지 않는 것이 규칙의 전부다.
///
/// 폴백 사유는 `syncMessage` 가 아니라 여기(진단 문자열)에 남긴다. 사용자에게 "동기화 실패" 를 보일 상황이 아니라
/// 이득만 사라진 상태이기 때문이다. NSLock 으로 보호하는 `@unchecked Sendable` — 액터 밖(메인 액터)에서 동기로 읽는다.
package final class WorkTickGate: @unchecked Sendable {
    /// 연속 일시 실패 상한. 도달하면 `suspensionSeconds` 동안 폴백.
    package static let transientFailureLimit = 3
    package static let suspensionSeconds: TimeInterval = 60 * 60

    private let lock = NSLock()
    private var disabledReason: String?
    private var disabledAt: Date?
    private var consecutiveTransientFailures = 0
    private var suspendedUntil: Date?
    private var lastTransientReason: String?
    private var successCount = 0
    private var fallbackCount = 0
    /// server_now − 로컬 시계(초). 양수면 서버가 앞선다. 판정에는 쓰지 않는다(계측 전용).
    private var lastClockSkewSeconds: TimeInterval?

    /// 지금 work_tick 을 시도해도 되는가. 1시간 정지는 `now` 가 지나면 스스로 풀린다(카운터도 새로 센다).
    package func isAvailable(now: Date) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if disabledReason != nil { return false }
        if let until = suspendedUntil {
            if now < until { return false }
            suspendedUntil = nil
            consecutiveTransientFailures = 0
        }
        return true
    }

    /// 이 실행 동안 끈다(함수 없음·실행권 회수·계약 불일치·디코드 실패).
    package func disable(reason: String, at now: Date) {
        lock.lock(); defer { lock.unlock() }
        guard disabledReason == nil else { return }
        disabledReason = reason
        disabledAt = now
    }

    /// 일시 실패 1회(5xx·네트워크·그 밖의 4xx). 연속 3회면 1시간 정지.
    package func recordTransientFailure(reason: String, at now: Date) {
        lock.lock(); defer { lock.unlock() }
        lastTransientReason = reason
        consecutiveTransientFailures += 1
        if consecutiveTransientFailures >= Self.transientFailureLimit {
            suspendedUntil = now.addingTimeInterval(Self.suspensionSeconds)
        }
    }

    /// 성공 1회. 연속 실패 장부를 지우고 시계 차를 계측한다.
    package func recordSuccess(serverNow: Date?, localNow: Date) {
        lock.lock(); defer { lock.unlock() }
        successCount += 1
        consecutiveTransientFailures = 0
        lastTransientReason = nil
        if let serverNow { lastClockSkewSeconds = serverNow.timeIntervalSince(localNow) }
    }

    /// 폴백 경로로 수행한 틱 1회(진단 카운터).
    package func recordFallback() {
        lock.lock(); defer { lock.unlock() }
        fallbackCount += 1
    }

    /// 상태 스냅샷(테스트·진단용).
    package var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(
            disabledReason: disabledReason,
            disabledAt: disabledAt,
            consecutiveTransientFailures: consecutiveTransientFailures,
            suspendedUntil: suspendedUntil,
            lastTransientReason: lastTransientReason,
            successCount: successCount,
            fallbackCount: fallbackCount,
            lastClockSkewSeconds: lastClockSkewSeconds
        )
    }

    package struct Snapshot: Equatable, Sendable {
        package let disabledReason: String?
        package let disabledAt: Date?
        package let consecutiveTransientFailures: Int
        package let suspendedUntil: Date?
        package let lastTransientReason: String?
        package let successCount: Int
        package let fallbackCount: Int
        package let lastClockSkewSeconds: TimeInterval?
    }

    /// 설정 창용 한 줄(값 사이 구분자는 ` · ` — realtimeDiagnosticsLine 과 같은 규약).
    package func diagnosticsLine(now: Date) -> String {
        let s = snapshot
        var parts: [String] = []
        if let reason = s.disabledReason {
            parts.append("폴백 고정(\(reason))")
            if let at = s.disabledAt { parts.append("\(CheckCoreShared.realtimeDiagnosticsTime.string(from: at)) 부터") }
        } else if let until = s.suspendedUntil, now < until {
            parts.append("1시간 폴백(\(s.lastTransientReason ?? "연속 실패"))")
            parts.append("\(CheckCoreShared.realtimeDiagnosticsTime.string(from: until)) 까지")
        } else {
            parts.append("work_tick 사용")
            if s.consecutiveTransientFailures > 0, let reason = s.lastTransientReason {
                parts.append("연속 실패 \(s.consecutiveTransientFailures)회(\(reason))")
            }
        }
        parts.append("성공 \(s.successCount)회")
        parts.append("폴백 \(s.fallbackCount)회")
        if let skew = s.lastClockSkewSeconds {
            parts.append(String(format: "시계차 %+.1fs", skew))
        }
        return parts.joined(separator: " · ")
    }
}
#endif
