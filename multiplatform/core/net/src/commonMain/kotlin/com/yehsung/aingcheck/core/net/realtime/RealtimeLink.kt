// 원본: Sources/CheckCore/RealtimeLink.swift @ 1b8260d
package com.yehsung.aingcheck.core.net.realtime

import com.yehsung.aingcheck.core.net.JWTClaims
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.math.pow

/** Swift `RealtimeState`(덤프 모양을 위해 갈래·칸 이름이 Swift 그대로다 — contract/README §2-3). */
sealed interface RealtimeState {
    data class Idle(val reason: IdleReason) : RealtimeState
    data class Connecting(val attempt: Long, val since: SwiftDate) : RealtimeState
    data class Subscribed(val since: SwiftDate, val lastHeardAt: SwiftDate) : RealtimeState
    data class Reconnecting(val backoff: Backoff) : RealtimeState
    /** Swift `case failed(Backoff, RealtimeFailure)` — 이름표 없는 둘 → v0·v1. */
    data class Failed(val v0: Backoff, val v1: RealtimeFailure) : RealtimeState

    val isSubscribed: Boolean get() = this is Subscribed
}

/** Swift `RealtimeState.IdleReason`. */
enum class IdleReason { signedOut, suspended, disabled }

/** Swift `RealtimeFailure`. */
enum class RealtimeFailure { unauthorized, topicDenied, exhausted }

/** Swift `Backoff`. */
data class Backoff(val attempt: Long, val retryAt: SwiftDate, val failingSince: SwiftDate)

/**
 * Swift `RealtimeLinkConstants`. INV-RealtimeLink-2dc4a615 이식: `notWorking`(근무 중에만 붙는다)은 v0.3.30 에 지웠다 —
 * 메시지·오목 신청의 근무 조건을 서버가 걷어 냈으므로 소켓은 로그인만 기준이다(IdleReason 에 근무 갈래가 없다).
 */
object RealtimeLinkConstants {
    /** 실패로 굳기까지(초) — reconnecting 이 이만큼 이어지면 failed(.exhausted). */
    const val failedAfterSeconds: Double = 45.0
    /** 실시간 하트비트 25초(근무 하트비트 30초와 이름도 값도 다르다 — C§4 #18). */
    const val heartbeatIntervalSeconds: Double = 25.0
    const val heartbeatMissesBeforeDead: Long = 2

    fun pokeChannel(userID: String): String = "poke:$userID"

    const val gomokuBroadcastEvent = "gomoku"
    const val messageReadBroadcastEvent = "message_read"
    const val chessBroadcastEvent = "chess"
    const val tetrisBroadcastEvent = "tetris"
}

/** Swift `RealtimeTransportEvent`. */
sealed interface RealtimeTransportEvent {
    data object Opened : RealtimeTransportEvent
    data object Joined : RealtimeTransportEvent
    data class JoinRejected(val rejection: RealtimeJoinRejection) : RealtimeTransportEvent
    data class Broadcast(val event: String) : RealtimeTransportEvent
    data object HeartbeatAck : RealtimeTransportEvent
    data object HeartbeatTimedOut : RealtimeTransportEvent
    data class Closed(val code: Long?) : RealtimeTransportEvent
}

/** Swift `RealtimeJoinRejection`. */
sealed interface RealtimeJoinRejection {
    data object ExpiredToken : RealtimeJoinRejection
    data object Unauthorized : RealtimeJoinRejection
    data class Unknown(val reason: String) : RealtimeJoinRejection
}

/** Swift `RealtimeEvent`(링에 들어오는 사건). */
sealed interface RealtimeEvent {
    data class SignedIn(val accessToken: String) : RealtimeEvent
    data object SignedOut : RealtimeEvent
    data object WillSleep : RealtimeEvent
    data object DidWake : RealtimeEvent
    data class Transport(val event: RealtimeTransportEvent) : RealtimeEvent
    data object BackoffElapsed : RealtimeEvent
    data object Tick : RealtimeEvent
    data class TokenRefreshed(val accessToken: String) : RealtimeEvent
    data class TokenRefreshFailed(val fatal: Boolean) : RealtimeEvent
    data object UserRequestedRetry : RealtimeEvent
}

