import AppKit
import Foundation
import Testing
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.74 — 아잉 뒤집기 · 이슬 아잉이 · 메시지 서식 · 대결 알림·창 수리)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(… → 0.3.73 → 여기).
// 다음 릴리스가 오면 이 둘을 그쪽 파일로 옮기고, 여기는 0.3.74 섹션의 **내용**만 남겨라 —
// 안 옮기면 버전을 올리는 그 커밋에서 전체 스위트가 빨개진다.
// 마작(아잉 마작)은 이 판에 넣지 않는다(대표 11-03 "마작 제외하고 일단 출시") — 체인지로그에 마작이 있으면 빨갛다.
@Test("CHANGELOG 0.3.74 (뒤집기·이슬 · 메시지 서식 · 알림·창 · 배너 폭 안)")
func v0374VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot

    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.74\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect((1...3).contains(items.count), "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0374] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["토큰", "서버", "테스트", "CheckCore", "리버시", "Broadcast", "SIGTERM", "장부", "마작", "💎"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘·빠진 기능('\(banned)')이 있다")
    }
    #expect(items.contains { $0.contains("아잉 뒤집기") }, "아잉 뒤집기 줄이 없다(feat/aing-flip)")
    #expect(items.contains { $0.contains("이슬 아잉이") }, "이슬 아잉이 줄이 없다(feat/isul-aing)")
    #expect(items.contains { $0.contains("메시지") }, "메시지 서식 줄이 없다(feat/chat-markdown-focus)")
    #expect(items.contains { $0.contains("내 차례") }, "가려진 창 차례 알림 줄이 없다(fix/turn-alert-1103)")
    // 버전 고정과 맨 위 섹션 단언은 0.3.75 로 옮겼다(V0375ReleaseTests).
}
