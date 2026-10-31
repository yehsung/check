import AppKit
import Foundation
import Testing
@testable import CheckCore

// MARK: - 0.3.70 체인지로그 (내용만 — 핫픽스: 반응 덮개 CPU · 시간 초과 1장 문구)
//
// 버전 고정과 "맨 위 섹션" 단언은 0.3.71 에서 `V0371ReleaseTests` 로 넘겼다(관행 — 그 릴리스의 시험 파일이 든다).
@Test("CHANGELOG 0.3.70(CPU · 시간 초과 1장 · 4줄 이하 · 배너 폭 안)")
func v0370VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.70\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect((1...4).contains(items.count), "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0370] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["토큰", "서버", "테스트", "CheckCore", "RPC", "마이그레이션", "💎", "rummy", "루미", "Rummikub", "덮개"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘·상표('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("CPU") }, "CPU 수리 줄이 없다")
    #expect(items.contains { $0.contains("1장") }, "시간 초과 1장 줄이 없다")
}
