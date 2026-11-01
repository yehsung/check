// 원본: Sources/CheckMobileKit/Games/GamesRummyTableCanvas.swift:1 @ ios-1017-cube 614d98bd · 맥 Sources/check/RummyTableCanvas.swift:192 (RummyTableCanvasView — 미리보기 · 손잡이 그림) @ 1a5eeca6 · 설계서 §4
//
// 폰 아잉 큐브 판 칸(입력은 없다 — 손은 화면 전체 입력 층 하나가 받는다).
//
// ── 왜 GamesRummyTile 을 안 쓰고 Canvas 에 그리는가 ──
// 판에는 타일이 100장 넘게 깔린다. GamesRummyTile 은 타일마다 Box · Text · Canvas 노드라 100장이면 노드가 수백 개고 판이 바뀔 때마다 그만큼 다시 잰다. 그래서 판 쪽은:
//   ① **Canvas 하나**에 전부 그린다. 같은 숫자 글자는 한 번만 잰다([GamesRummyTilePainter]) · 그림자는 한 겹 윤곽(흐림 없음).
//   ② **밀기는 다시 그리지 않는다.** 층을 캔버스 전체 크기(+ 손잡이 자리)로 한 번 그려 두고 graphicsLayer 로 옮긴다 — 보기는 그리기 단계 밖(층 단계)에서만 읽는다.
//   ③ **핀치도 프레임마다 다시 그리지 않는다.** 그린 배율(renderScale)은 두고 층을 키운 뒤, 손을 떼면 그 배율로 또렷하게 다시 그린다.
//   ④ **끌기 중에는 안 다시 그린다.** 손가락 자리는 떠 있는 타일 층만 읽고, 판 층 입력은 끌기가 시작 · 끝날 때만 바뀐다. 자석 · 캐럿 · 점선은 이 층 위의 따로 된 층이다.
//   ⑤ **판 변화 모션**(설계서 §7)은 움직이는 칸만 판 층에서 비우고 위 층 Canvas 에 그린다 — 옮기는 동안 판 층은 안 다시 그린다. 동작 줄이기 · 끄는 중엔 없다.
// 타일 모양 치수는 GamesRummyTile 과 같은 RummyTileSize 에서 나온다(몸체 · 표식 그리기 산식은 GamesRummyTile.kt 와 같은 값 — 그쪽 그리기 함수가 private 이라 여기 한 벌 있다).
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.animation.core.animate
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.rummy.RummyAttachSide
import com.yehsung.aingcheck.core.rules.rummy.RummyBoardMeld
import com.yehsung.aingcheck.core.rules.rummy.RummyBoardPreview
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasPoint
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasRect
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasSize
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasTransform
import com.yehsung.aingcheck.core.rules.rummy.RummyRect
import com.yehsung.aingcheck.core.rules.rummy.RummyTableLayout
import com.yehsung.aingcheck.core.rules.rummy.RummyTilePalette
import com.yehsung.aingcheck.core.rules.rummy.RummyTileSize
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.ui.games.minigame.canvasFont
import com.yehsung.aingcheck.ui.games.minigame.kit.TNUM
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingMotion
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

// MARK: - 타일 그리기

