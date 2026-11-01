// 원본: Sources/check/RummyTableCanvas.swift:11 (RummyCanvasTransform — zoom 은 1cbaa4d1 의 세로 가운데 값) · Sources/check/RummyPanelMatch.swift:124 (RummyDropResolver) ·
//       Sources/check/RummyRackView.swift:12,70 (RummyRackGeometry · motionKeys) · Sources/check/RummyArt.swift:27 (RummyRackArtMetrics) @ 1a5eeca6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.rules.format.roundedHalfAwayFromZero
import com.yehsung.aingcheck.core.wire.games.RummyPoint
import kotlin.math.abs

// 아잉 큐브 판 캔버스 변환 · 놓을 자리 판정 — 맥 화면 파일(SwiftUI)에 있던 순수 계산만 옮겼다(플랫폼 타입 CGFloat·CGRect 는 Double 값 타입으로).
//
// 판은 논리 캔버스 1000×640(타일 40×56, [RummyTableLayout])이고, 위치는 모두에게 같다(서버 table_layout).
// 화면은 그 캔버스를 테이블 칸에 **비율 유지로 맞춘다**([RummyCanvasTransform.fit]). 확대는 놓인 묶음을 다 담는 사각형(+ 여백)에 맞춰 크게 본다
// ([RummyCanvasTransform.zoom] — 묶음은 하나도 안 잘린다). 그리는 자리·누르는 자리·놓는 자리가 이 한 변환에서 나온다.
//
// 실수 계산은 화면 몫이라 골든이 아니다(모든 기기가 같아야 하는 값은 놓은 뒤 [RummyDropResolver.clampedTopLeft] 가 반올림한 정수 점이다).
// 1cbaa4d1(rummy 가지 — 이 저장소 Swift 에는 아직 없다) 때문에 [RummyCanvasTransform.zoom] 의 세로만 지금 Swift 와 다르다.
// [RummyMatchRegions] 는 맥 RummyMatchLayout 의 칸 둘(받침대 · 판)만 받는다 — 폰 배치는 화면 단계가 정한다.

/** 화면 좌표 한 점(Swift `CGPoint`). */
data class RummyCanvasPoint(val x: Double, val y: Double)

/** 크기(Swift `CGSize`). */
data class RummyCanvasSize(val width: Double, val height: Double)

/** 화면 좌표 사각형(Swift `CGRect` 가운데 이 파일이 쓰는 만큼). */
data class RummyCanvasRect(val x: Double, val y: Double, val width: Double, val height: Double) {
    val maxX: Double get() = x + width
    val maxY: Double get() = y + height
    val midX: Double get() = x + width / 2
    val midY: Double get() = y + height / 2

    /** Swift `CGRect.contains`(오른쪽·아래 끝은 열린 구간). */
    fun contains(point: RummyCanvasPoint): Boolean = point.x >= x && point.x < maxX && point.y >= y && point.y < maxY

    fun union(other: RummyCanvasRect): RummyCanvasRect {
        val left = minOf(x, other.x)
        val top = minOf(y, other.y)
        return RummyCanvasRect(left, top, maxOf(maxX, other.maxX) - left, maxOf(maxY, other.maxY) - top)
    }

    /** Swift `CGRect.insetBy` — 음수면 넓힌다. */
    fun insetBy(dx: Double, dy: Double): RummyCanvasRect = RummyCanvasRect(x + dx, y + dy, width - dx * 2, height - dy * 2)

    /** Swift `CGRect.intersection` — 안 겹치면 `CGRect.null`(원점 무한대 · 크기 0). */
    fun intersection(other: RummyCanvasRect): RummyCanvasRect {
        val left = maxOf(x, other.x)
        val top = maxOf(y, other.y)
        val right = minOf(maxX, other.maxX)
        val bottom = minOf(maxY, other.maxY)
        if (left >= right || top >= bottom) return RummyCanvasRect(Double.POSITIVE_INFINITY, Double.POSITIVE_INFINITY, 0.0, 0.0)
        return RummyCanvasRect(left, top, right - left, bottom - top)
    }
}

