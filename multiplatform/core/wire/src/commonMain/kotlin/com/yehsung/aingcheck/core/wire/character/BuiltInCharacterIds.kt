// 원본: Sources/CheckCore/CharacterKit/CharacterCatalog.swift:11-153(내장 id 상수 · 뽑기 전용 · 선물 전용 판정 · 생일/술 목록) @ 12624739
package com.yehsung.aingcheck.core.wire.character

/**
 * 내장 캐릭터 id 와 와이어가 부르는 두 판정(배정표 round5: 와이어 `ShopCharacterRow.isPurchasable/isGiftOnly` ·
 * `CharacterGiftOffer.choosable` 가 부르므로 **core/wire 에 두고**(W1-d) W1-c `CharacterCatalog` 가 다시 쓴다 — rules → wire 한 방향).
 * 내장 여섯의 **표시 순서는 내장 순서**다(정렬에 기대지 않는다).
 */
// INV-CharacterCatalog-ccf7c186 이식: 내장 id 는 매니페스트 파일로 못 싣는다(파일 id 문법 [a-z0-9-]{1,32} — 밑줄 금지) → 코드 상수다.
// INV-CharacterCatalog-d7d845ac 이식: 선물 전용(케이크 · 이슬)과 뽑기 전용(금·무지개)은 겹치지 않는다.
object BuiltInCharacterIds {
    const val builtInAingID = "aing"
    const val goldAingID = "aing_gold"
    const val rainbowAingID = "aing_rainbow"
    const val cakeStrawberryAingID = "aing_cake_strawberry"
    const val cakeChocoAingID = "aing_cake_choco"

    /** 이슬 아잉이(맥 0.3.74 · '술 한잔' 선물 전용). 서버 CHECK·가격표(`gift_only` · `gift_kind = 'drink'`)의 id 와 같다. */
    const val isulAingID = "aing_isul"

    /** 내장 순서(아잉 · 금 · 무지개 · 딸기 · 초코 · 이슬). */
    val builtInIDs: List<String> = listOf(builtInAingID, goldAingID, rainbowAingID, cakeStrawberryAingID, cakeChocoAingID, isulAingID)

    fun isGoldAing(id: String?): Boolean = id == goldAingID
    fun isRainbowAing(id: String?): Boolean = id == rainbowAingID

    /** 뽑기로만 얻는 내장(금·무지개). 서버 `gacha_only` 칸이 없는 옛 응답에서도 상점이 사기 단추를 그리지 않게. */
    fun isGachaOnlyBuiltIn(id: String?): Boolean = isGoldAing(id) || isRainbowAing(id)
    val gachaOnlyBuiltInIDs: List<String> = listOf(goldAingID, rainbowAingID)

    fun isCakeAing(id: String?): Boolean = id == cakeStrawberryAingID || id == cakeChocoAingID

    /** 이슬 아잉이인가(정확히 `aing_isul` 만 — 공백 · 대소문자를 봐주지 않는다). */
    fun isIsulAing(id: String?): Boolean = id == isulAingID

    /**
     * 선물로만 받는 내장 **전부**(케이크 둘 · 이슬 — 뽑기 전용이 아니다). '루비로 못 산다 · 잠긴 칸' 뜻으로만 쓴다.
     * ★ 케이크(생일) 뜻 자리(생일 선물 선택지 · 상점 번호 4 의 재료)에는 [birthdayGiftBuiltInIDs] 를 쓴다 — 이슬을 섞으면 이슬 그림이 없는
     *   빌드가 번호 3 으로 떨어져 케이크 선물까지 잃는다(설계서 isul-aing/SPEC.md §2).
     */
    fun isGiftOnlyBuiltIn(id: String?): Boolean = isCakeAing(id) || isIsulAing(id)

    /** 생일 선물 내장(딸기 → 초코). */
    val birthdayGiftBuiltInIDs: List<String> = listOf(cakeStrawberryAingID, cakeChocoAingID)

    /** 술 한잔 선물 내장(이슬 하나). */
    val drinkGiftBuiltInIDs: List<String> = listOf(isulAingID)

    /** 선물 전용 내장 전부(생일 → 술, 표시 순서) — [isGiftOnlyBuiltIn] 과 같은 집합. */
    val giftOnlyBuiltInIDs: List<String> = birthdayGiftBuiltInIDs + drinkGiftBuiltInIDs
}
