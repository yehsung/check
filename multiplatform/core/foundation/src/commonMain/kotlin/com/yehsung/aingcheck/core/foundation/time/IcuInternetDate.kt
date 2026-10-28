// 원본: Sources/CheckCore/CheckWorkInsights.swift:616-672(WorkInsightsDate) · Sources/CheckCore/SupabaseWorkService.swift:9-17·338-341(parseDate) @ 1b8260d
//       — 두 자리 모두 Foundation `ISO8601DateFormatter`(속은 ICU SimpleDateFormat · TimeZoneFormat 파서). 옛 자리: rules insights/IcuInternetDate.kt(W1-c)
package com.yehsung.aingcheck.core.foundation.time

import com.yehsung.aingcheck.core.foundation.text.DecimalDigits

/**
 * Apple `ISO8601DateFormatter` 의 `.withInternetDateTime`(+ `.withFractionalSeconds`) **파싱**을 손으로 옮긴 것 — 앱의 **날짜 파서 한 벌**
 * (6차 조정자 접기 c-fold, G §8-17 4). 부르는 곳 둘이 같은 포매터 옵션을 쓴다:
 *  - wire `SwiftISO8601.parse`(= Swift `SupabaseWorkService.parseDate` — 소수초 판 → 기본 판) · 골든 wire/rules `date-*` · `micros-*`
 *  - rules `WorkInsightsDate.parse`(기본 판 → 소수초 판 → 소수부 도려내기 · 초 내림) · 골든 dates/parse
 * 예전에는 wire 가 commonMain 정규식(`\d`)으로 따로 읽었다 — ART 의 java.util.regex 는 ICU 라 `\d` 가 Nd 전부를 받고 JDK 는 ASCII 만 받아
 * 같은 응답을 기기마다 다르게 읽었다. 이제 둘 다 이 파일을 부른다(구조 시험 rules `PlatformUnicodeStructureTest` 가 foundation·wire·net 의
 * 기기 소스에서도 `\d` 를 막는다).
 * 정규식을 쓰지 않는다 — 숫자 판정은 Swift 범위 표의 Nd([DecimalDigits], G §8-16 ②)로 하고, ART 의 ICU 정규식과 JDK 의 차이에 기대지 않는다.
 *
 * 맥에서 잰 ICU 동작(2026-10-28 — 골든 dates/parse 의 timestamps 줄이 잠근다):
 *  - 꼴은 `yyyy-MM-dd'T'HH:mm:ss[.SSS]XXXXX`. 글자 `-` `T` `:` `.` 는 정확히 그 글자다(대소문자 · 다른 글자 불가).
 *  - 숫자 칸은 **Nd(모든 문자의 10진 숫자 — 아랍-인도 · 전각 · 데바나가리 · 수학 굵은 숫자 …)** 를 받고 섞여도 된다. No(위첨자 ²)·Nl(Ⅷ 〇)은 아니다.
 *    자릿수 제한이 없다(욕심껏 — "202" 년 · "009" 월 · "000" 분). 앞에 ASCII `-` 하나를 받는다(ICU allowNegative — "-0" 분 · 음수 해).
 *    값은 ICU `Formattable::getLong()` 처럼 int32 로 자른다. 범위: 달 1…12 · 날 1…31(달 길이와 무관 — 2월 31일은 3월 3일로 넘김) ·
 *    시 0…24 · 분 0…59 · 초 0…59 · 해는 검사 없음(0 · 음수 = 율리우스력 천문 연도).
 *  - 소수초 `SSS` 도 Nd · `-` 를 받고, 숫자 i 자리를 ms 로 맞춘다(i<3 이면 ×10, i>3 이면 int32 로 10^(i-3) 나눔 — C 정수 나눗셈 · int32 넘침 그대로).
 *  - 시간대(ICU TimeZoneFormat ISO_EXTENDED_FULL): ① `Z`/`z` ② `+`/`-`(ASCII) 뒤 ASCII 숫자 — ICU parseAsciiOffsetFields
 *    (시 1~2자리 · 23 넘으면 앞 한 자리만 · 한 자리 시 뒤 `:` 는 건너뛰고 다음 숫자를 시에 붙이는 ICU 버그 그대로 · 분 · 초는 정확히 2자리 ≤ 59)
 *    와 기본형(parseAbuttingAsciiOffsetFields)을 견줘 긴 쪽 ③ 실패하면 지역화 GMT: `GMT` 접두 + `+H(:mm(:ss))`(지역화 숫자 = Nd) →
 *    `GMT`·`UTC`·`UT` 접두 + 기본 필드(구분자 · 붙은 꼴 중 긴 쪽) → `GMT`·`UTC`·`UT` 만(0). 시간대 **뒤에 남은 글자는 보지 않는다**(부분 일치).
 *
 * 모형 밖(골든에 넣지 않았다 — 서버 시각에 없는 꼴이고 ICU 가 자리마다 달리 받는다, 완료 보고에 실측 표):
 * 숫자 칸 · 시간대 앞 공백(White_Space)과 양방향 표시(U+200E 등), `-` `:` 앞 공백, 18자리 넘는 숫자, ASCII 밖 빼기표(U+2212 등).
 */
