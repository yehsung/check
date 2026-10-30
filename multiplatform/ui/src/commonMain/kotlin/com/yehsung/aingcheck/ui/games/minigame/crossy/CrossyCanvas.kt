// 원본: Sources/check/MiniGameCrossy.swift @ 1b8260d (CrossyGameView 틀 · CrossyHUD 점수·카드 — :20-195)
// 원본: Sources/check/MiniGameCrossyScene.swift @ 1b8260d (CrossyScene 카메라·아잉이·죽음 연출 :34-534 · CrossyPalette 색·모양 :580-904)
//
// 길건너 아잉이 한 프레임의 그림(W-9 #6 — ui 안 Canvas, GamesFlappyCanvas 와 같은 길). 규칙은 core/rules `CrossyGame` 하나이고
// 이 파일은 **읽기만** 한다(판을 고치는 줄 0 — 규칙 사본 금지). 맥은 SceneKit 3D(정사영 · 내려보기 56° · 옆으로 14°)이고 여기는
// 같은 정사영을 2.5D 로 편다: 땅 한 줄 = 윗면 띠, 물건 = 윗면 + 앞면 상자(빛은 맥 해 방향처럼 윗면이 밝다). 옆 기울기 14° 는 뺐다(unresolved).
//
// 지키는 것
//  · **판 시간으로만 움직인다.** 아잉이 자리(`playerVisual`)·세로 카메라(`cameraRow`)는 규칙 값이고, 가로 카메라만 그림 쪽 상태다 —
//    그 따라가기도 틱 수가 아니라 판 시간(`elapsed`) 차이로 섞는다([CrossyCameraFollower]). 그래서 틱 주기(주사율의 약수 — MiniGameFramePacer)가
//    60·75·120·144Hz 어디서든 같은 판 시각이면 같은 그림이다(기억 game-frame-rate-judder).
//  · 마스코트는 플래피와 같은 그림 경로(`MiniGameArt.flappySide` — 아잉 고정). 그림이 없으면 근무 초록 원(Swift 폴백과 같다).
//  · 반복 애니메이션 0 — 판이 멈추면(시작 전 · 결과 · 정지) 그림도 멈춘다(맥 :20 "repeatForever 를 넣지 마라").
package com.yehsung.aingcheck.ui.games.minigame.crossy

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.ui.games.minigame.GamesCanvasColors
import com.yehsung.aingcheck.ui.games.minigame.GamesOverlayCard
import com.yehsung.aingcheck.ui.games.minigame.MiniGameArt
import com.yehsung.aingcheck.ui.games.minigame.TABULAR_NUMBERS
import com.yehsung.aingcheck.ui.games.minigame.canvasFont
import com.yehsung.aingcheck.ui.games.minigame.canvasSp
import com.yehsung.aingcheck.ui.games.minigame.canvasTextShadow
import com.yehsung.aingcheck.ui.games.minigame.centeredAt
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/** 그림 상수(난이도와 무관 — 맥 `CrossyScene` :34-57 · `CrossyHUD` :131-140). */
object CrossyLook {
    /** 정사영 반높이(세계 단위) — 캔버스 세로가 2 × 3.1 단위다(맥 `orthographicScale`). */
    const val orthographicScale: Double = 3.1
    const val pitchDegrees: Double = 56.0
    /** 카메라가 아잉이보다 앞을 보는 줄 수(맥 `lookAhead`). */
    const val lookAhead: Double = 1.35
    /** 가로 카메라가 가운데서 벗어나는 한도(칸 — 맥 `cameraSwing`). */
    const val cameraSwing: Double = 2.0
    /** 가로 카메라 따라가기 비율(초당 — 맥 `updateCamera` 의 dt × 6). */
    const val cameraFollowRate: Double = 6.0
    const val aingHeight: Double = 0.98
    const val hopLift: Double = 0.55
    /** 놀이 칸(9칸) 밖까지 깔리는 땅의 반폭(세계 단위 — 맥 `groundHalfWidth`). */
    const val groundHalfWidth: Double = 16.0
    const val slabDepth: Double = 1.6
    const val waveSpacing: Double = 2.1
    /** 점수 글자 세로 중심(pt, 캔버스 위에서 — 맥 `CrossyHUD.scoreCenterY`). */
    const val scoreCenterY: Float = 31f

