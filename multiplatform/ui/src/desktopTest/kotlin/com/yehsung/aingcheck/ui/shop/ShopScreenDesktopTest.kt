// 원본: Tests/CheckMobileKitTests/MeGachaStoreTests.swift @ 3bd04bd (확률 합 ≠ 100% 면 숨김) · Tests/CheckMobileKitTests/MeDemoShopSheetRouteTests.swift @ 3bd04bd (상점·시트 장면)
//
// 상점 화면(데스크톱 오프스크린). 진짜 나 탭 스토어를 데모 픽스처로 채워 화면에 넘긴다 — 스토어 → 화면 경로를 통째로 지난다.
//  ① 스냅숏: 상점(밝음 · 어두움) · 확률 시트 · 조각 교환 시트 · 생일 선물 고르기 창
//  ② G §2-3 W4-c ② "확률 보기" 줄이 [뽑기] **바로 위**에 있다(자리 · 사이에 다른 것 없음)
//  ③ G §2-3 W4-c ③ 확률 합이 100% 가 아니면 뽑기 카드를 숨긴다(기준선: 같은 응답의 합 100% 판은 선다)
//  ④ 확률 보기 줄의 숫자는 서버 값이다(서버가 3 → 4 로 바꾸면 화면도 4)
package com.yehsung.aingcheck.ui.shop

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.runDesktopComposeUiTest
import androidx.compose.ui.unit.DpRect
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.character.gift.CakeGiftText
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.gachaOddsRows
import com.yehsung.aingcheck.core.stores.me.selectCakeGiftOption
import com.yehsung.aingcheck.core.stores.me.showsGacha
import com.yehsung.aingcheck.ui.gacha.GachaCardTags
import com.yehsung.aingcheck.ui.gacha.GachaOddsSummary
import com.yehsung.aingcheck.ui.gacha.MeGachaExchangeSheetContent
import com.yehsung.aingcheck.ui.gacha.MeGachaOddsSheetContent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class)
class ShopScreenDesktopTest {
    private fun shop(shards: Int = 23, price: Int = 50, odds: String? = null, robotAs: String = "robot"): MeStore {
        var json = MeScreenFixtures.shopState.replacingOnce("\"shards\": 23", "\"shards\": $shards").replacingOnce("\"price\": 50", "\"price\": $price")
        // 음성 기준선: 확률표 · 교환표의 로봇 한 줄만 이 빌드가 모르는 캐릭터로(그림 → 자리표시, 이름 → id, 값 → —).
        if (robotAs != "robot") json = json.replacingOnce("\"character_id\": \"robot\"", "\"character_id\": \"$robotAs\"").replacingOnce("\"robot\": 8", "\"$robotAs\": 8")
        if (odds != null) json = odds.split(';').fold(json) { acc, pair -> val (a, b) = pair.split('='); acc.replacingOnce(a, b) }
        return loadedMeStore(MeScene(shopState = json))
    }

    private fun shopScene(dark: Boolean, shards: Int): @Composable () -> Unit {
        val store = shop(shards)
        return W4cDesktopSnapshots.frame(dark, W, SHOP_H) { MeShopContent(store, onOpenMachine = {}, onOpenOdds = {}, onOpenExchange = {}, onRetry = {}, scrolls = false) }
    }

    @Test fun shopLight() = W4cDesktopSnapshots.check("shop", "shop-light", W, SHOP_H, shopScene(false, 23), shopScene(false, 24))
    @Test fun shopDark() = W4cDesktopSnapshots.check("shop", "shop-dark", W, SHOP_H, shopScene(true, 23), shopScene(true, 24))

    @Test
    fun oddsSheet() {
        fun scene(robot: String): @Composable () -> Unit {
            val store = shop(robotAs = robot)
            return W4cDesktopSnapshots.frame(false, W, ODDS_H) { MeGachaOddsSheetContent(store, onClose = {}, scrolls = false) }
        }
        W4cDesktopSnapshots.check("gacha", "odds-light", W, ODDS_H, scene("robot"), scene("zebra"))
    }

    @Test
    fun oddsSheetDark() {
        fun scene(robot: String): @Composable () -> Unit {
            val store = shop(robotAs = robot)
            return W4cDesktopSnapshots.frame(true, W, ODDS_H) { MeGachaOddsSheetContent(store, onClose = {}, scrolls = false) }
        }
        W4cDesktopSnapshots.check("gacha", "odds-dark", W, ODDS_H, scene("robot"), scene("zebra"))
    }

    @Test
    fun exchangeSheet() {
        fun scene(robot: String): @Composable () -> Unit {
            val store = shop(robotAs = robot)
            return W4cDesktopSnapshots.frame(false, W, EXCHANGE_H) { MeGachaExchangeSheetContent(store, onClose = {}, scrolls = false) }
        }
        W4cDesktopSnapshots.check("gacha", "exchange-light", W, EXCHANGE_H, scene("robot"), scene("zebra"))
    }

