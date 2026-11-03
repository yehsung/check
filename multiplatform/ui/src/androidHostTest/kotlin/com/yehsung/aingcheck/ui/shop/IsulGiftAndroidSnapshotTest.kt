// 원본: Sources/check/CheckCakeGiftWindow.swift @ 12624739 (맥 0.3.74 술 한잔 초대장 inviteScreen) · Sources/CheckCore/CharacterGift.swift(DrinkGiftText)
//
// 이슬 아잉이(Android 판 7) 화면 스냅숏 — W4cAndroidSnapshotTest 와 같은 틀(폰 = Android xhdpi 배율 2, Robolectric NATIVE 그래픽, 에뮬레이터·창 없음)과
// 같은 세 판정: ① 새로 세 번 그려도 같다 ② 골든과 같다(기록 AINGCHECK_SNAPSHOT_RECORD=1, 이 맥에서만) ③ 한 군데 다른 같은 크기 장면은 다르다.
// 골든: ui/snapshots/shop/android/<name>.png — 술 한잔 받는 창(라이트 · 다크) · 다시 열기 줄 · 이슬 잠긴 칸이 선 상점.
// 장면의 스토어는 Android 그림 집합(초상 열둘 — 번호 5)으로 서버 실출력 모양(20261108122000 p ≥ 5: gift.kind · 이슬 행)을 읽는다.
package com.yehsung.aingcheck.ui.shop

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.character.gift.DrinkGiftText
import com.yehsung.aingcheck.core.stores.me.MeCakeGiftSheet
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.dismissCakeGiftSheet
import com.yehsung.aingcheck.core.wire.gift.CharacterGiftKind
import com.yehsung.aingcheck.ui.components.AndroidSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import com.yehsung.aingcheck.ui.theme.AingTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w400dp-h1700dp-xhdpi")
class IsulGiftAndroidSnapshotTest {
    private val art: RepoMeArt by lazy { RepoMeArt { path -> File(AndroidSnapshots.repoRoot, path).takeIf { it.isFile }?.readBytes() } }

    private fun frame(dark: Boolean, w: Int, h: Int, content: @Composable () -> Unit): @Composable () -> Unit = {
        CompositionLocalProvider(LocalMeArt provides art) {
            AingTheme(dark = dark) { Box(Modifier.size(w.dp, h.dp).background(AingTheme.colors.background)) { content() } }
        }
    }

    private fun drinkStore(note: String?): Pair<MeStore, MeCakeGiftSheet> {
        val store = loadedMeStore(
            MeScene(shopState = MeScreenFixtures.isulShopState(), giftPending = MeScreenFixtures.drinkPending(note)),
            drawable = MeScreenFixtures.androidPortraits,
        )
        val sheet = requireNotNull(store.cakeGiftSheet) { "술 선물 시트가 서지 않았다" }
        assertEquals(CharacterGiftKind.drink, sheet.kind)
        assertEquals("aing_isul", sheet.selection)
        return store to sheet
    }

    /** 받는 창(초대장) — 운영자 한 줄이 크게, 본문이 작게. 기준선: 한 줄의 한 글자만 다르다("한잔" → "두잔"). */
    @Test
    fun drinkGiftLight() {
        fun scene(note: String): @Composable () -> Unit {
            val (store, sheet) = drinkStore(note)
            return frame(false, W, SHEET_H) { MeCakeGiftSheetContent(store, sheet, scrolls = false) }
        }
        check("drink-gift-light", scene("오늘 한잔 어때?"), scene("오늘 두잔 어때?"))
    }

    /** 다크 + 운영자 한 줄 없음(본문이 초대장의 큰 글). 기준선: 한 줄이 있는 장면(카드가 한 줄만큼 커져 아래가 밀린다 — 차이 허용 0.35). */
    @Test
    fun drinkGiftDarkWithoutNote() {
        fun scene(note: String?): @Composable () -> Unit {
            val (store, sheet) = drinkStore(note)
            return frame(true, W, SHEET_H) { MeCakeGiftSheetContent(store, sheet, scrolls = false) }
        }
        check("drink-gift-dark", scene(null), scene("짠"), maxChangedFraction = 0.35)
    }

