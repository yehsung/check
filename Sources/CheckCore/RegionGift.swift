import Foundation

// MARK: - 얻는 길 — 우리 센터 선물(선물 종류 'region' · 대표 #d_RyTlg0ZZED04 "가. 우리 센터 선물")

/// 우리 센터 선물 문구. **가안**(받는 창 문구는 대표 확인 전 — 바뀌면 여기 한 곳만 고친다). `DrinkGiftText` 와 같은 모양 · 같은 자리다.
/// 잠긴 칸 줄은 두 센터에 같은 글자다(남의 센터 아잉이를 볼 때 — "그 센터 사람에게만").
package nonisolated enum RegionGiftText {
    /// 받는 창 제목.
    package static let title = "우리 센터 아잉이가 왔어요! 📍"
    /// 받는 창 본문.
    package static let body = "우리 센터 사람에게만 주는 지역 아잉이예요. 하나씩 받아 가세요!"
    /// 확인 단추(고를 것이 없다 — 선택지는 우리 센터 아잉이 하나).
    package static let confirmButton = "받기"
    package static let wearNowButton = CakeGiftText.wearNowButton
    package static let closeButton = CakeGiftText.closeButton
    /// 상점 잠긴 칸 캡션(가격 · 사기 단추 자리).
    package static let lockedCaption = "센터 선물"
    /// 잠긴 칸을 골랐을 때의 안내.
    package static let lockedHint = "그 센터 사람에게만 주는 선물이에요. 루비나 뽑기로는 얻을 수 없어요."
    /// 받지 않고 닫은 뒤 메뉴 팝오버 · 상점에 남는 카드.
    package static let reopenTitle = "우리 센터 아잉이가 기다려요"
    package static let reopenButton = "받기"
    package static let claimFailed = CakeGiftText.claimFailed
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
