// 원본: 없음 — G §2-3 W4-a ① 판 스냅숏 + §8-17 #1 깃발 꺼짐/켜짐 스냅숏(데스크톱 배율 2). 골든: ui/snapshots/games/{gomoku,chess}/desktop/<장면>.png
//
// 장면마다 셋을 잰다(진열장 시험 GallerySnapshotDesktopTest 와 같은 규칙):
//  ① 같은 장면을 새로 세 번 그리면 픽셀이 같다(굳은 렌더)
//  ② 골든과 같다(기록은 AINGCHECK_SNAPSHOT_RECORD=1, 이 맥에서만 — 기록 실행은 실패로 끝난다. 기록 기계가 아닌 러너는 굵은 대조)
//  ③ 같은 크기에 **한 군데만 다른** 장면(음성 기준선)은 골든과 다르다 — 비교가 내용을 본다는 증거
// 깃발 꺼짐/켜짐 두 장은 서로도 달라야 한다(같으면 깃발이 화면에 닿지 않는다).
package com.yehsung.aingcheck.ui.games.gomoku

import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.fail

class BoardSnapshotDesktopTest {
    private val wrap: @androidx.compose.runtime.Composable (Boolean, @androidx.compose.runtime.Composable () -> Unit) -> Unit = { dark, body -> BoardTestTheme(dark) { body() } }

    private fun render(scene: BoardScene): PixelImage = DesktopSnapshots.render(scene.widthDp, scene.heightDp) { scene.content(wrap) }

    @Test fun gomokuMatchLight() { check(BoardScenes.gomokuMatch(false), BoardScenes.gomokuMatch(false, meName = "나검정둘")) }
    @Test fun gomokuMatchDark() { check(BoardScenes.gomokuMatch(true), BoardScenes.gomokuMatch(true, meName = "나검정둘")) }
    @Test fun chessMatchLight() { check(BoardScenes.chessMatch(false), BoardScenes.chessMatch(false, meName = "나백둘")) }
    @Test fun chessMatchDark() { check(BoardScenes.chessMatch(true), BoardScenes.chessMatch(true, meName = "나백둘")) }
    @Test fun chessBoardOverlays() { check(BoardScenes.chessBoardOverlays(true), BoardScenes.chessBoardOverlays(false)) }

    @Test fun gomokuLobbyDuelsOff() { check(BoardScenes.gomokuLobby(false), BoardScenes.gomokuLobby(false, ruby = 107)) }
    @Test fun gomokuLobbyDuelsOn() { check(BoardScenes.gomokuLobby(true), BoardScenes.gomokuLobby(true, ruby = 107)) }
    @Test fun chessLobbyDuelsOff() { check(BoardScenes.chessLobby(false), BoardScenes.chessLobby(false, ruby = 107)) }
    @Test fun chessLobbyDuelsOn() { check(BoardScenes.chessLobby(true), BoardScenes.chessLobby(true, ruby = 107)) }

    /** 깃발 꺼짐과 켜짐 두 장은 서로 달라야 한다(같으면 깃발이 화면에 닿지 않는다). */
    @Test
    fun duelsFlagReachesBothLobbies() {
        render(BoardScenes.gomokuLobby(false))
        assertFalse(SnapshotCompare.diff(render(BoardScenes.gomokuLobby(false)), render(BoardScenes.gomokuLobby(true))).identical, "오목: 깃발 꺼짐과 켜짐이 같은 그림")
        assertFalse(SnapshotCompare.diff(render(BoardScenes.chessLobby(false)), render(BoardScenes.chessLobby(true))).identical, "체스: 깃발 꺼짐과 켜짐이 같은 그림")
    }

    private fun check(scene: BoardScene, other: BoardScene): PixelImage {
        val name = scene.name
        // 한 장 먼저 구워 버린다(그림자 · 글리프 캐시가 첫 장만 다르게 굽는다 — 기억 imagerenderer-first-two-renders-differ: 굳힌 뒤 비교).
        render(scene)
        val renders = List(3) { render(scene) }
        val out = DesktopSnapshots.outDir()
        for (i in 1..2) {
            val d = SnapshotCompare.diff(renders[0], renders[i])
            if (!d.identical) {
                DesktopSnapshots.writePng(renders[i], File(out, "$name-render${i + 1}.png"))
                fail("$name: 1장과 ${i + 1}장이 다르다($d) — 렌더가 굳지 않았다")
            }
        }
        val actual = renders[0]
        assertTrue(actual.distinctColors() >= 64, "$name: 색이 ${actual.distinctColors()}개뿐 — 장면이 그려지지 않았다")
        val golden = DesktopSnapshots.golden(scene.group, name)
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
        if (!(if (exact) diff.identical else coarse.withinTolerance)) {
            DesktopSnapshots.writePng(actual, File(out, "$name-actual.png"))
            SnapshotCompare.diffImage(expected, actual)?.let { DesktopSnapshots.writePng(it, File(out, "$name-diff.png")) }
            fail("$name: 골든과 다르다($diff · $coarse) — build/aingcheck-snapshots/desktop/$name-{actual,diff}.png")
        }
        val baseline = render(other)
        assertEquals(actual.width to actual.height, baseline.width to baseline.height, "$name: 기준선 크기가 다르다")
        val negative = SnapshotCompare.diff(actual, baseline)
        val negativeCoarse = SnapshotCompare.coarse(actual, baseline)
        println("AINGCHECK-SNAPSHOT-NEGATIVE desktop $name diff=$negative coarse=$negativeCoarse")
        assertFalse(negative.identical, "$name: 한 군데 다른 장면인데 같은 픽셀 — 비교가 내용을 못 본다")
        assertTrue(negative.differingPixels in 1 until actual.argb.size / 10, "$name: 기준선 차이 ${negative.differingPixels}px — 한 군데만 달라야 한다")
        assertFalse(negativeCoarse.withinTolerance, "$name: 굵은 대조가 한 군데 다른 장면을 못 잡는다($negativeCoarse)")
        return actual
    }
}
