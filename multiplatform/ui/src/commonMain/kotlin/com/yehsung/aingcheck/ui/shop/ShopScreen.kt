// 원본: Sources/CheckMobileKit/Me/MeCharacterViews.swift:64-684 @ 3bd04bd (MeShopView)
//
// 상점(캐릭터만 · 시안 B 11). 카드를 누르면 **고르기만** 하고, 아래 막대의 [보석 30 사기] → 확인 대화상자 → `confirmPurchase()` 로만 산다.
// 잔량은 오른쪽 위 알약 하나 · 가격은 맨 보석 + 숫자(모자라면 흐림 — 자물쇠·진홍 없음) · 고른 캐릭터의 두 표정 미리 보기.
// 캐릭터 머리 **위**에 뽑기 카드(MeGachaCard)가 선다 — 서버가 확률표 합 100% 인 `shop_state.gacha` 를 줄 때만(W2-c showsGacha).
// [뽑기] 와 뽑기 전용 타일(황금 · 무지개)이 기계를 연다([onOpenMachine] — Android 는 전체 화면 목적지, 조립 K11).
package com.yehsung.aingcheck.ui.shop

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.me.MeCharacterCards
import com.yehsung.aingcheck.core.stores.me.MeCharacterName
import com.yehsung.aingcheck.core.stores.me.MeCharacterTileStatus
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.canConfirmPurchase
import com.yehsung.aingcheck.core.stores.me.charactersDidAppear
import com.yehsung.aingcheck.core.stores.me.confirmPurchase
import com.yehsung.aingcheck.core.stores.me.equippedCharacterID
import com.yehsung.aingcheck.core.stores.me.gachaShardCost
import com.yehsung.aingcheck.core.stores.me.isGachaOnly
import com.yehsung.aingcheck.core.stores.me.isGiftOnly
import com.yehsung.aingcheck.core.stores.me.isOwned
import com.yehsung.aingcheck.core.stores.me.loadShop
import com.yehsung.aingcheck.core.stores.me.price
import com.yehsung.aingcheck.core.stores.me.selectShopItem
import com.yehsung.aingcheck.core.stores.me.shopBarDetail
import com.yehsung.aingcheck.core.stores.me.shopDidDisappear
import com.yehsung.aingcheck.core.stores.me.shopRows
import com.yehsung.aingcheck.core.stores.me.shopSelectionPrice
import com.yehsung.aingcheck.core.stores.me.showsGacha
import com.yehsung.aingcheck.ui.components.RubyBalanceChip
import com.yehsung.aingcheck.ui.components.RubyChipStyle
import com.yehsung.aingcheck.ui.components.RubyIcon
import com.yehsung.aingcheck.ui.gacha.MeGachaCard
import com.yehsung.aingcheck.ui.gacha.MeGachaExchangeSheetHost
import com.yehsung.aingcheck.ui.gacha.MeGachaOddsSheetHost
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.shop.MeType.digits
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

object ShopTags {
    const val SCREEN = "shop.screen"
    fun tile(id: String) = "shop.tile.$id"
    const val BUY = "shop.buy"
}

