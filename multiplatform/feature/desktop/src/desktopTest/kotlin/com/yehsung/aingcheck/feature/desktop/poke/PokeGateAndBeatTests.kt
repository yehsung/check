// W2-g2 게이트·박자 시험 — Swift WorkTimerStorePoke.swift 375-475 · 539-575. ★P4 ★P11 · P5 · P10.
package com.yehsung.aingcheck.feature.desktop.poke

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.socialapi.DrainOutcome
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeConsumeFacts
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeConsumeGate
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeDrainer
import com.yehsung.aingcheck.feature.desktop.socialapi.QueuedBubbleMessage
import com.yehsung.aingcheck.feature.desktop.work.PokeFactsSource
import com.yehsung.aingcheck.testkit.mock.MockRouter
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 순서를 적는 가짜 drainer. */
internal class CountingDrainer(private val log: MutableList<String>? = null) : PokeDrainer {
    var drains = 0
    override suspend fun drainOnce(): DrainOutcome {
        drains++
        log?.add("take")
        return DrainOutcome.Ok(0)
    }
    override fun requestDrain() {}
    override fun flushOnUserStop(isTerminating: Boolean): Job? = null
}

class PokeConsumeGateTest {
    private data class Row(val name: String, val facts: PokeConsumeFacts, val flagOff: Boolean, val flagOn: Boolean)

    /** ★P4·P5 진리표 — 흡수 깃발 끔·켬 × 여섯 사실 = 12행. 700초 행이 900→600 변형을, '흡수 아님' 행이 `!adopted` 삭제를 잡는다. */
    private val table = listOf(
        Row("로컬 세션 닫힘(isWorking 아님)", facts(local = false, adopted = false), flagOff = false, flagOn = false),
        Row("흡수 아님 · 로컬 열림", facts(adopted = false), flagOff = true, flagOn = true),
        Row("흡수 · 셋 다 섬(입력 700초 — 서버 600 밖, 클라 900 안)", facts(), flagOff = false, flagOn = true),
        Row("흡수 · 기기 주장 빈 배열(판정 불가)", facts(claims = emptyList()), flagOff = false, flagOn = false),
        Row("흡수 · 남의 기기가 이 세션을 주장", facts(claims = listOf("mac:other" to "s-1")), flagOff = false, flagOn = false),
        Row("흡수 · 입력 901초", facts(inputAgo = 901.0), flagOff = false, flagOn = false),
    )

    @Test
    fun truthTable12Rows() {
        var rows = 0
        for (row in table) {
            for (flag in listOf(false, true)) {
                val gate = DesktopPokeConsumeGate(PokeFactsSource { row.facts }, DesktopAppConfig(adoptedPokeConsume = flag))
                assertEquals(if (flag) row.flagOn else row.flagOff, gate.mayConsume(T0), "${row.name} · 깃발=$flag")
                rows++
            }
        }
        assertEquals(12, rows)
    }

    @Test
    fun adoptedBranchUnknownsAreFalse() {
        val on = { f: PokeConsumeFacts -> DesktopPokeConsumeGate.decide(f, T0, adoptedConsumeEnabled = true) }
        assertFalse(on(facts(claims = null)), "주장을 못 읽음(null) = 판정 불가")
        assertFalse(on(facts(device = null)), "이 기기 id 가 null 이면 흡수 소비 금지")
        assertFalse(on(facts(ownOpen = "s-2")), "서버가 연 행의 세션이 흡수한 세션이 아니다")
        assertFalse(on(facts(canonical = null)), "세션 id 없음")
        assertFalse(on(facts(inputAgo = null)), "입력 기록 없음")
        assertTrue(on(facts(inputAgo = 900.0)), "경계 900초 = 안(≤)")
        assertTrue(on(facts(claims = listOf("" to "s-1", "win:me" to "s-1"))), "빈 deviceID 주장은 세지 않는다")
    }

    @Test
    fun windowsDefaultConfigNeverConsumesAdopted() {
        assertFalse(DesktopAppConfig().adoptedPokeConsume)
        assertFalse(DesktopPokeConsumeGate(PokeFactsSource { facts() }).mayConsume(T0), "기본 깃발 꺼짐 → 흡수 가지는 언제나 거짓")
    }

