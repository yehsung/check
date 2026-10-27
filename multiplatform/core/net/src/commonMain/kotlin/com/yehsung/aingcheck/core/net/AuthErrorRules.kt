// 원본: Sources/CheckCore/AuthErrorRules.swift @ 1b8260d
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import kotlin.coroutines.cancellation.CancellationException

/** 인증 경로 오류의 처분(Swift `AuthErrorDisposition`). */
enum class AuthErrorDisposition { cancelled, transient, fatal }

/**
 * 인증 경로 오류의 **처분**과 **사용자 문구**(C§4 #3): 취소 → 아무것도 안 바뀜, 네트워크·5xx·429 → 세션 유지, 나머지만 치명(로그아웃).
 * Swift `URLError` 의 Kotlin 꼴은 전송 예외(IOException 계열 · Ktor 시간 초과 · 이름 풀이 실패)다 — [isTransport] 가 가른다.
 */
object AuthErrorRules {
    fun classify(error: Throwable): AuthErrorDisposition {
        if (error is CancellationException && !isTransport(error)) return AuthErrorDisposition.cancelled
        if (isTransport(error)) return AuthErrorDisposition.transient
        if (error is SupabaseWorkServiceError.InvalidResponse && (error.statusCode in 500..599 || error.statusCode == 429)) {
            return AuthErrorDisposition.transient
        }
        if (error is SupabaseWorkServiceError.RateLimited) return AuthErrorDisposition.transient
        return AuthErrorDisposition.fatal
    }

    /**
     * 전송 실패(Swift URLError — 취소 아닌 것). JVM·Android 의 IOException 계열과 Ktor 시간 초과를 이름으로 본다
     * (commonMain 이라 java.io 를 직접 못 본다). Ktor `HttpRequestTimeoutException` 은 IOException 이면서 CancellationException 이 아니다.
     */
    fun isTransport(error: Throwable): Boolean =
        generateSequence(error as Throwable?) { it.cause }.take(4).any { (it::class.simpleName ?: "") in TRANSPORT_NAMES }

    private val TRANSPORT_NAMES = setOf(
        "IOException", "UnknownHostException", "ConnectException", "SocketTimeoutException", "SocketException",
        "UnresolvedAddressException", "HttpRequestTimeoutException", "ConnectTimeoutException", "EOFException",
        "SSLException", "SSLHandshakeException", "NoRouteToHostException", "ClosedReceiveChannelException",
    )

    /** 인증 오류 → 사용자 문구. 서비스 오류가 아니면 fallback. */
    fun message(error: Throwable, fallback: String): String {
        val e = error as? SupabaseWorkServiceError ?: return fallback
        return when (e) {
            SupabaseWorkServiceError.MissingAnonKey -> "Supabase 키 필요"
            SupabaseWorkServiceError.InvalidAPIKey -> "Supabase 키 오류"
            SupabaseWorkServiceError.SessionExpired -> "다시 로그인 필요"
            SupabaseWorkServiceError.InvalidLoginCredentials -> "로그인 정보 오류"
            SupabaseWorkServiceError.EmailNotConfirmed -> "이메일 확인 필요"
            SupabaseWorkServiceError.EmailAlreadyRegistered -> "이미 가입된 이메일"
            SupabaseWorkServiceError.SignupDisabled -> "가입 비활성화됨"
            SupabaseWorkServiceError.WeakPassword -> "비밀번호 조건 확인"
            SupabaseWorkServiceError.DatabaseSchemaMissing -> "DB 스키마 필요"
            SupabaseWorkServiceError.UltraWalletUnavailable -> "울트라 기능 준비 중"
            SupabaseWorkServiceError.SessionAlreadyOpen -> "이미 다른 곳에서 근무 중이에요"
            is SupabaseWorkServiceError.RateLimited -> "잠시 후 다시 시도해주세요"
            SupabaseWorkServiceError.OtpInvalidOrExpired -> "코드가 맞지 않거나 만료됐어요"
            SupabaseWorkServiceError.SamePasswordReuse -> "이전과 다른 비밀번호로 정해주세요"
            is SupabaseWorkServiceError.AuthMessage -> e.text
            is SupabaseWorkServiceError.InvalidResponse -> fallback
        }
    }
}
