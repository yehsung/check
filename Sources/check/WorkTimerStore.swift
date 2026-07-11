import Foundation
import Observation

@Observable
@MainActor
final class WorkTimerStore {
    var startedAt: Date?
    var accumulatedSeconds: Int = 0
    var tickerTask: Task<Void, Never>?
    var refreshTask: Task<Void, Never>?
    let service: SupabaseWorkService
    let hasAnonKey: Bool
    let defaults: UserDefaults
    var session: SupabaseSession?

    var snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
    var displayNow = Date()
    var displayName: String
    var email: String
    var password = ""
    var syncMessage: String
    var teamMembers: [TeamMemberStatus] = []

    var todayDuration: Int {
        accumulatedSeconds + (startedAt.map { Int(displayNow.timeIntervalSince($0)) } ?? 0)
    }

    var canSync: Bool {
        hasAnonKey
    }

    var isSignedIn: Bool {
        session != nil
    }

    init(
        service: SupabaseWorkService = SupabaseWorkService(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults
        hasAnonKey = SupabaseConfig.anonKey(environment: environment) != nil
        email = defaults.string(forKey: Self.emailKey) ?? ""
        displayName = defaults.string(forKey: Self.displayNameKey) ?? ""
        let restoredSession = Self.restoredSession(from: defaults)
        session = restoredSession
        syncMessage = hasAnonKey ? (restoredSession == nil ? "로그인 필요" : "동기화됨") : "Supabase 키 필요"
    }

    func toggle() {
        if snapshot.isWorking {
            stop()
        } else {
            start()
        }
    }

    func start(now: Date = Date()) {
        guard startedAt == nil else { return }
        displayNow = now
        startedAt = now
        snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
        startTimer()
        syncCurrentStatus()
    }

    func stop(now: Date = Date()) {
        guard let startedAt else { return }
        displayNow = now
        let duration = max(0, Int(now.timeIntervalSince(startedAt)))
        accumulatedSeconds += max(0, Int(now.timeIntervalSince(startedAt)))
        self.startedAt = nil
        snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: accumulatedSeconds)
        stopTimerIfIdle()
        syncCurrentStatus(durationSeconds: duration)
    }

    @discardableResult
    func signIn() -> Task<Void, Never>? {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            syncMessage = "이메일과 비밀번호 필요"
            return nil
        }

        let task = Task {
            await signIn(email: trimmedEmail, password: password)
        }
        return task
    }

    @discardableResult
    func signUp() -> Task<Void, Never>? {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty, !trimmedDisplayName.isEmpty else {
            syncMessage = "이메일, 비밀번호, 별명 필요"
            return nil
        }

        let task = Task {
            await signUp(email: trimmedEmail, password: password, displayName: trimmedDisplayName)
        }
        return task
    }

    func refreshTeamStatus() {
        Task {
            await refreshTeamStatus()
        }
    }

    func startTimer() {
        guard tickerTask == nil else { return }
        tickerTask?.cancel()
        tickerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    func stopTimerIfIdle() {
        guard startedAt == nil, !teamMembers.contains(where: { $0.status == .working }) else {
            startTimer()
            return
        }
        tickerTask?.cancel()
        tickerTask = nil
    }

    func startStatusRefreshLoop() {
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self?.refreshTeamStatus()
            }
        }
    }

    private func tick() {
        let now = Date()
        displayNow = now
        if let startedAt {
            snapshot = WorkStatusSnapshot(
                status: .working,
                elapsedSeconds: max(0, Int(now.timeIntervalSince(startedAt)))
            )
        }
    }
}

extension WorkTimerStore {
    static let emailKey = "check.userEmail"
    static let displayNameKey = "check.displayName"
    static let accessTokenKey = "check.session.accessToken"
    static let refreshTokenKey = "check.session.refreshToken"
    static let userIDKey = "check.session.userID"

    static func restoredSession(from defaults: UserDefaults) -> SupabaseSession? {
        guard let accessToken = defaults.string(forKey: accessTokenKey),
              let userID = defaults.string(forKey: userIDKey)
        else {
            return nil
        }
        return SupabaseSession(
            accessToken: accessToken,
            refreshToken: defaults.string(forKey: refreshTokenKey),
            userID: userID
        )
    }

    func persistSession(_ session: SupabaseSession, email: String? = nil, displayName: String? = nil) {
        defaults.set(session.accessToken, forKey: Self.accessTokenKey)
        defaults.set(session.userID, forKey: Self.userIDKey)
        if let refreshToken = session.refreshToken {
            defaults.set(refreshToken, forKey: Self.refreshTokenKey)
        } else {
            defaults.removeObject(forKey: Self.refreshTokenKey)
        }
        if let email {
            defaults.set(email, forKey: Self.emailKey)
        }
        if let displayName {
            defaults.set(displayName, forKey: Self.displayNameKey)
        }
    }

    func clearPersistedSession() {
        session = nil
        [Self.accessTokenKey, Self.refreshTokenKey, Self.userIDKey].forEach(defaults.removeObject)
        refreshTask?.cancel()
        refreshTask = nil
    }
}
