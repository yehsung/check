import AppKit
import Foundation
import Testing
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.69 — 아잉 큐브)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(0.3.60 → … → 0.3.67 → 여기).
// 다음 릴리스가 오면 이 둘을 그쪽 파일로 옮기고, 여기는 0.3.69 섹션의 **내용**만 남겨라 —
// 안 옮기면 버전을 올리는 그 커밋에서 전체 스위트가 빨개진다.
@Test("버전 0.3.69 / 122 · CHANGELOG 0.3.69 가 맨 위(아잉 큐브 · 공개 방과 초대 · 일일 미션 · 4줄 이하 · 배너 폭 안)")
func v0368VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.69</string>"))
    #expect(squashed.contains("<key>CFBundleVersion</key><string>122</string>"))

    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.69\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect((2...4).contains(items.count), "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0368] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["토큰", "서버", "테스트", "CheckCore", "RPC", "마이그레이션", "💎", "rummy", "루미", "Rummikub"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘·상표('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("아잉 큐브") && $0.contains("2~4명") }, "새 미니게임 줄이 없다")
    #expect(items.contains { $0.contains("공개 방") && $0.contains("초대") && $0.contains("등수") }, "모으기·분배 줄이 없다")
    #expect(items.contains { $0.contains("일일 미션") }, "일일 미션 줄이 없다")
    #expect(changelog.range(of: "## 0.3.69")!.lowerBound < changelog.range(of: "## 0.3.67")!.lowerBound,
            "0.3.69 가 맨 위 섹션이 아니다(릴리스 스크립트가 맨 위 버전을 쓴다)")
}

/// 서버 능력 게이트(`rummy_min_build()`)가 이 판의 build 와 같다. 크면 맥이 스스로를 '아잉 큐브를 모르는 앱'으로 막고(초대·참가 불가),
/// 작으면 아잉 큐브를 모르는 옛 맥이 초대를 받는다.
@Test("서버 rummy_min_build() = 이 판의 CFBundleVersion(122)")
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
    #expect(minBuild == appBuild, "rummy_min_build() = \(minBuild ?? -1), 앱 build = \(appBuild ?? -1)")
}
