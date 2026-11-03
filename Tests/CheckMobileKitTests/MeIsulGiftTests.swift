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
//   ② 잠긴 칸: 이슬 칸은 '술 한잔 선물 전용'(캡션 · 안내 · 접근성 글) — 같은 상점의 케이크 칸은 그대로 '생일 선물 전용'(대표 결정
//      #d_zCowzb68KWlC "모두에게 잠긴 칸 (케이크와 같게)" — 안 가진 사람도 흐린 칸으로 본다 · 고르기엔 가진 사람에게만)
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

    // MARK: - ② 상점 · 고르기 잠긴 칸

    /// 능력 번호 5 의 서버 모양(`shop_state` — 이슬 행은 모두에게 · 값 2002 · gacha_only · gift_only, 케이크 둘 뒤).
    nonisolated static func shopJSON(ownsIsul: Bool, ownsStrawberry: Bool = false) -> String {
        #"""
        {"ruby_balance":5000,"characters":[
          {"id":"fox","price":60,"owned":true,"gacha_only":false,"gift_only":false},
          {"id":"aing_gold","price":1000,"owned":false,"gacha_only":true,"gift_only":false},
          {"id":"aing_cake_strawberry","price":2000,"owned":\#(ownsStrawberry),"gacha_only":true,"gift_only":true},
          {"id":"aing_cake_choco","price":2001,"owned":false,"gacha_only":true,"gift_only":true},
          {"id":"aing_isul","price":2002,"owned":\#(ownsIsul),"gacha_only":true,"gift_only":true}]}
        """#
    }

    @Test("타일 상태: 이슬 잠긴 칸은 '술 한잔 선물 전용' · 케이크 칸은 '생일 선물 전용' — 루비 값 · 반짝임이 아니다 · 접근성 글도 종류대로")
    func lockedTileCaptionByKind() {
        #expect(MeCharacterTileStatus.giftOnly(.drink).content == .locked("술 한잔 선물 전용"))
        #expect(MeCharacterTileStatus.giftOnly(.drink).content == .locked(DrinkGiftText.lockedCaption))
        #expect(MeCharacterTileStatus.giftOnly(.birthday).content == .locked(CakeGiftText.lockedCaption))
        #expect(MeCharacterTileStatus.giftOnly(.drink) != MeCharacterTileStatus.giftOnly(.birthday))
        if case .ruby = MeCharacterTileStatus.giftOnly(.drink).content { Issue.record("이슬 잠긴 칸이 루비 값(장식값 2002)을 말한다") }
        if case .acquire = MeCharacterTileStatus.giftOnly(.drink).content { Issue.record("이슬 잠긴 칸이 뽑기 길을 말한다") }
    }

    @Test("상점: 이슬 칸은 모두에게 잠긴 칸 — 값 · 구매 없음 · 누르면 '술 한잔 선물로만…' · 케이크 칸은 생일 안내 · 고르기엔 안 선다")
    func shopLockedIsulTile() async {
        let shop = BaseLockedBox(Self.shopJSON(ownsIsul: false))
        let harness = await RankMeHarness(label: "me-isul-shop") { request in
            switch request.rpcName {
            case "shop_state": return .json(shop.get())
            case "set_character": return .json(#"{"status":"not_owned"}"#)
            default: return nil
            }
        }
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadShop()
        #expect(store.shopRows.map(\.id).contains(Self.isul), "이슬 행이 상점 목록에 없다(모두에게 잠긴 칸)")
        #expect(!store.pickerIDs.contains(Self.isul), "안 가진 이슬이 고르기에 섰다: \(store.pickerIDs)")
        #expect(store.isGiftOnly(Self.isul) && !store.isGachaOnly(Self.isul), "이슬이 뽑기 전용으로 읽힌다")
        #expect(store.price(of: Self.isul) == nil, "장식값 2002 가 가격으로 섰다")
        #expect(store.giftKind(of: Self.isul) == .drink && store.giftKind(of: CharacterCatalog.cakeChocoAingID) == .birthday)
        // 서버 표식으로만 선물 전용인 모르는 id 는 생일(0.3.66 선례 — 맥 `giftCopy(for:)` 와 같다).
        #expect(store.giftKind(of: "aing_future_gift") == .birthday)
        store.selectShopItem(Self.isul)
        #expect(store.shopSelection == nil && store.shopGachaHintID == nil, "잠긴 칸이 사는 줄로 골라졌다")
        #expect(store.shopGiftHintID == Self.isul)
        #expect(store.shopNotice == DrinkGiftText.lockedHint && store.shopBarDetail == DrinkGiftText.lockedHint,
                "이슬 칸 안내가 \(store.shopNotice ?? "nil") 다")
        #expect(!store.canConfirmPurchase)
        // 기준선: 같은 상점의 케이크 칸은 생일 안내 그대로다(두 종류가 한 글자로 접히지 않는다).
        store.selectShopItem(CharacterCatalog.cakeChocoAingID)
        #expect(store.shopNotice == CakeGiftText.lockedHint)
        // 고르기에서 안 가진 이슬을 누르면(목록에 안 서지만 — 안전망) 술 안내이고 요청은 없다.
        store.chooseCharacter(Self.isul)
        #expect(store.characterNotice == DrinkGiftText.lockedHint)
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "buy_character").isEmpty && harness.requests(rpc: "set_character").isEmpty)
        // 가졌다고 읽었는데 서버가 not_owned(다른 기기 · 운영자 정리) — 그 종류의 안내로 말한다.
        shop.mutate { $0 = Self.shopJSON(ownsIsul: true) }
        await store.loadShop()
        #expect(store.pickerIDs.contains(Self.isul), "가진 이슬이 고르기에 없다: \(store.pickerIDs)")
        shop.mutate { $0 = Self.shopJSON(ownsIsul: false) }
        store.chooseCharacter(Self.isul)
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "set_character").count == 1)
        #expect(store.characterNotice == DrinkGiftText.lockedHint && store.isCharacterNoticeError)
        harness.expectNoForbiddenCalls()
    }

    @Test("뷰 배선: 상점 · 고르기 타일이 종류를 실어 잠긴 칸을 세우고 생일 글자를 박지 않는다 — 주석을 걷고 본다")
    func lockedTileWiring() throws {
        let views = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeCharacterViews.swift")
        #expect(views.components(separatedBy: "status = .giftOnly(store.giftKind(of: id))").count - 1 == 2,
                "상점 · 고르기 타일 둘 다 종류를 실어야 한다")
        #expect(views.contains("store.giftCopy(for: id).lockedCaption"), "고르기 잠긴 칸 접근성 글이 종류를 안 본다")
        #expect(!views.contains("CakeGiftText.lockedCaption"), "타일이 생일 캡션을 박았다 — 이슬 칸에 '생일 선물 전용'이 선다")
        let store = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeStoreCharacters.swift")
        #expect(!store.contains("CakeGiftText.lockedHint"), "상점 · 고르기 안내가 생일 글자를 박았다")
    }
}