/** 논리 캔버스 ↔ 테이블 칸 좌표(테이블 칸 왼쪽 위 원점). 순수 값. */
data class RummyCanvasTransform(
    val scale: Double,
    /** 화면 원점(테이블 칸 좌표)에 오는 논리 점. */
    val logicalOrigin: RummyCanvasPoint,
    /** 그 논리 점이 놓이는 테이블 칸 좌표. */
    val screenOrigin: RummyCanvasPoint,
) {
    fun toScreen(p: RummyCanvasPoint): RummyCanvasPoint =
        RummyCanvasPoint(screenOrigin.x + (p.x - logicalOrigin.x) * scale, screenOrigin.y + (p.y - logicalOrigin.y) * scale)

    fun toLogical(p: RummyCanvasPoint): RummyCanvasPoint =
        RummyCanvasPoint(logicalOrigin.x + (p.x - screenOrigin.x) / scale, logicalOrigin.y + (p.y - screenOrigin.y) / scale)

    fun rect(r: RummyRect): RummyCanvasRect {
        val o = toScreen(RummyCanvasPoint(r.x.toDouble(), r.y.toDouble()))
        return RummyCanvasRect(o.x, o.y, r.width.toDouble() * scale, r.height.toDouble() * scale)
    }

    companion object {
        val canvas = RummyCanvasSize(RummyTableLayout.canvasWidth.toDouble(), RummyTableLayout.canvasHeight.toDouble())

        /** 캔버스 전체를 칸 가운데에 비율 유지로. */
        fun fit(viewport: RummyCanvasSize, inset: Double = 6.0): RummyCanvasTransform {
            val w = maxOf(1.0, viewport.width - inset * 2)
            val h = maxOf(1.0, viewport.height - inset * 2)
            val scale = minOf(w / canvas.width, h / canvas.height)
            return RummyCanvasTransform(
                scale,
                RummyCanvasPoint(0.0, 0.0),
                RummyCanvasPoint((viewport.width - canvas.width * scale) / 2, (viewport.height - canvas.height * scale) / 2),
            )
        }

        /**
         * 놓인 묶음을 다 담는 사각형(+ 가로 두 장·세로 한 줄 여백)에 맞춰 확대. 배율은 [전체 맞춤, maxScale] 사이.
         * 묶음이 없으면 캔버스 왼쪽 위 1/4 를 본다. 가로 구간은 되도록 캔버스 안으로 민다.
         * 세로는 묶음을 칸 가운데에 둔다(사용자 10-31 "다음 판에 세로 가운데로" — 위 줄부터 채우는 판이 위로 붙어 아래가 비었다).
         * 그래서 구간이 캔버스 위·아래로 나갈 수 있다 — 거기 놓아도 편집기 clampInside 가 캔버스 안으로 들인다.
         * 여백 20: 판 확대가 기본이 되며 캔버스 왼끝(x 0) 묶음의 손잡이(묶음 왼쪽 13 단위 밖)가 판 테두리에 잘렸다.
         */
        fun zoom(viewport: RummyCanvasSize, content: List<RummyRect>, inset: Double = 20.0, maxScale: Double = 1.0): RummyCanvasTransform {
            val base = fit(viewport, inset)
            val bounds = content.map { cg(it) }.reduceOrNull { a, b -> a.union(b) }
            var region = if (bounds != null) {
                bounds.insetBy(-RummyTableLayout.tileWidth.toDouble() * 2, -RummyTableLayout.tileHeight.toDouble() * 1.3)
            } else {
                RummyCanvasRect(0.0, 0.0, canvas.width / 2, canvas.height / 2)
            }
            region = region.intersection(RummyCanvasRect(0.0, 0.0, canvas.width, canvas.height))
            val w = maxOf(1.0, viewport.width - inset * 2)
            val h = maxOf(1.0, viewport.height - inset * 2)
            val scale = maxOf(base.scale, minOf(maxScale, w / maxOf(region.width, 1.0), h / maxOf(region.height, 1.0)))
            // 묶음이 판 전체에 퍼져 확대할 것이 없으면 그냥 전체 맞춤(여백 6 — 맞춤과 같은 크기).
            if (scale <= base.scale + 0.0001) return fit(viewport)
            // 칸 안쪽(여백 뺀) 구간이 보이는 논리 폭. 여백만큼은 펠트만 보인다(묶음이 칸 테두리에 붙지 않게).
            val spanW = w / scale
            val spanH = h / scale
            fun clampOrigin(center: Double, span: Double, limit: Double): Double {
                val start = center - span / 2
                if (span >= limit) return (limit - span) / 2
                return minOf(maxOf(start, 0.0), limit - span)
            }
            val origin = RummyCanvasPoint(
                clampOrigin(region.midX, spanW, canvas.width),
                bounds?.let { it.midY - spanH / 2 } ?: clampOrigin(region.midY, spanH, canvas.height),
            )
            return RummyCanvasTransform(scale, origin, RummyCanvasPoint(inset, inset))
        }

        private fun cg(r: RummyRect) = RummyCanvasRect(r.x.toDouble(), r.y.toDouble(), r.width.toDouble(), r.height.toDouble())
    }
}

/** 맥 `RummyRackArtMetrics` — 받침대 그림 기준선(비율 값). */
object RummyRackArtMetrics {
    /** 뒷줄 타일 바닥 · 앞줄 타일 바닥(H 대비). */
    const val backRowBottom: Double = 0.44
    const val frontRowBottom: Double = 0.76

