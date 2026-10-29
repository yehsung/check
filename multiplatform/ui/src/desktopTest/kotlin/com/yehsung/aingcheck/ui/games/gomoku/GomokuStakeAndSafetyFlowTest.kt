// 원본: 없음 — W4-a 7차 검증 지적(w4-a.verdict.json)의 화면 시험(오목). 스토어 시험이 이미 잰 판정을 다시 재지 않고 **화면이 그 문에 닿는가**를 잰다.
//
//  ① 판돈 신청 경로: [도전] → 판돈 시트 → 3/5/10 고르기 → 보내기 = gomoku_challenge 본문 p_stake · p_opponent(V7) · 잔액이 모자란 칸은 비활성.
//  ② §8-17 #1 깃발: 꺼진 빌드는 판돈 시트를 띄워도 보내기가 서지 않는다(V8 짝) · 결과의 [같은 판돈으로 다시 신청]이 꺼짐 0 / 켜짐 1(V1) ·
//     "신청하고 받을 수 있어요" 캡션이 꺼짐 0 / 켜짐 1.
//  ③ 대국 채팅 신고·차단: [차단하기]는 확인 덮개만 열고 확인의 [차단하기]만 block + 음소거 · [신고하기]는 화면 안 덮개(창·폴링이 산다) ·
//     onSent(blocked) 일 때만 음소거.
//  ④ 수가 바뀌면 금수 초점이 지워진다 · 판이 갈리면 판돈 시트가 접힌다(V5) · 겹친 화면 하나가 빠져도 남은 화면의 폴링이 산다.
//  ⑤ iOS 동작 짝: 기권은 머리 ⋯ 메뉴 안 · 당겨서 새로고침(로비 + 받은함) · 보이스오버 힌트 = 누름 이름표 · 햅틱(착수 · 끝남).
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.hapticfeedback.HapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.DesktopComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.click
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.runDesktopComposeUiTest
import androidx.compose.ui.test.swipeDown
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.rules.text.BlockReportPlatform
import com.yehsung.aingcheck.core.rules.text.BlockReportText
import com.yehsung.aingcheck.core.stores.games.GomokuPhoneText
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhase
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneBoardGeometry
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStake
import com.yehsung.aingcheck.core.stores.gomoku.GomokuUser
import com.yehsung.aingcheck.ui.components.CharacterMood
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 햅틱 기록기(LocalHapticFeedback 자리). */
class RecordingHaptics : HapticFeedback {
    val types = mutableListOf<HapticFeedbackType>()
    override fun performHapticFeedback(hapticFeedbackType: HapticFeedbackType) {
        types += hapticFeedbackType
    }
}

/** 신고·차단 문 기록기 — 신고 시트 자리에 두 단추(신고만 · 신고하며 차단)와 ✕ 를 둔 가짜 시트를 넣는다(메시지 탭 시트 W3-a 대역). */
class RecordingSafety {
    val blocked = mutableListOf<String>()
    val reported = mutableListOf<BoardReportTarget>()
    val safety = BoardGameSafety(
        block = { blocked += it },
        reportSheet = { target, onSent, onClose ->
            reported += target
            Column(Modifier.testTag("fake-report-sheet")) {
                Text("신고: ${target.peerName}")
                androidx.compose.material3.Button(onClick = { onSent(false) }, modifier = Modifier.testTag("fake-report-send")) { Text("보내기") }
                androidx.compose.material3.Button(onClick = { onSent(true) }, modifier = Modifier.testTag("fake-report-send-block")) { Text("보내며 차단") }
                androidx.compose.material3.Button(onClick = onClose, modifier = Modifier.testTag("fake-report-close")) { Text("닫기") }
            }
        },
    )
}

