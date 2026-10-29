// 원본: 없음 — 오목·체스 화면 스냅숏 장면(데스크톱·Android 가 같은 장면을 그린다). 서버 호출 없이 스토어 칸·실서버 픽스처로 장면을 세운다.
//
// 장면마다 **한 군데만 다른** 짝(음성 기준선)을 같이 낸다 — 같은 크기에서 비교가 내용을 본다는 증거(기억 comparison-baseline-must-differ).
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.stores.chess.ChessInvite
import com.yehsung.aingcheck.core.stores.chess.ChessLiveMatch
import com.yehsung.aingcheck.core.stores.chess.ChessRankEntry
import com.yehsung.aingcheck.core.stores.chess.ChessRankingBoard
import com.yehsung.aingcheck.core.stores.chess.ChessRecord
import com.yehsung.aingcheck.core.stores.chess.ChessStake
import com.yehsung.aingcheck.core.stores.chess.ChessUser
import com.yehsung.aingcheck.core.stores.gomoku.GomokuInvite
import com.yehsung.aingcheck.core.stores.gomoku.GomokuLiveMatch
import com.yehsung.aingcheck.core.stores.gomoku.GomokuRankEntry
import com.yehsung.aingcheck.core.stores.gomoku.GomokuRankingBoard
import com.yehsung.aingcheck.core.stores.gomoku.GomokuRecord
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStake
import com.yehsung.aingcheck.core.stores.gomoku.GomokuUser
import com.yehsung.aingcheck.core.wire.games.ChessStatePayload
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.games.chess.ChessBoardCanvas
import com.yehsung.aingcheck.ui.games.chess.ChessBoardPicture
import com.yehsung.aingcheck.ui.games.chess.ChessScreen
import com.yehsung.aingcheck.core.rules.chess.ChessPosition
import com.yehsung.aingcheck.core.rules.chess.fromFen

/** 장면 하나 = 이름 · 크기 · 그리기(감싸개를 받는다 — 플랫폼마다 그림 출처가 다르다). */
class BoardScene(val group: String, val name: String, val widthDp: Int, val heightDp: Int, val content: @Composable (wrap: @Composable (Boolean, @Composable () -> Unit) -> Unit) -> Unit)

object BoardScenes {
    const val WIDTH = 390

    val gomokuUsers = listOf(
        GomokuUser("aaaaaaaa-0000-4000-8000-000000000001", "솜사탕", null, "fox", isWorking = true, isCapable = true, inMatch = false, center = "서울"),
        GomokuUser("aaaaaaaa-0000-4000-8000-000000000002", "구름빵", null, null, isWorking = false, isCapable = true, inMatch = false),
        GomokuUser("aaaaaaaa-0000-4000-8000-000000000003", "달토끼", null, "aing", isWorking = true, isCapable = true, inMatch = true),
        GomokuUser("aaaaaaaa-0000-4000-8000-000000000004", "옛폰", null, null, isWorking = true, isCapable = false, inMatch = false),
    )
    const val GOMOKU_INVITE = "11111111-0000-4000-8000-0000000000a1"
    const val GOMOKU_LIVE = "22222222-0000-4000-8000-0000000000b2"

    /** 오목 로비 장면(세션 없는 호스트 — 화면 열기가 조회를 안 낸다). [ruby] 는 공유 루비 미러(기준선은 이 숫자 하나만 바꾼다). */
    fun seedGomokuLobby(rig: BoardGameRig, ruby: Int = 100) {
        val g = rig.gomoku
        rig.sharedRuby = ruby
        g.users = gomokuUsers
        g.hasLoadedLobby = true
        g.hasLoadedInbox = true
        g.record = GomokuRecord(6, 2, 1)
        g.spectatorFeaturesEnabled = true
        g.incoming = listOf(GomokuInvite(GOMOKU_INVITE, gomokuUsers[1], 5, boardClock.addingTimeInterval(42.0)))
        g.liveMatches = listOf(GomokuLiveMatch(GOMOKU_LIVE, gomokuUsers[2], gomokuUsers[0], GomokuStake.ten, boardClock.addingTimeInterval(-95.0), watchers = 3))
        g.ranking = GomokuRankingBoard(
            entries = listOf(
                GomokuRankEntry(gomokuUsers[0].id, 1, gomokuUsers[0], 6, 2, 1, 4),
                GomokuRankEntry(gomokuUsers[2].id, 2, gomokuUsers[2], 3, 3, 0, 0),
                GomokuRankEntry(gomokuUsers[1].id, 3, gomokuUsers[1], 1, 4, 0, -3),
            ),
            me = null, recordSince = null,
        )
        g.hasLoadedRanking = true
    }

