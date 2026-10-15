import Foundation

// MARK: - 캐릭터 뽑기 (v0.3.54 맥 · 1.0.8 폰)
//
// 서버 정본은 `supabase/migrations/20261015121000_gacha.sql` 이다. 요점만(설계서 Wire contract):
//   · 1회 50루비(`gacha_price()`). 결과는 서버 `gacha_pool` 표(합 100%)에서 뽑는다 — 클라는 확률을 **보여 주기만** 한다.
//   · 처음 나온 캐릭터 → 소유(acquired_via='gacha'). 이미 가진 캐릭터(황금 포함) → 조각 1개.
//   · 조각으로 일곱 캐릭터를 교환한다(`shard_costs` — 황금 아잉이 20 포함, 사장님 정정 2026-10-15 AMENDMENT 1).
//     아잉(무료 기본)만 교환 불가. 황금 아잉이는 **루비로는 안 판다**(뽑기 · 조각 교환으로만).
//     교환값은 서버가 준 것만 쓴다 — 클라에 숫자를 적지 않는다(값이 바뀌어도 앱을 다시 낼 필요가 없게).
//   · `shop_state(p_protocol >= 2)` 만 `gacha` 키를 싣는다. 없으면 클라는 뽑기 화면을 통째로 숨긴다.
//   · `gacha_pull`·`gacha_exchange` 는 `p_protocol >= 2` 가 아니면 `needs_update`(루비·조각 안 움직임).
//   · 같은 `(사용자, request_id)` 를 다시 보내면 **처음 결과를 `replayed: true` 로** 돌려준다 — 두 번 깎지 않는다.
//
// ── 이 파일이 지키는 것 ──
// ① **이중 과금이 원리적으로 없다.** 사용자 동작 한 번에 request_id 를 **하나** 만들고(`GachaRequestIDs`), 결과를 모르는 실패
//    (오프라인 · 5xx · 응답 해석 실패)에서는 그 id 를 **쥔 채** 다시 묻는다. id 를 버리는 것은 서버가 답을 준 뒤 · 함수가 없다는
//    것이 확실할 때뿐이다(확성기 `MegaphoneStore` 와 같은 규약).
// ② **루비·조각은 서버가 말한다.** 응답이 실어 준 잔량·조각 수로만 화면을 고친다 — 클라가 스스로 빼거나 더하지 않는다.
// ③ **맥과 폰이 한 벌이다.** 판정(뽑을 수 있나 · 교환할 수 있나 · 결과 분류)과 문구는 여기서 만들고 화면은 그리기만 한다.
// ④ **확률은 서버가 준 표 그대로** 보인다(순서까지). 표가 불완전하면(합 ≠ 100%) 뽑기를 열지 않는다 — 공개한 확률과 실제
//    확률이 다를 수 있는 상태에서 루비를 받지 않는다.

// MARK: 전선 모양 — shop_state.gacha

/// `shop_state.gacha` — `{price, shards, odds: [{character_id, percent}], shard_costs: {id: n}}`.
///
/// ★ **이 타입의 디코드는 throw 하지 않는다.** `ShopStateResponse` 안에 들어 있으므로 여기서 한 칸이 깨지면 **상점 전체**
///   (잔량·가격·보유)가 죽는다. 모양이 틀린 칸은 nil 로, 깨진 확률 행·교환값은 그 행만 버린다. 그 대가로 화면은
///   `isUsable` 로 "뽑기를 열 만큼 아는가"를 묻는다(가격 + 완전한 확률표).
package struct GachaInfo: Decodable, Equatable, Sendable {
    /// 1회 값(루비). 서버 `gacha_price()` — 클라가 50 을 다시 적지 않는다.
    package var price: Int?
    /// 내 조각 수.
    package var shards: Int?
    /// 결과 확률표 — **서버 순서 그대로**(정렬하지 않는다).
    package var odds: [GachaOddsEntry]?
    /// 조각 교환값(id → 조각 수). 여기 없는 id 는 교환할 수 없다(아잉 · 모르는 id). 황금 아잉이도 여기 있다(20).
    package var shardCosts: [String: Int]?

    package init(price: Int? = nil, shards: Int? = nil, odds: [GachaOddsEntry]? = nil, shardCosts: [String: Int]? = nil) {
        self.price = price
        self.shards = shards
        self.odds = odds
        self.shardCosts = shardCosts
    }

    package enum CodingKeys: String, CodingKey {
        case price, shards, odds, shardCosts
    }

    package init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            // `"gacha": "…"` 처럼 객체가 아니면 아무것도 모르는 정보로 둔다(상점은 산다 · 뽑기는 숨는다).
            self.init()
            return
        }
        // `[String: T]` 는 키 변환 전략(snake → camel)을 **타지 않는다**(실측 — 키가 id 그대로 남는다. 테스트가 `aing_gold`
        // 키로 못 박는다). 값 하나가 숫자가 아니어도 나머지는 살린다.
        let costs = container.lossy([String: GachaLossyInt].self, forKey: .shardCosts)?.compactMapValues(\.value)
        self.init(price: container.lossy(Int.self, forKey: .price),
                  shards: container.lossy(Int.self, forKey: .shards),
                  odds: Self.lossyOdds(container),
                  shardCosts: costs)
    }

    private static func lossyOdds(_ container: KeyedDecodingContainer<CodingKeys>) -> [GachaOddsEntry]? {
        guard container.contains(.odds), var list = try? container.nestedUnkeyedContainer(forKey: .odds) else { return nil }
        var rows: [GachaOddsEntry] = []
        while !list.isAtEnd {
            if let row = try? list.decode(GachaOddsEntry.self) {
                rows.append(row)
            } else if (try? list.decode(GachaDiscard.self)) == nil {
                // 버리기도 못 하면(이론상 없음) 무한 반복 대신 멈춘다.
                break
            }
        }
        return rows
    }

    /// 확률표의 합(%). 표가 없으면 0.
    package var totalPercent: Double {
        (odds ?? []).reduce(0) { $0 + $1.percent }
    }

    /// 확률표가 완전한가 — 행이 있고 합이 100% 다(부동소수 오차 0.01 이내). 깨진 행을 버렸으면 거짓이 된다.
    package var hasCompleteOdds: Bool {
        guard let odds, !odds.isEmpty else { return false }
        return abs(totalPercent - 100) < 0.01
    }

    /// 화면이 뽑기를 **열 만큼** 아는가: 값과 완전한 확률표. 하나라도 모르면 뽑기 카드를 숨긴다
    /// (값을 지어내지 않는다 · 공개하지 못한 확률로 루비를 받지 않는다).
    package var isUsable: Bool {
        price != nil && hasCompleteOdds
    }
}

