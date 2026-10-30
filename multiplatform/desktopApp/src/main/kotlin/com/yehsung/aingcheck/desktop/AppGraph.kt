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
import com.yehsung.aingcheck.desktop.wiring.OverlayDuelFacts
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
import com.yehsung.aingcheck.desktop.wiring.HomeBannerStores
import com.yehsung.aingcheck.desktop.wiring.TodoWiring
import com.yehsung.aingcheck.desktop.wiring.TodoWiringDeps
import com.yehsung.aingcheck.desktop.wiring.TokenUsageCollectSource
import com.yehsung.aingcheck.desktop.todo.DesktopTodoFileSystem
import com.yehsung.aingcheck.desktop.overlay.todoboard.TodoBoardController
import com.yehsung.aingcheck.desktop.pages.work.HomeBannerSources
import com.yehsung.aingcheck.desktop.platform.windows.display.DisplayChangeSource
import com.yehsung.aingcheck.desktop.windows.kit.DesktopGameWindows
import com.yehsung.aingcheck.core.net.fetchTokenUsageSettings
import com.yehsung.aingcheck.core.stores.me.loadFeedbackReplyLatest
import com.yehsung.aingcheck.core.stores.me.weeklyWorkDidChange
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
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
import androidx.compose.runtime.snapshotFlow
import com.yehsung.aingcheck.core.rules.insights.KstCalendar
import com.yehsung.aingcheck.core.stores.me.evaluateRetroBanner
import com.yehsung.aingcheck.core.stores.me.loadRecords
import com.yehsung.aingcheck.core.stores.me.loadShop
import com.yehsung.aingcheck.core.stores.me.markRetroBannerDisplayed
import com.yehsung.aingcheck.core.stores.me.markRetroBannerSeen
import com.yehsung.aingcheck.core.stores.me.retroBannerMenuDidClose
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.desktop.overlay.assembly.OverlaySurfaces
import com.yehsung.aingcheck.desktop.todo.TodoQuarantineLog
import com.yehsung.aingcheck.desktop.overlay.assembly.OverlaySurfacesConfig
import com.yehsung.aingcheck.desktop.pages.aitokens.AiTokensPageDeps
import com.yehsung.aingcheck.desktop.pages.ailimits.asActions
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsStore
import com.yehsung.aingcheck.desktop.pages.focus.FocusModeModel
import com.yehsung.aingcheck.desktop.pages.poke.PokeListDeps
import com.yehsung.aingcheck.desktop.pages.work.HomeBannerActions
import com.yehsung.aingcheck.desktop.pages.work.HomePageDeps
import com.yehsung.aingcheck.desktop.pages.work.HomeRetroBanner
import com.yehsung.aingcheck.desktop.pages.work.WorkShortcutGate
import com.yehsung.aingcheck.desktop.platform.windows.network.NetworkReadiness
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.wiring.AiLimitsInputs
import com.yehsung.aingcheck.desktop.wiring.DesktopRealtimeGamesOf
import com.yehsung.aingcheck.desktop.wiring.DesktopSocialHooks
import com.yehsung.aingcheck.desktop.wiring.InviteDots
import com.yehsung.aingcheck.desktop.wiring.OsDeps
import com.yehsung.aingcheck.desktop.wiring.OsWiring
import com.yehsung.aingcheck.desktop.wiring.PagesWiring
import com.yehsung.aingcheck.desktop.wiring.PagesWiringDeps
import com.yehsung.aingcheck.desktop.wiring.UltraPageInputs
import io.ktor.client.HttpClient
import io.ktor.client.HttpClientConfig
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.dropWhile
import kotlinx.coroutines.flow.map
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
    /** 앱 한 벌의 kv(W3-d — Windows 는 FileDesktopKeyValueStore: 근무 큐 키 즉시 쓰기 · 나머지 250ms 묶음, W-13 #2). 시험은 메모리. */
    val keyValueStore: DesktopKeyValueStore = InMemoryDesktopKeyValueStore(),
    /** 깨움 뒤 망 준비(W3-d). null 이면 기다리지 않는다. */
    val networkReadiness: NetworkReadiness? = null,
    /** 오버레이 실물 표면(W5-b4 — Windows 는 OverlaySurfaces.create). null 이면 seams 의 sink·presenter(그리지 않음) 그대로. */
    val overlaySurfaces: ((OverlaySurfacesConfig) -> OverlaySurfaces?)? = null,
    /** 화면 배치·배율 바뀜(W-14 #4 — Windows 는 Win32DisplayChangeSource: WM_DISPLAYCHANGE·WM_DPICHANGED). null 이면 오버레이가 다시 재지 않는다. */
    val displayChanges: DisplayChangeSource? = null,
    /** 단축키가 지금 근무를 바꿀 수 없을 때(맥 NSSound.beep). */
    val beep: () -> Unit = {},
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

    /** 앱 한 벌의 kv(W3-d — Windows 는 파일 영속, 시험은 메모리). 큐·잠자기 마커·소유 id·창 자리·세션 prefs·설정이 같은 칸을 쓴다. */
    val kv: DesktopKeyValueStore = seams.keyValueStore
    val prefs: KeyValueStore = DesktopPrefs(kv)

    /** 데스크톱 설정 한 벌(W3-c4 — 키는 맥 UserDefaults 글자 그대로). 페이지·OS·오버레이·토큰·근무가 이 값만 읽는다. */
    val desktopSettings = DesktopSettingsStore(kv)
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

    init {
        // '이 기기가 연 판' 기록(vc3 한 판 한 기기 — 사용자별 키 tetris.duel.ownedMatches.<id>)을 앱 kv 에 둔다: 다시 켠 앱이 옛 서버
        // (my_device 없음)에서도 자기 판을 알아본다. 맥 TetrisDuelStore.swift:607-610(앱 배선이 넣는다 · nil 이면 프로세스 안에만).
        // Windows kv 는 이 키 머리를 즉시 쓰기로 연다(FileDesktopKeyValueStore.WORK_IMMEDIATE_KEY_PREFIXES).
        tetris.defaults = prefs
    }
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

    /**
     * 서버 수집 설정(profiles.token_usage_collect — W-14 #10, 맥 WorkTimerStorePoke.swift:841-856). 계정마다 받은 뒤에만 참 — 받기 전·
     * 로그아웃은 거짓(동의 없는 스캔 0 — 안전 쪽). 업로드 자체는 여전히 빌드 깃발 tokenUpload(기본 꺼짐)가 막는다.
     */
    val tokenUsageCollectSource = TokenUsageCollectSource(
        accountIds = sessionStore.sessionFlow.map { it?.userID },
        fetchCollects = { sessionContext.withSessionRetry { s -> service.fetchTokenUsageSettings(s.accessToken, s.userID) }.collects },
    )
    val tokenUsageCollect: Boolean get() = tokenUsageCollectSource.collects

    lateinit var work: WorkWiring
        private set
    lateinit var social: SocialWiring
        private set

    /**
     * 할 일(W-14 #3 — 맥 TodoListStore·TodoSync): 계정별 파일 + 서버 맞추기. 오버레이 보드가 [TodoWiring.list] 를 그리므로 오버레이보다
     * 먼저 짓는다. 계정 전환 직전 보드의 되돌리기 창을 앞 계정 파일에 확정한다(beforeAccountSwitch — 람다라 표면이 늦게 서도 된다).
     */
    val todo = TodoWiring(
        TodoWiringDeps(
            dataDir = Path.of(graph.platform.paths.dataDir),
            transport = TodoWiring.sessionTransport(sessionContext),
            accountIds = sessionStore.sessionFlow.map { it?.userID },
            currentUserID = { sessionStore.session?.userID },
            clock = { graph.clock.now().toEpochMilliseconds() / 1000.0 },
            files = DesktopTodoFileSystem(
                // 손상 파일 격리 보고 → 앱 로그 폴더 aing-check-todo.log 한 줄(배포본은 콘솔이 없다 — System.err 는 어디에도 안 남는다).
                onQuarantine = TodoQuarantineLog.sink(graph.platform.paths, now = { graph.clock.now() }),
            ),
            power = graph.platform.power,
            wakeNetworkReady = seams.networkReadiness?.let { r -> suspend { r.awaitReady() } },
            beforeAccountSwitch = { (overlaySurfaces?.board as? TodoBoardController)?.resetForAccountSwitch() },
        ),
        scope,
    )

    /** 실물 오버레이 표면(Windows). 할 일 보드는 [todo] 의 목록을 그리고, 보드를 열면 서버 맞추기를 한 번 청한다(맥 boardOpened). */
    private val overlaySurfaces: OverlaySurfaces? = seams.overlaySurfaces?.invoke(
        OverlaySurfacesConfig(
            keyValueStore = kv,
            todoStore = todo.list,
            boardEnabled = { desktopSettings.todoBoard.value.enabled },
            onBoardOpened = { scope.launch { todo.onBoardOpened() } },
            initialCharacterId = me.equippedServerID,
        ),
    )

    /**
     * 오버레이 포인터 결과 한 문: 대결 말풍선(신청·차례)을 누르면 그 판 창(맥 CheckApp.swift:370·407·443 onOpen… → store.openWindow(focusMatchID:)),
     * 메시지 도착 말풍선을 누르면 플라이아웃의 그 사람 대화(보낸이 모르면 콕 목록 — 맥 CheckApp.swift:192-199 onOpenMessages)
     * 뒤 바깥 seam. 게임 배선([lateGames])·껍데기([shell])는 오버레이 뒤에 지어진다 — 누를 때 읽는다(클릭은 start 뒤에만 온다).
     */
    internal val overlayPointerOutcome: (PointerOutcome) -> Unit = { o ->
        OverlayWiring.openDuel(o, lateGames?.handle?.windows ?: com.yehsung.aingcheck.desktop.windows.kit.DesktopGameWindows.None)
        OverlayWiring.openMessages(o, shell.handle.nav, graph.desktopConfig.poke)
        seams.onOverlayPointer(o)
    }

    val overlay = OverlayWiring(
        OverlayWiringDeps(
            desktopConfig = graph.desktopConfig,
            keyValueStore = kv,
            clock = graph.clock,
            monotonic = graph.monotonic,
            workState = { work.store },
            overlayEnabled = desktopSettings.overlayEnabled,
            sink = seams.characterSink,
            measure = seams.bubbleMeasure,
            power = graph.platform.power,
            session = graph.platform.session,
            consoleSessionUsable = seams.consoleSessionUsable,
            presenter = seams.overlayPresenter,
            onPointerOutcome = overlayPointerOutcome,
            accountIds = sessionStore.sessionFlow.map { it?.userID },
            todoBoard = desktopSettings.todoBoard,
            onBoardOpacityChanged = desktopSettings::setTodoBoardOpacity,
            weeklyRubyGrants = OverlayWiring.weeklyRubyGrants(snapshotFlow { me.weeklyGrantSerial to me.weeklyGrantNotice?.ruby }),
            // W-14 #4: 팀 출근 · 새 버전 · 화면 바뀜. work·shell 은 오버레이 뒤에 지어지므로 차가운 흐름으로 감싼다(overlay.start 때 읽는다).
            teamStatuses = flow { emitAll(work.teamStatuses) },
            selfUserId = { sessionStore.session?.userID },
            updateVersions = OverlayWiring.updateVersions(flow { emitAll(shell.handle.updateChecker.state) }),
            displayChanges = seams.displayChanges,
            // 대결 말풍선은 띄우기 직전 스토어 사실(받은 신청·창 보임·지금 판)을 읽는다 — 창을 연 뒤·판이 끝난 뒤 대기 차례 말풍선 0(맥 :1393).
            duelFacts = OverlayDuelFacts.from(gomoku, chess, tetris),
        ),
        // 실물 표면이 있으면 sink·presenter·board 를 표면 것으로 바꾼다(seams 값은 Windows 밖 대체값).
        overlaySurfaces,
    )

    /** 미션 화면이 보이는가(지갑 박자 — 소셜이 껍데기보다 먼저 지어지므로 껍데기 생성 뒤 갈아 끼운다). */
    private var missionsVisible: () -> Boolean = { false }

    /** 콕 목록 디렉터리 다시 읽기(발신 훅 — 페이지는 소셜 뒤에 지어진다). */
    private var pokeDirectoryReload: () -> Unit = {}

    init {
        work = WorkWiring(
            WorkDeps(
                sessionStore = sessionStore,
                kv = kv,
                clock = graph.clock,
                // W-14 #7: 조립 때 몇 번까지 묻는 공급자(레지스트리·파일 잠깐 잠김을 넘긴다 — 토큰 deviceId 와 같은 꼴).
                deviceIdSource = { graph.deviceId },
                idle = graph.platform.idle,
                power = graph.platform.power,
                session = graph.platform.session,
                teamId = { sessionStore.profile?.teamID },
                events = overlay.workEventSink,
                social = { social.lifecycle },
                autoWorkStartEnabled = { desktopSettings.autoWorkStart.value },
                wakeNetworkReady = seams.networkReadiness?.let { r -> suspend { r.awaitReady() } },
                consoleSessionUsable = seams.consoleSessionUsable,
                // 빠른 주기 3항(근무 || 플라이아웃 열림 || 큐 대기) — 틱 루프는 work.start 뒤에만 부른다(shell 은 그때 서 있다).
                menuPresented = { shell.handle.nav.visible.value },
                // 주간 근무 보상 몫(맥 근무 종료 → weeklyWorkDidChange) — me 는 이 init 보다 먼저 선다.
                onWorkEndedWeekly = { me.weeklyWorkDidChange() },
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
                walletCadence = DesktopSocialHooks.walletCadence(me) { missionsVisible() },
                beatOthers = DesktopSocialHooks.beatOthers(me),
                sendHooks = DesktopSocialHooks.sendHooks(messages) { pokeDirectoryReload() },
                onShopMutation = DesktopSocialHooks.shopMutation(scope, me),
                games = DesktopRealtimeGamesOf.stores(graph.desktopConfig, gomoku, chess, tetris),
                // 공용 18(MeStore.ultraPrice — Compose 상태를 읽는 람다라 값이 오면 다시 그린다).
                ultraPrice = { me.ultraPrice },
                // W-3 #6: 말풍선 큐 한 벌 — 소셜이 쌓고 오버레이가 띄운다.
                bubbles = overlay.bubbles,
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
            // W-13 #5: AI 도구 기록 동의(check.mas.aiToolDataConsent, 기본 거절) — 동의 전 스캔·리밋 읽기·업로드 0, 철회는 흐름으로 즉시.
            aiToolDataAllowed = { desktopSettings.tokenUsageCollect.value },
            aiToolDataConsentChanges = desktopSettings.tokenUsageCollect,
            workState = work.store,
            aiLimitRunner = seams.aiLimitRunner,
            deviceLabel = seams.deviceLabel,
            codexAccountRunner = seams.codexAccountRunner,
            computeDiagnostics = seams.computeDiagnostics,
        ),
    )

    /**
     * int-w2 페이지(W-9 #2 · W-13 #1·#4·#5·#6·#8·#9): 홈·콕 목록·울트라·AI 토큰·AI 리밋·기기·PC 설정·첫 실행. 껍데기보다 먼저 —
     * 홈 람다의 shell 참조는 Content 때 읽으므로 늦게 묶여도 된다.
     */
    val pages: PagesWiring = PagesWiring(
        PagesWiringDeps(
            desktopConfig = graph.desktopConfig,
            settings = desktopSettings,
            wallNow = wallNow,
            home = { nav ->
                HomePageDeps(
                    work = work.state,
                    commands = work.commands,
                    teamStatuses = work.teamStatuses,
                    clock = wallNow,
                    isSignedIn = { sessionStore.session != null },
                    isTeamless = { sessionStore.profile?.teamID == null },
                    myUserId = { sessionStore.session?.userID },
                    teamName = { sessionStore.profile?.teamName.orEmpty() },
                    teamGoalSeconds = { (sessionStore.profile?.teamGoalHours ?: TeamWeeklyGoal.defaultGoalHours) * 3600 },
                    duelsEnabled = graph.desktopConfig.duels,
                    update = shell.handle.updateChecker.state,
                    canSync = { graph.backend.anonKey != null },
                    actions = HomeBannerActions(openRecords = { nav.navigate(FlyoutRoute.Records) }),
                )
            },
            // 공용 19 회고 배너(맥 WorkTimerStore.swift:1130 showsRetroBanner · CheckMenuView.swift:480-500 X→Seen · onAppear→Displayed).
            retroBanner = HomeRetroBanner(
                due = { me.showsRetroBanner },
                seen = { me.markRetroBannerSeen() },
                displayed = { me.markRetroBannerDisplayed() },
            ),
            // W-14 #5 홈 배너 피드: 대결 신청·제보 답장·케이크 선물. 게임 창 문은 람다라 games 가 늦게 서도 된다(duels 꺼짐은 HomePageDeps 가 거른다).
            homeBanners = HomeBannerSources(
                gomoku = HomeBannerStores.gomoku(gomoku) { lateGames?.handle?.windows ?: DesktopGameWindows.None },
                chess = HomeBannerStores.chess(chess) { lateGames?.handle?.windows ?: DesktopGameWindows.None },
                tetris = HomeBannerStores.tetris(tetris) { lateGames?.handle?.windows ?: DesktopGameWindows.None },
                feedbackReply = HomeBannerStores.feedbackReply(me),
                cakeGift = HomeBannerStores.cakeGift(me) { lateGames?.handle?.windows ?: DesktopGameWindows.None },
                launch = { block -> scope.launch { block() } },
            ),
            pokeList = PokeListDeps(
                host = sessionStore,
                config = graph.desktopConfig,
                sender = social.sender,
                wallet = social.wallet,
                focus = FocusModeModel(social.focus, wallNow),
                scope = scope,
                clock = wallNow,
                localSessionOpen = { work.store.pokeConsumeFacts().localSessionOpen },
                workChanges = work.store.snapshot,
                hiddenBlockedPeerIDs = { messages.hiddenBlockedPeerIDs },
            ),
            ultra = UltraPageInputs(wallet = social.wallet, purchase = social.purchase, ruby = ruby, reloadShop = { scope.launch { me.loadShop() } }),
            ultraPrice = { me.ultraPrice },
            aiTokens = AiTokensPageDeps(
                settings = desktopSettings,
                usage = tokens.scan.currentMonthUsage,
                scanning = tokens.scan.isScanning,
                account = { tokens.account.snapshot },
                serverRow = { tokens.upload.myTokenRow },
                userID = { sessionStore.session?.userID },
                currentMonth = { KstCalendar.monthKey(wallNow().timeIntervalSince1970) },
                onConsentGranted = { tokens.scan.refreshNow() },
            ),
            aiLimits = AiLimitsInputs(tokens.aiLimits, tokens.aiLimitSync.asActions(wallNow)),
            onConsentGranted = { tokens.scan.refreshNow() },
            openUrl = seams.openUrl,
        ),
    )

    init {
        pokeDirectoryReload = { pages.pokeListPage?.model?.directory?.load() }
        // 로그아웃·계정 전환: 콕 디렉터리 비우기(c3 notes) + 울트라 고른 것 풀기(W-14 #5).
        social.addSignedOutListener { pages.onSignedOut() }
        // 1:1 게임도 계정에 묶인 상태다(맥 WorkTimerStore.swift:4120-4126 로그아웃 · :4265-4267 adoptWorkStateOwner ·
        // 폰 PhoneAppModel.kt sessionDidSignOut). 계정 전환(A → B 직행)도 SocialWiring 이 onSignedOut → onSignedIn 으로
        // 펼치므로 이 한 곳이다. 남기면 다음 사람이 앞 사람의 판·신청을 보고, 앞 사람의 판 구동기가 새 세션의 토큰으로 보고를 낸다.
        // '이 기기가 연 판' 기록은 사용자별 키라 reset 이 건드리지 않는다. 따로 건다 — 앞 리스너가 던져도 판은 내린다.
        social.addSignedOutListener {
            gomoku.reset()
            chess.reset()
            tetris.reset()
        }
        // 나머지 계정 묶음 스토어(맥 WorkTimerStore.swift clearPersistedSession 4028-4350 · adoptWorkStateOwner 4356-4375 · 폰 PhoneAppModel.kt
        // sessionDidSignOut 과 같은 사슬·같은 순서). 없던 때 잰 것(AccountBoundaryTest): 로그아웃·A → B 둘 다 앞 사람의 리그 줄·보던 주·토큰 공개
        // (맥 4054-4060·4141) · 케이크 선물(4230 resetCakeGiftState) · 제보·별명 초안(4314·4233) · 미니게임 판 토큰(4286 — 서버가 소유자를
        // 대조해 다음 사람 제출이 조용히 거절된다) · 게임 탭 화면 깃발 · 루비 미러가 남았다. 메시지(초안·확성기 글 — 4115·4224)는 여기서 부르지
        // 않는다: MessagesBackgroundRefresh 가 로그아웃·A → B 직행 둘 다에서 reset 한 **뒤** B 의 요약을 바로 읽는다(int-w4b ③). 여기서 또 부르면
        // 그 첫 요약 Task 를 끊을 수 있다(reset → runtime.cancelAll — 두 수집기의 순서는 정해져 있지 않다).
        // 토큰 업로드 장부·내 행(맥 4072-4088 — 앞 사람 숫자 · "이미 올린 날")도 여기서 비운다(int-w4b ①).
        // 뽑기(resetGachaState 4228 — 앞 사람의 request_id)·도전 미션·주간 보상·회고 배너도 me.reset 이 함께 내린다.
        // 계정 묶음 창(게임·뽑기·케이크)은 GamesWiring 이 계정이 바뀌면 closeAll 로 **닫는다**(맥 4237-4250 — 깃발만 내리지 않는다).
        social.addSignedOutListener {
            ruby.rubyBalance = null
            rankings.reset()
            gamesStore.reset()
            me.reset()
            tokens.upload.resetForAccount()
        }
    }

    /** 트레이·메뉴가 읽는 근무 값(조정 ⑩ — DesktopWorkSnapshot 을 값으로 옮긴다, 판정 없음). 근무 중이면 30초마다 경과를 새로 적는다. */
    private val workStatus = MutableStateFlow(WorkStatusSnapshot(WorkStatus.offWork, 0))

    private var lateGames: GamesWiring? = null

    val shell: ShellWiring = ShellWiring(
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
            inviteDots = InviteDots.from(gomoku, chess, tetris),
            onUltraPageLeft = { social.onUltraPageLeft() },
            routePages = pages.routePages,
            firstRun = pages.firstRun,
            // W-14 #4: 셸 사건 → 오버레이 말풍선 한 문. 오버레이가 보이거나 엿볼 수 있을 때만 말풍선을 고른다(못 받으면 토스트로 내려간다).
            bubble = overlay.shellBubble,
            notifyContext = {
                ShellDeps.DEFAULT_NOTIFY_CONTEXT.copy(overlayVisible = overlay.availability.value.let { it.visibleNow || it.canPeek })
            },
        ),
    )

    init {
        missionsVisible = { shell.handle.nav.visible.value && shell.handle.nav.route.value == FlyoutRoute.Missions }
    }

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
            boardMe = { overlay.boardMe(me.displayName, me.equippedServerID) },
            onInviteNotice = { shell.handle.notifyDuelInvite(it) },
            characters = { shell.handle.characters.directory },
            // W-14 #1: 대국 채팅 신고·차단 — 메시지 탭과 한 스토어.
            messages = messages,
            // W-14 #4: 구조 신청 → 오버레이(글 알림 onInviteNotice 보다 먼저 온다 — 같은 신청의 대체 말풍선을 하나로 묶는다).
            onInviteArrival = { g, id, peer, stake, exp -> overlay.onDuelInvite(g, id, peer, stake, exp) },
            // 차례 알림 구조 정보(판 id·종류) → 오버레이 말풍선(누르면 위 onPointerOutcome 이 그 판 창을 연다).
            onDuelAttention = { overlay.onDuelAttention(it) },
        ),
    ).also { lateGames = it }

    /** OS 배선(W3-d · W-13 #2·#3·#6): 단축키 → 근무 토글 · 자동 실행 적용 · 플라이아웃 열림 기기 재등록 · 종료 kv flush. */
    val os: OsWiring = OsWiring(
        OsDeps.fromSettings(
            settings = desktopSettings,
            hotkeys = graph.platform.hotkeys,
            // 맥 canToggleWorkByShortcut(로그인 · 팀 · canSync)의 짝 — 홈 알약 조건과 같은 함수(W-13 #4).
            canToggleWork = { WorkShortcutGate.canToggle(sessionStore.phaseFlow.value, sessionStore.profile, canSync = graph.backend.anonKey != null) },
            toggleWork = { work.commands.toggle() },
            onHotkeyRejected = { seams.beep() },
            loginItem = graph.platform.loginItem,
            flyoutOpen = shell.handle.nav.visible,
            appDidBecomeActive = sessionStore::appDidBecomeActive,
            kv = kv,
        ),
    )

    private var workStatusJob: Job? = null
    private var launchJob: Job? = null
    private val flyoutJobs = mutableListOf<Job>()

    /**
     * 시작 순서(W-6 #6 · 배선 notes): 세션 복원 → work → social(로그인 변화를 스스로 본다) → overlay → tokens → shell(창 attach·트레이
     * 첫 그림·클릭·두 번째 실행·메시지 60초·업데이트 감시) → os(nav.visible 이 서 있어야 첫 열림을 본다) → games. [scope] 줄기(EDT)에서 부른다.
     */
    fun start() {
        launchJob = scope.launch { sessionStore.launch() }
        // 할 일: 계정 파일 · 깨어남(power WAKE) · 5분 주기 — 오버레이보다 먼저(보드가 첫 그림에 목록을 읽는다).
        todo.start()
        tokenUsageCollectSource.start(scope)
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
        os.start(scope)
        games.start(scope)
        startFlyoutHooks()
        // 첫 실행 화면(W-13 #5·#6): 동의·자동 실행 값 중 하나라도 없으면 한 번 연다 — 공용 호스트가 페이지·레일 대신 그린다.
        if (pages.firstRun.pending.value) shell.handle.nav.open(null)
    }

    /**
     * 플라이아웃 열림·경로에 거는 일: 토큰 열림 주기(스캔·리밋 강제·내 행) · 회고 배너 판정(공용 19 — 맥 WorkTimerStore.swift:316-321
     * 열림 판정 · 381-386 닫힘 내림 · 2972-2976 기록 패널 · WorkTimerStoreInsights.swift:162 loadInsights 끝) · 설정 화면 진입 때 OS 재적용.
     */
    private fun startFlyoutHooks() {
        val nav = shell.handle.nav
        val recordsShown = { nav.visible.value && nav.route.value == FlyoutRoute.Records }
        flyoutJobs += scope.launch {
            nav.visible.dropWhile { !it }.distinctUntilChanged().collect { open ->
                if (open) {
                    tokens.onFlyoutOpened()
                    // 제보 답장 시각(맥 WorkTimerStore.swift:3081-3083 refreshFeedbackReplyBadge — 부르는 자리는 팝오버를 여는 순간 하나뿐).
                    scope.launch { me.loadFeedbackReplyLatest() }
                    // 맥은 열 때 회고가 아직 없으면 기록을 조용히 받아 온다 — 월요일 첫 열림에 배너가 뜨게.
                    if (!me.recordsState.hasLoaded) scope.launch { me.loadRecords() }
                    me.evaluateRetroBanner(isInsightsPanelVisible = recordsShown(), isMenuPresented = true)
                } else {
                    tokens.onFlyoutClosed()
                    me.retroBannerMenuDidClose()
                }
            }
        }
        flyoutJobs += scope.launch {
            snapshotFlow { me.retro }.drop(1).collect {
                me.evaluateRetroBanner(isInsightsPanelVisible = recordsShown(), isMenuPresented = nav.visible.value)
            }
        }
        flyoutJobs += scope.launch {
            combine(nav.visible, nav.route) { v, r -> v to r }.distinctUntilChanged().collect { (visible, route) ->
                if (!visible) return@collect
                when (route) {
                    FlyoutRoute.Records -> me.evaluateRetroBanner(isInsightsPanelVisible = true, isMenuPresented = true)
                    FlyoutRoute.DesktopSettings -> os.reapply()
                    else -> Unit
                }
            }
        }
    }

    /**
     * W-6 #6 종료 순서 한 벌(이름은 시험이 녹음한다): 근무 마무리(beginTermination → QuitFinisher 3초, UI 줄기) → 토큰 캐시 저장 →
     * 토큰 루프 내림 → 실시간 shutdown(social) → 게임 구독 걷기 → 할 일 내림 → 오버레이 내림 → 근무 루프·OS 구독 내림 → 단축키 등록 풀기(os) → 껍데기(구독 취소 → 업데이트
     * 감시·전원 Registration close → nav.hide → **tray.remove**) → kv flush(W3-d — 앞 단계들이 kv 에 쓴 뒤). 플랫폼 닫기는 Main 몫(이 뒤).
     */
    fun shutdownSteps(): List<ShutdownStep> = listOf(
        ShutdownStep.Bounded(STEP_WORK_FINISH, WORK_FINISH_MILLIS) { withContext(seams.mainDispatcher) { work.finishForQuit() } },
        ShutdownStep.Bounded(STEP_TOKENS_PERSIST, TOKENS_PERSIST_MILLIS) { tokens.finishForQuit() },
        ShutdownStep.Always(STEP_TOKENS_STOP) {
            tokens.stop()
            tokenUsageCollectSource.stop()
        },
        ShutdownStep.Always(STEP_REALTIME_SHUTDOWN) { social.shutdown() },
        ShutdownStep.Always(STEP_GAMES_STOP) { games.stop() },
        // 할 일: 계정 흐름·깨어남 구독·맞추기 타이머·진행 중 요청 거두기(파일은 고칠 때마다 이미 쓰였다) — 오버레이 보드보다 먼저, kv flush 앞.
        ShutdownStep.Always(STEP_TODO_STOP) { todo.close() },
        ShutdownStep.Always(STEP_OVERLAY_STOP) { overlay.stop() },
        ShutdownStep.Always(STEP_WORK_STOP) {
            workStatusJob?.cancel()
            launchJob?.cancel()
            flyoutJobs.forEach { it.cancel() }
            flyoutJobs.clear()
            work.stop()
        },
        // 단축키 등록 풀기 — 근무 루프가 내려간 뒤라 늦은 토글 없음.
        ShutdownStep.Always(STEP_OS_STOP) { os.stop() },
        ShutdownStep.Always(STEP_SHELL_STOP) { shell.stop() },
        // 근무 마무리·토큰 캐시·오버레이 자리·껍데기 저장이 모두 kv 에 쓴 뒤(close 뒤 늦은 put 은 바로 쓴다).
        ShutdownStep.Always(STEP_KV_FLUSH) { os.flushKeyValueStore() },
    )

    companion object {
        const val STEP_WORK_FINISH = "work.finishForQuit"
        const val STEP_TOKENS_PERSIST = "tokens.persistForTermination"
        const val STEP_TOKENS_STOP = "tokens.stop"
        const val STEP_REALTIME_SHUTDOWN = "social.shutdown"
        const val STEP_GAMES_STOP = "games.stop"
        const val STEP_TODO_STOP = TodoWiring.STEP_TODO_STOP
        const val STEP_OVERLAY_STOP = "overlay.stop"
        const val STEP_WORK_STOP = "work.stop"
        const val STEP_SHELL_STOP = "shell.stop"
        const val STEP_OS_STOP = OsWiring.STEP_OS_STOP
        const val STEP_KV_FLUSH = OsWiring.STEP_KV_FLUSH

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
