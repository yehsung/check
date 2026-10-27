// 원본: 없음 — Swift 표준 라이브러리 알고리즘(`RandomNumberGenerator.next(upperBound:)` · `Int.random(in:using:)` ·
//   `Collection.randomElement(using:)`)을 AI 두 벌(GomokuAIEngine · ChessAIEngine)이 쓰는 꼴 그대로 옮긴다.
package com.yehsung.aingcheck.core.rules.ai

import com.yehsung.aingcheck.core.foundation.rng.SplitMix64
import kotlin.random.Random

// AI 동점 고르기의 난수원. C§3.2 A-5 는 "randomElement(using:) 은 Swift 표준 라이브러리 알고리즘이라 비트 동일은 요구하지 않는다(판단)"
// 이지만, 알고리즘이 공개돼 있고 짧아서 **그대로 옮겼다** — 그래야 같은 씨앗이면 같은 수를 고르고, 골든 `renju/ai-trace`·`chess/ai-trace`
// 가 수·점수·노드 수까지 비트로 대조할 수 있다(집합 동등보다 이식 결함을 훨씬 일찍 잡는다).

/** Swift `RandomNumberGenerator` 의 꼴: 64비트를 하나씩 낸다. */
interface SwiftRandomSource {
    fun next(): ULong
}

/** 씨앗 고정(시험·재현) — SplitMix64(Swift `GomokuAISplitMix64` 와 같은 열, 골든 `rng/splitmix64`). */
class SeededSwiftRandom(seed: ULong) : SwiftRandomSource {
    private val rng = SplitMix64(seed)
    override fun next(): ULong = rng.next()
}

/** 씨앗 없음(앱) — Swift `SystemRandomNumberGenerator` 자리. 매판 다른 기보. */
object SystemSwiftRandom : SwiftRandomSource {
    override fun next(): ULong = Random.Default.nextLong().toULong()
}

/**
 * Swift `RandomNumberGenerator.next(upperBound:)`(UInt64) — Lemire 곱셈·거절. `upperBound` 는 0 이 아니어야 한다.
 * ```
 * var random = next(); var m = random.multipliedFullWidth(by: upperBound)
 * if m.low < upperBound { let t = (0 &- upperBound) % upperBound; while m.low < t { random = next(); m = … } }
 * return m.high
 * ```
 */
fun SwiftRandomSource.nextBounded(upperBound: ULong): ULong {
    require(upperBound != 0uL) { "upperBound cannot be zero." }
    var random = next()
    var low = random * upperBound
    if (low < upperBound) {
        val t = (0uL - upperBound) % upperBound
        while (low < t) {
            random = next()
            low = random * upperBound
        }
    }
    return multiplyHigh(random, upperBound)
}

/** Swift `Int.random(in: 0 ..< count, using:)` = `Int(truncatingIfNeeded: 0 &+ next(upperBound: UInt(count)))`. */
fun SwiftRandomSource.nextIndex(count: Int): Int {
    require(count > 0) { "Can't get random value with an empty range" }
    return nextBounded(count.toULong()).toInt()
}

/** Swift `Collection.randomElement(using:)` — 비면 null, 아니면 `Int.random(in: 0..<count)` 번째. */
fun <T> List<T>.randomElement(rng: SwiftRandomSource): T? {
    if (isEmpty()) return null
    return this[rng.nextIndex(size)]
}

/** 부호 없는 64×64 → 위 64비트(Swift `multipliedFullWidth(by:).high`). 32비트 조각 넷으로 센다(공용 코드라 JDK 함수를 쓰지 않는다). */
internal fun multiplyHigh(a: ULong, b: ULong): ULong {
    val mask = 0xFFFF_FFFFuL
    val aLo = a and mask
    val aHi = a shr 32
    val bLo = b and mask
    val bHi = b shr 32
    val loLo = aLo * bLo
    val hiLo = aHi * bLo
    val loHi = aLo * bHi
    val hiHi = aHi * bHi
    val cross = (loLo shr 32) + (hiLo and mask) + loHi
    return hiHi + (hiLo shr 32) + (cross shr 32)
}
