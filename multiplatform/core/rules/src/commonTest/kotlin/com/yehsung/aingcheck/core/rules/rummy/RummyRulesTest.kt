// 원본: Tests/checkTests/V0369RummyRulesTests.swift:125 @ 1a5eeca6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyTurnReason
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 규칙 판정과 차례 작업 상태 편집기의 이름 시험.
 * 없으면 어떤 결함이 초록으로 통과하는가: 조커 값(R-07)·첫 등록 30(R-11)·판 보존(R-16)·막힘 정산(R-23·R-24)·등수 분배(§2.1)를 서버와 각자 다르게 셈해도,
 * 편집기가 판 타일을 랙으로 받아도(R-14) 아무 시험도 빨개지지 않는다. 코퍼스 154건은 [RummyRulesGoldenTest] 가 잰다.
 */
class RummyRulesTest {
    private fun f(text: String): RummyFace = RummyGoldenText.face(text)

    private fun a(seat: Int, score: Int, tiles: Int) = RummyPayoutSeat(true, score, tiles, seat)

    private fun x(seat: Int, order: Int) = RummyPayoutSeat(false, 0, 0, seat, order)

    private class PayoutCase(val id: String, val n: Int, val stake: Int, val seats: List<RummyPayoutSeat>, val payouts: List<Int>, val ranks: List<Int>?)

    private val payoutCases = listOf(
        PayoutCase("P01", 2, 5, listOf(a(0, 20, 0), a(1, -20, 3)), listOf(10, 0), null),
        PayoutCase("P02", 4, 5, listOf(a(0, 30, 0), a(1, -5, 2), a(2, -10, 3), a(3, -15, 4)), listOf(15, 5, 0, 0), null),
        PayoutCase("P03", 4, 3, listOf(a(0, 22, 0), a(1, -5, 2), a(2, -5, 3), a(3, -12, 4)), listOf(9, 2, 1, 0), listOf(1, 2, 2, 4)),
        PayoutCase("P04", 4, 10, listOf(a(0, 11, 3), a(1, 11, 1), a(2, -12, 5), a(3, -10, 4)), listOf(20, 20, 0, 0), listOf(1, 1, 4, 3)),
        PayoutCase("P05", 3, 5, listOf(a(0, 7, 0), a(1, -7, 2), x(2, 1)), listOf(10, 5, 0), null),
        PayoutCase("P06", 4, 5, listOf(a(0, 0, 6), x(1, 1), x(2, 2), x(3, 3)), listOf(20, 0, 0, 0), listOf(1, 4, 3, 2)),
        PayoutCase("P07", 4, 3, listOf(a(0, -10, 3), a(1, 25, 0), a(2, -15, 4), x(3, 1)), listOf(3, 9, 0, 0), null),
        PayoutCase("P08", 3, 10, listOf(a(0, 0, 2), a(1, 0, 1), a(2, 0, 1)), listOf(10, 10, 10), null),
        PayoutCase("P09", 4, 5, listOf(a(0, -3, 1), a(1, 9, 0), a(2, -3, 2), a(3, -3, 1)), listOf(2, 15, 1, 2), listOf(2, 1, 2, 2)),
        PayoutCase("P10", 2, 3, listOf(a(0, 0, 5), x(1, 1)), listOf(6, 0), null),
    )

    @Test
    fun payoutTableP01toP10() {
        assertEquals(10, payoutCases.size)
        for (c in payoutCases) {
            val got = RummyRules.payouts(c.n, c.stake, c.seats)
            assertEquals(c.payouts, got.payouts, c.id)
            assertEquals(c.n * c.stake, got.payouts.sum(), "${c.id} 제로섬")
            if (c.ranks != null) assertEquals(c.ranks, got.ranks, c.id)
        }
    }

    @Test
    fun payoutRanksForEveryCase() {
        // 표에 등수가 적히지 않은 여섯 건도 §2.1 ⑤ 정의로 손계산한 값.
        val expected = mapOf(
            "P01" to listOf(1, 2), "P02" to listOf(1, 2, 3, 4), "P05" to listOf(1, 2, 3),
            "P07" to listOf(2, 1, 3, 4), "P08" to listOf(1, 1, 1), "P10" to listOf(1, 2),
        )
        for (c in payoutCases) {
            val ranks = expected[c.id] ?: continue
            assertEquals(ranks, RummyRules.payouts(c.n, c.stake, c.seats).ranks, c.id)
        }
    }

