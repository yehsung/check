import AppKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.54 — 맥 상점의 캐릭터 뽑기 · 황금 아잉이 카드 · 판돈 수수료 문구.
//
// 스토어 테스트는 스텁 서버(`GomokuStubProtocol` — 호스트별 응답)로 **서버 응답 → 스토어 상태**를 잰다: 잔량·조각·보유는
// 서버가 말한 값이어야 하고(클라 계산값과 다르게 스텁을 짜서 갈라 본다), 연타·결과 모름 실패에서 요청 id 가 하나로 남는다.
// 렌더 테스트는 실제 패널을 그려(ImageRenderer) 높이 예산과 상태별 그림을 잰다. 미리보기 PNG 는 `CHECK_V0354_MAC_PREVIEW_DIR`.

// MARK: - 스텁

enum V0354GachaStub {
    /// 설계서 표 + AMENDMENT 1 교환값(여우 2 · 다람쥐 2 · 강아지 4 · 유령 4 · 해파리 5 · 로봇 8 · 황금 20). 서버 순서 그대로.
    static func gachaJSON(shards: Int = 3, goldCost: Int = 20) -> String {
        #"{"price":50,"shards":"# + "\(shards)" + #","odds":[{"character_id":"aing_gold","percent":5},{"character_id":"fox","percent":24},"#
            + #"{"character_id":"squirrel","percent":24},{"character_id":"shiba","percent":14},{"character_id":"ghost","percent":14},"#
            + #"{"character_id":"jellyfish","percent":11},{"character_id":"robot","percent":8}],"#
            + #""shard_costs":{"aing_gold":"# + "\(goldCost)" + #","fox":2,"squirrel":2,"shiba":4,"ghost":4,"jellyfish":5,"robot":8}}"#
    }

