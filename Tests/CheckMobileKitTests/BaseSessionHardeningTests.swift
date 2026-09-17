import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// dbase-fix 회귀(검증 V1~V4): 로그아웃 서버 정리(만료 토큰 · 오프라인 · 같은 계정 재로그인) · 실행 복원 중 딥링크 ·
/// 늦게 끝난 옛 실시간 갱신 · 느린 client_release.
@MainActor
@Suite(.serialized) struct BaseSessionHardeningTests {
    nonisolated static let installation = "11111111-2222-4333-8444-555555555555"

    struct Harness {
        let host: String
        let storage: AingSharedStorage
        let vault: InMemoryTokenVault
        let clock: BaseTestClock

        var requests: [MobileStubRequest] { MobileStubURLProtocol.requests(host: host) }

        func paths() -> [String] {
            requests.map { $0.rpcName.map { "rpc/\($0)" } ?? $0.path }
        }

        func bearers(_ filter: (MobileStubRequest) -> Bool) -> [String] {
            requests.filter(filter).map { BaseStub.bearer($0).replacingOccurrences(of: "Bearer ", with: "") }
        }

        @MainActor
        func makeSession() -> MobileSessionStore {
            MobileSessionStore(
                service: BaseStub.makeService(host: host),
                vault: vault,
                storage: storage,
                appInfo: BaseStub.appInfo,
                installationID: BaseSessionHardeningTests.installation,
                clock: clock.clock
            )
        }

        @MainActor
        func makeModel(transport: BaseFakeTransport? = nil) -> MobileAppModel {
            MobileAppModel(environment: MobileEnvironment(
                service: BaseStub.makeService(host: host),
                vault: vault,
                storage: storage,
                appInfo: BaseStub.appInfo,
                clock: clock.clock,
                installationID: BaseSessionHardeningTests.installation,
                realtimeTransport: transport,
                runsTimers: false,
                reloadWidgetTimelines: {}
            ))
        }

        func tearDown() { BaseStub.tearDown(host: host, storage: storage) }
    }

    /// 키체인에 `access`/`refresh` 가 있는 로그인 상태로 시작하는 하네스.
    func makeHarness(label: String, access: String?, refresh: String? = "r1", userID: String = "user-1",
                     responder: @escaping MobileStubURLProtocol.Responder) -> Harness {
        let host = BaseStub.makeHost(label)
        MobileStubURLProtocol.register(host: host, responder: responder)
        let storage = BaseStub.makeStorage()
        let vault = InMemoryTokenVault()
        if let access {
            vault.write(access, key: AingKeychain.accessTokenKey)
            if let refresh { vault.write(refresh, key: AingKeychain.refreshTokenKey) }
            storage.defaults.set(userID, forKey: AingSharedKeys.userID)
        }
        return Harness(host: host, storage: storage, vault: vault, clock: BaseTestClock())
    }

