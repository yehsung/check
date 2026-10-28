// 원본: Sources/CheckMobileKit/Me/MeCharacterViews.swift:383-684 @ 3bd04bd (MeCharacterPickerView · MeCharacterTile · MeCharacterArt — 고르기 화면과 상점·고르기 공용 타일)
// 원본: Sources/CheckMobileKit/Theme/MobileTheme.swift:104-111 @ 3bd04bd (sparkle — 뽑기 전용 반짝임 빛깔: 금 · 라이트 무지개 단색 · 다크 무지개)
//
// 캐릭터 고르기: 지금 입은 캐릭터 크게 + 이 캐릭터가 어디에 나오는지 · 가진 것 먼저(아잉 → 받은 순서) 3열 타일 · [상점 가기].
// 판정(상태 줄 · 고르기/뽑기 기계 · 순서 · 열 수)은 이 파일의 순수 함수와 스토어(W2-c MeStoreCharacters · MeCharacterTileStatus)다.
// 타일([MeCharacterTile])은 상점(W4-c ui/shop)과 같은 모양이다 — **표시 둘은 뜻이 다르니 모양도 다르다**: 착용 중 = 파랑 2 테두리 + 체크,
// 상점에서 사려고 고른 것 = 파랑 틴트 바탕 + 파랑 이름. 그림은 두 화면에서 똑같이 원색이다(안 가진 것을 흐리게 그리지 않는다 — 비평 5).
package com.yehsung.aingcheck.ui.screens.me

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.character.CharacterManifest
import com.yehsung.aingcheck.core.rules.character.gift.CakeGiftText
import com.yehsung.aingcheck.core.stores.me.MeCharacterName
import com.yehsung.aingcheck.core.stores.me.MeCharacterTileStatus
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.charactersDidAppear
import com.yehsung.aingcheck.core.stores.me.chooseCharacter
import com.yehsung.aingcheck.core.stores.me.equippedCharacterID
import com.yehsung.aingcheck.core.stores.me.gachaShardCost
import com.yehsung.aingcheck.core.stores.me.isGachaOnly
import com.yehsung.aingcheck.core.stores.me.isGiftOnly
import com.yehsung.aingcheck.core.stores.me.isOwned
import com.yehsung.aingcheck.core.stores.me.isUnlocked
import com.yehsung.aingcheck.core.stores.me.pickerIDs
import com.yehsung.aingcheck.core.stores.me.price
import com.yehsung.aingcheck.core.stores.me.showsGacha
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.CharacterPortrait
import com.yehsung.aingcheck.ui.components.RubyPrice
import com.yehsung.aingcheck.ui.components.RubyPriceRule
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.settingscommon.AingButton
import com.yehsung.aingcheck.ui.screens.settingscommon.AingButtonKind
import com.yehsung.aingcheck.ui.screens.settingscommon.AingCard
import com.yehsung.aingcheck.ui.screens.settingscommon.InlineNotice
import com.yehsung.aingcheck.ui.screens.settingscommon.LocalScreenArt
import com.yehsung.aingcheck.ui.screens.settingscommon.NoticeKind
import com.yehsung.aingcheck.ui.screens.settingscommon.SectionTitle
import com.yehsung.aingcheck.ui.theme.AingColors
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

object CharacterPickerTags {
    fun tile(id: String) = "picker-tile:$id"
    const val SHOP = "picker-go-shop"
    const val HERO = "picker-hero"
}

/** 타일에 얹는 표시(뜻이 다르면 모양도 다르다). */
enum class MeCharacterTileMark { None, Picked, Equipped }

/** 타일을 눌렀을 때 할 일. */
enum class CharacterPickerTap { Choose, OpenGachaMachine }

/** 고르기 화면 판정(순수 — Swift pickerTile · MeCharacterTile 의 정적 함수). */
object CharacterPickerRules {
    /** 두 화면 같은 순서: 가진 것 먼저(아잉 → 받은 순서), 그다음 안 가진 것(받은 순서). 안정 정렬. */
    fun ordered(ids: List<String>, isOwned: (String) -> Boolean): List<String> = ids.filter(isOwned) + ids.filterNot(isOwned)

