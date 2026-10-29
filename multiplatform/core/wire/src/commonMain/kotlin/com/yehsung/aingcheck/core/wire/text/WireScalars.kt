// 원본: 없음(W1-d 번들 해석 — 표는 contract/golden/wire/scalar-props.json, Swift 판정 원본은 그 골든의 swiftSources) @ 1b8260d
package com.yehsung.aingcheck.core.wire.text

/**
 * W1-d 글자 판정(G §8-20 #3 · §8-16 ② — 8차 fold). `Character.getType` 에 기대는 Kotlin 판정(`isLetter` · `isWhitespace` ·
 * `isUpperCase` · `isLowerCase` · 인자 없는 `trim`)을 쓰지 않고 **Swift 가 낸 범위 표**([WireScalarTable])로 가른다 —
 * JDK 21 은 유니코드 15.0, ART 는 기기 API 마다 판이 달라 같은 글자에 답이 갈린다. 표는 JVM·모든 ART 에서 같은 답을 낸다.
 *
 * 판정 단위는 유니코드 스칼라(코드포인트) 하나 — 그 스칼라 하나로 된 Swift `Character` 의 답이다. 서로게이트 반쪽·범위 밖은 0.
 * wire·net 은 rules 에 기댈 수 없어(의존 방향 rules → wire) W1-c 의 `TextScalars` 와 따로 둔다.
 */
object WireScalars {
    /** ① Swift `Character.isWhitespace`(초대 코드 정규화). */
    const val WHITESPACE: Int = 0b10000

    /** ② Foundation `CharacterSet.whitespaces`(실시간 환경 변수 trim). */
    const val SWIFT_WHITESPACES: Int = 0b01000

    /** ③ Swift `Character.isLetter`. */
    const val LETTER: Int = 0b00100

    /** ④ Swift `Character.isUppercase`. */
    const val UPPERCASE: Int = 0b00010

    /** ⑤ Swift `Character.isLowercase`. */
    const val LOWERCASE: Int = 0b00001

    private class Runs(val starts: IntArray, val ends: IntArray, val bits: ByteArray)

    private val runs: Runs by lazy { decode(WireScalarTable.RANGES) }

    private fun decode(encoded: String): Runs {
        val starts = ArrayList<Int>()
        val ends = ArrayList<Int>()
        val bits = ArrayList<Byte>()
        var next = 0
        var length = 0
        for (c in encoded) {
            val klass = WireScalarTable.ALPHABET.indexOf(c)
            if (klass < 0) {
                val digit = when (c) {
                    in '0'..'9' -> c - '0'
                    in 'a'..'z' -> c - 'a' + 10
                    else -> error("WireScalarTable 에 모르는 글자 '$c'")
                }
                length = length * 36 + digit
            } else {
                check(length > 0) { "WireScalarTable 구간 길이가 0" }
                starts += next
                ends += next + length - 1
                bits += klass.toByte()
                next += length
                length = 0
            }
        }
        check(length == 0 && next == 0x110000) { "WireScalarTable 이 U+10FFFF 까지 빈틈없이 닿지 않는다(next=$next)" }
        return Runs(starts.toIntArray(), ends.toIntArray(), bits.toByteArray())
    }

    /** 스칼라 하나의 다섯 비트([WHITESPACE] … [LOWERCASE]). 범위 밖·음수는 0. */
    fun bits(codePoint: Int): Int {
        if (codePoint < 0 || codePoint > 0x10FFFF) return 0
        val r = runs
        var lo = 0
        var hi = r.starts.size - 1
        while (lo < hi) {
            val mid = (lo + hi + 1) ushr 1
            if (r.starts[mid] <= codePoint) lo = mid else hi = mid - 1
        }
        return r.bits[lo].toInt()
    }

    fun isWhitespace(codePoint: Int): Boolean = bits(codePoint) and WHITESPACE != 0
    fun isSwiftWhitespaces(codePoint: Int): Boolean = bits(codePoint) and SWIFT_WHITESPACES != 0
    fun isLetter(codePoint: Int): Boolean = bits(codePoint) and LETTER != 0
    fun isUppercase(codePoint: Int): Boolean = bits(codePoint) and UPPERCASE != 0
    fun isLowercase(codePoint: Int): Boolean = bits(codePoint) and LOWERCASE != 0

    /**
     * [index] 자리의 스칼라. 대리쌍 앞쪽이면 합친 값, **대리쌍 뒤쪽이면 -1**(앞 스칼라의 나머지 — 판정은 0 이 된다),
     * 짝 없는 반쪽은 그 값 그대로(표에서 0).
     */
    fun scalarAt(s: CharSequence, index: Int): Int {
        val c = s[index]
        if (c.isHighSurrogate() && index + 1 < s.length && s[index + 1].isLowSurrogate()) {
            return 0x10000 + ((c.code - 0xD800) shl 10) + (s[index + 1].code - 0xDC00)
        }
        if (c.isLowSurrogate() && index > 0 && s[index - 1].isHighSurrogate()) return -1
        return c.code
    }

    /** [index] 에서 시작하는 스칼라가 차지하는 UTF-16 칸 수(1 또는 2). */
    fun scalarWidth(s: CharSequence, index: Int): Int =
        if (s[index].isHighSurrogate() && index + 1 < s.length && s[index + 1].isLowSurrogate()) 2 else 1

    /** 스칼라 단위 filter([keep] 이 참인 스칼라만 남긴다 — 대리쌍을 반으로 가르지 않는다). */
    inline fun filterScalars(s: String, keep: (Int) -> Boolean): String {
        val out = StringBuilder(s.length)
        var i = 0
        while (i < s.length) {
            val width = scalarWidth(s, i)
            if (keep(scalarAt(s, i))) out.append(s, i, i + width)
            i += width
        }
        return out.toString()
    }

    /** Foundation `trimmingCharacters(in: .whitespaces)` — 앞뒤의 [SWIFT_WHITESPACES] 스칼라를 걷는다(줄바꿈은 남는다). */
    fun trimSwiftWhitespaces(s: String): String {
        var start = 0
        while (start < s.length) {
            val width = scalarWidth(s, start)
            if (!isSwiftWhitespaces(scalarAt(s, start))) break
            start += width
        }
        var end = s.length
        while (end > start) {
            val width = if (end - 2 >= start && s[end - 1].isLowSurrogate() && s[end - 2].isHighSurrogate()) 2 else 1
            if (!isSwiftWhitespaces(scalarAt(s, end - width))) break
            end -= width
        }
        return s.substring(start, end)
    }

    /** 시험용: 풀린 구간 전부(시작, 끝, 비트 글자 다섯 — 골든 `wire/scalar-props` 와 같은 꼴). */
    fun ranges(): List<Triple<Int, Int, String>> {
        val r = runs
        return r.starts.indices.map { i ->
            Triple(r.starts[i], r.ends[i], r.bits[i].toInt().toString(2).padStart(5, '0'))
        }
    }
}
