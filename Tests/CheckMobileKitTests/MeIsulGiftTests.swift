@testable import CheckCore
import CheckMobileShared
import CoreGraphics
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 **이슬 아잉이 · '술 한잔' 선물**(맥 0.3.74 먼저 → 폰 1.0.17)의 계약.
//
// 폰 뷰(상점 타일 · 받는 시트 · 다시 열기 줄 · 아바타)는 `#if os(iOS)` 라 맥 스위트가 못 본다. 그래서 화면이 가르는 판정을 플랫폼 무관한
// 자리(`AingCharacterArt.avatarFraming` · `MeCharacterTileStatus` · `MeStoreCakeGift` · `MeCakeGiftSheet`)에 두었고 여기서 **값**과
// **실제 요청**으로 잰다(케이크 `MeCakeGiftTests` 와 같은 틀). 번호 5 자체는 `MeIsulProtocolPinTests` 가 잰다.
//
//   ① 아바타 틀: 이슬 초상을 틀로 되돌리면 몸이 아잉 몸과 겹친다 · 케이크 값을 그대로 쓰면 안 겹친다(기준선이 다르다)
@MainActor
@Suite struct MeIsulGiftTests {
    nonisolated static let isul = CharacterCatalog.isulAingID

    // MARK: - ① 아바타 틀(얼굴 크기)

    @Test("아바타 틀: 이슬 초상을 틀로 되돌리면 몸이 아잉 몸과 겹친다 — 케이크 값(28px)으로는 안 겹친다")
    func isulAvatarFramingMatchesAingBody() throws {
        let framing = AingCharacterArt.avatarFraming(id: Self.isul)
        #expect(framing.scale > 1.1 && framing.scale < 1.2, "이슬은 키워야 한다(0.88 축소를 되돌린다): \(framing)")
        #expect(framing.offsetY < 0, "이슬은 몸을 위로 올려야 한다: \(framing)")
        #expect(AingCharacterArt.avatarFraming(id: " \(Self.isul) ") == framing, "착용값 접기와 같은 규칙")
        // 케이크 자리로 그린 틀 — 같은 0.88 배율이지만 몸 자리가 다르다(이슬 뚜껑은 케이크 장식보다 낮다).
        let cakeTop = AingCharacterArt.cakePortraitBodyTop, s = AingCharacterArt.cakePortraitBodyScale
        let side = Double(AingCharacterArt.portraitPixelSize)
        let cakeFraming = AingCharacterArt.AvatarFraming(scale: 1 / s, offsetY: ((side / 2 - cakeTop) / s - side / 2) / side)
        #expect(cakeFraming != framing, "이슬 틀이 케이크 틀과 같다 — 이슬 몸 자리를 따로 재지 않았다")
        for expression in AingCharacterArt.Expression.allCases {
            let aing = try #require(AingCharacterArt.portraitImage(id: "aing", expression: expression))
            let image = try #require(AingCharacterArt.portraitImage(id: Self.isul, expression: expression))
            let reference = MeCakeGiftTests.bodyShape(try MeCakeGiftTests.framedAlpha(aing, framing: .identity))
            let framed = MeCakeGiftTests.bodyShape(try MeCakeGiftTests.framedAlpha(image, framing: framing))
            let raw = MeCakeGiftTests.bodyShape(try MeCakeGiftTests.framedAlpha(image, framing: .identity))
            let asCake = MeCakeGiftTests.bodyShape(try MeCakeGiftTests.framedAlpha(image, framing: cakeFraming))
            // 기준선 둘: 틀 없는 이슬은 아잉보다 좁고(0.88), 케이크 틀로 되돌린 이슬은 아래 끝이 아잉과 어긋난다.
            #expect(abs(raw.widest - reference.widest) > 10, "틀 없는 이슬이 이미 아잉 폭이다 — 생성기 배치가 바뀌었다(\(raw) vs \(reference))")
            #expect(abs(asCake.bottom - reference.bottom) > 6, "케이크 틀로도 이슬 몸이 아잉과 겹친다 — 이 시험이 자리를 못 가른다(\(asCake) vs \(reference))")
            #expect(abs(framed.widest - reference.widest) <= 3, "이슬-\(expression): 틀 뒤 \(framed) · 아잉 \(reference)")
            #expect(abs(framed.bottom - reference.bottom) <= 2, "이슬-\(expression): 틀 뒤 \(framed) · 아잉 \(reference)")
            #expect(abs(framed.widestY - reference.widestY) <= 6, "이슬-\(expression): 틀 뒤 \(framed) · 아잉 \(reference)")
        }
    }
}
