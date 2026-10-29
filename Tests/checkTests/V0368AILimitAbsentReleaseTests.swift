import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.68)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(0.3.60 → … → 0.3.67 → 여기).
// 다음 릴리스가 오면 이 둘을 그쪽 파일로 옮기고, 여기는 0.3.68 섹션의 **내용**만 남겨라 —
// 안 옮기면 버전을 올리는 그 커밋에서 전체 스위트가 빨개진다.
//
// 0.3.68 의 기능 시험은 버전 이름이 없는 `AILimitsMacTests` · `MeAILimitsTests` · `WidgetAILimitsTests` 에
// 들어갔다(코덱스 5시간 '없음' 칸 수리 — 정본 `docs/plan/ai-limit-absent-cell-contract.md`). 그래서 이 파일은
// 게이트만 든다 — 다음 판이 "버전 고정을 어디서 옮겨 오나"를 파일 이름으로 찾게.
@Test("버전 0.3.68 / 121 · CHANGELOG 0.3.68 가 맨 위(코덱스 5시간 이유 · 리셋 날짜 · 4줄 이하 · 배너 폭 안)")
func v0368VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.68</string>"))
    #expect(squashed.contains("<key>CFBundleVersion</key><string>121</string>"))

    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.68\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect((2...4).contains(items.count), "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0368] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    // 내부 어휘 — 지난 판 목록에 이번 수리의 진단 어휘(창 이름·창 길이·플랜 필드)를 더한다.
    for banned in ["토큰", "서버", "테스트", "CheckCore", "RPC", "마이그레이션", "💎",
                   "primary_window", "window", "plan_type", "10080", "18000"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("코덱스") && $0.contains("5시간") }, "코덱스 5시간 이유 줄이 없다")
    #expect(items.contains { $0.contains("리셋") && $0.contains("날짜") }, "리셋 날짜 줄이 없다")
    #expect(changelog.range(of: "## 0.3.68")!.lowerBound < changelog.range(of: "## 0.3.67")!.lowerBound,
            "0.3.68 가 맨 위 섹션이 아니다(릴리스 스크립트가 맨 위 버전을 쓴다)")
}
