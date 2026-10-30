// W2-g2 폴링 박자 — Swift Sources/check/WorkTimerStorePoke.swift 375-453(startPokePolling · localExpiryTick) · 456-475(주기·억제).
// 옮기지 않는 것: reportAppVersionIfNeeded(app_build PATCH 금지) · loadTokenUsagePrivacyIfNeeded(토큰 공개 — W2-h) · 운영자 신고 점(W-3 #14).
package com.yehsung.aingcheck.feature.desktop.poke

import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeConsumeGate
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeDrainer
import com.yehsung.aingcheck.feature.desktop.socialapi.RealtimeSubscription
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** 다른 갈래가 박자에 얹는 일(P10 순서 그대로 부른다). 집중 만료(W2-g4) → 지갑 periodic(W2-g4) → 그 밖(주간 근무 빚·케이크 선물…). */
class PokeBeatHooks(
    val focusExpiry: suspend (SwiftDate) -> Unit = {},
    val walletPeriodic: suspend (SwiftDate) -> Unit = {},
    val others: List<suspend (SwiftDate) -> Unit> = emptyList(),
) {
    companion object {
        val NONE: PokeBeatHooks = PokeBeatHooks()
    }
}

/**
 * 로그인 중 상시 도는 폴링. take_pokes 는 게이트([PokeConsumeGate] — P4)가 열렸을 때만 나간다.
 * [drainer] 가 null 이면(받는 쪽 싱크가 없어 조립하지 않았다) take_pokes 를 **부르지 않는다**.
 */
class DesktopPokePoller(
    private val host: SessionHost,
    private val clock: () -> SwiftDate,
    private val gate: PokeConsumeGate,
    private val drainer: PokeDrainer?,
    private val subscription: RealtimeSubscription,
    private val bubbles: DesktopMessageBubbleQueue,
    private val hooks: PokeBeatHooks = PokeBeatHooks.NONE,
) {
    private val lock = Any()
    private var loop: Job? = null

    /** ★ P11: 구독 여부는 [RealtimeSubscription.isSubscribed] **한 곳**에서 읽고, 주기와 억제를 둘 다 여기서 파생한다. */
    val pollIntervalSecondsNow: Double get() = DesktopPokeRules.pollIntervalSeconds(subscription.isSubscribed)
    val pollingIsPausedByRealtime: Boolean get() = DesktopPokeRules.pollingIsPausedByRealtime(subscription.isSubscribed)

    /** 시작(멱등). 첫 동작은 sleep 이다 — 시작 즉시 요청 0건. 주기는 매 반복 **앞**에서 다시 읽는다(자는 도중 깨워 재계산하지 않는다). */
    fun start(scope: CoroutineScope) {
        synchronized(lock) {
            if (loop != null) return
            loop = scope.launch {
                while (isActive) {
                    delay((pollIntervalSecondsNow * 1000).toLong())
                    if (!isActive) return@launch
                    pokeBeatStep { tick(clock()) }
                }
            }
        }
    }

    /** 로그아웃(clearPersistedSession 짝). */
    fun stop() {
        synchronized(lock) {
            loop?.cancel()
            loop = null
        }
    }

    /**
     * 폴링 1회분(P10). 세션이 없으면 요청 0건으로 빠진다. 순서: 메시지 만료 → 마지막 표시 만료 → 집중 만료 → 지갑 periodic →
     * 다른 갈래 훅 → 마지막에 게이트·take_pokes. 로컬 만료가 근무 게이트 **앞**인 것이 핵심이다(비근무 구간이 큐가 가장 오래 밀리는 구간).
     * 칸마다 [pokeBeatStep] 으로 따로 감싼다 — 한 칸이 던져도 남은 칸(특히 take_pokes)과 다음 박자는 돈다.
     */
    suspend fun tick(now: SwiftDate) {
        if (host.session == null) return
        pokeBeatStep { bubbles.expireStale(now) }
        pokeBeatStep { bubbles.expireLastShown(now) }
        pokeBeatStep { hooks.focusExpiry(now) }
        pokeBeatStep { hooks.walletPeriodic(now) }
        for (hook in hooks.others) pokeBeatStep { hook(now) }
        if (!pollingIsPausedByRealtime) pokeBeatStep { takePokesIfWorking(now) }
    }

    /** Swift `takePokesIfWorking` — 게이트 하나(P4)를 지나면 drain 몸을 직접 부른다. */
    suspend fun takePokesIfWorking(now: SwiftDate) {
        val d = drainer ?: return
        if (!gate.mayConsume(now)) return
        d.drainOnce()
    }
}

/**
 * 박자 한 칸. 취소만 다시 던지고 그 밖의 실패는 이 칸에서 끝낸다 — 다음 칸과 다음 박자는 돈다.
 * Swift 의 박자 함수(localExpiryTick 과 그 안의 훅)는 throws 가 아니라 폴링 루프가 끊길 수 없다(WorkTimerStorePoke.swift 378-386).
 * Kotlin suspend 람다는 던질 수 있어, 감싸지 않으면 한 번에 루프가 영구히 멈추고 조립 스코프가 SupervisorJob 이 아니면 앱 스코프까지
 * 취소한다 — ⚠️ "이 앱의 최악 실패 모드는 침묵이다"(449). 신고 점은 옮기지 않는다(W-3 #14 — Windows 1차 false).
 */
private inline fun pokeBeatStep(step: () -> Unit) {
    try {
        step()
    } catch (e: CancellationException) {
        throw e
    } catch (swallowed: Throwable) {
        // 삼킨다: 이 칸은 다음 박자(15/60초 뒤)에 다시 돈다.
    }
}
