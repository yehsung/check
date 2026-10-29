// 원본: Sources/check/CheckMiniGameWindow.swift:150-243(지연 생성 · 멱등 열기 · 닫아도 파괴 안 함) ·
//       CheckGomokuWindow.swift:384-419(고착 감시자 · 재생성 3회 상한) (W4-d — 가짜 손잡이로 창 0)
package com.yehsung.aingcheck.desktop.windows.kit

import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertSame
import kotlin.test.assertTrue

class GameWindowSlotTest {
    private class FakeHandle : GameWindowHandle {
        override var isMinimized = false
        override var isOnScreen = false
        var bounds = PxRect(0, 0, 0, 0)
        val calls = mutableListOf<String>()
        override fun restoreFromMinimized() { calls += "restore"; isMinimized = false }
        override fun showAndFocus() { calls += "show"; isOnScreen = true }
        override fun hide() { calls += "hide"; isOnScreen = false }
        override fun boundsPx() = bounds
        override fun setBoundsPx(rect: PxRect) { bounds = rect }
        override fun dispose() { calls += "dispose" }
    }

    private val work = listOf(PxRect(0, 0, 1920, 1040))
    private val created = mutableListOf<FakeHandle>()
    private val notices = mutableListOf<StoreNotice>()
    private val kv = InMemoryDesktopKeyValueStore()

    private fun slot(kind: GameWindowKind) = GameWindowSlot(
        kind, create = { FakeHandle().also { created += it } }, bounds = KeyValueWindowBoundsStore(kv),
        workAreas = { work }, scale = { 1.0 }, onNotices = { notices += it },
    )

    @Test
    fun lazyCreationAndIdempotentOpen() {
        val s = slot(GameWindowKind.Gomoku)
        assertFalse(s.isCreated)
        assertEquals(0, created.size)
        s.open(); s.open()
        assertEquals(1, created.size, "두 번 열어도 창은 하나")
        assertEquals(PxRect(740, 160, 1180, 880), created[0].bounds)
        assertEquals(listOf<StoreNotice>(StoreNotice.DidShow, StoreNotice.DidShow), notices)
    }

    @Test
    fun minimizedWindowIsRestoredOnOpen() {
        val s = slot(GameWindowKind.Chess)
        s.open()
        created[0].isMinimized = true
        s.onEvent(WindowEvent.Minimized)
        s.open()
        assertEquals(listOf("show", "restore", "show"), created[0].calls)
        assertTrue(s.presence.isActive)
    }

    @Test
    fun userCloseHidesWithoutDisposingAndKeepsBounds() {
        val s = slot(GameWindowKind.Gomoku)
        s.open()
        created[0].bounds = PxRect(100, 100, 540, 820)
        s.onEvent(WindowEvent.UserClosed)
        assertEquals(listOf("show", "hide"), created[0].calls)
        assertEquals(listOf<StoreNotice>(StoreNotice.DidShow, StoreNotice.DidHide, StoreNotice.DidClose), notices)
        s.open()
        assertEquals(1, created.size, "닫아도 파괴 안 함 — 다시 열면 같은 창")
        assertEquals("100,100,540,820", kv.getString("windowBounds.check.gomoku.window"))
        // 새 슬롯(앱 재시작)은 저장된 자리로 연다.
        val again = slot(GameWindowKind.Gomoku)
        again.open()
        assertEquals(PxRect(100, 100, 540, 820), created.last().bounds)
    }

    @Test
    fun appCloseIsIdempotentAndMiniGameDoesNotEndRound() {
        val s = slot(GameWindowKind.MiniGame)
        s.open(); notices.clear()
        s.closeFromApp(); s.closeFromApp()
        assertEquals(emptyList<StoreNotice>(), notices, "프로그램 닫기는 미니게임 판을 건드리지 않는다")
        s.open(); notices.clear()
        s.onEvent(WindowEvent.UserClosed)
        assertEquals(listOf<StoreNotice>(StoreNotice.EndRound), notices)
    }

    @Test
    fun stuckWatchdogRecreatesAtMostThreeTimes() {
        val s = slot(GameWindowKind.Gacha)
        s.open()
        assertFalse(s.checkStuck(), "화면에 있으면 그대로")
        repeat(5) { created.last().isOnScreen = false; s.checkStuck() }
        assertEquals(GameWindowSlot.MAX_RECREATIONS, s.recreations)
        assertEquals(1 + GameWindowSlot.MAX_RECREATIONS, created.size)
        assertTrue(created.dropLast(1).all { "dispose" in it.calls })
        assertSame(created.last(), created.last())
    }
}
