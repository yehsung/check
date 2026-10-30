// 원본: Sources/check/CheckGachaWindow.swift:15-24(머리 규약 ★①·★②) · :48-78(GachaWindowState.isActive) · :441-500(show · close · windowWillClose)
// 창 0 — 가짜 손잡이로 창 수명과 기계 상태만 잰다.
package com.yehsung.aingcheck.desktop.windows.gacha

import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind
import com.yehsung.aingcheck.desktop.windows.kit.WindowEvent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GachaWindowStateTest {
    private class Facts(var pulling: Boolean = false, val cell: GachaUnrevealedCell = GachaUnrevealedCell()) : GachaMachineFacts {
        override val isPulling: Boolean get() = pulling
        override fun hasUnrevealedTurn(): Boolean = cell.value
    }

    private class Rig(val facts: Facts = Facts()) {
        val handles = mutableListOf<FakeWindowHandle>()
        val bounds = MemoryBounds()
        val c = GachaWindowController(facts, { FakeWindowHandle().also { handles += it } }, bounds, { listOf(WORK_AREA) }, { 1.0 })
        val handle: FakeWindowHandle get() = handles.single()
    }

    /** ★① isActive = 열림 ∧ ¬최소화 ∧ ¬가림 — 사건열마다 기계가 움직여도 되는가. */
    @Test
    fun isActiveTable() {
        val cases: List<Pair<List<WindowEvent>, Boolean>> = listOf(
            listOf<WindowEvent>() to true,
            listOf(WindowEvent.Minimized) to false,
            listOf(WindowEvent.Minimized, WindowEvent.Restored) to true,
            listOf(WindowEvent.Visibility(false)) to false,
            listOf(WindowEvent.Visibility(false), WindowEvent.Visibility(true)) to true,
            // 최소화된 채 가림이 풀려도(잠금 해제) 기계는 깨어나지 않는다.
            listOf(WindowEvent.Minimized, WindowEvent.Visibility(false), WindowEvent.Visibility(true)) to false,
            listOf(WindowEvent.UserClosed) to false,
            // 닫힌 창의 가림 통지는 무시한다(맥 applyOcclusion 의 guard isOpen).
            listOf(WindowEvent.UserClosed, WindowEvent.Visibility(true)) to false,
            // 키 상실·화면 이동은 기계와 무관(뽑기는 판 게임이 아니다).
            listOf(WindowEvent.FocusLost) to true,
            listOf(WindowEvent.ScreenChanged) to true,
        )
        for ((events, expected) in cases) {
            val r = Rig()
            r.c.open()
            events.forEach(r.c::onEvent)
            assertEquals(expected, r.c.state.isActive, "사건열 ${events.map { it.toString() }} 뒤 isActive")
        }
    }

    @Test
    fun programCloseStopsMachineAndKeepsWindow() {
        val r = Rig()
        r.c.open()
        assertTrue(r.c.state.isActive)
        r.c.close() // 기계의 [닫기] · 로그아웃 = 프로그램 닫기
        assertFalse(r.c.state.isActive, "프로그램 닫기 뒤 기계가 돈다")
        assertEquals(1, r.handle.hides)
        assertFalse(r.handle.disposed, "닫아도 파괴하지 않는다")
        assertTrue(GameWindowKind.Gacha.boundsKey in r.bounds.saved, "닫을 때 자리를 저장한다")
    }

    /** ★② 다시 열면 새 기계 — 사용자 닫기 · 프로그램 닫기 둘 다. 처음 열기 · 멱등 열기 · 최소화 되살림은 그대로. */
    @Test
    fun reopenBuildsNewMachine() {
        val r = Rig()
        r.c.open()
        assertEquals(0, r.c.state.contentID, "처음 연 창은 첫 기계")
        r.c.open()
        assertEquals(0, r.c.state.contentID, "열린 창을 또 열면(멱등) 기계 그대로")
        r.c.onEvent(WindowEvent.Minimized)
        r.c.open()
        assertEquals(0, r.c.state.contentID, "최소화 되살림은 기계 그대로")
        assertTrue(r.c.state.isActive)
        r.c.onEvent(WindowEvent.UserClosed)
        r.c.open()
        assertEquals(1, r.c.state.contentID, "사용자가 닫았다 다시 열면 새 기계")
        r.c.close()
        r.c.open()
        assertEquals(2, r.c.state.contentID, "프로그램이 닫았다 다시 열면 새 기계")
        assertEquals(1, r.handles.size, "창은 한 번만 만든다(지연 생성 · 닫아도 파괴 안 함)")
    }

    /** ★② 단서: 왕복 중이면 기계 그대로(CheckGachaWindow.swift:445 `!wiring.store.gachaPulling`). */
    @Test
    fun reopenWhilePullingKeepsMachine() {
        val r = Rig()
        r.c.open()
        r.c.onEvent(WindowEvent.UserClosed)
        r.facts.pulling = true
        r.c.open()
        assertEquals(0, r.c.state.contentID, "왕복 중인데 새 기계를 세웠다 — 산 캡슐이 창에서 사라진다")
        assertTrue(r.c.state.isActive)
    }

    /**
     * ★② 단서: 루비 낸 판을 아직 못 봤으면 기계 그대로(`!state.machineLink.hasUnrevealedTurn`).
     * 규칙은 여기서 잰다. 기계 → 칸 배선(공용 패치 5 MeGachaMachineScreen onUnrevealedChanged)은 GachaUnrevealedWiringTest 가 실제 누름으로 잰다.
     */
    @Test
    fun reopenWithUnrevealedTurnKeepsMachine() {
        val r = Rig()
        r.c.open()
        r.c.onEvent(WindowEvent.UserClosed)
        r.facts.cell.value = true
        r.c.open()
        assertEquals(0, r.c.state.contentID, "공개 전 판이 있는데 새 기계를 세웠다")
        r.c.onEvent(WindowEvent.UserClosed)
        r.facts.cell.value = false
        r.c.open()
        assertEquals(1, r.c.state.contentID, "판을 다 봤으면 다시 열 때 새 기계")
    }
}
