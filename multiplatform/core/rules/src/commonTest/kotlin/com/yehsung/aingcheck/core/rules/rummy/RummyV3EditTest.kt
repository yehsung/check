// 원본: Tests/checkTests/V0369RummyV3EditTests.swift:42 @ 1a5eeca6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyLayout
import com.yehsung.aingcheck.core.wire.games.RummyPoint
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

// 아잉 큐브 3판(K3) — 판 편집 손맛 규칙. 사용자 원문(0.3.69 실플레이): "7장 연속으로 있는데 중간꺼 뺐으면 양옆으로 3장씩 이어진 상태 남아있어야지 ·
// 어느정도 가까이 배치하면 이어지는것들은 자동으로 붙게 · 붙을 수 있는 조합에 카드 추가할 땐 알맞는 위치로 자동으로".

private fun eEditor(sets: List<String>, at: List<RummyPoint>, rack: String = ""): RummyTurnEditor =
    RummyTurnEditor(sets.map { ef(it) }, ef(rack), true, tableLayout = RummyLayout(at))

private fun eRack(editor: RummyTurnEditor, text: String): Int = editor.rack.first { it.face.text == text }.id

private fun eTable(editor: RummyTurnEditor, text: String): Int = editor.melds.flatten().first { it.face.text == text }.id

/** 판 위 타일의 화면 왼쪽 위(묶음 점 + 자리 × 타일폭). */
private fun eSpot(editor: RummyTurnEditor, id: Int): RummyPoint? {
    editor.melds.forEachIndexed { set, meld ->
        val index = meld.indexOfFirst { it.id == id }
        if (index >= 0) return ep(editor.points[set].x + index * RummyTableLayout.tileWidth, editor.points[set].y)
    }
    return null
}

private fun eTexts(editor: RummyTurnEditor): List<String> = editor.submissionTable.map { RummyGoldenText.text(it) }

private fun at(x: Long, y: Long) = RummyDropTarget.NewMeldAt(ep(x, y))

/** 가운데 빼면 양쪽 유지(규칙 ①). */
class RummyV3SplitTest {
    @Test
    fun splitPure() {
        // 없으면: 가운데를 뺀 뒤 오른 토막이 왼쪽으로 당겨져(타일이 튄다) 사용자가 "중간만 분리" 를 못 보는 결함이 초록이 된다.
        val point = ep(100, 200)
        assertEquals(listOf(RummySplitPiece(0 until 3, ep(100, 200)), RummySplitPiece(4 until 7, ep(260, 200))), RummyTableEdit.split(7, point, setOf(3)))
        assertEquals(listOf(RummySplitPiece(0 until 6, point)), RummyTableEdit.split(7, point, setOf(6)))
        assertEquals(listOf(RummySplitPiece(1 until 7, ep(140, 200))), RummyTableEdit.split(7, point, setOf(0)))
        assertEquals(listOf(0 until 1, 2 until 4, 5 until 7), RummyTableEdit.split(7, point, setOf(1, 4)).map { it.range })
        assertTrue(RummyTableEdit.split(3, point, setOf(0, 1, 2)).isEmpty())
        assertEquals(listOf(RummySplitPiece(0 until 3, point)), RummyTableEdit.split(3, point, emptySet()))
    }

    @Test
    fun sevenRunMiddle() {
        // 없으면: 가운데를 빼면 나머지 여섯 장이 한 묶음(무효)으로 붙어 남는 0.3.69 결함이 초록이 된다.
        val editor = eEditor(listOf("A1 A2 A3 A4 A5 A6 A7"), listOf(ep(100, 200)))
        val before = editor.melds[0].map { it.id to eSpot(editor, it.id) }
        val a4 = eTable(editor, "A4")
        assertTrue(editor.moveBlock(listOf(a4), at(600, 500)))
        assertEquals(listOf("A1 A2 A3", "A5 A6 A7", "A4"), eTexts(editor))
        assertEquals(ep(100, 200), editor.points[0])
        assertEquals(ep(260, 200), editor.points[1])
        assertTrue(editor.analysis(0).valid && editor.analysis(1).valid)
        for ((id, spot) in before) if (id != a4) assertEquals(spot, eSpot(editor, id), "타일 $id 가 움직였다")
        // 판 출신은 쪼갠 뒤에도 랙으로 못 간다(R-14).
        assertFalse(editor.canMoveBlock(listOf(a4), RummyDropTarget.Rack(null)))
        assertNull(editor.previewDrop(listOf(eTable(editor, "A2")), RummyDropTarget.RackSlot(RummyRackSlot(0, 0))))
    }