object IcuInternetDate {
    private const val MAX_OFFSET_HOUR = 23
    private const val MAX_OFFSET_MINUTE = 59
    private const val MAX_OFFSET_SECOND = 59
    private const val MILLIS_PER_HOUR = 3_600_000
    private const val MILLIS_PER_MINUTE = 60_000
    private const val MILLIS_PER_SECOND = 1_000

    /**
     * 성공이면 ICU UDate 를 CF 처럼 **1000 으로 한 번 나눈 값**(1970 기준 초, Swift `Date` 의 2001 기준 왕복 **전**), 실패면 null.
     * 부르는 쪽이 자기 Date 꼴로 옮긴다(wire `SwiftDate(초)` · rules `SwiftDate.since1970(초)` — 둘 다 2001 기준으로 한 번 왕복한다).
     * 내림은 부르는 쪽이 한다.
     */
    fun parse(text: String, fractional: Boolean): Double? {
        val c = Cursor(text)
        val year = c.number() ?: return null
        if (!c.literal('-')) return null
        val month = c.number() ?: return null
        if (month !in 1..12) return null
        if (!c.literal('-')) return null
        val day = c.number() ?: return null
        if (day !in 1..31) return null
        if (!c.literal('T')) return null
        val hour = c.number() ?: return null
        if (hour !in 0..24) return null
        if (!c.literal(':')) return null
        val minute = c.number() ?: return null
        if (minute !in 0..59) return null
        if (!c.literal(':')) return null
        val second = c.number() ?: return null
        if (second !in 0..59) return null
        var millis = 0
        if (fractional) {
            if (!c.literal('.')) return null
            millis = c.fractionMillis() ?: return null
        }
        val offsetMillis = zoneOffsetMillis(text, c.pos) ?: return null
        // ICU Calendar::computeTime — (날 × 86400000 + 하루 안 ms) − 시간대, 전부 double. CF 가 1000 으로 나눠 2001 기준으로 옮긴다.
        val epochDay = FoundationGregorian.epochDayLenient(year.toLong(), month.toLong(), day.toLong())
        var millisInDay = hour.toDouble()
        millisInDay = millisInDay * 60 + minute
        millisInDay = millisInDay * 60 + second
        millisInDay = millisInDay * 1000 + millis
        val udate = (epochDay.toDouble() * 86_400_000.0 + millisInDay) - offsetMillis.toDouble()
        return udate / 1000.0
    }

    // ---------- 숫자 ----------

    /** Nd 스칼라의 10진 값([DecimalDigits] — Swift 범위 표). Nd 가 아니면 -1. */
    private fun decimalDigitValue(cp: Int): Int = DecimalDigits.value(cp)

    private class Cursor(val text: String) {
        var pos = 0

        fun literal(ch: Char): Boolean {
            if (pos >= text.length || text[pos] != ch) return false
            pos++
            return true
        }

        /** ICU 숫자 칸: ASCII `-` 하나 + Nd 1자리 이상. (값, 숫자 자리 수). 18자리 넘으면 모형 밖이라 null. */
        private fun signedDigits(): Pair<Long, Int>? {
            var i = pos
            val negative = i < text.length && text[i] == '-'
            if (negative) i++
            var value = 0L
            var digits = 0
            while (i < text.length) {
                val cp = codePointAt(text, i)
                val d = decimalDigitValue(cp)
                if (d < 0) break
                if (++digits > 18) return null
                value = value * 10 + d
                i += if (cp >= 0x10000) 2 else 1
            }
            if (digits == 0) return null
            pos = i
            return (if (negative) -value else value) to digits
        }

