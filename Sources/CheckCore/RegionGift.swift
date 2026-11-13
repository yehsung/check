import Foundation

// MARK: - 얻는 길 — 우리 센터 선물(선물 종류 'region' · 대표 #d_RyTlg0ZZED04 "가. 우리 센터 선물")

/// 우리 센터 선물 문구 — 받는 창 말투는 대표 결정 #d_vxeOaE7gAxzt "부산센터 선물 도착! 이런식으로 가자": 제목 · 본문 · 다시 열기 카드에
/// **그 선물의 센터 이름**이 들어간다(`title(center:)` — 센터 이름은 `RegionAingArt.centerName(of:)` 의 "부산" · "서울").
/// 센터를 모를 때(선택지가 비었거나 모르는 id)는 "우리 센터" 판(`title` · `body` · `reopenTitle`)이다. `DrinkGiftText` 와 같은 자리다.
/// 잠긴 칸 줄은 두 센터에 같은 글자다(남의 센터 아잉이를 볼 때 — "그 센터 사람에게만").
package nonisolated enum RegionGiftText {
    /// 받는 창 제목(센터를 모를 때).
    package static let title = title(center: nil)
    /// 받는 창 본문(센터를 모를 때).
    package static let body = body(center: nil)
    /// 확인 단추(고를 것이 없다 — 선택지는 우리 센터 아잉이 하나).
    package static let confirmButton = "받기"
    package static let wearNowButton = CakeGiftText.wearNowButton
    package static let closeButton = CakeGiftText.closeButton
    /// 상점 잠긴 칸 캡션(가격 · 사기 단추 자리).
    package static let lockedCaption = "센터 선물"
    /// 잠긴 칸을 골랐을 때의 안내.
    package static let lockedHint = "그 센터 사람에게만 주는 선물이에요. 루비나 뽑기로는 얻을 수 없어요."
    /// 받지 않고 닫은 뒤 메뉴 팝오버 · 상점에 남는 카드(센터를 모를 때).
    package static let reopenTitle = reopenTitle(center: nil)
    package static let reopenButton = "받기"
    package static let claimFailed = CakeGiftText.claimFailed

    /// "부산센터" · "서울센터"(센터를 모르면 "우리 센터").
    package static func centerLabel(_ center: String?) -> String {
        guard let center, !center.isEmpty else { return "우리 센터" }
        return "\(center)센터"
    }

    /// 받는 창 제목 — "부산센터 선물 도착!"(대표 원문 그대로의 꼴).
    package static func title(center: String?) -> String {
        "\(centerLabel(center)) 선물 도착!"
    }

    /// 받는 창 본문 — "부산센터 사람에게만 주는 아잉이예요. 지금 받아 가세요!"
    package static func body(center: String?) -> String {
        "\(centerLabel(center)) 사람에게만 주는 아잉이예요. 지금 받아 가세요!"
    }

    /// 다시 열기 카드 — "부산센터 선물이 기다려요".
    package static func reopenTitle(center: String?) -> String {
        "\(centerLabel(center)) 선물이 기다려요"
    }
}

// MARK: - 전선 모양 — region_gift_ensure

/// `region_gift_ensure(p_protocol)` 본문 — 우리 센터 선물이 없으면 만들어 달라고(있으면 그대로) 서버에 말한다. **키를 언제나 싣는다**.
package struct RegionGiftEnsureRequest: Encodable, Equatable, Sendable {
    package let pProtocol: Int

    package init(pProtocol: Int) {
        self.pProtocol = pProtocol
    }
}

/// `region_gift_ensure` 응답 — `{"status":"granted"|"pending"|"owned"|"no_center"|"needs_update"|"unauthorized", …}`.
/// 화면은 이 값으로 아무것도 그리지 않는다(뒤이은 `character_gift_pending` 이 선물을 싣는다) — 진단용이다.
package struct RegionGiftEnsureResponse: Decodable, Equatable, Sendable {
    package let status: String

    package init(status: String) {
        self.status = status
    }
}

extension SupabaseWorkService {
    package nonisolated static let regionGiftEnsurePath = "/rest/v1/rpc/region_gift_ensure"

    /// 우리 센터 선물을 마련해 달라고 한다(멱등 — 이미 받았거나 열린 선물이 있거나 센터가 없으면 아무것도 안 바뀐다).
    /// 함수가 없는 서버(PGRST202 · 404 — 앱이 db push 보다 먼저 나간 창)는 nil(오류가 아니다). 그 밖의 실패는 던진다.
    /// `protocolVersion` 이 `ShopWire.regionProtocol` 미만이면 부르지 않는다(nil) — 그 빌드는 지역 아잉이를 못 그린다.
    package func ensureRegionGift(accessToken: String, protocolVersion: Int) async throws -> RegionGiftEnsureResponse? {
        guard ShopWire.supportsRegionGift(protocolVersion: protocolVersion) else { return nil }
        let data: Data
        do {
            data = try await send(
                path: Self.regionGiftEnsurePath,
                method: "POST",
                body: RegionGiftEnsureRequest(pProtocol: protocolVersion),
                accessToken: accessToken,
                prefer: nil
            )
        } catch let error as SupabaseWorkServiceError where BlockReportRules.isMissingFunction(error) {
            return nil
        }
        return try decoder.decode(RegionGiftEnsureResponse.self, from: data)
    }
}
