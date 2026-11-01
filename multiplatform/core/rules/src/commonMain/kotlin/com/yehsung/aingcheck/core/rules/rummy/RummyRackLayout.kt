// 원본: Sources/CheckCore/RummyRackLayout.swift:1 @ 1a5eeca6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.wire.games.RummyFace
import kotlinx.serialization.Serializable
import kotlin.math.abs

// 아잉 큐브 2판 — 내 받침대(랙) 자유 배치 모델(설계서 v2 §2.3). 골든 `rummy/rack-layout`.
//
// 받침대는 줄 2개(넘치면 3번째 줄부터 더 연다)이고, 한 줄은 **반 칸 단위** [RummyRackLayout.halfColumns](기본 halfColumnsPerRow 32 = 타일 16장)다.
// 줄 폭은 인스턴스 값이다 — 폰은 22(한 줄 11장, RummyRackGeometry.phoneHalfColumns)를 쓴다. 저장 항목은 기기별 로컬이라 맥 판을 폰에서 이어 받으면 폭 밖 자리는 nearestFree 로 간다.
// 타일 한 장은 반 칸 2개를 차지한다(`halfCol ..< halfCol + 2`). 같은 줄에서 두 타일이 반 칸이라도 겹치면 안 되고, 빈칸은 된다.
// 화면 순서([RummyRackLayout.readingOrder])는 줄 → 반 칸 순이다. 편집기의 rack 목록은 늘 이 순서다.
//
// 정렬(777 · 789)은 **조합 단위로 끊고 단위 사이 반 칸**을 띄운다(낱장끼리도). 단위가 줄 끝에 안 들어가면 통째로 다음 줄로.
// 판마다 로컬에 저장한다([RummyRackEntry] — 면과 자리. 타일 로컬 id 는 차례마다 새로 붙으므로 면으로 짝짓는다).
//
// Swift 와 다른 점(값 의미): Swift `RummyRackLayout` 은 값 타입이다. Kotlin 은 참조라 복제는 [RummyRackLayout.copy] 로 한다.
// [RummyRackLayout.slots] 는 읽기 전용 지도이고 고칠 때마다 새 지도로 갈아 끼우므로 복사본끼리 나누지 않는다.

/** 받침대 위 한 자리(줄 · 반 칸). 타일의 왼쪽 끝이다. */
@Serializable
data class RummyRackSlot(val row: Int, val halfCol: Int) : Comparable<RummyRackSlot> {
    override fun compareTo(other: RummyRackSlot): Int =
        if (row != other.row) row.compareTo(other.row) else halfCol.compareTo(other.halfCol)

    override fun toString(): String = "($row,$halfCol)"
}

/** 저장용 한 줄 — 면과 자리. 같은 면이 둘이면 저장 순서대로 하나씩 짝짓는다. 면이 와이어 타입이라 읽기는 SwiftJson 으로 한다. */
@Serializable
data class RummyRackEntry(val face: RummyFace, val slot: RummyRackSlot)

