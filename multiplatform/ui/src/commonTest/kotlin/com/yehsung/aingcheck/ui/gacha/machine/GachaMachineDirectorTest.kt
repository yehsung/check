// 원본: Tests/checkTests/V0354GachaMachineTests.swift @ 3bd04bd (감독 — 상태 기계 · 안 보일 때 · 결과 · 덮개 · 문구)
//
// 감독(상태 기계)을 시계를 손으로 넘기며 화면 없이 몬다(autoSchedule = false + advance — 앱에서 감독이 스스로 깨어 부르는 바로 그 함수).
// 돈이 걸린 규칙을 잰다: 모자라면 pull 을 안 부른다 · 한 판에 한 번 · 실패는 공개 없이 처음으로 · [한 번 더] 는 공개가 자리 잡은 뒤에만 ·
// 안 보이는 기계는 저절로 돌지 않는다 · 황금 · 동작 줄이기.
package com.yehsung.aingcheck.ui.gacha.machine

import com.yehsung.aingcheck.core.rules.gacha.GachaPullResult
import com.yehsung.aingcheck.core.rules.gacha.GachaText
import com.yehsung.aingcheck.core.stores.me.MeGachaReveal
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

@OptIn(ExperimentalCoroutinesApi::class)
class GachaMachineDirectorTest {
    private class Gate {
        var calls = 0
        private var pending: CompletableDeferred<GachaRevealOutcome>? = null
        suspend fun pull(): GachaRevealOutcome {
            calls += 1
            val d = CompletableDeferred<GachaRevealOutcome>()
            pending = d
            return d.await()
        }
        fun succeed(o: GachaRevealOutcome) { pending?.complete(o); pending = null }
        fun fail(e: Throwable) { pending?.completeExceptionally(e); pending = null }
        val isWaiting: Boolean get() = pending != null
    }

    private class Rig(val scope: TestScope, val d: GachaMachineDirector, val gate: Gate, val haptics: MutableList<GachaMachineHapticEvent>, var againCalls: Int = 0) {
        var now = 1_000.0
        fun advance(s: Double) { now += s }
        fun env(
            balance: Long = 500, reduceMotion: Boolean = false, blockedReason: String? = null, againEnabled: Boolean = true,
            teaseChance: Double = 0.0, isActive: Boolean = true,
        ) = GachaMachineEnv(
            balance = balance, cost = 50, shards = 3, art = GachaMachineArt.Vector, teaseChance = teaseChance,
            haptics = { haptics += it }, pull = { gate.pull() }, onAgain = { againCalls += 1 },
            blockedReason = blockedReason, againEnabled = againEnabled, isActive = isActive, reduceMotion = reduceMotion,
        )
    }

    private fun TestScope.rig(
        balance: Long = 500, reduceMotion: Boolean = false, blockedReason: String? = null, againEnabled: Boolean = true,
        teaseChance: Double = 0.0, dice: Double = 0.5,
    ): Rig {
        val holder = arrayOfNulls<Rig>(1)
        val d = GachaMachineDirector(clock = { holder[0]?.now ?: 1_000.0 }, scope = backgroundScope, seedSource = { 0x5EEDuL }, random = { dice })
        d.autoSchedule = false
        val r = Rig(this, d, Gate(), mutableListOf())
        holder[0] = r
        d.update(r.env(balance, reduceMotion, blockedReason, againEnabled, teaseChance))
        return r
    }

    private val new = GachaRevealOutcome("fox", "여우", GachaRevealKind.New, shardCount = 3)
    private val dup = GachaRevealOutcome("squirrel", "다람쥐", GachaRevealKind.Duplicate, shardCount = 4)
    private val gold = GachaRevealOutcome("aing_gold", "황금 아잉이", GachaRevealKind.Gold, shardCount = 3)

    /** 손잡이 클릭(자동 회전) → 한 바퀴 끝 → 커밋(pull 부름). */
    private fun Rig.turn() {
        d.autoTurn(now)
        advance(d.autoTurnDuration)
        d.advance(now)
        scope.runCurrent()
    }

