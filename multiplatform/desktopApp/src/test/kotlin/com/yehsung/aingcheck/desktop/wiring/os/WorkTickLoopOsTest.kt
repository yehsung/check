// 근무 틱 루프의 OS 몫(int-w2 os-work) — 맥 원본이 정답:
//  - 빠른 주기 = 근무 || 플라이아웃 열림 || 큐 대기(WorkTimerStore.swift:3319-3321)
//  - 깨움 게이트: 관측자가 있으면 틱 루프를 내렸다가 결합 뒤 본문부터(:4309-4370 · runBodyFirst :3363-3373), 소셜 깨움은 그 본문 뒤
//  - 로그아웃이면 팀 상태 즉시 비움 · 콘솔 세션 질의를 근무 판정에(CheckWorkNudge.swift:81-87 · WorkTimerStore.swift:1781)
// 픽스처는 합성뿐(MockEngine 녹음 — WiringTestRig).
@file:OptIn(ExperimentalTime::class, ExperimentalCoroutinesApi::class)

package com.yehsung.aingcheck.desktop.wiring.os

import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TeamMemberStatus
import com.yehsung.aingcheck.core.wire.models.WorkStatus
import com.yehsung.aingcheck.desktop.wiring.RecordingLifecycle
import com.yehsung.aingcheck.desktop.wiring.WiringTestRig
import com.yehsung.aingcheck.desktop.wiring.WorkDeps
import com.yehsung.aingcheck.desktop.wiring.WorkWiring
import com.yehsung.aingcheck.feature.desktop.socialapi.DesktopSocialLifecycle
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.minutes
import kotlin.time.ExperimentalTime

class WorkTickLoopOsTest {
    private companion object {
        val TICK_OK = """{"v":1,"server_now":"2026-09-16T00:00:00.000Z","team_id":"${WiringTestRig.TEAM}",""" +
            """"heartbeat":null,"statuses":[],"sessions_active":[],"sessions_weekly":[],"devices":[],"away":null}"""
    }

    private class Built(val rig: WiringTestRig, val work: WorkWiring, val social: RecordingLifecycle)