    @Test
    fun settlementP11CoWinnersShareRubyAndRank() {
        // 설계서 §2.1 0번 · P11(V1-01): 막힘 끝 최소 집단은 분배 점수를 ⌊P/m⌋ 로 같게 — 화면 점수의 나머지 1점이
        // 묶음을 가르면 같은 값 두 사람이 15/5 · 1위/2위로 갈린다(서버 tests/f_fix2.sql F1 과 같은 값).
        fun settle(racks: List<List<RummyFace>>, stake: Int): Pair<RummyFinalScores, RummyPayouts> {
            val final = RummyRules.finalScores(racks)
            val paid = RummyRules.payoutScores(racks)
            return final to RummyRules.payouts(racks.size, stake, racks.indices.map { RummyPayoutSeat(true, paid[it], racks[it].size, it) })
        }
        val racks = listOf(ef("A2"), ef("B2"), ef("C5"), ef("D6"))
        val (p11, p11Paid) = settle(racks, 5)
        assertEquals(listOf(4, 3, -3, -4), p11.scores, "화면 점수는 R-24 그대로")
        assertEquals(listOf(3, 3, -3, -4), RummyRules.payoutScores(racks))
        assertEquals(listOf(10, 10, 0, 0), p11Paid.payouts)
        assertEquals(listOf(1, 1, 3, 4), p11Paid.ranks)
        assertEquals(listOf(0, 1), p11.winners)
        // 장수가 다른 최소 집단(F1b): 점수 [2,3,−5] · 승자 s1 만 · 상금은 한 묶음 [7,8,0](나머지는 장수 적은 쪽) · 등수 [1,1,3]
        val (b, bPaid) = settle(listOf(ef("A1 B1"), ef("C2"), ef("D7")), 5)
        assertEquals(listOf(2, 3, -5), b.scores)
        assertEquals(listOf(1), b.winners)
        assertEquals(listOf(7, 8, 0), bPaid.payouts)
        assertEquals(listOf(1, 1, 3), bPaid.ranks)
        // 빈 랙 끝(R-22)·혼자 남음은 그대로.
        val emptied = listOf(ef("A2"), emptyList(), ef("B3"))
        assertEquals(RummyRules.finalScores(emptied).scores, RummyRules.payoutScores(emptied))
        assertEquals(listOf(0), RummyRules.payoutScores(listOf(ef("A2 B2"))))
    }

    @Test
    fun displayOrderPutsJokerInItsRunSlot() {
        assertEquals(ef("A5 A6 J"), RummyRules.displayOrder(ef("A5 A6 J"))) // J = A7
        assertEquals(ef("A5 A6 J"), RummyRules.displayOrder(ef("J A5 A6"))) // 왼쪽에 놓아도 A7(R-07 주의)
        assertEquals(ef("J A12 A13"), RummyRules.displayOrder(ef("A12 A13 J"))) // J = A11
        assertEquals(ef("A5 J A7"), RummyRules.displayOrder(ef("A5 A7 J"))) // J = A6
        assertEquals(ef("A9 B9 D9 J"), RummyRules.displayOrder(ef("J D9 B9 A9"))) // 그룹: 색 A→D, 조커 끝
        assertEquals(ef("A3 B3"), RummyRules.displayOrder(ef("A3 B3"))) // 무효 조각은 놓은 순서 그대로
    }

    @Test
    fun sameTableIgnoresOrderButCountsDuplicates() {
        val base = listOf(ef("A1 A2 A3"), ef("B7 C7 D7"))
        assertTrue(RummyRules.sameTable(base, listOf(ef("D7 B7 C7"), ef("A3 A1 A2"))))
        assertFalse(RummyRules.sameTable(base, listOf(ef("A1 A2 A3"), ef("B7 C7 D7"), ef("A1 A2 A3"))))
        assertFalse(RummyRules.sameTable(listOf(ef("A1 A2 A3"), ef("A1 A2 A3")), listOf(ef("A1 A2 A3"), ef("B1 B2 B3"))))
        assertFalse(RummyRules.sameTable(base, listOf(ef("A1 A2 A3 B7 C7 D7"))))
    }

    @Test
    fun newMeldPointsCountsOnlyNewMelds() {
        val before = listOf(ef("A1 A2 A3"))
        assertEquals(0, RummyRules.newMeldPoints(before, before))
        assertEquals(15, RummyRules.newMeldPoints(before, before + listOf(ef("B5 C5 D5"))))
        assertEquals(36, RummyRules.newMeldPoints(before, before + listOf(ef("B12 J J"))))
        assertEquals(0, RummyRules.newMeldPoints(before, before + listOf(ef("B5 C5")))) // 무효 조각 0점
        assertEquals(39, RummyRules.newMeldPoints(emptyList(), listOf(ef("C10 C11 C12"), ef("A1 A2 A3"))))
    }

