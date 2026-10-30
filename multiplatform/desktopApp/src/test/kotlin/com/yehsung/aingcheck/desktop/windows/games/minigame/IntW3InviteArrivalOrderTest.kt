// 원본: Sources/check/CheckApp.swift:359·380-387·401·437(onInviteArrived — 구조 신청을 오버레이 큐에 먼저 넣고 글 알림은 그 뒤)
//       · W-14 #4(대결 신청 id·만료 → overlay.onDuelInvite — 셸 글이 먼저 오면 대체 말풍선이 하나 더 뜬다)
package com.yehsung.aingcheck.desktop.windows.games.minigame

import com.yehsung.aingcheck.core.stores.chess.ChessAttention
import com.yehsung.aingcheck.core.stores.gomoku.GomokuAttention
import com.yehsung.aingcheck.core.stores.gomoku.GomokuInvite
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelAttention
import com.yehsung.aingcheck.desktop.overlay.engine.DuelGame
import com.yehsung.aingcheck.desktop.windows.games.minigame.rig.BoardGameRig
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.ui.games.gomoku.boardClock
import com.yehsung.aingcheck.ui.games.minigame.UiGamesHarness
import kotlinx.coroutines.test.TestScope
import kotlin.test.Test
import kotlin.test.assertEquals

class IntW3InviteArrivalOrderTest {
    private class Rig(config: DesktopAppConfig, log: MutableList<String>) {
        val board = BoardGameRig(me = null, duelsEnabled = config.toAppConfig().duelsEnabled)
        val games = UiGamesHarness(TestScope(), config.toAppConfig()) { null }
        val host = GameWindowScenes.host(GamesWindowsHost.OWN_KINDS.associateWith { FakeGameWindowShell() })
        init {
            GameWindowWiring.wire(
                board.gomoku, board.chess, games.tetris, host, config,
                onInviteNotice = { log += "notice:${it.kind}:${it.inviteId}" },
                onInviteArrival = { g, id, peer, stake, exp -> log += "arrival:$g:$id:$peer:$stake:${exp.timeIntervalSince1970}" },
                onTurnWhileHidden = { log += "hidden:$it" },
                onDuelAttention = { a -> log += "attention:${a.game}:${a.matchId}:${a.kind}:${a.opponentName}:${a.moveCount}" },
            )
        }
    }

    /** 구조 신청(id·이름·판돈·만료)이 글 알림보다 먼저 — 오버레이가 같은 글을 '이미 받은 신청'으로 묶는 열쇠. duels 꺼짐이면 둘 다 0. */
    @Test
    fun structuredArrivalPrecedesShellNoticeAndCarriesIdAndExpiry() {
        val expires = boardClock.addingTimeInterval(42.0)
        val invite = GomokuInvite("11111111-0000-4000-8000-0000000000b7", GameWindowScenes.SEED_USERS[0], 5, expires)

        val off = mutableListOf<String>()
        val offRig = Rig(DesktopAppConfig(duels = false), off)
        requireNotNull(offRig.board.gomoku.onInviteArrived).invoke(invite)
        assertEquals(emptyList(), off, "duels 꺼진 빌드가 신청을 오버레이·셸로 냈다")

        val on = mutableListOf<String>()
        val onRig = Rig(DesktopAppConfig(duels = true), on)
        requireNotNull(onRig.board.gomoku.onInviteArrived).invoke(invite)
        assertEquals(
            listOf(
                "arrival:${DuelGame.GOMOKU}:${invite.id}:${invite.peer.displayName}:5:${expires.timeIntervalSince1970}",
                "notice:Gomoku:${invite.id}",
            ),
            on,
        )
        offRig.board.close()
        onRig.board.close()
    }

    /**
     * int-w4a ③: 차례 알림(onAttention)이 구조 정보(판 id·종류·상대·수 번호)를 실어 오버레이로 간다 — 맥 CheckApp.swift:367 · :404 · :440
     * `onAttention → enqueue…Attention`(누르면 그 판 창). 셸 쪽 onTurnWhileHidden 은 그대로. duels 꺼짐이면 구조 알림 0.
     */
    @Test
    fun attentionCarriesMatchIdAndKindToOverlay() {
        val on = mutableListOf<String>()
        val onRig = Rig(DesktopAppConfig(duels = true), on)
        requireNotNull(onRig.board.gomoku.onAttention).invoke(GomokuAttention(GomokuAttention.Kind.myTurn, "g-1", "합성상대", 4))
        requireNotNull(onRig.board.chess.onAttention).invoke(ChessAttention(ChessAttention.Kind.matchStarted, "c-1", "합성상대", 0))
        requireNotNull(onRig.games.tetris.onAttention).invoke(TetrisDuelAttention(TetrisDuelAttention.Kind.matchStarted, "t-1", "합성상대"))
        assertEquals(
            listOf(
                "hidden:Gomoku", "attention:GOMOKU:g-1:MY_TURN:합성상대:4",
                "hidden:Chess", "attention:CHESS:c-1:MATCH_STARTED:합성상대:0",
                "hidden:TetrisDuel", "attention:TETRIS:t-1:MATCH_STARTED:합성상대:0",
            ),
            on,
        )

        val off = mutableListOf<String>()
        val offRig = Rig(DesktopAppConfig(duels = false), off)
        requireNotNull(offRig.board.gomoku.onAttention).invoke(GomokuAttention(GomokuAttention.Kind.myTurn, "g-1", "합성상대", 4))
        assertEquals(listOf("hidden:Gomoku"), off, "duels 꺼짐 → 구조 알림 0")
        onRig.board.close()
        offRig.board.close()
    }
}
