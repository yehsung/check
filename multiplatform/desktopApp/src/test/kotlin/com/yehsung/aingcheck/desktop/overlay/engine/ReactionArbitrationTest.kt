package com.yehsung.aingcheck.desktop.overlay.engine

import com.yehsung.aingcheck.desktop.overlay.engine.OverlayDirector.EngineState
import com.yehsung.aingcheck.desktop.overlay.engine.ReactionKind.CommuteEnd
import com.yehsung.aingcheck.desktop.overlay.engine.ReactionKind.CommuteStart
import com.yehsung.aingcheck.desktop.overlay.engine.ReactionKind.Drowsy
import com.yehsung.aingcheck.desktop.overlay.engine.ReactionKind.GoalAchieved
import com.yehsung.aingcheck.desktop.overlay.engine.ReactionKind.Hit
import com.yehsung.aingcheck.desktop.overlay.engine.ReactionKind.Milestone
import com.yehsung.aingcheck.desktop.overlay.engine.ReactionKind.UltraCharged
import com.yehsung.aingcheck.desktop.overlay.engine.ReactionKind.Wake
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 맥 CheckOverlayTests·UltraPokeOverlayTests 의 리액션 중재 시나리오(이름 따라). 규약 1·2·3·4·5·6. */
class ReactionArbitrationTest {
    private fun idle(): Pair<Fixture, Double> { val f = Fixture(); return f to f.working(0.0) }

    @Test fun reactionEnginePrioritizesHigherAndIgnoresLowerWhilePlaying() {
        val (f, t) = idle()
        assertTrue(f.d.request(Milestone, t))
        assertFalse(f.d.request(ReactionKind.Greeting("민수"), t + 0.1), "낮은 순위는 거절")
        assertTrue(f.d.request(Hit, t + 0.2), "높은 순위는 이긴다")
        assertEquals(Hit, f.d.activeReaction(t + 0.3))
    }

    @Test fun reactionEngineEnforcesHitCooldown() {
        val (f, t) = idle()
        assertTrue(f.d.request(Hit, t))
        assertFalse(f.d.request(Hit, t + 0.61 - 0.02), "0.6s 안 두 번째 때리기는 거절")
        assertTrue(f.d.request(Hit, t + 0.61))
    }

    // ⚠️ 규약 1 — 자는 중 보상은 endSleep 뒤 재생(무시 가지 아님).
    @Test fun rule01_sleepingIsInterruptedByRewardReactions() {
        for (kind in listOf(GoalAchieved, UltraCharged, ReactionKind.RubyReward(20))) {
            val (f, t) = idle()
            assertTrue(f.d.request(Drowsy, t))
            assertEquals(EngineState.SLEEPING, f.d.state(t + 1))
            assertTrue(f.d.request(kind, t + 2), "$kind 은 자는 중에도 재생된다")
            assertEquals(EngineState.PLAYING, f.d.state(t + 2.1))
            assertTrue(f.d.bubbleAt(t + 2.1) != null, "$kind 말풍선(보상 통지)이 증발하지 않는다")
        }
    }

    @Test fun rule01_drowsyAndGreetingAreIgnoredWhileSleeping_hitAndWakeStartleRegardlessOfCooldown() {
        val (f, t) = idle()
        assertTrue(f.d.request(Hit, t))
        f.d.cancelActiveReaction(t + 0.1) // 쿨다운 창(0.6) 안에서 잠들게 만든다
        assertTrue(f.d.request(Drowsy, t + 0.2))
        assertFalse(f.d.request(ReactionKind.Greeting("민수"), t + 0.25))
        assertFalse(f.d.request(Drowsy, t + 0.25), "reactionEngineReDrowsyWhileSleepingIsNoop")
        assertTrue(f.d.isSleeping)
        // 때리기 쿨다운(0.6) 안이어도 자는 중 hit 은 화들짝.
        assertTrue(f.d.request(Hit, t + 0.3))
        assertEquals(Wake, f.d.activeReaction(t + 0.35))
        assertEquals(ReactionRules.WAKE_TEXT, f.d.bubbleAt(t + 0.35)?.text)
        assertTrue("wake:startled" in f.sink.calls)
    }

    // 규약 2 — 울트라만 4, 길이 5.0 = ultraSeconds.
    @Test fun rule02_ultraPokedOutranksEveryOtherReaction_andIsFiveSeconds() {
        val all = listOf(Hit, CommuteStart, CommuteEnd, Milestone, ReactionKind.Greeting("a"), Drowsy, Wake,
            ReactionKind.Poked("p"), GoalAchieved, UltraCharged, ReactionKind.RubyReward(3))
        assertTrue(all.all { it.priority < 4 })
        assertEquals(4, ReactionKind.UltraPoked("u").priority)
        assertEquals(OverlayTimings.ULTRA_S, ReactionKind.UltraPoked("u").duration)
        assertEquals(OverlayTimings.ULTRA_S, ReactionRules.ULTRA_POKED_BUBBLE_S)
        val (f, t) = idle()
        assertTrue(f.d.request(ReactionKind.UltraPoked("u"), t))
        for (k in all) assertFalse(f.d.request(k, t + 1), "$k 은 울트라를 못 끊는다")
    }

