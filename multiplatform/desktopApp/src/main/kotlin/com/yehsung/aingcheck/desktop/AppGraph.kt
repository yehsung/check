// 원본: 없음(새 코드) — G K11(조립 지점: W1-f 가 뼈대, 이후 조정자만) · A§2(의존 주입은 손으로 — 생성자 주입 + 플랫폼별 AppGraph,
// Koin·Hilt 를 쓰지 않는다) · D§2-1(각 OS 기능은 인터페이스 뒤)
//
// 플랫폼 묶음 + 시계 + 빌드 신원 + HTTP 엔진 팩토리 한 자리 + 본 통합(W-6 #6) 조립: [AppGraph.assemble] 이 세션·스토어와 배선 여섯
// (work·social·overlay·tokens·shell·games — desktopApp/…/wiring)을 생성자 주입으로 묶는다. OS·창·도구 몫은 [AppSeams](Windows 는
// Main 이 채우고 시험은 가짜). 종료 순서는 [AppWirings.shutdownSteps] 한 벌(W-6 #6)을 [ShutdownSequence] 가 상한 안에서 돈다.
@file:OptIn(ExperimentalTime::class)

package com.yehsung.aingcheck.desktop

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.MonotonicClock
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.core.foundation.platform.desktop.AppPaths
import com.yehsung.aingcheck.core.foundation.platform.desktop.EnvReader
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyService
import com.yehsung.aingcheck.core.foundation.platform.desktop.IdleSource
import com.yehsung.aingcheck.core.foundation.platform.desktop.LoginItem
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayHost
import com.yehsung.aingcheck.desktop.generated.BuildIdentity
import com.yehsung.aingcheck.desktop.generated.DesktopFlags
import com.yehsung.aingcheck.desktop.generated.ProdConfig
import com.yehsung.aingcheck.desktop.http.HttpEngineFactory
import com.yehsung.aingcheck.desktop.platform.windows.identity.WindowsDeviceIdentity
import com.yehsung.aingcheck.desktop.wiring.WindowsDeviceRegistration
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.RunningTests
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.realtime.KtorRealtimeTransport
import com.yehsung.aingcheck.core.rules.format.WorkStatusSnapshot
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.games.GamesContext
import com.yehsung.aingcheck.core.stores.games.GamesDestination
import com.yehsung.aingcheck.core.stores.games.GamesRouter
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.gomoku.SessionGomokuHost
import com.yehsung.aingcheck.core.stores.me.MeContext
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.RubyBalanceCell
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.NaturalKoNameCollation
import com.yehsung.aingcheck.core.stores.rankings.RankingsStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStoreHost
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.rules.format.WorkStatus
import com.yehsung.aingcheck.desktop.overlay.engine.BubbleTextMeasure
import com.yehsung.aingcheck.desktop.overlay.engine.CharacterSink
import com.yehsung.aingcheck.desktop.overlay.engine.PointerOutcome
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.desktop.shell.flyout.FlyoutIconLocator
import com.yehsung.aingcheck.desktop.shell.flyout.FlyoutScreen
import com.yehsung.aingcheck.desktop.shell.tray.TrayMenuPresenter
import com.yehsung.aingcheck.desktop.wiring.FlyoutWindowPort
import com.yehsung.aingcheck.desktop.wiring.GameWindowFactory
import com.yehsung.aingcheck.desktop.wiring.GamesDeps
import com.yehsung.aingcheck.desktop.wiring.GamesWiring
import com.yehsung.aingcheck.desktop.wiring.OverlayPresenter
import com.yehsung.aingcheck.desktop.wiring.OverlayWiring
import com.yehsung.aingcheck.desktop.wiring.OverlayWiringDeps
import com.yehsung.aingcheck.desktop.wiring.ShellDeps
import com.yehsung.aingcheck.desktop.wiring.ShellWiring
import com.yehsung.aingcheck.desktop.wiring.SocialDeps
import com.yehsung.aingcheck.desktop.wiring.SocialWiring
import com.yehsung.aingcheck.desktop.wiring.TokensWiring
import com.yehsung.aingcheck.desktop.wiring.TokensWiringDeps
import com.yehsung.aingcheck.desktop.wiring.WorkDeps
import com.yehsung.aingcheck.desktop.wiring.WorkWiring
import com.yehsung.aingcheck.feature.desktop.DesktopAiHomes
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitRunner
import com.yehsung.aingcheck.feature.desktop.poke.MessagesStoreConsumedRowsSink
import com.yehsung.aingcheck.feature.desktop.realtime.MessagesStoreRealtimeMessages
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexProbeResult
import com.yehsung.aingcheck.feature.desktop.tokens.diag.CodexUsageDiagnostics
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.ui.games.chess.ChessGamesLink
import com.yehsung.aingcheck.ui.games.gomoku.GomokuGamesLink
import com.yehsung.aingcheck.ui.screens.rankings.RankingsScreenRules
import com.yehsung.aingcheck.ui.screens.settingscommon.AppearanceStore
import io.ktor.client.HttpClient
import io.ktor.client.HttpClientConfig
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.nio.file.Path
import java.util.UUID
import java.util.concurrent.Executor
import kotlin.coroutines.CoroutineContext
import kotlin.time.Clock
import kotlin.time.ExperimentalTime

