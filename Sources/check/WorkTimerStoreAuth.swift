import Foundation

@MainActor
extension WorkTimerStore {
    func activateStoredSession() async {
        guard session != nil else {
            return
        }
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

    func signUp(email: String, password: String, displayName: String, teamID: String) async {
        syncMessage = "계정 생성 중"
        let generation = sessionGeneration
        do {
            if let createdSession = try await service.signUp(email: email, password: password, displayName: displayName, teamID: teamID) {
                guard generation == sessionGeneration else { return }
                session = createdSession
                persistSession(createdSession, email: email, displayName: displayName)
                self.password = ""
                // 가입 직후 트리거가 membership 을 만들기까지 지연될 수 있으므로 재시도로 확정한다.
                await confirmMembership(allowRetryForFreshSignup: true)
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

    /// 로그인/세션복구/가입 성공 후 내 팀을 확정한다. 소속이 있으면 currentTeamID/teamName/teamGoalSeconds 를
    /// 서버 값으로 채우고, 없으면 무소속(currentTeamID=nil, teamName="팀", 목표=기본값)으로 둔다.
    /// 가입 직후에는 트리거 타이밍 때문에 빈 값이면 1초 간격으로 3회까지 재시도한다.
    func confirmMembership(allowRetryForFreshSignup: Bool = false) async {
        guard session != nil else { return }
        let generation = sessionGeneration
        let attempts = allowRetryForFreshSignup ? 3 : 1
        for attempt in 0..<attempts {
            let membership = try? await withSessionRetry { activeSession in
                try await service.fetchOwnMembership(accessToken: activeSession.accessToken, userID: activeSession.userID)
            }
            guard generation == sessionGeneration else { return }
            if let membership = membership ?? nil {
                currentTeamID = membership.teamID
                teamName = membership.teamName
                // 목표시간은 DB 값(시간) 그대로 초로 환산해 반영한다(캐시/일회성 없음).
                teamGoalSeconds = membership.goalHours * 3600
                return
            }
            if attempt + 1 < attempts {
                try? await Task.sleep(for: .seconds(1))
                guard generation == sessionGeneration else { return }
            }
        }
        currentTeamID = nil
        teamName = "팀"
        teamGoalSeconds = TeamWeeklyGoal.defaultGoalSeconds
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
                clearPersistedSession()
                syncMessage = "다시 로그인 필요"
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
        teamMembers = []
        currentTeamID = nil
        teamName = "팀"
        teamGoalSeconds = TeamWeeklyGoal.defaultGoalSeconds
        teamDirectory = []
        selectedSignupTeamID = nil
        pendingOperation = nil
        pendingStopStartedAt = nil
        pendingStopEndedAt = nil
        longSessionAnchor = nil
        clearLongSessionPrompt()
        sleepBeganAt = nil
        lastAutoClosedSessionID = nil
        lastAutoClosedStartedAt = nil
        snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        tickerTask?.cancel()
        tickerTask = nil
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
            clearPersistedSession()
            syncMessage = authMessage(for: error, fallback: "다시 로그인 필요")
        }
    }
}
