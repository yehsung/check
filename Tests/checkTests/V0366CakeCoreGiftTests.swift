import Foundation
import Testing
@testable import check
@testable import CheckCore

/// v0.3.66 생일 선물(케이크 아잉이) — 전선 모양 · 서비스 두 메서드 · 수령 결과 분류 · 문구.
///
/// 지키는 것(설계서 §2-3 · §2-4 · §3):
///  ① `character_gift_pending` 응답을 설계서 JSON 그대로 읽는다 — gift 없음 · 있음 · note 문자열 · 키 빠짐 · 모양 틀림 · unauthorized.
///     선택지는 이 빌드가 아는 케이크만, **딸기 → 초코** 순서로 남는다(서버 순서에 기대지 않는다).
///  ② `claim_character_gift` 응답 표의 일곱 줄을 전부 읽고 도메인 결과로 접는다(모르는 status 는 `.failed`).
///  ③ 서비스: 진짜 `SupabaseWorkService` 가 보낸 본문의 키 집합 · 옛 서버(404 PGRST202 · 본문 없는 404) → nil · 5xx 는 던진다.
///  ④ 문구는 설계서 표의 글자 그대로다(맥 · 폰이 같이 쓴다).
@Suite("v0.3.66 생일 선물 전선")
struct V0366CakeCoreGiftTests {
    static let strawberry = V0366CakeCoreTests.strawberry
    static let choco = V0366CakeCoreTests.choco
    static let giftID = "6f1c2b9e-1a2b-4c3d-8e9f-0a1b2c3d4e5f"

    static func pending(_ json: String) throws -> CharacterGiftPendingResponse {
        try V0354GachaWireTests.decoder().decode(CharacterGiftPendingResponse.self, from: Data(json.utf8))
    }

    static func claim(_ json: String) throws -> CharacterGiftClaimResponse {
        try V0354GachaWireTests.decoder().decode(CharacterGiftClaimResponse.self, from: Data(json.utf8))
    }

