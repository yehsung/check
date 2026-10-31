// 원본: Tests/checkTests/V0246MiniGameFlappyTests.swift:240-275(튀는 기둥 붉은 예고 — 세기 함수) @ 1a5eeca6
// 사용자 번복(2026-10-30): "플래피 아잉에서 움직이게 될 벽돌은 살짝 붉은 빛 표시하면서 미리 움직일거라고 예고하게끔 추가하자." 물리는 안 바뀐다(flappy 골든 그대로).
package com.yehsung.aingcheck.core.rules.minigame

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class FlappyShiftWarningTest {
    private val w = FlappyGame.width
    private val h = FlappyGame.height

    private fun pipe(x: Double) = FlappyGame.Pipe(x = x, centerY = h / 2, gap = 132.0)
    private fun jumpPipe(x: Double, delay: Double = 0.7, at: Double? = null) =
        FlappyGame.Pipe(x = x, centerY = h / 2, gap = 132.0, shiftDelay = delay, shiftOffset = 58.0, shiftAt = at)

    @Test
    fun onlyShiftingPipesCarryTheRedWarningUntilTheyHaveJumped() {
        assertEquals(0.0, pipe(100.0).warningLevel(5.0), "고정 기둥은 예고가 없다")
        // 조준 전(화면 밖)에도 1 — 들어오는 첫 프레임부터 붉다.
        assertEquals(1.0, jumpPipe(w + 40).warningLevel(0.0))
        val armed = jumpPipe(200.0, at = 1.0)
        assertEquals(1.0, armed.warningLevel(0.5), "튀기 전엔 1")
        assertEquals(1.0, armed.warningLevel(1.0 + FlappyGame.shiftDuration / 2), "튀는 도중에도 1")
        assertEquals(1.0, armed.warningLevel(1.0 + FlappyGame.shiftDuration), "다 튄 순간까지 1")
        val mid = armed.warningLevel(1.0 + FlappyGame.shiftDuration + FlappyGame.warningFade / 2)
        assertTrue(abs(mid - 0.5) < 1e-9, "빠지는 것은 선형이다(이징 없음) — 중간이 $mid")
        assertEquals(0.0, armed.warningLevel(1.0 + FlappyGame.shiftDuration + FlappyGame.warningFade))
        assertEquals(0.0, armed.warningLevel(60.0), "다 빠진 뒤 다시 켜지지 않는다")
        assertEquals(0.35, FlappyGame.warningFade)
    }

    /** 판 시계(step)가 조준한 기둥으로: 화면에 들어온 그 프레임에 예고가 1 이고, 튀기를 마친 뒤 warningFade 가 지나면 0 이다. 옆의 고정 기둥은 내내 0. */
    @Test
    fun aJumpPipeArmedByTheBoardIsWarnedUntilItSettles() {
        val game = FlappyGame(
            seed = 3uL,
            bird = FlappyGame.Bird(FlappyGame.birdX, h / 2, 0.0),
            pipes = listOf(jumpPipe(w + 0.5), pipe(w + 190), pipe(w + 340)),
            score = 20,
            phase = FlappyGame.Phase.Running,
        )
        game.step(1.0 / 60.0)
        val entered = game.pipes[0]
        val armed = assertNotNull(entered.shiftAt)
        assertEquals(1.0, entered.warningLevel(game.elapsed), "들어온 프레임에 예고가 없다")
        assertEquals(0.0, game.pipes[1].warningLevel(game.elapsed), "고정 기둥에 예고가 묻었다")
        assertEquals(1.0, entered.warningLevel(armed - 0.01), "튀기 직전에 예고가 빠졌다")
        assertEquals(0.0, entered.warningLevel(armed + FlappyGame.shiftDuration + FlappyGame.warningFade + 0.01), "다 튀고 빠질 시간이 지났는데 예고가 남았다")
    }
}
