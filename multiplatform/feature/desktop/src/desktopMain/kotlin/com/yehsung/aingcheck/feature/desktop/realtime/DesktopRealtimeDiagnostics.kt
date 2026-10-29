// 원본: Sources/check/WorkTimerStoreRealtime.swift:51-101(RealtimeDiagnostics) · 452-485(진단 한 줄 · cause) @ c4e0ebfc
package com.yehsung.aingcheck.feature.desktop.realtime

import com.yehsung.aingcheck.core.net.realtime.IdleReason
import com.yehsung.aingcheck.core.net.realtime.RealtimeEvent
import com.yehsung.aingcheck.core.net.realtime.RealtimeJoinRejection
import com.yehsung.aingcheck.core.net.realtime.RealtimeState
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransportEvent
import com.yehsung.aingcheck.core.wire.SwiftDate
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.floor

/** 설정 화면 진단 — "찌르기가 안 와요" 신고에서 소켓/따라잡기/토큰 중 어디인지 가른다. 러너만 쓴다(읽기는 누구나). */
class DesktopRealtimeDiagnostics {
    data class Entry(val at: SwiftDate, val from: String, val to: String, val cause: String)

    /** 최근 전이 10건(링 버퍼). */
    var recent: List<Entry> = emptyList()
        private set
    var totalReconnects: Int = 0
        private set
    var lastCatchUpAt: SwiftDate? = null
        internal set
    var lastCatchUpCount: Int = 0
        internal set

    /** 마지막 따라잡기가 몇 번 시도했는가(요청 수는 다른 스위트와 섞이므로 시도 횟수를 따로 남긴다). */
    var lastCatchUpAttempts: Int = 0
        internal set
    var lastCatchUpFailure: String? = null
        internal set

    /** 전송자가 아예 없는가 — `idle(disabled)` 이 가장 조용한 결말이라 따로 남긴다. */
    var transportAvailable: Boolean = false
        internal set

    internal fun record(from: RealtimeState, to: RealtimeState, cause: String, at: SwiftDate) {
        if (from == to) return
        append(Entry(at, label(from), label(to), cause))
        if (to is RealtimeState.Reconnecting) totalReconnects += 1
    }

    /** 상태 전이가 아닌 사실(토큰 추월 등). record 는 from == to 를 버리므로 따로 둔다. */
    internal fun note(cause: String, state: RealtimeState, at: SwiftDate) {
        val l = label(state)
        append(Entry(at, l, l, cause))
    }

    private fun append(entry: Entry) {
        recent = (recent + entry).takeLast(RECENT_LIMIT)
    }

    companion object {
        const val RECENT_LIMIT = 10

        /** 맥 `CheckCoreShared.realtimeDiagnosticsTime`(en_US_POSIX "HH:mm:ss", 기기 시간대). */
        private val TIME: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm:ss", Locale.ROOT)

        fun label(state: RealtimeState): String = when (state) {
            is RealtimeState.Idle -> when (state.reason) {
                IdleReason.signedOut -> "idle(signedOut)"
                IdleReason.suspended -> "idle(suspended)"
                IdleReason.disabled -> "idle(disabled)"
            }
            is RealtimeState.Connecting -> "connecting(${state.attempt})"
            is RealtimeState.Subscribed -> "subscribed"
            is RealtimeState.Reconnecting -> "reconnecting(${state.backoff.attempt})"
            is RealtimeState.Failed -> "failed(${state.v1})"
        }

        /** Swift `cause(of:)` 와 같은 글자. */
        fun cause(event: RealtimeEvent): String = when (event) {
            is RealtimeEvent.SignedIn -> "signedIn"
            RealtimeEvent.SignedOut -> "signedOut"
            RealtimeEvent.WillSleep -> "willSleep"
            RealtimeEvent.DidWake -> "didWake"
            RealtimeEvent.BackoffElapsed -> "backoffElapsed"
            RealtimeEvent.Tick -> "tick"
            is RealtimeEvent.TokenRefreshed -> "tokenRefreshed"
            is RealtimeEvent.TokenRefreshFailed -> if (event.fatal) "tokenRefreshFailed(fatal)" else "tokenRefreshFailed"
            RealtimeEvent.UserRequestedRetry -> "userRequestedRetry"
            is RealtimeEvent.Transport -> when (val t = event.event) {
                RealtimeTransportEvent.Opened -> "opened"
                RealtimeTransportEvent.Joined -> "joined"
                is RealtimeTransportEvent.JoinRejected -> "joinRejected(${rejection(t.rejection)})"
                is RealtimeTransportEvent.Broadcast -> "broadcast(${t.event})"
                RealtimeTransportEvent.HeartbeatAck -> "heartbeatAck"
                RealtimeTransportEvent.HeartbeatTimedOut -> "heartbeatTimedOut"
                is RealtimeTransportEvent.Closed -> "closed(${t.code?.toString() ?: "-"})"
            }
        }

        private fun rejection(r: RealtimeJoinRejection): String = when (r) {
            RealtimeJoinRejection.ExpiredToken -> "expiredToken"
            RealtimeJoinRejection.Unauthorized -> "unauthorized"
            is RealtimeJoinRejection.Unknown -> "unknown(\"${r.reason}\")"
        }

        fun time(at: SwiftDate, zone: ZoneId): String {
            val seconds = at.timeIntervalSince1970
            val whole = floor(seconds)
            val instant = Instant.ofEpochSecond(whole.toLong(), ((seconds - whole) * 1e9).toLong())
            return TIME.format(instant.atZone(zone))
        }

        /** 설정 화면 한 줄. 구분자는 ` · ` 하나로 고정(로그를 눈으로 자르는 사람이 있다). */
        fun line(state: RealtimeState, d: DesktopRealtimeDiagnostics, catchUpFailedAt: SwiftDate?, zone: ZoneId): String {
            val parts = mutableListOf(label(state))
            if (!d.transportAvailable) parts += "전송자 없음"
            parts += "재연결 ${d.totalReconnects}회"
            val at = d.lastCatchUpAt
            parts += if (at != null) "따라잡기 ${time(at, zone)} ${d.lastCatchUpCount}건" else "따라잡기 없음"
            if (catchUpFailedAt != null) parts += "따라잡기 실패"
            return parts.joinToString(" · ")
        }
    }
}
