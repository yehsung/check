// 조정자 핀 시험(xplat-w2/pins.md E) — 갈래는 읽기만. 라우트 규약 3 · 업데이트 판정.
package com.yehsung.aingcheck.desktop.shellapi

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ShellApiPinTest {
    @Test
    fun messageArrivalRouteRule3() {
        assertEquals(FlyoutRoute.PokeList, FlyoutRoutes.forMessageArrival(null, pokeEnabled = true))
        assertEquals(FlyoutRoute.Messages, FlyoutRoutes.forMessageArrival(null, pokeEnabled = false))
        assertEquals(FlyoutRoute.Conversation("u1", Entry.NOTIFICATION), FlyoutRoutes.forMessageArrival("u1", pokeEnabled = false))
        assertEquals(FlyoutRoute.Conversation("u1", Entry.OVERLAY), FlyoutRoutes.forMessageArrival("u1", true, Entry.OVERLAY))
    }

    @Test
    fun backOfConversationDependsOnEntry() {
        assertNull(FlyoutRoutes.backOf(FlyoutRoute.Home))
        assertEquals(FlyoutRoute.Messages, FlyoutRoutes.backOf(FlyoutRoute.Conversation("u1", Entry.MESSAGES)))
        assertEquals(FlyoutRoute.Home, FlyoutRoutes.backOf(FlyoutRoute.Conversation("u1", Entry.OVERLAY)))
        assertEquals(FlyoutRoute.Home, FlyoutRoutes.backOf(FlyoutRoute.Conversation("u1", Entry.NOTIFICATION)))
        assertEquals(FlyoutRoute.Home, FlyoutRoutes.backOf(FlyoutRoute.Missions))
        val nav = InMemoryFlyoutNavigator()
        nav.open(FlyoutRoute.Conversation("u1", Entry.NOTIFICATION))
        nav.back()
        assertEquals(FlyoutRoute.Home, nav.route.value)
        nav.back()
        assertFalse(nav.visible.value, "Home 에서 뒤로 = 숨김")
    }

    @Test
    fun updateAvailableOnlyWhenLatestIsNewer() {
        assertFalse(DesktopUpdateState(currentBuild = 5).updateAvailable)
        assertFalse(DesktopUpdateState(currentBuild = 5, latestBuild = 5).updateAvailable)
        assertTrue(DesktopUpdateState(currentBuild = 5, latestBuild = 6).updateAvailable)
        assertFalse(BalloonNotifier.None.showBalloon("t", "b", NotifyKind.MESSAGE, respectQuietTime = true))
    }
}
