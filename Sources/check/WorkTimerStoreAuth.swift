import Foundation

@MainActor
extension WorkTimerStore {
    /// 실행 직후 저장 세션을 활성화해야 하는지(D1). 키가 없으면(canSync == false) **킥하지 않는다** —
    /// missingAnonKey 는 classifyAuthError 에서 `.fatal` 이라 refreshPersistedSessionIfPossible 이 저장 세션을
    /// 조용히 지운다(아래 clearPersistedSession 분기). 지금까진 팝오버를 직접 연 사람만 그 경로를 밟았지만
    /// 킥은 화면 없이 도므로, 키 없이 `swift run` 한 개발 맥에서 실계정 세션이 아무 화면도 안 보인 채 날아간다.
    var shouldActivateOnLaunch: Bool { isSignedIn && canSync && !hasActivatedStoredSession }

    /// 실행당 1회 저장 세션 활성화를 발사하고 그 Task 를 돌려준다(테스트가 완료를 기다릴 수 있게).
    /// 조건 미달이면 아무것도 하지 않고 nil — 비로그인/키 없음 실행에서 요청이 0건이어야 하는 계약이다.
    @discardableResult
    func activateStoredSessionOnLaunch() -> Task<Void, Never>? {
        guard shouldActivateOnLaunch else { return nil }
        let task = Task { @MainActor [weak self] in
            await self?.performActivateStoredSession()
            self?.launchActivationTask = nil
        }
        launchActivationTask = task
        return task
    }

    /// 팝오버 오픈(.task) 진입점. 실행 킥이 아직 돌고 있으면 **그 완료를 먼저 기다린다** — 기다리지 않으면
    /// 킥의 refresh grant 가 in-flight 인 사이에 fast path 의 confirmMembership 이 회전 전 access token 으로
    /// 나갔다가 401 → 같은 낡은 refresh token 으로 두 번째 grant 를 치게 된다(launchActivationTask 주석 참조).
    func activateStoredSession() async {
        if let launchActivationTask { await launchActivationTask.value }
        await performActivateStoredSession()
    }

    private func performActivateStoredSession() async {
        guard session != nil else {
            return
        }
        // 실행당 1회만 전체 활성화(토큰 회전 + 멤버십 확정)한다. 이후 팝오버 여닫이에선 refresh 만 돌려
        // refresh token 회전(+reuse-detection 리스크)을 없앤다. access token 만료는 401 재시도 경로가 담당한다.
        if hasActivatedStoredSession {
            // 첫 활성화가 오프라인/취소로 멤버십 확정에 실패했으면(membershipConfirmed==false) 재오픈 때 재확정한다 —
            // hasActivatedStoredSession 조기 래치로 확정 경로가 영구 소멸하던 결함을 막는다. 토큰 회전은 여전히 1회다.
            if !membershipConfirmed { await confirmMembership() }
            await refreshTeamStatus()
            return
        }
        hasActivatedStoredSession = true
        let generation = sessionGeneration
        await refreshPersistedSessionIfPossible()
        guard generation == sessionGeneration else { return }
        await confirmMembership()
        guard generation == sessionGeneration else { return }
        await refreshTeamStatus()
        guard generation == sessionGeneration else { return }
        startStatusRefreshLoop()
    }

    func signIn(email: String, password: String) async {
        syncMessage = "로그인 중"
        let generation = sessionGeneration
        do {
            let signedInSession = try await service.signIn(email: email, password: password)
            guard generation == sessionGeneration else { return }
            await completeSignIn(signedInSession, email: email)
        } catch {
            guard generation == sessionGeneration else { return }
            syncMessage = authMessage(for: error, fallback: "로그인 실패")
        }
    }

    /// 세션을 손에 넣은 직후의 **공통 마무리**. 비밀번호/OTP 등 세션을 얻는 경로가 늘어나도 로그인 이후의
    /// 일은 반드시 여기 한 곳을 지나게 한다 — 복제하면 언젠가 갈리고, 갈린 쪽은 "로그인은 됐는데 팀이 없다 /
    /// 하트비트가 안 돈다 / 회고가 안 뜬다"처럼 **화면상 정상으로 보이는** 결함으로만 드러난다.
    func completeSignIn(_ signedInSession: SupabaseSession, email: String) async {
        let generation = sessionGeneration
        session = signedInSession
        persistSession(signedInSession, email: email)
        // 강제 로그아웃이 남겨 둔 미반영 근무 큐/진행 중 근무의 주인을 확정한다(같은 계정이면 재생, 다른 계정이면 폐기).
        adoptWorkStateOwner(signedInSession.userID)
        self.password = ""
        await confirmMembership()
        guard generation == sessionGeneration else { return }
        syncMessage = "동기화됨"
        await refreshTeamStatus()
        guard generation == sessionGeneration else { return }
        startStatusRefreshLoop()
        // 개인 기록(히트맵/회고)을 로그인 직후에 받아 온다. 자동 로드의 유일한 진입점이 팝오버 오픈 훅
        // (setMenuPresented → needsInsightsReload)뿐이면, **팝오버를 연 채 로그인하는 정상 동선**에서는
        // 그 훅이 이미 비로그인 시점에 지나가 버려(performLoadInsights 의 session 가드에서 즉시 반환)
        // insights 가 그 팝오버 세션 내내 비어 있다. 리그/토큰보드/찌르기는 사용자가 직접 여는 패널이라
        // 무관하지만, 지난주 회고 배너는 사용자가 열 수 없는 '자동 안내'라 이 경로가 없으면 팝오버를
        // 닫았다 다시 열기 전까지 영영 뜨지 않는다(회귀 지점).
        if needsInsightsReload { await performLoadInsights() }
    }

    func signUp(email: String, password: String, displayName: String) async {
        syncMessage = "계정 생성 중"
        let generation = sessionGeneration
        do {
            if let createdSession = try await service.signUp(email: email, password: password, displayName: displayName) {
                guard generation == sessionGeneration else { return }
                session = createdSession
                persistSession(createdSession, email: email, displayName: displayName)
                // 새 계정이므로 앞 계정이 남긴 큐/진행 중 근무는 여기서 버려진다(오염 금지).
                adoptWorkStateOwner(createdSession.userID)
                self.password = ""
                // 트리거는 더 이상 팀을 만들지 않으므로, 모드에 따라 팀을 만들거나(join 은 하지 않고) 코드로 합류한다.
                if isCreateTeamMode {
                    await createTeamAfterSignup()
                } else {
                    await joinTeamAfterSignup()
                }
                guard generation == sessionGeneration else { return }
                syncMessage = "동기화됨"
                await refreshTeamStatus()
                guard generation == sessionGeneration else { return }
                startStatusRefreshLoop()
            } else {
                guard generation == sessionGeneration else { return }
                self.password = ""
                syncMessage = "확인 메일 필요"
            }
        } catch {
            guard generation == sessionGeneration else { return }
            syncMessage = authMessage(for: error, fallback: "계정 생성 실패")
        }
    }

