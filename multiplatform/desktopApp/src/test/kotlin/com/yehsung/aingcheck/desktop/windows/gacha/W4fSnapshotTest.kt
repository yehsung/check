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
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.presentCakeGiftIfDue
import com.yehsung.aingcheck.core.stores.me.selectCakeGiftOption
import com.yehsung.aingcheck.desktop.pages.missions.MissionsFlyoutPage
import com.yehsung.aingcheck.desktop.pages.shop.ShopFlyoutPage
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import com.yehsung.aingcheck.desktop.testsupport.DesktopSnapshots
import com.yehsung.aingcheck.desktop.testsupport.PixelImage
import com.yehsung.aingcheck.desktop.testsupport.SnapshotCompare
import com.yehsung.aingcheck.desktop.windows.gacha.W4fSnapshots.PxBox
import com.yehsung.aingcheck.desktop.windows.cakegift.CakeGiftWindowContent
import com.yehsung.aingcheck.desktop.windows.kit.DesktopGameWindows
import com.yehsung.aingcheck.ui.missions.MeMissionsScreen
import com.yehsung.aingcheck.ui.shop.CakeGiftTags
import com.yehsung.aingcheck.ui.shop.MeShopScreen
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.test.Test
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

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

    /**
     * 앱 다크 고정. 기준선 = 첫 선택지를 고른 판(확인 단추·고른 칸 받침 — 넓은 판이라 상한 1/4, 첫 실행 실측 16%).
     * 제목 끝 🎂(rules title)는 OS 그림 글꼴로 그려진다 — 비기록 러너의 굵은 대조에서 그 칸만 뺀다(맥은 픽셀 그대로).
     * CI 40963096714 실측: 이 칸 때문에 ubuntu 칸 최대 142 · windows 173(상한 64), 같은 러너의 다른 장면은 ≤38.
     */
    @Test
    fun cakeGiftWindow() {
        withStores(2, giftScene) { (a, b) ->
            a.store.presentCakeGiftIfDue()
            b.store.presentCakeGiftIfDue()
            val sheet = assertNotNull(b.store.cakeGiftSheet, "선물 시트가 서지 않았다")
            b.store.selectCakeGiftOption(sheet.gift.options.first())
            val (glyph, _) = cakeTitleBoxes(a.store)
            W4fSnapshots.check(
                "windows/cakegift", "cake-gift-window-dark", 440, 430,
                { WithRepoArt { CakeGiftWindowContent(a.store) } },
                { WithRepoArt { CakeGiftWindowContent(b.store) } },
                maxChangedFraction = 0.25,
                coarseIgnore = listOf(glyph),
            )
        }
    }

    /**
     * 가리개는 그림 글자 칸만 가린다 — 골든의 그 칸만 칠한 그림은 가리개 없이 빨강(CI 와 같은 꼴), 가리면 차 0.
     * 같은 크기를 칸 밖(아래로 칸 높이 세 배)에 칠하면 가려도 빨강. 칸은 제목 글자와 겹치지 않고 그림의 2% 안.
     */
    @Test
    fun cakeGlyphMaskHidesOnlyTheGlyphCell() = withStores(1, giftScene) { (a) ->
        a.store.presentCakeGiftIfDue()
        val (glyph, text) = cakeTitleBoxes(a.store)
        assertTrue(glyph.left >= text.right, "그림 글자 칸($glyph)이 제목 글자($text)와 겹친다")
        val golden = DesktopSnapshots.readPng(W4fSnapshots.golden("windows/cakegift", "cake-gift-window-dark"))
        assertTrue(glyph.snapped(golden.width, golden.height).area <= golden.argb.size * W4fSnapshots.MAX_IGNORED_FRACTION, "칸이 너무 넓다: $glyph")

        val inCell = golden.painted(glyph)
        assertFalse(SnapshotCompare.coarse(golden, inCell).withinTolerance, "칸만 칠해도 굵은 대조가 못 잡는다")
        val masked = SnapshotCompare.coarse(golden, W4fSnapshots.maskedForCoarse(golden, inCell, listOf(glyph)))
        assertTrue(masked.withinTolerance, "가렸는데 빨강: $masked")
        assertEquals(0, masked.maxBlockDelta, "가린 칸 밖에 차가 남았다: $masked")

        val h = glyph.bottom - glyph.top
        val outside = PxBox(glyph.left, glyph.top + 3 * h, glyph.right, glyph.bottom + 3 * h)
        val leaked = SnapshotCompare.coarse(golden, W4fSnapshots.maskedForCoarse(golden, golden.painted(outside), listOf(glyph)))
        assertFalse(leaked.withinTolerance, "칸 밖 변화까지 가렸다: $leaked")
    }

    private fun PixelImage.painted(box: PxBox, argbColor: Int = 0xFFFF00FF.toInt()): PixelImage {
        val out = argb.copyOf()
        for (y in box.top until box.bottom) for (x in box.left until box.right) out[y * width + x] = argbColor
        return PixelImage(width, height, out)
    }

    /**
     * 케이크 창 제목의 (그림 글자 칸 + 사방 [GLYPH_PAD_DP], 글자 부분) — 스냅숏 px. 실제 구성에서 태그 경계를 잰다(하드코딩 0 — 배치가 바뀌어도 따라간다).
     * 덧댐: 그림은 칸 가운데에 넘쳐도 되게 그려진다(wrapContentSize unbounded) — OS 그림 글꼴 폭 차이를 덮는다.
     */
    @OptIn(ExperimentalTestApi::class)
    private fun cakeTitleBoxes(store: MeStore): Pair<PxBox, PxBox> {
        var glyph: Rect? = null
        var text: Rect? = null
        var k = 1f
        runComposeUiTest {
            setContent { WithRepoArt { CakeGiftWindowContent(store) } }
            k = DesktopSnapshots.DENSITY / density.density
            glyph = onNodeWithTag(CakeGiftTags.TITLE_GLYPH, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
            text = onNodeWithTag(CakeGiftTags.TITLE_TEXT, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        }
        val pad = GLYPH_PAD_DP * DesktopSnapshots.DENSITY
        fun Rect.px(p: Float) = PxBox(
            floor(left * k - p).toInt().coerceAtLeast(0), floor(top * k - p).toInt().coerceAtLeast(0),
            ceil(right * k + p).toInt(), ceil(bottom * k + p).toInt(),
        )
        return assertNotNull(glyph, "그림 글자 칸이 없다").px(pad) to assertNotNull(text, "제목 글자가 없다").px(0f)
    }

    private fun String.replacingOnce(old: String, new: String): String {
        val i = indexOf(old)
        require(i >= 0) { "장면에 바꿀 조각이 없다: $old" }
        return substring(0, i) + new + substring(i + old.length)
    }

    companion object {
        const val FLYOUT_W = 380
        const val FLYOUT_H = 640
        const val GLYPH_PAD_DP = 4f
        private val giftScene = W4fScene(
            shopState = W4fServer.fixture("_me/rpc.shop_state@demo-gift.json"),
            giftPending = W4fServer.fixture("rpc.character_gift_pending@demo-gift.json"),
        )
    }
}
