// 원본: 없음 — 설계서 §10.1 '빠져나가는 길을 전부 잰다'의 기기 몫(iOS 는 데모 라우트 match/leave · match/signout 을 시뮬레이터로 봤다).
//
// 진짜 앱(MainActivity)에서 판 진입 → 가로 → 이탈 → 세로 복귀를 잰다. 시험 프로세스는 세션을 시작하지 않으니 망은 0 이다(AssemblyDeviceTest ①). 판 값은 앱 스토어에 직접 넣는다.
// 재는 것: ① 앱이 Activity 에 실제로 요청하고(requestedOrientation) 화면이 실제로 돈다(Configuration.orientation) ② 돌아도 Activity 가 다시 안 만들어진다(매니페스트 configChanges — 다시 만들어지면 화면 수명이 끊겨 답이 뒤집힌다)
// ③ 판 끝 · 화면 사라짐 · 세션 끝 어느 길로 나가도 세로로 돌아온다. 에뮬레이터: am instrument · connectedAndroidTest 어느 쪽이든 돈다.
package com.yehsung.aingcheck.android.screens.games.rummy

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.yehsung.aingcheck.android.app.AingApplication
import com.yehsung.aingcheck.android.shell.MainActivity
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.applyState
import com.yehsung.aingcheck.core.stores.rummy.dismissResult
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RummyOrientationDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private lateinit var games: GamesStore
    private lateinit var rummy: RummyStore

    private fun state(status: String, mine: String): RummyMatchState = SwiftJson.decode(
        RummyMatchState.serializer(),
        """{"id":"7e7e0000-0000-4000-8000-000000000068","status":"$status","host_id":"7e7e0000-0000-4000-8000-0000000000a1","seq":1,""" +
            """"seats":[{"seat_no":0,"user_id":"7e7e0000-0000-4000-8000-0000000000a1","display_name":"나","state":"$mine"},{"seat_no":1,"user_id":"7e7e0000-0000-4000-8000-0000000000b2","display_name":"비","state":"playing"}],""" +
            """"my_seat_no":0,"my_rack":${if (status == "active") "[\"A1\"]" else "null"},"table":[],"turn_seat_no":1}""",
    )

    @Before
    fun setUp() {
        val screens = requireNotNull(ApplicationProvider.getApplicationContext<AingApplication>().container.shellScreens) { "조립 셸이 없다" }
        games = screens.phone.games
        rummy = screens.phone.rummy
    }

    @After
    fun tearDown() {
        instrumentation.runOnMainSync {
            games.reset()
            rummy.reset()
        }
    }

    private fun ActivityScenario<MainActivity>.current(): MainActivity {
        var activity: MainActivity? = null
        onActivity { activity = it }
        return requireNotNull(activity)
    }

    /** 요청 값과 실제 화면 방향이 둘 다 그 쪽이 될 때까지 기다린다(회전은 비동기다). */
    private fun ActivityScenario<MainActivity>.awaitOrientation(requested: Int, configuration: Int, label: String) {
        repeat(ROTATION_WAIT_STEPS) {
            val activity = current()
            if (activity.requestedOrientation == requested && activity.resources.configuration.orientation == configuration) return
            Thread.sleep(ROTATION_WAIT_STEP_MS)
        }
        val activity = current()
        throw AssertionError("$label: 요청 ${activity.requestedOrientation}(기대 $requested) · 화면 ${activity.resources.configuration.orientation}(기대 $configuration)")
    }

    private fun ActivityScenario<MainActivity>.awaitPortrait(label: String) =
        awaitOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, Configuration.ORIENTATION_PORTRAIT, label)

    private fun ActivityScenario<MainActivity>.awaitLandscape(label: String) =
        awaitOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE, Configuration.ORIENTATION_LANDSCAPE, label)

    @Test
    fun enterRotatesAndLeavingComesBackWithoutRecreating() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.awaitPortrait("앱이 세로로 안 떴다")
            val first = scenario.current()

            // 판 진입 → 가로. 돌아도 같은 Activity 다.
            instrumentation.runOnMainSync {
                games.rummyScreenDidAppear()
                rummy.applyState(state("active", "playing"))
            }
            scenario.awaitLandscape("판 화면이 안 돌았다")
            assertSame("돌면서 Activity 가 다시 만들어졌다 — 화면 수명이 끊긴다", first, scenario.current())
            assertTrue(games.isRummyScreenVisible)

            // 화면이 사라졌다(뒤로 · 탭 전환 · 딥링크) → 세로.
            instrumentation.runOnMainSync { games.rummyScreenDidDisappear() }
            scenario.awaitPortrait("화면이 사라졌는데 가로에 남았다")

            // 돌아왔다 → 가로. 앱을 내렸다 올려도 판이면 가로다.
            instrumentation.runOnMainSync { games.rummyScreenDidAppear() }
            scenario.awaitLandscape("돌아왔는데 안 돌았다")
            scenario.moveToState(androidx.lifecycle.Lifecycle.State.CREATED)
            scenario.moveToState(androidx.lifecycle.Lifecycle.State.RESUMED)
            scenario.awaitLandscape("앱을 내렸다 올리니 세로가 됐다")
            assertSame(first, scenario.current())

            // 판이 끝나 결과로 → 세로 · [최종 판] → 가로 · 등수로 → 세로.
            instrumentation.runOnMainSync { rummy.applyState(state("finished", "done").copy(seq = 2)) }
            scenario.awaitPortrait("결과가 가로에 남았다")
            instrumentation.runOnMainSync { games.setRummyFinalBoardShown(true) }
            scenario.awaitLandscape("[최종 판]이 안 돌았다")
            assertEquals("결과가 돌면서 접혔다", true, games.isRummyFinalBoardShown)
            instrumentation.runOnMainSync { rummy.dismissResult() }
            scenario.awaitPortrait("결과를 닫았는데 가로에 남았다")

            // 세션 끝 → 세로(화면이 사라졌다는 소식 없이).
            instrumentation.runOnMainSync { rummy.applyState(state("active", "playing").copy(id = com.yehsung.aingcheck.core.wire.SwiftUUID.parse("7e7e0000-0000-4000-8000-0000000000f3")!!)) }
            scenario.awaitLandscape("다음 판이 안 돌았다")
            instrumentation.runOnMainSync { games.reset() }
            scenario.awaitPortrait("세션이 끝났는데 가로에 남았다")
            assertSame(first, scenario.current())
        }
    }

    private companion object {
        const val ROTATION_WAIT_STEP_MS: Long = 50
        const val ROTATION_WAIT_STEPS: Int = 200
    }
}
