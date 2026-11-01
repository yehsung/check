// 원본: Sources/CheckCore/RummyTurnEditor.swift:1 @ 1a5eeca6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyLayout
import com.yehsung.aingcheck.core.wire.games.RummyPoint
import com.yehsung.aingcheck.core.wire.games.RummyTurnReason
import kotlin.math.abs

// 차례 중 작업 상태. 골든 `rummy/turn-editor`(동작 열 → 판·랙·배치 스냅숏)가 이 파일의 계약이다.
//
// 로컬 id: 판 타일 먼저(세트 순·표시 순), 그다음 랙(화면 순)으로 0.. 을 붙인다. 와이어엔 면 문자열만 간다(설계서 §1).
// 시작 판의 세트는 R-09 표시 순서로 다시 그린다(런의 조커가 제자리에) — 비교는 K 다중집합이라 판정엔 영향이 없다.
//
// 끌기 자리(index) 규약: **옮기기 전 화면에서 "이 자리 앞에 놓는다"** 는 슬롯 번호다.
// 같은 줄 안에서 뒤로 옮기면 빠진 자리만큼 하나 당겨 꽂는다. null 이거나 넘치면 끝, 음수는 맨 앞.
//
// R-14: 차례 시작 때 판에 있던 타일은 랙으로 못 간다([RummyTurnEditor.move] 가 false, 아무것도 안 바꾼다). 이번 차례에 랙에서 낸 타일은 돌아올 수 있다.
// 첫 등록 차례의 판 조작(R-12)은 막지 않는다 — 판정([RummyTurnEditor.reason])이 initial_table_touched 로 알려 준다(편집기는 규칙을 둘로 들지 않는다).
//
// ── v2(설계서 v2 §2.2·§2.3) ──
//  · 판 배치: 묶음마다 왼쪽 위 점(points)을 함께 든다. 시작 점은 [RummyTableLayout.place](결정적 자동 배치)이고, 묶음 길이가
//    바뀌면 오른쪽으로 늘어나다 막히면 옆으로 · 그래도 막히면 이웃을 비켜 놓는다([RummyTableEdit.settle]). moveSet = 묶음 통째 위치 이동.
//    NewMeldAt(점) = 빈 곳에 놓아 새 묶음(그 점에서 가장 가까운 빈자리). 배치는 판정과 무관하다(reason 은 면만 본다).
//  · 받침대: rackLayout(줄 · 반 칸 자유 배치)이 랙 자리의 정본이고 rack 목록은 늘 그 화면 순서다. RackSlot(자리) = 그 자리
//    가까운 빈자리로. 옛 Rack(index = i) 는 선형 자리 규약 그대로 꽂은 뒤 **빈칸 없이 다시 채운다**(v2 화면은 RackSlot),
//    Rack(index = null) 은 마지막 빈자리([RummyRackLayout.endSlot]). 판으로 나간 랙 타일은 나간 **자리**를 기억했다가
//    reset 이 그 자리로(막혔으면 가장 가까운 빈자리로) 돌린다.
//  · 묶음째 옮기기: moveBlock 은 전부 아니면 전무이고 move(x) 는 moveBlock([x]) 다(같은 규약 한 벌).
//
// ── v3(K3) — 판 손맛 규칙. 판정과 무관(규칙 정본은 RummyTableEdit.kt 머리말) ──
//  ① 판 묶음에서 빼면 남은 토막이 제자리에 남는다(가운데면 둘로 — 오른 토막은 원래 묶음 바로 뒤 번호, 새 묶음은 늘 맨 끝).
//  ② 빈 곳에 놓기(NewMeldAt)·묶음 옮기기(moveSet)가 다른 묶음 끝 가까이면 이어질 때 그 끝에 합친다(대상 제자리).
//  ③ 묶음 위에 놓기(Meld)는 슬롯보다 알맞은 정렬 자리가 먼저(없으면 슬롯 — 위 자리 규약), 앞에 꽂히면 왼쪽으로 늘어난다.
//  화면은 previewDrop · previewMoveSet 으로 놓기 전에 계획(붙기 · 꽂기 · 새 자리)을 묻는다.
//
// ── 0.3.70 판 조작감 ──
//  · 받은 묶음이 맞는 세트가 되면 R-09 표시 순서로 늘어놓는다(그룹 색 순 · 런의 조커 자리) — 확정 전후가 같다.
//  · 늘어난 묶음이 막히면 옆으로(왼쪽 먼저) → 그래도 막히면 이웃을 비켜 놓는다(편집기 전용).
//  · 판이 꽉 차도 구석에 겹쳐 놓지 않는다([RummyTableLayout.freeSpot] 이 없으면 놓은 자리 + 이웃 비켜 놓기).
//  · 판 길게 누르기 = meldChunk(누른 타일에서 가까운 끝까지).
//  · 받침대 — RackSlot 이 타일 사이면 **끼우고 오른쪽을 민다**(빈칸이면 옛 그대로, 넘치면 다음 줄로 흘림 — [RummyRackLayout.insert]).
//
// Swift 와 다른 점(값 의미 — TetrisGame·ChessPosition 선례): Swift `RummyTurnEditor` 는 mutating 값 타입이다. Kotlin 은 참조에 바꾸는 메서드를 두고
// 복제는 [RummyTurnEditor.copy] 로만 한다(미리보기 · 사본에 해 보기). 안쪽 목록은 모두 읽기 전용이고 고칠 때마다 새 목록으로 갈아 끼우므로 사본끼리 나누지 않는다.
// 스토어는 편집기를 Compose 상태에 담을 때 copy() 뒤 바꾼 값을 다시 넣는다. [RummyTurnEditor.equals] 는 Swift 합성 Equatable 처럼 저장 칸 전부를 잰다.

/** 끌기용 타일 한 장. [id] 는 이 편집기 안에서만 뜻이 있는 로컬 번호다(와이어엔 면 문자열만 간다 — 설계서 §1). */
data class RummyTile(val id: Int, val face: RummyFace)

