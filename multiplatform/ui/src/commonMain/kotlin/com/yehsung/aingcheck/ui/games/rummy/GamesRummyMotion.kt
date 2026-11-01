// 원본: Sources/CheckMobileKit/Games/GamesRummyMotion.swift:1 @ ios-1017-cube 614d98bd · 맥 Sources/check/RummyPanelMatch.swift:306,835 (뽑기 · 정렬 시차) · Sources/check/RummyTableCanvas.swift:193 (판 변화 스프링) @ 1a5eeca6 · 설계서 §7
//
// 폰 아잉 큐브 모션의 **순수 값**. 그리기는 GamesRummyRackPane(뽑기 · 정렬) · GamesRummyBoardCanvas(판 변화)이고, 모두 **동작 줄이기면 끈다**.
//   · 뽑기: [뽑기] 자리 → 받침대 빈자리 · 스프링 0.45초([drawOrigin]).
//   · 정렬: 25ms 시차 미끄러짐([GamesRummyRackMotion.sortStagger]).
//   · 판 변화: 타일이 옛 자리에서 새 자리로 이동([GamesRummyBoardMotion]). 판은 Canvas 한 장이라 움직이는 타일만 판 층에서 비우고 따로 된 층에 그린다.
// 불투명도는 이징으로 깎지 않는다 — 여기 곡선은 자리 · 크기 · 기울기뿐이다.
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.spring
import com.yehsung.aingcheck.core.rules.rummy.RummyBoardMeld
import com.yehsung.aingcheck.core.rules.rummy.RummyBoardTile
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasPoint
import com.yehsung.aingcheck.core.rules.rummy.RummyRackSort
import com.yehsung.aingcheck.core.rules.rummy.RummyTableLayout
import com.yehsung.aingcheck.core.rules.rummy.RummyTurnEditor
import com.yehsung.aingcheck.core.stores.rummy.RummyDrawEvent
import com.yehsung.aingcheck.core.wire.games.RummyFace
import kotlin.math.PI

/** 맥 · iOS 스프링 수치를 Compose 스프링으로. SwiftUI `.spring(response:dampingFraction:)` 의 response 는 고유 주기라 강성 = (2π / response)². */
object GamesRummySpring {
    const val flightResponse: Double = 0.45
    const val flightDamping: Float = 0.72f
    const val slideResponse: Double = 0.38
    const val slideDamping: Float = 0.82f
    const val boardDamping: Float = 0.84f

    fun stiffness(response: Double): Float {
        val frequency = 2 * PI / response
        return (frequency * frequency).toFloat()
    }

    /** 뽑은 타일이 날아오는 곡선. */
    fun <T> flight(): SpringSpec<T> = spring(dampingRatio = flightDamping, stiffness = stiffness(flightResponse))

    /** 받침대 타일이 미끄러지는 곡선(정렬 · 끼워 넣기 미리보기). */
    fun <T> slide(): SpringSpec<T> = spring(dampingRatio = slideDamping, stiffness = stiffness(slideResponse))

    /** 판 타일이 옮겨지는 곡선. */
    fun <T> board(): SpringSpec<T> = spring(dampingRatio = boardDamping, stiffness = stiffness(slideResponse))
}

/** 지금 날아오는 뽑기 하나 — 사건 번호와 그 타일들. */
data class GamesRummyRackFlight(val serial: Int, val ids: Set<Int>)

object GamesRummyRackMotion {
    /** 정렬 시차 한 칸. */
    const val staggerStepMillis: Long = 25L

    /** 정렬 시차를 비우는 때 — 안 비우면 끼워 넣기 미리보기까지 늦는다. */
    const val staggerClearMillis: Long = 1_400L

    /** 뽑기 사건을 닫는 때 — 뒤의 정렬 스프링이 뽑기 곡선을 쓰지 않게. */
    const val flightMillis: Long = 900L

    private const val flightStartScale: Float = 0.55f
    private const val flightStartDegrees: Float = -10f

    /** 정렬한 뒤의 읽는 순서대로 25ms 씩 늦는다(타일 id → 지연). 편집기를 사본으로 정렬해 본다. */
    fun sortStagger(editor: RummyTurnEditor, mode: RummyRackSort): Map<Int, Long> {
        val sorted = editor.copy()
        sorted.sortRack(mode)
        return sorted.rackLayout.readingOrder.withIndex().associate { (position, id) -> id to position * staggerStepMillis }
    }

    /** 지금 날아오는 중인 타일 — [doneSerial] 까지는 끝났다. 동작 줄이기면 없다. */
    fun flight(lastDraw: RummyDrawEvent?, doneSerial: Int?, reduceMotion: Boolean): GamesRummyRackFlight? {
        if (reduceMotion || lastDraw == null || lastDraw.serial == doneSerial) return null
        return GamesRummyRackFlight(lastDraw.serial, lastDraw.tiles.map { it.tileID }.toSet())
    }

    /** 비행 진행도 0(버튼 자리) ~ 1(내려앉음)의 크기. */
    fun flightScale(progress: Float): Float = flightStartScale + (1f - flightStartScale) * progress

    /** 비행 진행도의 기울기(도). */
    fun flightDegrees(progress: Float): Float = flightStartDegrees * (1f - progress)
}

