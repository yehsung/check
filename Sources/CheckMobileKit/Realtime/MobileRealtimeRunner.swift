import CheckCore
import Foundation
import Observation

/// 실시간 핸들러 등록 증표. `cancel()` 하면 핸들러가 빠진다. 탭 스토어는 앱 모델과 수명이 같아 보통 부를 일이 없다 —
/// 핸들러 안에서 로그인·세대 가드를 스스로 한다(`reset()` 뒤에도 등록은 살아 있다).
@MainActor
package final class MobileRealtimeRegistration {
    private var cancelAction: (@MainActor () -> Void)?

    init(cancel: @escaping @MainActor () -> Void) {
        cancelAction = cancel
    }

    package func cancel() {
        cancelAction?()
        cancelAction = nil
    }
}

/// 폰의 실시간 **effect 실행층**(SPEC-ios §3.3 · ios-inventory §7).
///
/// 링(`RealtimeLink`)과 소켓(`LiveRealtimeTransport`)은 코어 것을 그대로 쓰고, effect 를 실행하는 층만 새로 쓴다.
/// 맥 `WorkTimerStoreRealtime.run` 과 갈리는 곳은 넷이다:
///  1. `.catchUp`·`.drain` → **take_pokes 가 아니다.** 등록된 `onMessageActivity` 핸들러들을 1초 창에 모아 한 번 부른다
///     (+ `.catchUp` 은 오목 `realtimeDidJoin`). take_pokes 는 원자 소비라 폰이 부르면 맥의 말풍선을 훔친다(R3) —
///     그리고 iOS 에서는 서비스에 그 메서드가 **컴파일되지 않는다**(`SupabaseWorkServiceMacOnly.swift`).
///  2. `.messageReadSignal` → 등록된 `onMessageRead` 핸들러들(같은 1초 합치기).
///  3. `.gomokuSignal` → `GomokuStore.handleSignal()`.
///  4. 연결은 **앱이 active 이고 로그인 상태일 때만**. background 로 가면 `.willSleep` 으로 내려놓는다.
/// 토큰 갱신은 세션 스토어의 조정자를 지난다(`refreshForRealtime`) — 갱신 주체가 둘이 되지 않게.
@MainActor
@Observable
package final class MobileRealtimeRunner {
    /// 화면이 읽는 링 상태(진단 · 오목 폴링 간격).
    package private(set) var state: RealtimeState

    @ObservationIgnored private var link: RealtimeLink
    @ObservationIgnored package let transport: RealtimeTransport?
    @ObservationIgnored private let service: SupabaseWorkService
    @ObservationIgnored private let clock: MobileClock
    @ObservationIgnored private let jitter: @Sendable (Double) -> Double
    @ObservationIgnored private weak var session: MobileSessionStore?
    /// 오목 신호를 받을 스토어(앱 모델이 붙인다).
    @ObservationIgnored package weak var gomoku: GomokuStore?

    /// 메시지 활동(`.drain`·`.catchUp`)·읽음 신호를 모으는 창(초). 테스트는 크게 두고 `flushCoalescedSignals()` 를 직접 부른다.
    @ObservationIgnored package var coalesceSeconds: TimeInterval = 1
    /// 주기 점검(`.tick`) 간격. 하트비트(25초)보다 촘촘해야 한다(맥과 같은 5초).
    @ObservationIgnored package var tickIntervalSeconds: TimeInterval = 5
    /// 벽시계 타이머를 띄울지. 테스트는 false 로 두고 `tick(at:)` 을 직접 부른다(두 시계가 겹치면 좀비 판정이 흔들린다).
    @ObservationIgnored package var runsTimers: Bool

    @ObservationIgnored private var activityHandlers: [UUID: @MainActor () -> Void] = [:]
    @ObservationIgnored private var readHandlers: [UUID: @MainActor () -> Void] = [:]
    @ObservationIgnored private var pendingActivity = false
    @ObservationIgnored private var pendingRead = false
    @ObservationIgnored private var coalesceTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var tokenRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var wired = false
    @ObservationIgnored package private(set) var isAppActive = false

    /// 실행한 effect 기록(최근 50개 — 테스트·진단). 네트워크 경로의 증거는 스텁이 받은 요청이다.
    @ObservationIgnored package private(set) var effectLog: [RealtimeEffect] = []
    /// 핸들러를 실제로 부른 횟수(합치기 증거).
    @ObservationIgnored package private(set) var activityFlushCount = 0
    @ObservationIgnored package private(set) var readFlushCount = 0

    package init(
        service: SupabaseWorkService,
        transport: RealtimeTransport?,
        clock: MobileClock,
        runsTimers: Bool = true,
        jitter: @escaping @Sendable (Double) -> Double = { ceiling in ceiling <= 0 ? 0 : Double.random(in: 0...ceiling) }
    ) {
        self.service = service
        self.transport = transport
        self.clock = clock
        self.runsTimers = runsTimers
        self.jitter = jitter
        let link = RealtimeLink(transportAvailable: transport != nil && service.anonKey != nil)
        self.link = link
        self.state = link.state
    }

    package func attach(session: MobileSessionStore) {
        self.session = session
    }

    // MARK: - 핸들러 등록(탭 스토어가 부른다)

    /// `.drain`(새 메시지 신호) · `.catchUp`(조인 직후 따라잡기)마다 — 1초 창에 모아 한 번.
    /// 메시지 탭: 요약(`message_unread_summary`) + 보이는 대화 이력 재조회. **take_pokes 금지.**
    package func onMessageActivity(_ handler: @escaping @MainActor () -> Void) -> MobileRealtimeRegistration {
        let id = UUID()
        activityHandlers[id] = handler
        return MobileRealtimeRegistration { [weak self] in self?.activityHandlers[id] = nil }
    }

    /// 읽음 신호(`message_read`)마다 — 1초 창에 모아 한 번. 메시지 탭: 이력(말풍선 옆 1)·요약 재조회.
    package func onMessageRead(_ handler: @escaping @MainActor () -> Void) -> MobileRealtimeRegistration {
        let id = UUID()
        readHandlers[id] = handler
        return MobileRealtimeRegistration { [weak self] in self?.readHandlers[id] = nil }
    }

    // MARK: - 수명(앱 모델이 부른다)

    package func appDidBecomeActive() {
        isAppActive = true
        connectIfPossible()
    }

    package func appDidEnterBackground() {
        isAppActive = false
        stopTicker()
        apply(.willSleep)
        // 모아 둔 신호는 버린다 — active 로 돌아오면 조인 따라잡기(`.catchUp`)와 각 스토어의 appDidBecomeActive 가 다시 읽는다.
        coalesceTask?.cancel()
        coalesceTask = nil
        pendingActivity = false
        pendingRead = false
    }

    package func sessionDidSignIn() {
        connectIfPossible()
    }

    package func sessionDidSignOut() {
        apply(.signedOut)
        cancelTimers()
    }

    /// 다른 경로(401 재시도)가 토큰을 갱신했다 — 붙어 있으면 채널에 새 토큰을 민다(재연결하지 않는다).
    package func accessTokenDidChange(_ token: String) {
        apply(.tokenRefreshed(accessToken: token))
    }

    private func connectIfPossible() {
        guard isAppActive, let current = session?.session, session?.isSignedIn == true else { return }
        wireTransportIfNeeded()
        switch link.state {
        case .idle(.signedOut):
            apply(.signedIn(accessToken: current.accessToken))
        case .idle(.suspended):
            apply(.didWake)
        default:
            break
        }
        startTickerIfNeeded()
    }

    private func wireTransportIfNeeded() {
        guard !wired, let transport else { return }
        wired = true
        transport.onEvent = { [weak self] event in
            self?.apply(.transport(event))
        }
    }

    // MARK: - 링

    /// 링에 사건을 넣고 effect 를 실행한다. **러너가 링에 시각을 주는 유일한 문.**
    package func apply(_ event: RealtimeEvent, at now: Date? = nil) {
        let instant = now ?? clock.now()
        let effects = link.apply(event, now: instant, jitter: jitter)
        if state != link.state { state = link.state }
        run(effects, now: instant)
    }

    /// 주기 점검 1회(테스트는 직접 부른다).
    package func tick(at now: Date? = nil) {
        let instant = now ?? clock.now()
        apply(.tick, at: instant)
        if retryTask == nil, let retryAt = link.retryAt, instant >= retryAt {
            apply(.backoffElapsed, at: instant)
        }
    }

    private func run(_ effects: [RealtimeEffect], now: Date) {
        for effect in effects {
            effectLog.append(effect)
            if effectLog.count > 50 { effectLog.removeFirst(effectLog.count - 50) }
            switch effect {
            case .connect(let linkToken):
                performConnect(linkToken: linkToken)
            case .disconnect:
                transport?.disconnect()
            case .scheduleRetry(let at):
                scheduleRetry(at: at, now: now)
            case .cancelRetry:
                retryTask?.cancel()
                retryTask = nil
            case .catchUp:
                // 조인 직후 따라잡기: 소켓이 내려가 있던 동안의 신호는 재생되지 않는다 — 서버 표를 다시 읽는다(조회만).
                requestMessageActivity()
                gomoku?.realtimeDidJoin()
            case .drain:
                // ★ take_pokes 가 아니다(R3). 새 메시지가 있다는 신호일 뿐 — 요약·이력 조회로 갚는다.
                requestMessageActivity()
            case .messageReadSignal:
                requestMessageRead()
            case .gomokuSignal:
                gomoku?.handleSignal()
            case .pushAccessToken(let token):
                transport?.pushAccessToken(token)
            case .scheduleTokenRefresh(let at):
                scheduleTokenRefresh(at: at, now: now)
            case .refreshToken:
                startTokenRefresh()
            case .sendHeartbeat:
                transport?.sendHeartbeat()
            }
        }
    }

    private func performConnect(linkToken: String) {
        guard let transport, let current = session?.session, let apiKey = service.anonKey else { return }
        // 링이 실어 온 토큰이 아니라 **지금 세션의 토큰**(백오프 동안 갱신됐을 수 있다 — 맥과 같은 경합 2 차단).
        transport.connect(
            url: service.projectURL,
            apiKey: apiKey,
            accessToken: current.accessToken,
            channel: RealtimeLinkConstants.pokeChannel(userID: current.userID),
            isPrivate: true
        )
    }

    // MARK: - 합치기

    private func requestMessageActivity() {
        pendingActivity = true
        scheduleCoalescedFlush()
    }

    private func requestMessageRead() {
        pendingRead = true
        scheduleCoalescedFlush()
    }

    private func scheduleCoalescedFlush() {
        guard coalesceTask == nil else { return }
        let delay = coalesceSeconds
        coalesceTask = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            self.coalesceTask = nil
            self.flushCoalescedSignals()
        }
    }

    /// 모아 둔 신호를 지금 갚는다(창이 끝났을 때 · 테스트).
    package func flushCoalescedSignals() {
        coalesceTask?.cancel()
        coalesceTask = nil
        if pendingActivity {
            pendingActivity = false
            activityFlushCount += 1
            for handler in activityHandlers.values { handler() }
        }
        if pendingRead {
            pendingRead = false
            readFlushCount += 1
            for handler in readHandlers.values { handler() }
        }
    }

    // MARK: - 타이머

    private func scheduleRetry(at date: Date, now: Date) {
        retryTask?.cancel()
        let delay = max(0, date.timeIntervalSince(now))
        retryTask = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil
            self.apply(.backoffElapsed)
        }
    }

    private func scheduleTokenRefresh(at date: Date, now: Date) {
        tokenRefreshTask?.cancel()
        guard runsTimers else { return }
        let delay = max(0, date.timeIntervalSince(now))
        tokenRefreshTask = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            self.tokenRefreshTask = nil
            self.startTokenRefresh()
        }
    }

    private func startTokenRefresh() {
        guard let session else { return }
        Task { @MainActor [weak self] in
            let result = await session.refreshForRealtime()
            guard let self else { return }
            switch result {
            case .success:
                // 세션 스토어의 onAccessTokenChanged 가 이미 `.tokenRefreshed` 를 넣었다(accessTokenDidChange).
                break
            case .failure(let failure):
                self.apply(.tokenRefreshFailed(fatal: failure.fatal))
            }
        }
    }

    private func startTickerIfNeeded() {
        guard runsTimers, tickTask == nil, transport != nil else { return }
        let interval = tickIntervalSeconds
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(1))
                if Task.isCancelled { return }
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func stopTicker() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func cancelTimers() {
        stopTicker()
        retryTask?.cancel(); retryTask = nil
        tokenRefreshTask?.cancel(); tokenRefreshTask = nil
        coalesceTask?.cancel(); coalesceTask = nil
        pendingActivity = false
        pendingRead = false
    }
}