/** Canvas 안 타일 한 장 그리기 — 한 크기에 하나. 같은 숫자 글자 · 몸체 붓을 한 번만 만든다. [size] 는 dp. */
@Stable
internal class GamesRummyTilePainter(
    private val measurer: TextMeasurer,
    private val fontFamily: FontFamily?,
    private val density: Density,
    size: RummyCanvasSize,
) {
    private val metrics = RummyTileSize(size)
    private val width = (size.width * density.density).toFloat()
    private val height = (size.height * density.density).toFloat()
    private val bevel = (metrics.bevel * density.density).toFloat()
    private val bodyHeight = (height - bevel).coerceAtLeast(1f)
    private val corner = CornerRadius((metrics.corner * density.density).toFloat())
    private val hairline = 0.8f * density.density
    private val bodyBrush = Brush.verticalGradient(listOf(rummyColor(RummyTilePalette.bodyTop), rummyColor(RummyTilePalette.bodyBottom)), endY = bodyHeight)
    private val numbers = HashMap<Long, TextLayoutResult>()

    private fun number(value: Long): TextLayoutResult = numbers.getOrPut(value) {
        // dp → sp: 시스템 글자 크기를 무시한다(타일 안에 들어가야 한다).
        val font = with(density) { metrics.numberFont.dp.toSp() }
        measurer.measure(
            value.toString(),
            TextStyle(fontFamily = fontFamily, fontSize = font, fontWeight = FontWeight.Black, fontFeatureSettings = TNUM),
            softWrap = false,
            maxLines = 1,
        )
    }

    /** 왼쪽 위 [x] · [y](px)에 그린다. [alpha] 는 묶음 옮기기 · 끌려 나간 자리의 흐림. */
    fun paint(scope: DrawScope, face: RummyFace, x: Float, y: Float, joker: ImageBitmap?, highlighted: Boolean = false, lifted: Color? = null, alpha: Float = 1f) {
        scope.translate(x, y) {
            drawRoundRect(Color.Black, topLeft = Offset(0f, hairline), size = Size(width, height), cornerRadius = corner, alpha = 0.28f * alpha)
            drawRoundRect(rummyColor(RummyTilePalette.bevel), size = Size(width, height), cornerRadius = corner, alpha = alpha)
            drawRoundRect(bodyBrush, size = Size(width, bodyHeight), cornerRadius = corner, alpha = alpha)
            val color = face.color
            val value = face.number
            if (color != null && value != null) paintNumber(this, value, color, alpha) else paintJoker(this, joker, alpha)
            if (highlighted) ring(this, rummyColor(RummyTilePalette.highlight), maxOf(1.5f * density.density, width * 0.06f), alpha)
            if (lifted != null) ring(this, lifted, 2f * density.density, alpha)
        }
    }

    private fun ring(scope: DrawScope, color: Color, stroke: Float, alpha: Float) {
        val out = stroke / 2
        scope.drawRoundRect(
            color,
            topLeft = Offset(-out, -out),
            size = Size(width + stroke, height + stroke),
            cornerRadius = CornerRadius(corner.x + out),
            alpha = alpha,
            style = Stroke(stroke),
        )
    }

    private fun paintNumber(scope: DrawScope, value: Long, color: Long, alpha: Float) {
        val d = density.density
        val layout = number(value)
        val ink = rummyColor(RummyTilePalette.ink(color))
        val line = (metrics.numberFont * 1.12 * d).toFloat()
        val spacing = (metrics.stackSpacing * d).toFloat()
        val mark = (metrics.markSize * d).toFloat()
        val start = maxOf((metrics.topPadding * d * 0.5).toFloat(), (bodyHeight - line - spacing - mark) / 2)
        scope.drawText(
            layout,
            color = ink,
            topLeft = Offset((width - layout.size.width) / 2, start + (line - layout.size.height) / 2),
            alpha = alpha,
        )
        scope.translate((width - mark) / 2, start + line + spacing) { drawTileMark(this, color.toInt(), mark, ink, alpha) }
    }

    /** ●▲■◆ — GamesRummyTile 과 같은 도형. */
    private fun drawTileMark(scope: DrawScope, colorIndex: Int, side: Float, ink: Color, alpha: Float) {
        when (colorIndex) {
            0 -> scope.drawCircle(ink, radius = side / 2, center = Offset(side / 2, side / 2), alpha = alpha)
            1 -> scope.drawPath(Path().apply { moveTo(side / 2, 0f); lineTo(side, side); lineTo(0f, side); close() }, ink, alpha = alpha)
            2 -> scope.drawRect(ink, topLeft = Offset(side * 0.06f, side * 0.06f), size = Size(side * 0.88f, side * 0.88f), alpha = alpha)
            else -> scope.drawPath(Path().apply { moveTo(side / 2, 0f); lineTo(side, side / 2); lineTo(side / 2, side); lineTo(0f, side / 2); close() }, ink, alpha = alpha)
        }
    }

    private fun paintJoker(scope: DrawScope, joker: ImageBitmap?, alpha: Float) {
        val d = density.density
        val side = width * 0.76f
        val dot = maxOf(2f * d, width * 0.1f)
        val spacing = (metrics.stackSpacing * d).toFloat()
        val start = maxOf(0f, (bodyHeight - side - spacing - dot) / 2)
        val left = (width - side) / 2
        if (joker != null) {
            scope.drawImage(
                joker,
                dstOffset = IntOffset(left.roundToInt(), start.roundToInt()),
                dstSize = IntSize(side.roundToInt(), side.roundToInt()),
                alpha = alpha,
                filterQuality = FilterQuality.Medium,
            )
        } else {
            scope.drawCircle(rummyColor(RummyTilePalette.jokerFallback), radius = side / 2, center = Offset(left + side / 2, start + side / 2), alpha = alpha)
        }
        val gap = maxOf(1f * d, dot * 0.38f)
        val inks = RummyTilePalette.inks
        val total = dot * inks.size + gap * (inks.size - 1)
        inks.forEachIndexed { index, ink ->
            scope.drawCircle(
                rummyColor(ink),
                radius = dot / 2,
                center = Offset((width - total) / 2 + index * (dot + gap) + dot / 2, start + side + spacing + dot / 2),
                alpha = alpha,
            )
        }
    }
}

