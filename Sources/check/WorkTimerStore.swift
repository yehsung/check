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

    /// 3D 캐릭터 오버레이 표시 여부 (사용자 토글, UserDefaults 유지).
    var isOverlayEnabled: Bool = true

    /// 팝오버(MenuBarExtra 창) 표시 여부. 표시 감지(onAppear/창 노티)가 setMenuPresented 로 알린다.
    /// 관찰 대상이 아니다 — 티커/폴링 게이팅 판정에만 쓴다.
    @ObservationIgnored var isMenuPresented = false
    /// 실행당 1회 전체 활성화(토큰 회전+멤버십 확정) 플래그. signOut/clearPersistedSession 에서 리셋.
    @ObservationIgnored var hasActivatedStoredSession = false
    /// 메뉴바 라벨 텍스트. 문자열이 실제로 바뀔 때만 대입해 라벨 무효화를 최소화한다.
    var menuBarTitle = "오프"

    /// 팝오버 표시 상태를 반영한다(idempotent — 중복 신호 무해).
    /// 열림: 낡은 초를 즉시 갱신하고 티커/리그를 재개. 닫힘: 티커 게이팅만 재평가.
    func setMenuPresented(_ presented: Bool) {
        guard isMenuPresented != presented else { return }
        isMenuPresented = presented
        if presented {
            displayNow = Date()
            stopTimerIfIdle()
            if isLeaderboardVisible { loadLeaderboard() }
        } else {
            stopTimerIfIdle()
        }
    }

    /// 리액션 트리거 싱크. 오버레이 컨트롤러가 연결해 마일스톤/팀원 인사를 엔진으로 흘린다(관찰 대상 아님).
    @ObservationIgnored var onReactionTrigger: ((ReactionKind) -> Void)?
    /// 마일스톤 1일 1회 기록기. init 에서 defaults 로 초기화한다.
    @ObservationIgnored var milestoneTracker: MilestoneTracker!
    /// 팀원 출근 인사(offWork→working) 전이 감지기. 로그아웃 시 reset.
    @ObservationIgnored var greetingDetector = TeammateGreetingDetector()
    /// 팀 주간 목표 완료 상태의 직전 관측값. nil=첫 로드(전이로 치지 않음). false→true 로 바뀌는 순간만 축하.
    @ObservationIgnored var teamGoalComplete: Bool?

    // 잠자기/깨어남 옵저버 토큰. 보관해 두어 필요 시 해제할 수 있게 한다(클로저는 [weak self] 라 수명 자체는 안전).
    @ObservationIgnored private var sleepObserverToken: NSObjectProtocol?
    @ObservationIgnored private var wakeObserverToken: NSObjectProtocol?
    @ObservationIgnored private var observedWorkspaceCenter: NotificationCenter?

    var snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
    var displayNow = Date()
    var displayName: String
    var email: String
    var password = ""
    var syncMessage: String
    var teamMembers: [TeamMemberStatus] = []
    // 멀티팀 상태.
    // teamName: 로그인 후 내 팀 이름(미확정 시 "팀"). currentTeamID: 확정된 내 팀 id(무소속이면 nil).
    // teamRole: 확정된 내 역할(owner/member, 무소속이면 nil).
    var teamName = "팀"
    var currentTeamID: String?
    var teamRole: String?

    // (레거시 호환) 초대코드 흐름 전의 가입 뷰/렌더 테스트가 아직 참조하는 팀 목록/선택 상태.
    // 새 가입 흐름은 팀 목록을 노출하지 않으므로 이 값들은 채우지 않는다(형만 유지).
    var teamDirectory: [TeamDirectoryEntry] = []
    var selectedSignupTeamID: String?

    // 초대코드 기반 가입/합류 상태.
    // signupTeamCode: 코드 입력 바인딩. joinPreview: 미리보기 결과(nil=미확인/불일치). joinPreviewMessage: 상태 문구.
    // isCreateTeamMode: 가입 화면 코드 입력 ↔ 팀 만들기 전환. createTeamName/createTeamGoalHours: 팀 만들기 폼.
    // createdTeamCode: 방금 만든 팀의 참여코드(공유 안내용). myTeamInviteCode: owner 일 때만 채워짐.
    var signupTeamCode = ""
    var joinPreview: TeamJoinPreview?
    var joinPreviewMessage = ""
    var isCreateTeamMode = false
    var createTeamName = ""
    var createTeamGoalHours = 60
    var createdTeamCode: String?
    var myTeamInviteCode: String?
    // 코드 미리보기 재입력 경합 방지용 세대 카운터(세션과 무관 — 비로그인에서도 쓰므로). 마지막 요청만 반영한다.
    var previewGeneration = 0
    // 팀 주간 목표시간(초). 출처는 오직 teams.weekly_goal_hours(멤버십 조회 시 확정). 앱은 읽기 전용이다.
    // confirmMembership 성공 시 서버 값으로 갱신하고, signOut/무소속이면 기본값으로 되돌린다.
    var teamGoalSeconds = TeamWeeklyGoal.defaultGoalSeconds
    // 서버 미반영 근무 조작의 FIFO 큐. 단일 슬롯이 아니라 큐라, in-flight 중 들어온 반대 조작이나
    // 오프라인에서 쌓인 여러 세션이 유실되지 않고 순서대로 재생된다. 각 항목은 자체 세션 정보를 동봉해
    // currentSessionID 변화와 무관하게 정확히 재생된다.
    var pendingItems: [PendingWorkItem] = []

    // 팀 리그(이번 주 팀별 근무시간) 페이지 상태.
    // leaderboard: 1인당 평균 근무시간 내림차순(동률 시 이름)으로 정렬한 팀 목록. isLeaderboardVisible: 리그 페이지 노출 여부.
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
        guard let startedAt else { return accumulatedSeconds }
        // 진행 세션 기여를 KST 자정으로 클리핑한다: 자정을 넘긴 세션이 오늘 표시를 부풀리거나 자정 직후
        // 마일스톤이 오발화하지 않게 하고, 시계 되돌림으로 음수가 되면 0으로 클램프한다.
        let dayStart = TeamWeeklyGoal.koreanDayStart(for: displayNow)
        let effectiveStart = max(startedAt, dayStart)
        return accumulatedSeconds + max(0, Int(displayNow.timeIntervalSince(effectiveStart)))
    }

    /// 내 이번 주 누적(초). 팀 목록에서 내 행의 라이브 주간값을 쓰고, 아직 못 받았으면 오늘 누적으로 대체한다.
    /// 헤더 보조 문구와 내 팀 카드의 "내 주간 목표 진행률" 게이지가 같은 값을 쓰도록 한곳에서 계산한다.
    var myLiveWeeklySeconds: Int {
        guard let userID = session?.userID,
              let mine = teamMembers.first(where: { $0.id == userID })
        else {
            return todayDuration
        }
        return mine.liveWeeklyDurationSeconds(now: displayNow)
    }

    var canSync: Bool {
        hasAnonKey
    }

    var isSignedIn: Bool {
        session != nil
    }

    /// 로그인은 되어 있으나 소속 팀이 없는 상태. 무소속 계정에 팀 코드 입력 패널을 띄우는 판정에 쓴다.
    var isTeamless: Bool {
        isSignedIn && currentTeamID == nil
    }

    /// 내가 현재 팀의 owner 인지. owner 여야 팀 카드에서 참여코드 보기/복사를 노출한다.
    var isTeamOwner: Bool {
        teamRole == "owner"
    }

    init(
        service: SupabaseWorkService = SupabaseWorkService(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        workspaceNotifications: NotificationCenter? = NSWorkspace.shared.notificationCenter
    ) {
        self.service = service
        self.defaults = defaults
        milestoneTracker = MilestoneTracker(defaults: defaults)
        hasAnonKey = SupabaseConfig.anonKey(environment: environment) != nil
        email = defaults.string(forKey: Self.emailKey) ?? ""
        displayName = defaults.string(forKey: Self.displayNameKey) ?? ""
        isOverlayEnabled = defaults.object(forKey: Self.overlayEnabledKey) as? Bool ?? true
        let restoredSession = Self.restoredSession(from: defaults)
        session = restoredSession
        syncMessage = hasAnonKey ? (restoredSession == nil ? "로그인 필요" : "동기화됨") : "Supabase 키 필요"
        observeSleepWake(workspaceNotifications)
        refreshMenuBarTitle()
    }

    /// 잠자기/깨어남 노티를 구독한다. 클로저는 [weak self]로 스토어 수명을 넘겨 자동 무력화되므로
    /// 별도 해제가 필요 없다(테스트는 handleSleep/handleWake 를 직접 호출한다).
    private func observeSleepWake(_ center: NotificationCenter?) {
        guard let center else { return }
        observedWorkspaceCenter = center
        sleepObserverToken = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [weak self] _ in
            let now = Date()
            Task { @MainActor in self?.handleSleep(at: now) }
        }
        wakeObserverToken = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
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
        refreshMenuBarTitle()
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
        refreshMenuBarTitle()
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
        refreshMenuBarTitle()
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
        // 코드 모드: 미리보기가 확인되어야(joinPreview != nil) 가입 가능. 만들기 모드: 팀 이름 필수.
        if isCreateTeamMode {
            guard !createTeamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                syncMessage = "팀 이름을 입력해 주세요"
                return nil
            }
        } else {
            guard joinPreview != nil else {
                syncMessage = "팀 코드를 확인해 주세요"
                return nil
            }
        }

        let task = Task {
            await signUp(email: trimmedEmail, password: password, displayName: trimmedDisplayName)
        }
        return task
    }

    /// 팀 코드 미리보기(가입 화면). signupTeamCode 를 검증해 joinPreview/joinPreviewMessage 를 갱신한다.
    /// 디바운스는 UI 몫이고, 여기선 재입력 경합만 막는다(마지막 요청 우선). 비로그인에서도 호출 가능.
    func previewTeamCode() {
        previewGeneration &+= 1
        Task { @MainActor in await performPreviewTeamCode() }
    }

    /// 무소속 계정 패널의 합류 액션. 로그인 상태에서 signupTeamCode 로 join_team 을 실행한다.
    func joinTeamWithCode() {
        Task { @MainActor in await performJoinTeamWithCode() }
    }

    /// 방금 만든 팀의 참여코드 안내를 닫는다.
    func dismissCreatedTeamCode() {
        createdTeamCode = nil
    }

    func refreshTeamStatus() {
        Task {
            await refreshTeamStatus()
        }
    }

    /// (레거시 호환) 초대코드 흐름 전의 가입 뷰가 호출하던 팀 목록 로드. 팀 목록 공개를 폐기했으므로 no-op 이다.
    /// 새 가입 흐름은 previewTeamCode()/createTeam 으로 대체됐다.
    func loadTeamDirectory() {}

    /// 트로피 버튼 액션. 리그 페이지를 토글하고, 여는 순간 순위를 로드한다.
    func toggleLeaderboard() {
        isLeaderboardVisible.toggle()
        if isLeaderboardVisible {
            loadLeaderboard()
        }
    }

    func startTimer() {
        guard tickerTask == nil else { return }
        tickerTask?.cancel()
        tickerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // 표시값은 wall-clock 파생이라 누적 오차가 없어 tolerance 로 웨이크업을 병합해도 안전하다.
                try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(200))
                self?.tick()
            }
        }
    }

    func stopTimerIfIdle() {
        // 내가 근무중이면 티커를 항상 유지한다(12h 확인/마일스톤/라벨 갱신). 팀원 초침만 필요한 경우는
        // 팝오버가 열려 있을 때만 티커를 돌린다 — 숨김 상태에선 매초 재평가가 낭비이므로 정지한다.
        guard startedAt == nil, !(isMenuPresented && teamMembers.contains(where: { $0.status == .working })) else {
            startTimer()
            return
        }
        tickerTask?.cancel()
        tickerTask = nil
    }

    /// 30초 refresh 루프의 적응형 주기 판정. 근무중/팝오버 열림/미반영 큐가 있으면 빠른 주기(30s)로,
    /// 그 외 유휴에선 느린 주기(300s)로 돈다. 팝오버를 여는 순간의 즉시 refresh(.task)가 감속 지연을 메운다.
    var refreshLoopIsFast: Bool {
        startedAt != nil || isMenuPresented || !pendingItems.isEmpty
    }

    func startStatusRefreshLoop() {
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let fast = self?.refreshLoopIsFast ?? false
                try? await Task.sleep(for: .seconds(fast ? 30 : 300), tolerance: .seconds(fast ? 5 : 30))
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
        // snapshot 은 재대입하지 않는다 — 라벨/오버레이/헤더 전체 무효화를 막는다. 라이브 초는 todayDuration
        // (잎 뷰)과 menuBarTitle 파생값으로 흐르고, 여기선 정책 평가와 라벨 문자열만 갱신한다.
        if startedAt != nil {
            evaluateLongSession(now: now)
            evaluateTimeMilestones(now: now)
            refreshMenuBarTitle()
        }
    }

    /// 메뉴바 라벨 문자열을 현재 상태에서 다시 계산해, 문자열이 실제로 바뀔 때만 대입한다.
    /// (@Observable 은 동일 값 대입도 관찰자를 발화시키므로 != 가드가 무효화 최소화의 핵심이다.)
    func refreshMenuBarTitle() {
        var derived = snapshot
        if derived.isWorking {
            derived.elapsedSeconds = todayDuration
        }
        let new = MenuBarStatusFormatter.title(for: derived)
        if menuBarTitle != new {
            menuBarTitle = new
        }
    }

    /// 근무 중 오늘 누적이 1시간/4시간을 넘는 순간 마일스톤 축하를 트리거한다(마일스톤별 1일 1회).
    /// 4시간을 이미 넘긴 채 관측되면 1시간 키는 조용히 소비해 뒤늦게 축하가 터지지 않게 한다.
    func evaluateTimeMilestones(now: Date) {
        guard startedAt != nil else { return }
        let today = todayDuration
        if today >= 4 * 3_600 {
            if milestoneTracker.fireIfNeeded(MilestoneTracker.hourFourKey, now: now) {
                onReactionTrigger?(.milestone)
            }
            _ = milestoneTracker.fireIfNeeded(MilestoneTracker.hourOneKey, now: now)
        } else if today >= 3_600 {
            if milestoneTracker.fireIfNeeded(MilestoneTracker.hourOneKey, now: now) {
                onReactionTrigger?(.milestone)
            }
        }
    }
}

