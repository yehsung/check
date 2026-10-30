package com.yehsung.aingcheck.desktop.overlay.engine

import com.yehsung.aingcheck.core.rules.insights.DrowsyWindow
import com.yehsung.aingcheck.feature.desktop.work.WorkEvent
import com.yehsung.aingcheck.feature.desktop.work.WorkStartOrigin
import java.time.Instant
import java.time.ZoneId
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 출근·작별 0.55s·오버라이드(규약 7·8) — 맥 CheckOverlayTests overlayController* 시나리오. */
class OverlayWorkingTest {
    @Test fun overlayControllerTogglesVisibilityWithWorking() {
        val f = Fixture()
        f.d.onWorking(isWorking = true, overlayEnabled = true, now = 0.0)
        assertEquals(OverlayMode.Normal, f.d.mode(0.0))
        assertTrue("play:commuteStart" in f.sink.calls)
        assertEquals(ReactionRules.COMMUTE_START_TEXT, f.d.bubbleAt(4.99)?.text)
        assertNull(f.d.bubbleAt(5.0))
        f.d.onWorking(isWorking = false, overlayEnabled = true, now = 10.0)
        assertEquals(OverlayMode.Farewell, f.d.mode(10.0))
        assertTrue("play:commuteEnd" in f.sink.calls)
        assertEquals(ReactionRules.COMMUTE_END_TEXT, f.d.bubbleAt(10.1)?.text)
        f.d.tick(10.0 + 0.549)
        assertEquals(OverlayMode.Farewell, f.d.mode(10.549))
        f.d.tick(10.0 + 0.55)
        assertEquals(OverlayMode.Hidden, f.d.mode(10.55), "작별 숨김 = commuteEnd 0.4 + 0.15")
        assertEquals(0.55, OverlayTimings.FAREWELL_HIDE_S, 1e-9)
    }

    @Test fun overlayTimerStaysVisibleDuringFarewell_andRestartWithinFarewellCancelsHide() {
        val f = Fixture()
        f.d.onWorking(true, true, 0.0)
        f.d.onWorking(false, true, 10.0)
        f.d.onWorking(true, true, 10.2)
        assertEquals(OverlayMode.Normal, f.d.mode(10.2))
        assertEquals(ReactionKind.CommuteStart, f.d.activeReaction(10.25), "commuteEnd→commuteStart 재시작(규약 3)")
        f.d.tick(11.0)
        assertEquals(OverlayMode.Normal, f.d.mode(11.0), "취소된 작별이 창을 숨기지 않는다")
    }

    @Test fun sameValueReEmissionDoesNotReplayCommuteStart() {
        val f = Fixture()
        f.d.onWorking(true, true, 0.0)
        f.sink.clear()
        f.d.onWorking(true, true, 20.0)
        assertTrue(f.sink.calls.isEmpty(), "StateFlow 의 같은 값 재방출은 무시")
    }

    @Test fun overlayDisabledNeverShows() {
        val f = Fixture()
        f.d.onWorking(true, false, 0.0)
        assertEquals(OverlayMode.Hidden, f.d.mode(0.0))
        assertFalse(f.d.availability(0.0).canPeek)
    }

    // 규약 7 — 오버라이드는 어느 길이든 소비, 10s 넘은 것은 평소 문구.
    @Test fun rule07_firstArrivalOverrideIsUsedOnceThenConsumed() {
        val f = Fixture()
        f.d.setCommuteStartOverride(OverlayTimings.FIRST_ARRIVAL_TEXT, OverlayTimings.FIRST_ARRIVAL_BUBBLE_S, 0.0)
        f.d.onWorking(true, true, 10.0) // 경계 10s 는 아직 유효(<=)
        val b = f.d.bubbleAt(10.0)!!
        assertEquals(OverlayTimings.FIRST_ARRIVAL_TEXT, b.text)
        assertEquals(16.0, b.until, 1e-9)
        f.d.onWorking(false, true, 20.0)
        f.d.onWorking(true, true, 30.0)
        assertEquals(ReactionRules.COMMUTE_START_TEXT, f.d.bubbleAt(30.0)?.text, "두 번째 출근은 평소 문구")
    }