    private fun Rig.resolve(o: GachaRevealOutcome) {
        scope.runCurrent()
        assertTrue(gate.isWaiting, "전제: pull 이 떠 있다")
        gate.succeed(o)
        scope.runCurrent()
    }

    private fun Rig.reject(e: Throwable) {
        scope.runCurrent()
        gate.fail(e)
        scope.runCurrent()
    }

    private fun Rig.toTapping() {
        val ds = d.dropStart ?: fail("낙하가 없다")
        now = maxOf(now, ds + d.drop.total + 0.01)
        d.advance(now)
    }

    private fun Rig.tapThree() {
        repeat(3) {
            d.press(now)
            advance(0.2)
        }
    }

    // MARK: 돈이 걸린 규칙

    @Test
    fun refusesWhenShortWithoutPulling() = runTest {
        val r = rig(balance = 49)
        r.d.autoTurn(r.now)
        assertNull(r.d.autoTurnStart)
        r.d.commit(r.now)
        r.d.dragChanged(GLayout.knobCenter.copy(x = GLayout.knobCenter.x + 30), androidx.compose.ui.geometry.Offset(10f, 0f))
        r.d.dragEnded()
        r.advance(2.0)
        r.d.advance(r.now)
        runCurrent()
        assertEquals(0, r.gate.calls)
        assertEquals(0, r.d.pullCount)
        assertNull(r.d.commitTime)
        assertNotNull(r.d.refuseTime)
        assertTrue(GachaMachineHapticEvent.Refuse in r.haptics)
        assertEquals(GPhase.Idle, r.d.phase(r.now))
    }

    @Test
    fun refusesWhenBlocked() = runTest {
        val r = rig(balance = 5000, blockedReason = GachaText.needsUpdate)
        r.d.autoTurn(r.now)
        r.advance(1.0)
        r.d.advance(r.now)
        r.d.commit(r.now)
        runCurrent()
        assertEquals(0, r.gate.calls)
        assertNull(r.d.commitTime)
    }

    @Test
    fun onePullPerTurn() = runTest {
        val r = rig()
        r.turn()
        assertEquals(1, r.gate.calls)
        assertTrue(r.d.pullInFlight)
        // 연타 · 다시 끌기 · 커밋 직접 호출 · [한 번 더]
        r.d.autoTurn(r.now)
        r.d.commit(r.now)
        r.d.dragChanged(GLayout.knobCenter.copy(x = GLayout.knobCenter.x + 30), androidx.compose.ui.geometry.Offset(10f, 0f))
        r.d.again(r.now)
        r.advance(1.0)
        r.d.advance(r.now)
        runCurrent()
        assertEquals(1, r.gate.calls)
        assertEquals(1, r.d.pullCount)
        r.resolve(new)
        assertFalse(r.d.pullInFlight)
        assertEquals(new, r.d.result)
        assertEquals(1, r.gate.calls)
    }

    @Test
    fun failureResetsWithoutReveal() = runTest {
        val r = rig()
        r.turn()
        r.advance(0.3)
        r.reject(GachaRevealFailure(GachaText.unavailable))
        assertEquals(GachaText.unavailable, r.d.failText)
        assertNull(r.d.result)
        assertNull(r.d.dropStart)
        assertIs<GPhase.Failed>(r.d.phase(r.now))
        assertEquals(GachaMachineHapticEvent.Refuse, r.haptics.last())
        r.d.autoTurn(r.now)
        assertNull(r.d.autoTurnStart, "실패 중엔 손잡이가 안 돈다")
        var step = 0.0
        while (step <= 2.3) {
            if (r.d.phase(r.now + step) is GPhase.Reveal) fail("실패한 뽑기를 공개했다 at $step")
            step += 0.1
        }
        r.advance(GTiming.failHold + 0.01)
        r.d.advance(r.now)
        assertEquals(GPhase.Idle, r.d.phase(r.now))
        assertNull(r.d.commitTime)
        assertTrue(r.d.knobAngle(r.now) < 1)
        r.turn()
        assertEquals(2, r.gate.calls)
    }

