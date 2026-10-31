import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// 폰 앱의 컨테이너(SPEC-ios-build §1-4). 세션 · 라우터 · 실시간 · 위젯 스냅샷 · 오목 · 탭 스토어 5개 · 푸시를 한 번 만들고 수명을 잇는다.
///
/// 수명 규칙(탭 스토어가 기대해도 되는 것)
/// - 스토어는 앱 실행 동안 하나다. 로그인 전에도 만들어져 있다.
/// - `appDidBecomeActive()` 는 **로그인 상태에서만** 부른다: scenePhase 가 active 가 될 때, 그리고 active 인 채로 로그인이 끝났을 때.
/// - `appDidEnterBackground()` 는 scenePhase 가 background 로 갈 때 부른다(로그인 여부와 무관).
/// - 세대가 바뀌면(로그아웃·치명 만료) 전부 `reset()` 한다 — 오목 스토어·라우터·루비 미러·실시간도 함께.
@MainActor
@Observable
public final class MobileAppModel {
    @ObservationIgnored package let environment: MobileEnvironment
    package let session: MobileSessionStore
    package let router: MobileRouter
    package let realtime: MobileRealtimeRunner
    @ObservationIgnored package let widgetSnapshots: WidgetSnapshotWriter
    package let gomokuHost: MobileGomokuHost
    package let gomoku: GomokuStore
    package let chess: ChessStore
    package let tetris: TetrisDuelStore
    @ObservationIgnored package let links: MobileStoreLinks
    @ObservationIgnored package let context: MobileContext
    package let push: PushCoordinator
    package let now: NowStore
    package let messages: MessagesStore
    package let rankings: RankingsStore
    package let games: GamesStore
    package let me: MeStore
    /// 확성기 배너(코어 `MegaphoneBannerStore` — 맥과 한 벌). 메시지함 필터·푸시·실시간·전송 뒤 내 배너가 이 하나를 쓴다.
    /// 호스트는 오목·체스·확성기 작성과 같은 하나(`gomokuHost`). 로그아웃 사슬(`sessionDidSignOut`)에서 비운다.
    package let megaphoneBanner: MegaphoneBannerStore
    /// 시트·풀스크린 커버가 떠 있는가(배너 미룸의 한 갈래 — `isMegaphoneBannerDeferred`). 시험이 바꿔 끼운다.
    @ObservationIgnored package var megaphoneModalProbe: @MainActor () -> Bool = { MegaphoneBannerModalProbe.isModalPresented() }
    /// 화면 모드(기기 설정). `sessionDidSignOut` 의 reset 사슬에 넣지 않는다 — 로그아웃해도 남는다.
    package let appearance: MobileAppearanceStore
    /// 캐릭터 한 표(사람 아바타 = 사진 → 착용 캐릭터 → 이니셜). 탭 막대가 환경값으로 흘린다. 로그아웃하면 비운다.
    package let characters: AppUserCharacterStore

    package private(set) var isSceneActive = false
    @ObservationIgnored private var started = false
    /// 실행 복원(`.launching`) 중에 온 딥링크. 로그인 상태가 되는 순간 연다 — 복원이 로그아웃·업데이트 필요로 끝나면 버린다.
    /// 앱이 꺼진 채 위젯·링크로 열리면 `onOpenURL` 이 client_release 왕복보다 먼저 오고, 위젯은 URL 을 다시 주지 않는다(dbase-fix · 검증 V1).
    @ObservationIgnored package private(set) var pendingLaunchRoute: AingRoute?

    /// 프로덕션 진입점. DEBUG 빌드에서 `-AingCheckDemo YES` 가 있으면 데모 조립(스텁 서버·고정 시계)을 쓴다.
    public static func bootstrap(arguments: [String] = ProcessInfo.processInfo.arguments) -> MobileAppModel {
        #if DEBUG
        if let demo = MobileDemo.environment(arguments: arguments) {
            return MobileAppModel(environment: demo)
        }
        #endif
        return MobileAppModel(environment: .live())
    }

