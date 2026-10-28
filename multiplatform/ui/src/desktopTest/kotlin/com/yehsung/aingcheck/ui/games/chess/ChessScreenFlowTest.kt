// 원본: 없음 — G §2-3 W4-a ②③⑤ · §8-17 #1 · 6차 int-h '[조립 K11]' 의 화면 시험(체스). 스토어 시험(core/stores ChessStoreContractTest)과 같은 픽스처·같은 끝 상태.
//
// ⑤ 백 흐름을 **화면으로** 몬다: 화면 열기(로비 me.active_match_id → 코어가 내 판을 연다) → 판에서 e2 · e4 를 눌러 첫 수 → 폴링 한 번(상대 수) — 끝 상태(FEN ·
//    기보 SAN · 내 차례 · 루비 95 · p_protocol 1)가 스토어 시험과 같다. 흑 [수락]도 화면 단추로 누른다.
// ② 한 화면 안 탭(로봇 화면 덮개 · 규칙 · 관전 · 순위)에서 창 표시 · 폴링이 산다 — 기준선: 화면을 빼면 죽는다.
// ③ 뒤로가기 — 로봇 화면은 닫힘(판은 남는다) · 사람과의 판은 확인 · 승격 고르기는 cancelPromotion 하나.
// §8-17 #1 — 깃발 꺼짐/켜짐. K11 — 로비는 games.chessLobbyUsers 만.
package com.yehsung.aingcheck.ui.games.chess

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.DesktopComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.click
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.rules.chess.ChessMove
import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.rules.chess.fromUci
import com.yehsung.aingcheck.core.stores.chess.ChessInvite
import com.yehsung.aingcheck.core.stores.chess.ChessLiveMatch
import com.yehsung.aingcheck.core.stores.chess.ChessPhase
import com.yehsung.aingcheck.core.stores.chess.ChessRecord
import com.yehsung.aingcheck.core.stores.chess.ChessStake
import com.yehsung.aingcheck.core.stores.chess.ChessUser
import com.yehsung.aingcheck.core.stores.chess.isAIMatch
import com.yehsung.aingcheck.core.stores.chess.startAIMatch
import com.yehsung.aingcheck.ui.games.gomoku.BoardBackStep
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameRig
import com.yehsung.aingcheck.ui.games.gomoku.BoardTestTheme
import com.yehsung.aingcheck.ui.games.gomoku.CHESS_FIXTURES
import com.yehsung.aingcheck.ui.games.gomoku.boardClock
import com.yehsung.aingcheck.ui.games.gomoku.fixtureJSON
import com.yehsung.aingcheck.ui.games.gomoku.fixtureText
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class)
class ChessScreenFlowTest {
    private val users: JsonObject get() = fixtureJSON(CHESS_FIXTURES, "_manifest")["users"]!!.jsonObject
    private val m1: String get() = users["m1"]!!.jsonPrimitive.content
    private val playerA: String get() = users["A"]!!.jsonPrimitive.content
    private val playerB: String get() = users["B"]!!.jsonPrimitive.content

    private fun sq(notation: String): ChessSquare = ChessSquare.parse(notation)!!

    private fun DesktopComposeUiTest.settle(rig: BoardGameRig) {
        waitForIdle()
        rig.settle()
        waitForIdle()
    }

    /** 판의 그 칸 가운데를 누른다(뒤집기는 판 기하 하나가 쥔다 — 같은 식으로 화면 좌표를 낸다). */
    private fun DesktopComposeUiTest.tapSquare(tag: String, square: ChessSquare, whiteAtBottom: Boolean) {
        onNodeWithTag(tag).performTouchInput {
            val c = chessGeometry(width.toFloat(), whiteAtBottom).center(square)
            click(Offset(c.x.toFloat(), c.y.toFloat()))
        }
        waitForIdle()
    }

