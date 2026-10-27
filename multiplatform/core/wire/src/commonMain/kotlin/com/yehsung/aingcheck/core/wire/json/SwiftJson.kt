// 원본: Sources/CheckCore/SupabaseWorkService.swift:86-89(JSONEncoder/JSONDecoder 설정) @ 1b8260d · C§2.6 · C-X3(decoder.json 실측)
package com.yehsung.aingcheck.core.wire.json

import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.SerializationException
import kotlinx.serialization.SerializationStrategy
import kotlinx.serialization.descriptors.PolymorphicKind
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.SerialKind
import kotlinx.serialization.descriptors.StructureKind
import kotlinx.serialization.encoding.CompositeDecoder
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.modules.EmptySerializersModule
import kotlinx.serialization.modules.SerializersModule

/** Swift `DecodingError` 의 갈래(G6 은 성패만 견주지만 실패 문구에 남긴다). */
enum class SwiftDecodingErrorKind { typeMismatch, valueNotFound, keyNotFound, dataCorrupted }

/** Swift `DecodingError` 대응. lossy 자리(`try?`)는 이것과 kotlinx 의 SerializationException 을 nil 로 접는다. */
class SwiftDecodingException(val kind: SwiftDecodingErrorKind, val path: String, message: String) :
    SerializationException("$kind at $path: $message")

/**
 * 와이어 JSON 한 벌 — Swift `JSONDecoder(keyDecodingStrategy: .convertFromSnakeCase)` 와 **같은 판정**으로 읽고,
 * `JSONEncoder(keyEncodingStrategy: .convertToSnakeCase)` 와 같은 키로 쓴다(키는 `@SerialName` 으로 명시).
 *
 * kotlinx 의 기본 Json 디코더를 쓰지 않는 이유(C-X3 실측 decoder.json 과 다르다):
 *  · 정수 칸에 `3.0`·`1e2` → Swift 는 3·100 으로 읽고, kotlinx 는 실패한다.
 *  · 정수·실수 칸에 `"3"`(글자) → Swift 는 typeMismatch, kotlinx 는 받아들인다.
 *  · 키: Swift 는 전선 키를 camel 로 접어 견준다(`user_id` = `userId`) — [SwiftKeys.fromSnakeCase].
 *  · 사전(`[String: T]`)의 키는 접지 않는다(C§4 #37).
 * 그래서 JSON 을 트리로 읽고 그 위를 도는 디코더([SwiftValueDecoder])가 Swift 규칙대로 값을 낸다. 생성된 kotlinx 직렬화기는
 * 그대로 쓴다 — 빠진 필수 칸은 MissingFieldException(= keyNotFound), 널 → valueNotFound, 타입이 다르면 typeMismatch.
 * Optional 칸은 Kotlin 에서 `= null` 기본값을 둔다(합성 `decodeIfPresent` — 없음·null 은 nil, 타입이 다르면 **던진다**).
 */
object SwiftJson {
    /** 쓰기: 합성 Encodable 처럼 기본값 칸도 싣고(`encodeDefaults`), nil Optional 은 키째 뺀다(`explicitNulls = false`). */
    val encoder: Json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = true
        isLenient = false
        allowSpecialFloatingPointValues = false
    }

    /** JSON 글자 → 트리. 숫자는 글자 그대로 남는다(정밀도 손실 없음). */
    private val parser: Json = Json { isLenient = false }

    fun parse(text: String): JsonElement = try {
        parser.parseToJsonElement(text)
    } catch (e: SerializationException) {
        throw SwiftDecodingException(SwiftDecodingErrorKind.dataCorrupted, "$", "JSON 이 아니다: ${e.message}")
    } catch (e: IllegalArgumentException) {
        throw SwiftDecodingException(SwiftDecodingErrorKind.dataCorrupted, "$", "JSON 이 아니다: ${e.message}")
    }

    fun <T> decode(deserializer: DeserializationStrategy<T>, text: String): T = decode(deserializer, parse(text))

    fun <T> decode(deserializer: DeserializationStrategy<T>, element: JsonElement): T =
        deserializer.deserialize(SwiftValueDecoder(element, "$"))

    fun <T> encode(serializer: SerializationStrategy<T>, value: T): String = encoder.encodeToString(serializer, value)

    fun <T> encodeToElement(serializer: SerializationStrategy<T>, value: T): JsonElement =
        encoder.encodeToJsonElement(serializer, value)
}

