// 원본: Sources/CheckCore/CharacterKit/CharacterCatalog.swift(내장 id 상수 · 뽑기 전용 · 선물 전용 판정 · 생일/술/빼빼로/지역 목록 · 조각 전용 · 미션 보상) @ e4995a3a
package com.yehsung.aingcheck.core.wire.character

/**
 * 내장 캐릭터 id 와 와이어가 부르는 두 판정(배정표 round5: 와이어 `ShopCharacterRow.isPurchasable/isGiftOnly` ·
 * `CharacterGiftOffer.choosable` 가 부르므로 **core/wire 에 두고**(W1-d) W1-c `CharacterCatalog` 가 다시 쓴다 — rules → wire 한 방향).
 * 내장 열둘의 **표시 순서는 내장 순서**다(정렬에 기대지 않는다).
 */
// INV-CharacterCatalog-ccf7c186 이식: 내장 id 는 매니페스트 파일로 못 싣는다(파일 id 문법 [a-z0-9-]{1,32} — 밑줄 금지) → 코드 상수다.
// INV-CharacterCatalog-d7d845ac 이식: 선물 전용(케이크 · 이슬 · 빼빼로 · 지역)과 뽑기 전용(금 · 무지개 · 흑우)은 겹치지 않는다.
object BuiltInCharacterIds {
    const val builtInAingID = "aing"
    const val goldAingID = "aing_gold"
    const val rainbowAingID = "aing_rainbow"
    const val cakeStrawberryAingID = "aing_cake_strawberry"
    const val cakeChocoAingID = "aing_cake_choco"

    /** 이슬 아잉이(맥 0.3.74 · '술 한잔' 선물 전용). 서버 CHECK·가격표(`gift_only` · `gift_kind = 'drink'`)의 id 와 같다. */
    const val isulAingID = "aing_isul"

    /** 빼빼로 아잉이(맥 0.3.77 · 11-11 빼빼로 데이 기간 선물 전용 — `gift_kind = 'pepero'`). Android 판 8 · 폰 1.0.18 은 상자에 글자 없는 그림. */
    const val peperoAingID = "aing_pepero"

    /** 빼빼로 아잉이의 표시 이름 — 한 곳('빼빼로'는 남의 상표라 바뀔 수 있다). 카탈로그 이름 · 받는 창 본문이 이 값을 읽는다. */
    const val peperoAingDisplayName = "빼빼로 아잉이"

    /** 흑우 아잉이(맥 0.3.78 · **조각 20개로만** 바꾼다 — 서버 `gacha_only` · `min_protocol = 7` · 뽑기 확률 0). */
    const val hwooAingID = "aing_hwoo"

    /** 루비 아잉이(맥 0.3.78 · 상점 **루비 1000개** — 서버 `min_protocol = 8`, 뽑기 · 선물 표식 없음). */
    const val rubyAingID = "aing_ruby"

    /** 개발에 찌든 아잉이(맥 0.3.81 · 도전 미션 '누적 근무 100시간' 보상 — 서버 `min_protocol = 9`). 원본 `DevAingArt.characterID`. */
    const val devAingID = "aing_dev"

    /** 부산 갈매기 아잉이(지역 아잉이 — 부산 센터 선물, 번호 10). Android 는 그림을 싣지 않아 번호 10 을 말하지 않는다(서버가 안 보낸다). */
    const val busanAingID = RegionAingNames.busanID

    /** 서울의 밤 아잉이(지역 아잉이 — 서울 센터 선물, 번호 10). 부산과 같다. */
    const val seoulAingID = RegionAingNames.seoulID

    /**
     * 내장 순서(아잉 · 금 · 무지개 · 딸기 · 초코 · 이슬 · 빼빼로 · 흑우 · 루비 · 개발 · 부산 · 서울) — 맥 `CharacterCatalog.builtIns` 그대로.
     * 지역 둘은 Android 에 그림이 없어도 목록에는 선다(남이 입은 지역 아잉이 id 를 '모르는 값'으로 접지 않는다 — 그림은 아잉으로 폴백).
     */
    val builtInIDs: List<String> = listOf(
        builtInAingID, goldAingID, rainbowAingID, cakeStrawberryAingID, cakeChocoAingID, isulAingID,
        peperoAingID, hwooAingID, rubyAingID, devAingID, busanAingID, seoulAingID,
    )

    fun isGoldAing(id: String?): Boolean = id == goldAingID
    fun isRainbowAing(id: String?): Boolean = id == rainbowAingID

    /** 흑우 아잉이인가(정확히 `aing_hwoo` 만). */
    fun isHwooAing(id: String?): Boolean = id == hwooAingID

    /** 루비 아잉이인가(정확히 `aing_ruby` 만). */
    fun isRubyAing(id: String?): Boolean = id == rubyAingID

    /** 개발에 찌든 아잉이인가(정확히 `aing_dev` 만). */
    fun isDevAing(id: String?): Boolean = id == devAingID