/// 확률표 한 줄. `percent` 는 서버가 정수로 주지만 소수로 받는다 — 정수만 받게 두면 `2.5` 하나에 이 행이 사라지고
/// 표가 불완전해진다(그러면 뽑기가 닫힌다). 소수로 받으면 표가 그대로 산다.
package struct GachaOddsEntry: Decodable, Equatable, Sendable {
    package let characterID: String
    package let percent: Double

    package init(characterID: String, percent: Double) {
        self.characterID = characterID
        self.percent = percent
    }

    package enum CodingKeys: String, CodingKey {
        // 서비스 디코더가 `character_id` → `characterId` 로 바꾼 뒤 찾는다.
        case characterID = "characterId"
        case percent
    }
}

// MARK: 전선 모양 — RPC 본문

/// `gacha_pull(p_protocol, p_request_id)` 본문. **키 둘을 언제나 싣는다** — 서버 인자는 둘 다 DEFAULT 지만 키 집합이 흔들리면
/// PostgREST 가 다른 함수를 찾는다. request_id 는 uuid 라 `UUID` 로만 받는다(아무 문자열이나 실으면 서버가 400 으로 거절한다).
package struct GachaPullRequest: Encodable, Equatable, Sendable {
    package let pProtocol: Int
    package let pRequestId: String

    package init(protocolVersion: Int, requestID: UUID) {
        pProtocol = protocolVersion
        pRequestId = requestID.uuidString.lowercased()
    }
}

/// `gacha_exchange(p_character_id, p_protocol, p_request_id)` 본문. 키 셋을 언제나 싣는다.
package struct GachaExchangeRequest: Encodable, Equatable, Sendable {
    package let pCharacterId: String
    package let pProtocol: Int
    package let pRequestId: String

    package init(characterID: String, protocolVersion: Int, requestID: UUID) {
        pCharacterId = characterID
        pProtocol = protocolVersion
        pRequestId = requestID.uuidString.lowercased()
    }
}

// MARK: 전선 모양 — 응답

/// `gacha_pull` 의 status 어휘. 모르는 값은 `.unknown(원문)` — 새 어휘가 생겨도 디코드가 죽지 않는다.
package enum GachaPullStatus: Equatable, Sendable, Decodable {
    case ok
    case notSignedIn
    case needsUpdate
    case insufficient
    case invalid
    case unknown(String)

    package init(raw: String) {
        switch raw {
        case "ok": self = .ok
        case "not_signed_in": self = .notSignedIn
        case "needs_update": self = .needsUpdate
        case "insufficient": self = .insufficient
        case "invalid": self = .invalid
        default: self = .unknown(raw)
        }
    }

    package var raw: String {
        switch self {
        case .ok: return "ok"
        case .notSignedIn: return "not_signed_in"
        case .needsUpdate: return "needs_update"
        case .insufficient: return "insufficient"
        case .invalid: return "invalid"
        case .unknown(let raw): return raw
        }
    }

    package init(from decoder: Decoder) throws {
        self.init(raw: try decoder.singleValueContainer().decode(String.self))
    }
}

/// `gacha_exchange` 의 status 어휘. 모르는 값은 `.unknown(원문)`.
package enum GachaExchangeStatus: Equatable, Sendable, Decodable {
    case ok
    case notSignedIn
    case needsUpdate
    case notExchangeable
    case alreadyOwned
    case insufficientShards
    case unknown(String)

    package init(raw: String) {
        switch raw {
        case "ok": self = .ok
        case "not_signed_in": self = .notSignedIn
        case "needs_update": self = .needsUpdate
        case "not_exchangeable": self = .notExchangeable
        case "already_owned": self = .alreadyOwned
        case "insufficient_shards": self = .insufficientShards
        default: self = .unknown(raw)
        }
    }

    package var raw: String {
        switch self {
        case .ok: return "ok"
        case .notSignedIn: return "not_signed_in"
        case .needsUpdate: return "needs_update"
        case .notExchangeable: return "not_exchangeable"
        case .alreadyOwned: return "already_owned"
        case .insufficientShards: return "insufficient_shards"
        case .unknown(let raw): return raw
        }
    }

    package init(from decoder: Decoder) throws {
        self.init(raw: try decoder.singleValueContainer().decode(String.self))
    }
}

