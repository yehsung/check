import Foundation
import Observation

@Observable
@MainActor
final class WorkTimerStore {
    var startedAt: Date?
    var accumulatedSeconds: Int = 0
    var tickerTask: Task<Void, Never>?
    var refreshTask: Task<Void, Never>?
    var syncTask: Task<Void, Never>?
    let service: SupabaseWorkService
    let hasAnonKey: Bool
    let defaults: UserDefaults
    var session: SupabaseSession?
    var sessionGeneration = 0
    var currentSessionID: String?

    var snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
    var displayNow = Date()
    var displayName: String
    var email: String
    var password = ""
    var syncMessage: String
    var teamMembers: [TeamMemberStatus] = []
    var pendingOperation: PendingWorkOperation?
    var pendingStopStartedAt: Date?
    var pendingStopEndedAt: Date?

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

    /// 앱 종료 직전 근무를 마무리한다. 로그인 상태가 아니거나 근무중이 아니면 즉시 리턴(요청 0건).
    /// 근무중이면 기존 stop()/enqueueSync 직렬 경로로 퇴근 upsert를 큐에 넣고, 그 sync 체인이
    /// 끝나거나 timeout(초)이 지날 때까지만 기다린다. 타임아웃 시 서버에 열린 세션이 남을 수 있으나
    /// 다음 실행의 refreshTeamStatus/applyRemoteOwnStatus 복구 경로가 이를 정리하므로 종료를 막지 않는다.
    func finishWorkBeforeQuit(timeout: Double = 3) async {
        guard session != nil, startedAt != nil else { return }
        stop()
        guard let syncTask else { return }
        await Self.awaitFirst(of: syncTask, orTimeout: timeout)
    }

    /// task 완료 또는 timeout 중 먼저 오는 시점에 리턴한다. 진 쪽(타임아웃/미완료 sync)은 취소하지 않고
    /// 백그라운드에 남겨 두어 종료 지연이 timeout을 넘지 않도록 한다.
    private static func awaitFirst(of task: Task<Void, Never>, orTimeout timeout: Double) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let barrier = QuitBarrier(continuation)
            Task { @MainActor in
                await task.value
                barrier.resume()
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                barrier.resume()
            }
        }
    }

    func start(now: Date = Date()) {
        guard startedAt == nil else { return }
        displayNow = now
        startedAt = now
        currentSessionID = UUID().uuidString
        snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
        startTimer()
        syncCurrentStatus()
    }

    func stop(now: Date = Date()) {
        guard let startedAt else { return }
        displayNow = now
        let duration = max(0, Int(now.timeIntervalSince(startedAt)))
        let sessionStart = startedAt
        accumulatedSeconds += duration
        self.startedAt = nil
        snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: accumulatedSeconds)
        stopTimerIfIdle()
        syncCurrentStatus(durationSeconds: duration, sessionStartedAt: sessionStart, endedAt: now)
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
                await self?.retryPendingSync()
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

/// 종료 대기용 단일-resume 장벽. sync 완료와 타임아웃 두 경로가 경쟁하되 continuation은 정확히
/// 한 번만 resume되도록 메인 액터에서 직렬화한다(nil로 만들어 재-resume을 무시).
@MainActor
private final class QuitBarrier {
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
