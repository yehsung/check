// 원본: Sources/CheckMobileKit/App/MobileAppModel.swift · Sources/CheckMobileKit/App/MobileEnvironment.swift(조립 재료) @ 3bd04bd
package com.yehsung.aingcheck.feature.phone.app

import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.Logger
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransport
import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.stores.characters.AppUserCharacterStore
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.games.GamesRouteRequest
import com.yehsung.aingcheck.core.stores.games.GamesRouteStep
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.gomoku.SessionGomokuHost
import com.yehsung.aingcheck.core.stores.me.DrawableCharacterSource
import com.yehsung.aingcheck.core.stores.me.MeRoute
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.RubyBalanceCell
import com.yehsung.aingcheck.core.stores.me.equippedCharacterID
import com.yehsung.aingcheck.core.stores.me.presentCakeGiftIfDue
import com.yehsung.aingcheck.core.stores.me.refreshAchievementsAfterGameResult
import com.yehsung.aingcheck.core.stores.me.weeklyWorkDidChange
import com.yehsung.aingcheck.core.stores.messages.MegaphoneBannerStore
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.now.NowStore
import com.yehsung.aingcheck.core.stores.now.NowTodoStorage
import com.yehsung.aingcheck.core.stores.rankings.RankingsStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.feature.phone.push.PhonePushCoordinator
import com.yehsung.aingcheck.feature.phone.realtime.PhoneRealtimeRunner
import com.yehsung.aingcheck.feature.phone.realtime.RealtimeSignalReceiver
import com.yehsung.aingcheck.feature.phone.routing.PhoneBadges
import com.yehsung.aingcheck.feature.phone.routing.PhoneRouteTarget
import com.yehsung.aingcheck.feature.phone.routing.PhoneRouter
import com.yehsung.aingcheck.feature.phone.routing.PhoneTab
import com.yehsung.aingcheck.feature.phone.widget.NowWidgetSnapshotSink
import com.yehsung.aingcheck.feature.phone.widget.WidgetSnapshotFile
import com.yehsung.aingcheck.feature.phone.widget.WidgetSnapshotWriter
import com.yehsung.aingcheck.feature.phone.work.PhoneWorkController
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * 폰 앱 조립 재료(Swift `MobileEnvironment`). 조립 지점(Android `AppContainer` — K11 조정자)이 플랫폼 구현을 채워 넘긴다. 벽시계([clock])·
 * HTTP 엔진([service])·금고·설치 식별자는 전부 조립 지점에서만 만든다(구조 시험 R2 · 단일 HTTP 팩토리 G §8-12).
 */
class PhoneEnvironment(
    val service: SupabaseWorkService,
    val vault: TokenVault,
    val prefs: KeyValueStore,
    val appInfo: AppInfo,
    val installationIdentity: InstallationIdentity,
    val clock: SessionClock,
    val instanceGuard: SingleInstanceGuard,
    /** 앱 구성(판돈 대결 깃발 — §8-17 #1, BuildConfig 를 읽는 곳은 조립 한 곳). */
    val appConfig: AppConfig,
    /** 스토어·세션이 도는 자리(앱 = `Dispatchers.Main.immediate` 한 줄기). */
    val scope: CoroutineScope,
    /** 실시간 소켓(시험 프로세스에서는 null — 실 전송자는 시험에서 태어나지 못한다, C§4 #17). */
    val realtimeTransport: RealtimeTransport?,
    /** 벽시계 타이머(실시간 주기 점검 · 지금 탭 60초 새로고침)를 띄울지. 시험·데모 고정 시계는 false. */
    val runsTimers: Boolean,
    /** 위젯 스냅숏 파일(앱 전용 폴더의 `widget-snapshot.json`). */
    val widgetFile: WidgetSnapshotFile,
    /** 위젯 타임라인 새로고침(Glance `updateAll` — 조립이 넣는다). */
    val reloadWidgetTimelines: () -> Unit,
    /** 할 일 파일 자리(위젯 체크와 같은 파일 — W2-b). */
    val todoStorage: NowTodoStorage,
    /** 이름 정렬(Swift `localizedStandardCompare` — W1-c NaturalKoCollation). */
    val collation: Collation,
    /** K9: 번들에 초상이 실린 캐릭터(ui `CharacterArt.drawableCharacterSource`). */
    val drawableCharacters: DrawableCharacterSource,
    /** 이 빌드가 초상을 그릴 수 있는 캐릭터 id(캐릭터 한 표 — 모르는 id 를 입은 사람은 이니셜). */
    val knownCharacterIDs: List<String>,
    val logger: Logger? = null,
    /** 데모 조립(stub 변형). 스토어는 이 값으로 동작을 바꾸지 않는다 — 설명 시트만 띄우지 않는다. */
    val isDemo: Boolean = false,
)

