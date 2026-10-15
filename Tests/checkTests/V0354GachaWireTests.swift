import Foundation
import Testing
@testable import check
@testable import CheckCore

/// v0.3.54 뽑기 — 전선(설계서 Wire contract)을 **서비스의 진짜 디코더**로 잰다.
///
/// 손으로 만든 `JSONDecoder()` 로 재면 서비스의 snake→camel 전략과 `characterId`/`requestId` 키 이름을 안 지난다 —
/// 그래서 응답은 전부 스텁 서버 → `SupabaseWorkService` → 모델 순서로 받는다. 본문은 JSON 으로 열어 키 집합·값을 잰다
/// (PostgREST 는 본문의 키 집합으로 함수를 고른다 — 키 하나가 다르면 404 다).
@Suite("v0.3.54 뽑기 전선")
struct V0354GachaWireTests {

    // MARK: - shop_state.gacha

    @Test("shop_state: gacha 객체 · gacha_only 를 서비스 디코더로 읽는다 — 순서·교환표 키(aing_gold 포함)가 그대로다")
    func shopStateCarriesGacha() async throws {
        let host = Self.host("shop")
        GomokuStubProtocol.register(host: host, handler: V0354CoreStub.shopHandler)
        let service = Self.service(host: host)

        let state = try await service.fetchShopState(accessToken: "t", protocolVersion: ShopWire.goldProtocol)
        let gacha = try #require(state.gacha, "2 를 보냈는데 gacha 가 없다")
        #expect(gacha.price == 50)
        #expect(gacha.shards == 3)
        #expect(gacha.odds?.map(\.characterID) == ["aing_gold", "fox", "squirrel", "shiba", "ghost", "jellyfish", "robot"],
                "서버 순서가 아니다 — 정렬하거나 키 이름(character_id)을 못 읽었다")
        #expect(gacha.odds?.map(\.percent) == [5, 24, 24, 14, 14, 11, 8])
        // AMENDMENT 1: 일곱 값(황금 20 포함). `[String: T]` 는 키 변환을 안 타서 `aing_gold` 키가 그대로 남는다.
        #expect(gacha.shardCosts == ["aing_gold": 20, "fox": 2, "squirrel": 2, "shiba": 4, "ghost": 4, "jellyfish": 5, "robot": 8])
        #expect(gacha.totalPercent == 100 && gacha.hasCompleteOdds && gacha.isUsable)

        let rows = try #require(state.characters)
        #expect(rows.first { $0.id == "aing_gold" }?.gachaOnly == true)
        #expect(rows.first { $0.id == "shiba" }?.gachaOnly == false)
        #expect(rows.first { $0.id == "fox" }?.gachaOnly == nil, "키를 안 실은 줄이 nil 이 아니다")
        #expect(rows.filter(\.isPurchasable).map(\.id).contains("aing_gold") == false)

