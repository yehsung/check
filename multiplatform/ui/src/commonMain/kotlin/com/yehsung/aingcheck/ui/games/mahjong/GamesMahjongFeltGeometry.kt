// 원본: Sources/CheckMobileKit/Games/GamesMahjongFeltGeometry.swift @ 928d5562(펠트 884×502 배치 · 강 바람개비 · 상대 손 띠 · 가로 판 칸) — Android 판 8
//
// 펠트 좌표 · 강 · 손 띠 · 가운데 판 자리는 맥 `MahjongMatchLayout` · `MahjongTableGeometry` 를 글자 그대로 옮긴 아이폰 값과 같다 —
// 같은 서버 판을 세 기기가 다른 자리로 그리지 않게. 폰은 이 펠트 한 장을 가로 화면에 맞춰 통째로 줄여 그린다(feltScale).
// 좌표 단위는 펠트 점(= iOS pt). 화면 좌표(dp)로 옮길 때 feltScale 을 곱한다.
package com.yehsung.aingcheck.ui.games.mahjong

import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import com.yehsung.aingcheck.core.rules.mahjong.MahjongCompass
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileArtModel
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileFace
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileSize
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileState
import com.yehsung.aingcheck.core.stores.mahjong.MahjongDiscard
import com.yehsung.aingcheck.core.stores.mahjong.MahjongWireMeld

/** 띠 한 장에 놓을 패 하나(펠트 좌표 — 원래 크기). */
data class GamesMahjongStripTile(
    val face: MahjongTileFace,
    val size: MahjongTileSize,
    val state: MahjongTileState = MahjongTileState.normal,
    val rotation: Int = 0,
    val originX: Float,
    val originY: Float,
) {
    /** 회전을 반영한 사각형. */
    val rect: Rect
        get() {
            val s = mahjongImageSize(size, rotation)
            return Rect(originX, originY, originX + s.width, originY + s.height)
        }
}

object GamesMahjongFeltLayout {
    val felt = Rect(0f, 0f, 884f, 502f)
    const val feltInset = 4f
    const val handStrip = 32f
    const val gap = 4f
    const val centerSide = 162f
    val riverTile: Size get() = Size(MahjongTileSize.discard.width, MahjongTileSize.discard.height)
    val riverDepth: Float get() = riverTile.height * 3
    const val riverWorstCount = 27

    /** 가운데 판 — (361, 188, 162, 162). */
    val center: Rect
        get() {
            val x = (felt.width - centerSide) / 2
            val y = feltInset + handStrip + gap + riverDepth + gap
            return Rect(x, y, x + centerSide, y + centerSide)
        }

    fun riverMaxRows(compass: MahjongCompass): Int = if (compass == MahjongCompass.left || compass == MahjongCompass.right) 4 else 3

    /** 방위별 강 칸. 아래 (361, 354, 483, 144) · 위 (40, 40, 483, 144) · 왼쪽 (165, 188, 192, 310) · 오른쪽 (527, 40, 192, 310). */
    fun riverLane(compass: MahjongCompass): Rect {
        val c = center
        val edge = feltInset + handStrip + gap
        val rows = riverTile.height * riverMaxRows(compass)
        return when (compass) {
            MahjongCompass.bottom -> Rect(c.left, c.bottom + gap, c.left + (felt.width - edge - c.left), c.bottom + gap + rows)
            MahjongCompass.top -> Rect(edge, c.top - gap - rows, edge + (c.right - edge), c.top - gap)
            MahjongCompass.right -> Rect(c.right + gap, edge, c.right + gap + rows, edge + (c.bottom - edge))
            MahjongCompass.left -> Rect(c.left - gap - rows, c.top, c.left - gap, c.top + (felt.height - feltInset - c.top))
        }
    }

    /** 강 한 줄에 놓을 수 있는 장수(위아래 13 · 좌우 8). */
    fun riverLaneTiles(compass: MahjongCompass): Int {
        val lane = riverLane(compass)
        val along = if (compass == MahjongCompass.top || compass == MahjongCompass.bottom) lane.width else lane.height
        return ((along - (riverTile.height - riverTile.width)) / riverTile.width).toInt()
    }

    const val sideStripEndInset = 10f

