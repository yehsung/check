// 원본: Sources/CheckMobileKit/Games/GamesAlkkagiBoard.swift @ 928d5562(폰 1.0.18 — 판 그림 · 판 뷰 · 관전 판) — Android 판 8
//
// 그림은 맥 · 아이폰 `AlkkagiDrawing` 과 같은 식이다 — 나무 판 15줄 · 화점 다섯 · 돌(오목과 같은 돌) · 끌기 띠 · 날아갈 방향 점선 화살
// (길이 = 힘, 흰 → 주황 → 빨강) · 부딪힘 고리 · 떨어지는 돌. 좌표는 판 600 칸이고 흑이 아래다(화면을 뒤집지 않는다).
package com.yehsung.aingcheck.ui.games.alkkagi

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.alkkagi.AlkkagiGame
import com.yehsung.aingcheck.core.rules.alkkagi.AlkkagiVector
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiOnlineStore
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiPhoneFall
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiPhoneHaptic
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiPhoneHit
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiPhoneLaunch
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiWatchState
import com.yehsung.aingcheck.core.stores.alkkagi.GamesAlkkagiBoardModel
import com.yehsung.aingcheck.core.stores.alkkagi.rules
import com.yehsung.aingcheck.core.wire.games.AlkkagiMatchPhase
import com.yehsung.aingcheck.ui.games.gomoku.GomokuBoardInk
import com.yehsung.aingcheck.ui.games.gomoku.drawStone
import com.yehsung.aingcheck.ui.games.minigame.MiniGameFrameLoop
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

object GamesAlkkagiDrawing {
    fun board(scope: DrawScope) = with(scope) {
        val side = size.width
        val inset = side * 0.06f
        val lines = 15
        val cell = (side - inset * 2) / (lines - 1)
        drawRoundRect(
            Brush.linearGradient(listOf(GomokuBoardInk.woodLight, GomokuBoardInk.woodDark), Offset.Zero, Offset(side, side)),
            cornerRadius = CornerRadius(side * 0.025f),
        )
        val far = inset + (lines - 1) * cell
        val thin = max(0.6f, side / 640)
        for (i in 0 until lines) {
            val o = inset + i * cell
            drawLine(GomokuBoardInk.line.copy(alpha = 0.85f), Offset(o, inset), Offset(o, far), thin)
            drawLine(GomokuBoardInk.line.copy(alpha = 0.85f), Offset(inset, o), Offset(far, o), thin)
        }
        drawRect(GomokuBoardInk.line, Offset(inset, inset), Size(far - inset, far - inset), style = Stroke(max(1f, side / 380)))
        for ((x, y) in listOf(3 to 3, 11 to 3, 7 to 7, 3 to 11, 11 to 11)) {
            drawCircle(GomokuBoardInk.line, max(1.5f, cell * 0.1f), Offset(inset + x * cell, inset + y * cell))
        }
    }

    fun disc(scope: DrawScope, center: Offset, radius: Float, player: AlkkagiGame.Player, opacity: Float = 1f) =
        scope.drawStone(center, radius, if (player == AlkkagiGame.Player.black) GomokuColor.black else GomokuColor.white, opacity)

    fun stone(
        scope: DrawScope, stone: AlkkagiGame.Stone, scale: Float, selected: Boolean, pull: AlkkagiVector,
        launch: AlkkagiPhoneLaunch?, hits: List<AlkkagiPhoneHit>, trails: Boolean,
    ) = with(scope) {
        val point = Offset((stone.position.x * scale).toFloat(), (stone.position.y * scale).toFloat())
        val radius = (AlkkagiGame.stoneRadius * scale).toFloat()
        if (trails && stone.velocity.length > 130) {
            for (i in 3 downTo 1) {
                val lag = i * 0.009
                val p = Offset((point.x - stone.velocity.x * scale * lag).toFloat(), (point.y - stone.velocity.y * scale * lag).toFloat())
                val ink = if (stone.owner == AlkkagiGame.Player.black) Color(0.15f, 0.15f, 0.15f) else Color(0.95f, 0.95f, 0.95f)
                drawCircle(ink.copy(alpha = (0.035 * (4 - i)).toFloat()), radius, p)
            }
        }
        var squash = if (selected) min(1.0, pull.length / AlkkagiGame.maxPull) * 0.09 else 0.0
        var angle = atan2(pull.y, pull.x)
        if (launch != null && launch.stoneID == stone.id) {
            squash += sin(launch.age * 65) * exp(-launch.age * 22) * launch.power * 0.12
            angle = atan2(launch.direction.y, launch.direction.x)
        }
        hits.lastOrNull { !it.ringOut && it.age < 0.1 && (stone.position - it.position).length < 70 }?.let { hit ->
            squash += hit.strength * exp(-hit.age * 28) * 0.16
            angle = atan2(stone.position.y - hit.position.y, stone.position.x - hit.position.x)
        }
        if (trails) {
            val s = min(0.22, max(-0.12, squash)).toFloat()
            withTransform({
                rotateRad(angle.toFloat(), point)
                scale(1 - s, 1 / (1 - s), point)
            }) { disc(this, point, radius, stone.owner) }
        } else {
            disc(this, point, radius, stone.owner)
        }
        if (selected) drawCircle(Color.White.copy(alpha = 0.85f), radius + 5, point, style = Stroke(1.5f))
    }

