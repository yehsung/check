// 원본: Sources/CheckCore/AuthErrorRules.swift @ 1b8260d
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import kotlinx.io.IOException
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
     * 전송 실패(Swift `URLError` — 취소 아닌 것 **전부**). Kotlin 의 꼴은 `kotlinx.io.IOException`(JVM·Android = java.io.IOException)
     * 계열 전체다 — 이름 허용 목록이면 `InterruptedIOException`(OkHttp 호출 시간 초과)·`StreamResetException`(HTTP/2 끊김)·
     * `SSLPeerUnverifiedException`·`ProtocolException` 같은 하위 예외가 빠져 **로그아웃**으로 갔다(검증 지적 · C§4 #3 "네트워크 → 세션 유지").
     * Ktor `HttpRequestTimeoutException`·`ConnectTimeoutException`·`SocketTimeoutException` 도 IOException 이다.
     * IOException 이 아닌 전송 실패 둘(`UnresolvedAddressException` = IllegalArgumentException, 웹소켓 `ClosedReceiveChannelException`)만
     * 이름으로 더 본다. 원인 사슬을 네 겹까지 본다(엔진이 감싸서 던지는 경우).
     */
    fun isTransport(error: Throwable): Boolean =
        generateSequence(error as Throwable?) { it.cause }.take(4).any { it is IOException || (it::class.simpleName ?: "") in NON_IO_TRANSPORT_NAMES }

    private val NON_IO_TRANSPORT_NAMES = setOf("UnresolvedAddressException", "ClosedReceiveChannelException")

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
