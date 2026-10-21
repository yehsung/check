// 원본: Sources/CheckCore/MenuBarStatusFormatter.swift @ a63fea2 (localizedStatus·titleDuration·우선순위)
//       · Sources/check/CheckMenuView.swift:1160-1166 @ a63fea2 (빨간 점) — 시험은 새 코드: 설계 D§3-2·§4-2 · G §2-3 W1-f ②
//       · G §8-13(툴팁 문구는 맥 그대로: 근무중·근무종료) · R2 검증 지적(시험 이름은 '맥과 같다'인데 문구가 '근무 중'이었다)
package com.yehsung.aingcheck.desktop.platform.windows.tray

import com.yehsung.aingcheck.core.foundation.platform.desktop.RasterImage
import com.yehsung.aingcheck.desktop.platform.windows.support.Goldens
import java.io.File
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

    /**
     * 툴팁의 상태 글자가 맥 소스의 `localizedStatus` 글자와 **같은 글자**인지 맥 파일을 읽어 대조한다(기대값을 손으로 다시 적지 않는
     * 다른 출처 — 맥 문구가 바뀌면 여기서 먼저 빨갛다). 주석은 걷어 낸다(기억 source-contract-tests-need-comment-stripping).
     */
    @Test
    fun tooltipStatusWordsAreTheMacLocalizedStatusLiterals() {
        val repo = System.getProperty("aingcheck.repoRoot") ?: error("aingcheck.repoRoot 시스템 속성이 없다(aingcheck.test-seal 밖 실행)")
        val swift = File(repo, "Sources/CheckCore/MenuBarStatusFormatter.swift").readText()
        val code = swift.replace(Regex("""/\*[\s\S]*?\*/"""), "").lines().joinToString("\n") { it.replace(Regex("""//.*$"""), "") }
        // WorkStatusSnapshot 선언부(다음 선언 `enum WorkStatus` 앞까지)만 본다 — 그 안의 글자 return 은 localizedStatus 뿐이다.
        val start = code.indexOf("struct WorkStatusSnapshot")
        val end = code.indexOf("enum WorkStatus", start + 1)
        check(start >= 0 && end > start) { "맥 소스에서 WorkStatusSnapshot 선언을 못 찾았다" }
        val body = code.substring(start, end)
        val pending = Regex("""if\s+pendingSync\s*\{\s*return\s+"([^"]+)"""").find(body)?.groupValues?.get(1)
        val working = Regex("""case\s+\.working\s*:\s*return\s+"([^"]+)"""").find(body)?.groupValues?.get(1)
        val off = Regex("""case\s+\.offWork\s*:\s*return\s+"([^"]+)"""").find(body)?.groupValues?.get(1)
        checkNotNull(pending) { "맥 localizedStatus 의 동기화 대기 글자를 못 찾았다" }
        checkNotNull(working) { "맥 localizedStatus 의 근무 글자를 못 찾았다" }
        checkNotNull(off) { "맥 localizedStatus 의 근무 종료 글자를 못 찾았다" }
        assertEquals("아잉체크 · $working 00:00", TrayTooltip.text(TrayIconStatus.Working(0)))
        assertEquals("아잉체크 · $off", TrayTooltip.text(TrayIconStatus.Off))
        assertEquals("아잉체크 · $pending", TrayTooltip.text(TrayIconStatus.Pending))
    }

    @Test
    fun tooltipMatchesMacTitleRules() {
        assertEquals("아잉체크 · 근무중 01:23", TrayTooltip.text(TrayIconStatus.Working(1 * 3600 + 23 * 60 + 59)))
        assertEquals("아잉체크 · 근무중 27:05", TrayTooltip.text(TrayIconStatus.Working(27 * 3600 + 5 * 60)))
        assertEquals("아잉체크 · 근무종료", TrayTooltip.text(TrayIconStatus.Off))
        assertEquals("아잉체크 · 동기화 대기", TrayTooltip.text(TrayIconStatus.Pending))
        // 맥 우선순위: 동기화 대기 > 근무 중 > 오프.
        assertEquals(TrayIconStatus.Pending, TrayIconStatus.of(isWorking = true, elapsedSeconds = 60, pendingSync = true))
        assertEquals(TrayIconStatus.Working(60), TrayIconStatus.of(isWorking = true, elapsedSeconds = 60, pendingSync = false))
        assertEquals(TrayIconStatus.Off, TrayIconStatus.of(isWorking = false, elapsedSeconds = 60, pendingSync = false))
    }
}
