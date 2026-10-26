import Foundation
import Testing
@testable import check
@testable import CheckCore

/// v0.3.59 무지개 아잉이 — 카탈로그 내장 항목과 렌더러가 무지개 변형을 알아보는 길(`CharacterManifest.finish`).
///
/// 지키는 것(금 V0354GoldCatalogTests 와 같은 네 겹):
///  ① 번들이 비어도 무지개가 있다(내장 안전망) · 순서는 아잉 → 황금 → 무지개 → 나머지 정렬.
///  ② 렌더러는 `finish` 로 가른다 — kind 는 아잉 · 황금과 같은 `.scene3D` 라 kind 로 가르면 무지개 착용자 화면에 보라 아잉이 선다.
///  ③ 파일 매니페스트로는 못 싣는다(밑줄 id 거절) · 같은 id 를 넣어도 내장이 이긴다.
///  ④ 선택 · 동기화가 무지개를 "아는 캐릭터"로 다룬다(모르는 id → 아잉 접기에 걸리지 않는다) — 소유 판정은 서버.
@Suite("v0.3.59 무지개 아잉이 카탈로그")
struct V0359RainbowCatalogTests {

    @Test("번들이 비어도 무지개 아잉이가 있다 — 셋째 내장 · 3D · 이름 '무지개 아잉이' · 아틀라스·초상·폴더 없음")
    func rainbowIsBuiltIn() {
        let empty = CharacterCatalog.load(charactersDirectory: nil)
        // v0.3.66: 케이크 둘이 넷째 · 다섯째 내장으로 붙는다(V0366CakeCoreTests).
        #expect(empty.allIDs == ["aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco"])
        let rainbow = empty.manifest(id: "aing_rainbow")
        #expect(rainbow?.displayName == "무지개 아잉이")
        #expect(rainbow?.kind == .scene3D)
        #expect(rainbow?.atlas == nil && rainbow?.portrait == nil)
        #expect(empty.entry(id: "aing_rainbow")?.directory == nil)
        #expect(empty.atlasURL(for: "aing_rainbow") == nil)
        #expect(CharacterCatalog.builtIns.map(\.id) == ["aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco"])
        #expect(CharacterCatalog.rainbowAingID == "aing_rainbow")
        #expect(CharacterCatalog.builtInRainbowAing.id == CharacterCatalog.rainbowAingID)
    }

    @MainActor
    @Test("실제 번들: 아잉 → 황금 → 무지개 → 나머지(id 정렬) — 스프라이트 6종은 그대로 · 3D 경로 카탈로그도 같은 목록")
    func bundledOrder() {
        let ids = CheckMascotAssets.catalog.allIDs
        #expect(Array(ids.prefix(5)) == ["aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco"])   // v0.3.66 케이크 둘이 넷째 · 다섯째
        let rest = Array(ids.dropFirst(5))
        #expect(rest == rest.sorted())
        #expect(Set(rest) == ["fox", "ghost", "jellyfish", "robot", "shiba", "squirrel"], Comment(rawValue: "\(rest)"))
        #expect(CheckCharacter3DScene.catalog.allIDs == ids)
    }

    @Test("finish: 무지개만 .rainbow · 황금만 .gold — 아잉·스프라이트·모르는 id 는 .standard (kind 로는 못 가른다)")
    func finishSeparatesRainbow() {
        let catalog = CheckMascotAssets.catalog
        let aing = catalog.manifest(id: "aing"), gold = catalog.manifest(id: "aing_gold"), rainbow = catalog.manifest(id: "aing_rainbow")
        #expect(aing?.kind == rainbow?.kind && gold?.kind == rainbow?.kind, "전제: 셋 다 scene3D — kind 로는 못 가른다")
        #expect(rainbow?.finish == .rainbow)
        #expect(gold?.finish == .gold)
        #expect(aing?.finish == .standard)
        for id in ["fox", "ghost", "jellyfish", "robot", "shiba", "squirrel"] {
            #expect(catalog.manifest(id: id)?.finish == .standard, "\(id)")
        }
        #expect(CharacterManifest(id: "dragon", displayName: "용", kind: .scene3D).finish == .standard)
        #expect(CharacterCatalog.isRainbowAing("aing_rainbow"))
        for other in ["aing", "aing_gold", "AING_RAINBOW", "aing-rainbow", " aing_rainbow", "aing_rainbow ", "rainbow", "", nil] as [String?] {
            #expect(CharacterCatalog.isRainbowAing(other) == false, Comment(rawValue: "\(other ?? "nil")"))
        }
        // 두 판정이 서로를 삼키지 않는다.
        #expect(CharacterCatalog.isGoldAing("aing_rainbow") == false)
    }

    @Test("파일 매니페스트로는 aing_rainbow 를 못 싣는다 · 같은 id 를 넣어도 내장이 이긴다")
    func builtInWins() throws {
        let json = #"{"id":"aing_rainbow","displayName":"가짜 무지개","kind":"scene3D"}"#
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(CharacterManifest.self, from: Data(json.utf8))
        }
        let fake = CharacterManifest(id: "aing_rainbow", displayName: "가짜 무지개", kind: .sprite)
        let catalog = CharacterCatalog(manifests: [fake, CharacterManifest(id: "fox", displayName: "여우", kind: .sprite)])
        #expect(catalog.manifest(id: "aing_rainbow")?.kind == .scene3D)
        #expect(catalog.manifest(id: "aing_rainbow")?.displayName == "무지개 아잉이")
        #expect(catalog.allIDs == ["aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco", "fox"])
    }

    @MainActor
    @Test("선택·동기화: 무지개는 아는 캐릭터 — 저장되고 finish 가 .rainbow, 미보유면 동기화가 아잉으로 접는다")
    func selectionAndSyncKnowRainbow() {
        let defaults = CheckTestScratch.defaults("v0359-rainbow-select")
        let selection = CharacterSelection(defaults: defaults, catalog: CheckMascotAssets.catalog)
        #expect(selection.select("aing_rainbow"))
        #expect(selection.selectedID == "aing_rainbow")
        #expect(selection.selectedManifest.finish == .rainbow)
        #expect(selection.select("aing_prism") == false, "기준선: 모르는 id 는 거절")
        #expect(selection.selectedID == "aing_rainbow")

        let known: (String) -> Bool = { CheckMascotAssets.catalog.manifest(id: $0) != nil }
        #expect(CharacterSyncDecision.decide(serverID: "aing_rainbow", localID: "aing", migrated: true,
                                             isKnown: known, isUnlocked: { _ in true }) == .adopt("aing_rainbow"))
        #expect(CharacterSyncDecision.decide(serverID: "aing_rainbow", localID: "aing", migrated: true,
                                             isKnown: known, isUnlocked: { $0 != "aing_rainbow" }) == .keep)
        // 모르는 id 는 여전히 아잉(무지개가 그 규칙을 넓히지 않았다).
        #expect(CharacterSyncDecision.decide(serverID: "aing_prism", localID: "aing_rainbow", migrated: true,
                                             isKnown: known, isUnlocked: { _ in true }) == .adopt("aing"))
    }
}
