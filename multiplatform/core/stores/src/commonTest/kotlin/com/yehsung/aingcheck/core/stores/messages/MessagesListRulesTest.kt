// 원본: Sources/CheckMobileKit/Messages/MessagesRules.swift:590-641(MessagesDestination · MessagesListRules) @ 1b8260d — Swift 쪽 표 시험은
//       라우터 시험(RouterTests)이 묶어서 쟀다. 여기서는 순수 함수만 표로 잰다.
package com.yehsung.aingcheck.core.stores.messages

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class MessagesListRulesTest {
    @Test
    fun destinationsForMessagesRoutes() {
        assertEquals(emptyList(), MessagesListRules.destinations(MessagesRouteTarget.list), "목록 라우트는 빈 경로(목록 맨 위)")
        assertEquals(listOf(MessagesDestination.conversation("peer-a")), MessagesListRules.destinations(MessagesRouteTarget.conversation("peer-a")))
        assertNull(MessagesListRules.destinations(null), "메시지 탭 라우트가 아니면 null(조용히 목록으로 접지 않는다)")
    }

    @Test
    fun subtitleAndCountBadge() {
        assertNull(MessagesListRules.subtitle(0))
        assertEquals("안 읽은 메시지 3", MessagesListRules.subtitle(3))
        assertNull(MessagesListRules.countBadge(isUnread = false, count = 5))
        assertEquals("1", MessagesListRules.countBadge(isUnread = true, count = 0), "점이 있으면 최소 1")
        assertEquals("1", MessagesListRules.countBadge(isUnread = true, count = null))
        assertEquals("99", MessagesListRules.countBadge(isUnread = true, count = 99))
        assertEquals("99+", MessagesListRules.countBadge(isUnread = true, count = 100))
    }
}
