// 원본: Sources/CheckMobileKit/Push/MobileAppModel+Push.swift · PushNotificationCenterAdapter.swift(willPresent · didRegister 전달 몫) @ 3bd04bd
// FCM 서비스(W1-g AingMessagingService) → 푸시 자리(PushInbox) → 폰 로직(W2-f PhonePushCoordinator)을 잇는 조립 한 자리.
// 서비스는 판정·게시만 하고 네트워크를 쓰지 않는다(E§6.3 짧은 실행 창). 스토어 재조회는 조정자가 **앱이 앞일 때만** 한다.
package com.yehsung.aingcheck.android.push

import com.yehsung.aingcheck.android.routing.RouteTargets
import com.yehsung.aingcheck.feature.phone.push.PhonePushContent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch

object PushBridge {
    /**
     * 받은 판정마다 [deliver](= `PhonePushCoordinator.didReceive`)로, 새 FCM 토큰마다 [token](= `PhonePushCoordinator.didReceivePushToken`)으로
     * 넘긴다. 토큰 원문은 어디에도 기록하지 않는다. 돌려준 작업을 취소하면 멈춘다.
     */
    fun start(
        scope: CoroutineScope,
        inbox: PushInbox,
        deliver: (PhonePushContent) -> Unit,
        token: (String) -> Unit,
    ): Job = scope.launch {
        launch { inbox.events.collect { decision -> RouteTargets.content(decision)?.let(deliver) } }
        launch { inbox.latestToken.filterNotNull().collect(token) }
    }
}
