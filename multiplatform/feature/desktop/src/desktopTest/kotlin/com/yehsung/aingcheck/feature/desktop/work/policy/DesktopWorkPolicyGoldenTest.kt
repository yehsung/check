// 원본: Tests/checkTests/GoldenExport/desktop-work-policy/GoldenExportDesktopWorkPolicy.swift(골든) ·
//       Tests/checkTests/{AwayCloseTests,V0236StoreTests,CheckNudgeTests,NudgeAutoStartContractTests}.swift(시나리오를 본떴다) @ a90d8623
// W2-g6(wp) 완료 기준 — 골든 대조 + 시나리오 + negative_*(규칙 하나를 깬 변형을 넣으면 같은 판정이 빨강이 된다).
// 규약 번호 ⑰~㉕ 는 xplat-w1/briefs/work.md §2 의 번호다. 픽스처는 전부 합성(실제 홈·로그·계정 0).
@file:OptIn(ExperimentalTime::class)

package com.yehsung.aingcheck.feature.desktop.work.policy

import com.yehsung.aingcheck.core.foundation.platform.desktop.IdleSource
import com.yehsung.aingcheck.core.foundation.platform.desktop.InputKind
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvent
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.work.AutoCloseReason
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.feature.desktop.work.InMemoryDesktopWorkState
import com.yehsung.aingcheck.feature.desktop.work.LapGrant
import com.yehsung.aingcheck.feature.desktop.work.LastAutoClose
import com.yehsung.aingcheck.feature.desktop.work.PendingWorkItem
import com.yehsung.aingcheck.feature.desktop.work.PendingWorkOperation
import com.yehsung.aingcheck.feature.desktop.work.ScavengeThrottle
import com.yehsung.aingcheck.feature.desktop.work.WorkAutoClose
import com.yehsung.aingcheck.feature.desktop.work.WorkEvent
import com.yehsung.aingcheck.feature.desktop.work.WorkEventSink
import com.yehsung.aingcheck.feature.desktop.work.WorkQueue
import com.yehsung.aingcheck.feature.desktop.work.WorkStartOrigin
import com.yehsung.aingcheck.feature.desktop.work.lap.KstDayKey
import com.yehsung.aingcheck.feature.desktop.work.lap.LapCelebration
import com.yehsung.aingcheck.feature.desktop.work.lap.LapWalletJudge
import com.yehsung.aingcheck.feature.desktop.work.lap.MilestoneTracker
import com.yehsung.aingcheck.feature.desktop.work.lap.TeamGoalDetector
import com.yehsung.aingcheck.feature.desktop.work.lap.TimeMilestones
import com.yehsung.aingcheck.feature.desktop.work.lap.ultraLapKey
import com.yehsung.aingcheck.feature.desktop.work.nudge.AutoStartSuppression
import com.yehsung.aingcheck.feature.desktop.work.nudge.NudgeAction
import com.yehsung.aingcheck.feature.desktop.work.nudge.NudgeAutoStarter
import com.yehsung.aingcheck.feature.desktop.work.nudge.NudgeScheduler
import com.yehsung.aingcheck.feature.desktop.work.nudge.SessionUsability
import com.yehsung.aingcheck.feature.desktop.work.nudge.meaningfulIdleSeconds
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.long
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlin.math.roundToLong
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.ExperimentalTime
import kotlin.time.Instant

class DesktopWorkPolicyGoldenTest {
    // ---------- 가짜 ----------

    private class Close(val endedAt: SwiftDate, val reason: AutoCloseReason, val message: String)

    /** ws 관문 대역 — 흡수 세션도 **그대로 기록한다**(wp 자신의 ㉓ 가드를 재기 위해). */
    private class RecordingAutoClose : WorkAutoClose {
        val calls = ArrayList<Close>()
        override fun closeOwnedSessionLocally(endedAt: SwiftDate, reason: AutoCloseReason, message: String) {
            calls += Close(endedAt, reason, message)
        }
    }

    private class FakeQueue(private val idleForever: Boolean = true) : WorkQueue {
        private val flow = MutableStateFlow<List<PendingWorkItem>>(emptyList())
        override val items: StateFlow<List<PendingWorkItem>> = flow
        var awaitCalls = 0
        override fun enqueue(item: PendingWorkItem) {
            flow.value = flow.value + item
        }
        override suspend fun awaitIdle(timeoutMillis: Long) {
            awaitCalls++
            if (idleForever) awaitCancellation()
        }
        override val scavenge: ScavengeThrottle = ScavengeThrottle { true }
    }

    private class FakeIdle : IdleSource {
        val last = HashMap<InputKind, SwiftDate>()
        override fun lastInput(kinds: Set<InputKind>): Instant? =
            kinds.mapNotNull { last[it] }.maxOrNull()?.let { Instant.fromEpochMilliseconds((it.timeIntervalSince1970 * 1000).roundToLong()) }
        override fun addListener(listener: (kind: InputKind, at: Instant) -> Unit): Registration = Registration { }
    }

    private class Events : WorkEventSink {
        val seen = ArrayList<WorkEvent>()
        override fun onWorkEvent(e: WorkEvent) {
            seen += e
        }
    }

    private companion object {
        val T0 = SwiftDate(1_790_000_000.0)
        const val SID = "6f1c2a9e-0000-4000-8000-00000000abcd"
        fun at(seconds: Double): SwiftDate = T0.addingTimeInterval(seconds)
        fun working(start: SwiftDate = T0, lastInput: SwiftDate? = null, adopted: Boolean = false, sessionId: String = SID) =
            DesktopWorkSnapshot(isWorking = true, startedAt = start, sessionId = sessionId, adopted = adopted, lastMeaningfulInputAt = lastInput)
        fun ms(d: SwiftDate): Long = (d.timeIntervalSince(T0) * 1000).roundToLong()
    }

