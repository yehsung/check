// 원본: Sources/CheckMobileKit/Me/MeCakeGiftViews.swift @ 3bd04bd (MeCakeGiftSheetView · MeCakeGiftReopenRow)
//
// 생일 선물 축하 시트(폰 1.0.14 — 맥 0.3.66 축하 창의 짝): 두 초상(전신 — 장식이 케이크의 핵심이라 원에 가두지 않는다) → 고르기 →
// [이걸로 받을게요] → 받은 뒤 "○○를 받았어요!" + [지금 입기] [닫기]. 실패하면 한 줄 안내를 보이고 다시 누르게 한다.
// 상태 · 판정은 스토어(W2-c MeStoreCakeGift), 문구는 코어(rules CakeGiftText — 맥과 같은 글자)다. 이 파일은 그리기만 한다.
// 사용자 결정(기억 cake-aing-decisions): 딸기 · 초코 둘 중 **하나를 골라** 받는다 · 구매·뽑기·조각 불가 · 받으면 축하(고르기) 창 한 번.
package com.yehsung.aingcheck.ui.shop

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.character.gift.CakeGiftText
import com.yehsung.aingcheck.core.stores.me.MeCakeGiftSheet
import com.yehsung.aingcheck.core.stores.me.MeCharacterName
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.cakeGiftSheetDidAppear
import com.yehsung.aingcheck.core.stores.me.cakeGiftSheetDidDisappear
import com.yehsung.aingcheck.core.stores.me.confirmCakeGift
import com.yehsung.aingcheck.core.stores.me.dismissCakeGiftSheet
import com.yehsung.aingcheck.core.stores.me.reopenCakeGift
import com.yehsung.aingcheck.core.stores.me.selectCakeGiftOption
import com.yehsung.aingcheck.core.stores.me.showsCakeGiftReopen
import com.yehsung.aingcheck.core.stores.me.wearReceivedCakeGift
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

object CakeGiftTags {
    fun option(id: String) = "cakeGift.option.$id"
    const val CONFIRM = "cakeGift.confirm"
}

/**
 * 축하 시트를 띄우는 그릇 — 어느 탭에 있든 뜬다(조립이 탭 막대 위에 둔다 — assembly.md). 스토어의 [MeStore.cakeGiftSheet] 가 null 이 아니면 선다.
 * 받는 중에는 끌어 닫지 못한다(결과를 모른 채 닫히면 수령이 성공해도 받은 뒤 화면 · [지금 입기]가 안 선다 — 스토어도 따로 막는다).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MeCakeGiftSheetHost(store: MeStore) {
    val sheet = store.cakeGiftSheet ?: return
    ModalBottomSheet(
        onDismissRequest = { store.dismissCakeGiftSheet() },
        // 상태 판정은 부를 때의 스토어 값으로(시트 상태는 처음 람다를 쥔다 — 그때의 '받는 중'을 굳히면 안 된다).
        sheetState = rememberModalBottomSheetState(
            skipPartiallyExpanded = true,
            confirmValueChange = { store.cakeGiftSheet?.phase != MeCakeGiftSheet.Phase.Claiming },
        ),
        containerColor = AingTheme.colors.surface,
    ) { MeCakeGiftSheetContent(store, sheet) }
}

/** 시트 내용. [item] = 그릇이 받은 마지막 값 — 내려가는 동안에도 쥔다(스토어 값은 이미 null 이라 그것만 보면 판이 텅 빈다). */
@Composable
fun MeCakeGiftSheetContent(store: MeStore, item: MeCakeGiftSheet, modifier: Modifier = Modifier, scrolls: Boolean = true) {
    val live = store.cakeGiftSheet
    val sheet = if (live != null && live.id == item.id) live else item
    LaunchedEffect(item.id) { store.cakeGiftSheetDidAppear() }
    DisposableEffect(item.id) { onDispose { store.cakeGiftSheetDidDisappear() } }
    val c = AingTheme.colors
    Column(modifier.fillMaxWidth().background(c.surface)) {
        MeSheetHeader("", closeEnabled = sheet.phase != MeCakeGiftSheet.Phase.Claiming, onClose = { store.dismissCakeGiftSheet() })
        Column(
            Modifier
                .fillMaxWidth()
                .then(if (scrolls) Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()) else Modifier)
                .padding(horizontal = AingDimens.sideMargin)
                .padding(bottom = AingDimens.space4),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(AingDimens.space4),
        ) {
            when (val phase = sheet.phase) {
                MeCakeGiftSheet.Phase.Choosing, MeCakeGiftSheet.Phase.Claiming -> Choosing(store, sheet)
                is MeCakeGiftSheet.Phase.Received -> Received(phase.characterID)
                MeCakeGiftSheet.Phase.Closed -> {
                    Heading(CakeGiftText.title, null)
                    sheet.notice?.let { MeInlineNotice(it, MeNoticeKind.Info) }
                }
            }
        }
        BottomBar(store, sheet)
    }
}

