// 원본: 없음 — W4-b 계측(에뮬레이터 ART · 진짜 Choreographer vsync). 완료 기준 ②(F§5.4 vsync 정수배 · 기억 game-frame-rate-judder)와 ③(keepScreenOn)의 기기 몫.
//
// 호스트 시험(MiniGameFramePacerTableTest)은 합성 vsync 표로 페이서를 잰다. 여기서는 **기기 프레임 시계**(Compose 의 AndroidUiFrameClock → Choreographer)
// 위에서 같은 루프(MiniGameFrameLoop)를 2초 돌려:
//  ① 디스플레이 주사율 → 목표 fps 가 core 표대로다(이 AVD 는 60Hz → 60, k = 1).
//  ② k = 1 이면 **모든** 프레임이 틱이다(흔들림이 있는 진짜 vsync 에서 (k − 0.01)/hz 여유가 장을 버리지 않는다 — 버리면 그 장이 늘어진 저더).
//  ③ 기준선(같은 프레임 쌍 · 다른 입력): 1 vsync 뒤에 온 프레임을 이 화면 페이서는 고르고, 30Hz 로 잘못 안 페이서는 거른다 — 판정이 프레임을 실제로 가른다는 증거
//     (장 수 비율이 아니라 쌍으로 재서 호스트 부하로 vsync 가 듬성할 때도 선다 — 실측 부하 중 2초 25장).
//  ④ 화면 켜짐: GamesKeepScreenOn.apply 가 **이 기기 창**의 FLAG_KEEP_SCREEN_ON 을 켜고 끈다.
// 증거 그림: 계측 인자 aingcheckEvidence=1 이면 테트리스 판 화면을 띄운 기기 화면을 앱 외부 파일 폴더에 PNG 로 남긴다(adb pull 로 가져간다).
package com.yehsung.aingcheck.android.screens.games.minigame

import android.graphics.Bitmap
import android.os.SystemClock
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.yehsung.aingcheck.android.screens.games.hub.GamesKeepScreenOn
import com.yehsung.aingcheck.core.rules.minigame.MiniGameFrameRate
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.ui.games.minigame.GamesTetrisCanvas
import com.yehsung.aingcheck.ui.games.minigame.MiniGameFrameLoop
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.isActive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import kotlin.math.roundToInt

@RunWith(AndroidJUnit4::class)
class MiniGameFrameDeviceTest {
    private val args get() = InstrumentationRegistry.getArguments()

    private class Record {
        val frames = mutableListOf<Long>()
        val ticks = mutableListOf<Long>()
        val baselineTicks = mutableListOf<Long>()
    }

