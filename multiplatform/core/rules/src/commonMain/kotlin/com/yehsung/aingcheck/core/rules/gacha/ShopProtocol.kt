// 원본: Sources/CheckCore/ShopProtocol.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.gacha

import com.yehsung.aingcheck.core.rules.character.CharacterCatalog

/**
 * 상점 RPC 가 서버에 말하는 **능력 번호**(K9). 번호는 언제나 "**내가 그 캐릭터를 그릴 수 있는가**"에서 파생시킨다 — 상수로 박으면
 * 그림이 없는 빌드가 그 캐릭터 카드를 받고, 그 카드는 아잉 그림으로 팔린다(v0.3.43 사고).
 * Android·Windows 의 "그릴 수 있다" = 번들에 그 id 의 초상 두 장이 실재한다(G §8-7 — 첫 판 정의는 초상만, 폰과 같다).
 */
object ShopWire {
    /** `p_protocol` 을 **안 싣는** 옛 모양과 같은 값(서버 인자 기본값 0 — `{}` 와 같은 뜻이라 키를 아예 싣지 않는다). */
    const val legacyProtocol = 0
    const val robotProtocol = 1
    const val robotCharacterID = "robot"
    /** 황금 아잉이 + 뽑기(`shop_state.gacha` · `gacha_pull` · `gacha_exchange`). 2 미만이면 서버가 gacha 키를 아예 안 싣는다. */
    const val goldProtocol = 2
    val goldCharacterID: String get() = CharacterCatalog.goldAingID
    /** 무지개 아잉이(v0.3.59) — 이 번호 미만인 클라에게 서버는 그 행을 아예 안 보인다. */
    const val rainbowProtocol = 3
    val rainbowCharacterID: String get() = CharacterCatalog.rainbowAingID
    /** 케이크 아잉이 둘(v0.3.66) + 생일 선물(`character_gift_pending` · `claim_character_gift`). */
    const val cakeProtocol = 4
    /** 이 번호를 요구하는 캐릭터 — **둘 다**(딸기 → 초코). */
    val cakeCharacterIDs: List<String> get() = CharacterCatalog.giftOnlyBuiltInIDs

    /**
     * 그릴 수 있는 id 들 → 서버에 말할 번호.
     * INV-ShopProtocol-c8e9aa64 이식: **번호는 누적이다** — 서버 게이트는 `min_protocol <= p_protocol` 이라 2 를 보내면 1 짜리(robot)도 받는다.
     * 그래서 앞 번호의 캐릭터를 전부 그릴 수 있을 때만 다음 번호를 말한다(건너뛰어 말할 수 없다 — 보수적인 쪽으로 틀린다). 4 는 케이크 **둘 다**.
     */
    fun protocolVersion(drawableCharacterIDs: Iterable<String>): Int {
        val drawable = drawableCharacterIDs.toSet()
        if (robotCharacterID !in drawable) return legacyProtocol
        if (goldCharacterID !in drawable) return robotProtocol
        if (rainbowCharacterID !in drawable) return goldProtocol
        return if (cakeCharacterIDs.all { it in drawable }) cakeProtocol else rainbowProtocol
    }

    /** 생일 선물을 조회 · 수령할 수 있는가(서버 문턱 `p_protocol >= 4`). 판정의 권위는 서버다 — 헛왕복을 줄이는 문이다. */
    fun supportsCakeGift(protocolVersion: Int): Boolean = protocolVersion >= cakeProtocol

    /** 뽑기를 쓸 수 있는가(`p_protocol >= 2`). 화면을 여는 판정은 이것이 아니라 `shop_state.gacha` 의 유무다. */
    fun supportsGacha(protocolVersion: Int): Boolean = protocolVersion >= goldProtocol

    /**
     * 플랫폼 그림 집합 → 그릴 수 있는 id(G §8-7 ③). 초상 두 장(`<id>-neutral` · `<id>-negative`)이 다 있는 id 만.
     * Android 는 ui 의 Gradle Sync 로 실린 초상(CharacterArt.portraitIds), Windows 첫 판도 같다. 그림을 지운 빌드는 번호가 내려간다.
     */
    fun drawableCharacterIDs(portraitResourceNames: Iterable<String>): Set<String> {
        val names = portraitResourceNames.toSet()
        val ids = HashSet<String>()
        for (name in names) {
            if (!name.endsWith("-neutral")) continue
            val id = name.removeSuffix("-neutral")
            if ("$id-negative" in names) ids += id
        }
        return ids
    }
}