/**
 * 폰 앱의 컨테이너(Swift `MobileAppModel` · SPEC-ios-build §1-4). 세션 · 라우터 · 실시간 · 위젯 스냅숏 · 오목·체스·테트리스 · 탭 스토어 5개 · 폰 근무 ·
 * 푸시를 한 번 만들고 수명을 잇는다. Android 조립(K11)은 [PhoneEnvironment] 를 채워 이것을 하나 만들고, 셸의 수명 사건을 이 문으로 넘긴다
 * (조립 순서는 저장소 밖 assembly.md).
 *
 * 수명 규칙(탭 스토어가 기대해도 되는 것 — Swift 그대로)
 * - 스토어는 앱 실행 동안 하나다. 로그인 전에도 만들어져 있다.
 * - [sceneDidBecomeActive] 는 프로세스가 앞으로 올 때(`ProcessLifecycleOwner` ON_START). 스토어 활성화는 **로그인 상태에서만**.
 * - [sceneDidEnterBackground] 는 ON_STOP(ON_PAUSE 는 끊지 않는다 — E§5.1).
 * - 세대가 바뀌면(로그아웃·치명 만료) 전부 `reset()` 한다 — 오목·체스·테트리스·라우터·루비 미러·실시간·위젯도 함께.
 */
class PhoneAppModel(val environment: PhoneEnvironment) {
    val session: SessionStore
    val router: PhoneRouter = PhoneRouter()
    val realtime: PhoneRealtimeRunner
    val widgets: WidgetSnapshotWriter

    /** 루비 칸 **하나**(오목·체스·테트리스·확성기·나 탭·폰 근무 지갑). */
    val ruby: RubyBalanceCell = RubyBalanceCell()
    val links: PhoneStoreLinks = PhoneStoreLinks()
    val context: PhoneContext
    val gomokuHost: SessionGomokuHost
    val gomoku: GomokuStore
    val chess: ChessStore
    val tetris: TetrisDuelStore
    val characters: AppUserCharacterStore
    val push: PhonePushCoordinator
    val now: NowStore
    val messages: MessagesStore

    /** 확성기 배너(2026-10-30 — Swift `MobileAppModel.megaphoneBanner` @ a6791165). 셸이 탭 위 오버레이로 [MegaphoneBannerStore.current] 를 그린다. */
    val megaphoneBanner: MegaphoneBannerStore

    /** 지금 시트·대화상자가 떠 있는가(셸이 채운다 — 오버레이가 그 밑에 깔리면 미룬다). Swift `megaphoneModalProbe`. */
    var megaphoneModalProbe: () -> Boolean = { false }
    val rankings: RankingsStore
    val gamesContext: PhoneGamesContext
    val games: GamesStore
    val me: MeStore
    val work: PhoneWorkController
    val widgetSink: NowWidgetSnapshotSink

    var isSceneActive: Boolean = false
        private set
    private var started = false
    private var startJob: Job? = null

    /**
     * 실행 복원(`Launching`) 중에 온 딥링크. 로그인 상태가 되는 순간 연다 — 복원이 로그아웃·업데이트 필요로 끝나면 버린다(앱이 꺼진 채 위젯·알림으로
     * 열리면 링크가 client_release 왕복보다 먼저 온다 — dbase-fix 검증 V1).
     */
    var pendingLaunchRoute: PhoneRouteTarget? = null
        private set

