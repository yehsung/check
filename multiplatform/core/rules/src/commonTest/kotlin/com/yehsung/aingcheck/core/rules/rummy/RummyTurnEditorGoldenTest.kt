// 원본: Tests/checkTests/GoldenExport/rummy/GoldenExportRummyTurnEditor.swift(골든 생성기) @ 1a5eeca6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.rules.renju.asObject
import com.yehsung.aingcheck.core.rules.renju.bool
import com.yehsung.aingcheck.core.rules.renju.strings
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * 차례 편집기가 Swift 와 비트로 같다: 동작 열 → 판·랙·배치·판정 스냅숏. 이름 있는 대본은 글자로, 무작위 대본은 지문으로 대조한다.
 * 스냅숏은 와이어로 나가는 값(묶음 · 점)뿐 아니라 로컬 id · 받침대 자리 · 되돌린 자리까지 재므로 편집기 안쪽이 갈려도 빨갛다.
 */
class RummyTurnEditorGoldenTest {
    private val t = RummyGoldenText

    /** 대본 한 동작. 답 = (받음, 미리보기 글자). */
    private fun run(editor: RummyTurnEditor, op: String): Pair<Boolean, String> {
        val parts = op.split(' ', limit = 3)
        return when (parts[0]) {
            "start" -> true to "-"
            "reset" -> {
                editor.reset()
                true to "-"
            }
            "sort" -> {
                editor.sortRack(RummyRackSort.valueOf(parts[1]))
                true to "-"
            }
            "set" -> {
                val index = parts[1].toInt()
                val point = t.point(parts[2])
                val preview = t.preview(editor.previewMoveSet(index, point))
                editor.moveSet(index, point) to preview
            }
            "block" -> {
                val ids = t.ints(parts[1])
                val target = t.target(parts[2])
                val preview = t.preview(editor.previewDrop(ids, target))
                editor.moveBlock(ids, target) to preview
            }
            "afterdrop" -> {
                val layout = editor.rackLayoutAfterDrop(t.ints(parts[1]), t.slot(parts[2]))
                (layout != null) to (layout?.let { t.layout(it) } ?: "nil")
            }
            "stands" -> {
                val (table, rack) = op.removePrefix("stands ").split(';')
                editor.standsOn(t.sets(table), t.faces(rack)) to "-"
            }
            else -> fail("모르는 동작: $op")
        }
    }

    @Test
    fun namedScriptsMatchSwift() {
        val cases = Golden.load("rummy/turn-editor").cases.filter { "steps" in it }
        assertTrue(cases.size >= 55, "이름 있는 대본이 잘렸다: ${cases.size}")
        var steps = 0
        for (case in cases) {
            val id = case.string("id")
            val editor = t.editor(case)
            for ((index, element) in case.array("steps").withIndex()) {
                val step = element.asObject()
                val at = "$id 단계 $index(${step.string("op")})"
                val (ok, preview) = run(editor, step.string("op"))
                assertEquals(step.bool("ok"), ok, "$at 받음")
                assertEquals(step.string("preview"), preview, "$at 미리보기")
                assertEquals(step.string("after"), t.core(editor), "$at 스냅숏")
                assertEquals(step.string("extra"), t.fnv(t.extra(editor)), "$at 나머지 읽기: ${t.extra(editor)}")
                steps += 1
            }
        }
        assertTrue(steps >= 150, "단계가 너무 적다: $steps")
    }

    /** 동작 열이 규칙을 실제로 밟는가 — 계획 갈래마다 받은 수. 지문 대조가 헛돌지 않게 잰다. */
    private val planCounts = HashMap<String, Int>()

    private fun replayLines(case: JsonObject): Int {
        val id = case.string("id")
        val editor = t.editor(case)
        var accepted = 0
        for ((index, line) in case.array("lines").strings().withIndex()) {
            val cols = line.split(" ~ ")
            val op = cols[0]
            val at = "$id 단계 $index($op)"
            val (ok, preview) = run(editor, op)
            if (ok) {
                accepted += 1
                val kind = preview.substringBefore(':').substringBefore(' ')
                planCounts[kind] = (planCounts[kind] ?: 0) + 1
            }
            assertEquals(cols[1] == "1", ok, "$at 받음")
            assertEquals(cols[2], t.fnv(preview), "$at 미리보기: $preview")
            assertEquals(cols[3], t.fnv(t.core(editor)), "$at 스냅숏: ${t.core(editor)}")
            assertEquals(cols[4], t.fnv(t.extra(editor)), "$at 나머지 읽기: ${t.extra(editor)}")
        }
        return accepted
    }

    @Test
    fun fuzzScriptsMatchSwift() {
        val cases = Golden.load("rummy/turn-editor").cases.filter { "lines" in it }
        assertEquals(100, cases.size)
        val steps = cases.sumOf { it.array("lines").size - 1 }
        val accepted = cases.sumOf { replayLines(it) } - cases.size
        assertTrue(accepted > steps / 3, "받아들인 단계가 너무 적다 — 대본이 규칙을 못 건드린다($accepted/$steps)")
        for (kind in listOf("attach", "insert", "new", "rack")) {
            assertTrue((planCounts[kind] ?: 0) >= 10, "무작위 대본이 '$kind' 계획을 거의 안 밟는다: $planCounts")
        }
    }

    /** 생성기가 망가져 전 단계가 같은 지문이면 대조가 헛돈다. */
    @Test
    fun fuzzFingerprintsMove() {
        val lines = Golden.load("rummy/turn-editor").cases.filter { "lines" in it }.flatMap { it.array("lines").strings() }
        assertNotEquals(1, lines.map { it.split(" ~ ")[3] }.toSet().size)
        assertTrue(lines.map { it.split(" ~ ")[3] }.toSet().size > lines.size / 2, "서로 다른 스냅숏이 너무 적다")
    }
}
