// 원본: 없음 (설계 F §5.1 QuadDraw actual — 데스크톱 Skia `Matrix33`(원근 항 포함) · G §8-12 프리멀티 `kPremul` 그대로)
package com.yehsung.aingcheck.character.render

import androidx.compose.ui.graphics.nativeCanvas
import com.yehsung.aingcheck.character.bake.PixelRect
import com.yehsung.aingcheck.character.math.Homography
import com.yehsung.aingcheck.character.math.Vec2
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.BlendMode
import org.jetbrains.skia.Canvas
import org.jetbrains.skia.Codec
import org.jetbrains.skia.ColorAlphaType
import org.jetbrains.skia.ColorType
import org.jetbrains.skia.Data
import org.jetbrains.skia.FilterMipmap
import org.jetbrains.skia.FilterMode
import org.jetbrains.skia.Image
import org.jetbrains.skia.ImageInfo
import org.jetbrains.skia.Matrix33
import org.jetbrains.skia.MipmapMode
import org.jetbrains.skia.Paint
import org.jetbrains.skia.PathBuilder
import org.jetbrains.skia.Rect
import org.jetbrains.skia.Surface

/** Skia 그림(프리멀티 래스터 또는 인코딩된 지연 그림). */
class SkiaImage(val image: Image) : DrawableImage {
    override val width: Int get() = image.width
    override val height: Int get() = image.height
    override fun close() = image.close()
}

/** 아무 Skia 캔버스(Compose `nativeCanvas` · 래스터 표면)에 원근 사각형을 그린다. */
class SkiaQuadCanvas(val canvas: Canvas) : QuadCanvas {
    override fun drawImageQuad(image: DrawableImage, srcRect: PixelRect, srcToDst: Homography, linear: Boolean, alpha: Float) {
        val skia = (image as? SkiaImage)?.image ?: error("Skia 캔버스에는 SkiaImage 만 그린다")
        val h = srcToDst.h
        val m = Matrix33(
            h[0].toFloat(), h[1].toFloat(), h[2].toFloat(),
            h[3].toFloat(), h[4].toFloat(), h[5].toFloat(),
            h[6].toFloat(), h[7].toFloat(), h[8].toFloat(),
        )
        val r = Rect.makeXYWH(srcRect.x.toFloat(), srcRect.y.toFloat(), srcRect.w.toFloat(), srcRect.h.toFloat())
        val sampling = if (linear) FilterMipmap(FilterMode.LINEAR, MipmapMode.NONE) else FilterMipmap(FilterMode.NEAREST, MipmapMode.NONE)
        canvas.save()
        canvas.concat(m)
        Paint().use { paint ->
            paint.isAntiAlias = true
            if (alpha < 1f) paint.alpha = (alpha.coerceIn(0f, 1f) * 255).toInt()
            // strict = true: 사각형 밖 텍셀을 이중선형이 물지 않게(이웃 칸 · 손실 매크로블록 번짐).
            canvas.drawImageRect(skia, r, r, sampling, paint, true)
        }
        canvas.restore()
    }

    override fun fillQuad(quad: List<Vec2>, color: Int, additive: Boolean) {
        val builder = PathBuilder()
        builder.moveTo(quad[0].x.toFloat(), quad[0].y.toFloat())
        for (i in 1 until quad.size) builder.lineTo(quad[i].x.toFloat(), quad[i].y.toFloat())
        builder.closePath()
        val path = builder.detach()
        builder.close()
        Paint().use { paint ->
            paint.color = color
            paint.isAntiAlias = true
            paint.blendMode = if (additive) BlendMode.PLUS else BlendMode.SRC_OVER
            canvas.drawPath(path, paint)
        }
        path.close()
    }
}

private class SkiaRasterSurface(override val width: Int, override val height: Int) : RasterSurface {
    private val info = ImageInfo(width, height, ColorType.RGBA_8888, ColorAlphaType.PREMUL)
    private val surface: Surface = Surface.makeRaster(info)
    private val quad = SkiaQuadCanvas(surface.canvas)

    override fun clear() { surface.canvas.clear(0) }

    override fun readPixels(): RgbaImage {
        val bitmap = Bitmap()
        try {
            check(bitmap.allocPixels(info)) { "비트맵 할당 실패" }
            check(surface.readPixels(bitmap, 0, 0)) { "표면 읽기 실패" }
            val bytes = bitmap.readPixels(info, width * 4, 0, 0) ?: error("비트맵 바이트 읽기 실패")
            return RgbaImage(width, height, bytes, true)
        } finally {
            bitmap.close()
        }
    }

    override fun close() = surface.close()

    override fun drawImageQuad(image: DrawableImage, srcRect: PixelRect, srcToDst: Homography, linear: Boolean, alpha: Float) =
        quad.drawImageQuad(image, srcRect, srcToDst, linear, alpha)

    override fun fillQuad(quad: List<Vec2>, color: Int, additive: Boolean) = this.quad.fillQuad(quad, color, additive)
}

actual object PlatformRaster : RasterFactory {
    override fun imageFromPremultiplied(rgba: RgbaImage): DrawableImage {
        require(rgba.premultiplied) { "프리멀티 바이트만 받는다" }
        val info = ImageInfo(rgba.width, rgba.height, ColorType.RGBA_8888, ColorAlphaType.PREMUL)
        return SkiaImage(Image.makeRaster(info, rgba.px, rgba.width * 4))
    }

    override fun decodeStraight(encoded: ByteArray): DrawableImage = SkiaImage(Image.makeFromEncoded(encoded))

    override fun decodeRaw(encoded: ByteArray): RgbaImage {
        Data.makeFromBytes(encoded).use { data ->
            Codec.makeFromData(data).use { codec ->
                val w = codec.width; val h = codec.height
                // UNPREMUL 로 받으면 libwebp 가 파일에 든 바이트를 그대로 준다(곱하지 않는다). 색 공간 없음 = 변환 없음.
                val info = ImageInfo(w, h, ColorType.RGBA_8888, ColorAlphaType.UNPREMUL)
                val bitmap = Bitmap()
                try {
                    check(bitmap.allocPixels(info)) { "비트맵 할당 실패" }
                    codec.readPixels(bitmap)
                    val bytes = bitmap.readPixels(info, w * 4, 0, 0) ?: error("디코드 바이트 읽기 실패")
                    return RgbaImage(w, h, bytes, false)
                } finally {
                    bitmap.close()
                }
            }
        }
    }

    override fun newSurface(width: Int, height: Int): RasterSurface = SkiaRasterSurface(width, height)
}

actual fun quadCanvasOf(canvas: androidx.compose.ui.graphics.Canvas): QuadCanvas =
    SkiaQuadCanvas(canvas.nativeCanvas)
