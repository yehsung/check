import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.84 — 1:1 알까기 선후 맞춤: 판의 첫 수(흑) 힘 60%, 단독)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(… → 0.3.83 → 여기).
// 대표 결정: 11-10 "알까기에서 선으로 날리는 흑돌이 너무 많이 유리한거 같아" → 비교 자료 · #d_5KuZ3DGTw6BY
//   "흑 첫 수 힘 60%로 — 다음 맥 판(0.3.84)에"(컴퓨터 대전 5,000판 × 실력 셋: 흑 56~66% → 51~52%).
// 서버(출시 직전 운영): 첫 수 상한 파일(_alkkagi_first_shot — alk_match_call 조각 치환) → 알까기 문 137(옛 앱은 업데이트 안내).
//
// 골라 돌리는 필터:
//   --filter 'checkTests\.(v0384VersionAndChangelog|v0383VersionAndChangelog|v0384AlkkagiFirstShotGate)\('
@Test("CHANGELOG 0.3.84 (두 줄 · 배너 폭 안 · 내부 어휘 없음)")
func v0384VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    // 버전 고정과 맨 위 섹션 단언은 0.3.85 로 옮겼다(V0385ReleaseTests).
    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.84\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect((2...4).contains(items.count), "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0384] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["서버", "CheckCore", "테스트", "protocol", "RPC", "시뮬레이션", "당김"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("알까기") && $0.contains("첫 수") && $0.contains("60%") }, "첫 수 60% 줄이 없다")
}

@Test("릴리스 게이트: 알까기 첫 수 상한 81(최대 135 의 60%) · protocol 2 그대로 · 감속 B 그대로")
@MainActor
func v0384AlkkagiFirstShotGate() {
    #expect(AlkkagiGame.firstShotMaxPull == 81 && AlkkagiGame.maxPull == 135)
    #expect(AlkkagiOnlineWire.protocolVersion == 2, "규칙은 문(137)으로 가른다 — protocol 은 그대로")
    #expect(AlkkagiGame.Physics.current == .board, "물리는 바꾸지 않는다")
}