    static func shopStateJSON(ruby: Int = 120, shards: Int = 3, goldCost: Int = 20, owned: Set<String> = ["squirrel"]) -> String {
        let prices: [(String, Int)] = [("fox", 60), ("squirrel", 60), ("shiba", 100), ("ghost", 100), ("jellyfish", 140), ("robot", 200)]
        let rows = prices.map { id, price in
            #"{"id":""# + id + #"","price":"# + "\(price)" + #","owned":"# + (owned.contains(id) ? "true" : "false") + #","gacha_only":false}"#
        } + [#"{"id":"aing_gold","price":1000,"owned":"# + (owned.contains("aing_gold") ? "true" : "false") + #","gacha_only":true}"#]
        return #"{"ruby_balance":"# + "\(ruby)" + #","ultra_balance":0,"ultra_price":3,"ultra_buy_max":20,"characters":["#
            + rows.joined(separator: ",") + #"],"gacha":"# + gachaJSON(shards: shards, goldCost: goldCost) + "}"
    }

    /// shop_state 는 n 번째 호출에 `shopStates[min(n, 끝)]` 를 답한다 — 첫 조회 뒤의 다시 읽기(뽑기·교환 직후)는 **서버의 새 상태**를
    /// 0.4초 늦게 준다(그 사이 스토어가 RPC 응답만으로 고친 값을 잴 수 있게 — 다시 읽기가 먼저 덮으면 무엇을 쟀는지 모른다).
    /// gacha_pull · gacha_exchange 는 n 번째 호출마다 `pull`/`exchange` 가 답한다.
    static func register(host: String,
                         shopStates: [String] = [shopStateJSON()],
                         pull: @escaping @Sendable (Int) -> GomokuStubProtocol.Reply = { _ in .init(body: #"{"status":"invalid"}"#) },
                         exchange: @escaping @Sendable (Int) -> GomokuStubProtocol.Reply = { _ in .init(body: #"{"status":"invalid"}"#) }) {
        GomokuStubProtocol.register(host: host) { rpc, _, index in
            switch rpc {
            case "shop_state":
                return .init(body: shopStates[min(index, shopStates.count - 1)], delay: index == 0 ? 0 : 0.4)
            case "gacha_pull": return pull(index)
            case "gacha_exchange": return exchange(index)
            case "megaphone_info": return .init(body: #"{"price":50,"cooldown_seconds":600,"cooldown_remaining_seconds":0,"recipients":10,"max_length":198}"#)
            default: return nil
            }
        }
    }

    @MainActor
    static func loadedStore(host: String, label: String, function: String = #function) async -> WorkTimerStore {
        let store = V0354GoldShopProtocolTests.store(host: host, label: label, function: function)
        store.loadShopState()
        _ = await V0354CoreStub.waitUntil { store.shopLoaded || store.shopFailed }
        return store
    }

    static func requestID(_ call: GomokuStubProtocol.Call) -> String? { call.json["p_request_id"] as? String }
}

// MARK: - 스토어

@MainActor
@Suite struct V0354GachaMacStoreTests {
    static func host(_ label: String) -> String { "v0354-gacha-\(label)-\(UUID().uuidString.prefix(8))".lowercased() }

    @Test("shop_state 의 gacha 가 오면 뽑기가 서고(조각 3), 안 오면(옛 서버) 숨고 열린 패널도 접힌다")
    func gachaShowsAndHides() async throws {
        let host = Self.host("show")
        V0354GachaStub.register(host: host)
        let store = await V0354GachaStub.loadedStore(host: host, label: "show")
        #expect(store.shopLoaded)
        #expect(store.isGachaAvailable && store.gachaShards == 3)
        // v0.3.59: 번들이 무지개까지 그리면 3 이다(누적) — 뽑기 문턱(2) 이상이면 서버가 뽑기를 준다. 값은 번들에서 파생한 그 번호.
        let sent = GomokuStubProtocol.calls(host: host, rpc: "shop_state").last?.json["p_protocol"] as? Int
        #expect(sent == store.shopProtocolVersion && ShopWire.supportsGacha(protocolVersion: sent ?? 0),
                "맥이 능력 번호 \(sent.map(String.init) ?? "없음") 를 보낸다 — 2 이상이 아니면 서버가 뽑기를 안 준다")
        store.openGachaPanel()
        #expect(store.isGachaPanelOpen)
        // 기준선: gacha 없는 응답(옛 서버) — 뽑기가 숨고 패널이 접힌다.
        store.applyShopState(ShopStateResponse(rubyBalance: 120, characters: []))
        #expect(!store.isGachaAvailable && store.gachaInfo == nil && !store.isGachaPanelOpen)
    }

    @Test("뽑기 성공: 잔량·조각·보유는 서버 값 그대로(클라가 50 을 빼지 않는다) · 본문은 능력 번호 2 + 소문자 uuid · 호출 한 번")
    func pullAppliesTheServerValues() async throws {
        let host = Self.host("pull")
        // 서버 잔량 71 — 클라가 120 − 50 = 70 을 계산하면 갈린다(기준선이 다르다).
        V0354GachaStub.register(host: host,
                                shopStates: [V0354GachaStub.shopStateJSON(),
                                             V0354GachaStub.shopStateJSON(ruby: 71, owned: ["squirrel", "fox"])],
                                pull: { _ in
            .init(body: #"{"status":"ok","character_id":"fox","duplicate":false,"shards_gained":0,"shards":3,"ruby_balance":71,"price":50,"replayed":false}"#)
        })
        let store = await V0354GachaStub.loadedStore(host: host, label: "pull")
        #expect(store.rubyBalance == 120 && !store.ownedCharacterIDs.contains("fox"))
        store.openGachaPanel()
        store.pullGacha()
        #expect(store.gachaPulling, "왕복 중 표시가 안 섰다")
        #expect(await V0354CoreStub.waitUntil { !store.gachaPulling })
        #expect(store.rubyBalance == 71, "잔량 \(String(describing: store.rubyBalance)) — 서버 값(71)이 아니다")
        #expect(store.ownedCharacterIDs.contains("fox"))
        #expect(store.gachaLastResult?.kind == .newCharacter && store.gachaLastResult?.characterID == "fox")
        #expect(store.gachaNotice == nil)
        let calls = GomokuStubProtocol.calls(host: host, rpc: "gacha_pull")
        #expect(calls.count == 1)
        let body = try #require(calls.first).json
        #expect(body["p_protocol"] as? Int == store.shopProtocolVersion && store.shopProtocolVersion >= ShopWire.goldProtocol)
        let id = try #require(body["p_request_id"] as? String)
        #expect(UUID(uuidString: id) != nil && id == id.lowercased())
        // 보유·조각을 사실과 맞추려 상점을 다시 읽는다(서버의 새 상태가 같은 값을 말한다).
        #expect(await V0354CoreStub.waitUntil { GomokuStubProtocol.count(host: host, rpc: "shop_state") >= 2 && !store.shopLoading })
        #expect(store.rubyBalance == 71 && store.ownedCharacterIDs.contains("fox"))
    }

    @Test("황금 아잉이가 나오면 결과가 '황금' 갈래 · 이미 있는 캐릭터면 조각 +1(서버 조각 수)")
    func goldAndDuplicateResults() async throws {
        let host = Self.host("kinds")
        V0354GachaStub.register(host: host,
                                shopStates: [V0354GachaStub.shopStateJSON(),
                                             V0354GachaStub.shopStateJSON(ruby: 70, owned: ["squirrel", "aing_gold"]),
                                             V0354GachaStub.shopStateJSON(ruby: 20, shards: 4, owned: ["squirrel", "aing_gold"])],
                                pull: { index in
            index == 0
                ? .init(body: #"{"status":"ok","character_id":"aing_gold","duplicate":false,"shards_gained":0,"shards":3,"ruby_balance":70}"#)
                : .init(body: #"{"status":"ok","character_id":"squirrel","duplicate":true,"shards_gained":1,"shards":4,"ruby_balance":20}"#)
        })
        let store = await V0354GachaStub.loadedStore(host: host, label: "kinds")
        store.pullGacha()
        #expect(await V0354CoreStub.waitUntil { !store.gachaPulling && store.gachaLastResult != nil })
        #expect(store.gachaLastResult?.kind == .gold && store.ownedCharacterIDs.contains(CharacterCatalog.goldAingID))
        // 첫 뽑기 뒤의 상점 다시 읽기(0.4초 늦다)를 **기다리지 않고** 곧바로 다시 누른다 — [한 번 더] 연타 그대로다
        // (늦게 오는 그 조회가 둘째 뽑기 값을 덮지 않는 것은 `V0354GachaRaceTests` 가 잰다).
        store.pullGacha()
        #expect(await V0354CoreStub.waitUntil { !store.gachaPulling && store.gachaLastResult?.characterID == "squirrel" })
        #expect(store.gachaLastResult?.kind == .duplicate && store.gachaShards == 4 && store.rubyBalance == 20)
        let name = store.gachaDisplayName("squirrel")
        #expect(GachaText.headline(for: try #require(store.gachaLastResult), name: name) == "이미 있는 다람쥐 → 조각 +1")
    }

    @Test("연타: 왕복 중에 다시 눌러도 요청은 하나다")
    func doubleClickSendsOneRequest() async throws {
        let host = Self.host("double")
        V0354GachaStub.register(host: host, pull: { _ in
            .init(body: #"{"status":"ok","character_id":"ghost","duplicate":false,"shards":3,"ruby_balance":70}"#, delay: 0.3)
        })
        let store = await V0354GachaStub.loadedStore(host: host, label: "double")
        store.pullGacha()
        store.pullGacha()
        store.pullGacha()
        #expect(await V0354CoreStub.waitUntil { !store.gachaPulling })
        #expect(GomokuStubProtocol.count(host: host, rpc: "gacha_pull") == 1, "연타가 요청 \(GomokuStubProtocol.count(host: host, rpc: "gacha_pull")) 개를 보냈다")
    }

    @Test("결과를 모르는 실패(503) 뒤 다시 누르면 같은 요청 id 로 묻는다(두 번 깎이지 않는다) · 답을 받은 뒤엔 새 id")
    func unknownFailureKeepsTheRequestID() async throws {
        let host = Self.host("retry")
        V0354GachaStub.register(host: host, pull: { index in
            switch index {
            case 0: return .init(status: 503, body: #"{"message":"upstream"}"#)
            case 1: return .init(body: #"{"status":"ok","character_id":"fox","duplicate":false,"shards":3,"ruby_balance":70,"replayed":true}"#)
            default: return .init(body: #"{"status":"ok","character_id":"shiba","duplicate":false,"shards":3,"ruby_balance":20}"#)
            }
        })
        let store = await V0354GachaStub.loadedStore(host: host, label: "retry")
        store.pullGacha()
        #expect(await V0354CoreStub.waitUntil { !store.gachaPulling })
        #expect(store.gachaNotice == GachaText.connection && store.gachaNoticeIsError)
        #expect(store.rubyBalance == 120, "실패했는데 잔량이 움직였다")
        store.pullGacha()
        #expect(await V0354CoreStub.waitUntil { !store.gachaPulling && store.gachaLastResult != nil })
        store.pullGacha()
        #expect(await V0354CoreStub.waitUntil { !store.gachaPulling && store.gachaLastResult?.characterID == "shiba" })
        let ids = GomokuStubProtocol.calls(host: host, rpc: "gacha_pull").compactMap(V0354GachaStub.requestID)
        #expect(ids.count == 3)
        #expect(ids[0] == ids[1], "결과를 모르는 실패 뒤 다시 누른 요청이 새 id 다 — 서버가 두 번 깎을 수 있다")
        #expect(ids[2] != ids[1], "답을 받은 뒤에도 같은 id 를 쓴다 — 다음 뽑기가 재응답(replayed)이 된다")
    }

    @Test("모자람: 서버가 말한 잔량으로 고치고 이유를 말한다 · 화면이 이미 모자라면 서버에 안 묻는다")
    func insufficientAndShortBalance() async throws {
        let host = Self.host("short")
        V0354GachaStub.register(host: host, pull: { _ in .init(body: #"{"status":"insufficient","need":50,"have":30}"#) })
        let store = await V0354GachaStub.loadedStore(host: host, label: "short")
        store.pullGacha()
        #expect(await V0354CoreStub.waitUntil { !store.gachaPulling })
        #expect(store.rubyBalance == 30, "서버가 말한 잔량(30)으로 안 고쳤다")
        #expect(store.gachaNotice == GachaText.shortfall(need: 50, have: 30) && store.gachaNoticeIsError)
        // 이제 화면이 아는 잔량 30 < 50 — 버튼이 잠기고, 스토어도 서버에 안 묻는다.
        #expect(!store.gachaPullAvailability.canPull)
        let before = GomokuStubProtocol.count(host: host, rpc: "gacha_pull")
        store.pullGacha()
        #expect(GomokuStubProtocol.count(host: host, rpc: "gacha_pull") == before, "모자란데 서버에 물었다")
        #expect(CheckGachaPanel.reason(for: store.gachaPullAvailability, balance: store.rubyBalance) == "루비 20개 더 필요해요")
    }

    @Test("교환: 보유·조각을 서버 값으로 고친다 · 모자라면 서버에 안 묻고 몇 개 더 필요한지 말한다")
    func exchangeAppliesServerValues() async throws {
        let host = Self.host("exchange")
        V0354GachaStub.register(host: host,
                                shopStates: [V0354GachaStub.shopStateJSON(),
                                             V0354GachaStub.shopStateJSON(shards: 1, owned: ["squirrel", "fox"])],
                                exchange: { _ in
            .init(body: #"{"status":"ok","character_id":"fox","shards":1,"cost":2,"replayed":false}"#)
        })
        let store = await V0354GachaStub.loadedStore(host: host, label: "exchange")
        #expect(!store.ownedCharacterIDs.contains("fox") && store.gachaShards == 3)
        store.exchangeGacha("fox")
        #expect(store.gachaExchangingID == "fox")
        #expect(await V0354CoreStub.waitUntil { store.gachaExchangingID == nil })
        #expect(store.ownedCharacterIDs.contains("fox") && store.gachaShards == 1)
        #expect(store.gachaNotice == GachaText.exchanged(name: "여우") && !store.gachaNoticeIsError)
        let body = try #require(GomokuStubProtocol.calls(host: host, rpc: "gacha_exchange").first).json
        #expect(body["p_character_id"] as? String == "fox" && body["p_protocol"] as? Int == store.shopProtocolVersion
                && store.shopProtocolVersion >= ShopWire.goldProtocol)
        // 해파리(5) > 조각 1 — 서버에 안 묻는다.
        store.exchangeGacha("jellyfish")
        #expect(GomokuStubProtocol.count(host: host, rpc: "gacha_exchange") == 1)
        #expect(store.gachaNotice == GachaText.shardShortfall(missing: 4))
    }

    @Test("황금 아잉이 카드: 고르면 [구매하기] 대신 뽑기 패널 · 루비 값(명목 1000)은 어디에도 안 나온다 · 억지로 골라도 안 산다")
    func goldCardOpensTheGacha() async throws {
        let host = Self.host("goldcard")
        V0354GachaStub.register(host: host)
        let store = await V0354GachaStub.loadedStore(host: host, label: "goldcard")
        let gold = CharacterCatalog.goldAingID
        #expect(store.shopCharacters.first { $0.id == gold }?.price == 1000, "기준선: 서버는 명목가 1000 을 싣는다")
        #expect(store.shopPrice(of: gold) == nil, "캐릭터 고르기 자물쇠·하단 바가 1000 을 말한다")
        #expect(store.shopPrice(of: "fox") == 60)
        store.selectShopItem(.character(gold))
        #expect(store.shopSelection == nil && store.isGachaPanelOpen, "금 카드를 눌렀는데 뽑기 패널이 안 열렸다")
        // 두 번째 문: 선택을 억지로 세워도 구매 RPC 가 안 나간다.
        store.shopSelection = .character(gold)
        store.confirmShopPurchase()
        #expect(GomokuStubProtocol.count(host: host, rpc: "buy_character") == 0)
        #expect(store.shopNotice == GachaText.gachaOnlyHint)
        // 다른 상품을 고르면 패널이 자리를 돌려준다.
        store.openGachaPanel()
        store.selectShopItem(.character("fox"))
        #expect(!store.isGachaPanelOpen && store.shopSelection == .character("fox"))
    }

    @Test("금 카드 문구는 서버 교환값을 따른다: '뽑기 또는 조각 20개' · 값이 바뀌면 숫자도 · 모르면 '뽑기 전용' · 가지면 '보유'")
    func goldCardCopyIsDataDriven() async throws {
        let gold = CharacterCatalog.goldAingID
        let host = Self.host("goldcopy")
        V0354GachaStub.register(host: host)
        let store = await V0354GachaStub.loadedStore(host: host, label: "goldcopy")
        #expect(GachaText.gachaOnlyPrice(shardCost: store.gachaShardCost(of: gold)) == "뽑기 또는 조각 20개")
        let host25 = Self.host("goldcopy25")
        V0354GachaStub.register(host: host25, shopStates: [V0354GachaStub.shopStateJSON(goldCost: 25)])
        let store25 = await V0354GachaStub.loadedStore(host: host25, label: "goldcopy25")
        #expect(GachaText.gachaOnlyPrice(shardCost: store25.gachaShardCost(of: gold)) == "뽑기 또는 조각 25개")
        #expect(GachaText.gachaOnlyPrice(shardCost: nil) == GachaText.gachaOnly)
        #expect(GachaText.owned == "보유")
    }

    /// 0.3.54 캡슐 기계: 잠긴 금 카드는 상점 안 뽑기 패널이 아니라 **뽑기 창**을 연다(`V0354GachaWindowDoorTests.lockedGoldOpensTheWindow`
    /// 가 자세히 잰다). 여기선 창 문이 열리고 상점 패널은 안 열리는 것만 — 다른 잠긴 카드(기준선)는 그대로 상점이다.
    @Test("캐릭터 고르기의 잠긴 금 카드 → 뽑기 창(상점 패널 아님) · 다른 잠긴 카드 → 상점만")
    func lockedGoldInThePickerOpensTheGacha() async throws {
        let host = Self.host("locked")
        V0354GachaStub.register(host: host)
        let store = await V0354GachaStub.loadedStore(host: host, label: "locked")
        var shows = 0
        store.gachaWindowHooks = GachaWindowHooks(show: { shows += 1 }, close: {})
        store.openShopForLockedCharacter("fox")
        #expect(store.isShopPanelVisible && !store.isGachaPanelOpen && shows == 0)
        store.closeShopPanel()
        store.openShopForLockedCharacter(CharacterCatalog.goldAingID)
        #expect(shows == 1 && !store.isShopPanelVisible && !store.isGachaPanelOpen)
    }

    @Test("확성기 작성기와 뽑기 패널은 같은 자리 — 하나를 열면 다른 하나가 접힌다 · 상점을 닫으면 둘 다 접힌다")
    func megaphoneAndGachaShareTheSlot() async throws {
        let host = Self.host("slot")
        V0354GachaStub.register(host: host)
        let store = await V0354GachaStub.loadedStore(host: host, label: "slot")
        store.isShopPanelVisible = true
        store.toggleGachaPanel()
        #expect(store.isGachaPanelOpen)
        store.toggleMegaphoneComposer()
        #expect(store.megaphone.isComposerOpen && !store.isGachaPanelOpen)
        store.toggleGachaPanel()
        #expect(store.isGachaPanelOpen && !store.megaphone.isComposerOpen)
        store.closeShopPanel()
        #expect(!store.isGachaPanelOpen)
    }

    @Test("로그아웃은 뽑기 정보·결과·요청 id 를 지운다(다음 사람이 앞 사람의 조각·결과를 안 본다)")
    func signOutClearsGacha() async throws {
        let host = Self.host("signout")
        V0354GachaStub.register(host: host, pull: { _ in .init(status: 503, body: "{}") })
        let store = await V0354GachaStub.loadedStore(host: host, label: "signout")
        store.pullGacha()
        #expect(await V0354CoreStub.waitUntil { !store.gachaPulling })
        #expect(store.gachaRequestIDs.pull != nil && store.gachaInfo != nil, "기준선: 결과 모름 id 와 정보가 안 섰다")
        store.signOut(notifyServer: false)
        #expect(store.gachaInfo == nil && store.gachaRequestIDs.pull == nil && store.gachaLastResult == nil)
    }
}

// MARK: - 렌더

@MainActor
@Suite struct V0354GachaMacRenderTests {
    static let width = CheckMenuView.contentColumnWidth
    static let previewDir = ProcessInfo.processInfo.environment["CHECK_V0354_MAC_PREVIEW_DIR"]

    static func info(shards: Int = 3) -> GachaInfo? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase   // 서비스 디코더와 같은 전략
        return try? decoder.decode(GachaInfo.self, from: Data(V0354GachaStub.gachaJSON(shards: shards).utf8))
    }

    /// 서버처럼 여섯 장 + 황금 아잉이(뽑기 전용 · 명목가 1000). `V0317ShopTests.rows` 는 카탈로그를 따라 금을 가격 30 으로 끼워
    /// 넣으므로(그 스위트의 픽스처) 여기서는 금을 빼고 서버 모양으로 다시 붙인다.
    static func shopRows(goldOwned: Bool = false) -> [ShopCharacterRow] {
        // v0.3.59: 무지개 아잉이(내장 · 뽑기 전용)는 이 '금 포함 일곱 장' 픽스처에 없다 — 루비 값 30 의 파는 줄로 섞이지 않게 뺀다.
        V0317ShopTests.rows(ownedIDs: ["squirrel"]).filter { !CharacterCatalog.isGoldAing($0.id) && !CharacterCatalog.isRainbowAing($0.id) }
            + [ShopCharacterRow(id: CharacterCatalog.goldAingID, price: 1000, owned: goldOwned, gachaOnly: true)]
    }

    /// 뽑기가 선 상점 스토어(세션 없음 — 네트워크 안 나감).
    static func store(ruby: Int? = 120, shards: Int = 3, goldOwned: Bool = false,
                      function: String = #function, line: Int = #line) -> WorkTimerStore {
        let store = V0317ShopTests.plainStore(function: function, line: line)
        store.applyShopState(ShopStateResponse(rubyBalance: ruby, ultraBalance: 7, ultraPrice: 3, ultraBuyMax: 20,
                                               characters: shopRows(goldOwned: goldOwned)))
        store.rubyBalance = ruby
        store.gachaInfo = info(shards: shards)
        store.shopLoaded = true
        store.megaphone.applyInfo(MegaphoneInfoResponse(price: 50, cooldownSeconds: 600, cooldownRemainingSeconds: 0,
                                                       recipients: 46, maxLength: 198))
        return store
    }

    static func result(_ id: String, duplicate: Bool) -> GachaPullResult {
        GachaPullResult(characterID: id, isDuplicate: duplicate, shardsGained: duplicate ? 1 : 0, shards: duplicate ? 4 : 3,
                        rubyBalance: 70, replayed: false)
    }

    /// ImageRenderer 는 첫 두 장을 다르게 굽는다 — 두 장 버리고 세 번째를 쓴다.
    static func settledBitmap(_ view: some View, width: CGFloat) -> NSBitmapImageRep? {
        _ = V0317ShopTests.bitmap(view, width: width)
        _ = V0317ShopTests.bitmap(view, width: width)
        return V0317ShopTests.bitmap(view, width: width)
    }

    static func save(_ bitmap: NSBitmapImageRep, _ name: String) {
        guard let previewDir, let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(atPath: previewDir, withIntermediateDirectories: true)
        try? png.write(to: URL(fileURLWithPath: previewDir).appendingPathComponent(name))
    }

    /// 금빛 글자·그림 픽셀(진한 금 — r 높고 b 낮음, 채도 높음) 수.
    static func goldInk(_ rep: NSBitmapImageRep) -> Int {
        V0317ShopTests.count(rep) { r, g, b in r > 200 && g > 140 && g < 215 && b < 110 && r - b > 120 }
    }

    /// 경고색(CheckTheme.danger ≈ 255,115,117) 픽셀 수.
    static func dangerInk(_ rep: NSBitmapImageRep) -> Int {
        V0317ShopTests.count(rep) { r, g, b in r > 220 && g > 80 && g < 150 && b > 80 && b < 150 }
    }

    enum State: String, CaseIterable {
        case idle, insufficient, pulling, resultNew, resultDuplicate, resultGold, odds, exchange, exchangeShort
    }

    static func configure(_ state: State, function: String = #function) -> WorkTimerStore {
        let store = Self.store(ruby: state == .insufficient ? 30 : 120, shards: state == .exchangeShort ? 1 : 3,
                               function: function + state.rawValue)
        store.isShopPanelVisible = true
        store.openGachaPanel()
        switch state {
        case .idle, .insufficient: break
        case .pulling: store.gachaPulling = true
        case .resultNew: store.gachaLastResult = result("fox", duplicate: false); store.ownedCharacterIDs.insert("fox")
        case .resultDuplicate: store.gachaLastResult = result("squirrel", duplicate: true); store.gachaInfo?.shards = 4
        case .resultGold:
            store.gachaLastResult = result(CharacterCatalog.goldAingID, duplicate: false)
            store.ownedCharacterIDs.insert(CharacterCatalog.goldAingID)
        case .odds: store.setGachaPanelMode(.odds)
        case .exchange: store.setGachaPanelMode(.exchange)
        case .exchangeShort: store.setGachaPanelMode(.exchange)
        }
        return store
    }

    @Test("뽑기 패널 상태별 렌더: 높이는 늘 고정 · 금 결과는 금빛 글자 · 모자람은 경고색 이유 · 상점 전체 미리보기")
    func panelStatesRender() throws {
        var gold: [State: Int] = [:], danger: [State: Int] = [:]
        for state in State.allCases {
            let store = Self.configure(state)
            // 패널 바탕색 위에 그린다(앱에선 상점 패널 바탕 위다 — 투명이면 흰 글자가 미리보기에서 안 보인다).
            let panel = CheckGachaPanel(store: store).padding(.horizontal, 0).background(CheckTheme.panel)
            let rep = try #require(Self.settledBitmap(panel.frame(width: Self.width - 24), width: Self.width - 24))
            #expect(abs(CGFloat(rep.pixelsHigh) / 2 - CheckGachaPanel.height) < 1, "\(state): 패널 높이 \(rep.pixelsHigh / 2)")
            // 내용이 고정 높이를 넘지 않는다(넘으면 아래 줄이 잘린 채 초록이다 — 자연 높이로 따로 잰다).
            let natural = try #require(V0317ShopTests.height(CheckGachaPanel(store: store, measuresNaturalHeight: true),
                                                             width: Self.width - 24))
            #expect(natural <= CheckGachaPanel.height + 0.5, "\(state): 내용 \(natural)pt 가 패널 \(CheckGachaPanel.height)pt 를 넘는다")
            gold[state] = Self.goldInk(rep)
            danger[state] = Self.dangerInk(rep)
            Self.save(rep, "gacha-panel-\(state.rawValue).png")
            let shop = try #require(Self.settledBitmap(CheckShopPanel(store: store, onBack: {}), width: Self.width))
            Self.save(shop, "gacha-shop-\(state.rawValue).png")
        }
        print("[v0354-gacha] 금빛 픽셀 \(gold.sorted { $0.key.rawValue < $1.key.rawValue }) · 경고색 \(danger.sorted { $0.key.rawValue < $1.key.rawValue })")
        // 결과(0.3.54 캡슐 기계 뒤): 패널은 연출하지 않고 마지막 결과를 **한 줄**로만 말한다 — 황금이면 그 줄이 금빛이다.
        // 확률 띠의 금 초상은 모든 보기에 있으므로 기준선(새 캐릭터 한 줄 = 흰 글자)과의 차가 곧 금빛 한 줄이다(실측 +184).
        #expect((gold[.resultGold] ?? 0) > (gold[.resultNew] ?? 0) + 100, "금 결과 한 줄이 금빛이 아니다")
        #expect(gold[.resultNew] == gold[.idle], "새 캐릭터 한 줄이 금빛으로 칠해졌다(기준선이 갈리지 않는다)")
        // 결과: 잔량이 모자라면 이유가 경고색으로 선다 — 뽑을 수 있을 때(기준선)는 없다.
        #expect((danger[.insufficient] ?? 0) > (danger[.idle] ?? 0) + 30, "모자람 이유가 안 보인다")
    }

    /// AMENDMENT 1(황금 아잉이도 조각 20개로 교환)은 코어 담당이 `GachaRules` 에 넣는다 — 이 브랜치의 코어는 아직 금을 교환 목록에서
    /// 뺀다. 그 뒤의 모습(교환 일곱 줄 · 금 맨 위 · 확률표 금 상점가 "뽑기 또는 조각 20개")이 **이 패널 높이 안에 드는지**를 줄을 직접 넣어
    /// 잰다(코어 판정을 흉내 내는 것이 아니라 배치만 본다). 미리보기 `gacha-panel-*-amended.png`.
    @Test("AMENDMENT 1 모습(교환 일곱 줄 · 금 맨 위 · 금 상점가 긴 문구)도 고정 높이 안에 든다")
    func amendedListsFitThePanel() throws {
        let store = Self.store(shards: 3)
        store.isShopPanelVisible = true
        let rules = CheckGachaPanel(store: store).exchangeLines.filter { !CharacterCatalog.isGoldAing($0.id) }
        let seven = [GachaExchangeLine(id: CharacterCatalog.goldAingID, name: "황금 아잉이",
                                       availability: .short(cost: 20, missing: 17))] + rules
        #expect(seven.count == 7)
        let odds = CheckGachaPanel(store: store).oddsLines.map { line in
            line.isGold ? GachaOddsLine(id: line.id, name: line.name, priceText: "뽑기 또는 조각 20개",
                                        percentText: line.percentText, isGold: true) : line
        }
        for (mode, name) in [(GachaPanelMode.exchange, "exchange"), (.odds, "odds")] {
            store.openGachaPanel(mode: mode)
            let panel = CheckGachaPanel(store: store, previewOddsLines: odds, previewExchangeLines: seven)
                .background(CheckTheme.panel)
            let rep = try #require(Self.settledBitmap(panel.frame(width: Self.width - 24), width: Self.width - 24))
            Self.save(rep, "gacha-panel-\(name)-amended.png")
            let natural = try #require(V0317ShopTests.height(
                CheckGachaPanel(store: store, previewOddsLines: odds, previewExchangeLines: seven, measuresNaturalHeight: true),
                width: Self.width - 24))
            #expect(natural <= CheckGachaPanel.height + 0.5, "\(name): 일곱 줄 내용 \(natural)pt 가 패널 \(CheckGachaPanel.height)pt 를 넘는다")
        }
    }

    @Test("확률표: 서버 순서 그대로 일곱 줄 · 이름은 맥 카탈로그(강아지) · 상점가는 서버 값 · 금은 루비 값 대신 뽑기 문구")
    func oddsLinesFollowTheServer() throws {
        let store = Self.store()
        let lines = CheckGachaPanel(store: store).oddsLines
        #expect(lines.map(\.name) == ["황금 아잉이", "여우", "다람쥐", "강아지", "유령", "해파리", "로봇"])
        #expect(lines.map(\.percentText) == ["5%", "24%", "24%", "14%", "14%", "11%", "8%"])
        #expect(Array(lines.map(\.priceText).dropFirst()) == ["60", "60", "100", "100", "140", "200"])
        let goldPrice = try #require(lines.first?.priceText)
        #expect(goldPrice.contains("뽑기") && Int(goldPrice) == nil, "금 줄 상점가가 '\(goldPrice)' — 루비 값을 말한다")
        #expect(lines.first?.isGold == true)
    }

    @Test("교환 목록은 코어(GachaRules)가 준 줄 그대로 · 보유는 '보유' · 모자라면 가진/필요 · 금이 교환표에 있으면 맨 위")
    func exchangeLinesFollowTheRules() throws {
        let store = Self.store(shards: 3)
        store.ownedCharacterIDs.insert("fox")
        let info = try #require(store.gachaInfo)
        let expected = GachaRules.exchangeRows(info: info, ownedIDs: store.ownedCharacterIDs) {
            CheckCharacter3DScene.catalog.manifest(id: $0)?.displayName
        }
        let lines = CheckGachaPanel(store: store).exchangeLines
        #expect(lines.map(\.id) == expected.map(\.characterID) && lines.map(\.availability) == expected.map(\.availability))
        #expect(lines.count >= 6, "교환 목록이 \(lines.count) 줄 — 교환표 일곱 값 중 여섯 이상은 있어야 한다")
        if lines.contains(where: { CharacterCatalog.isGoldAing($0.id) }) {
            #expect(CharacterCatalog.isGoldAing(lines.first?.id), "금이 교환 목록 맨 위가 아니다")
        }
        #expect(CheckGachaPanel.costText(.owned) == "보유")
        #expect(CheckGachaPanel.costText(.available(cost: 2)) == "조각 2개")
        #expect(CheckGachaPanel.costText(.short(cost: 5, missing: 2)) == "조각 3/5")
        #expect(CheckGachaPanel.costText(.short(cost: 20, missing: 17)) == "조각 3/20")
    }

    @Test("[캐릭터 뽑기] 카드가 더하는 크롬이 실측(gachaCardChrome)과 맞다 · 카드 없을 때는 종전 230 그대로 · 확성기와 한 줄을 나눠 쓰면 0")
    func gachaCardChromeMatchesMeasurement() throws {
        // 한 행(카드 1장·3장)으로 잰다 — 두 행(232pt)은 카드가 서면 격자 상한(249 − 31 = 218)에 걸려 '자연 높이'가 아니다.
        for cards in [1, 3] {
            func chrome(withGacha: Bool, extra: CGFloat = 0) throws -> CGFloat {
                let store = V0317ShopTests.plainStore()
                store.applyShopState(ShopStateResponse(rubyBalance: 10, ultraBalance: 1, ultraPrice: 3,
                                                       characters: V0317ShopTests.rows(ownedIDs: [], limit: cards)))
                store.shopLoaded = true
                store.megaphone.applyInfo(MegaphoneInfoResponse(price: 50, cooldownSeconds: 600, cooldownRemainingSeconds: 0,
                                                               recipients: 46, maxLength: 198))
                if withGacha { store.gachaInfo = Self.info() }
                #expect(store.isGachaAvailable == withGacha, "준비 실패 — 카드 유무 기준선이 안 갈렸다")
                let panel = CheckShopPanel(store: store, extraChromeHeight: extra, onBack: {})
                let height = try #require(Self.settledBitmap(panel, width: Self.width)).pixelsHigh
                return CGFloat(height) / 2 - ShopPanelGridBudget.naturalHeight(rowCount: ShopPanelGridBudget.rowCount(cardCount: cards))
            }
            let bare = try chrome(withGacha: false), carded = try chrome(withGacha: true)
            print("[v0354-gacha] 상점 크롬 카드 \(cards): 뽑기 없음 \(bare)pt · 뽑기 있음 \(carded)pt")
            #expect(abs(bare - ShopPanelGridBudget.chromeOutsideGrid) < 1.0)
            #expect(abs((carded - bare) - ShopPanelGridBudget.gachaCardChrome) < 1.0,
                    "뽑기 카드 크롬 \(carded - bare)pt ≠ 상수 \(ShopPanelGridBudget.gachaCardChrome)pt")
            // 큰 배너(새 버전 노트 4줄 149pt)가 얹혀 격자가 카드 높이를 못 받으면 확성기와 한 줄을 나눠 쓴다 — 크롬이 안 는다.
            // 한 행 격자는 이 크롬에서 상한(바닥 112)과 자연 높이가 같아 위와 같은 뺄셈으로 잰다.
            let banner: CGFloat = 149
            #expect(ShopPanelGridBudget.sharesConsumableRow(extraChromeHeight: banner))
            #expect(!ShopPanelGridBudget.sharesConsumableRow(extraChromeHeight: 0) && !ShopPanelGridBudget.sharesConsumableRow(extraChromeHeight: 92))
            let bareBanner = try chrome(withGacha: false, extra: banner), sharedBanner = try chrome(withGacha: true, extra: banner)
            print("[v0354-gacha] 상점 크롬 카드 \(cards) · 배너 \(banner): 뽑기 없음 \(bareBanner)pt · 한 줄 나눔 \(sharedBanner)pt")
            #expect(abs(sharedBanner - bareBanner) < 0.5, "확성기와 나눠 쓴 뽑기 카드가 크롬을 \(sharedBanner - bareBanner)pt 키웠다")
        }
    }

    @Test("뽑기 패널을 연 상점은 격자를 연 상점보다 높지 않다 · 패널 상수는 격자 구획 최소보다 작다")
    func gachaPanelFitsTheBudget() throws {
        func panelHeight(open: Bool, cards: Int, extra: CGFloat) throws -> CGFloat {
            let store = V0317ShopTests.plainStore()
            store.applyShopState(ShopStateResponse(rubyBalance: 100, ultraBalance: 1, ultraPrice: 3,
                                                   characters: V0317ShopTests.rows(ownedIDs: [], limit: cards)))
            store.shopLoaded = true
            store.gachaInfo = Self.info()
            if open {
                store.openGachaPanel(mode: .exchange)
            }
            let rep = try #require(V0317ShopTests.bitmap(CheckShopPanel(store: store, extraChromeHeight: extra, onBack: {}),
                                                         width: Self.width))
            return CGFloat(rep.pixelsHigh) / 2
        }
        for (cards, extra) in [(3, CGFloat(0)), (6, 0), (6, 92), (3, 92)] {
            let grid = try panelHeight(open: false, cards: cards, extra: extra)
            let open = try panelHeight(open: true, cards: cards, extra: extra)
            print("[v0354-gacha] 상점 패널 카드 \(cards) · 추가 크롬 \(extra): 격자 \(grid)pt vs 뽑기 패널 \(open)pt")
            #expect(open <= grid, "카드 \(cards) · 추가 \(extra): 뽑기 패널 \(open)pt > 격자 \(grid)pt")
        }
        #expect(CheckGachaPanel.height <= 14 + 4 + ShopPanelGridBudget.minGridHeight + 7 + CheckShopPanel.purchaseBarHeight)
    }

    /// 상점 위에 얹힐 수 있는 큰 배너들(배너는 한 번에 하나 — `CheckMenuView.TopBanner`).
    enum WorstBanner: String, CaseIterable {
        case none
        /// 새 버전 배너 + 노트 4줄(`UpdateCheckStore.maxNotes`) = 149pt — 팝오버가 얹는 가장 큰 배너.
        case update4
        /// 앱 공지 QR 카드 144pt — 닫기 전까지 로그인한 사람 모두에게 선다.
        case appNoticeQR
        /// 12시간 확인 92pt.
        case longSession
    }

    /// 상점이 그리는 세 모습: 격자 · 뽑기 패널 · 확성기 작성기(뒤 둘은 격자 구획 + 구매 바 자리를 빌린다).
    enum WorstMode: String, CaseIterable { case grid, gachaPanel, megaphone }

    static let worstNotes = ["캐릭터 뽑기가 생겼어요", "황금 아잉이를 만나 보세요", "판돈 수수료가 10%예요", "자잘한 문제를 고쳤어요"]

    /// 실제 팝오버(8인 팀 · 상점 · 확성기 가격 칩 · 금 포함 일곱 장)를 그려 높이를 잰다.
    static func worstPopoverHeight(banner: WorstBanner, goal: Bool, gacha: Bool, mode: WorstMode,
                                   save name: String? = nil) throws -> CGFloat {
        let label = "\(banner.rawValue)-\(goal)-\(gacha)-\(mode.rawValue)"
        let store = V0317ShopTests.teamStore(members: 8, service: V0317ShopTests.offlineService("v0354-worst-\(label)"),
                                             function: "worst-" + label)
        store.toggleShopPanel()
        store.applyShopState(ShopStateResponse(rubyBalance: 42, ultraBalance: 7, ultraPrice: 3, characters: Self.shopRows()))
        store.gachaInfo = gacha ? Self.info() : nil
        store.shopLoaded = true
        store.megaphone.applyInfo(MegaphoneInfoResponse(price: 50, cooldownSeconds: 600, cooldownRemainingSeconds: 0,
                                                       recipients: 46, maxLength: 198))
        #expect(store.isGachaAvailable == gacha && store.shopCharacters.count == 7, "\(label): 준비 실패")
        if banner == .appNoticeQR {
            // 앱이 공지를 심는 문 그대로(`applyAppNotice`) — QR 이 그려지는 주소를 준다.
            store.applyAppNotice(AppNotice(id: "ios-launch-2026-09", title: "아이폰 앱도 있어요",
                                           body: "앱스토어에서 아잉체크를 검색하거나 QR 을 찍어 주세요",
                                           linkURL: CheckAppLinks.iosAppStore.absoluteString, linkLabel: nil))
            #expect(store.appNotice != nil && store.isSignedIn, "\(label): 공지가 안 섰다")
        }
        if goal { store.isEditingWeeklyGoal = true }
        switch mode {
        case .grid: break
        case .gachaPanel:
            store.openGachaPanel(mode: .exchange)
            #expect(store.isGachaPanelOpen, "\(label): 뽑기 패널이 안 열렸다")
        case .megaphone:
            store.toggleMegaphoneComposer()
            #expect(store.megaphone.isComposerOpen, "\(label): 확성기 작성기가 안 열렸다")
        }
        let view = CheckMenuView(store: store,
                                 previewLongSessionBanner: banner == .longSession,
                                 previewClipsOverflowList: true,
                                 previewGoalEditing: goal,
                                 previewUpdateBanner: banner == .update4,
                                 previewUpdateNotes: banner == .update4 ? Self.worstNotes : [],
                                 characterDefaults: V0317ShopTests.isolatedDefaults(label))
        if let name, let rep = V0317ShopTests.bitmap(view, width: CheckMenuView.mainWindowWidth) { Self.save(rep, name) }
        return try #require(V0317ShopTests.popoverHeight(view))
    }

    /// ★ "최악 조합"은 **배너를 포함해** 잰다. 예전 이 테스트는 목표 편집(92pt)만 얹었고, 격자 상한이 그걸 다 흡수해 카드가 있든 없든
    ///   673pt 였다 — 정작 새 버전 배너 노트 4줄(714pt) · 앱 공지 QR(711pt)에서 뽑기 카드가 700pt 를 넘기는 걸 못 봤다(리뷰 실측).
    ///
    /// 단언 셋:
    ///  · 뽑기 카드는 팝오버를 **키우지 않는다** — 어느 조합 · 어느 모습(격자 · 뽑기 패널 · 확성기 작성기)이든 카드 없는 격자 화면 이하.
    ///  · 배너 하나 · 목표 편집 하나짜리 화면은 700pt 안이다.
    ///  · 배너가 정말 그려졌다 — 목표 편집과 겹치면 격자가 바닥(한 줄)에 닿아 배너만큼 팝오버가 커진다(재서 확인한다, 가정하지 않는다).
    /// 배너 + 목표 편집이 **겹친** 화면은 0.3.54 이전부터 700pt 를 넘는다(카드 없이 720~775pt — 상점 격자 바닥 112pt 가 그 크롬을 못 받는다).
    /// 그건 뽑기 카드가 만든 것이 아니라 여기서는 "카드가 더하지 않는다"만 못 박는다(보고서에 남긴다).
    @Test("최악 조합(큰 배너 · 목표 편집 · 뽑기 카드 · 확성기 · 금 포함 일곱 장): 뽑기 카드는 팝오버를 키우지 않고, 배너 하나짜리 화면은 700pt 안이다")
    func worstCasePopoverWithGacha() throws {
        var table: [String] = []
        var goalOnly: CGFloat = 0
        for banner in WorstBanner.allCases {
            for goal in [false, true] {
                let baseline = try Self.worstPopoverHeight(banner: banner, goal: goal, gacha: false, mode: .grid)
                var line = "\(banner.rawValue)\(goal ? "+목표" : ""): 카드 없음 \(baseline)"
                if banner == .none && goal { goalOnly = baseline }
                if banner != .none && goal {
                    #expect(baseline > goalOnly + 1, "\(banner): 배너가 안 그려졌다(목표 편집만 \(goalOnly)pt · 배너 더해 \(baseline)pt)")
                }
                for mode in WorstMode.allCases {
                    let save = (banner == .update4 && !goal) ? "gacha-popover-worst-\(mode.rawValue).png" : nil
                    let height = try Self.worstPopoverHeight(banner: banner, goal: goal, gacha: true, mode: mode, save: save)
                    line += " · \(mode.rawValue) \(height)"
                    #expect(height <= baseline + 0.5,
                            "\(banner)\(goal ? " + 목표 편집" : "") · \(mode): 뽑기 카드가 팝오버를 \(height - baseline)pt 키웠다(\(baseline) → \(height))")
                    if banner == .none || !goal {
                        #expect(height <= 700, "\(banner)\(goal ? " + 목표 편집" : "") · \(mode): 팝오버 \(height)pt — 700pt 상한을 넘어 푸터가 잘린다")
                    }
                }
                table.append(line)
            }
        }
        print("[v0354-gacha] 최악 조합 팝오버(pt)\n  " + table.joined(separator: "\n  "))
    }

    @Test("상점 격자의 금 카드: 안 가졌으면 '뽑기 또는 조각 20개'(금빛) · 가지면 '보유' — 렌더에서 금빛 글자가 갈린다")
    func goldCardRenders() throws {
        let unowned = Self.store(goldOwned: false), owned = Self.store(goldOwned: true)
        // 금 카드는 서버 순서(가격순)로 셋째 줄이라 평소엔 스크롤 아래다 — 격자 전체가 보이게 상한을 풀어 그린다(음수 추가 크롬).
        let a = try #require(Self.settledBitmap(CheckShopPanel(store: unowned, extraChromeHeight: -300,
                                                               clipsOverflowInsteadOfScroll: true, onBack: {}), width: Self.width))
        let b = try #require(Self.settledBitmap(CheckShopPanel(store: owned, extraChromeHeight: -300,
                                                               clipsOverflowInsteadOfScroll: true, onBack: {}), width: Self.width))
        Self.save(a, "gacha-shop-grid-gold-card.png")
        Self.save(b, "gacha-shop-grid-gold-owned.png")
        // 두 그림은 금 카드 아래 줄 글자만 다르다(초상·나머지 카드는 같다) — 금빛 글자 몫만큼 갈린다.
        let goldA = Self.goldInk(a), goldB = Self.goldInk(b)
        print("[v0354-gacha] 금 카드 금빛 픽셀 안 가짐 \(goldA) · 가짐 \(goldB)")
        #expect(goldA > goldB + 40, "안 가진 금 카드에 금빛 '뽑기 또는 조각' 글자가 안 보인다(\(goldA) vs \(goldB))")
        #expect(GachaText.gachaOnlyPrice(shardCost: unowned.gachaShardCost(of: CharacterCatalog.goldAingID))
                == "뽑기 또는 조각 20개")
    }
}

