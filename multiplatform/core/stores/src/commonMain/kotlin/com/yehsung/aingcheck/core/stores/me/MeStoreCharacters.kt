// 원본: Sources/CheckMobileKit/Me/MeStoreCharacters.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.buyCharacter
import com.yehsung.aingcheck.core.net.fetchEquippedCharacter
import com.yehsung.aingcheck.core.net.fetchShopState
import com.yehsung.aingcheck.core.net.setCharacter
import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import com.yehsung.aingcheck.core.rules.character.CharacterSyncDecision
import com.yehsung.aingcheck.core.rules.character.gift.CakeGiftText
import com.yehsung.aingcheck.core.rules.format.SharedText
import com.yehsung.aingcheck.core.rules.gacha.ShopWire
import com.yehsung.aingcheck.core.wire.models.BuyCharacterResponse
import com.yehsung.aingcheck.core.wire.models.ShopCharacterRow
import com.yehsung.aingcheck.core.wire.models.ShopStateResponse

// 캐릭터: 상점(`shop_state` · `buy_character`) · 고르기(`set_character`) · 착용값 읽기(`profiles.character`).
// 맥 상점과 같은 규칙이되 **캐릭터 가지만** 있다 — 울트라 구매·지갑 동기화는 폰에 없다.
//  - 카드를 누르면 **고르기만** 한다. 사는 문은 confirmPurchase() 하나(맥 2026-09-14 "실수로 전부 사 버렸다" 신고의 교훈).
//  - 잔량·보유는 **서버가 준 값**으로만 바꾼다. 잔량은 루비 미러에도 쓴다(게임 탭과 공유).
//  - 착용값의 진실은 서버다 — 폰은 로컬 선택을 따로 들지 않는다.

/**
 * 상점 RPC 에 싣는 능력 번호(로봇 1 · 금 2 · 무지개 3 · 케이크 **4**). 파생 자리는 여기 하나다 — 목록과 구매가 **같은 번호**로 가야 한다
 * (목록만 가리고 구매를 열어 두면 게이트가 장식이다 — B12). 재료는 [MeStore.drawableCharacters](K9).
 */
suspend fun MeStore.shopProtocolVersion(): Int = ShopWire.protocolVersion(drawableCharacterIDs())

// MARK: 읽기

suspend fun MeStore.loadShop() {
    if (!context.sessionStore.isSignedIn) return
    val serial = nextSerial("shop")
    val generation = context.generation
    // 루비 미러에 쓴 횟수를 **떠날 때** 찍는다 — 도착했을 때 그 사이 누가 썼으면 이 조회는 그 쓰기보다 옛 서버를 말한다.
    val rubyWriteAtDeparture = context.ruby.rubyWriteSerial
    shopState.isLoading = true
    shopState.hasFailed = false
    try {
        val service = context.service
        val protocolVersion = shopProtocolVersion().toLong()
        val state = try {
            context.withSessionRetry { s -> service.fetchShopState(s.accessToken, protocolVersion) }
        } catch (e: Throwable) {
            if (generation != context.generation || !isCurrent("shop", serial)) return
            if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
            shopState.hasFailed = true
            return
        }
        if (generation != context.generation || !isCurrent("shop", serial)) return
        applyShopRubyBalance(state.rubyBalance, rubyWriteAtDeparture)
        applyShopState(state)
        shopState.hasLoaded = true
        shopState.loadedAt = context.clock.now()
    } finally {
        if (isCurrent("shop", serial)) shopState.isLoading = false
    }
}

/**
 * 상점 조회가 실어 온 잔량을 루비 미러에 옮긴다 — **떠난 뒤 미러에 쓴 적이 없을 때만**(폰 1.0.9).
 *
 * INV-MeStoreCharacters-7379a09b 이식: 미러는 상점 · 뽑기 · 받기 · 오목 · 체스가 다 쓰는 한 칸이다. 나 탭이 뜨면 상점과 주간 · 도전 미션
 *   조회가 **함께** 떠나므로 받기를 누른 뒤 **받기 전에 떠난** `shop_state` 가 도착하는 창이 흔하다(도장 없이 덮던 시절 1055 → 1000 —
 *   받은 루비가 눈앞에서 사라졌다). 주간 보상과 같은 규약(쓴 **횟수**로 묻는다 — ABA). 구매·뽑기·교환 **응답**의 잔량은 이 문을 지나지
 *   않는다(누른 사람 자신의 가장 새 결과라 언제나 쓴다).
 */
internal fun MeStore.applyShopRubyBalance(server: Long?, writeSerialAtDeparture: Int) {
    if (!WeeklyWorkRules.shouldApplyRuby(server, writeSerialAtDeparture, context.ruby.rubyWriteSerial) || server == null) return
    context.ruby.rubyBalance = server
}

