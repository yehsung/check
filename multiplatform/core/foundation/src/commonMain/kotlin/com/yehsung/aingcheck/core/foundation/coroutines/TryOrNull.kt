// 원본: Swift `try?` 의 Kotlin 대응(C§2.4)
package com.yehsung.aingcheck.core.foundation.coroutines

import kotlin.coroutines.cancellation.CancellationException

/**
 * Swift `try?` 대응. 실패면 null — 단 **취소는 삼키지 않는다**.
 * `runCatching`·`catch (e: Exception)` 은 CancellationException 을 삼켜 구조적 동시성을 깨뜨린다(C§2.4).
 */
inline fun <T> tryOrNull(block: () -> T): T? = try {
    block()
} catch (e: CancellationException) {
    throw e
} catch (e: Exception) {
    null
}
