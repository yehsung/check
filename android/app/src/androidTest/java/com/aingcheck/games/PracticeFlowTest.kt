package com.aingcheck.games

import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File

/** Real frame clock and OS input: game loops do not become idle like static Compose screens. */
class PracticeFlowTest {
    private lateinit var scenario: ActivityScenario<MainActivity>
    private lateinit var device: UiDevice
    @Before fun launch() {
        device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        device.wakeUp()
        scenario = ActivityScenario.launch(MainActivity::class.java)
        requireNotNull(device.wait(Until.findObject(By.res("practice_timing_bar")), 5_000))
    }
    @After fun close() { scenario.close() }
    private fun visibleTag(tag: String): UiObject2 {
        repeat(6) {
            device.findObject(By.res(tag))?.takeIf {
                val bounds = it.visibleBounds
                bounds.height() > 80 && bounds.bottom < device.displayHeight - 80
            }?.let { return it }
            // Scroll in the outer gutter, avoiding gameplay taps inside the canvas.
            device.swipe(device.displayWidth - 12, device.displayHeight * 8 / 10,
                device.displayWidth - 12, device.displayHeight * 3 / 10, 20)
            // A tap during a fling only stops scrolling; wait before locating the clickable bounds.
            device.waitForIdle(2_000)
        }
        return requireNotNull(device.wait(Until.findObject(By.res(tag)), 3_000)) { "Missing $tag" }
    }
    @Test fun timingPracticeCompletesAndReplaysWithoutLogin() {
        visibleTag("practice_timing_bar").click()
        repeat(10) {
            requireNotNull(device.wait(Until.findObject(By.res("game_action").enabled(true)), 3_000)).click()
            if (it < 9) device.wait(Until.hasObject(By.res("game_action").enabled(false)), 1_000)
        }
        assertTrue(device.wait(Until.hasObject(By.res("game_finished")), 3_000))
        val replay = visibleTag("play_again")
        device.waitForIdle(2_000)
        replay.click()
        val replayed = device.wait(Until.hasObject(By.res("game_action")), 3_000)
        var replayState = ""
        if (!replayed) {
            scenario.onActivity { activity ->
                val state = androidx.lifecycle.ViewModelProvider(activity)[GamesViewModel::class.java].ui.value
                replayState = "selected=${state.selected}, preparing=${state.preparing}, submitting=${state.submitting}, finished=${state.game?.finished}, score=${state.game?.score}"
            }
            val files = InstrumentationRegistry.getInstrumentation().targetContext.filesDir
            device.takeScreenshot(File(files, "replay-failure.png"))
            device.dumpWindowHierarchy(File(files, "replay-failure.xml"))
        }
        assertTrue(replayState, replayed)
        device.pressBack()
        requireNotNull(device.wait(Until.findObject(By.text("그만하기")), 2_000)).click()
        assertTrue(device.wait(Until.hasObject(By.res("practice_timing_bar")), 3_000))
    }
    @Test fun flappyPracticeStartsAndReturnsToLobby() {
        visibleTag("practice_flappy").click()
        val canvas = requireNotNull(device.wait(Until.findObject(By.res("game_canvas")), 3_000))
        canvas.click()
        device.pressBack()
        device.wait(Until.findObject(By.text("그만하기")), 1_000)?.click()
        assertTrue(device.wait(Until.hasObject(By.res("practice_timing_bar")), 3_000))
    }
    @Test fun backgroundingDiscardsUnfinishedPractice() {
        visibleTag("practice_timing_bar").click()
        assertTrue(device.wait(Until.hasObject(By.res("game_canvas")), 3_000))
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.moveToState(Lifecycle.State.RESUMED)
        assertTrue(device.wait(Until.hasObject(By.res("practice_timing_bar")), 3_000))
        assertTrue(device.hasObject(By.text("앱을 벗어나 진행 중인 판을 종료했어요. 점수는 제출하지 않았어요.")))
    }
}
