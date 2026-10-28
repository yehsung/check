// 원본: Sources/CheckCore/CheckCoreShared.swift:28-44(AuthErrorDisposition · GomokuStoreHost) · Sources/CheckMobileKit/App/MobileContext.swift:127-163(MobileGomokuHost) · 루비 칸은 W2-c RubyBalanceMirror(조립 계약) @ 1b8260d
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.foundation.platform.LogLevel
import com.yehsung.aingcheck.core.foundation.platform.Logger
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.realtime.IdleReason
import com.yehsung.aingcheck.core.net.realtime.RealtimeState
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.stores.me.RubyBalanceMirror
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate

/**
 * 오목·체스(·테트리스) 스토어가 네트워크·세션·루비 미러를 빌리는 소유자(Swift `GomokuStoreHost`).
 *
 * 세션 몫 다섯(session · sessionGeneration · service · withSessionRetry · classifyAuthError)은 W2-a [SessionHost] 가 정했고,
 * 여기서 실시간 상태·루비 미러를 더한다(SessionHost 머리말의 약속). 그 위에 **앱 구성**([appConfig] — G §8-17 #1)과 **시계**를 더했다:
 *  - [appConfig]: 판돈 대결 진입 깃발 `duelsEnabled` 를 스토어가 읽는 유일한 문이다. 조립 지점은 [SessionContext.appConfig] 를 그대로
 *    넘긴다([SessionGomokuHost]) — 스토어가 깃발을 상수로 다시 적거나 BuildConfig 를 직접 읽지 않는다(AppConfig 머리말).
 *  - [now]: 스토어의 '지금'(Swift `clock: () -> Date` 기본값 `Date()`). 벽시계는 조립 지점에서만 만든다(구조 시험 R2) —
 *    그래서 스토어가 기본값을 지어내지 않고 호스트에서 빌린다.
 *
 * Swift 는 `weak var host` 였다(맥 `WorkTimerStore` 가 스토어를 소유). Kotlin 은 참조 순환이 문제가 아니라 그냥 든다.
 * 체스는 `typealias ChessStoreHost = GomokuStoreHost` 다(ChessStore.swift:43 — 같은 소유자가 두 게임의 호스트).
 */
interface GomokuStoreHost : SessionHost {
    /** 실시간 연결 상태(폴링 주기 판정은 구독 여부만 본다 — Swift `realtimeState.isSubscribed`). */
    val realtimeState: RealtimeState

    /** 루비 잔액 미러. 대결 응답이 쓰고(정산), 나 탭 상점이 채운다. null = 모른다(막지 않는다 — 맥 0.3.29 규칙). */
    var rubyBalance: Long?

    /** 앱 구성(§8-17 #1 — `duelsEnabled`). */
    val appConfig: AppConfig

    /** 스토어의 '지금'(조립 지점의 시계 — Swift `MobileClock.now()`). */
    fun now(): SwiftDate

    /** 진단 한 줄을 받는 곳(Swift `Logger(subsystem: "kingcheck", category: …)`). null 이면 버린다. */
    val logger: Logger? get() = null
}

/**
 * 폰 세션으로 구현한 호스트(Swift `MobileGomokuHost`). 세션·서비스·시계·**앱 구성**은 W2-a [SessionContext] 에서 그대로 빌린다 —
 * `duelsEnabled` 가 스토어에 닿는 길은 `SessionContext.appConfig → appConfig → 스토어` 하나다(시험이 이 길로 켜짐·꺼짐을 잰다).
 * 실시간 상태는 실시간 러너가 아직 이 층에 없어(W2-f 몫) 함수로 받는다. 기본은 `idle(disabled)`(Swift `realtimeRunner?.state ?? .idle(.disabled)`).
 *
 * **루비 칸은 하나다.** Swift 는 `MobileGomokuHost.rubyBalance` 한 칸을 오목·체스·나 탭이 같이 쓴다. Kotlin 은 그 칸이 W2-c
 * [RubyBalanceMirror](`MeContext.ruby`)이고, 이 호스트는 칸을 **갖지 않고 빌린다** — 조립 지점이 하나를 만들어 나 탭 문맥과 이 호스트에
 * 같이 건넨다(기본값이 없는 까닭: 기본값이 있으면 조립이 잊은 자리에서 칸이 둘이 되어 탭마다 잔액이 갈리고, 나 탭의 `rubyWriteSerial`
 * 가드가 오목 정산을 못 본다).
 */
class SessionGomokuHost(
    private val context: SessionContext,
    /** 루비 잔액 미러(나 탭과 같은 칸). 대입마다 그 칸의 `rubyWriteSerial` 이 오른다. */
    val ruby: RubyBalanceMirror,
    private val realtime: () -> RealtimeState = { RealtimeState.Idle(IdleReason.disabled) },
    override val logger: Logger? = null,
) : GomokuStoreHost {
    override var rubyBalance: Long?
        get() = ruby.rubyBalance
        set(value) {
            ruby.rubyBalance = value
        }

    override val session: SupabaseSession? get() = context.sessionStore.session
    override val sessionGeneration: Int get() = context.sessionStore.sessionGeneration
    override val service: SupabaseWorkService get() = context.service
    override val realtimeState: RealtimeState get() = realtime()
    override val appConfig: AppConfig get() = context.appConfig

    override fun now(): SwiftDate = context.clock.now()

    override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T = context.withSessionRetry(operation)
}

/** 진단 한 줄(Swift `Self.logger.notice(…)`). 문구는 고정 어휘만 싣는다 — 이름·판 내용·토큰 금지(로그는 제보에 실려 나간다). */
internal fun GomokuStoreHost?.notice(tag: String, message: String) {
    this?.logger?.log(LogLevel.INFO, tag, message)
}

/** Swift `Date.distantPast`(0001-01-01 00:00:00 UTC = 2001 기준 −63,114,076,800초). "아직 한 번도 안 했다"의 기준선. */
internal val distantPast: SwiftDate = SwiftDate.fromReferenceDate(-63_114_076_800.0)

/** Swift `max(0, x)` 정수판(관전자 수·연속 횟수 — 서버가 음수를 줘도 0 으로 접는다). */
internal fun nonNegative(value: Long?): Long = if (value == null || value < 0) 0 else value