    /// 코드 모드 가입 성공 후. signupTeamCode 로 join_team 을 실행하고 confirmMembership 으로 팀을 확정한다.
    private func joinTeamAfterSignup() async {
        let generation = sessionGeneration
        let code = signupTeamCode
        do {
            _ = try await withSessionRetry { activeSession in
                try await service.joinTeam(accessToken: activeSession.accessToken, code: code)
            }
            guard generation == sessionGeneration else { return }
        } catch {
            // 합류 실패는 조용히 넘기고 confirmMembership 이 무소속으로 확정하게 둔다(문구는 이후 refresh 가 정리).
            guard generation == sessionGeneration else { return }
        }
        // 가입 직후 확정은 트리거 지연이 없더라도(직접 upsert) 안전하게 재시도 경로를 재사용한다.
        await confirmMembership(allowRetryForFreshSignup: true)
    }

    /// 만들기 모드 가입 성공 후. create_team 으로 팀을 만들고 참여코드를 안내용으로 보관한 뒤 팀을 확정한다.
    private func createTeamAfterSignup() async {
        let generation = sessionGeneration
        let name = createTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
        let goal = createTeamGoalHours
        do {
            let created = try await withSessionRetry { activeSession in
                try await service.createTeam(accessToken: activeSession.accessToken, name: name, goalHours: goal)
            }
            guard generation == sessionGeneration else { return }
            createdTeamCode = created.inviteCode
        } catch {
            guard generation == sessionGeneration else { return }
            syncMessage = authMessage(for: error, fallback: "팀 생성 실패")
        }
        await confirmMembership(allowRetryForFreshSignup: true)
    }

    /// 로그인/세션복구/가입 성공 후 내 팀을 확정한다. 소속이 있으면 currentTeamID/teamName/teamGoalSeconds 를
    /// 서버 값으로 채우고, 없으면 무소속(currentTeamID=nil, teamName="팀", 목표=기본값)으로 둔다.
    /// 가입 직후에는 트리거 타이밍 때문에 빈 값이면 1초 간격으로 3회까지 재시도한다.
    func confirmMembership(allowRetryForFreshSignup: Bool = false) async {
        guard session != nil else { return }
        let generation = sessionGeneration
        let attempts = allowRetryForFreshSignup ? 3 : 1
        for attempt in 0..<attempts {
            // fetch 발사 전 목표 write 세대를 캡처한다. 응답을 반영할 때 값이 바뀌었으면(그 사이 새 목표 write)
            // teamGoalSeconds 대입만 건너뛴다(팀명/역할/코드는 최신 서버값으로 반영).
            let goalWriteGen = teamGoalWriteGeneration
            let membership: (teamID: String, teamName: String, goalHours: Int, role: String)?
            do {
                membership = try await withSessionRetry { activeSession in
                    try await service.fetchOwnMembership(accessToken: activeSession.accessToken, userID: activeSession.userID)
                }
            } catch {
                // 취소/네트워크 오류를 포함한 모든 throw 는 무소속 확정으로 이어지지 않는다. 기존 팀 상태를
                // 유지한 채 조용히 빠져나간다('정상 응답 0행'일 때만 아래에서 무소속으로 확정한다).
                guard generation == sessionGeneration else { return }
                return
            }
            guard generation == sessionGeneration else { return }
            if let membership {
                // 소속 확인 성공 — 확정적 결과. throw(취소/네트워크)로는 여기 오지 않는다.
                membershipConfirmed = true
                currentTeamID = membership.teamID
                teamName = membership.teamName
                // 목표시간은 DB 값(시간) 그대로 초로 환산해 반영한다(캐시/일회성 없음). 단, fetch 발사 후 새 목표를
                // write 했으면(세대 변화) 이 응답은 낡은 값이므로 목표 대입만 건너뛴다(스냅백 방지).
                if teamGoalWriteGeneration == goalWriteGen {
                    teamGoalSeconds = membership.goalHours * 3600
                    // 이 응답이 인사이트 응답보다 늦게 왔다면 회고가 기본 목표로 굳어 있다 — 목표선만 바로잡는다.
                    reconcileInsightsGoal()
                }
                teamRole = membership.role
                // 참여코드는 소속 팀원 누구나 공유할 수 있게 항상 로드한다(코드가 곧 열쇠 — 팀원도 새 동료를 초대).
                await loadMyInviteCode()
                return
            }
            if attempt + 1 < attempts {
                try? await Task.sleep(for: .seconds(1))
                guard generation == sessionGeneration else { return }
            }
        }
        // 정상 응답 0행 — 무소속으로 확정한다(이 역시 확정적 결과다).
        membershipConfirmed = true
        currentTeamID = nil
        teamName = "팀"
        teamGoalSeconds = TeamWeeklyGoal.defaultGoalSeconds
        reconcileInsightsGoal()
        teamRole = nil
        myTeamInviteCode = nil
    }

    /// 소속 팀원이면 my_team_invite_code() RPC 로 참여코드를 로드한다. 실패/무소속이면 nil.
    private func loadMyInviteCode() async {
        let generation = sessionGeneration
        let code: String?
        do {
            code = try await withSessionRetry { activeSession in
                try await service.fetchMyInviteCode(accessToken: activeSession.accessToken)
            }
        } catch {
            // 일시 실패(취소/네트워크)는 try? 로 nil 삼켜 코드 버튼을 깜빡 지우지 말고, 기존 myTeamInviteCode 를
            // 유지한다(대입 스킵). 정상 0행일 때만 아래에서 nil 로 확정한다.
            return
        }
        guard generation == sessionGeneration else { return }
        myTeamInviteCode = code
    }