    @Test
    fun whiteFlowDrivenThroughTheScreenEndsWhereTheStoreTestEnds() = runDesktopComposeUiTest(420, 2600) {
        val rig = BoardGameRig(me = playerA) {
            // 화면 열기의 로비가 내 진행 판(m1)을 말한다 → 코어가 since 0 으로 판을 읽는다.
            respondWith("chess_lobby") { _, _ -> fixtureText(CHESS_FIXTURES, "chess_lobby__ok_in_match") }
            queueFixtures("chess_state", CHESS_FIXTURES, "chess_state__ok_initial_my_turn", "chess_state__ok_mid_since0")
            queueFixtures("chess_move", CHESS_FIXTURES, "chess_move__ok_white_first")
        }
        rig.games.appDidBecomeActive()
        setContent { BoardTestTheme { ChessScreen(rig.games, rig.chess, BoardGameMe("나백", "fox", com.yehsung.aingcheck.ui.components.CharacterMood.Working), onLeave = {}) } }
        settle(rig)
        val match = assertNotNull(rig.chess.match, "로비의 active_match_id 로 판이 안 열렸다")
        assertEquals(m1, match.id)
        assertEquals(0L, rig.server.calls.first { it.rpc == "chess_state" }.long("p_since_seq"))
        assertEquals(20, match.legalMoves.size)
        onNodeWithTag(ChessScreenTags.match).assertExists()
        // 입력 2단 — 화면의 판을 눌러서: 말 고르기(e2) → 도착 칸(e4).
        tapSquare(ChessScreenTags.board, sq("e2"), whiteAtBottom = true)
        settle(rig)
        assertEquals(setOf(sq("e3"), sq("e4")), rig.chess.selection?.targets)
        assertEquals(0, rig.server.count("chess_move"), "말 고르기가 수를 냈다")
        tapSquare(ChessScreenTags.board, sq("e4"), whiteAtBottom = true)
        settle(rig)
        assertEquals(1, rig.server.count("chess_move"))
        val body = rig.server.last("chess_move")
        assertEquals(0L, body.long("p_expected_ply"))
        assertEquals("e2e4", body.str("p_uci"))
        assertEquals(m1, body.str("p_match_id"))
        assertNull(rig.chess.selection)
        assertFalse(rig.chess.match!!.isMyTurn)
        assertEquals(ChessMove.fromUci("e2e4"), rig.chess.match!!.lastMove)
        // 상대 수 — 폴링 한 걸음(스토어 문). since 는 들고 있는 ply(1).
        rig.chess.scope.launch { rig.chess.refreshMatch() }
        settle(rig)
        assertEquals(1L, rig.server.last("chess_state").long("p_since_seq"))
        val mid = fixtureJSON(CHESS_FIXTURES, "chess_state__ok_mid_since0")
        assertEquals(mid["match"]!!.jsonObject["fen"]!!.jsonPrimitive.content, rig.chess.match!!.fen)
        assertEquals(listOf("e4", "e5", "Nf3", "Nc6", "Bb5", "Nf6"), rig.chess.match!!.moves.map { it.san })
        assertTrue(rig.chess.match!!.isMyTurn)
        assertEquals(95L, rig.host.rubyBalance)
        assertEquals(ChessPhase.playing, rig.chess.phase)
        for (call in rig.server.calls.filter { it.rpc.startsWith("chess_") }) assertEquals(1L, call.long("p_protocol"), "${call.rpc}: ${call.body}")
        // 화면도 같은 사실을 말한다 — 기보의 마지막 수(Nf6) · 내 차례.
        onNodeWithText("Nf6", useUnmergedTree = true).assertExists()
        onNodeWithTag("chess-turn-line").assertExists()
        rig.close()
    }

    @Test
    fun blackAcceptsThroughTheInviteCard() = runDesktopComposeUiTest(420, 2600) {
        val rig = BoardGameRig(me = playerB) { queueFixtures("chess_respond", CHESS_FIXTURES, "chess_respond__accept_ok") }
        rig.chess.incoming = ChessInvite(m1, ChessUser(playerA, "체스예은", null, "fox", true, true, false), 5, boardClock.addingTimeInterval(50.0))
        setContent { BoardTestTheme { ChessScreen(rig.games, rig.chess, BoardGameMe.unknown, onLeave = {}) } }
        settle(rig)
        onNodeWithTag(ChessScreenTags.accept(m1)).performClick()
        settle(rig)
        assertEquals(1, rig.server.count("chess_respond"))
        assertEquals("true", rig.server.last("chess_respond").body["p_accept"]?.jsonPrimitive?.content)
        assertNull(rig.chess.incoming)
        assertEquals(ChessColor.black, rig.chess.match!!.myColor)
        assertFalse(rig.chess.match!!.isMyTurn)
        onNodeWithTag(ChessScreenTags.match).assertExists()
        rig.close()
    }

