// FCM 수신(E§6.3·6.4). data 전용 + high 라 앞·뒤·프로세스 없음 모두 여기로 온다(강제 중지면 FCM 이 버린다).
// "짧은 실행 창" 안에서 끝낸다: 판정(NotificationSpecs, 순수) → 게시 → 사건 알림. 네트워크 호출을 하지 않는다 —
// 재조회는 앱이 앞에 올 때 스토어가 한다(W2-f 가 [PushInbox.events] 를 듣는다).
//
// Firebase 는 release 조립 지점에서 설정이 있을 때만 초기화된다(FirebaseBootstrap). 초기화되지 않은 빌드(debug·stub·시험)에서는
// 이 서비스가 불릴 일이 없다.
package com.yehsung.aingcheck.android.push

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.yehsung.aingcheck.android.app.AingApplication
import com.yehsung.aingcheck.core.foundation.platform.LogLevel

class AingMessagingService : FirebaseMessagingService() {
    private val container get() = (application as AingApplication).container

    override fun onMessageReceived(message: RemoteMessage) {
        val c = container
        val decision = NotificationSpecs.decide(
            message.data, viewing = c.visibleRoute.viewing(), duelsEnabled = c.appConfig.duelsEnabled, isForeground = c.visibleRoute.isForeground(),
        )
        when (decision) {
            is PushDecision.Post -> {
                val posted = c.notificationPoster.post(decision.spec)
                c.logger.log(LogLevel.INFO, TAG, "push ${decision.spec.channel.id} posted=$posted")
            }
            is PushDecision.Hide ->
                c.logger.log(LogLevel.INFO, TAG, "push ${decision.refresh.id} hidden(${if (decision.megaphone != null) "확성기 — 앱 배너" else "보고 있는 대화"})")
            is PushDecision.Drop -> c.logger.log(LogLevel.WARN, TAG, "push dropped: ${decision.reason}")
        }
        c.pushInbox.publish(decision)
    }

    // 새 토큰. 등록(register_device_fcm)은 W2-f 의 일이다 — 여기서는 새 토큰이 생겼다는 사실만 넘긴다(토큰을 로그에 싣지 않는다).
    // firebase-messaging 26 은 getToken() 길의 onNewToken 을 폐기 표시하고 register() 길의 onRegistered 를 더했다. 서비스는
    // 두 길을 따로 부르므로(26.0.0 바이트코드 확인) 어느 API 를 W2-f 가 고르든 받도록 둘 다 받는다.
    @Suppress("OVERRIDE_DEPRECATION")
    override fun onNewToken(token: String) {
        container.pushInbox.newToken(token)
    }

    override fun onRegistered(token: String) {
        container.pushInbox.newToken(token)
    }

    private companion object {
        const val TAG = "AingPush"
    }
}
