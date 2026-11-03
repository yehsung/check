// 원본: Sources/CheckMobileKit/Games/GamesReversiBoard.swift:86-348(판 그림 · 판 입력 · 3초 테두리 · 돌 하나) @ ios-1017-int 467aec40
//
// 폰 아잉 뒤집기 **판**. 맥 `ReversiPanelBoard` 의 좌표계·그리는 순서·색을 iOS 폰 판이 옮긴 것을 다시 Compose 로 옮겼다. 좌표·칸 판정은 core/stores 의
// [GamesReversiBoardGeometry] 하나다(JVM 시험이 값으로 잰다).
//
// 지키는 약속(iOS 머리 그대로):
//  · **방향 뒤집기가 없다 — 1행이 위, a열이 왼쪽**(`idx = row*8 + col`). 체스처럼 내 색을 아래로 돌리지 않는다.
//  · **둘 수 있는 칸은 판이 계산하지 않는다.** 1:1 은 서버 `legal_moves`, 로봇 판은 로컬 규칙이 이미 코어 `legalTargets` 에 들어 있고 판은 그것만 점으로 그린다.
//    이 파일에 `ReversiRules` 가 나오지 않는다.
//  · **입력은 한 단이다** — 칸 하나를 누르면 곧바로 `place`. 거절(내 차례 아님 · 보내는 중 · 이미 돌 · 뒤집을 돌 없음)은 **코어가 문구로 말한다**.
//    조용해도 되는 길은 판 밖 하나뿐이다.
//  · **뒤집기 애니메이션은 코어 값**(`ReversiFlipAnimation`)을 프레임마다 읽기만 한다. 불투명도를 건드리지 않고 가로 비율만 |cos| 로 줄였다 편다.
//    애니메이션이 없으면 펌프가 한 틱도 돌지 않는다(배터리).
//  · 판 그림에 그림자 효과를 쓰지 않는다 — 돌 그림자는 자체 타원이다(판 바깥 그림자는 감싸는 화면의 몫).
//  · TalkBack: 칸마다 노드("d3, 흑 돌, 마지막 수" · "c4, 빈칸, 둘 수 있어요") — 두 번 탭이 곧 착수다. 칸 노드는 누름을 가로채지 않는다(semantics 만).
package com.yehsung.aingcheck.ui.games.reversi

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.renju.GomokuTurnWarning
import com.yehsung.aingcheck.core.rules.reversi.ReversiFlipAnimation
import com.yehsung.aingcheck.core.rules.reversi.ReversiTurnWarning
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiBoardCells
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiBoardGeometry
import com.yehsung.aingcheck.core.stores.reversi.ReversiPhoneText
import com.yehsung.aingcheck.core.stores.reversi.ReversiStore
import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.ui.games.gomoku.drawGomokuEdgeGlow
import com.yehsung.aingcheck.ui.games.gomoku.rememberTicker

/** 판 그림 색 — 맥·iOS 판과 같은 값(두 플랫폼이 같은 판을 그린다 · 라이트·다크 같은 판이라 고정색이다). 칸은 중간 톤 초록 · 돌만 극단. */
object ReversiBoardInk {
    val felt = Color(0.32f, 0.58f, 0.42f)
    val line = Color(0.24f, 0.44f, 0.31f)
    val coordinate = Color(0.70f, 0.85f, 0.72f)
    val blackStone = Color(0.10f, 0.10f, 0.10f)
    val blackStoneHighlight = Color(0.30f, 0.30f, 0.30f)
    val whiteStone = Color(0.96f, 0.96f, 0.96f)
    val whiteStoneShade = Color(0.86f, 0.86f, 0.86f)
    const val stoneRadiusRatio: Float = 0.42f

    /** 둘 수 있는 칸 점(반지름 0.15칸). 초록 위에서 읽히는 파랑. */
    val target = Color(0.36f, 0.66f, 1.0f)
    const val targetOpacity: Float = 0.70f
    const val targetRadiusRatio: Float = 0.15f
    val autoStone = Color(0.62f, 0.62f, 0.62f)
    val lastMove = Color(0.95f, 0.30f, 0.26f)

    /** 판 바깥 그림자(감싸는 화면 몫 — iOS `.shadow(color: .black.opacity(0.16|0.35))`). */
    val shadowLight = Color.Black.copy(alpha = 0.16f)
    val shadowDark = Color.Black.copy(alpha = 0.35f)
}

