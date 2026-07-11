import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class WorkTimerStore {
    // 연속 근무 확인/자동 마감 임계값. 12시간 도달 시 확인, 이후 30분 무응답이면 12시간 시점으로 마감.
    static let longSessionThresholdSeconds: TimeInterval = 12 * 60 * 60
    static let longSessionResponseWindowSeconds: TimeInterval = 30 * 60
    // 잠자기 유예. 이 시간 이하 잠자기는 근무 연속으로 인정, 초과하면 덮은 시각으로 마감.
    static let sleepGraceSeconds: TimeInterval = 5 * 60

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
    // 멀티팀 상태.
    // teamDirectory: 가입 화면 팀 목록. selectedSignupTeamID: 가입 시 선택한 팀.
    // teamName: 로그인 후 내 팀 이름(미확정 시 "팀"). currentTeamID: 확정된 내 팀 id(무소속이면 nil).
    var teamDirectory: [TeamDirectoryEntry] = []
    var selectedSignupTeamID: String?
    var teamName = "팀"
    var currentTeamID: String?
    // 팀 주간 목표시간(초). 출처는 오직 teams.weekly_goal_hours(멤버십 조회 시 확정). 앱은 읽기 전용이다.
    // confirmMembership 성공 시 서버 값으로 갱신하고, signOut/무소속이면 기본값으로 되돌린다.
    var teamGoalSeconds = TeamWeeklyGoal.defaultGoalSeconds
    var pendingOperation: PendingWorkOperation?
    var pendingStopStartedAt: Date?
    var pendingStopEndedAt: Date?

    // 팀 리그(이번 주 팀별 총 근무시간 경쟁) 페이지 상태.
    // leaderboard: 총시간 내림차순으로 정렬한 팀 순위. isLeaderboardVisible: 리그 페이지 노출 여부.
    // 페이지가 열려 있는 동안 30초 refresh 루프가 함께 갱신하고, signOut 시 둘 다 초기화한다.
    var leaderboard: [TeamLeaderboardEntry] = []
    var isLeaderboardVisible = false

    // 잠자기 정책: willSleep 시각을 기록해 didWake 에서 잠든 시간을 판정한다.
    var sleepBeganAt: Date?
    // 12시간 확인: 카운터 기준점(근무 시작 또는 마지막 "네, 근무 중이에요" 확인 시점).
    var longSessionAnchor: Date?
    var isLongSessionPromptActive = false
    var promptShownAt: Date?
    // 자리 비움 자동 마감 되돌리기용: 마지막으로 자동 마감한 세션.
    var lastAutoClosedSessionID: String?
    var lastAutoClosedStartedAt: Date?


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
        defaults: UserDefaults = .standard,
        workspaceNotifications: NotificationCenter? = NSWorkspace.shared.notificationCenter
    ) {
        self.service = service
        self.defaults = defaults
        hasAnonKey = SupabaseConfig.anonKey(environment: environment) != nil
        email = defaults.string(forKey: Self.emailKey) ?? ""
        displayName = defaults.string(forKey: Self.displayNameKey) ?? ""
        let restoredSession = Self.restoredSession(from: defaults)
        session = restoredSession
        syncMessage = hasAnonKey ? (restoredSession == nil ? "로그인 필요" : "동기화됨") : "Supabase 키 필요"
        observeSleepWake(workspaceNotifications)
    }

    /// 잠자기/깨어남 노티를 구독한다. 클로저는 [weak self]로 스토어 수명을 넘겨 자동 무력화되므로
    /// 별도 해제가 필요 없다(테스트는 handleSleep/handleWake 를 직접 호출한다).
    private func observeSleepWake(_ center: NotificationCenter?) {
        guard let center else { return }
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [weak self] _ in
            let now = Date()
            Task { @MainActor in self?.handleSleep(at: now) }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            let now = Date()
            Task { @MainActor in self?.handleWake(at: now) }
        }
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
        longSessionAnchor = now
        clearLongSessionPrompt()
        sleepBeganAt = nil
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
        longSessionAnchor = nil
        clearLongSessionPrompt()
        sleepBeganAt = nil
        snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: accumulatedSeconds)
        stopTimerIfIdle()
        syncCurrentStatus(durationSeconds: duration, sessionStartedAt: sessionStart, endedAt: now)
    }

    // MARK: - 잠자기 정책 (5분 유예)

    /// willSleep. 근무중이면 덮은 시각을 기록한다(깨어날 때 잠든 시간을 재기 위함).
    func handleSleep(at date: Date = Date()) {
        guard startedAt != nil else { return }
        sleepBeganAt = date
    }

    /// didWake. 잠든 시간이 5분 이하면 근무 연속으로 인정, 초과하면 덮은 시각으로 자동 마감한다.
    func handleWake(at date: Date = Date()) {
        guard let sleepBeganAt, startedAt != nil else {
            self.sleepBeganAt = nil
            return
        }
        let asleep = date.timeIntervalSince(sleepBeganAt)
        guard asleep > Self.sleepGraceSeconds else {
            self.sleepBeganAt = nil
            return
        }
        autoStop(endedAt: sleepBeganAt, message: "잠자기로 자동 근무종료됨")
    }

    // MARK: - 12시간 확인 (30분 무응답 자동 마감)

    /// 근무 틱에서 호출. 12시간 도달 시 확인 배너를 띄우고, 배너 노출 후 30분 무응답이면 12시간 시점으로 마감한다.
    func evaluateLongSession(now: Date) {
        guard startedAt != nil, let anchor = longSessionAnchor else { return }

        if isLongSessionPromptActive {
            guard let promptShownAt, now.timeIntervalSince(promptShownAt) > Self.longSessionResponseWindowSeconds else {
                return
            }
            autoStop(
                endedAt: anchor.addingTimeInterval(Self.longSessionThresholdSeconds),
                message: "장시간 미확인으로 자동 근무종료됨"
            )
            return
        }

        if now.timeIntervalSince(anchor) > Self.longSessionThresholdSeconds {
            isLongSessionPromptActive = true
            promptShownAt = now
        }
    }

    /// 배너의 "네, 근무 중이에요" 액션. 배너를 닫고 12시간 카운터를 지금부터 다시 시작한다.
    func confirmStillWorking() {
        guard isLongSessionPromptActive else { return }
        clearLongSessionPrompt()
        longSessionAnchor = Date()
    }

    func clearLongSessionPrompt() {
        isLongSessionPromptActive = false
        promptShownAt = nil
    }

    /// 지정한 종료 시각으로 로컬 상태를 즉시 마감하고, 기존 직렬 sync 경로(enqueueSync)로 서버에 반영한다.
    /// syncMessage 는 사유 문구로 세팅한다(이후 refresh 가 "동기화됨"으로 정규화할 수 있음 — 즉시 피드백 목적).
    private func autoStop(endedAt: Date, message: String) {
        guard let sessionStart = startedAt else { return }
        let duration = max(0, Int(endedAt.timeIntervalSince(sessionStart)))
        accumulatedSeconds += duration
        startedAt = nil
        longSessionAnchor = nil
        clearLongSessionPrompt()
        sleepBeganAt = nil
        snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: accumulatedSeconds)
        stopTimerIfIdle()
        syncCurrentStatus(durationSeconds: duration, sessionStartedAt: sessionStart, endedAt: endedAt)
        syncMessage = message
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
        guard let teamID = selectedSignupTeamID else {
            syncMessage = "팀을 선택해 주세요"
            return nil
        }

        let task = Task {
            await signUp(email: trimmedEmail, password: password, displayName: trimmedDisplayName, teamID: teamID)
        }
        return task
    }

    func refreshTeamStatus() {
        Task {
            await refreshTeamStatus()
        }
    }

    /// 가입 모드 진입 시 호출. 서버(team_directory RPC)에서 팀 목록을 로드한다(Task 발사).
    func loadTeamDirectory() {
        Task { @MainActor in await performLoadTeamDirectory() }
    }

    /// 트로피 버튼 액션. 리그 페이지를 토글하고, 여는 순간 순위를 로드한다.
    func toggleLeaderboard() {
        isLeaderboardVisible.toggle()
        if isLeaderboardVisible {
            loadLeaderboard()
        }
    }

    func performLoadTeamDirectory() async {
        do {
            teamDirectory = try await service.fetchTeamDirectory()
        } catch {
            // 목록 로드 실패는 조용히 무시한다(가입 버튼은 여전히 팀 미선택으로 거부됨).
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
                await self?.sendHeartbeatIfWorking()
                await self?.refreshTeamStatus()
                await self?.refreshLeaderboardIfVisible()
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
            evaluateLongSession(now: now)
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
        // 세션이 사라지면 리그 페이지 상태도 함께 초기화한다(signOut·토큰 만료 로그아웃 공통 경로).
        leaderboard = []
        isLeaderboardVisible = false
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
