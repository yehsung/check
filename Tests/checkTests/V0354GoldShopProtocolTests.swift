import Foundation
import Testing
@testable import check
@testable import CheckCore

/// v0.3.54 황금 아잉이 — 상점 능력 번호 2(`ShopWire.goldProtocol`)와 "그릴 수 있다"의 정의(`GoldAingArt`).
///
/// 이 스위트가 지키는 사실(robot 의 V0343 과 같은 세 겹):
///  ① 파생 — "aing_gold **와** robot 을 그릴 수 있다" ⟺ 2. 번호는 누적이라 금만 있고 robot 이 없으면 2 를 보내지 않는다.
///  ② 전선 — 맥 스토어의 진짜 경로(`loadShopState`·`buyCharacter`)가 그 번호를 **같이** 싣는다(가짜 명단으로 양쪽 분기).
///  ③ 번들 그대로 — 소스 트리의 금 그림 파일이 기준선이다(파생과 같은 식으로 기대값을 만들면 영원히 초록이다).
///
/// ★ ③ 은 그림(A)이 들어오고 맥 초상 조회(M)가 아직 배선되지 않은 상태에서 **일부러 빨개진다** —
///   "그림은 실렸는데 맥이 서버에 2 를 안 말한다 = 뽑기가 통째로 안 보인다" 를 알리는 신호다(V0343 ③ 과 같은 관용).
@Suite("v0.3.54 황금 아잉이 상점 프로토콜")
struct V0354GoldShopProtocolTests {

    // MARK: - ① 파생

