// 원본: Sources/CheckMobileKit/Realtime/MobileRealtimeRunner.swift @ 3bd04bd
package com.yehsung.aingcheck.feature.phone.realtime

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.realtime.IdleReason
import com.yehsung.aingcheck.core.net.realtime.RealtimeEffect
import com.yehsung.aingcheck.core.net.realtime.RealtimeEvent
import com.yehsung.aingcheck.core.net.realtime.RealtimeLink
import com.yehsung.aingcheck.core.net.realtime.RealtimeLinkConstants
import com.yehsung.aingcheck.core.net.realtime.RealtimeState
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransport
import com.yehsung.aingcheck.core.session.RealtimeRefreshResult
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.random.Random

/** 실시간 핸들러 등록 증표. [cancel] 하면 핸들러가 빠진다(Swift `MobileRealtimeRegistration`). */
class PhoneRealtimeRegistration internal constructor(private var cancelAction: (() -> Unit)?) {
    fun cancel() {
        cancelAction?.invoke()
        cancelAction = null
    }
}

/**
 * 실시간 신호를 받는 게임 스토어 문(Swift `realtime.gomoku` · `realtime.tetris` 약참조 칸). 조립이 오목·테트리스 스토어로 잇는다 —
 * `handleSignal` 은 **직렬화된 재조회 한 번**(도는 중이면 뒤따르는 한 번으로 합친다), `realtimeDidJoin` 은 조인 직후 따라잡기.
 */
interface RealtimeSignalReceiver {
    fun handleSignal()
    fun realtimeDidJoin()
}

/**
 * 폰의 실시간 **effect 실행층**(SPEC-ios §3.3 · ios-inventory §7 · E§7.2). 링([RealtimeLink])과 소켓([RealtimeTransport] — Ktor+OkHttp
 * WebSocket, supabase-kt 금지 §8-1 #14)은 코어 것을 그대로 쓰고, effect 를 실행하는 층만 여기 있다. 맥(데스크톱 W2-g)과 갈리는 곳은 넷이다:
 *  1. `.catchUp`·`.drain` → **take_pokes 가 아니다**(C§4 #15, G §2-3 W2-f ②). 등록된 [onMessageActivity] 핸들러들을 1초 창에 모아 한 번 부른다
 *     (+ `.catchUp` 은 오목·테트리스 `realtimeDidJoin`). take_pokes 는 원자 소비라 폰이 부르면 맥의 말풍선을 훔친다(R3).
 *  2. `.messageReadSignal` → 등록된 [onMessageRead] 핸들러들(같은 1초 합치기).
 *  3. `.gomokuSignal` → 오목 `handleSignal()` · `.tetrisSignal` → 테트리스 `handleSignal()`. `.chessSignal` 은 **일부러 빈 가지**다(아래).
 *  4. 연결은 **앱이 active 이고 로그인 상태일 때만**. background 로 가면 `.willSleep` 으로 내려놓는다.
 * 토큰 갱신은 세션 스토어의 조정자를 지난다([SessionStore.refreshForRealtime]) — 갱신 주체가 둘이 되지 않게.
 *
 * 실행 규약(Swift `@MainActor`): 한 디스패처에서 부른다. 타이머는 [scope] 에서 돈다(시험은 가상 시간, [runsTimers] 를 끄고 [tick] 을 직접).
 */