    /** 열 수: 큰 글자에서 줄인다(Swift 접근성 크기 1 · xxLarge 이상 2 · 그 밖 3 — Android 는 글자 배율로). */
    fun columns(fontScale: Float): Int = when {
        fontScale >= 1.8f -> 1
        fontScale >= 1.3f -> 2
        else -> 3
    }

    /** 타일 상태(Swift pickerTile 의 갈래 순서 그대로 — 저장 중 → 착용 → 보유 → 선물 전용 → 뽑기 전용 → 가격 → 모름). */
    fun status(
        savingThis: Boolean,
        isOn: Boolean,
        owned: Boolean,
        giftOnly: Boolean,
        gachaOnly: Boolean,
        shardCost: Long?,
        price: Long?,
        balance: Long?,
        unlocked: Boolean,
    ): MeCharacterTileStatus = when {
        savingThis -> MeCharacterTileStatus.Busy
        isOn -> MeCharacterTileStatus.Equipped
        owned -> MeCharacterTileStatus.Owned
        // 고르기에는 가진 사람에게만 서므로(pickerIDs) 거의 닿지 않는다 — 착용값이 소유보다 먼저 도착한 창의 안전망.
        giftOnly -> MeCharacterTileStatus.GiftOnly
        gachaOnly -> MeCharacterTileStatus.GachaOnly(shardCost)
        price != null -> MeCharacterTileStatus.Price(price, balance)
        unlocked -> MeCharacterTileStatus.None
        else -> MeCharacterTileStatus.UnknownPrice
    }

    /** 안 가진 뽑기 전용(황금 · 무지개) → 기계를 연다(뽑기가 열린 서버일 때만 — 아니면 고르기가 얻는 길을 말한다). */
    fun tap(showsGacha: Boolean, owned: Boolean, gachaOnly: Boolean): CharacterPickerTap =
        if (showsGacha && !owned && gachaOnly) CharacterPickerTap.OpenGachaMachine else CharacterPickerTap.Choose

    /** 타일 읽기 글자(Swift MeCharacterTile.accessibilityText). */
    fun accessibilityText(name: String, status: MeCharacterTileStatus): String = when (status) {
        MeCharacterTileStatus.Equipped -> "$name, ${MeText.equipped}"
        MeCharacterTileStatus.Owned -> "$name, ${MeText.owned}"
        is MeCharacterTileStatus.Price -> {
            val p = status.price.toInt()
            "$name, ${RubyPriceRule.accessibilityText(p, RubyPriceRule.isShort(p, status.balance?.toInt()))}"
        }
        is MeCharacterTileStatus.GachaOnly -> MeText.gachaTileAccessibility(name, status.shardCost)
        MeCharacterTileStatus.GiftOnly -> "$name, ${CakeGiftText.lockedCaption}"
        MeCharacterTileStatus.UnknownPrice -> "$name, 가격 모름"
        MeCharacterTileStatus.Busy -> "$name, ${MeText.loading}"
        MeCharacterTileStatus.None -> name
    }

    /** 잠긴 타일 읽기 글자(얻는 길을 말한다). */
    fun lockedLabel(name: String, giftOnly: Boolean, gachaOnly: Boolean, shardCost: Long?): String = when {
        giftOnly -> "$name, 잠김 — ${CakeGiftText.lockedCaption}"
        gachaOnly -> "$name, 잠김 — ${MeText.gachaAcquirePhrase(shardCost)}"
        else -> "$name, 잠김 — 상점에서 사기"
    }

    /** 머리 카드 둘째 줄: 착용 중 · 불러오지 못함 · 불러오는 중(색이 갈린다). */
    fun heroStatus(loaded: Boolean, failed: Boolean): Pair<String, MeWearKind> = when {
        loaded -> MeText.equipped to MeWearKind.Value
        failed -> MeText.equippedLoadFailed to MeWearKind.Failed
        else -> MeText.loading to MeWearKind.Loading
    }
}