@Composable
private fun Choosing(store: MeStore, sheet: MeCakeGiftSheet) {
    val c = AingTheme.colors
    Heading(CakeGiftText.title, CakeGiftText.body)
    sheet.gift.note?.let { Text(it, style = MeType.subheadline, color = c.label2, textAlign = TextAlign.Center) }
    Row(horizontalArrangement = Arrangement.spacedBy(AingDimens.space3), verticalAlignment = Alignment.Top) {
        for (id in sheet.gift.options) {
            OptionCard(store, id, isSelected = sheet.selection == id, isLocked = sheet.phase != MeCakeGiftSheet.Phase.Choosing, Modifier.weight(1f))
        }
    }
    sheet.notice?.let { MeInlineNotice(it, MeNoticeKind.Warning) }
}

@Composable
private fun OptionCard(store: MeStore, id: String, isSelected: Boolean, isLocked: Boolean, modifier: Modifier) {
    val c = AingTheme.colors
    val shape = RoundedCornerShape(AingDimens.tileRadius)
    val name = MeCharacterName.display(id)
    Box(
        modifier
            .testTag(CakeGiftTags.option(id))
            .clickable(enabled = !isLocked, role = Role.Button) { store.selectCakeGiftOption(id) }
            .clearAndSetSemantics {
                contentDescription = name
                role = Role.Button
                selected = isSelected
            },
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .background(c.surface, shape)
                .then(if (isSelected) Modifier.background(c.accentTint, shape) else Modifier)
                .border(if (isSelected) 2.dp else 1.dp, if (isSelected) c.accent else c.separator, shape)
                .padding(AingDimens.space2),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
        ) {
            Box(
                Modifier.fillMaxWidth().background(c.surface2, RoundedCornerShape(AingDimens.innerRadius)).padding(vertical = AingDimens.space2),
                contentAlignment = Alignment.Center,
            ) { MeCharacterArt(id, 132.dp) }
            Text(
                name, style = MeType.subheadline.copy(fontWeight = FontWeight.SemiBold), color = if (isSelected) c.accent else c.label,
                textAlign = TextAlign.Center, maxLines = 2,
            )
        }
        if (isSelected) {
            Box(
                Modifier.align(Alignment.TopEnd).offset(x = (-6).dp, y = 6.dp).size(24.dp).background(c.accentFill, CircleShape),
                contentAlignment = Alignment.Center,
            ) { AingIcon(AppIcon.Check, contentDescription = null, size = 14.dp, tint = c.onAccentFill) }
        }
    }
}

