// 원본: Tests/CheckMobileKitTests/V1019DuelRoomsTests.swift @ 9774e23b · 맥 V03xxDuelRoomsTests(코어 스토어 규칙) — 판 9 1:1 대기방
package com.yehsung.aingcheck.core.stores.rooms

import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.rooms.DuelRoomBody
import com.yehsung.aingcheck.core.wire.rooms.DuelRoomCall
import com.yehsung.aingcheck.core.wire.rooms.DuelRoomGame
import com.yehsung.aingcheck.core.wire.rooms.DuelRoomStatus
import com.yehsung.aingcheck.core.wire.rooms.DuelRoomText
import com.yehsung.aingcheck.core.wire.rooms.DuelRoomsResponse
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 대본 서비스 — RPC 이름별 응답 줄(마지막 하나는 계속 돌려준다). 없는 RPC 는 취소로 끝낸다(아이폰 PhoneDRScript). */
private class Script : DuelRoomServing {
    val replies = HashMap<String, ArrayDeque<DuelRoomsResponse>>()
    val calls = mutableListOf<DuelRoomCall>()
    fun on(rpc: String, vararg responses: DuelRoomsResponse) { replies.getOrPut(rpc) { ArrayDeque() }.addAll(responses) }
    override suspend fun call(call: DuelRoomCall): DuelRoomsResponse {
        calls += call
        val list = replies[call.rpcName]
        val first = list?.firstOrNull() ?: throw kotlinx.coroutines.CancellationException("대본 없음")
        if (list.size > 1) list.removeFirst()
        return first
    }
    fun count(rpc: String) = calls.count { it.rpcName == rpc }
}

private fun fixture(name: String): DuelRoomsResponse =
    SwiftJson.decode(DuelRoomsResponse.serializer(), RepoFiles.readText("Tests/checkTests/Fixtures/duel-rooms/$name.json"))

@OptIn(ExperimentalCoroutinesApi::class)
class V9DuelRoomStoreTest {
    private val nowMs = 1_794_293_541_576.0

    private fun TestScope.store(script: Script): DuelRoomStore {
        val job = SupervisorJob()
        backgroundScope.coroutineContext[Job]!!.invokeOnCompletion { job.cancel() }
        return DuelRoomStore(CoroutineScope(coroutineContext.minusKey(Job) + job), script, clockMs = { nowMs + testScheduler.currentTime })
    }

    @Test
    fun wireDecodesFixturesAndBodiesCarryOnlyTheirKeys() {
        val list = fixture("list__ok")
        assertEquals(DuelRoomStatus.ok, list.status)
        assertEquals(listOf(3L, 5L, 10L), list.stakes)
        val room = assertNotNull(list.rooms?.single())
        assertEquals(DuelRoomGame.reversi, room.game)
        assertEquals("민수", room.host?.displayName)
        assertEquals(DuelRoomStatus.unsupportedClient, fixture("list__door_closed").status)
        assertTrue(fixture("ping__started").myRoom!!.isStarted)
        // 모르는 상태 · 깨진 방 줄 하나는 죽지 않는다.
        val odd = SwiftJson.decode(DuelRoomsResponse.serializer(), """{"status":"brand_new","rooms":[{"id":"x"},{"id":"r","game":"chess","stake":3,"status":"open","created_ms":1}]}""")
        assertEquals(DuelRoomStatus.unknown, odd.status)
        assertEquals(listOf("r"), odd.rooms?.map { it.id })
        // 본문: 있는 칸만 · p_protocol 은 언제나 맨 뒤.
        fun body(call: DuelRoomCall) = SwiftJson.encode(DuelRoomBody.serializer(), call.body)
        assertEquals("""{"p_game":"crossy_duel","p_protocol":1}""", body(DuelRoomCall.list(DuelRoomGame.crossyDuel)))
        assertEquals("""{"p_game":"chess","p_stake":5,"p_protocol":1}""", body(DuelRoomCall.open(DuelRoomGame.chess, 5)))
        assertEquals("""{"p_protocol":1}""", body(DuelRoomCall.ping))
        assertEquals("duel_room_join", DuelRoomCall.join("r").rpcName)
        assertEquals("루비가 모자라요 · 판돈 10", DuelRoomText.notice(DuelRoomStatus.insufficient, 10))
        assertEquals("3분째 기다림", DuelRoomText.waiting(190))
    }

    @Test
    fun rulesBlockJoinWithoutRubyAndWhenMyRoomIsOpenHere() = runTest {
        assertTrue(DuelRoomsRules.affordable(5, null))
        assertTrue(DuelRoomsRules.affordable(5, 5))
        assertFalse(DuelRoomsRules.affordable(10, 9))
        assertEquals(15.0, DuelRoomsRules.refreshSeconds, "맥 DuelRoomsTab 과 같은 주기")
        val script = Script()
        script.on("duel_rooms_list", fixture("list__ok"))
        val store = store(script)
        var balance: Long? = 100
        store.rubyBalanceSource = { balance }
        store.refresh(DuelRoomGame.reversi)
        assertEquals(true, store.doorOpen)
        val room = store.rooms(DuelRoomGame.reversi).first()
        assertTrue(DuelRoomsRules.canJoin(room, store, DuelRoomGame.reversi))
        balance = room.stake - 1
        assertFalse(DuelRoomsRules.canJoin(room, store, DuelRoomGame.reversi), "루비가 모자란데 [참가]가 켜졌다")
    }

