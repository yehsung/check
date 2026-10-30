// 원본: Sources/check/CheckMenuView.swift 4911-5030(UltraPanelCopy · UltraPanel 히어로 카드) · CheckShopPanel.swift 152-200(ShopText 울트라 줄·하단 바)
//       · 355-400(purchaseBar) · 430-500(ultraCard — 누르면 고르기 → 하단 [구매하기]) · WorkTimerStoreAuth.swift 645-697(selectShopItem·pickSomethingNotice)
//       · 700-720(shopSelectionPrice·canConfirmShopPurchase) · 805-846(buyUltra) · WorkTimerStore.swift 2866-2881(openUltraPanel → panelOpen sync) @ 35649bee
// W3-c3 울트라 페이지(FlyoutRoute.Ultra). 맥 울트라 화면(보유 수량 히어로) + 구매 진입(W-3 #15 — Windows 공용 상점엔 울트라 칸이 없어 여기 단추).
// 구매 동작·판정은 feature UltraPurchase(W2-g4): 결과는 **서버 값**으로 적고 클라가 잔액을 앞질러 빼지 않는다.
package com.yehsung.aingcheck.desktop.pages.ultra

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.format.SharedText
import com.yehsung.aingcheck.core.stores.me.RubyBalanceMirror
import com.yehsung.aingcheck.desktop.pages.poke.PageEntry
import com.yehsung.aingcheck.desktop.pages.poke.UltraBalanceText
import com.yehsung.aingcheck.desktop.pages.poke.pageActive
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraSyncReason
import com.yehsung.aingcheck.feature.desktop.ultra.UltraPurchase
import com.yehsung.aingcheck.feature.desktop.ultra.UltraWalletStore
import com.yehsung.aingcheck.ui.components.RubyBalanceChip
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** 울트라 화면 문구(Swift UltraPanelCopy). */
object UltraPageCopy {
    const val TITLE: String = "울트라"
    const val UNKNOWN_BALANCE: String = "—"
    const val LOADING_CAPTION: String = "불러오는 중…"
    const val FAILED_CAPTION: String = "최신 잔량을 못 읽었어요"
    const val UNLIMITED_BALANCE: String = "무제한"
    const val UNIT: String = "개"
    const val RETRY: String = "다시 시도"
    val unlimitedCaption: String get() = "${UltraBalanceText.holdSecondsText}초 꾹 누르면 발사 — 잔량을 쓰지 않아요"

    /** 무제한 > 실패 > 모름 > 있음/없음(Swift 4929-4945 순서). */
    fun heroCaption(balance: Long?, hasFailed: Boolean, unlimited: Boolean = false): String {
        if (unlimited) return unlimitedCaption
        if (hasFailed) return FAILED_CAPTION
        if (balance == null) return LOADING_CAPTION
        return if (balance > 0) "${UltraBalanceText.holdSecondsText}초 꾹 누르면 한 개 써요" else "상점에서 루비로 사요"
    }

    fun balanceText(balance: Long?, unlimited: Boolean = false): String {
        if (unlimited) return UNLIMITED_BALANCE
        return balance?.coerceAtLeast(0)?.toString() ?: UNKNOWN_BALANCE
    }
}

/** 구매 칸 문구(Swift ShopText 의 울트라 몫 · WorkTimerStore 안내). */
object UltraShopText {
    const val SECTION: String = "소모품"
    const val PICKED_TITLE: String = "울트라 찌르기 1개"
    const val PICK_SOMETHING: String = "살 것을 골라 주세요"
    const val BUY: String = "구매하기"
    const val BUSY: String = "…"

    /** 값을 모르면 "1개"를 말하지 않는다. */
    fun rowTitle(price: Long?): String = if (price == null) "울트라 찌르기" else PICKED_TITLE

    /** 잔량을 모르면 숫자를 만들지 않는다. */
    fun held(balance: Long?): String = balance?.let { "보유 ${it.coerceAtLeast(0)}개" } ?: "보유 —"

    fun barTitle(selected: Boolean): String = if (selected) PICKED_TITLE else PICK_SOMETHING