    fun aim(scope: DrawScope, stone: AlkkagiGame.Stone, pull: AlkkagiVector, scale: Float) = with(scope) {
        if (pull.length <= 2) return@with
        val center = Offset((stone.position.x * scale).toFloat(), (stone.position.y * scale).toFloat())
        val grip = Offset((center.x + pull.x * scale).toFloat(), (center.y + pull.y * scale).toFloat())
        val direction = pull * (-1 / pull.length)
        val power = min(1.0, pull.length / AlkkagiGame.maxPull).toFloat()
        val spread = (AlkkagiGame.stoneRadius * scale * 0.8).toFloat()
        val band = Path().apply {
            moveTo((center.x - direction.y * spread).toFloat(), (center.y + direction.x * spread).toFloat())
            lineTo(grip.x, grip.y)
            lineTo((center.x + direction.y * spread).toFloat(), (center.y - direction.x * spread).toFloat())
        }
        val dark = Color(0.19f, 0.17f, 0.14f)
        drawPath(band, dark.copy(alpha = 0.15f), style = Stroke(6f, cap = StrokeCap.Round, join = StrokeJoin.Round))
        drawPath(band, Color.White.copy(alpha = 0.65f + power * 0.35f), style = Stroke(1.5f + power, cap = StrokeCap.Round, join = StrokeJoin.Round))
        drawCircle(Color.White, 5 + power * 2, grip, style = Stroke(1.5f))
        // 날아갈 방향 — 돌 앞으로 점선 화살. 길이 = 힘(어디서 멈출지는 보여 주지 않는다), 색 = 흰 → 주황 → 빨강.
        val radius = (AlkkagiGame.stoneRadius * scale).toFloat()
        val length = ((36 + 150 * power) * scale)
        val from = Offset((center.x + direction.x * (radius + 4)).toFloat(), (center.y + direction.y * (radius + 4)).toFloat())
        val to = Offset((from.x + direction.x * length).toFloat(), (from.y + direction.y * length).toFloat())
        val tint = if (power < 0.6f) Color.White else if (power < 0.9f) Color(1f, 0.72f, 0.3f) else Color(1f, 0.38f, 0.3f)
        drawLine(tint.copy(alpha = 0.85f), from, to, 2 + power * 1.5f, cap = StrokeCap.Round, pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f)))
        val head = 7 + power * 4
        val arrow = Path().apply {
            moveTo((to.x - direction.x * head - direction.y * head * 0.6).toFloat(), (to.y - direction.y * head + direction.x * head * 0.6).toFloat())
            lineTo(to.x, to.y)
            lineTo((to.x - direction.x * head + direction.y * head * 0.6).toFloat(), (to.y - direction.y * head - direction.x * head * 0.6).toFloat())
        }
        drawPath(arrow, tint.copy(alpha = 0.9f), style = Stroke(2 + power, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }

    fun effects(scope: DrawScope, hits: List<AlkkagiPhoneHit>, scale: Float, reduced: Boolean) = with(scope) {
        for (hit in hits) {
            val t = (hit.age / 0.32).toFloat()
            val radius = ((8 + t * (18 + hit.strength * 24)) * scale).toFloat()
            val p = Offset((hit.position.x * scale).toFloat(), (hit.position.y * scale).toFloat())
            drawCircle(Color.White.copy(alpha = ((1 - t) * 0.8f).coerceIn(0f, 1f)), radius, p, style = Stroke((1 - t) * 2 + 0.5f))
            if (!reduced && !hit.ringOut && t < 0.35f) {
                val flash = ((6 + hit.strength * 14) * scale * (1 + t)).toFloat()
                drawCircle(Color.White.copy(alpha = ((1 - t / 0.35f) * (0.25f + 0.5f * hit.strength.toFloat())).coerceIn(0f, 1f)), flash, p)
            }
            if (!reduced) {
                val sparks = 5 + (hit.strength * 6).toInt()
                for (i in 0 until sparks) {
                    val a = i.toDouble() / sparks * Math.PI * 2
                    val d = radius * 1.3f
                    drawCircle(Color.White.copy(alpha = ((1 - t) * 0.7f).coerceIn(0f, 1f)), 1.5f, Offset(p.x + (cos(a) * d).toFloat(), p.y + (sin(a) * d).toFloat()))
                }
            }
        }
    }

    /** 판 밖으로 나간 돌이 떨어진다(판 여백 안 — 판 칸 밖까지 그린다). */
    fun falling(scope: DrawScope, falls: List<AlkkagiPhoneFall>, scale: Float, origin: Offset, reduced: Boolean) = with(scope) {
        for (fall in falls) {
            val t = min(1.0, fall.age / 0.9).toFloat()
            val outward = if (fall.outward.length > 0) fall.outward * (1 / fall.outward.length) else AlkkagiVector(0.0, 1.0)
            val distance = (if (reduced) 24 * t else 10 + 40 * t) * scale / 0.6f
            val p = Offset(
                (origin.x + fall.position.x * scale + outward.x * distance).toFloat(),
                (origin.y + fall.position.y * scale + outward.y * distance + t * t * 60).toFloat(),
            )
            val radius = (AlkkagiGame.stoneRadius * scale * (1 - t * 0.25)).toFloat()
            val opacity = if (reduced) 1 - t else 1 - t * 0.6f
            if (!reduced) {
                withTransform({
                    rotateRad(t * 0.7f * (if (outward.x < 0) -1 else 1), p)
                    scale(1f, 1 - t * 0.25f, p)
                }) { disc(this, p, radius, fall.owner, opacity) }
            } else {
                disc(this, p, radius, fall.owner, opacity)
            }
        }
    }

    /** 관전 판에서 그릴 돌(순수). 굴림 중이면 shot 을 처음부터 지금까지 되살린 돌. */
    fun watchStones(watch: AlkkagiWatchState, serverNowMs: Double): List<AlkkagiGame.Stone> {
        val fallback = watch.stones.map { it.rules() }
        if (watch.phase != AlkkagiMatchPhase.rolling) return fallback
        val shot = watch.shot ?: return fallback
        if (!shot.startedAtMs.isFinite()) return fallback
        val shooter = shot.initialStones.firstOrNull { it.id == shot.stoneID }?.owner?.rules() ?: return fallback
        val game = AlkkagiGame.restore(shot.initialStones.map { it.rules() }, shooter, AlkkagiGame.Phase.aiming, shotCount = max(0L, watch.shotCount - 1).toInt()) ?: return fallback
        if (!game.shoot(shot.stoneID.toInt(), AlkkagiVector(shot.pull.x, shot.pull.y))) return fallback
        var left = min(shot.duration, max(0.0, (serverNowMs - shot.startedAtMs) / 1000))
        while (left > 1e-9 && game.phase == AlkkagiGame.Phase.rolling) {
            val slice = min(0.25, left)
            game.advance(slice)
            left -= slice
        }
        return game.stones
    }
}

