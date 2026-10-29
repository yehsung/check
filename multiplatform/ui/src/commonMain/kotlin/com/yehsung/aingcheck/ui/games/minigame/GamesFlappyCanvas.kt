// 원본: Sources/CheckMobileKit/Games/GamesFlappyCanvas.swift @ 3bd04bd
//
// 플래피 아잉 한 프레임의 그림. **남긴 넷과 기둥만** 그린다: ① 오른쪽을 보는 옆모습 ② 점프 때 발밑 흰 파편 ③ 기둥을 지날 때 "+1"
// ④ 뒤 배경(점수 무대) + 기둥. 맥 파일 머리의 "다시 넣지 마라" 목록(잔상·스쿼시·플래시·링·플레어·배너…)은 여기도 그대로다 — 사용자가 보고 물린 것이다.
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.minigame.FlappyGame
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.MiniGameRect
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min

/** 플래피 이펙트 상수(Swift `FlappyFX` 그대로). */
internal object FlappyFX {
    const val flapSpark = 0.35
    const val scorePopHold = 0.60
    const val tiltMin = -20.0
    const val tiltMax = 25.0
    const val lip = 10.0
    const val scoreY = 26.0
    const val scorePopBack = FlappyGame.pipeWidth * 0.75
    const val flapSparkRadius = 44f
    const val flapSparkDot = 2.0f
    const val flapSparkFrom = 0.28 * PI
    const val flapSparkTo = 1.22 * PI
    val flapSparkColor = Color.White.copy(alpha = 0.82f)
    val scorePopX: Double = FlappyGame.birdX - scorePopBack
}

/** 점수를 위에 띄우는가(진행·게임오버 유예 중). */
internal val FlappyGame.showsTopScore: Boolean
    get() = phase == FlappyGame.Phase.Running || phase is FlappyGame.Phase.Over

/** 아잉 기울기(°) — 속도에 비례, 위로 −20 · 아래로 +25 에서 멈춘다. reduceMotion 이면 0. */
internal fun FlappyGame.spriteAngle(reduceMotion: Boolean): Double {
    if (reduceMotion) return 0.0
    val raw = bird.vy / FlappyGame.maxFallSpeed * FlappyFX.tiltMax
    return min(FlappyFX.tiltMax, max(FlappyFX.tiltMin, raw))
}

@Composable
fun GamesFlappyCanvas(game: FlappyGame, bestScore: Long, reduceMotion: Boolean, art: MiniGameArt, modifier: Modifier = Modifier) {
    val density = LocalDensity.current.density
    BoxWithConstraints(modifier) {
        val size = Size(constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat())
        val t = MiniGameProjection(size, FlappyGame.logicalSize, density)
        val scale = t.scaleDp
        Canvas(Modifier.fillMaxSize()) { drawFlappy(this, game, reduceMotion, density) }
        Box(Modifier.fillMaxSize().clearAndSetSemantics { }) {
            // 아잉 고정(맥과 같다). 게임오버면 시무룩 정면. 그림이 없으면 근무 초록 원(Swift 폴백 그대로).
            val side = (FlappyGame.spriteSize * scale).dp
            val sprite = if (game.isGameOver) art.flappyNegative else art.flappySide
            val spriteModifier = Modifier.centeredAt(t.x(game.bird.x), t.y(game.bird.y)).size(side).rotate(game.spriteAngle(reduceMotion).toFloat())
            if (sprite != null) FlappyAingImage(sprite, side, spriteModifier) else Box(spriteModifier.background(GamesCanvasColors.working, CircleShape))
            if (game.showsTopScore) {
                Text(
                    game.score.toString(),
                    modifier = Modifier.centeredAt(t.x(FlappyGame.width / 2), t.y(FlappyFX.scoreY)),
                    style = TextStyle(
                        fontFamily = canvasFont(),
                        fontSize = canvasSp(26 * scale), fontWeight = FontWeight.ExtraBold, fontFeatureSettings = TABULAR_NUMBERS,
                        color = GamesCanvasColors.primaryText, shadow = canvasTextShadow(0.55f, 4f, 2f),
                    ),
                )
            }
            val at = game.lastScoreAt
            val center = game.lastScorePipeCenter
            if (at != null && center != null && game.elapsed - at < FlappyFX.scorePopHold && game.showsTopScore) {
                GamesScorePop(
                    "+1", key = game.score, tint = game.stage.paint.glow, reduceMotion = reduceMotion, scale = scale,
                    modifier = Modifier.centeredAt(t.x(FlappyFX.scorePopX), t.y(center)),
                )
            }
            if (!reduceMotion && game.flashRemaining > 0) {
                Box(Modifier.fillMaxSize().background(GamesCanvasColors.danger.copy(alpha = (0.25 * game.flashRemaining / FlappyGame.flashDuration).toFloat())))
            }
            when (game.phase) {
                FlappyGame.Phase.Ready ->
                    // 시작 카드는 아래로 — 가운데에 두면 대기 중인 아잉(판 가운데 높이)을 불투명 카드가 가린다.
                    Box(Modifier.fillMaxSize().padding(bottom = (10 * scale).dp), contentAlignment = Alignment.BottomCenter) {
                        GamesOverlayCard(
                            title = MiniGameKind.flappy.title, subtitle = GamesMiniGameText.howToPlay(MiniGameKind.flappy),
                            action = GamesMiniGameText.startAction, tint = game.stage.paint.glow, scale = scale * 0.82f,
                        )
                    }
                FlappyGame.Phase.Result ->
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        GamesOverlayCard(
                            title = "${game.score}점", titleIsScore = true,
                            subtitle = if (game.score > bestScore) "신기록!" else "최고 $bestScore",
                            subtitleIsHighlighted = game.score > bestScore,
                            action = GamesMiniGameText.againAction, showsAing = true, aingArt = art.flappySide,
                            tint = game.stage.paint.glow, scale = scale,
                        )
                    }
                FlappyGame.Phase.Running, is FlappyGame.Phase.Over -> Unit
            }
        }
    }
}

