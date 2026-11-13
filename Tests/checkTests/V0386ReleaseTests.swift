import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.86 — 메시지 사진 · 지난 대화 30일 · 지난 확성기 · 제보 캡처 · 대기방 수리 · 알까기 시계·안내)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(… → 0.3.85 → 여기).
// 대표 결정: 넷 고름 #d_x5kYyOPOeLlH · 메시지 30일 #d_IKem7qxZXc5b · 한 판 #d_hx5gdoOsyLUZ "한 판에 넷 다(0.3.86)" ·
//   대기방 #d_Yoh3lSljkiSI → #d_u8XAC7N2hWZp "대기방 수리도 0.3.86에 넣고, 다 되면 바로 출시" ·
//   알까기 #d_cjxnVZpLHWw5 "C안 — 남은 초 고침과 함께 다음 맥 판에".
// 서버(출시 직전 운영): 보관 30일 · 사진/캡처/지난 글 · 맥 문 열기 build 139(사진 · 캡처). 이 판의 build 가 139 여야
//   서버 문 열기 파일과 맞는다 — 번호가 바뀌면 서버 문 열기 파일도 같이 고친다.
//
// 골라 돌리는 필터:
//   --filter 'checkTests\.(v0386VersionAndChangelog|v0385VersionAndChangelog)\('
@Test("버전 0.3.86 / 139 · CHANGELOG 0.3.86 가 맨 위(네 줄 · 배너 폭 안 · 내부 어휘 없음)")
func v0386VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.86</string>"))
    #expect(squashed.contains("<key>CFBundleVersion</key><string>139</string>"),
            "사진 · 캡처 서버 문 열기(139)가 이 build 와 같아야 한다")
    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.86\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect((3...4).contains(items.count), "항목 \(items) — 배너는 앞의 4줄까지 보인다")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0386] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["서버", "CheckCore", "테스트", "protocol", "RPC", "디코드", "build"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("사진") && $0.contains("30일") }, "사진 · 지난 대화 줄이 없다")
    #expect(items.contains { $0.contains("확성기") && $0.contains("캡처") }, "지난 확성기 · 캡처 줄이 없다")
    #expect(items.contains { $0.contains("대기방") }, "대기방 수리 줄이 없다")
    #expect(items.contains { $0.contains("알까기") }, "알까기 줄이 없다")
    #expect(changelog.range(of: "## 0.3.86")!.lowerBound < changelog.range(of: "## 0.3.85")!.lowerBound,
            "0.3.86 가 맨 위 섹션이 아니다(릴리스 스크립트가 맨 위 버전을 쓴다)")
}
