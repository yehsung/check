package com.yehsung.aingcheck.desktop.platform.windows.tray

import com.yehsung.aingcheck.core.foundation.platform.desktop.RasterImage
import com.yehsung.aingcheck.desktop.platform.windows.support.Goldens
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * G §2-3 W1-f ②: 트레이 아이콘 그리기 골든 — 5크기(16·20·24·28·32 = 배율 100~200%) × 2테마 × 상태 4.
 * 렌더러는 글꼴·OS 그리기를 쓰지 않으므로 맥·Linux·Windows JVM 에서 비트가 같아야 한다(골든은 맥에서 기록, CI 두 OS 가 대조).
 * 골든 말고 성질도 잰다: 골든은 '바뀌었다'만 알고 '맞다'는 모른다.
 */
class TrayIconRendererTest {
    private val sizes = listOf(16, 20, 24, 28, 32)
    private val states = listOf(
        "working-0123" to (TrayIconStatus.Working(1 * 3600 + 23 * 60) to false),
        "working-1247-dot" to (TrayIconStatus.Working(12 * 3600 + 47 * 60) to true),
        "off-dot" to (TrayIconStatus.Off to true),
        "pending" to (TrayIconStatus.Pending to false),
    )

    private fun render(status: TrayIconStatus, dot: Boolean, theme: TaskbarTheme, size: Int): RasterImage =
        TrayIconRenderer.render(TrayIconSpec(status, dot, theme, size))

    private fun alpha(p: Int) = p ushr 24
    private fun px(img: RasterImage, x: Int, y: Int) = img.argb[y * img.width + x]

    @Test
    fun goldenImages() {
        var count = 0
        for (size in sizes) for (theme in TaskbarTheme.entries) for ((name, sd) in states) {
            val img = render(sd.first, sd.second, theme, size)
            Goldens.assertImage("tray/$name-${theme.name.lowercase()}-$size.png", img.width, img.height, img.argb)
            count++
        }
        assertEquals(40, count)
        Goldens.failIfRecording()
    }

    @Test
    fun sizesFollowWindowsSmallIconMetric() {
        assertEquals(listOf(16, 20, 24, 28, 32), listOf(100, 125, 150, 175, 200).map { TrayIconRenderer.sizeForScalePercent(it) })
        assertEquals(40, TrayIconRenderer.sizeForScalePercent(250))
    }

    @Test
    fun renderingIsDeterministic() {
        for (size in sizes) {
            val a = render(TrayIconStatus.Working(5000), true, TaskbarTheme.DARK, size)
            val b = render(TrayIconStatus.Working(5000), true, TaskbarTheme.DARK, size)
            assertContentEquals(a.argb, b.argb)
            assertEquals(size, a.width)
            assertEquals(size, a.height)
        }
    }

    @Test
    fun hoursChangeTheGlyphsMinutesOnlyTheTicks() {
        val one = render(TrayIconStatus.Working(1 * 3600), false, TaskbarTheme.DARK, 16)
        val two = render(TrayIconStatus.Working(2 * 3600), false, TaskbarTheme.DARK, 16)
        assertFalse(one.argb.contentEquals(two.argb), "1시와 2시가 같은 그림")
        // 16px(<24) 에는 눈금이 없다 → 같은 시의 분 차이는 그림을 바꾸지 않는다.
        assertContentEquals(
            render(TrayIconStatus.Working(3600 + 5 * 60), false, TaskbarTheme.DARK, 16).argb,
            render(TrayIconStatus.Working(3600 + 50 * 60), false, TaskbarTheme.DARK, 16).argb,
        )
        // 24px 이상은 15분 눈금 → 사분이 바뀌면 그림이 바뀐다.
        assertFalse(
            render(TrayIconStatus.Working(3600 + 5 * 60), false, TaskbarTheme.DARK, 24).argb
                .contentEquals(render(TrayIconStatus.Working(3600 + 50 * 60), false, TaskbarTheme.DARK, 24).argb),
        )
        // 같은 사분 안의 분 차이는 그림을 바꾸지 않는다(분 경계 1회 갱신이면 충분하다는 근거).
        assertContentEquals(
            render(TrayIconStatus.Working(3600 + 31 * 60), false, TaskbarTheme.DARK, 24).argb,
            render(TrayIconStatus.Working(3600 + 44 * 60), false, TaskbarTheme.DARK, 24).argb,
        )
    }