    /**
     * 검토 ISUL-2: 좁은 폰 · 큰 글꼴(2.0 배)에서 초대장 카드의 글(운영자 한 줄 · 본문)이 말없이 잘리지 않고 줄을 늘린다. 시트는 세로로
     * 스크롤되므로 줄 수를 막을 까닭이 없다(맥은 고정 창이라 lineLimit 2 + minimumScaleFactor 0.75 였다). 한 줄이 없으면 본문이 큰 글(headline),
     * 긴 한 줄이 있으면 그 줄이 큰 글(title3)이다 — 둘 다 큰 글이 2 줄을 넘는 배치에서 잰다(실측: 본문 320dp 3 줄 · 한 줄 360dp 3 줄.
     * 본문은 360dp 에선 이 렌더러 글꼴로 2 줄에 든다). 수리 전(maxLines = 2) 빨강: 본문 320dp "잘렸다(줄 2)".
     */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun inviteCardTextWrapsInsteadOfClippingAtLargeFontScale() {
        val longNote = "오늘 하루도 정말 고생 많았어요. 퇴근길에 한잔하면서 푹 쉬어요!"
        for ((note, width) in listOf(null to 320, longNote to 360)) {
            val (store, sheet) = drinkStore(note)
            runComposeUiTest {
                setContent {
                    val base = LocalDensity.current
                    CompositionLocalProvider(LocalDensity provides Density(base.density, fontScale = 2f)) {
                        frame(false, width, 1600) { MeCakeGiftSheetContent(store, sheet, scrolls = false) }()
                    }
                }
                waitForIdle()
                for (text in listOfNotNull(note, DrinkGiftText.body)) {
                    val node = onNode(hasText(text), useUnmergedTree = true).fetchSemanticsNode()
                    val layouts = mutableListOf<TextLayoutResult>()
                    node.config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
                    val layout = layouts.single()
                    println("AINGCHECK-INVITE-LINES note=${note != null} w=$width text=${text.take(8)} lines=${layout.lineCount} overflow=${layout.hasVisualOverflow}")
                    assertFalse("'$text' 이(가) 잘렸다(줄 ${layout.lineCount}) — 말줄임도 없이 뒷부분이 사라진다", layout.hasVisualOverflow)
                    assertEquals("'$text' 의 마지막 글자까지 그린다", text.length, layout.getLineEnd(layout.lineCount - 1, visibleEnd = true))
                }
                // 잴 만한 배치인가(기준선): 큰 글은 이 크기에서 2 줄을 넘는다 — 넘지 않으면 이 시험은 잘림을 잡지 못한다.
                val big = note ?: DrinkGiftText.body
                val layouts = mutableListOf<TextLayoutResult>()
                onNode(hasText(big), useUnmergedTree = true).fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
                assertTrue("큰 글이 2 줄을 넘는 배치여야 한다(${layouts.single().lineCount})", layouts.single().lineCount > 2)
            }
        }
    }

    /** 받지 않고 닫은 뒤 나 탭의 다시 열기 줄 — "짠! 선물이 왔어요" [받기] + 🥂. 기준선: 생일 선물 줄. */
    @Test
    fun drinkReopenRowLight() {
        fun scene(drink: Boolean): @Composable () -> Unit {
            val store = loadedMeStore(
                MeScene(
                    shopState = MeScreenFixtures.isulShopState(),
                    giftPending = if (drink) MeScreenFixtures.drinkPending() else MeScreenFixtures.giftPending,
                ),
                drawable = MeScreenFixtures.androidPortraits,
            )
            store.dismissCakeGiftSheet()
            return frame(false, W, 96) { MeCakeGiftReopenRow(store, Modifier.padding(16.dp)) }
        }
        check("drink-reopen-light", scene(true), scene(false), maxChangedFraction = 0.6)
    }

