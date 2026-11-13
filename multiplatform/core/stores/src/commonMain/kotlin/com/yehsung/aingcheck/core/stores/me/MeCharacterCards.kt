// 원본: Sources/CheckMobileKit/Me/MeCharacterCards.swift · Sources/CheckMobileKit/Me/MeCharacterCardData.swift(그림 바이트 heicBase64 를 뺀 메타) @ 1b8260d · 928d5562(새 아잉이 넷)
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import com.yehsung.aingcheck.core.rules.character.CharacterSyncDecision

/**
 * 캐릭터 카드 한 장의 메타(아잉 가족 + 스프라이트 캐릭터). 이름은 맥 manifest.json 의 displayName 과 같은 글자다.
 *
 * Swift 판은 카드 그림을 HEIC base64 로 **소스에 박았다**(폰 번들 자리가 기반 소유라). Android·Windows 는 그림을 git 에 두지 않는다(A-X18):
 * 카드 그림은 ui 의 Gradle Sync 가 싣는 초상(`CharacterArt.portraitPath`)이 맡고, 여기에는 id · 이름 · 자르기 값만 남긴다
 * (무지개·케이크 카드 자르기 값은 0.3.59·0.3.66 의 Swift 생성물과 같은 수 — 드리프트는 Swift `MeCharacterCardTests` 가 잰다).
 * 이슬(맥 0.3.74 · Android 판 7)은 Swift 카드 생성물이 아직 없어(아이폰 1.0.17 이 굽는다) 맥 초상 `aing_isul-neutral.png` 의 알파 상자
 * (x 23–168 · y 20–170, 알파 > 0)를 직접 잰 값이다 — Kotlin 은 이 자르기 값을 그리기에 쓰지 않는다(메타).
 */
data class MeCharacterCard(
    val id: String,
    val displayName: String,
    val pixelArt: Boolean,
    /** 알파로 조인 원본 상자 크기(px). */
    val sourceCropWidth: Int,
    val sourceCropHeight: Int,
    /** 구운 카드 그림의 픽셀 크기(최장변 216px). */
    val pixelWidth: Int,
    val pixelHeight: Int,
)

/**
 * 나 탭의 캐릭터 카탈로그(이름). **순서·기본값 규칙은 코어 `CharacterCatalog` 와 같다**: 내장 먼저(그 순서), 나머지 id 정렬.
 * 서버(`shop_state`)가 이 빌드가 모르는 캐릭터를 주면 이름은 id 그대로 — 맥 상점과 같은 관용.
 */
object MeCharacterCards {
    val aingID: String = CharacterCatalog.builtInAingID

    /** Swift `MeCharacterCards.bundled` 의 메타(생성물 — 순서 그대로). */
    val bundled: List<MeCharacterCard> = listOf(
        MeCharacterCard("aing", "아잉", false, 164, 154, 164, 154),
        MeCharacterCard("aing_gold", "황금 아잉이", false, 180, 179, 180, 179),
        MeCharacterCard("aing_rainbow", "무지개 아잉이", false, 180, 179, 180, 179),
        MeCharacterCard("aing_cake_strawberry", "딸기 케이크 아잉이", false, 146, 163, 146, 163),
        MeCharacterCard("aing_cake_choco", "초코 케이크 아잉이", false, 146, 169, 146, 169),
        MeCharacterCard("aing_isul", "이슬 아잉이", false, 146, 151, 146, 151),
        // 판 8(아이폰 1.0.18 맞추기): 폰 MeCharacterCardData.swift 생성물의 자르기 값 그대로(빼빼로는 폰 판 — 상자 글자 없음).
        MeCharacterCard("aing_pepero", "빼빼로 아잉이", false, 168, 160, 168, 160),
        MeCharacterCard("aing_hwoo", "흑우 아잉이", false, 164, 154, 164, 154),
        MeCharacterCard("aing_ruby", "루비 아잉이", false, 166, 152, 166, 152),
        MeCharacterCard("aing_dev", "개발에 찌든 아잉이", false, 166, 152, 166, 152),
        MeCharacterCard("fox", "여우", false, 444, 512, 187, 216),
        MeCharacterCard("ghost", "유령", false, 504, 512, 213, 216),
        MeCharacterCard("jellyfish", "해파리", false, 444, 512, 187, 216),
        MeCharacterCard("robot", "로봇", false, 420, 512, 177, 216),
        MeCharacterCard("shiba", "강아지", false, 402, 512, 170, 216),
        MeCharacterCard("squirrel", "다람쥐", false, 373, 512, 157, 216),
    )

