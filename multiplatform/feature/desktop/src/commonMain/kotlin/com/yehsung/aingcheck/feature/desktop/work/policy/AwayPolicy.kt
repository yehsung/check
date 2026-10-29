// 원본: Sources/check/WorkTimerStore.swift 2391-2470(advanceMeaningfulInput · awayLastInputAt · evaluateAwaySession · awayCloseSchedule)
//       · Sources/check/WorkTimerStoreSync.swift 1200-1255(away_sync 스로틀 120초 · 실패 접기) · 1255-1340(방치 자가 마감 판정)
//       · 1360-1395(30분 자동 재개 판정) @ a90d8623
// W2-g6(wp) 자리 비움 · 30분 재개 · 방치 자가 마감 — 판정만. away_sync HTTP·stopWork·reopen 은 wq/ws 가 내고 결과를 여기 넘긴다.
package com.yehsung.aingcheck.feature.desktop.work.policy

import com.yehsung.aingcheck.core.foundation.platform.desktop.IdleSource
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.feature.desktop.work.AutoCloseReason
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkState
import com.yehsung.aingcheck.feature.desktop.work.WorkAutoClose
import com.yehsung.aingcheck.feature.desktop.work.WorkSessionIds
import kotlin.time.ExperimentalTime
import kotlin.time.Instant

@OptIn(ExperimentalTime::class)
fun Instant.toSwiftDate(): SwiftDate = SwiftDate.fromEpochMillis(toEpochMilliseconds())

/**
 * 마지막 **의미 있는** 입력 시각(단조 증가). Swift advanceMeaningfulInput 2391.
 * 전진하지 않는 경우: 잠금·비콘솔([sessionUsable] 거짓) · 관측 없음 · 뒤로 가는 값. 미래 시각은 지금으로 누른다.
 */
class MeaningfulInputTracker(
    private val idle: IdleSource,
    private val sessionUsable: () -> Boolean,
    private val rules: WorkPolicyRules = WorkPolicyRules.Standard,
) {
    var lastMeaningfulInputAt: SwiftDate? = null
        private set

    @OptIn(ExperimentalTime::class)
    fun advance(now: SwiftDate): SwiftDate? {
        if (!sessionUsable()) return lastMeaningfulInputAt
        val seen = idle.lastInput(rules.meaningfulInputKinds) ?: return lastMeaningfulInputAt
        val observed = minOf(seen.toSwiftDate(), now)
        val current = lastMeaningfulInputAt
        if (current == null || observed > current) lastMeaningfulInputAt = observed
        return lastMeaningfulInputAt
    }

    fun reset() {
        lastMeaningfulInputAt = null
    }
}

/** away_sync 응답의 열린 세션 조각. closeEligible 이 없으면(null) 마감하지 않는다(㉒). */
data class AwayOpenSession(val sessionId: String?, val closeEligible: Boolean?, val lastInputAt: SwiftDate?)

/** wq 의 away_sync 결과를 정책에 넘기는 모양. */
sealed interface AwaySyncResult {
    data class Ok(val closeThresholdSeconds: Double?, val openSession: AwayOpenSession?) : AwaySyncResult
    /** 마이그레이션 전 서버(AwaySyncUnavailable) — 정책도 새 컬럼 전송도 끈다. */
    data object Unavailable : AwaySyncResult
    /** 네트워크 실패·취소 — 판정 재료만 무효화(모를 때의 안전한 기본값은 "안 끊는다"). */
    data object Failed : AwaySyncResult
}

/**
 * 자리 비움 자동 마감(Swift evaluateAwaySession · awayCloseSchedule). 여섯 가드를 **전부** 통과할 때만 [schedule] 이 값이 있다:
 * 흡수 아님(㉓) · 근무 중 · 서버 임계 > 0(㉒) · closeEligible == true · 서버가 든 세션 id == 내 세션 id · start ≤ lastInput.
 * 마감 시각 = lastInput(소급), 사유 away.
 */
