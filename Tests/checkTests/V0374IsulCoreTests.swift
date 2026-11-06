import Foundation
import Testing
@testable import check
@testable import CheckCore

/// v0.3.74 이슬 아잉이('술 한잔' 선물 전용) — 공용 코어(설계서 §1 · §2 · §3 · §5).
///
/// 지키는 것:
///  ① 카탈로그: `aing_isul` · "이슬 아잉이" · 내장 여섯째(케이크 뒤) · 선물 전용 판정 · 생일/술 목록이 갈린다.
///  ② ★ 케이크 뜻 자리는 케이크 둘 그대로다 — `ShopWire.cakeCharacterIDs` · 생일 선물 선택지 · 상점 케이크 순서에 이슬이 섞이지 않는다.
///  ③ 능력 번호 누적: 케이크까지 → 4 · 이슬까지 → 5 · 이슬만 있고 케이크가 빠지면 3. 맥 번들은 이슬 그림(초상 · 라벨)이 실리면 5(3D 갈래 — v0.3.74).
///  ④ 선물 전선: `kind` 없음 → 생일 · 술 선물엔 이슬만 · 생일 선물에 이슬이 섞이면 버림 · 술 선물에 케이크만 → 선물 없음 ·
///     모르는 종류 → 선물 없음 · 번호 4 인 빌드엔 술 선물을 띄우지 않는다.
///  ⑤ 술 선물 문구는 설계서 §5 표의 가제 글자 그대로이고 비어 있지 않다.
@Suite("v0.3.74 이슬 아잉이 공용 코어")
struct V0374IsulCoreTests {
    static let isul = "aing_isul"
    static let strawberry = "aing_cake_strawberry"
    static let choco = "aing_cake_choco"
    static let giftID = "0b7e4c1a-5d2f-4e8a-9c3b-7a6d5e4f3a2b"

    /// 맥 소스 트리에 이슬 초상 두 장이 있는가(그림 갈래 — `scripts/make-isul-aing.swift` — 전엔 거짓). V0335 · V0336 아바타 기준선이 쓴다.
    static var macIsulPortraitsInSourceTree: Bool {
        ["\(isul)-neutral", "\(isul)-negative"].allSatisfy(V0354CoreArtBaseline.macResourceExists)
    }

    static func pending(_ json: String) throws -> CharacterGiftPendingResponse {
        try V0354GachaWireTests.decoder().decode(CharacterGiftPendingResponse.self, from: Data(json.utf8))
    }

    static func host(_ label: String) -> String {
        "v0374-isul-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    }

    // MARK: - ① 카탈로그

    @Test("카탈로그: id · 표시 이름 · scene3D · 내장 여섯째(케이크 뒤) · 정확한 id 만")
    func catalogEntry() {
        #expect(CharacterCatalog.isulAingID == Self.isul)
        #expect(CharacterCatalog.builtInIsulAing.id == Self.isul)
        #expect(CharacterCatalog.builtInIsulAing.displayName == "이슬 아잉이")
        #expect(CharacterCatalog.builtInIsulAing.kind == .scene3D)
        // v0.3.77: 빼빼로가 일곱째로 이슬 뒤에 붙는다(V0377PeperoCoreTests) — 이슬의 자리(여섯째)는 그대로다.
        #expect(CharacterCatalog.builtIns.map(\.id)
            == ["aing", "aing_gold", "aing_rainbow", Self.strawberry, Self.choco, Self.isul, CharacterCatalog.peperoAingID, CharacterCatalog.hwooAingID])
        // 번들이 비어도 내장 순서 그대로 · 나머지는 그 뒤.
        let empty = CharacterCatalog(entries: [])
        #expect(empty.allIDs == ["aing", "aing_gold", "aing_rainbow", Self.strawberry, Self.choco, Self.isul, CharacterCatalog.peperoAingID, CharacterCatalog.hwooAingID])
        #expect(empty.manifest(id: Self.isul)?.displayName == "이슬 아잉이")
        #expect(CharacterCatalog.isIsulAing(Self.isul))
        for near in ["aing_isul ", "AING_ISUL", "aing_isul2", "isul", "", nil] as [String?] {
            #expect(!CharacterCatalog.isIsulAing(near), "\(String(describing: near))")
        }
    }

