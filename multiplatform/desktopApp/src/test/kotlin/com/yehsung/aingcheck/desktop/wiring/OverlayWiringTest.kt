// 조정자 배선 시험 — OverlayWiring 을 가짜 의존(InMemoryDesktopWorkState · InMemoryDesktopKeyValueStore · FakeSink/FakeMeasure ·
// 가상 시간 단조 시계)으로 만들고 start→stop 한 바퀴를 돈다. 합성 값만(실제 홈·계정·네트워크 0).
package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.foundation.platform.MonotonicClock
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.overlay.assembly.OverlaySurfaces
import com.yehsung.aingcheck.desktop.overlay.engine.BoardHost
import com.yehsung.aingcheck.desktop.overlay.engine.BubbleKind
import com.yehsung.aingcheck.desktop.overlay.engine.DuelFacts
import com.yehsung.aingcheck.desktop.overlay.engine.HitTarget
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayPoint
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayRect
import com.yehsung.aingcheck.desktop.overlay.engine.PointerKind
import com.yehsung.aingcheck.desktop.overlay.engine.PointerOutcome
import com.yehsung.aingcheck.desktop.overlay.todoboard.TodoBoardAppearanceStore
import com.yehsung.aingcheck.desktop.pages.desktopsettings.TodoBoardSetting
import com.yehsung.aingcheck.feature.desktop.poke.DesktopMessageBubbleQueue
import com.yehsung.aingcheck.feature.desktop.socialapi.QueuedBubbleMessage
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import kotlinx.coroutines.launch
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
        val surfaces: OverlaySurfaces? = null,
        extra: (OverlayWiringDeps) -> OverlayWiringDeps = { it },
    ) {
        val work = InMemoryDesktopWorkState()
        val overlayOn = MutableStateFlow(enabled)
        val sink = FakeSink()
        val power = FakePower()
        val weekly = MutableSharedFlow<Long>(extraBufferCapacity = 4)
        val views = ArrayList<Pair<Double, OverlayView>>()
        val outcomes = ArrayList<PointerOutcome>()
        val wiring = OverlayWiring(
            extra(OverlayWiringDeps(
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
                onPointerOutcome = { outcomes += it },
                random = Random(7),
            )),
            surfaces,
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

    // ───────────────────────── int-w2 배선(W5-b4 notes · W-3 #6) ─────────────────────────

    private fun msg(id: String) = QueuedBubbleMessage(id, "합성동료", "합성 메시지 $id", SwiftDate.fromEpochMillis(wallEpoch * 1000))

    @Test
    fun `말풍선 큐는 하나 — wiring_bubbles 에 쌓인 메시지는 띄우고 소비, 다른 큐 인스턴스는 엔진에 안 닿는다(W-3 #6)`() = runTest {
        val rig = Rig(this)
        rig.wiring.start(backgroundScope)
        step(50)
        val stranger = DesktopMessageBubbleQueue()
        stranger.append(listOf(msg("x1")))
        step(3_000)
        assertEquals(1, stranger.queue.value.size, "음성 대조: 다른 큐는 소비되지 않는다")
        assertTrue(rig.shownBubbles().isEmpty(), "음성 대조: 다른 큐 → 말풍선 0")

        rig.wiring.bubbles.append(listOf(msg("b1")))
        step(3_000)
        assertTrue(rig.shownBubbles().isNotEmpty(), "같은 큐 → 말풍선")
        assertTrue(rig.wiring.bubbles.queue.value.isEmpty(), "띄웠으니 소비(규약 10)")
        rig.wiring.stop()
    }

    @Test
    fun `계정 전환 — 알던 계정에서 다른 id·로그아웃이면 대결 큐를 비운다, 첫 로그인·같은 id 는 그대로`() = runTest {
        val ids = MutableSharedFlow<String?>(extraBufferCapacity = 8)
        val rig = Rig(this, DesktopAppConfig(duels = true)) { it.copy(accountIds = ids) }
        rig.wiring.start(backgroundScope)
        step(50)
        rig.startWorking(WorkStartOrigin.MANUAL)
        step(100) // 출근 말풍선이 떠 있는 동안 신청은 큐에 남는다
        val expires = SwiftDate.fromEpochMillis((wallEpoch + 600) * 1000)
        rig.wiring.onDuelFacts(DuelGame.GOMOKU, DuelFacts(aliveInviteIds = setOf("m-1", "m-2")))
        rig.wiring.onDuelInvite(DuelGame.GOMOKU, "m-1", "합성상대", 5, expires)
        step(100)
        assertEquals(1, rig.wiring.director.pendingInvitesForTest(DuelGame.GOMOKU).size, "전제: 신청이 큐에 있다")

        ids.emit(null); step(10); ids.emit("u-a"); step(10); ids.emit("u-a"); step(10)
        assertEquals(1, rig.wiring.director.pendingInvitesForTest(DuelGame.GOMOKU).size, "음성 대조: 첫 로그인·같은 id 는 비우지 않는다")

        ids.emit("u-b"); step(10)
        assertTrue(rig.wiring.director.pendingInvitesForTest(DuelGame.GOMOKU).isEmpty(), "계정 전환 → onSignedOut")

        rig.wiring.onDuelInvite(DuelGame.GOMOKU, "m-2", "합성상대", 5, expires)
        step(10)
        assertEquals(1, rig.wiring.director.pendingInvitesForTest(DuelGame.GOMOKU).size, "전제: 새 계정의 신청이 큐에 있다")
        ids.emit(null); step(10)
        assertTrue(rig.wiring.director.pendingInvitesForTest(DuelGame.GOMOKU).isEmpty(), "로그아웃 → onSignedOut")
        rig.wiring.stop()
    }

    @Test
    fun `할 일 보드 설정 — 켜짐이 꺼지면 열린 보드를 닫고, 진하기는 외양으로·보드에서 바꾼 진하기는 설정으로(stop 뒤 0)`() = runTest {
        val board = com.yehsung.aingcheck.desktop.overlay.todoboard.BoardFixture()
        val kv = InMemoryDesktopKeyValueStore()
        val appearance = TodoBoardAppearanceStore(kv)
        val setting = MutableStateFlow(TodoBoardSetting(enabled = true, opacity = null))
        val written = ArrayList<Double>()
        val surfaces = OverlaySurfaces(FakeSink(), OverlayPresenter.None, board.controller, appearance, null, null) {}
        val rig = Rig(this, kv = kv, surfaces = surfaces) { it.copy(todoBoard = setting, onBoardOpacityChanged = { v -> written += v }) }
        rig.wiring.start(backgroundScope)
        step(50)
        board.controller.toggle(OverlayRect(1200.0, 130.0, 140.0, 170.0), OverlayRect(0.0, 0.0, 1440.0, 900.0))
        assertTrue(board.surface.visible, "전제: 보드 열림")

        setting.value = TodoBoardSetting(enabled = true, opacity = 0.8)
        step(50)
        assertEquals(0.8, appearance.appearance.opacity, "설정 진하기 → 외양")
        assertTrue(board.surface.visible, "음성 대조: 진하기만 바뀌면 보드는 그대로")

        board.enabled = false
        setting.value = TodoBoardSetting(enabled = false, opacity = 0.8)
        step(50)
        assertFalse(board.surface.visible, "켜짐 꺼짐 → 열린 보드 닫기(enabledDidChange)")

        appearance.setOpacity(0.3)
        assertEquals(listOf(0.3), written, "보드에서 바꾼 진하기 → 설정(같은 값 되돌림은 0)")
        rig.wiring.stop()
        appearance.setOpacity(0.4)
        assertEquals(listOf(0.3), written, "stop 뒤 0")
    }

    @Test
    fun `실물 화면 조립 — surfaces 의 sink·presenter·board 로 갈아 끼우고 포인터를 묶는다, stop 은 엔진 뒤 창을 한 번 닫는다`() = runTest {
        val sink = FakeSink()
        val frames = ArrayList<OverlayView>()
        val relay = OverlaySurfaces.PointerRelay()
        var closed = 0
        val surfaces = OverlaySurfaces(sink, OverlayPresenter { v, _ -> frames += v }, BoardHost.None, null, null, relay) { closed += 1 }
        val rig = Rig(this, surfaces = surfaces)
        rig.wiring.start(backgroundScope)
        step(100)
        assertTrue(frames.isNotEmpty(), "그림은 실물 발표자로")
        assertTrue(rig.views.isEmpty(), "음성 대조: deps 의 발표자는 갈아 끼워져 안 불린다")

        relay.onPointer(PointerKind.DOWN, OverlayPoint(10.0, 10.0), HitTarget.Body)
        relay.onPointer(PointerKind.UP, OverlayPoint(10.0, 10.0), HitTarget.Body)
        step(50)
        assertEquals(2, rig.outcomes.size, "창 포인터 → 배선 → 엔진 → 포인터 결과(원래 콜백도 불린다)")

        rig.wiring.stop()
        val n = frames.size
        step(1_000)
        assertEquals(n, frames.size, "stop 뒤 그림 0")
        assertEquals(1, closed, "창은 한 번 닫힌다")
        rig.wiring.stop()
        assertEquals(1, closed, "두 번째 stop 도 한 번")
    }

    @Test
    fun `주간 루비 흐름 — 일련번호가 오를 때만 낸다, 같은 값·로그아웃 0 되돌림은 0`() = runTest {
        val src = MutableSharedFlow<Pair<Int, Long?>>(extraBufferCapacity = 8)
        val out = ArrayList<Long>()
        val job = launch { OverlayWiring.weeklyRubyGrants(src).collect { out += it } }
        runCurrent()
        src.emit(0 to null); src.emit(1 to 20L); src.emit(1 to 20L); src.emit(0 to null); src.emit(1 to 50L); src.emit(2 to null)
        runCurrent()
        assertEquals(listOf(20L, 50L), out)
        job.cancel()
    }

    @Test
    fun `게임 화면의 나 — 근무 중 Working, 아니면 Off(맥 CheckMascotAssets mood)`() = runTest {
        val rig = Rig(this)
        assertEquals(CharacterMood.Off, rig.wiring.boardMe("합성", "fox").mood)
        rig.startWorking(WorkStartOrigin.MANUAL)
        assertEquals(BoardGameMe("합성", "fox", CharacterMood.Working), rig.wiring.boardMe("합성", "fox"))
    }
}