/** 크기별 붓 묶음 — 크기가 자꾸 바뀌지는 않는다(판 배율 · 받침대 · 들어 올림). 넘치면 비운다. */
@Stable
internal class GamesRummyTilePainters(private val measurer: TextMeasurer, private val fontFamily: FontFamily?, private val density: Density) {
    private val painters = HashMap<RummyCanvasSize, GamesRummyTilePainter>()

    fun of(size: RummyCanvasSize): GamesRummyTilePainter {
        if (painters.size > 12) painters.clear()
        return painters.getOrPut(size) { GamesRummyTilePainter(measurer, fontFamily, density, size) }
    }
}

@Composable
internal fun rememberGamesRummyTilePainters(): GamesRummyTilePainters {
    val measurer = rememberTextMeasurer()
    val font = canvasFont()
    val density = LocalDensity.current
    return remember(measurer, font, density) { GamesRummyTilePainters(measurer, font, density) }
}

// MARK: - 판 칸

/** 묶음 상자 · 타일 · 손잡이 층의 값 — 좌표 = 논리 좌표 × 배율 + [bleed]. */
internal object GamesRummyBoardLayer {
    /** 캔버스 바깥 여백(왼끝 묶음의 손잡이 · 이번 차례 링이 잘리지 않게). */
    const val bleed: Double = 44.0
}

/** 판 칸 — 펠트 · 판 층(옮기기만) · 미리보기 층. 칸 크기는 부르는 쪽이 정하고 [GamesRummyMatchModel.viewport] 를 그린다. */
@Composable
internal fun GamesRummyTablePane(model: GamesRummyMatchModel, scene: GamesRummyBoardScene, editable: Boolean, modifier: Modifier = Modifier, reduceMotion: Boolean = false) {
    val summary = GamesRummyMatchText.boardSummary(scene.melds.size, scene.tileCount)
    val motion = rememberGamesRummyBoardMotion(model, scene.melds, reduceMotion)
    Box(
        modifier
            .clip(RoundedCornerShape(14.dp))
            .semantics { contentDescription = summary },
    ) {
        GamesRummyTableSurface(Modifier.fillMaxSize(), cornerRadius = 14.dp)
        GamesRummyBoardCanvas(model, scene, editable, motion?.motion?.hidden ?: emptySet())
        if (motion != null) GamesRummyBoardMotionCanvas(model, motion, Modifier.fillMaxSize().testTag(GamesRummyMatchTags.BOARD_MOTION))
        GamesRummyPreviewCanvas(model, scene, Modifier.fillMaxSize())
    }
}

/** 판 변화 한 번을 그리는 값 — 진행도는 그리기 단계에서만 읽는다. */
@Stable
private class GamesRummyBoardMotionRun(val motion: GamesRummyBoardMotion, val progress: Animatable<Float, AnimationVector1D>)

/** 앞 판을 기억해 두는 자리. 그리는 값이 아니라 상태가 아니다. */
private class GamesRummyBoardMotionTracker(var melds: List<RummyBoardMeld>)

/**
 * 판이 바뀌었다 — 움직인 타일을 옛 자리에 세웠다가 새 자리로 보낸다(맥 slide 와 같은 스프링). 끝나면 판 층이 다시 그린다. 끄는 중 · 동작 줄이기면 없다.
 * **조립 중에** 옛 판 → 새 판을 잰다 — 효과까지 미루면 새 자리를 한 프레임 보였다가 옛 자리로 돌아간다. 손가락 · 놓은 기록은 관찰 값이 아니라 끄는 동안 이 자리가 다시 돌지 않는다.
 * 효과의 열쇠는 이 모션 값이고 효과는 끝났다는 표시만 쓴다(재생성 고리 없음).
 */
@Composable
private fun rememberGamesRummyBoardMotion(model: GamesRummyMatchModel, melds: List<RummyBoardMeld>, reduceMotion: Boolean): GamesRummyBoardMotionRun? {
    val tracker = remember { GamesRummyBoardMotionTracker(melds) }
    val motion = remember(melds) {
        val old = tracker.melds
        tracker.melds = melds
        if (reduceMotion || model.machine.drag != null) null else GamesRummyBoardMotion.make(old, melds, model.recentDropIDs)
    }
    val run = remember(motion) { motion?.let { GamesRummyBoardMotionRun(it, Animatable(0f)) } }
    var finished by remember { mutableStateOf<GamesRummyBoardMotionRun?>(null) }
    LaunchedEffect(run) {
        if (run == null) return@LaunchedEffect
        run.progress.animateTo(1f, GamesRummySpring.board())
        finished = run
    }
    return run.takeIf { it !== finished }
}

