// 원본: 없음 — Swift(맥 CoreGraphics) `CGRect` 의 규칙 몫(maxY · intersects). 플래피 충돌이 이 의미에 기댄다.
package com.yehsung.aingcheck.core.rules.minigame

/**
 * 논리 좌표 사각형(Swift `CGRect` 의 규칙 몫). [maxX]·[maxY] 는 CoreGraphics 와 같은 식 `origin + size`(음수 크기면 origin 쪽)다 —
 * `bird.y + 12` 처럼 다시 묶어 쓰면 반올림이 달라질 수 있어 사각형을 만든 뒤 이 값을 읽는다(Swift 와 같은 연산 순서).
 *
 * [intersects] 는 맥 CoreGraphics `CGRect.intersects` 를 실측한 의미다(골든 `flappy/rules` 의 `rectIntersects` 표가 Swift 에서 낸다):
 * 축마다 크기가 양수인 구간은 반열린 [min, max), 크기 0 인 구간은 점 {v} 로 보고, 두 축 모두 겹치면 참.
 * 그래서 변만 맞닿은 두 사각형은 거짓, 크기 0 사각형이 상대의 min 변 위에 있으면 참, max 변 위에 있으면 거짓이다.
 */
data class MiniGameRect(val x: Double, val y: Double, val width: Double, val height: Double) {
    val minX: Double get() = if (width < 0) x + width else x
    val maxX: Double get() = if (width < 0) x else x + width
    val minY: Double get() = if (height < 0) y + height else y
    val maxY: Double get() = if (height < 0) y else y + height

    fun intersects(other: MiniGameRect): Boolean =
        axisOverlaps(minX, maxX, other.minX, other.maxX) && axisOverlaps(minY, maxY, other.minY, other.maxY)

    private companion object {
        fun axisOverlaps(a1: Double, a2: Double, b1: Double, b2: Double): Boolean {
            val aPoint = !(a2 > a1)
            val bPoint = !(b2 > b1)
            return when {
                aPoint && bPoint -> a1 == b1
                aPoint -> b1 <= a1 && a1 < b2
                bPoint -> a1 <= b1 && b1 < a2
                else -> swiftMax(a1, b1) < swiftMin(a2, b2)
            }
        }
    }
}
