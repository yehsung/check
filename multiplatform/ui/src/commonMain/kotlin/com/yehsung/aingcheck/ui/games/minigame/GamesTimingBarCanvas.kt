// 원본: Sources/CheckMobileKit/Games/GamesTimingBarCanvas.swift @ 3bd04bd
//
// 타이밍 바 한 프레임의 그림(맥 MiniGameTimingBar 의 TimingBarFrame · TimingBarOverlay 를 옮긴 폰 판을 다시 옮겼다 — 값·순서 동일).
// 규칙은 core `TimingBarGame`, 판은 논리 292×302 이고 [MiniGameProjection] 이 캔버스에 **등비 확대**한다.
// 판정 등급·배점·주기·폭은 순위표가 걸린 난이도라 그림이 한 줄도 건드리지 않는다. 이펙트 시계는 전부 phase 에서 파생한다(맥과 같다).
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.minigame.MiniGameCanvas
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.MiniGameStage
import com.yehsung.aingcheck.core.rules.minigame.TimingBarGame
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** 타이밍 바 배치(논리 좌표 — Swift `TimingBarLayout` 그대로). */
internal object TimingBarLayout {
    const val width = MiniGameCanvas.logicalWidth
    const val height = MiniGameCanvas.logicalHeight
    const val headerY = 22.0
    const val comboY = 56.0
    const val trackLeft = 24.0
    const val trackWidth = 244.0
    const val trackY = 150.0
    const val trackHeight = 18.0
    const val markerWidth = 4.0
    const val markerHeight = 30.0
    const val markerTip = 6.0
    const val segmentsY = 250.0
    const val segmentHeight = 10.0
    const val popY = 106.0

    /** 90점 경계는 배점상 정확히 d < 0.35 다. */
    const val innerTargetRatio = 0.35
    const val perfectLineWidth = 2.0
    const val perfectOverhang = 4.0
    const val outerTargetOpacity = 0.78f
    const val innerTargetOpacity = 1.0f
    const val ringDuration = 0.4
    const val flashDuration = 0.15
    const val shakeDuration = 0.12
    const val stageFlareDuration = 0.6
}

private fun MiniGameProjection.trackX(position: Double): Float = x(TimingBarLayout.trackLeft + position * TimingBarLayout.trackWidth)

/** 결과 표시가 시작된 뒤 흐른 시간(결과 표시 중일 때만). */
internal fun TimingBarGame.sinceTap(): Double? = (phase as? TimingBarGame.Phase.RoundResult)?.let { TimingBarGame.resultHold - it.hold }

/** 지금 결과 표시 중인 라운드의 판정. */
internal fun TimingBarGame.currentVerdict(): TimingBarGame.Verdict? =
    (phase as? TimingBarGame.Phase.RoundResult)?.let { TimingBarGame.verdict(it.score) }

/** 흔들림(pt). 빗나감이 더 세다. reduceMotion 이면 0. */
internal fun TimingBarGame.shakeOffset(reduceMotion: Boolean): Pair<Double, Double> {
    if (reduceMotion) return 0.0 to 0.0
    val elapsed = sinceTap() ?: return 0.0 to 0.0
    val hit = lastHit ?: return 0.0 to 0.0
    if (elapsed >= TimingBarLayout.shakeDuration) return 0.0 to 0.0
    val decay = 1 - elapsed / TimingBarLayout.shakeDuration
    val amplitude = (if (hit) 2.0 else 4.0) * decay
    return amplitude * sin(elapsed * 160) to amplitude * 0.6 * cos(elapsed * 130)
}

/** 타이밍 바 캔버스(배경·트랙·마커·이펙트 + 글자층·카드). */
@Composable
fun GamesTimingBarCanvas(game: TimingBarGame, bestScore: Long, reduceMotion: Boolean, modifier: Modifier = Modifier) {
    val stage = MiniGameStage.forTimingRound(game.round)
    val density = LocalDensity.current.density
    val (shakeX, shakeY) = game.shakeOffset(reduceMotion)
    BoxWithConstraints(modifier.offset(shakeX.dp, shakeY.dp)) {
        Canvas(Modifier.fillMaxSize()) { drawTimingBar(this, game, stage, reduceMotion, density) }
        val size = androidx.compose.ui.geometry.Size(constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat())
        TimingBarOverlay(game, bestScore, stage, reduceMotion, MiniGameProjection(size, MiniGameCanvas.logicalSize, density))
    }
}

