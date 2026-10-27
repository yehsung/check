// 원본: 없음(W1-c 완료 ② — platformSensitive 골든을 ART 에서 다시 돈다 · G §8-16 ①~③)
package com.yehsung.aingcheck.core.rules.text

import android.os.Build
import com.yehsung.aingcheck.core.rules.insights.RecordsGoldenChecks
import com.yehsung.aingcheck.core.rules.todo.TodoGoldenChecks
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenFile
import com.yehsung.aingcheck.testkit.golden.string
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * W1-c 골든을 에뮬레이터(ART)에서 대조한다. 판정은 commonTest 의 `…GoldenChecks` 하나 — JVM 시험(desktopTest)과 같은 함수를 부른다.
 *
 * 골든은 저장소 파일을 읽지 못하는 기기라서 시험 APK 의 Java 자원(`contract/golden` 을 자원 뿌리로 — 조정자 패치)으로 싣는다.
 * 근거 줄은 `AINGCHECK-W1C-ART` 로 남긴다(emu.sh instrumented 가 logcat 에서 모은다).
 */
// AndroidJUnitRunner 가 JUnit4 기본 러너로 돈다(@RunWith 없음 — androidx.test.ext 가 끌고 오는 옛 lifecycle 을 피한다).
class RulesGoldenDeviceTest {
    private fun load(name: String): GoldenFile {
        val stream = RulesGoldenDeviceTest::class.java.classLoader!!.getResourceAsStream("$name.json")
            ?: error("시험 APK 에 골든 $name.json 이 없다 — core/rules 의 androidDeviceTest 자원 뿌리(contract/golden)를 확인한다")
        val text = stream.use { it.readBytes().toString(Charsets.UTF_8) }
        return Golden.parse(name, text, "apk:$name.json")
    }

    private fun note(line: String) = println("AINGCHECK-W1C-ART api=${Build.VERSION.SDK_INT} $line")

    @Test
    fun nfcFollowsStandardWithSixLockedDivergences() {
        val divergent = TextGoldenChecks.nfc(load("text/nfc"))
        note("text/nfc knownDivergence=$divergent")
    }

    @Test
    fun graphemesUsePlatformBreakIteratorWithinLockedDivergences() {
        val differ = TextGoldenChecks.graphemes(load("text/graphemes"), TextRuntime.ANDROID_ART)
        note("text/graphemes differFromSwift=$differ (InCB 2줄 중)")
        assertTrue(differ in 0..2, "InCB 밖에서 갈렸다")
    }

    @Test
    fun scalarTableBundleMatchesSwiftOnArt() {
        val golden = load("text/scalar-classes")
        val want = golden.cases.sortedBy { it.string("id") }.joinToString(",") { it.string("ranges") }
        val got = TextScalars.ranges().joinToString(",") { (lo, hi, klass) ->
            lo.toString(16).padStart(4, '0') + "-" + hi.toString(16).padStart(4, '0') + ":" + klass
        }
        assertEquals(want, got, "번들 범위 표가 Swift 표와 다르다(ART)")
        var probes = 0
        for ((lo, hi, klass) in TextScalars.ranges()) {
            for (cp in listOf(lo, hi)) {
                assertEquals(klass.substring(0, 2), TextScalars.generalCategory(cp), "범주 U+${cp.toString(16)}")
                probes++
            }
        }
        note("text/scalar-classes probes=$probes ranges=${TextScalars.ranges().size}")
    }

    @Test
    fun sanitizeMatchesSwift() = TextGoldenChecks.sanitize(load("text/sanitize"))

    @Test
    fun stickerTokensMatchSwift() = TextGoldenChecks.stickers(load("stickers/tokens"))

    @Test
    fun naturalSortMatchesSwiftWhereSwiftIsConsistent() {
        val (hanMismatch, inconsistent) = TextGoldenChecks.naturalSort(load("sort/natural-ko"))
        note("sort/natural-ko swiftInconsistentPairs=$inconsistent hanMismatch=${hanMismatch.size}")
        assertEquals(3, hanMismatch.size, "한자 갈림 쌍 수가 데스크톱 잠금(3)과 다르다: $hanMismatch")
    }

    @Test
    fun messageRulesMatchSwift() {
        val scenarios = MessageGoldenChecks.messageRules(load("text/message-rules"))
        note("text/message-rules scenarios=$scenarios zones=5")
    }

    @Test
    fun megaphoneMatchesSwift() = MessageGoldenChecks.megaphone(load("text/megaphone"))

    @Test
    fun blockReportMatchesSwift() = MessageGoldenChecks.blockReport(load("text/block-report"))

    @Test
    fun weeklyStatusMatchesSwift() = RecordsGoldenChecks.weeklyStatusMatchesSwift(load("weekly/status"))

    @Test
    fun datesParseMatchesSwift() = RecordsGoldenChecks.datesParseMatchesSwift(load("dates/parse"))

    @Test
    fun insightsComputationMatchesSwift() = RecordsGoldenChecks.insightsComputationMatchesSwift(load("insights/computation"))

    @Test
    fun insightsTokenMatchesSwift() = RecordsGoldenChecks.insightsTokenMatchesSwift(load("insights/token"))

    @Test
    fun todoRulesMatchSwift() = TodoGoldenChecks.todoRulesMatchSwift(load("todo/rules"))
}