/// `gacha_pull` 응답. `status` 만 필수다 — 없으면 결과를 모르는 응답이라 throw 하고, 호출부는 같은 request_id 로 다시 묻는다
/// (서버가 처리했으면 `replayed` 로 같은 결과가 오고 두 번 깎이지 않는다). 나머지 칸은 모양이 틀려도 nil 로 삼킨다 —
/// 한 칸 때문에 "루비는 빠졌는데 결과를 영영 못 읽는" 응답을 만들지 않는다.
package struct GachaPullResponse: Decodable, Equatable, Sendable {
    package let status: GachaPullStatus
    package var characterID: String?
    package var duplicate: Bool?
    /// 이번에 얻은 조각(0 또는 1).
    package var shardsGained: Int?
    /// 뽑은 뒤 내 조각 수.
    package var shards: Int?
    /// 뽑은 뒤 루비 잔량. **클라가 스스로 빼지 않는다.**
    package var rubyBalance: Int?
    package var price: Int?
    package var requestID: String?
    /// 같은 request_id 의 두 번째 호출이라 서버가 처음 결과를 돌려줬다(새로 깎지 않았다).
    package var replayed: Bool?
    /// insufficient 일 때: 필요한 양 · 가진 양.
    package var need: Int?
    package var have: Int?

    package init(status: GachaPullStatus, characterID: String? = nil, duplicate: Bool? = nil, shardsGained: Int? = nil,
                 shards: Int? = nil, rubyBalance: Int? = nil, price: Int? = nil, requestID: String? = nil,
                 replayed: Bool? = nil, need: Int? = nil, have: Int? = nil) {
        self.status = status
        self.characterID = characterID
        self.duplicate = duplicate
        self.shardsGained = shardsGained
        self.shards = shards
        self.rubyBalance = rubyBalance
        self.price = price
        self.requestID = requestID
        self.replayed = replayed
        self.need = need
        self.have = have
    }

    package enum CodingKeys: String, CodingKey {
        case status, duplicate, shardsGained, shards, rubyBalance, price, replayed, need, have
        case characterID = "characterId"
        case requestID = "requestId"
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(GachaPullStatus.self, forKey: .status)
        characterID = container.lossy(String.self, forKey: .characterID)
        duplicate = container.lossy(Bool.self, forKey: .duplicate)
        shardsGained = container.lossy(Int.self, forKey: .shardsGained)
        shards = container.lossy(Int.self, forKey: .shards)
        rubyBalance = container.lossy(Int.self, forKey: .rubyBalance)
        price = container.lossy(Int.self, forKey: .price)
        requestID = container.lossy(String.self, forKey: .requestID)
        replayed = container.lossy(Bool.self, forKey: .replayed)
        need = container.lossy(Int.self, forKey: .need)
        have = container.lossy(Int.self, forKey: .have)
    }
}

/// `gacha_exchange` 응답. 규약은 `GachaPullResponse` 와 같다(status 만 필수 · 나머지는 삼킨다).
package struct GachaExchangeResponse: Decodable, Equatable, Sendable {
    package let status: GachaExchangeStatus
    package var characterID: String?
    /// 교환 뒤 내 조각 수.
    package var shards: Int?
    /// 이번 교환에 쓴 조각 수.
    package var cost: Int?
    package var requestID: String?
    package var replayed: Bool?
    /// insufficient_shards 일 때: 필요한 조각 · 가진 조각.
    package var need: Int?
    package var have: Int?

    package init(status: GachaExchangeStatus, characterID: String? = nil, shards: Int? = nil, cost: Int? = nil,
                 requestID: String? = nil, replayed: Bool? = nil, need: Int? = nil, have: Int? = nil) {
        self.status = status
        self.characterID = characterID
        self.shards = shards
        self.cost = cost
        self.requestID = requestID
        self.replayed = replayed
        self.need = need
        self.have = have
    }

    package enum CodingKeys: String, CodingKey {
        case status, shards, cost, replayed, need, have
        case characterID = "characterId"
        case requestID = "requestId"
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(GachaExchangeStatus.self, forKey: .status)
        characterID = container.lossy(String.self, forKey: .characterID)
        shards = container.lossy(Int.self, forKey: .shards)
        cost = container.lossy(Int.self, forKey: .cost)
        requestID = container.lossy(String.self, forKey: .requestID)
        replayed = container.lossy(Bool.self, forKey: .replayed)
        need = container.lossy(Int.self, forKey: .need)
        have = container.lossy(Int.self, forKey: .have)
    }
}

// MARK: - 서비스

extension SupabaseWorkService {
    package nonisolated static let gachaPullPath = "/rest/v1/rpc/gacha_pull"
    package nonisolated static let gachaExchangePath = "/rest/v1/rpc/gacha_exchange"