private fun drawTimingBar(scope: DrawScope, game: TimingBarGame, stage: MiniGameStage, reduceMotion: Boolean, density: Float) {
    val t = MiniGameProjection(scope.size, MiniGameCanvas.logicalSize, density)
    val full = Rect(Offset.Zero, scope.size)
    val paint = stage.paint
    MiniGameBackdrop.draw(scope, full.insetBy(-8 * density, -8 * density), stage, scroll = 0f, terrain = false, reduceMotion = reduceMotion, density = density)
    // 무대 전환 플레어: 홀수 라운드(3·5·7·9)의 첫 0.6초.
    (game.phase as? TimingBarGame.Phase.Running)?.let { p ->
        if (p.round >= 3 && p.round % 2 == 1 && p.t < TimingBarLayout.stageFlareDuration) {
            MiniGameEffects.flare(scope, full, p.t / TimingBarLayout.stageFlareDuration, paint.glow)
        }
    }
    // 트랙 뒤 후광 · 트랙.
    MiniGameEffects.glow(scope, t.rect(TimingBarLayout.trackLeft - 46, TimingBarLayout.trackY - 52, TimingBarLayout.trackWidth + 92, 104.0), paint.glow, 0.22f)
    drawTrack(scope, t, stage, density)
    if (game.isPlaying) {
        drawTarget(scope, t, game, stage)
        drawMarker(scope, t, game, reduceMotion)
        drawHitEffects(scope, t, full, game, stage)
        drawSegments(scope, t, game, stage, reduceMotion, density)
    }
    val elapsed = game.sinceTap()
    if (elapsed != null && game.currentVerdict() == TimingBarGame.Verdict.miss && elapsed < TimingBarLayout.flashDuration) {
        val strength = (1 - elapsed / TimingBarLayout.flashDuration).toFloat()
        scope.drawRect(GamesCanvasColors.danger.copy(alpha = 0.24f * strength), full.topLeft, full.size)
    }
}

private fun drawTrack(scope: DrawScope, t: MiniGameProjection, stage: MiniGameStage, density: Float) {
    val paint = stage.paint
    val body = t.rect(TimingBarLayout.trackLeft, TimingBarLayout.trackY - TimingBarLayout.trackHeight / 2, TimingBarLayout.trackWidth, TimingBarLayout.trackHeight)
    val radius = CornerRadius(body.height / 2)
    scope.drawRoundRect(
        Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.86f), Color.Black.copy(alpha = 0.66f)), startY = body.top, endY = body.bottom),
        body.topLeft, body.size, radius,
    )
    scope.drawRoundRect(paint.structureEdge.copy(alpha = 0.35f), body.topLeft, body.size, radius, style = Stroke(density))
    for (step in 0 until 3) {
        val inset = 6 + step * 5.0
        val tickHeight = 8 - step * 2.0
        val opacity = (0.5 - step * 0.14).toFloat()
        for (side in listOf(-1, 1)) {
            val center = if (side < 0) TimingBarLayout.trackLeft - inset else TimingBarLayout.trackLeft + TimingBarLayout.trackWidth + inset
            val tick = t.rect(center - 0.75, TimingBarLayout.trackY - tickHeight / 2, 1.5, tickHeight)
            scope.drawRect(paint.structureEdge.copy(alpha = opacity), tick.topLeft, tick.size)
        }
    }
}

