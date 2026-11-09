import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 릴리스 게이트 (v0.3.81 — 개발에 찌든 아잉이 + 오목알 스킨 6종, 합본)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(… → 0.3.80 → 여기).
// 대표 결정: 개발 아잉이 그림 #d_NuLS5imieQds "D2 후드티 개발자" · 얻는 길 #d_OwYy6Avg5alV "미션보상으로 가자. 총 누적근무시간 100시간
//   이상달성. (이미 달성한 사람들은 바로 받는걸로.)" · 오목알 스킨 #d_UVBJ8vJua1jD 상점 루비 100 · #d_RR2dyBIHDMW5 상대에게도 보임 ·
//   #d_TFKnfZL40Ax6 "2, 4, 5, 7, 6 채택" · 출시 #d_18sen3lPbnPb "오목알 스킨과 같이 출시".
// 서버: 20261111120000_aing_dev_mission · 20261111130000_omok_skins(출시 직전 운영 적용).
//
// 골라 돌리는 필터:
//   --filter 'checkTests\.(v0381VersionAndChangelog|v0380VersionAndChangelog|v0381BundleGate)\('
@Test("버전 0.3.81 / 134 · CHANGELOG 0.3.81 가 맨 위(두 줄 · 배너 폭 안 · 내부 어휘 없음)")
func v0381VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.81</string>"))
    #expect(squashed.contains("<key>CFBundleVersion</key><string>134</string>"))
    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.81\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect(items.count == 2, "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0381] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["서버", "CheckCore", "테스트", "미션 보상 RPC", "protocol", "능력 번호", "aing_dev"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(items.contains { $0.contains("개발에 찌든 아잉이") && $0.contains("100시간") }, "개발 아잉이 줄이 없다")
    #expect(items.contains { $0.contains("오목알 스킨") && $0.contains("상대") }, "오목알 스킨 줄이 없다")
    #expect(changelog.range(of: "## 0.3.81")!.lowerBound < changelog.range(of: "## 0.3.80")!.lowerBound,
            "0.3.81 가 맨 위 섹션이 아니다(릴리스 스크립트가 맨 위 버전을 쓴다)")
}

@Test("릴리스 게이트: 번들에 개발 아잉이(능력 번호 9 — 서버 min 9) · 오목알 스킨 6종(스킨 능력 번호 1 — 서버 min 1) · 미션 키 work100")
@MainActor
func v0381BundleGate() {
    let drawable = WorkTimerStore.bundledDrawableCharacterIDs
    #expect(drawable.contains(CharacterCatalog.devAingID), "번들 drawable 에 aing_dev 가 없다 \(drawable)")
    #expect(ShopWire.devProtocol == 9, "능력 번호가 서버 초안(aing_dev min 9)과 어긋난다")
    #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable) == ShopWire.devProtocol)
    #expect(V0317ShopTests.plainStore().shopProtocolVersion == ShopWire.devProtocol)
    #expect(DevAingMission.key == "work100")
    #expect(OmokStoneSkin.protocolVersion == 1)
    #expect(OmokStoneSkin.allCases.map(\.rawValue) == ["neon", "dice", "cat", "aing", "diamond", "pixel"])
}
