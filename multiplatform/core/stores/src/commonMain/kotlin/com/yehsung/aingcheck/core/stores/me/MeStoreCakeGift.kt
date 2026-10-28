// 원본: Sources/CheckMobileKit/Me/MeStoreCakeGift.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.claimCharacterGift
import com.yehsung.aingcheck.core.net.fetchCharacterGiftPending
import com.yehsung.aingcheck.core.rules.character.gift.CakeGiftText
import com.yehsung.aingcheck.core.rules.character.gift.CharacterGiftClaimOutcome
import com.yehsung.aingcheck.core.rules.gacha.ShopWire
import com.yehsung.aingcheck.core.wire.gift.CharacterGiftOffer

// 생일 선물 — 케이크 아잉이(맥 0.3.66 · 폰 1.0.14). 서버 · 전선 · 결과 분류 · 문구는 코어 한 벌이다(wire gift · rules character/gift).
// 이 파일은 폰의 **언제 묻고 언제 띄우는가**와 시트의 상태만 쥔다(화면은 W4-c — 판정은 전부 여기 있다).
//  - 묻는 때: 앱이 앞으로 올 때(로그인 직후도 같은 길) · **10분에 한 번 이하**. 새 타이머 · 새 폴링은 없다.
//  - 열린 선물이 있으면 **실행당 한 번**(선물 id 마다) 스스로 띄운다 — 한 번은 **실제로 화면에 선 때**로 센다(cakeGiftSheetDidAppear).
//  - **대국·관전 중에는 스스로 띄우지 않는다**(30초 수·15초 침묵이 걸린 판을 시트가 덮으면 진다). 그동안은 '다시 열기' 줄만 선다.
//  - 고르지 않고 닫으면 '다시 열기' 줄이 **수령할 때까지** 남는다. [고르기]는 스로틀을 건너뛰고 서버에 다시 물은 뒤 연다.
//  - 선택지는 **보유와 맞춰 거른다**(unownedCakeGift) — 이미 가진 케이크를 고르는 길이 없다.
//  - 받은 뒤 `shop_state` 를 다시 읽어 보유를 맞추고, [지금 입기]는 기존 착용 경로(chooseCharacter)를 탄다.

/** 축하 시트 한 장의 상태. 시트는 선물 id 로 선다 — 단계가 바뀌어도 같은 시트다. */
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
            cakeGiftSheet = MeCakeGiftSheet(gift, sheet.selection?.takeIf { it in gift.options }, notice = sheet.notice)
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
    cakeGiftSheet = MeCakeGiftSheet(gift)
}

/** 오목 · 체스 · 테트리스 화면(로비 · 대국 · 관전)이 떠 있다 — 로비도 넣는다(받은 신청을 수락하면 그 자리에서 판이 선다). */
internal val MeStore.isGameScreenUp: Boolean get() = context.meLinks.isAnyMatchScreenVisible

/** 선택지를 **지금 아는 보유**와 맞춰 거른다. 남는 게 없으면 null. 보유를 아직 못 읽었으면(아잉뿐) 서버 값 그대로. */
internal fun MeStore.unownedCakeGift(gift: CharacterGiftOffer): CharacterGiftOffer? {
    val remaining = gift.options.filter { !isOwned(it) }
    if (remaining == gift.options) return gift
    if (remaining.isEmpty()) return null
    return CharacterGiftOffer(gift.id, remaining, gift.note, gift.createdAt)
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
                MeCakeGiftSheet(sheet.gift, phase = MeCakeGiftSheet.Phase.Closed, notice = CakeGiftText.alreadyClaimed)
            } else {
                val gift = CharacterGiftOffer(sheet.gift.id, remaining, sheet.gift.note, sheet.gift.createdAt)
                MeCakeGiftSheet(gift, sheet.selection?.takeIf { it in remaining }, notice = sheet.notice)
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
        cakeGiftSheet = MeCakeGiftSheet(gift)
    }
}

fun MeStore.selectCakeGiftOption(id: String) {
    val sheet = cakeGiftSheet ?: return
    if (sheet.phase != MeCakeGiftSheet.Phase.Choosing || id !in sheet.gift.options) return
    cakeGiftSheet = sheet.copy(selection = id, notice = null)
}

/** 시트를 닫는다. 선물이 아직 열려 있으면 '다시 열기' 줄이 남는다. **받는 중에는 닫지 않는다**(결과를 모른 채 닫히면 [지금 입기]가 안 선다). */
fun MeStore.dismissCakeGiftSheet() {
    if (cakeGiftSheet?.phase == MeCakeGiftSheet.Phase.Claiming) return
    cakeGiftSheet = null
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
                notice = if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) null else CakeGiftText.claimFailed,
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
    if (sheet != null && sheet.gift.id == giftID) {
        cakeGiftSheet = if (received != null) {
            sheet.copy(phase = MeCakeGiftSheet.Phase.Received(received), notice = null)
        } else {
            sheet.copy(
                phase = if (outcome.settlesGift) MeCakeGiftSheet.Phase.Closed else MeCakeGiftSheet.Phase.Choosing,
                notice = CakeGiftText.notice(outcome, MeCharacterName::display),
            )
        }
    }
    if (received != null) loadShop()
}

/** 받은 뒤 [지금 입기] — 시트를 닫고 **기존 착용 경로**(chooseCharacter → set_character)를 탄다. */
fun MeStore.wearReceivedCakeGift() {
    val id = cakeGiftSheet?.receivedID ?: return
    cakeGiftSheet = null
    chooseCharacter(id)
}