    // ---------- 골든 ----------

    @Test
    fun golden_constants_match_swift() {
        val g = Golden.load("desktop-work-policy/constants")
        val kotlin: Map<String, String> = mapOf(
            "sleepGraceSeconds" to WorkPolicyConstants.SLEEP_GRACE_SECONDS.toLong().toString(),
            "heartbeatIntervalSeconds" to WorkPolicyConstants.HEARTBEAT_INTERVAL_SECONDS.toLong().toString(),
            "adoptedReclaimStaleSeconds" to WorkPolicyConstants.ADOPTED_RECLAIM_STALE_SECONDS.toLong().toString(),
            "longSessionThresholdSeconds" to WorkPolicyConstants.LONG_SESSION_THRESHOLD_SECONDS.toLong().toString(),
            "longSessionResponseWindowSeconds" to WorkPolicyConstants.LONG_SESSION_RESPONSE_WINDOW_SECONDS.toLong().toString(),
            "recentAutoCloseResumeWindowSeconds" to WorkPolicyConstants.RECENT_AUTO_CLOSE_RESUME_WINDOW_SECONDS.toLong().toString(),
            "awaySyncIdleThrottleSeconds" to WorkPolicyConstants.AWAY_SYNC_IDLE_THROTTLE_SECONDS.toLong().toString(),
            "milestoneHourOneSeconds" to TimeMilestones.HOUR_ONE_SECONDS.toString(),
            "milestoneHourFourSeconds" to TimeMilestones.HOUR_FOUR_SECONDS.toString(),
            "missionWorkSecondsHint" to TimeMilestones.MISSION_WORK_SECONDS_HINT.toString(),
            "nudgeCheckInterval" to NudgeScheduler.CHECK_INTERVAL_SECONDS.toLong().toString(),
            "nudgeActiveIdleThreshold" to NudgeScheduler.ACTIVE_IDLE_THRESHOLD_SECONDS.toLong().toString(),
            "nudgeRequiredActiveMinutes" to NudgeScheduler.REQUIRED_ACTIVE_MINUTES.toString(),
            "nudgeActiveWindowSeconds" to NudgeScheduler.ACTIVE_WINDOW_SECONDS.toLong().toString(),
            "nudgeCooldownSeconds" to NudgeScheduler.COOLDOWN_SECONDS.toLong().toString(),
            "nudgeRearmGapSeconds" to NudgeScheduler.REARM_GAP_SECONDS.toLong().toString(),
            "pendingSleepCloseKey" to SleepCloseMarkerStore.KEY,
            "autoStartSuppressedKey" to AutoStartSuppression.SUPPRESSED_KEY,
            "nudgeLastAliveAtKey" to AutoStartSuppression.LAST_ALIVE_KEY,
            "milestoneHourOneKey" to MilestoneTracker.HOUR_ONE_KEY,
            "milestoneHourFourKey" to MilestoneTracker.HOUR_FOUR_KEY,
            "milestoneHourThreeKey" to MilestoneTracker.HOUR_THREE_KEY,
            "milestoneTeamGoalKey" to MilestoneTracker.TEAM_GOAL_KEY,
            "milestoneFirstArrivalKey" to MilestoneTracker.FIRST_ARRIVAL_KEY,
        )
        // 이름 누락 단언: 골든의 모든 상수가 Kotlin 표에 있고, 그 반대도.
        assertEquals(g.cases.map { it.string("id") }.toSet(), kotlin.keys, g.failure("*", "상수 이름 집합"))
        for (case in g.cases) {
            val id = case.string("id")
            assertEquals(case["value"]!!.jsonPrimitive.content, kotlin.getValue(id), g.failure(id, "값"))
        }
    }

    /** Swift 각본을 Kotlin NudgeScheduler 로 그대로 몬다 — 걸음마다 누적 발동·적립·쿨다운·공백·생존이 같아야 한다. */
    private fun replayNudge(case: JsonObject): List<String> {
        var now = T0
        var idle = Double.POSITIVE_INFINITY
        var eligible = true
        var usable = true
        var nudges = 0
        var gaps = 0
        var alive = 0
        val s = NudgeScheduler(
            idleSeconds = { idle }, clock = { now }, isEligible = { eligible }, onNudge = { nudges++ },
            isSessionUsable = { usable }, onAbsenceGap = { gaps++ }, onAliveTick = { alive++ },
        )
        return case["steps"]!!.jsonArray.map { stepEl ->
            val step = stepEl.jsonObject
            now = T0.addingTimeInterval(step.long("atMs") / 1000.0)
            idle = step["idleMs"]!!.jsonPrimitive.longOrNull?.let { it / 1000.0 } ?: Double.POSITIVE_INFINITY
            eligible = step["eligible"]!!.jsonPrimitive.content == "true"
            usable = step["usable"]!!.jsonPrimitive.content == "true"
            if (step["wakeBefore"]!!.jsonPrimitive.content == "true") s.handleWake()
            s.tick()
            val cool = s.cooldownUntil?.let { ms(it).toString() } ?: "null"
            "nudges=$nudges active=${s.activeMinutes} cooldown=$cool gaps=$gaps alive=$alive"
        }
    }

    private fun expectedNudge(case: JsonObject): List<String> = case["expect"]!!.jsonArray.map { e ->
        val o = e.jsonObject
        val cool = if (o["cooldownUntilMs"] is JsonNull) "null" else o.long("cooldownUntilMs").toString()
        "nudges=${o.int("nudges")} active=${o.int("activeMinutes")} cooldown=$cool gaps=${o.int("absenceGaps")} alive=${o.int("aliveTicks")}"
    }

