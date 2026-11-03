import AppKit
import Foundation
import Testing
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.73 — Claude 기록 위치 자동 찾기)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(… → 0.3.72 → 여기).
// 다음 릴리스가 오면 이 둘을 그쪽 파일로 옮기고, 여기는 0.3.73 섹션의 **내용**만 남겨라 —
// 안 옮기면 버전을 올리는 그 커밋에서 전체 스위트가 빨개진다.
@Test("CHANGELOG 0.3.73 (Claude 위치 찾기 한 줄 · 배너 폭 안)")
func v0373VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot

    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.73\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect((1...3).contains(items.count), "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0373] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["토큰", "서버", "테스트", "CheckCore", "CLAUDE_CONFIG_DIR", "스캐너", "Orca", "💎"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("Claude") && $0.contains("자동") }, "Claude 위치 자동 찾기 줄이 없다(88798c8d)")
    // 버전 고정과 맨 위 섹션 단언은 0.3.74 로 옮겼다(V0374ReleaseTests).
}
