// 원본: 없음 — Swift 표준 라이브러리 수 의미(min · max · Double.rounded())를 재현하는 도우미의 경계 시험(C§2.5).
package com.yehsung.aingcheck.core.rules.minigame

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 기대값은 Swift 문서의 정의에서 왔다(구현을 거울로 옮긴 값이 아니다): `min(x, y) = y < x ? y : x`, `max(x, y) = y >= x ? y : x`,
 * `Double.rounded()` = `.toNearestOrAwayFromZero`. 대조로 Kotlin 기본(`maxOf`)이 다른 자리를 같이 박는다(core/rules 는 표준 반올림 함수를
 * 쓰지 않는다 — 구조 규칙 R4 — 그래서 반올림 대조는 여기 두지 않는다).
 */
class SwiftNumericsTest {
    @Test
    fun roundedHalfAwayFromZeroFollowsSwift() {
        val cases = listOf(
            2.5 to 3.0, -2.5 to -3.0, 0.5 to 1.0, -0.5 to -1.0, 1.4999999999999998 to 1.0,
            0.49999999999999994 to 0.0, 7.0 to 7.0, -7.5 to -8.0, 4503599627370495.5 to 4503599627370496.0, 1e300 to 1e300,
        )
        for ((x, want) in cases) assertEquals(want, x.roundedHalfAwayFromZero(), "($x).rounded()")
        assertEquals((-0.0).toRawBits(), (-0.3).roundedHalfAwayFromZero().toRawBits(), "음수 0 의 부호")
        assertTrue(Double.NaN.roundedHalfAwayFromZero().isNaN())
    }

    @Test
    fun minMaxFollowSwiftOrder() {
        // NaN: Swift max(0, NaN) = 0(NaN >= 0 이 거짓), min(NaN, 1) = NaN(1 < NaN 이 거짓 → x).
        assertEquals(0.0, swiftMax(0.0, Double.NaN))
        assertTrue(swiftMin(Double.NaN, 1.0).isNaN())
        assertEquals(1.0, swiftMin(1.0, Double.NaN))
        // 같으면: min 은 x, max 는 y — 부호 있는 0 으로 갈린다.
        assertEquals((-0.0).toRawBits(), swiftMax(0.0, -0.0).toRawBits())
        assertEquals(0.0.toRawBits(), swiftMin(0.0, -0.0).toRawBits())
        // 대조: Kotlin maxOf 는 NaN 을 퍼뜨린다.
        assertTrue(maxOf(0.0, Double.NaN).isNaN())
    }
}
