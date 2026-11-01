// 원본: 없음 — ios-1017 설계서 §2 "받침대 폭 매개변수화" 의 성질 시험(22 에서 겹침 없음 · 셋째 줄 · 저장-복원 · 폭 밖 항목 재배치 · 32 동작 불변) + 폰 받침대 기하.
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.wire.games.RummyFace
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

private const val PHONE = RummyRackGeometry.phoneHalfColumns

/** 서로 다른 면 [count] 장(A1…A13 · B1…). */
private fun faces(count: Int): List<RummyFace> = (0 until count).map { n ->
    RummyGoldenText.face("${"ABCD"[n / 13]}${n % 13 + 1}")
}

private fun phoneEditor(rack: List<RummyFace>, entries: List<RummyRackEntry>? = null) =
    RummyTurnEditor(emptyList(), rack, initialDone = true, rackEntries = entries, rackHalfColumns = PHONE)

/** 줄 밖 · 겹침 · 화면 순서 어긋남을 글자로 모은다. */
private fun violations(editor: RummyTurnEditor, count: Int, width: Int = PHONE): List<String> {
    val bad = ArrayList<String>()
    val layout = editor.rackLayout
    if (editor.rack.size != count || layout.slots.size != count) bad.add("타일 수 ${layout.slots.size} ≠ $count")
    if (editor.rack.map { it.id } != layout.readingOrder) bad.add("화면 순서 ≠ 자리")
    for ((id, slot) in layout.slots) {
        if (slot.row < 0 || slot.halfCol < 0 || slot.halfCol + RummyRackLayout.tileSpan > width) bad.add("줄 밖 $id $slot")
        for ((other, o) in layout.slots) {
            if (other > id && o.row == slot.row && abs(o.halfCol - slot.halfCol) < RummyRackLayout.tileSpan) bad.add("겹침 $id·$other")
        }
    }
    return bad
}

class RummyPhoneRackTest {
    @Test
    fun widthIsCarriedThroughEveryCopy() {
        // 없으면: 복제·미리보기·정렬 어딘가에서 폭이 32 로 돌아가 12장째가 화면 밖에 놓이는 결함이 초록이 된다.
        val editor = phoneEditor(faces(14))
        assertEquals(PHONE, editor.rackHalfColumns)
        assertEquals(PHONE, editor.rackLayout.halfColumns)
        assertEquals(PHONE, editor.copy().rackHalfColumns)
        assertEquals(PHONE, editor.rackLayoutAfterDrop(listOf(editor.rack[0].id), RummyRackSlot(1, 0))?.halfColumns)
        val sorted = editor.copy()
        sorted.sortRack(RummyRackSort.color)
        assertEquals(PHONE, sorted.rackHalfColumns)
        assertEquals(RummyRackLayout.halfColumnsPerRow, RummyTurnEditor(emptyList(), faces(3), initialDone = true).rackHalfColumns)
    }

    @Test
    fun packsElevenToARow() {
        for (count in listOf(1, 11, 14, 22, 23, 33, 34)) {
            val editor = phoneEditor(faces(count))
            assertEquals(emptyList(), violations(editor, count), "$count 장")
        }
        // ★ 기준선: 22장은 두 줄에 들고 23장부터 셋째 줄이 열린다. 폭이 32 면 16장씩이라 이 값이 달라진다.
        assertEquals(2, phoneEditor(faces(22)).rackLayout.rowCount)
        assertEquals(3, phoneEditor(faces(23)).rackLayout.rowCount)
        assertEquals(2, RummyTurnEditor(emptyList(), faces(32), initialDone = true).rackLayout.rowCount)
        assertEquals(RummyRackSlot(1, 0), phoneEditor(faces(12)).let { it.rackLayout.slot(it.rack[11].id) })
    }

    @Test
    fun sortWrapsAtTheNarrowWidth() {
        // 없으면: 정렬(조합 사이 반 칸)이 맥 폭으로 줄을 바꿔 폰에서 타일이 줄 밖으로 나간다.
        for (count in listOf(14, 21, 30, 40)) {
            for (mode in RummyRackSort.entries) {
                val editor = phoneEditor(faces(count))
                editor.sortRack(mode)
                assertEquals(emptyList(), violations(editor, count), "$count 장 $mode")
            }
        }
    }

    @Test
    fun savedEntriesRestoreInPlace() {
        val editor = phoneEditor(faces(13))
        assertTrue(editor.moveBlock(listOf(editor.rack[0].id), RummyDropTarget.RackSlot(RummyRackSlot(1, 15))))
        val restored = phoneEditor(faces(13), editor.rackEntries)
        assertEquals(editor.rackEntries, restored.rackEntries)
        assertEquals(emptyList(), violations(restored, 13))
    }

    @Test
    fun entriesOutsideTheWidthMoveToNearestFree() {
        // 맥 판을 폰에서 이어 받았다 — 저장 자리가 폭 22 밖이다. 없으면: 타일이 화면 밖에 놓여 집을 수 없다.
        val rack = faces(16)
        val entries = rack.mapIndexed { i, face -> RummyRackEntry(face, RummyRackSlot(0, i * 2)) }
        val editor = phoneEditor(rack, entries)
        assertEquals(emptyList(), violations(editor, 16))
        // 폭 안 자리는 제자리다.
        assertEquals(RummyRackSlot(0, 20), editor.rackLayout.slot(editor.rack.first { it.face == rack[10] }.id))
        // ★ 기준선: 맥 폭이면 그 자리 그대로다.
        val mac = RummyTurnEditor(emptyList(), rack, initialDone = true, rackEntries = entries)
        assertEquals(RummyRackSlot(0, 30), mac.rackLayout.slot(mac.rack.first { it.face == rack[15] }.id))
    }

