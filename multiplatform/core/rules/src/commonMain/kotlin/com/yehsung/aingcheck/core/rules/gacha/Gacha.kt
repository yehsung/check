// 원본: Sources/CheckCore/Gacha.swift @ 1b8260d (와이어 포함 전부 — C§3.2 B-1. 서비스 래퍼 `extension SupabaseWorkService` 는 net(W1-d) 몫)
package com.yehsung.aingcheck.core.rules.gacha

import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import com.yehsung.aingcheck.core.rules.character.CharacterManifest
import com.yehsung.aingcheck.core.rules.format.SharedText
import com.yehsung.aingcheck.core.rules.format.SwiftDecodingError
import com.yehsung.aingcheck.core.rules.format.SwiftKeyed
import com.yehsung.aingcheck.core.rules.format.SwiftValue
import com.yehsung.aingcheck.core.rules.format.convertFromSnakeCase
import com.yehsung.aingcheck.core.rules.format.roundedHalfAwayFromZero
import com.yehsung.aingcheck.core.rules.format.swiftKeyed
import com.yehsung.aingcheck.core.rules.text.TextScalars
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.abs

// 캐릭터 뽑기(v0.3.54 맥 · 1.0.8 폰). 서버 정본은 gacha 마이그레이션. 이 파일이 지키는 것:
// ① 이중 과금이 원리적으로 없다 — 동작 한 번에 request_id 하나, 결과를 모르는 실패에서는 그 id 를 **쥔 채** 다시 묻는다(C§4 #26).
// ② 루비·조각은 서버가 말한다 — 응답의 잔량·조각 수로만 고친다.
// ③ 맥·폰·Android 가 한 벌 — 판정과 문구는 여기서, 화면은 그리기만.
// ④ 확률은 서버 표 그대로(순서까지). 합 ≠ 100% 면 뽑기를 열지 않는다(C§4 #27).

/**
 * `shop_state.gacha` — `{price, shards, odds: [{character_id, percent}], shard_costs: {id: n}}`.
 * INV-Gacha-f8ff63e4 이식: **이 타입의 디코드는 throw 하지 않는다**(`ShopStateResponse` 안이라 한 칸이 깨지면 상점 전체가 죽는다) —
 * 모양이 틀린 칸은 null, 깨진 확률 행 · 교환값은 그 행만 버린다. 화면은 [isUsable] 로 "뽑기를 열 만큼 아는가"를 묻는다.
 */
data class GachaInfo(
    val price: Long? = null,
    val shards: Long? = null,
    /** 결과 확률표 — **서버 순서 그대로**(정렬하지 않는다). */
    val odds: List<GachaOddsEntry>? = null,
    /** 조각 교환값(id → 조각 수). `[String: T]` 키는 snake 변환을 타지 않는다(C§4 #37 — 키가 id 그대로). */
    val shardCosts: Map<String, Long>? = null,
) {
    /** 확률표의 합(%). 표가 없으면 0. 서버 순서대로 더한다(부동소수 합의 순서가 비트를 정한다). */
    val totalPercent: Double
        get() = (odds ?: emptyList()).fold(0.0) { sum, entry -> sum + entry.percent }

    /** 행이 있고 합이 100%(오차 0.01 이내). 깨진 행을 버렸으면 거짓이 된다. */
    val hasCompleteOdds: Boolean
        get() {
            val odds = odds ?: return false
            if (odds.isEmpty()) return false
            return abs(totalPercent - 100) < 0.01
        }

    /** 값과 완전한 확률표 — 하나라도 모르면 뽑기 카드를 숨긴다. */
    val isUsable: Boolean get() = price != null && hasCompleteOdds

    companion object {
        /** Swift `init(from:)` — 객체가 아니면 빈 정보(throw 하지 않는다). */
        fun decode(element: JsonElement): GachaInfo {
            val obj = element as? JsonObject ?: return GachaInfo()
            val c = SwiftKeyed(obj)
            return GachaInfo(
                price = c.lossyInt("price"),
                shards = c.lossyInt("shards"),
                odds = lossyOdds(c),
                shardCosts = lossyCosts(obj),
            )
        }

        private fun lossyOdds(c: SwiftKeyed): List<GachaOddsEntry>? {
            if (!c.contains("odds")) return null
            val list = c.element("odds") as? JsonArray ?: return null
            return list.mapNotNull { GachaOddsEntry.decodeOrNull(it) }
        }

        /** 교환표: 키는 **원문 그대로**(snake 변환 없음), 값은 정수가 아니면 그 값만 버린다. */
        private fun lossyCosts(obj: JsonObject): Map<String, Long>? {
            // Swift CodingKey `shardCosts` 는 전선 키를 convertFromSnakeCase 한 이름으로 찾는다 — 사전 안쪽 키는 변환하지 않는다.
            val raw = obj.entries.lastOrNull { convertFromSnakeCase(it.key) == "shardCosts" }?.value ?: return null
            val inner = raw as? JsonObject ?: return null
            val out = LinkedHashMap<String, Long>()
            for ((key, value) in inner) {
                val number = try { SwiftValue.int(value) } catch (e: SwiftDecodingError) { null }
                if (number != null) out[key] = number
            }
            return out
        }
    }
}

