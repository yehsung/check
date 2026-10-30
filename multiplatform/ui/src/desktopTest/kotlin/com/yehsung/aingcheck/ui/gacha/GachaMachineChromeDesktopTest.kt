// 원본: Sources/check/CheckGachaWindow.swift:88-98 · :152-172(뽑기 창 — ✕ 없음 · 아래 띠 오른쪽 oddsLink) · Sources/CheckMobileKit/Me/MeGachaViews.swift(폰 — ✕ · 위 오른쪽 확률 보기)
// 공용 패치 12(W-6 #7): MeGachaMachineScreen 의 chrome 매개. 기본(Sheet) = 지금 모양, Window = 맥 뽑기 창 자리.
// 진짜 나 탭 스토어(데모 픽스처)를 420×552(맥 뽑기 창 크기)에 그려 자리를 잰다.
package com.yehsung.aingcheck.ui.gacha

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.runDesktopComposeUiTest
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.gacha.GachaText
import com.yehsung.aingcheck.ui.shop.MeScene
import com.yehsung.aingcheck.ui.shop.loadedMeStore
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class)
class GachaMachineChromeDesktopTest {
    private fun scene(chrome: GachaMachineChrome?, check: androidx.compose.ui.test.ComposeUiTest.() -> Unit) = runDesktopComposeUiTest(W, H) {
        val store = loadedMeStore(MeScene())
        // 기계는 잦아들 때까지(실제 시계 수 초) 프레임을 청한다 — 시험 시계를 손으로 몇 장만 민다(자동 진행이면 waitForIdle 이 기계를 따라 돈다).
        mainClock.autoAdvance = false
        setContent {
            AingTheme(dark = false) {
                Box(Modifier.size(W.dp, H.dp)) {
                    if (chrome == null) MeGachaMachineScreen(store, onClose = {}) else MeGachaMachineScreen(store, onClose = {}, chrome = chrome)
                }
            }
        }
        repeat(5) { mainClock.advanceTimeByFrame() }
        check()
    }

    /** 기본값 = 지금 모양: 왼쪽 위 ✕ · 위쪽 [확률 보기] 알약(Android 호출처는 매개를 안 넘긴다). */
    @Test
    fun defaultIsTheSheetChrome() = scene(null) {
        val close = onNodeWithContentDescription("닫기").getBoundsInRoot()
        assertTrue(close.left < (W / 4).dp && close.top < (H / 4).dp, "✕ 가 왼쪽 위에 없다: $close")
        val odds = onNodeWithText(GachaText.oddsButton, useUnmergedTree = true).getBoundsInRoot()
        assertTrue(odds.top < (H / 4).dp && odds.left > (W / 2).dp, "확률 보기가 오른쪽 위에 없다: $odds")
        assertEquals(0, onAllNodesWithContentDescription(GachaText.oddsTitle).fetchSemanticsNodes().size, "기본 꼴에 창용 링크가 섰다")
    }

    /** 창 꼴: ✕ 없음 · [확률 보기] 는 아래 띠 오른쪽(맥 ZStack(alignment: .bottomTrailing) oddsLink). */
    @Test
    fun windowChromeHasNoCloseAndOddsSitsBottomTrailing() = scene(GachaMachineChrome.Window) {
        assertEquals(0, onAllNodesWithContentDescription("닫기").fetchSemanticsNodes().size, "창 꼴에 ✕ 가 남았다")
        val link = onNodeWithContentDescription(GachaText.oddsTitle).getBoundsInRoot()
        assertEquals(W.toFloat(), link.right.value, 0.5f, "링크가 오른쪽 끝에 붙지 않았다: $link")
        assertEquals(H.toFloat(), link.bottom.value, 0.5f, "링크가 아래 끝에 붙지 않았다: $link")
        // 무대(380×460)를 420×552 에 맞추면 아래 띠는 (552 − 460×420/380)/2 ≈ 21.8 — 링크는 그 띠 안이다(기계 알약을 안 가린다).
        val band = (H - 460f * (W / 380f)) / 2f
        assertTrue(link.top.value >= H - band - 0.5f, "링크가 띠를 넘어 기계 위로 올라왔다: $link (띠 $band)")
    }

    private companion object {
        const val W = 420
        const val H = 552
    }
}