    @Test
    fun workingIsPurpleWithWhiteGlyphsAtTheCenter() {
        for (size in sizes) {
            val img = render(TrayIconStatus.Working(8 * 3600), false, TaskbarTheme.LIGHT, size)
            assertEquals(TrayIconRenderer.PURPLE, px(img, 1 + size / 8, size / 2), "왼쪽 바탕 $size")
            val whites = img.argb.count { it == TrayIconRenderer.WHITE }
            assertTrue(whites >= size / 2, "흰 글자 픽셀이 너무 적다($whites, $size)")
            // 모서리 바깥은 투명(둥근 사각형).
            assertEquals(0, alpha(px(img, 0, 0)), "모서리 $size")
        }
    }

    @Test
    fun redDotSitsTopRightAndOnlyWhenAsked() {
        for (size in sizes) {
            val with = render(TrayIconStatus.Off, true, TaskbarTheme.DARK, size)
            val without = render(TrayIconStatus.Off, false, TaskbarTheme.DARK, size)
            val x = (size * TrayIconRenderer.DOT_CENTER_X).toInt()
            val y = (size * TrayIconRenderer.DOT_CENTER_Y).toInt()
            assertEquals(TrayIconRenderer.RED, px(with, x, y), "점 중심 $size")
            assertNotEquals(TrayIconRenderer.RED, px(without, x, y), "점이 없어야 한다 $size")
            // 왼쪽 아래 사분면은 점과 무관하다.
            for (yy in size / 2 until size) for (xx in 0 until size / 2) assertEquals(px(without, xx, yy), px(with, xx, yy), "($xx,$yy) $size")
        }
    }

    @Test
    fun offFaceFollowsTaskbarThemeButWorkingDoesNot() {
        val light = render(TrayIconStatus.Off, false, TaskbarTheme.LIGHT, 24)
        val dark = render(TrayIconStatus.Off, false, TaskbarTheme.DARK, 24)
        assertEquals(TrayIconRenderer.FACE_ON_LIGHT, px(light, 12, 19))
        assertEquals(TrayIconRenderer.FACE_ON_DARK, px(dark, 12, 19))
        assertContentEquals(
            render(TrayIconStatus.Working(3600), false, TaskbarTheme.LIGHT, 24).argb,
            render(TrayIconStatus.Working(3600), false, TaskbarTheme.DARK, 24).argb,
        )
    }

    @Test
    fun pendingIsOrangeBang() {
        val img = render(TrayIconStatus.Pending, false, TaskbarTheme.DARK, 32)
        assertEquals(TrayIconRenderer.ORANGE, px(img, 4, 16))
        assertEquals(TrayIconRenderer.WHITE, px(img, 16, 12), "느낌표 기둥")
    }

    @Test
    fun hoursAboveNinetyNineAreCappedAndNegativeIsZero() {
        assertContentEquals(
            render(TrayIconStatus.Working(99 * 3600), false, TaskbarTheme.DARK, 20).argb,
            render(TrayIconStatus.Working(150 * 3600), false, TaskbarTheme.DARK, 20).argb,
        )
        assertContentEquals(
            render(TrayIconStatus.Working(0), false, TaskbarTheme.DARK, 20).argb,
            render(TrayIconStatus.Working(-30), false, TaskbarTheme.DARK, 20).argb,
        )
    }

    @Test
    fun tooltipMatchesMacTitleRules() {
        assertEquals("아잉체크 · 근무 중 01:23", TrayTooltip.text(TrayIconStatus.Working(1 * 3600 + 23 * 60 + 59)))
        assertEquals("아잉체크 · 근무 중 27:05", TrayTooltip.text(TrayIconStatus.Working(27 * 3600 + 5 * 60)))
        assertEquals("아잉체크 · 근무 종료", TrayTooltip.text(TrayIconStatus.Off))
        assertEquals("아잉체크 · 동기화 대기", TrayTooltip.text(TrayIconStatus.Pending))
        // 맥 우선순위: 동기화 대기 > 근무 중 > 오프.
        assertEquals(TrayIconStatus.Pending, TrayIconStatus.of(isWorking = true, elapsedSeconds = 60, pendingSync = true))
        assertEquals(TrayIconStatus.Working(60), TrayIconStatus.of(isWorking = true, elapsedSeconds = 60, pendingSync = false))
        assertEquals(TrayIconStatus.Off, TrayIconStatus.of(isWorking = false, elapsedSeconds = 60, pendingSync = false))
    }
}