    // MARK: 편집기

    /** 판 [A1 A2 A3] · 랙 [B10 C10 D10 A4 J]. */
    private fun sampleEditor(initialDone: Boolean = true) = RummyTurnEditor(listOf(ef("A1 A2 A3")), ef("B10 C10 D10 A4 J"), initialDone)

    private fun id(editor: RummyTurnEditor, face: String): Int = editor.rack.first { it.face == f(face) }.id

    private fun move(editor: RummyTurnEditor, tile: Int, target: RummyDropTarget, accepted: Boolean = true) {
        assertEquals(accepted, editor.move(tile, target), "move $tile → $target")
    }

    @Test
    fun editorInitNumbersTableFirstAndShowsRunJokerInPlace() {
        val editor = RummyTurnEditor(listOf(ef("A5 A7 J")), ef("B1 B2"), true)
        assertEquals(listOf(ef("A5 J A7")), editor.melds.map { meld -> meld.map { it.face } })
        assertEquals(listOf(0, 1, 2), editor.melds[0].map { it.id }.sorted())
        assertEquals(listOf(3, 4), editor.rack.map { it.id })
        assertTrue(editor.melds[0].all { editor.isFromTable(it.id) })
        assertFalse(editor.rack.any { editor.isFromTable(it.id) })
        assertFalse(editor.isChanged)
        assertEquals(0, editor.playedCount)
        assertEquals(RummyTurnReason.noTilePlayed, editor.reason)
    }

    @Test
    fun editorRejectsTableTileToRack() {
        val editor = sampleEditor()
        val before = editor.copy()
        val tableTile = editor.melds[0][0].id
        move(editor, tableTile, RummyDropTarget.Rack(null), accepted = false)
        move(editor, tableTile, RummyDropTarget.Rack(0), accepted = false)
        assertEquals(before, editor) // 거절은 아무것도 안 바꾼다
        // 판 → 판은 된다.
        move(editor, tableTile, RummyDropTarget.NewMeld)
        assertEquals(2, editor.melds.size)
        // 이번 차례 낸 내 타일은 랙으로 돌아온다.
        val mine = id(editor, "A4")
        move(editor, mine, RummyDropTarget.Meld(0, null))
        move(editor, mine, RummyDropTarget.Rack(0))
        assertEquals(f("A4"), editor.rack.first().face)
        // 모르는 id · 없는 세트 번호도 거절.
        move(editor, 999, RummyDropTarget.NewMeld, accepted = false)
        move(editor, mine, RummyDropTarget.Meld(7, null), accepted = false)
    }

    @Test
    fun editorRemovesEmptiedMelds() {
        val editor = sampleEditor()
        val b10 = id(editor, "B10")
        move(editor, b10, RummyDropTarget.NewMeld)
        assertEquals(2, editor.melds.size)
        assertEquals(1, editor.playedCount)
        move(editor, b10, RummyDropTarget.Rack(null))
        assertEquals(1, editor.melds.size)
        assertEquals(0, editor.playedCount)
        // 판 세트를 통째로 다른 세트로 옮기면 빈 원래 세트가 사라진다.
        val tableIDs = editor.melds[0].map { it.id }
        move(editor, b10, RummyDropTarget.NewMeld)
        for (tile in tableIDs) move(editor, tile, RummyDropTarget.Meld(1, null))
        assertEquals(1, editor.melds.size)
        assertEquals(4, editor.melds[0].size)
        assertFalse(editor.melds.any { it.isEmpty() })
    }

    @Test
    fun editorMovesWithinMeldUsingPreRemovalSlots() {
        // v3(K3): 맞는 정렬 자리가 있으면 슬롯보다 먼저라(규칙 ③), 슬롯 규약은 어디에도 안 이어지는 조각으로 잰다.
        val editor = RummyTurnEditor(listOf(ef("A1 B5 C9 D13")), emptyList(), true)
        val first = editor.melds[0][0].id
        move(editor, first, RummyDropTarget.Meld(0, 1)) // 자기 바로 뒤 슬롯 = 제자리
        assertEquals(ef("A1 B5 C9 D13"), editor.melds[0].map { it.face })
        move(editor, first, RummyDropTarget.Meld(0, 3)) // D13 앞
        assertEquals(ef("B5 C9 A1 D13"), editor.melds[0].map { it.face })
        move(editor, first, RummyDropTarget.Meld(0, null)) // 끝
        assertEquals(ef("B5 C9 D13 A1"), editor.melds[0].map { it.face })
        move(editor, first, RummyDropTarget.Meld(0, 0)) // 맨 앞
        assertEquals(ef("A1 B5 C9 D13"), editor.melds[0].map { it.face })
        assertFalse(editor.isChanged)
    }

