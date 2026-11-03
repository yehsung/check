// 원본: Tests/CheckMobileKitTests/GamesReversiLobbyTests.swift · GamesReversiMatchTests.swift(요청 본문·건수 · 기준선 짝) @ ios-1017-int 3e5051ed · 467aec40
//
// 아잉 뒤집기(판 7) 화면을 **화면으로** 몬다 — 단추를 누르면 요청이 몇 건, 어떤 본문으로 나가는가(모양이 아니라 결과를 잰다). 서버는 RpcStub(픽스처 원문 ·
// 손으로 짠 서버 모양)이고 스토어 일은 가상 시간에서 돈다(settle). 시험마다 결과가 갈리는 기준선(누르기 전 0건 · 깃발 끔 · 고르기 전 비활성)을 같이 잰다.
package com.yehsung.aingcheck.ui.games.reversi

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.DesktopComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.click
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.core.rules.reversi.ReversiPoint
import com.yehsung.aingcheck.core.rules.reversi.ReversiRules
import com.yehsung.aingcheck.core.stores.games.GamesDestination
import com.yehsung.aingcheck.core.stores.reversi.ReversiPhase
import com.yehsung.aingcheck.core.stores.reversi.ReversiPhoneText
import com.yehsung.aingcheck.core.stores.reversi.isAIMatch
import com.yehsung.aingcheck.core.stores.reversi.startAIMatch
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.ui.games.gomoku.BoardBackStep
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameRig
import com.yehsung.aingcheck.ui.games.gomoku.BoardTestTheme
import com.yehsung.aingcheck.ui.games.gomoku.fixtureText
import com.yehsung.aingcheck.ui.games.minigame.MiniGameArt
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubBoardFactsSnapshot
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubScreen
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubTags
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class)
class ReversiScreenFlowTest {
    private companion object {
        const val FIXTURES = "Tests/checkTests/Fixtures/reversi-rpc"
    }

    private fun DesktopComposeUiTest.settle(rig: BoardGameRig) {
        waitForIdle()
        rig.settle()
        waitForIdle()
    }

    /** 로비·순위를 늘 같은 서버 모양으로 답하는 묶음(화면 열기의 조회가 실패 안내를 세우지 않게). */
    private fun lobbyRig(
        me: String? = ReversiHand.ME,
        duels: Boolean = true,
        lobbyText: String = ReversiHand.lobbyJson(),
        configure: com.yehsung.aingcheck.ui.games.gomoku.RpcStub.() -> Unit = {},
    ) =
        BoardGameRig(me = me, duelsEnabled = duels, withReversi = true) {
            respondWith("reversi_lobby") { _, _ -> lobbyText }
            respondWith("reversi_ranking") { _, _ -> ReversiHand.rankingJson() }
            configure()
        }

    // MARK: 입구 — 떼어 내기 깃발

    /** 허브 카드: 스토어가 있으면 서고 눌러 아잉 뒤집기로 간다. 깃발을 끈 조립(스토어 없음)은 카드도, 화면도 없다 — 같은 허브에서 다른 카드는 그대로다. */
    @Test
    fun hubCardStandsOnlyWhenTheFlagLeavesAStore() = runDesktopComposeUiTest(420, 2600) {
        val on = BoardGameRig(withReversi = true)
        val off = BoardGameRig(withReversi = false)
        var games by mutableStateOf(on.games)
        val opened = mutableListOf<GamesDestination>()
        setContent { BoardTestTheme { GamesHubScreen(games, GamesHubBoardFactsSnapshot(), MiniGameArt.empty, { SwiftDate(1_900_000_000.0) }, { opened += it }, {}, {}) } }
        waitForIdle()
        onNodeWithTag(GamesHubTags.REVERSI).performScrollTo().performClick()
        assertEquals(listOf<GamesDestination>(GamesDestination.Reversi), opened)
        onNodeWithText(ReversiPhoneText.idleLine, useUnmergedTree = true).assertExists()
        games = off.games
        waitForIdle()
        onNodeWithTag(GamesHubTags.CHESS).assertExists()
        onNodeWithTag(GamesHubTags.REVERSI).assertDoesNotExist()
        on.close()
        off.close()
    }

