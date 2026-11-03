// 원본: Sources/CheckMobileKit/Me/MeStoreCakeGift.swift @ 1b8260d
// 원본: Sources/check/WorkTimerStoreCakeGift.swift @ 12624739 (맥 0.3.74 — 종류를 아는 박자 · ⑤ 다음 선물 · ⑥ 종류 문구 · 종류를 실어 옮기는 보유 거름)
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.claimCharacterGift
import com.yehsung.aingcheck.core.net.fetchCharacterGiftPending
import com.yehsung.aingcheck.core.rules.character.gift.CharacterGiftClaimOutcome
import com.yehsung.aingcheck.core.rules.character.gift.CharacterGiftCopy
import com.yehsung.aingcheck.core.rules.character.gift.copy
import com.yehsung.aingcheck.core.rules.gacha.ShopWire
import com.yehsung.aingcheck.core.wire.gift.CharacterGiftKind
import com.yehsung.aingcheck.core.wire.gift.CharacterGiftOffer

// 생일 선물 — 케이크 아잉이(맥 0.3.66 · 폰 1.0.14). 서버 · 전선 · 결과 분류 · 문구는 코어 한 벌이다(wire gift · rules character/gift).
// 이 파일은 폰의 **언제 묻고 언제 띄우는가**와 시트의 상태만 쥔다(화면은 W4-c — 판정은 전부 여기 있다).
//  - 묻는 때: 앱이 앞으로 올 때(로그인 직후도 같은 길) · **10분에 한 번 이하**. 새 타이머 · 새 폴링은 없다.
//  - 열린 선물이 있으면 **실행당 한 번**(선물 id 마다) 스스로 띄운다 — 한 번은 **실제로 화면에 선 때**로 센다(cakeGiftSheetDidAppear).
//  - **대국·관전 중에는 스스로 띄우지 않는다**(30초 수·15초 침묵이 걸린 판을 시트가 덮으면 진다). 그동안은 '다시 열기' 줄만 선다.
//  - 고르지 않고 닫으면 '다시 열기' 줄이 **수령할 때까지** 남는다. [고르기]는 스로틀을 건너뛰고 서버에 다시 물은 뒤 연다.
//  - 선택지는 **보유와 맞춰 거른다**(unownedCakeGift) — 이미 가진 케이크를 고르는 길이 없다.
//  - 받은 뒤 `shop_state` 를 다시 읽어 보유를 맞추고, [지금 입기]는 기존 착용 경로(chooseCharacter)를 탄다.
//
// ── '술 한잔' 선물 — 이슬 아잉이(맥 0.3.74 · Android 판 7) ──
// 이 박자는 이제 **종류를 아는 박자**다(이름 `cakeGift…` 는 생일 때 것을 그대로 둔다 — 상태는 선물 전용 캐릭터 선물 **한 장**: 생일 · 술 한잔).
//  - 시트 · 다시 열기 줄 · 수령 한 줄은 그 선물 종류의 문구 묶음(`CharacterGiftKind.copy` — CakeGiftText · DrinkGiftText)에서 온다.
//  - 술 선물은 선택지가 이슬 하나라 **고르기가 없다** — 시트가 설 때 그 하나를 미리 골라 둔다([MeCakeGiftSheet.open]).
//  - 보유로 거른 새 선물을 만들 때 **종류를 실어 옮긴다**(빼먹으면 술 선물이 생일로 읽혀 선택지가 0 이 된다 — 맥이 고친 잠재 결함).
//  - 다음 선물(맥 ⑤): 서버는 한 번에 하나만 준다(p ≥ 5 면 두 종류 중 먼저 지급된 것). 선물이 결론 난 뒤(받았다 · 이미 받았다 · 없다) 시트가
//    닫히면(또는 이미 닫혀 있었으면 결론 즉시) 10분 문을 건너뛰고 **한 번 더** 묻는다. 술 선물을 받을 수 있는 빌드(번호 5)에서만 —
//    번호 4 인 빌드(Windows v1)는 서버가 생일만 싣고 (사용자, 종류)당 열린 선물은 하나라 '다음'이 없다(요청 수가 0.3.73 그대로다).

