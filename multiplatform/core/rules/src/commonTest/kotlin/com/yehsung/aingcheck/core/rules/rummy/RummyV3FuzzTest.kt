// 원본: Tests/checkTests/V0369RummyV3FuzzTests.swift:13 @ 1a5eeca6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyLayout
import com.yehsung.aingcheck.core.wire.games.RummyPoint
import com.yehsung.aingcheck.core.wire.games.RummyTurnReason
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

// 아잉 큐브 3판(K3·U3) 적대 검증 — 무작위 편집 시퀀스 퍼즈. 편집기 새 규칙(가운데 빼면 둘로 · 가까이 붙기 · 정렬 삽입)이
// 타일을 잃거나 · 판 출신을 랙으로 보내거나(R-14) · 묶음을 겹치게 두거나 · 손대지 않은 타일을 옮기거나 · 미리보기와 실제가
// 어긋나거나 · 같은 입력에 다른 답을 내는 경우를 찾는다. 0.3.70 검증에서 넓혔다: 길게 눌러 쪼개기 · 붐비는 판(비켜 놓기 · 꽉 찬 판 대체) ·
// **모든** 맞는 묶음의 표시 순서(R-09 — 확정 판과 같은 그림, 남은 토막 포함) · 판 밖 없음 · 와이어 배치 왕복.
// Swift 는 `Int.random(using:)` 이라 같은 수열이 아니다 — 비트 대조는 골든 rummy/turn-editor 몫이고 여기는 불변식이다.

private class FuzzRng(seed: Long) {
    private var state: ULong = seed.toULong()

    fun next(): ULong {
        state += 0x9E3779B97F4A7C15uL
        var z = state
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        return z xor (z shr 31)
    }

    fun below(n: Int): Int = (next() % n.toULong()).toInt()

    fun range(lo: Int, hi: Int): Int = lo + below(hi - lo + 1)

    fun flip(): Boolean = below(2) == 0

    fun <T> pick(items: List<T>): T = items[below(items.size)]

    fun <T> shuffled(items: List<T>): List<T> {
        val out = items.toMutableList()
        for (i in out.indices.reversed()) {
            if (i == 0) break
            val j = below(i + 1)
            val tmp = out[i]
            out[i] = out[j]
            out[j] = tmp
        }
        return out
    }
}

private sealed interface FuzzOp {
    data class Block(val ids: List<Int>, val target: RummyDropTarget) : FuzzOp

    data class SetMove(val set: Int, val point: RummyPoint) : FuzzOp

    data object Reset : FuzzOp

    data class Sort(val mode: RummyRackSort) : FuzzOp
}

private fun fuzzSet(r: FuzzRng): List<RummyFace> {
    val faces: MutableList<RummyFace>
    if (r.flip()) {
        val n = r.range(3, 7)
        val start = r.range(1, 14 - n)
        val color = r.below(4)
        faces = (start until start + n).map { RummyFace.numbered(color, it) }.toMutableList()
    } else {
        val n = r.range(3, 4)
        val number = r.range(1, 13)
        faces = r.shuffled(listOf(0, 1, 2, 3)).take(n).map { RummyFace.numbered(it, number) }.toMutableList()
    }
    if (r.below(5) == 0) faces[r.below(faces.size)] = RummyFace.joker
    return faces
}

/** 판 묶음을 잇는 면(런 앞뒤 · 그룹 빠진 색) — 붙기·끼우기가 실제로 일어나게. */
private fun extender(set: List<RummyFace>, r: FuzzRng): RummyFace? {
    val numbered = set.filter { !it.isJoker }.map { it.color!!.toInt() to it.number!!.toInt() }
    val first = numbered.firstOrNull() ?: return null
    if (numbered.map { it.second }.toSet().size == 1) {
        val used = numbered.map { it.first }.toSet()
        val free = (0 until 4).filter { it !in used }
        if (free.isEmpty()) return null
        return RummyFace.numbered(r.pick(free), first.second)
    }
    val numbers = numbered.map { it.second }
    val candidates = listOf(numbers.min() - 1, numbers.max() + 1, numbers.min() - 2, numbers.max() + 2).filter { it in 1..13 }
    if (candidates.isEmpty()) return null
    return RummyFace.numbered(first.first, r.pick(candidates))
}