    package init(environment env: MobileEnvironment) {
        environment = env
        let session = MobileSessionStore(
            service: env.service,
            vault: env.vault,
            storage: env.storage,
            appInfo: env.appInfo,
            installationID: env.installationID,
            clock: env.clock
        )
        session.reloadWidgetTimelines = env.reloadWidgetTimelines
        let router = MobileRouter()
        let realtime = MobileRealtimeRunner(
            service: env.service,
            transport: env.realtimeTransport,
            clock: env.clock,
            runsTimers: env.runsTimers
        )
        realtime.attach(session: session)
        let writer = WidgetSnapshotWriter(
            url: env.storage.widgetSnapshotURL,
            clock: env.clock,
            reloadTimelines: env.reloadWidgetTimelines
        )
        let host = MobileGomokuHost(sessionStore: session, realtime: realtime)
        let gomoku = GomokuStore(host: host)
        let clock = env.clock
        gomoku.clock = { clock.now() }
        // 순위표·관전(0.3.41)의 **주 스위치**. 기본이 꺼짐(`GomokuStore.spectatorFeaturesEnabled`)이라 이 한 줄이 없으면
        // `gomoku_ranking`·`gomoku_watch` 가 **한 번도 안 나간다** — `loadRanking`·`startWatching`·`refreshWatch` 와
        // `pollTick`·`windowDidShow` 의 두 분기가 전부 이 값을 먼저 본다(`canPollSpectatorFeatures`).
        // 빠지면 순위 절은 영영 로딩 문구이고 [관전] 은 눌러도 관전 상태조차 서지 않는다. **화면이 죽는데 빨간 테스트가 없다**
        // (뷰 파일은 `#if os(iOS)` 안이라 맥 스위트가 못 본다) — 그래서 못을 따로 박아 두었다:
        // `Tests/CheckMobileKitTests/GamesGomokuSpectateWiringTests.swift`.
        // **"기본값이니 지워도 되겠지"로 지우지 마라.** 꺼짐은 0.3.41 맥 작업이 남긴 의도된 보호다 — 그리지도 않는 폰이
        // 순위를 1분마다 당기지 않게 맥 배선(`CheckApp.wireGomoku` · CheckApp.swift:248)만 켰다. 폰이 그 화면을 갖는
        // 지금은 폰도 자기 배선에서 켠다(같은 스토어를 쓰는 두 앱의 유일한 차이라 배선에만 있다).
        gomoku.spectatorFeaturesEnabled = true
        realtime.gomoku = gomoku
        // 1:1 체스(0.3.44 서버·맥 · 폰은 이 세션부터). 호스트는 **오목과 같은 하나**다 —
        // `ChessStoreHost` 는 `GomokuStoreHost` 의 별명이고(ChessStore.swift:43), 루비 미러를 한 칸으로 두면
        // 체스 정산이 오목·상점과 같은 잔액을 적는다(두 벌이면 탭마다 다른 잔액이 보인다).
        let chess = ChessStore(host: host)
        chess.clock = { clock.now() }
        // 순위·관전(체스)의 **주 스위치**. 기본이 꺼짐(`ChessStore.spectatorFeaturesEnabled`, ChessStore.swift:745)이라
        // 이 한 줄이 없으면 `chess_ranking`·`chess_watch` 가 **한 번도 안 나간다** — `loadRanking`·`startWatching`·
        // `refreshWatch` 와 `pollTick`·`windowDidShow` 의 두 분기가 전부 `canPollSpectatorFeatures` 를 먼저 본다.
        // 빠지면 순위 절은 영영 로딩 문구이고 [관전]은 눌러도 관전 상태조차 서지 않는다. **화면이 죽는데 빨간
        // 테스트가 없다**(뷰 파일은 `#if os(iOS)` 안이라 맥 스위트가 못 본다) — 그래서 못을 따로 박아 두었다:
        // `Tests/CheckMobileKitTests/GamesChessWiringTests.swift`(켠 효과를 **요청 건수**로 재고, 스위치만
        // 되돌린 기준선과 나란히 본다).
        // **"기본값이니 지워도 되겠지"로 지우지 마라.** 꺼짐은 맥 작업이 남긴 의도된 보호다(그리지도 않는 폰이
        // 순위를 1분마다 당기지 않게) — 폰이 그 화면을 갖는 지금은 폰도 자기 배선에서 켠다. 바로 위 오목 한 줄과 짝이다.
        chess.spectatorFeaturesEnabled = true
        // 1:1 테트리스(0.3.60 서버·맥 · 폰은 1.0.11). 호스트는 **오목·체스와 같은 하나**다(루비 미러 한 칸).
        let tetris = TetrisDuelStore(host: host)
        tetris.clock = { clock.now() }
        // 한 판 한 기기(0.3.69 — 코어 머리말 ⑩): '이 기기가 연 판' 기록을 둘 곳. 빠지면 기록이 프로세스 안에만 살아, 판 중에
        // 앱을 다시 켠 폰이 옛 서버(my_device 없음)에서 자기 판을 못 알아본다.
        tetris.defaults = env.storage.defaults
        // 순위의 **주 스위치**. 기본이 꺼짐이라 이 한 줄이 없으면 `tetris_ranking` 이 **한 번도 안 나가고**
        // 순위 탭은 영영 로딩 문구다 — 오목·체스의 바로 위 두 줄과 같은 못이고, 같은 까닭으로 지우지 마라
        // (뷰는 `#if os(iOS)` 안이라 맥 스위트가 못 본다). 못: `Tests/CheckMobileKitTests/GamesTetrisDuelWiringTests.swift`
        // (`GamesTetrisWiringTests` 는 **솔로** 테트리스 것이다 — 섞지 마라).
        tetris.rankingEnabled = true
        // 관전의 **주 스위치**(0.3.65 — 테트리스 관전은 이번에 생겼다). 기본이 꺼짐이라 이 한 줄이 없으면
        // [관전] 칩이 뜨지도 않고 `tetris_watch` 가 **한 번도 안 나간다** — `startWatching`·`refreshWatch`·
        // `pollWatch`·`spectatorWindowDidShow` 가 전부 `spectatorFeaturesEnabled` 를 먼저 본다
        // (`canPollSpectatorFeatures`). 순위 스위치와 **따로** 두는 것이 코어 규약이다(순위 없이 관전만 여는 날).
        // 바로 위 오목·체스 두 줄과 같은 못이고, 같은 까닭으로 "기본값이니 지워도 되겠지"로 지우지 마라
        // (뷰는 `#if os(iOS)` 안이라 맥 스위트가 못 본다). 못: `Tests/CheckMobileKitTests/GamesTetrisWatchTests.swift`.
        tetris.spectatorFeaturesEnabled = true
        // 실시간 'tetris' 초인종을 받을 자리(오목 `realtime.gomoku` 바로 옆 · 같은 꼴). 이 한 줄이 없으면
        // 러너의 `.tetrisSignal` 가지가 **nil 에 말을 걸어** 아무 일도 안 한다 — 초인종이 와도 폰은 자기 보고
        // 왕복(1초)까지 방해 줄을 모르고, 조인 따라잡기(`.catchUp` → `realtimeDidJoin`)도 안 돈다.
        // 러너는 **약한 참조**로 들고 있고(수명은 앱 모델이 쥔다) 핸들러가 스스로 세션 가드를 한다.
        realtime.tetris = tetris
        let links = MobileStoreLinks()
        // 본 것 기록(계정별 최근 100개)은 앱 기본값 저장소에 — 재실행해도 같은 확성기를 두 번 안 띄운다(코어 머리말 ⑤).
        let megaphoneBanner = MegaphoneBannerStore(host: host, defaults: env.storage.defaults, clock: { clock.now() })
        // 실시간 'megaphone' 신호를 받을 자리(오목·테트리스 칸과 같은 꼴 — 러너는 약한 참조).
        realtime.megaphoneBanner = megaphoneBanner
        let appearance = MobileAppearanceStore(defaults: env.appearanceDefaults ?? env.storage.defaults)
        let characters = AppUserCharacterStore(session: session, clock: env.clock)
        let context = MobileContext(
            service: env.service,
            session: session,
            clock: env.clock,
            router: router,
            realtime: realtime,
            widgetSnapshots: writer,
            gomoku: gomoku,
            chess: chess,
            tetris: tetris,
            gomokuHost: host,
            storage: env.storage,
            appInfo: env.appInfo,
            isDemo: env.isDemo,
            links: links,
            appearance: appearance,
            characters: characters
        )

        self.session = session
        self.router = router
        self.realtime = realtime
        self.widgetSnapshots = writer
        self.gomokuHost = host
        self.gomoku = gomoku
        self.chess = chess
        self.tetris = tetris
        self.links = links
        self.appearance = appearance
        self.characters = characters
        self.megaphoneBanner = megaphoneBanner
        self.context = context
        self.push = PushCoordinator(context: context)
        self.now = NowStore(context: context)
        self.messages = MessagesStore(context: context)
        self.rankings = RankingsStore(context: context)
        self.games = GamesStore(context: context)
        self.me = MeStore(context: context)

        links.push = push
        links.now = now
        links.messages = messages
        links.rankings = rankings
        links.games = games
        links.me = me
        links.megaphoneBanner = megaphoneBanner
        // 배너 미룸(계약 — 폰 배너): 시트·대결 화면·미니게임 판. 바뀌는 순간은 배너 오버레이가 `syncMegaphoneBannerDeferral()` 로 알린다.
        megaphoneBanner.isBannerDeferred = { [weak self] in self?.isMegaphoneBannerDeferred ?? false }
        // 필터가 켜지거나 꺼지면 메시지함이 요약 함수 짝을 다시 맞춘다 — refresh 가 실시간·푸시 어느 길로 왔든.
        megaphoneBanner.onCapabilityChange = { [weak messages] in messages?.megaphoneFilterDidSettle() }
        // 표가 바뀌면 위젯 근무 중 얼굴도 다시 쓴다(지금 탭이 위젯의 유일한 작성자 — 같은 값이면 쓰기 창구가 건너뛴다).
        characters.onDirectoryChange = { [weak now] in now?.writeWidgetSnapshot() }
        // 일일 미션(v0.3.64) — **1:1 판이 끝난 것을 처음 보는 자리**가 여기다(코어 스토어가 `match` 가 끝으로 바뀐 그 자리에서
        // 부른다 — `GomokuStore.matchJustFinished` 계열). 그 순간 미션 진행을 **한 번** 묻는다: 새 타이머도 새 주기 RPC 도 없고,
        // 오늘 그 게임 줄을 이미 채웠으면 요청 0건이다(`MeStore.refreshAchievementsAfterGameResult`).
        // 게임 이름은 **서버 `daily_mission_defs()` 의 game 값**이다 — 1:1 테트리스는 `tetris_duel`(솔로 `tetris` 가 아니다).
        // 맥의 같은 세 줄은 `WorkTimerStore.wireGomoku` 에 있다. 빠지면 "판을 했는데 [받기]가 안 뜬다"가 되고,
        // 뷰가 아니라 배선이라 **화면만 보는 테스트로는 안 잡힌다** — 못: `Tests/CheckMobileKitTests/MeDailyMissionStoreTests.swift`.
        gomoku.onMatchFinished = { [weak me] in me?.refreshAchievementsAfterGameResult(game: "gomoku") }
        chess.onMatchFinished = { [weak me] in me?.refreshAchievementsAfterGameResult(game: "chess") }
        tetris.onMatchFinished = { [weak me] in me?.refreshAchievementsAfterGameResult(game: "tetris_duel") }

        session.onSignedIn = { [weak self] in self?.sessionDidSignIn() }
        session.onSignedOut = { [weak self] in self?.sessionDidSignOut() }
        session.onAccessTokenChanged = { [weak realtime] token in realtime?.accessTokenDidChange(token) }
    }

