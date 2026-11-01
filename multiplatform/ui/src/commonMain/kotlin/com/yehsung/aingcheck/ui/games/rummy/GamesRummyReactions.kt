// 원본: Sources/check/RummyReactionOverlay.swift:84 (앵커) · :107 (RummyReactionOverlay) · :293 (RummyReactionButton) · :312 (RummyReactionPicker) @ 1a5eeca6 · Sources/CheckMobileKit/Games/GamesRummyReaction.swift:1 @ ios-1017-cube 614d98bd · 폰 배치는 ios-1017 설계서 §6
//
// 이모티콘 반응. [반응] → 아잉이 이모티콘 여섯 → 보낸 사람 **자리에서** 말풍선 2.5초. 보내기 · 쿨다운(2초) · 내 말풍선 즉시 · 메아리 무시는 코어(`sendReaction` · `reactionFeed`)가 한다. 여기는 그리기만 한다.
//
// ── 말풍선 수명은 시각 비교로만 끝낸다 ──
// **재생성 고리 금지**(맥 0.3.69 CPU 120% — 메모리 swiftui-task-id-identity-loop). 효과의 열쇠는 마지막 반응 번호 하나고 효과는 그 열쇠를 쓰지 않는다. 뷰 정체성도 안 바꾼다.
// 프레임 수는 시작할 때 정해진다([GamesRummyReactionPlan.frameCount]): 마지막 말풍선이 만료되는 프레임 하나 뒤에서 끝나므로, 띄울 것이 없으면 **시계가 스스로 멈춘다**(빈 층이 30fps 로 돌지 않는다).
// 값은 그리는 층에서만 읽는다 — 프레임마다 다시 조립하지 않고 말풍선이 나고 질 때만 조립한다.
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.structuralEqualityPolicy
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasPoint
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasRect
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasSize
import com.yehsung.aingcheck.core.rules.text.AingSticker
import com.yehsung.aingcheck.core.rules.text.AingStickerText
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyReactionEvent
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.canReact
import com.yehsung.aingcheck.core.stores.rummy.sendReaction
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.games.minigame.canvasFont
import com.yehsung.aingcheck.ui.games.minigame.canvasSp
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesSheet
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.session.kit.StickerArtState
import com.yehsung.aingcheck.ui.screens.session.kit.rememberStickerArt
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay
import kotlin.math.ceil

/** 시험 · 계측 꼬리표. */
object GamesRummyReactionTags {
    const val PANEL_BACKDROP: String = "rummy.reaction.panelBackdrop"
    const val BUTTON: String = "rummy.reaction.button"
    const val PICKER: String = "rummy.reaction.picker"

    fun cell(sticker: String): String = "rummy.reaction.cell.$sticker"

    fun bubble(seatNo: Long): String = "rummy.reaction.bubble.$seatNo"
}

/** 반응 글자. 문구 표(RummyPhoneText)에 없는 몫이다. */
object RummyReactionPhoneText {
    const val title: String = "반응 보내기"

    fun accessibility(name: String, sticker: String): String = "${name}님의 반응 $sticker"
}

/** 말풍선의 순수 값 — 언제 보이고 · 어떤 크기 · 투명도이고 · 어디에 서는가. 값 단위는 dp. */
object GamesRummyReactionPlan {
    const val lifetime: Double = 2.5
    const val popIn: Double = 0.22
    const val fadeOut: Double = 0.3

    /** 말풍선 몸 한 변 · 꼬리 길이(상대 카드 폭이 좁아 맥보다 작다). */
    const val bubbleSide: Double = 56.0
    const val tail: Double = 7.0
    const val bubbleHeight: Double = bubbleSide + tail * 2

    /** 프레임 간격 — 30fps 를 올림(프레임 수 × 간격이 남은 시간을 넘게). */
    const val frameMillis: Long = 34L

    /** 보낸 뒤 시계가 잠깐 뒤로 간 말풍선까지 받는 폭. */
    private const val futureSlack: Double = -0.5

    /** 판 화면(가로)은 왼쪽 열 카드의 **오른쪽**으로 — 위아래로 띄우면 옆 카드를 가린다. 결과 화면(세로)은 줄의 위 · 아래다. */
    enum class Side { above, below, trailing }

