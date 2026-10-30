// 원본: Sources/check/CheckMiniGameWindow.swift ★202(앱 테마 고정) · MiniGamePanel.swift:39-92 — Windows 는 공용 세로 화면을 창 기본 크기 440×720dp 에 그대로(W-3 #2)
//       (W4-e 완료 기준 — 오프스크린 스냅숏: 배율 100·150 × 밝음·어두움: 허브 · 테트리스 진행 · 오목 로비 · 체스 로비 · 테트리스 대결 로비)
//
// 세 가지를 잰다(ui GamesSnapshotDesktopTest 와 같은 정책): ① 세 번 새로 그려 같다(굳은 렌더) ② 골든과 같다(기록 기계는 픽셀 그대로, 다른 러너는 굵은 대조)
// ③ 한 군데만 다른 장면(음성 기준선 — 100%·밝음)은 골든과 다르다. 골든: 같은 글롭 아래 windows/games/<자리>/golden/<장면>.png.
// 판 게임 로비는 깃발 기본값(DesktopAppConfig() — 대결 꺼짐)으로 그린다: Windows 가 실제로 싣는 모습.
package com.yehsung.aingcheck.desktop.windows.games.minigame

import androidx.compose.runtime.Composable
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.chess.ChessRecord
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuRecord
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.TetrisLobbyResponse
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import com.yehsung.aingcheck.desktop.windows.games.chess.ChessWindowContent
import com.yehsung.aingcheck.desktop.windows.games.gomoku.GomokuWindowContent
import com.yehsung.aingcheck.desktop.windows.games.minigame.GameWindowScenes.BoardArt
import com.yehsung.aingcheck.desktop.windows.games.minigame.rig.BoardGameRig
import com.yehsung.aingcheck.ui.games.minigame.UiGamesHarness
import com.yehsung.aingcheck.desktop.windows.games.tetris.TetrisDuelWindowContent
import com.yehsung.aingcheck.desktop.windows.games.tetris.TetrisDuelWindowDoors
import com.yehsung.aingcheck.desktop.windows.games.tetris.TetrisDuelWindowState
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.games.minigame.MiniGameArt
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubBoardFactsSnapshot
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.TestScope
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.fail

class GamesWindowSnapshotTest {
    private val now = SwiftDate(1_789_621_500.0)
    private val art by lazy {
        MiniGameArt(DesktopSnapshots.repoImage(MiniGameArt.FLAPPY_SIDE_SOURCE), DesktopSnapshots.repoImage(MiniGameArt.FLAPPY_NEGATIVE_SOURCE))
    }
    private val windowW = GameWindowKind.MiniGame.defaultWidthDp
    private val windowH = GameWindowKind.MiniGame.defaultHeightDp
    private val shipped = DesktopAppConfig().toAppConfig()

    /** 장면 하나 = 그릴 것 + 첫 장 뒤 손댈 것. 부를 때마다 새 스토어(렌더 셋이 서로 상태를 나누지 않게). */
    private class Scene(val afterFirst: () -> Unit = {}, val content: @Composable () -> Unit)

    private fun gamesStore(config: com.yehsung.aingcheck.core.session.app.AppConfig = shipped): GamesStore {
        val h = UiGamesHarness(TestScope(), config) { null }
        h.tetris.clock = { now }
        h.tetris.uptime = { 1_000.0 }
        return GamesStore(h.context)
    }

    private fun hub(dark: Boolean, chessIncoming: Boolean = false): Scene {
        val store = gamesStore()
        val state = MiniGameWindowState(store.miniGames)
        val facts = GamesHubBoardFactsSnapshot(gomokuRecord = GomokuRecord(12, 9, 1), chessRecord = ChessRecord(3, 2, 0), chessHasIncoming = chessIncoming)
        return Scene { MiniGameWindowContent(store, state, facts, art, null, { now }, dark, reduceMotion = true, onOpenBoard = {}, onOpenShop = {}, onOpenRankings = {}) }
    }

