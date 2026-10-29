// 원본: Sources/check/WorkTimerStore.swift 44-97(상수) · 2242-2325(handleSleep·handleWake) · 2327-2380(12시간 확인)
//       · 2473-2490·4505-4510(잠자기 마커) · Sources/check/WorkTimerStoreSync.swift 2005-2060(마커 정정 (a)/(b)) @ a90d8623
// W2-g6(wp) 근무 정책 — 잠자기 5분 유예 · 깨어남 마커 · 12시간 + 30분. 마감은 핀의 WorkAutoClose 관문(ws 구현)만 부른다.
// 규약 번호는 지시서 work.md §2 의 ⑲~㉓ 다. 시각 타입은 core 관례 SwiftDate(핀 조정 ⑥).
package com.yehsung.aingcheck.feature.desktop.work.policy

import com.yehsung.aingcheck.core.foundation.platform.desktop.InputKind
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.work.AutoCloseReason
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkState
import com.yehsung.aingcheck.feature.desktop.work.PendingWorkItem
import com.yehsung.aingcheck.feature.desktop.work.PendingWorkOperation
import com.yehsung.aingcheck.feature.desktop.work.WorkAutoClose
import com.yehsung.aingcheck.feature.desktop.work.WorkQueue
import com.yehsung.aingcheck.feature.desktop.work.WorkSessionIds
import com.yehsung.aingcheck.feature.desktop.work.lap.ultraLapKey
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Swift WorkTimerStore 정적 상수(44-97) — 골든 desktop-work-policy/constants 가 Swift 값과 대조한다. */
object WorkPolicyConstants {
    const val SLEEP_GRACE_SECONDS: Double = 5 * 60.0
    const val HEARTBEAT_INTERVAL_SECONDS: Double = 30.0
    /** = 잠자기 유예 + 4 하트비트(7분). 방치 자가 마감 임계(Sync:1255). */
    const val ADOPTED_RECLAIM_STALE_SECONDS: Double = SLEEP_GRACE_SECONDS + 4 * HEARTBEAT_INTERVAL_SECONDS
    const val LONG_SESSION_THRESHOLD_SECONDS: Double = 12 * 60 * 60.0
    const val LONG_SESSION_RESPONSE_WINDOW_SECONDS: Double = 30 * 60.0
    const val RECENT_AUTO_CLOSE_RESUME_WINDOW_SECONDS: Double = 30 * 60.0
    const val AWAY_SYNC_IDLE_THROTTLE_SECONDS: Double = 120.0
    /** 깨움 결합 게이트 상한(WorkTimerStore.swift:427 wakeGateTimeoutSeconds). */
    const val WAKE_GATE_TIMEOUT_SECONDS: Double = 10.0
    /** finishWorkBeforeQuit(timeout: 3). */
    const val QUIT_TIMEOUT_SECONDS: Double = 3.0

    const val MESSAGE_SLEEP: String = "잠자기로 자동 근무종료됨"
    const val MESSAGE_LONG_SESSION: String = "장시간 미확인으로 자동 근무종료됨"
    const val MESSAGE_AWAY: String = "자리 비움으로 자동 근무종료됨"
}

/**
 * 정책의 순수 규칙 한 벌. 시험의 negative_* 가 한 규칙만 바꾼 하위 클래스를 넣어 "규칙을 깨면 빨강"을 잰다.
 * 프로덕션은 [Standard] 만 쓴다.
 */
open class WorkPolicyRules {
    /** ⑲ 유예는 **초과**일 때만 마감한다(300.000초 유지 · 300.001초 마감). */
    open fun sleepExceedsGrace(asleepSeconds: Double): Boolean = asleepSeconds > WorkPolicyConstants.SLEEP_GRACE_SECONDS

    /** ★⑲(2313) endedAt = max(start, min(sleepBegan, lastInput)) — 절전 대기만큼의 덤을 빼고, 0초 세션이 되지 않게 시작으로 클램프. */
    open fun sleepEndedAt(startedAt: SwiftDate?, sleepBeganAt: SwiftDate, lastInputAt: SwiftDate?): SwiftDate =
        maxOf(startedAt ?: sleepBeganAt, minOf(sleepBeganAt, lastInputAt ?: sleepBeganAt))

