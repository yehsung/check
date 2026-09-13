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
@Suite("v0.3.16 캐릭터 명단 계약")
struct V0316RosterContractTests {

    /// 번들에 있어야 하는 스프라이트 캐릭터. 아잉은 내장 3D 라 여기 없다.
    ///
    /// 화풍 교체(2026-09-13 오후, 사용자): 픽셀아트 5종(시바·판다·토끼·슬라임·드래곤)을 버리고
    /// **글로시 3D 토이 렌더** 5종으로 갈았다. 시바만 이름이 남았고 에셋은 새로 구웠다.
    static let bundledSprites = ["shiba", "squirrel", "ghost", "jellyfish", "fox"]

    /// 이제는 번들에 없어야 하는 이름. 임시 픽스처 + 픽셀아트 라운드에서 빠진 4종.
    /// (`fox` 는 한때 임시 픽스처였지만 지금은 **정식 캐릭터**다 — 여기 넣지 마라.)
    static let retiredIDs = ["bot", "panda", "rabbit", "slime", "dragon"]

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
    @Test("물러난 캐릭터는 번들에서 사라졌다")
    func retiredCharactersAreGone() {
        let catalog = CharacterCatalog.load(bundle: CheckResources.bundle)
        for stale in Self.retiredIDs {
            #expect(catalog.manifest(id: stale) == nil,
                    "물러난 캐릭터 \(stale) 가 아직 번들에 있다 — Sources/check/Characters 에서 지워라")
        }
    }

    @MainActor
    @Test("번들 캐릭터는 픽셀아트가 아니다(글로시 3D)")
    func bundledAreNotPixelArt() {
        // 화풍 교체(2026-09-13 오후): 글로시 3D 토이 렌더. `pixelArt` 가 켜지면 재질 필터가
        // `.nearest` 로 떨어져(SpriteCharacterNode) 부드러운 그라디언트가 계단으로 깨지고,
        // 초상 보간도 `.none` 으로 가서 메뉴바 18pt 에서 얼굴이 뭉개진다.
        // 깃발 자체는 살려 둔다 — 나중에 픽셀아트 캐릭터를 다시 넣을 때 쓰는 기구다.
        let catalog = CharacterCatalog.load(bundle: CheckResources.bundle)
        for id in Self.bundledSprites {
            #expect(catalog.manifest(id: id)?.pixelArt != true,
                    "\(id) 에 pixelArt 가 켜져 있다 — 팩 스크립트에 --pixel-art 를 잘못 넘겼다")
        }
    }
}