    val pitchRadians: Double get() = pitchDegrees * PI / 180.0

    /** 땅 윗면 높이(맥 `groundTop`). 강이 제일 낮다. */
    fun groundTop(kind: CrossyGame.LaneKind?): Double = when (kind) {
        CrossyGame.LaneKind.grass, null -> 0.0
        CrossyGame.LaneKind.road -> -0.08
        CrossyGame.LaneKind.river -> -0.30
        CrossyGame.LaneKind.rail -> -0.04
    }

    /** 아잉이가 서는 높이(강이면 통나무 윗면 — 맥 `standHeight`). */
    fun standHeight(kind: CrossyGame.LaneKind?): Double = when (kind) {
        CrossyGame.LaneKind.grass, null -> 0.0
        CrossyGame.LaneKind.road -> -0.08
        CrossyGame.LaneKind.river -> -0.08
        CrossyGame.LaneKind.rail -> -0.04
    }
}

/** 색(맥 `CrossyPalette` — 시안 px 그대로). 3D 판은 앱 테마와 무관하다(맥도 한 벌이다). */
object CrossyPaint {
    val background = hex(0x1A1C26)
    val grassDark = hex(0x9AD35B)
    val grassLight = hex(0x8FCA50)
    val road = hex(0x575D6B)
    val river = hex(0x52BDF2)
    val rail = hex(0x6E6862)
    val roadDash = hex(0xE6E9EF)
    val wave = hex(0xB5E7FF)
    val sleeper = hex(0x8A6A4C)
    val railSteel = hex(0xC9CED6)
    val railWarning = hex(0xFF4A4A)
    val signalPost = hex(0x3A3F4A)
    val signalHead = hex(0x2A2D36)
    val lampOn = hex(0xFF4A4A)
    val lampOff = hex(0x5A2A2A)
    val trunk = hex(0x7A4F2E)
    val leaves = hex(0x4CAF50)
    val leavesTop = hex(0x5CC060)
    val rock = hex(0xA3A9B3)
    val rockTop = hex(0xB9BEC7)
    val tyre = hex(0x2A2D36)
    val glass = hex(0x2C3A58)
    val body = hex(0xF3F4F7)
    val cabTop = hex(0xF4F6FA)
    val headlight = hex(0xF2B632)
    val headlightPale = hex(0xFFF2C2)
    val taillight = hex(0xE0475A)
    val log = hex(0x8F5C36)
    val logStripe = hex(0xA8703F)
    val logEnd = hex(0xD39C67)
    val engine = hex(0xE0475A)
    val carriageStripe = hex(0x3A7BF0)
    val splash = hex(0xE8F7FF)
    val carColors: List<Color> = listOf(hex(0x3A7BF0), hex(0xE0479E), hex(0xF2B632), hex(0x35C2A0), hex(0xF06A3C))
    /** 카드·행동 알약 강조색(맥 `CrossyHUD.tint` — 풀밭 위 따뜻한 노랑). */
    val tint = Color(1.0f, 0.84f, 0.40f)

    fun lane(kind: CrossyGame.LaneKind, row: Int): Color = when (kind) {
        CrossyGame.LaneKind.grass -> if (row and 1 == 0) grassDark else grassLight
        CrossyGame.LaneKind.road -> road
        CrossyGame.LaneKind.river -> river
        CrossyGame.LaneKind.rail -> rail
    }

    /** 놀이 칸 밖은 같은 색을 22% 어둡게(맥 slab outside — 크로시 로드식 경계). */
    fun outside(color: Color): Color = shade(color, 0.78f)

    /** 앞면(카메라 쪽 면) — 해가 위·왼쪽 뒤에서 와서 윗면보다 어둡다. */
    fun front(color: Color): Color = shade(color, 0.74f)

    fun shade(color: Color, k: Float): Color = Color(color.red * k, color.green * k, color.blue * k, color.alpha)

    private fun hex(v: Long): Color = Color(((v shr 16) and 0xFF) / 255f, ((v shr 8) and 0xFF) / 255f, (v and 0xFF) / 255f)
}

/**
 * 가로 카메라(맥 `updateCamera` — 가로는 부드럽게, 세로는 규칙의 `cameraRow` 그대로). 따라가기는 **판 시간 차이**로 섞는다:
 * `k = 1 − e^(−6·dt)`(맥 `min(1, dt × 6)` 의 주사율 무관판 — 작은 dt 에서 같다). 같은 판 시각을 두 번 그려도(재구성) 움직이지 않고,
 * 새 판(시간이 뒤로 감) · 시작 전에는 바로 그 자리에 선다.
 */
