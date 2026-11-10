import Foundation

// MARK: - 생일 선물 — 케이크 아잉이 (v0.3.66 맥 · 1.0.14 폰)
//
// 서버 정본은 `supabase/migrations/20261026120000_cake_aing_gift.sql` 이다. 요점만(설계서 §2):
//   · 운영자가 `grant_character_gift(p_user)` 로 지급한다(service_role 만). 선물 행(`character_gifts`)의 선택지는 그 사람이 **아직 안 가진**
//     생일 선물 전용 캐릭터(딸기 → 초코)이고, 사용자당 열린(미수령) 선물은 하나다.
//   · 클라는 `character_gift_pending(p_protocol)` 로 열린 선물을 묻는다. 서버는 p_protocol ≥ 4 · 열린 선물이 있음 · 안 가진 선택지가
//     1개 이상일 때만 `gift` 를 싣는다(선택지는 **읽는 시점에** 거른다).
//   · 받는 사람이 하나를 골라 `claim_character_gift(p_gift, p_character, p_protocol)` 로 받는다. 같은 캐릭터로 다시 부르면
//     `replayed: true` 로 같은 답이 오고(두 번 넣지 않는다), 다른 캐릭터로 다시 부르면 `already_claimed` 다.
//   · 루비 · 장부 · 착용은 움직이지 않는다. 착용은 클라가 기존 `set_character` 로 따로 한다([지금 입기]).
//
// ── 이 파일이 지키는 것 ──
// ① **맥과 폰이 한 벌이다.** 전선 모양 · 결과 분류 · 문구를 여기서 만들고 화면은 그리기만 한다.
// ② **옛 서버에서도 앱이 산다.** 함수가 없는 서버(404 · PGRST202 — 앱이 db push 보다 먼저 나간 창)의 조회는 오류가 아니라 "선물 없음"(nil)이다.
// ③ **모르는 선택지를 그리지 않는다.** 선택지는 이 빌드가 아는 **그 선물 종류의** 내장 캐릭터(`CharacterGiftKind.builtInIDs`)만 남기고
//    표시 순서(생일 = 딸기 → 초코 · 술 = 이슬)로 세운다. 남는 게 없으면 선물이 없는 것으로 읽는다(열 수 없는 창을 띄우지 않는다).
//
// ── '술 한잔' 선물 — 이슬 아잉이 (v0.3.74 맥 먼저) ──
// 서버 초안(설계서 §4): `character_gifts.kind`('birthday' · 'drink')가 생기고, 운영자는 생일은 `grant_character_gift`, 술은
// `grant_drink_gift` 로 지급한다. `character_gift_pending(p_protocol)` 은 p < 4 면 gift 없음 · 4 면 **생일만**(옛 행동 그대로) ·
// 5 이상이면 두 종류 중 먼저 지급된 것 하나이고, gift 객체에 `"kind"` 를 싣는다(키가 없으면 옛 서버 — 생일로 읽는다).
// 술 선물 수령은 p < 5 면 `needs_update`(아무것도 안 움직인다). 수령 · 결과 분류는 생일과 같은 함수 · 같은 어휘다.
//
// ── 빼빼로 데이 선물 — 빼빼로 아잉이 (v0.3.77 맥 먼저 · 11-11 기간 선물) ──
// 셋째 종류 `'pepero'`. 이슬과 같은 틀이다: 선택지 하나(고를 것 없이 받기) · 최소 능력 번호 6 · 서버는 p ≥ 6 에게만 빼빼로 선물을 싣고,
// 수령은 p < 6 이면 `needs_update`. 옛 빌드(0.3.74~0.3.76 — 이 종류를 모른다)는 서버가 실어 보내도 `kind` 를 몰라 선물 없음으로 삼킨다
// (아래 디코드 규칙) — 그래도 서버는 번호로 먼저 막는다(옛 빌드는 받을 수 없는 선물을 가진 채 생일 · 술 선물까지 가려지지 않게).

// MARK: 전선 모양 — character_gift_pending

/// `character_gift_pending(p_protocol)` 본문. **키를 언제나 싣는다**(새 함수라 옛 모양이 없다 — 키 집합을 하나로 고정한다).
package struct CharacterGiftPendingRequest: Encodable, Equatable, Sendable {
    package let pProtocol: Int

    package init(pProtocol: Int) {
        self.pProtocol = pProtocol
    }
}

// MARK: 선물 종류 — birthday · drink (v0.3.74) · pepero (v0.3.77)

