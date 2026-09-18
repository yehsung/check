import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 화면 모드(나 → 설정): 기본값 · 저장 · 복원 · 모르는 저장값 · 알림 · 로그아웃 뒤 유지 · 서버 요청 0 · 데모 시작값.
@MainActor
@Suite("나 탭 화면 모드(w9)")
struct MeAppearanceTests {
    /// 테스트마다 따로 쓰는 suite(병렬 테스트끼리 섞이지 않게). 끝나면 지운다.
    final class ScratchDefaults {
        let name = "com.yehsung.aingcheck.scratch.appearance-\(UUID().uuidString.lowercased().prefix(12))"
        let defaults: UserDefaults

        init() {
            defaults = UserDefaults(suiteName: name)!
        }

        deinit {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
    }

    /// 기본은 **다크**다(사용자 결정 2026-09-18) — 앱의 그림이 어두운 바탕을 전제로 만들어졌다.
    @Test("기본값: 저장값이 없으면 다크")
    func defaultsToDark() {
        let scratch = ScratchDefaults()
        let store = MobileAppearanceStore(defaults: scratch.defaults)
        #expect(store.mode == .dark)
        #expect(scratch.defaults.object(forKey: MobileAppearanceStore.defaultsKey) == nil, "읽기만 했는데 값을 썼다")
    }

    @Test("저장 · 복원: 고르는 즉시 저장되고 새 저장소(재실행)가 같은 값을 읽는다 — 세 값 모두")
    func persistsAndRestores() {
        let scratch = ScratchDefaults()
        let store = MobileAppearanceStore(defaults: scratch.defaults)
        for mode in [MobileAppearanceMode.dark, .light, .system, .dark] {
            store.select(mode)
            #expect(store.mode == mode)
            #expect(scratch.defaults.string(forKey: MobileAppearanceStore.defaultsKey) == mode.rawValue)
            #expect(MobileAppearanceStore(defaults: scratch.defaults).mode == mode, "재실행 복원이 \(mode) 가 아니다")
        }
    }

    @Test("모르는 저장값(다음 버전 값 · 대소문자 다름 · 빈 문자열 · 숫자 · 불린)은 기본(다크)으로 읽고, 고르기 전에는 지우지 않는다")
    func unknownStoredValueFallsBackToDefault() {
        let scratch = ScratchDefaults()
        let key = MobileAppearanceStore.defaultsKey
        let unknowns: [Any] = ["sepia", "Dark", "", 2, true]
        for value in unknowns {
            scratch.defaults.set(value, forKey: key)
            #expect(MobileAppearanceStore(defaults: scratch.defaults).mode == .dark, "\(value) 를 기본(다크)으로 접지 않았다")
        }
        #expect(MobileAppearanceMode(storedValue: nil) == .dark)
        #expect(MobileAppearanceMode(storedValue: "light") == .light)

        scratch.defaults.set("sepia", forKey: key)
        let store = MobileAppearanceStore(defaults: scratch.defaults)
        #expect(scratch.defaults.string(forKey: key) == "sepia", "읽기만 했는데 모르는 값을 지웠다")
        // 사용자가 지금 값(시스템)을 다시 골라도 저장은 알려진 값으로 덮인다.
        store.select(.system)
        #expect(scratch.defaults.string(forKey: key) == "system")
    }

    @Test("알림: 값이 바뀔 때만 한 번씩 부른다(같은 값을 다시 고르면 부르지 않는다)")
    func notifiesOnlyOnChange() {
        let scratch = ScratchDefaults()
        let store = MobileAppearanceStore(defaults: scratch.defaults)
        var received: [MobileAppearanceMode] = []
        store.onChange = { received.append($0) }
        // 시작값이 다크이므로 첫 .dark 는 알림이 없다 — '바뀔 때만' 이 그 뜻이다.
        store.select(.dark)
        store.select(.system)
        store.select(.system)
        store.select(.light)
        store.select(.dark)
        #expect(received == [.system, .light, .dark])
    }

    @Test("문구: 세 칸 제목이 서로 다르고 비지 않았다 · 위젯 안내가 칸 아래에 있다")
    func texts() {
        let titles = MobileAppearanceMode.allCases.map(MeText.appearanceTitle)
        #expect(titles == ["다크", "라이트", "시스템 설정 따르기"])
        #expect(Set(MobileAppearanceMode.allCases.map(MeText.appearanceSymbol)).count == 3)
        #expect(MeText.appearanceWidgetNote.contains("위젯"))
        #expect(MobileAppearanceMode.allCases == [.dark, .light, .system], "기본(다크)이 맨 위가 아니다")
    }