    @Test
    fun golden_nudge_traces_match_swift() {
        val g = Golden.load("desktop-work-policy/nudge")
        val ids = g.cases.map { it.string("id") }.toSet()
        // 이름 누락 단언 — 완료 기준의 넛지 짝(이동만 0 · 클릭 5분 1 · 1시간 쉼 · 설정 끔 0)이 전부 골든에 있다.
        assertTrue(ids.containsAll(setOf("move-only", "click-every-minute", "cooldown-one-hour", "setting-off", "locked")), "골든 넛지 case 누락: $ids")
        for (case in g.cases) {
            val id = case.string("id")
            assertEquals(expectedNudge(case), replayNudge(case), g.failure(id, "걸음별 넛지 상태"))
        }
        val finalNudges = g.cases.associate { it.string("id") to it["expect"]!!.jsonArray.last().jsonObject.int("nudges") }
        assertEquals(0, finalNudges["move-only"], "㉔ 이동만이면 시작 0")
        assertEquals(1, finalNudges["click-every-minute"], "클릭 5분이면 시작 1")
        assertEquals(2, finalNudges["cooldown-one-hour"], "70분 동안 두 번 — 사이에 1시간 쉼")
        assertEquals(0, finalNudges["setting-off"], "설정 끔이면 0")
        assertEquals(0, finalNudges["locked"], "잠금이면 0")
    }

    @Test
    fun golden_lap_keys_day_keys_and_marker_match_swift() {
        val g = Golden.load("desktop-work-policy/laps")
        for (case in g.cases) {
            val id = case.string("id")
            when {
                id.startsWith("lap-key/") -> assertEquals(case.string("key"), ultraLapKey(case.long("lap")), g.failure(id, "랩 키"))
                id.startsWith("day-key/") ->
                    assertEquals(case.string("key"), KstDayKey.of(SwiftDate(case.long("epochSeconds").toDouble())), g.failure(id, "KST 일 키"))
                id.startsWith("marker/") -> {
                    val store = InMemoryDesktopKeyValueStore(mapOf(SleepCloseMarkerStore.KEY to case.string("json")))
                    val m = assertNotNull(SleepCloseMarkerStore(store).load(), g.failure(id, "Swift 마커 JSON 디코드"))
                    assertEquals(SID, m.sessionID)
                    assertEquals(case.long("sessionStartedAtMs"), ms(m.startedAtDate), g.failure(id, "시작"))
                    assertEquals(case.long("sleepBeganAtMs"), ms(m.sleepBeganAtDate), g.failure(id, "잠든 시각"))
                    val last = case["lastInputAtMs"]!!.jsonPrimitive.longOrNull
                    assertEquals(last, m.lastInputAtDate?.let(::ms), g.failure(id, "마지막 입력"))
                }
                else -> error("모르는 case $id")
            }
        }
        assertEquals(7, g.cases.count { it.string("id").startsWith("lap-key/") })
    }

    // ---------- ⑲⑳ 잠자기 ----------

    /** 시작 T0, 마지막 입력 +1000초, +2000초에 잠들어 [asleep] 초 뒤 깸. 결과 문자열(규칙 위반 탐지용). */
    private fun sleepScenario(asleep: Double, rules: WorkPolicyRules, adopted: Boolean = false, lastInput: Double = 1000.0): Pair<WakeOutcome, List<Close>> {
        val state = InMemoryDesktopWorkState(working(lastInput = at(lastInput), adopted = adopted))
        val close = RecordingAutoClose()
        val policy = SleepPolicy(state, close, SleepCloseMarkerStore(InMemoryDesktopKeyValueStore()), rules = rules)
        policy.handleSleep(at(2000.0))
        return policy.handleWake(at(2000.0 + asleep)) to close.calls
    }

    private fun sleepRulesHold(rules: WorkPolicyRules): Boolean {
        val (keep, keepCalls) = sleepScenario(300.000, rules)
        val (close, closeCalls) = sleepScenario(300.001, rules)
        val (_, clampCalls) = sleepScenario(400.0, rules, lastInput = -50.0)
        val (_, adoptedCalls) = sleepScenario(4000.0, rules, adopted = true)
        return keep == WakeOutcome.WithinGrace && keepCalls.isEmpty() &&
            close == WakeOutcome.Closed(at(1000.0)) && closeCalls.singleOrNull()?.let { it.endedAt == at(1000.0) && it.reason == AutoCloseReason.SLEEP } == true &&
            clampCalls.singleOrNull()?.endedAt == T0 &&
            adoptedCalls.isEmpty()
    }

    @Test
    fun sleep_300_000_keeps_300_001_closes_at_min_of_sleep_and_input_19() {
        assertTrue(sleepRulesHold(WorkPolicyRules.Standard))
    }

    @Test
    fun negative_sleep_endedAt_sleepBegan_turns_red() {
        assertFalse(sleepRulesHold(object : WorkPolicyRules() {
            override fun sleepEndedAt(startedAt: SwiftDate?, sleepBeganAt: SwiftDate, lastInputAt: SwiftDate?) = sleepBeganAt
        }))
    }

    @Test
    fun negative_sleep_grace_inclusive_turns_red() {
        assertFalse(sleepRulesHold(object : WorkPolicyRules() {
            override fun sleepExceedsGrace(asleepSeconds: Double) = asleepSeconds >= WorkPolicyConstants.SLEEP_GRACE_SECONDS
        }))
    }

    @Test
    fun negative_adopted_session_closed_turns_red_23() {
        assertFalse(sleepRulesHold(object : WorkPolicyRules() {
            override fun excludesFromAutoClose(snapshot: DesktopWorkSnapshot) = false
        }))
    }

