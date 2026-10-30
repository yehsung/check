// 원본: 없음(조립 — W-6 #6 배선 work). 근거: 갈래 보고 coordinator_patches W2-g1(wq) · W2-g5(ws) · W2-g6(wp) + W-6 #1·#2·#3·#6.
// 근무 한 벌(큐·상태·정책·넛지·잠자기·12h·away·종료 3초)을 생성자 주입으로 묶는다. AppGraph 는 [WorkWiring] 하나만 만들고
// start(scope) → (앱 수명) → finishForQuit() → stop() 순서로 부른다. 모든 상태 호출은 [WorkDeps.scope](UI 단일 스레드)에서만 돈다.
@file:OptIn(ExperimentalTime::class)

package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.foundation.platform.desktop.IdleSource
import com.yehsung.aingcheck.core.foundation.platform.desktop.InputKind
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvents
import com.yehsung.aingcheck.core.net.assembleTeamStatuses
import com.yehsung.aingcheck.core.net.fetchOwnMembership
import com.yehsung.aingcheck.core.net.fetchTeamStatuses
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TeamMemberStatus
import com.yehsung.aingcheck.core.wire.models.WorkStatus
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.socialapi.DesktopSocialLifecycle
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkCommands
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkState
import com.yehsung.aingcheck.feature.desktop.work.LapWalletJudgment
import com.yehsung.aingcheck.feature.desktop.work.WorkEventSink
import com.yehsung.aingcheck.feature.desktop.work.WorkQueueHost
import com.yehsung.aingcheck.feature.desktop.work.WorkStartOrigin
import com.yehsung.aingcheck.feature.desktop.work.lap.LapCelebration
import com.yehsung.aingcheck.feature.desktop.work.lap.MilestoneTracker
import com.yehsung.aingcheck.feature.desktop.work.lap.TeamGoalDetector
import com.yehsung.aingcheck.feature.desktop.work.lap.TimeMilestones
import com.yehsung.aingcheck.feature.desktop.work.nudge.AutoStartSuppression
import com.yehsung.aingcheck.feature.desktop.work.nudge.NudgeAutoStarter
import com.yehsung.aingcheck.feature.desktop.work.nudge.NudgeScheduler
import com.yehsung.aingcheck.feature.desktop.work.nudge.SessionUsability
import com.yehsung.aingcheck.feature.desktop.work.policy.AwayOpenSession
import com.yehsung.aingcheck.feature.desktop.work.policy.AwayPolicy
import com.yehsung.aingcheck.feature.desktop.work.policy.AwaySyncResult
import com.yehsung.aingcheck.feature.desktop.work.policy.LongSessionPolicy
import com.yehsung.aingcheck.feature.desktop.work.policy.MeaningfulInputTracker
import com.yehsung.aingcheck.feature.desktop.work.policy.QuitFinisher
import com.yehsung.aingcheck.feature.desktop.work.policy.QuitOutcome
import com.yehsung.aingcheck.feature.desktop.work.policy.SleepCloseCorrection
import com.yehsung.aingcheck.feature.desktop.work.policy.SleepCloseMarkerStore
import com.yehsung.aingcheck.feature.desktop.work.policy.SleepPolicy
import com.yehsung.aingcheck.feature.desktop.work.policy.TerminationFlag
import com.yehsung.aingcheck.feature.desktop.work.policy.WakeGate
import com.yehsung.aingcheck.feature.desktop.work.policy.WorkPolicyConstants
import com.yehsung.aingcheck.feature.desktop.work.policy.toSwiftDate
import com.yehsung.aingcheck.feature.desktop.work.queue.DesktopWorkQueue
import com.yehsung.aingcheck.feature.desktop.work.service.LegacyHeartbeatFacts
import com.yehsung.aingcheck.feature.desktop.work.service.WorkTickGate
import com.yehsung.aingcheck.feature.desktop.work.service.awaySync
import com.yehsung.aingcheck.feature.desktop.work.service.awaySyncFrom
import com.yehsung.aingcheck.feature.desktop.work.service.makeWorkTickRequest
import com.yehsung.aingcheck.feature.desktop.work.service.reopenSession
import com.yehsung.aingcheck.feature.desktop.work.service.sendLegacyHeartbeat
import com.yehsung.aingcheck.feature.desktop.work.service.workTick
import com.yehsung.aingcheck.feature.desktop.work.state.DesktopWorkStore
import com.yehsung.aingcheck.feature.desktop.work.state.HeartbeatPlan
import com.yehsung.aingcheck.feature.desktop.work.state.SleepCloseMarker
import com.yehsung.aingcheck.feature.desktop.work.state.WorkPolicyHooks
import com.yehsung.aingcheck.feature.desktop.work.state.WorkReopenCall
import com.yehsung.aingcheck.feature.desktop.work.wire.AwaySync
import com.yehsung.aingcheck.feature.desktop.work.wire.AwaySyncResponse
import com.yehsung.aingcheck.feature.desktop.work.wire.AwaySyncUnavailable
import com.yehsung.aingcheck.feature.desktop.work.wire.WorkTickFailure
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.time.Clock
import kotlin.time.ExperimentalTime