    /** 지금 보일 말풍선 — 자리마다 가장 최근 것 하나, 받은 지 2.5초 안. 자리 순. */
    fun visible(feed: List<RummyReactionEvent>, now: SwiftDate): List<RummyReactionEvent> {
        val latest = HashMap<Long, RummyReactionEvent>()
        for (event in feed) {
            val age = now.timeIntervalSince(event.receivedAt)
            if (age < futureSlack || age >= lifetime) continue
            val kept = latest[event.seatNo]
            if (kept != null && kept.receivedAt > event.receivedAt) continue
            latest[event.seatNo] = event
        }
        return latest.values.sortedBy { it.seatNo }
    }

    /** 다시 그릴 프레임 수. 마지막 말풍선이 만료되는 프레임 **하나 뒤**에서 끝난다 — 그 프레임이 말풍선을 지우고 시계는 멈춘다. 띄울 것이 없으면 0. */
    fun frameCount(feed: List<RummyReactionEvent>, now: SwiftDate): Int {
        val last = visible(feed, now).maxOfOrNull { it.receivedAt.timeIntervalSinceReferenceDate } ?: return 0
        val remaining = last + lifetime - now.timeIntervalSinceReferenceDate
        if (remaining <= 0) return 0
        return ceil(remaining * 1000.0 / frameMillis.toDouble()).toInt() + 1
    }

    /** 튀어나오기 — 0.22초 동안 0.5 → 1.08 → 1. */
    fun scale(age: Double): Double {
        if (age >= popIn) return 1.0
        val t = maxOf(0.0, age) / popIn - 1.0
        val back = 1 + 2.2 * t * t * t + 1.2 * t * t
        return 0.5 + 0.5 * back
    }

    /** 마지막 0.3초 동안 **선형**으로 사라진다(이징으로 불투명도를 깎지 않는다). */
    fun opacity(age: Double): Double {
        val left = lifetime - age
        if (left >= fadeOut) return 1.0
        return maxOf(0.0, left / fadeOut)
    }

    /** 가로 화면 = 카드 오른쪽. 세로 화면은 자리 위에 설 자리가 없으면 아래로. */
    fun side(rect: RummyCanvasRect, bounds: RummyCanvasSize): Side = when {
        GamesRummyMatchLayout.isLandscape(bounds) -> Side.trailing
        rect.y < bubbleHeight + 8 -> Side.below
        else -> Side.above
    }

    /** 말풍선 중심. 꼬리 끝이 자리에서 3 떨어지고, 흐르는 축은 화면 안으로 들인다. */
    fun center(rect: RummyCanvasRect, side: Side, bounds: RummyCanvasSize): RummyCanvasPoint {
        val half = bubbleHeight / 2
        val inset = half + 2
        val x = minOf(maxOf(rect.midX, inset), maxOf(inset, bounds.width - inset))
        return when (side) {
            Side.above -> RummyCanvasPoint(x, rect.y - 3 - half)
            Side.below -> RummyCanvasPoint(x, rect.maxY + 3 + half)
            Side.trailing -> RummyCanvasPoint(rect.maxX + 3 + half, minOf(maxOf(rect.midY, inset), maxOf(inset, bounds.height - inset)))
        }
    }
}

/** 자리 번호 → 그 자리 사각형(뿌리 좌표, px). 자리를 그리는 뷰가 [rummyReactionAnchor] 로 채우고 말풍선 층이 읽는다. */
@Stable
class GamesRummyReactionAnchors {
    val rects = mutableStateMapOf<Long, Rect>()
}

/** 껍데기 GamesRummyScreen 이 넣는다. */
val LocalGamesRummyReactionAnchors = staticCompositionLocalOf { GamesRummyReactionAnchors() }

/**
 * 이 뷰가 [seatNo] 자리다 — 그 사람의 반응 말풍선이 이 뷰 위에 선다. null 이면 아무것도 안 한다.
 * 뷰가 사라지면 자리를 지운다(결과의 [최종 판] · 방 → 판 전환 뒤 옛 좌표에 말풍선이 뜨지 않게).
 */
