// 원본: Sources/CheckMobileKit/Messages/MessagesTab.swift @ 3bd04bd (consumeRoute → MessagesListRules.destinations(for:) → 경로 push)
// 6차 int-h 이월 "MessagesListRules.destinations 를 AingRoute 에 잇기": 셸 라우트 → 메시지 탭 경로가 코어 규칙 한 곳을 지나고,
// 셸의 RoutePlans(목적지 쌓기)와 같은 답을 내는지 잰다 — 둘이 갈리면 알림 탭이 다른 대화를 연다.
package com.yehsung.aingcheck.android.screens.messages

import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.nav.RoutePlans
import com.yehsung.aingcheck.android.routing.AingMiniGame
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.routing.AingTab
import com.yehsung.aingcheck.android.routing.RankingsBoard
import com.yehsung.aingcheck.core.stores.messages.MessagesRouteTarget
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MessagesRoutingTest {
    private val peer = "d0000000-0000-4000-8000-0000000000b1"

    /** 모든 라우트 모양 하나씩(빠짐없는 when 과 같은 목록 — 라우트를 더하면 여기도 더한다). */
    private val all: List<AingRoute> = listOf(
        AingRoute.Now, AingRoute.Messages, AingRoute.Message(peer), AingRoute.Rankings(RankingsBoard.TOKENS), AingRoute.Games,
        AingRoute.MiniGame(AingMiniGame.FLAPPY), AingRoute.GomokuLobby, AingRoute.GomokuInvite("m1"), AingRoute.GomokuMatch(null),
        AingRoute.ChessLobby, AingRoute.ChessInvite("c1"), AingRoute.ChessMatch("c2"), AingRoute.Me, AingRoute.Shop,
        AingRoute.Feedback(null), AingRoute.Settings,
    )

    @Test
    fun messagesRoutesGoThroughTheStoreRule() {
        assertEquals(MessagesRouteTarget.list, MessagesRouting.target(AingRoute.Messages))
        assertEquals(MessagesRouteTarget.conversation(peer), MessagesRouting.target(AingRoute.Message(peer)))
        assertEquals(emptyList<Any>(), MessagesRouting.children(AingRoute.Messages))
        assertEquals(listOf<Any>(Dest.Conversation(peer)), MessagesRouting.children(AingRoute.Message(peer)))
    }

    @Test
    fun otherTabsAreNotMessagesRoutes() {
        for (route in all.filter { it.tab != AingTab.MESSAGES }) {
            assertNull("$route 는 메시지 탭 라우트가 아니다", MessagesRouting.target(route))
            assertNull(MessagesRouting.children(route))
        }
    }

    @Test
    fun agreesWithShellRoutePlans() {
        // 셸이 쌓는 자식 목적지 = 코어 규칙이 정한 경로(메시지 탭 라우트 전부). 셸이 이 함수를 부르게 바꾸는 패치는 조정자 몫(assembly.md).
        for (route in all.filter { it.tab == AingTab.MESSAGES }) {
            val plan = RoutePlans.plan(route)
            assertEquals(Dest.MessagesList, plan.root)
            assertEquals("$route", plan.children, MessagesRouting.children(route))
        }
        // 딥링크 글자 → 경로까지 한 줄(알림 탭의 실제 길).
        val parsed = AingRoute.parse("aingcheck://message/$peer")!!
        assertEquals(listOf<Any>(Dest.Conversation(peer)), MessagesRouting.children(parsed))
    }
}