        /** 날짜 · 시각 칸 — ICU `Formattable::getLong()` 처럼 int32 로 자른 값. */
        fun number(): Int? = signedDigits()?.first?.toInt()

        /** 소수초 칸 → ms(ICU UDAT_FRACTIONAL_SECOND_FIELD — int32 산술 그대로). */
        fun fractionMillis(): Int? {
            val (raw, digits) = signedDigits() ?: return null
            var value = raw.toInt()
            if (digits < 3) {
                repeat(3 - digits) { value *= 10 }
            } else {
                var a = 1
                repeat(digits - 3) { a *= 10 }
                if (a == 0) return null   // 10^32 이상은 int32 에서 0 — C 에서는 0 으로 나눔(모형 밖)
                value /= a
            }
            return value
        }
    }

    // ---------- 시간대(ICU TimeZoneFormat::parse, UTZFMT_STYLE_ISO_EXTENDED_FULL) ----------

    /** 시간대 칸 → ms(동쪽 +). 못 읽으면 null. 뒤에 남은 글자는 보지 않는다. */
    private fun zoneOffsetMillis(text: String, start: Int): Int? {
        if (start >= text.length) return null
        isoOffset(text, start)?.let { return it }
        return localizedGmtOffset(text, start)
    }

    /** ICU parseOffsetISO8601(extendedOnly = false). */
    private fun isoOffset(text: String, start: Int): Int? {
        val first = text[start]
        if (first == 'Z' || first == 'z') return 0
        val sign = when (first) {
            '+' -> 1
            '-' -> -1
            else -> return null
        }
        var (offset, end) = asciiOffsetFields(text, start + 1) ?: return null
        if (end - start <= 3) {
            // 확장형으로 두 자리 이하만 읽었으면 기본형("0230" → 2:30)도 읽어 긴 쪽을 쓴다.
            abuttingAsciiOffsetFields(text, start + 1)?.let { (basic, basicEnd) ->
                if (basicEnd > end) {
                    offset = basic
                    end = basicEnd
                }
            }
        }
        return sign * offset
    }

    private fun asciiDigit(c: Char): Int = if (c in '0'..'9') c - '0' else -1

    /** ICU parseAsciiOffsetFields(sep = ':', minFields = H, maxFields = HMS). (ms, 끝 위치). */
    private fun asciiOffsetFields(text: String, start: Int): Pair<Int, Int>? {
        val fieldVal = intArrayOf(0, 0, 0)
        val fieldLen = intArrayOf(0, -1, -1)
        var idx = start
        var fieldIdx = 0
        while (idx < text.length && fieldIdx <= 2) {
            val c = text[idx]
            if (c == ':') {
                if (fieldIdx == 0) {
                    if (fieldLen[0] == 0) break
                    // ICU 주석은 "1 digit hour, move to next field" 지만 fieldIdx 를 올리지 않는다 — "+1:30" 은 13시다(맥 실측 그대로 옮긴다).
                } else {
                    if (fieldLen[fieldIdx] != -1) break
                    fieldLen[fieldIdx] = 0
                }
                idx++
                continue
            } else if (fieldLen[fieldIdx] == -1) {
                break
            }
            val digit = asciiDigit(c)
            if (digit < 0) break
            fieldVal[fieldIdx] = fieldVal[fieldIdx] * 10 + digit
            fieldLen[fieldIdx]++
            if (fieldLen[fieldIdx] >= 2) fieldIdx++
            idx++
        }
        if (fieldLen[0] == 0) return null
        if (fieldVal[0] > MAX_OFFSET_HOUR) return (fieldVal[0] / 10) * MILLIS_PER_HOUR to (start + 1)
        var offset = fieldVal[0] * MILLIS_PER_HOUR
        var parsedLen = fieldLen[0]
        if (fieldLen[1] == 2 && fieldVal[1] <= MAX_OFFSET_MINUTE) {
            offset += fieldVal[1] * MILLIS_PER_MINUTE
            parsedLen += 1 + fieldLen[1]
            if (fieldLen[2] == 2 && fieldVal[2] <= MAX_OFFSET_SECOND) {
                offset += fieldVal[2] * MILLIS_PER_SECOND
                parsedLen += 1 + fieldLen[2]
            }
        }
        return offset to (start + parsedLen)
    }

