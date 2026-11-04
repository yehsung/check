import AppKit
import Foundation
import Testing
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.75 — 채팅 링크 속임수 구멍 두 개 수리)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(… → 0.3.74 → 여기).
// 다음 릴리스가 오면 이 둘을 그쪽 파일로 옮기고, 여기는 0.3.75 섹션의 **내용**만 남겨라 —
// 안 옮기면 버전을 올리는 그 커밋에서 전체 스위트가 빨개진다.
// 이 판은 핫픽스 하나뿐이다(대표 11-03 결재 "디스크 정리 뒤 바로 핫픽스(0.3.75)"). 마작은 0.3.76 이다 — 체인지로그에 마작이 있으면 빨갛다.
@Test("CHANGELOG 0.3.75 (채팅 링크 수리 한 줄 · 배너 폭 안)")
func v0375VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.75\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect(items.count == 1, "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0375] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["토큰", "서버", "테스트", "CheckCore", "퍼센트", "인코딩", "호스트", "마작", "💎"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘·빠진 기능('\(banned)')이 있다")
    }
    #expect(items.contains { $0.contains("링크") }, "채팅 링크 수리 줄이 없다(99fe1f7e)")
    // 버전 고정과 맨 위 섹션 단언은 0.3.76 으로 옮겼다(V0376ReleaseTests).
}
