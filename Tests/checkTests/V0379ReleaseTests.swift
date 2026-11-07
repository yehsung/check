import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.79 — 다른 기기 또는 서버 연결: 원격 토큰 스캐너 aing-scan)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(… → 0.3.78 → 여기).
// 대표 결정: 착수 #d_ACV5ZaIddlnZ · 운영 반영 #d_fIBZyX9HBfl2 · 배포·출시 #d_UxrqtwZedQIS(메모: "다른 기기또는 서버 연결 이라고 해").
// 서버 20261110120000_token_scanner 는 11-07 18:58 운영 적용됐다. 스캐너는 GitHub 프리릴리스 `aing-scan`(최신 아님).
//
// 골라 돌리는 필터:
//   --filter 'checkTests\.(v0379VersionAndChangelog|v0378VersionAndChangelog)\('
@Test("버전 0.3.79 / 132 · CHANGELOG 0.3.79 가 맨 위(한 줄 · 배너 폭 안 · 내부 어휘 없음)")
func v0379VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.79</string>"))
    #expect(squashed.contains("<key>CFBundleVersion</key><string>132</string>"))
    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.79\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect(items.count == 1, "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0379] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["토큰", "스캐너", "aing-scan", "원격 기계", "서버 함수", "CheckCore", "테스트"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("다른 기기") && $0.contains("서버") }, "대표 메모의 이름('다른 기기 또는 서버')이 없다")
    #expect(changelog.range(of: "## 0.3.79")!.lowerBound < changelog.range(of: "## 0.3.78")!.lowerBound,
            "0.3.79 가 맨 위 섹션이 아니다(릴리스 스크립트가 맨 위 버전을 쓴다)")
}

@Test("릴리스 게이트: 설정 행 이름은 '다른 기기 또는 서버 연결'(대표 메모) · 앱스토어 판에는 없다")
func v0379RemoteScannerEntryGate() throws {
    #expect(RemoteScannerText.entryTitle == "다른 기기 또는 서버 연결")
    let source = try String(contentsOf: CheckCoreSourceLayout.repoRoot.appendingPathComponent("Sources/check/CheckSettingsView.swift"), encoding: .utf8)
    #expect(source.contains("if !store.macEdition.asksBeforeReadingAITools {\n                    RemoteScannerSettingsEntryRow(store: store)"))
}
