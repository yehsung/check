import Foundation

// MARK: - 상점 프로토콜 (v0.3.43 로봇)
//
// 서버 `character_roster_v3_robot` 가 `shop_state()` → `shop_state(p_protocol int default 0)` 로,
// `buy_character(p_id)` → `buy_character(p_id, p_protocol int default 0)` 로 바뀐다.
// 0 이면 목록에서 robot 이 **조용히 빠지고**(거절이 아니다 — 거절하면 옛 클라의 상점이 통째로 죽는다),
// robot 을 0 으로 사려 하면 `needs_update` 로 거절되고 루비는 안 깎인다.

/// 상점 RPC 가 서버에 말하는 **능력 번호**. 숫자를 고르는 자리는 이 타입 하나다.
///
/// ── 왜 번호를 상수로 박지 않는가 ──
/// `fetchShopState`·`buyCharacter` 는 맥과 폰이 **공유한다**(CheckCore). 번호를 박아 두면 그림이 아직 없는 쪽도
/// 1 을 보내고, 서버는 그걸 "너는 robot 을 그릴 수 있다"로 읽어 카드를 내려 보낸다. 그 카드는 폰에서
/// **아잉 그림**으로 뜨고(모르는 id → 아잉 접기), 사면 루비만 빠진 채 착용해도 아무 일이 안 생긴다
/// (mapC §7 ③④ 실측). 그래서 번호는 언제나 "**내가 그 캐릭터를 그릴 수 있는가**"에서 파생시킨다 —
/// 판정 자리는 `protocolVersion(drawableCharacterIDs:)` 하나뿐이고, 테스트가 그 동치를 양방향으로 못 박는다.
package nonisolated enum ShopWire {
    /// `p_protocol` 을 **안 싣는** 옛 모양과 같은 값. 서버 인자 기본값이 0 이라 `{}` 와 뜻이 완전히 같다 —
    /// 그래서 이 값일 때는 키를 아예 싣지 않는다(안 그러면 아직 안 올라간 서버에서 공짜로 404 를 한 번 맞는다).
    package static let legacyProtocol = 0

    /// robot 이 들어간 명단(서버 roster v3)을 받을 수 있는 번호.
    package static let robotProtocol = 1

    /// 이 번호를 요구하는 캐릭터. 서버 `character_prices.min_protocol = 1` 인 행과 같은 id 다.
    package static let robotCharacterID = "robot"

    /// 이 빌드가 **그릴 수 있는** 캐릭터 id 들 → 서버에 말할 번호.
    ///
    /// 맥은 번들 카탈로그(`CharacterCatalog.allIDs` — `Characters/<id>/manifest.json` 이 실재하는 id)가,
    /// 폰은 `AingCharacterArt.knownIDs`(번들 초상이 있는 id)가 답을 안다. 둘 다 "그림이 있다"의 정본이라
    /// 그림이 번들에 들어오는 순간 이 값이 저절로 1 이 되고, 그 전에는 저절로 0 이다.
    package static func protocolVersion(drawableCharacterIDs: some Sequence<String>) -> Int {
        drawableCharacterIDs.contains(where: { $0 == robotCharacterID }) ? robotProtocol : legacyProtocol
    }
}