// MARK: - 판돈 수수료 문구

@MainActor
@Suite struct V0354DuelFeeCopyTests {
    // v0.3.64: 수수료를 없앴다(사용자 결정 2026-10-22 "멀티 미니게임 수수료 다시 제거해줘") — 이 스위트는 이제 **수수료가 없다는 것**을 잰다.
    @Test("판돈 줄은 순이익(+3/+5/+10 = +판돈) · 판돈 창·규칙 보기(오목·체스·테트리스)에 '수수료' 글자가 없다")
    func feeCopyShowsTheNet() {
        for (stake, net) in [(3, 3), (5, 5), (10, 10)] {
            #expect(GomokuText.stakeLine(stake) == "\(stake) · 이기면 +\(net)")
            #expect(ChessText.stakeLine(stake) == "\(stake) · 이기면 +\(net)")
            #expect(TetrisDuelText.stakeLine(stake) == "\(stake) · 이기면 +\(net)")
            #expect(GomokuText.stakePromptChosen(stake).hasSuffix("+\(net)") && ChessText.stakePromptChosen(stake).hasSuffix("+\(net)"))
            // 기준선: 수수료 시절 문구(+2/+4/+8)와 갈린다.
            #expect(GomokuText.stakeLine(stake) != "\(stake) · 이기면 +\(stake - (2 * stake + 5) / 10)")
        }
        let chessRules = ChessRulesOverlayLines.all.map(\.detail).joined()
        let tetrisRules = TetrisDuelText.rules.map(\.detail).joined()
        for (label, text) in [("오목 판돈 창", GomokuText.stakeCaption), ("오목 규칙", GomokuRuleExample.ruleLines.joined()),
                              ("체스 규칙", chessRules), ("테트리스 규칙", tetrisRules)] {
            #expect(!text.contains("수수료"), "\(label)이(가) 없어진 수수료를 말한다: \(text)")
            #expect(!text.contains("%"), "\(label)에 비율이 남았다: \(text)")
        }
        #expect(GomokuText.stakeCaption.contains("판돈만큼 더") && chessRules.contains("판돈만큼 더") && tetrisRules.contains("판돈만큼 더"))
        #expect(!GomokuText.stakeCaption.contains("도박") && !GomokuText.stakeCaption.contains("베팅"))
    }

    @Test("결과 카드의 대체값(서버 값이 없을 때)도 순이익이다 — 두 패널 모두 DuelFee.winnerNet 을 쓴다(소스 계약)")
    func resultFallbackUsesTheNet() throws {
        for file in ["GomokuPanel.swift", "ChessPanel.swift"] {
            let code = V0317ShopTests.stripped(try V0317ShopTests.source(file))
            #expect(code.contains("case .won?: return DuelFee.winnerNet(stake: match.stake)"), "\(file): 이긴 결과 대체값이 순이익이 아니다")
            #expect(!code.contains("case .won?: return match.stake"), "\(file): 수수료 전 대체값이 남아 있다")
        }
    }
}
