// 원본: Sources/CheckMobileKit/Games/GamesRummyRackView.swift:1 @ ios-1017-cube 614d98bd · 맥 Sources/check/RummyRackView.swift:90 (RummyRackView) · Sources/check/RummyRackCues.swift:59,117 (밑줄 띠 · 빛) @ 1a5eeca6 · 설계서 §4 ⑤
//
// 폰 아잉 큐브 받침대(입력은 없다 — 손은 화면 전체 입력 층 하나가 받는다). 자리는 코어 RummyRackGeometry.phone 한 벌에서 나온다.
// **받침대 그림(rummy-rack)을 판 화면에 깔지 않는다**(iOS 실화면 결정): 그림의 선반은 높이의 0.44 · 0.76 에 박혀 있어 두 선반 사이가 0.32H 인데, 타일 47 을 그 사이에 세우려면
// 받침대가 155 가 돼야 한다(세로 화면 칸은 118). 깔면 그림 선반이 앞줄 타일 중간을 지나간다 — 그래서 그림 없이 남색 유광 + 분홍 테두리 몸체(GamesRummyRackStand 의 그린 폴백)에 줄마다 선반을 그린다.
// 받침대 타일은 많아야 30장 남짓이라 GamesRummyTile 노드를 그대로 쓴다(판과 다르다 — GamesRummyBoardCanvas 머리말). 면 이름이 그대로 접근성 글자가 된다.
// 모션(설계서 §7): 자리가 바뀌면 미끄러지고(정렬은 25ms 시차) 뽑은 타일은 [뽑기] 자리에서 날아온다. 값은 층 단계에서만 읽어 타일이 움직여도 다시 조립하지 않는다. 동작 줄이기면 바로 제자리다.
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.snap
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasPoint
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasSize
import com.yehsung.aingcheck.core.rules.rummy.RummyRackGeometry
import com.yehsung.aingcheck.core.rules.rummy.RummyRackLayout
import com.yehsung.aingcheck.core.rules.rummy.RummyRackMeld
import com.yehsung.aingcheck.core.rules.rummy.RummyTile
import com.yehsung.aingcheck.core.rules.rummy.RummyTilePalette
import com.yehsung.aingcheck.core.rules.rummy.RummyTileSize
import com.yehsung.aingcheck.ui.games.minigame.canvasFont
import com.yehsung.aingcheck.ui.games.minigame.canvasSp
import com.yehsung.aingcheck.ui.games.minigame.kit.TNUM
import com.yehsung.aingcheck.ui.theme.AingMotion
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/** 받침대 테두리 빛 단계. */
enum class GamesRummyTurnGlowPhase {
    /** 차례가 막 왔다(한 번 크게). */
    pulse,

    /** 그 뒤 차례 내내 은은하게. */
    steady,
}

/**
 * 받침대. [geometry] 는 놓는 판정과 같은 값이고, 끼워 넣기 미리보기가 새 줄을 열면 그리는 기하만 그 줄 수로 줄여 칸 안에 담는다.
 * [freshIDs] = 방금 뽑은 타일(3초 빛남), [turnGlow] = 내 차례 빛(아니면 null).
 * [flight] = 날아오는 뽑기(동작 줄이기면 null) · [flightOrigin] = 그 출발점(받침대 칸 좌표) · [stagger] = 정렬 시차(타일 id → 밀리초).
 */