    init {
        val env = environment
        val scope = env.scope
        session = SessionStore(
            service = env.service,
            vault = env.vault,
            prefs = env.prefs,
            appInfo = env.appInfo,
            installationIdentity = env.installationIdentity,
            clock = env.clock,
            instanceGuard = env.instanceGuard,
            parentScope = scope,
        )
        realtime = PhoneRealtimeRunner(env.service, env.realtimeTransport, env.clock, scope, runsTimers = env.runsTimers)
        realtime.attach(session)
        widgets = WidgetSnapshotWriter(env.widgetFile, env.clock, scope, env.reloadWidgetTimelines)
        context = PhoneContext(session, env.appConfig, ruby, router, realtime, widgets, links, scope, env.collation, env.logger)

        gomokuHost = SessionGomokuHost(context, ruby, realtime = { realtime.state }, logger = env.logger)
        gomoku = GomokuStore(scope, gomokuHost)
        // 순위표·관전의 **주 스위치**. 기본이 꺼짐이라 이 한 줄이 없으면 `gomoku_ranking`·`gomoku_watch` 가 한 번도 안 나간다 — 화면이 죽는데
        // 빨간 시험이 없다(Swift 머리말). "기본값이니 지워도 되겠지"로 지우지 마라(PhoneAppModelTest 가 요청 건수로 잰다).
        gomoku.spectatorFeaturesEnabled = true
        chess = ChessStore(scope, gomokuHost)
        // 체스 순위·관전의 주 스위치(오목 한 줄과 짝).
        chess.spectatorFeaturesEnabled = true
        tetris = TetrisDuelStore(PhoneTetrisHost(context, ruby), scope, clock = { env.clock.now() }, collation = env.collation, logger = env.logger)
        // 한 판 한 기기(0.3.69 — 코어 머리말 ⑩ · Swift MobileAppModel 75c31cd2): '이 기기가 연 판' 기록을 둘 곳. 빠지면 기록이 프로세스 안에만
        // 살아, 판 중에 앱을 다시 켠 폰이 옛 서버(my_device 없음)에서 자기 판을 못 알아본다.
        tetris.defaults = env.prefs
        // 테트리스 순위 · 관전의 주 스위치(순위와 관전은 **따로** — 코어 규약).
        tetris.rankingEnabled = true
        tetris.spectatorFeaturesEnabled = true
        realtime.gomoku = object : RealtimeSignalReceiver {
            override fun handleSignal() = gomoku.handleSignal()
            override fun realtimeDidJoin() = gomoku.realtimeDidJoin()
        }
        // 실시간 'tetris' 초인종을 받을 자리(오목 바로 옆 · 같은 꼴). 이 줄이 없으면 러너의 테트리스 가지가 아무 일도 안 한다 — 방해 줄이
        // 자기 보고 왕복(1초)까지 늦고, 조인 따라잡기도 안 돈다.
        realtime.tetris = object : RealtimeSignalReceiver {
            override fun handleSignal() = tetris.handleSignal()
            override fun realtimeDidJoin() = tetris.realtimeDidJoin()
        }
        characters = AppUserCharacterStore(context, scope, env.knownCharacterIDs)
        context.gomoku = gomoku
        context.chess = chess
        context.tetris = tetris
        context.characters = characters

        push = PhonePushCoordinator(context, isDemo = env.isDemo)
        now = NowStore(context, scope, env.todoStorage, runsPeriodicRefresh = env.runsTimers)
        messages = MessagesStore(context, scope, env.collation, megaphoneHost = PhoneMegaphoneHost(context, ruby))
        megaphoneBanner = MegaphoneBannerStore(PhoneMegaphoneHost(context, ruby), scope, env.prefs, clock = { env.clock.now() })
        rankings = RankingsStore(context, scope, env.collation)
        gamesContext = PhoneGamesContext(context, PhoneGomokuLink(gomoku), PhoneChessLink(chess))
        games = GamesStore(gamesContext)
        me = MeStore(context, scope, env.drawableCharacters)
        work = PhoneWorkController(now, ruby, weeklyWorkDidChange = { me.weeklyWorkDidChange() }, reloadWidgets = env.reloadWidgetTimelines)
        widgetSink = NowWidgetSnapshotSink(
            now = now,
            writer = widgets,
            equippedCharacterID = { if (me.equippedLoaded) me.equippedCharacterID else null },
            characterFor = { userID -> characters.directory.characterID(userID) },
        )

        links.push = push
        links.now = now
        links.messages = messages
        links.rankings = rankings
        links.games = games
        links.me = me
        links.work = work
        links.widgetSink = widgetSink
        links.megaphoneBanner = megaphoneBanner
        // 확성기 배너 배선(Swift cec08cb1 · 8b40bd44): 메시지함 필터(visibleHistory · 요약 v2) · 미룸 · 실시간 'megaphone' · 보낸 뒤 내 배너.
        // 메시지 스토어에 이 한 줄이 없으면 확성기 줄이 메시지로 남고 요약은 옛 함수다(배너와 메시지함에 두 번 보인다).
        messages.megaphoneBanner = megaphoneBanner
        megaphoneBanner.isBannerDeferred = { isMegaphoneBannerDeferred }
        // 필터가 켜지거나 꺼지면 메시지함이 요약 함수 짝을 다시 맞춘다 — refresh 가 실시간·푸시 어느 길로 왔든(Swift f3360b47).
        megaphoneBanner.onCapabilityChange = { messages.megaphoneFilterDidSettle() }
        realtime.megaphone = { scope.launch { megaphoneBanner.refresh() } }
        messages.megaphone.onSent = { body, megaphoneID ->
            megaphoneBanner.presentOwn(body, me.displayName.orEmpty(), me.avatarURL?.absoluteString, megaphoneID)
        }
        // 딥링크 대상 해석 한 문 — 푸시 조정자(알림 탭 · [수락] 뒤 열기)가 라우터를 바로 부르지 않고 이 규칙을 지난다(W2-f 검증 7차 지적).
        links.routeResolver = { target -> openRoute(target) }
        now.phoneWork = work
        now.widgetSink = widgetSink
        messages.nowStore = now
        messages.router = router
        // 메시지 탭이 실시간 신호를 받는 자리(Swift 는 MessagesStore.init 이 등록했다 — Kotlin 은 조립이 잇는다). `.drain` 은 take_pokes 가 아니라
        // 이 조회다(C§4 #15).
        realtime.onMessageActivity { messages.realtimeMessageActivity() }
        realtime.onMessageRead { messages.realtimeMessageRead() }
        // 표가 바뀌면 위젯 근무 중 얼굴도 다시 쓴다(지금 탭이 위젯의 유일한 작성자 — 같은 값이면 쓰기 창구가 건너뛴다).
        characters.onDirectoryChange = { widgetSink.writeAfterDirectoryChange() }
        // 일일 미션(v0.3.64) — 1:1 판이 끝난 것을 처음 보는 자리. 게임 이름은 서버 `daily_mission_defs()` 의 game 값이다(1:1 테트리스는 `tetris_duel`).
        gomoku.onMatchFinished = { me.refreshAchievementsAfterGameResult(GAME_GOMOKU) }
        chess.onMatchFinished = { me.refreshAchievementsAfterGameResult(GAME_CHESS) }
        tetris.onMatchFinished = { me.refreshAchievementsAfterGameResult(GAME_TETRIS_DUEL) }

        session.onSignedIn = { sessionDidSignIn() }
        session.onSignedOut = { sessionDidSignOut() }
        session.onAccessTokenChanged = { token -> realtime.accessTokenDidChange(token) }
        // 로컬 사용자 데이터를 지운 직후(로그아웃 · 만료 · 삭제) 위젯 스냅숏을 지우고 바로 새로 그린다(위젯이 앞 계정을 그리지 않게).
        session.onLocalUserDataCleared = { widgets.clear() }
    }

