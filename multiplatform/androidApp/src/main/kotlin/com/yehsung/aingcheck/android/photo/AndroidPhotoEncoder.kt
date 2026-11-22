// 원본: Sources/CheckMobileKit/Messages/MessagePhotoEncoder(긴 변 1600px · JPEG 0.8, 1.5MB 넘으면 0.6)의 Android 판 — 판 9(제보 캡처 · 메시지 사진)
package com.yehsung.aingcheck.android.photo

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import com.yehsung.aingcheck.core.stores.me.EncodedPhoto
import com.yehsung.aingcheck.core.stores.me.PhotoEncoding
import com.yehsung.aingcheck.core.wire.models.FeedbackShotRules
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * 고른 이미지 원본 → 줄인 JPEG. 먼저 크기만 읽어 2의 거듭제곱으로 덜 읽고(메모리), 긴 변을 1600 으로 맞춘 뒤, EXIF 회전을 바로 세우고,
 * 품질 80 으로 굽는다 — 1.5MB 를 넘으면 60 으로 한 번 더. 못 읽으면 null. **바이트를 로그 · 디스크에 남기지 않는다**(남의 이름 · 대화가 찍혔을 수 있다).
 */
object AndroidPhotoEncoder : PhotoEncoding {
    override fun encode(data: ByteArray): EncodedPhoto? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val longSide = max(bounds.outWidth, bounds.outHeight)
        var sample = 1
        while (longSide / (sample * 2) >= FeedbackShotRules.maxDimension) sample *= 2
        val decoded = BitmapFactory.decodeByteArray(data, 0, data.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        val scaled = scaleToLongSide(decoded, FeedbackShotRules.maxDimension)
        val upright = rotateByExif(scaled, data)
        var jpeg = compress(upright, FeedbackShotRules.jpegQuality)
        if (jpeg.size > FeedbackShotRules.maxUploadBytes) jpeg = compress(upright, FeedbackShotRules.fallbackJPEGQuality)
        return EncodedPhoto(jpeg, upright.width, upright.height)
    }

    private fun scaleToLongSide(bitmap: Bitmap, target: Int): Bitmap {
        val long = max(bitmap.width, bitmap.height)
        if (long <= target) return bitmap
        val k = target.toDouble() / long
        return Bitmap.createScaledBitmap(bitmap, max(1, (bitmap.width * k).roundToInt()), max(1, (bitmap.height * k).roundToInt()), true)
    }

    private fun rotateByExif(bitmap: Bitmap, data: ByteArray): Bitmap {
        val orientation = runCatching { ExifInterface(ByteArrayInputStream(data)).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) }
            .getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        val degrees = when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, Matrix().apply { postRotate(degrees) }, true)
    }

    private fun compress(bitmap: Bitmap, quality: Int): ByteArray =
        ByteArrayOutputStream().use { out -> bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out); out.toByteArray() }
}
