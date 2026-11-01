// 원본: Sources/CheckMobileKit/Games/GamesChessBoardCanvas.swift @ 3bd04bd · 손에 든 말 · 끌기 어댑터: Sources/check/ChessPanel.swift:379,637-815 @ 1a5eeca6
//
// 폰 체스 판 — 8×8 을 Canvas **한 장**으로 그리고, 움직이는 말은 프레임 루프가 프레임마다 다시 묻는다.
// 수학은 여기 없다: 시각·이징·칸 셈은 [ChessMoveFlight], 화면 좌표·뒤집기는 core/stores 의 `ChessPhoneBoardGeometry`(px 축으로 만든다),
// 실루엣은 [ChessPieceArt]. 이 파일은 받은 숫자를 사각형으로 바꿔 그리기만 한다.
//
// 색 상수가 **렌더 판정의 감지기**다(맥 `ChessBoardView` 와 같은 규칙): 칸 색과 덮개(마지막 수·선택·체크·도착 점)는 전부 중간 톤이고 **말만 극단**이다
// (최대 채널 ≥ 235 또는 최소 채널 ≤ 55). 그래서 "칸 가운데에 극단 픽셀이 있는가" 가 곧 "그 자리에 말이 있는가" 다. 판은 물건이라 외관과 무관하게 같다.
package com.yehsung.aingcheck.ui.games.chess

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalViewConfiguration
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
import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.rules.chess.ChessPiece
import com.yehsung.aingcheck.core.rules.chess.ChessPosition
import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.stores.chess.ChessBoardPointer
import com.yehsung.aingcheck.core.stores.chess.ChessDragGrab
import com.yehsung.aingcheck.core.stores.chess.ChessPendingDrop
import com.yehsung.aingcheck.core.stores.chess.ChessPhoneBoardGeometry
import com.yehsung.aingcheck.core.stores.gomoku.BoardPoint
import com.yehsung.aingcheck.core.stores.gomoku.BoardRect
import com.yehsung.aingcheck.ui.theme.AingColors

/** 판 그림 상수(sRGB — Swift `GamesChessBoardCanvas` 정적 색). */
object ChessBoardInk {
    // 칸 — 둘 다 중간 톤(최대 ≤ 204 · 최소 ≥ 71).
    val lightSquare = Color(0.80f, 0.72f, 0.60f)
    val darkSquare = Color(0.44f, 0.35f, 0.28f)
    // 말 — **여기만 극단**이다.
    val whitePiece = Color(0.96f, 0.96f, 0.96f)
    val whitePieceEdge = Color(0.10f, 0.10f, 0.10f)
    val blackPiece = Color(0.10f, 0.10f, 0.10f)
    val blackPieceEdge = Color(0.90f, 0.90f, 0.90f)
    // INV-GamesChessBoardCanvas-2eac35ac 이식: 덮개 — 전부 **중간 톤으로 떨어지는 불투명도**를 골랐다(극단으로 바꾸면 빈 칸이 말로 세어져 렌더 판정이 조용히
    //   쓸모없어진다). 판은 물건이라 라이트 토큰 하나로 칠한다(다크에서 더 밝은 파랑이 극단에 닿지 않게).
    val lastMoveTint: Color = AingColors.Light.pending
    const val LAST_MOVE_OPACITY: Float = 0.35f
    val selectedTint: Color = AingColors.Light.accent
    const val SELECTED_OPACITY: Float = 0.35f
    val targetTint: Color = AingColors.Light.accent
    const val TARGET_OPACITY: Float = 0.60f
    val checkTint: Color = AingColors.Light.danger
    const val CHECK_OPACITY: Float = 0.45f
    /** 끄는 말 밑이 갈 수 있는 칸이면 그 칸을 한 단 더 진하게(맥 `dropTargetOpacity` — 놓으면 어디로 가는지). 이 덮개도 중간 톤으로 떨어진다. */
    const val DROP_TARGET_OPACITY: Float = 0.28f
}