class RummyRackLayout private constructor(
    slots: Map<Int, RummyRackSlot>,
    /** 한 줄의 반 칸 수. 복제·정렬·저장 복원이 모두 이 값을 잇는다. */
    val halfColumns: Int,
) {
    constructor(halfColumns: Int = halfColumnsPerRow) : this(emptyMap(), halfColumns)

    /** 타일 로컬 id → 자리. */
    var slots: Map<Int, RummyRackSlot> = slots
        private set

    fun copy(): RummyRackLayout = RummyRackLayout(slots, halfColumns)

    override fun equals(other: Any?): Boolean = other is RummyRackLayout && slots == other.slots && halfColumns == other.halfColumns

    override fun hashCode(): Int = 31 * slots.hashCode() + halfColumns

    override fun toString(): String = "RummyRackLayout($slots)"

    /** 화면에 그릴 줄 수(최소 2). */
    val rowCount: Int get() = maxOf(baseRows, (slots.values.maxOfOrNull { it.row } ?: -1) + 1)

    fun slot(tileID: Int): RummyRackSlot? = slots[tileID]

    /** 그 반 칸을 덮는 타일(화면의 누르기 판정용). */
    fun tile(covering: RummyRackSlot): Int? =
        slots.entries.firstOrNull { it.value.row == covering.row && covering.halfCol - it.value.halfCol in 0 until tileSpan }?.key

    /** 화면 순서(줄 → 반 칸). 자리가 같을 일은 없지만(겹침 금지) 만약을 위해 id 로 끊는다. */
    val readingOrder: List<Int>
        get() = slots.entries.sortedWith(compareBy({ it.value }, { it.key })).map { it.key }

    /** [tiles] 장을 [slot] 부터 나란히 놓을 수 있는가(줄 안 · 겹침 없음). [excluding] 은 장애물에서 뺀다(옮기는 타일들). */
    fun isFree(slot: RummyRackSlot, tiles: Int = 1, excluding: Set<Int> = emptySet()): Boolean {
        val span = tiles * tileSpan
        if (slot.row < 0 || slot.halfCol < 0 || slot.halfCol + span > halfColumns) return false
        for ((id, other) in slots) {
            if (other.row != slot.row || id in excluding) continue
            if (other.halfCol < slot.halfCol + span && other.halfCol + tileSpan > slot.halfCol) return false
        }
        return true
    }

    /**
     * [slot] 에서 가장 가까운 빈자리([tiles] 장이 나란히 들어가는). 같은 줄을 먼저(줄 차이 → 반 칸 차이 → 왼쪽),
     * 기존 줄이 다 막혔으면 새 줄(맨 아래)의 첫 자리. 늘 답이 있다.
     */
    fun nearestFree(slot: RummyRackSlot, tiles: Int = 1, excluding: Set<Int> = emptySet()): RummyRackSlot {
        val span = tiles * tileSpan
        val maxStart = maxOf(0, halfColumns - span)
        val wantRow = maxOf(0, slot.row)
        val wantCol = minOf(maxOf(0, slot.halfCol), maxStart)
        var best: RummyRackSlot? = null
        var bestRow = 0
        var bestCol = 0
        var bestLeft = 0
        for (row in 0 until rowCount) {
            for (col in 0..maxStart) {
                val candidate = RummyRackSlot(row, col)
                if (!isFree(candidate, tiles, excluding)) continue
                val dRow = abs(row - wantRow)
                val dCol = abs(col - wantCol)
                val better = best == null || dRow < bestRow || (dRow == bestRow && (dCol < bestCol || (dCol == bestCol && col < bestLeft)))
                if (better) {
                    best = candidate
                    bestRow = dRow
                    bestCol = dCol
                    bestLeft = col
                }
            }
        }
        if (best != null) return best
        val occupiedRows = slots.filter { it.key !in excluding }.values.map { it.row }
        return RummyRackSlot(maxOf(rowCount, (occupiedRows.maxOrNull() ?: -1) + 1), 0)
    }

    /**
     * "마지막 빈자리"(뽑은 타일·랙 끝으로 보내기): 화면 순서로 마지막 타일 **바로 뒤**에 들어가면 거기,
     * 아니면 그 뒤 줄들의 첫 빈자리, 그것도 없으면 앞에서부터 첫 빈자리, 다 막혔으면 새 줄.
     */
    fun endSlot(tiles: Int = 1, excluding: Set<Int> = emptySet()): RummyRackSlot {
        val span = tiles * tileSpan
        val others = slots.filter { it.key !in excluding }
        val rows = rowCount
        val last = others.values.maxOrNull()
        if (last != null) {
            val after = RummyRackSlot(last.row, last.halfCol + tileSpan)
            if (isFree(after, tiles, excluding)) return after
            for (row in (last.row + 1) until maxOf(rows, last.row + 1)) {
                firstFree(row, span, excluding)?.let { return it }
            }
        }
        for (row in 0 until rows) {
            firstFree(row, span, excluding)?.let { return it }
        }
        return RummyRackSlot(maxOf(rows, (others.values.maxOfOrNull { it.row } ?: -1) + 1), 0)
    }

    private fun firstFree(row: Int, span: Int, excluding: Set<Int>): RummyRackSlot? {
        if (span > halfColumns) return null
        for (col in 0..(halfColumns - span)) {
            val slot = RummyRackSlot(row, col)
            if (isFree(slot, span / tileSpan, excluding)) return slot
        }
        return null
    }

    /** 타일들을 [slot] 부터 나란히 놓는다(덮어쓴다 — 호출자가 [isFree]/[nearestFree] 로 고른 자리여야 한다). */
    fun set(tileIDs: List<Int>, slot: RummyRackSlot) {
        val next = slots.toMutableMap()
        tileIDs.forEachIndexed { offset, id -> next[id] = RummyRackSlot(slot.row, slot.halfCol + offset * tileSpan) }
        slots = next
    }

    fun remove(tileID: Int) {
        slots = slots - tileID
    }

    // MARK: - 0.3.70 끼워 넣기 · 덩어리

    private data class Item(val id: Int, val col: Int)

    /**
     * 끼워 넣기(0.3.70 — 감사 #2). [tileIDs] 를 [wanted] 부터 나란히 놓는다(이미 있던 자리는 먼저 뺀다).
     *  · [wanted] 가 비었으면 **그대로**(옛 규칙 — 빈칸에 놓기).
     *  · 아니면 그 줄의 타일 사이에 **끼운다**: 왼쪽 끝이 [wanted] 보다 앞인 타일은 제자리, 나머지는 오른쪽으로 민다.
     *    놓은 블록이 왼쪽 이웃에 닿거나 겹치면 그 바로 뒤에 붙인다(그 이웃 덩어리에 붙는다).
     *    미는 타일은 **필요한 만큼만** 밀고 덩어리 모양을 지킨다: 딱 붙은 타일은 붙은 채, 빈칸은 반 칸까지 줄어들되 0 은 안 된다
     *    (다른 덩어리끼리 붙어 버리지 않게). 블록이 왼쪽 덩어리에 붙었는데 오른쪽 이웃이 원래 다른 덩어리였으면 그 사이에도 반 칸을 둔다.
     *  · 줄 끝을 넘치면 넘친 **덩어리**를 다음 줄 맨 앞에 끼워 흘린다([settle]) — 덩어리가 한 줄보다 길거나 줄의 첫 덩어리면
     *    넘친 타일부터. 다음 줄도 같은 규칙으로 밀리고, 마지막 줄을 넘치면 새 줄이 열린다.
     * 타일을 잃거나 겹치지 않는다.
     */
    fun insert(tileIDs: List<Int>, wanted: RummyRackSlot) {
        if (tileIDs.isEmpty()) return
        slots = slots - tileIDs.toSet()
        val span = tileIDs.size * tileSpan
        val row = maxOf(0, wanted.row)
        val start0 = minOf(maxOf(0, wanted.halfCol), maxOf(0, halfColumns - span))
        val first = RummyRackSlot(row, start0)
        if (isFree(first, tileIDs.size)) {
            set(tileIDs, first)
            return
        }
        val line = items(row)
        val split = line.indexOfFirst { it.col >= start0 }.let { if (it < 0) line.size else it }
        val left = line.subList(0, split)
        val right = line.subList(split, line.size)
        var start = start0
        var joinedLeft = false
        val a = left.lastOrNull()
        if (a != null && start0 <= a.col + tileSpan) {
            start = a.col + tileSpan
            joinedLeft = true
        }
        val placed = left.toMutableList()
        tileIDs.forEachIndexed { offset, id -> placed.add(Item(id, start + offset * tileSpan)) }
        var end = start + span
        right.forEachIndexed { index, tile ->
            val gap = if (index == 0) {
                val separate = left.lastOrNull()?.let { it.col + tileSpan < tile.col } ?: false
                if (joinedLeft && separate) 1 else 0
            } else {
                minOf(1, tile.col - (right[index - 1].col + tileSpan))
            }
            val col = maxOf(tile.col, end + gap)
            placed.add(Item(tile.id, col))
            end = col + tileSpan
        }
        settle(placed, row)
    }

    /** 같은 줄에서 딱 붙은(빈칸 없는) 덩어리들 — 화면 순, 덩어리 안은 왼쪽부터. 랙 묶음 표시(감사 #3)가 쓴다. */
    val chunks: List<List<Int>>
        get() {
            val result = ArrayList<MutableList<Int>>()
            var previous: RummyRackSlot? = null
            for (id in readingOrder) {
                val slot = slots[id] ?: continue
                val before = previous
                if (before != null && before.row == slot.row && before.halfCol + tileSpan == slot.halfCol) {
                    result.last().add(id)
                } else {
                    result.add(mutableListOf(id))
                }
                previous = slot
            }
            return result
        }

    /** 한 줄의 타일(왼쪽부터). */
    private fun items(row: Int): List<Item> =
        slots.entries.filter { it.value.row == row }
            .sortedWith(compareBy({ it.value.halfCol }, { it.key }))
            .map { Item(it.key, it.value.halfCol) }

    /**
     * 한 줄 몫(왼쪽부터 · 겹침 없음)을 [row] 에 앉힌다. 줄 끝을 넘으면 넘친 덩어리(한 줄보다 짧고 줄의 첫 덩어리가 아니면 통째로,
     * 아니면 넘친 타일부터)를 다음 줄 맨 앞에 끼우고 그 줄 타일을 민다(첫 타일과는 반 칸 — 다른 덩어리). 줄마다 한 장 이상 남으니 끝난다.
     */
    private fun settle(placed: List<Item>, row: Int) {
        val over = placed.indexOfFirst { it.col + tileSpan > halfColumns }
        if (over < 0) {
            val next = slots.toMutableMap()
            for (item in placed) next[item.id] = RummyRackSlot(row, item.col)
            slots = next
            return
        }
        fun touches(i: Int) = placed[i - 1].col + tileSpan == placed[i].col
        var head = over
        while (head > 0 && touches(head)) head -= 1
        var tail = over
        while (tail + 1 < placed.size && touches(tail + 1)) tail += 1
        val chunkSpan = placed[tail].col + tileSpan - placed[head].col
        val cut = if (head > 0 && chunkSpan <= halfColumns) head else maxOf(over, 1)
        val next = slots.toMutableMap()
        for (item in placed.subList(0, minOf(cut, placed.size))) next[item.id] = RummyRackSlot(row, item.col)
        slots = next
        if (cut >= placed.size) return
        val flowing = ArrayList<Item>()
        for (i in cut until placed.size) {
            val col = if (i == cut) {
                0
            } else {
                flowing.last().col + tileSpan + minOf(1, placed[i].col - (placed[i - 1].col + tileSpan))
            }
            flowing.add(Item(placed[i].id, col))
        }
        val moving = flowing.map { it.id }.toSet()
        val nextRow = row + 1
        val existing = items(nextRow).filter { it.id !in moving }
        val line = flowing.toMutableList()
        var end = flowing.last().col + tileSpan
        existing.forEachIndexed { index, tile ->
            val gap = if (index == 0) 1 else minOf(1, tile.col - (existing[index - 1].col + tileSpan))
            val col = maxOf(tile.col, end + gap)
            line.add(Item(tile.id, col))
            end = col + tileSpan
        }
        settle(line, nextRow)
    }

    companion object {
        /** 한 줄의 반 칸 수 기본값(타일 16장, 맥). */
        const val halfColumnsPerRow: Int = 32

        /** 늘 보이는 줄 수. 넘치면 줄이 더 열린다. */
        const val baseRows: Int = 2

        /** 타일 한 장의 폭(반 칸). */
        const val tileSpan: Int = 2

        /** 빈칸 없이 순서대로(줄이 차면 다음 줄). 옛 선형 자리 API(`Rack(index)`)와 처음 받은 랙이 쓴다. */
        fun packed(tileIDs: List<Int>, halfColumns: Int = halfColumnsPerRow): RummyRackLayout =
            grouped(tileIDs.map { listOf(it) }, gap = 0, halfColumns = halfColumns)

        /** 단위(조합)마다 이어 놓고 단위 사이 [gap] 반 칸. 단위가 줄 끝에 안 들어가면 통째로 다음 줄(단위가 한 줄보다 길면 쪼갠다). */
        fun grouped(units: List<List<Int>>, gap: Int = 1, halfColumns: Int = halfColumnsPerRow): RummyRackLayout {
            val out = HashMap<Int, RummyRackSlot>()
            var row = 0
            var col = 0
            for (unit in units) {
                if (unit.isEmpty()) continue
                val span = unit.size * tileSpan
                if (col > 0 && col + span > halfColumns && span <= halfColumns) {
                    row += 1
                    col = 0
                }
                for (id in unit) {
                    if (col + tileSpan > halfColumns) {
                        row += 1
                        col = 0
                    }
                    out[id] = RummyRackSlot(row, col)
                    col += tileSpan
                }
                col += gap
            }
            return RummyRackLayout(out, halfColumns)
        }

        /**
         * 정렬 단위로 나눈다. `number`(777) = 숫자 → 색 순으로 늘어놓고 **같은 숫자**끼리 한 단위,
         * `color`(789) = 색 → 숫자 순으로 늘어놓고 **같은 색 연속 숫자**끼리 한 단위. 조커는 둘 다 맨 뒤 한 단위.
         * 늘어놓는 순서는 v1 sortRack 과 같다(같은 면은 id 순 — 안정).
         */
        fun sortUnits(tiles: List<RummyTile>, mode: RummyRackSort): List<List<RummyTile>> {
            fun rank(tile: RummyTile) = if (tile.face.color != null && tile.face.number != null) 0 else 1
            fun first(tile: RummyTile): Long {
                if (rank(tile) == 1) return 0
                return if (mode == RummyRackSort.number) tile.face.number!! else tile.face.color!!
            }
            fun second(tile: RummyTile): Long {
                if (rank(tile) == 1) return 0
                return if (mode == RummyRackSort.number) tile.face.color!! else tile.face.number!!
            }
            val sorted = tiles.sortedWith(compareBy({ rank(it) }, { first(it) }, { second(it) }, { it.id }))
            val units = ArrayList<MutableList<RummyTile>>()
            for (tile in sorted) {
                val last = units.lastOrNull()?.lastOrNull()
                if (last != null && joins(last.face, tile.face, mode)) {
                    units.last().add(tile)
                } else {
                    units.add(mutableListOf(tile))
                }
            }
            return units
        }

        private fun joins(previous: RummyFace, next: RummyFace, mode: RummyRackSort): Boolean {
            if (previous.isJoker || next.isJoker) return previous.isJoker && next.isJoker
            return when (mode) {
                RummyRackSort.number -> previous.number == next.number
                RummyRackSort.color -> previous.color == next.color && (previous.number ?: 0L) + 1 == next.number
            }
        }
    }
}

