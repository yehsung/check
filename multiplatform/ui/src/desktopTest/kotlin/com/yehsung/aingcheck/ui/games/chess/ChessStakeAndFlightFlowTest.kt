// 원본: 없음 — W4-a 7차 검증 지적(w4-a.verdict.json)의 화면 시험(체스). 스토어 시험이 잰 판정을 다시 재지 않고 **화면이 그 문에 닿는가**를 잰다.
//
//  ① 판돈 신청 경로: [도전] → 판돈 시트 → 3/5/10 고르기 → 보내기 = chess_challenge 본문 p_stake · p_opponent · 잔액이 모자란 칸은 비활성.
//  ② §8-17 #1 깃발: 꺼진 빌드는 판돈 시트가 서도 보내기가 서지 않는다(`GamesChessStakeSend.sendable` 의 깃발 — V8). 스토어도 짝으로 막으므로
//     나간 RPC 수만으로는 화면 문이 안 잰다 — **단추의 활성**을 잰다.
//  ③ INV-ChessStore-635cb077 · 221d2393(화면 몫): 날던 수는 앱이 배경으로 가는(가림) **순간** 거둔다 — 재조성을 기다리지 않는다(V4).
package com.yehsung.aingcheck.ui.games.chess

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.DesktopComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.click
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.stores.chess.ChessStake
import com.yehsung.aingcheck.core.wire.games.ChessStatePayload
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameRig
import com.yehsung.aingcheck.ui.games.gomoku.BoardTestTheme
import com.yehsung.aingcheck.ui.games.gomoku.CHESS_FIXTURES
import com.yehsung.aingcheck.ui.games.gomoku.fixtureJSON
import com.yehsung.aingcheck.ui.games.gomoku.fixtureText
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class)
class ChessStakeAndFlightFlowTest {
    private val playerA: String get() = fixtureJSON(CHESS_FIXTURES, "_manifest")["users"]!!.jsonObject["A"]!!.jsonPrimitive.content
    private val target = ChessScreenFlowTest.SEED_CHESS_USERS[0]

    private fun DesktopComposeUiTest.settle(rig: BoardGameRig) {
        waitForIdle()
        rig.settle()
        waitForIdle()
    }

    /** 로비(시드) + 잔액 [ruby] — 공유 미러와 스토어 미러 둘 다(시트는 공유 미러, 스토어 사전 검사는 제 미러를 읽는다). */
    private fun lobbyRig(duelsEnabled: Boolean, ruby: Int): BoardGameRig =
        BoardGameRig(me = playerA, duelsEnabled = duelsEnabled) { queueFixtures("chess_challenge", CHESS_FIXTURES, "chess_challenge__ok") }.also {
            ChessScreenFlowTest.seedChessLobby(it)
            it.sharedRuby = ruby
            it.host.rubyBalance = ruby.toLong()
        }

    // MARK: ① 판돈 신청 경로

    @Test
    fun stakeSheetSendsTheChosenStakeAndDimsWhatTheBalanceCannotPay() = runDesktopComposeUiTest(420, 3200) {
        val rig = lobbyRig(duelsEnabled = true, ruby = 7)
        setContent { BoardTestTheme { ChessScreen(rig.games, rig.chess, BoardGameMe.unknown, onLeave = {}) } }
        waitForIdle()
        onNodeWithTag(ChessScreenTags.challenge(target.id)).performClick()
        waitForIdle()
        onNodeWithTag(ChessScreenTags.stakeSheet).assertExists()
        // 아무것도 안 골라진 채 열린다 — 보내기는 서지 않는다.
        onNodeWithTag(ChessScreenTags.stakeSend).assertIsNotEnabled()
        // 잔액 7: 3·5 는 고를 수 있고 10 은 비활성(같은 시트에서 칸마다 갈린다 — 기준선이 안에 있다).
        onNodeWithTag(ChessScreenTags.stakeOption(3)).assertIsEnabled()
        onNodeWithTag(ChessScreenTags.stakeOption(5)).assertIsEnabled()
        onNodeWithTag(ChessScreenTags.stakeOption(10)).assertIsNotEnabled()
        onNodeWithTag(ChessScreenTags.stakeOption(5)).performClick()
        waitForIdle()
        onNodeWithTag(ChessScreenTags.stakeSend).assertIsEnabled()
        assertEquals(0, rig.server.count("chess_challenge"), "고르기만 했는데 신청이 나갔다")
        onNodeWithTag(ChessScreenTags.stakeSend).performClick()
        settle(rig)
        assertEquals(1, rig.server.count("chess_challenge"))
        val body = rig.server.last("chess_challenge")
        assertEquals(5L, body.long("p_stake"), "고른 판돈(5)이 아닌 값이 나갔다")
        assertEquals(target.id, body.str("p_opponent"))
        assertEquals(ChessStake.five, rig.chess.selectedStake, "결과의 [다시 신청]이 쓸 판돈이 고른 값이 아니다")
        onNodeWithTag(ChessScreenTags.stakeSheet).assertDoesNotExist()
        rig.close()
    }

    // MARK: ② §8-17 #1 깃발 — 판돈 시트의 보내기 문

