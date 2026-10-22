import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 폰 캐릭터 뽑기(v0.3.54 · 1.0.8) — `MeStore` 의 **진짜 경로**(스텁 서버 → `gacha_pull`/`gacha_exchange` → 스토어 상태 → 화면이 읽는 값)를 잰다.
///
/// 뷰(`MeGachaViews.swift`)는 iOS 전용이라 맥 스위트가 못 그린다 — 그래서 화면이 **읽는 값**(`showsGacha` · `canPullGacha` ·
/// `gachaDetail` · `lastGachaResult` 와 그 문구 · `gachaOddsRows` · `gachaExchangeRows` · 루비 미러)을 끝까지 따라간다.
/// 기대값은 손으로 적은 글자다(코어 함수로 기대값을 다시 만들면 코어가 틀려도 초록이다).
@MainActor
@Suite("나 탭 캐릭터 뽑기(v0.3.54)")
struct MeGachaStoreTests {
    /// 서버 `shop_state` 가 **무지개 행 없이** 준 응답(AMENDMENT 1 교환값 — 금 20 · 2/2/4/4/5/8). 상점 목록은 서버처럼 가격순(금은 명목가 1000 이라 맨 뒤).
    ///
    /// ★ 폰 1.0.10 은 `p_protocol = 3` 을 싣고(무지개 초상이 번들에 있다), 지금 운영 서버는 3 에 **8줄**(무지개 2 포함)을 준다.
    ///   이 픽스처는 그 8줄이 아니라 **금까지만 있는 7줄**이다 — 그래도 재는 것이 그대로 산다: 이 절들이 묻는 것은
    ///   "서버가 말한 표를 그대로 세우는가"이고, 기대값은 손으로 적은 글자다. 무지개가 **든** 응답(8줄 정수)과 서버가 무지개를
    ///   **안 준** 응답(7줄 소수 — 2 를 받은 클라가 보는 모양)은 `MeRainbowProtocolTests` 가 따로 잰다.
    ///   (이 픽스처를 8줄로 바꾸지 않은 이유: `MeGachaMachineTests` 가 `typealias Fixture = MeGachaStoreTests` 로 같은 글자를 쓴다.)
    static func shopV2(ruby: Int = 120, shards: Int = 0, owned: Set<String> = ["fox"]) -> String {
        func row(_ id: String, _ price: Int, gachaOnly: Bool = false) -> String {
            #"{"id":"\#(id)","price":\#(price),"owned":\#(owned.contains(id)),"gacha_only":\#(gachaOnly)}"#
        }
        let rows = [row("fox", 60), row("squirrel", 60), row("ghost", 100), row("shiba", 100), row("jellyfish", 140),
                    row("robot", 200), row("aing_gold", 1000, gachaOnly: true)].joined(separator: ",")
        return #"""
        {"ruby_balance":\#(ruby),"characters":[\#(rows)],
         "gacha":{"price":50,"shards":\#(shards),
                  "odds":[{"character_id":"aing_gold","percent":5},{"character_id":"fox","percent":24},
                          {"character_id":"squirrel","percent":24},{"character_id":"shiba","percent":14},
                          {"character_id":"ghost","percent":14},{"character_id":"jellyfish","percent":11},
                          {"character_id":"robot","percent":8}],
                  "shard_costs":{"aing_gold":20,"fox":2,"squirrel":2,"shiba":4,"ghost":4,"jellyfish":5,"robot":8}}}
        """#
    }

    /// 뽑기를 닫은 서버(키 없음) — 옛 서버 · db push 전 · 1 을 보낸 응답과 같은 모양.
    static let shopWithoutGacha = #"{"ruby_balance":120,"characters":[{"id":"fox","price":60,"owned":true},{"id":"ghost","price":100,"owned":false}]}"#

    static func pullOK(_ id: String, duplicate: Bool, shards: Int, ruby: Int, replayed: Bool = false) -> MobileStubResponse {
        .json(#"{"status":"ok","character_id":"\#(id)","duplicate":\#(duplicate),"shards_gained":\#(duplicate ? 1 : 0),"shards":\#(shards),"ruby_balance":\#(ruby),"price":50,"request_id":"00000000-0000-4000-8000-000000000001","replayed":\#(replayed)}"#)
    }

    // MARK: - 문 — 서버가 열어야 열린다

    @Test("뽑기 카드는 서버가 gacha 를 줄 때만 선다 · 키가 빠진 응답이 오면 다시 닫힌다 · 닫힌 채 누르면 요청 없이 이유만")
    func gachaFollowsServerKey() async throws {
        let harness = await RankMeHarness(label: "me-gacha-gate") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        // 전제는 **번들이 실제로 싣는 번호**다. 1.0.10 은 3 이다 — robot · 금 · 무지개 초상이 모두 번들에 있어서
        // (`AingCharacterArt.knownIDs`), 번호는 누적으로 3 까지 올라간다. 뽑기 문턱 자체는 2 그대로다(`supportsGacha`).
        #expect(store.shopProtocolVersion == ShopWire.rainbowProtocol,
                "전제: 이 번들은 3 을 보낸다(robot + 금 + 무지개 초상)")
        #expect(ShopWire.supportsGacha(protocolVersion: store.shopProtocolVersion), "전제: 이 번호로 뽑기가 열린다")

        harness.enqueue("shop_state", .json(Self.shopWithoutGacha))
        harness.enqueue("shop_state", .json(Self.shopV2()))
        harness.enqueue("shop_state", .json(Self.shopWithoutGacha))

        await store.loadShop()
        #expect(!store.showsGacha && store.gachaInfo == nil, "서버가 안 줬는데 뽑기가 선다")
        #expect(store.gachaPullAvailability == .unavailable)
        store.pullGacha()
        #expect(store.gachaNotice == GachaText.unavailable && store.gachaNotice == "지금은 뽑을 수 없어요")
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "gacha_pull").isEmpty, "닫힌 뽑기로 요청을 냈다")

        await store.loadShop()
        #expect(store.showsGacha, "서버가 gacha 를 줬는데 카드가 안 선다")
        #expect(store.gachaInfo?.price == 50 && store.gachaShards == 0)
        #expect(store.canPullGacha && store.gachaPullAvailability == .ready(price: 50))

        await store.loadShop()
        #expect(!store.showsGacha, "서버가 닫은 뒤에도 지난 뽑기 정보가 남아 카드가 선다")
        #expect(!store.canPullGacha)
        harness.expectNoForbiddenCalls()
    }

    // MARK: - 뽑기 — 결과 세 갈래

    @Test("뽑기: 새 캐릭터 · 중복(조각 +1) · 황금 아잉이 — 본문 키 · 누를 때마다 새 request_id · 잔량은 서버 값 · 결과 문구 · 보유")
    func pullThreeOutcomes() async throws {
        let harness = await RankMeHarness(label: "me-gacha-pull") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Self.shopV2(ruby: 200, shards: 0)))
        await store.loadShop()
        #expect(store.rubyBalance == 200)

        // ① 새 캐릭터(다람쥐) — 잔량 150, 보유에 들어간다.
        harness.enqueue("gacha_pull", Self.pullOK("squirrel", duplicate: false, shards: 0, ruby: 150))
        harness.enqueue("shop_state", .json(Self.shopV2(ruby: 150, shards: 0, owned: ["fox", "squirrel"])))
        store.pullGacha()
        #expect(store.isPulling && !store.canPullGacha, "요청이 떠 있는데 버튼이 안 잠긴다")
        await harness.quiesceMe()
        #expect(!store.isPulling)
        let first = try #require(harness.requests(rpc: "gacha_pull").last?.jsonBody)
        #expect(Set(first.keys) == ["p_protocol", "p_request_id"], "본문 \(first)")
        // 3 이다(2 가 아니다 — v0.3.59 무지개). 2 를 실으면 서버가 무지개를 뺀 7줄로 추첨해 무지개가 영영 안 나온다.
        #expect(first["p_protocol"] as? Int == 3)
        let firstID = try #require(first["p_request_id"] as? String)
        #expect(UUID(uuidString: firstID) != nil && firstID == firstID.lowercased(), "request_id 가 소문자 uuid 가 아니다: \(firstID)")
        let newResult = try #require(store.lastGachaResult)
        #expect(newResult.kind == .newCharacter)
        #expect(GachaText.headline(for: newResult, name: store.gachaName(newResult.characterID)) == "새 캐릭터: 다람쥐")
        #expect(store.rubyBalance == 150 && harness.model.gomokuHost.rubyBalance == 150, "잔량 미러가 서버 값이 아니다")
        #expect(store.isOwned("squirrel"))
        #expect(store.gachaNotice == nil && store.gachaDetail == nil)
        #expect(harness.requests(rpc: "shop_state").count == 2, "뽑은 뒤 상점을 다시 읽어 서버 값에 맞추지 않는다")
        let firstSerial = store.gachaRevealSerial

        // ② 중복(여우 — 이미 있다) → 조각 +1.
        harness.enqueue("gacha_pull", Self.pullOK("fox", duplicate: true, shards: 1, ruby: 100))
        harness.enqueue("shop_state", .json(Self.shopV2(ruby: 100, shards: 1, owned: ["fox", "squirrel"])))
        store.pullGacha()
        await harness.quiesceMe()
        let dup = try #require(store.lastGachaResult)
        #expect(dup.kind == .duplicate && dup.shardsGained == 1)
        #expect(GachaText.headline(for: dup, name: store.gachaName(dup.characterID)) == "이미 있는 여우 → 조각 +1")
        #expect(store.gachaShards == 1, "조각 수가 서버 값으로 안 바뀌었다")
        #expect(store.gachaRevealSerial == firstSerial + 1, "새 결과인데 연출 번호가 안 올랐다")
        let secondID = try #require(harness.requests(rpc: "gacha_pull").last?.jsonBody["p_request_id"] as? String)
        #expect(secondID != firstID, "답을 받은 뒤 새로 누른 뽑기가 같은 request_id 를 썼다 — 서버가 replayed 로 막아 영영 한 번만 뽑힌다")

        // ③ 황금 아잉이(처음) — "황금 아잉이!" + 둘째 줄 "새 캐릭터: 황금 아잉이".
        harness.enqueue("gacha_pull", Self.pullOK("aing_gold", duplicate: false, shards: 1, ruby: 50))
        harness.enqueue("shop_state", .json(Self.shopV2(ruby: 50, shards: 1, owned: ["fox", "squirrel", "aing_gold"])))
        store.pullGacha()
        await harness.quiesceMe()
        let gold = try #require(store.lastGachaResult)
        #expect(gold.kind == .gold)
        let goldName = store.gachaName(gold.characterID)
        #expect(goldName == "황금 아잉이")
        #expect(GachaText.headline(for: gold, name: goldName) == "황금 아잉이!")
        #expect(GachaText.detail(for: gold, name: goldName) == "새 캐릭터: 황금 아잉이")
        #expect(store.isOwned("aing_gold") && store.rubyBalance == 50)
        // 잔량 50 = 값 50 → 아직 뽑을 수 있다(같으면 된다).
        #expect(store.canPullGacha)
        #expect(Set(harness.requests(rpc: "gacha_pull").compactMap { $0.jsonBody["p_request_id"] as? String }).count == 3)
        harness.expectNoForbiddenCalls()
    }

    // MARK: - 연타 · 결과를 모르는 실패

    @Test("연타는 요청 하나 · 결과를 모르는 실패(오프라인·500)는 같은 request_id 로 다시 묻고 replayed 결과를 그대로 받는다 · 그다음은 새 id")
    func unknownFailureReusesRequestID() async throws {
        let harness = await RankMeHarness(label: "me-gacha-retry") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Self.shopV2(ruby: 200)))
        await store.loadShop()

        // 연타: 응답을 붙잡아 둔 채 세 번 누른다.
        let hold = BaseHold.rpc("gacha_pull", host: harness.host)
        harness.enqueue("gacha_pull", .networkFailure())
        store.pullGacha()
        store.pullGacha()
        store.pullGacha()
        #expect(await hold.waitHeld())
        #expect(store.isPulling)
        #expect(await hold.releaseAndWaitDelivered())
        await harness.quiesceMe()
        #expect(hold.held == 1, "세 번 눌렀더니 요청이 \(hold.held)개 나갔다")
        #expect(harness.requests(rpc: "gacha_pull").count == 1)
        #expect(store.gachaNotice == GachaText.connection && store.isGachaNoticeError)
        #expect(store.lastGachaResult == nil)
        #expect(store.rubyBalance == 200, "결과를 모르는데 잔량을 지어냈다")
        let heldID = try #require(store.gachaRequestIDs.pull, "결과를 모르는 실패 뒤 request_id 를 버렸다 — 다시 누르면 두 번 깎일 수 있다")

        // 5xx 도 결과를 모른다.
        harness.enqueue("gacha_pull", .json(#"{"message":"boom"}"#, status: 500))
        store.pullGacha()
        await harness.quiesceMe()
        #expect(store.gachaRequestIDs.pull == heldID, "500 뒤 id 를 바꿨다")
        #expect(store.gachaNotice == GachaText.connection)

        // 다시 누르면 같은 id — 서버는 이미 처리했던 결과를 replayed 로 준다(두 번 깎지 않는다).
        harness.enqueue("gacha_pull", Self.pullOK("ghost", duplicate: false, shards: 0, ruby: 150, replayed: true))
        store.pullGacha()
        await harness.quiesceMe()
        let ids = harness.requests(rpc: "gacha_pull").compactMap { $0.jsonBody["p_request_id"] as? String }
        #expect(ids.count == 3 && Set(ids).count == 1, "결과를 모르는 동안 id 가 흔들렸다: \(ids)")
        #expect(ids.first == heldID.uuidString.lowercased())
        #expect(store.lastGachaResult?.characterID == "ghost" && store.lastGachaResult?.replayed == true)
        #expect(store.rubyBalance == 150)
        #expect(store.gachaRequestIDs.pull == nil, "답을 받았는데 id 를 쥐고 있다")

        // 답을 받은 뒤의 누름은 새 동작 → 새 id.
        harness.enqueue("gacha_pull", Self.pullOK("fox", duplicate: true, shards: 1, ruby: 100))
        store.pullGacha()
        await harness.quiesceMe()
        let last = try #require(harness.requests(rpc: "gacha_pull").last?.jsonBody["p_request_id"] as? String)
        #expect(last != heldID.uuidString.lowercased(), "새 동작이 앞 동작의 id 를 썼다")
        harness.expectNoForbiddenCalls()
    }

    // MARK: - 거절

    @Test("모자람: 클라가 먼저 막고(요청 없음) 이유를 말한다 · 서버 insufficient 는 서버의 need/have 로 · 함수 없음·needs_update 는 그 문장")
    func refusals() async throws {
        let harness = await RankMeHarness(label: "me-gacha-refuse") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Self.shopV2(ruby: 40)))
        await store.loadShop()
        #expect(store.gachaPullAvailability == .short(price: 50, missing: 10))
        #expect(!store.canPullGacha)
        #expect(store.gachaDetail == "루비 10개 더 필요해요", "버튼 아래 이유가 없다: \(String(describing: store.gachaDetail))")
        store.pullGacha()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "gacha_pull").isEmpty, "모자란데 요청을 냈다")

        // 다른 기기에서 루비를 받아 클라는 60 으로 알지만, 서버는 그새 30 이라고 말한다.
        harness.enqueue("shop_state", .json(Self.shopV2(ruby: 60)))
        await store.loadShop()
        #expect(store.canPullGacha)
        harness.enqueue("gacha_pull", .json(#"{"status":"insufficient","need":50,"have":30}"#))
        store.pullGacha()
        await harness.quiesceMe()
        #expect(store.gachaNotice == "루비 20개 더 필요해요" && store.isGachaNoticeError)
        #expect(store.rubyBalance == 30, "서버가 말한 잔량으로 맞추지 않았다")
        #expect(!store.canPullGacha)
        #expect(store.gachaRequestIDs.pull == nil, "서버가 답했는데 id 를 쥐고 있다")

        harness.enqueue("shop_state", .json(Self.shopV2(ruby: 100)))
        await store.loadShop()
        harness.enqueue("gacha_pull", .json(#"{"status":"needs_update"}"#))
        store.pullGacha()
        await harness.quiesceMe()
        #expect(store.gachaNotice == "앱을 업데이트하면 뽑을 수 있어요")
        #expect(store.rubyBalance == 100)

        // 함수가 없는 서버(앱이 db push 보다 먼저 나간 창) — 하네스 기본 응답이 PGRST202 다.
        store.pullGacha()
        await harness.quiesceMe()
        #expect(store.gachaNotice == "지금은 뽑을 수 없어요")
        #expect(store.gachaRequestIDs.pull == nil, "함수가 없다는 게 확실한데 id 를 쥐고 있다")
        #expect(store.lastGachaResult == nil && store.rubyBalance == 100)
        harness.expectNoForbiddenCalls()
    }

    // MARK: - 확률표 · 교환표

    @Test("확률표: 서버 순서 그대로 7줄 · 이름은 앱 카드 이름(시바 → 강아지) · 상점가는 서버 값 · 금은 사는 줄이 아니다")
    func oddsRowsFollowServer() async throws {
        let harness = await RankMeHarness(label: "me-gacha-odds") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        #expect(store.gachaOddsRows.isEmpty, "상점을 읽기 전에 확률표를 지어냈다")
        harness.enqueue("shop_state", .json(Self.shopV2()))
        await store.loadShop()
        let rows = store.gachaOddsRows
        #expect(rows.map(\.characterID) == ["aing_gold", "fox", "squirrel", "shiba", "ghost", "jellyfish", "robot"])
        #expect(rows.map(\.name) == ["황금 아잉이", "여우", "다람쥐", "강아지", "유령", "해파리", "로봇"])
        #expect(rows.map(\.percentText) == ["5%", "24%", "24%", "14%", "14%", "11%", "8%"])
        #expect(rows.dropFirst().map(\.shopPrice) == [60, 60, 100, 100, 140, 200])
        #expect(rows.first?.shopPrice == nil && rows.first?.isGachaOnly == true, "금 줄에 명목가 1000 이 상점가로 섰다")
        #expect(rows.first?.priceText != "1000")
    }

    @Test("교환표: 서버 교환값 그대로(박지 않는다) · 확률표 순서 · 보유는 '보유' · 모자라면 잠김 · 금은 코어가 교환을 허락할 때 맨 앞")
    func exchangeRowsFollowServer() async throws {
        let harness = await RankMeHarness(label: "me-gacha-xrows") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Self.shopV2(shards: 4, owned: ["fox"])))
        await store.loadShop()
        let rows = store.gachaExchangeRows
        // 황금 아잉이 교환(AMENDMENT 1 — 조각 20)은 코어 판정(`GachaRules.exchangeAvailability`)이 쥔다. 이 화면은 그 판정을 따를 뿐이다.
        let goldExchangeable = GachaRules.exchangeAvailability(characterID: "aing_gold", isOwned: false, shards: 100,
                                                                shardCosts: ["aing_gold": 20]) != .notExchangeable
        #expect(rows.map(\.characterID)
                == (goldExchangeable ? ["aing_gold"] : []) + ["fox", "squirrel", "shiba", "ghost", "jellyfish", "robot"])
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.characterID, $0.availability) })
        #expect(byID["fox"] == .owned)
        #expect(byID["squirrel"] == .available(cost: 2))
        #expect(byID["shiba"] == .available(cost: 4), "조각 4 로 4 짜리를 못 바꾼다(같으면 된다)")
        #expect(byID["jellyfish"] == .short(cost: 5, missing: 1))
        #expect(byID["robot"] == .short(cost: 8, missing: 4))
        if goldExchangeable { #expect(byID["aing_gold"] == .short(cost: 20, missing: 16)) }
        #expect(store.gachaShardCost(of: "aing_gold") == 20 && store.gachaShardCost(of: "aing") == nil)

        // 서버가 값을 바꾸면 화면도 바뀐다(기준선이 다르다).
        harness.enqueue("shop_state", .json(Self.shopV2(shards: 4).replacingOccurrences(of: #""squirrel":2"#, with: #""squirrel":7"#)))
        await store.loadShop()
        #expect(store.gachaExchangeAvailability("squirrel") == .short(cost: 7, missing: 3))
    }

    // MARK: - 교환

    @Test("교환: 본문 키 셋 · 서버 조각 수 · 보유 · 안내 · 모자라면 요청 없음 · 서버 insufficient_shards · 연타는 요청 하나")
    func exchangeFlow() async throws {
        let harness = await RankMeHarness(label: "me-gacha-exchange") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Self.shopV2(shards: 5)))
        await store.loadShop()

        let hold = BaseHold.rpc("gacha_exchange", host: harness.host)
        harness.enqueue("gacha_exchange", .json(#"{"status":"ok","character_id":"squirrel","shards":3,"cost":2,"request_id":"00000000-0000-4000-8000-0000000000e1","replayed":false}"#))
        harness.enqueue("shop_state", .json(Self.shopV2(shards: 3, owned: ["fox", "squirrel"])))
        store.exchangeShards(for: "squirrel")
        store.exchangeShards(for: "squirrel")
        store.exchangeShards(for: "shiba")
        #expect(store.exchangingID == "squirrel")
        #expect(await hold.waitHeld())
        #expect(await hold.releaseAndWaitDelivered())
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "gacha_exchange").count == 1, "교환 중에 또 눌러 요청이 더 나갔다")
        let body = try #require(harness.requests(rpc: "gacha_exchange").first?.jsonBody)
        #expect(Set(body.keys) == ["p_character_id", "p_protocol", "p_request_id"], "본문 \(body)")
        // 번호 3 — 2 를 실으면 서버 교환표에 무지개(조각 20)가 아예 없어 무지개 교환이 `needs_update` 로 거절된다.
        #expect(body["p_character_id"] as? String == "squirrel" && body["p_protocol"] as? Int == 3)
        #expect(store.isOwned("squirrel") && store.gachaShards == 3)
        #expect(store.exchangeNotice == "교환했어요: 다람쥐" && !store.isExchangeNoticeError)
        #expect(store.rubyBalance == 120, "교환이 루비를 움직였다")
        #expect(store.exchangingID == nil)

        // 조각 3 으로 해파리(5)는 못 바꾼다 — 요청 없이 이유.
        store.exchangeShards(for: "jellyfish")
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "gacha_exchange").count == 1)
        #expect(store.exchangeNotice == "조각 2개 더 필요해요")
        // 가진 것은 "이미 갖고 있어요".
        store.exchangeShards(for: "fox")
        #expect(store.exchangeNotice == GachaText.alreadyOwned)

        // 클라는 조각 5 로 알지만(강아지 4 를 바꿀 수 있다) 서버는 그새 1 이라고 말한다(다른 기기에서 썼다).
        harness.enqueue("shop_state", .json(Self.shopV2(shards: 5, owned: ["fox", "squirrel"])))
        await store.loadShop()
        #expect(store.gachaExchangeAvailability("shiba") == .available(cost: 4))
        harness.enqueue("gacha_exchange", .json(#"{"status":"insufficient_shards","need":4,"have":1}"#))
        store.exchangeShards(for: "shiba")
        await harness.quiesceMe()
        #expect(store.exchangeNotice == "조각 3개 더 필요해요" && store.isExchangeNoticeError)
        #expect(store.gachaShards == 1, "서버가 말한 조각 수로 맞추지 않았다")
        #expect(!store.isOwned("shiba"))
        harness.expectNoForbiddenCalls()
    }

    // MARK: - 세대 가드 · 로그아웃

    @Test("로그아웃 뒤 도착한 뽑기·교환 응답은 아무것도 안 바꾼다 · 로그아웃은 뽑기 상태와 request_id 를 비운다")
    func generationGuardAndReset() async throws {
        let harness = await RankMeHarness(label: "me-gacha-race") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Self.shopV2(ruby: 200, shards: 2)))
        await store.loadShop()

        // 같은 세대: 옮긴다(가드가 모든 응답을 버리지 않는다는 기준선).
        let ok = GachaPullResponse(status: .ok, characterID: "ghost", duplicate: false, shardsGained: 0, shards: 2, rubyBalance: 150, replayed: false)
        harness.enqueue("shop_state", .json(Self.shopV2(ruby: 150, shards: 2, owned: ["fox", "ghost"])))
        await store.applyGachaPullResponse(ok, requestID: UUID(), generation: store.context.generation)
        #expect(store.lastGachaResult?.characterID == "ghost" && store.rubyBalance == 150)

        // 결과를 모르는 채 쥔 id 를 만든다.
        harness.enqueue("gacha_pull", .networkFailure())
        store.pullGacha()
        await harness.quiesceMe()
        #expect(store.gachaRequestIDs.pull != nil)

        let oldGeneration = store.context.generation
        await harness.model.session.signOut()
        await harness.barrier()
        #expect(!harness.model.session.isSignedIn)
        #expect(store.gachaInfo == nil && !store.showsGacha && store.lastGachaResult == nil && store.gachaNotice == nil)
        #expect(store.gachaRequestIDs == GachaRequestIDs(), "앞 계정의 request_id 가 남았다")
        #expect(!store.isPulling && store.exchangingID == nil)

        // 로그아웃 뒤 메인 액터 차례를 기다리던 응답 — 버린다.
        let late = GachaPullResponse(status: .ok, characterID: "aing_gold", duplicate: false, shardsGained: 0, shards: 9, rubyBalance: 77, replayed: false)
        await store.applyGachaPullResponse(late, requestID: UUID(), generation: oldGeneration)
        let lateExchange = GachaExchangeResponse(status: .ok, characterID: "robot", shards: 1, cost: 8)
        await store.applyGachaExchangeResponse(lateExchange, id: "robot", requestID: UUID(), generation: oldGeneration)
        #expect(harness.model.gomokuHost.rubyBalance == nil, "로그아웃 뒤 뽑기 응답이 루비 미러를 세웠다")
        #expect(store.ownedCharacterIDs == [MeCharacterCards.aingID], "로그아웃 뒤 응답이 보유를 더했다")
        #expect(store.lastGachaResult == nil && store.gachaInfo == nil && store.exchangeNotice == nil)
    }

    // MARK: - 상점 타일 · 고르기 — 금은 사는 줄이 아니다

    @Test("금 타일: 명목가 1000 을 가격으로 안 쓴다 · 눌러도 고르지 않고 얻는 길을 말한다 · 고르기 잠김 문구도 '상점에서'가 아니다")
    func goldIsNotForSale() async throws {
        let harness = await RankMeHarness(label: "me-gacha-gold-tile") { request in
            if request.path == "/rest/v1/profiles", request.query.contains("select=character") { return .json(#"[{"character":null}]"#) }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Self.shopV2(ruby: 5_000)))
        await store.loadShop()
        await store.loadEquippedCharacter()

        #expect(store.shopRows.contains { $0.id == "aing_gold" }, "전제: 서버가 금 행을 줬다")
        #expect(store.price(of: "aing_gold") == nil, "명목가 1000 이 상점가로 읽힌다")
        #expect(store.price(of: "ghost") == 100, "기준선: 파는 캐릭터는 값이 있다")
        #expect(store.isGachaOnly("aing_gold") && !store.isGachaOnly("ghost"))

        store.selectShopItem("aing_gold")
        #expect(store.shopSelection == nil && !store.canConfirmPurchase, "금을 사려고 고를 수 있다")
        #expect(store.shopBarDetail == "황금 아잉이는 뽑기 또는 조각 20개로 얻을 수 있어요")
        store.confirmPurchase()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "buy_character").isEmpty, "금을 사려 했다")
        // 기준선: 유령은 고르면 살 수 있다.
        store.selectShopItem("ghost")
        #expect(store.shopSelection == "ghost" && store.canConfirmPurchase)

        // 고르기: 안 가진 금 → 얻는 길(서버 교환값 20). 유령 → 종전 문장.
        store.chooseCharacter("aing_gold")
        #expect(store.characterNotice == "황금 아잉이는 아직 없어요 — 뽑기 또는 조각 20개로 얻을 수 있어요")
        store.chooseCharacter("ghost")
        #expect(store.characterNotice == "유령은 아직 없어요 — 상점에서 살 수 있어요")
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "set_character").isEmpty)

        // 교환값을 모르는 서버(교환표에 금이 없다)면 "뽑기로만" — 그리고 누른 뒤 상점이 다시 읽혀도 안내는 **지금 값**으로
        // 말한다(누를 때 굳혀 두면 상점이 읽히기 전에 누른 "뽑기로만"이 교환값을 안 뒤에도 남는다 — 시뮬레이터 실측).
        store.selectShopItem("aing_gold")
        #expect(store.shopBarDetail == "황금 아잉이는 뽑기 또는 조각 20개로 얻을 수 있어요")
        harness.enqueue("shop_state", .json(Self.shopV2(ruby: 5_000).replacingOccurrences(of: #""aing_gold":20,"#, with: "")))
        await store.loadShop()
        #expect(store.gachaShardCost(of: "aing_gold") == nil)
        // 교환값을 모를 때의 문장은 코어 `GachaText.gachaOnlyHint`(맥과 한 벌 — AMENDMENT 1 로 코어가 고친다)를 그대로 쓴다.
        let unknownCostHint = "황금 아잉이는 \(GachaText.gachaOnlyHint)"
        #expect(store.shopBarDetail == unknownCostHint, "교환값이 사라졌는데 안내가 옛 값을 말한다")
        #expect(store.shopBarDetail?.contains("조각 20") == false && store.shopBarDetail?.contains("상점") == false)
        store.selectShopItem("ghost")
        #expect(store.shopBarDetail != unknownCostHint, "다른 타일을 눌렀는데 금 안내가 남았다")
        #expect(MeText.gachaTileStatus(shardCost: nil) == "뽑기 전용")
        #expect(MeText.gachaTileStatus(shardCost: 20) == "뽑기 · 조각 20")
        harness.expectNoForbiddenCalls()
    }

    @Test("고르기: 서버가 금을 not_owned 로 거절하면 뽑기 쪽 문장(기준선: 여우는 종전 문장) · 가진 금은 입는다(p_id=aing_gold)")
    func equipGold() async throws {
        let harness = await RankMeHarness(label: "me-gacha-equip") { request in
            if request.path == "/rest/v1/profiles", request.query.contains("select=character") { return .json(#"[{"character":null}]"#) }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Self.shopV2(owned: ["fox", "aing_gold"])))
        await store.loadShop()
        await store.loadEquippedCharacter()
        #expect(store.equippedCharacterID == "aing")

        // 다른 기기·운영자가 소유를 정리했다 — 금의 거절 문장은 "상점에서"가 아니다.
        harness.enqueue("set_character", .json(#"{"status":"not_owned"}"#))
        harness.enqueue("shop_state", .json(Self.shopV2(owned: ["fox", "aing_gold"])))
        store.chooseCharacter("aing_gold")
        #expect(await baseWaitUntil { store.savingCharacterID == nil && store.characterNotice != nil })
        #expect(store.characterNotice == MeText.gachaCharacterNotOwned)
        #expect(MeText.gachaCharacterNotOwned == "아직 없는 캐릭터예요 — 뽑기나 조각 교환으로 얻을 수 있어요")
        await harness.quiesceMe()

        // 기준선: 여우의 not_owned 는 종전 문장(상점).
        harness.enqueue("set_character", .json(#"{"status":"not_owned"}"#))
        harness.enqueue("shop_state", .json(Self.shopV2(owned: ["fox", "aing_gold"])))
        store.chooseCharacter("fox")
        #expect(await baseWaitUntil { store.savingCharacterID == nil && store.characterNotice == MeText.characterNotOwned })
        await harness.quiesceMe()

        // 가진 금은 입는다 — 화면이 아잉으로 접히지 않는다(초상 명단에 금이 있다).
        harness.enqueue("set_character", .json(#"{"status":"ok","character":"aing_gold"}"#))
        store.chooseCharacter("aing_gold")
        #expect(await baseWaitUntil { store.savingCharacterID == nil && store.equippedCharacterID == "aing_gold" },
                "금을 입었는데 화면이 아잉으로 접혔다")
        #expect(harness.requests(rpc: "set_character").last?.jsonBody["p_id"] as? String == "aing_gold")
        #expect(store.characterNotice == MeText.characterSaved)
        await harness.quiesceMe()
        harness.expectNoForbiddenCalls()
    }

    // MARK: - 폰이 더 쓰는 문구(코어 GachaText 밖)

    @Test("폰 문구: 설명 줄 · 교환 진입 · 교환 확인 · 타일 · 조사(을/를 · 은/는) — 숫자는 넘긴 값")
    func phoneOnlyCopy() {
        #expect(MeText.gachaLede(price: 50) == "루비 50개로 캐릭터 하나를 뽑아요")
        #expect(MeText.gachaLede(price: 70) == "루비 70개로 캐릭터 하나를 뽑아요", "값을 박았다")
        #expect(MeText.gachaExchangeEntry(shards: 3) == "조각 3개 · 교환")
        #expect(MeText.gachaExchangeEntry(shards: nil) == "조각 교환")
        #expect(MeText.exchangeConfirmTitle(name: "여우", cost: 2) == "여우를 조각 2개로 교환할까요?")
        #expect(MeText.exchangeConfirmTitle(name: "황금 아잉이", cost: 20) == "황금 아잉이를 조각 20개로 교환할까요?")
        #expect(MeText.exchangeConfirmTitle(name: "다람쥐", cost: 2) == "다람쥐를 조각 2개로 교환할까요?")
        #expect(MeText.exchangeConfirmTitle(name: "유령", cost: 4) == "유령을 조각 4개로 교환할까요?")
        #expect(MeText.exchangeConfirmMessage(cost: 2, shards: 5) == "남는 조각 3개")
        #expect(MeText.gachaOnlyNotice("유령", shardCost: 4) == "유령은 뽑기 또는 조각 4개로 얻을 수 있어요")
        #expect(MeText.gachaTileAccessibility(name: "황금 아잉이", shardCost: 20) == "황금 아잉이, 뽑기 또는 조각 20개로 얻을 수 있어요")
        #expect(MeText.exchangeBlocked(.available(cost: 2)) == nil)
        #expect(MeText.exchangeBlocked(.short(cost: 5, missing: 2)) == "조각 2개 더 필요해요")
        #expect(MeText.exchangeRowAccessibility(name: "여우", availability: .available(cost: 2)) == "여우, 조각 2개, 교환할 수 있어요")
        for line in [MeText.gachaLede(price: 50), MeText.gachaCharacterNotOwned, MeText.gachaOnlyNotice("황금 아잉이", shardCost: 20)] {
            for word in ["도박", "베팅"] { #expect(!line.contains(word)) }
        }
    }

    @Test("고르기 목록: 뽑기가 없는 서버면 얻을 길 없는 금 타일을 세우지 않는다 · 서버가 금을 말하거나 가졌으면 선다")
    func pickerHidesGoldWithoutServerGacha() async throws {
        let harness = await RankMeHarness(label: "me-gacha-picker") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        #expect(store.pickerIDs.contains("aing_gold"), "상점을 읽기 전에는 막지 않는다")
        harness.enqueue("shop_state", .json(Self.shopWithoutGacha))
        await store.loadShop()
        #expect(!store.pickerIDs.contains("aing_gold"), "뽑기가 없는 서버인데 금 타일이 선다")
        #expect(store.pickerIDs.contains("robot"), "기준선: 다른 캐릭터는 그대로")
        harness.enqueue("shop_state", .json(Self.shopV2()))
        await store.loadShop()
        #expect(store.pickerIDs.contains("aing_gold"))
        // 뽑기를 안 싣는 응답이라도 가진 금은 서버가 보유 행으로 싣는다(`or o.user_id is not null`) — 고르기에 선다.
        harness.enqueue("shop_state", .json(#"{"ruby_balance":10,"characters":[{"id":"aing_gold","price":1000,"owned":true,"gacha_only":true}]}"#))
        await store.loadShop()
        #expect(store.pickerIDs.contains("aing_gold"), "가진 금이 고르기에서 사라졌다")
    }

    // MARK: - 연달아 뽑기 — 늦은 상점 조회(맥 리뷰 결함의 폰 짝 점검)

    /// 맥은 뽑기 뒤 상점 다시 읽기가 떠 있는 동안 [한 번 더]가 풀려, 늦게 온 그 조회가 둘째 뽑기 값을 되돌렸다(v0.3.54 리뷰 P1).
    /// 폰은 같은 결함이 없다 — 이 테스트가 그 이유 둘을 못 박는다:
    ///  · 뽑기 응답을 옮긴 뒤 **다시 읽기가 끝나야** `isPulling` 이 풀린다(그 사이 [뽑기]는 요청을 안 낸다).
    ///  · 상점 조회는 순번(`nextSerial("shop")`)으로 **마지막에 떠난 것만** 옮긴다 — 뽑기 전에 떠난 조회가 늦게 와도 버린다.
    @Test("연달아 뽑기(폰): 뽑기 뒤 다시 읽기가 끝나야 [뽑기]가 풀리고, 뽑기 전에 떠난 늦은 상점 조회는 뽑기 값을 되돌리지 않는다")
    func lateShopFetchNeverRollsBackAPull() async throws {
        let harness = await RankMeHarness(label: "me-gacha-race") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Self.shopV2(ruby: 200, shards: 0, owned: ["fox"])))
        await store.loadShop()
        #expect(store.rubyBalance == 200 && store.canPullGacha)

        // ① 뽑기 **전에** 떠난 상점 조회(화면 다시 열기)를 붙잡는다.
        let staleHold = BaseHold.rpc("shop_state", host: harness.host)
        let stale = Task { await store.loadShop() }
        #expect(await staleHold.waitHeld())
        // ② 뽑기 뒤의 다시 읽기도 붙잡는다(붙잡기는 설치 순서로 고른다 — ①은 이미 찼다).
        let refetchHold = BaseHold.rpc("shop_state", host: harness.host)
        harness.enqueue("gacha_pull", Self.pullOK("ghost", duplicate: false, shards: 0, ruby: 150))
        store.pullGacha()
        #expect(await refetchHold.waitHeld(), "뽑은 뒤 상점을 다시 읽지 않는다")
        #expect(store.rubyBalance == 150 && store.isOwned("ghost"), "뽑기 응답을 안 옮겼다")
        // 다시 읽기가 떠 있는 동안은 [뽑기]가 잠겨 있다 — 둘째 뽑기가 끼어들 틈이 없다.
        #expect(store.isPulling && !store.canPullGacha, "다시 읽기가 끝나기 전에 [뽑기]가 풀렸다")
        store.pullGacha()
        #expect(harness.requests(rpc: "gacha_pull").count == 1, "다시 읽기가 떠 있는데 둘째 뽑기가 나갔다")

        // ②(뽑기 뒤 사실)를 먼저 놓고, ①(뽑기 전 값 — 200 · 유령 없음)이 **나중에** 도착하게 한다.
        harness.enqueue("shop_state", .json(Self.shopV2(ruby: 150, shards: 0, owned: ["fox", "ghost"])))
        #expect(await refetchHold.releaseAndWaitDelivered())
        #expect(await baseWaitUntil { !store.isPulling }, "다시 읽기가 끝났는데 [뽑기]가 안 풀린다")
        harness.enqueue("shop_state", .json(Self.shopV2(ruby: 200, shards: 0, owned: ["fox"])))
        #expect(await staleHold.releaseAndWaitDelivered())
        await stale.value
        await harness.quiesceMe()
        #expect(store.rubyBalance == 150, "잔량 \(String(describing: store.rubyBalance)) — 뽑기 전에 떠난 조회(200)가 덮었다")
        #expect(store.isOwned("ghost"), "방금 뽑은 유령이 다시 잠겼다")
        #expect(harness.requests(rpc: "shop_state").count == 3)
    }
}