    /// 팀 주간 목표시간을 바꾼다(팀원 누구나). 범위(1~168) 밖이거나 이미 변경 중이면 즉시 false 로 무시한다.
    /// 성공 시 목표를 서버 반영값으로 갱신하고 안내 문구를 남기며, 리그 페이지가 열려 있으면 새로고침한다.
    /// 취소(빠른 닫기)는 조용히 넘기고(문구 유지), 그 외 실패는 authMessage 로 알린다.
    /// 반환값(성공 여부)으로 뷰가 편집 행을 닫을지 결정한다(실패 시 값 유지·재시도 가능).
    @discardableResult
    func updateTeamGoal(hours: Int) async -> Bool {
        guard (1...168).contains(hours) else { return false }
        guard !isUpdatingTeamGoal else { return false }
        isUpdatingTeamGoal = true
        defer { isUpdatingTeamGoal = false }
        let generation = sessionGeneration
        do {
            let newGoalHours = try await withSessionRetry { activeSession in
                try await service.setTeamWeeklyGoal(accessToken: activeSession.accessToken, goalHours: hours)
            }
            guard generation == sessionGeneration else { return false }
            teamGoalSeconds = newGoalHours * 3600
            // 개인 기록 회고의 목표선도 새 목표를 따라간다(패널을 다시 열지 않아도 즉시 일치).
            reconcileInsightsGoal()
            // 이 write 이후 도착하는 낡은 멤버십 응답(in-flight refreshTeamMeta/confirmMembership)이 목표를
            // 되돌리지 못하게 세대를 올린다.
            teamGoalWriteGeneration += 1
            syncMessage = "주간 목표 변경됨"
            // 리그 페이지가 열려 있으면 바뀐 목표가 게이지/퍼센트에 즉시 반영되도록 새로고침한다(내부에서 노출 가드).
            await refreshLeaderboardIfVisible()
            return true
        } catch {
            guard generation == sessionGeneration else { return false }
            // 취소(.task 취소/빠른 닫기)는 헛경보 문구를 남기지 않고 조용히 넘긴다.
            if case .cancelled = classifyAuthError(error) { return false }
            syncMessage = authMessage(for: error, fallback: "목표 변경 실패")
            return false
        }
    }

    /// 팝오버를 열 때 60초 스로틀로 팀 메타(목표/이름/역할/참여코드)를 재조회한다. 팀원이 바꾼 목표가
    /// 내 팝오버에 최대 1분 안에 반영되게 한다. 스로틀 시각은 관찰 대상이 아니라 무효화를 유발하지 않는다.
    /// 로그인·소속 상태에서만 동작하고, 무소속 확정은 여기서 하지 않는다(refreshTeamStatus 담당).
    func refreshTeamMetaIfStale(now: Date = Date()) {
        guard session != nil, currentTeamID != nil else { return }
        guard now.timeIntervalSince(lastTeamMetaRefreshAt) >= Self.teamMetaRefreshThrottleSeconds else { return }
        lastTeamMetaRefreshAt = now
        Task { @MainActor in await refreshTeamMeta() }
    }

    /// 멤버십을 재조회해 팀 메타(목표/이름/역할)와 참여코드를 갱신한다. == 가드로 값이 실제로 바뀔 때만
    /// 대입해 폴링이 숨은 잎 뷰를 헛무효화하지 않게 한다. 취소/네트워크 오류는 조용히 넘긴다(다음 기회 재시도).
    func refreshTeamMeta() async {
        guard session != nil else { return }
        let generation = sessionGeneration
        // fetch 발사 전 목표 write 세대를 캡처한다(응답이 낡았는지 판정용).
        let goalWriteGen = teamGoalWriteGeneration
        let membership: (teamID: String, teamName: String, goalHours: Int, role: String)?
        do {
            membership = try await withSessionRetry { activeSession in
                try await service.fetchOwnMembership(accessToken: activeSession.accessToken, userID: activeSession.userID)
            }
        } catch {
            return
        }
        // 정상 0행(무소속 확정)은 여기서 처리하지 않는다 — 팀 메타 갱신만이 목적이라 기존 팀 상태를 유지한다.
        guard generation == sessionGeneration, let membership else { return }
        if currentTeamID != membership.teamID { currentTeamID = membership.teamID }
        if teamName != membership.teamName { teamName = membership.teamName }
        // fetch 발사 후 새 목표를 write 했으면(세대 변화) 이 응답은 낡은 목표라 대입을 건너뛴다(스냅백 방지).
        // 팀명/역할/코드는 최신 서버값으로 반영한다.
        if teamGoalWriteGeneration == goalWriteGen {
            let newGoal = membership.goalHours * 3600
            if teamGoalSeconds != newGoal { teamGoalSeconds = newGoal }
            reconcileInsightsGoal()
        }
        if teamRole != membership.role { teamRole = membership.role }
        await loadMyInviteCode()
    }

    /// previewTeamCode() 의 실제 작업. signupTeamCode 를 lookup_team_by_code 로 조회해 미리보기를 갱신한다.
    /// 세션이 아니라 previewGeneration 으로 마지막 요청만 반영한다(비로그인에서도 동작).
    func performPreviewTeamCode() async {
        let generation = previewGeneration
        let code = signupTeamCode
        let normalized = SupabaseWorkService.normalizeInviteCode(code)
        guard !normalized.isEmpty else {
            joinPreview = nil
            joinPreviewMessage = ""
            return
        }
        joinPreviewMessage = "확인 중"
        do {
            let preview = try await service.lookupTeamByCode(code: code)
            guard generation == previewGeneration else { return }
            if let preview {
                joinPreview = preview
                joinPreviewMessage = ""
            } else {
                joinPreview = nil
                joinPreviewMessage = "코드를 확인해 주세요"
            }
        } catch {
            guard generation == previewGeneration else { return }
            joinPreview = nil
            joinPreviewMessage = "코드를 확인해 주세요"
        }
    }

    /// joinTeamWithCode() 의 실제 작업. 로그인 상태에서 signupTeamCode 로 join_team 을 실행하고 팀을 확정한다.
    func performJoinTeamWithCode() async {
        guard session != nil else { return }
        let code = signupTeamCode
        let normalized = SupabaseWorkService.normalizeInviteCode(code)
        guard !normalized.isEmpty else {
            joinPreviewMessage = "팀 코드를 확인해 주세요"
            return
        }
        let generation = sessionGeneration
        do {
            let joined = try await withSessionRetry { activeSession in
                try await service.joinTeam(accessToken: activeSession.accessToken, code: code)
            }
            guard generation == sessionGeneration else { return }
            guard joined != nil else {
                joinPreviewMessage = "코드를 확인해 주세요"
                return
            }
            signupTeamCode = ""
            joinPreview = nil
            joinPreviewMessage = ""
            await confirmMembership()
            guard generation == sessionGeneration else { return }
            await refreshTeamStatus()
            guard generation == sessionGeneration else { return }
            startStatusRefreshLoop()
        } catch {
            guard generation == sessionGeneration else { return }
            syncMessage = authMessage(for: error, fallback: "합류 실패")
        }
    }