/**
 * @param onBack 뒤로(null 이면 막대에 뒤로 단추가 없다).
 * @param onOpenMachine 캡슐 뽑기 기계를 연다(전체 화면).
 * @param onOpenOdds 확률 표를 연다. null 이면 이 화면이 시트를 띄운다.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MeShopScreen(
    store: MeStore,
    onBack: (() -> Unit)?,
    onOpenMachine: () -> Unit,
    modifier: Modifier = Modifier,
    onOpenOdds: (() -> Unit)? = null,
) {
    val c = AingTheme.colors
    var confirming by remember { mutableStateOf(false) }
    var showsOdds by remember { mutableStateOf(false) }
    var showsExchange by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(store) { store.charactersDidAppear() }
    DisposableEffect(store) { onDispose { store.shopDidDisappear() } }

    Scaffold(
        modifier.testTag(ShopTags.SCREEN),
        containerColor = c.background,
        topBar = {
            TopAppBar(
                title = { Text(MeText.shopTitle, style = MeType.headline, color = c.label) },
                navigationIcon = { if (onBack != null) BackButton(onBack) },
                actions = { RubyBalanceChip(store.rubyBalance, rememberRuby(22f), Modifier.padding(end = AingDimens.space2), style = RubyChipStyle.Toolbar) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.background),
            )
        },
        bottomBar = { PurchaseBar(store) { confirming = true } },
    ) { inner ->
        MeShopContent(
            store,
            onOpenMachine = onOpenMachine,
            onOpenOdds = onOpenOdds ?: { showsOdds = true },
            onOpenExchange = { showsExchange = true },
            onRetry = { scope.launch { store.loadShop() } },
            contentPadding = inner,
        )
    }
    if (showsOdds) MeGachaOddsSheetHost(store) { showsOdds = false }
    if (showsExchange) MeGachaExchangeSheetHost(store) { showsExchange = false }
    if (confirming) {
        val price = store.shopSelectionPrice
        val balance = store.rubyBalance
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text(MeText.purchaseConfirmTitle(store.shopSelection?.let(MeCharacterName::display) ?: "")) },
            text = { if (price != null && balance != null) Text(MeText.purchaseConfirmMessage(price, balance)) },
            confirmButton = { TextButton(onClick = { confirming = false; store.confirmPurchase() }) { Text(MeText.buyAction) } },
            dismissButton = { TextButton(onClick = { confirming = false }) { Text("취소") } },
        )
    }
}

/** 상점 본문(막대 · 시트 없이 — 스냅숏이 이것만 그린다). */
@Composable
fun MeShopContent(
    store: MeStore,
    onOpenMachine: () -> Unit,
    onOpenOdds: () -> Unit,
    onOpenExchange: () -> Unit,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(0.dp),
    scrolls: Boolean = true,
) {
    val c = AingTheme.colors
    Column(
        modifier
            .fillMaxWidth()
            .then(if (scrolls) Modifier.fillMaxSize().verticalScroll(rememberScrollState()) else Modifier)
            .padding(contentPadding)
            .padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.rowSpacing),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
    ) {
        Text(MeText.shopLede, style = MeType.footnote, color = c.label2, modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin))
        if (store.shopState.hasFailed && !store.shopState.hasLoaded) {
            MeCard { MeLoadFailureRow(MeText.shopFailed, isRetrying = store.shopState.isLoading, retry = onRetry) }
        }
        if (store.showsGacha) MeGachaCard(store, onPull = onOpenMachine, onOdds = onOpenOdds, onExchange = onOpenExchange)
        val ids = tileIDs(store)
        MeSectionHeader(
            MeText.charactersTitle, MeText.ownedCount(ids.count(store::isOwned), ids.size),
            Modifier.padding(start = AingDimens.titleMargin - AingDimens.sideMargin, end = AingDimens.titleMargin - AingDimens.sideMargin, top = AingDimens.space1),
        )
        TileGrid(ids) { id -> ShopTile(store, id, onOpenMachine) }
        previewID(store)?.let { MeCharacterPreviewCard(it) }
    }
}

/** 아잉(기본 보유) + 서버 목록 — 고르기 화면과 같은 순서 규칙. */
private fun tileIDs(store: MeStore): List<String> {
    val ids = mutableListOf(MeCharacterCards.aingID)
    for (row in store.shopRows) if (row.id !in ids) ids += row.id
    return MeCharacterTileRules.ordered(ids, store::isOwned)
}

/** 미리 볼 캐릭터: 고른 것 → 없으면 지금 입은 것(착용값을 알 때). */
private fun previewID(store: MeStore): String? = store.shopSelection ?: if (store.equippedLoaded) store.equippedCharacterID else null

