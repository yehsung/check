// 원본: Tests/checkTests/GoldenExport/_base/GoldenExportBase.swift(rng/splitmix64 생성기) @ W0-b
package com.yehsung.aingcheck.core.foundation.rng

import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenFile
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.bits
import com.yehsung.aingcheck.testkit.golden.hex64
import com.yehsung.aingcheck.testkit.golden.string
import com.yehsung.aingcheck.testkit.golden.stringValue
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * Kotlin SplitMix64 가 Swift(MiniGameRandom = GomokuAISplitMix64)와 비트로 같다 — 골든 `rng/splitmix64`(C§5.2 G2).
 * 시드 12개 × next 64 · unit 16 · uniform 2×4. 첫 불일치에서 멈추고 골든 이름 · case · 자리 · 두 값을 말한다.
 */
class SplitMix64GoldenTest {
    private val golden: GoldenFile = Golden.load("rng/splitmix64")

    private fun mismatch(case: JsonObject, what: String, index: Int, want: String, got: String): Nothing =
        fail(golden.failure(case.string("id"), "$what[$index] 기대 $want · Kotlin $got (시드 ${case.string("seed")})"))

    @Test
    fun nextMatchesSwiftBitForBit() {
        var compared = 0
        for (case in golden.cases) {
            val rng = SplitMix64(case.hex64("seed"))
            case.array("next").forEachIndexed { i, element ->
                val want = Golden.hex64(element.stringValue())
                val got = rng.next()
                if (got != want) mismatch(case, "next", i, Golden.hex64Text(want), Golden.hex64Text(got))
                compared++
            }
        }
        assertEquals(12 * 64, compared, "골든의 next 값을 덜 읽었다(빈 대조가 초록이 되지 않게)")
    }

    @Test
    fun unitMatchesSwiftBitForBit() {
        var compared = 0
        for (case in golden.cases) {
            val rng = SplitMix64(case.hex64("seed"))
            case.array("unitBits").forEachIndexed { i, element ->
                val want = Golden.bits(element.stringValue())
                val got = rng.unit()
                if (got.toRawBits() != want.toRawBits()) mismatch(case, "unitBits", i, element.stringValue(), Golden.bitsText(got))
                assertTrue(got >= 0.0 && got < 1.0, "unit() 이 [0, 1) 밖이다: $got")
                compared++
            }
        }
        assertEquals(12 * 16, compared)
    }

    @Test
    fun uniformMatchesSwiftBitForBit() {
        var compared = 0
        for (case in golden.cases) {
            for (range in case.array("uniform")) {
                val r = range as JsonObject
                val lo = r.bits("loBits")
                val hi = r.bits("hiBits")
                val rng = SplitMix64(case.hex64("seed"))
                r.array("valuesBits").forEachIndexed { i, element ->
                    val got = rng.uniform(lo, hi)
                    if (got.toRawBits() != Golden.bits(element.stringValue()).toRawBits()) {
                        mismatch(case, "uniform($lo, $hi)", i, element.stringValue(), Golden.bitsText(got))
                    }
                    compared++
                }
            }
        }
        assertEquals(12 * 2 * 4, compared)
    }

    /** 기준선이 다른 입력이어야 한다(기억 comparison-baseline-must-differ): 시드마다 열이 서로 달라야 대조가 뜻이 있다. */
    @Test
    fun goldenStreamsDifferAcrossSeeds() {
        val heads = golden.cases.map { it.array("next").first().stringValue() }
        assertEquals(heads.size, heads.toSet().size, "시드가 달라도 첫 값이 같다 — 골든이 시드를 안 탄다")
        assertTrue(golden.cases.any { it.hex64("seed") >= 0x8000000000000000uL }, "위 비트가 선 시드가 없다(부호 함정을 못 잰다)")
    }

    @Test
    fun copyForksTheStream() {
        val a = SplitMix64(42uL)
        a.next()
        val b = a.copy()
        assertEquals(a.next(), b.next(), "복사본은 같은 다음 값을 낸다")
        a.next()
        assertTrue(a.next() != b.next(), "복사본이 원본과 상태를 나눈다(참조 복사)")
    }
}