    @Test
    fun unknownFailureUsesGenericLine() = runTest {
        val r = rig()
        r.turn()
        r.reject(IllegalStateException("x"))
        assertEquals(GachaText.pullFailed, r.d.failText)
        assertFalse("그대로" in r.d.failText)
    }

    @Test
    fun staleResultIsDropped() = runTest {
        val r = rig()
        r.turn()
        r.d.resetPull(r.now)
        r.resolve(gold)
        assertNull(r.d.result)
        assertEquals(GPhase.Idle, r.d.phase(r.now))
    }

    @Test
    fun againOnlyAfterRevealSettles() = runTest {
        val r = rig()
        r.turn()
        r.advance(0.3)
        r.resolve(new)
        r.toTapping()
        assertEquals(GPhase.Tapping(0), r.d.phase(r.now))
        r.d.again(r.now)
        assertEquals(0, r.againCalls)
        r.tapThree()
        val ph = r.d.phase(r.now) as? GPhase.Reveal ?: fail("공개가 아니다: ${r.d.phase(r.now)}")
        assertTrue(ph.t < GTiming.buttonsAt(GachaRevealKind.New))
        r.d.again(r.now)
        assertEquals(0, r.againCalls)
        assertNull(r.d.againAt)
        assertFalse(r.d.revealSettled(r.now))
        r.advance(GTiming.buttonsAt(GachaRevealKind.New))
        assertTrue(r.d.revealSettled(r.now))
        r.d.again(r.now)
        r.d.again(r.now) // 연타
        assertEquals(1, r.againCalls)
        assertNotNull(r.d.againAt)
        assertEquals(GPhase.Idle, r.d.phase(r.now))
        assertEquals(new, r.d.outgoing)
        r.advance(GTiming.againDelay)
        r.d.advance(r.now)
        assertNotNull(r.d.autoTurnStart)
        r.d.again(r.now)
        r.advance(r.d.autoTurnDuration)
        r.d.advance(r.now)
        runCurrent()
        assertEquals(2, r.gate.calls)
    }

    @Test
    fun againDisabledByHost() = runTest {
        val r = rig(againEnabled = false)
        r.turn()
        r.resolve(new)
        r.toTapping()
        r.tapThree()
        r.advance(3.0)
        r.d.again(r.now)
        assertEquals(0, r.againCalls)
        assertNull(r.d.againAt)
        assertEquals(1, r.gate.calls)
    }

    @Test
    fun goldPath() = runTest {
        val r = rig(teaseChance = 0.0)
        r.turn()
        r.resolve(gold)
        assertTrue(r.d.isGold)
        assertFalse(r.d.tease)
        assertEquals(GDropTimes.gold, r.d.drop)
        r.toTapping()
        repeat(3) { r.d.press(r.now); r.advance(0.15) }
        r.advance(-0.15)
        assertIs<GPhase.Building>(r.d.phase(r.now))
        val old = r.d.beats(r.now)
        r.advance(GTiming.goldBuild + 0.01)
        val newBeats = r.d.beats(r.now)
        r.d.emitBeats(old, newBeats, r.now)
        assertIs<GPhase.Reveal>(r.d.phase(r.now))
        assertTrue(GachaMachineHapticEvent.GoldReveal in r.haptics)
        assertEquals(GTiming.buttonsAt(GachaRevealKind.Gold), r.d.buttonsAt(GachaRevealKind.Gold))
    }

    @Test
    fun goldTeaseFollowsTheDice() = runTest {
        // 기준선: 주사위가 확률 밖이면 반전이 없다(황금 시간표). 주사위 0 · 확률 1 이면 반전(평범한 캡슐 시간표 → 둘째 톡에 황금).
        val plain = rig(teaseChance = 0.3, dice = 0.9)
        plain.turn()
        plain.resolve(gold)
        assertFalse(plain.d.tease)
        assertEquals(GDropTimes.gold, plain.d.drop)

        val r = rig(teaseChance = 1.0, dice = 0.0)
        r.turn()
        r.resolve(gold)
        assertTrue(r.d.tease)
        assertEquals(GDropTimes.normal, r.d.drop)
        r.toTapping()
        r.d.press(r.now); r.advance(0.2); r.d.press(r.now)
        assertTrue(GachaMachineHapticEvent.GoldFlip in r.haptics)
    }

