// 원본: Tests/checkTests/V0369RummyStoreTests.swift · V0369RummyV2StoreTests.swift · V0369RummyV2EngagedTests.swift · V0369RummyV2ExitVerifyTests.swift ·
//       V0369RummyRoomTransitionTests.swift · V0369RummyMidTurnForfeitTests.swift · V0369RummyVerifyV5Tests.swift · V0369RummyV2LobbyTests.swift:276(초대 줄) @ 1a5eeca6
//       (판돈 깃발 · 앱 수명 · 뒤로 가기 시험은 원본 없음 — 폰 몫)
package com.yehsung.aingcheck.core.stores.rummy

import com.yehsung.aingcheck.core.net.realtime.RealtimeState
import com.yehsung.aingcheck.core.rules.rummy.RummyCloseDecision
import com.yehsung.aingcheck.core.rules.rummy.RummyDropTarget
import com.yehsung.aingcheck.core.rules.rummy.RummyPhase
import com.yehsung.aingcheck.core.rules.rummy.RummyRackSlot
import com.yehsung.aingcheck.core.rules.rummy.RummyRackSort
import com.yehsung.aingcheck.core.rules.rummy.isJoker
import com.yehsung.aingcheck.core.rules.text.AingSticker
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.MemoryPrefs
import com.yehsung.aingcheck.core.stores.games.Reply
import com.yehsung.aingcheck.core.stores.games.StoreFixtures
import com.yehsung.aingcheck.core.stores.games.StoreHarness
import com.yehsung.aingcheck.core.stores.games.TestRummyHost
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyActionResponse
import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyLobby
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.games.RummyMatchStatus
import com.yehsung.aingcheck.core.wire.games.RummyPoint
import com.yehsung.aingcheck.core.wire.games.RummySeatState
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val ME = StoreFixtures.USER
private const val B = StoreFixtures.PEER
private const val C = StoreFixtures.OTHER
private const val MATCH_TEXT = "7e7e0000-0000-4000-8000-000000000068"
private const val ROOM_TEXT = "7e7e0000-0000-4000-8000-000000000069"
private const val OTHER_ROOM_TEXT = "7e7e0000-0000-4000-8000-00000000006a"
private const val NOW_MS = 1_800_000_000_000L

private val MATCH = SwiftUUID.parse(MATCH_TEXT)!!
private val ROOM = SwiftUUID.parse(ROOM_TEXT)!!
private val PEER_B = SwiftUUID.parse(B)!!
private val PEER_C = SwiftUUID.parse(C)!!
private val WALL0 = SwiftDate(1_800_000_000.0)
private val RACK = listOf("A10", "A11", "A12", "B5", "C9", "J", "D1", "D2", "B13", "C1", "A3", "B7", "C7", "D7")

private fun strings(items: List<String>) = items.joinToString(",", "[", "]") { "\"$it\"" }
private fun tableJson(table: List<List<String>>) = table.joinToString(",", "[", "]") { strings(it) }
private fun opt(value: Any?) = value?.toString() ?: "null"
private fun quoted(value: String?) = value?.let { "\"$it\"" } ?: "null"
private fun faces(vararg texts: String): List<RummyFace> = texts.map { RummyFace.of(it)!! }

private fun seat(no: Long?, user: String, name: String, state: String, rackCount: Long = 14, forfeitOrder: Long? = null) =
    """{"seat_no":${opt(no)},"user_id":"$user","display_name":"$name","state":"$state","rack_count":$rackCount,"initial_done":false,"timeout_streak":0,"forfeit_order":${opt(forfeitOrder)}}"""

private fun stateJson(
    status: String = "active", id: String = MATCH_TEXT, seq: Long = 1, turnSeat: Long? = 0, mySeat: Long? = 0,
    myRack: List<String>? = RACK, table: List<List<String>> = emptyList(), draft: String? = null, seats: List<String>? = null,
    nowMs: Long = NOW_MS, deadlineMs: Long? = null, expiresMs: Long? = null, endReason: String? = null, host: String = ME,
    turnStartedMs: Long? = null, tableLayout: String? = null, reactions: String? = null, initialDone: Boolean = false,
): String {
    val active = status == "active"
    val defaults = if (status == "forming") {
        listOf(seat(0, ME, "나", "joined", 0))
    } else {
        listOf(seat(0, ME, "나", "playing"), seat(1, B, "비", "playing"))
    }
    return """{"id":"$id","status":"$status","host_id":"$host","stake":5,"is_public":false,"max_seats":4,"server_now_ms":$nowMs,"seq":$seq,""" +
        """"expires_at_ms":${opt(if (status == "forming") (expiresMs ?: (nowMs + 600_000)) else null)},""" +
        """"seats":[${(seats ?: defaults).joinToString(",")}],"my_seat_no":${opt(mySeat)},""" +
        """"my_rack":${if (active && myRack != null) strings(myRack) else "null"},"my_initial_done":$initialDone,""" +
        """"table":${tableJson(table)},"table_layout":${tableLayout ?: "null"},"pool_count":78,""" +
        """"turn_seat_no":${opt(if (active) turnSeat else null)},"turn_started_ms":${opt(if (active) (turnStartedMs ?: nowMs) else null)},""" +
        """"turn_deadline_ms":${opt(if (active) (deadlineMs ?: (nowMs + 60_000)) else null)},"grace_ms":2000,""" +
        """"draft":${draft ?: "null"},"end_reason":${quoted(endReason)},"finished_at_ms":${opt(if (status == "finished") nowMs else null)},""" +
        """"reactions":${reactions ?: "[]"}}"""
}

private fun envelope(status: String = "ok", state: String? = null, extra: String = "") =
    """{"status":"$status"${state?.let { ""","state":$it""" } ?: ""}$extra,"server_now_ms":$NOW_MS}"""

private fun draftJson(table: List<List<String>>, draftSeq: Long, layout: String? = null) =
    """{"table":${tableJson(table)},"layout":${layout ?: "null"},"draft_seq":$draftSeq,"at_ms":$NOW_MS}"""

private fun roomJson(id: String = ROOM_TEXT, host: String = B, hostName: String = "비", isPublic: Boolean = false, extraSeats: List<String> = emptyList()): String {
    val seats = (listOf("""{"user_id":"$host","display_name":"$hostName","state":"joined","seat_no":0}""") + extraSeats).joinToString(",")
    return """{"id":"$id","host":{"id":"$host","display_name":"$hostName"},"stake":5,"is_public":$isPublic,"expires_at_ms":${NOW_MS + 600_000},"max_seats":4,"seats":[$seats]}"""
}

private fun lobbyJson(
    room: String? = null, active: String? = null, invites: List<String> = emptyList(), publicRooms: List<String> = emptyList(), ruby: Long = 120,
): String {
    val users = """{"id":"$B","display_name":"비","is_working":true,"in_match":false,"capable":true},{"id":"$C","display_name":"씨","is_working":true,"in_match":false,"capable":true}"""
    return """{"status":"ok","server_now_ms":$NOW_MS,"stakes":[3,5,10],"turn_seconds":60,"room_ttl_seconds":600,""" +
        """"me":{"ruby_balance":$ruby,"games":4,"wins":1,"room":${room ?: "null"},"active_match_id":${quoted(active)}},""" +
        """"invites":[${invites.joinToString(",")}],"public_rooms":[${publicRooms.joinToString(",")}],"users":[$users]}"""
}

private fun decodeState(text: String): RummyMatchState = SwiftJson.decode(RummyMatchState.serializer(), text)

/** rpc 이름별 응답 스크립트: 줄 세운 응답이 먼저, 그다음 고정 응답(Swift `RKScript`). */
private class Script {
    private val queued = HashMap<String, ArrayDeque<Reply>>()
    private val standing = HashMap<String, Reply>()

    fun enqueue(rpc: String, reply: Reply) {
        queued.getOrPut(rpc) { ArrayDeque() }.addLast(reply)
    }

    fun enqueue(rpc: String, body: String) = enqueue(rpc, Reply.Json(body))

    fun stand(rpc: String, reply: Reply) {
        standing[rpc] = reply
    }

    fun stand(rpc: String, body: String) = stand(rpc, Reply.Json(body))

    fun route(r: RecordedRequest): Reply? {
        val rpc = r.rpcName ?: return null
        return queued[rpc]?.removeFirstOrNull() ?: standing[rpc]
    }
}

private class Tally {
    var presents = 0
    var dismisses = 0
    var attentionRequests = 0
    val attentions = mutableListOf<String>()
    val arrived = mutableListOf<SwiftUUID>()
    var finished = 0
}

private class Rig(val h: StoreHarness, val host: TestRummyHost, val store: RummyStore, val script: Script) {
    var wall: SwiftDate = WALL0
    val tally = Tally()

    fun count(rpc: String): Int = h.server.count(rpc)

    fun bodies(rpc: String): List<JsonObject> = h.server.bodies(rpc).map { Json.parseToJsonElement(it).jsonObject }

    fun tableOf(body: JsonObject): List<List<String>> =
        body.getValue("p_table").jsonArray.map { row -> row.jsonArray.map { it.jsonPrimitive.content } }

