// 원본: Sources/CheckMobileKit/Now/NowStore.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.now

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.fetchOwnMembership
import com.yehsung.aingcheck.core.net.fetchPokeDirectory
import com.yehsung.aingcheck.core.net.fetchTeamStatuses
import com.yehsung.aingcheck.core.net.isMissingDeviceFunction
import com.yehsung.aingcheck.core.net.setTeamWeeklyGoal
import com.yehsung.aingcheck.core.rules.todo.TodoRules
import com.yehsung.aingcheck.core.rules.text.StatusMessage
import com.yehsung.aingcheck.core.session.SessionText
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.session.team.TeamJoinStore
import com.yehsung.aingcheck.core.stores.messages.SwiftStrings
import com.yehsung.aingcheck.core.stores.now.todo.TodoListStore
import com.yehsung.aingcheck.core.stores.now.todo.TodoSync
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncCancellable
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncCoroutineScheduler
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncReason
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncScheduler
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryRow
import com.yehsung.aingcheck.core.wire.models.TeamMemberStatus
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.core.wire.models.WorkStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * 폰 근무(0.3.51 — Swift `NowStorePhoneWork.swift`, W2-f 몫)가 이 스토어에 붙는 문. 생존 신호의 간격·왕복은 그쪽이 정한다.
 * Swift 는 같은 클래스의 확장이라 `appDidBecomeActive` · 60초 주기 · `reset` 에서 바로 불렀다 — 여기서는 조립이 이 문을 잇는다.
 */
interface NowPhoneWorkLink {
    /** 앱이 앞으로 왔다(Swift `touchPhoneWorkIfNeeded(minimumInterval: phoneTouchOnActiveSeconds)`). */
    fun appDidBecomeActive()

    /** active 동안 60초 주기 — 폰이 연 근무일 때만 생존 신호(Swift `phoneTouchWhileActiveSeconds`). */
    fun periodicTick()

    /** 로그아웃(Swift `resetPhoneWork` 의 왕복 몫 — 값 칸은 이 스토어가 비운다). */
    fun reset()
}

/**
 * 위젯 스냅숏 쓰기(Swift `writeWidgetSnapshot` · `touchWidgetSnapshot` — 쓰는 주체는 지금 탭 하나, 쓰기 창구는 W2-f 위젯 갈래).
 * 이 스토어는 **언제** 쓸지만 알린다(로그아웃이면 부르지 않는다). 무엇을 쓸지는 이 스토어의 값([NowStore.myCard] · [NowStore.workingPeople] ·
 * 할 일 미리보기 [NowStore.widgetTodoPreviewRows] — 지금 계정 파일이 아니면 null 이라 그 칸을 건드리지 않는다)에서 그쪽이 만든다.
 * 위젯의 할 일 체크는 같은 파일([NowStore.todoStorage])을 [NowTodoFileAccess] 안에서 읽고-고치고-쓴다.
 */
interface NowWidgetSink {
    /** 받은 값으로 스냅숏을 고친다. `deferWhileRefreshing` 이면 [NowStore.shouldDeferWidgetWrite] 가 참일 때 미룬다. */
    fun write(deferWhileRefreshing: Boolean)

    /** 성공한 새로고침 뒤 generatedAt 만 옮긴다(값이 같아 쓰기 창구가 파일을 건드리지 않은 경우 — now-verify R4). */
    fun touch(at: SwiftDate)
}

/**
 * 지금 탭 스토어(SPEC-ios §3.2 · §4 스냅샷 쓰기).
 *
 * 자리 API: 생성(네트워크 없음) · [appDidBecomeActive] · [appDidEnterBackground] · [reset] · [badgeCount](0).
 *
 * 데이터(읽기 — 폰 금지 호출 없음, C§4 #13)
 * - 내 상태·우리 팀: `fetchOwnMembership` + `fetchTeamStatuses`(GET 넷)를 받아 **값으로만** 계산한다. 맥 스토어의 팀 상태 반영
 *   (세션 흡수 · 소유권 · 버려진 세션 마감)은 가져오지 않는다 — 그 경로가 근무 쓰기로 샌다(ios-inventory R2).
 * - 근무 시작·종료·생존 신호는 폰 근무 RPC 셋만(W2-f — [NowPhoneWorkLink]). E-1 은 읽기만 한다(C§3.2).
 * - 다른 팀: `app_user_directory` 의 근무 여부·센터만.
 * - 주간 목표 쓰기: `set_team_weekly_goal`(팀 전체 1인당 목표 — 팀원 누구나).
 *
 * - 할 일: 엔진 [TodoListStore] · [TodoSync](core/stores …/now/todo)를 [NowTodoStorage] 의 파일로(위젯 동작과 같은 파일 · 같은 조정 — [NowTodoFileAccess]).
 *
 * 새로고침: active 진입 · 60초마다(active 동안, [runsPeriodicRefresh]) · 당겨서 · 탭 표시(30초 안에 받았으면 건너뜀). background 에서는 멈춘다.
 */
