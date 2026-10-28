// 원본: 없음 (G §8-12·§8-13 — 칸은 프리멀티 바이트 그대로 · 디코드 클램프 `min(c, table[A])`)
package com.yehsung.aingcheck.character.render

import com.yehsung.aingcheck.character.bake.DecodeClampTable
import com.yehsung.aingcheck.character.bake.PixelRect

/**
 * RGBA8 래스터(행 우선, 행 0 = 위). [premultiplied] 가 참이면 색이 이미 알파를 곱한 값이다.
 * 구운 칸은 SceneKit 이 쓴 **sRGB 부호화 프리멀티 바이트 그대로**라 색이 알파를 넘을 수 있다(F §3.4 · G §8-12) — 직선으로 바꾸지 않는다.
 */
class RgbaImage(val width: Int, val height: Int, val px: ByteArray, val premultiplied: Boolean) {
    init {
        require(width >= 0 && height >= 0 && px.size == width * height * 4) { "RGBA 크기가 맞지 않다: ${width}x$height · ${px.size}" }
    }

    fun alpha(x: Int, y: Int): Int = if (x in 0 until width && y in 0 until height) px[(y * width + x) * 4 + 3].toInt() and 0xFF else 0

    fun channel(x: Int, y: Int, c: Int): Int = px[(y * width + x) * 4 + c].toInt() and 0xFF

    /** 사각형 하나를 잘라 새 그림으로(바깥은 투명). */
    fun crop(r: PixelRect): RgbaImage {
        val out = ByteArray(r.w * r.h * 4)
        for (y in 0 until r.h) {
            val sy = r.y + y
            if (sy !in 0 until height) continue
            for (x in 0 until r.w) {
                val sx = r.x + x
                if (sx !in 0 until width) continue
                val s = (sy * width + sx) * 4; val d = (y * r.w + x) * 4
                out[d] = px[s]; out[d + 1] = px[s + 1]; out[d + 2] = px[s + 2]; out[d + 3] = px[s + 3]
            }
        }
        return RgbaImage(r.w, r.h, out, premultiplied)
    }

    /** `patch` 를 (atX, atY) 에 **덮어쓰기**(복사 — 감은 눈 패치 규약, F §3.2-3). 새 그림을 돌려준다. */
    fun overwritten(patch: RgbaImage, atX: Int, atY: Int): RgbaImage {
        val out = px.copyOf()
        for (y in 0 until patch.height) {
            val dy = atY + y
            if (dy !in 0 until height) continue
            for (x in 0 until patch.width) {
                val dx = atX + x
                if (dx !in 0 until width) continue
                val s = (y * patch.width + x) * 4; val d = (dy * width + dx) * 4
                out[d] = patch.px[s]; out[d + 1] = patch.px[s + 1]; out[d + 2] = patch.px[s + 2]; out[d + 3] = patch.px[s + 3]
            }
        }
        return RgbaImage(width, height, out, premultiplied)
    }

    companion object {
        fun transparent(width: Int, height: Int) = RgbaImage(width, height, ByteArray(width * height * 4), true)
    }
}

/** 디코드 클램프(G §8-13 · manifest `bake.alpha.decodeClamp`). 손실 RGB 코덱 잡음이 알파 0 자리에 남긴 빛을 지운다. */
object DecodeClamp {
    /** 제자리에서 채널마다 `c := min(c, table[A])`. 바뀐 채널 수를 돌려준다(진단). */
    fun applyInPlace(image: RgbaImage, clamp: DecodeClampTable): Int {
        val t = clamp.table
        val p = image.px
        var changed = 0
        var i = 0
        while (i < p.size) {
            val limit = t[p[i + 3].toInt() and 0xFF]
            for (c in 0 until 3) {
                val v = p[i + c].toInt() and 0xFF
                if (v > limit) { p[i + c] = limit.toByte(); changed++ }
            }
            i += 4
        }
        return changed
    }
}

/** 직선 알파 → 프리멀티(정수 반올림 `(c·a + 127) / 255`) — 후광 PNG 를 CPU 경로로 그릴 때. */
fun RgbaImage.toPremultiplied(): RgbaImage {
    if (premultiplied) return this
    val out = ByteArray(px.size)
    var i = 0
    while (i < px.size) {
        val a = px[i + 3].toInt() and 0xFF
        for (c in 0 until 3) out[i + c] = (((px[i + c].toInt() and 0xFF) * a + 127) / 255).toByte()
        out[i + 3] = a.toByte()
        i += 4
    }
    return RgbaImage(width, height, out, true)
}
