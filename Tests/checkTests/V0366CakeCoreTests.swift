import Foundation
import Testing
@testable import check
@testable import CheckCore

/// v0.3.66 케이크 아잉이(생일 선물 전용 둘) — 공용 코어의 식별 · 마감 · 상점 번호 · 구매 불가 판정.
///
/// 지키는 것(설계서 §1 · §3):
///  ① 카탈로그: 두 케이크가 **넷째 · 다섯째 내장**(아잉 → 황금 → 무지개 → 딸기 → 초코 → 나머지)이고, 번들이 비어도 있다.
///     판정 셋(`isCakeAing` · `isGiftOnlyBuiltIn` · `isGachaOnlyBuiltIn`)이 서로를 삼키지 않는다 — 케이크는 뽑기 전용이 아니다.
///  ② 마감: `.cakeStrawberry` · `.cakeChoco` 는 id 에서만 나오고, **희귀가 아니다**(뽑기 화면에 서지 않는다).
///  ③ 상점 번호 4: robot · 금 · 무지개 · **두 케이크** 전부를 그릴 수 있다 ⟺ 4. 케이크가 하나 빠지면 3 이다(양방향 — 32 부분집합 전수).
///  ④ 구매 불가: 서버 표식(`gift_only`)이 오든 빠지든 케이크 줄은 절대 안 팔린다 · `gift_only` 는 디코드된다(키 없음 = nil).
@Suite("v0.3.66 케이크 아잉이 공용 코어")
struct V0366CakeCoreTests {
    static let strawberry = "aing_cake_strawberry"
    static let choco = "aing_cake_choco"
    static let fiveBuiltIns = ["aing", "aing_gold", "aing_rainbow", strawberry, choco]

    /// 맥 케이크 초상 두 장(`<id>-neutral` · `<id>-negative`)이 소스 트리(`Sources/check/Resources/`)에 있는가 — 금 · 무지개와 같은 기준선.
    /// 이 단계(코어)에는 없다. 그림 단계가 넣는 순간 아바타 · 고르기 시험이 그 초상을 찾아야 초록이다(못 찾으면 배선이 빠졌다).
    static func macCakePortraitsInSourceTree(_ id: String) -> Bool {
        ["\(id)-neutral", "\(id)-negative"].allSatisfy(V0354CoreArtBaseline.macResourceExists)
    }

    // MARK: - ① 카탈로그

    @Test("번들이 비어도 케이크 둘이 있다 — 넷째 · 다섯째 내장 · 3D · 이름 · 아틀라스 · 초상 · 폴더 없음")
    func cakesAreBuiltIn() {
        #expect(CharacterCatalog.cakeStrawberryAingID == Self.strawberry)
        #expect(CharacterCatalog.cakeChocoAingID == Self.choco)
        #expect(CharacterCatalog.builtIns.map(\.id) == Self.fiveBuiltIns)
        #expect(CharacterCatalog.builtInCakeStrawberryAing.id == Self.strawberry)
        #expect(CharacterCatalog.builtInCakeChocoAing.id == Self.choco)

        let empty = CharacterCatalog.load(charactersDirectory: nil)
        #expect(empty.allIDs == Self.fiveBuiltIns)
        for (id, name) in [(Self.strawberry, "딸기 케이크 아잉이"), (Self.choco, "초코 케이크 아잉이")] {
            let manifest = empty.manifest(id: id)
            #expect(manifest?.displayName == name, "\(id)")
            #expect(manifest?.kind == .scene3D, "\(id)")
            #expect(manifest?.atlas == nil && manifest?.portrait == nil, "\(id)")
            #expect(empty.entry(id: id)?.directory == nil, "\(id)")
            #expect(empty.atlasURL(for: id) == nil, "\(id)")
            // 이름 해석(확률표 · 교환 줄이 쓰는 내장 이름 폴백)도 케이크를 안다.
            #expect(GachaRules.name(for: id, displayName: { _ in nil }) == name)
        }
    }

    @Test("표시 순서: 케이크는 정렬로는 금보다 앞(`aing_cake_*` < `aing_gold`)이라도 내장 순서 그대로 · 나머지는 id 정렬")
    func orderIsBuiltInNotSorted() {
        // 기준선: 정렬만 하면 케이크가 금 앞에 선다 — 내장 순서가 실제로 일을 한다.
        #expect(Self.fiveBuiltIns.sorted().prefix(3) == ["aing", "aing_cake_choco", "aing_cake_strawberry"])
        let catalog = CharacterCatalog(manifests: [
            CharacterManifest(id: "zebra", displayName: "얼룩말", kind: .sprite),
            CharacterManifest(id: "aardvark", displayName: "땅돼지", kind: .sprite),
        ])
        #expect(catalog.allIDs == Self.fiveBuiltIns + ["aardvark", "zebra"])
    }