    /// 인증 경로 에러 처분. 취소는 아무 상태도 바꾸지 않고, 일시 네트워크 오류는 세션을 유지하며,
    /// 진짜 만료(SupabaseWorkServiceError 등)만 로그아웃 대상이다. .task 취소로 강제 로그아웃되는 회귀를 막는다.
    enum AuthErrorDisposition { case cancelled, transient, fatal }

    func classifyAuthError(_ error: Error) -> AuthErrorDisposition {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return .cancelled
        }
        if error is URLError {
            return .transient
        }
        // Supabase 무료플랜 일시정지(5xx)·레이트리밋(429)은 알려진 운영 이슈다. refresh grant 실패로 강제
        // 로그아웃하지 않고 세션을 유지한 채 다음 주기에 재시도한다. 400/401 계열(만료 등)은 fatal 로 남긴다.
        if case let SupabaseWorkServiceError.invalidResponse(code) = error, (500...599).contains(code) || code == 429 {
            return .transient
        }
        // 재설정 경로가 429 를 구조화해 던지는 형태(.rateLimited)도 같은 429 다 — 위 분기와 뜻이 갈리면
        // 같은 상황이 경로에 따라 세션 유지/강제 로그아웃으로 나뉜다.
        if case SupabaseWorkServiceError.rateLimited = error {
            return .transient
        }
        return .fatal
    }

    func authMessage(for error: Error, fallback: String) -> String {
        guard let serviceError = error as? SupabaseWorkServiceError else {
            return fallback
        }

        switch serviceError {
        case .missingAnonKey:
            return "Supabase 키 필요"
        case .invalidAPIKey:
            return "Supabase 키 오류"
        case .sessionExpired:
            return "다시 로그인 필요"
        case .invalidLoginCredentials:
            return "로그인 정보 오류"
        case .emailNotConfirmed:
            return "이메일 확인 필요"
        case .emailAlreadyRegistered:
            return "이미 가입된 이메일"
        case .signupDisabled:
            return "가입 비활성화됨"
        case .weakPassword:
            return "비밀번호 조건 확인"
        case .databaseSchemaMissing:
            return "DB 스키마 필요"
        case .sessionAlreadyOpen:
            return "이미 다른 곳에서 근무 중이에요"
        // 아래 셋은 비밀번호 재설정(OTP) 경로가 만들어 낸 분류다. 그 경로는 자체 매퍼
        // (passwordReset*FailureMessage)로 더 구체적인 문장을 쓰지만, 이 공용 매퍼도 **반드시** 한국어를
        // 돌려줘야 한다 — 여기 빠지면 다른 경로가 이 오류를 만났을 때 영문 원문이 메뉴바에 그대로 뜬다.
        case .rateLimited:
            return "잠시 후 다시 시도해주세요"
        case .otpInvalidOrExpired:
            return "코드가 맞지 않거나 만료됐어요"
        case .samePasswordReuse:
            return "이전과 다른 비밀번호로 정해주세요"
        case .authMessage(let message):
            return message
        case .invalidResponse:
            return fallback
        }
    }

    func withSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T {
        guard let currentSession = session else {
            throw SupabaseWorkServiceError.sessionExpired
        }
        let generation = sessionGeneration

        do {
            return try await operation(currentSession)
        } catch let originalError as SupabaseWorkServiceError where originalError == .sessionExpired {
            guard generation == sessionGeneration else { throw originalError }
            guard let refreshToken = currentSession.refreshToken else {
                clearPersistedSession()
                syncMessage = "다시 로그인 필요"
                throw originalError
            }

            let refreshedSession: SupabaseSession
            do {
                refreshedSession = try await service.refreshSession(refreshToken: refreshToken)
            } catch {
                guard generation == sessionGeneration else { throw originalError }
                // 취소/일시 네트워크 오류로 갱신이 실패했으면 세션을 유지한다(throw 는 유지 — 호출부가 재시도).
                // 진짜 만료(refresh token 무효 등)만 로그아웃한다.
                if classifyAuthError(error) == .fatal {
                    clearPersistedSession()
                    syncMessage = "다시 로그인 필요"
                }
                throw originalError
            }

            guard generation == sessionGeneration else { throw originalError }
            session = refreshedSession
            persistSession(refreshedSession)
            return try await operation(refreshedSession)
        }
    }

    func signOut() {
        sessionGeneration += 1

        if let accessToken = session?.accessToken {
            Task {
                await service.signOut(accessToken: accessToken)
            }
        }

        clearPersistedSession()
        startedAt = nil
        accumulatedSeconds = 0
        accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: Date())
        teamMembers = []
        currentTeamID = nil
        teamName = "팀"
        teamGoalSeconds = TeamWeeklyGoal.defaultGoalSeconds
        teamRole = nil
        teamDirectory = []
        selectedSignupTeamID = nil
        signupTeamCode = ""
        joinPreview = nil
        joinPreviewMessage = ""
        isCreateTeamMode = false
        createTeamName = ""
        createTeamGoalHours = 60
        createdTeamCode = nil
        myTeamInviteCode = nil
        currentSessionID = nil
        // 흡수 표식과 영속된 소유 세션 ID 도 함께 내린다. 로그아웃은 startedAt 을 실제로 지우므로(강제 로그아웃의
        // clearPersistedSession 과 달리 여기선 진행 중 근무를 남기지 않는다) 표식이 서술할 세션 자체가 사라진다.
        // 남겨 두면 다음 로그인 후 **내가 직접 시작한** 근무가 흡수로 오인돼 자동 마감·하트비트가 통째로 죽고,
        // 소유 ID 쪽은 이미 끝난 세션을 가리킨 채 다음 실행의 재시작 판정에 끼어든다.
        releaseSessionOwnership()
        pendingItems = []
        longSessionAnchor = nil
        clearLongSessionPrompt()
        sleepBeganAt = nil
        clearAutoCloseUndo()
        isEditingWeeklyGoal = false
        snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        tickerTask?.cancel()
        tickerTask = nil
        refreshMenuBarTitle()
        syncMessage = "로그인 필요"
    }

    private func refreshPersistedSessionIfPossible() async {
        guard let refreshToken = session?.refreshToken else {
            return
        }
        let generation = sessionGeneration

        do {
            let refreshedSession = try await service.refreshSession(refreshToken: refreshToken)
            guard generation == sessionGeneration else { return }
            session = refreshedSession
            persistSession(refreshedSession)
            syncMessage = "동기화됨"
        } catch {
            guard generation == sessionGeneration else { return }
            // .task 취소(팝오버 빨리 닫기)는 조용히, 일시 네트워크 오류는 세션 유지, 진짜 만료만 로그아웃한다.
            switch classifyAuthError(error) {
            case .cancelled:
                return
            case .transient:
                if syncMessage != "동기화 실패" { syncMessage = "동기화 실패" }
            case .fatal:
                clearPersistedSession()
                syncMessage = authMessage(for: error, fallback: "다시 로그인 필요")
            }
        }
    }
}