    @Test
    fun sleep_hooks_run_before_guards_even_when_not_working_20() {
        val state = InMemoryDesktopWorkState(DesktopWorkSnapshot())
        val order = ArrayList<String>()
        val p = SleepPolicy(
            state, RecordingAutoClose(), SleepCloseMarkerStore(InMemoryDesktopKeyValueStore()),
            beforeSleepGuard = { order += "willSleep" }, wakeFirst = { order += "wakeGate" },
        )
        p.handleSleep(at(0.0))
        assertEquals(WakeOutcome.NotWorking, p.handleWake(at(900.0)))
        assertEquals(listOf("willSleep", "wakeGate"), order)
    }

    @Test
    fun marker_persists_and_corrects_on_relaunch_once() {
        val disk = InMemoryDesktopKeyValueStore()
        val state = InMemoryDesktopWorkState(working(lastInput = at(1000.0)))
        SleepPolicy(state, RecordingAutoClose(), SleepCloseMarkerStore(disk)).handleSleep(at(2000.0))
        assertNotNull(disk.snapshot()[SleepCloseMarkerStore.KEY], "마커는 디스크에 남는다")
        // 잠자는 사이 앱이 죽었다 — 다음 실행: 로컬 근무 없음, 서버는 off_work, 영속 소유 id 가 그 세션.
        val queue = FakeQueue()
        val close = RecordingAutoClose()
        val fix = SleepCloseCorrection(SleepCloseMarkerStore(disk), close, queue, newItemId = { "item-1" })
        val result = fix.onOwnStatusOffWork(DesktopWorkSnapshot(), isOwnedByThisDevice = { it == SID }, ownerUserId = "user-a")
        val item = (result as SleepCorrection.Enqueued).item
        assertEquals(PendingWorkItem("item-1", PendingWorkOperation.Stop(1000), SID, T0, at(1000.0), "user-a", AutoCloseReason.SLEEP), item)
        assertEquals(listOf(item), queue.items.value)
        assertTrue(close.calls.isEmpty())
        assertEquals(SleepCorrection.None, fix.onOwnStatusOffWork(DesktopWorkSnapshot(), { true }, "user-a"), "정정은 1회")
        assertNull(disk.snapshot()[SleepCloseMarkerStore.KEY])
    }

    // ⑲ 마커 정정 (b) 재실행 갈래의 소유 관문 — Swift WorkTimerStoreSync.swift:2167 `if startedAt == nil, isOwnedByThisMac(marker.sessionID)`.
    // 마커는 있고 로컬 근무도 없지만 그 세션 id 를 이 기기가 더는 소유하지 않으면(다른 기기가 같은 id 를 재개했다)
    // 정정 Stop(reason=sleep)을 서버로 내보내면 안 된다. Swift 처럼 마커도 지우지 않는다(소유가 돌아오면 그때 1회).
    @Test
    fun marker_branch_b_needs_this_device_ownership_19() {
        val disk = InMemoryDesktopKeyValueStore()
        SleepPolicy(InMemoryDesktopWorkState(working(lastInput = at(1000.0))), RecordingAutoClose(), SleepCloseMarkerStore(disk))
            .handleSleep(at(2000.0))
        val planted = disk.snapshot()[SleepCloseMarkerStore.KEY]
        assertNotNull(planted, "마커는 디스크에 남는다")
        val queue = FakeQueue()
        val close = RecordingAutoClose()
        val asked = ArrayList<String>()
        val fix = SleepCloseCorrection(SleepCloseMarkerStore(disk), close, queue, newItemId = { "item-2" })
        val r = fix.onOwnStatusOffWork(DesktopWorkSnapshot(), isOwnedByThisDevice = { asked += it; false }, ownerUserId = "user-a")
        assertEquals(SleepCorrection.None, r, "내 소유 아님 → 정정 없음")
        assertEquals(listOf(SID), asked, "소유는 마커의 세션 id 로 묻는다")
        assertTrue(queue.items.value.isEmpty(), "남의 세션엔 정정 Stop 이 큐에 실리지 않는다")
        assertTrue(close.calls.isEmpty())
        assertEquals(planted, disk.snapshot()[SleepCloseMarkerStore.KEY], "소유 아님 → 마커를 지우지 않는다(Swift 와 같음)")
        // 짝: 위 None 이 마커를 소모하지 않았으므로 소유가 맞는 다음 호출이 정정을 1회 싣는다.
        val again = fix.onOwnStatusOffWork(DesktopWorkSnapshot(), isOwnedByThisDevice = { it == SID }, ownerUserId = "user-a")
        assertEquals(SID, (again as SleepCorrection.Enqueued).item.sessionId)
        assertEquals(1, queue.items.value.size)
        assertNull(disk.snapshot()[SleepCloseMarkerStore.KEY])
    }

    @Test
    fun marker_branch_a_closes_locally_and_adopted_never_plants() {
        val disk = InMemoryDesktopKeyValueStore()
        val state = InMemoryDesktopWorkState(working(lastInput = at(1000.0)))
        SleepPolicy(state, RecordingAutoClose(), SleepCloseMarkerStore(disk)).handleSleep(at(2000.0))
        val close = RecordingAutoClose()
        val r = SleepCloseCorrection(SleepCloseMarkerStore(disk), close, FakeQueue(), { "x" }).onOwnStatusOffWork(state.snapshot.value, { false }, "u")
        assertEquals(SleepCorrection.ClosedLocally(at(1000.0)), r)
        assertEquals(AutoCloseReason.SLEEP, close.calls.single().reason)
        val adoptedDisk = InMemoryDesktopKeyValueStore()
        SleepPolicy(InMemoryDesktopWorkState(working(adopted = true)), RecordingAutoClose(), SleepCloseMarkerStore(adoptedDisk)).handleSleep(at(10.0))
        assertTrue(adoptedDisk.snapshot().isEmpty(), "㉓ 흡수 세션은 마커를 심지 않는다")
    }

