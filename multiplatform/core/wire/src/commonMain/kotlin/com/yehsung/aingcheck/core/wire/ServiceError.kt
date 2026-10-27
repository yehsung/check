// 원본: Sources/CheckCore/SupabaseWorkModels.swift(SupabaseWorkServiceError · SupabaseSession · EmptyBody) @ 1b8260d
package com.yehsung.aingcheck.core.wire

import kotlinx.serialization.Serializable

/**
 * 서비스 오류(Swift `SupabaseWorkServiceError` 갈래 그대로). 분류 순서는 `core.net.ServiceErrorClassifier`
 * (23505 → 5xx → 429 → 본문 — §5-2, `SupabaseWorkHTTP.swift:91-174`).
 */
sealed class SupabaseWorkServiceError(message: String) : Exception(message) {
    data object MissingAnonKey : SupabaseWorkServiceError("missingAnonKey")
    data object InvalidAPIKey : SupabaseWorkServiceError("invalidAPIKey")
    data object SessionExpired : SupabaseWorkServiceError("sessionExpired")
    data object InvalidLoginCredentials : SupabaseWorkServiceError("invalidLoginCredentials")
    data object EmailNotConfirmed : SupabaseWorkServiceError("emailNotConfirmed")
    data object EmailAlreadyRegistered : SupabaseWorkServiceError("emailAlreadyRegistered")
    data object SignupDisabled : SupabaseWorkServiceError("signupDisabled")
    data object WeakPassword : SupabaseWorkServiceError("weakPassword")
    data object DatabaseSchemaMissing : SupabaseWorkServiceError("databaseSchemaMissing")
    data object UltraWalletUnavailable : SupabaseWorkServiceError("ultraWalletUnavailable")
    data object SessionAlreadyOpen : SupabaseWorkServiceError("sessionAlreadyOpen")
    /** 남은 초는 본문("…after N seconds")에서만 뽑는다. 못 뽑으면 null — 0 으로 지어내면 재시도가 바로 열린다. */
    data class RateLimited(val retryAfterSeconds: Long?) : SupabaseWorkServiceError("rateLimited($retryAfterSeconds)")
    data object OtpInvalidOrExpired : SupabaseWorkServiceError("otpInvalidOrExpired")
    data object SamePasswordReuse : SupabaseWorkServiceError("samePasswordReuse")
    data class AuthMessage(val text: String) : SupabaseWorkServiceError("authMessage($text)")
    data class InvalidResponse(val statusCode: Int) : SupabaseWorkServiceError("invalidResponse($statusCode)")

    /** Swift case 이름(골든 표기). */
    val caseName: String
        get() = when (this) {
            MissingAnonKey -> "missingAnonKey"
            InvalidAPIKey -> "invalidAPIKey"
            SessionExpired -> "sessionExpired"
            InvalidLoginCredentials -> "invalidLoginCredentials"
            EmailNotConfirmed -> "emailNotConfirmed"
            EmailAlreadyRegistered -> "emailAlreadyRegistered"
            SignupDisabled -> "signupDisabled"
            WeakPassword -> "weakPassword"
            DatabaseSchemaMissing -> "databaseSchemaMissing"
            UltraWalletUnavailable -> "ultraWalletUnavailable"
            SessionAlreadyOpen -> "sessionAlreadyOpen"
            is RateLimited -> "rateLimited"
            OtpInvalidOrExpired -> "otpInvalidOrExpired"
            SamePasswordReuse -> "samePasswordReuse"
            is AuthMessage -> "authMessage"
            is InvalidResponse -> "invalidResponse"
        }
}

/** 로그인 결과(Swift `SupabaseSession`). */
data class SupabaseSession(val accessToken: String, val refreshToken: String?, val userID: String)

/** 빈 본문 `{}`(Swift `EmptyBody`). PostgREST 는 본문 키 집합으로 오버로드를 고른다 — 인자 없음 = `{}`(C§4 #38). */
@Serializable
class EmptyBody {
    override fun equals(other: Any?): Boolean = other is EmptyBody
    override fun hashCode(): Int = 0
}
