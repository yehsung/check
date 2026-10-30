// W2-g5 근무 상태 코어 — 시작·종료·소유·흡수·틱 조립·하트비트 계획·읽기 전용 상태.
// 원본(@ a90d8623, 줄은 그 커밋 기준):
//   Sources/check/WorkTimerStore.swift 1835(todayDuration) · 2005-2180(toggle·start·stop) · 2491-2540(closeOwnedSessionLocally·autoStop) ·
//     2369(confirmStillWorking) · 2391(advanceMeaningfulInput) · 3699-3850(소유) · 4257(adoptWorkStateOwner)
//   Sources/check/WorkTimerStoreSync.swift 72-200(work_tick 조립) · 1093-1160(레거시 하트비트) · 1360-1470(30분 재개) ·
//     1669(syncCurrentStatus) · 1969-2424(applyRemoteOwnStatus·흡수·백스톱·반납·yieldsToClaim)
// 규약 번호는 지시서 work.md §2: ⑬ confirmed 만 싣는다 · ⑭ 입력 관측이 소유 판정보다 앞 · ⑮ 도장 (a)(b)(c) · ⑯ 반납 ·
//   ⑰ 종료 시퀀스 stop 은 억제를 안 심는다 · ⑱ start/stop/autoStop 세대↑, 늦은 응답은 그 세대로 버린다 · C#22 소문자 id.
// 스레드: Swift @MainActor 와 같게 **한 스레드(UI 디스패처)에서만** 부른다 — 조립이 지킨다.
package com.yehsung.aingcheck.feature.desktop.work.state

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TeamMemberStatus
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.core.wire.models.WorkStatus
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeConsumeFacts
import com.yehsung.aingcheck.feature.desktop.work.AutoCloseReason
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkCommands
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkState
import com.yehsung.aingcheck.feature.desktop.work.LastAutoClose
import com.yehsung.aingcheck.feature.desktop.work.PendingWorkItem
import com.yehsung.aingcheck.feature.desktop.work.PendingWorkOperation
import com.yehsung.aingcheck.feature.desktop.work.PokeFactsSource
import com.yehsung.aingcheck.feature.desktop.work.WorkAutoClose
import com.yehsung.aingcheck.feature.desktop.work.WorkEvent
import com.yehsung.aingcheck.feature.desktop.work.WorkEventSink
import com.yehsung.aingcheck.feature.desktop.work.WorkQueue
import com.yehsung.aingcheck.feature.desktop.work.WorkQueueHost
import com.yehsung.aingcheck.feature.desktop.work.WorkSessionIds
import com.yehsung.aingcheck.feature.desktop.work.WorkStartOrigin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** 되돌리기 재개(reopen) 서버 호출 — wq 서비스의 reopenSession 을 조립이 잇는다. 실패는 예외. */
fun interface WorkReopenCall {
    suspend fun reopen(teamId: String, sessionId: String)
}

/**
 * Windows 근무 상태기계. 핀의 [DesktopWorkState]·[DesktopWorkCommands]·[WorkAutoClose]·[WorkQueueHost]·[PokeFactsSource] 를 구현한다.
 *
 * @param deviceId 'win:'+소문자 uuid(AppGraph.deviceId). null·빈 문자열이면 기기 단위 쓰기 0 — 틱 p_device_id null,
 *   기기 행 upsert·입력 보고 계획 0.
 * @param meaningfulInput OS 가 본 마지막 의미 있는 입력(키·클릭·휠, 이동 제외 · 잠금/비콘솔이면 null) — W3-d 배선이 준다.
 * @param newUuid 세션·항목 id 원천. 대문자여도 세션 id 는 만드는 순간 소문자로 고친다(C#22).
 */
