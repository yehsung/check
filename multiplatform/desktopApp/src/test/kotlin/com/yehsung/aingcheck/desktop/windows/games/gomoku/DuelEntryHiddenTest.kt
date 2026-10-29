// 원본: 없음 — G §8-17 #1 · W-3 #7·#17(Windows 대결 깃발 DesktopAppConfig.duels 기본 false — 서버 ④⑥ 전이라 대결 상수 미도달)
//       (W4-e 완료 기준 — DuelEntryHiddenTest: 출고 깃발 → 도전·수락 노드 0 · 신청 RPC 0건. 음성: duels=true 면 노드가 생긴다)
package com.yehsung.aingcheck.desktop.windows.games.gomoku

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.desktop.windows.games.chess.ChessWindowContent
import com.yehsung.aingcheck.desktop.windows.games.minigame.GameWindowScenes
import com.yehsung.aingcheck.desktop.windows.games.minigame.GameWindowScenes.BoardArt
import com.yehsung.aingcheck.desktop.windows.games.minigame.rig.BoardGameRig
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.ui.games.chess.ChessScreenTags
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.games.gomoku.GomokuScreenTags
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class)
class DuelEntryHiddenTest {
    private data class Seen(val gomokuChallenge: Int, val gomokuAccept: Int, val chessChallenge: Int, val rpcs: Int)

    @Test
    fun shippedFlagsHideEveryDuelEntry() {
        assertEquals(false, DesktopAppConfig().toAppConfig().duelsEnabled, "출고 깃발이 대결을 켰다")
        val seen = lobbies(DesktopAppConfig())
        assertEquals(Seen(0, 0, 0, 0), seen)
    }

    @Test
    fun negativeDuelsOnShowsTheEntries() {
        val seen = lobbies(DesktopAppConfig(duels = true))
        assertTrue(seen.gomokuChallenge > 0 && seen.gomokuAccept > 0, "깃발을 켰는데 오목 도전·수락이 없다 — 시험이 노드를 못 본다($seen)")
        assertTrue(seen.chessChallenge > 0, "깃발을 켰는데 체스 도전이 없다($seen)")
    }

    private fun lobbies(config: DesktopAppConfig): Seen {
        var out: Seen? = null
        runDesktopComposeUiTest(440, 3000) {
            val rig = BoardGameRig(me = null, duelsEnabled = config.toAppConfig().duelsEnabled)
            GameWindowScenes.seedGomokuLobby(rig)
            GameWindowScenes.seedChessLobby(rig)
            var chess by mutableStateOf(false)
            setContent {
                BoardArt {
                    if (!chess) GomokuWindowContent(rig.games, rig.gomoku, BoardGameMe.unknown, dark = false, onLeave = {})
                    else ChessWindowContent(rig.games, rig.chess, BoardGameMe.unknown, dark = false, onLeave = {})
                }
            }
            waitForIdle()
            onNodeWithTag(GomokuScreenTags.aiEntry).assertExists() // 양성 대조 — 로비가 그려졌다
            val gc = GameWindowScenes.SEED_USERS.count { onAllNodesWithTag(GomokuScreenTags.challenge(it.id)).fetchSemanticsNodes().isNotEmpty() }
            val ga = onAllNodesWithTag(GomokuScreenTags.accept(GameWindowScenes.SEED_INVITE_ID)).fetchSemanticsNodes().size
            chess = true
            waitForIdle()
            val cc = GameWindowScenes.SEED_CHESS_USERS.count { onAllNodesWithTag(ChessScreenTags.challenge(it.id)).fetchSemanticsNodes().isNotEmpty() }
            val rpcs = listOf("gomoku_challenge", "gomoku_accept_invite", "chess_challenge", "chess_accept").sumOf { rig.server.count(it) }
            out = Seen(gc, ga, cc, rpcs)
            rig.close()
        }
        return requireNotNull(out)
    }
}
