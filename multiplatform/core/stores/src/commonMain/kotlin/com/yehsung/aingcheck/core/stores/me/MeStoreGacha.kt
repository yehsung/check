// 원본: Sources/CheckMobileKit/Me/MeStoreGacha.swift · Sources/CheckCore/GachaMachine/GachaMachineModel.swift:28-74(GachaRevealOutcome · GachaRevealFailure — 값 몫만) @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.gachaExchange
import com.yehsung.aingcheck.core.net.gachaPull
import com.yehsung.aingcheck.core.rules.gacha.GachaExchangeAvailability
import com.yehsung.aingcheck.core.rules.gacha.GachaExchangeOutcome
import com.yehsung.aingcheck.core.rules.gacha.GachaExchangeRow
import com.yehsung.aingcheck.core.rules.gacha.GachaOddsRow
import com.yehsung.aingcheck.core.rules.gacha.GachaPullAvailability
import com.yehsung.aingcheck.core.rules.gacha.GachaPullOutcome
import com.yehsung.aingcheck.core.rules.gacha.GachaPullResult
import com.yehsung.aingcheck.core.rules.gacha.GachaRules
import com.yehsung.aingcheck.core.rules.gacha.GachaText
import com.yehsung.aingcheck.core.wire.models.GachaExchangeResponse as WireGachaExchangeResponse
import com.yehsung.aingcheck.core.wire.models.GachaPullResponse as WireGachaPullResponse
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred

// 캐릭터 뽑기(v0.3.54 맥 · 폰 1.0.8) — `gacha_pull` · `gacha_exchange`. 판정·문구·요청 id 수명은 코어(rules gacha) 한 벌이고 여기는 부르고 옮긴다.
//  - 뽑기를 여는 문은 `shop_state.gacha`(gachaInfo) — 서버가 안 주거나 **확률표 합이 100% 가 아니면** 화면이 통째로 숨는다(showsGacha).
//  - 사용자 동작 한 번 = request_id 하나. **결과를 모르는 실패**(오프라인 · 5xx · 해석 실패)는 id 를 **쥔 채** 두고 다시 누르면 같은 id 로
//    묻는다 — 서버가 이미 처리했으면 처음 결과가 `replayed` 로 오고 두 번 깎이지 않는다(C§4 #26).
//  - 루비·조각·보유는 **서버가 준 값**으로만 바꾼다. 응답 적용은 **보낸 세대**일 때만.

/** 기계가 공개할 결과(Swift `GachaRevealOutcome` 의 값 — 연출 화면은 W4-c). */
data class MeGachaReveal(
    val characterID: String,
    /** 화면 이름("여우"). */
    val name: String,
    val kind: GachaPullResult.Kind,
    /** 뽑은 **뒤** 조각 수. */
    val shardCount: Long,
    /** 이번에 얻은 조각(중복 = 보통 1, 처음 = 0). */
    val shardsGained: Long,
) {
    val shardCountBefore: Long get() = maxOf(0L, shardCount - shardsGained)

    companion object {
        /** 스토어 결과에서. [shardsBefore] 는 뽑기 **전** 조각 수 — 서버가 뒤 조각 수를 안 줬을 때만 쓴다. */
        fun of(result: GachaPullResult, name: String, shardsBefore: Long): MeGachaReveal {
            val gained = if (result.isDuplicate) maxOf(0L, result.shardsGained) else 0L
            val count = result.shards ?: (maxOf(0L, shardsBefore) + gained)
            return MeGachaReveal(result.characterID, name, result.kind, maxOf(0L, count), gained)
        }
    }
}

/** 기계가 던지는 실패 — [message] 가 기계 아래 한 줄로 뜬다. */
class MeGachaRevealFailure(override val message: String) : Exception(message)

/** 뽑기 한 번이 어떻게 끝났나(카드 · 기계 공용 몸통의 답). */
internal sealed interface GachaPullStep {
    /** 서버가 답했다(어떤 status 든 — 옮긴 뒤 · 뽑혔으면 상점 다시 읽기까지 끝난 뒤). */
    data class Answered(val outcome: GachaPullOutcome) : GachaPullStep

    /** 결과를 모른다 — request_id 를 **쥔 채** 둔다. */
    data object Unknown : GachaPullStep

    /** 로그아웃 · 취소로 버렸다. */
    data object Dropped : GachaPullStep
}

// MARK: 표시값

/** 뽑기 카드를 세울 만큼 아는가: 서버가 `gacha` 를 줬고 · 값과 **합이 100% 인** 확률표가 있다(공개 못 한 확률로 루비를 받지 않는다). */
val MeStore.showsGacha: Boolean get() = gachaInfo?.isUsable == true

