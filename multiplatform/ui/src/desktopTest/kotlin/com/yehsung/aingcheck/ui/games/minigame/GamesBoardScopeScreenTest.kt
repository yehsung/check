// 원본: Sources/CheckMobileKit/Games/GamesMiniGameScreen.swift:325-430 · Sources/CheckMobileKit/Rankings/RankingsBoardSections.swift:452-547 @ 1a5eeca6
//
// [오늘 | 역대] 를 **화면에서** 잰다(스토어 시험은 RankingsAllTimeTest · MiniGameAllTimeTest): 폰 경로는 전환을 누르면 표 · 제목 · 바닥이 바뀌고 어제 1등·상금은 [오늘] 에만 있다.
// Windows 경로(isPhone 기본값)는 전환이 없고 오늘 판 그대로다 — 스토어만 있고 화면에 안 붙는 일과, Windows 로 새는 일을 함께 막는다.
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardScope
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesBoardScopeTags
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.TestScope
import kotlin.test.Test
import kotlin.test.assertEquals

@OptIn(ExperimentalTestApi::class)
class GamesBoardScopeScreenTest {
    private val allTime = """[{"user_id":"u-1","display_name":"구름","avatar_url":null,"best_score":982,"best_at":"2026-09-13T01:10:00Z","day":"2026-09-13","center":null}]"""
    private val winner = """[{"user_id":"u-2","display_name":"어제왕","score":77,"awarded":true,"center":null}]"""

    private fun harness(scope: TestScope) = UiGamesHarness(scope, AppConfig()) { r ->
        when (r.rpcName) {
            "minigame_alltime_board" -> allTime to 200
            "minigame_yesterday_winner" -> winner to 200
            else -> UiFixtures.miniGameRoute(r) { 1 }
        }
    }

    @Test
    fun thePhonePathSwitchesTableTitleAndFooter() = runDesktopComposeUiTest(390, 1000) {
        val scope = TestScope()
        val h = harness(scope)
        runBlocking { h.signIn() }
        val store = GamesStore(h.context)
        setContent { AingTheme(dark = false) { GamesMiniGameScreen(store, MiniGameKind.flappy, 60, MiniGameArt.empty, null, isPhone = true) } }
        waitForIdle()
        scope.testScheduler.advanceUntilIdle()
        waitForIdle()
        onNodeWithTag(GamesBoardScopeTags.segment(MiniGameBoardScope.today)).assertIsSelected()
        onNodeWithText(MiniGameBoardScope.today.boardTitle).assertExists()
        onNodeWithText(GamesMiniGameText.prizeCaption).assertExists()
        onNodeWithText(GamesMiniGameText.yesterdayChampion, useUnmergedTree = true).assertExists()
        onNodeWithText(GamesMiniGameText.allTimeRuleCaption).assertDoesNotExist()

        onNodeWithTag(GamesBoardScopeTags.segment(MiniGameBoardScope.allTime)).performClick()
        waitForIdle()
        assertEquals(MiniGameBoardScope.allTime, store.miniGames.boardScope, "전환이 허브에 안 닿았다")
        scope.testScheduler.advanceUntilIdle()
        waitForIdle()
        onNodeWithTag(GamesBoardScopeTags.segment(MiniGameBoardScope.allTime)).assertIsSelected()
        onNodeWithText(MiniGameBoardScope.allTime.boardTitle).assertExists()
        onNodeWithText("9/13", useUnmergedTree = true).assertExists()
        onNodeWithText(GamesMiniGameText.allTimeRuleCaption).assertExists()
        onNodeWithText(GamesMiniGameText.allTimeDayCaption).assertExists()
        onNodeWithText(GamesMiniGameText.prizeCaption).assertDoesNotExist()
        onNodeWithText(GamesMiniGameText.yesterdayChampion, useUnmergedTree = true).assertDoesNotExist()
        h.close()
    }

    /** 준비 중 · 실패 표시도 화면까지 닿는다: 실패에는 [다시 시도] 가 있고, 준비 중에는 없다. */
    @Test
    fun theEmptyStatesReachTheScreen() = runDesktopComposeUiTest(390, 1000) {
        val scope = TestScope()
        var reply: Pair<String, Int> = """{"message":"upstream"}""" to 503
        val h = UiGamesHarness(scope, AppConfig()) { r -> if (r.rpcName == "minigame_alltime_board") reply else UiFixtures.miniGameRoute(r) { 1 } }
        runBlocking { h.signIn() }
        val store = GamesStore(h.context)
        setContent { AingTheme(dark = false) { GamesMiniGameScreen(store, MiniGameKind.flappy, 60, MiniGameArt.empty, null, isPhone = true) } }
        waitForIdle()
        scope.testScheduler.advanceUntilIdle()
        onNodeWithTag(GamesBoardScopeTags.segment(MiniGameBoardScope.allTime)).performClick()
        waitForIdle()
        scope.testScheduler.advanceUntilIdle()
        waitForIdle()
        onNodeWithText(GamesMiniGameText.allTimeFailedCaption, useUnmergedTree = true).assertExists()
        onNodeWithText(GamesMiniGameText.retry, useUnmergedTree = true).assertExists()
        reply = """{"code":"PGRST202","message":"Could not find the function in the schema cache"}""" to 404
        onNodeWithText(GamesMiniGameText.retry, useUnmergedTree = true).performClick()
        waitForIdle()
        scope.testScheduler.advanceUntilIdle()
        waitForIdle()
        onNodeWithText(GamesMiniGameText.allTimeUnavailableCaption, useUnmergedTree = true).assertExists()
        onNodeWithText(GamesMiniGameText.retry, useUnmergedTree = true).assertDoesNotExist()
        h.close()
    }

    /** Windows 경로: 전환이 없고 제목·바닥은 오늘 판 그대로다. */
    @Test
    fun theDefaultPathHasNoPicker() = runDesktopComposeUiTest(390, 1000) {
        val scope = TestScope()
        val h = harness(scope)
        val store = GamesStore(h.context)
        setContent { AingTheme(dark = false) { GamesMiniGameScreen(store, MiniGameKind.flappy, 60, MiniGameArt.empty, null) } }
        waitForIdle()
        for (s in MiniGameBoardScope.entries) onNodeWithTag(GamesBoardScopeTags.segment(s)).assertDoesNotExist()
        onNodeWithText(GamesMiniGameText.rankTitle).assertExists()
        onNodeWithText(GamesMiniGameText.prizeCaption).assertExists()
        h.close()
    }
}
