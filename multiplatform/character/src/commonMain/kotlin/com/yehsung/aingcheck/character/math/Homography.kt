// 원본: 없음 (설계 F §2.1 C · §5.3 — 4점 원근 정합. 식은 탐침 probe-f/probe.swift `homography(from:to:)` 와 같다)
package com.yehsung.aingcheck.character.math

import kotlin.math.abs

/**
 * 3×3 원근 사상(호모그래피) `d = H · s`, **행 우선** 9칸(`h[row * 3 + col]`, `h[8]` = 1 로 정규화).
 * 칸 픽셀(연속 좌표) → 화면 픽셀(연속 좌표). Skia `Matrix33` · Android `Matrix.setValues` 와 같은 배치다.
 */
class Homography(val h: DoubleArray) {
    init {
        require(h.size == 9) { "호모그래피는 9칸이다" }
    }

    fun map(p: Vec2): Vec2 {
        val w = h[6] * p.x + h[7] * p.y + h[8]
        return Vec2((h[0] * p.x + h[1] * p.y + h[2]) / w, (h[3] * p.x + h[4] * p.y + h[5]) / w)
    }

    /** 점이 원근 분모가 양인 쪽(사각형 앞면)에 있는가. */
    fun denominator(p: Vec2): Double = h[6] * p.x + h[7] * p.y + h[8]

    operator fun times(o: Homography): Homography {
        val r = DoubleArray(9)
        for (row in 0 until 3) for (c in 0 until 3) {
            var s = 0.0
            for (k in 0 until 3) s += h[row * 3 + k] * o.h[k * 3 + c]
            r[row * 3 + c] = s
        }
        return Homography(r).normalized()
    }

    fun normalized(): Homography {
        val s = h[8]
        return if (s != 0.0 && s != 1.0) Homography(DoubleArray(9) { h[it] / s }) else this
    }

    fun inverse(): Homography {
        val a = h
        val det = a[0] * (a[4] * a[8] - a[5] * a[7]) - a[1] * (a[3] * a[8] - a[5] * a[6]) + a[2] * (a[3] * a[7] - a[4] * a[6])
        require(abs(det) > 1e-300) { "특이 호모그래피" }
        val inv = doubleArrayOf(
            a[4] * a[8] - a[5] * a[7], a[2] * a[7] - a[1] * a[8], a[1] * a[5] - a[2] * a[4],
            a[5] * a[6] - a[3] * a[8], a[0] * a[8] - a[2] * a[6], a[2] * a[3] - a[0] * a[5],
            a[3] * a[7] - a[4] * a[6], a[1] * a[6] - a[0] * a[7], a[0] * a[4] - a[1] * a[3],
        )
        return Homography(DoubleArray(9) { inv[it] / det }).normalized()
    }

    /** 원근 항이 있는가(아핀이 아닌가). */
    val isPerspective: Boolean get() = abs(h[6]) > 1e-15 || abs(h[7]) > 1e-15

    companion object {
        val IDENTITY = Homography(doubleArrayOf(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0))

        fun translation(dx: Double, dy: Double) = Homography(doubleArrayOf(1.0, 0.0, dx, 0.0, 1.0, dy, 0.0, 0.0, 1.0))

        /**
         * 네 점 대응 s[i] → d[i] 의 호모그래피. 8 미지수 선형계를 부분 피벗 가우스 소거로 푼다(탐침과 같은 식).
         * 세 점이 한 줄이면(퇴화) null.
         */
        fun fromQuads(src: List<Vec2>, dst: List<Vec2>): Homography? {
            require(src.size == 4 && dst.size == 4) { "네 점씩 준다" }
            val a = Array(8) { DoubleArray(9) }
            for (i in 0 until 4) {
                val x = src[i].x; val y = src[i].y; val u = dst[i].x; val v = dst[i].y
                a[2 * i] = doubleArrayOf(x, y, 1.0, 0.0, 0.0, 0.0, -u * x, -u * y, u)
                a[2 * i + 1] = doubleArrayOf(0.0, 0.0, 0.0, x, y, 1.0, -v * x, -v * y, v)
            }
            for (c in 0 until 8) {
                var p = c
                for (r in c + 1 until 8) if (abs(a[r][c]) > abs(a[p][c])) p = r
                if (abs(a[p][c]) < 1e-12) return null
                val t = a[p]; a[p] = a[c]; a[c] = t
                for (r in 0 until 8) if (r != c) {
                    val f = a[r][c] / a[c][c]
                    if (f != 0.0) for (k in c until 9) a[r][k] -= f * a[c][k]
                }
            }
            val out = DoubleArray(9)
            for (i in 0 until 8) out[i] = a[i][8] / a[i][i]
            out[8] = 1.0
            return Homography(out)
        }
    }
}
