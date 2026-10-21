// W1-g 완료 기준 ③: 앱이 시작하면 채널 다섯이 계약 id·중요도로 있다. 그리고 사양 → 게시까지(PendingIntent 의 라우트·수락 증표).
package com.yehsung.aingcheck.android.push

import android.app.NotificationManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.yehsung.aingcheck.android.app.AingApplication
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.routing.RouteIntents
import com.yehsung.aingcheck.android.routing.RouteRequest
import com.yehsung.aingcheck.android.shell.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class NotificationChannelsTest {
    private val app get() = ApplicationProvider.getApplicationContext<AingApplication>()
    private val manager get() = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    @Test
    fun fiveChannelsWithContractIds() {
        val channels = manager.notificationChannels.associateBy { it.id }
        assertEquals(setOf("message", "gomoku_invite", "chess_invite", "feedback_reply", "work_check"), channels.keys)
        assertEquals(NotificationManager.IMPORTANCE_HIGH, channels.getValue("message").importance)
        assertEquals(NotificationManager.IMPORTANCE_HIGH, channels.getValue("work_check").importance)
        assertEquals(NotificationManager.IMPORTANCE_DEFAULT, channels.getValue("feedback_reply").importance)
        assertEquals("근무 확인", channels.getValue("work_check").name)
        // 끌 수 있는 키 넷(서버 set_push_prefs 허용 목록) · work_check 는 없다.
        assertEquals(listOf("message", "gomoku_invite", "chess_invite", "feedback_reply"), AingChannel.entries.mapNotNull { it.prefsKey })
        assertFalse(NotificationChannels.isBlockedBySystem(app, AingChannel.MESSAGE)!!)
    }

    @Test
    fun postedInviteOpensRouteAndAcceptCarriesProof() {
        shadowOf(manager).setNotificationsEnabled(true)
        val route = AingRoute.GomokuInvite("m1")
        val spec = (NotificationSpecs.decide(mapOf("type" to "gomoku_invite", "match_id" to "m1", "title" to "오목 신청", "body" to "b"), null) as PushDecision.Post).spec
        assertTrue(app.container.notificationPoster.post(spec))
        val posted = shadowOf(manager).allNotifications.single()
        assertEquals("gomoku_invite", posted.channelId)
        val tap = shadowOf(posted.contentIntent).savedIntent
        assertEquals(MainActivity::class.java.name, tap.component?.className)
        assertEquals(RouteIntents.ACTION_OPEN_ROUTE, tap.action)
        assertEquals(route.url, tap.getStringExtra(RouteIntents.EXTRA_ROUTE))
        assertNull("본문 탭에 수락 증표가 실렸다", tap.getStringExtra(RouteIntents.EXTRA_PROOF))
        val accept = shadowOf(posted.actions.single().actionIntent).savedIntent
        val proof = app.container.routeProof.value()
        assertEquals(proof, accept.getStringExtra(RouteIntents.EXTRA_PROOF))
        // 그 Intent 를 셸이 읽으면 수락이 참이다(다른 증표면 거짓 — RouteIntentsTest).
        assertEquals(RouteRequest(route, accept = true), RouteIntents.parse(RouteIntents.read(accept)!!, proof))
        assertTrue(shadowOf(posted.contentIntent).isActivityIntent)
    }

    @Test
    fun messagesShareAGroupAndReplaceByPeer() {
        shadowOf(manager).setNotificationsEnabled(true)
        fun msg(peer: String, body: String) =
            (NotificationSpecs.decide(mapOf("type" to "message", "peer_id" to peer, "title" to "보낸사람", "body" to body), null) as PushDecision.Post).spec
        app.container.notificationPoster.post(msg("p1", "하나"))
        app.container.notificationPoster.post(msg("p1", "둘"))
        app.container.notificationPoster.post(msg("p2", "셋"))
        val active = shadowOf(manager).activeNotifications.associate { it.tag to it.notification }
        // 상대별 하나(p1 은 둘째가 첫째를 갈아 끼움) + 묶음 요약 하나.
        assertEquals(setOf("message-p1", "message-p2", "message-summary"), active.keys)
        assertEquals("둘", active.getValue("message-p1").extras.getCharSequence("android.text").toString())
        assertTrue(active.values.all { it.group == NotificationSpecs.MESSAGE_GROUP })
    }

    @Test
    fun nothingIsPostedWhenNotificationsAreOff() {
        shadowOf(manager).setNotificationsEnabled(false)
        val spec = (NotificationSpecs.decide(mapOf("type" to "work_check"), null) as PushDecision.Post).spec
        assertFalse(app.container.notificationPoster.post(spec))
        assertEquals(0, shadowOf(manager).size())
    }
}
