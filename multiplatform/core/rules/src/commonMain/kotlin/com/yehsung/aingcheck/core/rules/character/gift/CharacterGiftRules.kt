// 원본: Sources/CheckCore/CharacterGift.swift(CharacterGiftClaimOutcome · CakeGiftText · DrinkGiftText · CharacterGiftCopy · CharacterGiftKind.copy) @ 12624739
//       (전선 모양 · CharacterGiftKind 의 원문 값 · 서비스 · 디코드 보조는 W1-d core/wire — 배정표 round5)
package com.yehsung.aingcheck.core.rules.character.gift

import com.yehsung.aingcheck.core.rules.gacha.ShopWire
import com.yehsung.aingcheck.core.rules.text.TextScalars
import com.yehsung.aingcheck.core.wire.gift.CharacterGiftKind

/**
 * 생일 선물 수령 한 번의 도메인 결과(맥 · 폰 · Android 한 벌). **모르는 status 는 `failed(원문)`** — 화면이 죽지 않는다.
 * 응답 타입(`CharacterGiftClaimResponse`)은 와이어(W1-d)라 여기서는 그 세 칸(status · character_id · replayed)을 받는다.
 */
sealed interface CharacterGiftClaimOutcome {
    /** 받았다(replayed 면 같은 선택의 재응답). [지금 입기]는 이 id 로 기존 착용 경로를 탄다. */
    data class received(val characterID: String, val replayed: Boolean) : CharacterGiftClaimOutcome
    /** 이미 **다른** 캐릭터로 받은 선물(받은 것 — 서버가 안 실었으면 null). */
    data class alreadyClaimed(val characterID: String?) : CharacterGiftClaimOutcome
    /** 이 빌드는 그 선물의 캐릭터를 못 그린다(생일 p_protocol < 4 · 술 < 5) — 아무것도 안 움직였다. */
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

/**
 * '술 한잔' 선물 문구(맥 0.3.74 이슬 아잉이 — Swift `DrinkGiftText` 글자 그대로). [CakeGiftText] 와 같은 모양이다 — 받는 창 · 상점 잠긴 칸 ·
 * 다시 열기 카드가 같이 쓴다. 실패 · 거절 줄은 생일과 한 벌이다.
 * 문구는 대표 결정(2026-11-03, 결재 #d_QKdjqLLU7S0b "C 짧고 가볍게 (짠! 🥂)" — 수고 인사처럼 가볍게). 잠긴 칸 캡션 · 안내 · 받은 뒤 한 줄은
 * C 안에 따로 없어 설계서 §5 가제를 그대로 둔다(맥과 같다).
 */
object DrinkGiftText {
    /** 받는 창 제목. */
    const val title = "짠! 🥂"
    /** 받는 창 본문(운영자 한 줄 `note` 가 있으면 화면이 그 위에 크게 — 초대장처럼). */
    const val body = "오늘도 고생 많았어요. 이슬 아잉이 한 병 받아요!"
    /** 확인 단추(고를 것이 없다 — 선택지는 이슬 하나). */
    const val confirmButton = "짠 받기"
    /** 받은 뒤의 단추 둘(생일과 같은 글자). */
    const val wearNowButton = CakeGiftText.wearNowButton
    const val closeButton = CakeGiftText.closeButton
    /** 상점 잠긴 칸 캡션(가격 · 사기 단추 자리). */
    const val lockedCaption = "술 한잔 선물 전용"
    /** 잠긴 칸을 골랐을 때의 안내. */
    const val lockedHint = "술 한잔 선물로만 받을 수 있어요. 루비나 뽑기로는 얻을 수 없어요."
    /** 받지 않고 닫은 뒤 나 탭에 남는 카드. */
    const val reopenTitle = "짠! 선물이 왔어요"
    const val reopenButton = "받기"
    /** 결과를 모르는 수령의 한 줄 — 생일과 같은 글자다(다시 눌러도 안전하다). */
    const val claimFailed = CakeGiftText.claimFailed

