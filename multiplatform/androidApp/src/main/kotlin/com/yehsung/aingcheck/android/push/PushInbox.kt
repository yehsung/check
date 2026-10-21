// 푸시 서비스 → 앱 로직(W2-f) 사이의 자리. 서비스는 판정 결과와 새 토큰을 여기 두고, 폰 로직이 듣는다.
// 버퍼가 차면 오래된 사건부터 버린다(재조회 신호라 하나만 남아도 된다). 토큰은 마지막 값만 의미가 있다.
package com.yehsung.aingcheck.android.push

import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow

class PushInbox {
    private val decisions = MutableSharedFlow<PushDecision>(extraBufferCapacity = 16, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    private val token = MutableStateFlow<String?>(null)

    /** 받은 data 메시지의 판정(게시·숨김·버림). */
    val events: SharedFlow<PushDecision> = decisions.asSharedFlow()

    /** onNewToken 으로 받은 마지막 FCM 토큰(로그인 뒤 등록은 W2-f). */
    val latestToken: StateFlow<String?> = token.asStateFlow()

    fun publish(decision: PushDecision) {
        decisions.tryEmit(decision)
    }

    fun newToken(value: String) {
        token.value = value
    }
}