/**
 * 근무 배선의 의존 묶음. 이름·타입은 AppGraph 그대로(clock = AppGraph.clock, deviceId = AppGraph.deviceId, idle/power/session =
 * AppGraph.platform 의 같은 이름). [teamId] 는 소속 스토어가, [autoWorkStartEnabled] 는 설정이 준다(설정엔 자동 시작만 — 기본 끔).
 * [social] 은 늦게 묶는다(소셜 배선이 근무 상태를 받아 만들어지므로 — AppGraph 가 `{ social.lifecycle }` 를 넘긴다).
 */
data class WorkDeps(
    val sessionStore: SessionStore,
    val kv: DesktopKeyValueStore,
    val clock: Clock,
    val deviceId: String?,
    val idle: IdleSource,
    val power: PowerEvents,
    val session: SessionEvents,
    val teamId: () -> String?,
    val events: WorkEventSink = WorkEventSink.NONE,
    val social: () -> DesktopSocialLifecycle = { DesktopSocialLifecycle.None },
    val autoWorkStartEnabled: () -> Boolean = { false },
    /** 깨움 결합 관측자(W3-d 네트워크). null 이면 게이트 없이 즉시 연다. */
    val wakeNetworkReady: (suspend () -> Unit)? = null,
    val newUuid: () -> String = { java.util.UUID.randomUUID().toString() },
    /** 정책 박자(away·12h·마일스톤) 주기. Swift 하트비트 주기와 같다. */
    val policyBeatMillis: Long = (WorkPolicyConstants.HEARTBEAT_INTERVAL_SECONDS * 1000).toLong(),
    /**
     * 팀 상태 틱(work_tick · 폴백 하트비트) 한 슬라이스(Swift refreshLoopSliceSeconds = heartbeatIntervalSeconds 30초).
     * 근무 중엔 슬라이스마다, 비근무엔 [WorkWiring.IDLE_TICK_SLICES] 슬라이스(300초)마다 — 근무로 바뀌면 다음 슬라이스에 바로.
     */
    val tickSliceMillis: Long = (WorkPolicyConstants.HEARTBEAT_INTERVAL_SECONDS * 1000).toLong(),
)

/**
 * 근무 한 벌. 만든 것들은 속성으로 드러낸다(화면·트레이·오버레이 배선이 읽는다). 화면·단축키·트레이 메뉴는 [commands] 만 부른다 —
 * [store] 를 직접 start/stop 하면 소셜 생명주기(onWorkStarted·onUserStoppedWork)가 빠진다.
 */
class WorkWiring(private val deps: WorkDeps) {
    private val clockFn: () -> SwiftDate = { deps.clock.now().toSwiftDate() }

    // DesktopWorkQueue·DesktopWorkStore·WakeGate 는 생성자에서 스코프를 받는다 — start 전에 만들어지므로 늦게 묶는 스코프를 준다.
    // (맨 위에 둔다 — 아래 속성 초기화가 이것을 읽는다.)
    private val lateScope = LateScope()
    private fun scopeHolder(): CoroutineScope = lateScope
    private val session = deps.sessionStore