    private fun TestScope.build(
        onDidWake: (() -> Unit)? = null,
        menu: () -> Boolean = { false },
        console: () -> Boolean = { true },
        wakeReady: (suspend () -> Unit)? = null,
    ): Built {
        val rig = WiringTestRig(this)
        // work_tick 이 살아 있어야 본문마다 work_tick 1건으로 센다(404 면 이 실행 동안 꺼져 폴백으로 간다).
        rig.answer = { path ->
            when {
                path.endsWith("/rpc/work_tick") -> TICK_OK
                path.endsWith("/rpc/take_pokes") -> "[]"
                else -> null
            }
        }
        lateinit var work: WorkWiring
        val social = RecordingLifecycle { work.store.snapshot.value }
        val lifecycle = if (onDidWake == null) social else object : DesktopSocialLifecycle by social {
            override fun onDidWake(at: SwiftDate) {
                onDidWake()
                social.onDidWake(at)
            }
        }
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
                social = { lifecycle },
                wakeNetworkReady = wakeReady,
                consoleSessionUsable = console,
                menuPresented = menu,
            ),
        )
        return Built(rig, work, social)
    }

    /** 무한 박자는 단언이 빨개져도 반드시 내린다. */
    private inline fun Built.use(block: (Built) -> Unit) {
        try {
            block(this)
        } finally {
            work.stop()
            rig.close()
        }
    }

    private val Built.ticks: Int get() = rig.count("/rpc/work_tick")

    @Test
    fun 플라이아웃이_열려_있으면_비근무여도_30초_주기__닫혀_있으면_300초() = runTest(timeout = 1.minutes) {
        var open = true
        build(menu = { open }).use { b ->
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            assertTrue(b.work.refreshLoopIsFast, "열림 = 빠른 주기")
            advanceTimeBy(30_500); runCurrent()
            assertEquals(1, b.ticks, "열린 채 30초 → 틱 1 — ${b.rig.requests}")
            // 음성 대조: 닫으면 이미 고른 빠른 잠(60초 본문) 뒤로는 300초(슬라이스 10) — 맥도 고른 잠은 그대로 잔다.
            open = false
            assertFalse(b.work.refreshLoopIsFast)
            advanceTimeBy(30_000); runCurrent()
            val base = b.ticks
            assertEquals(2, base)
            advanceTimeBy(290_000); runCurrent()
            assertEquals(base, b.ticks, "닫힘·비근무·큐 빔이면 300초 전 틱 0 — ${b.rig.requests}")
            advanceTimeBy(15_000); runCurrent()
            assertEquals(base + 1, b.ticks, "300초에 한 번")
        }
    }

    @Test
    fun 비근무_닫힘이면_30초에_틱_0__음성_대조() = runTest(timeout = 1.minutes) {
        build(menu = { false }).use { b ->
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            advanceTimeBy(31_000); runCurrent()
            assertEquals(0, b.ticks)
            assertFalse(b.work.refreshLoopIsFast)
        }
    }

    @Test
    fun 깨움_게이트가_서_있는_동안_틱_0__열리면_본문부터_그_뒤에_소셜_깨움() = runTest(timeout = 1.minutes) {
        val ready = CompletableDeferred<Unit>()
        var ticksAtWake = -1
        lateinit var probe: Built
        build(onDidWake = { ticksAtWake = probe.ticks }, menu = { true }, wakeReady = { ready.await() }).also { probe = it }.use { b ->
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            advanceTimeBy(30_500); runCurrent()
            assertTrue(b.work.isTickLoopRunning)
            b.rig.power.emit(PowerEvent.SLEEP); runCurrent()
            b.rig.power.emit(PowerEvent.WAKE); runCurrent()
            assertFalse(b.work.isTickLoopRunning, "게이트가 루프를 내린다")
            val held = b.ticks
            advanceTimeBy(8_000); runCurrent() // 상한 10초 안
            assertEquals(held, b.ticks, "망 결합 전 work_tick 0 — ${b.rig.requests}")
            assertTrue(b.social.calls.none { it == "didWake" }, "소셜 깨움도 게이트 뒤 — ${b.social.calls}")
            ready.complete(Unit); runCurrent()
            assertEquals(held + 1, b.ticks, "열리면 잠 없이 본문 1회(runBodyFirst)")
            assertTrue(b.work.isTickLoopRunning)
            assertEquals(1, b.social.calls.count { it == "didWake" }, "깨움 재연결 1회 — ${b.social.calls}")
            assertEquals(held + 1, ticksAtWake, "소셜 깨움은 본문(work_tick) **뒤**(맥 flushWakeRejoinIfPending)")
        }
    }

    @Test
    fun 깨움_게이트_상한_10초면_망이_안_붙어도_연다() = runTest(timeout = 1.minutes) {
        build(menu = { true }, wakeReady = { CompletableDeferred<Unit>().await() }).use { b ->
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            b.rig.power.emit(PowerEvent.WAKE); runCurrent()
            assertFalse(b.work.isTickLoopRunning)
            val held = b.ticks
            advanceTimeBy(10_001); runCurrent()
            assertTrue(b.work.isTickLoopRunning, "상한 뒤 되살림(영구 대기 금지)")
            assertEquals(held + 1, b.ticks)
        }
    }

    @Test
    fun 관측자가_없으면_루프를_내리지_않고_깨움은_바로__음성_대조() = runTest(timeout = 1.minutes) {
        build(menu = { true }, wakeReady = null).use { b ->
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            b.rig.power.emit(PowerEvent.WAKE); runCurrent()
            assertTrue(b.work.isTickLoopRunning, "맥 networkPath nil — beginWakeGate 를 부르지 않는다")
            assertEquals(1, b.social.calls.count { it == "didWake" })
            assertEquals(0, b.ticks, "본문을 당겨 쏘지도 않는다(평소 30초)")
        }
    }

    @Test
    fun 로그아웃하면_팀_상태가_다음_틱을_기다리지_않고_비워진다() = runTest(timeout = 1.minutes) {
        build().use { b ->
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            val mate = TeamMemberStatus(id = "d0000000-0000-4000-8000-0000000000c3", name = "합성팀원", status = WorkStatus.working, updatedAt = null, currentSessionStartedAt = null)
            b.work.applyTeamStatus(listOf(mate), b.work.store.workStateWriteGeneration)
            assertEquals(1, b.work.teamStatuses.value.size)
            b.rig.scope.launch { b.rig.sessionStore.signOut() }
            runCurrent()
            assertTrue(b.work.teamStatuses.value.isEmpty(), "로그아웃 즉시 빈 목록")
        }
    }

    @Test
    fun 로그인_유지면_팀_상태가_남는다__음성_대조() = runTest(timeout = 1.minutes) {
        build().use { b ->
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            val mate = TeamMemberStatus(id = "d0000000-0000-4000-8000-0000000000c3", name = "합성팀원", status = WorkStatus.working, updatedAt = null, currentSessionStartedAt = null)
            b.work.applyTeamStatus(listOf(mate), b.work.store.workStateWriteGeneration)
            advanceTimeBy(5_000); runCurrent()
            assertEquals(1, b.work.teamStatuses.value.size)
        }
    }

    @Test
    fun 콘솔_세션_질의가_거짓이면_근무_판정이_쓸_수_없음() = runTest(timeout = 1.minutes) {
        var console = true
        build(console = { console }).use { b ->
            assertTrue(b.work.isSessionUsable())
            console = false
            assertFalse(b.work.isSessionUsable(), "WTS 질의 거짓(다른 사용자 세션·연결 끊김) = 적립 0")
            console = true
            b.work.start(b.rig.scope); runCurrent()
            b.rig.sessionEvents.listeners.toList().forEach { it(com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvent.LOCK) }
            assertFalse(b.work.isSessionUsable(), "사건 판정(잠금)과 AND")
        }
    }

    @Test
    fun 콘솔_세션_판독이_던지면_막지_않는다() = runTest(timeout = 1.minutes) {
        build(console = { error("WTS 판독 실패(합성)") }).use { b ->
            assertTrue(b.work.isSessionUsable(), "맥 fail-open")
        }
    }
}