    @Test("파일 매니페스트로는 케이크를 못 싣는다(밑줄 id) · 같은 id 를 넣어도 내장이 이긴다")
    func builtInWins() {
        for id in [Self.strawberry, Self.choco] {
            let json = #"{"id":"\#(id)","displayName":"가짜 케이크","kind":"scene3D"}"#
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode(CharacterManifest.self, from: Data(json.utf8))
            }
        }
        let fake = CharacterManifest(id: Self.choco, displayName: "가짜 초코", kind: .sprite)
        let catalog = CharacterCatalog(manifests: [fake])
        #expect(catalog.manifest(id: Self.choco)?.kind == .scene3D)
        #expect(catalog.manifest(id: Self.choco)?.displayName == "초코 케이크 아잉이")
        #expect(catalog.allIDs == Self.fiveBuiltIns)
    }

    @Test("판정 셋은 서로를 삼키지 않는다 — 케이크는 선물 전용이지 뽑기 전용이 아니다 · 비슷한 이름에 반응하지 않는다")
    func predicatesAreDisjoint() {
        #expect(CharacterCatalog.giftOnlyBuiltInIDs == [Self.strawberry, Self.choco])
        #expect(CharacterCatalog.gachaOnlyBuiltInIDs == ["aing_gold", "aing_rainbow"], "뽑기 전용 목록이 케이크로 넓어졌다")
        for id in [Self.strawberry, Self.choco] {
            #expect(CharacterCatalog.isCakeAing(id))
            #expect(CharacterCatalog.isGiftOnlyBuiltIn(id))
            #expect(CharacterCatalog.isGachaOnlyBuiltIn(id) == false, "\(id) 가 뽑기 전용으로 읽혔다")
            #expect(CharacterCatalog.isGoldAing(id) == false && CharacterCatalog.isRainbowAing(id) == false)
        }
        for other in ["aing", "aing_gold", "aing_rainbow", "fox", "AING_CAKE_CHOCO", "aing-cake-choco", " aing_cake_choco",
                      "aing_cake_choco ", "aing_cake", "cake", "aing_cake_strawberry2", "", nil] as [String?] {
            #expect(CharacterCatalog.isCakeAing(other) == false, Comment(rawValue: "\(other ?? "nil")"))
            #expect(CharacterCatalog.isGiftOnlyBuiltIn(other) == false, Comment(rawValue: "\(other ?? "nil")"))
        }
        // 금 · 무지개는 그대로 뽑기 전용이다(케이크가 그 규칙을 바꾸지 않았다).
        #expect(CharacterCatalog.isGachaOnlyBuiltIn("aing_gold") && CharacterCatalog.isGachaOnlyBuiltIn("aing_rainbow"))
        #expect(CharacterCatalog.isGiftOnlyBuiltIn("aing_gold") == false && CharacterCatalog.isGiftOnlyBuiltIn("aing_rainbow") == false)
    }

    @Test("조각 교환: 케이크는 절대 교환 불가 — 서버 교환표에 실려 와도 교환 목록 · 확률표 교환값 칸에 서지 않는다")
    func cakesAreNeverExchangeable() {
        #expect(GachaRules.isNeverExchangeable(Self.strawberry) && GachaRules.isNeverExchangeable(Self.choco))
        #expect(GachaRules.isNeverExchangeable("aing"))
        #expect(GachaRules.isNeverExchangeable("aing_gold") == false, "기준선: 금은 교환된다(AMENDMENT 1)")
        let costs = ["fox": 2, "aing_gold": 20, Self.strawberry: 20, Self.choco: 20]
        #expect(GachaRules.exchangeAvailability(characterID: Self.choco, isOwned: false, shards: 99, shardCosts: costs) == .notExchangeable)
        #expect(GachaRules.exchangeAvailability(characterID: "fox", isOwned: false, shards: 99, shardCosts: costs) == .available(cost: 2))
        let info = GachaInfo(price: 50, shards: 99, odds: [GachaOddsEntry(characterID: "fox", percent: 100)], shardCosts: costs)
        let rows = GachaRules.exchangeRows(info: info, ownedIDs: [], displayName: { _ in nil }).map(\.characterID)
        #expect(rows == ["aing_gold", "fox"], Comment(rawValue: "\(rows)"))
    }

    // MARK: - ② 마감

    @Test("마감: 케이크 둘은 각자의 마감 · 희귀가 아니다 · isCake 는 둘만 · 금 · 무지개 희귀는 그대로")
    func finishForCakes() {
        #expect(CharacterManifest.Finish(characterID: Self.strawberry) == .cakeStrawberry)
        #expect(CharacterManifest.Finish(characterID: Self.choco) == .cakeChoco)
        #expect(CharacterCatalog.builtInCakeStrawberryAing.finish == .cakeStrawberry)
        #expect(CharacterCatalog.builtInCakeChocoAing.finish == .cakeChoco)
        let catalog = CharacterCatalog.load(charactersDirectory: nil)
        #expect(catalog.manifest(id: Self.strawberry)?.finish == .cakeStrawberry)
        #expect(catalog.manifest(id: Self.choco)?.finish == .cakeChoco)

        let table: [(CharacterManifest.Finish, rare: Bool, cake: Bool)] = [
            (.standard, false, false), (.gold, true, false), (.rainbow, true, false),
            (.cakeStrawberry, false, true), (.cakeChoco, false, true),
        ]
        for (finish, rare, cake) in table {
            #expect(finish.isRare == rare, "\(finish).isRare")
            #expect(finish.isCake == cake, "\(finish).isCake")
        }
        for other in ["aing", "fox", "aing_cake", "AING_CAKE_CHOCO", "", nil] as [String?] {
            #expect(CharacterManifest.Finish(characterID: other) == .standard, Comment(rawValue: "\(other ?? "nil")"))
        }
        // 확률표 줄의 강조(GachaOddsRow.finish)도 같은 판정 — 케이크 줄이 실수로 와도 희귀 강조가 안 붙는다.
        let row = GachaOddsRow(characterID: Self.choco, name: "초코 케이크 아잉이", percent: 1, percentText: "1%",
                               shopPrice: nil, priceText: "—", isGachaOnly: false, shardCost: nil)
        #expect(row.finish == .cakeChoco && row.finish.isRare == false)
    }

    // MARK: - ③ 상점 번호 4

    @Test("파생 함수: + 두 케이크 → 4 · 케이크 하나 빠지면 3 · 무지개가 없으면 케이크 둘이 있어도 2 · 비슷한 이름 무반응")
    func derivationIsCumulative() {
        let sprites = ["aing", "fox", "ghost", "jellyfish", "shiba", "squirrel"]
        let base = sprites + ["robot", "aing_gold", "aing_rainbow"]
        let table: [([String], Int)] = [
            (base, 3),
            (base + [Self.strawberry, Self.choco], 4),
            ([Self.choco, Self.strawberry, "aing_rainbow", "aing_gold", "robot"], 4),
            (base + [Self.strawberry], 3),
            (base + [Self.choco], 3),
            (sprites + ["robot", "aing_gold", Self.strawberry, Self.choco], 2),
            (sprites + ["robot", Self.strawberry, Self.choco], 1),
            (sprites + ["aing_gold", "aing_rainbow", Self.strawberry, Self.choco], 0),
            (base + [Self.strawberry, "AING_CAKE_CHOCO"], 3),
            (base + [Self.strawberry, "aing-cake-choco"], 3),
            (base + [" aing_cake_strawberry", Self.choco], 3),
            (base + ["aing_cake", Self.choco], 3),
        ]
        for (ids, expected) in table {
            #expect(ShopWire.protocolVersion(drawableCharacterIDs: ids) == expected,
                    Comment(rawValue: "\(ids) → \(ShopWire.protocolVersion(drawableCharacterIDs: ids)), 기대 \(expected)"))
        }
        #expect(ShopWire.cakeProtocol == 4, "서버 `character_prices.min_protocol = 4` 와 같은 숫자여야 한다")
        #expect(ShopWire.rainbowProtocol < ShopWire.cakeProtocol)
        #expect(ShopWire.cakeCharacterIDs == [Self.strawberry, Self.choco])
        #expect(ShopWire.cakeCharacterIDs == CharacterCatalog.giftOnlyBuiltInIDs)
    }

    /// 동치를 **양방향으로** 못 박는다: 다섯 id(robot · 금 · 무지개 · 딸기 · 초코)의 32 부분집합 전부에서
    /// "다섯 다 있다 ⟺ 4" 이고, "앞 셋은 다 있고 케이크는 하나라도 빠졌다 ⟺ 3" 이다. 기대값은 파생 함수가 아니라 집합 포함으로 만든다.
    @Test("양방향 동치: 다섯 다 그릴 수 있다 ⟺ 4 · 앞 셋 다 + 케이크 하나라도 빠짐 ⟺ 3 (32 부분집합 전수)")
    func equivalenceBothWays() {
        let five = ["robot", "aing_gold", "aing_rainbow", Self.strawberry, Self.choco]
        var sawFour = 0, sawThree = 0
        for mask in 0..<(1 << five.count) {
            let present = five.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            let set = Set(present)
            let version = ShopWire.protocolVersion(drawableCharacterIDs: ["aing", "fox"] + present)
            let allFive = set.isSuperset(of: five)
            let rainbowWorld = set.isSuperset(of: ["robot", "aing_gold", "aing_rainbow"])
            #expect((version == ShopWire.cakeProtocol) == allFive, Comment(rawValue: "\(present) → \(version)"))
            #expect((version == ShopWire.rainbowProtocol) == (rainbowWorld && !allFive), Comment(rawValue: "\(present) → \(version)"))
            #expect(version <= ShopWire.cakeProtocol)
            if version == 4 { sawFour += 1 }
            if version == 3 { sawThree += 1 }
        }
        #expect(sawFour == 1 && sawThree == 3, "4 는 한 부분집합, 3 은 세 부분집합(케이크 없음 · 딸기만 · 초코만)이어야 한다")
    }

    @Test("문턱: 뽑기는 2 그대로 · 생일 선물은 4 부터")
    func thresholds() {
        #expect(ShopWire.supportsGacha(protocolVersion: ShopWire.cakeProtocol))
        #expect(ShopWire.supportsCakeGift(protocolVersion: ShopWire.rainbowProtocol) == false)
        #expect(ShopWire.supportsCakeGift(protocolVersion: ShopWire.cakeProtocol))
        #expect(ShopWire.supportsCakeGift(protocolVersion: ShopWire.legacyProtocol) == false)
    }

    // MARK: - ④ 구매 불가 · gift_only 디코드

    @Test("구매 불가: 케이크 줄은 표식이 빠지거나 false 여도 못 산다 · 표식이 참이면 다른 id 도 못 산다 · 기준선 여우는 산다")
    func purchasability() {
        let cases: [(ShopCharacterRow, purchasable: Bool, giftOnly: Bool)] = [
            (ShopCharacterRow(id: "fox", price: 60, owned: false, gachaOnly: false, giftOnly: false), true, false),
            (ShopCharacterRow(id: "fox", price: 60), true, false),
            (ShopCharacterRow(id: "fox", price: nil), false, false),
            (ShopCharacterRow(id: "fox", price: 60, giftOnly: true), false, true),
            (ShopCharacterRow(id: Self.strawberry, price: 2000, owned: false, gachaOnly: true, giftOnly: true), false, true),
            (ShopCharacterRow(id: Self.strawberry, price: 2000, owned: false, gachaOnly: false, giftOnly: false), false, true),
            (ShopCharacterRow(id: Self.choco, price: 2000), false, true),
            (ShopCharacterRow(id: Self.choco, price: 2000, gachaOnly: false, giftOnly: nil), false, true),
            (ShopCharacterRow(id: "aing_gold", price: 1000, gachaOnly: false), false, false),
        ]
        for (row, purchasable, giftOnly) in cases {
            #expect(row.isPurchasable == purchasable, Comment(rawValue: "\(row) 구매 가능 \(row.isPurchasable)"))
            #expect(row.isGiftOnly == giftOnly, Comment(rawValue: "\(row) 선물 전용 \(row.isGiftOnly)"))
        }
    }

    /// 서버는 케이크 행에 not_for_sale 갈래를 타려고 `gacha_only = true` 도 싣는다 — 그 표식만 보면 케이크가 '뽑기 전용'으로 읽혀
    /// 맥 상점이 뽑기 창을 열고 폰이 "뽑기나 조각 교환으로…"라고 말한다. 선물 전용이 먼저 이긴다.
    @Test("뽑기 전용 판정: 케이크 행은 gacha_only 가 참이어도 뽑기 전용이 아니다 — 줄 · 맥 스토어 · 금 기준선")
    func cakeRowIsNotGachaOnly() {
        let cakeRow = ShopCharacterRow(id: Self.choco, price: 2000, owned: false, gachaOnly: true, giftOnly: true)
        let goldRow = ShopCharacterRow(id: "aing_gold", price: 1000, owned: false, gachaOnly: true, giftOnly: false)
        let flaggedFox = ShopCharacterRow(id: "fox", price: 60, gachaOnly: true)
        let giftFox = ShopCharacterRow(id: "fox", price: 60, gachaOnly: true, giftOnly: true)
        #expect(cakeRow.isGachaOnly == false)
        #expect(ShopCharacterRow(id: Self.strawberry, price: 2000, gachaOnly: true).isGachaOnly == false, "표식 없이 와도 케이크 id 는 선물 전용")
        #expect(goldRow.isGachaOnly && ShopCharacterRow(id: "aing_rainbow").isGachaOnly, "기준선: 금 · 무지개는 뽑기 전용")
        #expect(flaggedFox.isGachaOnly && giftFox.isGachaOnly == false)
        let rows = [cakeRow, goldRow, flaggedFox]
        #expect(WorkTimerStore.isGachaOnly(Self.choco, rows: rows) == false)
        #expect(WorkTimerStore.isGachaOnly(Self.strawberry, rows: []) == false)
        #expect(WorkTimerStore.isGachaOnly("aing_gold", rows: []) && WorkTimerStore.isGachaOnly("fox", rows: rows))
    }

    /// 맥 고르기 · 상점 자리표시 격자: 케이크는 **가진 사람에게만** 선다(안 가진 사람의 잠긴 칸은 서버 목록이 있는 상점에서 보인다).
    /// 이 문이 없으면 내장 다섯이 된 순간 모든 사람의 고르기가 11 → 13 장이 되어 격자가 높이 예산(4행)을 넘는다(V0316 패널 시험).
    @Test("맥 고르기: 케이크는 가진 사람에게만 — 로드 전 · 서버 행이 있어도 안 가졌으면 안 선다 · 금 관용은 그대로")
    func macPickerListsCakesOnlyWhenOwned() {
        let cakeRow = ShopCharacterRow(id: Self.choco, price: 2000, owned: false, gachaOnly: true, giftOnly: true)
        for loaded in [false, true] {
            for gacha in [false, true] {
                #expect(WorkTimerStore.isCharacterListed(Self.choco, shopLoaded: loaded, gachaAvailable: gacha, owned: [], rows: [cakeRow]) == false)
                #expect(WorkTimerStore.isCharacterListed(Self.choco, shopLoaded: loaded, gachaAvailable: gacha, owned: [Self.choco], rows: []))
                #expect(WorkTimerStore.isCharacterListed(Self.strawberry, shopLoaded: loaded, gachaAvailable: gacha, owned: [Self.choco], rows: []) == false)
            }
        }
        // 기준선: 금은 로드 전 관용으로 서고, 여우는 언제나 선다.
        #expect(WorkTimerStore.isCharacterListed("aing_gold", shopLoaded: false, gachaAvailable: false, owned: [], rows: []))
        #expect(WorkTimerStore.isCharacterListed("fox", shopLoaded: true, gachaAvailable: false, owned: [], rows: []))
    }

    @Test("shop_state 디코드: gift_only 참 · 거짓 · 키 없음(옛 서버 = nil) — 서비스와 같은 snake → camel 디코더")
    func shopStateDecodesGiftOnly() throws {
        let json = #"""
        {"ruby_balance":120,"ultra_balance":0,"ultra_price":3,"ultra_buy_max":20,"characters":[
          {"id":"fox","price":60,"owned":false,"gacha_only":false,"gift_only":false},
          {"id":"aing_rainbow","price":1000,"owned":true,"gacha_only":true,"gift_only":false},
          {"id":"aing_cake_strawberry","price":2000,"owned":false,"gacha_only":true,"gift_only":true},
          {"id":"aing_cake_choco","price":2000,"owned":true,"gacha_only":true,"gift_only":true},
          {"id":"shiba","price":100,"owned":false}
        ]}
        """#
        let state = try V0354GachaWireTests.decoder().decode(ShopStateResponse.self, from: Data(json.utf8))
        let rows = try #require(state.characters)
        #expect(rows.map(\.id) == ["fox", "aing_rainbow", Self.strawberry, Self.choco, "shiba"])
        #expect(rows.map(\.giftOnly) == [false, false, true, true, nil])
        #expect(rows.map(\.isPurchasable) == [true, false, false, false, true])
        #expect(rows.map(\.isGiftOnly) == [false, false, true, true, false])
        #expect(rows.map(\.isGachaOnly) == [false, true, false, false, false])
        #expect(rows.first { $0.id == Self.choco }?.owned == true)
    }
}
