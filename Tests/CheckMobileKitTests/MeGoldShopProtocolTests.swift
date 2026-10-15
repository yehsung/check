import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 폰이 상점 RPC 에 싣는 능력 번호 2(v0.3.54 황금 아잉이 · 뽑기).
///
/// 폰에서 "황금 아잉이를 그릴 수 있다"는 **번들 초상 두 장**이다(`GoldAingArt.requiredResourceNames(for: .phone)` — 3D 가 없다).
/// 재료는 robot 때와 같은 `AingCharacterArt.knownIDs` 라, 초상이 들어오고 knownIDs 에 `aing_gold` 를 더하는 순간 저절로 2 가 된다.
///
/// 세 겹(맥 V0354GoldShopProtocolTests 와 같은 모양):
///  ① 파생 — 번들 초상 파일(기준선) ⟺ 2. knownIDs 와 파일이 갈리면 빨갛다.
///  ② 전선 — `MeStore` 의 진짜 경로(`loadShop()`·`confirmPurchase()`)가 2 를 **같이** 싣고, 서버가 준 금 행이 목록에 선다.
///  ③ 번들 그대로 — 지금 출하되는 폰이 내보내는 본문.
///
/// ★ 그림(A)이 폰 번들에 들어오고 knownIDs(P)가 아직이면 ①③ 이 **일부러 빨개진다** — "초상은 실렸는데 폰이 2 를 안 말한다
///   = 폰에서 뽑기가 통째로 안 보인다" 의 신호다(robot 의 `phoneStillSendsLegacyProtocol` 과 같은 관용).
@Suite struct MeGoldShopProtocolTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// 기준선: 폰 번들에 실릴 금 초상 두 장(`Package.swift` 의 `.copy("Resources/Portraits")`).
    static var goldPortraitsExist: Bool {
        GoldAingArt.isDrawable(on: .phone) { name in
            FileManager.default.fileExists(atPath: root
                .appendingPathComponent("Sources/CheckMobileShared/Resources/Portraits/\(name).\(GoldAingArt.resourceExtension)").path)
        }
    }

    static var robotPortraitExists: Bool { MeShopProtocolTests.robotPortraitExists }

    static let shopStateV2 = #"""
    {"ruby_balance":400,"characters":[{"id":"fox","price":60,"owned":false,"gacha_only":false},
     {"id":"robot","price":200,"owned":false,"gacha_only":false},
     {"id":"aing_gold","price":1000,"owned":false,"gacha_only":true}],
     "gacha":{"price":50,"shards":0,"odds":[{"character_id":"aing_gold","percent":5},{"character_id":"fox","percent":95}],
              "shard_costs":{"fox":3}}}
    """#
    static let shopStateV1 = #"{"ruby_balance":400,"characters":[{"id":"fox","price":60,"owned":false}]}"#

    // MARK: - ① 파생

    @Test("폰이 보내는 번호는 금 초상(과 robot 초상)이 번들에 있을 때만 2 다 — 양방향")
    func phoneProtocolTracksGoldPortraits() {
        let known = AingCharacterArt.knownIDs
        let derived = ShopWire.protocolVersion(drawableCharacterIDs: known)
        let expectsGold = Self.goldPortraitsExist && Self.robotPortraitExists
        #expect((derived == ShopWire.goldProtocol) == expectsGold,
                Comment(rawValue: "금 초상 \(Self.goldPortraitsExist) · robot 초상 \(Self.robotPortraitExists) · 목록 \(known) → \(derived)"
                        + (Self.goldPortraitsExist && !known.contains("aing_gold")
                           ? " — 금 초상이 실렸는데 knownIDs 에 aing_gold 가 없다: AingCharacterArt.knownIDs 에 더해라" : "")))
        #expect(known.contains(ShopWire.goldCharacterID) == Self.goldPortraitsExist,
                "번들 초상과 knownIDs 가 갈렸다 — 목록에만 있으면 아잉 그림의 금 카드가 팔리고, 파일만 있으면 아무도 못 본다")
    }

    // MARK: - ② 전선

    @MainActor
    @Test("폰 목록·구매가 같은 번호(2/1)를 싣고, 2 일 때만 서버의 금 행(뽑기 전용)이 목록에 선다")
    func bothPhoneCallSitesCarryProtocolTwo() async throws {
        for (label, drawable, expected) in [
            ("gold", ["aing", "fox", "robot", "aing_gold"], ShopWire.goldProtocol),
            ("robot", ["aing", "fox", "robot"], ShopWire.robotProtocol),
        ] {
            let harness = await RankMeHarness(label: "me-gold-protocol-\(label)") { request in
                switch request.rpcName {
                case "shop_state":
                    let version = request.jsonBody["p_protocol"] as? Int ?? 0
                    return .json(version >= 2 ? Self.shopStateV2 : Self.shopStateV1)
                case "buy_character": return .json(#"{"status":"ok","character":"fox","price":60,"ruby_balance":340}"#)
                default: return nil
                }
            }
            defer { harness.tearDown() }
            let store = harness.me
            store.drawableCharacterIDs = drawable
            #expect(store.shopProtocolVersion == expected, Comment(rawValue: "\(label): \(drawable) → \(store.shopProtocolVersion)"))

            await store.loadShop()
            let list = try #require(harness.requests(rpc: "shop_state").last?.jsonBody)
            #expect(Set(list.keys) == ["p_protocol"], Comment(rawValue: "\(label) 목록 본문 \(list)"))
            #expect(list["p_protocol"] as? Int == expected, Comment(rawValue: "\(label) 목록 본문 \(list)"))
            // 결과까지: 서버가 준 금 행이 목록에 서고, 뽑기 전용으로 읽힌다(사는 줄이 아니다).
            let gold = store.shopCharacters.first { $0.id == "aing_gold" }
            #expect((gold != nil) == (expected == ShopWire.goldProtocol), Comment(rawValue: "\(label): \(store.shopCharacters.map(\.id))"))
            if let gold { #expect(gold.gachaOnly == true && gold.isPurchasable == false) }

            store.selectShopItem("fox")
            #expect(store.canConfirmPurchase, "고르고도 살 수 없다 — 픽스처 잔량·가격을 확인해라")
            store.confirmPurchase()
            #expect(await baseWaitUntil { store.purchasingID == nil }, "구매가 안 끝났다")
            let buy = try #require(harness.requests(rpc: "buy_character").last?.jsonBody)
            #expect(Set(buy.keys) == ["p_id", "p_protocol"], Comment(rawValue: "\(label) 구매 본문 \(buy)"))
            #expect(buy["p_protocol"] as? Int == expected,
                    Comment(rawValue: "\(label) 구매 본문 \(buy) — 목록 2·구매 1 이면 게이트가 장식이다"))
            harness.expectNoForbiddenCalls()
        }
    }

    // MARK: - ③ 번들 그대로

    @MainActor
    @Test("번들 그대로의 폰이 보내는 번호 — 금 초상 파일이 기준선")
    func shippedPhoneBodyFollowsGoldPortraits() async throws {
        let harness = await RankMeHarness(label: "me-gold-protocol-bundle") { request in
            request.rpcName == "shop_state" ? .json(Self.shopStateV1) : nil
        }
        defer { harness.tearDown() }
        await harness.me.loadShop()
        let list = try #require(harness.requests(rpc: "shop_state").last?.jsonBody)
        let sent = list["p_protocol"] as? Int ?? ShopWire.legacyProtocol
        let expectsGold = Self.goldPortraitsExist && Self.robotPortraitExists
        #expect((sent == ShopWire.goldProtocol) == expectsGold,
                Comment(rawValue: "본문 \(list) · 금 초상 \(Self.goldPortraitsExist)"))
        // 위험한 방향은 무조건 막는다: 금 초상이 없는 폰은 절대 2 를 보내지 않는다(아잉 그림의 '황금 아잉이'를 뽑게 된다).
        if !Self.goldPortraitsExist { #expect(sent < ShopWire.goldProtocol) }
    }
}
