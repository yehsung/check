// 원본: Sources/CheckMobileKit/Me/MeCharacterViews.swift:1-63 @ 1b8260d (64– 는 `#if os(iOS)` 화면 — W4-c)
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.rules.character.gift.CakeGiftText
import com.yehsung.aingcheck.core.rules.gacha.GachaRules

/**
 * 타일 · 구매 막대 · 고르기 머리에 설 캐릭터 이름. 카드 표 → **코어 내장 이름** → id 차례다.
 * 카드 표의 이름을 그대로 쓰면 표에 없을 때 id 글자가 그려진다 — 서버가 준 **모르는** 캐릭터는 여전히 id 로 선다(이름을 지어내지 않는다).
 */
object MeCharacterName {
    fun display(id: String): String = GachaRules.name(id, MeGachaNames::displayName)
}

/**
 * 타일 상태 줄이 말하는 것(화면 갈래가 `content` 로만 가른다 — "뽑기 전용 카드가 루비 값을 말하지 않는다"를 **값으로** 잡는다).
 */
sealed interface MeCharacterTileStatus {
    data object Equipped : MeCharacterTileStatus
    data object Owned : MeCharacterTileStatus
    data class Price(val price: Long, val balance: Long?) : MeCharacterTileStatus

    /** 뽑기·조각 교환으로만 얻는다(황금 · 무지개 아잉이) — 가격 대신 얻는 길. 교환값은 서버 값(모르면 null). */
    data class GachaOnly(val shardCost: Long?) : MeCharacterTileStatus

    /** 생일 선물로만 얻는다(케이크 아잉이 둘) — 안 가진 사람의 잠긴 칸. 가격 · 사기 단추 없이 "생일 선물 전용". */
    data object GiftOnly : MeCharacterTileStatus
    data object UnknownPrice : MeCharacterTileStatus
    data object Busy : MeCharacterTileStatus
    data object None : MeCharacterTileStatus

    /** 상태 줄이 실제로 그리는 것. */
    sealed interface Content {
        /** 보석 + 숫자 — **루비로 사는 줄만** 이 값이다. */
        data class Ruby(val price: Long, val balance: Long?) : Content

        /** 글자 한 줄(`emphasized` = 착용 중). */
        data class Text(val text: String, val emphasized: Boolean) : Content

        /** 반짝임 + 얻는 길("뽑기 · 조각 20"). */
        data class Acquire(val text: String) : Content

        /** 선물 기호 + 한 줄("생일 선물 전용") — 잠긴 칸(자물쇠가 아니다). 루비 값도 반짝임도 없다. */
        data class Locked(val text: String) : Content
        data object Spinner : Content
    }

    /**
     * **뽑기 전용은 Acquire 다 — Ruby 가 아니다**: 서버가 금·무지개 행에 싣는 명목 가격(1000)은 사는 값이 아니다. 생일 선물 전용(케이크 —
     * 장식값 2000)도 같은 까닭으로 Locked 다.
     */
    val content: Content
        get() = when (this) {
            Equipped -> Content.Text(MeText.equipped, emphasized = true)
            Owned -> Content.Text(MeText.owned, emphasized = false)
            is Price -> Content.Ruby(price, balance)
            is GachaOnly -> Content.Acquire(MeText.gachaTileStatus(shardCost))
            GiftOnly -> Content.Locked(CakeGiftText.lockedCaption)
            UnknownPrice -> Content.Text("—", emphasized = false)
            Busy -> Content.Spinner
            None -> Content.Text(" ", emphasized = false)
        }
}

/** 뽑기 이름 표(Swift `MeStore.gachaDisplayName` — 이 빌드의 카드 이름, 모르는 id 는 null → 코어가 내장 이름 · id 로 채운다). */
object MeGachaNames {
    fun displayName(id: String): String? = if (MeCharacterCards.isKnown(id)) MeCharacterCards.displayName(id) else null
}
