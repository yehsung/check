// 원본: Sources/check/CheckWorkNudge.swift 24-190(NudgeScheduler — 상수 60/120/5분/10분/1h/재무장 1h)
//       · Sources/check/WorkTimerStore.swift 1944-1952·2212-2240(수동 종료 억제 · 생존 스탬프 · 실행 시 재무장)
//       · Sources/check/CheckOverlayWindow.swift 496-505·660-675(넛지 자격 · nudgeAutoStart — 재개 먼저, 그다음 시작) @ a90d8623
// W2-g6(wp) 넛지(자동 근무 시작). 입력 배선(Raw Input → IdleSource)·세션 이벤트 실물은 W3-d 가 주입한다.
package com.yehsung.aingcheck.feature.desktop.work.nudge

import com.yehsung.aingcheck.core.foundation.platform.desktop.IdleSource
import com.yehsung.aingcheck.core.foundation.platform.desktop.InputKind
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvents
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkState
import com.yehsung.aingcheck.feature.desktop.work.WorkEvent
import com.yehsung.aingcheck.feature.desktop.work.WorkEventSink
import com.yehsung.aingcheck.feature.desktop.work.WorkStartOrigin
import com.yehsung.aingcheck.feature.desktop.work.policy.RecentAutoCloseResume
import com.yehsung.aingcheck.feature.desktop.work.policy.TerminationFlag
import com.yehsung.aingcheck.feature.desktop.work.policy.WorkPolicyRules
import com.yehsung.aingcheck.feature.desktop.work.policy.toSwiftDate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.roundToLong
import kotlin.time.ExperimentalTime

/** 마지막 의미 있는 입력 후 경과 초. 관측이 없으면 무한대(Swift `.min() ?? .infinity`). ㉔ 기본 종류에 MOVE 는 없다. */
@OptIn(ExperimentalTime::class)
fun meaningfulIdleSeconds(
    idle: IdleSource,
    now: SwiftDate,
    kinds: Set<InputKind> = WorkPolicyRules.Standard.meaningfulInputKinds,
): Double {
    val last = idle.lastInput(kinds) ?: return Double.POSITIVE_INFINITY
    return maxOf(0.0, now.timeIntervalSince(last.toSwiftDate()))
}

/**
 * 이 세션이 지금 사람 앞에 있는가(㉔ · D§5-1). 잠금·비콘솔·로그오프면 거짓, RDP 연결은 **쓰는 것**으로 친다. 판정 불가(시작)는 참(fail-open).
 */
class SessionUsability {
    private var locked = false
    private var console = true
    private var remote = false
    private var loggedOff = false

    val isUsable: Boolean get() = !locked && !loggedOff && (console || remote)

    fun on(event: SessionEvent) {
        when (event) {
            SessionEvent.LOCK -> locked = true
            SessionEvent.UNLOCK -> locked = false
            SessionEvent.CONSOLE_CONNECT -> console = true
            SessionEvent.CONSOLE_DISCONNECT -> console = false
            SessionEvent.REMOTE_CONNECT -> remote = true
            SessionEvent.REMOTE_DISCONNECT -> remote = false
            SessionEvent.LOGOFF -> loggedOff = true
        }
    }

    fun attach(events: SessionEvents): Registration = events.addListener { on(it) }
}

/**
 * 넛지 판정기(Swift NudgeScheduler). "최근 10분 안에 실제 사용 5분"이면 발동, 발동 뒤 1시간 쉼. 잠금·비콘솔이면 적립하지 않는다.
 * [tick] 은 주입 시계·idle 로 결정적이고, [start] 의 루프가 60초마다 부른다(시험은 직접 부른다).
 */
class NudgeScheduler(
    private val idleSeconds: () -> Double,
    private val clock: () -> SwiftDate,
    private val isEligible: () -> Boolean,
    private val onNudge: () -> Unit,
    private val isSessionUsable: () -> Boolean = { true },
    private val onAbsenceGap: () -> Unit = {},
    private val onAliveTick: (SwiftDate) -> Unit = {},
) {
    private val active = ArrayList<SwiftDate>()
    val activeTickTimes: List<SwiftDate> get() = active.toList()
    val activeMinutes: Int get() = active.size

    /** 이 시각 전까지는 세지 않는다. null = 과거(Swift .distantPast). */
    var cooldownUntil: SwiftDate? = null
        private set
    private var lastTickAt: SwiftDate? = null
    private var loop: Job? = null

    /** 루프를 켠다(멱등). 꺼져 있던 구간(근무 중)을 공백으로 오인하지 않게 간격 측정을 처음부터 시작한다. */
    fun start(scope: CoroutineScope) {
        if (loop != null) return
        lastTickAt = null
        loop = scope.launch {
            while (isActive) {
                delay((CHECK_INTERVAL_SECONDS * 1000).toLong())
                tick()
            }
        }
    }

    fun stop() {
        loop?.cancel()
        loop = null
        active.clear()
    }

    fun tick() {
        val now = clock()
        val last = lastTickAt
        if (last != null && now.timeIntervalSince(last) >= REARM_GAP_SECONDS) onAbsenceGap()
        if (idleSeconds() >= REARM_GAP_SECONDS) onAbsenceGap()
        lastTickAt = now
        onAliveTick(now)
        if (!isEligible()) {
            active.clear()
            return
        }
        val cool = cooldownUntil
        if (cool != null && now < cool) return
        if (!isSessionUsable()) return
        if (idleSeconds() < ACTIVE_IDLE_THRESHOLD_SECONDS) active.add(now)
        active.removeAll { now.timeIntervalSince(it) > ACTIVE_WINDOW_SECONDS }
        if (active.size >= REQUIRED_ACTIVE_MINUTES) {
            active.clear()
            cooldownUntil = now.addingTimeInterval(COOLDOWN_SECONDS)
            onNudge()
        }
    }

    /** 깨어남 — 활성 누적을 0 으로("켜진 지 5분"의 의미 보존). */
    fun handleWake() {
        active.clear()
    }

    /** 근무 → 비근무 실전이(서버·자동 마감)에서 쿨다운을 즉시 만료한다. 적립은 건드리지 않는다. */
    fun resetCooldown() {
        cooldownUntil = null
    }

    companion object {
        const val CHECK_INTERVAL_SECONDS: Double = 60.0
        const val ACTIVE_IDLE_THRESHOLD_SECONDS: Double = 120.0
        const val REQUIRED_ACTIVE_MINUTES: Int = 5
        const val ACTIVE_WINDOW_SECONDS: Double = 10 * 60.0
        const val COOLDOWN_SECONDS: Double = 3600.0
        const val REARM_GAP_SECONDS: Double = 60 * 60.0
    }
}

