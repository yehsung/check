// W4-f 완료 기준 스냅숏: 상점·미션 페이지(플라이아웃 폭 380) · 뽑기 창 420×552 · 케이크 창 440×430.
// 진짜 나 탭 스토어를 데모 픽스처(합성)로 채워 스토어 → 화면 경로를 통째로 지난다. 기준선은 장면마다 한 군데만 다르다.
package com.yehsung.aingcheck.desktop.windows.gacha

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.me.presentCakeGiftIfDue
import com.yehsung.aingcheck.core.stores.me.selectCakeGiftOption
import com.yehsung.aingcheck.desktop.pages.missions.MissionsFlyoutPage
import com.yehsung.aingcheck.desktop.pages.shop.ShopFlyoutPage
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import com.yehsung.aingcheck.desktop.windows.cakegift.CakeGiftWindowContent
import com.yehsung.aingcheck.desktop.windows.kit.DesktopGameWindows
import com.yehsung.aingcheck.ui.missions.MeMissionsScreen
import com.yehsung.aingcheck.ui.shop.MeShopScreen
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.test.Test
import kotlin.test.assertNotNull

class W4fSnapshotTest {
    private fun <T> withStores(n: Int, scene: W4fScene = W4fScene(), body: (List<W4fStore>) -> T): T {
        val stores = List(n) { W4fStore(scene) }
        try {
            return body(stores)
        } finally {
            stores.forEach { it.close() }
        }
    }

    /** 플라이아웃 틀(셸이 테마를 건다 — 페이지는 테마를 걸지 않는다). */
    private fun flyout(content: @Composable () -> Unit): @Composable () -> Unit = {
        WithRepoArt {
            AingTheme(dark = false) {
                Box(Modifier.size(FLYOUT_W.dp, FLYOUT_H.dp).background(AingTheme.colors.background)) { content() }
            }
        }
    }

    /** 기준선 = 같은 화면에 뒤로 단추만 없음(플라이아웃 뒤로 배선이 그려졌는지까지 본다). */
    @Test
    fun shopPage() = withStores(1) { (w) ->
        val nav = InMemoryFlyoutNavigator(FlyoutRoute.Shop)
        val page = ShopFlyoutPage(w.store, DesktopGameWindows.None)
        W4fSnapshots.check(
            "pages/shop", "shop-page-light", FLYOUT_W, FLYOUT_H,
            flyout { page.Content(nav, FLYOUT_W.toDouble()) },
            flyout { MeShopScreen(w.store, onBack = null, onOpenMachine = {}, modifier = Modifier.width(FLYOUT_W.dp).fillMaxHeight()) },
        )
    }

    @Test
    fun missionsPage() = withStores(1) { (w) ->
        val nav = InMemoryFlyoutNavigator(FlyoutRoute.Missions)
        val page = MissionsFlyoutPage(w.store)
        W4fSnapshots.check(
            "pages/missions", "missions-page-light", FLYOUT_W, FLYOUT_H,
            flyout { page.Content(nav, FLYOUT_W.toDouble()) },
            flyout { MeMissionsScreen(w.store, onBack = null, modifier = Modifier.width(FLYOUT_W.dp).fillMaxHeight()) },
        )
    }

    /**
     * 기계는 멈춘 상태(isActive=false) · 애니메이션 줄이기로 그린다 — 기계 시계가 벽시계(TimeSource.Monotonic)라 대기 반짝임이
     * 장면마다 다른 위상으로 그려진다(첫 실행 실측: 6,091px · 채널 차 12). 기준선 = 조각 23 → 24.
     */
    @Test
    fun gachaWindow() {
        val shards24 = W4fScene(shopState = W4fScene().shopState.replacingOnce("\"shards\": 23", "\"shards\": 24"))
        W4fStore().use { a ->
            W4fStore(shards24).use { b ->
                W4fSnapshots.check(
                    "windows/gacha", "gacha-window-light", 420, 552,
                    { WithRepoArt { GachaWindowContent(a.store, GachaWindowState(), onClose = {}, dark = false, reduceMotion = true) } },
                    { WithRepoArt { GachaWindowContent(b.store, GachaWindowState(), onClose = {}, dark = false, reduceMotion = true) } },
                )
            }
        }
    }

    /** 앱 다크 고정. 기준선 = 첫 선택지를 고른 판(확인 단추·고른 칸 받침 — 넓은 판이라 상한 1/4, 첫 실행 실측 16%). */
    @Test
    fun cakeGiftWindow() {
        val gift = W4fScene(shopState = W4fServer.fixture("_me/rpc.shop_state@demo-gift.json"), giftPending = W4fServer.fixture("rpc.character_gift_pending@demo-gift.json"))
        withStores(2, gift) { (a, b) ->
            a.store.presentCakeGiftIfDue()
            b.store.presentCakeGiftIfDue()
            val sheet = assertNotNull(b.store.cakeGiftSheet, "선물 시트가 서지 않았다")
            b.store.selectCakeGiftOption(sheet.gift.options.first())
            W4fSnapshots.check(
                "windows/cakegift", "cake-gift-window-dark", 440, 430,
                { WithRepoArt { CakeGiftWindowContent(a.store) } },
                { WithRepoArt { CakeGiftWindowContent(b.store) } },
                maxChangedFraction = 0.25,
            )
        }
    }

    private fun String.replacingOnce(old: String, new: String): String {
        val i = indexOf(old)
        require(i >= 0) { "장면에 바꿀 조각이 없다: $old" }
        return substring(0, i) + new + substring(i + old.length)
    }

    companion object {
        const val FLYOUT_W = 380
        const val FLYOUT_H = 640
    }
}
