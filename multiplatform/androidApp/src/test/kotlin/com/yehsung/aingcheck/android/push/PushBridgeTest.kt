// 원본: Sources/CheckMobileKit/Push/MobileAppModel+Push.swift · PushNotificationCenterAdapter.swift(willPresent · didRegister 전달) @ 3bd04bd
// FCM 수신 처리를 연결째 잰다: 가짜 RemoteMessage(서버 트리거 정본 contract/push/payloads → K7 data 맵) → 진짜 AingMessagingService →
// PushInbox → PushBridge → 폰 로직 입구(PhonePushCoordinator.didReceive 자리). 새 토큰(onNewToken)도 같은 다리로 간다.
package com.yehsung.aingcheck.android.push

import androidx.test.core.app.ApplicationProvider
import com.google.firebase.messaging.RemoteMessage
import com.yehsung.aingcheck.android.app.AingApplication
import com.yehsung.aingcheck.feature.phone.push.PhonePushContent
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class PushBridgeTest {
    private val app get() = ApplicationProvider.getApplicationContext<AingApplication>()

    private fun remote(kind: String): RemoteMessage =
        RemoteMessage.Builder("aingcheck-test@fcm.googleapis.com")
            .setData(K7DataMessage.fromSqlPayload(RepoFiles.readText("contract/push/payloads/$kind.json"), kind))
            .build()

    @Test
    fun everyContractPayloadReachesThePhoneCoordinatorEntryWithItsIds() {
        val delivered = mutableListOf<PhonePushContent>()
        val tokens = mutableListOf<String>()
        val scope = CoroutineScope(Dispatchers.Unconfined)
        PushBridge.start(scope, app.container.pushInbox, deliver = { delivered += it }, token = { tokens += it })
        try {
            val service = Robolectric.buildService(AingMessagingService::class.java).create().get()
            for (kind in listOf("message", "gomoku_invite", "chess_invite", "feedback_reply", "work_check")) service.onMessageReceived(remote(kind))
            // 모르는 type 은 게시하지 않고 조정자에도 가지 않는다.
            service.onMessageReceived(RemoteMessage.Builder("x@fcm.googleapis.com").setData(mapOf("type" to "tetris_invite", "match_id" to "t-1")).build())
            assertEquals(
                listOf(
                    PhonePushContent.Message("0a11ce00-0000-4000-8000-00000000a501"),
                    PhonePushContent.GomokuInvite("0f0f0000-0000-4000-8000-00000000f506"),
                    PhonePushContent.ChessInvite("1a1a0000-0000-4000-8000-00000001a507"),
                    PhonePushContent.FeedbackReply("1b1b0000-0000-4000-8000-00000001b508"),
                    PhonePushContent.WorkCheck(null),
                ),
                delivered,
            )
            service.onNewToken("tok-" + "A".repeat(40))
            assertEquals("새 토큰은 조정자로(원문은 기록하지 않는다)", listOf("tok-" + "A".repeat(40)), tokens)
        } finally {
            scope.cancel()
        }
    }
}
