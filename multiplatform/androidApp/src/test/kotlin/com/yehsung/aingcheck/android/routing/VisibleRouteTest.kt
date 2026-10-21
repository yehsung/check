// E§6.4 "앞 + 보고 있는 대화만 숨김"의 '앞' 문: VisibleRoute.viewing() 은 앱이 앞일 때만 화면의 라우트를 낸다.
// 순수 판정(NotificationSpecs.decide)의 viewing 인자는 NotificationSpecTest 가, 서비스가 그 값을 넘기는 자리는
// AingMessagingServiceTest 가 잰다. 여기서는 앞/뒤 × 같은 대화/다른 대화 표.
package com.yehsung.aingcheck.android.routing

import com.yehsung.aingcheck.android.push.NotificationSpecs
import com.yehsung.aingcheck.android.push.PushDecision
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class VisibleRouteTest {
    private val conversation = AingRoute.Message("p1")

    @Test
    fun viewingOnlyWhileForeground() {
        val v = VisibleRoute()
        v.setRoute(conversation)
        assertNull("뒤인데 보고 있다고 읽혔다", v.viewing())
        v.setForeground(true)
        assertEquals(conversation, v.viewing())
        v.setForeground(false)
        assertNull("뒤로 간 뒤에도 보고 있다고 읽혔다", v.viewing())
        // 화면의 라우트(마지막으로 그린 것)는 뒤로 가도 그대로다 — 숨김을 막는 것은 앞/뒤 문뿐이다.
        assertEquals(conversation, v.route.value)
    }

    /** 앞/뒤 × 같은 대화/다른 대화 → 게시 여부(기대값은 글자 표). */
    @Test
    fun sameConversationIsHiddenOnlyInFront() {
        val table = listOf(
            // 앞,   알림 상대, 결과
            Triple(true, "p1", "Hide"),
            Triple(true, "p2", "Post"),
            Triple(false, "p1", "Post"),
            Triple(false, "p2", "Post"),
        )
        for ((front, peer, want) in table) {
            val v = VisibleRoute()
            v.setRoute(conversation)
            v.setForeground(front)
            val decision = NotificationSpecs.decide(mapOf("type" to "message", "peer_id" to peer, "body" to "b"), v.viewing())
            val got = when (decision) {
                is PushDecision.Hide -> "Hide"
                is PushDecision.Post -> "Post"
                is PushDecision.Drop -> "Drop"
            }
            assertEquals("front=$front peer=$peer", want, got)
        }
    }
}
