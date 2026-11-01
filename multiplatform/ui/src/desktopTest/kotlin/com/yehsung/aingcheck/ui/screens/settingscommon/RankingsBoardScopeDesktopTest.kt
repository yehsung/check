// 원본: Sources/CheckMobileKit/Rankings/RankingsBoardSections.swift:452-547 @ 1a5eeca6
// [순위] 탭 미니게임 [오늘 | 역대] 를 화면에서 잰다: 폰 경로만 전환이 서고 누르면 스토어에 닿는다 · [역대] 는 날짜·바닥 두 줄이 서고 상금이 없다 · Windows 경로(기본값)는 오늘 판 그대로다.
package com.yehsung.aingcheck.ui.screens.settingscommon

import androidx.compose.ui.Modifier
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.core.stores.rankings.RankingsBoard
import com.yehsung.aingcheck.core.stores.rankings.RankingsText
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardScope
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesBoardScopeTags
import com.yehsung.aingcheck.ui.screens.rankings.RankingsMyFace
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.test.Test
import kotlin.test.assertEquals

@OptIn(ExperimentalTestApi::class)
class RankingsBoardScopeDesktopTest {
    private val face = RankingsMyFace("fox", CharacterMood.Working)

    @Test
    fun thePhonePathShowsTheAllTimeTable() = runDesktopComposeUiTest(390, 1000) {
        val store = ScreenScenes.rankings(RankingsBoard.minigame, allTime = true)
        setContent { AingTheme(dark = false) { RankingsScene(store, face, Modifier, isPhone = true) } }
        waitForIdle()
        onNodeWithText(MiniGameBoardScope.allTime.boardTitle).assertExists()
        onNodeWithText("역대 · 마감 없이 이어져요").assertExists()
        onNodeWithText(GamesMiniGameText.allTimeRuleCaption).assertExists()
        onNodeWithText(GamesMiniGameText.allTimeDayCaption).assertExists()
        onNodeWithText(RankingsText.yesterdayChampion, useUnmergedTree = true).assertDoesNotExist()
        onNodeWithTag(GamesBoardScopeTags.segment(MiniGameBoardScope.today)).performClick()
        waitForIdle()
        assertEquals(MiniGameBoardScope.today, store.miniGameScope, "전환이 스토어에 안 닿았다")
        onNodeWithText(MiniGameBoardScope.today.boardTitle).assertExists()
        onNodeWithText(GamesMiniGameText.allTimeRuleCaption).assertDoesNotExist()
    }

    @Test
    fun theDefaultPathStaysOnToday() = runDesktopComposeUiTest(390, 1000) {
        val store = ScreenScenes.rankings(RankingsBoard.minigame)
        setContent { AingTheme(dark = false) { RankingsScene(store, face, Modifier) } }
        waitForIdle()
        for (s in MiniGameBoardScope.entries) onNodeWithTag(GamesBoardScopeTags.segment(s)).assertDoesNotExist()
        onNodeWithText(RankingsText.miniGameRankTitle).assertExists()
    }
}
