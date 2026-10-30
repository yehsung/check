// 원본: Sources/check/MiniGameCrossy.swift @ 1b8260d · MiniGameCrossyScene.swift @ 1b8260d (맥 장면 구성 — 대조 목록은 W4-g 보고 unresolved)
//
// 길건너 캔버스 스냅숏 — 다섯 장면(시작 · 찻길 · 강 · 기찻길 · 끝) × 배율 100%·150% × 밝음·어두움 = 20장.
// 골든: ui/snapshots/games/minigame/desktop/crossy-<장면>-<배율>-<테마>.png. GamesSnapshotDesktopTest 와 같은 셋을 잰다:
// ① 세 번 새로 그려 같다 ② 골든과 같다(기록 기계는 픽셀 그대로, 다른 기계는 굵은 대조) ③ 한 군데 다른 기준선과는 다르다(비교가 내용을 본다).
package com.yehsung.aingcheck.ui.games.minigame.crossy

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import com.yehsung.aingcheck.ui.games.minigame.GamesCanvasColors
import com.yehsung.aingcheck.ui.games.minigame.MiniGameArt
import com.yehsung.aingcheck.ui.theme.AingTheme
import org.jetbrains.skia.Bitmap
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.fail

class CrossySnapshotDesktopTest {
    private val art by lazy {
        MiniGameArt(DesktopSnapshots.repoImage(MiniGameArt.FLAPPY_SIDE_SOURCE), DesktopSnapshots.repoImage(MiniGameArt.FLAPPY_NEGATIVE_SOURCE))
    }

    /** 캔버스 자리(게임 화면의 캔버스 상자와 같은 둥근 모서리 · 패널 · 테두리 — 테마가 테두리에 산다). */
    private fun scene(game: CrossyGame, best: Long, dark: Boolean, art: MiniGameArt = this.art): @Composable () -> Unit = {
        AingTheme(dark = dark) {
            val shape = RoundedCornerShape(14.dp)
            Box(Modifier.fillMaxSize().background(AingTheme.colors.background)) {
                Box(Modifier.fillMaxSize().clip(shape).background(GamesCanvasColors.panel).border(1.dp, AingTheme.colors.separator, shape)) {
                    CrossyCanvas(game, best, reduceMotion = true, art = art, modifier = Modifier.fillMaxSize())
                }
            }
        }
    }

    @OptIn(ExperimentalComposeUiApi::class)
    private fun render(density: Float, content: @Composable () -> Unit): PixelImage {
        val w = (W * density).toInt()
        val h = (H * density).toInt()
        val scene = ImageComposeScene(width = w, height = h, density = Density(density), content = content)
        try {
            var image: org.jetbrains.skia.Image? = null
            for (i in 0 until 3) {
                image?.close()
                image = scene.render(i * 16_666_667L)
            }
            val bitmap = Bitmap.makeFromImage(requireNotNull(image))
            val pixels = IntArray(w * h)
            for (y in 0 until h) for (x in 0 until w) pixels[y * w + x] = bitmap.getColor(x, y)
            bitmap.close()
            image.close()
            return PixelImage(w, h, pixels)
        } finally {
            scene.close()
        }
    }

    // 기준선: 시작은 다른 시드(길이 통째로 다르다 — '한 군데' 검사 없음) · 판 중 셋은 같은 판에 아잉 그림만 뺀 것(근무 초록 원 — 한 군데) ·
    // 끝은 같은 판에 최고 기록만 다른 것(결과 카드 가운데 줄 — 한 군데).
    @Test fun start() = checkAll("start", CrossyScenes.start(), CrossyScenes.start(seed = 8uL), oneSpot = false)

    @Test fun road() = CrossyScenes.road().let { checkAll("road", it, it, otherArt = MiniGameArt.empty) }

    @Test fun river() = CrossyScenes.river().let { checkAll("river", it, it, otherArt = MiniGameArt.empty) }

    @Test fun rail() = CrossyScenes.rail().let { checkAll("rail", it, it, otherArt = MiniGameArt.empty) }

    @Test fun end() = CrossyScenes.end().let { checkAll("end", it, it, otherBest = 31L) }

