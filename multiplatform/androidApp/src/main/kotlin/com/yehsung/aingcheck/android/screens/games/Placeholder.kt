// 자리표시 — 게임 탭(E§3.2). 주인: 허브·미니게임·테트리스 W4-b, 오목·체스 W4-a(각자 screens/games/<게임>/ 하위 폴더에 낸다).
// 셸(W1-g)이 둔다.
package com.yehsung.aingcheck.android.screens.games

import androidx.compose.runtime.Composable
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.nav.GameSection
import com.yehsung.aingcheck.android.nav.RoutePlans
import com.yehsung.aingcheck.android.routing.AingMiniGame
import com.yehsung.aingcheck.android.shell.PlaceholderLink
import com.yehsung.aingcheck.android.shell.PlaceholderScreen

@Composable
fun GamesHomePlaceholder(open: (Any) -> Unit) = PlaceholderScreen(
    "게임", "W4-b 허브", detail = RoutePlans.routeOf(Dest.GamesHome)?.url,
    links = AingMiniGame.entries.map { game -> PlaceholderLink("미니게임 ${game.raw}") { open(Dest.MiniGame(game.raw)) } } +
        listOf(
            PlaceholderLink("오목") { open(Dest.Gomoku(GameSection.LOBBY.raw)) },
            PlaceholderLink("체스") { open(Dest.Chess(GameSection.LOBBY.raw)) },
            PlaceholderLink("테트리스 1:1") { open(Dest.TetrisDuel) },
        ),
)

@Composable
fun MiniGamePlaceholder(game: String) =
    PlaceholderScreen("미니게임", "W4-b 미니게임", detail = RoutePlans.routeOf(Dest.MiniGame(game))?.url ?: "game=$game")

@Composable
fun GomokuPlaceholder(dest: Dest.Gomoku, open: (Any) -> Unit) = PlaceholderScreen(
    "오목", "W4-a 오목", detail = RoutePlans.routeOf(dest)?.url ?: "section=${dest.section} match=${dest.matchId}",
    links = listOf(PlaceholderLink("판돈") { open(Dest.StakeSheet("gomoku")) }),
)

@Composable
fun ChessPlaceholder(dest: Dest.Chess, open: (Any) -> Unit) = PlaceholderScreen(
    "체스", "W4-a 체스", detail = RoutePlans.routeOf(dest)?.url ?: "section=${dest.section} match=${dest.matchId}",
    links = listOf(PlaceholderLink("판돈") { open(Dest.StakeSheet("chess")) }),
)

@Composable
fun TetrisDuelPlaceholder(open: (Any) -> Unit) = PlaceholderScreen(
    "테트리스 1:1", "W4-b 테트리스",
    links = listOf(PlaceholderLink("판돈") { open(Dest.StakeSheet("tetris")) }),
)

@Composable
fun StakeSheetPlaceholder(game: String) = PlaceholderScreen("판돈 고르기", "W4-a·b", detail = "game=$game · 판돈 목록은 서버값")
