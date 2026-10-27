// 원본: Sources/CheckCore/SupabaseWorkHTTP.swift:91-174(serviceError) · SupabaseWorkService.swift:1384-1434(passwordRecoveryError · retryAfterSeconds) · CheckCore/BlockReportRules.swift:166-172(isMissingFunction) @ 1b8260d
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.json.swiftTry
import com.yehsung.aingcheck.core.wire.models.SupabaseErrorResponse
import com.yehsung.aingcheck.core.wire.models.swiftTrim

/**
 * 2xx 가 아닌 응답 → 서비스 오류. **분류 순서가 계약이다**(C§4 #2 · G §5-2): 23505·work_sessions → 5xx → 429 → 본문.
 * 골든: `contract/golden/errors/classify.json`(상태코드 × 본문 원문 → 갈래).
 */
object ServiceErrorClassifier {
    fun classify(statusCode: Int, body: ByteArray): SupabaseWorkServiceError {
        // Postgres 유니크 위반(23505)은 GoTrue 의 정수 code 와 타입이 섞여 안전하게 디코드할 수 없어 원문에서 직접 본다.
        // 디코드 성패와 무관하게 **먼저** 판정한다.
        val rawBody = body.decodeToString().lowercase()
        if (rawBody.contains("work_sessions_one_open_per_user") || rawBody.contains("23505") ||
            (rawBody.contains("duplicate key") && rawBody.contains("work_sessions"))
        ) {
            return SupabaseWorkServiceError.SessionAlreadyOpen
        }

        // INV-SupabaseWorkHTTP-d4703379 이식: 상태코드 게이트는 본문 폴딩(.authMessage)보다 **먼저**다. GoTrue 는 5xx/429 에도
        // {"msg":…} 를 싣는데 그걸 authMessage 로 접으면 갱신 경로에서 일시 장애가 강제 로그아웃이 된다.
        if (statusCode >= 500) return SupabaseWorkServiceError.InvalidResponse(statusCode)
        if (statusCode == 429) {
            // 남은 초는 본문에서만. 못 뽑으면 null(0 으로 지어내면 재시도가 바로 열린다).
            return SupabaseWorkServiceError.RateLimited(retryAfterSeconds(rawBody))
        }

        val response = swiftTry { SwiftJson.decode(SupabaseErrorResponse.serializer(), body.decodeToString()) }
            ?: return if (statusCode == 401) SupabaseWorkServiceError.SessionExpired else SupabaseWorkServiceError.InvalidResponse(statusCode)

        val message = listOf(response.message, response.msg, response.errorDescription, response.error)
            .mapNotNull { it?.let(::swiftTrim) }
            .firstOrNull { it.isNotEmpty() }
        val lowercased = listOfNotNull(message, response.errorCode).joinToString(" ") { it.lowercase() }

        if (lowercased.contains("schema cache") || lowercased.contains("could not find the table")) {
            return SupabaseWorkServiceError.DatabaseSchemaMissing
        }
        if (lowercased.contains("invalid api key")) return SupabaseWorkServiceError.InvalidAPIKey
        if (lowercased.contains("jwt expired") || lowercased.contains("pgrst301") ||
            (statusCode == 401 && (lowercased.contains("jwt") || lowercased.contains("expired")))
        ) {
            return SupabaseWorkServiceError.SessionExpired
        }
        // 갱신 토큰 만료/재사용("Invalid Refresh Token: Already Used")은 아래 "already" 보다 **먼저** 세션 만료로.
        if (lowercased.contains("refresh token") || lowercased.contains("refresh_token") || lowercased.contains("invalid_grant")) {
            return SupabaseWorkServiceError.SessionExpired
        }
        if (lowercased.contains("invalid login credentials")) return SupabaseWorkServiceError.InvalidLoginCredentials
        if (lowercased.contains("email not confirmed") || lowercased.contains("email_not_confirmed")) {
            return SupabaseWorkServiceError.EmailNotConfirmed
        }
        if (lowercased.contains("already") || lowercased.contains("registered") || lowercased.contains("exists")) {
            return SupabaseWorkServiceError.EmailAlreadyRegistered
        }
        if (lowercased.contains("signup") && lowercased.contains("disable")) return SupabaseWorkServiceError.SignupDisabled
        // INV-SupabaseWorkHTTP-e2d6e11e 이식: 비밀번호 재사용 거절은 아래 "password" 가드보다 **먼저**(순서가 바뀌면 weakPassword 로 뭉개진다).
        if (lowercased.contains("different from the old password") || lowercased.contains("same_password")) {
            return SupabaseWorkServiceError.SamePasswordReuse
        }
        if (lowercased.contains("password")) return SupabaseWorkServiceError.WeakPassword
        if (message != null) return SupabaseWorkServiceError.AuthMessage(message)
        return SupabaseWorkServiceError.InvalidResponse(statusCode)
    }

