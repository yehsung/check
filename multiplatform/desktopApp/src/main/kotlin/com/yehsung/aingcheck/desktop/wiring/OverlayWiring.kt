// 원본: 없음(조정자 배선) — W-6 #6(AppGraph/Main 을 wiring/*Wiring.kt 로 나눠 각자 가짜로 시험) · W5-b1 coordinator_patches P3 ·
// W5-b2 P3(CharacterPlayerSink·OverlayPlacementStore) · W5-b3 P3(TodoBoardController 를 BoardHost 로) · W-3 #6·#7·#12 · pins.md I-8.
//
// 오버레이 엔진(OverlayDirector, 순수·시계 없음)에 앱의 사실을 잇는다: 근무 스냅숏·캐릭터 켜짐 → onWorking, 근무 사건 → onWorkEvent,
// 받은 찌르기 → onPokes, 울트라 충전·주간 근무 루비 → onReward, 메시지 큐 변화 → onMessagesChanged, 잠자기·잠금 → onRenderSuspend.
// **엔진은 한 줄로만 만진다**: 모든 입력은 명령 채널 하나로 들어가고, 한 소비 코루틴이 단조 `now` 를 찍어 차례로 적용한다
// (트레이·Win32 메시지 스레드·소셜 폴러 어느 스레드에서 와도 순서가 섞이지 않는다). start 전에 온 입력은 채널에 쌓였다가 start 때 흐른다.
//
// int-w2(W5-b4 notes): 화면 쪽 한 벌([OverlaySurfaces] — 구운 재생기·레이어드 창·할 일 보드 외양)을 생성자에서 받아 sink·presenter·board 를 갈아 끼우고
// 엔진·포인터를 묶는다(종료 때 [stop] 이 엔진을 내린 **뒤** 창을 닫는다). 받은 메시지 말풍선 큐([bubbles])는 이 배선이 만들어 소셜에 넘긴다
// (W-3 #6 — 같은 사건은 한 표면만). 계정 전환([OverlayWiringDeps.accountIds]) · 설정 할 일 보드([OverlayWiringDeps.todoBoard]) 를 스스로 본다.
package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.foundation.platform.MonotonicClock
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvents
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.overlay.engine.BoardHost
import com.yehsung.aingcheck.desktop.overlay.engine.BubbleTextMeasure
import com.yehsung.aingcheck.desktop.overlay.engine.CharacterSink
import com.yehsung.aingcheck.desktop.overlay.engine.DuelAttention
import com.yehsung.aingcheck.desktop.overlay.engine.DuelFacts
import com.yehsung.aingcheck.desktop.overlay.engine.DuelGame
import com.yehsung.aingcheck.desktop.overlay.engine.DuelInvite
import com.yehsung.aingcheck.desktop.overlay.engine.HitTarget
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayDirector
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayPoint
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayView
import com.yehsung.aingcheck.desktop.overlay.engine.PointerKind
import com.yehsung.aingcheck.desktop.overlay.engine.PointerOutcome
import com.yehsung.aingcheck.desktop.overlay.engine.ReactionKind
import com.yehsung.aingcheck.desktop.overlay.engine.RenderSuspendReason
import com.yehsung.aingcheck.desktop.overlay.engine.TeamPresence
import com.yehsung.aingcheck.desktop.overlay.assembly.OverlaySurfaces
import com.yehsung.aingcheck.desktop.overlay.surface.OverlayPlacementStore
import com.yehsung.aingcheck.desktop.overlay.surface.OverlaySurfaceListener
import com.yehsung.aingcheck.desktop.overlay.todoboard.TodoBoardAppearance
import com.yehsung.aingcheck.desktop.overlay.todoboard.TodoBoardController
import com.yehsung.aingcheck.desktop.pages.desktopsettings.TodoBoardSetting
import com.yehsung.aingcheck.desktop.shellapi.OverlayAvailability
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.poke.DesktopMessageBubbleQueue
import com.yehsung.aingcheck.feature.desktop.socialapi.ReceivedPokeSink
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraChargedSink
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkState
import com.yehsung.aingcheck.feature.desktop.work.WorkEventSink
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import kotlin.random.Random
import kotlin.time.Clock

