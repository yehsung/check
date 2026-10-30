// 원본: 없음(새 코드) — W-windows-resume W-6 #6(조립 구조: wiring/{…}Wiring.kt 로 나눠 각자 가짜로 시험, 마지막에 AppGraph·Main 이 묶는다 ·
//       종료 훅 꼬리 = 업데이트 Registration close → tray.remove()) · W-6 #1(poke 깃발 — 껍데기는 찌르기 poller 를 만들지 않는다) ·
//       갈래 보고 coordinator_patches: W3-c0(SharedFlyoutPageHost·MessagesBackgroundRefresh·안 읽음 점) · W3-c1(FlyoutWindow·FlyoutController·
//       트레이 클릭·TrayPresenter·InstanceActivation·ShellNotifier) · W3-c5(DesktopUpdateChecker — 스토어와 같은 SupabaseWorkService) ·
//       W1-f2(테마 = tray.currentTheme + addThemeListener, 풍선 = tray 가 BalloonNotifier) · W4-f(FlyoutRoute.Shop/Missions → 페이지)
//
// 껍데기 한 벌을 의존 묶음([ShellDeps])에서 만든다. 창·OS 는 문([FlyoutWindowPort]·[TaskbarThemeSource]·TrayHost)으로만 만진다 —
// 시험은 가짜 문으로 창 0 에서 한 바퀴 돈다. 게임 창과는 서로를 늦게 묶는다([LateGameWindows] — 게임 배선이 플라이아웃 문을 받는다).
package com.yehsung.aingcheck.desktop.wiring

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.MonotonicClock
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayClick
import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayHost
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.format.WorkStatusSnapshot
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionProfile
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.SessionText
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.stores.characters.AppUserCharacterStore
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.rankings.RankingsStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.wire.models.AppUserCharacterDirectory
import com.yehsung.aingcheck.desktop.pages.missions.MissionsFlyoutPage
import com.yehsung.aingcheck.desktop.pages.onboarding.FirstRunOnboarding
import com.yehsung.aingcheck.desktop.pages.shared.RoutePages
import com.yehsung.aingcheck.desktop.pages.shared.MessagesBackgroundRefresh
import com.yehsung.aingcheck.desktop.pages.shared.MessagesUnreadDot
import com.yehsung.aingcheck.desktop.pages.shared.SharedFlyoutPageHost
import com.yehsung.aingcheck.desktop.pages.shared.SharedPage
import com.yehsung.aingcheck.desktop.pages.shared.SharedPagesDeps
import com.yehsung.aingcheck.desktop.pages.shop.ShopFlyoutPage
import com.yehsung.aingcheck.desktop.platform.windows.flyout.FlyoutPlacement
import com.yehsung.aingcheck.desktop.platform.windows.flyout.FlyoutPlacer
import com.yehsung.aingcheck.desktop.platform.windows.tray.TaskbarTheme
import com.yehsung.aingcheck.desktop.platform.windows.tray.WindowsTrayHost
import com.yehsung.aingcheck.desktop.shell.flyout.FlyoutComposeContent
import com.yehsung.aingcheck.desktop.shell.flyout.FlyoutController
import com.yehsung.aingcheck.desktop.shell.flyout.FlyoutIconLocator
import com.yehsung.aingcheck.desktop.shell.flyout.FlyoutScreen
import com.yehsung.aingcheck.desktop.shell.flyout.FlyoutSurface
import com.yehsung.aingcheck.desktop.shell.flyout.FlyoutWindow
import com.yehsung.aingcheck.desktop.shell.instance.InstanceActivation
import com.yehsung.aingcheck.desktop.shell.notify.ShellNotice
import com.yehsung.aingcheck.desktop.shell.notify.ShellNotifier
import com.yehsung.aingcheck.desktop.shell.tray.TrayDotReasons
import com.yehsung.aingcheck.desktop.shell.tray.TrayMenuActions
import com.yehsung.aingcheck.desktop.shell.tray.TrayMenuModel
import com.yehsung.aingcheck.desktop.shell.tray.TrayMenuPresenter
import com.yehsung.aingcheck.desktop.shell.tray.TrayPresenter
import com.yehsung.aingcheck.desktop.shell.update.DesktopUpdateChecker
import com.yehsung.aingcheck.desktop.shell.update.ServiceUpdateRpc
import com.yehsung.aingcheck.desktop.shell.update.StoreUpdateDestination
import com.yehsung.aingcheck.desktop.shell.update.UpdatePollSchedule
import com.yehsung.aingcheck.desktop.shell.update.UpdateRpc
import com.yehsung.aingcheck.desktop.shellapi.BalloonNotifier
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.NotifyContext
import com.yehsung.aingcheck.desktop.shellapi.NotifyKind
import com.yehsung.aingcheck.desktop.shellapi.NotifySurface
import com.yehsung.aingcheck.desktop.windows.kit.DesktopGameWindows
import com.yehsung.aingcheck.desktop.windows.kit.DuelInviteNotice
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.screens.rankings.RankingsMyFace
import com.yehsung.aingcheck.ui.screens.session.UpdateRequiredScreen
import com.yehsung.aingcheck.ui.screens.session.kit.LocalAppUserCharacters
import com.yehsung.aingcheck.ui.screens.settingscommon.AppearanceStore
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import java.util.concurrent.Executor

