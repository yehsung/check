// 원본: 없음 (설계 F §6 T3 픽셀 · 음성 대조 — 데스크톱 Skia 래스터, ubuntu · windows-latest · windows-11-arm)
package com.yehsung.aingcheck.character

import com.yehsung.aingcheck.character.bake.BakeCell
import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.parity.Golden
import com.yehsung.aingcheck.character.parity.GoldenClass
import com.yehsung.aingcheck.character.parity.GoldenReplay
import com.yehsung.aingcheck.character.parity.ParityRules
import com.yehsung.aingcheck.character.render.BakeImageStore
import com.yehsung.aingcheck.character.render.ImageMetrics
import com.yehsung.aingcheck.character.render.ParityBand
import com.yehsung.aingcheck.character.render.PlatformRaster
import com.yehsung.aingcheck.character.render.RgbaImage
import com.yehsung.aingcheck.character.render.asPremultiplied
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * T3: Kotlin 합성(후광 → 몸 칸 + 감은 눈 패치)을 **실제 그리기 함수**(Skia `Matrix33` 원근 · 래스터 표면)로 그려 맥 진짜 렌더 골든 240장과 맞댄다.
 * 판정 갈래 · 무리는 골든 쪽 사실로만 정한다([ParityRules]). 깨끗한 장은 F §6 문턱 그대로, 모든 장(입자 오염 제외)에 음성 대조.
 *
 * 음성 대조와 문턱의 묶음(F §6 시험 규율 "문턱이 헐거워지면 스스로 드러난다"): 틀린 칸이 F 문턱을 넘는 장이 모든 장은 아니다(설계 이탈 —
 * 조정자 판단 대기). 대신 **무리별로 넘은 장 수의 하한**과 **무리 분포**를 잠근다 — 문턱을 풀거나 장을 느슨한 무리로 몰면 그 수가 줄어 빨갛다.
 */
class PixelParityTest {
    private val lib = RepoBake.library

    private fun verdicts(tierName: String, filter: (Golden) -> Boolean = { true }): List<ParityRules.Verdict> {
        val out = ArrayList<ParityRules.Verdict>()
        for ((folder, entries) in RepoBake.goldens.entries.filter(filter).groupBy { it.finishFolder }) {
            val finish = lib.finish(BakeLibrary.FOLDER_IDS.getValue(folder))!!
            val store = BakeImageStore(finish, RepoBake.files, PlatformRaster, pageCapacity = 2)
            try {
                for (g in entries) {
                    val golden = PlatformRaster.decodeRaw(RepoBake.goldenBytes(g)).asPremultiplied()
                    out += GoldenReplay.verdict(lib, PlatformRaster, store, g, golden, tierName)
                }
            } finally {
                store.close()
            }
        }
        return out
    }

    private fun summary(label: String, all: List<ParityRules.Verdict>): String = buildString {
        val byClass = all.groupBy { it.cls }
        val clean = byClass[GoldenClass.clean].orEmpty()
        append("$label: 깨끗 ${clean.size} · 입자 ${byClass[GoldenClass.particles].orEmpty().size} · 후광 지연 ${byClass[GoldenClass.haloLag].orEmpty().size} · 격자 거칠음 ${byClass[GoldenClass.gridCoarse].orEmpty().size}\n")
        append("  무리 분포(전체): ${ParityBand.entries.associateWith { b -> all.count { it.band == b } }}\n")
        if (clean.isNotEmpty()) append("  깨끗한 장 평균 오차의 평균 ${"%.4f".format(clean.map { it.composite.mean }.average())} · IoU 평균 ${"%.5f".format(clean.map { it.composite.iou }.average())}\n")
        for ((band, vs) in clean.groupBy { it.band }.toSortedMap()) {
            append("  ${band.name}(${vs.size}): 최저 IoU ${"%.4f".format(vs.minOf { it.composite.iou })} · 최대 평균 ${"%.2f".format(vs.maxOf { it.composite.mean })}\n")
        }
        val checked = all.filter { it.cls != GoldenClass.particles }
        append("  음성 대조(${checked.size}장): 최소 비 ${"%.2f".format(checked.minOfOrNull { it.negativeRatio } ?: 0.0)} · F 문턱을 넘은 장 ${checked.count { it.wrongExceedsThreshold }}\n")
        append("  무리별 F 문턱을 넘은 장 / 잰 장: ${ParityBand.entries.associateWith { b -> "${checked.count { it.band == b && it.wrongExceedsThreshold }}/${checked.count { it.band == b }}" }}\n")
        val notExceeding = checked.filter { !it.wrongExceedsThreshold }
        if (notExceeding.isNotEmpty()) append("  틀린 칸이 F 문턱 안인 장(${notExceeding.size}): ${notExceeding.groupBy { "${it.cls}/${it.band}" }.mapValues { e -> e.value.size }}\n")
    }