    @Test("선물 전용: 이슬은 선물 전용 · 케이크 아님 · 뽑기 전용 아님 · 생일/술 목록이 갈린다")
    func giftOnlyLists() {
        #expect(CharacterCatalog.isGiftOnlyBuiltIn(Self.isul))
        #expect(!CharacterCatalog.isCakeAing(Self.isul))
        #expect(!CharacterCatalog.isGachaOnlyBuiltIn(Self.isul))
        #expect(CharacterCatalog.birthdayGiftBuiltInIDs == [Self.strawberry, Self.choco])
        #expect(CharacterCatalog.drinkGiftBuiltInIDs == [Self.isul])
        #expect(CharacterCatalog.giftOnlyBuiltInIDs == [Self.strawberry, Self.choco, Self.isul, CharacterCatalog.peperoAingID])
        #expect(Set(CharacterCatalog.giftOnlyBuiltInIDs) == Set(CharacterCatalog.builtIns.map(\.id).filter(CharacterCatalog.isGiftOnlyBuiltIn)))
        #expect(CharacterCatalog.giftKind(ofBuiltIn: Self.strawberry) == .birthday)
        #expect(CharacterCatalog.giftKind(ofBuiltIn: Self.choco) == .birthday)
        #expect(CharacterCatalog.giftKind(ofBuiltIn: Self.isul) == .drink)
        #expect(CharacterCatalog.giftKind(ofBuiltIn: CharacterCatalog.peperoAingID) == .pepero, "v0.3.77 빼빼로")
        for other in ["aing", "aing_gold", "aing_rainbow", "robot", "", nil] as [String?] {
            #expect(CharacterCatalog.giftKind(ofBuiltIn: other) == nil, "\(String(describing: other))")
        }
        // 조각 교환 절대 불가 · 뽑기 희귀 아님.
        #expect(GachaRules.isNeverExchangeable(Self.isul))
        #expect(CharacterManifest.Finish(characterID: Self.isul) == .isul)
        #expect(CharacterCatalog.builtInIsulAing.finish == .isul)
        #expect(!CharacterManifest.Finish.isul.isRare)
        #expect(!CharacterManifest.Finish.isul.isCake)
        #expect(CharacterManifest.Finish(characterID: Self.choco) == .cakeChoco, "케이크 판정이 이슬에 먹히지 않는다")
    }

    @Test("상점 줄: 이슬은 표식이 있든 없든 못 산다 · 선물 전용 · 뽑기 전용으로 안 읽힌다")
    func shopRow() {
        let flagged = ShopCharacterRow(id: Self.isul, price: 2002, owned: false, gachaOnly: true, giftOnly: true)
        #expect(!flagged.isPurchasable)
        #expect(flagged.isGiftOnly)
        #expect(!flagged.isGachaOnly)
        let bare = ShopCharacterRow(id: Self.isul, price: 2002, owned: false)
        #expect(!bare.isPurchasable, "표식이 빠져도 이슬 id 는 팔지 않는다")
        #expect(bare.isGiftOnly)
    }

    // MARK: - ② 케이크 뜻 자리는 케이크 둘 그대로

