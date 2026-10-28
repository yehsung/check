// 원본: Tests/checkTests/V0327GomokuContractTests.swift:371-473(실서버 M1 흐름 두 사람 시점) · :500-660(신청·stale·not_your_turn) @ 1b8260d
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuEndReason
import com.yehsung.aingcheck.core.rules.renju.GomokuOutcome
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.wire.games.GomokuStatePayload
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * G §2-3 W2-d ①: 대국 픽스처 흐름(`flow_m1_*`) 재생 — 실서버 M1 흐름(수락 → 9수 → 흑 5목)을 **두 사람 시점**으로 재생하면 화면 상태가 서버 사실과
 * 같고, 스토어가 내는 요청 인자(p_since_seq · p_expected_seq · p_x · p_accept)가 서버가 그 응답을 만든 인자와 같다(Swift 계약 시험과 같은 표).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class GomokuFlowContractTest {
    class Rig(val store: GomokuStore, val host: FakeDuelHost, val server: DuelStubServer)

    private fun TestScope.rig(me: String, configure: DuelStubServer.() -> Unit): Rig {
        val server = DuelStubServer(this).apply(configure)
        val host = FakeDuelHost(server.service { contractClock }, me, clockNow = { contractClock })
        val store = GomokuStore(storeScope(), host)
        store.clock = { contractClock }
        return Rig(store, host, server)
    }

    /** 스토어의 대국 상태가 서버 사실과 같은가(Swift `expectMatchEqualsServer`). */
    private fun assertMatchEqualsServer(
        store: GomokuStore,
        facts: GomokuServerFacts,
        label: String,
        lastMove: GomokuPoint? = null,
        checkLastMove: Boolean = false,
        blackPassed: Boolean? = null,
    ) {
        val match = assertNotNull(store.match, "$label 판이 없다")
        assertEquals(facts.matchID, match.id, label)
        assertEquals(facts.board, match.board.serverString, "$label 판이 서버 board 와 다르다")
        assertEquals(facts.moveCount, match.moveCount, label)
        assertEquals(facts.turn, match.turn?.rawValue, "$label 차례")
        assertEquals(facts.myColor, match.myColor.rawValue, label)
        assertEquals(facts.stake, match.stake, label)
        val finished = facts.matchStatus == "finished"
        assertEquals(finished, match.isFinished, label)
        assertEquals(if (finished) GomokuPhase.result else GomokuPhase.playing, store.phase, label)
        val deadlineMs = facts.deadlineMs
        val serverNowMs = facts.serverNowMs
        if (!finished && deadlineMs != null && serverNowMs != null) {
            // 서버 시계와 기기 시계가 며칠 어긋나도(픽스처는 과거에 떴다) 기기 시각으로는 '지금 + (마감 − 서버 지금)'이다.
            val expected = contractClock.addingTimeInterval((deadlineMs - serverNowMs) / 1000)
            val actual = assertNotNull(match.deadline, "$label 마감")
            val tolerance = GomokuStore.serverClockToleranceSeconds + 0.002
            assertTrue(abs(actual.timeIntervalSince(expected)) < tolerance, "$label 마감 보정 ${actual.timeIntervalSince(expected)}초 어긋남")
            val remaining = store.remainingSeconds(contractClock) ?: -1.0
            assertTrue(remaining > 29 && remaining <= 30 + tolerance, "$label 남은 시간 $remaining 초")
        } else {
            assertNull(match.deadline, label)
            assertNull(store.remainingSeconds(contractClock), label)
        }
        val expectedOutcome = when (facts.result) {
            "draw" -> GomokuOutcome.draw
            "black_win" -> if (facts.myColor == "black") GomokuOutcome.won else GomokuOutcome.lost
            "white_win" -> if (facts.myColor == "white") GomokuOutcome.won else GomokuOutcome.lost
            else -> null
        }
        assertEquals(expectedOutcome, match.outcome, "$label 결과")
        assertEquals(facts.endReason, match.endReason?.rawValue, "$label 끝난 이유")
        // 손으로 적은 표(v0.3.64 수수료 0: 3/5/10 → +3/+5/+10). `DuelFee` 식으로 기대값을 만들면 식이 틀려도 초록이다.
        val expectedDelta = when (expectedOutcome) {
            GomokuOutcome.won -> mapOf(3L to 3L, 5L to 5L, 10L to 10L)[facts.stake]
            GomokuOutcome.lost -> -facts.stake
            GomokuOutcome.draw -> 0L
            null -> null
        }
        assertEquals(expectedDelta, match.rubyDelta, "$label 루비 변화")
        facts.ruby?.let { assertEquals(it, store.rubyBalance, "$label 루비") }
        if (checkLastMove) assertEquals(lastMove, match.lastMove, "$label 마지막 수")
        blackPassed?.let { assertEquals(it, match.blackPassed, "$label 흑 자동 패스") }
    }

    private fun flowReplay(perspective: String) = runTest {
        val manifest = gomokuManifest()
        val fullFlow = manifest["flow_m1"]!!.jsonArray.map { it.jsonObject }
        val flow = fullFlow.filter { it.str("perspective") == perspective }
        val m1 = gomokuUser("m1")
        val acceptMatch = fixtureJSON(GOMOKU_FIXTURES, "gomoku_respond__accept_ok").obj("match")!!
        val blackID = acceptMatch.str("black")!!
        val whiteID = acceptMatch.str("white")!!
        val challengerID = acceptMatch.str("challenger")!!
        val myID = if (perspective == "black") blackID else whiteID
        val peerID = if (perspective == "black") whiteID else blackID
        assertEquals(5L, GomokuServerFacts("gomoku_respond__accept_ok").stake)

        val points = HashMap<Int, GomokuPoint>()
        for (entry in fullFlow) {
            if (entry.str("kind") != "place") continue
            points[entry.long("expected")!!.toInt() + 1] = GomokuPoint.at(entry.long("x")!!.toInt(), entry.long("y")!!.toInt())!!
        }
        val rig = rig(myID) {
            for (entry in flow) {
                val rpc = when (entry.str("kind")) {
                    "respond" -> "gomoku_respond"
                    "inbox" -> "gomoku_inbox"
                    "state" -> "gomoku_state"
                    else -> "gomoku_move"
                }
                queueFixtures(rpc, GOMOKU_FIXTURES, entry.str("file")!!)
            }
            queueFixtures("gomoku_lobby", GOMOKU_FIXTURES, "gomoku_lobby__ok_after_win_$perspective")
        }
        val store = rig.store
        val server = rig.server
        var finishedCalls = 0
        store.onMatchFinished = { finishedCalls += 1 }
        val invite = GomokuInvite(m1, peerFor(peerID), 5, contractClock.addingTimeInterval(50.0))
        if (myID == challengerID) store.outgoing = invite else store.incoming = listOf(invite)

        var index = 0
        var states = 0
        var moves = 0
        while (index < flow.size) {
            val entry = flow[index]
            var file = entry.str("file")!!
            when (entry.str("kind")) {
                "respond" -> {
                    store.respond(m1, accept = true)
                    assertTrue(store.incoming.isEmpty(), "수락한 신청 카드가 남았다")
                    assertEquals(true, server.lastBody("gomoku_respond").bool("p_accept"))
                }
                "inbox" -> {
                    // 인박스가 active_match_id 를 말하면 스토어가 곧바로 그 판을 since 0 으로 읽는다 — 흐름의 다음 항목이 그 응답이다.
                    store.loadInbox()
                    val next = flow[index + 1]
                    assertEquals("state", next.str("kind"))
                    file = next.str("file")!!
                    index += 1
                    states += 1
                    assertEquals(next.long("since"), server.lastBody("gomoku_state").long("p_since_seq"))
                    assertNull(store.outgoing, "수락된 보낸 신청 카드가 남았다")
                }
                "state" -> {
                    store.refreshMatch()
                    states += 1
                    assertEquals(entry.long("since"), server.lastBody("gomoku_state").long("p_since_seq"), "스토어가 낸 since 가 서버가 이 응답을 만든 since 와 다르다")
                }
                else -> {
                    val point = GomokuPoint.at(entry.long("x")!!.toInt(), entry.long("y")!!.toInt())!!
                    store.place(point)
                    moves += 1
                    assertEquals(entry.long("expected"), server.lastBody("gomoku_move").long("p_expected_seq"))
                    assertEquals(point.x.toLong(), server.lastBody("gomoku_move").long("p_x"))
                    assertEquals(point.y.toLong(), server.lastBody("gomoku_move").long("p_y"))
                }
            }
            assertEquals(states, server.count("gomoku_state"), "$file state 호출 수")
            assertEquals(moves, server.count("gomoku_move"), "$file move 호출 수")
            val facts = GomokuServerFacts(file)
            assertEquals(myID, facts.myID)
            assertMatchEqualsServer(
                store, facts, file,
                lastMove = if (facts.moveCount > 0) points[facts.moveCount] else null, checkLastMove = true, blackPassed = false,
            )
            assertNull(store.notice, "$file 안내: ${store.notice}")
            assertEquals(facts.ruby, rig.host.rubyBalance, "$file 호스트 루비 칩")
            index += 1
        }

        val final = assertNotNull(store.match)
        assertTrue(final.isFinished)
        assertEquals(9, final.moveCount)
        assertEquals(if (perspective == "black") GomokuOutcome.won else GomokuOutcome.lost, final.outcome)
        assertEquals(GomokuEndReason.five, final.endReason)
        // 결과 카드 눈금(클라 계산): 판돈 5 승리 → +5(v0.3.64 수수료 0) · 패배 → −5.
        assertEquals(if (perspective == "black") 5L else -5L, final.rubyDelta)
        // 서버 정산 산수(녹화 당시 서버): 100 → 수락 −5 → 승자 +10 = 105. 잔량은 서버 값을 그대로 옮긴다.
        assertEquals(if (perspective == "black") 105L else 95L, store.rubyBalance)
        // v0.3.64: 끝난 것을 **처음 본** 순간 한 번(일일 미션 재조회 고리). 같은 끝난 판을 다시 받아도 또 안 부른다.
        assertEquals(1, finishedCalls)
        // 같은 값이면 Swift 처럼 대입 자체를 건너뛰므로(`if match != next`) 상대 이름 하나를 바꿔 **대입이 일어나게** 한다.
        val lastFile = flow.last { it.str("perspective") == perspective }.str("file")!!
        val again = fixtureJSON(GOMOKU_FIXTURES, lastFile).let { json ->
            val opponent = json.obj("opponent")!!
            JsonObject((json - "state") + ("opponent" to JsonObject(opponent + ("display_name" to JsonPrimitive("다시받음")))))
        }
        store.applyState(decodeJson(again, GomokuStatePayload.serializer()))
        assertEquals("다시받음", store.match?.opponent?.displayName, "다시 받은 끝난 판이 대입되지 않았다(아래 단언이 빈 단언이 된다)")
        assertEquals(1, finishedCalls, "같은 끝난 판을 다시 받았는데 끝남 고리를 또 불렀다")
        // 판이 끝난 순간 전적을 다시 읽는다(스토어 계약) — 서버 로비 me 가 이 판을 센다.
        settle()
        assertEquals(1, server.count("gomoku_lobby"))
        assertEquals(if (perspective == "black") GomokuRecord(1, 0, 0) else GomokuRecord(0, 1, 0), store.record)
        assertEquals(GomokuPhase.result, store.phase, "로비 재조회가 결과 화면을 걷었다")
        // ③ p_protocol 은 언제나 싣는다 — 이 흐름이 낸 요청 **전부**(respond · inbox · state · move · lobby)가 2 를 싣는다.
        assertTrue(server.calls.isNotEmpty())
        for (call in server.calls) assertEquals(2L, call.body.long("p_protocol"), "${call.rpc} 본문에 p_protocol 2 가 없다: ${call.body}")
    }

    @Test
    fun flowM1ReplayFromBlackMatchesServer() = flowReplay("black")

    @Test
    fun flowM1ReplayFromWhiteMatchesServer() = flowReplay("white")

    @Test
    fun challengeStatusesBecomeUserWordsAndFollowUpReads() = runTest {
        val rivalB = gomokuUser("B")
        // (픽스처, 안내, 뒤따라 다시 읽는 rpc) — Swift 계약 시험의 표 그대로.
        val cases = listOf(
            Triple("gomoku_challenge__invalid", "신청할 수 없는 상대예요", null),
            Triple("gomoku_challenge__unsupported_client", "앱을 업데이트해야 대결할 수 있어요", null),
            Triple("gomoku_challenge__blackout", "지금은 조용한 기간이라 신청할 수 없어요", null),
            Triple("gomoku_challenge__not_working", "근무 중일 때만 신청할 수 있어요", null),
            Triple("gomoku_challenge__target_not_working", "상대가 근무 중이 아니에요", "gomoku_lobby"),
            Triple("gomoku_challenge__target_focused", "상대가 집중 모드라 신청할 수 없어요", null),
            Triple("gomoku_challenge__target_outdated", "상대가 앱을 업데이트해야 해요", "gomoku_lobby"),
            Triple("gomoku_challenge__busy", "이미 진행 중인 대국이 있어요", "gomoku_inbox"),
            Triple("gomoku_challenge__target_busy", "상대가 다른 대국 중이에요", "gomoku_lobby"),
            Triple("gomoku_challenge__insufficient", "루비 6개 더 필요해요", null),
            Triple("gomoku_challenge__already_pending", "이미 보낸 신청이 있어요", "gomoku_inbox"),
            Triple("gomoku_challenge__ok", "신청을 보냈어요", null),
        )
        for ((name, notice, follow) in cases) {
            val rig = rig("caller-$name") { queueFixtures("gomoku_challenge", GOMOKU_FIXTURES, name) }
            rig.store.challenge(rivalB)
            settle()
            assertEquals(notice, rig.store.notice, name)
            assertEquals(1, rig.server.count("gomoku_challenge"), name)
            assertEquals(rivalB, rig.server.lastBody("gomoku_challenge").str("p_opponent"), name)
            assertEquals(3L, rig.server.lastBody("gomoku_challenge").long("p_stake"), name)
            for (rpc in listOf("gomoku_lobby", "gomoku_inbox")) {
                assertEquals(if (rpc == follow) 1 else 0, rig.server.count(rpc), "$name → $rpc")
            }
            if (name.endsWith("__ok")) {
                val fixture = fixtureJSON(GOMOKU_FIXTURES, name)
                val sent = assertNotNull(rig.store.outgoing, name)
                assertEquals(fixture.str("match_id")!!.lowercase(), sent.id)
                // 만료 = 기기 시각 + (서버 만료 − 서버 지금).
                val expected = contractClock.addingTimeInterval((fixture.double("invite_expires_ms")!! - fixture.double("server_now_ms")!!) / 1000)
                assertTrue(abs(sent.expiresAt.timeIntervalSince(expected)) < 0.01, "$name 만료 보정")
            } else {
                assertNull(rig.store.outgoing, name)
            }
            assertTrue(!rig.store.isBusy, name)
        }
    }

    @Test
    fun staleMoveRereadsFromSinceAndDoesNotPlaceTheStone() = runTest {
        val facts = GomokuServerFacts("gomoku_move__stale")
        val rig = rig(facts.myID) {
            queueFixtures("gomoku_move", GOMOKU_FIXTURES, "gomoku_move__stale")
            queueFixtures("gomoku_state", GOMOKU_FIXTURES, "gomoku_state__ok_black_since2_count2")
        }
        // 이 기기는 같은 판의 count 0 화면에 머물러 있다 — stale 호출자와 같은 시점의 count 0 응답을 고른다.
        val flow = gomokuManifest()["flow_m1"]!!.jsonArray.map { it.jsonObject }
        val seedFile = flow.firstOrNull { entry ->
            val file = entry.str("file") ?: return@firstOrNull false
            entry.str("perspective") == facts.myColor && entry.str("kind") in setOf("respond", "state") &&
                runCatching { GomokuServerFacts(file) }.getOrNull()?.let { it.matchID == facts.matchID && it.moveCount == 0 } == true
        }?.str("file") ?: fail("stale 호출자(${facts.myColor})의 count 0 응답이 흐름에 없다")
        seed(rig.store, seedFile)
        assertEquals(facts.myColor, rig.store.match?.myColor?.rawValue)
        assertEquals(0, rig.store.match?.moveCount)
        rig.store.place(GomokuPoint.at(5, 5)!!)
        assertEquals(0L, rig.server.lastBody("gomoku_move").long("p_expected_seq"))
        assertEquals(2L, rig.server.lastBody("gomoku_state").long("p_since_seq"))
        assertMatchEqualsServer(
            rig.store, GomokuServerFacts("gomoku_state__ok_black_since2_count2"), "stale 뒤 재조회",
            lastMove = GomokuPoint.at(0, 1), checkLastMove = true, blackPassed = false,
        )
        assertNull(rig.store.match?.board?.get(GomokuPoint.at(5, 5)!!), "stale 로 거절된 돌이 판에 남았다")
        assertNull(rig.store.notice)
    }

    @Test
    fun aGapInTheMoveLogRereadsFromTheStartOnce() = runTest {
        // Swift `기록에_구멍이_나면_처음부터_한_번_더_받는다` — 판 글자(board)가 없는 응답(옛 서버 꼴)에서 기록만으로 판을 쌓는 길.
        val base = "gomoku_state__ok_black_since2_count2"
        val facts = GomokuServerFacts(base)
        val all = listOf(Triple(1, "black", 7 to 7), Triple(2, "white", 8 to 7), Triple(3, "black", 6 to 6), Triple(4, "white", 5 to 5))
        fun payload(seqs: Set<Int>, moveCount: Int): JsonObject {
            val json = fixtureJSON(GOMOKU_FIXTURES, base)
            val match = json.obj("match")!!
            val moves = all.filter { it.first in seqs }.map { (seq, color, xy) ->
                JsonObject(mapOf("seq" to JsonPrimitive(seq), "color" to JsonPrimitive(color), "x" to JsonPrimitive(xy.first), "y" to JsonPrimitive(xy.second)))
            }
            return JsonObject(
                (json - "state") + mapOf(
                    "match" to JsonObject((match - "board") + mapOf("move_count" to JsonPrimitive(moveCount), "turn" to JsonPrimitive("black"))),
                    "moves" to JsonArray(moves),
                ),
            )
        }
        val rig = rig(facts.myID) {
            // since 2 를 물었는데 3이 빠진 채 온다(구멍) → 처음부터 다시 받아야 한다.
            queue("gomoku_state", StubReply.Json(payload(setOf(4), 4).toString()), StubReply.Json(payload(setOf(1, 2, 3, 4), 4).toString()))
        }
        assertEquals(GomokuStore.StateApplyOutcome.applied, rig.store.applyState(decodeJson(payload(setOf(1, 2), 2), GomokuStatePayload.serializer())))
        assertEquals(2, rig.store.match?.moveCount)
        rig.store.refreshMatch()
        assertEquals(listOf(2L, 0L), rig.server.bodies("gomoku_state").map { it.long("p_since_seq") })
        assertEquals(4, rig.store.match?.moveCount)
        assertEquals(GomokuColor.black, rig.store.match?.board?.get(GomokuPoint.at(6, 6)!!), "구멍 난 판을 그리면 이 돌이 빠진다")
        assertEquals(4, rig.store.match?.board?.stoneCount)
        assertEquals(GomokuPoint.at(5, 5), rig.store.match?.lastMove)
    }

    @Test
    fun autoPlacedIsNotALossButAServerPlacedStone() = runTest {
        // 마감이 지나도 **판은 계속된다** — 서버가 빈칸 하나에 대신 놓고 차례를 넘긴다. 결과 화면으로 넘어가면 사용자는 진 줄 안다.
        val facts = GomokuServerFacts("gomoku_move__auto_placed")
        val fixture = fixtureJSON(GOMOKU_FIXTURES, "gomoku_move__auto_placed")
        val rig = rig(facts.myID) { queueFixtures("gomoku_move", GOMOKU_FIXTURES, "gomoku_move__auto_placed") }
        // 이 기기는 아직 자동 착수 전(내 차례, 기록 1수)으로 알고 있다.
        seed(rig.store, "gomoku_move__auto_placed") { json ->
            val match = json.obj("match")!!
            val nextMatch = JsonObject(
                (match - "board") + mapOf(
                    "move_count" to kotlinx.serialization.json.JsonPrimitive(1),
                    "turn" to kotlinx.serialization.json.JsonPrimitive(facts.myColor),
                ),
            )
            JsonObject(
                json + mapOf(
                    "match" to nextMatch,
                    "moves" to kotlinx.serialization.json.JsonArray(emptyList()),
                    "my_auto_streak" to kotlinx.serialization.json.JsonPrimitive(0),
                ),
            )
        }
        assertEquals(1, rig.store.match?.moveCount)
        assertEquals(facts.myColor, rig.store.match?.turn?.rawValue)

        rig.store.place(GomokuPoint.at(8, 8)!!)

        assertEquals(1L, rig.server.lastBody("gomoku_move").long("p_expected_seq"))
        assertEquals(1L, fixture.long("auto_placed_count"), "픽스처: 한 수가 자동으로 놓였다")
        // ① 판은 끝나지 않았고 ② 내 돌이 아니라 **서버가 놓은 돌**이 하나 늘었고 ③ 차례가 상대에게 갔다
        assertEquals(false, rig.store.match?.isFinished)
        assertEquals(GomokuPhase.playing, rig.store.phase, "자동 착수를 결과 화면으로 옮겼다")
        assertEquals(facts.moveCount, rig.store.match?.moveCount)
        assertEquals(facts.board, rig.store.match?.board?.serverString)
        assertEquals(facts.turn, rig.store.match?.turn?.rawValue)
        assertNull(rig.store.match?.outcome)
        assertNull(rig.store.match?.endReason)
        assertEquals(true, rig.store.match?.lastMoveWasAuto, "자동으로 놓인 수가 회색 점으로 구분되지 않는다")
        assertEquals(1, rig.store.myAutoStreak)
        assertNull(rig.store.autoStreakWarning, "첫 번째부터 겁을 주지 않는다")
        assertEquals(GomokuNoticeText.autoPlaced, rig.store.notice)
        assertEquals(0, rig.server.count("gomoku_state"), "상태를 함께 실어 줬는데 또 물었다")
    }

    /** 픽스처(최상위 상태 묶음)를 스토어에 심는다. [mutate] 로 한 기기의 옛 화면을 흉내 낸다. */
    private fun seed(store: GomokuStore, name: String, mutate: ((JsonObject) -> JsonObject)? = null) {
        var json = fixtureJSON(GOMOKU_FIXTURES, name)
        json = JsonObject(json - "state")
        if (mutate != null) json = mutate(json)
        val payload = decodeJson(json, GomokuStatePayload.serializer())
        assertEquals(GomokuStore.StateApplyOutcome.applied, store.applyState(payload), "seed $name")
    }
}