class CrossyCameraFollower {
    private var x: Double? = null
    private var at: Double = 0.0

    fun follow(game: CrossyGame): Double {
        val wanted = wantedX(game)
        val previous = x
        if (previous == null || game.elapsed < at || game.phase == CrossyGame.Phase.Ready) {
            x = wanted
            at = game.elapsed
            return wanted
        }
        val dt = game.elapsed - at
        at = game.elapsed
        val next = previous + (wanted - previous) * (1.0 - exp(-CrossyLook.cameraFollowRate * dt))
        x = next
        return next
    }

    companion object {
        /** 카메라가 가려는 가로 자리(가운데 칸 4 기준, ±[CrossyLook.cameraSwing] — 죽으면 죽은 자리). */
        fun wantedX(game: CrossyGame): Double {
            val x = game.death?.x ?: game.playerVisual.x
            return min(CrossyLook.cameraSwing, max(-CrossyLook.cameraSwing, x - CrossyGame.startColumn))
        }
    }
}

/** 세계(칸 · 줄 · 높이) → 화면 픽셀. 정사영 내려보기: 줄 하나 = sin 56° 단위, 높이 하나 = cos 56° 단위. */
class CrossyView(val size: Size, val cameraX: Double, cameraRow: Double) {
    /** 세계 1 단위의 화면 픽셀. */
    val unit: Double = size.height / (2.0 * CrossyLook.orthographicScale)
    val rowStep: Double = unit * sin(CrossyLook.pitchRadians)
    val rise: Double = unit * cos(CrossyLook.pitchRadians)
    val focusRow: Double = cameraRow + CrossyLook.lookAhead

    /** 칸 좌표(가운데 칸 4 가 x = 4) → 화면 x. */
    fun x(column: Double): Float = (size.width / 2.0 + (column - CrossyGame.startColumn - cameraX) * unit).toFloat()

    /** 줄 좌표 · 높이 → 화면 y(앞 줄이 위). */
    fun y(row: Double, height: Double = 0.0): Float = (size.height / 2.0 - (row - focusRow) * rowStep - height * rise).toFloat()

    /** 화면에 걸리는 줄 범위(먼 줄 → 가까운 줄 순서로 그린다). */
    val farRow: Int get() = ceil(focusRow + (size.height / 2.0) / rowStep + 2.5).toInt()
    val nearRow: Int get() = floor(focusRow - (size.height / 2.0 + CrossyLook.slabDepth * rise) / rowStep - 2.5).toInt()
}