/** 한 틱의 그림을 화면에 낸다(Windows: OverlayCompositor.compose → WindowsOverlaySurface.present — W5-b2 P3). 시험은 기록만. */
fun interface OverlayPresenter {
    fun present(view: OverlayView, now: Double)

    companion object {
        val None: OverlayPresenter = OverlayPresenter { _, _ -> }
    }
}

/** 오버레이 배선이 받는 것. 이름·타입은 AppGraph 의 것 그대로(desktopConfig·clock·monotonic·platform.power/session). */
data class OverlayWiringDeps(
    val desktopConfig: DesktopAppConfig,
    val keyValueStore: DesktopKeyValueStore,
    val clock: Clock,
    val monotonic: MonotonicClock,
    /**
     * 근무 스냅숏(ws W2-g5 DesktopWorkStore). isWorking·startOrigin 만 읽는다. **start 때 한 번 부른다** — DesktopWorkStore 가
     * `events = overlay.workEventSink` 를 받아 만들어지므로(순환), 오버레이를 먼저 만들고 근무 스토어는 그 뒤에 만든다.
     */
    val workState: () -> DesktopWorkState,
    /** 설정의 캐릭터 켜짐(맥 isOverlayEnabled). 꺼짐이면 peek 하지 않는다(W-3 #6 — 그때만 토스트). */
    val overlayEnabled: StateFlow<Boolean>,
    /** W5-b2 `CharacterPlayerSink(player)`. */
    val sink: CharacterSink,
    /** W5-b2 `PretendardBubbleMeasure.bundled`(W-3 #8). */
    val measure: BubbleTextMeasure,
    /** W5-b3 `TodoBoardController`(I-6). 없으면 클릭은 때리기. */
    val board: BoardHost = BoardHost.None,
    /** `platform.power` — 잠자기 동안 그리기 정지. */
    val power: PowerEvents? = null,
    /** `platform.session` — 잠금·콘솔 분리 동안 그리기 정지. */
    val session: SessionEvents? = null,
    /** WTS 콘솔 세션을 지금 쓸 수 있나 — 낡은 잠금 사유 풀기(W5-b1 unresolved, 맥은 깜빡 주기마다). */
    val consoleSessionUsable: () -> Boolean = { true },
    /** 주간 근무 루비 지급액(MeStore `weeklyGrantSerial` 변화 때 `weeklyGrantNotice.ruby`). 무엇을 보낼지는 생산자(규약 8). */
    val weeklyRubyGrants: Flow<Long> = emptyFlow(),
    /**
     * 로그인 사용자 id(`sessionStore.sessionFlow.map { it?.userID }`). 알던 계정에서 다른 값(null = 로그아웃 · 다른 id = 전환)으로 바뀌면
     * [OverlayWiring.onAccountChanged] — 인사 기억·대결 큐를 비우고 보드를 새 계정으로(맥 onSignedOut).
     */
    val accountIds: Flow<String?> = emptyFlow(),
    /**
     * 설정의 할 일 보드(`DesktopSettingsStore.todoBoard` — 켜짐·진하기). 켜짐이 바뀌면 [OverlayWiring.onBoardEnabledChanged],
     * 진하기는 화면 쪽 외양([OverlaySurfaces.boardAppearance])으로 옮긴다(null = 외양 기본값 0.55).
     */
    val todoBoard: StateFlow<TodoBoardSetting>? = null,
    /** 보드 위에서 진하기를 바꿨다(외양 → 설정 — `desktopSettings.setTodoBoardOpacity(it)`). 같은 값이면 부르지 않는다. */
    val onBoardOpacityChanged: (Double) -> Unit = {},
    val presenter: OverlayPresenter = OverlayPresenter.None,
    /** 포인터 결과(클릭 → 플라이아웃·대결 창, 이동 → 창 옮기기). 자리 저장은 이 배선이 한다. */
    val onPointerOutcome: (PointerOutcome) -> Unit = {},
    val random: Random = Random.Default,
    val tickMillis: Long = OverlayWiring.DEFAULT_TICK_MILLIS,
)

/**
 * 오버레이 배선 핸들. AppGraph 가 하나 만들고, 사건 출구([workEventSink]·[receivedPokeSink]·[ultraChargedSink])를 근무·소셜 배선에 넘긴다.
 * 명령은 언제든 받는다(start 전이면 쌓인다). [start] 의 scope 는 앱 수명(Swing Main) — 소비자는 하나라 디스패처 종류와 무관하게 직렬이다.
 */