@OptIn(ExperimentalTestApi::class)
class GomokuStakeAndSafetyFlowTest {
    private val me = "00000000-0000-4000-8000-0000000000aa"
    private val emptyInbox = """{"status":"ok","incoming":[],"outgoing":null,"ruby_balance":100,"last_finished":null,"server_now_ms":1789547568000,"active_match_id":null}"""

    private fun DesktopComposeUiTest.settle(rig: BoardGameRig) {
        waitForIdle()
        rig.settle()
        waitForIdle()
    }

    private fun DesktopComposeUiTest.tapBoard(point: GomokuPoint) {
        onNodeWithTag(GomokuScreenTags.board).performTouchInput {
            val location = GomokuPhoneBoardGeometry(side = width.toDouble()).location(point)
            click(Offset(location.x.toFloat(), location.y.toFloat()))
        }
        waitForIdle()
    }

    /** 로비가 서버 로비(gomoku_lobby__ok — 수락 가능한 사람 '코덱스토큰도둑예은')를 읽은 화면. 잔액은 공유 미러 [ruby]. */
    private fun lobbyRig(duelsEnabled: Boolean = true, ruby: Long = 7, extra: RpcStub.() -> Unit = {}): BoardGameRig = BoardGameRig(me = me, duelsEnabled = duelsEnabled) {
        respondWith("gomoku_lobby") { _, _ -> fixtureText(GOMOKU_FIXTURES, "gomoku_lobby__ok") }
        respondWith("gomoku_inbox") { _, _ -> emptyInbox }
        extra()
    }.also { it.host.rubyBalance = ruby }

    private val lobbyTarget = "3e240c02-8972-478e-a674-014f498a641b"

    // MARK: ① 판돈 신청 경로

