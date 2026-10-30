// W-14 #7 · int-w2 nice(주간 owed) — 근무 배선의 두 몫. 맥 원본이 정답:
//  - 근무 종료(수동·자동 마감) → 종료 기록이 큐에서 나간 뒤 주간 조회 한 번(WorkTimerStore.swift:2217-2221·2611-2615 →
//    WorkTimerStoreWeeklyWork.swift:80-86). 종료 시퀀스 중이면 0(`if !isTerminating`). 1분 창에 막히면 빚 → 박자가 갚는다(:39-71).
//  - 기기 id 공급자는 조립 때 몇 번까지 묻는다(설치 id 읽기는 실패를 캐시하지 않는다 — WindowsInstallationIdentity.resolve).
// 픽스처는 합성뿐(MockEngine 녹음 — WiringTestRig).
@file:OptIn(ExperimentalTime::class, ExperimentalCoroutinesApi::class)

package com.yehsung.aingcheck.desktop.wiring.os

import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.wiring.WeeklyWorkEndRefresh
import com.yehsung.aingcheck.desktop.wiring.WiringTestRig
import com.yehsung.aingcheck.desktop.wiring.WorkDeps
import com.yehsung.aingcheck.desktop.wiring.WorkWiring
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.ExperimentalTime

class WorkWeeklyAndDeviceIdTest {
    private class Built(val rig: WiringTestRig, val work: WorkWiring, val weekly: MutableList<Long>)

