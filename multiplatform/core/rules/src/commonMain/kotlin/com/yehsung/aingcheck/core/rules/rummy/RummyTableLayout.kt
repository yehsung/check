// 원본: Sources/CheckCore/RummyTableLayout.swift:89 @ 1a5eeca6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyLayout
import com.yehsung.aingcheck.core.wire.games.RummyPoint
import kotlin.math.abs

// 아잉 큐브 2판 — 판(테이블) 자유 배치 모델(설계서 v2 §1.1 · §2.1).
//
// 논리 캔버스는 1000×640 단위, 타일 한 장은 40×56 단위, 묶음(세트)은 가로 한 줄(회전 없음)이다.
// 위치 = 묶음 **왼쪽 위** `[x, y]` 정수. 서버는 겹침·폭을 따지지 않고 범위만 정리한다(배치는 꾸밈) — 겹치지 않게 놓는 것은
// 클라 몫이고, 그 규칙(자동 배치 · 놓기 스냅 · 길이 변화)은 **모든 클라가 같은 결과**를 내야 한다(남의 작업 판·확정 판의
// 빈 자리를 저마다 채운다). 그래서 여기 함수는 전부 결정적이다: 부동소수 없음, 정렬 키는 내용(면) → 원래 번호. 골든 `rummy/table-layout`.
//
// 겹침 판정은 **여백([RummyTableLayout.clearance]) 16 단위**를 둔다 — 딱 붙은 두 묶음이 한 묶음으로 읽히지 않게. 격자는 8 단위.
//
// [RummyPoint]·[RummyLayout](느슨한 디코드)는 core/wire 한 벌이다. 좌표는 그 와이어 타입을 따라 `Long` 이고 장수·번호는 `Int` 다.

/** 판 위 사각형(논리 단위). 오른쪽·아래 끝은 열린 구간이다([maxX] 는 포함하지 않는다). */
data class RummyRect(val x: Long, val y: Long, val width: Long, val height: Long) {
    val maxX: Long get() = x + width
    val maxY: Long get() = y + height
    val origin: RummyPoint get() = RummyPoint(x, y)

    fun contains(point: RummyPoint): Boolean = point.x >= x && point.x < maxX && point.y >= y && point.y < maxY
}

