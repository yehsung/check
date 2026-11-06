import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.77 — 빼빼로 아잉이 · 11-11 선물)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(… → 0.3.76 → 여기).
// 다음 릴리스가 오면 이 둘을 그쪽 파일로 옮기고, 여기는 0.3.77 섹션의 **내용**과 그림 묶음 게이트만 남겨라 —
// 안 옮기면 버전을 올리는 그 커밋에서 전체 스위트가 빨개진다.
// 이 판은 빼빼로 아잉이(11-11 하루 선물 전용 캐릭터) 하나다. 마작은 0.3.76 이다 — 0.3.77 섹션에 마작이 있으면 빨갛다.
// 체인지로그는 공개 GitHub 릴리스·brew 에 그대로 실린다 — 상표 글자('빼빼로')는 앱 안에만 쓰고 여기엔 일반 말로 쓴다.
// 서버(빼빼로 선물 파일 20261108230000 — 적용 때 번호만 운영 마지막 뒤로)는 빌드가 아니라 상점 능력 번호 6 으로 가른다 —
// 그래서 130 은 서버에 박히지 않는다(0.3.76 의 마작 문 열기 129 와 다르다).
//
// 골라 돌리는 릴리스 게이트(전체 스위트 대신 돌릴 때)의 필터 — 자유 함수는 스위트 이름으로 안 잡혀 이름으로 따로 고른다:
//   --filter 'checkTests\.(V0377ReleaseTests|V0377PeperoReleaseGateTests|V0377PeperoReviewFixTests)/'
//   --filter 'checkTests\.(v0377VersionAndChangelog|v0376VersionAndChangelog)\('
@Test("버전 0.3.77 / 130 · CHANGELOG 0.3.77 가 맨 위(11-11 새 캐릭터 한 줄 · 배너 폭 안 · 상표 글자 없음)")
func v0377VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.77</string>"))
    #expect(squashed.contains("<key>CFBundleVersion</key><string>130</string>"))

    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.77\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect(items.count == 1, "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0377] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["토큰", "서버", "테스트", "CheckCore", "빼빼로", "Pepero", "pepero", "롯데", "마작", "💎"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘·상표 글자·다른 판('\(banned)')이 있다")
    }
    #expect(items.contains { $0.contains("11월 11일") && $0.contains("캐릭터") }, "11-11 새 캐릭터 줄이 없다(feat/pepero-aing)")
    #expect(changelog.range(of: "## 0.3.77")!.lowerBound < changelog.range(of: "## 0.3.76")!.lowerBound,
            "0.3.77 가 맨 위 섹션이 아니다(릴리스 스크립트가 맨 위 버전을 쓴다)")
}

/// 빼빼로 그림 묶음 게이트. 번들만으로 빼빼로를 그릴 수 있어야 맥이 상점 능력 번호 6 을 말하고, 그래야 11-11 에 선물이 온다 —
/// 그림이 빠지면 맥은 **조용히 5 에 머문다**(시험도 앱도 빨개지지 않는다). 그래서 이 판의 게이트가 직접 단언한다.
@MainActor
@Suite struct V0377ReleaseTests {
    @Test("릴리스 게이트: 번들 drawable 에 aing_pepero · 능력 번호 6 · 빼빼로 선물 지원(정본 V0377PeperoReleaseGateTests 를 그대로 부른다)")
    func peperoArtBundleGate() {
        // 정본 단언(번들 drawable · 능력 번호 6 · 선물 종류 지원)을 그대로 부른다 — 이 파일만 골라 돌려도 게이트가 선다.
        V0377PeperoReleaseGateTests().bundledPeperoAndProtocolSix()
        // 같은 단언을 여기에도 직접 둔다 — 정본이 뒤에 약해져도 이 판의 게이트는 그대로다.
        #expect(WorkTimerStore.bundledDrawableCharacterIDs.contains(CharacterCatalog.peperoAingID),
                "번들 drawable 에 aing_pepero 가 없다 \(WorkTimerStore.bundledDrawableCharacterIDs)")
        // v0.3.78: 흑우가 얹혀 7(누적) — 빼빼로 판 게이트의 뜻은 '6 이상'이다(흑우 판 게이트는 V0378HwooMac3DTests).
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: WorkTimerStore.bundledDrawableCharacterIDs) >= ShopWire.peperoProtocol)
        #expect(V0317ShopTests.plainStore().shopProtocolVersion >= ShopWire.peperoProtocol)
        #expect(ShopWire.peperoProtocol == 6, "빼빼로 능력 번호가 6 이 아니다(\(ShopWire.peperoProtocol)) — 서버 min_protocol 과 어긋난다")
    }

    @Test("릴리스 게이트: 그림 세 장(판 · 초상 둘)이 소스 트리에 있고 패키징 대본이 같은 셋을 센다 · 게이트 스위트 둘이 있다")
    func peperoArtFilesAndGateSuites() throws {
        let root = CheckCoreSourceLayout.repoRoot
        let names = ["aing_pepero-box", "aing_pepero-neutral", "aing_pepero-negative"]
        for name in names {
            let url = root.appendingPathComponent("Sources/check/Resources/\(name).png")
            #expect(FileManager.default.fileExists(atPath: url.path), "그림이 없다: \(url.path)")
        }
        let script = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
        #expect(script.contains("for PEPERO_PNG in \(names.joined(separator: " ")); do"),
                "build-local.sh 가 빼빼로 그림 세 장을 안 센다 — 하나 빠진 채로 패키징이 지나간다")
        // 게이트 필터가 고르는 두 스위트(위 머리말) — 이름이 바뀌거나 지워지면 이 줄이 컴파일에서 멈춘다.
        let gateSuites: [Any.Type] = [V0377PeperoReleaseGateTests.self, V0377PeperoReviewFixTests.self]
        #expect(gateSuites.count == 2)
    }
}
