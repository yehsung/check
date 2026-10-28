// 원본: Sources/CheckMobileKit/Components/MobileComponentModels.swift:249-335 @ 3bd04bd (ContributionCalendarLayout · MeGrassSelection)
//
// 잔디 상세 판정(순수)을 Swift 규칙과 같은 값으로 잰다: 피치 = 폭 / 7(360dp 화면에서도 ≥ 44) · 가로 위치 → 요일 · 하루 옮기기(창 밖·미래면 null) ·
// 처음 고를 칸 = 오늘 · 달 묶음은 그 주의 **일요일**이 든 달(8/31 월요일 주는 9월) · 두 잔디 창이 어긋나면 토큰 값을 말하지 않는다.
package com.yehsung.aingcheck.ui.screens.me

import com.yehsung.aingcheck.core.rules.insights.TokenDailyGrid
import com.yehsung.aingcheck.core.rules.insights.WorkDailyGrid
import com.yehsung.aingcheck.core.stores.me.MeGrassAxis
import com.yehsung.aingcheck.core.stores.me.MeText
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GrassDetailRulesTest {
    /** 2026-08-31(월) 00:00 KST. */
    private val monday = 1_788_102_000.0

    @Test
    fun pitchAndWeekdayHitTesting() {
        assertEquals(50f, GrassDetailRules.pitch(350f))
        assertEquals(46f, GrassDetailRules.cell(350f))
        assertEquals(0f, GrassDetailRules.pitch(0f))
        assertTrue(GrassDetailMetrics.pitchAt(360f) >= GrassDetailRules.MINIMUM_PITCH, "360dp 폰에서도 칸 피치가 44 이상(전치한 이유)")
        assertEquals(0, GrassDetailRules.weekday(0f, 350f))
        assertEquals(0, GrassDetailRules.weekday(49.9f, 350f))
        assertEquals(1, GrassDetailRules.weekday(50f, 350f))
        assertEquals(6, GrassDetailRules.weekday(349.9f, 350f))
        assertNull(GrassDetailRules.weekday(350f, 350f), "칸 밖")
        assertNull(GrassDetailRules.weekday(-1f, 350f))
    }

    @Test
    fun steppingStopsAtWindowEdgesAndFuture() {
        // 13주 창 · 오늘 = 12주 차 화요일(오프셋 85 → dayCount 86).
        val today = GrassCell(12, 1)
        assertEquals(today, GrassDetailRules.latest(13, 86))
        assertEquals(GrassCell(12, 0), GrassDetailRules.stepped(today, -1, 13, 86))
        assertEquals(GrassCell(11, 6), GrassDetailRules.stepped(GrassCell(12, 0), -1, 13, 86), "주를 넘어 일요일로")
        assertNull(GrassDetailRules.stepped(today, 1, 13, 86), "미래는 못 간다")
        assertNull(GrassDetailRules.stepped(GrassCell(0, 0), -1, 13, 86), "창 앞은 못 간다")
        assertEquals(GrassCell(12, 6), GrassDetailRules.latest(13, 200), "날 수가 창보다 많으면 창 끝")
        assertNull(GrassDetailRules.latest(0, 5))
        assertNull(GrassDetailRules.latest(13, 0))
    }

    @Test
    fun monthSectionsFollowTheSundayOfEachWeek() {
        val sections = GrassDetailRules.monthSections(monday, 13)
        assertEquals(listOf(GrassMonthSection(9, 0..3), GrassMonthSection(10, 4..7), GrassMonthSection(11, 8..12)), sections)
        assertEquals(emptyList(), GrassDetailRules.monthSections(Double.NEGATIVE_INFINITY, 13), "창이 없으면 머리도 없다")
        assertEquals(emptyList(), GrassDetailRules.monthSections(monday, 0))
    }

    @Test
    fun levelsMarkFutureAndTokenWindowMismatchSilencesTokens() {
        val seconds = List(2) { w -> List(7) { d -> if (w == 0 && d == 0) 8L * 3_600 else 0L } }
        val work = WorkDailyGrid(monday, 2, seconds, 9)
        val token = TokenDailyGrid(monday, 2, List(2) { List(7) { 0L } }, 9)
        assertEquals(4, GrassDetailRules.level(MeGrassAxis.work, work, token, 0, 0), "하루 8시간 = 가장 진한 칸")
        assertEquals(0, GrassDetailRules.level(MeGrassAxis.work, work, token, 1, 1))
        assertNull(GrassDetailRules.level(MeGrassAxis.work, work, token, 1, 2), "미래 칸")
        assertTrue(GrassDetailRules.tokenUsable(true, work, token))
        assertTrue(!GrassDetailRules.tokenUsable(false, work, token), "토큰 수집을 끈 사람")
        assertTrue(!GrassDetailRules.tokenUsable(true, work, token.copy(weekStart = monday + 7 * 86_400)), "창이 어긋나면 말하지 않는다")
        assertTrue(!GrassDetailRules.tokenUsable(true, work, TokenDailyGrid.empty))
    }

    @Test
    fun valuePartsSplitAtThePhraseBoundaryOnly() {
        assertEquals(listOf("근무 2시간 30분"), GrassDetailRules.valueParts(9_000, 25_951_977, showsToken = false), "토큰을 안 보면 근무 구절 하나")
        val parts = GrassDetailRules.valueParts(9_000, 25_951_977, showsToken = true)
        assertEquals(listOf("근무 2시간 30분", "AI 25,951,977 토큰"), parts)
        assertEquals(MeText.grassValueLine(9_000, 25_951_977, true), parts.joinToString(" · "), "다시 이으면 원문 그대로")
        assertEquals(2, GrassDetailRules.valueParts(0, 0, showsToken = true).size, "0 인 날도 두 구절")
    }

    @Test
    fun emptyBarTextByPhase() {
        assertEquals("최근 12주 기록이 없어요", GrassDetailText.emptyBar(MeRecordsPhase.Ready))
        assertEquals("기록을 불러오지 못했어요", GrassDetailText.emptyBar(MeRecordsPhase.Failed))
        assertEquals("불러오는 중…", GrassDetailText.emptyBar(MeRecordsPhase.Loading))
    }
}
