// W2-g2 소비 몸 시험 — Swift WorkTimerStorePoke.swift 581-665 · 686-840 · SupabaseWorkServiceMacOnly.swift 864-904. P6 ★P7 P8 P12 P13.
package com.yehsung.aingcheck.feature.desktop.poke

import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.PokeKind
import com.yehsung.aingcheck.core.wire.models.TakenPokeRow
import com.yehsung.aingcheck.feature.desktop.poke.net.takePokes
import com.yehsung.aingcheck.feature.desktop.socialapi.DrainOutcome
import com.yehsung.aingcheck.feature.desktop.socialapi.QueuedBubbleMessage
import com.yehsung.aingcheck.testkit.mock.MockRouter
import com.yehsung.aingcheck.testkit.mock.StubResponse
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun drainer(
    scope: CoroutineScope,
    host: FakeSessionHost = FakeSessionHost(pokeService(MockRouter())),
    sink: RecordingPokeSink = RecordingPokeSink(),
    rows: RecordingRowsSink = RecordingRowsSink(),
    bubbles: DesktopMessageBubbleQueue = DesktopMessageBubbleQueue(),
    subscription: FakeSubscription = FakeSubscription(),
    alreadyRead: (QueuedBubbleMessage) -> Boolean = { false },
    take: suspend (String) -> List<TakenPokeRow>,
) = DesktopPokeDrainer(host, scope, { T0 }, sink, rows, bubbles, subscription, isAlreadyReadForBubble = alreadyRead, takePokesCall = take)

@OptIn(ExperimentalCoroutinesApi::class)
class PokeDrainSerialTest {
    /** ★P7: drain 이 도는 중 신호 2건 → take_pokes 정확히 2회(첫 회 + 트레일링 한 번으로 접힘). */
    @Test
    fun twoSignalsDuringDrainMeansExactlyTwoCalls() = runTest {
        val release = Channel<Unit>(Channel.UNLIMITED)
        var calls = 0
        val d = drainer(backgroundScope) { calls++; release.receive(); emptyList() }
        d.requestDrain()
        runCurrent()
        assertEquals(1, calls)
        d.requestDrain()
        d.requestDrain()
        runCurrent()
        assertEquals(1, calls, "돌고 있으면 새로 쏘지 않는다")
        release.send(Unit)
        runCurrent()
        assertEquals(2, calls, "트레일링 한 번")
        release.send(Unit)
        runCurrent()
        assertEquals(2, calls, "정확히 2회")
        assertNull(d.inFlight, "끝나면 비운다(defer 꼴 금지 — 다음 요청이 자기에게 막히지 않는다)")
        d.requestDrain()
        runCurrent()
        assertEquals(3, calls, "다음 신호는 새로 돈다")
        release.send(Unit)
        runCurrent()
        assertNull(d.inFlight)
    }

    @Test
    fun drainOnceCountsRowsBeforeFreshnessAndSplitsKinds() = runTest {
        val sink = RecordingPokeSink()
        val rowsSink = RecordingRowsSink()
        val bubbles = DesktopMessageBubbleQueue()
        val rows = listOf(
            row("p-new", 5, "normal"), row("p-old", 3601, "normal"), row("u-late", 200, "ultra"),
            row("m-1", 10, "message", " 밥? "), row("m-read", 20, "message", "읽음"), row("m-old", 301, "message", "늦음"),
        )
        val d = drainer(backgroundScope, sink = sink, rows = rowsSink, bubbles = bubbles, alreadyRead = { it.id == "m-read" }) { rows }
        val outcome = d.drainOnce()
        assertEquals(DrainOutcome.Ok(6), outcome, "P6 count 는 신선도로 거르기 전 행 수")
        assertEquals(listOf(listOf("p-new", "u-late")), sink.batches.map { b -> b.map { it.id } })
        assertEquals(PokeKind.normal, sink.batches.single()[1].kind, "120초 넘은 ultra 는 강등된 채 싱크로")
        assertEquals(listOf("m-1"), bubbles.queue.value.map { it.id }, "메시지는 말풍선 큐로 · 읽은 것·5분 넘은 것 제외")
        assertEquals("밥?", bubbles.current?.body)
        assertEquals(1, rowsSink.inserted.size)
        assertEquals(1, rowsSink.messages.size)
    }

    @Test
    fun generationChangeIsFailureAndNoSessionIsFailure() = runTest {
        val host = FakeSessionHost(pokeService(MockRouter()))
        val sink = RecordingPokeSink()
        val d = drainer(backgroundScope, host = host, sink = sink) { host.generation++; listOf(row("p", 1, "normal")) }
        assertTrue(d.drainOnce() is DrainOutcome.Failed, "세대가 바뀌었으면 .failed")
        assertTrue(sink.batches.isEmpty(), "앞 계정의 찌르기를 새 계정 화면에 띄우지 않는다")
        host.current = null
        assertEquals(DrainOutcome.Failed("세션 없음"), d.drainOnce())
        val failing = drainer(backgroundScope) { throw IllegalStateException("offline") }
        assertTrue(failing.drainOnce() is DrainOutcome.Failed)
    }
}

class FlushOnUserStopTest {
    @Test
    fun stopIsOneTerminatingIsZeroNoSessionIsNull() = runBlocking {
        var calls = 0
        val host = FakeSessionHost(pokeService(MockRouter()))
        val d = drainer(this, host = host) { calls++; emptyList() }
        d.flushOnUserStop(isTerminating = false)!!.join()
        assertEquals(1, calls, "사용자가 누른 stop = 꼬리 1회")
        assertNull(d.flushOnUserStop(isTerminating = true), "종료 시퀀스 = 0")
        assertEquals(1, calls)
        host.current = null
        assertNull(d.flushOnUserStop(isTerminating = false), "세션이 없으면 null")
        assertEquals(1, calls)
    }

