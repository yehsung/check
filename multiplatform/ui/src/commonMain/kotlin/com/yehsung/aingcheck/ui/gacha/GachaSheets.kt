// 원본: Sources/CheckMobileKit/Me/MeGachaViews.swift @ 3bd04bd (MeGachaOddsSheet · MeGachaExchangeSheet)
//
// "확률 보기" 시트(서버 표 그대로 — 순서까지)와 조각 교환 시트. 시트를 띄우는 그릇(ModalBottomSheet · 목적지 대화상자)은 호출부가 고른다 —
// 여기는 내용만 그린다. **합계 줄은 두지 않는다** — 화면 표시는 한 자리 반올림이라 더하면 100.1% 가 된다. 표가 불완전하면 카드가 아예 안
// 서므로(showsGacha) 여기 오는 표는 늘 합 100% 다. 확률 숫자는 서버 값(GachaOddsRow.percentText)만 그린다.
package com.yehsung.aingcheck.ui.gacha

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.character.CharacterManifest
import com.yehsung.aingcheck.core.rules.gacha.GachaExchangeAvailability
import com.yehsung.aingcheck.core.rules.gacha.GachaExchangeRow
import com.yehsung.aingcheck.core.rules.gacha.GachaOddsRow
import com.yehsung.aingcheck.core.rules.gacha.GachaText
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.exchangeShards
import com.yehsung.aingcheck.core.stores.me.exchangeSheetDidDisappear
import com.yehsung.aingcheck.core.stores.me.gachaExchangeRows
import com.yehsung.aingcheck.core.stores.me.gachaOddsRows
import com.yehsung.aingcheck.core.stores.me.gachaShards
import com.yehsung.aingcheck.ui.components.RubyPrice
import com.yehsung.aingcheck.ui.shop.MeButton
import com.yehsung.aingcheck.ui.shop.MeButtonKind
import com.yehsung.aingcheck.ui.shop.MeButtonSize
import com.yehsung.aingcheck.ui.shop.MeCharacterArt
import com.yehsung.aingcheck.ui.shop.MeGroupRow
import com.yehsung.aingcheck.ui.shop.MeInlineNotice
import com.yehsung.aingcheck.ui.shop.MeInsetGroup
import com.yehsung.aingcheck.ui.shop.MeNoticeKind
import com.yehsung.aingcheck.ui.shop.MeSheetHeader
import com.yehsung.aingcheck.ui.shop.MeType
import com.yehsung.aingcheck.ui.shop.MeType.digits
import com.yehsung.aingcheck.ui.shop.rememberRuby
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** "확률 보기" 시트 내용(머리 ✕ · 표 · 규칙 한 줄). [scrolls] 가 거짓이면 스크롤 없이 다 그린다(스냅숏). */
@Composable
fun MeGachaOddsSheetContent(store: MeStore, onClose: () -> Unit, modifier: Modifier = Modifier, scrolls: Boolean = true) {
    val c = AingTheme.colors
    val rows = store.gachaOddsRows
    Column(modifier.fillMaxWidth().background(c.background)) {
        MeSheetHeader(GachaText.oddsTitle, subtitle = store.gachaInfo?.price?.let { GachaText.pullButton(it) }, onClose = onClose)
        Column(
            Modifier
                .fillMaxWidth()
                .then(if (scrolls) Modifier.verticalScroll(rememberScrollState()) else Modifier)
                .padding(start = AingDimens.sideMargin, end = AingDimens.sideMargin, top = AingDimens.space2, bottom = AingDimens.space6),
            verticalArrangement = Arrangement.spacedBy(AingDimens.space3),
        ) {
            MeInsetGroup {
                MeGroupRow(Modifier.clearAndSetSemantics { }, dividerInset = null, minHeight = 32.dp, verticalPadding = 8.dp) {
                    val head = MeType.caption.copy(fontWeight = FontWeight.SemiBold)
                    Text(MeText.gachaOddsColumnName, style = head, color = c.label2, modifier = Modifier.weight(1f))
                    Text(MeText.gachaOddsColumnPrice, style = head, color = c.label2, textAlign = TextAlign.End, modifier = Modifier.widthIn(min = 72.dp))
                    Text(MeText.gachaOddsColumnPercent, style = head, color = c.label2, textAlign = TextAlign.End, modifier = Modifier.widthIn(min = 48.dp))
                }
                rows.forEachIndexed { index, row -> OddsRow(row, isLast = index == rows.lastIndex) }
            }
            Text(GachaText.oddsFootnote, style = MeType.footnote, color = c.label2, modifier = Modifier.padding(horizontal = AingDimens.space1))
        }
    }
}