    @Test
    fun T3_골든_240장_픽셀_대조와_음성_대조() {
        val all = verdicts("S")
        assertEquals(240, all.size)
        val problems = all.flatMap { v -> v.problems().map { "${v.golden.id} [${v.cls}/${v.band}] $it" } }
        val byClass = all.groupBy { it.cls }
        val clean = byClass[GoldenClass.clean].orEmpty()
        val text = summary("T3", all)
        println(text)
        assertTrue(problems.isEmpty(), "T3 실패 ${problems.size}건\n$text" + problems.take(40).joinToString("\n"))
        // 기기 T7 부분집합(S 단)은 깨끗한 장이어야 한다(기기는 같은 판정을 쓴다).
        val t7 = all.filter { it.golden.index in GoldenReplay.T7_SUBSET }
        assertEquals(GoldenReplay.T7_SUBSET.size, t7.size)
        assertTrue(t7.all { it.cls == GoldenClass.clean }, "T7 부분집합에 깨끗하지 않은 장: ${t7.filter { it.cls != GoldenClass.clean }.map { it.golden.id }}")

        // 면제가 조용히 늘지 않게 잠근다: 입자 오염은 굽기 결함(조정자 패치로 다시 구우면 0), 후광 지연 · 격자 거칠음은 맥 쪽 한계.
        assertTrue(clean.size >= 165, "깨끗한 장이 줄었다: ${clean.size}")
        assertEquals(3, byClass[GoldenClass.gridCoarse].orEmpty().size, "격자 거칠음은 울트라 찔림 표본 288 세 마감뿐")
        assertTrue(byClass[GoldenClass.particles].orEmpty().size <= 45)
        assertTrue(byClass[GoldenClass.haloLag].orEmpty().size <= 40)

        // 퇴행 상한: F 문턱은 넉넉해 그리기 품질이 조금 무너져도(예: 몸 칸 nearest 필터) 통과한다 — 깨끗한 장 전체 평균 오차가 실측보다 0.05 넘게 오르면 빨강.
        val avgMean = clean.map { it.composite.mean }.average()
        assertTrue(avgMean <= Locks.CLEAN_MEAN_AVG_MAX, "깨끗한 장 평균 오차의 평균 ${"%.4f".format(avgMean)} > ${Locks.CLEAN_MEAN_AVG_MAX} — 그리기 품질 퇴행\n$text")

        // 무리 분포: 골든 사실(참조 칸 · 녹화 world · 리액션)로만 정하므로 굽기를 다시 해도 같다. 장을 느슨한 무리로 몰면 빨갛다.
        assertEquals(Locks.BAND_DISTRIBUTION, ParityBand.entries.associateWith { b -> all.count { it.band == b } }, "무리 분포가 바뀌었다\n$text")
        // 깨끗한 장 무리별 하한 — 한 무리의 장이 면제 갈래로 빠져나가면 빨갛다.
        for ((band, min) in Locks.CLEAN_MIN) {
            val n = clean.count { it.band == band }
            assertTrue(n >= min, "깨끗한 ${band.name} 장 $n < $min\n$text")
        }
        // 음성 대조 × 문턱: 무리별로 틀린 칸이 F 문턱을 넘은 장 수의 하한. 문턱을 헐겁게 하면 이 수가 줄어 빨갛다.
        val checked = all.filter { it.cls != GoldenClass.particles }
        for ((band, min) in Locks.NEGATIVE_EXCEEDS_MIN) {
            val n = checked.count { it.band == band && it.wrongExceedsThreshold }
            assertTrue(n >= min, "음성 대조: ${band.name} 에서 틀린 칸이 F 문턱을 넘은 장 $n < $min — 문턱이 헐거워졌다\n$text")
        }
    }