/**
 * 판 위에서 **제자리를 떠나 있는 말 한 장** — 끄는 중이거나, 놓고 답을 기다리는 중이다(Swift `ChessBoardLift`). 그림의 규칙이 같다: 출발 칸에는 그리지 않고 다른 자리에 **맨 위로** 그린다.
 * 판에는 **한 번에 한 장**만 든다.
 */
data class ChessBoardLift(val piece: ChessPiece, val from: ChessSquare, val place: Place) {
    sealed interface Place {
        /** 끄는 중 — 손가락 점(판 좌표 px). 말은 [fingerCenter] 에 그린다. */
        data class Finger(val x: Float, val y: Float) : Place

        /** 놓았다 — 그 칸에 그대로 선다(답을 기다리는 중 · 승격을 고르는 중). */
        data class Square(val square: ChessSquare) : Place
    }

    companion object {
        /**
         * 끄는 말의 크기(칸 대비). 맥은 커서가 말을 가리지 않아 1.12 다. 폰은 손가락이 칸만 하므로 크게 든다.
         */
        const val FINGER_SCALE: Float = 1.5f

        /** 끄는 말을 손가락 위로 올리는 거리(칸 대비) — 손가락에 가리면 무엇을 드는지 안 보인다. 놓는 칸은 **손가락 점**이다(덮개가 그 칸을 말한다). */
        const val FINGER_RAISE_CELLS: Float = 0.75f

        /**
         * 끄는 말의 **중심**. 손가락 위로 올리되 판 변에서 **그려지는 말의 반폭**만큼 안쪽으로 묶는다(Swift `ChessBoardView.cursorCenter`) — 판은 Canvas 한 장이라 그 밖은 잘린다.
         * 숫자가 아닌 좌표는 0 으로 읽는다(그 뒤 같은 묶기를 지난다) — 판을 깨지 않는다.
         */
        fun fingerCenter(x: Float, y: Float, cell: Float, side: Float): Offset {
            val half = cell * ChessPieceArt.FILL_FRACTION * FINGER_SCALE / 2f
            // 말보다 작은 판은 없지만, 있다면 위아래 한계가 뒤집히지 않게 한가운데로 모은다.
            val low = minOf(half, side / 2f)
            val high = maxOf(side - half, side / 2f)
            fun bound(value: Float) = minOf(high, maxOf(low, if (value.isNaN()) 0f else value))
            return Offset(bound(x), bound(y - cell * FINGER_RAISE_CELLS))
        }
    }
}

private fun BoardRect.toRect(): Rect = Rect(x.toFloat(), y.toFloat(), (x + width).toFloat(), (y + height).toFloat())

/** 판 그림 한 장의 재료. 관전 판은 [selected]·[targets] 를 늘 비운다(부르는 쪽 [ChessBoard] 가 끊는다). */
data class ChessBoardPicture(
    val position: ChessPosition?,
    val whiteAtBottom: Boolean,
    val lastMove: Pair<ChessSquare, ChessSquare>? = null,
    val selected: ChessSquare? = null,
    val targets: Set<ChessSquare> = emptySet(),
    val checkSquare: ChessSquare? = null,
    val showsCoordinates: Boolean = true,
    /** 손에 든 말(끄는 중 · 놓고 답을 기다리는 중). null = 멈춘 국면 = 이 값이 생기기 전과 같은 그림이다. */
    val lifted: ChessBoardLift? = null,
    /** 끄는 손가락 밑의 갈 수 있는 칸. */
    val dropTarget: ChessSquare? = null,
)

fun chessGeometry(sidePx: Float, whiteAtBottom: Boolean): ChessPhoneBoardGeometry =
    ChessPhoneBoardGeometry(side = sidePx.toDouble(), orientation = if (whiteAtBottom) ChessColor.white else ChessColor.black)