    /** 상대 손 띠. 나(아래)는 없다. 위 (40, 4, 804, 32) · 왼쪽 (4, 10, 32, 482) · 오른쪽 (848, 10, 32, 482). */
    fun handStripRect(compass: MahjongCompass): Rect? {
        val edge = feltInset + handStrip + gap
        val sideLength = felt.height - sideStripEndInset * 2
        return when (compass) {
            MahjongCompass.bottom -> null
            MahjongCompass.top -> Rect(edge, feltInset, felt.width - edge, feltInset + handStrip)
            MahjongCompass.left -> Rect(feltInset, sideStripEndInset, feltInset + handStrip, sideStripEndInset + sideLength)
            MahjongCompass.right -> Rect(felt.width - feltInset - handStrip, sideStripEndInset, felt.width - feltInset, sideStripEndInset + sideLength)
        }
    }
}

object GamesMahjongFeltGeometry {
    val riverTile = MahjongTileSize.discard
    const val rowLength = 6

    /** 줄마다 패 수(판 쪽 줄부터). 6 · 6 · 나머지 — 넘치면 줄 수 한도 안에서 고르게 늘린다. */
    fun riverRowCounts(count: Int, compass: MahjongCompass): List<Int> {
        val lane = GamesMahjongFeltLayout.riverLaneTiles(compass)
        val rows = GamesMahjongFeltLayout.riverMaxRows(compass)
        val caps = listOf(rowLength, rowLength) + List(rows - 2) { lane }
        val widened = if (count > caps.sum()) caps.map { maxOf(it, (count + rows - 1) / rows) } else caps
        var left = maxOf(0, count)
        val out = mutableListOf<Int>()
        for (cap in widened) {
            if (left <= 0) break
            out += minOf(cap, left)
            left -= minOf(cap, left)
        }
        return out
    }

    /** 한 자리의 강 패들. highlightLast 면 마지막 패(울려 가지 않았으면)를 강조한다. */
    fun river(discards: List<MahjongDiscard>, compass: MahjongCompass, highlightLast: Boolean = false): List<GamesMahjongStripTile> {
        val rect = GamesMahjongFeltLayout.riverLane(compass)
        val w = riverTile.width
        val h = riverTile.height
        val base = MahjongTileArtModel.rotation(compass)
        val rowOf = mutableListOf<Int>()
        riverRowCounts(discards.size, compass).forEachIndexed { row, length -> repeat(length) { rowOf += row } }
        val out = mutableListOf<GamesMahjongStripTile>()
        var u = 0f
        var row = 0
        discards.forEachIndexed { index, discard ->
            val nextRow = if (index < rowOf.size) rowOf[index] else row
            if (nextRow != row) {
                row = nextRow
                u = 0f
            }
            val sideways = discard.riichi == true
            val lw = if (sideways) h else w
            val lh = if (sideways) w else h
            val v = row * h + (if (sideways) h - w else 0f)
            val (x, y) = when (compass) {
                MahjongCompass.bottom -> (rect.left + u) to (rect.top + v)
                MahjongCompass.top -> (rect.right - u - lw) to (rect.bottom - v - lh)
                MahjongCompass.right -> (rect.left + v) to (rect.bottom - u - lw)
                MahjongCompass.left -> (rect.right - v - lh) to (rect.top + u)
            }
            var state = if (discard.taken == true) MahjongTileState.taken else if (discard.tsumogiri == true) MahjongTileState.tsumogiri else MahjongTileState.normal
            if (highlightLast && index == discards.size - 1 && discard.taken != true) state = MahjongTileState.highlighted
            out += GamesMahjongStripTile(MahjongTileFace.of(discard.tile), riverTile, state, (base + (if (sideways) 1 else 0)) % 4, x, y)
            u += lw
        }
        return out
    }

    private data class Item(val face: MahjongTileFace, val size: MahjongTileSize, val sideways: Boolean, val lead: Float)

