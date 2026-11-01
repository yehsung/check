// 원본: Sources/check/RummyPanelResult.swift:28 (rows) · :33 (winnerName) · :101 (net) · :159 (RummyFinalBoard 배율 · 타일 자리) @ 1a5eeca6 · 폰 값은 ios-1017 설계서 §4·§6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyLayout
import com.yehsung.aingcheck.core.wire.games.RummyMatchSeat
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.games.RummySeatState
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

// 아잉 큐브 결과 화면의 순수 값 — 맥 뷰 안에 있던 계산과 폰 칸 폭에 맞춘 값. [한 판 더] 가 부를 사람은 RummyExitPolicy.rematchInvitees 한 곳이다.

/** 남은 타일 한 줄 — 칸에 들어가는 만큼 + 못 그린 장수(`+N`). */
data class RummyResultRackLine(val shown: List<RummyFace>, val overflow: Int)

/** 끝난 판 위 타일 한 장(논리 좌표). */
data class RummyFinalBoardTile(val face: RummyFace, val x: Long, val y: Long)

object RummyResultSummary {
    /** 등수 줄 남은 타일 — 폰 폭 361 안에 13장쯤 들어가는 크기. */
    val rackTile: RummyTileSize = RummyTileSize.canvas(0.6)
    const val rackTileSpacing: Double = 2.0
    const val rackBadgeWidth: Double = 28.0

    /** 판에 앉았던 자리(끝까지 한 자리 · 기권) — 서버 등수 순. 초대만 받은 자리는 빠진다. */
    fun rows(match: RummyMatchState): List<RummyMatchSeat> =
        (match.seats ?: emptyList())
            .filter { it.state == RummySeatState.done || it.state == RummySeatState.forfeit || it.finalRank != null }
            .sortedWith(compareBy<RummyMatchSeat>({ it.finalRank ?: 99L }, { it.seatNo ?: 9L }))

    fun winnerName(rows: List<RummyMatchSeat>): String? = rows.firstOrNull { it.isWinner == true }?.displayName

    /** 루비 순수익(받은 몫 − 판돈). 판돈은 시작할 때 걷혔다. */
    fun net(seat: RummyMatchSeat, stake: Long?): Long = (seat.payout ?: 0L) - (stake ?: 0L)

    fun isMe(seat: RummyMatchSeat, match: RummyMatchState): Boolean = seat.seatNo != null && seat.seatNo == match.mySeatNo

    /** 폭 [width] 에 들어가는 만큼만 그린다. 다 들어가면 `+N` 칸을 비우지 않는다. */
    fun rackLine(
        rack: List<RummyFace>,
        width: Double,
        tileWidth: Double = rackTile.size.width,
        spacing: Double = rackTileSpacing,
        badgeWidth: Double = rackBadgeWidth,
    ): RummyResultRackLine {
        val step = tileWidth + spacing
        if (rack.size * step - spacing <= width) return RummyResultRackLine(rack, 0)
        val room = floor((width - badgeWidth) / step).toInt().coerceIn(0, rack.size - 1)
        return RummyResultRackLine(rack.take(room), rack.size - room)
    }

    /** 끝난 판의 타일 자리 — 서버 배치(`table_layout`) 그대로, 없는 자리는 [RummyTableLayout.place] 가 채운다. */
    fun boardTiles(sets: List<List<RummyFace>>, layout: RummyLayout?): List<RummyFinalBoardTile> {
        val table = RummyTableLayout(sets, layout)
        return sets.flatMapIndexed { setIndex, faces ->
            faces.mapIndexedNotNull { tileIndex, face ->
                table.tileFrame(setIndex, tileIndex)?.let { RummyFinalBoardTile(face, it.x, it.y) }
            }
        }
    }
}

/**
 * 끝난 판을 칸에 맞추는 값(dp). 판 화면과 같은 두 보기다:
 * 기본 = 캔버스 높이를 칸에 맞춘 배율(가로는 밀어 본다, 타일 폭 40 상한) · 전체 = 1000×640 이 한눈에(세로 폰에서 타일 약 15).
 */
data class RummyFinalBoardLayout(val scale: Double, val width: Double, val height: Double, val scrolls: Boolean) {
    val tile: RummyTileSize get() = RummyTileSize.canvas(scale)

    companion object {
        const val inset: Double = 16.0

        /** 논리 타일 폭 40 × 1.0 = 40dp(설계서 §4 상한). */
        const val maxScale: Double = 1.0

        fun make(viewWidth: Double, viewHeight: Double, whole: Boolean): RummyFinalBoardLayout {
            val roomWidth = max(viewWidth - inset * 2, 1.0)
            val roomHeight = max(viewHeight - inset * 2, 1.0)
            val canvasWidth = RummyTableLayout.canvasWidth.toDouble()
            val canvasHeight = RummyTableLayout.canvasHeight.toDouble()
            val fit = min(roomWidth / canvasWidth, roomHeight / canvasHeight)
            val scale = if (whole) fit else max(fit, min(roomHeight / canvasHeight, maxScale))
            return RummyFinalBoardLayout(scale, canvasWidth * scale, canvasHeight * scale, canvasWidth * scale > roomWidth + 0.5)
        }

        /** 두 보기가 다른가 — 넓은 칸이면 전환 단추가 뜻이 없다. */
        fun canZoom(viewWidth: Double, viewHeight: Double): Boolean =
            make(viewWidth, viewHeight, whole = true).scale < make(viewWidth, viewHeight, whole = false).scale
    }
}
