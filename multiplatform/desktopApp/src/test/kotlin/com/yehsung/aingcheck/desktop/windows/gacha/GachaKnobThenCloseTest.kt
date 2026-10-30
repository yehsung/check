// 원본: Sources/check/CheckGachaWindow.swift:17-19(★① 손잡이를 누르고 바로 닫아도 루비가 안 나간다 — 닫아도 창이 파괴되지 않아 isActive 가 유일한 문)
//       Sources/CheckCore/GachaMachine/GachaMachineView.swift(isActive=false → 커밋 전 예약(자동 회전 · [한 번 더])을 거둔다)
// 껍데기 배선 — GachaWindowContent 가 GachaWindowState.isActive 를 기계의 isAppActive 로 넘기는가 — 을 실제 손잡이 누름으로 잰다:
//  · 기준선: 창을 연 채 손잡이를 한 번 누르면 자동 한 바퀴 뒤 뽑기 1(누름이 손잡이에 닿고 예약이 커밋까지 간다 — 아래 0 이 헛것이 아니라는 증거).
//  · ★①: 같은 누름 뒤 바로 창을 닫으면(UserClosed) 자동 회전 시간을 넘겨 프레임을 그려도 뽑기 0.
// 기계 시계는 실제 단조 시계(감독 안에서 remember — 주입 불가)라 자동 회전(0.95초)을 실제로 기다린다. 창 0(가짜 손잡이) · 오프스크린 장면.
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
import kotlin.math.min
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalComposeUiApi::class)
class GachaKnobThenCloseTest {
    /** 뽑기 창 하나(창 0) + 그 내용을 그리는 오프스크린 장면. */
    private class Rig(val w: W4fStore) : AutoCloseable {
        val c = GachaWindowController(w.store.gachaMachineFacts(), { FakeWindowHandle() }, MemoryBounds(), { listOf(WORK_AREA) }, { 1.0 })
        private val scene: ImageComposeScene
        private var frame = 0L

        init {
            c.open()
            scene = ImageComposeScene((W * D).toInt(), (H * D).toInt(), Density(D)) {
                WithRepoArt { GachaWindowContent(w.store, c.state, onClose = c::close, dark = false) }
            }
            render(5)
        }

        fun render(n: Int = 1) = repeat(n) { scene.render(frame++ * 16_666_667L).close() }

        /** 손잡이를 한 번 눌렀다 뗀다(끌지 않음 → 기계가 저절로 한 바퀴를 예약한다). */
        fun pressKnob() {
            val p = knobPx()
            scene.sendPointerEvent(PointerEventType.Press, p, type = PointerType.Touch)
            scene.sendPointerEvent(PointerEventType.Release, p, type = PointerType.Touch)
        }

        /** [seconds] 동안 프레임을 그린다(조건이 서면 일찍 멈춘다). */
        fun renderFor(seconds: Double, until: () -> Boolean = { false }) {
            val end = System.nanoTime() + (seconds * 1e9).toLong()
            while (System.nanoTime() < end && !until()) {
                render()
                Thread.sleep(16)
            }
        }

        override fun close() = scene.close()
    }

    @Test
    fun baselineKnobPressWithWindowOpenPullsOnce() = W4fStore().use { w ->
        Rig(w).use { r ->
            assertTrue(r.c.state.isActive)
            assertEquals(0, w.server.count(W4fServer.PULL))
            r.pressKnob()
            r.renderFor(BASELINE_CAP_SECONDS) { w.server.count(W4fServer.PULL) >= 1 }
            assertEquals(1, w.server.count(W4fServer.PULL), "열린 창에서 손잡이를 눌렀는데 뽑기가 안 나갔다 — 누름이 손잡이에 안 닿았다(아래 ★① 시험이 헛것) — ${w.server.calls}")
        }
    }

    @Test
    fun star1_closingRightAfterKnobPressAddsNoPull() = W4fStore().use { w ->
        Rig(w).use { r ->
            assertTrue(r.c.state.isActive)
            r.pressKnob()
            // 자동 회전(0.95초)이 끝나기 전에 닫는다 — 창은 숨기만 하고 파괴되지 않으므로 isActive 만이 예약을 거둘 수 있다(★①).
            r.c.onEvent(WindowEvent.UserClosed)
            assertFalse(r.c.state.isActive)
            r.renderFor(WAIT_SECONDS) { w.server.count(W4fServer.PULL) >= 1 }
            assertEquals(0, w.server.count(W4fServer.PULL), "손잡이를 누르고 바로 닫았는데 뽑기가 나갔다(★① — 루비가 나간다) — ${w.server.calls}")
        }
    }

    private companion object {
        val W = GameWindowKind.Gacha.defaultWidthDp.toFloat()
        val H = GameWindowKind.Gacha.defaultHeightDp.toFloat()
        val D = DesktopSnapshots.DENSITY

        /** ★① 이 지켜보는 시간 — 자동 회전 0.95초의 두 배 남짓(이 사이에 커밋이 안 오면 예약이 거둬진 것). */
        const val WAIT_SECONDS = 2.5

        /** 기준선 상한(대개 1.1초에 끝난다 — 갈래 여럿이 동시에 도는 기계에서도 헛빨강이 안 나게 넉넉히). */
        const val BASELINE_CAP_SECONDS = 10.0

        /** 손잡이 중심(설계 380×460 좌표)을 창 픽셀로 — GachaMachineScaler 가 무대를 비율 그대로 키워 가운데 둔다. */
        fun knobPx(): Offset {
            val s = min(W / GLayout.size.width, H / GLayout.size.height)
            val x = W / 2f + (GLayout.knobCenter.x - GLayout.size.width / 2f) * s
            val y = H / 2f + (GLayout.knobCenter.y - GLayout.size.height / 2f) * s
            return Offset(x * D, y * D)
        }
    }
}