fun Modifier.rummyReactionAnchor(anchors: GamesRummyReactionAnchors, seatNo: Long?): Modifier {
    if (seatNo == null) return this
    return composed {
        DisposableEffect(anchors, seatNo) {
            onDispose { anchors.rects.remove(seatNo) }
        }
        Modifier.onGloballyPositioned { coordinates -> anchors.rects[seatNo] = coordinates.boundsInRoot() }
    }
}

/** 말풍선 층 — `rummy.reactionFeed` 를 읽어 보낸 사람 자리에 2.5초. 입력을 막지 않는다. 앵커가 없는 자리의 반응은 그리지 않는다. */
@Composable
fun GamesRummyReactionLayer(rummy: RummyStore, reduceMotion: Boolean, now: () -> SwiftDate, modifier: Modifier = Modifier) {
    GamesRummyReactionOverlay(
        feed = rummy.reactionFeed,
        seatName = { seat -> rummy.match?.seats?.firstOrNull { it.seatNo == seat }?.displayName ?: "?" },
        anchors = LocalGamesRummyReactionAnchors.current,
        reduceMotion = reduceMotion,
        now = now,
        modifier = modifier,
    )
}

/** 층 본체 — 값만 받는다(시험이 스토어 없이 수명을 잰다). */
@Composable
internal fun GamesRummyReactionOverlay(
    feed: List<RummyReactionEvent>,
    seatName: (Long) -> String,
    anchors: GamesRummyReactionAnchors,
    reduceMotion: Boolean,
    now: () -> SwiftDate,
    modifier: Modifier = Modifier,
) {
    // 첫 말풍선 전에 그림을 읽어 둔다 — 말풍선이 빈 판으로 뜨지 않게.
    val art = rememberStickerArt()
    val clock by rememberUpdatedState(now)
    var frameNow by remember { mutableStateOf(now()) }
    // 열쇠는 마지막 반응 번호뿐 · 효과 안에서 열쇠를 안 쓴다 · 정해진 프레임 수에서 끝난다.
    LaunchedEffect(feed.lastOrNull()?.id) {
        frameNow = clock()
        repeat(GamesRummyReactionPlan.frameCount(feed, frameNow)) {
            delay(GamesRummyReactionPlan.frameMillis)
            frameNow = clock()
        }
    }
    val visible by remember(feed) { derivedStateOf(structuralEqualityPolicy()) { GamesRummyReactionPlan.visible(feed, frameNow) } }
    var origin by remember { mutableStateOf(Offset.Zero) }
    var layerSize by remember { mutableStateOf(IntSize.Zero) }
    val density = LocalDensity.current.density
    Box(
        modifier.onGloballyPositioned { coordinates ->
            origin = coordinates.positionInRoot()
            layerSize = coordinates.size
        },
    ) {
        // 고리 안에 continue 를 두지 않는다 — 바퀴마다 자리 그룹이 씌워져 key 가 뜻을 잃는다(GamesRummyRackPane).
        for (event in visible.filter { anchors.rects[it.seatNo]?.isEmpty == false }) {
            val rect = anchors.rects.getValue(event.seatNo)
            val local = RummyCanvasRect(
                ((rect.left - origin.x) / density).toDouble(),
                ((rect.top - origin.y) / density).toDouble(),
                (rect.width / density).toDouble(),
                (rect.height / density).toDouble(),
            )
            key(event.id) {
                GamesRummyReactionBubble(event, seatName(event.seatNo), local, RummyCanvasSize((layerSize.width / density).toDouble(), (layerSize.height / density).toDouble()), art, reduceMotion) { frameNow }
            }
        }
    }
}

