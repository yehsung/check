// 원본: Sources/CheckCore/TetrisBoardPainter.swift @ 3bd04bd (TetrisDuelPalette · TetrisMiniBoardLayout · TetrisBoardPainter)
// 원본: Sources/CheckMobileKit/Games/GamesTetrisCanvas.swift @ 3bd04bd (솔로 판 그리기 — 같은 순서·수치)
// 원본: Sources/CheckCore/TetrisLayout.swift @ 3bd04bd (TetrisPalette 의 Color 몫 — 수치 원장은 core/rules TetrisPalette)
//
// 테트리스 **판 그림 한 벌**(솔로 · 1:1 내 판 · 상대 미니 판 · 관전 판). 순수 `DrawScope` 함수이고 상태·시계·뷰가 없다 — 부르는 쪽이 판(값)과
// 캔버스 크기를 넘긴다. Swift 는 솔로 잎 뷰의 그리기가 그 파일의 private 이라 대결 painter 에 **같은 순서·같은 수치**를 한 벌 더 적었다.
// Kotlin 은 그 제약이 없어 솔로 판도 이 painter 를 부른다([drawBoard] 의 `duel = false`) — 두 벌이 갈릴 자리(그리는 순서)가 아예 없다.
//
// 순서: 하늘 → 후광 → 우물 → 격자 → 버퍼 경계 → 굳은 칸 → 고스트 → 조각 → 홀드·넥스트 (대결만: → 들어올 방해 줄 미터).
// 대결이 더하는 것 셋: ① 방해 줄 칸은 **회색**(`isGarbage` 로만 가른다 — 판 배열에는 조각으로 들어 있다) ② 우물 왼쪽 거터의 미터 ③ 미니 판.
//
// 금지(솔로·맥 캔버스와 같다): 필터(blur) 금지 · 배경은 **하늘만**(terrain = false — 능선은 하단 밴드 자리를 밝게 채워 글자와 겹친다)
// · 배치·색은 core 표 한 벌(TetrisLayout · TetrisPalette) — 폰 전용 배치 타입을 새로 만들지 않는다.
package com.yehsung.aingcheck.ui.games.tetris

import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import com.yehsung.aingcheck.core.rules.minigame.MiniGameRect
import com.yehsung.aingcheck.core.rules.minigame.MiniGameStage
import com.yehsung.aingcheck.core.rules.tetris.TetrisDuelCell
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.rules.tetris.TetrisLayout
import com.yehsung.aingcheck.core.rules.tetris.TetrisPalette
import com.yehsung.aingcheck.ui.games.minigame.GamesCanvasColors
import com.yehsung.aingcheck.ui.games.minigame.MiniGameBackdrop
import com.yehsung.aingcheck.ui.games.minigame.MiniGameEffects
import com.yehsung.aingcheck.ui.games.minigame.MiniGameProjection
import com.yehsung.aingcheck.ui.games.minigame.insetBy
import com.yehsung.aingcheck.ui.games.minigame.paint

/** 조각 색(core `TetrisPalette.rgb` 원장 → Compose 색). 원장을 바꾸면 우물 대비 시험(core)이 걸린다. */
object TetrisPaletteColors {
    val wellColor: Color = TetrisPalette.wellInk.let { Color(it.r.toFloat(), it.g.toFloat(), it.b.toFloat()) }

    fun color(piece: TetrisGame.Piece): Color {
        val c = TetrisPalette.rgb[piece] ?: TetrisPalette.Rgb(1.0, 1.0, 1.0)
        return Color(c.r.toFloat(), c.g.toFloat(), c.b.toFloat())
    }

    val cellHighlight: Color = Color.White.copy(alpha = TetrisPalette.cellHighlightOpacity.toFloat())
}

/** 대결 전용 색. 조각 7색은 [TetrisPaletteColors] 그대로다(솔로와 같은 판이어야 한다). */
object TetrisDuelPalette {
    /** 방해 줄 칸(무채색 회색). 우물 위 3:1 이상 · 조각 7색과 채널 최대 차 0.20 이상(Swift 시험이 되묻는다). */
    val garbageColor: Color = Color(0.60f, 0.62f, 0.68f)

    /** 들어올 방해 줄 미터(위험 빨강 — CheckTheme.danger 와 같은 값). */
    val meterColor: Color = Color(1.0f, 0.45f, 0.46f)

    /** 상대 미니 판 바닥(불투명) — 하늘이 없는 카드 위라 조각 대비의 기준을 이 한 색으로 고정한다. */
    val miniWellColor: Color = Color(0.04f, 0.05f, 0.09f)
}

/** 상대 미니 판의 배치(셀 9pt 기본). 순수 상수. */
object TetrisMiniBoardLayout {
    const val cell: Double = 9.0

