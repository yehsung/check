// 원본: 없음 — Swift `case .cancelled: return`(조용히 접기)의 Kotlin 몫(C§2.4 동시성 매핑).
package com.yehsung.aingcheck.core.session

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.cancellation.CancellationException

/**
 * Swift 는 취소를 조용히 접는다(`case .cancelled: return`). Kotlin 은 **이 코루틴 자신이** 취소됐으면 그 취소를 다시 던져야 구조적
 * 동시성이 산다 — 그래서 취소 예외면 지금 문맥이 살아 있는지만 확인한다(살아 있으면 Swift 처럼 이어 간다: 남이 취소한 하위 작업의
 * 취소 예외는 '취소된 왕복'일 뿐이다).
 */
internal suspend fun rethrowIfOwnCancellation(error: Throwable) {
    if (error is CancellationException) currentCoroutineContext().ensureActive()
}