/** 움직이는 타일만 — 많아야 GamesRummyBoardMotion.maxMoves 장. 판 층과 같은 붓 · 같은 크기 값. */
@Composable
private fun GamesRummyBoardMotionCanvas(model: GamesRummyMatchModel, run: GamesRummyBoardMotionRun, modifier: Modifier) {
    val painters = rememberGamesRummyTilePainters()
    val joker = LocalGamesRummyArt.current?.joker
    Canvas(modifier.clearAndSetSemantics { }) {
        val transform = model.viewport.transform
        val tileW = RummyTableLayout.tileWidth.toDouble() * transform.scale
        val tileH = RummyTableLayout.tileHeight.toDouble() * transform.scale
        val inset = maxOf(1.0, tileW * 0.05)
        val painter = painters.of(RummyCanvasSize(tileW - inset, tileH - inset))
        val progress = run.progress.value.toDouble()
        for (move in run.motion.moves) {
            val at = transform.toScreen(move.at(progress))
            painter.paint(
                this,
                move.face,
                ((at.x + inset / 2) * density).toFloat(),
                ((at.y + inset / 2) * density).toFloat(),
                joker,
                highlighted = move.highlighted,
            )
        }
    }
}

/**
 * 묶음 · 타일 · 손잡이 Canvas 한 장. 그리는 동안 [GamesRummyMatchModel.renderScale] · 끌기 값만 읽고 보기는 층 단계에서만 읽는다(밀기 · 핀치에 다시 안 그린다).
 * [editable] 이면 손잡이를 그린다 — 읽기 전용 판(결과 최종 판 · 남의 차례)은 그리지 않는다. [hidden] = 판 변화 모션이 위 층에 대신 그리는 칸.
 */
@Composable
internal fun GamesRummyBoardCanvas(model: GamesRummyMatchModel, scene: GamesRummyBoardScene, editable: Boolean, hidden: Set<GamesRummyBoardMotion.Slot> = emptySet()) {
    val painters = rememberGamesRummyTilePainters()
    val joker = LocalGamesRummyArt.current?.joker
    val renderScale = model.renderScale
    val canvas = RummyCanvasTransform.canvas
    val bleed = GamesRummyBoardLayer.bleed
    val accent = AingTheme.colors.accent
    Canvas(
        Modifier
            .wrapContentSize(Alignment.TopStart, unbounded = true)
            .size((canvas.width * renderScale + bleed * 2).dp, (canvas.height * renderScale + bleed * 2).dp)
            .graphicsLayer {
                // 층 단계에서만 보기를 읽는다 — 밀어도 아래 그리기는 안 돈다.
                val view = model.viewport
                val ratio = view.scale / renderScale
                val origin = view.transform.toScreen(RummyCanvasPoint(0.0, 0.0))
                transformOrigin = TransformOrigin(0f, 0f)
                scaleX = ratio.toFloat()
                scaleY = ratio.toFloat()
                translationX = ((origin.x - bleed * ratio) * density).toFloat()
                translationY = ((origin.y - bleed * ratio) * density).toFloat()
            }
            .testTag(GamesRummyMatchTags.BOARD_LAYER),
    ) {
        drawBoard(scene.melds, renderScale, editable, painters, joker, model.draggingIDs, model.lift, model.movingSet, accent, hidden)
    }
}

