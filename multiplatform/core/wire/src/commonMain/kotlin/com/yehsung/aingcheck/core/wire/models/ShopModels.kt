// 원본: Sources/CheckCore/SupabaseWorkModels.swift:1588-1726(상점 — set_character·shop_state·buy_character) · CheckCore/Gacha.swift:1-370·855-872(뽑기 와이어 + lossy 보조) @ 1b8260d
package com.yehsung.aingcheck.core.wire.models

import com.yehsung.aingcheck.core.wire.character.BuiltInCharacterIds
import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.json.SwiftKeyed
import com.yehsung.aingcheck.core.wire.json.SwiftValueDecoder
import com.yehsung.aingcheck.core.wire.json.swiftTry
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Swift `SetCharacterRequest` — nil 이어도 키를 싣는다(`{"p_id": null}` = 기본 캐릭터로). encodeIfPresent 가 아니다. */
// INV-SupabaseWorkModels-7507a66b 이식: nil 일 때 키를 빼면 안 된다(`{"p_id": null}` = 기본 캐릭터).
@Serializable(with = SetCharacterRequest.Serializer::class)
data class SetCharacterRequest(val pId: String?) {
    object Serializer : KSerializer<SetCharacterRequest> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("SetCharacterRequest")
        override fun serialize(encoder: Encoder, value: SetCharacterRequest) {
            (encoder as JsonEncoder).encodeJsonElement(JsonObject(mapOf("p_id" to (value.pId?.let { JsonPrimitive(it) } ?: JsonNull))))
        }
        override fun deserialize(decoder: Decoder): SetCharacterRequest = throw UnsupportedOperationException("요청 본문은 읽지 않는다")
    }
}

@Serializable
data class SetCharacterResponse(
    @SerialName("status") val status: String,
    @SerialName("character") val character: String? = null,
    @SerialName("id") val id: String? = null,
)

// INV-SupabaseWorkModels-e5e621e7 이식: status 가 없다(조회라 실패 어휘가 없다 — 실패는 HTTP 로).
// INV-SupabaseWorkModels-bf4b876b 이식: 칸이 전부 Optional(이 키를 안 보내는 서버에서 디코드가 통째로 죽지 않게).
/** Swift `ShopStateResponse`(shop_state). 모든 칸 Optional — 서버가 칸을 넓혀도 구버전이 끊기지 않는다. */
@Serializable
data class ShopStateResponse(
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    @SerialName("ultra_balance") val ultraBalance: Long? = null,
    @SerialName("ultra_price") val ultraPrice: Long? = null,
    @SerialName("ultra_buy_max") val ultraBuyMax: Long? = null,
    @SerialName("characters") val characters: List<ShopCharacterRow>? = null,
    @SerialName("gacha") val gacha: GachaInfo? = null,
)

/** Swift `ShopCharacterRow`. 사기 단추·선물 전용·뽑기 전용 판정은 서버 칸과 내장 id 판정을 함께 본다(옛 응답 호환). */
@Serializable
data class ShopCharacterRow(
    @SerialName("id") val id: String,
    @SerialName("price") val price: Long? = null,
    @SerialName("owned") val owned: Boolean? = null,
    @SerialName("gacha_only") val gachaOnly: Boolean? = null,
    @SerialName("gift_only") val giftOnly: Boolean? = null,
) {
    /** 살 수 있다 = 뽑기 전용도 선물 전용도 아니고 값이 있다. */
    val isPurchasable: Boolean
        get() = gachaOnly != true && !BuiltInCharacterIds.isGachaOnlyBuiltIn(id) &&
            giftOnly != true && !BuiltInCharacterIds.isGiftOnlyBuiltIn(id) && price != null

    // INV-SupabaseWorkModels-746177aa 이식: 선물 전용이 먼저 이긴다(케이크 행은 gacha_only 도 싣는다).
    val isGiftOnly: Boolean get() = giftOnly == true || BuiltInCharacterIds.isGiftOnlyBuiltIn(id)

    /** 케이크는 뽑기 전용이 아니다(선물 전용이 우선). */
    val isGachaOnly: Boolean get() = !isGiftOnly && (gachaOnly == true || BuiltInCharacterIds.isGachaOnlyBuiltIn(id))
}

/** shop_state 본문. `p_protocol` 이 null 이면 키째 뺀다(= 옛 서명 `{}` — C§4 #9). */
@Serializable
data class ShopStateRequest(@SerialName("p_protocol") val pProtocol: Long? = null)

