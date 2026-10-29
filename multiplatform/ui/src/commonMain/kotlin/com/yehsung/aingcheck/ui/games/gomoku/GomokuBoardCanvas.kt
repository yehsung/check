// 원본: Sources/CheckMobileKit/Games/GamesGomokuBoardCanvas.swift @ 3bd04bd
//
// 15×15 오목판(또는 일부) 그림 — 맥 `GomokuBoardView`·폰 `GamesGomokuBoardCanvas` 와 같은 그림·색이다. 판은 **물건**이라 라이트·다크와
// 무관하게 같은 색이다(나무판 상수는 이 파일이 든다). 좌표 셈은 core/stores 의 [GomokuPhoneBoardGeometry](맥과 같은 식 — 여백 6%)가 쥐고,
// 이 파일은 받은 숫자를 픽셀로 옮기기만 한다(px 단위 기하를 만들어 그대로 그린다 — 탭 위치도 같은 px 축이다).
//
// 입력은 [GomokuPlayBoard] 만 받는다: **첫 탭은 미리보기 돌, 같은 칸을 다시 누르면 착수, 다른 칸은 미리보기 이동**(GomokuTapPreview).
// 둘 수 없는 탭은 스토어 `place` 에 넘겨 거절 이유 한 줄을 남긴다(화면이 조용히 삼키지 않는다 — 맥과 같은 규약).
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuForbiddenReason
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.rules.renju.GomokuRules
import com.yehsung.aingcheck.core.rules.renju.GomokuTurnWarning
import com.yehsung.aingcheck.core.stores.gomoku.BoardPoint
import com.yehsung.aingcheck.core.stores.gomoku.GomokuMatchState
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneBoardGeometry
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneRuleExample
import com.yehsung.aingcheck.core.stores.gomoku.GomokuSeenTurn
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuTapOutcome
import com.yehsung.aingcheck.core.stores.gomoku.GomokuTapPreview
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/** 판 그림 상수(Swift `GamesGomokuBoardCanvas` 정적 색 — sRGB 그대로). */
object GomokuBoardInk {
    val woodLight = Color(0.88f, 0.73f, 0.49f)
    val woodDark = Color(0.79f, 0.62f, 0.38f)
    val line = Color(0.30f, 0.21f, 0.12f)
    val forbidden = Color(0.87f, 0.16f, 0.18f)
    val lastMove = Color(0.95f, 0.30f, 0.26f)
    val autoStone = Color(0.62f, 0.62f, 0.62f)
    /** 미리보기 돌 고리(폰 전용 — 호버가 없어 "지금 고른 칸"이 더 또렷해야 한다). */
    val previewRing = Color(0.10f, 0.45f, 0.95f)
    val winLine = Color(0.95f, 0.30f, 0.26f)
    /** 판 그림자(라이트 — 나무색 갈색 18%). 다크는 검정 35%. */
    val shadowLight = Color(80f / 255f, 50f / 255f, 10f / 255f, 0.18f)
    val shadowDark = Color(0f, 0f, 0f, 0.35f)
    /** 차례 경고 빛(GomokuTurnWarning 의 sRGB). */
    val warning = Color(GomokuTurnWarning.tintRed.toFloat(), GomokuTurnWarning.tintGreen.toFloat(), GomokuTurnWarning.tintBlue.toFloat())
}

/** 흑 차례 금수 표시 계산을 판이 바뀔 때만 한다(맥 `GomokuForbiddenMemo` · Swift `GamesGomokuForbiddenMemo`). */
class GomokuForbiddenMemo {
    private var board: GomokuBoard? = null
    private var cached: Map<GomokuPoint, GomokuForbiddenReason> = emptyMap()

    fun points(board: GomokuBoard): Map<GomokuPoint, GomokuForbiddenReason> {
        if (this.board != board) {
            cached = GomokuRules.forbiddenPoints(board)
            this.board = board
        }
        return cached
    }

    companion object {
        /** 금수 표시가 서는 때: 끝나지 않았고 · 내가 흑이고 · 흑 차례(렌주는 흑에게만 금수가 있다). */
        fun shows(match: GomokuMatchState): Boolean =
            !match.isFinished && match.myColor == GomokuColor.black && match.turn == GomokuColor.black
    }
}