fun DrawScope.drawChessBoard(picture: ChessBoardPicture, frame: ChessFlightFrame?, measurer: TextMeasurer) {
    val side = size.minDimension
    val g = chessGeometry(side, picture.whiteAtBottom)
    val cell = g.cell.toFloat()
    fun rect(square: ChessSquare): Rect = g.rect(square).toRect()
    // ① 칸 64개
    for (index in 0 until 64) {
        val square = ChessSquare.of(index) ?: continue
        val r = rect(square)
        drawRect(if (square.isLightSquare) ChessBoardInk.lightSquare else ChessBoardInk.darkSquare, topLeft = r.topLeft, size = r.size)
    }
    // ② 덮개 — 마지막 수 → 선택 → 체크(뒤가 위). 폰에는 호버가 없다.
    picture.lastMove?.let { (from, to) ->
        for (square in listOf(from, to)) {
            val r = rect(square)
            drawRect(ChessBoardInk.lastMoveTint.copy(alpha = ChessBoardInk.LAST_MOVE_OPACITY), topLeft = r.topLeft, size = r.size)
        }
    }
    picture.selected?.let { val r = rect(it); drawRect(ChessBoardInk.selectedTint.copy(alpha = ChessBoardInk.SELECTED_OPACITY), topLeft = r.topLeft, size = r.size) }
    picture.checkSquare?.let { val r = rect(it); drawRect(ChessBoardInk.checkTint.copy(alpha = ChessBoardInk.CHECK_OPACITY), topLeft = r.topLeft, size = r.size) }
    picture.dropTarget?.let { val r = rect(it); drawRect(ChessBoardInk.targetTint.copy(alpha = ChessBoardInk.DROP_TARGET_OPACITY), topLeft = r.topLeft, size = r.size) }
    // ③ 좌표(가장자리 칸 **안쪽**)
    if (picture.showsCoordinates) {
        val fontPx = maxOf(8f * density, cell * 0.17f)
        fun style(square: ChessSquare) = TextStyle(
            fontSize = (fontPx / density / fontScale).sp, fontWeight = FontWeight.Bold,
            color = if (square.isLightSquare) ChessBoardInk.darkSquare else ChessBoardInk.lightSquare,
        )
        for (file in 0 until 8) {
            val square = ChessSquare.at(file, if (picture.whiteAtBottom) 0 else 7) ?: continue
            val box = rect(square)
            drawCentered(measurer, ('a'.code + file).toChar().toString(), style(square), Offset(box.right - fontPx * 0.55f, box.bottom - fontPx * 0.6f))
        }
        for (rank in 0 until 8) {
            val square = ChessSquare.at(if (picture.whiteAtBottom) 0 else 7, rank) ?: continue
            val box = rect(square)
            drawCentered(measurer, "${rank + 1}", style(square), Offset(box.left + fontPx * 0.6f, box.top + fontPx * 0.6f))
        }
    }
    // ④ 갈 수 있는 칸 — 빈 칸은 점, 잡는 칸은 고리(점을 말 위에 찍으면 무엇을 잡는지 가린다).
    for (target in picture.targets) {
        val box = rect(target)
        if (picture.position?.get(target) != null) {
            val inset = cell * 0.07f
            drawOval(ChessBoardInk.targetTint.copy(alpha = ChessBoardInk.TARGET_OPACITY), topLeft = Offset(box.left + inset, box.top + inset),
                size = androidx.compose.ui.geometry.Size(box.width - inset * 2, box.height - inset * 2), style = Stroke(cell * 0.09f))
        } else {
            drawCircle(ChessBoardInk.targetTint.copy(alpha = ChessBoardInk.TARGET_OPACITY), radius = cell * 0.15f, center = box.center)
        }
    }
    // ⑤ 말 — 세 겹(+끌어 놓은 말 한 겹)으로 **갈라서** 그린다.
    val position = picture.position ?: return
    // ⑤a 멈춘 말
    for (index in 0 until 64) {
        val square = ChessSquare.of(index) ?: continue
        val piece = position[square] ?: continue
        // INV-GamesChessBoardCanvas-1f8d4ec2 이식: 날고 있는 말의 **도착** 칸은 뺀다 — position 은 이미 수를 둔 뒤의 배치라 안 빼면 같은 말이 도착 칸과
        //   궤적 위에 둘로 보인다(캐슬링이면 셋·넷).
        if (frame?.hidden?.contains(square) == true) continue
        if (square == frame?.landed) continue
        // 손에 든 말의 출발 칸은 비운다 — 안 빼면 같은 말이 두 자리에 보인다.
        if (square == picture.lifted?.from) continue
        drawPiece(piece, rect(square), cell, 1f)
    }
    // ⑤b 판에서 빠지는 말 — 멈춘 말 위, 날고 있는 말 아래(잡힌 말은 position 에 이미 없다 — 여기가 비면 "말이 갑자기 사라진다"로 돌아간다).
    frame?.leaving?.let { leaving ->
        val shift = g.offset(leaving.fileOffset, leaving.rankOffset)
        val base = g.rect(leaving.square)
        val moved = BoardRect(base.x + shift.width, base.y + shift.height, base.width, base.height)
        val box = g.scaled(moved, leaving.scale).toRect()
        // INV-GamesChessBoardCanvas-f743ebd1 이식: 불투명도는 **이 말 한 장에만** 건다 — 그리기 판 전체(뒤에 그리는 ⑤c 날고 있는 말까지)에 걸면 잡는 수마다
        //   잡은 말이 도착하며 투명해진다(Swift 는 GraphicsContext 사본, 여기는 drawPath 의 alpha 인자 하나).
        drawPiece(leaving.piece, box, cell, leaving.opacity.toFloat())
    }
    // ⑤c 날고 있는 말 — 맨 위, 배열 순서대로(캐슬링에서 왕이 룩 위). 지나가는 칸의 말을 덮으므로 나이트가 말을 뛰어넘는 것이 보인다.
    frame?.moving?.forEach { moving -> drawPiece(moving.piece, g.rect(moving.from, moving.to, moving.t).toRect(), cell, 1f) }
    // ⑤d 끌어 놓아 이미 도착해 있는 말 — 잡힌 말·캐슬링 룩보다 위(날지 않는다, 손이 옮겨 놓았다).
    frame?.landed?.takeIf { it != picture.lifted?.from }?.let { landed -> position[landed]?.let { drawPiece(it, rect(landed), cell, 1f) } }
    // ⑥ 손에 든 말 — **맨 위**. 판 위의 무엇도 손에 든 말을 가리지 않는다.
    picture.lifted?.let { lifted ->
        when (val place = lifted.place) {
            is ChessBoardLift.Place.Square -> drawPiece(lifted.piece, rect(place.square), cell, 1f)
            is ChessBoardLift.Place.Finger -> {
                val center = ChessBoardLift.fingerCenter(place.x, place.y, cell, side)
                val half = cell * ChessBoardLift.FINGER_SCALE / 2f
                drawPiece(lifted.piece, Rect(center.x - half, center.y - half, center.x + half, center.y + half), cell, 1f)
            }
        }
    }
}