/** K3 데스크톱 인터페이스 묶음. Windows 는 WindowsPlatform 이 채우고, 시험은 가짜로 채운다. */
interface DesktopPlatform {
    val paths: AppPaths
    val env: EnvReader
    val tokenVault: TokenVault
    val installationIdentity: InstallationIdentity
    val singleInstance: SingleInstanceGuard
    val tray: TrayHost
    val hotkeys: HotkeyService
    val idle: IdleSource
    val power: PowerEvents
    val session: SessionEvents
    /** MSI 판 Run 키. MSIX 는 StartupTask 라 null(D§5-5). */
    val loginItem: LoginItem?
}

class AppGraph(
    val platform: DesktopPlatform,
    /** 벽시계는 여기(앱 조립 지점)에서만 System 을 쓴다(구조 시험 R2). 아래 층은 주입받는다. */
    val clock: Clock = Clock.System,
    val monotonic: MonotonicClock = SystemMonotonicClock,
    val clientIdentity: ClientIdentity = ClientIdentity.fromGenerated(BuildIdentity.PLATFORM, BuildIdentity.BUILD, BuildIdentity.VERSION),
    /** Windows 기능 깃발(W-3 #17). 앱은 생성 상수에서, 시험은 값을 넣는다. */
    val desktopConfig: DesktopAppConfig = DesktopAppConfig.fromBuild(),
    /** 서버 주소·anon 키. 앱은 생성 상수 ProdConfig, 시험은 `.invalid` 주소(망 봉인 — MockEngine 만 받는다). */
    val backend: Backend = Backend(ProdConfig.SUPABASE_URL, ProdConfig.SUPABASE_ANON_KEY.takeIf { it.isNotEmpty() }),
    /** 제보에 싣는 OS 표시값(AppInfo.osVersion). */
    val osVersion: String = "Windows ${System.getProperty("os.version").orEmpty()}".trim(),
    /** HTTP 클라이언트를 만드는 단 하나의 문. 앱은 [HttpEngineFactory], 시험은 MockEngine 클라이언트(시험 소스에서). */
    private val httpFactory: (HttpClientConfig<*>.() -> Unit) -> HttpClient = { configure -> HttpEngineFactory.ktorClient(configure) },
) {
    data class Backend(val projectURL: String, val anonKey: String?)

    /** 세션 문맥의 AppConfig(duelsEnabled 등)는 desktopConfig 에서만 만든다(W-3 #17 — 다른 곳에서 깃발을 다시 적지 않는다). */
    val appConfig: AppConfig get() = desktopConfig.toAppConfig()

    /**
     * 서버 `device_id`(K6) = `'win:'` + 소문자 installation_id. 신원을 확인하지 못했으면 null — 이때 기기 단위 쓰기(토큰 업로드 등)는
     * 하지 않는다(G §5-1 #6, 기억 device-identity-must-not-be-invented). 부르는 쪽(W2-g·h)은 null 을 '건너뜀'으로 다룬다.
     */
    val deviceId: String? get() = WindowsDeviceIdentity.deviceId(platform.installationIdentity.installationId())

    /** 서버 `client_devices.installation_id`(uuid). */
    val installationId: String? get() = platform.installationIdentity.installationId()

    /** HTTP 클라이언트는 단일 팩토리에서만(G §8-12 · 구조 시험 R3c). */
    fun httpClient(configure: HttpClientConfig<*>.() -> Unit = {}): HttpClient = httpFactory(configure)

    /**
     * 본 통합 조립(W-6 #6). [scope] 는 UI 한 줄기(앱 = Swing EDT, 시험 = 시험 디스패처) — 스토어·근무 상태는 이 줄기에서만 돈다.
     * EDT 에서 부른다(FlyoutWindow·게임 창 생성자가 EDT 를 요구 — W-shell-games). 만들기만 하고 돌리지 않는다 → [AppWirings.start].
     */
    fun assemble(seams: AppSeams, scope: CoroutineScope): AppWirings = AppWirings(this, seams, scope)
}

