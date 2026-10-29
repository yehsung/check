import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 실시간 러너(SPEC-ios-build §1-6): 연결은 active+로그인일 때만, `.drain`·`.catchUp` → 메시지 핸들러(앞쪽 곧바로 +
/// 창 안의 나머지는 창 끝 한 번 — stab-1030), 읽음 신호 → 읽음 핸들러(뒤쪽 1초 합치기만), 오목 신호 → GomokuStore,
/// **take_pokes 0건**(스텁이 받은 경로로 단언).
@MainActor
@Suite struct BaseRealtimeRunnerTests {
    struct Harness {
        let host: String
        let storage: AingSharedStorage
        let session: MobileSessionStore
        let runner: MobileRealtimeRunner
        let transport: BaseFakeTransport
        /// 러너·세션이 읽는 주입 시계 — 앞쪽 창이 지났는지를 이 시계로 잰다.
        let clock: BaseTestClock
        let gomokuHost: MobileGomokuHost
        let gomoku: GomokuStore
        var requests: [MobileStubRequest] { MobileStubURLProtocol.requests(host: host) }
        func tearDown() { BaseStub.tearDown(host: host, storage: storage) }
    }

    func makeHarness(signedIn: Bool = true) async -> Harness {
        let host = BaseStub.makeHost("realtime")
        MobileStubURLProtocol.register(host: host) { request in
            switch request.rpcName {
            case "client_release": return BaseStub.releaseOK
            case "register_device": return BaseStub.registerOK
            case "message_unread_summary": return .json(#"{"status":"ok","total":0,"peers":[]}"#)
            case "message_history_with_reads": return .json("[]")
            default: break
            }
            if request.path == "/rest/v1/memberships" { return BaseStub.membershipOK }
            // 오목 RPC 는 "없는 함수"로 답해도 스토어가 조용히 접는다 — 여기서 보는 것은 **어떤 경로를 불렀는가**다.
            return .missingFunction(request.path)
        }
        let storage = BaseStub.makeStorage()
        let vault = InMemoryTokenVault()
        if signedIn {
            vault.write(BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600)), key: AingKeychain.accessTokenKey)
            vault.write("r", key: AingKeychain.refreshTokenKey)
            storage.defaults.set("user-7", forKey: AingSharedKeys.userID)
        }
        let service = BaseStub.makeService(host: host)
        let clock = BaseTestClock()
        let session = MobileSessionStore(service: service, vault: vault, storage: storage, appInfo: BaseStub.appInfo,
                                         installationID: "11111111-2222-4333-8444-555555555555", clock: clock.clock)
        session.clientReleaseTimeoutSeconds = 0   // 벽시계 상한 없음
        let transport = BaseFakeTransport()
        let runner = MobileRealtimeRunner(service: service, transport: transport, clock: clock.clock, runsTimers: false,
                                          jitter: { $0 })
        runner.attach(session: session)
        runner.coalesceSeconds = 3600  // 창을 테스트가 직접 닫는다(flushCoalescedSignals)
        let host2 = MobileGomokuHost(sessionStore: session, realtime: runner)
        let gomoku = GomokuStore(host: host2)
        runner.gomoku = gomoku
        session.onSignedIn = { runner.sessionDidSignIn() }
        session.onSignedOut = { runner.sessionDidSignOut() }
        session.onAccessTokenChanged = { runner.accessTokenDidChange($0) }
        await session.launch()
        await session.pendingDeviceRegistration?.value
        return Harness(host: host, storage: storage, session: session, runner: runner, transport: transport, clock: clock,
                       gomokuHost: host2, gomoku: gomoku)
    }

    @Test("로그인 상태라도 앱이 active 가 아니면 붙지 않는다 — active 가 되면 poke:<uid> private 채널로 지금 토큰을 들고 붙는다")
    func connectsOnlyWhenActive() async throws {
        let h = await makeHarness()
        defer { h.tearDown() }
        #expect(h.session.phase == .signedIn)
        #expect(h.transport.connects.isEmpty, "background 에서 로그인만으로 소켓을 열었다")

        h.runner.appDidBecomeActive()
        #expect(h.transport.connects.count == 1)
        let connect = try #require(h.transport.connects.first, "소켓을 열지 않았다 — 인덱스 읽기 전에 멈춘다")
        #expect(connect.channel == "poke:user-7")
        #expect(connect.isPrivate)
        #expect(connect.accessToken == h.session.session?.accessToken)
        #expect(h.runner.state == .connecting(attempt: 1, since: MobileClock.demoInstant))
    }

    @Test("catchUp 은 곧바로·창 안의 drain 은 창 끝 한 번·읽음은 창 끝 한 번, 오목 신호는 GomokuStore 로 간다 — take_pokes 등 금지 경로 0건")
    func effectsAreCoalescedAndNeverTakePokes() async {
        let h = await makeHarness()
        defer { h.tearDown() }
        var activity = 0
        var reads = 0
        let service = h.session.service
        let session = h.session
        let activityToken = h.runner.onMessageActivity {
            activity += 1
            // 메시지 탭이 할 법한 조회: 요약(읽기). 금지 경로 대조군이 실제 네트워크를 보게 한다.
            Task { @MainActor in
                _ = try? await session.withMobileSessionRetry { current in
                    try await service.send(path: "/rest/v1/rpc/message_unread_summary", method: "POST",
                                           body: BaseNoBody(), accessToken: current.accessToken, prefer: nil)
                }
            }
        }
        _ = h.runner.onMessageRead { reads += 1 }

        h.runner.appDidBecomeActive()
        h.transport.emit(.joined)                               // → .catchUp(조용하던 창의 첫 신호 → 곧바로)
        #expect(h.runner.state.isSubscribed)
        #expect(activity == 1, "조용하던 창의 첫 신호(catchUp)를 창 끝까지 붙잡았다(앞쪽 처리 없음)")
        h.transport.emit(.broadcast(event: "ring"))             // → .drain(창 안 → 모은다)
        h.transport.emit(.broadcast(event: ""))                 // → .drain(이름 없음도)
        h.transport.emit(.broadcast(event: "message_read"))     // → .messageReadSignal
        h.transport.emit(.broadcast(event: "message_read"))
        #expect(activity == 1 && reads == 0, "창이 닫히기 전에 창 안의 신호를 불렀다(뒤쪽 합치기 없음)")
        h.runner.flushCoalescedSignals()
        #expect(activity == 2, "창 안의 drain 2건이 창 끝 한 번으로 모여야 한다")
        #expect(reads == 1)
        #expect(h.runner.activityFlushCount == 2 && h.runner.readFlushCount == 1)

        h.transport.emit(.broadcast(event: "gomoku"))           // → GomokuStore.handleSignal
        #expect(h.runner.effectLog.contains(.gomokuSignal))
        #expect(await baseWaitUntil { h.requests.contains { $0.rpcName == "message_unread_summary" } })
        #expect(await baseWaitUntil { h.requests.contains { ($0.rpcName ?? "").hasPrefix("gomoku_") } },
                "오목 신호·조인 따라잡기가 오목 조회를 부르지 않았다")
        await baseBarrier(h.session.service)

        let paths = h.requests.map(\.path)
        #expect(!paths.contains("/rest/v1/rpc/take_pokes"), "폰이 take_pokes 를 불렀다(맥 말풍선 훔치기 — R3)")
        #expect(MobileForbiddenCalls.violations(in: h.requests).isEmpty, "\(MobileForbiddenCalls.violations(in: h.requests))")
        let beforeCancel = activity
        activityToken.cancel()
        h.transport.emit(.broadcast(event: "ring"))
        h.runner.flushCoalescedSignals()
        #expect(activity == beforeCancel, "취소한 핸들러가 불렸다")
    }

    // MARK: - 메시지 활동: 앞쪽 처리 + 뒤쪽 합치기(stab-1030 §5-2)
    // 없으면: 열린 대화에서도 새 말이 늘 1초(창) 뒤에 선다 — 첫 신호도 창 끝까지 붙잡혔다.

    /// 붙고(조인 따라잡기가 앞쪽 한 번 — 전제) 창을 다 보내 "조용한 상태"로 만든다. 돌려주는 값은 그때까지의 활동 호출 수.
    private func subscribeAndGoQuiet(_ h: Harness, activity: () -> Int) -> Int {
        h.runner.appDidBecomeActive()
        h.transport.emit(.joined)
        #expect(h.runner.state.isSubscribed)
        #expect(activity() == 1, "전제: 조인 따라잡기(catchUp)는 조용하던 창의 첫 신호라 곧바로 한 번")
        h.clock.advance(h.runner.coalesceSeconds)   // 마지막 flush 뒤로 창이 꼭 맞게 지났다(경계 포함)
        return activity()
    }

    @Test("① 조용한 상태의 drain 하나는 창을 기다리지 않고 곧바로 한 번 — 창 끝에 또 부르지 않는다")
    func quietDrainFlushesImmediately() async {
        let h = await makeHarness()
        defer { h.tearDown() }
        h.runner.coalesceSeconds = 10
        var activity = 0
        let token = h.runner.onMessageActivity { activity += 1 }
        defer { token.cancel() }
        let base = subscribeAndGoQuiet(h) { activity }

        h.transport.emit(.broadcast(event: "ring"))
        #expect(activity == base + 1, "조용한 상태의 첫 drain 을 창 끝까지 붙잡았다")
        h.runner.flushCoalescedSignals()   // 창 끝
        #expect(activity == base + 1, "곧바로 갚은 신호를 창 끝에 또 갚았다(모아 둔 것이 없다)")
        #expect(h.runner.activityFlushCount == base + 1)
    }

    @Test("② 창 안의 drain 다섯 개 → 곧바로 1회 + 창 끝 1회 = 2회(조회 폭주 없음)")
    func burstInWindowFlushesTwice() async {
        let h = await makeHarness()
        defer { h.tearDown() }
        h.runner.coalesceSeconds = 10
        var activity = 0
        let token = h.runner.onMessageActivity { activity += 1 }
        defer { token.cancel() }
        let base = subscribeAndGoQuiet(h) { activity }

        for _ in 0..<5 { h.transport.emit(.broadcast(event: "ring")) }
        #expect(h.runner.effectLog.suffix(5).allSatisfy { $0 == .drain }, "전제: 다섯 개 모두 drain 이다")
        #expect(activity == base + 1, "창 안 다섯 개 중 첫 하나만 곧바로여야 한다")
        h.runner.flushCoalescedSignals()   // 창 끝
        #expect(activity == base + 2, "창 안의 나머지 넷이 창 끝 한 번으로 모여야 한다")
        h.runner.flushCoalescedSignals()
        #expect(activity == base + 2, "모아 둔 것이 없는데 또 불렀다")
    }

    @Test("③ 창이 지난 뒤의 drain 은 다시 곧바로 한 번 — 창 끝 직전(대조군)은 모았다가 창 끝에 한 번")
    func drainAfterWindowFlushesImmediatelyAgain() async {
        let h = await makeHarness()
        defer { h.tearDown() }
        h.runner.coalesceSeconds = 10
        var activity = 0
        let token = h.runner.onMessageActivity { activity += 1 }
        defer { token.cancel() }
        let base = subscribeAndGoQuiet(h) { activity }

        h.transport.emit(.broadcast(event: "ring"))   // 앞쪽(창 시작)
        #expect(activity == base + 1)
        h.clock.advance(9.9)                          // 대조군: 아직 창 안
        h.transport.emit(.broadcast(event: "ring"))
        #expect(activity == base + 1, "창 안의 drain 을 곧바로 불렀다")
        h.runner.flushCoalescedSignals()              // 창 끝 → 이 flush 가 다음 창의 시작
        #expect(activity == base + 2)

        h.clock.advance(10)                           // 마지막 flush 뒤로 창이 다 지났다
        h.transport.emit(.broadcast(event: "ring"))
        #expect(activity == base + 3, "창이 지난 뒤의 drain 을 창 끝까지 붙잡았다")
        h.runner.flushCoalescedSignals()
        #expect(activity == base + 3)
    }

    @Test("④ 읽음 신호는 곧바로 부르지 않고 창 끝에 한 번(예전과 같다) — 모아 둔 읽음이 조용한 drain 을 붙잡지 않는다")
    func readSignalStaysTrailingOnly() async {
        let h = await makeHarness()
        defer { h.tearDown() }
        h.runner.coalesceSeconds = 10
        var activity = 0
        var reads = 0
        let activityToken = h.runner.onMessageActivity { activity += 1 }
        let readToken = h.runner.onMessageRead { reads += 1 }
        defer { activityToken.cancel(); readToken.cancel() }
        let base = subscribeAndGoQuiet(h) { activity }

        h.transport.emit(.broadcast(event: "message_read"))
        #expect(h.runner.effectLog.last == .messageReadSignal)
        #expect(reads == 0, "조용한 상태라도 읽음 신호는 곧바로 부르지 않는다(뒤쪽 합치기만)")
        h.transport.emit(.broadcast(event: "message_read"))
        #expect(reads == 0 && activity == base, "읽음 신호가 메시지 활동을 깨웠다")

        h.transport.emit(.broadcast(event: "ring"))   // 읽음 창이 열려 있어도 활동의 앞쪽은 따로다
        #expect(activity == base + 1, "모아 둔 읽음 신호가 조용한 drain 을 창 끝까지 붙잡았다")
        #expect(reads == 0)

        h.runner.flushCoalescedSignals()   // 창 끝
        #expect(reads == 1, "읽음 두 건이 창 끝 한 번으로 모여야 한다")
        #expect(h.runner.readFlushCount == 1)
        #expect(activity == base + 1, "창 끝에 활동을 또 불렀다(모아 둔 활동이 없다)")
    }

    @Test("⑤ active 가 아니면 곧바로 부르지 않는다 — 모아 두었다가 창 끝에 한 번, background 진입은 모아 둔 것을 버린다")
    func notActiveNeverFlushesImmediately() async throws {
        let h = await makeHarness()
        defer { h.tearDown() }
        h.runner.coalesceSeconds = 10
        var activity = 0
        let token = h.runner.onMessageActivity { activity += 1 }
        defer { token.cancel() }

        // 실제로는 active 일 때만 붙는다 — 여기서는 문 하나(active 여부)만 따로 재려고 링을 직접 몬다.
        let access = try #require(h.session.session?.accessToken)
        h.runner.apply(.signedIn(accessToken: access))
        h.runner.apply(.transport(.joined))                     // → .catchUp
        #expect(h.runner.state.isSubscribed, "전제: 붙어 있다")
        #expect(!h.runner.isAppActive)
        #expect(h.runner.effectLog.contains(.catchUp))
        #expect(activity == 0, "active 가 아닌데 catchUp 을 곧바로 불렀다")
        h.runner.apply(.transport(.broadcast(event: "ring")))   // → .drain
        #expect(activity == 0, "active 가 아닌데 drain 을 곧바로 불렀다")
        h.runner.flushCoalescedSignals()
        #expect(activity == 1, "모아 둔 신호를 창 끝에 한 번 갚아야 한다(뒤쪽 합치기는 남는다)")

        // 폐기 규칙: active 에서 창 안에 모인 drain 은 background 로 가면 버린다.
        h.runner.appDidBecomeActive()
        h.clock.advance(10)
        h.transport.emit(.broadcast(event: "ring"))             // 앞쪽(곧바로)
        #expect(activity == 2)
        h.transport.emit(.broadcast(event: "ring"))             // 창 안 → 모은다
        #expect(activity == 2)
        h.runner.appDidEnterBackground()
        h.runner.flushCoalescedSignals()
        #expect(activity == 2, "background 진입 뒤에도 모아 둔 신호를 갚았다(폐기 규칙)")
    }

    @Test("창 끝 타이머는 '마지막 flush + 창'에 돈다 — 모은 drain 의 도착 + 창이 아니다(훅 없이, 주입 시계로 남은 창을 잰다)")
    func activityWindowEndUsesRemainingWindow() async {
        let h = await makeHarness()
        defer { h.tearDown() }
        h.runner.coalesceSeconds = 30
        var activity = 0
        let token = h.runner.onMessageActivity { activity += 1 }
        defer { token.cancel() }
        let base = subscribeAndGoQuiet(h) { activity }

        h.transport.emit(.broadcast(event: "ring"))   // 앞쪽
        #expect(activity == base + 1)
        h.clock.advance(29.9)                         // 창 끝까지 0.1초 남았다
        h.transport.emit(.broadcast(event: "ring"))
        #expect(activity == base + 1, "창 안의 drain 을 곧바로 불렀다")
        // 남은 0.1초 뒤에 돌아야 한다. 도착 + 창(30초)으로 잡으면 이 대기(≥5초)를 넘긴다.
        #expect(await baseWaitUntil(turns: 1_000) { activity == base + 2 }, "창 끝 타이머가 남은 창이 아니라 창 전체를 기다렸다(또는 돌지 않았다)")
        try? await Task.sleep(for: .milliseconds(300))
        #expect(activity == base + 2, "모아 둔 것이 없는데 창 끝에 또 불렀다")
    }

    @Test("읽음 창 끝 타이머도 훅 없이 돈다 — 읽음 두 건이 창 끝에 한 번")
    func readWindowEndTimerFires() async {
        let h = await makeHarness()
        defer { h.tearDown() }
        h.runner.coalesceSeconds = 0.2
        var reads = 0
        let token = h.runner.onMessageRead { reads += 1 }
        defer { token.cancel() }
        h.runner.appDidBecomeActive()
        h.transport.emit(.joined)
        h.transport.emit(.broadcast(event: "message_read"))
        h.transport.emit(.broadcast(event: "message_read"))
        #expect(reads == 0)
        #expect(await baseWaitUntil { reads == 1 }, "읽음 창 끝 타이머가 돌지 않았다")
        try? await Task.sleep(for: .milliseconds(500))
        #expect(reads == 1, "읽음 두 건을 창 끝에 두 번 갚았다")
    }

    @Test("테트리스 초인종(맥 0.3.60)은 폰에서 자기 가지로 가고 아무것도 부르지 않는다 — drain(메시지 활동 조회)으로 새지 않는다")
    func tetrisSignalIsItsOwnEmptyBranchOnThePhone() async {
        // 없으면: 폰 화면이 없는 1.0.11 전까지 'tetris' 초인종(판 중 공격마다 울린다)이 drain 갈래로 떨어져
        // 울릴 때마다 메시지 활동 조회가 한 번씩 더 나간다.
        let h = await makeHarness()
        defer { h.tearDown() }
        var activity = 0
        let token = h.runner.onMessageActivity { activity += 1 }
        h.runner.appDidBecomeActive()
        h.transport.emit(.joined)                               // → .catchUp(합치기 창에 한 번)
        h.runner.flushCoalescedSignals()
        let afterJoin = activity
        #expect(afterJoin == 1, "전제: 조인 따라잡기가 활동 조회를 한 번 부른다")

        h.transport.emit(.broadcast(event: "tetris"))
        h.transport.emit(.broadcast(event: "tetris"))
        #expect(h.runner.effectLog.filter { $0 == .tetrisSignal }.count == 2)
        #expect(!h.runner.effectLog.suffix(2).contains(.drain))
        h.runner.flushCoalescedSignals()
        #expect(activity == afterJoin, "테트리스 초인종이 메시지 활동 조회로 샜다")

        // ★ 기준선: 모르는 이름은 예전 그대로 drain → 활동 조회 한 번(그래야 위 '안 늘었다' 가 뜻을 가진다).
        h.transport.emit(.broadcast(event: "모르는이름"))
        h.runner.flushCoalescedSignals()
        #expect(activity == afterJoin + 1)
        await baseBarrier(h.session.service)
        #expect(!h.requests.contains { ($0.rpcName ?? "").hasPrefix("tetris_") }, "폰이 테트리스 RPC 를 불렀다(화면이 없다)")
        #expect(!h.requests.map(\.path).contains("/rest/v1/rpc/take_pokes"))
        token.cancel()
    }

    @Test("background → willSleep(소켓 내림) · active → didWake(다시 붙음) · 로그아웃 → signedOut")
    func lifecycle() async {
        let h = await makeHarness()
        defer { h.tearDown() }
        h.runner.appDidBecomeActive()
        h.transport.emit(.joined)
        let disconnectsBefore = h.transport.disconnectCount

        h.runner.appDidEnterBackground()
        #expect(h.runner.state == .idle(.suspended))
        #expect(h.transport.disconnectCount == disconnectsBefore + 1)

        h.runner.appDidBecomeActive()
        #expect(h.transport.connects.count == 2)

        await h.session.signOut()
        #expect(h.runner.state == .idle(.signedOut))
    }

    @Test("다른 경로(401 재시도)가 토큰을 바꾸면 붙어 있는 채널에 새 토큰을 민다(재연결 없음)")
    func pushesRefreshedToken() async {
        let h = await makeHarness()
        defer { h.tearDown() }
        h.runner.appDidBecomeActive()
        h.transport.emit(.joined)
        h.runner.accessTokenDidChange("new-token")
        #expect(h.transport.pushedTokens == ["new-token"])
        #expect(h.transport.connects.count == 1)
    }

    @Test("소켓이 없는 조립(데모·테스트·킬스위치)은 링이 disabled 로 움직이지 않는다")
    func noTransportStaysDisabled() async {
        let service = BaseStub.makeService(host: BaseStub.makeHost("rt-none"))
        let runner = MobileRealtimeRunner(service: service, transport: nil, clock: .system, runsTimers: false)
        runner.appDidBecomeActive()
        runner.apply(.signedIn(accessToken: "t"))
        #expect(runner.state == .idle(.disabled))
    }
}

struct BaseNoBody: Encodable {}
