// 원본: Swift `enum X: String, Decodable` + `init(from:) { X(rawValue: raw) ?? .unknown }` 관례(GomokuRPCStatus · ChessRPCStatus · TetrisRPCStatus) @ 1b8260d
package com.yehsung.aingcheck.core.wire.json

import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/** 원시값이 있는 Swift 열거(Kotlin enum 상수 이름 = Swift case 이름, [rawValue] = 전선 글자). */
interface SwiftRawValued {
    val rawValue: String
}

/**
 * 모르는 원시값을 [unknown] 갈래로 접는 열거 직렬화기(C§4 #19 — status 만 필수, 모르는 status 는 `.unknown`).
 * 글자가 아니면(숫자·null) Swift 처럼 던진다 — `singleValueContainer().decode(String.self)` 가 실패하는 자리다.
 */
open class SwiftRawEnumSerializer<E>(
    name: String,
    private val entries: List<E>,
    private val unknown: E?,
) : KSerializer<E> where E : Enum<E>, E : SwiftRawValued {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor(name, PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): E {
        val raw = SwiftDecoding.single(decoder).decodeString()
        return entries.firstOrNull { it.rawValue == raw } ?: unknown
            ?: throw SwiftDecodingException(SwiftDecodingErrorKind.dataCorrupted, SwiftDecoding.single(decoder).path, "모르는 열거값 '$raw'")
    }

    override fun serialize(encoder: Encoder, value: E) = encoder.encodeString(value.rawValue)
}
