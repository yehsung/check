// 원본: Sources/CheckCore/MiniGameEngine.swift:347-370(MiniGameRandom) · Sources/CheckCore/GomokuAIEngine.swift:176-187(GomokuAISplitMix64) @ 862be0f
package com.yehsung.aingcheck.core.foundation.rng

/**
 * 결정적 난수 SplitMix64(C§5.1 E1 — 모든 게임의 뿌리). Swift 의 두 벌(게임 `MiniGameRandom` · 오목 AI `GomokuAISplitMix64`)을
 * 하나로 합쳤다(C§3.2 F-1). 두 벌이 같은 열을 낸다는 것은 Swift 골든 내보내기가 시드마다 단언한다.
 *
 * 비트 동일이 계약이다(골든 `contract/golden/rng/splitmix64.json`, 시험 `SplitMix64GoldenTest`).
 * - 산술은 **부호 없는 64비트 감김**이다(`ULong`). 부호 있는 `Long` 의 `shr` 를 쓰면 위 비트가 1 인 상태에서 열이 갈린다
 *   (A§4-2 결정성 함정 표).
 * - `unit()` 은 Swift 식 그대로 `Double(next() >> 11) / 2^53` 이다. 위 53비트는 Double 로 정확히 옮겨지고, 2^53 으로 나누는 것은
 *   지수만 바꾸므로 어느 플랫폼이든 같은 비트다.
 * - Swift 는 값 타입(struct)이라 복사하면 상태가 갈라진다. Kotlin 은 참조라 같은 일을 하려면 [copy] 를 부른다
 *   (테트리스 판을 복제해 미리 떨어뜨려 보는 자리 — `GoldenTetrisPilot.bestPlacement` 꼴).
 */
class SplitMix64(seed: ULong) {
    private var state: ULong = seed

    /** 다음 64비트. */
    fun next(): ULong {
        state += GAMMA
        var z = state
        z = (z xor (z shr 30)) * MIX1
        z = (z xor (z shr 27)) * MIX2
        return z xor (z shr 31)
    }

    /** [0, 1) 균등. */
    fun unit(): Double = (next() shr 11).toDouble() / TWO_POW_53

    /** [lo, hi] 균등(Swift `uniform(_:_:)` 와 같은 식 — `lo + (hi - lo) * unit()`). */
    fun uniform(lo: Double, hi: Double): Double = lo + (hi - lo) * unit()

    /** 같은 상태의 새 생성기(Swift struct 복사와 같은 뜻). */
    fun copy(): SplitMix64 = SplitMix64(0uL).also { it.state = state }

    companion object {
        /** 황금비 증분(Steele·Lea·Flood 2014). */
        const val GAMMA: ULong = 0x9E3779B97F4A7C15uL
        const val MIX1: ULong = 0xBF58476D1CE4E5B9uL
        const val MIX2: ULong = 0x94D049BB133111EBuL

        /** 2^53 — Swift `Double(1 << 53)`. */
        const val TWO_POW_53: Double = 9007199254740992.0
    }
}
