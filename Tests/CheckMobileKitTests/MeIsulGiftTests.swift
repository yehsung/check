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
//   ③ 받는 시트: 술 선물은 고르기 없이 이슬이 미리 골라진 채 · 문구 C("짠! 🥂" · [짠 받기]) · 수령 본문 · 실패 한 줄 · 다시 열기 줄(🥂 "짠! 선물이 왔어요" [받기])
//   ④ 다음 선물: 결론 난 시트가 내려간 뒤 스로틀 없이 한 번 더 묻는다(생일 → 술 차례로) — 번호 4 빌드는 묻지 않는다(기준선) · 안 끝난 시트는 묻지 않는다
//   ⑤ 종류 보존: 보유로 거른 새 선물 값은 언제나 종류를 싣는다(소스 — 술 선물은 선택지가 하나라 값으로는 그 길을 못 탄다)
//   ⑥ 데모: `me/gift/drink…` 장면(열린 술 선물 → 받기 → 이슬 보유 · 선물 없음) · 일반 상점 장면의 이슬 잠긴 칸 · 데모 글에 상표 글자 없음
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

    // MARK: - ③ 받는 시트(술 한잔)

    nonisolated static let drinkGiftID = "d0000000-0000-4000-8000-00000000d71c"
    nonisolated static let birthdayGiftID = "9f3c1b2a-0000-4000-8000-00000000ca4e"

    nonisolated static func drinkPendingJSON(id: String = drinkGiftID, note: String? = "오늘 한잔 어때요?") -> String {
        let noteJSON = note.map { "\"\($0)\"" } ?? "null"
        return #"{"status":"ok","gift":{"id":"\#(id)","kind":"drink","options":["aing_isul"],"note":\#(noteJSON),"created_at":"2026-11-03T09:00:00+00:00"}}"#
    }

    nonisolated static func birthdayPendingJSON(id: String = birthdayGiftID) -> String {
        #"{"status":"ok","gift":{"id":"\#(id)","kind":"birthday","options":["aing_cake_strawberry","aing_cake_choco"],"note":null,"created_at":"2026-11-03T08:00:00+00:00"}}"#
    }

    /// 선물 · 수령 · 상점 · 착용 응답 상자.
    final class Server: @unchecked Sendable {
        let pending = BaseLockedBox(MobileStubResponse.json(MeIsulGiftTests.drinkPendingJSON()))
        let claim = BaseLockedBox(MobileStubResponse.json(#"{"status":"ok","character_id":"aing_isul","replayed":false}"#))
        let shop = BaseLockedBox(MeIsulGiftTests.shopJSON(ownsIsul: false))

        func respond(_ request: MobileStubRequest) -> MobileStubResponse? {
            switch request.rpcName {
            case "character_gift_pending": return pending.get()
            case "claim_character_gift": return claim.get()
            case "shop_state": return .json(shop.get())
            case "set_character":
                let id = request.jsonBody["p_id"] as? String ?? ""
                return .json(#"{"status":"ok","character":"\#(id)"}"#)
            default: return nil
            }
        }
    }

    static func harness(_ label: String, server: Server) async -> RankMeHarness {
        await RankMeHarness(label: label) { server.respond($0) }
    }

    @Test("시트 값: 술 선물은 이슬이 미리 골라진 채(누르면 곧바로 받기) · 문구 C · 생일 선물은 하나 남아도 고르게 한다(1.0.14 그대로)")
    func drinkSheetPreselectsAndUsesCopyC() {
        let drink = CharacterGiftOffer(id: "g", options: [Self.isul], note: nil, createdAt: nil, kind: .drink)
        let sheet = MeCakeGiftSheet(gift: drink)
        #expect(sheet.selection == Self.isul && sheet.canConfirm, "술 선물 시트가 고른 것 없이 섰다 — [짠 받기]가 꺼진다")
        #expect(sheet.copy == .drink)
        #expect(sheet.copy.title == "짠! 🥂" && sheet.copy.confirmButton == "짠 받기")
        #expect(sheet.copy.body == "오늘도 고생 많았어요. 이슬 아잉이 한 병 받아요!")
        #expect(sheet.copy.received(name: MeCharacterName.display(Self.isul)) == "이슬 아잉이를 받았어요!")
        // 기준선: 생일 선물은 하나만 남아도 미리 고르지 않는다 · 문구는 생일 그대로.
        let cake = MeCakeGiftSheet(gift: CharacterGiftOffer(id: "c", options: [CharacterCatalog.cakeChocoAingID]))
        #expect(cake.selection == nil && !cake.canConfirm && cake.copy == .birthday)
        #expect(!sheet.isSettled && MeCakeGiftSheet(gift: drink, phase: .received(characterID: Self.isul)).isSettled
                && MeCakeGiftSheet(gift: drink, phase: .closed).isSettled && !MeCakeGiftSheet(gift: drink, phase: .claiming).isSettled)
    }

    @Test("술 선물: 번호 5 로 묻고 스스로 뜬다 · note 를 쥔다 · [짠 받기] = 이슬 · 번호 5 · 받은 뒤 상점 다시 읽기 · [지금 입기]는 기존 착용 경로")
    func drinkGiftClaimFlow() async throws {
        let server = Server()
        let h = await Self.harness("me-isul-claim", server: server)
        defer { h.tearDown() }
        let store = h.me
        store.appDidBecomeActive()
        await h.quiesceMe()
        let asked = try #require(h.requests(rpc: "character_gift_pending").first?.jsonBody)
        #expect(asked["p_protocol"] as? Int == ShopWire.devProtocol)
        let sheet = try #require(store.cakeGiftSheet, "열린 술 선물인데 시트가 안 섰다")
        #expect(sheet.gift.kind == .drink && sheet.gift.options == [Self.isul] && sheet.gift.note == "오늘 한잔 어때요?")
        #expect(sheet.selection == Self.isul && sheet.canConfirm && sheet.copy == .drink)
        store.cakeGiftSheetDidAppear()
        server.shop.mutate { $0 = Self.shopJSON(ownsIsul: true) }
        let shopBefore = h.requests(rpc: "shop_state").count
        store.confirmCakeGift()
        #expect(store.cakeGiftSheet?.phase == .claiming)
        await h.quiesceMe()
        let body = try #require(h.requests(rpc: "claim_character_gift").last?.jsonBody)
        #expect(Set(body.keys) == ["p_gift", "p_character", "p_protocol"])
        #expect(body["p_gift"] as? String == Self.drinkGiftID && body["p_character"] as? String == Self.isul
                && body["p_protocol"] as? Int == ShopWire.devProtocol, "\(body)")
        #expect(store.cakeGiftSheet?.phase == .received(characterID: Self.isul))
        #expect(store.isOwned(Self.isul) && store.cakeGift == nil && !store.showsCakeGiftReopen)
        #expect(h.requests(rpc: "shop_state").count == shopBefore + 1, "받은 뒤 상점을 다시 안 읽었다")
        #expect(store.pickerIDs.contains(Self.isul), "받은 이슬이 고르기에 없다")
        server.pending.mutate { $0 = .json(#"{"status":"ok"}"#) }
        store.wearReceivedCakeGift()
        #expect(store.cakeGiftSheet == nil)
        await h.quiesceMe()
        #expect(h.requests(rpc: "set_character").last?.jsonBody["p_id"] as? String == Self.isul)
        #expect(store.equippedCharacterID == Self.isul, "착용값이 아잉으로 접혔다 — 카드 표가 이슬을 모른다")
        h.expectNoForbiddenCalls()
    }

    @Test("술 선물 실패 · 다시 열기: 오프라인은 그 종류의 실패 한 줄 · 닫으면 🥂 '짠! 선물이 왔어요' [받기] · 생일 선물 줄은 🎂 그대로")
    func drinkGiftFailureAndReopenRow() async throws {
        let server = Server()
        server.claim.mutate { $0 = .networkFailure() }
        let h = await Self.harness("me-isul-reopen", server: server)
        defer { h.tearDown() }
        let store = h.me
        await store.loadCakeGift()
        store.cakeGiftSheetDidAppear()
        store.confirmCakeGift()
        await h.quiesceMe()
        #expect(store.cakeGiftSheet?.phase == .choosing && store.cakeGiftSheet?.notice == DrinkGiftText.claimFailed)
        #expect(store.cakeGiftSheet?.selection == Self.isul, "다시 누를 수 있게 이슬이 골라진 채여야 한다")
        let asked = h.requests(rpc: "character_gift_pending").count
        store.dismissCakeGiftSheet()
        store.cakeGiftSheetDidDisappear()
        await h.quiesceMe()
        #expect(h.requests(rpc: "character_gift_pending").count == asked, "안 끝난 시트를 닫았는데 다음 선물을 물었다")
        #expect(store.showsCakeGiftReopen && store.cakeGiftReopenKind == .drink)
        #expect(store.cakeGiftReopenKind.copy.reopenTitle == "짠! 선물이 왔어요" && store.cakeGiftReopenKind.copy.reopenButton == "받기")
        #expect(store.cakeGiftReopenKind.phoneReopenEmoji == "🥂")
        // [받기] — 서버에 다시 묻고 같은 선물로 연다(미리 골라진 채).
        store.reopenCakeGift()
        await h.quiesceMe()
        #expect(store.cakeGiftSheet?.gift.id == Self.drinkGiftID && store.cakeGiftSheet?.canConfirm == true)
        // 기준선: 생일 선물의 줄은 🎂 · 생일 글자 그대로.
        store.dismissCakeGiftSheet()
        server.pending.mutate { $0 = .json(Self.birthdayPendingJSON()) }
        await store.loadCakeGift()
        store.dismissCakeGiftSheet()
        #expect(store.cakeGiftReopenKind == .birthday && store.cakeGiftReopenKind.phoneReopenEmoji == "🎂")
        #expect(store.cakeGiftReopenKind.copy.reopenTitle == CakeGiftText.reopenTitle)
    }

    @Test("뷰 배선: 시트 · 다시 열기 줄의 글자는 선물 종류의 묶음에서 · 술 선물은 초대장 갈래 · 생일 글자를 박지 않는다 — 주석을 걷고 본다")
    func giftViewWiring() throws {
        let sheet = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeCakeGiftViews.swift")
        #expect(!sheet.contains("CakeGiftText."), "시트가 생일 글자를 박았다 — 술 선물에 '생일 축하해요! 🎂'가 선다")
        #expect(!sheet.contains("Text(\"🎂\")"), "다시 열기 줄 기호가 케이크로 박혔다")
        // 폰 1.0.18: 고를 것 없는 한 개 선물(술 한잔 · 빼빼로)이 초대장 갈래다 — 생일만 고르기.
        #expect(sheet.contains("if sheet.gift.kind != .birthday {") && sheet.contains("invite(sheet)"), "한 개 선물(술 · 빼빼로) 초대장 갈래가 없다")
        #expect(sheet.contains("store.cakeGiftReopenKind.copy.reopenTitle") && sheet.contains("store.cakeGiftReopenKind.phoneReopenEmoji"))
        #expect(sheet.contains("sheet.copy.confirmButton"), "확인 단추가 종류의 글자를 안 쓴다(술 = [짠 받기])")
    }

    // MARK: - ④ 다음 선물

    @Test("다음 선물: 생일을 받고 시트가 내려간 뒤 스로틀 없이 한 번 더 묻는다 → 술 선물 시트가 스스로 뜬다 · 내려가기 전엔 묻지 않는다")
    func followUpAfterSettledSheetDisappears() async throws {
        let server = Server()
        server.pending.mutate { $0 = .json(Self.birthdayPendingJSON()) }
        server.claim.mutate { $0 = .json(#"{"status":"ok","character_id":"aing_cake_strawberry","replayed":false}"#) }
        let h = await Self.harness("me-isul-followup", server: server)
        defer { h.tearDown() }
        let store = h.me
        await store.loadCakeGift()
        #expect(store.cakeGiftSheet?.gift.kind == .birthday)
        store.cakeGiftSheetDidAppear()
        store.selectCakeGiftOption(CharacterCatalog.cakeStrawberryAingID)
        // 서버: 생일을 받으면 다음으로 열린 술 선물이 보인다.
        server.pending.mutate { $0 = .json(Self.drinkPendingJSON()) }
        server.shop.mutate { $0 = Self.shopJSON(ownsIsul: false, ownsStrawberry: true) }
        store.confirmCakeGift()
        await h.quiesceMe()
        #expect(store.cakeGiftSheet?.phase == .received(characterID: CharacterCatalog.cakeStrawberryAingID))
        let before = h.requests(rpc: "character_gift_pending").count
        store.dismissCakeGiftSheet()
        await h.quiesceMe()
        #expect(h.requests(rpc: "character_gift_pending").count == before, "시트가 내려가기도 전에 다음 선물을 물었다(겹쳐 띄우기)")
        #expect(store.cakeGiftFollowUpPending)
        store.cakeGiftSheetDidDisappear()
        await h.quiesceMe()
        #expect(h.requests(rpc: "character_gift_pending").count == before + 1, "결론 난 시트가 내려갔는데 다음 선물을 안 물었다(10분 스로틀 안)")
        let next = try #require(store.cakeGiftSheet, "다음 선물(술) 시트가 스스로 안 섰다")
        #expect(next.gift.id == Self.drinkGiftID && next.gift.kind == .drink && next.canConfirm)
        #expect(!store.cakeGiftFollowUpPending)
        h.expectNoForbiddenCalls()
    }

    @Test("다음 선물 기준선: 번호 4 빌드(이슬 초상 없음)는 결론 난 시트가 내려가도 다시 묻지 않는다 — 다시 열기 줄도 없다")
    func noFollowUpOnProtocolFour() async throws {
        let server = Server()
        server.pending.mutate { $0 = .json(Self.birthdayPendingJSON()) }
        server.claim.mutate { $0 = .json(#"{"status":"ok","character_id":"aing_cake_strawberry","replayed":false}"#) }
        let h = await Self.harness("me-isul-followup-p4", server: server)
        defer { h.tearDown() }
        let store = h.me
        store.drawableCharacterIDs = AingCharacterArt.knownIDs.filter { $0 != Self.isul }
        #expect(store.shopProtocolVersion == ShopWire.cakeProtocol, "전제: 번호 4")
        await store.loadCakeGift()
        store.cakeGiftSheetDidAppear()
        store.selectCakeGiftOption(CharacterCatalog.cakeStrawberryAingID)
        server.pending.mutate { $0 = .json(Self.drinkPendingJSON()) }
        store.confirmCakeGift()
        await h.quiesceMe()
        #expect(h.requests(rpc: "claim_character_gift").last?.jsonBody["p_protocol"] as? Int == ShopWire.cakeProtocol)
        let before = h.requests(rpc: "character_gift_pending").count
        store.dismissCakeGiftSheet()
        store.cakeGiftSheetDidDisappear()
        await h.quiesceMe()
        #expect(h.requests(rpc: "character_gift_pending").count == before, "번호 4 빌드가 '다음 선물'을 물었다(0.3.66~ 요청 수가 늘었다)")
        #expect(store.cakeGiftSheet == nil && !store.showsCakeGiftReopen)
    }

    @Test("다음 선물: 시트 없이 결론 나면(받는 사이 내려감) 그 자리에서 묻는다 · 계정이 바뀌면 깃발을 비운다")
    func followUpWhenNoSheetAndReset() async throws {
        let server = Server()
        let h = await Self.harness("me-isul-followup-nosheet", server: server)
        defer { h.tearDown() }
        let store = h.me
        await store.loadCakeGift()
        // 시트가 화면에 서지 못하고(다른 시트가 떠 있었다) 거둬졌다 — 선물만 안다.
        store.dismissCakeGiftSheet()
        #expect(store.cakeGiftSheet == nil && store.cakeGift?.kind == .drink)
        server.pending.mutate { $0 = .json(#"{"status":"ok"}"#) }
        server.shop.mutate { $0 = Self.shopJSON(ownsIsul: true) }
        let before = h.requests(rpc: "character_gift_pending").count
        await store.applyCakeGiftClaim(.received(characterID: Self.isul, replayed: false), giftID: Self.drinkGiftID,
                                       generation: store.context.generation)
        await h.quiesceMe()
        #expect(h.requests(rpc: "character_gift_pending").count == before + 1, "시트 없이 결론 났는데 다음 선물을 안 물었다")
        #expect(store.cakeGift == nil && store.isOwned(Self.isul))
        store.cakeGiftFollowUpPending = true
        store.reset()
        #expect(!store.cakeGiftFollowUpPending)
    }

    // MARK: - ⑤ 종류 보존

    @Test("종류 보존: 스토어가 선물 값을 새로 만드는 자리는 언제나 kind 를 싣는다 — 주석을 걷고 본다")
    func offerRebuildsCarryKind() throws {
        let code = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeStoreCakeGift.swift")
        var calls: [String] = []
        var rest = Substring(code)
        while let start = rest.range(of: "CharacterGiftOffer(") {
            var depth = 0
            var end = start.upperBound
            var index = start.lowerBound
            while index < rest.endIndex {
                let ch = rest[index]
                if ch == "(" { depth += 1 }
                if ch == ")" { depth -= 1; if depth == 0 { end = rest.index(after: index); break } }
                index = rest.index(after: index)
            }
            calls.append(String(rest[start.lowerBound..<end]))
            rest = rest[end...]
        }
        #expect(calls.count >= 2, "선물 값을 새로 만드는 자리를 못 찾았다: \(calls)")
        for call in calls {
            #expect(call.contains("kind:"), "종류 없이 선물 값을 만든다(술 선물이 생일로 읽혀 사라진다): \(call)")
        }
    }

    // MARK: - ⑥ 데모 픽스처

    static func demoRequest(_ rpc: String, body: String) -> MobileStubRequest {
        MobileStubRequest(method: "POST", host: MobileDemo.host, path: "/rest/v1/rpc/\(rpc)", query: "", headers: [:], bodyText: body)
    }

    @Test("데모 me/gift/drink…: 바늘로 열린 술 선물(이슬 하나 · 운영자 한 줄) · 받으면 이슬만 보유 · 선물 없음 · [지금 입기]는 이슬 · 생일 장면은 그대로")
    func demoDrinkGiftRoute() throws {
        let fixtures = MeCakeGiftTests.fixtures
        let decoder = MeCakeGiftTests.snakeDecoder
        #expect(MobileDemoCakeGiftRoute(demoRoute: "me/gift/drink") == MobileDemoCakeGiftRoute(action: nil, kind: .drink))
        #expect(MobileDemoCakeGiftRoute(demoRoute: "/me/gift/drink/received/") == MobileDemoCakeGiftRoute(action: "received", kind: .drink))
        #expect(MobileDemoCakeGiftRoute(demoRoute: "me/gift/drink/dismissed")?.action == "dismissed")
        #expect(MobileDemoCakeGiftRoute(demoRoute: "me/gift/received")?.kind == .birthday, "생일 장면이 술로 읽혔다")
        let route = try #require(MobileDemoCakeGiftRoute(demoRoute: "me/gift/drink"))
        #expect(route.needle == MobileDemoCakeGiftRoute.drinkNeedle && AingRoute(path: route.openRoute) != nil)
        let pendingBody = #"{"p_protocol":5}"#
        let ledger = route.makeLedger()
        #expect(ledger.needle == "demo-drink")
        let pending = fixtures.response(for: route.rewrite(Self.demoRequest("character_gift_pending", body: pendingBody), ledger: ledger),
                                        scenario: route.scene)
        let offer = try #require(try decoder.decode(CharacterGiftPendingResponse.self, from: pending.body).offer, "술 장면에 열린 선물이 없다")
        #expect(offer.kind == .drink && offer.options == [Self.isul] && offer.note != nil)
        // 받기 전 상점(일반 _me — 이슬은 잠긴 칸): 서버가 만들 수 있는 상태(가진 이슬에게 술 선물을 주지 않는다).
        let shopRequest = Self.demoRequest("shop_state", body: pendingBody)
        let before = try decoder.decode(ShopStateResponse.self, from: fixtures.response(for: route.rewrite(shopRequest, ledger: ledger),
                                                                                         scenario: route.scene).body)
        #expect(before.characters?.first { $0.id == Self.isul }?.owned == false, "술 장면(받기 전)에 이미 이슬이 있다")
        // 받기 → 받은 뒤 바늘.
        let claimRequest = Self.demoRequest("claim_character_gift",
                                            body: #"{"p_gift":"\#(offer.id)","p_character":"aing_isul","p_protocol":5}"#)
        let claim = fixtures.response(for: route.rewrite(claimRequest, ledger: ledger), scenario: route.scene)
        let claimed = try decoder.decode(CharacterGiftClaimResponse.self, from: claim.body)
        #expect(CharacterGiftClaimOutcome(response: claimed, requestedID: Self.isul) == .received(characterID: Self.isul, replayed: false))
        ledger.record(claimRequest, response: claim)
        #expect(ledger.needle == "demo-drink-got")
        let after = try decoder.decode(ShopStateResponse.self, from: fixtures.response(for: route.rewrite(shopRequest, ledger: ledger),
                                                                                        scenario: route.scene).body)
        #expect(after.characters?.first { $0.id == Self.isul }?.owned == true, "받은 뒤 상점에 이슬 보유가 없다")
        let pendingAfter = fixtures.response(for: route.rewrite(Self.demoRequest("character_gift_pending", body: pendingBody), ledger: ledger),
                                             scenario: route.scene)
        #expect(try decoder.decode(CharacterGiftPendingResponse.self, from: pendingAfter.body).offer == nil, "받은 뒤에도 술 선물이 열려 있다")
        let wear = fixtures.response(for: route.rewrite(Self.demoRequest("set_character", body: #"{"p_id":"aing_isul"}"#), ledger: ledger),
                                     scenario: route.scene)
        #expect(try decoder.decode(SetCharacterResponse.self, from: wear.body).character == Self.isul)
        let other = fixtures.response(for: route.rewrite(Self.demoRequest("set_character", body: #"{"p_id":"fox"}"#), ledger: ledger),
                                      scenario: route.scene)
        #expect(try decoder.decode(SetCharacterResponse.self, from: other.body).character != Self.isul, "받은 뒤 바늘이 여우 착용을 이슬로 가로챘다")
        // 생일 기록은 이슬 수령을 적지 않는다(종류마다 기록이 따로다) · 술 기록은 케이크 수령을 적지 않는다.
        let birthdayLedger = MobileDemoCakeGiftRoute.Ledger()
        birthdayLedger.record(claimRequest, response: claim)
        #expect(birthdayLedger.needle == MobileDemoCakeGiftRoute.needle)
        let drinkLedger = MobileDemoCakeGiftRoute.Ledger(kind: .drink)
        drinkLedger.record(claimRequest, response: .json(#"{"status":"ok","character_id":"aing_cake_choco"}"#))
        #expect(drinkLedger.needle == MobileDemoCakeGiftRoute.drinkNeedle)
    }

    @Test("데모 글에 상표 글자('참이슬')가 없다 — 픽스처 · 폰이 링크하는 코드(코어 포함) · 스토어 문서 · 게시 문서 · 랜딩(그림 라벨에만 있다 · 대표 결정 #d_dk4IjWRZvFYR)")
    func noTrademarkTextInDemoOrStoreCopy() throws {
        let mark = "참" + "이슬"
        for entry in MeCakeGiftTests.fixtures.entries {
            #expect(!String(decoding: entry.data, as: UTF8.self).contains(mark), "\(entry.relativePath) 에 상표 글자가 있다")
        }
        // 코어(`Sources/CheckCore`)도 본다(검토 지적) — 받는 창 · 잠긴 칸 문구(`DrinkGiftText`)가 거기서 오고 폰 화면에 그대로 선다.
        for relative in ["Sources/CheckMobileKit", "Sources/CheckMobileShared", "Sources/CheckWidgetsKit", "Sources/CheckCore"] {
            #expect(try IntegrationContractTests.files(containing: [mark], under: relative).isEmpty, "\(relative) 코드에 상표 글자가 있다")
        }
        // 사람이 읽는 게시물: 스토어 문서 · GitHub Pages 로 게시되는 처리방침 · 약관 · 첫 화면, 그리고 랜딩(지원 URL 이 가리키는 곳)의 글.
        for relative in Self.publishedTextFiles() {
            let text = try String(contentsOf: MeIsulProtocolPinTests.root.appendingPathComponent(relative), encoding: .utf8)
            #expect(!text.contains(mark), "\(relative) 에 상표 글자가 있다(스토어 · 게시 글)")
        }
    }

    /// 상표 글자 그물이 훑는 게시 글 파일(저장소 루트 기준). 랜딩은 화면을 짓는 폴더(app · components · lib · data)의 글 파일만 —
    /// node_modules · .next 같은 산출물은 저장소에 없거나 훑지 않는다. 빈 목록이면 그물이 아무것도 안 잰다(아래 시험이 막는다).
    static func publishedTextFiles() -> [String] {
        let root = MeIsulProtocolPinTests.root
        var out = ["docs/appstore.md", "docs/privacy.md", "docs/terms.md", "docs/index.md"]
            .filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
        let textExtensions: Set<String> = ["ts", "tsx", "js", "mjs", "json", "md", "mdx", "css", "html", "txt"]
        for folder in ["landing/app", "landing/components", "landing/lib", "landing/data"] {
            guard let walker = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: [.isRegularFileKey])
            else { continue }
            for case let url as URL in walker {
                if url.lastPathComponent == "node_modules" || url.lastPathComponent == ".next" { walker.skipDescendants(); continue }
                // 폴더 이름이 글 파일 꼴일 수 있다(Next.js 경로 `app/llms.txt/` 는 폴더다) — 보통 파일만.
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                      textExtensions.contains(url.pathExtension.lowercased()) else { continue }
                out.append(String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1)))
            }
        }
        return out.sorted()
    }

    @Test("상표 글자 그물의 게시 글 목록이 비지 않았다 — 처리방침 · 스토어 문서 · 랜딩 화면 글이 실제로 들어 있다(기준선)")
    func trademarkNetCoversPublishedText() {
        let files = Self.publishedTextFiles()
        #expect(files.contains("docs/privacy.md") && files.contains("docs/appstore.md"), "처리방침 · 스토어 문서를 안 훑는다: \(files.prefix(5))")
        #expect(files.contains { $0.hasPrefix("landing/app/") && $0.hasSuffix(".tsx") }, "랜딩 화면 글을 안 훑는다")
        #expect(files.contains("landing/app/delete-account/page.tsx"), "계정 삭제 안내(처리방침 짝)를 안 훑는다")
    }

    @Test("스토어 문서 §3: 이슬을 그리는 빌드면 '술·담배·약물' 칸은 드묾(대표 결정 원문 #d_E3bxq1b2jSsS) · 다른 칸이 약물을 '없음'으로 겹쳐 말하지 않는다")
    func ageRatingRowFollowsIsul() throws {
        #expect(AingCharacterArt.knownIDs.contains(Self.isul), "전제: 이 번들은 이슬을 그린다")
        let doc = try AppStoreDocContractTests.document("docs/appstore.md")
        let survey = try AppStoreDocContractTests.section(of: doc, heading: "## 3. 연령 등급 설문 예상 답")
        let alcohol = try AppStoreDocContractTests.row(in: survey, containing: "술·담배·약물 사용 또는 언급")
        #expect(alcohol[1].contains("드묾") && !alcohol[1].contains("없음 |"), "술 칸 답: \(alcohol[1])")
        #expect(alcohol[2].contains("#d_E3bxq1b2jSsS") && alcohol[2].contains(DrinkGiftText.lockedCaption), "술 칸 근거: \(alcohol[2])")
        let lumped = survey.split(separator: "\n").filter { $0.contains("| 없음 |") && $0.contains("약물") }
        #expect(lumped.isEmpty, "다른 줄이 약물을 '없음'으로 답한다 — 설문 답이 둘로 갈린다: \(lumped)")
    }
}
