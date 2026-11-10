@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 빼빼로 · 흑우 · 루비 · 개발에 찌든 아잉이(맥 0.3.77 · 0.3.78 · 0.3.81 먼저)를 폰 1.0.18 이 실어 **능력 번호가 9** 가 된다는 못.
//
// 대표 지시(2026-11-10 "지금 맥만 구현해놓고 폰 구현 안된거 많잖아. 이것들 다 구현해서 넣자."): 넷의 초상 · 카드를 번들에 싣는다.
// 번호는 누적이라(`ShopWire.protocolVersion`) 넷이 한 묶음이다 — 빼빼로 하나만 빠져도 5 에서 멈추고 흑우 · 루비 · 개발이 통째로 안 온다.
// 폰 빼빼로 초상은 상자에 '빼빼로' 글자가 없는 판이다(상표 대비 — `BaseComponentTests`).
@Suite("폰 1.0.18 — 능력 번호 9(빼빼로 · 흑우 · 루비 · 개발)")
struct MePeperoProtocolPinTests {
    @Test("폰 knownIDs 에 넷이 다 있다 → 번호 9 · 하나라도 빠지면 그 앞 번호에서 멈춘다 · 빼빼로 선물을 받는다 · 카드 표도 안다")
    @MainActor
    func phoneProtocolIsNine() {
        let known = AingCharacterArt.knownIDs
        let four = [CharacterCatalog.peperoAingID, CharacterCatalog.hwooAingID, CharacterCatalog.rubyAingID, CharacterCatalog.devAingID]
        for id in four { #expect(known.contains(id), Comment(rawValue: "\(id) 가 없다: \(known)")) }
        let derived = ShopWire.protocolVersion(drawableCharacterIDs: known)
        #expect(derived == ShopWire.devProtocol, Comment(rawValue: "목록 \(known) → \(derived)"))
        // 반대 방향(번호가 목록에서 파생된다): 빼빼로가 빠지면 5 · 흑우 6 · 루비 7 · 개발 8.
        let expectations: [(String, Int)] = [(CharacterCatalog.peperoAingID, ShopWire.isulProtocol), (CharacterCatalog.hwooAingID, ShopWire.peperoProtocol),
                                            (CharacterCatalog.rubyAingID, ShopWire.hwooProtocol), (CharacterCatalog.devAingID, ShopWire.rubyProtocol)]
        for (id, expected) in expectations {
            #expect(ShopWire.protocolVersion(drawableCharacterIDs: known.filter { $0 != id }) == expected, Comment(rawValue: "\(id) 를 뺀 번호"))
        }
        #expect(ShopWire.supportsCakeGift(protocolVersion: derived) && ShopWire.supportsDrinkGift(protocolVersion: derived))
        #expect(ShopWire.supportsPeperoGift(protocolVersion: derived))
        #expect(CharacterGiftKind.pepero.isSupported(protocolVersion: derived))
        for id in four {
            #expect(MeCharacterCards.knownIDs.contains(id))
            #expect(MeCharacterCards.equippedID(fromServer: id) == id)
        }
        // 선물 전용 판정(상점 '못 산다')은 코어 한 벌 — 빼빼로는 선물 전용이다.
        #expect(CharacterCatalog.isGiftOnlyBuiltIn(CharacterCatalog.peperoAingID))
    }

    @Test("디코더 길: 이 번호로는 빼빼로 선물을 받는다 · 모르는 종류 · kind 없는 응답은 여전히 선물 없음")
    func peperoGiftIsForThePhone() throws {
        let derived = ShopWire.protocolVersion(drawableCharacterIDs: AingCharacterArt.knownIDs)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let body = #"{"status":"ok","gift":{"id":"g","kind":"pepero","options":["aing_pepero"],"note":null}}"#
        let offer = try decoder.decode(CharacterGiftPendingResponse.self, from: Data(body.utf8)).offer
        #expect(offer?.kind == .pepero && offer?.options == [CharacterCatalog.peperoAingID])
        #expect(offer.map { $0.kind.isSupported(protocolVersion: derived) } == true)
        let unknown = #"{"status":"ok","gift":{"id":"g","kind":"valentine","options":["aing_pepero"],"note":null}}"#
        #expect(try decoder.decode(CharacterGiftPendingResponse.self, from: Data(unknown.utf8)).offer == nil)
        let kindless = #"{"status":"ok","gift":{"id":"g","options":["aing_pepero"],"note":null}}"#
        #expect(try decoder.decode(CharacterGiftPendingResponse.self, from: Data(kindless.utf8)).offer == nil)
    }
}