/** 확률표 한 줄. `percent` 는 소수로 받는다(정수만 받으면 2.5 하나에 행이 사라져 표가 불완전해진다). */
data class GachaOddsEntry(val characterID: String, val percent: Double) {
    companion object {
        /** 합성 Decodable — character_id(글자) · percent(수) 둘 다 필수. 실패면 null(그 행만 버린다). */
        fun decodeOrNull(element: JsonElement): GachaOddsEntry? = try {
            val c = swiftKeyed(element)
            GachaOddsEntry(c.string("characterId"), c.decode("percent", SwiftValue::double))
        } catch (e: SwiftDecodingError) {
            null
        }
    }
}

/** `gacha_pull(p_protocol, p_request_id)` 본문 — **키 둘을 언제나 싣는다**(C§4 #10). request_id 는 소문자 uuid. */
data class GachaPullRequest(val pProtocol: Int, val pRequestId: String) {
    fun body(): JsonObject = JsonObject(linkedMapOf("p_protocol" to JsonPrimitive(pProtocol), "p_request_id" to JsonPrimitive(pRequestId)))

    companion object {
        fun of(protocolVersion: Int, requestID: String): GachaPullRequest = GachaPullRequest(protocolVersion, requestID.lowercase())
    }
}

/** `gacha_exchange(p_character_id, p_protocol, p_request_id)` 본문 — 키 셋을 언제나 싣는다. */
data class GachaExchangeRequest(val pCharacterId: String, val pProtocol: Int, val pRequestId: String) {
    fun body(): JsonObject = JsonObject(linkedMapOf(
        "p_character_id" to JsonPrimitive(pCharacterId), "p_protocol" to JsonPrimitive(pProtocol), "p_request_id" to JsonPrimitive(pRequestId),
    ))

    companion object {
        fun of(characterID: String, protocolVersion: Int, requestID: String): GachaExchangeRequest =
            GachaExchangeRequest(characterID, protocolVersion, requestID.lowercase())
    }
}

/** `gacha_pull` status. 모르는 값은 `unknown(원문)` — 새 어휘가 생겨도 디코드가 죽지 않는다. */
sealed interface GachaPullStatus {
    val raw: String

    data object ok : GachaPullStatus { override val raw = "ok" }
    data object notSignedIn : GachaPullStatus { override val raw = "not_signed_in" }
    data object needsUpdate : GachaPullStatus { override val raw = "needs_update" }
    data object insufficient : GachaPullStatus { override val raw = "insufficient" }
    data object invalid : GachaPullStatus { override val raw = "invalid" }
    data class unknown(override val raw: String) : GachaPullStatus