    /** 받은 뒤 한 줄 — "이슬 아잉이를 받았어요!"(조사 규칙은 생일과 한 곳). */
    fun received(name: String): String = CakeGiftText.received(name)

    /** 수령 결과 중 받은 화면이 아닌 것의 한 줄 — 생일과 같은 어휘 · 같은 글자. */
    fun notice(outcome: CharacterGiftClaimOutcome, name: (String) -> String): String? = CakeGiftText.notice(outcome, name)
}

/** 선물 종류 하나의 문구 묶음 — 화면이 종류로 갈라 그릴 때 [CharacterGiftKind.copy] 로 받는다(글자는 [CakeGiftText] · [DrinkGiftText] 한 곳). */
data class CharacterGiftCopy(
    val title: String,
    val body: String,
    val confirmButton: String,
    val wearNowButton: String,
    val closeButton: String,
    val lockedCaption: String,
    val lockedHint: String,
    val reopenTitle: String,
    val reopenButton: String,
    /** 결과를 모르는 수령의 한 줄. */
    val claimFailed: String,
) {
    /** 받은 뒤 한 줄(종류와 무관하게 한 규칙 — "○○를 받았어요!"). */
    fun received(name: String): String = CakeGiftText.received(name)

    /** 수령 결과 한 줄(실패 · 거절 줄은 두 종류가 같은 글자다). */
    fun notice(outcome: CharacterGiftClaimOutcome, name: (String) -> String): String? = CakeGiftText.notice(outcome, name)

    companion object {
        /** 생일 선물(케이크 아잉이 — 0.3.66). */
        val birthday = CharacterGiftCopy(
            title = CakeGiftText.title, body = CakeGiftText.body, confirmButton = CakeGiftText.confirmButton,
            wearNowButton = CakeGiftText.wearNowButton, closeButton = CakeGiftText.closeButton,
            lockedCaption = CakeGiftText.lockedCaption, lockedHint = CakeGiftText.lockedHint,
            reopenTitle = CakeGiftText.reopenTitle, reopenButton = CakeGiftText.reopenButton,
            claimFailed = CakeGiftText.claimFailed,
        )

        /** '술 한잔' 선물(이슬 아잉이 — 0.3.74). */
        val drink = CharacterGiftCopy(
            title = DrinkGiftText.title, body = DrinkGiftText.body, confirmButton = DrinkGiftText.confirmButton,
            wearNowButton = DrinkGiftText.wearNowButton, closeButton = DrinkGiftText.closeButton,
            lockedCaption = DrinkGiftText.lockedCaption, lockedHint = DrinkGiftText.lockedHint,
            reopenTitle = DrinkGiftText.reopenTitle, reopenButton = DrinkGiftText.reopenButton,
            claimFailed = DrinkGiftText.claimFailed,
        )
    }
}

/** 이 종류의 문구 묶음(Swift `CharacterGiftKind.copy`). */
val CharacterGiftKind.copy: CharacterGiftCopy
    get() = when (this) {
        CharacterGiftKind.birthday -> CharacterGiftCopy.birthday
        CharacterGiftKind.drink -> CharacterGiftCopy.drink
    }

/**
 * 이 종류를 받을 수 있는 최소 능력 번호 — rules 의 정본 상수(`ShopWire.cakeProtocol` · `ShopWire.isulProtocol`). 와이어 열거의
 * [CharacterGiftKind.minProtocol] 와 같아야 한다(rules 시험이 맞댄다 — 와이어는 rules 를 못 봐서 숫자를 따로 쥔다).
 */
val CharacterGiftKind.shopMinProtocol: Int
    get() = when (this) {
        CharacterGiftKind.birthday -> ShopWire.cakeProtocol
        CharacterGiftKind.drink -> ShopWire.isulProtocol
    }