private fun fuzzFace(r: FuzzRng): RummyFace = if (r.below(16) == 0) RummyFace.joker else RummyFace.numbered(r.below(4), r.range(1, 13))

/** 판 위 타일 id → 화면 왼쪽 위. */
private fun fuzzSpots(e: RummyTurnEditor): Map<Int, RummyPoint> {
    val spots = HashMap<Int, RummyPoint>()
    e.melds.forEachIndexed { set, meld ->
        meld.forEachIndexed { index, tile ->
            spots[tile.id] = RummyPoint(e.points[set].x + index * RummyTableLayout.tileWidth, e.points[set].y)
        }
    }
    return spots
}

/**
 * 0.3.70 ④(비켜 놓기): 손대지 않은 판 타일은 제자리거나, 그 묶음이 **통째로** 비켜났다 — 묶음의 타일이 옮기기 전에도 한 줄로
 * 나란히 있었고(쪼개진 토막 포함), 그 옛 사각형이 놓은 묶음의 새 사각형과 겹쳤다(막은 이웃만 비킨다). 어기면 그 까닭.
 */
private fun fuzzUntouched(before: RummyTurnEditor, after: RummyTurnEditor, landedSet: Int?, moving: Set<Int>): String? {
    val landedIDs = landedSet?.takeIf { it in after.melds.indices }?.let { set -> after.melds[set].map { it.id }.toSet() } ?: emptySet()
    val landedFrame = landedSet?.let { after.tableLayout.frame(it) }
    val was = fuzzSpots(before)
    val now = fuzzSpots(after)
    for (meld in after.melds) {
        val ids = meld.map { it.id }
        if (ids.any { it in moving || it in landedIDs }) continue
        if (ids.all { was[it] == now[it] }) continue
        val olds = ids.mapNotNull { was[it] }
        if (olds.size != ids.size) return "손대지 않은 묶음 $ids 이 판에 없었다"
        val minX = olds.minOf { it.x }
        val first = RummyPoint(minX, olds[0].y)
        val rigid = olds.toSet() == ids.indices.map { RummyPoint(first.x + it * RummyTableLayout.tileWidth, first.y) }.toSet()
        // 0.3.70 검증: 남은 토막은 안의 순서가 바뀔 수 있다 — 그때는 표시 순서(확정 뒤 그림)여야 한다.
        val faces = meld.map { it.face }
        val reordered = ids != ids.sortedBy { was.getValue(it).x }
        if (reordered && faces != RummyRules.displayOrder(faces)) {
            return "손대지 않은 묶음 ${faces.map { it.text }} 의 순서가 바뀌었는데 표시 순서가 아니다"
        }
        val old = RummyTableLayout.frame(first, ids.size)
        if (rigid && old == RummyTableLayout.frame(now.getValue(ids[0]), ids.size)) continue // 제자리에서 순서만
        // 남은 토막이 표시 순서로 바뀌며 사각형이 움직였으면 가장 많은 타일이 제자리인 밀기다(그 자리 타일 수 ≥ 제자리 순서만).
        if (reordered && rigid) {
            val stay = ids.count { was[it] == now[it] }
            val inPlace = ids.withIndex().count { (offset, id) -> was[id] == RummyPoint(first.x + offset * RummyTableLayout.tileWidth, first.y) }
            if (stay >= inPlace && stay > 0) continue
        }
        if (!rigid || landedFrame == null || !RummyTableLayout.overlaps(old, landedFrame)) {
            return "손대지 않은 타일 이동(막은 이웃 통째 비켜 놓기가 아님) $ids $first → ${now[ids[0]]}"
        }
    }
    return null
}