    companion object {
        fun of(raw: String): GachaPullStatus = when (raw) {
            "ok" -> ok
            "not_signed_in" -> notSignedIn
            "needs_update" -> needsUpdate
            "insufficient" -> insufficient
            "invalid" -> invalid
            else -> unknown(raw)
        }
    }
}

/** `gacha_exchange` status. */
sealed interface GachaExchangeStatus {
    val raw: String

    data object ok : GachaExchangeStatus { override val raw = "ok" }
    data object notSignedIn : GachaExchangeStatus { override val raw = "not_signed_in" }
    data object needsUpdate : GachaExchangeStatus { override val raw = "needs_update" }
    data object notExchangeable : GachaExchangeStatus { override val raw = "not_exchangeable" }
    data object alreadyOwned : GachaExchangeStatus { override val raw = "already_owned" }
    data object insufficientShards : GachaExchangeStatus { override val raw = "insufficient_shards" }
    data class unknown(override val raw: String) : GachaExchangeStatus

    companion object {
        fun of(raw: String): GachaExchangeStatus = when (raw) {
            "ok" -> ok
            "not_signed_in" -> notSignedIn
            "needs_update" -> needsUpdate
            "not_exchangeable" -> notExchangeable
            "already_owned" -> alreadyOwned
            "insufficient_shards" -> insufficientShards
            else -> unknown(raw)
        }
    }
}

/**
 * `gacha_pull` 응답. **status 만 필수**(없거나 글자가 아니면 [SwiftDecodingError] — 결과를 모르는 응답이라 호출부는 같은 request_id 로
 * 다시 묻는다). 나머지 칸은 모양이 틀려도 null 로 삼킨다.
 */
data class GachaPullResponse(
    val status: GachaPullStatus,
    val characterID: String? = null,
    val duplicate: Boolean? = null,
    val shardsGained: Long? = null,
    val shards: Long? = null,
    val rubyBalance: Long? = null,
    val price: Long? = null,
    val requestID: String? = null,
    val replayed: Boolean? = null,
    val need: Long? = null,
    val have: Long? = null,
) {
    companion object {
        fun decode(element: JsonElement): GachaPullResponse {
            val c = swiftKeyed(element)
            return GachaPullResponse(
                status = GachaPullStatus.of(c.string("status")),
                characterID = c.lossyString("characterId"),
                duplicate = c.lossyBool("duplicate"),
                shardsGained = c.lossyInt("shardsGained"),
                shards = c.lossyInt("shards"),
                rubyBalance = c.lossyInt("rubyBalance"),
                price = c.lossyInt("price"),
                requestID = c.lossyString("requestId"),
                replayed = c.lossyBool("replayed"),
                need = c.lossyInt("need"),
                have = c.lossyInt("have"),
            )
        }
    }
}

/** `gacha_exchange` 응답. 규약은 [GachaPullResponse] 와 같다. */
data class GachaExchangeResponse(
    val status: GachaExchangeStatus,
    val characterID: String? = null,
    val shards: Long? = null,
    val cost: Long? = null,
    val requestID: String? = null,
    val replayed: Boolean? = null,
    val need: Long? = null,
    val have: Long? = null,
) {
    companion object {
        fun decode(element: JsonElement): GachaExchangeResponse {
            val c = swiftKeyed(element)
            return GachaExchangeResponse(
                status = GachaExchangeStatus.of(c.string("status")),
                characterID = c.lossyString("characterId"),
                shards = c.lossyInt("shards"),
                cost = c.lossyInt("cost"),
                requestID = c.lossyString("requestId"),
                replayed = c.lossyBool("replayed"),
                need = c.lossyInt("need"),
                have = c.lossyInt("have"),
            )
        }
    }
}

// MARK: - 도메인 — 결과 분류