    /**
     * "…after 30 seconds" → 30. "second" 앞에서 뒤로 걸으며 **Swift `Character.isNumber`** 인 글자 덩어리를 모은 뒤 Swift `Int(String)`
     * 으로 읽는다 — 덩어리에 ASCII 0-9 밖의 숫자(전각 ３０ · 위첨자 ² · 아랍 ٣٠ · 한자 一 · ½)가 하나라도 있으면 Swift 는 nil 이다(실측,
     * 골든 errors retry-after-*). 없으면 null(0 으로 지어내면 재시도가 바로 열린다).
     * 알려진 갈림: 보조 평면(서로게이트 쌍)의 숫자 글자(𝟑 등)는 범주를 공용 코드에서 못 읽어 숫자로 치지 않는다 — 골든에 잠겨 있다.
     */
    fun retryAfterSeconds(lowercasedMessage: String): Long? {
        val at = lowercasedMessage.indexOf("second")
        if (at < 0) return null
        val digits = StringBuilder()
        for (i in at - 1 downTo 0) {
            val ch = lowercasedMessage[i]
            if (ch.isSwiftNumber()) digits.append(ch) else if (digits.isNotEmpty()) break
        }
        if (digits.isEmpty()) return null
        val text = digits.reverse().toString()
        if (!text.all { it in '0'..'9' }) return null
        return text.toLongOrNull()
    }

    /**
     * Swift `Character.isNumber`(= 첫 스칼라의 Unicode Numeric_Type 이 있다) = 범주 Nd·Nl·No + 숫자 값이 있는 한자 99자
     * (BMP 75자는 아래 표 — 1b8260d 의 Swift 로 U+0000~U+10FFFF 를 전수 실측).
     */
    private fun Char.isSwiftNumber(): Boolean = when (category) {
        CharCategory.DECIMAL_DIGIT_NUMBER, CharCategory.LETTER_NUMBER, CharCategory.OTHER_NUMBER -> true
        else -> code in HAN_NUMERIC_BMP
    }

    private val HAN_NUMERIC_BMP: Set<Int> = setOf(
        0x3405, 0x3483, 0x382A, 0x3B4D, 0x4E00, 0x4E03, 0x4E07, 0x4E09, 0x4E24, 0x4E5D, 0x4E8C, 0x4E94, 0x4E96, 0x4EAC, 0x4EBF,
        0x4EC0, 0x4EDF, 0x4EE8, 0x4F0D, 0x4F70, 0x4FE9, 0x5006, 0x5104, 0x5146, 0x5169, 0x516B, 0x516D, 0x5341, 0x5343, 0x5344,
        0x5345, 0x534C, 0x53C1, 0x53C2, 0x53C3, 0x53C4, 0x56DB, 0x58F1, 0x58F9, 0x5E7A, 0x5EFE, 0x5EFF, 0x5F0C, 0x5F0D, 0x5F0E,
        0x5F10, 0x62D0, 0x62FE, 0x634C, 0x67D2, 0x6D1E, 0x6F06, 0x7396, 0x767E, 0x7695, 0x79ED, 0x8086, 0x842C, 0x8CAE, 0x8CB3,
        0x8D30, 0x920E, 0x94A9, 0x9621, 0x9646, 0x964C, 0x9678, 0x96F6, 0xF96B, 0xF973, 0xF978, 0xF9B2, 0xF9D1, 0xF9D3, 0xF9FD,
    )

    /** 비밀번호 재설정·가입 OTP 경로의 재분류(429 → rateLimited, GoTrue 문구 → otp 만료·세션 만료). */
    fun passwordRecoveryError(error: SupabaseWorkServiceError): SupabaseWorkServiceError {
        if (error == SupabaseWorkServiceError.InvalidResponse(429)) return SupabaseWorkServiceError.RateLimited(null)
        if (error !is SupabaseWorkServiceError.AuthMessage) return error
        val lowercased = error.text.lowercase()
        if (lowercased.contains("rate limit") || lowercased.contains("security purposes")) {
            return SupabaseWorkServiceError.RateLimited(retryAfterSeconds(lowercased))
        }
        if (lowercased.contains("token has expired or is invalid") || lowercased.contains("otp_expired") ||
            lowercased.contains("verify requires")
        ) {
            return SupabaseWorkServiceError.OtpInvalidOrExpired
        }
        if (lowercased.contains("invalid jwt") || lowercased.contains("bad_jwt") || lowercased.contains("missing sub claim")) {
            return SupabaseWorkServiceError.SessionExpired
        }
        return error
    }

    /** 서버에 함수가 아직 없다(PGRST202 → databaseSchemaMissing · 404) — db push 전 창. */
    fun isMissingFunction(error: SupabaseWorkServiceError): Boolean = when (error) {
        SupabaseWorkServiceError.DatabaseSchemaMissing -> true
        is SupabaseWorkServiceError.InvalidResponse -> error.statusCode == 404
        else -> false
    }
}