    /** 판 테두리 안쪽 여백(테두리 선이 칸을 덮지 않게). */
    const val inset: Double = 2.0

    /** 셀 변을 주면 그 판의 크기(dp 와 같은 단위). */
    fun boardSize(cell: Double): Pair<Double, Double> =
        (cell * TetrisGame.columns + inset * 2) to (cell * TetrisGame.visibleRows + inset * 2)
}

object TetrisBoardPainter {
    /** 미터가 그리는 최대 줄 수(보이는 판 높이). */
    const val meterMaxLines: Int = TetrisGame.visibleRows

    /** 미터 바탕(거터 8 의 가운데 5 — 양옆 1.5 는 왼쪽 열 상자·우물 테두리와 붙지 않게 비운다). */
    val meterTrackRect: MiniGameRect
        get() = MiniGameRect(
            TetrisLayout.boardX - TetrisLayout.gutter + 1.5, TetrisLayout.boardTopY,
            TetrisLayout.gutter - 3, TetrisLayout.boardBottomY - TetrisLayout.boardTopY,
        )

    /** 미터 막대(판 바닥에서 위로 자란다). */
    fun meterRect(pendingLines: Int): MiniGameRect {
        val lines = pendingLines.coerceIn(0, meterMaxLines)
        val height = lines * TetrisLayout.cell
        return MiniGameRect(meterTrackRect.minX, TetrisLayout.boardBottomY - height, meterTrackRect.maxX - meterTrackRect.minX, height)
    }

    /**
     * 판 한 장(캔버스 전체). [duel] 이면 방해 줄 회색·미터를 더한다(솔로는 둘 다 없다 — 솔로 판에는 방해 줄이 생길 길이 없다).
     * [density] 는 글자가 아니라 1px 선 두께를 dp 로 맞추는 데 쓴다.
     */
    fun drawBoard(scope: DrawScope, game: TetrisGame, size: Size, reduceMotion: Boolean, duel: Boolean, density: Float) {
        val t = MiniGameProjection(size, TetrisLayout.logicalSize, density)
        val full = Rect(Offset.Zero, size)
        val stage = MiniGameStage.forTetrisAdvance(game.advance)
        val paint = stage.paint

        // 1) 하늘(캔버스 전체 — 레터박스까지) · 2) 우물 뒤 후광(radialGradient 하나).
        MiniGameBackdrop.draw(scope, full, stage, scroll = 0f, terrain = false, reduceMotion = reduceMotion, density = density)
        val well = t.rect(TetrisLayout.wellRect)
        MiniGameEffects.glow(scope, well.insetBy(-well.width * 0.45f, -well.height * 0.12f), paint.glow, 0.16f)

        // 3) 우물 바닥 — 조각-배경 대비의 기준값이라 불투명도를 흔들면 TetrisPalette 실측이 무효가 된다.
        val corner = CornerRadius(4 * t.scale)
        scope.drawRoundRect(TetrisPaletteColors.wellColor.copy(alpha = TetrisPalette.wellOpacity.toFloat()), well.topLeft, well.size, corner)
        drawGrid(scope, t)
        // 버퍼행은 판의 일부지만 규칙상 다른 자리다(여기까지 쌓이면 다음 스폰이 막힌다) — 경계선 하나로 말한다.
        val boundary = t.rect(TetrisLayout.boardX, TetrisLayout.boardTopY, TetrisLayout.boardWidth, 1.0)
        scope.drawRect(paint.structureEdge.copy(alpha = 0.45f), boundary.topLeft, boundary.size)
        scope.drawRoundRect(paint.structureEdge.copy(alpha = 0.55f), well.topLeft, well.size, corner, style = Stroke(density))

        // 4) 굳은 칸. 버퍼행(보이는 판 바로 위 한 줄)은 0.55 — 거기 쌓인 것은 "곧 끝"이라는 경고다.
        val bufferRow = TetrisGame.firstVisibleRow - 1
        for (row in bufferRow until TetrisGame.totalRows) {
            for (column in 0 until TetrisGame.columns) {
                val piece = game.cell(row, column) ?: continue
                val opacity = if (row == bufferRow) 0.55f else 1f
                if (duel && game.isGarbage(row, column)) {
                    drawCell(scope, t, row, column, TetrisDuelPalette.garbageColor, opacity, highlight = false)
                } else {
                    drawCell(scope, t, row, column, TetrisPaletteColors.color(piece), opacity)
                }
            }
        }

        // 5) 고스트 → 6) 조각(겹치는 자리에서는 실물이 위).
        val active = game.active
        val ghost = game.ghost
        if (ghost != null && active != null && ghost.row != active.row) {
            for (cell in ghost.cells) if (cell.row >= bufferRow) {
                drawCell(scope, t, cell.row, cell.column, TetrisPaletteColors.color(ghost.piece), TetrisPalette.ghostOpacity.toFloat(), highlight = false)
            }
        }
        if (active != null) {
            for (cell in active.cells) if (cell.row >= bufferRow) {
                drawCell(scope, t, cell.row, cell.column, TetrisPaletteColors.color(active.piece), if (cell.row == bufferRow) 0.55f else 1f)
            }
        }

        // 7) 홀드 상자와 넥스트 5칸. 크기가 아니라 **세기**로 1번 슬롯을 구분한다(크기를 달리하면 슬롯 산식이 두 벌이 된다).
        drawSlot(
            scope, t, MiniGameRect(TetrisLayout.outerMargin, TetrisLayout.boxY, TetrisLayout.columnWidth, TetrisLayout.boxHeight),
            game.heldPiece, stage, emphasized = false, spent = game.holdUsed, density = density,
        )
        game.next.take(TetrisGame.nextCount).forEachIndexed { index, piece ->
            drawSlot(
                scope, t, MiniGameRect(TetrisLayout.rightColumnX, TetrisLayout.slotY(index), TetrisLayout.columnWidth, TetrisLayout.boxHeight),
                piece, stage, emphasized = index == 0, spent = false, density = density,
            )
        }

        // 8) (대결) 들어올 방해 줄 미터.
        if (duel) drawMeter(scope, t, game.pendingGarbageLines)
    }