/** 뽑기 한 번의 결과(서버 ok 응답에서만 만든다). */
data class GachaPullResult(
    val characterID: String,
    val isDuplicate: Boolean,
    /** 이번에 얻은 조각. 서버가 안 줬으면 규칙대로(중복 = 1, 처음 = 0). */
    val shardsGained: Long,
    val shards: Long?,
    val rubyBalance: Long?,
    val replayed: Boolean,
) {
    enum class Kind { gold, rainbow, newCharacter, duplicate }

    val isGold: Boolean get() = CharacterCatalog.isGoldAing(characterID)
    val isRainbow: Boolean get() = CharacterCatalog.isRainbowAing(characterID)

    val kind: Kind
        get() = when {
            isGold -> Kind.gold
            isRainbow -> Kind.rainbow
            isDuplicate -> Kind.duplicate
            else -> Kind.newCharacter
        }

    /** 이 결과로 **새로 갖게 된** id(중복이면 null). */
    val newlyOwnedID: String? get() = if (isDuplicate) null else characterID
}

/** 뽑기 호출의 도메인 결과. 모르는 status 는 `failed(원문)`. */
sealed interface GachaPullOutcome {
    data class pulled(val result: GachaPullResult) : GachaPullOutcome
    data class insufficient(val need: Long?, val have: Long?) : GachaPullOutcome
    data object needsUpdate : GachaPullOutcome
    data object notSignedIn : GachaPullOutcome
    data object invalid : GachaPullOutcome
    /** 서버에 뽑기 함수가 아직 없다(PGRST202 · 404). throw 로만 온다([fromError]). */
    data object unavailable : GachaPullOutcome
    data class failed(val status: String) : GachaPullOutcome

    companion object {
        fun from(response: GachaPullResponse): GachaPullOutcome = when (val status = response.status) {
            GachaPullStatus.ok -> {
                val id = response.characterID
                if (id.isNullOrEmpty()) {
                    failed(status.raw)
                } else {
                    val duplicate = response.duplicate ?: false
                    pulled(GachaPullResult(id, duplicate, response.shardsGained ?: if (duplicate) 1 else 0, response.shards, response.rubyBalance,
                        response.replayed ?: false))
                }
            }
            GachaPullStatus.insufficient -> insufficient(response.need, response.have)
            GachaPullStatus.needsUpdate -> needsUpdate
            GachaPullStatus.notSignedIn -> notSignedIn
            GachaPullStatus.invalid -> invalid
            is GachaPullStatus.unknown -> failed(status.raw)
        }

        /**
         * throw 로 온 실패 중 **결과를 아는 것**만 값으로 — 함수 없음(`BlockReportRules.isMissingFunction`)이면 [unavailable].
         * 그 밖(오프라인 · 5xx · 해석 실패)은 null — 서버가 처리했는지 모르므로 **request_id 를 쥔 채** 다시 묻는다.
         */
        fun fromError(isMissingFunction: Boolean): GachaPullOutcome? = if (isMissingFunction) unavailable else null
    }
}

/** 교환 호출의 도메인 결과. */
sealed interface GachaExchangeOutcome {
    data class exchanged(val characterID: String, val shards: Long?, val cost: Long?, val replayed: Boolean) : GachaExchangeOutcome
    data object alreadyOwned : GachaExchangeOutcome
    data object notExchangeable : GachaExchangeOutcome
    data class insufficientShards(val need: Long?, val have: Long?) : GachaExchangeOutcome
    data object needsUpdate : GachaExchangeOutcome
    data object notSignedIn : GachaExchangeOutcome
    data object unavailable : GachaExchangeOutcome
    data class failed(val status: String) : GachaExchangeOutcome