/** 판 한 장의 그림 값(입력 없음). [flipNow] 는 뒤집기 프레임 시각(1970 기준 초 — 스토어 시계). */
data class ReversiBoardPicture(
    val board: ReversiBoard,
    val legalTargets: Set<Int> = emptySet(),
    val lastStoneIdx: Int? = null,
    val autoStones: Set<Int> = emptySet(),
    val flip: ReversiFlipAnimation? = null,
    val flipNow: Double? = null,
    /** 규칙 예시의 주황 고리(방금 뒤집힌 돌). */
    val rings: Set<Int> = emptySet(),
    val ringColor: Color = Color.Transparent,
)

/**
 * 8×8 판을 Canvas **한 장**으로 그린다. 그리는 순서(맥 §5.3): ① 초록 칸 + 격자선 + 화점 → ② 좌표 글자 → ③ 둘 수 있는 칸 점 → ④ 돌(뒤집히는 중이면 그 프레임) →
 * ⑤ 자동 착수 회색 점 → ⑥ 마지막 수 빨간 점(돌 위에만) → (예시) 주황 고리.
 */
fun DrawScope.drawReversiBoard(picture: ReversiBoardPicture, measurer: TextMeasurer) {
    val side = size.minDimension
    if (side <= 0f) return
    val g = GamesReversiBoardGeometry(side.toDouble())
    val cell = g.cell.toFloat()
    fun center(idx: Int): Offset = g.center(idx).let { (x, y) -> Offset(x.toFloat(), y.toFloat()) }

    // ① 초록 칸 + 격자선 + 네 화점
    drawRoundRect(ReversiBoardInk.felt, size = Size(side, side), cornerRadius = CornerRadius(side * GomokuTurnWarning.cornerRatio.toFloat()))
    val lineWidth = maxOf(1f, side / 400f)
    for (i in 1 until 8) {
        val offset = i * cell
        drawLine(ReversiBoardInk.line, Offset(offset, 0f), Offset(offset, side), lineWidth)
        drawLine(ReversiBoardInk.line, Offset(0f, offset), Offset(side, offset), lineWidth)
    }
    for ((x, y) in listOf(2 to 2, 6 to 2, 2 to 6, 6 to 6)) {
        drawCircle(ReversiBoardInk.line, maxOf(1.5f * density, cell * 0.06f), Offset(x * cell, y * cell))
    }

    // ② 좌표(가장자리 칸 안쪽). 글자는 1행 칸의 오른쪽 위, 숫자는 a열 칸의 왼쪽 위.
    val fontPx = maxOf(7f * density, cell * 0.17f)
    val style = TextStyle(fontSize = (fontPx / density / fontScale).sp, fontWeight = FontWeight.Bold, color = ReversiBoardInk.coordinate)
    for (col in 0 until 8) {
        val (bx, by) = g.origin(col)
        drawCentered(measurer, ('a'.code + col).toChar().toString(), style, Offset(bx.toFloat() + cell - fontPx * 0.6f, by.toFloat() + fontPx * 0.65f))
    }
    for (row in 0 until 8) {
        val (bx, by) = g.origin(row * 8)
        drawCentered(measurer, "${row + 1}", style, Offset(bx.toFloat() + fontPx * 0.6f, by.toFloat() + fontPx * 0.65f))
    }

    // ③ 둘 수 있는 칸 점 — 빈 칸에만.
    for (idx in picture.legalTargets) {
        if (idx !in 0 until 64 || picture.board[idx] != null) continue
        drawCircle(ReversiBoardInk.target.copy(alpha = ReversiBoardInk.targetOpacity), cell * ReversiBoardInk.targetRadiusRatio, center(idx))
    }

    // ④ 돌 — 뒤집히는 중인 칸은 그 프레임의 색·가로 비율로.
    val radius = cell * ReversiBoardInk.stoneRadiusRatio
    val flip = picture.flip
    val now = picture.flipNow
    for (idx in 0 until 64) {
        val color = picture.board[idx] ?: continue
        var shown = color
        var xScale = 1f
        if (flip != null && now != null) {
            val displayed = flip.displayedColor(idx, now)
            if (displayed != null) {
                shown = displayed
                xScale = flip.xScale(idx, now).toFloat()
            }
        }
        drawReversiStone(center(idx), radius, shown, xScale)
    }

    // ⑤ 자동 착수 회색 점 — 마지막 수 점보다 먼저, 더 크게(둘이 겹쳐도 둘 다 보인다).
    for (idx in picture.autoStones) {
        if (idx !in 0 until 64 || picture.board[idx] == null) continue
        drawCircle(ReversiBoardInk.autoStone, maxOf(3f * density, cell * 0.15f), center(idx))
    }

    // ⑥ 마지막 수 빨간 점(돌 위에만)
    val last = picture.lastStoneIdx
    if (last != null && last in 0 until 64 && picture.board[last] != null) {
        drawCircle(ReversiBoardInk.lastMove, maxOf(2.5f * density, cell * 0.10f), center(last))
    }

    // 예시 판의 주황 고리(방금 뒤집힌 돌).
    for (idx in picture.rings) {
        if (idx !in 0 until 64) continue
        drawCircle(picture.ringColor, cell * 0.46f, center(idx), style = Stroke(maxOf(1.5f * density, cell * 0.09f)))
    }
}