@Composable
internal fun GamesRummyRackPane(
    model: GamesRummyMatchModel,
    tiles: List<RummyTile>,
    layout: RummyRackLayout,
    geometry: RummyRackGeometry,
    regionWidth: Double,
    regionHeight: Double,
    rackMelds: List<RummyRackMeld>,
    turnGlow: GamesRummyTurnGlowPhase?,
    freshIDs: Set<Int>,
    reduceMotion: Boolean,
    modifier: Modifier = Modifier,
    flight: GamesRummyRackFlight? = null,
    flightOrigin: RummyCanvasPoint = RummyCanvasPoint(0.0, 0.0),
    stagger: Map<Int, Long> = emptyMap(),
) {
    val colors = AingTheme.colors
    val preview = model.rackPreview
    val shown = preview?.layout ?: layout
    val draw = preview?.let { GamesRummyRackDraw.fitted(regionWidth, regionHeight, it.layout.rowCount) } ?: geometry
    val refused = model.hoverRefused || model.refusedFlash
    val lift = model.lift
    val lifted = if (lift?.surface == GamesRummySurface.rack) lift.ids.toSet() else emptySet()
    val dragging = model.draggingIDs
    val keys = remember(tiles) { RummyRackGeometry.motionKeys(tiles) }
    val shape = RoundedCornerShape(14.dp)
    val summary = GamesRummyMatchText.rackSummary(tiles.size)
    Box(modifier.semantics { contentDescription = summary }) {
        // 그림 없이 그린 몸체(머리말) — 이 잎만 그림을 비운다.
        CompositionLocalProvider(LocalGamesRummyArt provides null) {
            GamesRummyRackStand(draw, Modifier.fillMaxSize())
        }
        val ghosts = preview?.ghosts ?: emptyList()
        if (ghosts.isNotEmpty()) {
            val accent = colors.accent
            Canvas(Modifier.fillMaxSize().clearAndSetSemantics { }) {
                val tile = RummyTileSize(draw.tileSize)
                val corner = CornerRadius((tile.corner * density).toFloat())
                for (slot in ghosts) {
                    val frame = draw.frame(slot)
                    val topLeft = Offset((frame.x * density).toFloat(), (frame.y * density).toFloat())
                    val size = Size((frame.width * density).toFloat(), (frame.height * density).toFloat())
                    drawRoundRect(accent, topLeft, size, corner, alpha = 0.18f)
                    drawRoundRect(accent, topLeft, size, corner, style = Stroke(2f * density, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f * density, 3f * density))))
                }
            }
        }
        // 고르기는 고리 밖에서 한다 — 고리 안 continue 는 컴파일러가 바퀴마다 자리 그룹을 씌워, 순서가 바뀌면(정렬) key 가 있어도 상태가 끊겨 타일이 순간 이동한다.
        // 미리보기 동안 끌려 나간 타일은 놓일 자리에 점선이 대신 선다.
        val seated = tiles.filter { tile -> preview == null || tile.id !in dragging }.mapNotNull { tile -> shown.slot(tile.id)?.let { tile to it } }
        for ((tile, slot) in seated) {
            key(keys[tile.id] ?: tile.id.toString()) {
                val frame = draw.frame(slot)
                val metrics = RummyTileSize(RummyCanvasSize(frame.width, frame.height))
                val isLifted = tile.id in lifted
                val isFresh = tile.id in freshIDs && !isLifted
                val ring = RoundedCornerShape((metrics.corner + 1).dp)
                val target = Offset(frame.x.toFloat(), frame.y.toFloat())
                val placement = rememberGamesRummyTilePlacement(
                    target = target,
                    flightStart = Offset((flightOrigin.x - frame.width / 2).toFloat(), (flightOrigin.y - frame.height / 2).toFloat()),
                    flightSerial = flight?.takeIf { tile.id in it.ids }?.serial,
                    delayMillis = stagger[tile.id] ?: 0L,
                    reduceMotion = reduceMotion,
                )
                var place: Modifier = Modifier.rummyTilePlaced(placement, target, if (isLifted) 5f else 0f, reduceMotion)
                if (isLifted) place = place.border(2.dp, colors.accent, ring)
                if (isFresh) place = place.border(2.5.dp, colors.pending, ring)
                GamesRummyTile(tile.face, metrics, place.testTag(GamesRummyMatchTags.rackTile(tile.face.text)), dimmed = tile.id in dragging)
            }
        }
        for (meld in preview?.melds ?: rackMelds) {
            val bar = GamesRummyRackDraw.meldBar(meld, shown, draw) ?: continue
            Box(
                Modifier.offset(bar.x.dp, bar.y.dp).size(bar.width.dp, bar.height.dp).background(colors.working, CircleShape).clearAndSetSemantics { },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    meld.points.toString(),
                    style = TextStyle(fontFamily = canvasFont(), fontSize = canvasSp(9f), fontWeight = FontWeight.Black, fontFeatureSettings = TNUM),
                    color = Color.White,
                    maxLines = 1,
                    softWrap = false,
                )
            }
        }
        if (lifted.size > 1) {
            val frames = tiles.filter { it.id in lifted }.mapNotNull { each -> shown.slot(each.id)?.let(draw::frame) }
            val top = frames.minOfOrNull { it.y }
            val right = frames.filter { it.y == top }.maxOfOrNull { it.maxX }
            if (top != null && right != null) GamesRummyCountBadge(lifted.size, Modifier.offset((right - 6).dp, maxOf(0.0, top - 15).dp))
        }
        if (turnGlow != null && !refused) GamesRummyTurnGlow(turnGlow, reduceMotion, Modifier.fillMaxSize())
        if (refused) Box(Modifier.fillMaxSize().border(3.dp, rummyColor(RummyTilePalette.invalid), shape).testTag(GamesRummyMatchTags.RACK_REFUSED))
    }
}

