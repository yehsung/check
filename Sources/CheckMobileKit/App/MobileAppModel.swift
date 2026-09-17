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
    @ObservationIgnored package let links: MobileStoreLinks
    @ObservationIgnored package let context: MobileContext
    package let push: PushCoordinator
    package let now: NowStore
    package let messages: MessagesStore
    package let rankings: RankingsStore
    package let games: GamesStore
    package let me: MeStore

    package private(set) var isSceneActive = false
    @ObservationIgnored private var started = false

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
        realtime.gomoku = gomoku
        let links = MobileStoreLinks()
        let context = MobileContext(
            service: env.service,
            session: session,
            clock: env.clock,
            router: router,
            realtime: realtime,
            widgetSnapshots: writer,
            gomoku: gomoku,
            gomokuHost: host,
            storage: env.storage,
            appInfo: env.appInfo,
            isDemo: env.isDemo,
            links: links
        )

        self.session = session
        self.router = router
        self.realtime = realtime
        self.widgetSnapshots = writer
        self.gomokuHost = host
        self.gomoku = gomoku
        self.links = links
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

        session.onSignedIn = { [weak self] in self?.sessionDidSignIn() }
        session.onSignedOut = { [weak self] in self?.sessionDidSignOut() }
        session.onAccessTokenChanged = { [weak realtime] token in realtime?.accessTokenDidChange(token) }
    }

    /// 탭 배지(메시지 · 게임).
    package var badges: MobileBadges { links.badges }

    // MARK: - 시작 · scenePhase · URL

    /// 한 번만 돈다: client_release → 세션 복원 → (데모면) 시작 라우트 열기.
    public func start() {
        guard !started else { return }
        started = true
        Task { [weak self] in
            guard let self else { return }
            await self.session.launch()
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

    /// `onOpenURL`(위젯 · 외부 링크). 로그인 전이면 무시한다(로그인 뒤 링크는 푸시·위젯이 다시 준다).
    @discardableResult
    public func handleOpenURL(_ url: URL) -> Bool {
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
        if isSceneActive {
            activateStores()
        }
    }

    private func sessionDidSignOut() {
        realtime.sessionDidSignOut()
        gomoku.reset()
        gomokuHost.rubyBalance = nil
        router.reset()
        widgetSnapshots.forgetCurrent()
        now.reset()
        messages.reset()
        rankings.reset()
        games.reset()
        me.reset()
        push.reset()
    }

    private func activateStores() {
        now.appDidBecomeActive()
        messages.appDidBecomeActive()
        rankings.appDidBecomeActive()
        games.appDidBecomeActive()
        me.appDidBecomeActive()
        push.appDidBecomeActive()
    }

    private func openDemoRouteIfNeeded() {
        guard let raw = environment.demoRoute, session.isSignedIn, let route = AingRoute(path: raw) else { return }
        router.open(route)
    }
}