/**
 * 사각형 하나에 말 하나.
 * INV-GamesChessBoardCanvas-5a4c050e 이식: 색은 **극단 그대로**다 — 날고 있는 말을 중간 톤으로 흐리면 "말이 두 칸 사이에 있다"를 재는 판정이 공허해진다
 *   (불투명도는 빠지는 말 한 장에만 — 위 ⑤b).
 * INV-GamesChessBoardCanvas-ed4c50d8 이식: **그림자를 쓰지 않는다** — 같은 장면을 여러 번 구워 픽셀을 비교하는 스냅숏이 그림자 경로에서 흔들리지 않게(판 위
 *   말에도, 판을 감싸는 틀에도 그림자 수정자를 달지 않는다).
 */
private fun DrawScope.drawPiece(piece: ChessPiece, box: Rect, cell: Float, alpha: Float) {
    val path = ChessPieceArt.path(piece.kind, box)
    val white = piece.color == ChessColor.white
    drawPath(path, if (white) ChessBoardInk.whitePiece else ChessBoardInk.blackPiece, alpha = alpha)
    drawPath(path, if (white) ChessBoardInk.whitePieceEdge else ChessBoardInk.blackPieceEdge, alpha = alpha, style = Stroke(maxOf(0.8f * density, cell * 0.035f)))
}

