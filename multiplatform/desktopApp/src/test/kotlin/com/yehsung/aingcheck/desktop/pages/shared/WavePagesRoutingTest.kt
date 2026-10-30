// int-w2 배선(pages) — 3차 페이지 라우트·레일·본문 폭·첫 실행 판정. 맥 대조: CheckMenuView.swift 421-429(본문 + 레일) · 762-799(미션 = 본문 안)
// · 1002-1010(레일 [미션] isActive). 깃발 판정은 페이지 쪽 함수(SocialPageFlags) 하나와 견준다.
package com.yehsung.aingcheck.desktop.pages.shared

import androidx.compose.runtime.Composable
import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionProfile
import com.yehsung.aingcheck.desktop.pages.poke.SocialPageFlags
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

class WavePagesRoutingTest {
    private val team = SessionProfile("u1", "a@b.c", teamID = "t1")
    private val on = DesktopAppConfig(poke = true, ultra = true)
    private val combos = listOf(false, true).flatMap { p -> listOf(false, true).map { u -> DesktopAppConfig(poke = p, ultra = u) } }

    private fun resolve(route: FlyoutRoute, config: DesktopAppConfig = on, runtime: (FlyoutRoute) -> Boolean = { true }) =
        SharedRouter.resolve(SessionPhase.SignedIn, team, true, route, config, runtime)

    private class Marker : FlyoutPageHost {
        @Composable
        override fun Content(nav: FlyoutNavigator, widthDip: Double) = Unit
    }

    @Test
    fun `3차 라우트는 제 페이지로 — 상점·고정 안내만 Pending`() {
        assertEquals(SharedPage.Home, resolve(FlyoutRoute.Home))
        assertEquals(SharedPage.PokeList, resolve(FlyoutRoute.PokeList))
        assertEquals(SharedPage.Ultra, resolve(FlyoutRoute.Ultra))
        assertEquals(SharedPage.AiTokens, resolve(FlyoutRoute.AiTokens))
        assertEquals(SharedPage.AiLimits, resolve(FlyoutRoute.AiLimits))
        assertEquals(SharedPage.Devices, resolve(FlyoutRoute.Devices))
        assertEquals(SharedPage.DesktopSettings, resolve(FlyoutRoute.DesktopSettings))
        assertEquals(SharedPage.Pending(FlyoutRoute.Shop), resolve(FlyoutRoute.Shop))
        assertEquals(SharedPage.Pending(FlyoutRoute.PinToTaskbar), resolve(FlyoutRoute.PinToTaskbar))
    }

    @Test
    fun `깃발 네 조합 — 라우트·레일 칸이 페이지 쪽 판정과 같은 답`() {
        for (c in combos) {
            val visible = SocialPageFlags.visibleRoutes(c)
            assertEquals(if (FlyoutRoute.PokeList in visible) SharedPage.PokeList else SharedPage.Home, resolve(FlyoutRoute.PokeList, c), "$c 콕")
            assertEquals(if (FlyoutRoute.Ultra in visible) SharedPage.Ultra else SharedPage.Home, resolve(FlyoutRoute.Ultra, c), "$c 울트라")
            val slots = SharedRail.slots(SharedPage.Home, c, miniGameAvailable = true)
            assertEquals(SocialPageFlags.surfaces(c).pokeList, RailSlot.POKE in slots, "$c 레일 콕 칸")
            assertEquals(c.poke, RailSlot.POKE in slots, "$c 레일 콕 칸 = poke 깃발")
        }
    }