    /** 이슬 잠긴 칸이 선 상점(모두에게 — 케이크와 같게, "술 한잔 선물 전용"). 기준선: 조각 수 한 자리. */
    @Test
    fun shopWithIsulLockedCellLight() {
        fun scene(shards: Int): @Composable () -> Unit {
            val json = MeScreenFixtures.isulShopState().replacingOnce("\"shards\": 23", "\"shards\": $shards")
            val store = loadedMeStore(MeScene(shopState = json), drawable = MeScreenFixtures.androidPortraits)
            assertTrue("이슬 행이 상점에 선다", store.shopCharacters.any { it.id == "aing_isul" })
            return frame(false, W, 1240) { MeShopContent(store, {}, {}, {}, {}, scrolls = false) }
        }
        check("shop-isul-light", scene(23), scene(24))
    }

    @OptIn(ExperimentalTestApi::class)
    private fun render(content: @Composable () -> Unit): PixelImage {
        var out: PixelImage? = null
        runComposeUiTest {
            setContent { Box(Modifier.wrapContentSize(Alignment.TopStart, unbounded = true).testTag(TAG)) { content() } }
            waitForIdle()
            out = AndroidSnapshots.pixels(onNodeWithTag(TAG).captureToImage())
        }
        return requireNotNull(out)
    }

    private fun check(name: String, scene: @Composable () -> Unit, other: @Composable () -> Unit, maxChangedFraction: Double = 0.1) {
        val renders = List(3) { render(scene) }
        val out = AndroidSnapshots.outDir()
        for (i in 1..2) {
            val d = SnapshotCompare.diff(renders[0], renders[i])
            if (!d.identical) {
                AndroidSnapshots.writePng(renders[i], File(out, "$name-render${i + 1}.png"))
                fail("$name: 1장과 ${i + 1}장이 다르다($d) — 렌더가 굳지 않았다")
            }
        }
        val actual = renders[0]
        assertTrue("$name: 색이 ${actual.distinctColors()}개뿐 — 장면이 그려지지 않았다", actual.distinctColors() >= 64)
        val golden = AndroidSnapshots.golden(GROUP, name)
        if (AndroidSnapshots.recording()) {
            AndroidSnapshots.writePng(actual, golden)
            fail("$name: 골든을 기록했다(${golden.path}) — 기록 실행은 실패로 끝난다. 기록 변수 없이 다시 돌려 대조한다.")
        }
        assertTrue("$name: 골든이 없다(${golden.path})", golden.isFile)
        val expected = AndroidSnapshots.readPng(golden)
        val exact = SnapshotPolicy.isRecordingHost(System.getProperty("os.name"), System.getProperty("os.arch"))
        val diff = SnapshotCompare.diff(expected, actual)
        val coarse = SnapshotCompare.coarse(expected, actual)
        println("AINGCHECK-SNAPSHOT android $name mode=${if (exact) "exact" else "coarse"} ${actual.width}x${actual.height} diff=$diff coarse=$coarse")
        if (!(if (exact) diff.identical else coarse.withinTolerance)) {
            AndroidSnapshots.writePng(actual, File(out, "$name-actual.png"))
            SnapshotCompare.diffImage(expected, actual)?.let { AndroidSnapshots.writePng(it, File(out, "$name-diff.png")) }
            fail("$name: 골든과 다르다($diff · $coarse) — build/aingcheck-snapshots/android/$name-{actual,diff}.png")
        }
        val baseline = render(other)
        assertEquals("$name: 기준선 크기가 다르다", actual.width to actual.height, baseline.width to baseline.height)
        val negative = SnapshotCompare.diff(actual, baseline)
        val negativeCoarse = SnapshotCompare.coarse(actual, baseline)
        println("AINGCHECK-SNAPSHOT-NEGATIVE android $name diff=$negative coarse=$negativeCoarse")
        assertFalse("$name: 한 군데 다른 장면인데 같은 픽셀", negative.identical)
        assertTrue("$name: 기준선 차이 ${negative.differingPixels}px — 한 군데만 달라야 한다", negative.differingPixels in 1 until (actual.argb.size * maxChangedFraction).toInt())
        assertFalse("$name: 굵은 대조가 한 군데 다른 장면을 못 잡는다($negativeCoarse)", negativeCoarse.withinTolerance)
    }

    private companion object {
        const val TAG = "isul-scene"
        const val GROUP = "shop"
        const val W = 390
        const val SHEET_H = 470
    }
}
