// 원본: Sources/CheckMobileKit/Components/CharacterPortrait.swift @ a63fea2
// 원본: Sources/CheckMobileKit/Components/CharacterTabIcon.swift @ a63fea2
//
// 캐릭터 초상 — **나를 가리키는 자리에만** 쓴다(지금 상태 카드 · 나 머리 · 순위의 내 행 · 오목 플레이어 · 위젯).
// 표정 = 근무 상태: 근무 중 웃음 + 초록 링·발광 · 끊김 웃음 + 앰버 링 · 근무 안 함 시무룩 + 청회색 링 · Plain 은 링 없이 받침만.
//
// 기하(iOS 그대로): 받침 원 → 그림은 원 안 88%, 아래로 5% 내려 원으로 자른다 → 틈 링(2, 놓인 면 색) → 상태 링(max(2, 지름×0.04)).
// 링은 원 **바깥**으로 그린다(프레임은 size 그대로 — iOS overlay padding 음수와 같다).
// 발광: iOS 는 blur 를 쓴다. Compose blur 는 Android 12 미만에서 꺼져 화면이 기기마다 갈리므로 **방사형 그라데이션으로 근사**한다
// (판단: 같은 색·같은 반경, 가장자리 모양만 다르다 — 모든 플랫폼에서 같은 픽셀).
//
// 그림은 부르는 쪽이 넘긴다(ImageBitmap). 불러오기는 CharacterArt(Res — Gradle Sync 로 Sources/check/Characters 를 읽는다).
// 그림이 없으면(null) 받침·링만 그린다 — SF 기호나 다른 그림으로 대신하지 않는다(iOS ArtImage 와 같다).
package com.yehsung.aingcheck.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingColors
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** 초상 오른쪽 아래 배지. */
sealed interface PortraitBadge {
    data object None : PortraitBadge
    /** accentFill 원 + 기호(예: 캐릭터 바꾸기 붓). */
    data class Symbol(val icon: AppIcon) : PortraitBadge
    /** 오목 돌. */
    data class Stone(val isBlack: Boolean) : PortraitBadge
}

/**
 * - [size]: 원 지름. 탭 막대 25 · 행 32~40 · 카드 52 · 나 머리 68 · 무대 120~140.
 * - [ringGap]: 링과 그림 사이 틈 색 = 초상이 놓인 면(카드 위면 surface, 바탕 위면 background). null 이면 surface.
 * - [framed]: false 면 원·받침·링 없이 그림만(무대의 큰 전신).
 */
@Composable
fun CharacterPortrait(
    art: ImageBitmap?,
    mood: CharacterMood,
    size: Dp,
    modifier: Modifier = Modifier,
    badge: PortraitBadge = PortraitBadge.None,
    ringGap: Color? = null,
    framed: Boolean = true,
) {
    val colors = AingTheme.colors
    val gapColor = ringGap ?: colors.surface
    Box(modifier.size(size).semantics { contentDescription = portraitDescription(mood) }) {
        Canvas(Modifier.size(size)) {
            if (framed) drawFramedPortrait(art, mood, colors, gapColor) else drawArt(art, Offset.Zero, this.size)
        }
        PortraitBadgeView(badge, size, gapColor, Modifier.align(Alignment.BottomEnd))
    }
}

internal fun portraitDescription(mood: CharacterMood): String = when (mood) {
    CharacterMood.Working -> "내 캐릭터, 근무 중"
    CharacterMood.Lost -> "내 캐릭터, 연결 끊김"
    CharacterMood.Off -> "내 캐릭터, 근무 안 함"
    CharacterMood.Plain -> "내 캐릭터"
}

private fun DrawScope.drawFramedPortrait(art: ImageBitmap?, mood: CharacterMood, colors: AingColors, gapColor: Color) {
    val d = size.minDimension
    val r = d / 2f
    val center = Offset(size.width / 2f, size.height / 2f)
    val dpPx = density
    if (mood == CharacterMood.Working) {
        // 바깥 발광(iOS: workingDot 35% 원 · blur s×0.15 · 바깥으로 s×0.04) → 반지름 r×1.04 + 번짐까지 옅어지는 방사형.
        val outer = r * 1.04f + d * 0.15f
        drawCircle(
            brush = Brush.radialGradient(
                0f to colors.workingDot.copy(alpha = 0.35f),
                (r * 0.85f / outer) to colors.workingDot.copy(alpha = 0.35f),
                1f to Color.Transparent,
                center = center, radius = outer,
            ),
            radius = outer, center = center,
        )
    }
    drawCircle(mood.backing(colors), radius = r, center = center)
    if (mood == CharacterMood.Working) {
        // 안쪽 발광(iOS: 두께 s×0.18 테두리 25% · blur s×0.1 · 원으로 자름) → 가장자리에서 안으로 옅어지는 방사형.
        val inner = (r - d * 0.18f - d * 0.1f).coerceAtLeast(0f)
        drawCircle(
            brush = Brush.radialGradient(
                0f to Color.Transparent,
                (inner / r) to Color.Transparent,
                1f to colors.workingDot.copy(alpha = 0.25f),
                center = center, radius = r,
            ),
            radius = r, center = center,
        )
    }
    val artSide = d * 0.88f
    val clip = Path().apply { addOval(androidx.compose.ui.geometry.Rect(center, r)) }
    clipPath(clip) {
        drawArt(art, Offset(center.x - artSide / 2f, center.y - artSide / 2f + d * 0.05f), Size(artSide, artSide))
    }
    val ring = mood.ring ?: return
    val gap = CharacterMood.RING_GAP * dpPx
    val ringW = CharacterMood.ringWidth(d / dpPx) * dpPx
    drawCircle(gapColor, radius = r + gap / 2f, center = center, style = Stroke(width = gap))
    drawCircle(ring.dotColor(colors), radius = r + gap + ringW / 2f, center = center, style = Stroke(width = ringW))
}

