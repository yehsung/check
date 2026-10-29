// 원본: 없음 — 상점 · 뽑기 · 미션 화면 스냅숏(폰 = Android xhdpi 배율 2, Robolectric NATIVE 그래픽 + Compose 시험 규칙, 에뮬레이터·창 없음).
//
// 데스크톱 판(ShopScreenDesktopTest · MissionsScreenDesktopTest · GachaMachineFrameSnapshotDesktopTest)과 같은 장면 · 같은 세 판정:
//  ① 새로 세 번 그려도 같다 ② 골든과 같다(기록 AINGCHECK_SNAPSHOT_RECORD=1, 이 맥에서만) ③ 한 군데 다른 같은 크기 장면은 다르다.
// 골든: ui/snapshots/<group>/android/<name>.png. 폰 화면 갈래 대표 다섯 장(상점 · 확률 시트 · 미션 · 생일 선물 · 기계 황금 공개).
package com.yehsung.aingcheck.ui.shop

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.me.selectCakeGiftOption
import com.yehsung.aingcheck.ui.components.AndroidSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import com.yehsung.aingcheck.ui.gacha.MeGachaOddsSheetContent
import com.yehsung.aingcheck.ui.gacha.machine.GachaCapsuleSprites
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineArt
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineScaler
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineStage
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineTheme
import com.yehsung.aingcheck.ui.gacha.machine.MachineFrames
import com.yehsung.aingcheck.ui.missions.MeMissionsContent
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
class W4cAndroidSnapshotTest {
    private val art: RepoMeArt by lazy { RepoMeArt { path -> File(AndroidSnapshots.repoRoot, path).takeIf { it.isFile }?.readBytes() } }

    private fun frame(dark: Boolean, w: Int, h: Int, content: @Composable () -> Unit): @Composable () -> Unit = {
        CompositionLocalProvider(LocalMeArt provides art) {
            AingTheme(dark = dark) { Box(Modifier.size(w.dp, h.dp).background(AingTheme.colors.background)) { content() } }
        }
    }

    @Test
    fun shopLight() {
        fun scene(shards: Int): @Composable () -> Unit {
            val store = loadedMeStore(MeScene(shopState = MeScreenFixtures.shopState.replacingOnce("\"shards\": 23", "\"shards\": $shards")))
            return frame(false, W, 1240) { MeShopContent(store, {}, {}, {}, {}, scrolls = false) }
        }
        check("shop", "shop-light", scene(23), scene(24))
    }

    @Test
    fun oddsLight() {
        // 기준선: 로봇 한 줄만 이 빌드가 모르는 캐릭터로(그림 → 자리표시 · 이름 → id · 값 → —).
        fun scene(robot: String): @Composable () -> Unit {
            val json = if (robot == "robot") MeScreenFixtures.shopState else MeScreenFixtures.shopState.replacingOnce("\"character_id\": \"robot\"", "\"character_id\": \"$robot\"")
            val store = loadedMeStore(MeScene(shopState = json))
            return frame(false, W, 780) { MeGachaOddsSheetContent(store, onClose = {}, scrolls = false) }
        }
        check("gacha", "odds-light", scene("robot"), scene("zebra"))
    }

    @Test
    fun missionsLight() {
        // 기준선: 일일 「1:1 오목」 한 줄만 받음으로.
        fun scene(gomokuClaimed: Boolean): @Composable () -> Unit {
            val base = MeScreenFixtures.achievements
            val json = if (!gomokuClaimed) base else {
                val at = base.indexOf("\"key\": \"daily_gomoku\"")
                val claimed = base.indexOf("\"claimed\": false", at)
                base.substring(0, claimed) + "\"claimed\": true" + base.substring(claimed + "\"claimed\": false".length)
            }
            val store = loadedMeStore(MeScene(achievements = json))
            return frame(false, W, 1640) { MeMissionsContent(store, scrolls = false) }
        }
        check("missions", "missions-light", scene(false), scene(true))
    }

    @Test
    fun cakeGiftLight() {
        fun scene(pick: String?): @Composable () -> Unit {
            val store = loadedMeStore(MeScene(shopState = MeScreenFixtures.fixture("_me/rpc.shop_state@demo-gift.json"), giftPending = MeScreenFixtures.giftPending))
            if (pick != null) store.selectCakeGiftOption(pick)
            val sheet = requireNotNull(store.cakeGiftSheet) { "선물 시트가 서지 않았다" }
            return frame(false, W, 420) { MeCakeGiftSheetContent(store, sheet, scrolls = false) }
        }
        check("shop", "cake-gift-light", scene("aing_cake_choco"), scene(null), maxChangedFraction = 0.25)
    }

    @Test
    fun machineRevealGold() {
        fun scene(balance: Long) = frame(false, 380, 460) {
            val machine = remember {
                val n = GachaMachineArt.resourceNames
                GachaMachineArt(
                    art.peek(MeArtPaths.machine(n[0])), art.peek(MeArtPaths.machine(n[1])), art.peek(MeArtPaths.machine(n[2])),
                    art.peek(MeArtPaths.machine(n[3])), art.peek(MeArtPaths.machine(n[4])),
                )
            }
            val f = remember { MachineFrames.build("reveal-gold", balance, machine) }
            val sprites = remember { GachaCapsuleSprites(machine) }
            GachaMachineScaler {
                GachaMachineStage(f.d, f.env, GachaMachineTheme.of(false), sprites, f.now, { id -> art.peek(MeArtPaths.portrait(id)) }, art.peek(MeArtPaths.ruby(24f, 2f)))
            }
        }
        check("gacha", "machine-reveal-gold", scene(120), scene(121))
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

    private fun check(group: String, name: String, scene: @Composable () -> Unit, other: @Composable () -> Unit, maxChangedFraction: Double = 0.1) {
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
        val golden = AndroidSnapshots.golden(group, name)
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
        const val TAG = "w4c-scene"
        const val W = 390
    }
}