private fun DrawScope.drawCentered(measurer: TextMeasurer, text: String, style: TextStyle, center: Offset) {
    val layout = measurer.measure(text, style)
    drawText(layout, topLeft = Offset(center.x - layout.size.width / 2f, center.y - layout.size.height / 2f))
}

/** 판 그림만(입력·애니메이션 없음 — 승격 시트 칸 · 스냅숏). */
@Composable
fun ChessBoardCanvas(picture: ChessBoardPicture, side: Dp, modifier: Modifier = Modifier, frame: ChessFlightFrame? = null) {
    val measurer = rememberTextMeasurer()
    Canvas(modifier.size(side)) { drawChessBoard(picture, frame, measurer) }
}

/**
 * 끌어 두기의 스토어 문(Swift `ChessPlayBoard` 가 스토어에서 읽고 부르는 것들). **판단은 여기 없다** — 둘 수 있는가는 스토어, 누름의 해석은 [ChessBoardPointer] 다.
 * 이 값은 조성마다 새로 온다. 제스처는 [rememberUpdatedState] 로 **지금** 값을 읽는다(키로 걸면 판이 다시 그려질 때마다 제스처가 죽어 끌던 말이 손에서 떨어진다).
 *
 * @param origin 스토어 걸쇠(`dragOrigin`). 스토어가 먼저 내렸으면(화면 가림) 끌기를 거둔다.
 * @param pending 놓고 답을 기다리는 말(이 판의 것만). 끄는 말보다 먼저다.
 * @param premise 끌기의 전제(판 id · 수 번호 · 내 차례 · 왕복 중 · 창 표시). 하나라도 바뀌면 끌던 말을 거둔다 — 스토어의 걸쇠를 안 보고 **날 값**을 본다. 한쪽이 계기를 놓쳐도 다른 쪽이 잡는다.
 */
class ChessBoardDragPort(
    val grab: (ChessSquare) -> ChessDragGrab,
    val isSelectionTarget: (ChessSquare) -> Boolean,
    val begin: (ChessSquare) -> Boolean,
    val drop: (from: ChessSquare, on: ChessSquare?) -> Unit,
    val cancel: () -> Unit,
    val origin: ChessSquare?,
    val pending: ChessPendingDrop?,
    val premise: Any?,
)

/**
 * 판 하나의 끌기 상태(Swift `ChessPlayBoard` 의 @State 셋 — 화면에서 태어나 화면에서 죽는다). 끄는 자리를 스토어에 두지 않는 까닭은 손가락이 움직일 때마다 바뀌기 때문이다.
 * [perform] 은 해석기가 낸 행동을 스토어 문으로 옮긴다. **판단은 여기 없다.**
 */
internal class ChessBoardDragState(threshold: Double, val port: State<ChessBoardDragPort>, private val tap: State<(ChessSquare) -> Unit>) {
    val pointer = ChessBoardPointer(threshold)
    val dragPoint = mutableStateOf<Offset?>(null)

    /** 지금 누름이 **시작될 때 본** 전제. 통지가 왔을 때 "그 변화가 이 누름 뒤에 일어났는가"를 가르는 기준이다 — 상대 수가 닿은 바로 그 프레임에 집은 말이 손에서 떨어지지 않게. */
    var pressPremise: Any? = null