/// 선물 종류. 서버 `character_gifts.kind` · `character_prices.gift_kind` 의 원문 값과 같다(`rawValue`).
///
/// ★ 종류마다 **선택지 집합이 따로**다 — 생일 선물엔 케이크만, 술 선물엔 이슬만, 빼빼로 선물엔 빼빼로만 선다(`builtInIDs`). 서버가 섞어
///   보내도(초안 전 · 잘못 지급) 클라는 그 종류의 것만 남긴다. 그리고 종류마다 **받을 수 있는 능력 번호가 다르다**(`minProtocol` — 생일 4 ·
///   술 5 · 빼빼로 6).
package enum CharacterGiftKind: String, CaseIterable, Sendable, Equatable {
    /// 생일 선물(v0.3.66) — 케이크 아잉이 둘 중 하나를 받는 사람이 고른다.
    case birthday
    /// '술 한잔' 선물(v0.3.74) — 이슬 아잉이 하나, 고를 것 없이 받는다.
    case drink
    /// 빼빼로 데이 선물(v0.3.77 · 11-11 기간 선물) — 빼빼로 아잉이 하나, 고를 것 없이 받는다.
    case pepero
    /// 우리 센터 선물(지역 아잉이) — 그 사람 센터의 아잉이 하나(부산 → 갈매기 · 서울 → 서울 아잉이), 고를 것 없이 받는다. 기한 없음.
    case region

    /// 서버 원문 값("birthday" · "drink" · "pepero"). 문자열을 적는 곳은 여기(`rawValue`) 하나다.
    package var wireValue: String { rawValue }

    /// 서버 원문 → 종류. 정확히 그 세 값만(공백 · 대소문자를 봐주지 않는다 — 서버 CHECK 가 그 값들만 허락한다). 그 밖은 nil.
    package init?(wireValue: String?) {
        guard let wireValue, let kind = Self(rawValue: wireValue) else { return nil }
        self = kind
    }

    /// 이 종류의 선물로 받는 내장 캐릭터 — **표시 순서 그대로**(생일 = 딸기 → 초코 · 술 = 이슬). 선물 선택지는 이 목록으로 거른다.
    package var builtInIDs: [String] {
        switch self {
        case .birthday: return CharacterCatalog.birthdayGiftBuiltInIDs
        case .drink: return CharacterCatalog.drinkGiftBuiltInIDs
        case .pepero: return CharacterCatalog.peperoGiftBuiltInIDs
        case .region: return CharacterCatalog.regionGiftBuiltInIDs
        }
    }

    /// 이 종류의 선물을 받을 수 있는 최소 능력 번호(서버 `claim_character_gift` 의 문턱과 같다 — 생일 4 · 술 5 · 빼빼로 6).
    package var minProtocol: Int {
        switch self {
        case .birthday: return ShopWire.cakeProtocol
        case .drink: return ShopWire.isulProtocol
        case .pepero: return ShopWire.peperoProtocol
        case .region: return ShopWire.regionProtocol
        }
    }

    /// 이 번호의 빌드가 이 종류의 선물을 받을 수 있는가(번호는 누적이다 — `ShopWire.protocolVersion`).
    package func isSupported(protocolVersion: Int) -> Bool {
        protocolVersion >= minProtocol
    }

    /// 내장 캐릭터 → 그 캐릭터를 주는 선물 종류(케이크 → 생일 · 이슬 → 술 · 빼빼로 → 빼빼로). 선물 전용 내장이 아니면 nil.
    package init?(builtInID id: String?) {
        guard let id, let kind = Self.allCases.first(where: { $0.builtInIDs.contains(id) }) else { return nil }
        self = kind
    }

    /// 이 종류의 문구 묶음(받는 창 · 잠긴 칸 · 다시 열기 카드). 글자는 `CakeGiftText` · `DrinkGiftText` · `PeperoGiftText` 한 곳에 있다.
    package var copy: CharacterGiftCopy {
        switch self {
        case .birthday: return .birthday
        case .drink: return .drink
        case .pepero: return .pepero
        case .region: return .region
        }
    }
}