private fun fuzzFrames(e: RummyTurnEditor): List<RummyRect> = e.melds.indices.map { RummyTableLayout.frame(e.points[it], e.melds[it].size) }

private fun fuzzClear(frames: List<RummyRect>): Boolean {
    for (i in frames.indices) {
        if (!RummyTableLayout.fits(frames[i])) return false
        for (j in frames.indices) if (j > i && RummyTableLayout.overlaps(frames[i], frames[j])) return false
    }
    return true
}

private fun fuzzNear(e: RummyTurnEditor, blockCount: Int, r: FuzzRng): RummyPoint {
    val w = RummyTableLayout.tileWidth
    val frames = fuzzFrames(e)
    val roll = r.below(10)
    return when {
        roll < 4 && frames.isNotEmpty() -> {
            val f = r.pick(frames)
            RummyPoint(f.maxX + r.range(-30, 30), f.y + r.range(-34, 34))
        }
        roll in 4..6 && frames.isNotEmpty() -> {
            val f = r.pick(frames)
            RummyPoint(f.x - blockCount * w + r.range(-30, 30), f.y + r.range(-34, 34))
        }
        roll == 7 -> RummyPoint(r.range(-120, 1120).toLong(), r.range(-80, 720).toLong())
        else -> RummyPoint(r.range(0, 960).toLong(), r.range(0, 584).toLong())
    }
}

private fun fuzzOp(e: RummyTurnEditor, r: FuzzRng): FuzzOp {
    val roll = r.below(100)
    if (roll < 3) return FuzzOp.Reset
    if (roll < 6) return FuzzOp.Sort(if (r.flip()) RummyRackSort.number else RummyRackSort.color)
    if (roll < 18 && e.melds.isNotEmpty()) {
        val set = r.below(e.melds.size)
        return FuzzOp.SetMove(set, fuzzNear(e, e.melds[set].size, r))
    }
    // 블록 고르기.
    var ids: List<Int> = emptyList()
    val tableIDs = e.melds.flatten().map { it.id }
    val pick = r.below(7)
    when {
        pick == 0 && e.rack.isNotEmpty() -> ids = e.rackChain(r.pick(e.rack).id)
        pick == 1 && e.rack.isNotEmpty() -> ids = e.screenOrder(r.shuffled(e.rack).take(r.range(1, 3)).map { it.id }.toSet())
        pick == 2 && tableIDs.isNotEmpty() -> {
            // 0.3.70 ⑤: 판 길게 누르기 = 누른 타일에서 가까운 끝까지(meldChunk) — 옛 집기와 반반.
            val pressed = r.pick(tableIDs)
            ids = if (r.flip()) e.meldChunk(pressed) else e.meldPick(pressed, r.flip())
        }
        pick == 3 && tableIDs.isNotEmpty() && e.rack.isNotEmpty() -> ids = e.screenOrder(setOf(r.pick(tableIDs), r.pick(e.rack).id))
        pick == 4 || pick == 5 -> if (tableIDs.isNotEmpty()) ids = listOf(r.pick(tableIDs))
        else -> if (e.rack.isNotEmpty()) ids = listOf(r.pick(e.rack).id)
    }
    val all = tableIDs + e.rack.map { it.id }
    if (ids.isEmpty() && all.isNotEmpty()) ids = listOf(r.pick(all))
    val roll2 = r.below(20)
    val target: RummyDropTarget = when {
        roll2 < 6 && e.melds.isNotEmpty() -> {
            val set = r.below(e.melds.size)
            RummyDropTarget.Meld(set, if (r.below(5) == 0) null else r.range(-1, e.melds[set].size + 1))
        }
        roll2 == 6 -> RummyDropTarget.Meld(e.melds.size, 0) // 없는 묶음 → 거절
        roll2 == 7 -> RummyDropTarget.NewMeld
        roll2 in 8..14 -> RummyDropTarget.NewMeldAt(fuzzNear(e, ids.size, r))
        roll2 == 15 || roll2 == 16 -> RummyDropTarget.RackSlot(RummyRackSlot(r.range(0, 2), r.range(0, 30)))
        roll2 == 17 -> RummyDropTarget.Rack(null)
        else -> RummyDropTarget.Rack(r.range(-1, e.rack.size + 1))
    }
    return FuzzOp.Block(ids, target)
}

