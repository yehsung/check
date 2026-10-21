// 라우트 ↔ 목적지(순수 — JVM 시험이 닿는다). 탭마다 자기 백스택(iOS 탭별 NavigationStack, E§3): 라우트를 열면
// 그 탭으로 가서 탭 뿌리 위에 자식 목적지를 쌓는다. 빠짐없는 when — 라우트를 더하면 여기가 컴파일로 막는다(E§3 규약).
package com.yehsung.aingcheck.android.nav

import com.yehsung.aingcheck.android.routing.AingMiniGame
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.routing.AingTab
import com.yehsung.aingcheck.android.routing.RankingsBoard

/** 라우트 하나를 여는 방법: [tab] 으로 가서 뿌리를 [root] 로 두고 [children] 을 차례로 쌓는다. */
data class RoutePlan(val tab: AingTab, val root: Any, val children: List<Any>) {
    /** 맨 위에 보일 목적지. */
    val top: Any get() = children.lastOrNull() ?: root
}

object RoutePlans {
    fun graphOf(tab: AingTab): Any = when (tab) {
        AingTab.NOW -> Dest.NowGraph
        AingTab.MESSAGES -> Dest.MessagesGraph
        AingTab.RANKINGS -> Dest.RankingsGraph
        AingTab.GAMES -> Dest.GamesGraph
        AingTab.ME -> Dest.MeGraph
    }

    /** 탭 그래프의 시작 목적지(탭 막대로 처음 들어갈 때의 뿌리). */
    fun defaultRoot(tab: AingTab): Any = when (tab) {
        AingTab.NOW -> Dest.NowHome
        AingTab.MESSAGES -> Dest.MessagesList
        AingTab.RANKINGS -> Dest.RankingsHome()
        AingTab.GAMES -> Dest.GamesHome
        AingTab.ME -> Dest.MeHome
    }

    fun plan(route: AingRoute): RoutePlan = when (route) {
        AingRoute.Now -> RoutePlan(AingTab.NOW, Dest.NowHome, emptyList())
        AingRoute.Messages -> RoutePlan(AingTab.MESSAGES, Dest.MessagesList, emptyList())
        is AingRoute.Message -> RoutePlan(AingTab.MESSAGES, Dest.MessagesList, listOf(Dest.Conversation(route.peerId)))
        is AingRoute.Rankings -> RoutePlan(AingTab.RANKINGS, Dest.RankingsHome(route.board.raw), emptyList())
        AingRoute.Games -> RoutePlan(AingTab.GAMES, Dest.GamesHome, emptyList())
        is AingRoute.MiniGame -> games(Dest.MiniGame(route.game.raw))
        AingRoute.GomokuLobby -> games(Dest.Gomoku(GameSection.LOBBY.raw))
        is AingRoute.GomokuInvite -> games(Dest.Gomoku(GameSection.INVITE.raw, route.matchId))
        is AingRoute.GomokuMatch -> games(Dest.Gomoku(GameSection.MATCH.raw, route.matchId))
        AingRoute.ChessLobby -> games(Dest.Chess(GameSection.LOBBY.raw))
        is AingRoute.ChessInvite -> games(Dest.Chess(GameSection.INVITE.raw, route.matchId))
        is AingRoute.ChessMatch -> games(Dest.Chess(GameSection.MATCH.raw, route.matchId))
        AingRoute.Me -> RoutePlan(AingTab.ME, Dest.MeHome, emptyList())
        AingRoute.Shop -> me(Dest.Shop)
        is AingRoute.Feedback -> me(Dest.Feedback(route.reportId))
        AingRoute.Settings -> me(Dest.Settings)
    }

    private fun games(child: Any) = RoutePlan(AingTab.GAMES, Dest.GamesHome, listOf(child))
    private fun me(child: Any) = RoutePlan(AingTab.ME, Dest.MeHome, listOf(child))

    /**
     * 목적지 → 라우트(지금 보이는 화면 판정 — 푸시 숨김). 라우트로 나타낼 수 없는 목적지(시트·관전·순위 등)는 null.
     * `routeOf(plan(r).top) == r` 가 모든 라우트에서 성립한다(RoutePlanTest).
     */
    fun routeOf(dest: Any?): AingRoute? = when (dest) {
        Dest.NowHome -> AingRoute.Now
        Dest.MessagesList -> AingRoute.Messages
        is Dest.Conversation -> AingRoute.safeId(dest.peerId)?.let { AingRoute.Message(it) }
        is Dest.RankingsHome -> RankingsBoard.fromRaw(dest.board)?.let { AingRoute.Rankings(it) }
        Dest.GamesHome -> AingRoute.Games
        is Dest.MiniGame -> AingMiniGame.fromRaw(dest.game)?.let { AingRoute.MiniGame(it) }
        is Dest.Gomoku -> boardRoute(dest.section, dest.matchId, AingRoute.GomokuLobby, AingRoute::GomokuInvite, AingRoute::GomokuMatch)
        is Dest.Chess -> boardRoute(dest.section, dest.matchId, AingRoute.ChessLobby, AingRoute::ChessInvite, AingRoute::ChessMatch)
        Dest.MeHome -> AingRoute.Me
        Dest.Shop -> AingRoute.Shop
        is Dest.Feedback -> AingRoute.Feedback(dest.reportId)
        Dest.Settings -> AingRoute.Settings
        else -> null
    }

    private fun boardRoute(
        section: String,
        matchId: String?,
        lobby: AingRoute,
        invite: (String) -> AingRoute,
        match: (String?) -> AingRoute,
    ): AingRoute? = when (section) {
        GameSection.LOBBY.raw -> lobby
        GameSection.INVITE.raw -> matchId?.let(invite)
        GameSection.MATCH.raw -> match(matchId)
        else -> null
    }
}
