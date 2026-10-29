// 원본: multiplatform/androidApp/…/rankings/RankingsRouteScreen.kt · me/MeHomeRouteScreen.kt (tabDidAppear / onDispose tabDidDisappear)
//
// W3-c0 FlyoutLifecycleTest — 페이지 활성 = visible && route 가 그 페이지(핀 FlyoutNavigator 주석의 한 식).
//  · visible=false 면 그 페이지 disappear(숨은 창은 구성 해제가 아니다 — 고리가 직접 부른다).
//  · 같은 페이지 재진입(같은 라우트 다시 · 판만 바뀐 순위 · 같은 값 두 번)은 중복 0.
//  · 플라이아웃 활성(appDidBecomeActive/EnterBackground)은 페이지 appear 앞 · disappear 뒤.
//  · 진짜 스토어(RankingsStore.isTabVisible)가 숨김과 함께 꺼진다.
package com.yehsung.aingcheck.desktop.pages.shared

import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class FlyoutLifecycleTest {
    private val log = mutableListOf<String>()

    private fun tracker() = SharedPageLifecycle(
        hooksFor = { key -> PageHooks({ log += "+$key" }, { log += "-$key" }) },
        onFlyoutActive = { log += if (it) "active" else "background" },
    )

    @Test
    fun `숨기면 disappear · 다시 열면 appear — 활성은 appear 앞, 배경은 disappear 뒤`() {
        val t = tracker()
        t.update(true, SharedPage.Rankings("league"))
        t.update(false, SharedPage.Rankings("league"))
        t.update(true, SharedPage.Rankings("league"))
        assertEquals(listOf("active", "+RANKINGS", "-RANKINGS", "background", "active", "+RANKINGS"), log)
    }

    @Test
    fun `같은 페이지 재진입은 중복 0 — 같은 값 두 번 · 판만 바뀐 순위 · 상대만 바뀐 대화`() {
        val t = tracker()
        t.update(true, SharedPage.Rankings("league"))
        t.update(true, SharedPage.Rankings("league"))
        t.update(true, SharedPage.Rankings("tokens"))
        t.update(true, SharedPage.Conversation("a", com.yehsung.aingcheck.desktop.shellapi.Entry.MESSAGES))
        t.update(true, SharedPage.Conversation("b", com.yehsung.aingcheck.desktop.shellapi.Entry.MESSAGES))
        assertEquals(listOf("active", "+RANKINGS", "-RANKINGS", "+CONVERSATION"), log)
        assertEquals(1, log.count { it == "+RANKINGS" })
    }

    @Test
    fun `숨은 채 라우트가 바뀌어도 아무 페이지도 서지 않는다`() {
        val t = tracker()
        t.update(false, SharedPage.Messages)
        t.update(false, SharedPage.Records)
        assertEquals(emptyList(), log)
        t.update(true, SharedPage.Records)
        assertEquals(listOf("active", "+RECORDS"), log)
    }

    @Test
    fun `follow — 내비 흐름을 따라가고 끝나면 활성 페이지를 닫는다`() = runTest {
        val t = tracker()
        val nav = InMemoryFlyoutNavigator()
        val job = launch { t.follow(nav.visible, nav.route.map(SharedRouter::pageOf)) }
        runCurrent()
        nav.open(FlyoutRoute.Records)
        runCurrent()
        nav.navigate(FlyoutRoute.Records)
        runCurrent()
        nav.navigate(FlyoutRoute.Rankings("league"))
        runCurrent()
        nav.hide()
        runCurrent()
        nav.open()
        runCurrent()
        job.cancel()
        runCurrent()
        assertEquals(
            listOf("active", "+RECORDS", "-RECORDS", "+RANKINGS", "-RANKINGS", "background", "active", "+RANKINGS", "-RANKINGS", "background"),
            log,
        )
    }

    @Test
    fun `진짜 스토어 — 순위 페이지를 보이다 숨기면 isTabVisible 이 꺼진다`() = runTest {
        val h = SharedTestHarness(this, answer = SharedTestHarness.withTeam)
        h.signIn()
        advanceUntilIdle()
        val lifecycle = h.host.lifecycle()
        val job = launch { lifecycle.follow(h.nav.visible, h.host.pages(h.nav)) }
        h.nav.open(FlyoutRoute.Rankings("league"))
        advanceUntilIdle()
        assertTrue(h.rankings.isTabVisible, "보일 때 tabDidAppear")
        h.nav.hide()
        advanceUntilIdle()
        assertFalse(h.rankings.isTabVisible, "숨기면 tabDidDisappear")
        job.cancel()
    }
}