/**
 * OS·창·도구 몫(조립 지점 밖 — Windows 는 Main 이 실물로, 시험은 가짜로 채운다). 기본값은 '없음'(그리지 않음·창 없음·호출 0).
 * [mainDispatcher] 는 종료 훅에서 근무 마무리를 UI 줄기로 돌려 보낼 곳(근무 상태는 UI 스레드 한정 — W-work-social).
 */
class AppSeams(
    val events: Executor,
    val mainDispatcher: CoroutineContext,
    val window: FlyoutWindowPort,
    val screen: FlyoutScreen,
    val iconLocator: FlyoutIconLocator = FlyoutIconLocator { null },
    val menu: TrayMenuPresenter? = null,
    val instanceListen: ((onActivate: () -> Unit) -> Registration)? = null,
    val trayIconSizePx: () -> Int = { 16 },
    val reduceMotion: () -> Boolean = { false },
    val scale: () -> Double = { 1.0 },
    val workAreas: () -> List<PxRect> = { emptyList() },
    val characterSink: CharacterSink,
    val bubbleMeasure: BubbleTextMeasure,
    val overlayPresenter: OverlayPresenter = OverlayPresenter.None,
    val onOverlayPointer: (PointerOutcome) -> Unit = {},
    val consoleSessionUsable: () -> Boolean = { true },
    val gameWindows: GameWindowFactory = GameWindowFactory.Compose,
    val homes: DesktopAiHomes,
    val tokenCacheFile: Path?,
    val aiLimitRunner: AILimitRunner,
    val codexAccountRunner: suspend (now: SwiftDate) -> CodexProbeResult,
    val computeDiagnostics: suspend (month: String, appBuild: Long) -> CodexUsageDiagnostics?,
    val deviceLabel: () -> String? = { null },
    val runningTests: RunningTests,
    val environment: Map<String, String> = emptyMap(),
    val openUrl: (String) -> Unit = {},
    val share: (String) -> Unit = {},
    /** 사용자 '종료'(트레이 메뉴). Main 은 EDT 밖 스레드에서 exitProcess → 종료 훅이 [AppWirings.shutdownSteps] 를 돈다. */
    val quit: () -> Unit = {},
)

/** [DesktopKeyValueStore] 위의 세션 prefs(K3 KeyValueStore). 실영속은 W3-d — 그 전엔 [AppWirings.kv] 와 같은 칸을 쓴다. */
class DesktopPrefs(private val kv: DesktopKeyValueStore) : KeyValueStore {
    override fun getString(key: String): String? = kv.getString(key)
    override fun putString(key: String, value: String) = kv.putString(key, value)
    override fun getLong(key: String): Long? = kv.getLong(key)
    override fun putLong(key: String, value: Long) = kv.putLong(key, value)
    override fun getBoolean(key: String): Boolean? = kv.getBoolean(key)
    override fun putBoolean(key: String, value: Boolean) = kv.putBoolean(key, value)
    override fun remove(key: String) = kv.remove(key)
}

/** 테트리스 대결 호스트(폰 PhoneTetrisHost 와 같은 몫 — 같은 루비 칸). */
class DesktopTetrisHost(private val context: SessionContext, private val ruby: RubyBalanceCell) : TetrisDuelStoreHost {
    override var rubyBalance: Long?
        get() = ruby.rubyBalance
        set(value) {
            ruby.rubyBalance = value
        }
    override val appConfig get() = context.appConfig
    override val session get() = context.sessionStore.session
    override val sessionGeneration: Int get() = context.sessionStore.sessionGeneration
    override val service: SupabaseWorkService get() = context.service
    override suspend fun <T> withSessionRetry(operation: suspend (com.yehsung.aingcheck.core.wire.SupabaseSession) -> T): T =
        context.withSessionRetry(operation)
}