private fun DrawScope.drawCentered(measurer: TextMeasurer, text: String, style: TextStyle, center: Offset) {
    val layout = measurer.measure(text, style)
    drawText(layout, topLeft = Offset(center.x - layout.size.width / 2f, center.y - layout.size.height / 2f))
}

/** 돌 하나. 그림자는 **자체 타원**. [xScale] 은 뒤집히는 중의 가로 비율 — 불투명도는 바꾸지 않는다. */
fun DrawScope.drawReversiStone(c: Offset, r: Float, color: ReversiColor, xScale: Float) {
    val k = if (xScale.isNaN()) 1f else xScale.coerceIn(0f, 1f)
    val rx = r * k
    if (rx <= 0.2f) return
    drawOval(Color.Black.copy(alpha = 0.22f), Offset(c.x - rx + r * 0.05f, c.y - r + r * 0.12f), Size(rx * 2, r * 2))
    val discTopLeft = Offset(c.x - rx, c.y - r)
    val discSize = Size(rx * 2, r * 2)
    when (color) {
        ReversiColor.black -> {
            drawOval(ReversiBoardInk.blackStone, discTopLeft, discSize)
            drawOval(ReversiBoardInk.blackStoneHighlight.copy(alpha = 0.55f), Offset(c.x - rx * 0.55f, c.y - r * 0.72f), Size(rx * 0.7f, r * 0.45f))
        }
        ReversiColor.white -> {
            drawOval(ReversiBoardInk.whiteStone, discTopLeft, discSize)
            drawOval(ReversiBoardInk.whiteStoneShade.copy(alpha = 0.25f), Offset(c.x - rx * 0.86f, c.y - r * 0.2f), Size(rx * 1.72f, r * 1.12f))
            drawOval(Color.Black.copy(alpha = 0.25f), discTopLeft, discSize, style = Stroke(maxOf(0.8f * density, r * 0.04f)))
        }
    }
}

/** 입력 없는 그림 판(규칙 예시 · 시험). */
@Composable
fun ReversiBoardCanvas(picture: ReversiBoardPicture, side: Dp, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    Canvas(modifier.size(side)) { drawReversiBoard(picture, measurer) }
}

/**
 * 대국·결과·관전의 판 한 장. [onTap] 이 null 이면 입력 없는 판(결과 · 관전)이다.
 * ★ 뒤집기 프레임의 `now` 는 **스토어 시계**다(애니메이션 시작 시각이 그 시계로 찍혔다) — 펌프([rememberTicker])는 다시 그리게 깨우기만 한다.
 * ★ 칸 노드(TalkBack)는 누름을 가로채지 않는다 — 손가락 누름은 판의 pointerInput 하나가 받는다(반 칸 관용 없음 — [GamesReversiBoardGeometry.idx]).
 */