private fun drawTarget(scope: DrawScope, t: MiniGameProjection, game: TimingBarGame, stage: MiniGameStage) {
    val paint = stage.paint
    val (center, width) = game.target
    val height = TimingBarLayout.trackHeight
    val top = TimingBarLayout.trackY - height / 2
    val outerWidth = width * TimingBarLayout.trackWidth
    val outerLeft = TimingBarLayout.trackLeft + (center - width / 2) * TimingBarLayout.trackWidth
    val outer = t.rect(outerLeft, top, outerWidth, height)
    scope.drawRoundRect(paint.structure.copy(alpha = TimingBarLayout.outerTargetOpacity), outer.topLeft, outer.size, CornerRadius(3 * t.scale))
    val innerWidth = outerWidth * TimingBarLayout.innerTargetRatio
    val inner = t.rect(outerLeft + (outerWidth - innerWidth) / 2, top + 2, innerWidth, height - 4)
    scope.drawRoundRect(paint.structureEdge.copy(alpha = TimingBarLayout.innerTargetOpacity), inner.topLeft, inner.size, CornerRadius(2 * t.scale))
    scope.drawRoundRect(Color.Black.copy(alpha = 0.50f), inner.topLeft, inner.size, CornerRadius(2 * t.scale), style = Stroke(1f))
    val lineX = TimingBarLayout.trackLeft + center * TimingBarLayout.trackWidth
    val slotWidth = TimingBarLayout.perfectLineWidth + 2
    val slot = t.rect(lineX - slotWidth / 2, top - TimingBarLayout.perfectOverhang, slotWidth, height + TimingBarLayout.perfectOverhang * 2)
    scope.drawRect(Color.Black.copy(alpha = 0.55f), slot.topLeft, slot.size)
    val line = t.rect(lineX - TimingBarLayout.perfectLineWidth / 2, top - TimingBarLayout.perfectOverhang, TimingBarLayout.perfectLineWidth, height + TimingBarLayout.perfectOverhang * 2)
    scope.drawRect(paint.glow, line.topLeft, line.size)
}

private fun bladeRect(t: MiniGameProjection, position: Double): Rect {
    val left = t.trackX(position) - (TimingBarLayout.markerWidth / 2 * t.scale).toFloat()
    val top = t.y(TimingBarLayout.trackY - TimingBarLayout.markerHeight / 2)
    return Rect(left, top, left + (TimingBarLayout.markerWidth * t.scale).toFloat(), top + (TimingBarLayout.markerHeight * t.scale).toFloat())
}

private fun drawMarker(scope: DrawScope, t: MiniGameProjection, game: TimingBarGame, reduceMotion: Boolean) {
    val color = game.currentVerdict()?.tint ?: GamesCanvasColors.primaryText
    val running = game.phase as? TimingBarGame.Phase.Running
    if (!reduceMotion && running != null) {
        val period = TimingBarGame.period(running.round)
        for ((age, opacity) in listOf(2.0 / 60.0 to 0.28f, 4.0 / 60.0 to 0.16f, 6.0 / 60.0 to 0.08f)) {
            val past = TimingBarGame.markerPosition(running.t - age, period)
            val ghost = bladeRect(t, past).insetBy(0f, 4 * t.scale)
            scope.drawRoundRect(color.copy(alpha = color.alpha * opacity), ghost.topLeft, ghost.size, CornerRadius(1.5f * t.scale))
        }
    }
    val markerX = t.trackX(game.markerPosition)
    val centerY = t.y(TimingBarLayout.trackY)
    val halo = 26 * t.scale
    MiniGameEffects.glow(scope, Rect(markerX - halo, centerY - halo, markerX + halo, centerY + halo), color, 0.38f)
    val blade = bladeRect(t, game.markerPosition)
    scope.drawRoundRect(color, blade.topLeft, blade.size, CornerRadius(1.5f * t.scale))
    val half = 5 * t.scale
    val tip = (TimingBarLayout.markerTip * t.scale).toFloat()
    val top = Path().apply {
        moveTo(markerX, blade.top + 1)
        lineTo(markerX - half, blade.top - tip)
        lineTo(markerX + half, blade.top - tip)
        close()
    }
    val bottom = Path().apply {
        moveTo(markerX, blade.bottom - 1)
        lineTo(markerX - half, blade.bottom + tip)
        lineTo(markerX + half, blade.bottom + tip)
        close()
    }
    scope.drawPath(top, color)
    scope.drawPath(bottom, color)
}

private fun drawHitEffects(scope: DrawScope, t: MiniGameProjection, full: Rect, game: TimingBarGame, stage: MiniGameStage) {
    val elapsed = game.sinceTap() ?: return
    val verdict = game.currentVerdict() ?: return
    if (verdict == TimingBarGame.Verdict.miss) return
    val progress = elapsed / TimingBarLayout.ringDuration
    if (progress >= 1) return
    val center = Offset(t.trackX(game.markerPosition), t.y(TimingBarLayout.trackY))
    MiniGameEffects.ring(scope, center, progress, 42 * t.scale, verdict.tint, 2f)
    MiniGameEffects.ring(scope, center, min(1.0, progress * 1.5), 24 * t.scale, verdict.tint.copy(alpha = 0.85f), 1.5f)
    MiniGameEffects.sparks(scope, center, progress, 8, 34 * t.scale, verdict.tint, max(1, game.round).toULong(), 2.2f * t.scale)
    if (verdict == TimingBarGame.Verdict.perfect) {
        MiniGameEffects.flare(scope, full, elapsed / TimingBarLayout.stageFlareDuration, stage.paint.glow)
    }
}

