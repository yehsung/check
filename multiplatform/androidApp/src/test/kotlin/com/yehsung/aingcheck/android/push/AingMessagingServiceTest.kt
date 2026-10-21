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
import com.yehsung.aingcheck.android.shell.MainActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
}