    @Test
    fun endRemoval() {
        // 없으면: 왼끝을 빼면 남은 묶음이 왼쪽으로 한 칸 당겨져 타일이 튀는 결함이 초록이 된다.
        val editor = eEditor(listOf("A1 A2 A3 A4 A5 A6 A7"), listOf(ep(100, 200)))
        assertTrue(editor.moveBlock(listOf(eTable(editor, "A7")), at(600, 500)))
        assertEquals(listOf("A1 A2 A3 A4 A5 A6", "A7"), eTexts(editor))
        assertEquals(ep(100, 200), editor.points[0])
        assertTrue(editor.moveBlock(listOf(eTable(editor, "A1")), at(600, 400)))
        assertEquals(listOf("A2 A3 A4 A5 A6", "A7", "A1"), eTexts(editor))
        assertEquals(ep(140, 200), editor.points[0])
    }

    @Test
    fun groupJokerAndMulti() {
        // 없으면: 그룹이나 조커 런에서만 규칙이 달라(한 덩어리로 남거나 조커가 엉뚱한 토막으로) 판이 깨지는 결함이 초록이 된다.
        val group = eEditor(listOf("A5 B5 C5 D5"), listOf(ep(100, 100)))
        assertTrue(group.moveBlock(listOf(eTable(group, "B5")), at(600, 500)))
        assertEquals(listOf("A5", "C5 D5", "B5"), eTexts(group))
        assertEquals(ep(180, 100), group.points[1])

        val joker = eEditor(listOf("A3 J A5 A6 A7 A8 A9"), listOf(ep(40, 300)))
        assertEquals(listOf("A3", "J", "A5", "A6", "A7", "A8", "A9"), joker.melds[0].map { it.face.text })
        assertTrue(joker.moveBlock(listOf(eTable(joker, "A6")), at(600, 500)))
        assertEquals(listOf("A3 J A5", "A7 A8 A9", "A6"), eTexts(joker))
        assertTrue(joker.analysis(0).valid && joker.analysis(1).valid)
        assertEquals(ep(40 + 4 * 40, 300), joker.points[1])

        val multi = eEditor(listOf("B1 B2 B3 B4 B5 B6 B7 B8"), listOf(ep(0, 0)))
        assertTrue(multi.moveBlock(listOf(eTable(multi, "B3"), eTable(multi, "B6")), at(500, 500)))
        assertEquals(listOf("B1 B2", "B4 B5", "B7 B8", "B3 B6"), eTexts(multi))
        assertEquals(listOf(ep(0, 0), ep(120, 0), ep(240, 0)), multi.points.take(3))
    }

    @Test
    fun rackTileOutOfMiddleAndReset() {
        // 없으면: 내 타일을 거둘 때 남은 판 묶음이 한 덩어리로 붙어 남거나, 되돌리기가 쪼갠 판을 못 되돌리는 결함이 초록이 된다.
        val fresh = eEditor(listOf("A1 A2 A3", "A5 A6 A7"), listOf(ep(100, 200), ep(300, 200)), "A4 B9")
        val editor = fresh.copy()
        val a4 = eRack(editor, "A4")
        assertTrue(editor.moveBlock(listOf(a4), RummyDropTarget.Meld(0, null)))
        assertTrue(editor.moveSet(1, ep(260, 200))) // A1-A4 오른끝(260)에 닿는다 → 합친다
        assertEquals(listOf("A1 A2 A3 A4 A5 A6 A7"), eTexts(editor))
        assertEquals(listOf(ep(100, 200)), editor.points)
        val undone = editor.copy()
        undone.reset()
        assertEquals(fresh, undone)
        assertTrue(editor.moveBlock(listOf(a4), RummyDropTarget.Rack(null)))
        assertEquals(listOf("A1 A2 A3", "A5 A6 A7"), eTexts(editor))
        assertEquals(listOf(ep(100, 200), ep(260, 200)), editor.points)
        assertFalse(editor.isChanged)
        assertTrue(editor.isLayoutChanged)
        editor.reset()
        assertEquals(fresh.melds, editor.melds)
        assertEquals(fresh.points, editor.points)
        assertEquals(2, editor.rackFaces.size)
    }
}