    /**
     * 오목 대국 장면 — 흑(나) 차례, 8수, 3-3 금수 자리가 선 판(흑 (6,7)(7,7) 가로 둘 · (8,8)(8,9) 세로 둘 → (8,7) 이 3-3). 마감 21초 · 관전자 3.
     */
    fun seedGomokuMatch(rig: BoardGameRig) {
        val black = listOf(6 to 7, 7 to 7, 8 to 8, 8 to 9).map { Triple(it.first, it.second, 'b') }
        val white = listOf(3 to 3, 11 to 3, 3 to 11, 11 to 12).map { Triple(it.first, it.second, 'w') }
        val now = 1_789_547_568_000L
        rig.gomoku.applyState(
            handGomokuState(
                myColor = "black", turn = "black", moveCount = 8, stones = black + white, deadlineMs = now + 21_000, serverNowMs = now,
                watchers = 3, opponentName = "라이벌",
            ),
        )
    }

    fun gomokuLobby(duelsEnabled: Boolean, ruby: Int = 100): BoardScene {
        // 스토어는 장면을 만들 때 한 번(컴포지션 밖) — 다시 그려도 같은 스토어다.
        val rig = BoardGameRig(me = null, duelsEnabled = duelsEnabled)
        seedGomokuLobby(rig, ruby)
        return BoardScene("games/gomoku", "gomoku-lobby-duels-${if (duelsEnabled) "on" else "off"}-light", WIDTH, 1900) { wrap ->
            wrap(false) { GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = {}, modifier = Modifier.size(WIDTH.dp, 1900.dp)) }
        }
    }

    fun gomokuMatch(dark: Boolean, meName: String = "나검정"): BoardScene {
        val rig = BoardGameRig(me = HAND_ME)
        seedGomokuMatch(rig)
        return BoardScene("games/gomoku", "gomoku-match-${if (dark) "dark" else "light"}", WIDTH, 900) { wrap ->
            // 앞 장면이 내려가며 부른 `gomokuScreenDidDisappear` → `stopWatching()` 이 내 판 관전자 수까지 0 으로 되돌린다(코어 규약 — 다음 상태 응답이 다시 세운다).
            // 장면마다 같은 상태 응답을 한 번 더 받아 관전자 수 3 을 세운다(폴링 한 번과 같은 일).
            androidx.compose.runtime.remember { seedGomokuMatch(rig); 0 }
            wrap(dark) { GomokuScreen(rig.games, rig.gomoku, BoardGameMe(meName, "fox", CharacterMood.Working), onLeave = {}, modifier = Modifier.size(WIDTH.dp, 900.dp)) }
        }
    }

    /**
     * 오목 판돈 시트 장면(§8-17 깃발 켜짐 · [도전]을 누른 직후) — 아무것도 안 골라진 채, 잔액 [ruby](기본 7 — 10 칸이 흐리다).
     * 기준선은 잔액 하나만 바꾼다(100 — 세 칸 다 선다). 시트 상태는 장면 밖 한 벌(다시 그려도 같은 대상).
     */
    fun gomokuStakeSheet(ruby: Int = 7): BoardScene {
        val rig = BoardGameRig(me = null)
        seedGomokuLobby(rig, ruby)
        rig.host.rubyBalance = ruby.toLong()
        val state = GomokuScreenState().also { it.stakeTarget = gomokuUsers[0] }
        return BoardScene("games/gomoku", "gomoku-stake-sheet-light", WIDTH, 900) { wrap ->
            androidx.compose.runtime.remember { state.stakeTarget = gomokuUsers[0]; 0 }
            wrap(false) { GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = {}, modifier = Modifier.size(WIDTH.dp, 900.dp), state = state) }
        }
    }

    // MARK: 체스

    val chessUsers = listOf(
        ChessUser("bbbbbbbb-0000-4000-8000-000000000001", "체스솜", null, "fox", isWorking = true, isCapable = true, inMatch = false, center = "서울"),
        ChessUser("bbbbbbbb-0000-4000-8000-000000000002", "체스구름", null, null, isWorking = false, isCapable = true, inMatch = false),
        ChessUser("bbbbbbbb-0000-4000-8000-000000000003", "체스달", null, "shiba", isWorking = true, isCapable = false, inMatch = false),
    )
    const val CHESS_INVITE = "33333333-0000-4000-8000-0000000000c1"
    const val CHESS_LIVE = "44444444-0000-4000-8000-0000000000d2"

    fun seedChessLobby(rig: BoardGameRig, ruby: Int = 100) {
        val c = rig.chess
        rig.sharedRuby = ruby
        c.users = chessUsers
        c.hasLoadedLobby = true
        c.record = ChessRecord(4, 1, 2)
        c.spectatorFeaturesEnabled = true
        c.incoming = ChessInvite(CHESS_INVITE, chessUsers[1], 5, boardClock.addingTimeInterval(42.0))
        c.liveMatches = listOf(ChessLiveMatch(CHESS_LIVE, chessUsers[0], chessUsers[2], ChessStake.ten, boardClock.addingTimeInterval(-95.0), watchers = 2))
        c.ranking = ChessRankingBoard(
            entries = listOf(
                ChessRankEntry(chessUsers[0].id, 1, chessUsers[0], 4, 1, 2, 3),
                ChessRankEntry(chessUsers[1].id, 2, chessUsers[1], 1, 1, 0, 0),
            ),
            me = null, recordSince = null,
        )
        c.hasLoadedRanking = true
    }

    fun chessLobby(duelsEnabled: Boolean, ruby: Int = 100): BoardScene {
        val rig = BoardGameRig(me = null, duelsEnabled = duelsEnabled)
        seedChessLobby(rig, ruby)
        return BoardScene("games/chess", "chess-lobby-duels-${if (duelsEnabled) "on" else "off"}-light", WIDTH, 2000) { wrap ->
            wrap(false) { ChessScreen(rig.games, rig.chess, BoardGameMe.unknown, onLeave = {}, modifier = Modifier.size(WIDTH.dp, 2000.dp)) }
        }
    }

    /** 체스 대국 장면 — 실서버 픽스처(6수 진행 국면 · 백(나) 차례 · 마지막 수 덮개). */
    fun chessMatch(dark: Boolean, meName: String = "나백"): BoardScene {
        val rig = BoardGameRig(me = "aa000000-0000-4000-8000-0000000000a1")
        rig.chess.applyState(SwiftJson.decode(ChessStatePayload.serializer(), fixtureText(CHESS_FIXTURES, "chess_state__ok_mid_since0")))
        return BoardScene("games/chess", "chess-match-${if (dark) "dark" else "light"}", WIDTH, 1100) { wrap ->
            wrap(dark) { ChessScreen(rig.games, rig.chess, BoardGameMe(meName, "fox", CharacterMood.Working), onLeave = {}, modifier = Modifier.size(WIDTH.dp, 1100.dp)) }
        }
    }

    /** 판 그림만 — 체크 덮개 · 고른 말 · 도착 점(빈 칸 점 · 잡는 칸 고리) · 흑이 아래(뒤집힌 판). [withTargets] 가 기준선 손잡이(도착 점 넷 — 덮개는 일부러 중간 톤이라 체크 칸 하나는 굵은 대조 문턱 아래다). */
    fun chessBoardOverlays(withTargets: Boolean = true): BoardScene =
        BoardScene("games/chess", "chess-board-overlays", 320, 320) { wrap ->
            val position = requireNotNull(ChessPosition.fromFen("r1bqkb1r/pppp1ppp/2n2n2/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"))
            fun sq(n: String) = ChessSquare.parse(n)!!
            wrap(false) {
                ChessBoardCanvas(
                    ChessBoardPicture(
                        position = position, whiteAtBottom = false, lastMove = sq("g8") to sq("f6"),
                        selected = sq("b5"), targets = if (withTargets) setOf(sq("c6"), sq("a4"), sq("c4"), sq("d3")) else emptySet(), checkSquare = sq("e8"),
                    ),
                    side = 320.dp,
                )
            }
        }
}