    /** 종료 시퀀스 표식 한 개(wp 억제 · 퀵 피니셔 · 이 배선이 함께 본다). */
    val termination = TerminationFlag()
    val usability = SessionUsability()
    val inputTracker = MeaningfulInputTracker(deps.idle, sessionUsable = { usability.isUsable })
    val suppression = AutoStartSuppression(deps.kv, termination)
    val sleepMarkers = SleepCloseMarkerStore(deps.kv)
    private val milestoneTracker = MilestoneTracker(deps.kv)

    // 큐 ↔ 상태는 서로를 생성자로 받는다 — 큐 쪽 host 를 늦게 묶어 순환을 끊는다(큐는 생성 중에 host 를 부르지 않는다).
    private val hostRef = LateWorkQueueHost()
    val queue = DesktopWorkQueue(session, hostRef, deps.kv, scopeHolder(), clockFn)

    private lateinit var wakeGateRef: WakeGate
    private lateinit var awayRef: AwayPolicy
    private lateinit var longSessionRef: LongSessionPolicy

    private val policyHooks = object : WorkPolicyHooks {
        override fun clearAutoStartSuppression() = suppression.clear()
        override fun suppressAutoStart(now: SwiftDate) {
            suppression.onManualStop(now)
        }
        override fun onSessionAnchored(anchor: SwiftDate, resetSleepBegan: Boolean, clearSleepMarker: Boolean) {
            if (clearSleepMarker) sleepMarkers.clear()
        }
        override fun onSessionEnded(resetSleepTracking: Boolean) {
            if (resetSleepTracking) sleepMarkers.clear()
        }
        override fun onLongSessionConfirmed(now: SwiftDate) = longSessionRef.confirmStillWorking(now)
        override fun pendingSleepClose(): SleepCloseMarker? = sleepMarkers.load()?.let {
            SleepCloseMarker(it.sessionID, it.startedAtDate, it.sleepBeganAtDate, it.lastInputAtDate)
        }
        override fun clearPendingSleepClose() = sleepMarkers.clear()
        override fun clearAwayState() = awayRef.clear()
        override suspend fun awaitWakeGate() = wakeGateRef.await()
    }

    val store: DesktopWorkStore = DesktopWorkStore(
        queue = queue,
        kv = deps.kv,
        deviceId = deps.deviceId,
        userId = { session.session?.userID },
        teamId = deps.teamId,
        clock = clockFn,
        newUuid = deps.newUuid,
        events = deps.events,
        policy = policyHooks,
        meaningfulInput = { inputTracker.advance(clockFn()) },
        scope = scopeHolder(),
        reopenCall = WorkReopenCall { team, sid ->
            session.withSessionRetry { s -> session.service.reopenSession(s.accessToken, team, s.userID, sid) }
        },
    ).also { hostRef.target = it }

    val state: DesktopWorkState get() = store

    /** 화면·단축키·트레이·넛지가 부르는 단 하나의 명령 문(소셜 생명주기를 여기서 펼친다). */
    val commands: DesktopWorkCommands = object : DesktopWorkCommands {
        override fun toggle() = if (store.snapshot.value.isWorking) stop() else start()

        override fun start(origin: WorkStartOrigin) {
            val was = store.snapshot.value.isWorking
            store.start(origin)
            // 순서: 상태가 근무 중이 된 **뒤에** 소셜(drain 은 localSessionOpen 을 본다). 실패·중복 시작이면 부르지 않는다.
            if (!was && store.snapshot.value.isWorking) deps.social().onWorkStarted()
        }

        override fun stop() {
            val was = store.snapshot.value.isWorking
            store.stop()
            if (was && !store.snapshot.value.isWorking) deps.social().onUserStoppedWork(termination.isTerminating)
        }

        override fun confirmStillWorking() = store.confirmStillWorking()

        override fun resumeRecentlyClosed() = store.resumeRecentlyClosed()
    }

    val wakeGate: WakeGate = WakeGate(
        scope = scopeHolder(),
        waitUntilSatisfied = deps.wakeNetworkReady,
        onRelease = { deps.social().onDidWake(clockFn()) },
    ).also { wakeGateRef = it }

