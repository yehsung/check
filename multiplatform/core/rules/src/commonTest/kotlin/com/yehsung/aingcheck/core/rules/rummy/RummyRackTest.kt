// 원본: Tests/checkTests/V0370RummyRackTests.swift:52 @ 1a5eeca6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.wire.json.SwiftJson
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// 아잉 큐브 0.3.70 — 받침대 끼워 넣기 · 랙 묶음 표시(감사 #2 #3). 규칙 단위 시험만 옮겼다(렌더 시험은 화면 단계 몫).

/** 받침대 자리를 그대로 준 편집기. rows = (면, 줄, 반칸). */
private fun r70Editor(rows: List<Triple<String, Int, Int>>, table: List<String> = emptyList(), initialDone: Boolean = true): RummyTurnEditor {
    val entries = rows.map { RummyRackEntry(RummyGoldenText.face(it.first), RummyRackSlot(it.second, it.third)) }
    return RummyTurnEditor(table.map { ef(it) }, entries.map { it.face }, initialDone, rackEntries = entries)
}

private fun r(face: String, row: Int, col: Int) = Triple(face, row, col)

private fun r70ID(editor: RummyTurnEditor, face: String): Int = editor.rack.first { it.face.text == face }.id

/** 받침대 모양 글자("면@줄,반칸" 화면 순). */
private fun r70Shape(editor: RummyTurnEditor): List<String> {
    val layout = editor.rackLayout
    return editor.rack.map { tile -> layout.slot(tile.id)!!.let { "${tile.face.text}@${it.row},${it.halfCol}" } }
}

private fun r70Invariants(editor: RummyTurnEditor, count: Int): List<String> {
    val bad = ArrayList<String>()
    val layout = editor.rackLayout
    if (editor.rack.size != count || layout.slots.size != count) bad.add("타일 수 ${layout.slots.size} ≠ $count")
    if (editor.rack.map { it.id } != layout.readingOrder) bad.add("화면 순서 ≠ 자리")
    for ((id, slot) in layout.slots) {
        if (slot.halfCol < 0 || slot.halfCol + RummyRackLayout.tileSpan > RummyRackLayout.halfColumnsPerRow || slot.row < 0) bad.add("줄 밖 $id $slot")
        for ((other, o) in layout.slots) {
            if (other > id && o.row == slot.row && abs(o.halfCol - slot.halfCol) < RummyRackLayout.tileSpan) bad.add("겹침 $id·$other")
        }
    }
    return bad
}

private fun slot(row: Int, col: Int) = RummyDropTarget.RackSlot(RummyRackSlot(row, col))

class RummyRackTest {
    /** 저장 모양은 Swift 합성 Codable 과 같다(면은 글자 · 자리는 row/halfCol) — 스토어 단계가 판마다 로컬에 쓴다. 면이 와이어 타입이라 SwiftJson 으로만 읽는다. */
    @Test
    fun rackEntryStoresLikeSwiftCodable() {
        val entry = RummyRackEntry(RummyGoldenText.face("A7"), RummyRackSlot(1, 4))
        val text = SwiftJson.encode(RummyRackEntry.serializer(), entry)
        assertEquals("""{"face":"A7","slot":{"row":1,"halfCol":4}}""", text)
        assertEquals(entry, SwiftJson.decode(RummyRackEntry.serializer(), text))
    }

    @Test
    fun insertsBetweenAttachedTiles() {
        // 없으면: 랙의 5 7 사이에 6 을 놓아도 가장 가까운 빈칸으로 튀어 7 을 먼저 옮겨야 하는 결함(감사 #2)이 초록이 된다.
        val base = r70Editor(listOf(r("A5", 0, 0), r("A7", 0, 2), r("B1", 0, 4), r("A6", 1, 0)))
        val a6 = listOf(r70ID(base, "A6"))
        val between = base.copy()
        assertTrue(between.moveBlock(a6, slot(0, 1)))
        assertEquals(listOf("A5@0,0", "A6@0,2", "A7@0,4", "B1@0,6"), r70Shape(between))
        // 7 위에 놓아도(왼쪽 5 와 닿는다) 5 와 7 사이.
        val onto = base.copy()
        assertTrue(onto.moveBlock(a6, slot(0, 2)))
        assertEquals(r70Shape(between), r70Shape(onto))
        // 맨 앞 타일 위 = 그 앞.
        val front = base.copy()
        assertTrue(front.moveBlock(a6, slot(0, 0)))
        assertEquals(listOf("A6@0,0", "A5@0,2", "A7@0,4", "B1@0,6"), r70Shape(front))
        // 빈칸이면 옛 규칙 그대로(바로 그 자리).
        val free = base.copy()
        assertTrue(free.moveBlock(a6, slot(0, 11)))
        assertEquals(listOf("A5@0,0", "A7@0,2", "B1@0,4", "A6@0,11"), r70Shape(free))
        // 여러 장 한 덩어리도 같은 규칙(순서 그대로).
        val block = r70Editor(listOf(r("A5", 0, 0), r("A8", 0, 2), r("A6", 1, 0), r("A7", 1, 2)))
        assertTrue(block.moveBlock(listOf(r70ID(block, "A6"), r70ID(block, "A7")), slot(0, 1)))
        assertEquals(listOf("A5@0,0", "A6@0,2", "A7@0,4", "A8@0,6"), r70Shape(block))
    }

