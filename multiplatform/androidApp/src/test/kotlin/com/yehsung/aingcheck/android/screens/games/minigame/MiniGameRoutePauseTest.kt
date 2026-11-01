// 원본: Sources/CheckMobileKit/App/MobileRootView.swift:71-75 @ de5c153b (.inactive → 미니게임 판을 얼린다) · Sources/CheckMobileKit/App/MobileAppModel.swift:239-253
//
// 폰 일시정지의 **부르는 자리**(androidApp 경로): Activity 수명(ON_PAUSE·ON_RESUME) → 라우트 → 스토어 → 허브. 합성을 기다리지 않고 관찰자에서 바로 언다 — 멈춘 Activity 에는 다음 프레임이 안 온다.
package com.yehsung.aingcheck.android.screens.games.minigame

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.platform.WindowInfo
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.yehsung.aingcheck.android.screens.games.hub.GamesAndroidRig
import com.yehsung.aingcheck.core.rules.minigame.FlappyGame
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.stores.minigame.GamesMiniGameHub
import com.yehsung.aingcheck.core.stores.minigame.MiniGamePauseState
import com.yehsung.aingcheck.ui.games.minigame.MiniGameScreenTags
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.awaitCancellation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
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
@Config(sdk = [36], qualifiers = "w360dp-h740dp-xhdpi")
class MiniGameRoutePauseTest {
    @get:Rule
    val compose = createComposeRule()