    val sleep = SleepPolicy(
        state = store,
        autoClose = store,
        markers = sleepMarkers,
        // 실시간 링은 근무 가드보다 앞에서 내린다(W2-g3).
        beforeSleepGuard = { at -> deps.social().onWillSleep(at) },
        wakeFirst = { wakeGate.begin() },
    )
    val sleepCorrection = SleepCloseCorrection(sleepMarkers, store, queue, newItemId = { deps.newUuid().lowercase() })
    val away = AwayPolicy(store, store, inputTracker).also { awayRef = it }
    val longSession = LongSessionPolicy(store, store).also { longSessionRef = it }
    val milestones = TimeMilestones(milestoneTracker, deps.events, onLapCandidate = { lap -> deps.social().onLapCrossed(lap.toInt()) })
    val teamGoal = TeamGoalDetector(milestoneTracker, deps.events)
    val lapCelebration = LapCelebration(deps.events)

    /** 울트라 지갑(W2-g4)이 받는 랩 판정 실물(W2-g6) — LapCelebrated 사건은 여기서 한 번. */
    val lapJudgment: LapWalletJudgment = LapWalletJudgment { grants, streak -> lapCelebration.onWalletSynced(grants, streak) }

    val nudge = NudgeAutoStarter(
        state = store,
        isSignedIn = { session.session != null },
        hasTeam = { deps.teamId() != null },
        suppression = suppression,
        autoWorkStartEnabled = deps.autoWorkStartEnabled,
        // W-6 #2: NudgeStarted 는 ws 가 낸다 — 여기서 내지 않는다. 명령 문을 지나 소셜 onWorkStarted 도 함께.
        startWork = { origin -> commands.start(origin) },
        resumeRecentlyClosed = { origin -> store.resumeRecentlyClosed(origin) },
        clock = clockFn,
    )
    val nudgeScheduler: NudgeScheduler = nudge.scheduler(
        idleSeconds = {
            val last = deps.idle.lastInput(InputKind.entries.toSet())
            if (last == null) Double.MAX_VALUE else maxOf(0.0, clockFn().timeIntervalSince(last.toSwiftDate()))
        },
        isSessionUsable = { usability.isUsable },
    )

    /** work_tick 사용 가능 판정(⑨ — 404·403·계약은 이 실행 동안 끄고, (c) 일시 실패 3연속이면 정지). (b) 과부하는 세지 않는다. */
    val workTickGate = WorkTickGate()

    /** (b) 과부하·도달 불가 백오프(≤120초×지터) — [workTickGate] 의 정지 카운터와 따로 센다(Swift recordOverloadFailure). */
    val workTickBackoff = WorkTickOverloadBackoff()

    /** 소속 읽기가 성공한 계정(Swift membershipConfirmed — 로그아웃·계정 전환이면 다른 uid 라 미확정으로 돌아간다). */
    @Volatile private var membershipConfirmedFor: String? = null
    private val teamStatusFlow = MutableStateFlow<List<TeamMemberStatus>>(emptyList())

    /** 마지막으로 반영한 팀 상태(work_tick 조각 또는 폴백 4 GET). 팀 목록·트레이가 읽는다. 로그아웃이면 빈 목록. */
    val teamStatuses: StateFlow<List<TeamMemberStatus>> = teamStatusFlow.asStateFlow()
    private var lastHeartbeatSucceededAt: SwiftDate? = null
    private var lastLegacyHeartbeatAt: SwiftDate? = null

    val quitFinisher = QuitFinisher(
        state = store,
        isSignedIn = { session.session != null },
        termination = termination,
        stop = { commands.stop() },
        queue = queue,
    )

    private var scope: CoroutineScope? = null
    private val jobs = mutableListOf<Job>()
    private val registrations = mutableListOf<Registration>()

