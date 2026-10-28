// 원본: Sources/CheckMobileKit/Games/GamesChessScreen.swift(진입) · Sources/CheckMobileKit/Games/GamesStore.swift(chessScreenDidAppear — focusMatchID 는 늘 null) @ 3bd04bd
//
// 체스 목적지(Dest.Chess)의 **진입 함수와 라우트 상수** — 화면 본문은 ui 모듈의 [ChessScreen](한 화면 안 탭). 내비 배선은 조립(K11)이 이 함수로 바꾼다.
//  ① 섹션 → 진입 동작: 체스는 받은함 RPC 가 없고 내 판은 코어가 로비 `me.active_match_id` 로 스스로 연다(초점 인자가 없다 — Swift `chessScreenDidAppear` 는
//     focusMatchID 로 늘 null 을 넘긴다). 관전 · 순위 · 로봇만 섹션이 뜻을 가진다.
//  ② Android 뒤로가기 → [ChessBackPlan](덮개 · 로봇 화면 닫기 · 사람과의 판이면 확인 · 관전 나가기 · 떠나기). 승격 고르기는 `cancelPromotion()` 하나로만 닫힌다.
package com.yehsung.aingcheck.android.screens.games.chess

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.nav.GameSection
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.chess.startWatching
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.ui.games.chess.ChessBackPlan
import com.yehsung.aingcheck.ui.games.chess.ChessLobbyRoster
import com.yehsung.aingcheck.ui.games.chess.ChessScreen
import com.yehsung.aingcheck.ui.games.chess.handleBack
import com.yehsung.aingcheck.ui.games.chess.rememberChessScreenState
import com.yehsung.aingcheck.ui.games.gomoku.BoardBackStep
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe

/** 체스 목적지 라우트 상수 — [Dest.Chess] 를 만드는 한 자리. */
object ChessRoute {
    fun lobby(): Dest.Chess = Dest.Chess(GameSection.LOBBY.raw)
    fun match(): Dest.Chess = Dest.Chess(GameSection.MATCH.raw)
    fun watch(matchID: String): Dest.Chess = Dest.Chess(GameSection.WATCH.raw, matchID)
    fun ranking(): Dest.Chess = Dest.Chess(GameSection.RANKING.raw)
    fun robot(): Dest.Chess = Dest.Chess(GameSection.AI.raw)
}

object ChessEntry {
    sealed interface Action {
        data object Lobby : Action
        data class Watch(val matchID: String) : Action
        data object Ranking : Action
        data object Robot : Action
    }

    /** 모르는 섹션 · 초점 섹션(INVITE · MATCH — 체스는 코어가 내 판을 스스로 연다)은 로비로 접는다. */
    fun action(section: String, matchId: String?): Action = when (GameSection.entries.firstOrNull { it.raw == section }) {
        GameSection.WATCH -> matchId?.let { Action.Watch(it) } ?: Action.Lobby
        GameSection.RANKING -> Action.Ranking
        GameSection.AI -> Action.Robot
        GameSection.LOBBY, GameSection.INVITE, GameSection.MATCH, null -> Action.Lobby
    }
}

@Composable
fun ChessDestination(
    dest: Dest.Chess,
    games: GamesStore,
    chess: ChessStore,
    me: BoardGameMe,
    onLeave: () -> Unit,
    modifier: Modifier = Modifier,
    onTabBarHidden: (Boolean) -> Unit = {},
) {
    val state = rememberChessScreenState()
    val roster = remember(chess) { ChessLobbyRoster(chess) }
    val action = remember(dest) { ChessEntry.action(dest.section, dest.matchId) }
    remember(dest) {
        when (action) {
            ChessEntry.Action.Ranking -> state.rankingExpanded = true
            ChessEntry.Action.Robot -> state.robotScreenOpen = true
            else -> Unit
        }
        true
    }
    LaunchedEffect(dest) {
        if (action is ChessEntry.Action.Watch) chess.startWatching(action.matchID)
    }
    BackHandler(enabled = ChessBackPlan.step(state, chess) != BoardBackStep.Leave) { state.handleBack(chess) }
    ChessScreen(games, chess, me, onLeave, modifier, roster = roster, state = state, onTabBarHidden = onTabBarHidden)
}