    /** 미터. 바탕 띠는 언제나, 빨간 막대는 들어올 줄이 있을 때만. 칸마다 1 틈을 둬 "몇 줄인가" 가 세어진다. */
    fun drawMeter(scope: DrawScope, t: MiniGameProjection, pendingLines: Int) {
        val track = t.rect(meterTrackRect)
        scope.drawRoundRect(Color.White.copy(alpha = 0.07f), track.topLeft, track.size, CornerRadius(1.5f * t.scale))
        val lines = pendingLines.coerceIn(0, meterMaxLines)
        if (lines <= 0) return
        val meter = meterRect(lines)
        for (index in 0 until lines) {
            val y = meter.maxY - (index + 1) * TetrisLayout.cell
            val cell = t.rect(MiniGameRect(meter.minX, y, meter.maxX - meter.minX, TetrisLayout.cell).insetBy(0.0, 0.5))
            scope.drawRoundRect(TetrisDuelPalette.meterColor, cell.topLeft, cell.size, CornerRadius(t.scale))
        }
    }

    /**
     * 상대 판(20행 × 10칸, 행 0 = 맨 위)을 작게. 바닥은 불투명 한 색이고, 빈 판에도 격자가 보인다. [cell] 은 **픽셀** 한 칸 변 — 폰은 기본(9)보다
     * 작은 값을 준다(세로 20행이라 기본값이면 머리글에 안 들어간다). 줄여 그리지 않고 칸 변 자체를 바꾼다(1px 선이 흐려지지 않게).
     */
    fun drawMiniBoard(scope: DrawScope, cells: List<List<TetrisDuelCell>>, size: Size, cell: Float, density: Float) {
        val inset = (TetrisMiniBoardLayout.inset * density).toFloat()
        val corner = CornerRadius(4 * density)
        scope.drawRoundRect(TetrisDuelPalette.miniWellColor, Offset.Zero, size, corner)
        val line = Color.White.copy(alpha = 0.06f)
        val hair = 0.5f * density
        for (column in 1 until TetrisGame.columns) {
            val x = inset + column * cell
            scope.drawRect(line, Offset(x, inset), Size(hair, cell * TetrisGame.visibleRows))
        }
        for (row in 1 until TetrisGame.visibleRows) {
            val y = inset + row * cell
            scope.drawRect(line, Offset(inset, y), Size(cell * TetrisGame.columns, hair))
        }
        cells.take(TetrisGame.visibleRows).forEachIndexed { rowIndex, row ->
            row.take(TetrisGame.columns).forEachIndexed { columnIndex, value ->
                val color = when (value) {
                    TetrisDuelCell.Empty -> null
                    is TetrisDuelCell.Piece -> TetrisPaletteColors.color(value.piece)
                    TetrisDuelCell.Garbage -> TetrisDuelPalette.garbageColor
                }
                if (color != null) {
                    val r = Rect(inset + columnIndex * cell, inset + rowIndex * cell, inset + (columnIndex + 1) * cell, inset + (rowIndex + 1) * cell)
                        .insetBy(hair, hair)
                    scope.drawRoundRect(color, r.topLeft, r.size, CornerRadius(density))
                }
            }
        }
        scope.drawRoundRect(
            Color.White.copy(alpha = 0.16f), Offset(hair, hair), Size(size.width - 2 * hair, size.height - 2 * hair), corner, style = Stroke(density),
        )
    }

