import AppKit
import Foundation
import Testing
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.71 — 아잉 큐브 UX · 확성기 5초)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(… → 0.3.69 → 0.3.70 → 여기).
// 다음 릴리스가 오면 이 둘을 그쪽 파일로 옮기고, 여기는 0.3.71 섹션의 **내용**만 남겨라 —
// 안 옮기면 버전을 올리는 그 커밋에서 전체 스위트가 빨개진다.
@Test("버전 0.3.71 / 124 · CHANGELOG 0.3.71 이 맨 위(아잉 큐브 UX · 확성기 · 4줄 이하 · 배너 폭 안)")
func v0371VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.71</string>"))
    #expect(squashed.contains("<key>CFBundleVersion</key><string>124</string>"))

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
    #expect(changelog.range(of: "## 0.3.71")!.lowerBound < changelog.range(of: "## 0.3.70")!.lowerBound,
            "0.3.71 이 맨 위 섹션이 아니다(릴리스 스크립트가 맨 위 버전을 쓴다)")
}
