// 원본: Sources/check/WorkTimerStoreInsights.swift 207-261(evaluateRetroBanner · markRetroBannerDisplayed · markRetroBannerSeen ·
//       retroBannerShownWeekKeyForCurrentUser) · Sources/check/WorkTimerStore.swift 381-386(팝오버 닫힘) · 4245(로그아웃) @ db93317f
// 공용 패치 19: 맥 분기를 표로 옮겨 하나씩 + 음성 대조. 날짜는 KST 주 경계(월요일 00:00)를 직접 찍는다. 픽스처는 합성.
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.rules.insights.WeeklyRetro
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MeRetroBannerTest {
    private companion object {
        // KST 2026-09-07(월) · 09-14(월) 00:00 · 09-17(목) 14:05 · 09-20(일) 23:59:59 · 09-21(월) 00:00
        const val PREV_MON = 1_788_706_800.0
        const val MON = 1_789_311_600.0
        const val THU = 1_789_621_500.0
        const val SUN_LAST = 1_789_916_399.0
        const val NEXT_MON = 1_789_916_400.0
        const val PREV_KEY = "2026-09-07"
        const val CUR_KEY = "2026-09-14"
        const val NEXT_KEY = "2026-09-21"
        const val USER_KEY = "check.retro.shownForWeek.user-1"
        val RETRO = WeeklyRetro(PREV_MON, 30_600, 216_000, 25_200, 4, 2, 10_800)
    }

    private fun TestScope.signedIn(): MeHarness {
        val h = MeHarness(this) { null }
        h.signIn()
        advanceUntilIdle()
        return h
    }

    /** 판정 한 줄: 입력(패널 · 팝오버 · 회고 · 저장값 · 지금 떠 있나 · 시각) → 기대(떠 있나 · 저장값). */
    private data class Row(
        val name: String,
        val panel: Boolean,
        val menu: Boolean,
        val hasRetro: Boolean,
        val stored: String?,
        val showing: Boolean,
        val now: Double,
        val expectShowing: Boolean,
        val expectStored: String?,
    )

    private val evaluateRows = listOf(
        // 맥 223-231: 개인 기록 패널을 보고 있다
        Row("패널+회고 → 소비하고 내림", true, true, true, null, true, THU, false, CUR_KEY),
        Row("패널+회고, 지난주 소비 → 이번 주로 소비", true, true, true, PREV_KEY, false, THU, false, CUR_KEY),
        Row("패널, 회고 없음, 떠 있음 → 내리기만(소비 안 함)", true, true, false, null, true, THU, false, null),
        Row("패널, 회고 없음 → 저장값 그대로", true, false, false, PREV_KEY, false, THU, false, PREV_KEY),
        // 맥 232-235: 보여 줄 회고가 없다
        Row("회고 없음, 떠 있음 → 내림", false, true, false, null, true, THU, false, null),
        Row("회고 없음, 저장 없음 → 띄우지 않음", false, true, false, null, false, THU, false, null),
        // 맥 236-242: 이번 주 몫 이미 소비
        Row("이미 봄 + 떠 있음 + 열림 → 지금 노출은 걷지 않음", false, true, true, CUR_KEY, true, THU, true, CUR_KEY),
        Row("이미 봄 + 떠 있음 + 닫힘 → 내림", false, false, true, CUR_KEY, true, THU, false, CUR_KEY),
        Row("이미 봄 + 안 떠 있음 + 열림 → 다시 올리지 않음", false, true, true, CUR_KEY, false, THU, false, CUR_KEY),
        // 맥 243: 띄운다(판정은 키를 쓰지 않는다)
        Row("저장 없음 → 띄움", false, true, true, null, false, THU, true, null),
        Row("지난주 소비 → 이번 주는 띄움", false, true, true, PREV_KEY, false, THU, true, PREV_KEY),
        // 날짜 경계(KST 월요일 00:00)
        Row("일요일 23:59:59 는 아직 같은 주 → 띄우지 않음", false, true, true, CUR_KEY, false, SUN_LAST, false, CUR_KEY),
        Row("월요일 00:00 은 새 주 → 띄움", false, true, true, CUR_KEY, false, NEXT_MON, true, CUR_KEY),
        Row("월요일 00:00 그 주의 소비 → 띄우지 않음", false, true, true, CUR_KEY, false, MON, false, CUR_KEY),
        Row("월요일 00:00, 지난주 소비 → 띄움", false, true, true, PREV_KEY, false, MON, true, PREV_KEY),
        Row("패널+회고, 월요일 00:00 → 새 주 키로 소비", true, true, true, CUR_KEY, false, NEXT_MON, false, NEXT_KEY),
    )

    @Test
    fun evaluateFollowsEveryMacBranch() = runTest {
        for (row in evaluateRows) {
            val h = signedIn()
            h.store.retro = if (row.hasRetro) RETRO else null
            h.store.showsRetroBanner = row.showing
            row.stored?.let { h.prefs.putString(USER_KEY, it) }
            val sent = h.server.requests.size
            h.store.evaluateRetroBanner(isInsightsPanelVisible = row.panel, isMenuPresented = row.menu, now = SwiftDate(row.now))
            assertEquals(row.expectShowing, h.store.showsRetroBanner, "${row.name}: 떠 있나")
            assertEquals(row.expectStored, h.prefs.getString(USER_KEY), "${row.name}: 저장값")
            advanceUntilIdle()
            assertEquals(sent, h.server.requests.size, "${row.name}: 판정이 요청을 냈다")
        }
    }

    @Test
    fun displayedConsumesOnlyWhenShowingAndSeenAlwaysConsumesAndHides() = runTest {
        // (이름, 동작, 떠 있나 전, 시각) → (떠 있나 후, 저장값)
        data class Op(val name: String, val seen: Boolean, val showing: Boolean, val now: Double, val expectShowing: Boolean, val expectStored: String?)
        val ops = listOf(
            Op("표시: 안 떠 있으면 쓰지 않음", false, false, THU, false, null),
            Op("표시: 떠 있으면 이번 주 소비 · 배너는 그대로", false, true, THU, true, CUR_KEY),
            Op("표시: 월요일 00:00 은 새 주 키", false, true, NEXT_MON, true, NEXT_KEY),
            Op("봄: 떠 있으면 소비 + 내림", true, true, THU, false, CUR_KEY),
            Op("봄: 안 떠 있어도 소비", true, false, SUN_LAST, false, CUR_KEY),
        )
        for (op in ops) {
            val h = signedIn()
            h.store.retro = RETRO
            h.store.showsRetroBanner = op.showing
            if (op.seen) h.store.markRetroBannerSeen(SwiftDate(op.now)) else h.store.markRetroBannerDisplayed(SwiftDate(op.now))
            assertEquals(op.expectShowing, h.store.showsRetroBanner, "${op.name}: 떠 있나")
            assertEquals(op.expectStored, h.prefs.getString(USER_KEY), "${op.name}: 저장값")
        }
    }

    @Test
    fun keyIsMacStringPerAccountAndOtherAccountsOrGlobalKeyDoNotSuppress() = runTest {
        val anon = MeHarness(this) { null }
        assertEquals("check.retro.shownForWeek", anon.store.retroBannerShownWeekKeyForCurrentUser, "로그인 전 키")
        assertEquals("check.retro.shownForWeek", RETRO_BANNER_SHOWN_WEEK_KEY)

        val h = signedIn()
        assertEquals(USER_KEY, h.store.retroBannerShownWeekKeyForCurrentUser, "계정 키")
        // 음성 대조: 같은 주 값이 **다른 계정 키 · 접미사 없는 옛 키** 에 있어도 이 계정의 배너는 막히지 않는다.
        h.prefs.putString("check.retro.shownForWeek", CUR_KEY)
        h.prefs.putString("check.retro.shownForWeek.user-2", CUR_KEY)
        h.store.retro = RETRO
        h.store.evaluateRetroBanner(isInsightsPanelVisible = false, isMenuPresented = true, now = SwiftDate(THU))
        assertTrue(h.store.showsRetroBanner, "남의 키가 이 계정의 배너를 막았다")
        // 양성: 이 계정 키에 같은 주 값이 있으면 막힌다.
        h.store.markRetroBannerSeen(SwiftDate(THU))
        h.store.evaluateRetroBanner(isInsightsPanelVisible = false, isMenuPresented = true, now = SwiftDate(THU))
        assertFalse(h.store.showsRetroBanner, "이 계정 키의 이번 주 값을 무시했다")
        assertEquals(CUR_KEY, h.prefs.getString("check.retro.shownForWeek.user-2"), "남의 키를 건드렸다")
        assertEquals(CUR_KEY, h.prefs.getString("check.retro.shownForWeek"), "옛 키를 건드렸다")
        // 음성 대조: 형식이 다른 값(0 채움 없음)은 이번 주가 아니다.
        h.prefs.putString(USER_KEY, "2026-9-14")
        h.store.evaluateRetroBanner(isInsightsPanelVisible = false, isMenuPresented = true, now = SwiftDate(THU))
        assertTrue(h.store.showsRetroBanner, "다른 형식의 값을 이번 주로 읽었다")
    }

    @Test
    fun oncePerWeekAcrossOpenDisplayCloseReopenThenNextWeek() = runTest {
        val h = signedIn()
        val sent = h.server.requests.size
        h.store.retro = RETRO
        // 열림 → 판정 → 그려짐(소비)
        h.store.evaluateRetroBanner(isInsightsPanelVisible = false, isMenuPresented = true, now = SwiftDate(THU))
        assertTrue(h.store.showsRetroBanner, "첫 열림에 안 떴다")
        h.store.markRetroBannerDisplayed(SwiftDate(THU))
        assertEquals(CUR_KEY, h.prefs.getString(USER_KEY))
        // 같은 열림에서 기록 계산이 끝나 다시 판정해도 지금 노출은 남는다
        h.store.evaluateRetroBanner(isInsightsPanelVisible = false, isMenuPresented = true, now = SwiftDate(THU + 5))
        assertTrue(h.store.showsRetroBanner, "떠 있던 노출을 도중에 걷었다")
        // 닫힘 → 다시 열림: 같은 주엔 다시 안 뜬다
        h.store.retroBannerMenuDidClose()
        assertFalse(h.store.showsRetroBanner, "닫혀도 남았다")
        h.store.evaluateRetroBanner(isInsightsPanelVisible = false, isMenuPresented = true, now = SwiftDate(SUN_LAST))
        assertFalse(h.store.showsRetroBanner, "같은 주에 두 번 떴다")
        // 다음 주 월요일 00:00 → 다시 뜬다
        h.store.evaluateRetroBanner(isInsightsPanelVisible = false, isMenuPresented = true, now = SwiftDate(NEXT_MON))
        assertTrue(h.store.showsRetroBanner, "새 주에 안 떴다")
        // 그려지지 못하고(더 급한 배너) 닫히면 소비되지 않아 다음 열림에 다시 뜬다
        h.store.retroBannerMenuDidClose()
        h.store.evaluateRetroBanner(isInsightsPanelVisible = false, isMenuPresented = true, now = SwiftDate(NEXT_MON + 60))
        assertTrue(h.store.showsRetroBanner, "그려지지 못한 배너가 다음 열림에 안 돌아왔다")
        assertEquals(CUR_KEY, h.prefs.getString(USER_KEY), "그려지지 않았는데 소비했다")
        advanceUntilIdle()
        assertEquals(sent, h.server.requests.size, "판정·소비가 요청을 냈다")
    }

    @Test
    fun signOutResetAndWeekDiscardLowerTheBannerWithoutTouchingTheKey() = runTest {
        val h = signedIn()
        h.store.retro = RETRO
        h.prefs.putString(USER_KEY, PREV_KEY)
        h.store.showsRetroBanner = true
        h.store.discardRecords()
        assertFalse(h.store.showsRetroBanner, "주 경계 폐기가 배너를 남겼다")
        assertEquals(PREV_KEY, h.prefs.getString(USER_KEY), "폐기가 키를 소비했다")
        h.store.showsRetroBanner = true
        h.store.reset()
        assertFalse(h.store.showsRetroBanner, "로그아웃 정리가 배너를 남겼다")
        assertEquals(PREV_KEY, h.prefs.getString(USER_KEY), "로그아웃이 계정 키를 지웠다")
        // 닫힘은 안 떠 있으면 아무것도 안 한다
        h.store.retroBannerMenuDidClose()
        assertFalse(h.store.showsRetroBanner)
    }
}