    companion object {
        /** `requestedID` 는 보낸 id — 서버가 ok 에 id 를 안 실었을 때만 쓴다. */
        fun from(response: GachaExchangeResponse, requestedID: String): GachaExchangeOutcome = when (val status = response.status) {
            GachaExchangeStatus.ok -> exchanged(response.characterID ?: requestedID, response.shards, response.cost, response.replayed ?: false)
            GachaExchangeStatus.alreadyOwned -> alreadyOwned
            GachaExchangeStatus.notExchangeable -> notExchangeable
            GachaExchangeStatus.insufficientShards -> insufficientShards(response.need, response.have)
            GachaExchangeStatus.needsUpdate -> needsUpdate
            GachaExchangeStatus.notSignedIn -> notSignedIn
            is GachaExchangeStatus.unknown -> failed(status.raw)
        }

        fun fromError(isMissingFunction: Boolean): GachaExchangeOutcome? = if (isMissingFunction) unavailable else null
    }
}

// MARK: - 도메인 — request_id 수명

/**
 * 사용자 동작 한 번 = request_id 하나(C§4 #26). 결과를 모르는 실패 뒤 **같은 동작**을 다시 누르면 같은 id 를 돌려준다.
 * 버리는 때는 서버가 답을 줬을 때 · 함수가 없다는 것이 확실할 때뿐. 동작마다 칸이 따로다(교환은 캐릭터마다). id 는 소문자 uuid 글자.
 */
class GachaRequestIDs {
    var pull: String? = null
        private set
    private val exchangeIDs = LinkedHashMap<String, String>()
    val exchange: Map<String, String> get() = exchangeIDs

    /** 뽑기 요청 id — 쥔 것이 있으면 그것, 없으면 새로 만든다(만든 값을 쥔다). */
    fun pullID(make: () -> String): String {
        pull?.let { return it }
        val made = make().lowercase()
        pull = made
        return made
    }

    fun exchangeID(characterID: String, make: () -> String): String {
        exchangeIDs[characterID]?.let { return it }
        val made = make().lowercase()
        exchangeIDs[characterID] = made
        return made
    }

    /** 서버가 답을 줬다 — 그 id 를 버린다. 다른 id 가 쥐어져 있으면(그 사이 새 동작) 건드리지 않는다. */
    fun settlePull(id: String) {
        if (pull == id.lowercase()) pull = null
    }

    fun settleExchange(id: String, characterID: String) {
        if (exchangeIDs[characterID] == id.lowercase()) exchangeIDs.remove(characterID)
    }

    /** 로그아웃·계정 전환 — 앞 계정의 id 를 다음 계정이 쓰지 않게. */
    fun reset() {
        pull = null
        exchangeIDs.clear()
    }
}

// MARK: - 도메인 — 판정

sealed interface GachaPullAvailability {
    data class ready(val price: Long) : GachaPullAvailability
    data class short(val price: Long, val missing: Long) : GachaPullAvailability
    /** 잔량을 모른다(버튼 비활성 — 모르면서 깎지 않는다). */
    data class unknownBalance(val price: Long) : GachaPullAvailability
    data object unavailable : GachaPullAvailability

    val canPull: Boolean get() = this is ready
}

sealed interface GachaExchangeAvailability {
    data object owned : GachaExchangeAvailability
    data class available(val costValue: Long) : GachaExchangeAvailability
    data class short(val costValue: Long, val missing: Long) : GachaExchangeAvailability
    data class unknownShards(val costValue: Long) : GachaExchangeAvailability
    data object notExchangeable : GachaExchangeAvailability

    val canExchange: Boolean get() = this is available

    val cost: Long?
        get() = when (this) {
            is available -> costValue
            is short -> costValue
            is unknownShards -> costValue
            owned, notExchangeable -> null
        }
}

/**
 * `shop_state.characters` 한 줄 중 뽑기 규칙이 읽는 세 칸(Swift `ShopCharacterRow` 의 id · price · gachaOnly).
 * 그 행 타입은 와이어(W1-d)이고 rules 는 wire 보다 먼저 섰다 — 병합 뒤 W2-c 가 `ShopCharacterRow` 를 이 꼴로 넘긴다(필드 이름 같음).
 */
data class GachaShopRow(val id: String, val price: Long?, val gachaOnly: Boolean?)

