import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// 지금 탭 스토어(SPEC-ios §3.2 · §4 스냅샷 쓰기).
///
/// 자리 API(기반이 부르는 것 — 이름·모양을 지킨다)
/// - `init(context:)` — 앱 모델이 로그인 여부와 무관하게 한 번 만든다. 여기서 네트워크를 부르지 않는다.
/// - `appDidBecomeActive()` — 로그인 상태에서 앱이 active 가 될 때 · active 인 채로 로그인이 끝났을 때.
/// - `appDidEnterBackground()` — 앱이 background 로 갈 때(주기 작업을 멈춘다).
/// - `reset()` — 로그아웃·치명 만료로 세대가 바뀐 직후(계정에 묶인 값을 전부 비운다).
/// - `badgeCount` — 탭 배지 없음(0).
///
/// 데이터(읽기만 — 폰 금지 호출 없음)
/// - 내 상태·우리 팀: `fetchOwnMembership` + `fetchTeamStatuses`(GET 넷) 를 받아 **값으로만** 계산한다. 맥 스토어의 팀 상태 반영
///   (세션 흡수 · 소유권 · 버려진 세션 마감)은 가져오지 않는다 — 그 경로가 근무 쓰기로 샌다(ios-inventory R2).
/// - 다른 팀: `app_user_directory` 의 근무 여부·센터만(경과 시간은 서버가 주지 않는다).
/// - 주간 목표 쓰기: `set_team_weekly_goal`(팀 전체 1인당 목표 — 맥과 같은 권한 규칙, 팀원 누구나).
/// - 할 일: 코어 `TodoListStore` · `TodoSync` 를 App Group 파일로(위젯 인텐트와 같은 파일 · 같은 조정 규칙).
///
/// 새로고침: active 진입 · 60초마다(active 동안) · 당겨서 · 탭 표시(30초 안에 받았으면 건너뜀). background 에서는 멈춘다.
@MainActor
@Observable
package final class NowStore {
    @ObservationIgnored package let context: MobileContext

    // MARK: 팀 · 사람

    package private(set) var membership: NowMembership?
    /// 멤버십 조회가 "소속 없음"으로 확정됐다.
    package private(set) var hasNoTeam = false
    package private(set) var teamMembers: [TeamMemberStatus] = []
    /// 팀 상태를 받은 시각(nil = 아직 못 받음). 오늘·이번 주 경계 판정의 기준.
    package private(set) var teamFetchedAt: Date?
    package private(set) var directory: [PokeDirectoryRow] = []
    package private(set) var hasLoadedDirectory = false
    package private(set) var isRefreshing = false
    /// 한 줄 안내(불러오기 실패). 받아 둔 값은 지우지 않는다.
    package private(set) var notice: String?
    package private(set) var lastRefreshedAt: Date?

    // MARK: 주간 목표

    package private(set) var isSavingGoal = false
    package private(set) var goalNotice: String?

    // MARK: 할 일

    /// 코어 할 일 목록(파일 = App Group `todos.<uid>.json`). 로그아웃이면 `todos.local.json` 을 가리키고 동기화하지 않는다.
    package let todos: TodoListStore
    @ObservationIgnored package let todoSync: TodoSync
    @ObservationIgnored package let todoScheduler: NowPausableScheduler
    /// 눌러서 고치는 중인 줄(서버 병합 보호 대상).
    package private(set) var editingTodoID: UUID?
    /// "삭제됨 · 되돌리기" 토스트가 떠 있는 줄(5초, 보호 대상).
    package private(set) var undoTodoID: UUID?

    // MARK: 내부

    @ObservationIgnored private let timers: any TodoSyncScheduler
    @ObservationIgnored private let runsPeriodicRefresh: Bool
    @ObservationIgnored private var refreshTimer: (any TodoSyncCancellable)?
    @ObservationIgnored private var undoTimer: (any TodoSyncCancellable)?
    @ObservationIgnored package private(set) var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshRerun = false
    /// 목표를 저장할 때마다 +1. 그 전에 떠난 멤버십 조회가 옛 목표로 되돌리지 못하게 한다(맥 `teamGoalWriteGeneration`).
    @ObservationIgnored private var goalWriteSerial = 0
    @ObservationIgnored package private(set) var isActive = false
    /// 실제로 돈 새로고침 횟수(테스트).
    @ObservationIgnored package private(set) var refreshCount = 0
    #if DEBUG
    /// 데모 스크린샷 전용(`-AingCheckDemoNow undo`): 되돌리기 토스트를 5초 뒤에도 닫지 않는다.
    @ObservationIgnored package var demoHoldsUndo = false
    #endif

    package nonisolated static let refreshIntervalSeconds: Double = 60
    /// 탭을 다시 볼 때 이 초 안에 받았으면 새로고침을 건너뛴다.
    package nonisolated static let tabRefreshFreshSeconds: Double = 30
    package nonisolated static let goalRange: ClosedRange<Int> = 1...168
    /// 위젯 스냅샷에 싣는 할 일 상한(위젯은 3·6개만 그리지만 "외 N개"를 세려고 더 싣는다).
    package nonisolated static let widgetTodoLimit = 50

    /// 자리 API. 프로덕션 타이머(Task.sleep), 60초 주기는 실시간 러너가 벽시계 타이머를 쓰는 조립(프로덕션)에서만 켠다.
    package convenience init(context: MobileContext) {
        self.init(context: context, timers: NowTaskScheduler(), runsPeriodicRefresh: context.realtime.runsTimers)
    }

    /// 테스트 조립: 타이머를 손으로 미는 스케줄러를 꽂는다.
    package init(context: MobileContext, timers: any TodoSyncScheduler, runsPeriodicRefresh: Bool) {
        self.context = context
        self.timers = timers
        self.runsPeriodicRefresh = runsPeriodicRefresh
        let clock = context.clock
        let list = TodoListStore(fileURL: context.storage.todoFileURL(userID: nil), clock: { clock.now() })
        let scheduler = NowPausableScheduler(base: timers)
        todos = list
        todoScheduler = scheduler
        todoSync = TodoSync(
            list: list,
            transport: NowTodoSyncTransport(context: context),
            scheduler: scheduler,
            clock: { clock.now() }
        )
        list.onLocalChange = { [weak self] in self?.todoSync.noteLocalChange() }
        list.syncProtectedIDs = { [weak self] in self?.protectedTodoIDs ?? [] }
        observeTodos()
    }

    package var badgeCount: Int { 0 }

    // MARK: - 수명

    package func appDidBecomeActive() {
        guard context.session.isSignedIn, let userID = context.session.userID else { return }
        isActive = true
        todoScheduler.resume()
        prepareTodos(for: userID)
        refresh()
        armRefreshTimer()
    }

    package func appDidEnterBackground() {
        isActive = false
        refreshTimer?.cancel()
        refreshTimer = nil
        // 되돌리기 창은 닫는다(삭제는 이미 파일에 있다) — 돌아왔을 때 몇 시간 지난 토스트가 남지 않게.
        closeUndoWindow()
        // 고친 뒤 1.5초를 기다리던 변경은 지금 한 번 보낸다. 폰을 잠근 채 두면 다음 실행까지 맥에 닿지 않는다.
        if context.session.isSignedIn, todoSync.userID != nil, !todos.pendingIDs.isEmpty {
            todoSync.requestSync(.edit)
        }
        todoScheduler.pause()
    }

    package func reset() {
        isActive = false
        refreshTimer?.cancel()
        refreshTimer = nil
        refreshRerun = false
        membership = nil
        hasNoTeam = false
        teamMembers = []
        teamFetchedAt = nil
        directory = []
        hasLoadedDirectory = false
        isRefreshing = false
        notice = nil
        lastRefreshedAt = nil
        isSavingGoal = false
        goalNotice = nil
        editingTodoID = nil
        closeUndoWindow()
        todoScheduler.resume()
        // 앞 계정 목록을 메모리에 남기지 않는다. 파일은 지우지 않는다(아직 못 올린 변경 — 세션 스토어와 같은 관용).
        let localURL = context.storage.todoFileURL(userID: nil)
        NowTodoFileAccess.coordinated(at: localURL) {
            todoSync.switchAccount(userID: nil, fileURL: localURL)
        }
    }

    /// 탭이 화면에 나타났다(할 일 동기화 · 오래됐으면 새로고침).
    package func tabDidAppear() {
        guard isActive, context.session.isSignedIn else { return }
        todoSync.requestSync(.boardOpened)
        if let last = lastRefreshedAt, context.clock.now().timeIntervalSince(last) < Self.tabRefreshFreshSeconds { return }
        guard refreshTask == nil else { return }
        refresh()
    }

    // MARK: - 새로고침

    /// 한 번에 하나만 돈다(도는 중이면 끝난 뒤 한 번 더).
    package func refresh() {
        guard context.session.isSignedIn else { return }
        if refreshTask != nil {
            refreshRerun = true
            return
        }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.refreshRerun = false
                await self.performRefresh()
            } while self.refreshRerun && self.context.session.isSignedIn
            self.refreshTask = nil
            self.isRefreshing = false
        }
    }

    /// 당겨서 새로고침(끝날 때까지 기다린다). 할 일도 한 번 맞춘다.
    package func refreshNow() async {
        if context.session.isSignedIn, todoSync.userID != nil {
            todoSync.requestSync(.periodic)
        }
        refresh()
        await refreshTask?.value
    }

    private func armRefreshTimer() {
        refreshTimer?.cancel()
        refreshTimer = nil
        guard runsPeriodicRefresh, isActive else { return }
        refreshTimer = timers.schedule(after: Self.refreshIntervalSeconds) { [weak self] in
            guard let self, self.isActive else { return }
            self.refresh()
            self.armRefreshTimer()
        }
    }

    private func performRefresh() async {
        guard context.session.isSignedIn, let userID = context.session.userID else { return }
        let generation = context.generation
        let goalSerial = goalWriteSerial
        let service = context.service
        isRefreshing = true
        refreshCount += 1
        var failures: [Error] = []
        func stillCurrent() -> Bool {
            generation == context.generation && context.session.userID == userID
        }

        // ① 팀 소속(팀 id · 이름 · 1인당 목표)
        var teamID: String?
        do {
            let row = try await context.withMobileSessionRetry { session in
                try await service.fetchOwnMembership(accessToken: session.accessToken, userID: session.userID)
            }
            guard stillCurrent() else { return }
            if let row {
                var next = NowMembership(teamID: row.teamID, teamName: row.teamName, goalHours: row.goalHours, role: row.role)
                // 이 조회가 떠난 뒤 목표를 저장했다 — 조회가 싣고 온 옛 목표로 되돌리지 않는다.
                if goalSerial != goalWriteSerial, let current = membership, current.teamID == next.teamID {
                    next.goalHours = current.goalHours
                }
                if membership != next { membership = next }
                hasNoTeam = false
                teamID = row.teamID
            } else {
                membership = nil
                hasNoTeam = true
                teamMembers = []
                teamFetchedAt = nil
            }
        } catch {
            guard stillCurrent() else { return }
            failures.append(error)
            teamID = membership?.teamID
        }

        // ② 전체 디렉터리(다른 팀의 근무 여부 · 센터). 함수가 없는 서버면 조용히 빈 목록.
        do {
            let rows = try await context.withMobileSessionRetry { session in
                try await service.fetchPokeDirectory(accessToken: session.accessToken)
            }
            guard stillCurrent() else { return }
            directory = rows
            hasLoadedDirectory = true
        } catch {
            guard stillCurrent() else { return }
            if MobileDeviceRPC.isMissingFunction(error) {
                directory = []
                hasLoadedDirectory = true
            } else {
                failures.append(error)
            }
        }

        // ③ 우리 팀 상태(읽기 GET 넷 — 코어 서비스). 반영은 값으로만.
        if let teamID {
            let now = context.clock.now()
            do {
                let statuses = try await context.withMobileSessionRetry { session in
                    try await service.fetchTeamStatuses(accessToken: session.accessToken, teamID: teamID, now: now)
                }
                guard stillCurrent() else { return }
                teamMembers = statuses
                teamFetchedAt = now
            } catch {
                guard stillCurrent() else { return }
                failures.append(error)
            }
        }

        notice = Self.notice(for: failures)
        if failures.isEmpty { lastRefreshedAt = context.clock.now() }
        writeWidgetSnapshot()
    }

    /// 실패 목록 → 한 줄 안내. 취소만 있으면 nil.
    package static func notice(for failures: [Error]) -> String? {
        let meaningful = failures.filter { AuthErrorRules.classify($0) != .cancelled }
        guard !meaningful.isEmpty else { return nil }
        if meaningful.contains(where: { $0 is URLError }) { return NowText.networkFailed }
        return NowText.loadFailed
    }

    // MARK: - 주간 목표

    package var goalHours: Int { membership?.goalHours ?? TeamWeeklyGoal.defaultGoalHours }

    /// 팀 1인당 주간 목표 저장(1~168). 성공하면 true(시트를 닫는다), 실패하면 문구를 남기고 false(값을 둔 채 다시 시도).
    @discardableResult
    package func saveGoal(hours: Int) async -> Bool {
        guard Self.goalRange.contains(hours), !isSavingGoal, context.session.isSignedIn, membership != nil else { return false }
        isSavingGoal = true
        goalNotice = nil
        defer { isSavingGoal = false }
        let generation = context.generation
        let service = context.service
        do {
            let saved = try await context.withMobileSessionRetry { session in
                try await service.setTeamWeeklyGoal(accessToken: session.accessToken, goalHours: hours)
            }
            guard generation == context.generation else { return false }
            goalWriteSerial += 1
            if var next = membership {
                next.goalHours = saved
                membership = next
            }
            writeWidgetSnapshot()
            return true
        } catch {
            guard generation == context.generation else { return false }
            if AuthErrorRules.classify(error) == .cancelled { return false }
            goalNotice = error is URLError
                ? MobileSessionText.network
                : AuthErrorRules.message(for: error, fallback: NowText.goalFailed)
            return false
        }
    }

    package func clearGoalNotice() {
        goalNotice = nil
    }

    // MARK: - 파생 값

    package var hasLoadedTeam: Bool { teamFetchedAt != nil }

    package var myStatus: TeamMemberStatus? {
        guard let id = context.session.userID else { return nil }
        return teamMembers.first { $0.id == id }
    }

    /// 내 상태 카드(팀 상태를 한 번이라도 받았을 때만).
    package func myCard(now: Date) -> NowMyCard? {
        guard let fetchedAt = teamFetchedAt, membership != nil else { return nil }
        guard let me = myStatus else {
            // 한 번도 근무하지 않은 팀원은 work_statuses 행이 없다 — 0 으로 보인다(지어내지 않는다).
            return NowMyCard(isWorking: false, isStale: false, sessionStartedAt: nil, todaySeconds: 0, weekSeconds: 0, goalHours: goalHours)
        }
        let working = me.status == .working
        return NowMyCard(
            isWorking: working,
            isStale: working && NowTimeMath.isStale(me, now: now),
            sessionStartedAt: working ? me.currentSessionStartedAt : nil,
            todaySeconds: NowTimeMath.todaySeconds(me, fetchedAt: fetchedAt, now: now),
            weekSeconds: NowTimeMath.weekSeconds(me, fetchedAt: fetchedAt, now: now),
            goalHours: goalHours
        )
    }

    /// 지금 근무 중(나 제외): 우리 팀(경과 시간 · 오래 일한 순) 먼저, 그다음 다른 팀(근무 여부만 · 이름순).
    /// 다른 팀은 **우리 팀 상태를 받은 뒤에만** 가른다 — 모르는 채로 가르면 우리 팀원이 "다른 팀"에 시간 없이 섞인다.
    package func workingPeople(now: Date) -> [NowWorkingPerson] {
        let me = context.session.userID
        var directoryByID: [String: PokeDirectoryRow] = [:]
        for row in directory where directoryByID[row.userId] == nil { directoryByID[row.userId] = row }
        let teammates = teamMembers
            .filter { $0.id != me && $0.status == .working }
            .map { member -> NowWorkingPerson in
                let entry = directoryByID[member.id]
                return NowWorkingPerson(
                    id: member.id,
                    name: member.name,
                    avatarURL: member.avatarURL ?? entry?.avatarUrl.flatMap { URL(string: $0) },
                    center: entry?.center,
                    isTeammate: true,
                    startedAt: member.currentSessionStartedAt,
                    elapsedSeconds: member.currentDurationSeconds(now: now),
                    isStale: NowTimeMath.isStale(member, now: now)
                )
            }
            .sorted(by: Self.teammateOrder)
        guard hasLoadedTeam || hasNoTeam else { return teammates }
        let teamIDs = Set(teamMembers.map(\.id))
        var others: [NowWorkingPerson] = []
        for row in directory where row.isWorking && row.userId != me && !teamIDs.contains(row.userId) {
            let avatar: URL? = row.avatarUrl.flatMap { URL(string: $0) }
            others.append(NowWorkingPerson(
                id: row.userId, name: row.displayName, avatarURL: avatar,
                center: row.center, isTeammate: false, startedAt: nil, elapsedSeconds: nil, isStale: false
            ))
        }
        others.sort { lhs, rhs in lhs.name == rhs.name ? lhs.id < rhs.id : lhs.name < rhs.name }
        var seen: Set<String> = []
        return (teammates + others).filter { seen.insert($0.id).inserted }
    }

    private static func teammateOrder(_ lhs: NowWorkingPerson, _ rhs: NowWorkingPerson) -> Bool {
        switch (lhs.startedAt, rhs.startedAt) {
        case let (l?, r?) where l != r: return l < r
        case (nil, _?): return false
        case (_?, nil): return true
        default: return lhs.name == rhs.name ? lhs.id < rhs.id : lhs.name < rhs.name
        }
    }

    // MARK: - 할 일

    /// 지금 계정 파일로 동기화 중인가(아니면 편집을 받지 않는다 — 로그아웃 파일에 적지 않게).
    package var canEditTodos: Bool {
        context.session.isSignedIn && todoSync.userID != nil && todoSync.userID == context.session.userID
    }

    /// 오늘 목록(`TodoRules.visible` 순서): 7일 넘게 이월된 미완료는 `old` 로 따로(맥 "오래된 항목").
    package func todoRows() -> (main: [NowTodoRow], old: [NowTodoRow]) {
        let key = todos.todayKey
        var main: [NowTodoRow] = []
        var old: [NowTodoRow] = []
        for item in TodoRules.visible(todos.items, todayKey: key) {
            let days = TodoRules.carriedDays(originDayKey: item.originDayKey, todayKey: key)
            let row = NowTodoRow(
                id: item.id, title: item.title, isDone: item.isDone,
                carryBadge: TodoRules.carryBadge(days: days), carryOverDays: days
            )
            if TodoRules.isOld(item, todayKey: key) { old.append(row) } else { main.append(row) }
        }
        return (main, old)
    }

    package var remainingTodoCount: Int {
        let key = todos.todayKey
        return TodoRules.visible(todos.items, todayKey: key).filter { !$0.isDone }.count
    }

    @discardableResult
    package func addTodo(_ raw: String) -> Bool {
        guard canEditTodos else { return false }
        var added = false
        NowTodoFileAccess.coordinated(at: todos.fileURL) {
            added = todos.add(raw) != nil
        }
        return added
    }

    package func toggleTodo(_ id: UUID) {
        guard canEditTodos else { return }
        NowTodoFileAccess.coordinated(at: todos.fileURL) {
            todos.toggleDone(id)
        }
    }

    package func beginEditing(_ id: UUID) {
        guard canEditTodos, todos.items.contains(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        editingTodoID = id
        // 다른 줄을 고치다 넘어왔다면 그 줄의 보호는 끝났다(미룬 병합이 있으면 한 번 더 맞춘다).
        todos.syncProtectionDidEnd()
    }

    /// 수정 확정. 빈 제목·상한 초과는 코어가 무시한다(원래 문장이 남는다). 수정 모드는 어느 쪽이든 닫는다.
    package func commitEditing(_ id: UUID, title: String) {
        guard editingTodoID == id else { return }
        if canEditTodos {
            NowTodoFileAccess.coordinated(at: todos.fileURL) {
                todos.rename(id, to: title)
            }
        }
        editingTodoID = nil
        todos.syncProtectionDidEnd()
    }

    package func cancelEditing() {
        guard editingTodoID != nil else { return }
        editingTodoID = nil
        todos.syncProtectionDidEnd()
    }

    /// 밀어서 삭제 → 곧바로 톰스톤(파일에 남는다) + 5초 되돌리기 토스트.
    package func deleteTodo(_ id: UUID) {
        guard canEditTodos, todos.items.contains(where: { $0.id == id && $0.deletedAt == nil }) else { return }
        if editingTodoID == id { editingTodoID = nil }
        closeUndoWindow()
        NowTodoFileAccess.coordinated(at: todos.fileURL) {
            todos.delete(id)
        }
        undoTodoID = id
        undoTimer = timers.schedule(after: TodoRules.undoSeconds) { [weak self] in
            guard let self, self.undoTodoID == id else { return }
            #if DEBUG
            if self.demoHoldsUndo { return }
            #endif
            self.closeUndoWindow()
        }
    }

    /// 토스트의 되돌리기.
    package func undoDelete() {
        guard let id = undoTodoID else { return }
        closeUndoWindow()
        guard canEditTodos else { return }
        NowTodoFileAccess.coordinated(at: todos.fileURL) {
            todos.undoDelete(id)
        }
    }

    package func dismissUndo() {
        closeUndoWindow()
    }

    private func closeUndoWindow() {
        undoTimer?.cancel()
        undoTimer = nil
        guard undoTodoID != nil else { return }
        undoTodoID = nil
        todos.syncProtectionDidEnd()
    }

    private var protectedTodoIDs: Set<UUID> {
        Set([editingTodoID, undoTodoID].compactMap { $0 })
    }

    /// 계정 파일을 열고 동기화를 건다. 같은 계정이면 **파일을 다시 읽는다** — 앱이 뒤에 있는 동안 위젯이 체크했을 수 있다.
    private func prepareTodos(for userID: String) {
        let url = context.storage.todoFileURL(userID: userID)
        if todoSync.userID != userID || todos.fileURL != url {
            editingTodoID = nil
            closeUndoWindow()
            NowTodoFileAccess.coordinated(at: url) {
                todoSync.switchAccount(userID: userID, fileURL: url)
            }
        } else {
            NowTodoFileAccess.coordinated(at: url) {
                todos.reload()
            }
            if let editing = editingTodoID, !todos.items.contains(where: { $0.id == editing && $0.deletedAt == nil }) {
                editingTodoID = nil
            }
            todoSync.activate(userID: userID, reason: .wake)
        }
        writeWidgetSnapshot()
    }

    /// 목록이 바뀔 때마다(사용자 · 동기화 병합 · 다시 읽기) 위젯 스냅샷을 고친다.
    private func observeTodos() {
        withObservationTracking {
            _ = todos.items
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.writeWidgetSnapshot()
                self.observeTodos()
            }
        }
    }

    // MARK: - 위젯 스냅샷

    /// 받은 값으로 위젯 스냅샷을 고친다(같은 값이면 쓰기·새로고침 없음 — 쓰기 창구가 가른다). 아직 모르는 칸은 건드리지 않는다.
    package func writeWidgetSnapshot() {
        guard context.session.isSignedIn, let userID = context.session.userID else { return }
        let now = context.clock.now()
        let card = myCard(now: now)
        let noTeam = hasNoTeam
        let people = (hasLoadedTeam || hasNoTeam) ? workingPeople(now: now) : nil
        let previews = todoSync.userID == userID ? widgetTodoPreviews() : nil
        context.widgetSnapshots.update { snapshot in
            if let card {
                snapshot.me = WidgetSnapshot.Me(
                    working: card.isWorking,
                    // 신호가 끊긴 세션은 위젯이 스스로 세지 않게 시작 시각을 싣지 않는다(마지막 신호에서 멈춘 값만).
                    sessionStartedAt: card.isStale ? nil : card.sessionStartedAt,
                    todaySeconds: card.todaySeconds,
                    weekSeconds: card.weekSeconds,
                    goalHours: card.goalHours
                )
            } else if noTeam {
                snapshot.me = nil
            }
            if let people {
                snapshot.working = people.map {
                    WidgetSnapshot.WorkingPerson(name: $0.name, center: $0.center, teammate: $0.isTeammate, startedAt: $0.isTeammate ? $0.startedAt : nil)
                }
            }
            if let previews {
                snapshot.todosPreview = previews
            }
        }
    }

    private func widgetTodoPreviews() -> [WidgetSnapshot.TodoPreview] {
        let rows = todoRows()
        return (rows.main + rows.old).prefix(Self.widgetTodoLimit).map {
            WidgetSnapshot.TodoPreview(id: $0.id.uuidString.lowercased(), title: $0.title, isCompleted: $0.isDone, carryOverDays: $0.carryOverDays)
        }
    }
}
