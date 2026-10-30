// 원본: Sources/check/WorkTimerStoreRealtime.swift 1-507 전부 · 배선 Sources/check/WorkTimerStore.swift 2111-2118(근무 시작) ·
//       3335-3341(로그인) · 3396(팀 상태 되맞춤) · 2246(willSleep) · 4115-4144(로그아웃) · 4357-4381(깨어남 .didWake) @ c4e0ebfc
// 링(core/net RealtimeLink)과 전송자(RealtimeTransport)는 공용 그대로 쓴다 — 여기는 둘 사이에서 시각을 만들고 바깥을 부르는 유일한 층이다.
// 폰 PhoneRealtimeRunner 는 상속·복사하지 않는다(폰의 .drain 은 메시지 활동 조회 — 데스크톱은 take_pokes 게이트를 지난다).
package com.yehsung.aingcheck.feature.desktop.realtime

import com.yehsung.aingcheck.core.net.realtime.IdleReason
import com.yehsung.aingcheck.core.net.realtime.RealtimeEffect
import com.yehsung.aingcheck.core.net.realtime.RealtimeEvent
import com.yehsung.aingcheck.core.net.realtime.RealtimeLink
import com.yehsung.aingcheck.core.net.realtime.RealtimeLinkConstants
import com.yehsung.aingcheck.core.net.realtime.RealtimeState
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransport
import com.yehsung.aingcheck.core.session.RealtimeRefreshResult
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.socialapi.DesktopSocialLifecycle
import com.yehsung.aingcheck.feature.desktop.socialapi.DrainOutcome
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeConsumeGate
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeDrainer
import com.yehsung.aingcheck.feature.desktop.socialapi.RealtimeSubscription
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.ZoneId
import kotlin.coroutines.cancellation.CancellationException
import kotlin.random.Random

/**
 * 데스크톱 초인종 러너(Swift `RealtimeRuntime` + `WorkTimerStore` 의 Realtime 확장).
 *
 * 이 파일이 지키는 계약 셋(Swift 머리 7-9 — ★ R1):
 *  ① 링에게 시각을 주는 문은 [apply] 하나다(다른 곳에서 시계를 읽어 링에 넣지 않는다).
 *  ② effect 실행은 [run] 하나를 지난다.
 *  ③ take_pokes 로 가는 문은 [mayConsumePokes] 하나다(그 안의 판정은 찌르기 갈래의 [PokeConsumeGate] 한 벌 — P4).
 *
 * **단일 스레드 범위에서만 부른다**(앱은 Main — 전송자 `onEvent` 도 같은 범위에서 온다, RealtimeTransport.kt:19).
 *
 * @param drainer 찌르기 소비 몸(W2-g2). drainer 가 subscription(이 러너)을 받으므로 늦게 묶는다. **null 이면 소비하지 않는다** —
 *   받는 쪽 싱크가 없어 조립이 drainer 를 만들지 않은 판(poke.md §4 (6) · 위험 ①).
 * @param refreshForRealtime 조정자를 지나는 토큰 갱신(SessionStore.refreshForRealtime). 여기서 갱신 HTTP 를 직접 부르지 않는다.
 * @param runsTimers 벽시계 5초 티커를 띄우는가. 시험은 false 로 두고 [tick] 을 직접 부른다(Swift isRunningTests 가드).
 */
