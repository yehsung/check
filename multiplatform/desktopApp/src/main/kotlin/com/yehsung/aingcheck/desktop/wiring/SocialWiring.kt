// 원본: 없음(조립 — W-6 #6 배선 social). 근거: 갈래 보고 coordinator_patches W2-g2(찌르기) · W2-g3(실시간) · W2-g4(울트라·집중)
// + W-6 #1(깃발 꺼진 기능의 조립). 근무 배선(WorkWiring)이 낸 상태·사실·랩 판정을 받아 소셜 한 벌을 만들고, 근무→소셜 생명주기를
// [SocialWiring.lifecycle] 하나로 펼친다.
//
// W-6 #1: poke=false → 찌르기 poller·drainer·sender 를 **만들지 않는다**(take_pokes·발신 0). 실시간 러너는 메시지·게임 갱신용으로
// 만들되 drainer 공급자는 null(소비 0). ultra=false → 울트라 발신·구매만 막고 지갑 sync·집중 모드는 깃발 없이 돈다
// (찌르기 폴러가 없으면 [SocialWiring] 의 자기 박자가 집중 만료 → 지갑 periodic 을 돌린다).
@file:OptIn(ExperimentalTime::class)

package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.foundation.platform.RunningTests
import com.yehsung.aingcheck.core.net.realtime.KtorRealtimeTransport
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransport
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.stores.me.RubyBalanceMirror
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.focus.FocusModeController
import com.yehsung.aingcheck.feature.desktop.poke.DesktopMessageBubbleQueue
import com.yehsung.aingcheck.feature.desktop.poke.DesktopPokeConsumeGate
import com.yehsung.aingcheck.feature.desktop.poke.DesktopPokeDrainer
import com.yehsung.aingcheck.feature.desktop.poke.DesktopPokePoller
import com.yehsung.aingcheck.feature.desktop.poke.DesktopPokeRules
import com.yehsung.aingcheck.feature.desktop.poke.DesktopPokeSender
import com.yehsung.aingcheck.feature.desktop.poke.DesktopPokeWiring
import com.yehsung.aingcheck.feature.desktop.poke.PokeBeatHooks
import com.yehsung.aingcheck.feature.desktop.poke.PokeSendHooks
import com.yehsung.aingcheck.feature.desktop.realtime.DesktopRealtimeGames
import com.yehsung.aingcheck.feature.desktop.realtime.DesktopRealtimeMessages
import com.yehsung.aingcheck.feature.desktop.realtime.DesktopRealtimeRunner
import com.yehsung.aingcheck.feature.desktop.socialapi.ConsumedRowsSink
import com.yehsung.aingcheck.feature.desktop.socialapi.DesktopSocialLifecycle
import com.yehsung.aingcheck.feature.desktop.socialapi.ReceivedPokeSink
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraChargedSink
import com.yehsung.aingcheck.feature.desktop.ultra.UltraFocusLifecycle
import com.yehsung.aingcheck.feature.desktop.ultra.UltraPurchase
import com.yehsung.aingcheck.feature.desktop.ultra.UltraWalletCadence
import com.yehsung.aingcheck.feature.desktop.ultra.UltraWalletStore
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkState
import com.yehsung.aingcheck.feature.desktop.work.LapWalletJudgment
import com.yehsung.aingcheck.feature.desktop.work.PokeFactsSource
import com.yehsung.aingcheck.feature.desktop.work.policy.toSwiftDate
import io.ktor.client.HttpClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.time.Clock
import kotlin.time.ExperimentalTime

/**
 * 소셜 배선의 의존 묶음. 앞 칸은 AppGraph 공용(이름·타입 그대로), [workState]·[pokeFacts]·[lapJudgment] 는 [WorkWiring] 이 낸 것
 * (`work.store` · `work.store` · `work.lapJudgment`). 받는 쪽(오버레이·메시지·게임)이 없으면 기본값 — 특히 [receivedPokes]·[consumedRows]
 * 가 null 이면 poke 깃발이 켜져도 drainer 를 만들지 않는다(DesktopPokeWiring.drainerOrNull — take_pokes 0).
 * [httpClient] 는 실시간 WebSockets 가 붙은 것(`graph.httpClient(KtorRealtimeTransport.clientConfig)`).
 */
