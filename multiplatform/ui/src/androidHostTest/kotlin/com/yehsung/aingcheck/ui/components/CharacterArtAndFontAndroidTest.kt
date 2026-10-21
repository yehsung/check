// 원본: Sources/check/Characters · Sources/check/Resources · Sources/CheckCore/Resources/Stickers @ 862be0f
//
// W1-e 완료 기준 ①·④(Android 호스트, Robolectric): Compose 리소스가 Android 자산으로 실려
//  - fox 매니페스트·초상·이모티콘을 Res 로 연다(Gradle Sync — 원본과 바이트가 같다)
//  - Pretendard 다섯 굵기가 번들 바이트 그대로이고, Compose 가 실제로 그 글꼴로 잰다(기본 글꼴과 폭이 다르다 · 굵기끼리 다르다)
// 이 시험은 ui/build.gradle.kts 의 androidResources.enable·Sync(조정자 패치 w1e-ui-build)가 있어야 돈다.
package com.yehsung.aingcheck.ui.components

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.ui.fonts.Pretendard
import com.yehsung.aingcheck.ui.fonts.pretendardFontFamily
import com.yehsung.aingcheck.ui.resources.Res
import kotlinx.coroutines.runBlocking
import org.jetbrains.compose.resources.ExperimentalResourceApi
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import kotlin.test.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.security.MessageDigest

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h640dp-xhdpi")
@OptIn(ExperimentalResourceApi::class, ExperimentalTestApi::class)
class CharacterArtAndFontAndroidTest {
    private val repo = AndroidSnapshots.repoRoot
    private fun sha(b: ByteArray) = MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }

    @Test
    fun foxManifestAndPortraitsLoadFromAndroidAssets() = runComposeUiTest {
        // Compose 리소스 읽개는 Android 문맥(AndroidContextProvider — 앱이 뜰 때 선다)으로 자산을 연다. 여기서는 활동이 이미 떠 있다.
        val manifest = runBlocking { Res.readBytes(CharacterArt.manifestPath("fox")) }
        assertArrayEquals(File(repo, "Sources/check/Characters/fox/manifest.json").readBytes(), manifest)
        assertTrue(manifest.decodeToString().contains("\"id\": \"fox\""))
        val portrait = runBlocking { Res.readBytes(CharacterArt.portraitPath("aing_rainbow", CharacterExpression.Negative)) }
        assertArrayEquals(File(repo, "Sources/check/Resources/aing_rainbow-negative.png").readBytes(), portrait)
        val img = assertNotNull(runBlocking { CharacterArt.decode(CharacterArt.portraitPath("fox", CharacterExpression.Neutral)) })
        assertEquals(192 to 192, img.width to img.height)
        val sticker = runBlocking { Res.readBytes(CharacterArt.stickerPath("joy")) }
        assertArrayEquals(File(repo, "${CharacterArt.STICKER_SOURCE_DIR}/sticker-joy.png").readBytes(), sticker)
    }

    @Test
    fun pretendardIsBundledAndUsedForMeasurement() = runComposeUiTest {
        var widths: List<Float> = emptyList()
        setContent {
            val measurer = rememberTextMeasurer()
            val family = pretendardFontFamily()
            val sample = "Pretendard 0123 WMiil"
            widths = listOf(
                measurer.measure(sample, TextStyle(fontFamily = family, fontSize = 20.sp)).size.width.toFloat(),
                measurer.measure(sample, TextStyle(fontFamily = FontFamily.Default, fontSize = 20.sp)).size.width.toFloat(),
                measurer.measure(sample, TextStyle(fontFamily = family, fontWeight = FontWeight.ExtraBold, fontSize = 20.sp)).size.width.toFloat(),
            )
        }
        waitForIdle()
        for (face in Pretendard.faces) assertEquals(face.path, face.sha256, sha(runBlocking { Res.readBytes(face.path) }))
        val (pretendard, system, extraBold) = widths
        assertTrue("폭이 0", pretendard > 0f)
        assertNotEquals("번들 글꼴과 기본 글꼴의 폭이 같다 — 번들 글꼴이 안 실렸다", system, pretendard)
        assertNotEquals("Regular 와 ExtraBold 폭이 같다 — 굵기가 안 실렸다", pretendard, extraBold)
    }
}
