// 원본: Sources/check/WorkTimerStore.swift 3487-3522(1h/4h 마일스톤 · 3h 랩) · 3540-3555(ultraLapKey) · Sources/CheckCore/MilestoneTracker.swift 50-130
//       · Sources/check/WorkTimerStorePoke.swift 339-356(granted_now 만 축하) · Sources/check/WorkTimerStoreSync.swift 360-390(팀 주간 목표 달성) @ a90d8623
// W2-g6(wp) 마일스톤 · 랩 · 팀 목표 달성(W-3 #12 — WorkEventSink 로 낸다).
package com.yehsung.aingcheck.feature.desktop.work.lap

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.feature.desktop.work.LapGrant
import com.yehsung.aingcheck.feature.desktop.work.LapOutcome
import com.yehsung.aingcheck.feature.desktop.work.LapWalletJudgment
import com.yehsung.aingcheck.feature.desktop.work.WorkEvent
import com.yehsung.aingcheck.feature.desktop.work.WorkEventSink
import com.yehsung.aingcheck.feature.desktop.work.policy.WorkPolicyRules
import kotlin.math.floor

/**
 * ㉕ 랩 n(누적 3·6·9시간…)의 스로틀 키. 랩 1은 옛 "hour3" 그대로(장부 연속성), 2부터 "hour3.lap<n>".
 * 하루 1개 키로 접으면 랩 2·3·4 가 근무 중 5분 sync 까지 밀린다.
 */
fun ultraLapKey(lap: Long): String = if (lap <= 1) MilestoneTracker.HOUR_THREE_KEY else "hour3.lap$lap"

/** KST(UTC+9, 1988 이후 일광절약 없음) 그날의 "yyyyMMdd" — Swift MilestoneTracker.dayKey. */
object KstDayKey {
    fun of(date: SwiftDate): String {
        val days = (floor(date.timeIntervalSince1970).toLong() + 9 * 3600).floorDiv(86_400L)
        // civil_from_days(H. Hinnant) — 1970-01-01 기준 일수 → 그레고리력.
        val z = days + 719_468
        val era = z.floorDiv(146_097L)
        val doe = z - era * 146_097
        val yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        val doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        val mp = (5 * doy + 2) / 153
        val d = doy - (153 * mp + 2) / 5 + 1
        val m = if (mp < 10) mp + 3 else mp - 9
        val y = yoe + era * 400 + if (m <= 2) 1 else 0
        return y.toString().padStart(4, '0') + m.toString().padStart(2, '0') + d.toString().padStart(2, '0')
    }
}

/** 마일스톤 1일 1회 기록기 — "check.milestone.<키>.<yyyyMMdd(KST)>" 를 데스크톱 KeyValueStore 에 남긴다. */
class MilestoneTracker(private val store: DesktopKeyValueStore) {
    private val firedThisSession = HashSet<String>()

    /** 오늘(KST) 아직 안 터진 키면 기록하고 true. 하루가 지나면 다시 true. */
    fun fireIfNeeded(key: String, now: SwiftDate): Boolean {
        val k = storeKey(key, KstDayKey.of(now))
        if (k in firedThisSession) return false
        if (store.getBoolean(k) == true) {
            firedThisSession.add(k)
            return false
        }
        store.putBoolean(k, true)
        firedThisSession.add(k)
        return true
    }

    companion object {
        const val HOUR_ONE_KEY: String = "hour1"
        const val HOUR_FOUR_KEY: String = "hour4"
        const val HOUR_THREE_KEY: String = "hour3"
        const val TEAM_GOAL_KEY: String = "teamGoal"
        const val FIRST_ARRIVAL_KEY: String = "firstArrival"

        fun storeKey(key: String, day: String): String = "check.milestone.$key.$day"
    }
}

/**
 * 근무 틱마다: 오늘 누적이 1h/4h 를 넘는 순간 [WorkEvent.Milestone](키별 1일 1회. 4h 로 처음 관측되면 1h 는 조용히 소비).
 * 3h 랩은 **축하하지 않는다** — 받았는지는 서버가 안다. [onLapCandidate] 로 지갑 sync 만 부른다(DesktopSocialLifecycle.onLapCrossed).
 */