    @Test
    fun subscribedRingDoesNotSuppressTailWhilePollingRunsAlongside() = runBlocking {
        var calls = 0
        val d = drainer(this, subscription = FakeSubscription(subscribed = true)) { calls++; emptyList() }
        assertNotNull(d.flushOnUserStop(isTerminating = false)).join()
        assertEquals(1, calls, "P11 억제가 없으므로 구독 중에도 꼬리 회수")
    }
}

class TakePokesFallbackTest {
    private val ok = """[{"id":"p-1","from_user":"peer-1","from_display_name":"보낸이","created_epoch":1790000000,"kind":"normal"}]"""

    /** P12: PGRST202 일 때 `{}` 재호출 1회, 다음 호출은 다시 새 모양(캐시 없음). */
    @Test
    fun schemaMissingRetriesOnceWithEmptyBodyAndDoesNotCache() = runBlocking {
        val router = MockRouter().rpc("take_pokes", StubResponse.missingFunction("take_pokes"), StubResponse.Json(ok), StubResponse.Json("[]"))
        val service = pokeService(router)
        assertEquals(1, service.takePokes("token-1").size)
        assertEquals(0, service.takePokes("token-1").size)
        assertEquals(listOf("""{"p_message_capable":true}""", "{}", """{"p_message_capable":true}"""), router.requests.map { it.bodyText })
        router.assertAllRouted()
    }

    @Test
    fun otherErrorsDoNotRetry() = runBlocking {
        val router = MockRouter().rpc("take_pokes", StubResponse.Json("""{"message":"boom"}""", status = 500))
        assertFailsWith<SupabaseWorkServiceError> { pokeService(router).takePokes("token-1") }
        assertEquals(1, router.requests.size)
    }

    @Test
    fun drainerOverRealServiceDeliversToSink() = runBlocking {
        val router = MockRouter().rpc("take_pokes", StubResponse.Json(ok))
        val host = FakeSessionHost(pokeService(router))
        val sink = RecordingPokeSink()
        val d = DesktopPokeDrainer(host, this, { T0 }, sink, NoOpConsumedRowsSink, DesktopMessageBubbleQueue(), FakeSubscription())
        assertEquals(DrainOutcome.Ok(1), d.drainOnce())
        assertEquals("p-1", sink.batches.single().single().id)
        assertEquals("Bearer token-1", router.requests.single().headers["Authorization"]?.single())
    }
}

class MessageBubbleQueueTest {
    private fun msg(id: String, age: Double) = QueuedBubbleMessage(id, "보낸이", "본문", T0.addingTimeInterval(-age))

    @Test
    fun limit20DropsOldestAndDedupes() {
        val q = DesktopMessageBubbleQueue()
        assertTrue(q.append((1..25).map { msg("m$it", 0.0) }))
        assertEquals(DesktopPokeRules.MESSAGE_QUEUE_LIMIT, q.queue.value.size)
        assertEquals("m6", q.current?.id, "상한을 넘으면 오래된 쪽부터")
        assertFalse(q.append(listOf(msg("m25", 0.0))), "같은 id 는 무시")
        assertEquals(19, q.waitingCount)
        assertFalse(q.append(emptyList()))
    }

    @Test
    fun expiresAt300SecondsNotBefore() {
        val q = DesktopMessageBubbleQueue()
        q.append(listOf(msg("edge", 300.0), msg("late", 301.0)))
        q.expireStale(T0)
        assertEquals(listOf("edge"), q.queue.value.map { it.id }, "5분(≤300) 은 남고 301 은 버린다")
    }

    @Test
    fun consumeMovesToLastShownWhichExpiresAfterAnHour() {
        val q = DesktopMessageBubbleQueue()
        q.append(listOf(msg("a", 10.0)))
        q.consumeCurrent()
        assertNull(q.current)
        assertEquals("a", q.lastShown.value?.id)
        q.consumeCurrent()
        assertEquals("a", q.lastShown.value?.id, "빈 큐에서 consume 이 한 번 더 와도 직전 표시분 유지")
        q.expireLastShown(T0.addingTimeInterval(3590.0))
        assertEquals("a", q.lastShown.value?.id, "나이 3600 = 아직")
        q.expireLastShown(T0.addingTimeInterval(3591.0))
        assertNull(q.lastShown.value, "1시간 넘으면 버린다(5분과 다른 상수)")
    }

    @Test
    fun resetClearsBoth() {
        val q = DesktopMessageBubbleQueue()
        q.append(listOf(msg("a", 1.0), msg("b", 1.0)))
        q.consumeCurrent()
        q.reset()
        assertNull(q.current)
        assertNull(q.lastShown.value)
    }

    /** P13: 메시지 쿨타임 미러는 되살리지 않는다 — 큐 클래스에 cooldown 칸이 없다. */
    @Test
    fun noMessageCooldownMirror() {
        val names = DesktopMessageBubbleQueue::class.java.declaredMethods.map { it.name.lowercase() } +
            DesktopMessageBubbleQueue::class.java.declaredFields.map { it.name.lowercase() }
        assertTrue(names.none { "cooldown" in it }, names.toString())
        assertEquals(SwiftDate(NOW_EPOCH.toDouble()), T0)
    }
}
