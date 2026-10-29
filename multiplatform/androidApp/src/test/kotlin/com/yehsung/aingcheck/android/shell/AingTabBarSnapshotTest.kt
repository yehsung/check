// 원본: Sources/CheckMobileKit/App/MobileRootView.swift @ 39199b0 (MobileTabsView — 기호 · 배지 · 나 탭 얼굴)
//
// 셸 탭 막대 스냅숏(밝음 · 어두움 × 배지 없음 · 있음, '나' 탭 = 착용 캐릭터 얼굴). 막대만 떼어 그린다(셸 전체 색은 ShellTabColorsTest).
// 어디서나 도는 구조 단언(자리표시 점 · M3 알약 · 아이콘을 대신하는 배지로 되돌리면 빨강):
//  ① 기호 넷(지금 · 메시지 · 순위 · 게임)은 탭 색 잉크가 MIN_SYMBOL_PX 이상, 잉크 너비가 MIN_SYMBOL_WIDTH_DP 이상(10dp 점은 너비 20px · 약 270px)
//  ② '나' 칸은 초상(서로 다른 색 MIN_FACE_COLORS 이상 — 단색 기호·점은 몇 가지뿐)
//  ③ 고른 칸에 받침 알약 색(secondaryContainer)이 0px
//  ④ 배지는 기호 칸의 오른쪽 위에 얹히고(왼쪽 끝 > 기호 가운데, 위 끝 < 기호 위 끝) 기호 잉크는 그대로 남는다
// 골든 대조는 기록 호스트(맥 arm64)에서만 — 기록은 AINGCHECK_SNAPSHOT_RECORD=1(그 실행은 실패로 끝난다). 증거 PNG 는 build/ 아래.
package com.yehsung.aingcheck.android.shell

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import com.yehsung.aingcheck.android.routing.AingTab
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.theme.AingColors
import com.yehsung.aingcheck.ui.theme.AingTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import kotlin.math.abs

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h740dp-xhdpi")
class AingTabBarSnapshotTest {
    @get:Rule
    val compose = createComposeRule()

    @Test fun lightPlain() = scene(dark = false, badges = false)
    @Test fun lightBadges() = scene(dark = false, badges = true)
    @Test fun darkPlain() = scene(dark = true, badges = false)
    @Test fun darkBadges() = scene(dark = true, badges = true)

    private fun scene(dark: Boolean, badges: Boolean) {
        val name = "tab-bar-${if (dark) "dark" else "light"}-${if (badges) "badges" else "plain"}"
        val art = portrait()
        var selectedInk = 0
        var unselectedInk = 0
        var pill = 0
        compose.setContent {
            AingTheme(dark = dark) {
                val scheme = MaterialTheme.colorScheme
                selectedInk = scheme.secondary.toArgb()
                unselectedInk = scheme.onSurfaceVariant.toArgb()
                pill = scheme.secondaryContainer.toArgb()
                AingTabBar(
                    selected = { it == SELECTED },
                    badge = { if (badges) BADGES[it] ?: 0 else 0 },
                    meFace = MeTabFace(art, CharacterMood.Working),
                    onSelect = {},
                )
            }
        }
        compose.waitForIdle()
        val density = compose.density.density

        for (tab in AingTab.entries) {
            val icon = pixels(compose.onNodeWithTag(ShellTabTags.icon(tab), useUnmergedTree = true).captureToImage())
            if (tab == AingTab.ME) {
                val colors = icon.argb.filter { (it ushr 24) == 0xFF }.toHashSet().size
                println("AINGCHECK-TABBAR $name ME face colors=$colors")
                assertTrue("$name '나' 칸이 캐릭터 얼굴이 아니다(서로 다른 색 $colors 가지)", colors >= MIN_FACE_COLORS)
                continue
            }
            val ink = if (tab == SELECTED) selectedInk else unselectedInk
            val count = icon.argb.count { it == ink }
            val width = icon.inkWidth(ink)
            println("AINGCHECK-TABBAR $name ${tab.name} ink=$count width=${width}px")
            assertTrue("$name ${tab.title} 기호 잉크가 모자라다($count px) — 자리표시 점으로 돌아갔나", count >= MIN_SYMBOL_PX)
            assertTrue("$name ${tab.title} 기호 너비가 좁다(${width}px) — 자리표시 점으로 돌아갔나", width >= MIN_SYMBOL_WIDTH_DP * density)
        }

        val selectedItem = pixels(compose.onNodeWithTag(ShellTabTags.tab(SELECTED)).captureToImage())
        assertEquals("$name 고른 칸에 받침 알약(M3 indicator)이 있다", 0, selectedItem.argb.count { it == pill })

        for (tab in AingTab.entries) {
            val nodes = compose.onAllNodesWithTag(ShellTabTags.badge(tab), useUnmergedTree = true).fetchSemanticsNodes()
            val expected = if (badges) BADGES[tab] ?: 0 else 0
            assertEquals("$name ${tab.title} 배지 수", if (expected > 0) 1 else 0, nodes.size)
            if (expected == 0) continue
            val badge = compose.onNodeWithTag(ShellTabTags.badge(tab), useUnmergedTree = true).getBoundsInRoot()
            val icon = compose.onNodeWithTag(ShellTabTags.icon(tab), useUnmergedTree = true).getBoundsInRoot()
            val iconCenter = (icon.left + icon.right) / 2
            println("AINGCHECK-TABBAR $name badge ${tab.name} badge=$badge icon=$icon")
            assertTrue("$name ${tab.title} 배지가 기호 오른쪽에 있지 않다", badge.left > iconCenter && badge.left < icon.right)
            assertTrue("$name ${tab.title} 배지가 기호 위쪽에 얹히지 않았다", badge.top < icon.top && badge.bottom > icon.top)
            val red = pixels(compose.onNodeWithTag(ShellTabTags.badge(tab), useUnmergedTree = true).captureToImage()).argb.count { it == AingColors.of(dark).badge.toArgb() }
            assertTrue("$name ${tab.title} 배지가 빨갛지 않다($red px)", red >= MIN_BADGE_RED_PX)
        }

        val bar = pixels(compose.onNodeWithTag(ShellTabTags.BAR).captureToImage())
        golden(name, bar)
    }