    @Test
    fun pollingStaysAliveAcrossInScreenTabsAndDiesWhenTheScreenLeaves() = runDesktopComposeUiTest(420, 3200) {
        val live = fixtureJSON(CHESS_FIXTURES, "chess_lobby__ok_watch_entry")["matches"]!!.jsonArray.first().jsonObject["match_id"]!!.jsonPrimitive.content
        val rig = BoardGameRig(me = "cc000000-0000-4000-8000-0000000000c3") {
            respondWith("chess_lobby") { _, _ -> fixtureText(CHESS_FIXTURES, "chess_lobby__ok_watch_entry") }
            respondWith("chess_ranking") { _, _ -> fixtureText(CHESS_FIXTURES, "chess_ranking__ok_me_ranked") }
            respondWith("chess_watch_live") { _, _ -> fixtureText(CHESS_FIXTURES, "chess_watch__ok_active") }
        }
        rig.chess.spectatorFeaturesEnabled = true
        rig.games.appDidBecomeActive()
        var shown by mutableStateOf(true)
        setContent { BoardTestTheme { if (shown) ChessScreen(rig.games, rig.chess, BoardGameMe.unknown, onLeave = {}) } }
        settle(rig)
        fun assertAlive(label: String) {
            assertTrue(rig.games.isChessScreenVisible, "$label: 화면 표시가 꺼졌다")
            assertTrue(rig.chess.isWindowVisible, "$label: 창 표시가 꺼졌다")
            assertEquals(true, rig.chess.pollTask?.isActive, "$label: 폴링이 죽었다")
        }
        assertAlive("로비")
        onNodeWithTag(ChessScreenTags.rules).performClick()
        settle(rig)
        onNodeWithTag(ChessScreenTags.rulesSheet).assertExists()
        assertAlive("규칙")
        onNodeWithContentDescription("닫기").performClick()
        settle(rig)
        onNodeWithTag(ChessScreenTags.robotEntry).performClick()
        settle(rig)
        onNodeWithTag(ChessScreenTags.robotScreen).assertExists()
        assertAlive("로봇 화면")
        onNodeWithTag("chess-robot-close").performClick()
        settle(rig)
        onNodeWithTag(ChessScreenTags.watch(live)).performClick()
        settle(rig)
        onNodeWithTag("chess-watch").assertExists()
        assertAlive("관전")
        val before = rig.server.count("chess_watch_live")
        rig.advance(4.5)
        settle(rig)
        assertTrue(rig.server.count("chess_watch_live") > before, "관전 중 폴링이 관전 조회를 안 냈다")

        shown = false
        settle(rig)
        assertFalse(rig.chess.isWindowVisible, "화면이 빠졌는데 창 표시가 남았다")
        assertNull(rig.chess.pollTask, "화면이 빠졌는데 폴링이 남았다")
        assertNull(rig.chess.spectating)
        val after = rig.server.calls.count { it.rpc.startsWith("chess_") }
        rig.advance(10.0)
        settle(rig)
        assertEquals(after, rig.server.calls.count { it.rpc.startsWith("chess_") }, "화면이 빠졌는데 체스 조회가 나갔다")
        rig.close()
    }

    @Test
    fun backClosesTheRobotScreenFirstAndAsksDuringALiveHumanMatch() = runDesktopComposeUiTest(420, 2600) {
        val rig = BoardGameRig(me = null)
        var leaves = 0
        val state = ChessScreenState()
        setContent { BoardTestTheme { ChessScreen(rig.games, rig.chess, BoardGameMe.unknown, onLeave = { leaves += 1 }, state = state) } }
        settle(rig)
        // 로봇 화면 — 뒤로는 덮개 닫기(판은 남는다). 로그인 없이 연다(세션 없는 호스트).
        onNodeWithTag(ChessScreenTags.robotEntry).performClick()
        waitForIdle()
        onNodeWithTag("chess-robot-white").performClick()
        settle(rig)
        assertTrue(rig.chess.isAIMatch, "로그인 없이 로봇 판이 안 섰다")
        assertEquals(BoardBackStep.CloseOverlay, ChessBackPlan.step(state, rig.chess))
        assertTrue(state.handleBack(rig.chess))
        waitForIdle()
        assertFalse(state.robotScreenOpen)
        assertTrue(rig.chess.isAIMatch, "뒤로가기가 로봇 판을 버렸다")
        assertEquals(BoardBackStep.Leave, ChessBackPlan.step(state, rig.chess), "로봇 판은 확인하지 않는다")
        assertEquals(0, leaves)
        // 사람과의 판(로비 갈래 판정 — 순수 계획).
        assertEquals(BoardBackStep.ConfirmLeave, ChessBackPlan.step(hasOverlay = false, robotScreenOpen = false, hasLiveHumanMatch = true, isSpectating = false))
        assertEquals(BoardBackStep.LeaveWatch, ChessBackPlan.step(hasOverlay = false, robotScreenOpen = false, hasLiveHumanMatch = false, isSpectating = true))
        rig.close()
    }

    @Test
    fun duelsFlagOffHidesChallengeAndAcceptButKeepsRobotRankingAndWatch() {
        val off = lobbyEntries(duelsEnabled = false)
        assertEquals(0, off.first, "깃발이 꺼졌는데 [도전]이 섰다")
        assertEquals(0, off.second, "깃발이 꺼졌는데 [수락]이 섰다")
        assertTrue(off.third, "깃발이 꺼졌는데 받은 신청 접힌 한 줄이 없다")
        val on = lobbyEntries(duelsEnabled = true)
        assertTrue(on.first > 0, "깃발이 켜졌는데 [도전]이 없다 — 위 0 이 빈 단언이 된다")
        assertTrue(on.second > 0, "깃발이 켜졌는데 [수락]이 없다")
        assertFalse(on.third)
    }