    /** 둘째 줄 — 방금 일어난 일 > 모자란 양 > 빈칸(높이 고정, Swift barDetail). */
    fun barDetail(notice: String?, selected: Boolean, price: Long?, balance: Long?): String {
        if (notice != null) return notice
        if (!selected || price == null || balance == null || balance >= price) return " "
        return SharedText.shortfallNotice(need = price, have = balance)
    }

    /** UltraPurchase 의 ok 안내와 같은 글자(시험이 둘을 견준다). */
    fun okNotice(count: Int): String = "울트라 ${count}개를 샀어요!"
}

/**
 * 고르기 → [구매하기] 두 단계(맥 2026-09-14 신고 뒤 규칙 — 누르자마자 사지 않는다).
 * - 날아가는 동안 고르기·구매 둘 다 무시(요청 1건). [UltraPurchase] 도 같은 깃발로 한 번 더 막는다.
 * - 값·잔량을 **모르면** 살 수 없다(지어내지 않는다) — 그때 [구매하기]는 사지 않고 상점을 다시 읽는다(맥 WorkTimerStoreAuth.swift 736-744).
 *   모자라면 바가 모자란 양을 말하고 단추는 흐리다(서버가 최종 판정).
 * - 화면 진입 = 상점 한 번 읽기([onEnter] — 맥 toggleShopPanel → loadShopState, WorkTimerStore.swift 3022: 값·루비는 다른 기기에서도 바뀐다).
 * - ok 면 고른 것을 푼다(Swift shopSelection = nil). 잔액은 응답 값 그대로(UltraPurchase.apply).
 */
class UltraPurchaseModel(
    private val purchase: UltraPurchase,
    private val ruby: RubyBalanceMirror,
    private val ultraPrice: () -> Long?,
    /** 상점 상태 다시 읽기(MeStore.loadShop — 값·루비가 같은 응답으로 온다). */
    private val reloadShop: () -> Unit,
) {
    private val _selected = MutableStateFlow(false)
    val selected: StateFlow<Boolean> = _selected.asStateFlow()
    val isPurchasing: StateFlow<Boolean> get() = purchase.isPurchasing
    val notice: StateFlow<String?> get() = purchase.notice

    fun select() {
        if (purchase.isPurchasing.value) return
        _selected.value = !_selected.value
        purchase.clearNotice()
    }

    /** 화면 진입(진입마다 1회 — 플라이아웃을 다시 여는 것은 진입이 아니다). */
    fun onEnter() = reloadShop()

    fun canConfirm(): Boolean {
        if (purchase.isPurchasing.value || !_selected.value) return false
        val have = ruby.rubyBalance ?: return false
        val price = ultraPrice() ?: return false
        return have >= price
    }

    fun confirm(): Job? {
        if (purchase.isPurchasing.value || !_selected.value) return null
        if (ruby.rubyBalance == null || ultraPrice() == null) {
            reloadShop()
            return null
        }
        if (!canConfirm()) return null
        val job = purchase.buy(1) ?: return null
        job.invokeOnCompletion { if (purchase.notice.value == UltraShopText.okNotice(1)) _selected.value = false }
        return job
    }
}

/** 구매 칸 값(없으면 칸째 안 그린다 — ultra=false). */
data class UltraPurchaseView(
    val selected: Boolean,
    val purchasing: Boolean,
    val notice: String?,
    val price: Long?,
    val ruby: Long?,
    val canConfirm: Boolean,
)

data class UltraViewState(
    val balance: Long?,
    val unlimited: Boolean,
    val failed: Boolean,
    val purchase: UltraPurchaseView?,
)