    // 규약 3 — 동순위 양보 예외 넷.
    @Test fun rule03_reactionEngineCommuteStartInterruptsCommuteEnd_butNotTheOtherWay() {
        val (f, t) = idle()
        assertTrue(f.d.request(CommuteEnd, t))
        assertTrue(f.d.request(CommuteStart, t + 0.1), "commuteEnd→commuteStart 재시작")
        assertFalse(f.d.request(CommuteEnd, t + 0.2), "reactionEngineCommuteEndDuringCommuteStartStaysRejected")
    }

    @Test fun rule03_activePokedYieldsToAnyLowerOrEqualRequest() {
        val (f, t) = idle()
        assertTrue(f.d.request(ReactionKind.Poked("a"), t))
        assertTrue(f.d.request(ReactionKind.Poked("b"), t + 0.1), "reactionEngineRepokeInterruptsAndRefreshesBubble")
        assertEquals("b", f.d.bubbleAt(t + 0.2)?.text)
        assertTrue(f.d.request(ReactionKind.Greeting("민수"), t + 0.3), "진행 중 poked 는 인사에도 양보")
    }

    @Test fun rule03_ultraRestartsOnlyForUltra() {
        val (f, t) = idle()
        assertTrue(f.d.request(ReactionKind.UltraPoked("1"), t))
        assertTrue(f.d.request(ReactionKind.UltraPoked("2"), t + 1), "ultraPokedAcceptsRepeatUltraAndRefreshesBubble")
        assertEquals("2", f.d.bubbleAt(t + 1.1)?.text)
    }

    @Test fun rule03_rewardPlaybackYieldsToIncomingPokeButNotToLowerReactions() {
        for (reward in listOf(GoalAchieved, UltraCharged, ReactionKind.RubyReward(50))) {
            val (f, t) = idle()
            assertTrue(f.d.request(reward, t))
            assertFalse(f.d.request(Milestone, t + 0.1), "보상은 낮은 순위(2)에 양보하지 않는다")
            assertFalse(f.d.request(ReactionKind.Greeting("a"), t + 0.1))
            assertTrue(f.d.request(ReactionKind.Poked("p"), t + 0.2), "동순위(3)에만 양보")
        }
    }

    @Test fun rule03_milestoneDoesNotYieldToEqualRank_otherActivesHoldAgainstEqual() {
        val (f, t) = idle()
        assertTrue(f.d.request(Milestone, t))
        assertFalse(f.d.request(Milestone, t + 0.1))
        val (g, u) = idle()
        assertTrue(g.d.request(Hit, u))
        assertFalse(g.d.request(ReactionKind.Poked("p"), u + 0.1), "때리기 재생 중 찌름은 동순위 거절(peek 경로가 반환값을 본다)")
    }

    // ⚠️ 규약 4 — 인터럽트는 모든 일시 파티클을 걷는다.
    @Test fun rule04_interruptClearsEveryTransientParticle() {
        val (f, t) = idle()
        f.d.request(Milestone, t)
        assertEquals(listOf(ParticleCue.CONFETTI), f.d.view(t + 0.1).particles.map { it.cue })
        f.d.request(GoalAchieved, t + 0.2)
        assertEquals(listOf(ParticleCue.GOAL_SPARKS), f.d.view(t + 0.3).particles.map { it.cue }, "앞 색종이는 걷혔다")
        f.d.request(ReactionKind.Poked("p"), t + 0.4)
        assertTrue(f.d.view(t + 0.5).particles.isEmpty())
        // 열거형 전부가 리액션 하나에 대응하거나(ZZZ 는 잠) 걷히는지 — 새 파티클을 더하면 이 목록도 같이 늘어난다.
        assertEquals(setOf(ParticleCue.CONFETTI, ParticleCue.GOAL_SPARKS, ParticleCue.ULTRA_CHARGE, ParticleCue.ZZZ), ParticleCue.entries.toSet())
        f.d.request(Drowsy, t + 5)
        assertEquals(listOf(ParticleCue.ZZZ), f.d.view(t + 5.1).particles.map { it.cue })
        f.d.request(Hit, t + 6)
        assertTrue(f.d.view(t + 6.1).particles.isEmpty(), "깨면 Zzz 도 걷는다")
    }