/** 플라이아웃 창 한 장의 문. Windows = [SwingFlyoutWindowPort](FlyoutWindow), 시험 = 가짜(창 0). */
interface FlyoutWindowPort : FlyoutSurface {
    /** 페이지 호스트·컨트롤러를 창에 붙인다(내용 · 비활성화 → 닫기 · Esc). */
    fun attach(pages: FlyoutPageHost, nav: FlyoutController)

    /** 첫 클릭 지연을 없애려 창을 미리 만든다(보이지 않음). */
    fun precreate()
}

/** W3-c1 조립 그대로: setContent(FlyoutComposeContent.create(…)) · onDeactivated · onEscape · precreate. EDT 에서 만든다. */
class SwingFlyoutWindowPort(private val window: FlyoutWindow = FlyoutWindow()) : FlyoutWindowPort {
    override fun show(placement: FlyoutPlacement) = window.show(placement)
    override fun hide() = window.hide()
    override fun attach(pages: FlyoutPageHost, nav: FlyoutController) {
        window.setContent(FlyoutComposeContent.create(pages, nav, { nav.widthDip }, nav::onContentHeight))
        window.onDeactivated = nav::onDeactivated
        window.onEscape = nav::onEscape
    }

    override fun precreate() = window.precreate()
}

/** 작업 표시줄 테마(W1-f2). Windows 트레이는 WM_SETTINGCHANGE(ImmersiveColorSet)로 알린다. */
interface TaskbarThemeSource {
    fun current(): TaskbarTheme
    fun addListener(listener: (TaskbarTheme) -> Unit): Registration

    companion object {
        /** WindowsTrayHost 면 그 테마 길, 아니면 고정(어두움 — Windows 11 기본 작업 표시줄). */
        fun of(tray: TrayHost): TaskbarThemeSource = if (tray is WindowsTrayHost) {
            object : TaskbarThemeSource {
                override fun current(): TaskbarTheme = tray.currentTheme()
                override fun addListener(listener: (TaskbarTheme) -> Unit): Registration = tray.addThemeListener(listener)
            }
        } else {
            fixed(TaskbarTheme.DARK)
        }

        fun fixed(theme: TaskbarTheme): TaskbarThemeSource = object : TaskbarThemeSource {
            override fun current(): TaskbarTheme = theme
            override fun addListener(listener: (TaskbarTheme) -> Unit): Registration = Registration {}
        }
    }
}

