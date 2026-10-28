// 원본: 없음 — Swift `Unicode.Scalar.Properties.generalCategory == .decimalNumber`(표: contract/golden/text/scalar-classes.json 의 Nd 구간) @ 1b8260d
package com.yehsung.aingcheck.core.foundation.text

/**
 * 십진 숫자(유니코드 일반 범주 Nd)의 값. 날짜 파서(ICU 가 숫자 칸에 Nd 를 받는다 — [com.yehsung.aingcheck.core.foundation.time.IcuInternetDate])가 쓴다.
 *
 * G §8-16 ②: `Character.getType`·`Char.isDigit`·`digitToInt` 를 쓰지 않는다(JDK 21 = Unicode 15.0, ART 는 기기 API 마다 판이 다르다).
 * 정규식 `\d` 도 쓰지 않는다(ART 의 java.util.regex 는 ICU 라 Nd 전부를 받고 JDK 는 ASCII 만 — 같은 앱이 기기마다 다른 날짜를 읽는다).
 * 그래서 Swift 가 낸 범위 표(rules/text `UnicodeScalarTable` 과 같은 출처)의 Nd 구간을 여기 싣는다 — foundation 은 rules 에 기댈 수 없다.
 *
 * 유니코드는 Nd 를 언제나 0…9 가 이어진 열 칸 묶음으로만 싣는다(안정성 보장) — 그래서 표는 묶음의 첫 코드포인트만 든다.
 * 이 표와 rules/text 번들 표의 Nd 가 한 칸이라도 다르면 core/rules 의 `DecimalDigitsBundleTest` 가 빨갛다(U+0000…U+10FFFF 전부 대조).
 */
object DecimalDigits {
    /** Nd 묶음(열 칸)의 첫 코드포인트, 오름차순. Swift 표(1b8260d · 유니코드 16.0)의 Nd 770 칸 = 77 묶음. */
    private val RUN_STARTS: IntArray = intArrayOf(
        0x30, 0x660, 0x6F0, 0x7C0, 0x966, 0x9E6, 0xA66, 0xAE6, 0xB66, 0xBE6, 0xC66, 0xCE6, 0xD66, 0xDE6, 0xE50, 0xED0,
        0xF20, 0x1040, 0x1090, 0x17E0, 0x1810, 0x1946, 0x19D0, 0x1A80, 0x1A90, 0x1B50, 0x1BB0, 0x1C40, 0x1C50, 0xA620, 0xA8D0, 0xA900,
        0xA9D0, 0xA9F0, 0xAA50, 0xABF0, 0xFF10, 0x104A0, 0x10D30, 0x10D40, 0x11066, 0x110F0, 0x11136, 0x111D0, 0x112F0, 0x11450, 0x114D0, 0x11650,
        0x116C0, 0x116D0, 0x116DA, 0x11730, 0x118E0, 0x11950, 0x11BF0, 0x11C50, 0x11D50, 0x11DA0, 0x11DE0, 0x11F50, 0x16130, 0x16A60, 0x16AC0, 0x16B50,
        0x16D70, 0x1CCF0, 0x1D7CE, 0x1D7D8, 0x1D7E2, 0x1D7EC, 0x1D7F6, 0x1E140, 0x1E2F0, 0x1E4F0, 0x1E5F1, 0x1E950, 0x1FBF0,
    )

    /** 표에 든 묶음 수(시험이 표의 모양을 잰다). */
    val runCount: Int get() = RUN_STARTS.size

    /** Nd 스칼라의 10진 값(0…9). Nd 가 아니면 -1. 서로게이트 · 범위 밖도 -1. */
    fun value(cp: Int): Int {
        if (cp in 0x30..0x39) return cp - 0x30
        // 마지막으로 cp 이하에서 시작한 묶음을 찾는다(이분 탐색).
        var lo = 0
        var hi = RUN_STARTS.size - 1
        if (cp < RUN_STARTS[0]) return -1
        while (lo < hi) {
            val mid = (lo + hi + 1) ushr 1
            if (RUN_STARTS[mid] <= cp) lo = mid else hi = mid - 1
        }
        val offset = cp - RUN_STARTS[lo]
        return if (offset in 0..9) offset else -1
    }

    /** Nd 인가. */
    fun isDecimalDigit(cp: Int): Boolean = value(cp) >= 0
}