class AwayPolicy(
    private val state: DesktopWorkState,
    private val autoClose: WorkAutoClose,
    private val input: MeaningfulInputTracker,
    private val rules: WorkPolicyRules = WorkPolicyRules.Standard,
) {
    data class Schedule(val lastInput: SwiftDate, val thresholdSeconds: Double)

    var serverSupported: Boolean = false
        private set
    var closeThresholdSeconds: Double? = null
        private set
    var openSession: AwayOpenSession? = null
        private set
    private var lastSyncAt: SwiftDate? = null

    /** 근무 중이면 매 폴링, 비근무면 120초 스로틀. 로그아웃이면 통째로 비우고 false. 참이면 호출자가 away_sync 를 낸다. */
    fun shouldSync(now: SwiftDate, signedIn: Boolean): Boolean {
        if (!signedIn) {
            clear()
            return false
        }
        val last = lastSyncAt
        if (!state.snapshot.value.working && last != null &&
            now.timeIntervalSince(last) < WorkPolicyConstants.AWAY_SYNC_IDLE_THROTTLE_SECONDS
        ) {
            return false
        }
        lastSyncAt = now
        return true
    }

    fun apply(result: AwaySyncResult) {
        when (result) {
            is AwaySyncResult.Ok -> {
                serverSupported = true
                closeThresholdSeconds = result.closeThresholdSeconds?.takeIf { it > 0 }
                openSession = result.openSession
            }
            AwaySyncResult.Unavailable -> {
                serverSupported = false
                closeThresholdSeconds = null
                openSession = null
            }
            AwaySyncResult.Failed -> {
                closeThresholdSeconds = null
                openSession = null
            }
        }
    }

    /** 기준 = max(로컬 관측, 서버가 계산한 내 모든 기기 행의 max) — 한쪽만 보면 "다른 기기에서 작업"이 오마감된다. */
    fun lastInputAt(): SwiftDate? =
        listOfNotNull(state.snapshot.value.lastMeaningfulInputAt, input.lastMeaningfulInputAt, openSession?.lastInputAt).maxOrNull()

    fun schedule(): Schedule? {
        val snap = state.snapshot.value
        if (rules.excludesFromAutoClose(snap)) return null
        if (!snap.working) return null
        val threshold = closeThresholdSeconds ?: return null
        val open = openSession ?: return null
        if (open.closeEligible != true) return null
        val local = WorkSessionIds.canonical(snap.sessionId) ?: return null
        if (WorkSessionIds.canonical(open.sessionId) != local) return null
        val last = lastInputAt() ?: return null
        val start = snap.startedAt ?: return null
        if (start > last) return null
        return Schedule(last, threshold)
    }

    /** 근무 틱마다(12시간보다 **먼저** — 더 이른 시각이고 되살릴 수 있는 사유). 마감했으면 true. */
    fun evaluate(now: SwiftDate): Boolean {
        schedule() ?: return false
        // ★ 판정 직전에 로컬 관측을 전진시킨다 — 임계 직전에 돌아와 타이핑한 사람을 끊지 않게.
        input.advance(now)
        val s = schedule() ?: return false
        if (!rules.awayExceeded(now, s.lastInput, s.thresholdSeconds)) return false
        autoClose.closeOwnedSessionLocally(s.lastInput, AutoCloseReason.AWAY, WorkPolicyConstants.MESSAGE_AWAY)
        return true
    }

    fun clear() {
        input.reset()
        serverSupported = false
        closeThresholdSeconds = null
        openSession = null
        lastSyncAt = null
    }
}

/**
 * 자동 재개(30분 창)의 판정자(Swift canResumeRecentlyClosedSession 1375). 앵커는 마감이 발화한 시각이 아니라 **ended_at** —
 * 되살아나는 양이 `지금 − ended_at` 이라 재계상 상한이 구조적으로 30분이다. long_session 은 재개하지 않는다(12시간 상한 보존).
 */
object RecentAutoCloseResume {
    fun canResume(snapshot: DesktopWorkSnapshot, now: SwiftDate): Boolean {
        val last = snapshot.lastAutoClose ?: return false
        if (snapshot.isWorking || snapshot.startedAt != null) return false
        if (last.reason == AutoCloseReason.LONG_SESSION) return false
        val gap = now.timeIntervalSince(last.endedAt)
        // 음수 갭(시계 되돌림)은 "모른다" — 미래에 끝난 세션을 되살리지 않는다.
        return gap >= 0 && gap <= WorkPolicyConstants.RECENT_AUTO_CLOSE_RESUME_WINDOW_SECONDS
    }
}

/** 방치 자가 마감 판정 결과(Sync:1255). endedAt = 마지막 신호, 오늘 몫은 KST 자정으로 자른다. */
data class AbandonedSelfClose(val endedAt: SwiftDate, val durationSeconds: Long, val closedTodaySeconds: Long)

/**
 * 서버상 내 세션이 열려 있고 로컬은 비근무 · 큐 비어 있음 · 마지막 신호 공백 > 7분이면 그 세션을 마지막 신호 시각으로 닫는다.
 * 네트워크만 끊긴 채 로컬이 일하던 경우(로컬 근무 중)는 절대 닫지 않는다. stopWork 호출·회계는 ws.
 */
object AbandonedOwnSessionClose {
    fun decide(
        localWorking: Boolean,
        queueEmpty: Boolean,
        hasTeam: Boolean,
        ownRowWorking: Boolean,
        ownRowSessionStartedAt: SwiftDate?,
        ownRowLastSignalAt: SwiftDate?,
        now: SwiftDate,
    ): AbandonedSelfClose? {
        if (localWorking || !queueEmpty || !hasTeam || !ownRowWorking) return null
        val start = ownRowSessionStartedAt ?: return null
        val seen = ownRowLastSignalAt ?: return null
        if (now.timeIntervalSince(seen) <= WorkPolicyConstants.ADOPTED_RECLAIM_STALE_SECONDS) return null
        val dayStart = TeamWeeklyGoal.koreanDayStart(now)
        return AbandonedSelfClose(
            endedAt = seen,
            durationSeconds = maxOf(0L, seen.timeIntervalSince(start).toLong()),
            closedTodaySeconds = maxOf(0L, seen.timeIntervalSince(maxOf(start, dayStart)).toLong()),
        )
    }
}