    // ---------- ㉑ 12시간 + 30분 ----------

    private fun longSessionHolds(rules: WorkPolicyRules): Boolean {
        val state = InMemoryDesktopWorkState(working())
        val close = RecordingAutoClose()
        val p = LongSessionPolicy(state, close, rules)
        p.evaluate(at(43_200.0))
        if (p.promptShownAt.value != null) return false
        val shown = at(43_200.5)
        p.evaluate(shown)
        if (p.promptShownAt.value != shown) return false
        p.evaluate(shown.addingTimeInterval(1800.0))
        if (close.calls.isNotEmpty()) return false
        p.evaluate(shown.addingTimeInterval(1800.25))
        val c = close.calls.singleOrNull() ?: return false
        // 흡수 세션 — 배너도 마감도 없다.
        val adopted = LongSessionPolicy(InMemoryDesktopWorkState(working(adopted = true)), close, rules)
        adopted.evaluate(at(50_000.0))
        adopted.evaluate(at(60_000.0))
        return c.endedAt == at(43_200.0) && c.reason == AutoCloseReason.LONG_SESSION && close.calls.size == 1 && adopted.promptShownAt.value == null
    }

    @Test
    fun long_session_prompt_after_12h_then_close_at_anchor_plus_12h_21() {
        assertTrue(longSessionHolds(WorkPolicyRules.Standard))
    }

    @Test
    fun negative_long_session_endedAt_now_turns_red() {
        assertFalse(longSessionHolds(object : WorkPolicyRules() {
            override fun longSessionEndedAt(anchor: SwiftDate, now: SwiftDate) = now
        }))
    }

    @Test
    fun confirm_still_working_restarts_12h_from_now() {
        val close = RecordingAutoClose()
        val p = LongSessionPolicy(InMemoryDesktopWorkState(working()), close)
        p.evaluate(at(43_201.0))
        p.confirmStillWorking(at(43_300.0))
        assertNull(p.promptShownAt.value)
        p.evaluate(at(43_300.0 + 43_200.0))
        assertNull(p.promptShownAt.value, "새 앵커 기준 12시간은 아직 아니다(배타)")
        p.evaluate(at(43_300.0 + 43_201.0 + 1801.0))
        assertNotNull(p.promptShownAt.value)
        assertTrue(close.calls.isEmpty())
    }

    // ---------- ㉒ 자리 비움 ----------

    private fun awaySetup(
        threshold: Double?,
        eligible: Boolean? = true,
        openSid: String? = SID.uppercase(),
        serverLast: SwiftDate? = at(100.0),
        adopted: Boolean = false,
        start: SwiftDate = T0,
        rules: WorkPolicyRules = WorkPolicyRules.Standard,
    ): Triple<AwayPolicy, RecordingAutoClose, FakeIdle> {
        val idle = FakeIdle()
        val close = RecordingAutoClose()
        val state = InMemoryDesktopWorkState(working(start = start, lastInput = at(50.0), adopted = adopted))
        val p = AwayPolicy(state, close, MeaningfulInputTracker(idle, { true }, rules), rules)
        p.apply(AwaySyncResult.Ok(threshold, AwayOpenSession(openSid, eligible, serverLast)))
        return Triple(p, close, idle)
    }

    private fun awayHolds(rules: WorkPolicyRules): Boolean {
        val (p, close, _) = awaySetup(9000.0, rules = rules)
        p.evaluate(at(9100.0))                     // 정확히 임계 — 배타라 유지
        if (close.calls.isNotEmpty()) return false
        p.evaluate(at(9100.001))
        val c = close.calls.singleOrNull() ?: return false
        val (pa, ca, _) = awaySetup(9000.0, adopted = true, rules = rules)
        pa.evaluate(at(99_999.0))
        return c.endedAt == at(100.0) && c.reason == AutoCloseReason.AWAY && ca.calls.isEmpty()
    }

    @Test
    fun away_closes_at_last_input_past_threshold_exclusive_22() {
        assertTrue(awayHolds(WorkPolicyRules.Standard))
    }

    @Test
    fun negative_away_adopted_closed_turns_red_23() {
        assertFalse(awayHolds(object : WorkPolicyRules() {
            override fun excludesFromAutoClose(snapshot: DesktopWorkSnapshot) = false
        }))
    }

    @Test
    fun away_guards_threshold_zero_eligible_missing_mismatch_and_start_after_input() {
        for ((label, setup) in listOf(
            "임계 0" to awaySetup(0.0),
            "임계 없음" to awaySetup(null),
            "closeEligible 없음" to awaySetup(9000.0, eligible = null),
            "closeEligible 거짓" to awaySetup(9000.0, eligible = false),
            "남의 세션" to awaySetup(9000.0, openSid = "11111111-0000-4000-8000-000000000000"),
            "시작이 입력보다 뒤" to awaySetup(9000.0, start = at(200.0)),
        )) {
            val (p, close, _) = setup
            assertNull(p.schedule(), label)
            p.evaluate(at(99_999.0))
            assertTrue(close.calls.isEmpty(), label)
        }
    }