/**
 * 이 순서 그대로 런이나 그룹의 **일부**가 될 수 있는가(길이 무관 · 조커 와일드 · 1장 = 참). 길게 눌러 집기(랙)의 넓히기 기준.
 * 런 = 숫자 타일이 모두 같은 색이고 왼쪽부터 1씩 오르며(조커가 빈칸을 메운다) 1…13 안. 그룹 = 4장 이하, 숫자 하나, 색 모두 다름.
 */
fun RummyRules.isChainable(faces: List<RummyFace>): Boolean {
    if (faces.size <= 1) return faces.isNotEmpty()
    val colors = ArrayList<Long>()
    val numbers = ArrayList<Long>()
    val starts = HashSet<Long>()
    faces.forEachIndexed { index, face ->
        val color = face.color
        val number = face.number
        if (color != null && number != null) {
            colors.add(color)
            numbers.add(number)
            starts.add(number - index)
        }
    }
    if (numbers.isEmpty()) return faces.size <= 13
    // 런의 일부: 시작 숫자 s = number − index 가 모두 같고 s ≥ 1, s + count − 1 ≤ 13, 색 하나.
    if (colors.toSet().size == 1 && starts.size == 1) {
        val start = starts.first()
        if (start >= 1 && start + faces.size - 1 <= 13) return true
    }
    // 그룹의 일부.
    return faces.size <= 4 && numbers.toSet().size == 1 && colors.toSet().size == numbers.size
}
