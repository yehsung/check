import AppKit
import Foundation
import Testing
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.76 — 아잉 마작)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(… → 0.3.75 → 여기).
// 다음 릴리스가 오면 이 둘을 그쪽 파일로 옮기고, 여기는 0.3.76 섹션의 **내용**만 남겨라 —
// 안 옮기면 버전을 올리는 그 커밋에서 전체 스위트가 빨개진다.
// 이 판은 아잉 마작 하나다(대표 11-04 결재 #d_3DxzZrHMUzvr "지금 바로 출시 (운영 시험 한 판 포함)").
// 서버 문 열기(20261108222000_mahjong_open_mac_129)의 129 가 이 판의 CFBundleVersion 과 같아야 한다.
@Test("버전 0.3.76 / 129 · CHANGELOG 0.3.76 가 맨 위(아잉 마작 한 줄 · 배너 폭 안)")
func v0376VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.76</string>"))
    #expect(squashed.contains("<key>CFBundleVersion</key><string>129</string>"))

    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.76\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect(items.count == 1, "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0376] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["토큰", "서버", "테스트", "CheckCore", "리치 마작 규칙", "mahjong", "💎"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("아잉 마작") }, "아잉 마작 줄이 없다(feat/aing-mahjong)")
    #expect(changelog.range(of: "## 0.3.76")!.lowerBound < changelog.range(of: "## 0.3.75")!.lowerBound,
            "0.3.76 가 맨 위 섹션이 아니다(릴리스 스크립트가 맨 위 버전을 쓴다)")
}
