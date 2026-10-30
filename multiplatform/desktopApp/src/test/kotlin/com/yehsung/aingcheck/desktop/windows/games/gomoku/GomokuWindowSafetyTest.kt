// 원본: 없음 — W-14 #1(대국 채팅 신고·차단, Store 11.12) · 맥 CheckGomokuWindow.swift:198-204 · GomokuPanel.swift:2093-2101 ·
//       폰 NavGraph.kt:269-275(같은 모양) · 공용 패치 20(LocalBlockReportPlatform — 게임 창 뿌리에서 .mac, 승인 조건 4)
// 실제 배선 한 바퀴: GamesDeps(messages) → GamesWiring → GameWindowFactory.Compose.board → ComposeGamesWindows.create → 오목 껍데기 내용(창 0).
package com.yehsung.aingcheck.desktop.windows.games.gomoku

import androidx.compose.ui.test.DesktopComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.core.rules.text.BlockReportPlatform
import com.yehsung.aingcheck.core.rules.text.BlockReportText
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.NaturalKoNameCollation
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.ContentReportReason
import com.yehsung.aingcheck.desktop.pages.shared.SharedTestHarness
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import com.yehsung.aingcheck.desktop.windows.games.minigame.ComposeGameWindowShell
import com.yehsung.aingcheck.desktop.windows.games.minigame.GameWindowScenes
import com.yehsung.aingcheck.desktop.windows.games.minigame.GameWindowScenes.BoardArt
import com.yehsung.aingcheck.desktop.windows.games.minigame.GamesWindowsHost
import com.yehsung.aingcheck.desktop.windows.games.minigame.rig.BoardGameRig
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind
import com.yehsung.aingcheck.desktop.wiring.FakeGameFactory
import com.yehsung.aingcheck.desktop.wiring.GamesDeps
import com.yehsung.aingcheck.desktop.wiring.GamesWiring
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.games.gomoku.BoardSafetyTags
import com.yehsung.aingcheck.ui.games.gomoku.GOMOKU_FIXTURES
import com.yehsung.aingcheck.ui.games.gomoku.GomokuScreen
import com.yehsung.aingcheck.ui.games.gomoku.GomokuScreenTags
import com.yehsung.aingcheck.ui.games.gomoku.HAND_ME
import com.yehsung.aingcheck.ui.games.gomoku.HAND_RIVAL
import com.yehsung.aingcheck.ui.games.gomoku.handGomokuState
import com.yehsung.aingcheck.ui.screens.messages.MessagesTags
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class)
class GomokuWindowSafetyTest {
    /** 오목 창 한 벌 — 실제 배선(창 0). [withMessages] = AppGraph 가 메시지 스토어를 넘겼는가. [live] = 흐르는 사람 판(채팅 서랍이 선다). */
    private class WindowRig(config: DesktopAppConfig, withMessages: Boolean, live: Boolean) {
        val board = BoardGameRig(me = HAND_ME, duelsEnabled = config.toAppConfig().duelsEnabled) {
            respondWith("gomoku_inbox") { _, _ -> EMPTY_INBOX }
            queueFixtures("gomoku_chat_mute", GOMOKU_FIXTURES, "gomoku_chat_mute__ok_on")
            respondWith("block_user") { _, _ -> "null" }
            respondWith("report_content") { _, _ -> "null" }
        }
        val messages: MessagesStore? = if (!withMessages) null else {
            board.sessionStore.adoptSignedInSession(SupabaseSession("tok-me", "ref-me", HAND_ME), "me@aing.example")
            MessagesStore(SessionContext(board.sessionStore, board.appConfig), board.scope, NaturalKoNameCollation)
        }
        private val h = SharedTestHarness(board.testScope)
        val wiring = GamesWiring(
            GamesDeps(
                games = board.games,
                gomoku = board.gomoku,
                chess = board.chess,
                me = h.me,
                session = board.sessionStore,
                desktopConfig = config,
                deviceStore = InMemoryDesktopKeyValueStore(),
                flyout = InMemoryFlyoutNavigator(),
                workAreas = { listOf(PxRect(0, 0, 1920, 1032)) },
                now = { SwiftDate(1_789_621_500.0) },
                factory = FakeGameFactory(realBoard = true),
                messages = messages,
            ),
        )
        val shell = (wiring.handle.windows as GamesWindowsHost).shell(GameWindowKind.Gomoku) as ComposeGameWindowShell

