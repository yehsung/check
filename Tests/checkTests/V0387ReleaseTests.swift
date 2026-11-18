import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.87 — Claude 로그인 수리 · 콕 찌르기 칸 · 미션 모두 받기 · 산타 아잉이)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(… → 0.3.86 → 여기).
// 대표 결정: 한 판 #d_d5uHytEKkEXj "지금 한 판으로(수리 셋 + 산타)" · Claude 로그인 #d_IYrzxrcSCkTs "다음 맥 판에 넣기" ·
//   콕 찌르기 칸 · 모두 받기 #d_OuNnIBw0Ntdr "추천대로: 찌르기 칸·모두 받기는 고치기" ·
//   산타 #d_Tx5bJnJvCmN6 · #d_3VZdglOgRABx · 문구 #d_4wR1Qzn9OKmt · 기간 #d_jdcyBSon9oZ3(12-21~25).
// 산타는 깜짝 선물이다 — 서버(가격표 행)는 12-21 아침 지급 직전에 켜고, 그 전에는 상점 · 고르기 어디에도 안 선다.
//   그래서 업데이트 안내(체인지로그)에 산타를 적지 않는다(아래 단언).
//
// 골라 돌리는 필터:
//   --filter 'checkTests\.(v0387VersionAndChangelog|v0386VersionAndChangelog|v0387SantaShipsHidden)\('
@Test("버전 0.3.87 / 140 · CHANGELOG 0.3.87 가 맨 위(세 줄 · 배너 폭 안 · 내부 어휘 없음 · 산타는 안 적음)")
func v0387VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.87</string>"))
    #expect(squashed.contains("<key>CFBundleVersion</key><string>140</string>"))
    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.87\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect((3...4).contains(items.count), "항목 \(items) — 배너는 앞의 4줄까지 보인다")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0387] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["서버", "CheckCore", "테스트", "protocol", "RPC", "디코드", "build", "키체인"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("Claude") }, "Claude 로그인 수리 줄이 없다")
    #expect(items.contains { $0.contains("콕 찌르기") && $0.contains("근무중") && $0.contains("자리비움") }, "콕 찌르기 칸 줄이 없다")
    #expect(items.contains { $0.contains("모두 받기") }, "미션 모두 받기 줄이 없다")
    for secret in ["산타", "크리스마스", "선물"] {
        #expect(!section.contains(secret), "깜짝 선물(산타)을 업데이트 안내에 적었다('\(secret)')")
    }
    #expect(changelog.range(of: "## 0.3.87")!.lowerBound < changelog.range(of: "## 0.3.86")!.lowerBound,
            "0.3.87 가 맨 위 섹션이 아니다(릴리스 스크립트가 맨 위 버전을 쓴다)")
}

@Test("릴리스 게이트: 산타 아잉이 — 이 빌드가 산타를 그려 능력 번호 11 · 문구는 대표 결정 C · 서버 행 없으면 상점에 안 선다")
func v0387SantaShipsHidden() throws {
    let drawable = WorkTimerStore.bundledDrawableCharacterIDs
    #expect(drawable.contains(CharacterCatalog.santaAingID), "번들 drawable \(drawable) 에 산타가 없다")
    #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable) == ShopWire.santaProtocol,
            "출시 빌드가 11 을 싣지 않으면 12-21 에 아무도 산타 선물을 못 받는다")
    #expect(CharacterGiftKind.santa.minProtocol == ShopWire.santaProtocol)
    #expect(ShopWire.santaProtocol == 11)
    #expect(SantaGiftText.copyDecided)
    #expect(SantaGiftText.title == "띵동! 산타 왔어요 🎁" && SantaGiftText.confirmButton == "선물 열기")
    // 서버가 산타 행을 싣기 전(가격표 없음 · 가진 사람 없음): 고르기에 안 선다 — 깜짝 선물이 12-21 전에 새지 않는다.
    let santa = CharacterCatalog.santaAingID
    #expect(!WorkTimerStore.isCharacterListed(santa, shopLoaded: true, gachaAvailable: false, owned: [], rows: []))
    #expect(!WorkTimerStore.isCharacterListed(santa, shopLoaded: false, gachaAvailable: false, owned: [], rows: []))
}