/** [뽑기] 칸의 가운데 — 받침대 칸 좌표로(뽑은 타일이 여기서 출발한다). 동작 줄 배치(GamesRummyActionRow)와 같은 값에서 나온다. */
fun GamesRummyMatchLayout.drawOrigin(textScale: Double): RummyCanvasPoint {
    val gap = GamesRummyMatchLayout.actionGap
    val point = if (GamesRummyMatchLayout.actionRowCount(textScale) == 1) {
        val widths = GamesRummyMatchLayout.actionWidths(size.width)
        RummyCanvasPoint(gap + widths.submit + gap + widths.draw / 2, actions.midY)
    } else {
        val height = GamesRummyMatchLayout.actionButtonHeight(textScale)
        val third = maxOf(0.0, size.width - gap * 4) / 3
        RummyCanvasPoint(gap + third / 2, actions.midY + (gap + height) / 2)
    }
    return RummyCanvasPoint(point.x - rack.x, point.y - rack.y)
}

/** 판 변화 한 번 — 옛 자리에서 새 자리로 움직일 타일들. */
data class GamesRummyBoardMotion(val moves: List<Move>) {
    /** 새 판에서의 자리(그동안 판 층이 이 칸을 그리지 않는다). */
    data class Slot(val meld: Int, val tile: Int)

    /** [from] · [to] 는 타일 왼쪽 위(논리 좌표). */
    data class Move(val slot: Slot, val face: RummyFace, val highlighted: Boolean, val from: RummyCanvasPoint, val to: RummyCanvasPoint) {
        /** 진행도 [progress] 의 자리. 스프링이 넘쳐도 그대로 잇는다. */
        fun at(progress: Double): RummyCanvasPoint = RummyCanvasPoint(from.x + (to.x - from.x) * progress, from.y + (to.y - from.y) * progress)
    }

    val hidden: Set<Slot> = moves.map { it.slot }.toSet()

    private class Placed(val slot: Slot, val tile: RummyBoardTile, val origin: RummyCanvasPoint)

    companion object {
        /** 이보다 많이 움직이면 뛰어넘는다(판을 통째로 다시 깐 차례). */
        const val maxMoves: Int = 40

        private fun placed(melds: List<RummyBoardMeld>): List<Placed> = melds.flatMapIndexed { index, meld ->
            meld.tiles.mapIndexed { position, tile ->
                Placed(
                    Slot(index, position),
                    tile,
                    RummyCanvasPoint(meld.frame.x.toDouble() + position.toDouble() * RummyTableLayout.tileWidth.toDouble(), meld.frame.y.toDouble()),
                )
            }
        }

        /**
         * 짝짓는 순서: ① 같은 id · 같은 면(편집 중) ② 면이 같고 자리가 같은 것(가만히 있었다 — 같은 면 둘이 엇갈려 날지 않게) ③ 남은 같은 면을 읽는 순서대로.
         * 새로 생긴 타일(받침대에서 낸 것 · 남이 낸 것)은 옛 자리가 없어 그 자리에 바로 선다. [excluding] = 방금 손으로 놓은 타일(손이 놓은 자리가 곧 제자리다 — 옛 자리에서 날아오면 안 된다).
         * 움직일 것이 없거나 [maxMoves] 를 넘으면 null.
         */
        fun make(old: List<RummyBoardMeld>, new: List<RummyBoardMeld>, excluding: Set<Int> = emptySet()): GamesRummyBoardMotion? {
            if (old.isEmpty() || old == new) return null
            fun kept(entry: Placed): Boolean = entry.tile.id?.let { it !in excluding } ?: true
            val olds = placed(old).filter(::kept)
            val news = placed(new).filter(::kept)
            val moves = ArrayList<Move>()
            fun move(from: Placed, to: Placed) {
                if (from.origin == to.origin) return
                moves.add(Move(to.slot, to.tile.face, to.tile.highlighted, from.origin, to.origin))
            }

            val oldByID = HashMap<Int, Int>()
            olds.forEachIndexed { index, entry -> entry.tile.id?.let { oldByID[it] = index } }
            val usedOld = HashSet<Int>()
            val leftovers = ArrayList<Placed>()
            for (entry in news) {
                val index = entry.tile.id?.let { oldByID[it] }
                if (index != null && olds[index].tile.face == entry.tile.face) {
                    usedOld.add(index)
                    move(olds[index], entry)
                } else {
                    leftovers.add(entry)
                }
            }
            val waiting = HashMap<RummyFace, MutableList<Placed>>()
            olds.forEachIndexed { index, entry ->
                if (index !in usedOld) waiting.getOrPut(entry.tile.face) { ArrayList() }.add(entry)
            }
            val unplaced = ArrayList<Placed>()
            for (entry in leftovers) {
                val list = waiting[entry.tile.face]
                val index = list?.indexOfFirst { it.origin == entry.origin } ?: -1
                if (list != null && index >= 0) list.removeAt(index) else unplaced.add(entry)
            }
            for (entry in unplaced) {
                val list = waiting[entry.tile.face]
                if (list.isNullOrEmpty()) continue
                move(list.removeAt(0), entry)
            }
            if (moves.isEmpty() || moves.size > maxMoves) return null
            return GamesRummyBoardMotion(moves)
        }
    }
}
