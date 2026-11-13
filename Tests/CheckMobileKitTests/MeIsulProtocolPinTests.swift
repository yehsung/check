@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 이슬 아잉이(맥 0.3.74 먼저 → 폰 1.0.17)가 폰 번들에 들어와 **폰의 능력 번호가 5** 라는 못.
//
// 사용자 결정(2026-11-03 "맥 먼저, 폰은 다음 폰 판에 모아서" → 폰 1.0.17 판 "그대로 + 대체 그림 미리 준비" #d_dk4IjWRZvFYR):
// 폰의 "그릴 수 있다"(`AingCharacterArt.knownIDs`)는 번들 초상에서만 오고, 이슬 초상 두 장이 들어온 이 판부터 번호가 저절로 5 다.
// 번호를 적는 자리는 없다 — 목록에서 파생된다. 그래서 반대 방향도 잰다: 이슬 하나만 빠져도 4, 케이크 하나만 빠져도(이슬이 있어도) 3 이다
// (코어가 `cakeCharacterIDs` 에 이슬을 섞는 설계서 §2 함정이 되살아나면 이 시험이 잡는다).
@Suite("이슬 아잉이 — 폰 능력 번호 5")
struct MeIsulProtocolPinTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func portraitFileExists(_ id: String) -> Bool {
        AingCharacterArt.Expression.allCases.allSatisfy { expression in
            FileManager.default.fileExists(atPath: root
                .appendingPathComponent("Sources/CheckMobileShared/Resources/Portraits/\(id)-\(expression.rawValue).png").path)
        }
    }

    @Test("폰 knownIDs 에 이슬이 있다 → 번호는 5 이상(1.0.18 은 9) · 생일 · 술 선물 둘 다 · 카드 표도 이슬을 안다 · 이슬 하나만 빠져도 4")
    @MainActor
    func phoneProtocolIsFive() {
        let known = AingCharacterArt.knownIDs
        #expect(known.contains(CharacterCatalog.isulAingID), Comment(rawValue: "\(known)"))
        // 초상 파일 ⟺ 목록: 이름만 더하면 아잉 그림의 '이슬 아잉이'를 받는다(위 머리말 · `AingCharacterArt.knownIDs` 주석).
        #expect(Self.portraitFileExists(CharacterCatalog.isulAingID), "이슬 초상 두 장이 폰 번들에 없다")
        let derived = ShopWire.protocolVersion(drawableCharacterIDs: known)
        // 1.0.18 은 빼빼로 · 흑우 · 루비 · 개발까지 그려 9 다(`MePeperoProtocolPinTests`) — 이슬 문(5)은 누적이라 넘는다.
        #expect(derived == ShopWire.devProtocol, Comment(rawValue: "목록 \(known) → \(derived)"))
        #expect(ShopWire.supportsCakeGift(protocolVersion: derived))
        #expect(ShopWire.supportsDrinkGift(protocolVersion: derived))
        #expect(CharacterGiftKind.drink.isSupported(protocolVersion: derived))
        // 폰 카드 목록(번들 카드 기준)에도 이슬이 있다 — 착용값이 아잉으로 접히지 않고 고르기 · 상점 자리표시에 선다.
        #expect(MeCharacterCards.knownIDs.contains(CharacterCatalog.isulAingID))
        #expect(MeCharacterCards.equippedID(fromServer: CharacterCatalog.isulAingID) == CharacterCatalog.isulAingID)
        // 반대 방향: 이슬 하나만 빠지면 4(케이크까지) — 번호가 목록에서 파생된다는 증거.
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: known.filter { $0 != CharacterCatalog.isulAingID }) == ShopWire.cakeProtocol)
        // 케이크 하나가 빠지면 이슬이 있어도 3(번호를 건너뛰어 말할 수 없다).
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: known.filter { $0 != CharacterCatalog.cakeChocoAingID }) == ShopWire.rainbowProtocol)
    }

    @Test("스토어가 싣는 번호도 번들 번호다(1.0.18 = 9 · 번호를 박지 않는다 — `MeStore.drawableCharacterIDs` 기본값이 이 목록)")
    @MainActor
    func storeProtocolIsFive() async {
        let harness = await RankMeHarness(label: "me-isul-protocol") { _ in nil }
        defer { harness.tearDown() }
        #expect(harness.me.shopProtocolVersion == ShopWire.devProtocol)
    }
}