class OverlayWiring(base: OverlayWiringDeps, private val surfaces: OverlaySurfaces? = null) {
    companion object {
        /** 그리기 틱(30fps). 엔진 타이머는 마감 시각 비교라 틱 간격과 무관하다. */
        const val DEFAULT_TICK_MILLIS: Long = 33
        /** 이미 띄운 업데이트 버전(버전당 1회 — 재시작해도). */
        const val SHOWN_UPDATE_VERSION_KEY = "check.overlay.shownUpdateVersion"
        /** 낡은 잠금 사유 재검사 간격(초) — 맥 깜빡 주기 몫. */
        const val RECONCILE_INTERVAL_S = 5.0

        /**
         * MeStore 의 (weeklyGrantSerial, weeklyGrantNotice?.ruby) 흐름 → 지급 루비(규약 8). 일련번호가 **올라갈 때만** 한 번 낸다 —
         * 같은 값 재방출·로그아웃 0 되돌림은 내지 않는다(맥 applyWeeklyWork 가 새 지급마다 onRewardTrigger 한 번 — WorkTimerStoreWeeklyWork.swift:131-134).
         * 일련번호는 프로세스 안에서 0 부터라 첫 값이 1 이상이면 그것도 새 지급이다.
         */
        fun weeklyRubyGrants(serials: Flow<Pair<Int, Long?>>): Flow<Long> = flow {
            var last = 0
            serials.collect { (serial, ruby) ->
                if (serial > last && ruby != null) emit(ruby)
                last = serial
            }
        }

        /** 게임 화면의 '나'(GamesDeps.boardMe) — 표정은 맥 CheckMascotAssets.mood(for:)(:73-75): 근무 중 Working, 아니면 Off. */
        fun boardMe(name: String?, characterId: String?, isWorking: Boolean): BoardGameMe =
            BoardGameMe(name, characterId, if (isWorking) CharacterMood.Working else CharacterMood.Off)
    }

    /** 실물 화면이 있으면 그 sink·presenter·board 와 포인터 결과(끌기 = 창 옮기기 먼저)로 갈아 끼운다. */
    private val deps: OverlayWiringDeps = surfaces?.let { s ->
        base.copy(
            sink = s.sink,
            presenter = s.presenter,
            board = s.board,
            onPointerOutcome = { o -> s.onPointerOutcome(o); base.onPointerOutcome(o) },
        )
    } ?: base

    /**
     * 받은 메시지 말풍선 큐 — **오버레이와 소셜이 같은 인스턴스**(W-3 #6). SocialDeps 가 조립에서 받아 폴링·실시간이 여기에 쌓고,
     * 엔진은 띄웠을 때만 consumeCurrent 한다(규약 10).
     */
    val bubbles: DesktopMessageBubbleQueue = DesktopMessageBubbleQueue()

    val director: OverlayDirector = OverlayDirector(deps.sink, deps.measure, bubbles, deps.board, deps.random)
    private val placements = OverlayPlacementStore(deps.keyValueStore)

    private val commands = Channel<(Double) -> Unit>(Channel.UNLIMITED)
    private val _availability = MutableStateFlow(OverlayAvailability.NONE)
    /** W3-c1 알림 중재가 읽는다(말풍선 > 토스트 > 점). 명령·틱마다 갱신. */
    val availability: StateFlow<OverlayAvailability> = _availability.asStateFlow()

    private var job: Job? = null
    private val registrations = ArrayList<Registration>()
    private var lastReconcileAt = Double.NEGATIVE_INFINITY
    @Volatile private var tickPending = false
    private var persistedUpdateVersion: String? = deps.keyValueStore.getString(SHOWN_UPDATE_VERSION_KEY)

    /** 그린 틱 수(시험·진단). */
    @Volatile var framesPresented: Int = 0
        private set

    private var surfacesClosed = false
    private var appearanceListener: (() -> Unit)? = null
    @Volatile private var applyingBoardSetting = false

    init {
        director.shownUpdateVersion = persistedUpdateVersion
        surfaces?.bind(director, OverlaySurfaceListener { kind, pt, target -> onPointer(kind, pt, target) })
    }