class DesktopWorkStore(
    private val queue: WorkQueue,
    kv: DesktopKeyValueStore,
    deviceId: String?,
    private val userId: () -> String?,
    private val teamId: () -> String?,
    private val clock: () -> SwiftDate,
    private val newUuid: () -> String,
    private val events: WorkEventSink = WorkEventSink.NONE,
    private val policy: WorkPolicyHooks = WorkPolicyHooks.NONE,
    private val meaningfulInput: () -> SwiftDate? = { null },
    private val scope: CoroutineScope? = null,
    private val reopenCall: WorkReopenCall? = null,
) : DesktopWorkState, DesktopWorkCommands, WorkAutoClose, WorkQueueHost, PokeFactsSource {

    val deviceId: String? = deviceId?.takeIf { it.isNotEmpty() }
    val hasDeviceIdentity: Boolean get() = deviceId != null

    private val ledger = OwnedSessionLedger(kv)
    private val state = MutableStateFlow(DesktopWorkSnapshot())
    override val snapshot: StateFlow<DesktopWorkSnapshot> = state.asStateFlow()

    // ── 상태(Swift 프로퍼티 이름에 맞춘다) ──
    var startedAt: SwiftDate? = null
        private set
    var currentSessionId: String? = null
        private set
    private var confirmedServerSessionId: String? = null
    var adoptedRemoteSession: Boolean = false
        private set
    private var accumulatedSeconds: Long = 0
    private var accumulatedDayStart: SwiftDate? = null
    private var lastMeaningfulInputAt: SwiftDate? = null
    private var pendingSync = false
    private var syncMessage: String? = null
    private var longSessionPromptShownAt: SwiftDate? = null
    private var startOrigin: WorkStartOrigin? = null
    var isTerminating: Boolean = false
        private set
    override var workStateWriteGeneration: Int = 0
        private set
    private var lastOwnMember: TeamMemberStatus? = null
    private var workStateOwnerUserId: String? = null

    private var recentSessionId: String? = null
    private var recentStartedAt: SwiftDate? = null
    private var recentEndedAt: SwiftDate? = null
    private var recentReason: AutoCloseReason? = null
    private var recentSeconds: Long = 0
    private var recentStrength: SessionClaimStrength = SessionClaimStrength.WEAK
    private var recentAt: SwiftDate? = null

    // 흡수 백스톱 장부(Swift adoptedLastSeen*) · 반납 장부(foreignDevice*) — 둘을 합치지 않는다(Swift 3836 주석).
    private var adoptedLastSeenAt: SwiftDate? = null
    private var adoptedLastSeenSessionId: String? = null
    private var adoptedStallBeganAt: SwiftDate? = null
    private var adoptedStallObservations = 0
    private val foreignDeviceLastSeenAt = mutableMapOf<String, SwiftDate>()
    private var foreignDeviceTrackingSessionId: String? = null

    // ── 파생 값 ──
    /** 확인된 서버 세션 id — 현재 세션과 서버가 확인해 준 값이 같을 때만(Swift confirmedSessionID 173). */
    val confirmedSessionId: String?
        get() {
            val current = WorkSessionIds.canonical(currentSessionId) ?: return null
            return if (current == confirmedServerSessionId) current else null
        }

    val ownsCurrentSessionStrongly: Boolean
        get() = ledger.isOwned(currentSessionId) && ledger.strength == SessionClaimStrength.STRONG

    val ownedSessionId: String? get() = ledger.ownedSessionId
    val ownedSessionStrength: SessionClaimStrength get() = ledger.strength

    // ── WorkQueueHost ──
    override val currentTeamId: String? get() = teamId()
    override val liveSessionId: String? get() = if (startedAt != null) WorkSessionIds.canonical(currentSessionId) else null

    /** 도장 (a)·blocker==mine 이면 id, (3-b) 면 null. */
    override fun setConfirmedServerSessionId(id: String?) {
        confirmedServerSessionId = WorkSessionIds.canonical(id)
        publish()
    }

    override suspend fun awaitWakeGate() = policy.awaitWakeGate()

    override suspend fun onDrained() {
        pendingSync = false
        publish()
    }

    override fun onSyncFailed(message: String) {
        pendingSync = true
        syncMessage = message
        publish()
    }

    // ── 명령 ──
    override fun toggle() {
        if (startedAt != null) stop() else start()
    }

    override fun start(origin: WorkStartOrigin) = start(origin, clock())

    /** 넛지 자동 시작은 [WorkStartOrigin.NUDGE] 로 부른다 — 실제로 시작됐을 때만 [WorkEvent.NudgeStarted] 를 낸다(W-6 #2: 이 사건은 ws 만 낸다). */
    fun start(origin: WorkStartOrigin, now: SwiftDate) {
        if (startedAt != null) return
        policy.clearAutoStartSuppression()
        workStateWriteGeneration += 1 // ⑱
        clearRecentAutoCloseResume()
        startedAt = now
        // C#22: 만드는 순간 정규화(서버 uuid 컬럼은 소문자로 돌려준다).
        currentSessionId = WorkSessionIds.canonical(newUuid())
        claimSessionOwnership(currentSessionId, SessionClaimStrength.STRONG)
        startOrigin = origin
        longSessionPromptShownAt = null
        policy.onSessionAnchored(now, resetSleepBegan = true, clearSleepMarker = true)
        lastMeaningfulInputAt = now
        syncCurrentStatus()
        publish()
        if (origin == WorkStartOrigin.NUDGE) events.onWorkEvent(WorkEvent.NudgeStarted)
    }

    override fun stop() = stop(clock())

    fun stop(now: SwiftDate) {
        val sessionStart = startedAt ?: return
        if (!isTerminating) policy.suppressAutoStart(now) // ⑰
        workStateWriteGeneration += 1 // ⑱
        clearRecentAutoCloseResume()
        val duration = maxOf(0L, now.timeIntervalSince(sessionStart).toLong())
        val dayStart = TeamWeeklyGoal.koreanDayStart(now)
        accumulatedSeconds += maxOf(0L, now.timeIntervalSince(maxOf(sessionStart, dayStart)).toLong())
        accumulatedDayStart = dayStart
        startedAt = null
        startOrigin = null
        releaseSessionOwnership()
        longSessionPromptShownAt = null
        policy.onSessionEnded(resetSleepTracking = true)
        syncCurrentStatus(durationSeconds = duration, sessionStartedAt = sessionStart, endedAt = now)
        publish()
    }

    /** 종료 시퀀스 진입(Swift finishWorkBeforeQuit 의 isTerminating=true). 이 뒤의 stop() 은 억제를 심지 않는다(⑰). */
    fun beginTermination() {
        isTerminating = true
    }

    /** 12h 프롬프트를 띄웠다(정책 갈래가 부른다). 근무 중이 아니면 무시. */
    fun showLongSessionPrompt(at: SwiftDate) {
        if (startedAt == null) return
        longSessionPromptShownAt = at
        publish()
    }

    override fun confirmStillWorking() {
        if (longSessionPromptShownAt == null) return
        longSessionPromptShownAt = null
        policy.onLongSessionConfirmed(clock())
        publish()
    }

    // ── 자동 마감(유일한 관문) ──
    override fun closeOwnedSessionLocally(endedAt: SwiftDate, reason: AutoCloseReason, message: String) {
        val sessionStart = startedAt ?: return
        if (adoptedRemoteSession) return // 흡수 세션은 마감하지 않는다(㉓)
        workStateWriteGeneration += 1 // ⑱
        clearRecentAutoCloseResume()
        val duration = maxOf(0L, endedAt.timeIntervalSince(sessionStart).toLong())
        val dayStart = TeamWeeklyGoal.koreanDayStart(endedAt)
        val closedTodaySeconds = maxOf(0L, endedAt.timeIntervalSince(maxOf(sessionStart, dayStart)).toLong())
        accumulatedSeconds += closedTodaySeconds
        accumulatedDayStart = dayStart
        recentSessionId = WorkSessionIds.canonical(currentSessionId)
        recentStartedAt = sessionStart
        recentEndedAt = endedAt
        recentReason = reason
        recentStrength = if (ledger.isOwned(currentSessionId)) ledger.strength else SessionClaimStrength.WEAK
        recentSeconds = closedTodaySeconds
        recentAt = clock()
        startedAt = null
        startOrigin = null
        releaseSessionOwnership()
        longSessionPromptShownAt = null
        policy.onSessionEnded(resetSleepTracking = true)
        syncCurrentStatus(durationSeconds = duration, sessionStartedAt = sessionStart, endedAt = endedAt, autoCloseReason = reason)
        syncMessage = message
        publish()
        events.onWorkEvent(WorkEvent.AutoClosed(reason, endedAt))
    }

    // ── 30분 재개 ──
    fun canResumeRecentlyClosed(now: SwiftDate = clock()): Boolean {
        if (recentSessionId == null || recentStartedAt == null) return false
        if (startedAt != null) return false
        val reason = recentReason ?: return false
        if (reason == AutoCloseReason.LONG_SESSION) return false
        val endedAt = recentEndedAt ?: return false
        val gap = now.timeIntervalSince(endedAt)
        return gap >= 0 && gap <= WorkStateConstants.RECENT_AUTO_CLOSE_RESUME_WINDOW_SECONDS
    }

    override fun resumeRecentlyClosed() = resumeRecentlyClosed(WorkStartOrigin.RESUME)

    /** 넛지 재개는 [WorkStartOrigin.NUDGE] — reopen 이 성공해 되살아날 때만 [WorkEvent.NudgeStarted] 를 스냅숏보다 먼저 낸다(W-6 #2). */
    fun resumeRecentlyClosed(origin: WorkStartOrigin) {
        if (!canResumeRecentlyClosed()) {
            clearRecentAutoCloseResume()
            publish()
            return
        }
        val launcher = scope ?: return
        launcher.launch { performResumeRecentlyClosed(origin) }
    }

    /** Swift performResumeRecentlyClosedSession — 서버 reopen 성공 뒤에만 되살린다. 강도는 마감 때 기록한 그대로. */
    suspend fun performResumeRecentlyClosed(origin: WorkStartOrigin = WorkStartOrigin.RESUME) {
        val sessionId = WorkSessionIds.canonical(recentSessionId) ?: return
        val restoredStart = recentStartedAt ?: return
        if (!canResumeRecentlyClosed()) {
            clearRecentAutoCloseResume()
            publish()
            return
        }
        val closedSeconds = recentSeconds
        val team = teamId() ?: return
        val call = reopenCall ?: return
        val owner = userId()
        val writeGeneration = workStateWriteGeneration
        try {
            call.reopen(team, sessionId)
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (_: Exception) {
            if (owner != userId()) return
            syncMessage = WorkStateConstants.RESUME_FAILED_MESSAGE
            publish()
            return
        }
        if (owner != userId()) return
        if (writeGeneration != workStateWriteGeneration || startedAt != null) {
            clearRecentAutoCloseResume()
            publish()
            return
        }
        workStateWriteGeneration += 1
        accumulatedSeconds = maxOf(0L, accumulatedSeconds - closedSeconds)
        startedAt = restoredStart
        currentSessionId = sessionId
        claimSessionOwnership(sessionId, recentStrength)
        startOrigin = WorkStartOrigin.RESUME
        policy.onSessionAnchored(restoredStart, resetSleepBegan = false, clearSleepMarker = false)
        clearRecentAutoCloseResume()
        syncMessage = WorkStateConstants.RESUMED_MESSAGE
        // 오버레이 I-8: 사건이 isWorking=true 스냅숏보다 먼저 와야 8초 문구가 출근 말풍선에 걸린다.
        if (origin == WorkStartOrigin.NUDGE) events.onWorkEvent(WorkEvent.NudgeStarted)
        publish()
    }

    // ── 서버 스냅숏 반영(소유·흡수·도장) ──

    /**
     * Swift applyRemoteOwnStatus(writeGeneration:) 1969. [members] 는 work_tick·팀 상태 응답을 조립한 팀원 행,
     * [writeGeneration] 은 요청을 낼 때의 세대(⑱ — 다르면 통째로 버린다).
     */
    fun applyRemoteOwnStatus(members: List<TeamMemberStatus>, writeGeneration: Int, now: SwiftDate = clock()) {
        val uid = userId() ?: return
        val own = members.firstOrNull { it.id == uid } ?: return
        lastOwnMember = own
        if (writeGeneration != workStateWriteGeneration) return
        if (queue.items.value.isNotEmpty()) return

        // ★ 도장 규칙 (c): 열린 행이 내 도장과 다르면 즉시 지운다.
        val serverOpenId = own.openSession?.id
        if (serverOpenId != null && serverOpenId != confirmedServerSessionId) confirmedServerSessionId = null

        if (own.status == WorkStatus.offWork) {
            val marker = policy.pendingSleepClose()
            if (marker != null) {
                val sleepEndedAt = maxOf(marker.sessionStartedAt, minOf(marker.sleepBeganAt, marker.lastInputAt ?: marker.sleepBeganAt))
                val markerId = WorkSessionIds.canonical(marker.sessionId)
                // (a) 경쟁 갈래: 로컬은 아직 근무 중인데 서버가 이미 닫았다 — autoStop 관문으로 잠자기 시각에 마감.
                if (startedAt != null && !adoptedRemoteSession && WorkSessionIds.canonical(currentSessionId) == markerId) {
                    policy.clearPendingSleepClose()
                    closeOwnedSessionLocally(sleepEndedAt, AutoCloseReason.SLEEP, WorkStateConstants.SLEEP_CLOSE_MESSAGE)
                    currentSessionId = null
                    publish()
                    return
                }
                // (b) 재실행 갈래: 로컬 근무 상태가 없다 — 영속 마커 + 소유 id 로 정정 Stop 을 줄에 넣는다.
                if (startedAt == null && markerId != null && ledger.isOwned(markerId)) {
                    policy.clearPendingSleepClose()
                    pendingSync = true
                    queue.enqueue(
                        PendingWorkItem(
                            id = newUuid(),
                            operation = PendingWorkOperation.Stop(maxOf(0L, sleepEndedAt.timeIntervalSince(marker.sessionStartedAt).toLong())),
                            sessionId = markerId,
                            sessionStartedAt = marker.sessionStartedAt,
                            endedAt = sleepEndedAt,
                            ownerUserId = uid,
                            autoCloseReason = AutoCloseReason.SLEEP,
                        ),
                    )
                    releaseSessionOwnership()
                }
            }
        }

        accumulatedSeconds = own.todayDurationSeconds
        accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(now)
        val localStart = startedAt
        when {
            own.status == WorkStatus.working && localStart == null -> adoptRemoteSession(own, now)
            own.status == WorkStatus.offWork && localStart != null -> applyRemoteEnded(own, localStart, now)
            else -> {
                val localSessionId = WorkSessionIds.canonical(currentSessionId)
                val serverSessionId = own.openSession?.id
                if (own.status == WorkStatus.working && serverSessionId != null && serverSessionId != localSessionId) {
                    if (localSessionId == null && startedAt != null) {
                        currentSessionId = serverSessionId
                        confirmedServerSessionId = serverSessionId // 도장 (b)
                    } else if (own.currentSessionStartedAt != null) {
                        adoptRemoteSession(own, now)
                    }
                }
                pendingSync = false
            }
        }
        releaseOwnershipIfAnotherDeviceClaims(own)
        updateAdoptedPresenceTracking(own, now)
        publish()
    }

    private fun applyRemoteEnded(own: TeamMemberStatus, closedSessionStart: SwiftDate, now: SwiftDate) {
        val seen = own.lastSeenAt ?: own.updatedAt
        if (!adoptedRemoteSession && seen != null && now.timeIntervalSince(seen) > WorkStateConstants.ABANDONED_THRESHOLD_SECONDS) {
            recentSessionId = WorkSessionIds.canonical(currentSessionId)
            recentStartedAt = closedSessionStart
            recentEndedAt = seen
            recentReason = AutoCloseReason.ABANDONED
            recentStrength = if (ledger.isOwned(currentSessionId)) ledger.strength else SessionClaimStrength.WEAK
            recentSeconds = maxOf(0L, seen.timeIntervalSince(maxOf(closedSessionStart, TeamWeeklyGoal.koreanDayStart(now))).toLong())
            recentAt = now
            syncMessage = WorkStateConstants.REMOTE_ABANDONED_CLOSE_NOTICE
            events.onWorkEvent(WorkEvent.AutoClosed(AutoCloseReason.ABANDONED, seen))
        } else if (seen != null && now.timeIntervalSince(seen) <= WorkStateConstants.ABANDONED_THRESHOLD_SECONDS) {
            syncMessage = WorkStateConstants.REMOTE_ENDED_ELSEWHERE_NOTICE
            policy.suppressAutoStart(now)
        }
        startedAt = null
        currentSessionId = null
        startOrigin = null
        releaseSessionOwnership()
        longSessionPromptShownAt = null
        policy.onSessionEnded(resetSleepTracking = false)
    }

    private fun adoptRemoteSession(own: TeamMemberStatus, now: SwiftDate) {
        val restoredStart = own.currentSessionStartedAt ?: now
        startedAt = restoredStart
        val resolvedId = own.openSession?.id ?: currentSessionId
        currentSessionId = resolvedId
        val open = own.openSession
        if (open != null && open.id == resolvedId) confirmedServerSessionId = open.id // 도장 (b)
        longSessionPromptShownAt = null
        policy.onSessionAnchored(restoredStart, resetSleepBegan = true, clearSleepMarker = false)
        if (ledger.isOwned(resolvedId)) {
            // 재시작 구제: 영속된 소유 id 가 이 세션 — 강도는 영속된 그대로(세탁 금지).
            claimSessionOwnership(resolvedId, ledger.strength)
            startOrigin = WorkStartOrigin.RESUME
        } else {
            adoptedRemoteSession = true
            startOrigin = WorkStartOrigin.ADOPTED
        }
    }

    /** 백스톱: 흡수 세션의 생존신호가 5분·3회 넘게 멈추면 **약하게** 되찾는다(Swift updateAdoptedPresenceTracking). */
    private fun updateAdoptedPresenceTracking(own: TeamMemberStatus, now: SwiftDate) {
        if (!adoptedRemoteSession || startedAt == null) {
            resetAdoptedPresenceTracking()
            return
        }
        val seen = own.lastSeenAt ?: own.updatedAt
        val sessionId = WorkSessionIds.canonical(currentSessionId)
        val previous = adoptedLastSeenAt
        if (adoptedLastSeenSessionId != sessionId || previous == null) {
            adoptedLastSeenSessionId = sessionId
            adoptedLastSeenAt = seen
            adoptedStallBeganAt = null
            adoptedStallObservations = 0
            return
        }
        if (seen != null && seen > previous) {
            adoptedLastSeenAt = seen
            adoptedStallBeganAt = null
            adoptedStallObservations = 0
            return
        }
        if (seen == null) return
        if (adoptedStallBeganAt == null) adoptedStallBeganAt = now
        adoptedStallObservations += 1
        val stallBeganAt = adoptedStallBeganAt ?: return
        if (adoptedStallObservations < WorkStateConstants.ADOPTED_RECLAIM_MIN_OBSERVATIONS) return
        if (now.timeIntervalSince(stallBeganAt) < WorkStateConstants.ADOPTED_RECLAIM_STALE_SECONDS) return
        if (now.timeIntervalSince(seen) <= WorkStateConstants.ADOPTED_RECLAIM_STALE_SECONDS) return
        val foreignClaimsThisSession = own.deviceClaims.any { claim ->
            claim.deviceID.isNotEmpty() && claim.deviceID != (deviceId ?: "") &&
                WorkSessionIds.canonical(claim.sessionID) == sessionId
        }
        if (foreignClaimsThisSession) return
        claimSessionOwnership(currentSessionId, SessionClaimStrength.WEAK)
        startOrigin = WorkStartOrigin.ADOPTED
    }

    /** ⑯ 다른 기기의 기기 행이 **전진**하고 그 기기에 물러나야 하면 흡수로 내려간다(Swift releaseOwnershipIfAnotherDeviceClaims). */
    private fun releaseOwnershipIfAnotherDeviceClaims(own: TeamMemberStatus) {
        if (adoptedRemoteSession || startedAt == null || own.status != WorkStatus.working) return
        val sessionId = WorkSessionIds.canonical(currentSessionId) ?: return
        if (own.openSession?.id != sessionId) return
        if (foreignDeviceTrackingSessionId != sessionId) {
            foreignDeviceTrackingSessionId = sessionId
            foreignDeviceLastSeenAt.clear()
        }
        val mine = deviceId ?: ""
        var shouldRelease = false
        for (claim in own.deviceClaims) {
            if (claim.deviceID.isEmpty() || claim.deviceID == mine) continue
            if (WorkSessionIds.canonical(claim.sessionID) != sessionId) continue
            val seen = claim.lastSeenAt ?: continue
            val previous = foreignDeviceLastSeenAt[claim.deviceID]
            foreignDeviceLastSeenAt[claim.deviceID] = seen
            if (previous == null || seen <= previous) continue
            if (!WorkClaimRules.yieldsToClaim(claim.deviceID, claim.openedSession, ownsCurrentSessionStrongly, deviceId)) continue
            shouldRelease = true
        }
        if (!shouldRelease) return
        adoptedRemoteSession = true
        startOrigin = WorkStartOrigin.ADOPTED
        ledger.set(null)
        resetAdoptedPresenceTracking()
        resetForeignDeviceTracking()
    }

    // ── 틱·하트비트 계획 ──

    /** ⑭ 입력 관측은 소유 판정보다 앞이다 — 틱·하트비트 계획의 첫 줄(Swift advanceMeaningfulInput 2391). 단조 증가. */
    fun advanceMeaningfulInput(now: SwiftDate = clock()): SwiftDate? {
        val raw = meaningfulInput() ?: return lastMeaningfulInputAt
        val observed = minOf(raw, now)
        val current = lastMeaningfulInputAt
        if (current == null || observed > current) {
            lastMeaningfulInputAt = observed
            publish()
        }
        return lastMeaningfulInputAt
    }

    /**
     * work_tick 인자 4갈래(Swift workTickIfPossible 72-140). 로그인·팀이 없으면 null(조립은 레거시 경로 [planHeartbeat] 로 간다).
     * 게이트(WorkTickAvailability)는 wq 몫 — 조립이 먼저 묻는다.
     */
    fun planWorkTick(now: SwiftDate = clock()): WorkTickArgs? {
        val uid = userId() ?: return null
        val team = teamId() ?: return null
        val observedInput = advanceMeaningfulInput(now)
        var heartbeat = startedAt != null
        var sessionId: String? = null
        var deviceToSend: String? = null
        var openedSession = false
        var lastInputAt: SwiftDate? = null
        if (heartbeat) {
            val confirmed = confirmedSessionId
            when {
                adoptedRemoteSession -> {
                    deviceToSend = deviceId
                    lastInputAt = observedInput
                }
                confirmed != null -> {
                    sessionId = confirmed // ⑬ confirmed 만
                    deviceToSend = deviceId
                    openedSession = ownsCurrentSessionStrongly
                    lastInputAt = observedInput
                }
                currentSessionId != null -> {
                    deviceToSend = deviceId
                    lastInputAt = observedInput
                }
                else -> heartbeat = false
            }
        }
        return WorkTickArgs(team, heartbeat, sessionId, deviceToSend, openedSession, lastInputAt, uid, workStateWriteGeneration)
    }

    /** 레거시 하트비트 계획(Swift sendHeartbeatIfWorking 1093). [awayServerSupported] 가 거짓이면 입력 시각을 싣지 않는다. */
    fun planHeartbeat(awayServerSupported: Boolean, now: SwiftDate = clock()): HeartbeatPlan {
        val observedInput = advanceMeaningfulInput(now)
        if (startedAt == null || userId() == null) return HeartbeatPlan.Skip
        val team = teamId() ?: return HeartbeatPlan.Skip
        val confirmed = confirmedSessionId
        if (adoptedRemoteSession || confirmed == null) {
            val device = deviceId
            if (!awayServerSupported || observedInput == null || device == null) return HeartbeatPlan.Skip
            return HeartbeatPlan.DeviceInputOnly(team, device, observedInput)
        }
        val input = if (awayServerSupported) observedInput else null
        val device = deviceId?.let { DeviceClaimUpsert(it, confirmed, ownsCurrentSessionStrongly, input) }
        return HeartbeatPlan.Beat(team, confirmed, input, device)
    }

    // ── 계정 ──

    /** 계정 전환(Swift adoptWorkStateOwner 4257). 다른 사람의 항목을 큐에서 빼는 일은 wq 큐 몫(C#23 항목별 owner). */
    fun adoptWorkStateOwner(userId: String) {
        val previous = workStateOwnerUserId
        workStateOwnerUserId = userId
        if (previous == null || previous == userId) return
        startedAt = null
        accumulatedSeconds = 0
        accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(clock())
        currentSessionId = null
        startOrigin = null
        lastOwnMember = null
        releaseSessionOwnership()
        longSessionPromptShownAt = null
        policy.onSessionEnded(resetSleepTracking = true)
        clearRecentAutoCloseResume()
        policy.clearAwayState()
        publish()
    }

    // ── 찌르기 사실(조정 ③) ──
    override fun pokeConsumeFacts(): PokeConsumeFacts {
        val own = lastOwnMember?.takeIf { it.id == userId() }
        return PokeConsumeFacts(
            localSessionOpen = startedAt != null,
            adoptedRemoteSession = adoptedRemoteSession,
            canonicalSessionID = WorkSessionIds.canonical(currentSessionId),
            ownOpenSessionID = WorkSessionIds.canonical(own?.openSession?.id),
            ownDeviceClaims = own?.deviceClaims?.map { it.deviceID to WorkSessionIds.canonical(it.sessionID) },
            deviceID = deviceId,
            lastMeaningfulInputAt = lastMeaningfulInputAt,
        )
    }

    // ── 안쪽 ──

    /** Swift syncCurrentStatus 1669 — 항목 하나를 직렬 줄에 넣는다. id 를 만드는 순서(대체 세션 id → 항목 id)도 Swift 와 같다. */
    private fun syncCurrentStatus(
        durationSeconds: Long? = null,
        sessionStartedAt: SwiftDate? = null,
        endedAt: SwiftDate? = null,
        autoCloseReason: AutoCloseReason? = null,
    ) {
        val owner = userId()
        if (owner == null) {
            pendingSync = true
            syncMessage = WorkStateConstants.LOGIN_REQUIRED
            return
        }
        val fallbackSessionId = WorkSessionIds.canonical(newUuid())!!
        val sessionId = currentSessionId ?: fallbackSessionId
        val item = if (startedAt != null) {
            PendingWorkItem(newUuid(), PendingWorkOperation.Start, sessionId, startedAt, null, owner, null)
        } else {
            val duration = durationSeconds ?: currentSnapshot().todaySeconds(endedAt ?: clock())
            PendingWorkItem(newUuid(), PendingWorkOperation.Stop(duration), sessionId, sessionStartedAt, endedAt, owner, autoCloseReason)
        }
        pendingSync = true
        queue.enqueue(item)
    }

    private fun claimSessionOwnership(sessionId: String?, strength: SessionClaimStrength) {
        adoptedRemoteSession = false
        resetAdoptedPresenceTracking()
        resetForeignDeviceTracking()
        ledger.set(sessionId, strength)
    }

    private fun releaseSessionOwnership() {
        adoptedRemoteSession = false
        resetAdoptedPresenceTracking()
        resetForeignDeviceTracking()
        ledger.set(null)
        confirmedServerSessionId = null
    }

    private fun resetAdoptedPresenceTracking() {
        adoptedLastSeenAt = null
        adoptedLastSeenSessionId = null
        adoptedStallBeganAt = null
        adoptedStallObservations = 0
    }

    private fun resetForeignDeviceTracking() {
        foreignDeviceLastSeenAt.clear()
        foreignDeviceTrackingSessionId = null
    }

    private fun clearRecentAutoCloseResume() {
        recentSessionId = null
        recentStartedAt = null
        recentAt = null
        recentEndedAt = null
        recentReason = null
        recentSeconds = 0
        recentStrength = SessionClaimStrength.WEAK
    }

    private fun currentSnapshot(): DesktopWorkSnapshot {
        val sessionId = recentSessionId
        val reason = recentReason
        val endedAt = recentEndedAt
        val lastAutoClose = if (sessionId != null && reason != null && endedAt != null) {
            LastAutoClose(sessionId, reason, endedAt, recentSeconds)
        } else {
            null
        }
        return DesktopWorkSnapshot(
            isWorking = startedAt != null,
            startedAt = startedAt,
            sessionId = WorkSessionIds.canonical(currentSessionId),
            confirmedSessionId = confirmedSessionId,
            adopted = adoptedRemoteSession,
            ownsStrongly = ownsCurrentSessionStrongly,
            accumulatedTodaySeconds = accumulatedSeconds,
            accumulatedDayStart = accumulatedDayStart,
            lastMeaningfulInputAt = lastMeaningfulInputAt,
            pendingSync = pendingSync,
            syncMessage = syncMessage,
            longSessionPromptShownAt = longSessionPromptShownAt,
            lastAutoClose = lastAutoClose,
            startOrigin = if (startedAt != null) startOrigin else null,
        )
    }

    private fun publish() {
        state.value = currentSnapshot()
    }
}
