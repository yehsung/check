// 원본: Tests/checkTests/V0369RummyV2LobbyTests.swift:296 (rematchInvitees) 의 뜻을 스토어 동작까지 — [한 판 더] 의 뜻은 맥 뷰(RummyPanelResult.swift:85)에 있어 원본 시험이 없다.
package com.yehsung.aingcheck.core.stores.rummy

import com.yehsung.aingcheck.core.rules.rummy.RummyPhase
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.Reply
import com.yehsung.aingcheck.core.stores.games.StoreFixtures
import com.yehsung.aingcheck.core.stores.games.StoreHarness
import com.yehsung.aingcheck.core.stores.games.TestRummyHost
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val ME = StoreFixtures.USER
private const val B = StoreFixtures.PEER
private const val C = StoreFixtures.OTHER
private const val FINISHED = "7e7e0000-0000-4000-8000-000000000071"
private const val ROOM = "7e7e0000-0000-4000-8000-000000000072"
private const val NOW_MS = 1_800_000_000_000L
private const val LOBBY = """{"status":"ok","server_now_ms":$NOW_MS,"stakes":[3,5,10],"turn_seconds":60,"room_ttl_seconds":600,"me":{"ruby_balance":120,"games":4,"wins":1,"room":null,"active_match_id":null},"invites":[],"public_rooms":[],"users":[]}"""

private fun state(status: String, thirdState: String = "forfeit", seq: Long = 9): String =
    """{"id":"$FINISHED","status":"$status","host_id":"$B","stake":10,"is_public":true,"seq":$seq,"server_now_ms":$NOW_MS,"my_seat_no":0,"table":[],""" +
        """"seats":[{"seat_no":0,"user_id":"$ME","display_name":"나","state":"${if (status == "finished") "done" else "playing"}"},""" +
        """{"seat_no":1,"user_id":"$B","display_name":"비","state":"${if (status == "finished") "done" else "playing"}"},""" +
        """{"seat_no":2,"user_id":"$C","display_name":"씨","state":"$thirdState"}]}"""

private const val FORMING =
    """{"id":"$ROOM","status":"forming","host_id":"$ME","stake":10,"is_public":true,"seq":0,"server_now_ms":$NOW_MS,"expires_at_ms":${NOW_MS + 600_000},"max_seats":4,"my_seat_no":0,"table":[],""" +
        """"seats":[{"seat_no":0,"user_id":"$ME","display_name":"나","state":"joined"}]}"""

private fun decode(text: String): RummyMatchState = SwiftJson.decode(RummyMatchState.serializer(), text)

private class ResultRig(val h: StoreHarness, val store: RummyStore, val standing: MutableMap<String, String>) {
    fun bodies(rpc: String): List<JsonObject> = h.server.bodies(rpc).map { Json.parseToJsonElement(it).jsonObject }
}

@OptIn(ExperimentalCoroutinesApi::class)
private suspend fun TestScope.rig(): ResultRig {
    val standing = mutableMapOf("rummy_lobby" to LOBBY)
    val config = AppConfig(duelsEnabled = true)
    val h = StoreHarness(this, config) { r -> r.rpcName?.let { standing[it] }?.let { Reply.Json(it) } }
    h.signIn()
    val wall = SwiftDate(1_800_000_000.0)
    val host = TestRummyHost(h.sessionStore, config) { wall }
    val store = RummyStore(h.storeScope, host)
    store.clock = { wall }
    store.pollStepSeconds = Double.POSITIVE_INFINITY
    store.deadlineWakeEnabled = false
    store.heartbeatEnabled = false
    return ResultRig(h, store, standing)
}

@OptIn(ExperimentalCoroutinesApi::class)
class RummyStoreResultTest {
    @Test
    fun playAgainKeepsStakeAndPublicAndCallsSurvivorsOnly() = runTest {
        // 없으면: 판돈 10 공개 판 뒤의 [한 판 더]가 기본값(판돈 3 · 비공개)으로 열리거나 기권한 사람을 다시 부른다.
        val r = rig()
        r.standing["rummy_create"] = """{"status":"ok","match_id":"$ROOM","state":$FORMING,"server_now_ms":$NOW_MS}"""
        r.standing["rummy_invite"] = """{"status":"ok"}"""
        r.standing["rummy_state"] = """{"status":"ok","state":$FORMING,"server_now_ms":$NOW_MS}"""
        r.store.applyState(decode(state("finished")))
        runCurrent()
        assertEquals(RummyPhase.finished, r.store.phase)
        assertEquals(3L, r.store.selectedStake, "기준선: 판돈은 아직 기본값")

        r.store.playAgain()
        runCurrent()

        val create = r.bodies("rummy_create").single()
        assertEquals("10", create.getValue("p_stake").jsonPrimitive.content)
        assertEquals("true", create.getValue("p_public").jsonPrimitive.content)
        assertEquals(listOf(B), r.bodies("rummy_invite").map { it.getValue("p_user").jsonPrimitive.content })
        assertEquals(RummyPhase.room, r.store.phase)
        assertTrue(r.store.inviteQueue.pending.isEmpty())
        r.h.assertClean()
    }

