// 원본: Sources/CheckCore/CharacterGift.swift:164-217(CharacterGiftClaimOutcome) · :269-326(CakeGiftText) @ 1b8260d
//       (1–163 전선 모양 · 218–268 서비스 · 327– 디코드 보조는 W1-d — 배정표 round5 의 줄 구간)
package com.yehsung.aingcheck.core.rules.character.gift

import com.yehsung.aingcheck.core.rules.text.TextScalars

/**
 * 생일 선물 수령 한 번의 도메인 결과(맥 · 폰 · Android 한 벌). **모르는 status 는 `failed(원문)`** — 화면이 죽지 않는다.
 * 응답 타입(`CharacterGiftClaimResponse`)은 와이어(W1-d)라 여기서는 그 세 칸(status · character_id · replayed)을 받는다.
 */
sealed interface CharacterGiftClaimOutcome {
    /** 받았다(replayed 면 같은 선택의 재응답). [지금 입기]는 이 id 로 기존 착용 경로를 탄다. */
    data class received(val characterID: String, val replayed: Boolean) : CharacterGiftClaimOutcome
    /** 이미 **다른** 캐릭터로 받은 선물(받은 것 — 서버가 안 실었으면 null). */
    data class alreadyClaimed(val characterID: String?) : CharacterGiftClaimOutcome
    /** 이 빌드는 케이크를 못 그린다(p_protocol < 4) — 아무것도 안 움직였다. */
    data object needsUpdate : CharacterGiftClaimOutcome
    /** 내 선물이 아니거나 없다. */
    data object notFound : CharacterGiftClaimOutcome
    /** 선택지에 없는 캐릭터를 보냈다. */
    data object invalidChoice : CharacterGiftClaimOutcome
    data object notSignedIn : CharacterGiftClaimOutcome
    /** 서버에 수령 함수가 아직 없다(PGRST202 · 404). throw 로만 온다([fromError]). */
    data object unavailable : CharacterGiftClaimOutcome
    data class failed(val status: String) : CharacterGiftClaimOutcome

    /** 이 선물이 끝났는가 — 받았다 · 이미 받았다 · 없다. 화면이 선물 카드를 거두는 조건. */
    val settlesGift: Boolean
        get() = when (this) {
            is received, is alreadyClaimed, notFound -> true
            needsUpdate, invalidChoice, notSignedIn, unavailable, is failed -> false
        }

    companion object {
        // 서버 status 어휘(CharacterGiftStatus — 전선 몫 상수와 같은 글자).
        private const val OK = "ok"
        private const val UNAUTHORIZED = "unauthorized"
        private const val NEEDS_UPDATE = "needs_update"
        private const val NOT_FOUND = "not_found"
        private const val INVALID_CHOICE = "invalid_choice"
        private const val ALREADY_CLAIMED = "already_claimed"

        /** `requestedID` 는 보낸 id — 서버가 ok 에 id 를 안 실었거나 비었을 때만 쓴다. */
        fun from(status: String, characterId: String?, replayed: Boolean?, requestedID: String): CharacterGiftClaimOutcome = when (status) {
            OK -> received(characterId?.takeIf { it.isNotEmpty() } ?: requestedID, replayed ?: false)
            ALREADY_CLAIMED -> alreadyClaimed(characterId?.takeIf { it.isNotEmpty() })
            NEEDS_UPDATE -> needsUpdate
            NOT_FOUND -> notFound
            INVALID_CHOICE -> invalidChoice
            UNAUTHORIZED -> notSignedIn
            else -> failed(status)
        }

        /** 함수 없음이면 [unavailable], 그 밖(오프라인 · 5xx · 해석 실패)은 null — 같은 선택으로 다시 불러도 안전하다(replayed). */
        fun fromError(isMissingFunction: Boolean): CharacterGiftClaimOutcome? = if (isMissingFunction) unavailable else null
    }
}

/** 생일 선물 문구(설계서 §3 표 그대로 — 축하 창 · 시트 · 잠긴 칸 · 다시 열기 카드가 같이 쓴다). */
object CakeGiftText {
    const val title = "생일 축하해요! 🎂"
    const val body = "생일 선물로 케이크 아잉이를 하나 골라 주세요."
    const val confirmButton = "이걸로 받을게요"
    const val wearNowButton = "지금 입기"
    const val closeButton = "닫기"
    const val lockedCaption = "생일 선물 전용"
    const val lockedHint = "생일에 선물로만 받을 수 있어요. 루비나 뽑기로는 얻을 수 없어요."
    const val reopenTitle = "생일 선물이 도착했어요"
    const val reopenButton = "고르기"

    /** "딸기 케이크 아잉이를 받았어요!"(받침이 있으면 '을'). */
    fun received(name: String): String = "$name${objectParticle(name)} 받았어요!"

    const val claimFailed = "받지 못했어요. 잠시 후 다시 시도해 주세요"
    const val needsUpdate = "앱을 업데이트하면 받을 수 있어요"
    const val unavailable = "지금은 받을 수 없어요"
    const val notSignedIn = "로그인하면 받을 수 있어요"
    const val notFound = "선물을 찾지 못했어요"
    const val invalidChoice = "고를 수 없는 캐릭터예요"
    const val alreadyClaimed = "이미 받은 선물이에요"

    /** 받은 화면이 아닌 결과의 한 줄. `received` 는 null. `alreadyClaimed` 는 id 를 알면 "○○를 받았어요!", 모르면 "이미 받은 선물이에요". */
    fun notice(outcome: CharacterGiftClaimOutcome, name: (String) -> String): String? = when (outcome) {
        is CharacterGiftClaimOutcome.received -> null
        is CharacterGiftClaimOutcome.alreadyClaimed -> outcome.characterID?.let { received(name(it)) } ?: alreadyClaimed
        CharacterGiftClaimOutcome.needsUpdate -> needsUpdate
        CharacterGiftClaimOutcome.notFound -> notFound
        CharacterGiftClaimOutcome.invalidChoice -> invalidChoice
        CharacterGiftClaimOutcome.notSignedIn -> notSignedIn
        CharacterGiftClaimOutcome.unavailable -> unavailable
        is CharacterGiftClaimOutcome.failed -> claimFailed
    }

    /** 목적격 조사 — 마지막 스칼라(앞뒤 whitespacesAndNewlines 를 지운 뒤)가 받침 있는 한글 음절이면 '을', 그 밖은 '를'. */
    fun objectParticle(word: String): String {
        val trimmed = TextScalars.trimmingWhitespacesAndNewlines(word)
        if (trimmed.isEmpty()) return "를"
        val last = trimmed.codePointBefore(trimmed.length)
        if (last !in 0xAC00..0xD7A3) return "를"
        return if ((last - 0xAC00) % 28 == 0) "를" else "을"
    }

    /** 마지막 코드포인트(서로게이트 짝이면 합친 값). */
    private fun String.codePointBefore(end: Int): Int {
        val low = this[end - 1]
        if (low.isLowSurrogate() && end >= 2 && this[end - 2].isHighSurrogate()) {
            return 0x10000 + ((this[end - 2].code - 0xD800) shl 10) + (low.code - 0xDC00)
        }
        return low.code
    }
}
