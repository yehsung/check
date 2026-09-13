import Foundation
import Testing
@testable import check

/// 번들에 실린 캐릭터 **명단**이 바뀌면 여기서 한 번에 걸린다.
///
/// **왜 필요한가**(2026-09-13): 임시 픽스처(`fox`·`bot`)를 실제 5종으로 교체했더니 **테스트 9개 파일
/// 71곳**이 한꺼번에 빨개졌다. 이름이 그만큼 여러 곳에 흩어져 있었기 때문이다. 다음 명단 변경에서
/// 같은 일을 겪지 않도록, "번들에 무엇이 있는가"를 **이 파일 하나가** 못 박는다 — 여기가 먼저 빨개지면
/// 나머지 실패가 전부 같은 원인임을 바로 안다.
///
/// ⚠️ 이 명단은 **서버 CHECK 제약**(`profiles_character_valid`)과 같아야 한다. 서버가 모르는 id 를
/// 착용하려 하면 `set_character` 가 `unknown_character` 를 돌려주고, 앱 번들에만 있는 캐릭터는
/// 고를 수는 있어도 **저장되지 않는다**. 반대로 서버에만 있으면 클라가 아잉으로 접는다(안 죽는다).
@Suite("v0.3.15 캐릭터 명단 계약")
struct V0316RosterContractTests {

    /// 번들에 있어야 하는 스프라이트 캐릭터. 아잉은 내장 3D 라 여기 없다.
    static let bundledSprites = ["shiba", "panda", "rabbit", "slime", "dragon"]

    @MainActor
    @Test("번들 명단이 기대와 정확히 같다")
    func bundledRosterMatches() {
        let catalog = CharacterCatalog.load(bundle: CheckResources.bundle)
        let sprites = catalog.allIDs.filter { catalog.manifest(id: $0)?.kind == .sprite }
        let detail = "번들 명단이 바뀌었다 — 있는 것 \(sprites.sorted()), 기대 \(Self.bundledSprites.sorted()). "
            + "서버 CHECK(profiles_character_valid)와 이 목록을 함께 고쳐라."
        #expect(Set(sprites) == Set(Self.bundledSprites), Comment(rawValue: detail))
        // 아잉은 언제나 첫 번째이고 3D 다.
        #expect(catalog.allIDs.first == CharacterCatalog.builtInAingID)
        #expect(catalog.manifest(id: CharacterCatalog.builtInAingID)?.kind == .scene3D)
    }

    @MainActor
    @Test("임시 픽스처는 번들에서 사라졌다")
    func temporaryFixturesAreGone() {
        let catalog = CharacterCatalog.load(bundle: CheckResources.bundle)
        for stale in ["fox", "bot"] {
            #expect(catalog.manifest(id: stale) == nil,
                    "임시 픽스처 \(stale) 가 아직 번들에 있다 — 화풍 확정 전 에셋이다")
        }
    }

    @MainActor
    @Test("모든 번들 캐릭터가 픽셀아트로 표시된다")
    func allBundledArePixelArt() {
        // 화풍 확정(2026-09-13): 픽셀아트. 이 깃발이 꺼지면 재질 필터가 .linear 로 떨어져 격자가 뭉개진다.
        let catalog = CharacterCatalog.load(bundle: CheckResources.bundle)
        for id in Self.bundledSprites {
            #expect(catalog.manifest(id: id)?.pixelArt == true,
                    "\(id) 에 pixelArt 플래그가 없다 — 팩 스크립트에 --pixel-art 를 빠뜨렸다")
        }
    }
}