/**
 * 조립된 앱 한 벌. 생성 순서가 계약이다(W-work-social · W-overlay-tokens · W-shell-games notes):
 * kv → 세션 → 스토어 → overlay(근무 상태는 공급자 — start 때 읽음) → work(events = overlay.workEventSink) → social → tokens
 * → shell → games(shell.handle.nav). social 은 work 보다 늦게 만들어 `{ social.lifecycle }` 공급자로 잇는다(순환 없음).
 */
class AppWirings internal constructor(val graph: AppGraph, val seams: AppSeams, val scope: CoroutineScope) {
    private val wallNow: () -> SwiftDate = { SwiftDate.fromEpochMillis(graph.clock.now().toEpochMilliseconds()) }
    val sessionClock = SessionClock { wallNow() }

    /** W3-d 실영속(파일) 전까지 메모리(pins.md C). 큐·잠자기 마커·소유 id·창 자리·세션 prefs 가 같은 칸을 쓴다. */
    val kv: DesktopKeyValueStore = InMemoryDesktopKeyValueStore()
    val prefs: KeyValueStore = DesktopPrefs(kv)
    val ruby = RubyBalanceCell()

    val service = SupabaseWorkService(
        projectURL = graph.backend.projectURL,
        anonKey = graph.backend.anonKey,
        client = graph.httpClient { SupabaseWorkService.clientConfig(this) },
        clock = { sessionClock.now() },
        text = RulesWireTextRules,
        newUUIDString = { UUID.randomUUID().toString().uppercase() },
    )
    val sessionStore = SessionStore(
        service = service,
        vault = graph.platform.tokenVault,
        prefs = prefs,
        appInfo = AppInfo(graph.clientIdentity, graph.osVersion),
        installationIdentity = graph.platform.installationIdentity,
        clock = sessionClock,
        instanceGuard = graph.platform.singleInstance,
        parentScope = scope,
        // client_devices 'windows' 행(B 계약 1) — 울트라 밑바닥·Windows 빌드 축이 이 행을 읽는다. core 기본값(None)은 그대로.
        deviceRegistration = WindowsDeviceRegistration,
    )
    val sessionContext = SessionContext(sessionStore, graph.appConfig)
    val messages = MessagesStore(sessionContext, scope, NaturalKoNameCollation)
    val rankings = RankingsStore(sessionContext, scope, NaturalKoNameCollation)
    val me = MeStore(MeContext(sessionStore, graph.appConfig, ruby), scope, com.yehsung.aingcheck.ui.components.CharacterArt.drawableCharacterSource)
    val appearance = AppearanceStore(prefs)

    val gomoku = GomokuStore(scope, SessionGomokuHost(sessionContext, ruby))
    val chess = ChessStore(scope, SessionGomokuHost(sessionContext, ruby))
    val tetris = TetrisDuelStore(DesktopTetrisHost(sessionContext, ruby), scope, clock = { sessionClock.now() }, collation = NaturalKoNameCollation)
    /** 게임 탭 라우터(플라이아웃 게임 쪽이 갈아 끼운다). 기본은 아무것도 안 한다. */
    var gamesRouter: GamesRouter = object : GamesRouter {
        override fun present(destination: GamesDestination) = Unit
    }
    val gamesStore = GamesStore(
        object : GamesContext, SessionContext by sessionContext {
            override val scope: CoroutineScope get() = this@AppWirings.scope
            override val collation = NaturalKoNameCollation
            override fun refreshAchievementsAfterGameResult(game: String) = Unit
            override val tetris: TetrisDuelStore get() = this@AppWirings.tetris
            override val gomoku = GomokuGamesLink(this@AppWirings.gomoku)
            override val chess = ChessGamesLink(this@AppWirings.chess)
            override val router: GamesRouter = object : GamesRouter {
                override fun present(destination: GamesDestination) = gamesRouter.present(destination)
            }
            override val hiddenBlockedPeerIDs: Set<String> get() = emptySet()
            override val sharedRubyBalance: Long? get() = ruby.rubyBalance
        },
    )
    init {
        // 데스크톱 허브는 길건너까지 연다(W-9 #6 — 데스크톱은 구동, 폰은 phoneCases·라우트가 거른다). 창 상태는 이 목록을 그대로 받는다.
        gamesStore.miniGames.visibleKinds = com.yehsung.aingcheck.core.stores.minigame.MiniGameExposure.desktopVisible
    }

