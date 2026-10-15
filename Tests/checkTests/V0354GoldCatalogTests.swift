import Foundation
import Testing
@testable import check
@testable import CheckCore

/// v0.3.54 황금 아잉이 — 카탈로그 내장 항목과 렌더러가 금 변형을 알아보는 길.
///
/// 지키는 것:
///  ① 번들이 비어도 금이 있다(아잉과 같은 내장 안전망) · 순서는 아잉 → 황금 → 나머지 정렬.
///  ② 렌더러는 `finish` 로 금을 가른다 — `kind` 는 아잉과 같은 `.scene3D` 라 kind 로 가르면 금 착용자 화면에 보라 아잉이 선다.
///  ③ 파일 매니페스트로는 금을 못 싣는다(밑줄 id 거절) — 그래서 내장이어야 한다. 파일 쪽이 같은 id 를 실어도 내장이 이긴다.
///  ④ 선택·동기화가 금을 "아는 캐릭터"로 다룬다(모르는 id → 아잉 접기에 걸리지 않는다) — 소유 판정은 그대로 서버가 한다.
@Suite("v0.3.54 황금 아잉이 카탈로그")
struct V0354GoldCatalogTests {

    @Test("번들이 비어도 황금 아잉이가 있다 — 아잉과 같은 3D · 이름 '황금 아잉이' · 아틀라스·초상·폴더 없음")
    func goldIsBuiltIn() {
        let empty = CharacterCatalog.load(charactersDirectory: nil)
        #expect(empty.allIDs == ["aing", "aing_gold"])
        let gold = empty.manifest(id: "aing_gold")
        #expect(gold?.displayName == "황금 아잉이")
        #expect(gold?.kind == .scene3D)
        #expect(gold?.atlas == nil && gold?.portrait == nil)
        #expect(empty.entry(id: "aing_gold")?.directory == nil)
        #expect(empty.atlasURL(for: "aing_gold") == nil)
        #expect(CharacterCatalog.builtIns.map(\.id) == ["aing", "aing_gold"])
        #expect(CharacterCatalog.goldAingID == "aing_gold")
    }

    @MainActor
    @Test("실제 번들: 아잉 → 황금 아잉이 → 나머지(id 정렬) — 스프라이트 6종은 그대로")
    func bundledOrder() {
        let ids = CheckMascotAssets.catalog.allIDs
        #expect(Array(ids.prefix(2)) == ["aing", "aing_gold"])
        let rest = Array(ids.dropFirst(2))
        #expect(rest == rest.sorted())
        #expect(Set(rest) == ["fox", "ghost", "jellyfish", "robot", "shiba", "squirrel"], Comment(rawValue: "\(rest)"))
        // 3D 경로가 쓰는 카탈로그(별도 인스턴스)도 같은 목록이다.
        #expect(CheckCharacter3DScene.catalog.allIDs == ids)
    }

    @Test("finish: 황금만 .gold — 아잉·스프라이트·모르는 id 는 .standard (kind 로는 못 가른다)")
    func finishSeparatesGoldFromAing() {
        let catalog = CheckMascotAssets.catalog
        let aing = catalog.manifest(id: "aing")
        let gold = catalog.manifest(id: "aing_gold")
        #expect(aing?.kind == gold?.kind, "전제: 둘 다 scene3D — kind 로는 못 가른다")
        #expect(gold?.finish == .gold)
        #expect(aing?.finish == .standard)
        for id in ["fox", "ghost", "jellyfish", "robot", "shiba", "squirrel"] {
            #expect(catalog.manifest(id: id)?.finish == .standard, "\(id)")
        }
        #expect(CharacterCatalog.isGoldAing("aing_gold"))
        for other in ["aing", "AING_GOLD", "aing-gold", " aing_gold", "", nil] as [String?] {
            #expect(CharacterCatalog.isGoldAing(other) == false, Comment(rawValue: "\(other ?? "nil")"))
        }
    }

    /// 파일 매니페스트의 id 문법(`[a-z0-9-]`)은 밑줄을 거절한다 — 그래서 금은 내장이어야 한다. 그리고 메모리 카탈로그가
    /// 같은 id 의 가짜(스프라이트)를 넣어도 내장 3D 가 이긴다(아잉과 같은 규칙).
    @Test("파일 매니페스트로는 aing_gold 를 못 싣는다 · 같은 id 를 넣어도 내장이 이긴다")
    func builtInWins() throws {
        let json = #"{"id":"aing_gold","displayName":"가짜 금","kind":"scene3D"}"#
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(CharacterManifest.self, from: Data(json.utf8))
        }
        let fake = CharacterManifest(id: "aing_gold", displayName: "가짜 금", kind: .sprite)
        let catalog = CharacterCatalog(manifests: [fake, CharacterManifest(id: "fox", displayName: "여우", kind: .sprite)])
        #expect(catalog.manifest(id: "aing_gold")?.kind == .scene3D)
        #expect(catalog.manifest(id: "aing_gold")?.displayName == "황금 아잉이")
        #expect(catalog.allIDs == ["aing", "aing_gold", "fox"])
    }

    /// 선택은 카탈로그가 아는 id 만 저장한다 — 금이 내장이므로 저장된다(모르는 id 는 거절 · 아잉 접기 그대로).
    /// 소유 판정은 여기서 하지 않는다: 동기화(`CharacterSyncDecision`)가 서버 보유로 다시 접는다.
    @MainActor
    @Test("선택·동기화: 금은 아는 캐릭터 — 저장되고, 미보유면 동기화가 아잉으로 접는다")
    func selectionAndSyncKnowGold() {
        let defaults = CheckTestScratch.defaults("v0354-gold-select")
        let selection = CharacterSelection(defaults: defaults, catalog: CheckMascotAssets.catalog)
        #expect(selection.select("aing_gold"))
        #expect(selection.selectedID == "aing_gold")
        #expect(selection.selectedManifest.finish == .gold)
        // 기준선: 모르는 id 는 거절된다(같은 함수가 다른 답을 낸다).
        #expect(selection.select("dragon") == false)
        #expect(selection.selectedID == "aing_gold")

        let known: (String) -> Bool = { CheckMascotAssets.catalog.manifest(id: $0) != nil }
        // 서버가 금을 입었다고 말한다 + 가졌다 → 받아들인다(모르는 id 로 접지 않는다).
        #expect(CharacterSyncDecision.decide(serverID: "aing_gold", localID: "aing", migrated: true,
                                             isKnown: known, isUnlocked: { _ in true }) == .adopt("aing_gold"))
        // 기준선: 안 가졌다(상점 목록에 owned 가 없다) → 아잉으로 접는다 — 같은 id 가 소유에 따라 다른 답을 낸다.
        #expect(CharacterSyncDecision.decide(serverID: "aing_gold", localID: "aing", migrated: true,
                                             isKnown: known, isUnlocked: { $0 != "aing_gold" }) == .keep)
        // 모르는 id 는 여전히 아잉(금이 그 규칙을 넓히지 않았다).
        #expect(CharacterSyncDecision.decide(serverID: "aing_platinum", localID: "aing_gold", migrated: true,
                                             isKnown: known, isUnlocked: { _ in true }) == .adopt("aing"))
    }
}
