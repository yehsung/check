import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 세션(SPEC-ios §2): 복원 · 최소 빌드 · 실행 직후 갱신 · 갱신 경합 · 치명/일시 오류 · 로그인 · 로그아웃(세대·scope=local) · 기기 등록 스로틀.
@MainActor
@Suite struct BaseSessionTests {
    struct Harness {
        let host: String
        let storage: AingSharedStorage
        let vault: InMemoryTokenVault
        let clock: BaseTestClock
        let service: SupabaseWorkService
        let session: MobileSessionStore

        var requests: [MobileStubRequest] { baseRequests(host: host) }

        func paths(_ filter: (MobileStubRequest) -> Bool = { _ in true }) -> [String] {
            requests.filter(filter).map { $0.rpcName.map { "rpc/\($0)" } ?? $0.path }
        }

        func count(rpc: String) -> Int { requests.filter { $0.rpcName == rpc }.count }

        func count(grant: String) -> Int {
            requests.filter { $0.path == "/auth/v1/token" && $0.queryValue("grant_type") == grant }.count
        }

        func tearDown() { BaseStub.tearDown(host: host, storage: storage) }
    }

    func makeHarness(
        appBuild: Int = 1,
        seedAccess: String? = nil,
        seedRefresh: String? = "refresh-old",
        userID: String = "user-1",
        responder: @escaping MobileStubURLProtocol.Responder
    ) -> Harness {
        let host = BaseStub.makeHost("session")
        MobileStubURLProtocol.register(host: host, responder: responder)
        let storage = BaseStub.makeStorage()
        let vault = InMemoryTokenVault()
        if let seedAccess {
            vault.write(seedAccess, key: AingKeychain.accessTokenKey)
            if let seedRefresh { vault.write(seedRefresh, key: AingKeychain.refreshTokenKey) }
            storage.defaults.set(userID, forKey: AingSharedKeys.userID)
        }
        let clock = BaseTestClock()
        var info = BaseStub.appInfo
        info.build = appBuild
        let service = BaseStub.makeService(host: host)
        let session = MobileSessionStore(
            service: service,
            vault: vault,
            storage: storage,
            appInfo: info,
            installationID: "11111111-2222-4333-8444-555555555555",
            clock: clock.clock
        )
        session.clientReleaseTimeoutSeconds = 0   // 벽시계 상한 없음(포화에서 최소 빌드 답이 3초를 넘어도 같은 경로)
        return Harness(host: host, storage: storage, vault: vault, clock: clock, service: service, session: session)
    }

    /// 흔한 서버: release ok · register ok · membership ok · 로그아웃 ok.
    static func happyServer(extra: @escaping @Sendable (MobileStubRequest) -> MobileStubResponse? = { _ in nil }) -> MobileStubURLProtocol.Responder {
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

    // MARK: - 실행

    @Test("키체인 토큰이 있으면 복원해 로그인 상태가 되고, 소속을 읽고, 기기를 한 번 등록한다(app_build PATCH 없음)")
    func restoresStoredSession() async throws {
        let access = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600))
        let h = makeHarness(seedAccess: access, responder: Self.happyServer())
        defer { h.tearDown() }