/** 지금 뽑을 수 있는가(버튼 잠금 + 이유). 판정의 권위는 서버다 — 헛왕복을 줄이는 문이다. */
val MeStore.gachaPullAvailability: GachaPullAvailability get() = GachaRules.pullAvailability(gachaInfo, rubyBalance)

val MeStore.canPullGacha: Boolean get() = !isPulling && gachaPullAvailability.canPull

/** 버튼 아래 이유 한 줄(모자람 · 닫힘). 안내(실패·거절)가 있으면 그게 먼저다. */
val MeStore.gachaDetail: String? get() = gachaNotice ?: GachaText.blockedReason(gachaPullAvailability)

val MeStore.gachaShards: Long? get() = gachaInfo?.shards

/** 확률표(서버 순서 그대로 · 이름은 이 빌드의 카드 이름). */
val MeStore.gachaOddsRows: List<GachaOddsRow>
    get() {
        val info = gachaInfo ?: return emptyList()
        return GachaRules.oddsRows(info, MeWireBridge.shopRows(shopCharacters), MeGachaNames::displayName)
    }

/** 조각 교환 목록(황금 · 무지개 먼저 · 교환값은 서버 `shard_costs` 그대로). */
val MeStore.gachaExchangeRows: List<GachaExchangeRow>
    get() {
        val info = gachaInfo ?: return emptyList()
        return GachaRules.exchangeRows(info, ownedCharacterIDs + MeCharacterCards.aingID, MeGachaNames::displayName)
    }

/** 이 캐릭터의 조각 교환값(서버 `shard_costs` · 없으면 null). 문구가 값을 박지 않게 여기서 읽는다. */
fun MeStore.gachaShardCost(id: String): Long? = gachaInfo?.shardCosts?.get(id)?.takeIf { it > 0 }

fun MeStore.gachaExchangeAvailability(id: String): GachaExchangeAvailability =
    GachaRules.exchangeAvailability(id, isOwned(id), gachaInfo?.shards, gachaInfo?.shardCosts)

fun MeStore.gachaName(id: String): String = GachaRules.name(id, MeGachaNames::displayName)

// MARK: 뽑기

/** [뽑기 · 50] 한 번(카드). 떠 있는 요청이 있으면 아무것도 안 한다(연타 = 요청 하나). */
fun MeStore.pullGacha() {
    if (isPulling || !context.sessionStore.isSignedIn) return
    val availability = gachaPullAvailability
    if (!availability.canPull) {
        if (availability is GachaPullAvailability.unknownBalance) {
            // 잔량을 모르면 깎지 않는다 — 상점을 다시 읽어 잔량을 안 뒤에 다시 누르게 한다.
            launch { loadShop() }
        } else {
            gachaNotice = GachaText.blockedReason(availability)
            isGachaNoticeError = false
        }
        return
    }
    startGachaPull { }
}

/**
 * 기계가 손잡이 한 바퀴를 다 돌렸을 때 **한 번** 부른다. 카드와 **같은 몸통**([startGachaPull])을 지나고, 뽑아 줬을 때만 결과를 돌려준다.
 * 그 밖은 던진다. 요청은 **스토어의 일**로 뜬다 — 덮개가 닫혀 기다리던 쪽이 사라져도 끊기지 않는다(로그아웃만 끊는다).
 */
suspend fun MeStore.pullGachaForMachine(): MeGachaReveal {
    if (isPulling) throw MeGachaRevealFailure(MeText.gachaPullBusy)
    if (!context.sessionStore.isSignedIn) throw MeGachaRevealFailure(GachaText.notSignedIn)
    val availability = gachaPullAvailability
    if (!availability.canPull) {
        if (availability is GachaPullAvailability.unknownBalance) launch { loadShop() }
        throw MeGachaRevealFailure(GachaText.blockedReason(availability) ?: MeText.loading)
    }
    // 서버가 뒤 조각 수를 안 실었을 때만 쓰는 '앞' 값.
    val shardsBefore = gachaShards ?: 0
    val done = CompletableDeferred<GachaPullStep>()
    startGachaPull { done.complete(it) }
    return when (val step = done.await()) {
        is GachaPullStep.Answered -> when (val outcome = step.outcome) {
            is GachaPullOutcome.pulled -> MeGachaReveal.of(outcome.result, gachaName(outcome.result.characterID), shardsBefore)
            else -> throw MeGachaRevealFailure(GachaText.notice(outcome) ?: GachaText.pullFailed)
        }
        GachaPullStep.Unknown -> throw MeGachaRevealFailure(GachaText.connection)
        GachaPullStep.Dropped -> throw CancellationException("뽑기를 버렸다(로그아웃 · 취소)")
    }
}

