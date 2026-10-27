// 원본: Sources/CheckCore/CharacterGift.swift:1-163·218-268·327-353(전선 모양 · choosable · lossy 보조 — 배정표 W1-d 몫) @ 1b8260d
package com.yehsung.aingcheck.core.wire.gift

import com.yehsung.aingcheck.core.wire.character.BuiltInCharacterIds
import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.json.SwiftDecodingErrorKind
import com.yehsung.aingcheck.core.wire.json.SwiftDecodingException
import com.yehsung.aingcheck.core.wire.json.SwiftKeyed
import com.yehsung.aingcheck.core.wire.json.SwiftValueDecoder
import com.yehsung.aingcheck.core.wire.json.swiftTry
import com.yehsung.aingcheck.core.wire.models.swiftTrim
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encoding.Decoder

/** character_gift_pending 본문(`p_protocol` = 상점 능력 번호 — 4 미만이면 스토어가 부르지 않는다). */
@Serializable
data class CharacterGiftPendingRequest(@SerialName("p_protocol") val pProtocol: Long)

/**
 * Swift `CharacterGiftOffer` — 받을 선물 하나.
 * INV-CharacterGift-1eb6cb1a 이식: `id` 가 없거나 비었으면, 또는 거른 뒤 선택지가 하나도 없으면 **던진다** — 감싼 응답
 * (`CharacterGiftPendingResponse.gift`)은 그 실패를 lossy 로 접어 "선물 없음"이 된다(빈 시트를 띄우지 않는다).
 * `options` 는 서버 순서에 기대지 않고 **내장 순서(딸기 → 초코)** 로 거른다([choosable]).
 */
@Serializable(with = CharacterGiftOffer.Serializer::class)
data class CharacterGiftOffer private constructor(
    val id: String,
    val options: List<String>,
    val note: String?,
    val createdAt: String?,
) {
    companion object {
        /** Swift memberwise init — options 도 [choosable] 을 거친다. */
        operator fun invoke(id: String, options: List<String>, note: String? = null, createdAt: String? = null): CharacterGiftOffer =
            CharacterGiftOffer(id, choosable(options), note, createdAt)

        /** 고를 수 있는 것만, **내장 순서**로(서버 순서·중복에 기대지 않는다). */
        fun choosable(raw: List<String>): List<String> {
            val given = raw.toSet()
            return BuiltInCharacterIds.giftOnlyBuiltInIDs.filter { it in given }
        }
    }

    object Serializer : SwiftDecodableSerializer<CharacterGiftOffer>("CharacterGiftOffer") {
        override fun deserialize(decoder: Decoder): CharacterGiftOffer {
            val c = SwiftDecoding.keyed(decoder)
            val rawID = c.lossyString("id")?.let(::swiftTrim)
            if (rawID.isNullOrEmpty()) throw SwiftDecodingException(SwiftDecodingErrorKind.dataCorrupted, "${c.path}.id", "gift id 가 없다")
            val options = choosable(giftLossyStrings(c, "options") ?: emptyList())
            if (options.isEmpty()) {
                throw SwiftDecodingException(SwiftDecodingErrorKind.dataCorrupted, "${c.path}.options", "고를 수 있는 선택지가 없다")
            }
            val note = c.lossyString("note")?.let(::swiftTrim)
            return CharacterGiftOffer(
                id = rawID,
                options = options,
                note = if (note.isNullOrEmpty()) null else note,
                createdAt = c.lossyString("created_at"),
            )
        }
    }
}

/** 글자가 아닌 원소는 그 원소만 버린다(배열이 아니면 null). */
internal fun giftLossyStrings(c: SwiftKeyed, key: String): List<String>? {
    if (!c.contains(key)) return null
    val list = swiftTry { c.decoder(key).array() } ?: return null
    return list.mapIndexedNotNull { i, e -> swiftTry { SwiftValueDecoder(e, "${c.path}.$key[$i]").decodeString() } }
}

/** Swift `CharacterGiftPendingResponse` — status 만 필수, gift 는 lossy(깨지면 "선물 없음"). */
@Serializable(with = CharacterGiftPendingResponse.Serializer::class)
data class CharacterGiftPendingResponse(val status: String, val gift: CharacterGiftOffer? = null) {
    /** status 가 ok 일 때만 선물. */
    val offer: CharacterGiftOffer? get() = if (status == CharacterGiftStatus.ok) gift else null

    object Serializer : SwiftDecodableSerializer<CharacterGiftPendingResponse>("CharacterGiftPendingResponse") {
        override fun deserialize(decoder: Decoder): CharacterGiftPendingResponse {
            val c = SwiftDecoding.keyed(decoder)
            return CharacterGiftPendingResponse(
                status = c.string("status"),
                gift = c.lossy("gift", CharacterGiftOffer.serializer()),
            )
        }
    }
}

@Serializable
data class CharacterGiftClaimRequest(
    @SerialName("p_gift") val pGift: String,
    @SerialName("p_character") val pCharacter: String,
    @SerialName("p_protocol") val pProtocol: Long,
)

/** Swift `CharacterGiftClaimResponse` — status 만 필수, 나머지 lossy. */
@Serializable(with = CharacterGiftClaimResponse.Serializer::class)
data class CharacterGiftClaimResponse(
    val status: String,
    val characterId: String? = null,
    val replayed: Boolean? = null,
    val minProtocol: Long? = null,
) {
    object Serializer : SwiftDecodableSerializer<CharacterGiftClaimResponse>("CharacterGiftClaimResponse") {
        override fun deserialize(decoder: Decoder): CharacterGiftClaimResponse {
            val c = SwiftDecoding.keyed(decoder)
            return CharacterGiftClaimResponse(
                status = c.string("status"),
                characterId = c.lossyString("character_id"),
                replayed = c.lossyBool("replayed"),
                minProtocol = c.lossyLong("min_protocol"),
            )
        }
    }
}

/** Swift `CharacterGiftStatus`(서버 어휘). */
object CharacterGiftStatus {
    const val ok = "ok"
    const val unauthorized = "unauthorized"
    const val needsUpdate = "needs_update"
    const val notFound = "not_found"
    const val invalidChoice = "invalid_choice"
    const val alreadyClaimed = "already_claimed"
}