    @Test
    fun away_advances_input_right_before_judging_and_failure_clears_policy() {
        val (p, close, idle) = awaySetup(9000.0)
        idle.last[InputKind.CLICK] = at(9050.0)     // 임계 직전에 돌아와 클릭
        idle.last[InputKind.MOVE] = at(9200.0)      // 이동은 세지 않는다(㉔)
        p.evaluate(at(9200.0))
        assertTrue(close.calls.isEmpty())
        assertEquals(at(9050.0), p.lastInputAt())
        p.apply(AwaySyncResult.Failed)
        assertNull(p.schedule())
        assertTrue(p.shouldSync(at(0.0), signedIn = true))
    }

    @Test
    fun away_sync_throttles_120s_only_when_idle() {
        val idleState = InMemoryDesktopWorkState(DesktopWorkSnapshot())
        val p = AwayPolicy(idleState, RecordingAutoClose(), MeaningfulInputTracker(FakeIdle(), { true }))
        assertTrue(p.shouldSync(at(0.0), true))
        assertFalse(p.shouldSync(at(119.9), true))
        assertTrue(p.shouldSync(at(120.0), true))
        idleState.set(working())
        assertTrue(p.shouldSync(at(121.0), true), "근무 중이면 매 폴링")
        assertFalse(p.shouldSync(at(122.0), false))
    }

    @Test
    fun meaningful_input_freezes_when_locked_and_never_goes_back() {
        val idle = FakeIdle()
        var usable = true
        val t = MeaningfulInputTracker(idle, { usable })
        idle.last[InputKind.KEY] = at(100.0)
        assertEquals(at(100.0), t.advance(at(200.0)))
        idle.last[InputKind.KEY] = at(50.0)
        assertEquals(at(100.0), t.advance(at(210.0)), "뒤로 가지 않는다")
        usable = false
        idle.last[InputKind.KEY] = at(300.0)
        assertEquals(at(100.0), t.advance(at(310.0)), "잠금 동안 동결")
        usable = true
        idle.last[InputKind.KEY] = at(500.0)
        assertEquals(at(400.0), t.advance(at(400.0)), "미래는 지금으로 누른다")
    }

    // ---------- 30분 재개 · 방치 자가 마감 ----------

    @Test
    fun resume_window_is_30_minutes_from_ended_at_and_never_long_session() {
        fun snap(reason: AutoCloseReason, working: Boolean = false) = DesktopWorkSnapshot(
            isWorking = working, startedAt = if (working) T0 else null,
            lastAutoClose = LastAutoClose(SID, reason, at(0.0), 600),
        )
        assertTrue(RecentAutoCloseResume.canResume(snap(AutoCloseReason.AWAY), at(1800.0)))
        assertFalse(RecentAutoCloseResume.canResume(snap(AutoCloseReason.AWAY), at(1800.001)))
        assertFalse(RecentAutoCloseResume.canResume(snap(AutoCloseReason.SLEEP), at(-0.001)), "음수 갭")
        assertTrue(RecentAutoCloseResume.canResume(snap(AutoCloseReason.ABANDONED), at(1.0)))
        assertFalse(RecentAutoCloseResume.canResume(snap(AutoCloseReason.LONG_SESSION), at(1.0)))
        assertFalse(RecentAutoCloseResume.canResume(snap(AutoCloseReason.SLEEP, working = true), at(1.0)))
        assertFalse(RecentAutoCloseResume.canResume(DesktopWorkSnapshot(), at(1.0)))
    }

    @Test
    fun abandoned_self_close_only_past_7_minutes_and_never_while_local_works() {
        val now = at(10_000.0)
        val seen = now.addingTimeInterval(-WorkPolicyConstants.ADOPTED_RECLAIM_STALE_SECONDS)
        assertNull(AbandonedOwnSessionClose.decide(false, true, true, true, T0, seen, now), "정확히 7분은 유지")
        val d = assertNotNull(AbandonedOwnSessionClose.decide(false, true, true, true, T0, seen.addingTimeInterval(-1.0), now))
        assertEquals(seen.addingTimeInterval(-1.0), d.endedAt)
        assertEquals(9579L, d.durationSeconds)
        assertNull(AbandonedOwnSessionClose.decide(true, true, true, true, T0, T0, now), "로컬 근무 중")
        assertNull(AbandonedOwnSessionClose.decide(false, false, true, true, T0, T0, now), "큐가 남았다")
        val dayStart = TeamWeeklyGoal.koreanDayStart(now)
        val y = assertNotNull(AbandonedOwnSessionClose.decide(false, true, true, true, dayStart.addingTimeInterval(-3600.0), dayStart.addingTimeInterval(60.0), dayStart.addingTimeInterval(4000.0)))
        assertEquals(60L, y.closedTodaySeconds, "오늘 몫은 KST 자정으로 자른다")
    }

    // ---------- 깨움 게이트 · 종료 3초 ----------

    @Test
    fun wake_gate_releases_at_10s_cap_or_on_network() = runTest {
        val released = ArrayList<Pair<Long, Boolean>>()
        val never = WakeGate(backgroundScope, { awaitCancellation() }, onRelease = { released += currentTime to it })
        never.begin()
        var queueRanAt = -1L
        launch { never.await(); queueRanAt = currentTime }
        advanceTimeBy(9_999); runCurrent()
        assertTrue(released.isEmpty() && never.isHolding)
        advanceTimeBy(1); runCurrent()
        assertEquals(listOf(10_000L to false), released)
        assertEquals(10_000L, queueRanAt, "큐는 게이트 뒤에 나간다")
        released.clear()
        val net = kotlinx.coroutines.CompletableDeferred<Unit>()
        val gate = WakeGate(backgroundScope, { net.await() }, onRelease = { released += currentTime to it })
        gate.begin()
        advanceTimeBy(2_000); net.complete(Unit); runCurrent()
        assertEquals(listOf(12_000L to true), released)
        released.clear()
        WakeGate(backgroundScope, null, onRelease = { released += currentTime to it }).begin()
        assertEquals(listOf(12_000L to true), released, "관측자 없으면 즉시")
    }

