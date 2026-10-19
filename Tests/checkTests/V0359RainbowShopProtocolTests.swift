import Foundation
import Testing
@testable import check
@testable import CheckCore

/// v0.3.59 무지개 아잉이 — 상점 능력 번호 3(`ShopWire.rainbowProtocol`)과 "그릴 수 있다"의 정의(`RainbowAingArt`),
/// 그리고 번호 2 에 머무는 클라(0.3.58 · 폰 1.0.9)가 받을 **소수 확률표**의 전선.
///
/// 세 겹(robot V0343 · 금 V0354 와 같은 모양):
///  ① 파생 — "robot · aing_gold · aing_rainbow 를 **셋 다** 그릴 수 있다" ⟺ 3. 번호는 누적이라 무지개만 있고 금이 없으면 3 은커녕 2 도 없다.
///  ② 전선 — 맥 스토어의 진짜 경로(`loadShopState` · `buyCharacter`)가 그 번호를 같이 싣고, 3 일 때만 서버의 무지개 행이 목록에 선다.
///  ③ 번들 그대로 — 소스 트리의 그림 파일이 기준선이다(파생과 같은 식으로 기대값을 만들면 영원히 초록이다).
@Suite("v0.3.59 무지개 아잉이 상점 프로토콜")
struct V0359RainbowShopProtocolTests {

    // MARK: - ① 파생

