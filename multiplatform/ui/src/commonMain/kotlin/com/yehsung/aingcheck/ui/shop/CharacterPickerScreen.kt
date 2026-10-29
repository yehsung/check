// 원본: Sources/CheckMobileKit/Me/MeCharacterViews.swift:64-684 @ 3bd04bd (MeCharacterPickerView)
//
// 캐릭터 고르기: 위에 지금 입은 캐릭터를 크게(무엇이 바뀌는지) · 아래 상점과 같은 타일(착용 = 파랑 테두리 + 체크 · 보유 · 가격) · [상점 가기].
// 머리 그림은 살아 있는 미리보기 자리(W5-c — [LocalLiveCharacterPreview])다. 안 꽂혀 있으면 초상.
package com.yehsung.aingcheck.ui.shop

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.unit.dp
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
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

object PickerTags {
    const val HERO = "picker.hero"
    fun tile(id: String) = "picker.tile.$id"
}

/**
 * @param onOpenShop [상점 가기].
 * @param onOpenMachine 안 가진 뽑기 전용(황금 · 무지개) 타일을 누르면 기계를 연다(뽑기가 열린 서버일 때만).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MeCharacterPickerScreen(store: MeStore, onBack: (() -> Unit)?, onOpenShop: () -> Unit, onOpenMachine: () -> Unit, modifier: Modifier = Modifier) {
    val c = AingTheme.colors
    LaunchedEffect(store) { store.charactersDidAppear() }
    Scaffold(
        modifier,
        containerColor = c.background,
        topBar = {
            TopAppBar(
                title = { Text(MeText.pickerTitle, style = MeType.headline, color = c.label) },
                navigationIcon = { if (onBack != null) BackButton(onBack) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.background),
            )
        },
    ) { inner -> MeCharacterPickerContent(store, onOpenShop, onOpenMachine, contentPadding = inner) }
}

@Composable
fun MeCharacterPickerContent(
    store: MeStore,
    onOpenShop: () -> Unit,
    onOpenMachine: () -> Unit,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(0.dp),
    scrolls: Boolean = true,
) {
    Column(
        modifier
            .fillMaxWidth()
            .then(if (scrolls) Modifier.fillMaxSize().verticalScroll(rememberScrollState()) else Modifier)
            .padding(contentPadding)
            .padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.rowSpacing),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
    ) {
        Hero(store)
        store.characterNotice?.let { MeInlineNotice(it, if (store.isCharacterNoticeError) MeNoticeKind.Warning else MeNoticeKind.Info) }
        val ids = MeCharacterTileRules.ordered(store.pickerIDs, store::isOwned)
        MeSectionHeader(
            MeText.charactersTitle, MeText.ownedCount(ids.count(store::isOwned), ids.size),
            Modifier.padding(start = AingDimens.titleMargin - AingDimens.sideMargin, end = AingDimens.titleMargin - AingDimens.sideMargin, top = AingDimens.space1),
        )
        TileGrid(ids) { id -> PickerTile(store, id, onOpenMachine) }
        MeButton(MeText.goToShop, Modifier.padding(top = AingDimens.space1), icon = AppIcon.ShoppingBag, kind = MeButtonKind.Tinted, size = MeButtonSize.Md, fillsWidth = true, onClick = onOpenShop)
    }
}

/** 지금 입은 캐릭터 크게 + 이 캐릭터가 어디에 나오는지. */
@Composable
private fun Hero(store: MeStore) {
    val c = AingTheme.colors
    val id = store.equippedCharacterID
    MeCard(Modifier.testTag(PickerTags.HERO)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
            Box(
                Modifier.size(100.dp, 104.dp).drawBehind {
                    // 바닥 빛(파랑 22% → 투명 타원)
                    val w = 92.dp.toPx()
                    val h = 20.dp.toPx()
                    drawOval(
                        Brush.radialGradient(listOf(c.accent.copy(alpha = 0.22f), Color.Transparent), center = Offset(size.width / 2, size.height - h / 2), radius = w / 2),
                        topLeft = Offset((size.width - w) / 2, size.height - h), size = Size(w, h),
                    )
                }.clearAndSetSemantics { },
                contentAlignment = Alignment.BottomCenter,
            ) { MeLiveOrPortrait(id, 92.dp, Modifier.padding(bottom = 8.dp)) }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(MeCharacterName.display(id), style = MeType.title3, color = c.label)
                Text(
                    if (store.equippedLoaded) MeText.equipped else if (store.equippedLoadFailed) MeText.equippedLoadFailed else MeText.loading,
                    style = MeType.subheadline.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold),
                    color = if (store.equippedLoaded) c.accent else if (store.equippedLoadFailed) c.pending else c.label2,
                )
                Text(MeText.pickerCaption, style = MeType.footnote, color = c.label2)
            }
        }
    }
}

@Composable
private fun PickerTile(store: MeStore, id: String, onOpenMachine: () -> Unit) {
    val isOn = store.equippedLoaded && id == store.equippedCharacterID
    val unlocked = store.isUnlocked(id)
    val name = MeCharacterName.display(id)
    val status: MeCharacterTileStatus = when {
        store.savingCharacterID == id -> MeCharacterTileStatus.Busy
        isOn -> MeCharacterTileStatus.Equipped
        store.isOwned(id) -> MeCharacterTileStatus.Owned
        // 고르기에는 가진 사람에게만 서므로(pickerIDs) 거의 닿지 않는다 — 착용값이 소유보다 먼저 도착한 창의 안전망.
        store.isGiftOnly(id) -> MeCharacterTileStatus.GiftOnly
        store.isGachaOnly(id) -> MeCharacterTileStatus.GachaOnly(store.gachaShardCost(id))
        else -> store.price(id)?.let { MeCharacterTileStatus.Price(it, store.rubyBalance) }
            ?: if (unlocked) MeCharacterTileStatus.None else MeCharacterTileStatus.UnknownPrice
    }
    val lockedLabel = when {
        store.isGiftOnly(id) -> "$name, 잠김 — ${CakeGiftText.lockedCaption}"
        store.isGachaOnly(id) -> "$name, 잠김 — ${MeText.gachaAcquirePhrase(store.gachaShardCost(id))}"
        else -> "$name, 잠김 — 상점에서 사기"
    }
    MeCharacterTile(
        id, name, status, if (isOn) MeTileMark.Equipped else MeTileMark.None,
        Modifier
            .testTag(PickerTags.tile(id))
            .clickable(enabled = store.savingCharacterID == null, role = Role.Button) {
                if (store.showsGacha && !store.isOwned(id) && store.isGachaOnly(id)) onOpenMachine() else store.chooseCharacter(id)
            }
            .clearAndSetSemantics {
                contentDescription = if (unlocked) MeCharacterTileRules.accessibilityText(name, status) else lockedLabel
                role = Role.Button
                selected = isOn
            },
    )
}