    @Test
    fun stakeSheetSendsTheChosenStakeAndDimsWhatTheBalanceCannotPay() = runDesktopComposeUiTest(420, 2600) {
        val rig = lobbyRig { queueFixtures("gomoku_challenge", GOMOKU_FIXTURES, "gomoku_challenge__ok") }
        setContent { BoardTestTheme { GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = {}) } }
        settle(rig)
        rig.host.rubyBalance = 7
        onNodeWithTag(GomokuScreenTags.challenge(lobbyTarget)).performClick()
        waitForIdle()
        onNodeWithTag(GomokuScreenTags.stakeSheet).assertExists()
        // 아무것도 안 골라진 채 열린다 — 보내기는 서지 않는다.
        onNodeWithTag(GomokuScreenTags.stakeSend).assertIsNotEnabled()
        // 잔액 7: 3·5 는 고를 수 있고 10 은 비활성(기준선 — 같은 시트에서 칸마다 갈린다).
        onNodeWithTag(GomokuScreenTags.stakeOption(3)).assertIsEnabled()
        onNodeWithTag(GomokuScreenTags.stakeOption(5)).assertIsEnabled()
        onNodeWithTag(GomokuScreenTags.stakeOption(10)).assertIsNotEnabled()
        onNodeWithTag(GomokuScreenTags.stakeOption(5)).performClick()
        waitForIdle()
        onNodeWithTag(GomokuScreenTags.stakeSend).assertIsEnabled()
        assertEquals(0, rig.server.count("gomoku_challenge"), "고르기만 했는데 신청이 나갔다")
        onNodeWithTag(GomokuScreenTags.stakeSend).performClick()
        settle(rig)
        assertEquals(1, rig.server.count("gomoku_challenge"))
        val body = rig.server.last("gomoku_challenge")
        assertEquals(5L, body.long("p_stake"), "고른 판돈(5)이 아닌 값이 나갔다")
        assertEquals(lobbyTarget, body.str("p_opponent"))
        assertEquals(GomokuStake.five, rig.gomoku.selectedStake, "결과의 [다시 신청]이 쓸 판돈이 고른 값이 아니다")
        onNodeWithTag(GomokuScreenTags.stakeSheet).assertDoesNotExist()
        assertNotNull(rig.gomoku.outgoing, "신청 응답이 보낸 신청으로 서지 않았다")
        rig.close()
    }

    // MARK: ② §8-17 #1 깃발

    /** 판돈 시트를 (어떤 길로든) 띄운 채 5 를 고르고 보내기를 누른다 — (보내기 활성, 나간 신청 수). */
    private fun stakeSendWith(duelsEnabled: Boolean): Pair<Boolean, Int> {
        var out: Pair<Boolean, Int>? = null
        runDesktopComposeUiTest(420, 2600) {
            val rig = lobbyRig(duelsEnabled = duelsEnabled, ruby = 100) { queueFixtures("gomoku_challenge", GOMOKU_FIXTURES, "gomoku_challenge__ok") }
            val state = GomokuScreenState()
            setContent { BoardTestTheme { GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = {}, state = state) } }
            settle(rig)
            rig.host.rubyBalance = 100
            state.stakeTarget = GomokuUser(lobbyTarget, "코덱스토큰도둑예은", null, null, isWorking = true, isCapable = true, inMatch = false)
            waitForIdle()
            onNodeWithTag(GomokuScreenTags.stakeOption(5)).performClick()
            waitForIdle()
            val enabled = onNodeWithTag(GomokuScreenTags.stakeSend).fetchSemanticsNode().config.contains(SemanticsActions.OnClick) &&
                !onNodeWithTag(GomokuScreenTags.stakeSend).fetchSemanticsNode().config.contains(androidx.compose.ui.semantics.SemanticsProperties.Disabled)
            onNodeWithTag(GomokuScreenTags.stakeSend).performClick()
            settle(rig)
            out = enabled to rig.server.count("gomoku_challenge")
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

    /** 끝난 사람 판(흑 5목 승) 결과 화면 — (다시 신청 단추 수, 로비 캡션 수). */
    private fun resultAndCaption(duelsEnabled: Boolean): Pair<Int, Int> {
        var out: Pair<Int, Int>? = null
        runDesktopComposeUiTest(420, 2600) {
            val rig = BoardGameRig(me = null, duelsEnabled = duelsEnabled)
            GomokuScreenFlowTest.seedLobby(rig)
            setContent { BoardTestTheme { GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = {}) } }
            waitForIdle()
            val caption = onAllNodesWithText(GomokuPhoneText.lobbyCaption).fetchSemanticsNodes().size
            rig.gomoku.applyState(handGomokuState(myColor = "black", moveCount = 9, finished = true, result = "black_win", endReason = "five",
                stones = (3..7).map { Triple(it, 7, 'b') } + (3..6).map { Triple(it, 8, 'w') }))
            settle(rig)
            assertEquals(GomokuPhase.result, rig.gomoku.phase)
            onNodeWithTag(GomokuScreenTags.result).assertExists()
            out = onAllNodesWithTag(GomokuScreenTags.rematch).fetchSemanticsNodes().size to caption
            rig.close()
        }
        return requireNotNull(out)
    }

    @Test
    fun rematchAndLobbyCaptionFollowTheDuelsFlag() {
        val (offRematch, offCaption) = resultAndCaption(duelsEnabled = false)
        assertEquals(0, offRematch, "깃발이 꺼졌는데 [같은 판돈으로 다시 신청]이 섰다")
        assertEquals(0, offCaption, "깃발이 꺼졌는데 '신청하고 받을 수 있어요' 캡션이 섰다")
        val (onRematch, onCaption) = resultAndCaption(duelsEnabled = true)
        assertEquals(1, onRematch, "켜진 빌드에서 [다시 신청]이 없다 — 위 0 이 빈 단언이 된다")
        assertEquals(1, onCaption)
    }

    // MARK: ③ 대국 채팅 신고·차단

    /** 흐르는 사람 판(상대 차례) — 채팅 서랍이 선다. 음소거 응답은 픽스처. */
    private fun liveMatchRig(): BoardGameRig = BoardGameRig(me = HAND_ME) {
        respondWith("gomoku_inbox") { _, _ -> emptyInbox }
        queueFixtures("gomoku_chat_mute", GOMOKU_FIXTURES, "gomoku_chat_mute__ok_on")
    }.also { it.gomoku.applyState(handGomokuState(myColor = "black", turn = "white", moveCount = 1, stones = listOf(Triple(7, 7, 'b')), opponentName = "라이벌")) }

    @Test
    fun chatBlockAsksFirstAndOnlyTheConfirmBlocksAndMutes() = runDesktopComposeUiTest(420, 2600) {
        val rig = liveMatchRig()
        val safety = RecordingSafety()
        rig.games.appDidBecomeActive()
        setContent { BoardTestTheme { GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = {}, safety = safety.safety) } }
        settle(rig)
        onNodeWithTag(BoardSafetyTags.menu).performClick()
        waitForIdle()
        onNodeWithTag(BoardSafetyTags.menuBlock).performClick()
        settle(rig)
        // 메뉴는 확인만 연다 — 아직 아무도 차단되지 않았고 음소거도 나가지 않았다.
        assertEquals(emptyList(), safety.blocked, "확인 없이 차단이 나갔다")
        assertEquals(0, rig.server.count("gomoku_chat_mute"))
        onNodeWithTag(BoardSafetyTags.blockSheet).assertExists()
        onNodeWithText(BlockReportText.blockConfirmTitle("라이벌")).assertExists()
        for (line in BlockReportText.blockConfirmItems(BlockReportPlatform.phone)) onNodeWithText(line, useUnmergedTree = true).assertExists()
        // 확인 덮개 위에서도 화면은 그대로다(목적지가 아니다).
        assertTrue(rig.games.isGomokuScreenVisible)
        onNodeWithTag(BoardSafetyTags.blockConfirm).performClick()
        settle(rig)
        assertEquals(listOf(HAND_RIVAL), safety.blocked)
        assertEquals(1, rig.server.count("gomoku_chat_mute"), "차단 뒤 이 판의 채팅을 끄지 않았다")
        assertEquals("true", rig.server.last("gomoku_chat_mute").body["p_muted"]?.jsonPrimitive?.content)
        onNodeWithTag(BoardSafetyTags.blockSheet).assertDoesNotExist()
        rig.close()
    }

    @Test
    fun chatReportOpensInsideTheScreenAndMutesOnlyWhenItAlsoBlocked() = runDesktopComposeUiTest(420, 2600) {
        val rig = liveMatchRig()
        val safety = RecordingSafety()
        rig.games.appDidBecomeActive()
        setContent { BoardTestTheme { GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = {}, safety = safety.safety) } }
        settle(rig)
        fun openReport() {
            onNodeWithTag(BoardSafetyTags.menu).performClick()
            waitForIdle()
            onNodeWithTag(BoardSafetyTags.menuReport).performClick()
            settle(rig)
            // 가짜 시트는 덮개 카드(누름을 삼키는 노드)에 합쳐진다 — 펼친 나무에서 찾는다.
            onNodeWithTag("fake-report-sheet", useUnmergedTree = true).assertExists()
            onNodeWithTag(BoardSafetyTags.reportSheet).assertExists()
            // 화면 안 덮개 — 대국 화면·창 표시·폴링이 그대로 산다(목적지로 밀었다면 셋 다 꺼진다).
            onNodeWithTag(GomokuScreenTags.match).assertExists()
            assertTrue(rig.games.isGomokuScreenVisible, "신고 시트가 대국 화면을 내렸다")
            assertTrue(rig.gomoku.isWindowVisible)
            assertEquals(true, rig.gomoku.pollTask?.isActive, "신고 시트가 폴링을 죽였다")
        }
        openReport()
        assertEquals(BoardReportTarget(HAND_RIVAL, "라이벌"), safety.reported.last())
        // 신고만 — 음소거는 나가지 않는다(기준선).
        onNodeWithTag("fake-report-send").performClick()
        settle(rig)
        onNodeWithTag(BoardSafetyTags.reportSheet).assertDoesNotExist()
        assertEquals(0, rig.server.count("gomoku_chat_mute"), "차단 없는 신고가 채팅을 껐다")
        assertEquals(emptyList(), safety.blocked)
        // 신고하며 차단 — 서버가 이미 차단했다(onSent(true)) → 이 판의 채팅을 끈다.
        openReport()
        onNodeWithTag("fake-report-send-block").performClick()
        settle(rig)
        assertEquals(1, rig.server.count("gomoku_chat_mute"), "'신고하며 차단' 뒤 채팅을 끄지 않았다")
        assertEquals(emptyList(), safety.blocked, "신고 시트가 차단을 한 번 더 냈다(서버가 이미 했다)")
        rig.close()
    }

    // MARK: ④ 초점 · 판 전환 · 겹침

    @Test
    fun aMoveClearsTheForbiddenFocus() = runDesktopComposeUiTest(420, 2600) {
        val rig = BoardGameRig(me = HAND_ME)
        BoardScenes.seedGomokuMatch(rig)
        val state = GomokuScreenState()
        setContent { BoardTestTheme { GomokuScreen(rig.games, rig.gomoku, BoardGameMe("나검정", "fox", CharacterMood.Working), onLeave = {}, state = state) } }
        settle(rig)
        // (8,7) 은 흑 3-3 금수 — 누르면 빨간 금수 줄이 1순위로 선다.
        tapBoard(GomokuPoint.at(8, 7)!!)
        settle(rig)
        val reason = assertNotNull(state.focusedForbidden, "금수 자리를 눌렀는데 초점이 서지 않았다")
        onNodeWithText(GomokuPhoneText.forbiddenStatus(reason), useUnmergedTree = true).assertExists()
        // 시간 초과 자동 착수(다른 칸) — 수가 9 로 늘고 상대 차례가 된다.
        val black = listOf(6 to 7, 7 to 7, 8 to 8, 8 to 9, 1 to 1).map { Triple(it.first, it.second, 'b') }
        val white = listOf(3 to 3, 11 to 3, 3 to 11, 11 to 12).map { Triple(it.first, it.second, 'w') }
        rig.gomoku.applyState(handGomokuState(myColor = "black", turn = "white", moveCount = 9, stones = black + white))
        settle(rig)
        assertNull(state.focusedForbidden, "수가 바뀌었는데 금수 초점이 남았다")
        // 스토어의 탭 거절 안내(`notice`)도 같은 문구를 한 줄 남긴다(스토어 몫 — 화면 초점과 다른 칸). 화면 초점 줄만 재려고 그 칸을 비운다.
        rig.gomoku.notice = null
        waitForIdle()
        onNodeWithText(GomokuPhoneText.forbiddenStatus(reason), useUnmergedTree = true).assertDoesNotExist()
        rig.close()
    }

    @Test
    fun aNewMatchFoldsTheStakeSheet() = runDesktopComposeUiTest(420, 2600) {
        val rig = BoardGameRig(me = null)
        GomokuScreenFlowTest.seedLobby(rig)
        setContent { BoardTestTheme { GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = {}) } }
        waitForIdle()
        onNodeWithTag(GomokuScreenTags.challenge(GomokuScreenFlowTest.SEED_USERS[0].id)).performClick()
        waitForIdle()
        onNodeWithTag(GomokuScreenTags.stakeSheet).assertExists()
        // 다른 기기에서 수락된 판이 선다(판 id 가 바뀐다) — 판돈 시트가 대국 위에 남으면 안 된다(Swift onChange(of: match?.id)).
        rig.gomoku.applyState(handGomokuState(myColor = "white", turn = "black", moveCount = 0))
        settle(rig)
        onNodeWithTag(GomokuScreenTags.match).assertExists()
        onNodeWithTag(GomokuScreenTags.stakeSheet).assertDoesNotExist()
        rig.close()
    }

    @Test
    fun overlappingScreensKeepThePollingOfTheOneThatStays() = runDesktopComposeUiTest(420, 2600) {
        val rig = BoardGameRig(me = me) {
            respondWith("gomoku_lobby") { _, _ -> fixtureText(GOMOKU_FIXTURES, "gomoku_lobby__ok_matches") }
            respondWith("gomoku_inbox") { _, _ -> emptyInbox }
        }
        rig.games.appDidBecomeActive()
        var first by mutableStateOf(true)
        var second by mutableStateOf(false)
        val firstTabBar = mutableListOf<Boolean>()
        setContent {
            BoardTestTheme {
                Box {
                    if (first) GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = {}, onTabBarHidden = { firstTabBar += it })
                    if (second) GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = {})
                }
            }
        }
        settle(rig)
        fun alive(label: String) {
            assertTrue(rig.games.isGomokuScreenVisible, "$label: 화면 표시가 꺼졌다")
            assertTrue(rig.gomoku.isWindowVisible, "$label: 창 표시가 꺼졌다")
            assertEquals(true, rig.gomoku.pollTask?.isActive, "$label: 폴링이 죽었다")
        }
        alive("하나")
        // 알림·딥링크로 같은 목적지가 하나 더 쌓였다 → 옛 화면이 내려간다.
        second = true
        settle(rig)
        alive("둘")
        firstTabBar.clear()
        first = false
        settle(rig)
        alive("옛 화면이 내려간 뒤")
        assertEquals(emptyList(), firstTabBar, "남은 화면이 있는데 옛 화면이 탭 막대를 되돌렸다")
        // 기준선: 마지막 하나가 내려가면 창이 내려가고 폴링이 죽는다.
        second = false
        settle(rig)
        assertFalse(rig.games.isGomokuScreenVisible)
        assertNull(rig.gomoku.pollTask, "마지막 화면이 내려갔는데 폴링이 남았다")
        rig.close()
    }

    // MARK: ⑤ iOS 동작 짝

    @Test
    fun resignLivesInTheMoreMenu() = runDesktopComposeUiTest(420, 2600) {
        val rig = BoardGameRig(me = null)
        rig.gomoku.applyState(handGomokuState(myColor = "black", turn = "white", moveCount = 1, stones = listOf(Triple(7, 7, 'b'))))
        val state = GomokuScreenState()
        setContent { BoardTestTheme { GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = {}, state = state) } }
        settle(rig)
        // 머리에는 ⋯ 하나 — [기권]은 메뉴를 열어야 보인다.
        onNodeWithTag(GomokuScreenTags.resign).assertDoesNotExist()
        onNodeWithTag(GomokuScreenTags.more).performClick()
        waitForIdle()
        onNodeWithTag(GomokuScreenTags.resign).assertExists()
        // 화면이 뜬 직후의 누름은 가드가 먹는다(GomokuPhoneResignGuard) — 시각을 넉넉히 흘린 뒤 누른다.
        state.shownAt = boardClock.addingTimeInterval(-10.0)
        onNodeWithTag(GomokuScreenTags.resign).performClick()
        waitForIdle()
        assertTrue(state.showsResignConfirm, "메뉴의 [기권]이 확인을 띄우지 않았다")
        onNodeWithTag(GomokuScreenTags.resignConfirm).assertExists()
        assertEquals(0, rig.server.count("gomoku_resign"), "확인 전에 기권이 나갔다")
        rig.close()
    }

    @Test
    fun pullToRefreshReloadsTheLobbyAndTheInbox() = runDesktopComposeUiTest(420, 2600) {
        val rig = lobbyRig()
        setContent { BoardTestTheme { GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = {}) } }
        settle(rig)
        val lobbyBefore = rig.server.count("gomoku_lobby")
        val inboxBefore = rig.server.count("gomoku_inbox")
        assertEquals(1, lobbyBefore, "화면 열기의 로비 조회")
        onNodeWithTag(GomokuScreenTags.lobbyRefresh).performTouchInput { swipeDown(startY = top + 10f, endY = top + 700f, durationMillis = 600) }
        settle(rig)
        rig.settle()
        waitForIdle()
        assertEquals(lobbyBefore + 1, rig.server.count("gomoku_lobby"), "당겨서 새로고침이 로비를 다시 읽지 않았다")
        assertEquals(inboxBefore + 1, rig.server.count("gomoku_inbox"), "당겨서 새로고침이 받은함을 다시 읽지 않았다")
        rig.close()
    }

    @Test
    fun accessibilityHintsReachTheClickLabel() = runDesktopComposeUiTest(420, 3000) {
        val rig = BoardGameRig(me = null)
        GomokuScreenFlowTest.seedLobby(rig)
        setContent { BoardTestTheme { GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = {}) } }
        waitForIdle()
        val user = GomokuScreenFlowTest.SEED_USERS[0]
        val challenge = onNodeWithTag(GomokuScreenTags.challenge(user.id)).fetchSemanticsNode().config[SemanticsActions.OnClick]
        assertEquals(GomokuScreenText.challengeHint(user.displayName), challenge.label)
        val watch = onNodeWithTag(GomokuScreenTags.watch(GomokuScreenFlowTest.SEED_LIVE_ID)).fetchSemanticsNode().config[SemanticsActions.OnClick]
        assertEquals(GomokuScreenText.watchChipHint, watch.label)
        val ai = onNodeWithTag(GomokuScreenTags.aiEntry).fetchSemanticsNode().config[SemanticsActions.OnClick]
        assertEquals(GomokuPhoneText.aiPromptCaption, ai.label)
        // 이름표를 단 누름도 같은 동작이다(보이스오버·TalkBack 이 부르는 길) — 판돈 시트가 선다.
        onNodeWithTag(GomokuScreenTags.challenge(user.id)).performSemanticsAction(SemanticsActions.OnClick)
        waitForIdle()
        onNodeWithTag(GomokuScreenTags.stakeSheet).assertExists()
        rig.close()
    }

    @Test
    fun hapticsFollowMovesAndTheEnd() = runDesktopComposeUiTest(420, 2600) {
        val rig = BoardGameRig(me = null)
        rig.gomoku.applyState(handGomokuState(myColor = "black", turn = "white", moveCount = 1, stones = listOf(Triple(7, 7, 'b'))))
        val haptics = RecordingHaptics()
        setContent { CompositionLocalProvider(LocalHapticFeedback provides haptics) { BoardTestTheme { GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = {}) } } }
        settle(rig)
        // 나타날 때는 울리지 않는다(Swift onChange 의미 — 기준선).
        assertEquals(emptyList(), haptics.types, "화면이 나타나며 햅틱이 울렸다")
        rig.gomoku.applyState(handGomokuState(myColor = "black", turn = "black", moveCount = 2, stones = listOf(Triple(7, 7, 'b'), Triple(8, 8, 'w'))))
        settle(rig)
        assertEquals(listOf(HapticFeedbackType.LongPress), haptics.types, "상대 수에 착수 햅틱이 없다")
        rig.gomoku.applyState(handGomokuState(myColor = "black", moveCount = 9, finished = true, result = "black_win", endReason = "five",
            stones = (3..7).map { Triple(it, 7, 'b') } + (3..6).map { Triple(it, 8, 'w') }))
        settle(rig)
        assertEquals(listOf(HapticFeedbackType.LongPress, HapticFeedbackType.Confirm), haptics.types, "이긴 판 끝에 확인 햅틱이 없다")
        rig.close()
    }
}
