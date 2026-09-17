import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 앱 모델 수명(로그인·scenePhase·로그아웃 reset) · 데모 조립(라우트·장면·픽스처 규칙) · 금지 호출 판정.
@MainActor
@Suite(.serialized) struct BaseAppModelTests {
    // MARK: - 데모

    @Test("데모 실행 인자: -AingCheckDemo YES 일 때만, 라우트 기본은 now")
    func demoLaunchArguments() {
        #expect(MobileDemo.launchRoute(arguments: ["app"]) == nil)
        #expect(MobileDemo.launchRoute(arguments: ["app", "-AingCheckDemo", "NO"]) == nil)
        #expect(MobileDemo.launchRoute(arguments: ["app", "-AingCheckDemo", "YES"]) == "now")
        #expect(MobileDemo.launchRoute(arguments: ["app", "-AingCheckDemo", "YES", "-AingCheckDemoRoute", "games/gomoku/match"]) == "games/gomoku/match")
        #expect(JWTClaims.expiry(accessToken: MobileDemo.accessToken) == Date(timeIntervalSince1970: 4_102_444_800))
    }

    @Test("픽스처: 전부 JSON 으로 읽히고, 같은 장면·키·바늘의 중복이 없다")
    func fixturesAreValidAndUnique() throws {
        let fixtures = MobileDemoFixtures.load()
        #expect(fixtures.entries.count >= 8)
        #expect(fixtures.duplicateKeys.isEmpty, "\(fixtures.duplicateKeys)")
        for entry in fixtures.entries {
            #expect((try? JSONSerialization.jsonObject(with: entry.data, options: [.fragmentsAllowed])) != nil, "\(entry.relativePath) 가 JSON 이 아니다")
        }
    }

