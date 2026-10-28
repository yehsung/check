// 원본: 없음 — Swift `Task.isCancelled` 와 요청 취소(URLError.cancelled)를 Kotlin 구조적 동시성에서 가르는 한 자리(W2-a core/session Cancellation.kt 와 같은 판정).
package com.yehsung.aingcheck.feature.phone.app

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.cancellation.CancellationException

/**
 * 잡은 오류가 **이 코루틴 자신의 취소**면 다시 던진다(로그아웃 `reset` 이 도는 작업을 끊은 경우 — 삼키면 끊긴 작업이 뒤 단계를 계속 탄다).
 * 요청 하나가 취소로 끝난 것(엔진 취소 · OS 가 끊은 연결)은 던지지 않는다 — Swift 처럼 '취소' 처분으로 호출부가 접는다.
 */
internal suspend fun rethrowIfOwnCancellation(error: Throwable) {
    if (error is CancellationException) currentCoroutineContext().ensureActive()
}