/** 점 사유 중 대결 신청 셋(게임 스토어가 아는 값 — 조립 전엔 없음). duels 깃발은 [TrayDotReasons.of] 가 건다. */
data class InviteDots(val gomoku: Boolean = false, val chess: Boolean = false, val tetris: Boolean = false) {
    companion object {
        val NONE = InviteDots()

        /**
         * 맥 CheckApp.swift:55-80 점 사유 배선 그대로: 오목 = pendingIncomingInvites 비지 않음 · 체스 = visibleIncoming · 테트리스 = visibleIncoming.
         * 스토어 값은 Compose 상태라 snapshotFlow 로 읽는다(MessagesUnreadDot 과 같은 길). duels 깃발은 [TrayDotReasons.of] 가 건다.
         */
        fun from(gomoku: GomokuStore, chess: ChessStore, tetris: TetrisDuelStore): Flow<InviteDots> = snapshotFlow {
            InviteDots(
                gomoku = gomoku.pendingIncomingInvites.isNotEmpty(),
                chess = chess.visibleIncoming != null,
                tetris = tetris.visibleIncoming != null,
            )
        }.distinctUntilChanged()
    }
}

/**
 * 껍데기 의존 묶음. 이름·타입은 AppGraph 그대로(platform.tray·platform.power · clientIdentity · desktopConfig · monotonic).
 * 스토어(세션·메시지·순위·나)는 이미 지은 것을 받는다 — 서비스를 하나 더 만들지 않는다(W3-c5: 스토어와 같은 [service]).
 */
