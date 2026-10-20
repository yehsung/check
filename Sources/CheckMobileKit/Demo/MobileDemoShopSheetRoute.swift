#if DEBUG
import Foundation

/// 데모 스크린샷 라우트 `me/shop/odds` · `me/shop/exchange` 를 **값으로 푼 것**(DEBUG 전용) — 상점의 뽑기 시트 둘.
///
/// ── 왜 이 파일이 필요한가 ──
/// 확률표 시트(`MeGachaOddsSheet`)와 조각 교환 시트(`MeGachaExchangeSheet`)는 **버튼을 눌러야** 열린다
/// (`MeShopView` 의 `showsGachaOdds` · `showsGachaExchange`). 그래서 라우트 하나로는 찍히지 않고, 지금까지는 깃발
/// `-AingCheckDemoMeGacha odds|exchange` 를 **라우트와 함께** 두 개 넘겨야 했다. 색 시안처럼 같은 화면을 모드마다 ·
/// 안마다 여러 장 찍을 때 깃발 두 벌을 손으로 맞추는 것이 틀리기 쉬워서(한쪽만 바꾸면 조용히 다른 화면이 찍힌다)
/// **라우트 글자 하나**로 같은 자리에 닿게 한 것이다. 깃발은 그대로 살아 있다(이 값은 깃발이 없을 때만 쓰인다).
///
/// ── 왜 `Demo/` 안이고 파일 통째가 `#if DEBUG` 인가 ──
/// Release 바이너리에서 **이름이 사라져야** 한다. 출시 게이트 `ios/scripts/check-release-app.sh` 의 금지 심볼
/// `MobileDemo` 가 타입 이름(nominal type descriptor)을 물면 아카이브가 막힌다(1.0.6 build 16 실측 —
/// `MobileDemoMissionsRoute` 머리말에 그 사고가 적혀 있다). 그래서 데모 기계는 전부 이 폴더 안 `#if DEBUG` 이다.
/// **`#if os(iOS)` 는 더하면 안 된다**: 그걸 더하는 순간 맥 스위트가 이 판정을 한 줄도 못 보게 된다
/// (저장소 메모 '폰 뷰는 맥 스위트가 못 본다' — 시트 자체는 이미 `#if os(iOS)` 안이라 맥이 못 그린다).
///
/// ── 왜 새 장면 폴더가 아니라 **기존 장면**인가 ──
/// 스텁은 라우트 글자의 `/` 를 `-` 로 바꾼 것을 장면 폴더 이름으로 쓴다(`MobileDemo.environment`). 라우트를 그대로 두면
/// 장면이 `me-shop-odds` 가 되어 **픽스처가 하나도 안 닿고**(전부 404) 빈 상점이 뜬다. 폴더를 새로 만드는 길도 막혀 있다 —
/// `IntegrationContractTests.demoFixtureScenesMatchRoutes` 가 "장면 폴더는 모두 실제 데모 라우트의 장면이다"를 단언한다.
/// 그래서 이 값은 ① 라우트를 **상점 라우트로 바꿔** 넘기고(그러면 장면이 `me-shop` 으로 제대로 풀린다)
/// ② 시트 이름만 따로 들고 있다가 `MeDemoHooks.gachaAction()` 에 내준다.
///
/// | 라우트                | openRoute | action     | 보이는 것                                     |
/// | --------------------- | --------- | ---------- | --------------------------------------------- |
/// | `me/shop/odds`        | me/shop   | odds       | 확률표 시트가 **열린 채**(여덟 줄 · 합 100%)   |
/// | `me/shop/exchange`    | me/shop   | exchange   | 조각 교환 시트가 **열린 채**(조각 23개)        |
/// | `me/shop/<모르는 꼬리>`| me/shop   | nil        | 상점 화면(시트 없이) — 라우트를 조용히 버리지 않는다 |
///
/// 실행:
/// ```
/// xcrun simctl launch <기기> com.yehsung.aingcheck -AingCheckDemo YES -AingCheckDemoRoute me/shop/odds
/// ```
package struct MobileDemoShopSheetRoute: Hashable, Sendable {
    /// 이 라우트들이 **실제로 여는** 라우트(`AingRoute(path:)` 가 아는 글자 — `me/shop/odds` 는 nil 이다).
    package static let openRoute = "me/shop"

    /// 열어 둘 시트(`MeDemoHooks.gachaAction()` 이 아는 글자). 모르는 꼬리면 nil — 상점만 선다.
    package var action: String?

    package init(action: String?) {
        self.action = action
    }

    package var openRoute: String { Self.openRoute }

    /// 데모 라우트 글자 → 값. 상점 시트 라우트가 아니면 nil(그러면 데모는 평소대로 라우트에서 장면을 뽑는다).
    /// `me/shop` 자체는 **가로채지 않는다** — 그 라우트는 이미 돌고 있고, 가로채면 시트 없는 상점이 두 길로 열린다.
    package init?(demoRoute raw: String) {
        let path = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard path.hasPrefix("me/shop/") else { return nil }
        switch path.split(separator: "/").dropFirst(2).first.map(String.init) {
        case "odds": self.init(action: "odds")
        case "exchange": self.init(action: "exchange")
        default: self.init(action: nil)
        }
    }
}
#endif
