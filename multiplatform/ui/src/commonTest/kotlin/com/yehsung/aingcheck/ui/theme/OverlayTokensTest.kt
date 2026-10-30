// 원본: Sources/check/CheckOverlayWindow.swift ~:2700(말풍선 — fill(white 0.92) · stroke(black 0.10) · 글자 black 0.85 · 화살표 black 0.45, 어둠 모드에서도 흰 캡슐)
//       Sources/check/CheckTodoBoardView.swift:147-162(todoBoardTextHalo — .black 그림자)
// 공용 패치 6(W-6 #7): 데스크톱 오버레이 말풍선 · 보드 토큰. 값은 W5-b2(BubbleStyle) · W5-b3(TodoBoardView 바탕 = surface)이 임시로 쓴 값 그대로다 —
// 데스크톱이 임시 계산을 이 토큰으로 갈아도 그림이 한 비트도 안 바뀌어야 한다.
package com.yehsung.aingcheck.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import kotlin.test.Test
import kotlin.test.assertEquals

class OverlayTokensTest {
    private fun hex(c: Color): String = (c.toArgb().toLong() and 0xFFFFFFFFL).toString(16).uppercase().padStart(8, '0')

    @Test
    fun bubbleTokensAreTheTemporaryValuesAndTheSameInBothModes() {
        val l = AingColors.Light
        for (c in listOf(AingColors.Light, AingColors.Dark)) {
            val mode = if (c.isDark) "다크" else "라이트"
            // W5-b2 BubbleStyle: AingColors.Light.surface/label 에 불투명도를 곱한 값(맥 말풍선은 다크에서도 흰 캡슐).
            assertEquals(hex(l.surface.copy(alpha = 0.92f)), hex(c.overlayBubbleFill), "$mode 말풍선 바탕")
            assertEquals(hex(l.label.copy(alpha = 0.10f)), hex(c.overlayBubbleStroke), "$mode 말풍선 테두리")
            assertEquals(hex(l.label.copy(alpha = 0.85f)), hex(c.overlayBubbleText), "$mode 말풍선 글자")
            assertEquals(hex(l.label.copy(alpha = 0.45f)), hex(c.overlayBubbleArrival), "$mode 도착 강조")
        }
        // 숫자로도 못박는다(라이트 표면 = 흰색 · 라이트 글자 = #0B0B10).
        assertEquals("EBFFFFFF", hex(l.overlayBubbleFill))
        assertEquals("1A0B0B10", hex(l.overlayBubbleStroke))
        assertEquals("D90B0B10", hex(l.overlayBubbleText))
        assertEquals("730B0B10", hex(l.overlayBubbleArrival))
    }

    @Test
    fun boardTokensFollowTheModeAndHaloIsBlack() {
        assertEquals(AingColors.Light.surface, AingColors.Light.boardTint, "라이트 보드 틴트 = W5-b3 바탕(surface)")
        assertEquals(AingColors.Dark.surface, AingColors.Dark.boardTint, "다크 보드 틴트 = W5-b3 바탕(surface)")
        for (c in listOf(AingColors.Light, AingColors.Dark)) assertEquals("FF000000", hex(c.boardTextHalo), "글자 후광 = 맥 .black")
    }
}
