// 원본: 없음(W1-d 번들 대조 — 8차 fold, G §8-20 #3 · §8-16 ②: 글자 판정은 Swift 가 낸 범위 표로)
package com.yehsung.aingcheck.core.wire.text

import com.yehsung.aingcheck.core.wire.json.SwiftKeys
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.string
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.fail

class WireScalarTableGoldenTest {
    private fun golden(): String =
        Golden.load("wire/scalar-props").cases.sortedBy { it.string("id") }.joinToString(",") { it.string("ranges") }

    private fun bundle(): String = WireScalars.ranges().joinToString(",") { (lo, hi, bits) ->
        lo.toString(16).padStart(4, '0') + "-" + hi.toString(16).padStart(4, '0') + ":" + bits
    }

    /** 번들이 골든과 다르면 새 [WireScalarTable] 을 build/aingcheck-regen/ 에 적고 실패한다(손으로 고치지 않는다 — 그 파일을 옮긴다). */
    @Test
    fun bundleEqualsSwiftTable() {
        val want = golden()
        val got = runCatching { bundle() }.getOrElse { "(번들을 못 풀었다: ${it.message})" }
        if (want == got) {
            println("AINGCHECK-W1D wire/scalar-props ranges=${WireScalars.ranges().size} bundleChars=${WireScalarTable.RANGES.length}")
            return
        }
        val encoded = StringBuilder()
        for (token in want.split(',')) {
            val (span, bits) = token.split(':')
            val (lo, hi) = span.split('-').map { it.toInt(16) }
            encoded.append((hi - lo + 1).toString(36)).append(WireScalarTable.ALPHABET[bits.toInt(2)])
        }
        val chunks = encoded.toString().chunked(4000).joinToString(" +\n") { "        \"$it\"" }
        val content = """
            |// 원본: 없음(생성물 — contract/golden/wire/scalar-props.json 을 압축한 번들. Swift 판정 원본은 그 골든의 swiftSources) @ 1b8260d
            |// 손으로 고치지 않는다: 골든이 바뀌면 WireScalarTableGoldenTest 가 빨개지고, 새 내용을 build/aingcheck-regen/ 에 적는다.
            |package com.yehsung.aingcheck.core.wire.text
            |
            |/**
            | * W1-d 스칼라 판정 번들(G §8-20 #3 · §8-16 ② — `Character.getType` 을 쓰지 않는다). 비트 다섯의 뜻은 [WireScalars] 머리말.
            | *
            | * - [RANGES]: U+0000 부터 빈틈없이 이어지는 구간들. 구간 하나 = 길이(36진 소문자) + 비트 글자([ALPHABET] 의 자리 = 비트 값).
            | *   평면(0x10000) 경계에서 구간을 끊는다(골든 꼴 그대로).
            | */
            |internal object WireScalarTable {
            |    const val ALPHABET: String = "${WireScalarTable.ALPHABET}"
            |    val RANGES: String =
            |__CHUNKS__
            |}
            |""".trimMargin().replace("__CHUNKS__", chunks)
        val dir = File(System.getProperty("user.dir"), "build/aingcheck-regen").apply { mkdirs() }
        val file = File(dir, "WireScalarTable.kt").apply { writeText(content) }
        fail("번들 WireScalarTable 이 골든 wire/scalar-props 와 다르다 — 새 내용을 ${file.path} 에 적었다(그 파일로 commonMain 의 같은 파일을 바꾼다)")
    }

    /**
     * 판정이 JDK `Character` 가 아니라 표를 따르는지 — JDK 와 Swift 가 갈리는 글자로 잰다.
     * U+0085(NEL): Swift White_Space 참 · JDK isWhitespace 거짓. U+001C(FS): Swift 거짓 · JDK 참. U+00A0: Swift 참 · JDK isWhitespace 거짓.
     */
    @Test
    fun predicatesFollowSwiftNotJdk() {
        assertTrue(WireScalars.isWhitespace(0x85))
        assertFalse(WireScalars.isWhitespace(0x1C))
        assertTrue(WireScalars.isWhitespace(0xA0))
        assertFalse(WireScalars.isSwiftWhitespaces('\n'.code), "CharacterSet.whitespaces 는 줄바꿈을 넣지 않는다")
        assertTrue(WireScalars.isSwiftWhitespaces('\t'.code))
        assertTrue(WireScalars.isUppercase('A'.code) && WireScalars.isLetter('A'.code))
        assertTrue(WireScalars.isLowercase('z'.code))
        assertFalse(WireScalars.isLetter('2'.code))
        assertEquals(0, WireScalars.bits(0xD800), "서로게이트 반쪽은 0")
        // 키 전략(정답 표는 W0-b decoder.json). 표가 보조 평면 대문자(U+10400)를 대문자로 보므로 대리쌍을 반으로 가르지 않아야 한다.
        assertEquals("url2X", SwiftKeys.fromSnakeCase("url_2x"))
        assertEquals("my_url_property", SwiftKeys.toSnakeCase("myURLProperty"))
        assertTrue(WireScalars.isUppercase(0x10400))
        assertEquals("a_\uD801\uDC28b", SwiftKeys.toSnakeCase("a\uD801\uDC00b"))
        assertEquals("ab_\uD801\uDC28_\uD801\uDC28c", SwiftKeys.toSnakeCase("ab\uD801\uDC00\uD801\uDC00c"), "대문자 덩어리의 마지막 글자 앞 = 스칼라 하나 앞")
    }
}