/** 축하 시트 한 장의 상태. 시트는 선물 id 로 선다 — 단계가 바뀌어도 같은 시트다. 그리는 글자는 [texts](선물 종류의 문구 묶음)다. */
data class MeCakeGiftSheet(
    val gift: CharacterGiftOffer,
    val selection: String? = null,
    val phase: Phase = Phase.Choosing,
    /** 실패 · 거절 한 줄. null 이면 없음. */
    val notice: String? = null,
) {
    sealed interface Phase {
        /** 둘 중 하나를 고르는 중(확인 단추는 고른 뒤에만 켜진다). */
        data object Choosing : Phase

        /** 수령 요청이 떠 있다(단추 잠금 · 시트를 끌어 닫지 못한다). */
        data object Claiming : Phase

        /** 받았다 — "○○를 받았어요!" + [지금 입기] [닫기]. */
        data class Received(val characterID: String) : Phase

        /** 선물이 끝났는데 받은 것을 모른다 — 안내와 [닫기]만. */
        data object Closed : Phase
    }

    val id: String get() = gift.id

    /** [이걸로 받을게요]를 누를 수 있는가 — 고르는 중이고, 고른 것이 이 선물의 선택지다. */
    val canConfirm: Boolean get() = phase == Phase.Choosing && selection != null && selection in gift.options

    val receivedID: String? get() = (phase as? Phase.Received)?.characterID

    /** 선물 종류(생일 · 술 한잔). */
    val kind: CharacterGiftKind get() = gift.kind

    /** 이 시트가 그리는 글자 묶음(제목 · 본문 · 확인 단추 · 받은 뒤 단추 · 다시 열기). */
    val texts: CharacterGiftCopy get() = gift.kind.copy

    /** 고를 것이 있는가 — 생일(케이크 둘 중 하나)만. 술 한잔은 이슬 하나라 고르기 없이 [짠 받기]. */
    val choosesOption: Boolean get() = gift.kind == CharacterGiftKind.birthday

    companion object {
        /**
         * 선물 하나로 시트를 세운다. 술 한잔 선물은 선택지가 하나라 **미리 골라 둔다**(맥 `presentCakeGiftWindow` 와 같다 — [짠 받기]가 곧바로 켜진다).
         * 생일은 고르지 않은 채로 선다(둘 중 하나를 사용자가 고른다).
         */
        fun open(gift: CharacterGiftOffer, notice: String? = null): MeCakeGiftSheet =
            MeCakeGiftSheet(gift, selection = preselection(gift), notice = notice)

        /** 미리 고를 것 — 술 한잔이면 그 하나(선택지가 정확히 하나일 때만), 그 밖은 null. */
        fun preselection(gift: CharacterGiftOffer): String? =
            if (gift.kind == CharacterGiftKind.drink) gift.options.singleOrNull() else null
    }
}

// MARK: 묻기

/** 앱이 앞으로 올 때: 마지막 시도에서 10분이 지났으면 묻는다. */
fun MeStore.refreshCakeGiftIfStale() {
    if (!context.sessionStore.isSignedIn || cakeGiftLoading) return
    val last = cakeGiftCheckedAt
    if (last != null && context.clock.now().timeIntervalSince(last) < MeStore.CAKE_GIFT_CHECK_INTERVAL) return
    launch { loadCakeGift() }
}

/**
 * `character_gift_pending(p_protocol)` 한 번. 이 빌드가 케이크를 다 그리지 못하면(번호 < 4) 묻지 않는다 — 서버도 gift 를 싣지 않는다.
 * 번호 4 면 생일 선물만, 5 면 두 종류 중 먼저 지급된 것 하나가 온다(이 빌드가 못 받는 종류는 전선이 버린다).
 * 성공(선물 있음 · 없음 · 옛 서버 404 → 없음)은 옮기고, 실패(오프라인 · 5xx)는 지금 아는 선물을 그대로 둔다.
 */
suspend fun MeStore.loadCakeGift() {
    if (!context.sessionStore.isSignedIn) return
    val protocolVersion = shopProtocolVersion()
    if (!ShopWire.supportsCakeGift(protocolVersion)) return
    val serial = nextSerial("cakeGift")
    val generation = context.generation
    val claimStamp = writeStamp(MeStore.CAKE_GIFT_CLAIM_WRITE_KEY)
    cakeGiftCheckedAt = context.clock.now()
    cakeGiftLoading = true
    try {
        val service = context.service
        val offer = try {
            context.withSessionRetry { s -> service.fetchCharacterGiftPending(s.accessToken, protocolVersion.toLong()) }
        } catch (e: Throwable) {
            return // 지난 값을 둔다(취소도 같다).
        }
        if (generation != context.generation || !isCurrent("cakeGift", serial) ||
            writeStamp(MeStore.CAKE_GIFT_CLAIM_WRITE_KEY) != claimStamp
        ) return
        applyCakeGiftOffer(offer)
    } finally {
        if (isCurrent("cakeGift", serial)) cakeGiftLoading = false
    }
}