/** 숫자 글자 → Swift 규칙의 값(decoder.json: 정수 글자는 범위 검사, 소수·지수 글자는 Double 을 거쳐 정확히 정수일 때만). */
object SwiftNumbers {
    private val plainInteger = Regex("""-?(0|[1-9][0-9]*)""")
    private val jsonNumber = Regex("""-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?""")

    fun isJsonNumber(literal: String): Boolean = jsonNumber.matches(literal)

    /**
     * Int(64비트) 칸. null = dataCorrupted. 맥 Foundation JSONDecoder 실측(2026-10-28, W1-d — numprobe):
     *  · 정수 글자는 그대로(범위 밖이면 실패).
     *  · 소수·지수 글자는 Double 로 읽어 **정수가 아니면 실패**(3.5 · 15e-1), Int64 범위 밖이면 실패(9223372036854775807.0 = 2^63).
     *  · 그 Double 이 2^53 미만이면 그 값(7.99999999999999999 → 8). 2^53 이상이면 **글자의 정수부를 정확히** 읽는다
     *    (9007199254740993.5 → 9007199254740993 — Double 로 접으면 …994 가 된다).
     */
    fun int64(literal: String): Long? {
        if (plainInteger.matches(literal)) return literal.toLongOrNull()
        val d = double(literal) ?: return null
        if (d != kotlin.math.floor(d)) return null
        if (d < -9.223372036854775808E18 || d >= 9.223372036854775808E18) return null
        if (kotlin.math.abs(d) < 9.007199254740992E15) return d.toLong()
        return exactTruncated(literal)
    }

    /** JSON 숫자 글자의 0 쪽 정수부(정확히, 자릿수로). Long 밖이면 null. */
    private fun exactTruncated(literal: String): Long? {
        val m = jsonNumber.matchEntire(literal) ?: return null
        val negative = literal.startsWith("-")
        val intPart = m.groupValues[1]
        val frac = m.groupValues[2].removePrefix(".")
        val exp = m.groupValues[3].let { if (it.isEmpty()) 0 else it.substring(1).toInt() }
        var digits = (intPart + frac).trimStart('0')
        val shift = exp - frac.length // 값 = digits × 10^shift
        digits = if (shift >= 0) digits + "0".repeat(shift) else digits.dropLast(minOf(-shift, digits.length))
        if (digits.isEmpty()) return 0
        if (digits.length > 19) return null
        return (if (negative) "-$digits" else digits).toLongOrNull()
    }

    /** Double 칸. 유한하지 않으면(1e400) null = dataCorrupted. */
    fun double(literal: String): Double? {
        if (!jsonNumber.matches(literal)) return null
        val d = literal.toDoubleOrNull() ?: return null
        return if (d.isFinite()) d else null
    }
}

/**
 * Swift 규칙으로 값 하나를 읽는 디코더. 직접 짠 직렬화기(Swift `init(from:)` 의 Kotlin 꼴)는 이것을 받아
 * [SwiftDecoding.keyed]·[SwiftDecoding.unkeyed] 로 컨테이너를 연다.
 */