class UltraPageDeps(
    /** SocialWiring.wallet(깃발 없이 돈다 — W-6 #1). */
    val wallet: UltraWalletStore,
    /** SocialWiring.purchase 를 감싼 것. ultra=false → null(구매 칸 없음 · 요청 0). */
    val purchase: UltraPurchaseModel?,
    /** 상점과 **같은 칸**(RubyBalanceMirror — 칸이 둘이면 화면마다 잔액이 갈린다). */
    val ruby: RubyBalanceMirror,
    /**
     * shop_state.ultra_price(SocialDeps.ultraPrice 와 같은 출처 — MeStore.ultraPrice). **Compose 상태를 읽는 람다**여야 한다:
     * 화면이 구성 중에 읽으므로 상점 조회가 값을 적는 순간 다시 그린다(루비 칸 [ruby] 와 같은 결).
     */
    val ultraPrice: () -> Long?,
    val rubyArt: () -> ImageBitmap? = { null },
)

/**
 * 울트라 페이지. 보일 때마다 지갑 PanelOpen sync 1회(맥 openUltraPanel 2880 · 다시 열기 setMenuPresented 310).
 * 진입의 첫 보임엔 상점도 읽는다(구매 칸이 있을 때만 — 맥 상점 진입 3022). 뒤로 = 플라이아웃 뒤로.
 */
class UltraPage(private val deps: UltraPageDeps) : FlyoutPageHost {
    private val entry = PageEntry()

    @Composable
    override fun Content(nav: FlyoutNavigator, widthDip: Double) {
        val active = pageActive(nav, FlyoutRoute.Ultra, entry)
        LaunchedEffect(active) {
            if (!active) return@LaunchedEffect
            deps.wallet.sync(UltraSyncReason.PanelOpen)
            if (entry.firstShow()) deps.purchase?.onEnter()
        }
        val wallet by deps.wallet.state.collectAsState()
        val p = deps.purchase
        val purchaseView = if (p == null) {
            null
        } else {
            val selected by p.selected.collectAsState()
            val purchasing by p.isPurchasing.collectAsState()
            val notice by p.notice.collectAsState()
            UltraPurchaseView(selected, purchasing, notice, deps.ultraPrice(), deps.ruby.rubyBalance, p.canConfirm())
        }
        UltraContent(
            state = UltraViewState(wallet.balance, wallet.unlimited, wallet.failed, purchaseView),
            onBack = { nav.back() },
            onRetry = { deps.wallet.sync(UltraSyncReason.PanelOpen) },
            onSelect = { p?.select() },
            onConfirm = { p?.confirm() },
            rubyArt = deps.rubyArt(),
            modifier = Modifier.width(widthDip.dp).fillMaxHeight(),
        )
    }
}

/** 값 → 픽셀(스냅숏·페이지 공용). */
@Composable
fun UltraContent(
    state: UltraViewState,
    onBack: () -> Unit,
    onRetry: () -> Unit,
    onSelect: () -> Unit,
    onConfirm: () -> Unit,
    rubyArt: ImageBitmap?,
    modifier: Modifier = Modifier,
) {
    val c = AingTheme.colors
    Column(modifier.background(c.background).padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth().height(27.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.size(27.dp).clickable(onClick = onBack).semantics { contentDescription = "뒤로" }, contentAlignment = Alignment.Center) {
                AingIcon(AppIcon.ChevronLeft, contentDescription = null, size = 16.dp, tint = c.label2)
            }
            Text(UltraPageCopy.TITLE, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, color = c.label)
            Spacer(Modifier.weight(1f))
            // 구매 칸이 있을 때만 루비 잔량(맥 상점 머리 — 이 화면에서 먼저 읽어야 할 숫자).
            state.purchase?.let { RubyBalanceChip(count = it.ruby, art = rubyArt) }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(c.separator))
        HeroCard(state, onRetry)
        state.purchase?.let { PurchaseSection(it, state.balance, onSelect, onConfirm, rubyArt) }
    }
}