    @Test fun rule07_staleCommuteStartOverrideFallsBackToDefaultBubble_andIsStillConsumed() {
        val f = Fixture()
        f.d.setCommuteStartOverride("오래된 문구", 8.0, 0.0)
        f.d.onWorking(true, true, 10.01)
        assertEquals(ReactionRules.COMMUTE_START_TEXT, f.d.bubbleAt(10.02)?.text)
        f.d.onWorking(false, true, 20.0)
        f.d.setCommuteStartOverride("새 문구", 8.0, 25.0)
        f.d.onWorking(true, true, 26.0)
        assertEquals("새 문구", f.d.bubbleAt(26.0)?.text)
    }

    @Test fun overlayNudgeAutoStartShowsEightSecondNotice_viaStartOriginOrEvent() {
        val f = Fixture()
        f.d.onWorking(true, true, 0.0, WorkStartOrigin.NUDGE)
        val b = f.d.bubbleAt(0.0)!!
        assertEquals(OverlayTimings.NUDGE_AUTO_START_TEXT, b.text)
        assertEquals(8.0, b.until, 1e-9)
        val g = Fixture()
        g.d.onWorking(false, true, 0.0)
        g.d.onWorkEvent(WorkEvent.NudgeStarted, 1.0)
        g.d.onWorking(true, true, 1.1)
        assertEquals(OverlayTimings.NUDGE_AUTO_START_TEXT, g.d.bubbleAt(1.1)?.text)
        val h = Fixture()
        h.d.onWorking(false, false, 0.0)
        h.d.onWorkEvent(WorkEvent.NudgeStarted, 1.0)
        h.d.onWorking(true, true, 1.1)
        assertEquals(ReactionRules.COMMUTE_START_TEXT, h.d.bubbleAt(1.1)?.text, "캐릭터가 꺼져 있을 때 걸린 넛지 문구는 없다")
    }

    // ★ 규약 8 — goalAchieved 는 가시 게이트 길(숨김이면 버림), 보상 길은 생산자가 고른 것을 그대로(화이트리스트 없음).
    @Test fun rule08_goalAchievedIsGatedNotPeeked_rewardPathHasNoWhitelist() {
        val f = Fixture()
        f.d.onWorking(false, true, 0.0)
        f.d.onWorkEvent(WorkEvent.TeamGoalAchieved, 1.0)
        assertEquals(OverlayMode.Hidden, f.d.mode(1.0), "숨김 중 팀 목표는 peek 하지 않는다")
        assertNull(f.d.bubbleAt(1.0))
        assertTrue(f.d.onReward(ReactionKind.RubyReward(50), 2.0))
        assertEquals(OverlayMode.Peek, f.d.mode(2.0))
        assertEquals("루비 +50!", f.d.bubbleAt(2.0)?.text)
        val g = Fixture()
        g.d.onWorking(false, true, 0.0)
        assertTrue(g.d.onReward(ReactionKind.GoalAchieved, 1.0), "생산자가 보상 길로 보내면 막지 않는다(두 번째 화이트리스트 금지)")
        val h = Fixture()
        val t = h.working()
        h.d.onWorkEvent(WorkEvent.TeamGoalAchieved, t)
        assertEquals(ReactionRules.GOAL_TEXT, h.d.bubbleAt(t)?.text)
        h.d.onWorkEvent(WorkEvent.Milestone(4), t + 10)
        assertEquals(ReactionKind.Milestone, h.d.activeReaction(t + 10.1))
    }
}