@OptIn(ExperimentalSerializationApi::class)
class SwiftValueDecoder(
    val element: JsonElement,
    val path: String,
    override val serializersModule: SerializersModule = EmptySerializersModule(),
) : Decoder {
    private fun fail(kind: SwiftDecodingErrorKind, message: String): Nothing = throw SwiftDecodingException(kind, path, message)

    private fun number(expected: String): String {
        if (element is JsonNull) fail(SwiftDecodingErrorKind.valueNotFound, "$expected 자리에 null")
        val p = element as? JsonPrimitive ?: fail(SwiftDecodingErrorKind.typeMismatch, "$expected 자리에 ${kindOf(element)}")
        if (p.isString) fail(SwiftDecodingErrorKind.typeMismatch, "$expected 자리에 글자")
        if (p.content == "true" || p.content == "false") fail(SwiftDecodingErrorKind.typeMismatch, "$expected 자리에 불")
        return p.content
    }

    override fun decodeNotNullMark(): Boolean = element !is JsonNull
    override fun decodeNull(): Nothing? = null

    override fun decodeBoolean(): Boolean {
        if (element is JsonNull) fail(SwiftDecodingErrorKind.valueNotFound, "Bool 자리에 null")
        val p = element as? JsonPrimitive ?: fail(SwiftDecodingErrorKind.typeMismatch, "Bool 자리에 ${kindOf(element)}")
        if (p.isString) fail(SwiftDecodingErrorKind.typeMismatch, "Bool 자리에 글자")
        return when (p.content) {
            "true" -> true
            "false" -> false
            else -> fail(SwiftDecodingErrorKind.typeMismatch, "Bool 자리에 숫자")
        }
    }

    override fun decodeLong(): Long = SwiftNumbers.int64(number("Int")) ?: fail(SwiftDecodingErrorKind.dataCorrupted, "Int 에 안 맞는 수")

    override fun decodeInt(): Int {
        val v = decodeLong()
        if (v < Int.MIN_VALUE || v > Int.MAX_VALUE) fail(SwiftDecodingErrorKind.dataCorrupted, "Int32 범위 밖")
        return v.toInt()
    }

    override fun decodeShort(): Short {
        val v = decodeLong()
        if (v < Short.MIN_VALUE || v > Short.MAX_VALUE) fail(SwiftDecodingErrorKind.dataCorrupted, "Int16 범위 밖")
        return v.toInt().toShort()
    }

    override fun decodeByte(): Byte {
        val v = decodeLong()
        if (v < Byte.MIN_VALUE || v > Byte.MAX_VALUE) fail(SwiftDecodingErrorKind.dataCorrupted, "Int8 범위 밖")
        return v.toInt().toByte()
    }

    override fun decodeDouble(): Double = SwiftNumbers.double(number("Double")) ?: fail(SwiftDecodingErrorKind.dataCorrupted, "Double 에 안 맞는 수")
    override fun decodeFloat(): Float = decodeDouble().toFloat()

    override fun decodeString(): String {
        if (element is JsonNull) fail(SwiftDecodingErrorKind.valueNotFound, "String 자리에 null")
        val p = element as? JsonPrimitive ?: fail(SwiftDecodingErrorKind.typeMismatch, "String 자리에 ${kindOf(element)}")
        if (!p.isString) fail(SwiftDecodingErrorKind.typeMismatch, "String 자리에 숫자·불")
        return p.content
    }

    override fun decodeChar(): Char {
        val s = decodeString()
        if (s.length != 1) fail(SwiftDecodingErrorKind.dataCorrupted, "Character 가 아니다")
        return s[0]
    }

    /** 원시값 열거(`enum X: String, Codable`): 모르는 값은 dataCorrupted(합성 디코더 그대로). */
    override fun decodeEnum(enumDescriptor: SerialDescriptor): Int {
        val raw = decodeString()
        val index = enumDescriptor.getElementIndex(raw)
        if (index == CompositeDecoder.UNKNOWN_NAME) fail(SwiftDecodingErrorKind.dataCorrupted, "모르는 열거값 '$raw'")
        return index
    }

    override fun decodeInline(descriptor: SerialDescriptor): Decoder = this

    override fun beginStructure(descriptor: SerialDescriptor): CompositeDecoder = when (descriptor.kind) {
        StructureKind.LIST -> SwiftListDecoder(array(), path, serializersModule)
        StructureKind.MAP -> SwiftMapDecoder(obj(), path, serializersModule)
        is PolymorphicKind -> fail(SwiftDecodingErrorKind.dataCorrupted, "다형 직렬화는 쓰지 않는다(직접 짠 직렬화기로)")
        else -> SwiftObjectDecoder(obj(), path, serializersModule)
    }

    fun obj(): JsonObject {
        if (element is JsonNull) fail(SwiftDecodingErrorKind.valueNotFound, "객체 자리에 null")
        return element as? JsonObject ?: fail(SwiftDecodingErrorKind.typeMismatch, "객체 자리에 ${kindOf(element)}")
    }

    fun array(): JsonArray {
        if (element is JsonNull) fail(SwiftDecodingErrorKind.valueNotFound, "배열 자리에 null")
        return element as? JsonArray ?: fail(SwiftDecodingErrorKind.typeMismatch, "배열 자리에 ${kindOf(element)}")
    }

    companion object {
        fun kindOf(e: JsonElement): String = when (e) {
            is JsonNull -> "null"
            is JsonObject -> "객체"
            is JsonArray -> "배열"
            is JsonPrimitive -> if (e.isString) "글자" else "숫자·불"
        }
    }
}

