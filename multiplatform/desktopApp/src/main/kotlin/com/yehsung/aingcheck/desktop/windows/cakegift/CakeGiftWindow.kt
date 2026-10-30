// 원본: Sources/check/CheckCakeGiftWindow.swift:1-24(머리 규약 · 440×430) · :340-380(show(activating:) · close · windowWillClose → cakeGiftDidClose)
//       WorkTimerStoreCakeGift.swift:260-275(cakeGiftDidClose · 로그아웃 때 창 내림)
//       (W4-f — 케이크 선물 창. Kotlin 스토어는 이 화면을 '시트'(MeStore.cakeGiftSheet)로 가진다 — 창은 시트의 유무를 따른다)
//
// 규칙:
//   ① 시트가 서면 창을 연다. 스스로 띄울 때(presentCakeGiftIfDue)는 키를 가져가지 않는다(맥 show(activating: false)).
//   ② 사용자가 × 로 닫으면 = 시트 닫기(dismissCakeGiftSheet — 맥 cakeGiftDidClose). 고르지 않고 닫으면 선물은 남는다('다시 열기' 줄).
//   ③ 시트가 걷히면(받은 뒤 [닫기] · 로그아웃) 창은 프로그램 닫기 — 통지 없음(kit 표: CakeGift 는 UserClosed 만 DidClose).
//   ④ 받는 중에는 닫지 않는다 — Kotlin 스토어 계약(dismissCakeGiftSheet 가 Claiming 이면 무시, 시트 머리 ✕ 도 꺼진다)을 창에도 건다.
//      맥은 창을 닫게 두고 왕복을 이어 갔지만, 여기서 창만 닫히면 스토어 시트가 남아 받은 뒤 화면이 숨은 창에 갇힌다.
//   ⑤ 외관은 앱 다크 고정(맥 CheckTheme). ⑥ 440×430 고정.
package com.yehsung.aingcheck.desktop.windows.cakegift

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.character.gift.CakeGiftText
import com.yehsung.aingcheck.core.stores.me.MeCakeGiftSheet
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.dismissCakeGiftSheet
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.desktop.windows.gacha.AwtGameWindowHandle
import com.yehsung.aingcheck.desktop.windows.gacha.ShowFocus
import com.yehsung.aingcheck.desktop.windows.gacha.armStuckWatchdog
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowHandle
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowSlot
import com.yehsung.aingcheck.desktop.windows.kit.StoreNotice
import com.yehsung.aingcheck.desktop.windows.kit.WindowBoundsStore
import com.yehsung.aingcheck.desktop.windows.kit.WindowEvent
import com.yehsung.aingcheck.ui.shop.MeCakeGiftSheetContent
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import kotlinx.coroutines.swing.Swing

/** 선물 시트의 사실(스토어 값 그대로). */
interface CakeGiftFacts {
    val hasSheet: Boolean
    val isClaiming: Boolean

    /** 사용자가 창을 닫았다(맥 cakeGiftDidClose → Kotlin dismissCakeGiftSheet). */
    fun dismiss()
}

fun MeStore.cakeGiftFacts(): CakeGiftFacts {
    val store = this
    return object : CakeGiftFacts {
        override val hasSheet: Boolean get() = store.cakeGiftSheet != null
        override val isClaiming: Boolean get() = store.cakeGiftSheet?.phase == MeCakeGiftSheet.Phase.Claiming
        override fun dismiss() = store.dismissCakeGiftSheet()
    }
}

/** 케이크 선물 창 하나. 실제 창은 [create] 뒤 — 시험은 창 0. */
class CakeGiftWindowController(
    private val facts: CakeGiftFacts,
    create: (onEvent: (WindowEvent) -> Unit) -> GameWindowHandle,
    bounds: WindowBoundsStore,
    workAreas: () -> List<PxRect>,
    scale: () -> Double,
    private val focus: ShowFocus = ShowFocus(),
) {
    val slot: GameWindowSlot = GameWindowSlot(GameWindowKind.CakeGift, { create(::onEvent) }, bounds, workAreas, scale, ::apply)

    /**
     * 스토어의 시트 유무를 창에 옮긴다(①·③). 이미 열린 창은 다시 열지 않는다(최소화한 창을 스스로 되살려 키를 뺏지 않게).
     * @param activating 사용자가 연 것인가(플라이아웃 '다시 열기' [고르기]) — 거짓이면 키를 가져가지 않는다. 창을 새로 열었으면 true.
     */
    fun sync(activating: Boolean): Boolean {
        if (!facts.hasSheet) {
            slot.closeFromApp()
            return false
        }
        if (slot.presence.open) return false
        focus.activate = activating
        slot.open()
        return true
    }

    /** 껍데기가 Win32/AWT 사건을 넘긴다. ④ 받는 중의 닫기는 받지 않는다. */
    fun onEvent(event: WindowEvent) {
        if (event == WindowEvent.UserClosed && facts.isClaiming) return
        slot.onEvent(event)
    }

    private fun apply(notices: List<StoreNotice>) {
        if (StoreNotice.DidClose in notices) facts.dismiss()
    }
}

/** 창 내용 — 시트가 있을 때만 그린다(걷히면 내용도 걷혀 cakeGiftSheetDidDisappear 가 온다). */
@Composable
fun CakeGiftWindowContent(store: MeStore, dark: Boolean = true) {
    val sheet = store.cakeGiftSheet ?: return
    AingTheme(dark = dark) {
        Box(Modifier.size(GameWindowKind.CakeGift.defaultWidthDp.dp, GameWindowKind.CakeGift.defaultHeightDp.dp).background(AingTheme.colors.surface)) {
            MeCakeGiftSheetContent(store, sheet)
        }
    }
}

/**
 * 케이크 선물 창(실제 ComposeWindow) — AppGraph(조정자 C3)가 [start] 를 앱 범위에서 한 번 부른다.
 * DesktopGameWindows.openCakeGift 는 [openByUser](스토어 reopenCakeGift 가 시트를 세우면 창이 따라 선다).
 * @param userIsLooking 지금 사용자가 플라이아웃을 보고 있는가 — 그때 선 시트는 사용자가 연 것으로 친다(키를 가져간다).
 */
class CakeGiftWindowHost(
    private val store: MeStore,
    bounds: WindowBoundsStore,
    workAreas: () -> List<PxRect>,
    scale: () -> Double,
    private val userIsLooking: () -> Boolean = { false },
) {
    private val focus = ShowFocus()
    val controller = CakeGiftWindowController(store.cakeGiftFacts(), ::createHandle, bounds, workAreas, scale, focus)

    fun start(scope: CoroutineScope): Job = scope.launch(Dispatchers.Swing) {
        snapshotFlow { store.cakeGiftSheet != null }.distinctUntilChanged().collect {
            if (controller.sync(activating = userIsLooking())) armStuckWatchdog(controller.slot)
        }
    }

    /** 이미 시트가 서 있으면 창을 앞으로(멱등 열기). 시트가 없으면 아무 일도 없다 — 시트를 세우는 건 스토어(reopenCakeGift)다. */
    fun openByUser() {
        if (!store.cakeGiftFacts().hasSheet) return
        focus.activate = true
        controller.slot.open()
    }

    fun close() = controller.slot.closeFromApp()

    private fun createHandle(onEvent: (WindowEvent) -> Unit): GameWindowHandle =
        AwtGameWindowHandle(CakeGiftText.title, focus, onEvent) { CakeGiftWindowContent(store) }
}

