// 원본: Swift `Double.rounded()`(.toNearestOrAwayFromZero) — Gacha.swift:756 · CheckTokenRowDisplay.swift:250 · AILimitFreshnessRule.swift:441 ·
//       CheckTodoModel.swift:309 의 반올림 @ 1b8260d (C§2.5)
package com.yehsung.aingcheck.core.rules.format

import kotlin.math.floor

/**
 * Swift `x.rounded()` — **0.5 는 0 에서 먼 쪽**. Kotlin `round`(짝수 쪽) · `roundToInt`(+∞ 쪽)와 음수 .5 에서 셋이 다르다(A§4-2 —
 * core/rules 는 반올림 함수를 구조 시험이 막는다). 소수부는 `x - floor(x)` 로 정확히 뗀다(|x| < 2^52 에서 정확).
 */
fun roundedHalfAwayFromZero(x: Double): Double {
    if (!x.isFinite()) return x
    val f = floor(x)
    val fraction = x - f
    val result = when {
        fraction > 0.5 -> f + 1
        fraction < 0.5 -> f
        else -> if (x > 0) f + 1 else f
    }
    // -0.4 → floor -1 · 소수 0.6 → 0.0 이 아니라 -0.0 이어야 Swift 와 비트가 같다(부호 보존).
    return if (result == 0.0 && x < 0) -0.0 else result
}

/** Swift `Double.rounded(.down)`(내림). */
fun roundedDown(x: Double): Double = floor(x)

/** Swift `Int(x)`(0 쪽으로 자름) — 범위 밖이면 트랩 대신 [ArithmeticException]. */
fun swiftIntTruncating(x: Double): Long {
    if (!x.isFinite() || x >= 9.223372036854775807E18 || x < -9.223372036854775808E18) throw ArithmeticException("Int 범위 밖: $x")
    return x.toLong()
}
