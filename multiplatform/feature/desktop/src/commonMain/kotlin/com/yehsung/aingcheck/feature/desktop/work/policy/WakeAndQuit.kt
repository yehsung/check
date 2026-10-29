// 원본: Sources/check/WorkTimerStore.swift 4295-4385(깨움 결합 게이트 · 상한 10초) · 2019-2045(finishWorkBeforeQuit 3초 + awaitFirst) @ a90d8623
// W2-g6(wp) 깨움 게이트 · 종료 3초. 네트워크 관측자·shutdown hook 실물은 W3-d·조정자(Main.kt) 가 주입한다.
package com.yehsung.aingcheck.feature.desktop.work.policy

import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkState
import com.yehsung.aingcheck.feature.desktop.work.WorkQueue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * 깨어난 직후 모든 루프가 동시에 만료돼 Wi-Fi 가 붙기도 전에 요청이 폭주하던 것을 막는 결합 게이트(v0.2.38 M7).
 * [begin] 은 handleWake 의 **맨 앞**(⚠️⑳)에서 부른다. 결합 확인 또는 상한(10초) 중 먼저 오는 쪽에서 [onRelease] — 영구 대기 금지.
 * 관측자가 없으면(시험 기본·주입 안 함) 게이트 없이 즉시 [onRelease]. 큐(WorkQueueHost.awaitWakeGate)는 [await] 를 기다린다.
 */
class WakeGate(
    private val scope: CoroutineScope,
    private val waitUntilSatisfied: (suspend () -> Unit)?,
    private val timeoutMillis: Long = (WorkPolicyConstants.WAKE_GATE_TIMEOUT_SECONDS * 1000).toLong(),
    private val onRelease: (satisfied: Boolean) -> Unit = {},
) {
    private var job: Job? = null

    val isHolding: Boolean get() = job?.isActive == true

    fun begin() {
        // 앞선 게이트가 안 열렸으면(연속 깨움) 버리고 새로 센다 — 두 게이트가 각자 루프를 되살리면 본문이 두 번 돈다.
        job?.cancel()
        val waiter = waitUntilSatisfied
        if (waiter == null) {
            job = null
            onRelease(true)
            return
        }
        job = scope.launch {
            val satisfied = withTimeoutOrNull(timeoutMillis) {
                waiter()
                true
            } ?: false
            onRelease(satisfied)
        }
    }

    /** 서 있는 게이트가 열릴 때까지(없으면 즉시). 기다리는 사이 새 게이트로 바뀌면 그것까지 기다린다. */
    suspend fun await() {
        while (true) {
            val current = job ?: return
            current.join()
            if (job === current) return
        }
    }
}

/** 종료 시퀀스 표식(Swift isTerminating). 표식이 서면 수동 종료 억제를 심지 않는다(⑰). */
class TerminationFlag {
    var isTerminating: Boolean = false
        private set

    fun markTerminating() {
        isTerminating = true
    }
}

enum class QuitOutcome { SKIPPED, DRAINED, TIMED_OUT }

/**
 * 앱 종료 직전 근무 마무리(Swift finishWorkBeforeQuit). 로그인·근무 중이 아니거나 **흡수 세션이면 요청 0**(㉓ — 이 기기를 끄는 것이
 * 저쪽 근무를 끝내지 않는다). 근무 중이면 stop(큐 Stop) 뒤 큐가 비거나 3초 중 먼저 오는 쪽까지만 기다린다. 진 쪽은 취소하지 않는다
 * (큐의 드레인은 큐 자신의 수명에서 돈다 — 여기서 거두는 것은 기다림뿐).
 */
class QuitFinisher(
    private val state: DesktopWorkState,
    private val isSignedIn: () -> Boolean,
    private val termination: TerminationFlag,
    private val stop: () -> Unit,
    private val queue: WorkQueue,
    private val timeoutMillis: Long = (WorkPolicyConstants.QUIT_TIMEOUT_SECONDS * 1000).toLong(),
) {
    suspend fun finishWorkBeforeQuit(): QuitOutcome {
        // 가드보다 앞 — 이 함수에 들어온 시점이 곧 종료 시퀀스 진입이다.
        termination.markTerminating()
        val snap = state.snapshot.value
        if (!isSignedIn() || !snap.working || snap.adopted) return QuitOutcome.SKIPPED
        stop()
        val drained = withTimeoutOrNull(timeoutMillis) {
            queue.awaitIdle(timeoutMillis)
            true
        } ?: false
        return if (drained) QuitOutcome.DRAINED else QuitOutcome.TIMED_OUT
    }
}
