// 원본: Sources/CheckMobileKit/Games/GamesTab.swift @ 3bd04bd · GamesTimingBarCanvas.swift · GamesFlappyCanvas.swift · GamesTetrisCanvas.swift ·
//       GamesTetrisDuelScreen.swift · GamesTetrisDuelMatch.swift @ 3bd04bd (화면 — 스냅숏은 이식 시험)
//
// 게임 화면 스냅숏(데스크톱 배율 2). 골든: ui/snapshots/games/{minigame,tetris}/desktop/<장면>.png
// 진열장 스냅숏(GallerySnapshotDesktopTest)과 같은 세 가지를 잰다: ① 세 번 새로 그려 같다(굳은 렌더) ② 골든과 같다(기록 기계는 픽셀 그대로,
// 다른 러너는 굵은 대조) ③ 한 군데만 다른 장면(음성 기준선)은 골든과 다르다.
// 판 값은 시드 고정 엔진을 직접 굴려 만든다(시계 0 — 장면 안에서 시간이 흐르지 않는다). 로비·대결 값은 폰 데모 픽스처(저장소 경로에서 읽는다).
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.minigame.FlappyGame
import com.yehsung.aingcheck.core.rules.minigame.TimingBarGame
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.chess.ChessRecord
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuRecord
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.TetrisActionResponse
import com.yehsung.aingcheck.core.wire.games.TetrisLobbyResponse
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubBoardFactsSnapshot
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubScreen
import com.yehsung.aingcheck.ui.games.tetris.GamesTetrisDuelMatchView
import com.yehsung.aingcheck.ui.games.tetris.GamesTetrisDuelScreen
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.TestScope
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.fail

class GamesSnapshotDesktopTest {
    private val now = SwiftDate(1_789_621_500.0)
    private val art by lazy {
        MiniGameArt(DesktopSnapshots.repoImage(MiniGameArt.FLAPPY_SIDE_SOURCE), DesktopSnapshots.repoImage(MiniGameArt.FLAPPY_NEGATIVE_SOURCE))
    }

    // MARK: 판 값(시드 고정)

    private fun tetris(extraRotate: Boolean = false): TetrisGame = TetrisGame(seed = 20_260_919uL).also { g ->
        g.action()
        repeat(6) {
            g.step(0.05)
            g.action() // 하드드롭
            repeat(12) { g.step(1.0 / 30) } // 텀 · 다음 조각
        }
        g.step(0.2)
        if (extraRotate) g.rotate(clockwise = true)
    }

    /** [lateFrames] 장 늦게 누른 판(판정 뒤 정지 구간이라 그 뒤 시간은 그림을 바꾸지 않는다 — 누르는 순간을 바꿔야 한 군데가 달라진다). */
    /** 한 번의 step 은 maxStep(1/30 초)으로 잘린다 — 시간은 장 단위로 흘린다. */
    private fun timing(lateFrames: Int = 0): TimingBarGame = TimingBarGame(seed = 7uL).also { g ->
        g.tap() // 시작
        repeat(11 + lateFrames) { g.step(1.0 / 30) }
        g.tap() // 판정 1
        repeat(6) { g.step(1.0 / 30) }
    }

    private fun flappy(extraFlap: Boolean = false): FlappyGame = FlappyGame(seed = 11uL).also { g ->
        g.flap() // 시작
        repeat(40) { i ->
            if (i % 12 == 0) g.flap()
            g.step(1.0 / 30)
        }
        if (extraFlap) {
            g.flap() // 날갯짓은 속도만 바꾼다 — 몇 장 흘러야 자리가 달라진다
            repeat(4) { g.step(1.0 / 30) }
        }
    }

    // MARK: 장면

    private fun store(duelsEnabled: Boolean = true): GamesStore {
        val h = UiGamesHarness(TestScope(), AppConfig(duelsEnabled = duelsEnabled)) { null }
        h.tetris.clock = { now }
        h.tetris.uptime = { 1_000.0 } // 판 경과 시계(단조 시계)를 멈춘다 — 렌더 사이에 초가 넘어가면 '1:13 → 1:14' 로 장면이 흔들린다(Android 실측)
        return GamesStore(h.context)
    }

    private fun hubScene(dark: Boolean, chessIncoming: Boolean = false): @Composable () -> Unit {
        val store = store()
        val facts = GamesHubBoardFactsSnapshot(gomokuRecord = GomokuRecord(12, 9, 1), chessRecord = ChessRecord(3, 2, 0), chessHasIncoming = chessIncoming)
        return { AingTheme(dark = dark) { GamesHubScreen(store, facts, art, { now }, {}, {}, {}, Modifier.size(PHONE_W.dp, PHONE_H.dp)) } }
    }

    private fun lobbyScene(duelsEnabled: Boolean): @Composable () -> Unit {
        val store = store(duelsEnabled)
        val lobby = SwiftJson.decode(TetrisLobbyResponse.serializer(), RepoFiles.readText("$FIXTURES/_games-tetris-lobby-invites/rpc.tetris_lobby.json"))
        runBlocking { store.tetris.applyLobby(lobby) }
        return { AingTheme(dark = false) { GamesTetrisDuelScreen(store, myUserID = null, refreshHz = 60, modifier = Modifier.size(PHONE_W.dp, PHONE_H.dp)) } }
    }