/** 판 그림 한 장의 재료(Swift `GamesGomokuBoardCanvas` 의 저장 칸). */
data class GomokuBoardPicture(
    val board: GomokuBoard,
    val lastMove: GomokuPoint? = null,
    val forbidden: Map<GomokuPoint, GomokuForbiddenReason> = emptyMap(),
    val autoPoints: Set<GomokuPoint> = emptySet(),
    val marks: Map<GomokuPoint, GomokuPhoneRuleExample.Mark> = emptyMap(),
    val preview: Pair<GomokuPoint, GomokuColor>? = null,
    val showsCoordinates: Boolean = true,
    val winLine: Pair<GomokuPoint, GomokuPoint>? = null,
    val lines: Int = GomokuBoard.size,
    val originX: Int = 0,
    val originY: Int = 0,
    val insetRatio: Double = 0.06,
)

/** 입력 없는 판 그림. [side] 한 변. */
@Composable
fun GomokuBoardCanvas(picture: GomokuBoardPicture, side: Dp, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    val colors = AingTheme.colors
    val pending = colors.pending
    val working = colors.working
    val accent = colors.accent
    Canvas(modifier.size(side)) {
        drawGomokuBoard(picture, measurer, pending = pending, working = working, accent = accent)
    }
}

/** px 기하(그림·탭이 같은 축을 쓴다). */
fun gomokuGeometry(sidePx: Float, picture: GomokuBoardPicture): GomokuPhoneBoardGeometry =
    GomokuPhoneBoardGeometry(side = sidePx.toDouble(), lines = picture.lines, originX = picture.originX, originY = picture.originY, insetRatio = picture.insetRatio)

private fun BoardPoint.offset(): Offset = Offset(x.toFloat(), y.toFloat())

fun DrawScope.drawGomokuBoard(picture: GomokuBoardPicture, measurer: TextMeasurer, pending: Color, working: Color, accent: Color) {
    val side = size.minDimension
    val g = gomokuGeometry(side, picture)
    val inset = g.inset.toFloat()
    val cell = g.cell.toFloat()
    drawRoundRect(
        brush = Brush.linearGradient(listOf(GomokuBoardInk.woodLight, GomokuBoardInk.woodDark), start = Offset.Zero, end = Offset(side, side)),
        size = Size(side, side),
        cornerRadius = CornerRadius(side * 0.025f),
    )
    val far = inset + (g.lines - 1) * cell
    val gridWidth = maxOf(0.8f * density, side / 640f)
    for (i in 0 until g.lines) {
        val offset = inset + i * cell
        drawLine(GomokuBoardInk.line.copy(alpha = 0.85f), Offset(offset, inset), Offset(offset, far), strokeWidth = gridWidth)
        drawLine(GomokuBoardInk.line.copy(alpha = 0.85f), Offset(inset, offset), Offset(far, offset), strokeWidth = gridWidth)
    }
    drawRect(GomokuBoardInk.line, topLeft = Offset(inset, inset), size = Size(far - inset, far - inset), style = Stroke(maxOf(1.2f * density, side / 380f)))
    for (star in GomokuPhoneBoardGeometry.starPoints) {
        if (!g.contains(star)) continue
        drawCircle(GomokuBoardInk.line, radius = maxOf(2f * density, cell * 0.1f), center = g.location(star).offset())
    }
    if (picture.showsCoordinates) {
        val letters = "ABCDEFGHIJKLMNO"
        val fontPx = maxOf(8f * density, inset * 0.44f)
        val style = TextStyle(fontSize = (fontPx / density / fontScale).sp, fontWeight = FontWeight.SemiBold, color = GomokuBoardInk.line.copy(alpha = 0.8f))
        for (i in 0 until g.lines) {
            val offset = inset + i * cell
            val column = g.originX + i
            if (column < letters.length) drawCentered(measurer, letters[column].toString(), style, Offset(offset, side - inset * 0.38f))
            val row = g.originY + g.lines - i
            drawCentered(measurer, "$row", style, Offset(inset * 0.4f, offset))
        }
    }
    val radius = cell * 0.46f
    for (y in g.originY until g.originY + g.lines) for (x in g.originX until g.originX + g.lines) {
        val point = GomokuPoint.at(x, y) ?: continue
        val color = picture.board[point] ?: continue
        drawStone(g.location(point).offset(), radius, color, 1f)
    }
    for (point in picture.autoPoints) {
        if (!g.contains(point) || picture.board[point] == null) continue
        drawCircle(GomokuBoardInk.autoStone, radius = maxOf(3f * density, cell * 0.17f), center = g.location(point).offset())
    }
    val last = picture.lastMove
    if (last != null && g.contains(last) && picture.board[last] != null) {
        drawCircle(GomokuBoardInk.lastMove, radius = maxOf(2.5f * density, cell * 0.13f), center = g.location(last).offset())
    }
    val win = picture.winLine
    if (win != null && g.contains(win.first) && g.contains(win.second)) {
        val a = g.location(win.first).offset()
        val b = g.location(win.second).offset()
        drawLine(Color.Black.copy(alpha = 0.35f), a, b, strokeWidth = maxOf(4f * density, cell * 0.24f), cap = StrokeCap.Round)
        drawLine(GomokuBoardInk.winLine, a, b, strokeWidth = maxOf(2.5f * density, cell * 0.16f), cap = StrokeCap.Round)
    }
    val preview = picture.preview
    if (preview != null && g.contains(preview.first) && picture.board[preview.first] == null) {
        val c = g.location(preview.first).offset()
        drawStone(c, radius, preview.second, 0.55f)
        drawCircle(
            GomokuBoardInk.previewRing, radius = radius + 2f * density, center = c,
            style = Stroke(width = maxOf(1.5f * density, cell * 0.09f), pathEffect = PathEffect.dashPathEffect(floatArrayOf(3f * density, 2f * density))),
        )
    }
    for ((point, reason) in picture.forbidden) {
        if (!g.contains(point) || picture.board[point] != null) continue
        drawCross(g.location(point).offset(), cell * 0.22f, maxOf(2f * density, cell * 0.08f), if (reason == GomokuForbiddenReason.budget) pending else GomokuBoardInk.forbidden)
    }
    for ((point, mark) in picture.marks) {
        if (!g.contains(point)) continue
        val c = g.location(point).offset()
        when (mark) {
            GomokuPhoneRuleExample.Mark.forbidden -> drawCross(c, cell * 0.26f, maxOf(2f * density, cell * 0.1f), GomokuBoardInk.forbidden)
            GomokuPhoneRuleExample.Mark.pivot -> drawCross(c, cell * 0.2f, maxOf(1.6f * density, cell * 0.08f), pending)
            GomokuPhoneRuleExample.Mark.win, GomokuPhoneRuleExample.Mark.legal -> {
                drawStone(c, radius, GomokuColor.black, 0.5f)
                drawCircle(if (mark == GomokuPhoneRuleExample.Mark.win) working else accent, radius = radius, center = c, style = Stroke(maxOf(2f * density, cell * 0.1f)))
            }
        }
    }
}

