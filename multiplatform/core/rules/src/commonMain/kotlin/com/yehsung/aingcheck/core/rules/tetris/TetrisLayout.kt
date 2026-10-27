// 원본: Sources/CheckCore/TetrisLayout.swift @ 1b8260d
// 옮긴 것: 배치·색의 **상수만**(C§3.2 A-1 "TetrisLayout(상수만)"). SwiftUI `Color`·그리기는 ui(W4-b)가 이 값으로 다시 칠한다.
package com.yehsung.aingcheck.core.rules.tetris

import com.yehsung.aingcheck.core.rules.minigame.MiniGameCanvas
import com.yehsung.aingcheck.core.rules.minigame.MiniGameRect
import com.yehsung.aingcheck.core.rules.minigame.MiniGameSize

/**
 * 캔버스 배치 상수(논리 292×302 · 셀 13). 맥·폰이 한 벌을 쓴다(폰 전용 배치를 만들지 않는다 — 판은 안 커진다).
 * 가로 12 + 61 + 8 + 130 + 8 + 61 + 12 = 292, 세로 13 + 260 + 4 + 21 + 4 = 302. 양쪽 열 바닥과 판 바닥이 같은 줄(273)이다.
 */
object TetrisLayout {
    val logicalSize: MiniGameSize get() = MiniGameCanvas.logicalSize

    const val cell: Double = 13.0
    const val outerMargin: Double = 12.0
    const val columnWidth: Double = 61.0
    const val gutter: Double = 8.0

    const val boardX: Double = outerMargin + columnWidth + gutter
    const val boardWidth: Double = cell * TetrisGame.columns
    const val rightColumnX: Double = boardX + boardWidth + gutter

    const val bufferY: Double = 0.0
    const val boardTopY: Double = cell
    const val boardBottomY: Double = boardTopY + cell * TetrisGame.visibleRows

    const val bandY: Double = 277.0
    const val bandHeight: Double = 21.0
    const val textMinX: Double = 16.0
    const val textMaxX: Double = 276.0

    const val labelY: Double = 13.0
    const val labelHeight: Double = 10.0
    const val boxY: Double = 25.0
    const val boxHeight: Double = 44.0
    const val stageChipY: Double = 89.0
    const val stageChipHeight: Double = 16.0
    const val levelCaptionY: Double = 213.0
    const val levelValueY: Double = 222.0
    const val linesCaptionY: Double = 248.0
    const val linesValueY: Double = 257.0
    const val captionHeight: Double = 9.0
    const val valueHeight: Double = 16.0

    const val slotGap: Double = 7.0

    /** 미니 조각 한 칸 — 홀드와 넥스트가 같은 값을 쓴다. */
    const val miniCell: Double = 9.0

    /** n 번째 넥스트 슬롯(0부터)의 윗변. */
    fun slotY(index: Int): Double = boxY + index.toDouble() * (boxHeight + slotGap)

    /** 판 좌표(행 0 = 맨 위) → 논리 사각형. 보이는 20행 + 그 위 버퍼 한 줄만 뜻을 가진다. */
    fun cellRect(row: Int, column: Int): MiniGameRect = MiniGameRect(
        x = boardX + column.toDouble() * cell,
        y = boardTopY + (row - TetrisGame.firstVisibleRow).toDouble() * cell,
        width = cell,
        height = cell,
    )

    /** 판 우물 전체(버퍼행 포함). */
    val wellRect: MiniGameRect get() = MiniGameRect(boardX, bufferY, boardWidth, boardBottomY - bufferY)
}

/** 조각 7종의 색(sRGB 0…1) — 표준 배색을 대비 규약(우물 위 최소 4.31:1, 조각끼리 채널 최대 차 0.27 이상)에 맞춰 조인 값. */
object TetrisPalette {
    data class Rgb(val r: Double, val g: Double, val b: Double)

    /** 우물 바닥 잉크(무대 하늘 위에 [wellOpacity] 로 얹는다). */
    val wellInk: Rgb = Rgb(0.02, 0.03, 0.06)

    /** 우물 불투명도 — 위 대비 실측의 기준값이다(내리면 조각-배경 대비가 그대로 내려간다). */
    const val wellOpacity: Double = 0.72

    val rgb: Map<TetrisGame.Piece, Rgb> = mapOf(
        TetrisGame.Piece.i to Rgb(0.33, 0.85, 0.92),
        TetrisGame.Piece.j to Rgb(0.36, 0.50, 0.96),
        TetrisGame.Piece.l to Rgb(0.99, 0.60, 0.16),
        TetrisGame.Piece.o to Rgb(0.97, 0.89, 0.33),
        TetrisGame.Piece.s to Rgb(0.44, 0.88, 0.45),
        TetrisGame.Piece.t to Rgb(0.74, 0.48, 0.97),
        TetrisGame.Piece.z to Rgb(0.95, 0.33, 0.36),
    )

    /** 칸 윗변 하이라이트(흰색 불투명도). */
    const val cellHighlightOpacity: Double = 0.22

    /** 고스트(하드드롭 착지 자리) 불투명도 — 우물 대비 1.36:1. */
    const val ghostOpacity: Double = 0.26

    /** 홀드를 이미 쓴 상태 표시(조각을 흐린다). */
    const val spentOpacity: Double = 0.35
}