    @Test
    fun readsLatestFactsEveryCall() {
        var current = facts(local = false)
        val gate = DesktopPokeConsumeGate(PokeFactsSource { current })
        assertFalse(gate.mayConsume(T0))
        current = facts(adopted = false)
        assertTrue(gate.mayConsume(T0))
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class PokeBeatOrderTest {
    private val open = PokeConsumeGate { true }

    @Test
    fun notWorkingMeansZeroTakePokes() = runBlocking {
        val router = MockRouter()
        val host = FakeSessionHost(pokeService(router))
        val bubbles = DesktopMessageBubbleQueue()
        val drainer = DesktopPokeDrainer(host, this, { T0 }, RecordingPokeSink(), RecordingRowsSink(), bubbles, FakeSubscription())
        val gate = DesktopPokeConsumeGate(PokeFactsSource { facts(local = false, adopted = false) })
        val poller = DesktopPokePoller(host, { T0 }, gate, drainer, FakeSubscription(), bubbles)
        repeat(3) { poller.tick(T0) }
        assertEquals(0, router.requests.size, "비근무 = take_pokes 0건")
        router.assertAllRouted()
    }

    @Test
    fun signedOutTickDoesNothing() = runBlocking {
        val host = FakeSessionHost(pokeService(MockRouter())).apply { current = null }
        val log = mutableListOf<String>()
        val hooks = PokeBeatHooks(focusExpiry = { log += "focus" }, walletPeriodic = { log += "wallet" })
        DesktopPokePoller(host, { T0 }, open, CountingDrainer(log), FakeSubscription(), DesktopMessageBubbleQueue(), hooks).tick(T0)
        assertEquals(emptyList(), log)
    }

    /** P10: 메시지 만료 → 마지막 표시 만료 → 집중 만료 → 지갑 periodic → 다른 갈래 훅 → 마지막에 게이트·take_pokes. */
    @Test
    fun beatOrderIsP10() = runBlocking {
        val log = mutableListOf<String>()
        val bubbles = DesktopMessageBubbleQueue()
        bubbles.append(listOf(QueuedBubbleMessage("old-shown", "a", "x", T0.addingTimeInterval(-3601.0))))
        bubbles.consumeCurrent()
        bubbles.append(listOf(QueuedBubbleMessage("stale", "a", "x", T0.addingTimeInterval(-301.0))))
        val hooks = PokeBeatHooks(
            focusExpiry = {
                log += "focus"
                assertNull(bubbles.current, "메시지 만료가 집중 만료보다 앞")
                assertNull(bubbles.lastShown.value, "마지막 표시 만료가 집중 만료보다 앞")
            },
            walletPeriodic = { log += "wallet" },
            others = listOf({ _ -> log += "weekly" }, { _ -> log += "cake" }),
        )
        val host = FakeSessionHost(pokeService(MockRouter()))
        DesktopPokePoller(host, { T0 }, open, CountingDrainer(log), FakeSubscription(), bubbles, hooks).tick(T0)
        assertEquals(listOf("focus", "wallet", "weekly", "cake", "take"), log)
    }

    @Test
    fun startIssuesNoRequestImmediately() = runTest {
        val drainer = CountingDrainer()
        val host = FakeSessionHost(pokeService(MockRouter()))
        val poller = DesktopPokePoller(host, { T0 }, open, drainer, FakeSubscription(), DesktopMessageBubbleQueue())
        poller.start(backgroundScope)
        poller.start(backgroundScope)
        runCurrent()
        assertEquals(0, drainer.drains, "첫 동작은 sleep — 시작 즉시 요청 0건")
        advanceTimeBy(14_999)
        runCurrent()
        assertEquals(0, drainer.drains)
        advanceTimeBy(1)
        runCurrent()
        assertEquals(1, drainer.drains, "15초 뒤 1회(멱등 start — 루프는 하나)")
        poller.stop()
        advanceTimeBy(60_000)
        runCurrent()
        assertEquals(1, drainer.drains, "stop 뒤 0")
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class PokeIntervalTest {
    @Test
    fun intervalAndPauseDeriveFromOneSignal() {
        assertEquals(60.0, DesktopPokeRules.pollIntervalSeconds(ringIsSubscribed = true))
        assertEquals(15.0, DesktopPokeRules.pollIntervalSeconds(ringIsSubscribed = false))
        assertFalse(DesktopPokeRules.pollingIsPausedByRealtime(ringIsSubscribed = true), "★P11 폴링은 링과 함께 돈다 — 억제는 언제나 거짓")
        assertFalse(DesktopPokeRules.pollingIsPausedByRealtime(ringIsSubscribed = false))
        assertTrue(DesktopPokeRules.POLLING_KEEPS_RUNNING_ALONGSIDE_REALTIME)
    }

    @Test
    fun subscribedRingStillPollsAndTakes() = runBlocking {
        val drainer = CountingDrainer()
        val host = FakeSessionHost(pokeService(MockRouter()))
        DesktopPokePoller(host, { T0 }, { true }, drainer, FakeSubscription(subscribed = true), DesktopMessageBubbleQueue()).tick(T0)
        assertEquals(1, drainer.drains, "구독 중에도 take_pokes 는 나간다(억제 없음)")
    }

    /** 주기는 매 반복 **앞**에서 읽는다 — 전이는 지금 자는 구간이 끝난 다음 tick 부터. */
    @Test
    fun intervalIsReadAtTheFrontOfEachIteration() = runTest {
        val drainer = CountingDrainer()
        val subscription = FakeSubscription(subscribed = false)
        val host = FakeSessionHost(pokeService(MockRouter()))
        DesktopPokePoller(host, { T0 }, { true }, drainer, subscription, DesktopMessageBubbleQueue()).start(backgroundScope)
        advanceTimeBy(15_001)
        assertEquals(1, drainer.drains)
        subscription.subscribed = true // 이미 15초 잠에 들어갔다 → 그 잠은 15초 그대로
        advanceTimeBy(15_000)
        assertEquals(2, drainer.drains, "구독 전이 직전에 시작한 잠은 15초")
        advanceTimeBy(59_000)
        assertEquals(2, drainer.drains, "다음 반복부터 60초")
        subscription.subscribed = false // 자는 도중 깨워 재계산하지 않는다
        advanceTimeBy(1_000)
        assertEquals(3, drainer.drains)
        advanceTimeBy(15_000)
        assertEquals(4, drainer.drains, "다시 15초")
    }
}

class PokeSinkRequiredTest {
    @Test
    fun missingSinkMeansNoDrainerAndNoTakePokes() = runBlocking {
        val router = MockRouter()
        val host = FakeSessionHost(pokeService(router))
        val bubbles = DesktopMessageBubbleQueue()
        val noReceived = DesktopPokeWiring.drainerOrNull(host, this, { T0 }, null, NoOpConsumedRowsSink, bubbles, FakeSubscription())
        val noConsumed = DesktopPokeWiring.drainerOrNull(host, this, { T0 }, RecordingPokeSink(), null, bubbles, FakeSubscription())
        assertNull(noReceived, "ReceivedPokeSink 없음 → 조립하지 않는다")
        assertNull(noConsumed, "ConsumedRowsSink 없음 → 조립하지 않는다")
        val poller = DesktopPokePoller(host, { T0 }, { true }, noReceived, FakeSubscription(), bubbles)
        poller.tick(T0)
        assertEquals(0, router.requests.size, "싱크가 없으면 take_pokes 를 부르지 않는다")
        val both = DesktopPokeWiring.drainerOrNull(host, this, { T0 }, RecordingPokeSink(), NoOpConsumedRowsSink, bubbles, FakeSubscription())
        assertTrue(both != null)
    }

    @Test
    fun noOpConsumedSinkCountsZero() {
        assertEquals(0, NoOpConsumedRowsSink.insertConsumedPokes(listOf(row("p", 1, "normal"))))
        NoOpConsumedRowsSink.receiveConsumedMessages(listOf(row("m", 1, "message", "x")), SwiftDate(0.0))
    }
}