/// 열린 선물 한 장 — `{"id":"…","kind":"birthday"|"drink","options":["aing_cake_strawberry","aing_cake_choco"],"note":null|"…","created_at":"…"}`.
///
/// ★ 디코드 규칙: `id` 가 없거나 비었으면, `kind` 가 이 빌드가 모르는 값이면, 또는 **그 종류로** 거른 뒤 선택지가 하나도 없으면
///   **throw** 한다 — 감싼 응답(`CharacterGiftPendingResponse`)이 그걸 "선물 없음"(nil)으로 삼킨다. `kind` 키가 없거나 null 이면
///   옛 서버(0.3.66 생일 선물만 있던 시절) — **생일**로 읽는다. `note` · `created_at` 은 모양이 틀려도 nil 이다.
package struct CharacterGiftOffer: Decodable, Equatable, Sendable, Identifiable {
    /// 선물 행 id(uuid 문자열 — 서버가 준 그대로). 수령 때 `p_gift` 로 돌려준다.
    package let id: String
    /// 선물 종류(생일 · 술 한잔). 서버가 안 실었으면 생일.
    package let kind: CharacterGiftKind
    /// 고를 수 있는 캐릭터 id — **이 빌드가 아는 그 종류의 내장 캐릭터만**, 표시 순서(생일 = 딸기 → 초코 · 술 = 이슬), 중복 없음.
    package let options: [String]
    /// 운영자가 남긴 한 줄(없으면 nil).
    package let note: String?
    /// 지급 시각(서버 timestamptz 원문). 화면 판정에 쓰지 않는다 — 진단용이다.
    package let createdAt: String?

    package init(id: String, options: [String], note: String? = nil, createdAt: String? = nil, kind: CharacterGiftKind = .birthday) {
        self.id = id
        self.kind = kind
        self.options = Self.choosable(options, kind: kind)
        self.note = note
        self.createdAt = createdAt
    }

    package enum CodingKeys: String, CodingKey {
        // 서비스 디코더가 `created_at` → `createdAt` 으로 바꾼 뒤 찾는다.
        case id, kind, options, note, createdAt
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let rawID = container.giftLossy(String.self, forKey: .id)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawID.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "gift id 가 없다")
        }
        // kind: 키가 없거나 null → 생일(옛 서버). 있는데 모르는 값 · 모양이 틀림 → 이 빌드가 열 수 없는 선물(throw → 선물 없음).
        let kind: CharacterGiftKind
        if (try? container.decodeNil(forKey: .kind)) ?? true {
            kind = .birthday
        } else if let known = CharacterGiftKind(wireValue: container.giftLossy(String.self, forKey: .kind)) {
            kind = known
        } else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "모르는 선물 종류다")
        }
        let options = Self.choosable(container.giftLossyStrings(forKey: .options) ?? [], kind: kind)
        guard !options.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .options, in: container, debugDescription: "고를 수 있는 선택지가 없다")
        }
        self.id = rawID
        self.kind = kind
        self.options = options
        let note = container.giftLossy(String.self, forKey: .note)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = (note?.isEmpty ?? true) ? nil : note
        self.createdAt = container.giftLossy(String.self, forKey: .createdAt)
    }

    /// 서버 선택지 → 화면 선택지: 이 빌드가 아는 **그 종류의** 내장 캐릭터만, `CharacterGiftKind.builtInIDs` 순서로
    /// (생일 = `CharacterCatalog.birthdayGiftBuiltInIDs` 딸기 → 초코 · 술 = 이슬). 순서를 서버에 기대지 않는다
    /// (설계서 §1 "지급 선택지의 순서도 딸기 → 초코"). ★ 생일 선물에 이슬이 섞여 와도 버리고, 술 선물엔 이슬만 남긴다.
    package static func choosable(_ raw: [String], kind: CharacterGiftKind = .birthday) -> [String] {
        let given = Set(raw)
        return kind.builtInIDs.filter { given.contains($0) }
    }
}

/// `character_gift_pending` 응답 — `{"status":"ok"}` · `{"status":"ok","gift":{…}}` · `{"status":"unauthorized"}`.
/// `status` 만 필수다(없으면 무슨 응답인지 모르므로 throw). `gift` 는 모양이 틀리면 nil — 선물 하나 때문에 조회가 죽지 않는다.
package struct CharacterGiftPendingResponse: Decodable, Equatable, Sendable {
    package let status: String
    package let gift: CharacterGiftOffer?

    package init(status: String, gift: CharacterGiftOffer? = nil) {
        self.status = status
        self.gift = gift
    }

    package enum CodingKeys: String, CodingKey {
        case status, gift
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        gift = container.giftLossy(CharacterGiftOffer.self, forKey: .gift)
    }

    /// 화면이 띄울 선물 — `status == "ok"` 이고 gift 가 있을 때만. 그 밖(unauthorized · 모르는 status)은 nil.
    package var offer: CharacterGiftOffer? {
        status == CharacterGiftStatus.ok ? gift : nil
    }
}

// MARK: 전선 모양 — claim_character_gift