    @Test
    fun finish_before_quit_caps_at_3s_skips_adopted_and_never_plants_suppression_17() = runTest {
        val disk = InMemoryDesktopKeyValueStore()
        val flag = TerminationFlag()
        val suppression = AutoStartSuppression(disk, flag)
        var stops = 0
        val queue = FakeQueue(idleForever = true)
        val q = QuitFinisher(InMemoryDesktopWorkState(working()), { true }, flag, { stops++; suppression.onManualStop(T0) }, queue)
        assertEquals(QuitOutcome.TIMED_OUT, q.finishWorkBeforeQuit())
        assertEquals(3_000L, currentTime, "가상 시간 3초 상한")
        assertEquals(1, stops)
        assertFalse(suppression.isSuppressed, "⑰ 종료 시퀀스의 stop 은 억제를 심지 않는다")
        assertTrue(disk.snapshot().isEmpty())

        val adoptedQueue = FakeQueue()
        var adoptedStops = 0
        val qa = QuitFinisher(InMemoryDesktopWorkState(working(adopted = true)), { true }, TerminationFlag(), { adoptedStops++ }, adoptedQueue)
        assertEquals(QuitOutcome.SKIPPED, qa.finishWorkBeforeQuit())
        assertEquals(0, adoptedStops, "㉓ 흡수면 요청 0")
        assertEquals(0, adoptedQueue.awaitCalls)
        assertEquals(3_000L, currentTime)

        val fast = QuitFinisher(InMemoryDesktopWorkState(working()), { true }, TerminationFlag(), { }, FakeQueue(idleForever = false))
        assertEquals(QuitOutcome.DRAINED, fast.finishWorkBeforeQuit())
        // 대조: 종료 시퀀스가 아니면 수동 종료가 억제를 심는다.
        assertTrue(AutoStartSuppression(InMemoryDesktopKeyValueStore(), TerminationFlag()).onManualStop(T0))
    }

    // ---------- ㉔ 넛지 짝 ----------

    private class NudgeRig(rules: WorkPolicyRules = WorkPolicyRules.Standard, setting: Boolean = true, snapshot: DesktopWorkSnapshot = DesktopWorkSnapshot()) {
        var now = T0
        val idle = FakeIdle()
        val events = Events()
        val starts = ArrayList<WorkStartOrigin>()
        var resumes = 0
        val usability = SessionUsability()
        val suppression = AutoStartSuppression(InMemoryDesktopKeyValueStore(), TerminationFlag())
        val starter = NudgeAutoStarter(
            InMemoryDesktopWorkState(snapshot), { true }, { true }, suppression, { setting },
            startWork = { starts += it }, resumeRecentlyClosed = { resumes++ }, clock = { now }, events = events,
        )
        val scheduler = starter.scheduler(
            idleSeconds = { meaningfulIdleSeconds(idle, now, rules.meaningfulInputKinds) },
            isSessionUsable = { usability.isUsable },
        )

        fun minutes(range: IntRange, input: InputKind?) {
            for (m in range) {
                now = at(m * 60.0)
                if (input != null) idle.last[input] = now.addingTimeInterval(-5.0)
                scheduler.tick()
            }
        }
    }

    private fun moveOnlyStartsNothing(rules: WorkPolicyRules): Boolean {
        val rig = NudgeRig(rules)
        rig.minutes(1..15, InputKind.MOVE)
        return rig.starts.isEmpty()
    }

    @Test
    fun nudge_pairs_move_only_zero_click_five_minutes_one_rest_one_hour_setting_off_zero_24() {
        assertTrue(moveOnlyStartsNothing(WorkPolicyRules.Standard), "이동만 = 시작 0")
        val rig = NudgeRig()
        rig.minutes(1..4, InputKind.CLICK)
        assertTrue(rig.starts.isEmpty())
        rig.minutes(5..5, InputKind.CLICK)
        assertEquals(listOf(WorkStartOrigin.NUDGE), rig.starts, "클릭 5분(10분 창) = 시작 1")
        assertEquals(listOf<WorkEvent>(WorkEvent.NudgeStarted), rig.events.seen)
        rig.minutes(6..64, InputKind.CLICK)
        assertEquals(1, rig.starts.size, "시작 뒤 1시간 쉼")
        rig.minutes(65..69, InputKind.CLICK)
        assertEquals(2, rig.starts.size, "쉼이 끝나면 다시 5분")
        val off = NudgeRig(setting = false)
        off.minutes(1..30, InputKind.KEY)
        assertTrue(off.starts.isEmpty() && off.resumes == 0 && off.events.seen.isEmpty(), "설정 끔 = 0")
        val locked = NudgeRig()
        locked.usability.on(SessionEvent.LOCK)
        locked.minutes(1..10, InputKind.KEY)
        assertTrue(locked.starts.isEmpty(), "잠금 동안 0")
        locked.usability.on(SessionEvent.UNLOCK)
        locked.usability.on(SessionEvent.CONSOLE_DISCONNECT)
        locked.usability.on(SessionEvent.REMOTE_CONNECT)
        locked.minutes(11..15, InputKind.WHEEL)
        assertEquals(1, locked.starts.size, "RDP 는 쓰는 것으로 친다")
    }

    @Test
    fun negative_move_counted_as_input_turns_red_24() {
        assertFalse(moveOnlyStartsNothing(object : WorkPolicyRules() {
            override val meaningfulInputKinds = setOf(InputKind.KEY, InputKind.CLICK, InputKind.WHEEL, InputKind.MOVE)
        }))
    }

