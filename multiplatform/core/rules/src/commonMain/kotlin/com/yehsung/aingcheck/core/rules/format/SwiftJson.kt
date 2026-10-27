// 원본: Sources/CheckCore/SupabaseWorkService.swift:86-89(JSONDecoder keyDecodingStrategy = .convertFromSnakeCase) ·
//       Gacha.swift·Achievements.swift·DailyMissions.swift·WeeklyWorkReward.swift 의 lossy 디코드 보조 @ 1b8260d
package com.yehsung.aingcheck.core.rules.format

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Swift `JSONDecoder` 의 칸 읽기 규칙을 Kotlin `JsonElement` 위에 옮긴 것(앱 규칙 파일들의 손수 짠 디코드가 쓴다).
 * 표는 W0-b `w0b-probe/decoder`(C-X3 실측)다 — 정수 칸은 정수 리터럴(범위 안)과 소수점·지수가 있어도 정확히 정수인 수만,
 * 글자 "3" 은 정수가 아니다, 불은 true/false 만, Double 은 수(정수 리터럴 포함)만, 1e400 은 실패.
 *
 * 세 가지 읽기:
 *  - [SwiftKeyed.decode]: Swift `decode(T.self, forKey:)` — 없음·null·모양 틀림이면 [SwiftDecodingError].
 *  - [SwiftKeyed.decodeIfPresent]: 없음·null 이면 null, 모양이 틀리면 [SwiftDecodingError](합성 Codable 의 Optional 칸).
 *  - [SwiftKeyed.lossy]: `(try? decodeIfPresent) ?? nil` — 어떤 실패든 null(이 저장소의 lossy 관용구).
 *
 * 키는 Swift 처럼 **전선 키를 convertFromSnakeCase 로 바꾼 뒤** CodingKey 이름으로 찾는다([convertFromSnakeCase]).
 * 와이어 갈래(W1-d)의 lossy 직렬화기와 같은 표를 따른다 — 이 파일은 앱 규칙 파일이 직접 디코드하는 몫만 진다.
 */
class SwiftDecodingError(val kind: String, message: String) : Exception(message)

/** 정규 Json 파서(엄격 — 표준 JSON 만). */
internal val SwiftJsonParser: Json = Json { isLenient = false }

/** Swift `JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase`(swift-foundation 구현 그대로 — 앞뒤 밑줄 보존, 가운데는 낙타). */
fun convertFromSnakeCase(key: String): String {
    if (key.isEmpty()) return key
    val first = key.indexOfFirst { it != '_' }
    if (first < 0) return key
    var last = key.length - 1
    while (last > first && key[last] == '_') last--
    val core = key.substring(first, last + 1)
    val components = core.split('_').filter { it.isNotEmpty() }
    val joined = if (components.size == 1) {
        core
    } else {
        components[0].lowercase() + components.drop(1).joinToString("") { capitalizedWord(it) }
    }
    return key.substring(0, first) + joined + key.substring(last + 1)
}

/** Foundation `capitalized`(한 낱말): 첫 글자(문자)를 대문자로, 나머지는 소문자로. */
private fun capitalizedWord(word: String): String {
    val sb = StringBuilder(word.length)
    var done = false
    for (c in word) {
        if (!done && c.isLetter()) {
            sb.append(c.uppercaseChar())
            done = true
        } else if (!done && c.isDigit()) {
            sb.append(c)
        } else {
            sb.append(c.lowercaseChar())
        }
    }
    return sb.toString()
}

/** 객체 하나를 Swift 키 규칙으로 본 것. */
class SwiftKeyed(val raw: JsonObject) {
    private val converted: Map<String, JsonElement> = LinkedHashMap<String, JsonElement>().also { map ->
        for ((key, value) in raw) map[convertFromSnakeCase(key)] = value
    }

    fun contains(key: String): Boolean = converted.containsKey(key)
    fun element(key: String): JsonElement? = converted[key]
    fun isNullOrAbsent(key: String): Boolean = converted[key].let { it == null || it is JsonNull }

    fun <T> decode(key: String, read: (JsonElement) -> T): T {
        val value = converted[key] ?: throw SwiftDecodingError("keyNotFound", "칸 '$key' 가 없다")
        if (value is JsonNull) throw SwiftDecodingError("valueNotFound", "칸 '$key' 가 null 이다")
        return read(value)
    }

    fun <T> decodeIfPresent(key: String, read: (JsonElement) -> T): T? {
        val value = converted[key] ?: return null
        if (value is JsonNull) return null
        return read(value)
    }

    fun <T> lossy(key: String, read: (JsonElement) -> T): T? = try {
        decodeIfPresent(key, read)
    } catch (e: SwiftDecodingError) {
        null
    }

