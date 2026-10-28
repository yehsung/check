// 원본: Sources/CheckMobileKit/Games/GamesCanvasKit.swift @ 3bd04bd (GamesOverlayCard · GamesStageChip · GamesScorePop)
//
// 세 게임 캔버스(+ 1:1 테트리스)가 함께 쓰는 조각. 캔버스는 무대 하늘이 늘 어두워 라이트 모드에서도 맥 패널 색([GamesCanvasColors])을 쓴다 —
// 게임 화면은 라이트·다크와 무관하게 같은 그림이다. 글자 크기는 캔버스 배율(`scale`)을 따라 커지고 **시스템 글자 크기에는 끌려가지 않는다**
// (Swift `.dynamicTypeSize(...large)` — 시스템 글자에 끌려가면 판을 넘친다). 그래서 글자는 [canvasSp] 로 dp 를 그대로 sp 로 옮긴다.
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.minigame.MiniGameStage
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.icons.SfSymbols
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/** 캔버스 글자: [points] dp 를 시스템 글자 크기와 무관하게 sp 로(판 배율을 따르고 글자 설정에 끌려가지 않는다). */
@Composable
fun canvasSp(points: Float): TextUnit = with(LocalDensity.current) { points.dp.toSp() }

/** 캔버스 글자의 숫자 꼴(고정폭 숫자 — Swift `.monospacedDigit()`). */
const val TABULAR_NUMBERS: String = "tnum"

/** 캔버스 글자 그림자(Swift `.shadow(color: .black.opacity(0.5), radius: 3, y: 1)` 의 꼴). */
fun canvasTextShadow(alpha: Float = 0.5f, blur: Float = 6f, dy: Float = 2f): Shadow = Shadow(Color.Black.copy(alpha = alpha), Offset(0f, dy), blur)

/**
 * 자식을 부모 안 한 점([x],[y] — 픽셀)에 **가운데로** 앉힌다(SwiftUI `.position(x:y:)`). 부모는 꽉 찬 상자여야 한다.
 */
fun Modifier.centeredAt(x: Float, y: Float): Modifier = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints.copy(minWidth = 0, minHeight = 0))
    layout(constraints.maxWidth, constraints.maxHeight) {
        placeable.place((x - placeable.width / 2f).roundToInt(), (y - placeable.height / 2f).roundToInt())
    }
}

/** SF 기호 이름 → Material Symbols(없으면 null — 그 자리는 비운다, 맞지 않는 기호로 대신하지 않는다). */
fun sfIcon(name: String?): AppIcon? = name?.let { SfSymbols.icon(it) }

/**
 * 시작 안내·결과 카드. **불투명**(반투명이면 플래피 기둥 선이 점수 뒤로 비친다) · 조작 안내는 손가락 기호 + 글자(캔버스 전체가 누름 영역).
 * 플래피는 기호 대신 실제 아잉 옆모습([aingArt]).
 */
