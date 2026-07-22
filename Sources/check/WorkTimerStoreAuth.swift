import Foundation

@MainActor
extension WorkTimerStore {
    func activateStoredSession() async {
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
            session = signedInSession
            persistSession(signedInSession, email: email)
            self.password = ""
            await confirmMembership()
            guard generation == sessionGeneration else { return }
            syncMessage = "동기화됨"
            await refreshTeamStatus()
            guard generation == sessionGeneration else { return }
            startStatusRefreshLoop()
        } catch {
            guard generation == sessionGeneration else { return }
            syncMessage = authMessage(for: error, fallback: "로그인 실패")
        }
    }

    func signUp(email: String, password: String, displayName: String) async {
        syncMessage = "계정 생성 중"
        let generation = sessionGeneration
        do {
            if let createdSession = try await service.signUp(email: email, password: password, displayName: displayName) {
                guard generation == sessionGeneration else { return }
                session = createdSession
                persistSession(createdSession, email: email, displayName: displayName)
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
        pendingItems = []
        longSessionAnchor = nil
        clearLongSessionPrompt()
        sleepBeganAt = nil
        lastAutoClosedSessionID = nil
        lastAutoClosedStartedAt = nil
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