    private fun matchScene(meName: String): @Composable () -> Unit {
        val store = store()
        val state = SwiftJson.decode(TetrisActionResponse.serializer(), RepoFiles.readText("$FIXTURES/rpc.tetris_state@demo-tetris-playing.json"))
        // 한 판 한 기기(Swift 75c31cd2): 데모 픽스처는 my_device 'this' 를 싣는다(GamesTetrisFixtureContractTests ①-b) — 구동기가 서야 스틸이 판이다.
        store.tetris.applyState(requireNotNull(state.state))
        check(store.tetris.match != null) { "픽스처로 판이 서지 않았다" }
        check(store.tetris.duel != null && !store.tetris.playingElsewhere) { "픽스처 판에 구동기가 안 섰다" }
        return {
            AingTheme(dark = true) {
                GamesTetrisDuelMatchView(store, refreshHz = 60, appActive = true, reduceMotion = true, meName = meName, modifier = Modifier.size(PHONE_W.dp, PHONE_H.dp))
            }
        }
    }

    private fun canvas(dark: Boolean, heightDp: Int, body: @Composable (Modifier) -> Unit): @Composable () -> Unit =
        { AingTheme(dark = dark) { body(Modifier.size(PHONE_W.dp, heightDp.dp)) } }

    @Test fun hubLight() = check("games/minigame", "hub-light", PHONE_H, hubScene(false), hubScene(false, chessIncoming = true))
    @Test fun hubDark() = check("games/minigame", "hub-dark", PHONE_H, hubScene(true), hubScene(true, chessIncoming = true))

    @Test fun timingBarCanvas() = check(
        "games/minigame", "timing-bar-light", CANVAS_H,
        canvas(false, CANVAS_H) { GamesTimingBarCanvas(timing(), 412L, reduceMotion = true, modifier = it) },
        canvas(false, CANVAS_H) { GamesTimingBarCanvas(timing(lateFrames = 2), 412L, reduceMotion = true, modifier = it) },
    )

    @Test fun flappyCanvas() = check(
        "games/minigame", "flappy-light", CANVAS_H,
        canvas(false, CANVAS_H) { GamesFlappyCanvas(flappy(), 9L, reduceMotion = true, art = art, modifier = it) },
        canvas(false, CANVAS_H) { GamesFlappyCanvas(flappy(extraFlap = true), 9L, reduceMotion = true, art = art, modifier = it) },
    )

    @Test fun tetrisSoloCanvas() = check(
        "games/minigame", "tetris-solo-dark", TETRIS_H,
        canvas(true, TETRIS_H) { GamesTetrisCanvas(tetris(), 18_400L, reduceMotion = true, modifier = it) },
        canvas(true, TETRIS_H) { GamesTetrisCanvas(tetris(extraRotate = true), 18_400L, reduceMotion = true, modifier = it) },
    )

    @Test fun tetrisLobby() = check("games/tetris", "lobby-invites-light", PHONE_H, lobbyScene(duelsEnabled = true), lobbyScene(duelsEnabled = false))

    @Test fun tetrisMatch() = check("games/tetris", "match-playing-dark", PHONE_H, matchScene("새벽"), matchScene("새벽빵"))

    private fun check(group: String, name: String, heightDp: Int, scene: @Composable () -> Unit, other: @Composable () -> Unit) {
        val renders = List(3) { DesktopSnapshots.render(PHONE_W, heightDp, content = scene) }
        val out = DesktopSnapshots.outDir()
        for (i in 1..2) {
            val d = SnapshotCompare.diff(renders[0], renders[i])
            if (!d.identical) {
                DesktopSnapshots.writePng(renders[i], File(out, "$name-render${i + 1}.png"))
                fail("$name: 1장과 ${i + 1}장이 다르다($d) — 렌더가 굳지 않았다")
            }
        }
        val actual = renders[0]
        DesktopSnapshots.writePng(actual, File(out, "games-$name.png")) // 증거용 사본(build/ 아래)
        assertTrue(actual.distinctColors() >= 64, "$name: 색이 ${actual.distinctColors()}개뿐 — 장면이 그려지지 않았다")
        val golden = DesktopSnapshots.golden(group, name)
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
        val baseline: PixelImage = DesktopSnapshots.render(PHONE_W, heightDp, content = other)
        assertEquals(actual.width to actual.height, baseline.width to baseline.height, "$name: 기준선 크기가 다르다")
        val negative = SnapshotCompare.diff(actual, baseline)
        val negativeCoarse = SnapshotCompare.coarse(actual, baseline)
        println("AINGCHECK-SNAPSHOT-NEGATIVE desktop $name diff=$negative coarse=$negativeCoarse")
        assertFalse(negative.identical, "$name: 한 군데 다른 장면인데 같은 픽셀 — 비교가 내용을 못 본다")
        assertTrue(negative.differingPixels in 1 until actual.argb.size / 10, "$name: 기준선 차이 ${negative.differingPixels}px — 한 군데만 달라야 한다")
        assertFalse(negativeCoarse.withinTolerance, "$name: 굵은 대조가 한 군데 다른 장면을 못 잡는다($negativeCoarse)")
    }

    private companion object {
        const val PHONE_W = 390
        const val PHONE_H = 844
        const val CANVAS_H = 420
        const val TETRIS_H = 560
        const val FIXTURES = "Sources/CheckMobileKit/Demo/Fixtures/games"
    }
}