    /** 장면이 정말 그 장면인가(장면 운전수가 조용히 다른 판을 내면 스냅숏이 엉뚱한 것을 굳힌다). */
    @Test
    fun scenesAreWhatTheyClaim() {
        assertEquals(CrossyGame.Phase.Ready, CrossyScenes.start().phase)
        val road = CrossyScenes.road()
        assertEquals(CrossyGame.LaneKind.road, road.lane(road.player.row)?.kind)
        val river = CrossyScenes.river()
        assertTrue(river.player.riding, "강 장면이 통나무 위가 아니다")
        val rail = CrossyScenes.rail()
        assertEquals(CrossyGame.LaneKind.rail, rail.lane(rail.player.row + 1)?.kind)
        assertTrue(rail.lane(rail.player.row + 1)?.train != null, "기찻길 장면에 기차가 없다")
        val end = CrossyScenes.end()
        assertEquals(CrossyGame.Phase.Result, end.phase)
        assertEquals(CrossyGame.DeathCause.leftBehind, end.death?.cause)
    }

    private fun checkAll(
        name: String, game: CrossyGame, other: CrossyGame, otherBest: Long = BEST, otherArt: MiniGameArt? = null, oneSpot: Boolean = true,
    ) {
        val failures = mutableListOf<String>()
        for (percent in listOf(100, 150)) for (dark in listOf(false, true)) {
            val id = "crossy-$name-$percent-${if (dark) "dark" else "light"}"
            try {
                check(id, percent / 100f, scene(game, BEST, dark), scene(other, otherBest, dark, otherArt ?: art), oneSpot)
            } catch (e: AssertionError) {
                failures += e.message ?: id
            }
        }
        if (failures.isNotEmpty()) fail(failures.joinToString("\n"))
    }

    private fun check(name: String, density: Float, scene: @Composable () -> Unit, other: @Composable () -> Unit, oneSpot: Boolean) {
        val renders = List(3) { render(density, scene) }
        val out = DesktopSnapshots.outDir()
        for (i in 1..2) {
            val d = SnapshotCompare.diff(renders[0], renders[i])
            if (!d.identical) {
                DesktopSnapshots.writePng(renders[i], File(out, "$name-render${i + 1}.png"))
                fail("$name: 1장과 ${i + 1}장이 다르다($d) — 렌더가 굳지 않았다")
            }
        }
        val actual = renders[0]
        DesktopSnapshots.writePng(actual, File(out, "games-$name.png"))
        assertTrue(actual.distinctColors() >= 64, "$name: 색이 ${actual.distinctColors()}개뿐 — 장면이 그려지지 않았다")
        val golden = DesktopSnapshots.golden("games/minigame", name)
        if (DesktopSnapshots.recording()) {
            DesktopSnapshots.writePng(actual, golden)
            fail("$name: 골든을 기록했다(${golden.path}) — 기록 실행은 실패로 끝난다. 기록 변수 없이 다시 돌려 대조한다.")
        }
        assertTrue(golden.isFile, "$name: 골든이 없다(${golden.path}) — 이 맥에서 ${SnapshotCompare.RECORD_ENV}=1 로 기록한다")
        val expected = DesktopSnapshots.readPng(golden)
        val exact = SnapshotPolicy.isRecordingHost(System.getProperty("os.name"), System.getProperty("os.arch"))
        val diff = SnapshotCompare.diff(expected, actual)
        val coarse = SnapshotCompare.coarse(expected, actual)
        println("AINGCHECK-SNAPSHOT desktop $name mode=${if (exact) "exact" else "coarse"} ${actual.width}x${actual.height} diff=$diff coarse=$coarse")
        val ok = if (exact) diff.identical else coarse.withinTolerance
        if (!ok) {
            DesktopSnapshots.writePng(actual, File(out, "$name-actual.png"))
            SnapshotCompare.diffImage(expected, actual)?.let { DesktopSnapshots.writePng(it, File(out, "$name-diff.png")) }
            fail("$name: 골든과 다르다(${if (exact) "픽셀 그대로" else "굵은 대조"} — $diff · $coarse)")
        }
        val baseline = render(density, other)
        assertEquals(actual.width to actual.height, baseline.width to baseline.height, "$name: 기준선 크기가 다르다")
        val negative = SnapshotCompare.diff(actual, baseline)
        println("AINGCHECK-SNAPSHOT-NEGATIVE desktop $name diff=$negative")
        assertFalse(negative.identical, "$name: 다른 장면인데 같은 픽셀 — 비교가 내용을 못 본다")
        if (oneSpot) assertTrue(negative.differingPixels in 1 until actual.argb.size / 10, "$name: 기준선 차이 ${negative.differingPixels}px — 한 군데만 달라야 한다")
    }

    private companion object {
        const val BEST = 9L
        const val W = 300
        const val H = 310
    }
}