    /** 타일 높이(H 대비). */
    const val tileHeight: Double = 0.31

    /** 원본 가로/세로. */
    const val naturalAspect: Double = 2400.0 / 478.0

    /** 타일이 놓이는 가로 구간(원본 폭 대비 7%~93%) → 높이 H 일 때 좌우 안쪽 여백. */
    const val tileSpanStart: Double = 0.07

    /** 3-슬라이스 끝캡(원본 2400 기준 좌우 약 150px). */
    const val capFraction: Double = 150.0 / 2400.0

    /** 타일 높이 [tile] 에 맞는 받침대 높이. */
    fun height(tile: Double): Double = roundedHalfAwayFromZero(tile / tileHeight)

    /** 높이 H 받침대의 타일 구간 좌우 여백. */
    fun sideInset(height: Double): Double = tileSpanStart * naturalAspect * height

    /** 높이 H 받침대의 끝캡 폭. */
    fun capWidth(height: Double): Double = capFraction * naturalAspect * height
}

/** 놓기 판정이 받침대에 묻는 두 가지 — 폰은 그림 기준선 없이 칸 폭으로 잰 기하를 넘긴다(ui GamesRummyRackGeometry · 맥 산식은 [RummyRackGeometry]). */
interface RummyRackDropGeometry {
    /** 놓는 타일 폭. */
    val dropTileWidth: Double

    /** 놓을 자리: 맨 왼쪽 타일의 왼쪽 끝 x · 손의 y → 가장 가까운 반 칸과 줄(받침대 안으로 자른다). */
    fun slot(tileLeft: Double, centerY: Double, tiles: Int): RummyRackSlot
}

/** 받침대 기하(받침대 칸 왼쪽 위 원점). 순수 값. */
data class RummyRackGeometry(
    val tile: RummyCanvasSize = standardTile,
    val height: Double = standHeight(tile),
    val requestedRowCount: Int = RummyRackLayout.baseRows,
) : RummyRackDropGeometry {
    val rowCount: Int = maxOf(RummyRackLayout.baseRows, requestedRowCount)

    /** 줄이 넘치면 타일을 줄인다(2줄 = 1). */
    val tileScale: Double get() = if (rowCount <= 2) 1.0 else 2.0 / rowCount.toDouble()
    val tileSize: RummyCanvasSize get() = RummyCanvasSize(tile.width * tileScale, tile.height * tileScale)
    val sideInset: Double get() = RummyRackArtMetrics.sideInset(height)
    val halfPitch: Double get() = tileSize.width / RummyRackLayout.tileSpan.toDouble()
    override val dropTileWidth: Double get() = tileSize.width

    fun rowBottom(row: Int): Double {
        if (rowCount <= 2) return (if (row <= 0) RummyRackArtMetrics.backRowBottom else RummyRackArtMetrics.frontRowBottom) * height
        val top = (RummyRackArtMetrics.backRowBottom - RummyRackArtMetrics.tileHeight) * height
        val bottom = RummyRackArtMetrics.frontRowBottom * height
        return top + (row + 1).toDouble() * (bottom - top) / rowCount.toDouble()
    }

    fun rowCenter(row: Int): Double = rowBottom(row) - tileSize.height / 2

    fun frame(slot: RummyRackSlot): RummyCanvasRect = RummyCanvasRect(
        sideInset + slot.halfCol.toDouble() * halfPitch,
        rowBottom(slot.row) - tileSize.height,
        tileSize.width,
        tileSize.height,
    )

    override fun slot(tileLeft: Double, centerY: Double, tiles: Int): RummyRackSlot {
        val maxHalf = maxOf(0, RummyRackLayout.halfColumnsPerRow - RummyRackLayout.tileSpan * maxOf(1, tiles))
        val half = roundedHalfAwayFromZero((tileLeft - sideInset) / halfPitch).toInt()
        val row = (0 until rowCount).minByOrNull { abs(rowCenter(it) - centerY) } ?: 0
        return RummyRackSlot(row, minOf(maxOf(half, 0), maxHalf))
    }

    companion object {
        /** 맥 `RummyTileSize.rack`. */
        val standardTile = RummyCanvasSize(36.0, 50.0)

        /** 받침대 높이 = 타일 높이 / 0.31(세로로 늘이지 않는다). */
        fun standHeight(tile: RummyCanvasSize): Double = RummyRackArtMetrics.height(tile.height)

        /**
         * 받침대 타일의 모션 키 — 면 글자 + 같은 면 순번(id 순). 차례가 바뀌어 편집기가 새 id 를 붙여도 같은 타일이 같은 뷰로 남아
         * 제자리에서 부드럽게 옮겨진다.
         */
        fun motionKeys(tiles: List<RummyTile>): Map<Int, String> {
            val seen = HashMap<String, Int>()
            val keys = HashMap<Int, String>()
            for (tile in tiles.sortedBy { it.id }) {
                val text = tile.face.text
                val n = seen[text] ?: 0
                seen[text] = n + 1
                keys[tile.id] = "$text#$n"
            }
            return keys
        }
    }
}