// MARK: - 비밀번호 재설정(메일 OTP)
//
// 흐름: [비밀번호를 잊었어요] → 이메일 입력 → 6자리 코드 메일 → **코드만** 입력 → **새 비밀번호만** 입력
//      → 로그인 화면 복귀(자동 로그인 없음).
// 브라우저도 딥링크도 타지 않는다(check:// 스킴을 등록한 앱이 없어 메일 링크가 빈 화면만 띄웠다).
//
// 화면을 둘로 쪼갠 이유: 한 화면에서 코드와 새 비밀번호를 함께 받으면 **코드가 틀렸을 때 새 비밀번호까지
// 같이 날아간다**. 자동 로그인을 뺀 이유: 방금 정한 비밀번호를 사용자가 직접 한 번 쳐 봐야 "정말 바뀌었다"가
// 확인되고, 재설정 경로가 로그인 세션을 만들지 않으므로 recovery 토큰이 디스크에 남을 여지도 사라진다.
@MainActor
extension WorkTimerStore {
    /// **첫 발송** 뒤 재전송이 열리기까지의 초. 60초가 아닌 이유: 첫 메일은 실제로 안 오는 일이 있는데
    /// (스팸함·전송 지연) 그때 1분을 붙잡아 두면 사용자가 할 수 있는 일이 아무것도 없다. 5초면 바로 다시
    /// 눌러 볼 수 있다. 서버가 그보다 긴 간격을 강제해 429 를 주면 **서버가 준 초로 덮인다**(아래 429 분기).
    static let passwordResetFirstResendDelaySeconds = 5
    /// **재전송** 뒤 쿨다운(초). GoTrue 는 같은 이메일에 대한 재발송을 기본 60초로 제한하고 429 를 준다.
    /// 서버가 남은 초를 알려주면 그 값을 쓰고, 못 알아내면 이 값으로 떨어진다(틀려도 '늦게 풀린다' 방향이라 안전).
    static let passwordResetResendCooldownSeconds = 60
    /// 새 비밀번호 최소 길이. GoTrue 기본 최소치와 같은 값이라 여기서 통과한 것을 서버가 길이로 거절하지 않는다.
    static let passwordResetMinPasswordLength = 6
    /// OTP 자릿수. GoTrue 메일 템플릿의 `{{ .Token }}` 기본이 6자리 숫자다.
    static let passwordResetCodeLength = 6

    // 사용자에게 나가는 문장 **그대로**. 한곳에 모아 두는 이유는 문구가 곧 계약이기 때문이다 —
    // 특히 발송 실패/성공 문구는 **계정 존재 여부를 흘리면 안 된다**(recover 는 없는 주소에도 200 을 준다.
    // "가입되지 않은 이메일" 류의 문구는 근거가 없을뿐더러 이 앱을 계정 목록 확인기로 만든다).
    static let passwordResetInvalidEmailMessage = "이메일 주소를 확인해주세요"
    static let passwordResetSentMessage = "메일을 보냈어요 · 오지 않으면 주소를 확인해주세요"
    static let passwordResetAlreadySentMessage = "메일을 이미 보냈어요 · 메일함을 확인해주세요"
    static let passwordResetCooldownMessage = "조금 뒤에 다시 받을 수 있어요"
    static let passwordResetSendFailedMessage = "메일을 보내지 못했어요 · 주소를 확인하고 다시 시도해주세요"
    static let passwordResetNetworkMessage = "네트워크를 확인하고 다시 시도해주세요"
    static let passwordResetInvalidCodeMessage = "메일로 받은 6자리 숫자를 입력해주세요"
    static let passwordResetShortPasswordMessage = "비밀번호 조건 확인 · 6자 이상으로 정해주세요"
    static let passwordResetRejectedPasswordMessage = "비밀번호 조건 확인 · 6자 이상, 이전과 다른 값으로 정해주세요"
    static let passwordResetCodeRejectedMessage = "코드가 맞지 않거나 만료됐어요 · 다시 받기를 눌러주세요"
    static let passwordResetUpdateFailedMessage = "비밀번호를 바꾸지 못했어요 · 다시 시도해주세요"
    /// 재설정 성공 후 **로그인 화면**에 남기는 안내(passwordResetMessage 가 아니라 syncMessage 로 나간다 —
    /// 성공하면 재설정 화면은 사라지고 그 화면의 문구는 함께 청소되기 때문이다).
    /// 자동 로그인을 하지 않으므로 사용자에게 "이제 뭘 해야 하는지"를 이 한 줄이 말해 줘야 한다.
    static let passwordResetChangedSignInMessage = "비밀번호를 바꿨어요 · 새 비밀번호로 로그인해주세요"

    // MARK: 입력 정규화·사전 검증

