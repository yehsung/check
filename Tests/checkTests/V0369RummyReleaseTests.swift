import AppKit
import Foundation
import Testing
@testable import CheckCore

// MARK: - 0.3.69 체인지로그 (내용만)
//
// 버전 고정과 "맨 위 섹션" 단언은 0.3.70 에서 `V0370ReleaseTests` 로 넘겼다(관행 — 그 릴리스의 시험 파일이 든다).
// 여기는 0.3.69 섹션의 **내용**만 남는다.
@Test("CHANGELOG 0.3.69(아잉 큐브 · 확성기 · 미니게임 창 · 플래피 · 메시지 · 버그 수리 · 4줄 이하 · 배너 폭 안)")
func v0369VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.69\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect((2...4).contains(items.count), "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0369] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["토큰", "서버", "테스트", "CheckCore", "RPC", "마이그레이션", "💎", "rummy", "루미", "Rummikub"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘·상표('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("아잉 큐브") && $0.contains("2~4명") }, "새 미니게임 줄이 없다")
    #expect(items.contains { $0.contains("확성기") }, "확성기 배너 줄이 없다(main a6791165)")
    #expect(items.contains { $0.contains("미니게임 창") && $0.contains("왼쪽") }, "미니게임 창 개편 줄이 없다")
    #expect(items.contains { $0.contains("메시지") }, "메시지 즉시 확정 줄이 없다(서버 안정화 맥 변경)")
    #expect(items.contains { $0.contains("플래피") && $0.contains("붉게") }, "플래피 기둥 예고 줄이 없다(버그 개선 db93317f)")
    #expect(items.contains { $0.contains("테트리스") && $0.contains("두 개") }, "버그 개선 줄이 없다(main 8d761790)")
}

/// 서버 능력 게이트(`rummy_min_build()`)가 이 판의 build 와 같다. 크면 맥이 스스로를 '아잉 큐브를 모르는 앱'으로 막고(초대·참가 불가),
/// 작으면 아잉 큐브를 모르는 옛 맥이 초대를 받는다.
@Test("서버 rummy_min_build() = 122(아잉 큐브 첫 판) · 이 판의 CFBundleVersion 은 그 이상")
func v0368ServerMinBuildMatchesApp() throws {
    let sql = try rwcMigrationSQL()
    let regex = try NSRegularExpression(
        pattern: #"function\s+public\.rummy_min_build\s*\(\s*\).*?select\s+(\d+)"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators])
    let match = try #require(regex.firstMatch(in: sql, range: NSRange(sql.startIndex..., in: sql)))
    let minBuild = Int(sql[Range(match.range(at: 1), in: sql)!])
    let build = try String(contentsOf: CheckCoreSourceLayout.repoRoot.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    let marker = "<key>CFBundleVersion</key><string>"
    let tail = try #require(squashed.range(of: marker)).upperBound
    let appBuild = Int(squashed[tail...].prefix { $0.isNumber })
    #expect(minBuild == 122, "rummy_min_build() = \(minBuild ?? -1)")
    #expect((appBuild ?? 0) >= (minBuild ?? Int.max), "앱 build \(appBuild ?? -1) 이 rummy_min_build \(minBuild ?? -1) 보다 낮다 — 스스로를 막는다")
}