    @Test("픽스처 키 규칙과 선택 순서(장면 > 바늘 > 기본), 없는 키는 404 PGRST202, 금지 호출은 403")
    func fixtureSelection() throws {
        func request(_ method: String, _ path: String, query: String = "", body: String = "") -> MobileStubRequest {
            MobileStubRequest(method: method, host: "h", path: path, query: query, headers: [:], bodyText: body)
        }
        #expect(MobileDemoFixtures.key(for: request("POST", "/rest/v1/rpc/client_release")) == "rpc.client_release")
        #expect(MobileDemoFixtures.key(for: request("GET", "/rest/v1/memberships")) == "rest.memberships.get")
        #expect(MobileDemoFixtures.key(for: request("POST", "/auth/v1/token", query: "grant_type=password")) == "auth.token.post")
        #expect(MobileDemoFixtures.key(for: request("POST", "/storage/v1/object/avatars/u.jpg")) == "storage.post")

        let fixtures = MobileDemoFixtures(entries: [
            .init(key: "rpc.x", needle: nil, scenario: nil, relativePath: "a/rpc.x.json", data: Data("1".utf8)),
            .init(key: "rpc.x", needle: "peer-9", scenario: nil, relativePath: "a/rpc.x@peer-9.json", data: Data("2".utf8)),
            .init(key: "rpc.x", needle: nil, scenario: "update", relativePath: "a/_update/rpc.x.json", data: Data("3".utf8)),
            .init(key: "rpc.e", needle: nil, scenario: nil, relativePath: "a/rpc.e.json", data: Data(#"{"__status":409,"__body":{"status":"busy"}}"#.utf8)),
        ])
        let plain = request("POST", "/rest/v1/rpc/x", body: #"{"p_peer":"peer-1"}"#)
        let needle = request("POST", "/rest/v1/rpc/x", body: #"{"p_peer":"peer-9"}"#)
        #expect(fixtures.response(for: plain, scenario: "now").body == Data("1".utf8))
        #expect(fixtures.response(for: needle, scenario: "now").body == Data("2".utf8))
        #expect(fixtures.response(for: needle, scenario: "update").body == Data("3".utf8))
        let envelope = fixtures.response(for: request("POST", "/rest/v1/rpc/e"), scenario: nil)
        #expect(envelope.status == 409)
        #expect(String(decoding: envelope.body, as: UTF8.self).contains("busy"))
        #expect(fixtures.response(for: request("POST", "/rest/v1/rpc/nope"), scenario: nil).status == 404)
        #expect(fixtures.response(for: request("POST", "/rest/v1/rpc/take_pokes"), scenario: nil).status == 403)
    }

    @Test("데모 조립: now → 로그인 상태로 시작해 라우트를 연다 · login → 로그아웃 · update → 업데이트 화면 · 금지 호출 0")
    func demoEnvironments() async throws {
        for (route, expected) in [("rankings/tokens", MobileSessionPhase.signedIn), ("login", .signedOut), ("update", .needsUpdate(minBuild: 99))] {
            MobileStubURLProtocol.clearRequests(host: MobileDemo.host)
            let environment = try #require(MobileDemo.environment(arguments: ["app", "-AingCheckDemo", "YES", "-AingCheckDemoRoute", route]))
            #expect(environment.isDemo)
            #expect(environment.clock.now() == MobileClock.demoInstant)
            let model = MobileAppModel(environment: environment)
            model.session.clientReleaseTimeoutSeconds = 0   // 벽시계 상한 없음(update 장면은 client_release 답에 달렸다)
            model.start()
            #expect(await baseWaitUntil { model.session.phase == expected }, "\(route): \(model.session.phase)")
            if route == "rankings/tokens" {
                #expect(await baseWaitUntil { model.router.selectedTab == .rankings })
                #expect(model.router.consumePendingRoute(for: .rankings) == .rankings(.tokens))
                #expect(await baseWaitUntil { model.session.profile?.teamName == "아잉 데모팀" })
            }
            await model.session.pendingDeviceRegistration?.value
            await baseBarrier(model.context.service)
            #expect(MobileForbiddenCalls.violations(in: MobileStubURLProtocol.requests(host: MobileDemo.host)).isEmpty)
        }
        BaseStub.tearDown(host: MobileDemo.host, storage: .temporary(name: "demo"))
    }

    // MARK: - 수명

    @Test("scenePhase·로그인·로그아웃 수명: active 에서 로그인되면 실시간이 깨어나고, 로그아웃은 라우터·오목·루비·스냅샷 기억을 비운다")
    func lifecycleWiring() async {
        let host = BaseStub.makeHost("model")
        let fresh = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600))
        MobileStubURLProtocol.register(host: host) { request in
            switch request.rpcName {
            case "client_release": return BaseStub.releaseOK
            case "register_device": return BaseStub.registerOK
            case "unregister_device": return .json(#"{"status":"ok","removed":true}"#)
            default: break
            }
            if request.path == "/auth/v1/token" { return BaseStub.authResponse(access: fresh, refresh: "r", userID: "u-model") }
            if request.path == "/auth/v1/logout" { return .json("{}") }
            if request.path == "/rest/v1/memberships" { return BaseStub.membershipOK }
            return .missingFunction(request.path)
        }
        let storage = BaseStub.makeStorage()
        defer { BaseStub.tearDown(host: host, storage: storage) }
        let transport = BaseFakeTransport()
        let environment = MobileEnvironment(
            service: BaseStub.makeService(host: host),
            vault: InMemoryTokenVault(),
            storage: storage,
            appInfo: BaseStub.appInfo,
            clock: BaseTestClock().clock,
            installationID: "11111111-2222-4333-8444-555555555555",
            realtimeTransport: transport,
            runsTimers: false,
            reloadWidgetTimelines: {}
        )
        let model = MobileAppModel(environment: environment)
        #expect(model.links.now === model.now && model.links.push === model.push, "링크가 채워지지 않았다")
        #expect(model.gomoku.host === model.gomokuHost)
        model.session.clientReleaseTimeoutSeconds = 0   // 벽시계 상한 없음
        model.start()
        #expect(await baseWaitUntil { model.session.phase == .signedOut })

        model.sceneDidBecomeActive()
        #expect(transport.connects.isEmpty, "로그아웃 상태에서 소켓을 열었다")

        await model.session.signIn(email: "a@b.c", password: "pw")
        #expect(model.session.phase == .signedIn)
        #expect(transport.connects.count == 1, "active 인 채로 로그인되면 바로 붙어야 한다")

        model.router.open(.settings)
        model.gomokuHost.rubyBalance = 12
        model.widgetSnapshots.update { $0.working = [.init(name: "민트", center: nil, teammate: true, startedAt: nil)] }
        #expect(model.handleOpenURL(URL(string: "aingcheck://message/p1")!))

        await model.session.signOut()
        #expect(model.router.selectedTab == .now)
        #expect(model.gomokuHost.rubyBalance == nil)
        #expect(model.widgetSnapshots.current == nil)
        #expect(model.realtime.state == .idle(.signedOut))
        #expect(!model.handleOpenURL(URL(string: "aingcheck://message/p1")!), "로그아웃 상태에서 링크를 열었다")

        model.sceneDidEnterBackground()
        #expect(!model.isSceneActive)
        #expect(MobileForbiddenCalls.violations(in: MobileStubURLProtocol.requests(host: host)).isEmpty)
    }

    // MARK: - 금지 호출 판정

    @Test("금지 호출 판정: 양성(take_pokes·work_tick·기기 상태 쓰기·app_build PATCH)과 음성(읽기·허용 쓰기)")
    func forbiddenCallClassification() {
        func request(_ method: String, _ path: String, body: String = "") -> MobileStubRequest {
            MobileStubRequest(method: method, host: "h", path: path, query: "", headers: [:], bodyText: body)
        }
        let positives = [
            request("POST", "/rest/v1/rpc/take_pokes"), request("POST", "/rest/v1/rpc/work_tick"),
            request("POST", "/rest/v1/rpc/close_abandoned_work_sessions"), request("POST", "/rest/v1/rpc/ultra_wallet_sync"),
            request("POST", "/rest/v1/rpc/buy_ultra"), request("POST", "/rest/v1/work_statuses"),
            request("PATCH", "/rest/v1/work_sessions"), request("POST", "/rest/v1/work_status_devices"),
            request("POST", "/rest/v1/token_usage_device_daily"),
            request("PATCH", "/rest/v1/profiles", body: #"{"app_build":1,"app_version":"0.1.0"}"#),
            request("PATCH", "/rest/v1/profiles", body: #"{"focus_mode":true}"#),
        ]
        for positive in positives {
            #expect(MobileForbiddenCalls.violation(positive) != nil, "\(positive.method) \(positive.path) 를 놓쳤다")
        }
        let negatives = [
            request("POST", "/rest/v1/rpc/message_history_with_reads"), request("POST", "/rest/v1/rpc/register_device", body: #"{"p_app_build":1}"#),
            request("GET", "/rest/v1/work_sessions"), request("GET", "/rest/v1/work_statuses"),
            request("PATCH", "/rest/v1/profiles", body: #"{"token_usage_public":true}"#),
            request("POST", "/rest/v1/rpc/set_team_weekly_goal"), request("POST", "/auth/v1/logout"),
        ]
        for negative in negatives {
            #expect(MobileForbiddenCalls.violation(negative) == nil, "\(negative.method) \(negative.path) 를 금지로 잘못 봤다")
        }
    }
}
