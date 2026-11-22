// 원본: Sources/CheckMobileKit/Messages/MessagePhotoEncoder(맥 · 폰 공용 줄이기 — 긴 변 1600px · JPEG · 약 0.35MB)의 안드로이드 자리 — 판 9
package com.yehsung.aingcheck.core.stores.me

/** 줄인 사진 한 장(JPEG · 픽셀 크기). 바이트는 남의 이름 · 대화가 찍혔을 수 있다 — 로그 · 디스크 금지. */
class EncodedPhoto(val jpeg: ByteArray, val pixelWidth: Int, val pixelHeight: Int)

/**
 * 고른 이미지 원본 → 줄인 JPEG(긴 변 ≤ 1600px · 품질 0.8, 그래도 1.5MB 를 넘으면 0.6). 못 읽으면 null.
 * 플랫폼 그림 도구가 필요해 **앱 조립이 넣는다**(Android `BitmapFactory`). 없으면(데스크톱 · 시험 기본) 캡처 입구가 숨는다.
 */
fun interface PhotoEncoding {
    fun encode(data: ByteArray): EncodedPhoto?
}
