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
///  1. `.catchUp`·`.drain` → **take_pokes 가 아니다.** 등록된 `onMessageActivity` 핸들러들을 부른다 — 조용하던 창의
///     첫 신호는 **곧바로**(앞쪽), 그 1초 창 안에 또 온 신호들은 창 끝에 **한 번**(뒤쪽 합치기)
///     (+ `.catchUp` 은 오목·테트리스 `realtimeDidJoin`). take_pokes 는 원자 소비라 폰이 부르면 맥의 말풍선을 훔친다(R3) —
///     그리고 iOS 에서는 서비스에 그 메서드가 **컴파일되지 않는다**(`SupabaseWorkServiceMacOnly.swift`).
///  2. `.messageReadSignal` → 등록된 `onMessageRead` 핸들러들(뒤쪽 1초 합치기만 — 앞쪽 즉시 처리는 없다).
///  3. `.gomokuSignal` → `GomokuStore.handleSignal()` · `.tetrisSignal` → `TetrisDuelStore.handleSignal()`(1.0.11).
///     `.chessSignal` 은 **일부러 빈 가지**다 — 까닭 셋을 그 자리에 적었다(폰 체스는 1.0.6 에 나갔다).
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
    /// 테트리스 대결 신호를 받을 스토어(앱 모델이 붙인다 — 오목 칸과 같은 꼴·같은 자리).
    @ObservationIgnored package weak var tetris: TetrisDuelStore?
    /// 확성기 배너 신호(`megaphone`)를 받을 스토어(앱 모델이 붙인다 — 오목·테트리스 칸과 같은 꼴).
    @ObservationIgnored package weak var megaphoneBanner: MegaphoneBannerStore?

    /// 메시지 활동(`.drain`·`.catchUp`)·읽음 신호를 모으는 창(초). 테스트는 크게 두고 `flushCoalescedSignals()` 를 직접 부른다.
    /// 메시지 활동은 이 창의 **앞쪽**(조용하던 창의 첫 신호)을 곧바로 갚고 창 안의 나머지를 창 끝에 한 번 갚는다 —
    /// 창 하나에 최대 두 번. 읽음 신호는 뒤쪽 한 번뿐이다(stab-1030 §5-2: 읽음·배경까지 즉시 조회로 넓히지 않는다).
    @ObservationIgnored package var coalesceSeconds: TimeInterval = 1
    /// 주기 점검(`.tick`) 간격. 하트비트(25초)보다 촘촘해야 한다(맥과 같은 5초).
    @ObservationIgnored package var tickIntervalSeconds: TimeInterval = 5
    /// 벽시계 타이머를 띄울지. 테스트는 false 로 두고 `tick(at:)` 을 직접 부른다(두 시계가 겹치면 좀비 판정이 흔들린다).
    @ObservationIgnored package var runsTimers: Bool

    @ObservationIgnored private var activityHandlers: [UUID: @MainActor () -> Void] = [:]
    @ObservationIgnored private var readHandlers: [UUID: @MainActor () -> Void] = [:]
    @ObservationIgnored private var pendingActivity = false
    @ObservationIgnored private var pendingRead = false
    /// 읽음 신호의 뒤쪽 합치기 타이머(첫 신호 + `coalesceSeconds`).
    @ObservationIgnored private var coalesceTask: Task<Void, Never>?
    /// 메시지 활동의 뒤쪽 합치기 타이머(창 끝 = 마지막 활동 flush + `coalesceSeconds`). 읽음 타이머와 **따로** 둔다 —
    /// 둘이 한 타이머를 나누면 먼저 온 읽음 신호의 창 끝이 활동을 창 중간에 한 번 더 갚아 '창 하나에 최대 두 번'이 흐려진다.
    @ObservationIgnored private var activityWindowTask: Task<Void, Never>?
    /// 메시지 활동 핸들러를 마지막으로 부른 시각(앞쪽·뒤쪽 어느 쪽이든 — 주입 시계 기준). 앞쪽 즉시 처리의 창을 여기서 잰다.
    @ObservationIgnored private var lastActivityFlushAt: Date?
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

    /// `.drain`(새 메시지 신호) · `.catchUp`(조인 직후 따라잡기)마다 — 조용하던 창의 첫 신호는 곧바로, 창 안의 나머지는 창 끝에 한 번.
    /// 핸들러 쪽도 돌고 있는 새로고침에 뒤따르는 한 번으로 합친다(`MessagesStore.requestActivityRefresh`) — 이 창은 그 앞단이다.
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
        activityWindowTask?.cancel()
        activityWindowTask = nil
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
        var effects = link.apply(event, now: instant, jitter: jitter)
        if state != link.state { state = link.state }
        // 확성기 배너 신호(서버 `send_megaphone` 이 받는 사람마다 `poke_ring` 다음에 보낸다 — 계약 S2-3).
        // 링은 이 이름을 몰라 기본값 `.drain` 으로 접는다. 여기서 **그 drain 을 배너 갱신으로 바꾼다**: 같은 확성기의
        // `poke_ring` 이 이미 메시지 활동(요약)을 깨웠으므로 drain 을 남기면 메시지 조회가 한 번 더 나갈 뿐이다.
        // 링이 거른 경우(구독 전 — 효과 없음)는 아무것도 하지 않는다.
        if case .transport(.broadcast(let name)) = event, name == Self.megaphoneBroadcastEvent, effects == [.drain] {
            effects = []
            requestMegaphoneRefresh()
        }
        run(effects, now: instant)
    }

    /// 확성기 배너 신호의 이벤트 이름(서버 `realtime.send(…, 'megaphone', poke_topic(target), true)`).
    package nonisolated static let megaphoneBroadcastEvent = "megaphone"

    /// 배너 스토어가 `megaphone_inbox` 를 다시 읽는다(겹친 호출은 코어가 하나로 모은다). 새 항목이 있으면 배너가 뜨고 메시지함 필터 id 가 는다.
    private func requestMegaphoneRefresh() {
        guard let banner = megaphoneBanner else { return }
        Task { @MainActor in await banner.refresh() }
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
                requestMessageActivity(now: now)
                gomoku?.realtimeDidJoin()
                // 테트리스도 같은 자리다. 소켓이 내려가 있던 사이에 온 신청·수락·공격 누계는 재생되지 않으므로
                // 조인 직후 로비를 한 번 긁는다(`catchUp` → `refreshLobby`, 그 응답이 가리키는 판까지).
                // ★ 판 중에 소켓이 끊겼다 붙으면 그 사이의 방해 줄을 **보고 왕복이 알려 주기 전에** 받는다.
                tetris?.realtimeDidJoin()
            case .drain:
                // ★ take_pokes 가 아니다(R3). 새 메시지가 있다는 신호일 뿐 — 요약·이력 조회로 갚는다.
                requestMessageActivity(now: now)
            case .messageReadSignal:
                requestMessageRead()
            case .gomokuSignal:
                gomoku?.handleSignal()
            case .chessSignal:
                // ⚠️ **"폰에 체스 화면이 없다"는 낡은 말이었다** — 폰 체스는 1.0.6(build 16, 2026-10-13 제출)에 이미
                // 나갔다. 그런데도 이 가지는 **일부러** 비어 있다. 셋을 적어 둔다.
                //
                // ① 왜 아직 `break` 인가: 폰 체스는 **받은함 RPC 가 없다**(`ChessStore` 머리말 ⑪) — 받은 신청·진행 중
                //    판·전적이 전부 `chess_lobby` 의 `me` 로만 오고, 그 조회는 **허브·체스 화면에서만** 나간다
                //    (`GamesStore.hubDidAppear`·`appDidBecomeActive` 의 `refreshLobbyIfStale`, 30초 스로틀).
                //    그래서 이 신호를 소비할 주체를 **아직 정하지 않았다**: 여기서 `chess?.handleSignal()` 로 이으면
                //    상대가 한 수 둘 때마다(블리츠 한 판 = 왕복 80회) 화면이 안 떠 있어도 조회가 나간다.
                //    `GamesStore.badgeCount` 주석이 체스를 탭 배지에 안 싣는 근거와 **같은 근거**다(60초 TTL 짜리
                //    숫자를 30초 스로틀로 갱신하는 꼴이 된다) — 둘은 한 짝으로 움직여야 한다.
                // ② 그래서 지금 무슨 일이 벌어지는가: **초인종이 와도 폰은 다음 폴링까지 모른다.** 체스 화면이 떠
                //    있으면 코어 폴링(1.0~1.5초)이 금방 갚고, 화면 밖이면 다음 허브 진입·active 복귀까지 모른다.
                //    잃는 것은 신선도뿐이고 판은 서버 시계로 흐른다(체스는 자동 착수가 없다 — DECISIONS B4).
                // ③ **`.drain` 으로 떨어뜨리면 안 되는 까닭**: `.drain` 은 "새 메시지가 있다"는 뜻이라 메시지 활동
                //    핸들러(요약·이력 조회)를 깨운다. 체스 초인종이 그 갈래로 새면 **수마다** 메시지 조회가 한 번씩
                //    더 나간다 — 폰이 소비할 것이 하나도 없는 조회다. 가지를 **따로 비워 두는 것**이 그 차단이다.
                //    (이 파일 머리말의 `.drain` ≠ `take_pokes` 규약 R3 과 같은 자리.)
                break
            case .tetrisSignal:
                // 1:1 테트리스(서버·맥 0.3.60 · 폰 1.0.11). 체스 가지와 달리 **잇는다** — 까닭은 둘이다.
                //  · 맥 대 폰 판에서 방해 줄이 늦는다: 서버는 공격 누계가 늘 때만 링을 울리는데(`tetris__ring`),
                //    이 가지가 비면 폰은 자기 보고 왕복(1초)이 상태를 되돌려 줄 때까지 그 줄을 모른다. 상쇄는
                //    '줄을 안 지운 다음 굳힘'에서 일어나므로 1초는 한 조각을 잘못 놓게 만든다.
                //  · 구조가 맥과 같아야 한다: 맥은 `WorkTimerStoreRealtime` 이 같은 신호를 `handleSignal()` 로
                //    흘린다. 한쪽만 다르면 "폰에서만 늦는다"는 신고가 들어올 때 볼 자리가 두 곳이 된다.
                // `handleSignal()` 은 **직렬화된 재조회 한 번**이다(도는 중이면 뒤따르는 한 번으로 합친다 —
                // `requestSync`), 판 중이면 그 판의 상태, 아니면 로비. 그래서 초인종이 몰려도 조회는 겹치지 않는다.
                //
                // ★ **`.drain` 으로 떨어뜨리면 안 되는 까닭**(가지를 따로 두는 값): 테트리스 초인종은 판 중
                //   공격마다 울린다. `.drain` 으로 새면 그 울림마다 **메시지** 요약·이력 조회가 한 번씩 더 나간다 —
                //   테트리스와 아무 상관 없는 조회다. 잇는 것과 따로 두는 것은 별개의 요구다.
                tetris?.handleSignal()
            case .megaphoneSignal:
                // 확성기 배너 신호(2026-10-30). 폰 배너 배선은 폰 갈래가 잇는다(`MegaphoneBannerStore.refresh()`) — 그때까지 비워 둔다.
                // `.drain` 으로 떨어뜨리지 않는 까닭은 위 체스 가지 ③과 같다(소비할 것이 없는 메시지 조회가 한 번 더 나간다).
                break
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

    /// 메시지 활동: **앞쪽 처리 + 뒤쪽 합치기**(stab-1030 §5-2).
    /// 예전에는 모든 활동을 1초 뒤에 갚아, 열린 대화에서도 새 말이 **늘 1초 이상 늦게** 섰다. 지금은
    ///  · 앱이 active 이고 최근 `coalesceSeconds` 안에 활동 flush 가 없었으면 → **곧바로** 핸들러를 부른다(앞쪽).
    ///  · 그 창 안에 또 온 신호는 모아 두었다가 **창 끝**(마지막 flush + 창)에 한 번 부른다(뒤쪽 — 예전 합치기).
    /// 그래서 신호가 몰려도 창 하나에 최대 두 번이다. 핸들러가 띄운 새로고침이 아직 돌고 있으면 그쪽이 뒤따르는
    /// 한 번으로 또 합친다(`MessagesStore.requestActivityRefresh` 의 activityAgain) — 이 창은 그 계약을 건드리지 않는다.
    /// active 가 아니면 앞쪽은 없다 — 예전 그대로 첫 신호 + 창 뒤에 한 번이고, background 진입이 모아 둔 것을 버린다.
    private func requestMessageActivity(now: Date) {
        if isAppActive, activityWindowHasElapsed(at: now) {
            flushPendingActivity(at: now)
            return
        }
        pendingActivity = true
        scheduleActivityWindowEnd(now: now)
    }

    /// 마지막 활동 flush 뒤로 창이 다 지났는가. 시계가 뒤로 갔으면(음수) 아직 창 안으로 본다 — 앞쪽을 더 열지 않는 쪽.
    private func activityWindowHasElapsed(at now: Date) -> Bool {
        guard let last = lastActivityFlushAt else { return true }
        return now.timeIntervalSince(last) >= coalesceSeconds
    }

    private func scheduleActivityWindowEnd(now: Date) {
        guard activityWindowTask == nil else { return }
        let window = max(0, coalesceSeconds)
        // 창 끝까지 남은 시간. active 가 아니거나 앞쪽 flush 가 없었으면 예전처럼 첫 신호 + 창 전체다.
        // [0, 창] 으로 묶는다 — 시계가 뒤로 가도 창보다 오래 붙잡지 않는다.
        var delay = window
        if isAppActive, let last = lastActivityFlushAt {
            delay = min(window, max(0, last.addingTimeInterval(window).timeIntervalSince(now)))
        }
        activityWindowTask = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            self.activityWindowTask = nil
            if self.pendingActivity { self.flushPendingActivity(at: self.clock.now()) }
        }
    }

    /// 메시지 활동 핸들러를 지금 부른다(앞쪽 · 창 끝 · 테스트 훅). 모아 둔 것도 이 한 번이 함께 갚는다.
    private func flushPendingActivity(at now: Date) {
        activityWindowTask?.cancel()
        activityWindowTask = nil
        pendingActivity = false
        lastActivityFlushAt = now
        activityFlushCount += 1
        for handler in activityHandlers.values { handler() }
    }

    private func requestMessageRead() {
        pendingRead = true
        scheduleCoalescedFlush()
    }

    /// 읽음 신호의 뒤쪽 합치기(첫 신호 + 창). 앞쪽 즉시 처리는 **일부러** 없다 — 읽음 신호는 새 줄을 세우지 않고
    /// 말풍선 옆 1 만 지우므로 1초 늦어도 잃는 것이 적고, 감사(stab-1030 §5-2)가 읽음까지 즉시 조회로 넓히지 말라고 했다.
    private func scheduleCoalescedFlush() {
        guard coalesceTask == nil else { return }
        let delay = coalesceSeconds
        coalesceTask = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            self.coalesceTask = nil
            self.flushPendingRead()
        }
    }

    private func flushPendingRead() {
        coalesceTask?.cancel()
        coalesceTask = nil
        guard pendingRead else { return }
        pendingRead = false
        readFlushCount += 1
        for handler in readHandlers.values { handler() }
    }

    /// 모아 둔 신호를 지금 갚는다(창이 끝났을 때 · 테스트). 모아 둔 것이 없으면 아무것도 부르지 않는다 —
    /// 그래서 이 훅은 앞쪽 창을 새로 열지도 닫지도 않는다(활동 flush 시각은 핸들러를 실제로 부를 때만 바뀐다).
    package func flushCoalescedSignals() {
        if pendingActivity {
            flushPendingActivity(at: clock.now())
        } else {
            activityWindowTask?.cancel()
            activityWindowTask = nil
        }
        flushPendingRead()
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
                // 갱신이 도는 사이 로그아웃·재로그인으로 세대가 바뀌었다 — 옛 링의 결과다. 새 세션의 링에 넣으면
                // fatal 로 접혀 막 붙은 소켓을 내린다(dbase-fix · 검증 V3). 새 링은 자기 토큰으로 이미 움직이고 있다.
                guard !failure.stale else { return }
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
        activityWindowTask?.cancel(); activityWindowTask = nil
        pendingActivity = false
        pendingRead = false
    }
}