    @Test
    fun reduceMotionPath() = runTest {
        val r = rig(reduceMotion = true, teaseChance = 1.0, dice = 0.0)
        r.d.autoTurn(r.now)
        assertTrue(r.d.autoTurnDuration <= 0.45)
        r.advance(r.d.autoTurnDuration)
        r.d.advance(r.now)
        runCurrent()
        assertTrue(r.d.reduced)
        r.resolve(dup)
        assertFalse(r.d.tease, "반전 연출도 없다")
        assertEquals(GDropTimes.reduced, r.d.drop)
        val ds = r.d.dropStart ?: fail("낙하가 없다")
        assertEquals(ds + GDropTimes.reduced.total, r.d.burstTime)
        var step = 0.0
        while (step <= GDropTimes.reduced.total + 2) {
            if (r.d.phase(ds + step) is GPhase.Tapping) fail("동작 줄이기에서 톡톡 단계 at $step")
            assertEquals(0.0, r.d.ambient(ds + step))
            step += 0.05
        }
        r.now = ds + GDropTimes.reduced.total + 0.01
        assertIs<GPhase.Reveal>(r.d.phase(r.now))
        assertEquals("이미 있는 친구예요. 다람쥐 조각 +1", GachaMachineText.announcement(dup))
        r.advance(GTiming.Reduced.buttonsAt(GachaRevealKind.Duplicate))
        assertTrue(r.d.revealSettled(r.now))
        assertNotNull(r.d.quietAt(r.now))
    }

    @Test
    fun idleGoesQuiet() = runTest {
        val r = rig()
        r.d.touched(r.now)
        assertTrue(r.d.framesWanted)
        assertEquals(1.0, r.d.ambient(r.now))
        val q = r.d.quietAt(r.now) ?: fail("멎는 때가 없다")
        assertTrue(abs(q - r.now - (GTiming.ambientGrace + GTiming.ambientFade + 0.05)) < 0.001)
        r.now = q
        r.d.advance(r.now)
        assertFalse(r.d.framesWanted)
        assertEquals(0.0, r.d.ambient(r.now))
        assertNull(r.d.nextWake(r.now))
        r.d.autoTurn(r.now)
        assertTrue(r.d.framesWanted)
        assertNull(r.d.quietAt(r.now))
    }

    @Test
    fun beatsEmitHaptics() = runTest {
        val r = rig()
        r.d.autoTurn(r.now)
        var old = r.d.beats(r.now)
        repeat(20) {
            r.advance(r.d.autoTurnDuration / 20)
            val b = r.d.beats(r.now)
            r.d.emitBeats(old, b, r.now)
            old = b
        }
        assertEquals(7, r.haptics.count { it == GachaMachineHapticEvent.Ratchet }, "45° 마다, 마지막(360°)은 커밋 쿵이 대신한다")
        r.d.advance(r.now)
        runCurrent()
        r.resolve(dup)
        old = r.d.beats(r.now)
        r.toTapping()
        var b = r.d.beats(r.now)
        r.d.emitBeats(old, b, r.now)
        assertTrue(GachaMachineHapticEvent.Land in r.haptics)
        old = b
        r.tapThree()
        b = r.d.beats(r.now)
        r.d.emitBeats(old, b, r.now)
        assertEquals(1, r.haptics.count { it == GachaMachineHapticEvent.Reveal })
        old = b
        r.advance(GTiming.dupFly1 + 0.1)
        b = r.d.beats(r.now)
        r.d.emitBeats(old, b, r.now)
        assertEquals(1, r.haptics.count { it == GachaMachineHapticEvent.Shard })
    }

    // MARK: 안 보일 때 돈이 안 나간다