    /// 탭 배지(메시지 · 게임).
    package var badges: MobileBadges { links.badges }

    /// 탭을 바꿨을 때(탭 막대). 캐릭터 한 표만 60초 스로틀로 다시 묻는다 — 탭 스토어의 갱신은 각 탭 화면이 스스로 한다.
    /// 대국·관전 화면 때문에 미뤄 둔 생일 선물 축하 시트도 이때 띄운다(요청 없음 — 이미 아는 선물만, `MeStore.presentCakeGiftIfDue`).
    /// 게임 탭으로 **들어갈** 때는 띄우지 않는다 — 그 탭의 대국 화면은 아직 안 섰을 뿐 곧 선다(덮으면 진다).
    package func tabDidChange() {
        guard session.isSignedIn else { return }
        characters.refreshIfStale()
        if router.selectedTab != .games { me.presentCakeGiftIfDue() }
    }

    // MARK: - 시작 · scenePhase · URL

    /// 한 번만 돈다: client_release → 세션 복원 → (데모면) 시작 라우트 열기.
    public func start() {
        guard !started else { return }
        started = true
        Task { [weak self] in
            guard let self else { return }
            await self.session.launch()
            if !self.session.isSignedIn {
                // 로그아웃·업데이트 필요로 끝났다 — 복원 중에 붙잡은 링크는 버린다(나중에 로그인해도 열지 않는다).
                self.pendingLaunchRoute = nil
            }
            self.openDemoRouteIfNeeded()
        }
    }