/**
 * @param openShop [상점 가기](W4-c 상점 화면).
 * @param openGachaMachine 안 가진 뽑기 전용 타일 → 뽑기 기계(W4-c). 조립 전에는 아무것도 안 해도 된다(고르기가 대신 얻는 길을 말하지 않는다 — 보고).
 */
@Composable
fun CharacterPickerScreen(
    store: MeStore,
    openShop: () -> Unit,
    openGachaMachine: () -> Unit,
    modifier: Modifier = Modifier,
    scrollable: Boolean = true,
) {
    val colors = AingTheme.colors
    DisposableEffect(store) {
        store.charactersDidAppear()
        onDispose {}
    }
    val ids = CharacterPickerRules.ordered(store.pickerIDs) { store.isOwned(it) }
    val columns = CharacterPickerRules.columns(LocalDensity.current.fontScale)
    val scroll = if (scrollable) Modifier.verticalScroll(rememberScrollState()) else Modifier
    Column(
        modifier.fillMaxWidth().background(colors.background).then(scroll).padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.rowSpacing),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
    ) {
        PickerHero(store)
        store.characterNotice?.let { InlineNotice(it, if (store.isCharacterNoticeError) NoticeKind.Warning else NoticeKind.Info) }
        SectionTitle(MeText.charactersTitle, Modifier.padding(top = AingDimens.space1)) {
            Text(MeText.ownedCount(ids.count { store.isOwned(it) }, ids.size), style = MaterialTheme.typography.bodyMedium, color = colors.label2)
        }
        ids.chunked(columns).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
                row.forEach { id -> PickerTile(store, id, openGachaMachine, Modifier.weight(1f)) }
                repeat(columns - row.size) { Box(Modifier.weight(1f)) }
            }
        }
        AingButton(
            MeText.goToShop,
            AingButtonKind.Tinted,
            onClick = openShop,
            fillsWidth = true,
            icon = AppIcon.ShoppingBag,
            modifier = Modifier.padding(top = AingDimens.space1).testTag(CharacterPickerTags.SHOP),
        )
    }
}