    @Test("파생 함수: robot → 1, + 금 → 2, + 무지개 → 3 — 누적이라 무지개만 있으면 robot 까지의 번호에 머문다")
    func derivationIsCumulative() {
        let sprites = ["aing", "fox", "ghost", "jellyfish", "shiba", "squirrel"]
        let table: [([String], Int)] = [
            ([], 0),
            (sprites, 0),
            (sprites + ["robot"], 1),
            (sprites + ["robot", "aing_gold"], 2),
            (sprites + ["robot", "aing_gold", "aing_rainbow"], 3),
            (["aing_rainbow", "aing_gold", "robot"], 3),
            // 무지개는 있는데 금이 없다: 3 을 보내면 금 카드가(2 를 건너뛰면 금 행이) 아잉 그림으로 팔린다 → robot 까지(1).
            (sprites + ["robot", "aing_rainbow"], 1),
            // robot 이 없으면 다른 게 다 있어도 0(번호를 건너뛰어 말할 수 없다).
            (sprites + ["aing_gold", "aing_rainbow"], 0),
            // 비슷한 이름에 반응하면 안 된다.
            (sprites + ["robot", "aing_gold", "aing-rainbow"], 2),
            (sprites + ["robot", "aing_gold", "AING_RAINBOW"], 2),
            (sprites + ["robot", "aing_gold", " aing_rainbow"], 2),
            (sprites + ["robot", "aing_gold", "rainbow"], 2),
        ]
        for (ids, expected) in table {
            #expect(ShopWire.protocolVersion(drawableCharacterIDs: ids) == expected,
                    Comment(rawValue: "\(ids) → \(ShopWire.protocolVersion(drawableCharacterIDs: ids)), 기대 \(expected)"))
        }
        #expect(ShopWire.goldProtocol < ShopWire.rainbowProtocol && ShopWire.rainbowProtocol == 3)
        #expect(ShopWire.rainbowCharacterID == "aing_rainbow" && ShopWire.rainbowCharacterID == CharacterCatalog.rainbowAingID)
    }

    @Test("뽑기 문턱은 2 그대로 — 3 도 뽑을 수 있다(무지개가 뽑기 문턱을 올리지 않는다)")
    func gachaThresholdUnchanged() {
        #expect(ShopWire.supportsGacha(protocolVersion: 1) == false)
        #expect(ShopWire.supportsGacha(protocolVersion: ShopWire.goldProtocol))
        #expect(ShopWire.supportsGacha(protocolVersion: ShopWire.rainbowProtocol))
    }

    @Test("RainbowAingArt: 요구 파일이 전부 있을 때만 그릴 수 있다 — 맥 4장 · 폰 2장, 한 장씩 빼며 잰다 · 이름 규칙")
    func artPredicateNeedsEveryFile() {
        #expect(RainbowAingArt.requiredResourceNames(for: .mac)
                == ["aing_rainbow-neutral", "aing_rainbow-negative", "aing_rainbow-shade", "aing_rainbow-halo"])
        #expect(RainbowAingArt.requiredResourceNames(for: .phone) == ["aing_rainbow-neutral", "aing_rainbow-negative"])
        #expect(RainbowAingArt.resourceExtension == "png")
        #expect(RainbowAingArt.haloCellResourceNames.count == 36)
        #expect(RainbowAingArt.haloResourceName(cell: 0) == "aing_rainbow-halo")
        #expect(RainbowAingArt.haloResourceName(cell: 4) == "aing_rainbow-halo-040")
        #expect(RainbowAingArt.haloResourceName(cell: 35) == "aing_rainbow-halo-350")
        for platform in [RainbowAingArt.Platform.mac, .phone] {
            let all = Set(RainbowAingArt.requiredResourceNames(for: platform))
            #expect(RainbowAingArt.isDrawable(on: platform) { all.contains($0) }, "\(platform): 다 있는데 못 그린다")
            #expect(RainbowAingArt.isDrawable(on: platform) { _ in false } == false)
            for missing in all {
                let present = all.subtracting([missing])
                #expect(RainbowAingArt.isDrawable(on: platform) { present.contains($0) } == false, "\(platform): \(missing) 가 없는데 그린다고 했다")
            }
        }
        // 기준선: 금 그림만 있는 번들은 무지개를 못 그린다(이름이 섞이지 않는다).
        let goldOnly = Set(GoldAingArt.requiredResourceNames(for: .mac) + GoldAingArt.haloCellResourceNames)
        #expect(RainbowAingArt.isDrawable(on: .mac) { goldOnly.contains($0) } == false)
    }

    // MARK: - ② 전선 — 맥 스토어의 진짜 경로

    @MainActor
    @Test("목록과 구매가 같은 번호(3/2)를 싣고, 3 일 때만 무지개 행(뽑기 전용)이 목록에 선다")
    func bothCallSitesCarryProtocolThree() async throws {
        for (label, drawable, expected) in [
            ("rainbow", ["aing", "fox", "robot", "aing_gold", "aing_rainbow"], 3),
            ("gold", ["aing", "fox", "robot", "aing_gold"], 2),
        ] {
            let host = "v0359-rainbow-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
            GomokuStubProtocol.register(host: host, handler: V0359RainbowStub.shopHandler)
            let store = V0354GoldShopProtocolTests.store(host: host, label: "v0359-" + label)
            store.drawableCharacterIDs = drawable
            #expect(store.shopProtocolVersion == expected, "\(label): 명단 \(drawable) → \(store.shopProtocolVersion)")

            store.loadShopState()
            #expect(await V0354CoreStub.waitUntil { store.shopLoaded || store.shopFailed }, "\(label): 상점 조회가 안 끝났다")
            let list = try #require(GomokuStubProtocol.calls(host: host, rpc: "shop_state").last).json
            #expect(Set(list.keys) == ["p_protocol"] && list["p_protocol"] as? Int == expected, Comment(rawValue: "\(label) 목록 본문 \(list)"))
            let rainbow = store.shopCharacters.first { $0.id == "aing_rainbow" }
            #expect((rainbow != nil) == (expected == 3), Comment(rawValue: "\(label): 목록 \(store.shopCharacters.map(\.id))"))
            if let rainbow { #expect(rainbow.gachaOnly == true && rainbow.isPurchasable == false, "무지개 행이 팔리는 줄로 읽혔다") }

            store.buyCharacter("fox")
            #expect(await V0354CoreStub.waitUntil { store.purchasingID == nil }, "\(label): 구매가 안 끝났다")
            let buy = try #require(GomokuStubProtocol.calls(host: host, rpc: "buy_character").last).json
            #expect(Set(buy.keys) == ["p_id", "p_protocol"] && buy["p_protocol"] as? Int == expected,
                    Comment(rawValue: "\(label) 구매 본문 \(buy) — 목록 3·구매 2 면 게이트가 장식이다"))
        }
    }

    // MARK: - ③ 번들 그대로의 맥

    @MainActor
    @Test("번들 그대로의 맥이 보내는 번호 — 소스 트리의 그림 파일이 기준선(robot · 금 · 무지개)")
    func shippedMacFollowsTheArtInTheTree() async throws {
        let robot = V0343RobotShopProtocolTests.robotArtInSourceTree
        let gold = V0354CoreArtBaseline.macGoldArtInSourceTree
        let rainbow = Self.macRainbowArtInSourceTree
        let expected = ShopWire.protocolVersion(drawableCharacterIDs:
            (robot ? ["robot"] : []) + (gold ? ["aing_gold"] : []) + (rainbow ? ["aing_rainbow"] : []))
        #expect(rainbow, "무지개 그림 네 장이 소스 트리에 없다 — scripts/make-rainbow-aing.swift 를 돌려라")

        let host = "v0359-rainbow-bundle-\(UUID().uuidString.prefix(8))".lowercased()
        GomokuStubProtocol.register(host: host, handler: V0359RainbowStub.shopHandler)
        let store = V0354GoldShopProtocolTests.store(host: host, label: "v0359-bundle")
        #expect(store.shopProtocolVersion == expected,
                Comment(rawValue: "robot \(robot) · 금 \(gold) · 무지개 \(rainbow) · 명단 \(store.drawableCharacterIDs) → \(store.shopProtocolVersion)"))
        #expect(store.drawableCharacterIDs.contains("aing_rainbow") == rainbow)
        store.loadShopState()
        #expect(await V0354CoreStub.waitUntil { store.shopLoaded || store.shopFailed }, "상점 조회가 안 끝났다")
        let body = try #require(GomokuStubProtocol.calls(host: host, rpc: "shop_state").last).json
        #expect((body["p_protocol"] as? Int ?? ShopWire.legacyProtocol) == expected, Comment(rawValue: "본문 \(body)"))
    }

    // MARK: - ④ 번호 2 에 머무는 클라의 소수 확률표(0.3.58 · 폰 1.0.9 가 받는 모양)

    /// 서버는 2 인 클라에게 무지개를 뺀 일곱 행만 보이고, 가중치 합 98 로 다시 나눈 **소수** 확률을 준다(3 이면 정수 그대로).
    /// 클라 디코더 · 완전성(|합 − 100| < 0.01) · 표시(소수 한 자리)가 그 모양을 그대로 받아야 0.3.58 의 뽑기가 안 닫힌다.
    @Test("p=2 소수 확률표: 서비스 디코더로 읽고 완전하다 — 표시는 3.1% · 24.5% … · 무지개 없음 / p=3 은 정수 2 · 3")
    func protocolTwoDecimalOdds() async throws {
        let host = "v0359-rainbow-odds-\(UUID().uuidString.prefix(8))".lowercased()
        GomokuStubProtocol.register(host: host, handler: V0359RainbowStub.shopHandler)
        let service = V0354GachaWireTests.service(host: host)

        let two = try await service.fetchShopState(accessToken: "t", protocolVersion: ShopWire.goldProtocol)
        let twoGacha = try #require(two.gacha, "2 를 보냈는데 gacha 가 없다")
        #expect(twoGacha.odds?.map(\.characterID) == ["aing_gold", "fox", "squirrel", "shiba", "ghost", "jellyfish", "robot"])
        #expect(twoGacha.hasCompleteOdds && twoGacha.isUsable, "합 \(twoGacha.totalPercent) — 0.3.58 의 뽑기가 닫힌다")
        #expect(twoGacha.odds?.map { GachaText.percent($0.percent) } == ["3.1%", "24.5%", "24.5%", "14.3%", "14.3%", "11.2%", "8.2%"])
        #expect(twoGacha.shardCosts?["aing_rainbow"] == nil && two.characters?.contains { $0.id == "aing_rainbow" } == false)

        // 서버가 소수 둘째 자리로 반올림해 보내도(3.06 · 24.49 …) 합이 100.00 이라 완전하다.
        let rounded = try V0354GachaWireTests.decoder().decode(ShopStateResponse.self, from: Data(
            (#"{"ruby_balance":1,"characters":[],"gacha":{"price":50,"shards":0,"odds":"# + V0359RainbowStub.oddsJSON(V0359RainbowStub.protocolTwoRounded2) + "}}").utf8))
        #expect(rounded.gacha?.hasCompleteOdds == true, "둘째 자리 반올림 합 \(rounded.gacha?.totalPercent ?? -1)")
        // 기준선(서버 쪽 주의): 첫째 자리로 반올림하면 합 100.1 — 클라가 표를 불완전으로 보고 뽑기를 닫는다(잣대가 실제로 가른다).
        let coarse = try V0354GachaWireTests.decoder().decode(ShopStateResponse.self, from: Data(
            (#"{"ruby_balance":1,"characters":[],"gacha":{"price":50,"shards":0,"odds":"# + V0359RainbowStub.oddsJSON(V0359RainbowStub.protocolTwoRounded1) + "}}").utf8))
        #expect(coarse.gacha?.hasCompleteOdds == false, "첫째 자리 반올림(합 \(coarse.gacha?.totalPercent ?? -1))이 완전으로 읽혔다")

        let three = try await service.fetchShopState(accessToken: "t", protocolVersion: ShopWire.rainbowProtocol)
        let threeGacha = try #require(three.gacha)
        #expect(threeGacha.odds?.map(\.characterID) == ["aing_gold", "aing_rainbow", "fox", "squirrel", "shiba", "ghost", "jellyfish", "robot"])
        #expect(threeGacha.odds?.map(\.percent) == [3, 2, 24, 24, 14, 14, 11, 8] && threeGacha.hasCompleteOdds)
        #expect(threeGacha.odds?.map { GachaText.percent($0.percent) }.prefix(2) == ["3%", "2%"])
        #expect(threeGacha.shardCosts?["aing_rainbow"] == 20 && threeGacha.shardCosts?["aing_gold"] == 20)
        #expect(three.characters?.first { $0.id == "aing_rainbow" }?.gachaOnly == true)
    }

    // MARK: - 기준선

    /// 맥이 무지개를 그리는 데 필요한 네 장(초상 둘 + 밝기 맵 + 정면 후광)이 소스 트리에 전부 있는가.
    static var macRainbowArtInSourceTree: Bool {
        RainbowAingArt.isDrawable(on: .mac, resourceExists: V0354CoreArtBaseline.macResourceExists)
    }
}

/// 무지개 서버 흉내(설계 확정표 — 합 100). 본문의 p_protocol 이 응답을 고른다: 3 이면 정수 · 무지개 포함, 2 면 무지개를 뺀 일곱 행을
/// 합 98 로 다시 나눈 소수(서버 numeric 나눗셈과 같은 자릿수), 2 미만이면 gacha 키 없음.
enum V0359RainbowStub {
    static let weights: [(String, Int)] = [("aing_gold", 3), ("aing_rainbow", 2), ("fox", 24), ("squirrel", 24),
                                          ("shiba", 14), ("ghost", 14), ("jellyfish", 11), ("robot", 8)]
    static let shardCosts = #"{"fox":2,"ghost":4,"robot":8,"shiba":4,"squirrel":2,"aing_gold":20,"jellyfish":5"#

    /// 2 인 클라의 표(무지개 뺀 일곱 행, × 100 / 98 — 16자리).
    static let protocolTwoFull: [(String, String)] = [
        ("aing_gold", "3.0612244897959184"), ("fox", "24.4897959183673469"), ("squirrel", "24.4897959183673469"),
        ("shiba", "14.2857142857142857"), ("ghost", "14.2857142857142857"), ("jellyfish", "11.2244897959183673"),
        ("robot", "8.1632653061224490"),
    ]
    static let protocolTwoRounded2: [(String, String)] = protocolTwoFull.map { ($0.0, String(format: "%.2f", Double($0.1)!)) }
    static let protocolTwoRounded1: [(String, String)] = protocolTwoFull.map { ($0.0, String(format: "%.1f", Double($0.1)!)) }

    static func oddsJSON(_ rows: [(String, String)]) -> String {
        "[" + rows.map { #"{"character_id":"\#($0.0)","percent":\#($0.1)}"# }.joined(separator: ",") + "]"
    }

    static func gachaJSON(protocolVersion: Int) -> String? {
        guard protocolVersion >= 2 else { return nil }
        if protocolVersion >= 3 {
            let odds = oddsJSON(weights.map { ($0.0, String($0.1)) })
            return #"{"price":50,"shards":3,"odds":"# + odds + #","shard_costs":"# + shardCosts + #","aing_rainbow":20}}"#
        }
        return #"{"price":50,"shards":3,"odds":"# + oddsJSON(protocolTwoFull) + #","shard_costs":"# + shardCosts + "}}"
    }

    static func shopRows(protocolVersion: Int) -> String {
        var rows = [#"{"id":"fox","price":60,"owned":false,"gacha_only":false}"#,
                    #"{"id":"shiba","price":100,"owned":false,"gacha_only":false}"#]
        if protocolVersion >= 1 { rows.append(#"{"id":"robot","price":200,"owned":false,"gacha_only":false}"#) }
        if protocolVersion >= 2 { rows.append(#"{"id":"aing_gold","price":1000,"owned":false,"gacha_only":true}"#) }
        if protocolVersion >= 3 { rows.append(#"{"id":"aing_rainbow","price":1000,"owned":false,"gacha_only":true}"#) }
        return "[" + rows.joined(separator: ",") + "]"
    }

    static let shopHandler: GomokuStubProtocol.Handler = { rpc, body, _ in
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        let version = json["p_protocol"] as? Int ?? 0
        switch rpc {
        case "shop_state":
            let gacha = V0359RainbowStub.gachaJSON(protocolVersion: version).map { #","gacha":"# + $0 } ?? ""
            return GomokuStubProtocol.Reply(body: #"{"ruby_balance":120,"ultra_balance":0,"ultra_price":3,"ultra_buy_max":20,"characters":"#
                                            + V0359RainbowStub.shopRows(protocolVersion: version) + gacha + "}")
        case "buy_character":
            return GomokuStubProtocol.Reply(body: #"{"status":"ok","character":"fox","price":60,"ruby_balance":60}"#)
        default:
            return nil
        }
    }
}