/**
 * 서버가 말한 상점 상태를 옮긴다. **null 은 건너뛴다** — 모르는 것을 0 으로 적지 않는다. 울트라는 값(`ultra_price`)만 읽는다
 * (잔량은 데스크톱 지갑 UltraWalletStore 몫).
 *
 * INV-MeStoreCharacters-23099059 이식: **잔량은 여기서 쓰지 않는다** — 부르는 자리가 도장과 함께 [applyShopRubyBalance] 로 옮긴다
 *   (위 이식 주석). 새로 이 함수를 부르는 자리를 만들거든 잔량도 그 짝으로 같이 옮겨라.
 *
 * 뽑기(v0.3.54)는 예외로 **없음도 사실이다**: 서버는 `p_protocol >= 2` 일 때만 `gacha` 를 싣는다 — 받은 그대로 옮긴다.
 */
internal fun MeStore.applyShopState(state: ShopStateResponse) {
    gachaInfo = MeWireBridge.gachaInfo(state.gacha)
    // Swift applyShopState 624 `if let price = state.ultraPrice` — 캐릭터 줄이 없는 응답에도 옮긴다(아래 조기 반환보다 앞).
    state.ultraPrice?.let { ultraPrice = it }
    val rows = state.characters ?: return
    shopCharacters = rows
    val owned = LinkedHashSet<String>()
    owned += MeCharacterCards.aingID
    for (row in rows) if (row.owned == true) owned += row.id
    ownedCharacterIDs = owned
    // 생일 선물(v0.3.66): 새 보유와 선택지를 맞춘다 — 다른 기기에서 받은 케이크가 선물 · '다시 열기' 줄에 남지 않게.
    reconcileCakeGiftWithOwnership()
}

/** 착용값 읽기. `set_character` 가 **끝날 때** 순번을 올리므로 저장 전·저장 중에 나간 GET 은 늦게 와도 버려진다. */
suspend fun MeStore.loadEquippedCharacter() {
    if (!context.sessionStore.isSignedIn) return
    val serial = nextSerial("equipped")
    val generation = context.generation
    val service = context.service
    equippedLoadFailed = false
    val serverID = try {
        context.withSessionRetry { s -> service.fetchEquippedCharacter(s.accessToken, s.userID) }
    } catch (e: Throwable) {
        // 행 없음·옛 서버·네트워크: 값은 모르는 채로 둔다(아잉으로 단정하지 않는다) — 실패였다는 사실만 남긴다.
        if (generation != context.generation || !isCurrent("equipped", serial)) return
        if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
        equippedLoadFailed = true
        return
    }
    if (generation != context.generation || !isCurrent("equipped", serial) || savingCharacterID != null) return
    equippedServerID = CharacterSyncDecision.normalized(serverID)
    equippedLoaded = true
    // 캐릭터 한 표의 내 칸도 같은 값으로 — '나' 자리(지금·순위·탭 막대)가 다른 캐릭터로 서지 않게.
    context.meLinks.noteMyEquipped(equippedServerID)
}

// MARK: 표시값

/** 지금 서 있는 캐릭터(모르면 아잉). */
val MeStore.equippedCharacterID: String get() = MeCharacterCards.equippedID(equippedServerID)

/** 상점 목록(서버 순서). 아직 못 읽었으면 이 빌드가 아는 캐릭터를 가격 모름으로. */
val MeStore.shopRows: List<ShopCharacterRow>
    get() = shopCharacters.ifEmpty {
        MeCharacterCards.knownIDs.filter { it != MeCharacterCards.aingID }.map { ShopCharacterRow(id = it) }
    }

/**
 * 고르기 목록: 아잉 + 이 빌드가 아는 캐릭터 + 서버가 준 모르는 캐릭터. 뽑기 전용은 서버가 말했거나 내가 가졌을 때만(상점을 아직 못 읽었으면
 * 막지 않는다). 생일 선물 전용(케이크 둘)은 **가진 사람에게만** 선다 — 지금 입고 있으면(착용값을 안다) 가진 것이다.
 */
val MeStore.pickerIDs: List<String>
    get() {
        val ids = MeCharacterCards.knownIDs.filter { id ->
            if (isGiftOnly(id)) isOwned(id) || isWearing(id)
            else !shopState.hasLoaded || !isGachaOnly(id) || isOwned(id) || shopCharacters.any { it.id == id }
        }.toMutableList()
        for (row in shopCharacters) {
            if (row.id in ids) continue
            if (row.isGiftOnly && !(isOwned(row.id) || isWearing(row.id))) continue
            ids += row.id
        }
        return ids
    }

/** 지금 입고 있는가(착용값을 알 때만). */
fun MeStore.isWearing(id: String): Boolean = equippedLoaded && equippedCharacterID == id

