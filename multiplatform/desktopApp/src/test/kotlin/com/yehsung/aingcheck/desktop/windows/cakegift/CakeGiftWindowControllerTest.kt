// 원본: Sources/check/CheckCakeGiftWindow.swift:340-375(show(activating:) · close · windowWillClose → cakeGiftDidClose) · WorkTimerStoreCakeGift.swift:260-275
// 창 0 — 가짜 손잡이·가짜 시트 사실로 창 규칙 ①~④(CakeGiftWindow.kt 머리 주석 번호)를 잰다.
package com.yehsung.aingcheck.desktop.windows.cakegift

import com.yehsung.aingcheck.desktop.windows.gacha.FakeWindowHandle
import com.yehsung.aingcheck.desktop.windows.gacha.MemoryBounds
import com.yehsung.aingcheck.desktop.windows.gacha.ShowFocus
import com.yehsung.aingcheck.desktop.windows.gacha.WORK_AREA
import com.yehsung.aingcheck.desktop.windows.kit.WindowEvent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CakeGiftWindowControllerTest {
    private class Facts(var sheet: Boolean = false, var claiming: Boolean = false) : CakeGiftFacts {
        var dismissals = 0
        override val hasSheet: Boolean get() = sheet
        override val isClaiming: Boolean get() = claiming
        override fun dismiss() {
            dismissals++
            if (!claiming) sheet = false
        }
    }

    private class Rig {
        val facts = Facts()
        val focus = ShowFocus()
        val handles = mutableListOf<FakeWindowHandle>()
        val c = CakeGiftWindowController(facts, { FakeWindowHandle().also { handles += it } }, MemoryBounds(), { listOf(WORK_AREA) }, { 1.0 }, focus)
        val handle: FakeWindowHandle get() = handles.single()
    }

    /** ① 시트가 서면 창이 선다. 스스로 띄울 때는 키를 가져가지 않는다. 열린 창은 다시 열지 않는다. */
    @Test
    fun sheetOpensWindowWithoutStealingFocus() {
        val r = Rig()
        assertFalse(r.c.sync(activating = false), "시트가 없는데 창이 섰다")
        assertEquals(0, r.handles.size, "시트가 없으면 창을 만들지도 않는다(지연 생성)")
        r.facts.sheet = true
        assertTrue(r.c.sync(activating = false))
        assertTrue(r.handle.visible)
        assertFalse(r.focus.activate, "스스로 띄운 창이 키를 가져간다")
        r.c.onEvent(WindowEvent.Minimized)
        assertFalse(r.c.sync(activating = false), "최소화한 창을 스스로 되살렸다")
        assertEquals(1, r.handle.shows)
    }

    /** ② × 로 닫으면 시트 닫기(맥 cakeGiftDidClose) — 한 번. */
    @Test
    fun userCloseDismissesSheet() {
        val r = Rig()
        r.facts.sheet = true
        r.c.sync(activating = true)
        assertTrue(r.focus.activate)
        r.c.onEvent(WindowEvent.UserClosed)
        assertEquals(1, r.facts.dismissals)
        assertFalse(r.handle.visible)
        assertFalse(r.handle.disposed, "닫아도 파괴하지 않는다")
        r.c.sync(activating = false) // 시트가 걷혔다 — 이미 닫힌 창에 또 통지하지 않는다
        assertEquals(1, r.facts.dismissals)
    }

    /** ③ 시트가 걷히면(받은 뒤 [닫기] · 로그아웃) 프로그램 닫기 — 시트 닫기 통지 없음. */
    @Test
    fun sheetGoneClosesWindowSilently() {
        val r = Rig()
        r.facts.sheet = true
        r.c.sync(activating = false)
        r.facts.sheet = false
        r.c.sync(activating = false)
        assertFalse(r.handle.visible)
        assertEquals(0, r.facts.dismissals, "프로그램 닫기가 시트 닫기를 불렀다")
        r.facts.sheet = true
        assertTrue(r.c.sync(activating = false), "다음 선물 시트에 창이 다시 안 선다")
        assertEquals(1, r.handles.size)
    }

    /** ④ 받는 중에는 닫지 않는다 — 창도 시트도 그대로. */
    @Test
    fun claimingRefusesUserClose() {
        val r = Rig()
        r.facts.sheet = true
        r.c.sync(activating = false)
        r.facts.claiming = true
        r.c.onEvent(WindowEvent.UserClosed)
        assertTrue(r.handle.visible, "받는 중에 창이 닫혔다")
        assertEquals(0, r.facts.dismissals)
        r.facts.claiming = false
        r.c.onEvent(WindowEvent.UserClosed)
        assertFalse(r.handle.visible)
        assertEquals(1, r.facts.dismissals)
    }
}