    public func sceneDidBecomeActive() {
        guard !isSceneActive else { return }
        isSceneActive = true
        session.appDidBecomeActive()
        realtime.appDidBecomeActive()
        guard session.isSignedIn else { return }
        activateStores()
    }

    public func sceneDidEnterBackground() {
        guard isSceneActive else { return }
        isSceneActive = false
        realtime.appDidEnterBackground()
        now.appDidEnterBackground()
        messages.appDidEnterBackground()
        rankings.appDidEnterBackground()
        games.appDidEnterBackground()
        me.appDidEnterBackground()
        push.appDidEnterBackground()
    }

    /// `onOpenURL`(위젯 · 외부 링크).
    /// - 실행 복원 중(`.launching`)이면 붙잡아 두었다가 로그인 상태가 되면 연다(true). 모르는 URL 은 false.
    /// - 로그아웃·업데이트 필요 상태면 무시한다(false) — 로그인 화면 뒤에 남의 대화가 열리지 않게.
    @discardableResult
    public func handleOpenURL(_ url: URL) -> Bool {
        if session.phase == .launching {
            guard let route = AingRoute(url: url) else { return false }
            pendingLaunchRoute = route
            return true
        }
        guard session.isSignedIn else { return false }
        return router.open(url: url)
    }

    // MARK: - 푸시 어댑터 전달(ios/App/AppDelegate.swift 가 부른다)

