// 조정자 핀(W-windows-resume W-3·xplat-w2/pins.md) — 갈래는 읽기만
// 출처: xplat-w1/briefs/work.md §4 + pins.md A 조정 ①②③. 시간 타입은 core 관례 SwiftDate 하나(조정 ⑥).
// 바꿀 일이 생기면 고치지 말고 완료 보고의 coordinator_patches 에 적는다.
package com.yehsung.aingcheck.feature.desktop.work

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeConsumeFacts
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** C#22 세션 id 정규화 — 모든 갈래 공용(Swift canonicalSessionID). */
object WorkSessionIds {
    fun canonical(raw: String?): String? = raw?.lowercase()
}

enum class AutoCloseReason(val raw: String) { AWAY("away"), SLEEP("sleep"), LONG_SESSION("long_session"), ABANDONED("abandoned") }

sealed interface PendingWorkOperation {
    data object Start : PendingWorkOperation
    data class Stop(val durationSeconds: Long) : PendingWorkOperation
}

data class PendingWorkItem(
    val id: String,
    val operation: PendingWorkOperation,
    val sessionId: String,
    val sessionStartedAt: SwiftDate?,
    val endedAt: SwiftDate?,
    val ownerUserId: String?,
    val autoCloseReason: AutoCloseReason?,
)

/** ws(W2-g5) 가 구현, wq(W2-g1) 해소기가 읽는다. */
interface WorkQueueHost {
    /** null → "소속 팀이 없어요 — 팀 코드로 참여해 주세요". */
    val currentTeamId: String?
    /** 해소기 시작 값과 다르면 SessionAlreadyOpen 으로 되던진다. */
    val workStateWriteGeneration: Int
    /** Swift: startedAt != nil 일 때만 canonical(currentSessionID). */
    val liveSessionId: String?
    /** 도장 (a)·blocker==mine 이면 id, (3-b)면 null. */
    fun setConfirmedServerSessionId(id: String?)
    suspend fun awaitWakeGate()
    suspend fun onDrained()
    fun onSyncFailed(message: String)
}

/** wq(W2-g1) 가 구현. */
interface WorkQueue {
    val items: StateFlow<List<PendingWorkItem>>
    /** 직렬 체인(Swift enqueueSync). */
    fun enqueue(item: PendingWorkItem)
    /** finishWorkBeforeQuit: 먼저 오는 쪽, 진 쪽은 취소하지 않는다. */
    suspend fun awaitIdle(timeoutMillis: Long)
    /** 5분 스로틀 한 칸(해소기 (2) · 팀 스캐빈저 공용). */
    val scavenge: ScavengeThrottle
}

fun interface ScavengeThrottle {
    fun tryAcquire(now: SwiftDate): Boolean
}

/** ws 가 구현, wp(W2-g6) 가 부른다(잠자기·12h·away·마커 정정). */
interface WorkAutoClose {
    /** 근무 중이 아니거나 흡수 세션이면 no-op. 세대↑·회계·큐 Stop(reason)·소유 해제를 한 번에. */
    fun closeOwnedSessionLocally(endedAt: SwiftDate, reason: AutoCloseReason, message: String)
}

/** 트레이·근무 페이지·찌르기·wp 가 읽는다. */
interface DesktopWorkState {
    val snapshot: StateFlow<DesktopWorkSnapshot>
}

/** 조정 ①: 이번 근무가 어떻게 시작됐나(오버레이 넛지 안내 8초 — overlay.md I-8). 근무 중이 아니면 null. */
enum class WorkStartOrigin { MANUAL, NUDGE, RESUME, ADOPTED }

data class DesktopWorkSnapshot(
    val isWorking: Boolean = false,
    val startedAt: SwiftDate? = null,
    val sessionId: String? = null,
    val confirmedSessionId: String? = null,
    val adopted: Boolean = false,
    val ownsStrongly: Boolean = false,
    val accumulatedTodaySeconds: Long = 0,
    val accumulatedDayStart: SwiftDate? = null,
    val lastMeaningfulInputAt: SwiftDate? = null,
    val pendingSync: Boolean = false,
    val syncMessage: String? = null,
    val longSessionPromptShownAt: SwiftDate? = null,
    val lastAutoClose: LastAutoClose? = null,
    val startOrigin: WorkStartOrigin? = null,
) {
    /** 현재 근무 경과(초). 근무 중이 아니면 0, 시계 되돌림 음수는 0. */
    fun elapsedSeconds(now: SwiftDate): Long {
        val start = startedAt ?: return 0
        if (!isWorking) return 0
        return maxOf(0L, now.timeIntervalSince(start).toLong())
    }

    /** Swift WorkTimerStore.todayDuration(at:) 1835 — 누적은 스탬프가 KST 오늘이면만, 진행 세션은 KST 자정으로 자른다. */
    fun todaySeconds(now: SwiftDate): Long {
        val dayStart = TeamWeeklyGoal.koreanDayStart(now)
        val stamp = accumulatedDayStart
        val accumulated = if (stamp != null && stamp >= dayStart) accumulatedTodaySeconds else 0L
        val start = startedAt ?: return accumulated
        val effectiveStart = maxOf(start, dayStart)
        return accumulated + maxOf(0L, now.timeIntervalSince(effectiveStart).toLong())
    }
}

data class LastAutoClose(val sessionId: String, val reason: AutoCloseReason, val endedAt: SwiftDate, val seconds: Long)

interface DesktopWorkCommands {
    fun toggle()
    fun start()
    fun stop()
    fun confirmStillWorking()
    fun resumeRecentlyClosed()
}

/** wp 구현, 울트라 갈래가 응답을 매핑해 부른다. */
fun interface LapWalletJudgment {
    fun judge(grants: List<LapGrant>, streakDays: Int): LapOutcome
}

data class LapGrant(val grantedNow: Boolean, val lapsGranted: Int)

data class LapOutcome(val celebrate: Boolean, val lapsToday: Int, val streakDays: Int)

/** 조정 ②: 근무 갈래(ws·wp)가 내고 오버레이·알림이 받는다(조립 때 연결). 1·4시간 마일스톤·팀 주간 목표 달성은 wp 가 판정한다. */
sealed interface WorkEvent {
    data class Milestone(val hours: Int) : WorkEvent
    data object TeamGoalAchieved : WorkEvent
    data object NudgeStarted : WorkEvent
    data class AutoClosed(val reason: AutoCloseReason, val at: SwiftDate) : WorkEvent
    data class LapCelebrated(val lapsToday: Int, val streakDays: Int) : WorkEvent
}

fun interface WorkEventSink {
    fun onWorkEvent(e: WorkEvent)

    companion object {
        /** 받는 쪽이 아직 없을 때(조립 전·시험). */
        val NONE: WorkEventSink = WorkEventSink { }
    }
}

/** 조정 ③: ws 가 구현(팀원 행의 deviceClaims 포함, 정규화 끝난 값). 읽을 때마다 최신. */
fun interface PokeFactsSource {
    fun pokeConsumeFacts(): PokeConsumeFacts
}

/** 최소 구현 — 시험·조립 전 자리. 실구현은 ws(W2-g5). */
class InMemoryDesktopWorkState(initial: DesktopWorkSnapshot = DesktopWorkSnapshot()) : DesktopWorkState {
    private val state = MutableStateFlow(initial)
    override val snapshot: StateFlow<DesktopWorkSnapshot> = state.asStateFlow()
    fun set(value: DesktopWorkSnapshot) {
        state.value = value
    }
}