data class ShellDeps(
    val session: SessionStore,
    val sessionContext: SessionContext,
    val service: SupabaseWorkService,
    val messages: MessagesStore,
    val rankings: RankingsStore,
    val me: MeStore,
    val appearance: AppearanceStore,
    val desktopConfig: DesktopAppConfig,
    val clientIdentity: ClientIdentity,
    /** 기기 단위 설정(사용자 id 섞지 않음 — 공지 닫음 기억). */
    val deviceStore: DesktopKeyValueStore,
    val monotonic: MonotonicClock,
    /** 앱 범위(업데이트 조회기가 지을 때 받는다). [ShellWiring.start] 도 기본으로 이 범위에서 돈다. */
    val scope: CoroutineScope,
    val tray: TrayHost,
    val power: PowerEvents,
    /** 근무 상태(WorkWiring 의 DesktopWorkSnapshot → WorkStatusSnapshot, 조정 ⑩). */
    val work: StateFlow<WorkStatusSnapshot>,
    /** 트레이 메뉴 '근무 시작/종료'(WorkWiring commands::toggle). */
    val toggleWork: () -> Unit,
    /** 트레이 메뉴 '종료'(Main 의 평소 종료 절차). */
    val quit: () -> Unit,
    /** 창을 만질 스레드(Windows = Swing EDT). 트레이 왼쪽 클릭은 비활성화 사건과 같은 EDT 순서로(300ms 가드 전제). */
    val events: Executor,
    val window: FlyoutWindowPort,
    /** 화면 사실(Windows = TaskbarProbe::probe). */
    val screen: FlyoutScreen,
    val iconLocator: FlyoutIconLocator = FlyoutIconLocator { null },
    /** 게임 창(GamesWiring). 서로를 늦게 묶는다 — 누를 때 읽는다. */
    val gameWindows: () -> DesktopGameWindows = { DesktopGameWindows.None },
    /** 오른쪽 클릭 메뉴(Windows = NativeTrayMenu(messageThread)). null 이면 메뉴 없음. */
    val menu: TrayMenuPresenter? = null,
    /** 두 번째 실행 신호 길(Windows = { InstanceSignal.listen(messageThread, events, it) }). null 이면 듣지 않는다. */
    val instanceListen: ((onActivate: () -> Unit) -> Registration)? = null,
    val theme: TaskbarThemeSource = TaskbarThemeSource.of(tray),
    /** 풍선(W1-f2: WindowsTrayHost 가 구현, 비-Windows 는 None). */
    val balloon: BalloonNotifier = (tray as? BalloonNotifier) ?: BalloonNotifier.None,
    /** 말풍선(W5-b 오버레이 — OverlayWiring). 띄웠으면 true. */
    val bubble: (ShellNotice) -> Boolean = { false },
    /** SM_CXSMICON(물리 픽셀) — Windows = TrayIconRenderer.sizeForScalePercent(배율). */
    val trayIconSizePx: () -> Int = { DEFAULT_TRAY_ICON_PX },
    val reduceMotion: () -> Boolean = { false },
    val rankingsFace: () -> RankingsMyFace,
    val rubyBalance: () -> Long? = { null },
    val openUrl: (String) -> Unit = {},
    val share: (String) -> Unit = {},
    val inviteDots: Flow<InviteDots> = flowOf(InviteDots.NONE),
    val updateRpc: UpdateRpc = ServiceUpdateRpc(service, clientIdentity.platform.wire),
    val updateSchedule: UpdatePollSchedule = UpdatePollSchedule.DEFAULT,
    val messagesRefreshIntervalMillis: Long = MessagesBackgroundRefresh.INTERVAL_SECONDS * 1000,
    /**
     * 착용 캐릭터 표(W-8 3차 — 안드로이드 AingShell:162 와 같은 자리). 기본은 여기서 짓는다(세션 문맥 · 앱 범위 · 초상 번들 id) —
     * 로그인 직후 한 번 · 플라이아웃을 열 때 60초 스로틀 · 로그아웃 reset · 내 착용값 즉시 반영은 [ShellWiring.start] 가 건다.
     */
    val characters: AppUserCharacterStore = AppUserCharacterStore(sessionContext, scope, CharacterArt.portraitIds),
    /** 알림 표면 고르기 사실(오버레이 보임·전체화면·집중·토스트). 조립 전 기본 = 오버레이 없음 · 토스트 켬. */
    val notifyContext: () -> NotifyContext = { DEFAULT_NOTIFY_CONTEXT },
    /** 울트라 화면을 떠났다(조립: `{ social.onUltraPageLeft() }` — 맥 closeShopPanel 의 shopNotice = nil). */
    val onUltraPageLeft: () -> Unit = {},
    /** 최소 빌드 미달 화면의 [업데이트] 목적지(W-13 #7). null 이면 단추 숨김(공용 화면 그대로). */
    val storeUpdateDestination: String? = StoreUpdateDestination.windows,
    /**
     * int-w2 3차 페이지·첫 실행(PagesWiring.routePages · firstRun). 상점·미션이 비어 있으면 여기서 W4-f 페이지로 채워 **공용 호스트의
     * 본문 자리**(레일 옆)에 꽂는다 — 맥 CheckMenuView.swift:421-429 · 762-799 · 1002-1010 @ db93317f(미션·상점도 본문 열 안, 레일은 옆에 선다).
     */
    val routePages: RoutePages = RoutePages.NONE,
    val firstRun: FirstRunOnboarding? = null,
) {
    companion object {
        const val DEFAULT_TRAY_ICON_PX = 16
        val DEFAULT_NOTIFY_CONTEXT = NotifyContext(
            overlayVisible = false, fullscreenQuiet = false, bubbleAllowedByFocus = true, toastEnabled = true,
        )
    }
}

