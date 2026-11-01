// 원본: Sources/CheckMobileKit/App/MobileRootView.swift:66-78 @ de5c153b (scenePhase) — 폰 일시정지의 기기 몫.
//
// 호스트 시험(MiniGameRoutePauseTest · GamesLifecycleBridgeTest)은 수명 이벤트를 손으로 넣는다. 여기서는 **진짜 Activity** 를 STARTED·CREATED 로 내렸다 올린다:
//  ① 조립(PhoneAppModel)의 스토어 · 라우트 그대로 ② Activity 가 내려가면 판이 언다 ③ 돌아와도 안 풀린다 · 카드가 보인다 ④ [이어하기] → 3-2-1 → 풀린다(실제 1초씩).
package com.yehsung.aingcheck.android.screens.games.minigame

import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.yehsung.aingcheck.android.app.AssembledStubApp
import com.yehsung.aingcheck.core.stores.minigame.MiniGamePauseState
import com.yehsung.aingcheck.ui.games.minigame.MiniGameScreenTags
import com.yehsung.aingcheck.ui.theme.AingTheme
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MiniGamePauseDeviceTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private var app: AssembledStubApp? = null

    @After
    fun tearDown() {
        instrumentation.runOnMainSync { app?.close() }
    }

    @Test
    fun aRealActivityStopFreezesTheRoundAndComingBackDoesNotThawIt() {
        val a = AssembledStubApp(instrumentation.targetContext.filesDir, duelsEnabled = false)
        app = a
        val hub = a.phone.games.miniGames
        assertTrue("조립이 폰 규칙을 켠다", hub.phonePauseRules)
        compose.setContent { AingTheme(dark = false) { MiniGameRoute(a.phone.games, "flappy", null, onBack = {}) } }
        compose.waitForIdle()
        instrumentation.runOnMainSync { requireNotNull(hub.controller).tap() }
        compose.mainClock.autoAdvance = false // 판이 돌면 프레임 루프가 안 멈춰 idle 이 오지 않는다
        compose.mainClock.advanceTimeByFrame()

        compose.activityRule.scenario.moveToState(Lifecycle.State.CREATED)
        instrumentation.runOnMainSync {
            val c = requireNotNull(hub.controller)
            assertEquals("Activity 가 내려갔는데 안 얼었다", MiniGamePauseState.Paused, c.pauseState)
            assertTrue("앱을 내렸는데 판이 끝났다", c.isPlaying)
        }

        compose.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        compose.mainClock.autoAdvance = true // 언 판은 프레임 루프가 안 돈다
        compose.waitForIdle()
        instrumentation.runOnMainSync { assertEquals("복귀가 판을 저절로 풀었다", MiniGamePauseState.Paused, requireNotNull(hub.controller).pauseState) }
        compose.onNodeWithTag(MiniGameScreenTags.QUIT).assertExists()

        compose.onNodeWithTag(MiniGameScreenTags.RESUME).performClick()
        compose.mainClock.autoAdvance = false
        SystemClock.sleep(3_500) // 3-2-1 은 허브의 코루틴이 실제 1초씩 돈다
        compose.mainClock.advanceTimeByFrame()
        instrumentation.runOnMainSync { assertEquals("3-2-1 뒤에 안 풀렸다", MiniGamePauseState.None, requireNotNull(hub.controller).pauseState) }
        assertTrue("풀리면 카드가 사라진다", compose.onAllNodesWithTag(MiniGameScreenTags.RESUME).fetchSemanticsNodes().isEmpty())
    }
}
