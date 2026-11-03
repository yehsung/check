// 원본: Sources/CheckCore/CharacterGift.swift(전선 모양 · CharacterGiftKind · choosable · lossy 보조 — 배정표 W1-d 몫) @ 12624739
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
import kotlinx.serialization.json.JsonNull

/** character_gift_pending 본문(`p_protocol` = 상점 능력 번호 — 4 미만이면 스토어가 부르지 않는다). */
@Serializable
data class CharacterGiftPendingRequest(@SerialName("p_protocol") val pProtocol: Long)

/**
 * Swift `CharacterGiftKind` — 선물 종류(맥 0.3.74). 서버 `character_gifts.kind` · `character_prices.gift_kind` 의 원문 값과 같다([wireValue]).
 * ★ 종류마다 **선택지 집합이 따로**다 — 생일 선물엔 케이크만, 술 선물엔 이슬만 선다([builtInIDs]). 그리고 종류마다 받을 수 있는 능력 번호가
 *   다르다([minProtocol] — 생일 4 · 술 5). 문구 묶음(`copy`)은 rules(`CharacterGiftKinds`)에 있다(글자는 rules 한 곳).
 * 상수 이름 = Swift case 이름(골든 덤프가 이름으로 잰다).
 */
enum class CharacterGiftKind(val wireValue: String) {
    /** 생일 선물(0.3.66) — 케이크 아잉이 둘 중 하나를 받는 사람이 고른다. */
    birthday("birthday"),

    /** '술 한잔' 선물(0.3.74) — 이슬 아잉이 하나, 고를 것 없이 받는다. */
    drink("drink"),
    ;

    /** 이 종류의 선물로 받는 내장 캐릭터 — **표시 순서 그대로**(생일 = 딸기 → 초코 · 술 = 이슬). 선물 선택지는 이 목록으로 거른다. */
    val builtInIDs: List<String>
        get() = when (this) {
            birthday -> BuiltInCharacterIds.birthdayGiftBuiltInIDs
            drink -> BuiltInCharacterIds.drinkGiftBuiltInIDs
        }

    /**
     * 이 종류를 받을 수 있는 최소 능력 번호(서버 `claim_character_gift` 의 문턱 — 생일 4 · 술 5). 값은 rules `ShopWire.cakeProtocol` ·
     * `ShopWire.isulProtocol` 과 같다(와이어는 rules 를 못 본다 — rules 시험 `CharacterShopGoldenTest.giftKindsMatchSwift` 가 둘을 맞댄다).
     */
    val minProtocol: Int
        get() = when (this) {
            birthday -> 4
            drink -> 5
        }

    /** 이 번호의 빌드가 이 종류의 선물을 받을 수 있는가(번호는 누적). */
    fun isSupported(protocolVersion: Int): Boolean = protocolVersion >= minProtocol

    companion object {
        /** 서버 원문 → 종류. 정확히 그 두 값만(공백 · 대소문자를 봐주지 않는다 — 서버 CHECK 가 두 값만 허락한다). 그 밖은 null. */
        fun fromWire(wireValue: String?): CharacterGiftKind? = entries.firstOrNull { it.wireValue == wireValue }

        /** 내장 캐릭터 → 그 캐릭터를 주는 선물 종류(케이크 → 생일 · 이슬 → 술). 선물 전용 내장이 아니면 null. */
        fun ofBuiltIn(id: String?): CharacterGiftKind? = if (id == null) null else entries.firstOrNull { id in it.builtInIDs }
    }
}

/**
 * Swift `CharacterGiftOffer` — 받을 선물 하나.
 * INV-CharacterGift-1eb6cb1a 이식: `id` 가 없거나 비었으면, `kind` 가 이 빌드가 모르는 값이면, 또는 **그 종류로** 거른 뒤 선택지가 하나도
 * 없으면 **던진다** — 감싼 응답(`CharacterGiftPendingResponse.gift`)은 그 실패를 lossy 로 접어 "선물 없음"이 된다(빈 시트를 띄우지 않는다).
 * `kind` 키가 없거나 null 이면 옛 서버(생일 선물만 있던 시절 · 서버 p < 5 응답) — **생일**로 읽는다.
 * `options` 는 서버 순서에 기대지 않고 **그 종류의 내장 순서**(생일 = 딸기 → 초코 · 술 = 이슬)로 거른다([choosable]).
 */
@Serializable(with = CharacterGiftOffer.Serializer::class)
data class CharacterGiftOffer private constructor(
    val id: String,
    val options: List<String>,
    val note: String?,
    val createdAt: String?,
    /** 선물 종류(생일 · 술 한잔). 서버가 안 실었으면 생일. */
    val kind: CharacterGiftKind,
) {
    companion object {
        /** Swift memberwise init — options 도 그 종류로 [choosable] 을 거친다. 보유로 거른 새 선물을 만들 때는 **kind 를 실어 옮긴다**. */
        operator fun invoke(
            id: String,
            options: List<String>,
            note: String? = null,
            createdAt: String? = null,
            kind: CharacterGiftKind = CharacterGiftKind.birthday,
        ): CharacterGiftOffer = CharacterGiftOffer(id, choosable(options, kind), note, createdAt, kind)

        /** 고를 수 있는 것만, **그 종류의 내장 순서**로(서버 순서·중복에 기대지 않는다). 생일 선물에 이슬이 섞여 와도 버린다. */
        fun choosable(raw: List<String>, kind: CharacterGiftKind = CharacterGiftKind.birthday): List<String> {
            val given = raw.toSet()
            return kind.builtInIDs.filter { it in given }
        }
    }

    object Serializer : SwiftDecodableSerializer<CharacterGiftOffer>("CharacterGiftOffer") {
        override fun deserialize(decoder: Decoder): CharacterGiftOffer {
            val c = SwiftDecoding.keyed(decoder)
            val rawID = c.lossyString("id")?.let(::swiftTrim)
            if (rawID.isNullOrEmpty()) throw SwiftDecodingException(SwiftDecodingErrorKind.dataCorrupted, "${c.path}.id", "gift id 가 없다")
            // kind: 키가 없거나 null → 생일(옛 서버). 있는데 모르는 값 · 모양이 틀림(숫자 등) → 이 빌드가 열 수 없는 선물(던진다 → 선물 없음).
            val rawKind = c.raw("kind")
            val kind = if (rawKind == null || rawKind is JsonNull) {
                CharacterGiftKind.birthday
            } else {
                CharacterGiftKind.fromWire(c.lossyString("kind"))
                    ?: throw SwiftDecodingException(SwiftDecodingErrorKind.dataCorrupted, "${c.path}.kind", "모르는 선물 종류다")
            }
            val options = choosable(giftLossyStrings(c, "options") ?: emptyList(), kind)
            if (options.isEmpty()) {
                throw SwiftDecodingException(SwiftDecodingErrorKind.dataCorrupted, "${c.path}.options", "고를 수 있는 선택지가 없다")
            }
            val note = c.lossyString("note")?.let(::swiftTrim)
            return CharacterGiftOffer(
                id = rawID,
                options = options,
                note = if (note.isNullOrEmpty()) null else note,
                createdAt = c.lossyString("created_at"),
                kind = kind,
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