/** 지은 것들. AppGraph·Main·다른 배선이 이 손잡이로 잇는다(알림 → [notifier], 게임 배선 → [nav]). */
data class ShellHandle(
    val nav: FlyoutController,
    val pages: ShellPageHost,
    val sharedPages: SharedFlyoutPageHost,
    val notifier: ShellNotifier,
    val updateChecker: DesktopUpdateChecker,
    val messagesRefresh: MessagesBackgroundRefresh,
    val trayPresenter: TrayPresenter,
    val menuActions: TrayMenuActions,
    val theme: StateFlow<TaskbarTheme>,
    /** 트레이 점 사유(안 읽음 · 대결 신청(duels) · 업데이트). [ShellWiring.start] 뒤에 흐른다. */
    val dots: StateFlow<TrayDotReasons>,
    /** 착용 캐릭터 표(게임 배선이 `{ characters.directory }` 로 받는다). */
    val characters: AppUserCharacterStore,
    /** 받은 대결 신청 → 알림 한 문(게임 배선 GamesDeps.onInviteNotice). duels=false 면 notifier 가 거른다. */
    val notifyDuelInvite: (DuelInviteNotice) -> NotifySurface?,
)

class ShellWiring(private val deps: ShellDeps) {
    private val nav = FlyoutController(
        surface = deps.window,
        screen = deps.screen,
        icon = deps.iconLocator,
        clock = { deps.monotonic.elapsedNanos() / NANOS_PER_MILLI },
        requestedWidthDip = { ShellWidths.requested(deps.session.phaseFlow.value, deps.session.profileFlow.value) },
    )
    private val gameWindows = LateGameWindows(deps.gameWindows)
    private val sharedPages = SharedFlyoutPageHost(
        SharedPagesDeps(
            session = deps.session,
            sessionContext = deps.sessionContext,
            messages = deps.messages,
            rankings = deps.rankings,
            me = deps.me,
            appearance = deps.appearance,
            config = deps.desktopConfig,
            currentBuild = deps.clientIdentity.build,
            rankingsFace = deps.rankingsFace,
            rubyBalance = deps.rubyBalance,
            openMiniGame = { gameWindows.openGames() },
            openUrl = deps.openUrl,
            share = deps.share,
            routePages = deps.routePages.withShellPages(
                shop = ShopFlyoutPage(deps.me, gameWindows),
                missions = MissionsFlyoutPage(deps.me, deps.reduceMotion),
            ),
            firstRun = deps.firstRun,
        ),
    )

    /** 상점·미션은 공용 호스트 본문(레일 옆)이 그린다 — 전체 폭 덮개는 Store 업데이트 화면만 남는다(W-13 #9). */
    private val pages = ShellPageHost(
        shared = sharedPages,
        shop = null,
        missions = null,
        appearance = deps.appearance,
        characters = { deps.characters.directory },
        update = ShellUpdatePage(deps.storeUpdateDestination, deps.clientIdentity.build, deps.openUrl),
    )
    private val notifier = ShellNotifier(deps.desktopConfig, deps.balloon, nav, deps.bubble)
    private val updateChecker = DesktopUpdateChecker(
        deps.updateRpc, deps.clientIdentity.build, deps.deviceStore, deps.scope, deps.monotonic, deps.updateSchedule,
    )
    private val messagesRefresh = MessagesBackgroundRefresh(
        signedIn = deps.session.phaseFlow.map { it == SessionPhase.SignedIn },
        refresh = { deps.messages.requestActivityRefresh() },
        onSignedOut = { deps.messages.reset() },
        intervalMillis = deps.messagesRefreshIntervalMillis,
    )
    private val trayPresenter = TrayPresenter(deps.tray, deps.trayIconSizePx) { deps.monotonic.elapsedNanos() / NANOS_PER_MILLI }
    private val menuActions = TrayMenuActions(deps.toggleWork, nav, deps.quit)
    private val themeState = MutableStateFlow(TaskbarTheme.DARK)
    private val dotsState = MutableStateFlow(TrayDotReasons())

    val handle = ShellHandle(
        nav, pages, sharedPages, notifier, updateChecker, messagesRefresh, trayPresenter, menuActions, themeState.asStateFlow(),
        dotsState.asStateFlow(), deps.characters, ::notifyDuelInvite,
    )