/** 생성된 직렬화기의 칸 이름(SerialName = 전선 snake 키) → Swift 가 견주는 CodingKey(camel). */
@OptIn(ExperimentalSerializationApi::class)
internal fun swiftKeyOf(descriptor: SerialDescriptor, index: Int): String {
    val override = descriptor.getElementAnnotations(index).filterIsInstance<SwiftKey>().firstOrNull()
    return override?.codingKey ?: SwiftKeys.fromSnakeCase(descriptor.getElementName(index))
}

/**
 * Swift CodingKey 가 SerialName 의 camel 꼴과 다를 때(예: 디코드 쪽 CodingKey 가 `userID` 라 convertFromSnakeCase 로는
 * **영영 못 찾는** 칸)만 붙인다 — Swift 의 그 동작을 그대로 옮기기 위한 자리다.
 */
@OptIn(ExperimentalSerializationApi::class)
@kotlinx.serialization.SerialInfo
@Target(AnnotationTarget.PROPERTY)
annotation class SwiftKey(val codingKey: String)

/** JSON 객체의 키를 Swift 처럼 camel 로 접은 사전(같은 칸으로 접히는 키가 둘이면 앞의 것). */
internal fun convertedKeys(obj: JsonObject): Map<String, JsonElement> {
    val out = LinkedHashMap<String, JsonElement>()
    for ((k, v) in obj) {
        val key = SwiftKeys.fromSnakeCase(k)
        if (key !in out) out[key] = v
    }
    return out
}

@OptIn(ExperimentalSerializationApi::class)
internal class SwiftObjectDecoder(
    obj: JsonObject,
    private val path: String,
    override val serializersModule: SerializersModule,
) : CompositeDecoder {
    private val values = convertedKeys(obj)
    private var next = 0

    override fun decodeElementIndex(descriptor: SerialDescriptor): Int {
        while (next < descriptor.elementsCount) {
            val i = next++
            if (swiftKeyOf(descriptor, i) in values) return i
        }
        return CompositeDecoder.DECODE_DONE
    }

    private fun child(descriptor: SerialDescriptor, index: Int): SwiftValueDecoder {
        val key = swiftKeyOf(descriptor, index)
        val value = values[key] ?: throw SwiftDecodingException(SwiftDecodingErrorKind.keyNotFound, "$path.$key", "칸이 없다")
        return SwiftValueDecoder(value, "$path.$key", serializersModule)
    }

    override fun endStructure(descriptor: SerialDescriptor) {}
    override fun decodeBooleanElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeBoolean()
    override fun decodeByteElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeByte()
    override fun decodeCharElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeChar()
    override fun decodeDoubleElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeDouble()
    override fun decodeFloatElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeFloat()
    override fun decodeIntElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeInt()
    override fun decodeLongElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeLong()
    override fun decodeShortElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeShort()
    override fun decodeStringElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeString()
    override fun decodeInlineElement(descriptor: SerialDescriptor, index: Int): Decoder = child(descriptor, index)

    override fun <T> decodeSerializableElement(
        descriptor: SerialDescriptor, index: Int, deserializer: DeserializationStrategy<T>, previousValue: T?,
    ): T = deserializer.deserialize(child(descriptor, index))

    override fun <T : Any> decodeNullableSerializableElement(
        descriptor: SerialDescriptor, index: Int, deserializer: DeserializationStrategy<T?>, previousValue: T?,
    ): T? {
        val c = child(descriptor, index)
        return if (c.element is JsonNull) null else deserializer.deserialize(c)
    }
}

