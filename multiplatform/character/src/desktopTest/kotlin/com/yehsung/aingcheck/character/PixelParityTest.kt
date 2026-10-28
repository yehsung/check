// 원본: 없음 (설계 F §6 T3 픽셀 · 음성 대조 — 데스크톱 Skia 래스터, ubuntu · windows-latest · windows-11-arm)
package com.yehsung.aingcheck.character

import com.yehsung.aingcheck.character.parity.GoldenClass
import com.yehsung.aingcheck.character.parity.GoldenReplay
import com.yehsung.aingcheck.character.parity.ParityRules
import com.yehsung.aingcheck.character.render.BakeImageStore
import com.yehsung.aingcheck.character.render.ImageMetrics
import com.yehsung.aingcheck.character.render.PlatformRaster
import com.yehsung.aingcheck.character.render.RgbaImage
import com.yehsung.aingcheck.character.render.asPremultiplied
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * T3: Kotlin 합성(후광 → 몸 칸 + 감은 눈 패치)을 **실제 그리기 함수**(Skia `Matrix33` 원근 · 래스터 표면)로 그려 맥 진짜 렌더 골든 240장과 맞댄다.
 * 판정 갈래는 골든 쪽 사실로만 정한다([ParityRules]). 깨끗한 장은 F §6 문턱 그대로, 모든 장(입자 오염 제외)에 음성 대조.
 */
class PixelParityTest {
    private val lib = RepoBake.library

    private fun verdicts(): List<ParityRules.Verdict> {
        val out = ArrayList<ParityRules.Verdict>()
        for ((folder, entries) in RepoBake.goldens.entries.groupBy { it.finishFolder }) {
            val finish = lib.finish(com.yehsung.aingcheck.character.bake.BakeLibrary.FOLDER_IDS.getValue(folder))!!
            val store = BakeImageStore(finish, RepoBake.files, PlatformRaster, pageCapacity = 2)
            try {
                for (g in entries) {
                    val golden = PlatformRaster.decodeRaw(RepoBake.goldenBytes(g)).asPremultiplied()
                    out += GoldenReplay.verdict(lib, PlatformRaster, store, g, golden)
                }
            } finally {
                store.close()
            }
        }
        return out
    }

    @Test
    fun T3_골든_240장_픽셀_대조와_음성_대조() {
        val all = verdicts()
        assertEquals(240, all.size)
        val problems = all.flatMap { v -> v.problems().map { "${v.golden.id} [${v.cls}/${v.band}] $it" } }
        val byClass = all.groupBy { it.cls }
        val clean = byClass[GoldenClass.clean].orEmpty()
        val summary = buildString {
            append("T3: 깨끗 ${clean.size} · 입자 ${byClass[GoldenClass.particles].orEmpty().size} · 후광 지연 ${byClass[GoldenClass.haloLag].orEmpty().size} · 격자 거칠음 ${byClass[GoldenClass.gridCoarse].orEmpty().size}\n")
            for ((band, vs) in clean.groupBy { it.band }) {
                append("  ${band.name}(${vs.size}): 최저 IoU ${"%.4f".format(vs.minOf { it.composite.iou })} · 최대 평균 ${"%.2f".format(vs.maxOf { it.composite.mean })}\n")
            }
            val checked = all.filter { it.cls != GoldenClass.particles }
            append("  음성 대조(${checked.size}장): 최소 비 ${"%.2f".format(checked.minOf { it.negativeRatio })} · F 문턱을 넘은 장 ${checked.count { it.wrongExceedsThreshold }}\n")
        }
        println(summary)
        assertTrue(problems.isEmpty(), "T3 실패 ${problems.size}건\n$summary" + problems.take(40).joinToString("\n"))
        // 면제가 조용히 늘지 않게 잠근다: 입자 오염은 굽기 결함(조정자 패치로 다시 구우면 0), 후광 지연 · 격자 거칠음은 맥 쪽 한계.
        assertTrue(clean.size >= 165, "깨끗한 장이 줄었다: ${clean.size}")
        assertEquals(3, byClass[GoldenClass.gridCoarse].orEmpty().size, "격자 거칠음은 울트라 찔림 표본 288 세 마감뿐")
        assertTrue(byClass[GoldenClass.particles].orEmpty().size <= 45)
        assertTrue(byClass[GoldenClass.haloLag].orEmpty().size <= 30)
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