    fun perform(actions: List<ChessBoardPointer.Action>) {
        for (action in actions) {
            when (action) {
                is ChessBoardPointer.Action.Tap -> tap.value(action.square)
                is ChessBoardPointer.Action.BeginDrag -> {
                    // 누른 뒤 문턱을 넘기 전에 판이 바뀌었으면 스토어가 거절한다(문구는 스토어가 말했다). 뒤따르는 행동(끄는 자리 · 놓기)은 버린다.
                    if (!port.value.begin(action.square)) {
                        pointer.dragRefused()
                        return
                    }
                }
                is ChessBoardPointer.Action.DragMoved -> dragPoint.value = Offset(action.point.x.toFloat(), action.point.y.toFloat())
                is ChessBoardPointer.Action.Drop -> {
                    dragPoint.value = null
                    port.value.drop(action.from, action.on)
                }
                ChessBoardPointer.Action.Cancel -> {
                    dragPoint.value = null
                    port.value.cancel()
                }
            }
        }
    }
}

/**
 * 판 위 탭 + 끌기를 **제스처 하나**로 받는다(Swift `DragGesture(minimumDistance: 0)` 자리). 둘로 나누면 문턱을 살짝 넘긴 누름에 둘이 함께 답한다 — 어느 쪽인지는 해석기 한 곳이 정한다.
 *
 * 스크롤과 겹치면 **판 위 끌기가 먼저다**: 지금 끌 수 있는 내 말을 누른 손가락은 움직임을 처음부터 소비해 부모 스크롤이 시작되지 못한다(문턱을 기다리면 스크롤이 먼저 가져간다).
 * 끌 수 없는 누름(빈 칸 · 상대 말 · 도착 칸 · 못 끄는 내 말)은 소비하지 않는다 — 판 위에서 시작해도 화면은 스크롤되고, 스크롤이 가져가면 그 누름은 탭도 안 낸다.
 */
private fun Modifier.chessDragGestures(whiteAtBottom: Boolean, state: ChessBoardDragState): Modifier =
    pointerInput(whiteAtBottom, state) {
        awaitEachGesture {
            val g = chessGeometry(size.width.toFloat(), whiteAtBottom)
            fun point(at: Offset) = BoardPoint(at.x.toDouble(), at.y.toDouble())
            fun square(at: Offset): ChessSquare? = g.square(point(at))
            val down = awaitFirstDown(requireUnconsumed = false)
            val pressed = square(down.position)
            val door = state.port.value
            val grab = pressed?.let(door.grab) ?: ChessDragGrab.none
            val isTarget = pressed?.let(door.isSelectionTarget) ?: false
            state.pressPremise = door.premise
            state.perform(state.pointer.press(point(down.position), pressed, grab, isTarget))
            val claimsTheFinger = grab == ChessDragGrab.movable && !isTarget
            if (claimsTheFinger) down.consume()
            var finished = false
            try {
                while (true) {
                    val event = awaitPointerEvent()
                    val change = event.changes.firstOrNull { it.id == down.id } ?: continue
                    if (!change.pressed) {
                        state.perform(state.pointer.release(point(change.position), square(change.position)))
                        change.consume()
                        finished = true
                        break
                    }
                    state.perform(state.pointer.move(point(change.position)))
                    if (claimsTheFinger) {
                        change.consume()
                    } else if (awaitPointerEvent(PointerEventPass.Final).changes.any { it.id == down.id && it.isConsumed }) {
                        // 부모 스크롤이 가져갔다 — Main 차례는 자식이 먼저라 Final 에서 본다(detectTapGestures 와 같은 자리).
                        state.perform(state.pointer.stolenByScroll())
                    }
                }
            } finally {
                // 뗌 없이 끝났다(제스처가 죽었다) — 끌던 말을 공중에 남기지 않는다.
                if (!finished) {
                    state.perform(state.pointer.stolenByScroll())
                    state.pointer.release(point(down.position), null)
                }
            }
        }
    }