/** 놓기가 보는 칸 둘(판 화면 좌표). 맥 `RummyMatchLayout.rack` · `.table`. */
data class RummyMatchRegions(val rack: RummyCanvasRect, val table: RummyCanvasRect)

/** 놓을 자리 판정(순수). 재료는 칸 자리·변환·배치와 "내 차례인가" 뿐이다 — 놓아도 되는가는 편집기·서버가 정한다. */
object RummyDropResolver {
    /** 판 묶음 누르기 여유(논리 단위) — 묶음 사이 틈(16)의 반 남짓. */
    val meldSlack = RummyCanvasSize(10.0, 10.0)

    /**
     * 타일 묶음([count] 장, 손에 [grabIndex] 번째)을 [pointer](판 화면 좌표)에 놓으면.
     * [skipMeld] = 묶음 하나를 통째로 끄는 중이면 그 묶음(자기 위에 놓기 = 위치 이동으로 본다).
     */
    fun target(
        pointer: RummyCanvasPoint,
        grabIndex: Int,
        count: Int,
        layout: RummyMatchRegions,
        canvas: RummyCanvasTransform,
        table: RummyTableLayout,
        rack: RummyRackDropGeometry,
        isMyTurn: Boolean,
        skipMeld: Int? = null,
    ): RummyDropTarget? {
        if (layout.rack.contains(pointer)) {
            val localX = pointer.x - layout.rack.x
            val localY = pointer.y - layout.rack.y
            val left = localX - (grabIndex.toDouble() + 0.5) * rack.dropTileWidth
            return RummyDropTarget.RackSlot(rack.slot(left, localY, count))
        }
        if (!isMyTurn || !layout.table.contains(pointer)) return null
        val logical = canvas.toLogical(RummyCanvasPoint(pointer.x - layout.table.x, pointer.y - layout.table.y))
        table.frames.forEachIndexed { index, frame ->
            if (index == skipMeld) return@forEachIndexed
            val zone = RummyCanvasRect(frame.x.toDouble(), frame.y.toDouble(), frame.width.toDouble(), frame.height.toDouble())
                .insetBy(-meldSlack.width, -meldSlack.height)
            if (!zone.contains(logical)) return@forEachIndexed
            var at = 0
            for (tile in 0 until table.counts[index]) {
                val f = table.tileFrame(index, tile)
                if (f != null && f.x.toDouble() + f.width.toDouble() / 2 < logical.x) at += 1
            }
            return RummyDropTarget.Meld(index, at)
        }
        val w = RummyTableLayout.tileWidth.toDouble()
        val h = RummyTableLayout.tileHeight.toDouble()
        return RummyDropTarget.NewMeldAt(
            clampedTopLeft(RummyCanvasPoint(logical.x - (grabIndex.toDouble() + 0.5) * w, logical.y - h / 2), count),
        )
    }

    /** 손잡이로 묶음을 끌어 [pointer] 에 놓으면 — 판 위면 새 왼쪽 위(잡은 자리 오프셋 [grab] 을 뺀다), 밖이면 null. */
    fun setTarget(
        pointer: RummyCanvasPoint,
        grab: RummyCanvasPoint,
        tiles: Int,
        layout: RummyMatchRegions,
        canvas: RummyCanvasTransform,
    ): RummyPoint? {
        if (!layout.table.contains(pointer)) return null
        val logical = canvas.toLogical(RummyCanvasPoint(pointer.x - layout.table.x, pointer.y - layout.table.y))
        return clampedTopLeft(RummyCanvasPoint(logical.x - grab.x, logical.y - grab.y), tiles)
    }

    fun clampedTopLeft(p: RummyCanvasPoint, tiles: Int): RummyPoint {
        val maxX = RummyTableLayout.canvasWidth - RummyTableLayout.width(tiles)
        val maxY = RummyTableLayout.canvasHeight - RummyTableLayout.tileHeight
        return RummyPoint(
            minOf(maxOf(roundedHalfAwayFromZero(p.x).toLong(), 0L), maxOf(0L, maxX)),
            minOf(maxOf(roundedHalfAwayFromZero(p.y).toLong(), 0L), maxOf(0L, maxY)),
        )
    }
}
