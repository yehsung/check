// 원본: Sources/CheckMobileKit/Me/MeGrassDetailView.swift @ 3bd04bd (칸을 탭하면 아래 고정 막대에 그 날 값 · 하루 전/뒤 · 미래 칸 탭은 선택 유지)
//
// 데모 픽스처로 루트 새로고침을 끝낸 나 스토어(오늘 = 2026-09-17 목)를 잔디 상세에 얹고 누름이 막대의 날짜를 바꾸는지 잰다(java.awt.headless=true).
// 기준선(다른 입력): 미래 칸(같은 주 토요일)을 누르면 막대는 그대로다 — 과거 칸 누름과 결과가 갈려야 시험이 뜻이 있다.
package com.yehsung.aingcheck.ui.screens.me

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.click
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.me.MeGrassAxis
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.screens.settingscommon.ScreenScenes
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class)
class GrassDetailInteractionDesktopTest {
    @BeforeTest
    fun headless() {
        System.setProperty("java.awt.headless", "true")
    }

    private fun date(store: MeStore, cell: GrassCell): String =
        MeText.grassDetailDate(SwiftDate(store.dailyGrid.weekStart), cell.week, cell.weekday)

    private fun scope() = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)

    @Test
    fun opensOnTodayStepsBackAndForward() {
        val store = ScreenScenes.me()
        runComposeUiTest { stepping(store) }
    }

    private fun androidx.compose.ui.test.ComposeUiTest.stepping(store: MeStore) {
        val grid = store.dailyGrid
        val today = requireNotNull(GrassDetailRules.latest(grid.weeks, grid.days))
        assertEquals(3, today.weekday, "픽스처 오늘은 목요일(2026-09-17)")
        setContent { AingTheme(dark = false) { Box(Modifier.size(380.dp, 820.dp)) { GrassDetailScreen(store, MeGrassAxis.work, scope()) } } }

        onNodeWithText(date(store, today)).assertExists()
        onNodeWithTag(GrassDetailTags.STEP_FORWARD).assertIsNotEnabled()
        onNodeWithTag(GrassDetailTags.STEP_BACK).assertIsEnabled().performClick()
        waitForIdle()
        onNodeWithText(date(store, GrassCell(today.week, today.weekday - 1))).assertExists()
        onNodeWithText(date(store, today)).assertDoesNotExist()
        onNodeWithTag(GrassDetailTags.STEP_FORWARD).assertIsEnabled().performClick()
        waitForIdle()
        onNodeWithText(date(store, today)).assertExists()
    }

    @Test
    fun tappingAPastCellSelectsItButAFutureCellKeepsTheSelection() {
        val store = ScreenScenes.me()
        runComposeUiTest { tapping(store) }
    }

    private fun androidx.compose.ui.test.ComposeUiTest.tapping(store: MeStore) {
        val grid = store.dailyGrid
        val today = requireNotNull(GrassDetailRules.latest(grid.weeks, grid.days))
        setContent { AingTheme(dark = false) { Box(Modifier.size(380.dp, 820.dp)) { GrassDetailScreen(store, MeGrassAxis.work, scope()) } } }

        // 기준선: 오늘 주 토요일(미래) — 막대는 오늘 그대로.
        onNodeWithTag(GrassDetailTags.row(today.week)).performScrollTo().performTouchInput { click(Offset(width * (5 + 0.5f) / 7f, height / 2f)) }
        waitForIdle()
        onNodeWithText(date(store, today)).assertExists()

        // 과거 칸: 오늘 주 월요일.
        onNodeWithTag(GrassDetailTags.row(today.week)).performTouchInput { click(Offset(width * 0.5f / 7f, height / 2f)) }
        waitForIdle()
        val monday = GrassCell(today.week, 0)
        assertTrue(monday != today)
        onNodeWithText(date(store, monday)).assertExists()
        onNodeWithText(date(store, today)).assertDoesNotExist()
    }
}
