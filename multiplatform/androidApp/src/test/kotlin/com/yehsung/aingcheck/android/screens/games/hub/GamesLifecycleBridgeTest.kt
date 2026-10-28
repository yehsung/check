// 원본: 없음 — W4-b 완료 기준 ③(G §2-3) "ON_STOP 점수 확정, keepScreenOn" 의 Android 배선 시험(E§4.4 · E§5.1).
//
// 진짜 경로 그대로: 프로세스 수명(LifecycleRegistry — ProcessLifecycleOwner 자리) → AppLifecycle.attach → GamesLifecycleBridge → GamesStore,
// 그리고 GamesStore.installIdleTimerSink → GamesKeepScreenOn → **Activity 창의 FLAG_KEEP_SCREEN_ON**. 망은 앱 단일 팩토리(OkHttp) → 로컬 MockWebServer.
//  ① 테트리스: 판이 돌면 화면 켜짐 → ON_STOP 에 **여기까지의 점수로 제출**(본문 p_score = 나가는 순간 점수 · 토큰 t1) · 결과 화면 · 화면 켜짐 풀림.
//  ② 플래피: ON_PAUSE(알림창 내리기 — iOS .inactive)는 판을 끝내지 않는다(기준선) → ON_STOP 에 **기록 없이** 끝 · 화면 켜짐 풀림.
//  ③ 타이밍 바: 판이 돌아도 화면 켜짐을 **켜지 않는다**(INV-GamesStore-78b92b69 — 스스로 끝나지 않는 판이라 화면이 영원히 켜진다).
//  ④ 처음 붙을 때 받는 '뒤'(AppLifecycle 의 첫 값 false)는 아무것도 끝내지 않는다 · 같은 값 두 번은 한 번.
package com.yehsung.aingcheck.android.screens.games.hub