    private fun lobbyEntries(duelsEnabled: Boolean): Triple<Int, Int, Boolean> {
        var out: Triple<Int, Int, Boolean>? = null
        runDesktopComposeUiTest(420, 3200) {
            val rig = BoardGameRig(me = null, duelsEnabled = duelsEnabled)
            seedChessLobby(rig)
            setContent { BoardTestTheme { ChessScreen(rig.games, rig.chess, BoardGameMe.unknown, onLeave = {}) } }
            waitForIdle()
            onNodeWithTag(ChessScreenTags.robotEntry).assertExists()
            assertTrue(onAllNodesWithTag("chess-ranking").fetchSemanticsNodes().isNotEmpty(), "순위 절이 없다")
            assertTrue(onAllNodesWithTag(ChessScreenTags.watch(SEED_LIVE)).fetchSemanticsNodes().isNotEmpty(), "관전 입구가 없다")
            val challenge = SEED_CHESS_USERS.count { onAllNodesWithTag(ChessScreenTags.challenge(it.id)).fetchSemanticsNodes().isNotEmpty() }
            val accept = onAllNodesWithTag(ChessScreenTags.accept(SEED_INVITE)).fetchSemanticsNodes().size
            val folded = onAllNodesWithTag(ChessScreenTags.incomingNotice).fetchSemanticsNodes().isNotEmpty()
            out = Triple(challenge, accept, folded)
            rig.close()
        }
        return requireNotNull(out)
    }

    @Test
    fun lobbyReadsOnlyTheBlockFilteredRosterFromTheGamesStore() = runDesktopComposeUiTest(420, 3200) {
        val rig = BoardGameRig(me = null)
        seedChessLobby(rig)
        val blocked = SEED_CHESS_USERS[0]
        rig.hiddenBlocked = setOf(blocked.id)
        setContent { BoardTestTheme { ChessScreen(rig.games, rig.chess, BoardGameMe.unknown, onLeave = {}) } }
        waitForIdle()
        assertTrue(rig.chess.visibleUsers.any { it.id == blocked.id })
        onNodeWithTag(ChessScreenTags.challenge(blocked.id)).assertDoesNotExist()
        onNodeWithTag(ChessScreenTags.challenge(SEED_CHESS_USERS[1].id)).assertExists()
        onNodeWithText("${SEED_CHESS_USERS.size - 1}명", useUnmergedTree = true).assertExists()
        rig.hiddenBlocked = emptySet()
        waitForIdle()
        onNodeWithTag(ChessScreenTags.challenge(blocked.id)).assertExists()
        rig.close()
    }

    companion object {
        const val SEED_INVITE = "33333333-0000-4000-8000-0000000000c1"
        const val SEED_LIVE = "44444444-0000-4000-8000-0000000000d2"
        val SEED_CHESS_USERS = listOf(
            ChessUser("bbbbbbbb-0000-4000-8000-000000000001", "체스솜", null, "fox", isWorking = true, isCapable = true, inMatch = false, center = "서울"),
            ChessUser("bbbbbbbb-0000-4000-8000-000000000002", "체스구름", null, null, isWorking = false, isCapable = true, inMatch = false),
            ChessUser("bbbbbbbb-0000-4000-8000-000000000003", "체스달", null, "shiba", isWorking = true, isCapable = false, inMatch = false),
        )

        fun seedChessLobby(rig: BoardGameRig) {
            val c = rig.chess
            c.users = SEED_CHESS_USERS
            c.hasLoadedLobby = true
            c.record = ChessRecord(4, 1, 2)
            c.spectatorFeaturesEnabled = true
            c.incoming = ChessInvite(SEED_INVITE, SEED_CHESS_USERS[1], 5, boardClock.addingTimeInterval(42.0))
            c.liveMatches = listOf(ChessLiveMatch(SEED_LIVE, SEED_CHESS_USERS[0], SEED_CHESS_USERS[2], ChessStake.ten, boardClock.addingTimeInterval(-95.0), watchers = 2))
            c.ranking = com.yehsung.aingcheck.core.stores.chess.ChessRankingBoard(
                entries = listOf(
                    com.yehsung.aingcheck.core.stores.chess.ChessRankEntry(SEED_CHESS_USERS[0].id, 1, SEED_CHESS_USERS[0], 4, 1, 2, 3),
                    com.yehsung.aingcheck.core.stores.chess.ChessRankEntry(SEED_CHESS_USERS[1].id, 2, SEED_CHESS_USERS[1], 1, 1, 0, 0),
                ),
                me = null, recordSince = null,
            )
            c.hasLoadedRanking = true
        }
    }
}