        await h.session.launch()
        #expect(h.session.phase == .signedIn)
        #expect(h.session.session?.accessToken == access)
        #expect(h.session.latestBuild == 3)
        await h.session.pendingDeviceRegistration?.value
        #expect(await baseWaitUntil { h.session.profile?.teamName == "테스트팀" })
        #expect(h.count(rpc: "register_device") == 1)
        #expect(h.count(grant: "refresh_token") == 0, "유효한 토큰으로 실행하면 갱신하지 않는다")
        #expect(h.session.pushPrefs == PushPrefs(message: true, gomokuInvite: false, feedbackReply: true))
        let register = try #require(h.requests.first { $0.rpcName == "register_device" })
        #expect(register.bodyText.contains(#""p_platform":"ios""#))
        #expect(register.bodyText.contains(#""p_app_build":1"#))
        #expect(register.bodyText.contains(#""p_installation_id":"11111111-2222-4333-8444-555555555555""#))
        #expect(!register.bodyText.contains("p_apns_token"), "토큰이 없으면 키를 싣지 않는다(서버가 기존 토큰 유지)")
        #expect(MobileForbiddenCalls.violations(in: h.requests).isEmpty)
    }

    @Test("빌드가 서버 최소 빌드보다 낮으면 업데이트 화면에서 멈춘다(복원·인증 요청 0)")
    func needsUpdateStopsLaunch() async {
        let access = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600))
        let h = makeHarness(appBuild: 2, seedAccess: access) { request in
            request.rpcName == "client_release"
                ? .json(#"{"status":"ok","platform":"ios","min_build":5,"latest_build":6}"#)
                : .missingFunction(request.path)
        }
        defer { h.tearDown() }

        await h.session.launch()
        #expect(h.session.phase == .needsUpdate(minBuild: 5))
        #expect(h.paths() == ["rpc/client_release"])
    }

    @Test("client_release 가 없는 서버(404)·네트워크 실패는 막지 않는다 — 대조: 최소 빌드와 같으면 통과")
    func missingReleaseFunctionDoesNotBlock() async {
        let access = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600))
        let missing = makeHarness(seedAccess: access, responder: Self.happyServer(extra: { request in
            request.rpcName == "client_release" ? .missingFunction("client_release") : nil
        }))
        defer { missing.tearDown() }
        await missing.session.launch()
        #expect(missing.session.phase == .signedIn)

        let equal = makeHarness(appBuild: 5, seedAccess: access, responder: Self.happyServer(extra: { request in
            request.rpcName == "client_release" ? .json(#"{"status":"ok","min_build":5,"latest_build":5}"#) : nil
        }))
        defer { equal.tearDown() }
        await equal.session.launch()
        #expect(equal.session.phase == .signedIn)
    }

    @Test("저장된 토큰이 없으면 로그아웃 상태")
    func launchWithoutTokensIsSignedOut() async {
        let h = makeHarness(responder: Self.happyServer())
        defer { h.tearDown() }
        await h.session.launch()
        #expect(h.session.phase == .signedOut)
        #expect(h.count(rpc: "register_device") == 0)
    }

    @Test("곧 만료되는 토큰은 실행 직후 조정자로 한 번 갱신하고 새 토큰을 저장한다")
    func launchRefreshesNearExpiryToken() async {
        let old = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(20))
        let fresh = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600), salt: "fresh")
        let h = makeHarness(seedAccess: old, responder: Self.happyServer(extra: { request in
            request.path == "/auth/v1/token" ? BaseStub.authResponse(access: fresh, refresh: "refresh-new", userID: "user-1") : nil
        }))
        defer { h.tearDown() }

        await h.session.launch()
        #expect(h.session.phase == .signedIn)
        #expect(h.count(grant: "refresh_token") == 1)
        #expect(h.session.refreshCoordinator.completedRefreshCount == 1, "갱신은 조정자를 지난다")
        #expect(h.vault.read(AingKeychain.accessTokenKey) == fresh)
        #expect(h.vault.read(AingKeychain.refreshTokenKey) == "refresh-new")
    }

    @Test("실행 직후 갱신이 치명(invalid_grant)이면 로그아웃, 일시(503)면 세션 유지")
    func launchRefreshFatalVersusTransient() async {
        let old = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(10))

        let fatal = makeHarness(seedAccess: old, responder: Self.happyServer(extra: { request in
            request.path == "/auth/v1/token" ? BaseStub.invalidGrant : nil
        }))
        defer { fatal.tearDown() }
        await fatal.session.launch()
        #expect(fatal.session.phase == .signedOut)
        #expect(fatal.session.notice == "다시 로그인 필요")
        #expect(fatal.vault.read(AingKeychain.accessTokenKey) == nil)
        #expect(fatal.storage.defaults.string(forKey: AingSharedKeys.userID) == nil)

        let transient = makeHarness(seedAccess: old, responder: Self.happyServer(extra: { request in
            request.path == "/auth/v1/token" ? .json(#"{"msg":"upstream"}"#, status: 503) : nil
        }))
        defer { transient.tearDown() }
        await transient.session.launch()
        #expect(transient.session.phase == .signedIn)
        #expect(transient.vault.read(AingKeychain.accessTokenKey) == old)
    }

    // MARK: - 401 재시도

    @Test("동시에 401 을 맞은 두 요청은 갱신을 한 번만 하고 둘 다 새 토큰으로 재시도한다")
    func concurrent401RefreshOnce() async throws {
        let old = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600), salt: "old")
        let fresh = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(7200), salt: "fresh")
        let h = makeHarness(seedAccess: old, responder: Self.happyServer(extra: { request in
            if request.path == "/auth/v1/token" {
                return BaseStub.authResponse(access: fresh, refresh: "refresh-new", userID: "user-1")
            }
            if request.rpcName == "my_team_invite_code" {
                return BaseStub.bearer(request) == "Bearer \(fresh)" ? .json(#"[{"invite_code":"ABC123"}]"#) : BaseStub.jwtExpired
            }
            return nil
        }))
        defer { h.tearDown() }
        await h.session.launch()
        await h.session.pendingDeviceRegistration?.value
        #expect(h.count(grant: "refresh_token") == 0)

        let service = h.service
        let session = h.session
        // 갱신 응답을 붙잡는다 — 두 요청이 모두 401 을 맞은 뒤에야 갱신이 끝난다(경합을 벽시계 지연 없이 만든다).
        let refreshHold = BaseHold.install(host: h.host) { $0.path == "/auth/v1/token" && $0.queryValue("grant_type") == "refresh_token" }
        let first = Task { @MainActor in
            try await session.withMobileSessionRetry { current in
                try await service.fetchMyInviteCode(accessToken: current.accessToken)
            }
        }
        let second = Task { @MainActor in
            try await session.withMobileSessionRetry { current in
                try await service.fetchMyInviteCode(accessToken: current.accessToken)
            }
        }
        #expect(await refreshHold.waitHeld())
        #expect(await baseWaitUntil { h.count(rpc: "my_team_invite_code") == 2 }, "둘 다 옛 토큰으로 떠나지 않았다")
        #expect(await refreshHold.releaseAndWaitDelivered())
        let results = [try await first.value, try await second.value]
        #expect(results == ["ABC123", "ABC123"])
        #expect(h.count(rpc: "my_team_invite_code") == 4, "둘 다 401 을 맞고 둘 다 재시도했다(대조: 경합이 실제로 일어났다)")
        #expect(h.count(grant: "refresh_token") == 1, "갱신 요청은 한 번이어야 한다(refresh token 회전 경합 금지)")
        #expect(h.session.session?.accessToken == fresh)
        #expect(h.session.phase == .signedIn)
    }

    @Test("401 뒤 갱신이 치명이면 로그아웃(세대 +1), 일시면 세션을 유지하고 원래 오류를 던진다")
    func retryFatalVersusTransient() async {
        let old = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600))

        let fatal = makeHarness(seedAccess: old, responder: Self.happyServer(extra: { request in
            if request.path == "/auth/v1/token" { return BaseStub.invalidGrant }
            if request.path == "/rest/v1/memberships" { return BaseStub.jwtExpired }
            return nil
        }))
        defer { fatal.tearDown() }
        await fatal.session.launch()
        await fatal.session.pendingDeviceRegistration?.value
        _ = await baseWaitUntil { fatal.session.phase != .signedIn }
        let signedOutByProfile = fatal.session.phase == .signedOut
        if !signedOutByProfile {
            let generation = fatal.session.generation
            let service = fatal.service
            await #expect(throws: SupabaseWorkServiceError.self) {
                _ = try await fatal.session.withMobileSessionRetry { session in
                    try await service.fetchOwnMembership(accessToken: session.accessToken, userID: session.userID)
                }
            }
            #expect(fatal.session.generation == generation + 1)
        }
        #expect(fatal.session.phase == .signedOut)
        #expect(fatal.vault.read(AingKeychain.accessTokenKey) == nil)

        let transient = makeHarness(seedAccess: old, responder: Self.happyServer(extra: { request in
            if request.path == "/auth/v1/token" { return .json(#"{"msg":"busy"}"#, status: 503) }
            if request.path == "/rest/v1/memberships" { return BaseStub.jwtExpired }
            if request.rpcName == "register_device" { return BaseStub.jwtExpired }
            return nil
        }))
        defer { transient.tearDown() }
        await transient.session.launch()
        await transient.session.pendingDeviceRegistration?.value
        let service = transient.service
        await #expect(throws: SupabaseWorkServiceError.self) {
            _ = try await transient.session.withMobileSessionRetry { session in
                try await service.fetchOwnMembership(accessToken: session.accessToken, userID: session.userID)
            }
        }
        #expect(transient.session.phase == .signedIn)
        #expect(transient.vault.read(AingKeychain.accessTokenKey) == old)
    }

    // MARK: - 로그인

    @Test("로그인: 성공하면 토큰·userID·이메일을 저장하고 기기를 등록한다 / 틀린 비밀번호는 맥과 같은 문구")
    func signInSuccessAndFailure() async {
        let fresh = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600))
        let h = makeHarness(responder: Self.happyServer(extra: { request in
            guard request.path == "/auth/v1/token" else { return nil }
            if request.bodyText.contains("wrong") {
                return .json(#"{"error":"invalid_grant","error_description":"Invalid login credentials"}"#, status: 400)
            }
            return BaseStub.authResponse(access: fresh, refresh: "r1", userID: "user-9")
        }))
        defer { h.tearDown() }
        await h.session.launch()
        #expect(h.session.phase == .signedOut)

        await h.session.signIn(email: "a@b.c", password: "wrong")
        #expect(h.session.phase == .signedOut)
        #expect(h.session.notice == "로그인 정보 오류")

        await h.session.signIn(email: "  a@b.c ", password: "right")
        #expect(h.session.phase == .signedIn)
        #expect(h.session.notice == nil)
        #expect(h.vault.read(AingKeychain.accessTokenKey) == fresh)
        #expect(h.storage.defaults.string(forKey: AingSharedKeys.userID) == "user-9")
        #expect(h.session.storedEmail == "a@b.c")
        await h.session.pendingDeviceRegistration?.value
        #expect(h.count(rpc: "register_device") == 1)
        #expect(MobileForbiddenCalls.violations(in: h.requests).isEmpty)
    }

    // MARK: - 로그아웃

    @Test("로그아웃: 세대 +1 · 키체인/사용자 키/위젯 스냅샷 삭제 · 위젯 새로고침 · unregister_device → logout?scope=local 순서")
    func signOutClearsAndCallsServerInOrder() async throws {
        let access = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600))
        let h = makeHarness(seedAccess: access, responder: Self.happyServer())
        defer { h.tearDown() }
        await h.session.launch()
        await h.session.pendingDeviceRegistration?.value
        try WidgetSnapshotCodec.write(WidgetSnapshot(generatedAt: MobileClock.demoInstant), to: h.storage.widgetSnapshotURL)
        var reloads = 0
        var signedOutEvents = 0
        h.session.reloadWidgetTimelines = { reloads += 1 }
        h.session.onSignedOut = { signedOutEvents += 1 }
        let generation = h.session.generation
        MobileStubURLProtocol.clearRequests(host: h.host)

        await h.session.signOut()

        #expect(h.session.phase == .signedOut)
        #expect(h.session.generation == generation + 1)
        #expect(h.session.session == nil)
        #expect(h.vault.read(AingKeychain.accessTokenKey) == nil)
        #expect(h.vault.read(AingKeychain.refreshTokenKey) == nil)
        #expect(h.storage.defaults.string(forKey: AingSharedKeys.userID) == nil)
        #expect(!FileManager.default.fileExists(atPath: h.storage.widgetSnapshotURL.path))
        #expect(reloads == 1)
        #expect(signedOutEvents == 1)
        #expect(h.paths() == ["rpc/unregister_device", "/auth/v1/logout"])
        let logout = try #require(h.requests.last)
        #expect(logout.queryValue("scope") == "local", "scope=local 이 빠지면 맥 세션까지 끊긴다")
        #expect(BaseStub.bearer(logout) == "Bearer \(access)")
    }

    @Test("로그아웃 전에 떠난 느린 응답은 새 세대에 적용되지 않는다(세대 가드)")
    func lateResponseAfterSignOutIsDiscarded() async {
        let access = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600))
        let h = makeHarness(seedAccess: access, responder: Self.happyServer(extra: { request in
            guard request.path == "/rest/v1/memberships" else { return nil }
            return BaseStub.membershipOK
        }))
        defer { h.tearDown() }
        let membershipHold = BaseHold.install(host: h.host) { $0.path == "/rest/v1/memberships" }
        await h.session.launch()
        // launch 가 띄운 프로필 읽기가 **서버에 닿은 뒤**(= 붙잡혀 응답을 기다리는 중에) 로그아웃한다.
        // 요청이 떠나기 전에 로그아웃하면 세션 가드가 먼저 막아 세대 가드를 시험하지 못한다(변이 M9 실측).
        #expect(await membershipHold.waitHeld())
        await h.session.signOut()
        #expect(await membershipHold.releaseAndWaitDelivered())
        await baseBarrier(h.service)
        #expect(h.session.profile == nil, "로그아웃 뒤 도착한 소속 응답이 프로필을 되살렸다")
        #expect(h.session.phase == .signedOut)
    }

    // MARK: - 기기 등록

    @Test("register_device: 포그라운드는 1시간 스로틀, APNs 토큰이 바뀌면 즉시, 같은 토큰은 다시 안 보낸다")
    func deviceRegistrationThrottle() async throws {
        let access = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(86_400))
        let h = makeHarness(seedAccess: access, responder: Self.happyServer())
        defer { h.tearDown() }
        await h.session.launch()
        await h.session.pendingDeviceRegistration?.value
        #expect(h.count(rpc: "register_device") == 1)

        h.clock.advance(30 * 60)
        h.session.appDidBecomeActive()
        await h.session.pendingDeviceRegistration?.value
        #expect(h.count(rpc: "register_device") == 1, "30분 뒤 포그라운드는 스로틀에 걸린다")

        h.clock.advance(31 * 60)
        h.session.appDidBecomeActive()
        await h.session.pendingDeviceRegistration?.value
        #expect(h.count(rpc: "register_device") == 2, "1시간이 지나면 다시 보낸다")

        let token = String(repeating: "ab", count: 32)
        h.session.updateAPNsToken(token.uppercased())
        await h.session.pendingDeviceRegistration?.value
        #expect(h.count(rpc: "register_device") == 3, "새 APNs 토큰은 스로틀 없이 즉시")
        let withToken = try #require(h.requests.last { $0.rpcName == "register_device" })
        #expect(withToken.bodyText.contains(#""p_apns_token":"\#(token)""#), "토큰은 소문자로")
        #expect(withToken.bodyText.contains(#""p_apns_env":"sandbox""#))

        h.session.updateAPNsToken(token)
        await h.session.pendingDeviceRegistration?.value
        h.session.appDidBecomeActive()
        await h.session.pendingDeviceRegistration?.value
        #expect(h.count(rpc: "register_device") == 3, "같은 토큰·스로틀 안 포그라운드는 요청을 만들지 않는다")

        h.session.updateAPNsToken("not-hex")
        await h.session.pendingDeviceRegistration?.value
        #expect(h.session.apnsToken == nil, "형식이 틀린 토큰은 저장하지 않는다")
        #expect(MobileForbiddenCalls.violations(in: h.requests).isEmpty)
    }

    @Test("register_device 가 없는 서버(404)는 조용히 접고 스탬프를 찍지 않는다 — 다음 포그라운드가 다시 시도")
    func missingRegisterFunctionFoldsQuietly() async {
        let access = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(86_400))
        let h = makeHarness(seedAccess: access, responder: Self.happyServer(extra: { request in
            request.rpcName == "register_device" ? .missingFunction("register_device") : nil
        }))
        defer { h.tearDown() }
        await h.session.launch()
        await h.session.pendingDeviceRegistration?.value
        #expect(h.session.phase == .signedIn)
        #expect(h.storage.defaults.object(forKey: AingSharedKeys.deviceRegisteredAt) == nil)
        h.session.appDidBecomeActive()
        await h.session.pendingDeviceRegistration?.value
        #expect(h.count(rpc: "register_device") == 2)
    }

    @Test("치명 오류 분류는 맥과 같은 코어 규칙이다(취소·URLError·5xx·429 는 로그아웃 아님)")
    func authErrorRulesMatchMac() {
        #expect(AuthErrorRules.classify(CancellationError()) == .cancelled)
        #expect(AuthErrorRules.classify(URLError(.cancelled)) == .cancelled)
        #expect(AuthErrorRules.classify(URLError(.notConnectedToInternet)) == .transient)
        #expect(AuthErrorRules.classify(SupabaseWorkServiceError.invalidResponse(502)) == .transient)
        #expect(AuthErrorRules.classify(SupabaseWorkServiceError.rateLimited(retryAfterSeconds: nil)) == .transient)
        #expect(AuthErrorRules.classify(SupabaseWorkServiceError.sessionExpired) == .fatal)
        #expect(AuthErrorRules.message(for: SupabaseWorkServiceError.invalidLoginCredentials, fallback: "x") == "로그인 정보 오류")
    }
}