import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.yehsung.aingcheck.android.lifecycle.AppLifecycle
import com.yehsung.aingcheck.core.rules.minigame.FlappyGame
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class GamesLifecycleBridgeTest {
    private class Process : LifecycleOwner {
        val registry: LifecycleRegistry = LifecycleRegistry.createUnsafe(this)
        override val lifecycle: Lifecycle get() = registry
    }

    private class Wired(val rig: GamesAndroidRig, val process: Process, val activity: ComponentActivity) {
        val keepScreenOn: Boolean
            get() = (activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0

        fun start() {
            process.registry.handleLifecycleEvent(Lifecycle.Event.ON_START)
            process.registry.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)
            rig.settle()
        }

        fun pause() {
            process.registry.handleLifecycleEvent(Lifecycle.Event.ON_PAUSE)
            rig.settle()
        }

        fun stop() {
            process.registry.handleLifecycleEvent(Lifecycle.Event.ON_STOP)
        }
    }

    /** 조립(K11)이 하는 두 줄 그대로 — assembly.md. */
    private fun wired(): Wired {
        val rig = GamesAndroidRig()
        rig.signIn()
        val activity = Robolectric.buildActivity(ComponentActivity::class.java).setup().get()
        val process = Process()
        val lifecycle = AppLifecycle().also { it.attach(process.registry) }
        GamesKeepScreenOn.install(rig.store, activity.window)
        GamesLifecycleBridge(rig.store).attach(lifecycle)
        process.registry.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
        rig.settle()
        return Wired(rig, process, activity)
    }

    @Test
    fun onStopConfirmsTetrisAtItsScoreAndReleasesTheScreen() {
        val w = wired()
        w.rig.use { rig ->
            w.start()
            rig.store.miniGames.openScreen(MiniGameKind.tetris)
            rig.settle()
            assertFalse("판이 없으면 화면 켜짐 없음", w.keepScreenOn)
            val controller = requireNotNull(rig.store.miniGames.controller)
            controller.tap()
            assertTrue(controller.isPlaying)
            assertTrue("테트리스 판이 돌면 화면 켜짐", rig.pumpUntil { w.keepScreenOn })
            assertTrue("판 시작이 토큰을 받는다", rig.pumpUntil { rig.bodies("minigame_start_round").isNotEmpty() })
            controller.hardDrop()
            controller.hardDrop()
            val reached = controller.tetris.score
            assertTrue("하드드롭 두 번이면 점수", reached > 0)
            assertEquals(emptyList<String>(), rig.bodies("minigame_submit_score"))

            w.stop()
            assertEquals("확정 = 결과 화면", TetrisGame.Phase.Result, controller.tetris.phase)
            assertTrue("확정 제출이 나간다", rig.pumpUntil { rig.bodies("minigame_submit_score").isNotEmpty() })
            rig.settle()
            val bodies = rig.bodies("minigame_submit_score")
            assertEquals("제출 한 번 — $bodies", 1, bodies.size)
            val body = Json.parseToJsonElement(bodies.single()).jsonObject
            assertEquals("tetris", body.getValue("p_game").jsonPrimitive.content)
            assertEquals("나가는 순간까지의 점수", reached.toLong(), body.getValue("p_score").jsonPrimitive.long)
            assertEquals("t1", body.getValue("p_token").jsonPrimitive.content)
            assertTrue("뒤로 가면 화면 켜짐 풀림", rig.pumpUntil { !w.keepScreenOn })
            assertEquals(GamesMiniGameText.endedInBackground(MiniGameKind.tetris), rig.store.miniGames.submitNotice)
        }
    }

    @Test
    fun onPauseKeepsTheFlappyRunAndOnStopEndsItWithoutARecord() {
        val w = wired()
        w.rig.use { rig ->
            w.start()
            rig.store.miniGames.openScreen(MiniGameKind.flappy)
            rig.settle()
            val controller = requireNotNull(rig.store.miniGames.controller)
            controller.tap()
            assertTrue(rig.pumpUntil { w.keepScreenOn })
            // 기준선: ON_PAUSE 만으로는 아무것도 끝나지 않는다(앱은 여전히 started).
            w.pause()
            assertTrue("ON_PAUSE 는 판을 끝내지 않는다", controller.isPlaying)
            assertTrue("ON_PAUSE 는 화면 켜짐을 풀지 않는다", w.keepScreenOn)
            w.stop()
            assertFalse("ON_STOP 은 판을 끝낸다", controller.isPlaying)
            assertEquals("새 판(시작 전)으로", FlappyGame.Phase.Ready, controller.flappy.phase)
            assertTrue(rig.pumpUntil { !w.keepScreenOn })
            rig.settle()
            assertEquals("플래피는 기록하지 않는다", emptyList<String>(), rig.bodies("minigame_submit_score"))
            assertEquals(GamesMiniGameText.endedInBackground(MiniGameKind.flappy), rig.store.miniGames.submitNotice)
        }
    }

    @Test
    fun timingBarNeverHoldsTheScreenOnAndTheFirstBackgroundIsIgnored() {
        val w = wired()
        w.rig.use { rig ->
            // 처음 붙을 때 AppLifecycle 이 넘기는 false — 판이 있었어도 끝내지 않는다(이 시점의 '뒤'는 바뀐 것이 아니다).
            rig.store.miniGames.openScreen(MiniGameKind.flappy)
            val flappy = requireNotNull(rig.store.miniGames.controller)
            flappy.tap()
            val bridge = GamesLifecycleBridge(rig.store)
            bridge.onForegroundChanged(false)
            assertTrue("첫 '뒤'는 무시", flappy.isPlaying)
            bridge.onForegroundChanged(true)
            bridge.onForegroundChanged(false)
            assertFalse("앞 → 뒤 는 끝낸다", flappy.isPlaying)
            bridge.onForegroundChanged(false)
            rig.settle()

            w.start()
            rig.store.miniGames.openScreen(MiniGameKind.timingBar)
            rig.settle()
            val timing = requireNotNull(rig.store.miniGames.controller)
            timing.tap()
            assertTrue(timing.isPlaying)
            rig.settle()
            assertFalse("타이밍 바 판은 화면 켜짐을 켜지 않는다", w.keepScreenOn)
        }
    }

    @Test
    fun applyTogglesOnlyTheKeepScreenOnFlag() {
        val window = Robolectric.buildActivity(ComponentActivity::class.java).setup().get().window
        val others = window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON.inv()
        GamesKeepScreenOn.apply(window, true)
        assertTrue((window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0)
        GamesKeepScreenOn.apply(window, true)
        assertTrue((window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0)
        GamesKeepScreenOn.apply(window, false)
        assertEquals(0, window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        assertEquals("다른 창 플래그는 그대로", others, window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON.inv())
    }
}