    /** 깃발을 끈 조립에서 목적지에 닿아도(옛 딥링크 · 경합) 화면은 빈 판을 그리지 않고 곧바로 물러난다. 켠 조립은 물러나지 않는다(기준선). */
    @Test
    fun screenWithoutAStoreLeavesAtOnce() = runDesktopComposeUiTest(420, 1200) {
        val off = BoardGameRig(withReversi = false)
        val on = lobbyRig(me = null)
        var leftOff = 0
        var leftOn = 0
        var showOff by mutableStateOf(true)
        setContent {
            BoardTestTheme {
                if (showOff) ReversiScreen(off.games, BoardGameMe.unknown, onLeave = { leftOff += 1 }) else ReversiScreen(on.games, BoardGameMe.unknown, onLeave = { leftOn += 1 })
            }
        }
        waitForIdle()
        assertEquals(1, leftOff)
        onNodeWithTag(ReversiScreenTags.screen).assertDoesNotExist()
        showOff = false
        waitForIdle()
        onNodeWithTag(ReversiScreenTags.screen).assertExists()
        assertEquals(0, leftOn)
        off.close()
        on.close()
    }

    // MARK: 로비 — 신청 · 받기

    /** [도전] → 판돈 시트(고르기 전엔 비활성 · 요청 0건) → 5 → [5 걸고 도전하기] → reversi_challenge 한 건(p_stake 5 · 그 사람). */
    @Test
    fun challengeGoesOutOnlyThroughTheStakeSheetWithTheChosenStake() = runDesktopComposeUiTest(420, 2600) {
        val target = ReversiHand.users[0].first
        val rig = lobbyRig { respondWith("reversi_challenge") { _, _ -> fixtureText(FIXTURES, "reversi_challenge__ok") } }
        val reversi = requireNotNull(rig.reversi)
        reversi.applyLobby(ReversiHand.lobby(ReversiHand.lobbyJson()))
        rig.games.appDidBecomeActive()
        setContent { BoardTestTheme { ReversiScreen(rig.games, BoardGameMe.unknown, onLeave = {}) } }
        settle(rig)
        // 막힌 상대(대결 중 · 옛 버전 · 집중)는 [도전]이 비활성이다 — 신청 0건.
        onNodeWithTag(ReversiScreenTags.challenge(ReversiHand.users[3].first)).performScrollTo().assertIsNotEnabled()
        onNodeWithText("업데이트 필요", useUnmergedTree = true).assertExists()
        onNodeWithTag(ReversiScreenTags.challenge(target)).performScrollTo().performClick()
        settle(rig)
        onNodeWithTag(ReversiScreenTags.stakeSheet).assertExists()
        onNodeWithTag(ReversiScreenTags.stakeSend).assertIsNotEnabled()
        onNodeWithTag(ReversiScreenTags.stakeSend).performClick()
        settle(rig)
        assertEquals(0, rig.server.count("reversi_challenge"), "판돈을 고르기 전에 신청이 나갔다")
        onNodeWithTag(ReversiScreenTags.stakeOption(5)).performClick()
        waitForIdle()
        onNodeWithText(ReversiPhoneText.challengeWithStake(5), useUnmergedTree = true).assertExists()
        onNodeWithTag(ReversiScreenTags.stakeSend).performClick()
        settle(rig)
        assertEquals(1, rig.server.count("reversi_challenge"))
        val body = rig.server.last("reversi_challenge")
        assertEquals(5L, body.long("p_stake"))
        assertEquals(target, body.str("p_opponent"))
        onNodeWithTag(ReversiScreenTags.stakeSheet).assertDoesNotExist()
        assertNotNull(reversi.outgoing, "보낸 신청 줄이 서야 한다")
        rig.close()
    }