/** 그림을 [dstOffset]·[dstSize] 에 맞춰 부드럽게. 없으면 아무것도 안 그린다. */
internal fun DrawScope.drawArt(art: ImageBitmap?, dstOffset: Offset, dstSize: Size, alpha: Float = 1f) {
    art ?: return
    drawImage(
        image = art,
        srcOffset = IntOffset.Zero,
        srcSize = IntSize(art.width, art.height),
        dstOffset = IntOffset(dstOffset.x.roundToInt(), dstOffset.y.roundToInt()),
        dstSize = IntSize(dstSize.width.roundToInt(), dstSize.height.roundToInt()),
        alpha = alpha,
        filterQuality = FilterQuality.High,
    )
}

@Composable
private fun PortraitBadgeView(badge: PortraitBadge, portraitSize: Dp, gapColor: Color, modifier: Modifier) {
    val colors = AingTheme.colors
    when (badge) {
        PortraitBadge.None -> Unit
        is PortraitBadge.Symbol -> {
            val side = max(18f, min(26f, portraitSize.value * 0.32f)).dp
            Box(
                modifier
                    .offset(3.dp, 3.dp)
                    .size(side + 5.dp)
                    .background(gapColor, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.size(side).background(colors.accentFill, CircleShape), contentAlignment = Alignment.Center) {
                    AingIcon(badge.icon, contentDescription = null, size = side * 0.6f, tint = colors.onAccentFill)
                }
            }
        }
        is PortraitBadge.Stone -> {
            val side = max(12f, min(20f, portraitSize.value * 0.3f)).dp
            val stops = if (badge.isBlack) listOf(Color(0.42f, 0.42f, 0.42f), Color(0.05f, 0.05f, 0.05f))
            else listOf(Color.White, Color(0.85f, 0.85f, 0.85f))
            // iOS: RadialGradient(center 0.35·0.3, endRadius side×0.7) + 바깥 틈 2.
            Canvas(modifier.offset(2.dp, 2.dp).size(side)) {
                val r = size.minDimension / 2f
                val c = Offset(size.width / 2f, size.height / 2f)
                val gap = 2f * density
                drawCircle(gapColor, radius = r + gap / 2f, center = c, style = Stroke(width = gap))
                drawCircle(
                    brush = Brush.radialGradient(stops, center = Offset(size.width * 0.35f, size.height * 0.3f), radius = size.width * 0.7f),
                    radius = r, center = c,
                )
            }
        }
    }
}

/**
 * 탭 막대 '나' 아이콘 = 착용 캐릭터 초상 + 근무 상태 링(26dp). M3 NavigationBarItem 의 icon 자리에 넣으면 막대 색으로 칠해지므로
 * 이 부품은 Icon 이 아니라 직접 그린다(틴트 없음 — iOS `.alwaysOriginal`). 링 2 · 틈 1.5 · 그림 88% 아래로 5%.
 */
@Composable
fun CharacterTabIcon(art: ImageBitmap?, mood: CharacterMood, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Canvas(modifier.size(TAB_ICON_SIDE.dp).semantics { contentDescription = portraitDescription(mood) }) {
        val side = size.minDimension
        val ringW = 2f * density
        val gap = 1.5f * density
        val inset = ringW + gap
        val innerR = side / 2f - inset
        val center = Offset(size.width / 2f, size.height / 2f)
        drawCircle(mood.backing(colors), radius = innerR, center = center)
        val artSide = innerR * 2f * 0.88f
        clipPath(Path().apply { addOval(androidx.compose.ui.geometry.Rect(center, innerR)) }) {
            drawArt(art, Offset(center.x - artSide / 2f, center.y - artSide / 2f + innerR * 2f * 0.05f), Size(artSide, artSide))
        }
        val ring = mood.ring ?: return@Canvas
        drawCircle(ring.dotColor(colors), radius = side / 2f - ringW / 2f, center = center, style = Stroke(width = ringW))
    }
}

/** 탭 아이콘 한 변(dp). */
const val TAB_ICON_SIDE = 26f