/// `claim_character_gift(p_gift, p_character, p_protocol)` 본문. **키 셋을 언제나 싣는다**(키 집합이 흔들리면 PostgREST 가 다른 함수를 찾는다).
package struct CharacterGiftClaimRequest: Encodable, Equatable, Sendable {
    package let pGift: String
    package let pCharacter: String
    package let pProtocol: Int

    package init(pGift: String, pCharacter: String, pProtocol: Int) {
        self.pGift = pGift
        self.pCharacter = pCharacter
        self.pProtocol = pProtocol
    }
}

/// `claim_character_gift` 응답 — 설계서 §2-4 의 표:
/// `unauthorized` · `{"status":"needs_update","min_protocol":4}` · `not_found` · `invalid_choice` ·
/// `{"status":"ok","character_id":…,"replayed":true|false}` · `{"status":"already_claimed","character_id":<받은 것>}`.
/// `status` 만 필수다. 나머지 칸은 모양이 틀려도 nil 로 삼킨다(한 칸 때문에 "받았는데 결과를 못 읽는" 응답을 만들지 않는다).
package struct CharacterGiftClaimResponse: Decodable, Equatable, Sendable {
    package let status: String
    package let characterId: String?
    package let replayed: Bool?
    package let minProtocol: Int?

    package init(status: String, characterId: String? = nil, replayed: Bool? = nil, minProtocol: Int? = nil) {
        self.status = status
        self.characterId = characterId
        self.replayed = replayed
        self.minProtocol = minProtocol
    }

    package enum CodingKeys: String, CodingKey {
        case status, characterId, replayed, minProtocol
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        characterId = container.giftLossy(String.self, forKey: .characterId)
        replayed = container.giftLossy(Bool.self, forKey: .replayed)
        minProtocol = container.giftLossy(Int.self, forKey: .minProtocol)
    }
}

/// 서버 status 어휘(두 함수 공통). 문자열을 적는 곳은 여기 하나다.
package nonisolated enum CharacterGiftStatus {
    package static let ok = "ok"
    package static let unauthorized = "unauthorized"
    package static let needsUpdate = "needs_update"
    package static let notFound = "not_found"
    package static let invalidChoice = "invalid_choice"
    package static let alreadyClaimed = "already_claimed"
}

// MARK: - 도메인 — 수령 결과 분류

/// 수령 한 번의 도메인 결과(맥 · 폰 한 벌). **모르는 status 는 `.failed(원문)`** — 화면이 죽지 않는다.
package enum CharacterGiftClaimOutcome: Equatable, Sendable {
    /// 받았다(`replayed` 면 같은 선택의 재응답 — 새로 넣지 않았다). [지금 입기]는 이 id 로 기존 착용 경로를 탄다.
    case received(characterID: String, replayed: Bool)
    /// 이미 **다른** 캐릭터로 받은 선물이다. `characterID` 는 받은 것(서버가 안 실었으면 nil). 사용자는 이미 케이크를 가졌다.
    case alreadyClaimed(characterID: String?)
    /// 이 빌드는 그 선물의 캐릭터를 못 그린다(생일 p_protocol < 4 · 술 < 5) — 아무것도 안 움직였다.
    case needsUpdate
    /// 내 선물이 아니거나 없다(회수됐거나 계정이 바뀌었다).
    case notFound
    /// 선택지에 없는 캐릭터를 보냈다(이미 가진 것 · 모르는 id).
    case invalidChoice
    case notSignedIn
    /// 서버에 수령 함수가 아직 없다(PGRST202 · 404 — 앱이 db push 보다 먼저 나간 창). throw 로만 온다(`init?(error:)`).
    case unavailable
    /// 우리가 모르는 status.
    case failed(status: String)

    /// `requestedID` 는 보낸 id — 서버가 ok 에 id 를 안 실었을 때만 쓴다.
    package init(response: CharacterGiftClaimResponse, requestedID: String) {
        switch response.status {
        case CharacterGiftStatus.ok:
            let id = response.characterId.flatMap { $0.isEmpty ? nil : $0 } ?? requestedID
            self = .received(characterID: id, replayed: response.replayed ?? false)
        case CharacterGiftStatus.alreadyClaimed:
            self = .alreadyClaimed(characterID: response.characterId.flatMap { $0.isEmpty ? nil : $0 })
        case CharacterGiftStatus.needsUpdate: self = .needsUpdate
        case CharacterGiftStatus.notFound: self = .notFound
        case CharacterGiftStatus.invalidChoice: self = .invalidChoice
        case CharacterGiftStatus.unauthorized: self = .notSignedIn
        default: self = .failed(status: response.status)
        }
    }

    /// throw 로 온 실패 중 **결과를 아는 것**만 값으로 만든다: 함수 없음(PGRST202 · 404) → `.unavailable`(서버에서 아무것도 안 돌았다).
    /// 그 밖(오프라인 · 5xx · 응답 해석 실패)은 nil — 서버가 처리했는지 모른다. 수령은 같은 선택으로 다시 불러도 안전하다
    /// (같은 캐릭터면 `replayed: true` 로 같은 답이 온다).
    package init?(error: Error) {
        guard let known = error as? SupabaseWorkServiceError, BlockReportRules.isMissingFunction(known) else { return nil }
        self = .unavailable
    }

    /// 이 선물이 끝났는가 — 받았다 · 이미 받았다 · 내 선물이 아니거나 없다. 화면이 선물 카드(다시 열기 카드)를 거두는 조건이다.
    /// 그 밖(업데이트 필요 · 고를 수 없음 · 로그인 · 서버 미배포 · 모르는 status)은 선물이 그대로 열려 있다.
    package var settlesGift: Bool {
        switch self {
        case .received, .alreadyClaimed, .notFound: return true
        case .needsUpdate, .invalidChoice, .notSignedIn, .unavailable, .failed: return false
        }
    }
}