/** 가까이 놓으면 붙기(규칙 ②). */
class RummyV3AttachTest {
    @Test
    fun attachRightLeftAndThresholds() {
        // 없으면: 묶음 끝 가까이 놓은 타일이 따로 놀아 손으로 정확히 겨눠야만 붙는 0.3.69 손맛이 초록이 된다.
        assertEquals(24, RummyTableEdit.attachGap)
        assertEquals(28, RummyTableEdit.attachRise)
        val base = eEditor(listOf("A2 A3 A4"), listOf(ep(200, 200)), "A1 A5 B9")
        val right = base.copy()
        assertEquals(RummyDropPlan.Attach(0, RummyAttachSide.right), right.previewDrop(listOf(eRack(right, "A5")), at(344, 228))?.plan)
        assertTrue(right.moveBlock(listOf(eRack(right, "A5")), at(344, 228))) // 간격 24 · 세로 28
        assertEquals(listOf("A2 A3 A4 A5"), eTexts(right))
        assertEquals(listOf(ep(200, 200)), right.points)

        val left = base.copy()
        assertTrue(left.moveBlock(listOf(eRack(left, "A1")), at(140, 190))) // 왼끝 간격 20
        assertEquals(listOf("A1 A2 A3 A4"), eTexts(left))
        assertEquals(listOf(ep(160, 200)), left.points)

        val far = base.copy()
        assertNotEquals(RummyDropPlan.Attach(0, RummyAttachSide.right), far.previewDrop(listOf(eRack(far, "A5")), at(345, 200))?.plan)
        assertTrue(far.moveBlock(listOf(eRack(far, "A5")), at(320, 229))) // 세로 29 → 안 붙는다
        assertEquals(listOf("A2 A3 A4", "A5"), eTexts(far))

        val mismatch = base.copy()
        val preview = mismatch.previewDrop(listOf(eRack(mismatch, "B9")), at(330, 200))
        assertTrue(mismatch.moveBlock(listOf(eRack(mismatch, "B9")), at(330, 200)))
        assertEquals(listOf("A2 A3 A4", "B9"), eTexts(mismatch))
        assertEquals(RummyDropPlan.NewSet(mismatch.points[1]), preview?.plan)
        assertEquals(mismatch.tableLayout.frame(1), preview?.landing?.frame)
        assertTrue(mismatch.tableLayout.frames[0].maxX + RummyTableLayout.clearance <= mismatch.points[1].x)
    }