private fun drawSegments(scope: DrawScope, t: MiniGameProjection, game: TimingBarGame, stage: MiniGameStage, reduceMotion: Boolean, density: Float) {
    val paint = stage.paint
    val count = TimingBarGame.roundCount
    val gap = 3.0
    val cellWidth = (TimingBarLayout.trackWidth - gap * (count - 1)) / count
    val running = game.phase as? TimingBarGame.Phase.Running
    val currentIndex = running?.let { it.round - 1 }
    val pulse = if (reduceMotion || running == null) 1.0 else 0.5 + 0.5 * sin(running.t * 5.5)
    val scores = game.roundScores
    for (index in 0 until count) {
        val left = TimingBarLayout.trackLeft + index * (cellWidth + gap)
        val cell = t.rect(left, TimingBarLayout.segmentsY - TimingBarLayout.segmentHeight / 2, cellWidth, TimingBarLayout.segmentHeight)
        val radius = CornerRadius(3 * t.scale)
        when {
            index < scores.size -> {
                val verdict = TimingBarGame.verdict(scores[index])
                scope.drawRoundRect(verdict.tint.copy(alpha = 0.85f), cell.topLeft, cell.size, radius)
                scope.drawRoundRect(verdict.tint, cell.topLeft, cell.size, radius, style = Stroke(density))
                drawGlyph(scope, verdict.glyph, cell)
            }
            index == currentIndex -> {
                scope.drawRoundRect(paint.glow.copy(alpha = (0.14 + 0.16 * pulse).toFloat()), cell.topLeft, cell.size, radius)
                scope.drawRoundRect(paint.glow.copy(alpha = (0.55 + 0.45 * pulse).toFloat()), cell.topLeft, cell.size, radius, style = Stroke(1.6f * density))
            }
            else -> scope.drawRoundRect(paint.structureEdge.copy(alpha = 0.28f), cell.topLeft, cell.size, radius, style = Stroke(density))
        }
    }
}

/** 등급 글리프(라운드 스트립 칸 안) — 색을 못 보는 눈의 두 번째 채널(꽉 참 → 테두리만 → ×). */
private fun drawGlyph(scope: DrawScope, glyph: TimingBarGame.SegmentGlyph, cell: Rect) {
    val ink = Color.Black.copy(alpha = 0.72f)
    val r = min(cell.height, cell.width) * 0.28f
    val c = cell.center
    val box = Rect(c.x - r, c.y - r, c.x + r, c.y + r)
    when (glyph) {
        TimingBarGame.SegmentGlyph.star, TimingBarGame.SegmentGlyph.disc -> {
            scope.drawOval(ink, box.topLeft, box.size)
            if (glyph == TimingBarGame.SegmentGlyph.star) {
                val inner = box.insetBy(r * 0.5f, r * 0.5f)
                scope.drawOval(Color.White.copy(alpha = 0.85f), inner.topLeft, inner.size)
            }
        }
        TimingBarGame.SegmentGlyph.diamond -> scope.drawPath(
            Path().apply {
                moveTo(c.x, c.y - r)
                lineTo(c.x + r, c.y)
                lineTo(c.x, c.y + r)
                lineTo(c.x - r, c.y)
                close()
            },
            ink,
        )
        TimingBarGame.SegmentGlyph.ring -> scope.drawOval(ink, box.topLeft, box.size, style = Stroke(max(1f, r * 0.55f)))
        TimingBarGame.SegmentGlyph.cross -> {
            val w = max(1f, r * 0.55f)
            scope.drawLine(ink, Offset(c.x - r, c.y - r), Offset(c.x + r, c.y + r), w)
            scope.drawLine(ink, Offset(c.x + r, c.y - r), Offset(c.x - r, c.y + r), w)
        }
    }
}

