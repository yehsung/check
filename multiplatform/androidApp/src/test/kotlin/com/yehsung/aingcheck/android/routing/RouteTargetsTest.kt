// 원본: Tests/CheckMobileKitTests/AingRouteTests.swift(미니게임 열거 짝) · PushPayloadTests.swift(route) @ 3bd04bd
// 조립 변환(AingRoute ↔ PhoneRouteTarget · 판정 → 푸시 내용)의 빠짐없음과 왕복을 잰다.
package com.yehsung.aingcheck.android.routing

import com.yehsung.aingcheck.android.push.NotificationSpecs
import com.yehsung.aingcheck.android.push.PushDecision
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.games.GamesRouteRequest
import com.yehsung.aingcheck.feature.phone.push.PhonePushContent
import com.yehsung.aingcheck.feature.phone.routing.PhoneRouteTarget
import com.yehsung.aingcheck.feature.phone.routing.PhoneTab
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RouteTargetsTest {
    private val routes: List<AingRoute> = listOf(
        AingRoute.Now, AingRoute.Messages, AingRoute.Message("p-1"),
        AingRoute.Rankings(RankingsBoard.LEAGUE), AingRoute.Rankings(RankingsBoard.TOKENS), AingRoute.Rankings(RankingsBoard.MINIGAME),
        AingRoute.Games, AingRoute.MiniGame(AingMiniGame.TIMING), AingRoute.MiniGame(AingMiniGame.FLAPPY), AingRoute.MiniGame(AingMiniGame.TETRIS),
        AingRoute.GomokuLobby, AingRoute.GomokuInvite("m-1"), AingRoute.GomokuMatch(null), AingRoute.GomokuMatch("m-2"),
        AingRoute.ChessLobby, AingRoute.ChessInvite("c-1"), AingRoute.ChessMatch(null), AingRoute.ChessMatch("c-2"),
        AingRoute.Me, AingRoute.Shop, AingRoute.Feedback(null), AingRoute.Feedback("r-1"), AingRoute.Settings,
    )

    @Test
    fun everyRouteRoundTripsAndKeepsItsTab() {
        for (route in routes) {
            val target = RouteTargets.target(route)
            assertEquals("$route", route, RouteTargets.route(target))
            assertEquals("$route 의 탭", RouteTargets.tab(route.tab), target.tab)
        }
        for (tab in AingTab.entries) assertEquals(tab, RouteTargets.tab(RouteTargets.tab(tab)))
        assertNull("게임 탭 밖 요청은 셸 라우트가 없다", RouteTargets.route(PhoneRouteTarget.Games(GamesRouteRequest.Other)))
        assertNull("이 빌드에 링크가 없는 미니게임(길건너)", RouteTargets.route(PhoneRouteTarget.Games(GamesRouteRequest.MiniGame(MiniGameKind.crossy))))
        assertNull("모양이 틀린 id 는 라우트가 되지 않는다", RouteTargets.route(PhoneRouteTarget.Message("../x")))
        assertEquals(PhoneTab.entries.size, AingTab.entries.size)
    }

    @Test
    fun miniGameLinksAndPhoneCasesWidenTogether() {
        // INV-AingRoute-67c8ae7d: 딥링크 미니게임 열거와 MiniGameKind.phoneCases 는 1:1 — 한쪽만 넓히면 오배달·링크 소실.
        assertEquals(MiniGameKind.phoneCases.toSet(), AingMiniGame.entries.map(RouteTargets::miniGame).toSet())
        assertEquals(AingMiniGame.entries.size, MiniGameKind.phoneCases.size)
        for (kind in MiniGameKind.entries) {
            assertEquals("$kind", kind in MiniGameKind.phoneCases, RouteTargets.miniGame(kind) != null)
        }
        // 솔로 테트리스 링크(`games/tetris`)는 엔진의 솔로 테트리스다 — 1:1 대결로 가로채지 않는다(INV-MobileAppModel-14155396).
        assertEquals(PhoneRouteTarget.Games(GamesRouteRequest.MiniGame(MiniGameKind.tetris)), RouteTargets.target(AingRoute.parse("aingcheck://games/tetris")!!))
    }

    @Test
    fun decisionsBecomeCoordinatorContentWithoutParsingTwice() {
        fun content(data: Map<String, String>, viewing: AingRoute? = null) = RouteTargets.content(NotificationSpecs.decide(data, viewing))
        assertEquals(PhonePushContent.Message("p-1"), content(mapOf("type" to "message", "peer_id" to "P-1")))
        assertEquals(PhonePushContent.Message("p-1"), content(mapOf("type" to "message", "peer_id" to "p-1"), viewing = AingRoute.Message("p-1")))
        assertEquals(PhonePushContent.GomokuInvite("m-1"), content(mapOf("type" to "gomoku_invite", "match_id" to "m-1")))
        assertEquals(PhonePushContent.ChessInvite("c-1"), content(mapOf("type" to "chess_invite", "match_id" to "c-1")))
        assertEquals(PhonePushContent.FeedbackReply("r-1"), content(mapOf("type" to "feedback_reply", "report_id" to "r-1")))
        assertEquals(PhonePushContent.FeedbackReply(null), content(mapOf("type" to "feedback_reply")))
        assertEquals(PhonePushContent.WorkCheck(null), content(mapOf("type" to "work_check", "session_id" to "s-1")))
        assertNull("버린 메시지는 조정자에 가지 않는다", content(mapOf("type" to "tetris_invite", "match_id" to "t-1")))
        assertNull(RouteTargets.content(PushDecision.Drop("x")))
        assertEquals(PhonePushContent.GomokuInvite("m-1"), RouteTargets.acceptContent(AingRoute.GomokuInvite("m-1")))
        assertEquals(PhonePushContent.ChessInvite("c-1"), RouteTargets.acceptContent(AingRoute.ChessInvite("c-1")))
        assertNull(RouteTargets.acceptContent(AingRoute.Message("p-1")))
    }
}
