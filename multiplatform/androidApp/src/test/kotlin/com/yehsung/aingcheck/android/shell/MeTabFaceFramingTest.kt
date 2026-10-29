// 원본: Sources/CheckMobileKit/Components/CharacterTabIcon.swift @ 862be0f (AingCharacterArt.avatarFraming) · Tests/CheckMobileKitTests/MeCakeGiftTests.swift (② 아바타 틀)
//
// '나' 탭 얼굴의 아바타 틀: 케이크 착용자도 원 안 얼굴(몸) 크기 · 자리가 아잉과 같아야 한다(iOS CharacterTabIcon — 케이크 초상은 장식 때문에
// 몸을 0.88 배로 줄여 내려 그렸다). **부르는 자리(AingTabBar ← MeTabFace.characterID)**를 그려 잰다:
//  ① 틀 값이 iOS 공식과 같다(케이크 둘만 identity 가 아니다 · 공백 접기 · 모르는 id 는 identity)
//  ② 탭 막대의 케이크 얼굴 몸 최대폭 · 그 줄 높이가 아잉 얼굴과 같다(채도로 몸을 가른다 — 받침 · 막대는 회색)
//  ③ 기준선이 다르다: 틀 없이 그린 케이크 얼굴은 아잉보다 몸이 좁다(이 시험이 늘 초록이 되는 그림이 아니다)
package com.yehsung.aingcheck.android.shell

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import com.yehsung.aingcheck.android.routing.AingTab
import com.yehsung.aingcheck.ui.components.AvatarFraming
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.CharacterTabIcon
import com.yehsung.aingcheck.ui.theme.AingTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
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
@Config(sdk = [36], qualifiers = "w360dp-h740dp-xxxhdpi")
class MeTabFaceFramingTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun cakeTabFaceMatchesAingBody() {
        // ① 틀 값(iOS avatarFraming: scale = 1/0.88, offsetY = ((96 − 28)/0.88 − 96)/192).
        val cakeFraming = AvatarFraming.of(CAKE)
        assertEquals(1 / 0.88f, cakeFraming.scale, 1e-4f)
        assertEquals((((96.0 - 28.0) / 0.88 - 96.0) / 192.0).toFloat(), cakeFraming.offsetY, 1e-4f)
        assertEquals(cakeFraming, AvatarFraming.of("aing_cake_choco"))
        assertEquals("착용값 접기와 같은 공백 규칙", cakeFraming, AvatarFraming.of(" $CAKE "))
        for (id in listOf(null, "", "aing", "aing_gold", "aing_rainbow", "fox", "모르는_id")) {
            assertEquals("$id", AvatarFraming.Identity, AvatarFraming.of(id))
        }

        // ②·③ 부르는 자리: 탭 막대 두 벌(아잉 · 케이크 착용) + 틀 없는 케이크 얼굴(기준선).
        val aing = portrait("aing-neutral")
        val cake = portrait("$CAKE-neutral")
        compose.setContent {
            AingTheme(dark = false) {
                Column {
                    AingTabBar(selected = { false }, badge = { 0 }, meFace = MeTabFace(aing, CharacterMood.Plain, "aing"), onSelect = {})
                    AingTabBar(selected = { false }, badge = { 0 }, meFace = MeTabFace(cake, CharacterMood.Plain, CAKE), onSelect = {})
                    Box(Modifier.testTag(RAW)) { CharacterTabIcon(cake, CharacterMood.Plain) }
                }
            }
        }
        compose.waitForIdle()
        val icons = compose.onAllNodesWithTag(ShellTabTags.icon(AingTab.ME), useUnmergedTree = true)
        val reference = bodyShape(icons[0].captureToImage())
        val framed = bodyShape(icons[1].captureToImage())
        val raw = bodyShape(compose.onNodeWithTag(RAW).captureToImage())
        println("AINGCHECK-FRAMING aing=$reference cake=$framed cakeRaw=$raw")
        assertTrue("몸을 못 찾았다(채도 문턱): $reference", reference.widest > 20)
        assertTrue("틀 없는 케이크가 이미 아잉 폭이다 — 기준선이 같다(raw=$raw · 아잉 $reference)", abs(raw.widest - reference.widest) > 4)
        assertTrue("케이크 얼굴 몸 폭이 아잉과 다르다 — 아바타 틀이 안 걸렸다(케이크 $framed · 아잉 $reference)", abs(framed.widest - reference.widest) <= 3)
        assertTrue("케이크 얼굴 몸 높이가 아잉과 다르다(케이크 $framed · 아잉 $reference)", abs(framed.widestY - reference.widestY) <= 4)
    }

    /** 최대폭 줄의 폭(px)과 그 줄의 높이(이미지 가운데 기준 — 칸 크기가 달라도 원은 가운데). 아래 절반에서만 잰다(장식은 머리 위다). */
    data class Shape(val widest: Int, val widestY: Int)

    private fun bodyShape(image: ImageBitmap): Shape {
        val bitmap = image.asAndroidBitmap()
        val w = bitmap.width
        val h = bitmap.height
        val px = IntArray(w * h).also { bitmap.getPixels(it, 0, w, 0, 0, w, h) }
        var widest = 0
        var widestY = 0
        for (y in h / 2 until h) {
            var min = w
            var max = -1
            for (x in 0 until w) {
                val c = px[y * w + x]
                val r = (c shr 16) and 0xFF
                val g = (c shr 8) and 0xFF
                val b = c and 0xFF
                if (maxOf(r, g, b) - minOf(r, g, b) > SATURATION) { min = minOf(min, x); max = maxOf(max, x) }
            }
            if (max >= min && max - min + 1 > widest) { widest = max - min + 1; widestY = y - h / 2 }
        }
        return Shape(widest, widestY)
    }

    private fun portrait(name: String): ImageBitmap {
        val root = File(requireNotNull(System.getProperty("aingcheck.repoRoot")) { "aingcheck.repoRoot 없음 — Gradle 시험 작업으로 돌린다" })
        val file = File(root, "Sources/CheckMobileShared/Resources/Portraits/$name.png")
        val options = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
        return requireNotNull(BitmapFactory.decodeFile(file.path, options)) { "초상 디코드 실패: $file" }.asImageBitmap()
    }

    private companion object {
        const val CAKE = "aing_cake_strawberry"
        const val RAW = "raw-cake-face"
        /** 몸(아잉 보라 · 케이크 분홍)과 회색 받침 · 막대를 가르는 채도(최대 − 최소 채널). */
        const val SATURATION = 40
    }
}