    /** ㉑ 30분 무응답 마감 시각 = 앵커 + 12시간(지금이 아니다). */
    @Suppress("UNUSED_PARAMETER")
    open fun longSessionEndedAt(anchor: SwiftDate, now: SwiftDate): SwiftDate =
        anchor.addingTimeInterval(WorkPolicyConstants.LONG_SESSION_THRESHOLD_SECONDS)

    /** ㉒ 경계는 배타(정확히 임계면 마감하지 않는다 — 서버 부등호와 같게). */
    open fun awayExceeded(now: SwiftDate, lastInput: SwiftDate, thresholdSeconds: Double): Boolean =
        now.timeIntervalSince(lastInput) > thresholdSeconds

    /** ㉓ 흡수 세션(다른 기기가 연 세션)은 잠자기·12h·away·종료 마감에서 모두 뺀다. */
    open fun excludesFromAutoClose(snapshot: DesktopWorkSnapshot): Boolean = snapshot.adopted

    /** ㉔ 넛지·자리 비움 입력은 키·클릭·휠만(MOVE 제외 — 광마우스 지터·합성 이동). */
    open val meaningfulInputKinds: Set<InputKind> = setOf(InputKind.KEY, InputKind.CLICK, InputKind.WHEEL)

    /** ㉕ 랩 스로틀 키는 랩마다 다르다(Swift ultraLapKey). */
    open fun lapKey(lap: Long): String = ultraLapKey(lap)

    companion object {
        val Standard: WorkPolicyRules = WorkPolicyRules()
    }
}

/** Swift startedAt != nil 과 같은 판정(근무 중이고 시작 시각이 있다). */
internal val DesktopWorkSnapshot.working: Boolean get() = isWorking && startedAt != null

// ---------- 잠자기 마커(v0.2.36) ----------

/**
 * 근무 중 잠든 순간의 관측(Swift PendingSleepClose 4505). 시각은 Swift Date 기본 Codable 과 같은 기준일(2001) 초.
 * 잠자는 사이 앱이 죽어도 다음 실행이 서버의 abandoned 마감을 sleep 으로 정정하게 디스크에 남긴다.
 */
@Serializable
data class PendingSleepClose(
    val sessionID: String,
    val sessionStartedAt: Double,
    val sleepBeganAt: Double,
    val lastInputAt: Double? = null,
) {
    val startedAtDate: SwiftDate get() = SwiftDate.fromReferenceDate(sessionStartedAt)
    val sleepBeganAtDate: SwiftDate get() = SwiftDate.fromReferenceDate(sleepBeganAt)
    val lastInputAtDate: SwiftDate? get() = lastInputAt?.let(SwiftDate::fromReferenceDate)

    companion object {
        fun of(sessionId: String, startedAt: SwiftDate, sleepBeganAt: SwiftDate, lastInputAt: SwiftDate?): PendingSleepClose =
            PendingSleepClose(
                sessionID = sessionId,
                sessionStartedAt = startedAt.timeIntervalSinceReferenceDate,
                sleepBeganAt = sleepBeganAt.timeIntervalSinceReferenceDate,
                lastInputAt = lastInputAt?.timeIntervalSinceReferenceDate,
            )
    }
}

/** 마커 영속(키는 Swift 와 같다). 시작·수동 종료·자동 마감이 지우는 자리는 ws 가 [clear] 를 부른다. */
class SleepCloseMarkerStore(private val store: DesktopKeyValueStore) {
    fun persist(marker: PendingSleepClose) {
        store.putString(KEY, JSON.encodeToString(PendingSleepClose.serializer(), marker))
    }

    /** 깨진 값은 없는 것으로 접는다(Swift try? decode). */
    fun load(): PendingSleepClose? {
        val text = store.getString(KEY) ?: return null
        return runCatching { JSON.decodeFromString(PendingSleepClose.serializer(), text) }.getOrNull()
    }

    fun clear() {
        store.remove(KEY)
    }

    companion object {
        const val KEY: String = "check.sleepClose.pending"
        internal val JSON: Json = Json { ignoreUnknownKeys = true; explicitNulls = false }
    }
}

/** handleWake 의 갈래(시험이 읽는다). */
sealed interface WakeOutcome {
    data object NotWorking : WakeOutcome
    data object WithinGrace : WakeOutcome
    data object Adopted : WakeOutcome
    data class Closed(val endedAt: SwiftDate) : WakeOutcome
}