    @Test
    fun closerSideAndGapFill() {
        // 없으면: 두 묶음 사이에 놓은 타일이 먼 쪽에 붙거나, 구멍을 메워도 세 조각으로 남는 결함이 초록이 된다.
        val base = eEditor(listOf("A2 A3 A4", "B5 C5 D5"), listOf(ep(100, 200), ep(290, 200)), "A5")
        val nearRun = base.copy()
        assertTrue(nearRun.moveBlock(listOf(eRack(nearRun, "A5")), at(230, 200))) // 런 10 · 그룹 20
        assertEquals(listOf("A2 A3 A4 A5", "B5 C5 D5"), eTexts(nearRun))
        val nearGroup = base.copy()
        assertEquals(RummyDropPlan.Attach(1, RummyAttachSide.left), nearGroup.previewDrop(listOf(eRack(nearGroup, "A5")), at(238, 200))?.plan)
        assertTrue(nearGroup.moveBlock(listOf(eRack(nearGroup, "A5")), at(238, 200))) // 런 18 · 그룹 12
        assertEquals(listOf("A2 A3 A4", "A5 B5 C5 D5"), eTexts(nearGroup))
        assertEquals(ep(250, 200), nearGroup.points[1])

        // 7장 런 가운데를 뺐다가 그 구멍에 도로 놓으면 다시 한 묶음.
        val hole = eEditor(listOf("A1 A2 A3 A4 A5 A6 A7"), listOf(ep(100, 200)))
        val a4 = eTable(hole, "A4")
        assertTrue(hole.moveBlock(listOf(a4), at(600, 500)))
        val preview = hole.previewDrop(listOf(a4), at(220, 204))
        assertEquals(listOf("A1", "A2", "A3", "A4", "A5", "A6", "A7"), preview?.landing?.faces?.map { it.text })
        assertEquals(true, preview?.landing?.valid)
        assertEquals(3, preview?.landing?.blockStart)
        assertTrue(hole.moveBlock(listOf(a4), at(220, 204)))
        assertEquals(listOf("A1 A2 A3 A4 A5 A6 A7"), eTexts(hole))
        assertEquals(listOf(ep(100, 200)), hole.points)
        assertFalse(hole.isChanged)
    }

    @Test
    fun moveSetAndBlockAttach() {
        // 없으면: 묶음째 끌어 런 끝에 갖다 대도 두 묶음으로 남아 하나씩 다시 옮겨야 하는 결함이 초록이 된다.
        val editor = eEditor(listOf("A1 A2 A3", "A4 A5", "C9 D9 B9"), listOf(ep(100, 200), ep(500, 400), ep(600, 100)))
        val preview = editor.previewMoveSet(1, ep(235, 205))
        assertEquals(RummyDropPlan.Attach(0, RummyAttachSide.right), preview?.plan)
        assertTrue(editor.moveSet(1, ep(235, 205)))
        assertEquals(listOf("A1 A2 A3 A4 A5", "B9 C9 D9"), eTexts(editor))
        assertEquals(ep(100, 200), editor.points[0])
        assertEquals(editor.tableLayout.frame(0), preview?.landing?.frame)
        // 그룹 묶음을 런 끝에 대면 안 이어진다 → 위치 이동만(스냅).
        assertTrue(editor.moveSet(1, ep(310, 200)))
        assertEquals(2, editor.melds.size)
        assertTrue(editor.tableLayout.frames[0].maxX + RummyTableLayout.clearance <= editor.points[1].x)

        val block = eEditor(listOf("A3 A4 A5"), listOf(ep(400, 300)), "A1 A2 B7")
        val ids = block.rackChain(eRack(block, "A1"))
        assertEquals(2, ids.size)
        assertTrue(block.moveBlock(ids, at(310, 296)))
        assertEquals(listOf("A1 A2 A3 A4 A5"), eTexts(block))
        assertEquals(listOf(ep(320, 300)), block.points)
    }
}

/** 알맞은 자리에 자동 삽입(규칙 ③). */
class RummyV3InsertTest {
    private fun ix(block: String, meld: String, preferred: Int) = RummyTableEdit.insertionIndex(ef(block), ef(meld), preferred)

    @Test
    fun insertionPure() {
        // 없으면: 6-7-8 위에 놓은 5 가 놓은 자리(뒤)에 꽂혀 무효 묶음이 되는 0.3.69 손맛이 초록이 된다.
        assertEquals(RummyInsertion(0, true), ix("A5", "A6 A7 A8", 3))
        assertEquals(RummyInsertion(3, true), ix("A9", "A6 A7 A8", 0))
        assertEquals(2, ix("A8", "A6 A7 J", 3).index) // J 가 9 로 밀린다
        assertEquals(3, ix("A8", "A5 J A7", 0).index)
        assertEquals(0, ix("J", "A5 A6 A7", 0).index) // 둘 다 맞으면 놓은 쪽
        assertEquals(3, ix("J", "A5 A6 A7", 2).index)
        assertEquals(3, ix("A9 A10", "A6 A7 A8", 0).index)
        assertEquals(RummyInsertion(3, true), ix("D5", "A5 B5 C5", 0))
        assertEquals(RummyInsertion(1, false), ix("B2", "A6 A7 A8", 1))
        assertEquals(RummyInsertion(0, true), ix("A5", "", 9))
    }

