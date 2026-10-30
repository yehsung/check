// 원본: Sources/CheckCore/StatusMessage.swift(precomposedStringWithCanonicalMapping) · CheckTodoModel.swift(String.count 그래핌) @ 1b8260d
package com.yehsung.aingcheck.core.rules.text

/**
 * 플랫폼이 답하는 글자 연산 두 가지(G §8-16 ①·③). 나머지(범주·공백·보이는 글자)는 번들 표([UnicodeScalarTable])가 답한다.
 *
 * ① NFC 는 **유니코드 표준**을 따른다 — `java.text.Normalizer`(데스크톱 JDK · Android ICU 모두 표준). 서버(Postgres normalize)와 같은 쪽이다.
 *    Foundation `precomposedStringWithCanonicalMapping` 은 6줄(완성형 LV + 종성 자모 · 옛 종성 · 결합 등급 재배열 · 태그 + 결합)에서
 *    표준과 어긋난다 — 그 목록은 골든 `text/nfc` 의 knownDivergence 가 정확히 잠근다(늘거나 줄면 빨강).
 * ③ 그래핌은 **플랫폼 BreakIterator**(ART = ICU, 데스크톱 = JDK). JDK 21 은 유니코드 15.1 InCB 규칙 전이라 2줄이 갈린다 —
 *    골든 `text/graphemes` 의 knownDivergence 가 잠근다.
 */
internal expect fun platformNfc(text: String): String

/** NFD(정준 분해) — 이름 정렬의 마지막 판정만 쓴다(Foundation forcedOrdering 은 분해한 꼴을 먼저 견준다 — C-X5). */
internal expect fun platformNfd(text: String): String

/** 확장 그래핌 경계 — 그래핌마다 **UTF-16 길이**(앞에서부터). 빈 글이면 빈 배열. */
internal expect fun platformGraphemeLengths(text: String): IntArray

/** 공개 진입점: NFC(Swift `precomposedStringWithCanonicalMapping` 자리). */
object TextNormalization {
    fun nfc(text: String): String = if (text.isEmpty()) text else platformNfc(text)
}

/** 공개 진입점: 그래핌(Swift `Character`) 단위 연산. */
object Graphemes {
    /** Swift `String.count`. */
    fun count(text: String): Int = platformGraphemeLengths(text).size

    /** 그래핌 하나하나(원문 조각). */
    fun clusters(text: String): List<String> {
        val lengths = platformGraphemeLengths(text)
        val out = ArrayList<String>(lengths.size)
        var start = 0
        for (length in lengths) {
            out += text.substring(start, start + length)
            start += length
        }
        return out
    }

    /** 그래핌마다 유니코드 스칼라(코드포인트) 수 — 골든 `text/graphemes` 의 clusters 칸과 같은 눈금. */
    fun scalarCounts(text: String): IntArray {
        val lengths = platformGraphemeLengths(text)
        var start = 0
        return IntArray(lengths.size) { index ->
            val end = start + lengths[index]
            val scalars = text.codePointCountCompat(start, end)
            start = end
            scalars
        }
    }
}

/**
 * `String.codePointCount` 의 공용 판(commonMain 에서 JDK API 를 부르지 않는다). 짝 없는 서로게이트는 한 개로 센다.
 * 공개(Windows 공용 패치 14): 데스크톱 AI 리밋 계약(`AILimitMainDeviceIDContract`)이 스칼라 세기 사본을 두지 않게 — 몸·기본값 그대로.
 */
fun String.codePointCountCompat(start: Int = 0, end: Int = length): Int {
    var count = 0
    var index = start
    while (index < end) {
        val c = this[index]
        index += if (c.isHighSurrogate() && index + 1 < end && this[index + 1].isLowSurrogate()) 2 else 1
        count++
    }
    return count
}

/** 코드포인트 배열(Swift `unicodeScalars`). 짝 없는 서로게이트는 그 값 그대로 하나로 든다(Swift 글자에는 없다). */
internal fun String.codePointArray(): IntArray {
    val out = IntArray(codePointCountCompat())
    var index = 0
    var slot = 0
    while (index < length) {
        val c = this[index]
        if (c.isHighSurrogate() && index + 1 < length && this[index + 1].isLowSurrogate()) {
            out[slot++] = 0x10000 + ((c.code - 0xD800) shl 10) + (this[index + 1].code - 0xDC00)
            index += 2
        } else {
            out[slot++] = c.code
            index += 1
        }
    }
    return out
}

/** 코드포인트 하나 → 글자(서로게이트 짝 포함). */
internal fun StringBuilder.appendCodePointCompat(cp: Int): StringBuilder {
    if (cp >= 0x10000) {
        val v = cp - 0x10000
        append(((v shr 10) + 0xD800).toChar())
        append(((v and 0x3FF) + 0xDC00).toChar())
    } else {
        append(cp.toChar())
    }
    return this
}

/** 코드포인트 배열 → 글자. */
internal fun stringFromCodePoints(cps: IntArray, from: Int = 0, to: Int = cps.size): String {
    val sb = StringBuilder(to - from)
    for (i in from until to) sb.appendCodePointCompat(cps[i])
    return sb.toString()
}