/**
 * 잠자기 5분 유예(Swift handleSleep/handleWake). OS 신호 배선(전원 브로드캐스트 · 벽시계 공백 30초)은 W3-d 가 [handleSleep]/[handleWake] 로 잇는다.
 *
 * @param beforeSleepGuard ⚠️⑳ 비근무 가드보다 **앞**에서 부른다(소켓·찌르기 수명 `DesktopSocialLifecycle.onWillSleep`).
 * @param wakeFirst ⚠️⑳ handleWake 의 **맨 앞**(깨움 게이트 [WakeGate.begin] · 재연결). 아래 조기 리턴 가지가 셋이라 뒤에 두면 대부분 안 돈다.
 */
class SleepPolicy(
    private val state: DesktopWorkState,
    private val autoClose: WorkAutoClose,
    private val markers: SleepCloseMarkerStore,
    private val beforeSleepGuard: (SwiftDate) -> Unit = {},
    private val wakeFirst: (SwiftDate) -> Unit = {},
    private val rules: WorkPolicyRules = WorkPolicyRules.Standard,
) {
    /** 메모리의 잠든 시각(마커와 별개 — 마커는 재실행 정정용). */
    var sleepBeganAt: SwiftDate? = null
        private set

    fun handleSleep(at: SwiftDate) {
        beforeSleepGuard(at)
        val snap = state.snapshot.value
        if (!snap.working) return
        val start = snap.startedAt ?: return
        sleepBeganAt = at
        // 흡수 세션은 심지 않는다 — 내 덮개 시각은 남의 세션의 마감 근거가 될 수 없다(㉓).
        val sessionId = WorkSessionIds.canonical(snap.sessionId)
        if (!rules.excludesFromAutoClose(snap) && sessionId != null) {
            markers.persist(PendingSleepClose.of(sessionId, start, at, snap.lastMeaningfulInputAt))
        }
    }

    fun handleWake(at: SwiftDate): WakeOutcome {
        wakeFirst(at)
        val began = sleepBeganAt
        val snap = state.snapshot.value
        if (began == null || !snap.working) {
            sleepBeganAt = null
            return WakeOutcome.NotWorking
        }
        if (!rules.sleepExceedsGrace(at.timeIntervalSince(began))) {
            sleepBeganAt = null
            // 유예 안 잠자기 = 세션 계속. 스캐빈저 임계(10분)보다 짧아 서버가 먼저 닫았을 수 없으니 마커도 소용을 다했다.
            markers.clear()
            return WakeOutcome.WithinGrace
        }
        if (rules.excludesFromAutoClose(snap)) {
            sleepBeganAt = null
            return WakeOutcome.Adopted
        }
        val endedAt = rules.sleepEndedAt(snap.startedAt, began, snap.lastMeaningfulInputAt)
        sleepBeganAt = null
        autoClose.closeOwnedSessionLocally(endedAt, AutoCloseReason.SLEEP, WorkPolicyConstants.MESSAGE_SLEEP)
        markers.clear()
        return WakeOutcome.Closed(endedAt)
    }
}

/** 마커 정정의 갈래(Sync:2011). */
sealed interface SleepCorrection {
    data object None : SleepCorrection
    /** (a) 로컬은 아직 근무 중인데 서버가 먼저 닫았다 → autoStop 관문으로 sleep 마감. */
    data class ClosedLocally(val endedAt: SwiftDate) : SleepCorrection
    /** (b) 재실행: 로컬 근무 없음 + 내 소유 세션 → 정정 Stop 항목만 큐에(드레인 → 0행 → correctAutoClose). 소유 해제는 호출자(ws). */
    data class Enqueued(val item: PendingWorkItem) : SleepCorrection
}

/**
 * 서버가 내 행을 off_work 로 돌려준 자리(ws 의 applyRemoteOwnStatus)와 다음 실행이 부른다. 정정은 1회 — 쓰면 마커를 지운다.
 */
