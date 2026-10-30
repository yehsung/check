// 원본: Sources/CheckCore/SupabaseWorkServiceMacOnly.swift 1017-1138(WorkTickGate) · Sources/check/WorkTimerStoreSync.swift 1093-1200(레거시 하트비트 폴백) @ a90d8623
package com.yehsung.aingcheck.feature.desktop.work.service

import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.coroutines.cancellation.CancellationException

/**
 * work_tick 사용 가능 판정(⑨): 404·PGRST202·403·42501·v≠1·디코드 실패 → 이 실행 동안 끈다([disable]).
 * 5xx 등 일시 실패 3연속 → 1시간 끈다. 성공하면 연속 수를 0 으로.
 */
class WorkTickGate {
    companion object {
        const val transientFailureLimit = 3
        const val suspensionSeconds: Double = 60.0 * 60.0
    }

    data class Snapshot(
        val disabledReason: String?,
        val disabledAt: SwiftDate?,
        val consecutiveTransientFailures: Int,
        val suspendedUntil: SwiftDate?,
        val lastTransientReason: String?,
        val successCount: Int,
        val fallbackCount: Int,
        val lastClockSkewSeconds: Double?,
    )

    private val lock = Any()
    private var disabledReason: String? = null
    private var disabledAt: SwiftDate? = null
    private var consecutiveTransientFailures = 0
    private var suspendedUntil: SwiftDate? = null
    private var lastTransientReason: String? = null
    private var successCount = 0
    private var fallbackCount = 0
    private var lastClockSkewSeconds: Double? = null

    fun isAvailable(now: SwiftDate): Boolean = synchronized(lock) {
        if (disabledReason != null) return false
        val until = suspendedUntil
        if (until != null) {
            if (now < until) return false
            suspendedUntil = null
            consecutiveTransientFailures = 0
        }
        true
    }

    fun disable(reason: String, at: SwiftDate) = synchronized(lock) {
        if (disabledReason != null) return
        disabledReason = reason
        disabledAt = at
    }

    fun recordTransientFailure(reason: String, at: SwiftDate) = synchronized(lock) {
        lastTransientReason = reason
        consecutiveTransientFailures += 1
        if (consecutiveTransientFailures >= transientFailureLimit) suspendedUntil = at.addingTimeInterval(suspensionSeconds)
    }

    fun recordSuccess(serverNow: SwiftDate?, localNow: SwiftDate) = synchronized(lock) {
        successCount += 1
        consecutiveTransientFailures = 0
        lastTransientReason = null
        if (serverNow != null) lastClockSkewSeconds = serverNow.timeIntervalSince(localNow)
    }

    fun recordFallback() = synchronized(lock) { fallbackCount += 1 }

    val snapshot: Snapshot
        get() = synchronized(lock) {
            Snapshot(disabledReason, disabledAt, consecutiveTransientFailures, suspendedUntil, lastTransientReason, successCount, fallbackCount, lastClockSkewSeconds)
        }
}

/**
 * 레거시 하트비트 폴백(work_tick 이 꺼졌을 때 — Swift `sendHeartbeatIfWorking` · `reportDeviceInputIfPossible`)의 **와이어 몫**.
 * 판정 값(흡수·확인된 세션 id·강한 소유·기기 id)은 상태 갈래(W2-g5)가 넘긴다 — 여기서는 순서와 가드만.
 *  · ⑬ 공유 행에는 **confirmedSessionId 만** 싣는다. 흡수 중이거나 확인 전이면 입력만(reportDeviceInput).
 *  · ⑭ 입력 관측(observedInput)은 호출부가 소유 판정보다 먼저 한다.
 *  · deviceId null 이면 기기 단위 쓰기 0(work_status_devices 요청 0).
 *  · 세대가 바뀌면(로그아웃·계정 전환) 기기 행을 쓰지 않는다. 실패는 삼킨다(다음 주기가 다시 낸다).
 */
data class LegacyHeartbeatFacts(
    val teamId: String,
    val adopted: Boolean,
    val confirmedSessionId: String?,
    val deviceId: String?,
    val ownsStrongly: Boolean,
    val awayServerSupported: Boolean,
    val observedInput: SwiftDate?,
)

/** 낸 요청 갈래(시험·진단용). */
enum class LegacyHeartbeatPath { INPUT_ONLY, HEARTBEAT, HEARTBEAT_AND_DEVICE, NOTHING }

suspend fun SessionHost.sendLegacyHeartbeat(facts: LegacyHeartbeatFacts): LegacyHeartbeatPath {
    val input = if (facts.awayServerSupported) facts.observedInput else null
    val sessionId = facts.confirmedSessionId
    if (facts.adopted || sessionId == null) {
        val deviceId = facts.deviceId
        if (input == null || deviceId == null) return LegacyHeartbeatPath.NOTHING
        swallow { withSessionRetry { s -> service.reportDeviceInput(s.accessToken, facts.teamId, s.userID, deviceId, input) } }
        return LegacyHeartbeatPath.INPUT_ONLY
    }
    val generation = sessionGeneration
    swallow { withSessionRetry { s -> service.heartbeat(s.accessToken, facts.teamId, s.userID, sessionId, input) } }
    if (generation != sessionGeneration) return LegacyHeartbeatPath.HEARTBEAT
    val deviceId = facts.deviceId ?: return LegacyHeartbeatPath.HEARTBEAT
    swallow {
        withSessionRetry { s ->
            service.upsertStatusDevice(s.accessToken, facts.teamId, s.userID, deviceId, sessionId, facts.ownsStrongly, input)
        }
    }
    return LegacyHeartbeatPath.HEARTBEAT_AND_DEVICE
}

private inline fun swallow(block: () -> Unit) {
    try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        // 생존신호 실패는 다음 주기가 다시 낸다(Swift catch {}).
    }
}