    // ---------------------------------------------------------------- 픽셀

    private class Pixels(val width: Int, val height: Int, val argb: IntArray) {
        /** [ink] 픽셀이 있는 열의 왼쪽 끝 ~ 오른쪽 끝. */
        fun inkWidth(ink: Int): Int {
            var min = Int.MAX_VALUE
            var max = -1
            for (y in 0 until height) for (x in 0 until width) if (argb[y * width + x] == ink) { min = minOf(min, x); max = maxOf(max, x) }
            return if (max < 0) 0 else max - min + 1
        }
    }

    private fun pixels(image: ImageBitmap): Pixels {
        val bitmap = image.asAndroidBitmap()
        val all = IntArray(bitmap.width * bitmap.height).also { bitmap.getPixels(it, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height) }
        return Pixels(bitmap.width, bitmap.height, all)
    }

    private fun repoRoot(): File = File(requireNotNull(System.getProperty("aingcheck.repoRoot")) { "aingcheck.repoRoot 없음 — Gradle 시험 작업으로 돌린다" })

    private fun portrait(): ImageBitmap {
        val file = File(repoRoot(), "Sources/CheckMobileShared/Resources/Portraits/aing-neutral.png")
        val options = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
        return requireNotNull(BitmapFactory.decodeFile(file.path, options)) { "초상 디코드 실패: $file" }.asImageBitmap()
    }

    private fun golden(name: String, image: Pixels) {
        val mp = File(repoRoot(), "multiplatform")
        val evidence = File(mp, "androidApp/build/aingcheck-snapshots/shell/$name.png")
        write(image, evidence)
        val golden = File(mp, "androidApp/snapshots/shell/$name.png")
        if (System.getenv(RECORD_ENV) == "1") {
            write(image, golden)
            fail("$name: 골든을 기록했다(${golden.path}) — 기록 실행은 실패로 끝난다. 기록 변수 없이 다시 돌려 대조한다.")
        }
        val recordingHost = System.getProperty("os.name")?.startsWith("Mac") == true && System.getProperty("os.arch") == "aarch64"
        if (!recordingHost) {
            println("AINGCHECK-TABBAR $name 골든 대조 건너뜀(기록 호스트 아님) — 구조 단언만")
            return
        }
        assertTrue("$name: 골든이 없다(${golden.path}) — 이 맥에서 $RECORD_ENV=1 로 기록한다", golden.isFile)
        val expected = BitmapFactory.decodeFile(golden.path, BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 })
        assertEquals("$name 크기", "${expected.width}x${expected.height}", "${image.width}x${image.height}")
        val want = IntArray(expected.width * expected.height).also { expected.getPixels(it, 0, expected.width, 0, 0, expected.width, expected.height) }
        val off = want.indices.count { i -> channelDelta(want[i], image.argb[i]) > GOLDEN_CHANNEL_DELTA }
        val ratio = off.toDouble() / want.size
        println("AINGCHECK-TABBAR $name golden off=$off ratio=$ratio")
        assertTrue("$name 골든과 다르다($off px, ${"%.4f".format(ratio)}) — 증거 ${evidence.path}", ratio <= GOLDEN_MAX_RATIO)
    }

    private fun channelDelta(a: Int, b: Int): Int =
        maxOf(abs((a ushr 24) - (b ushr 24)), abs((a shr 16 and 0xFF) - (b shr 16 and 0xFF)), abs((a shr 8 and 0xFF) - (b shr 8 and 0xFF)), abs((a and 0xFF) - (b and 0xFF)))

    private fun write(image: Pixels, file: File) {
        file.parentFile.mkdirs()
        val bitmap = Bitmap.createBitmap(image.argb, image.width, image.height, Bitmap.Config.ARGB_8888)
        file.outputStream().use { require(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) { "PNG 인코딩 실패" } }
    }

    private companion object {
        const val RECORD_ENV = "AINGCHECK_SNAPSHOT_RECORD"
        val SELECTED = AingTab.NOW
        /** iOS 배지가 서는 탭은 메시지 · 게임 · 나(MobileTabsView .badge). 두 자리 수는 옆으로 자라는지 본다. */
        val BADGES = mapOf(AingTab.MESSAGES to 3, AingTab.GAMES to 12, AingTab.ME to 1)

        /** 24dp 채움 기호의 잉크(xhdpi). 10dp 점은 안쪽 약 270px · 너비 20px 이라 둘 다 못 넘는다. */
        const val MIN_SYMBOL_PX = 400
        const val MIN_SYMBOL_WIDTH_DP = 16f
        const val MIN_FACE_COLORS = 40
        const val MIN_BADGE_RED_PX = 300
        const val GOLDEN_CHANNEL_DELTA = 48
        const val GOLDEN_MAX_RATIO = 0.01
    }
}