/** 글자층 — 머리 줄(라운드 · 무대 칩 · 총점) · 콤보 · 판정 팝 · 시작/결과 카드. 손을 받지 않는다(캔버스가 받는다). */
@Composable
private fun TimingBarOverlay(game: TimingBarGame, bestScore: Long, stage: MiniGameStage, reduceMotion: Boolean, t: MiniGameProjection) {
    val scale = t.scaleDp
    val paint = stage.paint
    val shadow = canvasTextShadow()
    Box(Modifier.fillMaxSize().clearAndSetSemantics { }) {
        Row(
            modifier = Modifier.width(((TimingBarLayout.width - 28) * scale).dp).centeredAt(t.x(TimingBarLayout.width / 2), t.y(TimingBarLayout.headerY)),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy((6 * scale).dp),
        ) {
            Text(
                "라운드 ${max(1, game.round)}/${TimingBarGame.roundCount}",
                style = TextStyle(fontFamily = canvasFont(), fontSize = canvasSp(11 * scale), fontWeight = FontWeight.SemiBold, color = GamesCanvasColors.primaryText.copy(alpha = 0.86f), shadow = shadow),
            )
            GamesStageChip(stage, scale = scale)
            Spacer(Modifier.weight(1f))
            Text(
                game.total.toString(),
                style = TextStyle(fontFamily = canvasFont(), fontSize = canvasSp(25 * scale), fontWeight = FontWeight.ExtraBold, fontFeatureSettings = TABULAR_NUMBERS, color = GamesCanvasColors.primaryText, shadow = shadow),
            )
        }
        if (game.isPlaying && game.combo >= 2) {
            Row(
                modifier = Modifier
                    .centeredAt(t.x(TimingBarLayout.width / 2), t.y(TimingBarLayout.comboY))
                    .scale(if (game.combo >= 3) 1.14f else 1f)
                    .background(paint.glow.copy(alpha = 0.18f), CircleShape)
                    .border(1.dp, paint.glow.copy(alpha = 0.50f), CircleShape)
                    .padding(horizontal = (9 * scale).dp, vertical = (3 * scale).dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy((3 * scale).dp),
            ) {
                AingIcon(AppIcon.LocalFireDepartmentFill, contentDescription = null, size = (10 * scale).dp, tint = paint.glow)
                Text("콤보 x${game.combo}", style = TextStyle(fontFamily = canvasFont(), fontSize = canvasSp(11 * scale), fontWeight = FontWeight.ExtraBold, color = paint.glow))
            }
        }
        val result = game.phase as? TimingBarGame.Phase.RoundResult
        if (result != null) {
            val verdict = TimingBarGame.verdict(result.score)
            val clamped = min(max(game.markerPosition, 0.10), 0.90)
            GamesScorePop(
                "+${result.score}", key = result.round, caption = verdict.label, tint = verdict.tint, reduceMotion = reduceMotion, scale = scale,
                modifier = Modifier.centeredAt(t.trackX(clamped), t.y(TimingBarLayout.popY)),
            )
        }
        // 카드는 판 배율보다 한 단계 작게(0.82) — 판 배율 그대로 키우면 아래 카드 윗변이 트랙(y 150)을 덮는다.
        val cardScale = scale * 0.82f
        val card: (@Composable () -> Unit)? = when (val p = game.phase) {
            TimingBarGame.Phase.Ready -> {
                {
                    GamesOverlayCard(
                        title = MiniGameKind.timingBar.title, subtitle = GamesMiniGameText.howToPlay(MiniGameKind.timingBar),
                        action = GamesMiniGameText.startAction, icon = MiniGameKind.timingBar.icon, tint = paint.glow, scale = cardScale,
                    )
                }
            }
            is TimingBarGame.Phase.Finished -> {
                {
                    GamesOverlayCard(
                        title = "총점 ${p.total}", titleIsScore = true,
                        subtitle = if (p.total > bestScore) "신기록!" else "최고 $bestScore",
                        subtitleIsHighlighted = p.total > bestScore,
                        action = GamesMiniGameText.againAction, icon = MiniGameKind.timingBar.icon, tint = paint.glow, scale = cardScale,
                    )
                }
            }
            is TimingBarGame.Phase.Running, is TimingBarGame.Phase.RoundResult -> null
        }
        if (card != null) {
            Box(Modifier.fillMaxSize().padding(bottom = (10 * cardScale).dp), contentAlignment = Alignment.BottomCenter) { card() }
        }
    }
}
