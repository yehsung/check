@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 빼빼로 아잉이(맥 0.3.77 먼저 — 폰은 다음 폰 판)가 공용 코어에 들어와도 **폰의 능력 번호는 그대로**라는 못.
//
// 사용자 결정(2026-11-04 "맥만, 따로 빨리 (0.3.77)" — 폰은 다음 판): 이번엔 폰 초상 · 폰 화면 · 폰 번호를 올리지 않는다.
// 코어 카탈로그(`CharacterCatalog.builtIns`)에 빼빼로가 붙어도 폰의 "그릴 수 있다"(`AingCharacterArt.knownIDs`)는 번들 초상에서만 오므로
// 빼빼로가 없고, 번호는 빼빼로를 빼고 센 값과 같다(지금 main 은 이슬 초상도 없어 4 — 폰 1.0.17 이 이슬을 실으면 5). 어느 쪽이든 6 은 아니다.
// 코어가 `cakeCharacterIDs` · `isulCharacterIDs` 에 빼빼로를 섞으면(설계서 §2 함정) 이 시험이 번호가 떨어진 것으로 잡는다.
@Suite("빼빼로 아잉이 — 폰 능력 번호 그대로")
struct MePeperoProtocolPinTests {
    @Test("폰 knownIDs 에 빼빼로가 없다 → 번호는 빼빼로 전과 같다(6 아님) · 케이크 선물 그대로 · 빼빼로 선물은 아니다")
    @MainActor
    func phoneProtocolIgnoresPepero() {
        let known = AingCharacterArt.knownIDs
        #expect(!known.contains(CharacterCatalog.peperoAingID), Comment(rawValue: "\(known)"))
        let derived = ShopWire.protocolVersion(drawableCharacterIDs: known)
        let withoutPepero = ShopWire.protocolVersion(drawableCharacterIDs: known.filter { $0 != CharacterCatalog.peperoAingID })
        #expect(derived == withoutPepero)
        #expect(derived < ShopWire.peperoProtocol, Comment(rawValue: "목록 \(known) → \(derived)"))
        #expect(derived >= ShopWire.cakeProtocol, "폰이 케이크 선물 번호(4) 밑으로 떨어졌다 — 케이크 뜻 자리에 빼빼로가 섞였는가")
        #expect(ShopWire.supportsCakeGift(protocolVersion: derived))
        #expect(!ShopWire.supportsPeperoGift(protocolVersion: derived))
        #expect(!CharacterGiftKind.pepero.isSupported(protocolVersion: derived))
        // 폰 카드 목록(번들 초상 기준)에도 빼빼로가 없다 — 고르기 · 상점 자리표시에 서지 않는다 · 착용값은 아잉으로 접힌다.
        #expect(!MeCharacterCards.knownIDs.contains(CharacterCatalog.peperoAingID))
        #expect(MeCharacterCards.equippedID(fromServer: CharacterCatalog.peperoAingID) == MeCharacterCards.aingID)
        // 선물 전용 판정(상점 '못 산다')은 코어 한 벌이라 폰에서도 빼빼로를 선물 전용으로 읽는다(서버가 실어 보내도 사기 단추가 안 선다).
        #expect(CharacterCatalog.isGiftOnlyBuiltIn(CharacterCatalog.peperoAingID))
    }

    @Test("옛 디코더 길: 폰 번호로는 빼빼로 선물을 받을 수 없다 — 섞여 와도 선물 없음(fetch 가 번호로 버린다) · 모르는 종류도 없음")
    func peperoGiftIsNotForThePhone() throws {
        let derived = ShopWire.protocolVersion(drawableCharacterIDs: AingCharacterArt.knownIDs)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let body = #"{"status":"ok","gift":{"id":"g","kind":"pepero","options":["aing_pepero"],"note":null}}"#
        let offer = try decoder.decode(CharacterGiftPendingResponse.self, from: Data(body.utf8)).offer
        // 새 코어는 종류를 안다 — 하지만 이 번호로는 받을 수 없으므로 서비스(`fetchCharacterGiftPending`)가 띄우지 않는다.
        #expect(offer?.kind == .pepero)
        #expect(offer.map { $0.kind.isSupported(protocolVersion: derived) } == false)
        // 옛 빌드의 두 길 — 둘 다 선물 없음:
        //  · 종류를 아는 코어(맥 0.3.74~0.3.76 · 이슬 코어를 실은 폰)는 모르는 종류를 선물 없음으로 삼킨다. 같은 길: 이 코어가 모르는 종류.
        let unknown = #"{"status":"ok","gift":{"id":"g","kind":"valentine","options":["aing_pepero"],"note":null}}"#
        #expect(try decoder.decode(CharacterGiftPendingResponse.self, from: Data(unknown.utf8)).offer == nil)
        //  · 종류를 모르는 코어(폰 1.0.14~1.0.16 — kind 키를 안 읽는다)는 생일로 읽고 선택지를 케이크로 거른다 → 빼빼로만이면 빈 선택지 → 없음.
        //    같은 길: kind 키가 없는 응답.
        let kindless = #"{"status":"ok","gift":{"id":"g","options":["aing_pepero"],"note":null}}"#
        #expect(try decoder.decode(CharacterGiftPendingResponse.self, from: Data(kindless.utf8)).offer == nil)
    }
}
