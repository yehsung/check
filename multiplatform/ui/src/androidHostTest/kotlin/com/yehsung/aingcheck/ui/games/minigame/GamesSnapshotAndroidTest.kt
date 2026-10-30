// 원본: Sources/CheckMobileKit/Games/GamesTab.swift @ 3bd04bd · GamesTetrisCanvas.swift · GamesTetrisDuelMatch.swift @ 3bd04bd (화면 — 스냅숏은 이식 시험)
//
// 게임 화면 스냅숏(폰 = Android xhdpi 배율 2, Robolectric NATIVE). 골든: ui/snapshots/games/{minigame,tetris}/android/<장면>.png
// 데스크톱 판(GamesSnapshotDesktopTest)과 같은 장면 셋(허브 · 테트리스 혼자 · 1:1 판)과 같은 세 가지 판정: ① 새로 세 번 그려도 같다
// ② 골든과 같다(기록 기계 픽셀 그대로 · 다른 러너 굵은 대조) ③ 한 군데 다른 같은 크기 장면은 다르다.
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.chess.ChessRecord
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuRecord
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.TetrisActionResponse
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.ui.components.AndroidSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubBoardFactsSnapshot
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubScreen
import com.yehsung.aingcheck.ui.games.tetris.GamesTetrisDuelMatchView
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.test.TestScope
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
@Config(sdk = [36], qualifiers = "w390dp-h900dp-xhdpi")
class GamesSnapshotAndroidTest {
    private val now = SwiftDate(1_789_621_500.0)
    private val art by lazy {
        MiniGameArt(AndroidSnapshots.repoImage(MiniGameArt.FLAPPY_SIDE_SOURCE), AndroidSnapshots.repoImage(MiniGameArt.FLAPPY_NEGATIVE_SOURCE))
    }

    private fun store(): GamesStore {
        val h = UiGamesHarness(TestScope(), AppConfig(duelsEnabled = true)) { null }
        h.tetris.clock = { now }
        h.tetris.uptime = { 1_000.0 } // 판 경과 시계(단조 시계)를 멈춘다 — 렌더 사이에 초가 넘어가면 '1:13 → 1:14' 로 장면이 흔들린다(Android 실측)
        return GamesStore(h.context)
    }

    private fun tetris(extraRotate: Boolean = false): TetrisGame = TetrisGame(seed = 20_260_919uL).also { g ->
        g.action()
        repeat(6) {
            g.step(0.05)
            g.action()
            repeat(12) { g.step(1.0 / 30) }
        }
        g.step(0.2)
        if (extraRotate) g.rotate(clockwise = true)
    }

    private fun hubScene(chessIncoming: Boolean = false): @Composable () -> Unit {
        val store = store()
        val facts = GamesHubBoardFactsSnapshot(gomokuRecord = GomokuRecord(12, 9, 1), chessRecord = ChessRecord(3, 2, 0), chessHasIncoming = chessIncoming)
        return { AingTheme(dark = false) { GamesHubScreen(store, facts, art, { now }, {}, {}, {}, Modifier.size(PHONE_W.dp, PHONE_H.dp)) } }
    }

    private fun matchScene(meName: String): @Composable () -> Unit {
        val store = store()
        val state = SwiftJson.decode(TetrisActionResponse.serializer(), RepoFiles.readText("$FIXTURES/rpc.tetris_state@demo-tetris-playing.json"))
        // 한 판 한 기기(Swift 75c31cd2 — TetrisDuelStore 머리말 ⑩): 데모 픽스처는 그 판에서 my_device 'this' 를 싣는다(Swift
        // GamesTetrisFixtureContractTests ①-b). 이 워크트리의 픽스처는 그 전이라 없으면 여기서 'this' 로 읽는다 — 안 그러면 코어가 구동기를
        // 안 세워 스틸이 빈 판(다른 기기 안내)이 된다. 픽스처가 따라오면 이 줄은 아무 일도 안 한다.
        val payload = requireNotNull(state.state).let { if (it.myDevice == null) it.copy(myDevice = "this") else it }
        store.tetris.applyState(payload)
        check(store.tetris.match != null) { "픽스처로 판이 서지 않았다" }
        check(store.tetris.duel != null && !store.tetris.playingElsewhere) { "픽스처 판에 구동기가 안 섰다" }
        return {
            AingTheme(dark = true) {
                GamesTetrisDuelMatchView(store, refreshHz = 60, appActive = true, reduceMotion = true, meName = meName, modifier = Modifier.size(PHONE_W.dp, PHONE_H.dp))
            }
        }
    }

    @Test fun hubLight() = check("games/minigame", "hub-light", hubScene(), hubScene(chessIncoming = true))

    @Test fun tetrisSoloCanvas() = check(
        "games/minigame", "tetris-solo-dark",
        { AingTheme(dark = true) { GamesTetrisCanvas(tetris(), 18_400L, reduceMotion = true, modifier = Modifier.size(PHONE_W.dp, TETRIS_H.dp)) } },
        { AingTheme(dark = true) { GamesTetrisCanvas(tetris(extraRotate = true), 18_400L, reduceMotion = true, modifier = Modifier.size(PHONE_W.dp, TETRIS_H.dp)) } },
    )

    @Test fun tetrisMatch() = check("games/tetris", "match-playing-dark", matchScene("새벽"), matchScene("새벽빵"))

    @OptIn(ExperimentalTestApi::class)
    private fun render(content: @Composable () -> Unit): PixelImage {
        var out: PixelImage? = null
        runComposeUiTest {
            setContent { Box(Modifier.wrapContentSize(Alignment.TopStart, unbounded = true).testTag(TAG)) { content() } }
            waitForIdle()
            out = AndroidSnapshots.pixels(onNodeWithTag(TAG).captureToImage())
        }
        return requireNotNull(out)
    }

    private fun check(group: String, name: String, scene: @Composable () -> Unit, other: @Composable () -> Unit) {
        val renders = List(3) { render(scene) }
        val out = AndroidSnapshots.outDir()
        for (i in 1..2) {
            val d = SnapshotCompare.diff(renders[0], renders[i])
            if (!d.identical) {
                AndroidSnapshots.writePng(renders[0], File(out, "$name-render1.png"))
                AndroidSnapshots.writePng(renders[i], File(out, "$name-render${i + 1}.png"))
                fail("$name: 1장과 ${i + 1}장이 다르다($d) — 렌더가 굳지 않았다")
            }
        }
        val actual = renders[0]
        AndroidSnapshots.writePng(actual, File(out, "games-$name.png")) // 증거용 사본(build/ 아래)
        assertTrue("$name: 색이 ${actual.distinctColors()}개뿐 — 장면이 그려지지 않았다", actual.distinctColors() >= 64)
        val golden = AndroidSnapshots.golden(group, name)
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
            fail("$name: 골든과 다르다(${if (exact) "픽셀 그대로" else "굵은 대조"} — $diff · $coarse)")
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
        const val TAG = "aingcheck-games-scene"
        const val PHONE_W = 390
        const val PHONE_H = 844
        const val TETRIS_H = 560
        const val FIXTURES = "Sources/CheckMobileKit/Demo/Fixtures/games"
    }
}