    @Test
    fun editorFrontAndBack() {
        // 없으면: 앞에 꽂힌 타일이 기존 타일을 오른쪽으로 밀어내 묶음이 들썩이는 결함이 초록이 된다.
        val editor = eEditor(listOf("A6 A7 A8"), listOf(ep(300, 200)), "A5 A9 B2")
        val plan = editor.previewDrop(listOf(eRack(editor, "A5")), RummyDropTarget.Meld(0, 3))
        assertEquals(RummyDropPlan.Insert(0, 0), plan?.plan)
        assertEquals(0, plan?.landing?.blockStart)
        assertEquals(true, plan?.landing?.valid)
        assertTrue(editor.moveBlock(listOf(eRack(editor, "A5")), RummyDropTarget.Meld(0, 3)))
        assertEquals(listOf("A5 A6 A7 A8"), eTexts(editor))
        assertEquals(listOf(ep(260, 200)), editor.points)
        assertTrue(editor.moveBlock(listOf(eRack(editor, "A9")), RummyDropTarget.Meld(0, 0)))
        assertEquals(listOf("A5 A6 A7 A8 A9"), eTexts(editor))
        assertEquals(listOf(ep(260, 200)), editor.points)
        // 맞는 자리가 없으면 놓은 자리(무효 표시는 판정 몫).
        assertTrue(editor.moveBlock(listOf(eRack(editor, "B2")), RummyDropTarget.Meld(0, 2)))
        assertEquals(listOf("A5 A6 B2 A7 A8 A9"), eTexts(editor))
        assertFalse(editor.analysis(0).valid)
    }

    @Test
    fun jokerGroupAndEdge() {
        // 없으면: 조커가 메우는 숫자를 무시해 엉뚱한 자리에 꽂히거나, 그룹 오른끝에 꽂혀 확정 뒤 서버 표시 순서(R-09)로 타일이 튀는 결함이 초록이 된다.
        val joker = eEditor(listOf("A6 A7 J"), listOf(ep(300, 200)), "A8")
        assertEquals(listOf("A6", "A7", "J"), joker.melds[0].map { it.face.text })
        assertTrue(joker.moveBlock(listOf(eRack(joker, "A8")), RummyDropTarget.Meld(0, 3)))
        assertEquals(listOf("A6 A7 A8 J"), eTexts(joker))
        assertTrue(joker.analysis(0).valid)

        val group = eEditor(listOf("A5 B5 D5"), listOf(ep(300, 200)), "C5")
        assertTrue(group.moveBlock(listOf(eRack(group, "C5")), RummyDropTarget.Meld(0, 0)))
        assertEquals(listOf("A5 B5 C5 D5"), eTexts(group))
        assertEquals(listOf(ep(300, 200)), group.points)
        assertTrue(group.analysis(0).valid)

        val edge = eEditor(listOf("A6 A7 A8"), listOf(ep(0, 0)), "A5")
        assertTrue(edge.moveBlock(listOf(eRack(edge, "A5")), RummyDropTarget.Meld(0, null)))
        assertEquals(listOf("A5 A6 A7 A8"), eTexts(edge))
        assertTrue(RummyTableLayout.fits(edge.tableLayout.frames[0]))
    }

    @Test
    fun insertGrowthAttachesOnlyOnGrownSide() {
        // 없으면: 조커를 빼낸 구멍에 7 을 [6] 위로 놓으면 [6 7] 이 [8] 과 겹쳐 엉뚱한 곳으로 튀거나, 따로 둔 묶음이 곁 런과 멋대로 합쳐진다.
        val hole = eEditor(listOf("A6 J A8"), listOf(ep(200, 200)), "A7")
        assertTrue(hole.moveBlock(listOf(eTable(hole, "J")), at(600, 500)))
        assertEquals(listOf("A6", "A8", "J"), eTexts(hole))
        assertTrue(hole.moveBlock(listOf(eRack(hole, "A7")), RummyDropTarget.Meld(0, null)))
        assertEquals(listOf("A6 A7 A8", "J"), eTexts(hole))
        assertEquals(ep(200, 200), hole.points[0])

        val apart = eEditor(listOf("A1 A2 A3", "A4"), listOf(ep(0, 0), ep(136, 0)), "A5")
        assertTrue(apart.moveBlock(listOf(eRack(apart, "A5")), RummyDropTarget.Meld(1, null)))
        assertEquals(listOf("A1 A2 A3", "A4 A5"), eTexts(apart))
        assertEquals(listOf(ep(0, 0), ep(136, 0)), apart.points)
    }
}

