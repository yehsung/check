// 원본: Tests/CheckMobileKitTests/V1017RummyLandscapeTests.swift:159-180 (systemWiring — 시스템 쪽 배선) @ ios-1017-cube 61d75d8c
//
// 방향 값 → Activity 값 표와 알리는 자리. 값의 판단은 core stores GamesRummyOrientationTest, 실제로 도는지는 기기 시험 RummyOrientationDeviceTest 가 잰다.
package com.yehsung.aingcheck.android.screens.games.rummy

import android.content.pm.ActivityInfo
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.Snapshot
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyInterfaceOrientation.landscape
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyInterfaceOrientation.portrait
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class RummyOrientationDriverTest {
    /** 폰: 세로는 잠금이다(옆으로 든 폰에서 판을 나간 뒤 결과 · 로비가 가로로 남지 않게). 가로는 '화면 방향 고정'과 무관하게 양쪽 가로. 큰 화면은 세로로 묶지 않는다. */
    @Test
    fun orientationTable() {
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, RummyOrientationDriver.activityOrientation(portrait, 360))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, RummyOrientationDriver.activityOrientation(portrait, 599))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, RummyOrientationDriver.activityOrientation(portrait, 600))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE, RummyOrientationDriver.activityOrientation(landscape, 360))
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE, RummyOrientationDriver.activityOrientation(landscape, 800))
    }

    /** 지금 값을 곧바로 한 번 · 바뀔 때마다 옮긴다 · 같은 값은 안 옮긴다. 값을 쥐지 않는다 — 값이 세로면 잠금도 세로다. */
    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun installAppliesNowAndOnEveryChange() {
        var value by mutableStateOf(portrait)
        val applied = ArrayList<Any>()
        val scheduler = TestCoroutineScheduler()
        val scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(scheduler))
        RummyOrientationDriver.install({ value }, scope) { applied.add(it) }
        assertEquals(listOf<Any>(portrait), applied)
        scheduler.advanceUntilIdle()
        value = landscape
        Snapshot.sendApplyNotifications()
        scheduler.advanceUntilIdle()
        assertEquals(landscape, applied.last())
        val count = applied.size
        value = landscape
        Snapshot.sendApplyNotifications()
        scheduler.advanceUntilIdle()
        assertEquals("같은 값을 또 옮겼다", count, applied.size)
        value = portrait
        Snapshot.sendApplyNotifications()
        scheduler.advanceUntilIdle()
        assertEquals("화면이 사라졌는데 가로에 남았다", portrait, applied.last())
        scope.cancel()
    }

    private fun source(path: String): String {
        val file = File("src/main/$path")
        assertTrue("없다: ${file.absolutePath}", file.isFile)
        return file.readText().lineSequence().map { it.substringBefore("//") }.joinToString("\n")
    }

    /** 소스 계약 — Activity 를 띄우지 않는 자리만: 알리는 자리가 앱 Activity 에 있고 · 값을 쥐지 않고 · 가장자리 뒤로 쓸기를 판 동안 뺀다. */
    @Test
    fun systemWiring() {
        val activity = source("kotlin/com/yehsung/aingcheck/android/shell/MainActivity.kt")
        assertTrue("알리는 자리가 없으면 돌지 않는다", "RummyOrientationDriver.install(screens.phone.games, lifecycleScope, ::applyRummyOrientation)" in activity)
        assertTrue("requestedOrientation = RummyOrientationDriver.activityOrientation(orientation," in activity)
        val driver = source("kotlin/com/yehsung/aingcheck/android/screens/games/rummy/RummyOrientationDriver.kt")
        assertFalse("잠금이 값을 쥐면 푸는 길을 잊을 수 있다", Regex("\\bvar\\b").containsMatchIn(driver))
        val route = source("kotlin/com/yehsung/aingcheck/android/screens/games/rummy/RummyRoute.kt")
        assertTrue("systemGestureExclusion()" in route)
        assertTrue("isRummyFinalBoardShown" in route)
        assertFalse("방향의 주인은 드라이버 하나다", "requestedOrientation" in route)
    }
}