private fun DrawScope.drawCentered(measurer: TextMeasurer, text: String, style: TextStyle, center: Offset) {
    val layout = measurer.measure(text, style)
    drawText(layout, topLeft = Offset(center.x - layout.size.width / 2f, center.y - layout.size.height / 2f))
}

/** 돌 하나(그림자 + 방사형 빛). [opacity] 는 사본 층에만 건다(미리보기 · 규칙 예시). */
fun DrawScope.drawStone(c: Offset, r: Float, color: GomokuColor, opacity: Float) {
    drawCircle(Color.Black.copy(alpha = 0.25f * opacity), radius = r, center = Offset(c.x + r * 0.06f, c.y + r * 0.14f))
    val highlight = Offset(c.x - r * 0.35f, c.y - r * 0.4f)
    when (color) {
        GomokuColor.black -> drawCircle(
            Brush.radialGradient(listOf(Color(0.45f, 0.45f, 0.45f), Color(0.05f, 0.05f, 0.05f)), center = highlight, radius = r * 1.5f),
            radius = r, center = c, alpha = opacity,
        )
        GomokuColor.white -> {
            drawCircle(
                Brush.radialGradient(listOf(Color(1f, 1f, 1f), Color(0.80f, 0.80f, 0.80f)), center = highlight, radius = r * 1.6f),
                radius = r, center = c, alpha = opacity,
            )
            drawCircle(Color.Black.copy(alpha = 0.2f * opacity), radius = r, center = c, style = Stroke(0.8f * density))
        }
    }
}

private fun DrawScope.drawCross(c: Offset, half: Float, width: Float, color: Color) {
    drawLine(color, Offset(c.x - half, c.y - half), Offset(c.x + half, c.y + half), strokeWidth = width, cap = StrokeCap.Round)
    drawLine(color, Offset(c.x + half, c.y - half), Offset(c.x - half, c.y + half), strokeWidth = width, cap = StrokeCap.Round)
}