/** Swift `RealtimeEffect`(링이 내는 할 일). `drain` 은 모르는 방송 — 맥은 take_pokes, 폰은 메시지 활동 조회(C§4 #15, 처리는 플랫폼). */
sealed interface RealtimeEffect {
    data class Connect(val accessToken: String) : RealtimeEffect
    data object Disconnect : RealtimeEffect
    data class ScheduleRetry(val at: SwiftDate) : RealtimeEffect
    data object CancelRetry : RealtimeEffect
    data object CatchUp : RealtimeEffect
    data object Drain : RealtimeEffect
    data object GomokuSignal : RealtimeEffect
    data object ChessSignal : RealtimeEffect
    data object TetrisSignal : RealtimeEffect
    data object MessageReadSignal : RealtimeEffect
    data class PushAccessToken(val token: String) : RealtimeEffect
    data class ScheduleTokenRefresh(val at: SwiftDate) : RealtimeEffect
    data class RefreshToken(val force: Boolean) : RealtimeEffect
    data object SendHeartbeat : RealtimeEffect
}

/** Swift `BackoffPolicy` — 지수 백오프(1 · 2 · 4 … 30초 상한, 하한 0.25초) + 지터 함수. */
data class BackoffPolicy(
    val base: Double = 1.0,
    val factor: Double = 2.0,
    val cap: Double = 30.0,
    val floor: Double = 0.25,
) {
    /** 정수 지수의 거듭제곱 — 기본(2.0)은 두 언어 모두 정확한 2의 거듭제곱이다(Java Math.pow 명세: 정수 인자 · 표현 가능하면 정확). */
    fun delay(attempt: Long, jitter: (Double) -> Double): Double {
        val ceiling = minOf(cap, base * factor.pow(maxOf(0L, attempt - 1).toDouble()))
        return maxOf(floor, jitter(ceiling))
    }

    companion object {
        val default = BackoffPolicy()
    }
}

/**
 * Swift `RealtimeLink` — 소켓 수명 순수 상태기계(시계·지터 주입). 골든: `contract/golden/realtime/link-walk.json`(10,000걸음, G4).
 * 값 타입이라 [apply] 가 자기를 바꾼다(Swift `mutating`).
 */
class RealtimeLink(transportAvailable: Boolean = false) {
    var state: RealtimeState = if (transportAvailable) RealtimeState.Idle(IdleReason.signedOut) else RealtimeState.Idle(IdleReason.disabled)
        private set
    var policy: BackoffPolicy = BackoffPolicy.default
    var accessToken: String? = null
        private set
    var failingSince: SwiftDate? = null
        private set
    var forcedRefreshUsedThisAttempt: Boolean = false
        private set
    var lastHeartbeatSentAt: SwiftDate? = null
        private set

    val retryAt: SwiftDate?
        get() = when (val s = state) {
            is RealtimeState.Reconnecting -> s.backoff.retryAt
            is RealtimeState.Failed -> s.v0.retryAt
            else -> null
        }

    val isFailed: Boolean get() = state is RealtimeState.Failed
    val isDisabled: Boolean get() = state == RealtimeState.Idle(IdleReason.disabled)

    companion object {
        const val tokenRefreshLeadSeconds: Double = 300.0
        const val tokenRefreshMinDelaySeconds: Double = 30.0
        const val tokenRefreshFallbackSeconds: Double = 3000.0
        const val joinTimeoutSeconds: Double = 15.0

        /** 만료 5분 전(최소 30초 뒤). exp 를 모르면 50분 폴백 — 모름을 만료로 읽지 않는다(C§4 #5). */
        fun tokenRefreshDate(accessToken: String, now: SwiftDate): SwiftDate {
            val expiry = JWTClaims.expiry(accessToken) ?: return now.addingTimeInterval(tokenRefreshFallbackSeconds)
            return maxOf(now.addingTimeInterval(tokenRefreshMinDelaySeconds), expiry.addingTimeInterval(-tokenRefreshLeadSeconds))
        }
    }