    /** 앱 시작(로그인 전이어도 된다). 멱등. */
    fun start(scope: CoroutineScope) {
        if (this.scope != null) return
        this.scope = scope
        lateScope.target = scope
        suppression.restoreOnLaunch(clockFn())
        registrations += usability.attach(deps.session)
        registrations += deps.power.addListener { event ->
            scope.launch {
                when (event) {
                    PowerEvent.SLEEP -> sleep.handleSleep(clockFn())
                    PowerEvent.WAKE -> {
                        nudgeScheduler.handleWake()
                        sleep.handleWake(clockFn())
                    }
                }
            }
        }
        // 계정 전환: 상태 주인 바꾸기 → 남의 큐 항목 걷기 → 남은 줄 재시도(Swift adoptWorkStateOwner · W-6 #3).
        jobs += scope.launch {
            session.sessionFlow.map { it?.userID }.distinctUntilChanged().collect { uid ->
                if (uid == null) return@collect
                store.adoptWorkStateOwner(uid)
                queue.retainOwner(uid)
                scope.launch { swallow { queue.retryPending() } }
            }
        }
        nudgeScheduler.start(scope)
        jobs += scope.launch {
            while (isActive) {
                delay(deps.policyBeatMillis)
                policyBeat(clockFn())
            }
        }
        // 팀 상태 틱(Swift startRefreshLoopTask): 근무 중 30초 · 비근무 300초(슬라이스마다 근무 전이를 본다). 이 루프가 없으면
        // 근무 중 last_seen_at 이 시작 시각에 얼어 서버 스캐빈저(10분)가 세션을 닫는다.
        jobs += scope.launch {
            while (isActive) {
                if (store.snapshot.value.isWorking) {
                    delay(deps.tickSliceMillis)
                } else {
                    var slices = 0
                    while (slices < IDLE_TICK_SLICES) {
                        delay(deps.tickSliceMillis)
                        slices += 1
                        // 소속 미확정(실행 킥이 망 결합 전에 실패)은 유휴 1주기를 기다리지 않는다 — 그동안 팀이 null 이라
                        // 하트비트·큐 드레인이 전부 죽어 있다. 확정돼 있으면 요청 0(Swift 느린 주기 안 confirmMembershipIfNeeded).
                        swallow { confirmMembershipIfNeeded() }
                        if (store.snapshot.value.isWorking) break
                    }
                }
                swallow { workTickBeat(clockFn()) }
            }
        }
    }

    /**
     * 팀 상태 틱 한 번(Swift 폴링 본문 retryPendingSync → workTickIfPossible → finishWorkTick 자리, 시험이 직접 부른다).
     * work_tick 1건이 하트비트·팀 상태·away 조각을 한 번에 가져온다. 못 쓰면(함수 없음·실행권·계약·일시 실패) 같은 틱에서
     * 레거시 하트비트 → 팀 상태 4 GET → away_sync 로 펼친다. 과부하·도달 불가(502·503·504·52x·408·429·전송 실패)는 펼치지 않고
     * 근무 중 하트비트만 120초 간격으로 지킨다(Swift overloadHeartbeatMaxGapSeconds — 스캐빈저 10분보다 한참 안쪽).
     */
    suspend fun workTickBeat(now: SwiftDate) {
        if (session.session == null) {
            teamStatusFlow.value = emptyList()
            away.shouldSync(now, signedIn = false)
            return
        }
        // 본문 맨 앞: 큐는 팀이 없으면 noTeam 으로 던지므로, 팀 확정이 드레인보다 앞서야 오프라인에서 쌓인 근무가 같은 틱에 재생된다.
        swallow { confirmMembershipIfNeeded() }
        swallow { queue.retryPending() }
        when (val outcome = performWorkTick(now)) {
            is TickOutcome.Applied -> {
                applyTeamStatus(outcome.members, outcome.writeGeneration)
                if (away.shouldSync(now, signedIn = true)) away.apply(awayFromTick(outcome.away))
            }
            TickOutcome.Fallback -> {
                swallow { legacyHeartbeat(now) }
                swallow { legacyTeamStatus(now) }
                if (away.shouldSync(now, signedIn = true)) away.apply(fetchAway())
            }
            TickOutcome.Overloaded -> {
                if (store.snapshot.value.isWorking && olderThan(lastHeartbeatSucceededAt, now) && olderThan(lastLegacyHeartbeatAt, now)) {
                    swallow { legacyHeartbeat(now) }
                }
                if (away.shouldSync(now, signedIn = true)) away.apply(AwaySyncResult.Failed)
            }
            TickOutcome.Skipped -> Unit
        }
    }