    static func host(_ label: String) -> String {
        "v0366-gift-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    }

    /// 서비스와 같은 전략(camel → snake)의 인코더 — 본문 키를 서비스 경로 시험과 따로 한 번 더 잰다.
    static func encodedKeys(_ value: some Encodable) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - ① pending 디코드

    @Test("pending: 설계서 JSON 그대로 — gift 없음 · gift 있음(note null) · note 문자열 · unauthorized")
    func pendingDecodesSpecShapes() throws {
        let none = try Self.pending(#"{"status":"ok"}"#)
        #expect(none.status == "ok" && none.gift == nil && none.offer == nil)

        let full = try Self.pending(#"""
        {"status":"ok","gift":{"id":"6f1c2b9e-1a2b-4c3d-8e9f-0a1b2c3d4e5f","options":["aing_cake_strawberry","aing_cake_choco"],"note":null,"created_at":"2026-10-26T03:00:00.123456+00:00"}}
        """#)
        let offer = try #require(full.offer, "gift 가 있는데 offer 가 nil")
        #expect(offer.id == Self.giftID)
        #expect(offer.options == [Self.strawberry, Self.choco])
        #expect(offer.note == nil)
        #expect(offer.createdAt == "2026-10-26T03:00:00.123456+00:00")

        let noted = try Self.pending(#"{"status":"ok","gift":{"id":"g1","options":["aing_cake_choco"],"note":"생일 축하해요 태화님","created_at":"2026-10-26T03:00:00Z"}}"#)
        #expect(noted.offer?.note == "생일 축하해요 태화님")
        #expect(noted.offer?.options == [Self.choco], "이미 딸기를 가진 사람은 초코 하나만 받는다(서버가 읽는 시점에 거른다)")

        let unauthorized = try Self.pending(#"{"status":"unauthorized"}"#)
        #expect(unauthorized.status == "unauthorized" && unauthorized.offer == nil)
        // status 가 ok 가 아니면 gift 가 실려 와도 띄우지 않는다.
        let odd = try Self.pending(#"{"status":"needs_update","gift":{"id":"g1","options":["aing_cake_choco"]}}"#)
        #expect(odd.gift != nil && odd.offer == nil)
    }

    @Test("pending: 선택지는 아는 케이크만 · 딸기 → 초코 순서 · 중복 없음 — 남는 게 없거나 id 가 없으면 선물 없음")
    func pendingFiltersAndOrdersOptions() throws {
        let reversed = try Self.pending(#"{"status":"ok","gift":{"id":"g1","options":["aing_cake_choco","aing_cake_strawberry"]}}"#)
        #expect(reversed.offer?.options == [Self.strawberry, Self.choco], "서버 순서에 기댔다")
        let mixed = try Self.pending(#"{"status":"ok","gift":{"id":"g1","options":["aing_cake_choco","aing_cake_mint","fox",7,null,"aing_cake_choco"]}}"#)
        #expect(mixed.offer?.options == [Self.choco], "모르는 선택지 · 중복 · 문자열 아닌 원소를 걸러야 한다")

        // 선물이 없는 것으로 읽어야 하는 모양들 — 응답 자체는 산다(조회가 죽지 않는다).
        let empties = [
            #"{"status":"ok","gift":{"id":"g1","options":[]}}"#,
            #"{"status":"ok","gift":{"id":"g1","options":["aing_cake_mint","AING_CAKE_CHOCO"]}}"#,
            #"{"status":"ok","gift":{"id":"g1"}}"#,
            #"{"status":"ok","gift":{"id":"g1","options":"aing_cake_choco"}}"#,
            #"{"status":"ok","gift":{"options":["aing_cake_choco"]}}"#,
            #"{"status":"ok","gift":{"id":"  ","options":["aing_cake_choco"]}}"#,
            #"{"status":"ok","gift":{"id":42,"options":["aing_cake_choco"]}}"#,
            #"{"status":"ok","gift":null}"#,
            #"{"status":"ok","gift":"aing_cake_choco"}"#,
            #"{"status":"ok","gift":[]}"#,
        ]
        for json in empties {
            let response = try Self.pending(json)
            #expect(response.status == "ok" && response.offer == nil, Comment(rawValue: json))
        }
        // note · created_at 이 모양이 틀려도 선물은 산다.
        let sloppy = try Self.pending(#"{"status":"ok","gift":{"id":"g1","options":["aing_cake_strawberry"],"note":5,"created_at":false}}"#)
        #expect(sloppy.offer == CharacterGiftOffer(id: "g1", options: [Self.strawberry], note: nil, createdAt: nil))
        let blankNote = try Self.pending(#"{"status":"ok","gift":{"id":"g1","options":["aing_cake_strawberry"],"note":"  "}}"#)
        #expect(blankNote.offer?.note == nil, "빈 메모를 메모로 그리지 않는다")
    }

    @Test("pending: status 가 없으면 무슨 응답인지 모른다 → throw (호출부가 지금 아는 선물을 그대로 둔다)")
    func pendingWithoutStatusThrows() {
        for json in [#"{"gift":{"id":"g1","options":["aing_cake_choco"]}}"#, #"[]"#, #"{"status":1}"#] {
            #expect(throws: (any Error).self, Comment(rawValue: json)) { _ = try Self.pending(json) }
        }
    }

    @Test("CharacterGiftOffer 생성자도 같은 거르기를 탄다(픽스처 · 미리보기가 모르는 선택지를 못 만든다)")
    func offerInitFilters() {
        let offer = CharacterGiftOffer(id: "g1", options: [Self.choco, "fox", Self.strawberry, Self.choco])
        #expect(offer.options == [Self.strawberry, Self.choco])
        #expect(CharacterGiftOffer.choosable(["aing_gold", "aing_rainbow"]).isEmpty)
    }

    // MARK: - ② claim 디코드 · 결과 분류

    @Test("claim: 응답 표 일곱 줄을 전부 읽는다 — 키 없는 줄은 nil")
    func claimDecodesSpecTable() throws {
        let rows: [(String, CharacterGiftClaimResponse)] = [
            (#"{"status":"unauthorized"}"#, CharacterGiftClaimResponse(status: "unauthorized")),
            (#"{"status":"needs_update","min_protocol":4}"#, CharacterGiftClaimResponse(status: "needs_update", minProtocol: 4)),
            (#"{"status":"not_found"}"#, CharacterGiftClaimResponse(status: "not_found")),
            (#"{"status":"invalid_choice"}"#, CharacterGiftClaimResponse(status: "invalid_choice")),
            (#"{"status":"ok","character_id":"aing_cake_choco","replayed":true}"#,
             CharacterGiftClaimResponse(status: "ok", characterId: Self.choco, replayed: true)),
            (#"{"status":"already_claimed","character_id":"aing_cake_strawberry"}"#,
             CharacterGiftClaimResponse(status: "already_claimed", characterId: Self.strawberry)),
            (#"{"status":"ok","character_id":"aing_cake_strawberry","replayed":false}"#,
             CharacterGiftClaimResponse(status: "ok", characterId: Self.strawberry, replayed: false)),
        ]
        for (json, expected) in rows {
            #expect(try Self.claim(json) == expected, Comment(rawValue: json))
        }
        // 모양이 틀린 칸은 nil 로 삼킨다(받았는데 결과를 못 읽는 응답을 만들지 않는다).
        #expect(try Self.claim(#"{"status":"ok","character_id":7,"replayed":"yes","min_protocol":"4"}"#)
                == CharacterGiftClaimResponse(status: "ok"))
        #expect(throws: (any Error).self) { _ = try Self.claim(#"{"character_id":"aing_cake_choco"}"#) }
    }

    @Test("claim 결과 분류: 표의 모든 갈래 · ok 에 id 가 없으면 보낸 id · 모르는 status 는 failed · 선물 카드를 거두는 조건")
    func claimOutcomes() {
        func outcome(_ response: CharacterGiftClaimResponse, _ requested: String = V0366CakeCoreGiftTests.choco) -> CharacterGiftClaimOutcome {
            CharacterGiftClaimOutcome(response: response, requestedID: requested)
        }
        let table: [(CharacterGiftClaimResponse, CharacterGiftClaimOutcome, settles: Bool)] = [
            (.init(status: "ok", characterId: Self.choco, replayed: false), .received(characterID: Self.choco, replayed: false), true),
            (.init(status: "ok", characterId: Self.choco, replayed: true), .received(characterID: Self.choco, replayed: true), true),
            (.init(status: "ok"), .received(characterID: Self.choco, replayed: false), true),
            (.init(status: "ok", characterId: ""), .received(characterID: Self.choco, replayed: false), true),
            (.init(status: "already_claimed", characterId: Self.strawberry), .alreadyClaimed(characterID: Self.strawberry), true),
            (.init(status: "already_claimed"), .alreadyClaimed(characterID: nil), true),
            (.init(status: "not_found"), .notFound, true),
            (.init(status: "needs_update", minProtocol: 4), .needsUpdate, false),
            (.init(status: "invalid_choice"), .invalidChoice, false),
            (.init(status: "unauthorized"), .notSignedIn, false),
            (.init(status: "gift_expired"), .failed(status: "gift_expired"), false),
        ]
        for (response, expected, settles) in table {
            let got = outcome(response)
            #expect(got == expected, Comment(rawValue: "\(response) → \(got)"))
            #expect(got.settlesGift == settles, Comment(rawValue: "\(got).settlesGift"))
        }
        #expect(CharacterGiftClaimOutcome.unavailable.settlesGift == false)
    }

    @Test("본문 키: pending 은 p_protocol 하나 · claim 은 p_gift · p_character · p_protocol 셋(언제나)")
    func requestBodies() throws {
        let pending = try Self.encodedKeys(CharacterGiftPendingRequest(pProtocol: 4))
        #expect(Set(pending.keys) == ["p_protocol"] && pending["p_protocol"] as? Int == 4)
        let legacy = try Self.encodedKeys(CharacterGiftPendingRequest(pProtocol: 0))
        #expect(Set(legacy.keys) == ["p_protocol"], "0 이어도 키를 싣는다(새 함수라 옛 모양이 없다)")
        let claim = try Self.encodedKeys(CharacterGiftClaimRequest(pGift: Self.giftID, pCharacter: Self.strawberry, pProtocol: 4))
        #expect(Set(claim.keys) == ["p_gift", "p_character", "p_protocol"])
        #expect(claim["p_gift"] as? String == Self.giftID && claim["p_character"] as? String == Self.strawberry)
    }

    // MARK: - ③ 서비스

    @Test("서비스: 진짜 경로가 p_protocol 을 싣고 선물을 돌려준다 · gift 없음 · unauthorized 는 nil")
    func servicePendingPath() async throws {
        let host = Self.host("pending")
        GomokuStubProtocol.register(host: host) { rpc, body, _ in
            guard rpc == "character_gift_pending" else { return nil }
            let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
            let version = json["p_protocol"] as? Int ?? 0
            guard version >= 4 else { return GomokuStubProtocol.Reply(body: #"{"status":"ok"}"#) }
            return GomokuStubProtocol.Reply(body: #"{"status":"ok","gift":{"id":"g-77","options":["aing_cake_strawberry","aing_cake_choco"],"note":null,"created_at":"2026-10-26T03:00:00Z"}}"#)
        }
        let service = V0354GachaWireTests.service(host: host)
        let offer = try await service.fetchCharacterGiftPending(accessToken: "t", protocolVersion: ShopWire.cakeProtocol)
        #expect(offer == CharacterGiftOffer(id: "g-77", options: [Self.strawberry, Self.choco], note: nil, createdAt: "2026-10-26T03:00:00Z"))
        let three = try await service.fetchCharacterGiftPending(accessToken: "t", protocolVersion: ShopWire.rainbowProtocol)
        #expect(three == nil, "3 인 빌드에는 서버가 gift 를 안 싣는다")
        let calls = GomokuStubProtocol.calls(host: host, rpc: "character_gift_pending")
        #expect(calls.count == 2)
        #expect(calls.map { Set($0.json.keys) } == [["p_protocol"], ["p_protocol"]])
        #expect(calls.map { $0.json["p_protocol"] as? Int } == [4, 3])
        #expect(SupabaseWorkService.characterGiftPendingPath == "/rest/v1/rpc/character_gift_pending")

        let unauthorizedHost = Self.host("unauth")
        GomokuStubProtocol.register(host: unauthorizedHost) { _, _, _ in GomokuStubProtocol.Reply(body: #"{"status":"unauthorized"}"#) }
        #expect(try await V0354GachaWireTests.service(host: unauthorizedHost)
                    .fetchCharacterGiftPending(accessToken: "t", protocolVersion: 4) == nil)
    }

    @Test("서비스: 옛 서버(404 PGRST202 · 본문 없는 404)의 조회는 nil · 5xx · status 없는 응답은 던진다")
    func servicePendingOldServer() async throws {
        let missingHost = Self.host("missing")
        GomokuStubProtocol.register(host: missingHost) { rpc, _, _ in
            GomokuStubProtocol.Reply(status: 404, body: #"{"code":"PGRST202","message":"Could not find the function public."#
                                     + rpc + #"(p_protocol) in the schema cache"}"#)
        }
        #expect(try await V0354GachaWireTests.service(host: missingHost)
                    .fetchCharacterGiftPending(accessToken: "t", protocolVersion: 4) == nil)

        let bareHost = Self.host("bare404")
        GomokuStubProtocol.register(host: bareHost) { _, _, _ in GomokuStubProtocol.Reply(status: 404, body: "") }
        #expect(try await V0354GachaWireTests.service(host: bareHost)
                    .fetchCharacterGiftPending(accessToken: "t", protocolVersion: 4) == nil)

        // 기준선: 아픈 서버 · 모르는 응답은 "선물 없음"으로 단정하지 않는다(던진다).
        let sickHost = Self.host("sick")
        GomokuStubProtocol.register(host: sickHost) { _, _, _ in
            GomokuStubProtocol.Reply(status: 503, body: #"{"message":"upstream connect error"}"#)
        }
        await #expect(throws: (any Error).self) {
            _ = try await V0354GachaWireTests.service(host: sickHost).fetchCharacterGiftPending(accessToken: "t", protocolVersion: 4)
        }
        let oddHost = Self.host("odd")
        GomokuStubProtocol.register(host: oddHost) { _, _, _ in GomokuStubProtocol.Reply(body: #"{"gift":null}"#) }
        await #expect(throws: (any Error).self) {
            _ = try await V0354GachaWireTests.service(host: oddHost).fetchCharacterGiftPending(accessToken: "t", protocolVersion: 4)
        }
    }

    @Test("서비스: 수령 본문 키 셋 · 응답 디코드 · 404 는 던지고 unavailable · 5xx 는 결과를 모름(nil)")
    func serviceClaimPath() async throws {
        let host = Self.host("claim")
        GomokuStubProtocol.register(host: host) { rpc, body, index in
            guard rpc == "claim_character_gift" else { return nil }
            let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
            let character = json["p_character"] as? String ?? ""
            return GomokuStubProtocol.Reply(body: #"{"status":"ok","character_id":""# + character + #"","replayed":"#
                                            + (index > 0 ? "true" : "false") + "}")
        }
        let service = V0354GachaWireTests.service(host: host)
        let first = try await service.claimCharacterGift(accessToken: "t", giftID: Self.giftID, characterID: Self.choco,
                                                         protocolVersion: ShopWire.cakeProtocol)
        #expect(first == CharacterGiftClaimResponse(status: "ok", characterId: Self.choco, replayed: false))
        #expect(CharacterGiftClaimOutcome(response: first, requestedID: Self.choco) == .received(characterID: Self.choco, replayed: false))
        let again = try await service.claimCharacterGift(accessToken: "t", giftID: Self.giftID, characterID: Self.choco,
                                                         protocolVersion: ShopWire.cakeProtocol)
        #expect(again.replayed == true)
        let call = try #require(GomokuStubProtocol.calls(host: host, rpc: "claim_character_gift").first)
        #expect(Set(call.json.keys) == ["p_gift", "p_character", "p_protocol"], Comment(rawValue: call.body))
        #expect(call.json["p_gift"] as? String == Self.giftID)
        #expect(call.json["p_character"] as? String == Self.choco)
        #expect(call.json["p_protocol"] as? Int == 4)
        #expect(SupabaseWorkService.claimCharacterGiftPath == "/rest/v1/rpc/claim_character_gift")

        let missingHost = Self.host("claim-missing")
        GomokuStubProtocol.register(host: missingHost) { rpc, _, _ in
            GomokuStubProtocol.Reply(status: 404, body: #"{"code":"PGRST202","message":"Could not find the function public."#
                                     + rpc + #" in the schema cache"}"#)
        }
        do {
            _ = try await V0354GachaWireTests.service(host: missingHost)
                .claimCharacterGift(accessToken: "t", giftID: Self.giftID, characterID: Self.choco, protocolVersion: 4)
            Issue.record("404 인데 throw 하지 않았다")
        } catch {
            #expect(CharacterGiftClaimOutcome(error: error) == .unavailable, "\(error)")
        }
        let sickHost = Self.host("claim-sick")
        GomokuStubProtocol.register(host: sickHost) { _, _, _ in
            GomokuStubProtocol.Reply(status: 503, body: #"{"message":"upstream connect error"}"#)
        }
        do {
            _ = try await V0354GachaWireTests.service(host: sickHost)
                .claimCharacterGift(accessToken: "t", giftID: Self.giftID, characterID: Self.choco, protocolVersion: 4)
            Issue.record("503 인데 throw 하지 않았다")
        } catch {
            #expect(CharacterGiftClaimOutcome(error: error) == nil, "결과를 모르는 실패를 아는 갈래로 접었다: \(error)")
        }
    }

    // MARK: - ④ 문구

    @Test("문구: 설계서 표의 글자 그대로")
    func textConstants() {
        #expect(CakeGiftText.title == "생일 축하해요! 🎂")
        #expect(CakeGiftText.body == "생일 선물로 케이크 아잉이를 하나 골라 주세요.")
        #expect(CakeGiftText.confirmButton == "이걸로 받을게요")
        #expect(CakeGiftText.wearNowButton == "지금 입기")
        #expect(CakeGiftText.closeButton == "닫기")
        #expect(CakeGiftText.lockedCaption == "생일 선물 전용")
        #expect(CakeGiftText.lockedHint == "생일에 선물로만 받을 수 있어요. 루비나 뽑기로는 얻을 수 없어요.")
        #expect(CakeGiftText.reopenTitle == "생일 선물이 도착했어요")
        #expect(CakeGiftText.reopenButton == "고르기")
        #expect(CakeGiftText.received(name: "딸기 케이크 아잉이") == "딸기 케이크 아잉이를 받았어요!")
        #expect(CakeGiftText.received(name: "초코 케이크 아잉이") == "초코 케이크 아잉이를 받았어요!")
        // 조사: 받침이 있으면 '을'(기준선 — 함수가 실제로 가른다).
        #expect(CakeGiftText.received(name: "케이크 곰") == "케이크 곰을 받았어요!")
        #expect(CakeGiftText.objectParticle(after: "robot") == "를")
        #expect(CakeGiftText.objectParticle(after: "") == "를")
    }

    @Test("문구: 수령 결과 한 줄 — 받음은 nil(받은 뒤 화면이 말한다) · 이미 받음은 받은 것의 이름 · 나머지는 각자의 줄")
    func claimNotices() {
        let name: (String) -> String = { GachaRules.name(for: $0, displayName: { _ in nil }) }
        #expect(CakeGiftText.notice(for: .received(characterID: Self.choco, replayed: false), name: name) == nil)
        #expect(CakeGiftText.notice(for: .alreadyClaimed(characterID: Self.strawberry), name: name) == "딸기 케이크 아잉이를 받았어요!")
        #expect(CakeGiftText.notice(for: .alreadyClaimed(characterID: nil), name: name) == CakeGiftText.alreadyClaimed)
        #expect(CakeGiftText.notice(for: .needsUpdate, name: name) == CakeGiftText.needsUpdate)
        #expect(CakeGiftText.notice(for: .notFound, name: name) == CakeGiftText.notFound)
        #expect(CakeGiftText.notice(for: .invalidChoice, name: name) == CakeGiftText.invalidChoice)
        #expect(CakeGiftText.notice(for: .notSignedIn, name: name) == CakeGiftText.notSignedIn)
        #expect(CakeGiftText.notice(for: .unavailable, name: name) == CakeGiftText.unavailable)
        #expect(CakeGiftText.notice(for: .failed(status: "x"), name: name) == CakeGiftText.claimFailed)
        // 줄끼리 겹치지 않는다(같은 글이면 사용자가 무슨 일인지 모른다).
        let lines = [CakeGiftText.claimFailed, CakeGiftText.needsUpdate, CakeGiftText.unavailable, CakeGiftText.notSignedIn,
                     CakeGiftText.notFound, CakeGiftText.invalidChoice, CakeGiftText.alreadyClaimed]
        #expect(Set(lines).count == lines.count)
    }
}