    /** 설정 '캐릭터 켜짐'(설정 화면이 바꾼다 — 맥 기본 켜짐). */
    val overlayEnabled = MutableStateFlow(true)

    /** 설정 '토큰 사용량 수집'. 설정·MeStore 칸이 오기 전에는 꺼 둔다(동의 없는 스캔 0 — 안전 쪽). */
    @Volatile var tokenUsageCollect: Boolean = false

    lateinit var work: WorkWiring
        private set
    lateinit var social: SocialWiring
        private set

    val overlay = OverlayWiring(
        OverlayWiringDeps(
            desktopConfig = graph.desktopConfig,
            keyValueStore = kv,
            clock = graph.clock,
            monotonic = graph.monotonic,
            workState = { work.store },
            overlayEnabled = overlayEnabled.asStateFlow(),
            sink = seams.characterSink,
            measure = seams.bubbleMeasure,
            power = graph.platform.power,
            session = graph.platform.session,
            consoleSessionUsable = seams.consoleSessionUsable,
            presenter = seams.overlayPresenter,
            onPointerOutcome = seams.onOverlayPointer,
        ),
    )

    init {
        work = WorkWiring(
            WorkDeps(
                sessionStore = sessionStore,
                kv = kv,
                clock = graph.clock,
                deviceId = graph.deviceId,
                idle = graph.platform.idle,
                power = graph.platform.power,
                session = graph.platform.session,
                teamId = { sessionStore.profile?.teamID },
                events = overlay.workEventSink,
                social = { social.lifecycle },
                wakeNetworkReady = null,
            ),
        )
        social = SocialWiring(
            SocialDeps(
                sessionStore = sessionStore,
                httpClient = graph.httpClient(KtorRealtimeTransport.clientConfig),
                desktopConfig = graph.desktopConfig,
                kv = kv,
                clock = graph.clock,
                workState = work.store,
                pokeFacts = work.store,
                lapJudgment = work.lapJudgment,
                ruby = ruby,
                runningTests = seams.runningTests,
                environment = seams.environment,
                messages = MessagesStoreRealtimeMessages(messages),
                receivedPokes = overlay.receivedPokeSink,
                consumedRows = MessagesStoreConsumedRowsSink(messages),
                ultraCharged = overlay.ultraChargedSink,
            ),
        )
    }

    val tokens = TokensWiring(
        TokensWiringDeps(
            desktopConfig = graph.desktopConfig,
            sessionStore = sessionStore,
            service = service,
            keyValueStore = kv,
            clock = graph.clock,
            deviceId = { graph.deviceId },
            homes = seams.homes,
            cacheBase = seams.tokenCacheFile,
            appBuild = graph.clientIdentity.build,
            tokenUsageCollect = { tokenUsageCollect },
            workState = work.store,
            aiLimitRunner = seams.aiLimitRunner,
            deviceLabel = seams.deviceLabel,
            codexAccountRunner = seams.codexAccountRunner,
            computeDiagnostics = seams.computeDiagnostics,
        ),
    )

    /** 트레이·메뉴가 읽는 근무 값(조정 ⑩ — DesktopWorkSnapshot 을 값으로 옮긴다, 판정 없음). 근무 중이면 30초마다 경과를 새로 적는다. */
    private val workStatus = MutableStateFlow(WorkStatusSnapshot(WorkStatus.offWork, 0))

    private var lateGames: GamesWiring? = null

    val shell = ShellWiring(
        ShellDeps(
            session = sessionStore,
            sessionContext = sessionContext,
            service = service,
            messages = messages,
            rankings = rankings,
            me = me,
            appearance = appearance,
            desktopConfig = graph.desktopConfig,
            clientIdentity = graph.clientIdentity,
            deviceStore = kv,
            monotonic = graph.monotonic,
            scope = scope,
            tray = graph.platform.tray,
            power = graph.platform.power,
            work = workStatus.asStateFlow(),
            toggleWork = { work.commands.toggle() },
            quit = seams.quit,
            events = seams.events,
            window = seams.window,
            screen = seams.screen,
            iconLocator = seams.iconLocator,
            gameWindows = { lateGames?.handle?.windows ?: com.yehsung.aingcheck.desktop.windows.kit.DesktopGameWindows.None },
            menu = seams.menu,
            instanceListen = seams.instanceListen,
            trayIconSizePx = seams.trayIconSizePx,
            reduceMotion = seams.reduceMotion,
            rankingsFace = {
                RankingsScreenRules.myFace(
                    meEquippedLoaded = me.equippedLoaded,
                    meEquippedCharacterID = me.equippedServerID,
                    snapshotCharacterID = null,
                    nowCard = null,
                    snapshotMood = null,
                )
            },
            rubyBalance = { ruby.rubyBalance },
            openUrl = seams.openUrl,
            share = seams.share,
        ),
    )