/** 기계 손잡이를 잠글 이유(없으면 null). [machineOwnsPull] = 이 기계가 띄운 뽑기가 떠 있는가(그 판은 막지 않는다). */
fun MeStore.gachaMachineBlockedReason(machineOwnsPull: Boolean): String? {
    if (!context.sessionStore.isSignedIn) return GachaText.notSignedIn
    if (isPulling && !machineOwnsPull) return MeText.gachaPullBusy
    return when (gachaPullAvailability) {
        is GachaPullAvailability.ready, is GachaPullAvailability.short -> null
        // 잔량을 모른다 — 0 으로 그려 "모자라요"라고 거짓말하지 않는다.
        is GachaPullAvailability.unknownBalance -> MeText.loading
        GachaPullAvailability.unavailable -> GachaText.unavailable
    }
}

/** 덮개가 떴을 때: 잔량을 모르면 다시 읽는다. */
fun MeStore.gachaMachineDidAppear() {
    if (!context.sessionStore.isSignedIn || rubyBalance != null || shopState.isLoading) return
    launch { loadShop() }
}

/**
 * 요청 하나를 스토어의 일로 띄우고, 끝나면 [completion] 을 **꼭 한 번** 부른다(카드 · 기계 공용). 부르기 전에 호출부가 `!isPulling` ·
 * 로그인 · 판정 ready 를 봤다.
 */
private fun MeStore.startGachaPull(completion: (GachaPullStep) -> Unit) {
    // 사용자 동작 하나 = request_id 하나 — 결과를 모르는 채 쥔 id 가 있으면 그것을 다시 쓴다(서버가 replayed 로 처음 결과를 준다).
    val requestID = gachaRequestIDs.pullID(newRequestID)
    isPulling = true
    gachaNotice = null
    isGachaNoticeError = false
    val generation = context.generation
    val service = context.service
    launch {
        var step: GachaPullStep = GachaPullStep.Dropped
        try {
            val protocolVersion = shopProtocolVersion().toLong()
            val response = try {
                context.withSessionRetry { s -> service.gachaPull(s.accessToken, protocolVersion, requestID) }
            } catch (e: Throwable) {
                if (generation != context.generation) return@launch
                if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return@launch
                val known = GachaPullOutcome.fromError(MeWireBridge.isMissingFunction(e))
                if (known != null) {
                    // 함수가 없다(서버에서 아무것도 안 돌았다) — id 를 버려도 된다.
                    gachaRequestIDs.settlePull(requestID)
                    gachaNotice = GachaText.notice(known)
                    step = GachaPullStep.Answered(known)
                } else {
                    // 결과를 모른다 — id 를 **쥔 채** 둔다(다시 누르면 같은 id 로 묻는다).
                    gachaNotice = GachaText.connection
                    step = GachaPullStep.Unknown
                }
                isGachaNoticeError = true
                return@launch
            }
            // 옮긴 뒤(뽑혔으면 다시 읽기까지) 세대가 그대로일 때만 답이다 — 그 사이 로그아웃했으면 기계에 결과를 넘기지 않는다.
            val outcome = applyGachaPullResponse(response, requestID, generation)
            if (outcome != null && generation == context.generation) step = GachaPullStep.Answered(outcome)
        } finally {
            if (generation == context.generation) isPulling = false
            completion(step)
        }
    }
}

/** 뽑기 응답을 화면에 옮긴다. **보낼 때의 세대가 아니면 아무것도 안 한다**. 돌려주는 값: 옮긴 결과(세대가 바뀌어 버렸으면 null). */
internal suspend fun MeStore.applyGachaPullResponse(wire: WireGachaPullResponse, requestID: String, generation: Int): GachaPullOutcome? {
    if (generation != context.generation) return null
    // 서버가 답을 줬다(어떤 status 든) — 이 id 의 일은 끝났다. 다음 누름은 새 동작이다.
    gachaRequestIDs.settlePull(requestID)
    val response = MeWireBridge.pullResponse(wire)
    // 잔량·조각은 실린 것만(서버 값) — 모르는 칸을 0 으로 적지 않는다.
    response.rubyBalance?.let { context.ruby.rubyBalance = it }
    response.shards?.let { shards -> gachaInfo = gachaInfo?.copy(shards = shards) }
    val outcome = GachaPullOutcome.from(response)
    when (outcome) {
        is GachaPullOutcome.pulled -> {
            outcome.result.newlyOwnedID?.let { ownedCharacterIDs = ownedCharacterIDs + it }
            lastGachaResult = outcome.result
            gachaRevealSerial += 1
            gachaNotice = null
            isGachaNoticeError = false
            // 보유·조각·확률표를 서버 값으로 다시 맞춘다(다른 기기에서 바뀐 것까지).
            loadShop()
        }
        is GachaPullOutcome.insufficient -> {
            // 응답이 잔량을 따로 안 실었으면 서버가 말한 '가진 양'이 지금 잔량이다.
            val have = outcome.have
            if (response.rubyBalance == null && have != null) context.ruby.rubyBalance = have
            gachaNotice = GachaText.notice(outcome)
            isGachaNoticeError = true
        }
        is GachaPullOutcome.failed -> {
            // ok 인데 결과 id 가 빠졌거나 모르는 status — 잔량이 바뀌었을 수 있어 상점을 다시 읽는다.
            gachaNotice = GachaText.notice(outcome)
            isGachaNoticeError = true
            loadShop()
        }
        else -> {
            gachaNotice = GachaText.notice(outcome)
            isGachaNoticeError = true
        }
    }
    return outcome
}