/**
 * 대국·관전·로봇 화면이 쓰는 판 — 애니메이션을 프레임으로 풀고, 탭을 칸으로 바꾼다.
 *
 * INV-GamesChessBoardCanvas-7de9893a 이식: [onTapSquare] 가 **null 이면 관전 판**이다 — 탭·선택·도착 점이 전부 없어야 한다. 관전자는 "내 차례·내 색"이 없으므로
 *   그 둘에 매인 그림을 **여기서 끊는다**(부르는 쪽이 매번 빈 값을 넘기기를 믿지 않는다).
 * INV-GamesChessBoardCanvas-93bbbe41 이식: [whiteAtBottom] **하나**가 뒤집기를 쥔다 — 내 색이 아래여야 판이 읽히고, 관전자는 백이 아래가 관례다.
 * INV-GamesChessBoardCanvas-63de5f51 이식: 체크([checkSquare])는 **관전 판에서도 그린다** — 선택·도착 점과 달리 "내 차례·내 색"에 매이지 않은 판의 사실이다.
 * [drag] 가 있으면 탭에 끌기를 더한다(탭은 그대로다). null 이면 지금까지처럼 탭만이다 — 부르는 쪽이 켠다(안드로이드 대국 · 로봇 판).
 */
@Composable
fun ChessBoard(
    position: ChessPosition,
    flight: ChessMoveFlight?,
    whiteAtBottom: Boolean,
    selection: ChessSquare?,
    legalTargets: Set<ChessSquare>,
    lastMove: Pair<ChessSquare, ChessSquare>?,
    checkSquare: ChessSquare?,
    onTapSquare: ((ChessSquare) -> Unit)?,
    side: Dp,
    onFlightFinished: (generation: Int) -> Unit,
    modifier: Modifier = Modifier,
    accessibility: String? = null,
    testTag: String = "chess-board",
    drag: ChessBoardDragPort? = null,
) {
    val interactive = onTapSquare != null
    val dragState = if (drag != null && onTapSquare != null) rememberChessBoardDragState(drag, onTapSquare) else null
    val sidePx = with(LocalDensity.current) { side.toPx() }
    val lifted = drag?.let { port -> chessBoardLift(port, dragState, position) }
    // 끄는 말 밑이 갈 수 있는 칸이면 그 칸을 한 단 더 진하게.
    val dropTarget = (lifted?.place as? ChessBoardLift.Place.Finger)?.let { finger ->
        chessGeometry(sidePx, whiteAtBottom).square(BoardPoint(finger.x.toDouble(), finger.y.toDouble()))?.takeIf { it in legalTargets }
    }
    val picture = ChessBoardPicture(
        position = position, whiteAtBottom = whiteAtBottom, lastMove = lastMove,
        selected = if (interactive) selection else null,
        targets = if (interactive) legalTargets else emptySet(),
        checkSquare = checkSquare,
        lifted = lifted,
        dropTarget = dropTarget,
    )
    var frameNanos by remember { mutableLongStateOf(0L) }
    // INV-GamesChessBoardCanvas-8161a594 이식: **애니메이션이 없으면 한 틱도 돌지 않는다**(배터리 계약 — Swift `paused: flight == nil`). 판은 대국 화면에 늘
    //   떠 있어서 루프가 굳으면 아무도 수를 안 두는 동안에도 64칸 + 32말을 매 프레임 다시 그린다. 진행은 **프레임 시각**으로 센다 — 시작 시각은 값이
    //   들고 있고(스토어 시계 축), 프레임 사이 경과만 더한다.
    var firstFrame by remember(flight?.generation) { mutableLongStateOf(-1L) }
    if (flight != null) {
        LaunchedEffect(flight.generation) {
            while (true) {
                val nanos = withFrameNanos { it }
                if (firstFrame < 0) firstFrame = nanos
                frameNanos = nanos
                val now = flight.startedAt.addingTimeInterval((nanos - firstFrame) / 1e9)
                if (flight.isFinished(now)) {
                    onFlightFinished(flight.generation)
                    break
                }
            }
        }
    }
    val frame = flight?.let { f ->
        val elapsed = if (firstFrame < 0) 0.0 else (frameNanos - firstFrame) / 1e9
        f.frame(f.startedAt.addingTimeInterval(elapsed))
    }
    val measurer = rememberTextMeasurer()
    var tapModifier: Modifier = Modifier
    if (dragState != null) {
        tapModifier = Modifier.chessDragGestures(whiteAtBottom, dragState)
    } else if (onTapSquare != null) {
        tapModifier = Modifier.pointerInput(whiteAtBottom, onTapSquare) {
            detectTapGestures { location ->
                val g = chessGeometry(size.width.toFloat(), whiteAtBottom)
                // 판 밖은 조용하다(거절이 아니라 빈 곳). 둘 수 있는가의 판정은 받는 쪽(스토어)에 있다 — 화면이 미리 걸러 삼키지 않는다.
                g.square(BoardPoint(location.x.toDouble(), location.y.toDouble()))?.let(onTapSquare)
            }
        }
    }
    Canvas(
        modifier.size(side).testTag(testTag).then(tapModifier)
            .semantics { contentDescription = accessibility ?: "체스판" },
    ) { drawChessBoard(picture, frame, measurer) }
}