    fun apply(event: RealtimeEvent, now: SwiftDate, jitter: (Double) -> Double): List<RealtimeEffect> {
        if (state == RealtimeState.Idle(IdleReason.disabled)) {
            if (event is RealtimeEvent.SignedIn) accessToken = event.accessToken
            if (event is RealtimeEvent.SignedOut) accessToken = null
            return emptyList()
        }
        return when (event) {
            is RealtimeEvent.SignedIn -> {
                accessToken = event.accessToken
                beginConnecting(1, now, resetFailure = true)
            }
            RealtimeEvent.SignedOut -> {
                accessToken = null
                failingSince = null
                state = RealtimeState.Idle(IdleReason.signedOut)
                listOf(RealtimeEffect.Disconnect, RealtimeEffect.CancelRetry)
            }
            RealtimeEvent.WillSleep -> {
                if (state == RealtimeState.Idle(IdleReason.signedOut)) return emptyList()
                failingSince = null
                state = RealtimeState.Idle(IdleReason.suspended)
                listOf(RealtimeEffect.Disconnect, RealtimeEffect.CancelRetry)
            }
            RealtimeEvent.DidWake -> when (val s = state) {
                RealtimeState.Idle(IdleReason.suspended) -> {
                    if (accessToken == null) {
                        state = RealtimeState.Idle(IdleReason.signedOut)
                        listOf(RealtimeEffect.Disconnect, RealtimeEffect.CancelRetry)
                    } else {
                        beginConnecting(1, now, resetFailure = true)
                    }
                }
                is RealtimeState.Reconnecting -> {
                    state = RealtimeState.Reconnecting(s.backoff.copy(retryAt = now))
                    listOf(RealtimeEffect.ScheduleRetry(now))
                }
                is RealtimeState.Failed -> {
                    state = RealtimeState.Failed(s.v0.copy(retryAt = now), s.v1)
                    listOf(RealtimeEffect.ScheduleRetry(now))
                }
                else -> emptyList()
            }
            is RealtimeEvent.Transport -> applyTransport(event.event, now, jitter)
            RealtimeEvent.UserRequestedRetry -> when (val s = state) {
                RealtimeState.Idle(IdleReason.suspended) -> {
                    if (accessToken == null) {
                        state = RealtimeState.Idle(IdleReason.signedOut)
                        listOf(RealtimeEffect.Disconnect, RealtimeEffect.CancelRetry)
                    } else {
                        beginConnecting(1, now, resetFailure = true)
                    }
                }
                is RealtimeState.Reconnecting -> {
                    state = RealtimeState.Reconnecting(s.backoff.copy(retryAt = now))
                    listOf(RealtimeEffect.ScheduleRetry(now))
                }
                is RealtimeState.Failed -> {
                    state = RealtimeState.Failed(s.v0.copy(retryAt = now), s.v1)
                    listOf(RealtimeEffect.ScheduleRetry(now))
                }
                else -> emptyList()
            }
            RealtimeEvent.BackoffElapsed -> {
                val b = when (val s = state) {
                    is RealtimeState.Reconnecting -> s.backoff
                    is RealtimeState.Failed -> s.v0
                    else -> return emptyList()
                }
                if (accessToken == null) {
                    state = RealtimeState.Idle(IdleReason.signedOut)
                    listOf(RealtimeEffect.Disconnect, RealtimeEffect.CancelRetry)
                } else {
                    beginConnecting(b.attempt, now, resetFailure = false)
                }
            }
            RealtimeEvent.Tick -> applyTick(now, jitter)
            is RealtimeEvent.TokenRefreshed -> {
                accessToken = event.accessToken
                val refreshAt = tokenRefreshDate(event.accessToken, now)
                when (val s = state) {
                    is RealtimeState.Subscribed ->
                        listOf(RealtimeEffect.PushAccessToken(event.accessToken), RealtimeEffect.ScheduleTokenRefresh(refreshAt))
                    is RealtimeState.Connecting -> {
                        state = RealtimeState.Connecting(s.attempt, now)
                        forcedRefreshUsedThisAttempt = false
                        listOf(RealtimeEffect.Disconnect, RealtimeEffect.Connect(event.accessToken), RealtimeEffect.ScheduleTokenRefresh(refreshAt))
                    }
                    is RealtimeState.Reconnecting -> {
                        state = RealtimeState.Reconnecting(s.backoff.copy(retryAt = now))
                        listOf(RealtimeEffect.ScheduleRetry(now), RealtimeEffect.ScheduleTokenRefresh(refreshAt))
                    }
                    is RealtimeState.Failed -> {
                        state = RealtimeState.Failed(s.v0.copy(retryAt = now), s.v1)
                        listOf(RealtimeEffect.ScheduleRetry(now), RealtimeEffect.ScheduleTokenRefresh(refreshAt))
                    }
                    is RealtimeState.Idle -> emptyList()
                }
            }
            is RealtimeEvent.TokenRefreshFailed -> {
                if (!event.fatal) return emptyList()
                accessToken = null
                failingSince = null
                state = RealtimeState.Idle(IdleReason.signedOut)
                listOf(RealtimeEffect.Disconnect, RealtimeEffect.CancelRetry)
            }
        }
    }