private fun DrawScope.drawBoard(
    melds: List<RummyBoardMeld>,
    scale: Double,
    editable: Boolean,
    painters: GamesRummyTilePainters,
    joker: ImageBitmap?,
    dimmed: Set<Int>,
    lift: GamesRummyLift?,
    movingSet: Int?,
    accent: Color,
    hidden: Set<GamesRummyBoardMotion.Slot>,
) {
    val px = density.toDouble()
    val bleed = GamesRummyBoardLayer.bleed
    val tileW = RummyTableLayout.tileWidth.toDouble() * scale
    val tileH = RummyTableLayout.tileHeight.toDouble() * scale
    val inset = maxOf(1.0, tileW * 0.05)
    val pad = maxOf(2.0, 3 * scale)
    val painter = painters.of(RummyCanvasSize(tileW - inset, tileH - inset))
    val invalid = rummyColor(RummyTilePalette.invalid)
    val lifted = if (lift?.surface == GamesRummySurface.board) lift.ids.toSet() else emptySet()
    fun sx(logical: Long): Float = ((logical.toDouble() * scale + bleed) * px).toFloat()
    // 묶음 상자.
    melds.forEachIndexed { index, meld ->
        val alpha = if (movingSet == index) 0.35f else 1f
        val frame = meld.frame
        val left = sx(frame.x) - (pad * px).toFloat()
        val top = sx(frame.y) - (pad * px).toFloat()
        val box = Size(((frame.width.toDouble() * scale + pad * 2) * px).toFloat(), ((frame.height.toDouble() * scale + pad * 2) * px).toFloat())
        val radius = CornerRadius((pad * 2 * px).toFloat())
        drawRoundRect(if (meld.invalid) invalid else Color.Black, Offset(left, top), box, radius, alpha = (if (meld.invalid) 0.16f else 0.18f) * alpha)
        drawRoundRect(
            if (meld.invalid) invalid else Color.White,
            Offset(left, top),
            box,
            radius,
            style = Stroke((if (meld.invalid) 2f else 1f) * density),
            alpha = (if (meld.invalid) 1f else 0.08f) * alpha,
        )
    }
    // 타일.
    melds.forEachIndexed { index, meld ->
        val left = sx(meld.frame.x)
        val top = sx(meld.frame.y)
        meld.tiles.forEachIndexed { slot, tile ->
            val id = tile.id
            val isLifted = id != null && id in lifted
            val alpha = when {
                movingSet == index -> 0.35f
                id != null && id in dimmed -> 0.28f
                else -> 1f
            }
            if (hidden.isEmpty() || GamesRummyBoardMotion.Slot(index, slot) !in hidden) {
                painter.paint(
                    this,
                    tile.face,
                    left + ((slot * tileW + inset / 2) * px).toFloat(),
                    top + ((inset / 2 - if (isLifted) 4.0 else 0.0) * px).toFloat(),
                    joker,
                    highlighted = tile.highlighted,
                    lifted = if (isLifted) accent else null,
                    alpha = alpha,
                )
            }
        }
    }
    if (!editable) return
    // 손잡이(내 차례).
    val width = maxOf(8.0, 10 * scale)
    melds.forEachIndexed { index, meld ->
        val alpha = if (movingSet == index) 0.35f else 1f
        val frameHeight = meld.frame.height.toDouble() * scale
        val barLeft = ((meld.frame.x.toDouble() * scale + bleed - maxOf(9.0, 13 * scale)) * px).toFloat()
        val barTop = ((meld.frame.y.toDouble() * scale + bleed + frameHeight * 0.07) * px).toFloat()
        val bar = Size((width * px).toFloat(), (frameHeight * 0.86 * px).toFloat())
        val capsule = CornerRadius(bar.width / 2)
        drawRoundRect(Color(0.55f, 0.45f, 1.0f), Offset(barLeft, barTop), bar, capsule, alpha = 0.55f * alpha)
        drawRoundRect(Color.White, Offset(barLeft, barTop), bar, capsule, style = Stroke(0.8f * density), alpha = 0.25f * alpha)
        val dot = maxOf(2.5, width * 0.36) * px
        val gap = maxOf(2.0, frameHeight * 0.08) * px
        for (step in -1..1) {
            drawCircle(
                Color.White,
                radius = (dot / 2).toFloat(),
                center = Offset(barLeft + bar.width / 2, barTop + bar.height / 2 + step * (dot + gap).toFloat()),
                alpha = 0.75f * alpha,
            )
        }
    }
}

// MARK: - 놓기 미리보기

/** 자석 · 끼울 자리 캐럿 · 새 묶음 점선 · 맞는 세트 체크(맥 previewUnder · previewOver). 판 층 위 따로 된 층이라 놓을 자리가 바뀌어도 타일을 다시 안 그린다. 보기 · 미리보기는 그리기 단계에서만 읽는다. */
@Composable
private fun GamesRummyPreviewCanvas(model: GamesRummyMatchModel, scene: GamesRummyBoardScene, modifier: Modifier) {
    val colors = AingTheme.colors
    val accent = colors.accent
    val working = colors.working
    Canvas(modifier.clearAndSetSemantics { }) {
        val preview = model.boardPreview ?: return@Canvas
        drawBoardPreview(preview, scene.melds, model.viewport.transform, accent, working)
    }
}

/** 값이 어떤 사각형이든 dp → px. */
private fun RummyCanvasRect.topLeftPx(density: Float, grow: Double = 0.0): Offset = Offset(((x - grow) * density).toFloat(), ((y - grow) * density).toFloat())

private fun RummyCanvasRect.sizePx(density: Float, grow: Double = 0.0): Size = Size(((width + grow * 2) * density).toFloat(), ((height + grow * 2) * density).toFloat())