    /// 한 번 뽑는다. `gacha_pull(p_protocol, p_request_id)`.
    ///
    /// **잔량 확인·차감·장부·소유/조각 기입이 서버 한 트랜잭션 안에서 끝난다**(구매와 같은 규약). 클라의 비활성화는
    /// 헛왕복을 줄이는 장치이지 게이트가 아니다.
    ///
    /// `requestID` 는 **호출부(스토어)가 사용자 동작 한 번에 하나** 만들고, 결과를 모르는 실패 뒤 다시 누르면 **같은 값**을
    /// 넘긴다(`GachaRequestIDs`). 함수가 없는 서버(PGRST202 · 404)는 throw 하고 `GachaPullOutcome(error:)` 가 `.unavailable` 로 접는다 —
    /// 상점 RPC 처럼 옛 모양으로 되묻지 않는다(뽑기에는 옛 모양이 없다).
    /// `protocolVersion` 은 `ShopWire.protocolVersion(drawableCharacterIDs:)` 로만 만든다 — 2 미만이면 서버가 `needs_update` 다.
    package func gachaPull(accessToken: String, protocolVersion: Int, requestID: UUID) async throws -> GachaPullResponse {
        let data = try await send(
            path: Self.gachaPullPath,
            method: "POST",
            body: GachaPullRequest(protocolVersion: protocolVersion, requestID: requestID),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(GachaPullResponse.self, from: data)
    }

    /// 조각으로 캐릭터를 교환한다. `gacha_exchange(p_character_id, p_protocol, p_request_id)`.
    /// 루비는 움직이지 않는다(서버도 루비 장부를 쓰지 않는다). request_id 규약은 `gachaPull` 과 같다.
    package func gachaExchange(
        accessToken: String,
        characterID: String,
        protocolVersion: Int,
        requestID: UUID
    ) async throws -> GachaExchangeResponse {
        let data = try await send(
            path: Self.gachaExchangePath,
            method: "POST",
            body: GachaExchangeRequest(characterID: characterID, protocolVersion: protocolVersion, requestID: requestID),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(GachaExchangeResponse.self, from: data)
    }
}

// MARK: - 도메인 — 결과 분류

/// 뽑기 한 번의 결과(서버 ok 응답에서만 만든다).
package struct GachaPullResult: Equatable, Sendable {
    /// 결과의 갈래. 화면 연출이 이 값 하나로 갈린다.
    package enum Kind: Equatable, Sendable {
        /// 황금 아잉이(처음이든 중복이든 — 중복이면 `isDuplicate` 가 참이고 조각을 받았다). 후광 초상 + "황금 아잉이!".
        case gold
        /// 처음 나온 캐릭터 — 이제 가졌다.
        case newCharacter
        /// 이미 가진 캐릭터 — 조각을 받았다.
        case duplicate
    }

    package let characterID: String
    package let isDuplicate: Bool
    /// 이번에 얻은 조각. 서버가 안 줬으면 규칙대로(중복 = 1, 처음 = 0) — 서버 값이 있으면 그 값이 이긴다.
    package let shardsGained: Int
    /// 뽑은 뒤 조각 수(서버 값 · 모르면 nil).
    package let shards: Int?
    /// 뽑은 뒤 잔량(서버 값 · 모르면 nil).
    package let rubyBalance: Int?
    /// 같은 요청의 재응답인가(새로 깎이지 않았다).
    package let replayed: Bool

    package init(characterID: String, isDuplicate: Bool, shardsGained: Int, shards: Int?, rubyBalance: Int?, replayed: Bool) {
        self.characterID = characterID
        self.isDuplicate = isDuplicate
        self.shardsGained = shardsGained
        self.shards = shards
        self.rubyBalance = rubyBalance
        self.replayed = replayed
    }

    package var isGold: Bool { CharacterCatalog.isGoldAing(characterID) }

    package var kind: Kind {
        if isGold { return .gold }
        return isDuplicate ? .duplicate : .newCharacter
    }

    /// 이 결과로 **새로 갖게 된** 캐릭터 id(중복이면 nil). 스토어가 보유 목록에 바로 넣는 값이다.
    package var newlyOwnedID: String? { isDuplicate ? nil : characterID }
}

/// 뽑기 호출의 도메인 결과. **모르는 status 는 `.failed(원문)`** — 화면이 죽지 않는다.
package enum GachaPullOutcome: Equatable, Sendable {
    case pulled(GachaPullResult)
    case insufficient(need: Int?, have: Int?)
    case needsUpdate
    case notSignedIn
    case invalid
    /// 서버에 뽑기 함수가 아직 없다(PGRST202 · 404 — 앱이 db push 보다 먼저 나간 창). throw 로만 온다(`init?(error:)`).
    case unavailable
    /// 우리가 모르는 status, 또는 ok 인데 결과 id 가 빠진 응답.
    case failed(status: String)

    package init(response: GachaPullResponse) {
        switch response.status {
        case .ok:
            guard let id = response.characterID, !id.isEmpty else {
                self = .failed(status: response.status.raw)
                return
            }
            let duplicate = response.duplicate ?? false
            self = .pulled(GachaPullResult(
                characterID: id,
                isDuplicate: duplicate,
                shardsGained: response.shardsGained ?? (duplicate ? 1 : 0),
                shards: response.shards,
                rubyBalance: response.rubyBalance,
                replayed: response.replayed ?? false
            ))
        case .insufficient: self = .insufficient(need: response.need, have: response.have)
        case .needsUpdate: self = .needsUpdate
        case .notSignedIn: self = .notSignedIn
        case .invalid: self = .invalid
        case .unknown(let raw): self = .failed(status: raw)
        }
    }

    /// throw 로 온 실패 중 **결과를 아는 것**만 값으로 만든다: 함수 없음(PGRST202 · 404) → `.unavailable`(서버에서 아무것도 안 돌았다).
    /// 그 밖(오프라인 · 5xx · 응답 해석 실패)은 nil — 서버가 처리했는지 모르므로 호출부는 **request_id 를 쥔 채** 다시 묻는다.
    package init?(error: Error) {
        guard let known = error as? SupabaseWorkServiceError, BlockReportRules.isMissingFunction(known) else { return nil }
        self = .unavailable
    }
}

/// 교환 호출의 도메인 결과.
package enum GachaExchangeOutcome: Equatable, Sendable {
    case exchanged(characterID: String, shards: Int?, cost: Int?, replayed: Bool)
    case alreadyOwned
    case notExchangeable
    case insufficientShards(need: Int?, have: Int?)
    case needsUpdate
    case notSignedIn
    case unavailable
    case failed(status: String)

    /// `requestedID` 는 보낸 id — 서버가 ok 에 id 를 안 실었을 때만 쓴다.
    package init(response: GachaExchangeResponse, requestedID: String) {
        switch response.status {
        case .ok:
            self = .exchanged(characterID: response.characterID ?? requestedID, shards: response.shards,
                              cost: response.cost, replayed: response.replayed ?? false)
        case .alreadyOwned: self = .alreadyOwned
        case .notExchangeable: self = .notExchangeable
        case .insufficientShards: self = .insufficientShards(need: response.need, have: response.have)
        case .needsUpdate: self = .needsUpdate
        case .notSignedIn: self = .notSignedIn
        case .unknown(let raw): self = .failed(status: raw)
        }
    }

    package init?(error: Error) {
        guard let known = error as? SupabaseWorkServiceError, BlockReportRules.isMissingFunction(known) else { return nil }
        self = .unavailable
    }
}

// MARK: - 도메인 — request_id 수명

/// 사용자 동작 한 번 = request_id 하나. 결과를 모르는 실패 뒤 **같은 동작**을 다시 누르면 같은 id 를 돌려준다.
///
/// 버리는 때(`settle`)는 서버가 답을 줬을 때(어떤 status 든) · 함수가 없다는 것이 확실할 때(`.unavailable`)뿐이다.
/// 오프라인·5xx·응답 해석 실패에서는 쥔 채로 둔다 — 서버가 이미 처리했으면 다시 물을 때 `replayed` 로 처음 결과가 오고
/// 두 번 깎이지 않는다. 동작마다 칸이 따로다(뽑기 하나 · 교환은 캐릭터마다): 여우 교환이 결과를 모르는 채 남아 있어도
/// 뽑기는 새 id 로 간다.
package struct GachaRequestIDs: Equatable, Sendable {
    package private(set) var pull: UUID?
    package private(set) var exchange: [String: UUID] = [:]

    package init() {}

    /// 뽑기 요청 id — 쥔 것이 있으면 그것, 없으면 새로 만든다(만든 값을 쥔다).
    package mutating func pullID(make: () -> UUID = { UUID() }) -> UUID {
        if let pull { return pull }
        let made = make()
        pull = made
        return made
    }

    /// 교환 요청 id(캐릭터마다 따로).
    package mutating func exchangeID(for characterID: String, make: () -> UUID = { UUID() }) -> UUID {
        if let held = exchange[characterID] { return held }
        let made = make()
        exchange[characterID] = made
        return made
    }

    /// 서버가 답을 줬다 — 그 id 를 버린다. 다른 id 가 쥐어져 있으면(그 사이 새 동작) 건드리지 않는다.
    package mutating func settlePull(_ id: UUID) {
        if pull == id { pull = nil }
    }

    package mutating func settleExchange(_ id: UUID, for characterID: String) {
        if exchange[characterID] == id { exchange[characterID] = nil }
    }

    /// 로그아웃·계정 전환 — 앞 계정의 id 를 다음 계정이 쓰지 않게.
    package mutating func reset() {
        pull = nil
        exchange = [:]
    }
}

// MARK: - 도메인 — 판정(맥·폰 한 벌)

/// 지금 뽑을 수 있는가.
package enum GachaPullAvailability: Equatable, Sendable {
    /// 뽑을 수 있다.
    case ready(price: Int)
    /// 루비가 모자라다(버튼 비활성 + 이유).
    case short(price: Int, missing: Int)
    /// 잔량을 모른다(버튼 비활성 — 모르면서 깎지 않는다).
    case unknownBalance(price: Int)
    /// 뽑기를 열 수 없다(서버가 `gacha` 를 안 줬거나 · 값/확률표를 모른다).
    case unavailable

    package var canPull: Bool {
        if case .ready = self { return true }
        return false
    }
}

/// 한 캐릭터를 조각으로 교환할 수 있는가.
package enum GachaExchangeAvailability: Equatable, Sendable {
    /// 이미 가졌다 → "보유".
    case owned
    /// 교환할 수 있다.
    case available(cost: Int)
    /// 조각이 모자라다(비활성).
    case short(cost: Int, missing: Int)
    /// 조각 수를 모른다(비활성).
    case unknownShards(cost: Int)
    /// 교환표에 없다(아잉 · 모르는 id). 황금 아잉이는 교환표에 값이 있으면 다른 캐릭터와 똑같이 교환된다.
    case notExchangeable

    package var canExchange: Bool {
        if case .available = self { return true }
        return false
    }

    package var cost: Int? {
        switch self {
        case .available(let cost), .short(let cost, _), .unknownShards(let cost): return cost
        case .owned, .notExchangeable: return nil
        }
    }
}

/// 확률표 한 줄(화면용). 맥 "확률 보기" 표와 폰 시트가 같은 줄을 그린다.
package struct GachaOddsRow: Equatable, Sendable, Identifiable {
    package var id: String { characterID }
    package let characterID: String
    /// 사람이 읽는 이름("여우" · "황금 아잉이").
    package let name: String
    package let percent: Double
    /// "5%" · "2.5%".
    package let percentText: String
    /// 상점가(루비). 뽑기 전용(루비로 안 판다)이거나 서버가 값을 안 줬으면 nil.
    package let shopPrice: Int?
    /// 상점가 칸의 글: 숫자("60") · 뽑기 전용이면 "뽑기 또는 조각 20개"(교환값을 모르면 "뽑기 전용") · 모르면 "—".
    package let priceText: String
    package let isGachaOnly: Bool
    /// 조각 교환값(교환 불가면 nil).
    package let shardCost: Int?
    package var isGold: Bool { CharacterCatalog.isGoldAing(characterID) }
}

/// 교환 목록 한 줄(화면용).
package struct GachaExchangeRow: Equatable, Sendable, Identifiable {
    package var id: String { characterID }
    package let characterID: String
    package let name: String
    package let availability: GachaExchangeAvailability
}

package nonisolated enum GachaRules {
    /// 뽑을 수 있는가. 판정의 권위는 서버다 — 이건 버튼을 잠그고 이유를 말하는 문이다.
    package static func pullAvailability(info: GachaInfo?, rubyBalance: Int?) -> GachaPullAvailability {
        guard let info, info.isUsable, let price = info.price else { return .unavailable }
        guard let rubyBalance else { return .unknownBalance(price: price) }
        if rubyBalance < price { return .short(price: price, missing: price - rubyBalance) }
        return .ready(price: price)
    }

    /// 한 캐릭터의 교환 가능성. 보유가 먼저다(가진 것은 값과 무관하게 "보유").
    package static func exchangeAvailability(
        characterID: String,
        isOwned: Bool,
        shards: Int?,
        shardCosts: [String: Int]?
    ) -> GachaExchangeAvailability {
        // 아잉(무료 기본)은 서버가 교환표에 안 싣지만, 서버가 실수로 실어도 여기서 막는다(교환 불가는 사장님 규칙).
        // 황금 아잉이는 교환할 수 있다(AMENDMENT 1 — 값은 서버 교환표의 것만 · 없으면 교환 불가로 둔다).
        guard !isNeverExchangeable(characterID),
              let cost = shardCosts?[characterID], cost > 0 else { return .notExchangeable }
        if isOwned { return .owned }
        guard let shards else { return .unknownShards(cost: cost) }
        if shards < cost { return .short(cost: cost, missing: cost - shards) }
        return .available(cost: cost)
    }

    /// 확률표를 화면 줄로. **서버 순서 그대로**이고, 이름은 호출부가 준다(맥 = 카탈로그 · 폰 = 카드 표) — 못 찾으면
    /// 내장 이름(아잉 · 황금 아잉이), 그것도 없으면 id 를 그대로 쓴다(빈칸을 만들지 않는다).
    /// 상점가는 `shop_state.characters` 의 값이다(클라에 가격표를 두지 않는다).
    package static func oddsRows(
        info: GachaInfo,
        shopRows: [ShopCharacterRow],
        displayName: (String) -> String?
    ) -> [GachaOddsRow] {
        let rowsByID = Dictionary(shopRows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return (info.odds ?? []).map { entry in
            let id = entry.characterID
            let row = rowsByID[id]
            // 서버 표식이 참이면 뽑기 전용 · 황금 아잉이는 표식과 무관하게 언제나 뽑기 전용(사장님 규칙 — 루비로 안 판다).
            let gachaOnly = row?.gachaOnly == true || CharacterCatalog.isGoldAing(id)
            let price = gachaOnly ? nil : row?.price
            // 교환값(아잉은 서버가 실어도 버린다 · 0 이하는 값이 아니다).
            let cost = isNeverExchangeable(id) ? nil : info.shardCosts?[id].flatMap { $0 > 0 ? $0 : nil }
            let priceText: String
            if gachaOnly {
                // 루비 값 대신 얻는 길을 말한다: "뽑기 또는 조각 20개"(교환값을 모르면 "뽑기 전용").
                priceText = GachaText.gachaOnlyPrice(shardCost: cost)
            } else if let price {
                priceText = "\(price)"
            } else {
                priceText = GachaText.unknownValue
            }
            return GachaOddsRow(
                characterID: id,
                name: name(for: id, displayName: displayName),
                percent: entry.percent,
                percentText: GachaText.percent(entry.percent),
                shopPrice: price,
                priceText: priceText,
                isGachaOnly: gachaOnly,
                shardCost: cost
            )
        }
    }

    /// 교환 목록. **황금 아잉이가 맨 위**(사장님 정정 — "교환 목록은 금 먼저"), 그다음 확률표 순서(서버 순서),
    /// 확률표에 없는 교환값은 뒤에 id 순으로 붙는다. 교환표(`shard_costs`)에 없는 캐릭터는 줄을 만들지 않는다.
    package static func exchangeRows(
        info: GachaInfo,
        ownedIDs: Set<String>,
        displayName: (String) -> String?
    ) -> [GachaExchangeRow] {
        let costs = info.shardCosts ?? [:]
        var ordered: [String] = []
        for entry in info.odds ?? [] where costs[entry.characterID] != nil && !ordered.contains(entry.characterID) {
            ordered.append(entry.characterID)
        }
        ordered += costs.keys.filter { !ordered.contains($0) }.sorted()
        // 금 먼저 — 서버가 확률표를 어떤 순서로 주든(나머지의 상대 순서는 그대로).
        if let gold = ordered.firstIndex(where: { CharacterCatalog.isGoldAing($0) }), gold > 0 {
            ordered.insert(ordered.remove(at: gold), at: 0)
        }
        return ordered.compactMap { id in
            let availability = exchangeAvailability(characterID: id, isOwned: ownedIDs.contains(id),
                                                    shards: info.shards, shardCosts: costs)
            guard availability != .notExchangeable else { return nil }
            return GachaExchangeRow(characterID: id, name: name(for: id, displayName: displayName),
                                    availability: availability)
        }
    }

    /// 조각으로 **절대** 바꿀 수 없는 캐릭터인가 — 무료 기본(아잉) 하나. 서버 교환표에 실려 와도 막는다.
    /// (황금 아잉이는 여기 없다 — AMENDMENT 1 로 교환표의 값만큼 조각을 내면 교환된다.)
    package static func isNeverExchangeable(_ id: String) -> Bool {
        id == CharacterCatalog.builtInAingID
    }

    /// 이름 해석(호출부 → 내장 → id).
    package static func name(for id: String, displayName: (String) -> String?) -> String {
        if let given = displayName(id)?.trimmingCharacters(in: .whitespacesAndNewlines), !given.isEmpty { return given }
        if let builtIn = CharacterCatalog.builtIns.first(where: { $0.id == id }) { return builtIn.displayName }
        return id
    }
}

// MARK: - 문구(맥·폰 한 벌)

/// 뽑기 문구. 말투는 상점·확성기와 같은 해요체이고, "도박"·"베팅" 같은 말은 쓰지 않는다(뽑기 · 조각 · 확률).
package nonisolated enum GachaText {
    package static let title = "캐릭터 뽑기"
    package static let pullButton = "뽑기"
    /// 큰 버튼("뽑기 · 50"). 값을 모르면 부르지 않는다.
    package static func pullButton(price: Int) -> String { "\(pullButton) · \(price)" }
    package static let oddsButton = "확률 보기"
    package static let oddsTitle = "뽑기 확률"
    /// 확률표 아래 한 줄 — 규칙 전부를 짧게.
    package static let oddsFootnote = "이미 있는 캐릭터가 나오면 조각 1개를 받아요 · 조각으로 캐릭터를 바꿀 수 있어요"
    /// 상점가 칸의 "루비로 안 팖"(황금 아잉이) — 교환값을 모를 때만 쓰는 짧은 말. 교환값을 알면 `gachaOnlyPrice(shardCost:)`.
    package static let gachaOnly = "뽑기 전용"
    /// 루비 값 대신 얻는 길(황금 아잉이 카드·확률표 상점가 칸): "뽑기 또는 조각 20개". 교환값을 모르면(nil · 0 이하) "뽑기 전용".
    /// 숫자는 서버 `shard_costs` 의 값을 넘긴다 — 20 을 화면에 적지 않는다.
    package static func gachaOnlyPrice(shardCost: Int?) -> String {
        guard let shardCost, shardCost > 0 else { return gachaOnly }
        return "뽑기 또는 \(Self.shardCost(shardCost))"
    }
    /// 뽑기 전용 캐릭터를 눌렀을 때 · 고르기에서 안 가진 황금 아잉이를 눌렀을 때의 한 줄. "상점에서 살 수 있어요"는 이 캐릭터에 거짓이고,
    /// AMENDMENT 1 뒤로는 "뽑기로만"도 거짓이다(조각으로도 바꾼다). 서버 `buy_character` 의 `not_for_sale` 도 이 문장으로 말한다
    /// (루비는 안 깎였다).
    package static let gachaOnlyHint = "뽑기나 조각 교환으로 얻을 수 있어요"
    /// 값을 모를 때(상점 카드의 "—" 와 같은 표기).
    package static let unknownValue = "—"
    package static let owned = "보유"
    package static let exchangeButton = "교환"
    package static let exchangeTitle = "조각 교환"

    /// "5%" · "2.5%"(정수면 소수점 없이, 아니면 한 자리).
    package static func percent(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded))%" }
        return String(format: "%.1f%%", rounded)
    }

    /// 내 조각 수("조각 3개").
    package static func shards(_ count: Int) -> String { "조각 \(count)개" }
    /// 교환값("조각 5개") — 같은 눈금이라 같은 말을 쓴다.
    package static func shardCost(_ cost: Int) -> String { shards(cost) }

    // 결과 연출
    package static let goldHeadline = "황금 아잉이!"
    package static func newCharacter(name: String) -> String { "새 캐릭터: \(name)" }
    package static func duplicate(name: String, shardsGained: Int) -> String { "이미 있는 \(name) → 조각 +\(shardsGained)" }

    /// 결과 한 줄(큰 글씨). 황금은 언제나 "황금 아잉이!".
    package static func headline(for result: GachaPullResult, name: String) -> String {
        switch result.kind {
        case .gold: return goldHeadline
        case .newCharacter: return newCharacter(name: name)
        case .duplicate: return duplicate(name: name, shardsGained: result.shardsGained)
        }
    }

    /// 결과 둘째 줄(작은 글씨). 황금일 때만 있다 — 처음이면 "새 캐릭터: 황금 아잉이", 중복이면 조각 줄.
    package static func detail(for result: GachaPullResult, name: String) -> String? {
        guard result.kind == .gold else { return nil }
        return result.isDuplicate ? duplicate(name: name, shardsGained: result.shardsGained) : newCharacter(name: name)
    }

    // 막힌 이유 · 실패
    /// 모자란 루비(상점·확성기와 같은 문구를 쓴다 — 새로 만들지 않는다).
    package static func shortfall(need: Int?, have: Int?) -> String { CheckCoreShared.shortfallNotice(need: need, have: have) }
    package static func shardShortfall(missing: Int) -> String { "조각 \(missing)개 더 필요해요" }
    package static let needsUpdate = "앱을 업데이트하면 뽑을 수 있어요"
    package static let unavailable = "지금은 뽑을 수 없어요"
    package static let notSignedIn = "로그인하면 뽑을 수 있어요"
    package static let connection = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"
    package static let pullFailed = "뽑지 못했어요. 잠시 후 다시 시도해 주세요"
    package static let exchangeFailed = "교환하지 못했어요. 잠시 후 다시 시도해 주세요"
    package static let alreadyOwned = "이미 갖고 있어요"
    package static let notExchangeable = "교환할 수 없는 캐릭터예요"
    package static func exchanged(name: String) -> String { "교환했어요: \(name)" }

    /// 버튼을 잠근 이유(뽑기). 뽑을 수 있으면 nil.
    package static func blockedReason(_ availability: GachaPullAvailability) -> String? {
        switch availability {
        case .ready: return nil
        case .short(let price, let missing): return shortfall(need: price, have: price - missing)
        case .unknownBalance: return nil
        case .unavailable: return unavailable
        }
    }

    /// 뽑기 결과 중 **연출이 아닌** 것의 한 줄(실패·거절). `.pulled` 는 nil — 화면이 결과 연출로 말한다.
    package static func notice(for outcome: GachaPullOutcome) -> String? {
        switch outcome {
        case .pulled: return nil
        case .insufficient(let need, let have): return shortfall(need: need, have: have)
        case .needsUpdate: return needsUpdate
        case .notSignedIn: return notSignedIn
        case .unavailable: return unavailable
        case .invalid, .failed: return pullFailed
        }
    }

    /// 교환 결과 한 줄. `name` 은 교환한(하려던) 캐릭터 이름.
    package static func notice(for outcome: GachaExchangeOutcome, name: String) -> String {
        switch outcome {
        case .exchanged: return exchanged(name: name)
        case .alreadyOwned: return alreadyOwned
        case .notExchangeable: return notExchangeable
        case .insufficientShards(let need, let have):
            if let need, let have, need > have { return shardShortfall(missing: need - have) }
            return "조각이 모자라요"
        case .needsUpdate: return "앱을 업데이트하면 교환할 수 있어요"
        case .notSignedIn: return "로그인하면 교환할 수 있어요"
        case .unavailable: return "지금은 교환할 수 없어요"
        case .failed: return exchangeFailed
        }
    }
}

// MARK: - 디코드 보조(이 파일 전용)

/// 어떤 값이든 받아 버리는 자리(확률표에서 깨진 행을 건너뛸 때 커서를 한 칸 옮기는 용도).
private struct GachaDiscard: Decodable {
    init(from decoder: Decoder) throws {}
}

/// 숫자가 아니면 nil 이 되는 정수(교환표의 값 하나가 깨져도 나머지를 살린다).
private struct GachaLossyInt: Decodable {
    let value: Int?
    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Int.self)
    }
}

private extension KeyedDecodingContainer {
    /// 키가 없거나 · null 이거나 · 모양이 틀리면 nil. **throw 하지 않는다.**
    func lossy<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}
