// 원본: 없음 (설계 G §2-6 F-1 실패 시 대안 "280×340 CPU 워프(Kotlin)" · 탐침 probe-f/probe.swift `warpH` 와 같은 역사상 이중선형)
package com.yehsung.aingcheck.character.render

import com.yehsung.aingcheck.character.bake.PixelRect
import com.yehsung.aingcheck.character.math.Homography
import com.yehsung.aingcheck.character.math.Vec2
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * 원근 그리기의 CPU 판(F-1 대안이자 시험의 독립 기준). 플랫폼 그리기(Skia `Matrix33` · Android `setPolyToPoly`)와 같은 일을
 * 순수 Kotlin 으로 한다: 대상 픽셀 중심을 H⁻¹ 로 원본에 되짚어 **프리멀티 이중선형**으로 읽고 src-over 로 얹는다.
 * 원본 사각형 밖은 투명으로 본다(칸 둘레에 여백이 있어 플랫폼의 가장자리 물기와 결과가 같다).
 */
object CpuWarp {
    /**
     * @param srcToDst 원본 그림 좌표(연속, 사각형 원점이 아니라 그림 원점) → 대상 픽셀.
     * @param linear false 면 최근접(픽셀아트).
     */
    fun drawQuad(dst: RgbaImage, src: RgbaImage, srcRect: PixelRect, srcToDst: Homography, linear: Boolean = true, alpha: Float = 1f) {
        require(dst.premultiplied && src.premultiplied) { "CPU 워프는 프리멀티끼리만 섞는다" }
        val inv = srcToDst.inverse()
        // 대상에서 칠할 상자: 원본 사각형 네 모서리의 상(像) 상자.
        val corners = listOf(
            Vec2(srcRect.x.toDouble(), srcRect.y.toDouble()), Vec2((srcRect.x + srcRect.w).toDouble(), srcRect.y.toDouble()),
            Vec2((srcRect.x + srcRect.w).toDouble(), (srcRect.y + srcRect.h).toDouble()), Vec2(srcRect.x.toDouble(), (srcRect.y + srcRect.h).toDouble()),
        )
        if (corners.any { srcToDst.denominator(it) <= 0 }) return // 사각형이 카메라 뒤로 넘어갔다 — 그리지 않는다
        val mapped = corners.map { srcToDst.map(it) }
        val x0 = max(0, floor(mapped.minOf { it.x }).toInt() - 1)
        val y0 = max(0, floor(mapped.minOf { it.y }).toInt() - 1)
        val x1 = min(dst.width - 1, ceil(mapped.maxOf { it.x }).toInt() + 1)
        val y1 = min(dst.height - 1, ceil(mapped.maxOf { it.y }).toInt() + 1)
        val acc = DoubleArray(4)
        val h = inv.h
        for (y in y0..y1) for (x in x0..x1) {
            val px = x + 0.5; val py = y + 0.5
            val w = h[6] * px + h[7] * py + h[8]
            if (w <= 0) continue
            val sx = (h[0] * px + h[1] * py + h[2]) / w
            val sy = (h[3] * px + h[4] * py + h[5]) / w
            if (!sample(src, srcRect, sx, sy, linear, acc)) continue
            if (alpha < 1f) for (c in 0 until 4) acc[c] *= alpha.toDouble()
            val sa = acc[3]
            if (sa <= 0.0 && acc[0] <= 0.0 && acc[1] <= 0.0 && acc[2] <= 0.0) continue
            val o = (y * dst.width + x) * 4
            val keep = 1.0 - sa / 255.0
            for (c in 0 until 4) {
                val d = dst.px[o + c].toInt() and 0xFF
                val v = acc[c] + d * keep
                dst.px[o + c] = v.roundHalfUp().coerceIn(0, 255).toByte()
            }
        }
    }

    private fun Double.roundHalfUp(): Int = floor(this + 0.5).toInt()