/** 아잉이 한 프레임의 몸(맥 `updateAing` :373-484 — 뛰기 늘이기 · 착지 눌림 · 죽음 연출 넷 · 동작 줄이기). */
data class CrossyAingPose(
    val column: Double,
    val row: Double,
    val height: Double,
    /** 발밑(뜀 높이를 뺀 서는 높이) — 그림자 자리. */
    val ground: Double,
    val scaleX: Float,
    val scaleY: Float,
    val rollDegrees: Float,
    val alpha: Float,
    val mirrored: Boolean,
    val shadowAlpha: Float,
    val shadowScale: Float,
    /** 첨벙 고리 진행(0~1) — 물에 빠졌을 때만. */
    val splash: Double?,
) {
    companion object {
        /** 착지 직후 눌림 길이(초). 맥은 노드 상태(landedAt)로 재고 여기는 판 값(마지막 착지 = 뛰기 끝 시각)이 없어 뛰기 끝 직후 [squashSeconds] 를 뺀다. */
        const val squashSeconds: Double = 0.08

        fun of(game: CrossyGame, reduceMotion: Boolean): CrossyAingPose {
            val visual = game.playerVisual
            val laneHere = game.lane(visual.row.roundToInt())?.kind
            var height = CrossyLook.standHeight(laneHere)
            val hop = game.hop
            if (hop != null) {
                val from = CrossyLook.standHeight(game.lane(hop.fromRow)?.kind)
                val to = CrossyLook.standHeight(game.lane(hop.toRow)?.kind)
                height = from + (to - from) * hop.progress
            }
            val lift = if (reduceMotion) 0.0 else visual.lift * CrossyLook.hopLift
            var sx = 1f
            var sy = 1f
            if (hop != null && !reduceMotion) {
                val s = sin(PI * hop.progress).toFloat()
                sy = 1f + 0.13f * s
                sx = 1f - 0.10f * s
            }
            var column = visual.x
            var row = visual.row
            var roll = 0f
            var alpha = 1f
            var splash: Double? = null
            val death = game.death
            if (death != null) {
                column = death.x
                row = death.row.toDouble()
                val t = max(0.0, game.elapsed - death.at)
                val kind = game.lane(death.row)?.kind
                height = CrossyLook.standHeight(kind)
                val ease = min(1.0, t / 0.12).toFloat()
                when (death.cause) {
                    CrossyGame.DeathCause.car -> {
                        sy = 1f - 0.82f * ease
                        sx = 1f + 0.35f * ease
                    }
                    CrossyGame.DeathCause.water, CrossyGame.DeathCause.carriedOff -> {
                        val sink = min(1.0, t / 0.55)
                        height = CrossyLook.groundTop(CrossyGame.LaneKind.river) - 0.9 * sink * sink
                        alpha = max(0.0, 1.0 - sink).toFloat()
                        splash = min(1.0, t / 0.6)
                    }
                    CrossyGame.DeathCause.train -> {
                        val fly = min(t, 0.9)
                        column += death.pushDirection * 7.5 * fly
                        height += 3.2 * fly - 3.0 * fly * fly
                        roll = (death.pushDirection * -11.0 * fly * 180.0 / PI).toFloat()
                        alpha = if (t > 0.9) 0f else 1f
                    }
                    CrossyGame.DeathCause.leftBehind -> {
                        val fall = min(1.0, t / 0.7)
                        row -= 1.6 * fall * fall
                        height -= 0.4 * fall * fall
                        sy = 1f - 0.45f * fall.toFloat() // 맥은 뒤로 넘어진다(pitch 1.3) — 2.5D 에서는 납작해지는 것으로 보인다
                        alpha = max(0.0, 1.0 - fall).toFloat()
                    }
                }
                if (reduceMotion) {
                    // 동작 줄이기: 움직이는 연출 없이 그 자리에서 사라진다(사유는 결과 카드 글자가 말한다).
                    sx = 1f; sy = 1f; roll = 0f; splash = null
                    column = death.x
                    row = death.row.toDouble()
                    height = CrossyLook.standHeight(kind)
                    alpha = max(0.0, 1.0 - t / 0.4).toFloat()
                }
            }
            val facing = game.player.facing
            val liftShare = visual.lift.toFloat()
            val shadowGone = death?.cause.let {
                it == CrossyGame.DeathCause.water || it == CrossyGame.DeathCause.carriedOff || it == CrossyGame.DeathCause.train
            }
            return CrossyAingPose(
                column = column,
                row = row,
                height = height + lift,
                ground = height,
                scaleX = sx,
                scaleY = sy,
                rollDegrees = roll,
                alpha = alpha,
                mirrored = facing == CrossyGame.Direction.left,
                shadowAlpha = if (shadowGone) 0f else (1f - 0.3f * liftShare) * alpha,
                shadowScale = 1f - 0.30f * liftShare,
                splash = splash,
            )
        }
    }
}

/** 점수를 위에 띄우는가(진행 · 죽음 연출 중 — 맥 `CrossyHUD.showsTopScore`). */
internal val CrossyGame.showsTopScore: Boolean
    get() = phase == CrossyGame.Phase.Running || phase is CrossyGame.Phase.Over

/**
 * 길건너 캔버스(그림 + 점수 + 시작/결과 카드). [game] 은 읽기만 한다. [bestScore] 는 결과 카드의 "최고 N" · 신기록 판정.
 */