    @Test
    fun playAgainWithNobodyLeftStillOpensATable() = runTest {
        // 혼자 남아 이긴 판 — 부를 사람이 없어도 탁자는 열린다.
        val r = rig()
        r.standing["rummy_create"] = """{"status":"ok","match_id":"$ROOM","state":$FORMING,"server_now_ms":$NOW_MS}"""
        r.standing["rummy_state"] = """{"status":"ok","state":$FORMING,"server_now_ms":$NOW_MS}"""
        val alone = decode(state("finished")).let { m -> m.copy(seats = m.seats!!.filter { it.seatNo == 0L }) }
        r.store.applyState(alone)
        runCurrent()
        r.store.playAgain()
        runCurrent()
        assertEquals(1, r.bodies("rummy_create").size)
        assertTrue(r.bodies("rummy_invite").isEmpty())
        r.h.assertClean()
    }

    @Test
    fun playAgainDoesNothingOutsideAFinishedMatch() = runTest {
        // 없으면: 도는 판에서 불리면 판을 접는다(판돈이 걸린 판이 화면에서 사라진다).
        val r = rig()
        r.store.playAgain()
        assertEquals(0, r.h.server.count("rummy_create"))
        // 로비는 '내 판 없음'이라 답한다 — 스토어가 그 판을 직접 다시 읽는다(state 고정 응답).
        val active = state("active", thirdState = "playing", seq = 1)
        r.standing["rummy_state"] = """{"status":"ok","state":$active,"server_now_ms":$NOW_MS}"""
        r.store.applyState(decode(active))
        runCurrent()
        r.store.playAgain()
        runCurrent()
        assertEquals(RummyPhase.playing, r.store.phase)
        assertEquals(FINISHED, r.store.match?.id?.lowercased)
        assertEquals(0, r.h.server.count("rummy_create"))
        r.h.assertClean()
    }

    @Test
    fun playAgainWaitsForTheRunningAction() = runTest {
        // 없으면: 앞 동작 때문에 만들기가 무시되고 결과만 접혀 사람들을 못 부른다.
        val r = rig()
        r.store.applyState(decode(state("finished")))
        runCurrent()
        r.store.isWorking = true
        r.store.playAgain()
        assertEquals(RummyPhase.finished, r.store.phase)
        assertEquals(3L, r.store.selectedStake)
        assertFalse(r.store.createPublic)
        r.store.isWorking = false
        r.h.assertClean()
    }

    @Test
    fun dismissResultFoldsTheMatch() = runTest {
        val r = rig()
        r.store.applyState(decode(state("finished")))
        runCurrent()
        r.store.dismissResult()
        runCurrent()
        assertEquals(RummyPhase.lobby, r.store.phase)
        assertNull(r.store.match)
        assertEquals(0, r.h.server.count("rummy_create"), "[나가기]는 새 탁자를 열지 않는다")
        r.h.assertClean()
    }

    @Test
    fun ruleExamplesAreRealTiles() {
        // 규칙 시트가 면 글자를 조용히 건너뛰면 예시가 비어 보인다.
        val examples = RummyPhoneText.ruleList.flatMap { it.example }
        assertTrue(examples.isNotEmpty())
        for (text in examples) assertTrue(RummyFace.of(text) != null, text)
    }

    @Test
    fun rulesSpeakTheUserDecisions() {
        // 사용자 결정: 시간 초과 3번 · 이탈 = 기권 = 꼴찌.
        val lines = RummyPhoneText.ruleList.associate { it.title to it.detail }
        assertTrue("시간 초과가 3번 이어지면 기권" in lines.getValue("시간 60초"))
        assertTrue("기권은 꼴찌" in lines.getValue("등수 분배"))
        assertTrue("판을 나가거나 시간 초과가 3번" in lines.getValue("기권"))
        assertTrue("1분 안에 돌아오면" in lines.getValue("기권"))
        assertTrue("0.5초 꾹 누른 채" in lines.getValue("조작"))
    }
}