@Composable
fun GamesOverlayCard(
    title: String,
    subtitle: String,
    action: String,
    modifier: Modifier = Modifier,
    titleIsScore: Boolean = false,
    subtitleIsHighlighted: Boolean = false,
    icon: String? = null,
    showsAing: Boolean = false,
    aingArt: ImageBitmap? = null,
    tint: Color = GamesCanvasColors.accent,
    scale: Float = 1f,
) {
    val shape = RoundedCornerShape((14 * scale).dp)
    Column(
        modifier = modifier
            .widthIn(max = (240 * scale).dp)
            .shadow((8 * scale).dp, shape, ambientColor = Color.Black.copy(alpha = 0.35f), spotColor = Color.Black.copy(alpha = 0.35f))
            .background(GamesCanvasColors.panelElevated, shape)
            .border(1.dp, Brush.linearGradient(listOf(tint.copy(alpha = 0.45f), GamesCanvasColors.border)), shape)
            .padding(horizontal = (18 * scale).dp, vertical = (14 * scale).dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy((6 * scale).dp),
    ) {
        if (showsAing) {
            FlappyAingImage(aingArt, (40 * scale).dp)
        } else {
            val appIcon = sfIcon(icon)
            if (appIcon != null) {
                Box(
                    Modifier.size((34 * scale).dp).background(tint.copy(alpha = 0.16f), CircleShape).clearAndSetSemantics { },
                    contentAlignment = Alignment.Center,
                ) {
                    AingIcon(appIcon, contentDescription = null, size = (16 * scale).dp, tint = tint)
                }
            }
        }
        Text(
            title,
            style = TextStyle(
                fontSize = canvasSp((if (titleIsScore) 30 else 17) * scale),
                fontWeight = if (titleIsScore) FontWeight.ExtraBold else FontWeight.SemiBold,
                fontFeatureSettings = TABULAR_NUMBERS,
                color = GamesCanvasColors.primaryText,
            ),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            subtitle,
            style = TextStyle(
                fontSize = canvasSp((if (subtitleIsHighlighted) 13 else 12) * scale),
                fontWeight = if (subtitleIsHighlighted) FontWeight.Bold else FontWeight.Normal,
                fontFeatureSettings = TABULAR_NUMBERS,
                color = if (subtitleIsHighlighted) GamesCanvasColors.working else GamesCanvasColors.primaryText.copy(alpha = 0.78f),
                textAlign = TextAlign.Center,
            ),
        )
        Row(
            modifier = Modifier.padding(top = (4 * scale).dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy((4 * scale).dp),
        ) {
            AingIcon(AppIcon.TouchAppFill, contentDescription = null, size = (14 * scale).dp, tint = tint)
            Text(action, style = TextStyle(fontSize = canvasSp(13 * scale), fontWeight = FontWeight.SemiBold, color = tint))
        }
    }
}

/** 무대 이름 칩(세 게임이 같은 픽셀). */
@Composable
fun GamesStageChip(stage: MiniGameStage, modifier: Modifier = Modifier, scale: Float = 1f) {
    val glow = stage.paint.glow
    Text(
        stage.stageName,
        modifier = modifier
            .background(glow.copy(alpha = 0.16f), CircleShape)
            .border(1.dp, glow.copy(alpha = 0.40f), CircleShape)
            .padding(horizontal = (6 * scale).dp, vertical = (2 * scale).dp),
        style = TextStyle(fontSize = canvasSp(10 * scale), fontWeight = FontWeight.SemiBold, color = glow),
        maxLines = 1,
    )
}

/**
 * 잠깐 떠오르는 점수·판정 글씨("+100 · 완벽!" · "+1"). [key] 가 바뀔 때마다 새로 튄다(Swift `.id(round)`).
 * 확대·상승만 움직인다 — **불투명도는 이징으로 깎지 않는다**(기억 easing-must-not-drive-opacity). reduceMotion 이면 정지 글씨.
 */
@Composable
fun GamesScorePop(
    text: String,
    key: Any,
    modifier: Modifier = Modifier,
    caption: String? = null,
    tint: Color = GamesCanvasColors.working,
    reduceMotion: Boolean = false,
    scale: Float = 1f,
) {
    val grow = remember(key) { Animatable(if (reduceMotion) 1f else 0.55f) }
    val lift = remember(key) { Animatable(0f) }
    LaunchedEffect(key, reduceMotion) {
        if (reduceMotion) return@LaunchedEffect
        // 스프링(0.30초 · 튐 0.42)으로 커지고, 0.55초 감속으로 14 만큼 오른다.
        launch { grow.animateTo(1f, spring(dampingRatio = 0.58f, stiffness = 430f)) }
        launch { lift.animateTo(-14f * scale, tween(550, easing = FastOutSlowInEasing)) }
    }
    val shadow = canvasTextShadow(0.45f, 6f, 1f)
    Column(
        modifier = modifier
            .graphicsLayer {
                scaleX = grow.value
                scaleY = grow.value
                translationY = lift.value * density
            }
            .clearAndSetSemantics { },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(1.dp),
    ) {
        Text(text, style = TextStyle(fontSize = canvasSp(19 * scale), fontWeight = FontWeight.ExtraBold, fontFeatureSettings = TABULAR_NUMBERS, color = tint, shadow = shadow))
        if (caption != null) {
            Text(caption, style = TextStyle(fontSize = canvasSp(10 * scale), fontWeight = FontWeight.Bold, color = tint, shadow = shadow))
        }
    }
}

/** 플래피 아잉 옆모습(게임 탭 타일 · 플래피 카드). 그림이 없으면 같은 크기의 빈 자리(기호로 대신하지 않는다 — Swift ArtImage). */
@Composable
fun FlappyAingImage(art: ImageBitmap?, size: Dp, modifier: Modifier = Modifier) {
    if (art == null) {
        Box(modifier.size(size))
    } else {
        androidx.compose.foundation.Image(
            bitmap = art,
            contentDescription = null,
            modifier = modifier.size(size),
            filterQuality = androidx.compose.ui.graphics.FilterQuality.High,
        )
    }
}