    /**
     * Swift confirmMembershipIfNeeded: 이 계정의 소속 읽기가 아직 성공하지 않았으면 한 번 읽는다(확정 상태면 요청 0).
     * 로그인 직후 SessionStore.refreshProfile 이 실패하면(오프라인 부팅) 팀이 이 실행 내내 null 로 남고, 근무가 서버에
     * 한 건도 오르지 않는다(반박 검증 must_fix 1 · s1) — 틱 루프가 유일한 회복 경로다. refreshProfile 은 성패를 알려 주지 않아
     * (공용 core) 읽기 자체는 여기서 하고, 읽은 팀이 프로필과 다를 때만 refreshProfile 로 프로필에 싣는다.
     */
    suspend fun confirmMembershipIfNeeded() {
        val uid = session.session?.userID ?: return
        if (membershipConfirmedFor == uid) return
        // 프로필에 팀이 이미 섰다 = 이 계정의 소속 읽기가 성공했다(enterSignedIn · 팀 참여 · 기록 화면).
        if (deps.teamId() != null) {
            membershipConfirmedFor = uid
            return
        }
        val generation = session.sessionGeneration
        val service = session.service
        val membership = session.withSessionRetry { s -> service.fetchOwnMembership(s.accessToken, s.userID) }
        if (generation != session.sessionGeneration || session.session?.userID != uid) return
        if (membership?.teamID != deps.teamId()) {
            session.refreshProfile()
            if (membership?.teamID != deps.teamId()) return // 싣기 실패 — 다음 슬라이스가 다시 본다
        }
        membershipConfirmedFor = uid
    }

    private sealed interface TickOutcome {
        data class Applied(val members: List<TeamMemberStatus>, val writeGeneration: Int, val away: AwaySyncResponse?) : TickOutcome
        data object Fallback : TickOutcome
        data object Overloaded : TickOutcome
        data object Skipped : TickOutcome
    }

    private suspend fun performWorkTick(now: SwiftDate): TickOutcome {
        // 무소속은 통합 대상이 아니다(Swift — 팀 GET 이 없어 합칠 것이 없다): 폴백(하트비트·팀 조회는 팀이 없어 0, away 만).
        if (deps.teamId() == null) return TickOutcome.Fallback
        if (!workTickGate.isAvailable(now)) {
            // (a) 이 실행 동안 끔 · (c) 정지 — 기존 경로 그대로(Swift .disabled/.suspended).
            workTickGate.recordFallback()
            return TickOutcome.Fallback
        }
        // (b) 과부하 백오프 중 — work_tick 도 기존 경로도 내지 않는다(Swift .backingOff → holdTickDuringOverload).
        if (workTickBackoff.isBackingOff(now)) return TickOutcome.Overloaded
        val args = store.planWorkTick(now) ?: return TickOutcome.Fallback
        val generation = session.sessionGeneration
        val service = session.service
        val request = service.makeWorkTickRequest(
            teamID = args.teamId,
            heartbeat = args.heartbeat,
            sessionID = args.sessionId,
            deviceID = args.deviceId,
            openedSession = args.openedSession,
            lastInputAt = args.lastInputAt,
            includeMeta = false,
            now = now,
        )
        return try {
            val response = session.withSessionRetry { s -> service.workTick(s.accessToken, request) }
            workTickGate.recordSuccess(response.serverNow?.let(service::parseDate), clockFn())
            workTickBackoff.recordSuccess()
            if (generation != session.sessionGeneration) return TickOutcome.Skipped
            if (args.heartbeat) lastHeartbeatSucceededAt = now
            val members = service.assembleTeamStatuses(
                response.statuses.orEmpty(),
                response.sessionsActive.orEmpty(),
                response.sessionsWeekly.orEmpty(),
                response.devices.orEmpty(),
                now,
            )
            TickOutcome.Applied(members, args.writeGeneration, response.away)
        } catch (e: CancellationException) {
            throw e
        } catch (e: WorkTickFailure) {
            val reason = e.message ?: e.toString()
            when {
                e.disablesForRun -> {
                    workTickGate.disable(reason, now)
                    workTickBackoff.recordSuccess() // 이 실행 동안 꺼졌다 — 백오프로 붙들지 말고 폴백으로 산다
                    workTickGate.recordFallback()
                    TickOutcome.Fallback
                }
                isOverload(e) -> {
                    // (b) 는 (c) 정지 카운터에 세지도 지우지도 않는다 — 따로 백오프(≤120초×지터).
                    workTickBackoff.recordFailure(reason, now)
                    TickOutcome.Overloaded
                }
                else -> {
                    workTickGate.recordTransientFailure(reason, now)
                    workTickGate.recordFallback()
                    TickOutcome.Fallback
                }
            }
        } catch (e: SupabaseWorkServiceError) {
            // 세션 만료·키 문제 등(c) — 폴백 경로가 같은 오류를 만나 기존 규약대로 다룬다.
            workTickGate.recordTransientFailure(e.toString(), now)
            workTickGate.recordFallback()
            TickOutcome.Fallback
        } catch (e: Exception) {
            // 서버에 닿지 못했다(시간 초과·연결 실패·오프라인) — 펼쳐도 같은 벽이다(b).
            workTickBackoff.recordFailure(e::class.simpleName ?: "transport", now)
            TickOutcome.Overloaded
        }
    }