    private fun TestScope.build(
        hook: Boolean = true,
        deviceId: String? = WiringTestRig.DEVICE,
        deviceIdSource: (() -> String?)? = null,
        wakeReady: (suspend () -> Unit)? = null,
    ): Built {
        val rig = WiringTestRig(this)
        val weekly = mutableListOf<Long>()
        val work = WorkWiring(
            WorkDeps(
                sessionStore = rig.sessionStore,
                kv = rig.kv,
                clock = rig.clock,
                deviceId = deviceId,
                idle = rig.idle,
                power = rig.power,
                session = rig.sessionEvents,
                teamId = { WiringTestRig.TEAM },
                deviceIdSource = deviceIdSource,
                wakeNetworkReady = wakeReady,
                // 발사 순간의 녹음 길이 — 종료 기록이 큐에서 먼저 나갔는지 잰다.
                onWorkEndedWeekly = if (hook) ({ weekly += rig.requests.size.toLong() }) else ({}),
            ),
        )
        return Built(rig, work, weekly)
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

    @Test
    fun 수동_종료_뒤_주간_조회_한_번__종료_기록이_큐에서_나간_뒤() = runTest {
        build().use { b ->
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            b.work.commands.start()
            runCurrent()
            assertEquals(emptyList(), b.weekly, "근무 시작은 주간 조회가 아니다")
            val beforeStop = b.rig.requests.size
            b.work.commands.stop()
            runCurrent()
            assertEquals(1, b.weekly.size, "종료 뒤 한 번: ${b.rig.requests}")
            // 순서(맥 `await queue?.value` 뒤): 발사 순간에 종료 기록이 이미 서비스로 나갔다.
            assertTrue(b.weekly[0] > beforeStop, "종료 기록보다 먼저 쐈다: 발사 때 ${b.weekly[0]} · 멈춤 전 $beforeStop · ${b.rig.requests}")
            assertFalse(b.work.weeklyAfterWork.owed)
        }
    }

    @Test
    fun 큐가_종료_기록을_붙든_동안은_쏘지_않는다__깨움_게이트로_큐를_붙잡음() = runTest {
        val net = CompletableDeferred<Unit>()
        build(wakeReady = { net.await() }).use { b ->
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            b.work.commands.start()
            runCurrent()
            // 짧은 잠 → 깨움: 게이트가 망 결합을 기다린다(맥 beginWakeGate). 그동안 큐 드레인은 게이트 뒤에 선다.
            b.rig.power.emit(PowerEvent.SLEEP)
            runCurrent()
            b.rig.power.emit(PowerEvent.WAKE)
            runCurrent()
            assertTrue(b.work.store.snapshot.value.isWorking, "짧은 잠은 마감이 아니다")
            val beforeStop = b.rig.requests.size
            b.work.commands.stop()
            runCurrent()
            assertFalse(b.work.store.snapshot.value.isWorking)
            assertEquals(emptyList(), b.weekly, "종료 기록이 큐에 붙들려 있는데 쐈다(맥은 syncTask 를 기다린다)")
            net.complete(Unit)
            runCurrent()
            assertEquals(1, b.weekly.size, "게이트가 열려 큐가 나간 뒤 한 번")
            assertTrue(b.weekly[0] > beforeStop, "발사 때 종료 기록이 아직 안 나갔다: ${b.rig.requests}")
        }
    }

    @Test
    fun 종료_시퀀스의_멈춤은_주간_조회_0__음성_대조() = runTest {
        build().use { b ->
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            b.work.commands.start()
            runCurrent()
            b.work.finishForQuit()
            runCurrent()
            assertFalse(b.work.store.snapshot.value.isWorking, "종료 훅이 근무를 닫았다")
            assertEquals(emptyList(), b.weekly, "맥 `if !isTerminating` — 볼 사람이 없다")
        }
    }

    @Test
    fun 자동_마감도_근무_종료다__잠자기_5분_넘김() = runTest {
        build().use { b ->
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            b.work.commands.start()
            runCurrent()
            b.rig.power.emit(PowerEvent.SLEEP)
            runCurrent()
            advanceTimeBy(10 * 60 * 1000L)
            b.rig.power.emit(PowerEvent.WAKE)
            runCurrent()
            assertFalse(b.work.store.snapshot.value.isWorking)
            assertEquals(1, b.weekly.size, "자동 마감(맥 :2611-2615)도 한 번")
        }
    }

    @Test
    fun 일분_창에_막히면_빚__박자가_일분_뒤에_갚는다() = runTest {
        build().use { b ->
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            b.work.commands.start()
            runCurrent()
            b.work.commands.stop()
            runCurrent()
            assertEquals(1, b.weekly.size)
            advanceTimeBy(5_000)
            b.work.commands.start()
            runCurrent()
            b.work.commands.stop()
            runCurrent()
            assertEquals(1, b.weekly.size, "1분 안의 두 번째 종료는 쏘지 않는다")
            assertTrue(b.work.weeklyAfterWork.owed, "빚으로 남긴다")
            // 다음 정책 박자(30초)는 아직 창 안 — 0건.
            advanceTimeBy(30_000)
            runCurrent()
            assertEquals(1, b.weekly.size, "창 안의 박자는 갚지 않는다")
            advanceTimeBy(30_000)
            runCurrent()
            assertEquals(2, b.weekly.size, "1분이 지난 박자가 한 번 갚는다")
            assertFalse(b.work.weeklyAfterWork.owed)
            advanceTimeBy(5 * 60_000)
            runCurrent()
            assertEquals(2, b.weekly.size, "빚이 없으면 박자는 0건")
        }
    }

    @Test
    fun 훅이_없으면_주간_서버_경로_요청_0__MockEngine_녹음() = runTest {
        build(hook = false).use { b ->
            b.rig.signIn()
            b.work.start(b.rig.scope)
            runCurrent()
            b.work.commands.start()
            runCurrent()
            b.work.commands.stop()
            runCurrent()
            advanceTimeBy(2 * 60_000)
            runCurrent()
            assertEquals(0, b.rig.countContaining("weekly_work"), "${b.rig.requests}")
            assertEquals(emptyList(), b.weekly)
        }
    }

    @Test
    fun 순수_규칙__로그아웃이면_도장도_빚도_안_바뀐다() {
        var signedIn = false
        var fired = 0
        val r = WeeklyWorkEndRefresh(isSignedIn = { signedIn }, fire = { fired += 1 })
        assertFalse(r.onWorkEnded(SwiftDate(1000.0)))
        assertFalse(r.owed)
        signedIn = true
        assertTrue(r.onWorkEnded(SwiftDate(1001.0)), "로그아웃 때의 시도가 창을 열지 않았다")
        assertFalse(r.onWorkEnded(SwiftDate(1060.0)))
        assertTrue(r.owed)
        assertFalse(r.payIfOwed(SwiftDate(1060.5)), "59.5초 — 아직 창 안")
        assertTrue(r.payIfOwed(SwiftDate(1061.0)), "60초 — 창 밖")
        assertEquals(2, fired)
        // 시계가 뒤로 가면(dt<0) 창으로 막지 않는다(맥 `now >= last` 조건).
        assertTrue(r.onWorkEnded(SwiftDate(900.0)))
        assertEquals(3, fired)
    }

    @Test
    fun 기기_id_공급자__한_번_실패해도_다시_묻는다() = runTest {
        var calls = 0
        val source = {
            calls += 1
            if (calls == 1) error("레지스트리 잠깐 막힘") else WiringTestRig.DEVICE
        }
        build(deviceId = null, deviceIdSource = source).use { b ->
            assertEquals(WiringTestRig.DEVICE, b.work.resolvedDeviceId)
            assertEquals(WiringTestRig.DEVICE, b.work.store.deviceId, "근무 상태가 공급자 값을 쓴다")
            assertEquals(2, calls)
        }
    }

    @Test
    fun 기기_id_공급자__끝내_없으면_상한까지만_묻고_기기_없음__음성_대조() = runTest {
        var calls = 0
        build(deviceId = "win:legacy-ignored", deviceIdSource = { calls += 1; null }).use { b ->
            assertNull(b.work.resolvedDeviceId, "공급자가 있으면 옛 값으로 메우지 않는다(지어내지 않는다)")
            assertFalse(b.work.store.hasDeviceIdentity)
            assertEquals(WorkWiring.DEVICE_ID_ATTEMPTS, calls)
        }
    }

    @Test
    fun 공급자가_없으면_옛_값_그대로__음성_대조() = runTest {
        build(deviceId = WiringTestRig.DEVICE, deviceIdSource = null).use { b ->
            assertEquals(WiringTestRig.DEVICE, b.work.store.deviceId)
        }
    }
}