/** 결정성 · 미리보기 = 실제. */
class RummyV3DeterminismTest {
    @Test
    fun deterministicAndPreviewMatches() {
        // 없으면: 미리보기가 그린 자리와 놓은 뒤 자리가 달라 손이 속거나, 기기마다 다른 판이 그려지는 결함이 초록이 된다.
        val base = eEditor(listOf("A1 A2 A3 A4 A5 A6 A7", "B5 C5 D5", "A9 A10 J"), listOf(ep(40, 40), ep(500, 40), ep(300, 300)), "A8 A5 C2 J")
        val tableIDs = base.melds.flatten().map { it.id }
        val rackIDs = base.rack.map { it.id }
        val targets = arrayListOf(RummyDropTarget.NewMeld, RummyDropTarget.Rack(null), RummyDropTarget.RackSlot(RummyRackSlot(1, 4)), RummyDropTarget.Meld(9, null))
        for (x in 0L..960L step 60) for (y in 0L..580L step 52) targets.add(RummyDropTarget.NewMeldAt(ep(x, y)))
        for (set in 0 until 3) for (slot in listOf(null, 0, 2, 5)) targets.add(RummyDropTarget.Meld(set, slot))
        var compared = 0
        val expectedIDs = (tableIDs + rackIDs).toSet()
        for (id in tableIDs + rackIDs) {
            for (target in targets) {
                val snapshot = base.copy()
                val preview = base.previewDrop(listOf(id), target)
                assertEquals(snapshot, base)
                val a = base.copy()
                val b = base.copy()
                val movedA = a.moveBlock(listOf(id), target)
                val movedB = b.moveBlock(listOf(id), target)
                assertEquals(movedA, movedB, "$id → $target")
                assertEquals(a, b, "$id → $target")
                assertEquals(preview != null, movedA, "$id → $target")
                val landing = preview?.landing
                if (landing != null) {
                    assertTrue(landing.set in a.melds.indices)
                    assertEquals(landing.faces, a.melds[landing.set].map { it.face })
                    assertEquals(landing.frame, a.tableLayout.frame(landing.set))
                    assertEquals(id, a.melds[landing.set][landing.blockStart].id)
                    compared += 1
                }
                assertTrue(a.melds.none { it.isEmpty() } && a.points.size == a.melds.size)
                assertEquals(expectedIDs, (a.melds.flatten() + a.rack).map { it.id }.toSet())
            }
        }
        assertTrue(compared > 500, "미리보기 대조가 너무 적다: $compared")
        // 묶음 통째: 미리보기 = 실제.
        for (set in 0 until 3) {
            for (x in 0L..900L step 90) {
                val point = ep(x, 44)
                val moved = base.copy()
                val preview = base.previewMoveSet(set, point)
                assertTrue(moved.moveSet(set, point))
                val landing = preview?.landing
                if (landing != null) {
                    assertEquals(landing.frame, moved.tableLayout.frame(landing.set))
                    assertEquals(landing.faces, moved.melds[landing.set].map { it.face })
                }
            }
        }
        assertNull(base.previewMoveSet(7, ep(0, 0)))
    }

    @Test
    fun faceExtensions() {
        assertEquals(RummyFace.joker, RummyGoldenText.face("J"))
        assertTrue(RummyFace.joker.isJoker)
        assertEquals(30, RummyFace.joker.rackValue)
        assertEquals(7, RummyFace.numbered(0, 7).rackValue)
    }
}