class PhoneRealtimeRunner(
    private val service: SupabaseWorkService,
    val transport: RealtimeTransport?,
    private val clock: SessionClock,
    private val scope: CoroutineScope,
    /** 벽시계 타이머(주기 점검 · 토큰 선제 갱신)를 띄울지. 시험은 false 로 두고 [tick] 을 직접 부른다. */
    var runsTimers: Boolean = true,
    private val jitter: (Double) -> Double = { ceiling -> if (ceiling <= 0) 0.0 else Random.nextDouble(0.0, ceiling) },
) {
    private var link: RealtimeLink = RealtimeLink(transportAvailable = transport != null && service.anonKey != null)

    /** 화면이 읽는 링 상태(진단 · 오목 폴링 간격). */
    var state: RealtimeState by mutableStateOf(link.state)
        private set

    private var session: SessionStore? = null

    /** 오목 신호를 받을 스토어(조립이 붙인다). */
    var gomoku: RealtimeSignalReceiver? = null

    /** 테트리스 대결 신호를 받을 스토어(조립이 붙인다 — 오목 칸과 같은 꼴·같은 자리). */
    var tetris: RealtimeSignalReceiver? = null

    /** 확성기 배너 신호('megaphone')를 받을 자리(조립이 붙인다 — 배너 스토어 refresh). 비어 있으면 아무 일도 안 한다(같은 묶음의 ring 이 메시지를 갚는다). */
    var megaphone: (() -> Unit)? = null

    /** 메시지 활동(`.drain`·`.catchUp`)·읽음 신호를 모으는 창(초). 시험은 크게 두고 [flushCoalescedSignals] 를 직접 부른다. */
    var coalesceSeconds: Double = 1.0

    /** 주기 점검(`.tick`) 간격. 하트비트(25초)보다 촘촘해야 한다(맥과 같은 5초). */
    var tickIntervalSeconds: Double = 5.0

    private val activityHandlers = LinkedHashMap<Long, () -> Unit>()
    private val readHandlers = LinkedHashMap<Long, () -> Unit>()
    private var nextHandlerID = 0L
    private var pendingActivity = false
    private var pendingRead = false
    private var coalesceJob: Job? = null
    private var retryJob: Job? = null
    private var tokenRefreshJob: Job? = null
    private var tickJob: Job? = null
    private var wired = false

    var isAppActive: Boolean = false
        private set

    /** 실행한 effect 기록(최근 50개 — 시험·진단). 네트워크 경로의 증거는 스텁이 받은 요청이다. */
    private val effects = ArrayList<RealtimeEffect>()
    val effectLog: List<RealtimeEffect> get() = effects.toList()

    /** 핸들러를 실제로 부른 횟수(합치기 증거). */
    var activityFlushCount: Int = 0
        private set
    var readFlushCount: Int = 0
        private set

    fun attach(session: SessionStore) {
        this.session = session
    }

    // ---------------------------------------------------------------- 핸들러 등록(탭 스토어 · 조립이 부른다)

    /** `.drain`(새 메시지 신호) · `.catchUp`(조인 직후 따라잡기)마다 — 1초 창에 모아 한 번. 메시지 탭: 요약 + 보이는 대화 이력 재조회. **take_pokes 금지.** */
    fun onMessageActivity(handler: () -> Unit): PhoneRealtimeRegistration {
        val id = nextHandlerID++
        activityHandlers[id] = handler
        return PhoneRealtimeRegistration { activityHandlers.remove(id) }
    }

    /** 읽음 신호(`message_read`)마다 — 1초 창에 모아 한 번. */
    fun onMessageRead(handler: () -> Unit): PhoneRealtimeRegistration {
        val id = nextHandlerID++
        readHandlers[id] = handler
        return PhoneRealtimeRegistration { readHandlers.remove(id) }
    }

    // ---------------------------------------------------------------- 수명(앱 모델이 부른다)

    fun appDidBecomeActive() {
        isAppActive = true
        connectIfPossible()
    }

    fun appDidEnterBackground() {
        isAppActive = false
        stopTicker()
        apply(RealtimeEvent.WillSleep)
        // 모아 둔 신호는 버린다 — active 로 돌아오면 조인 따라잡기(`.catchUp`)와 각 스토어의 appDidBecomeActive 가 다시 읽는다.
        coalesceJob?.cancel()
        coalesceJob = null
        pendingActivity = false
        pendingRead = false
    }

    fun sessionDidSignIn() {
        connectIfPossible()
    }

    fun sessionDidSignOut() {
        apply(RealtimeEvent.SignedOut)
        cancelTimers()
    }

    /** 다른 경로(401 재시도)가 토큰을 갱신했다 — 붙어 있으면 채널에 새 토큰을 민다(재연결하지 않는다). */
    fun accessTokenDidChange(token: String) {
        apply(RealtimeEvent.TokenRefreshed(token))
    }

    private fun connectIfPossible() {
        val store = session ?: return
        val current = store.session
        if (!isAppActive || current == null || !store.isSignedIn) return
        wireTransportIfNeeded()
        val s = link.state
        if (s is RealtimeState.Idle) {
            when (s.reason) {
                IdleReason.signedOut -> apply(RealtimeEvent.SignedIn(current.accessToken))
                IdleReason.suspended -> apply(RealtimeEvent.DidWake)
                IdleReason.disabled -> Unit
            }
        }
        startTickerIfNeeded()
    }

    private fun wireTransportIfNeeded() {
        val t = transport ?: return
        if (wired) return
        wired = true
        t.onEvent = { event -> apply(RealtimeEvent.Transport(event)) }
    }

    // ---------------------------------------------------------------- 링

    /** 링에 사건을 넣고 effect 를 실행한다. **러너가 링에 시각을 주는 유일한 문.** */
    fun apply(event: RealtimeEvent, at: SwiftDate? = null) {
        val instant = at ?: clock.now()
        val out = link.apply(event, instant, jitter)
        if (state != link.state) state = link.state
        run(out, instant)
    }

    /** 주기 점검 1회(시험은 직접 부른다). */
    fun tick(at: SwiftDate? = null) {
        val instant = at ?: clock.now()
        apply(RealtimeEvent.Tick, instant)
        val retryAt = link.retryAt
        if (retryJob == null && retryAt != null && instant >= retryAt) apply(RealtimeEvent.BackoffElapsed, instant)
    }

    private fun run(out: List<RealtimeEffect>, now: SwiftDate) {
        for (effect in out) {
            effects += effect
            if (effects.size > EFFECT_LOG_LIMIT) effects.subList(0, effects.size - EFFECT_LOG_LIMIT).clear()
            when (effect) {
                is RealtimeEffect.Connect -> performConnect()
                RealtimeEffect.Disconnect -> transport?.disconnect()
                is RealtimeEffect.ScheduleRetry -> scheduleRetry(effect.at, now)
                RealtimeEffect.CancelRetry -> {
                    retryJob?.cancel()
                    retryJob = null
                }
                RealtimeEffect.CatchUp -> {
                    // 조인 직후 따라잡기: 소켓이 내려가 있던 동안의 신호는 재생되지 않는다 — 서버 표를 다시 읽는다(조회만).
                    requestMessageActivity()
                    gomoku?.realtimeDidJoin()
                    // INV-MobileRealtimeRunner-b94b3ac4 이식: 테트리스도 같은 자리다 — 판 중에 소켓이 끊겼다 붙으면 그 사이의 방해 줄을 **보고 왕복이
                    //   알려 주기 전에** 받는다(조인 직후 로비를 한 번 긁는다 → 그 응답이 가리키는 판까지).
                    tetris?.realtimeDidJoin()
                }
                // INV-MobileRealtimeRunner-8764ac83 이식: take_pokes 가 아니다(R3). 새 메시지가 있다는 신호일 뿐 — 요약·이력 조회로 갚는다
                //   (PhoneRealtimeRunnerTest 가 진짜 메시지 스토어로 요청을 재서 take_pokes 0 · message_unread_summary 1 을 단언한다).
                RealtimeEffect.Drain -> requestMessageActivity()
                RealtimeEffect.MessageReadSignal -> requestMessageRead()
                RealtimeEffect.GomokuSignal -> gomoku?.handleSignal()
                // INV-MobileRealtimeRunner-04360395 이식: **일부러 빈 가지**다. ① 폰 체스는 받은함 RPC 가 없어(로비 `me` 로만 온다) 이 신호를 소비할
                //   주체를 정하지 않았다 — 여기서 체스 재조회를 이으면 상대가 한 수 둘 때마다 화면이 안 떠 있어도 조회가 나간다(게임 탭 배지가 체스를
                //   안 세는 근거와 같다). ② 그래서 초인종이 와도 폰은 다음 폴링까지 모른다 — 체스 화면이 떠 있으면 코어 폴링이 금방 갚는다.
                //   ③ **`.drain` 으로 떨어뜨리면 안 된다**: 수마다 메시지 조회가 한 번씩 더 나간다. 가지를 따로 비워 두는 것이 그 차단이다.
                RealtimeEffect.ChessSignal -> Unit
                // INV-MobileRealtimeRunner-d94b411a 이식: 테트리스 초인종은 판 중 공격마다 울린다 — **`.drain` 으로 떨어뜨리면** 그 울림마다 메시지
                //   요약·이력 조회가 한 번씩 더 나간다. 잇는 것(방해 줄이 늦지 않게 — 맥과 같은 구조)과 따로 두는 것은 별개의 요구다.
                RealtimeEffect.TetrisSignal -> tetris?.handleSignal()
                // 확성기 배너(Swift MobileRealtimeRunner .megaphoneSignal @ 8b40bd44): 배너 목록 재조회 — **take_pokes 도 메시지 조회도 아니다**
                //   (확성기 줄의 소비·요약은 같은 묶음의 ring → .drain 이 맡는다). `.drain` 으로 떨어뜨리면 배너가 안 뜬다.
                RealtimeEffect.MegaphoneSignal -> megaphone?.invoke()
                is RealtimeEffect.PushAccessToken -> transport?.pushAccessToken(effect.token)
                is RealtimeEffect.ScheduleTokenRefresh -> scheduleTokenRefresh(effect.at, now)
                is RealtimeEffect.RefreshToken -> startTokenRefresh()
                RealtimeEffect.SendHeartbeat -> transport?.sendHeartbeat()
            }
        }
    }

    private fun performConnect() {
        val t = transport ?: return
        val current = session?.session ?: return
        val apiKey = service.anonKey ?: return
        // 링이 실어 온 토큰이 아니라 **지금 세션의 토큰**(백오프 동안 갱신됐을 수 있다 — 맥과 같은 경합 2 차단). private=true 필수.
        t.connect(service.projectURL, apiKey, current.accessToken, RealtimeLinkConstants.pokeChannel(current.userID), isPrivate = true)
    }

    // ---------------------------------------------------------------- 합치기

    private fun requestMessageActivity() {
        pendingActivity = true
        scheduleCoalescedFlush()
    }

    private fun requestMessageRead() {
        pendingRead = true
        scheduleCoalescedFlush()
    }

    private fun scheduleCoalescedFlush() {
        if (coalesceJob != null) return
        val delayMillis = (coalesceSeconds * 1000.0).toLong()
        coalesceJob = scope.launch {
            if (delayMillis > 0) delay(delayMillis)
            coalesceJob = null
            flushCoalescedSignals()
        }
    }

    /** 모아 둔 신호를 지금 갚는다(창이 끝났을 때 · 시험). */
    fun flushCoalescedSignals() {
        coalesceJob?.cancel()
        coalesceJob = null
        if (pendingActivity) {
            pendingActivity = false
            activityFlushCount += 1
            for (handler in activityHandlers.values.toList()) handler()
        }
        if (pendingRead) {
            pendingRead = false
            readFlushCount += 1
            for (handler in readHandlers.values.toList()) handler()
        }
    }

    // ---------------------------------------------------------------- 타이머

    private fun scheduleRetry(at: SwiftDate, now: SwiftDate) {
        retryJob?.cancel()
        val delayMillis = (maxOf(0.0, at.timeIntervalSince(now)) * 1000.0).toLong()
        retryJob = scope.launch {
            if (delayMillis > 0) delay(delayMillis)
            retryJob = null
            apply(RealtimeEvent.BackoffElapsed)
        }
    }

    private fun scheduleTokenRefresh(at: SwiftDate, now: SwiftDate) {
        tokenRefreshJob?.cancel()
        tokenRefreshJob = null
        if (!runsTimers) return
        val delayMillis = (maxOf(0.0, at.timeIntervalSince(now)) * 1000.0).toLong()
        tokenRefreshJob = scope.launch {
            if (delayMillis > 0) delay(delayMillis)
            tokenRefreshJob = null
            startTokenRefresh()
        }
    }

    private fun startTokenRefresh() {
        val store = session ?: return
        scope.launch {
            when (val result = store.refreshForRealtime()) {
                // 세션 스토어의 onAccessTokenChanged 가 이미 `.tokenRefreshed` 를 넣었다(accessTokenDidChange).
                is RealtimeRefreshResult.Refreshed -> Unit
                is RealtimeRefreshResult.Failed -> {
                    // 갱신이 도는 사이 로그아웃·재로그인으로 세대가 바뀌었다 — 옛 링의 결과다. 새 세션의 링에 넣으면 fatal 로 접혀 막 붙은 소켓을
                    // 내린다(dbase-fix · 검증 V3). 새 링은 자기 토큰으로 이미 움직이고 있다.
                    if (result.stale) return@launch
                    apply(RealtimeEvent.TokenRefreshFailed(result.fatal))
                }
            }
        }
    }

    private fun startTickerIfNeeded() {
        if (!runsTimers || tickJob != null || transport == null) return
        val intervalMillis = (tickIntervalSeconds * 1000.0).toLong()
        tickJob = scope.launch {
            while (isActive) {
                delay(intervalMillis)
                tick()
            }
        }
    }

    private fun stopTicker() {
        tickJob?.cancel()
        tickJob = null
    }

    private fun cancelTimers() {
        stopTicker()
        retryJob?.cancel()
        retryJob = null
        tokenRefreshJob?.cancel()
        tokenRefreshJob = null
        coalesceJob?.cancel()
        coalesceJob = null
        pendingActivity = false
        pendingRead = false
    }

    private companion object {
        const val EFFECT_LOG_LIMIT = 50
    }
}