    /** 탭 배지(메시지 · 게임 · 나). */
    val badges: PhoneBadges get() = links.badges

    /**
     * 탭을 바꿨을 때(탭 막대). 캐릭터 한 표만 60초 스로틀로 다시 묻는다. 대국·관전 화면 때문에 미뤄 둔 생일 선물 축하 시트도 이때 띄운다 —
     * 게임 탭으로 **들어갈** 때는 띄우지 않는다(그 탭의 대국 화면은 곧 선다).
     */
    fun tabDidChange(tab: PhoneTab) {
        router.selectedTab = tab
        if (!session.isSignedIn) return
        characters.refreshIfStale()
        if (tab != PhoneTab.games) me.presentCakeGiftIfDue()
    }

    // ---------------------------------------------------------------- 시작 · 수명 · 딥링크

    /** 한 번만 돈다: client_release → 세션 복원. 복원이 로그아웃·업데이트 필요로 끝나면 붙잡은 링크를 버린다. */
    fun start(): Job? {
        if (started) return startJob
        started = true
        val job = environment.scope.launch {
            session.launch()
            if (!session.isSignedIn) pendingLaunchRoute = null
        }
        startJob = job
        return job
    }

    fun sceneDidBecomeActive() {
        if (isSceneActive) return
        isSceneActive = true
        session.appDidBecomeActive()
        realtime.appDidBecomeActive()
        if (!session.isSignedIn) return
        activateStores()
    }