enum class RummyRackSort {
    /** 같은 숫자끼리(777). */
    number,

    /** 색별 연속(789). */
    color,
}

sealed interface RummyDropTarget {
    data class Rack(val index: Int?) : RummyDropTarget

    data class Meld(val set: Int, val index: Int?) : RummyDropTarget

    data object NewMeld : RummyDropTarget

    /** v2: 판의 빈 곳에 놓아 새 묶음. 점 = 놓은 묶음의 왼쪽 위(판 논리 좌표) — 그 점에서 가장 가까운 빈자리로 스냅한다. */
    data class NewMeldAt(val point: RummyPoint) : RummyDropTarget

    /** v2: 받침대의 한 자리(줄 · 반 칸). 그 자리에서 가장 가까운 빈자리로, 여러 장이면 그 자리부터 나란히. */
    data class RackSlot(val slot: RummyRackSlot) : RummyDropTarget
}

class RummyTurnEditor private constructor(
    melds: List<List<RummyTile>>,
    points: List<RummyPoint>,
    rack: List<RummyTile>,
    private var layout: RummyRackLayout,
    val initialDone: Boolean,
    /** 차례 시작 판(면) — 판정 기준. */
    private val startTable: List<List<RummyFace>>,
    /** 차례 시작 랙(면) — 판정 기준(순서 무관). */
    private val startRack: List<RummyFace>,
    /** 차례 시작 판(타일) — reset 이 되돌아갈 곳. */
    private val startMelds: List<List<RummyTile>>,
    /** 차례 시작 판 배치. */
    private val startPoints: List<RummyPoint>,
    /** 차례 시작 때 판에 있던 타일의 로컬 id(→ 랙으로 못 감, R-14). */
    private val tableTileIDs: Set<Int>,
    /** 랙에서 판으로 나간 타일과 나갈 때의 받침대 자리(나간 순서). reset 이 거꾸로 되짚어 제자리에 놓는다. 불변식: 지금 판 위에 있는 랙 출신 타일 = 이 목록의 타일. */
    private var departures: List<Departure>,
) {
    /** 작업 판(놓인 순서). */
    var melds: List<List<RummyTile>> = melds
        private set

    /** v2: 묶음마다 왼쪽 위 점(판 순서, [melds] 와 같은 길이). */
    var points: List<RummyPoint> = points
        private set

    /** 내 랙(화면 순서 = [rackLayout].readingOrder). */
    var rack: List<RummyTile> = rack
        private set

    /** v2: 받침대 자리(타일 id → 줄 · 반 칸). 랙 자리의 정본. 읽어 간 값은 사본이다. */
    val rackLayout: RummyRackLayout get() = layout.copy()

    /** 받침대 한 줄의 반 칸 수(맥 32 · 폰 22). */
    val rackHalfColumns: Int get() = layout.halfColumns

    private data class Departure(val tile: RummyTile, val slot: RummyRackSlot)

    /** 값 복제(Swift 대입과 같다). */
    fun copy(): RummyTurnEditor = RummyTurnEditor(
        melds, points, rack, layout.copy(), initialDone, startTable, startRack, startMelds, startPoints, tableTileIDs, departures,
    )

    override fun equals(other: Any?): Boolean =
        other is RummyTurnEditor && melds == other.melds && points == other.points && rack == other.rack && layout == other.layout &&
            initialDone == other.initialDone && startTable == other.startTable && startRack == other.startRack &&
            startMelds == other.startMelds && startPoints == other.startPoints && tableTileIDs == other.tableTileIDs &&
            departures == other.departures

    override fun hashCode(): Int {
        var h = melds.hashCode()
        h = 31 * h + points.hashCode()
        h = 31 * h + rack.hashCode()
        h = 31 * h + layout.hashCode()
        h = 31 * h + initialDone.hashCode()
        h = 31 * h + departures.hashCode()
        return h
    }

    /** 차례 시작 때 판에 있던 타일인가. */
    fun isFromTable(tileID: Int): Boolean = tileID in tableTileIDs

    private sealed interface Spot {
        data class Rack(val index: Int) : Spot

        data class Meld(val meld: Int, val index: Int) : Spot
    }

    private fun locate(tileID: Int): Spot? {
        val inRack = rack.indexOfFirst { it.id == tileID }
        if (inRack >= 0) return Spot.Rack(inRack)
        melds.forEachIndexed { meldIndex, meld ->
            val index = meld.indexOfFirst { it.id == tileID }
            if (index >= 0) return Spot.Meld(meldIndex, index)
        }
        return null
    }

    private fun tile(tileID: Int): RummyTile? = when (val spot = locate(tileID)) {
        is Spot.Rack -> rack[spot.index]
        is Spot.Meld -> melds[spot.meld][spot.index]
        null -> null
    }

    /**
     * 타일 하나를 옮긴다. 받아들였으면 true. 거절(false)이면 아무것도 바뀌지 않는다:
     * 모르는 id · 판 타일을 Rack/RackSlot 으로(R-14) · 없는 세트 번호.
     * 옮긴 뒤 빈 세트는 자동으로 지운다. 자리 번호 규약은 파일 머리말. `moveBlock(listOf(tileID), target)` 와 같다.
     */
    fun move(tileID: Int, target: RummyDropTarget): Boolean = moveBlock(listOf(tileID), target)

    // MARK: - v2 묶음째 집기·옮기기

    /**
     * 랙에서 길게 눌러 집히는 '이어진 덩어리'(화면 순). 누른 타일에서 같은 줄의 **딱 붙은** 이웃(반 칸 빈칸이면 끊긴다)을
     * 오른쪽 → 왼쪽 번갈아 넓히되, 이 순서로 런이나 그룹의 일부가 될 수 있는 동안만([isChainable]). 랙에 없는 id 면 빈 목록.
     */
    fun rackChain(tileID: Int): List<Int> {
        val start = layout.slot(tileID) ?: return emptyList()
        val bySlot = HashMap<RummyRackSlot, Int>()
        for ((id, slot) in layout.slots) bySlot[slot] = id
        val faces = rack.associate { it.id to it.face }
        fun face(id: Int): RummyFace = faces[id] ?: RummyFace.joker
        val chain = ArrayDeque(listOf(tileID))
        var left = start.halfCol
        var right = start.halfCol
        var grew = true
        while (grew) {
            grew = false
            val next = bySlot[RummyRackSlot(start.row, right + RummyRackLayout.tileSpan)]
            if (next != null && RummyRules.isChainable((chain + next).map(::face))) {
                chain.addLast(next)
                right += RummyRackLayout.tileSpan
                grew = true
            }
            val previous = bySlot[RummyRackSlot(start.row, left - RummyRackLayout.tileSpan)]
            if (previous != null && RummyRules.isChainable((listOf(previous) + chain).map(::face))) {
                chain.addFirst(previous)
                left -= RummyRackLayout.tileSpan
                grew = true
            }
        }
        return chain.toList()
    }

    /** 판에서 길게 눌러 집히는 타일들: 그 타일의 묶음 전체, [fromTileToEnd] 면 그 타일부터 오른쪽 끝까지(런 쪼개기). 판에 없는 id 면 빈 목록. */
    fun meldPick(tileID: Int, fromTileToEnd: Boolean = false): List<Int> {
        val spot = locate(tileID) as? Spot.Meld ?: return emptyList()
        val meld = melds[spot.meld]
        return (if (fromTileToEnd) meld.subList(spot.index, meld.size) else meld).map { it.id }
    }

    /**
     * 판에서 길게 눌러 집히는 토막(0.3.70 — 쪼개기): 누른 타일에서 가까운 끝까지([RummyTableEdit.pickRange] —
     * 오른쪽 절반이면 그 타일부터 끝까지, 왼쪽 절반이면 처음부터 그 타일까지, 정확히 가운데면 묶음 전체). 판에 없는 id 면 빈 목록.
     */
    fun meldChunk(tileID: Int): List<Int> {
        val spot = locate(tileID) as? Spot.Meld ?: return emptyList()
        val meld = melds[spot.meld]
        return meld.slice(RummyTableEdit.pickRange(meld.size, spot.index)).map { it.id }
    }

    /** 고른 타일들의 화면 순서(판 묶음 순 → 묶음 안 순 → 랙 화면 순). 모르는 id 는 버린다. */
    fun screenOrder(tileIDs: Set<Int>): List<Int> = (melds.flatten() + rack).map { it.id }.filter { it in tileIDs }

    /** [moveBlock] 이 받아들일까(바꾸지 않고 묻기). */
    fun canMoveBlock(tileIDs: List<Int>, target: RummyDropTarget): Boolean = copy().moveBlock(tileIDs, target)

    /**
     * 여러 장을 한 번에 옮긴다 — **전부 아니면 전무.** 거절(false): 빈 목록 · 중복 · 모르는 id · 판 출신이 섞인 채 랙으로(R-14) ·
     * 없는 세트 번호. 놓인 순서 = 넘긴 순서(화면이 [screenOrder] 로 맞춰 넘긴다).
     * 자리 = 옮기기 전 화면 슬롯([move] 규약) — 같은 줄이면 그 슬롯 앞에 있던 집힌 장수만큼 당겨 꽂는다.
     * 랙에서 판으로 나간 타일은 나갈 때의 받침대 자리를 하나씩 기억한다(→ reset 이 고칠 것 없이 맞는다).
     * v3(K3) 판 손맛(RummyTableEdit.kt 머리말): ① 판 묶음에서 빼면 남은 토막이 제자리에 남는다(가운데면 둘로 — 오른 토막은
     * 원래 묶음 바로 뒤 번호) ② NewMeldAt 이 다른 묶음 끝 가까이면 이어질 때 그 끝에 붙는다 ③ Meld 는 슬롯보다
     * 알맞은 정렬 자리가 먼저다(없으면 슬롯). 받은 묶음은 붙기 → 맞는 세트면 R-09 표시 순서 → 앉히기(settle — 막히면 옆으로,
     * 그래도 막히면 이웃을 비켜 놓는다) 순(0.3.70).
     */
    fun moveBlock(tileIDs: List<Int>, target: RummyDropTarget): Boolean = apply(tileIDs, target) != null

    /** 작업 중 판 묶음 하나. */
    private class Piece(
        var tiles: List<RummyTile>,
        var point: RummyPoint,
        /** 옮기기 전 화면 묶음 번호(쪼개진 토막이면 원래 묶음). 새 묶음이면 null. */
        val origin: Int?,
        /** 판 묶음에서 타일이 빠져 남은 토막(규칙 ①). 받은 묶음이 아니면 마무리에서 제자리 표시 순서로(apply 4). */
        val cut: Boolean = false,
    ) {
        val faces: List<RummyFace> get() = tiles.map { it.face }
        val frame: RummyRect get() = RummyTableLayout.frame(point, tiles.size)
    }

    private class Outcome(val plan: RummyDropPlan, val landed: Int?)

    /** [moveBlock] 의 몸체. 받아들였으면 계획과 놓은 뒤 블록이 든 묶음 번호(받침대행이면 null), 거절이면 null(아무것도 안 바꾼다). */
    private fun apply(tileIDs: List<Int>, target: RummyDropTarget): Outcome? {
        if (tileIDs.isEmpty() || tileIDs.toSet().size != tileIDs.size) return null
        val block = ArrayList<RummyTile>(tileIDs.size)
        val sources = HashMap<Int, Spot>()
        for (id in tileIDs) {
            val spot = locate(id) ?: return null
            val found = tile(id) ?: return null
            sources[id] = spot
            block.add(found)
        }
        val toRack: Boolean
        var targetSet: Int? = null
        var targetSlot: Int? = null
        when (target) {
            is RummyDropTarget.Rack, is RummyDropTarget.RackSlot -> {
                if (tileIDs.any { isFromTable(it) }) return null
                toRack = true
            }
            is RummyDropTarget.Meld -> {
                if (target.set !in melds.indices) return null
                toRack = false
                targetSet = target.set
                targetSlot = target.index
            }
            RummyDropTarget.NewMeld, is RummyDropTarget.NewMeldAt -> toRack = false
        }
        val moving = tileIDs.toSet()
        val lookup = HashMap<Int, RummyTile>()
        for (tile in rack) lookup[tile.id] = tile
        for (tile in block) lookup[tile.id] = tile

        // 1) 랙에서 빼기(판으로 나가는 것은 자리를 기억).
        val readingBefore = rack.map { it.id }
        val nextDepartures = departures.toMutableList()
        for (tile in block) {
            if (sources[tile.id] !is Spot.Rack) continue
            val slot = layout.slot(tile.id) ?: continue
            if (!toRack) nextDepartures.add(Departure(tile, slot))
            layout.remove(tile.id)
        }
        if (toRack) nextDepartures.removeAll { it.tile.id in moving }
        departures = nextDepartures

        // 2) 판에서 빼기(규칙 ① — 남은 토막은 제자리) + 대상 묶음에 꽂기(규칙 ③). 세트 번호는 옮기기 전 화면 기준이다.
        val pieces = ArrayList<Piece>()
        var receiving: Int? = null
        var plan: RummyDropPlan = RummyDropPlan.Rack
        // 꽂기 대상 묶음의 남은 타일(캐럿 자리를 표시 순서로 다시 셀 때).
        var keptIDs: Set<Int> = emptySet()
        val width = RummyTableLayout.tileWidth
        melds.forEachIndexed { index, meld ->
            val removed = meld.indices.filter { meld[it].id in moving }.toSet()
            if (index == targetSet) {
                val rest = meld.filter { it.id !in moving }
                keptIDs = rest.map { it.id }.toSet()
                var preferred = rest.size
                val slot = targetSlot
                if (slot != null) {
                    val before = meld.take(maxOf(slot, 0)).count { it.id in moving }
                    preferred = clamp(slot - before, rest.size)
                }
                val at = RummyTableEdit.insertionIndex(block.map { it.face }, rest.map { it.face }, preferred).index
                val tiles = rest.subList(0, at) + block + rest.subList(at, rest.size)
                // 남은 첫 타일이 제자리: 앞에 꽂히면 왼쪽으로 늘어난다.
                var point = points[index]
                val firstKept = meld.indices.firstOrNull { it !in removed }
                if (firstKept != null) {
                    point = RummyPoint(point.x + (firstKept - if (at == 0) block.size else 0) * width, point.y)
                }
                receiving = pieces.size
                pieces.add(Piece(tiles, point, index))
                plan = RummyDropPlan.Insert(index, at)
            } else if (removed.isEmpty()) {
                pieces.add(Piece(meld, points[index], index))
            } else {
                for (piece in RummyTableEdit.split(meld.size, points[index], removed)) {
                    pieces.add(Piece(meld.slice(piece.range), piece.point, index, cut = true))
                }
            }
        }

        // 3) 놓기.
        when (target) {
            is RummyDropTarget.Meld -> {
                val landed = receiving
                val inserted = plan
                if (landed != null && inserted is RummyDropPlan.Insert) {
                    // 자란 쪽만 본다: 앞에 꽂혔으면 왼쪽 이웃의 오른끝, 아니면 오른쪽 이웃의 왼끝. 다 옮겨 비었던 묶음이면 안 본다.
                    val grewLeft = inserted.index == 0 && pieces[landed].tiles.size > block.size
                    val sides = when {
                        pieces[landed].tiles.size == block.size -> emptyList()
                        grewLeft -> listOf(RummyAttachSide.right)
                        else -> listOf(RummyAttachSide.left)
                    }
                    receiving = attachAll(pieces, landed, sides, attachFixed).receiving
                }
            }
            RummyDropTarget.NewMeld -> {
                val point = RummyTableLayout.firstFree(block.size, pieces.map { it.frame })
                receiving = pieces.size
                pieces.add(Piece(block, point, null))
                plan = RummyDropPlan.NewSet(point)
            }
            is RummyDropTarget.NewMeldAt -> {
                val wanted = target.point
                pieces.add(Piece(block, wanted, null))
                val attached = attachAll(pieces, pieces.size - 1, ALL_SIDES, attachFixed)
                val landed = attached.receiving
                val first = attached.first
                if (first != null) {
                    plan = first
                } else {
                    // 가장 가까운 빈자리 — 판이 꽉 찼으면 구석 대신 놓은 자리(④ 가 이웃을 비켜 놓는다).
                    val others = pieces.indices.filter { it != landed }.map { pieces[it].frame }
                    pieces[landed].point = RummyTableLayout.freeSpot(wanted, block.size, others)
                        ?: RummyTableLayout.clampInside(wanted, block.size)
                    plan = RummyDropPlan.NewSet(pieces[landed].point)
                }
                receiving = landed
            }
            is RummyDropTarget.Rack -> {
                val slot = target.index
                if (slot != null) {
                    // 옛 선형 자리: 화면 순서에 꽂고 빈칸 없이 다시 채운다.
                    val order = readingBefore.filter { it !in moving }.toMutableList()
                    val before = readingBefore.take(maxOf(slot, 0)).count { it in moving }
                    order.addAll(clamp(slot - before, order.size), tileIDs)
                    layout = RummyRackLayout.packed(order, layout.halfColumns)
                } else {
                    layout.set(tileIDs, layout.endSlot(tileIDs.size))
                }
            }
            // 0.3.70: 빈칸이면 그 자리, 타일 사이면 끼우고 오른쪽을 민다([RummyRackLayout.insert]).
            is RummyDropTarget.RackSlot -> layout.insert(tileIDs, target.slot)
        }

        // 4) 남은 토막(0.3.70 검증): 타일이 빠져 남은 토막이 맞는 세트면 R-09 표시 순서로 — 확정 판은 모든 기기가 표시 순서로
        //    같은 점에 그린다(A3 J A5 A6 에서 A3 을 빼고 남은 J A5 A6 이 확정 뒤 A5 A6 J 로 튀지 않게 · 무효 묶음 끝을 빼 맞게 된
        //    토막도). 가장 많은 타일이 제자리(J A5 A6 → 조커만 반대 끝으로 · B4 A4 C4 D4 → C4 D4 제자리) — 그 자리가 막히면(판 밖 ·
        //    겹침) 사각형 제자리에서 순서만. 이웃은 건드리지 않는다. 붙기(②) 뒤라 '빼서 제자리 곁에 다시 놓기'는 옛 순서로
        //    이어 붙는다. 받은 묶음은 아래 마무리 몫.
        for (i in pieces.indices) {
            if (!pieces[i].cut || i == receiving) continue
            val point = pieces[i].point
            arrange(pieces[i], emptySet())
            if (pieces[i].point == point) continue
            val others = pieces.indices.filter { it != i }.map { pieces[it].frame }
            if (!RummyTableLayout.isClear(pieces[i].frame, others)) pieces[i].point = point
        }
        // 받은 묶음 마무리(0.3.70): 맞는 세트면 R-09 표시 순서로(③), 그다음 판에 앉힌다(④).
        val landed = receiving
        if (!toRack && landed != null) {
            finish(pieces, landed, moving, reorder = true)
            val current = plan
            when (current) {
                is RummyDropPlan.Insert -> {
                    val tiles = pieces[landed].tiles
                    val first = tiles.indexOfFirst { it.id in moving }.let { if (it < 0) 0 else it }
                    plan = RummyDropPlan.Insert(current.set, tiles.subList(0, first).count { it.id in keptIDs })
                }
                is RummyDropPlan.NewSet -> plan = RummyDropPlan.NewSet(pieces[landed].point)
                RummyDropPlan.Rack, is RummyDropPlan.Attach -> Unit
            }
        }

        melds = pieces.map { it.tiles }
        points = pieces.map { it.point }
        rack = layout.readingOrder.mapNotNull { lookup[it] }
        return Outcome(plan, receiving)
    }

    /** 규칙 ② 가 못 건드리는 타일: 첫 등록 전(R-12)이면 시작 판 타일 전부, 아니면 없음. 3판 검증에서 찾은 결함. */
    private val attachFixed: Set<Int> get() = if (initialDone) emptySet() else tableTileIDs

    /**
     * v2: 묶음 통째 위치 이동(판 좌표 왼쪽 위). 가장 가까운 빈자리로 스냅한다(자기 자리는 장애물에서 뺀다). 없는 번호면 false.
     * 배치만 바꾸면 판정(reason)·[isChanged] 와 무관하고 [isLayoutChanged] 만 바뀐다.
     * v3(K3) 규칙 ②: 놓은 자리가 다른 묶음 끝 가까이고 이어질 수 있으면 그 끝에 **합친다**(대상 제자리, 합친 묶음은 대상 번호).
     * 그때는 내용(묶음 수)이 바뀌므로 [isChanged] 도 바뀔 수 있다.
     */
    fun moveSet(setIndex: Int, point: RummyPoint): Boolean = applySet(setIndex, point) != null

    private fun applySet(setIndex: Int, point: RummyPoint): Outcome? {
        if (setIndex !in melds.indices) return null
        val pieces = ArrayList(melds.indices.map { Piece(melds[it], points[it], it) })
        pieces[setIndex].point = point
        val moved = melds[setIndex].map { it.id }.toSet()
        val attached = attachAll(pieces, setIndex, ALL_SIDES, attachFixed)
        val landed = attached.receiving
        val first = attached.first
        val plan: RummyDropPlan
        if (first != null) {
            finish(pieces, landed, moved, reorder = true)
            plan = first
        } else {
            // 가장 가까운 빈자리 — 판이 꽉 찼으면 구석 대신 놓은 자리에 두고 이웃을 비켜 놓는다(④). 만진 묶음이 맞는 세트인데 표시
            // 순서가 아니면(무효였던 묶음에서 끝을 빼 맞게 된 토막 등) 이때 표시 순서로 — 확정 뒤와 같게.
            val others = pieces.indices.filter { it != setIndex }.map { pieces[it].frame }
            val count = melds[setIndex].size
            pieces[setIndex].point = RummyTableLayout.freeSpot(point, count, others) ?: RummyTableLayout.clampInside(point, count)
            finish(pieces, setIndex, moved, reorder = true)
            plan = RummyDropPlan.NewSet(pieces[setIndex].point)
        }
        melds = pieces.map { it.tiles }
        points = pieces.map { it.point }
        return Outcome(plan, landed)
    }

    // MARK: - v3 놓기 미리보기(K3)

    /**
     * 놓기 전에 묻기(바꾸지 않는다): `moveBlock(tileIDs, target)` 이 할 일(계획)과 놓은 뒤 블록이 든 묶음.
     * 거절이면 null. 화면은 끄는 동안 이것으로 붙을 끝·꽂힐 자리·새 자리를 미리 그린다(같은 입력이면 같은 답).
     */
    fun previewDrop(tileIDs: List<Int>, target: RummyDropTarget): RummyDropPreview? {
        val copy = copy()
        val outcome = copy.apply(tileIDs, target) ?: return null
        val first = tileIDs.firstOrNull() ?: return null
        return RummyDropPreview(outcome.plan, outcome.landed?.let { copy.landing(it, first) })
    }

    /** [moveSet] 의 미리보기 — 붙으면 Attach, 아니면 NewSet(스냅된 점). 없는 번호면 null. */
    fun previewMoveSet(setIndex: Int, point: RummyPoint): RummyDropPreview? {
        if (setIndex !in melds.indices) return null
        val first = melds[setIndex].firstOrNull()?.id ?: return null
        val copy = copy()
        val outcome = copy.applySet(setIndex, point) ?: return null
        return RummyDropPreview(outcome.plan, outcome.landed?.let { copy.landing(it, first) })
    }

    private fun landing(set: Int, first: Int): RummyDropPreview.Landing {
        val tiles = melds[set]
        return RummyDropPreview.Landing(
            set = set,
            faces = tiles.map { it.face },
            frame = RummyTableLayout.frame(points[set], tiles.size),
            blockStart = tiles.indexOfFirst { it.id == first }.let { if (it < 0) 0 else it },
            valid = RummyRules.analyze(tiles.map { it.face }).valid,
        )
    }

    /**
     * 차례 시작 상태로. 판은 시작 판·시작 배치 그대로, 랙은 **지금 자리를 유지**하고 판에 나갔던 타일만 나간 자리로 돌린다
     * (그 자리가 그새 막혔으면 가장 가까운 빈자리).
     */
    fun reset() {
        val lookup = HashMap<Int, RummyTile>()
        for (tile in rack) lookup[tile.id] = tile
        for (departure in departures.asReversed()) {
            val slot = if (layout.isFree(departure.slot)) departure.slot else layout.nearestFree(departure.slot)
            layout.set(listOf(departure.tile.id), slot)
            lookup[departure.tile.id] = departure.tile
        }
        melds = startMelds
        points = startPoints
        rack = layout.readingOrder.mapNotNull { lookup[it] }
        departures = emptyList()
    }

    /**
     * 랙 정렬. number(777) = 숫자 → 색, color(789) = 색 → 숫자. 조커는 둘 다 맨 뒤. 같은 면은 id 순(안정).
     * v2: 조합 단위(777 = 같은 숫자, 789 = 같은 색 연속)로 끊어 **단위 사이 반 칸**을 띄워 받침대에 다시 놓는다.
     */
    fun sortRack(mode: RummyRackSort) {
        val units = RummyRackLayout.sortUnits(rack, mode)
        layout = RummyRackLayout.grouped(units.map { unit -> unit.map { it.id } }, halfColumns = layout.halfColumns)
        val lookup = rack.associateBy { it.id }
        rack = layout.readingOrder.mapNotNull { lookup[it] }
    }

    /**
     * 이 편집기가 그 확정 판·랙에서 시작했는가(판은 K 비교, 랙은 순서 무관). 같은 차례에 seq 만 오른 state 가 와도
     * 이것이 참이면 편집기를 덮지 않는다.
     */
    fun standsOn(table: List<List<RummyFace>>, rack: List<RummyFace>): Boolean {
        if (!RummyRules.sameTable(table, startTable) || rack.size != startRack.size) return false
        val counts = HashMap<RummyFace, Int>()
        for (face in startRack) counts[face] = (counts[face] ?: 0) + 1
        for (face in rack) counts[face] = (counts[face] ?: 0) - 1
        return counts.values.all { it == 0 }
    }

    /** !sameTable(작업 판, 시작 판) — 세트 안 순서만 바꿨거나 쪼갰다 되돌린 것은 "안 바뀜"(R-19·R-09). */
    val isChanged: Boolean get() = !RummyRules.sameTable(submissionTable, startTable)

    val submissionTable: List<List<RummyFace>> get() = melds.map { meld -> meld.map { it.face } }

    val reason: RummyTurnReason get() = RummyRules.judgeTurn(initialDone, startTable, startRack, submissionTable)

    val canSubmit: Boolean get() = reason == RummyTurnReason.ok

    fun analysis(ofMeld: Int): RummyMeldAnalysis =
        if (ofMeld in melds.indices) RummyRules.analyze(melds[ofMeld].map { it.face }) else RummyMeldAnalysis.invalid

    /** 첫 등록 전: 새 세트 점수 합("18/30" 의 18). */
    val initialPoints: Int get() = RummyRules.newMeldPoints(startTable, submissionTable)

    /** 이번 차례에 랙에서 판으로 낸 장수. 판 타일은 랙에 못 오므로 시작 랙 장수 − 지금 랙 장수다. */
    val playedCount: Int get() = startRack.size - rack.size

    val rackFaces: List<RummyFace> get() = rack.map { it.face }

    // MARK: - v2 배치 읽기

    /** 지금 작업 판의 배치(묶음 장수 + 점). 화면이 그대로 그린다. */
    val tableLayout: RummyTableLayout get() = RummyTableLayout(melds.map { it.size }, points)

    /** `rummy_draft`/`rummy_play` 의 `p_layout`(묶음마다 점, null 없음). */
    val submissionLayout: RummyLayout get() = RummyLayout(points)

    /** 배치만이라도 바뀌었는가(되돌리기 버튼·작업 전송용 — 판정과 무관). */
    val isLayoutChanged: Boolean get() = points != startPoints || isChanged

    /** 차례 시작 랙(면, 서버가 준 순서). 스토어가 다음 차례 랙과 대어 새로 받은 타일(뽑기)을 가린다. */
    val startRackFaces: List<RummyFace> get() = startRack

    /** 받침대 저장용(면 + 자리, 화면 순). */
    val rackEntries: List<RummyRackEntry>
        get() = rack.mapNotNull { tile -> layout.slot(tile.id)?.let { RummyRackEntry(tile.face, it) } }

    /**
     * 되돌린 것처럼(판에 나간 랙 타일이 나간 자리로 돌아온) 받침대 자리 — 다음 차례 편집기에 넘긴다(서버가 작업 판을 버리고
     * 그 타일들을 랙에 돌려주므로).
     */
    val restoredRackEntries: List<RummyRackEntry>
        get() {
            val copy = copy()
            copy.reset()
            return copy.rackEntries
        }

    companion object {
        private val ALL_SIDES = listOf(RummyAttachSide.right, RummyAttachSide.left)

        /**
         * Swift `RummyTurnEditor(table:rack:initialDone:rackOrder:tableLayout:rackEntries:)`.
         * @param rackOrder 앞 차례의 내 랙 배치(면 순서). 그 순서대로 맞추고, 거기 없는 면(새로 받은 타일)은 받은 순서로 끝에 붙인다.
         * @param tableLayout v2 확정 판 배치(`state.table_layout`). 빈 자리는 결정적 자동 배치로 채운다.
         * @param rackEntries v2 앞 차례(또는 저장된) 받침대 자리(면 + 자리). 주면 [rackOrder] 보다 앞선다 — 면으로 짝지어 그 자리에 놓고,
         *   짝 없는 면(새로 받은 타일)은 받은 순서로 마지막 빈자리에.
         * @param rackHalfColumns 받침대 한 줄의 반 칸 수(맥 32 · 폰 22). 저장된 자리가 이 폭 밖이면 가장 가까운 빈자리로 간다.
         */
        operator fun invoke(
            table: List<List<RummyFace>>,
            rack: List<RummyFace>,
            initialDone: Boolean,
            rackOrder: List<RummyFace>? = null,
            tableLayout: RummyLayout? = null,
            rackEntries: List<RummyRackEntry>? = null,
            rackHalfColumns: Int = RummyRackLayout.halfColumnsPerRow,
        ): RummyTurnEditor {
            var nextID = 0
            val builtMelds = ArrayList<List<RummyTile>>(table.size)
            val tableIDs = HashSet<Int>()
            for (meld in table) {
                val tiles = ArrayList<RummyTile>(meld.size)
                for (face in RummyRules.displayOrder(meld)) {
                    tiles.add(RummyTile(nextID, face))
                    tableIDs.add(nextID)
                    nextID += 1
                }
                builtMelds.add(tiles)
            }
            // 받침대: 면 → 자리를 먼저 정하고, 화면 순서로 id 를 붙인다(로컬 id 규약: 랙은 화면 순).
            val placed = arrangeSlots(rack, rackOrder, rackEntries, rackHalfColumns)
            val builtRack = ArrayList<RummyTile>(placed.size)
            val layout = RummyRackLayout(rackHalfColumns)
            for ((face, slot) in placed) {
                val tile = RummyTile(nextID, face)
                builtRack.add(tile)
                layout.set(listOf(tile.id), slot)
                nextID += 1
            }
            val points = RummyTableLayout.place(table, tableLayout)
            return RummyTurnEditor(
                melds = builtMelds,
                points = points,
                rack = builtRack,
                layout = layout,
                initialDone = initialDone,
                startTable = table,
                startRack = rack,
                startMelds = builtMelds,
                startPoints = points,
                tableTileIDs = tableIDs,
                departures = emptyList(),
            )
        }

        /** 면 순서 [order] 를 따라 [rack] 을 늘어놓는다(같은 면 여럿이면 앞에서부터 하나씩 짝짓는다). 짝 없는 면은 무시, 남는 랙 면은 끝에. */
        private fun arrange(rack: List<RummyFace>, order: List<RummyFace>?): List<RummyFace> {
            if (order == null) return rack
            val remaining = rack.toMutableList()
            val arranged = ArrayList<RummyFace>(rack.size)
            for (face in order) {
                val index = remaining.indexOf(face)
                if (index >= 0) arranged.add(remaining.removeAt(index))
            }
            return arranged + remaining
        }

        /**
         * 받침대 첫 배치(면 · 자리, 화면 순서). 저장된 자리가 있으면 면으로 짝지어 그 자리(겹치면 가장 가까운 빈자리),
         * 남는 면은 받은 순서로 마지막 빈자리. 없으면 rackOrder 순으로 빈칸 없이.
         */
        private fun arrangeSlots(
            rack: List<RummyFace>,
            order: List<RummyFace>?,
            entries: List<RummyRackEntry>?,
            halfColumns: Int,
        ): List<Pair<RummyFace, RummyRackSlot>> {
            if (entries.isNullOrEmpty()) {
                val faces = arrange(rack, order)
                val layout = RummyRackLayout.packed(faces.indices.toList(), halfColumns)
                return faces.indices.map { faces[it] to layout.slot(it)!! }
            }
            val layout = RummyRackLayout(halfColumns)
            val used = BooleanArray(rack.size)
            for (entry in entries) {
                val index = rack.indices.firstOrNull { !used[it] && rack[it] == entry.face } ?: continue
                used[index] = true
                val slot = if (layout.isFree(entry.slot)) entry.slot else layout.nearestFree(entry.slot)
                layout.set(listOf(index), slot)
            }
            for (index in rack.indices) {
                if (!used[index]) layout.set(listOf(index), layout.endSlot())
            }
            return layout.readingOrder.map { rack[it] to layout.slot(it)!! }
        }

        private fun clamp(value: Int, upTo: Int): Int = minOf(maxOf(value, 0), upTo)

        /** [attachAll] 의 답 — 합친 뒤 받은 묶음 번호와 첫 붙기. */
        private class Attached(val receiving: Int, val first: RummyDropPlan?)

        /**
         * 규칙 ②: [receiving] 묶음을 닿는 이웃 끝에 붙인다 — 합친 뒤 또 닿으면 또(가운데를 메우면 양쪽이 다 붙는다).
         * 합친 묶음은 대상의 번호·점(제자리)을 잇고 답의 receiving 이 그것을 가리킨다. 첫 붙기를 돌려준다(없으면 null).
         * [fixed] 타일(첫 등록 전의 시작 판 타일 — attachFixed)이 든 묶음은 붙는 쪽도 받는 쪽도 안 된다.
         * 블록의 **끝마다 한 번만** 붙는다: 한 끝이 붙으면 그 쪽은 다 썼고, 합친 묶음의 그 바깥 끝은 대상의 반대 끝(손대지 않은
         * 이웃 자리)이다 — 자동 배치로 여백 16(붙기 거리 24 안)에 따로 서 있던 묶음까지 끌어와 합치지 않는다(3판 검증: A1-A3 · A4-A6
         * 곁에 A7 을 붙이면 A1-A7 이 되며 A4-A6 이 16 당겨지던 결함. 묶음 위에 꽂기(Meld)가 곁 이웃과 안 합치는 규칙과 같은 뜻).
         */
        private fun attachAll(pieces: MutableList<Piece>, receiving: Int, sides: List<RummyAttachSide>, fixed: Set<Int>): Attached {
            var landed = receiving
            val left = sides.toMutableList()
            var first: RummyDropPlan? = null
            fun isFixed(piece: Piece) = fixed.isNotEmpty() && piece.tiles.any { it.id in fixed }
            while (left.isNotEmpty() && !isFixed(pieces[landed])) {
                val others = pieces.indices.filter { it != landed && !isFixed(pieces[it]) }
                val hit = RummyTableEdit.attachment(
                    pieces[landed].faces,
                    pieces[landed].frame,
                    others.map { pieces[it].faces },
                    others.map { pieces[it].frame },
                    left,
                ) ?: break
                val host = others[hit.set]
                val mover = pieces[landed]
                if (first == null) first = RummyDropPlan.Attach(pieces[host].origin ?: host, hit.side)
                pieces[host].tiles = if (hit.side == RummyAttachSide.right) pieces[host].tiles + mover.tiles else mover.tiles + pieces[host].tiles
                pieces[host].point = RummyTableEdit.attachedPoint(pieces[host].point, hit.side, mover.tiles.size)
                pieces.removeAt(landed)
                landed = if (host > landed) host - 1 else host
                left.removeAll { it == hit.side }
            }
            return Attached(landed, first)
        }

        /**
         * 받은 묶음 마무리(0.3.70, RummyTableEdit ③·④): [reorder] 면 맞는 세트일 때 R-09 표시 순서로 늘어놓고(남은 타일이 가장 많이 제자리 —
         * 남은 타일이 없으면 점 그대로), 그다음 [RummyTableEdit.settle] 로 앉힌다(늘어난 장수 = 이번에 옮긴 타일 수 — 막히면 옆으로,
         * 그래도 막히면 이웃을 비켜 놓는다).
         */
        private fun finish(pieces: List<Piece>, index: Int, moving: Set<Int>, reorder: Boolean) {
            if (reorder) arrange(pieces[index], moving)
            val grown = pieces[index].tiles.count { it.id in moving }
            val settled = RummyTableEdit.settle(pieces.map { it.frame }, index, grown)
            for (i in pieces.indices) pieces[i].point = settled[i]
        }

        /**
         * 맞는 세트면 R-09 표시 순서로([RummyRules.displayOrder] — 확정 판·남의 화면과 같은 순서). 같은 면(조커 둘)은 원래 순서를 잇는다.
         * 옮기지 않은 타일이 가장 많이 화면 제자리에 남게 점을 민다(남은 토막이면 모든 타일이 '옮기지 않은' 타일이다).
         */
        private fun arrange(piece: Piece, moving: Set<Int>) {
            val faces = piece.faces
            if (!RummyRules.analyze(faces).valid) return
            val order = RummyRules.displayOrder(faces)
            if (order == faces) return
            val pool = piece.tiles.toMutableList()
            val arranged = ArrayList<RummyTile>(pool.size)
            for (face in order) {
                val at = pool.indexOfFirst { it.face == face }
                if (at < 0) return
                arranged.add(pool.removeAt(at))
            }
            // 점 밀기(타일 칸 단위): 옮기지 않은 타일이 **가장 많이 제자리**인 밀기(숫자 2 · 조커 1 — 조커는 뜻(대신하는 숫자)에 따라
            // 표시 자리가 바뀌는 타일이다). 같으면 첫 숫자 타일(없으면 첫 타일)이 제자리인 밀기 → 덜 미는 쪽 → 왼쪽. 0.3.70 검증:
            // 첫 남은 타일만 제자리로 두면 작업 중 [J A5] 에 A6 을 놓을 때 A5 · A6 이 80 왼쪽으로 튀었다(조커가 기준).
            val tiles = piece.tiles
            val kept = tiles.indices.filter { tiles[it].id !in moving }
            val newIndex = HashMap<Int, Int>()
            arranged.forEachIndexed { index, tile -> newIndex[tile.id] = index }
            fun shift(i: Int): Int = i - (newIndex[tiles[i].id] ?: i)
            val score = HashMap<Int, Int>()
            for (i in kept) score[shift(i)] = (score[shift(i)] ?: 0) + if (tiles[i].face.isJoker) 1 else 2
            val leadIndex = kept.firstOrNull { !tiles[it].face.isJoker } ?: kept.firstOrNull()
            val lead = leadIndex?.let { shift(it) }
            // Swift `max(by:)` 의 열쇠 (값, 제자리 표지, -|밀기|, -밀기) — 밀기가 서로 달라 사전 순서와 무관하게 답이 하나다.
            val best = score.entries.maxWithOrNull(
                compareBy(
                    { it.value },
                    { if (it.key == lead) 1 else 0 },
                    { -abs(it.key) },
                    { -it.key },
                ),
            )
            if (best != null) {
                piece.point = RummyPoint(piece.point.x + best.key * RummyTableLayout.tileWidth, piece.point.y)
            }
            piece.tiles = arranged
        }
    }
}