private fun fuzzApply(e: RummyTurnEditor, op: FuzzOp): Boolean = when (op) {
    is FuzzOp.Block -> e.moveBlock(op.ids, op.target)
    is FuzzOp.SetMove -> e.moveSet(op.set, op.point)
    FuzzOp.Reset -> {
        e.reset()
        true
    }
    is FuzzOp.Sort -> {
        e.sortRack(op.mode)
        true
    }
}

private class FuzzStart(val table: List<List<RummyFace>>, val rack: List<RummyFace>, val initialDone: Boolean, val layout: RummyLayout?) {
    fun editor() = RummyTurnEditor(table, rack, initialDone, tableLayout = layout)
}

private fun fuzzStart(r: FuzzRng): FuzzStart {
    // 가끔 붐비는 판(0.3.70 ④ 비켜 놓기 · 꽉 찬 판 대체가 실제로 일어나게).
    val crowded = r.below(5) == 0
    val table = List(if (crowded) r.range(14, 30) else r.range(0, 6)) { fuzzSet(r) }
    var rack = List(r.range(2, 10)) { fuzzFace(r) }
    for (set in table) {
        if (r.flip()) extender(set, r)?.let { rack = rack + it }
    }
    rack = r.shuffled(rack)
    // 배치: 대개 자동 배치(여백 16 으로 한 줄에 붙어 선다 — 붙기 거리 24 안), 가끔 손으로 흩은 배치.
    var layout: RummyLayout? = null
    if (r.below(3) == 0) {
        val points = ArrayList<RummyPoint>()
        val obstacles = ArrayList<RummyRect>()
        for (set in table) {
            val want = RummyPoint(r.range(0, 900).toLong(), r.range(0, 580).toLong())
            val point = RummyTableLayout.snap(want, set.size, obstacles)
            points.add(point)
            obstacles.add(RummyTableLayout.frame(point, set.size))
        }
        layout = RummyLayout(points)
    }
    return FuzzStart(table, rack, r.below(4) != 0, layout)
}

private fun faceBag(faces: List<RummyFace>): Map<String, Int> = faces.groupingBy { it.text }.eachCount()