data class SocialDeps(
    val sessionStore: SessionStore,
    val httpClient: HttpClient,
    val desktopConfig: DesktopAppConfig,
    val kv: DesktopKeyValueStore,
    val clock: Clock,
    val workState: DesktopWorkState,
    val pokeFacts: PokeFactsSource,
    val lapJudgment: LapWalletJudgment,
    val ruby: RubyBalanceMirror,
    val runningTests: RunningTests,
    val environment: Map<String, String>,
    val messages: DesktopRealtimeMessages = DesktopRealtimeMessages.None,
    val games: DesktopRealtimeGames = DesktopRealtimeGames.NONE,
    val receivedPokes: ReceivedPokeSink? = null,
    val consumedRows: ConsumedRowsSink? = null,
    val ultraCharged: UltraChargedSink = UltraChargedSink { },
    val walletCadence: UltraWalletCadence = UltraWalletCadence.NONE,
    val sendHooks: PokeSendHooks = PokeSendHooks.None,
    val ultraPrice: () -> Long? = { null },
    val onShopMutation: () -> Unit = {},
    val onFocusNotice: (String) -> Unit = {},
    /** 폴링 박자의 다른 갈래 훅(주간 근무 빚·케이크 선물 — W2-g2 PokeBeatHooks.others). */
    val beatOthers: List<suspend (SwiftDate) -> Unit> = emptyList(),
)

/** 화면이 부르는 찌르기·울트라 문 — 깃발 판정을 여기 한 곳에 둔다(W-6 #1). 꺼진 기능은 null(요청 0). */
class SocialPokeActions internal constructor(
    private val sender: DesktopPokeSender?,
    private val purchase: UltraPurchase?,
    private val ultraEnabled: Boolean,
) {
    val canPoke: Boolean get() = sender != null
    val canUltra: Boolean get() = sender != null && ultraEnabled
    val canBuyUltra: Boolean get() = purchase != null

    fun sendPoke(to: String): Job? = sender?.sendPoke(to)

    fun sendUltraPoke(to: String): Job? = if (ultraEnabled) sender?.sendUltraPoke(to) else null

    fun buyUltra(count: Int = 1): Job? = purchase?.buy(count)
}

class SocialWiring(private val deps: SocialDeps) {
    private val clockFn: () -> SwiftDate = { deps.clock.now().toSwiftDate() }
    private val session = deps.sessionStore
    private val config = deps.desktopConfig
    private val lateScope = LateScope()

    /** 소비 게이트 한 벌 — 폴링과 실시간 .drain/따라잡기가 같은 인스턴스(W2-g2). */
    val gate = DesktopPokeConsumeGate(deps.pokeFacts, config)
    val bubbles = DesktopMessageBubbleQueue()

    val focus = FocusModeController(session, deps.kv, lateScope, clockFn, onNotice = deps.onFocusNotice)
    val wallet = UltraWalletStore(
        host = session,
        workState = deps.workState,
        lapJudgment = deps.lapJudgment,
        chargedSink = deps.ultraCharged,
        scope = lateScope,
        clock = clockFn,
        cadence = deps.walletCadence,
    )
    val ultraFocus = UltraFocusLifecycle(wallet, focus)

    /** ultra=false 면 만들지 않는다(구매 요청 0). */
    val purchase: UltraPurchase? =
        if (config.ultra) UltraPurchase(session, deps.ruby, wallet, lateScope, deps.ultraPrice, deps.onShopMutation) else null

    /** 러너가 drainer 를 생성자로 받는 순환(drainer 는 러너를 RealtimeSubscription 으로 받는다) — 공급자로 늦게 묶는다(W2-g3). */
    private var drainerRef: DesktopPokeDrainer? = null

    val transport: RealtimeTransport? = KtorRealtimeTransport.create(deps.httpClient, lateScope, deps.runningTests, deps.environment)
    val runner = DesktopRealtimeRunner(
        host = session,
        transport = transport,
        gate = gate,
        drainer = { drainerRef },
        messages = deps.messages,
        games = deps.games,
        refreshForRealtime = { session.refreshForRealtime() },
        scope = lateScope,
        clock = clockFn,
    )

    val drainer: DesktopPokeDrainer? = if (!config.poke) {
        null
    } else {
        DesktopPokeWiring.drainerOrNull(session, lateScope, clockFn, deps.receivedPokes, deps.consumedRows, bubbles, runner)
    }.also { drainerRef = it }

    val poller: DesktopPokePoller? = if (!config.poke) {
        null
    } else {
        DesktopPokePoller(
            host = session,
            clock = clockFn,
            gate = gate,
            drainer = drainer,
            subscription = runner,
            bubbles = bubbles,
            // P10: 집중 만료 → 지갑 periodic 두 단계(UltraFocusLifecycle.onPollBeat) · 다른 갈래 훅.
            hooks = PokeBeatHooks(focusExpiry = { now -> ultraFocus.onPollBeat(now) }, others = deps.beatOthers),
        )
    }

