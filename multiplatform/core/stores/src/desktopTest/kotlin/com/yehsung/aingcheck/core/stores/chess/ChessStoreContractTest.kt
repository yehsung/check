// 원본: Tests/checkTests/V0343ChessStoreTests.swift · V0345ChessStoreGapTests.swift · V0348ChessDragStoreTests.swift · V0364ChessGomokuWatcherCountTests.swift(스토어 몫) @ 1b8260d
package com.yehsung.aingcheck.core.stores.chess

import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.rules.chess.ChessMove
import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.rules.chess.fromUci
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.gomoku.CHESS_FIXTURES
import com.yehsung.aingcheck.core.stores.gomoku.DuelStubServer
import com.yehsung.aingcheck.core.stores.gomoku.FakeDuelHost
import com.yehsung.aingcheck.core.stores.gomoku.StubReply
import com.yehsung.aingcheck.core.stores.gomoku.contractClock
import com.yehsung.aingcheck.core.stores.gomoku.decodeJson
import com.yehsung.aingcheck.core.stores.gomoku.fixtureJSON
import com.yehsung.aingcheck.core.stores.gomoku.long
import com.yehsung.aingcheck.core.stores.gomoku.obj
import com.yehsung.aingcheck.core.stores.gomoku.objects
import com.yehsung.aingcheck.core.stores.gomoku.settle
import com.yehsung.aingcheck.core.stores.gomoku.storeScope
import com.yehsung.aingcheck.core.stores.gomoku.str
import com.yehsung.aingcheck.core.wire.games.ChessStatePayload
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 체스 스토어 × 실서버 픽스처(`Tests/checkTests/Fixtures/chess-rpc`). G §2-3 W2-d ①~④ 의 체스 몫: 대국 흐름 재생(초기 → 백 e4 → 6수 국면) ·
 * 40P01 한 번 재시도(쓰기 + `chess_state` — 서버가 시간 판정을 돌리는 조회) · `p_protocol` 1 을 언제나 · 관전·순위·로봇. §8-17 #1 깃발도 잰다.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ChessStoreContractTest {
    private val users: JsonObject get() = fixtureJSON(CHESS_FIXTURES, "_manifest").obj("users")!!
    private val m1: String get() = users.str("m1")!!
    private val playerA: String get() = users.str("A")!!
    private val playerB: String get() = users.str("B")!!

    private fun TestScope.rig(me: String, duelsEnabled: Boolean = true, configure: DuelStubServer.() -> Unit = {}): Triple<ChessStore, FakeDuelHost, DuelStubServer> {
        val server = DuelStubServer(this).apply(configure)
        val host = FakeDuelHost(server.service { contractClock }, me, AppConfig(duelsEnabled = duelsEnabled), clockNow = { contractClock })
        val store = ChessStore(storeScope(), host)
        store.clock = { contractClock }
        return Triple(store, host, server)
    }

    private fun sq(notation: String): ChessSquare = ChessSquare.parse(notation)!!

    /** 상태 응답의 사실과 스토어 판이 같은가(체스 몫). */
    private fun assertMatchEqualsServer(store: ChessStore, name: String, checkRuby: Boolean = true) {
        val json = fixtureJSON(CHESS_FIXTURES, name)
        val match = json.obj("match")!!
        val state = assertNotNull(store.match, name)
        assertEquals(match.str("id"), state.id, name)
        assertEquals(match.str("fen"), state.fen, "$name 판(FEN)")
        assertNotNull(state.position, "$name FEN 을 못 읽었다")
        assertEquals(match.long("ply_count")!!.toInt(), state.plyCount, name)
        assertEquals(json.str("my_color"), state.myColor.rawValue, name)
        // 끝난 판에는 차례가 없다(Swift `isFinished ? nil : …` — 서버 행은 마지막 차례 글자를 그대로 둔다).
        val finished = match.str("status") == "finished"
        assertEquals(if (finished) null else match.str("turn"), state.turn?.rawValue, "$name 차례")
        assertEquals(match.long("white_ms_left"), state.clock.whiteMsLeft, "$name 백 시계 — 서버 값으로 통째로 덮어써야 한다")
        assertEquals(match.long("black_ms_left"), state.clock.blackMsLeft, "$name 흑 시계")
        val legal = json["legal_moves"]?.let { runCatching { it.jsonArray }.getOrNull() }?.map { it.toString().trim('"') } ?: emptyList()
        assertEquals(legal.toSet(), state.legalMoves.map { it.toString() }.toSet(), "$name 합법 수 — 서버가 준 것만 쓴다")
        val moves = json["moves"]?.let { runCatching { it.objects() }.getOrNull() } ?: emptyList()
        if (moves.isNotEmpty() && moves.first().long("seq") == 1L) {
            assertEquals(moves.map { it.str("san") }, state.moves.map { it.san }, "$name 기보 — 서버 SAN 그대로")
        }
        if (checkRuby) json.long("ruby_balance")?.let { assertEquals(it, store.rubyBalance, "$name 루비") }
        val turnStarted = match.double2("turn_started_ms")
        val serverNow = json.double2("server_now_ms")
        if (match.str("status") == "active" && turnStarted != null && serverNow != null) {
            val expected = contractClock.addingTimeInterval((turnStarted - serverNow) / 1000)
            val actual = assertNotNull(state.clock.turnStartedAt, "$name 차례 시작 시각")
            assertTrue(abs(actual.timeIntervalSince(expected)) < ChessStore.serverClockToleranceSeconds + 0.002, "$name 시계 보정")
        }
    }

    private fun JsonObject.double2(key: String): Double? = (this[key] as? JsonPrimitive)?.content?.toDoubleOrNull()

    @Test
    fun whiteFlowReplaysInitialMoveAndMidGame() = runTest {
        val (store, host, server) = rig(playerA) {
            queueFixtures("chess_state", CHESS_FIXTURES, "chess_state__ok_initial_my_turn", "chess_state__ok_mid_since0")
            queueFixtures("chess_move", CHESS_FIXTURES, "chess_move__ok_white_first")
        }
        store.refreshMatch(m1)
        assertEquals(0L, server.lastBody("chess_state").long("p_since_seq"))
        assertMatchEqualsServer(store, "chess_state__ok_initial_my_turn")
        assertEquals(20, store.match!!.legalMoves.size)
        assertTrue(store.match!!.isMyTurn)
        assertEquals(ChessPhase.playing, store.phase)

        // 입력 2단: 말 고르기 → 도착 칸. 고른 상태는 스토어가 든다.
        store.tap(sq("e2"))
        assertEquals(setOf(sq("e3"), sq("e4")), store.selection?.targets)
        store.tap(sq("e4"))
        assertNull(store.selection)
        assertEquals(1, server.count("chess_move"))
        val body = server.lastBody("chess_move")
        assertEquals(0L, body.long("p_expected_ply"))
        assertEquals("e2e4", body.str("p_uci"))
        assertEquals(m1, body.str("p_match_id"))
        assertMatchEqualsServer(store, "chess_move__ok_white_first")
        assertFalse(store.match!!.isMyTurn)
        assertTrue(store.match!!.legalMoves.isEmpty(), "상대 차례인데 합법 수가 남았다(서버는 null 을 준다)")
        assertEquals(ChessMove.fromUci("e2e4"), store.match!!.lastMove)
        assertNull(store.notice)

        // 상대가 두는 동안 따라잡기 — since 는 들고 있는 ply(1). 서버가 1번부터 다 실어 주면 다시 쌓는다.
        store.refreshMatch()
        assertEquals(1L, server.lastBody("chess_state").long("p_since_seq"))
        assertMatchEqualsServer(store, "chess_state__ok_mid_since0")
        assertEquals(listOf("e4", "e5", "Nf3", "Nc6", "Bb5", "Nf6"), store.match!!.moves.map { it.san })
        assertTrue(store.match!!.isMyTurn)
        assertEquals(95L, host.rubyBalance, "호스트 루비 칩")
        // ③ p_protocol 은 언제나 1.
        for (call in server.calls) assertEquals(1L, call.body.long("p_protocol"), "${call.rpc}: ${call.body}")
    }

    @Test
    fun blackAcceptsAndWaitsForWhite() = runTest {
        val (store, _, server) = rig(playerB) { queueFixtures("chess_respond", CHESS_FIXTURES, "chess_respond__accept_ok") }
        store.incoming = ChessInvite(m1, ChessUser(playerA, "", null, null, true, true, false), 5, contractClock.addingTimeInterval(50.0))
        store.respond(m1, accept = true)
        assertEquals(1, server.count("chess_respond"))
        assertEquals(true, server.lastBody("chess_respond")["p_accept"]?.toString()?.toBoolean())
        assertNull(store.incoming, "수락한 신청 카드가 남았다")
        assertMatchEqualsServer(store, "chess_respond__accept_ok")
        assertEquals(ChessColor.black, store.match!!.myColor)
        assertFalse(store.match!!.isMyTurn)
        assertEquals(1L, server.lastBody("chess_respond").long("p_protocol"))
    }

    @Test
    fun deadlockRetriesWritesAndStateOnceButNotTheLobby() = runTest {
        val (store, _, server) = rig(playerA) {
            queue("chess_state", StubReply.deadlock)
            queueFixtures("chess_state", CHESS_FIXTURES, "chess_state__ok_initial_my_turn")
            queue("chess_move", StubReply.deadlock)
            queueFixtures("chess_move", CHESS_FIXTURES, "chess_move__ok_white_first")
            queue("chess_lobby", StubReply.deadlock, StubReply.deadlock)
            queue("chess_resign", StubReply.deadlock, StubReply.deadlock, StubReply.deadlock)
        }
        store.refreshMatch(m1)
        assertEquals(2, server.count("chess_state"), "체스 판 조회는 서버가 시간 판정을 돌리므로 교착을 한 번 다시 보낸다")
        assertMatchEqualsServer(store, "chess_state__ok_initial_my_turn")
        store.send(ChessMove.fromUci("e2e4")!!)
        assertEquals(2, server.count("chess_move"))
        val bodies = server.bodies("chess_move")
        assertEquals(bodies[0], bodies[1], "재시도는 첫 시도와 같은 요청이다")
        assertMatchEqualsServer(store, "chess_move__ok_white_first")
        store.resign()
        assertEquals(2, server.count("chess_resign"), "두 번째 교착이면 그대로 던진다")
        assertEquals(ChessNoticeText.checkConnection, store.notice)
        store.refreshLobby()
        assertEquals(1, server.count("chess_lobby"), "읽기 전용 로비는 재시도하지 않는다")
        assertTrue(store.lobbyLoadFailed)
    }

    /** B 가 받은 신청 하나(`pending`) — 서버는 받은 신청을 로비 id 로만 말하고 상세는 `chess_state` 로 준다(⑪). */
    private fun pendingForB(): ChessStatePayload {
        val json = fixtureJSON(CHESS_FIXTURES, "chess_state__ok_initial_their_turn")
        val match = json.obj("match")!!
        val pending = JsonObject(
            match + mapOf(
                "status" to JsonPrimitive("pending"),
                "challenger" to JsonPrimitive(playerA),
                "invite_expires_ms" to JsonPrimitive((json.double2("server_now_ms") ?: 0.0) + 60_000),
            ),
        )
        return decodeJson(JsonObject((json - "state") + ("match" to pending)), ChessStatePayload.serializer())
    }

    @Test
    fun lockedBuildSendsNoChallengeNoAcceptAndFoldsTheIncomingInvite() = runTest {
        val (store, _, server) = rig(playerB, duelsEnabled = false) {
            queueFixtures("chess_respond", CHESS_FIXTURES, "chess_respond__decline_ok")
        }
        var arrived = 0
        store.onInviteArrived = { arrived += 1 }
        store.challenge(playerA)
        assertEquals(0, server.count("chess_challenge"), "깃발이 꺼진 빌드에서 체스 신청 RPC 가 나갔다")
        assertEquals(ChessNoticeText.updateMine, store.notice)
        store.applyState(pendingForB())
        assertNotNull(store.incoming, "서버 사실(받은 신청)은 들고 있어야 한다")
        assertNull(store.visibleIncoming, "잠긴 빌드의 받은 신청이 수락 카드로 섰다")
        assertEquals(ChessNoticeText.updateMine, store.incomingFoldedNotice)
        assertEquals(0, arrived)
        store.respond(m1, accept = true)
        assertEquals(0, server.count("chess_respond"), "깃발이 꺼진 빌드에서 체스 수락 RPC 가 나갔다")
        store.respond(m1, accept = false)
        assertEquals(1, server.count("chess_respond"), "거절은 막지 않는다")
        settle()
    }

    @Test
    fun unlockedBuildShowsTheIncomingInviteAndChallenges() = runTest {
        val (store, _, server) = rig(playerB, duelsEnabled = true) {
            queueFixtures("chess_challenge", CHESS_FIXTURES, "chess_challenge__ok")
        }
        var arrived = 0
        store.onInviteArrived = { arrived += 1 }
        store.applyState(pendingForB())
        assertEquals(store.incoming, store.visibleIncoming)
        assertNull(store.incomingFoldedNotice)
        assertEquals(1, arrived)
        store.incoming = null
        store.challenge(playerA)
        assertEquals(1, server.count("chess_challenge"))
        assertEquals(playerA, server.lastBody("chess_challenge").str("p_opponent"))
        assertNotNull(store.outgoing)
        settle()
    }

    @Test
    fun watchLiveFoldsToChessWatchAndWhiteBlackComeFromTheServer() = runTest {
        val (store, _, server) = rig(users.str("C")!!) {
            queue("chess_watch_live", StubReply.missingFunction("chess_watch_live"))
            queueFixtures("chess_watch", CHESS_FIXTURES, "chess_watch__ok_active")
        }
        store.spectatorFeaturesEnabled = true
        store.startWatching(m1)
        assertEquals(false, store.spectating?.hasServerState)
        store.refreshWatch()
        assertEquals(1, server.count("chess_watch_live"))
        assertEquals(1, server.count("chess_watch"))
        assertTrue(store.spectatorCountUnavailable)
        assertFalse(store.watchUnavailable)
        val json = fixtureJSON(CHESS_FIXTURES, "chess_watch__ok_active")
        val watch = assertNotNull(store.spectating)
        assertEquals(json.obj("white_user")!!.str("user_id"), watch.white?.id)
        assertEquals(json.obj("black_user")!!.str("user_id"), watch.black?.id)
        assertEquals(json.obj("match")!!.str("fen"), watch.fen)
        assertEquals(6, watch.plyCount)
        assertEquals(6, watch.moves.size)
        assertNotNull(watch.position)
        assertEquals(GamesChessWatchPlan.Entry.chip, GamesChessWatchPlan.entry(store, isMine = false))
        for (call in server.calls) assertEquals(1L, call.body.long("p_protocol"))
    }

    @Test
    fun rankingKeepsServerOrder() = runTest {
        val (store, _, server) = rig(playerA) { queueFixtures("chess_ranking", CHESS_FIXTURES, "chess_ranking__ok_me_ranked") }
        store.spectatorFeaturesEnabled = true
        store.loadRanking()
        assertEquals(1, server.count("chess_ranking"))
        val board = assertNotNull(store.ranking)
        val rows = fixtureJSON(CHESS_FIXTURES, "chess_ranking__ok_me_ranked")["rows"]!!.jsonArray.map { it.jsonObject }
        assertEquals(rows.map { it.str("user_id")!!.lowercase() }, board.entries.map { it.id })
        assertTrue(ChessRankingOrder.isSorted(board.entries))
        assertTrue(ChessRankingOrder.ranksMatchServerRule(board.entries))
        assertNotNull(board.me?.rank, "A 는 순위 안")
        assertNull(store.notice)
    }

    @Test
    fun robotGamePlaysLocallyWithLocalLegalMoves() = runTest {
        val (store, _, server) = rig(playerA, duelsEnabled = false)
        store.aiRuntime.minimumThinkSeconds = 0.0
        store.aiMoveChooser = { _, _ -> ChessMove.fromUci("e7e5") }
        var finishedCalls = 0
        store.onMatchFinished = { finishedCalls += 1 }
        store.startAIMatch(ChessColor.white)
        assertTrue(store.isAIMatch)
        assertEquals(20, store.match!!.legalMoves.size, "로봇 판의 합법 수는 로컬 규칙이 채운다(사람 차례)")
        store.tap(sq("e2"))
        store.tap(sq("e4"))
        settle()
        assertEquals(2, store.match!!.plyCount, "로봇이 답하지 않았다")
        assertEquals("e5", store.match!!.moves.last().san)
        assertEquals(ChessColor.white, store.match!!.turn)
        store.resign()
        assertEquals(ChessMatchOutcome.lost, store.match!!.outcome)
        assertEquals(ChessEndReason.resign, store.match!!.endReason)
        assertEquals(0, finishedCalls, "로봇 판 끝남이 일일 미션 고리를 불렀다")
        assertTrue(server.calls.isEmpty(), "로봇 판이 서버로 나갔다")
    }

    @Test
    fun resignFinishesOnceThenRereadsLobbyAndRanking() = runTest {
        val (store, _, server) = rig(playerB) {
            queueFixtures("chess_state", CHESS_FIXTURES, "chess_state__ok_initial_their_turn")
            queueFixtures("chess_resign", CHESS_FIXTURES, "chess_resign__ok")
            queueFixtures("chess_lobby", CHESS_FIXTURES, "chess_lobby__ok_empty")
            queueFixtures("chess_ranking", CHESS_FIXTURES, "chess_ranking__ok_me_unranked")
        }
        store.spectatorFeaturesEnabled = true
        var finishedCalls = 0
        store.onMatchFinished = { finishedCalls += 1 }
        store.refreshMatch(m1)
        assertEquals(false, store.match?.isFinished)
        assertEquals(0, finishedCalls, "진행 중 판에서 끝남 고리가 불렸다")
        store.resign()
        settle()
        assertEquals(1, server.count("chess_resign"))
        // 루비는 뒤이은 로비 재조회(다른 순간에 찍은 픽스처 100)가 마지막 말이다 — 가장 늦은 서버 응답이 이긴다.
        assertMatchEqualsServer(store, "chess_resign__ok", checkRuby = false)
        assertEquals(fixtureJSON(CHESS_FIXTURES, "chess_lobby__ok_empty").long("ruby_balance"), store.rubyBalance)
        assertEquals(true, store.match?.isFinished)
        assertEquals(ChessMatchOutcome.lost, store.match?.outcome)
        assertEquals(-5L, store.match?.rubyDelta, "진 판 루비 변화(손으로 적은 값)")
        assertEquals(ChessPhase.result, store.phase)
        assertEquals(1, finishedCalls)
        // 끝난 순간 전적(로비)과 순위를 한 번 다시 읽는다 — 머리글이 옛 전적과 새 순위를 섞지 않게.
        assertEquals(1, server.count("chess_lobby"))
        assertEquals(1, server.count("chess_ranking"))
        assertEquals(ChessPhase.result, store.phase, "로비 재조회가 결과 화면을 걷었다")
    }

    @Test
    fun dragDropHoldsTheTagUntilTheBoardAdvances() = runTest {
        val (store, _, server) = rig(playerA) {
            queueFixtures("chess_state", CHESS_FIXTURES, "chess_state__ok_initial_my_turn")
            queueFixtures("chess_move", CHESS_FIXTURES, "chess_move__ok_white_first")
        }
        store.refreshMatch(m1)
        assertEquals(ChessDragGrab.movable, store.grab(sq("e2")))
        assertEquals(ChessDragGrab.none, store.grab(sq("e7")), "상대 말을 끌 수 있다고 했다")
        assertTrue(store.beginDrag(sq("e2")))
        assertEquals(sq("e2"), store.dragOrigin)
        val move = assertNotNull(store.placeDrop(sq("e2"), sq("e4")))
        assertNull(store.dragOrigin)
        assertEquals(sq("e4"), store.pendingDrop?.to, "놓은 말이 답을 기다리는 동안 도착 칸에 머물지 않는다")
        // 놓은 직후 두 번째 놓기는 왕복 중과 같이 거절한다(두 수가 함께 사라지지 않게).
        assertNull(store.placeDrop(sq("d2"), sq("d4")))
        store.finishDrop(move)
        assertEquals(1, server.count("chess_move"))
        assertEquals("e2e4", server.lastBody("chess_move").str("p_uci"))
        assertNull(store.pendingDropRecord, "판이 나아갔는데 꼬리표가 남았다(유령 말)")
        assertEquals(1, store.match!!.plyCount)
    }

    @Test
    fun boardAdvancingBeforeTheSendDropsTheTagAndSendsNothing() = runTest {
        val (store, _, server) = rig(playerA) {
            queueFixtures("chess_state", CHESS_FIXTURES, "chess_state__ok_initial_my_turn")
        }
        store.refreshMatch(m1)
        store.beginDrag(sq("e2"))
        val move = assertNotNull(store.placeDrop(sq("e2"), sq("e4")))
        val initial = fixtureJSON(CHESS_FIXTURES, "chess_state__ok_initial_my_turn")
        // 수 번호가 그대로인 응답(폴링 · 시계)은 아직 답이 아니다 — 꼬리표를 붙든다.
        store.applyState(decodeJson(JsonObject(initial - "state"), ChessStatePayload.serializer()))
        assertEquals(sq("e4"), store.pendingDropRecord?.to, "같은 수 번호의 응답이 놓은 말을 되돌렸다")
        // 보내기 전에 판이 나아갔다(다른 기기에서 둔 수가 실시간으로 먼저 왔다) — 꼬리표는 그 자리에서 끝난다.
        val advanced = fixtureJSON(CHESS_FIXTURES, "chess_move__ok_white_first").obj("state")!!
        store.applyState(decodeJson(advanced, ChessStatePayload.serializer()))
        assertEquals(1, store.match!!.plyCount)
        assertNull(store.pendingDropRecord, "판이 나아갔는데 놓은 말 꼬리표가 남았다(유령 말)")
        // 낡은 수는 나가지 않는다 — `send` 는 지금의 판 수 번호로 나가므로 다른 수 자리에 떨어질 수 있다.
        store.finishDrop(move)
        assertEquals(0, server.count("chess_move"), "판이 바뀐 뒤 낡은 놓기를 보냈다")
    }

    @Test
    fun rejectedDropReturnsThePieceWithoutWaitingForTheReread() = runTest {
        val (store, _, server) = rig(playerA) {
            queueFixtures("chess_state", CHESS_FIXTURES, "chess_state__ok_initial_my_turn")
            queueFixtures("chess_move", CHESS_FIXTURES, "chess_move__not_your_turn")
        }
        store.refreshMatch(m1)
        store.beginDrag(sq("e2"))
        val move = assertNotNull(store.placeDrop(sq("e2"), sq("e4")))
        store.finishDrop(move)
        assertEquals(ChessNoticeText.notYourTurn, store.notice)
        assertNull(store.pendingDropRecord, "거절된 수의 말이 도착 칸에 남았다")
        assertTrue(server.count("chess_state") >= 2, "판단이 서버와 갈렸는데 다시 읽지 않았다")
    }
}
