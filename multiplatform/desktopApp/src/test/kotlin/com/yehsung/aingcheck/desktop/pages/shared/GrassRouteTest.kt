// W-6 #3: shellapi FlyoutRoute.Grass(axis) — c0 라우터가 내 기록 잔디 카드에서 잔디 상세를 연다(전엔 그 자리에 머물렀다).
package com.yehsung.aingcheck.desktop.pages.shared

import com.yehsung.aingcheck.core.stores.me.MeDestination
import com.yehsung.aingcheck.core.stores.me.MeGrassAxis
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoutes
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import kotlin.test.Test
import kotlin.test.assertEquals

class GrassRouteTest {
    @Test
    fun grassCardOpensGrassDetailForEachAxis() {
        for (axis in MeGrassAxis.entries) {
            val route = SharedRouter.routeOf(MeDestination.Grass(axis))
            assertEquals(FlyoutRoute.Grass(axis.name), route)
            assertEquals(SharedPage.Grass(axis), SharedRouter.pageOf(route))
            assertEquals(SharedPageKey.GRASS, SharedRouter.keyOf(SharedRouter.pageOf(route)))
        }
    }

    @Test
    fun unknownAxisReadsAsWork_andBackReturnsToRecords() {
        assertEquals(SharedPage.Grass(MeGrassAxis.work), SharedRouter.pageOf(FlyoutRoute.Grass("weird")))
        assertEquals(FlyoutRoute.Records, FlyoutRoutes.backOf(FlyoutRoute.Grass(MeGrassAxis.token.name)))
        val nav = InMemoryFlyoutNavigator(FlyoutRoute.Records)
        nav.navigate(SharedRouter.routeOf(MeDestination.Grass(MeGrassAxis.token)))
        nav.back()
        assertEquals(FlyoutRoute.Records, nav.route.value, "잔디 상세에서 뒤로 = 내 기록")
    }

    @Test
    fun otherMeDestinationsKeepTheirRoutes() {
        assertEquals(FlyoutRoute.Shop, SharedRouter.routeOf(MeDestination.Shop))
        assertEquals(FlyoutRoute.Missions, SharedRouter.routeOf(MeDestination.Missions))
        assertEquals(FlyoutRoute.Blocked, SharedRouter.routeOf(MeDestination.Blocked))
    }
}