/** 말풍선 하나 — 흰 둥근 판 + 자리 쪽 꼬리 + 아잉이 이모티콘(맥 RummyReactionBubbleView 의 그림 값). [frame] 은 그리는 층에서만 읽는다. */
@Composable
private fun GamesRummyReactionBubble(
    event: RummyReactionEvent,
    name: String,
    rect: RummyCanvasRect,
    bounds: RummyCanvasSize,
    art: StickerArtState,
    reduceMotion: Boolean,
    frame: () -> SwiftDate,
) {
    val side = GamesRummyReactionPlan.side(rect, bounds)
    val center = GamesRummyReactionPlan.center(rect, side, bounds)
    val full = GamesRummyReactionPlan.bubbleHeight
    val description = RummyReactionPhoneText.accessibility(name, event.sticker.label)
    val shape = RoundedCornerShape(16.dp)
    Box(
        Modifier
            .offset((center.x - full / 2).dp, (center.y - full / 2).dp)
            .size(full.dp)
            .graphicsLayer {
                val age = maxOf(0.0, frame().timeIntervalSince(event.receivedAt))
                alpha = GamesRummyReactionPlan.opacity(age).toFloat()
                if (!reduceMotion) {
                    val scale = GamesRummyReactionPlan.scale(age).toFloat()
                    scaleX = scale
                    scaleY = scale
                }
                // 튀어나오는 기준점 = 꼬리 끝(자리 쪽).
                transformOrigin = when (side) {
                    GamesRummyReactionPlan.Side.above -> TransformOrigin(0.5f, 1f)
                    GamesRummyReactionPlan.Side.below -> TransformOrigin(0.5f, 0f)
                    GamesRummyReactionPlan.Side.trailing -> TransformOrigin(0f, 0.5f)
                }
            }
            // 꼬리표가 먼저다 — clearAndSetSemantics 뒤에 달면 그 안쪽으로 치여 지워진다.
            .testTag(GamesRummyReactionTags.bubble(event.seatNo))
            .clearAndSetSemantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val tail = (GamesRummyReactionPlan.tail * density).toFloat()
            val half = 7f * density
            val middle = size.width / 2
            val path = Path().apply {
                when (side) {
                    GamesRummyReactionPlan.Side.above -> {
                        moveTo(middle - half, size.height - tail - density)
                        lineTo(middle + half, size.height - tail - density)
                        lineTo(middle, size.height)
                    }
                    GamesRummyReactionPlan.Side.below -> {
                        moveTo(middle - half, tail + density)
                        lineTo(middle + half, tail + density)
                        lineTo(middle, 0f)
                    }
                    GamesRummyReactionPlan.Side.trailing -> {
                        moveTo(tail + density, size.height / 2 - half)
                        lineTo(tail + density, size.height / 2 + half)
                        lineTo(0f, size.height / 2)
                    }
                }
                close()
            }
            drawPath(path, Color.White)
        }
        Box(
            Modifier.size(GamesRummyReactionPlan.bubbleSide.dp).shadow(6.dp, shape).background(Color.White, shape),
            contentAlignment = Alignment.Center,
        ) {
            GamesRummyStickerArt(event.sticker, art, Color.Black.copy(alpha = 0.7f), Modifier.padding(5.dp).fillMaxSize())
        }
    }
}

/** 이모티콘 그림(메시지 이모티콘과 같은 그림). 그림이 없으면 이름 글자. 읽는 중이면 빈 자리. */
@Composable
private fun GamesRummyStickerArt(sticker: AingSticker, art: StickerArtState, ink: Color, modifier: Modifier) {
    val image = (art as? StickerArtState.Ready)?.art?.get(sticker)
    Box(modifier, contentAlignment = Alignment.Center) {
        if (image != null) {
            Image(image, contentDescription = null, modifier = Modifier.fillMaxSize())
        } else if (art is StickerArtState.Ready) {
            Text(
                sticker.label,
                style = TextStyle(fontFamily = canvasFont(), fontSize = canvasSp(11f), fontWeight = FontWeight.Bold),
                color = ink,
                maxLines = 1,
                softWrap = false,
            )
        }
    }
}

/** 결과 머리 카드 [반응] 단추 + 여섯 이모티콘 시트(판 화면은 GamesRummyReactionPanel). 판이 없으면 꺼진다. */
@Composable
fun GamesRummyReactionButton(rummy: RummyStore, now: () -> SwiftDate, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val enabled = rummy.match != null
    var picking by remember { mutableStateOf(false) }
    Box(
        modifier
            .size(AingDimens.minimumTarget)
            .clickable(enabled = enabled, role = Role.Button) { picking = true }
            .semantics { contentDescription = RummyPhoneText.reactionButton }
            .testTag(GamesRummyReactionTags.BUTTON),
        contentAlignment = Alignment.Center,
    ) {
        AingIcon(AppIcon.Mood, contentDescription = null, size = 22.dp, tint = if (enabled) colors.label else colors.label3Text)
    }
    if (picking) {
        GamesSheet(onDismiss = { picking = false }) {
            GamesRummyReactionPicker(rummy, now, onPicked = { picking = false })
        }
    }
}