    /**
     * 볼록 사각형 단색 채우기(픽셀 중심이 안에 있으면 칠한다 — 가장자리 안티에일리어싱 없음). [color] 는 직선 ARGB.
     * 더하기는 프리멀티 색을 그대로 더하고(포화), src-over 는 프리멀티 섞기.
     */
    fun fillQuad(dst: RgbaImage, quad: List<Vec2>, color: Int, additive: Boolean) {
        val a = (color ushr 24) and 0xFF
        if (a == 0) return
        val pr = ((color ushr 16) and 0xFF) * a / 255.0
        val pg = ((color ushr 8) and 0xFF) * a / 255.0
        val pb = (color and 0xFF) * a / 255.0
        val x0 = max(0, floor(quad.minOf { it.x }).toInt()); val x1 = min(dst.width - 1, ceil(quad.maxOf { it.x }).toInt())
        val y0 = max(0, floor(quad.minOf { it.y }).toInt()); val y1 = min(dst.height - 1, ceil(quad.maxOf { it.y }).toInt())
        val src = doubleArrayOf(pr, pg, pb, a.toDouble())
        for (y in y0..y1) for (x in x0..x1) {
            if (!inside(quad, x + 0.5, y + 0.5)) continue
            val o = (y * dst.width + x) * 4
            val keep = if (additive) 1.0 else 1.0 - a / 255.0
            for (c in 0 until 4) {
                val d = (dst.px[o + c].toInt() and 0xFF) * keep
                dst.px[o + c] = (src[c] + d).roundHalfUp().coerceIn(0, 255).toByte()
            }
        }
    }

    private fun inside(q: List<Vec2>, x: Double, y: Double): Boolean {
        var sign = 0
        for (i in q.indices) {
            val a = q[i]; val b = q[(i + 1) % q.size]
            val cross = (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x)
            val s = if (cross > 0) 1 else if (cross < 0) -1 else 0
            if (s == 0) continue
            if (sign == 0) sign = s else if (s != sign) return false
        }
        return true
    }

    /** (sx, sy) 는 원본 그림 연속 좌표. 사각형 안 픽셀만 읽는다. 사각형과 전혀 안 겹치면 false. */
    private fun sample(src: RgbaImage, r: PixelRect, sx: Double, sy: Double, linear: Boolean, out: DoubleArray): Boolean {
        out.fill(0.0)
        if (!linear) {
            val ix = floor(sx).toInt(); val iy = floor(sy).toInt()
            if (ix < r.x || iy < r.y || ix >= r.x + r.w || iy >= r.y + r.h) return false
            val o = (iy * src.width + ix) * 4
            for (c in 0 until 4) out[c] = (src.px[o + c].toInt() and 0xFF).toDouble()
            return true
        }
        val fx = sx - 0.5; val fy = sy - 0.5
        val ix = floor(fx).toInt(); val iy = floor(fy).toInt()
        val tx = fx - ix; val ty = fy - iy
        if (ix + 1 < r.x || iy + 1 < r.y || ix >= r.x + r.w || iy >= r.y + r.h) return false
        tap(src, r, ix, iy, (1 - tx) * (1 - ty), out)
        tap(src, r, ix + 1, iy, tx * (1 - ty), out)
        tap(src, r, ix, iy + 1, (1 - tx) * ty, out)
        tap(src, r, ix + 1, iy + 1, tx * ty, out)
        return true
    }

    private fun tap(src: RgbaImage, r: PixelRect, xx: Int, yy: Int, w: Double, out: DoubleArray) {
        if (w == 0.0 || xx < r.x || yy < r.y || xx >= r.x + r.w || yy >= r.y + r.h) return
        val o = (yy * src.width + xx) * 4
        out[0] += w * (src.px[o].toInt() and 0xFF)
        out[1] += w * (src.px[o + 1].toInt() and 0xFF)
        out[2] += w * (src.px[o + 2].toInt() and 0xFF)
        out[3] += w * (src.px[o + 3].toInt() and 0xFF)
    }
}