        init {
            // 실제 배선의 창 문(present · dismiss · attention)은 진짜 AWT 창을 짓는다 — 시험은 창 0(기억 agents-no-visible-windows). 내용만 그린다.
            board.gomoku.presentWindow = {}
            board.gomoku.dismissWindow = {}
            board.gomoku.requestAttention = {}
            board.chess.presentWindow = {}
            board.chess.dismissWindow = {}
            board.chess.requestAttention = {}
            if (live) {
                board.gomoku.applyState(
                    handGomokuState(myColor = "black", turn = "white", moveCount = 1, stones = listOf(Triple(7, 7, 'b')), opponentName = "라이벌"),
                )
            }
            board.games.appDidBecomeActive()
        }

        fun safetyCalls(): Int = listOf("block_user", "report_content", "list_blocks").sumOf { board.server.count(it) }
    }

    private fun DesktopComposeUiTest.settle(rig: WindowRig) {
        repeat(3) {
            waitForIdle()
            rig.board.settle()
        }
        waitForIdle()
    }

    private fun DesktopComposeUiTest.show(rig: WindowRig) {
        setContent { BoardArt { rig.shell.content() } }
        settle(rig)
    }

    // MARK: 신고 — 시트 보내기 → report_content 1건(사람 id), 차단 0

    @Test
    fun chatMenuReportSendsOneReportForThePerson() = runDesktopComposeUiTest(420, 2600) {
        val rig = WindowRig(DesktopAppConfig(duels = true), withMessages = true, live = true)
        show(rig)
        onNodeWithTag(BoardSafetyTags.menu).performClick()
        waitForIdle()
        onNodeWithText(BlockReportText.reportAction).assertExists()
        onNodeWithText(BlockReportText.blockAction).assertExists()
        onNodeWithTag(BoardSafetyTags.menuReport).performClick()
        settle(rig)
        // 메시지 탭과 같은 시트(MessagesReportSheet)가 화면 안 덮개로 선다 — 목적지가 아니다.
        onNodeWithTag(MessagesTags.REPORT_SHEET, useUnmergedTree = true).assertExists()
        onNodeWithTag(BoardSafetyTags.reportSheet).assertExists()
        onNodeWithTag(MessagesTags.reportReason(ContentReportReason.harassment.rawValue), useUnmergedTree = true).performClick()
        waitForIdle()
        onNodeWithTag(MessagesTags.REPORT_SUBMIT, useUnmergedTree = true).performClick()
        settle(rig)
        assertEquals(1, rig.board.server.count("report_content"), "신고가 서버로 한 번 나가지 않았다")
        val body = rig.board.server.last("report_content").body
        assertTrue(body.values.any { it.jsonPrimitive.content == HAND_RIVAL }, "신고 대상이 상대 사람이 아니다: $body")
        assertTrue(body.values.any { it.jsonPrimitive.content == ContentReportReason.harassment.rawValue }, "고른 사유가 실리지 않았다: $body")
        assertEquals(0, rig.board.server.count("block_user"), "신고만 했는데 차단이 나갔다")
        onNodeWithTag(BoardSafetyTags.reportSheet).assertDoesNotExist()
        rig.board.close()
    }

    // MARK: 차단 — 메뉴는 확인만 연다 → 확인 시트(맥 문구) → block_user 1건

    @Test
    fun chatMenuBlockAsksWithMacWordingThenBlocksOnce() = runDesktopComposeUiTest(420, 2600) {
        val rig = WindowRig(DesktopAppConfig(duels = true), withMessages = true, live = true)
        show(rig)
        onNodeWithTag(BoardSafetyTags.menu).performClick()
        waitForIdle()
        onNodeWithTag(BoardSafetyTags.menuBlock).performClick()
        settle(rig)
        assertEquals(0, rig.board.server.count("block_user"), "확인 없이 차단이 나갔다")
        onNodeWithTag(BoardSafetyTags.blockSheet).assertExists()
        onNodeWithTag(MessagesTags.BLOCK_CONFIRM).assertExists() // 메시지 탭 확인 시트(세 입구가 한 시트)
        onNodeWithText(BlockReportText.blockConfirmTitle("라이벌")).assertExists()
        // 맥 문구: '설정 → 차단한 사람' · 맥 확인 항목 — 폰 문구('나 → 설정 → 차단한 사람')는 없다.
        onNodeWithText(BlockReportText.blockConfirmUndoNote(BlockReportPlatform.mac), useUnmergedTree = true).assertExists()
        assertTrue(BlockReportText.blockConfirmUndoNote(BlockReportPlatform.mac).startsWith("설정 → 차단한 사람"))
        assertEquals(0, onAllNodesWithText(BlockReportText.blockConfirmUndoNote(BlockReportPlatform.phone), useUnmergedTree = true).fetchSemanticsNodes().size)
        for (line in BlockReportText.blockConfirmItems(BlockReportPlatform.mac)) onNodeWithText(line, useUnmergedTree = true).assertExists()
        onNodeWithTag(MessagesTags.BLOCK_CONFIRM).performClick()
        settle(rig)
        assertEquals(1, rig.board.server.count("block_user"), "확인 뒤 차단이 한 번 나가지 않았다")
        assertEquals(HAND_RIVAL, rig.board.server.last("block_user").body["p_user"]?.jsonPrimitive?.content)
        assertEquals(0, rig.board.server.count("report_content"))
        onNodeWithTag(BoardSafetyTags.blockSheet).assertDoesNotExist()
        rig.board.close()
    }