    /** 받은 대결 신청 한 건 → 알림 중재(말풍선/풍선/점). 깃발(duels)은 notifier 가 한 번 더 본다. 띄운 표면(꺼졌으면 null). */
    fun notifyDuelInvite(invite: DuelInviteNotice): NotifySurface? =
        notifier.deliver(ShellNotice(NotifyKind.DUEL_INVITE, invite.title, invite.body), deps.notifyContext())

    private val jobs = mutableListOf<Job>()
    private val registrations = mutableListOf<Registration>()
    private var updatePower: Registration? = null
    private var started = false

    /** 창에 페이지를 붙이고(미리 만들기까지) 구독·주기 조회·트레이를 켠다. 두 번 불러도 한 번. */
    fun start(scope: CoroutineScope = deps.scope) {
        if (started) return
        started = true
        deps.window.attach(pages, nav)
        deps.window.precreate()

        themeState.value = deps.theme.current()
        registrations += deps.theme.addListener { themeState.value = it }

        jobs += scope.launch {
            combine(
                MessagesUnreadDot.flow { deps.messages.badgeCount },
                updateChecker.state,
                deps.inviteDots,
            ) { unread, update, invites ->
                TrayDotReasons.of(
                    flags = deps.desktopConfig,
                    unreadMessageCount = if (unread) 1 else 0,
                    gomokuInvite = invites.gomoku,
                    chessInvite = invites.chess,
                    tetrisInvite = invites.tetris,
                    update = update,
                )
            }.collect { dotsState.value = it }
        }
        jobs += trayPresenter.start(scope, deps.work, dotsState.asStateFlow(), themeState.asStateFlow())

        registrations += deps.tray.addClickListener { click, x, y -> onTrayClick(click, x, y) }
        deps.instanceListen?.let { listen -> registrations += InstanceActivation.bind(listen, nav) }

        jobs += messagesRefresh.start(scope)
        jobs += startCharacters(scope)
        // W3-c3 nice: 울트라 화면이 보이다가 안 보이게 되면(다른 화면 · 플라이아웃 닫힘) 구매 안내를 지운다.
        jobs += scope.launch {
            var wasUltra = false
            combine(nav.route, nav.visible) { route, visible -> visible && route == FlyoutRoute.Ultra }.distinctUntilChanged().collect { ultra ->
                if (wasUltra && !ultra) deps.onUltraPageLeft()
                wasUltra = ultra
            }
        }
        // W3-c5: 플라이아웃이 열릴 때마다 조회(60초 스로틀은 조회기 안).
        jobs += scope.launch { nav.visible.filter { it }.collect { updateChecker.onFlyoutOpened() } }
        updateChecker.startWatch()
        updatePower = updateChecker.attach(deps.power)
    }

    /**
     * 캐릭터 표 수명(폰 PhoneAppModel.kt:335 refresh · :360 reset · :240/:370 refreshIfStale · PhoneContext.kt:141 noteMyEquipped 와 같은 자리).
     * 새 폴링 없음 — 로그인 직후 한 번, 플라이아웃을 열 때마다 60초 스로틀, 로그아웃·계정 전환이면 reset.
     */
    private fun startCharacters(scope: CoroutineScope): Job = scope.launch {
        launch {
            var last: String? = null
            deps.session.profileFlow.map { it?.userID }.distinctUntilChanged().collect { uid ->
                if (uid == last) return@collect
                if (last != null) deps.characters.reset()
                last = uid
                if (uid != null) deps.characters.refresh()
            }
        }
        launch { nav.visible.filter { it }.collect { deps.characters.refreshIfStale() } }
        launch {
            snapshotFlow { if (deps.me.equippedLoaded) Equipped(deps.me.equippedServerID) else null }
                .distinctUntilChanged()
                .collect { mine -> if (mine != null) deps.characters.noteMyEquipped(mine.serverID) }
        }
    }

    private data class Equipped(val serverID: String?)

