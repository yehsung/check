// 원본: Swift `KeyedDecodingContainer`·`try?`(lossy) 관례 — Sources/CheckCore/TetrisWire.swift:7-10 · Gacha.swift:31-35 · SupabaseWorkModels.swift(직접 짠 init(from:) 들) @ 1b8260d
package com.yehsung.aingcheck.core.wire.json

import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlin.coroutines.cancellation.CancellationException

/**
 * Swift `init(from decoder:)` 를 Kotlin 으로 옮길 때 쓰는 컨테이너. 이름·뜻이 Swift 그대로다:
 *  · [decode] = `try c.decode(T.self, forKey:)` — 없으면 keyNotFound, null 이면 valueNotFound, 타입이 다르면 typeMismatch.
 *  · [decodeIfPresent] = `try c.decodeIfPresent` — 없음·null 은 null, 타입이 다르면 **던진다**.
 *  · [lossy] = `try? c.decodeIfPresent` — 무엇이든 실패면 null(lossy 칸).
 * 키는 전선 snake 이름으로 준다(내부에서 Swift 처럼 camel 로 접어 견준다).
 */
class SwiftKeyed internal constructor(val obj: JsonObject, val path: String, private val plainKeys: Boolean = false) {
    /** [plainKeys] = Swift 기본 `JSONDecoder()`(키 변환 없음 — `TodoSyncResponse.decode`). 아니면 convertFromSnakeCase. */
    private val values: Map<String, JsonElement> = if (plainKeys) obj else convertedKeys(obj)

    private fun keyOf(key: String) = if (plainKeys) key else SwiftKeys.fromSnakeCase(key)

    fun contains(key: String): Boolean = keyOf(key) in values

    /** 칸 값(없으면 null — JSON null 은 JsonNull). */
    fun raw(key: String): JsonElement? = values[keyOf(key)]

    fun decoder(key: String): SwiftValueDecoder {
        val k = keyOf(key)
        val v = values[k] ?: throw SwiftDecodingException(SwiftDecodingErrorKind.keyNotFound, "$path.$k", "칸이 없다")
        return SwiftValueDecoder(v, "$path.$k")
    }

    fun <T> decode(key: String, deserializer: DeserializationStrategy<T>): T = deserializer.deserialize(decoder(key))

    fun <T : Any> decodeIfPresent(key: String, deserializer: DeserializationStrategy<T>): T? {
        val k = keyOf(key)
        val v = values[k] ?: return null
        if (v is JsonNull) return null
        return deserializer.deserialize(SwiftValueDecoder(v, "$path.$k"))
    }

    fun <T : Any> lossy(key: String, deserializer: DeserializationStrategy<T>): T? = swiftTry { decodeIfPresent(key, deserializer) }

    // ---- 자주 쓰는 원시 칸 ----
    fun string(key: String): String = decode(key, String.serializer())
    fun long(key: String): Long = decode(key, Long.serializer())
    fun int(key: String): Int = decode(key, Int.serializer())
    fun bool(key: String): Boolean = decode(key, Boolean.serializer())
    fun double(key: String): Double = decode(key, Double.serializer())
    fun stringIfPresent(key: String): String? = decodeIfPresent(key, String.serializer())
    fun longIfPresent(key: String): Long? = decodeIfPresent(key, Long.serializer())
    fun intIfPresent(key: String): Int? = decodeIfPresent(key, Int.serializer())
    fun boolIfPresent(key: String): Boolean? = decodeIfPresent(key, Boolean.serializer())
    fun doubleIfPresent(key: String): Double? = decodeIfPresent(key, Double.serializer())
    fun lossyString(key: String): String? = lossy(key, String.serializer())
    fun lossyLong(key: String): Long? = lossy(key, Long.serializer())
    fun lossyInt(key: String): Int? = lossy(key, Int.serializer())
    fun lossyBool(key: String): Boolean? = lossy(key, Boolean.serializer())
    fun lossyDouble(key: String): Double? = lossy(key, Double.serializer())

    /** `try c.nestedContainer(keyedBy:forKey:)`. */
    fun nested(key: String): SwiftKeyed = if (plainKeys) SwiftDecoding.keyedPlain(decoder(key)) else SwiftDecoding.keyed(decoder(key))

    /** 같은 디코더에서 다른 타입을 통째로 읽기(`try T(from: decoder)` — 평평한 응답). */
    fun <T> decodeSelf(deserializer: DeserializationStrategy<T>): T = deserializer.deserialize(SwiftValueDecoder(obj, path))
}

/** Swift `try?` — 실패면 null. 취소는 삼키지 않는다(C§2.4). */
inline fun <T> swiftTry(block: () -> T): T? = try {
    block()
} catch (e: CancellationException) {
    throw e
} catch (e: SerializationException) {
    null
} catch (e: IllegalArgumentException) {
    null
} catch (e: IllegalStateException) {
    null
}

object SwiftDecoding {
    private fun swift(decoder: Decoder): SwiftValueDecoder = decoder as? SwiftValueDecoder
        ?: throw IllegalStateException("와이어 타입은 SwiftJson 으로만 읽는다(받은 디코더 ${decoder::class.simpleName})")

    /** `try decoder.container(keyedBy:)` — 객체가 아니면 typeMismatch. */
    fun keyed(decoder: Decoder): SwiftKeyed {
        val d = swift(decoder)
        return SwiftKeyed(d.obj(), d.path)
    }

    /**
     * 키 변환 **없는** `try decoder.container(keyedBy:)` — Swift 가 기본 `JSONDecoder()` 로 읽는 타입(todo_sync 응답 셋)만 쓴다.
     * 그 타입의 CodingKeys 는 snake 원문(`watermark_ms`)이라 camel 키(`watermarkMs`)는 **못 읽는다** — convertFromSnakeCase 로 읽으면
     * camel 키도 맞아 Swift 와 갈린다(검증 지적의 알려진 갈림 — 골든 wire/rules todo-response-* 가 잠근다).
     */
    fun keyedPlain(decoder: Decoder): SwiftKeyed {
        val d = swift(decoder)
        return SwiftKeyed(d.obj(), d.path, plainKeys = true)
    }

    /** `try decoder.unkeyedContainer()` — 원소 디코더 목록. */
    fun unkeyed(decoder: Decoder): List<SwiftValueDecoder> {
        val d = swift(decoder)
        return d.array().mapIndexed { i, e -> SwiftValueDecoder(e, "${d.path}[$i]") }
    }

    /** `try decoder.singleValueContainer()`. */
    fun single(decoder: Decoder): SwiftValueDecoder = swift(decoder)
}

/**
 * 읽기 전용 와이어 타입의 직접 짠 직렬화기 바탕(Swift `Decodable` 만 채택한 타입). 쓰기는 하지 않는다.
 */
abstract class SwiftDecodableSerializer<T>(name: String) : KSerializer<T> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor(name)
    override fun serialize(encoder: Encoder, value: T) {
        throw UnsupportedOperationException("$descriptor 는 읽기 전용 와이어 타입이다(Swift Decodable)")
    }
}

/** `[T]` 를 깨진 원소만 버리며 읽는다(Swift 의 `LossyArray`·`compactMap { try? }` 관례). 배열이 아니면 던진다. */
fun <T : Any> SwiftValueDecoder.lossyList(element: DeserializationStrategy<T>): List<T> =
    array().mapIndexedNotNull { i, e -> swiftTry { element.deserialize(SwiftValueDecoder(e, "$path[$i]")) } }