@Composable
private fun rememberChessBoardDragState(drag: ChessBoardDragPort, onTapSquare: (ChessSquare) -> Unit): ChessBoardDragState {
    val port = rememberUpdatedState(drag)
    val tap = rememberUpdatedState(onTapSquare)
    // 폰의 문턱은 플랫폼 터치 슬롭이다(맥 4pt 는 마우스 값 — ChessBoardPointer 머리말).
    val slop = LocalViewConfiguration.current.touchSlop.toDouble()
    val state = remember(slop) { ChessBoardDragState(slop, port, tap) }
    // 끄는 중에 판이 바뀌었다 — 끌기를 즉시 거두고 말을 제자리에. 그 뒤 손가락을 떼도 수가 나가지 않는다(해석기가 소진 · 스토어 걸쇠가 이중 안전).
    // **그 누름이 본 판과 지금 판이 다를 때만** 거둔다: 이 통지는 값이 바뀐 다음 그리기에 온다 — 그사이에 시작한 누름은 이미 바뀐 판을 보고 눌렀다.
    LaunchedEffect(drag.premise) {
        if (state.pressPremise != drag.premise) state.perform(state.pointer.cancel())
    }
    // 스토어가 먼저 걸쇠를 내렸다(화면 가림처럼 이 뷰가 볼 수 없는 계기). 해석기가 **그 끌기를 아직 붙들고 있을 때만** 거둔다.
    LaunchedEffect(drag.origin) {
        val from = state.pointer.draggingFrom
        if (from != null && drag.origin != from) state.perform(state.pointer.cancel())
    }
    // 화면이 내려갔다 — 걸쇠를 남기지 않는다.
    DisposableEffect(state) {
        onDispose { if (state.pointer.draggingFrom != null) state.perform(state.pointer.stolenByScroll()) }
    }
    return state
}

/**
 * 손에 든 말. **놓은 말이 먼저다**(스토어가 판·수 번호를 맞춰 본 값 — 자기 치유는 거기서 한다). 끄는 말은 넷이 다 맞을 때만 그린다: 해석기가 끄는 중이다 · 끄는 자리가 있다 ·
 * 스토어 걸쇠가 같은 칸이다 · 그 칸에 말이 있다. 하나라도 어긋나면 말은 판이 말하는 제자리에 그려진다(유령 말 없음).
 */
private fun chessBoardLift(port: ChessBoardDragPort, state: ChessBoardDragState?, position: ChessPosition): ChessBoardLift? {
    port.pending?.let { return ChessBoardLift(it.piece, it.from, ChessBoardLift.Place.Square(it.to)) }
    val active = state ?: return null
    val point = active.dragPoint.value ?: return null
    val from = active.pointer.draggingFrom ?: return null
    if (port.origin != from) return null
    val piece = position[from] ?: return null
    return ChessBoardLift(piece, from, ChessBoardLift.Place.Finger(point.x, point.y))
}