    /**
     * 루비로 **절대** 안 파는 내장(금 · 무지개 · 흑우). 서버 `gacha_only` 칸이 없는 옛 응답에서도 상점이 사기 단추를 그리지 않게.
     * 흑우는 여기에 들지만 뽑기에는 안 나온다(확률 0 — [isShardOnlyBuiltIn]).
     */
    fun isGachaOnlyBuiltIn(id: String?): Boolean = isGoldAing(id) || isRainbowAing(id) || isHwooAing(id)
    val gachaOnlyBuiltInIDs: List<String> = listOf(goldAingID, rainbowAingID, hwooAingID)

    /** **조각 교환으로만** 얻는 내장(흑우) — 뽑기 전용의 부분집합. 얻는 길 문구가 "조각 N개로 교환"이 된다. */
    fun isShardOnlyBuiltIn(id: String?): Boolean = isHwooAing(id)

    /** 조각 교환 전용 내장 — 흑우 하나. 상점 번호 7 의 재료다. */
    val shardOnlyBuiltInIDs: List<String> = listOf(hwooAingID)

    /** 루비로 사는 내장 — 루비 아잉이 하나. 상점 번호 8 의 재료다. */
    val shopBuiltInIDs: List<String> = listOf(rubyAingID)

    /** 개발에 찌든 아잉이 — 상점 번호 9 의 재료다. */
    val devBuiltInIDs: List<String> = listOf(devAingID)

    /**
     * 도전 미션 보상으로만 얻는 내장(개발 아잉이). 상점에서 못 사고 뽑기 · 조각 · 선물에도 없다 — 서버 행은 판매를 막으려고 `gacha_only = true` 를
     * 싣지만 **뽑기 전용이 아니다**(`ShopCharacterRow.isGachaOnly` 가 이 판정으로 거른다 — 케이크와 같은 사정).
     */
    fun isMissionRewardBuiltIn(id: String?): Boolean = isDevAing(id)

    fun isCakeAing(id: String?): Boolean = id == cakeStrawberryAingID || id == cakeChocoAingID

    /** 이슬 아잉이인가(정확히 `aing_isul` 만 — 공백 · 대소문자를 봐주지 않는다). */
    fun isIsulAing(id: String?): Boolean = id == isulAingID

    /** 빼빼로 아잉이인가(정확히 `aing_pepero` 만). */
    fun isPeperoAing(id: String?): Boolean = id == peperoAingID

    fun isBusanAing(id: String?): Boolean = id == busanAingID
    fun isSeoulAing(id: String?): Boolean = id == seoulAingID

    /** 지역 아잉이(부산 · 서울)인가 — 센터 선물 전용. */
    fun isRegionAing(id: String?): Boolean = isBusanAing(id) || isSeoulAing(id)

    /**
     * 선물로만 받는 내장 **전부**(케이크 둘 · 이슬 — 뽑기 전용이 아니다). '루비로 못 산다 · 잠긴 칸' 뜻으로만 쓴다.
     * ★ 케이크(생일) 뜻 자리(생일 선물 선택지 · 상점 번호 4 의 재료)에는 [birthdayGiftBuiltInIDs] 를 쓴다 — 이슬을 섞으면 이슬 그림이 없는
     *   빌드가 번호 3 으로 떨어져 케이크 선물까지 잃는다(설계서 isul-aing/SPEC.md §2).
     */
    fun isGiftOnlyBuiltIn(id: String?): Boolean = isCakeAing(id) || isIsulAing(id) || isPeperoAing(id) || isRegionAing(id)

    /** 생일 선물 내장(딸기 → 초코). */
    val birthdayGiftBuiltInIDs: List<String> = listOf(cakeStrawberryAingID, cakeChocoAingID)

    /** 술 한잔 선물 내장(이슬 하나). */
    val drinkGiftBuiltInIDs: List<String> = listOf(isulAingID)

    /** 빼빼로 데이 선물 내장(빼빼로 하나). 빼빼로 뜻 자리(상점 번호 6 · 빼빼로 선물 선택지)는 이 목록이다. */
    val peperoGiftBuiltInIDs: List<String> = listOf(peperoAingID)

    /** 우리 센터 선물(지역 아잉이) 내장 — 부산 → 서울. 지역 뜻 자리(번호 10)는 이 목록이다 — 두 센터 그림이 다 붙어야 10 을 말한다. */
    val regionGiftBuiltInIDs: List<String> = listOf(busanAingID, seoulAingID)

    /** 선물 전용 내장 전부(생일 → 술 → 빼빼로 → 지역, 표시 순서) — [isGiftOnlyBuiltIn] 과 같은 집합. */
    val giftOnlyBuiltInIDs: List<String> = birthdayGiftBuiltInIDs + drinkGiftBuiltInIDs + peperoGiftBuiltInIDs + regionGiftBuiltInIDs
}
