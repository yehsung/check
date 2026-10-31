// 원본: Foundation `UUID`(JSONDecoder 의 UUID 디코드 = `UUID(uuidString:)`) — 처음 쓰는 곳은 Sources/CheckCore/RummyWire.swift
package com.yehsung.aingcheck.core.wire

import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.json.SwiftDecodingErrorKind
import com.yehsung.aingcheck.core.wire.json.SwiftDecodingException
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/**
 * Swift `UUID` 의 Kotlin 꼴. 값은 언제나 **소문자** 36자다(Swift 쪽 요청 본문이 `uuidString.lowercased()` 로 접고, 골든 덤프가 `{"$uuid": 소문자}` 다).
 * 다른 와이어 타입(오목·체스·테트리스)은 id 를 글자로 들지만, 아잉 큐브는 Swift 가 `UUID` 로 읽어 **모양이 틀린 id 면 응답 전체가 던져진다**
 * — 그 갈림까지 같게 하려고 따로 둔다.
 */
@Serializable(with = SwiftUUID.Serializer::class)
class SwiftUUID private constructor(val lowercased: String) {
    override fun equals(other: Any?): Boolean = other is SwiftUUID && other.lowercased == lowercased
    override fun hashCode(): Int = lowercased.hashCode()
    override fun toString(): String = lowercased

    object Serializer : KSerializer<SwiftUUID> {
        override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("SwiftUUID", PrimitiveKind.STRING)

        override fun deserialize(decoder: Decoder): SwiftUUID {
            val d = SwiftDecoding.single(decoder)
            val raw = d.decodeString()
            return parse(raw) ?: throw SwiftDecodingException(SwiftDecodingErrorKind.dataCorrupted, d.path, "UUID 가 아니다: $raw")
        }

        override fun serialize(encoder: Encoder, value: SwiftUUID) = encoder.encodeString(value.lowercased)
    }

    companion object {
        private val FORM = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

        /** Swift `UUID(uuidString:)` — 하이픈 자리까지 맞는 36자만(대소문자 무관). 못 만들면 null. */
        fun parse(text: String): SwiftUUID? = if (FORM.matches(text)) SwiftUUID(text.lowercase()) else null
    }
}
