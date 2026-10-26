#if DEBUG
import CheckCore
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
/// ── 선물 장면의 계정은 서버가 만들 수 있는 상태다 ──
/// 서버는 지급 때 · 읽을 때 **가진 케이크를 선택지에서 뺀다**(`grant_character_gift` · `character_gift_pending`). 그래서 이 장면의 나는
/// 케이크를 **하나도 안 가졌고**(상점 `_me/rpc.shop_state@demo-gift.json` — 두 칸 다 잠김) 여우를 입고 있다(기본 착용 픽스처). 받은 뒤에는
/// 받은 것**만** 가진다: 스텁이 수령 응답을 기록해(`Ledger`) 그 뒤 요청에는 받은 뒤 바늘(`demo-gift-got-<strawberry|choco>`)을 붙이고,
/// 상점은 `_me/rpc.shop_state@demo-gift-got-*.json`(받은 것 보유) · 선물 조회는 `rpc.character_gift_pending@demo-gift-got.json`(선물 없음)을
/// 고른다(바늘이 긴 것이 이긴다). 일반 상점 장면(심사원의 기본 경로 — `_me` · `_me-shop`)은 케이크 두 행(딸기 보유 · 초코 잠김)이지만
/// 그 장면의 선물 조회는 언제나 '선물 없음'이라, 한 화면에 '가진 케이크'와 '열린 선물'이 같이 서는 일이 없다.
/// 받은 뒤 바늘에 캐릭터 id 를 통째로 넣지 않는 까닭: `rpc.set_character@aing_cake_choco.json` 같은 바늘이 그 글자를 보고 다른 착용
/// 요청까지 가로챈다(여우를 골라도 초코 응답).
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
    /// 받은 뒤 바늘의 머리(`demo-gift-got` + `-strawberry` | `-choco`). 이 머리만으로 고르는 파일도 있다(선물 조회 — 선물 없음).
    package static let claimedNeedle = "demo-gift-got"

    /// 받은 뒤 바늘의 꼬리 — 케이크 id 의 짧은 이름. 모르는 id 면 nil(기록하지 않는다).
    package static func claimedSuffix(for characterID: String) -> String? {
        switch characterID {
        case CharacterCatalog.cakeStrawberryAingID: return "strawberry"
        case CharacterCatalog.cakeChocoAingID: return "choco"
        default: return nil
        }
    }

    /// 데모 한 실행의 수령 기록. 스텁 응답기가 수령 응답을 보고 적고(`record`), 그 뒤 요청의 바늘을 바꾼다(`needle`). 응답기는
    /// URLSession 스레드에서 불리므로 자물쇠로 감싼다.
    package final class Ledger: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed: String?

        package init() {}

        /// 지금 붙일 바늘 — 받기 전 `demo-gift`, 받은 뒤 `demo-gift-got-<strawberry|choco>`.
        package var needle: String {
            lock.lock()
            defer { lock.unlock() }
            return claimed.map { "\(MobileDemoCakeGiftRoute.claimedNeedle)-\($0)" } ?? MobileDemoCakeGiftRoute.needle
        }

        /// 수령이 성공했으면(200 · status ok · 아는 케이크 id) 받은 것을 적는다. 그 밖의 요청 · 응답은 무시한다.
        package func record(_ request: MobileStubRequest, response: MobileStubResponse) {
            guard request.rpcName == "claim_character_gift", response.status == 200,
                  let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
                  object["status"] as? String == "ok", let id = object["character_id"] as? String,
                  let suffix = MobileDemoCakeGiftRoute.claimedSuffix(for: id) else { return }
            lock.lock()
            claimed = suffix
            lock.unlock()
        }
    }

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

    /// 바늘을 요청 본문 꼬리에 붙인 사본(`MobileDemoMissionsRoute.rewrite` 와 같다 — 기록은 원본으로 남는다). 받기 전 바늘이다.
    package func rewrite(_ request: MobileStubRequest) -> MobileStubRequest {
        rewrite(request, needle: Self.needle)
    }

    /// 수령 기록을 보고 바늘을 고른 사본(받기 전 `demo-gift` · 받은 뒤 `demo-gift-got-…`). 데모 스텁 응답기가 쓴다.
    package func rewrite(_ request: MobileStubRequest, ledger: Ledger) -> MobileStubRequest {
        rewrite(request, needle: ledger.needle)
    }

    private func rewrite(_ request: MobileStubRequest, needle: String) -> MobileStubRequest {
        MobileStubRequest(
            method: request.method,
            host: request.host,
            path: request.path,
            query: request.query,
            headers: request.headers,
            bodyText: request.bodyText + " __demoFixture=" + needle
        )
    }
}
#endif
