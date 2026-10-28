// 원본: Sources/CheckMobileKit/Games/GamesTetrisCanvas.swift @ 3bd04bd
//
// 솔로 테트리스 한 프레임의 그림. 배치·색은 **옮기지 않았다** — core `TetrisLayout`·`TetrisPalette` 한 벌을 맥·폰과 같이 읽는다.
// 판 그리기는 1:1 판과 **같은 painter**(ui/games/tetris `TetrisBoardPainter.drawBoard(duel = false)`)다.
//
// 맥과 다른 점은 딱 셋이다(폰 판 그대로):
//  ① **글꼴에 배율을 곱한다**(판이 커진 만큼 글자도 커져야 같은 그림이다).
//  ② **8pt 캡션 셋을 안 그린다**(레벨 · 줄 · 점수 캡션 — 곱해도 iOS 캡션 하한 10pt 를 못 넘고 키우면 값 상자와 겹친다). 값 자리를 자기설명형으로:
//     "Lv 7" · "12줄" · 밴드 왼쪽은 숫자만. 글꼴 기준값: 라벨 10 · 값 14 · 칩 10(전부 × scale).
//  ③ **키보드가 없다** — 폰 입력(끌기·탭·버튼)은 `GamesPlayController` 가 들고 이 뷰는 그림만 그린다(두 게임 캔버스와 같은 계약).
//
// INV-GamesTetrisCanvas-6f5f324b 이식: 소스 계약 문자열의 뜻(글꼴 배율 곱셈 — "* t.scale"·"* scale" 둘 다 센다)을 Compose 꼴로 옮겼다 — 이 파일의
//   모든 글자 크기는 `canvasSp(기준값 * scale)` 로만 정해지고(시스템 글자 크기에 끌려가지 않는다), 기준값 10 아래(8·9) 글꼴이 없다. 그 두 사실을
//   `MiniGameCanvasSourceContractTest` 가 이 파일 텍스트(주석 걷음)에서 잰다.
// reduceMotion: 판정 팝의 확대·상승과 무대 배경 연출만 끈다. 떨어지는 조각·고스트·무대 전환은 끄지 않는다(게임 자체·모양·배경 교체다).
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.MiniGameRect
import com.yehsung.aingcheck.core.rules.minigame.MiniGameStage
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.rules.tetris.TetrisLayout
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.ui.games.tetris.TetrisBoardPainter
import com.yehsung.aingcheck.ui.games.tetris.TetrisClearVerdict

/** 판정 팝이 화면에 머무는 시간(판 시계). 줄소거 정지(0.500초)보다 길어야 소거가 끝나기 전에 사라지지 않는다(맥 popHold 와 같다). */
const val TETRIS_POP_HOLD_SECONDS: Double = 0.80

/** 논리 사각형 자리에 글자를 앉힌다(폭·높이는 배율을 먹고, 글꼴은 부르는 쪽이 이미 곱해 넘긴다). */
@Composable
internal fun PlaceInLogical(t: MiniGameProjection, rect: MiniGameRect, content: @Composable () -> Unit) {
    val scale = t.scaleDp
    Box(
        Modifier
            .centeredAt(t.x((rect.minX + rect.maxX) / 2), t.y((rect.minY + rect.maxY) / 2))
            .size(((rect.maxX - rect.minX) * scale).dp, ((rect.maxY - rect.minY) * scale).dp),
        contentAlignment = Alignment.CenterStart,
    ) { content() }
}

/** 캔버스 칩(B2B · 콤보 · 들어올 줄) — 10 × scale bold, 틴트 18% 바탕 + 45% 테두리. */
@Composable
internal fun CanvasChip(text: String, tint: Color, scale: Float, borderAlpha: Float = 0.45f) {
    Text(
        text,
        modifier = Modifier
            .background(tint.copy(alpha = 0.18f), CircleShape)
            .border(1.dp, tint.copy(alpha = borderAlpha), CircleShape)
            .padding(horizontal = (5 * scale).dp, vertical = (1 * scale).dp),
        style = TextStyle(fontSize = canvasSp(10 * scale), fontWeight = FontWeight.Bold, fontFeatureSettings = TABULAR_NUMBERS, color = tint),
        maxLines = 1,
    )
}

/** '홀드'·'다음' 라벨(곱하기 전 기준값 10 — iOS 캡션 하한). */
@Composable
internal fun CanvasLabel(text: String, scale: Float) {
    Text(text, style = TextStyle(fontSize = canvasSp(10 * scale), fontWeight = FontWeight.Bold, color = GamesCanvasColors.secondaryText, shadow = canvasTextShadow()))
}

/** 레벨·줄 값 한 줄(자기설명형). 평문 숫자다 — 자리수 구분을 붙이지 않는다(이 창의 표기 규약). */
@Composable
internal fun CanvasStatValue(t: MiniGameProjection, valueY: Double, text: String) {
    PlaceInLogical(t, MiniGameRect(TetrisLayout.textMinX, valueY, TetrisLayout.columnWidth, TetrisLayout.valueHeight)) {
        Text(
            text,
            style = TextStyle(
                fontSize = canvasSp(14 * t.scaleDp), fontWeight = FontWeight.ExtraBold, fontFeatureSettings = TABULAR_NUMBERS,
                color = GamesCanvasColors.primaryText, shadow = canvasTextShadow(),
            ),
            maxLines = 1,
            overflow = TextOverflow.Clip,
        )
    }
}

