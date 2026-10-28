// 원본: 없음(6차 c-fold — G §8-17 2 (a) API 별 그래핌 잠금의 자료와 판정을 JVM 에서 잰다. 기기 판정은 androidDeviceTest RulesGoldenDeviceTest)
package com.yehsung.aingcheck.core.rules.text

import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenFile
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * 기기 없이 잴 수 있는 것: ① 잠금 자료가 골든과 맞물리는가(있는 id · Swift 와 다른 값 · 스칼라 합 · 갈래 수) ② 판정이 목록의 늘고 줆을 잡는가
 * (가짜 분할기 — 기기가 낼 값을 흉내 낸다). 진짜 기기 값은 계측 시험이 API 26·36 에서 잰다(emu.sh instrumented --task :core:rules:connectedAndroidDeviceTest).
 */
class GraphemeArtLocksTest {
    private val golden: GoldenFile = Golden.load("text/graphemes")
    private val swift: Map<String, List<Int>> = golden.cases.associate { it.string("id") to it.array("clusters").map { c -> c.jsonPrimitive.int } }
    private val cps: Map<String, List<Int>> = golden.cases.associate { c ->
        c.string("id") to c.string("cps").split(' ').filter { it.isNotEmpty() }.map { it.toInt(16) }
    }
    private val api26 = GraphemeArtLocks.forApi(26) as GraphemeArtLocks.Exact

    /** 그래핌 조각 → 안쪽 경계(스칼라 자리, 0 과 끝은 뺀다). */
    private fun boundaries(clusters: List<Int>): Set<Int> = clusters.runningFold(0) { a, c -> a + c }.drop(1).dropLast(1).toSet()

    /** 기기가 낼 값을 흉내 내는 분할기: 골든 입력 → [table] 에 있으면 그 값, 없으면 Swift 값. */
    private fun fake(table: Map<String, List<Int>>): (String) -> List<Int> {
        val byText = golden.cases.associate { TextGoldenChecks.text(it.string("cps")) to it.string("id") }
        return { input -> byText.getValue(input).let { id -> table[id] ?: swift.getValue(id) } }
    }

    @Test
    fun measuredApisAreExactly26And36() {
        assertEquals(setOf(26, 36), GraphemeArtLocks.measuredApis, "잰 API 목록이 바뀌었다 — 잰 기록(포트 · 이미지 판)과 함께 고친다")
        assertEquals(GraphemeArtLocks.Exact(36, "Android 16 · ICU 76.1 · Unicode 16.0", emptyMap()), GraphemeArtLocks.forApi(36),
            "API 36 은 갈림 0줄을 빈 목록으로 정확히 잠근다(실측 0줄 — 허용 폭이면 0→2줄이 초록이었다)")
        assertTrue(GraphemeArtLocks.byApi.values.all { it is GraphemeArtLocks.Exact }, "잰 API 는 모두 정확한 목록이어야 한다(G §8-17 2 '늘거나 줄면 빨강')")
        assertEquals(null, GraphemeArtLocks.forApi(30), "재지 않은 API 에 목록이 있으면 안 된다")
    }

    @Test
    fun api26LockAgreesWithGolden() {
        val incb = golden.cases.filter { it["knownDivergence"] is JsonObject }.associate {
            it.string("id") to (it["knownDivergence"] as JsonObject).array("legacyClusters").map { c -> c.jsonPrimitive.int }
        }
        var modifier = 0
        var zwj = 0
        for ((id, clusters) in api26.lines) {
            val want = swift[id] ?: error("API 26 잠금의 $id 가 골든에 없다")
            assertNotEquals(want, clusters, "$id: 잠금 값이 Swift 값과 같다(갈림이 아니다 — 목록이 낡았다)")
            assertEquals(cps.getValue(id).size, clusters.sum(), "$id: 조각의 스칼라 합이 입력과 다르다")
            val scalars = cps.getValue(id)
            if (id in incb) {
                assertEquals(incb.getValue(id), clusters, "$id: API 26 의 InCB 줄은 JDK 와 같은 옛 규칙 값이었다")
                continue
            }
            // 경계 모양(기기 없이 잴 수 있는 값의 근거 — 6차 c-fold 검증 지적: 합 · 갈래 수만 보면 같은 합의 다른 값이 초록이었다).
            // ICU 58 은 Swift 보다 **덜 붙인다**: Swift 경계는 전부 남고(더 쪼갤 뿐), 더 생긴 경계는 ① 피부색 수식자 바로 앞(GB10 의 E_Base 표가
            // 유니코드 9) ② ZWJ 바로 뒤(GB11 이 Glue_After_Zwj 만)뿐이다. 줄마다 하나의 원인이다.
            val extra = boundaries(clusters) - boundaries(want)
            assertTrue(boundaries(clusters).containsAll(boundaries(want)), "$id: API 26 값 $clusters 이 Swift 경계 $want 를 지웠다(ICU 58 은 더 쪼갤 뿐이다)")
            assertTrue(extra.isNotEmpty(), "$id: 더 생긴 경계가 없다")
            when {
                extra.all { scalars[it] in 0x1F3FB..0x1F3FF } -> modifier++
                extra.all { scalars[it - 1] == 0x200D } -> zwj++
                else -> error("$id: API 26 값 $clusters 의 새 경계 $extra 가 수식자 앞도 ZWJ 뒤도 아니다(입력 ${cps.getValue(id).joinToString(" ") { it.toString(16) }}) — 실측 기록과 다르다")
            }
        }
        assertTrue(api26.lines.keys.containsAll(incb.keys), "API 26 은 InCB 2줄도 옛 규칙 값으로 갈렸다(실측)")
        println("AINGCHECK-CFOLD graphemes api26 lines=${api26.lines.size} incb=${incb.size} modifier=$modifier zwj=$zwj")
        assertEquals(listOf(26, 2, 23, 1), listOf(api26.lines.size, incb.size, modifier, zwj), "API 26 갈림 26줄 = InCB 2 + 수식자 23 + ZWJ 1(G §8-17 2 · W0-f ③)")
    }