@Composable
private fun OddsRow(row: GachaOddsRow, isLast: Boolean) {
    val c = AingTheme.colors
    // 희귀 둘(황금 · 무지개)은 같은 급으로 강조한다 — 이름을 굵게, 이름·확률을 그 빛깔로. 가름은 MeText.gachaOddsEmphasized(= finish.isRare).
    val emphasized = MeText.gachaOddsEmphasized(row)
    val weight = if (emphasized) FontWeight.Bold else FontWeight.SemiBold
    val base = MeType.subheadline.copy(fontWeight = weight)
    MeGroupRow(
        Modifier.clearAndSetSemantics {
            contentDescription = "${row.name}, ${MeText.gachaOddsColumnPrice} ${row.priceText}, ${MeText.gachaOddsColumnPercent} ${row.percentText}"
        },
        dividerInset = if (isLast) null else AingDimens.cardPadding + 40.dp + AingDimens.space3,
    ) {
        Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) { MeCharacterArt(row.characterID, 40.dp) }
        Text(row.name, style = GachaPaint.styled(base, GachaPaint.ink(row.finish, row.name, c.label)), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Box(Modifier.widthIn(min = 72.dp, max = 104.dp), contentAlignment = Alignment.CenterEnd) { PriceCell(row) }
        // 확률(두세 글자) — 짧은 글자라 무지개도 단색이다(AingTextPaint 규칙).
        Text(
            row.percentText,
            style = GachaPaint.styled(base.digits(), GachaPaint.ink(row.finish, row.percentText, c.label)),
            textAlign = TextAlign.End,
            modifier = Modifier.widthIn(min = 48.dp),
        )
    }
}

@Composable
private fun PriceCell(row: GachaOddsRow) {
    val c = AingTheme.colors
    val price = row.shopPrice
    if (price != null) {
        RubyPrice(price.toInt(), isShort = false, art = rememberRuby(14f), gemSize = 14.dp, fontSize = 13f)
    } else {
        // 희귀 줄(금 · 무지개)은 "뽑기 또는 조각 20개"처럼 길 수 있다 — 두 줄까지 접고 오른쪽에 붙인다(글자를 줄여 숨기지 않는다).
        Text(row.priceText, style = MeType.footnote, color = c.label2, textAlign = TextAlign.End, maxLines = 2)
    }
}

/**
 * 조각 교환 시트 내용: 서버 교환표 그대로(**코어가 준 순서** — 황금 → 무지개 → 서버 순서) · 줄마다 그림 · 이름 · 값 · [교환](모자라면 잠김 ·
 * 가졌으면 "보유"). 교환은 확인 대화상자의 [교환하기] 로만 나간다(카드를 눌러 바로 쓰이지 않는다).
 */
