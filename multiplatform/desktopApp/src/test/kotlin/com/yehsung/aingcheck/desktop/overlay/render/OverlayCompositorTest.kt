// 원본: CheckOverlayWindow.swift :779-853(몸 판정) · :2211-2250(hasShadow = false · 배경 투명) · 말풍선 .shadow(0.25, r3, y1)
//       설계 D §9-1(레이어드 창: 알파 0 = 뒤 창으로, 알파>0 = 우리 창이 클릭을 먹는다 → 몸·캡슐 밖 알파 0) · overlay.md §5 b2 OverlayCompositorTest
//
// 창 없이 오프스크린 RGBA 로만 잰다. 캐릭터 층은 합성 도형(굽기 자산 0 — 조정자 P2 전).
package com.yehsung.aingcheck.desktop.overlay.render

import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.desktop.overlay.engine.BubbleKind
import com.yehsung.aingcheck.desktop.overlay.engine.DuelGame
import com.yehsung.aingcheck.desktop.overlay.engine.FrameIntent
import com.yehsung.aingcheck.desktop.overlay.engine.HitTarget
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayBubble
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayMode
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayView
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class OverlayCompositorTest {
    private val compositor = OverlayCompositor()

    @AfterTest
    fun close() = compositor.close()

    // 2x 오버레이 창(140×170 DIP) — CharacterFrames.REFERENCE_VIEWPORT_HEIGHT 340 과 같은 뷰포트.
    private val w = 280
    private val h = 340
    private val scale = 2.0

    /** 합성 몸: 픽셀 사각형 [BODY] 를 직선 ARGB 0x80FF8000(반투명 주황)으로 채운다. */
    private val body = CharacterLayer { canvas, _, _, _ ->
        val (l, t, r, b) = BODY
        canvas.fillQuad(listOf(Vec2(l, t), Vec2(r, t), Vec2(r, b), Vec2(l, b)), BODY_ARGB, additive = false)
    }

    private fun view(mode: OverlayMode = OverlayMode.Normal, bubble: OverlayBubble? = null) = OverlayView(
        mode = mode, characterId = "aing", bubble = bubble, activeReaction = null, reactionStartedAt = null, sleeping = false,
        facing = 0, walking = false, particles = emptyList(), frame = FrameIntent.Default(0), renderSuspended = false,
    )

    private val invite = OverlayBubble("민수님이 오목 대결을 신청했어요 · 루비 3", BubbleKind.Invite(DuelGame.GOMOKU, "m1"), shownAt = 0.0, until = 6.0)

    @Test
    fun cornersAreClearAndNoAlphaLeaksOutsideBodyOrCapsule_noShadow() {
        val f = compositor.compose(view(bubble = invite), w, h, scale, now = 1.0, character = body)
        for ((x, y) in listOf(0 to 0, w - 1 to 0, 0 to h - 1, w - 1 to h - 1)) assertEquals(0, f.alphaAt(x, y), "창 모서리 ($x,$y)")
        val cap = assertNotNull(f.bubbleRectPx, "말풍선을 그렸다")
        // 캡슐 사각형 모서리 픽셀은 둥근 모서리(10 DIP) 밖이다.
        assertEquals(0, f.alphaAt(cap.left, cap.top), "캡슐 왼쪽 위 모서리")
        assertEquals(0, f.alphaAt(cap.right - 1, cap.bottom - 1), "캡슐 오른쪽 아래 모서리")
        // 몸 마스크(반픽셀 가장자리 1px 여유) ∪ 캡슐 밖에 알파>0 픽셀이 하나라도 있으면 그림자·후광이 샌 것이다.
        val (l, t, r, b) = BODY
        val bodyMask = PxRect(l.toInt() - 1, t.toInt() - 1, r.toInt() + 1, b.toInt() + 1)
        val leaks = ArrayList<Pair<Int, Int>>()
        var capsuleInk = 0
        for (y in 0 until h) for (x in 0 until w) {
            val a = f.alphaAt(x, y)
            if (a == 0) continue
            if (cap.contains(x, y)) capsuleInk++ else if (!bodyMask.contains(x, y)) leaks += x to y
        }
        assertTrue(leaks.isEmpty(), "몸·캡슐 밖 알파>0 픽셀 ${leaks.size}개(처음 ${leaks.take(5)}) — 그림자 금지(D §9-1)")
        assertTrue(capsuleInk > cap.let { (it.right - it.left) * (it.bottom - it.top) } / 2, "캡슐이 실제로 칠해졌다")
    }

    @Test
    fun premultipliedRgbaBecomesBgraForTheLayeredWindow() {
        val f = compositor.compose(view(), w, h, scale, now = 1.0, character = body)
        val cx = ((BODY.l + BODY.r) / 2).toInt()
        val cy = ((BODY.t + BODY.b) / 2).toInt()
        val i = (cy * w + cx) * 4
        fun u(b: Byte) = b.toInt() and 0xFF
        // 직선 (a 128, r 255, g 128, b 0) → 프리멀티 RGBA (128, 64, 0, 128)
        val rgba = f.rgbaPremultiplied
        assertEquals(listOf(128, 64, 0, 128), listOf(u(rgba[i]), u(rgba[i + 1]), u(rgba[i + 2]), u(rgba[i + 3])), "프리멀티 RGBA")
        val bgra = f.toBgraPremultiplied()
        assertEquals(listOf(0, 64, 128, 128), listOf(u(bgra[i]), u(bgra[i + 1]), u(bgra[i + 2]), u(bgra[i + 3])), "프리멀티 BGRA(DIB 순서)")
        assertEquals(rgba.size, bgra.size)
    }

    @Test
    fun hitTargetFollowsPixelAlphaAndCapsule() {
        val f = compositor.compose(view(bubble = invite), w, h, scale, now = 1.0, character = body)
        val cap = f.bubbleRectPx!!
        assertEquals(HitTarget.Body, f.hitTarget(((BODY.l + BODY.r) / 2).toInt(), ((BODY.t + BODY.b) / 2).toInt()))
        assertEquals(HitTarget.Bubble, f.hitTarget((cap.left + cap.right) / 2, (cap.top + cap.bottom) / 2))
        assertEquals(HitTarget.None, f.hitTarget(w - 2, 2))
        assertEquals(HitTarget.None, f.hitTarget(-5, 10))
    }

    @Test
    fun hiddenModeAndExpiredBubbleDrawNothingOfThem() {
        val hidden = compositor.compose(view(OverlayMode.Hidden, invite), w, h, scale, now = 1.0, character = body)
        assertTrue(hidden.rgbaPremultiplied.all { it.toInt() == 0 }, "숨김은 전부 투명")
        assertNull(hidden.bubbleRectPx)
        val expired = compositor.compose(view(bubble = invite), w, h, scale, now = 6.0, character = body)
        assertNull(expired.bubbleRectPx, "until 이 지난 말풍선은 그리지 않는다")
        assertEquals(0, expired.alphaAt((BubbleMetricsPx.capsuleCenterX * scale).toInt(), (BubbleMetricsPx.capsuleCenterY * scale).toInt()))
    }

    private data class Box(val l: Double, val t: Double, val r: Double, val b: Double)

    private object BubbleMetricsPx {
        // 말풍선 자리(INSET 4·8) 안쪽 한 점 — 몸(아래 BODY)과 겹치지 않는다.
        const val capsuleCenterX = 30.0
        const val capsuleCenterY = 14.0
    }

    companion object {
        private val BODY = Box(100.0, 140.0, 200.0, 320.0)
        private const val BODY_ARGB = 0x80FF8000.toInt()
    }
}