    /** 트레이 클릭: 왼쪽 = EDT 에서 열기/닫기, 오른쪽 = 메시지 스레드에서 바로 메뉴(W3-c1). */
    private fun onTrayClick(click: TrayClick, x: Int, y: Int) {
        when (click) {
            TrayClick.PRIMARY -> deps.events.execute { nav.onTrayPrimaryClick(x, y) }
            TrayClick.SECONDARY -> {
                val menu = deps.menu ?: return
                val signedIn = deps.session.phaseFlow.value == SessionPhase.SignedIn
                menuActions.onSecondaryClick(menu, TrayMenuModel.items(deps.work.value, signedIn), x, y)
            }
            TrayClick.DOUBLE -> Unit
        }
    }

    /**
     * 걷기. 종료 훅에서는 **맨 끝**에 부른다(W-6 #6: … → 실시간 shutdown() → 업데이트 Registration close → tray.remove()).
     * 안 순서: 구독·주기 작업 취소 → 클릭·테마·두 번째 실행 해제 → 업데이트 주기 멈춤 + 전원 Registration close → 플라이아웃 닫기 → tray.remove().
     */
    fun stop() {
        if (!started) return
        started = false
        jobs.forEach { it.cancel() }
        jobs.clear()
        registrations.forEach { it.close() }
        registrations.clear()
        updateChecker.stopWatch()
        updatePower?.close()
        updatePower = null
        deps.events.execute { nav.hide() }
        deps.tray.remove()
    }

    companion object {
        private const val NANOS_PER_MILLI = 1_000_000L
    }
}

/** 원하는 플라이아웃 폭(W3-c1): 로그인 화면 · 무소속이면 좁은 폭(340), 나머지는 기본(414). */
object ShellWidths {
    fun requested(phase: SessionPhase, profile: SessionProfile?): Double = when {
        phase == SessionPhase.SignedOut -> FlyoutPlacer.NARROW_WIDTH_DIP
        phase == SessionPhase.SignedIn && profile != null && profile.teamID == null -> FlyoutPlacer.NARROW_WIDTH_DIP
        else -> FlyoutPlacer.WIDTH_DIP
    }
}

/** 공용 페이지 위에 올리는 갈래 페이지(W4-f). 세션·소속·깃발 판정은 공용 라우터가 먼저 한다 — 로그아웃이면 상점도 로그인 화면이다. */
enum class ShellOverlayPage { SHOP, MISSIONS, UPDATE }

object ShellPages {
    /**
     * [storeDestination] 이 있으면 최소 빌드 미달 화면을 [업데이트] 단추가 있는 판으로 덮는다(W-13 #7 — 공용 화면은 AppLinks(WINDOWS)=null 이라
     * 단추를 숨긴다). 없으면 공용 화면 그대로.
     */
    fun overlayFor(page: SharedPage, storeDestination: String? = null): ShellOverlayPage? = when {
        page is SharedPage.Pending && page.route == FlyoutRoute.Shop -> ShellOverlayPage.SHOP
        page == SharedPage.Missions -> ShellOverlayPage.MISSIONS
        page is SharedPage.NeedsUpdate && storeDestination != null -> ShellOverlayPage.UPDATE
        else -> null
    }
}

/** 최소 빌드 미달 화면 + Store 단추(W-13 #7). 문구는 공용 SessionText(WINDOWS) 그대로, 목적지만 Store 제품 페이지. */
class ShellUpdatePage(val destination: String?, private val currentBuild: Long, private val openUrl: (String) -> Unit) {
    @Composable
    fun Content(minBuild: Long) {
        val target = destination ?: return
        UpdateRequiredScreen(
            minBuild = minBuild,
            currentBuild = currentBuild,
            body = SessionText.updateBody(ClientPlatform.WINDOWS),
            buttonTitle = SessionText.updateButton(ClientPlatform.WINDOWS),
            onOpenStore = { openUrl(target) },
        )
    }
}