    val sender: DesktopPokeSender? = if (!config.poke) {
        null
    } else {
        DesktopPokeSender(
            host = session,
            scope = lateScope,
            clock = clockFn,
            localSessionOpen = { deps.pokeFacts.pokeConsumeFacts().localSessionOpen },
            wallet = wallet,
            hooks = WalletSendHooks(deps.sendHooks, wallet),
        )
    }

    val actions = SocialPokeActions(sender, purchase, ultraEnabled = config.ultra)

    /** 근무 배선이 부르는 생명주기 — 셋(찌르기·실시간·울트라/집중)에 펼친다. */
    val lifecycle: DesktopSocialLifecycle = object : DesktopSocialLifecycle {
        override fun onSignedIn() {
            runner.onSignedIn()
            ultraFocus.onSignedIn()
            scope?.let { poller?.start(it) }
        }

        override fun onSignedOut() {
            poller?.stop()
            bubbles.reset()
            runner.onSignedOut()
            ultraFocus.onSignedOut()
        }

        /** requestDrain 은 여기 한 곳(W2-g3: 러너의 onWorkStarted 는 빚 지우기 + startIfPossible 만 — 둘 다면 take_pokes 2회). */
        override fun onWorkStarted() {
            drainerRef?.requestDrain()
            runner.onWorkStarted()
        }

        override fun onUserStoppedWork(isTerminating: Boolean) {
            drainerRef?.flushOnUserStop(isTerminating)
        }

        override fun onLapCrossed(lap: Int) = ultraFocus.onLapCrossed(lap)

        override fun onTeamStatusApplied() = runner.onTeamStatusApplied()

        override fun onWillSleep(at: SwiftDate) = runner.onWillSleep(at)

        override fun onDidWake(at: SwiftDate) = runner.onDidWake(at)
    }

    private var scope: CoroutineScope? = null
    private val jobs = mutableListOf<Job>()

    /** 앱 시작. 로그인 변화를 보고 onSignedIn/onSignedOut 를 낸다(처음의 null 은 건너뛴다). 멱등. */
    fun start(scope: CoroutineScope) {
        if (this.scope != null) return
        this.scope = scope
        lateScope.target = scope
        jobs += scope.launch {
            var last: String? = null
            session.sessionFlow.map { it?.userID }.distinctUntilChanged().collect { uid ->
                if (uid == last) return@collect
                if (last != null) lifecycle.onSignedOut()
                last = uid
                if (uid != null) lifecycle.onSignedIn()
            }
        }
        // 찌르기 폴러가 없으면(poke=false) 같은 주기로 집중 만료 → 지갑 periodic 만 돈다(W-6 #1 — 3시간 랩 루비를 잃지 않게).
        if (poller == null) {
            jobs += scope.launch {
                while (isActive) {
                    delay((DesktopPokeRules.pollIntervalSeconds(runner.isSubscribed) * 1000).toLong())
                    if (session.session == null) continue
                    val now = clockFn()
                    swallow { ultraFocus.onPollBeat(now) }
                    for (hook in deps.beatOthers) swallow { hook(now) }
                }
            }
        }
    }

    /** 로그아웃과 같은 정리 + 루프 내림(시험·종료). 소켓까지 내리는 것은 [shutdown]. */
    fun stop() {
        poller?.stop()
        jobs.forEach { it.cancel() }
        jobs.clear()
        scope = null
    }

    /** 앱 종료(W-6 #6: 근무 3초 → 토큰 persist 뒤 이 칸). */
    fun shutdown() {
        stop()
        runner.shutdown()
    }

    val isStarted: Boolean get() = scope != null

    /** 발신 성공의 울트라 잔량을 지갑에 잇는다(W2-g2 PokeSendHooks.applyUltraBalance/currentUltraBalance = W2-g4 지갑). */
    private class WalletSendHooks(private val outer: PokeSendHooks, private val wallet: UltraWalletStore) : PokeSendHooks {
        override fun reloadDirectory() = outer.reloadDirectory()
        override fun refreshConversationAfterPokeSent(peerUserID: String) = outer.refreshConversationAfterPokeSent(peerUserID)
        override fun applyUltraBalance(balance: Long) {
            wallet.applyBalance(balance)
            outer.applyUltraBalance(balance)
        }
        override val currentUltraBalance: Long? get() = wallet.state.value.balance
    }
}