    @Test
    fun exactLockPassesOnTheMeasuredDeviceValues() {
        val differ = TextGoldenChecks.graphemes(golden, TextRuntime.ANDROID_ART, 26, fake(api26.lines))
        assertEquals(26, differ)
    }

    @Test
    fun exactLockFailsWhenTheListShrinksGrowsOrChanges() {
        // 줄어듦: 기기가 한 줄을 Swift 값으로 낸다(목록에 남은 줄이 갈리지 않는다).
        val shrunk = api26.lines - "g-200"
        assertFailsWith<AssertionError> { TextGoldenChecks.graphemes(golden, TextRuntime.ANDROID_ART, 26, fake(shrunk)) }
        // 늘어남: 목록 밖 한 줄이 Swift 와 갈린다(한 그래핌을 둘로 쪼갠 값 — 스칼라 합은 같다).
        val extraId = golden.cases.map { it.string("id") }.first { id -> id !in api26.lines && swift.getValue(id).any { it >= 2 } }
        val split = swift.getValue(extraId).let { c -> val i = c.indexOfFirst { it >= 2 }; c.take(i) + listOf(1, c[i] - 1) + c.drop(i + 1) }
        assertFailsWith<AssertionError> { TextGoldenChecks.graphemes(golden, TextRuntime.ANDROID_ART, 26, fake(api26.lines + (extraId to split))) }
        // 값이 바뀜: 잠근 줄이 다른 갈림을 낸다.
        assertFailsWith<AssertionError> { TextGoldenChecks.graphemes(golden, TextRuntime.ANDROID_ART, 26, fake(api26.lines + ("g-202" to listOf(2, 1)))) }
        // 재지 않은 API.
        assertFailsWith<AssertionError> { TextGoldenChecks.graphemes(golden, TextRuntime.ANDROID_ART, 30, fake(emptyMap())) }
    }

    @Test
    fun api36ExactEmptyLockFailsOnAnyDivergence() {
        assertEquals(0, TextGoldenChecks.graphemes(golden, TextRuntime.ANDROID_ART, 36, fake(emptyMap())), "Swift 값만 내면 0줄")
        val legacy = golden.cases.filter { it["knownDivergence"] is JsonObject }.associate {
            it.string("id") to (it["knownDivergence"] as JsonObject).array("legacyClusters").map { c -> c.jsonPrimitive.int }
        }
        assertEquals(2, legacy.size)
        // 늘어남: InCB 2줄이 옛 규칙 값으로 돌아오면(API 26·JDK 와 같은 값) 빨강 — 예전 허용 폭은 이것을 초록으로 넘겼다.
        assertFailsWith<AssertionError> { TextGoldenChecks.graphemes(golden, TextRuntime.ANDROID_ART, 36, fake(legacy)) }
        assertFailsWith<AssertionError> { TextGoldenChecks.graphemes(golden, TextRuntime.ANDROID_ART, 36, fake(legacy.entries.take(1).associate { it.key to it.value })) }
        // API 26 의 수식자 갈림이 API 36 에 나타나도 빨강.
        assertFailsWith<AssertionError> { TextGoldenChecks.graphemes(golden, TextRuntime.ANDROID_ART, 36, fake(mapOf("g-200" to listOf(1, 1)))) }
    }
}