/** 한 단계 검사. 실패 문구를 돌려준다(빈 목록 = 통과). [hasPreview] 는 미리보기를 잰 동작(블록 · 묶음 옮기기)인가. */
private fun fuzzCheck(
    before: RummyTurnEditor,
    after: RummyTurnEditor,
    op: FuzzOp,
    accepted: Boolean,
    hasPreview: Boolean,
    preview: RummyDropPreview?,
    start: FuzzStart,
    startIDs: Set<Int>,
    tableIDs: Set<Int>,
    startClear: Boolean,
): List<String> {
    val bad = ArrayList<String>()
    fun checkLanding(p: RummyDropPreview, block: List<Int>) {
        val landing = p.landing
        if (landing == null) {
            if (p.plan !is RummyDropPlan.Rack) bad.add("판행인데 landing 없음")
            return
        }
        if (landing.set !in after.melds.indices) {
            bad.add("landing 번호 밖")
            return
        }
        val meld = after.melds[landing.set]
        val faces = meld.map { it.face }
        if (landing.faces != faces) bad.add("landing 면 ≠ 실제")
        if (landing.frame != RummyTableLayout.frame(after.points[landing.set], meld.size)) bad.add("landing 사각형 ≠ 실제")
        if (landing.valid != RummyRules.analyze(faces).valid) bad.add("landing 유효 ≠ 실제")
        val ids = meld.map { it.id }
        val at = landing.blockStart
        if (landing.valid) {
            // 0.3.70 ③: 맞는 세트는 R-09 표시 순서(확정 뒤와 같다) — 블록은 흩어질 수 있다.
            if (faces != RummyRules.displayOrder(faces)) bad.add("맞는 세트인데 표시 순서가 아니다")
            if (ids.indexOf(block[0]) != at) bad.add("blockStart ≠ 블록 첫 장 자리")
        } else if (at + block.size > ids.size || ids.subList(at, at + block.size) != block) {
            bad.add("블록이 놓은 묶음 안에서 한 덩어리가 아니다")
        }
        if (p.plan is RummyDropPlan.Attach && !RummyRules.isChainable(faces)) bad.add("붙였는데 이어질 수 없는 모양")
    }

    val allTiles = after.melds.flatten() + after.rack
    // 1) 보존: id 집합 · 면 다중집합.
    if (allTiles.map { it.id }.toSet() != startIDs || allTiles.size != startIDs.size) bad.add("id 보존 깨짐")
    if (faceBag(allTiles.map { it.face }) != faceBag(start.table.flatten() + start.rack)) bad.add("면 보존 깨짐")
    // 2) R-14: 판 출신은 늘 판 위.
    val onTable = after.melds.flatten().map { it.id }.toSet()
    if (!onTable.containsAll(tableIDs)) bad.add("판 출신이 랙으로 감(R-14)")
    // 3) 모양.
    if (after.melds.any { it.isEmpty() } || after.melds.size != after.points.size) bad.add("빈 묶음/점 길이")
    if (after.rack.map { it.id } != after.rackLayout.readingOrder) bad.add("랙 화면 순서 ≠ 자리")
    // 4) 겹침 없음(시작 판이 깨끗했으면).
    if (startClear && !fuzzClear(fuzzFrames(after))) {
        // 0.3.70 ④ 대체: 붐비는 판에선 여백 0 자리(freeSpot 둘째 단계)까지 쓴다. 그래서 여기선 **실제로 덮는**(여백 없이 겹치는) 두 묶음만 본다
        // — 그것도 둘 중 하나에 덮지 않는 빈자리가 남아 있을 때만 결함.
        fun covers(a: RummyRect, b: RummyRect) = a.x < b.maxX && a.maxX > b.x && a.y < b.maxY && a.maxY > b.y
        val frames = fuzzFrames(after)
        val roomy = ArrayList<String>()
        for (i in frames.indices) {
            for (j in frames.indices) {
                if (j <= i || !covers(frames[i], frames[j])) continue
                for (k in listOf(i, j)) {
                    val others = frames.indices.filter { it != k }.map { frames[it] }
                    val spot = RummyTableLayout.freeSpot(after.points[k], after.melds[k].size, others)
                    if (spot != null) roomy.add("$i${frames[i]} × $j${frames[j]} — $k→$spot")
                }
            }
        }
        if (roomy.isNotEmpty()) bad.add("묶음이 덮임(빈자리 있음 $roomy)")
    }
    // 4-1) 판 밖 없음(시작 판이 붐벼도) · 와이어 배치(서버 0…1000 × 0…640 정수 → 모든 기기 place)가 화면 점 그대로 돌아온다.
    if (fuzzFrames(after).any { !RummyTableLayout.fits(it) }) bad.add("판 밖 묶음")
    if (RummyTableLayout.place(after.submissionTable, RummyLayout(after.points)) != after.points) bad.add("와이어 배치가 화면 점과 다르다")
    // 4-2) R-09 확정 전후 같은 그림: 맞는 묶음은 모두(받은 묶음만이 아니라 남은 토막·손대지 않은 묶음까지) 표시 순서다.
    for (meld in after.melds) {
        val faces = meld.map { it.face }
        if (RummyRules.analyze(faces).valid && faces != RummyRules.displayOrder(faces)) {
            bad.add("맞는 묶음 ${faces.map { it.text }} 이 표시 순서가 아니다(확정 뒤 튐)")
        }
    }
    // 6) isChanged = !sameTable.
    if (after.isChanged == RummyRules.sameTable(after.submissionTable, start.table)) bad.add("isChanged 불일치")
    if (op is FuzzOp.SetMove) {
        if (hasPreview) {
            if ((preview == null) == accepted) bad.add("묶음 옮기기 미리보기 거절 여부 ≠ 실제")
            if (preview != null && accepted && op.set in before.melds.indices) {
                val first = before.melds[op.set].map { it.id }
                checkLanding(preview, first)
                // 옮긴 묶음·붙은 묶음 말고는 제자리(막은 이웃은 통째 비켜 놓기만 — 0.3.70 ④).
                fuzzUntouched(before, after, preview.landing?.set, first.toSet())?.let { bad.add("묶음 옮기기: $it") }
            }
        }
        return bad
    }
    if (op !is FuzzOp.Block) return bad
    // 7) R-14 거절.
    if (op.ids.any { it in tableIDs } && accepted && (op.target is RummyDropTarget.Rack || op.target is RummyDropTarget.RackSlot)) {
        bad.add("판 출신 랙행을 받아들임")
    }
    // 8) 미리보기 = 실제.
    if (hasPreview) {
        if ((preview == null) == accepted) bad.add("미리보기 거절 여부 ≠ 실제")
        if (preview != null && accepted) checkLanding(preview, op.ids)
    }
    // 9) 손대지 않은 타일은 제자리: 블록도 아니고 놓은 묶음에도 없는 판 타일. 0.3.70 ④: 놓은 묶음을 막은 이웃은 통째 비켜날 수 있다.
    if (accepted) fuzzUntouched(before, after, preview?.landing?.set, op.ids.toSet())?.let { bad.add(it) }
    return bad
}