    /// 재설정 경로가 쓰는 이메일 정규화. **발송과 검증이 같은 문자열을 써야** GoTrue 가 같은 사용자로 본다 —
    /// 코드 화면에서 사용자가 주소를 다시 타이핑하지 않게 하려면 앱이 한 번 접어 두는 편이 확실하다.
    nonisolated static func normalizedResetEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 이메일 형식의 **최소** 검증. 최종 판정자는 서버이고, 이건 "@ 도 없는 입력"으로 왕복(과 60초 쿨다운)을
    /// 태우지 않기 위한 사전 필터다. 정규식으로 RFC 를 흉내 내지 않는다 — 그 흉내가 정상 주소를 막는 쪽으로
    /// 틀리면 사용자는 앱 안에서 영영 비밀번호를 못 바꾼다(지금 고치려는 상황과 정확히 같은 상태가 된다).
    nonisolated static func isPlausibleResetEmail(_ email: String) -> Bool {
        guard !email.contains(where: { $0.isWhitespace }) else { return false }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    /// 코드 정규화. 메일에서 복사하면 공백·하이픈이 섞여 오므로 ASCII 숫자만 남긴다(붙여넣기를 관대하게).
    /// 비ASCII 숫자(전각 등)를 남기지 않는 이유는 서버가 그걸 같은 코드로 보지 않기 때문이다.
    nonisolated static func normalizedResetCode(_ raw: String) -> String {
        String(raw.filter { $0.isASCII && $0.isNumber })
    }

    // MARK: 진입/종료

    /// idle → enterEmail. 로그인 폼에 이미 적혀 있는 이메일을 미리 채운다(그 사람이 방금 로그인에 실패한
    /// 그 주소가 거의 항상 정답이다). 앞선 흐름의 잔재는 여기서 통째로 청소하고 시작한다.
    func beginPasswordReset(email: String) {
        clearPasswordResetState()
        passwordResetEmail = Self.normalizedResetEmail(email)
        passwordResetPhase = .enterEmail
    }

    /// 어느 단계에서든 idle 로 되돌린다(sending/submitting 중 취소 포함).
    func cancelPasswordReset() {
        clearPasswordResetState()
    }

    /// 재설정 상태 전부를 내리는 **유일한 지점**. 취소와 성공이 같은 코드를 지나게 해 두 경로가 갈리지 않게 한다
    /// (성공 뒤에만 코드·이메일·문구가 남는 식의 어긋남을 구조적으로 없앤다).
    ///
    /// 세대를 **가장 먼저** 올린다: 이 줄 이후 도착하는 응답은 전부 '이미 닫힌 흐름의 것'이 되어 상태를 못 쓴다.
    /// 그다음 Task 를 취소해 날아가 있는 URLSession 요청 자체를 끊는다(세대만으로는 요청이 끝까지 살아 서버에
    /// 헛부하를 남긴다). 이 순서가 뒤집히면 취소와 세대 증가 사이의 틈으로 응답이 들어와 상태를 되살린다.
    private func clearPasswordResetState() {
        passwordResetGeneration &+= 1
        passwordResetTask?.cancel()
        passwordResetTask = nil
        passwordResetCooldownTask?.cancel()
        passwordResetCooldownTask = nil
        passwordResetPhase = .idle
        passwordResetMessage = nil
        passwordResetEmail = ""
        passwordResetResendSeconds = 0
        // 발송 차수도 되돌린다. 남겨 두면 다음에 연 재설정 화면의 **첫 발송**이 앞 흐름의 차수를 물려받아
        // 60초로 잠겨, "맨 처음엔 5초"라는 계약이 두 번째 흐름부터 조용히 깨진다.
        passwordResetSendCount = 0
        // 검증까지 끝난 세션도 반드시 버린다 — 남기면 다음 사람이 연 재설정 화면이 앞 사람의 계정 토큰으로
        // 비밀번호를 바꾼다(같은 맥을 여럿이 쓰는 상황에서 실제로 성립하는 경로다).
        passwordResetVerifiedSession = nil
    }

    // MARK: 코드 발송

    /// enterEmail → sending → enterCode. 형식 검증과 쿨다운은 **왕복 전에** 건다.
    func requestPasswordResetCode(email: String) async {
        let normalized = Self.normalizedResetEmail(email)
        guard Self.isPlausibleResetEmail(normalized) else {
            passwordResetEmail = normalized
            passwordResetMessage = Self.passwordResetInvalidEmailMessage
            // idle 에서 직접 불린 경우에도 사용자가 문구를 볼 화면이 있어야 한다.
            if passwordResetPhase != .enterCode { passwordResetPhase = .enterEmail }
            return
        }
        // 쿨다운 중이면 서버가 어차피 429 다. 헛왕복은 서버의 카운터만 더 밀어 대기를 늘린다.
        guard passwordResetResendSeconds <= 0 else {
            passwordResetMessage = Self.passwordResetCooldownMessage
            return
        }
        passwordResetEmail = normalized
        passwordResetMessage = nil
        passwordResetPhase = .sending
        // 새 왕복은 앞선 왕복을 무효화한다(연타·재입력이 겹쳐도 마지막 것만 상태를 쓴다).
        passwordResetGeneration &+= 1
        let generation = passwordResetGeneration
        passwordResetTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRequestPasswordResetCode(email: normalized, generation: generation)
        }
        passwordResetTask = task
        await task.value
        if passwordResetTask == task { passwordResetTask = nil }
    }

    private func performRequestPasswordResetCode(email: String, generation: Int) async {
        do {
            try await service.sendPasswordResetCode(email: email)
            guard generation == passwordResetGeneration else { return }
            passwordResetPhase = .enterCode
            passwordResetMessage = Self.passwordResetSentMessage
            startPasswordResetCooldown(seconds: consumeResendCooldownSeconds())
        } catch {
            guard generation == passwordResetGeneration else { return }
            if case .cancelled = classifyAuthError(error) { return }
            if let serverSeconds = passwordResetRateLimitSeconds(for: error) {
                // 429 = "방금 이미 보냈다". 코드는 이미 메일함으로 가는 중이므로 입력 화면으로 넘긴다 —
                // 이메일 화면에 붙잡아 두면 **받은 코드를 넣을 자리가 없어** 사용자가 그 시간을 헛되이 기다린다.
                passwordResetPhase = .enterCode
                passwordResetMessage = Self.passwordResetAlreadySentMessage
                // 차수는 여기서도 올린다(이 시도도 '한 번 눌렀다'이므로 다음 잠금은 재전송분 60초다).
                // 다만 **남은 초는 서버가 진실이다** — 서버의 최소 간격 설정이 우리 5초보다 길면(지금 60초)
                // 우리 값을 그대로 쓰는 순간 사용자는 열린 버튼을 눌러 429 만 한 번 더 맞는다.
                consumeResendCooldownSeconds()
                startPasswordResetCooldown(seconds: serverSeconds)
                return
            }
            passwordResetPhase = .enterEmail
            passwordResetMessage = passwordResetSendFailureMessage(for: error)
        }
    }

    /// 방금 끝난 발송 뒤에 걸 쿨다운(초)을 정하고 발송 차수를 한 칸 올린다.
    /// 차수를 **여기 한 곳에서만** 올려, "5초냐 60초냐"의 판정과 카운트가 갈릴 여지를 없앤다.
    @discardableResult
    private func consumeResendCooldownSeconds() -> Int {
        let seconds = passwordResetSendCount == 0
            ? Self.passwordResetFirstResendDelaySeconds
            : Self.passwordResetResendCooldownSeconds
        passwordResetSendCount += 1
        return seconds
    }

