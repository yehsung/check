// 원본: Sources/CheckMobileKit/Me/MeAvatarImage.swift @ 3bd04bd (아바타 업로드용 이미지 줄이기 — 최장변 256px 비율 유지 · JPEG 0.85 · 키우지 않는다 · EXIF 방향 · 흰 바탕)
//
// 사진 선택기가 준 원본 바이트 → 업로드할 JPEG(못 읽으면 null — 스토어가 "사진을 읽지 못했어요"를 세운다). 스토어 uploadAvatar 의 encodeJpeg 자리.
// API 28+ 는 ImageDecoder(HEIC · EXIF 방향을 스스로 적용), 26~27 은 BitmapFactory(방향 미적용 — 보고). JPEG 는 알파가 없어 투명 PNG 가 검게
// 올라가지 않게 바탕 한 장에 그린다 — 바탕 색은 손으로 만들지 않고 팔레트(라이트 카드 면 = 흰색)에서 받는다(D5 — 앱 셸 색 리터럴 금지).
package com.yehsung.aingcheck.android.screens.me

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ImageDecoder
import android.graphics.Paint
import android.os.Build
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.roundToInt

object AvatarJpeg {
    const val MAX_DIMENSION = 256
    /** Swift 압축 0.85 → Android 품질 85. */
    const val QUALITY = 85

    /** 최장변을 [maxDimension] 에 맞춘 비율 유지 크기. 원본이 더 작으면 그대로(키우지 않는다). 0 이하면 null. */
    fun targetSize(width: Int, height: Int, maxDimension: Int = MAX_DIMENSION): Pair<Int, Int>? {
        if (width <= 0 || height <= 0 || maxDimension <= 0) return null
        val longest = max(width, height)
        if (longest <= maxDimension) return width to height
        val scale = maxDimension.toDouble() / longest
        return max(1, (width * scale).roundToInt()) to max(1, (height * scale).roundToInt())
    }

    /** 원본 → JPEG. [background] 는 ARGB 정수(조립이 팔레트에서 넘긴다). 못 읽으면 null. */
    fun encode(source: ByteArray, background: Int, maxDimension: Int = MAX_DIMENSION): ByteArray? {
        if (source.isEmpty()) return null
        val decoded = runCatching { decode(source, maxDimension) }.getOrNull() ?: return null
        val (w, h) = targetSize(decoded.width, decoded.height, maxDimension) ?: return null
        val scaled = if (w == decoded.width && h == decoded.height) decoded else Bitmap.createScaledBitmap(decoded, w, h, true)
        val flat = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        Canvas(flat).apply {
            drawColor(background)
            drawBitmap(scaled, 0f, 0f, Paint(Paint.FILTER_BITMAP_FLAG))
        }
        val out = ByteArrayOutputStream()
        if (!flat.compress(Bitmap.CompressFormat.JPEG, QUALITY, out)) return null
        return out.toByteArray()
    }

    private fun decode(source: ByteArray, maxDimension: Int): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return ImageDecoder.decodeBitmap(ImageDecoder.createSource(ByteBuffer.wrap(source))) { decoder, info, _ ->
                // 소프트웨어 비트맵(Canvas 에 그린다) · 큰 원본은 디코드 단계에서 줄인다.
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                targetSize(info.size.width, info.size.height, maxDimension)?.let { (w, h) -> decoder.setTargetSize(w, h) }
            }
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(source, 0, source.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxDimension) sample *= 2
        return BitmapFactory.decodeByteArray(source, 0, source.size, BitmapFactory.Options().apply { inSampleSize = sample })
    }
}