    // 규약 5 — 렌더 정지 중엔 졸지 않는다. 정지 중 조용한 기상은 스냅.
    @Test fun rule05_noDrowsyWhileRenderSuspended_andQuietWakeSnaps() {
        val (f, t) = idle()
        f.d.onRenderSuspend(RenderSuspendReason.SCREENS_ASLEEP, true, t)
        assertFalse(f.d.request(Drowsy, t + 1), "엔진이 최종 문")
        assertFalse(f.d.isSleeping)
        f.d.onRenderSuspend(RenderSuspendReason.SCREENS_ASLEEP, false, t + 2)
        assertTrue(f.d.request(Drowsy, t + 3))
        f.d.onRenderSuspend(RenderSuspendReason.SCREEN_LOCKED, true, t + 4)
        f.sink.clear()
        f.d.wakeQuietly(t + 5)
        assertEquals(listOf("interrupt"), f.sink.calls, "정지 중 조용한 기상은 애니메이션 없이 스냅")
        f.d.onRenderSuspend(RenderSuspendReason.SCREEN_LOCKED, false, t + 6)
        assertTrue(f.d.request(Drowsy, t + 7))
        f.sink.clear()
        f.d.wakeQuietly(t + 8)
        assertEquals(listOf("wake:quiet"), f.sink.calls)
    }

    @Test fun staleLockReasonIsReleasedOnlyWhenConsoleUsable() {
        val (f, t) = idle()
        f.d.onRenderSuspend(RenderSuspendReason.SCREEN_LOCKED, true, t)
        f.d.onRenderSuspend(RenderSuspendReason.SCREENS_ASLEEP, true, t)
        assertFalse(f.d.reconcileStaleRenderSuspension(consoleSessionUsable = false, now = t + 1))
        assertTrue(f.d.reconcileStaleRenderSuspension(consoleSessionUsable = true, now = t + 1))
        assertTrue(f.d.view(t + 1).renderSuspended, "화면 꺼짐은 오래돼도 풀지 않는다")
        f.d.onRenderSuspend(RenderSuspendReason.SCREENS_ASLEEP, false, t + 2)
        assertFalse(f.d.view(t + 2).renderSuspended)
    }

    // 규약 6 — endSleep 은 낮잠 타이머까지 끊는다.
    @Test fun rule06_endSleepCancelsNapTimer_soAnOldNapNeverWakesTheNextSleep() {
        val (f, t) = idle()
        assertTrue(f.d.request(Drowsy, t))
        val firstNapEnd = f.d.napEndsAtForTest!!
        f.d.request(Hit, t + 10)
        assertNull(f.d.napEndsAtForTest, "깨우면 낮잠 타이머도 사라진다")
        assertTrue(f.d.request(Drowsy, t + 700))
        val secondNapEnd = f.d.napEndsAtForTest!!
        assertTrue(secondNapEnd > firstNapEnd)
        f.d.tick(firstNapEnd + 0.01)
        assertTrue(f.d.isSleeping, "옛 낮잠 마감이 새 잠을 깨우지 않는다")
        f.d.tick(secondNapEnd)
        assertFalse(f.d.isSleeping, "자기 낮잠 마감엔 조용히 깬다")
    }

    @Test fun reactionEngineSleepPersistsUntilWoken_andMilestoneWakesAndPlays() {
        val (f, t) = idle()
        f.d.request(Drowsy, t)
        assertEquals(EngineState.SLEEPING, f.d.state(t + 200))
        assertTrue(f.d.request(Milestone, t + 201))
        assertEquals(Milestone, f.d.activeReaction(t + 201.1))
        assertFalse(f.d.isSleeping)
    }

    @Test fun reactionEngineReplacesBubbleWhenInterruptedByReactionWithOwnBubble_milestoneKeepsIt() {
        val (f, t) = idle()
        f.d.request(ReactionKind.Greeting("민수"), t)
        assertEquals("민수님 출근!", f.d.bubbleAt(t + 0.1)?.text)
        f.d.request(Milestone, t + 0.2)
        assertEquals("민수님 출근!", f.d.bubbleAt(t + 0.3)?.text, "말 없는 리액션은 말풍선을 지우지 않는다")
        f.d.request(Hit, t + 0.4)
        assertEquals(ReactionRules.HIT_TEXT, f.d.bubbleAt(t + 0.5)?.text)
    }

    @Test fun reactionBubbleDurationsMatchSpec() {
        val (f, t) = idle()
        f.d.request(Hit, t)
        assertTrue(f.d.bubbleAt(t + 1.19) != null)
        assertNull(f.d.bubbleAt(t + 1.2))
        assertEquals("루비 +3!", ReactionRules.MISSION_REWARD_TEXT)
        assertEquals("루비 +0!", ReactionRules.rubyRewardText(-5))
        assertEquals("루비 +200!", ReactionRules.rubyRewardText(200))
    }
}