    /// 재발송 카운트다운을 건다. 남은 초는 **주입 clock 기준 데드라인에서 매번 다시 계산**한다 —
    /// 1초씩 빼기만 하면 잠자기·스케줄 지연이 그대로 누적 오차가 되어 버튼이 실제보다 늦게(또는 일찍) 풀린다.
    /// 대기는 주입 가능한 passwordResetSleep 이라 테스트가 60초를 실제로 자지 않는다.
    func startPasswordResetCooldown(seconds: Int) {
        let seconds = min(max(seconds, 1), 600)
        passwordResetCooldownTask?.cancel()
        passwordResetResendSeconds = seconds
        let deadline = clock().addingTimeInterval(TimeInterval(seconds))
        let generation = passwordResetGeneration
        passwordResetCooldownTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, generation == self.passwordResetGeneration else { return }
                let remaining = Int(ceil(deadline.timeIntervalSince(self.clock())))
                guard remaining > 0 else {
                    if self.passwordResetResendSeconds != 0 { self.passwordResetResendSeconds = 0 }
                    return
                }
                if self.passwordResetResendSeconds != remaining { self.passwordResetResendSeconds = remaining }
                let sleep = self.passwordResetSleep
                await sleep(1)
            }
        }
    }

    // MARK: 코드 검증(1단계)

    /// enterCode → verifying → (성공) enterNewPassword. 코드 6자리는 **왕복 전에** 거른다.
    ///
    /// 이 단계는 비밀번호를 아직 모른다 — 하는 일은 "코드가 맞나"뿐이고, 성공하면 그 대가로 받은 recovery
    /// 세션을 손에 쥐고 다음 화면으로 넘긴다. 실패하면 enterCode 에 그대로 머문다([다시 받기]가 그 화면에 있다).
    func verifyPasswordResetCode(code: String) async {
        let normalizedCode = Self.normalizedResetCode(code)
        guard normalizedCode.count == Self.passwordResetCodeLength else {
            passwordResetMessage = Self.passwordResetInvalidCodeMessage
            return
        }
        guard !passwordResetEmail.isEmpty else {
            // 어느 주소로 보냈는지 모르면 검증할 수 없다(발송 화면부터 다시).
            passwordResetPhase = .enterEmail
            passwordResetMessage = Self.passwordResetInvalidEmailMessage
            return
        }
        // 이미 검증을 통과해 세션을 쥐고 있으면 **왕복하지 않고** 곧장 다음 화면으로 넘긴다.
        // OTP 는 1회용이라 같은 코드를 서버에 다시 보내면 반드시 튕기고, 그러면 사용자는 멀쩡한 코드를
        // 버린 채 재발송 쿨다운에 갇힌다(비밀번호 화면에서 뒤로 돌아왔다가 다시 진행하는 동선이 정확히 이것).
        if passwordResetVerifiedSession != nil {
            passwordResetMessage = nil
            passwordResetPhase = .enterNewPassword
            return
        }
        passwordResetMessage = nil
        passwordResetPhase = .verifying
        passwordResetGeneration &+= 1
        let generation = passwordResetGeneration
        passwordResetTask?.cancel()
        let email = passwordResetEmail
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performVerifyPasswordResetCode(email: email, code: normalizedCode, generation: generation)
        }
        passwordResetTask = task
        await task.value
        if passwordResetTask == task { passwordResetTask = nil }
    }

    private func performVerifyPasswordResetCode(email: String, code: String, generation: Int) async {
        do {
            let verified = try await service.verifyPasswordResetCode(email: email, code: code)
            guard generation == passwordResetGeneration else { return }
            // 세션은 **여기서만** 보관하고 절대 영속하지 않는다(persistSession 을 태우지 않는다).
            passwordResetVerifiedSession = verified
            passwordResetPhase = .enterNewPassword
            passwordResetMessage = nil
        } catch {
            guard generation == passwordResetGeneration else { return }
            if case .cancelled = classifyAuthError(error) { return }
            passwordResetPhase = .enterCode
            passwordResetMessage = passwordResetVerifyFailureMessage(for: error)
        }
    }

    // MARK: 새 비밀번호 설정(2단계)

    /// enterNewPassword → submitting → (성공) idle + 로그인 화면. 비밀번호 길이는 **왕복 전에** 거른다.
    func submitNewPassword(_ newPassword: String) async {
        // 길이는 그래핌으로 센다. 서버(코드포인트)보다 **엄격한 쪽**이라 여기 통과한 값을 서버가 길이로
        // 거절하는 일은 없다(반대 방향으로 조금 보수적인 것은 안전하다).
        guard newPassword.count >= Self.passwordResetMinPasswordLength else {
            passwordResetMessage = Self.passwordResetShortPasswordMessage
            return
        }
        // 손에 쥔 recovery 세션이 이 단계의 전부다. 없으면 바꿀 수단 자체가 없으므로 코드 화면으로 되돌린다.
        guard let verified = passwordResetVerifiedSession else {
            passwordResetPhase = .enterCode
            passwordResetMessage = Self.passwordResetCodeRejectedMessage
            return
        }
        passwordResetMessage = nil
        passwordResetPhase = .submitting
        passwordResetGeneration &+= 1
        let generation = passwordResetGeneration
        passwordResetTask?.cancel()
        let email = passwordResetEmail
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performSubmitNewPassword(
                email: email,
                verified: verified,
                newPassword: newPassword,
                generation: generation
            )
        }
        passwordResetTask = task
        await task.value
        if passwordResetTask == task { passwordResetTask = nil }
    }

    private func performSubmitNewPassword(
        email: String,
        verified: SupabaseSession,
        newPassword: String,
        generation: Int
    ) async {
        do {
            try await service.updatePassword(accessToken: verified.accessToken, newPassword: newPassword)
        } catch {
            guard generation == passwordResetGeneration else { return }
            if case .cancelled = classifyAuthError(error) { return }
            // 붙잡아 둔 세션까지 죽었으면 그 세션으로는 두 번 다시 못 바꾼다 — 버려서 재시도가 코드 검증부터
            // 다시 타게 한다(남겨 두면 같은 실패만 무한 반복한다).
            if let serviceError = error as? SupabaseWorkServiceError,
               serviceError == .sessionExpired || serviceError == .otpInvalidOrExpired {
                passwordResetVerifiedSession = nil
                passwordResetPhase = .enterCode
                passwordResetMessage = passwordResetUpdateFailureMessage(for: error)
                return
            }
            // 그 밖의 거절(6자 미만·이전과 동일·일시 네트워크)은 **비밀번호만** 다시 받으면 되는 일이다.
            // 화면도 세션도 그대로 두어 사용자가 값만 고쳐 곧장 다시 누를 수 있게 한다 — 여기서 세션을 버리면
            // 1회용 OTP 가 날아가 "조건에 안 맞는 비밀번호를 한 번 골랐다"는 이유로 코드부터 다시 받아야 한다.
            passwordResetPhase = .enterNewPassword
            passwordResetMessage = passwordResetUpdateFailureMessage(for: error)
            return
        }
        guard generation == passwordResetGeneration else { return }

        // 새 비밀번호가 섰다. **여기서 로그인시키지 않는다**(completeSignIn 을 부르지 않는다):
        // 재설정은 로그인이 아니라 비밀번호 교체이고, 사장님 요청대로 사용자가 새 비밀번호로 직접 로그인해
        // "정말 바뀌었다"를 스스로 확인해야 한다. 부수 효과로 recovery 세션이 디스크(persistSession)에 남지
        // 않으므로, 다음 실행이 그 토큰으로 되살아나는 경로도 함께 사라진다.
        //
        // 폴링·하트비트·팀 확정은 전부 completeSignIn 안에서만 시작된다 — 그것을 부르지 않는 이 경로에서는
        // 애초에 시작되지 않는다(= 로그아웃인데 백그라운드만 도는 유령 상태가 성립할 수 없다).
        //
        // 청소 전에 핸들을 **반드시 먼저 뗀다**: clearPasswordResetState 의 일은 날아가 있는 왕복을 끊는 것인데,
        // 여기서 그 '날아가 있는 왕복'은 **지금 실행 중인 이 Task 자신**이다. 떼지 않으면 스스로를 취소한다.
        passwordResetTask = nil
        // 보관 세션은 이 안에서 버려진다(clearPasswordResetState → passwordResetVerifiedSession = nil).
        clearPasswordResetState()
        // 로그인 폼을 방금 바꾼 계정으로 채워 둔다 — 주소를 다시 타이핑시키지 않는다.
        self.email = email
        // 비밀번호 칸은 비운다. 여기 남아 있는 값은 방금 **바뀌기 전** 비밀번호(로그인에 실패해서 이 흐름에
        // 들어왔다)라, 그대로 두면 사용자가 그걸로 로그인 버튼을 눌러 또 실패한다.
        self.password = ""
        // 재설정 화면은 사라지므로 안내는 로그인 화면의 상태줄(syncMessage)로 옮겨 싣는다.
        syncMessage = Self.passwordResetChangedSignInMessage
    }

    // MARK: 오류 → 한국어 문구

    /// 키 부재/스키마처럼 **사용자가 아니라 설치가 잘못된** 경우. 재설정 문맥에서도 뜻이 같으므로 기존 문구를 쓴다.
    private func passwordResetConfigMessage(for error: Error) -> String? {
        guard let serviceError = error as? SupabaseWorkServiceError else { return nil }
        switch serviceError {
        case .missingAnonKey, .invalidAPIKey, .databaseSchemaMissing:
            return authMessage(for: serviceError, fallback: Self.passwordResetSendFailedMessage)
        default:
            return nil
        }
    }

    /// 레이트리밋이면 **걸어야 할 쿨다운 초**, 아니면 nil.
    ///
    /// 서버가 남은 초를 말해 주면(`over_email_send_rate_limit` 본문의 "…after N seconds") 그 값을 그대로 쓰고,
    /// 말해 주지 않으면(`over_request_rate_limit` 처럼 초가 아예 없는 본문) 기본 60초로 떨어진다.
    /// nil 을 0초로 취급하면 안 된다 — 버튼이 곧바로 열려 사용자가 429 를 한 번 더 맞는다.
    func passwordResetRateLimitSeconds(for error: Error) -> Int? {
        guard case .rateLimited(let retryAfterSeconds) = error as? SupabaseWorkServiceError else { return nil }
        return retryAfterSeconds ?? Self.passwordResetResendCooldownSeconds
    }

    private func passwordResetSendFailureMessage(for error: Error) -> String {
        if let config = passwordResetConfigMessage(for: error) { return config }
        if classifyAuthError(error) == .transient { return Self.passwordResetNetworkMessage }
        return Self.passwordResetSendFailedMessage
    }

    /// 검증 실패 문구. **만료와 불일치를 가르지 않는다** — GoTrue 는 계정/코드 존재를 흘리지 않으려고 둘 다
    /// 같은 403(otp_expired, "Token has expired or is invalid")으로 주므로 가르는 것이 애초에 불가능하고,
    /// 어느 쪽이든 **사용자가 할 일은 '다시 받기'로 같다**. recovery 토큰이 죽은 경우(.sessionExpired)도 같은 결론이다.
    func passwordResetVerifyFailureMessage(for error: Error) -> String {
        if let config = passwordResetConfigMessage(for: error) { return config }
        // 레이트리밋 판정이 transient 보다 앞이다 — classifyAuthError 는 429 를 transient 로 보기 때문이다.
        if passwordResetRateLimitSeconds(for: error) != nil { return Self.passwordResetCooldownMessage }
        if classifyAuthError(error) == .transient { return Self.passwordResetNetworkMessage }
        return Self.passwordResetCodeRejectedMessage
    }

    func passwordResetUpdateFailureMessage(for error: Error) -> String {
        if let config = passwordResetConfigMessage(for: error) { return config }
        if passwordResetRateLimitSeconds(for: error) != nil { return Self.passwordResetCooldownMessage }
        if classifyAuthError(error) == .transient { return Self.passwordResetNetworkMessage }
        guard let serviceError = error as? SupabaseWorkServiceError else {
            return Self.passwordResetUpdateFailedMessage
        }
        switch serviceError {
        // .weakPassword 로도, .samePasswordReuse 로도 올 수 있다. 공용 매핑이 "password" 를 담은 모든 메시지를
        // .weakPassword 로 뭉개기 때문에 지금은 사실상 전자로만 오지만(SupabaseWorkModels 의 근거 주석 참조),
        // 어느 쪽이든 사용자가 할 일은 하나다 — 그래서 문구가 두 사유를 함께 말한다.
        case .weakPassword, .samePasswordReuse:
            return Self.passwordResetRejectedPasswordMessage
        // recovery 토큰이 죽었다(만료/bad_jwt). 이 세션으로는 두 번 다시 못 바꾸므로 코드부터 다시 받아야 한다.
        case .sessionExpired, .otpInvalidOrExpired:
            return Self.passwordResetCodeRejectedMessage
        default:
            return Self.passwordResetUpdateFailedMessage
        }
    }
}
