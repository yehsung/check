// 원본: Sources/check/CheckGachaWindow.swift:445(★② `existed, !state.isOpen, !gachaPulling, !hasUnrevealedTurn` — 미공개 판이면 다시 열어도 그 기계)
//       Sources/CheckCore/GachaMachine/GachaMachineView.swift:122-140(GachaMachineLink — 왕복이 끝났어도 공개 전이면 판은 안 끝났다)
// 껍데기 배선(공용 패치 5 뒤): GachaWindowHost 와 같은 꼴로 컨트롤러의 사실 칸 = 창 내용이 기계 알림을 적는 칸. 실제 손잡이 누름 → 자동 한 바퀴 →
// 합성 서버 뽑기 왕복 → 결과가 와서 왕복이 끝났지만 캡슐을 아직 안 열었다(공개 전) → 닫았다 다시 열면 **그 기계 그대로**(W4-f unresolved ① 수리).
// 기준선: 같은 칸을 창 내용에 안 이으면(이전 배선) 같은 순서에서 새 기계가 선다 — 아래 ★② 가 헛것이 아니라는 증거.
package com.yehsung.aingcheck.desktop.windows.gacha

import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.ui.unit.Density
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind
import com.yehsung.aingcheck.desktop.windows.kit.WindowEvent
import com.yehsung.aingcheck.ui.gacha.machine.GLayout
import java.util.concurrent.CountDownLatch
import kotlin.math.min
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalComposeUiApi::class)
class GachaUnrevealedWiringTest {
    private class Rig(val w: W4fStore, wired: Boolean) : AutoCloseable {
        val cell = GachaUnrevealedCell()
        val c = GachaWindowController(w.store.gachaMachineFacts(cell), { FakeWindowHandle() }, MemoryBounds(), { listOf(WORK_AREA) }, { 1.0 })
        private val scene: ImageComposeScene
        private var frame = 0L

        init {
            c.open()
            scene = ImageComposeScene((W * D).toInt(), (H * D).toInt(), Density(D)) {
                WithRepoArt { GachaWindowContent(w.store, c.state, onClose = c::close, dark = false, unrevealed = if (wired) cell else null) }
            }
            render(5)
        }

        fun render(n: Int = 1) = repeat(n) { scene.render(frame++ * 16_666_667L).close() }

        fun pressKnob() {
            val p = knobPx()
            scene.sendPointerEvent(PointerEventType.Press, p, type = PointerType.Touch)
            scene.sendPointerEvent(PointerEventType.Release, p, type = PointerType.Touch)
        }

        fun renderUntil(what: String, cond: () -> Boolean) {
            val end = System.nanoTime() + (CAP_SECONDS * 1e9).toLong()
            while (!cond() && System.nanoTime() < end) {
                render()
                Thread.sleep(16)
            }
            assertTrue(cond(), "$what — ${CAP_SECONDS}초 안에 안 왔다(${w.server.calls})")
        }

        /** 손잡이 → 왕복(문으로 붙잡아 '왕복 중'을 본 뒤 연다) → 결과 도착. 캡슐은 안 연다(공개 전). */
        fun pullAndLeaveTheCapsuleClosed(onInFlight: () -> Unit = {}) {
            val gate = CountDownLatch(1)
            w.server.pullGate = gate
            pressKnob()
            renderUntil("손잡이 한 바퀴 뒤 뽑기 왕복") { w.server.count(W4fServer.PULL) == 1 }
            renderUntil("왕복 중 표시") { w.store.isPulling }
            onInFlight()
            gate.countDown()
            renderUntil("왕복 끝") { !w.store.isPulling }
            render(10)
        }

        override fun close() = scene.close()
    }

    @Test
    fun star2_reopeningBeforeTheRevealKeepsTheMachine() = W4fStore().use { w ->
        Rig(w, wired = true).use { r ->
            assertEquals(false, r.cell.value)
            r.pullAndLeaveTheCapsuleClosed(onInFlight = { r.renderUntil("왕복 중 = 미공개") { r.cell.value } })
            assertTrue(r.cell.value, "결과가 왔지만 공개 전인데 칸이 '봤다'다")
            r.c.onEvent(WindowEvent.UserClosed)
            r.render(5)
            r.c.open()
            assertEquals(0, r.c.state.contentID, "공개 전 판을 두고 다시 열었는데 새 기계가 섰다 — 산 캡슐이 창에서 사라진다(★②)")
        }
    }

    @Test
    fun baselineUnwiredCellLetsANewMachineStand() = W4fStore().use { w ->
        Rig(w, wired = false).use { r ->
            r.pullAndLeaveTheCapsuleClosed()
            assertEquals(false, r.cell.value, "잇지 않은 칸이 바뀌었다")
            r.c.onEvent(WindowEvent.UserClosed)
            r.render(5)
            r.c.open()
            assertEquals(1, r.c.state.contentID, "기준선: 칸을 안 이으면 같은 순서에서 새 기계가 서야 한다(위 ★② 가 헛것이 아님)")
        }
    }

    private companion object {
        val W = GameWindowKind.Gacha.defaultWidthDp.toFloat()
        val H = GameWindowKind.Gacha.defaultHeightDp.toFloat()
        val D = DesktopSnapshots.DENSITY
        const val CAP_SECONDS = 10.0

        fun knobPx(): Offset {
            val s = min(W / GLayout.size.width, H / GLayout.size.height)
            val x = W / 2f + (GLayout.knobCenter.x - GLayout.size.width / 2f) * s
            val y = H / 2f + (GLayout.knobCenter.y - GLayout.size.height / 2f) * s
            return Offset(x * D, y * D)
        }
    }
}