    /** 판돈 깃발(§8-17 #1)이 꺼진 빌드: [도전] 단추가 없고 받은 신청은 접힌 한 줄이다 — 신청·수락 요청 0건. */
    @Test
    fun duelsFlagOffHidesChallengeAndFoldsInvites() = runDesktopComposeUiTest(420, 2600) {
        val rig = lobbyRig(duels = false)
        val reversi = requireNotNull(rig.reversi)
        reversi.applyLobby(ReversiHand.lobby(ReversiHand.lobbyJson()))
        setContent { BoardTestTheme { ReversiScreen(rig.games, BoardGameMe.unknown, onLeave = {}) } }
        settle(rig)
        onNodeWithTag(ReversiScreenTags.challenge(ReversiHand.users[0].first)).assertDoesNotExist()
        onNodeWithTag(ReversiScreenTags.accept(ReversiHand.INVITE_A)).assertDoesNotExist()
        onNodeWithTag(ReversiScreenTags.incomingNotice).assertExists()
        // AI 연습은 그대로 열린다.
        onNodeWithTag(ReversiScreenTags.aiEntry).performScrollTo().assertExists()
        assertEquals(0, rig.server.count("reversi_challenge") + rig.server.count("reversi_respond"))
        rig.close()
    }

    /** 받은 신청 카드: [거절] → p_accept false 한 건 · [수락] → p_accept true 한 건(받은 신청 둘 — 각자 자기 id). */
    @Test
    fun inviteCardsAnswerTheirOwnInvite() = runDesktopComposeUiTest(420, 2600) {
        val rig = lobbyRig {
            respondWith("reversi_respond") { body, _ ->
                if (body["p_accept"]?.jsonPrimitive?.content == "true") fixtureText(FIXTURES, "reversi_respond__accepted") else fixtureText(FIXTURES, "reversi_respond__declined")
            }
        }
        val reversi = requireNotNull(rig.reversi)
        reversi.applyLobby(ReversiHand.lobby(ReversiHand.lobbyJson()))
        setContent { BoardTestTheme { ReversiScreen(rig.games, BoardGameMe.unknown, onLeave = {}) } }
        settle(rig)
        assertEquals(2, reversi.visibleIncomingInvites.size)
        onNodeWithTag(ReversiScreenTags.decline(ReversiHand.INVITE_B)).performClick()
        settle(rig)
        assertEquals(1, rig.server.count("reversi_respond"))
        assertEquals(ReversiHand.INVITE_B, rig.server.last("reversi_respond").str("p_match_id"))
        assertEquals("false", rig.server.last("reversi_respond").body["p_accept"]?.jsonPrimitive?.content)
        onNodeWithTag(ReversiScreenTags.accept(ReversiHand.INVITE_A)).performClick()
        settle(rig)
        assertEquals(2, rig.server.count("reversi_respond"))
        assertEquals(ReversiHand.INVITE_A, rig.server.last("reversi_respond").str("p_match_id"))
        assertEquals("true", rig.server.last("reversi_respond").body["p_accept"]?.jsonPrimitive?.content)
        assertNotNull(reversi.match, "수락 응답의 판이 서야 한다")
        rig.close()
    }

    /** 로봇 판을 두는 중에 온 신청: 판 위 띠의 [수락]은 **먼저 묻는다**(요청 0건) → [끝내고 수락] 에서 한 건. [그냥 두기]는 0건(기준선). */
    @Test
    fun acceptDuringRobotMatchAsksFirst() = runDesktopComposeUiTest(420, 1600) {
        val rig = lobbyRig { respondWith("reversi_respond") { _, _ -> fixtureText(FIXTURES, "reversi_respond__accepted") } }
        val reversi = requireNotNull(rig.reversi)
        reversi.applyLobby(ReversiHand.lobby(ReversiHand.lobbyJson()))
        reversi.startAIMatch(ReversiColor.black)
        setContent { BoardTestTheme { ReversiScreen(rig.games, BoardGameMe.unknown, onLeave = {}) } }
        settle(rig)
        onNodeWithTag(ReversiScreenTags.banner).assertExists()
        onNodeWithTag(ReversiScreenTags.accept(ReversiHand.INVITE_A)).performClick()
        settle(rig)
        onNodeWithTag(ReversiScreenTags.robotConfirm).assertExists()
        assertEquals(0, rig.server.count("reversi_respond"), "묻기 전에 수락이 나갔다")
        onNodeWithTag("${ReversiScreenTags.robotConfirm}-cancel").performClick()
        settle(rig)
        assertEquals(0, rig.server.count("reversi_respond"))
        assertTrue(reversi.isAIMatch, "[그냥 두기] 뒤에도 로봇 판은 남는다")
        onNodeWithTag(ReversiScreenTags.accept(ReversiHand.INVITE_A)).performClick()
        settle(rig)
        onNodeWithTag("${ReversiScreenTags.robotConfirm}-confirm").performClick()
        settle(rig)
        assertEquals(1, rig.server.count("reversi_respond"))
        assertFalse(reversi.isAIMatch, "1:1 판이 서면 로봇 판은 버려진다")
        rig.close()
    }