/** 세 칸 격자(iOS LazyVGrid flexible × 3 · 틈 10). */
@Composable
fun TileGrid(ids: List<String>, columns: Int = 3, tile: @Composable (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        ids.chunked(columns).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
                row.forEach { id -> Box(Modifier.weight(1f)) { tile(id) } }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun ShopTile(store: MeStore, id: String, onOpenMachine: () -> Unit) {
    val owned = store.isOwned(id)
    // 생일 선물 전용 잠긴 칸을 누르면 그 칸이 '고름' 틴트를 받는다 — 아래 막대가 그 칸의 이름과 얻는 길을 말한다(사지는 않는다).
    val picked = store.shopSelection == id || store.shopGiftHintID == id
    val equipped = store.equippedLoaded && store.equippedCharacterID == id
    val name = MeCharacterName.display(id)
    val status: MeCharacterTileStatus = when {
        store.purchasingID == id -> MeCharacterTileStatus.Busy
        equipped -> MeCharacterTileStatus.Equipped
        owned -> MeCharacterTileStatus.Owned
        store.isGiftOnly(id) -> MeCharacterTileStatus.GiftOnly
        // 뽑기 전용(황금 · 무지개 아잉이) — 서버가 싣는 명목 가격(1000)을 보이지 않는다. 사는 줄이 아니다.
        store.isGachaOnly(id) -> MeCharacterTileStatus.GachaOnly(store.gachaShardCost(id))
        else -> store.price(id)?.let { MeCharacterTileStatus.Price(it, store.rubyBalance) } ?: MeCharacterTileStatus.UnknownPrice
    }
    MeCharacterTile(
        id, name, status,
        mark = if (equipped) MeTileMark.Equipped else if (picked) MeTileMark.Picked else MeTileMark.None,
        modifier = Modifier
            .testTag(ShopTags.tile(id))
            .clickable(enabled = store.purchasingID == null, role = Role.Button) {
                store.selectShopItem(id)
                // 뽑기 전용 "뽑기 · 조각 20" → 기계를 연다(뽑기가 열린 서버일 때만 — 아니면 얻을 길이 없다).
                if (store.showsGacha && !owned && store.isGachaOnly(id)) onOpenMachine()
            }
            .clearAndSetSemantics {
                contentDescription = MeCharacterTileRules.accessibilityText(name, status)
                role = Role.Button
                selected = picked
            },
    )
}

/** 아래 구매 막대: 고른 것의 이름 + 안내 · 오른쪽 [보석 N 사기]. 생일 선물 잠긴 칸을 골랐으면 이름 + 얻는 길만(사기 단추를 세우지 않는다). */
@Composable
fun PurchaseBar(store: MeStore, onBuy: () -> Unit) {
    val c = AingTheme.colors
    val selection = store.shopSelection
    val giftHint = if (selection == null) store.shopGiftHintID else null
    val lead = selection ?: giftHint
    Column(Modifier.fillMaxWidth().background(c.surface).navigationBarsPadding()) {
        Box(Modifier.fillMaxWidth().height(AingDimens.hairline).background(c.separator))
        Row(
            Modifier.fillMaxWidth().padding(horizontal = AingDimens.sideMargin, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space3),
        ) {
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (lead != null) MeCharacterArt(lead, 40.dp)
                Column(Modifier.semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(lead?.let(MeCharacterName::display) ?: MeText.pickSomething, style = MeType.headline, color = if (lead == null) c.label2 else c.label)
                    barDetail(store)?.let { detail ->
                        Text(
                            detail, style = MeType.footnote,
                            color = when (detail) { MeText.bought -> c.working; MeText.buyFailed -> c.danger; else -> c.label2 },
                        )
                    }
                }
            }
            if (giftHint == null) BuyButton(store, onBuy)
        }
    }
}

/** 안내·모자람(스토어) → 살 수 있으면 "사고 나면 루비 N개 남아요". */
private fun barDetail(store: MeStore): String? {
    store.shopBarDetail?.let { return it }
    if (store.shopSelection == null) return null
    val price = store.shopSelectionPrice ?: return null
    val balance = store.rubyBalance ?: return null
    return if (balance >= price) MeText.remainingAfterPurchase(price, balance) else null
}

@Composable
private fun BuyButton(store: MeStore, onBuy: () -> Unit) {
    MeButtonFrame(Modifier.testTag(ShopTags.BUY), MeButtonKind.Filled, MeButtonSize.Lg, fillsWidth = false, enabled = store.canConfirmPurchase, onClick = onBuy) { fg ->
        if (store.purchasingID != null) {
            CircularProgressIndicator(Modifier.size(16.dp), color = fg, strokeWidth = 2.dp)
        } else {
            val price = store.shopSelectionPrice
            if (price != null) {
                RubyIcon(rememberRuby(20f), 20.dp)
                Text("$price ${MeText.buyShort}", style = MeType.body.copy(fontWeight = FontWeight.SemiBold).digits(), color = fg)
            } else {
                Text(MeText.buyShort, style = MeType.body.copy(fontWeight = FontWeight.SemiBold), color = fg)
            }
        }
    }
}

@Composable
internal fun BackButton(onBack: () -> Unit) {
    IconButton(onClick = onBack, modifier = Modifier.semantics { contentDescription = "뒤로" }) {
        AingIcon(AppIcon.ChevronLeft, contentDescription = null, size = 28.dp, tint = AingTheme.colors.accent)
    }
}
