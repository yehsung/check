// 근무 배선(WorkWiring) 시험 — 가짜 의존으로 만들고 start→stop 한 바퀴 + 갈래 보고가 '조립에서 확인'으로 남긴 이 배선 몫:
// W2-g5/W-6 #2 NudgeStarted 한 번 · W2-g2/g3 onWorkStarted 는 상태가 선 뒤 한 번 · W2-g5 ⑰ 종료 시퀀스 stop 은 억제를 심지 않음 ·
// W2-g3 onWillSleep 은 근무 가드보다 앞 · onDidWake 는 깨움 게이트가 열린 뒤.
@file:OptIn(ExperimentalTime::class, ExperimentalCoroutinesApi::class)

package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.feature.desktop.work.AutoCloseReason
import com.yehsung.aingcheck.feature.desktop.work.WorkEvent
import com.yehsung.aingcheck.feature.desktop.work.WorkEventSink
import com.yehsung.aingcheck.feature.desktop.work.WorkStartOrigin
import com.yehsung.aingcheck.feature.desktop.work.nudge.AutoStartSuppression
import com.yehsung.aingcheck.feature.desktop.work.nudge.NudgeAction
import com.yehsung.aingcheck.feature.desktop.work.policy.QuitOutcome
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.ExperimentalTime

class WorkWiringTest {
    private class Built(val rig: WiringTestRig, val work: WorkWiring, val social: RecordingLifecycle, val events: MutableList<WorkEvent>)

    private fun TestScope.build(autoStart: Boolean = false): Built {
        val rig = WiringTestRig(this)
        val events = mutableListOf<WorkEvent>()
        lateinit var work: WorkWiring
        val social = RecordingLifecycle { work.store.snapshot.value }
        work = WorkWiring(
            WorkDeps(
                sessionStore = rig.sessionStore,
                kv = rig.kv,
                clock = rig.clock,
                deviceId = WiringTestRig.DEVICE,
                idle = rig.idle,
                power = rig.power,
                session = rig.sessionEvents,
                teamId = { WiringTestRig.TEAM },
                events = WorkEventSink { events += it },
                social = { social },
                autoWorkStartEnabled = { autoStart },
            ),
        )
        return Built(rig, work, social, events)
    }

    @Test
    fun start_stop_한_바퀴__큐가_서비스에_닿고_OS_구독을_거둔다() = runTest {
        val b = build()
        try {
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            assertTrue(b.work.isStarted)
            assertEquals(1, b.rig.power.listeners.size, "전원 사건 구독 1")
            assertEquals(1, b.rig.sessionEvents.listeners.size, "세션 사건 구독 1")
            val before = b.rig.requests.size
            b.work.commands.start()
            runCurrent()
            assertTrue(b.work.store.snapshot.value.isWorking)
            assertTrue(b.rig.requests.size > before, "근무 시작 항목이 큐→서비스로 나가야 한다: ${b.rig.requests}")
            b.work.commands.stop()
            runCurrent()
            assertFalse(b.work.store.snapshot.value.isWorking)
            b.work.stop()
            assertFalse(b.work.isStarted)
            assertEquals(0, b.work.openRegistrations)
            assertTrue(b.rig.power.listeners.isEmpty() && b.rig.sessionEvents.listeners.isEmpty(), "stop 뒤 OS 구독 0")
            assertTrue(b.rig.uncaught.isEmpty(), "잡히지 않은 예외: ${b.rig.uncaught}")
        } finally {
            b.rig.close()
        }
    }

    @Test
    fun onWorkStarted_는_근무_상태가_선_뒤_한_번() = runTest {
        val b = build()
        try {
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            b.work.commands.start()
            b.work.commands.start() // 근무 중 두 번째 시작은 no-op — 소셜도 다시 부르지 않는다.
            runCurrent()
            assertEquals(listOf("workStarted(working=true)"), b.social.calls.filter { it.startsWith("workStarted") })
            b.work.commands.stop()
            assertEquals("userStopped(terminating=false)", b.social.calls.last())
        } finally {
            b.work.stop()
            b.rig.close()
        }
    }