/** 서버가 말한 열린 선물을 옮기고(보유와 맞춰 거른 값), 아직 화면에 띄운 적 없는 선물이면 시트를 세운다. */
internal fun MeStore.applyCakeGiftOffer(offer: CharacterGiftOffer?) {
    cakeGift = offer?.let { unownedCakeGift(it) }
    val gift = cakeGift ?: return
    val sheet = cakeGiftSheet
    if (sheet != null) {
        // 같은 선물을 고르는 중이면 선택지만 새 값으로(다른 기기에서 하나를 가져 선택지가 줄었을 수 있다).
        if (sheet.gift.id == gift.id && sheet.phase == MeCakeGiftSheet.Phase.Choosing && sheet.gift != gift) {
            cakeGiftSheet = MeCakeGiftSheet(gift, sheet.selection?.takeIf { it in gift.options } ?: MeCakeGiftSheet.preselection(gift), notice = sheet.notice)
        }
        return
    }
    presentCakeGiftIfDue()
}

/**
 * 열린 선물을 **스스로** 띄울 때가 됐으면 시트를 세운다 — 아는 선물이 있고 · 시트가 없고 · 이 실행에서 아직 화면에 선 적이 없고 ·
 * 대국·관전 화면이 떠 있지 않을 때. 부르는 자리: 선물 조회가 끝났을 때 · 앞으로 올 때 · 탭을 옮길 때.
 */
fun MeStore.presentCakeGiftIfDue() {
    val gift = cakeGift ?: return
    if (!context.sessionStore.isSignedIn || cakeGiftSheet != null || gift.id in cakeGiftAutoShownIDs || isGameScreenUp) return
    cakeGiftSheet = MeCakeGiftSheet.open(gift)
}

/** 오목 · 체스 · 테트리스 화면(로비 · 대국 · 관전)이 떠 있다 — 로비도 넣는다(받은 신청을 수락하면 그 자리에서 판이 선다). */
internal val MeStore.isGameScreenUp: Boolean get() = context.meLinks.isAnyMatchScreenVisible

/**
 * 선택지를 **지금 아는 보유**와 맞춰 거른다. 남는 게 없으면 null. 보유를 아직 못 읽었으면(아잉뿐) 서버 값 그대로.
 * 보유는 계정에 묶여 [MeStore.reset] 이 비운다 — 앞 계정이 가진 이슬로 새 계정의 술 선물(선택지 하나)을 거르는 일이 없다.
 * 새 선물은 **종류를 실어** 만든다(선택지가 그 종류의 내장 목록으로 다시 걸러진다 — 빼면 술 선물이 생일로 읽혀 선택지가 0 이 된다).
 */
internal fun MeStore.unownedCakeGift(gift: CharacterGiftOffer): CharacterGiftOffer? {
    val remaining = gift.options.filter { !isOwned(it) }
    if (remaining == gift.options) return gift
    if (remaining.isEmpty()) return null
    return CharacterGiftOffer(gift.id, remaining, gift.note, gift.createdAt, gift.kind)
}

/**
 * 상점 상태가 보유를 새로 말한 뒤: 아는 선물과 고르는 중인 시트의 선택지를 보유와 맞춘다. 둘 중 하나라도 움직였으면 **서버에 다시 묻는다**
 * (스로틀 무시 — 다른 기기에서 받았으면 서버는 선물을 이미 닫았다). 받는 중 · 받은 뒤 · 끝난 시트는 건드리지 않는다.
 */
internal fun MeStore.reconcileCakeGiftWithOwnership() {
    var moved = false
    cakeGift?.let { gift ->
        val kept = unownedCakeGift(gift)
        if (kept != gift) {
            cakeGift = kept
            moved = true
        }
    }
    val sheet = cakeGiftSheet
    if (sheet != null && sheet.phase == MeCakeGiftSheet.Phase.Choosing) {
        val remaining = sheet.gift.options.filter { !isOwned(it) }
        if (remaining != sheet.gift.options) {
            moved = true
            cakeGiftSheet = if (remaining.isEmpty()) {
                MeCakeGiftSheet(sheet.gift, phase = MeCakeGiftSheet.Phase.Closed, notice = sheet.texts.notice(CharacterGiftClaimOutcome.alreadyClaimed(null)) { it })
            } else {
                val gift = CharacterGiftOffer(sheet.gift.id, remaining, sheet.gift.note, sheet.gift.createdAt, sheet.gift.kind)
                MeCakeGiftSheet(gift, sheet.selection?.takeIf { it in remaining } ?: MeCakeGiftSheet.preselection(gift), notice = sheet.notice)
            }
        }
    }
    if (moved) launch { loadCakeGift() }
}