@Serializable
data class BuyCharacterRequest(
    @SerialName("p_id") val pId: String,
    @SerialName("p_protocol") val pProtocol: Long? = null,
)

@Serializable
data class BuyCharacterResponse(
    @SerialName("status") val status: String,
    @SerialName("character") val character: String? = null,
    @SerialName("price") val price: Long? = null,
    @SerialName("ruby_balance") val rubyBalance: Long? = null,
    @SerialName("need") val need: Long? = null,
    @SerialName("have") val have: Long? = null,
)

/** 상점 능력 번호의 와이어 몫(Swift `ShopWire` — 0 이면 키 생략, 404 면 5분 동안 옛 모양). 번호 파생은 W1-c(K9). */
object ShopWire {
    const val legacyProtocol: Long = 0
    /** 깃발을 믿는 기간(초) — 지나면 새 모양을 다시 묻는다(`SupabaseWorkService.swift:65-70`). */
    const val shopProtocolRecheckInterval: Double = 300.0
}

// ---------------------------------------------------------------- 뽑기 와이어(Gacha.swift:1-370)

/** `try? c.decodeIfPresent` — 없거나·null·모양이 틀리면 null(던지지 않는다). */
private fun <T : Any> SwiftKeyed.gachaLossy(key: String, ser: kotlinx.serialization.DeserializationStrategy<T>): T? = lossy(key, ser)

/** Swift `GachaInfo` — 칸 하나가 깨져도 나머지를 살린다. 객체가 아니면 빈 값. */
@Serializable(with = GachaInfo.Serializer::class)
data class GachaInfo(
    val price: Long? = null,
    val shards: Long? = null,
    val odds: List<GachaOddsEntry>? = null,
    val shardCosts: Map<String, Long>? = null,
) {
    /** 확률표 합(%). */
    val totalPercent: Double get() = (odds ?: emptyList()).fold(0.0) { acc, e -> acc + e.percent }

    /** 표가 있고 합이 100%(±0.01) — 아니면 뽑기 카드를 숨긴다(C§4 #27). */
    val hasCompleteOdds: Boolean
        get() {
            val o = odds ?: return false
            if (o.isEmpty()) return false
            return kotlin.math.abs(totalPercent - 100) < 0.01
        }

    val isUsable: Boolean get() = price != null && hasCompleteOdds

    object Serializer : SwiftDecodableSerializer<GachaInfo>("GachaInfo") {
        override fun deserialize(decoder: Decoder): GachaInfo {
            val c = swiftTry { SwiftDecoding.keyed(decoder) } ?: return GachaInfo()
            // 사전 키는 snake 변환을 타지 않는다(C§4 #37). 값 하나가 숫자가 아니면 그 값만 버린다(GachaLossyInt).
            val costs = swiftTry {
                val raw = c.raw("shard_costs") ?: return@swiftTry null
                if (raw is JsonNull) return@swiftTry null
                val obj = SwiftValueDecoder(raw, "${c.path}.shardCosts").obj()
                obj.entries.mapNotNull { (k, v) ->
                    val value = swiftTry { SwiftValueDecoder(v, "${c.path}.shardCosts.$k").decodeLong() }
                    value?.let { k to it }
                }.toMap()
            }
            return GachaInfo(
                price = c.gachaLossy("price", Long.serializer()),
                shards = c.gachaLossy("shards", Long.serializer()),
                odds = lossyOdds(c),
                shardCosts = costs,
            )
        }

        /** 원소 하나가 깨지면 그 원소만 버린다(배열이 아니면 null). */
        private fun lossyOdds(c: SwiftKeyed): List<GachaOddsEntry>? {
            if (!c.contains("odds")) return null
            val list = swiftTry { c.decoder("odds").array() } ?: return null
            return list.mapIndexedNotNull { i, e ->
                swiftTry { GachaOddsEntry.serializer().deserialize(SwiftValueDecoder(e, "${c.path}.odds[$i]")) }
            }
        }
    }
}

@Serializable
data class GachaOddsEntry(
    @SerialName("character_id") val characterID: String,
    @SerialName("percent") val percent: Double,
)

@Serializable
data class GachaPullRequest(
    @SerialName("p_protocol") val pProtocol: Long,
    /** 소문자 uuid(결과를 모르는 실패면 **쥔 채** 재시도 — C§4 #26). */
    @SerialName("p_request_id") val pRequestId: String,
)