    @Test
    fun 넛지_시작은_NudgeStarted_를_한_번만_낸다() = runTest {
        val b = build(autoStart = true)
        try {
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            assertEquals(NudgeAction.STARTED, b.work.nudge.fire())
            runCurrent()
            assertEquals(1, b.events.count { it == WorkEvent.NudgeStarted }, "W-6 #2: ws 만 낸다 — ${b.events}")
            assertEquals(WorkStartOrigin.NUDGE, b.work.store.snapshot.value.startOrigin)
            assertEquals(1, b.social.calls.count { it.startsWith("workStarted") }, "넛지 시작도 명령 문을 지나 소셜에 한 번")
        } finally {
            b.work.stop()
            b.rig.close()
        }
    }

    @Test
    fun 넛지_설정_끔이면_시작_0__음성_대조() = runTest {
        val b = build(autoStart = false)
        try {
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            assertEquals(NudgeAction.NONE, b.work.nudge.fire())
            assertTrue(b.events.none { it == WorkEvent.NudgeStarted })
            assertFalse(b.work.store.snapshot.value.isWorking)
        } finally {
            b.work.stop()
            b.rig.close()
        }
    }

    @Test
    fun 종료_훅은_beginTermination_뒤_3초_마무리__억제를_심지_않고_꼬리_회수도_없다() = runTest {
        val b = build()
        try {
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            b.work.commands.start()
            runCurrent()
            val outcome = b.work.finishForQuit()
            assertNotEquals(QuitOutcome.SKIPPED, outcome)
            assertFalse(b.work.store.snapshot.value.isWorking)
            assertEquals("userStopped(terminating=true)", b.social.calls.last())
            assertNull(b.rig.kv.getBoolean(AutoStartSuppression.SUPPRESSED_KEY), "⑰ 종료 시퀀스 stop 은 자동 시작 억제를 심지 않는다")
        } finally {
            b.work.stop()
            b.rig.close()
        }
    }

    @Test
    fun 수동_종료는_억제를_심는다__종료_시험의_음성_대조() = runTest {
        val b = build()
        try {
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            b.work.commands.start()
            b.work.commands.stop()
            assertEquals(true, b.rig.kv.getBoolean(AutoStartSuppression.SUPPRESSED_KEY))
            assertEquals("userStopped(terminating=false)", b.social.calls.last())
        } finally {
            b.work.stop()
            b.rig.close()
        }
    }

    @Test
    fun 잠자기_링은_근무_가드보다_앞__깨움은_게이트_뒤_자동_마감() = runTest {
        val b = build()
        try {
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            b.work.commands.start()
            runCurrent()
            val lifecycle = b.social
            lifecycle.willSleepProbe = { b.work.sleepMarkers.load() }
            b.rig.power.emit(PowerEvent.SLEEP)
            runCurrent()
            // 링 내림(onWillSleep)은 근무 가드(마커 기록)보다 앞 — 부르는 순간엔 마커가 아직 없다.
            assertEquals("willSleep(marker=null)", lifecycle.calls.last())
            assertTrue(b.work.sleepMarkers.load() != null, "근무 중 잠자기는 정정 마커를 남긴다")
            advanceTimeBy(10 * 60 * 1000L)
            b.rig.power.emit(PowerEvent.WAKE)
            runCurrent()
            assertTrue("didWake" in lifecycle.calls, "게이트(관측자 없음 → 즉시)가 열린 뒤 onDidWake")
            assertFalse(b.work.store.snapshot.value.isWorking, "5분 넘는 잠자기는 자동 마감")
            assertEquals(1, b.events.count { it is WorkEvent.AutoClosed && it.reason == AutoCloseReason.SLEEP })
        } finally {
            b.work.stop()
            b.rig.close()
        }
    }
}