    private fun tetrisSolo(dark: Boolean, drops: Int = 3): Scene {
        val store = gamesStore()
        val state = MiniGameWindowState(store.miniGames).also { it.show(MiniGameKind.tetris) }
        val facts = GamesHubBoardFactsSnapshot(gomokuRecord = null, chessRecord = null, chessHasIncoming = false)
        return Scene(afterFirst = {
            val c = requireNotNull(store.miniGames.controller) { "화면이 판을 열지 않았다" }
            c.tap() // 시작
            repeat(drops) { SoloTetrisKeys.action(c) } // 스페이스 = 하드드롭(판 중)
        }) { MiniGameWindowContent(store, state, facts, art, null, { now }, dark, reduceMotion = true, onOpenBoard = {}, onOpenShop = {}, onOpenRankings = {}) }
    }

    private fun gomokuLobby(dark: Boolean, oneLessUser: Boolean = false): Scene {
        val rig = BoardGameRig(me = null, duelsEnabled = shipped.duelsEnabled)
        GameWindowScenes.seedGomokuLobby(rig)
        if (oneLessUser) rig.gomoku.users = rig.gomoku.users.dropLast(1)
        return Scene { BoardArt { GomokuWindowContent(rig.games, rig.gomoku, BoardGameMe.unknown, dark, onLeave = {}) } }
    }

    private fun chessLobby(dark: Boolean, oneLessUser: Boolean = false): Scene {
        val rig = BoardGameRig(me = null, duelsEnabled = shipped.duelsEnabled)
        GameWindowScenes.seedChessLobby(rig)
        if (oneLessUser) rig.chess.users = rig.chess.users.dropLast(1)
        return Scene { BoardArt { ChessWindowContent(rig.games, rig.chess, BoardGameMe.unknown, dark, onLeave = {}) } }
    }

    private fun duelLobby(dark: Boolean, config: com.yehsung.aingcheck.core.session.app.AppConfig = shipped): Scene {
        val store = gamesStore(config)
        val lobby = SwiftJson.decode(TetrisLobbyResponse.serializer(), RepoFiles.readText("$FIXTURES/_games-tetris-lobby-invites/rpc.tetris_lobby.json"))
        runBlocking { store.tetris.applyLobby(lobby) }
        val state = TetrisDuelWindowState(TetrisDuelWindowDoors(store.tetris))
        return Scene { TetrisDuelWindowContent(store, state, myUserID = null, meName = null, dark = dark, reduceMotion = true, onBack = {}) }
    }

    @Test fun hubWindow() = matrix("minigame", "hub", { hub(it) }, hub(false, chessIncoming = true))
    @Test fun tetrisSoloWindow() = matrix("minigame", "tetris-playing", { tetrisSolo(it) }, tetrisSolo(false, drops = 0))
    @Test fun gomokuLobbyWindow() = matrix("gomoku", "lobby", { gomokuLobby(it) }, gomokuLobby(false, oneLessUser = true))
    @Test fun chessLobbyWindow() = matrix("chess", "lobby", { chessLobby(it) }, chessLobby(false, oneLessUser = true))
    @Test fun tetrisDuelLobbyWindow() = matrix("tetris", "duel-lobby", { duelLobby(it) }, duelLobby(false, com.yehsung.aingcheck.core.session.app.AppConfig(duelsEnabled = true)))

