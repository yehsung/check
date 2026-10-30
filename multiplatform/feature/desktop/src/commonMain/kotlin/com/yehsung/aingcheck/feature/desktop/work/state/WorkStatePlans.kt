// W2-g5 근무 상태 코어 — 틱·하트비트 **계획 값**과 정책 갈래(wp)로 가는 고리.
// HTTP 는 이 갈래가 내지 않는다: 계획 값을 조립(AppGraph·통합)이 wq 서비스로 보낸다(끝-끝 HTTP 는 통합 몫).
// 원본: Sources/check/WorkTimerStoreSync.swift 72-200(workTickIfPossible 인자 조립) · 1093-1160(sendHeartbeatIfWorking ·
//       reportDeviceInputIfPossible) @ a90d8623.
package com.yehsung.aingcheck.feature.desktop.work.state

import com.yehsung.aingcheck.core.wire.SwiftDate

/**
 * work_tick 인자(Swift makeWorkTickRequest 에 넘기는 값). ⑬ 공유 행·tick 에는 **confirmedSessionID 만** 싣는다.
 * 4갈래: 흡수(입력만) · 확인된 내 세션(id+opened) · 확인 전(입력만) · 세션 없음(heartbeat=false).
 * [deviceId] 는 기기 신원이 없으면 null(p_device_id null — 기기 행 쓰기 0).
 */
data class WorkTickArgs(
    val teamId: String,
    val heartbeat: Boolean,
    val sessionId: String?,
    val deviceId: String?,
    val openedSession: Boolean,
    val lastInputAt: SwiftDate?,
    val ownerUserId: String,
    /** 늦은 응답 버림용(Swift writeGeneration) — 응답을 applyRemoteOwnStatus 에 이 값으로 넘긴다. */
    val writeGeneration: Int,
)

/** 레거시 하트비트 계획(work_tick 이 꺼졌거나 실패했을 때 — Swift sendHeartbeatIfWorking). */
sealed interface HeartbeatPlan {
    /** 근무 중 아님 · 로그인/팀 없음 · 입력 보고 조건 미달. 요청 0. */
    data object Skip : HeartbeatPlan

    /** ②′ 흡수 세션이거나 확인 전: 세션 id 없이 기기 입력 시각만(reportDeviceInput, 본문 키 4개 — ⑦). */
    data class DeviceInputOnly(val teamId: String, val deviceId: String, val lastInputAt: SwiftDate) : HeartbeatPlan

    /** 확인된 내 세션: work_statuses 하트비트 + (기기 신원이 있으면) work_status_devices upsert. */
    data class Beat(
        val teamId: String,
        val sessionId: String,
        val lastInputAt: SwiftDate?,
        val device: DeviceClaimUpsert?,
    ) : HeartbeatPlan
}

data class DeviceClaimUpsert(val deviceId: String, val sessionId: String, val openedSession: Boolean, val lastInputAt: SwiftDate?)

/** Swift PendingSleepClose(잠자기 마감 정정 마커) — 기록·영속은 정책 갈래(wp), 상태 코어는 서버가 닫은 갈래 (a)/(b) 에서 읽기만. */
data class SleepCloseMarker(
    val sessionId: String,
    val sessionStartedAt: SwiftDate,
    val sleepBeganAt: SwiftDate,
    val lastInputAt: SwiftDate?,
)

/**
 * 상태 코어 → 정책 갈래(wp: 잠자기·12h·넛지 억제·깨움 게이트) 고리. 핀(WorkContracts)에 없는 자리라 이 갈래가 두고
 * 조립(AppGraph)이 wp 구현에 잇는다 — 기본은 전부 no-op(조립 전·시험).
 */
interface WorkPolicyHooks {
    /** Swift clearAutoStartSuppression — 어떤 경로로든 근무가 시작되면 억제는 끝. */
    fun clearAutoStartSuppression() {}

    /** Swift suppressAutoStart — 수동 종료(⑰ 종료 시퀀스 제외)·다른 기기에서 끝냄. */
    fun suppressAutoStart(now: SwiftDate) {}

    /**
     * 세션이 (다시) 섰다: 12h 기준점 = [anchor], 12h 프롬프트는 상태 코어가 이미 지웠다.
     * [resetSleepBegan] sleepBeganAt=nil(start·흡수), [clearSleepMarker] 마커 지움(start 만).
     */
    fun onSessionAnchored(anchor: SwiftDate, resetSleepBegan: Boolean, clearSleepMarker: Boolean) {}

    /** 세션이 끝났다: 12h 기준점 nil. [resetSleepTracking] sleepBeganAt=nil + 마커 지움(stop·autoStop·계정 전환). */
    fun onSessionEnded(resetSleepTracking: Boolean) {}

    /** Swift confirmStillWorking — 12h 기준점 = now. */
    fun onLongSessionConfirmed(now: SwiftDate) {}

    fun pendingSleepClose(): SleepCloseMarker? = null

    fun clearPendingSleepClose() {}

    /** 계정 전환(Swift adoptWorkStateOwner 의 clearAwayState). */
    fun clearAwayState() {}

    /** WorkQueueHost.awaitWakeGate 위임(깨움 게이트 최대 10초는 wp). */
    suspend fun awaitWakeGate() {}

    companion object {
        val NONE: WorkPolicyHooks = object : WorkPolicyHooks {}
    }
}

/** 상수(Swift WorkTimerStore 47·49·68·74·93 · WorkTimerStoreSync 1961·1963). */
object WorkStateConstants {
    /** abandonedSessionThresholdSeconds — 10분. */
    const val ABANDONED_THRESHOLD_SECONDS: Double = 10 * 60.0

    /** recentAutoCloseResumeWindowSeconds — 30분. */
    const val RECENT_AUTO_CLOSE_RESUME_WINDOW_SECONDS: Double = 30 * 60.0

    /** adoptedReclaimStaleSeconds = sleepGraceSeconds 5분. */
    const val ADOPTED_RECLAIM_STALE_SECONDS: Double = 5 * 60.0

    const val ADOPTED_RECLAIM_MIN_OBSERVATIONS: Int = 3

    const val REMOTE_ABANDONED_CLOSE_NOTICE = "연결이 끊겨 근무가 자동 종료됐어요"
    const val REMOTE_ENDED_ELSEWHERE_NOTICE = "다른 기기에서 근무를 끝냈어요"
    const val SLEEP_CLOSE_MESSAGE = "잠자기로 자동 근무종료됨"
    const val LOGIN_REQUIRED = "로그인 필요"
    const val RESUMED_MESSAGE = "근무 재개됨"
    const val RESUME_FAILED_MESSAGE = "재개 실패"
}