    private class Scene : LifecycleOwner {
        val registry: LifecycleRegistry = LifecycleRegistry.createUnsafe(this)
        override val lifecycle: Lifecycle get() = registry
        init {
            registry.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
            registry.handleLifecycleEvent(Lifecycle.Event.ON_START)
            registry.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)
        }
    }

    /** 창 초점만 시험이 쥔다. 나머지는 실제 값 그대로다. */
    private class TestWindow(private val real: WindowInfo) : WindowInfo by real {
        var focused: Boolean by mutableStateOf(true)
        override val isWindowFocused: Boolean get() = focused
    }

    private fun open(rig: GamesAndroidRig, scene: Scene, game: String, window: TestWindow? = null) {
        rig.signIn()
        rig.store.miniGames.pauseSleep = { awaitCancellation() }
        compose.setContent {
            val info = window ?: LocalWindowInfo.current
            CompositionLocalProvider(LocalLifecycleOwner provides scene, LocalWindowInfo provides info) {
                AingTheme(dark = false) { MiniGameRoute(rig.store, game, null, onBack = {}) }
            }
        }
        compose.mainClock.autoAdvance = false // 판이 돌면 프레임 루프가 안 멈춰 idle 이 오지 않는다
        compose.waitForIdle()
        assertTrue("선발급 토큰", rig.pumpUntil { rig.store.miniGames.roundToken != null })
    }

    /** 시험 스레드가 쓴 상태를 합성에 넘기고 한 장 민다(자동 진행을 껐다 — 멈춘 루퍼는 스냅숏 적용 알림을 저절로 안 돌린다). */
    private fun frame(rig: GamesAndroidRig) {
        rig.settle(20)
        compose.mainClock.advanceTimeByFrame()
    }

    /** ON_PAUSE 는 그 **호출 안에서** 언다(다음 합성을 기다리지 않는다) · 임시 항목을 적는다 · ON_RESUME 은 안 푼다 · 라우트의 [일시정지] · [그만두기] 가 켜져 있다. */
    @Test
    fun onPauseFreezesRightThereAndOnResumeDoesNotThaw() {
        GamesAndroidRig().use { rig ->
            val scene = Scene()
            open(rig, scene, "tetris")
            val hub = rig.store.miniGames
            val c = requireNotNull(hub.controller)
            c.tap()
            repeat(5) { c.softDropOneCell() }
            frame(rig)
            compose.onNodeWithTag(MiniGameScreenTags.PAUSE).assertExists()

            scene.registry.handleLifecycleEvent(Lifecycle.Event.ON_PAUSE)
            assertEquals("관찰자가 바로 얼려야 한다", MiniGamePauseState.Paused, c.pauseState)
            assertNotNull("앱을 쓸어 올려 죽여도 남게", rig.prefs.getString(GamesMiniGameHub.pauseDraftKey(GamesAndroidRig.USER)))

            scene.registry.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)
            assertEquals("복귀가 판을 저절로 풀었다", MiniGamePauseState.Paused, c.pauseState)
            assertTrue(c.isPlaying)
            frame(rig)
            compose.onNodeWithTag(MiniGameScreenTags.PAUSE).assertDoesNotExist()
            compose.onNodeWithTag(MiniGameScreenTags.RESUME).assertExists()

            compose.onNodeWithTag(MiniGameScreenTags.QUIT).performSemanticsAction(SemanticsActions.OnClick)
            assertEquals("[그만두기] 는 그 점수로 확정", TetrisGame.Phase.Result, c.tetris.phase)
            assertTrue("제출이 나간다", rig.pumpUntil { rig.bodies("minigame_submit_score").isNotEmpty() })
            assertNull("임시 항목이 남으면 다음 실행에 또 올라간다", rig.prefs.getString(GamesMiniGameHub.pauseDraftKey(GamesAndroidRig.USER)))
        }
    }

    /**
     * 알림 창 · 전원 메뉴 · 시스템 대화상자: Activity 는 RESUMED 로 남고 창 초점만 거둔다. 얼리지 않으면 판이 사람 없이 흘러 새가 떨어지고 길건너는 입력 공백으로 죽는다.
     * 초점이 돌아와도 저절로 안 풀린다 — [이어하기] 가 푼다(iOS .inactive · .active). 처음 값은 변화가 아니다.
     */
    @Test
    fun losingWindowFocusFreezesAndGettingItBackDoesNotThaw() {
        GamesAndroidRig().use { rig ->
            val scene = Scene()
            val window = TestWindow(object : WindowInfo { override val isWindowFocused: Boolean = true })
            window.focused = false
            open(rig, scene, "tetris", window)
            val hub = rig.store.miniGames
            val c = requireNotNull(hub.controller)
            focus(rig, window, true)
            c.tap()
            repeat(5) { c.softDropOneCell() }
            frame(rig)
            assertEquals("초점을 얻은 것은 얼릴 일이 아니다", MiniGamePauseState.None, c.pauseState)

            focus(rig, window, false)
            assertEquals("알림 창을 내렸는데 판이 그대로 돈다", MiniGamePauseState.Paused, c.pauseState)
            assertEquals("수명은 그대로다(전제)", Lifecycle.State.RESUMED, scene.registry.currentState)
            assertNotNull("앱을 쓸어 올려 죽여도 남게", rig.prefs.getString(GamesMiniGameHub.pauseDraftKey(GamesAndroidRig.USER)))

            focus(rig, window, true)
            assertEquals("복귀가 판을 저절로 풀었다", MiniGamePauseState.Paused, c.pauseState)
            assertTrue(c.isPlaying)
            compose.onNodeWithTag(MiniGameScreenTags.RESUME).assertExists()
        }
    }

    private fun focus(rig: GamesAndroidRig, window: TestWindow, focused: Boolean) {
        window.focused = focused
        Snapshot.sendApplyNotifications()
        frame(rig)
        frame(rig)
    }

    /** 라우트의 뒤로(화면이 사라짐) = [그만두기]: 플래피는 기록 없이 끝난다(사용자 답 "지금처럼 버림"). */
    @Test
    fun leavingAFrozenFlappyDiscardsIt() {
        GamesAndroidRig().use { rig ->
            val scene = Scene()
            open(rig, scene, "flappy")
            val hub = rig.store.miniGames
            val c = requireNotNull(hub.controller)
            c.tap()
            scene.registry.handleLifecycleEvent(Lifecycle.Event.ON_PAUSE)
            assertEquals(MiniGamePauseState.Paused, c.pauseState)
            assertNull("플래피는 임시 항목을 안 적는다", rig.prefs.getString(GamesMiniGameHub.pauseDraftKey(GamesAndroidRig.USER)))
            hub.closeScreen(MiniGameKind.flappy)
            assertEquals(FlappyGame.Phase.Ready, c.flappy.phase)
            assertFalse(c.isFrozen)
            rig.settle()
            assertEquals("플래피를 접었는데 기록했다", emptyList<String>(), rig.bodies("minigame_submit_score"))
        }
    }
}