    // MARK: 판 — 한 칸 탭 · TalkBack 칸

    /** 판의 둘 수 있는 칸을 한 번 누르면 reversi_move 한 건(p_idx 그 칸 · p_expected_seq 지금 수 번호). 둘 수 없는 칸은 요청 0건 + 코어 문구. */
    @Test
    fun oneTapOnALegalCellPlacesTheStone() = runDesktopComposeUiTest(420, 1200) {
        val rig = lobbyRig { respondWith("reversi_move") { _, _ -> fixtureText(FIXTURES, "reversi_move__ok") } }
        val reversi = requireNotNull(rig.reversi)
        val played = ReversiHand.play(listOf(0, 1, 2, 0, 1, 3, 2, 1, 0, 2))
        reversi.applyState(ReversiHand.state(ReversiHand.stateJson(played)))
        setContent { BoardTestTheme { ReversiScreen(rig.games, BoardGameMe("나검정", "fox", com.yehsung.aingcheck.ui.components.CharacterMood.Working), onLeave = {}) } }
        settle(rig)
        onNodeWithTag(ReversiScreenTags.match).assertExists()
        val legal = ReversiRules.legalMoves(played.board, ReversiColor.black)
        val illegal = (0 until 64).first { it !in legal && played.board[it] != null }
        fun tap(idx: Int) {
            onNodeWithTag(ReversiScreenTags.board).performTouchInput {
                val cell = width / 8f
                click(Offset((idx % 8) * cell + cell / 2, (idx / 8) * cell + cell / 2))
            }
            settle(rig)
        }
        tap(illegal)
        assertEquals(0, rig.server.count("reversi_move"), "둘 수 없는 칸이 요청을 냈다")
        assertEquals(ReversiNoticeTextProbe.occupied, reversi.notice)
        tap(legal.first())
        assertEquals(1, rig.server.count("reversi_move"))
        assertEquals(legal.first().toLong(), rig.server.last("reversi_move").long("p_idx"))
        assertEquals(played.moveCount.toLong(), rig.server.last("reversi_move").long("p_expected_seq"))
        rig.close()
    }

    /** TalkBack: 칸마다 "d3, 빈칸, 둘 수 있어요" 같은 읽기 · 두 번 탭(클릭 동작)이 곧 착수다. 끝난 판의 칸에는 클릭 동작이 없다(기준선). */
    @Test
    fun talkBackCellsReadTheirNameAndPlaceOnActivate() = runDesktopComposeUiTest(420, 1200) {
        val rig = lobbyRig { respondWith("reversi_move") { _, _ -> fixtureText(FIXTURES, "reversi_move__ok") } }
        val reversi = requireNotNull(rig.reversi)
        val start = ReversiHand.Played(com.yehsung.aingcheck.core.wire.games.ReversiBoard.start, emptyList(), ReversiColor.black, 0)
        reversi.applyState(ReversiHand.state(ReversiHand.stateJson(start)))
        setContent { BoardTestTheme { ReversiScreen(rig.games, BoardGameMe.unknown, onLeave = {}) } }
        settle(rig)
        val d3 = requireNotNull(ReversiPoint.fromCoord("d3")).idx
        fun description(idx: Int): String? =
            onNodeWithTag(ReversiScreenTags.cell(idx), useUnmergedTree = true).fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString()
        assertEquals("d3, 빈칸, 둘 수 있어요", description(d3))
        assertEquals("d4, 백 돌", description(27))
        assertEquals("a1, 빈칸", description(0))
        onNodeWithTag(ReversiScreenTags.board).assertExists()
        assertEquals("아잉 뒤집기 판, 흑 2 · 백 2 · 빈칸 60, 흑 차례, 둘 수 있는 칸 4곳",
            onNodeWithTag(ReversiScreenTags.board).fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString())
        onNodeWithTag(ReversiScreenTags.cell(d3), useUnmergedTree = true).performSemanticsAction(SemanticsActions.OnClick)
        settle(rig)
        assertEquals(1, rig.server.count("reversi_move"))
        assertEquals(d3.toLong(), rig.server.last("reversi_move").long("p_idx"))
        rig.close()
    }

