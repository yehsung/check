// 원본: Sources/CheckMobileKit/Games/GamesGomokuScreen.swift @ 3bd04bd (.sheet — 규칙 · 판돈 · AI 고르기가 창 전체를 어둡게 덮는다)
//
// 8c 스토어 05 결함: 판돈 시트 덮개가 탭 내용 칸만 **밝은 회색**(테마 글자색 × 0.32 — 다크에서 흰 막)으로 덮어 배경이 밝아지고,
// 상태 바 · 탭 막대는 덮이지 않았다. 여기서 두 가지를 잰다(Android 호스트 · 기본값 그대로 — 시험이 흘리는 값 없음):
//  ① 판 시트가 **따로 뜬 창**에 선다(합성 뿌리가 둘 — 화면 안 Box 덮개면 하나) → 상태 바 · 탭 막대까지 덮는 자리.
//  ② 막 색이 다크 배경을 **어둡게** 한다(밝히면 빨강).
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.theme.AingTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "w400dp-h900dp-xhdpi")
class BoardSheetWindowAndroidTest {
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun boardSheetCoversTheWholeWindowWithADarkScrim() = runComposeUiTest {
        var darkBackground = androidx.compose.ui.graphics.Color.Unspecified
        setContent {
            BoardTestTheme(dark = true) {
                darkBackground = AingTheme.colors.background
                Box(Modifier.size(400.dp, 800.dp)) {
                    Text("판 화면")
                    BoardSheetOverlay("판돈", onDismiss = {}, subtitle = "서연님에게 신청", testTag = "sheet-under-test") { Text("3 · 5 · 10") }
                }
            }
        }
        waitForIdle()
        onNode(hasTestTag("sheet-under-test")).assertExists()
        assertEquals("판 시트가 화면 안 덮개다(합성 뿌리 하나) — 상태 바 · 탭 막대가 안 덮인다", 2, onAllNodes(isRoot()).fetchSemanticsNodes().size)
        val veiled = BoardSheetScrim.compositeOver(darkBackground)
        assertTrue(
            "막이 다크 배경을 밝힌다(${darkBackground.luminance()} → ${veiled.luminance()}) — 검정 계열이어야 한다",
            veiled.luminance() < darkBackground.luminance(),
        )
    }
}
