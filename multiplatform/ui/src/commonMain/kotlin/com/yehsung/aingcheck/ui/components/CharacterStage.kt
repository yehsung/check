// 원본: Sources/CheckMobileKit/Me/MeTab.swift @ a63fea2 (MeStageCard.stage · floorTint — 나 탭 무대, 시안 A 09)
// 원본: Sources/CheckMobileKit/Components/MobileComponentModels.swift @ a63fea2 (CharacterArtChoice — 무대 고해상 고르기)
//
// 캐릭터 무대: 착용 캐릭터를 원·링 없이 크게(132) 세우고 발밑에 근무 상태 색 빛(타원 122×28, 45% → 12% → 투명)을 깐다.
// 그림자: iOS 는 그림 모양 그림자(검정 22% · 번짐 8 · 아래 6). Compose blur 는 Android 12 미만에서 꺼지므로, 그림을 검정으로 물들여
// 번짐 반경만큼 작게(1/[CharacterStageMetrics.SHADOW_RADIUS]·밀도) 줄였다가 부드럽게 다시 키워 번짐을 근사한다(판단 — 모든 플랫폼에서 돈다).
// 무대 이름표·루비 칩·단추 배치는 나 탭 화면(W3-b) 몫이다 — 여기는 무대 그림 한 칸만.
package com.yehsung.aingcheck.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.theme.AingColors
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.math.max
import kotlin.math.roundToInt

object CharacterStageMetrics {
    /** 무대 캐릭터 크기(시안 A 112×126 · 명세 120~140). */
    val artSize = 132.dp
    val floorWidth = 122.dp
    val floorHeight = 28.dp
    /** 발밑 빛 방사 반경(iOS endRadius 62). */
    const val FLOOR_RADIUS = 62f
    val artBottomPadding = 10.dp
    const val SHADOW_ALPHA = 0.22f
    const val SHADOW_RADIUS = 8f
    const val SHADOW_Y = 6f

    /** 초상 원본 한 변(px). 그릴 픽셀이 이보다 크고 웃는 얼굴이면 고해상 무대 그림(420px)을 고른다. */
    const val PORTRAIT_PIXELS = 192

    /** 무대 고해상(420px) 근무 중 표정이 있는 캐릭터(스프라이트 6종 — 아잉 원본은 192px 뿐). */
    val stageArtIds: Set<String> = setOf("fox", "ghost", "jellyfish", "robot", "shiba", "squirrel")

    /** iOS CharacterArtChoice.choose: 웃는 얼굴 + 무대 그림이 있는 캐릭터 + 그릴 픽셀 > 192 → 무대 그림. */
    fun prefersStageArt(id: String, expression: CharacterExpression, pointSize: Float, density: Float): Boolean =
        expression == CharacterExpression.Neutral && id in stageArtIds && pointSize * maxOf(density, 1f) > PORTRAIT_PIXELS
}

/**
 * 그림 모양 그림자 밑그림: 검정으로 물들인 그림을 번짐 반경(px)마다 한 칸이 되게 줄인 작은 그림.
 * 그릴 때 원래 크기로 부드럽게 키우면(FilterQuality.High) 가장자리가 번짐 반경만큼 퍼진다.
 */
internal fun stageShadow(art: ImageBitmap, sidePx: Float, density: Float): ImageBitmap {
    val blurPx = CharacterStageMetrics.SHADOW_RADIUS * density
    val small = max(2, (sidePx / blurPx).roundToInt())
    val out = ImageBitmap(small, small)
    val canvas = androidx.compose.ui.graphics.Canvas(out)
    val paint = Paint().apply {
        colorFilter = ColorFilter.tint(Color.Black, BlendMode.SrcIn)
        filterQuality = FilterQuality.High
    }
    canvas.drawImageRect(art, IntOffset.Zero, IntSize(art.width, art.height), IntOffset.Zero, IntSize(small, small), paint)
    return out
}

/** 발밑 빛 색 = 근무 상태 뜻 색(모르면 label3 회색). */
fun stageFloorTint(mood: CharacterMood?, colors: AingColors): Color = when (mood) {
    CharacterMood.Working -> colors.workingDot
    CharacterMood.Lost -> colors.pendingDot
    CharacterMood.Off -> colors.offWorkDot
    CharacterMood.Plain, null -> colors.label3
}

/** 무대 한 칸(크기 = 그림 + 6 × 그림 + 12). [mood] 가 null 이면 근무 상태를 모른다(회색 빛). */
@Composable
fun CharacterStage(
    art: ImageBitmap?,
    mood: CharacterMood?,
    modifier: Modifier = Modifier,
    artSize: Dp = CharacterStageMetrics.artSize,
) {
    val colors = AingTheme.colors
    val tint = stageFloorTint(mood, colors)
    val width = artSize + 6.dp
    val height = artSize + 12.dp
    val densityValue = LocalDensity.current.density
    val shadow = remember(art, artSize, densityValue) { art?.let { stageShadow(it, artSize.value * densityValue, densityValue) } }
    Canvas(modifier.size(width, height).semantics { contentDescription = portraitDescription(mood ?: CharacterMood.Plain) }) {
        val m = CharacterStageMetrics
        // 발밑 빛: 아래 가운데 타원(122×28), 반경 62 방사형을 세로로 눌러 그린다.
        val fw = m.floorWidth.toPx()
        val fh = m.floorHeight.toPx()
        val floorCenter = Offset(size.width / 2f, size.height - fh / 2f)
        val radius = m.FLOOR_RADIUS * density
        scale(scaleX = 1f, scaleY = fh / fw, pivot = floorCenter) {
            drawOval(
                brush = Brush.radialGradient(
                    0f to tint.copy(alpha = 0.45f),
                    0.5f to tint.copy(alpha = 0.12f),
                    1f to Color.Transparent,
                    center = floorCenter, radius = radius,
                ),
                topLeft = Offset(floorCenter.x - fw / 2f, floorCenter.y - fw / 2f),
                size = Size(fw, fw),
            )
        }
        val side = artSize.toPx()
        val artTop = size.height - m.artBottomPadding.toPx() - side
        val artLeft = (size.width - side) / 2f
        if (shadow != null) {
            drawImage(
                image = shadow,
                srcOffset = IntOffset.Zero, srcSize = IntSize(shadow.width, shadow.height),
                dstOffset = IntOffset(artLeft.roundToInt(), (artTop + m.SHADOW_Y * density).roundToInt()),
                dstSize = IntSize(side.roundToInt(), side.roundToInt()),
                alpha = m.SHADOW_ALPHA,
                filterQuality = FilterQuality.High,
            )
        }
        drawArt(art, Offset(artLeft, artTop), Size(side, side))
    }
}