    @Test
    fun pushKeepsChunksApart() {
        // 없으면: 끼운 덩어리가 옆 덩어리와 붙어 한 덩어리가 되거나(랙 묶음 점수가 사라진다), 밀 필요 없는 먼 타일까지 움직이는 결함이 초록이 된다.
        val editor = r70Editor(listOf(r("A1", 0, 0), r("A2", 0, 2), r("A3", 0, 4), r("B5", 0, 9), r("C7", 0, 13), r("D1", 1, 0), r("D2", 1, 2)))
        assertTrue(editor.moveBlock(listOf(r70ID(editor, "D1")), slot(0, 2)))
        assertEquals(listOf("A1@0,0", "D1@0,2", "A2@0,4", "A3@0,6", "B5@0,9", "C7@0,13"), r70Shape(editor).take(6))
        assertTrue(editor.moveBlock(listOf(r70ID(editor, "D2")), slot(0, 2)))
        assertEquals(listOf("A1@0,0", "D2@0,2", "D1@0,4", "A2@0,6", "A3@0,8", "B5@0,11", "C7@0,14"), r70Shape(editor))

        // A1-A3 | 반 칸 | B9-B11: A3 끝에 닿게 놓으면 왼쪽 덩어리에 붙고 오른쪽은 반 칸 떨어진 채 밀린다.
        val two = r70Editor(listOf(r("A1", 0, 0), r("A2", 0, 2), r("A3", 0, 4), r("B9", 0, 7), r("B10", 0, 9), r("B11", 0, 11), r("A4", 1, 0), r("B8", 1, 4)))
        val left = two.copy()
        assertTrue(left.moveBlock(listOf(r70ID(two, "A4")), slot(0, 6)))
        assertEquals(listOf("A1@0,0", "A2@0,2", "A3@0,4", "A4@0,6", "B9@0,9", "B10@0,11", "B11@0,13"), r70Shape(left).take(7))
        assertEquals(listOf(10, 30), left.rackMelds.map { it.points })
        // 오른쪽 덩어리 첫 타일 자리에 놓으면 그 앞에 붙는다(왼쪽과는 반 칸).
        val right = two.copy()
        assertTrue(right.moveBlock(listOf(r70ID(two, "B8")), slot(0, 7)))
        assertEquals(listOf("A1@0,0", "A2@0,2", "A3@0,4", "B8@0,7", "B9@0,9", "B10@0,11", "B11@0,13"), r70Shape(right).take(7))
        assertEquals(listOf(6, 38), right.rackMelds.map { it.points })
    }

    @Test
    fun overflowFlowsToNextRow() {
        // 없으면: 꽉 찬 줄에 끼우면 타일이 겹치거나 줄 밖으로 나가거나, 덩어리가 두 줄로 찢기는 결함이 초록이 된다.
        val entries = arrayListOf(r("C1", 0, 0), r("C2", 0, 2))
        for (n in 1..13) entries.add(r("A$n", 0, 6 + (n - 1) * 2)) // 6..30, 줄 끝까지
        entries.add(r("D9", 1, 0))
        entries.add(r("B5", 1, 6))
        val editor = r70Editor(entries)
        assertTrue(editor.moveBlock(listOf(r70ID(editor, "B5")), slot(0, 10)))
        val shape = r70Shape(editor)
        assertEquals(listOf("C1@0,0", "C2@0,2"), shape.take(2))
        // A1 A2 B5 A3 … A13 (14장 = 28 반 칸)이 통째로 다음 줄 맨 앞, D9 는 반 칸 떼고 29.
        assertEquals(listOf("A1@1,0", "A2@1,2", "B5@1,4", "A3@1,6"), shape.subList(2, 6))
        assertEquals("D9@1,29", shape.last())
        assertEquals(emptyList(), r70Invariants(editor, 17))

        // 한 줄을 꽉 채운 16장 덩어리에 끼우면 넘친 마지막 한 장만 다음 줄로(덩어리가 한 줄보다 길다).
        val full = ArrayList<Triple<String, Int, Int>>()
        val colors = listOf("A", "B")
        for (i in 0 until 16) full.add(r("${colors[i / 8]}${i % 8 + 1}", 0, i * 2))
        full.add(r("D9", 1, 0))
        full.add(r("C5", 1, 8))
        val packed = r70Editor(full)
        assertTrue(packed.moveBlock(listOf(r70ID(packed, "C5")), slot(0, 4)))
        val packedShape = r70Shape(packed)
        assertEquals("C5@0,4", packedShape[2])
        assertEquals("B7@0,30", packedShape[15])
        assertEquals("B8@1,0", packedShape[16])
        assertEquals("D9@1,3", packedShape[17])
        assertEquals(emptyList(), r70Invariants(packed, 18))
    }

