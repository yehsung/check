// 원본: Sources/CheckCore/ShopProtocol.swift @ 12624739(이슬 번호 5)
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
    /**
     * 이 번호를 요구하는 캐릭터 — **케이크 둘**(딸기 → 초코 · `CharacterCatalog.birthdayGiftBuiltInIDs`).
     * ★ 선물 전용 **전부**(`giftOnlyBuiltInIDs` — 이슬까지)가 아니다. 이슬을 섞으면 이슬 초상이 없는 빌드가 4 대신 3 을 말해 케이크 선물까지
     *   잃는다(설계서 isul-aing/SPEC.md §2). 그래서 케이크 둘로 고정한다.
     */
    val cakeCharacterIDs: List<String> get() = CharacterCatalog.birthdayGiftBuiltInIDs

    /**
     * 이슬 아잉이(맥 0.3.74 '술 한잔' 선물 전용)가 든 명단과 술 선물(`character_gift_pending` 의 `kind = 'drink'` · 그 수령)을 받을 수 있는 번호.
     * 서버 `character_prices.min_protocol = 5` 인 행이 이슬이고, 5 미만이면 그 행이 **가진 사람에게도** 안 보이며(20261108122000 §5-2),
     * 선물 조회는 생일 종류만 싣고(4), 술 선물 수령은 `needs_update{5}` 로 거절한다.
     */
    const val isulProtocol = 5
    /** 이 번호를 요구하는 캐릭터 — 이슬 하나(`CharacterCatalog.drinkGiftBuiltInIDs`). */
    val isulCharacterIDs: List<String> get() = CharacterCatalog.drinkGiftBuiltInIDs

    /**
     * 그릴 수 있는 id 들 → 서버에 말할 번호.
     * INV-ShopProtocol-c8e9aa64 이식: **번호는 누적이다** — 서버 게이트는 `min_protocol <= p_protocol` 이라 2 를 보내면 1 짜리(robot)도 받는다.
     * 그래서 앞 번호의 캐릭터를 전부 그릴 수 있을 때만 다음 번호를 말한다(건너뛰어 말할 수 없다 — 보수적인 쪽으로 틀린다). 4 는 케이크 **둘 다**,
     * 5 는 여기까지 전부 **와** 이슬(로봇 · 금 · 무지개 · 케이크 둘 · 이슬을 전부 그리는 빌드). 이슬만 있고 케이크가 하나라도 빠지면 3 에 머문다.
     */
    fun protocolVersion(drawableCharacterIDs: Iterable<String>): Int {
        val drawable = drawableCharacterIDs.toSet()
        if (robotCharacterID !in drawable) return legacyProtocol
        if (goldCharacterID !in drawable) return robotProtocol
        if (rainbowCharacterID !in drawable) return goldProtocol
        if (!cakeCharacterIDs.all { it in drawable }) return rainbowProtocol
        return if (isulCharacterIDs.all { it in drawable }) isulProtocol else cakeProtocol
    }

    /** 생일 선물을 조회 · 수령할 수 있는가(서버 문턱 `p_protocol >= 4`). 판정의 권위는 서버다 — 헛왕복을 줄이는 문이다. */
    fun supportsCakeGift(protocolVersion: Int): Boolean = protocolVersion >= cakeProtocol

    /**
     * 술 한잔 선물(이슬 아잉이)을 받을 수 있는가(서버 술 선물 수령 문턱 `p_protocol >= 5`). 조회 자체의 문은 여전히 [supportsCakeGift](4)다 —
     * 4 인 빌드는 생일 선물만 받는다. 이 값은 '다음 선물' 되묻기의 문이다(서버는 한 번에 하나만 내린다).
     */
    fun supportsDrinkGift(protocolVersion: Int): Boolean = protocolVersion >= isulProtocol

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