@OptIn(ExperimentalSerializationApi::class)
internal class SwiftListDecoder(
    private val array: JsonArray,
    private val path: String,
    override val serializersModule: SerializersModule,
) : CompositeDecoder {
    private var next = 0

    override fun decodeCollectionSize(descriptor: SerialDescriptor): Int = array.size
    override fun decodeElementIndex(descriptor: SerialDescriptor): Int =
        if (next < array.size) next++ else CompositeDecoder.DECODE_DONE

    private fun child(index: Int) = SwiftValueDecoder(array[index], "$path[$index]", serializersModule)

    override fun endStructure(descriptor: SerialDescriptor) {}
    override fun decodeBooleanElement(descriptor: SerialDescriptor, index: Int) = child(index).decodeBoolean()
    override fun decodeByteElement(descriptor: SerialDescriptor, index: Int) = child(index).decodeByte()
    override fun decodeCharElement(descriptor: SerialDescriptor, index: Int) = child(index).decodeChar()
    override fun decodeDoubleElement(descriptor: SerialDescriptor, index: Int) = child(index).decodeDouble()
    override fun decodeFloatElement(descriptor: SerialDescriptor, index: Int) = child(index).decodeFloat()
    override fun decodeIntElement(descriptor: SerialDescriptor, index: Int) = child(index).decodeInt()
    override fun decodeLongElement(descriptor: SerialDescriptor, index: Int) = child(index).decodeLong()
    override fun decodeShortElement(descriptor: SerialDescriptor, index: Int) = child(index).decodeShort()
    override fun decodeStringElement(descriptor: SerialDescriptor, index: Int) = child(index).decodeString()
    override fun decodeInlineElement(descriptor: SerialDescriptor, index: Int): Decoder = child(index)

    override fun <T> decodeSerializableElement(
        descriptor: SerialDescriptor, index: Int, deserializer: DeserializationStrategy<T>, previousValue: T?,
    ): T = deserializer.deserialize(child(index))

    override fun <T : Any> decodeNullableSerializableElement(
        descriptor: SerialDescriptor, index: Int, deserializer: DeserializationStrategy<T?>, previousValue: T?,
    ): T? {
        val c = child(index)
        return if (c.element is JsonNull) null else deserializer.deserialize(c)
    }
}

/**
 * 사전. 키는 **변환하지 않는다**(C§4 #37 · decoder.json keys-dictionary). 키 칸이 정수(`[Int: T]`)면 Swift 처럼 글자 키를
 * 정수로 읽는다(못 읽으면 dataCorrupted).
 */
@OptIn(ExperimentalSerializationApi::class)
internal class SwiftMapDecoder(
    obj: JsonObject,
    private val path: String,
    override val serializersModule: SerializersModule,
) : CompositeDecoder {
    private val entries = obj.entries.toList()
    private var next = 0

    override fun decodeCollectionSize(descriptor: SerialDescriptor): Int = entries.size
    override fun decodeElementIndex(descriptor: SerialDescriptor): Int =
        if (next < entries.size * 2) next++ else CompositeDecoder.DECODE_DONE

    private fun child(descriptor: SerialDescriptor, index: Int): SwiftValueDecoder {
        val (key, value) = entries[index / 2]
        return if (index % 2 == 0) {
            val keyKind: SerialKind = descriptor.getElementDescriptor(0).kind
            val keyElement = if (keyKind is PrimitiveKind && keyKind != PrimitiveKind.STRING && keyKind != PrimitiveKind.CHAR) {
                if (SwiftNumbers.isJsonNumber(key)) JsonPrimitive(key.toLongOrNull() ?: throw SwiftDecodingException(
                    SwiftDecodingErrorKind.dataCorrupted, "$path{$key}", "정수 키가 아니다")) else throw SwiftDecodingException(
                    SwiftDecodingErrorKind.dataCorrupted, "$path{$key}", "정수 키가 아니다")
            } else JsonPrimitive(key)
            SwiftValueDecoder(keyElement, "$path{key}", serializersModule)
        } else {
            SwiftValueDecoder(value, "$path.$key", serializersModule)
        }
    }

    override fun endStructure(descriptor: SerialDescriptor) {}
    override fun decodeBooleanElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeBoolean()
    override fun decodeByteElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeByte()
    override fun decodeCharElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeChar()
    override fun decodeDoubleElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeDouble()
    override fun decodeFloatElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeFloat()
    override fun decodeIntElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeInt()
    override fun decodeLongElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeLong()
    override fun decodeShortElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeShort()
    override fun decodeStringElement(descriptor: SerialDescriptor, index: Int) = child(descriptor, index).decodeString()
    override fun decodeInlineElement(descriptor: SerialDescriptor, index: Int): Decoder = child(descriptor, index)

    override fun <T> decodeSerializableElement(
        descriptor: SerialDescriptor, index: Int, deserializer: DeserializationStrategy<T>, previousValue: T?,
    ): T = deserializer.deserialize(child(descriptor, index))

    override fun <T : Any> decodeNullableSerializableElement(
        descriptor: SerialDescriptor, index: Int, deserializer: DeserializationStrategy<T?>, previousValue: T?,
    ): T? {
        val c = child(descriptor, index)
        return if (c.element is JsonNull) null else deserializer.deserialize(c)
    }
}