private fun DrawScope.drawBoardPreview(preview: RummyBoardPreview, melds: List<RummyBoardMeld>, transform: RummyCanvasTransform, accent: Color, working: Color) {
    val pad = maxOf(2.0, 3 * transform.scale)
    fun tint(valid: Boolean): Color = if (valid) working else accent
    fun dashed(rect: RummyRect, color: Color, fill: Float, grow: Double) {
        val frame = transform.rect(rect)
        val corner = CornerRadius((6 * maxOf(transform.scale, 0.6) * density).toFloat())
        drawRoundRect(color, frame.topLeftPx(density, grow), frame.sizePx(density, grow), corner, alpha = fill)
        drawRoundRect(
            color,
            frame.topLeftPx(density, grow),
            frame.sizePx(density, grow),
            corner,
            style = Stroke(2f * density, pathEffect = PathEffect.dashPathEffect(floatArrayOf(5f * density, 4f * density))),
        )
    }
    val target = preview.targetSet
    if (target != null && target in melds.indices) {
        val frame = transform.rect(melds[target].frame)
        drawRoundRect(
            tint(preview.completes),
            frame.topLeftPx(density, pad),
            frame.sizePx(density, pad),
            CornerRadius((pad * 2 * density).toFloat()),
            style = Stroke(2f * density),
        )
    }
    when (preview) {
        is RummyBoardPreview.Ghost -> dashed(preview.rect, accent, 0.16f, 2.0)
        is RummyBoardPreview.Attach -> {
            val color = tint(preview.valid)
            dashed(preview.slots, color, 0.2f, 1.0)
            val frame = transform.rect(preview.slots)
            // 자석은 실제 이음 자리(블록 칸의 대상 쪽 끝)에. 배지는 이음 위 — 맨 윗줄 묶음이면 칸 위로 잘리니 아래로 내린다.
            val badge = maxOf(18.0, 26 * transform.scale)
            val seamX = transform.toScreen(RummyCanvasPoint((preview.magnetSeamX ?: preview.slots.x).toDouble(), 0.0)).x
            drawMagnetSeam(color, seamX, frame.midY, frame.height + pad * 2 + 6, preview.side, badge, badgeBelow = frame.y - pad - badge < 0)
            if (preview.valid) drawCheckBadge(transform, preview.landing, pad, working)
        }
        is RummyBoardPreview.Insert -> {
            val color = tint(preview.valid)
            dashed(preview.landing, color, 0.1f, pad + 3)
            if (preview.set in melds.indices) {
                val frame = transform.rect(melds[preview.set].frame)
                val x = transform.toScreen(RummyCanvasPoint(preview.caretX.toDouble(), 0.0)).x
                drawInsertCaret(color, x, frame.midY, frame.height + pad * 2 + 8)
            }
            if (preview.valid) drawCheckBadge(transform, preview.landing, pad, working)
        }
    }
}

/** 끼울 자리 캐럿 — 타일 사이에 서는 세로 막대(위아래 둥근 머리). 값은 dp. */
private fun DrawScope.drawInsertCaret(color: Color, x: Double, y: Double, height: Double) {
    val cx = (x * density).toFloat()
    val cy = (y * density).toFloat()
    val half = (height / 2 * density).toFloat()
    val bar = 4f * density
    val head = 4.5f * density
    drawRoundRect(color, Offset(cx - bar / 2, cy - half + head), Size(bar, (half - head) * 2), CornerRadius(bar / 2))
    drawCircle(color, radius = head, center = Offset(cx, cy - half + head))
    drawCircle(color, radius = head, center = Offset(cx, cy + half - head))
    val core = 1.4f * density
    drawRoundRect(Color.White, Offset(cx - core / 2, cy - half + head * 2), Size(core, (half - head * 2) * 2), CornerRadius(core / 2), alpha = 0.7f)
}

/** 붙을 끝 자석 — 이음 막대 + 말굽 배지(열린 쪽이 블록이 붙는 쪽). 값은 dp. */
private fun DrawScope.drawMagnetSeam(color: Color, x: Double, y: Double, height: Double, side: RummyAttachSide, badge: Double, badgeBelow: Boolean) {
    val cx = (x * density).toFloat()
    val cy = (y * density).toFloat()
    val half = (height / 2 * density).toFloat()
    val bar = 5f * density
    drawRoundRect(color, Offset(cx - bar / 2, cy - half), Size(bar, half * 2), CornerRadius(bar / 2))
    val d = (badge * density).toFloat()
    val by = cy + (half + d * 0.3f) * (if (badgeBelow) 1f else -1f)
    drawCircle(color, radius = d / 2, center = Offset(cx, by))
    drawCircle(Color.White, radius = d / 2, center = Offset(cx, by), alpha = 0.9f, style = Stroke(1.2f * density))
    // 말굽 — 열린 쪽이 붙는 쪽. 다리 둘과 반대쪽 굽(회전 없이 가로로 눕혀 그린다).
    val arm = d * 0.26f
    val open = if (side == RummyAttachSide.right) 1f else -1f
    val path = Path().apply {
        moveTo(cx + open * arm, by - arm * 0.8f)
        lineTo(cx - open * arm * 0.2f, by - arm * 0.8f)
        quadraticTo(cx - open * arm * 1.2f, by, cx - open * arm * 0.2f, by + arm * 0.8f)
        lineTo(cx + open * arm, by + arm * 0.8f)
    }
    drawPath(path, Color.White, style = Stroke(d * 0.15f))
}

