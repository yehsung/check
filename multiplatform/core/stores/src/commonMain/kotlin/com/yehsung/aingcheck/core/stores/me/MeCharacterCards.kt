// 원본: Sources/CheckMobileKit/Me/MeCharacterCards.swift · Sources/CheckMobileKit/Me/MeCharacterCardData.swift(그림 바이트 heicBase64 를 뺀 메타) @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import com.yehsung.aingcheck.core.rules.character.CharacterSyncDecision

/**
 * 캐릭터 카드 한 장의 메타(아잉 가족 + 스프라이트 캐릭터). 이름은 맥 manifest.json 의 displayName 과 같은 글자다.
 *
 * Swift 판은 카드 그림을 HEIC base64 로 **소스에 박았다**(폰 번들 자리가 기반 소유라). Android·Windows 는 그림을 git 에 두지 않는다(A-X18):
 * 카드 그림은 ui 의 Gradle Sync 가 싣는 초상(`CharacterArt.portraitPath`)이 맡고, 여기에는 id · 이름 · 자르기 값만 남긴다
 * (무지개·케이크 카드 자르기 값은 0.3.59·0.3.66 의 Swift 생성물과 같은 수 — 드리프트는 Swift `MeCharacterCardTests` 가 잰다).
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
     * 이 빌드가 아는 캐릭터 id — 코어 `CharacterCatalog.allIDs` 와 같은 순서: 내장(아잉 · 황금 · 무지개 · 딸기 케이크 · 초코 케이크)이 그 순서로
     * 먼저, 나머지는 정렬(케이크 둘은 정렬이면 금보다 앞이고 초코가 딸기보다 앞이라 내장 순서로 박는다).
     */
    val knownIDs: List<String>
        get() {
            val ids = bundled.map { it.id }
            val builtIns = CharacterCatalog.builtIns.map { it.id }.filter { it in ids }
            return builtIns + ids.filter { it !in builtIns }.sorted()
        }

    fun isKnown(id: String): Boolean = card(id) != null

    /** 서버 착용값 → 화면에 세울 id. 비었거나 이 빌드가 모르는 id 면 아잉(서버 값은 건드리지 않는다). */
    fun equippedID(fromServer: String?): String {
        val id = CharacterSyncDecision.normalized(fromServer) ?: return aingID
        return if (isKnown(id)) id else aingID
    }
}