    @Test
    fun nudge_resumes_recent_auto_close_before_starting_and_suppression_rearms_after_1h() {
        val rig = NudgeRig(snapshot = DesktopWorkSnapshot(lastAutoClose = LastAutoClose(SID, AutoCloseReason.SLEEP, at(0.0), 300)))
        rig.now = at(600.0)
        assertEquals(NudgeAction.RESUMED, rig.starter.fire())
        assertEquals(1, rig.resumes)
        assertTrue(rig.starts.isEmpty(), "재개가 있으면 새 세션을 만들지 않는다")
        val disk = InMemoryDesktopKeyValueStore()
        val s = AutoStartSuppression(disk, TerminationFlag())
        s.onManualStop(T0)
        val relaunch = AutoStartSuppression(disk, TerminationFlag())
        relaunch.restoreOnLaunch(at(3599.0))
        assertTrue(relaunch.isSuppressed)
        relaunch.restoreOnLaunch(at(3600.0))
        assertFalse(relaunch.isSuppressed, "1시간 부재로 재무장")
    }

    // ---------- ㉕ 마일스톤 · 랩 · 팀 목표 ----------

    private fun lapKeysPerLap(rules: WorkPolicyRules): Boolean {
        val laps = ArrayList<Long>()
        val m = TimeMilestones(MilestoneTracker(InMemoryDesktopKeyValueStore()), WorkEventSink.NONE, { laps += it }, rules)
        val dayStart = TeamWeeklyGoal.koreanDayStart(T0)
        val snap = working(start = dayStart.addingTimeInterval(60.0))
        for (h in listOf(3.0, 3.5, 6.0, 9.0)) m.evaluate(snap, dayStart.addingTimeInterval(60.0 + h * 3600))
        return laps == listOf(1L, 2L, 3L)
    }

    @Test
    fun milestones_1h_4h_once_per_day_and_lap_key_per_lap_25() {
        assertTrue(lapKeysPerLap(WorkPolicyRules.Standard))
        val events = Events()
        val dayStart = TeamWeeklyGoal.koreanDayStart(T0)
        val m = TimeMilestones(MilestoneTracker(InMemoryDesktopKeyValueStore()), events, { })
        val snap = working(start = dayStart.addingTimeInterval(60.0))
        m.evaluate(snap, dayStart.addingTimeInterval(60.0 + 3599))
        m.evaluate(snap, dayStart.addingTimeInterval(60.0 + 3600))
        m.evaluate(snap, dayStart.addingTimeInterval(60.0 + 3700))
        assertEquals(listOf<WorkEvent>(WorkEvent.Milestone(1)), events.seen)
        val late = Events()
        TimeMilestones(MilestoneTracker(InMemoryDesktopKeyValueStore()), late, { }).apply {
            evaluate(snap, dayStart.addingTimeInterval(60.0 + 4 * 3600))
            evaluate(snap, dayStart.addingTimeInterval(60.0 + 4 * 3600 + 10))
        }
        assertEquals(listOf<WorkEvent>(WorkEvent.Milestone(4)), late.seen, "4h 로 처음 관측되면 1h 는 조용히 소비")
        val zero = ArrayList<Long>()
        TimeMilestones(MilestoneTracker(InMemoryDesktopKeyValueStore()), WorkEventSink.NONE, { zero += it })
            .evaluate(snap, dayStart.addingTimeInterval(60.0 + 5 * 3600), missionWorkSeconds = 0)
        assertTrue(zero.isEmpty(), "target 0 이면 랩 0")
    }

    @Test
    fun negative_lap_key_once_per_day_turns_red_25() {
        assertFalse(lapKeysPerLap(object : WorkPolicyRules() {
            override fun lapKey(lap: Long) = MilestoneTracker.HOUR_THREE_KEY
        }))
    }

    @Test
    fun lap_celebrates_only_after_server_granted_now() {
        assertEquals(false, LapWalletJudge.judge(listOf(LapGrant(false, 3)), 4).celebrate, "claimed 만으로는 축하 0")
        assertEquals(2, LapWalletJudge.judge(listOf(LapGrant(true, 2), LapGrant(true, 0), LapGrant(false, 9)), 4).lapsToday)
        assertEquals(1, LapWalletJudge.judge(listOf(LapGrant(true, 0)), 4).lapsToday, "랩 이전 서버 0 → 1")
        val events = Events()
        LapCelebration(events).onWalletSynced(listOf(LapGrant(true, 2)), 7)
        LapCelebration(events).onWalletSynced(listOf(LapGrant(false, 2)), 7)
        assertEquals(listOf<WorkEvent>(WorkEvent.LapCelebrated(2, 7)), events.seen)
    }

    @Test
    fun team_goal_fires_on_false_to_true_transition_once_a_day() {
        val events = Events()
        val d = TeamGoalDetector(MilestoneTracker(InMemoryDesktopKeyValueStore()), events)
        assertFalse(d.observe(100, 50, T0), "첫 관측은 전이가 아니다")
        assertFalse(d.observe(10, 50, T0))
        assertTrue(d.observe(50, 50, T0))
        assertFalse(d.observe(10, 50, T0))
        assertFalse(d.observe(60, 50, T0), "같은 날 두 번째 돌파는 조용히")
        assertFalse(d.observe(10, 50, at(86_400.0)))
        assertTrue(d.observe(60, 50, at(86_400.0)), "다음 날 다시")
        assertEquals(listOf<WorkEvent>(WorkEvent.TeamGoalAchieved, WorkEvent.TeamGoalAchieved), events.seen)
    }
}