/** 판 뷰 — 판 걸음(프레임 루프) · 끌기 손짓 · 흔들림. 판 한 변은 주어진 폭을 꽉 채운다(정사각형). */
@Composable
fun GamesAlkkagiBoardView(
    model: GamesAlkkagiBoardModel,
    placingPlayer: AlkkagiGame.Player?,
    refreshHz: Int,
    reduceMotion: Boolean,
    modifier: Modifier = Modifier,
) {
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(model) {
        model.haptic = { event ->
            when (event) {
                AlkkagiPhoneHaptic.Select, AlkkagiPhoneHaptic.Power, AlkkagiPhoneHaptic.Place -> haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                is AlkkagiPhoneHaptic.Launch, is AlkkagiPhoneHaptic.Impact -> haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            }
        }
    }
    MiniGameFrameLoop(running = true, refreshHz = refreshHz) { nanos -> model.tick(nanos / 1e9) }
    val accent = AingTheme.colors.accent
    val danger = AingTheme.colors.danger
    BoxWithConstraints(modifier.fillMaxWidth().aspectRatio(1f)) {
        val sidePx = constraints.maxWidth.toFloat()
        val side = maxWidth
        val shake = if (reduceMotion) Offset.Zero else {
            val recoil = model.launchRecoil
            Offset((sin(model.time * 155) * model.jolt * 2.5 + recoil.x * 0.6).toFloat(), (cos(model.time * 183) * model.jolt * 1.8 + recoil.y * 0.6).toFloat())
        }
        Box(Modifier.offset { IntOffset(shake.x.roundToInt(), shake.y.roundToInt()) }) {
            Canvas(
                Modifier.matchParentSizeSquare(side).shadow(6.dp, RoundedCornerShape(10.dp)).clip(RoundedCornerShape(10.dp))
                    .semantics {
                        contentDescription = "알까기 바둑판"
                        stateDescription = model.status
                    }
                    .pointerInput(model) {
                        awaitEachGesture {
                            val down = awaitFirstDown(requireUnconsumed = false)
                            val k = AlkkagiGame.boardSize / size.width
                            val start = AlkkagiVector(down.position.x * k, down.position.y * k)
                            model.aim(start, AlkkagiVector.zero)
                            down.consume()
                            while (true) {
                                val event = awaitPointerEvent()
                                val change = event.changes.firstOrNull { it.id == down.id } ?: break
                                if (!change.pressed) break
                                change.consume()
                                model.aim(start, AlkkagiVector((change.position.x - down.position.x) * k, (change.position.y - down.position.y) * k))
                            }
                            model.release()
                        }
                    },
            ) {
                GamesAlkkagiDrawing.board(this)
                val scale = (size.width / AlkkagiGame.boardSize).toFloat()
                val game = model.game
                if (game.phase == AlkkagiGame.Phase.placing && placingPlayer != null) {
                    val y = if (placingPlayer == AlkkagiGame.Player.black) size.height / 2 else 0f
                    drawRect(accent.copy(alpha = 0.12f), Offset(0f, y), Size(size.width, size.height / 2))
                }
                for (stone in game.stones) {
                    if (!stone.isPlaced || stone.isOut) continue
                    GamesAlkkagiDrawing.stone(this, stone, scale, stone.id == model.selectedID, model.pull, model.launch, model.hits, !reduceMotion)
                }
                val selected = model.selectedStone
                if (selected != null && game.phase == AlkkagiGame.Phase.aiming) GamesAlkkagiDrawing.aim(this, selected, model.pull, scale)
                val preview = model.placementPoint
                val id = model.dragPlacementID
                val stone = id?.let { i -> game.stones.firstOrNull { it.id == i } }
                if (preview != null && stone != null) {
                    val c = Offset((preview.x * scale).toFloat(), (preview.y * scale).toFloat())
                    val r = (AlkkagiGame.stoneRadius * scale).toFloat()
                    GamesAlkkagiDrawing.disc(this, c, r, stone.owner, 0.65f)
                    drawCircle(if (game.canPlace(stone.id, preview)) accent else danger, r + 3, c, style = Stroke(2f))
                }
                GamesAlkkagiDrawing.effects(this, model.hits, scale, reduceMotion)
            }
            // 떨어지는 돌은 판 칸 밖(여백)까지 그린다 — 판과 같은 크기의 **자르지 않는** 캔버스를 겹쳐 둔다(판을 밀지 않게 · Compose Canvas 는 기본으로 자르지 않는다).
            Canvas(Modifier.size(side)) {
                GamesAlkkagiDrawing.falling(this, model.falls, (sidePx / AlkkagiGame.boardSize).toFloat(), Offset.Zero, reduceMotion)
            }
        }
    }
}