/** 무작위 시퀀스 퍼즈(보존 · R-14 · 겹침 · 제자리 · 미리보기 · 결정성). */
class RummyV3FuzzTest {
    @Test
    fun randomEditSequences() {
        // 없으면: 붙기 연쇄가 곁의 손대지 않은 묶음을 끌어당기거나 · 쪼개기가 타일을 잃거나 · 미리보기가 실제와 다른 결함이 초록이 된다.
        val sequences = 240
        val failures = ArrayList<String>()
        var failureCount = 0
        var accepted = 0
        var steps = 0
        for (seed in 0 until sequences) {
            val r = FuzzRng(seed * 0x10000001L + 7)
            val start = fuzzStart(r)
            val first = start.editor()
            val startIDs = (first.melds.flatten() + first.rack).map { it.id }.toSet()
            val tableIDs = first.melds.flatten().map { it.id }.toSet()
            val startClear = fuzzClear(fuzzFrames(first))
            val editor = first.copy()
            val ops = ArrayList<FuzzOp>()
            for (step in 0 until r.range(1, 16)) {
                val op = fuzzOp(editor, r)
                ops.add(op)
                var preview: RummyDropPreview? = null
                var hasPreview = false
                when (op) {
                    is FuzzOp.Block -> {
                        preview = editor.previewDrop(op.ids, op.target)
                        if (preview != editor.previewDrop(op.ids, op.target)) failures.add("seed $seed step $step: 미리보기 비결정")
                        hasPreview = true
                    }
                    is FuzzOp.SetMove -> {
                        preview = editor.previewMoveSet(op.set, op.point)
                        hasPreview = true
                    }
                    else -> Unit
                }
                val before = editor.copy()
                val ok = fuzzApply(editor, op)
                steps += 1
                if (ok) accepted += 1
                val bad = fuzzCheck(before, editor, op, ok, hasPreview, preview, start, startIDs, tableIDs, startClear)
                if (bad.isNotEmpty()) {
                    failureCount += 1
                    if (failures.size < 12) {
                        failures.add("seed $seed step $step op $op → ${bad.joinToString(" · ")}\n  before ${RummyGoldenText.core(before)}\n  after  ${RummyGoldenText.core(editor)}")
                    }
                }
            }
            // 결정성: 같은 시작 · 같은 시퀀스 → 같은 편집기.
            val replay = start.editor()
            for (op in ops) fuzzApply(replay, op)
            if (replay != editor) {
                failureCount += 1
                failures.add("seed $seed: 다시 돌린 결과가 다르다")
            }
            // 되돌리기 = 시작 판 · 시작 배치, 랙 면은 시작 랙.
            val reset = editor.copy()
            reset.reset()
            if (reset.melds != first.melds || reset.points != first.points || faceBag(reset.rackFaces) != faceBag(start.rack) || reset.isChanged || reset.isLayoutChanged) {
                failureCount += 1
                failures.add("seed $seed: 되돌리기가 시작 판이 아니다")
            }
        }
        assertEquals(0, failureCount, failures.joinToString("\n"))
        assertTrue(accepted > steps / 3, "받아들인 단계가 너무 적다 — 퍼즈가 규칙을 못 건드린다($accepted/$steps)")
    }
}