    @Test("케이크 뜻 자리: cakeCharacterIDs 는 케이크 둘 · 상점 케이크 순서는 이슬을 안 옮긴다 · 잠긴 안내는 종류 문구")
    func cakeMeaningSites() {
        #expect(ShopWire.cakeCharacterIDs == [Self.strawberry, Self.choco])
        #expect(ShopWire.isulCharacterIDs == [Self.isul])
        // 서버 순서(값 · id): 초코 2000 → 딸기 2000 → 이슬 2002. 케이크 둘만 딸기 → 초코로 바로 서고 이슬은 그 자리.
        let rows = [Self.choco, Self.isul, "robot", Self.strawberry].map { ShopCharacterRow(id: $0, price: 1) }
        #expect(WorkTimerStore.giftOnlyInDisplayOrder(rows).map(\.id) == [Self.strawberry, Self.isul, "robot", Self.choco])
        // 고르기 잠긴 카드 · 상점 잠긴 안내가 종류마다 다르다.
        #expect(CheckCharacterPanel.lockedLabel(Self.isul, name: "이슬 아잉이") == "이슬 아잉이 잠김 — \(DrinkGiftText.lockedHint)")
        #expect(CheckCharacterPanel.lockedLabel(Self.choco, name: "초코") == "초코 잠김 — \(CakeGiftText.lockedHint)")
        // 고르기: 가진 사람에게만(케이크와 같다).
        #expect(!WorkTimerStore.isCharacterListed(Self.isul, shopLoaded: true, gachaAvailable: true, owned: [], rows: []))
        #expect(WorkTimerStore.isCharacterListed(Self.isul, shopLoaded: true, gachaAvailable: false, owned: [Self.isul], rows: []))
        #expect(WorkTimerStore.isCharacterListed(Self.isul, shopLoaded: false, gachaAvailable: false, owned: [], rows: [], wearing: Self.isul))
    }

    // MARK: - ③ 능력 번호

    @Test("능력 번호 누적: 케이크까지 4 · 이슬까지 5 · 이슬만(케이크 없음) 3 · 케이크 하나 + 이슬 3 · 무지개 없음 2")
    func protocolCumulative() {
        let base = ["robot", "aing_gold", "aing_rainbow"]
        #expect(ShopWire.isulProtocol == 5)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: base + [Self.strawberry, Self.choco]) == 4)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: base + [Self.strawberry, Self.choco, Self.isul]) == 5)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: base + [Self.isul]) == 3)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: base + [Self.choco, Self.isul]) == 3)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: ["robot", "aing_gold", Self.strawberry, Self.choco, Self.isul]) == 2)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: [Self.strawberry, Self.choco, Self.isul]) == 0)
        // 문턱.
        #expect(!ShopWire.supportsDrinkGift(protocolVersion: 4))
        #expect(ShopWire.supportsDrinkGift(protocolVersion: 5))
        #expect(ShopWire.supportsCakeGift(protocolVersion: 5))
        #expect(CharacterGiftKind.birthday.minProtocol == 4)
        #expect(CharacterGiftKind.drink.minProtocol == 5)
        #expect(CharacterGiftKind.birthday.isSupported(protocolVersion: 4))
        #expect(!CharacterGiftKind.drink.isSupported(protocolVersion: 4))
        #expect(CharacterGiftKind.drink.isSupported(protocolVersion: 6))
    }

    /// 맥 소스 트리에 이슬 그림이 다 있는가(초상 두 장 + 라벨 폴백 — 3D 마감 `IsulAingFinish` 의 번들 재료). 밝기 맵은 무지개 몫이다.
    static var macIsulArtInSourceTree: Bool {
        macIsulPortraitsInSourceTree && V0354CoreArtBaseline.macResourceExists("\(isul)-label")
    }