    @Test
    fun hiddenAutoTurnDoesNotPull() = runTest {
        // 기준선: 보이는 채로 자동 회전이 끝나면 커밋한다(pull 한 번).
        val seen = rig()
        seen.d.autoTurn(seen.now)
        seen.advance(0.2)
        seen.advance(seen.d.autoTurnDuration)
        seen.d.advance(seen.now)
        runCurrent()
        assertEquals(1, seen.gate.calls, "기준선: 보이는 채로 다 돈 손잡이가 pull 을 안 불렀다")

        val r = rig()
        r.d.autoTurn(r.now)
        r.advance(0.2)
        r.d.update(r.env(isActive = false))
        r.advance(1.0)
        r.d.advance(r.now)
        runCurrent()
        assertEquals(0, r.gate.calls, "안 보이는 기계가 손잡이를 마저 돌려 pull 을 불렀다")
        assertEquals(0, r.d.pullCount)
        assertNull(r.d.commitTime)
        assertNull(r.d.autoTurnStart)
        r.advance(2.0)
        assertTrue(r.d.knobAngle(r.now) < 1, "손잡이가 처음 자리로 안 돌아왔다(${r.d.knobAngle(r.now)})")
        r.d.update(r.env(isActive = true))
        r.turn()
        assertEquals(1, r.gate.calls)
    }

    @Test
    fun hiddenAgainDoesNotPull() = runTest {
        val r = rig()
        r.turn()
        r.resolve(new)
        r.toTapping()
        r.tapThree()
        r.advance(GTiming.buttonsAt(GachaRevealKind.New))
        assertTrue(r.d.revealSettled(r.now))
        r.d.again(r.now)
        assertNotNull(r.d.againAt, "전제: [한 번 더] 가 예약됐다")
        r.d.update(r.env(isActive = false))
        r.advance(GTiming.againDelay + 0.01)
        r.d.advance(r.now)
        r.advance(GTiming.autoTurn + 0.01)
        r.d.advance(r.now)
        runCurrent()
        assertEquals(1, r.gate.calls)
        assertNull(r.d.againAt)
        assertNull(r.d.autoTurnStart)
        assertNull(r.d.commitTime)
    }

    @Test
    fun unrevealedTurnTracksWhatTheUserSaw() = runTest {
        val r = rig()
        assertFalse(r.d.hasUnrevealedTurn(r.now))
        r.turn()
        assertTrue(r.d.hasUnrevealedTurn(r.now), "왕복 중인데 못 본 판이 없다고 한다")
        r.resolve(new)
        assertTrue(r.d.hasUnrevealedTurn(r.now))
        r.toTapping()
        assertTrue(r.d.hasUnrevealedTurn(r.now))
        r.tapThree()
        r.advance(GTiming.buttonsAt(GachaRevealKind.New))
        assertFalse(r.d.hasUnrevealedTurn(r.now), "보는 채로 공개가 끝났는데 못 봤다고 한다")
        r.d.update(r.env(isActive = false))
        r.advance(5.0)
        assertFalse(r.d.hasUnrevealedTurn(r.now))

        // 동작 줄이기: 흔들리는 중에 닫으면 안 보이는 동안 공개가 끝난다 → 못 본 판이다.
        val q = rig(reduceMotion = true)
        q.turn()
        q.d.update(q.env(reduceMotion = true, isActive = false))
        q.resolve(dup)
        q.advance(10.0)
        assertTrue(q.d.revealSettled(q.now))
        assertTrue(q.d.hasUnrevealedTurn(q.now), "안 보이는 동안 끝난 공개를 본 것으로 친다")
        q.d.update(q.env(reduceMotion = true, isActive = true))
        assertFalse(q.d.hasUnrevealedTurn(q.now))
    }

    // MARK: 결과 옮기기 · 덮개 · 문구