@Composable
fun CrossyCanvas(game: CrossyGame, bestScore: Long, reduceMotion: Boolean, art: MiniGameArt, modifier: Modifier = Modifier) {
    val camera = remember { CrossyCameraFollower() }
    val cameraX = camera.follow(game)
    val density = LocalDensity.current.density
    BoxWithConstraints(modifier) {
        val sprite = if (game.isGameOver && game.death?.cause == CrossyGame.DeathCause.car) art.flappyNegative ?: art.flappySide else art.flappySide
        val scale = (maxWidth.value / CROSSY_REFERENCE_WIDTH).coerceIn(0.6f, 1.6f)
        val centerX = constraints.maxWidth / 2f
        Canvas(Modifier.fillMaxSize()) { drawCrossy(this, game, cameraX, reduceMotion, sprite) }
        Box(Modifier.fillMaxSize().clearAndSetSemantics { }) {
            if (game.showsTopScore) {
                Text(
                    game.score.toString(),
                    modifier = Modifier.centeredAt(centerX, CrossyLook.scoreCenterY * scale * density),
                    style = TextStyle(
                        fontFamily = canvasFont(), fontSize = canvasSp(28 * scale), fontWeight = FontWeight.ExtraBold,
                        fontFeatureSettings = TABULAR_NUMBERS, color = Color.White.copy(alpha = 0.94f), shadow = canvasTextShadow(0.55f, 7f, 1f),
                    ),
                )
            }
            when (game.phase) {
                CrossyGame.Phase.Ready -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    GamesOverlayCard(
                        title = MiniGameKind.crossy.title, subtitle = GamesMiniGameText.howToPlay(MiniGameKind.crossy),
                        action = GamesMiniGameText.crossyStartAction, icon = MiniGameKind.crossy.icon, tint = CrossyPaint.tint, scale = scale,
                    )
                }
                CrossyGame.Phase.Result -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    GamesOverlayCard(
                        title = "${game.score}점", titleIsScore = true,
                        subtitle = GamesMiniGameText.crossyResultSubtitle(game.score, bestScore, game.death?.cause),
                        subtitleIsHighlighted = game.score.toLong() > bestScore,
                        action = GamesMiniGameText.crossyRetryAction, icon = MiniGameKind.crossy.icon, tint = CrossyPaint.tint, scale = scale,
                    )
                }
                CrossyGame.Phase.Running, is CrossyGame.Phase.Over -> Unit
            }
        }
    }
}

/** 카드·글자 배율의 기준 폭(dp — 맥 미니게임 캔버스 폭 292). */
private const val CROSSY_REFERENCE_WIDTH: Float = 292f

/** 한 프레임(시험이 화면 없이 부를 수 있게 DrawScope 하나만 받는다). */
fun drawCrossy(scope: DrawScope, game: CrossyGame, cameraX: Double, reduceMotion: Boolean, sprite: ImageBitmap?) = with(scope) {
    drawRect(CrossyPaint.background)
    val view = CrossyView(size, cameraX, game.cameraRow)
    val pose = CrossyAingPose.of(game, reduceMotion)
    val poseRow = pose.row.roundToInt()
    val flying = game.death?.cause == CrossyGame.DeathCause.train
    for (row in view.farRow downTo view.nearRow) {
        val lane = game.lane(row)
        drawGround(view, lane, row, game)
        if (lane != null) drawLaneThings(view, lane, game)
        if (row == poseRow && !flying) drawAing(view, pose, sprite)
    }
    if (flying) drawAing(view, pose, sprite)
}

private fun DrawScope.band(view: CrossyView, x0: Double, x1: Double, rowNear: Double, rowFar: Double, top: Double, color: Color) {
    val left = view.x(x0)
    val right = view.x(x1)
    val yTop = view.y(rowFar, top)
    val yBottom = view.y(rowNear, top)
    if (right <= 0f || left >= size.width || yBottom <= 0f || yTop >= size.height) return
    drawRect(color, Offset(left, yTop), Size(right - left, yBottom - yTop))
}

/** 상자 하나(윗면 + 앞면). x·줄은 칸 좌표, 높이는 세계 단위. */
private fun DrawScope.box(view: CrossyView, x0: Double, x1: Double, rowNear: Double, rowFar: Double, bottom: Double, top: Double, color: Color) {
    val left = view.x(x0)
    val right = view.x(x1)
    if (right <= 0f || left >= size.width) return
    val frontTop = view.y(rowNear, top)
    val frontBottom = view.y(rowNear, bottom)
    if (frontBottom > frontTop) drawRect(CrossyPaint.front(color), Offset(left, frontTop), Size(right - left, frontBottom - frontTop))
    val topFar = view.y(rowFar, top)
    if (frontTop > topFar) drawRect(color, Offset(left, topFar), Size(right - left, frontTop - topFar))
}

