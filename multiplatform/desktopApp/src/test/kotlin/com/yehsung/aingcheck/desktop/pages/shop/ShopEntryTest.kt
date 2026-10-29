// 원본: WorkTimerStoreGacha.swift:149-158(openGachaWindow — gachaWindowHooks.show() 뒤 dismissMenuPopover()) · CheckMenuView.swift:1063-1085(창 먼저, 팝오버 나중)
package com.yehsung.aingcheck.desktop.pages.shop

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.desktop.pages.missions.MissionsFlyoutPage
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoutes
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import com.yehsung.aingcheck.desktop.windows.kit.DesktopGameWindows
import kotlinx.coroutines.flow.StateFlow
import kotlin.test.Test
import kotlin.test.assertEquals

class ShopEntryTest {
    private val log = mutableListOf<String>()

    private val windows = object : DesktopGameWindows {
        override fun openGames(kind: MiniGameKind?) { log += "games" }
        override fun openGomoku(focusMatchID: String?) { log += "gomoku" }
        override fun openChess(focusMatchID: String?) { log += "chess" }
        override fun openTetrisDuel(focusMatchID: String?) { log += "tetris" }
        override fun openGacha() { log += "gacha" }
        override fun openCakeGift() { log += "cake" }
        override fun closeAll() { log += "closeAll" }
    }

    private class RecordingNav(private val inner: InMemoryFlyoutNavigator, private val log: MutableList<String>) : FlyoutNavigator {
        override val visible: StateFlow<Boolean> get() = inner.visible
        override val route: StateFlow<FlyoutRoute> get() = inner.route
        override fun open(route: FlyoutRoute?) { log += "open"; inner.open(route) }
        override fun navigate(route: FlyoutRoute) { log += "navigate"; inner.navigate(route) }
        override fun back() { log += "back"; inner.back() }
        override fun hide() { log += "hide"; inner.hide() }
    }

    /** ★ 창 먼저, 플라이아웃 나중 — 뽑기 창 열기만, 다른 창은 안 연다. */
    @Test
    fun openMachineOpensWindowBeforeHidingFlyout() {
        val inner = InMemoryFlyoutNavigator(FlyoutRoute.Shop)
        inner.open(FlyoutRoute.Shop)
        ShopEntry.openMachine(windows, RecordingNav(inner, log))
        assertEquals(listOf("gacha", "hide"), log)
        assertEquals(false, inner.visible.value)
    }

    /** W-3 #3: 상점·미션은 플라이아웃 페이지 — 뒤로는 홈. */
    @Test
    fun pagesSitOnTheirRoutes() {
        assertEquals(FlyoutRoute.Shop, ShopEntry.route)
        assertEquals(FlyoutRoute.Missions, MissionsFlyoutPage.route)
        assertEquals(FlyoutRoute.Home, FlyoutRoutes.backOf(ShopEntry.route))
        assertEquals(FlyoutRoute.Home, FlyoutRoutes.backOf(MissionsFlyoutPage.route))
    }
}
