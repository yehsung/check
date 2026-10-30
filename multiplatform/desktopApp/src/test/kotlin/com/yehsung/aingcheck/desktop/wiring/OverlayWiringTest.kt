// 조정자 배선 시험 — OverlayWiring 을 가짜 의존(InMemoryDesktopWorkState · InMemoryDesktopKeyValueStore · FakeSink/FakeMeasure ·
// 가상 시간 단조 시계)으로 만들고 start→stop 한 바퀴를 돈다. 합성 값만(실제 홈·계정·네트워크 0).
package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.foundation.platform.MonotonicClock
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.overlay.engine.BubbleKind
import com.yehsung.aingcheck.desktop.overlay.engine.DuelGame
import com.yehsung.aingcheck.desktop.overlay.engine.FakeMeasure
import com.yehsung.aingcheck.desktop.overlay.engine.FakeSink
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayTimings
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayView
import com.yehsung.aingcheck.desktop.overlay.engine.ReactionRules
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.work.AutoCloseReason
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.feature.desktop.work.InMemoryDesktopWorkState
import com.yehsung.aingcheck.feature.desktop.work.WorkEvent
import com.yehsung.aingcheck.feature.desktop.work.WorkStartOrigin
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Clock
import kotlin.time.Instant

class OverlayWiringTest {
    private val wallEpoch = 1_792_465_200L

    private class FakePower : PowerEvents {
        val listeners = ArrayList<(PowerEvent) -> Unit>()
        var closed = 0
        override fun addListener(listener: (PowerEvent) -> Unit): Registration {
            listeners += listener
            return Registration { closed += 1; listeners -= listener }
        }
    }

    private inner class Rig(
        val scope: TestScope,
        config: DesktopAppConfig = DesktopAppConfig(),
        val kv: InMemoryDesktopKeyValueStore = InMemoryDesktopKeyValueStore(),
        enabled: Boolean = true,
    ) {
        val work = InMemoryDesktopWorkState()
        val overlayOn = MutableStateFlow(enabled)
        val sink = FakeSink()
        val power = FakePower()
        val weekly = MutableSharedFlow<Long>(extraBufferCapacity = 4)
        val views = ArrayList<Pair<Double, OverlayView>>()
        val wiring = OverlayWiring(
            OverlayWiringDeps(
                desktopConfig = config,
                keyValueStore = kv,
                clock = object : Clock {
                    override fun now(): Instant = Instant.fromEpochMilliseconds(wallEpoch * 1000 + scope.testScheduler.currentTime)
                },
                monotonic = object : MonotonicClock {
                    override fun elapsedNanos(): Long = scope.testScheduler.currentTime * 1_000_000
                },
                workState = { work },
                overlayEnabled = overlayOn,
                sink = sink,
                measure = FakeMeasure(),
                power = power,
                weeklyRubyGrants = weekly,
                presenter = OverlayPresenter { view, now -> views += now to view },
                random = Random(7),
            ),
        )

        /** 화면에 뜬 말풍선(문구, 뜬 시각) — 같은 말풍선은 한 번만 센다. */
        fun shownBubbles(): List<Pair<String, Double>> = views.mapNotNull { it.second.bubble?.let { b -> b.text to b.shownAt } }.distinct()
        fun nudgeShows(): Int = shownBubbles().count { it.first == OverlayTimings.NUDGE_AUTO_START_TEXT }
        fun startWorking(origin: WorkStartOrigin) = work.set(DesktopWorkSnapshot(isWorking = true, startOrigin = origin))
    }

    private fun TestScope.step(ms: Long) { advanceTimeBy(ms); runCurrent() }