    @Test
    fun editorReorderInsideRack() {
        val editor = sampleEditor()
        move(editor, id(editor, "J"), RummyDropTarget.Rack(0))
        assertEquals(ef("J B10 C10 D10 A4"), editor.rackFaces)
        move(editor, id(editor, "B10"), RummyDropTarget.Rack(4)) // A4 앞
        assertEquals(ef("J C10 D10 B10 A4"), editor.rackFaces)
        assertFalse(editor.isChanged)
    }

    @Test
    fun editorResetRestoresTableAndKeepsRackOrder() {
        val editor = sampleEditor()
        editor.sortRack(RummyRackSort.color) // A4 B10 C10 D10 J
        assertEquals(ef("A4 B10 C10 D10 J"), editor.rackFaces)
        move(editor, id(editor, "C10"), RummyDropTarget.NewMeld)
        move(editor, id(editor, "J"), RummyDropTarget.Meld(0, null))
        move(editor, editor.melds[0][0].id, RummyDropTarget.Meld(1, 0))
        assertTrue(editor.isChanged)
        editor.reset()
        assertEquals(listOf(ef("A1 A2 A3")), editor.submissionTable)
        assertEquals(ef("A4 B10 C10 D10 J"), editor.rackFaces) // 정렬한 배치 그대로, 낸 타일은 제자리
        assertFalse(editor.isChanged)
        assertEquals(0, editor.playedCount)
        // 시작 판 id 도 그대로라 판 타일은 계속 랙으로 못 간다.
        assertTrue(editor.melds[0].all { editor.isFromTable(it.id) })
        val fresh = sampleEditor().also { it.sortRack(RummyRackSort.color) }
        assertEquals(fresh, editor)
    }

    @Test
    fun editorSortRackByNumberAndByColor() {
        val editor = RummyTurnEditor(emptyList(), ef("C9 J A7 B8 A9 B7 A7"), false)
        editor.sortRack(RummyRackSort.number) // 777: 숫자 → 색, 조커 끝
        assertEquals(ef("A7 A7 B7 B8 A9 C9 J"), editor.rackFaces)
        editor.sortRack(RummyRackSort.color) // 789: 색 → 숫자, 조커 끝
        assertEquals(ef("A7 A7 A9 B7 B8 C9 J"), editor.rackFaces)
        // 같은 면 둘은 id 순(안정) — 두 번 정렬해도 id 배치가 흔들리지 않는다.
        val ids = editor.rack.map { it.id }
        editor.sortRack(RummyRackSort.number)
        editor.sortRack(RummyRackSort.color)
        assertEquals(ids, editor.rack.map { it.id })
    }

    @Test
    fun editorPreservesPreviousRackOrder() {
        // 서버 랙 순서는 아무렇게나 온다. 앞 차례 배치(C3 A1 …)를 면 순서로 맞추고, 새로 받은 D4 는 끝에.
        assertEquals(ef("C3 A1 B2 A1 D4"), RummyTurnEditor(emptyList(), ef("A1 B2 C3 A1 D4"), true, rackOrder = ef("C3 A1 B5 B2 A1")).rackFaces)
        assertEquals(ef("A1 B2 C3"), RummyTurnEditor(emptyList(), ef("A1 B2 C3"), true).rackFaces)
        assertEquals(ef("D4 A1 B2 C3"), RummyTurnEditor(emptyList(), ef("A1 B2 C3 D4"), true, rackOrder = ef("D4")).rackFaces)
    }

    @Test
    fun editorIsChangedComparesKMultisets() {
        val editor = RummyTurnEditor(listOf(ef("A1 A2 A3 A4 A5 A6")), ef("B9"), true)
        val tiles = editor.melds[0].map { it.id }
        // 쪼개면 바뀜. v3(K3): 가운데 A4 를 빼면 A1-A3 · A5-A6 이 제자리에 남고 새 세트는 맨 끝이다 — A5·A6 을 거기로.
        move(editor, tiles[3], RummyDropTarget.NewMeld)
        for (tile in tiles.drop(4)) move(editor, tile, RummyDropTarget.Meld(editor.melds.size - 1, null))
        assertEquals(2, editor.melds.size)
        assertTrue(editor.isChanged)
        // 다시 합치면(순서는 섞여도) 안 바뀜 — R-19 "쪼갰다 원래대로 돌려놓은 것".
        for (tile in tiles.drop(3).reversed()) move(editor, tile, RummyDropTarget.Meld(0, 0))
        assertEquals(1, editor.melds.size)
        // 0.3.70: 다시 맞는 세트가 되면 편집기가 R-09 표시 순서로 늘어놓는다(확정 뒤와 같은 순서) — 판정은 여전히 K 비교.
        assertEquals(ef("A1 A2 A3 A4 A5 A6"), editor.submissionTable[0])
        assertFalse(editor.isChanged)
        // 내 타일을 내면 바뀜, 거두면 다시 안 바뀜.
        val b9 = id(editor, "B9")
        move(editor, b9, RummyDropTarget.NewMeld)
        assertTrue(editor.isChanged)
        move(editor, b9, RummyDropTarget.Rack(null))
        assertFalse(editor.isChanged)
    }