    @Test
    fun outcomeFromStoreReveal() {
        val dupResult = GachaPullResult("fox", isDuplicate = true, shardsGained = 1, shards = 9, rubyBalance = 10, replayed = false)
        val o = GachaRevealOutcome.of(MeGachaReveal.of(dupResult, "여우", shardsBefore = 2))
        assertEquals(GachaRevealKind.Duplicate, o.kind)
        assertEquals(9, o.shardCountAfter)
        assertEquals(8, o.shardCountBefore)
        val fresh = GachaPullResult("shiba", isDuplicate = false, shardsGained = 0, shards = null, rubyBalance = null, replayed = false)
        val n = GachaRevealOutcome.of(MeGachaReveal.of(fresh, "강아지", shardsBefore = 4))
        assertEquals(GachaRevealKind.New, n.kind)
        assertEquals(4, n.shardCountAfter)
        assertEquals(0, n.shardsGained)
        val goldDup = GachaPullResult("aing_gold", isDuplicate = true, shardsGained = 1, shards = 5, rubyBalance = null, replayed = false)
        val g = GachaRevealOutcome.of(MeGachaReveal.of(goldDup, "황금 아잉이", shardsBefore = 4))
        assertEquals(GachaRevealKind.Gold, g.kind)
        assertTrue(g.isRareDuplicate)
        assertNotNull(GTiming.shardLandAt(g, reduced = false))
        assertTrue("조각 +1" in GachaMachineText.goldSubtitle(g))
        val rainbow = GachaPullResult("aing_rainbow", isDuplicate = false, shardsGained = 0, shards = 2, rubyBalance = null, replayed = false)
        assertEquals(GachaRevealKind.Rainbow, GachaRevealOutcome.of(MeGachaReveal.of(rainbow, "무지개 아잉이", 2)).kind)
    }

    @Test
    fun chuteFlapOpensOnlyForTheCapsule() {
        for ((t, reduced) in listOf(GDropTimes.normal to false, GDropTimes.gold to false, GDropTimes.reduced to true)) {
            if (t.emerge0 > 0.1) assertEquals(0.0, GachaMachineDirector.flapOpen(0.0, t, reduced))
            val mid = (t.emerge0 + 0.09 + t.emerge1 - 0.03) / 2
            assertTrue(GachaMachineDirector.flapOpen(mid, t, reduced) > 0.95)
            assertTrue(abs(GachaMachineDirector.flapOpen(t.total, t, reduced)) < 0.02)
            var minimum = 1.0
            var td = 0.0
            while (td <= t.total) {
                minimum = minOf(minimum, GachaMachineDirector.flapOpen(td, t, reduced))
                td += 0.005
            }
            if (reduced) assertTrue(minimum >= 0) else assertTrue(minimum < 0, "동작 줄이기가 아니면 닫힐 때 살짝 흔들린다")
        }
    }

    @Test
    fun revealTextsAreTheSameForReducedMotion() {
        assertEquals("새 캐릭터! 여우", GachaMachineText.announcement(new))
        assertEquals("황금 아잉이! 아주 드문 친구를 만났어요", GachaMachineText.announcement(gold))
        assertEquals("다람쥐 조각", GachaMachineText.shardLine(dup))
        assertEquals("+1", GachaMachineText.shardGain(dup))
        assertEquals("+1 조각", GachaMachineText.chipGain(dup))
        assertEquals(GachaText.rainbowHeadline, GachaMachineText.title(GachaRevealOutcome("aing_rainbow", "무지개 아잉이", GachaRevealKind.Rainbow)))
    }

    // MARK: 불투명도 봉투는 직선이다(움직임 봉투와 끝점은 같고 사이만 다르다)

    @Test
    fun ambientOpacityEnvelopeIsLinearWhileMotionEnvelopeIsSmooth() = runTest {
        val r = rig()
        r.d.touched(r.now)
        val start = r.now + GTiming.ambientGrace
        val end = start + GTiming.ambientFade
        // 끝점이 같다.
        assertTrue(abs(r.d.ambient(start) - r.d.ambientLinear(start)) < 1e-9)
        assertTrue(abs(r.d.ambient(end) - r.d.ambientLinear(end)) < 1e-9)
        // 사이: 직선은 1/4 지점에서 0.75, smoothstep 은 0.84375 — 둘이 다르다(같으면 불투명도가 이징을 탄 것이다).
        val quarter = start + GTiming.ambientFade / 4
        assertTrue(abs(r.d.ambientLinear(quarter) - 0.75) < 1e-9, "직선 봉투 1/4 지점 = ${r.d.ambientLinear(quarter)}")
        assertTrue(abs(r.d.ambient(quarter) - 0.84375) < 1e-9, "움직임 봉투(smooth) 1/4 지점 = ${r.d.ambient(quarter)}")
    }
}