// MARK: 화면 사건

/** 나 탭에 서는 '다시 열기' 줄의 조건 — 열린 선물이 있고 시트가 떠 있지 않다. */
val MeStore.showsCakeGiftReopen: Boolean get() = cakeGift != null && cakeGiftSheet == null

/**
 * '다시 열기' 줄의 [고르기] — **스로틀을 건너뛰고 서버에 다시 묻고** 연다. 다른 기기에서 이미 받았으면 줄이 걷히고 시트는 안 뜬다.
 * 묻기가 실패하면 아는 선물(보유와 거른 값)로 연다 — 수령이 서버에서 다시 판정된다.
 */
fun MeStore.reopenCakeGift() {
    if (cakeGift == null || cakeGiftSheet != null || cakeGiftReopening || !context.sessionStore.isSignedIn) return
    cakeGiftReopening = true
    val generation = context.generation
    launch {
        loadCakeGift()
        if (generation != context.generation) return@launch
        cakeGiftReopening = false
        // 묻는 사이 스스로 섰을 수 있다.
        if (cakeGiftSheet != null) return@launch
        val gift = cakeGift?.let { unownedCakeGift(it) } ?: return@launch
        cakeGiftSheet = MeCakeGiftSheet.open(gift)
    }
}

fun MeStore.selectCakeGiftOption(id: String) {
    val sheet = cakeGiftSheet ?: return
    if (sheet.phase != MeCakeGiftSheet.Phase.Choosing || id !in sheet.gift.options) return
    cakeGiftSheet = sheet.copy(selection = id, notice = null)
}

/**
 * 시트를 닫는다. 선물이 아직 열려 있으면 '다시 열기' 줄이 남는다. **받는 중에는 닫지 않는다**(결과를 모른 채 닫히면 [지금 입기]가 안 선다).
 * 닫는 시트의 선물이 결론 났으면(받았다 · 끝났다) 다음 선물을 묻는다(맥 ⑤ — 번호 5 에서만).
 */
fun MeStore.dismissCakeGiftSheet() {
    val sheet = cakeGiftSheet ?: return
    if (sheet.phase == MeCakeGiftSheet.Phase.Claiming) return
    cakeGiftSheet = null
    if (sheet.phase is MeCakeGiftSheet.Phase.Received || sheet.phase == MeCakeGiftSheet.Phase.Closed) followUpCakeGiftIfNeeded()
}

/**
 * 선물이 결론 난 뒤 다음 선물을 한 번 묻는다(맥 0.3.74 ⑤ `followUpCakeGiftIfNeeded` — 서버는 한 번에 하나만 내린다). 10분 문을 건너뛴다.
 * **술 선물을 받을 수 있는 빌드(번호 5)에서만** — 4 인 빌드엔 '다음'이 없다(요청 수가 0.3.73 그대로). 떠 있던 조회가 있으면 이 조회가
 * 그것을 갈아 치운다(순번 — 결론 전에 떠난 응답일 수 있다).
 */
internal fun MeStore.followUpCakeGiftIfNeeded() {
    if (!context.sessionStore.isSignedIn) return
    val generation = context.generation
    launch {
        if (generation != context.generation) return@launch
        if (!ShopWire.supportsDrinkGift(shopProtocolVersion())) return@launch
        cakeGiftFollowUps += 1
        loadCakeGift()
    }
}

/** 시트 화면이 섰다 — 그 선물을 **띄운 것으로 센다**(실행당 한 번). */
fun MeStore.cakeGiftSheetDidAppear() {
    cakeGiftSheetOnScreen = true
    cakeGiftSheet?.gift?.id?.let { cakeGiftAutoShownIDs = cakeGiftAutoShownIDs + it }
}

fun MeStore.cakeGiftSheetDidDisappear() {
    cakeGiftSheetOnScreen = false
}

