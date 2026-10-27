// 원본: 없음 — Swift 표준 라이브러리의 수 의미(min · max · rounded)를 같은 비트로 재현하는 도우미(C§2.5). 게임 엔진 넷이 같이 쓴다.
package com.yehsung.aingcheck.core.rules.minigame

import kotlin.math.truncate

/**
 * Swift `min(x, y)` = `y < x ? y : x`. Kotlin `minOf`(= `Math.min`)는 NaN 을 퍼뜨리고 `-0.0 < 0.0` 으로 본다 —
 * 엔진이 dt·남은 시간을 자르는 자리에서 갈래가 갈리지 않게 Swift 정의를 그대로 쓴다.
 */
fun swiftMin(x: Double, y: Double): Double = if (y < x) y else x

/** Swift `max(x, y)` = `y >= x ? y : x`(같으면 y). */
fun swiftMax(x: Double, y: Double): Double = if (y >= x) y else x

/**
 * Swift `Double.rounded()`(= `.toNearestOrAwayFromZero`, 0.5 는 0 에서 먼 쪽). Kotlin `round`·`roundToInt`·`Math.round` 는
 * 동률을 짝수 쪽 또는 +∞ 쪽으로 보낸다(`Math.round(-2.5) = -2`) — core/rules 는 그것들을 쓰지 않는다(구조 규칙 R4).
 * `x - truncate(x)` 는 언제나 정확한 뺄셈이라(같은 지수 범위) 경계 0.5 판정이 비트로 맞는다. 부호 있는 0 도 Swift 와 같다.
 */
fun Double.roundedHalfAwayFromZero(): Double {
    if (isNaN() || isInfinite()) return this
    val whole = truncate(this)
    val fraction = this - whole
    return when {
        fraction >= 0.5 -> whole + 1.0
        fraction <= -0.5 -> whole - 1.0
        else -> whole
    }
}