@Composable
private fun Received(id: String) {
    val c = AingTheme.colors
    Box(
        Modifier.padding(top = AingDimens.space4).size(170.dp, 170.dp).drawBehind {
            val w = 150.dp.toPx()
            val h = 28.dp.toPx()
            drawOval(
                Brush.radialGradient(listOf(c.accent.copy(alpha = 0.22f), Color.Transparent), center = Offset(size.width / 2, size.height - h / 2), radius = w / 2),
                topLeft = Offset((size.width - w) / 2, size.height - h), size = Size(w, h),
            )
        }.clearAndSetSemantics { },
        contentAlignment = Alignment.BottomCenter,
    ) {
        // 초상 원본은 192px 다 — 너무 키우면 흐리다. 나 탭 무대(132)와 비슷한 크기로.
        MeLiveOrPortrait(id, 144.dp, Modifier.padding(bottom = 10.dp))
    }
    Heading(CakeGiftText.received(MeCharacterName.display(id)), null)
}

@Composable
private fun Heading(title: String, body: String?) {
    val c = AingTheme.colors
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        Text(title, style = MeType.title2, color = c.label, textAlign = TextAlign.Center, modifier = Modifier.semantics { heading() })
        if (body != null) Text(body, style = MeType.body, color = c.label2, textAlign = TextAlign.Center)
    }
}

@Composable
private fun BottomBar(store: MeStore, sheet: MeCakeGiftSheet) {
    Column(
        Modifier.fillMaxWidth().padding(start = AingDimens.sideMargin, end = AingDimens.sideMargin, top = AingDimens.space2, bottom = AingDimens.space3),
        verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
    ) {
        when (sheet.phase) {
            MeCakeGiftSheet.Phase.Choosing, MeCakeGiftSheet.Phase.Claiming -> MeButton(
                CakeGiftText.confirmButton, Modifier.testTag(CakeGiftTags.CONFIRM), kind = MeButtonKind.Filled, size = MeButtonSize.Lg, fillsWidth = true,
                isBusy = sheet.phase == MeCakeGiftSheet.Phase.Claiming, enabled = sheet.canConfirm,
            ) { store.confirmCakeGift() }
            is MeCakeGiftSheet.Phase.Received -> {
                MeButton(CakeGiftText.wearNowButton, kind = MeButtonKind.Filled, size = MeButtonSize.Lg, fillsWidth = true) { store.wearReceivedCakeGift() }
                MeButton(CakeGiftText.closeButton, kind = MeButtonKind.Tinted, size = MeButtonSize.Lg, fillsWidth = true) { store.dismissCakeGiftSheet() }
            }
            MeCakeGiftSheet.Phase.Closed ->
                MeButton(CakeGiftText.closeButton, kind = MeButtonKind.Tinted, size = MeButtonSize.Lg, fillsWidth = true) { store.dismissCakeGiftSheet() }
        }
    }
}

/** 고르지 않고 닫은 열린 선물 — 나 탭 무대 카드 바로 아래에 **수령할 때까지** 선다("생일 선물이 도착했어요" [고르기]). 자리는 W3-b 나 탭 루트. */
@Composable
fun MeCakeGiftReopenRow(store: MeStore, modifier: Modifier = Modifier) {
    if (!store.showsCakeGiftReopen) return
    val c = AingTheme.colors
    MeCard(modifier) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
            Box(Modifier.size(40.dp).background(c.accentTint, RoundedCornerShape(10.dp)).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
                Text("🎂", style = MeType.title3)
            }
            Text(CakeGiftText.reopenTitle, style = MeType.body.copy(fontWeight = FontWeight.SemiBold), color = c.label, modifier = Modifier.weight(1f))
            // 틴트 — 나 탭에는 이미 채운 버튼이 있다(채운 버튼은 화면당 하나). [고르기]는 서버에 다시 묻고 연다(묻는 동안 단추가 돈다).
            MeButton(CakeGiftText.reopenButton, kind = MeButtonKind.Tinted, size = MeButtonSize.Md, isBusy = store.cakeGiftReopening) { store.reopenCakeGift() }
        }
    }
}

