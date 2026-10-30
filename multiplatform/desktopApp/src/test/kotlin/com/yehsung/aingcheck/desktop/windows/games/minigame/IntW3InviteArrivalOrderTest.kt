// 원본: Sources/check/CheckApp.swift:359·380-387·401·437(onInviteArrived — 구조 신청을 오버레이 큐에 먼저 넣고 글 알림은 그 뒤)
//       · W-14 #4(대결 신청 id·만료 → overlay.onDuelInvite — 셸 글이 먼저 오면 대체 말풍선이 하나 더 뜬다)
package com.yehsung.aingcheck.desktop.windows.games.minigame

import com.yehsung.aingcheck.core.stores.gomoku.GomokuInvite
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
                onInviteNotice = { log += "notice:${it.kind}" },
                onInviteArrival = { g, id, peer, stake, exp -> log += "arrival:$g:$id:$peer:$stake:${exp.timeIntervalSince1970}" },
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
                "notice:Gomoku",
            ),
            on,
        )
        offRig.board.close()
        onRig.board.close()
    }
}
