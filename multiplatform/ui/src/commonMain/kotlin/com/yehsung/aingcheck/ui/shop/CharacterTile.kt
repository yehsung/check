// 원본: Sources/CheckMobileKit/Me/MeCharacterViews.swift:64-684 @ 3bd04bd (MeCharacterTile · MeCharacterArt · MeCharacterPreviewCard)
//
// 캐릭터 타일(상점 · 고르기 공용) · 캐릭터 그림 · 두 표정 미리 보기. 타일 상태 → 내용 판정은 스토어 쪽(W2-c `MeCharacterTileStatus.content`)이고
// 여기는 칠하기만 한다 — "뽑기 전용 카드가 루비 값을 말하지 않는다"가 값으로 잡혀 있다.
//
// 살아 있는 미리보기(W5-c, G §8-18 1 · F §8 B "'내 캐릭터'·고르기 화면에서 아잉이가 숨 쉬고 탭하면 hit"): 고르기 머리 그림과 상점 미리 보기 카드는
// [LocalLiveCharacterPreview] 자리를 먼저 본다. 조립(K11)이 W5-c 의 무대 Composable 을 꽂으면 그것이, 안 꽂으면 초상이 그려진다(assembly.md).
package com.yehsung.aingcheck.ui.shop

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.character.CharacterManifest
import com.yehsung.aingcheck.core.rules.character.gift.CakeGiftText
import com.yehsung.aingcheck.core.stores.me.MeCharacterTileStatus
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.ui.components.CharacterExpression
import com.yehsung.aingcheck.ui.components.RubyPrice
import com.yehsung.aingcheck.ui.components.RubyPriceRule
import com.yehsung.aingcheck.ui.gacha.GachaPaint
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/**
 * 살아 있는 미리보기 자리(W5-c). [Draw] 는 캐릭터 [characterId] 를 [size] 칸에 그린다. [revealSerial] 이 바뀌면(뽑기 공개 뒤) 한 번 도는 연출을
 * 틀어도 된다(F §8 B "뽑기 결과 공개 뒤 한 번 돌기"). null 이면 초상.
 */
fun interface LiveCharacterPreview {
    @Composable
    fun Draw(characterId: String, size: Dp, modifier: Modifier, revealSerial: Int)
}

val LocalLiveCharacterPreview = staticCompositionLocalOf<LiveCharacterPreview?> { null }

/**
 * 캐릭터 그림: 이 빌드가 초상을 싣는 캐릭터는 초상(전신 — 무대·위젯과 같은 그림), 모르는 id 는 자리표시(아잉으로 **지어내지 않는다** — 서버가 새
 * 캐릭터를 주면 이름은 id, 그림은 물음표).
 */
@Composable
fun MeCharacterArt(id: String, size: Dp, modifier: Modifier = Modifier, expression: CharacterExpression = CharacterExpression.Neutral) {
    if (MeArtPaths.isKnown(id)) {
        val art = rememberPortrait(id, expression)
        Box(modifier.size(size)) {
            if (art != null) {
                Image(art, contentDescription = null, modifier = Modifier.size(size), contentScale = ContentScale.Fit, filterQuality = FilterQuality.High)
            }
        }
    } else {
        Box(modifier.size(size), contentAlignment = Alignment.Center) {
            AingIcon(AppIcon.ContactSupport, contentDescription = null, size = size * 0.7f, tint = AingTheme.colors.label2)
        }
    }
}

/** 타일에 얹는 표시. 뜻이 다르면 모양도 다르다(상점의 '사려고 고른 것' ≠ 고르기의 '착용 중'). */
enum class MeTileMark {
    None,

    /** 상점에서 사려고 고른 것(파랑 틴트 바탕 · 파랑 이름). */
    Picked,

    /** 지금 입고 있는 것(파랑 테두리 + 체크). */
    Equipped,
}

object MeCharacterTileRules {
    /** 두 화면 같은 순서: 가진 것 먼저(아잉 → 받은 순서), 그다음 안 가진 것(받은 순서). 안정 정렬. */
    fun ordered(ids: List<String>, isOwned: (String) -> Boolean): List<String> = ids.filter(isOwned) + ids.filter { !isOwned(it) }

    fun accessibilityText(name: String, status: MeCharacterTileStatus): String = when (status) {
        MeCharacterTileStatus.Equipped -> "$name, ${MeText.equipped}"
        MeCharacterTileStatus.Owned -> "$name, ${MeText.owned}"
        is MeCharacterTileStatus.Price -> "$name, ${RubyPriceRule.accessibilityText(status.price.toLong(), RubyPriceRule.isShort(status.price.toLong(), status.balance))}"
        is MeCharacterTileStatus.GachaOnly -> MeText.gachaTileAccessibility(name, status.shardCost)
        MeCharacterTileStatus.GiftOnly -> "$name, ${CakeGiftText.lockedCaption}"
        MeCharacterTileStatus.UnknownPrice -> "$name, 가격 모름"
        MeCharacterTileStatus.Busy -> "$name, ${MeText.loading}"
        MeCharacterTileStatus.None -> name
    }
}