    @Test
    fun insertFlowsOverAtTheNarrowWidth() {
        val editor = phoneEditor(faces(12))
        assertEquals(1, editor.rackLayout.slot(editor.rack[11].id)?.row)
        // 꽉 찬 첫 줄 가운데에 끼우면 넘친 타일이 다음 줄로 흐른다(잃거나 겹치지 않는다).
        assertTrue(editor.moveBlock(listOf(editor.rack[11].id), RummyDropTarget.RackSlot(RummyRackSlot(0, 4))))
        assertEquals(emptyList(), violations(editor, 12))
        assertEquals(2, editor.rackLayout.rowCount)
    }

    @Test
    fun defaultWidthBehavesAsBefore() {
        // 맥 골든(rummy/rack-layout)이 재는 값 — 인자를 안 넘긴 길이 전과 같아야 한다.
        assertEquals(32, RummyRackLayout.halfColumnsPerRow)
        assertEquals(32, RummyRackLayout().halfColumns)
        assertEquals(RummyRackSlot(1, 0), RummyRackLayout.packed((0 until 17).toList()).slot(16))
        assertEquals(RummyRackSlot(1, 0), RummyRackLayout.packed((0 until 12).toList(), PHONE).slot(11))
        assertEquals(RummyRackSlot(0, 3), RummyRackLayout.grouped(listOf(listOf(0), listOf(1))).slot(1))
        assertEquals(RummyRackLayout.grouped(listOf(listOf(0))), RummyRackLayout.grouped(listOf(listOf(0))))
        assertTrue(RummyRackLayout.grouped(listOf(listOf(0))) != RummyRackLayout.grouped(listOf(listOf(0)), halfColumns = PHONE))
    }

    @Test
    fun phoneGeometryFitsEveryWidth() {
        for (width in listOf(320.0, 360.0, 393.0, 430.0)) {
            for (rows in 2..5) {
                val g = RummyRackGeometry.phone(width, rows)
                assertEquals(PHONE, g.halfColumns)
                for (row in 0 until rows) {
                    for (half in 0..(PHONE - RummyRackLayout.tileSpan)) {
                        val frame = g.frame(RummyRackSlot(row, half))
                        assertTrue(frame.x >= 0.0 && frame.maxX <= width + 0.001, "$width·$rows: 가로 밖 $frame")
                        assertTrue(frame.y >= 0.0 && frame.maxY <= g.height + 0.001, "$width·$rows: 세로 밖 $frame (높이 ${g.height})")
                        // 왕복: 그린 자리를 누르면 그 자리다.
                        assertEquals(RummyRackSlot(row, half), g.slot(frame.x, frame.midY, 1), "$width·$rows")
                    }
                }
                // 줄끼리 안 겹친다.
                for (row in 1 until rows) {
                    assertTrue(g.frame(RummyRackSlot(row, 0)).y >= g.frame(RummyRackSlot(row - 1, 0)).maxY, "$width·$rows")
                }
            }
        }
    }

    @Test
    fun phoneGeometryMatchesTheSpecHeights() {
        val two = RummyRackGeometry.phone(393.0, 2)
        assertEquals(34.0, two.tileSize.width)
        assertEquals(47.0, two.tileSize.height)
        assertEquals(118.0, two.height)
        val three = RummyRackGeometry.phone(393.0, 3)
        assertEquals(47.0, three.tileSize.height, "셋째 줄까지는 타일을 안 줄인다")
        assertEquals(165.0, three.height)
        val four = RummyRackGeometry.phone(393.0, 4)
        assertEquals(47.0 * 3 / 4, four.tileSize.height)
        // 좁은 폭은 타일을 비율대로 줄인다(받침대가 화면을 넘지 않게).
        assertTrue(RummyRackGeometry.phone(320.0).tileSize.width < 34.0)
    }

    @Test
    fun dropResolverSpeaksPhoneSlots() {
        val width = 393.0
        val rack = RummyRackGeometry.phone(width)
        val regions = RummyMatchRegions(
            rack = RummyCanvasRect(0.0, 500.0, width, rack.height),
            table = RummyCanvasRect(0.0, 40.0, width, 450.0),
        )
        val frame = rack.frame(RummyRackSlot(1, 6))
        val pointer = RummyCanvasPoint(frame.midX, regions.rack.y + frame.midY)
        val target = RummyDropResolver.target(pointer, 0, 1, regions, RummyCanvasTransform.fit(RummyCanvasSize(width, 450.0)), RummyTableLayout.empty, rack, isMyTurn = false)
        assertEquals(RummyDropTarget.RackSlot(RummyRackSlot(1, 6)), target)
        // 줄 끝을 넘겨 놓아도 11장째 자리로 잘린다(맥 폭이면 화면 밖 반 칸이 나온다).
        assertEquals(RummyRackSlot(0, PHONE - 2), rack.slot(width, rack.rowCenter(0), 1))
    }

    @Test
    fun motionKeysSurviveNewIDs() {
        val a7 = RummyGoldenText.face("A7")
        val keys = RummyRackGeometry.motionKeys(listOf(RummyTile(9, a7), RummyTile(4, a7), RummyTile(5, RummyFace.joker)))
        assertEquals(mapOf(4 to "A7#0", 9 to "A7#1", 5 to "J#0"), keys)
    }
}