/**
 * 이모티콘 여섯(3×2 · `AingSticker.entries` 순서가 고르는 순서). 고르면 보내고 닫는다. 쿨다운 2초 동안은 칸이 흐려진다 — 눌러도 안 간다는 것을 보인다(코어도 막는다).
 * 시계는 이 격자가 떠 있는 동안만 돈다 — 열쇠가 안 바뀌는 효과 하나다.
 */
@Composable
private fun GamesRummyReactionGrid(rummy: RummyStore, now: () -> SwiftDate, onPicked: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val art = rememberStickerArt()
    val clock by rememberUpdatedState(now)
    var ready by remember(rummy) { mutableStateOf(rummy.canReact(now())) }
    LaunchedEffect(rummy) {
        while (true) {
            ready = rummy.canReact(clock())
            delay(GAMES_RUMMY_PICKER_TICK_MILLIS)
        }
    }
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
        Text(RummyReactionPhoneText.title, style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Bold), color = colors.label)
        for (row in AingSticker.entries.chunked(3)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
                for (sticker in row) {
                    val shape = RoundedCornerShape(14.dp)
                    Box(
                        Modifier
                            .weight(1f)
                            .height(GAMES_RUMMY_PICKER_CELL_HEIGHT.dp)
                            .alpha(if (ready) 1f else 0.4f)
                            .background(colors.fill, shape)
                            .clickable(enabled = ready, role = Role.Button) { if (rummy.sendReaction(sticker)) onPicked() }
                            .semantics { contentDescription = AingStickerText.accessibilityLabel(sticker) }
                            .testTag(GamesRummyReactionTags.cell(sticker.rawValue)),
                        contentAlignment = Alignment.Center,
                    ) {
                        GamesRummyStickerArt(sticker, art, colors.label, Modifier.padding(6.dp).size((GAMES_RUMMY_PICKER_CELL_HEIGHT - 12).dp))
                    }
                }
            }
        }
    }
}

/** 결과 화면(세로)의 보내기 시트 내용. */
@Composable
internal fun GamesRummyReactionPicker(rummy: RummyStore, now: () -> SwiftDate, onPicked: () -> Unit, modifier: Modifier = Modifier) {
    GamesRummyReactionGrid(
        rummy,
        now,
        onPicked,
        modifier
            .fillMaxWidth()
            .padding(horizontal = AingDimens.sideMargin)
            .padding(top = AingDimens.space5, bottom = AingDimens.space6)
            .testTag(GamesRummyReactionTags.PICKER),
    )
}

/** 판 화면(가로)의 보내기 판 — 시트는 가로 폰에서 화면을 다 덮어 판과 남은 초를 가린다. [반응] 옆에 작게 띄우고, 바깥을 누르면 닫힌다. */
@Composable
internal fun GamesRummyReactionPanel(rummy: RummyStore, now: () -> SwiftDate, onClose: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(18.dp)
    Box(modifier.fillMaxSize()) {
        Box(
            Modifier.matchParentSize()
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClick = onClose)
                .semantics { contentDescription = RummyPhoneText.close }
                .testTag(GamesRummyReactionTags.PANEL_BACKDROP),
        )
        GamesRummyReactionGrid(
            rummy,
            now,
            onClose,
            Modifier
                .align(Alignment.TopEnd)
                .padding(top = GamesRummyMatchLayout.columnPadding.dp, end = (GamesRummyMatchLayout.rightColumnWidth + GamesRummyMatchLayout.columnPadding).dp)
                .width(GAMES_RUMMY_PANEL_WIDTH.dp)
                .shadow(12.dp, shape)
                .background(colors.surface, shape)
                .border(0.8.dp, colors.separator, shape)
                .padding(14.dp)
                .testTag(GamesRummyReactionTags.PICKER),
        )
    }
}

private const val GAMES_RUMMY_PANEL_WIDTH: Int = 252
private const val GAMES_RUMMY_PICKER_TICK_MILLIS: Long = 250L
private const val GAMES_RUMMY_PICKER_CELL_HEIGHT: Int = 64