    // ───────────────────────── 사건 출구(다른 배선이 받는다) ─────────────────────────

    /** ws·wp → 오버레이. NudgeStarted·AutoClosed 는 ws 만 낸다(W-6 #2). LapCelebrated·AutoClosed 는 엔진이 무시(랩 루비는 [ultraChargedSink] 길). */
    val workEventSink: WorkEventSink = WorkEventSink { e -> post { now -> director.onWorkEvent(e, now) } }

    /** W2-g2 DesktopPokeDrainer → 오버레이. poke=false 면 drainer 를 조립하지 않으니 이 출구는 불리지 않는다(W-6 #1). */
    val receivedPokeSink: ReceivedPokeSink = ReceivedPokeSink { batch -> post { now -> director.onPokes(batch, now) } }

    /** W2-g4 UltraWalletStore(granted_now) → 보상 말풍선. */
    val ultraChargedSink: UltraChargedSink = UltraChargedSink { post { now -> director.onReward(ReactionKind.UltraCharged, now) } }

    fun onTeam(members: List<TeamPresence>, selfId: String?) = post { now -> director.onTeam(members, selfId, now) }

    fun onUpdateAvailable(version: String) = post { now -> director.onUpdateAvailable(version, now) }

    /** 계정 전환·로그아웃 — 인사 기억·대결 큐를 비우고 보드를 새 계정으로. */
    fun onAccountChanged() = post { _ ->
        director.onSignedOut()
        (deps.board as? TodoBoardController)?.resetForAccountSwitch()
    }

    /** 설정의 할 일 켜짐이 바뀌었다(W5-b3 P3). */
    fun onBoardEnabledChanged() = post { _ -> (deps.board as? TodoBoardController)?.enabledDidChange() }

    /** WM_DISPLAYCHANGE·배율 변경(W5-b4 notes). */
    fun onDisplayChanged() {
        surfaces?.onDisplayChanged()
    }

    /** 게임 화면의 '나' — 지금 근무 스냅숏으로 표정을 정한다(GamesDeps.boardMe = { overlay.boardMe(me.displayName, me.equippedServerID) }). */
    fun boardMe(name: String?, characterId: String?): BoardGameMe =
        boardMe(name, characterId, deps.workState().snapshot.value.isWorking)

    /** 대결 신청 도착. duels=false 면 안내 0(W-3 #7). [expiresAt] 은 벽시계 — 단조 초로 바꿔 넣는다. */
    fun onDuelInvite(game: DuelGame, id: String, peerName: String, stake: Int, expiresAt: SwiftDate) {
        if (!deps.desktopConfig.duels) return
        val remaining = expiresAt.timeIntervalSince1970 - wallSeconds()
        post { now -> director.enqueueDuelInvite(DuelInvite(game, id, peerName, stake, now + remaining), now) }
    }

    fun onDuelAttention(attention: DuelAttention) {
        if (!deps.desktopConfig.duels) return
        post { now -> director.enqueueDuelAttention(attention, now) }
    }

    fun onDuelFacts(game: DuelGame, facts: DuelFacts) {
        if (!deps.desktopConfig.duels) return
        post { _ -> director.onDuelFacts(game, facts) }
    }

    /** Win32 메시지 스레드(OverlaySurfaceListener)에서 온다 — 결과는 [OverlayWiringDeps.onPointerOutcome] 로. 자리 저장은 여기서. */
    fun onPointer(kind: PointerKind, ptDip: OverlayPoint, target: HitTarget) = post { now ->
        val outcome = director.onPointer(kind, ptDip, target, now)
        outcome.savePlacement?.let(placements::save)
        deps.onPointerOutcome(outcome)
    }

    // ───────────────────────── 수명 ─────────────────────────

