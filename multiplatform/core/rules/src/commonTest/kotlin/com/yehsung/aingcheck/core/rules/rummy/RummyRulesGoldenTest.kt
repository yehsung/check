// 원본: Tests/checkTests/GoldenExport/rummy/GoldenExportRummyRules.swift(골든 생성기) · Tests/checkTests/V0369RummyRulesTests.swift:125 @ 1a5eeca6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.rules.renju.asArray
import com.yehsung.aingcheck.core.rules.renju.bool
import com.yehsung.aingcheck.core.rules.renju.optInt
import com.yehsung.aingcheck.core.rules.renju.optString
import com.yehsung.aingcheck.core.rules.renju.strings
import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 규칙이 Swift 와 비트로 같다 — 코퍼스 154건(기대값의 집이 하나뿐이다, Fixtures/rummy/cases.json) · payouts(설계서 §2.1) · 표시 순서 · 이어짐 · 면 받기.
 * 건수까지 잰다: 파일이 비거나 잘려도 "어긋남 0" 으로 초록이 되지 않게.
 */
class RummyRulesGoldenTest {
    private val golden = Golden.load("rummy/rules")
    private fun of(kind: String): List<JsonObject> = golden.cases.filter { it.string("kind_") == kind }

    private fun analysisText(a: RummyMeldAnalysis): String =
        "${RummyGoldenText.bit(a.valid)}:${a.kind?.rawValue ?: "-"}:${a.points?.toString() ?: "-"}"

    private fun parsed(texts: List<String>): List<RummyFace>? {
        val faces = texts.mapNotNull { RummyFace.of(it) }
        return if (faces.size == texts.size) faces else null
    }

    @Test
    fun corpusCountsAreExactly154() {
        assertEquals(74, of("meld").count { it.string("id").startsWith("M") })
        assertEquals(64, of("turn").size)
        assertEquals(16, of("score").count { it.string("id").startsWith("S") })
    }

    @Test
    fun meldsMatchSwift() {
        var checked = 0
        for (case in of("meld")) {
            val id = case.string("id")
            val meld = if ("tiles" in case) {
                parsed(case.array("tiles").strings())
            } else {
                RummyGoldenText.faces(case.string("faces"))
            }
            if (meld == null) {
                // R-01 밖 면이 든 세트는 만들 수 없다 = 무효.
                assertTrue(case["analysis"] is JsonNull, "$id: Kotlin 은 면 파싱 실패인데 Swift 는 읽었다")
                checked += 1
                continue
            }
            val got = RummyRules.analyze(meld)
            assertEquals(case.optString("analysis"), analysisText(got), id)
            // 세트 안 순서는 판정에 의미 없다(R-09): 뒤집어도 같은 답.
            assertEquals(got, RummyRules.analyze(meld.reversed()), "$id 순서 무관")
            assertEquals(case.optString("compareKey"), RummyGoldenText.text(RummyRules.compareKey(meld)), id)
            assertEquals(case.optString("displayOrder"), RummyGoldenText.text(RummyRules.displayOrder(meld)), id)
            assertEquals(case.bool("chainable"), RummyRules.isChainable(meld), id)
            checked += 1
        }
        assertEquals(174, checked)
    }

    @Test
    fun turnsMatchSwift() {
        val reasons = HashSet<String>()
        for (case in of("turn")) {
            val after = case.array("tableAfter").map { it.asArray().strings() }.mapNotNull { parsed(it) }
            val got = if (after.size == case.array("tableAfter").size) {
                // 형식 검사는 tableAfter 만 본다(R-16 0단계). 랙·이전 판의 이상한 면은 판정 입력에서 빠진다.
                val before = case.array("tableBefore").map { row -> row.asArray().strings().mapNotNull { RummyFace.of(it) } }
                val rack = case.array("rackBefore").strings().mapNotNull { RummyFace.of(it) }
                RummyRules.judgeTurn(case.bool("initialDone"), before, rack, after).rawValue
            } else {
                "malformed"
            }
            assertEquals(case.string("reason"), got, case.string("id"))
            reasons.add(got)
        }
        assertEquals(9, reasons.size, "코퍼스가 reason 9개를 다 밟아야 한다: $reasons")
    }

    @Test
    fun scoresMatchSwift() {
        for (case in of("score")) {
            val id = case.string("id")
            val racks = RummyGoldenText.sets(case.string("racks"))
            val got = RummyRules.finalScores(racks)
            assertEquals(case.string("scores"), RummyGoldenText.ids(got.scores), id)
            assertEquals(case.string("winners"), RummyGoldenText.ids(got.winners), id)
            assertEquals(case.string("payoutScores"), RummyGoldenText.ids(RummyRules.payoutScores(racks)), id)
            assertEquals(case.string("rackValues"), RummyGoldenText.ids(racks.map { RummyRules.rackValue(it) }), id)
            if (id.startsWith("S")) assertEquals(0, got.scores.sum(), "$id 영합")
        }
    }

    @Test
    fun payoutsMatchSwift() {
        val cases = of("payouts")
        assertTrue(cases.size >= 116, "payouts 표가 잘렸다: ${cases.size}")
        for (case in cases) {
            val id = case.string("id")
            val text = case.string("seats")
            val seats = if (text.isEmpty()) {
                emptyList()
            } else {
                text.split(' ').map { seat ->
                    val p = seat.split(',')
                    RummyPayoutSeat(p[0] == "a", p[1].toInt(), p[2].toInt(), p[3].toInt(), p[4].toIntOrNull())
                }
            }
            val got = RummyRules.payouts(case.int("seatCount"), case.int("stake"), seats)
            assertEquals(case.string("payouts"), RummyGoldenText.ids(got.payouts), id)
            assertEquals(case.string("ranks"), RummyGoldenText.ids(got.ranks), id)
        }
    }

    @Test
    fun prizeTableMatchesSwift() {
        val cases = of("prize")
        assertEquals(6, cases.size)
        for (case in cases) assertEquals(case.string("prizes"), RummyGoldenText.ids(RummyRules.prizeTable(case.int("seatCount"))), case.string("id"))
    }

    @Test
    fun faceTextMatchesSwift() {
        val cases = of("face")
        assertTrue(cases.size >= 18)
        for (case in cases) {
            val face = RummyFace.of(case.string("text"))
            assertEquals(case.bool("accepted"), face != null, case.string("id"))
            assertEquals(case.optInt("rackValue"), face?.rackValue, case.string("id"))
        }
    }

    @Test
    fun tablesMatchSwift() {
        val cases = of("tables")
        assertEquals(9, cases.size)
        for (case in cases) {
            val before = RummyGoldenText.sets(case.string("before"))
            val after = RummyGoldenText.sets(case.string("after"))
            assertEquals(case.bool("same"), RummyRules.sameTable(before, after), case.string("id"))
            assertEquals(case.int("newPoints"), RummyRules.newMeldPoints(before, after), case.string("id"))
        }
    }
}