    // MARK: 음성 대조

    /** 음성 ①: AppGraph 가 메시지 스토어를 안 넘기면(safety 없음) 같은 사람 판에서 ⋯ 메뉴 0 · 신고·차단 문구 0. */
    @Test
    fun negativeNoMessagesStoreMeansNoMenu() = runDesktopComposeUiTest(420, 2600) {
        val rig = WindowRig(DesktopAppConfig(duels = true), withMessages = false, live = true)
        show(rig)
        onNodeWithTag("gomoku-chat-drawer").assertExists() // 양성 — 채팅 서랍은 섰다(위 0 이 빈 단언이 아니다)
        assertEquals(0, onAllNodesWithTag(BoardSafetyTags.menu).fetchSemanticsNodes().size, "safety 없이 ⋯ 메뉴가 섰다")
        assertEquals(0, onAllNodesWithText(BlockReportText.reportAction).fetchSemanticsNodes().size)
        assertEquals(0, rig.safetyCalls())
        rig.board.close()
    }

    /** 음성 ②: 창 바탕(GameWindowFrame) 밖에서 같은 safety 로 그리면 폰 문구 — 맥 문구는 창 뿌리가 준 것이다. */
    @Test
    fun negativeOutsideTheWindowFrameFallsBackToPhoneWording() = runDesktopComposeUiTest(420, 2600) {
        val rig = WindowRig(DesktopAppConfig(duels = true), withMessages = true, live = true)
        setContent {
            BoardArt {
                AingTheme(dark = false) {
                    GomokuScreen(rig.board.games, rig.board.gomoku, BoardGameMe.unknown, onLeave = {}, safety = GomokuWindowSafety.of(rig.messages))
                }
            }
        }
        settle(rig)
        onNodeWithTag(BoardSafetyTags.menu).performClick()
        waitForIdle()
        onNodeWithTag(BoardSafetyTags.menuBlock).performClick()
        settle(rig)
        onNodeWithText(BlockReportText.blockConfirmUndoNote(BlockReportPlatform.phone), useUnmergedTree = true).assertExists()
        assertEquals(0, onAllNodesWithText(BlockReportText.blockConfirmUndoNote(BlockReportPlatform.mac), useUnmergedTree = true).fetchSemanticsNodes().size)
        rig.board.close()
    }

    // MARK: 깃발 꺼짐(출고 duels=false) — 배선만으로는 신고·차단 경로 요청 0

    @Test
    fun shippedFlagsWireSafetyWithoutAnyServerCall() = runDesktopComposeUiTest(440, 3000) {
        assertEquals(false, DesktopAppConfig().toAppConfig().duelsEnabled)
        val rig = WindowRig(DesktopAppConfig(), withMessages = true, live = false)
        GameWindowScenes.seedGomokuLobby(rig.board)
        show(rig)
        onNodeWithTag(GomokuScreenTags.aiEntry).assertExists() // 양성 — 로비가 그려졌다
        assertEquals(0, onAllNodesWithTag(BoardSafetyTags.menu).fetchSemanticsNodes().size, "사람 판이 없는데 ⋯ 메뉴가 섰다")
        assertEquals(0, rig.safetyCalls(), "배선이 신고·차단 경로를 불렀다: ${rig.board.server.calls.map { it.rpc }}")
        rig.board.close()
    }

    companion object {
        const val EMPTY_INBOX = """{"status":"ok","incoming":[],"outgoing":null,"ruby_balance":100,"last_finished":null,"server_now_ms":1789547568000,"active_match_id":null}"""
    }
}
