#if DEBUG
import Foundation

/// 데모 스크린샷 라우트 `me/gift…` 한 건을 **값으로 푼 것**(DEBUG 전용) — 생일 선물 축하 시트(폰 1.0.14).
///
/// ── 왜 이 모양인가 ──
/// 심사용 데모의 기본 응답은 **선물 없음**이다(`Demo/Fixtures/me/rpc.character_gift_pending.json` — 심사원 화면에 축하 시트가 뜨지 않게).
/// 축하 시트를 찍으려면 선물이 있는 응답이 필요한데, `character_gift_pending` 본문은 `{"p_protocol":4}` 뿐이라 변형을 고를 바늘이 없고,
/// 장면 폴더(`_me-gift`)는 `IntegrationContractTests.demoFixtureScenesMatchRoutes` 가 막는다(오타 장면을 잡는 그물 — 맞는 단언이다).
/// 그래서 `MobileDemoMissionsRoute` 와 **같은 길**로 푼다: 기존 장면(`me`) + 요청 본문 꼬리에 바늘(`demo-gift`)을 붙여
/// `rpc.character_gift_pending@demo-gift.json`(열린 선물 — 딸기 · 초코)을 고르게 하고, 앱에는 나 탭(`me`)을 연다.
/// 파일 통째가 `#if DEBUG` 인 까닭(Release 바이너리에서 이름이 사라져야 한다)은 `MobileDemoMissionsRoute` 머리말과 같다.
///
/// | 라우트              | 보이는 것                                                        |
/// | ------------------- | ---------------------------------------------------------------- |
/// | `me/gift`           | 나 탭 위에 축하 시트 — 두 초상, 아직 안 고름(확인 단추 꺼짐)      |
/// | `me/gift/picked`    | 같은 시트 — 첫 선택지(딸기)를 골라 둠(확인 단추 켜짐)            |
/// | `me/gift/received`  | 골라서 받은 뒤 — "딸기 케이크 아잉이를 받았어요!" + [지금 입기] [닫기] |
/// | `me/gift/dismissed` | 시트를 띄우지 않고 닫은 것으로 — 나 탭 '다시 열기' 줄             |
///
/// 실행:
/// ```
/// xcrun simctl launch <기기> com.yehsung.aingcheck -AingCheckDemo YES -AingCheckDemoRoute me/gift/received
/// ```
package struct MobileDemoCakeGiftRoute: Hashable, Sendable {
    /// 실제로 여는 탭 라우트(`AingRoute(path:)` 가 아는 글자).
    package static let openRoute = "me"
    /// 스텁이 고를 장면 폴더 이름(기존 장면만 — 위 머리말).
    package static let scene = "me"
    /// 픽스처 변형 바늘(`rpc.character_gift_pending@demo-gift.json`).
    package static let needle = "demo-gift"

    /// 시트에 시킬 일(`picked` · `received` · `dismissed`). nil 이면 띄우기만.
    package var action: String?

    package init(action: String? = nil) {
        self.action = action
    }

    package var openRoute: String { Self.openRoute }
    package var scene: String { Self.scene }

    /// 데모 라우트 글자 → 값. 선물 라우트가 아니면 nil. 모르는 꼬리는 띄우기만(라우트를 조용히 버리지 않는다).
    package init?(demoRoute raw: String) {
        let path = raw.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard path == "me/gift" || path.hasPrefix("me/gift/") else { return nil }
        let tail = path.split(separator: "/").dropFirst(2).first.map(String.init)
        switch tail {
        case "picked", "received", "dismissed":
            self.init(action: tail)
        default:
            self.init(action: nil)
        }
    }

    /// 바늘을 요청 본문 꼬리에 붙인 사본(`MobileDemoMissionsRoute.rewrite` 와 같다 — 기록은 원본으로 남는다).
    package func rewrite(_ request: MobileStubRequest) -> MobileStubRequest {
        MobileStubRequest(
            method: request.method,
            host: request.host,
            path: request.path,
            query: request.query,
            headers: request.headers,
            bodyText: request.bodyText + " __demoFixture=" + Self.needle
        )
    }
}
#endif