@Serializable
data class GachaExchangeRequest(
    @SerialName("p_character_id") val pCharacterId: String,
    @SerialName("p_protocol") val pProtocol: Long,
    @SerialName("p_request_id") val pRequestId: String,
)

/** Swift `GachaPullStatus`(모르는 값은 `unknown(raw)`). */
sealed interface GachaPullStatus {
    data object Ok : GachaPullStatus
    data object NotSignedIn : GachaPullStatus
    data object NeedsUpdate : GachaPullStatus
    data object Insufficient : GachaPullStatus
    data object Invalid : GachaPullStatus
    data class Unknown(val value: String) : GachaPullStatus

    val raw: String
        get() = when (this) {
            Ok -> "ok"; NotSignedIn -> "not_signed_in"; NeedsUpdate -> "needs_update"
            Insufficient -> "insufficient"; Invalid -> "invalid"; is Unknown -> value
        }

    companion object {
        fun of(raw: String): GachaPullStatus = when (raw) {
            "ok" -> Ok; "not_signed_in" -> NotSignedIn; "needs_update" -> NeedsUpdate
            "insufficient" -> Insufficient; "invalid" -> Invalid; else -> Unknown(raw)
        }
    }
}

/** Swift `GachaExchangeStatus`. */
sealed interface GachaExchangeStatus {
    data object Ok : GachaExchangeStatus
    data object NotSignedIn : GachaExchangeStatus
    data object NeedsUpdate : GachaExchangeStatus
    data object NotExchangeable : GachaExchangeStatus
    data object AlreadyOwned : GachaExchangeStatus
    data object InsufficientShards : GachaExchangeStatus
    data class Unknown(val value: String) : GachaExchangeStatus

    val raw: String
        get() = when (this) {
            Ok -> "ok"; NotSignedIn -> "not_signed_in"; NeedsUpdate -> "needs_update"; NotExchangeable -> "not_exchangeable"
            AlreadyOwned -> "already_owned"; InsufficientShards -> "insufficient_shards"; is Unknown -> value
        }

    companion object {
        fun of(raw: String): GachaExchangeStatus = when (raw) {
            "ok" -> Ok; "not_signed_in" -> NotSignedIn; "needs_update" -> NeedsUpdate; "not_exchangeable" -> NotExchangeable
            "already_owned" -> AlreadyOwned; "insufficient_shards" -> InsufficientShards; else -> Unknown(raw)
        }
    }
}

/** Swift `GachaPullResponse` — status 만 필수, 나머지는 lossy. */
@Serializable(with = GachaPullResponse.Serializer::class)
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
    object Serializer : SwiftDecodableSerializer<GachaPullResponse>("GachaPullResponse") {
        override fun deserialize(decoder: Decoder): GachaPullResponse {
            val c = SwiftDecoding.keyed(decoder)
            return GachaPullResponse(
                status = GachaPullStatus.of(c.string("status")),
                characterID = c.lossyString("character_id"),
                duplicate = c.lossyBool("duplicate"),
                shardsGained = c.lossyLong("shards_gained"),
                shards = c.lossyLong("shards"),
                rubyBalance = c.lossyLong("ruby_balance"),
                price = c.lossyLong("price"),
                requestID = c.lossyString("request_id"),
                replayed = c.lossyBool("replayed"),
                need = c.lossyLong("need"),
                have = c.lossyLong("have"),
            )
        }
    }
}

/** Swift `GachaExchangeResponse`. */
@Serializable(with = GachaExchangeResponse.Serializer::class)
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
    object Serializer : SwiftDecodableSerializer<GachaExchangeResponse>("GachaExchangeResponse") {
        override fun deserialize(decoder: Decoder): GachaExchangeResponse {
            val c = SwiftDecoding.keyed(decoder)
            return GachaExchangeResponse(
                status = GachaExchangeStatus.of(c.string("status")),
                characterID = c.lossyString("character_id"),
                shards = c.lossyLong("shards"),
                cost = c.lossyLong("cost"),
                requestID = c.lossyString("request_id"),
                replayed = c.lossyBool("replayed"),
                need = c.lossyLong("need"),
                have = c.lossyLong("have"),
            )
        }
    }
}

@Suppress("unused")
private val keepListSerializerImport = ListSerializer(Long.serializer())