    @Test
    fun editorJudgesInitialMeldProgress() {
        val editor = sampleEditor(initialDone = false)
        val b10 = id(editor, "B10")
        val c10 = id(editor, "C10")
        val d10 = id(editor, "D10")
        move(editor, b10, RummyDropTarget.NewMeld)
        assertEquals(RummyTurnReason.invalidMeld, editor.reason)
        assertFalse(editor.canSubmit)
        assertEquals(0, editor.initialPoints)
        move(editor, c10, RummyDropTarget.Meld(1, null))
        move(editor, d10, RummyDropTarget.Meld(1, null))
        assertEquals(30, editor.initialPoints)
        assertEquals(RummyTurnReason.ok, editor.reason)
        assertTrue(editor.canSubmit)
        assertEquals(listOf(ef("A1 A2 A3"), ef("B10 C10 D10")), editor.submissionTable)
        assertEquals(3, editor.playedCount)
        assertEquals(RummyMeldAnalysis(true, RummyMeldKind.group, 30), editor.analysis(1))
        assertEquals(RummyMeldAnalysis.invalid, editor.analysis(9))
        // 첫 등록 차례에 판 세트를 건드리면 판정이 막는다(편집기는 막지 않는다).
        move(editor, id(editor, "A4"), RummyDropTarget.Meld(0, null))
        assertEquals(RummyTurnReason.initialTableTouched, editor.reason)
        // 30 미만.
        val small = RummyTurnEditor(emptyList(), ef("A5 B5 C5"), false)
        for (tile in small.rack.map { it.id }) {
            move(small, tile, if (small.melds.isEmpty()) RummyDropTarget.NewMeld else RummyDropTarget.Meld(0, null))
        }
        assertEquals(15, small.initialPoints)
        assertEquals(RummyTurnReason.initialUnder30, small.reason)
    }

    /** Swift 는 값 타입이다 — Kotlin 은 copy() 가 그 뜻을 진다(ValueSemanticsTest 선례). 복사본을 바꿔도 원본이 안 바뀌어야 미리보기·사본에 해 보기가 산다. */
    @Test
    fun copyIsAValue() {
        val editor = sampleEditor()
        val before = editor.copy()
        val fork = editor.copy()
        assertEquals(editor, fork)
        fork.move(id(fork, "A4"), RummyDropTarget.Meld(0, null))
        fork.sortRack(RummyRackSort.number)
        assertEquals(before, editor, "복사본을 움직였는데 원본도 움직였다")
        // 읽어 간 받침대를 바꿔도 편집기는 그대로.
        val leaked = editor.rackLayout
        leaked.remove(editor.rack[0].id)
        assertEquals(before, editor, "받침대 읽기가 안쪽 값을 내줬다")
        // 미리보기 · 물어보기는 안 바꾼다.
        assertTrue(editor.canMoveBlock(listOf(id(editor, "A4")), RummyDropTarget.NewMeld))
        editor.previewDrop(listOf(id(editor, "A4")), RummyDropTarget.NewMeld)
        editor.previewMoveSet(0, ep(400, 400))
        editor.rackLayoutAfterDrop(listOf(id(editor, "A4")), RummyRackSlot(1, 0))
        assertEquals(before, editor, "미리보기가 편집기를 바꿨다")
        // 되돌리기 뒤 사본은 departures 까지 같다.
        val played = sampleEditor()
        val a4 = id(played, "A4")
        played.move(a4, RummyDropTarget.NewMeld)
        val copied = played.copy()
        copied.reset()
        played.reset()
        assertEquals(copied, played)
        assertEquals(copied.hashCode(), played.hashCode())
        // 받침대도 값이다.
        val layout = RummyRackLayout.packed(listOf(1, 2))
        val forked = layout.copy()
        forked.remove(1)
        assertEquals(RummyRackSlot(0, 0), layout.slot(1))
        assertNull(forked.slot(1))
    }
}
