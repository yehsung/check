// 원본: Sources/CheckMobileKit/Games/GamesTetrisDuelCanvas.swift @ 3bd04bd (내 판 한 장 + 글자 겹 · 상대 미니 판)
//
// 폰 1:1 테트리스 **판 그림** — 그림만 그린다. 받는 것은 값뿐이다(game · reduceMotion · cells). 입력·시계·배치 복제본은 여기 없다 — 프레임 루프는
// 화면(GamesTetrisDuelMatchView)이 돌고, 판은 코어 스토어가 단조 시계로 민다(설계 D10).
// 맥 대결 창과 다른 점(폰 판 그대로): ① 글꼴에 배율을 곱한다 ② 8pt 캡션을 안 그린다 — 값 자리를 자기설명형("Lv 7" · "12줄")으로 둔다. 하단 밴드의
// '보낸 공격'·'들어올 줄'은 10pt 라벨이라 하한을 지킨다(두 숫자가 같은 자리에 서므로 숫자만으로는 못 읽는다).
// 대결이 더하는 것 셋(방해 줄 회색 · 미터 · 미니 판)은 **전부 painter 안**이다 — 직접 칠하지 마라(같은 판이 화면마다 다르게 보인다).
// 판정 팝은 대결에 없다(점수가 아니라 공격이 승부 — 밴드의 '보낸 공격'이 상시로 그 일을 한다).
package com.yehsung.aingcheck.ui.games.tetris

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.minigame.MiniGameRect
import com.yehsung.aingcheck.core.rules.tetris.TetrisDuelCell
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.rules.tetris.TetrisLayout
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisDuelChrome
import com.yehsung.aingcheck.core.stores.tetris.TetrisPhoneText
import com.yehsung.aingcheck.ui.games.minigame.CanvasChip
import com.yehsung.aingcheck.ui.games.minigame.CanvasLabel
import com.yehsung.aingcheck.ui.games.minigame.CanvasStatValue
import com.yehsung.aingcheck.ui.games.minigame.GamesCanvasColors
import com.yehsung.aingcheck.ui.games.minigame.MiniGameProjection
import com.yehsung.aingcheck.ui.games.minigame.PlaceInLogical
import com.yehsung.aingcheck.ui.games.minigame.TABULAR_NUMBERS
import com.yehsung.aingcheck.ui.games.minigame.canvasSp
import com.yehsung.aingcheck.ui.games.minigame.canvasTextShadow
import com.yehsung.aingcheck.ui.games.minigame.canvasFont

/** 내 판 한 장(painter `duel = true`) + 글자 겹. 솔로 캔버스와 같은 서명 꼴 — **값만** 받는다. [frame] 은 프레임 루프가 올리는 번호(다시 그릴 신호). */
@Composable
fun GamesTetrisDuelCanvas(game: TetrisGame, reduceMotion: Boolean, modifier: Modifier = Modifier, frame: Int = 0) {
    val density = LocalDensity.current.density
    BoxWithConstraints(modifier) {
        val size = Size(constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat())
        val t = MiniGameProjection(size, TetrisLayout.logicalSize, density)
        val scale = t.scaleDp
        Canvas(Modifier.fillMaxSize()) {
            @Suppress("UNUSED_EXPRESSION") frame
            TetrisBoardPainter.drawBoard(this, game, this.size, reduceMotion, duel = true, density = density)
        }
        Box(Modifier.fillMaxSize().clearAndSetSemantics { }) {
            PlaceInLogical(t, MiniGameRect(TetrisLayout.textMinX, TetrisLayout.labelY, TetrisLayout.columnWidth, TetrisLayout.labelHeight)) { CanvasLabel(TetrisPhoneText.holdLabel, scale) }
            PlaceInLogical(t, MiniGameRect(TetrisLayout.rightColumnX, TetrisLayout.labelY, TetrisLayout.columnWidth, TetrisLayout.labelHeight)) { CanvasLabel(TetrisPhoneText.nextLabel, scale) }
            // 레벨은 **난이도 레벨**이다(가속 바닥이 섞인 값 — 맥 대결 창과 같다). 점수 레벨은 대결에 뜻이 없다.
            CanvasStatValue(t, TetrisLayout.levelValueY, TetrisPhoneText.levelValue(game.difficultyLevel))
            CanvasStatValue(t, TetrisLayout.linesValueY, TetrisPhoneText.linesValue(game.lines))
            // 하단 밴드: 왼쪽 **보낸 공격**(누계) · 오른쪽 **들어올 줄**(미터와 같은 빨강 — 우물 왼쪽 막대가 무엇인지 글자로 한 번 말한다).
            PlaceInLogical(t, MiniGameRect(TetrisLayout.textMinX, TetrisLayout.bandY, TetrisLayout.textMaxX - TetrisLayout.textMinX, TetrisLayout.bandHeight)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy((4 * scale).dp)) {
                    Text(TetrisPhoneText.attackTitle, style = TextStyle(fontFamily = canvasFont(), fontSize = canvasSp(10 * scale), fontWeight = FontWeight.Bold, color = GamesCanvasColors.secondaryText, shadow = canvasTextShadow()))
                    Text(
                        game.attackSentTotal.toString(),
                        style = TextStyle(fontFamily = canvasFont(), fontSize = canvasSp(14 * scale), fontWeight = FontWeight.ExtraBold, fontFeatureSettings = TABULAR_NUMBERS, color = GamesCanvasColors.working, shadow = canvasTextShadow()),
                    )
                    Spacer(Modifier.weight(1f))
                    if (game.pendingGarbageLines > 0) CanvasChip(TetrisPhoneText.incomingLines(game.pendingGarbageLines), TetrisDuelPalette.meterColor, scale, borderAlpha = 0.5f)
                }
            }
        }
    }
}

/**
 * 상대 판을 작게. **스냅숏이 올 때만 다시 그린다** — 프레임 루프 밖에 서고 받는 값([cells])은 보고 응답에서만 바뀐다.
 * 칸 변은 순수 표가 쥔다(GamesTetrisDuelChrome.miniBoardCell — 5) — 그 수가 판 폭을 깎고 판 폭이 곧 제스처 한 칸 문턱이라 여기 다시 적지 않는다.
 */
@Composable
fun GamesTetrisDuelMiniBoard(cells: List<List<TetrisDuelCell>>, modifier: Modifier = Modifier, cell: Double = GamesTetrisDuelChrome.miniBoardCell) {
    val density = LocalDensity.current.density
    val (w, h) = TetrisMiniBoardLayout.boardSize(cell)
    Canvas(modifier.size(w.dp, h.dp).semantics { contentDescription = TetrisPhoneText.opponentBoardLabel }) {
        TetrisBoardPainter.drawMiniBoard(this, cells, this.size, (cell * density).toFloat(), density)
    }
}