    fun start(scope: CoroutineScope) {
        if (job != null || surfacesClosed) return
        surfaces?.boardAppearance?.let { store ->
            appearanceListener = store.addListener { a -> if (!applyingBoardSetting) deps.onBoardOpacityChanged(a.opacity) }
        }
        deps.power?.let { p ->
            registrations += p.addListener { e ->
                post { now -> director.onRenderSuspend(RenderSuspendReason.SCREENS_ASLEEP, e == PowerEvent.SLEEP, now) }
            }
        }
        deps.session?.let { s ->
            registrations += s.addListener { e ->
                val (reason, suspended) = when (e) {
                    SessionEvent.LOCK -> RenderSuspendReason.SCREEN_LOCKED to true
                    SessionEvent.UNLOCK -> RenderSuspendReason.SCREEN_LOCKED to false
                    SessionEvent.CONSOLE_DISCONNECT, SessionEvent.REMOTE_DISCONNECT, SessionEvent.LOGOFF -> RenderSuspendReason.SESSION_INACTIVE to true
                    SessionEvent.CONSOLE_CONNECT, SessionEvent.REMOTE_CONNECT -> RenderSuspendReason.SESSION_INACTIVE to false
                }
                post { now -> director.onRenderSuspend(reason, suspended, now) }
            }
        }
        job = scope.launch {
            // I-8: isWorking·startOrigin 은 같은 스냅숏에서 온다(넛지 자동 시작은 startOrigin=NUDGE 로 8s 문구).
            launch {
                deps.workState().snapshot.combine(deps.overlayEnabled) { s, enabled -> Triple(s.isWorking, enabled, s.startOrigin) }
                    .collect { (working, enabled, origin) -> post { now -> director.onWorking(working, enabled, now, origin) } }
            }
            launch { bubbles.queue.collect { post { now -> director.onMessagesChanged(now) } } }
            launch { deps.weeklyRubyGrants.collect { ruby -> post { now -> director.onReward(ReactionKind.RubyReward(ruby.toInt()), now) } } }
            launch {
                var known: String? = null
                deps.accountIds.collect { id ->
                    if (known != null && id != known) onAccountChanged()
                    known = id
                }
            }
            deps.todoBoard?.let { board ->
                launch {
                    var enabled: Boolean? = null
                    board.collect { setting ->
                        surfaces?.boardAppearance?.let { store ->
                            applyingBoardSetting = true // 설정 → 외양은 되울리지 않는다(설정이 이미 그 값이다)
                            try { store.setOpacity(setting.opacity ?: TodoBoardAppearance.DEFAULT_OPACITY) } finally { applyingBoardSetting = false }
                        }
                        if (enabled != null && enabled != setting.enabled) onBoardEnabledChanged()
                        enabled = setting.enabled
                    }
                }
            }
            launch {
                while (isActive) {
                    // 틱은 쌓지 않는다(소비가 밀려도 한 칸만 — 그리기는 언제나 최신 now).
                    if (!tickPending) {
                        tickPending = true
                        post { now -> tickPending = false; tickAndPresent(now) }
                    }
                    delay(deps.tickMillis)
                }
            }
            for (cmd in commands) {
                val now = monoSeconds()
                cmd(now)
                afterCommand(now)
            }
        }
    }

    /** 종료 훅 한 자리(W5-b4: overlay.stop → surfaces.close → tray.remove). 엔진·구독을 먼저 내리고 창은 그 **뒤**에 닫는다 — 다시 start 하지 않는다. */
    fun stop() {
        registrations.forEach { runCatching { it.close() } }
        registrations.clear()
        appearanceListener?.let { runCatching { it() } }
        appearanceListener = null
        job?.cancel()
        job = null
        val s = surfaces
        if (s != null && !surfacesClosed) {
            surfacesClosed = true
            runCatching { s.close() }
        }
    }

    // ───────────────────────── 안쪽 ─────────────────────────

    private fun post(cmd: (now: Double) -> Unit) {
        commands.trySend(cmd)
    }

    private fun tickAndPresent(now: Double) {
        if (now - lastReconcileAt >= RECONCILE_INTERVAL_S) {
            lastReconcileAt = now
            director.reconcileStaleRenderSuspension(deps.consoleSessionUsable(), now)
        }
        director.tick(now)
        deps.presenter.present(director.view(now), now)
        framesPresented += 1
    }

    private fun afterCommand(now: Double) {
        val shown = director.shownUpdateVersion
        if (shown != persistedUpdateVersion) {
            persistedUpdateVersion = shown
            deps.keyValueStore.putString(SHOWN_UPDATE_VERSION_KEY, shown)
        }
        _availability.value = director.availability(now)
    }

    private fun monoSeconds(): Double = deps.monotonic.elapsedNanos() / 1_000_000_000.0

    private fun wallSeconds(): Double = deps.clock.now().toEpochMilliseconds() / 1000.0
}