/** 확률표 한 줄(화면용). */
data class GachaOddsRow(
    val characterID: String,
    val name: String,
    val percent: Double,
    val percentText: String,
    val shopPrice: Long?,
    val priceText: String,
    val isGachaOnly: Boolean,
    val shardCost: Long?,
) {
    val id: String get() = characterID
    val isGold: Boolean get() = CharacterCatalog.isGoldAing(characterID)
    val isRainbow: Boolean get() = CharacterCatalog.isRainbowAing(characterID)
    val finish: CharacterManifest.Finish get() = CharacterManifest.Finish.of(characterID)
}

/** 교환 목록 한 줄(화면용). */
data class GachaExchangeRow(val characterID: String, val name: String, val availability: GachaExchangeAvailability) {
    val id: String get() = characterID
}

object GachaRules {
    /** 뽑을 수 있는가 — 판정의 권위는 서버다(버튼을 잠그고 이유를 말하는 문). */
    fun pullAvailability(info: GachaInfo?, rubyBalance: Long?): GachaPullAvailability {
        if (info == null || !info.isUsable) return GachaPullAvailability.unavailable
        val price = info.price ?: return GachaPullAvailability.unavailable
        val balance = rubyBalance ?: return GachaPullAvailability.unknownBalance(price)
        if (balance < price) return GachaPullAvailability.short(price, price - balance)
        return GachaPullAvailability.ready(price)
    }

    /** 한 캐릭터의 교환 가능성. 보유가 먼저다(가진 것은 값과 무관하게 "보유") — 단 교환표에 없거나 교환 불가면 그 전에 끝난다. */
    fun exchangeAvailability(characterID: String, isOwned: Boolean, shards: Long?, shardCosts: Map<String, Long>?): GachaExchangeAvailability {
        if (isNeverExchangeable(characterID)) return GachaExchangeAvailability.notExchangeable
        val cost = shardCosts?.get(characterID) ?: return GachaExchangeAvailability.notExchangeable
        if (cost <= 0) return GachaExchangeAvailability.notExchangeable
        if (isOwned) return GachaExchangeAvailability.owned
        val have = shards ?: return GachaExchangeAvailability.unknownShards(cost)
        if (have < cost) return GachaExchangeAvailability.short(cost, cost - have)
        return GachaExchangeAvailability.available(cost)
    }

    /** 확률표 → 화면 줄. **서버 순서 그대로**, 상점가는 `shop_state.characters` 의 값(같은 id 가 둘이면 앞의 것). */
    fun oddsRows(info: GachaInfo, shopRows: List<GachaShopRow>, displayName: (String) -> String?): List<GachaOddsRow> {
        val rowsByID = LinkedHashMap<String, GachaShopRow>()
        for (row in shopRows) if (row.id !in rowsByID) rowsByID[row.id] = row
        return (info.odds ?: emptyList()).map { entry ->
            val id = entry.characterID
            val row = rowsByID[id]
            // 서버 표식이 참이면 뽑기 전용 · 황금·무지개는 표식과 무관하게 언제나 뽑기 전용.
            val gachaOnly = row?.gachaOnly == true || CharacterCatalog.isGachaOnlyBuiltIn(id)
            val price = if (gachaOnly) null else row?.price
            val cost = if (isNeverExchangeable(id)) null else info.shardCosts?.get(id)?.takeIf { it > 0 }
            val priceText = when {
                gachaOnly -> GachaText.gachaOnlyPrice(cost)
                price != null -> "$price"
                else -> GachaText.unknownValue
            }
            GachaOddsRow(id, name(id, displayName), entry.percent, GachaText.percent(entry.percent), price, priceText, gachaOnly, cost)
        }
    }