    /** Swift WorkTickGate.isOverload — 502·503·504·520~524 · 408·429. */
    private fun isOverload(e: WorkTickFailure): Boolean = when (e) {
        is WorkTickFailure.ServerError -> e.status in 502..504 || e.status in 520..524
        is WorkTickFailure.Rejected -> e.status == 408 || e.status == 429
        else -> false
    }

    private fun olderThan(at: SwiftDate?, now: SwiftDate): Boolean =
        at == null || now.timeIntervalSince(at) > OVERLOAD_HEARTBEAT_MAX_GAP_SECONDS

    /** 레거시 하트비트(Swift sendHeartbeatIfWorking) — 계획은 ws, 와이어 순서·가드는 wq. */
    private suspend fun legacyHeartbeat(now: SwiftDate) {
        val facts = when (val plan = store.planHeartbeat(away.serverSupported, now)) {
            HeartbeatPlan.Skip -> return
            is HeartbeatPlan.DeviceInputOnly -> LegacyHeartbeatFacts(
                teamId = plan.teamId, adopted = true, confirmedSessionId = null, deviceId = plan.deviceId,
                ownsStrongly = false, awayServerSupported = true, observedInput = plan.lastInputAt,
            )
            is HeartbeatPlan.Beat -> LegacyHeartbeatFacts(
                teamId = plan.teamId, adopted = false, confirmedSessionId = plan.sessionId, deviceId = plan.device?.deviceId,
                ownsStrongly = plan.device?.openedSession ?: false, awayServerSupported = true, observedInput = plan.lastInputAt,
            )
        }
        lastLegacyHeartbeatAt = now
        session.sendLegacyHeartbeat(facts)
    }

    /** 레거시 팀 상태(Swift refreshTeamStatus — 4 GET). 세대는 발사 전에 잡는다(늦은 응답 버림). */
    private suspend fun legacyTeamStatus(now: SwiftDate) {
        val team = deps.teamId() ?: return
        val generation = session.sessionGeneration
        val writeGeneration = store.workStateWriteGeneration
        val members = session.withSessionRetry { s -> session.service.fetchTeamStatuses(s.accessToken, team, now) }
        if (generation != session.sessionGeneration) return
        applyTeamStatus(members, writeGeneration)
    }

    private fun awayFromTick(fragment: AwaySyncResponse?): AwaySyncResult =
        fragment?.let { awayResult(session.service.awaySyncFrom(it)) } ?: AwaySyncResult.Failed

    private fun awayResult(sync: AwaySync): AwaySyncResult = if (!sync.isOK) {
        AwaySyncResult.Failed
    } else {
        AwaySyncResult.Ok(
            closeThresholdSeconds = sync.policy?.closeThresholdSeconds,
            openSession = sync.openSession?.let { AwayOpenSession(it.sessionID, it.closeEligible, it.lastInputAt) },
        )
    }

    /**
     * 정책 박자 한 번(시험이 직접 부른다). away·12h 평가 → 마일스톤. away 서버 판정 재료는 팀 상태 틱이 넣는다
     * ([workTickBeat] — work_tick 조각 또는 폴백 away_sync). 여기서 따로 away_sync 를 내지 않는다(요청 두 벌 금지).
     */
    suspend fun policyBeat(now: SwiftDate) {
        swallow { away.evaluate(now) }
        swallow {
            longSession.evaluate(now)
            val shown = longSession.promptShownAt.value
            if (shown != null && store.snapshot.value.longSessionPromptShownAt == null) store.showLongSessionPrompt(shown)
        }
        swallow { milestones.evaluate(store.snapshot.value, now) }
    }

