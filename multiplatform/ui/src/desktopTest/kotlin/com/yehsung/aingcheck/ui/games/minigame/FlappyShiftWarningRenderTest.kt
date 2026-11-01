// 원본: Tests/checkTests/V0246MiniGameFlappyTests.swift:281-292(같은 그림 값 · 0 이면 한 획도 더 긋지 않음) · :930-950(무대 다섯에서 빨강이 오른다) @ 1a5eeca6
//
// 플래피 붉은 예고를 **실제 캔버스 렌더**로 잰다(기억 tests-measure-shape-not-result — 세기 함수가 있어도 그림이 안 읽으면 소용없다).
//  · 무대 다섯: 튀기 전 기둥이 같은 높이의 고정 기둥보다 빨강이 뚜렷이 오르고, 초록·파랑보다 더 오른다(밝아진 게 아니라 붉어졌다).
//  · 세기 0(고정 기둥 · 예고가 다 빠진 기둥): 픽셀 하나 안 다르다 — 기준선은 "같은 틈의 튀는 기둥을 세기 1 로" 그린 다른 입력이다(비교가 내용을 본다).
//  · 물리는 안 바뀐다: 틈 중심이 예고와 무관하다(flappy 골든은 그대로).
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.minigame.FlappyGame
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class FlappyShiftWarningRenderTest {
    private val centerY = 151.0
    private val gap = 132.0
    private fun fixed(x: Double) = FlappyGame.Pipe(x = x, centerY = centerY, gap = gap)
    /** 조준됐고 아직 안 튀었다(세기 1). */
    private fun warned(x: Double) = FlappyGame.Pipe(x = x, centerY = centerY, gap = gap, shiftDelay = 0.7, shiftOffset = 58.0, shiftAt = 5.0)

    private fun game(pipes: List<FlappyGame.Pipe>, score: Int, elapsed: Double = 1.0) = FlappyGame(
        seed = 3uL, bird = FlappyGame.Bird(FlappyGame.birdX, centerY, 0.0), pipes = pipes, score = score,
        phase = FlappyGame.Phase.Running, elapsed = elapsed,
    )

    /** 논리 292×302 를 1:1 로(배율 1 × 렌더 배율) — 아잉 그림은 빼서 기둥만 본다. */
    private fun render(game: FlappyGame): PixelImage = DesktopSnapshots.render(292, 302) {
        AingTheme(dark = false) {
            GamesFlappyCanvas(game, bestScore = 0L, reduceMotion = true, art = MiniGameArt.empty, modifier = Modifier.size(292.dp, 302.dp))
        }
    }

    private fun rgb(image: PixelImage, logicalX: Double, logicalY: Double): IntArray {
        val scale = image.width / 292.0
        val p = image.argb[(logicalY * scale).toInt() * image.width + (logicalX * scale).toInt()]
        return intArrayOf((p shr 16) and 0xFF, (p shr 8) and 0xFF, p and 0xFF)
    }

    @Test
    fun aPipeAboutToJumpGlowsRedOnEveryStage() {
        for (score in listOf(0, 6, 13, 22, 34)) {
            val image = render(game(listOf(fixed(60.0), warned(200.0), fixed(460.0)), score))
            val plain = rgb(image, 60 + FlappyGame.pipeWidth / 2, 40.0)
            val red = rgb(image, 200 + FlappyGame.pipeWidth / 2, 40.0)
            val dr = red[0] - plain[0]
            val dg = red[1] - plain[1]
            val db = red[2] - plain[2]
            println("AINGCHECK-FLAPPY-WARNING score=$score 고정=${plain.toList()} 예고=${red.toList()} d=($dr,$dg,$db)")
            assertTrue(dr >= 20, "score $score: 빨강이 안 올랐다 — 고정 ${plain.toList()} · 예고 ${red.toList()}")
            assertTrue(dr > dg && dr > db, "score $score: 붉어진 게 아니라 밝아졌다 — ($dr,$dg,$db)")
        }
    }

    /** 다 빠진 기둥(세기 0)은 고정 기둥과 픽셀 하나 안 다르다 — 음성 기준선: 같은 판 시각의 세기 1 은 다르다(이 비교가 내용을 본다). */
    @Test
    fun zeroLevelDrawsNotASingleExtraStroke() {
        val settledAt = 5.0 + FlappyGame.shiftDuration + FlappyGame.warningFade + 0.01
        // 튄 뒤 자리(centerY + 58)에 같은 틈을 두는 고정 기둥과 비교한다.
        val jumped = FlappyGame.Pipe(x = 200.0, centerY = centerY, gap = gap, shiftDelay = 0.7, shiftOffset = 58.0, shiftAt = 5.0)
        val sameSpot = fixed(200.0).copy(centerY = centerY + 58)
        assertEquals(jumped.center(settledAt), sameSpot.center(settledAt), 1e-9, "두 기둥의 틈이 같은 자리다")
        assertEquals(0.0, jumped.warningLevel(settledAt))
        val faded = render(game(listOf(jumped), 20, settledAt))
        val plain = render(game(listOf(sameSpot), 20, settledAt))
        assertTrue(SnapshotCompare.diff(faded, plain).identical, "세기 0 인데 그림이 다르다: ${SnapshotCompare.diff(faded, plain)}")
        // 기준선: 빠지는 도중(세기 > 0)은 같은 비교에서 달라야 한다.
        val fadingAt = 5.0 + FlappyGame.shiftDuration + FlappyGame.warningFade / 2
        assertTrue(jumped.warningLevel(fadingAt) > 0.0)
        assertFalse(
            SnapshotCompare.diff(render(game(listOf(jumped), 20, fadingAt)), render(game(listOf(sameSpot), 20, fadingAt))).identical,
            "세기가 0 이 아닌데 같은 그림이다 — 위 비교가 예고를 못 본다",
        )
    }

    /** 예고는 그림값이다 — 같은 시각 틈 중심(충돌이 읽는 값)은 세기와 무관하다. */
    @Test
    fun theWarningDoesNotTouchThePhysics() {
        val pipe = warned(200.0)
        assertEquals(fixed(200.0).center(1.0), pipe.center(1.0), "튀기 전 틈이 고정 기둥과 다르다")
        assertEquals(fixed(200.0).topRect(1.0), pipe.topRect(1.0))
        assertEquals(fixed(200.0).bottomRect(1.0, FlappyGame.height), pipe.bottomRect(1.0, FlappyGame.height))
    }

    /** 그림 값은 Swift 의 `FlappyShiftWarning` 그대로다(저장소 Swift 소스를 읽어 대조). "살짝" — 덧칠 상한 0.4 미만. */
    @Test
    fun thePaintValuesMatchTheSwiftOriginal() {
        val swift = RepoFiles.readText("Sources/CheckCore/FlappyGame.swift")
        assertTrue("tint = Color(red: 1.0, green: 0.30, blue: 0.26)" in swift, "Swift 원본 색이 바뀌었다")
        assertTrue("fillOpacity: Double = 0.26" in swift && "strokeOpacity: Double = 0.90" in swift && "lineWidth: CGFloat = 1.5" in swift, "Swift 원본 불투명도가 바뀌었다")
        assertTrue("warningFade: TimeInterval = 0.35" in swift, "Swift 원본 빠짐 시간이 바뀌었다")
        assertEquals(0.26, FlappyShiftWarning.fillOpacity)
        assertEquals(0.90, FlappyShiftWarning.strokeOpacity)
        assertEquals(1.5f, FlappyShiftWarning.lineWidth)
        assertTrue(FlappyShiftWarning.fillOpacity < 0.4, "빨간 기둥이 된다")
    }
}