/** [이걸로 받을게요] — `claim_character_gift`. 같은 선택으로 다시 불러도 안전하다(서버가 `replayed` 로 같은 답을 준다). */
fun MeStore.confirmCakeGift() {
    val sheet = cakeGiftSheet ?: return
    val choice = sheet.selection
    if (!sheet.canConfirm || choice == null || !context.sessionStore.isSignedIn) return
    val giftID = sheet.gift.id
    cakeGiftSheet = sheet.copy(phase = MeCakeGiftSheet.Phase.Claiming, notice = null)
    val generation = context.generation
    val service = context.service
    launch {
        val response = try {
            val protocolVersion = shopProtocolVersion().toLong()
            context.withSessionRetry { s -> service.claimCharacterGift(s.accessToken, giftID, choice, protocolVersion) }
        } catch (e: Throwable) {
            if (generation != context.generation) return@launch
            val outcome = CharacterGiftClaimOutcome.fromError(MeWireBridge.isMissingFunction(e))
            if (outcome != null) {
                applyCakeGiftClaim(outcome, giftID, generation)
                return@launch
            }
            // 결과를 모른다(오프라인 · 5xx · 취소) — 고르는 화면으로 돌려 다시 누르게 한다(같은 선택이면 replayed).
            val current = cakeGiftSheet ?: return@launch
            if (current.gift.id != giftID || current.phase != MeCakeGiftSheet.Phase.Claiming) return@launch
            cakeGiftSheet = current.copy(
                phase = MeCakeGiftSheet.Phase.Choosing,
                // 문구는 받던 선물 종류의 묶음에서(생일 · 술 한잔 — 지금은 두 종류가 같은 글자다).
                notice = if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) null else current.texts.claimFailed,
            )
            return@launch
        }
        applyCakeGiftClaim(MeWireBridge.giftClaimOutcome(response, choice), giftID, generation)
    }
}

/**
 * 수령 결과를 옮긴다. **보낼 때의 세대가 아니면 아무것도 안 한다**.
 *  - 받았다(received · 받은 id 를 아는 already_claimed): 보유에 넣고, 받은 뒤 화면으로, 상점을 다시 읽는다.
 *  - 선물이 끝났다(settlesGift): 열린 선물을 거둔다. - 그 밖: 고르는 화면에 한 줄 안내, 선물은 그대로 열려 있다.
 */
internal suspend fun MeStore.applyCakeGiftClaim(outcome: CharacterGiftClaimOutcome, giftID: String, generation: Int) {
    if (generation != context.generation) return
    val received: String? = when (outcome) {
        is CharacterGiftClaimOutcome.received -> outcome.characterID
        is CharacterGiftClaimOutcome.alreadyClaimed -> outcome.characterID
        else -> null
    }
    if (outcome.settlesGift) {
        noteLocalWrite(MeStore.CAKE_GIFT_CLAIM_WRITE_KEY)
        if (cakeGift?.id == giftID) cakeGift = null
    }
    if (received != null) ownedCharacterIDs = ownedCharacterIDs + received
    val sheet = cakeGiftSheet
    val sheetShowsThisGift = sheet != null && sheet.gift.id == giftID
    if (sheet != null && sheetShowsThisGift) {
        cakeGiftSheet = if (received != null) {
            sheet.copy(phase = MeCakeGiftSheet.Phase.Received(received), notice = null)
        } else {
            sheet.copy(
                phase = if (outcome.settlesGift) MeCakeGiftSheet.Phase.Closed else MeCakeGiftSheet.Phase.Choosing,
                // 문구는 그 선물 종류의 묶음에서(실패 · 거절 줄은 두 종류가 같은 글자다).
                notice = sheet.texts.notice(outcome, MeCharacterName::display),
            )
        }
    }
    if (received != null) loadShop()
    // 다음 선물(맥 ⑤): 시트가 떠 있으면 사용자가 닫을 때 묻는다(받은 뒤 화면 위로 다음 시트를 겹치지 않게 — dismiss · 지금 입기).
    // 받는 사이에 시트를 닫았으면(받는 중엔 못 닫지만 계정·창 사정으로 걷혔을 수 있다) 닫기가 이미 지나갔다 — 지금 묻는다.
    if (outcome.settlesGift && !sheetShowsThisGift) followUpCakeGiftIfNeeded()
}

/** 받은 뒤 [지금 입기] — 시트를 닫고 **기존 착용 경로**(chooseCharacter → set_character)를 탄다. 다음 선물을 묻는다(번호 5 에서만). */
fun MeStore.wearReceivedCakeGift() {
    val id = cakeGiftSheet?.receivedID ?: return
    cakeGiftSheet = null
    chooseCharacter(id)
    followUpCakeGiftIfNeeded()
}