    fun sceneDidEnterBackground() {
        if (!isSceneActive) return
        isSceneActive = false
        realtime.appDidEnterBackground()
        now.appDidEnterBackground()
        messages.appDidEnterBackground()
        rankings.appDidEnterBackground()
        games.appDidEnterBackground()
        me.appDidEnterBackground()
        push.appDidEnterBackground()
    }

    /**
     * 딥링크(위젯 · 알림 · `aingcheck://`)로 열기. 실행 복원 중이면 붙잡아 두었다가 로그인 상태가 되면 연다(true). 로그아웃·업데이트 필요 상태면
     * 무시한다(false) — 로그인 화면 뒤에 남의 대화가 열리지 않게.
     */
    fun handleOpenRoute(target: PhoneRouteTarget): Boolean {
        if (session.phase == SessionPhase.Launching) {
            pendingLaunchRoute = target
            return true
        }
        if (!session.isSignedIn) return false
        openRoute(target)
        return true
    }

    /**
     * **딥링크 대상 해석** — 대상을 그 탭 스토어의 규칙으로 걸러 라우터에 쌓는다(Swift 는 탭이 `consumePendingRoute` 로 꺼내 이 일을 했다. Android 는
     * 셸이 탭별 백스택을 쥐므로 여는 순간 한 번에 정한다). 딥링크·위젯([handleOpenRoute]) · 알림 탭·[수락]([PhonePushCoordinator] —
     * [PhoneStoreLinks.routeResolver] 로 이 함수에 닿는다)이 모두 이 한 문을 지난다.
     * - 게임(오목 셋 · 미니게임): W2-e `GamesStore.routeStep` — 체스·테트리스 판이 흐르는 동안 온 오목 링크와 이 빌드에 보이지 않는 미니게임
     *   (길건너 — §8-18 #7)은 게임 탭 첫 화면에 세운다. 오목 화면이 이미 떠 있으면 대상 판을 코어에 바로 넘긴다.
     *   INV-MobileAppModel-14155396 이식: (딥링크 몫) `games/tetris` 한 토막은 **솔로** 테트리스 미니게임 링크다 — 1:1 테트리스로 가로채면 이미
     *   나간 솔로 딥링크가 조용히 사라진다. 그래서 미니게임 요청은 다시 판정하지 않고 게임 탭 규칙(`routeStep`) 한 곳에 그대로 넘긴다
     *   (데모 장면 접두 `games/tetris/…` 는 Android 에 없다 — 데모 라우트 몫 둘은 해당 없음, 조정자 패치 inv-na).
     * - 체스(Android 만): 오목·테트리스 판이 흐르면([GamesStore.chessEntryBlock]) 게임 탭 첫 화면에 세운다(한 사람 한 판 — 세 방향).
     * - 나: 탭을 뿌리로 열고 `MeStore.open` 이 하위 화면을 쌓는다(제보 링크는 그 제보에 초점).
     * - 순위: 판을 고른다. 그 밖(지금 · 메시지)은 그대로 연다.
     */
    fun openRoute(target: PhoneRouteTarget) {
        when (target) {
            is PhoneRouteTarget.Games -> when (val step = games.routeStep(target.request)) {
                null -> return
                GamesRouteStep.PopToRoot -> router.open(PhoneRouteTarget.Games(GamesRouteRequest.Games))
                is GamesRouteStep.Push -> router.open(target)
            }
            PhoneRouteTarget.ChessLobby, is PhoneRouteTarget.ChessInvite, is PhoneRouteTarget.ChessMatch ->
                if (games.chessEntryBlock != null) router.open(PhoneRouteTarget.Games(GamesRouteRequest.Games)) else router.open(target)
            is PhoneRouteTarget.Me -> {
                router.open(PhoneRouteTarget.Me(MeRoute.Me))
                if (target.route != MeRoute.Me) me.open(target.route)
            }
            is PhoneRouteTarget.Rankings -> {
                router.open(target)
                rankings.open(target.board)
            }
            PhoneRouteTarget.Now, PhoneRouteTarget.Messages, is PhoneRouteTarget.Message -> router.open(target)
        }
    }

