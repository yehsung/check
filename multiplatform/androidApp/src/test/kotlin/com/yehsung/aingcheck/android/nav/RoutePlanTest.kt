package com.yehsung.aingcheck.android.nav

import com.yehsung.aingcheck.android.routing.AingMiniGame
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.routing.AingTab
import com.yehsung.aingcheck.android.routing.RankingsBoard
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RoutePlanTest {
    private val all: List<AingRoute> = buildList {
        add(AingRoute.Now); add(AingRoute.Messages); add(AingRoute.Message("abc-123"))
        RankingsBoard.entries.forEach { add(AingRoute.Rankings(it)) }
        add(AingRoute.Games); AingMiniGame.entries.forEach { add(AingRoute.MiniGame(it)) }
        add(AingRoute.GomokuLobby); add(AingRoute.GomokuInvite("m9")); add(AingRoute.GomokuMatch(null)); add(AingRoute.GomokuMatch("m9"))
        add(AingRoute.ChessLobby); add(AingRoute.ChessInvite("c7")); add(AingRoute.ChessMatch(null)); add(AingRoute.ChessMatch("c7"))
        add(AingRoute.Me); add(AingRoute.Shop); add(AingRoute.Feedback(null)); add(AingRoute.Feedback("77")); add(AingRoute.Settings)
    }

    /** 라우트를 열어 맨 위에 보이는 목적지가 다시 같은 라우트로 읽힌다(푸시 숨김 판정이 이 짝에 기댄다). */
    @Test
    fun planTopReadsBackAsTheSameRoute() {
        // kotlin-reflect 없이: 하위형은 전부 AingRoute 안에 선언돼 있다(Java 리플렉션의 declaredClasses).
        val declared = AingRoute::class.java.declaredClasses.filter { AingRoute::class.java.isAssignableFrom(it) }.toSet()
        assertEquals("Swift 13 + 체스 3", 16, declared.size)
        assertEquals(declared, all.map { it.javaClass }.toSet())
        for (route in all) {
            val plan = RoutePlans.plan(route)
            assertEquals("$route 의 탭", route.tab, plan.tab)
            assertEquals("$route 를 연 화면이 다른 라우트로 읽힌다", route, RoutePlans.routeOf(plan.top))
        }
    }

    @Test
    fun childrenStackOnTheTabRoot() {
        assertEquals(RoutePlan(AingTab.MESSAGES, Dest.MessagesList, listOf(Dest.Conversation("p"))), RoutePlans.plan(AingRoute.Message("p")))
        assertEquals(RoutePlan(AingTab.GAMES, Dest.GamesHome, listOf(Dest.Chess("invite", "c"))), RoutePlans.plan(AingRoute.ChessInvite("c")))
        // 순위 세그먼트는 자식이 아니라 뿌리 인자다(기본과 다르면 뿌리를 갈아 끼운다).
        assertEquals(RoutePlan(AingTab.RANKINGS, Dest.RankingsHome("tokens"), emptyList()), RoutePlans.plan(AingRoute.Rankings(RankingsBoard.TOKENS)))
        assertEquals(Dest.RankingsHome("league"), RoutePlans.defaultRoot(AingTab.RANKINGS))
    }

    @Test
    fun sheetsAndUnknownSectionsAreNotRoutes() {
        assertNull(RoutePlans.routeOf(Dest.MegaphoneSheet))
        assertNull(RoutePlans.routeOf(Dest.Gomoku("watch", "m")))
        assertNull(RoutePlans.routeOf(Dest.Gomoku("invite", null)))
        assertNull(RoutePlans.routeOf(Dest.Conversation("bad id")))
        assertNull(RoutePlans.routeOf(null))
    }
}