    @Test
    fun insertFuzz() {
        // 없으면: 드문 자리(줄 끝 · 3줄째 · 덩어리 경계)에서 타일이 사라지거나 포개지는 결함이 초록이 된다. 무작위 놓기 3,000번.
        var seed = 0x70370000uL
        fun next(upper: Int): Int {
            seed = seed * 6364136223846793005uL + 1442695040888963407uL
            return ((seed shr 33) % upper.toULong()).toInt()
        }
        val faces = listOf(
            "A1", "A2", "A3", "A4", "A5", "B1", "B2", "B3", "B4", "C7", "C8", "C9", "D10", "D11", "D12", "J",
            "A9", "B9", "C9", "D9", "A13", "B13", "C13", "D1", "D2", "D3", "A6", "B6",
        )
        val bad = ArrayList<String>()
        for (round in 0 until 60) {
            val count = 8 + next(faces.size - 8)
            val editor = RummyTurnEditor(emptyList(), faces.take(count).map { RummyGoldenText.face(it) }, true)
            for (step in 0 until 50) {
                val ids = editor.rack.map { it.id }
                val start = next(ids.size)
                val length = minOf(1 + next(3), ids.size - start)
                val moving = ids.subList(start, start + length).toList()
                val target = RummyRackSlot(next(3), next(31))
                val preview = editor.rackLayoutAfterDrop(moving, target)
                val others = editor.rack.map { it.id }.filter { it !in moving }
                if (!editor.moveBlock(moving, RummyDropTarget.RackSlot(target))) bad.add("거절 $round/$step")
                if (preview != editor.rackLayout) bad.add("미리보기 ≠ 실제 $round/$step")
                if (editor.rack.map { it.id }.filter { it !in moving } != others) bad.add("순서 바뀜 $round/$step")
                bad += r70Invariants(editor, count).map { "$it $round/$step" }
                if (bad.size > 5) break
            }
        }
        assertEquals(emptyList(), bad.take(5))
    }

    @Test
    fun rackMeldsCountOnlyWhatIMade() {
        // 없으면: 붙여 둔 묶음이 맞는지 판에 꺼내 봐야 알거나(감사 #3), 반대로 화면이 정답 묶음을 찾아 주는 힌트가 되는 결함이 초록이 된다.
        val editor = r70Editor(
            listOf(
                r("A7", 0, 0), r("A8", 0, 2), r("A9", 0, 4), // 런 24
                r("B10", 0, 7), r("C10", 0, 9), r("D10", 0, 11), // 그룹 30
                r("B2", 0, 14), r("B4", 0, 16), // 2장 — 아님
                r("J", 0, 19), r("D5", 0, 21), r("D6", 0, 23), // 조커 런 — 점수는 서버 R-08 그대로(5-6-7 = 18)
                r("C1", 1, 0), r("C2", 1, 2), r("C3", 1, 4), r("C9", 1, 6), // 이어 붙였지만 덩어리 전체는 아님 — 쪼개 보지 않는다
                r("A11", 1, 10), r("A12", 1, 13), r("A13", 1, 15), // 반 칸 끊김 — 아님
            ),
        )
        assertEquals(listOf(24, 30, 18), editor.rackMelds.map { it.points })
        assertEquals(listOf(RummyMeldKind.run, RummyMeldKind.group, RummyMeldKind.run), editor.rackMelds.map { it.kind })
        assertEquals(72, editor.rackMeldPoints)
        assertEquals(listOf(r70ID(editor, "A7"), r70ID(editor, "A8"), r70ID(editor, "A9")), editor.rackMelds[0].tileIDs)
        assertNull(editor.initialPlanPoints) // 첫 등록 뒤엔 안 보인다
    }

    @Test
    fun initialPlanCombinesTableAndRack() {
        // 없으면: 랙 묶음을 판에 내려놓을수록 '랙 묶음 합'이 줄어 30 에 가까운지 거꾸로 읽히는 결함이 초록이 된다.
        val editor = r70Editor(
            listOf(r("A7", 0, 0), r("A8", 0, 2), r("A9", 0, 4), r("B10", 0, 7), r("C10", 0, 9), r("D10", 0, 11), r("B2", 1, 0)),
            table = listOf("C3 C4 C5"),
            initialDone = false,
        )
        val before = assertNotNull(editor.initialPlanPoints)
        assertEquals(RummyInitialPlan(0, 54), before)
        val group = listOf(r70ID(editor, "B10"), r70ID(editor, "C10"), r70ID(editor, "D10"))
        assertTrue(editor.moveBlock(group, RummyDropTarget.NewMeldAt(ep(400, 300))))
        val after = assertNotNull(editor.initialPlanPoints)
        assertEquals(RummyInitialPlan(30, 24), after)
        assertEquals(before.table + before.rack, after.table + after.rack)
        // 판의 무효 묶음은 0점(진행 막대와 같다).
        assertTrue(editor.moveBlock(listOf(r70ID(editor, "B2")), RummyDropTarget.NewMeldAt(ep(700, 500))))
        assertEquals(30, editor.initialPlanPoints?.table)
    }
}