    fun string(key: String): String = decode(key, SwiftValue::string)
    fun int(key: String): Long = decode(key, SwiftValue::int)
    fun lossyString(key: String): String? = lossy(key, SwiftValue::string)
    fun lossyInt(key: String): Long? = lossy(key, SwiftValue::int)
    fun lossyDouble(key: String): Double? = lossy(key, SwiftValue::double)
    fun lossyBool(key: String): Boolean? = lossy(key, SwiftValue::bool)
    fun stringIfPresent(key: String): String? = decodeIfPresent(key, SwiftValue::string)
    fun intIfPresent(key: String): Long? = decodeIfPresent(key, SwiftValue::int)
    fun boolIfPresent(key: String): Boolean? = decodeIfPresent(key, SwiftValue::bool)
    fun doubleIfPresent(key: String): Double? = decodeIfPresent(key, SwiftValue::double)
}

/** 값 하나 읽기(Swift single value container). */
object SwiftValue {
    fun string(element: JsonElement): String {
        val p = element as? JsonPrimitive ?: throw SwiftDecodingError("typeMismatch", "글자가 아니다: $element")
        if (p is JsonNull) throw SwiftDecodingError("valueNotFound", "null")
        if (!p.isString) throw SwiftDecodingError("typeMismatch", "글자가 아니다: $element")
        return p.content
    }

    fun bool(element: JsonElement): Boolean {
        val p = element as? JsonPrimitive ?: throw SwiftDecodingError("typeMismatch", "불이 아니다: $element")
        if (p is JsonNull) throw SwiftDecodingError("typeMismatch", "null")
        if (p.isString) throw SwiftDecodingError("typeMismatch", "불이 아니다: $element")
        return when (p.content) {
            "true" -> true
            "false" -> false
            else -> throw SwiftDecodingError("typeMismatch", "불이 아니다: $element")
        }
    }

    /** 수 리터럴인가(글자·불·null 이 아니다). */
    private fun numberLiteral(element: JsonElement): String {
        val p = element as? JsonPrimitive ?: throw SwiftDecodingError("typeMismatch", "수가 아니다: $element")
        if (p is JsonNull) throw SwiftDecodingError("valueNotFound", "null")
        if (p.isString || p.content == "true" || p.content == "false") throw SwiftDecodingError("typeMismatch", "수가 아니다: $element")
        return p.content
    }

    /**
     * Swift `Int`(64비트). 정수 리터럴은 범위 안이어야 하고(넘치면 실패 — Double 로 돌아가지 않는다), 소수점·지수가 있으면
     * Double 로 읽어 **정확히** 정수일 때만(3.0 · 1e2 · -0.0 → 0). 3.5 · 1e19 는 실패.
     */
    fun int(element: JsonElement): Long {
        val text = numberLiteral(element)
        val isIntegerLiteral = text.none { it == '.' || it == 'e' || it == 'E' }
        if (isIntegerLiteral) {
            return text.toLongOrNull() ?: throw SwiftDecodingError("dataCorrupted", "Int 범위 밖: $text")
        }
        val value = text.toDoubleOrNull() ?: throw SwiftDecodingError("dataCorrupted", "수가 아니다: $text")
        if (value.isNaN() || value.isInfinite()) throw SwiftDecodingError("dataCorrupted", "Int 가 아니다: $text")
        // Int(exactly:) — -2^63 ≤ v < 2^63 이고 소수부가 0.
        if (value < -9.223372036854775808E18 || value >= 9.223372036854775808E18) throw SwiftDecodingError("dataCorrupted", "Int 범위 밖: $text")
        val truncated = value.toLong()
        if (truncated.toDouble() != value) throw SwiftDecodingError("dataCorrupted", "정수가 아니다: $text")
        return truncated
    }

    /** Swift `Double`. 정수 리터럴도 받는다. 무한(1e400)은 실패. */
    fun double(element: JsonElement): Double {
        val text = numberLiteral(element)
        val value = text.toDoubleOrNull() ?: throw SwiftDecodingError("dataCorrupted", "수가 아니다: $text")
        if (value.isInfinite() || value.isNaN()) throw SwiftDecodingError("dataCorrupted", "Double 범위 밖: $text")
        return value
    }

    fun obj(element: JsonElement): JsonObject =
        element as? JsonObject ?: throw SwiftDecodingError("typeMismatch", "객체가 아니다: $element")

    fun array(element: JsonElement): JsonArray =
        element as? JsonArray ?: throw SwiftDecodingError("typeMismatch", "배열이 아니다: $element")
}

/** 글자 하나를 Swift 디코더처럼 연다(최상위가 객체가 아니면 typeMismatch). */
fun swiftKeyed(element: JsonElement): SwiftKeyed = SwiftKeyed(SwiftValue.obj(element))

/** 원문 글자 → JsonElement(표준 JSON 이 아니면 dataCorrupted). */
fun parseSwiftJson(text: String): JsonElement = try {
    SwiftJsonParser.parseToJsonElement(text)
} catch (e: Exception) {
    if (e is kotlin.coroutines.cancellation.CancellationException) throw e
    throw SwiftDecodingError("dataCorrupted", "JSON 이 아니다: ${e.message}")
}
