// 원본: Sources/CheckCore/CharacterKit/SpriteAlphaMask.swift @ 1b8260d
package com.yehsung.aingcheck.character.sprite

import com.yehsung.aingcheck.character.render.RgbaImage
import com.yehsung.aingcheck.core.rules.character.CharacterManifest
import kotlin.math.floor

/**
 * 그림 전체의 1비트 불투명 마스크 — 클릭이 캐릭터 "몸"에 맞았는지 판정한다(평면 · 칸은 투명 여백에서도 사각형 안이다).
 * 스프라이트 아틀라스와 구운 칸이 같은 판정을 쓴다(임계 32 — 설계 F §5.3 "스프라이트와 같은 임계").
 *
 * INV-SpriteAlphaMask-67fc2c0d 이식: **UV 규약은 `py = v × 높이`, 뒤집지 않는다.** 행 0 = 그림 위쪽 줄(RGBA 데이터 순서 그대로).
 * 대칭 그림으로는 두 규약이 구별되지 않으므로 시험은 비대칭 픽스처(위 절반만 불투명)로만 문다(SpriteRuntimeTest).
 */
class SpriteAlphaMask private constructor(val width: Int, val height: Int, private val bits: ByteArray) {
    override fun toString(): String = "SpriteAlphaMask(${width}x$height)"

    /** UV(0..1, **그림 전체** 기준)가 불투명 픽셀인가. 범위 밖은 가장자리로 물린다(재질 wrap = clamp 와 같은 픽셀). */
    fun isOpaque(u: Double, v: Double): Boolean {
        if (!u.isFinite() || !v.isFinite()) return false
        val x = floor(u * width).toInt().coerceIn(0, width - 1)
        val y = floor(v * height).toInt().coerceIn(0, height - 1)
        return isOpaque(x, y)
    }

    /** 그림 픽셀 좌표(위-왼쪽 원점) 직접 조회. 밖이면 false. */
    fun isOpaque(x: Int, y: Int): Boolean {
        if (x < 0 || y < 0 || x >= width || y >= height) return false
        val index = y * width + x
        return (bits[index shr 3].toInt() and (1 shl (index and 7))) != 0
    }

    companion object {
        const val DEFAULT_THRESHOLD = 32

        /**
         * 그림에서 마스크를 굽는다(`alpha > threshold` = 불투명). [states] 는 교차 검증용: 매니페스트 프레임이 그림 밖이면
         * 매니페스트와 에셋이 갈린 것이라 null(호출부는 아잉으로 접는다). 64M 픽셀 넘는 그림도 null.
         */
        fun of(image: RgbaImage, states: Map<String, CharacterManifest.State> = emptyMap(), threshold: Int = DEFAULT_THRESHOLD): SpriteAlphaMask? {
            val w = image.width; val h = image.height
            if (w <= 0 || h <= 0 || w.toLong() * h > 64_000_000L) return null
            for (key in states.keys.sorted()) {
                for (r in states.getValue(key).frames) {
                    if (!(r.w > 0 && r.h > 0 && r.x >= 0 && r.y >= 0 && r.x + r.w <= w && r.y + r.h <= h)) return null
                }
            }
            val bits = ByteArray((w * h + 7) / 8)
            for (y in 0 until h) for (x in 0 until w) {
                if ((image.px[(y * w + x) * 4 + 3].toInt() and 0xFF) > threshold) {
                    val index = y * w + x
                    bits[index shr 3] = (bits[index shr 3].toInt() or (1 shl (index and 7))).toByte()
                }
            }
            return SpriteAlphaMask(w, h, bits)
        }
    }
}