// MARK: 조각 교환

/** 조각으로 캐릭터를 교환한다(확인 대화상자의 [교환하기]만 부른다). 떠 있는 교환이 있으면 아무것도 안 한다. */
fun MeStore.exchangeShards(id: String) {
    if (exchangingID != null || !context.sessionStore.isSignedIn) return
    val name = gachaName(id)
    val availability = gachaExchangeAvailability(id)
    if (!availability.canExchange) {
        exchangeNotice = MeText.exchangeBlocked(availability)
        isExchangeNoticeError = false
        return
    }
    val requestID = gachaRequestIDs.exchangeID(id, newRequestID)
    exchangingID = id
    exchangeNotice = null
    isExchangeNoticeError = false
    val generation = context.generation
    val service = context.service
    launch {
        try {
            val protocolVersion = shopProtocolVersion().toLong()
            val response = try {
                context.withSessionRetry { s -> service.gachaExchange(s.accessToken, id, protocolVersion, requestID) }
            } catch (e: Throwable) {
                if (generation != context.generation) return@launch
                if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return@launch
                val known = GachaExchangeOutcome.fromError(MeWireBridge.isMissingFunction(e))
                if (known != null) {
                    gachaRequestIDs.settleExchange(requestID, id)
                    exchangeNotice = GachaText.notice(known, name)
                } else {
                    // 결과를 모른다 — id 를 쥔 채 둔다.
                    exchangeNotice = GachaText.connection
                }
                isExchangeNoticeError = true
                return@launch
            }
            applyGachaExchangeResponse(response, id, requestID, generation)
        } finally {
            if (generation == context.generation) exchangingID = null
        }
    }
}

/** 교환 응답을 화면에 옮긴다(세대 가드 · 서버 값만). */
internal suspend fun MeStore.applyGachaExchangeResponse(wire: WireGachaExchangeResponse, id: String, requestID: String, generation: Int) {
    if (generation != context.generation) return
    gachaRequestIDs.settleExchange(requestID, id)
    val response = MeWireBridge.exchangeResponse(wire)
    response.shards?.let { shards -> gachaInfo = gachaInfo?.copy(shards = shards) }
    when (val outcome = GachaExchangeOutcome.from(response, id)) {
        is GachaExchangeOutcome.exchanged -> {
            ownedCharacterIDs = ownedCharacterIDs + outcome.characterID
            exchangeNotice = GachaText.notice(outcome, gachaName(outcome.characterID))
            isExchangeNoticeError = false
            loadShop()
        }
        GachaExchangeOutcome.alreadyOwned -> {
            // 다른 기기에서 이미 얻었다 — 보유로 맞추고 서버 값을 다시 읽는다(조각은 안 깎였다).
            ownedCharacterIDs = ownedCharacterIDs + id
            exchangeNotice = GachaText.notice(outcome, gachaName(id))
            isExchangeNoticeError = false
            loadShop()
        }
        is GachaExchangeOutcome.insufficientShards -> {
            val have = outcome.have
            if (response.shards == null && have != null) gachaInfo = gachaInfo?.copy(shards = have)
            exchangeNotice = GachaText.notice(outcome, gachaName(id))
            isExchangeNoticeError = true
        }
        else -> {
            exchangeNotice = GachaText.notice(outcome, gachaName(id))
            isExchangeNoticeError = true
        }
    }
}

// MARK: 화면 사건

fun MeStore.dismissGachaResult() {
    lastGachaResult = null
}

fun MeStore.exchangeSheetDidDisappear() {
    exchangeNotice = null
    isExchangeNoticeError = false
}

/** 상점을 떠날 때: 결과 연출·안내를 걷는다. 요청 id 는 **남긴다**(결과를 모르는 채 떠났다면 돌아와 같은 id 로 묻는다). */
internal fun MeStore.gachaDidDisappear() {
    lastGachaResult = null
    gachaNotice = null
    isGachaNoticeError = false
    exchangeNotice = null
    isExchangeNoticeError = false
}