private fun vEditor(sets: List<String>, at: List<RummyPoint>, rack: String) =
    RummyTurnEditor(sets.map { ef(it) }, ef(rack), true, tableLayout = RummyLayout(at))

private fun vTexts(e: RummyTurnEditor): List<String> = e.submissionTable.map { RummyGoldenText.text(it) }

/** 적대 검증에서 찾은 결함(붙기 연쇄). */
class RummyV3VerifyTest {
    @Test
    fun attachDoesNotPullUntouchedNeighbor() {
        // 없으면: 붙은 뒤 합친 묶음의 **대상 쪽 바깥 끝**(손대지 않은 끝)까지 다시 붙기를 봐서, 자동 배치로 16 곁에 서 있던
        // A1-A3 까지 합쳐 A1-A7 이 되고 A4-A6 이 16 왼쪽으로 당겨지는 결함이 초록이 된다.
        val editor = vEditor(listOf("A1 A2 A3", "A4 A5 A6"), listOf(ep(0, 0), ep(136, 0)), "A7")
        val a7 = editor.rack[0].id
        val near = editor.copy()
        val preview = near.previewDrop(listOf(a7), RummyDropTarget.NewMeldAt(ep(260, 0)))
        assertTrue(near.moveBlock(listOf(a7), RummyDropTarget.NewMeldAt(ep(260, 0))))
        assertEquals(listOf("A1 A2 A3", "A4 A5 A6 A7"), vTexts(near))
        assertEquals(listOf(ep(0, 0), ep(136, 0)), near.points)
        assertEquals(RummyDropPlan.Attach(1, RummyAttachSide.right), preview?.plan)
        assertEquals(1, preview?.landing?.set)
        val onto = editor.copy()
        assertTrue(onto.moveBlock(listOf(a7), RummyDropTarget.Meld(1, null)))
        assertEquals(vTexts(near), vTexts(onto), "묶음 위에 놓기와 끝 곁에 놓기가 같은 판")
        assertEquals(near.points, onto.points)
    }

    @Test
    fun moveSetDoesNotCascadeThroughHost() {
        // 없으면: 옮긴 묶음이 대상과 합친 뒤 대상의 반대 끝 곁 묶음까지 합쳐(A1-A9) 손대지 않은 타일이 움직인다.
        val editor = vEditor(listOf("A1 A2 A3", "A4 A5 A6", "A7 A8 A9"), listOf(ep(0, 0), ep(136, 0), ep(0, 300)), "B1")
        assertTrue(editor.moveSet(2, ep(262, 4)))
        assertEquals(listOf("A1 A2 A3", "A4 A5 A6 A7 A8 A9"), vTexts(editor))
        assertEquals(listOf(ep(0, 0), ep(136, 0)), editor.points)
    }