@Composable
private fun HeroCard(state: UltraViewState, onRetry: () -> Unit) {
    val c = AingTheme.colors
    val charged = state.unlimited || (state.balance ?: 0) > 0
    Row(
        Modifier.fillMaxWidth().height(72.dp).background(c.fill, RoundedCornerShape(10.dp)).border(1.dp, c.accentLine, RoundedCornerShape(10.dp)).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(46.dp).background(if (charged) c.accentTint else c.fill2, CircleShape), contentAlignment = Alignment.Center) {
            AingIcon(AppIcon.BoltFill, contentDescription = null, size = 22.dp, tint = if (charged) c.accent else c.label2)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(UltraPageCopy.balanceText(state.balance, state.unlimited), style = MaterialTheme.typography.headlineSmall, fontSize = 26.sp, color = c.label)
                if (!state.unlimited) Text(UltraPageCopy.UNIT, style = MaterialTheme.typography.bodySmall, color = c.label2, modifier = Modifier.padding(bottom = 3.dp))
            }
            Text(UltraPageCopy.heroCaption(state.balance, state.failed, state.unlimited), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Normal, color = c.label2, maxLines = 1)
        }
        if (state.failed) {
            Box(Modifier.background(c.accentTint, CircleShape).clickable(onClick = onRetry).padding(horizontal = 10.dp, vertical = 4.dp)) {
                Text(UltraPageCopy.RETRY, style = MaterialTheme.typography.labelSmall, color = c.accent)
            }
        }
    }
}

@Composable
private fun PurchaseSection(p: UltraPurchaseView, ultraBalance: Long?, onSelect: () -> Unit, onConfirm: () -> Unit, rubyArt: ImageBitmap?) {
    val c = AingTheme.colors
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(UltraShopText.SECTION, style = MaterialTheme.typography.labelSmall, color = c.label2)
        // 울트라 카드 — 누르면 **고르기**(사지 않는다). 날아가는 동안 잠긴다.
        Row(
            Modifier
                .fillMaxWidth()
                .background(if (p.selected) c.accentTint else c.surface, RoundedCornerShape(10.dp))
                .border(if (p.selected) 2.dp else 1.dp, if (p.selected) c.accent else c.accentLine, RoundedCornerShape(10.dp))
                .clickable(enabled = !p.purchasing, onClick = onSelect)
                .padding(horizontal = 10.dp, vertical = 8.dp)
                .semantics { contentDescription = "울트라 찌르기 고르기" },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            AingIcon(AppIcon.BoltFill, contentDescription = null, size = 13.dp, tint = c.accent)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(UltraShopText.rowTitle(p.price), style = MaterialTheme.typography.labelLarge, color = c.label, maxLines = 1)
                Text(UltraShopText.held(ultraBalance), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Normal, color = c.label2, maxLines = 1)
            }
            p.price?.let { RubyBalanceChip(count = it, art = rubyArt) }
            if (p.selected) {
                Box(Modifier.size(18.dp).background(c.accent, CircleShape), contentAlignment = Alignment.Center) {
                    AingIcon(AppIcon.Check, contentDescription = null, size = 11.dp, tint = c.onAccentFill)
                }
            }
        }
        // 하단 바 — 높이 고정(둘째 줄은 언제나 그린다).
        Row(
            Modifier.fillMaxWidth().height(52.dp).background(c.surface, RoundedCornerShape(10.dp)).padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(UltraShopText.barTitle(p.selected), style = MaterialTheme.typography.labelMedium, color = if (p.selected) c.label else c.label2, maxLines = 1)
                Text(UltraShopText.barDetail(p.notice, p.selected, p.price, p.ruby), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Normal, color = c.label2, maxLines = 1)
            }
            if (p.selected) p.price?.let { RubyBalanceChip(count = it, art = rubyArt) }
            Box(
                Modifier
                    .background(if (p.canConfirm) c.accentFill else c.fill2, RoundedCornerShape(8.dp))
                    .clickable(enabled = p.canConfirm, onClick = onConfirm)
                    .padding(horizontal = 14.dp, vertical = 7.dp)
                    .semantics { contentDescription = UltraShopText.BUY },
                contentAlignment = Alignment.Center,
            ) {
                Text(if (p.purchasing) UltraShopText.BUSY else UltraShopText.BUY, style = MaterialTheme.typography.labelMedium, color = if (p.canConfirm) c.onAccentFill else c.label3Text)
            }
        }
    }
}