@Composable
private fun PickerHero(store: MeStore) {
    val colors = AingTheme.colors
    val id = store.equippedCharacterID
    val (statusText, kind) = CharacterPickerRules.heroStatus(store.equippedLoaded, store.equippedLoadFailed)
    AingCard(Modifier.testTag(CharacterPickerTags.HERO)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
            Box(Modifier.size(100.dp, 104.dp).clearAndSetSemantics {}, contentAlignment = Alignment.BottomCenter) {
                Box(
                    Modifier.size(92.dp, 20.dp).background(
                        Brush.radialGradient(listOf(colors.accent.copy(alpha = 0.22f), colors.accent.copy(alpha = 0f))),
                        RoundedCornerShape(percent = 50),
                    ),
                )
                MeCharacterArt(id, 92, Modifier.padding(bottom = 8.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(MeCharacterName.display(id), style = MaterialTheme.typography.titleLarge, color = colors.label)
                Text(
                    statusText,
                    style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                    color = when (kind) {
                        MeWearKind.Value -> colors.accent
                        MeWearKind.Failed -> colors.pending
                        MeWearKind.Loading -> colors.label2
                    },
                )
                Text(MeText.pickerCaption, style = MaterialTheme.typography.bodySmall, color = colors.label2)
            }
        }
    }
}

@Composable
private fun PickerTile(store: MeStore, id: String, openGachaMachine: () -> Unit, modifier: Modifier) {
    val isOn = store.equippedLoaded && id == store.equippedCharacterID
    val owned = store.isOwned(id)
    val giftOnly = store.isGiftOnly(id)
    val gachaOnly = store.isGachaOnly(id)
    val shardCost = store.gachaShardCost(id)
    val unlocked = store.isUnlocked(id)
    val name = MeCharacterName.display(id)
    val status = CharacterPickerRules.status(
        savingThis = store.savingCharacterID == id,
        isOn = isOn,
        owned = owned,
        giftOnly = giftOnly,
        gachaOnly = gachaOnly,
        shardCost = shardCost,
        price = store.price(id),
        balance = store.rubyBalance,
        unlocked = unlocked,
    )
    val label = if (unlocked) CharacterPickerRules.accessibilityText(name, status) else CharacterPickerRules.lockedLabel(name, giftOnly, gachaOnly, shardCost)
    MeCharacterTile(
        id = id,
        name = name,
        status = status,
        mark = if (isOn) MeCharacterTileMark.Equipped else MeCharacterTileMark.None,
        modifier = modifier
            .testTag(CharacterPickerTags.tile(id))
            .clearAndSetSemantics {
                contentDescription = label
                selected = isOn
            },
        enabled = store.savingCharacterID == null,
        onClick = {
            when (CharacterPickerRules.tap(store.showsGacha, owned, gachaOnly)) {
                CharacterPickerTap.OpenGachaMachine -> openGachaMachine()
                CharacterPickerTap.Choose -> store.chooseCharacter(id)
            }
        },
    )
}

/**
 * 캐릭터 타일(상점 · 고르기 공용): 받침(surface2) 위 그림 · 이름 · 상태 한 줄(착용 중 파랑 · 보유 회색 · 가격 RubyPrice · 얻는 길 반짝임 · 선물 잠김).
 * 상태 줄이 **무엇을 말하는지**는 [MeCharacterTileStatus.content](코어)가 정하고 여기서는 칠하기만 한다.
 */
@Composable
fun MeCharacterTile(
    id: String,
    name: String,
    status: MeCharacterTileStatus,
    mark: MeCharacterTileMark,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(AingDimens.tileRadius)
    Box(modifier) {
        Column(
            Modifier
                .fillMaxWidth()
                .clip(shape)
                .background(if (mark == MeCharacterTileMark.Picked) colors.accentTint else colors.surface)
                .then(if (mark == MeCharacterTileMark.Equipped) Modifier.border(2.dp, colors.accent, shape) else Modifier)
                .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
                .padding(8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Box(
                Modifier.fillMaxWidth().height(88.dp).background(colors.surface2, RoundedCornerShape(AingDimens.innerRadius)),
                contentAlignment = Alignment.Center,
            ) { MeCharacterArt(id, 76) }
            // 긴 이름("딸기 케이크 아잉이")은 0.8 배까지 줄여 한 줄에 넣는다(Swift minimumScaleFactor 0.8) — 그래도 넘치면 말줄임.
            val nameStyle = MaterialTheme.typography.bodyMedium.copy(
                fontWeight = FontWeight.SemiBold,
                color = if (mark == MeCharacterTileMark.Picked) colors.accent else colors.label,
            )
            // 줄 높이는 원래 글자 크기로 잡는다 — 줄인 이름의 타일만 낮아져 한 줄의 타일 높이가 갈리지 않게.
            Box(Modifier.heightIn(min = 22.dp), contentAlignment = Alignment.Center) {
                BasicText(
                    name,
                    style = nameStyle,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    autoSize = TextAutoSize.StepBased(minFontSize = nameStyle.fontSize * 0.8f, maxFontSize = nameStyle.fontSize, stepSize = 0.5.sp),
                )
            }
            Box(Modifier.heightIn(min = 20.dp), contentAlignment = Alignment.Center) { TileStatusLine(id, status) }
        }
        if (mark == MeCharacterTileMark.Equipped) {
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .offset(x = (-4).dp, y = 4.dp)
                    .size(22.dp)
                    .background(colors.surface, CircleShape)
                    .padding(2.dp)
                    .background(colors.accentFill, CircleShape),
                contentAlignment = Alignment.Center,
            ) { AingIcon(AppIcon.Check, contentDescription = null, size = 11.dp, tint = colors.onAccentFill) }
        }
    }
}

@Composable
private fun TileStatusLine(id: String, status: MeCharacterTileStatus) {
    val colors = AingTheme.colors
    val small = MaterialTheme.typography.bodySmall
    when (val content = status.content) {
        is MeCharacterTileStatus.Content.Ruby -> {
            val price = content.price.toInt()
            RubyPrice(price, RubyPriceRule.isShort(price, content.balance?.toInt()), LocalScreenArt.current.ruby(17f), gemSize = 17.dp)
        }
        is MeCharacterTileStatus.Content.Text -> Text(
            content.text,
            style = if (content.emphasized) small.copy(fontWeight = FontWeight.SemiBold) else small,
            color = if (content.emphasized) colors.accent else colors.label2,
        )
        is MeCharacterTileStatus.Content.Acquire -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Sparkle(CharacterManifest.Finish.of(id))
            ShrinkingLine(content.text, small.copy(color = colors.label2))
        }
        is MeCharacterTileStatus.Content.Locked -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            AingIcon(AppIcon.RedeemFill, contentDescription = null, size = 12.dp, tint = colors.label2)
            ShrinkingLine(content.text, small.copy(color = colors.label2))
        }
        MeCharacterTileStatus.Content.Spinner -> CircularProgressIndicator(Modifier.size(16.dp), color = colors.label2, strokeWidth = 2.dp)
    }
}

