// 원본: 없음 — G §2-3 W4-a ③ 대국 중 뒤로가기(E:56) · Android 진입 함수(ChessDestination)의 배선 시험(오목 판 GomokuDestinationTest 와 같은 축).
//  - 사람과의 판(실서버 픽스처 chess_state__ok_mid_since0)이 흐르면 뒤로가기는 확인 — [나가기]만 떠난다.
//  - 로봇 섹션은 로봇 화면을 연 채로 들어오고, 뒤로가기는 로봇 화면부터 닫는다(로봇 판은 확인 없이 — 잃을 것이 없다).
//  - 승격 고르기가 떠 있으면 뒤로가기는 `cancelPromotion()` 하나로 닫는다(시트 ✕ 와 같은 문).
package com.yehsung.aingcheck.android.screens.games.chess

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.screens.games.gomoku.DestinationTestRig
import com.yehsung.aingcheck.android.screens.games.gomoku.repoFixture
import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.stores.chess.isAIMatch
import com.yehsung.aingcheck.core.stores.chess.startAIMatch
import com.yehsung.aingcheck.core.wire.games.ChessStatePayload
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.ui.games.chess.ChessScreenTags
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.theme.AingTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w400dp-h900dp-xhdpi")
class ChessDestinationTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private var leaves = 0

    private fun launch(rig: DestinationTestRig, dest: Dest.Chess): ActivityScenario<ComponentActivity> {
        val scenario = ActivityScenario.launch(ComponentActivity::class.java)
        scenario.onActivity {
            it.setContent {
                AingTheme(dark = false) { ChessDestination(dest, rig.games, rig.chess, BoardGameMe.unknown, onLeave = { leaves += 1 }) }
            }
        }
        compose.waitForIdle()
        return scenario
    }

    private fun ActivityScenario<ComponentActivity>.back() {
        onActivity { it.onBackPressedDispatcher.onBackPressed() }
        compose.waitForIdle()
    }

    private fun ActivityScenario<ComponentActivity>.screenOwnsBack(): Boolean {
        var owns = false
        onActivity { owns = it.onBackPressedDispatcher.hasEnabledCallbacks() }
        return owns
    }

    private fun midGame(): ChessStatePayload =
        SwiftJson.decode(ChessStatePayload.serializer(), repoFixture("Tests/checkTests/Fixtures/chess-rpc/chess_state__ok_mid_since0.json"))

    @Test
    fun backDuringALiveHumanMatchAsksAndOnlyTheConfirmLeaves() {
        val rig = DestinationTestRig(me = "aa000000-0000-4000-8000-0000000000a1")
        rig.chess.applyState(midGame())
        launch(rig, ChessRoute.match()).use { scenario ->
            compose.onNodeWithTag(ChessScreenTags.match).assertExists()
            assertTrue("사람과의 판이 흐르는데 화면이 뒤로가기를 안 먹는다", scenario.screenOwnsBack())
            scenario.back()
            compose.onNodeWithTag(ChessScreenTags.leaveConfirm).assertExists()
            assertEquals(0, leaves)
            scenario.back()
            compose.onNodeWithTag(ChessScreenTags.leaveConfirm).assertDoesNotExist()
            compose.onNodeWithTag(ChessScreenTags.match).assertExists()
            scenario.back()
            compose.onNodeWithTag("${ChessScreenTags.leaveConfirm}-confirm").performClick()
            compose.waitForIdle()
            assertEquals(1, leaves)
            assertFalse("나가기가 판을 끝냈다(기권이 아니다)", requireNotNull(rig.chess.match).isFinished)
        }
    }

    @Test
    fun robotSectionOpensTheRobotScreenAndBackClosesItFirst() {
        val rig = DestinationTestRig(me = null)
        launch(rig, ChessRoute.robot()).use { scenario ->
            compose.onNodeWithTag(ChessScreenTags.robotScreen).assertExists()
            assertTrue(scenario.screenOwnsBack())
            // 로봇 판을 두는 중에도 뒤로가기는 로봇 화면을 닫을 뿐(판은 남는다 — 다시 열면 이어 둔다). 확인은 없다.
            rig.chess.startAIMatch(ChessColor.white)
            compose.waitForIdle()
            scenario.back()
            compose.onNodeWithTag(ChessScreenTags.robotScreen).assertDoesNotExist()
            compose.onNodeWithTag(ChessScreenTags.leaveConfirm).assertDoesNotExist()
            assertTrue("로봇 판이 뒤로가기로 사라졌다", rig.chess.isAIMatch)
            assertEquals(0, leaves)
        }
        // 기준선: 로비만 있으면 화면은 뒤로가기를 먹지 않는다.
        val lobby = DestinationTestRig(me = "aa000000-0000-4000-8000-0000000000a1")
        launch(lobby, ChessRoute.lobby()).use { scenario ->
            compose.onNodeWithTag(ChessScreenTags.lobby).assertExists()
            assertFalse("로비에서 화면이 뒤로가기를 먹는다 — 앱을 못 나간다", scenario.screenOwnsBack())
        }
    }

    @Test
    fun entryActionsKeepOnlyWatchRankingAndRobot() {
        assertEquals(ChessEntry.Action.Watch("w1"), ChessEntry.action("watch", "w1"))
        assertEquals(ChessEntry.Action.Ranking, ChessEntry.action("ranking", null))
        assertEquals(ChessEntry.Action.Robot, ChessEntry.action("ai", null))
        // 체스는 내 판을 코어가 로비 me.active_match_id 로 스스로 연다 — 초점 섹션은 로비로 접는다(Swift chessScreenDidAppear 는 focusMatchID 로 늘 nil).
        assertEquals(ChessEntry.Action.Lobby, ChessEntry.action("match", "m1"))
        assertEquals(ChessEntry.Action.Lobby, ChessEntry.action("invite", "i1"))
        assertEquals(ChessEntry.Action.Lobby, ChessEntry.action("watch", null))
        assertEquals(ChessEntry.Action.Lobby, ChessEntry.action("crossy", null))
        assertEquals(ChessEntry.Action.Robot, ChessRoute.robot().let { ChessEntry.action(it.section, it.matchId) })
    }
}