/** 생일 선물로만 얻는 캐릭터인가(케이크 아잉이 둘 — 내장 id 는 표식과 무관하게 언제나, 그 밖은 서버 `gift_only`). */
fun MeStore.isGiftOnly(id: String): Boolean =
    CharacterCatalog.isGiftOnlyBuiltIn(id) || shopCharacters.firstOrNull { it.id == id }?.isGiftOnly == true

fun MeStore.isOwned(id: String): Boolean = id == MeCharacterCards.aingID || id in ownedCharacterIDs

/** 고를 수 있는가. 상점을 아직 못 읽었으면 막지 않는다(서버가 `not_owned` 로 거절한다). */
fun MeStore.isUnlocked(id: String): Boolean = !shopState.hasLoaded || isOwned(id)

/** 상점가. **살 수 있는 줄만** 값이 있다 — 뽑기 전용의 명목값(1000)을 쓰면 [1000 사기]가 켜지고 서버가 `not_for_sale` 로 거절한다. */
fun MeStore.price(id: String): Long? {
    val row = shopCharacters.firstOrNull { it.id == id } ?: return null
    return if (row.isPurchasable) row.price else null
}

/** 뽑기·조각 교환으로만 얻는 캐릭터인가(서버 표식 · 내장 뽑기 전용 둘 — 케이크는 선물 전용이 이긴다). */
fun MeStore.isGachaOnly(id: String): Boolean {
    if (CharacterCatalog.isGiftOnlyBuiltIn(id)) return false
    return CharacterCatalog.isGachaOnlyBuiltIn(id) || shopCharacters.firstOrNull { it.id == id }?.isGachaOnly == true
}

// MARK: 상점

/** 카드를 눌렀을 때. **고르기만 한다.** 가진 것은 고르지 않고 그 사실을 말한다. 같은 것을 다시 누르면 선택을 푼다. */
fun MeStore.selectShopItem(id: String) {
    if (purchasingID != null) return
    shopGachaHintID = null
    shopGiftHintID = null
    if (isOwned(id)) {
        shopSelection = null
        shopNotice = MeText.alreadyOwned
        return
    }
    // 생일 선물 전용은 사는 줄도 뽑는 줄도 아니다 — 얻는 길만 말한다(사기 단추를 세우지 않는다). 다시 눌러도 풀지 않는다.
    if (isGiftOnly(id)) {
        shopSelection = null
        shopNotice = CakeGiftText.lockedHint
        shopGiftHintID = id
        return
    }
    // 뽑기 전용은 사는 줄이 아니다 — 얻는 길(뽑기 · 조각 교환)을 말한다.
    if (isGachaOnly(id)) {
        shopSelection = null
        shopNotice = null
        shopGachaHintID = id
        return
    }
    shopSelection = if (shopSelection == id) null else id
    shopNotice = null
}

val MeStore.shopSelectionPrice: Long? get() = shopSelection?.let { price(it) }

/** 지금 고른 것을 살 수 있는가. 잔량이나 값을 **모르면 false**. */
val MeStore.canConfirmPurchase: Boolean
    get() {
        if (purchasingID != null || shopSelection == null) return false
        val have = rubyBalance ?: return false
        val price = shopSelectionPrice ?: return false
        return have >= price
    }

/** 하단 바 두 번째 줄: 안내가 있으면 안내, 모자라면 모자란 만큼. */
val MeStore.shopBarDetail: String?
    get() {
        shopNotice?.let { return it }
        shopGachaHintID?.let { return MeText.gachaOnlyNotice(MeCharacterCards.displayName(it), gachaShardCost(it)) }
        if (shopSelection == null) return null
        val price = shopSelectionPrice ?: return null
        val have = rubyBalance ?: return null
        if (have >= price) return null
        return SharedText.shortfallNotice(price, have)
    }

/** INV-MeStoreCharacters-42a6fefb 이식: **실제 구매는 여기 하나뿐이다**(확인 대화상자의 [구매하기]만 부른다). */
fun MeStore.confirmPurchase() {
    val id = shopSelection ?: return
    if (purchasingID != null || !context.sessionStore.isSignedIn) return
    val have = rubyBalance
    val price = shopSelectionPrice
    if (have == null || price == null) {
        launch { loadShop() }
        return
    }
    if (have < price) {
        shopNotice = SharedText.shortfallNotice(price, have)
        return
    }
    purchasingID = id
    shopNotice = null
    val generation = context.generation
    val service = context.service
    launch {
        try {
            val protocolVersion = shopProtocolVersion().toLong()
            val response = try {
                context.withSessionRetry { s -> service.buyCharacter(s.accessToken, id, protocolVersion) }
            } catch (e: Throwable) {
                if (generation != context.generation) return@launch
                if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return@launch
                shopNotice = MeText.buyFailed
                return@launch
            }
            applyPurchaseResponse(response, id, generation)
        } finally {
            if (generation == context.generation) purchasingID = null
        }
    }
}

