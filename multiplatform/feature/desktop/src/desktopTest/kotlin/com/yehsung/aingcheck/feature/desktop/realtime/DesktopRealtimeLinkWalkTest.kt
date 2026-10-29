// 기존 골든 contract/golden/realtime/link-walk.json(Swift RealtimeWalk, 1만 걸음 + 경계 대본)을 **데스크톱 러너의 apply 문**으로 다시 돈다.
// 링 걸음 생성기·기록 모양은 core/net RealtimeGoldenTest 와 같은 글자(그쪽은 private 이라 여기 다시 적는다 — 골든 자체는 읽기만).
// 러너가 effect 를 실행해도(가짜 전송자·막힌 게이트·멈춘 시계 범위) 링의 걸음이 Swift 와 같아야 하고, 화면 값(state)은 걸음마다 링과 같아야 한다(R7).
package com.yehsung.aingcheck.feature.desktop.realtime

import com.yehsung.aingcheck.core.foundation.rng.SplitMix64
import com.yehsung.aingcheck.core.net.realtime.RealtimeEffect
import com.yehsung.aingcheck.core.net.realtime.RealtimeEvent
import com.yehsung.aingcheck.core.net.realtime.RealtimeJoinRejection
import com.yehsung.aingcheck.core.net.realtime.RealtimeLink
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransportEvent
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.testkit.dump.GoldenDump
import com.yehsung.aingcheck.testkit.dump.GoldenScrub
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenCanonical
import com.yehsung.aingcheck.testkit.golden.GoldenFile
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.hex64
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import java.util.Base64
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

@OptIn(ExperimentalCoroutinesApi::class)
class DesktopRealtimeLinkWalkTest {
    private val dumper = GoldenDump(leaf = { v -> if (v is SwiftDate) GoldenDump.date(v.timeIntervalSince1970) else null })

    private object Walk {
        const val START = 1_790_000_000.0
        fun jwt(exp: Long): String =
            "e30." + Base64.getUrlEncoder().withoutPadding().encodeToString("{\"exp\":$exp}".encodeToByteArray()) + ".c2ln"
        val tokOK = jwt((START + 2_592_000).toLong())
        val tokSoon = jwt((START + 100).toLong())
        const val tokBad = "not-a-jwt"

        /** Swift `RealtimeWalk.event` 와 같은 갈래 · 같은 rng 차례. */
        fun event(rng: SplitMix64): RealtimeEvent = when ((rng.next() % 34uL).toInt()) {
            0 -> RealtimeEvent.SignedIn(tokOK)
            1 -> RealtimeEvent.SignedIn(tokSoon)
            2 -> RealtimeEvent.SignedIn(tokBad)
            3 -> RealtimeEvent.SignedOut
            4 -> RealtimeEvent.WillSleep
            5 -> RealtimeEvent.DidWake
            6 -> RealtimeEvent.Transport(RealtimeTransportEvent.Opened)
            7, 8 -> RealtimeEvent.Transport(RealtimeTransportEvent.Joined)
            9 -> RealtimeEvent.Transport(RealtimeTransportEvent.JoinRejected(RealtimeJoinRejection.ExpiredToken))
            10 -> RealtimeEvent.Transport(RealtimeTransportEvent.JoinRejected(RealtimeJoinRejection.Unauthorized))
            11 -> RealtimeEvent.Transport(RealtimeTransportEvent.JoinRejected(RealtimeJoinRejection.Unknown("boom")))
            12 -> RealtimeEvent.Transport(RealtimeTransportEvent.Broadcast("gomoku"))
            13 -> RealtimeEvent.Transport(RealtimeTransportEvent.Broadcast("chess"))
            14 -> RealtimeEvent.Transport(RealtimeTransportEvent.Broadcast("tetris"))
            15 -> RealtimeEvent.Transport(RealtimeTransportEvent.Broadcast("message_read"))
            16 -> RealtimeEvent.Transport(RealtimeTransportEvent.Broadcast("poke"))
            17 -> RealtimeEvent.Transport(RealtimeTransportEvent.HeartbeatAck)
            18 -> RealtimeEvent.Transport(RealtimeTransportEvent.HeartbeatTimedOut)
            19 -> RealtimeEvent.Transport(RealtimeTransportEvent.Closed(if (rng.next() % 2uL == 0uL) null else 1006))
            20, 21 -> RealtimeEvent.BackoffElapsed
            in 22..27 -> RealtimeEvent.Tick
            28 -> RealtimeEvent.TokenRefreshed(tokOK)
            29 -> RealtimeEvent.TokenRefreshed(tokSoon)
            30 -> RealtimeEvent.TokenRefreshFailed(rng.next() % 2uL == 0uL)
            31 -> RealtimeEvent.UserRequestedRetry
            else -> RealtimeEvent.Tick
        }
    }

    private fun bits(d: Double): JsonElement = JsonPrimitive(Golden.bitsText(d))

    private fun record(link: RealtimeLink, event: RealtimeEvent, effects: List<RealtimeEffect>, now: SwiftDate): JsonObject = JsonObject(
        mapOf(
            "now" to bits(now.timeIntervalSince1970),
            "e" to dumper.dump(event),
            "fx" to dumper.dump(effects),
            "s" to dumper.dump(link.state),
            "tok" to (link.accessToken?.let { JsonPrimitive(it) } ?: JsonNull),
            "fs" to (link.failingSince?.let { bits(it.timeIntervalSince1970) } ?: JsonNull),
            "fr" to JsonPrimitive(link.forcedRefreshUsedThisAttempt),
            "hb" to (link.lastHeartbeatSentAt?.let { bits(it.timeIntervalSince1970) } ?: JsonNull),
        ),
    )