    // ---------------------------------------------------------------- 세션 사건

    private fun sessionDidSignIn() {
        realtime.sessionDidSignIn()
        push.sessionDidSignIn()
        // 착용 캐릭터 한 칸만 미리 받는다 — 나 탭을 열기 전에도 지금·순위·게임·탭 막대가 내 캐릭터로 선다.
        me.primeEquippedCharacter()
        // 캐릭터 한 표도 로그인 직후 한 번(그 뒤는 기존 갱신 시점에 60초 스로틀).
        characters.refresh()
        if (isSceneActive) activateStores()
        val route = pendingLaunchRoute
        if (route != null) {
            pendingLaunchRoute = null
            openRoute(route)
        }
    }

    private fun sessionDidSignOut() {
        realtime.sessionDidSignOut()
        gomoku.reset()
        // 체스도 같은 사슬이다 — 안 넣으면 다음 사람의 로비에 앞 사람의 판·신청·순위가 남는다.
        chess.reset()
        // 테트리스도 같은 사슬이다 — 판 구동기와 1초 보고가 살아 있으면 로그아웃한 사람의 판에 새 계정의 토큰으로 보고가 나간다.
        tetris.reset()
        ruby.rubyBalance = null
        router.reset()
        widgets.forgetCurrent()
        now.reset()
        // 배너 스토어가 먼저 — 메시지 스토어의 필터가 앞 계정의 확성기 id 로 다음 계정의 줄을 거르지 않게.
        megaphoneBanner.reset()
        messages.reset()
        rankings.reset()
        games.reset()
        me.reset()
        push.reset()
        characters.reset()
    }

    private fun activateStores() {
        now.appDidBecomeActive()
        messages.appDidBecomeActive()
        rankings.appDidBecomeActive()
        games.appDidBecomeActive()
        me.appDidBecomeActive()
        push.appDidBecomeActive()
        characters.refreshIfStale()
    }

    companion object {
        /** 서버 `daily_mission_defs()` 의 game 값(일일 미션 판정 — 솔로 `tetris` 가 아니다). */
        const val GAME_GOMOKU: String = "gomoku"
        const val GAME_CHESS: String = "chess"
        const val GAME_TETRIS_DUEL: String = "tetris_duel"
    }
}
