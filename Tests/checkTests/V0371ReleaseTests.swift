import AppKit
import Foundation
import Testing
@testable import CheckCore

// MARK: - 0.3.71 체인지로그 (내용만 — 아잉 큐브 UX · 확성기 5초)
//
// 버전 고정과 "맨 위 섹션" 단언은 0.3.72 에서 `V0372ReleaseTests` 로 넘겼다(관행 — 그 릴리스의 시험 파일이 든다).
@Test("CHANGELOG 0.3.71(아잉 큐브 UX · 확성기 · 4줄 이하 · 배너 폭 안)")
func v0371VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.71\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect((2...4).contains(items.count), "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0371] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["토큰", "서버", "테스트", "CheckCore", "RPC", "마이그레이션", "💎", "rummy", "루미", "Rummikub"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘·상표('\(banned)')가 있다")
    }
    // 사용자 10-31 "그냥 단순하게 아잉 큐브 UX를 개선했다고 써" — 판 편집·끼우기·받침대를 한 줄로 묶었다.
    #expect(items.contains { $0.contains("아잉 큐브") && $0.contains("UX") }, "아잉 큐브 UX 줄이 없다")
    #expect(items.contains { $0.contains("확성기") && $0.contains("5초") }, "확성기 줄이 없다(main 359c1ed2)")
}