    /// release · register · unregister · memberships · logout 이 ok 인 서버에 사건별 덮어쓰기를 얹는다.
    static func server(_ extra: @escaping @Sendable (MobileStubRequest) -> MobileStubResponse? = { _ in nil }) -> MobileStubURLProtocol.Responder {
        { request in
            if let custom = extra(request) { return custom }
            switch request.rpcName {
            case "client_release": return BaseStub.releaseOK
            case "register_device": return BaseStub.registerOK
            case "unregister_device": return .json(#"{"status":"ok","removed":true}"#)
            default: break
            }
            if request.path == "/rest/v1/memberships" { return BaseStub.membershipOK }
            if request.path == "/auth/v1/logout" { return .json("{}") }
            return .missingFunction(request.path)
        }
    }

    // MARK: - V2 로그아웃 서버 정리

    @Test("만료된 access token 으로 로그아웃해도 한 번 갱신해 unregister_device 를 다시 부르고, 새 토큰으로 logout?scope=local 을 보낸다")
    func signOutWithExpiredAccessTokenRefreshesAndUnregisters() async throws {
        let old = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600), salt: "old")
        let fresh = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(7200), salt: "fresh")
        let expired = BaseLockedBox(false)
        let h = makeHarness(label: "fix-expired", access: old, responder: Self.server { request in
            if expired.get(), BaseStub.bearer(request) == "Bearer \(old)", request.path != "/auth/v1/token" { return BaseStub.jwtExpired }
            if request.path == "/auth/v1/token" { return BaseStub.authResponse(access: fresh, refresh: "r2", userID: "user-1") }
            return nil
        })
        defer { h.tearDown() }
        let session = h.makeSession()
        await session.launch()
        await session.pendingDeviceRegistration?.value
        _ = await baseWaitUntil { session.profile?.teamName != nil }
        MobileStubURLProtocol.clearRequests(host: h.host)

        expired.mutate { $0 = true }   // 한 시간 뒤: 서버가 옛 access token 을 거절한다
        await session.signOut()

        #expect(h.paths() == ["rpc/unregister_device", "/auth/v1/token", "rpc/unregister_device", "/auth/v1/logout"], "\(h.paths())")
        #expect(h.bearers { $0.rpcName == "unregister_device" } == [old, fresh], "두 번째 unregister 는 갱신한 토큰이어야 한다")
        let refresh = try #require(h.requests.first { $0.path == "/auth/v1/token" })
        #expect(refresh.queryValue("grant_type") == "refresh_token")
        #expect(refresh.bodyText.contains(#""refresh_token":"r1""#), "로그아웃 직전에 붙잡아 둔 refresh token 으로 갱신한다")
        let logout = try #require(h.requests.last)
        #expect(logout.path == "/auth/v1/logout")
        #expect(logout.queryValue("scope") == "local")
        #expect(BaseStub.bearer(logout) == "Bearer \(fresh)", "옛 토큰으로 보내면 401 이라 서버 세션이 살아남는다")

        #expect(session.phase == .signedOut)
        #expect(session.session == nil)
        #expect(h.vault.read(AingKeychain.accessTokenKey) == nil, "정리용 갱신 토큰이 로그인 칸으로 되살아나면 안 된다")
        #expect(h.vault.read(AingKeychain.refreshTokenKey) == nil)
        #expect(!session.hasPendingSignOutCleanup, "끝난 정리가 장부에 남았다")
        #expect(MobileForbiddenCalls.violations(in: h.requests).isEmpty)
    }

    @Test("오프라인 로그아웃은 정리 빚으로 남고, 다음 실행(또는 active)에서 옛 토큰으로 unregister_device → logout?scope=local 을 마친다")
    func offlineSignOutIsSettledLater() async throws {
        let access = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600))
        let offline = BaseLockedBox(false)
        let h = makeHarness(label: "fix-offline", access: access, responder: Self.server { _ in
            offline.get() ? .networkFailure() : nil
        })
        defer { h.tearDown() }
        let session = h.makeSession()
        await session.launch()
        await session.pendingDeviceRegistration?.value
        _ = await baseWaitUntil { session.profile?.teamName != nil }

        offline.mutate { $0 = true }
        MobileStubURLProtocol.clearRequests(host: h.host)
        await session.signOut()
        #expect(session.phase == .signedOut, "오프라인이어도 화면은 곧바로 로그아웃이다")
        #expect(h.vault.read(AingKeychain.accessTokenKey) == nil)
        #expect(h.storage.defaults.string(forKey: AingSharedKeys.userID) == nil)
        #expect(h.paths() == ["rpc/unregister_device"], "\(h.paths())")
        #expect(session.hasPendingSignOutCleanup, "못 알린 정리를 버렸다 — 이 폰에 앞 계정의 푸시가 계속 온다")

        // 같은 실행 안에서 다시 active 가 되어도(로그아웃 상태) 갚는다 — 아직 오프라인이면 그대로 남는다.
        session.appDidBecomeActive()
        await session.pendingSignOutCleanup?.value
        #expect(session.hasPendingSignOutCleanup)

        // 다음 실행: 새 스토어 · 같은 키체인. 온라인이면 실행 직후 갚는다.
        offline.mutate { $0 = false }
        MobileStubURLProtocol.clearRequests(host: h.host)
        let relaunched = h.makeSession()
        await relaunched.launch()
        #expect(relaunched.phase == .signedOut)
        await relaunched.pendingSignOutCleanup?.value
        #expect(h.paths() == ["rpc/client_release", "rpc/unregister_device", "/auth/v1/logout"], "\(h.paths())")
        #expect(h.bearers { $0.rpcName == "unregister_device" || $0.path == "/auth/v1/logout" } == [access, access])
        #expect(h.requests.last?.queryValue("scope") == "local")
        #expect(!relaunched.hasPendingSignOutCleanup)

        // 갚은 뒤의 active 는 요청을 만들지 않는다.
        MobileStubURLProtocol.clearRequests(host: h.host)
        relaunched.appDidBecomeActive()
        await relaunched.pendingSignOutCleanup?.value
        #expect(h.requests.isEmpty, "\(h.paths())")
        #expect(MobileForbiddenCalls.violations(in: h.requests).isEmpty)
    }

    @Test("정리 중 갱신이 치명(invalid_grant)이면 빚을 버린다 — 알릴 방법이 없는 세션을 매 실행마다 두드리지 않는다")
    func fatalRefreshDropsTheDebt() async {
        let old = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600), salt: "old")
        let expired = BaseLockedBox(false)
        let h = makeHarness(label: "fix-fatal", access: old, responder: Self.server { request in
            if expired.get(), request.path == "/auth/v1/token" { return BaseStub.invalidGrant }
            if expired.get(), BaseStub.bearer(request) == "Bearer \(old)" { return BaseStub.jwtExpired }
            return nil
        })
        defer { h.tearDown() }
        let session = h.makeSession()
        await session.launch()
        await session.pendingDeviceRegistration?.value
        expired.mutate { $0 = true }
        MobileStubURLProtocol.clearRequests(host: h.host)

        await session.signOut()
        #expect(h.paths() == ["rpc/unregister_device", "/auth/v1/token"], "\(h.paths())")
        #expect(!session.hasPendingSignOutCleanup)
        MobileStubURLProtocol.clearRequests(host: h.host)
        session.appDidBecomeActive()
        await session.pendingSignOutCleanup?.value
        #expect(h.requests.isEmpty)
    }

    @Test("빚이 남은 채 같은 계정으로 다시 로그인하면 새 세션의 기기 행을 지우지 않고 옛 세션만 logout?scope=local 한다")
    func sameAccountReSignInKeepsTheNewDeviceRow() async throws {
        let old = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600), salt: "old")
        let second = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600), salt: "second")
        let offline = BaseLockedBox(false)
        let h = makeHarness(label: "fix-same", access: old, responder: Self.server { request in
            if offline.get() { return .networkFailure() }
            if request.path == "/auth/v1/token" { return BaseStub.authResponse(access: second, refresh: "r-second", userID: "user-1") }
            return nil
        })
        defer { h.tearDown() }
        let session = h.makeSession()
        await session.launch()
        await session.pendingDeviceRegistration?.value
        offline.mutate { $0 = true }
        await session.signOut()
        #expect(session.hasPendingSignOutCleanup)

        offline.mutate { $0 = false }
        MobileStubURLProtocol.clearRequests(host: h.host)
        await session.signIn(email: "a@b.c", password: "pw")
        #expect(session.phase == .signedIn)
        await session.pendingSignOutCleanup?.value
        await session.pendingDeviceRegistration?.value
        #expect(h.requests.filter { $0.rpcName == "unregister_device" }.isEmpty, "같은 계정의 새 기기 행을 지웠다: \(h.paths())")
        #expect(h.bearers { $0.path == "/auth/v1/logout" } == [old], "옛 세션만 끊는다")
        #expect(h.bearers { $0.rpcName == "register_device" } == [second])
        #expect(!session.hasPendingSignOutCleanup)
        #expect(h.vault.read(AingKeychain.accessTokenKey) == second, "빚 정리가 새 로그인의 키체인을 건드렸다")
    }

    // MARK: - 키체인이 없는 빌드

    @Test("키체인 저장이 실패하는 빌드(서명 없는 시뮬레이터 -34018)에서도 설치 식별자는 실행 사이에 같다 — 대조: 대체 저장소가 없으면 매번 새 값")
    func installationIDSurvivesBrokenKeychain() {
        let storage = BaseStub.makeStorage()
        defer { BaseStub.tearDown(host: "none", storage: storage) }
        let broken = InMemoryTokenVault()
        broken.failsWrites = true

        let first = InstallationID.current(store: broken, fallback: storage.defaults)
        #expect(UUID(uuidString: first) != nil)
        #expect(InstallationID.current(store: broken, fallback: storage.defaults) == first, "실행마다 새 기기 행이 생긴다")
        #expect(InstallationID.current(store: broken) != first, "대조: 대체 저장소 없이는 값이 바뀐다(고장 재현이 실제로 일어났다)")

        // 키체인이 정상이면 공용 suite 에 쓰지 않는다(키체인이 먼저 — 앱을 지웠다 깔아도 같은 값).
        let healthy = InMemoryTokenVault()
        let otherStorage = BaseStub.makeStorage()
        defer { BaseStub.tearDown(host: "none", storage: otherStorage) }
        let id = InstallationID.current(store: healthy, fallback: otherStorage.defaults)
        #expect(otherStorage.defaults.string(forKey: AingKeychain.installationIDKey) == nil)
        #expect(healthy.read(AingKeychain.installationIDKey) == id)
        // 대체 저장소에만 있던 값은 키체인이 되살아나면 그쪽으로 옮긴다.
        let recovered = InMemoryTokenVault()
        #expect(InstallationID.current(store: recovered, fallback: storage.defaults) == first)
        #expect(recovered.read(AingKeychain.installationIDKey) == first)
    }

    // MARK: - V1 실행 복원 중 딥링크

    @Test("실행 복원 중(launching)에 온 딥링크는 붙잡아 두었다가 로그인 상태가 되면 연다")
    func deepLinkDuringLaunchOpensAfterRestore() async {
        let access = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600))
        let h = makeHarness(label: "fix-link", access: access, responder: Self.server { request in
            guard request.rpcName == "client_release" else { return nil }
            var slow = BaseStub.releaseOK
            slow.delay = 0.3   // 실서버 왕복 흉내 — 그 사이 onOpenURL 이 먼저 온다
            return slow
        })
        defer { h.tearDown() }
        let model = h.makeModel()

        // MobileRootView.onAppear 순서 그대로: start() → scenePhase active → (콜드 스타트 URL) onOpenURL
        model.start()
        model.sceneDidBecomeActive()
        #expect(model.session.phase == .launching)
        #expect(model.handleOpenURL(URL(string: "aingcheck://message/peer-42")!), "복원 중 링크를 버렸다")
        #expect(model.router.selectedTab == .now, "로그인 전에 탭을 바꾸면 안 된다")

        #expect(await baseWaitUntil { model.session.phase == .signedIn })
        #expect(model.router.selectedTab == .messages)
        #expect(model.router.consumePendingRoute(for: .messages) == .message(peerID: "peer-42"))
    }

    @Test("복원이 로그아웃으로 끝나면 붙잡은 링크는 버린다 — 나중에 로그인해도 열리지 않고, 로그아웃 상태의 링크는 여전히 무시")
    func deepLinkDuringLaunchIsDroppedWhenSignedOut() async {
        let fresh = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600))
        let h = makeHarness(label: "fix-link-out", access: nil, responder: Self.server { request in
            if request.rpcName == "client_release" {
                var slow = BaseStub.releaseOK
                slow.delay = 0.3
                return slow
            }
            if request.path == "/auth/v1/token" { return BaseStub.authResponse(access: fresh, refresh: "r", userID: "user-1") }
            return nil
        })
        defer { h.tearDown() }
        let model = h.makeModel()
        model.start()
        model.sceneDidBecomeActive()
        _ = model.handleOpenURL(URL(string: "aingcheck://gomoku/invite/match-1")!)
        #expect(await baseWaitUntil { model.session.phase == .signedOut })
        #expect(model.router.selectedTab == .now)
        #expect(!model.handleOpenURL(URL(string: "aingcheck://message/p1")!), "로그아웃 상태에서 링크를 열었다")

        await model.session.signIn(email: "a@b.c", password: "pw")
        #expect(model.session.phase == .signedIn)
        #expect(model.router.selectedTab == .now, "실행 때 버렸어야 할 링크가 로그인 뒤에 열렸다")
        #expect(model.router.consumePendingRoute(for: .games) == nil)
    }

    // MARK: - V3 늦게 끝난 옛 실시간 갱신

    @Test("실시간 강제 갱신이 떠 있는 동안 로그아웃→재로그인해도, 늦게 끝난 옛 갱신이 새 세션의 소켓을 내리지 않는다")
    func staleRealtimeRefreshDoesNotKillNextSession() async {
        let first = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600), salt: "first")
        let refreshed = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600), salt: "refreshed")
        let second = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600), salt: "second")
        let h = makeHarness(label: "fix-rt", access: first, refresh: "r-first", responder: Self.server { request in
            guard request.path == "/auth/v1/token" else { return nil }
            if request.queryValue("grant_type") == "refresh_token" {
                var slow = BaseStub.authResponse(access: refreshed, refresh: "r-refreshed", userID: "user-1")
                slow.delay = 0.8
                return slow
            }
            return BaseStub.authResponse(access: second, refresh: "r-second", userID: "user-1")
        })
        defer { h.tearDown() }
        let transport = BaseFakeTransport()
        let model = h.makeModel(transport: transport)
        model.start()
        #expect(await baseWaitUntil { model.session.phase == .signedIn })
        model.sceneDidBecomeActive()
        #expect(transport.connects.count == 1)

        transport.emit(.joinRejected(.expiredToken))   // → .refreshToken → refreshForRealtime(0.8초)
        #expect(await baseWaitUntil { MobileStubURLProtocol.requests(host: h.host).contains { $0.queryValue("grant_type") == "refresh_token" } })
        await model.session.signOut()
        await model.session.signIn(email: "a@b.c", password: "pw")
        #expect(model.session.phase == .signedIn)
        #expect(transport.connects.count == 2)
        let disconnectsBefore = transport.disconnectCount

        try? await Task.sleep(for: .milliseconds(1200))   // 옛 갱신 응답 도착
        #expect(model.realtime.state != .idle(.signedOut), "옛 세대의 갱신 결과가 새 세션의 링을 로그아웃으로 접었다: \(model.realtime.state)")
        #expect(transport.disconnectCount == disconnectsBefore)
        transport.emit(.joined)
        #expect(model.realtime.state.isSubscribed, "새 세션 조인이 무시됐다: \(model.realtime.state)")
        #expect(model.session.session?.accessToken == second, "옛 갱신 토큰이 새 세션에 쓰였다")
    }

    // MARK: - V4 느린 client_release

    @Test("client_release 가 느리면 짧은 제한 시간 뒤 키체인 복원으로 넘어간다 — 대조: 제한 안에 온 최소 빌드는 여전히 막는다")
    func slowClientReleaseDoesNotHoldLaunch() async {
        let access = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600))
        let slow = makeHarness(label: "fix-slow", access: access, responder: Self.server { request in
            guard request.rpcName == "client_release" else { return nil }
            var response = BaseStub.releaseOK
            response.delay = 2.0
            return response
        })
        defer { slow.tearDown() }
        let session = slow.makeSession()
        session.clientReleaseTimeoutSeconds = 0.3
        let started = Date()
        await session.launch()
        let elapsed = Date().timeIntervalSince(started)
        #expect(session.phase == .signedIn)
        #expect(elapsed < 1.5, "느린 client_release 를 \(elapsed)초 기다렸다")

        let blocked = makeHarness(label: "fix-slow-min", access: access, responder: Self.server { request in
            guard request.rpcName == "client_release" else { return nil }
            return .json(#"{"status":"ok","platform":"ios","min_build":5,"latest_build":6}"#, delay: 0.05)
        })
        defer { blocked.tearDown() }
        let gated = blocked.makeSession()
        gated.clientReleaseTimeoutSeconds = 0.3
        await gated.launch()
        #expect(gated.phase == .needsUpdate(minBuild: 5))
        #expect(MobileSessionStore.defaultClientReleaseTimeoutSeconds <= 5, "기본 제한이 운영 요청 타임아웃(15초)과 같으면 고친 것이 아니다")
    }
}