    /**
     * Android 기본 묶음이 싣는 **L 단**(쉬는 행 57칸 · 감은 눈 패치)을 같은 280×340 몸 크기로 그려 골든과 맞댄다. L 은 쉬는 행뿐이라
     * 골든 참조 칸이 쉬는 행인 장만 잰다(골든 사실로 고른다). 판정 규칙은 S 와 같다([ParityRules.Verdict.problems]).
     */
    @Test
    fun T3_L_단_쉬는_행_골든_픽셀_대조() {
        val rest = RepoBake.goldens.entries.filter { GoldenReplay.referenceCell(lib, it).group == BakeCell.Group.rest }
        assertEquals(Locks.L_REST_GOLDENS, rest.size, "쉬는 행 참조 골든 수")
        val all = verdicts("L") { g -> rest.any { it.index == g.index } }
        assertTrue(all.all { it.tier == "L" && it.cellId.startsWith("L:") }, "L 단으로 그렸다")
        val problems = all.flatMap { v -> v.problems().map { "${v.golden.id} [${v.cls}/${v.band}] $it" } }
        val text = summary("T3-L", all)
        println(text)
        assertTrue(problems.isEmpty(), "T3-L 실패 ${problems.size}건\n$text" + problems.take(40).joinToString("\n"))
        val clean = all.filter { it.cls == GoldenClass.clean }
        // 기기 T7-L 부분집합은 쉬는 행 참조 · 깨끗한 장이어야 한다.
        val t7 = all.filter { it.golden.index in GoldenReplay.T7_L_SUBSET }
        assertEquals(GoldenReplay.T7_L_SUBSET.size, t7.size, "T7-L 부분집합은 모두 쉬는 행 참조 장")
        assertTrue(t7.all { it.cls == GoldenClass.clean }, "T7-L 부분집합에 깨끗하지 않은 장: ${t7.filter { it.cls != GoldenClass.clean }.map { it.golden.id }}")
        assertTrue(clean.size >= Locks.L_CLEAN_MIN, "L 깨끗한 장 ${clean.size} < ${Locks.L_CLEAN_MIN}\n$text")
        val avgMean = clean.map { it.composite.mean }.average()
        assertTrue(avgMean <= Locks.L_CLEAN_MEAN_AVG_MAX, "L 깨끗한 장 평균 오차의 평균 ${"%.4f".format(avgMean)} > ${Locks.L_CLEAN_MEAN_AVG_MAX} — 그리기 품질 퇴행\n$text")
        val checked = all.filter { it.cls != GoldenClass.particles }
        val exceeds = checked.count { it.wrongExceedsThreshold }
        assertTrue(exceeds >= Locks.L_NEGATIVE_EXCEEDS_MIN, "L 음성 대조: 틀린 칸이 F 문턱을 넘은 장 $exceeds < ${Locks.L_NEGATIVE_EXCEEDS_MIN}\n$text")
    }

