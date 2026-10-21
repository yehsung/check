// 원본: 없음 — 색 차 CIEDE2000(Sharma·Wu·Dalal 2005, "The CIEDE2000 Color-Difference Formula: Implementation Notes,
// Supplementary Test Data, and Mathematical Observations", 식 1~22). 시험 도구다(앱에 실리지 않는다).
//
// sRGB(D65) → CIE XYZ → L*a*b* → ΔE00. 쓰는 곳: "AI 토큰 보라가 주요색(primary 보라)과 나란히 놓여도 구분된다"(G §8-13).
// 식이 맞는지는 같은 논문 표 1 의 기준 쌍과 sRGB 빨강의 L*a*b*(53.2408, 80.0925, 67.2032)로 검산한다(AingThemeRulesTest).
package com.yehsung.aingcheck.ui.theme

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cbrt
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

internal object ColorDifference {
    data class Lab(val l: Double, val a: Double, val b: Double)

    /**
     * 나란히 놓았을 때 "구분된다"의 문턱. ΔE00 1 ≈ 나란히 본 최소 식별 차, 인쇄 업계의 "같은 색" 허용치가 2 안팎이다.
     * 그 허용치 위로 여유를 둔 3 을 "같은 색으로 읽히지 않는다"의 하한으로 쓴다(멀리서 한눈에 갈리는 정도는 아니다 — 보고서에 실측값).
     */
    const val SIDE_BY_SIDE_DISTINCT = 3.0

    private fun linear(c: Double) = if (c <= 0.04045) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)

    /** 불투명 sRGB → L*a*b*(D65 백색점 0.95047 · 1 · 1.08883). */
    fun lab(c: AingRgb): Lab {
        require(c.alpha == 1.0) { "반투명 색은 놓일 면 위에 겹친 뒤 잰다: $c" }
        val r = linear(c.r)
        val g = linear(c.g)
        val b = linear(c.b)
        val x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
        val y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        val z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b
        fun f(t: Double) = if (t > 216.0 / 24389.0) cbrt(t) else (24389.0 / 27.0 * t + 16.0) / 116.0
        val fx = f(x / 0.95047)
        val fy = f(y / 1.0)
        val fz = f(z / 1.08883)
        return Lab(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    fun ciede2000(x: AingRgb, y: AingRgb): Double = ciede2000(lab(x), lab(y))

    fun ciede2000(p: Lab, q: Lab): Double {
        fun deg(rad: Double) = rad * 180.0 / PI
        fun rad(deg: Double) = deg * PI / 180.0
        val c1 = sqrt(p.a * p.a + p.b * p.b)
        val c2 = sqrt(q.a * q.a + q.b * q.b)
        val cBar = (c1 + c2) / 2
        val g = 0.5 * (1 - sqrt(cBar.pow(7) / (cBar.pow(7) + 25.0.pow(7))))
        val a1 = (1 + g) * p.a
        val a2 = (1 + g) * q.a
        val c1p = sqrt(a1 * a1 + p.b * p.b)
        val c2p = sqrt(a2 * a2 + q.b * q.b)
        fun hue(b: Double, a: Double) = if (b == 0.0 && a == 0.0) 0.0 else (deg(atan2(b, a)) + 360.0) % 360.0
        val h1 = hue(p.b, a1)
        val h2 = hue(q.b, a2)
        val dL = q.l - p.l
        val dC = c2p - c1p
        val dh = when {
            c1p * c2p == 0.0 -> 0.0
            abs(h2 - h1) <= 180 -> h2 - h1
            h2 - h1 > 180 -> h2 - h1 - 360
            else -> h2 - h1 + 360
        }
        val dH = 2 * sqrt(c1p * c2p) * sin(rad(dh / 2))
        val lBar = (p.l + q.l) / 2
        val cBarP = (c1p + c2p) / 2
        val hBar = when {
            c1p * c2p == 0.0 -> h1 + h2
            abs(h1 - h2) <= 180 -> (h1 + h2) / 2
            h1 + h2 < 360 -> (h1 + h2 + 360) / 2
            else -> (h1 + h2 - 360) / 2
        }
        val t = 1 - 0.17 * cos(rad(hBar - 30)) + 0.24 * cos(rad(2 * hBar)) + 0.32 * cos(rad(3 * hBar + 6)) - 0.20 * cos(rad(4 * hBar - 63))
        val dTheta = 30 * exp(-((hBar - 275) / 25).pow(2))
        val rc = 2 * sqrt(cBarP.pow(7) / (cBarP.pow(7) + 25.0.pow(7)))
        val sl = 1 + 0.015 * (lBar - 50).pow(2) / sqrt(20 + (lBar - 50).pow(2))
        val sc = 1 + 0.045 * cBarP
        val sh = 1 + 0.015 * cBarP * t
        val rt = -sin(rad(2 * dTheta)) * rc
        return sqrt((dL / sl).pow(2) + (dC / sc).pow(2) + (dH / sh).pow(2) + rt * (dC / sc) * (dH / sh))
    }
}