    val games = GamesWiring(
        GamesDeps(
            games = gamesStore,
            gomoku = gomoku,
            chess = chess,
            me = me,
            session = sessionStore,
            desktopConfig = graph.desktopConfig,
            deviceStore = kv,
            flyout = shell.handle.nav,
            workAreas = seams.workAreas,
            scale = seams.scale,
            reduceMotion = seams.reduceMotion,
            now = { sessionClock.now() },
            factory = seams.gameWindows,
        ),
    ).also { lateGames = it }

    private var workStatusJob: Job? = null
    private var launchJob: Job? = null

    /**
     * 시작 순서(W-6 #6 · 배선 notes): 세션 복원 → work → social(로그인 변화를 스스로 본다) → overlay → tokens → shell(창 attach·트레이
     * 첫 그림·클릭·두 번째 실행·메시지 60초·업데이트 감시) → games. [scope] 줄기(EDT)에서 부른다.
     */
    fun start() {
        launchJob = scope.launch { sessionStore.launch() }
        workStatusJob = scope.launch {
            work.store.snapshot.collectLatest { s ->
                while (true) {
                    workStatus.value = status(s, wallNow())
                    if (!s.isWorking) break
                    delay(WORK_STATUS_TICK_MILLIS)
                }
            }
        }
        work.start(scope)
        social.start(scope)
        overlay.start(scope)
        tokens.start(scope)
        shell.start(scope)
        games.start(scope)
    }

    /**
     * W-6 #6 종료 순서 한 벌(이름은 시험이 녹음한다): 근무 마무리(beginTermination → QuitFinisher 3초, UI 줄기) → 토큰 캐시 저장 →
     * 토큰 루프 내림 → 실시간 shutdown(social) → 게임 구독 걷기 → 오버레이 내림 → 근무 루프·OS 구독 내림 → 껍데기(구독 취소 → 업데이트
     * 감시·전원 Registration close → nav.hide → **tray.remove** 마지막). 플랫폼 닫기는 Main 몫(이 뒤).
     */
    fun shutdownSteps(): List<ShutdownStep> = listOf(
        ShutdownStep.Bounded(STEP_WORK_FINISH, WORK_FINISH_MILLIS) { withContext(seams.mainDispatcher) { work.finishForQuit() } },
        ShutdownStep.Bounded(STEP_TOKENS_PERSIST, TOKENS_PERSIST_MILLIS) { tokens.finishForQuit() },
        ShutdownStep.Always(STEP_TOKENS_STOP) { tokens.stop() },
        ShutdownStep.Always(STEP_REALTIME_SHUTDOWN) { social.shutdown() },
        ShutdownStep.Always(STEP_GAMES_STOP) { games.stop() },
        ShutdownStep.Always(STEP_OVERLAY_STOP) { overlay.stop() },
        ShutdownStep.Always(STEP_WORK_STOP) {
            workStatusJob?.cancel()
            launchJob?.cancel()
            work.stop()
        },
        ShutdownStep.Always(STEP_SHELL_STOP) { shell.stop() },
    )

    companion object {
        const val STEP_WORK_FINISH = "work.finishForQuit"
        const val STEP_TOKENS_PERSIST = "tokens.persistForTermination"
        const val STEP_TOKENS_STOP = "tokens.stop"
        const val STEP_REALTIME_SHUTDOWN = "social.shutdown"
        const val STEP_GAMES_STOP = "games.stop"
        const val STEP_OVERLAY_STOP = "overlay.stop"
        const val STEP_WORK_STOP = "work.stop"
        const val STEP_SHELL_STOP = "shell.stop"

        /** 근무 마무리 상한(QuitFinisher 3초 + 줄기 왕복 여유). */
        const val WORK_FINISH_MILLIS = 3_500L
        const val TOKENS_PERSIST_MILLIS = 1_000L
        const val WORK_STATUS_TICK_MILLIS = 30_000L

        /** 트레이에 넘기는 값(조정 ⑩). */
        fun status(s: DesktopWorkSnapshot, now: SwiftDate): WorkStatusSnapshot =
            WorkStatusSnapshot(if (s.isWorking) WorkStatus.working else WorkStatus.offWork, s.elapsedSeconds(now), s.pendingSync)
    }
}