    @Test
    fun doorClosedHidesTheSection() = runTest {
        val script = Script()
        script.on("duel_rooms_list", fixture("list__door_closed"))
        val store = store(script)
        store.refresh(DuelRoomGame.gomoku)
        assertEquals(false, store.doorOpen)
        assertFalse(store.isAvailable)
        assertTrue(store.rooms(DuelRoomGame.gomoku).isEmpty())
    }

    @Test
    fun hostBreathesEveryTwentySecondsAndAdoptsTheStartedMatchOnce() = runTest {
        val script = Script()
        script.on("duel_room_open", fixture("open__ok"))
        script.on("duel_room_ping", fixture("ping__open"), fixture("ping__started"))
        val store = store(script)
        val started = mutableListOf<Pair<DuelRoomGame, String>>()
        store.onRoomStarted = { g, id -> started += g to id }
        store.open(DuelRoomGame.reversi, 5)
        assertNotNull(store.myOpenRoom(DuelRoomGame.reversi))
        assertNotNull(store.myOpenRoomOtherThan(DuelRoomGame.gomoku), "다른 게임 로비에 '열어 두었어요' 한 줄이 안 선다")
        assertEquals(0, script.count("duel_room_ping"))
        advanceTimeBy(20_001)
        runCurrent()
        assertEquals(1, script.count("duel_room_ping"), "20초에 숨을 안 쉬었다")
        advanceTimeBy(20_001)
        runCurrent()
        assertEquals(listOf(DuelRoomGame.reversi to "87174e14-fce5-444f-a24e-2c393e516c75"), started)
        assertNull(store.myOpenRoom(DuelRoomGame.reversi), "시작된 방이 열린 방으로 남았다")
        advanceTimeBy(60_000)
        runCurrent()
        assertEquals(2, script.count("duel_room_ping"), "방이 시작됐는데 숨을 계속 쉰다")
        assertEquals(1, started.size, "같은 방의 시작을 두 번 받았다")
    }

    @Test
    fun gameSignalPingsAtMostOncePerSecondOnlyWhileMyRoomIsOpen() = runTest {
        val script = Script()
        script.on("duel_room_open", fixture("open__ok"))
        script.on("duel_room_ping", fixture("ping__open"))
        val store = store(script)
        store.handleGameSignal()
        runCurrent()
        assertEquals(0, script.count("duel_room_ping"), "방이 없는데 숨을 쉬었다")
        store.open(DuelRoomGame.reversi, 5)
        store.handleGameSignal()
        store.handleGameSignal()
        runCurrent()
        assertEquals(1, script.count("duel_room_ping"), "1초 안의 초인종 둘이 숨 둘이 됐다")
        advanceTimeBy(1_100)
        store.handleGameSignal()
        runCurrent()
        assertEquals(2, script.count("duel_room_ping"))
        store.reset()
        advanceUntilIdle()
    }

    @Test
    fun joinOkHandsTheMatchToTheGameAndRoomGoneSaysSoAndReloads() = runTest {
        val script = Script()
        script.on("duel_rooms_list", fixture("list__ok"), SwiftJson.decode(DuelRoomsResponse.serializer(), """{"status":"ok","rooms":[]}"""))
        script.on("duel_room_join", fixture("join__room_gone"))
        val store = store(script)
        val joined = mutableListOf<Pair<DuelRoomGame, String>>()
        store.onJoined = { g, id -> joined += g to id }
        store.refresh(DuelRoomGame.reversi)
        val room = store.rooms(DuelRoomGame.reversi).first()
        store.join(room)
        assertEquals(DuelRoomText.notice(DuelRoomStatus.roomGone), store.notice)
        assertTrue(store.rooms(DuelRoomGame.reversi).isEmpty())
        assertEquals(2, script.count("duel_rooms_list"), "닫힌 방 뒤에 목록을 다시 읽지 않았다")
        assertTrue(joined.isEmpty())

        val script2 = Script()
        script2.on("duel_rooms_list", fixture("list__ok"))
        script2.on("duel_room_join", fixture("join__ok"))
        val store2 = store(script2)
        store2.onJoined = { g, id -> joined += g to id }
        store2.refresh(DuelRoomGame.reversi)
        store2.join(store2.rooms(DuelRoomGame.reversi).first())
        assertEquals(1, joined.size)
        assertEquals(DuelRoomGame.reversi, joined.single().first)
        assertTrue(store2.rooms(DuelRoomGame.reversi).isEmpty())
        assertNull(store2.notice)
    }
}