    @Test
    fun `start→stop 한 바퀴 — 근무 스냅숏이 보이게 하고, stop 뒤엔 틱·리스너·사건이 엔진에 닿지 않는다`() = runTest {
        val rig = Rig(this)
        rig.wiring.start(backgroundScope)
        step(100)
        assertTrue(rig.views.isNotEmpty(), "틱이 그림을 낸다")
        assertFalse(rig.wiring.director.isVisibleWhileWorking)

        rig.startWorking(WorkStartOrigin.MANUAL)
        step(100)
        assertTrue(rig.wiring.director.isVisibleWhileWorking, "isWorking·캐릭터 켜짐 → 보임")
        assertTrue(rig.wiring.availability.value.visibleNow, "중재(W3-c1)가 읽는 값도 따라온다")
        assertEquals(ReactionRules.COMMUTE_START_TEXT, rig.shownBubbles().last().first)
        assertEquals(1, rig.power.listeners.size)

        rig.wiring.stop()
        assertEquals(1, rig.power.closed, "stop 은 등록을 거둔다")
        val frames = rig.wiring.framesPresented
        rig.wiring.ultraChargedSink.onUltraCharged()
        step(5_000)
        assertEquals(frames, rig.wiring.framesPresented, "stop 뒤 틱 0")
        assertFalse(rig.shownBubbles().any { it.first == ReactionRules.MISSION_REWARD_TEXT }, "stop 뒤 사건은 엔진에 닿지 않는다")
    }

    @Test
    fun `I-8 넛지 8초 문구는 한 번 — 스냅숏 NUDGE 뒤 NudgeStarted 가 와도, 사건이 먼저 와도`() = runTest {
        // ① ws 순서: 스냅숏(isWorking + NUDGE)이 먼저 적용되고 그 뒤 NudgeStarted — 문구는 스냅숏 startOrigin 이 걸고, 늦은 사건은 무시.
        val a = Rig(this)
        a.wiring.start(backgroundScope)
        step(50)
        a.startWorking(WorkStartOrigin.NUDGE)
        step(50)
        assertEquals(1, a.nudgeShows(), "스냅숏 startOrigin=NUDGE 만으로 문구가 걸린다")
        a.wiring.workEventSink.onWorkEvent(WorkEvent.NudgeStarted)
        step(20_000)
        assertEquals(1, a.nudgeShows(), "넛지 문구 1회: ${a.shownBubbles()}")
        a.wiring.stop()

        // ② 사건이 먼저(스냅숏보다 앞서 도착).
        val b = Rig(this)
        b.wiring.start(backgroundScope)
        step(50)
        b.wiring.workEventSink.onWorkEvent(WorkEvent.NudgeStarted)
        step(50)
        b.startWorking(WorkStartOrigin.NUDGE)
        step(20_000)
        assertEquals(1, b.nudgeShows(), "넛지 문구 1회: ${b.shownBubbles()}")
        b.wiring.stop()

        // 대조: 손으로 시작(MANUAL)·사건 없음이면 넛지 문구 0(평소 출근 문구).
        val c = Rig(this)
        c.wiring.start(backgroundScope)
        step(50)
        c.startWorking(WorkStartOrigin.MANUAL)
        step(20_000)
        assertEquals(0, c.nudgeShows())
        assertTrue(c.shownBubbles().any { it.first == ReactionRules.COMMUTE_START_TEXT })
        c.wiring.stop()
    }

    @Test
    fun `랩 축하·자동 마감 사건은 오버레이가 무시 — 랩 루비는 UltraChargedSink 길로 한 번만, 주간 루비는 RubyReward`() = runTest {
        val rig = Rig(this)
        rig.wiring.start(backgroundScope)
        rig.startWorking(WorkStartOrigin.MANUAL)
        step(15_000) // 출근 말풍선이 끝나기를 기다린다
        val before = rig.shownBubbles().size
        rig.wiring.workEventSink.onWorkEvent(WorkEvent.LapCelebrated(lapsToday = 1, streakDays = 2))
        rig.wiring.workEventSink.onWorkEvent(WorkEvent.AutoClosed(AutoCloseReason.AWAY, SwiftDate.fromEpochMillis(wallEpoch * 1000)))
        step(500)
        assertEquals(before, rig.shownBubbles().size, "LapCelebrated·AutoClosed 는 말풍선 0(이중 방지)")

        rig.wiring.ultraChargedSink.onUltraCharged()
        step(500)
        assertEquals(1, rig.shownBubbles().count { it.first == ReactionRules.MISSION_REWARD_TEXT })

        step(15_000)
        rig.weekly.emit(50)
        step(500)
        assertEquals(1, rig.shownBubbles().count { it.first == ReactionRules.rubyRewardText(50) })
        rig.wiring.stop()
    }