private fun drawFlappy(scope: DrawScope, game: FlappyGame, reduceMotion: Boolean, density: Float) {
    val t = MiniGameProjection(scope.size, FlappyGame.logicalSize, density)
    val full = Rect(Offset.Zero, scope.size)
    val stage = game.stage
    val paint = stage.paint
    MiniGameBackdrop.draw(scope, full, stage, scroll = game.scrolled.toFloat(), terrain = true, reduceMotion = reduceMotion, density = density)
    // 기둥 — 세로 그라디언트는 캔버스 전체 기준 · 입구 립 · 립 경계선 · 1.5pt 외곽선.
    val pipeBrush = Brush.verticalGradient(listOf(paint.structureDeep, paint.structureDeepLit), startY = full.top, endY = full.bottom)
    for (pipe in game.pipes) {
        val halves = listOf(pipe.topRect(game.elapsed) to true, pipe.bottomRect(game.elapsed, FlappyGame.height) to false)
        for ((rect, isTop) in halves) {
            val h = rect.maxY - rect.minY
            if (h <= 0) continue
            val body = t.rect(rect)
            scope.drawRect(pipeBrush, body.topLeft, body.size)
            val lipHeight = min(FlappyFX.lip, h)
            val lipY = if (isTop) rect.maxY - lipHeight else rect.minY
            val lip = t.rect(MiniGameRect(rect.minX, lipY, rect.maxX - rect.minX, lipHeight))
            scope.drawRect(paint.structureEdge.copy(alpha = 0.55f), lip.topLeft, lip.size)
            if (h > FlappyFX.lip) {
                val edgeY = if (isTop) lipY else lipY + lipHeight - 1
                val edge = t.rect(MiniGameRect(rect.minX, edgeY, rect.maxX - rect.minX, 1.0))
                scope.drawRect(paint.structureEdge.copy(alpha = 0.95f), edge.topLeft, edge.size)
            }
            scope.drawRect(paint.structureEdge.copy(alpha = 0.92f), body.topLeft, body.size, style = Stroke(1.5f * density))
        }
    }
    val flapAt = game.lastFlapAt
    if (!reduceMotion && game.phase == FlappyGame.Phase.Running && flapAt != null) {
        val foot = t.point(game.bird.x + FlappyGame.spriteSize * 0.08, game.bird.y + FlappyGame.spriteSize * 0.52)
        MiniGameEffects.sparks(
            scope, foot, (game.elapsed - flapAt) / FlappyFX.flapSpark, 10, FlappyFX.flapSparkRadius * t.scale,
            FlappyFX.flapSparkColor, game.flapCount.toULong(), FlappyFX.flapSparkDot * t.scale, FlappyFX.flapSparkFrom, FlappyFX.flapSparkTo,
        )
    }
}
