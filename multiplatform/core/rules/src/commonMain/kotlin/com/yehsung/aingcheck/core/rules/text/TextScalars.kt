// 원본: Sources/CheckCore/SupabaseWorkModels.swift(MessageBody.hasVisibleContent) · CheckTodoModel.swift(generalCategory·isWhitespace) ·
//       Foundation CharacterSet.whitespacesAndNewlines·whitespaces(여러 trim) @ 1b8260d — G §8-16 ②
package com.yehsung.aingcheck.core.rules.text

/**
 * 스칼라 하나의 분류(번들 표 — [UnicodeScalarTable]). Swift 쪽 대응:
 *  - [generalCategory] = `Unicode.Scalar.Properties.generalCategory`(두 글자 약어)
 *  - [isWhiteSpaceProperty] = `properties.isWhitespace`(유니코드 White_Space)
 *  - [inWhitespacesAndNewlines] = `CharacterSet.whitespacesAndNewlines.contains`
 *  - [inWhitespaces] = `CharacterSet.whitespaces.contains`
 *  - [isVisible] = `MessageBody.hasVisibleContent(String(스칼라))`
 * 서로게이트(D800–DFFF)는 스칼라가 아니라 "Cs" · 전부 거짓이다(Swift 글자에 들어올 수 없다 — Kotlin 글자에 짝 없이 남은 것만 여기 온다).
 */
object TextScalars {
    private class Decoded(val starts: IntArray, val classes: Array<String>, val classOf: ByteArray)

    private val table: Decoded by lazy { decode(UnicodeScalarTable.CLASSES, UnicodeScalarTable.RANGES, UnicodeScalarTable.ALPHABET) }

    /** 번들 글자를 구간 시작 배열로 푼다. 모양이 틀리면 바로 실패한다(조용히 빈 표로 돌지 않게). */
    private fun decode(classesText: String, ranges: String, alphabet: String): Decoded {
        val classes = classesText.split(' ').toTypedArray()
        val starts = ArrayList<Int>(4400)
        val classOf = ArrayList<Byte>(4400)
        var next = 0
        var length = 0
        var digits = 0
        for (c in ranges) {
            val digit = when (c) {
                in '0'..'9' -> c - '0'
                in 'a'..'z' -> c - 'a' + 10
                else -> -1
            }
            if (digit >= 0) {
                length = length * 36 + digit
                digits++
                continue
            }
            val index = alphabet.indexOf(c)
            check(index in classes.indices && digits > 0 && length > 0) { "UnicodeScalarTable 을 못 읽었다: '$c' @ ${starts.size}" }
            starts += next
            classOf += index.toByte()
            next += length
            length = 0
            digits = 0
        }
        check(digits == 0 && next == 0x110000) { "UnicodeScalarTable 이 U+0000..U+10FFFF 를 빈틈없이 덮지 않는다(끝 ${next.toString(16)})" }
        return Decoded(starts.toIntArray(), classes, classOf.toByteArray())
    }

    private fun rangeIndex(cp: Int): Int {
        val t = table
        var lo = 0
        var hi = t.starts.size - 1
        while (lo < hi) {
            val mid = (lo + hi + 1) ushr 1
            if (t.starts[mid] <= cp) lo = mid else hi = mid - 1
        }
        return lo
    }

    /** 코드포인트의 분류 글자(6자: 범주 2 + 비트 4). 범위 밖이면 "Cn0000". */
    fun classOf(cp: Int): String {
        if (cp < 0 || cp > 0x10FFFF) return "Cn0000"
        val t = table
        return t.classes[t.classOf[rangeIndex(cp)].toInt()]
    }

    /** 그 코드포인트가 든 구간의 시작(같은 분류가 이어지는 첫 코드포인트). 숫자(Nd) 값 계산에 쓴다. */
    internal fun rangeStartOf(cp: Int): Int = table.starts[rangeIndex(cp.coerceIn(0, 0x10FFFF))]

    fun generalCategory(cp: Int): String = classOf(cp).substring(0, 2)
    fun isWhiteSpaceProperty(cp: Int): Boolean = classOf(cp)[2] == '1'
    fun inWhitespacesAndNewlines(cp: Int): Boolean = classOf(cp)[3] == '1'
    fun inWhitespaces(cp: Int): Boolean = classOf(cp)[4] == '1'
    fun isVisible(cp: Int): Boolean = classOf(cp)[5] == '1'

    /** 구간 목록(시험이 골든 꼴로 다시 짜 맞춘다): (시작, 끝 포함, 분류). */
    internal fun ranges(): List<Triple<Int, Int, String>> {
        val t = table
        return t.starts.indices.map { i ->
            val end = if (i + 1 < t.starts.size) t.starts[i + 1] - 1 else 0x10FFFF
            Triple(t.starts[i], end, t.classes[t.classOf[i].toInt()])
        }
    }

    /** Swift `trimmingCharacters(in: .whitespacesAndNewlines)` — 앞뒤 **스칼라** 를 지운다. */
    fun trimmingWhitespacesAndNewlines(text: String): String = trimScalars(text) { inWhitespacesAndNewlines(it) }

    /** Swift `trimmingCharacters(in: .whitespaces)`. */
    fun trimmingWhitespaces(text: String): String = trimScalars(text) { inWhitespaces(it) }

    /** 앞뒤에서 [drop] 이 참인 스칼라를 지운다(서로게이트 짝 단위). */
    fun trimScalars(text: String, drop: (Int) -> Boolean): String {
        if (text.isEmpty()) return text
        val cps = text.codePointArray()
        var start = 0
        var end = cps.size
        while (start < end && drop(cps[start])) start++
        while (end > start && drop(cps[end - 1])) end--
        if (start == 0 && end == cps.size) return text
        return stringFromCodePoints(cps, start, end)
    }
}