    /**
     * 잠금 값(실측 — ebb5565 의 골든, 맥 · ubuntu · windows-x64 · windows-arm64 같은 수치). 무리 분포는 골든 사실만으로 정하므로 다시 구워도 같다.
     * 깨끗한 장 · 음성 대조 하한은 입자 오염 42장을 뺀 값이다 — 조정자 패치 02(다시 구운 골든) 를 얹으면 패치 03 이 함께 올린다.
     */
    private object Locks {
        val BAND_DISTRIBUTION = mapOf(ParityBand.rigid to 69, ParityBand.bandUltra to 72, ParityBand.squashStretch to 49, ParityBand.spin to 50)
        val CLEAN_MIN = mapOf(ParityBand.rigid to 54, ParityBand.bandUltra to 63, ParityBand.squashStretch to 26, ParityBand.spin to 24)
        val NEGATIVE_EXCEEDS_MIN = mapOf(ParityBand.rigid to 42, ParityBand.bandUltra to 58, ParityBand.squashStretch to 21, ParityBand.spin to 32)
        const val L_REST_GOLDENS = 93
        const val L_CLEAN_MIN = 74
        const val L_NEGATIVE_EXCEEDS_MIN = 39
        /** 깨끗한 장 평균 오차(합집합 RGBA 평균)의 평균 상한 = 실측 + 0.05. */
        const val CLEAN_MEAN_AVG_MAX = 2.445
        const val L_CLEAN_MEAN_AVG_MAX = 1.725
    }

    @Test
    fun 지표_구현은_언어_무관_픽스처와_같다() {
        // 파이썬(탐침 probe-f `diff` 와 같은 정의, Kotlin 구현과 독립)으로 만든 7×5 프리멀티 두 장과 그 지표.
        val w = 7; val h = 5
        val a = intArrayOf(0, 0, 0, 0, 9, 127, 138, 127, 16, 0, 29, 30, 55, 8, 0, 127, 117, 104, 90, 127, 54, 118, 22, 127, 9, 21, 50, 127, 28, 177, 79, 255, 48, 9, 49, 30, 90, 126, 252, 255, 15, 18, 24, 30, 156, 188, 83, 255, 85, 25, 85, 127, 212, 59, 35, 255, 156, 68, 27, 255, 0, 0, 0, 0, 47, 134, 90, 128, 19, 0, 7, 30, 103, 107, 84, 128, 141, 113, 179, 255, 0, 22, 50, 30, 25, 47, 28, 30, 0, 0, 0, 0, 9, 15, 27, 128, 0, 0, 0, 0, 97, 52, 90, 127, 102, 71, 114, 128, 33, 142, 99, 128, 55, 27, 56, 127, 30, 131, 220, 200, 0, 0, 0, 0, 49, 152, 77, 255, 20, 68, 115, 127, 4, 135, 142, 127, 0, 0, 0, 0)
        val b = intArrayOf(63, 134, 65, 255, 228, 152, 96, 255, 20, 47, 140, 127, 169, 188, 151, 200, 237, 103, 2, 255, 3, 91, 125, 225, 90, 228, 92, 255, 160, 24, 242, 255, 0, 0, 0, 0, 32, 3, 21, 30, 0, 0, 0, 0, 213, 219, 127, 200, 0, 0, 0, 0, 232, 172, 139, 255, 33, 255, 56, 255, 21, 48, 24, 127, 4, 24, 25, 30, 146, 203, 47, 255, 0, 0, 0, 0, 0, 0, 0, 0, 66, 18, 24, 55, 83, 84, 119, 128, 0, 0, 0, 0, 119, 207, 109, 200, 141, 131, 131, 128, 83, 177, 167, 255, 169, 174, 96, 255, 157, 66, 82, 255, 10, 106, 75, 200, 69, 57, 38, 128, 0, 0, 0, 0, 0, 0, 0, 0, 39, 175, 47, 200, 153, 206, 0, 255, 82, 60, 3, 128)
        fun img(p: IntArray) = RgbaImage(w, h, ByteArray(p.size) { p[it].toByte() }, true)
        val d = ImageMetrics.diff(img(a), img(b))
        assertEquals(0.2962962962962963, d.iou, 1e-12)
        assertEquals(90.58333333333333, d.mean, 1e-9)
        assertEquals(0.9696969696969697, d.big, 1e-12)
        assertEquals(33, d.unionPixels)
        val same = ImageMetrics.diff(img(a), img(a))
        assertEquals(1.0, same.iou); assertEquals(0.0, same.mean)
    }
}
