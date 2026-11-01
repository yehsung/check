// 원본 없음(iOS 는 눌림 표시를 버튼 모양이 알아서 자른다) — Compose 쪽 결함 회귀 시험.
//
// 게임 공용 알약 단추의 눌림 표시가 둥근 모양 밖 직사각형으로 번지던 결함: clickable 이 누름 영역(직사각형) 전체에 ripple 을 그렸다.
// 실제 화면을 픽셀로 잰다 — 누름 영역 안 · 알약 밖 자리는 누른 뒤에도 바탕 그대로고, 알약 안 자리는 바뀐다(대조군 — 눌림이 아예 안 그려져도 초록이 되지 않게).
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PixelMap
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.games.minigame.kit.PillButton
import com.yehsung.aingcheck.ui.games.minigame.kit.PillKind
import com.yehsung.aingcheck.ui.games.minigame.kit.PillSize
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class)
class PillButtonRippleTest {
    private fun colorDelta(a: Color, b: Color): Float =
        maxOf(kotlin.math.abs(a.red - b.red), kotlin.math.abs(a.green - b.green), kotlin.math.abs(a.blue - b.blue))

    /** [outside]: 누름 영역 안 · 알약 밖 자리(px). [inside]: 알약 안, 글자가 없는 자리(px). */
    private fun pressedPixels(size: PillSize, kind: PillKind, outside: (PixelMap) -> Pair<Int, Int>, inside: (PixelMap) -> Pair<Int, Int>): Pair<Float, Float> {
        var result = 0f to 0f
        runComposeUiTest {
            mainClock.autoAdvance = false
            setContent {
                AingTheme(dark = false) {
                    Box(Modifier.background(Color.White).padding(8.dp).testTag("frame")) {
                        PillButton("큐브 입장", Modifier.testTag("pill"), kind = kind, size = size, onClick = {})
                    }
                }
            }
            mainClock.advanceTimeBy(100)
            val before = onNodeWithTag("pill").captureToImage().toPixelMap()
            onNodeWithTag("pill").performTouchInput { down(Offset(width / 2f, height / 2f)) }
            mainClock.advanceTimeBy(1_000)
            val pressed = onNodeWithTag("pill").captureToImage().toPixelMap()
            assertEquals(before.width to before.height, pressed.width to pressed.height)
            val (ox, oy) = outside(before)
            val (ix, iy) = inside(before)
            result = colorDelta(before[ox, oy], pressed[ox, oy]) to colorDelta(before[ix, iy], pressed[ix, iy])
            onNodeWithTag("pill").performTouchInput { up() }
            mainClock.advanceTimeBy(1_000)
        }
        return result
    }

    @Test
    fun rippleStaysInsideThePillOnTheShortSizeWhereTheTargetIsTaller() {
        // Sm: 알약 34 · 누름 영역 44 — 위 5dp 띠는 알약 밖이다(가운데 칸에서 재면 모서리 곡선과 무관하다).
        val (outside, inside) = pressedPixels(
            PillSize.Sm, PillKind.Gray,
            outside = { it.width / 2 to 2 },
            inside = { it.width / 2 to (it.height / 2 + (34 * density(it) / 2).toInt() - 3) },
        )
        assertTrue(inside > 0.005f, "대조: 알약 안에는 눌림이 그려져야 한다(delta=$inside)")
        assertEquals(0f, outside, "알약 위 띠에 눌림이 번졌다")
    }

    @Test
    fun rippleStaysInsideTheRoundedCornersOnTheFullHeightSize() {
        // Md: 알약 높이 = 누름 영역 — 네 귀퉁이가 알약 밖이다. 옛 결함이 눈에 띄던 자리.
        val (outside, inside) = pressedPixels(
            PillSize.Md, PillKind.Gray,
            outside = { 1 to 1 },
            inside = { it.width / 2 to it.height - 4 },
        )
        assertTrue(inside > 0.005f, "대조: 알약 안에는 눌림이 그려져야 한다(delta=$inside)")
        assertEquals(0f, outside, "둥근 모양 밖 귀퉁이에 눌림이 번졌다")
    }

    /** 시험 화면의 밀도(높이 44dp 가 몇 px 인가). */
    private fun density(map: PixelMap): Float = map.height / 44f
}
