// 원본: Sources/CheckMobileKit/App/MobileContext.swift · Sources/CheckMobileKit/App/MobileEnvironment.swift · Sources/CheckCore/CheckCoreShared.swift:36-44(GomokuStoreHost) @ 1b8260d
package com.yehsung.aingcheck.core.session.context

import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.wire.SupabaseSession

/**
 * 스토어가 세션에 기대는 **최소 문**(Swift `GomokuStoreHost` 의 세션 몫 다섯). 오목·체스·테트리스 스토어(W2-d·W2-e)의 호스트는
 * 이것을 넓혀 실시간 상태(`realtimeState`)와 루비 미러(`rubyBalance`)를 더한다 — 그 둘은 실시간·스토어 층 몫이라 여기 두지 않는다.
 * [SessionStore] 가 이 문을 구현한다.
 */
interface SessionHost {
    /** 지금 세션(없으면 null — 로그아웃). Swift `host.session`. */
    val session: SupabaseSession?

    /** 세션 세대. 응답을 적용하기 전에 캡처값과 비교한다(로그아웃·계정 전환 뒤 늦게 온 응답 버리기). */
    val sessionGeneration: Int

    val service: SupabaseWorkService

    /** 세션 가드 → 세대 캡처 → 호출 → 401 이면 조정자 경유 갱신 1회 → 재시도. 치명 갱신 실패만 로그아웃(C§4 #3·#4). */
    suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T

    /** 맥·iOS 와 같은 판정(취소 · 일시 · 치명 — C§4 #3). */
    fun classifyAuthError(error: Throwable): AuthErrorDisposition = AuthErrorRules.classify(error)
}

/**
 * 탭 스토어가 받는 **기반 묶음의 세션 몫**(Swift `MobileContext` 중 세션 층이 가질 수 있는 것). 모든 공용 스토어(W2-b~e)는
 * 이 인터페이스로 세션·서비스·시계·앱 정보·**앱 구성**([appConfig])에 닿는다.
 *
 * 의존 방향(session ← stores ← feature) 때문에 Swift `MobileContext` 의 나머지 칸 — 라우터 · 실시간 러너 · 위젯 스냅숏 · 오목/체스/
 * 테트리스 스토어 · 스토어 사이 약참조(`links`) · 화면 모드 · 캐릭터 표 — 는 여기 없다. 그것은 feature/phone(W2-f)의 폰 문맥이
 * 이 인터페이스를 넓혀 붙이고, 조립(K11)은 조정자가 한다.
 *
 * 쓰는 법(Swift 머리 주석 그대로): 서버 호출은 세션 가드 → 세대 캡처 → `withSessionRetry { s -> service.…(s.accessToken) }` → 세대 가드.
 * 시각은 [clock] 만. 판돈 대결 진입은 `appConfig.duelsEnabled` 로만 가른다(§8-17 #1).
 */
interface SessionContext {
    val sessionStore: SessionStore
    val appConfig: AppConfig

    val service: SupabaseWorkService get() = sessionStore.service
    val clock: SessionClock get() = sessionStore.clock
    val appInfo: AppInfo get() = sessionStore.appInfo

    /** 비밀 아닌 설정 저장소(Swift `storage.defaults` 자리). 세션 칸 밖은 각 스토어가 자기 접두로 쓴다. */
    val keyValueStore: KeyValueStore get() = sessionStore.prefs

    /** 지금 세션 세대(Swift `context.generation`). */
    val generation: Int get() = sessionStore.sessionGeneration

    suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T = sessionStore.withSessionRetry(operation)

    companion object {
        /** 기본 구현(조립 지점·시험이 쓴다). */
        operator fun invoke(sessionStore: SessionStore, appConfig: AppConfig = AppConfig()): SessionContext =
            DefaultSessionContext(sessionStore, appConfig)
    }
}

private data class DefaultSessionContext(
    override val sessionStore: SessionStore,
    override val appConfig: AppConfig,
) : SessionContext
