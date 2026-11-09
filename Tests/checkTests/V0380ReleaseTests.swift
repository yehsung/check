import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.80 — 1:1 알까기, 외부 기여 PR #9 를 고쳐서 받음)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(… → 0.3.79 → 여기).
// 대표 결정: 받기 #d_zZxechLDr8Dy "(가) 우리가 고쳐서 받기" · 감속 #d_eeuXIRdSJWxL "(B) 바둑판 마찰" ·
//   운영 적용 #d_ZG52BV7kDugo(11-09 16:20, 문 닫힌 채 · 운영 e2e 31/31) · 출시 #d_RRYeGRgyojI1 "② 알까기만으로 맥 새 판 바로 내기".
// 서버 20261110130000_alkkagi 는 운영에 있다 — 출시 뒤 문 열기 한 줄 파일(alk_min_build = 이 build)을 올린다.
//
// 골라 돌리는 필터:
//   --filter 'checkTests\.(v0380VersionAndChangelog|v0379VersionAndChangelog)\('
@Test("버전 0.3.80 / 133 · CHANGELOG 0.3.80 가 맨 위(한 줄 · 배너 폭 안 · 내부 어휘 없음)")
func v0380VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.80</string>"))
    #expect(squashed.contains("<key>CFBundleVersion</key><string>133</string>"),
            "알까기 맥 문 열기(make_open_mac.sh 133)가 이 build 와 같아야 한다")
    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.80\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect(items.count == 1, "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0380] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["PR", "기여", "서버", "Alkkagi", "CheckCore", "테스트", "물리"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("알까기") && $0.contains("1:1") }, "알까기 줄이 없다")
    #expect(changelog.range(of: "## 0.3.80")!.lowerBound < changelog.range(of: "## 0.3.79")!.lowerBound,
            "0.3.80 가 맨 위 섹션이 아니다(릴리스 스크립트가 맨 위 버전을 쓴다)")
}

@Test("릴리스 게이트: 감속은 대표가 고른 B(바둑판 마찰) — 서버 alkkagi_simulate 와 같은 값")
func v0380AlkkagiPhysicsGate() {
    #expect(AlkkagiGame.Physics.current == AlkkagiGame.Physics.board)
    #expect(AlkkagiGame.Physics.board == AlkkagiGame.Physics(drag: 1.5, friction: 300))
}
