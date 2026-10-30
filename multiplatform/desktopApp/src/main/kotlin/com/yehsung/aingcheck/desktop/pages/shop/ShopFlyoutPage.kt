// 원본: Sources/check/CheckMenuView.swift:820-830(상점 = 팝오버 패널) · WorkTimerStoreGacha.swift:149-158(openGachaWindow — 창 먼저, 팝오버 나중)
//       (W4-f — 조정자 결정 W-3 #3: 상점은 플라이아웃 페이지(맥 팝오버 패널 자리). 뽑기는 별도 창. 라우트는 shellapi FlyoutRoute.Shop)
package com.yehsung.aingcheck.desktop.pages.shop

import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.windows.kit.DesktopGameWindows
import com.yehsung.aingcheck.ui.shop.MeShopScreen

/** 상점에서 나가는 문(판정 한 곳 — 시험이 순서를 잰다). */
object ShopEntry {
    val route: FlyoutRoute = FlyoutRoute.Shop

    /**
     * [뽑기] — ★ 창 먼저, 플라이아웃 나중(맥 openGachaWindow: gachaWindowHooks.show() 뒤 dismissMenuPopover()).
     * 먼저 숨기면 이 단추를 그린 페이지가 액션 도중에 걷히고, 창이 앞으로 올 자리(전경 권한)를 플라이아웃과 함께 잃는다.
     */
    fun openMachine(windows: DesktopGameWindows, nav: FlyoutNavigator) {
        windows.openGacha()
        nav.hide()
    }
}

/** 상점 페이지 — 공용 ui 상점 화면 그대로(본문·확률 시트·조각 교환 시트는 화면 안에). 뒤로 = 플라이아웃 뒤로(FlyoutRoutes.backOf → Home). */
class ShopFlyoutPage(
    private val store: MeStore,
    private val windows: DesktopGameWindows,
) : FlyoutPageHost {
    @Composable
    override fun Content(nav: FlyoutNavigator, widthDip: Double) {
        MeShopScreen(
            store = store,
            onBack = { nav.back() },
            onOpenMachine = { ShopEntry.openMachine(windows, nav) },
            modifier = Modifier.width(widthDip.dp).fillMaxHeight(),
        )
    }
}