/**
 * 구매 응답을 화면에 옮긴다. **보낼 때의 세대가 아니면 아무것도 안 한다**(응답과 로그아웃이 경합하면 앞 계정의 루비·보유가 다음 계정에 선다).
 * 잔량은 **도장 없이 언제나 쓴다** — 누른 사람 자신이 방금 만든 결과다.
 */
internal suspend fun MeStore.applyPurchaseResponse(response: BuyCharacterResponse, id: String, generation: Int) {
    if (generation != context.generation) return
    response.rubyBalance?.let { context.ruby.rubyBalance = it }
    when (response.status) {
        "ok", "already_owned" -> {
            ownedCharacterIDs = ownedCharacterIDs + id
            shopSelection = null
            shopNotice = if (response.status == "ok") MeText.bought else MeText.alreadyOwned
            loadShop()
        }
        "insufficient" -> shopNotice = SharedText.shortfallNotice(response.need, response.have)
        else -> shopNotice = MeText.buyFailed
    }
}

// MARK: 고르기

/** 캐릭터를 입는다(`set_character` — 아잉은 null 로 기본값 되돌리기). 안 가진 캐릭터는 서버에 묻기 전에 막고 얻는 길을 말한다. */
fun MeStore.chooseCharacter(id: String) {
    if (savingCharacterID != null || !context.sessionStore.isSignedIn) return
    if (!isUnlocked(id)) {
        val name = MeCharacterCards.displayName(id)
        characterNotice = when {
            isGiftOnly(id) -> CakeGiftText.lockedHint
            isGachaOnly(id) -> MeText.lockedGachaCharacter(name, gachaShardCost(id))
            else -> MeText.lockedCharacter(name)
        }
        isCharacterNoticeError = false
        return
    }
    if (id == equippedCharacterID && equippedLoaded) return
    savingCharacterID = id
    characterNotice = null
    isCharacterNoticeError = false
    val generation = context.generation
    val service = context.service
    val target: String? = if (id == MeCharacterCards.aingID) null else id
    launch {
        var needsReread = false
        try {
            val response = context.withSessionRetry { s -> service.setCharacter(s.accessToken, target) }
            if (generation != context.generation) return@launch
            // 저장 전·저장 중에 나간 착용 GET 은 서버가 저장 전에 읽었을 수 있다 — 끝나는 순간 순번을 올려 늦게 와도 버린다.
            nextSerial("equipped")
            savingCharacterID = null
            when (response.status) {
                "ok" -> {
                    equippedServerID = CharacterSyncDecision.normalized(response.character) ?: target
                    equippedLoaded = true
                    equippedLoadFailed = false
                    context.meLinks.noteMyEquipped(equippedServerID)
                    characterNotice = MeText.characterSaved
                }
                "not_owned" -> {
                    // 다른 기기에서 소유가 사라졌다 — 상점 상태를 다시 읽어 화면을 사실에 맞춘다.
                    ownedCharacterIDs = ownedCharacterIDs - id
                    characterNotice = when {
                        isGiftOnly(id) -> CakeGiftText.lockedHint
                        isGachaOnly(id) -> MeText.gachaCharacterNotOwned
                        else -> MeText.characterNotOwned
                    }
                    isCharacterNoticeError = true
                    needsReread = !equippedLoaded
                    loadShop()
                }
                else -> {
                    characterNotice = MeText.characterSaveFailed
                    isCharacterNoticeError = true
                    needsReread = !equippedLoaded
                }
            }
        } catch (e: Throwable) {
            if (generation != context.generation) return@launch
            nextSerial("equipped")
            savingCharacterID = null
            if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return@launch
            characterNotice = MeText.characterSaveFailed
            isCharacterNoticeError = true
            needsReread = !equippedLoaded
        }
        // 버린 GET 이 착용값을 처음 알려 줄 참이었다면(아직 모름) 저장이 실패한 지금 다시 묻는다.
        if (needsReread && generation == context.generation) loadEquippedCharacter()
    }
}

/** 상점·고르기 화면이 열릴 때: 로컬 캐시를 믿지 않고 다시 읽는다(가격·보유는 다른 기기에서 바뀐다). */
fun MeStore.charactersDidAppear() {
    if (!context.sessionStore.isSignedIn) return
    if (!shopState.isLoading) launch { loadShop() }
    launch { loadEquippedCharacter() }
}

fun MeStore.shopDidDisappear() {
    shopNotice = null
    shopGachaHintID = null
    shopGiftHintID = null
    if (purchasingID == null) shopSelection = null
    gachaDidDisappear()
}
