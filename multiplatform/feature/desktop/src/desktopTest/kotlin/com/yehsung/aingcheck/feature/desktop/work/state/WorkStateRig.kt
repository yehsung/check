// W2-g5 시험 기반 — 합성 픽스처만(실제 홈·계정·로그 0). 큐는 핀 WorkQueue 의 가짜(끝-끝 HTTP 는 통합 몫).
package com.yehsung.aingcheck.feature.desktop.work.state

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.OpenSessionFact
import com.yehsung.aingcheck.core.wire.models.StatusDeviceClaim
import com.yehsung.aingcheck.core.wire.models.TeamMemberStatus
import com.yehsung.aingcheck.core.wire.models.WorkStatus
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.work.PendingWorkItem
import com.yehsung.aingcheck.feature.desktop.work.ScavengeThrottle
import com.yehsung.aingcheck.feature.desktop.work.WorkEvent
import com.yehsung.aingcheck.feature.desktop.work.WorkEventSink
import com.yehsung.aingcheck.feature.desktop.work.WorkQueue
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

internal val T0 = SwiftDate(1_789_621_500.0) // 2026-09-17 14:05 KST — Swift 골든과 같은 기준
internal const val ME = "00000000-0000-0000-0000-000000000002"
internal const val TEAM = "team-0001"
internal const val SESSION_S = "a0000000-0000-4000-8000-000000000001"
internal const val SESSION_X = "b0000000-0000-4000-8000-000000000002"
internal const val MAC_DEVICE = "3F2A9C1E-0000-4000-8000-0000000000AA"
internal const val WIN_DEVICE = "win:7b1e0c2a-0000-4000-8000-0000000000bb"

internal fun at(offsetSeconds: Int): SwiftDate = T0.addingTimeInterval(offsetSeconds.toDouble())

/** 핀 WorkQueue 가짜: 넣은 순서대로 쌓고, drain() 이 wq 의 성공 드레인을 흉내 낸다. */
internal class FakeWorkQueue : WorkQueue {
    private val flow = MutableStateFlow<List<PendingWorkItem>>(emptyList())
    override val items: StateFlow<List<PendingWorkItem>> = flow
    override fun enqueue(item: PendingWorkItem) {
        flow.value = flow.value + item
    }
    override suspend fun awaitIdle(timeoutMillis: Long) = Unit
    override val scavenge: ScavengeThrottle = ScavengeThrottle { true }
    override fun retainOwner(userId: String) {
        flow.value = flow.value.filter { it.ownerUserId == userId }
    }
    fun drain(): List<PendingWorkItem> = flow.value.also { flow.value = emptyList() }
}

internal class RecordingPolicy : WorkPolicyHooks {
    val calls = mutableListOf<String>()
    var marker: SleepCloseMarker? = null
    override fun clearAutoStartSuppression() { calls += "clearSuppression" }
    override fun suppressAutoStart(now: SwiftDate) { calls += "suppress" }
    override fun onSessionAnchored(anchor: SwiftDate, resetSleepBegan: Boolean, clearSleepMarker: Boolean) {
        calls += "anchored(${anchor.timeIntervalSince(T0).toInt()},$resetSleepBegan,$clearSleepMarker)"
        if (clearSleepMarker) marker = null
    }
    override fun onSessionEnded(resetSleepTracking: Boolean) {
        calls += "ended($resetSleepTracking)"
        if (resetSleepTracking) marker = null
    }
    override fun onLongSessionConfirmed(now: SwiftDate) { calls += "longConfirmed" }
    override fun pendingSleepClose(): SleepCloseMarker? = marker
    override fun clearPendingSleepClose() {
        calls += "clearMarker"
        marker = null
    }
    override fun clearAwayState() { calls += "clearAway" }
}

internal class WorkStateRig(deviceId: String? = null, userId: String? = ME) {
    var now: SwiftDate = T0
    var uid: String? = userId
    var input: SwiftDate? = null
    var reopen: WorkReopenCall? = null
    val queue = FakeWorkQueue()
    val kv = InMemoryDesktopKeyValueStore()
    val policy = RecordingPolicy()
    val events = mutableListOf<WorkEvent>()
    /** 사건이 올 때의 발행된 isWorking(I-8 순서 확인용). */
    val workingAtEvents = mutableListOf<Boolean>()
    private var storeRef: DesktopWorkStore? = null
    private var uuidCount = 0

    /** 맥처럼 대문자 UUID 를 낸다 — 세션 id 는 상태 코어가 소문자로 고쳐야 한다(C#22). */
    fun nextUuid(): String = "A0000000-0000-4000-8000-" + (++uuidCount).toString().padStart(12, '0')

    val store = DesktopWorkStore(
        queue = queue,
        kv = kv,
        deviceId = deviceId,
        userId = { uid },
        teamId = { TEAM },
        clock = { now },
        newUuid = { nextUuid() },
        events = WorkEventSink { e -> events += e; storeRef?.let { workingAtEvents += it.snapshot.value.isWorking } },
        policy = policy,
        meaningfulInput = { input },
        scope = null,
        reopenCall = WorkReopenCall { team, session -> reopen?.reopen(team, session) ?: error("reopen 미설정") },
    )

    init { storeRef = store }

    fun apply(member: TeamMemberStatus, generation: Int = store.workStateWriteGeneration) =
        store.applyRemoteOwnStatus(listOf(member), generation, now)

    fun own(sessionId: String, strength: SessionClaimStrength) {
        kv.putString(OwnedSessionLedger.OWNED_ID_KEY, sessionId)
        kv.putString(OwnedSessionLedger.OWNED_STRENGTH_KEY, strength.raw)
    }
}

internal fun working(
    sessionId: String,
    startedAt: SwiftDate,
    lastSeenAt: SwiftDate,
    claims: List<StatusDeviceClaim> = emptyList(),
    openSession: Boolean = true,
) = TeamMemberStatus(
    id = ME, name = "나", status = WorkStatus.working, updatedAt = lastSeenAt, currentSessionStartedAt = startedAt,
    lastSeenAt = lastSeenAt, activeSessionID = sessionId, deviceClaims = claims,
    openSession = if (openSession) OpenSessionFact(sessionId.lowercase(), startedAt) else null,
)

internal fun offWork(today: Long, lastSeenAt: SwiftDate) = TeamMemberStatus(
    id = ME, name = "나", status = WorkStatus.offWork, updatedAt = lastSeenAt, currentSessionStartedAt = null,
    todayDurationSeconds = today, lastSeenAt = lastSeenAt,
)
