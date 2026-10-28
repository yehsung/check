// 원본: 없음 — G §2-3 W4-a ③ 대국 중 뒤로가기(E:56) · Android 진입 함수(GomokuDestination)의 배선 시험.
//
// ui 모듈 시험(GomokuScreenFlowTest)은 화면 상태의 뒤로가기 계획을 잰다. 여기서는 **시스템 뒤로가기(OnBackPressedDispatcher)가 그 계획에 닿는가**를 잰다:
//  - 사람과의 판이 흐르면 뒤로가기는 화면이 먹고(확인을 띄운다) 목적지는 떠나지 않는다 — 확인의 [나가기]만 떠난다.
//  - 로비·AI 판·끝난 판은 BackHandler 가 꺼져 시스템(NavController)이 pop 한다(기준선 — 화면이 먹으면 앱을 못 나간다).
//  - 섹션 인자(관전 · AI 시트 · 순위)가 화면 상태로 들어가고, 뒤로가기가 그 덮개·관전을 먼저 걷는다.
package com.yehsung.aingcheck.android.screens.games.gomoku

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.stores.gomoku.startAIMatch
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.games.gomoku.GomokuScreenTags
import com.yehsung.aingcheck.ui.theme.AingTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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
class GomokuDestinationTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private var leaves = 0

    private fun launch(rig: DestinationTestRig, dest: Dest.Gomoku): ActivityScenario<ComponentActivity> {
        val scenario = ActivityScenario.launch(ComponentActivity::class.java)
        scenario.onActivity {
            it.setContent {
                AingTheme(dark = false) { GomokuDestination(dest, rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = { leaves += 1 }) }
            }
        }
        compose.waitForIdle()
        return scenario
    }

    private fun ActivityScenario<ComponentActivity>.back() {
        onActivity { it.onBackPressedDispatcher.onBackPressed() }
        compose.waitForIdle()
    }

    /** 화면이 뒤로가기를 먹는가(= BackHandler 가 켜졌는가). 꺼져 있으면 시스템이 NavController 로 pop 한다. */
    private fun ActivityScenario<ComponentActivity>.screenOwnsBack(): Boolean {
        var owns = false
        onActivity { owns = it.onBackPressedDispatcher.hasEnabledCallbacks() }
        return owns
    }

    @Test
    fun backDuringALiveHumanMatchAsksAndOnlyTheConfirmLeaves() {
        val rig = DestinationTestRig(me = DEST_ME)
        rig.gomoku.applyState(destinationGomokuState())
        launch(rig, GomokuRoute.match(DEST_MATCH)).use { scenario ->
            compose.onNodeWithTag(GomokuScreenTags.match).assertExists()
            assertTrue("사람과의 판이 흐르는데 화면이 뒤로가기를 안 먹는다 — 한 번에 대국을 떠난다", scenario.screenOwnsBack())

            scenario.back()
            compose.onNodeWithTag(GomokuScreenTags.leaveConfirm).assertExists()
            assertEquals("뒤로가기 한 번에 떠났다", 0, leaves)

            // 확인이 떠 있을 때 뒤로가기 = 확인 닫기(계속 두기). 판은 그대로.
            scenario.back()
            compose.onNodeWithTag(GomokuScreenTags.leaveConfirm).assertDoesNotExist()
            compose.onNodeWithTag(GomokuScreenTags.match).assertExists()
            assertEquals(0, leaves)

            // 다시 묻고 [나가기] 만 떠난다. 서버 시계는 흐른다 — 나가기는 기권이 아니다(판은 스토어에 남는다).
            scenario.back()
            compose.onNodeWithTag("${GomokuScreenTags.leaveConfirm}-confirm").performClick()
            compose.waitForIdle()
            assertEquals(1, leaves)
            assertEquals(DEST_MATCH, rig.gomoku.match?.id)
            assertFalse(rig.gomoku.match!!.isFinished)
        }
    }

    @Test
    fun lobbyAIMatchAndFinishedMatchLeaveBackToTheSystem() {
        // 로비 — 화면은 뒤로가기를 먹지 않는다(NavController 가 pop).
        val lobby = DestinationTestRig(me = DEST_ME)
        launch(lobby, GomokuRoute.lobby()).use { scenario ->
            compose.onNodeWithTag(GomokuScreenTags.lobby).assertExists()
            assertFalse("로비에서 화면이 뒤로가기를 먹는다 — 앱을 못 나간다", scenario.screenOwnsBack())
        }
        // AI 판 — 화면을 떠나면 AI 시계가 멈춘다(잃을 것이 없다) — 확인 없이 떠난다.
        val ai = DestinationTestRig(me = null)
        ai.gomoku.startAIMatch(GomokuColor.black)
        launch(ai, GomokuRoute.lobby()).use { scenario ->
            compose.onNodeWithTag(GomokuScreenTags.match).assertExists()
            assertFalse("AI 판에서 확인을 띄운다", scenario.screenOwnsBack())
        }
        // 끝난 판(결과) — 그냥 떠난다.
        val done = DestinationTestRig(me = DEST_ME)
        done.gomoku.applyState(destinationGomokuState(finished = true))
        launch(done, GomokuRoute.match(DEST_MATCH)).use { scenario ->
            compose.onNodeWithTag(GomokuScreenTags.result).assertExists()
            assertFalse("끝난 판에서 확인을 띄운다", scenario.screenOwnsBack())
        }
        assertEquals(0, leaves)
    }

    @Test
    fun sectionArgumentsLandInTheScreenAndBackPeelsThemFirst() {
        // AI 섹션 → 돌 색 시트가 선 채로 열린다. 뒤로가기는 시트부터 닫고, 그다음은 시스템 몫.
        val ai = DestinationTestRig(me = null)
        launch(ai, GomokuRoute.ai()).use { scenario ->
            compose.onNodeWithTag(GomokuScreenTags.aiSheet).assertExists()
            assertTrue(scenario.screenOwnsBack())
            scenario.back()
            compose.onNodeWithTag(GomokuScreenTags.aiSheet).assertDoesNotExist()
            compose.onNodeWithTag(GomokuScreenTags.lobby).assertExists()
            assertFalse(scenario.screenOwnsBack())
        }
        // 관전 섹션 → 화면이 나타난 뒤 관전에 들어간다. 뒤로가기 = 관전만 나간다(화면은 로비로 남는다).
        val watch = DestinationTestRig(me = DEST_ME)
        launch(watch, GomokuRoute.watch("CCCCCCCC-0000-4000-8000-000000000001")).use { scenario ->
            assertEquals("cccccccc-0000-4000-8000-000000000001", watch.gomoku.spectating?.id)
            assertTrue("관전 중인데 뒤로가기가 화면을 떠난다", scenario.screenOwnsBack())
            scenario.back()
            assertNull("뒤로가기가 관전을 안 걷었다", watch.gomoku.spectating)
            compose.onNodeWithTag(GomokuScreenTags.lobby).assertExists()
            assertFalse(scenario.screenOwnsBack())
        }
        // 판 초점 섹션 → 화면이 나타나기 전에 게임 탭 스토어에 심고, 나타나면서 꺼내 쓴다(남지 않는다).
        val focus = DestinationTestRig(me = DEST_ME)
        launch(focus, GomokuRoute.invite("11111111-0000-4000-8000-0000000000a1")).use {
            assertTrue(focus.games.isGomokuScreenVisible)
            assertNull("초점이 게임 탭 스토어에 남았다 — 화면이 꺼내 쓰지 않았다", focus.games.pendingGomokuFocusID)
        }
        assertEquals(0, leaves)
    }

    @Test
    fun leavingTheDestinationStopsTheScreenHooks() {
        val rig = DestinationTestRig(me = DEST_ME)
        rig.games.appDidBecomeActive() // 앱이 앞에 있다(조립의 프로세스 수명 훅이 부르는 문).
        val scenario = launch(rig, GomokuRoute.lobby())
        assertTrue(rig.games.isGomokuScreenVisible)
        assertTrue("화면이 나타났는데 창이 안 보인다고 한다", rig.gomoku.isWindowVisible)
        scenario.close()
        assertFalse("목적지가 내려갔는데 게임 탭 스토어가 화면이 보인다고 한다", rig.games.isGomokuScreenVisible)
        assertFalse("목적지가 내려갔는데 폴링 창이 열려 있다", rig.gomoku.isWindowVisible)
    }

    @Test
    fun entryActionsFoldUnknownSectionsIntoTheLobby() {
        assertEquals(GomokuEntry.Action.Focus("m1"), GomokuEntry.action("match", "m1"))
        assertEquals(GomokuEntry.Action.Focus("i1"), GomokuEntry.action("invite", "i1"))
        assertEquals(GomokuEntry.Action.Watch("w1"), GomokuEntry.action("watch", "w1"))
        assertEquals(GomokuEntry.Action.Ranking, GomokuEntry.action("ranking", null))
        assertEquals(GomokuEntry.Action.AIPicker, GomokuEntry.action("ai", null))
        assertEquals("id 없는 판 초점은 로비", GomokuEntry.Action.Lobby, GomokuEntry.action("match", null))
        assertEquals("id 없는 관전은 로비", GomokuEntry.Action.Lobby, GomokuEntry.action("watch", null))
        assertEquals("모르는 섹션은 로비(빈 화면 금지)", GomokuEntry.Action.Lobby, GomokuEntry.action("crossy", "x"))
        // 라우트 상수와 진입 동작이 같은 섹션 글자를 쓴다.
        assertEquals(GomokuEntry.Action.Watch("w2"), GomokuRoute.watch("w2").let { GomokuEntry.action(it.section, it.matchId) })
        assertEquals(GomokuEntry.Action.AIPicker, GomokuRoute.ai().let { GomokuEntry.action(it.section, it.matchId) })
    }
}