/** 판 하나의 배치(묶음마다 장수와 왼쪽 위 점). 값 자체가 결정적 자동 배치의 결과다 — 같은 입력이면 어느 기기든 같다. */
data class RummyTableLayout(
    /** 묶음마다 장수(판 순서). */
    val counts: List<Int>,
    /** 묶음마다 왼쪽 위 점(판 순서, [counts] 와 같은 길이). */
    val points: List<RummyPoint>,
) {
    init {
        require(counts.size == points.size) { "counts/points 길이" }
    }

    /** 와이어 판 + 와이어 배치 → 빈 자리를 채운 배치([place]). */
    constructor(sets: List<List<RummyFace>>, layout: RummyLayout?) : this(sets.map { it.size }, place(sets, layout))

    /** 묶음 [setIndex] 의 사각형. 없는 번호면 null. */
    fun frame(setIndex: Int): RummyRect? =
        if (setIndex in points.indices) frame(points[setIndex], counts[setIndex]) else null

    val frames: List<RummyRect> get() = points.indices.map { frame(points[it], counts[it]) }

    /** 한 점을 덮는 묶음(뒤에 놓인 것이 위 — 마지막부터 찾는다). 화면의 누르기 판정용. */
    fun setIndex(at: RummyPoint): Int? = frames.indexOfLast { it.contains(at) }.takeIf { it >= 0 }

    /** 묶음 안 [tileIndex] 번째 타일의 사각형(판 좌표). */
    fun tileFrame(set: Int, tile: Int): RummyRect? {
        val frame = frame(set) ?: return null
        if (tile !in 0 until counts[set]) return null
        return RummyRect(frame.x + tile * tileWidth, frame.y, tileWidth, tileHeight)
    }

    /**
     * [tiles] 장짜리 묶음을 [point] 가까이 놓을 때의 자리(가장 가까운 빈자리, 8 단위 격자). [excluding] 은 장애물에서 뺄 묶음
     * (자기 자신을 옮길 때). 화면은 놓는 순간 한 번 부른다(끄는 동안 미리보기에 써도 된다 — 줄당 O(묶음 수)).
     */
    fun snap(point: RummyPoint, tiles: Int, excluding: Int? = null): RummyPoint =
        snap(point, tiles, obstacles(excluding))

    private fun obstacles(excluding: Int?): List<RummyRect> = frames.filterIndexed { i, _ -> i != excluding }

    companion object {
        // MARK: 상수(설계서 v2 §1.1)

        const val canvasWidth: Long = RummyPoint.CANVAS_WIDTH
        const val canvasHeight: Long = RummyPoint.CANVAS_HEIGHT
        const val tileWidth: Long = 40
        const val tileHeight: Long = 56

        /** 자동 배치·스냅 격자(단위). */
        const val grid: Long = 8

        /** 두 묶음 사이 최소 여백(단위). 이보다 가까우면 "겹침"이다. */
        const val clearance: Long = 16

        val empty = RummyTableLayout(emptyList(), emptyList<RummyPoint>())

        // MARK: - 정적 규칙

        /** 서버 정리 규칙과 같은 범위: 0 ≤ x ≤ 1000, 0 ≤ y ≤ 640. */
        fun acceptsWire(x: Long, y: Long): Boolean = x in 0..canvasWidth && y in 0..canvasHeight

        fun width(tiles: Int): Long = maxOf(tiles, 1) * tileWidth

        fun frame(at: RummyPoint, tiles: Int): RummyRect = RummyRect(at.x, at.y, width(tiles), tileHeight)

        /** 캔버스 안에 통째로 들어가는가. */
        fun fits(frame: RummyRect): Boolean =
            frame.x >= 0 && frame.y >= 0 && frame.maxX <= canvasWidth && frame.maxY <= canvasHeight

        /** 두 묶음이 여백([clearance]) 안으로 들어오는가 — 붙어 보이면 겹침이다. */
        fun overlaps(a: RummyRect, b: RummyRect): Boolean =
            a.x < b.maxX + clearance && a.maxX + clearance > b.x && a.y < b.maxY + clearance && a.maxY + clearance > b.y

        /** 캔버스 안이고 어느 장애물과도 안 겹친다. */
        fun isClear(frame: RummyRect, among: List<RummyRect>): Boolean = fits(frame) && among.none { overlaps(frame, it) }

        /** 와이어 배치를 묶음 수에 맞춘다: 없거나 길이가 다르면 전부 null(서버 규칙), 아니면 그대로. */
        fun sanitize(layout: RummyLayout?, setCount: Int): List<RummyPoint?> =
            if (layout == null || layout.points.size != setCount) List(setCount) { null } else layout.points

        /**
         * 서버 정리는 왼쪽 위 점만 범위(0…1000·0…640)로 본다 — `[999,640]` 도 통과한다(v2 실출력 `state_with_layout`).
         * 그대로 그리면 묶음이 판 밖에 놓여 안 보이므로, 묶음이 캔버스를 넘으면 **안으로 당긴다**(오른쪽·아래 끝에 붙인다).
         * 같은 입력이면 어느 기기든 같은 답이다.
         */
        fun clampInside(point: RummyPoint, tiles: Int): RummyPoint {
            val w = width(tiles)
            return RummyPoint(
                minOf(maxOf(point.x, 0L), maxOf(canvasWidth - w, 0L)),
                minOf(maxOf(point.y, 0L), canvasHeight - tileHeight),
            )
        }

        /**
         * **결정적 자동 배치.** 주어진 점은 그대로 두고(겹쳐 있어도 — 남이 놓은 자리다), null 자리만 채운다:
         * 기존 묶음과 안 겹치는 첫 자리(행 우선 스캔, 8 단위 격자). 채우는 차례는 **내용 순**(긴 묶음 먼저 → 면 글자 → 원래 번호)이라
         * 묶음 순서를 섞어 넣어도 각 묶음이 받는 자리는 같다(같은 면의 묶음 둘은 서로 바뀔 수 있지만 보이는 판은 같다).
         */
        fun place(sets: List<List<RummyFace>>, layout: RummyLayout?): List<RummyPoint> {
            val counts = sets.map { it.size }
            val given = sanitize(layout, sets.size).mapIndexed { index, point -> point?.let { clampInside(it, counts[index]) } }
            val obstacles = ArrayList<RummyRect>()
            given.forEachIndexed { index, point -> if (point != null) obstacles.add(frame(point, counts[index])) }
            val missing = given.indices.filter { given[it] == null }
            // 면 글자는 ASCII 뿐이라 Swift `String.<` 과 Kotlin `compareTo` 가 같은 순서다.
            val keys = sets.map { set -> RummyRules.compareKey(set).joinToString(" ") { it.text } }
            val order = missing.sortedWith { a, b ->
                when {
                    counts[a] != counts[b] -> counts[b].compareTo(counts[a])
                    keys[a] != keys[b] -> keys[a].compareTo(keys[b])
                    else -> a.compareTo(b)
                }
            }
            val result = given.toMutableList()
            for (index in order) {
                val point = firstFree(counts[index], obstacles)
                result[index] = point
                obstacles.add(frame(point, counts[index]))
            }
            return result.map { it ?: RummyPoint(0, 0) }
        }

        /**
         * 행 우선 스캔(위 → 아래, 왼 → 오른, 8 단위)으로 처음 나오는 빈 자리. 판이 꽉 찼으면 여백 없이 한 번 더,
         * 그래도 없으면 왼쪽 아래 구석(겹쳐도 — 판 밖으로는 안 나간다).
         */
        fun firstFree(tiles: Int, among: List<RummyRect>): RummyPoint {
            val w = width(tiles)
            for (gap in listOf(clearance, 0L)) {
                for (y in rowStarts) {
                    val x = nearestFreeX(y, w, 0L, among, gap)
                    if (x != null) return RummyPoint(x, y)
                }
            }
            return RummyPoint(0, rowStarts.last())
        }

        /** 놓기 스냅: [point] 에서 가장 가까운(유클리드) 빈 격자점. 같으면 위 → 왼쪽. 빈 곳이 없으면 [firstFree] 와 같은 대체. */
        fun snap(point: RummyPoint, tiles: Int, among: List<RummyRect>): RummyPoint =
            freeSpot(point, tiles, among) ?: firstFree(tiles, among)

        /**
         * [snap] 의 빈자리 찾기만(0.3.70) — 여백 16 → 여백 0 순으로 [point] 에서 가장 가까운 빈 격자점, **없으면 null**(구석으로 안 보낸다).
         * 편집기가 판이 꽉 찼을 때 구석에 겹쳐 놓는 대신 이웃을 비켜 놓으려고 쓴다([RummyTableEdit.settle]). [place] 는 안 쓴다.
         */
        fun freeSpot(point: RummyPoint, tiles: Int, among: List<RummyRect>): RummyPoint? {
            val w = width(tiles)
            for (gap in listOf(clearance, 0L)) {
                var bestDistance: Long? = null
                var bestPoint: RummyPoint? = null
                for (y in rowStarts) {
                    val x = nearestFreeX(y, w, point.x, among, gap) ?: continue
                    val dx = x - point.x
                    val dy = y - point.y
                    val distance = dx * dx + dy * dy
                    if (bestDistance == null || distance < bestDistance) {
                        bestDistance = distance
                        bestPoint = RummyPoint(x, y)
                    }
                }
                if (bestPoint != null) return bestPoint
            }
            return null
        }

        /** 길이가 바뀐 묶음의 새 자리: 지금 자리에서 오른쪽으로 늘어난 사각형이 들어가면 그대로, 막히면(판 밖·겹침) 가장 가까운 빈자리. */
        fun refit(point: RummyPoint, tiles: Int, among: List<RummyRect>): RummyPoint =
            if (isClear(frame(point, tiles), among)) point else snap(point, tiles, among)

        /** 격자 행의 y 들(0, 8, … , 640 − 56 이하). */
        private val rowStarts: List<Long> = (0L..(canvasHeight - tileHeight) step grid).toList()

        // Swift 는 `Double` 나눗셈 뒤 내림·올림이다. 격자 8 은 2의 거듭제곱이고 값이 수천이라 나눗셈이 정확해 정수 내림과 같다.
        private fun floorGrid(v: Long): Long = v.floorDiv(grid) * grid

        private fun ceilGrid(v: Long): Long = -((-v).floorDiv(grid)) * grid

        /**
         * 한 행(y)에서 폭 [w] 묶음이 놓일 수 있는 격자 x 중 [near] 에 가장 가까운 것(같으면 작은 쪽). 없으면 null.
         * 막힌 x 는 장애물마다 열린 구간 (ox − gap − w, ox + ow + gap) 이다 — 빈 x 의 최근접점은 [near] 의 격자 반올림이거나
         * 막힌 구간 바로 바깥의 격자점이므로 그 후보만 대 본다(줄당 O(장애물²), 장애물 ≤ 수십).
         */
        private fun nearestFreeX(y: Long, w: Long, near: Long, among: List<RummyRect>, gap: Long): Long? {
            val maxX = canvasWidth - w
            if (maxX < 0) return null
            val rowTop = y
            val rowBottom = y + tileHeight
            // 막힌 x 의 닫힌 구간 [lo, hi].
            val blockedLo = ArrayList<Long>()
            val blockedHi = ArrayList<Long>()
            for (other in among) {
                if (rowTop < other.maxY + gap && rowBottom + gap > other.y) {
                    blockedLo.add(other.x - gap - w + 1)
                    blockedHi.add(other.maxX + gap - 1)
                }
            }
            fun free(x: Long): Boolean {
                if (x < 0 || x > maxX) return false
                for (i in blockedLo.indices) if (x >= blockedLo[i] && x <= blockedHi[i]) return false
                return true
            }
            val lastGrid = floorGrid(maxX)
            val candidates = ArrayList<Long>(4 + blockedLo.size * 2)
            candidates.add(floorGrid(near))
            candidates.add(ceilGrid(near))
            candidates.add(0L)
            candidates.add(lastGrid)
            for (i in blockedLo.indices) {
                candidates.add(floorGrid(blockedLo[i] - 1))
                candidates.add(ceilGrid(blockedHi[i] + 1))
            }
            var best: Long? = null
            for (raw in candidates) {
                val x = minOf(maxOf(raw, 0L), lastGrid)
                if (!free(x)) continue
                val current = best
                if (current != null) {
                    val d = abs(x - near)
                    val dc = abs(current - near)
                    if (d < dc || (d == dc && x < current)) best = x
                } else {
                    best = x
                }
            }
            return best
        }
    }
}
