// 원본: 없음 (설계 F §2.2 · §6 지표 — 탐침 probe-f/probe.swift `diff(_:_:)` 와 같은 정의, 언어 무관 픽스처로 맞춘다)
package com.yehsung.aingcheck.character.render

import kotlin.math.abs
import kotlin.math.max

/**
 * 두 프리멀티 그림의 차이(F §2.2):
 *  - [iou] 알파 > 127 마스크의 IoU
 *  - [mean] 합집합(어느 쪽이든 알파 > 0) 픽셀의 RGBA 채널 평균 절대차(/255 척도 그대로, 0–255)
 *  - [big] 합집합 중 채널 최대 차가 32 를 넘는 픽셀 비율
 */
data class ImageDiff(val iou: Double, val mean: Double, val big: Double, val unionPixels: Int)

object ImageMetrics {
    fun diff(a: RgbaImage, b: RgbaImage): ImageDiff {
        require(a.width == b.width && a.height == b.height) { "크기가 다르다: ${a.width}x${a.height} vs ${b.width}x${b.height}" }
        var inter = 0; var uni = 0; var unionAny = 0; var big = 0
        var sum = 0L
        val n = a.width * a.height
        for (i in 0 until n) {
            val o = i * 4
            val aa = a.px[o + 3].toInt() and 0xFF
            val ba = b.px[o + 3].toInt() and 0xFF
            val am = aa > 127; val bm = ba > 127
            if (am && bm) inter++
            if (am || bm) uni++
            if (aa > 0 || ba > 0) {
                unionAny++
                var m = 0
                for (c in 0 until 4) {
                    val d = abs((a.px[o + c].toInt() and 0xFF) - (b.px[o + c].toInt() and 0xFF))
                    sum += d
                    m = max(m, d)
                }
                if (m > 32) big++
            }
        }
        return ImageDiff(
            iou = inter.toDouble() / max(uni, 1),
            mean = sum.toDouble() / max(unionAny * 4, 1),
            big = big.toDouble() / max(unionAny, 1),
            unionPixels = unionAny,
        )
    }
}

/**
 * T3 문턱(F §6) — 맥 실측(F §2.2)에 여유를 둔 값. 무리는 리액션으로 가른다.
 *  - 강체(idle·살랑·깜빡임·졸기·절·인사·롤) IoU ≥ 0.990 · 평균 ≤ 4
 *  - 띠 행 · 울트라 IoU ≥ 0.985 · 평균 ≤ 7
 *  - 찌부 · 늘림 정점 IoU ≥ 0.980 · 평균 ≤ 8
 *  - 스핀(10° × 4°) IoU ≥ 0.965 · 평균 ≤ 11
 */
enum class ParityBand(val minIou: Double, val maxMean: Double) {
    rigid(0.990, 4.0),
    bandUltra(0.985, 7.0),
    squashStretch(0.980, 8.0),
    spin(0.965, 11.0),
    ;

    fun passes(d: ImageDiff): Boolean = d.iou >= minIou && d.mean <= maxMean
}