    @Test("맥 번들: 이슬 그림(초상 · 라벨)이 소스 트리에 있으면 그릴 수 있음 → 능력 번호 5, 없으면 4 그대로(누적 규칙)")
    @MainActor
    func macProtocolFollowsTheIsulArt() {
        let art = Self.macIsulArtInSourceTree
        // v0.3.77: 빼빼로 그림(판 · 초상)까지 실리면 누적으로 6 이다(이슬의 몫은 "5 이상" — 6 의 기준선은 V0377PeperoCoreTests).
        let expected = V0377PeperoCoreTests.expectedMacProtocolFromIsulOn
        let drawable = CheckMascotAssets.drawableCharacterIDs()
        #expect(drawable.contains(Self.isul) == art, "\(drawable)")
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable) == expected)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: WorkTimerStore.bundledDrawableCharacterIDs) == expected)
        let store = V0317ShopTests.plainStore()
        #expect(store.shopProtocolVersion == expected && store.supportsCakeGift)
        #expect(ShopWire.supportsDrinkGift(protocolVersion: store.shopProtocolVersion) == art)
    }

    // MARK: - ④ 선물 전선

    @Test("종류: 원문 값 두 개만 · 내장 id · 내장 → 종류")
    func giftKind() {
        #expect(CharacterGiftKind.allCases == [.birthday, .drink, .pepero], "v0.3.77 빼빼로가 셋째 종류")
        #expect(CharacterGiftKind.birthday.wireValue == "birthday")
        #expect(CharacterGiftKind.drink.wireValue == "drink")
        #expect(CharacterGiftKind(wireValue: "birthday") == .birthday)
        #expect(CharacterGiftKind(wireValue: "drink") == .drink)
        for odd in ["Drink", " drink", "soju", "", nil] as [String?] {
            #expect(CharacterGiftKind(wireValue: odd) == nil, "\(String(describing: odd))")
        }
        #expect(CharacterGiftKind.birthday.builtInIDs == [Self.strawberry, Self.choco])
        #expect(CharacterGiftKind.drink.builtInIDs == [Self.isul])
        #expect(CharacterGiftKind(builtInID: Self.isul) == .drink)
        #expect(CharacterGiftKind(builtInID: Self.strawberry) == .birthday)
        #expect(CharacterGiftKind(builtInID: "aing_gold") == nil)
    }

    @Test("디코드: kind 없음 · null → 생일 · 술 선물 + 이슬 · 생일에 이슬 섞임 → 이슬 버림 · 술에 케이크만 → 선물 없음 · 모르는 종류 → 없음")
    func pendingDecodesKinds() throws {
        // kind 없음(옛 서버) → 생일.
        let legacy = try Self.pending(#"{"status":"ok","gift":{"id":"\#(Self.giftID)","options":["aing_cake_choco","aing_cake_strawberry"],"note":null,"created_at":"2026-11-03T01:00:00Z"}}"#)
        #expect(legacy.offer?.kind == .birthday)
        #expect(legacy.offer?.options == [Self.strawberry, Self.choco])
        let nullKind = try Self.pending(#"{"status":"ok","gift":{"id":"g","kind":null,"options":["aing_cake_choco"]}}"#)
        #expect(nullKind.offer?.kind == .birthday)
        #expect(nullKind.offer?.options == [Self.choco])

        // 술 선물 + 이슬 → 이슬 하나 · note 는 그대로.
        let drink = try Self.pending(#"{"status":"ok","gift":{"id":"\#(Self.giftID)","kind":"drink","options":["aing_isul"],"note":"오늘 한잔?","created_at":"2026-11-03T01:00:00Z"}}"#)
        #expect(drink.offer == CharacterGiftOffer(id: Self.giftID, options: [Self.isul], note: "오늘 한잔?",
                                                  createdAt: "2026-11-03T01:00:00Z", kind: .drink))
        #expect(drink.offer?.kind == .drink)

        // 생일 선물에 이슬이 섞임 → 이슬을 버린다(케이크만, 딸기 → 초코).
        let mixedBirthday = try Self.pending(#"{"status":"ok","gift":{"id":"g","kind":"birthday","options":["aing_isul","aing_cake_choco","aing_cake_strawberry"]}}"#)
        #expect(mixedBirthday.offer?.kind == .birthday)
        #expect(mixedBirthday.offer?.options == [Self.strawberry, Self.choco])
        // kind 없음(생일로 읽음) + 이슬만 → 고를 것 없음 → 선물 없음.
        let legacyIsulOnly = try Self.pending(#"{"status":"ok","gift":{"id":"g","options":["aing_isul"]}}"#)
        #expect(legacyIsulOnly.offer == nil)

        // 술 선물에 케이크만 → 선물 없음 · 케이크와 이슬이 섞이면 이슬만.
        let cakeInDrink = try Self.pending(#"{"status":"ok","gift":{"id":"g","kind":"drink","options":["aing_cake_strawberry","aing_cake_choco"]}}"#)
        #expect(cakeInDrink.offer == nil)
        #expect(cakeInDrink.status == "ok")
        let mixedDrink = try Self.pending(#"{"status":"ok","gift":{"id":"g","kind":"drink","options":["aing_cake_strawberry","aing_isul"]}}"#)
        #expect(mixedDrink.offer?.options == [Self.isul])

        // 모르는 종류 · 모양이 틀린 종류 → 이 빌드가 열 수 없는 선물(없음). 응답 자체는 산다.
        for odd in [#""anniversary""#, #""Drink""#, "7", "true", #"["drink"]"#] {
            let response = try Self.pending(#"{"status":"ok","gift":{"id":"g","kind":\#(odd),"options":["aing_isul","aing_cake_choco"]}}"#)
            #expect(response.offer == nil, "\(odd)")
            #expect(response.status == "ok")
        }
    }

    @Test("memberwise · choosable: 종류 기본값은 생일 · 종류로 거른다")
    func offerInitAndChoosable() {
        let birthday = CharacterGiftOffer(id: "g", options: [Self.isul, Self.choco, Self.strawberry])
        #expect(birthday.kind == .birthday)
        #expect(birthday.options == [Self.strawberry, Self.choco])
        let drink = CharacterGiftOffer(id: "g", options: [Self.choco, Self.isul, Self.isul], kind: .drink)
        #expect(drink.options == [Self.isul])
        #expect(CharacterGiftOffer.choosable([Self.isul, Self.choco]) == [Self.choco], "기본 종류는 생일")
        #expect(CharacterGiftOffer.choosable([Self.isul, Self.choco], kind: .drink) == [Self.isul])
        #expect(CharacterGiftOffer.choosable([Self.strawberry, Self.choco], kind: .drink).isEmpty)
        #expect(CharacterGiftOffer(id: "g", options: [Self.isul], kind: .drink)
            != CharacterGiftOffer(id: "g", options: [Self.isul], kind: .birthday), "종류가 같음 판정에 든다")
    }

    @Test("서비스: 번호 5 는 술 선물을 받는다 · 번호 4 인 빌드엔 술 선물이 섞여 와도 띄우지 않는다 · 생일은 4 그대로")
    func servicePendingByProtocol() async throws {
        let host = Self.host("pending")
        GomokuStubProtocol.register(host: host) { rpc, body, _ in
            guard rpc == "character_gift_pending" else { return nil }
            // 일부러 번호와 무관하게 술 선물을 싣는다(서버가 잘못 실어도 클라가 막는지 잰다).
            return GomokuStubProtocol.Reply(body: #"{"status":"ok","gift":{"id":"g-drink","kind":"drink","options":["aing_isul"],"note":"한잔 하자"}}"#)
        }
        let service = V0354GachaWireTests.service(host: host)
        let four = try await service.fetchCharacterGiftPending(accessToken: "t", protocolVersion: ShopWire.cakeProtocol)
        #expect(four == nil, "4 인 빌드는 이슬을 못 그린다 — 받을 수 없는 창을 띄우지 않는다")
        let five = try await service.fetchCharacterGiftPending(accessToken: "t", protocolVersion: ShopWire.isulProtocol)
        #expect(five == CharacterGiftOffer(id: "g-drink", options: [Self.isul], note: "한잔 하자", kind: .drink))
        let calls = GomokuStubProtocol.calls(host: host, rpc: "character_gift_pending")
        #expect(calls.map { $0.json["p_protocol"] as? Int } == [4, 5])
        #expect(calls.map { Set($0.json.keys) } == [["p_protocol"], ["p_protocol"]], "요청 키 집합은 그대로")

        let birthdayHost = Self.host("birthday")
        GomokuStubProtocol.register(host: birthdayHost) { rpc, _, _ in
            guard rpc == "character_gift_pending" else { return nil }
            return GomokuStubProtocol.Reply(body: #"{"status":"ok","gift":{"id":"g-cake","kind":"birthday","options":["aing_cake_strawberry","aing_cake_choco"]}}"#)
        }
        let cakeService = V0354GachaWireTests.service(host: birthdayHost)
        #expect(try await cakeService.fetchCharacterGiftPending(accessToken: "t", protocolVersion: 4)?.kind == .birthday)
        #expect(try await cakeService.fetchCharacterGiftPending(accessToken: "t", protocolVersion: 5)?.options == [Self.strawberry, Self.choco])
    }

    @Test("수령: 술 선물 needs_update(min_protocol 5)도 같은 어휘로 접힌다")
    func claimNeedsUpdate() throws {
        let response = try V0354GachaWireTests.decoder().decode(
            CharacterGiftClaimResponse.self, from: Data(#"{"status":"needs_update","min_protocol":5}"#.utf8))
        #expect(response.minProtocol == 5)
        let outcome = CharacterGiftClaimOutcome(response: response, requestedID: Self.isul)
        #expect(outcome == .needsUpdate)
        #expect(!outcome.settlesGift)
        #expect(DrinkGiftText.notice(for: outcome) { $0 } == CakeGiftText.needsUpdate)
        let received = CharacterGiftClaimOutcome(
            response: CharacterGiftClaimResponse(status: "ok", characterId: Self.isul, replayed: false), requestedID: Self.isul)
        #expect(received == .received(characterID: Self.isul, replayed: false))
    }

    // MARK: - ⑤ 문구

    @Test("문구: 대표 결정 C(짠! 🥂) 그대로 · 비어 있지 않음 · 종류 → 묶음")
    func drinkText() {
        #expect(DrinkGiftText.title == "짠! 🥂")
        #expect(DrinkGiftText.body == "오늘도 고생 많았어요. 이슬 아잉이 한 병 받아요!")
        #expect(DrinkGiftText.confirmButton == "짠 받기")
        #expect(DrinkGiftText.wearNowButton == "지금 입기")
        #expect(DrinkGiftText.closeButton == "닫기")
        #expect(DrinkGiftText.lockedCaption == "술 한잔 선물 전용")
        #expect(DrinkGiftText.lockedHint == "술 한잔 선물로만 받을 수 있어요. 루비나 뽑기로는 얻을 수 없어요.")
        #expect(DrinkGiftText.reopenTitle == "짠! 선물이 왔어요")
        #expect(DrinkGiftText.reopenButton == "받기")
        #expect(DrinkGiftText.received(name: "이슬 아잉이") == "이슬 아잉이를 받았어요!")

        for copy in [CharacterGiftKind.birthday.copy, CharacterGiftKind.drink.copy] {
            let lines = [copy.title, copy.body, copy.confirmButton, copy.wearNowButton, copy.closeButton,
                         copy.lockedCaption, copy.lockedHint, copy.reopenTitle, copy.reopenButton]
            #expect(lines.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "\(lines)")
        }
        #expect(CharacterGiftKind.drink.copy == .drink)
        #expect(CharacterGiftKind.birthday.copy == .birthday)
        #expect(CharacterGiftCopy.drink.title == DrinkGiftText.title)
        #expect(CharacterGiftCopy.drink.lockedHint == DrinkGiftText.lockedHint)
        #expect(CharacterGiftCopy.birthday.title == CakeGiftText.title)
        #expect(CharacterGiftCopy.birthday.lockedCaption == CakeGiftText.lockedCaption)
        #expect(CharacterGiftCopy.drink.received(name: "이슬 아잉이") == "이슬 아잉이를 받았어요!")
        #expect(CharacterGiftCopy.drink != CharacterGiftCopy.birthday)
    }
}