    // MARK: 로봇 연습 · 규칙 · 결과

    /** [로봇과 연습하기] → 돌 색 시트 → [백] → 로봇 판(서버 0건 · 사람은 백). 시트를 닫으면 판이 안 선다(기준선). */
    @Test
    fun robotPracticeStartsFromTheColorSheetWithoutTheServer() = runDesktopComposeUiTest(420, 2600) {
        val rig = lobbyRig()
        val reversi = requireNotNull(rig.reversi)
        reversi.applyLobby(ReversiHand.lobby(ReversiHand.lobbyJson(incoming = false)))
        setContent { BoardTestTheme { ReversiScreen(rig.games, BoardGameMe.unknown, onLeave = {}) } }
        settle(rig)
        val before = rig.server.calls.size
        onNodeWithTag(ReversiScreenTags.aiEntry).performScrollTo().performClick()
        waitForIdle()
        onNodeWithTag(ReversiScreenTags.aiColorSheet).assertExists()
        onNodeWithText(ReversiPhoneText.aiPromptTitle, useUnmergedTree = true).assertExists()
        onNodeWithTag(ReversiScreenTags.aiColor("white")).performClick()
        waitForIdle()
        onNodeWithTag(ReversiScreenTags.aiColorSheet).assertDoesNotExist()
        assertTrue(reversi.isAIMatch)
        assertEquals(ReversiColor.white, reversi.match?.myColor)
        assertEquals(ReversiPhase.playing, reversi.phase)
        onNodeWithTag(ReversiScreenTags.match).assertExists()
        onNodeWithText(ReversiPhoneText.aiStakeChip, useUnmergedTree = true).assertExists()
        assertEquals(0, rig.server.calls.drop(before).count { it.rpc == "reversi_move" || it.rpc == "reversi_challenge" }, "로봇 판이 서버를 탔다")
        rig.close()
    }

    /** 규칙 책 → 규칙 시트(열 줄 · 마지막 줄 "리버시와 같은 규칙이에요" · 숫자는 로비 응답 값). 로비와 판 화면 둘 다에서 열린다. */
    @Test
    fun rulesSheetOpensFromTheBookAndSaysItIsTheSameAsReversi() = runDesktopComposeUiTest(420, 2000) {
        // 화면 열기의 로비 조회도 같은 값을 말한다(서버가 바꾼 날의 모양).
        val lobby25 = ReversiHand.lobbyJson().replace("\"turn_seconds\":30", "\"turn_seconds\":25")
        val rig = lobbyRig(lobbyText = lobby25)
        val reversi = requireNotNull(rig.reversi)
        reversi.applyLobby(ReversiHand.lobby(lobby25))
        setContent { BoardTestTheme { ReversiScreen(rig.games, BoardGameMe.unknown, onLeave = {}) } }
        settle(rig)
        onNodeWithTag(ReversiScreenTags.rulesSheet).assertDoesNotExist()
        onNodeWithTag(ReversiScreenTags.rules).performClick()
        waitForIdle()
        onNodeWithTag(ReversiScreenTags.rulesSheet).assertExists()
        onNodeWithText("리버시와 같은 규칙이에요. 리버시를 알면 따로 배울 것이 없어요.", useUnmergedTree = true).assertExists()
        onNodeWithText("한 수에 25초", substring = true, useUnmergedTree = true).assertExists()
        rig.close()
    }