    /** 배율 100·150 × 밝음·어두움. 음성 기준선은 100%·밝음 한 장과 견준다. */
    private fun matrix(area: String, name: String, scene: (Boolean) -> Scene, baseline: Scene) {
        var lightAt100: PixelImage? = null
        for (scale in SCALES) for (dark in listOf(false, true)) {
            val tag = "$name-${(scale * 100).toInt()}-${if (dark) "dark" else "light"}"
            val image = check(area, tag, scale) { scene(dark) }
            if (scale == 1.0f && !dark) lightAt100 = image
        }
        val actual = requireNotNull(lightAt100)
        val other = draw(1.0f, baseline)
        assertEquals(actual.width to actual.height, other.width to other.height, "$name: 기준선 크기가 다르다")
        val negative = SnapshotCompare.diff(actual, other)
        val negativeCoarse = SnapshotCompare.coarse(actual, other)
        println("AINGCHECK-SNAPSHOT-NEGATIVE windows-games $name diff=$negative coarse=$negativeCoarse")
        assertFalse(negative.identical, "$name: 한 군데 다른 장면인데 같은 픽셀 — 비교가 내용을 못 본다")
        // 로비 기준선은 한 줄을 빼 아래가 밀린다 — 1/3 미만이면 '한 군데'로 본다(통째 다른 장면이면 빨강).
        assertTrue(negative.differingPixels in 1 until actual.argb.size / 3, "$name: 기준선 차이 ${negative.differingPixels}px — 한 군데만 달라야 한다")
        assertFalse(negativeCoarse.withinTolerance, "$name: 굵은 대조가 한 군데 다른 장면을 못 잡는다($negativeCoarse)")
        if (DesktopSnapshots.recording()) fail("$name: 골든 넷을 기록했다 — 기록 실행은 실패로 끝난다. 기록 변수 없이 다시 돌려 대조한다.")
    }

    private fun draw(scale: Float, scene: Scene): PixelImage =
        GameWindowScenes.render(windowW, windowH, scale, afterFirst = scene.afterFirst, content = scene.content)

    private fun check(area: String, tag: String, scale: Float, scene: () -> Scene): PixelImage {
        val renders = List(3) { draw(scale, scene()) }
        val out = File(DesktopSnapshots.mpRoot, "desktopApp/build/aingcheck-snapshots/windows-games").apply { mkdirs() }
        for (i in 1..2) {
            val d = SnapshotCompare.diff(renders[0], renders[i])
            if (!d.identical) {
                DesktopSnapshots.writePng(renders[i], File(out, "$tag-render${i + 1}.png"))
                fail("$tag: 1장과 ${i + 1}장이 다르다($d) — 렌더가 굳지 않았다")
            }
        }
        val actual = renders[0]
        assertEquals((windowW * scale).toInt() to (windowH * scale).toInt(), actual.width to actual.height, "$tag: 창 기본 크기 × 배율이 아니다")
        DesktopSnapshots.writePng(actual, File(out, "$tag.png"))
        assertTrue(actual.distinctColors() >= 64, "$tag: 색이 ${actual.distinctColors()}개뿐 — 장면이 그려지지 않았다")
        val golden = File(DesktopSnapshots.mpRoot, "$GOLDEN_ROOT/$area/golden/$tag.png")
        if (DesktopSnapshots.recording()) {
            golden.parentFile.mkdirs()
            DesktopSnapshots.writePng(actual, golden)
            return actual // 넷을 다 기록한 뒤 matrix 끝에서 실패로 끝낸다
        }
        assertTrue(golden.isFile, "$tag: 골든이 없다(${golden.path}) — 이 맥에서 ${SnapshotCompare.RECORD_ENV}=1 로 기록한다")
        val expected = DesktopSnapshots.readPng(golden)
        val exact = SnapshotPolicy.isRecordingHost(System.getProperty("os.name"), System.getProperty("os.arch"))
        val diff = SnapshotCompare.diff(expected, actual)
        val coarse = SnapshotCompare.coarse(expected, actual)
        println("AINGCHECK-SNAPSHOT windows-games $tag mode=${if (exact) "exact" else "coarse"} ${actual.width}x${actual.height} diff=$diff coarse=$coarse")
        val ok = if (exact) diff.identical else coarse.withinTolerance
        if (!ok) {
            DesktopSnapshots.writePng(actual, File(out, "$tag-actual.png"))
            SnapshotCompare.diffImage(expected, actual)?.let { DesktopSnapshots.writePng(it, File(out, "$tag-diff.png")) }
            fail("$tag: 골든과 다르다(${if (exact) "픽셀 그대로" else "굵은 대조"} — $diff · $coarse)")
        }
        return actual
    }

    private companion object {
        val SCALES = listOf(1.0f, 1.5f)
        const val FIXTURES = "Sources/CheckMobileKit/Demo/Fixtures/games"
        const val GOLDEN_ROOT = "desktopApp/src/test/kotlin/com/yehsung/aingcheck/desktop/windows/games"
    }
}
