// 원본: 없음 (설계 G §2-6 · F §9-1 실험 F-1 — 원근 행렬로 그림 그리기. 데스크톱 Skiko `Canvas.concat(Matrix33)`)
package com.yehsung.aingcheck.character

import com.yehsung.aingcheck.character.bake.PixelRect
import com.yehsung.aingcheck.character.math.Homography
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.render.CpuRaster
import com.yehsung.aingcheck.character.render.ImageMetrics
import com.yehsung.aingcheck.character.render.PlatformRaster
import com.yehsung.aingcheck.character.render.RasterFactory
import com.yehsung.aingcheck.character.render.RgbaImage
import kotlin.math.floor
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * F-1: 알려진 사각형으로 체커보드를 호모그래피 그리기 → 네 모서리 픽셀 위치 · 보간 품질. 독립 기준은 순수 Kotlin CPU 워프(역사상 이중선형).
 * 음성 대조: 같은 사각형을 아핀(세 점)으로 그리면 문턱을 넘어야 한다 — 원근 항을 버리는 그리기는 여기서 빨개진다.
 */
class PerspectiveDrawTest {
    companion object {
        const val N = 64
        /** 원근이 센 사각형(TL · TR · BR · BL) — 위 변이 아래 변보다 짧다. */
        val QUAD = listOf(Vec2(70.3, 40.6), Vec2(190.2, 52.1), Vec2(236.8, 287.4), Vec2(30.9, 262.2))

        /** 8px 칸 체커보드, 사분면마다 다른 색(프리멀티 = 불투명이라 같음) + 투명 테두리 2px. */
        fun checker(): RgbaImage {
            val px = ByteArray(N * N * 4)
            for (y in 0 until N) for (x in 0 until N) {
                val o = (y * N + x) * 4
                if (x < 2 || y < 2 || x >= N - 2 || y >= N - 2) continue
                val on = ((x / 8) + (y / 8)) % 2 == 0
                val q = (if (x < N / 2) 0 else 1) + (if (y < N / 2) 0 else 2)
                val base = intArrayOf(0xE0_30_30, 0x30_C0_30, 0x30_30_E0, 0xE0_C0_30)[q]
                val c = if (on) base else 0x20_20_20
                px[o] = (c shr 16).toByte(); px[o + 1] = (c shr 8).toByte(); px[o + 2] = c.toByte(); px[o + 3] = 0xFF.toByte()
            }
            return RgbaImage(N, N, px, true)
        }

        fun draw(raster: RasterFactory, h: Homography): RgbaImage {
            val s = raster.newSurface(280, 340)
            try {
                s.clear()
                val img = raster.imageFromPremultiplied(checker())
                s.drawImageQuad(img, PixelRect(0, 0, N, N), h)
                img.close()
                return s.readPixels()
            } finally {
                s.close()
            }
        }

        val CORNERS = listOf(Vec2(0.0, 0.0), Vec2(N.toDouble(), 0.0), Vec2(N.toDouble(), N.toDouble()), Vec2(0.0, N.toDouble()))
    }

    private fun color(img: RgbaImage, p: Vec2): Int {
        val x = floor(p.x).toInt(); val y = floor(p.y).toInt()
        val o = (y * img.width + x) * 4
        return ((img.px[o].toInt() and 0xFF) shl 16) or ((img.px[o + 1].toInt() and 0xFF) shl 8) or (img.px[o + 2].toInt() and 0xFF)
    }

    @Test
    fun F1_스키아_원근_그리기가_CPU_워프_기준과_같다() {
        val h = Homography.fromQuads(CORNERS, QUAD)!!
        assertTrue(h.isPerspective, "원근 항이 있는 사각형이어야 실험이 된다")
        val skia = draw(PlatformRaster, h)
        val cpu = draw(CpuRaster(PlatformRaster), h)
        val d = ImageMetrics.diff(skia, cpu)
        println("F-1 데스크톱: Skia vs CPU 워프 IoU ${"%.5f".format(d.iou)} · 평균 ${"%.3f".format(d.mean)} · 32 넘는 픽셀 ${"%.4f".format(d.big)}")
        assertTrue(d.iou >= 0.995 && d.mean <= 2.0, "원근 그리기가 기준과 다르다: $d")

        // 네 사분면 칸 중심이 원근 사상한 자리에 그 색으로 있다(아핀이면 아래쪽 칸이 수 px 밀린다).
        for ((sx, sy, rgb) in listOf(Triple(4.5 + 8, 4.5 + 8, 0xE0_30_30), Triple(52.0, 12.0, 0x30_C0_30), Triple(12.0, 52.0, 0x30_30_E0), Triple(52.0, 52.0, 0xE0_C0_30))) {
            val center = Vec2(floor(sx / 8) * 8 + 4.0, floor(sy / 8) * 8 + 4.0)
            val on = ((center.x.toInt() / 8) + (center.y.toInt() / 8)) % 2 == 0
            val expected = if (on) rgb else 0x20_20_20
            assertEquals(expected, color(skia, h.map(center)), "칸 중심 $center → ${h.map(center)}")
        }
    }

    @Test
    fun F1_음성_대조_아핀으로_그리면_문턱을_넘는다() {
        val h = Homography.fromQuads(CORNERS, QUAD)!!
        // 세 점(TL · TR · BL)만 맞춘 아핀: 네 번째 꼭짓점은 평행사변형 자리로 간다.
        val affineQuad = listOf(QUAD[0], QUAD[1], Vec2(QUAD[1].x + QUAD[3].x - QUAD[0].x, QUAD[1].y + QUAD[3].y - QUAD[0].y), QUAD[3])
        val affine = Homography.fromQuads(CORNERS, affineQuad)!!
        assertTrue(!affine.isPerspective)
        val cpu = draw(CpuRaster(PlatformRaster), h)
        val wrong = draw(PlatformRaster, affine)
        val d = ImageMetrics.diff(wrong, cpu)
        assertTrue(d.iou < 0.98 || d.mean > 8.0, "원근을 버린 그리기가 문턱 안이다(실험이 무디다): $d")
    }
}
