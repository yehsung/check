// 원본: Tests/checkTests/GoldenExport/app-rules/GoldenExportAppRulesText.swift(골든 생성기) @ 1b8260d
package com.yehsung.aingcheck.core.rules.text

import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.string
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * 글자 골든의 JVM 대조(데스크톱 JDK 21). 같은 판정을 Android 계측(androidDeviceTest)이 ART 에서 다시 돈다(G §8-16 · 완료 ②).
 * 근거 줄은 `AINGCHECK-W1C …` 로 남긴다(게이트 로그 · 결과 XML).
 */
class TextGoldenTest {
    private fun note(line: String) = println("AINGCHECK-W1C $line")

    /** 번들이 골든과 다르면 새 번들 글자를 build/aingcheck-regen/ 에 적고 실패한다(손으로 고치지 않는다 — 그 파일을 옮긴다). */
    private fun regen(name: String, content: String): Nothing {
        val dir = File(System.getProperty("user.dir"), "build/aingcheck-regen").apply { mkdirs() }
        val file = File(dir, name)
        file.writeText(content)
        fail("번들 $name 이 골든과 다르다 — 새 내용을 ${file.path} 에 적었다(그 글자로 commonMain 의 같은 상수를 바꾼다)")
    }

    @Test
    fun scalarClassesBundleEqualsSwiftTable() {
        val golden = Golden.load("text/scalar-classes")
        val want = golden.cases.sortedBy { it.string("id") }.joinToString(",") { it.string("ranges") }
        val got = TextScalars.ranges().joinToString(",") { (lo, hi, klass) ->
            lo.toString(16).padStart(4, '0') + "-" + hi.toString(16).padStart(4, '0') + ":" + klass
        }
        if (want != got) {
            // 골든을 번들 꼴(구간 길이 36진 + 분류 글자)로 다시 짠다 — 생성 규칙은 UnicodeScalarTable 머리말.
            val classes = ArrayList<String>()
            val encoded = StringBuilder()
            for (token in want.split(',')) {
                val (span, klass) = token.split(':')
                val (lo, hi) = span.split('-').map { it.toInt(16) }
                if (klass !in classes) classes += klass
                encoded.append((hi - lo + 1).toString(36)).append(UnicodeScalarTable.ALPHABET[classes.indexOf(klass)])
            }
            regen("UnicodeScalarTable.txt", "CLASSES=" + classes.joinToString(" ") + "\nRANGES=" + encoded + "\n")
        }
        // 공개 판정이 표의 비트와 같은지(구간 양 끝을 표본으로).
        var probes = 0
        for ((lo, hi, klass) in TextScalars.ranges()) {
            for (cp in listOf(lo, hi)) {
                assertEquals(klass.substring(0, 2), TextScalars.generalCategory(cp))
                assertEquals(klass[2] == '1', TextScalars.isWhiteSpaceProperty(cp))
                assertEquals(klass[3] == '1', TextScalars.inWhitespacesAndNewlines(cp))
                assertEquals(klass[4] == '1', TextScalars.inWhitespaces(cp))
                assertEquals(klass[5] == '1', TextScalars.isVisible(cp))
                probes++
            }
        }
        val bundleChars = UnicodeScalarTable.CLASSES.length + UnicodeScalarTable.RANGES.length
        note("text/scalar-classes ranges=${TextScalars.ranges().size} bundleChars=$bundleChars probes=$probes")
        assertTrue(bundleChars < 16 * 1024, "스칼라 표 번들이 16KB 를 넘었다($bundleChars) — APK 예산 64KB(G §8-16 ②) 안에서 다시 압축한다")
    }

    @Test
    fun nfcFollowsStandardWithSixLockedDivergences() {
        val divergent = TextGoldenChecks.nfc(Golden.load("text/nfc"))
        note("text/nfc knownDivergence=$divergent runtime=JDK ${System.getProperty("java.runtime.version")}")
    }

    @Test
    fun graphemesUsePlatformBreakIteratorWithTwoLockedDivergences() {
        val differ = TextGoldenChecks.graphemes(Golden.load("text/graphemes"), TextRuntime.DESKTOP_JDK)
        note("text/graphemes differFromSwift=$differ runtime=JDK ${System.getProperty("java.runtime.version")}")
        assertEquals(2, differ, "JDK 21 은 InCB 2줄에서 Swift 와 갈린다(W0-b 실측)")
    }

    @Test
    fun sanitizeMatchesSwift() {
        TextGoldenChecks.sanitize(Golden.load("text/sanitize"))
    }

    @Test
    fun statusMessageOutcomeMatchesSwift() {
        val responses = TextGoldenChecks.statusMessage(Golden.load("text/status-message"))
        note("text/status-message responses=$responses")
    }

    @Test
    fun stickerTokensMatchSwift() {
        TextGoldenChecks.stickers(Golden.load("stickers/tokens"))
    }

    @Test
    fun collationTableBundleEqualsSwiftOrder() {
        val (order, ignorable, primaryIgnorable) = TextGoldenChecks.collationTableExpected(Golden.load("sort/collation-table"))
        if (order != CollationTable.ORDER || ignorable != CollationTable.IGNORABLE || primaryIgnorable != CollationTable.PRIMARY_IGNORABLE) {
            regen("CollationTable.txt", "ORDER=$order\nIGNORABLE=$ignorable\nPRIMARY_IGNORABLE=$primaryIgnorable\n")
        }
        note("sort/collation-table bundleChars=${CollationTable.ORDER.length}")
        assertTrue(CollationTable.ORDER.length + UnicodeScalarTable.RANGES.length < 64 * 1024, "글자 번들 합이 64KB 를 넘었다")
    }

    @Test
    fun naturalSortMatchesSwiftWhereSwiftIsConsistent() {
        val (hanMismatch, inconsistent) = TextGoldenChecks.naturalSort(Golden.load("sort/natural-ko"))
        note("sort/natural-ko swiftInconsistentPairs=$inconsistent hanMismatch=${hanMismatch.size}")
        // 잠금: 한자 읽기순(ko 규칙)을 번들하지 않아 갈리는 쌍 — 수가 바뀌면 코퍼스나 비교기가 바뀐 것이다.
        assertEquals(HAN_MISMATCH_LOCK, hanMismatch.size, "한자 갈림 쌍 수가 잠금과 다르다: $hanMismatch")
    }

    companion object {
        /** 한자 읽기순 미지원으로 Swift 와 갈리는 쌍 수(sort/natural-ko 코퍼스 기준 — C-X5 결과로 완료 보고에 싣는다). */
        const val HAN_MISMATCH_LOCK = 3
    }
}
