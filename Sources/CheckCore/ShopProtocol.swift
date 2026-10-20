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

    /// 황금 아잉이(v0.3.54)가 든 명단 + 뽑기(`shop_state.gacha` · `gacha_pull` · `gacha_exchange`)를 받을 수 있는 번호.
    /// 서버 `character_prices.min_protocol = 2` 인 행이 aing_gold 이고, 뽑기 RPC 는 `p_protocol >= 2` 가 아니면
    /// `needs_update` 로 거절한다(루비는 안 깎인다). `shop_state` 는 2 미만이면 `gacha` 키를 아예 안 싣는다 —
    /// 그래서 이 번호가 2 가 아닌 빌드는 **뽑기 화면이 통째로 안 보인다**(클라는 `gacha` 가 없으면 숨긴다).
    package static let goldProtocol = 2

    /// 이 번호를 요구하는 캐릭터. `CharacterCatalog.goldAingID` 와 같은 값이다(서버 CHECK·가격표의 id).
    package static let goldCharacterID = CharacterCatalog.goldAingID

    /// 무지개 아잉이(v0.3.59)가 든 명단 · 확률표 · 교환표를 받을 수 있는 번호. 서버 `character_prices.min_protocol = 3` 인 행이
    /// aing_rainbow 이고, 서버는 이 번호 미만인 클라에게 그 행을 **아예 안 보인다**(목록 · 확률표 · 교환표에서 빠지고, 뽑기도 그 클라가
    /// 쓸 수 있는 행만으로 추첨한다 — 2 인 클라의 확률표는 합 98 을 100 으로 다시 나눈 소수다). 뽑기 문턱(`supportsGacha`)은 2 그대로다.
    package static let rainbowProtocol = 3

    /// 이 번호를 요구하는 캐릭터. `CharacterCatalog.rainbowAingID` 와 같은 값이다.
    package static let rainbowCharacterID = CharacterCatalog.rainbowAingID

    /// 이 빌드가 **그릴 수 있는** 캐릭터 id 들 → 서버에 말할 번호.
    ///
    /// 맥은 `CheckMascotAssets.drawableCharacterIDs`(초상·아틀라스 **파일 실재**)가, 폰은 `AingCharacterArt.knownIDs`
    /// (번들 초상이 있는 id)가 답을 안다. 둘 다 "그림이 있다"의 정본이라 그림이 번들에 들어오는 순간 이 값이 저절로
    /// 오르고, 그 전에는 저절로 낮다. 황금 아잉이가 "그릴 수 있다"의 정의는 `GoldAingArt` 가 한 곳에서 말한다
    /// (폰 = 초상 두 장, 맥 = 초상 두 장 + 3D 마감 두 장).
    ///
    /// ★ **번호는 누적이다.** 서버 게이트는 `min_protocol <= p_protocol` 이라 2 를 보내면 1 짜리(robot)도 받는다.
    ///   그래서 2 는 "aing_gold **와** robot 을 둘 다 그릴 수 있다"일 때만 보낸다 — 금 그림만 있고 robot 이 없는 번들이
    ///   2 를 보내면 robot 카드가 아잉 그림으로 팔린다(v0.3.43 이 막은 바로 그 사고). 그 번들은 0 이다
    ///   (robot 이 없으면 1 도 못 보내고, 2 를 건너뛰어 말할 수도 없다 — 보수적인 쪽으로 틀린다).
    ///   3(v0.3.59)도 같다: robot · aing_gold · aing_rainbow 를 **셋 다** 그릴 수 있을 때만. 무지개만 있고 금이 없으면 2 도 못 보내
    ///   robot 까지의 번호(1 또는 0)에 머문다 — 무지개 그림이 없는 빌드가 3 을 보내면 아잉 그림의 '무지개 아잉이'를 뽑게 된다.
    package static func protocolVersion(drawableCharacterIDs: some Sequence<String>) -> Int {
        let drawable = Set(drawableCharacterIDs)
        guard drawable.contains(robotCharacterID) else { return legacyProtocol }
        guard drawable.contains(goldCharacterID) else { return robotProtocol }
        return drawable.contains(rainbowCharacterID) ? rainbowProtocol : goldProtocol
    }

    /// 이 번호로 뽑기를 쓸 수 있는가(서버 `gacha_pull`·`gacha_exchange` 의 `p_protocol >= 2` 와 같은 문턱).
    /// 화면을 여는 판정은 이것이 아니라 **`shop_state.gacha` 의 유무**다 — 서버가 꺼 두면 번호가 2 여도 없다.
    package static func supportsGacha(protocolVersion: Int) -> Bool {
        protocolVersion >= goldProtocol
    }
}