/** 한 줄 글자 — 0.75 배까지 줄여 넣고 그래도 넘치면 말줄임(Swift minimumScaleFactor 0.75). */
@Composable
private fun ShrinkingLine(text: String, style: androidx.compose.ui.text.TextStyle) {
    BasicText(
        text,
        style = style,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        autoSize = TextAutoSize.StepBased(minFontSize = style.fontSize * 0.75f, maxFontSize = style.fontSize, stepSize = 0.5.sp),
    )
}

/** 반짝임 빛깔(기호 갈래 — 글자 4.5:1 을 안 지키는 장식): 금 · 라이트 무지개 단색(짧은 기호에 그라데이션이 안 읽힌다) · 다크 무지개. */
object TileSparkle {
    fun solid(colors: AingColors, finish: CharacterManifest.Finish): androidx.compose.ui.graphics.Color? = when (finish) {
        CharacterManifest.Finish.rainbow -> if (colors.isDark) null else colors.rainbowStops[5]
        CharacterManifest.Finish.gold, CharacterManifest.Finish.standard,
        CharacterManifest.Finish.cakeStrawberry, CharacterManifest.Finish.cakeChoco -> colors.gold
    }
}

@Composable
private fun Sparkle(finish: CharacterManifest.Finish) {
    val colors = AingTheme.colors
    val solid = TileSparkle.solid(colors, finish)
    if (solid != null) {
        AingIcon(AppIcon.AutoAwesome, contentDescription = null, size = 12.dp, tint = solid)
    } else {
        // 다크 무지개: 기호 모양 안에만 무지개를 칠한다(오프스크린 합성 + SrcIn).
        AingIcon(
            AppIcon.AutoAwesome,
            contentDescription = null,
            size = 12.dp,
            tint = colors.label,
            modifier = Modifier
                .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
                .drawWithContent {
                    drawContent()
                    drawRect(Brush.linearGradient(colors.rainbowStops), blendMode = BlendMode.SrcIn)
                },
        )
    }
}

/**
 * 캐릭터 그림: 이 빌드가 아는 캐릭터는 공용 초상 원본(전신 — 무대·위젯과 같은 그림). 그림이 없으면 물음표 자리표시
 * (아잉으로 **지어내지 않는다** — 서버가 새 캐릭터를 주면 이름은 id, 그림은 물음표).
 */
@Composable
fun MeCharacterArt(id: String, size: Int, modifier: Modifier = Modifier) {
    val art = LocalScreenArt.current.portrait(id, null)
    if (art != null) {
        CharacterPortrait(art, CharacterMood.Plain, size.dp, modifier, framed = false)
    } else {
        Box(modifier.size(size.dp).semantics {}, contentAlignment = Alignment.Center) {
            AingIcon(AppIcon.ContactSupport, contentDescription = null, size = (size * 0.7f).dp, tint = AingTheme.colors.label2)
        }
    }
}