    @Test("파생 함수: robot 이 있으면 1, robot 과 aing_gold 가 둘 다 있을 때만 2 — 금만 있으면 0")
    func derivationIsCumulative() {
        let sprites = ["aing", "fox", "ghost", "jellyfish", "shiba", "squirrel"]
        let table: [([String], Int)] = [
            ([], 0),
            (sprites, 0),
            (sprites + ["robot"], 1),
            (sprites + ["robot", "aing_gold"], 2),
            (["aing_gold", "robot"], 2),
            // 금만 있고 robot 이 없다: 2 를 보내면 서버가 robot 카드를 내려 준다(아잉 그림으로 팔린다). 1 도 못 보낸다.
            (sprites + ["aing_gold"], 0),
            // 비슷한 이름에 반응하면 안 된다(하이픈 · 대문자 · 접두사 겹침 · 공백).
            (sprites + ["robot", "aing-gold"], 1),
            (sprites + ["robot", "AING_GOLD"], 1),
            (sprites + ["robot", "aing_golden"], 1),
            (sprites + ["robot", " aing_gold"], 1),
            (sprites + ["robot", "gold"], 1),
        ]
        for (ids, expected) in table {
            #expect(ShopWire.protocolVersion(drawableCharacterIDs: ids) == expected,
                    Comment(rawValue: "\(ids) → \(ShopWire.protocolVersion(drawableCharacterIDs: ids)), 기대 \(expected)"))
        }
        // 상수끼리의 관계(누적): 0 < 1 < 2, 금 id 는 카탈로그 내장 id 와 같은 글자다.
        #expect(ShopWire.legacyProtocol < ShopWire.robotProtocol && ShopWire.robotProtocol < ShopWire.goldProtocol)
        #expect(ShopWire.goldCharacterID == "aing_gold")
        #expect(ShopWire.goldCharacterID == CharacterCatalog.goldAingID)
    }

    @Test("뽑기 문턱은 2 — 서버 gacha_pull/gacha_exchange 의 p_protocol >= 2 와 같다")
    func gachaThresholdMatchesServer() {
        #expect(ShopWire.supportsGacha(protocolVersion: 0) == false)
        #expect(ShopWire.supportsGacha(protocolVersion: 1) == false)
        #expect(ShopWire.supportsGacha(protocolVersion: 2) == true)
        #expect(ShopWire.supportsGacha(protocolVersion: 3) == true)
    }

    /// "그릴 수 있다"의 재료 — 맥은 초상 둘 + 마감 둘, 폰은 초상 둘. 한 장이라도 없으면 거짓(낱개로 잰다).
    @Test("GoldAingArt: 요구 파일이 전부 있을 때만 그릴 수 있다 — 맥 4장 · 폰 2장, 한 장씩 빼며 잰다")
    func goldArtPredicateNeedsEveryFile() {
        #expect(GoldAingArt.requiredResourceNames(for: .mac)
                == ["aing_gold-neutral", "aing_gold-negative", "aing_gold-skin", "aing_gold-halo"])
        #expect(GoldAingArt.requiredResourceNames(for: .phone) == ["aing_gold-neutral", "aing_gold-negative"])
        #expect(GoldAingArt.resourceExtension == "png")

        for platform in [GoldAingArt.Platform.mac, .phone] {
            let all = Set(GoldAingArt.requiredResourceNames(for: platform))
            #expect(GoldAingArt.isDrawable(on: platform) { all.contains($0) }, "\(platform): 다 있는데 못 그린다")
            #expect(GoldAingArt.isDrawable(on: platform) { _ in false } == false)
            for missing in all {
                let present = all.subtracting([missing])
                #expect(GoldAingArt.isDrawable(on: platform) { present.contains($0) } == false,
                        "\(platform): \(missing) 가 없는데 그릴 수 있다고 했다")
            }
        }
        // 기준선이 갈린다: 폰이 요구하는 두 장만 있으면 폰은 참 · 맥은 거짓(마감이 없으면 금 착용자 오버레이에 보라 아잉이 선다).
        let portraitsOnly = Set(GoldAingArt.portraitResourceNames)
        #expect(GoldAingArt.isDrawable(on: .phone) { portraitsOnly.contains($0) })
        #expect(GoldAingArt.isDrawable(on: .mac) { portraitsOnly.contains($0) } == false)
    }

    // MARK: - ② 전선 — 맥 스토어의 진짜 경로

    /// 가짜 명단을 꽂아 `loadShopState()`·`buyCharacter(_:)` 를 **2 쪽과 1 쪽 둘 다** 돌리고, 나간 본문을 JSON 으로 연다.
    /// 결과까지 잰다: 2 를 보내면 서버가 aing_gold 행(뽑기 전용)을 내려 주고 스토어 목록에 선다 · 1 이면 안 선다.
    @MainActor
    @Test("목록과 구매가 같은 번호(2/1)를 싣고, 2 일 때만 금 행이 목록에 선다")
    func bothCallSitesCarryProtocolTwo() async throws {
        for (label, drawable, expected) in [
            ("gold", ["aing", "fox", "robot", "aing_gold"], 2),
            ("robot", ["aing", "fox", "robot"], 1),
        ] {
            let host = "v0354-gold-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
            GomokuStubProtocol.register(host: host, handler: V0354CoreStub.shopHandler)
            let store = Self.store(host: host, label: label)
            store.drawableCharacterIDs = drawable
            #expect(store.shopProtocolVersion == expected, "\(label): 명단 \(drawable) → \(store.shopProtocolVersion)")

            store.loadShopState()
            #expect(await V0354CoreStub.waitUntil { store.shopLoaded || store.shopFailed }, "\(label): 상점 조회가 안 끝났다")
            let list = try #require(GomokuStubProtocol.calls(host: host, rpc: "shop_state").last).json
            #expect(Set(list.keys) == ["p_protocol"], Comment(rawValue: "\(label) 목록 본문 \(list)"))
            #expect(list["p_protocol"] as? Int == expected, Comment(rawValue: "\(label) 목록 본문 \(list)"))
            let gold = store.shopCharacters.first { $0.id == "aing_gold" }
            #expect((gold != nil) == (expected == 2), Comment(rawValue: "\(label): 목록 \(store.shopCharacters.map(\.id))"))
            if let gold {
                #expect(gold.gachaOnly == true && gold.isPurchasable == false, "금 행이 팔리는 줄로 읽혔다")
            }
            // 기준선: 다른 줄은 뽑기 전용 표식이 없다(키를 안 실었다 → nil → 살 수 있다).
            #expect(store.shopCharacters.first { $0.id == "fox" }?.isPurchasable == true)

            store.buyCharacter("fox")
            #expect(await V0354CoreStub.waitUntil { store.purchasingID == nil }, "\(label): 구매가 안 끝났다")
            let buy = try #require(GomokuStubProtocol.calls(host: host, rpc: "buy_character").last).json
            #expect(Set(buy.keys) == ["p_id", "p_protocol"], Comment(rawValue: "\(label) 구매 본문 \(buy)"))
            #expect(buy["p_protocol"] as? Int == expected,
                    Comment(rawValue: "\(label) 구매 본문 \(buy) — 목록 2·구매 1 이면 게이트가 장식이다"))
        }
    }

    // MARK: - ③ 번들 그대로의 맥

    /// 기준선은 **소스 트리의 그림 파일**이다(robot 은 `Characters/robot/` 네 장 · 금은 `Resources/aing_gold-*.png` 네 장).
    /// 지금 번들에 금 그림이 없으면 1, 그림이 실리고 맥 조회가 배선되면 2 — 둘이 갈리면 빨강이다.
    @MainActor
    @Test("번들 그대로의 맥이 보내는 번호 — 소스 트리의 그림 파일이 기준선")
    func shippedMacFollowsTheArtInTheTree() async throws {
        let robot = V0343RobotShopProtocolTests.robotArtInSourceTree
        let gold = V0354CoreArtBaseline.macGoldArtInSourceTree
        // v0.3.59: 번호는 누적이라 무지개 그림까지 실리면 3 이다(무지개의 기준선은 V0359RainbowShopProtocolTests). 이 시험은 금의 몫 —
        // "금 그림이 있으면 2 이상, 없으면 robot 까지" — 를 잰다.
        let rainbow = V0359RainbowShopProtocolTests.macRainbowArtInSourceTree
        // v0.3.66: 케이크 아잉이 둘의 초상까지 실리면 4 다(누적 — 케이크의 기준선은 V0366CakeCoreTests.macCakePortraitsInSourceTree).
        let cakes = ShopWire.cakeCharacterIDs.allSatisfy(V0366CakeCoreTests.macCakePortraitsInSourceTree)
        let expected = robot ? (gold ? (rainbow ? (cakes ? ShopWire.cakeProtocol : ShopWire.rainbowProtocol) : ShopWire.goldProtocol)
                                     : ShopWire.robotProtocol)
                             : ShopWire.legacyProtocol

        let host = "v0354-gold-bundle-\(UUID().uuidString.prefix(8))".lowercased()
        GomokuStubProtocol.register(host: host, handler: V0354CoreStub.shopHandler)
        let store = Self.store(host: host, label: "bundle")
        #expect(store.shopProtocolVersion == expected,
                Comment(rawValue: "robot 그림 \(robot) · 금 그림 \(gold) · 명단 \(store.drawableCharacterIDs) → \(store.shopProtocolVersion)"
                        + (gold && store.shopProtocolVersion < ShopWire.goldProtocol
                           ? " — 금 그림이 실렸는데 맥이 2 를 안 말한다: CheckMascotAssets.drawableCharacterIDs 에 GoldAingArt.isDrawable(on: .mac) 를 배선해라"
                           : "")))
        // 금 그림이 없는 빌드는 **절대** aing_gold 를 그릴 수 있다고 말하지 않는다(위험한 방향 — 아잉 그림의 금 카드가 팔린다).
        if !gold {
            #expect(store.drawableCharacterIDs.contains("aing_gold") == false,
                    Comment(rawValue: "금 그림이 없는데 그릴 수 있다고 했다: \(store.drawableCharacterIDs)"))
        }

        store.loadShopState()
        #expect(await V0354CoreStub.waitUntil { store.shopLoaded || store.shopFailed }, "상점 조회가 안 끝났다")
        let body = try #require(GomokuStubProtocol.calls(host: host, rpc: "shop_state").last).json
        #expect((body["p_protocol"] as? Int ?? ShopWire.legacyProtocol) == expected, Comment(rawValue: "본문 \(body)"))
    }

    // MARK: - 헬퍼

    @MainActor
    static func store(host: String, label: String, function: String = #function) -> WorkTimerStore {
        let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!,
                                          anonKey: "anon-test-key",
                                          session: GomokuStubProtocol.session())
        let store = WorkTimerStore(service: service,
                                   environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                                   defaults: CheckTestScratch.defaults("v0354-shop-" + label, function: function))
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        store.currentTeamID = "00000000-0000-0000-0000-0000000000aa"
        store.membershipConfirmed = true
        store.characterDefaults = CheckTestScratch.defaults("v0354-char-" + label, function: function)
        V0354CoreStub.retain(store)
        return store
    }
}

