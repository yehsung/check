import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 폰이 상점 RPC 에 싣는 능력 번호 **3**(v0.3.59 무지개 아잉이 · 폰 1.0.10) — 배선 한 줄(`AingCharacterArt.knownIDs` 의 `aing_rainbow`)의
/// 결과를 끝까지 잰다.
///
/// 서버(2026-10-20 운영 반영)는 `p_protocol` 로 세상을 둘로 가른다:
/// - `>= 3`: 목록·확률표·교환표에 무지개 행이 있다. 확률은 **정수 8줄**(황금 3 · 무지개 2 · 여우 24 · 다람쥐 24 · 시바 14 ·
///   유령 14 · 해파리 11 · 로봇 8 = 100)이고 `shard_costs.aing_rainbow = 20` 이다.
/// - `< 3`: 무지개 행을 **아예 안 보낸다**. 남은 7줄(합 98)을 100 으로 다시 나눈 **소수** 확률표가 온다.
///
/// 그래서 번호가 2 에 머문 폰은 무지개를 뽑지도, 조각으로 바꾸지도 못한다 — "그림은 번들에 있는데 아무도 못 본다".
/// 반대로 그림 없이 3 을 말하면 아잉 그림의 "무지개 아잉이"를 뽑는다(v0.3.43 robot 이 막은 그 사고). 두 방향을 다 못 박는다.
///
/// 네 겹(맥·금 스위트와 같은 모양):
///  ① 파생 — 번들 초상 **파일**(기준선) ⟺ 3, 그리고 목록에서 무지개를 빼면 3 이 **아니다**(목록 ⟺ 번호 양방향).
///  ② 그림 — 초상 두 장이 번들에 실제로 있고, `aing_rainbow` 가 아잉으로 접히지 않는다.
///  ③ 사는 줄이 아니다 — 서버 표식(`gacha_only`) 없이도 뽑기 전용이고 루비로 못 산다.
///  ④ 전선 — `MeStore` 의 진짜 경로가 3 을 싣고(목록·구매·뽑기), 3 일 때만 무지개 행·확률·교환값이 선다. 2 로 떨어진 폰은
///     무지개 없는 소수 확률표를 받고도 **표가 완전하다**(뽑기가 닫히지 않는다).
@Suite("폰 무지개 아잉이 능력 번호 3(1.0.10)")
struct MeRainbowProtocolTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// 기준선은 `knownIDs` 가 아니라 **번들에 실릴 초상 파일**이다(같은 목록으로 기대값을 만들면 영원히 초록이다).
    /// 요구 파일 목록은 코어가 한 곳에서 말한다(`RainbowAingArt.requiredResourceNames(for: .phone)` — 폰은 3D 가 없다).
    static var rainbowPortraitsExist: Bool {
        RainbowAingArt.isDrawable(on: .phone) { name in
            FileManager.default.fileExists(atPath: root
                .appendingPathComponent("Sources/CheckMobileShared/Resources/Portraits/\(name).\(RainbowAingArt.resourceExtension)").path)
        }
    }

    /// 번호는 누적이라 앞 문턱의 그림도 전제다(robot → 금 → 무지개).
    static var robotPortraitExists: Bool { MeShopProtocolTests.robotPortraitExists }
    static var goldPortraitsExist: Bool { MeGoldShopProtocolTests.goldPortraitsExist }

    // MARK: - 픽스처 — 서버가 번호에 따라 주는 두 모양

    /// `p_protocol >= 3` 의 응답: 무지개 행이 있고 확률은 **정수 8줄**, 교환표에 `aing_rainbow: 20`.
    static func shopStateV3(ruby: Int = 400, shards: Int = 0, owned: Set<String> = ["fox"]) -> String {
        func row(_ id: String, _ price: Int, gachaOnly: Bool = false) -> String {
            #"{"id":"\#(id)","price":\#(price),"owned":\#(owned.contains(id)),"gacha_only":\#(gachaOnly)}"#
        }
        let rows = [row("fox", 60), row("squirrel", 60), row("ghost", 100), row("shiba", 100), row("jellyfish", 140),
                    row("robot", 200), row("aing_gold", 1_000, gachaOnly: true),
                    row("aing_rainbow", 1_000, gachaOnly: true)].joined(separator: ",")
        return #"""
        {"ruby_balance":\#(ruby),"characters":[\#(rows)],
         "gacha":{"price":50,"shards":\#(shards),
                  "odds":[{"character_id":"aing_gold","percent":3},{"character_id":"aing_rainbow","percent":2},
                          {"character_id":"fox","percent":24},{"character_id":"squirrel","percent":24},
                          {"character_id":"shiba","percent":14},{"character_id":"ghost","percent":14},
                          {"character_id":"jellyfish","percent":11},{"character_id":"robot","percent":8}],
                  "shard_costs":{"aing_gold":20,"aing_rainbow":20,"fox":2,"squirrel":2,"shiba":4,"ghost":4,"jellyfish":5,"robot":8}}}
        """#
    }

    /// `p_protocol < 3` 의 응답(= 2 를 말한 폰이 **지금** 운영 서버에서 받는 모양): 무지개 행이 없고, 남은 7줄을 100 으로 다시 나눈
    /// 소수 확률이다. 숫자는 서버가 주는 값 그대로 적었다 — 합이 **정확히** 100.0000 이라 `hasCompleteOdds` 가 참이어야 한다
    /// (3.0612 + 24.4898 + 24.4898 + 14.2857 + 14.2857 + 11.2245 + 8.1633).
    static let shopStateV2Decimal = #"""
    {"ruby_balance":400,"characters":[{"id":"fox","price":60,"owned":true},{"id":"squirrel","price":60,"owned":false},
     {"id":"ghost","price":100,"owned":false},{"id":"shiba","price":100,"owned":false},
     {"id":"jellyfish","price":140,"owned":false},{"id":"robot","price":200,"owned":false},
     {"id":"aing_gold","price":1000,"owned":false,"gacha_only":true}],
     "gacha":{"price":50,"shards":0,
              "odds":[{"character_id":"aing_gold","percent":3.0612},{"character_id":"fox","percent":24.4898},
                      {"character_id":"squirrel","percent":24.4898},{"character_id":"shiba","percent":14.2857},
                      {"character_id":"ghost","percent":14.2857},{"character_id":"jellyfish","percent":11.2245},
                      {"character_id":"robot","percent":8.1633}],
              "shard_costs":{"aing_gold":20,"fox":2,"squirrel":2,"shiba":4,"ghost":4,"jellyfish":5,"robot":8}}}
    """#

    /// 서버가 무지개 행에 `gacha_only` 표식을 **빼고** 명목가 1000 만 준 모양(표식이 빠지거나 false 로 오는 창 — 옛 가격표 ·
    /// 운영자 수정). 그래도 폰은 사는 줄로 세우지 않는다(판정이 서버 표식에만 매달려 있으면 [1000 사기] 가 켜진다).
    static let shopStateRainbowWithoutFlag = #"""
    {"ruby_balance":5000,"characters":[{"id":"fox","price":60,"owned":false},
     {"id":"ghost","price":100,"owned":false},
     {"id":"aing_rainbow","price":1000,"owned":false}],
     "gacha":{"price":50,"shards":0,
              "odds":[{"character_id":"aing_rainbow","percent":2},{"character_id":"fox","percent":49},
                      {"character_id":"ghost","percent":49}],
              "shard_costs":{"aing_rainbow":20,"fox":2,"ghost":4}}}
    """#

    // MARK: - ① 파생 — 번들 ⟺ 3, 목록 ⟺ 번호 양방향

    @Test("번들 그대로의 폰은 3 을 말한다 · 목록에서 무지개를 빼면 3 이 아니다 — 양방향")
    func protocolTracksRainbowPortraits() {
        #expect(ShopWire.rainbowProtocol == 3, "서버 `character_prices.min_protocol = 3` 과 같은 숫자여야 한다")
        #expect(Self.rainbowPortraitsExist,
                "전제: 무지개 초상 두 장이 폰 번들 자리(Sources/CheckMobileShared/Resources/Portraits)에 있다")

        let known = AingCharacterArt.knownIDs
        let derived = ShopWire.protocolVersion(drawableCharacterIDs: known)
        let expectsRainbow = Self.rainbowPortraitsExist && Self.goldPortraitsExist && Self.robotPortraitExists
        #expect((derived == ShopWire.rainbowProtocol) == expectsRainbow,
                Comment(rawValue: "무지개 초상 \(Self.rainbowPortraitsExist) · 금 \(Self.goldPortraitsExist) · robot \(Self.robotPortraitExists)"
                        + " · 목록 \(known) → \(derived)"
                        + (Self.rainbowPortraitsExist && !known.contains(ShopWire.rainbowCharacterID)
                           ? " — 무지개 초상이 실렸는데 knownIDs 에 aing_rainbow 가 없다: AingCharacterArt.knownIDs 에 더해라" : "")))
        #expect(known.contains(ShopWire.rainbowCharacterID) == Self.rainbowPortraitsExist,
                "번들 초상과 knownIDs 가 갈렸다 — 목록에만 있으면 아잉 그림의 무지개 카드가 뽑히고, 파일만 있으면 아무도 못 본다")
        // 위험한 방향은 못으로: 무지개 초상이 없으면 3 을 절대 안 보낸다.
        if !Self.rainbowPortraitsExist { #expect(derived < ShopWire.rainbowProtocol) }

        // 반대 방향 — 이 한 줄이 번호를 올린 방아쇠다. 목록에서 무지개만 빼면 3 이 아니고, 금까지의 번호(2)로 떨어진다.
        let without = known.filter { $0 != ShopWire.rainbowCharacterID }
        let derivedWithout = ShopWire.protocolVersion(drawableCharacterIDs: without)
        #expect(derivedWithout != ShopWire.rainbowProtocol,
                Comment(rawValue: "무지개를 뺀 목록 \(without) 이 아직 3 이다 — 번호가 목록에서 파생되지 않는다(어딘가에 숫자를 박았다)"))
        #expect(derivedWithout == ShopWire.goldProtocol, Comment(rawValue: "무지개를 뺀 목록 → \(derivedWithout)"))
        // 그리고 무지개만 있고 금이 없으면 3 도 2 도 아니다(번호는 누적이다 — 건너뛰어 말할 수 없다).
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: ["aing", "robot", "aing_rainbow"]) == ShopWire.robotProtocol)
    }

    // MARK: - ② 그림 — 초상 두 장이 번들에 있고, 아잉으로 접히지 않는다

    @Test("무지개 초상 두 장이 번들에 실제로 있고(아잉 그림이 아니다), aing_rainbow 가 모르는 id 로 접히지 않는다")
    func rainbowPortraitsAreBundledAndResolve() throws {
        let id = CharacterCatalog.rainbowAingID
        #expect(id == "aing_rainbow")
        // 모르는 id 는 아잉으로 접히므로 `portraitURL` 은 **nil 이 아닌 것만으로는 아무것도 증명하지 못한다** —
        // 돌아온 파일 이름을 본다(아잉 초상이 오면 빨강).
        for expression in AingCharacterArt.Expression.allCases {
            let url = try #require(AingCharacterArt.portraitURL(id: id, expression: expression),
                                   "\(id)-\(expression.rawValue) 초상이 번들에 없다")
            #expect(url.lastPathComponent == "\(id)-\(expression.rawValue).png",
                    Comment(rawValue: "무지개 초상 자리에 \(url.lastPathComponent) 가 왔다"))
            #expect(FileManager.default.fileExists(atPath: url.path))
            let image = try #require(AingCharacterArt.portraitImage(id: id, expression: expression), "디코드 실패")
            #expect(image.width == AingCharacterArt.portraitPixelSize && image.height == AingCharacterArt.portraitPixelSize)
        }
        #expect(AingCharacterArt.portraitName(id: id, expression: .neutral) == "aing_rainbow-neutral")
        #expect(AingCharacterArt.portraitName(id: id, expression: .negative) == "aing_rainbow-negative")
        // 코어가 요구하는 이름과 폰이 찾는 이름이 **같은 글자**여야 한다(아트 스크립트·맥 번들과 같은 이름).
        #expect(RainbowAingArt.requiredResourceNames(for: .phone)
                == [AingCharacterArt.portraitName(id: id, expression: .neutral),
                    AingCharacterArt.portraitName(id: id, expression: .negative)])

        // 착용값 접기: 정확히 그 글자만 산다(서버 값은 정확히 `aing_rainbow` 다).
        #expect(AingCharacterArt.resolvedID(id) == id, "무지개 착용값이 아잉으로 접혔다 — 화면·위젯에 보라 아잉이 선다")
        #expect(AingCharacterArt.resolvedID(" aing_rainbow ") == id, "앞뒤 공백은 봐준다")
        #expect(AingCharacterArt.resolvedID("AING_RAINBOW") == AingCharacterArt.defaultID, "대문자는 그 id 가 아니다")
        #expect(AingCharacterArt.resolvedID("aing_rainbow2") == AingCharacterArt.defaultID)
    }

    // MARK: - ③ 사는 줄이 아니다 — 서버 표식 없이도

    @MainActor
    @Test("무지개는 서버 표식(gacha_only)이 없어도 뽑기 전용이다 · 루비로 못 산다 · 눌러도 안 골라지고 요청도 안 나간다")
    func rainbowIsGachaOnlyWithoutServerFlag() async throws {
        let harness = await RankMeHarness(label: "me-rainbow-not-for-sale") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me

        // 가장 센 모양: 상점을 **아직 한 번도 못 읽었다**(서버 표식이 존재하지 않는다).
        #expect(store.shopCharacters.isEmpty, "전제: 서버 행이 하나도 없다")
        #expect(store.isGachaOnly(CharacterCatalog.rainbowAingID),
                "서버 표식 없이 뽑기 전용이 아니다 — 내장 판정(CharacterCatalog.isGachaOnlyBuiltIn)을 안 묻는다")
        #expect(store.isGachaOnly(CharacterCatalog.goldAingID), "기준선: 금도 표식 없이 뽑기 전용이다")
        #expect(!store.isGachaOnly("ghost"), "기준선: 파는 캐릭터는 표식 없이 뽑기 전용이 아니다")

        // 서버가 `gacha_only` 를 빼고 명목가 1000 만 준 행이 와도 그대로다.
        harness.enqueue("shop_state", .json(Self.shopStateRainbowWithoutFlag))
        await store.loadShop()
        let row = try #require(store.shopCharacters.first { $0.id == CharacterCatalog.rainbowAingID },
                               "전제: 서버가 무지개 행을 줬다")
        #expect(row.gachaOnly != true, "전제: 이 픽스처의 무지개 행에는 표식이 없다")
        #expect(row.price == 1_000, "전제: 명목가 1000 이 실려 있다")
        #expect(row.isPurchasable == false, "코어가 명목가를 살 수 있는 값으로 읽는다")

        #expect(store.isGachaOnly(CharacterCatalog.rainbowAingID))
        #expect(store.price(of: CharacterCatalog.rainbowAingID) == nil, "명목가 1000 이 상점가로 읽힌다 — [1000 사기] 가 켜진다")
        #expect(store.price(of: "ghost") == 100, "기준선: 파는 캐릭터는 값이 있다")

        // 눌러도 고르지 않고 얻는 길을 말한다(사는 줄이 아니다).
        store.selectShopItem(CharacterCatalog.rainbowAingID)
        #expect(store.shopSelection == nil && !store.canConfirmPurchase, "무지개를 사려고 고를 수 있다")
        #expect(store.shopGachaHintID == CharacterCatalog.rainbowAingID)
        #expect(store.shopSelectionPrice == nil)
        store.confirmPurchase()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "buy_character").isEmpty, "무지개를 사려 했다 — 서버가 not_for_sale 로 거절한다")
        // 기준선: 유령은 고르면 살 수 있다(문이 통째로 잠긴 게 아니다).
        store.selectShopItem("ghost")
        #expect(store.shopSelection == "ghost" && store.canConfirmPurchase)
        harness.expectNoForbiddenCalls()
    }

    // MARK: - ④ 전선 — 두 세상 모두

    @MainActor
    @Test("목록·구매·뽑기가 같은 번호(3/2)를 싣고, 3 일 때만 무지개 행·확률 2%·교환값 20 이 선다")
    func bothWorldsFollowTheProtocolOnTheWire() async throws {
        for (label, drawable, expected) in [
            ("rainbow", ["aing", "fox", "robot", "aing_gold", "aing_rainbow"], ShopWire.rainbowProtocol),
            ("gold", ["aing", "fox", "robot", "aing_gold"], ShopWire.goldProtocol),
        ] {
            // 스텁도 서버처럼 **보유를 기억한다** — 뽑은 뒤 상점을 다시 읽는데(`startGachaPull`), 그 응답이 옛 보유를
            // 말하면 방금 뽑은 캐릭터가 화면에서 사라진다(서버 값이 진실이라 클라가 이긴 척하지 않는다).
            let owned = BaseLockedBox<Set<String>>(["fox"])
            let harness = await RankMeHarness(label: "me-rainbow-protocol-\(label)") { request in
                switch request.rpcName {
                case "shop_state":
                    let version = request.jsonBody["p_protocol"] as? Int ?? ShopWire.legacyProtocol
                    // 서버처럼: 3 미만에는 무지개를 **아예 안 보내고** 7줄 소수 확률표를 준다.
                    return .json(version >= ShopWire.rainbowProtocol
                                 ? Self.shopStateV3(shards: 19, owned: owned.get()) : Self.shopStateV2Decimal)
                case "buy_character": return .json(#"{"status":"ok","character":"squirrel","price":60,"ruby_balance":340}"#)
                case "gacha_pull":
                    let version = request.jsonBody["p_protocol"] as? Int ?? ShopWire.legacyProtocol
                    // 3 을 받은 서버만 무지개를 추첨 풀에 넣는다.
                    let id = version >= ShopWire.rainbowProtocol ? "aing_rainbow" : "ghost"
                    owned.mutate { $0.insert(id) }
                    return .json(#"{"status":"ok","character_id":"\#(id)","duplicate":false,"shards_gained":0,"shards":19,"ruby_balance":350,"price":50,"request_id":"00000000-0000-4000-8000-0000000000a1","replayed":false}"#)
                default: return nil
                }
            }
            defer { harness.tearDown() }
            let store = harness.me
            store.drawableCharacterIDs = drawable
            #expect(store.shopProtocolVersion == expected, Comment(rawValue: "\(label): \(drawable) → \(store.shopProtocolVersion)"))

            // ── 목록 ──
            await store.loadShop()
            let list = try #require(harness.requests(rpc: "shop_state").last?.jsonBody)
            #expect(Set(list.keys) == ["p_protocol"], Comment(rawValue: "\(label) 목록 본문 \(list)"))
            #expect(list["p_protocol"] as? Int == expected, Comment(rawValue: "\(label) 목록 본문 \(list)"))

            let isRainbowWorld = expected == ShopWire.rainbowProtocol
            let rainbowRow = store.shopCharacters.first { $0.id == CharacterCatalog.rainbowAingID }
            #expect((rainbowRow != nil) == isRainbowWorld,
                    Comment(rawValue: "\(label): \(store.shopCharacters.map(\.id))"))
            if let rainbowRow {
                #expect(rainbowRow.gachaOnly == true && rainbowRow.isPurchasable == false)
                #expect(store.price(of: CharacterCatalog.rainbowAingID) == nil)
            }

            // ── 확률표: 두 세상 모두 **완전하다**(뽑기가 닫히지 않는다) ──
            let info = try #require(store.gachaInfo, "\(label): 서버가 gacha 를 줬는데 안 옮겼다")
            #expect(info.hasCompleteOdds, Comment(rawValue: "\(label): 확률표 합 \(info.totalPercent) — 깨진 줄을 버렸다"))
            #expect(abs(info.totalPercent - 100) < 0.0001, Comment(rawValue: "\(label): 합 \(info.totalPercent)"))
            #expect(store.showsGacha && store.canPullGacha, Comment(rawValue: "\(label): 뽑기가 닫혔다"))

            let rows = store.gachaOddsRows
            if isRainbowWorld {
                // 서버 순서 그대로 8줄 · 이름은 내장 카탈로그 이름 · 무지개는 사는 줄이 아니다 · 교환값은 서버 값.
                #expect(rows.map(\.characterID)
                        == ["aing_gold", "aing_rainbow", "fox", "squirrel", "shiba", "ghost", "jellyfish", "robot"])
                #expect(rows.map(\.percentText) == ["3%", "2%", "24%", "24%", "14%", "14%", "11%", "8%"])
                let rainbow = try #require(rows.first { $0.characterID == CharacterCatalog.rainbowAingID })
                #expect(rainbow.name == "무지개 아잉이", Comment(rawValue: "이름 \(rainbow.name) — 카드가 없어도 내장 이름이 선다"))
                #expect(rainbow.percentText == "2%" && rainbow.percent == 2)
                #expect(rainbow.isGachaOnly && rainbow.shopPrice == nil, "명목가 1000 이 상점가로 섰다")
                #expect(rainbow.priceText == "뽑기 또는 조각 20개" && rainbow.priceText != "1000")
                #expect(rainbow.isRainbow && !rainbow.isGold && rainbow.finish == .rainbow)
                #expect(rainbow.shardCost == 20)
                // 교환표: 희귀가 맨 위(금 → 무지개), 그다음 서버 순서. 값은 서버 교환표의 것이다(조각 19 라 1 모자라다).
                #expect(store.gachaExchangeRows.map(\.characterID)
                        == ["aing_gold", "aing_rainbow", "fox", "squirrel", "shiba", "ghost", "jellyfish", "robot"])
                #expect(store.gachaShardCost(of: CharacterCatalog.rainbowAingID) == 20)
                #expect(store.gachaExchangeAvailability(CharacterCatalog.rainbowAingID) == .short(cost: 20, missing: 1))
            } else {
                // 무지개가 빠진 7줄 — 소수 확률이 그대로 서고(버림 없이), 무지개는 어디에도 없다.
                #expect(rows.map(\.characterID) == ["aing_gold", "fox", "squirrel", "shiba", "ghost", "jellyfish", "robot"])
                #expect(rows.map(\.percentText) == ["3.1%", "24.5%", "24.5%", "14.3%", "14.3%", "11.2%", "8.2%"])
                #expect(!rows.contains { $0.characterID == CharacterCatalog.rainbowAingID },
                        "서버가 안 준 무지개 줄을 클라가 지어냈다")
                #expect(store.gachaShardCost(of: CharacterCatalog.rainbowAingID) == nil)
                #expect(store.gachaExchangeAvailability(CharacterCatalog.rainbowAingID) == .notExchangeable)
                #expect(!store.gachaExchangeRows.contains { $0.characterID == CharacterCatalog.rainbowAingID })
            }

            // ── 구매: 목록과 **같은 번호** ──
            store.selectShopItem("squirrel")
            #expect(store.canConfirmPurchase, "\(label): 고르고도 살 수 없다 — 픽스처 잔량·가격을 확인해라")
            store.confirmPurchase()
            #expect(await baseWaitUntil { store.purchasingID == nil }, "구매가 안 끝났다")
            let buy = try #require(harness.requests(rpc: "buy_character").last?.jsonBody)
            #expect(Set(buy.keys) == ["p_id", "p_protocol"], Comment(rawValue: "\(label) 구매 본문 \(buy)"))
            #expect(buy["p_protocol"] as? Int == expected,
                    Comment(rawValue: "\(label) 구매 본문 \(buy) — 목록 3·구매 2 면 게이트가 장식이다"))

            // ── 뽑기: 같은 번호 · 3 을 받은 서버만 무지개를 준다 ──
            store.pullGacha()
            await harness.quiesceMe()
            let pull = try #require(harness.requests(rpc: "gacha_pull").last?.jsonBody)
            #expect(Set(pull.keys) == ["p_protocol", "p_request_id"], Comment(rawValue: "\(label) 뽑기 본문 \(pull)"))
            #expect(pull["p_protocol"] as? Int == expected,
                    Comment(rawValue: "\(label) 뽑기 본문 \(pull) — 2 를 실으면 서버가 무지개를 뺀 풀로 추첨한다"))
            let result = try #require(store.lastGachaResult, "\(label): 뽑기 결과를 안 옮겼다")
            if isRainbowWorld {
                #expect(result.characterID == CharacterCatalog.rainbowAingID)
                #expect(result.kind == .rainbow && result.isRainbow && !result.isGold)
                #expect(GachaText.headline(for: result, name: store.gachaName(result.characterID)) == "무지개 아잉이!")
                #expect(store.isOwned(CharacterCatalog.rainbowAingID), "뽑았는데 보유로 안 들어갔다")
            } else {
                #expect(result.characterID == "ghost" && result.kind == .newCharacter)
                #expect(!store.isOwned(CharacterCatalog.rainbowAingID))
            }
            harness.expectNoForbiddenCalls()
        }
    }

    // MARK: - ⑤ 번들 그대로 — 지금 출하되는 폰이 내보내는 본문

    @MainActor
    @Test("번들 그대로의 폰이 보내는 본문은 무지개 초상 파일이 있을 때만 3 이다 · 교환값 20 은 서버 값이다")
    func shippedPhoneBodyFollowsRainbowPortraits() async throws {
        // 두 번째 조회의 몸통을 바꿔 끼우려면 상자가 필요하다 — 이 하네스는 `responder` 가 `shop_state` 를 **먼저** 답하므로
        // `enqueue` 가 아예 안 쓰인다(그 함정에 한 번 걸렸다).
        let body = BaseLockedBox(Self.shopStateV3(shards: 19))
        let harness = await RankMeHarness(label: "me-rainbow-protocol-bundle") { request in
            request.rpcName == "shop_state" ? .json(body.get()) : nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadShop()
        let list = try #require(harness.requests(rpc: "shop_state").last?.jsonBody)
        let sent = list["p_protocol"] as? Int ?? ShopWire.legacyProtocol
        let expectsRainbow = Self.rainbowPortraitsExist && Self.goldPortraitsExist && Self.robotPortraitExists
        #expect((sent == ShopWire.rainbowProtocol) == expectsRainbow,
                Comment(rawValue: "본문 \(list) · 무지개 초상 \(Self.rainbowPortraitsExist)"))
        // 위험한 방향: 무지개 초상이 없는 폰은 절대 3 을 보내지 않는다(아잉 그림의 '무지개 아잉이'를 뽑게 된다).
        if !Self.rainbowPortraitsExist { #expect(sent < ShopWire.rainbowProtocol) }

        // 20 을 클라가 적지 않는다 — 서버가 값을 바꾸면 화면도 바뀐다(기준선이 다르다).
        #expect(store.gachaShardCost(of: CharacterCatalog.rainbowAingID) == 20)
        body.mutate { $0 = $0.replacingOccurrences(of: #""aing_rainbow":20"#, with: #""aing_rainbow":25"#) }
        await store.loadShop()
        #expect(store.gachaShardCost(of: CharacterCatalog.rainbowAingID) == 25, "교환값 20 을 클라가 박았다")
        #expect(store.gachaExchangeAvailability(CharacterCatalog.rainbowAingID) == .short(cost: 25, missing: 6))
        harness.expectNoForbiddenCalls()
    }
}
