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
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.RubyBalanceMirror
import com.yehsung.aingcheck.core.stores.me.WeeklyWorkRules
import com.yehsung.aingcheck.core.stores.me.loadShop
import com.yehsung.aingcheck.core.stores.me.refreshAchievementsIfStale
import com.yehsung.aingcheck.core.stores.me.refreshCakeGiftIfStale
import com.yehsung.aingcheck.core.stores.me.refreshWeeklyWorkIfStale
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
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
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraSyncReason
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
    /** 메시지 말풍선 큐 — 오버레이와 **한 벌**(W-3 #6, 조립: overlay.bubbles). 기본은 자기 큐(시험·오버레이 없는 조립). */
    val bubbles: DesktopMessageBubbleQueue = DesktopMessageBubbleQueue(),
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
    val bubbles: DesktopMessageBubbleQueue = deps.bubbles

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

    /** 울트라 1개 값 공급자(조립: `{ me.ultraPrice }` — 공용 패치 18). 구매·울트라 화면이 **같은** 공급자를 읽게 그대로 내보낸다. */
    val ultraPrice: () -> Long? = deps.ultraPrice

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
            // W3-c3 nice: 로그아웃하면 구매 안내 · 화면이 고른 것을 푼다(다음 사람에게 앞사람의 '샀어요'가 남지 않게).
            purchase?.clearNotice()
            signedOutListeners.toList().forEach { swallowSync(it) }
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
    private val signedOutListeners = mutableListOf<() -> Unit>()

    /** 로그아웃·계정 전환 때 부를 일(울트라 화면의 고른 개수 풀기 · 콕 디렉터리 reset 등 — 화면 모델이 건다). */
    fun addSignedOutListener(listener: () -> Unit) {
        signedOutListeners += listener
    }

    /**
     * 울트라 화면을 떠났다(맥 closeShopPanel 의 `shopNotice = nil` — W3-c3 nice). 껍데기가 nav 를 보고 부른다
     * ([ShellDeps.onUltraPageLeft]). ultra=false 면 구매기가 없어 아무것도 안 한다.
     */
    fun onUltraPageLeft() {
        purchase?.clearNotice()
    }

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

/** 화면 쪽 훅 하나가 던져도 나머지 정리는 돈다. */
private inline fun swallowSync(block: () -> Unit) {
    try {
        block()
    } catch (e: Exception) {
        if (e is kotlinx.coroutines.CancellationException) throw e
    }
}

/**
 * int-asm 이 비워 둔 소셜 훅의 실물(int-w2). AppGraph 가 [SocialDeps] 칸에 넣는다 — 판정은 여기, 요청은 각 스토어의 IfStale 문 뒤.
 * 원본: Sources/check/WorkTimerStorePoke.swift:270-277(syncUltraWallet → refreshWeeklyWork(.walletCadence) · achievementsReason(forWallet:)) ·
 * WorkTimerStoreAchievements.swift:85-93 · WorkTimerStorePoke.swift:415-432(폴링 tick: 지갑 → 주간 빚 → 케이크 10분) ·
 * WorkTimerStoreWeeklyWork.swift:38-55(주 바뀜은 1분 창을 건너뛴다) · WorkTimerStoreMessagePokes.swift:151-155(발신 뒤 대화 갱신).
 */
object DesktopSocialHooks {
    /** 지갑 박자 → 도전 미션(맥 achievementsReason(forWallet:)): 미션 화면이 떠 있는 panelOpen · periodic · signIn 만, missionCandidate 는 아님. */
    fun achievementsOnWallet(reason: UltraSyncReason, missionPanelVisible: Boolean): Boolean = when (reason) {
        UltraSyncReason.PanelOpen -> missionPanelVisible
        UltraSyncReason.Periodic, UltraSyncReason.SignIn -> true
        UltraSyncReason.MissionCandidate -> false
    }

    /** U4: 주간 근무는 **모든** 지갑 박자에(그쪽 60초 창이 거른다), 도전 미션은 [achievementsOnWallet] 일 때만. */
    fun walletCadence(weekly: () -> Unit, achievements: () -> Unit, missionPanelVisible: () -> Boolean): UltraWalletCadence =
        UltraWalletCadence { reason ->
            weekly()
            if (achievementsOnWallet(reason, missionPanelVisible())) achievements()
        }

    /** 조립용: 나 스토어의 IfStale 문 둘(MeStoreWeeklyWork.kt:34 · MeStoreAchievements.kt:112). */
    fun walletCadence(me: MeStore, missionPanelVisible: () -> Boolean): UltraWalletCadence =
        walletCadence({ me.refreshWeeklyWorkIfStale() }, { me.refreshAchievementsIfStale() }, missionPanelVisible)

    /**
     * 폴링 박자의 다른 갈래(P10 순서 — 집중 만료 · 지갑 periodic 뒤). ① 주가 바뀌었으면 주간 근무 한 번(맥 weekRolled — 1분 창을 건너뛴다,
     * 아니면 요청 0) ② 케이크 선물 10분 문(맥 refreshCakeGiftIfDue — MeStore.refreshCakeGiftIfStale 의 10분 스로틀).
     */
    fun beatOthers(
        weekRolled: (SwiftDate) -> Boolean,
        refreshWeekly: () -> Unit,
        refreshCakeGift: () -> Unit,
    ): List<suspend (SwiftDate) -> Unit> = listOf(
        { now -> if (weekRolled(now)) refreshWeekly() },
        { _ -> refreshCakeGift() },
    )

    fun beatOthers(me: MeStore): List<suspend (SwiftDate) -> Unit> = beatOthers(
        weekRolled = { now -> WeeklyWorkRules.weekHasRolled(me.weeklyWork, now) },
        refreshWeekly = { me.refreshWeeklyWorkIfStale() },
        refreshCakeGift = { me.refreshCakeGiftIfStale() },
    )

    /** 발신 성공의 바깥 몫: 콕 디렉터리 다시 읽기(화면 모델이 늦게 건다) · 그 사람 대화가 떠 있으면 이력 한 번(MessagesStore:1022). */
    fun sendHooks(onReloadDirectory: () -> Unit, onRefreshConversation: (String) -> Unit): PokeSendHooks = object : PokeSendHooks {
        override fun reloadDirectory() = onReloadDirectory()
        override fun refreshConversationAfterPokeSent(peerUserID: String) = onRefreshConversation(peerUserID)
    }

    fun sendHooks(messages: MessagesStore, reloadDirectory: () -> Unit = {}): PokeSendHooks =
        sendHooks(reloadDirectory) { peer -> messages.refreshConversationAfterPokeSent(peer) }

    /**
     * 맥 noteShopMutation(WorkTimerStoreAuth.swift:613-617)은 늦게 온 상점 조회가 구매 응답을 덮지 않게 하는 순번이다 — Kotlin 은 같은 몫을
     * 루비 칸 serial 이 진다(UltraPurchase 가 rubyBalance 를 쓰면 +1). 여기서는 W3-c3 대로 상점 상태를 **구매 반영 뒤** 한 번 다시 읽는다
     * (scope.launch — apply 가 끝난 다음 차례). ultra=false 면 구매기가 없어 불리지 않는다(요청 0).
     */
    fun shopMutation(scope: CoroutineScope, reloadShop: suspend () -> Unit): () -> Unit = { scope.launch { swallow { reloadShop() } } }

    fun shopMutation(scope: CoroutineScope, me: MeStore): () -> Unit = shopMutation(scope) { me.loadShop() }
}
