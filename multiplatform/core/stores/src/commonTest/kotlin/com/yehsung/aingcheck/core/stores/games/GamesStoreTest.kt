// 원본: Tests/CheckMobileKitTests/GamesTetrisDuelWiringTests.swift:338-820(화면 훅 · P8 · 한 사람 한 판 삼각 · 딥링크 · 화면 꺼짐 · presentWindow) ·
//       GamesStoreHardeningTests.swift:84-200 @ 1b8260d
// G §2-3 W2-e ③ 바쁨 판정 세 방향: 오목·체스·테트리스 가운데 하나가 흐르면 나머지 둘의 입구가 막힌다(서버 오목 게이트는 남을 모른다).
package com.yehsung.aingcheck.core.stores.games

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelPhase
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStoreTest
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisDuelCard
import com.yehsung.aingcheck.core.stores.tetris.tick
import com.yehsung.aingcheck.core.wire.games.TetrisStatePayload
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import androidx.compose.runtime.snapshots.Snapshot
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class GamesStoreTest {
    private val json = Json { ignoreUnknownKeys = true }

    private class Stub {
        var lobby: Reply = TetrisDuelStoreTest.lobby()
        var state: Reply = TetrisDuelStoreTest.action(state = TetrisDuelStoreTest.activeState())
        fun route(r: RecordedRequest): Reply? = when (r.rpcName) {
            "tetris_lobby" -> lobby
            "tetris_state" -> state
            "tetris_respond" -> TetrisDuelStoreTest.action(state = TetrisDuelStoreTest.activeState())
            "tetris_report" -> TetrisDuelStoreTest.action(state = TetrisDuelStoreTest.activeState(mySeq = 1))
            "tetris_ranking" -> Reply.Json("""{"status":"ok","rows":[]}""")
            "minigame_board", "minigame_yesterday_winner" -> Reply.Json("[]")
            "minigame_start_round" -> Reply.Json("""{"status":"ok","token":"t1"}""")
            else -> if (r.path == "/rest/v1/profiles") Reply.Json("""[{"minigame_public":true}]""") else null
        }
    }

    private suspend fun TestScope.games(enabled: Boolean = true, stub: Stub = Stub()): Pair<StoreHarness, GamesStore> {
        val h = StoreHarness(this, AppConfig(duelsEnabled = enabled), route = stub::route)
        h.signIn()
        h.tetris.uptime = { testScheduler.currentTime / 1000.0 }
        return h to GamesStore(h.context)
    }

    private fun StoreHarness.applyTetris(stateJson: String) {
        tetris.applyState(json.decodeFromString(TetrisStatePayload.serializer(), stateJson), 0.0)
    }

    private data class Blocks(val chess: GamesBusyGame?, val gomoku: GamesBusyGame?, val tetris: GamesBusyGame?)

    private fun GamesStore.blocks() = Blocks(chessEntryBlock, gomokuEntryBlock, tetrisEntryBlock)

    /**
     * ★ 한 사람 한 판은 **삼각**이다. 판 하나가 흐르면 **나머지 둘**의 입구가 막히고 자기 입구는 열린 채다. 끝난 판·AI 판·로봇 판은 막지 않는다.
     * 서버가 말한 진행 판 id 만 알고 판을 아직 못 읽어도 막는다(그 틈은 1 왕복이 아니라 **열린 채로 남을 수 있다**).
     */
    @Test
    fun oneMatchAtATimeBlocksTheOtherTwoEntrances() = runTest {
        val g = GamesBusyGame.gomoku
        val c = GamesBusyGame.chess
        val t = GamesBusyGame.tetris
        val table: List<Triple<String, (StoreHarness) -> Unit, Blocks>> = listOf(
            Triple("판 없음", { _ -> }, Blocks(null, null, null)),
            Triple("오목 사람 판", { h -> h.gomoku.holdMatch() }, Blocks(g, null, g)),
            Triple("오목 진행 판 id 만", { h -> h.gomoku.activeMatchID = "gm-1" }, Blocks(g, null, g)),
            Triple("오목 AI 판", { h -> h.gomoku.holdMatch(ai = true) }, Blocks(null, null, null)),
            Triple("오목 끝난 판", { h -> h.gomoku.holdMatch(finished = true) }, Blocks(null, null, null)),
            Triple("체스 사람 판", { h -> h.chess.holdMatch() }, Blocks(null, c, c)),
            Triple("체스 로봇 판", { h -> h.chess.holdMatch(ai = true) }, Blocks(null, null, null)),
            Triple("테트리스 판", { h -> h.applyTetris(TetrisDuelStoreTest.activeState()) }, Blocks(t, t, null)),
            Triple("테트리스 끝난 판", { h -> h.applyTetris(TetrisDuelStoreTest.activeState(finished = true)) }, Blocks(null, null, null)),
            Triple("오목 + 테트리스", { h -> h.gomoku.holdMatch(); h.applyTetris(TetrisDuelStoreTest.activeState()) }, Blocks(g, t, g)),
            Triple("체스 + 테트리스", { h -> h.chess.holdMatch(); h.applyTetris(TetrisDuelStoreTest.activeState()) }, Blocks(t, c, c)),
        )
        for ((label, arrange, expected) in table) {
            val (h, games) = games()
            arrange(h)
            assertEquals(expected, games.blocks(), label)
        }
    }

    /** 테트리스: 서버가 말한 진행 판 id 만 알고 `tetris_state` 가 실패해 판을 못 읽어도 오목·체스 입구는 막힌다. 화면 꺼짐은 들고 있는 판만 본다. */
    @Test
    fun aTetrisMatchIdAloneStillBlocksButDoesNotKeepTheScreenOn() = runTest {
        val stub = Stub()
        stub.lobby = TetrisDuelStoreTest.lobby(incoming = false, activeMatch = "tm-1")
        stub.state = Reply.Offline
        val (h, games) = games(stub = stub)
        h.tetris.refreshLobby()
        runCurrent()
        assertNull(h.tetris.match, "판은 못 읽었다")
        assertEquals("tm-1", h.tetris.activeMatchID)
        assertEquals(Blocks(GamesBusyGame.tetris, GamesBusyGame.tetris, null), games.blocks())
        games.appDidBecomeActive()
        assertFalse(games.wantsIdleTimerDisabled, "id 만 알고 판을 못 읽은 채로 화면을 켜 두지 않는다")
    }

    /** 막힌 입구는 **두 줄**을 말한다(왜 · 언제 풀리는지) — 세 게임이라 '반대쪽' 이 없다: 두는 판과 막힌 입구를 둘 다 받는다. */
    @Test
    fun blockedEntrancesSayWhyAndWhen() = runTest {
        assertEquals("오목을 두는 중이에요", GamesBusyText.entryBlock(GamesBusyGame.gomoku))
        assertEquals("체스를 두는 중이에요", GamesBusyText.entryBlock(GamesBusyGame.chess))
        assertEquals("1:1 테트리스 대결 중이에요", GamesBusyText.entryBlock(GamesBusyGame.tetris))
        assertNull(GamesBusyText.entryBlock(null))
        assertEquals("오목 판이 끝나면 1:1 테트리스를 신청할 수 있어요", GamesBusyText.entryBlockHint(GamesBusyGame.gomoku, GamesBusyGame.tetris))
        assertEquals("테트리스 대결이 끝나면 체스를 신청할 수 있어요", GamesBusyText.entryBlockHint(GamesBusyGame.tetris, GamesBusyGame.chess))
        assertEquals("체스 판이 끝나면 오목을 신청할 수 있어요", GamesBusyText.entryBlockHint(GamesBusyGame.chess, GamesBusyGame.gomoku))
        assertEquals("오목을 두는 중이에요\n오목 판이 끝나면 체스를 신청할 수 있어요",
            GamesBusyText.entryBlockNotice(GamesBusyGame.gomoku, GamesBusyGame.chess))
        val (h, games) = games()
        h.gomoku.holdMatch()
        assertEquals(GamesTetrisDuelCard.Line.blocked, GamesTetrisDuelCard.line(games), "차단이 카드 서열 맨 앞")
        assertEquals("오목을 두는 중이에요", GamesTetrisDuelCard.chip(games))
        assertEquals("오목 판이 끝나면 1:1 테트리스를 신청할 수 있어요", GamesTetrisDuelCard.detail(games))
    }

    /** 테트리스 판이 흐르는 동안 들어온 오목 링크는 오목 화면을 열지 않는다(첫 화면) — 기준선: 막힘이 없으면 쌓고 대상 id 를 남긴다. */
    @Test
    fun aGomokuLinkDoesNotOpenWhileTetrisIsLive() = runTest {
        val (h, games) = games()
        assertEquals(GamesRouteStep.Push(GamesDestination.Gomoku), games.routeStep(GamesRouteRequest.GomokuMatch("gm-9")))
        assertEquals("gm-9", games.pendingGomokuFocusID)
        h.applyTetris(TetrisDuelStoreTest.activeState())
        assertEquals(GamesRouteStep.PopToRoot, games.routeStep(GamesRouteRequest.GomokuInvite("gi-1")))
        assertNull(games.pendingGomokuFocusID, "막힌 링크는 대상을 남기지 않는다")
        assertTrue(h.gomoku.calls.none { it.startsWith("openWindow") })
        assertEquals(GamesRouteStep.Push(GamesDestination.MiniGame(MiniGameKind.tetris)),
            games.routeStep(GamesRouteRequest.MiniGame(MiniGameKind.tetris)), "솔로 테트리스 링크는 그대로 열린다")
        assertEquals(GamesRouteStep.PopToRoot, games.routeStep(GamesRouteRequest.MiniGame(MiniGameKind.crossy)),
            "이 빌드에 보이지 않는 게임(길건너)은 쌓지 않는다")
        assertNull(games.routeStep(GamesRouteRequest.Other))
    }

    /**
     * ★ 화면이 뜨면 **준비 보고가 나간다** — 그 문을 켜는 것은 `tetrisScreenDidAppear()` 의 `windowDidShow()` 하나다. 기준선(훅을 안 부름)은
     * 같은 수락한 판에서 보고 0건이다(= 수락한 판이 30초 뒤 no_show 로 흘러간다). 떠나는 길(`…DidDisappear`)에서는 요청이 한 건도 안 나간다.
     */
    @Test
    fun theScreenHookOpensTheReadyReport() = runTest {
        for (hooked in listOf(false, true)) {
            val (h, games) = games()
            games.appDidBecomeActive()
            h.tetris.refreshLobby()
            runCurrent()
            h.tetris.respond("inv-1", accept = true)
            runCurrent()
            assertEquals(TetrisDuelPhase.ready, h.tetris.phase)
            if (hooked) games.tetrisScreenDidAppear()
            advanceTimeBy(500)
            h.tetris.tick()
            runCurrent()
            assertEquals(if (hooked) 1 else 0, h.server.count("tetris_report"), "hooked=$hooked")
            if (hooked) {
                val before = h.server.requests.size
                games.tetrisScreenDidDisappear()
                runCurrent()
                assertEquals(before, h.server.requests.size, "떠나는 길에서 요청 0건(기권이 아니다)")
                assertEquals("inv-1", h.tetris.match?.id, "흐르는 판은 남는다")
            }
        }
    }

    /** 끝난 판은 떠날 때 접힌다 — 다시 열면 결과가 아니라 로비가 선다. 진행 중인 판은 남는다. */
    @Test
    fun leavingFoldsAFinishedMatchOnly() = runTest {
        val (h, games) = games()
        games.appDidBecomeActive()
        h.applyTetris(TetrisDuelStoreTest.activeState())
        games.tetrisScreenDidAppear()
        h.applyTetris(TetrisDuelStoreTest.activeState(finished = true))
        assertEquals(TetrisDuelPhase.finished, h.tetris.phase)
        games.tetrisScreenDidDisappear()
        assertNull(h.tetris.match, "끝난 판은 접힌다")
        assertEquals(TetrisDuelPhase.lobby, h.tetris.phase)
    }

    /**
     * P8: active 복귀의 로비 조회는 **어느 가지에서도 한 번**이고, 화면이 없으면 창 깃발·폴링·준비 보고가 서지 않는다. 체스 가지가 함수 꼬리를
     * 끊지 않는다(화면이 안 보이는 체스 가지 뒤에도 테트리스 따라잡기가 돈다).
     */
    @Test
    fun becomingActiveCatchesUpTetrisExactlyOnceOnEitherBranch() = runTest {
        for (visible in listOf(false, true)) {
            val (h, games) = games()
            if (visible) {
                games.appDidBecomeActive()
                games.tetrisScreenDidAppear()
                runCurrent()
                games.appDidEnterBackground()
                assertTrue(h.tetris.isWindowVisible, "background 는 가림이다(창은 그대로)")
            }
            val lobbiesBefore = h.server.count("tetris_lobby")
            games.appDidBecomeActive()
            runCurrent()
            assertEquals(1, h.server.count("tetris_lobby") - lobbiesBefore, "visible=$visible — 로비 따라잡기 한 번")
            assertEquals(visible, h.tetris.isWindowVisible, "visible=$visible — 화면이 없으면 창 깃발을 세우지 않는다")
            assertTrue(h.chess.calls.contains("refreshLobbyIfStale"))
            assertEquals(0, h.server.count("tetris_report"))
        }
    }

    /** 코어가 판이 막 섰다고 알리면(presentWindow) 앱이 active 일 때만 게임 탭에 테트리스 화면을 쌓는다 — 이미 보이면 또 쌓지 않는다. */
    @Test
    fun aStartedMatchPresentsTheTetrisScreenOnce() = runTest {
        val (h, games) = games()
        h.applyTetris(TetrisDuelStoreTest.activeState(id = "m-1"))
        assertEquals(emptyList(), h.router.presented, "앱이 active 가 아니면 쌓지 않는다")
        games.appDidBecomeActive()
        h.applyTetris(TetrisDuelStoreTest.activeState(id = "m-1", finished = true))
        h.tetris.windowDidClose()
        h.applyTetris(TetrisDuelStoreTest.activeState(id = "m-2"))
        assertEquals(listOf<GamesDestination>(GamesDestination.TetrisDuel), h.router.presented)
        games.tetrisScreenDidAppear()
        assertEquals(1, h.router.presented.size, "보이는 화면은 또 쌓지 않는다")
    }

    /** 화면 꺼짐 방지: 테트리스 판·끝나지 않은 미니게임(타이밍 바 빼고)·1:1 체스는 켠다 · background 면 푼다 · 같은 값은 다시 안 넘긴다. */
    @Test
    fun theIdleTimerFollowsWhatIsRunning() = runTest {
        val (h, games) = games()
        // Compose 스냅숏 쓰기 알림은 앱에서는 compose-ui 의 전역 관리자가 보낸다 — 순수 런타임 시험은 손으로 보낸다.
        fun flush() {
            Snapshot.sendApplyNotifications()
            runCurrent()
        }
        val applied = mutableListOf<Boolean>()
        games.installIdleTimerSink { applied += it }
        flush()
        assertEquals(listOf(false), applied)
        games.appDidBecomeActive()
        h.applyTetris(TetrisDuelStoreTest.activeState())
        flush()
        assertEquals(listOf(false, true), applied, "테트리스 판이 돌면 어느 화면에 있든 켠다")
        games.appDidEnterBackground()
        flush()
        assertEquals(listOf(false, true, false), applied)
        h.tetris.reset()
        games.appDidBecomeActive()
        games.miniGames.openScreen(MiniGameKind.timingBar)
        games.miniGames.controller!!.tap()
        flush()
        assertTrue(games.miniGames.controller!!.isPlaying)
        assertFalse(games.wantsIdleTimerDisabled, "타이밍 바는 스스로 끝나지 않아 화면을 켜 두지 않는다")
        games.miniGames.openScreen(MiniGameKind.flappy)
        games.miniGames.controller!!.tap()
        flush()
        assertTrue(games.wantsIdleTimerDisabled, "플래피 판은 켠다")
        assertEquals(true, applied.last())
        h.chess.holdMatch(ai = true)
        games.miniGames.closeScreen(MiniGameKind.flappy)
        flush()
        assertFalse(games.wantsIdleTimerDisabled, "로봇 체스는 체스 화면이 보일 때만")
        h.chess.holdMatch()
        assertTrue(games.wantsIdleTimerDisabled, "1:1 체스는 켠다")
    }

    /** 오목 화면 수명: 나타남 → openWindow(대상) + windowDidShow · 사라짐 → 관전 먼저 내리고 숨김 → 닫힘 · AI 선택기 허락이 따라간다. */
    @Test
    fun gomokuScreenLifecycleKeepsTheOrder() = runTest {
        val (h, games) = games()
        games.appDidBecomeActive()
        games.routeStep(GamesRouteRequest.GomokuInvite("gi-7"))
        games.gomokuScreenDidAppear()
        assertEquals(listOf("refreshInboxIfStale", "openWindow(gi-7)", "windowDidShow"), h.gomoku.calls)
        assertEquals(true, h.gomoku.aiAllowed)
        games.gomokuScreenDidDisappear()
        assertEquals(listOf("stopWatching", "windowDidHide", "windowDidClose"), h.gomoku.calls.drop(3))
        assertEquals(false, h.gomoku.aiAllowed)
    }
}
