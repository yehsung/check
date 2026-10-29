// 원본: Sources/CheckMobileKit/Me/MeAvatarImage.swift @ 3bd04bd (최장변 256 비율 유지 · 키우지 않는다 · JPEG · 투명은 흰 바탕 · 못 읽으면 nil)
//
// Robolectric(NATIVE 그래픽 — 실제 Skia 코덱)으로 원본 PNG 를 만들어 줄인 JPEG 를 다시 읽어 잰다.
// 기준선(다른 입력): 불투명 빨강 원본은 빨강으로 남는다 — 투명 원본만 바탕색이 된다.
package com.yehsung.aingcheck.android.screens.me

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import androidx.compose.ui.graphics.toArgb
import com.yehsung.aingcheck.ui.theme.AingColors
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36])
class AvatarJpegTest {
    private val white = AingColors.Light.surface.toArgb()
    /** 기준선 색(빨강) — 시험 원본을 칠할 뿐 화면 색이 아니다. 팔레트 위험색에서 받는다(시험 소스도 손으로 색을 만들지 않는다). */
    private val ink = AingColors.Light.danger.toArgb()

    private fun png(width: Int, height: Int, fill: Int?): ByteArray {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        if (fill != null) Canvas(bitmap).drawColor(fill)
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray()
    }

    private fun channels(argb: Int) = listOf((argb shr 16) and 0xFF, (argb shr 8) and 0xFF, argb and 0xFF)

    private fun close(a: Int, b: Int, tolerance: Int = 12) = channels(a).zip(channels(b)).all { (x, y) -> kotlin.math.abs(x - y) <= tolerance }

    @Test
    fun targetSizeKeepsRatioAndNeverUpscales() {
        assertEquals(256 to 128, AvatarJpeg.targetSize(1024, 512))
        assertEquals(128 to 256, AvatarJpeg.targetSize(300, 600))
        assertEquals("작은 원본은 그대로", 100 to 80, AvatarJpeg.targetSize(100, 80))
        assertEquals("한 변이 0 으로 접히지 않는다", 256 to 1, AvatarJpeg.targetSize(4000, 10))
        assertNull(AvatarJpeg.targetSize(0, 10))
    }

    @Test
    fun transparentSourceFlattensOnTheBackgroundAndShrinks() {
        val jpeg = AvatarJpeg.encode(png(800, 400, fill = null), white)
        assertNotNull(jpeg)
        jpeg!!
        assertTrue("JPEG 머리(FF D8)", jpeg[0] == 0xFF.toByte() && jpeg[1] == 0xD8.toByte())
        val decoded = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)
        assertEquals(256, decoded.width)
        assertEquals(128, decoded.height)
        assertTrue("투명 원본은 흰 바탕이어야 한다(검게 올라가지 않게): ${Integer.toHexString(decoded.getPixel(10, 10))}", close(decoded.getPixel(10, 10), white))
    }

    @Test
    fun opaqueSourceKeepsItsColor() {
        val jpeg = AvatarJpeg.encode(png(64, 64, fill = ink), white)!!
        val decoded = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)
        assertEquals(64, decoded.width)
        assertTrue("불투명 원본은 제 색: ${Integer.toHexString(decoded.getPixel(32, 32))}", close(decoded.getPixel(32, 32), ink))
        assertTrue(!close(decoded.getPixel(32, 32), white))
    }

    @Test
    fun unreadableBytesAreNull() {
        assertNull(AvatarJpeg.encode(ByteArray(0), white))
        assertNull(AvatarJpeg.encode("not an image".encodeToByteArray(), white))
    }
}