/** 놓으면 맞는 세트가 된다 — 놓은 뒤 묶음 오른쪽 위 초록 체크. */
private fun DrawScope.drawCheckBadge(transform: RummyCanvasTransform, landing: RummyRect, pad: Double, working: Color) {
    val frame = transform.rect(landing)
    val d = (maxOf(14.0, 18 * transform.scale) * density).toFloat()
    val cx = ((frame.maxX + pad) * density).toFloat()
    val cy = ((frame.y - pad) * density).toFloat()
    drawCircle(working, radius = d / 2, center = Offset(cx, cy))
    drawCircle(Color.White, radius = d / 2, center = Offset(cx, cy), alpha = 0.85f, style = Stroke(1.2f * density))
    val path = Path().apply {
        moveTo(cx - d * 0.24f, cy + d * 0.02f)
        lineTo(cx - d * 0.06f, cy + d * 0.2f)
        lineTo(cx + d * 0.26f, cy - d * 0.18f)
    }
    drawPath(path, Color.Black, alpha = 0.8f, style = Stroke(d * 0.14f))
}

// MARK: - 판 위 조작

/**
 * [전체 보기] 토글 · 화면 밖 묶음 배지. 입력 층 **위**에 있어 제스처보다 먼저 눌린다. 끄는 동안은 숨는다(자동 밀기 · 미리보기를 가리지 않게).
 * 보기를 파생값으로만 읽는다 — 밀 때마다 다시 조립하지 않고, 값(배지 수 · 전체 보기 여부)이 바뀔 때만 돈다.
 */
