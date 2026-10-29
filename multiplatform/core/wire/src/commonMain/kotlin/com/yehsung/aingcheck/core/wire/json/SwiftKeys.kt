// 원본: Sources/CheckCore/SupabaseWorkService.swift:86-89(keyEncodingStrategy .convertToSnakeCase · keyDecodingStrategy .convertFromSnakeCase) @ 1b8260d
// 키 변환 규칙의 정답 표: multiplatform/testkit/src/desktopTest/resources/golden/w0b-probe/decoder.json(keys-decoded · keys-encoded, C-X3 실측)
package com.yehsung.aingcheck.core.wire.json

import com.yehsung.aingcheck.core.wire.text.WireScalars

/**
 * Swift `JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase` · `JSONEncoder.KeyEncodingStrategy.convertToSnakeCase` 의 Kotlin 꼴.
 *
 * 와이어 타입의 이름은 `@SerialName` 으로 **전선 키(snake)를 명시**한다(C§2.3 — 이름 짓기 전략 금지). 그런데 Swift 디코더는
 * 전선 키를 camel 로 바꾼 뒤 프로퍼티(CodingKey) 이름과 견준다 — `user_id` 와 `userId` 가 **같은 칸**이다. 그래서 디코더는
 * 들어온 키와 우리 SerialName 을 **둘 다** [fromSnakeCase] 로 접어 견준다(Swift 와 같은 칸을 고른다).
 *
 * `capitalized` 는 ICU 단어 제목 대문자다 — 첫 **대소문자 있는** 글자만 올린다(`url_2x` → `url2X`, 실측).
 *
 * 글자 판정(대문자·소문자·글자)은 `Char.isUpperCase` 같은 `Character.getType` 판정이 아니라 Swift 가 낸 번들 표([WireScalars])로 한다
 * (G §8-20 #3 · §8-16 ② — 8차 fold). 판정 단위는 스칼라 하나라 대리쌍을 반으로 가르지 않는다.
 */
object SwiftKeys {
    fun fromSnakeCase(key: String): String {
        if (key.isEmpty()) return key
        val first = key.indexOfFirst { it != '_' }
        if (first < 0) return key // 전부 밑줄
        var last = key.length - 1
        while (last > first && key[last] == '_') last--
        val leading = key.substring(0, first)
        val trailing = key.substring(last + 1)
        val core = key.substring(first, last + 1)
        val parts = core.split('_').filter { it.isNotEmpty() }
        val joined = if (parts.size == 1) {
            core // 밑줄 없는 키는 그대로(이미 camel 일 수 있다)
        } else {
            parts[0].lowercase() + parts.drop(1).joinToString("") { capitalized(it) }
        }
        return leading + joined + trailing
    }

    /** Foundation `capitalized`(ICU 제목 대문자): 단어의 첫 '대소문자 있는' 글자를 올리고 나머지는 내린다. */
    private fun capitalized(word: String): String {
        val lower = word.lowercase()
        val index = lower.indices.firstOrNull { i ->
            val cp = WireScalars.scalarAt(lower, i)
            WireScalars.isLetter(cp) && (WireScalars.isLowercase(cp) || WireScalars.isUppercase(cp))
        } ?: return lower
        val width = WireScalars.scalarWidth(lower, index)
        val head = if (width == 1) lower[index].titlecase() else lower.substring(index, index + width).uppercase()
        return lower.substring(0, index) + head + lower.substring(index + width)
    }

    /** `convertToSnakeCase`: 대문자 경계를 단어로 자른다. 대문자 덩어리(`URL`)는 소문자 앞 글자까지 한 단어. */
    fun toSnakeCase(key: String): String {
        if (key.isEmpty()) return key
        val words = mutableListOf<IntRange>()
        var wordStart = 0
        var searchStart = WireScalars.scalarWidth(key, 0)
        val end = key.length
        while (true) {
            val upper = (searchStart until end).firstOrNull { WireScalars.isUppercase(WireScalars.scalarAt(key, it)) } ?: break
            words += wordStart until upper
            val lowerIdx = (upper until end).firstOrNull { WireScalars.isLowercase(WireScalars.scalarAt(key, it)) }
            if (lowerIdx == null) {
                wordStart = upper
                searchStart = end
                break
            }
            if (lowerIdx == upper + WireScalars.scalarWidth(key, upper)) {
                wordStart = upper
            } else {
                val beforeLower = lowerIdx - (if (WireScalars.scalarAt(key, lowerIdx - 1) < 0) 2 else 1)
                words += upper until beforeLower
                wordStart = beforeLower
            }
            searchStart = lowerIdx + WireScalars.scalarWidth(key, lowerIdx)
            if (searchStart > end) break
        }
        words += wordStart until end
        return words.joinToString("_") { r -> key.substring(r.first, r.last + 1).lowercase() }
    }
}