// MARK: - 서비스

extension SupabaseWorkService {
    package nonisolated static let characterGiftPendingPath = "/rest/v1/rpc/character_gift_pending"
    package nonisolated static let claimCharacterGiftPath = "/rest/v1/rpc/claim_character_gift"

    /// 열린 생일 선물을 묻는다. `character_gift_pending(p_protocol)`.
    ///
    /// - 선물이 없거나 · status 가 ok 가 아니거나 · 고를 수 있는 선택지가 없으면 **nil** 이다.
    /// - 함수가 없는 서버(404 PGRST202 → `.databaseSchemaMissing`, 본문 없는 404 → `.invalidResponse(404)`)도 **nil** 이다 —
    ///   앱이 db push 보다 먼저 나간 창에서 오류를 올리지 않는다(`fetchAppUserCharacters` 와 같은 두 모양).
    /// - 그 밖의 실패(네트워크 · 5xx · 세션 만료 · status 없는 응답)는 **던진다** — 호출부는 지금 아는 선물을 그대로 둔다.
    ///
    /// `protocolVersion` 은 `ShopWire.protocolVersion(drawableCharacterIDs:)` 로만 만든다 — 4 미만이면 서버가 gift 를 싣지 않고,
    /// 4 면 생일 선물만 싣는다(술 선물은 5 부터 — v0.3.74 · 빼빼로 선물은 6 부터 — v0.3.77). 이 빌드의 번호로 받을 수 없는 종류가
    /// 섞여 오면 nil 이다(빼빼로 그림이 없는 빌드 = 번호 5 이하에 빼빼로 선물이 와도 안 띄운다).
    package func fetchCharacterGiftPending(accessToken: String, protocolVersion: Int) async throws -> CharacterGiftOffer? {
        let data: Data
        do {
            data = try await send(
                path: Self.characterGiftPendingPath,
                method: "POST",
                body: CharacterGiftPendingRequest(pProtocol: protocolVersion),
                accessToken: accessToken,
                prefer: nil
            )
        } catch let error as SupabaseWorkServiceError where BlockReportRules.isMissingFunction(error) {
            return nil
        }
        // 이 빌드가 받을 수 없는 종류(술 선물인데 번호 4)는 서버가 안 싣는 것이 정본이지만, 섞여 와도 띄우지 않는다
        // (열어 봐야 수령이 `needs_update` 다 — 받을 수 없는 창을 띄우지 않는다).
        guard let offer = try decoder.decode(CharacterGiftPendingResponse.self, from: data).offer,
              offer.kind.isSupported(protocolVersion: protocolVersion) else { return nil }
        return offer
    }

