// 원본: Sources/CheckCore/GachaMachine/GachaMachineView.swift:122-140(GachaMachineLink.hasUnrevealedTurn — 호스트가 창을 다시 열 때 묻는 값)
// 공용 패치 5(W-6 #7): GachaMachineView/MeGachaMachineScreen 의 onUnrevealedChanged 가 감독의 hasUnrevealedTurn 을 바뀔 때만 밖에 알린다.
// 실제 손잡이 누름 → 자동 한 바퀴(실제 단조 시계 — 감독 시계는 주입 불가) → pull 왕복을 가짜 문으로 붙잡아 잰다:
//  · 처음 그림 = false 한 번 · 왕복 중 = true · 실패(루비 안 나감) = false · 결과가 오면 공개 전까지 true(창을 다시 열어도 기계를 지킨다).
package com.yehsung.aingcheck.ui.gacha.machine

import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.ui.unit.Density
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.CompletableDeferred
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalComposeUiApi::class)
class GachaUnrevealedSignalDesktopTest {
    private class Rig : AutoCloseable {
        val reports = mutableListOf<Boolean>()
        var gate = CompletableDeferred<GachaRevealOutcome>()
        var pulls = 0
        private var frame = 0L
        private val scene = ImageComposeScene(W, H, Density(1f)) {
            AingTheme(dark = false) {
                GachaMachineView(
                    balance = 500, cost = 50, shards = 0, art = GachaMachineArt.Vector, portrait = { null }, ruby = null,
                    pull = { pulls += 1; gate.await() },
                    onClose = {}, teaseChance = 0.0,
                    onUnrevealedChanged = { reports += it },
                )
            }
        }

        fun render(n: Int = 1) = repeat(n) { scene.render(frame++ * 16_666_667L).close() }

        /** 손잡이를 한 번 눌렀다 뗀다(끌지 않음 → 기계가 저절로 한 바퀴를 돌고 커밋한다). */
        fun pressKnob() {
            val p = Offset(GLayout.knobCenter.x, GLayout.knobCenter.y)
            scene.sendPointerEvent(PointerEventType.Press, p, type = PointerType.Touch)
            scene.sendPointerEvent(PointerEventType.Release, p, type = PointerType.Touch)
        }

        fun renderUntil(what: String, capSeconds: Double = CAP_SECONDS, cond: () -> Boolean) {
            val end = System.nanoTime() + (capSeconds * 1e9).toLong()
            while (!cond() && System.nanoTime() < end) {
                render()
                Thread.sleep(16)
            }
            assertTrue(cond(), "$what — ${capSeconds}초 안에 안 왔다(알림 $reports · pull $pulls)")
        }

        override fun close() = scene.close()
    }

    @Test
    fun reportsInFlightThenFailureAsSeen() = Rig().use { r ->
        r.render(3)
        assertEquals(listOf(false), r.reports, "처음 그림에서 false 를 한 번만 알려야 한다(바뀔 때만)")
        r.pressKnob()
        r.renderUntil("손잡이 한 바퀴 뒤 뽑기 왕복") { r.pulls == 1 }
        r.renderUntil("왕복 중 = 못 본 판") { r.reports.lastOrNull() == true }
        r.gate.completeExceptionally(GachaRevealFailure("지금은 뽑을 수 없어요"))
        r.renderUntil("실패한 판은 루비가 안 나갔다 = 못 본 판 없음") { r.reports.lastOrNull() == false }
        r.render(10)
        assertEquals(listOf(false, true, false), r.reports, "바뀔 때만 알려야 한다")
    }

    @Test
    fun resultBeforeRevealStaysUnrevealed() = Rig().use { r ->
        r.render(3)
        r.pressKnob()
        r.renderUntil("손잡이 한 바퀴 뒤 뽑기 왕복") { r.pulls == 1 }
        r.gate.complete(GachaRevealOutcome("fox", "여우", GachaRevealKind.New, shardCount = 1))
        // 결과가 와도 캡슐을 톡톡 열기 전(공개 전)이면 여전히 못 본 판이다 — 맥 :125 "왕복이 끝났어도 공개 전이면 판은 안 끝났다".
        repeat(60) { r.render(); Thread.sleep(16) } // 낙하·톡 기다림까지 실제 1초 남짓
        assertEquals(listOf(false, true), r.reports, "결과가 왔지만 공개 전인데 '봤다'로 알렸다")
    }

    private companion object {
        val W = GLayout.size.width.toInt()
        val H = GLayout.size.height.toInt()

        /** 자동 회전 0.95초 + 여유(갈래 여럿이 동시에 도는 기계에서도 헛빨강이 안 나게). */
        const val CAP_SECONDS = 10.0
    }
}