/** 졸기·낮잠·깜빡·업데이트 말풍선 스케줄(시드 Random). 규약 12. */
class OverlaySchedulesTest {
    @Test fun seededDrawsStayInsideTheMacRanges() {
        val rng = Random(42)
        val drowsy = List(2000) { OverlaySchedules.nextDrowsyInterval(rng) }
        val nap = List(2000) { OverlaySchedules.nextNapDuration(rng) }
        val blink = List(2000) { OverlaySchedules.nextBlinkInterval(rng) }
        assertTrue(drowsy.all { it in 40 * 60.0..80 * 60.0 }, "졸기 40~80분")
        assertTrue(nap.all { it in 5 * 60.0..10 * 60.0 }, "낮잠 5~10분")
        assertTrue(blink.all { it in 3.0..7.0 }, "깜빡 3~7s")
        assertTrue(drowsy.max() - drowsy.min() > 30 * 60.0, "타이머가 아니라 졸음 — 매번 다르다")
        assertEquals(DrowsyWindow.minInterval, 2400.0)
    }

    @Test fun drowsySchedulerPutsCharacterToSleepWhenIdle_andBlinksOnSchedule() {
        val f = Fixture()
        f.d.onWorking(true, true, 0.0)
        val at = f.d.nextDrowsyAtForTest!!
        assertTrue(at in 2400.0..4800.0)
        val blinkAt = f.d.nextBlinkAtForTest!!
        assertTrue(blinkAt in 3.0..7.0)
        f.d.tick(blinkAt)
        assertTrue("blink" in f.sink.calls)
        f.d.tick(at - 0.01)
        assertFalse(f.d.isSleeping)
        f.d.tick(at)
        assertTrue(f.d.isSleeping)
        val nap = f.d.napEndsAtForTest!!
        assertTrue(nap - at in 300.0..600.0)
    }

    @Test fun boardOpenOrSuspendedBlocksDrowsy() {
        val f = Fixture()
        f.d.onWorking(true, true, 0.0)
        f.board.open = true
        f.d.tick(f.d.nextDrowsyAtForTest!!)
        assertFalse(f.d.isSleeping, "보드가 열려 있으면 졸지 않는다")
        f.board.open = false
        f.d.onRenderSuspend(RenderSuspendReason.SCREENS_ASLEEP, true, 1.0)
        f.d.tick(f.d.nextDrowsyAtForTest!!)
        assertFalse(f.d.isSleeping)
    }

    // ⚠️ 규약 12 — 맥은 DrowsyWindow.contains 를 안 쓴다: 낮 14시(KST)에도 존다.
    @Test fun rule12_drowsyHappensAtTwoPmKst_noNightWindow() {
        val twoPm = Instant.parse("2026-10-30T05:00:00Z")
        assertEquals(14, twoPm.atZone(ZoneId.of("Asia/Seoul")).hour)
        val start = twoPm.epochSecond.toDouble()
        val f = Fixture()
        f.d.onWorking(true, true, start)
        f.d.tick(f.d.nextDrowsyAtForTest!!)
        assertTrue(f.d.isSleeping, "시간창 없음 — 간격 40~80분만")
    }

    @Test fun overlayShowsUpdateBubbleOncePerVersionWhileVisibleAndIdle() {
        val f = Fixture()
        val t = f.working()
        assertTrue(f.d.onUpdateAvailable("0.1.2", t))
        assertEquals(OverlayTimings.UPDATE_BUBBLE_TEXT, f.d.bubbleAt(t)?.text)
        assertFalse(f.d.onUpdateAvailable("0.1.2", t + 100), "같은 버전은 한 번")
        f.d.request(ReactionKind.Milestone, t + 200)
        assertFalse(f.d.onUpdateAvailable("0.1.3", t + 200.1), "재생 중엔 미룬다")
        f.d.tick(f.d.nextDrowsyAtForTest!!)
        assertEquals("0.1.3", f.d.shownUpdateVersion, "졸기 주기에 다시 시도해 보여 준다")
        assertFalse(f.d.isSleeping, "업데이트 말풍선을 띄운 주기엔 졸지 않는다")
        val g = Fixture()
        g.d.onWorking(false, true, 0.0)
        assertFalse(g.d.onUpdateAvailable("0.1.2", 1.0), "숨김이면 안 띄운다")
    }
}