    @Test
    fun `깃발 꺼짐 — duels=false 면 대결 신청 안내 0(W-3 #7), 켜면 같은 입력이 말풍선이 된다`() = runTest {
        val expires = SwiftDate.fromEpochMillis((wallEpoch + 60) * 1000)
        val off = Rig(this, DesktopAppConfig(duels = false))
        off.wiring.start(backgroundScope)
        step(50)
        off.wiring.onDuelInvite(DuelGame.GOMOKU, "m-1", "합성상대", 5, expires)
        step(3_000)
        assertTrue(off.wiring.director.pendingInvitesForTest(DuelGame.GOMOKU).isEmpty())
        assertFalse(off.views.any { it.second.bubble?.kind is BubbleKind.Invite }, "꺼진 깃발: 신청 말풍선 0")
        off.wiring.stop()

        val on = Rig(this, DesktopAppConfig(duels = true))
        on.wiring.start(backgroundScope)
        step(50)
        on.wiring.onDuelInvite(DuelGame.GOMOKU, "m-1", "합성상대", 5, expires)
        step(3_000)
        assertTrue(on.views.any { (it.second.bubble?.kind as? BubbleKind.Invite)?.matchId == "m-1" }, "켠 깃발: 같은 입력 → 신청 말풍선(peek)")
        on.wiring.stop()
    }

    @Test
    fun `업데이트 말풍선은 버전당 한 번 — 이미 띄운 버전은 DesktopKeyValueStore 로 재시작을 넘는다`() = runTest {
        val kv = InMemoryDesktopKeyValueStore()
        val first = Rig(this, kv = kv)
        first.wiring.start(backgroundScope)
        first.startWorking(WorkStartOrigin.MANUAL)
        step(15_000)
        first.wiring.onUpdateAvailable("0.4.1")
        step(500)
        assertEquals(1, first.shownBubbles().count { it.first == OverlayTimings.UPDATE_BUBBLE_TEXT })
        assertEquals("0.4.1", kv.getString(OverlayWiring.SHOWN_UPDATE_VERSION_KEY))
        first.wiring.stop()

        val second = Rig(this, kv = kv)
        second.wiring.start(backgroundScope)
        second.startWorking(WorkStartOrigin.MANUAL)
        step(15_000)
        second.wiring.onUpdateAvailable("0.4.1")
        step(60_000)
        assertEquals(0, second.shownBubbles().count { it.first == OverlayTimings.UPDATE_BUBBLE_TEXT }, "재시작 뒤 같은 버전 0")
        second.wiring.stop()
    }

    @Test
    fun `잠자기 동안 그리기 정지 — platform power SLEEP·WAKE 가 onRenderSuspend 로`() = runTest {
        val rig = Rig(this)
        rig.wiring.start(backgroundScope)
        rig.startWorking(WorkStartOrigin.MANUAL)
        step(200)
        rig.power.listeners.toList().forEach { it(PowerEvent.SLEEP) }
        step(200)
        assertTrue(rig.views.last().second.renderSuspended)
        rig.power.listeners.toList().forEach { it(PowerEvent.WAKE) }
        step(200)
        assertFalse(rig.views.last().second.renderSuspended)
        rig.wiring.stop()
    }
}
