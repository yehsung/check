import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.88 — 캐릭터 창이 Space 소속을 잃으면 감지해 재시작 없이 고친다)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(… → 0.3.87 → 여기).
// 대표 결정: #d_pyrGrCaafCbN "이것만으로 맥 0.3.88 바로 내기"(가지 fix/overlay-space-rebuild-1122).
// 산타 숨김 게이트(V0387ReleaseTests.v0387SantaShipsHidden)는 12-21 지급 전까지 그대로 산다 — 이 판도 산타를 그리지만
//   상점·고르기 어디에도 안 세운다. 그래서 이 판의 업데이트 안내에도 산타를 적지 않는다(아래 단언).
//
// 골라 돌리는 필터:
//   --filter 'checkTests\.(v0388VersionAndChangelog|v0388OverlaySpaceProbeShips|v0387VersionAndChangelog|v0387SantaShipsHidden)\('
@Test("버전 0.3.88 / 141 · CHANGELOG 0.3.88 가 맨 위(한두 줄 · 배너 폭 안 · 내부 어휘 없음 · 산타는 안 적음)")
func v0388VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.88</string>"))
    #expect(squashed.contains("<key>CFBundleVersion</key><string>141</string>"))
    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.88\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect((1...2).contains(items.count), "항목 \(items) — 이 판은 캐릭터 수리 하나다")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0388] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["서버", "CheckCore", "테스트", "protocol", "RPC", "build", "Space", "SkyLight", "패널"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("캐릭터") && $0.contains("재시작 없이") }, "캐릭터 수리 줄이 없다")
    for secret in ["산타", "크리스마스", "선물"] {
        #expect(!section.contains(secret), "깜짝 선물(산타)을 업데이트 안내에 적었다('\(secret)')")
    }
    #expect(changelog.range(of: "## 0.3.88")!.lowerBound < changelog.range(of: "## 0.3.87")!.lowerBound,
            "0.3.88 가 맨 위 섹션이 아니다(릴리스 스크립트가 맨 위 버전을 쓴다)")
}

@Test("릴리스 게이트: 캐릭터 창 Space 감지 — 출시 맥에서 SkyLight 읽기 심볼이 풀리고 대표 맥 모양(2/12, 현재 빠짐)을 고장으로 읽는다")
func v0388OverlaySpaceProbeShips() {
    // 출시를 굽는 맥(macOS 27)에서 심볼이 하나라도 안 풀리면 감지가 공개 신호만으로 돈다 — 그래도 동작은 하지만
    // 이 판의 근거(두 신호 교차 확인)가 빠진 채 나가는 것이니 여기서 멈춘다.
    #expect(OverlaySpaceProbe.skyLightAvailable, "SkyLight 읽기 심볼이 이 맥에서 안 풀린다")
    // 2026-11-22 대표 맥 실측 모양: 소속 [데스크톱 4, IAMCEO 817], 지금 Space 는 그 밖(크롬 전체 화면 등), 그 화면 Space 12개.
    let broken = OverlaySpaceProbe.evaluate(spaces: [4, 817], current: 905, displaySpaceCount: 12)
    #expect(broken.isMissing)
    // 두 신호가 엇갈리면(비공개 "없음" · 공개 "있음") 고치지 않는다.
    let reading = OverlaySpaceProbe.SkyLightReading(spaces: [4, 817], current: 905, displaySpaceCount: 12)
    #expect(OverlaySpaceProbe.combine(skyLightAvailable: true, reading: reading, publicMissing: false) == nil)
    #expect(OverlaySpaceProbe.combine(skyLightAvailable: true, reading: reading, publicMissing: true)?.isMissing == true)
    // 지금 Space 에 있으면(12곳 중 어디든) 고장이 아니다.
    #expect(!OverlaySpaceProbe.evaluate(spaces: [4, 817], current: 817, displaySpaceCount: 12).isMissing)
}
