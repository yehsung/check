// 원본: Sources/CheckMobileKit/Theme/MobileThemePalette.swift @ 862be0f (tabSelected · label2 숫자 — 탭 막대는 고른 탭만 tabSelected 로 칠한다)
//
// 셸 탭 막대 색(G §8-15 — 파랑은 '선택'을 뜻한다). 실제 MainActivity 를 띄워(테마를 감싸는 자리까지) 탭마다 픽셀을 센다:
//  ① 고른 탭(시작 탭 '지금')의 기호와 이름(secondary) = iOS tabSelected(라이트 #1864CF · 다크 #7DC0FF)
//  ② 안 고른 탭 넷에는 유채색 픽셀이 없고 기호는 회색(onSurfaceVariant = iOS label2 를 카드 위에 겹친 값 — 라이트 #6F6F74 · 다크 #A6A8B3)
//  ③ 막대 어디에도 보라(브랜드 보라·AI 토큰 보라·M3 기준 보라 — 색상각 245~330°)가 없다
// 기대값은 Swift 숫자를 손으로 옮긴 리터럴이다. 셸 화면 모드는 지금 OS 설정(System)이라 라이트·다크를 Robolectric 한정자(night)로 가른다.
package com.yehsung.aingcheck.android.shell

import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.core.app.ActivityScenario
import com.yehsung.aingcheck.android.routing.AingTab
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h740dp-xhdpi")
class ShellTabColorsTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    /** 이 시험은 셸(탭 · 딥링크 · 수락 증표)만 잰다 — 조립 화면 대신 자리표시 셸(K11 뒤 단계를 주입한다, W2-f §1). */
    @org.junit.Before
    fun placeholderShell() {
        val container = androidx.test.core.app.ApplicationProvider.getApplicationContext<com.yehsung.aingcheck.android.app.AingApplication>().container
        container.usePlaceholderShell()
        // 화면 모드 저장값의 기본은 다크다(W3-b 패치 0002 — iOS 와 같다). 이 시험은 OS 라이트·다크(qualifier)마다 탭 색을 재므로 '시스템'을 고른다.
        container.appearance.select(com.yehsung.aingcheck.ui.theme.AingAppearanceMode.System)
    }

    @Test
    @Config(qualifiers = "+notnight")
    fun lightTabBarPaintsOnlyTheSelectedTabBlue() = check("라이트", selectedInk = 0xFF1864CF.toInt(), unselectedInk = 0xFF6F6F74.toInt())

    @Test
    @Config(qualifiers = "+night")
    fun darkTabBarPaintsOnlyTheSelectedTabBlue() = check("다크", selectedInk = 0xFF7DC0FF.toInt(), unselectedInk = 0xFFA6A8B3.toInt())

    private fun check(mode: String, selectedInk: Int, unselectedInk: Int) {
        ActivityScenario.launch(MainActivity::class.java).use {
            val start = AingTab.NOW
            compose.onNodeWithTag(tag(start)).assertIsSelected()
            compose.waitForIdle()
            val bar = capture("tab-bar")
            val purple = bar.all.count(::isPurple)
            println("AINGCHECK-SHELL-TABS $mode bar=${bar.all.size}px purple=$purple")
            assertEquals("$mode 탭 막대에 보라 픽셀이 있다", 0, purple)
            for (tab in AingTab.entries) {
                // 탭 칸(AingTabBar)은 기호를 위 절반에, 이름을 아래 절반에 둔다 — 기호와 이름을 따로 센다
                // (이름 글자도 고른 탭이면 파랑이라 합쳐 세면 기호 색이 틀려도 넘어간다).
                val item = capture(tag(tab))
                val colored = item.all.count { chroma(it) > COLORED_CHROMA }
                val iconSelected = item.top.count { it == selectedInk }
                val iconGray = item.top.count { it == unselectedInk }
                val labelSelected = item.bottom.count { it == selectedInk }
                println("AINGCHECK-SHELL-TABS $mode ${tab.name} px=${item.all.size} colored=$colored icon(selectedInk=$iconSelected unselectedInk=$iconGray) label(selectedInk=$labelSelected)")
                if (tab == start) {
                    assertTrue("$mode 고른 탭(${tab.title})의 기호가 tabSelected #${hex(selectedInk)} 가 아니다($iconSelected px)", iconSelected >= MIN_SYMBOL_PIXELS)
                    assertTrue("$mode 고른 탭(${tab.title})의 이름이 tabSelected #${hex(selectedInk)} 가 아니다($labelSelected px)", labelSelected >= MIN_LABEL_PIXELS)
                } else {
                    assertEquals("$mode 안 고른 탭(${tab.title})에 유채색 픽셀이 있다 — 파랑은 '선택'만 뜻한다", 0, colored)
                    assertTrue("$mode 안 고른 탭(${tab.title})의 기호가 회색 #${hex(unselectedInk)} 가 아니다($iconGray px)", iconGray >= MIN_SYMBOL_PIXELS)
                }
            }
        }
    }

    private fun tag(tab: AingTab) = "tab:${tab.name.lowercase()}"

    /** 노드 그림의 ARGB 픽셀 — 전부 · 위 절반 · 아래 절반. */
    private class Capture(val all: IntArray, val top: IntArray, val bottom: IntArray)

    private fun capture(tag: String): Capture {
        val bitmap = compose.onNodeWithTag(tag).captureToImage().asAndroidBitmap()
        val w = bitmap.width
        val h = bitmap.height
        val all = IntArray(w * h).also { bitmap.getPixels(it, 0, w, 0, 0, w, h) }
        return Capture(all, all.copyOfRange(0, w * (h / 2)), all.copyOfRange(w * (h / 2), w * h))
    }

    private fun channels(argb: Int) = Triple(argb shr 16 and 0xFF, argb shr 8 and 0xFF, argb and 0xFF)

    private fun chroma(argb: Int): Int {
        val (r, g, b) = channels(argb)
        return maxOf(r, g, b) - minOf(r, g, b)
    }

    /** 유채색(채도 있는) 픽셀 가운데 색상각이 보라 띠(245~330°)인 것. 파랑 가족(#1864CF 215° · #7DC0FF 209°)은 여기 들지 않는다. */
    private fun isPurple(argb: Int): Boolean {
        val c = chroma(argb)
        if (c <= COLORED_CHROMA) return false
        val (r, g, b) = channels(argb)
        val max = maxOf(r, g, b)
        val h = when (max) {
            r -> 60.0 * (((g - b).toDouble() / c).mod(6.0))
            g -> 60.0 * ((b - r).toDouble() / c + 2)
            else -> 60.0 * ((r - g).toDouble() / c + 4)
        }
        return h in 245.0..330.0
    }

    private fun hex(argb: Int) = (argb.toLong() and 0xFFFFFF).toString(16).uppercase().padStart(6, '0')

    private companion object {
        /** 무채색 경계: 막대 면(다크 #2F3144 = 21)·회색 기호(#A6A8B3 = 13)는 아래, 파랑·보라 기호(130~183)는 위. */
        const val COLORED_CHROMA = 48

        /**
         * 24dp 채움 기호(Material Symbols)의 위 절반 잉크 — 실측 최소 544px('나' 사람 기호), 최대 1010px('지금' 시계).
         * 예전 자리표시 점(10dp — 안쪽 268px)은 못 넘는다(8b shell: 점으로 되돌리면 빨강).
         */
        const val MIN_SYMBOL_PIXELS = 400

        /** 고른 탭 이름('지금') 글자 가운데 잉크 그대로인 픽셀(실측 약 180px). */
        const val MIN_LABEL_PIXELS = 60
    }
}