/**
 * 수동 [근무 종료]의 자동 시작 억제(1시간 부재로 재무장). 자동 마감(잠자기·12h·away)은 억제하지 않는다 — 사용자 의사가 아니다.
 * ⑰ 종료 시퀀스([TerminationFlag])면 심지 않는다. 키는 Swift 와 같다(값 표현은 데스크톱 KeyValueStore — 시각은 epoch ms).
 */
class AutoStartSuppression(
    private val store: DesktopKeyValueStore,
    private val termination: TerminationFlag,
) {
    var isSuppressed: Boolean = store.getBoolean(SUPPRESSED_KEY) == true
        private set

    /** 실행 시 재무장 — 앱이 꺼져 있던 시간은 마지막 생존 스탬프와의 차이로만 잴 수 있다. */
    fun restoreOnLaunch(now: SwiftDate) {
        isSuppressed = store.getBoolean(SUPPRESSED_KEY) == true
        val lastAlive = store.getLong(LAST_ALIVE_KEY)?.let(SwiftDate::fromEpochMillis) ?: return
        if (isSuppressed && now.timeIntervalSince(lastAlive) >= NudgeScheduler.REARM_GAP_SECONDS) clear()
    }

    /** ws 의 수동 stop() 이 부른다. 심었으면 true. */
    fun onManualStop(now: SwiftDate): Boolean {
        if (termination.isTerminating) return false
        isSuppressed = true
        store.putBoolean(SUPPRESSED_KEY, true)
        store.putLong(LAST_ALIVE_KEY, now.epochMillis())
        return true
    }

    /** 해제(멱등). 수동 [근무 시작] · 1시간+ 공백 · 재무장. */
    fun clear() {
        if (!isSuppressed) return
        isSuppressed = false
        store.remove(SUPPRESSED_KEY)
    }

    /** 스케줄러의 매 tick 생존 스탬프. 억제 중일 때만 영속한다. */
    fun recordAlive(now: SwiftDate) {
        if (!isSuppressed) return
        store.putLong(LAST_ALIVE_KEY, now.epochMillis())
    }

    companion object {
        const val SUPPRESSED_KEY: String = "check.nudge.autoStartSuppressed"
        const val LAST_ALIVE_KEY: String = "check.nudge.lastAliveAt"

        private fun SwiftDate.epochMillis(): Long = (timeIntervalSince1970 * 1000).roundToLong()
    }
}

enum class NudgeAction { NONE, RESUMED, STARTED }

/**
 * 넛지 발동 → 자동 근무 시작(Swift nudgeAutoStart). 자격 = 로그인 · 팀 있음 · 비근무 · 억제 아님 · **설정 켬**(설정 끔이면 시작·재개 둘 다 0).
 * ★ 새 세션을 만들기 **전에** 30분 재개 대상을 본다 — 순서가 뒤바뀌면 세션이 둘이 되거나 재개가 조용히 죽는다.
 */
class NudgeAutoStarter(
    private val state: DesktopWorkState,
    private val isSignedIn: () -> Boolean,
    private val hasTeam: () -> Boolean,
    private val suppression: AutoStartSuppression,
    private val autoWorkStartEnabled: () -> Boolean,
    private val startWork: (WorkStartOrigin) -> Unit,
    private val resumeRecentlyClosed: () -> Unit,
    private val clock: () -> SwiftDate,
    private val events: WorkEventSink = WorkEventSink.NONE,
) {
    val isEligible: Boolean
        get() = isSignedIn() && hasTeam() && !state.snapshot.value.isWorking && !suppression.isSuppressed && autoWorkStartEnabled()

    fun fire(): NudgeAction {
        if (!isEligible) return NudgeAction.NONE
        events.onWorkEvent(WorkEvent.NudgeStarted)
        if (RecentAutoCloseResume.canResume(state.snapshot.value, clock())) {
            resumeRecentlyClosed()
            return NudgeAction.RESUMED
        }
        startWork(WorkStartOrigin.NUDGE)
        return NudgeAction.STARTED
    }

    /** 이 시작기에 물린 판정기(자격·발동·공백 재무장·생존 스탬프를 잇는다). */
    fun scheduler(idleSeconds: () -> Double, isSessionUsable: () -> Boolean): NudgeScheduler =
        NudgeScheduler(
            idleSeconds = idleSeconds,
            clock = clock,
            isEligible = { isEligible },
            onNudge = { fire() },
            isSessionUsable = isSessionUsable,
            onAbsenceGap = { suppression.clear() },
            onAliveTick = { suppression.recordAlive(it) },
        )
}