class SleepCloseCorrection(
    private val markers: SleepCloseMarkerStore,
    private val autoClose: WorkAutoClose,
    private val queue: WorkQueue,
    private val newItemId: () -> String,
    private val rules: WorkPolicyRules = WorkPolicyRules.Standard,
) {
    fun onOwnStatusOffWork(
        snapshot: DesktopWorkSnapshot,
        isOwnedByThisDevice: (sessionId: String) -> Boolean,
        ownerUserId: String?,
    ): SleepCorrection {
        val marker = markers.load() ?: return SleepCorrection.None
        val endedAt = rules.sleepEndedAt(marker.startedAtDate, marker.sleepBeganAtDate, marker.lastInputAtDate)
        if (snapshot.working && !rules.excludesFromAutoClose(snapshot) &&
            WorkSessionIds.canonical(snapshot.sessionId) == marker.sessionID
        ) {
            markers.clear()
            autoClose.closeOwnedSessionLocally(endedAt, AutoCloseReason.SLEEP, WorkPolicyConstants.MESSAGE_SLEEP)
            return SleepCorrection.ClosedLocally(endedAt)
        }
        if (!snapshot.working && isOwnedByThisDevice(marker.sessionID)) {
            markers.clear()
            val item = PendingWorkItem(
                id = newItemId(),
                operation = PendingWorkOperation.Stop(maxOf(0L, endedAt.timeIntervalSince(marker.startedAtDate).toLong())),
                sessionId = marker.sessionID,
                sessionStartedAt = marker.startedAtDate,
                endedAt = endedAt,
                ownerUserId = ownerUserId,
                autoCloseReason = AutoCloseReason.SLEEP,
            )
            queue.enqueue(item)
            return SleepCorrection.Enqueued(item)
        }
        return SleepCorrection.None
    }
}

// ---------- 12시간 확인(30분 무응답 자동 마감) ----------

/**
 * Swift evaluateLongSession/longSessionPhase/confirmStillWorking. 앵커는 세션이 바뀌면 그 시작 시각, [confirmStillWorking] 이면 지금.
 * 근무 틱(ws·조립)이 [evaluate] 를 부르고, 배너는 [promptShownAt] 을 본다.
 */
class LongSessionPolicy(
    private val state: DesktopWorkState,
    private val autoClose: WorkAutoClose,
    private val rules: WorkPolicyRules = WorkPolicyRules.Standard,
) {
    sealed interface Phase {
        data class CountingDown(val anchor: SwiftDate) : Phase
        data class PromptOpen(val shownAt: SwiftDate) : Phase
    }

    private val prompt = MutableStateFlow<SwiftDate?>(null)
    val promptShownAt: StateFlow<SwiftDate?> = prompt.asStateFlow()
    private var anchorSessionId: String? = null
    var anchor: SwiftDate? = null
        private set

    private fun syncAnchor(snap: DesktopWorkSnapshot) {
        if (!snap.working) {
            anchorSessionId = null
            anchor = null
            prompt.value = null
            return
        }
        val id = WorkSessionIds.canonical(snap.sessionId)
        if (anchor == null || id != anchorSessionId) {
            anchorSessionId = id
            anchor = snap.startedAt
            prompt.value = null
        }
    }

    /** 흡수 세션의 '12시간'은 남의 기기가 잰 시간 — 배너도 띄우지 않는다(㉓, 유령 배너 방지). */
    fun phase(): Phase? {
        val snap = state.snapshot.value
        syncAnchor(snap)
        if (rules.excludesFromAutoClose(snap)) return null
        val a = anchor ?: return null
        val shown = prompt.value
        return if (shown != null) Phase.PromptOpen(shown) else Phase.CountingDown(a)
    }

    fun evaluate(now: SwiftDate) {
        when (val p = phase()) {
            null -> return
            is Phase.PromptOpen -> {
                if (now.timeIntervalSince(p.shownAt) <= WorkPolicyConstants.LONG_SESSION_RESPONSE_WINDOW_SECONDS) return
                val a = anchor ?: return
                autoClose.closeOwnedSessionLocally(
                    rules.longSessionEndedAt(a, now), AutoCloseReason.LONG_SESSION, WorkPolicyConstants.MESSAGE_LONG_SESSION,
                )
            }
            is Phase.CountingDown -> {
                if (now.timeIntervalSince(p.anchor) > WorkPolicyConstants.LONG_SESSION_THRESHOLD_SECONDS) prompt.value = now
            }
        }
    }

    /** 배너의 [네, 근무 중이에요] — 배너를 닫고 12시간을 지금부터 다시 센다. 배너가 없으면 아무것도 안 한다. */
    fun confirmStillWorking(now: SwiftDate) {
        if (prompt.value == null) return
        prompt.value = null
        anchor = now
    }
}