    @Test("나 탭: 고르면 앱 모델의 화면 모드가 바뀌고 서버 요청은 0 · 로그아웃(세대 · reset) 뒤에도 남고 · 같은 저장소로 다시 만든 앱이 복원한다")
    func survivesSignOutWithoutServerCalls() async throws {
        let harness = await RankMeHarness(label: "me-appearance") { request in
            if request.rpcName == "unregister_device" { return .json(#"{"status":"ok","removed":true}"#) }
            if request.path == "/auth/v1/logout" { return .json("{}") }
            return nil
        }
        defer { harness.tearDown() }
        let model = harness.model
        let me = harness.me
        #expect(me.appearanceMode == .dark)
        #expect(model.appearance === model.context.appearance)

        await harness.barrier()
        let before = harness.requests.count
        me.selectAppearance(.dark)
        await harness.barrier()
        #expect(me.appearanceMode == .dark && model.appearance.mode == .dark)
        // 실행 복원이 뒤늦게 낸 세션 요청(기기 등록 · 멤버십)만 허용한다.
        let sessionRPCs: Set<String> = ["client_release", "register_device"]
        let after = harness.requests.dropFirst(before).filter { !sessionRPCs.contains($0.rpcName ?? "") && $0.path != "/rest/v1/memberships" }
        #expect(after.isEmpty, "화면 모드가 서버로 나갔다: \(after.map(\.path))")

        let generation = model.session.generation
        await me.signOut()
        #expect(!model.session.isSignedIn)
        #expect(model.session.generation != generation)
        #expect(me.appearanceMode == .dark, "로그아웃이 화면 모드를 되돌렸다")
        // 테스트 환경은 appearanceDefaults 를 주지 않아 공용 suite(로그아웃이 사용자 키를 지우는 곳)에 둔다 — 그래도 남아야 한다.
        #expect(harness.storage.defaults.string(forKey: MobileAppearanceStore.defaultsKey) == "dark")

        let relaunched = MobileAppModel(environment: MobileEnvironment(
            service: BaseStub.makeService(host: harness.host),
            vault: InMemoryTokenVault(),
            storage: harness.storage,
            appInfo: BaseStub.appInfo,
            clock: harness.clock.clock,
            installationID: "11111111-2222-4333-8444-555555555555",
            realtimeTransport: nil,
            runsTimers: false,
            reloadWidgetTimelines: {}
        ))
        #expect(relaunched.appearance.mode == .dark, "재실행(로그아웃 상태)이 화면 모드를 복원하지 못했다")
        #expect(relaunched.me.appearanceMode == .dark)
        harness.expectNoForbiddenCalls()
    }

    @Test("저장 위치: 환경이 준 appearanceDefaults(프로덕션 = 앱 자신의 .standard)에만 쓰고 공용 suite 에는 쓰지 않는다")
    func writesOnlyToInjectedDefaults() {
        let scratch = ScratchDefaults()
        let storage = BaseStub.makeStorage()
        defer { BaseStub.tearDown(host: "appearance-unused.invalid", storage: storage) }
        let model = MobileAppModel(environment: MobileEnvironment(
            service: BaseStub.makeService(host: "appearance-unused.invalid"),
            vault: InMemoryTokenVault(),
            storage: storage,
            appInfo: BaseStub.appInfo,
            clock: BaseTestClock(MobileClock.demoInstant).clock,
            installationID: "11111111-2222-4333-8444-555555555555",
            realtimeTransport: nil,
            runsTimers: false,
            reloadWidgetTimelines: {},
            appearanceDefaults: scratch.defaults
        ))
        model.me.selectAppearance(.light)
        #expect(scratch.defaults.string(forKey: MobileAppearanceStore.defaultsKey) == "light")
        #expect(storage.defaults.object(forKey: MobileAppearanceStore.defaultsKey) == nil, "위젯과 나누는 공용 suite 에 썼다")
    }

    @Test("데모 시작값: -AingCheckDemoAppearance 가 있으면 그 값, 없으면 지난 실행 값을 지워 기본(다크)")
    func demoSeed() {
        let scratch = ScratchDefaults()
        MobileDemo.seedAppearance(arguments: ["app", "-AingCheckDemo", "YES", "-AingCheckDemoAppearance", "DARK"], into: scratch.defaults)
        #expect(MobileAppearanceStore(defaults: scratch.defaults).mode == .dark)
        MobileDemo.seedAppearance(arguments: ["app", "-AingCheckDemo", "YES"], into: scratch.defaults)
        #expect(MobileAppearanceStore(defaults: scratch.defaults).mode == .dark, "인자가 없으면 지난 실행 값을 지우고 기본으로 돌아간다")
        MobileDemo.seedAppearance(arguments: ["app", "-AingCheckDemoAppearance", "light"], into: scratch.defaults)
        #expect(MobileAppearanceStore(defaults: scratch.defaults).mode == .light)
    }

    @Test("실제 앱 조립은 화면 모드를 앱 자신의 UserDefaults.standard 에 둔다 — 공용 suite(로그아웃이 치우는 곳)가 아니다")
    func liveEnvironmentStoresAppearanceInStandardDefaults() throws {
        // live() 는 키체인 · App Group 을 만져 테스트에서 부르기 어렵다 — 조립 줄을 소스 계약으로 묶는다(w9 검증 발견).
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let raw = try String(contentsOf: root.appendingPathComponent("Sources/CheckMobileKit/App/MobileEnvironment.swift"), encoding: .utf8)
        let code = stripComments(raw).filter { !$0.isWhitespace }
        let live = try #require(code.range(of: "packagestaticfunclive("), "live() 조립을 못 찾았다")
        #expect(code[live.lowerBound...].contains("appearanceDefaults:.standard"), "실제 앱이 화면 모드를 .standard 에 두지 않는다")
    }
}
