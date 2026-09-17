import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 실시간 러너(SPEC-ios-build §1-6): 연결은 active+로그인일 때만, `.drain`·`.catchUp` → 메시지 핸들러(1초 합치기),
/// 읽음 신호 → 읽음 핸들러, 오목 신호 → GomokuStore, **take_pokes 0건**(스텁이 받은 경로로 단언).
@MainActor
@Suite struct BaseRealtimeRunnerTests {
    struct Harness {
        let host: String
        let storage: AingSharedStorage
        let session: MobileSessionStore
        let runner: MobileRealtimeRunner
        let transport: BaseFakeTransport
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
        return Harness(host: host, storage: storage, session: session, runner: runner, transport: transport, gomokuHost: host2, gomoku: gomoku)
    }

    @Test("로그인 상태라도 앱이 active 가 아니면 붙지 않는다 — active 가 되면 poke:<uid> private 채널로 지금 토큰을 들고 붙는다")
    func connectsOnlyWhenActive() async {
        let h = await makeHarness()
        defer { h.tearDown() }
        #expect(h.session.phase == .signedIn)
        #expect(h.transport.connects.isEmpty, "background 에서 로그인만으로 소켓을 열었다")

        h.runner.appDidBecomeActive()
        #expect(h.transport.connects.count == 1)
        let connect = h.transport.connects[0]
        #expect(connect.channel == "poke:user-7")
        #expect(connect.isPrivate)
        #expect(connect.accessToken == h.session.session?.accessToken)
        #expect(h.runner.state == .connecting(attempt: 1, since: MobileClock.demoInstant))
    }

    @Test("drain·catchUp·읽음은 창 하나에 모여 한 번씩 부르고, 오목 신호는 GomokuStore 로 간다 — take_pokes 등 금지 경로 0건")
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
        h.transport.emit(.joined)                               // → .catchUp
        #expect(h.runner.state.isSubscribed)
        h.transport.emit(.broadcast(event: "ring"))             // → .drain
        h.transport.emit(.broadcast(event: ""))                 // → .drain(이름 없음도)
        h.transport.emit(.broadcast(event: "message_read"))     // → .messageReadSignal
        h.transport.emit(.broadcast(event: "message_read"))
        #expect(activity == 0 && reads == 0, "창이 닫히기 전에 핸들러를 불렀다(합치기 없음)")
        h.runner.flushCoalescedSignals()
        #expect(activity == 1, "catchUp + drain 2건이 한 번으로 모여야 한다")
        #expect(reads == 1)
        #expect(h.runner.activityFlushCount == 1 && h.runner.readFlushCount == 1)

        h.transport.emit(.broadcast(event: "gomoku"))           // → GomokuStore.handleSignal
        #expect(h.runner.effectLog.contains(.gomokuSignal))
        #expect(await baseWaitUntil { h.requests.contains { $0.rpcName == "message_unread_summary" } })
        #expect(await baseWaitUntil { h.requests.contains { ($0.rpcName ?? "").hasPrefix("gomoku_") } },
                "오목 신호·조인 따라잡기가 오목 조회를 부르지 않았다")
        try? await Task.sleep(for: .milliseconds(200))

        let paths = h.requests.map(\.path)
        #expect(!paths.contains("/rest/v1/rpc/take_pokes"), "폰이 take_pokes 를 불렀다(맥 말풍선 훔치기 — R3)")
        #expect(MobileForbiddenCalls.violations(in: h.requests).isEmpty, "\(MobileForbiddenCalls.violations(in: h.requests))")
        activityToken.cancel()
        h.transport.emit(.broadcast(event: "ring"))
        h.runner.flushCoalescedSignals()
        #expect(activity == 1, "취소한 핸들러가 불렸다")
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