    fun card(id: String): MeCharacterCard? = bundled.firstOrNull { it.id == id }

    fun displayName(id: String): String = card(id)?.displayName ?: id

    /**
     * 이 빌드가 아는 캐릭터 id — 코어 `CharacterCatalog.allIDs` 와 같은 순서: 내장(아잉 · 황금 · 무지개 · 딸기 케이크 · 초코 케이크 · 이슬)이 그 순서로
     * 먼저, 나머지는 정렬(케이크 둘은 정렬이면 금보다 앞이고 초코가 딸기보다 앞이라 내장 순서로 박는다).
     */
    val knownIDs: List<String>
        get() {
            val ids = bundled.map { it.id }
            val builtIns = CharacterCatalog.builtIns.map { it.id }.filter { it in ids }
            return builtIns + ids.filter { it !in builtIns }.sorted()
        }

    /** 카드 표에 있는가(이름 · 자르기 메타 — 플랫폼과 무관). 착용값 접기 · 고르기 목록은 [isKnown] 의 두 인자 판을 쓴다. */
    fun isKnown(id: String): Boolean = card(id) != null

    /**
     * 이 플랫폼이 아는 캐릭터 id — [knownIDs] 에서 술 한잔 선물 캐릭터(이슬)는 그 선물을 받는 플랫폼([takesDrinkGift] — Android 판 7)에만 남긴다.
     * 번호 4 플랫폼(Windows v1)은 0.3.73 처럼 이슬을 모른다: 서버가 이슬 행을 가진 사람에게도 안 싣는 상대라(20261108122000 §5-2) 알면 잠긴
     * '착용 중' 칸이 선다(검토 ISUL-1). 문은 나 탭 스토어가 쥔 그림 재료의 [DrawableCharacterSource.takesDrinkGift] 하나다.
     */
    fun knownIDs(takesDrinkGift: Boolean): List<String> =
        if (takesDrinkGift) knownIDs else knownIDs.filter { it !in protocolFivePlusIDs }

    /** [knownIDs] (두 인자 판)에 드는가. */
    fun isKnown(id: String, takesDrinkGift: Boolean): Boolean =
        isKnown(id) && (takesDrinkGift || id !in protocolFivePlusIDs)

    /**
     * 상점 번호 5 이상에서만 서버가 싣는 내장(이슬 · 빼빼로 · 흑우 · 루비 · 개발) — 번호 4 플랫폼(Windows v1)은 이들을 모른다(서버가 그 행을
     * 가진 사람에게도 안 싣는 상대라, 알면 잠긴 '착용 중' 칸이 선다 — 검토 ISUL-1 과 같은 사정).
     */
    private val protocolFivePlusIDs: Set<String> = (
        CharacterCatalog.drinkGiftBuiltInIDs + CharacterCatalog.peperoGiftBuiltInIDs + CharacterCatalog.shardOnlyBuiltInIDs +
            CharacterCatalog.shopBuiltInIDs + CharacterCatalog.devBuiltInIDs
        ).toSet()

    /**
     * 서버 착용값 → 화면에 세울 id. 비었거나 이 플랫폼이 모르는 id 면 아잉(서버 값은 건드리지 않는다). 술 한잔 선물을 안 받는 플랫폼은
     * 이슬도 아잉으로 접는다(0.3.73 과 같다 — 서버 설계 전제 '옛 클라는 모르는 착용 id 를 아잉으로 접는다').
     */
    fun equippedID(fromServer: String?, takesDrinkGift: Boolean): String {
        val id = CharacterSyncDecision.normalized(fromServer) ?: return aingID
        return if (isKnown(id, takesDrinkGift)) id else aingID
    }
}