    /**
     * 교환 목록. **황금 맨 위 · 무지개 다음**, 그다음 확률표 순서, 확률표에 없는 교환값은 뒤에 id 순.
     * 교환표에 없는 캐릭터 · 교환 불가는 줄을 만들지 않는다.
     */
    fun exchangeRows(info: GachaInfo, ownedIDs: Set<String>, displayName: (String) -> String?): List<GachaExchangeRow> {
        val costs = info.shardCosts ?: emptyMap()
        val ordered = ArrayList<String>()
        for (entry in info.odds ?: emptyList()) {
            if (costs.containsKey(entry.characterID) && entry.characterID !in ordered) ordered += entry.characterID
        }
        ordered += costs.keys.filter { it !in ordered }.sorted()
        val rare = CharacterCatalog.gachaOnlyBuiltInIDs.filter { it in ordered }
        val final = rare + ordered.filter { it !in rare }
        return final.mapNotNull { id ->
            val availability = exchangeAvailability(id, id in ownedIDs, info.shards, costs)
            if (availability == GachaExchangeAvailability.notExchangeable) null else GachaExchangeRow(id, name(id, displayName), availability)
        }
    }

    /** 조각으로 **절대** 못 바꾸는 캐릭터 — 아잉(무료 기본)과 생일 선물 전용(케이크 둘). 황금은 여기 없다(교환표 값만큼 교환된다). */
    fun isNeverExchangeable(id: String): Boolean = id == CharacterCatalog.builtInAingID || CharacterCatalog.isGiftOnlyBuiltIn(id)

    /** 이름 해석(호출부 → 내장 이름 → id). 호출부 이름은 앞뒤 공백을 지우고 비면 다음으로. */
    fun name(id: String, displayName: (String) -> String?): String {
        val given = displayName(id)?.let(TextScalars::trimmingWhitespacesAndNewlines)
        if (!given.isNullOrEmpty()) return given
        CharacterCatalog.builtIns.firstOrNull { it.id == id }?.let { return it.displayName }
        return id
    }
}

// MARK: - 문구

/** 뽑기 문구(해요체 — "도박"·"베팅" 같은 말은 쓰지 않는다). */
object GachaText {
    const val title = "캐릭터 뽑기"
    const val pullButton = "뽑기"
    fun pullButton(price: Long): String = "$pullButton · $price"
    const val oddsButton = "확률 보기"
    const val oddsTitle = "뽑기 확률"
    const val oddsFootnote = "이미 있는 캐릭터가 나오면 조각 1개를 받아요 · 조각으로 캐릭터를 바꿀 수 있어요"
    const val gachaOnly = "뽑기 전용"

    /** "뽑기 또는 조각 20개"(교환값을 모르면 · 0 이하면 "뽑기 전용"). */
    fun gachaOnlyPrice(shardCost: Long?): String {
        if (shardCost == null || shardCost <= 0) return gachaOnly
        return "뽑기 또는 ${shardCost(shardCost)}"
    }

    const val gachaOnlyHint = "뽑기나 조각 교환으로 얻을 수 있어요"
    const val unknownValue = "—"
    const val owned = "보유"
    const val exchangeButton = "교환"
    const val exchangeTitle = "조각 교환"

    /**
     * "5%" · "2.5%"(정수면 소수점 없이, 아니면 한 자리). Swift `(v * 10).rounded() / 10` — 0.5 는 0 에서 먼 쪽.
     * 한 자리 표기는 그 값의 십분의 일 정수에서 바로 만든다(printf `%.1f` 와 같은 글자 — 값이 k/10 이라 경계에 걸리지 않는다).
     */
    fun percent(value: Double): String {
        val tenths = roundedHalfAwayFromZero(value * 10)
        val n = tenths.toLong()
        if (n % 10 == 0L) return "${n / 10}%"
        val sign = if (n < 0) "-" else ""
        val absolute = abs(n)
        return "$sign${absolute / 10}.${absolute % 10}%"
    }

    fun shards(count: Long): String = "조각 ${count}개"
    fun shardCost(cost: Long): String = shards(cost)