    private fun fnv(text: String, h0: ULong): ULong {
        var h = h0
        for (b in text.encodeToByteArray()) {
            h = h xor (b.toULong() and 0xFFuL)
            h *= 0x00000100000001B3uL
        }
        return h
    }

    /** 멈춘 범위(진행시키지 않는 TestScope) — 러너가 띄운 재시도·따라잡기 작업이 걸음 사이에 끼어들지 않는다. */
    private fun harness(transportAvailable: Boolean, jitter: (Double) -> Double): RealtimeHarness =
        RealtimeHarness(TestScope(), transport = if (transportAvailable) FakeTransport() else null, gateOpen = false, jitter = jitter)

    @Test
    fun linkWalkReplaysThroughDesktopRunner() {
        val golden = Golden.load("realtime/link-walk")
        var totalSteps = 0
        var scripts = 0
        for (c in golden.cases) {
            if ("script" in c) {
                replayScript(golden, c)
                scripts++
                continue
            }
            val rng = SplitMix64(c.hex64("seed"))
            val steps = c.int("steps")
            val h = harness((c["transportAvailable"] as JsonPrimitive).content == "true") { ceiling -> ceiling * (0.5 + 0.5 * rng.unit()) }
            var now = SwiftDate(Walk.START)
            var hash = 0xCBF29CE484222325uL
            val checkpoints = mutableListOf<String>()
            val head = c.array("head")
            for (step in 1..steps) {
                var dt = (rng.next() % 20_001uL).toDouble() / 1000
                if (rng.next() % 50uL == 0uL) dt += 60
                now = now.addingTimeInterval(dt)
                h.now = now
                val event = Walk.event(rng)
                val effects = h.runner.apply(event, now)
                if (h.runner.state.value != h.runner.link.state) fail("R7 걸음 $step: 화면 값 ${h.runner.state.value} ≠ 링 ${h.runner.link.state}")
                val rec = record(h.runner.link, event, effects, now)
                if (step <= head.size) {
                    val shown = GoldenCanonical.text(GoldenScrub.json(rec))
                    if (shown != GoldenCanonical.text(head[step - 1])) {
                        fail(golden.failure(c.string("id"), "걸음 $step 이 다르다\n  Swift : ${GoldenCanonical.text(head[step - 1])}\n  Kotlin: $shown"))
                    }
                }
                hash = fnv(GoldenCanonical.text(rec), hash)
                if (step % 500 == 0) checkpoints += Golden.hex64Text(hash)
            }
            totalSteps += steps
            val want = c.array("checkpoints").map { it.jsonPrimitive.content }
            val firstBad = want.indices.firstOrNull { it >= checkpoints.size || want[it] != checkpoints[it] }
            if (firstBad != null) {
                fail(golden.failure(c.string("id"), "체크포인트 #$firstBad 가 다르다: Swift ${want[firstBad]} · 데스크톱 ${checkpoints.getOrNull(firstBad)}"))
            }
            assertEquals(c.string("final"), Golden.hex64Text(hash), golden.failure(c.string("id"), "끝 해시"))
            // 막힌 게이트 아래 1만 걸음 — take_pokes 는 한 번도 나가지 않는다(R3).
            assertEquals(0, h.drainer.takePokes, "닫힌 게이트 걷기에서 take_pokes")
        }
        println("AINGCHECK-W2G3-WALK walks=${golden.cases.size - scripts} scripts=$scripts steps=$totalSteps")
        assertTrue(totalSteps >= 10_000, "걸음이 1만 미만($totalSteps)")
        assertTrue(scripts >= 3, "경계 대본(25·50·15·45초)이 골든에 없다($scripts)")
    }

    private fun scriptedEvent(code: String): RealtimeEvent = when (code) {
        "signedIn:tokOK" -> RealtimeEvent.SignedIn(Walk.tokOK)
        "joined" -> RealtimeEvent.Transport(RealtimeTransportEvent.Joined)
        "tick" -> RealtimeEvent.Tick
        "heartbeatAck" -> RealtimeEvent.Transport(RealtimeTransportEvent.HeartbeatAck)
        "closed:nil" -> RealtimeEvent.Transport(RealtimeTransportEvent.Closed(null))
        else -> error("모르는 대본 사건 $code")
    }

    /** 경계 대본: 정수 초만 더해 실시간 하트비트 눈금·무응답·조인 타임아웃·실패 굳기 경계에 정확히 닿는다(지터 = 상한 × 0.75). */
    private fun replayScript(golden: GoldenFile, c: JsonObject) {
        val h = harness(transportAvailable = true) { ceiling -> ceiling * 0.75 }
        var now = SwiftDate(Walk.START)
        val records = c.array("records")
        val script = c.array("script")
        assertEquals(script.size, records.size, golden.failure(c.string("id"), "대본 걸음 수와 기록 수"))
        script.forEachIndexed { i, step ->
            val pair = step as JsonArray
            now = now.addingTimeInterval((pair[0] as JsonPrimitive).content.toDouble())
            h.now = now
            val event = scriptedEvent((pair[1] as JsonPrimitive).content)
            val effects = h.runner.apply(event, now)
            val shown = GoldenCanonical.text(GoldenScrub.json(record(h.runner.link, event, effects, now)))
            val want = GoldenCanonical.text(records[i])
            if (shown != want) fail(golden.failure(c.string("id"), "대본 걸음 ${i + 1}(${pair[1]}) 이 다르다\n  Swift : $want\n  데스크톱: $shown"))
        }
    }
}
