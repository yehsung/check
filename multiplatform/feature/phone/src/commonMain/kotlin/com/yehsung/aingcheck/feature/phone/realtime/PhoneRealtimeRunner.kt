// 원본: Sources/CheckMobileKit/Realtime/MobileRealtimeRunner.swift @ 3bd04bd · 활동 앞쪽 즉시 + 뒤쪽 합치기 @ c220021e
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
 *  1. `.catchUp`·`.drain` → **take_pokes 가 아니다**(C§4 #15, G §2-3 W2-f ②). 등록된 [onMessageActivity] 핸들러들을 부른다 — 조용하던 창의 첫 신호는 **곧바로**(앞쪽),
 *     그 1초 창 안에 또 온 신호들은 창 끝에 **한 번**(뒤쪽 합치기)(+ `.catchUp` 은 오목·테트리스 `realtimeDidJoin`). take_pokes 는 원자 소비라 폰이 부르면 맥의 말풍선을 훔친다(R3).
 *  2. `.messageReadSignal` → 등록된 [onMessageRead] 핸들러들(뒤쪽 1초 합치기만 — 앞쪽 즉시 처리는 없다).
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

    /** 아잉 큐브 신호를 받을 스토어(조립이 붙인다 — 같은 꼴·같은 자리). */
    var rummy: RealtimeSignalReceiver? = null

    /** 아잉 뒤집기 신호를 받을 스토어(조립이 붙인다 — 같은 꼴·같은 자리 · 판 7). 떼어 내기 깃발이 꺼진 조립은 비워 둔다(가지는 아무 일도 안 한다). */
    var reversi: RealtimeSignalReceiver? = null

    /** 1:1 길건너 · 1:1 알까기 · 아잉 마작(판 8 — Swift `realtime.crossyDuel` 등). 조립이 각 스토어로 잇는다. */
    var crossyDuel: RealtimeSignalReceiver? = null
    var alkkagi: RealtimeSignalReceiver? = null
    var mahjong: RealtimeSignalReceiver? = null

    /** 확성기 배너 신호('megaphone')를 받을 자리(조립이 붙인다 — 배너 스토어 refresh). 비어 있으면 아무 일도 안 한다(같은 묶음의 ring 이 메시지를 갚는다). */
    var megaphone: (() -> Unit)? = null

    /**
     * 메시지 활동(`.drain`·`.catchUp`)·읽음 신호를 모으는 창(초). 시험은 크게 두고 [flushCoalescedSignals] 를 직접 부른다.
     * 메시지 활동은 이 창의 **앞쪽**(조용하던 창의 첫 신호)을 곧바로 갚고 창 안의 나머지를 창 끝에 한 번 갚는다 — 창 하나에 최대 두 번.
     * 읽음 신호는 뒤쪽 한 번뿐이다(stab-1030 §5-2: 읽음·배경까지 즉시 조회로 넓히지 않는다).
     */
    var coalesceSeconds: Double = 1.0

    /** 주기 점검(`.tick`) 간격. 하트비트(25초)보다 촘촘해야 한다(맥과 같은 5초). */
    var tickIntervalSeconds: Double = 5.0

    private val activityHandlers = LinkedHashMap<Long, () -> Unit>()
    private val readHandlers = LinkedHashMap<Long, () -> Unit>()
    private var nextHandlerID = 0L
    private var pendingActivity = false
    private var pendingRead = false

    /** 읽음 신호의 뒤쪽 합치기 타이머(첫 신호 + [coalesceSeconds]). */
    private var coalesceJob: Job? = null

    /**
     * 메시지 활동의 뒤쪽 합치기 타이머(창 끝 = 마지막 활동 flush + [coalesceSeconds]). 읽음 타이머와 **따로** 둔다 — 둘이 한 타이머를 나누면
     * 먼저 온 읽음 신호의 창 끝이 활동을 창 중간에 한 번 더 갚아 '창 하나에 최대 두 번'이 흐려진다.
     */
    private var activityWindowJob: Job? = null

    /** 메시지 활동 핸들러를 마지막으로 부른 시각(앞쪽·뒤쪽 어느 쪽이든 — 주입 시계 기준). 앞쪽 즉시 처리의 창을 여기서 잰다. */
    private var lastActivityFlushAt: SwiftDate? = null
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

    /**
     * `.drain`(새 메시지 신호) · `.catchUp`(조인 직후 따라잡기)마다 — 조용하던 창의 첫 신호는 곧바로, 창 안의 나머지는 창 끝에 한 번.
     * 핸들러 쪽도 돌고 있는 새로고침에 뒤따르는 한 번으로 합친다(`MessagesStore.requestActivityRefresh`) — 이 창은 그 앞단이다.
     * 메시지 탭: 요약 + 보이는 대화 이력 재조회. **take_pokes 금지.**
     */
    fun onMessageActivity(handler: () -> Unit): PhoneRealtimeRegistration {
        val id = nextHandlerID++
        activityHandlers[id] = handler
        return PhoneRealtimeRegistration { activityHandlers.remove(id) }
    }

    /** 읽음 신호(`message_read`)마다 — 뒤쪽 1초 창에 모아 한 번. */
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
        activityWindowJob?.cancel()
        activityWindowJob = null
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
                    requestMessageActivity(now)
                    gomoku?.realtimeDidJoin()
                    // INV-MobileRealtimeRunner-b94b3ac4 이식: 테트리스도 같은 자리다 — 판 중에 소켓이 끊겼다 붙으면 그 사이의 방해 줄을 **보고 왕복이
                    //   알려 주기 전에** 받는다(조인 직후 로비를 한 번 긁는다 → 그 응답이 가리키는 판까지).
                    tetris?.realtimeDidJoin()
                    // 아잉 큐브도 같다 — 소켓이 끊긴 사이 온 초대와 넘어간 차례를 이 한 번이 따라잡는다.
                    rummy?.realtimeDidJoin()
                    // 아잉 뒤집기도 같은 자리다(로비 한 번 + 그 응답이 가리키는 판). 받은 신청은 60초를 살고 내 차례는 30초 뒤 서버가 대신 두므로(연속 3번이면 패)
                    // 다음 계기까지 기다리면 늦다.
                    reversi?.realtimeDidJoin()
                    // 1:1 길건너도 같은 자리다(가벼운 로비 한 번 — 받은 신청 60초 · 판 시작을 놓치지 않게).
                    crossyDuel?.realtimeDidJoin()
                    alkkagi?.realtimeDidJoin()
                    mahjong?.realtimeDidJoin()
                }
                // INV-MobileRealtimeRunner-8764ac83 이식: take_pokes 가 아니다(R3). 새 메시지가 있다는 신호일 뿐 — 요약·이력 조회로 갚는다
                //   (PhoneRealtimeRunnerTest 가 진짜 메시지 스토어로 요청을 재서 take_pokes 0 · message_unread_summary 1 을 단언한다).
                RealtimeEffect.Drain -> requestMessageActivity(now)
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
                // 아잉 큐브(RealtimeEffect.rummySignal @ 1a5eeca6): 스토어의 합쳐지는 재조회로 간다 — `.drain` 으로 떨어뜨리면 끌기마다 메시지 조회가 나간다.
                RealtimeEffect.RummySignal -> rummy?.handleSignal()
                // 아잉 뒤집기(판 7 — iOS 1.0.17 과 같이 **잇는다**): 신청·수락·상대 수·자동 착수·정산이 전부 이 초인종으로 온다. 받은 신청은 로비 `me.incoming`
                //   으로만 오므로 이 가지가 비면 탭 배지가 다음 허브 진입(30초 스로틀)까지 늦다. `.drain` 으로 떨어뜨리면 수마다 메시지 조회가 한 번씩 더 나간다.
                RealtimeEffect.ReversiSignal -> reversi?.handleSignal()
                // 1:1 길건너(판 8 — iOS 1.0.18 과 같이 **잇는다**): 신청·수락·시작·정산 초인종. 받은 신청은 로비 `me.incoming` 으로만 온다.
                RealtimeEffect.CrossyDuelSignal -> crossyDuel?.handleSignal()
                // 1:1 알까기 · 아잉 마작: 받을 스토어를 이을 때까지 **일부러 빈 가지**다(`.drain` 으로 떨어뜨리면 울릴 때마다 메시지 조회가 나간다).
                RealtimeEffect.AlkkagiSignal -> alkkagi?.handleSignal()
                RealtimeEffect.MahjongSignal -> mahjong?.handleSignal()
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

    /**
     * 메시지 활동: **앞쪽 처리 + 뒤쪽 합치기**(stab-1030 §5-2). 예전에는 모든 활동을 1초 뒤에 갚아, 열린 대화에서도 새 말이 **늘 1초 이상 늦게** 섰다. 지금은
     *  · 앱이 active 이고 최근 [coalesceSeconds] 안에 활동 flush 가 없었으면 → **곧바로** 핸들러를 부른다(앞쪽).
     *  · 그 창 안에 또 온 신호는 모아 두었다가 **창 끝**(마지막 flush + 창)에 한 번 부른다(뒤쪽 — 예전 합치기).
     * 그래서 신호가 몰려도 창 하나에 최대 두 번이다. 핸들러가 띄운 새로고침이 아직 돌고 있으면 그쪽이 뒤따르는 한 번으로 또 합친다
     * (`MessagesStore.requestActivityRefresh`) — 이 창은 그 계약을 건드리지 않는다.
     * active 가 아니면 앞쪽은 없다 — 예전 그대로 첫 신호 + 창 뒤에 한 번이고, background 진입이 모아 둔 것을 버린다.
     */
    private fun requestMessageActivity(now: SwiftDate) {
        if (isAppActive && activityWindowHasElapsed(now)) {
            flushPendingActivity(now)
            return
        }
        pendingActivity = true
        scheduleActivityWindowEnd(now)
    }

    /** 마지막 활동 flush 뒤로 창이 다 지났는가. 시계가 뒤로 갔으면(음수) 아직 창 안으로 본다 — 앞쪽을 더 열지 않는 쪽. */
    private fun activityWindowHasElapsed(now: SwiftDate): Boolean {
        val last = lastActivityFlushAt ?: return true
        return now.timeIntervalSince(last) >= coalesceSeconds
    }

    private fun scheduleActivityWindowEnd(now: SwiftDate) {
        // 끝난 작업이 칸에 남아 있어도 새 창을 막지 않게 isActive 로 본다(즉시 디스패처에서는 대기 0 의 몸통이 대입보다 먼저 끝난다).
        if (activityWindowJob?.isActive == true) return
        val window = maxOf(0.0, coalesceSeconds)
        // 창 끝까지 남은 시간. active 가 아니거나 앞쪽 flush 가 없었으면 예전처럼 첫 신호 + 창 전체다.
        // [0, 창] 으로 묶는다 — 시계가 뒤로 가도 창보다 오래 붙잡지 않는다.
        val last = lastActivityFlushAt
        val delaySeconds = if (isAppActive && last != null) minOf(window, maxOf(0.0, window - now.timeIntervalSince(last))) else window
        val delayMillis = (delaySeconds * 1000.0).toLong()
        activityWindowJob = scope.launch {
            if (delayMillis > 0) delay(delayMillis)
            activityWindowJob = null
            if (pendingActivity) flushPendingActivity(clock.now())
        }
    }

    /** 메시지 활동 핸들러를 지금 부른다(앞쪽 · 창 끝 · 시험 훅). 모아 둔 것도 이 한 번이 함께 갚는다. */
    private fun flushPendingActivity(now: SwiftDate) {
        activityWindowJob?.cancel()
        activityWindowJob = null
        pendingActivity = false
        lastActivityFlushAt = now
        activityFlushCount += 1
        for (handler in activityHandlers.values.toList()) handler()
    }

    private fun requestMessageRead() {
        pendingRead = true
        scheduleCoalescedFlush()
    }

    /**
     * 읽음 신호의 뒤쪽 합치기(첫 신호 + 창). 앞쪽 즉시 처리는 **일부러** 없다 — 읽음 신호는 새 줄을 세우지 않고 말풍선 옆 1 만 지우므로
     * 1초 늦어도 잃는 것이 적고, 감사(stab-1030 §5-2)가 읽음까지 즉시 조회로 넓히지 말라고 했다.
     */
    private fun scheduleCoalescedFlush() {
        if (coalesceJob != null) return
        val delayMillis = (coalesceSeconds * 1000.0).toLong()
        coalesceJob = scope.launch {
            if (delayMillis > 0) delay(delayMillis)
            coalesceJob = null
            flushPendingRead()
        }
    }

    private fun flushPendingRead() {
        coalesceJob?.cancel()
        coalesceJob = null
        if (!pendingRead) return
        pendingRead = false
        readFlushCount += 1
        for (handler in readHandlers.values.toList()) handler()
    }

    /**
     * 모아 둔 신호를 지금 갚는다(창이 끝났을 때 · 시험). 모아 둔 것이 없으면 아무것도 부르지 않는다 — 그래서 이 훅은 앞쪽 창을 새로 열지도
     * 닫지도 않는다(활동 flush 시각은 핸들러를 실제로 부를 때만 바뀐다).
     */
    fun flushCoalescedSignals() {
        if (pendingActivity) {
            flushPendingActivity(clock.now())
        } else {
            activityWindowJob?.cancel()
            activityWindowJob = null
        }
        flushPendingRead()
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
        activityWindowJob?.cancel()
        activityWindowJob = null
        pendingActivity = false
        pendingRead = false
    }

    private companion object {
        const val EFFECT_LOG_LIMIT = 50
    }
}