/**
 * 플라이아웃 페이지 라우터(W4-f C3): FlyoutRoute.Shop → ShopFlyoutPage, FlyoutRoute.Missions → MissionsFlyoutPage, 나머지 → 공용 호스트.
 * 공용 호스트는 늘 그린다(수명 고리 — 메시지 활성·순위 탭 — 가 페이지를 오가도 끊기지 않게). 갈래 페이지는 그 위를 덮는다.
 */
class ShellPageHost(
    private val shared: SharedFlyoutPageHost,
    /** null 이면 덮지 않는다(공용 호스트가 [RoutePages] 로 본문 자리에 그린다 — int-w2 조립). */
    private val shop: FlyoutPageHost?,
    private val missions: FlyoutPageHost?,
    private val appearance: AppearanceStore,
    /** 착용 캐릭터 표(LocalAppUserCharacters — 메시지·순위·콕 아바타). Compose 상태를 읽는 람다. */
    private val characters: () -> AppUserCharacterDirectory = { AppUserCharacterDirectory(CharacterArt.portraitIds) },
    private val update: ShellUpdatePage = ShellUpdatePage(null, 0) {},
) : FlyoutPageHost {
    @Composable
    override fun Content(nav: FlyoutNavigator, widthDip: Double) {
        CompositionLocalProvider(LocalAppUserCharacters provides characters()) { Pages(nav, widthDip) }
    }

    @Composable
    private fun Pages(nav: FlyoutNavigator, widthDip: Double) {
        val pageFlow = remember(nav) { shared.pages(nav) }
        val page by pageFlow.collectAsState(SharedPage.Launching)
        val visible by nav.visible.collectAsState()
        Box {
            shared.Content(nav, widthDip)
            val overlay = (if (visible) ShellPages.overlayFor(page, update.destination) else null)?.takeIf {
                when (it) {
                    ShellOverlayPage.SHOP -> shop != null
                    ShellOverlayPage.MISSIONS -> missions != null
                    ShellOverlayPage.UPDATE -> true
                }
            }
            if (overlay != null) {
                AingTheme(appearance.mode) {
                    Box(Modifier.width(widthDip.dp).fillMaxHeight().background(AingTheme.colors.background)) {
                        when (overlay) {
                            ShellOverlayPage.SHOP -> shop?.Content(nav, widthDip)
                            ShellOverlayPage.MISSIONS -> missions?.Content(nav, widthDip)
                            ShellOverlayPage.UPDATE -> (page as? SharedPage.NeedsUpdate)?.let { update.Content(it.minBuild) }
                        }
                    }
                }
            }
        }
    }
}

/** 비어 있는 상점·미션 자리만 껍데기 페이지로 채운 사본([RoutePages] 는 값 묶음 — 나머지 칸은 그대로). */
fun RoutePages.withShellPages(shop: FlyoutPageHost, missions: FlyoutPageHost): RoutePages = RoutePages(
    home = home,
    pokeList = pokeList,
    ultra = ultra,
    aiTokens = aiTokens,
    aiLimits = aiLimits,
    devices = devices,
    desktopSettings = desktopSettings,
    shop = this.shop ?: shop,
    missions = this.missions ?: missions,
    runtimeShown = runtimeShown,
)

/** 늦게 묶는 게임 창 문 — 껍데기와 게임 배선이 서로를 받기 때문(부를 때 [target] 을 읽는다). */
class LateGameWindows(private val target: () -> DesktopGameWindows) : DesktopGameWindows {
    override fun openGames(kind: MiniGameKind?) = target().openGames(kind)
    override fun openGomoku(focusMatchID: String?) = target().openGomoku(focusMatchID)
    override fun openChess(focusMatchID: String?) = target().openChess(focusMatchID)
    override fun openTetrisDuel(focusMatchID: String?) = target().openTetrisDuel(focusMatchID)
    override fun openGacha() = target().openGacha()
    override fun openCakeGift() = target().openCakeGift()
    override fun closeAll() = target().closeAll()
}