    @Test
    fun theFrameLoopTicksEveryKthDeviceVsync() {
        val record = Record()
        var hz = 0
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                hz = DisplayRefreshRate.hz(activity.display?.refreshRate)
                activity.setContent {
                    // 모든 프레임(재료) · 이 화면 주사율로 고른 틱 · 30Hz 로 잘못 안 틱(기준선) — 같은 프레임 시계 위 세 루프.
                    LaunchedEffect(Unit) { while (isActive) withFrameNanos { record.frames += it } }
                    MiniGameFrameLoop(running = true, refreshHz = hz) { record.ticks += it }
                    MiniGameFrameLoop(running = true, refreshHz = 30) { record.baselineTicks += it }
                }
            }
            SystemClock.sleep(2_500)
            scenario.onActivity { activity -> activity.setContent { } } // 루프를 멈추고 읽는다(메인 스레드 값 — onActivity 안에서 복사)
            SystemClock.sleep(200)
        }
        val k = hz / MiniGameFrameRate.targetFPS(hz)
        // 첫 0.5초(창이 막 선 구간)는 뺀다. 프레임 시각은 서로 다른 값만 센다(같은 vsync 를 한 루프가 두 번 받는 일이 있다 — 실측 108 줄 · 107 시각).
        val start = record.frames.first() + 500_000_000L
        val frames = record.frames.filter { it >= start }.distinct()
        val ticks = record.ticks.filter { it >= start }
        val baseline = record.baselineTicks.filter { it >= start }
        val gaps = ticks.zipWithNext { a, b -> ((b - a) * hz / 1e9).roundToInt() }
        println("AINGCHECK-DEVICE-FRAMES hz=$hz target=${MiniGameFrameRate.targetFPS(hz)} k=$k frames=${frames.size} ticks=${ticks.size} baseline30=${baseline.size} gapHistogram=${gaps.groupingBy { it }.eachCount().toSortedMap()}")
        // 호스트가 바쁘면 에뮬레이터가 vsync 를 건너뛴다(실측: 부하 중 2초에 25장). 판정은 장 수가 아니라 **같은 프레임 쌍**에서 가른다 — 부하에도 선다.
        assertTrue("프레임이 너무 적다(${frames.size}) — 기기 프레임 시계가 돌지 않았다", frames.size >= 20)
        assertEquals("이 AVD 의 주사율 → 목표 fps(core 표)", MiniGameFrameRate.targetFPS(hz), hz / k)
        if (k == 1) {
            // ② 모든 프레임이 틱 — 버린 장 0.
            val ticked = ticks.toSet()
            val dropped = frames.count { it !in ticked }
            assertEquals("k=1 인데 페이서가 버린 프레임 ${dropped}장(저더)", 0, dropped)
        } else {
            assertTrue("틱 사이 vsync 수가 k=$k 의 배수가 아니다: $gaps", gaps.all { it % k == 0 })
        }
        // ③ 기준선(같은 프레임 쌍 · 다른 입력): 바로 다음 vsync(1 vsync 뒤)에 온 프레임은 — 이 화면 페이서는 고르고(위 ②),
        //    30Hz 로 잘못 안 페이서는 **앞 장을 골랐다면 반드시 거른다**(16.7ms < 33ms). 그런 쌍이 몇 개는 있어야 잰 것이다.
        val baselineSet = baseline.toSet()
        val oneVsyncPairs = frames.zipWithNext().filter { (a, b) -> ((b - a) * hz / 1e9).roundToInt() == 1 }
        val mustSkip = oneVsyncPairs.filter { (a, _) -> a in baselineSet }
        println("AINGCHECK-DEVICE-BASELINE oneVsyncPairs=${oneVsyncPairs.size} mustSkip=${mustSkip.size} baselinePicked=${mustSkip.count { (_, b) -> b in baselineSet }}")
        assertTrue("1 vsync 쌍이 ${mustSkip.size}개뿐 — 기준선을 잴 수 없다(기기가 vsync 를 못 따라온다)", mustSkip.size >= 3)
        assertTrue("기준선(30Hz 페이서)이 1 vsync 뒤 프레임을 골랐다 — 판정이 프레임을 거르지 않는다", mustSkip.none { (_, b) -> b in baselineSet })
    }

    @Test
    fun keepScreenOnReachesTheDeviceWindow() {
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            val seen = mutableListOf<Boolean>()
            scenario.onActivity { activity ->
                val window = activity.window
                fun on() = (window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0
                seen += on()
                GamesKeepScreenOn.apply(window, true)
                seen += on()
                GamesKeepScreenOn.apply(window, false)
                seen += on()
            }
            assertEquals(listOf(false, true, false), seen)
        }
    }

    @Test
    fun evidenceScreenshotOfTheTetrisCanvas() {
        val wanted = args.getString("aingcheckEvidence") == "1"
        val game = TetrisGame(seed = 20_260_919uL).also { g ->
            g.action()
            repeat(6) {
                g.step(0.05)
                g.action()
                repeat(12) { g.step(1.0 / 30) }
            }
            g.step(0.2)
        }
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent { AingTheme(dark = true) { GamesTetrisCanvas(game, 18_400L, reduceMotion = true, modifier = Modifier.fillMaxSize()) } }
            }
            SystemClock.sleep(1_500)
            val shot: Bitmap? = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
            assertTrue("기기 화면을 찍지 못했다", shot != null && shot.width > 0)
            if (wanted) {
                var dir: File? = null
                scenario.onActivity { dir = it.getExternalFilesDir(null) }
                val file = File(requireNotNull(dir), "w4b-tetris-solo-device.png")
                file.outputStream().use { requireNotNull(shot).compress(Bitmap.CompressFormat.PNG, 100, it) }
                println("AINGCHECK-DEVICE-EVIDENCE ${file.absolutePath} ${shot!!.width}x${shot.height}")
            }
        }
    }
}