class NowStore(
    val context: SessionContext,
    parentScope: CoroutineScope,
    /** 할 일 파일 자리(조립이 앱 전용 폴더 · 파일 시스템을 넘긴다 — Swift `context.storage`). */
    val todoStorage: NowTodoStorage,
    /** 60초 주기는 실시간 러너가 벽시계 타이머를 쓰는 조립(프로덕션)에서만 켠다(Swift `context.realtime.runsTimers`). */
    private val runsPeriodicRefresh: Boolean = false,
    /** 타이머(60초 새로고침 · 5초 되돌리기 · 할 일 디바운스/주기). null = 이 스토어 스코프의 코루틴 타이머. 시험은 손으로 미는 것을 꽂는다. */
    timers: TodoSyncScheduler? = null,
) {
    val scope: CoroutineScope = CoroutineScope(parentScope.coroutineContext + SupervisorJob(parentScope.coroutineContext[Job]))
    private val timers: TodoSyncScheduler = timers ?: TodoSyncCoroutineScheduler(scope)

    var phoneWork: NowPhoneWorkLink? = null
    var widgetSink: NowWidgetSink? = null

    // ---------------------------------------------------------------- 팀 · 사람

    var membership: NowMembership? by mutableStateOf(null)
        private set

    /** 멤버십 조회가 "소속 없음"으로 확정됐다. */
    var hasNoTeam: Boolean by mutableStateOf(false)
        private set

    /** 방금 팀에 들어갔는데(합류·생성) 아직 소속을 못 읽었다 — 그 한 왕복 동안은 무소속 카드도, 실패 줄도 아니고 **스피너**다. */
    var isSettlingTeam: Boolean by mutableStateOf(false)
        private set
    var teamMembers: List<TeamMemberStatus> by mutableStateOf(emptyList())
        private set

    /** 팀 상태를 받은 시각(null = 아직 못 받음). 끊김 판정도 이 시각에 한다([presenceJudgedAt]). */
    var teamFetchedAt: SwiftDate? by mutableStateOf(null)
        private set

    /** 받아 둔 팀 상태 뒤로 팀 상태 요청이 실패했다(오프라인 · 5xx). 이때만 끊김을 화면 시각으로 판정한다. */
    var teamStatusFailedSinceFetch: Boolean by mutableStateOf(false)
        private set

    /** 이 세대에서 새로고침이 한 번이라도 끝났다(성공 · 실패 무관). */
    var hasFinishedRefreshAttempt: Boolean by mutableStateOf(false)
        private set
    var directory: List<PokeDirectoryRow> by mutableStateOf(emptyList())
        private set
    var hasLoadedDirectory: Boolean by mutableStateOf(false)
        private set
    var isRefreshing: Boolean by mutableStateOf(false)
        private set

    /** 한 줄 안내(불러오기 실패). 받아 둔 값은 지우지 않는다. */
    var notice: String? by mutableStateOf(null)
        private set
    var lastRefreshedAt: SwiftDate? by mutableStateOf(null)
        private set

    // ---------------------------------------------------------------- 폰 근무 값(왕복은 W2-f — Swift 는 이 클래스의 칸이다)

    /** 서버에 폰 근무 함수가 있다(PGRST202 를 받으면 이 세대 동안 false — 버튼을 숨긴다). */
    var phoneWorkAvailable: Boolean by mutableStateOf(true)
    var isWorkBusy: Boolean by mutableStateOf(false)
    var workNotice: String? by mutableStateOf(null)

    /** 폰 RPC 가 알려 준 내 열린 세션. 근무 중이 아니면 null. */
    var phoneSession: NowPhoneSession? by mutableStateOf(null)

    // ---------------------------------------------------------------- 주간 목표

    var isSavingGoal: Boolean by mutableStateOf(false)
        private set
    var goalNotice: String? by mutableStateOf(null)
        private set

    /** 무소속 카드의 팀 합류·만들기(가입 화면과 같은 왕복·가드·문구 — W2-a `TeamJoinStore`). */
    val teamJoin: TeamJoinStore = TeamJoinStore(context)

    // ---------------------------------------------------------------- 할 일

    /** 할 일 목록(파일 = `todos.<uid>.json`). 로그아웃이면 `todos.local.json` 을 가리키고 동기화하지 않는다. */
    val todos: TodoListStore = TodoListStore(todoStorage.todoFilePath(null), todoStorage.files, clock = { context.clock.now().timeIntervalSince1970 })

    /** 엔진의 예약을 background 동안 막는 타이머(Swift `todoScheduler`). */
    val todoScheduler: NowPausableScheduler = NowPausableScheduler(this.timers)
    val todoSync: TodoSync = TodoSync(
        list = todos,
        transport = NowTodoSyncTransport(context),
        scheduler = todoScheduler,
        scope = scope,
        clock = { context.clock.now().timeIntervalSince1970 },
    )

    /** 눌러서 고치는 중인 줄(서버 병합 보호 대상). */
    var editingTodoID: String? by mutableStateOf(null)
        private set

    /** "삭제됨 · 되돌리기" 토스트가 떠 있는 줄(5초, 보호 대상). */
    var undoTodoID: String? by mutableStateOf(null)
        private set

    // ---------------------------------------------------------------- 내부

    var refreshTask: Job? = null
        private set
    private var refreshRerun = false
    private var refreshTimer: TodoSyncCancellable? = null
    private var undoTimer: TodoSyncCancellable? = null

    /** 목표를 저장할 때마다 +1. 그 전에 떠난 멤버십 조회가 옛 목표로 되돌리지 못하게 한다. */
    private var goalWriteSerial = 0

    /** 팀이 정해질 때마다 +1. 그 전에 떠난 멤버십 조회가 **"소속 없음"으로 되돌리지 못하게** 한다. */
    private var teamSettleSerial = 0
    var isActive: Boolean = false
        private set

    /** 실제로 돈 새로고침 횟수(시험). */
    var refreshCount: Int = 0
        private set

    init {
        todos.onLocalChange = { todoSync.noteLocalChange() }
        todos.syncProtectedIDs = { protectedTodoIDs }
        // 목록이 바뀔 때마다(사용자 · 동기화 병합 · 다시 읽기) 위젯 스냅숏을 고친다(Swift `observeTodos`).
        todos.onItemsChanged = { writeWidget(deferWhileRefreshing = true) }
        teamJoin.onTeamSettled = { adoptSettledTeam() }
    }

    /**
     * 무소속 카드에서 팀이 정해졌다. **역할·팀 상태는 서버에서 다시 읽는다**(join_team/create_team 은 역할을 돌려주지 않는다).
     * 그동안 무소속 카드는 내린다([isSettlingTeam] → 스피너). 재로그인은 요구하지 않는다.
     */
    private fun adoptSettledTeam() {
        teamSettleSerial += 1
        isSettlingTeam = true
        hasNoTeam = false
        teamMembers = emptyList()
        teamFetchedAt = null
        teamStatusFailedSinceFetch = false
        refresh()
        // 팀 이름·역할은 다른 탭(나 탭 설정 · 머리)도 읽는다 — 로그인 직후와 같은 길로 한 번 채운다.
        scope.launch { context.sessionStore.refreshProfile() }
    }

    val badgeCount: Int get() = 0

    // ---------------------------------------------------------------- 수명

    fun appDidBecomeActive() {
        val userID = context.sessionStore.userID
        if (!context.sessionStore.isSignedIn || userID == null) return
        isActive = true
        todoScheduler.resume()
        // 새로고침을 먼저 띄운다 — 할 일 준비가 부르는 스냅샷 쓰기가 "응답을 기다리는 중"을 알아 낡은 팀 상태로 쓰지 않게.
        refresh()
        prepareTodos(userID)
        armRefreshTimer()
        // 앱이 앞으로 왔다 = 폰 근무의 생존 신호(근무 중이 아니어도 보낸다 — 응답이 출처와 자리비움 안내를 알려 준다).
        phoneWork?.appDidBecomeActive()
    }

    fun appDidEnterBackground() {
        isActive = false
        refreshTimer?.cancel()
        refreshTimer = null
        // 되돌리기 창은 닫는다(삭제는 이미 파일에 있다) — 돌아왔을 때 몇 시간 지난 토스트가 남지 않게.
        closeUndoWindow()
        // 고친 뒤 1.5초를 기다리던 변경은 지금 한 번 보낸다. 폰을 잠근 채 두면 다음 실행까지 맥에 닿지 않는다.
        if (context.sessionStore.isSignedIn && todoSync.userID != null && todos.pendingIDs.isNotEmpty()) {
            todoSync.requestSync(TodoSyncReason.edit)
        }
        todoScheduler.pause()
    }

    fun reset() {
        isActive = false
        refreshTimer?.cancel()
        refreshTimer = null
        refreshRerun = false
        membership = null
        hasNoTeam = false
        isSettlingTeam = false
        teamSettleSerial += 1
        teamJoin.reset()
        teamMembers = emptyList()
        teamFetchedAt = null
        teamStatusFailedSinceFetch = false
        hasFinishedRefreshAttempt = false
        directory = emptyList()
        hasLoadedDirectory = false
        isRefreshing = false
        notice = null
        lastRefreshedAt = null
        isSavingGoal = false
        goalNotice = null
        resetPhoneWork()
        editingTodoID = null
        closeUndoWindow()
        todoScheduler.resume()
        // 앞 계정 목록을 메모리에 남기지 않는다. 파일은 지우지 않는다(아직 못 올린 변경 — 세션 스토어와 같은 관용).
        val localPath = todoStorage.todoFilePath(null)
        NowTodoFileAccess.coordinated(localPath) { todoSync.switchAccount(null, localPath) }
    }

    private fun resetPhoneWork() {
        phoneWork?.reset()
        phoneWorkAvailable = true
        isWorkBusy = false
        workNotice = null
        phoneSession = null
    }

    /** 탭이 화면에 나타났다(할 일 동기화 · 오래됐으면 새로고침). */
    fun tabDidAppear() {
        if (!isActive || !context.sessionStore.isSignedIn) return
        todoSync.requestSync(TodoSyncReason.boardOpened)
        val last = lastRefreshedAt
        if (last != null && context.clock.now().timeIntervalSince(last) < tabRefreshFreshSeconds) return
        if (refreshTask != null) return
        refresh()
    }

    // ---------------------------------------------------------------- 새로고침

    /** 한 번에 하나만 돈다(도는 중이면 끝난 뒤 한 번 더). */
    fun refresh() {
        if (!context.sessionStore.isSignedIn) return
        if (refreshTask != null) {
            refreshRerun = true
            return
        }
        val job = scope.launch(start = CoroutineStart.LAZY) {
            do {
                refreshRerun = false
                performRefresh()
            } while (refreshRerun && context.sessionStore.isSignedIn)
            refreshTask = null
            isRefreshing = false
        }
        refreshTask = job
        job.start()
    }

    /** 당겨서 새로고침(끝날 때까지 기다린다). 할 일도 한 번 맞춘다. */
    suspend fun refreshNow() {
        if (context.sessionStore.isSignedIn && todoSync.userID != null) todoSync.requestSync(TodoSyncReason.periodic)
        refresh()
        refreshTask?.join()
    }

    private fun armRefreshTimer() {
        refreshTimer?.cancel()
        refreshTimer = null
        if (!runsPeriodicRefresh || !isActive) return
        refreshTimer = timers.schedule(refreshIntervalSeconds) {
            if (isActive) {
                refresh()
                // 앱을 켜 둔 채 오래 두어도 확인 알림이 오지 않게 — 폰이 연 근무일 때만(간격은 그쪽이 정한다).
                if (phoneSession?.origin == NowWorkOrigin.phone) phoneWork?.periodicTick()
                armRefreshTimer()
            }
        }
    }

    private suspend fun performRefresh() {
        val userID = context.sessionStore.userID
        if (!context.sessionStore.isSignedIn || userID == null) return
        val generation = context.generation
        val goalSerial = goalWriteSerial
        val settleSerial = teamSettleSerial
        val service = context.service
        isRefreshing = true
        refreshCount += 1
        val failures = ArrayList<Throwable>()
        fun stillCurrent(): Boolean = generation == context.generation && context.sessionStore.userID == userID

        // ① 팀 소속(팀 id · 이름 · 1인당 목표)
        var teamID: String? = null
        try {
            val row = context.withSessionRetry { session -> service.fetchOwnMembership(session.accessToken, session.userID) }
            if (!stillCurrent()) return
            if (row != null) {
                var next = NowMembership(row.teamID, row.teamName, row.goalHours.toInt(), row.role)
                // 이 조회가 떠난 뒤 목표를 저장했다 — 조회가 싣고 온 옛 목표로 되돌리지 않는다.
                val current = membership
                if (goalSerial != goalWriteSerial && current != null && current.teamID == next.teamID) {
                    next = next.copy(goalHours = current.goalHours)
                }
                if (membership != next) membership = next
                hasNoTeam = false
                isSettlingTeam = false
                teamID = row.teamID
            } else if (settleSerial == teamSettleSerial) {
                membership = null
                hasNoTeam = true
                isSettlingTeam = false
                teamMembers = emptyList()
                teamFetchedAt = null
                teamStatusFailedSinceFetch = false
            }
            // 그 밖: 이 조회는 **합류가 끝나기 전에** 떠났다 — 싣고 온 "소속 없음"은 이미 지난 사실이라 되돌리지 않는다.
        } catch (error: Throwable) {
            if (!stillCurrent()) return
            failures += error
            teamID = membership?.teamID
        }

        // ② 전체 디렉터리(다른 팀의 근무 여부 · 센터). 함수가 없는 서버면 조용히 빈 목록.
        try {
            val rows = context.withSessionRetry { session -> service.fetchPokeDirectory(session.accessToken) }
            if (!stillCurrent()) return
            directory = rows
            hasLoadedDirectory = true
        } catch (error: Throwable) {
            if (!stillCurrent()) return
            if (isMissingDeviceFunction(error)) {
                directory = emptyList()
                hasLoadedDirectory = true
            } else {
                failures += error
            }
        }

        // ③ 우리 팀 상태(읽기 GET 넷 — 코어 서비스). 반영은 값으로만.
        val team = teamID
        if (team != null) {
            val now = context.clock.now()
            try {
                val statuses = context.withSessionRetry { session -> service.fetchTeamStatuses(session.accessToken, team, now) }
                if (!stillCurrent()) return
                teamMembers = statuses
                teamFetchedAt = now
                teamStatusFailedSinceFetch = false
            } catch (error: Throwable) {
                if (!stillCurrent()) return
                failures += error
                if (AuthErrorRules.classify(error) != AuthErrorDisposition.cancelled) teamStatusFailedSinceFetch = true
            }
        }

        notice = notice(failures)
        hasFinishedRefreshAttempt = true
        val finishedAt = context.clock.now()
        if (failures.isEmpty()) lastRefreshedAt = finishedAt
        writeWidget(deferWhileRefreshing = false)
        if (failures.isEmpty()) widgetSink?.touch(finishedAt)
    }

    // ---------------------------------------------------------------- 주간 목표

    val goalHours: Int get() = membership?.goalHours ?: TeamWeeklyGoal.defaultGoalHours.toInt()

    /** 팀 1인당 주간 목표 저장(1~168). 성공하면 true, 실패하면 문구를 남기고 false. */
    suspend fun saveGoal(hours: Int): Boolean {
        if (hours !in goalRange || isSavingGoal || !context.sessionStore.isSignedIn || membership == null) return false
        isSavingGoal = true
        goalNotice = null
        try {
            val generation = context.generation
            val service = context.service
            return try {
                val saved = context.withSessionRetry { session -> service.setTeamWeeklyGoal(session.accessToken, hours.toLong()) }
                if (generation != context.generation) return false
                goalWriteSerial += 1
                membership?.let { membership = it.copy(goalHours = saved.toInt()) }
                writeWidget(deferWhileRefreshing = true)
                true
            } catch (error: Throwable) {
                if (generation != context.generation) return false
                if (AuthErrorRules.classify(error) == AuthErrorDisposition.cancelled) return false
                goalNotice = if (AuthErrorRules.isTransport(error)) SessionText.network else AuthErrorRules.message(error, NowText.goalFailed)
                false
            }
        } finally {
            isSavingGoal = false
        }
    }

    fun clearGoalNotice() {
        goalNotice = null
    }

    // ---------------------------------------------------------------- 파생 값

    val hasLoadedTeam: Boolean get() = teamFetchedAt != null

    val teamLoadState: NowLoadState
        get() {
            if (isSettlingTeam) return NowLoadState.loading
            if (hasNoTeam || hasLoadedTeam) return NowLoadState.loaded
            return if (hasFinishedRefreshAttempt) NowLoadState.failed else NowLoadState.loading
        }

    /** "지금 근무 중" 자리. 소속이 없으면 디렉터리가 전부라 디렉터리를 받아야 받음 — 못 받았는데 "근무 중인 사람이 없어요"라고 하지 않는다. */
    val workingLoadState: NowLoadState
        get() {
            if (isSettlingTeam) return NowLoadState.loading
            if (hasLoadedTeam || (hasNoTeam && hasLoadedDirectory)) return NowLoadState.loaded
            return if (hasFinishedRefreshAttempt) NowLoadState.failed else NowLoadState.loading
        }

    /**
     * 신호 끊김(stale) 판정 시각. 받은 팀 상태는 **받은 시각에 판정하고 다음 응답까지 그 판정을 유지**한다(now-verify R1 · R2).
     * 그 뒤 팀 상태 요청이 **실패**했으면 화면 시각으로 판정한다.
     */
    fun presenceJudgedAt(now: SwiftDate): SwiftDate {
        val fetchedAt = teamFetchedAt
        if (fetchedAt == null || teamStatusFailedSinceFetch) return now
        return minOf(now, fetchedAt)
    }

    val myStatus: TeamMemberStatus?
        get() {
            val id = context.sessionStore.userID ?: return null
            return teamMembers.firstOrNull { it.id == id }
        }

    /** 내 열린 근무의 출처(Swift `NowStorePhoneWork.workOrigin(of:)` — 이 스토어의 칸만 읽는 순수 판정). */
    fun workOrigin(me: TeamMemberStatus): NowWorkOrigin {
        if (me.status != WorkStatus.working) return NowWorkOrigin.unknown
        if (!phoneWorkAvailable) return NowWorkOrigin.mac
        val session = phoneSession ?: return NowWorkOrigin.unknown
        val open = (me.openSession?.id ?: me.activeSessionID)?.lowercase() ?: return NowWorkOrigin.unknown
        return if (open == session.id) session.origin else NowWorkOrigin.unknown
    }

    /** 내 상태 카드(팀 상태를 한 번이라도 받았을 때만). */
    fun myCard(now: SwiftDate): NowMyCard? {
        val fetchedAt = teamFetchedAt ?: return null
        if (membership == null) return null
        // 한 번도 근무하지 않은 팀원은 work_statuses 행이 없다 — 0 으로 보인다(지어내지 않는다).
        val me = myStatus ?: return NowMyCard(false, false, null, 0, 0, goalHours)
        val working = me.status == WorkStatus.working
        val judgedAt = presenceJudgedAt(now)
        return NowMyCard(
            isWorking = working,
            isStale = working && NowTimeMath.isStale(me, judgedAt),
            sessionStartedAt = if (working) me.currentSessionStartedAt else null,
            todaySeconds = NowTimeMath.todaySeconds(me, fetchedAt, now, judgedAt),
            weekSeconds = NowTimeMath.weekSeconds(me, fetchedAt, now, judgedAt),
            goalHours = goalHours,
            origin = if (working) workOrigin(me) else NowWorkOrigin.unknown,
        )
    }

    /**
     * 지금 근무 중(나 제외): 우리 팀(경과 시간 · 오래 일한 순) 먼저, 그다음 다른 팀(근무 여부만 · 이름순 — Swift String `<`).
     * 다른 팀은 **우리 팀 상태를 받은 뒤에만** 가른다.
     */
    fun workingPeople(now: SwiftDate): List<NowWorkingPerson> {
        val me = context.sessionStore.userID
        val judgedAt = presenceJudgedAt(now)
        val directoryByID = LinkedHashMap<String, PokeDirectoryRow>()
        for (row in directory) if (row.userId !in directoryByID) directoryByID[row.userId] = row
        val teammates = teamMembers
            .filter { it.id != me && it.status == WorkStatus.working }
            .map { member ->
                val entry = directoryByID[member.id]
                NowWorkingPerson(
                    id = member.id,
                    name = member.name,
                    avatarURL = member.avatarURL ?: SwiftURL.parse(entry?.avatarUrl),
                    center = entry?.center,
                    isTeammate = true,
                    startedAt = member.currentSessionStartedAt,
                    elapsedSeconds = NowTimeMath.elapsedSeconds(member, now, judgedAt),
                    isStale = NowTimeMath.isStale(member, judgedAt),
                    lastSeenAt = member.lastSeenAt ?: member.updatedAt,
                    // 팀원의 상태메시지도 사람 목록에서 찾는다(팀 상태 조회는 이 칸을 싣지 않는다 — 옛 서버 42703 회피).
                    statusMessage = StatusMessage.display(entry?.statusMessage),
                )
            }
            .sortedWith(::teammateOrder)
        if (!(hasLoadedTeam || hasNoTeam)) return teammates
        val teamIDs = teamMembers.map { it.id }.toSet()
        val others = directory
            .filter { it.isWorking && it.userId != me && it.userId !in teamIDs }
            .map { row ->
                NowWorkingPerson(
                    id = row.userId, name = row.displayName, avatarURL = SwiftURL.parse(row.avatarUrl),
                    center = row.center, isTeammate = false, startedAt = null, elapsedSeconds = null, isStale = false,
                    statusMessage = StatusMessage.display(row.statusMessage),
                )
            }
            .sortedWith(::nameThenIDOrder)
        val seen = HashSet<String>()
        return (teammates + others).filter { seen.add(it.id) }
    }

    private fun teammateOrder(lhs: NowWorkingPerson, rhs: NowWorkingPerson): Int {
        val l = lhs.startedAt
        val r = rhs.startedAt
        return when {
            l != null && r != null && l != r -> l.compareTo(r)
            l == null && r != null -> 1
            l != null && r == null -> -1
            else -> nameThenIDOrder(lhs, rhs)
        }
    }

    /**
     * Swift `lhs.name == rhs.name ? lhs.id < rhs.id : lhs.name < rhs.name`. Swift String `==` 은 **정준 동치**다(NFC·NFD 만 다른 같은 이름도 같다)
     * — Kotlin `==`(UTF-16 같음)로 가르면 그런 이름 둘이 이름 비교(0)로 빠져 입력 순서가 남는다. 같음 판정도 [SwiftStrings.compare] 로 한다.
     */
    private fun nameThenIDOrder(lhs: NowWorkingPerson, rhs: NowWorkingPerson): Int {
        val byName = SwiftStrings.compare(lhs.name, rhs.name)
        return if (byName == 0) SwiftStrings.compare(lhs.id, rhs.id) else byName
    }

    // ---------------------------------------------------------------- 할 일

    /** 지금 계정 파일로 동기화 중인가(아니면 편집을 받지 않는다 — 로그아웃 파일에 적지 않게). */
    val canEditTodos: Boolean
        get() = context.sessionStore.isSignedIn && todoSync.userID != null && todoSync.userID == context.sessionStore.userID

    /** 오늘 목록(`TodoRules.visible` 순서): 7일 넘게 이월된 미완료는 `old` 로 따로(맥 "오래된 항목"). */
    fun todoRows(): NowTodoRows {
        val key = todos.todayKey
        val main = ArrayList<NowTodoRow>()
        val old = ArrayList<NowTodoRow>()
        for (item in TodoRules.visible(todos.items, key)) {
            val days = TodoRules.carriedDays(item.originDayKey, key)
            val row = NowTodoRow(item.id, item.title, item.isDone, TodoRules.carryBadge(days), days)
            if (TodoRules.isOld(item, key)) old += row else main += row
        }
        return NowTodoRows(main, old)
    }

    val remainingTodoCount: Int
        get() = TodoRules.visible(todos.items, todos.todayKey).count { !it.isDone }

    fun addTodo(raw: String): Boolean {
        if (!canEditTodos) return false
        return NowTodoFileAccess.coordinated(todos.filePath) { todos.add(raw) != null }
    }

    fun toggleTodo(id: String) {
        if (!canEditTodos) return
        NowTodoFileAccess.coordinated(todos.filePath) { todos.toggleDone(id) }
    }

    fun beginEditing(id: String) {
        if (!canEditTodos || todos.items.none { it.id == id && it.deletedAt == null }) return
        editingTodoID = id
        // 다른 줄을 고치다 넘어왔다면 그 줄의 보호는 끝났다(미룬 병합이 있으면 한 번 더 맞춘다).
        todos.syncProtectionDidEnd()
    }

    /** 수정 확정. 빈 제목·상한 초과는 엔진이 무시한다(원래 문장이 남는다). 수정 모드는 어느 쪽이든 닫는다. */
    fun commitEditing(id: String, title: String) {
        if (editingTodoID != id) return
        if (canEditTodos) NowTodoFileAccess.coordinated(todos.filePath) { todos.rename(id, title) }
        editingTodoID = null
        todos.syncProtectionDidEnd()
    }

    fun cancelEditing() {
        if (editingTodoID == null) return
        editingTodoID = null
        todos.syncProtectionDidEnd()
    }

    /** 밀어서 삭제 → 곧바로 톰스톤(파일에 남는다) + 5초 되돌리기 토스트. */
    fun deleteTodo(id: String) {
        if (!canEditTodos || todos.items.none { it.id == id && it.deletedAt == null }) return
        if (editingTodoID == id) editingTodoID = null
        closeUndoWindow()
        NowTodoFileAccess.coordinated(todos.filePath) { todos.delete(id) }
        undoTodoID = id
        undoTimer = timers.schedule(TodoRules.undoSeconds) {
            if (undoTodoID == id) closeUndoWindow()
        }
    }

    /** 토스트의 되돌리기. */
    fun undoDelete() {
        val id = undoTodoID ?: return
        closeUndoWindow()
        if (!canEditTodos) return
        NowTodoFileAccess.coordinated(todos.filePath) { todos.undoDelete(id) }
    }

    fun dismissUndo() {
        closeUndoWindow()
    }

    private fun closeUndoWindow() {
        undoTimer?.cancel()
        undoTimer = null
        if (undoTodoID == null) return
        undoTodoID = null
        todos.syncProtectionDidEnd()
    }

    private val protectedTodoIDs: Set<String>
        get() = setOfNotNull(editingTodoID, undoTodoID)

    /** 계정 파일을 열고 동기화를 건다. 같은 계정이면 **파일을 다시 읽는다** — 앱이 뒤에 있는 동안 위젯이 체크했을 수 있다. */
    private fun prepareTodos(userID: String) {
        val path = todoStorage.todoFilePath(userID)
        if (todoSync.userID != userID || todos.filePath != path) {
            editingTodoID = null
            closeUndoWindow()
            NowTodoFileAccess.coordinated(path) { todoSync.switchAccount(userID, path) }
        } else {
            NowTodoFileAccess.coordinated(path) { todos.reload() }
            val editing = editingTodoID
            if (editing != null && todos.items.none { it.id == editing && it.deletedAt == null }) editingTodoID = null
            todoSync.activate(userID, TodoSyncReason.wake)
        }
        writeWidget(deferWhileRefreshing = true)
    }

    /**
     * 위젯 스냅숏의 할 일 미리보기 줄(Swift `widgetTodoPreviews` — 쓰기는 W2-f [NowWidgetSink]). **지금 계정 파일일 때만**(로그인 직후 active 전,
     * 로그아웃 파일을 든 채면 null — 그 칸을 건드리지 않는다). 위젯은 3·6개만 그리지만 "외 N개"를 세려고 [widgetTodoLimit] 개까지 싣는다.
     */
    fun widgetTodoPreviewRows(): List<NowTodoRow>? {
        val userID = context.sessionStore.userID ?: return null
        if (todoSync.userID != userID) return null
        val rows = todoRows()
        return (rows.main + rows.old).take(widgetTodoLimit)
    }

    // ---------------------------------------------------------------- 위젯 스냅숏 판정(쓰기는 W2-f)

    /** 위젯 쓰기 창구를 부른다. 로그아웃이면 부르지 않는다 — 로그아웃 뒤 스냅숏을 다시 쓰면 위젯이 앞 계정을 그린다(Swift `writeWidgetSnapshot` 첫 가드). */
    private fun writeWidget(deferWhileRefreshing: Boolean) {
        if (!context.sessionStore.isSignedIn || context.sessionStore.userID == null) return
        widgetSink?.write(deferWhileRefreshing)
    }

    /**
     * 새로고침이 도는데 받아 둔 팀 상태가 끊김 임계(90초)보다 낡았으면 쓰지 않는다(Swift `writeWidgetSnapshot(deferWhileRefreshing:)` 의 첫 가드).
     * background 에서 돌아온 직후의 값은 몇 분 전 판정을 늘려 센 추정이다 — 응답이 몇 초 뒤 오는데 그 추정을 먼저 쓰지 않게.
     */
    fun shouldDeferWidgetWrite(now: SwiftDate): Boolean {
        val fetchedAt = teamFetchedAt ?: return false
        return refreshTask != null && now.timeIntervalSince(fetchedAt) > TeamMemberStatus.STALE_PRESENCE_SECONDS
    }

    companion object {
        const val refreshIntervalSeconds: Double = 60.0

        /** 탭을 다시 볼 때 이 초 안에 받았으면 새로고침을 건너뛴다. */
        const val tabRefreshFreshSeconds: Double = 30.0
        val goalRange: IntRange = 1..168
        const val widgetTodoLimit = 50
        const val widgetTouchAgeSeconds: Double = 60.0

        /** 실패 목록 → 한 줄 안내. 취소만 있으면 null. 전송 실패(Swift URLError)면 연결 안내. */
        fun notice(failures: List<Throwable>): String? {
            val meaningful = failures.filter { AuthErrorRules.classify(it) != AuthErrorDisposition.cancelled }
            if (meaningful.isEmpty()) return null
            if (meaningful.any { AuthErrorRules.isTransport(it) }) return NowText.networkFailed
            return NowText.loadFailed
        }
    }
}