    public func didRegisterForRemoteNotifications(deviceToken: Data) {
        push.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    public func didFailToRegisterForRemoteNotifications(error: Error) {
        push.didFailToRegisterForRemoteNotifications(error: error)
    }

    // MARK: - 세션 사건

    private func sessionDidSignIn() {
        realtime.sessionDidSignIn()
        push.sessionDidSignIn()
        // 착용 캐릭터 한 칸(`profiles.character`)만 미리 받는다 — 나 탭을 열기 전에도 지금·순위·게임·오목·탭 막대가 내 캐릭터로 선다.
        me.primeEquippedCharacter()
        // 캐릭터 한 표도 로그인 직후 한 번 — 사람 아바타가 첫 화면부터 착용 캐릭터로 선다(그 뒤는 기존 갱신 시점에 60초 스로틀).
        characters.refresh()
        if isSceneActive {
            activateStores()
        }
        if let route = pendingLaunchRoute {
            pendingLaunchRoute = nil
            router.open(route)
        }
    }

    private func sessionDidSignOut() {
        realtime.sessionDidSignOut()
        gomoku.reset()
        // 체스도 같은 사슬에 넣는다 — 안 넣으면 다음 사람의 로비에 앞 사람의 판·신청·순위가 남는다.
        // `reset()` 은 배선 값(`spectatorFeaturesEnabled`·`clock`·`presentWindow`)을 건드리지 않는다(위 주 스위치 주석).
        chess.reset()
        // 테트리스도 같은 사슬이다. 안 넣으면 다음 사람의 로비에 **앞 사람의 판·신청·순위·루비**가 남는다 —
        // 테트리스는 거기에 하나가 더 붙는다: 판 구동기(`duel`)와 1초 보고 Task 가 살아 있어서, 로그아웃한
        // 사람의 판에 **새 계정의 토큰으로** 보고가 계속 나간다. `reset()` 이 그 둘(`discardDuel`·세대)을 끊는다.
        // `reset()` 은 배선 값(`rankingEnabled`·`clock`·`presentWindow`)을 건드리지 않는다(위 주 스위치 주석).
        tetris.reset()
        gomokuHost.rubyBalance = nil
        router.reset()
        widgetSnapshots.forgetCurrent()
        now.reset()
        messages.reset()
        rankings.reset()
        games.reset()
        me.reset()
        push.reset()
        characters.reset()
        // 확성기 배너 줄·필터 id·떠 있는 배너 — 남기면 다음 사람 화면에 앞 사람의 배너가 뜨고 그 id 로 메시지함을 거른다.
        megaphoneBanner.reset()
    }

    private func activateStores() {
        now.appDidBecomeActive()
        messages.appDidBecomeActive()
        rankings.appDidBecomeActive()
        games.appDidBecomeActive()
        me.appDidBecomeActive()
        push.appDidBecomeActive()
        characters.refreshIfStale()
    }

    private func openDemoRouteIfNeeded() {
        guard let raw = environment.demoRoute, session.isSignedIn else { return }
        // 체스 데모 장면(`games/chess/…` — 로비·신청·대국·순위·관전)은 **`AingRoute` 에 가지가 없다.**
        // 가지를 더하지 않은 것이 일부러다: 그 열거는 `CheckMobileShared` 에 있고, 체스 라우트가 생기는 날
        // `IntegrationContractTests` 의 '장면 폴더 예외'가 자기 만료 단언으로 빨개진다(픽스처 레인이 설계한 신호).
        // 그래서 게임 탭만 열고, 탭이 체스를 쌓는다(`GamesTab.applyDemoChessRoute`).
        //
        // ★ **꼬리를 버리면 안 된다.** 스텁은 라우트 글자를 폴더 이름으로 바꿔 장면을 고르지만(`MobileDemo`: `/` → `-`),
        //   장면 폴더가 **없는** 꼬리(`match/<id>` · `watch/<id>`)는 바깥 층 로비(진행 판 없음)로 떨어지고
        //   `ranking…` 은 로비 **맨 아래 절**이라 머리에서 시작한 스크롤에 안 보인다. 꼬리를 깃발 하나(Bool)로
        //   접었을 때 라우트 일곱 중 넷이 **같은 로비**를 그렸고(스크린샷 md5 동일) 아무도 순위·관전·대국을
        //   눈으로 못 봤다. 그래서 꼬리를 **값으로 풀어**(`MobileDemoChessRoute`) 스토어에 넘긴다 —
        //   판 열기는 코어 문(`openWindow(focusMatchID:)`), 관전은 `startWatching`, 절은 스크롤 닻이 받는다.
        //
        // ★ **이 갈래는 `#if DEBUG` 안이다**(1.0.6 build 16 출시 게이트 수리). 꼬리를 푼 값
        //   `MobileDemoChessRoute` 가 DEBUG 전용이 됐기 때문이고, 그 까닭은 그 타입의 새 자리
        //   `Demo/MobileDemoChessRoute.swift` 머리에 적었다 — Release 바이너리에서 **이름이 사라져야** 한다.
        //   Release 에서 **잃는 동작은 없다**: `environment.demoRoute` 를 세우는 글자(`AingCheckDemo`)가
        //   Release 바이너리에 0건이라(실측) 이 함수는 맨 위 guard 에서 돌아선다.
        #if DEBUG
        if let chess = Self.demoChessRoute(raw) {
            games.pendingDemoChessScreen = true
            games.demoChessRoute = chess
            router.open(.games)
            return
        }
        // 1:1 테트리스 장면(`games/tetris/lobby…` · `…/ranking` · `…/match/<장면>`)도 **`AingRoute` 에 가지가
        // 없다** — 체스와 같은 꼴로 게임 탭만 열고 탭이 테트리스를 쌓는다(`GamesTab.applyDemoTetrisRoute`).
        //
        // ★★ **`games/tetris` 한 토막을 여기서 가로채면 안 된다.** 그 글자는 `AingRoute.parse` 의 `("games", 1)`
        //   가지가 `.miniGame(.tetris)` 로 읽는 **솔로** 미니게임 딥링크다(v0.3.38 에 나갔다). 이 갈래가
        //   `AingRoute` **앞**에 있으므로 그 한 토막을 받으면 솔로 테트리스 데모 라우트가 **조용히 사라진다** —
        //   설계서 P1("솔로 테트리스는 한 글자도 건드리지 않는다")을 글자가 아니라 동작으로 어기는 일이다.
        //   그래서 판정을 **여기서 다시 적지 않는다**: 꼬리를 푸는 자리는 `MobileDemoTetrisRoute(demoRoute:)`
        //   하나이고(그 값이 `games/tetris/` 접두만 받는다 — 한 토막에 nil) 이 갈래는 **그 값이 섰는가만** 본다.
        //   두 자리에서 판정하면 한쪽만 고쳐져 솔로 링크가 다시 사라진다.
        if let tetris = MobileDemoTetrisRoute(demoRoute: raw) {
            games.pendingDemoTetrisScreen = true
            games.demoTetrisRoute = tetris
            router.open(.games)
            return
        }
        #endif
        guard let route = AingRoute(path: raw) ?? Self.demoOnlyRoute(raw) else { return }
        router.open(route)
    }

    // 아래 둘은 **DEBUG 전용**이다(돌려주는 값이 DEBUG 전용 타입이다 — `Demo/MobileDemoChessRoute.swift`).
    // `swift test` 는 Debug 로 돌므로 맥 스위트는 이 둘을 그대로 잰다(`GamesChessDemoRouteTests` · `GamesChessWiringTests`).
    #if DEBUG
    /// 이 데모 라우트가 체스 화면을 띄우라는 뜻인가(`games/chess` · `games/chess/<장면…>`).
    /// 오목(`games/gomoku…`)·미니게임(`games/<게임>`)은 `AingRoute` 가 이미 안다 — 여기 걸리면 안 된다.
    ///
    /// **꼬리까지 푸는 자리는 `demoChessRoute(_:)` 다** — 이 되묻기는 그 값이 섰는가만 본다(두 판정이 갈리지 않게).
    package static func isDemoChessRoute(_ raw: String) -> Bool {
        demoChessRoute(raw) != nil
    }

    /// 데모 라우트 글자 → **꼬리까지 푼 값**. 체스 라우트가 아니면 nil.
    ///
    /// 꼬리가 정하는 것 셋(`MobileDemoChessRoute`): 열 판 · 걸 관전 · 로비 스크롤이 시작할 절.
    package static func demoChessRoute(_ raw: String) -> MobileDemoChessRoute? {
        let path = raw.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path == "games/chess" || path.hasPrefix("games/chess/") else { return nil }
        let tail = path.dropFirst("games/chess".count).split(separator: "/").map(String.init)
        return MobileDemoChessRoute(tail: tail)
    }
    #endif

    /// `AingRoute` 가 모르는 **데모 전용 표기**가 열 화면(DEBUG 전용). AI 대국 장면(`games/gomoku/ai…`)은 오목 로비로 열고,
    /// 장면은 오목 화면이 세운다(`MobileDemoGomokuAI`). 푸시·위젯 URL 모양에는 데모 때문에 값을 더하지 않는다.
    private static func demoOnlyRoute(_ raw: String) -> AingRoute? {
        #if DEBUG
        return MobileDemoGomokuAI.scene(route: raw) != nil ? .gomokuLobby : nil
        #else
        return nil
        #endif
    }
}
