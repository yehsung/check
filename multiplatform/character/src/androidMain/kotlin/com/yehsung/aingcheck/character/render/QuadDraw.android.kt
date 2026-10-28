// 원본: 없음 (설계 F §5.1 QuadDraw actual — Android `Matrix.setValues`(원근 항 포함) · G §8-12 premultiplied Bitmap 에 copyPixelsFromBuffer)
package com.yehsung.aingcheck.character.render

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import androidx.compose.ui.graphics.nativeCanvas
import com.yehsung.aingcheck.character.bake.PixelRect
import com.yehsung.aingcheck.character.math.Homography
import com.yehsung.aingcheck.character.math.Vec2
import java.nio.ByteBuffer

/**
 * Android 그림. [bitmap] 은 언제나 premultiplied ARGB_8888 이다(메모리 바이트 순서 R, G, B, A).
 * 사각형을 따로 잘라 둔 그림이면 [origin] 이 원래 그림 좌표의 원점이다(사각형 밖을 물지 않게 — Android 에는 strict 가 없다).
 */
class AndroidImage(val bitmap: Bitmap, val originX: Int = 0, val originY: Int = 0) : DrawableImage {
    override val width: Int get() = bitmap.width
    override val height: Int get() = bitmap.height
    override fun close() = bitmap.recycle()
}

/** 아무 Android 캔버스(소프트웨어 Bitmap 캔버스 · HWUI RecordingCanvas · Compose `nativeCanvas`)에 원근 사각형을 그린다. */
class AndroidQuadCanvas(val canvas: Canvas) : QuadCanvas {
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
    private val nearest = Paint(Paint.ANTI_ALIAS_FLAG)

    override fun drawImageQuad(image: DrawableImage, srcRect: PixelRect, srcToDst: Homography, linear: Boolean, alpha: Float) {
        val img = image as? AndroidImage ?: error("Android 캔버스에는 AndroidImage 만 그린다")
        // 사각형만 담은 비트맵을 그 원점에서 그린다 — 원래 그림 좌표 (x, y) = 비트맵 (x − originX, y − originY).
        val (bmp, ox, oy) = if (img.originX == srcRect.x && img.originY == srcRect.y && img.width == srcRect.w && img.height == srcRect.h) {
            Triple(img.bitmap, img.originX, img.originY)
        } else {
            val sub = Bitmap.createBitmap(img.bitmap, srcRect.x - img.originX, srcRect.y - img.originY, srcRect.w, srcRect.h)
            Triple(sub, srcRect.x, srcRect.y)
        }
        val h = (srcToDst * Homography.translation(ox.toDouble(), oy.toDouble())).h
        val m = Matrix()
        m.setValues(FloatArray(9) { h[it].toFloat() })
        val p = if (linear) paint else nearest
        p.alpha = (alpha.coerceIn(0f, 1f) * 255).toInt()
        canvas.save()
        canvas.concat(m)
        canvas.drawBitmap(bmp, 0f, 0f, p)
        canvas.restore()
        p.alpha = 255
        if (bmp !== img.bitmap) bmp.recycle()
    }

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)

    override fun fillQuad(quad: List<Vec2>, color: Int, additive: Boolean) {
        val path = Path()
        path.moveTo(quad[0].x.toFloat(), quad[0].y.toFloat())
        for (i in 1 until quad.size) path.lineTo(quad[i].x.toFloat(), quad[i].y.toFloat())
        path.close()
        fill.color = color
        fill.xfermode = if (additive) PorterDuffXfermode(PorterDuff.Mode.ADD) else null
        canvas.drawPath(path, fill)
    }
}

private class AndroidRasterSurface(override val width: Int, override val height: Int) : RasterSurface {
    val bitmap: Bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { it.isPremultiplied = true }
    private val canvas = Canvas(bitmap)
    private val quad = AndroidQuadCanvas(canvas)

    override fun clear() { bitmap.eraseColor(0); canvas.drawColor(0, PorterDuff.Mode.CLEAR) }

    override fun readPixels(): RgbaImage {
        val buf = ByteBuffer.allocate(width * height * 4)
        bitmap.copyPixelsToBuffer(buf)
        return RgbaImage(width, height, buf.array(), true)
    }

    override fun close() = bitmap.recycle()

    override fun drawImageQuad(image: DrawableImage, srcRect: PixelRect, srcToDst: Homography, linear: Boolean, alpha: Float) =
        quad.drawImageQuad(image, srcRect, srcToDst, linear, alpha)

    override fun fillQuad(quad: List<Vec2>, color: Int, additive: Boolean) = this.quad.fillQuad(quad, color, additive)
}

actual object PlatformRaster : RasterFactory {
    override fun imageFromPremultiplied(rgba: RgbaImage): DrawableImage {
        require(rgba.premultiplied) { "프리멀티 바이트만 받는다" }
        val bmp = Bitmap.createBitmap(rgba.width, rgba.height, Bitmap.Config.ARGB_8888)
        bmp.isPremultiplied = true
        // copyPixelsFromBuffer 는 바이트를 바꾸지 않고 비트맵의 프리멀티 상태 그대로 받는다(setPixels 와 다르다) — G §8-12.
        bmp.copyPixelsFromBuffer(ByteBuffer.wrap(rgba.px))
        return AndroidImage(bmp)
    }

    override fun decodeStraight(encoded: ByteArray): DrawableImage {
        val opts = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inScaled = false
            inPremultiplied = true
        }
        val bmp = BitmapFactory.decodeByteArray(encoded, 0, encoded.size, opts) ?: error("그림 디코드 실패")
        return AndroidImage(bmp)
    }

    override fun decodeRaw(encoded: ByteArray): RgbaImage {
        val opts = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inScaled = false
            // 곱하지 않는다: 구운 페이지 바이트는 이미 SceneKit 프리멀티다(G §8-12). 결과 바이트 = 파일에 든 RGBA 그대로.
            inPremultiplied = false
        }
        val bmp = BitmapFactory.decodeByteArray(encoded, 0, encoded.size, opts) ?: error("그림 디코드 실패")
        try {
            val buf = ByteBuffer.allocate(bmp.width * bmp.height * 4)
            bmp.copyPixelsToBuffer(buf)
            return RgbaImage(bmp.width, bmp.height, buf.array(), false)
        } finally {
            bmp.recycle()
        }
    }

    override fun newSurface(width: Int, height: Int): RasterSurface = AndroidRasterSurface(width, height)
}

actual fun quadCanvasOf(canvas: androidx.compose.ui.graphics.Canvas): QuadCanvas =
    AndroidQuadCanvas(canvas.nativeCanvas)
