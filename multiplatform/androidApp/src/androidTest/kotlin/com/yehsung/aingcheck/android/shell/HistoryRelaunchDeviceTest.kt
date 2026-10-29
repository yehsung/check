// G §8-13 기기 몫: 기록 표시(FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY)가 붙은 수락 Intent 가 ART 위에서도 화면만 열고 수락은 버린다.
// 시스템이 실제로 기록에서 다시 띄우는 순서(알림 [수락] 뿌리 → 뒤로 → 최근 앱)는 adb 시나리오(android-task-scenarios.sh — 조정자
// 패치 w1g-03)가 몬다. 여기서는 같은 플래그·같은 증표로 기준선(플래그 없음 → 수락)과 짝으로 잰다.
package com.yehsung.aingcheck.android.shell

import android.content.Intent
import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.yehsung.aingcheck.android.app.AingApplication
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.routing.RouteIntents
import com.yehsung.aingcheck.android.routing.RouteRequest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class HistoryRelaunchDeviceTest {
    private val app get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as AingApplication

    /**
     * 이 시험은 셸(수락 증표 · 기록 표시)만 잰다 — Robolectric 셸 시험(ShellNavigationTest)과 같이 자리표시 셸을 고른다.
     * 조립 셸은 시험 프로세스에서 세션을 시작하지 않아(AingApplication: runningTests 면 phone.start 안 함 — 망 0) 실행 중 단계에 머물고
     * 탭 · 화면을 열지 않는다. 같은 프로세스의 다음 시험(AppLaunchDeviceTest)이 조립 셸을 재므로 끝나면 되돌린다.
     */
    @Before
    fun placeholderShell() {
        app.container.usePlaceholderShell()
    }

    @After
    fun assembledShellAgain() {
        app.container.usePlaceholderShell(on = false)
    }

    private fun waitFor(timeoutMs: Long = 10_000, condition: () -> Boolean): Boolean {
        val end = SystemClock.uptimeMillis() + timeoutMs
        while (SystemClock.uptimeMillis() < end) {
            if (condition()) return true
            SystemClock.sleep(50)
        }
        return condition()
    }

    /** 수락 Intent 를 띄우고 셸이 그 화면을 연 뒤(= 수락 판정까지 끝난 뒤)의 pendingInviteAccept 를 돌려준다. */
    private fun launchAccept(fromHistory: Boolean): Pair<AingRoute, AingRoute?> {
        val c = app.container
        val route = AingRoute.GomokuInvite("dev-" + UUID.randomUUID().toString().take(8))
        val proof = c.routeProof.value()!!
        c.pendingInviteAccept.value = null
        val intent = RouteIntents.explicit(app, RouteRequest(route, accept = true), proof)
        if (fromHistory) intent.addFlags(Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY)
        ActivityScenario.launch<MainActivity>(intent).use {
            assertTrue("셸이 신청 화면을 열지 않았다", waitFor { c.visibleRoute.route.value == route })
            if (!fromHistory) waitFor { c.pendingInviteAccept.value == route }
            return route to c.pendingInviteAccept.value
        }
    }

    @Test
    fun acceptRedeliveredFromHistoryOpensTheInviteOnly() {
        val (_, accepted) = launchAccept(fromHistory = true)
        assertNull("기록에서 다시 온 수락이 통과했다", accepted)
    }

    @Test
    fun baselineSameProofWithoutHistoryAccepts() {
        val (route, accepted) = launchAccept(fromHistory = false)
        assertEquals(route, accepted)
    }
}