/** 타일 하나의 움직이는 값. [position] 은 왼쪽 위(받침대 칸 좌표 · dp), [flight] 는 비행 진행도(1 = 내려앉음). */
@Stable
private class GamesRummyTilePlacement(start: Offset, flying: Boolean) {
    val position = Animatable(start, Offset.VectorConverter)
    val flight = Animatable(if (flying) 0f else 1f)

    /** 이 사건을 이미 출발시켰다 — 나는 중에 자리가 또 바뀌어도 버튼 자리로 되돌아가지 않는다. 그리는 값이 아니다. */
    var flownSerial: Int? = null
}

/**
 * 자리가 바뀌면 그쪽으로 움직인다. 효과는 자리 · 사건이 바뀔 때만 돌고 그 값을 쓰지 않는다(재생성 고리 없음).
 * 같은 면의 모션 키가 뽑은 타일로 옮겨 올 수 있어(면 + 같은 면 순번) 처음 조립될 때뿐 아니라 사건이 올 때 출발점으로 세운다.
 */
@Composable
private fun rememberGamesRummyTilePlacement(target: Offset, flightStart: Offset, flightSerial: Int?, delayMillis: Long, reduceMotion: Boolean): GamesRummyTilePlacement {
    val flying = flightSerial != null && !reduceMotion
    val placement = remember { GamesRummyTilePlacement(if (flying) flightStart else target, flying) }
    LaunchedEffect(target, flightSerial, reduceMotion) {
        if (reduceMotion) {
            placement.position.snapTo(target)
            placement.flight.snapTo(1f)
            return@LaunchedEffect
        }
        if (flightSerial != null) {
            if (placement.flownSerial != flightSerial) {
                placement.flownSerial = flightSerial
                placement.position.snapTo(flightStart)
                placement.flight.snapTo(0f)
            }
            launch { placement.flight.animateTo(1f, GamesRummySpring.flight()) }
            placement.position.animateTo(target, GamesRummySpring.flight())
        } else {
            if (placement.flight.value != 1f) launch { placement.flight.animateTo(1f, GamesRummySpring.flight()) }
            if (placement.position.value == target) return@LaunchedEffect
            if (delayMillis > 0) delay(delayMillis)
            placement.position.animateTo(target, GamesRummySpring.slide())
        }
    }
    return placement
}

/** 놓기 — 움직이는 값은 층 단계에서만 읽는다. 동작 줄이기면 제자리 그대로. [lift] = 들어 올림(dp). */
private fun Modifier.rummyTilePlaced(placement: GamesRummyTilePlacement, target: Offset, lift: Float, reduceMotion: Boolean): Modifier =
    offset {
        val at = if (reduceMotion) target else placement.position.value
        IntOffset((at.x * density).roundToInt(), ((at.y - lift) * density).roundToInt())
    }.graphicsLayer {
        if (!reduceMotion) {
            val progress = placement.flight.value
            val scale = GamesRummyRackMotion.flightScale(progress)
            scaleX = scale
            scaleY = scale
            rotationZ = GamesRummyRackMotion.flightDegrees(progress)
        }
    }

/** 받침대 테두리 빛 — 굵기만 움직인다(불투명도를 이징으로 깎지 않는다). 동작 줄이기면 바로 은은한 굵기로. */
@Composable
private fun GamesRummyTurnGlow(phase: GamesRummyTurnGlowPhase, reduceMotion: Boolean, modifier: Modifier) {
    val accent = AingTheme.colors.accent
    val target = if (phase == GamesRummyTurnGlowPhase.pulse) 4.dp else 2.dp
    val width by animateDpAsState(target, if (reduceMotion) snap() else AingMotion.move(700))
    val shape = RoundedCornerShape(14.dp)
    Box(modifier.border(width, accent, shape).border(width + 3.dp, accent.copy(alpha = 0.3f), shape))
}

/** 집은 장수 배지. */
@Composable
private fun GamesRummyCountBadge(count: Int, modifier: Modifier) {
    val colors = AingTheme.colors
    Box(
        modifier.size(20.dp).background(colors.accentFill, CircleShape).border(1.5.dp, Color.White.copy(alpha = 0.9f), CircleShape).clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            count.toString(),
            style = TextStyle(fontFamily = canvasFont(), fontSize = canvasSp(11f), fontWeight = FontWeight.Black, fontFeatureSettings = TNUM),
            color = colors.onAccentFill,
            maxLines = 1,
            softWrap = false,
        )
    }
}