    const val goldHeadline = "황금 아잉이!"
    const val rainbowHeadline = "무지개 아잉이!"
    fun newCharacter(name: String): String = "새 캐릭터: $name"
    fun duplicate(name: String, shardsGained: Long): String = "이미 있는 $name → 조각 +$shardsGained"

    fun rareHeadline(kind: GachaPullResult.Kind): String? = when (kind) {
        GachaPullResult.Kind.gold -> goldHeadline
        GachaPullResult.Kind.rainbow -> rainbowHeadline
        GachaPullResult.Kind.newCharacter, GachaPullResult.Kind.duplicate -> null
    }

    fun headline(result: GachaPullResult, name: String): String = when (result.kind) {
        GachaPullResult.Kind.gold -> goldHeadline
        GachaPullResult.Kind.rainbow -> rainbowHeadline
        GachaPullResult.Kind.newCharacter -> newCharacter(name)
        GachaPullResult.Kind.duplicate -> duplicate(name, result.shardsGained)
    }

    fun detail(result: GachaPullResult, name: String): String? {
        if (rareHeadline(result.kind) == null) return null
        return if (result.isDuplicate) duplicate(name, result.shardsGained) else newCharacter(name)
    }

    fun shortfall(need: Long?, have: Long?): String = SharedText.shortfallNotice(need, have)
    fun shardShortfall(missing: Long): String = "조각 ${missing}개 더 필요해요"
    const val needsUpdate = "앱을 업데이트하면 뽑을 수 있어요"
    const val unavailable = "지금은 뽑을 수 없어요"
    const val notSignedIn = "로그인하면 뽑을 수 있어요"
    const val connection = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"
    const val pullFailed = "뽑지 못했어요. 잠시 후 다시 시도해 주세요"
    const val exchangeFailed = "교환하지 못했어요. 잠시 후 다시 시도해 주세요"
    const val alreadyOwned = "이미 갖고 있어요"
    const val notExchangeable = "교환할 수 없는 캐릭터예요"
    fun exchanged(name: String): String = "교환했어요: $name"

    /** 버튼을 잠근 이유(뽑기). 뽑을 수 있거나 잔량을 모르면 null. */
    fun blockedReason(availability: GachaPullAvailability): String? = when (availability) {
        is GachaPullAvailability.ready -> null
        is GachaPullAvailability.short -> shortfall(availability.price, availability.price - availability.missing)
        is GachaPullAvailability.unknownBalance -> null
        GachaPullAvailability.unavailable -> unavailable
    }

    /** 연출이 아닌 결과의 한 줄. `pulled` 는 null. */
    fun notice(outcome: GachaPullOutcome): String? = when (outcome) {
        is GachaPullOutcome.pulled -> null
        is GachaPullOutcome.insufficient -> shortfall(outcome.need, outcome.have)
        GachaPullOutcome.needsUpdate -> needsUpdate
        GachaPullOutcome.notSignedIn -> notSignedIn
        GachaPullOutcome.unavailable -> unavailable
        GachaPullOutcome.invalid, is GachaPullOutcome.failed -> pullFailed
    }

    fun notice(outcome: GachaExchangeOutcome, name: String): String = when (outcome) {
        is GachaExchangeOutcome.exchanged -> exchanged(name)
        GachaExchangeOutcome.alreadyOwned -> alreadyOwned
        GachaExchangeOutcome.notExchangeable -> notExchangeable
        is GachaExchangeOutcome.insufficientShards -> {
            val need = outcome.need
            val have = outcome.have
            if (need != null && have != null && need > have) shardShortfall(need - have) else "조각이 모자라요"
        }
        GachaExchangeOutcome.needsUpdate -> "앱을 업데이트하면 교환할 수 있어요"
        GachaExchangeOutcome.notSignedIn -> "로그인하면 교환할 수 있어요"
        GachaExchangeOutcome.unavailable -> "지금은 교환할 수 없어요"
        is GachaExchangeOutcome.failed -> exchangeFailed
    }
}
