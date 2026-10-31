import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// MARK: - 지금 탭 새 버전 안내 한 줄
//
// 보일 조건: `latestBuild != nil && latestBuild > 이 빌드 && 닫은 빌드 != latestBuild`.
// 값은 `client_release('ios')` 에서 실행 때 한 번 받고, 닫은 빌드는 `storage.defaults` 에 앱 단위로 남는다.
// 뷰는 `#if os(iOS)` 안이라 맥 스위트가 그리지 못한다 — 화면 쪽은 소스 계약으로만 잰다.
@MainActor
@Suite(.serialized) struct V1016UpdateNoticeTests {
    private static let thisBuild = 5

    private static func release(latest: Int) -> MobileStubResponse {
        .json(#"{"status":"ok","platform":"ios","min_build":1,"latest_build":\#(latest),"notes":null}"#)
    }

    /// 재실행은 같은 저장소·키체인으로 앱 모델을 새로 만드는 것이다.
    private final class Harness {
        let host = BaseStub.makeHost("update-notice")
        let storage: AingSharedStorage
        let vault = InMemoryTokenVault()
        let clock = BaseTestClock()
        let releaseResponse: BaseLockedBox<MobileStubResponse>

        init(release: MobileStubResponse, storage: AingSharedStorage = BaseStub.makeStorage()) {
            self.storage = storage
            let box = BaseLockedBox(release)
            releaseResponse = box
            let token = BaseStub.jwt(exp: clock.now.addingTimeInterval(3600), subject: "user-1")
            vault.write(token, key: AingKeychain.accessTokenKey)
            vault.write("refresh-1", key: AingKeychain.refreshTokenKey)
            storage.defaults.set("user-1", forKey: AingSharedKeys.userID)
            let signedIn = BaseStub.authResponse(access: token, refresh: "refresh-2", userID: "user-1")
            MobileStubURLProtocol.register(host: host) { request in
                switch request.rpcName {
                case "client_release": return box.get()
                case "register_device": return BaseStub.registerOK
                case "unregister_device": return .json(#"{"status":"ok","removed":true}"#)
                default: break
                }
                if request.path == "/rest/v1/memberships" { return BaseStub.membershipOK }
                if request.path == "/auth/v1/logout" { return .json("{}") }
                if request.path == "/auth/v1/token" { return signedIn }
                return .missingFunction(request.path)
            }
        }

        @MainActor
        func makeModel() -> MobileAppModel {
            var info = BaseStub.appInfo
            info.build = V1016UpdateNoticeTests.thisBuild
            let model = MobileAppModel(environment: MobileEnvironment(
                service: BaseStub.makeService(host: host),
                vault: vault,
                storage: storage,
                appInfo: info,
                clock: clock.clock,
                installationID: "11111111-2222-4333-8444-555555555555",
                realtimeTransport: nil,
                runsTimers: false,
                reloadWidgetTimelines: {}
            ))
            model.session.clientReleaseTimeoutSeconds = 0
            return model
        }

        /// 실행 복원까지 끝낸 앱 모델.
        @MainActor
        func launchedModel() async -> MobileAppModel {
            let model = makeModel()
            await model.session.launch()
            return model
        }

        var releaseRequestCount: Int {
            baseRequests(host: host).filter { $0.rpcName == "client_release" }.count
        }

        func tearDown() { BaseStub.tearDown(host: host, storage: storage) }
    }

    // MARK: 규칙

    @Test("규칙 표: nil·같음·낮음은 안 뜨고, 높으면 뜨고, 닫으면 내리고, 닫은 뒤 더 새 빌드면 다시 뜬다")
    func ruleTable() {
        let rows: [(latest: Int?, dismissed: Int?, visible: Bool, name: String)] = [
            (nil, nil, false, "최신 빌드를 모른다"),
            (nil, 9, false, "최신 빌드를 모르면 닫은 기록이 있어도 안 뜬다"),
            (5, nil, false, "같은 빌드"),
            (4, nil, false, "이 빌드가 더 높다(TestFlight 가 앞선 경우)"),
            (6, nil, true, "더 높다"),
            (6, 6, false, "그 빌드를 닫았다"),
            (7, 6, true, "닫은 뒤 더 새 빌드가 나왔다"),
            (6, 7, true, "닫은 값과 다르면 뜬다(서버가 값을 내린 경우)"),
            (5, 5, false, "같은 빌드는 닫은 기록과 무관하게 안 뜬다"),
        ]
        for row in rows {
            #expect(
                NowUpdateNoticeRule.isVisible(latestBuild: row.latest, currentBuild: Self.thisBuild, dismissedBuild: row.dismissed) == row.visible,
                "\(row.name)"
            )
        }
    }

    @Test("글자는 정해진 그대로다")
    func texts() {
        #expect(NowText.updateNoticeTitle == "새 버전이 나왔어요")
        #expect(NowText.updateNoticeAction == "업데이트")
        #expect(!NowText.updateNoticeDismiss.isEmpty)
    }

    // MARK: 값이 오는 길

    @Test("client_release 응답이 세션 latestBuild 를 거쳐 안내까지 온다")
    func releaseResponseReachesTheNotice() async {
        let h = Harness(release: Self.release(latest: 6))
        defer { h.tearDown() }
        let model = await h.launchedModel()
        #expect(model.session.phase == .signedIn)
        #expect(model.session.latestBuild == 6)
        #expect(model.now.showsUpdateNotice)
    }

    @Test("서버 값이 이 빌드와 같거나 낮으면, 또는 값이 없거나 함수가 없으면 안 뜬다")
    func noNoticeWithoutANewerBuild() async {
        let cases: [(MobileStubResponse, Int?, String)] = [
            (Self.release(latest: 5), 5, "같음"),
            (Self.release(latest: 4), 4, "낮음"),
            (.json(#"{"status":"ok","platform":"ios","min_build":1,"latest_build":null}"#), nil, "값 없음"),
            (.missingFunction("/rest/v1/rpc/client_release"), nil, "함수 없음"),
        ]
        for (response, latest, name) in cases {
            let h = Harness(release: response, storage: BaseStub.makeStorage(name))
            defer { h.tearDown() }
            let model = await h.launchedModel()
            #expect(model.session.phase == .signedIn, "\(name)")
            #expect(model.session.latestBuild == latest, "\(name)")
            #expect(!model.now.showsUpdateNotice, "\(name)")
        }
    }

    @Test("실행 때 한 번만 묻는다 — 포그라운드로 돌아와도 client_release 가 늘지 않는다")
    func foregroundDoesNotAskAgain() async {
        let h = Harness(release: Self.release(latest: 6))
        defer { h.tearDown() }
        let model = h.makeModel()
        model.start()
        #expect(await baseWaitUntil { model.session.phase == .signedIn })
        model.sceneDidBecomeActive()
        model.sceneDidEnterBackground()
        model.sceneDidBecomeActive()
        model.sceneDidEnterBackground()
        model.sceneDidBecomeActive()
        await baseBarrier(model.context.service)
        #expect(h.releaseRequestCount == 1)
        #expect(model.now.showsUpdateNotice)
    }

    @Test("상한을 넘긴 응답은 그 실행에 반영하지 않고, 다음 실행이 다시 받아 띄운다")
    func lateResponseWaitsForTheNextLaunch() async {
        let h = Harness(release: Self.release(latest: 6))
        defer { h.tearDown() }
        let hold = BaseHold.rpc("client_release", host: h.host)
        let model = h.makeModel()
        model.session.clientReleaseTimeoutSeconds = 0.3
        await model.session.launch()
        #expect(model.session.phase == .signedIn)
        #expect(hold.held == 1 && hold.delivered == 0, "응답을 기다린 뒤에야 복원했다")
        #expect(model.session.latestBuild == nil)
        #expect(!model.now.showsUpdateNotice)

        #expect(await hold.releaseAndWaitDelivered())
        await baseBarrier(model.context.service)
        #expect(model.session.latestBuild == nil, "상한을 넘겨 취소한 요청의 값이 들어왔다")
        #expect(!model.now.showsUpdateNotice)

        let next = await h.launchedModel()
        #expect(next.session.latestBuild == 6)
        #expect(next.now.showsUpdateNotice)
    }

    // MARK: 닫기

    @Test("닫으면 내려가고, 재실행해도 닫힌 채다 — 더 새 빌드가 나오면 다시 뜬다")
    func dismissSurvivesRelaunchUntilANewerBuild() async {
        let h = Harness(release: Self.release(latest: 6))
        defer { h.tearDown() }
        let first = await h.launchedModel()
        #expect(first.now.showsUpdateNotice)

        first.now.dismissUpdateNotice()
        #expect(!first.now.showsUpdateNotice)
        #expect(first.now.dismissedUpdateBuild == 6)
        #expect(h.storage.defaults.object(forKey: NowStore.dismissedUpdateBuildKey) as? Int == 6)

        let relaunched = await h.launchedModel()
        #expect(relaunched.session.latestBuild == 6)
        #expect(relaunched.now.dismissedUpdateBuild == 6)
        #expect(!relaunched.now.showsUpdateNotice, "재실행하니 닫은 안내가 다시 떴다")

        h.releaseResponse.mutate { $0 = Self.release(latest: 7) }
        let newer = await h.launchedModel()
        #expect(newer.session.latestBuild == 7)
        #expect(newer.now.showsUpdateNotice, "더 새 빌드인데 옛 닫기 기록이 가렸다")
    }

    @Test("로그아웃해도 닫기 기록은 남는다 — 다시 로그인해도, 재실행해도 닫힌 채다")
    func dismissSurvivesSignOut() async {
        let h = Harness(release: Self.release(latest: 6))
        defer { h.tearDown() }
        let model = await h.launchedModel()
        model.now.dismissUpdateNotice()

        await model.session.signOut()
        #expect(model.session.phase == .signedOut)
        #expect(model.now.dismissedUpdateBuild == 6, "로그아웃 사슬이 값을 비웠다")
        #expect(h.storage.defaults.object(forKey: NowStore.dismissedUpdateBuildKey) as? Int == 6, "로그아웃이 저장값을 지웠다")
        #expect(!AingSharedKeys.userScopedKeys.contains(NowStore.dismissedUpdateBuildKey))

        await model.session.signIn(email: "other@x.invalid", password: "pw")
        #expect(model.session.phase == .signedIn)
        #expect(model.session.latestBuild == 6, "최신 빌드는 실행 단위 값이라 로그아웃으로 사라지지 않는다")
        #expect(!model.now.showsUpdateNotice, "다시 로그인하니 닫은 안내가 다시 떴다")

        let relaunched = await h.launchedModel()
        #expect(relaunched.now.dismissedUpdateBuild == 6)
        #expect(!relaunched.now.showsUpdateNotice)
    }

    @Test("최신 빌드를 모르면 닫기는 아무것도 적지 않는다")
    func dismissWithoutAValueWritesNothing() async {
        let h = Harness(release: .missingFunction("/rest/v1/rpc/client_release"))
        defer { h.tearDown() }
        let model = await h.launchedModel()
        model.now.dismissUpdateNotice()
        #expect(model.now.dismissedUpdateBuild == nil)
        #expect(h.storage.defaults.object(forKey: NowStore.dismissedUpdateBuildKey) == nil)
    }

    // MARK: 데모

    @Test("데모 기본 픽스처의 latest_build 1 은 데모 빌드 1 에 안내를 띄우지 않는다")
    func demoFixtureShowsNoNotice() throws {
        let request = MobileStubRequest(method: "POST", host: "h", path: "/rest/v1/rpc/client_release", query: "", headers: [:], bodyText: "")
        let response = MobileDemoFixtures.load().response(for: request, scenario: "now")
        let object = try #require(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let latest = try #require(object["latest_build"] as? Int)
        #expect(latest == 1)
        #expect(!NowUpdateNoticeRule.isVisible(latestBuild: latest, currentBuild: 1, dismissedBuild: nil))
    }

    // MARK: 소스 계약

    /// `NowUpdateNoticeRow` 정의 본문. 주석을 걷은 코드라 바로 뒤 struct 머리에서 끊는다.
    private static func rowSource(_ tab: String) throws -> Substring {
        let start = try #require(tab.range(of: "struct NowUpdateNoticeRow"))
        let end = try #require(tab.range(of: "struct NowSectionHeader", range: start.upperBound..<tab.endIndex))
        return tab[start.lowerBound..<end.lowerBound]
    }

    @Test("NowTab 이 그 줄을 notice 띠 앞에 그린다")
    func tabDrawsTheRowFirst() throws {
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowTab.swift")
        let gate = try #require(tab.range(of: "if store.showsUpdateNotice"))
        let row = try #require(tab.range(of: "NowUpdateNoticeRow(store: store)"))
        let notice = try #require(tab.range(of: "if let notice = store.notice"))
        let status = try #require(tab.range(of: "NowStatusSection(store: store"))
        #expect(gate.lowerBound < row.lowerBound)
        #expect(row.lowerBound < notice.lowerBound, "안내 줄이 notice 띠 뒤로 갔다")
        #expect(notice.lowerBound < status.lowerBound)
    }

    @Test("줄의 약속: appStoreURL 을 열고 · 닫기를 부르고 · 채우지 않고 · 44pt · 요소를 합치지 않는다")
    func rowContract() throws {
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowTab.swift")
        let row = try Self.rowSource(tab)
        #expect(row.contains("openURL(MobileSessionText.appStoreURL)"), "[업데이트] 가 App Store 를 안 연다")
        #expect(row.contains("store.dismissUpdateNotice()"), "X 가 닫기를 안 부른다")
        #expect(row.contains("NowText.updateNoticeTitle"))
        #expect(row.contains("NowText.updateNoticeAction"))
        #expect(row.contains(".accessibilityLabel(Text(NowText.updateNoticeDismiss))"), "보이스오버가 X 를 이름 없이 읽는다")
        #expect(row.contains(".frame(width: 44, height: 44)"), "X 누름 영역이 44pt 가 아니다")
        #expect(row.contains(".buttonStyle(.plain)"), "X 가 행 전체 탭을 먹는다")
        #expect(row.contains("kind: .tinted"))
        #expect(!row.contains(".filled"), "채운 버튼은 화면당 하나다")
        #expect(!row.contains("accessibilityElement"), "요소를 합치면 보이스오버가 두 버튼에 따로 닿지 못한다")
        #expect(!row.contains(".onTapGesture"))
    }

    /// 16e(390pt) AX4 부터 · 375pt AX3 부터 잘렸다: 한 줄에 두면 고정된 [업데이트] 가 폭을 먼저 차지하고 남은 폭에 제목이 2줄로 갇힌다.
    @Test("큰 글자 약속: AX 갈래는 세로로 쌓고 · 그 갈래에선 버튼을 고정하지 않고 · 제목 줄 수를 가두지 않는다")
    func rowLargeTypeContract() throws {
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowTab.swift")
        let row = try Self.rowSource(tab)
        #expect(!row.contains(".lineLimit("), "제목 줄 수를 가두면 큰 글자에서 '새 버전이 나왔어요' 가 말줄임으로 잘린다")
        #expect(row.contains(".fixedSize(horizontal: false, vertical: true)"), "제목이 세로로 자라지 못한다")

        let branch = try #require(row.range(of: "if dynamicTypeSize.isAccessibilitySize"), "큰 글자 갈래가 없다")
        let otherwise = try #require(row.range(of: "} else {", range: branch.upperBound..<row.endIndex))
        let stacked = row[branch.upperBound..<otherwise.lowerBound]
        #expect(stacked.contains("VStack"), "큰 글자에서 [업데이트] 가 제목 옆에 남는다")
        #expect(stacked.contains("updateButton"), "큰 글자 갈래에 [업데이트] 가 없다")
        #expect(stacked.contains("dismissButton"), "큰 글자 갈래에 닫기가 없다")
        #expect(!stacked.contains(".fixedSize()"), "큰 글자 갈래에서 버튼 폭을 고정했다")

        // 고정은 작은 글자 갈래의 버튼 한 번뿐이다 — 공용 버튼 프로퍼티에 숨으면 큰 글자 갈래까지 번진다.
        #expect(row.components(separatedBy: ".fixedSize()").count - 1 == 1, "버튼 고정이 작은 글자 갈래 밖으로 나갔다")
        #expect(row[otherwise.upperBound...].contains("updateButton.fixedSize()"), "작은 글자 갈래의 버튼이 고정되지 않았다")
    }

    @Test("안내 값은 스토어 규칙 하나로 판정한다 — 뷰가 조건을 다시 적지 않는다")
    func viewDoesNotRestateTheRule() throws {
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowTab.swift")
        #expect(!tab.contains("latestBuild"))
        let store = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowStore.swift")
        #expect(store.contains("NowUpdateNoticeRule.isVisible("))
    }
}