    @Test
    fun cakeGiftSheet() {
        fun scene(pick: String?): @Composable () -> Unit {
            val store = loadedMeStore(MeScene(shopState = MeScreenFixtures.fixture("_me/rpc.shop_state@demo-gift.json"), giftPending = MeScreenFixtures.giftPending))
            if (pick != null) store.selectCakeGiftOption(pick)
            val sheet = requireNotNull(store.cakeGiftSheet) { "선물 시트가 서지 않았다" }
            return W4cDesktopSnapshots.frame(false, W, GIFT_H) { MeCakeGiftSheetContent(store, sheet, scrolls = false) }
        }
        // 기준선: 고른 칸 하나만 다르다(초코를 고름 ↔ 아직 안 고름). 고른 칸은 받침 전체가 파랑 틴트라 바뀐 픽셀이 화면의 1/10 을 넘는다(실측 17%) —
        // 이 장면만 상한을 1/4 로 둔다. 굵은 대조가 잡는지는 그대로 잰다.
        // 제목 끝 🎂 는 OS 그림 글꼴이라 기록 기계가 아닌 러너에서만 그 고정 칸을 굵은 대조에서 덮는다(W4cDesktopSnapshots 머리말).
        val shown = scene("aing_cake_choco")
        var glyph: DpRect? = null
        runDesktopComposeUiTest(W, GIFT_H) {
            setContent { shown() }
            glyph = onNodeWithTag(CakeGiftTags.TITLE_GLYPH, useUnmergedTree = true).getBoundsInRoot()
        }
        W4cDesktopSnapshots.check(
            "shop", "cake-gift-light", W, GIFT_H, shown, scene(null), maxChangedFraction = 0.25, platformGlyphs = listOf(requireNotNull(glyph)),
        )
    }