/** 캐릭터 타일: 받침(surface2) 위 그림 · 이름 · 상태 한 줄. 그림은 두 화면에서 똑같이 원색으로 그린다. */
@Composable
fun MeCharacterTile(id: String, name: String, status: MeCharacterTileStatus, mark: MeTileMark, modifier: Modifier = Modifier) {
    val c = AingTheme.colors
    val shape = RoundedCornerShape(AingDimens.tileRadius)
    Box(modifier) {
        Column(
            Modifier
                .fillMaxWidth()
                .background(c.surface, shape)
                .then(if (mark == MeTileMark.Picked) Modifier.background(c.accentTint, shape) else Modifier)
                .then(if (mark == MeTileMark.Equipped) Modifier.border(2.dp, c.accent, shape) else Modifier)
                .padding(8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Box(
                Modifier.fillMaxWidth().height(88.dp).background(c.surface2, RoundedCornerShape(AingDimens.innerRadius)),
                contentAlignment = Alignment.Center,
            ) { MeCharacterArt(id, 76.dp) }
            // iOS minimumScaleFactor(0.8) — 긴 이름("딸기 케이크 아잉이")은 글자를 0.8 배까지 줄여 한 줄에 담는다(그래도 넘치면 말줄임).
            BasicText(
                name, style = MeType.subheadline.copy(fontWeight = FontWeight.SemiBold, color = if (mark == MeTileMark.Picked) c.accent else c.label),
                maxLines = 1, overflow = TextOverflow.Ellipsis,
                autoSize = TextAutoSize.StepBased(minFontSize = MeType.subheadline.fontSize * 0.8f, maxFontSize = MeType.subheadline.fontSize, stepSize = 0.5.sp),
            )
            Box(Modifier.heightIn(min = 20.dp), contentAlignment = Alignment.Center) { StatusLine(id, status) }
        }
        if (mark == MeTileMark.Equipped) {
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .offset(x = (-4).dp, y = 4.dp)
                    .size(22.dp)
                    .background(c.surface, CircleShape)
                    .padding(2.dp)
                    .background(c.accentFill, CircleShape),
                contentAlignment = Alignment.Center,
            ) { AingIcon(AppIcon.Check, contentDescription = null, size = 13.dp, tint = c.onAccentFill) }
        }
    }
}

/** 상태 줄 — 무엇을 말하는지는 [MeCharacterTileStatus.content](스토어)가 정하고 여기서는 칠하기만 한다. */
@Composable
private fun StatusLine(id: String, status: MeCharacterTileStatus) {
    val c = AingTheme.colors
    when (val content = status.content) {
        is MeCharacterTileStatus.Content.Ruby ->
            RubyPrice(content.price.toLong(), RubyPriceRule.isShort(content.price.toLong(), content.balance), rememberRuby(17f), gemSize = 17.dp, fontSize = 15f)
        is MeCharacterTileStatus.Content.Text -> Text(
            content.text,
            style = if (content.emphasized) MeType.footnote.copy(fontWeight = FontWeight.SemiBold) else MeType.footnote,
            color = if (content.emphasized) c.accent else c.label2,
        )
        // 반짝임은 희귀 마감 빛깔의 **기호** 칠(짧은 자리 — 단색)이다. 글자는 보조색.
        is MeCharacterTileStatus.Content.Acquire -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            AingIcon(AppIcon.AutoAwesome, contentDescription = null, size = 12.dp, tint = GachaPaint.sparkle(CharacterManifest.Finish.of(id)))
            Text(content.text, style = MeType.footnote, color = c.label2, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        // 생일 선물 전용 잠긴 칸 — 선물 기호(자물쇠가 아니다) + 한 줄. 루비 값도 반짝임도 없다.
        is MeCharacterTileStatus.Content.Locked -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            AingIcon(AppIcon.RedeemFill, contentDescription = null, size = 12.dp, tint = c.label2)
            Text(content.text, style = MeType.footnote, color = c.label2, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        MeCharacterTileStatus.Content.Spinner -> CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
    }
}

/** 고른 캐릭터의 두 표정(근무 중 웃음 · 근무 안 함 시무룩) — 사면 무엇이 바뀌는지 보여 빈 가운데를 채운다. */
@Composable
fun MeCharacterPreviewCard(id: String, modifier: Modifier = Modifier) {
    val c = AingTheme.colors
    val name = com.yehsung.aingcheck.core.stores.me.MeCharacterName.display(id)
    MeCard(modifier) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(MeText.previewTitle(name), style = MeType.headline, color = c.label)
                Text(MeText.previewCaption, style = MeType.footnote, color = c.label2)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(AingDimens.space2), verticalAlignment = Alignment.Top) {
                Face(id, CharacterExpression.Neutral, MeText.previewWorking)
                Face(id, CharacterExpression.Negative, MeText.previewOff)
            }
        }
    }
}

@Composable
private fun Face(id: String, expression: CharacterExpression, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        MeCharacterArt(id, 52.dp, Modifier.padding(4.dp), expression)
        Text(label, style = MeType.caption2, color = AingTheme.colors.label2)
    }
}

/** 고르기 머리 · 공개 뒤 그림: 살아 있는 미리보기가 꽂혀 있으면 그것, 아니면 초상. */
@Composable
fun MeLiveOrPortrait(id: String, size: Dp, modifier: Modifier = Modifier, revealSerial: Int = 0) {
    val live = LocalLiveCharacterPreview.current
    if (live != null) live.Draw(id, size, modifier, revealSerial) else MeCharacterArt(id, size, modifier)
}