private fun DrawScope.drawGround(view: CrossyView, lane: CrossyGame.Lane?, row: Int, game: CrossyGame) {
    val kind = lane?.kind ?: CrossyGame.LaneKind.grass
    val top = CrossyLook.groundTop(lane?.kind)
    val base = CrossyPaint.lane(kind, row)
    val half = CrossyLook.groundHalfWidth
    val c = CrossyGame.startColumn.toDouble()
    val near = row - 0.5
    val far = row + 0.5
    val playMin = -0.5
    val playMax = CrossyGame.columns - 0.5
    // 앞면(판 두께) 먼저 — 다음(가까운) 줄이 더 낮으면 그 틈으로 보인다.
    box(view, c - half, playMin, near, far, top - CrossyLook.slabDepth, top, CrossyPaint.outside(base))
    box(view, playMin, playMax, near, far, top - CrossyLook.slabDepth, top, base)
    box(view, playMax, c + half, near, far, top - CrossyLook.slabDepth, top, CrossyPaint.outside(base))
    if (lane == null) return
    when (kind) {
        CrossyGame.LaneKind.road -> if (game.lane(row + 1)?.kind == CrossyGame.LaneKind.road) {
            // 찻길끼리 붙은 경계의 점선(맥 roadDashes — 먼 쪽 경계).
            var x = c - half + 0.3
            while (x < c + half) {
                band(view, x - 0.25, x + 0.25, far - 0.04, far + 0.04, top + 0.005, CrossyPaint.roadDash)
                x += 1.0
            }
        }
        CrossyGame.LaneKind.river -> {
            // 물결(맥 riverWaves — 줄 홀짝 두 갈래 · 흐름 쪽으로 천천히, 무늬 간격으로 감는다).
            val spacing = CrossyLook.waveSpacing
            val drift = (game.elapsed * lane.velocity * 0.35).rem(spacing)
            var seed = (977uL * (row and 1).toULong() + 977uL + 13uL)
            var x = c - half - spacing
            while (x < c + half + spacing) {
                seed = seed * 6_364_136_223_846_793_005uL + 1_442_695_040_888_963_407uL
                val fx = ((seed shr 33) % 1000uL).toDouble() / 1000.0
                val fz = ((seed shr 20) % 1000uL).toDouble() / 1000.0
                val wx = x + fx * 0.8 + drift
                val wz = row - 0.3 + fz * 0.6
                band(view, wx - 0.225, wx + 0.225, wz - 0.03, wz + 0.03, top + 0.004, CrossyPaint.wave)
                x += spacing
            }
        }
        CrossyGame.LaneKind.rail -> {
            val warning = lane.isTrainWarning && (game.elapsed / 0.15).toInt() % 2 == 0
            var x = c - half
            while (x <= c + half) {
                box(view, x - 0.10, x + 0.10, row - 0.41, row + 0.41, top, top + 0.05, CrossyPaint.sleeper)
                x += 0.5
            }
            for (z in listOf(0.22, -0.22)) {
                box(view, c - half, c + half, row + z - 0.03, row + z + 0.03, top + 0.05, top + 0.11, if (warning) CrossyPaint.railWarning else CrossyPaint.railSteel)
            }
        }
        CrossyGame.LaneKind.grass -> {
            // 경계 숲(놀이 칸 밖 양옆 세 칸씩 — 맥 borderForest, 줄 홀짝 두 갈래).
            val variant = row and 1
            for (dx in listOf(-7, -6, -5, 5, 6, 7)) {
                if (!((variant + dx) and 1 == 0 || kotlin.math.abs(dx) >= 6)) continue
                val height = if (kotlin.math.abs(dx) == 6) 1.3 else if ((variant + kotlin.math.abs(dx)) % 3 == 0) 1.0 else 0.8
                tree(view, c + dx, row.toDouble(), height)
            }
        }
    }
}

private fun DrawScope.tree(view: CrossyView, column: Double, row: Double, height: Double) {
    box(view, column - 0.13, column + 0.13, row - 0.13, row + 0.13, 0.0, 0.30, CrossyPaint.trunk)
    val foliage = max(0.2, height - 0.3)
    box(view, column - 0.36, column + 0.36, row - 0.36, row + 0.36, 0.30, 0.30 + foliage, CrossyPaint.leaves)
    box(view, column - 0.25, column + 0.25, row - 0.25, row + 0.25, 0.30 + foliage, 0.30 + foliage + 0.22, CrossyPaint.leavesTop)
}