    /// 선물을 받는다. `claim_character_gift(p_gift, p_character, p_protocol)`.
    ///
    /// 소유 기입과 선물 행 마감이 서버 한 트랜잭션 안에서 끝난다. 루비 · 착용은 움직이지 않는다.
    /// 함수가 없는 서버(PGRST202 · 404)는 throw 하고 `CharacterGiftClaimOutcome(error:)` 가 `.unavailable` 로 접는다.
    package func claimCharacterGift(
        accessToken: String,
        giftID: String,
        characterID: String,
        protocolVersion: Int
    ) async throws -> CharacterGiftClaimResponse {
        let data = try await send(
            path: Self.claimCharacterGiftPath,
            method: "POST",
            body: CharacterGiftClaimRequest(pGift: giftID, pCharacter: characterID, pProtocol: protocolVersion),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(CharacterGiftClaimResponse.self, from: data)
    }
}

// MARK: - 문구(맥·폰 한 벌)

/// 생일 선물 문구. 설계서 §3 표의 글자 그대로다 — 맥 축하 창 · 폰 축하 시트 · 상점 잠긴 칸 · 다시 열기 카드가 같이 쓴다.
package nonisolated enum CakeGiftText {
    /// 축하 창 제목.
    package static let title = "생일 축하해요! 🎂"
    /// 축하 창 본문.
    package static let body = "생일 선물로 케이크 아잉이를 하나 골라 주세요."
    /// 확인 단추(하나를 고른 뒤).
    package static let confirmButton = "이걸로 받을게요"
    /// 받은 뒤의 단추 둘.
    package static let wearNowButton = "지금 입기"
    package static let closeButton = "닫기"
    /// 상점 잠긴 칸 캡션(가격 · 사기 단추 자리).
    package static let lockedCaption = "생일 선물 전용"
    /// 잠긴 칸을 골랐을 때의 안내.
    package static let lockedHint = "생일에 선물로만 받을 수 있어요. 루비나 뽑기로는 얻을 수 없어요."
    /// 고르지 않고 닫은 뒤 메뉴 팝오버 · 상점 · 폰 Me 화면에 남는 카드.
    package static let reopenTitle = "생일 선물이 도착했어요"
    package static let reopenButton = "고르기"

    /// 받은 뒤 한 줄 — "딸기 케이크 아잉이를 받았어요!"(받침이 있으면 '을').
    package static func received(name: String) -> String {
        "\(name)\(objectParticle(after: name)) 받았어요!"
    }

    // 실패 · 거절(설계서 표에 없는 줄 — 말투는 뽑기 `GachaText` 와 같은 해요체, 마침표 없음)
    package static let claimFailed = "받지 못했어요. 잠시 후 다시 시도해 주세요"
    package static let needsUpdate = "앱을 업데이트하면 받을 수 있어요"
    package static let unavailable = "지금은 받을 수 없어요"
    package static let notSignedIn = "로그인하면 받을 수 있어요"
    package static let notFound = "선물을 찾지 못했어요"
    package static let invalidChoice = "고를 수 없는 캐릭터예요"
    package static let alreadyClaimed = "이미 받은 선물이에요"

    /// 수령 결과 중 **받은 화면이 아닌** 것의 한 줄. `.received` 는 nil — 화면이 받은 뒤 화면(`received(name:)`)으로 말한다.
    /// `.alreadyClaimed` 는 받은 것의 id 를 알면 "○○를 받았어요!"(사용자는 이미 가졌다 — `name` 은 id → 표시 이름), 모르면 "이미 받은 선물이에요".
    package static func notice(for outcome: CharacterGiftClaimOutcome, name: (String) -> String) -> String? {
        switch outcome {
        case .received: return nil
        case .alreadyClaimed(let id): return id.map { received(name: name($0)) } ?? alreadyClaimed
        case .needsUpdate: return needsUpdate
        case .notFound: return notFound
        case .invalidChoice: return invalidChoice
        case .notSignedIn: return notSignedIn
        case .unavailable: return unavailable
        case .failed: return claimFailed
        }
    }

    /// 목적격 조사 — 마지막 글자가 받침 있는 한글이면 '을', 그 밖(받침 없음 · 한글 아님 · 빈 문자열)은 '를'.
    package static func objectParticle(after word: String) -> String {
        guard let last = word.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.last,
              (0xAC00...0xD7A3).contains(last.value) else { return "를" }
        return (last.value - 0xAC00) % 28 == 0 ? "를" : "을"
    }
}

/// '술 한잔' 선물 문구(v0.3.74 이슬 아잉이). 설계서 §5 표의 **가제** 글자 그대로다(대표 확인 전 시안 — 바뀌면 여기 한 곳만 고친다).
/// `CakeGiftText` 와 같은 모양이다 — 받는 창 · 상점 잠긴 칸 · 다시 열기 카드가 같이 쓴다. 실패 · 거절 줄은 생일과 한 벌이다.
/// 문구는 대표 결정(2026-11-03, 결재 #d_QKdjqLLU7S0b "C 짧고 가볍게 (짠! 🥂)" — 수고 인사처럼 가볍게).
/// 잠긴 칸 캡션 · 안내 · 받은 뒤 한 줄은 C 안에 따로 없어 설계서 §5 가제를 그대로 둔다.
package nonisolated enum DrinkGiftText {
    /// 받는 창 제목.
    package static let title = "짠! 🥂"
    /// 받는 창 본문(운영자 한 줄 `note` 가 있으면 화면이 그 위에 크게 — 초대장처럼).
    package static let body = "오늘도 고생 많았어요. 이슬 아잉이 한 병 받아요!"
    /// 확인 단추(고를 것이 없다 — 선택지는 이슬 하나).
    package static let confirmButton = "짠 받기"
    /// 받은 뒤의 단추 둘(생일과 같은 글자).
    package static let wearNowButton = CakeGiftText.wearNowButton
    package static let closeButton = CakeGiftText.closeButton
    /// 상점 잠긴 칸 캡션(가격 · 사기 단추 자리).
    package static let lockedCaption = "술 한잔 선물 전용"
    /// 잠긴 칸을 골랐을 때의 안내.
    package static let lockedHint = "술 한잔 선물로만 받을 수 있어요. 루비나 뽑기로는 얻을 수 없어요."
    /// 받지 않고 닫은 뒤 메뉴 팝오버 · 상점에 남는 카드.
    package static let reopenTitle = "짠! 선물이 왔어요"
    package static let reopenButton = "받기"
    /// 결과를 모르는 수령(오프라인 · 5xx · 응답 해석 실패)의 한 줄 — 생일과 같은 글자다(다시 눌러도 안전하다).
    package static let claimFailed = CakeGiftText.claimFailed

    /// 받은 뒤 한 줄 — "이슬 아잉이를 받았어요!"(조사 규칙은 생일과 한 곳).
    package static func received(name: String) -> String {
        CakeGiftText.received(name: name)
    }

    /// 수령 결과 중 받은 화면이 아닌 것의 한 줄 — 생일과 같은 어휘 · 같은 글자(`CakeGiftText.notice`).
    package static func notice(for outcome: CharacterGiftClaimOutcome, name: (String) -> String) -> String? {
        CakeGiftText.notice(for: outcome, name: name)
    }
}

/// 빼빼로 데이 선물 문구(v0.3.77 빼빼로 아잉이 — 11-11 기간 선물). **대표 결정 C "장난스럽게"**(2026-11-04 결재 #d_JyxuQRmHOYKC — 몰래 챙겨 온 느낌, 단추도 '쏙 받기'). 바뀌면 여기 한 곳만 고친다.
/// `DrinkGiftText` 와 같은 모양 · 같은 자리다. '빼빼로'는 남의 상표라 행사 이름 · 캐릭터 이름이 바뀔 수 있다 — 캐릭터 이름은
/// `CharacterCatalog.peperoAingDisplayName` 한 곳에서 읽고, 행사 이름이 든 줄(제목 · 다시 열기 · 잠긴 칸)은 이 묶음에만 있다.
/// 실패 · 거절 줄은 생일과 한 벌이다.
package nonisolated enum PeperoGiftText {
    /// 받는 창 제목.
    package static let title = "빼빼로 받아랏! 🍫"
    /// 받는 창 본문(운영자 한 줄 `note` 가 있으면 화면이 그 위에 크게 — 이슬 초대장과 같은 틀).
    package static let body = "몰래 하나 챙겨 왔어요. \(CharacterCatalog.peperoAingDisplayName) 쏙!"
    /// 확인 단추(고를 것이 없다 — 선택지는 빼빼로 하나).
    package static let confirmButton = "쏙 받기"
    /// 받은 뒤의 단추 둘(생일과 같은 글자).
    package static let wearNowButton = CakeGiftText.wearNowButton
    package static let closeButton = CakeGiftText.closeButton
    /// 상점 잠긴 칸 캡션(가격 · 사기 단추 자리).
    package static let lockedCaption = "빼빼로 데이 선물 전용"
    /// 잠긴 칸을 골랐을 때의 안내.
    package static let lockedHint = "빼빼로 데이 선물로만 받을 수 있어요. 루비나 뽑기로는 얻을 수 없어요."
    /// 받지 않고 닫은 뒤 메뉴 팝오버 · 상점에 남는 카드.
    package static let reopenTitle = "빼빼로가 쏙 들어왔어요"
    package static let reopenButton = "받기"
    /// 결과를 모르는 수령의 한 줄 — 생일과 같은 글자다(다시 눌러도 안전하다).
    package static let claimFailed = CakeGiftText.claimFailed

    /// 받은 뒤 한 줄 — "빼빼로 아잉이를 받았어요!"(조사 규칙은 생일과 한 곳).
    package static func received(name: String) -> String {
        CakeGiftText.received(name: name)
    }

    /// 수령 결과 중 받은 화면이 아닌 것의 한 줄 — 생일과 같은 어휘 · 같은 글자(`CakeGiftText.notice`).
    package static func notice(for outcome: CharacterGiftClaimOutcome, name: (String) -> String) -> String? {
        CakeGiftText.notice(for: outcome, name: name)
    }
}

/// 선물 종류 하나의 문구 묶음 — 화면이 종류로 갈라 그릴 때 `CharacterGiftKind.copy` 로 받는다(글자는 `CakeGiftText` · `DrinkGiftText` ·
/// `PeperoGiftText` 한 곳).
package struct CharacterGiftCopy: Equatable, Sendable {
    package let title: String
    package let body: String
    package let confirmButton: String
    package let wearNowButton: String
    package let closeButton: String
    package let lockedCaption: String
    package let lockedHint: String
    package let reopenTitle: String
    package let reopenButton: String
    /// 결과를 모르는 수령의 한 줄(`CakeGiftText.claimFailed` · `DrinkGiftText.claimFailed`).
    package let claimFailed: String

    /// 생일 선물(케이크 아잉이 — v0.3.66).
    package static let birthday = CharacterGiftCopy(
        title: CakeGiftText.title, body: CakeGiftText.body, confirmButton: CakeGiftText.confirmButton,
        wearNowButton: CakeGiftText.wearNowButton, closeButton: CakeGiftText.closeButton,
        lockedCaption: CakeGiftText.lockedCaption, lockedHint: CakeGiftText.lockedHint,
        reopenTitle: CakeGiftText.reopenTitle, reopenButton: CakeGiftText.reopenButton,
        claimFailed: CakeGiftText.claimFailed
    )

    /// '술 한잔' 선물(이슬 아잉이 — v0.3.74).
    package static let drink = CharacterGiftCopy(
        title: DrinkGiftText.title, body: DrinkGiftText.body, confirmButton: DrinkGiftText.confirmButton,
        wearNowButton: DrinkGiftText.wearNowButton, closeButton: DrinkGiftText.closeButton,
        lockedCaption: DrinkGiftText.lockedCaption, lockedHint: DrinkGiftText.lockedHint,
        reopenTitle: DrinkGiftText.reopenTitle, reopenButton: DrinkGiftText.reopenButton,
        claimFailed: DrinkGiftText.claimFailed
    )

    /// 빼빼로 데이 선물(빼빼로 아잉이 — v0.3.77, 문구는 대표 결정 C).
    package static let pepero = CharacterGiftCopy(
        title: PeperoGiftText.title, body: PeperoGiftText.body, confirmButton: PeperoGiftText.confirmButton,
        wearNowButton: PeperoGiftText.wearNowButton, closeButton: PeperoGiftText.closeButton,
        lockedCaption: PeperoGiftText.lockedCaption, lockedHint: PeperoGiftText.lockedHint,
        reopenTitle: PeperoGiftText.reopenTitle, reopenButton: PeperoGiftText.reopenButton,
        claimFailed: PeperoGiftText.claimFailed
    )

    /// 우리 센터 선물(지역 아잉이 — 문구 가안, `RegionGiftText`).
    package static let region = CharacterGiftCopy(
        title: RegionGiftText.title, body: RegionGiftText.body, confirmButton: RegionGiftText.confirmButton,
        wearNowButton: RegionGiftText.wearNowButton, closeButton: RegionGiftText.closeButton,
        lockedCaption: RegionGiftText.lockedCaption, lockedHint: RegionGiftText.lockedHint,
        reopenTitle: RegionGiftText.reopenTitle, reopenButton: RegionGiftText.reopenButton,
        claimFailed: RegionGiftText.claimFailed
    )

    /// 받은 뒤 한 줄(종류와 무관하게 한 규칙 — "○○를 받았어요!").
    package func received(name: String) -> String {
        CakeGiftText.received(name: name)
    }
}

// MARK: - 디코드 보조(이 파일 전용)

private extension KeyedDecodingContainer {
    /// 키가 없거나 · null 이거나 · 모양이 틀리면 nil. **throw 하지 않는다.**
    func giftLossy<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// 배열이 아니면 nil, 배열이면 문자열 원소만 남긴다(원소 하나가 깨져도 나머지는 산다).
    func giftLossyStrings(forKey key: Key) -> [String]? {
        guard contains(key), var list = try? nestedUnkeyedContainer(forKey: key) else { return nil }
        var items: [String] = []
        while !list.isAtEnd {
            if let value = try? list.decode(String.self) {
                items.append(value)
            } else if (try? list.decode(CharacterGiftDiscard.self)) == nil {
                break
            }
        }
        return items
    }
}

/// 어떤 값이든 받아 버리는 자리(선택지 배열에서 문자열이 아닌 원소를 건너뛸 때 커서를 한 칸 옮기는 용도).
private struct CharacterGiftDiscard: Decodable {
    init(from decoder: Decoder) throws {}
}
