import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 0.3.68 체인지로그 (내용만)
//
// 버전 고정과 "맨 위 섹션" 단언은 0.3.69 에서 `V0369RummyReleaseTests` 로 넘겼다(관행 — 그 릴리스의
// 시험 파일이 든다). 여기는 0.3.68 섹션의 **내용**만 남는다.
//
// 0.3.68 의 기능 시험은 버전 이름이 없는 `AILimitsMacTests` · `MeAILimitsTests` · `WidgetAILimitsTests` 에
// 들어갔다(코덱스 5시간 '없음' 칸 수리 — 정본 `docs/plan/ai-limit-absent-cell-contract.md`). 그래서 이 파일은
// 게이트만 든다 — 다음 판이 "버전 고정을 어디서 옮겨 오나"를 파일 이름으로 찾게.
@Test("CHANGELOG 0.3.68(코덱스 5시간 이유 · 리셋 날짜 · 4줄 이하 · 배너 폭 안)")
func v0368VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
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
}