    /** 그림 글자 폭이 기기마다 달라도 제목 글자 자리는 그대로다(그림 글자는 고정 칸 — 한 줄에 섞으면 가운데 맞춤이 그 폭만큼 밀린다). */
    @Test
    fun cakeTitleTextIgnoresGlyphWidth() {
        assertEquals("생일 축하해요!" to "🎂", CakeGiftTitleParts.split(CakeGiftText.title))
        assertEquals("딸기 케이크 아잉이를 받았어요!" to null, CakeGiftTitleParts.split(CakeGiftText.received("딸기 케이크 아잉이")))
        fun bounds(title: String): Pair<DpRect, DpRect> {
            var text: DpRect? = null
            var glyph: DpRect? = null
            runDesktopComposeUiTest(W, TITLE_H) {
                setContent {
                    W4cDesktopSnapshots.frame(false, W, TITLE_H) {
                        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) { MeCakeGiftTitle(title) }
                    }()
                }
                text = onNodeWithTag(CakeGiftTags.TITLE_TEXT, useUnmergedTree = true).getBoundsInRoot()
                glyph = onNodeWithTag(CakeGiftTags.TITLE_GLYPH, useUnmergedTree = true).getBoundsInRoot()
            }
            return requireNotNull(text) to requireNotNull(glyph)
        }
        val one = bounds(CakeGiftText.title)
        val three = bounds(CakeGiftText.title + "🎂🎂") // 그림 글자가 세 배 넓은 기기 흉내
        assertEquals(one.first, three.first, "그림 글자 폭이 바뀌니 제목 글자 자리가 움직였다 — 그림 글자가 고정 칸 밖에 있다")
        assertEquals(one.second, three.second, "그림 글자 칸 크기가 그림 글자 폭을 따라 바뀌었다")
        assertTrue(one.second.left >= one.first.right, "그림 글자 칸이 글자 오른쪽에 있지 않다")
    }

    // MARK: ② 확률 보기 줄은 [뽑기] 바로 위

    @Test
    fun oddsRowSitsDirectlyAbovePull() = runDesktopComposeUiTest(W, SHOP_H) {
        val store = shop()
        setContent { W4cDesktopSnapshots.frame(false, W, SHOP_H) { MeShopContent(store, {}, {}, {}, {}, scrolls = false) }() }
        val odds = onNodeWithTag(GachaCardTags.ODDS_ROW).getBoundsInRoot()
        val pull = onNodeWithTag(GachaCardTags.PULL).getBoundsInRoot()
        val exchange = onNodeWithTag(GachaCardTags.EXCHANGE).getBoundsInRoot()
        assertTrue(odds.bottom <= pull.top, "확률 보기 줄(${odds.top}–${odds.bottom})이 [뽑기](${pull.top}–${pull.bottom}) 위가 아니다")
        // 바로 위: 카드 줄 사이 틈(12) 하나 — 그 사이에 다른 줄이 끼면 틈이 그보다 커진다.
        assertTrue(pull.top - odds.bottom <= 12.dp + 1.dp, "확률 보기 줄과 [뽑기] 사이가 ${pull.top - odds.bottom} — 사이에 다른 것이 있다")
        assertTrue(odds.left < pull.right && pull.left < odds.right, "확률 보기 줄과 [뽑기] 가 가로로 겹치지 않는다(같은 열이 아니다)")
        assertTrue(exchange.top >= pull.bottom, "조각 교환이 [뽑기] 위에 있다")
        // 줄 하나 · 단추 하나(같은 꼬리표가 둘이면 자리 판정이 거짓이다).
        assertEquals(1, onAllNodesWithTag(GachaCardTags.ODDS_ROW).fetchSemanticsNodes().size)
        assertEquals(1, onAllNodesWithTag(GachaCardTags.PULL).fetchSemanticsNodes().size)
    }

    // MARK: ③ 확률 합 ≠ 100% 면 숨긴다

    @Test
    fun gachaCardHiddenWhenOddsDoNotSumTo100() {
        // 기준선: 서버 표 그대로(합 100) — 카드가 선다.
        val complete = shop()
        assertTrue(complete.showsGacha)
        assertEquals(3, cardCount(complete), "기준선: 합 100% 인 표에서 뽑기 카드 · 확률 보기 줄 · [뽑기] 가 안 섰다 — 아래 '안 선다'가 아무것도 안 잰다")
        // 여우 24 → 23: 합 99%. 서버가 준 표지만 공개 못 한 확률로 루비를 받지 않는다(W2-c showsGacha · 코어 isUsable).
        val short = shop(odds = """"character_id": "fox",
        "percent": 24=$FOX_23""")
        assertFalse(short.showsGacha)
        assertEquals(0, cardCount(short), "합 99% 인 표인데 뽑기 카드(확률 보기 · 뽑기)가 섰다")
        // 합 101% 도 숨긴다.
        val over = shop(odds = """"character_id": "fox",
        "percent": 24=$FOX_25""")
        assertEquals(0, cardCount(over), "합 101% 인 표인데 뽑기 카드가 섰다")
    }

    /** 카드 · 확률 보기 줄 · [뽑기] 꼬리표 수의 합(카드가 서면 3, 숨으면 0). */
    private fun cardCount(store: MeStore): Int {
        var n = -1
        runDesktopComposeUiTest(W, SHOP_H) {
            setContent { W4cDesktopSnapshots.frame(false, W, SHOP_H) { MeShopContent(store, {}, {}, {}, {}, scrolls = false) }() }
            n = onAllNodesWithTag(GachaCardTags.CARD).fetchSemanticsNodes().size +
                onAllNodesWithTag(GachaCardTags.ODDS_ROW).fetchSemanticsNodes().size +
                onAllNodesWithTag(GachaCardTags.PULL).fetchSemanticsNodes().size
        }
        return n
    }

    // MARK: ④ 확률 숫자는 서버 값

    @Test
    fun oddsSummaryFollowsServerNumbers() {
        val base = shop()
        assertEquals("황금 아잉이 3% · 무지개 아잉이 2%", GachaOddsSummary.text(base.gachaOddsRows))
        // 서버가 황금 3 → 4, 여우 24 → 23 으로 바꿨다(합은 그대로 100) — 화면 글자도 따라 바뀐다(앱에 숫자가 박혀 있으면 3% 로 남는다).
        val moved = shop(odds = """"character_id": "aing_gold",
        "percent": 3=$GOLD_4;"character_id": "fox",
        "percent": 24=$FOX_23""")
        assertTrue(moved.showsGacha)
        assertEquals("황금 아잉이 4% · 무지개 아잉이 2%", GachaOddsSummary.text(moved.gachaOddsRows))
        var shown: String? = null
        runDesktopComposeUiTest(W, SHOP_H) {
            setContent { W4cDesktopSnapshots.frame(false, W, SHOP_H) { MeShopContent(moved, {}, {}, {}, {}, scrolls = false) }() }
            shown = onNodeWithTag(GachaCardTags.ODDS_ROW).description()
        }
        assertNotNull(shown)
        assertTrue("황금 아잉이 4%" in shown!!, "확률 보기 줄이 서버 숫자를 말하지 않는다: $shown")
    }

    private fun SemanticsNodeInteraction.description(): String =
        fetchSemanticsNode().config.getOrElse(androidx.compose.ui.semantics.SemanticsProperties.ContentDescription) { emptyList() }.joinToString(" ")

    private companion object {
        const val W = 390
        const val SHOP_H = 1240
        const val ODDS_H = 780
        const val EXCHANGE_H = 760
        const val GIFT_H = 420
        const val TITLE_H = 80
        // 픽스처 조각 바꾸기(줄바꿈 · 들여쓰기는 픽스처 원문 그대로).
        const val FOX_23 = "\"character_id\": \"fox\",\n        \"percent\": 23"
        const val FOX_25 = "\"character_id\": \"fox\",\n        \"percent\": 25"
        const val GOLD_4 = "\"character_id\": \"aing_gold\",\n        \"percent\": 4"
    }
}