    private fun applyTransport(event: RealtimeTransportEvent, now: SwiftDate, jitter: (Double) -> Double): List<RealtimeEffect> =
        when (event) {
            RealtimeTransportEvent.Opened -> emptyList()
            RealtimeTransportEvent.Joined -> {
                if (state !is RealtimeState.Connecting) return emptyList()
                failingSince = null
                forcedRefreshUsedThisAttempt = false
                lastHeartbeatSentAt = null
                state = RealtimeState.Subscribed(now, now)
                listOf(RealtimeEffect.CatchUp)
            }
            is RealtimeTransportEvent.JoinRejected -> {
                val attempt = (state as? RealtimeState.Connecting)?.attempt ?: return emptyList()
                when (event.rejection) {
                    RealtimeJoinRejection.ExpiredToken -> {
                        if (!forcedRefreshUsedThisAttempt) {
                            forcedRefreshUsedThisAttempt = true
                            listOf(RealtimeEffect.RefreshToken(force = true))
                        } else {
                            promote(RealtimeFailure.unauthorized, attempt, now, jitter)
                        }
                    }
                    RealtimeJoinRejection.Unauthorized -> promote(RealtimeFailure.topicDenied, attempt, now, jitter, forcedDelay = policy.cap)
                    is RealtimeJoinRejection.Unknown -> dropToReconnecting(attempt, now, jitter)
                }
            }
            is RealtimeTransportEvent.Broadcast -> {
                val s = state as? RealtimeState.Subscribed ?: return emptyList()
                state = RealtimeState.Subscribed(s.since, now)
                when (event.event) {
                    RealtimeLinkConstants.messageReadBroadcastEvent -> listOf(RealtimeEffect.MessageReadSignal)
                    RealtimeLinkConstants.tetrisBroadcastEvent -> listOf(RealtimeEffect.TetrisSignal)
                    RealtimeLinkConstants.gomokuBroadcastEvent -> listOf(RealtimeEffect.GomokuSignal)
                    RealtimeLinkConstants.chessBroadcastEvent -> listOf(RealtimeEffect.ChessSignal)
                    else -> listOf(RealtimeEffect.Drain)
                }
            }
            RealtimeTransportEvent.HeartbeatAck -> {
                val s = state as? RealtimeState.Subscribed ?: return emptyList()
                state = RealtimeState.Subscribed(s.since, now)
                emptyList()
            }
            RealtimeTransportEvent.HeartbeatTimedOut, is RealtimeTransportEvent.Closed -> when (val s = state) {
                is RealtimeState.Connecting -> dropToReconnecting(s.attempt, now, jitter)
                is RealtimeState.Subscribed -> dropToReconnecting(0, now, jitter)
                else -> emptyList()
            }
        }

