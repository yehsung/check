// 원본: Sources/check/CheckMenuView.swift @ a90d8623 — 535-560(isSignedIn → isTeamless → 메인) · multiplatform/androidApp/…/session/SessionEntries.kt(루트 분기)
//
// W3-c0 SignedOutRoutingTest — 실행 중 → 업데이트 필요 → 로그아웃 → 다른 실행 → 무소속 → 라우트 분기, 그리고 W-3 #17 깃발 숨김.
// 표 시험(순수) + 진짜 SessionStore 위의 흐름 시험(launch · adoptSignedInSession · 소속 읽기 → host.pages()).
package com.yehsung.aingcheck.desktop.pages.shared

import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionProfile
import com.yehsung.aingcheck.desktop.shellapi.Entry
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class SignedOutRoutingTest {
    private val off = DesktopAppConfig()
    private val withTeam = SessionProfile("u1", "a@b.c", teamID = "t1")
    private val noTeam = SessionProfile("u1", "a@b.c", teamID = null)

    @Test
    fun `세션 단계가 라우트보다 먼저다 — 실행 중·업데이트 필요·로그아웃·다른 실행`() {
        val route = FlyoutRoute.Messages
        assertEquals(SharedPage.Launching, SharedRouter.resolve(SessionPhase.Launching, withTeam, true, route, off))
        assertEquals(SharedPage.NeedsUpdate(12), SharedRouter.resolve(SessionPhase.NeedsUpdate(12), withTeam, true, route, off))
        assertEquals(SharedPage.SignedOut, SharedRouter.resolve(SessionPhase.SignedOut, null, true, route, off))
        assertEquals(SharedPage.AnotherInstance, SharedRouter.resolve(SessionPhase.AnotherInstanceRunning, null, true, route, off))
        assertEquals(SharedPage.Messages, SharedRouter.resolve(SessionPhase.SignedIn, withTeam, true, route, off))
    }

    @Test
    fun `무소속은 소속 읽기가 끝난 뒤에만 — 설정·계정 삭제·차단만 지나간다`() {
        // 읽기 전의 teamID null 은 '모른다' — 무소속 화면이 번쩍이지 않는다.
        assertEquals(SharedPage.Home, SharedRouter.resolve(SessionPhase.SignedIn, noTeam, false, FlyoutRoute.Home, off))
        assertEquals(SharedPage.Teamless, SharedRouter.resolve(SessionPhase.SignedIn, noTeam, true, FlyoutRoute.Home, off))
        assertEquals(SharedPage.Teamless, SharedRouter.resolve(SessionPhase.SignedIn, noTeam, true, FlyoutRoute.Messages, off))
        assertEquals(SharedPage.Teamless, SharedRouter.resolve(SessionPhase.SignedIn, noTeam, true, FlyoutRoute.Rankings("league"), off))
        for (allowed in listOf(FlyoutRoute.Settings, FlyoutRoute.AccountDeletion, FlyoutRoute.Blocked)) {
            assertEquals(SharedRouter.pageOf(allowed), SharedRouter.resolve(SessionPhase.SignedIn, noTeam, true, allowed, off), "$allowed")
        }
        assertEquals(listOf(RailSlot.SETTINGS), SharedRail.slots(SharedPage.Teamless, off, miniGameAvailable = true))
    }

    @Test
    fun `W-3 17 깃발 꺼진 찌르기·울트라는 라우트로 와도 홈 — 레일에도 칸이 없다`() {
        for (route in listOf(FlyoutRoute.PokeList, FlyoutRoute.Ultra)) {
            assertEquals(SharedPage.Home, SharedRouter.resolve(SessionPhase.SignedIn, withTeam, true, route, off), "$route")
        }
        assertFalse(RailSlot.POKE in SharedRail.slots(SharedPage.Home, off, miniGameAvailable = true))
        val on = DesktopAppConfig(poke = true, ultra = true)
        assertEquals(SharedPage.PokeList, SharedRouter.resolve(SessionPhase.SignedIn, withTeam, true, FlyoutRoute.PokeList, on))
        assertTrue(RailSlot.POKE in SharedRail.slots(SharedPage.Home, on, miniGameAvailable = true))
        // 미니게임 칸은 창이 있을 때만(W4-e).
        assertFalse(RailSlot.MINIGAME in SharedRail.slots(SharedPage.Messages, on, miniGameAvailable = false))
    }

    @Test
    fun `로그인 전 단계엔 레일이 없다 · 대화는 메시지 칸이 켜진다`() {
        for (page in listOf(SharedPage.Launching, SharedPage.NeedsUpdate(3), SharedPage.SignedOut, SharedPage.AnotherInstance)) {
            assertEquals(emptyList(), SharedRail.slots(page, DesktopAppConfig(poke = true), miniGameAvailable = true), "$page")
        }
        assertTrue(SharedRail.isActive(RailSlot.MESSAGES, SharedPage.Conversation("p", Entry.MESSAGES)))
        assertTrue(SharedRail.isActive(RailSlot.TEAM, SharedPage.Rankings("tokens")))
        assertEquals(FlyoutRoute.Rankings("league"), SharedRail.route(RailSlot.TEAM))
    }

    @Test
    fun `진짜 세션 — 금고가 비면 로그아웃 · 최소 빌드가 높으면 업데이트 필요`() = runTest {
        val h = SharedTestHarness(this)
        h.session.launch()
        advanceUntilIdle()
        assertEquals(SharedPage.SignedOut, h.host.pages(h.nav).first())

        val u = SharedTestHarness(this, answer = { p -> if (p.endsWith("/rpc/client_release")) SharedTestHarness.RELEASE_NEEDS_UPDATE else null })
        u.session.launch()
        advanceUntilIdle()
        assertEquals(SharedPage.NeedsUpdate(99), u.host.pages(u.nav).first())
    }

    @Test
    fun `진짜 세션 — 소속 읽기가 빈 배열이면 무소속, 소속이 있으면 라우트`() = runTest {
        val lone = SharedTestHarness(this, answer = SharedTestHarness.teamless)
        val seen = mutableListOf<SharedPage>()
        val job = launch { lone.host.pages(lone.nav).collect { seen += it } }
        lone.signIn()
        advanceUntilIdle()
        assertEquals(SharedPage.Teamless, seen.last(), "seen=$seen")
        // 소속을 읽기 전 프레임에 무소속이 먼저 서지 않는다(번쩍임 0).
        val firstSignedIn = seen.indexOfFirst { it != SharedPage.Launching && it != SharedPage.SignedOut }
        assertEquals(SharedPage.Home, seen[firstSignedIn], "seen=$seen")
        job.cancel()

        val team = SharedTestHarness(this, answer = SharedTestHarness.withTeam)
        team.signIn()
        advanceUntilIdle()
        team.nav.open(FlyoutRoute.Messages)
        assertEquals(SharedPage.Messages, team.host.pages(team.nav).first())
    }
}
