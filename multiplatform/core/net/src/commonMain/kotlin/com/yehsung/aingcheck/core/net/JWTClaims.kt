// 원본: Sources/CheckCore/JWTClaims.swift @ 1b8260d
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

/**
 * access token(JWT) 클레임을 **읽기만** 한다(서명 검증 없음 — 용도는 "언제 미리 갱신할까" 일정 계산뿐).
 * **null 은 '만료'가 아니라 '모른다'** — null 을 만료로 읽으면 파싱 한 번 실패로 갱신 폭풍 → 근무 중 강제 로그아웃(C§4 #5).
 * 골든: `contract/golden/jwt/expiry.json`.
 */
object JWTClaims {
    fun expiry(accessToken: String): SwiftDate? = numericClaim("exp", accessToken)?.let { SwiftDate(it) }

    /** 페이로드(가운데 조각)의 숫자 클레임. 소수도 받는다(RFC 7519 NumericDate). 글자·불이면 null. */
    fun numericClaim(name: String, accessToken: String): Double? {
        val parts = accessToken.split('.')
        if (parts.size < 2) return null
        val payload = base64URLDecode(parts[1]) ?: return null
        val obj = try {
            Json.parseToJsonElement(payload.decodeToString()) as? JsonObject
        } catch (e: Exception) {
            null
        } ?: return null
        val value = obj[name] as? JsonPrimitive ?: return null
        if (value.isString) return null
        // JSONSerialization 은 불도 NSNumber 로 준다 → Swift 는 true 를 1.0 으로 읽는다(같은 동작을 옮긴다).
        if (value.content == "true") return 1.0
        if (value.content == "false") return 0.0
        return value.doubleOrNull
    }

    /** base64url(패딩 없음) → 바이트. `-_` → `+/`, 패딩을 채운다. 표준 디코더를 그냥 쓰면 언제나 실패한다. */
    @OptIn(ExperimentalEncodingApi::class)
    fun base64URLDecode(value: String): ByteArray? {
        var s = value.replace('-', '+').replace('_', '/')
        val remainder = s.length % 4
        if (remainder > 0) s += "=".repeat(4 - remainder)
        return try {
            Base64.Default.decode(s)
        } catch (e: IllegalArgumentException) {
            null
        }
    }
}