    /**
     * INV-RealtimeLink-e07f7abd 이식: 좀비 소켓(Wi-Fi 이탈·VPN 전환의 half-open TCP)은 닫힘 사건이 영영 안 온다 —
     * 하트비트 두 번(50초) 동안 아무 소리도 없으면 스스로 끊고 다시 붙는다(틱이 잰다).
     * INV-RealtimeLink-7987373f 이식: `workEnded`(근무가 끝나면 소켓을 내린다)는 지웠다 — 소켓 기준은 로그인뿐.
     */
    private fun applyTick(now: SwiftDate, jitter: (Double) -> Double): List<RealtimeEffect> = when (val s = state) {
        is RealtimeState.Subscribed -> {
            val silence = now.timeIntervalSince(s.lastHeardAt)
            if (silence > RealtimeLinkConstants.heartbeatIntervalSeconds * RealtimeLinkConstants.heartbeatMissesBeforeDead.toDouble()) {
                listOf<RealtimeEffect>(RealtimeEffect.Disconnect) + dropToReconnecting(0, now, jitter)
            } else {
                val sentAgo = lastHeartbeatSentAt?.let { now.timeIntervalSince(it) } ?: Double.MAX_VALUE
                if (sentAgo >= RealtimeLinkConstants.heartbeatIntervalSeconds) {
                    lastHeartbeatSentAt = now
                    state = RealtimeState.Subscribed(s.since, s.lastHeardAt)
                    listOf(RealtimeEffect.SendHeartbeat)
                } else {
                    emptyList()
                }
            }
        }
        is RealtimeState.Connecting -> {
            if (!(now.timeIntervalSince(s.since) > joinTimeoutSeconds)) emptyList()
            else listOf<RealtimeEffect>(RealtimeEffect.Disconnect) + dropToReconnecting(s.attempt, now, jitter)
        }
        is RealtimeState.Reconnecting -> {
            if (now.timeIntervalSince(s.backoff.failingSince) > RealtimeLinkConstants.failedAfterSeconds) {
                state = RealtimeState.Failed(s.backoff, RealtimeFailure.exhausted)
            }
            emptyList()
        }
        else -> emptyList()
    }

    private fun beginConnecting(attempt: Long, now: SwiftDate, resetFailure: Boolean): List<RealtimeEffect> {
        val token = accessToken
        if (token == null) {
            state = RealtimeState.Idle(IdleReason.signedOut)
            return listOf(RealtimeEffect.Disconnect, RealtimeEffect.CancelRetry)
        }
        if (resetFailure) failingSince = null
        forcedRefreshUsedThisAttempt = false
        lastHeartbeatSentAt = null
        state = RealtimeState.Connecting(maxOf(1L, attempt), now)
        return listOf(RealtimeEffect.Connect(token), RealtimeEffect.ScheduleTokenRefresh(tokenRefreshDate(token, now)))
    }

    private fun dropToReconnecting(failedAttempt: Long, now: SwiftDate, jitter: (Double) -> Double): List<RealtimeEffect> {
        val start = failingSince ?: now
        failingSince = start
        val delay = policy.delay(maxOf(1L, failedAttempt), jitter)
        val retryAt = now.addingTimeInterval(delay)
        state = RealtimeState.Reconnecting(Backoff(maxOf(1L, failedAttempt + 1), retryAt, start))
        return listOf(RealtimeEffect.ScheduleRetry(retryAt))
    }

    private fun promote(
        reason: RealtimeFailure,
        failedAttempt: Long,
        now: SwiftDate,
        jitter: (Double) -> Double,
        forcedDelay: Double? = null,
    ): List<RealtimeEffect> {
        val start = failingSince ?: now
        failingSince = start
        val delay = forcedDelay ?: policy.delay(maxOf(1L, failedAttempt), jitter)
        val retryAt = now.addingTimeInterval(delay)
        state = RealtimeState.Failed(Backoff(maxOf(1L, failedAttempt + 1), retryAt, start), reason)
        return listOf(RealtimeEffect.ScheduleRetry(retryAt))
    }
}