    /**
     * 판 7 검토 S-F3 · U-F1(아이폰 33727592 이식): 로비에서 규칙 시트를 읽는 사이 신청이 수락돼 **새 판이 서면** 시트를 접는다 — 흑이면 곧바로 내 30초가 돈다.
     * 기준선: 판 중에 책 단추로 연 시트는 다음 수가 와도(같은 판 id) 그대로다.
     */
    @Test
    fun rulesSheetFoldsWhenANewMatchStandsButStaysForTheSameMatch() = runDesktopComposeUiTest(420, 1600) {
        val rig = lobbyRig()
        val reversi = requireNotNull(rig.reversi)
        reversi.applyLobby(ReversiHand.lobby(ReversiHand.lobbyJson()))
        setContent { BoardTestTheme { ReversiScreen(rig.games, BoardGameMe.unknown, onLeave = {}) } }
        settle(rig)
        onNodeWithTag(ReversiScreenTags.rules).performClick()
        waitForIdle()
        onNodeWithTag(ReversiScreenTags.rulesSheet).assertExists()
        // 수락됐다 — 판이 선다(나는 흑 · 내 차례).
        val opening = ReversiHand.play(listOf(0, 1))
        reversi.applyState(ReversiHand.state(ReversiHand.stateJson(opening)))
        settle(rig)
        onNodeWithTag(ReversiScreenTags.match).assertExists()
        assertFalse(reversi.isRulesVisible, "새 판이 섰는데 규칙 시트가 판을 덮은 채 남았다")
        onNodeWithTag(ReversiScreenTags.rulesSheet).assertDoesNotExist()
        // 기준선: 판 중에 연 규칙은 다음 수가 와도 그대로 읽는다.
        onNodeWithTag(ReversiScreenTags.rules).performClick()
        waitForIdle()
        reversi.applyState(ReversiHand.state(ReversiHand.stateJson(ReversiHand.play(listOf(0, 1, 2, 0)))))
        settle(rig)
        assertTrue(reversi.isRulesVisible, "같은 판의 다음 수가 규칙 시트를 접었다")
        onNodeWithTag(ReversiScreenTags.rulesSheet).assertExists()
        rig.close()
    }

    /** 판 7 검토 U-F3: 뒤로가기 '대국 화면을 나갈까요?'를 띄운 채 판이 끝나면(상대 기권) 확인을 접어 결과 카드가 보인다. 기준선: 진행 중이면 확인은 그대로다. */
    @Test
    fun leaveConfirmFoldsWhenTheMatchFinishes() = runDesktopComposeUiTest(420, 1600) {
        val rig = lobbyRig()
        val reversi = requireNotNull(rig.reversi)
        val played = ReversiHand.play(listOf(0, 1, 2, 0))
        reversi.applyState(ReversiHand.state(ReversiHand.stateJson(played)))
        val state = ReversiScreenState()
        setContent { BoardTestTheme { ReversiScreen(rig.games, BoardGameMe.unknown, onLeave = {}, state = state) } }
        settle(rig)
        assertTrue(state.handleBack(reversi), "사람 판의 뒤로가기는 확인을 띄운다")
        waitForIdle()
        onNodeWithTag(ReversiScreenTags.leaveConfirm).assertExists()
        // 기준선: 다음 수(진행 중)는 확인을 접지 않는다.
        reversi.applyState(ReversiHand.state(ReversiHand.stateJson(ReversiHand.play(listOf(0, 1, 2, 0, 1)))))
        settle(rig)
        assertTrue(state.confirmingLeave)
        // 상대 기권 — 내가 이겼다.
        reversi.applyState(ReversiHand.state(ReversiHand.stateJson(ReversiHand.play(listOf(0, 1, 2, 0, 1)), finished = true, result = "black_win", endReason = "resign")))
        settle(rig)
        assertFalse(state.confirmingLeave, "끝난 판 위에 나가기 확인이 남았다")
        onNodeWithTag(ReversiScreenTags.leaveConfirm).assertDoesNotExist()
        onNodeWithTag(ReversiScreenTags.result).assertExists()
        rig.close()
    }