private fun DrawScope.drawLaneThings(view: CrossyView, lane: CrossyGame.Lane, game: CrossyGame) {
    val row = lane.row.toDouble()
    val top = CrossyLook.groundTop(lane.kind)
    when (lane.kind) {
        CrossyGame.LaneKind.grass -> lane.props.forEachIndexed { column, prop ->
            when (prop) {
                is CrossyGame.Prop.Tree -> tree(view, column.toDouble(), row, 1.0 + 0.35 * prop.height)
                CrossyGame.Prop.Rock -> {
                    box(view, column - 0.31, column + 0.31, row - 0.27, row + 0.27, 0.0, 0.32, CrossyPaint.rock)
                    box(view, column - 0.24, column + 0.12, row - 0.15, row + 0.19, 0.32, 0.46, CrossyPaint.rockTop)
                }
                null -> Unit
            }
        }
        CrossyGame.LaneKind.road -> for (mover in lane.movers) vehicle(view, mover, row, top, lane.direction)
        CrossyGame.LaneKind.river -> for (mover in lane.movers) {
            // 통나무(맥 log — 물 위 윗면 −0.08, 줄무늬 · 밝은 끝면).
            val x0 = mover.x
            val x1 = mover.maxX
            box(view, x0, x1, row - 0.36, row + 0.36, -0.42, -0.08, CrossyPaint.log)
            band(view, x0 + 0.15, x1 - 0.15, row + 0.03, row + 0.21, -0.07, CrossyPaint.logStripe)
            box(view, x0 - 0.015, x0 + 0.015, row - 0.33, row + 0.33, -0.40, -0.10, CrossyPaint.logEnd)
            box(view, x1 - 0.015, x1 + 0.015, row - 0.33, row + 0.33, -0.40, -0.10, CrossyPaint.logEnd)
        }
        CrossyGame.LaneKind.rail -> {
            lane.train?.let { train(view, it, row, top, lane.direction) }
            // 신호등(놀이 칸 왼쪽 밖 — 경고 중 0.15초 깜빡임, 맥 lampOn/lampOff).
            val blinkOn = lane.isTrainWarning && (game.elapsed / 0.15).toInt() % 2 == 0
            val post = -1.0
            box(view, post - 0.04, post + 0.04, row + 0.38, row + 0.46, top, top + 1.02, CrossyPaint.signalPost)
            box(view, post - 0.16, post + 0.16, row + 0.36, row + 0.48, top + 0.91, top + 1.13, CrossyPaint.signalHead)
            box(view, post - 0.08, post + 0.08, row + 0.35, row + 0.36, top + 0.95, top + 1.09, if (blinkOn) CrossyPaint.lampOn else CrossyPaint.lampOff)
        }
    }
}

private fun DrawScope.vehicle(view: CrossyView, mover: CrossyGame.Mover, row: Double, top: Double, direction: Int) {
    val x0 = mover.x
    val x1 = mover.maxX
    val hex = CrossyPaint.carColors[((mover.variant % CrossyPaint.carColors.size) + CrossyPaint.carColors.size) % CrossyPaint.carColors.size]
    val nose = if (direction >= 0) x1 else x0
    val tail = if (direction >= 0) x0 else x1
    // 바퀴(앞면에 보이는 둘).
    for (w in listOf(x0 + 0.3, x1 - 0.3)) box(view, w - 0.16, w + 0.16, row - 0.42, row - 0.38, top, top + 0.32, CrossyPaint.tyre)
    if (mover.isTruck) {
        val cab = 0.62
        val cabX0 = if (direction >= 0) x1 - cab else x0
        val boxX0 = if (direction >= 0) x0 else x0 + cab
        box(view, boxX0, boxX0 + (x1 - x0 - cab), row - 0.42, row + 0.42, top + 0.24, top + 1.10, CrossyPaint.body)
        box(view, cabX0, cabX0 + cab, row - 0.40, row + 0.40, top + 0.24, top + 0.86, hex)
        box(view, cabX0 + 0.08, cabX0 + cab - 0.08, row - 0.41, row - 0.39, top + 0.55, top + 0.77, CrossyPaint.glass)
    } else {
        box(view, x0, x1, row - 0.40, row + 0.40, top + 0.16, top + 0.58, hex)
        val inset = (x1 - x0) * 0.2
        box(view, x0 + inset, x1 - inset, row - 0.35, row + 0.35, top + 0.58, top + 0.94, CrossyPaint.cabTop)
        box(view, x0 + inset + 0.04, x1 - inset - 0.04, row - 0.37, row - 0.355, top + 0.62, top + 0.86, CrossyPaint.glass)
    }
    // 앞등 · 뒷등(앞면 위 작은 점).
    val light = if (hex == CrossyPaint.headlight) CrossyPaint.headlightPale else CrossyPaint.headlight
    val sign = if (direction >= 0) 1.0 else -1.0
    val head = nose - 0.09 * sign
    val back = tail + 0.09 * sign
    box(view, head - 0.04, head + 0.04, row - 0.41, row - 0.40, top + 0.40, top + 0.49, light)
    box(view, back - 0.04, back + 0.04, row - 0.41, row - 0.40, top + 0.40, top + 0.48, CrossyPaint.taillight)
}