@Composable
fun MeGachaExchangeSheetContent(store: MeStore, onClose: () -> Unit, modifier: Modifier = Modifier, scrolls: Boolean = true) {
    val c = AingTheme.colors
    val rows = store.gachaExchangeRows
    var confirming by remember { mutableStateOf<GachaExchangeRow?>(null) }
    DisposableEffect(store) { onDispose { store.exchangeSheetDidDisappear() } }
    Column(modifier.fillMaxWidth().background(c.background)) {
        MeSheetHeader(GachaText.exchangeTitle, subtitle = store.gachaShards?.let { GachaText.shards(it) }, onClose = onClose)
        Column(
            Modifier
                .fillMaxWidth()
                .then(if (scrolls) Modifier.verticalScroll(rememberScrollState()) else Modifier)
                .padding(start = AingDimens.sideMargin, end = AingDimens.sideMargin, top = AingDimens.space2, bottom = AingDimens.space6),
            verticalArrangement = Arrangement.spacedBy(AingDimens.space3),
        ) {
            store.exchangeNotice?.let { MeInlineNotice(it, if (store.isExchangeNoticeError) MeNoticeKind.Warning else MeNoticeKind.Info) }
            MeInsetGroup {
                rows.forEachIndexed { index, row ->
                    MeGroupRow(dividerInset = if (index == rows.lastIndex) null else AingDimens.cardPadding + 44.dp + AingDimens.space3) {
                        ExchangeRow(store, row) { confirming = row }
                    }
                }
            }
            Text(GachaText.oddsFootnote, style = MeType.footnote, color = c.label2, modifier = Modifier.padding(horizontal = AingDimens.space1))
        }
    }
    val row = confirming
    val cost = row?.availability?.cost
    if (row != null && cost != null) {
        AlertDialog(
            onDismissRequest = { confirming = null },
            title = { Text(MeText.exchangeConfirmTitle(row.name, cost)) },
            text = { store.gachaShards?.let { Text(MeText.exchangeConfirmMessage(cost, it)) } },
            confirmButton = {
                TextButton(onClick = { confirming = null; store.exchangeShards(row.characterID) }) { Text(MeText.exchangeAction) }
            },
            dismissButton = { TextButton(onClick = { confirming = null }) { Text("취소") } },
        )
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.ExchangeRow(store: MeStore, row: GachaExchangeRow, onExchange: () -> Unit) {
    val c = AingTheme.colors
    val finish = CharacterManifest.Finish.of(row.characterID)
    Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) { MeCharacterArt(row.characterID, 44.dp) }
    Column(
        Modifier.weight(1f).clearAndSetSemantics { contentDescription = MeText.exchangeRowAccessibility(row.name, row.availability) },
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        val base = MeType.subheadline.copy(fontWeight = if (finish.isRare) FontWeight.Bold else FontWeight.SemiBold)
        Text(row.name, style = GachaPaint.styled(base, GachaPaint.ink(finish, row.name, c.label)), maxLines = 1, overflow = TextOverflow.Ellipsis)
        row.availability.cost?.let { cost ->
            Text(costLine(row.availability, cost), style = MeType.footnote.digits(), color = if (row.availability.canExchange) c.label2 else c.label3Text)
        }
    }
    when {
        store.exchangingID == row.characterID ->
            Box(Modifier.size(AingDimens.minimumTarget), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) }
        row.availability == GachaExchangeAvailability.owned -> Text(GachaText.owned, style = MeType.footnote, color = c.label2)
        else -> MeButton(
            GachaText.exchangeButton, kind = MeButtonKind.Tinted, size = MeButtonSize.Sm,
            enabled = row.availability.canExchange && store.exchangingID == null,
            contentDescription = MeText.exchangeRowAccessibility(row.name, row.availability), onClick = onExchange,
        )
    }
}

/** "조각 5개" · 모자라면 "조각 5개 · 조각 2개 더 필요해요". */
private fun costLine(availability: GachaExchangeAvailability, cost: Long): String =
    if (availability is GachaExchangeAvailability.short) "${GachaText.shardCost(cost)} · ${GachaText.shardShortfall(availability.missing)}"
    else GachaText.shardCost(cost)

/** 확률 시트 그릇(전체 높이 — 표 전체가 한 번에 보이게. 중간 높이면 공개한 확률이 반만 보인다). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MeGachaOddsSheetHost(store: MeStore, onDismiss: () -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = AingTheme.colors.background,
        dragHandle = null,
    ) { MeGachaOddsSheetContent(store, onClose = onDismiss) }
}

/** 조각 교환 시트 그릇. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MeGachaExchangeSheetHost(store: MeStore, onDismiss: () -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = AingTheme.colors.background,
        dragHandle = null,
    ) { MeGachaExchangeSheetContent(store, onClose = onDismiss) }
}