        // 기준선이 갈린다: 1 을 보내면 서버가 gacha 키를 아예 안 싣는다 → nil(뽑기 화면을 숨기는 신호).
        let old = try await service.fetchShopState(accessToken: "t", protocolVersion: ShopWire.robotProtocol)
        #expect(old.gacha == nil)
        #expect(old.characters?.contains { $0.id == "aing_gold" } == false)
        #expect(old.rubyBalance == 120, "gacha 가 없는 응답에서 다른 칸까지 못 읽었다")
    }

    /// ★ `gacha` 한 칸이 깨져도 **상점 전체**(잔량·가격·보유)는 산다. 그 대가로 뽑기는 닫힌다(`isUsable == false`).
    @Test("gacha 가 깨져 와도 상점은 산다 — 문자열 · null · 깨진 확률 행 · 숫자가 아닌 교환값")
    func brokenGachaNeverKillsTheShop() throws {
        let decoder = Self.decoder()
        func decode(_ gacha: String) throws -> ShopStateResponse {
            try decoder.decode(ShopStateResponse.self, from: Data(
                (#"{"ruby_balance":77,"characters":[{"id":"fox","price":60,"owned":false}],"gacha":"# + gacha + "}").utf8))
        }

        // ① 객체가 아니다 → 아무것도 모르는 정보(뽑기 닫힘) · 잔량은 산다.
        let string = try decode(#""broken""#)
        #expect(string.rubyBalance == 77 && string.characters?.count == 1)
        #expect(string.gacha == GachaInfo() && string.gacha?.isUsable == false)

        // ② null → 키가 없는 것과 같다.
        let null = try decode("null")
        #expect(null.gacha == nil && null.rubyBalance == 77)

        // ③ 확률 행 하나가 깨졌다(percent 가 글자) → 그 행만 버린다 → 표가 불완전해져(95%) 뽑기를 닫는다.
        let brokenRow = try decode(#"""
        {"price":50,"shards":0,"odds":[{"character_id":"aing_gold","percent":"5"},{"character_id":"fox","percent":95}],
         "shard_costs":{"fox":3}}
        """#)
        let info = try #require(brokenRow.gacha)
        #expect(info.odds == [GachaOddsEntry(characterID: "fox", percent: 95)])
        #expect(info.hasCompleteOdds == false && info.isUsable == false, "공개한 확률이 불완전한데 뽑기가 열린다")
        #expect(GachaRules.pullAvailability(info: info, rubyBalance: 500) == .unavailable)

        // ④ 소수 확률(2.5)은 행을 살린다(정수만 받으면 이 행이 사라지고 뽑기가 닫힌다).
        let fractional = try #require(try decode(#"""
        {"price":50,"odds":[{"character_id":"aing_gold","percent":2.5},{"character_id":"fox","percent":97.5}]}
        """#).gacha)
        #expect(fractional.hasCompleteOdds && fractional.isUsable)

        // ⑤ 교환값 하나가 숫자가 아니다 → 그 값만 버린다. 키는 id 그대로다(snake→camel 변환을 타지 않는다).
        let costs = try #require(try decode(#"""
        {"price":50,"odds":[{"character_id":"fox","percent":100}],"shard_costs":{"fox":2,"ghost":"4","aing_gold":20,"jelly_fish":5}}
        """#).gacha?.shardCosts)
        #expect(costs == ["fox": 2, "aing_gold": 20, "jelly_fish": 5], Comment(rawValue: "\(costs)"))

        // ⑥ 값이 없다 → 뽑기 닫힘(값을 지어내지 않는다).
        let noPrice = try #require(try decode(#"{"odds":[{"character_id":"fox","percent":100}]}"#).gacha)
        #expect(noPrice.isUsable == false)
        #expect(GachaRules.pullAvailability(info: noPrice, rubyBalance: 500) == .unavailable)
    }

    // MARK: - 응답 어휘

    @Test("gacha_pull 응답: 모든 status · 모르는 status 는 unknown · status 없으면 throw · 칸 모양이 틀려도 throw 하지 않는다")
    func pullResponseVocabulary() throws {
        let decoder = Self.decoder()
        func decode(_ text: String) throws -> GachaPullResponse {
            try decoder.decode(GachaPullResponse.self, from: Data(text.utf8))
        }
        let ok = try decode(#"""
        {"status":"ok","character_id":"fox","duplicate":true,"shards_gained":1,"shards":4,"ruby_balance":70,
         "price":50,"request_id":"0b6f5f0e-1d2c-4b8a-9c3e-2f1a0b9c8d7e","replayed":false}
        """#)
        #expect(ok.status == .ok && ok.characterID == "fox" && ok.duplicate == true && ok.shardsGained == 1)
        #expect(ok.shards == 4 && ok.rubyBalance == 70 && ok.price == 50 && ok.replayed == false)
        #expect(ok.requestID == "0b6f5f0e-1d2c-4b8a-9c3e-2f1a0b9c8d7e")

        #expect(try decode(#"{"status":"not_signed_in"}"#).status == .notSignedIn)
        #expect(try decode(#"{"status":"needs_update"}"#).status == .needsUpdate)
        #expect(try decode(#"{"status":"invalid"}"#).status == .invalid)
        let short = try decode(#"{"status":"insufficient","need":50,"have":49}"#)
        #expect(short.status == .insufficient && short.need == 50 && short.have == 49)
        #expect(try decode(#"{"status":"maintenance"}"#).status == .unknown("maintenance"))
        // 원문 왕복(진단 · 로그용) — 알려진 어휘가 모르는 어휘로 새지 않는다.
        for raw in ["ok", "not_signed_in", "needs_update", "insufficient", "invalid", "maintenance"] {
            #expect(GachaPullStatus(raw: raw).raw == raw)
        }

        // status 가 없으면 결과를 모른다 → throw(호출부는 같은 request_id 로 다시 묻는다).
        #expect(throws: (any Error).self) { try decode(#"{"character_id":"fox"}"#) }
        // 칸 하나의 모양이 틀려도(shards 가 글자) 나머지는 산다 — "깎였는데 결과를 영영 못 읽는" 응답을 만들지 않는다.
        let odd = try decode(#"{"status":"ok","character_id":"ghost","shards":"many","ruby_balance":20}"#)
        #expect(odd.status == .ok && odd.characterID == "ghost" && odd.shards == nil && odd.rubyBalance == 20)
    }

    @Test("gacha_exchange 응답: 모든 status · 모르는 status 는 unknown")
    func exchangeResponseVocabulary() throws {
        let decoder = Self.decoder()
        func decode(_ text: String) throws -> GachaExchangeResponse {
            try decoder.decode(GachaExchangeResponse.self, from: Data(text.utf8))
        }
        let ok = try decode(#"{"status":"ok","character_id":"robot","shards":2,"cost":8,"request_id":"x","replayed":true}"#)
        #expect(ok.status == .ok && ok.characterID == "robot" && ok.shards == 2 && ok.cost == 8 && ok.replayed == true)
        #expect(try decode(#"{"status":"not_signed_in"}"#).status == .notSignedIn)
        #expect(try decode(#"{"status":"needs_update"}"#).status == .needsUpdate)
        #expect(try decode(#"{"status":"not_exchangeable"}"#).status == .notExchangeable)
        #expect(try decode(#"{"status":"already_owned"}"#).status == .alreadyOwned)
        let short = try decode(#"{"status":"insufficient_shards","character_id":"aing_gold","need":20,"have":19}"#)
        #expect(short.status == .insufficientShards && short.need == 20 && short.have == 19 && short.characterID == "aing_gold")
        #expect(try decode(#"{"status":"nope"}"#).status == .unknown("nope"))
        for raw in ["ok", "not_signed_in", "needs_update", "not_exchangeable", "already_owned", "insufficient_shards", "nope"] {
            #expect(GachaExchangeStatus(raw: raw).raw == raw)
        }
    }

    // MARK: - 서비스 — 본문 · 경로 · 재요청

    @Test("gachaPull: /rpc/gacha_pull 에 {p_protocol, p_request_id} 두 키만 · uuid 는 소문자 · 응답을 결과로 옮긴다")
    func pullRequestBody() async throws {
        let host = Self.host("pull")
        GomokuStubProtocol.register(host: host, handler: Self.gachaHandler())
        let service = Self.service(host: host)
        let id = try #require(UUID(uuidString: "0B6F5F0E-1D2C-4B8A-9C3E-2F1A0B9C8D7E"))

        let response = try await service.gachaPull(accessToken: "t", protocolVersion: 2, requestID: id)
        let call = try #require(GomokuStubProtocol.calls(host: host, rpc: "gacha_pull").last)
        #expect(Set(call.json.keys) == ["p_protocol", "p_request_id"], Comment(rawValue: call.body))
        #expect(call.json["p_protocol"] as? Int == 2)
        #expect(call.json["p_request_id"] as? String == "0b6f5f0e-1d2c-4b8a-9c3e-2f1a0b9c8d7e")

        guard case .pulled(let result) = GachaPullOutcome(response: response) else {
            Issue.record("ok 응답이 결과가 아니다: \(response)")
            return
        }
        #expect(result.characterID == "fox" && result.kind == .newCharacter && result.rubyBalance == 70)
        #expect(result.replayed == false)
    }

    /// 같은 request_id 를 다시 보내면 서버는 처음 결과를 `replayed: true` 로 돌려준다 — 잔량이 그대로다(두 번 깎이지 않았다).
    /// 기준선: 다른 id 는 새로 뽑히고 잔량이 한 번 더 준다.
    @Test("같은 request_id 재요청은 replayed — 잔량이 그대로다 · 다른 id 는 새로 깎인다")
    func replaySameRequestID() async throws {
        let host = Self.host("replay")
        GomokuStubProtocol.register(host: host, handler: Self.gachaHandler())
        let service = Self.service(host: host)
        let first = UUID()

        let a = try await service.gachaPull(accessToken: "t", protocolVersion: 2, requestID: first)
        let b = try await service.gachaPull(accessToken: "t", protocolVersion: 2, requestID: first)
        let c = try await service.gachaPull(accessToken: "t", protocolVersion: 2, requestID: UUID())
        #expect(a.replayed == false && a.rubyBalance == 70)
        #expect(b.replayed == true && b.rubyBalance == 70, "같은 id 인데 잔량이 또 줄었다")
        #expect(c.replayed == false && c.rubyBalance == 20)
        let ids = GomokuStubProtocol.calls(host: host, rpc: "gacha_pull").compactMap { $0.json["p_request_id"] as? String }
        #expect(ids.count == 3 && ids[0] == ids[1] && ids[1] != ids[2])
    }

    @Test("gachaExchange: /rpc/gacha_exchange 에 {p_character_id, p_protocol, p_request_id} 세 키만")
    func exchangeRequestBody() async throws {
        let host = Self.host("exchange")
        GomokuStubProtocol.register(host: host, handler: Self.gachaHandler())
        let service = Self.service(host: host)
        let id = UUID()

        let response = try await service.gachaExchange(accessToken: "t", characterID: "jellyfish",
                                                       protocolVersion: 2, requestID: id)
        let call = try #require(GomokuStubProtocol.calls(host: host, rpc: "gacha_exchange").last)
        #expect(Set(call.json.keys) == ["p_character_id", "p_protocol", "p_request_id"], Comment(rawValue: call.body))
        #expect(call.json["p_character_id"] as? String == "jellyfish")
        #expect(call.json["p_protocol"] as? Int == 2)
        #expect(call.json["p_request_id"] as? String == id.uuidString.lowercased())
        #expect(GachaExchangeOutcome(response: response, requestedID: "jellyfish")
                == .exchanged(characterID: "jellyfish", shards: 0, cost: 5, replayed: false))

        // AMENDMENT 1: 황금도 같은 RPC · 같은 세 키로 교환된다(클라가 막지 않는다) — 서버 값(20)이 결과에 실린다.
        let goldID = UUID()
        let gold = try await service.gachaExchange(accessToken: "t", characterID: CharacterCatalog.goldAingID,
                                                   protocolVersion: 2, requestID: goldID)
        let goldCall = try #require(GomokuStubProtocol.calls(host: host, rpc: "gacha_exchange").last)
        #expect(Set(goldCall.json.keys) == ["p_character_id", "p_protocol", "p_request_id"], Comment(rawValue: goldCall.body))
        #expect(goldCall.json["p_character_id"] as? String == "aing_gold")
        #expect(GachaExchangeOutcome(response: gold, requestedID: "aing_gold")
                == .exchanged(characterID: "aing_gold", shards: 0, cost: 20, replayed: false))
    }

    /// throw 로 온 실패의 갈래: 함수 없음(PGRST202) = 아무것도 안 돌았다 → `.unavailable`(id 를 버려도 된다).
    /// 5xx = 결과를 모른다 → nil(id 를 쥔 채 다시 묻는다). 둘을 한 갈래로 접으면 이중 과금이나 영구 정지가 생긴다.
    @Test("함수 없음(404 PGRST202)은 unavailable · 5xx 는 결과를 모름(nil)")
    func thrownFailuresSplit() async throws {
        let missingHost = Self.host("missing")
        GomokuStubProtocol.register(host: missingHost) { rpc, _, _ in
            GomokuStubProtocol.Reply(status: 404, body: #"{"code":"PGRST202","message":"Could not find the function public."#
                                     + rpc + #" in the schema cache"}"#)
        }
        let sickHost = Self.host("sick")
        GomokuStubProtocol.register(host: sickHost) { _, _, _ in
            GomokuStubProtocol.Reply(status: 503, body: #"{"message":"upstream connect error"}"#)
        }

        do {
            _ = try await Self.service(host: missingHost).gachaPull(accessToken: "t", protocolVersion: 2, requestID: UUID())
            Issue.record("404 인데 throw 하지 않았다")
        } catch {
            #expect(GachaPullOutcome(error: error) == .unavailable, "\(error)")
        }
        do {
            _ = try await Self.service(host: missingHost).gachaExchange(accessToken: "t", characterID: "fox",
                                                                          protocolVersion: 2, requestID: UUID())
            Issue.record("404 인데 throw 하지 않았다")
        } catch {
            #expect(GachaExchangeOutcome(error: error) == .unavailable, "\(error)")
        }
        do {
            _ = try await Self.service(host: sickHost).gachaPull(accessToken: "t", protocolVersion: 2, requestID: UUID())
            Issue.record("503 인데 throw 하지 않았다")
        } catch {
            #expect(GachaPullOutcome(error: error) == nil, "결과를 모르는 실패를 '안 돌았다'로 접었다: \(error)")
            #expect(GachaExchangeOutcome(error: error) == nil)
        }
        // 서비스 오류가 아닌 것(오프라인 등)도 결과를 모른다.
        #expect(GachaPullOutcome(error: URLError(.notConnectedToInternet)) == nil)
    }

    // MARK: - 헬퍼

    /// 뽑기 스텁: 잔량 120 에서 시작해 **새 request_id 마다** 50 을 깎고, 본 id 는 처음 결과를 replayed 로 돌려준다.
    /// 장부는 **등록마다 새로** 만든다(테스트마다 고유 호스트 · 고유 장부 — 병렬 스위트가 서로의 잔량을 먹지 않는다).
    static func gachaHandler() -> GomokuStubProtocol.Handler {
        let ledger = V0354GachaLedger()
        return { rpc, body, _ in
            let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
            let requestID = json["p_request_id"] as? String ?? ""
            switch rpc {
            case "gacha_pull":
                let (balance, replayed) = ledger.charge(requestID: requestID)
                return GomokuStubProtocol.Reply(body: #"{"status":"ok","character_id":"fox","duplicate":false,"shards_gained":0,"#
                                                + #""shards":3,"ruby_balance":\#(balance),"price":50,"request_id":"\#(requestID)","#
                                                + #""replayed":\#(replayed)}"#)
            case "gacha_exchange":
                // 교환값은 서버 확률표(AMENDMENT 1) 그대로 — 보낸 id 의 값을 cost 로 싣는다.
                let id = json["p_character_id"] as? String ?? ""
                let cost = ["aing_gold": 20, "fox": 2, "squirrel": 2, "shiba": 4, "ghost": 4, "jellyfish": 5, "robot": 8][id] ?? 0
                return GomokuStubProtocol.Reply(body: #"{"status":"ok","character_id":"\#(id)","shards":0,"cost":\#(cost),"#
                                                + #""request_id":"\#(requestID)","replayed":false}"#)
            default:
                return nil
            }
        }
    }

    static func host(_ label: String) -> String {
        "v0354-wire-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    }

    static func service(host: String) -> SupabaseWorkService {
        SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                            session: GomokuStubProtocol.session())
    }

    /// 서비스와 같은 전략(snake → camel)의 디코더. 서비스 인스턴스의 것은 액터 격리라 꺼내 쓸 수 없어 한 줄을 다시 적는다 —
    /// 그래서 이 파일의 **서비스 경로 테스트**(fetchShopState · gachaPull · gachaExchange)가 진짜 디코더를 따로 한 번 지난다.
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

/// 뽑기 스텁의 장부(request_id → 그때의 잔량). 등록 하나에 하나(`gachaHandler()`).
final class V0354GachaLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String: Int] = [:]
    private var balance = 120

    /// (뽑은 뒤 잔량, 재요청인가). 본 id 면 처음 잔량을 그대로 돌려준다(서버 `gacha_log` 의 unique(user, request_id) 와 같은 뜻).
    func charge(requestID: String) -> (Int, Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let known = seen[requestID] { return (known, true) }
        balance -= 50
        seen[requestID] = balance
        return (balance, false)
    }
}