@Composable
fun GamesTetrisCanvas(game: TetrisGame, bestScore: Long, reduceMotion: Boolean, modifier: Modifier = Modifier) {
    val density = LocalDensity.current.density
    val stage = MiniGameStage.forTetrisAdvance(game.advance)
    BoxWithConstraints(modifier) {
        val size = Size(constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat())
        val t = MiniGameProjection(size, TetrisLayout.logicalSize, density)
        val scale = t.scaleDp
        // 바깥 모서리 자르기는 **화면이 한다**(두 게임 캔버스와 같다).
        Canvas(Modifier.fillMaxSize()) { TetrisBoardPainter.drawBoard(this, game, this.size, reduceMotion, duel = false, density = density) }
        Box(Modifier.fillMaxSize().clearAndSetSemantics { }) {
            // HUD — 맥과 같은 자리(TetrisLayout 논리 좌표)에 앉히되 글꼴에는 배율을 곱한다.
            PlaceInLogical(t, MiniGameRect(TetrisLayout.textMinX, TetrisLayout.labelY, TetrisLayout.columnWidth, TetrisLayout.labelHeight)) { CanvasLabel("홀드", scale) }
            PlaceInLogical(t, MiniGameRect(TetrisLayout.rightColumnX, TetrisLayout.labelY, TetrisLayout.columnWidth, TetrisLayout.labelHeight)) { CanvasLabel("다음", scale) }
            PlaceInLogical(t, MiniGameRect(TetrisLayout.outerMargin, TetrisLayout.stageChipY, TetrisLayout.columnWidth, TetrisLayout.stageChipHeight)) { GamesStageChip(stage, scale = scale) }
            CanvasStatValue(t, TetrisLayout.levelValueY, "Lv " + game.scoreLevel.toString())
            CanvasStatValue(t, TetrisLayout.linesValueY, game.lines.toString() + "줄")
            // 하단 밴드: 왼쪽 점수(**숫자만** — 8pt '점수' 캡션은 하한 아래라 뺐다) · 오른쪽 B2B/콤보 캡슐.
            PlaceInLogical(t, MiniGameRect(TetrisLayout.textMinX, TetrisLayout.bandY, TetrisLayout.textMaxX - TetrisLayout.textMinX, TetrisLayout.bandHeight)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy((5 * scale).dp)) {
                    Text(
                        game.score.toString(),
                        style = TextStyle(fontSize = canvasSp(14 * scale), fontWeight = FontWeight.ExtraBold, fontFeatureSettings = TABULAR_NUMBERS, color = GamesCanvasColors.primaryText, shadow = canvasTextShadow()),
                        maxLines = 1,
                    )
                    Spacer(Modifier.weight(1f))
                    if (game.backToBack >= 1) CanvasChip("B2B ×" + game.backToBack.toString(), GamesCanvasColors.pending, scale)
                    if (game.combo >= 1) CanvasChip("콤보 " + game.combo.toString(), stage.paint.glow, scale)
                }
            }
            // 판정 팝 — 눈이 가 있는 곳(판)에 뜬다(밴드는 한 줄이라 상시 값과 자리를 다툰다).
            val clear = game.lastClear
            if (clear != null && clear.points > 0 && game.elapsed - clear.at < TETRIS_POP_HOLD_SECONDS) {
                GamesScorePop(
                    "+" + clear.points.toString(), key = clear.at, caption = TetrisClearVerdict.text(clear), tint = stage.paint.glow,
                    reduceMotion = reduceMotion, scale = scale,
                    modifier = Modifier.centeredAt(t.x(TetrisLayout.boardX + TetrisLayout.boardWidth / 2), t.y(TetrisLayout.boardTopY + 58)),
                )
            }
            // 시작 · 결과 카드 — **가운데**(아래에 붙이면 하단 밴드를 덮는다). 배율은 판의 0.82 배.
            // 조작 안내는 howToPlay(.tetris) — "탭해서 회전"이 반드시 들어가야 한다(시계 회전은 캔버스 탭이고 화면 어디에도 그 사실을 말하는 자리가
            // 이 카드뿐이다). 정적 `MiniGameKind.controlHint`("클릭 또는 스페이스")는 여기서 절대 쓰지 않는다.
            val cardScale = scale * 0.82f
            when (game.phase) {
                TetrisGame.Phase.Ready -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    GamesOverlayCard(
                        title = MiniGameKind.tetris.title, subtitle = GamesMiniGameText.howToPlay(MiniGameKind.tetris),
                        action = GamesMiniGameText.startAction, icon = MiniGameKind.tetris.icon, tint = stage.paint.glow, scale = cardScale,
                    )
                }
                TetrisGame.Phase.Result -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    GamesOverlayCard(
                        title = game.score.toString() + "점", titleIsScore = true,
                        subtitle = if (game.score > bestScore) "신기록!" else "최고 $bestScore",
                        subtitleIsHighlighted = game.score > bestScore,
                        action = GamesMiniGameText.againAction, icon = MiniGameKind.tetris.icon, tint = stage.paint.glow, scale = cardScale,
                    )
                }
                TetrisGame.Phase.Running, is TetrisGame.Phase.LineClear, is TetrisGame.Phase.Are, is TetrisGame.Phase.Over -> Unit
            }
        }
    }
}