extension WorkTimerStore {
    static let emailKey = "check.userEmail"
    static let displayNameKey = "check.displayName"
    static let overlayEnabledKey = "check.overlayEnabled"

    /// 캐릭터 오버레이 표시 여부를 지정하고 설정을 저장한다.
    func setOverlayEnabled(_ enabled: Bool) {
        isOverlayEnabled = enabled
        defaults.set(enabled, forKey: Self.overlayEnabledKey)
    }

    /// 캐릭터 오버레이 표시를 토글하고 설정을 저장한다.
    func toggleOverlayEnabled() {
        setOverlayEnabled(!isOverlayEnabled)
    }
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
        // 세대를 올려 이 시점 이후 완료되는 낡은 Task 의 부수효과를 차단한다(토큰 만료 로그아웃 공통 경로).
        sessionGeneration += 1
        currentSessionID = nil
        hasActivatedStoredSession = false
        session = nil
        [Self.accessTokenKey, Self.refreshTokenKey, Self.userIDKey].forEach(defaults.removeObject)
        // 세션이 사라지면 리그 페이지 상태도 함께 초기화한다(signOut·토큰 만료 로그아웃 공통 경로).
        leaderboard = []
        isLeaderboardVisible = false
        // 팀원 인사/팀 목표 축하의 세션 상태도 비운다(다음 로그인의 첫 로드에서 인사 폭탄 금지).
        greetingDetector.reset()
        teamGoalComplete = nil
        refreshTask?.cancel()
        refreshTask = nil
        refreshMenuBarTitle()
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

/// 서버 미반영 근무 조작 한 건. 조작 종류와 그 조작이 속한 세션 정보를 함께 담아, 큐가 나중에 드레인할 때
/// currentSessionID/startedAt 의 이후 변화와 무관하게 정확히 재생되도록 한다(오프라인 복구 정합성).
struct PendingWorkItem: Equatable {
    let id: UUID
    let operation: PendingWorkOperation
    let sessionID: String
    let sessionStartedAt: Date?
    let endedAt: Date?
}
