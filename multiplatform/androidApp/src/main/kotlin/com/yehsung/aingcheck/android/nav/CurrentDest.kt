// 백스택 항목 → 목적지 값(라우트로 되돌릴 수 있는 것만). VisibleRoute(푸시 숨김)가 쓴다.
package com.yehsung.aingcheck.android.nav

import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.toRoute

object CurrentDest {
    fun of(entry: NavBackStackEntry): Any? {
        val d = entry.destination
        return when {
            d.hasRoute<Dest.NowHome>() -> Dest.NowHome
            d.hasRoute<Dest.MessagesList>() -> Dest.MessagesList
            d.hasRoute<Dest.Conversation>() -> entry.toRoute<Dest.Conversation>()
            d.hasRoute<Dest.RankingsHome>() -> entry.toRoute<Dest.RankingsHome>()
            d.hasRoute<Dest.GamesHome>() -> Dest.GamesHome
            d.hasRoute<Dest.MiniGame>() -> entry.toRoute<Dest.MiniGame>()
            d.hasRoute<Dest.Gomoku>() -> entry.toRoute<Dest.Gomoku>()
            d.hasRoute<Dest.Chess>() -> entry.toRoute<Dest.Chess>()
            d.hasRoute<Dest.MeHome>() -> Dest.MeHome
            d.hasRoute<Dest.Shop>() -> Dest.Shop
            d.hasRoute<Dest.Feedback>() -> entry.toRoute<Dest.Feedback>()
            d.hasRoute<Dest.Settings>() -> Dest.Settings
            else -> null
        }
    }
}