    /** 결과 화면: [로비로]가 끝난 판을 접는다. 기권 확인은 덮개를 지난다 — [기권] 한 번으로는 요청 0건, [기권하기] 에서 한 건. */
    @Test
    fun resignAsksThenSendsAndResultFoldsBackToTheLobby() = runDesktopComposeUiTest(420, 1200) {
        val rig = lobbyRig { respondWith("reversi_resign") { _, _ -> fixtureText(FIXTURES, "reversi_resign__ok") } }
        val reversi = requireNotNull(rig.reversi)
        reversi.applyState(ReversiHand.state(ReversiHand.stateJson(ReversiHand.play(listOf(0, 1, 2, 0)))))
        val state = ReversiScreenState()
        setContent { BoardTestTheme { ReversiScreen(rig.games, BoardGameMe.unknown, onLeave = {}, state = state) } }
        settle(rig)
        state.shownAt = null // 막 열린 판의 누름 가드(1초)를 지난 것으로
        onNodeWithTag(ReversiScreenTags.resign).performClick()
        settle(rig)
        onNodeWithTag(ReversiScreenTags.resignConfirm).assertExists()
        assertEquals(0, rig.server.count("reversi_resign"))
        onNodeWithTag("${ReversiScreenTags.resignConfirm}-confirm").performClick()
        settle(rig)
        assertEquals(1, rig.server.count("reversi_resign"))
        // 끝난 판(손으로 짠 결과)을 세우고 [로비로].
        reversi.applyState(ReversiHand.state(ReversiHand.stateJson(ReversiHand.play(listOf(0, 1, 2, 0)), finished = true, result = "white_win", endReason = "resign")))
        settle(rig)
        onNodeWithTag(ReversiScreenTags.result).assertExists()
        onNodeWithText("졌어요", useUnmergedTree = true).assertExists()
        onNodeWithTag(ReversiScreenTags.backToLobby).performClick()
        settle(rig)
        assertNull(reversi.match)
        assertEquals(ReversiPhase.lobby, reversi.phase)
        onNodeWithTag(ReversiScreenTags.lobby).assertExists()
        rig.close()
    }

    // MARK: 탭 막대 · 뒤로가기

    /** 판(1:1 · 로봇)이면 탭 막대를 숨기고 로비면 보인다. 뒤로가기: 사람 판은 확인 · 로봇 판은 바로 떠남 · 관전은 관전만 나간다. */
    @Test
    fun tabBarAndBackFollowTheMatchKind() = runDesktopComposeUiTest(420, 1200) {
        val rig = lobbyRig()
        val reversi = requireNotNull(rig.reversi)
        var hidden: Boolean? = null
        setContent { BoardTestTheme { ReversiScreen(rig.games, BoardGameMe.unknown, onLeave = {}, onTabBarHidden = { hidden = it }) } }
        settle(rig)
        assertEquals(false, hidden)
        reversi.applyState(ReversiHand.state(ReversiHand.stateJson(ReversiHand.play(listOf(0, 1)))))
        settle(rig)
        assertEquals(true, hidden)
        val state = ReversiScreenState()
        assertEquals(BoardBackStep.ConfirmLeave, ReversiBackPlan.step(state, reversi))
        state.confirmsResign = true
        assertEquals(BoardBackStep.CloseOverlay, ReversiBackPlan.step(state, reversi))
        assertEquals(BoardBackStep.Leave, ReversiBackPlan.step(hasOverlay = false, hasLiveHumanMatch = false, isSpectating = false))
        assertEquals(BoardBackStep.LeaveWatch, ReversiBackPlan.step(hasOverlay = false, hasLiveHumanMatch = false, isSpectating = true))
        assertTrue(ReversiTabBarPolicy.hidesTabBar(ReversiPhase.result, hasMatch = true))
        assertFalse(ReversiTabBarPolicy.hidesTabBar(ReversiPhase.playing, hasMatch = false), "판이 없으면 로비가 선다")
        rig.close()
    }
}

/** 코어 문구 한 줄(시험이 글자를 베끼지 않게). */
private object ReversiNoticeTextProbe {
    val occupied: String get() = com.yehsung.aingcheck.core.stores.reversi.ReversiNoticeText.occupied
}
