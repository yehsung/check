import Foundation
import Testing
@testable import check
@testable import CheckCore

/// v0.3.54 뽑기 — 맥·폰이 같이 쓰는 판정과 문구(`GachaRules` · `GachaPullOutcome` · `GachaText` · `GachaRequestIDs`).
///
/// 기대값은 **설계서 표를 손으로 옮긴 값**이다(확률 · 상점가 · 교환가). 서버 응답 모양을 지나 화면 줄(글자)까지 잰다 —
/// "확률 보기" 표가 사용자에게 무엇을 말하는지가 이 기능의 공개 의무다.
@Suite("v0.3.54 뽑기 판정·문구")
struct V0354GachaRulesTests {

    // MARK: - 확률표 → 화면 줄

    /// 맥의 실제 번들 카탈로그 이름으로 그린다(폰은 카드 표 이름 — 둘 다 "강아지" 다. 설계서 표의 "시바"는 id 의 별명이다).
    @Test("확률표 7줄: 서버 순서 · 이름 · % · 상점가(황금은 '뽑기 전용') · 교환가 — 설계서 표 그대로")
    func oddsTableMatchesTheOwnerTable() async throws {
        let state = try Self.shopState()
        let info = try #require(state.gacha)
        let catalog = CheckMascotAssets.catalog
        let rows = GachaRules.oddsRows(info: info, shopRows: state.characters ?? [],
                                       displayName: { catalog.manifest(id: $0)?.displayName })

        let table = rows.map { [$0.characterID, $0.name, $0.percentText, $0.priceText, $0.shardCost.map(String.init) ?? "-"] }
        #expect(table == [
            ["aing_gold", "황금 아잉이", "5%", "뽑기 전용", "-"],
            ["fox", "여우", "24%", "60", "3"],
            ["squirrel", "다람쥐", "24%", "60", "3"],
            ["shiba", "강아지", "14%", "100", "5"],
            ["ghost", "유령", "14%", "100", "5"],
            ["jellyfish", "해파리", "11%", "140", "7"],
            ["robot", "로봇", "8%", "200", "10"],
        ], Comment(rawValue: "\(table)"))
        #expect(rows.reduce(0) { $0 + $1.percent } == 100)
        #expect(rows.first?.isGold == true && rows.first?.isGachaOnly == true && rows.first?.shopPrice == nil)
        // 명목가(1000)가 화면에 새지 않는다 — 뽑기 전용은 값이 아니라 말로 쓴다.
        #expect(!rows.map(\.priceText).contains("1000"))
    }

    @Test("이름은 호출부 → 내장 이름 → id 순서로 — 빈칸을 만들지 않는다")
    func nameFallbacks() {
        #expect(GachaRules.name(for: "fox", displayName: { _ in "여우" }) == "여우")
        // 폰이 아직 금 카드를 모를 때(카드 표에 없음) 내장 이름으로 산다.
        #expect(GachaRules.name(for: "aing_gold", displayName: { _ in nil }) == "황금 아잉이")
        #expect(GachaRules.name(for: "aing", displayName: { _ in "  " }) == "아잉")
        #expect(GachaRules.name(for: "dragon", displayName: { _ in nil }) == "dragon")
    }

    @Test("상점가 칸: 황금은 언제나 '뽑기 전용' · 서버 표식이 참이면 뽑기 전용 · 값이 없으면 '—'")
    func priceTextRules() {
        let info = GachaInfo(price: 50, odds: [GachaOddsEntry(characterID: "aing_gold", percent: 40),
                                               GachaOddsEntry(characterID: "fox", percent: 30),
                                               GachaOddsEntry(characterID: "ghost", percent: 30)])
        // 상점 행이 없다(목록을 못 읽었다) → 황금만 뽑기 전용, 나머지는 값을 모른다.
        let bare = GachaRules.oddsRows(info: info, shopRows: [], displayName: { _ in nil })
        #expect(bare.map(\.priceText) == ["뽑기 전용", "—", "—"])
        // 서버 표식: 황금이 false 로 와도(있을 수 없는 조합) 팔지 않는다 · 다른 캐릭터는 표식대로 갈린다(기준선).
        let rows = GachaRules.oddsRows(info: info, shopRows: [
            ShopCharacterRow(id: "aing_gold", price: 1000, owned: false, gachaOnly: false),
            ShopCharacterRow(id: "fox", price: 60, owned: false, gachaOnly: true),
            ShopCharacterRow(id: "ghost", price: 100, owned: false),
        ], displayName: { _ in nil })
        #expect(rows.map(\.priceText) == ["뽑기 전용", "뽑기 전용", "100"])
        #expect(rows.map(\.shopPrice) == [nil, nil, 100])
        // 상점 행 자체의 "살 수 있나"도 같은 규칙이다.
        #expect(ShopCharacterRow(id: "aing_gold", price: 1000, owned: false, gachaOnly: false).isPurchasable == false)
        #expect(ShopCharacterRow(id: "aing_gold", price: 1000).isPurchasable == false)
        #expect(ShopCharacterRow(id: "fox", price: 60, gachaOnly: true).isPurchasable == false)
        #expect(ShopCharacterRow(id: "fox", price: 60).isPurchasable == true)
        #expect(ShopCharacterRow(id: "fox").isPurchasable == false, "값을 모르면 못 산다")
    }

    @Test("% 글자: 정수는 소수점 없이, 아니면 한 자리")
    func percentText() {
        #expect(GachaText.percent(5) == "5%")
        #expect(GachaText.percent(24) == "24%")
        #expect(GachaText.percent(2.5) == "2.5%")
        #expect(GachaText.percent(33.333) == "33.3%")
        #expect(GachaText.percent(0.04) == "0%")
    }

    // MARK: - 뽑을 수 있나

    @Test("뽑기 버튼: 정보 없음 · 잔량 모름 · 49 · 50 · 51")
    func pullAvailability() throws {
        let info = try #require(try Self.shopState().gacha)
        #expect(GachaRules.pullAvailability(info: nil, rubyBalance: 500) == .unavailable)
        #expect(GachaRules.pullAvailability(info: info, rubyBalance: nil) == .unknownBalance(price: 50))
        #expect(GachaRules.pullAvailability(info: info, rubyBalance: 49) == .short(price: 50, missing: 1))
        #expect(GachaRules.pullAvailability(info: info, rubyBalance: 50) == .ready(price: 50))
        #expect(GachaRules.pullAvailability(info: info, rubyBalance: 51).canPull)
        #expect(GachaRules.pullAvailability(info: info, rubyBalance: 49).canPull == false)
        #expect(GachaRules.pullAvailability(info: info, rubyBalance: nil).canPull == false)
        // 이유 문구(버튼 아래): 모자람은 상점과 같은 말 · 열 수 없음 · 뽑을 수 있으면 없음.
        #expect(GachaText.blockedReason(.short(price: 50, missing: 1)) == "루비 1개 더 필요해요")
        #expect(GachaText.blockedReason(.unavailable) == "지금은 뽑을 수 없어요")
        #expect(GachaText.blockedReason(.ready(price: 50)) == nil)
        #expect(GachaText.pullButton(price: 50) == "뽑기 · 50")
    }

    // MARK: - 결과 분류

    @Test("결과 분류: 새 캐릭터 · 중복 → 조각 · 황금(처음/중복) — 연출 글자까지")
    func resultClassification() throws {
        func outcome(_ json: String) throws -> GachaPullOutcome {
            GachaPullOutcome(response: try V0354GachaWireTests.decoder().decode(GachaPullResponse.self, from: Data(json.utf8)))
        }
        func result(_ json: String) throws -> GachaPullResult {
            guard case .pulled(let r) = try outcome(json) else { throw V0354RulesError("결과가 아니다: \(json)") }
            return r
        }

        let fresh = try result(#"{"status":"ok","character_id":"fox","duplicate":false,"shards_gained":0,"shards":3,"ruby_balance":70}"#)
        #expect(fresh.kind == .newCharacter && fresh.newlyOwnedID == "fox" && fresh.shards == 3 && fresh.rubyBalance == 70)
        #expect(GachaText.headline(for: fresh, name: "여우") == "새 캐릭터: 여우")
        #expect(GachaText.detail(for: fresh, name: "여우") == nil)

        let dup = try result(#"{"status":"ok","character_id":"fox","duplicate":true,"shards_gained":1,"shards":4}"#)
        #expect(dup.kind == .duplicate && dup.newlyOwnedID == nil && dup.shardsGained == 1)
        #expect(GachaText.headline(for: dup, name: "여우") == "이미 있는 여우 → 조각 +1")

        // 서버가 shards_gained 를 안 실어도 규칙대로(중복 = 1).
        let dupNoGain = try result(#"{"status":"ok","character_id":"ghost","duplicate":true}"#)
        #expect(dupNoGain.shardsGained == 1)

        let gold = try result(#"{"status":"ok","character_id":"aing_gold","duplicate":false,"shards_gained":0}"#)
        #expect(gold.kind == .gold && gold.isGold && gold.newlyOwnedID == "aing_gold")
        #expect(GachaText.headline(for: gold, name: "황금 아잉이") == "황금 아잉이!")
        #expect(GachaText.detail(for: gold, name: "황금 아잉이") == "새 캐릭터: 황금 아잉이")

        let goldDup = try result(#"{"status":"ok","character_id":"aing_gold","duplicate":true,"shards_gained":1,"replayed":true}"#)
        #expect(goldDup.kind == .gold && goldDup.isDuplicate && goldDup.newlyOwnedID == nil && goldDup.replayed)
        #expect(GachaText.headline(for: goldDup, name: "황금 아잉이") == "황금 아잉이!")
        #expect(GachaText.detail(for: goldDup, name: "황금 아잉이") == "이미 있는 황금 아잉이 → 조각 +1")

        // 거절·모름 갈래.
        #expect(try outcome(#"{"status":"insufficient","need":50,"have":12}"#) == .insufficient(need: 50, have: 12))
        #expect(try outcome(#"{"status":"needs_update"}"#) == .needsUpdate)
        #expect(try outcome(#"{"status":"not_signed_in"}"#) == .notSignedIn)
        #expect(try outcome(#"{"status":"invalid"}"#) == .invalid)
        #expect(try outcome(#"{"status":"maintenance"}"#) == .failed(status: "maintenance"))
        #expect(try outcome(#"{"status":"ok"}"#) == .failed(status: "ok"), "결과 id 없는 ok 를 결과로 지어냈다")

        #expect(GachaText.notice(for: .insufficient(need: 50, have: 12)) == "루비 38개 더 필요해요")
        #expect(GachaText.notice(for: .needsUpdate) == "앱을 업데이트하면 뽑을 수 있어요")
        #expect(GachaText.notice(for: .unavailable) == "지금은 뽑을 수 없어요")
        #expect(GachaText.notice(for: .failed(status: "x")) == GachaText.pullFailed)
        #expect(GachaText.notice(for: .pulled(fresh)) == nil, "결과는 연출이 말한다 — 안내 줄이 겹치면 안 된다")
    }

    // MARK: - 교환

    @Test("교환 판정: 보유 · 충분 · 모자람 · 조각 모름 · 교환 불가(아잉 · 황금 · 모르는 id)")
    func exchangeAvailability() {
        let costs = ["fox": 3, "robot": 10, "aing_gold": 9, "aing": 1]
        #expect(GachaRules.exchangeAvailability(characterID: "fox", isOwned: true, shards: 0, shardCosts: costs) == .owned)
        #expect(GachaRules.exchangeAvailability(characterID: "fox", isOwned: false, shards: 3, shardCosts: costs)
                == .available(cost: 3))
        #expect(GachaRules.exchangeAvailability(characterID: "fox", isOwned: false, shards: 2, shardCosts: costs)
                == .short(cost: 3, missing: 1))
        #expect(GachaRules.exchangeAvailability(characterID: "robot", isOwned: false, shards: nil, shardCosts: costs)
                == .unknownShards(cost: 10))
        // 서버가 실수로 실어도 아잉·황금은 교환 불가(사장님 규칙) · 표에 없는 id 도.
        #expect(GachaRules.exchangeAvailability(characterID: "aing_gold", isOwned: false, shards: 99, shardCosts: costs)
                == .notExchangeable)
        #expect(GachaRules.exchangeAvailability(characterID: "aing", isOwned: false, shards: 99, shardCosts: costs)
                == .notExchangeable)
        #expect(GachaRules.exchangeAvailability(characterID: "ghost", isOwned: false, shards: 99, shardCosts: costs)
                == .notExchangeable)
        #expect(GachaRules.exchangeAvailability(characterID: "fox", isOwned: false, shards: 9, shardCosts: nil) == .notExchangeable)
        #expect(GachaExchangeAvailability.available(cost: 3).canExchange)
        #expect(GachaExchangeAvailability.short(cost: 3, missing: 1).canExchange == false)
        #expect(GachaExchangeAvailability.owned.canExchange == false)
    }

    @Test("교환 목록: 확률표 순서 · 6종 · 황금 없음 · 보유/조각에 따라 갈린다")
    func exchangeRows() throws {
        let state = try Self.shopState()
        let info = try #require(state.gacha)   // 조각 3개
        let owned: Set<String> = ["aing", "squirrel"]
        let rows = GachaRules.exchangeRows(info: info, ownedIDs: owned,
                                           displayName: { CheckMascotAssets.catalog.manifest(id: $0)?.displayName })
        #expect(rows.map(\.characterID) == ["fox", "squirrel", "shiba", "ghost", "jellyfish", "robot"])
        #expect(rows.map(\.availability) == [
            .available(cost: 3), .owned, .short(cost: 5, missing: 2), .short(cost: 5, missing: 2),
            .short(cost: 7, missing: 4), .short(cost: 10, missing: 7),
        ])
        #expect(rows.map(\.name) == ["여우", "다람쥐", "강아지", "유령", "해파리", "로봇"])
    }

    @Test("교환 결과 문구")
    func exchangeNotices() {
        #expect(GachaText.notice(for: .exchanged(characterID: "fox", shards: 0, cost: 3, replayed: false), name: "여우")
                == "교환했어요: 여우")
        #expect(GachaText.notice(for: .insufficientShards(need: 7, have: 2), name: "해파리") == "조각 5개 더 필요해요")
        #expect(GachaText.notice(for: .insufficientShards(need: nil, have: nil), name: "해파리") == "조각이 모자라요")
        #expect(GachaText.notice(for: .alreadyOwned, name: "여우") == "이미 갖고 있어요")
        #expect(GachaText.notice(for: .notExchangeable, name: "황금 아잉이") == "교환할 수 없는 캐릭터예요")
        #expect(GachaExchangeOutcome(response: GachaExchangeResponse(status: .ok), requestedID: "ghost")
                == .exchanged(characterID: "ghost", shards: nil, cost: nil, replayed: false))
    }

    // MARK: - request_id 수명

    @Test("request_id: 같은 동작은 답을 받을 때까지 같은 id · 답을 받으면 새 id · 동작마다 칸이 따로")
    func requestIDLifecycle() {
        var ids = GachaRequestIDs()
        var made = 0
        let make: () -> UUID = { made += 1; return UUID() }

        let first = ids.pullID(make: make)
        // 결과를 모르는 실패 뒤 다시 누름 → 같은 id(서버가 이미 처리했으면 replayed 로 처음 결과가 온다).
        #expect(ids.pullID(make: make) == first)
        #expect(made == 1)
        // 옛 id 로 settle 해도(늦게 온 답) 지금 쥔 것은 안 버린다.
        ids.settlePull(UUID())
        #expect(ids.pull == first)
        // 답을 받았다 → 버린다 → 다음 누름은 새 id.
        ids.settlePull(first)
        let second = ids.pullID(make: make)
        #expect(second != first && made == 2)

        // 교환은 캐릭터마다 따로 · 뽑기와도 따로.
        let fox = ids.exchangeID(for: "fox", make: make)
        let robot = ids.exchangeID(for: "robot", make: make)
        #expect(fox != robot && fox != second)
        #expect(ids.exchangeID(for: "fox", make: make) == fox)
        ids.settleExchange(fox, for: "fox")
        #expect(ids.exchange["fox"] == nil && ids.exchange["robot"] == robot && ids.pull == second)

        ids.reset()
        #expect(ids == GachaRequestIDs())
    }

    // MARK: - 말투

    @Test("문구는 해요체 · '도박/베팅' 금지 · 뽑기/조각/확률 어휘")
    func vocabulary() {
        let sentences = [
            GachaText.oddsFootnote, GachaText.needsUpdate, GachaText.unavailable, GachaText.notSignedIn,
            GachaText.connection, GachaText.pullFailed, GachaText.exchangeFailed, GachaText.alreadyOwned,
            GachaText.notExchangeable, GachaText.shardShortfall(missing: 2),
            GachaText.notice(for: .needsUpdate), GachaText.notice(for: .unavailable, name: "여우"), GachaText.gachaOnlyHint,
        ].compactMap { $0 }
        for sentence in sentences {
            #expect(sentence.hasSuffix("요"), Comment(rawValue: "해요체가 아니다: \(sentence)"))
        }
        let everything = sentences + [
            GachaText.title, GachaText.pullButton, GachaText.oddsButton, GachaText.oddsTitle, GachaText.gachaOnly,
            GachaText.owned, GachaText.exchangeButton, GachaText.exchangeTitle, GachaText.goldHeadline,
        ]
        for text in everything {
            #expect(!text.contains("도박") && !text.contains("베팅") && !text.contains("확률형"), Comment(rawValue: text))
        }
        #expect(GachaText.title.contains("뽑기") && GachaText.oddsButton.contains("확률"))
        // 같은 일을 하는 확성기·상점 문구와 겹치지 않는다(뽑기만의 문장).
        #expect(GachaText.unavailable != MegaphoneText.unavailable)
        #expect(GachaText.needsUpdate != WorkTimerStore.needsUpdateNotice)
    }

    // MARK: - 헬퍼

    /// 스텁 서버의 2 응답을 **서비스 디코더**로 읽은 상점 상태(설계서 표 그대로).
    static func shopState() throws -> ShopStateResponse {
        let body = #"{"ruby_balance":120,"characters":"# + V0354CoreStub.shopRows(protocolVersion: 2)
            + #","gacha":"# + V0354CoreStub.gachaJSON + "}"
        return try V0354GachaWireTests.decoder().decode(ShopStateResponse.self, from: Data(body.utf8))
    }
}

struct V0354RulesError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