    /** 상대 손 띠: 뒷면 18×24 × hand_count + 부로 24×32(주인 기준 오른쪽 끝). 띠 가운데 맞춤. */
    fun handStrip(count: Int, melds: List<MahjongWireMeld>, compass: MahjongCompass): List<GamesMahjongStripTile> {
        val rect = GamesMahjongFeltLayout.handStripRect(compass) ?: return emptyList()
        val base = MahjongTileArtModel.rotation(compass)
        val items = mutableListOf<Item>()
        repeat(maxOf(0, count)) { items += Item(MahjongTileFace.Back, MahjongTileSize.back, false, 0f) }
        melds.forEachIndexed { mi, meld ->
            meld.tiles.forEachIndexed { ti, tile ->
                val closedEnd = meld.type == "ankan" && (ti == 0 || ti == meld.tiles.size - 1)
                val sideways = meld.called != null && tile == meld.called
                items += Item(
                    if (closedEnd) MahjongTileFace.Back else MahjongTileFace.of(tile), MahjongTileSize.smallMeld, sideways,
                    if (ti == 0) (if (mi == 0 && count > 0) 8f else 4f) else 0f,
                )
            }
        }
        fun length(item: Item) = item.lead + (if (item.sideways) item.size.height else item.size.width)
        val total = items.sumOf { length(it).toDouble() }.toFloat()
        val along = if (compass == MahjongCompass.top) rect.width else rect.height
        var u = (along - total) / 2
        val out = mutableListOf<GamesMahjongStripTile>()
        for (item in items) {
            u += item.lead
            val lw = if (item.sideways) item.size.height else item.size.width
            val lh = if (item.sideways) item.size.width else item.size.height
            val across = (GamesMahjongFeltLayout.handStrip - lh) / 2
            val (x, y) = when (compass) {
                MahjongCompass.top -> (rect.right - u - lw) to (rect.top + across)
                MahjongCompass.right -> (rect.left + across) to (rect.bottom - u - lw)
                MahjongCompass.left -> (rect.left + across) to (rect.top + u)
                MahjongCompass.bottom -> 0f to 0f
            }
            out += GamesMahjongStripTile(item.face, item.size, MahjongTileState.normal, (base + (if (item.sideways) 1 else 0)) % 4, x, y)
            u += lw
        }
        return out
    }
}

/** 가로 판 칸(순수 — 크기(dp 값)에서 계산). 펠트는 884×502 를 feltScale 로 줄인 크기. */
class GamesMahjongTableLayout(val width: Float, val height: Float) {
    companion object {
        const val sideWidth = 118f
        const val gap = 6f
        const val topStrip = 30f
        const val handHeight = 66f
    }

    val sideW: Float get() = sideWidth
    val centerX: Float get() = sideW + gap
    val centerW: Float get() = width - (sideW + gap) * 2
    val handTop: Float get() = height - handHeight
    val feltScale: Float
        get() {
            val availW = centerW
            val availH = handTop - topStrip - gap * 2
            return maxOf(0.2f, minOf(availW / GamesMahjongFeltLayout.felt.width, availH / GamesMahjongFeltLayout.felt.height))
        }
    val felt: Rect
        get() {
            val w = GamesMahjongFeltLayout.felt.width * feltScale
            val h = GamesMahjongFeltLayout.felt.height * feltScale
            val top = topStrip + gap
            val availH = handTop - gap - top
            val x = centerX + (centerW - w) / 2
            val y = top + maxOf(0f, (availH - h) / 2)
            return Rect(x, y, x + w, y + h)
        }
    val info: Rect get() = Rect(0f, 0f, sideW, 34f)
    val chrome: Rect get() = Rect(0f, 38f, sideW, 64f)
    val mySeat: Rect get() = Rect(0f, handTop - 74f, sideW, handTop - 4f)
    val leftSeat: Rect get() = Rect(0f, 70f, sideW, 70f + maxOf(60f, mySeat.top - 74f))
    val topSeat: Rect get() = Rect(centerX + centerW * 0.15f, 0f, centerX + centerW * 0.85f, topStrip)
    val rightSeat: Rect get() = Rect(width - sideW, 0f, width, 96f)
    val aids: Rect get() = Rect(width - sideW, 100f, width, 126f)
    val actions: Rect get() = Rect(width - sideW, 130f, width, height)
    val hand: Rect get() = Rect(0f, handTop, width - sideW - gap, height)
    /** 손패 높이(상태 줄 16 아래). 좁은 화면이면 열네 장 + 쯔모 간격이 손 칸에 들도록 줄인다. */
    val handTileHeight: Float
        get() {
            val byHeight = handHeight - 18
            val byWidth = (hand.width - 8) / 14 * MahjongTileSize.hand.height / MahjongTileSize.hand.width
            return maxOf(20f, minOf(byHeight, byWidth))
        }
}
