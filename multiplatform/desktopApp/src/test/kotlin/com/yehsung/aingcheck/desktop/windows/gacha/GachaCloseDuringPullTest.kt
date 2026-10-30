// 원본: Sources/check/CheckGachaWindow.swift:17-19(★① 닫아도 루비 안 나감 — 커밋 전 예약을 거둔다) · :445(★② 왕복 중이면 기계 유지) · :466(close 는 왕복을 끊지 않는다)
// 진짜 나 탭 스토어 + 합성 서버(로컬)로 뽑기 왕복 한 번을 띄운 채 창을 닫는다. 창 0(가짜 손잡이), 그림은 오프스크린 장면.
package com.yehsung.aingcheck.desktop.windows.gacha

import com.yehsung.aingcheck.core.stores.me.pullGachaForMachine
import com.yehsung.aingcheck.desktop.testsupport.DesktopSnapshots
import com.yehsung.aingcheck.desktop.windows.kit.WindowEvent
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import java.util.concurrent.CountDownLatch
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GachaCloseDuringPullTest {
    @Test
    fun closingDuringPullAddsNoPull() = W4fStore().use { w ->
        val handles = mutableListOf<FakeWindowHandle>()
        val c = GachaWindowController(w.store.gachaMachineFacts(), { FakeWindowHandle().also { handles += it } }, MemoryBounds(), { listOf(WORK_AREA) }, { 1.0 })
        c.open()
        assertTrue(c.state.isActive)

        val gate = CountDownLatch(1)
        w.server.pullGate = gate
        val pull = w.scope.async { w.store.pullGachaForMachine() }
        waitUntil("뽑기 요청이 서버에 닿는다") { w.server.count(W4fServer.PULL) == 1 }
        assertTrue(w.store.isPulling, "왕복 중 표시가 없다")

        // 왕복 중에 닫는다 — 기계 멈춤(★①), 왕복은 끊지 않는다.
        c.onEvent(WindowEvent.UserClosed)
        assertFalse(c.state.isActive, "닫힌 창의 기계가 돈다")
        assertFalse(handles.single().visible)

        // 왕복 중에 다시 열면 그 기계 그대로(★②).
        c.open()
        assertEquals(0, c.state.contentID, "왕복 중 다시 열기가 새 기계를 세웠다")
        c.onEvent(WindowEvent.UserClosed)

        gate.countDown()
        runBlocking { pull.await() }
        waitUntil("왕복이 끝난다") { !w.store.isPulling }

        // 닫힌 창의 기계를 여러 프레임 그려도 저절로 뽑기가 나가지 않는다. 이 기계엔 손잡이 예약이 없어 isActive 배선과 무관하다 —
        // '손잡이를 누르고 바로 닫기'(★① 배선)는 GachaKnobThenCloseTest 가 실제 누름으로 잰다.
        DesktopSnapshots.render(420, 552, frames = 30) {
            WithRepoArt { GachaWindowContent(w.store, c.state, onClose = c::close, dark = false) }
        }
        assertEquals(1, w.server.count(W4fServer.PULL), "창을 닫은 뒤 뽑기가 더 나갔다 — ${w.server.calls}")

        // 왕복이 끝났고 미공개 신호가 없으면(이 시험의 칸은 기계에 안 잇는다 — 잇는 배선은 GachaUnrevealedWiringTest) 다시 열 때 새 기계.
        c.open()
        assertEquals(1, c.state.contentID)
        assertTrue(c.state.isActive)
        assertEquals(1, handles.size, "창은 한 번만 만든다")
    }
}