    /** ICU parseAbuttingAsciiOffsetFields(minFields = H, maxFields = HMS, fixedHourDigits = false). */
    private fun abuttingAsciiOffsetFields(text: String, start: Int): Pair<Int, Int>? {
        val digits = IntArray(6)
        var count = 0
        var idx = start
        while (count < 6 && idx < text.length) {
            val d = asciiDigit(text[idx])
            if (d < 0) break
            digits[count++] = d
            idx++
        }
        return abuttingFields(digits, count)?.let { (offset, used) -> offset to (start + used) }
    }

    /** 붙은 숫자 n 개 → (H · HH · Hmm · HHmm · Hmmss · HHmmss) 중 범위 안인 가장 긴 것. (ms, 쓴 숫자 수). */
    private fun abuttingFields(digits: IntArray, available: Int): Pair<Int, Int>? {
        var n = available
        while (n >= 1) {
            var h = 0
            var m = 0
            var s = 0
            when (n) {
                1 -> h = digits[0]
                2 -> h = digits[0] * 10 + digits[1]
                3 -> { h = digits[0]; m = digits[1] * 10 + digits[2] }
                4 -> { h = digits[0] * 10 + digits[1]; m = digits[2] * 10 + digits[3] }
                5 -> { h = digits[0]; m = digits[1] * 10 + digits[2]; s = digits[3] * 10 + digits[4] }
                6 -> { h = digits[0] * 10 + digits[1]; m = digits[2] * 10 + digits[3]; s = digits[4] * 10 + digits[5] }
            }
            if (h <= MAX_OFFSET_HOUR && m <= MAX_OFFSET_MINUTE && s <= MAX_OFFSET_SECOND) {
                return (h * MILLIS_PER_HOUR + m * MILLIS_PER_MINUTE + s * MILLIS_PER_SECOND) to n
            }
            n--
        }
        return null
    }

    // ---------- 지역화 GMT(ICU parseOffsetLocalizedGMT — en_US_POSIX: "GMT{0}" · "+HH:mm;-HH:mm" · 영 "GMT") ----------

    private val ALT_GMT = listOf("GMT", "UTC", "UT")

    /** ICU caseCompare(대소문자 접기) — 접어서 g · m · t · u · c 가 되는 ASCII 밖 글자는 없으므로 ASCII 만 접는다(플랫폼 대소문자 표에 기대지 않는다). */
    private fun matchesIgnoringCase(text: String, at: Int, word: String): Boolean {
        if (at + word.length > text.length) return false
        for (k in word.indices) {
            val a = text[at + k]
            val folded = if (a in 'a'..'z') a - 32 else a
            if (folded != word[k]) return false
        }
        return true
    }

    private fun localizedGmtOffset(text: String, start: Int): Int? {
        // ① "GMT" + 지역화 꼴(+H:mm:ss · -H:mm:ss · +H:mm · -H:mm · +H · -H 차례)
        if (matchesIgnoringCase(text, start, "GMT")) {
            offsetFieldsWithPatterns(text, start + 3)?.let { return it }
        }
        // ② 기본 꼴: GMT · UTC · UT + 부호 + (구분자 꼴 · 붙은 꼴 중 긴 쪽)
        defaultLocalizedGmt(text, start)?.let { return it }
        // ③ 영 꼴 "GMT" · ④ 기본 영 꼴 GMT · UTC · UT
        if (matchesIgnoringCase(text, start, "GMT")) return 0
        for (word in ALT_GMT) if (matchesIgnoringCase(text, start, word)) return 0
        return null
    }

    /** ICU parseSingleLocalizedDigit — ASCII 다음 u_charDigitValue(Nd). (값, 글자 단위 길이) 또는 null. */
    private fun localizedDigit(text: String, idx: Int): Pair<Int, Int>? {
        if (idx >= text.length) return null
        val cp = codePointAt(text, idx)
        val d = decimalDigitValue(cp)
        if (d < 0) return null
        return d to (if (cp >= 0x10000) 2 else 1)
    }

    /** ICU parseOffsetFieldWithLocalizedDigits. (값, 길이) — 실패면 길이 0. */
    private fun localizedField(text: String, start: Int, minDigits: Int, maxDigits: Int, maxVal: Int): Pair<Int, Int> {
        var value = 0
        var count = 0
        var idx = start
        while (idx < text.length && count < maxDigits) {
            val (digit, len) = localizedDigit(text, idx) ?: break
            val next = value * 10 + digit
            if (next > maxVal) break
            value = next
            count++
            idx += len
        }
        return if (count < minDigits) -1 to 0 else value to (idx - start)
    }