    /** 판돈 시트를 (어떤 길로든 — 꺼진 빌드엔 [도전]이 없다) 띄운 채 5 를 고르고 보내기를 누른다 — (보내기 활성, 나간 신청 수). */
    private fun stakeSendWith(duelsEnabled: Boolean): Pair<Boolean, Int> {
        var out: Pair<Boolean, Int>? = null
        runDesktopComposeUiTest(420, 3200) {
            val rig = lobbyRig(duelsEnabled = duelsEnabled, ruby = 100)
            val state = ChessScreenState()
            setContent { BoardTestTheme { ChessScreen(rig.games, rig.chess, BoardGameMe.unknown, onLeave = {}, state = state) } }
            waitForIdle()
            state.stakeTarget = target
            waitForIdle()
            onNodeWithTag(ChessScreenTags.stakeOption(5)).performClick()
            waitForIdle()
            val config = onNodeWithTag(ChessScreenTags.stakeSend).fetchSemanticsNode().config
            val enabled = config.contains(SemanticsActions.OnClick) && !config.contains(SemanticsProperties.Disabled)
            onNodeWithTag(ChessScreenTags.stakeSend).performClick()
            settle(rig)
            out = enabled to rig.server.count("chess_challenge")
            rig.close()
        }
        return requireNotNull(out)
    }

    @Test
    fun duelsFlagOffKeepsTheStakeSheetFromSending() {
        val (offEnabled, offSent) = stakeSendWith(duelsEnabled = false)
        assertFalse(offEnabled, "깃발이 꺼졌는데 판돈 시트의 보내기가 섰다")
        assertEquals(0, offSent, "깃발이 꺼졌는데 신청이 나갔다")
        val (onEnabled, onSent) = stakeSendWith(duelsEnabled = true)
        assertTrue(onEnabled, "켜진 빌드에서 보내기가 안 선다 — 위 거짓이 빈 단언이 된다")
        assertEquals(1, onSent)
    }

    /** 판돈 시트를 연 채 다른 기기에서 수락된 판이 선다 — 시트가 대국 위에 남지 않는다(Swift onChange(of: match?.id) · ChessScreenState.matchChanged). */
    @Test
    fun aNewMatchFoldsTheStakeSheet() = runDesktopComposeUiTest(420, 3200) {
        val rig = BoardGameRig(me = "aa000000-0000-4000-8000-0000000000a1")
        ChessScreenFlowTest.seedChessLobby(rig)
        val state = ChessScreenState()
        setContent { BoardTestTheme { ChessScreen(rig.games, rig.chess, BoardGameMe.unknown, onLeave = {}, state = state) } }
        waitForIdle()
        onNodeWithTag(ChessScreenTags.challenge(target.id)).performClick()
        waitForIdle()
        onNodeWithTag(ChessScreenTags.stakeSheet).assertExists()
        rig.chess.applyState(SwiftJson.decode(ChessStatePayload.serializer(), fixtureText(CHESS_FIXTURES, "chess_state__ok_mid_since0")))
        settle(rig)
        onNodeWithTag(ChessScreenTags.match).assertExists()
        assertNull(state.stakeTarget, "판이 섰는데 판돈 대상이 남았다")
        onNodeWithTag(ChessScreenTags.stakeSheet).assertDoesNotExist()
        rig.close()
    }

    // MARK: ③ 날던 수 — 배경(가림) 순간 거둔다

    @Test
    fun aMoveInFlightIsClearedTheMomentTheAppGoesToTheBackground() = runDesktopComposeUiTest(420, 2600) {
        val rig = BoardGameRig(me = playerA) {
            respondWith("chess_lobby") { _, _ -> fixtureText(CHESS_FIXTURES, "chess_lobby__ok_in_match") }
            queueFixtures("chess_state", CHESS_FIXTURES, "chess_state__ok_initial_my_turn")
            queueFixtures("chess_move", CHESS_FIXTURES, "chess_move__ok_white_first")
        }
        rig.games.appDidBecomeActive()
        val state = ChessScreenState()
        setContent { BoardTestTheme { ChessScreen(rig.games, rig.chess, BoardGameMe("나백", "fox", CharacterMood.Working), onLeave = {}, state = state) } }
        settle(rig)
        assertNotNull(rig.chess.match, "로비의 active_match_id 로 판이 안 열렸다")
        fun tap(square: String) {
            onNodeWithTag(ChessScreenTags.board).performTouchInput {
                val c = chessGeometry(width.toFloat(), true).center(ChessSquare.parse(square)!!)
                click(Offset(c.x.toFloat(), c.y.toFloat()))
            }
            waitForIdle()
        }
        tap("e2")
        settle(rig)
        tap("e4")
        // 시계를 멈춘 채 수 응답을 들인다 — 날기가 끝나기 전에 배경으로 보낸다.
        mainClock.autoAdvance = false
        rig.settle()
        mainClock.advanceTimeByFrame()
        assertEquals(1, rig.server.count("chess_move"))
        assertNotNull(state.matchFlight.flight, "첫 수가 날지 않았다 — 아래 null 이 빈 단언이 된다")
        // 배경 = 게임 탭 스토어가 isAppActive 를 내리고 같은 호출에서 체스 창을 가린다(코어 isWindowOccluded 는 관찰 상태가 아니다).
        rig.games.appDidEnterBackground()
        assertTrue(rig.chess.isWindowOccluded)
        mainClock.advanceTimeByFrame()
        assertNull(state.matchFlight.flight, "앱이 배경으로 갔는데 날던 수가 남았다(돌아온 순간 끝나던 토막이 다시 미끄러진다)")
        mainClock.autoAdvance = true
        rig.close()
    }
}
