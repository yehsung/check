// 원본: Sources/CheckMobileKit/Games/GamesGomokuScreen.swift @ 3bd04bd (AingConfirmSheet — 창 전체를 어둡게 덮는 확인)
//
// 8d 미해결: 확인 카드(기권 · 나가기)가 화면 안 덮개라 막이 탭 막대 · 상태 바까지 가지 않았다. 판 시트(BoardSheetWindowAndroidTest)와 같은 꼴을 잰다:
//  ① 따로 뜬 창(합성 뿌리 둘) ② 그 창의 막이 BoardSheetScrim 과 같은 빛 ③ 떠 있는 동안 ModalPresence 가 센다(확성기 배너 미룸)
//  ④ 뒤로 가기 · 카드 바깥 누름 = 취소, 카드 안 누름 = 아무 일 없음(화면 안 덮개 때와 같다).
package com.yehsung.aingcheck.ui.games.gomoku

import android.view.WindowManager
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.test.topCenter
import com.yehsung.aingcheck.ui.components.LocalModalPresence
import com.yehsung.aingcheck.ui.components.ModalPresence
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowDialog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], qualifiers = "w400dp-h900dp-xhdpi")
class BoardConfirmWindowAndroidTest {
    private val tag = "confirm-under-test"

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun confirmCardStandsInItsOwnWindowWithTheScrimAndCountsAsAModal() = runComposeUiTest {
        val modals = ModalPresence()
        var showing by mutableStateOf(true)
        setContent {
            CompositionLocalProvider(LocalModalPresence provides modals) {
                BoardTestTheme(dark = true) {
                    Box(Modifier.fillMaxSize()) {
                        Text("판 화면")
                        if (showing) {
                            BoardConfirmOverlay("기권할까요?", "판돈을 잃어요", "기권", "계속", onConfirm = {}, onCancel = {}, testTag = tag)
                        }
                    }
                }
            }
        }
        waitForIdle()
        onNode(hasTestTag(tag)).assertExists()
        assertEquals("확인 카드가 화면 안 덮개다(합성 뿌리 하나) — 상태 바 · 탭 막대가 안 덮인다", 2, onAllNodes(isRoot()).fetchSemanticsNodes().size)
        val window = ShadowDialog.getLatestDialog().window!!
        assertTrue("창이 뒤를 어둡게 하지 않는다", window.attributes.flags and WindowManager.LayoutParams.FLAG_DIM_BEHIND != 0)
        assertEquals("창의 막이 판 시트 막과 다른 빛이다", BoardSheetScrim.alpha, window.attributes.dimAmount, 0.001f)
        assertEquals("확인 창이 떠 있는데 확성기 배너를 미루지 않는다", 1, modals.depth)
        showing = false
        waitForIdle()
        assertEquals("닫았는데 계수기가 남았다 — 배너가 영영 미뤄진다", 0, modals.depth)
    }

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun backAndOutsideCancelButTheCardBodyDoesNot() = runComposeUiTest {
        var cancels by mutableIntStateOf(0)
        var confirms by mutableIntStateOf(0)
        var showing by mutableStateOf(true)
        setContent {
            BoardTestTheme(dark = true) {
                Box(Modifier.fillMaxSize()) {
                    if (showing) {
                        BoardConfirmOverlay(
                            "기권할까요?", "판돈을 잃어요", "기권", "계속",
                            onConfirm = { confirms += 1 },
                            onCancel = { cancels += 1 },
                            testTag = tag,
                        )
                    }
                }
            }
        }
        waitForIdle()
        // 카드 윗변(제목 줄): 한가운데는 [확인] 단추 자리라 카드 면 누름이 안 된다.
        onNode(hasTestTag(tag)).performTouchInput { click(topCenter) }
        waitForIdle()
        assertEquals("카드 안을 눌렀는데 닫혔다", 0, cancels)
        ShadowDialog.getLatestDialog().onBackPressed()
        waitForIdle()
        assertEquals("뒤로 가기가 확인 창을 닫지 않는다", 1, cancels)
        // 카드 둘레 여백(창 안 · 카드 바깥) 누름: 화면 안 덮개 때 막 누름과 같다.
        onAllNodes(isRoot())[1].performTouchInput { click(topCenter) }
        waitForIdle()
        assertEquals("카드 바깥을 눌렀는데 닫히지 않는다", 2, cancels)
        onNode(hasTestTag("$tag-confirm")).performClick()
        waitForIdle()
        assertEquals(1, confirms)
        showing = false
    }
}
