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
        pendingOperation = nil
        pendingStopStartedAt = nil
        pendingStopEndedAt = nil
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
