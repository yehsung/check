// 원본: Tests/CheckMobileKitTests/RankingsLeagueWeekTests.swift:1-451(주 상태 기계 · 늦은 응답 · 롤오버 · 옛 서버 폴백 · 서버 주 채택) @ 1b8260d
// 팀 리그 지난 6주 보기(v0.3.37). 시계는 Swift 시험과 같은 두 시각(목요일 오후 · 일요일 23:59)에서 출발한다.
package com.yehsung.aingcheck.core.stores.rankings

import com.yehsung.aingcheck.core.rules.insights.TeamLeagueWeekNavigator
import com.yehsung.aingcheck.core.stores.messages.NaturalKoNameCollation
import com.yehsung.aingcheck.core.stores.messages.Reply
import com.yehsung.aingcheck.core.stores.messages.StoreHarness
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftISO8601
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class RankingsLeagueWeekTest {
    /** 2026-09-24 14:05 KST(목). 이번 주 월요일 = 2026-09-21 → 한 주 과거가 9월 14일 주. */
    private val thursday: SwiftDate = SwiftISO8601.parse("2026-09-24T05:05:00Z")!!

    /** 2026-09-20 23:59 KST(일). 120초만 지나면 주가 넘어간다. */
    private val sundayLate: SwiftDate = SwiftISO8601.parse("2026-09-20T14:59:00Z")!!

    private fun weekKey(offset: Int, now: SwiftDate) = TeamLeagueWeekNavigator.key(offset, now.timeIntervalSince1970)

    /** 새 서버 행 두 개(내 팀 + 다른 팀). `weekStart` 가 있으면 행이 스스로 과거를 말한다. */
    private fun leagueJSON(weekStart: String?, participants: Int? = 4): String {
        fun row(id: String, name: String, total: Long, working: Int): String {
            val fields = arrayListOf(
                """"team_id":"$id"""", """"team_name":"$name"""", """"weekly_goal_hours":40""",
                """"total_seconds":$total""", """"working_count":$working""", """"member_count":5""", """"center":null""",
            )
            if (weekStart != null) fields += """"week_start":"$weekStart""""
            if (participants != null) fields += """"participant_count":$participants"""
            return "{" + fields.joinToString(",") + "}"
        }
        return "[${row("t-high", "높은팀", 288_000, 2)},${row("team-1", "테스트팀", 36_000, 0)}]"
    }

    private fun offsetOf(r: RecordedRequest): Int =
        (SwiftJson.parse(r.bodyText) as? JsonObject)?.get("p_week_offset")?.jsonPrimitive?.content?.toInt() ?: -1

    /** 요청 본문의 `p_week_offset` 을 그대로 읽어 그 주의 행을 준다(서버 시늉 — '지금'은 요청 시각의 시계). */
    private fun answer(r: RecordedRequest, now: SwiftDate): Reply = Reply.Json(leagueJSON(weekKey(offsetOf(r).coerceAtLeast(0), now)))

    private fun offsets(h: StoreHarness): List<Int> = h.storeRequests.filter { it.rpcName == "team_weekly_leaderboard" }.map(::offsetOf)

    private suspend fun TestScope.make(start: SwiftDate, route: (StoreHarness, RecordedRequest) -> Reply?): Pair<StoreHarness, RankingsStore> {
        lateinit var harness: StoreHarness
        harness = StoreHarness(this, start) { r -> route(harness, r) }
        harness.signIn()
        return harness to RankingsStore(harness.context, harness.storeScope, NaturalKoNameCollation)
    }

    private fun leagueOnly(h: StoreHarness, r: RecordedRequest): Reply? =
        if (r.rpcName == "team_weekly_leaderboard") answer(r, h.now()) else null

    @Test
    fun stepsWeeksAndStopsAtBothEnds() = runTest {
        val now = thursday
        val (h, store) = make(now, ::leagueOnly)
        store.tabDidAppear()
        advanceUntilIdle()
        assertTrue(store.leagueState.hasLoaded)
        assertEquals(weekKey(0, now), store.leagueWeekKey)
        assertEquals("팀별 이번 주", store.leagueTitle, "이번 주 제목은 한 글자도 안 바뀐다")
        assertTrue(!store.isLeaguePastWeek && !store.canStepLeagueWeekForward && store.canStepLeagueWeekBack)
        assertEquals(listOf(0), offsets(h), "오프셋 0 도 본문에 실려 나간다")

        // 이번 주에서 ▸ — 값이 안 바뀌면 요청도 없다.
        store.stepLeagueWeek(1)
        advanceUntilIdle()
        assertEquals(listOf(0), offsets(h))

        store.stepLeagueWeek(-1)
        assertEquals(emptyList(), store.league, "옮기는 순간 직전 주 행을 비운다")
        assertTrue(store.leagueState.isLoading)
        advanceUntilIdle()
        assertEquals(weekKey(1, now), store.leagueWeekKey)
        assertEquals("팀별 9월 14일 주", store.leagueTitle)
        assertEquals("9월 14일 주", store.leagueWeekName)
        assertTrue(store.isLeaguePastWeek && store.canStepLeagueWeekForward)
        assertTrue(store.leagueDisplay.isNotEmpty() && store.leagueDisplay.all { it.isPastWeek(now) }, "행이 스스로 과거를 말한다")

        store.stepLeagueWeek(-1)
        advanceUntilIdle()
        assertEquals(weekKey(2, now), store.leagueWeekKey)
        assertEquals(listOf(0, 1, 2), offsets(h))

        repeat(4) {
            store.stepLeagueWeek(-1)
            advanceUntilIdle()
            assertTrue(store.leagueState.hasLoaded)
        }
        assertEquals(weekKey(6, now), store.leagueWeekKey)
        assertFalse(store.canStepLeagueWeekBack)
        val atFloor = offsets(h)
        store.stepLeagueWeek(-1)
        advanceUntilIdle()
        assertEquals(atFloor, offsets(h), "6주 전에서 ◂ 가 또 물었다")
        h.assertClean()
    }

    @Test
    fun lateWeekResponseIsDropped() = runTest {
        val now = thursday
        val gate = CompletableDeferred<Unit>()
        var holdPast = false
        val (h, store) = make(now) { harness, r ->
            if (r.rpcName != "team_weekly_leaderboard") null
            else if (holdPast && offsetOf(r) > 0) Reply.Gate(gate, answer(r, harness.now())) else answer(r, harness.now())
        }
        val current = weekKey(0, now)
        store.tabDidAppear()
        advanceUntilIdle()
        holdPast = true
        store.stepLeagueWeek(-1)
        runCurrent()
        // 기다리는 사이 ▸ 로 이번 주 복귀(이 조회는 붙잡히지 않는다).
        store.stepLeagueWeek(1)
        runCurrent()
        assertEquals(current, store.leagueWeekKey)
        assertTrue(store.leagueState.hasLoaded)
        val startedAt = testScheduler.currentTime
        gate.complete(Unit)
        runCurrent()
        assertEquals(startedAt, testScheduler.currentTime, "멈춘 조회가 시한에 걸렸다(늦은 응답을 재지 못했다)")
        assertEquals(listOf(0, 1, 0), offsets(h))
        assertEquals(current, store.leagueWeekKey)
        assertEquals(current, store.league.first().weekStart, "늦게 온 과거 주 행이 이번 주 화면을 덮었다")
        assertFalse(store.isLeaguePastWeek)
        assertFalse(store.leagueState.isLoading, "'불러오는 중'이 남았다")
        h.assertClean()
    }

    @Test
    fun rollsToCurrentWeekOnceWhenMondayPasses() = runTest {
        val start = sundayLate
        val (h, store) = make(start, ::leagueOnly)
        store.tabDidAppear()
        advanceUntilIdle()
        store.stepLeagueWeek(-1)
        advanceUntilIdle()
        assertTrue(store.isLeaguePastWeek)
        assertEquals(listOf(0, 1), offsets(h))

        h.clockShift += 120   // 23:59 → 00:01
        val newCurrent = weekKey(0, h.now())
        assertNotEquals(weekKey(0, start), newCurrent, "시계가 주를 안 넘겼다 — 이 시험이 무의미해진다")

        store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(newCurrent, store.leagueWeekKey)
        assertFalse(store.isLeaguePastWeek)
        assertEquals(listOf(0, 1, 0), offsets(h), "스냅 뒤 이번 주(오프셋 0)를 물어야 한다")

        store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(listOf(0, 1, 0), offsets(h), "앵커를 못 맞춰 두 번 스냅했다")
        h.assertClean()
    }

    @Test
    fun forwardStepInRolloverWindowRefillsTheList() = runTest {
        val start = sundayLate
        val (h, store) = make(start, ::leagueOnly)
        store.tabDidAppear()
        advanceUntilIdle()
        assertTrue(store.league.isNotEmpty())
        h.clockShift += 120
        val newCurrent = weekKey(0, h.now())
        assertNotEquals(weekKey(0, start), newCurrent)
        assertTrue(store.canStepLeagueWeekForward, "롤오버 창에서 ▸ 가 꺼져 있으면 이 회귀를 못 잰다")

        store.stepLeagueWeek(1)
        advanceUntilIdle()
        assertTrue(store.leagueState.hasLoaded && store.league.isNotEmpty())
        assertEquals(newCurrent, store.leagueWeekKey)
        assertFalse(store.isLeaguePastWeek || store.leagueState.isLoading)
        assertEquals(listOf(0, 0), offsets(h), "스냅이 비운 목록을 아무도 다시 채우지 않았다")

        store.stepLeagueWeek(1)
        advanceUntilIdle()
        assertEquals(listOf(0, 0), offsets(h))
        assertTrue(store.league.isNotEmpty())
        h.assertClean()
    }

    @Test
    fun backStepAfterRolloverCountsFromTheNewWeek() = runTest {
        val start = sundayLate
        val (h, store) = make(start, ::leagueOnly)
        store.tabDidAppear()
        advanceUntilIdle()
        store.stepLeagueWeek(-1)
        advanceUntilIdle()
        assertEquals(listOf(0, 1), offsets(h))
        h.clockShift += 120
        val now = h.now()
        assertNotEquals(weekKey(0, start), weekKey(0, now))

        store.stepLeagueWeek(-1)
        advanceUntilIdle()
        assertEquals(weekKey(1, now), store.leagueWeekKey, "롤오버를 무시하고 옛 주 기준으로 셌다")
        assertEquals(listOf(0, 1, 1), offsets(h))
        h.assertClean()
    }

    @Test
    fun pullToRefreshAlsoRolls() = runTest {
        val start = sundayLate
        val (h, store) = make(start, ::leagueOnly)
        store.tabDidAppear()
        advanceUntilIdle()
        assertEquals(listOf(0), offsets(h))
        h.clockShift += 120
        val newCurrent = weekKey(0, h.now())
        assertNotEquals(weekKey(0, start), newCurrent)
        // 당겨서 새로고침은 refreshIfStale 을 안 지난다 — loadLeague 안의 롤오버가 유일한 그물이다.
        store.refresh()
        assertEquals(newCurrent, store.leagueWeekKey, "당겨서 새로고침이 화면을 지난주로 데려갔다")
        assertEquals("팀별 이번 주", store.leagueTitle)
        assertEquals(listOf(0, 0), offsets(h))
        assertTrue(store.league.isNotEmpty() && !store.leagueState.isLoading)
        h.assertClean()
    }

    @Test
    fun cancelledPastWeekRecoversOnReturn() = runTest {
        val now = thursday
        var cancel = true
        val (h, store) = make(now) { harness, r ->
            if (r.rpcName != "team_weekly_leaderboard") null
            else if (offsetOf(r) > 0 && cancel) Reply.Cancelled else answer(r, harness.now())
        }
        store.tabDidAppear()
        advanceUntilIdle()
        store.stepLeagueWeek(-1)
        advanceUntilIdle()
        assertEquals(listOf(0, 1), offsets(h))
        assertFalse(store.leagueState.isLoading)
        // 취소는 실패로 올리지 않는다 — hasLoaded=false · hasFailed=false 인 죽은 카드.
        assertTrue(!store.leagueState.hasLoaded && !store.leagueState.hasFailed && store.league.isEmpty())
        assertEquals("불러오는 중…", RankingsText.leagueEmpty(store.leagueState.hasLoaded, store.leagueState.isLoading, store.leagueState.hasFailed, 0, isPastWeek = true))

        cancel = false
        h.clockShift += RankingsStore.staleSeconds + 1
        store.appDidBecomeActive()
        advanceUntilIdle()
        assertTrue(store.leagueState.hasLoaded && store.league.isNotEmpty())
        assertTrue(store.isLeaguePastWeek)
        assertEquals(weekKey(1, now), store.leagueWeekKey, "회복하면서 과거 주를 놓쳤다")
        assertEquals(listOf(0, 1, 1), offsets(h))

        h.clockShift += RankingsStore.staleSeconds + 1
        store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(listOf(0, 1, 1), offsets(h), "다 읽은 과거 주를 다시 물었다")
        h.assertClean()
    }

    @Test
    fun doorsFallToCurrentWeek() = runTest {
        val now = thursday
        val (h, store) = make(now, ::leagueOnly)
        val current = weekKey(0, now)
        suspend fun goPast() {
            store.stepLeagueWeek(-1)
            advanceUntilIdle()
            assertTrue(store.leagueState.hasLoaded && store.isLeaguePastWeek)
        }
        store.tabDidAppear()
        advanceUntilIdle()

        // ① 탭 재진입
        goPast()
        store.tabDidDisappear()
        store.tabDidAppear()
        assertEquals(current, store.leagueWeekKey, "탭을 다시 열었는데 과거 주가 따라왔다")
        advanceUntilIdle()
        assertTrue(store.leagueState.hasLoaded)

        // ② 보드 전환(리그 → 토큰 → 리그)
        goPast()
        store.select(RankingsBoard.tokens)
        store.select(RankingsBoard.league)
        assertEquals(current, store.leagueWeekKey, "보드를 갈아탔는데 과거 주가 살아 있다")
        advanceUntilIdle()

        // ③ 딥링크(이미 리그인 채로 다시 열기)
        goPast()
        store.open(RankingsBoard.league)
        assertEquals(current, store.leagueWeekKey, "딥링크가 과거 주를 그대로 뒀다")
        advanceUntilIdle()
        assertTrue(store.leagueState.hasLoaded && store.league.isNotEmpty())

        // ④ 이번 주에서 다시 열면 행이 비지 않는다(깜빡임 회귀).
        val before = offsets(h).size
        store.tabDidDisappear()
        store.tabDidAppear()
        assertTrue(store.league.isNotEmpty(), "이번 주 재진입이 행을 비웠다")
        advanceUntilIdle()
        assertEquals(before, offsets(h).size, "신선한 이번 주를 다시 물었다")
        h.assertClean()
    }

    @Test
    fun legacyServerFallbackKeepsThisWeekAndDoesNotRemember() = runTest {
        val now = thursday
        var legacy = true
        val (h, store) = make(now) { harness, r ->
            if (r.rpcName != "team_weekly_leaderboard") null
            else if (legacy) {
                if (r.bodyText.contains("p_week_offset")) Reply.missingFunction else Reply.Json(leagueJSON(null, null))
            } else answer(r, harness.now())
        }
        store.tabDidAppear()
        advanceUntilIdle()
        assertTrue(store.leagueState.hasLoaded)
        assertFalse(store.leagueWeekOffsetSupported)
        assertFalse(store.showsLeagueWeekNavigation, "옛 서버에서는 주 이동 알약을 그리지 않는다")
        assertEquals(weekKey(0, now), store.leagueWeekKey)
        assertTrue(store.league.isNotEmpty(), "폴백으로 받은 이번 주 표를 버렸다")
        assertFalse(store.isLeaguePastWeek)
        assertEquals(2, h.count("team_weekly_leaderboard"), "404 한 번 + {} 한 번, 그 이상은 내지 않는다")

        store.stepLeagueWeek(-1)
        advanceUntilIdle()
        assertEquals(2, h.count("team_weekly_leaderboard"))

        legacy = false
        store.loadLeague()
        assertTrue(store.leagueWeekOffsetSupported && store.showsLeagueWeekNavigation)
        assertEquals(3, h.count("team_weekly_leaderboard"))
        h.assertClean()
    }

    @Test
    fun pastWeekDoesNotPollButFailedPastWeekRetries() = runTest {
        val now = thursday
        var fail = false
        val (h, store) = make(now) { harness, r ->
            if (r.rpcName != "team_weekly_leaderboard") null
            else if (fail) Reply.Json("""{"message":"boom"}""", 500) else answer(r, harness.now())
        }
        store.tabDidAppear()
        advanceUntilIdle()
        store.stepLeagueWeek(-1)
        advanceUntilIdle()
        assertTrue(store.isLeaguePastWeek)
        val quiet = offsets(h).size

        h.clockShift += RankingsStore.staleSeconds + 1
        store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(quiet, offsets(h).size, "끝난 주를 30초마다 다시 물었다")

        fail = true
        store.refresh()
        assertTrue(store.leagueState.hasFailed)
        val afterFail = offsets(h).size
        fail = false
        h.clockShift += RankingsStore.staleSeconds + 1
        store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(afterFail + 1, offsets(h).size, "실패한 과거 주를 다시 읽지 않았다")
        assertTrue(!store.leagueState.hasFailed && store.isLeaguePastWeek)
        h.assertClean()
    }

    @Test
    fun adoptsTheWeekTheServerAnswered() = runTest {
        val now = thursday
        val served = weekKey(2, now)
        val (h, store) = make(now) { _, r -> if (r.rpcName == "team_weekly_leaderboard") Reply.Json(leagueJSON(served)) else null }
        store.tabDidAppear()
        advanceUntilIdle()
        assertTrue(store.leagueState.hasLoaded)
        assertEquals(served, store.leagueWeekKey, "서버가 답한 주를 안 따랐다 — 제목이 거짓말을 한다")
        assertEquals("팀별 9월 7일 주", store.leagueTitle)
        assertTrue(store.isLeaguePastWeek)
        assertFalse(store.leagueState.isLoading, "'불러오는 중'이 남았다(defer 에 주 키를 넣으면 이 단언이 깨진다)")
        h.assertClean()
    }
}