    @Test
    fun `실행 중 판정 — AI 리밋은 연동이 있을 때만, 기기는 두 대부터, 숨으면 홈`() {
        assertFalse(RuntimeRouteRules.shown(FlyoutRoute.AiLimits, aiLimitsAvailable = false, deviceCount = 3))
        assertTrue(RuntimeRouteRules.shown(FlyoutRoute.AiLimits, aiLimitsAvailable = true, deviceCount = 0))
        assertFalse(RuntimeRouteRules.shown(FlyoutRoute.Devices, aiLimitsAvailable = true, deviceCount = 1))
        assertTrue(RuntimeRouteRules.shown(FlyoutRoute.Devices, aiLimitsAvailable = true, deviceCount = 2))
        assertTrue(RuntimeRouteRules.shown(FlyoutRoute.AiTokens, aiLimitsAvailable = false, deviceCount = 0))
        assertTrue(RuntimeRouteRules.shown(FlyoutRoute.DesktopSettings, aiLimitsAvailable = false, deviceCount = 0))
        val noLimits: (FlyoutRoute) -> Boolean = { RuntimeRouteRules.shown(it, aiLimitsAvailable = false, deviceCount = 0) }
        assertEquals(SharedPage.Home, resolve(FlyoutRoute.AiLimits, runtime = noLimits))
        assertEquals(SharedPage.Home, resolve(FlyoutRoute.Devices, runtime = noLimits))
        assertEquals(SharedPage.AiTokens, resolve(FlyoutRoute.AiTokens, runtime = noLimits))
    }

    @Test
    fun `레일 켜짐 — 홈 칸은 홈, 콕 칸은 콕·울트라, 설정 칸은 PC 설정까지`() {
        assertTrue(SharedRail.isActive(RailSlot.HOME, SharedPage.Home))
        assertFalse(SharedRail.isActive(RailSlot.HOME, SharedPage.Pending(FlyoutRoute.Home)))
        assertTrue(SharedRail.isActive(RailSlot.POKE, SharedPage.PokeList))
        assertTrue(SharedRail.isActive(RailSlot.POKE, SharedPage.Ultra))
        assertTrue(SharedRail.isActive(RailSlot.SETTINGS, SharedPage.DesktopSettings))
        assertTrue(SharedRail.isActive(RailSlot.MISSIONS, SharedPage.Missions))
        assertFalse(SharedRail.isActive(RailSlot.SETTINGS, SharedPage.AiTokens))
    }

    @Test
    fun `W-13 #9 미션·상점은 레일 옆 본문 폭으로 — 맥 본문 316 + 레일 64`() {
        val missions = Marker()
        val shop = Marker()
        val pages = RoutePages(shop = shop, missions = missions)
        assertSame(missions, pages.hostFor(SharedPage.Missions))
        assertSame(shop, pages.hostFor(SharedPage.Pending(FlyoutRoute.Shop)))
        assertNull(pages.hostFor(SharedPage.Pending(FlyoutRoute.PinToTaskbar)))
        assertNull(pages.hostFor(SharedPage.Messages))
        // 미션 화면에서도 레일이 선다(맥 [미션] 칸이 켜진 채 보인다) → 본문 폭은 레일 몫을 뺀다.
        assertTrue(SharedRail.slots(SharedPage.Missions, on, miniGameAvailable = true).contains(RailSlot.MISSIONS))
        assertEquals(350.0, RouteBodyWidth.of(414.0, railShown = true))
        assertEquals(414.0, RouteBodyWidth.of(414.0, railShown = false))
    }

    @Test
    fun `첫 실행 화면 — 대기 중이면 로그인 전후 모두, 실행 중·다른 실행·업데이트 필요는 그 화면이 먼저`() {
        assertTrue(SharedRouter.showsFirstRun(true, SharedPage.SignedOut))
        assertTrue(SharedRouter.showsFirstRun(true, SharedPage.Home))
        assertTrue(SharedRouter.showsFirstRun(true, SharedPage.Teamless))
        assertFalse(SharedRouter.showsFirstRun(false, SharedPage.Home))
        assertFalse(SharedRouter.showsFirstRun(true, SharedPage.Launching))
        assertFalse(SharedRouter.showsFirstRun(true, SharedPage.AnotherInstance))
        assertFalse(SharedRouter.showsFirstRun(true, SharedPage.NeedsUpdate(99)))
    }
}