@Composable
fun ReversiPlayBoard(
    store: ReversiStore,
    matchID: String,
    board: ReversiBoard,
    side: Dp,
    legalTargets: Set<Int>,
    lastStoneIdx: Int?,
    autoStones: Set<Int>,
    turn: ReversiColor?,
    onTap: ((Int) -> Unit)?,
    modifier: Modifier = Modifier,
    warningIntensity: Double = 0.0,
    testTag: String = ReversiScreenTags.board,
) {
    // 지금 **이 판에서** 뒤집히는 수(값이 판 id 를 들고 있어 다른 판의 애니메이션이 새지 않는다).
    val flip = store.flip?.takeIf { it.matchID == matchID }
    val tick = rememberTicker(running = flip != null, periodMillis = 16)
    val flipNow = tick.let { if (flip != null) store.clock().timeIntervalSince1970 else null }
    val picture = ReversiBoardPicture(board, legalTargets, lastStoneIdx, autoStones, flip, flipNow)
    val measurer = rememberTextMeasurer()
    val cellSide = side / 8
    Box(
        modifier
            .size(side)
            .testTag(testTag)
            .semantics { contentDescription = ReversiPhoneText.boardAccessibility(board.counts, turn, legalTargets.size) }
            .let { m ->
                if (onTap == null) m else m.pointerInput(matchID, onTap) {
                    detectTapGestures { location ->
                        // **조용해도 되는 길은 판 밖 하나뿐이다.** 나머지 거절은 코어 `place` 가 문구로 말한다.
                        val idx = GamesReversiBoardGeometry(size.width.toDouble()).idx(location.x.toDouble(), location.y.toDouble()) ?: return@detectTapGestures
                        onTap(idx)
                    }
                }
            },
    ) {
        Canvas(Modifier.size(side)) {
            drawReversiBoard(picture, measurer)
            if (warningIntensity > 0) drawGomokuEdgeGlow(warningIntensity)
        }
        // TalkBack 칸 노드 64개 — 칸 이름이 먼저다. 누름은 판이 받는다(이 노드들은 포인터 입력이 없다).
        Column {
            for (row in 0 until 8) {
                Row {
                    for (col in 0 until 8) {
                        val idx = row * 8 + col
                        Box(
                            Modifier.size(cellSide).semantics {
                                contentDescription = GamesReversiBoardCells.label(idx, board, legalTargets, lastStoneIdx, autoStones)
                                this.testTag = ReversiScreenTags.cell(idx)
                                if (onTap != null) {
                                    role = Role.Button
                                    onClick { onTap(idx); true }
                                }
                            },
                        )
                    }
                }
            }
        }
    }
}

/** 내 차례 마지막 3초의 판 테두리 빛 세기 — 잎만 부른다(판정·세기는 코어 `GomokuTurnWarning` 숫자 함수 + `ReversiTurnWarning.watchesMyClock` 짝 한 곳). */
@Composable
fun rememberReversiWarningIntensity(store: ReversiStore): Double {
    val match = store.match
    val watches = match != null &&
        ReversiTurnWarning.watchesMyClock(match.isFinished, match.deadline?.timeIntervalSince1970, match.turn, match.myColor)
    val tick = rememberTicker(running = store.isWindowVisible && watches, periodMillis = 200)
    val remaining = tick.let { if (watches) store.remainingSeconds(store.clock()) else null }
    return if (GomokuTurnWarning.isActive(remaining)) GomokuTurnWarning.intensity(remaining) else 0.0
}

/** 돌 하나(판 그림과 같은 칠). [color] 가 null 이면 반은 흑 · 반은 백(무작위 고르기 · 게임 기호와 같은 뜻). 그림뿐이라 화면 읽기 노드가 없다(뜻은 옆 글자가 말한다). */
@Composable
fun ReversiStoneDot(color: ReversiColor?, size: Dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        val r = this.size.minDimension / 2 * 0.84f
        val c = Offset(this.size.width / 2, this.size.height / 2)
        if (color != null) {
            drawReversiStone(c, r, color, 1f)
        } else {
            drawReversiStone(c, r, ReversiColor.white, 1f)
            val half = Path().apply {
                addArc(androidx.compose.ui.geometry.Rect(c.x - r, c.y - r, c.x + r, c.y + r), 90f, 180f)
                close()
            }
            drawPath(half, ReversiBoardInk.blackStone)
        }
    }
}

/** 기본 판 칸 크기 헬퍼(시험 — 칸 가운데 좌표). */
internal fun reversiCellCenter(side: Dp, idx: Int): Pair<Dp, Dp> {
    val cell = side / 8
    return cell * (idx % 8) + cell / 2 to cell * (idx / 8) + cell / 2
}
