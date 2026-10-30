// 원본: CheckOverlayWindow.swift :779-853(몸 판정 · 말풍선 특례) · :2250-2300(히트 뷰) — Windows 는 픽셀 알파가 판정이라 특례가 필요 없다(D §9-1)
//       설계 F §5.3~5.4(오프스크린 프리멀티 표면 → 창) · overlay.md §4 I-3(b2 는 OverlayView 만 그린다) · I-5(HitTarget 은 b2)
//
// 한 프레임 = Skia RGBA8 프리멀티 표면에 ① 캐릭터 층(CharacterPlayer → CharacterFrames.draw) ② 말풍선(BubblePainter)을 겹친 바이트.
// 창에는 BGRA 로 바꿔 UpdateLayeredWindow 로 올린다. **이 프레임의 알파가 곧 클릭 판정**이라(알파 0 = 뒤 창으로) 그림자·후광처럼
// 몸·캡슐 밖으로 번지는 것은 그리지 않는다(OverlayCompositorTest 가 잠근다).
package com.yehsung.aingcheck.desktop.overlay.render

import com.yehsung.aingcheck.character.render.QuadCanvas
import com.yehsung.aingcheck.character.render.SkiaQuadCanvas
import com.yehsung.aingcheck.desktop.overlay.bubble.BubbleLayout
import com.yehsung.aingcheck.desktop.overlay.bubble.BubblePainter
import com.yehsung.aingcheck.desktop.overlay.bubble.PretendardBubbleMeasure
import com.yehsung.aingcheck.desktop.overlay.engine.BubbleKind
import com.yehsung.aingcheck.desktop.overlay.engine.HitTarget
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayMode
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayView
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.ColorAlphaType
import org.jetbrains.skia.ColorType
import org.jetbrains.skia.ImageInfo
import org.jetbrains.skia.Surface

/** 캐릭터(와 파티클) 층. 앱은 [PlayerCharacterLayer], 시험은 합성 도형. */
fun interface CharacterLayer {
    fun draw(canvas: QuadCanvas, widthPx: Int, heightPx: Int, now: Double)
}

/** 픽셀 사각형(반열림: right·bottom 제외). */
data class PxRect(val left: Int, val top: Int, val right: Int, val bottom: Int) {
    fun contains(x: Int, y: Int): Boolean = x >= left && x < right && y >= top && y < bottom
}

/** 바이트 순서 바꾸기 — 둘 다 프리멀티라 값은 그대로, 자리만. */
object PixelFormats {
    fun rgbaToBgra(src: ByteArray, dst: ByteArray = ByteArray(src.size)): ByteArray {
        require(src.size % 4 == 0 && dst.size == src.size)
        var i = 0
        while (i < src.size) {
            val r = src[i]
            dst[i] = src[i + 2]
            dst[i + 1] = src[i + 1]
            dst[i + 2] = r
            dst[i + 3] = src[i + 3]
            i += 4
        }
        return dst
    }
}

/** 합성된 한 프레임(행 0 = 위, RGBA8 프리멀티). [bubble] 은 그린 말풍선의 자리(없으면 null). */
class ComposedOverlay(
    val width: Int,
    val height: Int,
    val rgbaPremultiplied: ByteArray,
    val scale: Double = 1.0,
    val bubble: BubbleLayout? = null,
    val bubbleKind: BubbleKind? = null,
) {
    init {
        require(rgbaPremultiplied.size == width * height * 4) { "바이트 수가 ${width}x$height 와 다르다" }
    }

    val bubbleRectPx: PxRect? = bubble?.capsule?.let { c ->
        PxRect(
            kotlin.math.floor(c.left * scale).toInt(), kotlin.math.floor(c.top * scale).toInt(),
            kotlin.math.ceil(c.right * scale).toInt(), kotlin.math.ceil(c.bottom * scale).toInt(),
        )
    }

    fun alphaAt(x: Int, y: Int): Int =
        if (x < 0 || y < 0 || x >= width || y >= height) 0 else rgbaPremultiplied[(y * width + x) * 4 + 3].toInt() and 0xFF

    /**
     * I-5 — 창이 받은 클릭 자리의 대상. OS 가 알파 0 픽셀은 이미 뒤 창으로 보냈으므로 여기 오는 점은 대개 알파>0 이다.
     * 말풍선 캡슐 안이면 Bubble(누를 수 있는지는 엔진이 kind 로 정한다), 그 밖의 알파>0 은 Body.
     */
    fun hitTarget(x: Int, y: Int): HitTarget = when {
        alphaAt(x, y) == 0 -> HitTarget.None
        bubbleRectPx?.contains(x, y) == true -> HitTarget.Bubble
        else -> HitTarget.Body
    }

    fun toBgraPremultiplied(): ByteArray = PixelFormats.rgbaToBgra(rgbaPremultiplied)

    companion object {
        fun empty(width: Int, height: Int): ComposedOverlay = ComposedOverlay(width, height, ByteArray(width * height * 4))
    }
}

/** I-3 그리기. 표면은 크기별로 하나를 다시 쓴다. 한 스레드(렌더 실행기)에서만 부른다. */
class OverlayCompositor(private val measure: PretendardBubbleMeasure = PretendardBubbleMeasure.bundled) : AutoCloseable {
    private var surface: Surface? = null
    private var info: ImageInfo? = null

    private fun surfaceFor(w: Int, h: Int): Surface {
        val cur = surface
        if (cur != null && info?.width == w && info?.height == h) return cur
        cur?.close()
        val i = ImageInfo(w, h, ColorType.RGBA_8888, ColorAlphaType.PREMUL)
        return Surface.makeRaster(i).also { surface = it; info = i }
    }

    /**
     * [view] 를 [widthPx]×[heightPx] 픽셀(DIP × [scale])로 그린다. 숨김이면 전부 투명.
     * 말풍선은 `now < until` 일 때만(엔진이 지운 뒤 한 프레임 늦게 남지 않게).
     */
    fun compose(view: OverlayView, widthPx: Int, heightPx: Int, scale: Double, now: Double, character: CharacterLayer?): ComposedOverlay {
        require(widthPx > 0 && heightPx > 0 && scale > 0)
        val s = surfaceFor(widthPx, heightPx)
        val canvas = s.canvas
        canvas.clear(0)
        var layout: BubbleLayout? = null
        val bubble = view.bubble?.takeIf { now < it.until }
        if (view.mode != OverlayMode.Hidden) {
            character?.draw(SkiaQuadCanvas(canvas), widthPx, heightPx, now)
            if (bubble != null) layout = BubblePainter.paint(canvas, bubble, measure, scale)
        }
        return ComposedOverlay(widthPx, heightPx, readPixels(s), scale, layout, if (layout != null) bubble?.kind else null)
    }

    private fun readPixels(s: Surface): ByteArray {
        val i = info!!
        val bitmap = Bitmap()
        try {
            check(bitmap.allocPixels(i)) { "비트맵 할당 실패" }
            check(s.readPixels(bitmap, 0, 0)) { "표면 읽기 실패" }
            return bitmap.readPixels(i, i.width * 4, 0, 0) ?: error("비트맵 바이트 읽기 실패")
        } finally {
            bitmap.close()
        }
    }

    override fun close() {
        surface?.close()
        surface = null
        info = null
    }
}