    @Test
    fun gapFillStillJoinsBothEnds() {
        // 없으면: 끝마다 한 번만 붙게 고치다 틈 메우기(양쪽 다 붙기)까지 막는 회귀가 초록이 된다.
        val editor = vEditor(listOf("A1 A2 A3", "A5 A6 A7"), listOf(ep(100, 200), ep(260, 200)), "A4")
        assertTrue(editor.moveBlock(listOf(editor.rack[0].id), RummyDropTarget.NewMeldAt(ep(222, 204))))
        assertEquals(listOf("A1 A2 A3 A4 A5 A6 A7"), vTexts(editor))
        assertEquals(listOf(ep(100, 200)), editor.points)
    }
}

/** 첫 등록 전 자동 붙기(R-12). */
class RummyV3InitialAttachTest {
    private fun editor(sets: List<String>, at: List<RummyPoint>, rack: String, initialDone: Boolean) =
        RummyTurnEditor(sets.map { ef(it) }, ef(rack), initialDone, tableLayout = RummyLayout(at))

    @Test
    fun newSetDoesNotJoinTableSetBeforeInitial() {
        // 없으면: 첫 등록 전에 곁에 놓은 내 새 묶음이 판 묶음에 저절로 합쳐져 [완료]가 '판 묶음을 건드렸다'로 막히는 결함이 초록이 된다.
        for (initialDone in listOf(false, true)) {
            val e = editor(listOf("A1 A2 A3"), listOf(ep(0, 0)), "A4 A5 A6 B9", initialDone)
            val ids = e.rack.take(3).map { it.id }
            val target = RummyDropTarget.NewMeldAt(ep(126, 2))
            val preview = e.previewDrop(ids, target)
            assertTrue(e.moveBlock(ids, target))
            if (initialDone) {
                assertEquals(listOf("A1 A2 A3 A4 A5 A6"), vTexts(e))
                assertEquals(RummyDropPlan.Attach(0, RummyAttachSide.right), preview?.plan)
            } else {
                assertEquals(listOf("A1 A2 A3", "A4 A5 A6"), vTexts(e))
                assertTrue(preview?.plan is RummyDropPlan.NewSet, "첫 등록 전 미리보기가 붙기다: ${preview?.plan}")
                assertNotEquals(RummyTurnReason.initialTableTouched, e.reason)
                assertTrue(e.points[1].x >= 120 + RummyTableLayout.clearance, "새 묶음이 판 묶음과 겹친다")
            }
        }
    }

    @Test
    fun tableSetsDoNotMergeBeforeInitialButOwnSetsDo() {
        // 없으면: 첫 등록 전 판 정리(위치 옮기기)가 판 묶음 둘을 합쳐 낼 수 없는 판이 되는 결함이 초록이 된다.
        val e = editor(listOf("A1 A2 A3", "A4 A5 A6"), listOf(ep(0, 0), ep(0, 300)), "B4 B5 B6 B7 B8 B9", false)
        assertTrue(e.moveSet(1, ep(124, 0)))
        assertEquals(listOf("A1 A2 A3", "A4 A5 A6"), vTexts(e))
        assertTrue(!e.isChanged)
        // 내 새 묶음끼리(판 타일 없음)는 첫 등록 전에도 붙는다 → B4-B9 = 39점 → 낼 수 있다.
        val b = e.rack.map { it.id }
        assertTrue(e.moveBlock(b.take(3), RummyDropTarget.NewMeldAt(ep(0, 400))))
        assertTrue(e.moveBlock(b.takeLast(3), RummyDropTarget.NewMeldAt(ep(124, 400))))
        assertEquals("B4 B5 B6 B7 B8 B9", vTexts(e).last())
        assertTrue(e.canSubmit)
    }
}