// MARK: - 이 묶음(v0.3.54 코어) 공용

/// 소스 트리의 그림 파일 — 번들·카탈로그를 거치지 않는 기준선. 파생의 재료와 같은 식으로 기대값을 만들면 영원히 초록이다.
enum V0354CoreArtBaseline {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func macResourceExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: repoRoot
            .appendingPathComponent("Sources/check/Resources/\(name).\(GoldAingArt.resourceExtension)").path)
    }

    /// 맥 금 초상 두 장(메뉴바·카드·아바타가 쓰는 것)이 소스 트리에 있는가.
    static var macGoldPortraitsInSourceTree: Bool {
        GoldAingArt.portraitResourceNames.allSatisfy(macResourceExists)
    }

    /// 맥이 금 아잉을 그리는 데 필요한 네 장(초상 둘 + 마감 둘)이 전부 있는가.
    static var macGoldArtInSourceTree: Bool {
        GoldAingArt.isDrawable(on: .mac, resourceExists: macResourceExists)
    }
}

/// 상점·뽑기 스텁 응답(설계서 Wire contract 모양 그대로). `GomokuStubProtocol` 에 호스트별로 건다 —
/// 그 URLProtocol 은 rpc 이름을 가리지 않고 호스트로만 가른다(체스·오목 스위트도 같은 하네스를 쓴다).
enum V0354CoreStub {
    /// 설계서 표 그대로의 `gacha` 객체(서버 순서 · 합 100). 교환값은 AMENDMENT 1(2026-10-15) — 일곱(황금 20 포함).
    /// 키 순서는 서버 jsonb 가 내는 순서(길이 → 바이트)를 흉내 냈다 — 클라는 순서에 기대지 않는다.
    static let gachaJSON = #"""
    {"price":50,"shards":3,
     "odds":[{"character_id":"aing_gold","percent":5},{"character_id":"fox","percent":24},
             {"character_id":"squirrel","percent":24},{"character_id":"shiba","percent":14},
             {"character_id":"ghost","percent":14},{"character_id":"jellyfish","percent":11},
             {"character_id":"robot","percent":8}],
     "shard_costs":{"fox":2,"ghost":4,"robot":8,"shiba":4,"squirrel":2,"aing_gold":20,"jellyfish":5}}
    """#

    /// 상점 행(설계서 상점가). 2 이상이면 aing_gold(뽑기 전용 · 명목가 1000)가 붙는다.
    static func shopRows(protocolVersion: Int) -> String {
        var rows = [
            #"{"id":"shiba","price":100,"owned":false,"gacha_only":false}"#,
            #"{"id":"squirrel","price":60,"owned":true,"gacha_only":false}"#,
            #"{"id":"ghost","price":100,"owned":false,"gacha_only":false}"#,
            #"{"id":"jellyfish","price":140,"owned":false,"gacha_only":false}"#,
            #"{"id":"fox","price":60,"owned":false}"#,
        ]
        if protocolVersion >= 1 { rows.append(#"{"id":"robot","price":200,"owned":false,"gacha_only":false}"#) }
        if protocolVersion >= 2 { rows.append(#"{"id":"aing_gold","price":1000,"owned":false,"gacha_only":true}"#) }
        return "[" + rows.joined(separator: ",") + "]"
    }

    /// shop_state · buy_character 를 서버처럼 답한다(본문의 p_protocol 이 응답을 고른다 — 순번 상태가 없다).
    static let shopHandler: GomokuStubProtocol.Handler = { rpc, body, _ in
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        let version = json["p_protocol"] as? Int ?? 0
        switch rpc {
        case "shop_state":
            let gacha = version >= 2 ? #","gacha":"# + V0354CoreStub.gachaJSON : ""
            return GomokuStubProtocol.Reply(body: #"{"ruby_balance":120,"ultra_balance":0,"ultra_price":3,"ultra_buy_max":20,"characters":"#
                                            + V0354CoreStub.shopRows(protocolVersion: version) + gacha + "}")
        case "buy_character":
            return GomokuStubProtocol.Reply(body: #"{"status":"ok","character":"fox","price":60,"ruby_balance":60}"#)
        default:
            return nil
        }
    }

    /// `WorkTimerStore` 는 자식 스토어를 약참조로 들린다 — 테스트가 버리면 요청이 안 나간다(오목 스위트의 교훈).
    @MainActor private static var retained: [WorkTimerStore] = []
    @MainActor static func retain(_ store: WorkTimerStore) { retained.append(store) }

    /// 재개 횟수 상한(벽시계가 아니다 — 전체 스위트에서 렌더 테스트가 메인 액터를 오래 쥔다).
    @MainActor
    @discardableResult
    static func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<4_000 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}
