import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 데모 스크린샷 라우트 `me/shop/odds` · `me/shop/exchange`(폰 1.0.10 무지개 색 시안) 의 계약.
//
// 시트 둘(확률표 · 조각 교환)은 **버튼을 눌러야** 열리는 폰 뷰라 맥 스위트가 한 줄도 못 그린다
// (저장소 메모 '폰 뷰는 맥 스위트가 못 본다'). 그래서 여기서는 **라우트가 무엇으로 풀리는가**와
// **그 값이 실제로 배선돼 있는가**를 글자로 못 박는다 — 배선이 빠지면 라우트는 조용히 시트 없는 상점을 찍는다
// (스크린샷을 찍은 사람은 그것이 틀린 화면인 줄 모른다).
@Suite struct MeDemoShopSheetRouteTests {

    // MARK: - 라우트 → 값

    @Test("라우트 둘이 상점 라우트 + 시트 이름으로 풀린다 · 모르는 꼬리는 시트 없이 상점 · 남의 라우트는 가로채지 않는다")
    func theRouteResolves() {
        #expect(MobileDemoShopSheetRoute(demoRoute: "me/shop/odds")?.action == "odds")
        #expect(MobileDemoShopSheetRoute(demoRoute: "me/shop/exchange")?.action == "exchange")
        // 여는 라우트는 늘 상점이다 — `AingRoute` 는 `me/shop/odds` 를 모른다(그대로 넘기면 기본 탭에 머문다).
        #expect(AingRoute(path: "me/shop/odds") == nil, "라우트가 생겼다 — 이 값의 바꿔치기가 필요 없어졌는지 다시 보라")
        #expect(MobileDemoShopSheetRoute(demoRoute: "me/shop/odds")?.openRoute == "me/shop")
        #expect(AingRoute(path: "me/shop") == .shop)
        // 공백 · 대문자 · 끝 `/` 도 같게 읽는다. 모르는 꼬리는 라우트를 버리지 않고 상점만 세운다(시트 없음).
        #expect(MobileDemoShopSheetRoute(demoRoute: " /ME/Shop/Odds/ ")?.action == "odds")
        #expect(MobileDemoShopSheetRoute(demoRoute: "me/shop/nope") == MobileDemoShopSheetRoute(action: nil))
        // 남의 데모 라우트는 가로채지 않는다 — 특히 `me/shop` 자체(이미 도는 장면)는 nil 이어야 한다.
        for raw in ["me/shop", "me/shop/", "me", "me/", "me/settings", "me/missions", "now", "games"] {
            #expect(MobileDemoShopSheetRoute(demoRoute: raw) == nil, "남의 데모 라우트를 상점 시트로 읽었다: \(raw)")
        }
    }

    @Test("두 라우트의 장면은 기존 `_me-shop` 이다 — 상점 첫 화면 픽스처에 닿는다(안 닿으면 빈 상점이 찍힌다)")
    func theSceneIsTheExistingShopScene() {
        let fixtures = MobileDemoFixtures.load()
        let scene = MobileDemoShopSheetRoute.openRoute.replacingOccurrences(of: "/", with: "-")
        #expect(scene == "me-shop")
        let request = MobileStubRequest(method: "POST", host: MobileDemo.host, path: "/rest/v1/rpc/shop_state",
                                        query: "", headers: [:], bodyText: "{}")
        let entry = fixtures.entry(for: request, scenario: scene)
        #expect(entry?.relativePath == "me/_me-shop/rpc.shop_state.json", "장면 \(scene) 에서 상점 픽스처에 못 닿는다")
    }

    // MARK: - 배선(소스 계약)

    /// 값과 배선이 **전부 `#if DEBUG` 안**이다 — Release 바이너리에 `MobileDemoShopSheetRoute` 라는 이름이 남으면
    /// 출시 게이트 `ios/scripts/check-release-app.sh` 의 금지 심볼 `MobileDemo` 가 물어 아카이브가 막힌다
    /// (1.0.6 build 16 에서 실제로 막혔다 — `MobileDemoMissionsRoute` 머리말).
    @Test("값 파일은 #if DEBUG 로 시작하고 끝난다 · 플랫폼 분기가 없다 · 쓰는 자리가 셋뿐이고 모두 DEBUG 안이다")
    func theValueAndItsWiringAreDebugOnly() throws {
        let path = "Sources/CheckMobileKit/Demo/MobileDemoShopSheetRoute.swift"
        let source = try MeAchievementsFixtureContractTests.strippedSource(path)
        let lines = source.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        #expect(lines.first == "#if DEBUG", "\(path): 파일이 #if DEBUG 로 시작하지 않는다")
        #expect(lines.last == "#endif", "\(path): 파일이 #endif 로 끝나지 않는다")
        #expect(!source.contains("#if os("), "\(path): 플랫폼 분기가 들어왔다 — 맥 스위트가 데모 판정을 못 본다")
        #expect(source.contains("package struct MobileDemoShopSheetRoute"), "값 타입이 그 파일에 없다 — 경로가 틀렸다")

        // 쓰는 자리는 **정확히 셋**: 값 자신 · 데모 조립(라우트 바꿔치기) · 시트를 여는 깃발 자리(`MeDemoHooks`).
        // 네 번째가 생기면 그 자리가 `#if DEBUG` 안인지 사람이 봐야 한다.
        let users = try MeAchievementsFixtureContractTests.files(containing: "MobileDemoShopSheetRoute", under: "Sources")
        #expect(users == ["Sources/CheckMobileKit/Demo/MobileDemo.swift",
                          "Sources/CheckMobileKit/Demo/MobileDemoShopSheetRoute.swift",
                          "Sources/CheckMobileKit/Me/MeTab.swift"],
                "상점 시트 값을 다른 곳에서도 쓴다(Release 에 이름이 남을 수 있다): \(users)")

        // 배선 두 줄이 실제로 있는가 — 없으면 라우트는 **아무것도 안 하는 값**이고 시트 없는 상점이 찍힌다.
        let demo = try MeAchievementsFixtureContractTests.strippedSource("Sources/CheckMobileKit/Demo/MobileDemo.swift")
        #expect(demo.contains("MobileDemoShopSheetRoute(demoRoute: requested)?.openRoute ?? requested"),
                "데모 조립이 상점 시트 라우트를 상점으로 바꾸지 않는다 — 장면이 me-shop-odds 가 되어 픽스처가 전부 404 다")
        let tab = try MeAchievementsFixtureContractTests.strippedSource("Sources/CheckMobileKit/Me/MeTab.swift")
        #expect(tab.contains("MobileDemoShopSheetRoute(demoRoute: $0)?.action"),
                "MeDemoHooks.gachaAction() 이 라우트를 안 읽는다 — 시트가 안 열린다")
        // 깃발이 이긴다(라우트와 깃발을 같이 주면 깃발). 그 순서가 뒤집히면 기존 스크린샷 명령이 조용히 다른 화면을 찍는다.
        let flagFirst = tab.range(of: "argument(\"-AingCheckDemoMeGacha\")")
        let routeSecond = tab.range(of: "MobileDemoShopSheetRoute(demoRoute: $0)?.action")
        #expect(flagFirst != nil && routeSecond != nil && flagFirst!.lowerBound < routeSecond!.lowerBound,
                "깃발보다 라우트를 먼저 읽는다 — 깃발이 이겨야 한다")
    }
}