/** 내 차례 마지막 3초의 판 안쪽 가장자리 빛(Swift `GomokuTurnWarning.drawEdgeGlow` — 겹 8 · 제곱 감쇠 · 판 모서리 둥글기). */
fun DrawScope.drawGomokuEdgeGlow(intensity: Double) {
    val side = size.minDimension
    if (intensity <= 0 || side <= 0f || !intensity.isFinite()) return
    val strength = minOf(1.0, intensity)
    val corner = side * GomokuTurnWarning.cornerRatio.toFloat()
    val band = side * GomokuTurnWarning.depthRatio.toFloat() / GomokuTurnWarning.layerCount
    val clip = Path().apply { addRoundRect(RoundRect(Rect(0f, 0f, side, side), CornerRadius(corner))) }
    clipPath(clip) {
        for (index in 0 until GomokuTurnWarning.layerCount) {
            val inset = band * (index + 0.5f)
            val falloff = 1 - index.toDouble() / GomokuTurnWarning.layerCount
            val opacity = (strength * GomokuTurnWarning.peakOpacity * falloff * falloff).toFloat()
            drawRoundRect(
                GomokuBoardInk.warning.copy(alpha = opacity),
                topLeft = Offset(inset, inset),
                size = Size(side - inset * 2, side - inset * 2),
                cornerRadius = CornerRadius(maxOf(0f, corner - inset)),
                style = Stroke(band),
            )
        }
    }
}

/**
 * 대국 판(탭 입력). **첫 탭은 미리보기 돌, 같은 칸을 다시 누르면 착수, 다른 칸은 미리보기 이동**. 착수·거절은 스토어 범위([GomokuStore.scope])에서
 * 부른다 — 화면을 떠나도 보낸 수는 끝까지 간다(Swift `Task { await store.place }`).
 *
 * [focusedForbidden] 은 금수 자리를 눌렀을 때 상태줄이 그 이유를 1순위로 말하게 하는 바깥 상태다.
 */
@Composable
fun GomokuPlayBoard(
    gomoku: GomokuStore,
    match: GomokuMatchState,
    side: Dp,
    forbidden: Map<GomokuPoint, GomokuForbiddenReason>,
    preview: GomokuTapPreview,
    onPreviewChanged: () -> Unit,
    onFocusedForbidden: (GomokuForbiddenReason?) -> Unit,
    warningIntensity: Double,
    modifier: Modifier = Modifier,
) {
    var tapTick by remember { mutableIntStateOf(0) }
    // 미리보기는 화면이 드는 작은 가변 값(GomokuTapPreview)이라 탭마다 이 칸을 올려 다시 그린다.
    val previewPoint = tapTick.let { preview.visiblePoint(match, gomoku.isBusy, forbidden) }
    val picture = GomokuBoardPicture(
        board = match.board, lastMove = match.lastMove, forbidden = forbidden, autoPoints = match.autoPoints,
        preview = previewPoint?.let { it to match.myColor },
    )
    val measurer = rememberTextMeasurer()
    val colors = AingTheme.colors
    val pending = colors.pending
    val working = colors.working
    val accent = colors.accent
    Box(
        modifier
            .size(side)
            .testTag(GomokuScreenTags.board)
            .semantics { contentDescription = GomokuScreenText.boardAccessibility(match, forbidden.size) }
            .pointerInput(match.id, match.moveCount, match.turn, match.isFinished, gomoku.isBusy, forbidden) {
                detectTapGestures { location ->
                    val g = gomokuGeometry(size.width.toFloat(), picture)
                    val point = g.point(BoardPoint(location.x.toDouble(), location.y.toDouble()))
                    when (val outcome = preview.tap(point, match, gomoku.isBusy, forbidden)) {
                        GomokuTapOutcome.none -> Unit
                        is GomokuTapOutcome.preview -> onFocusedForbidden(null)
                        is GomokuTapOutcome.place -> {
                            onFocusedForbidden(null)
                            val seen = GomokuSeenTurn(match)
                            gomoku.scope.launch { gomoku.place(outcome.point, seen) }
                        }
                        is GomokuTapOutcome.refuse -> {
                            onFocusedForbidden(forbidden[outcome.point])
                            val seen = GomokuSeenTurn(match)
                            gomoku.scope.launch { gomoku.place(outcome.point, seen) }
                        }
                    }
                    tapTick += 1
                    onPreviewChanged()
                }
            },
    ) {
        Canvas(Modifier.size(side)) {
            drawGomokuBoard(picture, measurer, pending = pending, working = working, accent = accent)
            if (warningIntensity > 0) drawGomokuEdgeGlow(warningIntensity)
        }
    }
}
