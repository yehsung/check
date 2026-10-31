// 원본: 없음 — Android 13+ 테마 아이콘(iOS 에 없는 자리). res/mipmap-anydpi/ic_launcher*.xml 의 <monochrome> · res/drawable/ic_launcher_monochrome.xml
//
// 단색 층이 없으면 테마 아이콘을 켠 홈 화면에서 이 앱만 원색으로 남는다. 잰다: ① 네모 · 둥근 아이콘 둘 다 층이 붙었다 ② 그림 전체가 지름 66dp 안전 원 안이다(마스크에 안 잘린다)
// ③ 캐릭터로 읽힌다 — 눈 둘 · 입은 뚫렸고 그 둘레 얼굴 · 배 · 고리는 칠해졌고, 고리와 몸 사이는 비었다. 좌표는 전경 432px 판(1dp = 4px).
package com.yehsung.aingcheck.android.shell

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.AdaptiveIconDrawable
import androidx.test.core.app.ApplicationProvider
import com.yehsung.aingcheck.android.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36])
class LauncherMonochromeIconTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    private fun glyph(): Bitmap {
        val bitmap = Bitmap.createBitmap(SIZE, SIZE, Bitmap.Config.ARGB_8888)
        val drawable = requireNotNull(context.getDrawable(R.drawable.ic_launcher_monochrome))
        drawable.setBounds(0, 0, SIZE, SIZE)
        drawable.draw(Canvas(bitmap))
        return bitmap
    }

    private fun Bitmap.alphaAt(x: Int, y: Int): Int = android.graphics.Color.alpha(getPixel(x, y))

    @Test
    fun bothLauncherIconsCarryTheMonochromeLayer() {
        for ((name, id) in listOf("ic_launcher" to R.mipmap.ic_launcher, "ic_launcher_round" to R.mipmap.ic_launcher_round)) {
            val icon = context.getDrawable(id) as AdaptiveIconDrawable
            assertNotNull("$name 에 단색 층이 없다 — 테마 아이콘에서 이 앱만 원색으로 남는다", icon.monochrome)
        }
    }

    @Test
    fun glyphStaysInsideTheSafeCircle() {
        val bitmap = glyph()
        val safe = 33 * PX_PER_DP
        var painted = 0
        for (y in 0 until SIZE) for (x in 0 until SIZE) {
            if (bitmap.alphaAt(x, y) == 0) continue
            painted += 1
            val dx = x - SIZE / 2.0
            val dy = y - SIZE / 2.0
            assertTrue("($x,$y) 가 지름 66dp 안전 원 밖이다 — 마스크에 잘린다", dx * dx + dy * dy <= safe.toDouble() * safe)
        }
        assertTrue("칠한 면이 너무 적다($painted) — 실루엣이 비었다", painted > SIZE * SIZE / 12)
    }

    @Test
    fun glyphReadsAsTheCharacter() {
        val bitmap = glyph()
        fun opaque(what: String, x: Int, y: Int) = assertEquals("$what($x,$y)이 칠해져 있어야 한다", 255, bitmap.alphaAt(x, y))
        fun clear(what: String, x: Int, y: Int) = assertEquals("$what($x,$y)이 뚫려 있어야 한다", 0, bitmap.alphaAt(x, y))
        clear("왼눈", 201, 202)
        clear("오른눈", 236, 202)
        clear("입", 220, 215)
        opaque("미간", 218, 195)
        opaque("왼볼", 190, 225)
        opaque("배", 218, 250)
        opaque("고리 오른쪽", 216 + 102, 216)
        opaque("고리 아래", 216, 216 + 102)
        opaque("고리 끝 점", 105, 204)
        clear("고리와 몸 사이", 216, 216 + 80)
        clear("고리 빈 칸(왼쪽 위)", 216 - 72, 216 - 72)
    }

    private companion object {
        const val PX_PER_DP = 4
        const val SIZE = 108 * PX_PER_DP
    }
}
