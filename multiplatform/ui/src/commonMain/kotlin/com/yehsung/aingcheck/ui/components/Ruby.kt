// 원본: Sources/CheckMobileKit/Components/RubyComponents.swift @ 862be0f
// 원본: Sources/CheckMobileKit/Components/MobileComponentModels.swift @ 862be0f (RubyGlyph · RubyPriceRule)
// 원본: Sources/CheckMobileKit/Components/AingButtons.swift @ 862be0f (GlassBackground — 유리 알약)
//
// 루비 = ruby.png 하나, 문법 셋(시안 B "2 · 루비"):
//  - 잔량: 주요색 캡슐 속 보석(accentTint 바탕 + accentLine 테두리 — iOS 와 같은 파랑, G §8-15) — RubyBalanceChip
//  - 가격: 맨 보석 + 숫자, 모자라면 글자 label3Text + 보석 50% — RubyPrice
//  - 획득: 초록 +N — RubyGain
// 진홍 마름모 기호·자물쇠 가격표는 쓰지 않는다. 숫자는 고정폭 숫자(tnum).
package com.yehsung.aingcheck.ui.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 보석 크기·그림 고르기 규칙. */
object RubyGlyph {
    /** 시안 보석 크기 단계(dp): 가격 칸 14 · 작은 칩·가격 17 · 20 · 큰 칩 24. */
    val sizes: List<Float> = listOf(14f, 17f, 20f, 24f)

    /** 그릴 픽셀 크기에 맞는 파일(확장자 뺀 이름). 327px 를 14dp 로 한 번에 줄이면 면이 뭉개져 축소본을 고른다. */
    fun assetName(pointSize: Float, density: Float): String {
        val pixels = pointSize * maxOf(density, 1f)
        return when {
            pixels <= 48f -> "ruby-48"
            pixels <= 96f -> "ruby-96"
            else -> "ruby"
        }
    }

    /** 숫자 글자: 고정폭 숫자(iOS .monospacedDigit). */
    const val TABULAR_FEATURES = "tnum"
}

object RubyPriceRule {
    /** 잔량이 가격보다 모자라면 흐리게. 잔량을 모르면(null) 모자라다고 하지 않는다(맥 0.3.29 규칙). */
    fun isShort(price: Int, balance: Int?): Boolean = balance != null && balance < price

    fun accessibilityText(price: Int, isShort: Boolean): String = if (isShort) "루비 ${price}개, 모자라요" else "루비 ${price}개"

    fun balanceText(count: Int?): String = count?.toString() ?: "–"

    fun balanceAccessibility(count: Int?): String = count?.let { "루비 ${it}개" } ?: "루비 잔액 모름"
}

/** 보석 하나. [art] 는 크기에 맞는 그림(RubyGlyph.assetName — CharacterArt.ruby 가 고른다). */
@Composable
fun RubyIcon(art: ImageBitmap?, size: Dp = 17.dp, modifier: Modifier = Modifier) {
    if (art == null) {
        Box(modifier.size(size))
    } else {
        Image(
            bitmap = art,
            contentDescription = null,
            modifier = modifier.size(size),
            contentScale = ContentScale.Fit,
            filterQuality = FilterQuality.High,
        )
    }
}

enum class RubyChipStyle(val gem: Dp, val height: Dp, val fontSize: Float, val weight: FontWeight, val leading: Dp, val trailing: Dp) {
    /** 높이 24 · 보석 17 · subheadline bold. */
    Small(17.dp, 24.dp, 15f, FontWeight.Bold, 6.dp, 9.dp),
    /** 높이 34 · 보석 24 · title3 bold. */
    Large(24.dp, 34.dp, 20f, FontWeight.Bold, 8.dp, 12.dp),
    /** 유리 알약 44 · 보석 20 · headline semibold. */
    Glass(20.dp, 44.dp, 17f, FontWeight.SemiBold, 10.dp, 14.dp),
    /** 도구 막대 안 유리 알약(보석 22 · 숫자 16). */
    Toolbar(22.dp, 44.dp, 16f, FontWeight.SemiBold, 10.dp, 14.dp),
}

