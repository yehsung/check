@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 이슬 아잉이(맥 0.3.74 먼저 — 폰은 다음 폰 판)가 공용 코어에 들어와도 **폰의 능력 번호는 4 그대로**라는 못.
//
// 사용자 결정(2026-11-03 "맥 먼저, 폰은 다음 폰 판에 모아서"): 이번엔 폰 초상 · 폰 화면 · 폰 번호를 올리지 않는다.
// 코어 카탈로그(`CharacterCatalog.builtIns`)에 이슬이 붙어도 폰의 "그릴 수 있다"(`AingCharacterArt.knownIDs`)는 번들 초상에서만 오므로
// 이슬이 없고, 번호는 케이크까지인 4 다. 코어가 `cakeCharacterIDs` 에 이슬을 섞으면(설계서 §2 함정) 이 시험이 3 으로 잡는다.
@Suite("이슬 아잉이 — 폰 능력 번호 4 고정")
struct MeIsulProtocolPinTests {
    @Test("폰 knownIDs 에 이슬이 없다 → 번호 4 · 케이크 선물은 그대로 · 술 선물은 아니다 · 스토어 번호도 4")
    @MainActor
    func phoneProtocolStaysFour() {
        let known = AingCharacterArt.knownIDs
        #expect(!known.contains(CharacterCatalog.isulAingID), Comment(rawValue: "\(known)"))
        let derived = ShopWire.protocolVersion(drawableCharacterIDs: known)
        #expect(derived == ShopWire.cakeProtocol, Comment(rawValue: "목록 \(known) → \(derived)"))
        #expect(ShopWire.supportsCakeGift(protocolVersion: derived))
        #expect(!ShopWire.supportsDrinkGift(protocolVersion: derived))
        #expect(!CharacterGiftKind.drink.isSupported(protocolVersion: derived))
        // 폰 카드 목록(번들 초상 기준)에도 이슬이 없다 — 고르기 · 상점 자리표시에 서지 않는다.
        #expect(!MeCharacterCards.knownIDs.contains(CharacterCatalog.isulAingID))
        // 반대 방향: 폰에 이슬 초상이 생기는 날(다음 폰 판) 번호는 저절로 5 가 된다.
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: known + [CharacterCatalog.isulAingID]) == ShopWire.isulProtocol)
    }
}
