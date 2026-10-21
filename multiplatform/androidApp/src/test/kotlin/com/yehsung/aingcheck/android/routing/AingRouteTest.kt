// 원본: Tests/CheckMobileKitTests/BaseRouterTests.swift @ ios-1011(988609b) — 왕복·모양 판정을 그대로 옮기고 체스 라우트를 더했다.
package com.yehsung.aingcheck.android.routing

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AingRouteTest {
    /** 모든 라우트 값(열거마다 하나 이상 — 새 값을 더하면 아래 when 이 컴파일로 막는다). */
    private val all: List<AingRoute> = buildList {
        add(AingRoute.Now); add(AingRoute.Messages); add(AingRoute.Message("abc-123"))
        RankingsBoard.entries.forEach { add(AingRoute.Rankings(it)) }
        add(AingRoute.Games); AingMiniGame.entries.forEach { add(AingRoute.MiniGame(it)) }
        add(AingRoute.GomokuLobby); add(AingRoute.GomokuInvite("m9")); add(AingRoute.GomokuMatch(null)); add(AingRoute.GomokuMatch("m9"))
        add(AingRoute.ChessLobby); add(AingRoute.ChessInvite("c7")); add(AingRoute.ChessMatch(null)); add(AingRoute.ChessMatch("c7"))
        add(AingRoute.Me); add(AingRoute.Shop); add(AingRoute.Feedback(null)); add(AingRoute.Feedback("77")); add(AingRoute.Settings)
    }

    @Test
    fun everyRouteRoundTripsThroughItsUrl() {
        // 열거가 빠짐없는지: 모든 sealed 하위형이 목록에 하나 이상 있다(빠진 하위형이 있으면 왕복 시험이 그 값을 안 잰다).
        // kotlin-reflect 없이: 하위형은 전부 AingRoute 안에 선언돼 있다(Java 리플렉션의 declaredClasses).
        val declared = AingRoute::class.java.declaredClasses.filter { AingRoute::class.java.isAssignableFrom(it) }.toSet()
        assertEquals("Swift 13 + 체스 3", 16, declared.size)
        assertEquals(declared, all.map { it.javaClass }.toSet())
        for (route in all) {
            assertEquals("왕복 실패: $route → ${route.url}", route, AingRoute.parse(route.url))
        }
    }

    @Test
    fun knownUrlsParseLikeSwift() {
        assertEquals(AingRoute.Message("abc-123"), AingRoute.parse("aingcheck://message/abc-123"))
        assertEquals(AingRoute.GomokuInvite("m9"), AingRoute.parse("aingcheck://gomoku/invite/m9"))
        assertEquals(AingRoute.GomokuMatch("m9"), AingRoute.parse("aingcheck://gomoku/match/m9"))
        assertEquals(AingRoute.Feedback("77"), AingRoute.parse("aingcheck://feedback/77"))
        assertEquals(AingRoute.Now, AingRoute.parse("aingcheck://now"))
        assertEquals(AingRoute.Message("abc"), AingRoute.parse("aingcheck://messages/abc"))
        assertEquals(AingRoute.Rankings(RankingsBoard.LEAGUE), AingRoute.parse("aingcheck://rankings"))
        assertEquals(AingRoute.GomokuLobby, AingRoute.parse("aingcheck://gomoku"))
        assertEquals(AingRoute.Feedback(null), AingRoute.parse("aingcheck://me/feedback"))
        // 스킴·머리 대소문자, 질의·조각은 경로가 아니다.
        assertEquals(AingRoute.Shop, AingRoute.parse("AINGCHECK://ME/SHOP?x=1#y"))
        // Android 판: 체스 라우트.
        assertEquals(AingRoute.ChessInvite("c7"), AingRoute.parse("aingcheck://chess/invite/c7"))
        assertEquals(AingRoute.ChessMatch(null), AingRoute.parse("aingcheck://chess/match"))
    }

    @Test
    fun demoPathsShareTheSameParser() {
        assertEquals(AingRoute.Message("p1"), AingRoute.parsePath("messages/p1"))
        assertEquals(AingRoute.GomokuLobby, AingRoute.parsePath("games/gomoku/lobby"))
        assertEquals(AingRoute.ChessMatch(null), AingRoute.parsePath("games/chess/match"))
        assertEquals(AingRoute.Feedback(null), AingRoute.parsePath("me/feedback"))
    }

    @Test
    fun malformedUrlsAreNullNotNow() {
        assertNull(AingRoute.parse("https://message/abc"))
        assertNull(AingRoute.parse("aingcheck://unknown"))
        assertNull(AingRoute.parse("aingcheck://message"))
        assertNull(AingRoute.parse("aingcheck://message/a/b"))
        assertNull(AingRoute.parse("aingcheck://message/.."))
        assertNull(AingRoute.parse("aingcheck://message/a%20b"))
        assertNull(AingRoute.parse("aingcheck://message/%2E%2E"))
        assertNull(AingRoute.parse("aingcheck://rankings/weekly"))
        assertNull(AingRoute.parse("aingcheck://message/" + "a".repeat(65)))
        assertNull(AingRoute.parse("aingcheck://gomoku/invite"))
        assertNull(AingRoute.parse("aingcheck://chess/watch/c7"))
        assertNull(AingRoute.parse("aingcheck://message/%zz"))
        assertNull(AingRoute.parse(""))
    }

    @Test
    fun idBoundaryIs64Ascii() {
        val ok = "a".repeat(64)
        assertEquals(AingRoute.Message(ok), AingRoute.parse("aingcheck://message/$ok"))
        // 퍼센트로 쓴 영문은 풀어서 본다(Swift path(percentEncoded: false) 와 같다).
        assertEquals(AingRoute.Message("A1"), AingRoute.parse("aingcheck://message/%41%31"))
        assertNull(AingRoute.safeId("가나"))
    }

    @Test
    fun tabsFollowSwiftOrder() {
        assertEquals(listOf("지금", "메시지", "순위", "게임", "나"), AingTab.entries.map { it.title })
        assertEquals(AingTab.GAMES, AingRoute.ChessInvite("x").tab)
        assertEquals(AingTab.ME, AingRoute.Settings.tab)
    }
}