/** 루비 잔량 칩. null 은 "–"(모른다 — 0 으로 지어내지 않는다). [onClick] 이 있으면 누름 영역 44 이상. */
@Composable
fun RubyBalanceChip(
    count: Int?,
    art: ImageBitmap?,
    modifier: Modifier = Modifier,
    style: RubyChipStyle = RubyChipStyle.Small,
    onClick: (() -> Unit)? = null,
) {
    val colors = AingTheme.colors
    val shape = CircleShape
    val background = when (style) {
        RubyChipStyle.Small, RubyChipStyle.Large ->
            Modifier.background(colors.accentTint, shape).border(1.dp, colors.accentLine, shape)
        RubyChipStyle.Glass, RubyChipStyle.Toolbar ->
            Modifier.background(colors.glass, shape).border(0.5.dp, colors.glassLine, shape)
    }
    val clickable = if (onClick != null) Modifier.heightIn(min = AingDimens.minimumTarget).clickable(onClick = onClick) else Modifier
    Box(modifier.then(clickable), contentAlignment = Alignment.Center) {
        Row(
            Modifier
                .clearAndSetSemantics { contentDescription = RubyPriceRule.balanceAccessibility(count) }
                .then(background)
                .defaultMinSize(minHeight = style.height)
                .padding(start = style.leading, end = style.trailing),
            horizontalArrangement = Arrangement.spacedBy(if (style == RubyChipStyle.Small) 3.dp else if (style == RubyChipStyle.Toolbar) 6.dp else 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            RubyIcon(art, style.gem)
            Text(
                RubyPriceRule.balanceText(count),
                style = numberStyle(style.fontSize, style.weight),
                color = colors.label,
                maxLines = 1,
            )
        }
    }
}

/** 가격: 맨 보석 + 숫자. 모자라면 글자 label3Text + 보석 50%(자물쇠 없음). */
@Composable
fun RubyPrice(price: Int, isShort: Boolean, art: ImageBitmap?, modifier: Modifier = Modifier, gemSize: Dp = 17.dp, fontSize: Float = 15f) {
    val colors = AingTheme.colors
    Row(
        modifier.clearAndSetSemantics { contentDescription = RubyPriceRule.accessibilityText(price, isShort) },
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RubyIcon(art, gemSize, Modifier.alpha(if (isShort) 0.5f else 1f))
        Text("$price", style = numberStyle(fontSize, FontWeight.SemiBold), color = if (isShort) colors.label3Text else colors.label, maxLines = 1)
    }
}

enum class RubyGainStyle { Inline, Chip }

/** 획득: 초록 [보석]+N(Inline) 또는 틴트 칩(Chip — "+10 받음" 같은 꼬리 문구). */
@Composable
fun RubyGain(amount: Int, art: ImageBitmap?, modifier: Modifier = Modifier, suffix: String? = null, style: RubyGainStyle = RubyGainStyle.Inline) {
    val colors = AingTheme.colors
    val chip = style == RubyGainStyle.Chip
    Row(
        modifier
            .clearAndSetSemantics { contentDescription = "루비 ${amount}개 받음" }
            .then(if (chip) Modifier.background(colors.workingTint, CircleShape).defaultMinSize(minHeight = 24.dp).padding(start = 6.dp, end = 9.dp) else Modifier),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RubyIcon(art, 17.dp)
        Text(
            "+$amount" + (suffix?.let { " $it" } ?: ""),
            style = numberStyle(if (chip) 13f else 15f, FontWeight.Bold),
            color = colors.working,
            maxLines = 1,
        )
    }
}

@Composable
private fun numberStyle(size: Float, weight: FontWeight): TextStyle =
    MaterialTheme.typography.bodyMedium.copy(fontSize = size.sp, lineHeight = (size + 5f).sp, fontWeight = weight, fontFeatureSettings = RubyGlyph.TABULAR_FEATURES)