class DesktopRealtimeRunner(
    private val host: SessionHost,
    /** **기본값이 없다.** null = 실시간 없음(fail-closed — 시험 프로세스의 KtorRealtimeTransport.create 는 null). */
    val transport: RealtimeTransport?,
    private val gate: PokeConsumeGate,
    private val drainer: () -> PokeDrainer?,
    private val messages: DesktopRealtimeMessages,
    private val games: DesktopRealtimeGames,
    private val refreshForRealtime: suspend () -> RealtimeRefreshResult,
    private val scope: CoroutineScope,
    private val clock: () -> SwiftDate,
    private val runsTimers: Boolean = true,
    private val jitter: (Double) -> Double = DEFAULT_JITTER,
    private val zone: ZoneId = ZoneId.systemDefault(),
) : RealtimeSubscription, DesktopSocialLifecycle {

    /** 전송자가 없으면 링은 `idle(disabled)` 로 태어나 한 발짝도 움직이지 않는다(R6). */
    internal val link: RealtimeLink = RealtimeLink(transportAvailable = transport != null)

    private val _state = MutableStateFlow(link.state)

    /** 화면·폴링 억제가 읽는 값. **[apply] 에서만 쓴다**(R7). */
    val state: StateFlow<RealtimeState> = _state.asStateFlow()

    val diagnostics = DesktopRealtimeDiagnostics()

    private val _catchUpFailedAt = MutableStateFlow<SwiftDate?>(null)

    /** "놓친 찌르기를 못 받아왔어요" 경고 근거(Swift realtimeCatchUpFailedAt). */
    val catchUpFailedAt: StateFlow<SwiftDate?> = _catchUpFailedAt.asStateFlow()

    /**
     * 소비 게이트에 막혀 take_pokes 한 번을 빚지고 있는가(Swift catchUpDeferred).
     * ① 소비할 수 없는 동안 조인했다(따라잡기를 못 돌렸다) ② 소비할 수 없는 동안 `.drain` 이 울렸다.
     * 소비할 수 있게 되는 순간 **한 번만** 갚는다. 근무 시작 drain 이 갚고 지운다([clearCatchUpDebt]).
     */
    var catchUpDeferred: Boolean = false
        private set

    private var wired = false
    private var retryJob: Job? = null
    private var tokenRefreshJob: Job? = null
    private var tickJob: Job? = null
    private var catchUpJob: Job? = null
    private var readWindowJob: Job? = null

    // ------------------------------------------------------------------ RealtimeSubscription (핀 4)

    /** 구독 신호의 단일 읽기 지점(P11 — 폴링 주기·억제는 이 값에서 파생). */
    override val isSubscribed: Boolean get() = _state.value.isSubscribed

    override fun clearCatchUpDebt() {
        catchUpDeferred = false
    }

    // ------------------------------------------------------------------ DesktopSocialLifecycle (핀 5) — AppGraph 가 셋에 펼친다

    /** 로그인·활성화 지점(Swift startStatusRefreshLoop 의 startRealtimeIfPossible). ★ R2 소켓 기준은 로그인. */
    override fun onSignedIn() {
        startIfPossible()
    }

    /** Swift 4115-4119: 링을 내리고(realtimeState 는 apply 가 쓴다) 타이머를 전부 끈다. */
    override fun onSignedOut() {
        apply(RealtimeEvent.SignedOut)
        cancelTimers()
        _catchUpFailedAt.value = null
    }

    /**
     * Swift 2111-2118 의 실시간 몫: 빚을 지우고(근무 시작 drain 이 곧 따라잡기) 로그아웃 상태로 남은 링의 안전망.
     * **requestDrain 은 찌르기 갈래(W2-g2) 몫**이다 — 여기서도 부르면 근무 시작 한 번에 take_pokes 가 두 번 나간다.
     */
    override fun onWorkStarted() {
        clearCatchUpDebt()
        startIfPossible()
    }

    /** 꼬리 회수는 찌르기 갈래(P8). 실시간은 할 일이 없다. */
    override fun onUserStoppedWork(isTerminating: Boolean) {}

    override fun onLapCrossed(lap: Int) {}

    /** Swift reconcileRealtimeWithWorkState(3396) — 팀 상태가 반영된 직후 빚 되맞춤. 소켓은 올리고 내리지 않는다. */
    override fun onTeamStatusApplied() {
        resumeDeferredCatchUpIfPossible(clock())
    }

    /** Swift handleSleep(2246) — 근무 가드보다 **앞**(비근무 로그인 소켓도 뚜껑에 내려간다). */
    override fun onWillSleep(at: SwiftDate) {
        apply(RealtimeEvent.WillSleep, at)
    }

    /** Swift releaseWakeGate/flushWakeRejoinIfPending(4357-4381) — 깨움 게이트가 열린 뒤 한 번. */
    override fun onDidWake(at: SwiftDate) {
        apply(RealtimeEvent.DidWake, at)
    }

    // ------------------------------------------------------------------ 진입점

    /**
     * Swift startRealtimeIfPossible(132-147, idempotent). ★ R2: 기준은 로그인이다 — 근무에 다시 묶지 않는다.
     * 전송자가 없거나(R6) anon 키가 없으면 출발하지 않는다(소켓 URL 을 못 만들면 조인 타임아웃 → 재연결 빈 루프).
     * **로그아웃 상태의 링만** `signedIn` 을 받는다 — 붙어 있는 링에 넣으면 멀쩡한 구독을 끊고 다시 조인한다.
     */
    fun startIfPossible() {
        val active = host.session ?: return
        diagnostics.transportAvailable = transport != null
        val t = transport ?: return
        if (host.service.anonKey == null) return
        if (!wired) {
            wired = true
            t.onEvent = { event -> apply(RealtimeEvent.Transport(event)) }
            startTicker()
        }
        if (link.state != RealtimeState.Idle(IdleReason.signedOut)) return
        apply(RealtimeEvent.SignedIn(active.accessToken))
    }

    /**
     * ★ R1 ① 링에 사건을 넣고 나온 effect 를 실행한다. **링에 시각을 주는 유일한 문.** 실행한 effect 를 돌려준다(골든 재생·진단).
     */
    fun apply(event: RealtimeEvent, at: SwiftDate = clock()): List<RealtimeEffect> {
        val before = link.state
        val effects = link.apply(event, at, jitter)
        val after = link.state
        diagnostics.record(before, after, DesktopRealtimeDiagnostics.cause(event), at)
        // R7: 화면이 읽는 값은 여기서만 쓴다. `!=` 가드 — 5초 티커의 `.tick` 은 상태가 안 바뀌는 호출이 대부분이다.
        if (_state.value != after) _state.value = after
        run(effects, at)
        // ★ R5: 깨어남의 게임 조회는 **전송자가 없을 때만** — 있으면 이 didWake 가 곧 재조인이고 `.catchUp` 가지가 따라잡는다.
        if (event == RealtimeEvent.DidWake && transport == null) {
            for (g in games.inOrder) g.systemDidWake()
        }
        return effects
    }

    /** 주기 점검 1회분(Swift realtimeTick). 시험은 이것을 직접 부른다. */
    fun tick(at: SwiftDate = clock()) {
        apply(RealtimeEvent.Tick, at)
        // 안전망: 재시도 타이머가 사라졌는데 예약 시각이 지났으면 한 번 민다(없으면 링이 영구 reconnecting 으로 굳는다).
        val retryAt = link.retryAt
        if (retryJob == null && retryAt != null && at >= retryAt) apply(RealtimeEvent.BackoffElapsed, at)
        // 게이트에 막혀 건너뛴 따라잡기를 회수 — 판정은 되맞춤과 같은 함수 하나.
        resumeDeferredCatchUpIfPossible(at)
    }

    /**
     * ★ R1 ③ 초인종·따라잡기가 take_pokes 로 갈 수 있는가. **게이트는 여기 하나다**(P4 — 판정 본체는 PokeConsumeGate).
     * 받는 쪽이 없어 drainer 가 조립되지 않았으면 언제나 거짓.
     */
    fun mayConsumePokes(now: SwiftDate): Boolean = drainer() != null && gate.mayConsume(now)

    /** 설정 화면 한 줄(Swift realtimeDiagnosticsLine). */
    val diagnosticsLine: String
        get() = DesktopRealtimeDiagnostics.line(_state.value, diagnostics, _catchUpFailedAt.value, zone)

    /** 앱 종료 — 티커까지 전부 내린다(로그아웃은 [onSignedOut]). */
    fun shutdown() {
        cancelTimers()
        tickJob?.cancel()
        tickJob = null
        transport?.disconnect()
    }

    // ------------------------------------------------------------------ 빚

    /** ★ R4 빚 상환 조건 넷: 구독 중 · 빚 있음 · 소비 게이트 열림 · 도는 따라잡기 없음. */
    private fun resumeDeferredCatchUpIfPossible(now: SwiftDate) {
        if (!_state.value.isSubscribed || !catchUpDeferred || catchUpJob != null) return
        if (!mayConsumePokes(now)) return
        startCatchUp()
    }

    // ------------------------------------------------------------------ effect 실행

    /** ★ R1 ② effect 실행의 유일한 문. */
    private fun run(effects: List<RealtimeEffect>, now: SwiftDate) {
        for (effect in effects) {
            when (effect) {
                is RealtimeEffect.Connect -> performConnect(effect.accessToken)
                RealtimeEffect.Disconnect -> transport?.disconnect()
                is RealtimeEffect.ScheduleRetry -> scheduleRetry(effect.at, now)
                RealtimeEffect.CancelRetry -> {
                    retryJob?.cancel()
                    retryJob = null
                }
                RealtimeEffect.CatchUp -> {
                    startCatchUp()
                    // ★ R5: 게임 따라잡기는 조회라 소비 게이트를 지나지 않는다(브로드캐스트엔 재생이 없다).
                    for (g in games.inOrder) g.realtimeDidJoin()
                }
                RealtimeEffect.Drain -> {
                    // ★ R3: 게이트가 닫혔으면 take_pokes 를 부르지 않는다 — 서버 표만 읽고 빚을 적는다(남의 기기 찌르기를 훔치지 않는다).
                    if (!mayConsumePokes(now)) {
                        catchUpDeferred = true
                        messages.requestActivityRefresh()
                    } else {
                        drainer()?.requestDrain()
                    }
                }
                RealtimeEffect.MessageReadSignal -> requestReadRefreshCoalesced()
                RealtimeEffect.GomokuSignal -> games.gomoku?.handleSignal()
                RealtimeEffect.ChessSignal -> games.chess?.handleSignal()
                RealtimeEffect.TetrisSignal -> games.tetris?.handleSignal()
                // 확성기 배너(2026-10-30)는 아직 데스크톱 화면이 없다(데스크톱 세션 몫) — 같은 묶음의 `ring` 이 메시지를 갚는다.
                RealtimeEffect.MegaphoneSignal -> Unit
                is RealtimeEffect.PushAccessToken -> transport?.pushAccessToken(effect.token)
                is RealtimeEffect.ScheduleTokenRefresh -> scheduleTokenRefresh(effect.at, now)
                is RealtimeEffect.RefreshToken -> startTokenRefresh()
                RealtimeEffect.SendHeartbeat -> transport?.sendHeartbeat()
            }
        }
    }

    /**
     * 프로젝트 URL·anon 키는 조립된 서비스에서 읽는다(소켓과 REST 가 다른 프로젝트를 보지 않게).
     * ★ R6 경합 2: 링이 실어 온 토큰이 아니라 **지금 세션의 토큰**으로 붙는다(백오프 동안 갱신됐을 수 있다). 다르면 진단에 남긴다.
     */
    private fun performConnect(linkToken: String) {
        val t = transport ?: return
        val active = host.session ?: return
        val apiKey = host.service.anonKey ?: return
        val token = active.accessToken
        if (token != linkToken) diagnostics.note("token-superseded", link.state, clock())
        // private = true 가 없으면 realtime.messages RLS 가 상담되지 않는다.
        t.connect(host.service.projectURL, apiKey, token, RealtimeLinkConstants.pokeChannel(active.userID), isPrivate = true)
    }

    private fun scheduleRetry(at: SwiftDate, now: SwiftDate) {
        retryJob?.cancel()
        val delayMillis = millis(at.timeIntervalSince(now))
        val job = scope.launch {
            if (delayMillis > 0) delay(delayMillis)
            retryJob = null
            apply(RealtimeEvent.BackoffElapsed)
        }
        retryJob = job
    }

    private fun scheduleTokenRefresh(at: SwiftDate, now: SwiftDate) {
        tokenRefreshJob?.cancel()
        val delayMillis = millis(at.timeIntervalSince(now))
        tokenRefreshJob = scope.launch {
            if (delayMillis > 0) delay(delayMillis)
            tokenRefreshJob = null
            startTokenRefresh()
        }
    }

    /**
     * 선제·강제 토큰 갱신 — **반드시 조정자를 지난다**(SessionStore.refreshForRealtime). 세대가 바뀌었거나 stale 이면 버린다
     * (옛 링의 결과를 새 세션 링에 넣으면 막 붙은 소켓을 내린다). 세션 스토어의 onAccessTokenChanged 가 이미 넣었으면(링 토큰이 같다) 다시 넣지 않는다.
     */
    private fun startTokenRefresh() {
        val current = host.session ?: return
        if (current.refreshToken == null) return
        val generation = host.sessionGeneration
        scope.launch {
            val result = try {
                refreshForRealtime()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RealtimeRefreshResult.Failed(fatal = false, stale = false)
            }
            if (generation != host.sessionGeneration) return@launch
            when (result) {
                is RealtimeRefreshResult.Refreshed ->
                    if (link.accessToken != result.accessToken) apply(RealtimeEvent.TokenRefreshed(result.accessToken))
                is RealtimeRefreshResult.Failed ->
                    if (!result.stale) apply(RealtimeEvent.TokenRefreshFailed(result.fatal))
            }
        }
    }

    /** 벽시계 티커(5초 — 실시간 하트비트 눈금보다 촘촘해야 한다). 시험(runsTimers=false)에서는 띄우지 않는다. */
    private fun startTicker() {
        if (!runsTimers) return
        tickJob?.cancel()
        tickJob = scope.launch {
            while (isActive) {
                delay(millis(TICK_INTERVAL_SECONDS))
                tick()
            }
        }
    }

    /** 로그아웃에서 부른다. 타이머 하나라도 남기면 다음 계정 세션에 옛 사건이 흘러든다. */
    private fun cancelTimers() {
        catchUpDeferred = false
        retryJob?.cancel()
        retryJob = null
        tokenRefreshJob?.cancel()
        tokenRefreshJob = null
        catchUpJob?.cancel()
        catchUpJob = null
        readWindowJob?.cancel()
        readWindowJob = null
    }

    // ------------------------------------------------------------------ 읽음 신호 1초 창

    /** R7: 읽음 신호는 1초 창으로 합친다 — 창이 열려 있으면 그 창에 얹고, 닫히면 한 번 부른다. 로그아웃·계정 전환 뒤 깬 창은 쏘지 않는다. */
    private fun requestReadRefreshCoalesced() {
        if (host.session == null) return
        messages.readSignalArrived()
        if (readWindowJob != null) return
        val generation = host.sessionGeneration
        readWindowJob = scope.launch {
            delay(millis(READ_SIGNAL_COALESCE_SECONDS))
            readWindowJob = null
            if (generation != host.sessionGeneration) return@launch
            messages.readSignalWindowClosed()
        }
    }

    // ------------------------------------------------------------------ 따라잡기

    private fun startCatchUp() {
        catchUpJob?.cancel()
        val job = scope.launch { catchUpAfterSubscribe() }
        catchUpJob = job
        job.invokeOnCompletion { if (catchUpJob === job) catchUpJob = null }
    }

    /**
     * 구독 직후 1회 따라잡기(Swift catchUpAfterSubscribe 403-449). 폴백이 아니라 정확성이다 — 브로드캐스트엔 재생이 없어서
     * 소켓이 닫혀 있던 동안의 찌르기는 take_pokes 로만 온다. 시도 3회, 사이 간격 1·2초.
     */
    private suspend fun catchUpAfterSubscribe() {
        if (!mayConsumePokes(clock())) {
            // 소비할 수 없는 기기 — take_pokes 를 부르지 않고 빚을 적는다. 경고도 세우지 않는다(로그인만 한 기기 전부가 띄우게 된다).
            catchUpDeferred = true
            _catchUpFailedAt.value = null
            diagnostics.lastCatchUpAttempts = 0
            messages.requestActivityRefresh()
            return
        }
        catchUpDeferred = false
        // 근무 중 조인도 서버 표를 한 번 읽는다(소켓이 끊긴 동안의 메시지·읽음은 재생되지 않는다). 기다리지 않는다.
        messages.requestActivityRefresh()
        for (attempt in 0 until CATCH_UP_ATTEMPTS) {
            diagnostics.lastCatchUpAttempts = attempt + 1
            val body = drainer() ?: return
            when (val outcome = body.drainOnce()) {
                is DrainOutcome.Ok -> {
                    diagnostics.lastCatchUpAt = clock()
                    diagnostics.lastCatchUpCount = outcome.count
                    diagnostics.lastCatchUpFailure = null
                    _catchUpFailedAt.value = null
                    return
                }
                is DrainOutcome.Failed -> diagnostics.lastCatchUpFailure = outcome.reason
            }
            if (attempt < CATCH_UP_RETRY_DELAYS_SECONDS.size) delay(millis(CATCH_UP_RETRY_DELAYS_SECONDS[attempt]))
        }
        val failedAt = clock()
        diagnostics.lastCatchUpAt = failedAt
        _catchUpFailedAt.value = failedAt
    }

    companion object {
        /** 따라잡기 시도 횟수(take_pokes 1회 = 최대 2요청 × 15초 — wake 직후 최악 90초에서 끊는다). */
        const val CATCH_UP_ATTEMPTS: Int = 3

        /** 시도 **사이** 간격만(마지막 실패 뒤 대기는 아무도 기다리지 않는 순수 지연이라 뺐다). */
        val CATCH_UP_RETRY_DELAYS_SECONDS: List<Double> = listOf(1.0, 2.0)

        /** 링에 `.tick` 을 넣는 주기 — RealtimeLinkConstants 의 실시간 하트비트 주기보다 촘촘해야 한다. */
        const val TICK_INTERVAL_SECONDS: Double = 5.0

        /** 읽음 신호 합치기 창(Swift messageReadSignalCoalesceSeconds). */
        const val READ_SIGNAL_COALESCE_SECONDS: Double = 1.0

        /** full jitter — 링은 순수하므로 난수는 주입이다. */
        val DEFAULT_JITTER: (Double) -> Double = { ceiling -> if (ceiling <= 0) 0.0 else Random.nextDouble(0.0, ceiling) }

        private fun millis(seconds: Double): Long = (maxOf(0.0, seconds) * 1000.0).toLong()
    }
}