    // MARK: 조각(솔로 잎 뷰와 같은 수치)

    /** 우물 격자 — 아주 옅은 선(먼저 그린다 — 조각 위로 안 올라온다). 선 두께는 실제 1px(Swift `1 / t.scale` 논리 단위). */
    private fun drawGrid(scope: DrawScope, t: MiniGameProjection) {
        val line = Color.White.copy(alpha = 0.055f)
        val onePx = (1.0 / t.scale)
        for (column in 1 until TetrisGame.columns) {
            val x = TetrisLayout.boardX + column * TetrisLayout.cell
            val r = t.rect(x, TetrisLayout.bufferY, onePx, TetrisLayout.boardBottomY - TetrisLayout.bufferY)
            scope.drawRect(line, r.topLeft, r.size)
        }
        for (row in 1 until TetrisGame.visibleRows) {
            val y = TetrisLayout.boardTopY + row * TetrisLayout.cell
            val r = t.rect(TetrisLayout.boardX, y, TetrisLayout.boardWidth, onePx)
            scope.drawRect(line, r.topLeft, r.size)
        }
    }

    /** 칸 하나. 인접 칸과는 **1 틈**으로 갈린다. 윗변 띠는 덩어리에 두께를 준다(사각형 안쪽으로만). */
    private fun drawCell(scope: DrawScope, t: MiniGameProjection, row: Int, column: Int, color: Color, opacity: Float, highlight: Boolean = true) {
        val logical = TetrisLayout.cellRect(row, column).insetBy(0.5, 0.5)
        val rect = t.rect(logical)
        scope.drawRoundRect(color.copy(alpha = color.alpha * opacity), rect.topLeft, rect.size, CornerRadius(1.5f * t.scale))
        if (!highlight) return
        val band = t.rect(logical.minX, logical.minY, logical.maxX - logical.minX, 2.5)
        scope.drawRect(TetrisPaletteColors.cellHighlight.copy(alpha = TetrisPaletteColors.cellHighlight.alpha * opacity), band.topLeft, band.size)
    }

    /** 홀드·넥스트 상자 하나(61×44). 미리보기 조각은 상자 안 가운데. 소진 표시는 **불투명도**(조각 0.35 + 위험색 테두리) — 회색으로 칠하지 않는다. */
    private fun drawSlot(
        scope: DrawScope, t: MiniGameProjection, rect: MiniGameRect, piece: TetrisGame.Piece?,
        stage: MiniGameStage, emphasized: Boolean, spent: Boolean, density: Float,
    ) {
        val box = t.rect(rect)
        val corner = CornerRadius(6 * t.scale)
        scope.drawRoundRect(Color.White.copy(alpha = 0.05f), box.topLeft, box.size, corner)
        val border = when {
            spent -> GamesCanvasColors.danger.copy(alpha = 0.35f)
            emphasized -> stage.paint.glow.copy(alpha = 0.45f)
            else -> GamesCanvasColors.border
        }
        scope.drawRoundRect(border, box.topLeft, box.size, corner, style = Stroke(density))
        if (piece == null) return
        // 스폰 모양의 바운딩 상자만 잘라 쓴다(I 4×1 · O 2×2 · 나머지 3×2 → 미니셀 9 를 곱해 61×44 안에 넉넉히 든다).
        val cells = TetrisGame.shape(piece, TetrisGame.Rotation.spawn)
        val minX = cells.minOf { it.dx }
        val maxX = cells.maxOf { it.dx }
        val minY = cells.minOf { it.dy }
        val maxY = cells.maxOf { it.dy }
        val width = (maxX - minX + 1) * TetrisLayout.miniCell
        val height = (maxY - minY + 1) * TetrisLayout.miniCell
        val originX = rect.minX + (rect.maxX - rect.minX) / 2 - width / 2
        val originY = rect.minY + (rect.maxY - rect.minY) / 2 - height / 2
        val alpha = if (spent) TetrisPalette.spentOpacity.toFloat() else 1f
        val color = TetrisPaletteColors.color(piece).copy(alpha = alpha)
        for (cell in cells) {
            val logical = MiniGameRect(
                originX + (cell.dx - minX) * TetrisLayout.miniCell, originY + (cell.dy - minY) * TetrisLayout.miniCell,
                TetrisLayout.miniCell, TetrisLayout.miniCell,
            ).insetBy(0.5, 0.5)
            val r = t.rect(logical)
            scope.drawRoundRect(color, r.topLeft, r.size, CornerRadius(1.5f * t.scale))
        }
    }
}