private fun DrawScope.train(view: CrossyView, train: CrossyGame.Mover, row: Double, top: Double, direction: Int) {
    val carLength = 2.8
    var cx = train.x
    val end = train.maxX
    var index = 0
    val count = ceil((end - cx) / carLength).toInt()
    while (cx < end - 0.01) {
        val next = min(end, cx + carLength)
        val engine = if (direction >= 0) index == count - 1 else index == 0
        box(view, cx + 0.06, next - 0.06, row - 0.44, row + 0.44, top + 0.22, top + 1.17, if (engine) CrossyPaint.engine else CrossyPaint.body)
        band(view, cx + 0.06, next - 0.06, row - 0.44, row - 0.40, top + 0.84, if (engine) CrossyPaint.body else CrossyPaint.carriageStripe)
        box(view, cx + 0.30, next - 0.30, row - 0.45, row - 0.44, top + 0.70, top + 0.90, CrossyPaint.glass)
        cx = next
        index += 1
    }
}

private fun DrawScope.drawAing(view: CrossyView, pose: CrossyAingPose, sprite: ImageBitmap?) {
    if (pose.alpha <= 0f && pose.splash == null) return
    val cx = view.x(pose.column)
    // 발밑 그림자(맥 blob — 뛰면 작고 옅어진다).
    if (pose.shadowAlpha > 0f) {
        val w = (0.62 * view.unit * pose.shadowScale).toFloat()
        val h = (0.62 * view.rowStep * pose.shadowScale).toFloat() * 0.8f
        drawOval(Color.Black.copy(alpha = 0.30f * pose.shadowAlpha), Offset(cx - w / 2, view.y(pose.row, pose.ground) - h / 2), Size(w, h))
    }
    pose.splash?.let { p ->
        if (p < 1.0) {
            val r = ((0.4 + 1.4 * p) * 0.5 * view.unit).toFloat()
            val y = view.y(pose.row, CrossyLook.groundTop(CrossyGame.LaneKind.river) + 0.01)
            drawOval(CrossyPaint.splash.copy(alpha = (0.9 * (1 - p)).toFloat()), Offset(cx - r, y - r * 0.83f), Size(2 * r, 2 * r * 0.83f), style = Stroke((0.06 * view.unit).toFloat()))
        }
    }
    if (pose.alpha <= 0f) return
    val side = (CrossyLook.aingHeight * view.unit * 1.05).toFloat()
    val bottom = view.y(pose.row, pose.height)
    val pivot = Offset(cx, bottom)
    run {
        rotate(pose.rollDegrees, pivot) {
            scale(if (pose.mirrored) -pose.scaleX else pose.scaleX, pose.scaleY, pivot) {
                val topLeft = Offset(cx - side / 2, bottom - side)
                if (sprite != null) {
                    drawImage(
                        sprite, IntOffset.Zero, IntSize(sprite.width, sprite.height),
                        IntOffset(topLeft.x.roundToInt(), topLeft.y.roundToInt()), IntSize(side.roundToInt(), side.roundToInt()),
                        alpha = pose.alpha, filterQuality = FilterQuality.High,
                    )
                } else {
                    drawCircle(GamesCanvasColors.working.copy(alpha = pose.alpha), side * 0.42f, Offset(cx, bottom - side * 0.45f))
                }
            }
        }
    }
}
