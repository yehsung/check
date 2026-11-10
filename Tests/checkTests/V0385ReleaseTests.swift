import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.85 — 지역 아잉이(부산 갈매기 · 서울의 밤, 우리 센터 선물) + 콕 찌르기 이름 찾기)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(… → 0.3.84 → 여기).
// 대표 결정: 지역 아잉이 #d_i1SA8M2VJR5a · 나눠 주기 #d_RyTlg0ZZED04 "가. 우리 센터 선물" · 부산 #d_afa6DRyExPLp G1 · 서울 #d_MOlCB5s8cPsm H5 ·
//   받는 창 #d_vxeOaE7gAxzt "부산센터 선물 도착!" · 출시 #d_a1BzIxbjPzhQ "말투 고르면 바로 출시" · 이름 찾기 #d_L35QW1FGYzdH "다음 맥 판에 함께 넣기".
// 서버(출시 직전 운영): 우리 센터 선물 파일(_region_aing_gift — 선물 종류 region · 값 행 둘 · region_gift_ensure). 문은 능력 번호 10 이다
//   (두 센터 아잉이를 다 그리는 빌드만 10 을 싣는다 — 옛 앱은 지역 선물 · 지역 칸을 못 본다).
//
// 골라 돌리는 필터:
//   --filter 'checkTests\.(v0385VersionAndChangelog|v0384VersionAndChangelog|v0385RegionAingGate)\('
@Test("CHANGELOG 0.3.85 (세 줄 · 배너 폭 안 · 내부 어휘 없음)")
func v0385VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    // 버전 고정과 맨 위 섹션 단언은 0.3.86 으로 옮겼다(V0386ReleaseTests).
    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.85\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect((2...4).contains(items.count), "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0385] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["서버", "CheckCore", "테스트", "protocol", "RPC", "region", "능력"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("부산") && $0.contains("서울") }, "지역 아잉이 줄이 없다")
    #expect(items.contains { $0.contains("콕 찌르기") && $0.contains("찾") }, "이름 찾기 줄이 없다")
}

@Test("릴리스 게이트: 지역 아잉이 — 이 빌드가 두 센터를 다 그려 능력 번호 10 · 선물 종류 region 문턱 10 · 받는 창 제목은 센터 이름")
@MainActor
func v0385RegionAingGate() {
    #expect(ShopWire.regionProtocol == 10 && ShopWire.regionCharacterIDs == [CharacterCatalog.busanAingID, CharacterCatalog.seoulAingID])
    #expect(RegionAingFinish.isDrawable(CharacterCatalog.busanAingID) && RegionAingFinish.isDrawable(CharacterCatalog.seoulAingID),
            "두 센터 아잉이 그림이 번들에 다 있어야 한다")
    let drawable = WorkTimerStore.bundledDrawableCharacterIDs
    #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable) == ShopWire.regionProtocol,
            "출시 빌드가 10 을 싣지 않으면 아무도 우리 센터 선물을 못 받는다 — 번들 drawable \(drawable)")
    #expect(CharacterGiftKind.region.minProtocol == ShopWire.regionProtocol)
    #expect(CharacterGiftOffer(id: "g", options: [CharacterCatalog.busanAingID], kind: .region).copy.title == "부산센터 선물 도착!")
    #expect(CharacterGiftOffer(id: "g", options: [CharacterCatalog.seoulAingID], kind: .region).copy.title == "서울센터 선물 도착!")
}