class TimeMilestones(
    private val tracker: MilestoneTracker,
    private val events: WorkEventSink,
    private val onLapCandidate: (lap: Long) -> Unit,
    private val rules: WorkPolicyRules = WorkPolicyRules.Standard,
) {
    fun evaluate(snapshot: DesktopWorkSnapshot, now: SwiftDate, missionWorkSeconds: Long = MISSION_WORK_SECONDS_HINT) {
        if (!snapshot.isWorking || snapshot.startedAt == null) return
        val today = snapshot.todaySeconds(now)
        if (today >= HOUR_FOUR_SECONDS) {
            if (tracker.fireIfNeeded(MilestoneTracker.HOUR_FOUR_KEY, now)) events.onWorkEvent(WorkEvent.Milestone(4))
            tracker.fireIfNeeded(MilestoneTracker.HOUR_ONE_KEY, now)
        } else if (today >= HOUR_ONE_SECONDS) {
            if (tracker.fireIfNeeded(MilestoneTracker.HOUR_ONE_KEY, now)) events.onWorkEvent(WorkEvent.Milestone(1))
        }
        // 서버 target 이 0·음수면 랩 0(0 나눗셈 금지).
        val lap = if (missionWorkSeconds > 0) today / missionWorkSeconds else 0L
        if (lap >= 1 && tracker.fireIfNeeded(rules.lapKey(lap), now)) onLapCandidate(lap)
    }

    companion object {
        const val HOUR_ONE_SECONDS: Long = 3_600
        const val HOUR_FOUR_SECONDS: Long = 4 * 3_600
        /** MissionProgress.defaultTargetSeconds — 서버 target 이 오기 전 값. */
        const val MISSION_WORK_SECONDS_HINT: Long = 3 * 3_600
    }
}

/**
 * ㉕ 지갑 sync 응답 판정(LapWalletJudgment 구현). granted_now 가 **유일한** 축하 트리거 — claimed 는 5분마다 참이라 쓰면 연출이 반복된다.
 * 오늘 받은 랩 수 = granted_now 행들의 lapsGranted 최대(0 은 랩 이전 서버 → 1).
 */
object LapWalletJudge : LapWalletJudgment {
    override fun judge(grants: List<LapGrant>, streakDays: Int): LapOutcome {
        val granted = grants.filter { it.grantedNow }
        if (granted.isEmpty()) return LapOutcome(celebrate = false, lapsToday = 0, streakDays = streakDays)
        return LapOutcome(celebrate = true, lapsToday = maxOf(1, granted.maxOf { it.lapsGranted }), streakDays = streakDays)
    }
}

/** 울트라 갈래가 응답을 매핑해 부른다. 축하면 [WorkEvent.LapCelebrated] 를 낸다. */
class LapCelebration(
    private val events: WorkEventSink,
    private val judgment: LapWalletJudgment = LapWalletJudge,
) {
    fun onWalletSynced(grants: List<LapGrant>, streakDays: Int): LapOutcome {
        val outcome = judgment.judge(grants, streakDays)
        if (outcome.celebrate) events.onWorkEvent(WorkEvent.LapCelebrated(outcome.lapsToday, outcome.streakDays))
        return outcome
    }
}

/**
 * 팀 주간 목표 100% 돌파(Sync:378). 1인당 평균(총합 ÷ 인원)으로 판정하고, 첫 관측은 전이로 치지 않는다. 미완료→완료 순간에만, 1일 1회.
 */
class TeamGoalDetector(
    private val tracker: MilestoneTracker,
    private val events: WorkEventSink,
) {
    private var previous: Boolean? = null

    fun observe(weeklyAverageSeconds: Long, goalSeconds: Long, now: SwiftDate): Boolean {
        val complete = TeamWeeklyGoal(weeklyAverageSeconds, goalSeconds).isComplete
        val fired = previous == false && complete && tracker.fireIfNeeded(MilestoneTracker.TEAM_GOAL_KEY, now)
        previous = complete
        if (fired) events.onWorkEvent(WorkEvent.TeamGoalAchieved)
        return fired
    }

    /** 로그아웃·팀 전환 — 다음 관측을 다시 첫 관측으로. */
    fun reset() {
        previous = null
    }
}
