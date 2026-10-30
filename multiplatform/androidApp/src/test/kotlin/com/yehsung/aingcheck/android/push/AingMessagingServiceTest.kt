// E§6.4 "앞 + 보고 있는 대화면 게시 안 함"을 연결째 잰다: 셸이 적은 화면 라우트(진짜 MainActivity·NavGraph → VisibleRoute) ·
// 프로세스 수명(ProcessLifecycleOwner 레지스트리 → AppLifecycle → VisibleRoute.setForeground, AingApplication 이 잇는다) ·
// 서비스가 viewing 을 넘기는 자리(진짜 AingMessagingService 객체의 onMessageReceived). 순수 판정 표는 NotificationSpecTest·VisibleRouteTest.
package com.yehsung.aingcheck.android.push

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import com.google.firebase.messaging.RemoteMessage
import com.yehsung.aingcheck.android.app.AingApplication
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.routing.RouteIntents
import com.yehsung.aingcheck.android.routing.RouteRequest
import com.yehsung.aingcheck.android.routing.RouteTargets
import com.yehsung.aingcheck.feature.phone.push.PhonePushContent
import com.yehsung.aingcheck.feature.phone.push.PhonePushMegaphone
import com.yehsung.aingcheck.android.shell.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h740dp-xhdpi")
class AingMessagingServiceTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private val app get() = ApplicationProvider.getApplicationContext<AingApplication>()

    /** 셸은 자리표시(탭 · 딥링크 · 보이는 라우트만 — 조립 화면 없이, W2-f §1 "단계를 주입"). */
    @org.junit.Before
    fun placeholderShell() {
        app.container.usePlaceholderShell()
    }
    private val manager get() = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun messageFrom(peer: String): RemoteMessage =
        RemoteMessage.Builder("aingcheck-test@fcm.googleapis.com")
            .setData(mapOf("type" to "message", "peer_id" to peer, "title" to "보낸사람", "body" to "안녕"))
            .build()

    /** 그 상대의 대화 알림이 게시돼 있는 수(같은 태그는 갈아 끼우므로 0 또는 1). */
    private val processLifecycle get() = ProcessLifecycleOwner.get().lifecycle as LifecycleRegistry

    private fun posted(peer: String): Int = shadowOf(manager).activeNotifications.count { it.tag == "message-$peer" }

    @Test
    fun conversationOnScreenIsHiddenInFrontAndPostedAfterOnStop() {
        shadowOf(manager).setNotificationsEnabled(true)
        val conversation = AingRoute.Message("abc-123")
        val controller = Robolectric.buildService(AingMessagingService::class.java).create()
        val service = controller.get()
        val deepLink = Intent(Intent.ACTION_VIEW, Uri.parse(conversation.url), app, MainActivity::class.java)
        try {
            ActivityScenario.launch<MainActivity>(deepLink).use {
                compose.waitUntil { app.container.visibleRoute.route.value == conversation }
                // 프로세스를 앞으로: ProcessLifecycleOwner 의 레지스트리를 ON_START 로 민다(AingApplication 이 onCreate 에서 이 레지스트리에
                // AppLifecycle 을 붙였다 → VisibleRoute.setForeground). 기기에서는 androidx.startup 의 InitializationProvider 가
                // ProcessLifecycleOwner 를 Activity 콜백에 붙이지만, Robolectric 은 그 제공자를 돌리지 않는다(실측: 상태 INITIALIZED 에 멈춤 ·
                // 초기화기를 직접 부르면 "cannot be initialized lazily"). 그래서 Activity 대신 레지스트리를 직접 몬다.
                processLifecycle.handleLifecycleEvent(Lifecycle.Event.ON_START)
                assertTrue("ProcessLifecycle ON_START 뒤에도 앱이 앞으로 읽히지 않는다", app.container.lifecycle.isForeground.value)

                // 앞 + 같은 대화 → 게시 0.
                service.onMessageReceived(messageFrom("abc-123"))
                assertEquals("앞에서 보고 있는 대화의 알림이 게시됐다", 0, posted("abc-123"))
                // 기준선(같은 순간, 다른 상대 = 다른 입력): 다른 대화는 앞이어도 게시한다 — 위 0 이 '게시가 안 되는 환경' 탓이 아니다.
                service.onMessageReceived(messageFrom("other-1"))
                assertEquals(1, posted("other-1"))

                // 프로세스를 뒤로: ProcessLifecycle ON_STOP(Activity 는 그대로 — 화면 라우트도 그대로다).
                processLifecycle.handleLifecycleEvent(Lifecycle.Event.ON_STOP)
                assertFalse("ON_STOP 뒤에도 앞으로 읽힌다", app.container.lifecycle.isForeground.value)
                assertEquals("화면 라우트는 뒤로 가도 그대로여야 한다(숨김을 막는 것은 앞/뒤 문)", conversation, app.container.visibleRoute.route.value)

                // 뒤 + 같은 대화 → 게시 1.
                service.onMessageReceived(messageFrom("abc-123"))
                assertEquals("뒤로 간 뒤 그 대화의 알림이 게시되지 않았다", 1, posted("abc-123"))
            }
        } finally {
            controller.destroy()
            // ProcessLifecycleOwner 는 JVM 싱글턴이라 같은 샌드박스의 다음 시험에 상태가 남는다 — 앞(STARTED)으로 남기지 않는다.
            if (processLifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) processLifecycle.handleLifecycleEvent(Lifecycle.Event.ON_STOP)
        }
    }

    private fun megaphoneFrom(peer: String, megaphoneId: String): RemoteMessage =
        RemoteMessage.Builder("aingcheck-test@fcm.googleapis.com")
            .setData(mapOf("type" to "message", "peer_id" to peer, "megaphone_id" to megaphoneId, "title" to "보낸사람", "body" to "다들 화이팅"))
            .build()

    /** 그 상대·그 확성기로 게시된 알림 수(태그가 상대별이든 확성기별이든 센다). */
    private fun postedMegaphone(peer: String, megaphoneId: String): Int =
        shadowOf(manager).activeNotifications.count { it.tag == "message-$peer" || it.tag == "megaphone-$megaphoneId" }

    /**
     * 확성기 푸시 · 앞/뒤 판정(Swift PushCoordinator.presentation `isAppActive` 하나로 가른다 @ a6791165): 앞이면 **어느 화면이든** 시스템 알림을
     * 내지 않는다(앱 배너로). 라우트로 나타낼 수 없는 화면(미션 · 프로필 · 뽑기 · nav 대화상자 …)에서는 보이는 라우트가 null 이라 viewing() 도
     * null 이다 — 그것을 '뒤'로 읽으면 헤즈업 알림과 앱 배너가 겹친다.
     */
    @Test
    fun megaphoneInFrontIsNotPostedEvenOnAScreenWithoutARoute() {
        shadowOf(manager).setNotificationsEnabled(true)
        val controller = Robolectric.buildService(AingMessagingService::class.java).create()
        val service = controller.get()
        val deepLink = Intent(Intent.ACTION_VIEW, Uri.parse(AingRoute.Now.url), app, MainActivity::class.java)
        try {
            ActivityScenario.launch<MainActivity>(deepLink).use {
                compose.waitUntil { app.container.visibleRoute.route.value == AingRoute.Now }
                processLifecycle.handleLifecycleEvent(Lifecycle.Event.ON_START)
                // 라우트 없는 화면(셸은 RoutePlans.routeOf 가 null 인 목적지에서 null 을 적는다).
                app.container.visibleRoute.setRoute(null)
                assertTrue(app.container.lifecycle.isForeground.value)
                assertEquals("전제: 라우트 없는 화면에서는 viewing() 이 null", null, app.container.visibleRoute.viewing())

                // 앞 + 라우트 없는 화면 + 확성기 → 게시 0.
                service.onMessageReceived(megaphoneFrom("mega-1", "mp-1"))
                assertEquals("앞에서 받은 확성기가 시스템 알림으로 게시됐다(라우트 없는 화면)", 0, postedMegaphone("mega-1", "mp-1"))
                // 기준선(같은 순간 · megaphone_id 없는 평범한 메시지): 앞이어도 보고 있지 않은 대화면 게시한다 — 위 0 이 '게시가 안 되는 환경' 탓이 아니다.
                service.onMessageReceived(messageFrom("plain-1"))
                assertEquals(1, posted("plain-1"))

                // 뒤 → 확성기도 시스템 알림으로 게시한다.
                processLifecycle.handleLifecycleEvent(Lifecycle.Event.ON_STOP)
                service.onMessageReceived(megaphoneFrom("mega-2", "mp-2"))
                assertEquals("뒤에서 받은 확성기가 게시되지 않았다", 1, postedMegaphone("mega-2", "mp-2"))
            }
        } finally {
            controller.destroy()
            if (processLifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) processLifecycle.handleLifecycleEvent(Lifecycle.Event.ON_STOP)
        }
    }

    /** 게시된 알림(태그)의 본문 탭이 MainActivity 에 실어 보내는 요청 — 셸과 같은 길(RouteIntents.read → parse, 이 설치의 증표). */
    private fun tapRequest(tag: String): RouteRequest? {
        val notification = shadowOf(manager).activeNotifications.single { it.tag == tag }.notification
        val tapped = shadowOf(notification.contentIntent).savedIntent
        return RouteIntents.parse(RouteIntents.read(tapped)!!, expectedProof = app.container.routeProof.value())
    }

    /**
     * 뒤에서 받은 확성기 알림을 누르면 **대화가 아니라 그 확성기 배너**(Swift PushCoordinator.handleResponse 의 megaphoneID 가지 @ a6791165 ·
     * 계약 '푸시를 눌러 들어오면 대화로 가지 않고 그 항목을 배너로(24시간 안)'). 진짜 서비스가 게시한 알림의 PendingIntent 를 셸과 같은 길로 풀어,
     * MainActivity 가 조정자에 넘기는 내용이 표식을 실은 Message 인지 잰다 — 그 내용 → banner.current 는
     * feature/phone MegaphoneBannerPhoneTest.tappedPushOpensBannerNotThread 가 잰다(같은 값).
     */
    @Test
    fun tappedBackgroundMegaphoneOpensBannerNotThread() {
        shadowOf(manager).setNotificationsEnabled(true)
        val controller = Robolectric.buildService(AingMessagingService::class.java).create()
        val service = controller.get()
        try {
            // 뒤(프로세스 ON_START 없음).
            assertFalse(app.container.visibleRoute.isForeground())
            service.onMessageReceived(megaphoneFrom("mega-3", "mp-3"))
            val request = tapRequest("megaphone-mp-3")!!
            assertEquals(
                "확성기 알림 탭이 조정자에 표식을 싣지 않았다(대화로 간다)",
                PhonePushContent.Message("mega-3", PhonePushMegaphone("mp-3", "보낸사람", "다들 화이팅")),
                RouteTargets.megaphoneTapContent(request),
            )

            // 기준선(megaphone_id 없는 메시지 알림): 표식 없음 → 라우터가 그 대화를 연다.
            service.onMessageReceived(messageFrom("plain-3"))
            val plain = tapRequest("message-plain-3")!!
            assertEquals(AingRoute.Message("plain-3"), plain.route)
            assertNull(RouteTargets.megaphoneTapContent(plain))

            // 증표 없는 같은 표식(다른 앱이 보낸 명시적 Intent)은 믿지 않는다 — 배너도 대화도 아닌 메시지 탭.
            val forged = RouteIntents.Incoming(
                RouteIntents.ACTION_OPEN_ROUTE, dataString = null, routeExtra = AingRoute.Message("mega-3").url, acceptExtra = false,
                proofExtra = null, megaphoneIdExtra = "mp-3", megaphoneTitleExtra = "가짜", megaphoneBodyExtra = "가짜 본문",
            )
            val forgedRequest = RouteIntents.parse(forged, expectedProof = app.container.routeProof.value())!!
            assertEquals(RouteRequest(AingRoute.Messages), forgedRequest)
            assertNull(RouteTargets.megaphoneTapContent(forgedRequest))
        } finally {
            controller.destroy()
        }
    }
}
