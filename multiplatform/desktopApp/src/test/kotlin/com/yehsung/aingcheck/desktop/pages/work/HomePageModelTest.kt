// 원본: Sources/check/CheckMenuView.swift:1589-1628(HeaderCard) · CheckComponents.swift:7-46(WorkTogglePill — enabled = canSync 만)
//       · WorkTimerStore.swift:1868-1882(myLiveWeeklySeconds · canSync) · 2019-2025(toggle) · 2074 · 2138-2139(가드)
// W3-c2 — 근무 단추 한 번 = 명령 한 번 · 빠른 두 번 = 시작→종료 · 대기 중 눌림도 명령 · pendingSync 표시 · 헤더 글자.
@file:OptIn(ExperimentalTestApi::class)

package com.yehsung.aingcheck.desktop.pages.work

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.core.rules.format.MenuBarStatusFormatter
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class HomePageModelTest {
    @Test
    fun onePressIsOneCommand() {
        val w = HomeTestKit.FakeWork()
        assertTrue(HomePageModel.pressWorkToggle(enabled = true, commands = w))
        assertEquals(listOf("toggle"), w.log)
        assertEquals(listOf("started"), w.transitions)
    }

    /** 맥: SwiftUI Button 은 빠른 두 번을 막지 않고 toggle 이 스토어 상태로 고른다 → 시작 후 종료. 화면이 낡은 상태로 '시작' 두 번을 내지 않는다. */
    @Test
    fun quickDoublePressIsStartThenStop() {
        val w = HomeTestKit.FakeWork()
        val staleUi = HomePageModel.build(HomeTestKit.inputs(snapshot = w.flow.value), HomeTestKit.NOW)
        HomePageModel.pressWorkToggle(staleUi.header.pill.enabled, w)
        HomePageModel.pressWorkToggle(staleUi.header.pill.enabled, w) // 같은(낡은) 화면에서 두 번째 눌림
        assertEquals(listOf("toggle", "toggle"), w.log)
        assertEquals(listOf("started", "stopped"), w.transitions)
    }

    /** 맥 알약 enabled 는 canSync 만 — 동기화 대기 중에도 눌림은 명령이 된다(색·글자만 대기). canSync 거짓이면 0. */
    @Test
    fun pendingDoesNotBlockButNoKeyDoes() {
        val pending = DesktopWorkSnapshot(isWorking = true, startedAt = HomeTestKit.ago(60), pendingSync = true)
        val w = HomeTestKit.FakeWork(pending)
        val ui = HomePageModel.build(HomeTestKit.inputs(snapshot = pending), HomeTestKit.NOW)
        assertTrue(ui.header.pill.enabled)
        HomePageModel.pressWorkToggle(ui.header.pill.enabled, w)
        assertEquals(listOf("toggle"), w.log)

        val noKey = HomePageModel.build(HomeTestKit.inputs(canSync = false), HomeTestKit.NOW)
        assertFalse(noKey.header.pill.enabled)
        val w2 = HomeTestKit.FakeWork()
        assertFalse(HomePageModel.pressWorkToggle(noKey.header.pill.enabled, w2))
        assertTrue(w2.log.isEmpty())
    }

    /** 대기 표시: "동기화 대기"(core/rules WorkStatusSnapshot) · 대기 색이 근무 색보다 먼저. */
    @Test
    fun pendingSyncShowsWaitingTextAndTint() {
        val pending = DesktopWorkSnapshot(isWorking = true, startedAt = HomeTestKit.ago(60), pendingSync = true)
        val h = HomePageModel.build(HomeTestKit.inputs(snapshot = pending), HomeTestKit.NOW).header
        assertEquals("동기화 대기", h.statusText)
        assertEquals(HeaderTint.PENDING, h.tint)
        assertEquals("근무 종료", h.pill.label)
        val off = HomePageModel.build(HomeTestKit.inputs(), HomeTestKit.NOW).header
        assertEquals("근무종료", off.statusText)
        assertEquals(HeaderTint.OFF_WORK, off.tint)
        assertEquals("근무 시작", off.pill.label)
        val on = HomePageModel.build(HomeTestKit.inputs(snapshot = pending.copy(pendingSync = false)), HomeTestKit.NOW).header
        assertEquals("근무중", on.statusText)
        assertEquals(HeaderTint.WORKING, on.tint)
    }

    /** 오늘 타이머 = 오늘 누적(MM:SS/HH:MM) · 주간 = 내 행 라이브 주간(없으면 오늘 누적) · 퍼센트 반올림. */
    @Test
    fun headerTextsUseCoreFormatters() {
        val s = DesktopWorkSnapshot(isWorking = true, startedAt = HomeTestKit.ago(5 * 60 + 7))
        val alone = HomePageModel.build(HomeTestKit.inputs(snapshot = s), HomeTestKit.NOW).header
        assertEquals("05:07", alone.todayText)
        assertEquals(MenuBarStatusFormatter.duration(307), alone.todayText)
        assertEquals("이번 주 0시간 05분 / 40시간", alone.weeklyText, "내 행이 없으면 오늘 누적")
        val me = HomeTestKit.member(HomeTestKit.ME, "나", working = true, startedAgo = 307, weekly = 20L * 3600)
        val withRow = HomePageModel.build(HomeTestKit.inputs(snapshot = s, members = listOf(me)), HomeTestKit.NOW).header
        assertEquals("이번 주 20시간 05분 / 40시간", withRow.weeklyText)
        assertEquals("50%", withRow.percentText)
    }

    /** 화면 클릭: 알약 한 번 = toggle 한 번, 두 번 = 두 번(시작→종료). 근무 중 알약은 '근무 종료'로 바뀐다. */
    @Test
    fun pillClicksMapOneToOne() = runDesktopComposeUiTest(width = 414, height = 700) {
        val w = HomeTestKit.FakeWork()
        val page = HomePage(TwelveHourConfirmTest.homeDeps(w))
        setContent { AingTheme(dark = false) { page.Content(InMemoryFlyoutNavigator(), 414.0) } }
        onNodeWithText("근무 시작").performClick()
        waitForIdle()
        assertEquals(listOf("toggle"), w.log)
        onNodeWithText("근무 종료").performClick()
        waitForIdle()
        assertEquals(listOf("toggle", "toggle"), w.log)
        assertEquals(listOf("started", "stopped"), w.transitions)
    }
}