    /** 재운 시험 기본값의 스토어 하나 더(앱 재실행 재현 — 같은 서버 · 같은 세션). */
    fun another(host: TestRummyHost = this.host): RummyStore = RummyStore(h.storeScope, host).also {
        it.clock = { wall }
        it.pollStepSeconds = Double.POSITIVE_INFINITY
        it.deadlineWakeEnabled = false
        it.heartbeatEnabled = false
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
private suspend fun TestScope.rig(enabled: Boolean = true, lobby: String = lobbyJson(active = MATCH_TEXT)): Rig {
    val script = Script()
    script.stand("rummy_lobby", lobby)
    val config = AppConfig(duelsEnabled = enabled)
    val h = StoreHarness(this, config, route = script::route)
    h.signIn()
    lateinit var made: Rig
    val host = TestRummyHost(h.sessionStore, config) { made.wall }
    val store = RummyStore(h.storeScope, host)
    made = Rig(h, host, store, script)
    store.clock = { made.wall }
    store.pollStepSeconds = Double.POSITIVE_INFINITY
    store.deadlineWakeEnabled = false
    store.heartbeatEnabled = false
    val tally = made.tally
    store.presentWindow = { tally.presents += 1 }
    store.dismissWindow = { tally.dismisses += 1 }
    store.requestAttention = { tally.attentionRequests += 1 }
    store.onAttention = { tally.attentions += it }
    store.onInviteArrived = { tally.arrived += it.id }
    store.onMatchFinished = { tally.finished += 1 }
    return made
}

/** 첫 등록 30점 세트(A10·A11·A12 = 33점)를 끌어 놓는다. */
private fun playInitialMeld(store: RummyStore) {
    val editor = store.editor!!
    val ids = listOf("A10", "A11", "A12").map { text -> editor.rack.first { it.face.text == text }.id }
    store.moveTile(ids[0], RummyDropTarget.NewMeld)
    val meld = store.editor!!.melds.size - 1
    store.moveTile(ids[1], RummyDropTarget.Meld(meld, null))
    store.moveTile(ids[2], RummyDropTarget.Meld(meld, null))
}

/**
 * 스토어 규약 ①~⑯ 를 결과로 잰다. 서버는 스텁이고 벽시계는 주입이다 — 폴링은 무한으로 재우고 `pollTick` · `checkDeadline` 을 직접 밟는다.
 * 각 시험 첫 줄 주석은 Swift 관례 그대로 "없으면 어떤 결함이 초록으로 통과하는가" 다.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RummyStoreTest {
    // MARK: 흐름

    @Test
    fun fullFlowFromLobbyThroughRoomMatchResultBackToLobby() = runTest {
        // 없으면: 각 단계가 따로는 초록인데 이어 붙이면 phase·편집기·알림이 어긋나는 결함이 남는다.
        val r = rig(lobby = lobbyJson())
        val store = r.store
        store.refreshLobby()
        assertEquals(RummyPhase.lobby, store.phase)
        assertEquals(2, store.lobby?.users?.size)
        assertEquals(1L, store.lobby?.me?.wins)
        assertEquals(120L, store.rubyBalance)
        assertEquals(120L, r.host.rubyBalance, "호스트 거울도 같은 칸")

        // 방 만들기 — ok{match_id} 뒤 state 를 읽어 방으로.
        store.selectedStake = 5
        store.createPublic = true
        r.script.enqueue("rummy_create", """{"status":"ok","match_id":"$MATCH_TEXT"}""")
        r.script.stand("rummy_state", envelope(state = stateJson("forming", seq = 0)))
        r.script.stand("rummy_lobby", lobbyJson(active = MATCH_TEXT))
        store.createRoom()
        assertTrue(store.isWorking)
        store.actionJob?.join()
        assertFalse(store.isWorking)
        assertEquals(RummyPhase.room, store.phase)
        assertEquals(MATCH, store.match?.id)
        val create = r.bodies("rummy_create").single()
        assertEquals("5", create.getValue("p_stake").jsonPrimitive.content)
        assertEquals("true", create.getValue("p_public").jsonPrimitive.content)
        assertTrue(abs((store.roomRemaining(WALL0) ?: 0.0) - 600) < 0.01)
        assertEquals(MATCH, store.myRoom?.id, "방 카드는 30초 로비 폴링을 안 기다린다")

        // 초대 — ok 뒤 방 state 다시(초대 자리가 보인다).
        val invited = listOf(seat(0, ME, "나", "joined", 0), seat(null, B, "비", "invited", 0))
        r.script.enqueue("rummy_invite", """{"status":"ok"}""")
        r.script.stand("rummy_state", envelope(state = stateJson("forming", seq = 0, seats = invited)))
        store.invite(PEER_B)
        store.actionJob?.join()
        assertEquals(RummyNoticeText.invited, store.notice)
        assertEquals(2, store.match?.seats?.size)

        // 비가 참가 — 초인종 한 번이 방 state 를 다시 읽는다.
        val joined = listOf(seat(0, ME, "나", "joined", 0), seat(1, B, "비", "joined", 0))
        r.script.stand("rummy_state", envelope(state = stateJson("forming", seq = 0, seats = joined)))
        store.handleSignal()
        runCurrent()
        assertEquals(RummySeatState.joined, store.match?.seats?.last()?.state)
        assertEquals(1L, store.match?.seats?.last()?.seatNo)

        // 시작 — 판으로. 창이 안 보이니 창 띄우기 + 주의 + 말풍선(내 차례).
        r.script.enqueue("rummy_start", envelope(state = stateJson(seq = 1)))
        store.startGame()
        store.actionJob?.join()
        assertEquals(RummyPhase.playing, store.phase)
        assertTrue(store.isMyTurn)
        assertEquals(RACK.map { RummyFace.of(it)!! }, store.editor?.rackFaces)
        assertEquals(1L, store.editorSeq)
        assertEquals(1, r.tally.presents)
        assertEquals(1, r.tally.attentionRequests)
        assertEquals(listOf(RummyNoticeText.myTurnAttention), r.tally.attentions)
        assertTrue(abs((store.turnRemaining(WALL0) ?: 0.0) - 60) < 0.01)

        // 내 차례 완료 — seq 2(비 차례)로.
        playInitialMeld(store)
        val played = listOf(listOf("A10", "A11", "A12"))
        val rest = RACK.drop(3)
        r.script.enqueue("rummy_play", envelope(state = stateJson(seq = 2, turnSeat = 1, myRack = rest, table = played, turnStartedMs = NOW_MS + 1)))
        store.submitTurn()
        store.actionJob?.join()
        val play = r.bodies("rummy_play").single()
        assertEquals("1", play.getValue("p_expected_seq").jsonPrimitive.content)
        assertEquals(played, r.tableOf(play))
        assertEquals(2L, store.match?.seq)
        assertFalse(store.isMyTurn)
        assertEquals(2L, store.editorSeq)
        assertEquals(rest.map { RummyFace.of(it)!! }.toSet(), store.editor?.rackFaces?.toSet())
        assertNull(store.otherDraft)

        // 비가 놓는 중 — 남의 작업 판이 보인다.
        val otherWork = played + listOf(listOf("B1", "B2", "B3"))
        r.script.stand("rummy_state", envelope(state = stateJson(seq = 2, turnSeat = 1, myRack = rest, table = played, turnStartedMs = NOW_MS + 1, draft = draftJson(otherWork, 1))))
        store.handleSignal()
        runCurrent()
        assertEquals(otherWork.map { row -> row.map { RummyFace.of(it)!! } }, store.otherDraft)
        assertEquals(played.map { row -> row.map { RummyFace.of(it)!! } }, store.match?.table)

        // 끝 — 결과로, onMatchFinished 는 한 번.
        val done = listOf(seat(0, ME, "나", "done", 11), seat(1, B, "비", "done", 0))
        val finished = stateJson("finished", seq = 3, seats = done, endReason = "rack_empty")
        r.script.stand("rummy_state", envelope(state = finished))
        store.handleSignal()
        runCurrent()
        assertEquals(RummyPhase.finished, store.phase)
        assertNull(store.editor)
        assertEquals(1, r.tally.finished)
        store.handleSignal() // 끝난 판의 초인종은 로비로 간다 — 같은 판을 다시 알리지 않는다.
        runCurrent()
        assertEquals(1, r.tally.finished)

        // [로비로] — 그 판은 다시 끌려오지 않는다.
        store.dismissResult()
        assertEquals(RummyPhase.lobby, store.phase)
        assertNull(store.match)
        assertEquals(RummyStateApplyOutcome.ignored, store.applyState(decodeState(finished)))
        assertNull(store.match)
        runCurrent()
        r.h.assertClean()
    }

    // MARK: 늦은 응답(세대 · seq · 요청 표)

    @Test
    fun staleSnapshotsAreIgnored() = runTest {
        // 없으면: 폴링 응답이 완료 응답보다 늦게 닿아 판이 한 차례 전으로 되돌아가는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        assertEquals(RummyStateApplyOutcome.applied, store.applyState(decodeState(stateJson(seq = 3, turnSeat = 1))))
        assertEquals(RummyStateApplyOutcome.ignored, store.applyState(decodeState(stateJson(seq = 2, turnSeat = 0))))
        assertEquals(3L, store.match?.seq)

        val newer = draftJson(listOf(listOf("B1", "B2", "B3")), 5)
        val older = draftJson(listOf(listOf("B9")), 4)
        assertEquals(RummyStateApplyOutcome.applied, store.applyState(decodeState(stateJson(seq = 3, turnSeat = 1, draft = newer))))
        assertEquals(RummyStateApplyOutcome.ignored, store.applyState(decodeState(stateJson(seq = 3, turnSeat = 1, draft = older))))
        assertEquals(listOf(faces("B1", "B2", "B3")), store.otherDraft)

        // forming 방은 seq 가 안 오른다 — 요청 표로 가린다.
        val room = r.another()
        val two = listOf(seat(0, ME, "나", "joined", 0), seat(1, B, "비", "joined", 0))
        assertEquals(RummyStateApplyOutcome.applied, room.applyState(decodeState(stateJson("forming", seq = 0, seats = two)), 10))
        assertEquals(RummyStateApplyOutcome.ignored, room.applyState(decodeState(stateJson("forming", seq = 0)), 9))
        assertEquals(2, room.match?.seats?.size)

        // 다른 방의 옛 표도 버린다(방을 옮긴 뒤 늦게 온 옛 방의 응답).
        assertEquals(RummyStateApplyOutcome.ignored, room.applyState(decodeState(stateJson("forming", id = ROOM_TEXT, seq = 0)), 9))
        assertEquals(MATCH, room.match?.id)

        // 끝난 판에 진행 중 응답.
        assertEquals(RummyStateApplyOutcome.applied, store.applyState(decodeState(stateJson("finished", seq = 4, endReason = "blocked"))))
        assertEquals(RummyStateApplyOutcome.ignored, store.applyState(decodeState(stateJson(seq = 4))))
        assertEquals(RummyMatchStatus.finished, store.match?.status)
    }

    @Test
    fun responsesAfterResetAreDropped() = runTest {
        // 없으면: 로그아웃 직전에 나간 로비가 다음 사람의 화면에 앞 사람의 초대·방을 채우는 결함이 초록이 된다.
        val r = rig()
        val gate = CompletableDeferred<Unit>()
        r.script.stand("rummy_lobby", Reply.Gate(gate, Reply.Json(lobbyJson(invites = listOf(roomJson())))))
        val pending = launch { r.store.refreshLobby() }
        runCurrent()
        assertEquals(1, r.count("rummy_lobby"))
        r.store.reset()
        gate.complete(Unit)
        pending.join()
        assertNull(r.store.lobby)
        assertTrue(r.tally.arrived.isEmpty())
        assertEquals(1, r.tally.dismisses)
        assertEquals(RummyPhase.lobby, r.store.phase)
        assertFalse(r.store.lobbyInFlight, "다음 사람의 첫 로비가 막히지 않는다")
    }

    @Test
    fun lateDraftAnswerAfterResetTouchesNothing() = runTest {
        // 없으면: 로그아웃 뒤 닿은 작업 판 응답이 비운 스토어에 앞 판을 되살리는 결함이 초록이 된다.
        val r = rig()
        val gate = CompletableDeferred<Unit>()
        r.script.enqueue("rummy_draft", Reply.Gate(gate, Reply.Json(envelope("stale", state = stateJson(seq = 9, turnSeat = 1)))))
        r.store.applyState(decodeState(stateJson(seq = 1)))
        playInitialMeld(r.store)
        advanceTimeBy(260)
        runCurrent()
        assertTrue(r.store.draftInFlight)
        r.store.reset()
        assertFalse(r.store.draftInFlight)
        gate.complete(Unit)
        runCurrent()
        assertNull(r.store.match)
        assertNull(r.store.editor)
    }

    @Test
    fun cancelledPollCannotJamTheInFlightFlag() = runTest {
        // 없으면(Kotlin 몫): 폴링 잡이 조회 중에 취소되면 perform 이 취소를 다시 던져 비행 깃발이 선 채로 남고, 그 뒤 state 조회가 영영 안 나간다.
        val r = rig()
        val store = r.store
        store.applyState(decodeState(stateJson("forming", seq = 0)))
        store.lastStateRequestAt = WALL0
        store.lastLobbyRequestAt = WALL0
        store.pollStepSeconds = 1.0
        val gate = CompletableDeferred<Unit>()
        r.script.enqueue("rummy_state", Reply.Gate(gate, Reply.Json(envelope(state = stateJson("forming", seq = 0)))))
        r.script.stand("rummy_state", envelope(state = stateJson("forming", seq = 0)))
        store.setWindowVisible(true)
        r.wall = WALL0.addingTimeInterval(6.0)
        advanceTimeBy(1_001)
        runCurrent()
        assertTrue(store.stateInFlight, "전제: 폴링 잡 안에서 조회가 떠 있다")
        store.setWindowVisible(false)
        runCurrent()
        assertFalse(store.stateInFlight, "취소된 조회가 깃발을 세운 채 남겼다")
        store.refreshMatch(MATCH)
        assertEquals(2, r.count("rummy_state"), "그 뒤 조회가 나간다")
    }

    // MARK: 편집기

    @Test
    fun editorSurvivesSameTurnAndRebuildsOnNewTurn() = runTest {
        // 없으면: 내 draft 의 메아리·5초 폴링이 끌어 놓던 작업을 매번 지우는 결함이 초록이 된다.
        val store = rig().store
        store.applyState(decodeState(stateJson(seq = 1, myRack = listOf("A1", "A2", "A3"))))
        assertEquals(faces("A1", "A2", "A3"), store.editor?.rackFaces)
        // 같은 seq(서버 랙이 달라 보여도 = 다시 세웠다면 드러난다) — 그대로.
        store.applyState(decodeState(stateJson(seq = 1, myRack = listOf("D9"), draft = draftJson(listOf(listOf("A1")), 1))))
        assertEquals(faces("A1", "A2", "A3"), store.editor?.rackFaces)
        assertEquals(1L, store.editorSeq)
        // 차례가 바뀌었다 — 새 랙으로.
        store.applyState(decodeState(stateJson(seq = 2, turnSeat = 1, myRack = listOf("A1", "A2", "A3", "C4"))))
        assertEquals(2L, store.editorSeq)
        assertEquals(faces("A1", "A2", "A3", "C4").toSet(), store.editor?.rackFaces?.toSet())
        // 기권한 자리 — 편집기 없음, 내 차례도 아님.
        val forfeited = listOf(seat(0, ME, "나", "forfeit", 0, 1), seat(1, B, "비", "playing"), seat(2, C, "씨", "playing"))
        store.applyState(decodeState(stateJson(seq = 3, turnSeat = 0, myRack = null, seats = forfeited)))
        assertNull(store.editor)
        assertFalse(store.isMyTurn)
        assertEquals(RummyPhase.playing, store.phase)
    }

    @Test
    fun rackArrangementSurvivesTurnChange() = runTest {
        // 없으면: 차례가 돌 때마다 내가 정리한 랙이 서버 순서로 흐트러지는 결함이 초록이 된다.
        val store = rig().store
        store.applyState(decodeState(stateJson(seq = 1, myRack = listOf("C9", "A5", "J", "B3"))))
        val joker = store.editor!!.rack.first { it.face.isJoker }.id
        store.moveTile(joker, RummyDropTarget.Rack(0))
        assertEquals(faces("J", "C9", "A5", "B3"), store.editor?.rackFaces)
        store.applyState(decodeState(stateJson(seq = 2, turnSeat = 1, myRack = listOf("A5", "B3", "C9", "J", "D1"))))
        assertEquals(faces("J", "C9", "A5", "B3", "D1"), store.editor?.rackFaces)
    }

    @Test
    fun notMyTurnRejectsTurnActions() = runTest {
        // 없으면: 남의 차례에 완료·뽑기를 보내 서버 not_your_turn 만 쌓는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        store.applyState(decodeState(stateJson(seq = 4, turnSeat = 1)))
        val before = store.editor
        val tile = store.editor!!.rack.first().id
        store.moveTile(tile, RummyDropTarget.NewMeld)
        store.resetTurn()
        store.submitTurn()
        store.drawTile()
        advanceTimeBy(500)
        runCurrent()
        assertEquals(before, store.editor)
        assertNull(store.actionJob)
        assertEquals(0, r.count("rummy_play") + r.count("rummy_draw") + r.count("rummy_draft"))
    }

    @Test
    fun otherSeatForfeitKeepsMyWorkAndDoesNotReannounce() = runTest {
        // 없으면: 남이 기권할 때마다(seq+1) 내 차례 작업이 지워지고 '내 차례' 말풍선이 다시 뜨는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        val three = listOf(seat(0, ME, "나", "playing"), seat(1, B, "비", "playing"), seat(2, C, "씨", "playing"))
        store.applyState(decodeState(stateJson(seq = 5, seats = three, table = listOf(listOf("D1", "D2", "D3")), myRack = listOf("A10", "A11", "A12", "B5", "C9"))))
        assertTrue(store.isMyTurn)
        val startAttentions = r.tally.attentions.size
        playInitialMeld(store)
        val worked = store.editor!!.submissionTable
        assertEquals(2, worked.size)
        store.cancelDraft() // 위 끌기의 디바운스는 이미 서버에 닿았다고 친다(서버 draft = echo)

        // 씨가 나갔다: seq 6 · 차례 0 그대로 · 마감 그대로 · draft = 내가 보낸 작업 판.
        val after = listOf(seat(0, ME, "나", "playing"), seat(1, B, "비", "playing"), seat(2, C, "씨", "forfeit", 0, 1))
        val echo = draftJson(listOf(listOf("D1", "D2", "D3"), listOf("A10", "A11", "A12")), 3)
        assertEquals(
            RummyStateApplyOutcome.applied,
            store.applyState(decodeState(stateJson(seq = 6, seats = after, draft = echo, table = listOf(listOf("D1", "D2", "D3")), myRack = listOf("A10", "A11", "A12", "B5", "C9")))),
        )
        assertNull(store.draftDebounceJob, "서버가 이미 든 내 작업 판 위에 되돌린 시작 판을 다시 보내려 한다")
        assertTrue(store.isMyTurn)
        assertEquals(worked, store.editor?.submissionTable, "남의 기권(seq+1)으로 내 차례 작업 판이 지워졌다")
        assertEquals(2, store.editor?.rackFaces?.size)
        assertEquals(startAttentions, r.tally.attentions.size, "같은 차례의 '내 차례' 말풍선이 다시 떴다")
    }

    // MARK: 작업 상태 전송

    @Test
    fun midTurnEditorResyncsOnceOnEngagedDeviceOnly() = runTest {
        // 없으면: 앱을 다시 켠 사람의 화면엔 없는 옛 작업 판을 서버가 시간 초과 때 대신 내는 결함이 초록이 된다.
        val r = rig()
        r.script.stand("rummy_draft", """{"status":"ok","draft_seq":3}""")
        val store = r.store
        store.markEngaged(MATCH) // 앱을 다시 켠 **이 판을 하던 기기**
        val stale = draftJson(listOf(listOf("A1", "A2", "A3")), 2)
        store.applyState(decodeState(stateJson(seq = 6, draft = stale)))
        assertEquals(0, r.count("rummy_draft"), "디바운스 전")
        assertNotNull(store.draftDebounceJob)
        advanceTimeBy(260)
        runCurrent()
        val call = r.bodies("rummy_draft").single()
        assertEquals("6", call.getValue("p_expected_seq").jsonPrimitive.content)
        assertEquals(emptyList(), r.tableOf(call))
        // 되돌리기를 거듭해도 서버가 든 판과 같으면 다시 보내지 않는다.
        store.resetTurn()
        store.resetTurn()
        advanceTimeBy(500)
        runCurrent()
        assertEquals(1, r.count("rummy_draft"))

        // 놀던 기기: 그 작업 판은 다른 기기가 지금 만드는 것이다 — 되돌리지 않고 engaged 도 안 된다.
        val idle = rig()
        idle.script.stand("rummy_draft", """{"status":"ok"}""")
        idle.store.applyState(decodeState(stateJson(seq = 6, draft = stale)))
        advanceTimeBy(500)
        runCurrent()
        assertEquals(0, idle.count("rummy_draft"), "놀던 기기가 다른 기기의 작업 판을 되돌려 보냈다")
        assertFalse(idle.store.isEngaged(MATCH))
    }

    @Test
    fun draftIsSingleFlightAndStaleAdoptsCarriedState() = runTest {
        // 없으면: 끌 때마다 요청이 겹쳐 나가 서버에 순서가 뒤집힌 작업 판이 남는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        val gate = CompletableDeferred<Unit>()
        r.script.enqueue("rummy_draft", Reply.Gate(gate, Reply.Json(envelope("stale", state = stateJson(seq = 7, turnSeat = 1)))))
        store.markEngaged(MATCH)
        store.applyState(decodeState(stateJson(seq = 6, draft = draftJson(listOf(listOf("A1", "A2", "A3")), 2))))
        advanceTimeBy(260)
        runCurrent()
        assertTrue(store.draftInFlight)
        assertEquals(1, r.count("rummy_draft"))
        store.flushDraft()
        store.flushDraft()
        runCurrent()
        assertEquals(1, r.count("rummy_draft"))
        gate.complete(Unit)
        runCurrent()
        assertEquals(1, r.count("rummy_draft"))
        assertEquals(7L, store.match?.seq)
        assertEquals(7L, store.editorSeq)
        assertFalse(store.isMyTurn)
    }

    @Test
    fun draftDebounces250msAndSendsLatestOnceAfterFlight() = runTest {
        // 없으면: 끌기 한 번마다 요청이 나가거나(폭주), 비행 중 마지막 끌기를 잃어 서버가 옛 판으로 시간 초과 판정하는 결함이 초록이 된다.
        val r = rig()
        r.script.stand("rummy_draft", """{"status":"ok","draft_seq":1}""")
        val store = r.store
        store.applyState(decodeState(stateJson(seq = 1)))
        playInitialMeld(store)
        advanceTimeBy(249)
        runCurrent()
        assertEquals(0, r.count("rummy_draft"), "250ms 전에 나갔다")
        advanceTimeBy(2)
        runCurrent()
        assertEquals(1, r.count("rummy_draft"))
        assertEquals(listOf(listOf("A10", "A11", "A12")), r.tableOf(r.bodies("rummy_draft").last()))
        assertTrue(store.isEngaged(MATCH), "작업 판을 보낸 판은 손댄 판이다")

        // 비행 중 바뀐 것: 느린 응답 하나 → 그 사이 끌기 → 끝난 뒤 최신 판 한 번.
        val gate = CompletableDeferred<Unit>()
        r.script.enqueue("rummy_draft", Reply.Gate(gate, Reply.Json("""{"status":"ok","draft_seq":2}""")))
        val b5 = store.editor!!.rack.first { it.face.text == "B5" }.id
        store.moveTile(b5, RummyDropTarget.NewMeld)
        advanceTimeBy(260)
        runCurrent()
        assertTrue(store.draftInFlight)
        store.moveTile(b5, RummyDropTarget.Meld(0, null))
        advanceTimeBy(260)
        runCurrent()
        assertEquals(2, r.count("rummy_draft"), "비행 중인데 또 나갔다")
        gate.complete(Unit)
        runCurrent()
        assertEquals(3, r.count("rummy_draft"))
        assertEquals(listOf(listOf("A10", "A11", "A12", "B5")), r.tableOf(r.bodies("rummy_draft").last()))
    }

    @Test
    fun staleDraftOnSameTurnResendsWithNewSeq() = runTest {
        // 없으면: 남의 기권으로 seq 만 오른 차례에 서버가 내 작업 판을 버린 채로 남아 시간 초과 때 옛 판이 판정되는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        r.script.enqueue("rummy_draft", envelope("stale", state = stateJson(seq = 2)))
        r.script.stand("rummy_draft", """{"status":"ok"}""")
        store.applyState(decodeState(stateJson(seq = 1)))
        playInitialMeld(store)
        advanceTimeBy(260)
        runCurrent()
        assertEquals(2L, store.match?.seq)
        assertEquals(1, store.editor?.melds?.size, "같은 차례 — 작업은 남는다")
        advanceTimeBy(260)
        runCurrent()
        assertEquals(listOf("1", "2"), r.bodies("rummy_draft").map { it.getValue("p_expected_seq").jsonPrimitive.content })
    }

    @Test
    fun failedDraftRetriesBoundedAndFailedSubmitRearmsTheDraft() = runTest {
        // 없으면: 연결이 잠깐 끊긴 사이 낸 작업 판이 서버에 영영 안 닿거나, 끝없이 재시도해 서버를 두드리는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        r.script.stand("rummy_draft", Reply.Offline)
        store.applyState(decodeState(stateJson(seq = 1)))
        playInitialMeld(store)
        advanceTimeBy(20_000)
        runCurrent()
        assertEquals(1 + RummyStore.draftRetryLimit, r.count("rummy_draft"), "상한까지만 다시 보낸다")

        // 완료가 실패하면 디바운스로 걷힌 마지막 작업 판을 다시 보낸다(V5-D7).
        val fresh = rig()
        fresh.script.stand("rummy_draft", """{"status":"ok"}""")
        fresh.script.stand("rummy_play", Reply.Offline)
        fresh.store.applyState(decodeState(stateJson(seq = 1)))
        playInitialMeld(fresh.store)
        fresh.store.submitTurn()
        assertEquals(0, fresh.count("rummy_draft"), "확정이 작업 상태를 대신한다")
        fresh.store.actionJob?.join()
        assertEquals(RummyNoticeText.checkConnection, fresh.store.notice)
        advanceTimeBy(260)
        runCurrent()
        assertEquals(1, fresh.count("rummy_draft"), "걷었던 작업 판을 다시 걸지 않았다")
    }

    @Test
    fun draftAndPlayCarryLayoutAndSameLayoutIsNotResent() = runTest {
        // 없으면: 내가 옮긴 묶음 위치가 서버로 안 가 남들 화면·확정 판에서 제자리로 돌아가는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        r.script.stand("rummy_draft", """{"status":"ok","draft_seq":1}""")
        val table = listOf(listOf("A1", "A2", "A3"))
        store.applyState(decodeState(stateJson(seq = 1, table = table, tableLayout = "[[0,0]]", myRack = listOf("A4", "B9", "C2", "D13", "J"), initialDone = true)))
        store.moveSet(0, RummyPoint(400, 400))
        advanceTimeBy(260)
        runCurrent()
        val first = r.bodies("rummy_draft").single()
        assertEquals("[[400,400]]", first.getValue("p_layout").toString())
        assertEquals(table, r.tableOf(first))
        // 같은 자리로 다시 옮기면 보낼 것이 없다.
        store.moveSet(0, RummyPoint(400, 400))
        store.scheduleDraft()
        advanceTimeBy(260)
        runCurrent()
        assertEquals(1, r.count("rummy_draft"))
        // 랙 타일을 세트에 붙여 [완료] → rummy_play 도 배치를 싣는다.
        val a4 = store.editor!!.rack.first { it.face.text == "A4" }.id
        store.moveTile(a4, RummyDropTarget.Meld(0, null))
        r.script.stand(
            "rummy_play",
            envelope(state = stateJson(seq = 2, turnSeat = 1, turnStartedMs = NOW_MS + 1, myRack = listOf("B9", "C2", "D13", "J"), table = listOf(listOf("A1", "A2", "A3", "A4")), tableLayout = "[[400,400]]", initialDone = true)),
        )
        store.submitTurn()
        store.actionJob?.join()
        assertEquals("[[400,400]]", r.bodies("rummy_play").single().getValue("p_layout").toString())
        assertEquals(listOf(RummyPoint(400, 400)), store.confirmedLayout.points)
    }

    // MARK: 차례 동작

    @Test
    fun rejectedPlayKeepsWorkAndDrawSendsSeq() = runTest {
        // 없으면: 서버가 거절한 판을 고치려는데 편집기가 시작 판으로 날아가거나, 이유 대신 뭉뚱그린 문구가 뜨는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        r.script.stand("rummy_draft", """{"status":"ok","draft_seq":1}""")
        store.applyState(decodeState(stateJson(seq = 5)))
        playInitialMeld(store)
        val working = store.editor
        r.script.enqueue("rummy_play", envelope("rejected", state = stateJson(seq = 5), extra = ""","reason":"invalid_meld""""))
        store.submitTurn()
        store.actionJob?.join()
        assertEquals(1, r.count("rummy_play"))
        assertEquals("맞지 않는 묶음이 있어요.", store.notice)
        assertEquals(working, store.editor)
        assertEquals(5L, store.editorSeq)

        r.script.enqueue("rummy_draw", envelope(state = stateJson(seq = 6, turnSeat = 1, myRack = RACK + "C13")))
        store.drawTile()
        store.actionJob?.join()
        assertEquals("5", r.bodies("rummy_draw").single().getValue("p_expected_seq").jsonPrimitive.content)
        assertEquals(6L, store.match?.seq)
        assertEquals(15, store.editor?.rackFaces?.size)
        assertNull(store.notice)
    }

    @Test
    fun submitBlockedLocallyWhenEditorRejects() = runTest {
        // 없으면: [완료] 연타가 서버 거절만 쌓는 결함이 초록이 된다.
        val r = rig()
        r.store.applyState(decodeState(stateJson(seq = 1)))
        r.store.submitTurn()
        advanceTimeBy(100)
        runCurrent()
        assertEquals(0, r.count("rummy_play"))
        assertEquals("내 타일을 1개 이상 내야 해요.", r.store.notice)
    }

    @Test
    fun stalePlayWhileStillMyTurnSaysTableChangedAndStartStaleSaysTryAgain() = runTest {
        // 없으면: 시간이 남았는데 "차례가 넘어갔어요" 라고 말해 사람이 판을 놓는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        r.script.stand("rummy_draft", """{"status":"ok"}""")
        store.applyState(decodeState(stateJson(seq = 1)))
        playInitialMeld(store)
        r.script.enqueue("rummy_play", envelope("stale", state = stateJson(seq = 2)))
        store.submitTurn()
        store.actionJob?.join()
        assertEquals(RummyNoticeText.tableChanged, store.notice)
        assertTrue(store.isMyTurn)

        val room = rig()
        room.store.applyState(decodeState(stateJson("forming", seq = 0)))
        room.script.enqueue("rummy_start", """{"status":"stale"}""")
        room.store.startGame()
        room.store.actionJob?.join()
        assertEquals(RummyNoticeText.tryAgain, room.store.notice)
    }

    @Test
    fun drawFiresEventAndKeepsRackSlots() = runTest {
        // 없으면: 뽑기 모션이 엉뚱한 타일을 날리거나, 차례가 넘어갈 때마다 받침대 정렬이 풀리는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        val events = mutableListOf<RummyDrawEvent>()
        store.onTileDrawn = { events += it }
        val rack = listOf("A4", "B9", "C2", "D13", "J")
        store.applyState(decodeState(stateJson(seq = 1, myRack = rack)))
        store.sortRack(RummyRackSort.color)
        val joker = store.editor!!.rack.first { it.face.isJoker }.id
        store.moveTiles(listOf(joker), RummyDropTarget.RackSlot(RummyRackSlot(1, 20)))
        assertNull(store.rackSortMode)
        val slots = store.editor!!.rackEntries
        r.script.stand("rummy_draw", envelope(state = stateJson(seq = 2, turnSeat = 1, turnStartedMs = NOW_MS + 5, myRack = rack + "B10")))
        store.drawTile()
        store.actionJob?.join()
        val event = events.single()
        assertEquals(1, event.serial)
        assertEquals(event, store.lastDraw)
        assertEquals(listOf("B10"), event.tiles.map { it.face.text })
        val editor = store.editor!!
        val drawn = editor.rack.first { it.id == event.tiles[0].tileID }
        assertEquals("B10", drawn.face.text)
        assertEquals(event.tiles[0].slot, editor.rackLayout.slot(drawn.id))
        assertEquals(slots, editor.rackEntries.filter { it.face.text != "B10" })
    }

    @Test
    fun drawJoinsLiveSortAndRackMoveTurnsItOff() = runTest {
        // 없으면: 정렬해 둔 받침대에 뽑은 타일이 끝에 튀어나오거나 정렬 버튼 '선택됨'이 거짓말하는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        val events = mutableListOf<RummyDrawEvent>()
        store.onTileDrawn = { events += it }
        val rack = listOf("A4", "B9", "C2", "D13", "J")
        store.applyState(decodeState(stateJson(seq = 1, myRack = rack)))
        store.sortRack(RummyRackSort.number)
        assertEquals(RummyRackSort.number, store.rackSortMode)
        r.script.stand("rummy_draw", envelope(state = stateJson(seq = 2, turnSeat = 1, turnStartedMs = NOW_MS + 5, myRack = rack + "B10")))
        store.drawTile()
        store.actionJob?.join()
        assertEquals(RummyRackSort.number, store.rackSortMode)
        val tile = events.single().tiles.single()
        assertEquals(store.editor!!.rackLayout.slot(tile.tileID), tile.slot, "알린 자리 = 정렬 뒤 자리")
        val first = store.editor!!.rack.first().id
        store.moveTiles(listOf(first), RummyDropTarget.RackSlot(RummyRackSlot(1, 20)))
        assertNull(store.rackSortMode, "받침대를 손으로 옮기면 정렬이 풀린다")
    }

    // MARK: 알림

    @Test
    fun invitesArriveOnceAndBlockMirrorHidesPeopleAndRooms() = runTest {
        // 없으면: 30초 폴링마다 같은 초대 말풍선이 다시 뜨거나, 차단한 사람의 초대가 배너에 남는 결함이 초록이 된다.
        val fromC = roomJson(MATCH_TEXT, host = C, hostName = "씨")
        val publicWithC = roomJson(OTHER_ROOM_TEXT, isPublic = true, extraSeats = listOf("""{"user_id":"$C","state":"joined","seat_no":1}"""))
        val r = rig(lobby = lobbyJson(invites = listOf(roomJson(), fromC), publicRooms = listOf(publicWithC)))
        val store = r.store
        store.setHiddenPeers(setOf(PEER_C))
        store.refreshLobby()
        assertEquals(listOf(ROOM), r.tally.arrived)
        assertEquals(listOf(ROOM), store.incomingInvites.map { it.id })
        assertTrue(store.hasIncomingInvite)
        assertEquals(listOf(PEER_B), store.lobby?.users?.map { it.id })
        assertEquals(true, store.lobby?.publicRooms?.isEmpty())
        store.refreshLobby()
        assertEquals(listOf(ROOM), r.tally.arrived, "같은 초대를 또 알렸다")
        store.setHiddenPeers(emptySet())
        assertEquals(2, store.incomingInvites.size)
        assertEquals(2, store.lobby?.users?.size)
        assertEquals(listOf(ROOM), r.tally.arrived, "되살려도 다시 안 알린다(본 것으로 적어 뒀다)")
        assertEquals("비님이 아잉 큐브에 초대했어요 · 판돈 5", RummyNoticeText.invitation(store.incomingInvites.first()))
        assertEquals(2, store.pendingIncomingInviteCount)
    }

    @Test
    fun expiredInvitesDoNotCountOnTheBadge() = runTest {
        // 없으면: 폴링이 안 도는 화면 밖에서 방 수명이 지난 초대가 배지에 남는 결함이 초록이 된다.
        val r = rig(lobby = lobbyJson(invites = listOf(roomJson())))
        r.store.refreshLobby()
        assertEquals(1, r.store.pendingIncomingInviteCount)
        r.wall = WALL0.addingTimeInterval(601.0)
        assertEquals(0, r.store.pendingIncomingInviteCount)
    }

    @Test
    fun startOncePerMatchAndTurnBubbleOnlyWhenHidden() = runTest {
        // 없으면: 창을 보고 있는데 말풍선이 뜨거나, 5초 폴링마다 같은 차례 말풍선이 되풀이되는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        store.isWindowVisible = true
        store.applyState(decodeState(stateJson(seq = 1, turnSeat = 1)))
        assertEquals(1, r.tally.presents)
        assertTrue(r.tally.attentions.isEmpty())
        store.applyState(decodeState(stateJson(seq = 2, turnSeat = 0, nowMs = NOW_MS + 1_000)))
        assertTrue(r.tally.attentions.isEmpty())
        store.isWindowVisible = false
        store.applyState(decodeState(stateJson(seq = 3, turnSeat = 1, nowMs = NOW_MS + 2_000)))
        store.applyState(decodeState(stateJson(seq = 4, turnSeat = 0, nowMs = NOW_MS + 3_000)))
        store.applyState(decodeState(stateJson(seq = 4, turnSeat = 0, draft = draftJson(emptyList(), 1), nowMs = NOW_MS + 3_000)))
        assertEquals(listOf(RummyNoticeText.myTurnAttention), r.tally.attentions)
        assertEquals(1, r.tally.attentionRequests)
        assertEquals(1, r.tally.presents)
    }

    @Test
    fun rubyFollowsLobbyAndRereadsOnFirstStartAndFinish() = runTest {
        // 없으면: 판 state 에 잔액이 없어 머리글이 판돈 빼기 전 잔액을 끝까지 보이는 결함이 초록이 된다.
        val r = rig(lobby = lobbyJson())
        val store = r.store
        store.refreshLobby()
        val base = r.count("rummy_lobby")
        assertEquals(120L, store.rubyBalance)
        r.script.stand("rummy_lobby", lobbyJson(active = MATCH_TEXT, ruby = 115))
        store.applyState(decodeState(stateJson(seq = 1)))
        runCurrent()
        assertEquals(base + 1, r.count("rummy_lobby"), "판돈 차감을 처음 봤다 — 로비 한 번")
        assertEquals(115L, store.rubyBalance)
        store.applyState(decodeState(stateJson(seq = 2)))
        runCurrent()
        assertEquals(base + 1, r.count("rummy_lobby"), "같은 판의 다음 state 는 다시 안 읽는다")
        r.script.stand("rummy_lobby", lobbyJson(ruby = 125))
        store.applyState(decodeState(stateJson("finished", seq = 3, endReason = "rack_empty")))
        runCurrent()
        assertEquals(base + 2, r.count("rummy_lobby"), "정산을 처음 봤다 — 로비 한 번")
        assertEquals(125L, r.host.rubyBalance)
    }

    // MARK: 폴링 · 신호 · 마감

    @Test
    fun pollingRunsOnlyWhileVisible() = runTest {
        // 없으면: 창을 닫아도 5초 폴링이 계속 돌아 서버를 두드리거나, 방에서 참가자 변화를 못 보는 결함이 초록이 된다.
        val r = rig(lobby = lobbyJson(room = roomJson(MATCH_TEXT, host = ME, hostName = "나")))
        r.script.stand("rummy_state", envelope(state = stateJson("forming", seq = 0)))
        val store = r.store
        store.applyState(decodeState(stateJson("forming", seq = 0)))
        store.pollTick(WALL0)
        assertEquals(0, r.count("rummy_state"), "창이 안 보인다")

        store.setWindowVisible(true)
        runCurrent()
        assertEquals(1, r.count("rummy_state"))
        assertEquals(1, r.count("rummy_lobby"))
        suspend fun tick(seconds: Double) {
            r.wall = WALL0.addingTimeInterval(seconds)
            store.pollTick(r.wall)
        }
        tick(4.9)
        assertEquals(1, r.count("rummy_state"))
        tick(5.0)
        assertEquals(2, r.count("rummy_state"))
        tick(30.0)
        assertEquals(3, r.count("rummy_state"))
        assertEquals(2, r.count("rummy_lobby"))
        store.setWindowOccluded(true)
        tick(60.0)
        assertEquals(3, r.count("rummy_state"))
        store.setWindowOccluded(false)
        tick(60.0)
        assertEquals(4, r.count("rummy_state"))
        assertEquals(3, r.count("rummy_lobby"))
        store.setWindowVisible(false)
        tick(120.0)
        assertEquals(4, r.count("rummy_state"))
        assertNull(store.pollJob)
    }

    @Test
    fun pollSlowsDownOnlyWhileSubscribedAndFarFromDeadline() = runTest {
        // 없으면: 신호가 없는 기기까지 15초로 늦어지거나, 마감 근처에서 시간 초과 결과를 늦게 보는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        store.applyState(decodeState(stateJson(deadlineMs = NOW_MS + 60_000)))
        assertEquals(5.0, store.matchPollInterval(WALL0), "미구독은 신호가 없으니 늦추면 안 된다")
        r.host.realtimeState = RealtimeState.Subscribed(WALL0, WALL0)
        assertEquals(15.0, store.matchPollInterval(WALL0))
        assertEquals(15.0, store.matchPollInterval(WALL0.addingTimeInterval(44.0)))
        assertEquals(5.0, store.matchPollInterval(WALL0.addingTimeInterval(45.0)), "마감이 가까운데 늦췄다")

        val room = rig()
        room.host.realtimeState = RealtimeState.Subscribed(WALL0, WALL0)
        assertEquals(5.0, room.store.matchPollInterval(WALL0), "판이 없는데 늦췄다")
        room.store.applyState(decodeState(stateJson("forming", seq = 0, expiresMs = NOW_MS + 60_000)))
        assertEquals(15.0, room.store.matchPollInterval(WALL0))
        assertEquals(5.0, room.store.matchPollInterval(WALL0.addingTimeInterval(45.0)))
    }

    @Test
    fun signalsCoalesceToOneTrailingRead() = runTest {
        // 없으면: 작업 판 초인종(끌기마다)이 남의 화면에서 state 요청 폭주를 일으키는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        val gate = CompletableDeferred<Unit>()
        r.script.stand("rummy_state", Reply.Gate(gate, Reply.Json(envelope(state = stateJson(seq = 1, turnSeat = 1)))))
        store.applyState(decodeState(stateJson(seq = 1, turnSeat = 1)))
        store.handleSignal()
        runCurrent()
        assertEquals(1, r.count("rummy_state"))
        repeat(4) { store.handleSignal() }
        runCurrent()
        assertEquals(1, r.count("rummy_state"), "도는 중에 또 나갔다")
        gate.complete(Unit)
        runCurrent()
        assertEquals(2, r.count("rummy_state"), "뒤따르는 한 번으로 합친다")
    }

    @Test
    fun signalDuringLobbyFetchRereadsOnce() = runTest {
        // 없으면: 로비 조회가 도는 중 온 초대 초인종을 버려 배너가 다음 계기까지 안 뜨는 결함이 초록이 된다.
        val r = rig(lobby = lobbyJson())
        val gate = CompletableDeferred<Unit>()
        r.script.enqueue("rummy_lobby", Reply.Gate(gate, Reply.Json(lobbyJson())))
        r.script.enqueue("rummy_lobby", lobbyJson(invites = listOf(roomJson())))
        val first = launch { r.store.refreshLobby() }
        runCurrent()
        assertTrue(r.store.lobbyInFlight)
        r.store.handleSignal()
        runCurrent()
        gate.complete(Unit)
        first.join()
        runCurrent()
        assertEquals(2, r.count("rummy_lobby"), "초인종 뒤 로비를 다시 읽지 않았다")
        assertEquals(listOf(ROOM), r.tally.arrived)
    }

    @Test
    fun catchUpFollowsStartOfHeldRoomAndUnknownStatusIsReread() = runTest {
        // 없으면: 잠든 사이 시작된 방에 굳거나, 서버가 새 status 를 보낸 날 그 판이 영영 안 읽히는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        store.applyState(decodeState(stateJson("forming", seq = 0)))
        r.script.stand("rummy_state", envelope(state = stateJson(seq = 1)))
        store.systemDidWake()
        runCurrent()
        assertEquals(RummyPhase.playing, store.phase)

        val odd = rig()
        odd.script.stand("rummy_state", envelope(state = stateJson(seq = 2)))
        odd.store.applyState(decodeState(stateJson("paused", seq = 1)))
        assertEquals(RummyMatchStatus.unknown, odd.store.match?.status)
        odd.store.handleSignal()
        runCurrent()
        assertEquals(RummyPhase.playing, odd.store.phase, "모르는 status 를 들어도 신호가 오면 다시 읽는다")
    }

    @Test
    fun deadlinePassedRereadsStateWithRetrySpacing() = runTest {
        // 없으면: 상대가 자리를 비웠을 때 시간 초과 판정(서버 catchup)을 아무도 부르지 않아 판이 멈춘 듯 보이는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        store.applyState(decodeState(stateJson(seq = 1, turnSeat = 1)))
        suspend fun check(seconds: Double, seq: Long = 1, turnSeat: Long = 1, deadlineMs: Long = NOW_MS + 60_000) {
            r.wall = WALL0.addingTimeInterval(seconds)
            r.script.stand(
                "rummy_state",
                envelope(state = stateJson(seq = seq, turnSeat = turnSeat, nowMs = NOW_MS + (seconds * 1000).toLong(), deadlineMs = deadlineMs, turnStartedMs = deadlineMs - 60_000)),
            )
            store.checkDeadline(r.wall)
        }
        check(62.4)
        assertEquals(0, r.count("rummy_state"))
        check(62.5)
        assertEquals(1, r.count("rummy_state"))
        check(64.0)
        assertEquals(1, r.count("rummy_state"))
        check(65.5, seq = 2, turnSeat = 0, deadlineMs = NOW_MS + 125_000)
        assertEquals(2, r.count("rummy_state"))
        assertTrue(store.isMyTurn)
        check(66.0, seq = 2, turnSeat = 0, deadlineMs = NOW_MS + 125_000)
        assertEquals(2, r.count("rummy_state"))
        assertTrue(abs((store.turnRemaining(r.wall) ?: 0.0) - 59) < 0.01)
    }

    @Test
    fun remainingTimeUsesServerClock() = runTest {
        // 없으면: 기기 시계가 10초 빠른 폰에서 남은 초가 10초 모자라 보이는 결함이 초록이 된다.
        val store = rig().store
        val serverNow = NOW_MS + 10_000
        store.applyState(decodeState(stateJson(seq = 1, nowMs = serverNow, deadlineMs = serverNow + 60_000)))
        assertTrue(abs((store.turnRemaining(WALL0) ?: 0.0) - 60) < 0.01)
        assertEquals(0.0, store.turnRemaining(WALL0.addingTimeInterval(90.0)))
        assertNull(store.roomRemaining(WALL0))
    }

    // MARK: 방 · 거절 · 리셋

    @Test
    fun roomOutcomes() = runTest {
        // 없으면: 시작이 막혔는데 아무 말이 없거나, 닫힌 방 화면에 갇히거나, 기권한 판이 다음 폴링에 되살아나는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        r.script.stand("rummy_state", envelope(state = stateJson("forming", seq = 0)))
        store.applyState(decodeState(stateJson("forming", seq = 0)))
        r.script.enqueue("rummy_start", """{"status":"seats_dropped","dropped":["$B"]}""")
        store.startGame()
        store.actionJob?.join()
        assertEquals("루비가 모자라거나 다른 게임 중인 사람이 빠졌어요", store.notice)
        assertEquals(1, r.count("rummy_state"))
        assertEquals(RummyPhase.room, store.phase)

        // 비의 방에서 내가 빠졌다.
        val guest = rig().store
        val mine = listOf(seat(0, B, "비", "joined", 0), seat(1, ME, "나", "joined", 0))
        guest.applyState(decodeState(stateJson("forming", seq = 0, seats = mine, host = B, mySeat = 1)))
        assertEquals(RummyPhase.room, guest.phase)
        val dropped = listOf(seat(0, B, "비", "joined", 0), seat(null, ME, "나", "dropped", 0))
        guest.applyState(decodeState(stateJson("forming", seq = 0, seats = dropped, host = B, mySeat = null)))
        assertNull(guest.match)
        assertEquals(RummyPhase.lobby, guest.phase)
        assertEquals(RummyNoticeText.droppedFromRoom, guest.notice)
        guest.applyState(decodeState(stateJson("forming", seq = 0, seats = mine, host = B, mySeat = 1)))
        guest.applyState(decodeState(stateJson("cancelled", seq = 0, seats = mine, host = B, mySeat = 1)))
        assertNull(guest.match)
        assertEquals("방이 닫혔어요", guest.notice)

        // 판 기권 — 접고 로비로, 늦은 state 는 무시.
        store.applyState(decodeState(stateJson(seq = 3)))
        assertEquals(RummyPhase.playing, store.phase)
        r.script.enqueue("rummy_leave", """{"status":"ok"}""")
        store.leave()
        store.actionJob?.join()
        assertEquals(RummyPhase.lobby, store.phase)
        assertNull(store.match)
        assertNull(store.editor)
        assertEquals(RummyStateApplyOutcome.ignored, store.applyState(decodeState(stateJson(seq = 4))))
    }

    @Test
    fun staleLobbyAfterLeaveDoesNotResurrectRoomCard() = runTest {
        // 없으면: 나가기 직전에 읽힌 로비가 닫힌 방의 [시작]·[나가기] 카드를 되살리는 결함이 초록이 된다.
        val mineRoom = roomJson(MATCH_TEXT, host = ME, hostName = "나")
        val r = rig(lobby = lobbyJson(room = mineRoom))
        val store = r.store
        r.script.enqueue("rummy_create", envelope(state = stateJson("forming", seq = 0), extra = ""","match_id":"$MATCH_TEXT""""))
        store.createRoom()
        store.actionJob?.join()
        store.refreshLobby()
        assertEquals(MATCH, store.myRoom?.id)
        r.script.enqueue("rummy_leave", """{"status":"ok"}""")
        store.leave()
        store.actionJob?.join()
        assertNull(store.match)
        assertNull(store.lobby?.me?.room, "서버가 아직 me.room 을 말해도 접은 방은 다시 안 선다")
        assertNull(store.myRoom)
    }

    @Test
    fun availabilityAndRefusalNotices() = runTest {
        // 없으면: 옛 앱이 '잠시 후 다시' 만 되풀이하거나, 배포 중간 창에 연결 오류로 보이는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        r.script.enqueue("rummy_lobby", """{"status":"unsupported_client"}""")
        r.script.enqueue("rummy_lobby", Reply.pgrst202)
        r.script.enqueue("rummy_create", """{"status":"insufficient","side":"me"}""")
        store.refreshLobby()
        assertEquals(RummyAvailability.updateRequired, store.availability)
        assertEquals("앱을 업데이트해 주세요", store.notice)
        store.refreshLobby()
        assertEquals(RummyAvailability.serverMissing, store.availability)
        store.createRoom()
        store.actionJob?.join()
        assertEquals("루비가 모자라요", store.notice)
        assertNull(store.match)
    }

    @Test
    fun resetClearsEverythingButWiring() = runTest {
        // 없으면: 계정을 바꾼 뒤 앞 사람의 랙·방·초대가 남거나, 순위 스위치가 꺼져 영영 안 켜지는 결함이 초록이 된다.
        val r = rig(lobby = lobbyJson(invites = listOf(roomJson())))
        val store = r.store
        store.rankingEnabled = true
        store.refreshLobby()
        store.setHiddenPeers(setOf(PEER_C))
        store.applyState(decodeState(stateJson(seq = 2)))
        assertNotNull(store.editor)
        store.reset()
        assertEquals(RummyPhase.lobby, store.phase)
        assertNull(store.match)
        assertNull(store.editor)
        assertNull(store.lobby)
        assertFalse(store.hasIncomingInvite)
        assertTrue(store.seenInviteIDs.isEmpty())
        assertTrue(store.hiddenPeerIDs.isEmpty())
        assertNull(store.rubyBalance)
        assertTrue(store.rankingEnabled)
        assertEquals(1, r.tally.dismisses)
    }

    // MARK: 한 계정 기기 여럿 · 하트비트

    @Test
    fun heartbeatRunsOnlyForEngagedHeldMatchAndStopsAtTheEnd() = runTest {
        // 없으면: 판 중에 하트비트가 안 돌아 90초 뒤 끊김 기권되거나, 판이 끝난 뒤에도 계속 도는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        store.heartbeatEnabled = true
        r.script.stand("rummy_heartbeat", envelope())
        store.markEngaged(MATCH)
        store.applyState(decodeState(stateJson()))
        assertEquals(MATCH, store.heartbeatMatchID)
        assertNotNull(store.heartbeatJob)
        assertTrue(store.isHoldingMatch)
        runCurrent()
        assertEquals(1, r.count("rummy_heartbeat"), "판을 들면 바로 한 번")
        val call = r.bodies("rummy_heartbeat").single()
        assertEquals(setOf("p_protocol", "p_match_id"), call.keys)
        assertEquals(MATCH_TEXT, call.getValue("p_match_id").jsonPrimitive.content)
        advanceTimeBy(10_001)
        runCurrent()
        assertEquals(2, r.count("rummy_heartbeat"))
        advanceTimeBy(10_000)
        runCurrent()
        assertEquals(3, r.count("rummy_heartbeat"))
        store.applyState(decodeState(stateJson("finished", seq = 9)))
        assertEquals(RummyPhase.finished, store.phase)
        assertNull(store.heartbeatMatchID)
        assertNull(store.heartbeatJob)
        assertFalse(store.isHoldingMatch)
        assertFalse(store.isEngaged(MATCH), "끝난 판은 장부에서 지운다")
        advanceTimeBy(30_000)
        runCurrent()
        assertEquals(3, r.count("rummy_heartbeat"))
    }

    /**
     * 콜드 스타트: 뒤에 있는 동안 프로세스가 죽고 다시 켰다. 앱 복귀 시점엔 판이 없어 '바로 한 번'이 건너뛰어지고, 판을 읽은 뒤 루프가 주기(10초)부터 시작하면 그 사이 90초 끊김 기권에 걸린다.
     * 앱 복귀가 판보다 먼저 온다(GamesStore.appDidBecomeActive → catchUp → applyState).
     */
    @Test
    fun coldStartBeatsAtOnceWhenTheMatchIsRead() = runTest {
        val r = rig()
        val store = r.store
        store.heartbeatEnabled = true
        r.script.stand("rummy_heartbeat", envelope())
        store.markEngaged(MATCH)
        store.appDidBecomeActive()
        runCurrent()
        assertEquals(0, r.count("rummy_heartbeat"), "전제: 복귀 시점엔 판이 없다")
        store.applyState(decodeState(stateJson()))
        assertEquals(0, r.count("rummy_heartbeat"), "applyState 안에서 보내면 그 안으로 다시 들어온다")
        runCurrent()
        assertEquals(1, r.count("rummy_heartbeat"), "판을 읽고 주기를 기다렸다")
        store.applyState(decodeState(stateJson(seq = 9)))
        runCurrent()
        assertEquals(1, r.count("rummy_heartbeat"), "같은 판을 다시 읽어도 또 보내지 않는다")
        advanceTimeBy(9_000)
        runCurrent()
        assertEquals(1, r.count("rummy_heartbeat"))
        advanceTimeBy(1_001)
        runCurrent()
        assertEquals(2, r.count("rummy_heartbeat"), "주기는 그대로 돈다")
    }

    /** 방은 판이 아니다: 루프를 세우며 보내지 않고 앱 복귀만 한 번 보낸다(화면 복귀는 roomHeartbeatHeld 가 보낸다 — PhoneRummyTabExitTest). 두 번 나가지 않는다. */
    @Test
    fun roomBeatsOnceOnReturnAndNotOnRead() = runTest {
        val r = rig()
        val store = r.store
        store.heartbeatEnabled = true
        r.script.stand("rummy_heartbeat", envelope())
        store.markEngaged(MATCH)
        store.applyState(decodeState(stateJson("forming")))
        assertEquals(RummyPhase.room, store.phase)
        assertEquals(MATCH, store.heartbeatMatchID)
        runCurrent()
        assertEquals(0, r.count("rummy_heartbeat"), "방을 읽었다고 바로 보내면 방 규칙이 바뀐다")
        store.appDidEnterBackground()
        store.appDidBecomeActive()
        runCurrent()
        assertEquals(1, r.count("rummy_heartbeat"), "방도 돌아오면 바로 한 번 · 두 번 나가지 않는다")
    }

    @Test
    fun idleDeviceSendsNothing() = runTest {
        // 없으면: 초인종으로 판을 읽기만 한 '놀던 기기' 를 내리면 다른 기기에서 하던 판이 기권되는 결함이 초록이 된다(테트리스 10-30 실측).
        val r = rig()
        val store = r.store
        store.heartbeatEnabled = true
        r.script.stand("rummy_heartbeat", envelope())
        r.script.stand("rummy_leave", envelope())
        r.script.stand("rummy_state", envelope(state = stateJson()))
        store.refreshMatch(MATCH)
        assertEquals(RummyPhase.playing, store.phase)
        assertFalse(store.isEngaged(MATCH))
        assertNull(store.heartbeatMatchID)
        advanceTimeBy(30_000)
        runCurrent()
        store.heartbeatTick(MATCH)
        assertFalse(store.isHoldingMatch)
        assertEquals(RummyCloseDecision.close, store.closeDecision)
        assertFalse(store.needsExitLeave)
        assertTrue(store.leaveForExit(RummyExitReason.signOut))
        assertTrue(store.leaveRoomForExit(RummyExitReason.back))
        runCurrent()
        assertEquals(0, r.count("rummy_leave"), "놀던 기기가 rummy_leave 를 보냈다")
        assertEquals(0, r.count("rummy_heartbeat"), "놀던 기기가 하트비트를 보냈다")
        assertEquals(MATCH, store.match?.id, "놀던 기기가 남의 판을 접었다")
        store.reset()
        runCurrent()
        assertEquals(0, r.count("rummy_leave") + r.count("rummy_heartbeat"))
    }

    /** 놀던 기기가 내 차례에 받침대만 정리하면 작업 판을 안 보낸다 — 보내면 다른 기기가 만들던 작업 판을 덮고 이 기기가 engaged 가 된다. 판에 놓으면 보낸다. */
    @Test
    fun idleDeviceRackMoveSendsNoDraft() = runTest {
        val r = rig()
        val store = r.store
        r.script.stand("rummy_draft", envelope())
        store.applyState(decodeState(stateJson()))
        assertTrue(store.isMyTurn)
        assertFalse(store.isEngaged(MATCH))
        val tile = store.editor!!.rack[0].id
        store.moveTiles(listOf(tile), RummyDropTarget.RackSlot(RummyRackSlot(1, 30)))
        assertEquals(RummyRackSlot(1, 30), store.editor!!.rackLayout.slot(tile), "받침대 안 이동이 안 됐다")
        advanceTimeBy(2_000)
        runCurrent()
        assertEquals(0, r.count("rummy_draft"), "놀던 기기가 받침대 정리로 작업 판을 보냈다")
        assertFalse(store.isEngaged(MATCH), "받침대 정리로 이 기기가 판을 가져갔다")
        // 기준선: 판에 놓으면 보낸다 · 그 뒤 이 기기가 쥔다.
        store.moveTiles(listOf(store.editor!!.rack[1].id), RummyDropTarget.NewMeldAt(RummyPoint(100, 100)))
        advanceTimeBy(2_000)
        runCurrent()
        assertEquals(1, r.count("rummy_draft"), "판에 놓았는데 작업 판이 안 갔다")
        assertTrue(store.isEngaged(MATCH))

        // 쥔 기기의 받침대 정리는 전과 같다(작업 판을 띄운다 · 판이 그대로면 코어가 거른다) — 놀던 기기 문이 쥔 기기를 안 막는다.
        val held = rig()
        held.script.stand("rummy_draft", envelope())
        held.store.markEngaged(MATCH)
        held.store.applyState(decodeState(stateJson()))
        held.store.moveTiles(listOf(held.store.editor!!.rack[0].id), RummyDropTarget.RackSlot(RummyRackSlot(1, 30)))
        advanceTimeBy(2_000)
        runCurrent()
        assertEquals(1, held.count("rummy_draft"), "쥔 기기의 정리가 안 갔다")
    }

    /** 뒤로 나간 뒤 안내줄을 지우고 로비를 다시 읽는다 — 안 읽으면 낡은 active_match_id 로 게임 탭 카드가 최대 30초 '판 진행 중'이다. 시작된 판을 들고 남았으면 안 읽는다. */
    @Test
    fun leavingBackSettlesTheLobby() = runTest {
        val r = rig()
        val store = r.store
        r.script.stand("rummy_leave", envelope())
        r.script.stand("rummy_lobby", """{"status":"ok","server_now_ms":$NOW_MS,"stakes":[3,5,10],"me":{"ruby_balance":10},"invites":[],"public_rooms":[],"users":[]}""")
        store.markEngaged(MATCH)
        store.applyState(decodeState(stateJson()))
        store.setNotice("서버 말")
        runCurrent() // 판을 받으며 시작한 조회를 먼저 끝낸다 — 아래는 나간 뒤의 조회만 센다.
        val lobbies = r.count("rummy_lobby")
        assertEquals(RummyCloseDecision.confirmForfeit, store.requestBack())
        assertNull(store.confirmBack(RummyCloseDecision.confirmForfeit))
        runCurrent()
        assertEquals(1, r.count("rummy_leave"))
        assertNull(store.match)
        assertNull(store.notice, "나갔는데 안내줄이 남았다")
        assertEquals(lobbies + 1, r.count("rummy_lobby"), "나간 뒤 로비를 안 읽었다")
    }

    @Test
    fun everyWriteMarksEngagedAndRefusedJoinIsForgotten() = runTest {
        // 없으면: 이 기기에서 손댄 판인데 하트비트가 안 돌아 90초 끊김 기권되는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        r.script.enqueue("rummy_create", envelope(state = stateJson("forming", seq = 0), extra = ""","match_id":"$MATCH_TEXT""""))
        store.createRoom()
        store.actionJob?.join()
        assertTrue(store.isEngaged(MATCH), "만들기")
        store.reset()

        val join = rig()
        join.script.enqueue("rummy_join", envelope(state = stateJson("forming", seq = 0, id = ROOM_TEXT, host = B, seats = listOf(seat(0, B, "비", "joined", 0), seat(1, ME, "나", "joined", 0)), mySeat = 1)))
        join.store.join(ROOM)
        join.store.actionJob?.join()
        assertTrue(join.store.isEngaged(ROOM), "참가")

        val refused = rig()
        refused.script.enqueue("rummy_join", """{"status":"room_full"}""")
        refused.store.join(ROOM)
        refused.store.actionJob?.join()
        assertFalse(refused.store.isEngaged(ROOM), "못 앉은 참가는 장부에서 걷는다")

        val react = rig()
        react.script.stand("rummy_react", envelope())
        react.store.applyState(decodeState(stateJson()))
        assertFalse(react.store.isEngaged(MATCH))
        assertTrue(react.store.sendReaction(AingSticker.joy))
        assertTrue(react.store.isEngaged(MATCH), "반응")
    }

    @Test
    fun engagedLedgerPersistsAcrossRelaunchAndClearsAtTheEnd() = runTest {
        // 없으면: 앱을 다시 켠 폰이 쥐던 판의 하트비트를 잃어 90초 끊김 기권되거나, 끝난 판 id 가 쌓이는 결함이 초록이 된다.
        val r = rig()
        val prefs = MemoryPrefs()
        val store = r.store
        store.engagedDefaults = prefs
        store.markEngaged(MATCH)
        assertEquals("""["$MATCH_TEXT"]""", prefs.getString(RummyStore.engagedDefaultsKey))
        assertEquals(ME, prefs.getString(RummyStore.engagedOwnerDefaultsKey))

        // 앱 재실행 — 저장소를 넣으면 이어받고, 판을 읽으면 하트비트가 바로 선다.
        val relaunched = r.another()
        relaunched.heartbeatEnabled = true
        relaunched.engagedDefaults = prefs
        assertTrue(relaunched.isEngaged(MATCH))
        relaunched.applyState(decodeState(stateJson()))
        assertEquals(MATCH, relaunched.heartbeatMatchID)
        assertTrue(relaunched.isHoldingMatch)
        relaunched.applyState(decodeState(stateJson("finished", seq = 9)))
        assertFalse(relaunched.isEngaged(MATCH))
        assertEquals("[]", prefs.getString(RummyStore.engagedDefaultsKey))
        assertFalse(relaunched.isHoldingMatch)

        // 방 닫힘.
        val room = r.another()
        room.engagedDefaults = MemoryPrefs()
        room.markEngaged(MATCH)
        room.applyState(decodeState(stateJson("forming", seq = 0)))
        room.applyState(decodeState(stateJson("cancelled", seq = 2)))
        assertFalse(room.isEngaged(MATCH))

        // 상한 — 못 지운 것이 쌓여도 오래된 것부터 버린다.
        val many = r.another()
        repeat(RummyStore.engagedLimit + 4) { i ->
            many.markEngaged(SwiftUUID.parse("00000000-0000-4000-8000-" + i.toString().padStart(12, '0'))!!)
        }
        assertEquals(RummyStore.engagedLimit, many.engagedMatchIDs.size)
    }

    @Test
    fun engagedLedgerIsBoundToAccount() = runTest {
        // 없으면: 강제 로그아웃으로 남은 앞 계정의 판 id 가 같은 판의 상대 계정에게 맞아, 손대지 않은 판이 기권되는 결함이 초록이 된다.
        val r = rig()
        val prefs = MemoryPrefs()
        r.script.stand("rummy_leave", envelope())
        r.script.stand("rummy_heartbeat", envelope())
        val store = r.store
        store.heartbeatEnabled = true
        store.engagedDefaults = prefs
        store.markEngaged(MATCH) // 앞 계정이 이 기기에서 둔 판
        store.reset() // 강제 로그아웃(이탈 없음) — 장부는 남는다(같은 사람 재로그인용)
        r.host.overrideUser = B // 같은 판의 상대가 이 기기에 들어온다
        store.applyState(decodeState(stateJson(mySeat = 1, turnSeat = 0)))
        assertEquals(RummyPhase.playing, store.phase)
        assertEquals(MATCH, store.match?.id)
        assertFalse(store.isEngaged(MATCH), "앞 계정의 장부로 engaged 다")
        assertFalse(store.needsExitLeave)
        assertNull(store.heartbeatMatchID)
        assertTrue(store.leaveForExit(RummyExitReason.signOut))
        runCurrent()
        assertEquals(0, r.count("rummy_leave") + r.count("rummy_heartbeat"))

        // 앱 재실행으로 저장소를 이어받아도 그 계정에겐 아니다.
        val otherHost = TestRummyHost(r.h.sessionStore, AppConfig(duelsEnabled = true)) { r.wall }.also { it.overrideUser = B }
        val relaunched = r.another(otherHost)
        relaunched.engagedDefaults = prefs
        assertFalse(relaunched.isEngaged(MATCH))
        // 같은 계정이 다시 들어오면 이어진다(토큰 만료 강제 로그아웃 뒤 재로그인).
        val sameHost = TestRummyHost(r.h.sessionStore, AppConfig(duelsEnabled = true)) { r.wall }
        val same = r.another(sameHost)
        same.engagedDefaults = prefs
        assertTrue(same.isEngaged(MATCH))
        // 그 계정이 이 기기에서 손대면 장부는 그 계정 것으로 새로 열린다.
        relaunched.markEngaged(ROOM)
        assertEquals(listOf(ROOM), relaunched.engagedMatchIDs)
        assertTrue(relaunched.isEngaged(ROOM))
    }

    @Test
    fun megaphoneDefersOnlyWhileMySeatPlaysAnEngagedMatch() = runTest {
        // 없으면: 판 위로 확성기 배너가 내려와 끌기 중인 타일 위를 덮거나, 놀던 기기·구경 중에 배너가 영영 안 뜨는 결함이 초록이 된다.
        val r = rig()
        val playing = r.store
        playing.markEngaged(MATCH)
        playing.applyState(decodeState(stateJson()))
        assertTrue(playing.defersMegaphoneBanner)
        val idle = rig().store
        idle.applyState(decodeState(stateJson()))
        assertEquals(RummyPhase.playing, idle.phase)
        assertFalse(idle.defersMegaphoneBanner, "놀던 기기가 배너를 미뤘다")
        val forfeited = listOf(seat(0, ME, "나", "forfeit", 0, 1), seat(1, B, "비", "playing"))
        playing.applyState(decodeState(stateJson(seq = 2, myRack = null, seats = forfeited)))
        assertFalse(playing.defersMegaphoneBanner, "기권한 뒤 구경 중인데 미뤘다")
        assertFalse(playing.holdsLiveSeat, "기권한 자리는 서버 바쁨(joined·playing)이 아니다")
        playing.applyState(decodeState(stateJson("finished", seq = 3)))
        assertFalse(playing.defersMegaphoneBanner)
    }

    // MARK: 앱 수명(폰 몫)

    @Test
    fun backgroundIsNotAForfeitAndHeartbeatResumesAtOnceOnReturn() = runTest {
        // 없으면: 알림 하나 읽고 온 사람이 판돈을 잃거나(즉시 기권), 프로세스가 살아 있는 동안 90초 규칙이 안 돌거나, 돌아와도 10초를 기다려 끊기는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        store.heartbeatEnabled = true
        r.script.stand("rummy_heartbeat", envelope())
        r.script.stand("rummy_leave", envelope())
        store.markEngaged(MATCH)
        store.applyState(decodeState(stateJson()))
        store.appDidEnterBackground()
        assertNull(store.heartbeatMatchID, "뒤에서는 하트비트를 멈춘다 — 서버 90초 규칙에 맡긴다")
        advanceTimeBy(120_000)
        runCurrent()
        assertEquals(0, r.count("rummy_heartbeat"))
        assertEquals(0, r.count("rummy_leave"), "뒤로 가는 것은 기권이 아니다")
        assertEquals(MATCH, store.match?.id)
        store.appDidBecomeActive()
        runCurrent()
        assertEquals(1, r.count("rummy_heartbeat"), "돌아오면 바로 한 번")
        advanceTimeBy(10_001)
        runCurrent()
        assertEquals(2, r.count("rummy_heartbeat"), "그 뒤 10초 주기가 되살아난다")
    }

    // MARK: 의도적 이탈

    @Test
    fun leaveForExitCapsTheWaitAndFoldsTheMatch() = runTest {
        // 없으면: 로그아웃이 느린 서버를 기다리며 멈추거나, 나갔는데 판이 계속 '플레이 중'으로 남는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        r.script.stand("rummy_leave", Reply.Hang)
        store.markEngaged(MATCH)
        store.applyState(decodeState(stateJson()))
        val started = testScheduler.currentTime
        val confirmed = store.leaveForExit(RummyExitReason.signOut)
        assertFalse(confirmed)
        assertEquals(2_000L, testScheduler.currentTime - started, "서버 답을 2초만 기다린다")
        assertNull(store.match)
        assertEquals(RummyPhase.lobby, store.phase)
        assertTrue(MATCH in store.dismissedMatchIDs)
        assertEquals(1, r.count("rummy_leave"))

        val fast = rig()
        fast.script.stand("rummy_leave", envelope())
        fast.store.markEngaged(MATCH)
        fast.store.applyState(decodeState(stateJson()))
        assertTrue(fast.store.leaveForExit(RummyExitReason.signOut))
        assertNull(fast.store.match)
        assertFalse(fast.store.isEngaged(MATCH))
        assertTrue(fast.store.leaveForExit(RummyExitReason.signOut), "판이 없으면 할 일이 없다")
        assertEquals(1, fast.count("rummy_leave"))
    }

    @Test
    fun guestBackRacingStartDoesNotForfeit() = runTest {
        // 없으면: 방장이 [시작]을 누른 직후(이 기기에 닿기 전) 손님이 뒤로 가면 묻지도 않고 판돈을 잃는 결함이 초록이 된다.
        val seats = listOf(seat(0, B, "비", "joined", 0), seat(1, ME, "나", "joined", 0))
        val playingSeats = listOf(seat(0, B, "비", "playing"), seat(1, ME, "나", "playing"))
        val r = rig()
        val store = r.store
        r.script.stand("rummy_state", envelope(state = stateJson(seq = 2, turnSeat = 0, host = B, seats = playingSeats, mySeat = 1)))
        r.script.stand("rummy_leave", envelope())
        store.markEngaged(MATCH)
        store.applyState(decodeState(stateJson("forming", seq = 0, host = B, seats = seats, mySeat = 1)))
        assertEquals(RummyCloseDecision.leaveRoom, store.closeDecision)
        assertEquals(RummyCloseDecision.leaveRoom, store.requestBack())
        runCurrent()
        assertEquals(0, r.count("rummy_leave"), "묻지 않는 방 나가기가 시작된 판을 기권시켰다")
        assertEquals(RummyPhase.playing, store.phase)

        // 아직 방이면 나간다.
        val still = rig()
        still.script.stand("rummy_state", envelope(state = stateJson("forming", seq = 0, host = B, seats = seats, mySeat = 1)))
        still.script.stand("rummy_leave", envelope())
        still.store.markEngaged(MATCH)
        still.store.applyState(decodeState(stateJson("forming", seq = 0, host = B, seats = seats, mySeat = 1)))
        still.store.requestBack()
        runCurrent()
        assertEquals(1, still.count("rummy_leave"))
        assertNull(still.store.match)

        // state 가 안 와도 2초 남짓 뒤엔 나간다.
        val slow = rig()
        slow.script.stand("rummy_state", Reply.Hang)
        slow.script.stand("rummy_leave", envelope())
        slow.store.markEngaged(MATCH)
        slow.store.applyState(decodeState(stateJson("forming", seq = 0, host = B, seats = seats, mySeat = 1)))
        slow.store.requestBack()
        runCurrent()
        assertEquals(0, slow.count("rummy_leave"))
        advanceTimeBy(2_001)
        runCurrent()
        assertEquals(1, slow.count("rummy_leave"), "느린 조회가 방 나가기를 막았다")
    }

    @Test
    fun backConfirmFollowsTheDecisionAtConfirmTime() = runTest {
        // 없으면: "루비는 그대로예요" 를 읽고 고른 버튼이 판돈을 잃는 기권이 되는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        r.script.stand("rummy_leave", envelope())
        r.script.stand("rummy_state", envelope(state = stateJson("forming", seq = 0)))
        store.markEngaged(MATCH)
        store.applyState(decodeState(stateJson("forming", seq = 0)))
        assertEquals(RummyCloseDecision.confirmCloseRoom, store.requestBack())
        assertEquals(0, r.count("rummy_leave"), "확인 전에는 안 나간다")
        // 묻는 사이 판이 시작됐다 — 새 문구로 다시 묻는다.
        store.applyState(decodeState(stateJson(seq = 1)))
        assertEquals(RummyCloseDecision.confirmForfeit, store.confirmBack(RummyCloseDecision.confirmCloseRoom))
        runCurrent()
        assertEquals(0, r.count("rummy_leave"))
        // 다시 물은 뒤의 확인은 기권이다.
        assertNull(store.confirmBack(RummyCloseDecision.confirmForfeit))
        runCurrent()
        assertEquals(1, r.count("rummy_leave"))

        // 묻는 사이 판이 끝났다 — 확인은 그냥 떠난다.
        val ended = rig()
        ended.script.stand("rummy_leave", envelope())
        ended.store.markEngaged(MATCH)
        ended.store.applyState(decodeState(stateJson()))
        assertEquals(RummyCloseDecision.confirmForfeit, ended.store.requestBack())
        ended.store.applyState(decodeState(stateJson("finished", seq = 5)))
        assertNull(ended.store.confirmBack(RummyCloseDecision.confirmForfeit))
        runCurrent()
        assertEquals(0, ended.count("rummy_leave"))
    }

    // MARK: 반응

    @Test
    fun reactionsCooldownEchoAndUnknownKeys() = runTest {
        // 없으면: 내 말풍선이 두 번 뜨거나, 남의 반응이 폴링마다 되풀이되거나, 모르는 키에 화면이 죽는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        r.script.stand("rummy_react", envelope())
        store.applyState(decodeState(stateJson()))
        assertTrue(store.sendReaction(AingSticker.joy))
        assertEquals(1, store.reactionFeed.size)
        assertTrue(store.reactionFeed.single().isMine)
        assertFalse(store.sendReaction(AingSticker.sad), "쿨다운 안")
        r.wall = WALL0.addingTimeInterval(1.99)
        assertFalse(store.canReact(r.wall))
        r.wall = WALL0.addingTimeInterval(2.0)
        assertTrue(store.canReact(r.wall))
        runCurrent()
        assertEquals("joy", r.bodies("rummy_react").single().getValue("p_key").jsonPrimitive.content)

        val reactions = """[{"seat_no":1,"key":"nope","at_ms":${NOW_MS + 2}},{"seat_no":1,"key":"sad","at_ms":${NOW_MS + 1}},{"seat_no":0,"key":"joy","at_ms":$NOW_MS}]"""
        store.applyState(decodeState(stateJson(reactions = reactions)))
        assertEquals(listOf(AingSticker.joy, AingSticker.sad), store.reactionFeed.map { it.sticker }, "메아리는 삼키고 남의 것 하나 · 모르는 키는 버린다")
        assertFalse(store.reactionFeed.last().isMine)
        store.applyState(decodeState(stateJson(reactions = reactions)))
        assertEquals(2, store.reactionFeed.size, "같은 반응을 또 냈다")
    }

    // MARK: 받침대 저장

    @Test
    fun rackSlotsPersistPerMatchThroughSwiftJson() = runTest {
        // 없으면: 앱을 다시 켜면 받침대 배치가 처음 순서로 돌아가거나, 끝난 판의 저장값이 쌓이는 결함이 초록이 된다.
        val r = rig()
        val prefs = MemoryPrefs()
        val key = RummyStore.rackDefaultsKey(MATCH)
        val rack = listOf("A4", "B9", "C2", "D13", "J")
        val store = r.store
        store.rackDefaults = prefs
        store.applyState(decodeState(stateJson(myRack = rack)))
        store.moveTiles(listOf(store.editor!!.rack[0].id), RummyDropTarget.RackSlot(RummyRackSlot(1, 20)))
        val saved = store.editor!!.rackEntries
        assertNotNull(prefs.getString(key))

        val relaunched = r.another()
        relaunched.rackDefaults = prefs
        relaunched.applyState(decodeState(stateJson(myRack = rack)))
        assertEquals(saved, relaunched.editor?.rackEntries, "면 타입 때문에 일반 Json 디코더로 읽으면 여기서 면 순서로 돌아간다")
        relaunched.applyState(decodeState(stateJson("finished", seq = 9)))
        assertNull(prefs.getString(key), "끝난 판의 자리는 지운다")

        // 깨진 값은 면 순서로 돌아간다(던지지 않는다).
        prefs.putString(key, "not json")
        val broken = r.another()
        broken.rackDefaults = prefs
        broken.applyState(decodeState(stateJson(myRack = rack)))
        assertEquals(rack.map { RummyFace.of(it)!! }, broken.editor?.rackFaces)

        // 배선 없는 스토어(기본)는 저장소가 없어도 그대로 돈다 — 시험이 앱 저장소를 더럽히지 않는 까닭.
        val unwired = r.another()
        assertNull(unwired.rackDefaults)
        unwired.applyState(decodeState(stateJson(myRack = rack)))
        unwired.sortRack(RummyRackSort.number)
        assertEquals(rack.size, unwired.editor?.rackFaces?.size)
    }

    // MARK: 초대 줄

    @Test
    fun inviteQueueCreatesThenInvitesInOrderAndDropsOnRefusal() = runTest {
        // 없으면: 방 없이 누른 [초대]가 방만 열고 사람을 안 부르거나, 만들기가 거절됐는데 줄이 남아 다음 방에서 엉뚱하게 초대하는 결함이 초록이 된다.
        val r = rig()
        val store = r.store
        r.script.stand("rummy_create", envelope(state = stateJson("forming", seq = 0), extra = ""","match_id":"$MATCH_TEXT""""))
        r.script.stand("rummy_invite", """{"status":"ok"}""")
        r.script.stand("rummy_state", envelope(state = stateJson("forming", seq = 0)))
        store.inviteQueued(PEER_B)
        assertEquals(listOf(PEER_B), store.callingPeerIDs)
        runCurrent()
        assertEquals(1, r.count("rummy_create"))
        assertEquals(listOf(B), r.bodies("rummy_invite").map { it.getValue("p_user").jsonPrimitive.content })
        assertTrue(store.inviteQueue.pending.isEmpty())
        assertTrue(store.callingPeerIDs.isEmpty())

        // 한 판 더 — 차례대로, 이미 자리 있는 사람은 건너뛴다.
        val again = rig()
        val seatedB = listOf(seat(0, ME, "나", "joined", 0), seat(null, B, "비", "invited", 0))
        again.script.stand("rummy_create", envelope(state = stateJson("forming", seq = 0, seats = seatedB), extra = ""","match_id":"$MATCH_TEXT""""))
        again.script.stand("rummy_invite", """{"status":"ok"}""")
        again.script.stand("rummy_state", envelope(state = stateJson("forming", seq = 0, seats = seatedB)))
        again.store.createAndInvite(listOf(PEER_B, PEER_C))
        runCurrent()
        assertEquals(listOf(C), again.bodies("rummy_invite").map { it.getValue("p_user").jsonPrimitive.content })

        // 만들기 거절 — 줄을 버린다.
        val refused = rig()
        refused.script.stand("rummy_create", """{"status":"insufficient"}""")
        refused.store.inviteQueued(PEER_B)
        runCurrent()
        assertEquals(0, refused.count("rummy_invite"))
        assertTrue(refused.store.inviteQueue.pending.isEmpty())
        assertTrue(refused.store.callingPeerIDs.isEmpty())

        // 세션 없는 스토어는 만들기가 안 떠난다 — 그 자리에서 줄을 버린다.
        val bare = RummyStore(r.h.storeScope)
        bare.inviteQueued(PEER_B)
        assertTrue(bare.inviteQueue.pending.isEmpty())

        // 내 방이면 줄 없이 바로 초대(방장만).
        val hosted = rig()
        hosted.script.stand("rummy_invite", """{"status":"ok"}""")
        hosted.script.stand("rummy_state", envelope(state = stateJson("forming", seq = 0)))
        hosted.store.applyState(decodeState(stateJson("forming", seq = 0)))
        hosted.store.inviteQueued(PEER_B)
        runCurrent()
        assertEquals(1, hosted.count("rummy_invite"))
    }

    @Test
    fun resetDropsTheInviteQueue() = runTest {
        // 없으면: 앞 계정이 눌러 둔 사람이 다음 계정의 방에 초대되는 결함이 초록이 된다.
        val r = rig()
        r.script.stand("rummy_create", Reply.Hang)
        r.store.inviteQueued(PEER_B)
        runCurrent()
        assertEquals(listOf(PEER_B), r.store.callingPeerIDs)
        r.store.reset()
        assertTrue(r.store.inviteQueue.pending.isEmpty())
        assertTrue(r.store.callingPeerIDs.isEmpty())
    }

    // MARK: 판돈 깃발(§8-17 #1 — 폰 몫)

    /** 짝으로 잰다: 같은 손짓에 깃발만 다르다. 꺼짐 → 입구 요청 **0건** · 켜짐 → 1건씩. */
    @Test
    fun entrancesGoOutOnlyWhenTheBuildEnablesDuels() = runTest {
        for (enabled in listOf(false, true)) {
            val r = rig(enabled)
            val store = r.store
            assertEquals(enabled, store.duelsEnabled)
            assertEquals(!enabled, store.duelsLocked)
            r.script.stand("rummy_create", """{"status":"insufficient"}""")
            r.script.stand("rummy_join", """{"status":"room_full"}""")
            store.createRoom()
            store.actionJob?.join()
            assertEquals(if (enabled) 1 else 0, r.count("rummy_create"), "만들기 enabled=$enabled")
            store.join(ROOM)
            store.actionJob?.join()
            assertEquals(if (enabled) 1 else 0, r.count("rummy_join"), "참가 enabled=$enabled")
            store.applyState(decodeState(stateJson("forming", seq = 0)))
            r.script.stand("rummy_invite", """{"status":"not_host"}""")
            r.script.stand("rummy_start", """{"status":"not_enough_players"}""")
            store.invite(PEER_B)
            store.actionJob?.join()
            assertEquals(if (enabled) 1 else 0, r.count("rummy_invite"), "초대 enabled=$enabled")
            store.startGame()
            store.actionJob?.join()
            assertEquals(if (enabled) 1 else 0, r.count("rummy_start"), "시작 enabled=$enabled")
            if (!enabled) assertEquals(RummyNoticeText.updateRequired, store.notice)
            assertFalse(store.isWorking)
        }
    }

    @Test
    fun lockedBuildFoldsInvitesButStillDeclinesAndReadsNothingOutsideTheScreen() = runTest {
        // 없으면: 잠긴 빌드의 배지가 수락할 수 없는 초대를 세거나, 안 쓰는 조회가 초인종마다 나가는 결함이 초록이 된다.
        val locked = rig(enabled = false, lobby = lobbyJson(invites = listOf(roomJson())))
        locked.store.handleSignal()
        locked.store.systemDidWake()
        locked.store.realtimeDidJoin()
        locked.store.refreshLobbyIfStale()
        runCurrent()
        assertEquals(0, locked.count("rummy_lobby"), "잠긴 빌드가 화면 밖에서 로비를 읽었다")
        locked.store.refreshLobby() // 화면이 열면 읽는다
        assertEquals(1, locked.store.incomingInvites.size, "전제: 초대는 살아 있다")
        assertFalse(locked.store.hasIncomingInvite)
        assertEquals(0, locked.store.pendingIncomingInviteCount)
        assertEquals(RummyNoticeText.updateRequired, locked.store.incomingFoldedNotice)
        assertTrue(locked.tally.arrived.isEmpty(), "수락할 수 없는 초대를 알렸다")
        locked.script.stand("rummy_decline", """{"status":"ok"}""")
        locked.store.decline(ROOM)
        locked.store.actionJob?.join()
        assertEquals(1, locked.count("rummy_decline"), "거절은 판돈이 안 움직여 깃발과 무관하다")
        assertTrue(locked.store.incomingInvites.isEmpty())

        // 기준선: 켠 빌드는 같은 계기로 읽고, 배지·알림이 선다.
        val open = rig(enabled = true, lobby = lobbyJson(invites = listOf(roomJson())))
        open.store.handleSignal()
        runCurrent()
        assertEquals(1, open.count("rummy_lobby"))
        assertTrue(open.store.hasIncomingInvite)
        assertEquals(1, open.store.pendingIncomingInviteCount)
        assertNull(open.store.incomingFoldedNotice)
        assertEquals(listOf(ROOM), open.tally.arrived)
        open.h.assertClean()
    }

    // MARK: 서버 픽스처

    private fun fixture(name: String): String = RepoFiles.readText("Tests/checkTests/Fixtures/rummy/server/$name.json")

    private fun fixtureState(name: String): RummyMatchState = SwiftJson.decode(RummyActionResponse.serializer(), fixture(name)).state!!

    @Test
    fun serverFixturesAreReadCorrectly() = runTest {
        // 없으면: 실서버 출력이 손 픽스처와 다르게 생겼는데(키 이름·중첩·null 자리) 스텁 시험만 초록인 결함이 남는다.
        val scope = rig().h.storeScope
        fun bare() = RummyStore(scope).also { it.deadlineWakeEnabled = false } // 호스트 없는 스토어 — 내 자리는 my_seat_no 로 찾는다

        val mine = fixtureState("state_active_my_turn")
        val active = bare()
        assertEquals(RummyStateApplyOutcome.applied, active.applyState(mine))
        assertEquals(RummyPhase.playing, active.phase)
        assertTrue(active.isMyTurn)
        assertEquals(mine.myRack?.size, active.editor?.rackFaces?.size)
        assertTrue((active.turnRemaining(active.clock()) ?: 0.0) > 50)

        val other = fixtureState("state_active_other_draft")
        val watching = bare()
        watching.applyState(other)
        assertFalse(watching.isMyTurn)
        assertNotNull(watching.otherDraft)
        assertEquals(other.draft?.table, watching.otherDraft)

        val finished = fixtureState("state_finished")
        val done = bare()
        done.applyState(finished)
        assertEquals(RummyPhase.finished, done.phase)
        assertNull(done.editor)

        val forming = fixtureState("state_forming")
        val room = bare()
        room.applyState(forming)
        assertEquals(RummyPhase.room, room.phase)
        assertTrue((room.roomRemaining(room.clock()) ?: 0.0) > 0)

        val lobby = SwiftJson.decode(RummyLobby.serializer(), fixture("lobby_with_room_invites_public"))
        assertEquals(listOf(3L, 5L, 10L), lobby.stakes)
        val created = SwiftJson.decode(RummyActionResponse.serializer(), fixture("create_ok"))
        assertTrue(created.matchId != null || created.state?.id != null)
    }
}
