import Foundation

@MainActor
extension WorkTimerStore {
    func activateStoredSession() async {
        guard session != nil else {
            return
        }
        await refreshPersistedSessionIfPossible()
        await refreshTeamStatus()
        startStatusRefreshLoop()
    }

    func signIn(email: String, password: String) async {
        syncMessage = "로그인 중"
        do {
            let signedInSession = try await service.signIn(email: email, password: password)
            session = signedInSession
            persistSession(signedInSession, email: email)
            self.password = ""
            syncMessage = "동기화됨"
            await refreshTeamStatus()
            startStatusRefreshLoop()
        } catch {
            syncMessage = authMessage(for: error, fallback: "로그인 실패")
        }
    }

    func signUp(email: String, password: String, displayName: String) async {
        syncMessage = "계정 생성 중"
        do {
            if let createdSession = try await service.signUp(email: email, password: password, displayName: displayName) {
                session = createdSession
                persistSession(createdSession, email: email, displayName: displayName)
                self.password = ""
                syncMessage = "동기화됨"
                await refreshTeamStatus()
                startStatusRefreshLoop()
            } else {
                self.password = ""
                syncMessage = "확인 메일 필요"
            }
        } catch {
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

    private func refreshPersistedSessionIfPossible() async {
        guard let refreshToken = session?.refreshToken else {
            return
        }

        do {
            let refreshedSession = try await service.refreshSession(refreshToken: refreshToken)
            session = refreshedSession
            persistSession(refreshedSession)
            syncMessage = "동기화됨"
        } catch {
            clearPersistedSession()
            syncMessage = authMessage(for: error, fallback: "다시 로그인 필요")
        }
    }
}
