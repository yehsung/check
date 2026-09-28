import Foundation

/// 아이폰 앱(아잉체크)으로 가는 주소·문구 — **여기 한 곳에만** 있다. 공지 카드의 QR 과 설정의 QR 이 둘 다 이걸 쓴다.
/// 두 곳에 적히면 한쪽만 고쳐진다. 소스 계약 테스트(V0340AppNoticeTests)가 `Sources/` 전체에서 이 주소와 앱 ID 가
/// 이 파일에만 있음을 잰다 — 화면 코드에 글자로 다시 적지 마라.
package enum CheckAppLinks {
    /// 앱스토어 앱 ID. 2026-09-28 `itunes.apple.com/lookup?id=6812768622&country=kr` 실측:
    /// trackName "아잉체크"(붙여쓰기) · version 1.0.2 · minimumOsVersion 18.0.
    package static let iosAppStoreID = "6812768622"

    /// 아이폰 앱 앱스토어 주소. **지역 코드(`/kr/` 등)를 넣지 않는다** — 이 모양이 HTTP 200 이고 애플이 **보는 사람의
    /// 지역으로 알아서 보낸다**(175개 지역 판매 중). `/kr/` 을 박으면 해외에서 여는 사람이 엉뚱한 스토어로 간다.
    /// 슬러그(`아잉체크`)도 애플이 붙이니 우리가 쓸 필요 없고, itunes lookup 의 `trackViewUrl` 에 붙는 `?uo=4` 는
    /// 제휴 추적 파라미터라 뺀다. 테스트가 "지역 코드 없음 · 쿼리 없음 · 경로 = /app/id<ID>" 를 단언한다 —
    /// "한국 앱이니 /kr/ 을 넣자"로 되돌리기 쉬운 자리다.
    package static let iosAppStore = URL(string: "https://apps.apple.com/app/id\(iosAppStoreID)")!

    /// 스토어의 최소 iOS 버전 문구. 출처: 2026-09-28 `itunes.apple.com/lookup` 실측 `minimumOsVersion = 18.0`.
    /// 구형 아이폰이 QR 을 찍으면 "이 기기와 호환되지 않음"을 만나므로 화면이 이 문구를 주소 옆에 둔다.
    /// **스토어에서 최소 버전을 올리면 여기도 고쳐라** — 실제 값과 갈리면 이 문구는 거짓말이 된다.
    package static let iosMinimumVersionText = "iOS 18 이상"
}