    private suspend fun fetchAway(): AwaySyncResult = try {
        awayResult(session.withSessionRetry { s -> session.service.awaySync(s.accessToken) })
    } catch (e: CancellationException) {
        throw e
    } catch (e: AwaySyncUnavailable) {
        AwaySyncResult.Unavailable
    } catch (e: Exception) {
        AwaySyncResult.Failed
    }

    /**
     * 팀 상태·work_tick 응답을 반영하는 한 문(팀 상태 배선이 부른다). 순서: ws 소유 반영 → off_work 면 잠자기 마감 정정 →
     * 소셜 빚 되맞춤(Swift 3396 — 반영 **직후**).
     */
    fun applyTeamStatus(members: List<TeamMemberStatus>, writeGeneration: Int) {
        teamStatusFlow.value = members
        store.applyRemoteOwnStatus(members, writeGeneration)
        val uid = session.session?.userID
        val own = members.firstOrNull { it.id == uid }
        if (own != null && own.status == WorkStatus.offWork) {
            sleepCorrection.onOwnStatusOffWork(
                snapshot = store.snapshot.value,
                isOwnedByThisDevice = { sid -> store.ownedSessionId == sid },
                ownerUserId = uid,
            )
        }
        deps.social().onTeamStatusApplied()
    }

    /**
     * 종료 훅 몫(W-6 #6 첫 두 칸): beginTermination → QuitFinisher 3초. 이 뒤의 stop 은 자동 시작 억제를 심지 않고(⑰),
     * 찌르기 꼬리 회수도 하지 않는다(isTerminating=true).
     */
    suspend fun finishForQuit(): QuitOutcome {
        store.beginTermination()
        return quitFinisher.finishWorkBeforeQuit()
    }

    /** 수명 끝(시험·종료 훅 마지막). 루프·OS 구독을 내린다. 큐 드레인은 취소하지 않는다(진 쪽은 큐 수명에서). */
    fun stop() {
        nudgeScheduler.stop()
        jobs.forEach { it.cancel() }
        jobs.clear()
        registrations.forEach { runCatching { it.close() } }
        registrations.clear()
        scope = null
    }

    val isStarted: Boolean get() = scope != null

    companion object {
        /** 비근무 틱 = 슬라이스 × 10(Swift 느린 유휴 주기 300초). */
        const val IDLE_TICK_SLICES: Int = 10

        /** 과부하 중 하트비트 간격 상한(Swift overloadHeartbeatMaxGapSeconds 120초). */
        const val OVERLOAD_HEARTBEAT_MAX_GAP_SECONDS: Double = 120.0
    }
    internal val openRegistrations: Int get() = registrations.size

    private class LateWorkQueueHost : WorkQueueHost {
        lateinit var target: WorkQueueHost
        override val currentTeamId: String? get() = target.currentTeamId
        override val workStateWriteGeneration: Int get() = target.workStateWriteGeneration
        override val liveSessionId: String? get() = target.liveSessionId
        override fun setConfirmedServerSessionId(id: String?) = target.setConfirmedServerSessionId(id)
        override suspend fun awaitWakeGate() = target.awaitWakeGate()
        override suspend fun onDrained() = target.onDrained()
        override fun onSyncFailed(message: String) = target.onSyncFailed(message)
    }
}

/** start(scope) 전에 생성자로 넘겨야 하는 스코프 자리 — 묶이기 전엔 쓰지 않는다(쓰면 그 자리에서 실패해 드러난다). */
internal class LateScope : CoroutineScope {
    @Volatile var target: CoroutineScope? = null
    override val coroutineContext get() = (target ?: error("배선 start(scope) 전에 스코프를 썼다")).coroutineContext
}

internal suspend inline fun swallow(block: () -> Unit) {
    try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Throwable) {
        // 박자 한 칸의 실패는 다음 박자가 다시 본다(Swift 의 박자 함수는 throws 가 아니다).
    }
}
