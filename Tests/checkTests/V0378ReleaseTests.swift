import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.78 — 합본: 길건너 1:1 · 흑우 아잉이 · 루비 아잉이 · 근무 리듬 주별 · 제보 칩 색)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(… → 0.3.77 → 여기).
// 다음 릴리스가 오면 이 둘을 그쪽 파일로 옮기고, 여기는 0.3.78 섹션의 **내용**과 그림 묶음 게이트만 남겨라 —
// 안 옮기면 버전을 올리는 그 커밋에서 전체 스위트가 빨개진다.
// 이 판은 대표 결정 #d_zPlHsz4OOJML "시킨것들 다 합쳐서 출시하자 한번에"의 합본이다.
// 서버는 셋이다: 흑우(20261109100000 — 능력 번호 7) · 루비(20261109110000 — 능력 번호 8) · 길건너 판(20261109150000) +
// 맥 문 열기(20261109150500, make_open_mac.sh 131). 흑우 · 루비는 능력 번호로 가르고, 길건너만 **이 판의 build 131** 이 서버에 박힌다.
//
// 골라 돌리는 릴리스 게이트(전체 스위트 대신 돌릴 때)의 필터 — 자유 함수는 스위트 이름으로 안 잡혀 이름으로 따로 고른다:
//   --filter 'checkTests\.(V0378ReleaseTests|V0377ReleaseTests|V0378HwooCoreTests|V0378RubyCoreTests)/'
//   --filter 'checkTests\.(v0378VersionAndChangelog|v0377VersionAndChangelog)\('
@Test("CHANGELOG 0.3.78 (세 줄 · 배너 폭 안 · 내부 어휘 없음)")
func v0378VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    // 버전 고정과 맨 위 섹션 단언은 0.3.79 로 옮겼다(V0379ReleaseTests).

    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.78\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect(items.count == 3, "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0378] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["토큰", "서버", "테스트", "CheckCore", "빼빼로", "Pepero", "마작", "💎", "방송", "능력 번호"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘·다른 판('\(banned)')이 있다")
    }
    #expect(items.contains { $0.contains("길건너") && $0.contains("1:1") }, "길건너 1:1 줄이 없다(feat/crossy-duel)")
    #expect(items.contains { $0.contains("흑우") && $0.contains("루비") }, "새 아잉이 둘 줄이 없다(feat/hwoo-aing · feat/ruby-aing)")
    #expect(items.contains { $0.contains("근무 리듬") }, "근무 리듬 주별 줄이 없다(fix/feedback-1106)")
}

/// 흑우 · 루비 그림 묶음 게이트. 번들만으로 둘 다 그릴 수 있어야 맥이 상점 능력 번호 8 을 말한다 — 그림이 빠지면 맥은
/// **조용히 6 이나 7 에 머문다**(흑우 조각 교환 · 루비 1000 구매가 안 보이고, 시험도 앱도 빨개지지 않는다). 그래서 이 판의 게이트가 직접 단언한다.
@MainActor
@Suite struct V0378ReleaseTests {
    @Test("릴리스 게이트: 번들 drawable 에 aing_hwoo · aing_ruby · 상점 능력 번호 8(흑우 7 위 누적)")
    func newAingArtBundleGate() {
        let drawable = WorkTimerStore.bundledDrawableCharacterIDs
        #expect(drawable.contains(CharacterCatalog.hwooAingID), "번들 drawable 에 aing_hwoo 가 없다 \(drawable)")
        #expect(drawable.contains(CharacterCatalog.rubyAingID), "번들 drawable 에 aing_ruby 가 없다 \(drawable)")
        #expect(ShopWire.hwooProtocol == 7 && ShopWire.rubyProtocol == 8,
                "능력 번호가 서버 초안(흑우 min 7 · 루비 min 8)과 어긋난다 — hwoo \(ShopWire.hwooProtocol) · ruby \(ShopWire.rubyProtocol)")
        // v0.3.81: 번호는 누적이다 — 개발에 찌든 아잉이까지 실린 뒤로는 9(루비 8 위). 이 게이트는 "8 이상"을 잰다.
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable) >= ShopWire.rubyProtocol)
        #expect(V0317ShopTests.plainStore().shopProtocolVersion >= ShopWire.rubyProtocol)
    }

    @Test("릴리스 게이트: 초상 네 장이 소스 트리에 있고 패키징 대본이 같은 넷을 센다")
    func newAingArtFilesAndPackagingGuard() throws {
        let root = CheckCoreSourceLayout.repoRoot
        let names = HwooAingArt.portraitResourceNames + RubyAingArt.portraitResourceNames
        #expect(names == ["aing_hwoo-neutral", "aing_hwoo-negative", "aing_ruby-neutral", "aing_ruby-negative"])
        for name in names {
            let url = root.appendingPathComponent("Sources/check/Resources/\(name).png")
            #expect(FileManager.default.fileExists(atPath: url.path), "그림이 없다: \(url.path)")
        }
        let script = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
        #expect(script.contains("for NEW_AING_PNG in \(names.joined(separator: " ")); do"),
                "build-local.sh 가 흑우·루비 초상 네 장을 안 센다 — 하나 빠진 채로 패키징이 지나간다")
    }

    @Test("릴리스 게이트: 길건너 1:1 RPC 프로토콜 1(서버 crossy_duel_protocol() 과 같다)")
    func crossyDuelWireGate() {
        #expect(CrossyDuelWire.protocolVersion == 1, "서버 crossy_duel_protocol() 은 1 이다")
    }
}
