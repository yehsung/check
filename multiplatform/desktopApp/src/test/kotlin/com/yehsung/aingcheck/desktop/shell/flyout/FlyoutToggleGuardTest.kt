// 원본: 설계 D-windows-platform §3-3 — 토글 경합: 비활성화로 닫힌 지 300ms 안에 같은 아이콘 클릭이 오면 무시한다(★4 한 문).
package com.yehsung.aingcheck.desktop.shell.flyout

import com.yehsung.aingcheck.desktop.platform.windows.flyout.FlyoutPlacer
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxPoint
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FlyoutToggleGuardTest {
    private fun controller(clock: FakeClock = FakeClock(), surface: FakeSurface = FakeSurface(), icon: PxRect? = null) =
        FlyoutController(surface, { SyntheticScreen.facts }, { icon }, clock = { clock.read() }) to surface

    @Test
    fun guardBoundaryIs300msExactly() {
        val g = FlyoutToggleGuard()
        assertFalse(g.shouldIgnoreClick(0), "닫힌 적 없으면 막지 않는다")
        g.markClosedByDeactivation(1_000)
        assertTrue(g.shouldIgnoreClick(1_000))
        assertTrue(g.shouldIgnoreClick(1_299))
        assertFalse(g.shouldIgnoreClick(1_300))
    }

    @Test
    fun deactivatedAtTThenClickAtT299IgnoredAndT300Opens() {
        val clock = FakeClock()
        val (c, surface) = controller(clock)
        c.onTrayPrimaryClick(1800, 1050)
        assertTrue(c.visible.value)
        clock.now = 1_000
        c.onDeactivated() // 아이콘을 누르는 순간 창이 먼저 비활성화된다
        assertFalse(c.visible.value)
        clock.now = 1_299
        c.onTrayPrimaryClick(1800, 1050)
        assertFalse(c.visible.value, "t+299ms 클릭은 무시(다시 열리면 토글이 깨진다)")
        assertEquals(1, surface.shown.size)
        clock.now = 1_300
        c.onTrayPrimaryClick(1800, 1050)
        assertTrue(c.visible.value, "t+300ms 는 연다")
        assertEquals(2, surface.shown.size)
    }

    @Test
    fun clickWhileOpenClosesAndEscapeDoesNotArmTheGuard() {
        val clock = FakeClock()
        val (c, surface) = controller(clock)
        c.onTrayPrimaryClick(1800, 1050)
        c.onTrayPrimaryClick(1800, 1050)
        assertFalse(c.visible.value)
        assertEquals(1, surface.hides)
        c.onTrayPrimaryClick(1800, 1050)
        clock.now = 10
        c.onEscape()
        clock.now = 20
        c.onTrayPrimaryClick(1800, 1050)
        assertTrue(c.visible.value, "Esc 로 닫은 뒤 클릭은 바로 연다")
    }

    @Test
    fun placementIsFlyoutPlacerResultAndReplacesOnContentHeight() {
        val icon = PxRect(1700, 1040, 1724, 1064)
        val (c, surface) = controller(icon = icon)
        c.open()
        val anchor = PxPoint(1712, 1052)
        assertEquals(FlyoutPlacer.place(SyntheticScreen.facts.request(anchor, icon, FlyoutController.DEFAULT_CONTENT_HEIGHT_DIP)), surface.shown.single())
        c.onContentHeight(300.0)
        assertEquals(FlyoutPlacer.place(SyntheticScreen.facts.request(anchor, icon, 300.0)), surface.shown.last())
        assertEquals(surface.shown.last().rect.bottom, surface.shown.first().rect.bottom, "작업 표시줄 쪽 모서리 고정")
        c.onContentHeight(300.0)
        assertEquals(2, surface.shown.size, "같은 높이는 다시 올리지 않는다")
        assertEquals(FlyoutPlacer.WIDTH_DIP, c.widthDip)
    }

    @Test
    fun narrowWidthIsPassedToPlacer() {
        val c = FlyoutController(FakeSurface(), { SyntheticScreen.facts }, clock = { 0L }, requestedWidthDip = { FlyoutPlacer.NARROW_WIDTH_DIP })
        c.open()
        assertEquals(FlyoutPlacer.NARROW_WIDTH_DIP, c.widthDip)
        assertEquals(340, c.placement!!.rect.width)
    }

    @Test
    fun star4OpenWithoutAnchorUsesNotificationAreaEndAndOpenWhileVisibleOnlyNavigates() {
        val (c, surface) = controller()
        c.open(FlyoutRoute.Messages)
        val anchor = FlyoutAnchors.fallback(SyntheticScreen.facts)
        assertEquals(PxPoint(1919, 1056), anchor)
        assertEquals(FlyoutPlacer.place(SyntheticScreen.facts.request(anchor, null, FlyoutController.DEFAULT_CONTENT_HEIGHT_DIP)), surface.shown.single())
        c.open(FlyoutRoute.Settings)
        assertEquals(FlyoutRoute.Settings, c.route.value)
        assertEquals(1, surface.shown.size)
        c.navigate(FlyoutRoute.Home)
        c.back()
        assertFalse(c.visible.value, "홈에서 뒤로 = 닫기")
    }
}
