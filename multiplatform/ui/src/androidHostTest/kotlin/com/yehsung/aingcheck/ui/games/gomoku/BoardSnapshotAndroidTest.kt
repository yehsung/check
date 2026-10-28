// 원본: 없음 — G §2-3 W4-a ① 판 스냅숏 + §8-17 #1 깃발 꺼짐/켜짐 스냅숏(Android 호스트 · xhdpi 배율 2). 골든: ui/snapshots/games/{gomoku,chess}/android/<장면>.png
//
// 데스크톱 판(BoardSnapshotDesktopTest)과 같은 장면(BoardScenes)·같은 세 가지를 잰다:
//  ① 새로 세 번 그려도 같다 ② 골든과 같다(기록 기계는 픽셀 그대로, 다른 러너는 굵은 대조) ③ 한 군데 다른 같은 크기 장면은 다르다.
// 창은 가장 큰 장면(390×2000dp)이 들어가게 잡는다 — 창 밖으로 나간 노드는 잘린다.
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.runComposeUiTest
import com.yehsung.aingcheck.ui.components.AndroidSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w400dp-h2100dp-xhdpi")
class BoardSnapshotAndroidTest {
    private val wrap: @Composable (Boolean, @Composable () -> Unit) -> Unit = { dark, body -> BoardTestTheme(dark) { body() } }

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
        assertFalse("오목: 깃발 꺼짐과 켜짐이 같은 그림", SnapshotCompare.diff(render(BoardScenes.gomokuLobby(false)), render(BoardScenes.gomokuLobby(true))).identical)
        assertFalse("체스: 깃발 꺼짐과 켜짐이 같은 그림", SnapshotCompare.diff(render(BoardScenes.chessLobby(false)), render(BoardScenes.chessLobby(true))).identical)
    }

    @OptIn(ExperimentalTestApi::class)
    private fun render(scene: BoardScene): PixelImage {
        var out: PixelImage? = null
        runComposeUiTest {
            setContent {
                Box(Modifier.wrapContentSize(Alignment.TopStart, unbounded = true).testTag(TAG)) { scene.content(wrap) }
            }
            waitForIdle()
            out = AndroidSnapshots.pixels(onNodeWithTag(TAG).captureToImage())
        }
        return requireNotNull(out)
    }

    private fun check(scene: BoardScene, other: BoardScene) {
        val name = scene.name
        val renders = List(3) { render(scene) }
        val out = AndroidSnapshots.outDir()
        for (i in 1..2) {
            val d = SnapshotCompare.diff(renders[0], renders[i])
            if (!d.identical) {
                AndroidSnapshots.writePng(renders[i], File(out, "$name-render${i + 1}.png"))
                fail("$name: 1장과 ${i + 1}장이 다르다($d) — 렌더가 굳지 않았다")
            }
        }
        val actual = renders[0]
        assertEquals("$name: 크기", (scene.widthDp * 2) to (scene.heightDp * 2), actual.width to actual.height)
        assertTrue("$name: 색이 ${actual.distinctColors()}개뿐 — 장면이 그려지지 않았다", actual.distinctColors() >= 64)
        val golden = AndroidSnapshots.golden(scene.group, name)
        if (AndroidSnapshots.recording()) {
            AndroidSnapshots.writePng(actual, golden)
            fail("$name: 골든을 기록했다(${golden.path}) — 기록 실행은 실패로 끝난다. 기록 변수 없이 다시 돌려 대조한다.")
        }
        assertTrue("$name: 골든이 없다(${golden.path}) — 이 맥에서 ${SnapshotCompare.RECORD_ENV}=1 로 기록한다", golden.isFile)
        val expected = AndroidSnapshots.readPng(golden)
        val exact = SnapshotPolicy.isRecordingHost(System.getProperty("os.name"), System.getProperty("os.arch"))
        val diff = SnapshotCompare.diff(expected, actual)
        val coarse = SnapshotCompare.coarse(expected, actual)
        println("AINGCHECK-SNAPSHOT android $name mode=${if (exact) "exact" else "coarse"} ${actual.width}x${actual.height} diff=$diff coarse=$coarse")
        if (!(if (exact) diff.identical else coarse.withinTolerance)) {
            AndroidSnapshots.writePng(actual, File(out, "$name-actual.png"))
            SnapshotCompare.diffImage(expected, actual)?.let { AndroidSnapshots.writePng(it, File(out, "$name-diff.png")) }
            fail("$name: 골든과 다르다($diff · $coarse) — build/aingcheck-snapshots/android/$name-{actual,diff}.png")
        }
        val baseline = render(other)
        assertEquals("$name: 기준선 크기가 다르다", actual.width to actual.height, baseline.width to baseline.height)
        val negative = SnapshotCompare.diff(actual, baseline)
        val negativeCoarse = SnapshotCompare.coarse(actual, baseline)
        println("AINGCHECK-SNAPSHOT-NEGATIVE android $name diff=$negative coarse=$negativeCoarse")
        assertFalse("$name: 한 군데 다른 장면인데 같은 픽셀 — 비교가 내용을 못 본다", negative.identical)
        assertTrue("$name: 기준선 차이 ${negative.differingPixels}px — 한 군데만 달라야 한다", negative.differingPixels in 1 until actual.argb.size / 10)
        assertFalse("$name: 굵은 대조가 한 군데 다른 장면을 못 잡는다($negativeCoarse)", negativeCoarse.withinTolerance)
    }

    private companion object {
        const val TAG = "aingcheck-board-scene"
    }
}