    /** ICU parseOffsetFields — 꼴 여섯을 차례로(맞으면 그 부호). 성공이면 ms. */
    private fun offsetFieldsWithPatterns(text: String, start: Int): Int? {
        for (fields in intArrayOf(3, 2, 1)) {
            for (signChar in charArrayOf('+', '-')) {
                if (start >= text.length || text[start] != signChar) continue
                var idx = start + 1
                val (h, hLen) = localizedField(text, idx, 1, 2, MAX_OFFSET_HOUR)
                if (hLen == 0) continue
                idx += hLen
                var m = 0
                var s = 0
                if (fields >= 2) {
                    if (idx >= text.length || text[idx] != ':') continue
                    val (mv, mLen) = localizedField(text, idx + 1, 2, 2, MAX_OFFSET_MINUTE)
                    if (mLen == 0) continue
                    m = mv
                    idx += 1 + mLen
                }
                if (fields >= 3) {
                    if (idx >= text.length || text[idx] != ':') continue
                    val (sv, sLen) = localizedField(text, idx + 1, 2, 2, MAX_OFFSET_SECOND)
                    if (sLen == 0) continue
                    s = sv
                    idx += 1 + sLen
                }
                val sign = if (signChar == '+') 1 else -1
                return sign * (h * MILLIS_PER_HOUR + m * MILLIS_PER_MINUTE + s * MILLIS_PER_SECOND)
            }
        }
        return null
    }

    /** ICU parseOffsetDefaultLocalizedGMT. 성공이면 ms(숫자를 하나도 못 읽어도 부호까지 먹으면 0). */
    private fun defaultLocalizedGmt(text: String, start: Int): Int? {
        val word = ALT_GMT.firstOrNull { matchesIgnoringCase(text, start, it) } ?: return null
        var idx = start + word.length
        if (idx + 1 >= text.length) return null   // 부호와 숫자 하나가 들어갈 자리가 없다
        val sign = when (text[idx]) {
            '+' -> 1
            '-' -> -1
            else -> return null
        }
        idx++
        val (withSep, lenWithSep) = defaultOffsetFields(text, idx)
        if (lenWithSep == text.length - idx) return sign * withSep
        val (abut, lenAbut) = abuttingLocalizedFields(text, idx)
        return if (lenWithSep > lenAbut) sign * withSep else sign * abut
    }

    /** ICU parseDefaultOffsetFields(sep = ':'). (ms, 길이). */
    private fun defaultOffsetFields(text: String, start: Int): Pair<Int, Int> {
        var idx = start
        var hour = 0
        var min = 0
        var sec = 0
        run {
            val (h, hLen) = localizedField(text, idx, 1, 2, MAX_OFFSET_HOUR)
            if (hLen == 0) return@run
            hour = h
            idx += hLen
            if (idx + 1 < text.length && text[idx] == ':') {
                val (m, mLen) = localizedField(text, idx + 1, 2, 2, MAX_OFFSET_MINUTE)
                if (mLen == 0) return@run
                min = m
                idx += 1 + mLen
                if (idx + 1 < text.length && text[idx] == ':') {
                    val (s, sLen) = localizedField(text, idx + 1, 2, 2, MAX_OFFSET_SECOND)
                    if (sLen == 0) return@run
                    sec = s
                    idx += 1 + sLen
                }
            }
        }
        if (idx == start) return 0 to 0
        return (hour * MILLIS_PER_HOUR + min * MILLIS_PER_MINUTE + sec * MILLIS_PER_SECOND) to (idx - start)
    }

    /** ICU parseAbuttingOffsetFields(지역화 숫자 최대 6). (ms, 길이). */
    private fun abuttingLocalizedFields(text: String, start: Int): Pair<Int, Int> {
        val digits = IntArray(6)
        val ends = IntArray(6)
        var count = 0
        var idx = start
        while (count < 6) {
            val (d, len) = localizedDigit(text, idx) ?: break
            digits[count] = d
            idx += len
            ends[count] = idx - start
            count++
        }
        if (count == 0) return 0 to 0
        val (offset, used) = abuttingFields(digits, count) ?: return 0 to 0
        return offset to ends[used - 1]
    }

    private fun codePointAt(text: String, i: Int): Int {
        val c = text[i]
        if (c.isHighSurrogate() && i + 1 < text.length && text[i + 1].isLowSurrogate()) {
            return 0x10000 + ((c.code - 0xD800) shl 10) + (text[i + 1].code - 0xDC00)
        }
        return c.code
    }
}