/** 종료 단계. [Bounded] 는 남은 전체 상한과 자기 상한 중 작은 쪽 안에서만 기다리고, [Always] 는 상한이 지나도 돈다(트레이 유령 아이콘 방지). */
sealed class ShutdownStep(val name: String) {
    class Bounded(name: String, val maxMillis: Long, val run: suspend () -> Unit) : ShutdownStep(name)
    class Always(name: String, val run: () -> Unit) : ShutdownStep(name)
}

/** W-6 #6 종료 훅을 전체 상한 안에서 차례로 돈다. 한 단계 실패가 다음 단계를 막지 않는다. */
object ShutdownSequence {
    /** Windows 종료 대기(WM_ENDSESSION 뒤 수 초) 안 — 근무 마무리 3초 + 나머지. */
    const val TOTAL_BUDGET_MILLIS = 4_500L

    suspend fun run(
        steps: List<ShutdownStep>,
        elapsedMillis: () -> Long,
        budgetMillis: Long = TOTAL_BUDGET_MILLIS,
        onStep: (String) -> Unit = {},
    ) {
        val start = elapsedMillis()
        for (step in steps) {
            onStep(step.name)
            try {
                when (step) {
                    is ShutdownStep.Bounded -> {
                        val left = minOf(step.maxMillis, budgetMillis - (elapsedMillis() - start))
                        if (left > 0) withTimeoutOrNull(left) { step.run() }
                    }
                    is ShutdownStep.Always -> step.run()
                }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                // 종료 중 한 단계의 실패는 삼키고 다음으로(트레이 아이콘은 반드시 걷는다).
            }
        }
    }
}

/** JVM 단조 시계(System.nanoTime). 앱 조립 지점에서만 만든다. */
object SystemMonotonicClock : MonotonicClock {
    override fun elapsedNanos(): Long = System.nanoTime()
}

/**
 * W-3 #17 — [DesktopAppConfig] 를 생성 상수 DesktopFlags(`-Paingcheck.windows.<이름>=true|false`, build-logic aingcheckWindowsFlags)에서
 * 만드는 **한 자리**. DesktopFlags 를 다른 곳에서 읽지 않는다(selfcheck 도 이 함수를 거친다).
 */
fun DesktopAppConfig.Companion.fromBuild(): DesktopAppConfig = DesktopAppConfig(
    duels = DesktopFlags.DUELS,
    poke = DesktopFlags.POKE,
    ultra = DesktopFlags.ULTRA,
    chatToast = DesktopFlags.CHAT_TOAST,
    forkSafe = DesktopFlags.FORK_SAFE,
    tokenUpload = DesktopFlags.TOKEN_UPLOAD,
    adoptedPokeConsume = DesktopFlags.ADOPTED_POKE_CONSUME,
    spectator = DesktopFlags.SPECTATOR,
)

/**
 * 그리지 않는 캐릭터 자리(오버레이 엔진은 돌되 화면엔 아무것도 없음). 실물 CharacterPlayerSink(구운 라이브러리)·WindowsOverlaySurface
 * 발표자는 오버레이 표면 조립에서 바꾼다 — 그 전엔 이 자리라 엔진 판정(말풍선·반응 차례)이 사용자에게 보이지 않을 뿐 서버 호출은 같다.
 */
class SilentCharacterSink(override var currentCharacterId: String = "aing") : CharacterSink {
    override fun play(reaction: String, now: Double): Boolean = false
    override fun interrupt(now: Double) = Unit
    override fun beginSleep(now: Double): Boolean = false
    override fun wake(kind: com.yehsung.aingcheck.character.player.WakeKind, now: Double): Boolean = false
    override fun blink(now: Double): Boolean = false
    override fun setEyesClosed(closed: Boolean) = Unit
    override fun setFacing(direction: Int, moving: Boolean, now: Double) = Unit
    override fun swapCharacter(id: String?, now: Double) {
        currentCharacterId = id ?: "aing"
    }
    override fun setSuspended(value: Boolean, now: Double): Boolean = false
}