private fun Modifier.matchParentSizeSquare(side: androidx.compose.ui.unit.Dp): Modifier = this.size(side)

/** 관전 판 — 판 화면과 같은 그림 · 입력 없음. 굴림 중이면 서버 시각으로 되살린다. */
@Composable
fun GamesAlkkagiWatchBoard(store: AlkkagiOnlineStore, watch: AlkkagiWatchState, refreshHz: Int, modifier: Modifier = Modifier) {
    val rolling = watch.phase == AlkkagiMatchPhase.rolling && watch.shot != null
    var frame by remember { mutableLongStateOf(0L) }
    MiniGameFrameLoop(running = rolling && store.isWindowVisible, refreshHz = refreshHz) { frame += 1 }
    @Suppress("UNUSED_VARIABLE") val redraw = frame
    val stones = GamesAlkkagiDrawing.watchStones(watch, store.estimatedServerNowMs)
    Canvas(
        modifier.fillMaxWidth().aspectRatio(1f).shadow(6.dp, RoundedCornerShape(10.dp)).clip(RoundedCornerShape(10.dp))
            .semantics { contentDescription = "알까기 바둑판(관전)" },
    ) {
        GamesAlkkagiDrawing.board(this)
        val scale = (size.width / AlkkagiGame.boardSize).toFloat()
        for (stone in stones) {
            if (!stone.isPlaced || stone.isOut) continue
            GamesAlkkagiDrawing.stone(this, stone, scale, false, AlkkagiVector.zero, null, emptyList(), false)
        }
    }
}