@Composable
internal fun GamesRummyTableControls(model: GamesRummyMatchModel, frames: List<RummyRect>, reduceMotion: Boolean, modifier: Modifier = Modifier, badgeLift: Int = 36) {
    val counts by remember(model, frames) { derivedStateOf { model.viewport.offscreenCounts(frames) } }
    val isFull by remember(model) { derivedStateOf { model.viewport.isFullView } }
    val dragging by remember(model) { derivedStateOf { model.draggingIDs.isNotEmpty() } }
    val scope = rememberCoroutineScope()
    fun reveal(side: GamesRummySide) {
        val from = model.viewport
        val to = from.revealed(side, frames)
        if (reduceMotion) {
            model.reveal(side, frames)
            return
        }
        scope.launch {
            animate(0f, 1f, animationSpec = AingMotion.move<Float>(AingMotion.MEDIUM_MS)) { value, _ ->
                model.showRevealStep(from, to, value.toDouble())
            }
        }
    }
    Box(modifier) {
        if (dragging) return@Box
        // 기호만 — 글자까지 넣으니 판 오른쪽 위 묶음의 숫자를 석 장씩 가렸다(iOS 실화면).
        Box(
            Modifier.align(Alignment.TopEnd).padding(4.dp).size(44.dp)
                .clickable(role = Role.Button) { model.toggleFullView() }
                .semantics { contentDescription = if (isFull) RummyPhoneText.zoomIn else RummyPhoneText.zoomOut }
                .testTag(GamesRummyMatchTags.ZOOM),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                Modifier.size(30.dp).background(Color.Black.copy(alpha = 0.62f), CircleShape).border(0.8.dp, Color.White.copy(alpha = 0.25f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                AingIcon(if (isFull) AppIcon.Add else AppIcon.Remove, contentDescription = null, size = 18.dp, tint = Color.White)
            }
        }
        // 배지는 판 아래쪽 — 묶음은 위부터 깔리니 숫자를 덜 가린다(직전 사건 줄보다는 위).
        if (counts.left > 0) {
            OffscreenBadge(GamesRummySide.left, counts.left, { reveal(GamesRummySide.left) }, Modifier.align(Alignment.BottomStart).padding(bottom = badgeLift.dp))
        }
        if (counts.right > 0) {
            OffscreenBadge(GamesRummySide.right, counts.right, { reveal(GamesRummySide.right) }, Modifier.align(Alignment.BottomEnd).padding(bottom = badgeLift.dp))
        }
    }
}

@Composable
private fun OffscreenBadge(side: GamesRummySide, count: Int, onClick: () -> Unit, modifier: Modifier) {
    val colors = AingTheme.colors
    val label = if (side == GamesRummySide.left) RummyPhoneText.offscreenLeft(count) else RummyPhoneText.offscreenRight(count)
    Box(
        modifier
            .heightIn(min = 44.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label }
            .testTag(if (side == GamesRummySide.left) GamesRummyMatchTags.OFFSCREEN_LEFT else GamesRummyMatchTags.OFFSCREEN_RIGHT)
            .padding(horizontal = 5.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            Modifier.height(26.dp).background(colors.accentFill, CircleShape).border(1.dp, Color.White.copy(alpha = 0.55f), CircleShape).padding(horizontal = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            if (side == GamesRummySide.left) AingIcon(AppIcon.ArrowLeftFill, contentDescription = null, size = 14.dp, tint = colors.onAccentFill)
            Text(count.toString(), style = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = TNUM), color = colors.onAccentFill, maxLines = 1)
            if (side == GamesRummySide.right) AingIcon(AppIcon.ArrowRightFill, contentDescription = null, size = 14.dp, tint = colors.onAccentFill)
        }
    }
}

// MARK: - 손에 든 타일

/**
 * 손에 든 타일 — **이 층만 손가락 자리를 읽는다**(그리기 단계에서 [GamesRummyMatchModel.drag]). 받침대 · 판은 손이 움직여도 다시 안 그려진다.
 * 아래 놓을 자리 점선이 비쳐 보이게 0.82(1.25 배라 점선이 타일 뒤에 다 숨는다).
 */
@Composable
internal fun GamesRummyFloatingBlock(model: GamesRummyMatchModel, modifier: Modifier = Modifier) {
    val painters = rememberGamesRummyTilePainters()
    val joker = LocalGamesRummyArt.current?.joker
    val measurer = rememberTextMeasurer()
    val font = canvasFont()
    val accentFill = AingTheme.colors.accentFill
    val onAccent = AingTheme.colors.onAccentFill
    Canvas(modifier.clearAndSetSemantics { }) {
        val drag = model.drag ?: return@Canvas
        val base = model.currentContext ?: return@Canvas
        val context = base.with(model.viewport)
        val tile = GamesRummyFloatingLayout.tileSize(drag, context)
        val frames = GamesRummyFloatingLayout.frames(drag, tile, context.viewport.scale)
        val first = frames.firstOrNull() ?: return@Canvas
        val painter = painters.of(RummyCanvasSize(first.width, first.height))
        drag.tiles.forEachIndexed { index, each ->
            val frame = frames[index]
            painter.paint(this, each.face, (frame.x * density).toFloat(), (frame.y * density).toFloat(), joker, alpha = 0.82f)
        }
        val last = frames.last()
        val corner = Offset((last.maxX * density).toFloat(), (last.y * density).toFloat())
        if (model.hoverRefused) {
            drawRefusedMark(corner)
        } else if (drag.tiles.size > 1) {
            drawCountBadge(corner, drag.tiles.size, measurer, font, accentFill, onAccent)
        }
    }
}

/** 놓기 거절 표시(R-14) — 흰 바탕 위 빨간 금지 표시. */
private fun DrawScope.drawRefusedMark(center: Offset) {
    val radius = 10f * density
    val invalid = rummyColor(RummyTilePalette.invalid)
    drawCircle(Color.White, radius = radius, center = center)
    drawCircle(invalid, radius = radius * 0.8f, center = center, style = Stroke(2.5f * density))
    val arm = radius * 0.56f
    drawLine(invalid, Offset(center.x - arm, center.y - arm), Offset(center.x + arm, center.y + arm), strokeWidth = 2.5f * density)
}

/** 집은 장수 배지. */
private fun DrawScope.drawCountBadge(center: Offset, count: Int, measurer: TextMeasurer, font: FontFamily?, fill: Color, ink: Color) {
    val radius = 10f * density
    drawCircle(fill, radius = radius, center = center)
    drawCircle(Color.White, radius = radius, center = center, alpha = 0.9f, style = Stroke(1.5f * density))
    val layout = measurer.measure(
        count.toString(),
        TextStyle(fontFamily = font, fontSize = 11.dp.toSp(), fontWeight = FontWeight.Black, fontFeatureSettings = TNUM),
        maxLines = 1,
    )
    drawText(layout, color = ink, topLeft = Offset(center.x - layout.size.width / 2f, center.y - layout.size.height / 2f))
}
