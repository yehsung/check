// 원본: 없음 — 운영 시험에서 찾은 결함(기권하고 나간 게임 탭의 1:1 카드 셋이 '아잉 큐브 하는 중이에요'로 막혀 있다). 판이 끝난 뒤 낡은 값이 남는 길과, 판이 정말 살아 있으면 계속 막는 길을 네 방향 다 잰다.
package com.yehsung.aingcheck.core.stores.games

import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.snapshots.Snapshot
import com.yehsung.aingcheck.core.rules.rummy.RummyCloseDecision
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.applyLobby
import com.yehsung.aingcheck.core.stores.rummy.applyState
import com.yehsung.aingcheck.core.stores.rummy.confirmBack
import com.yehsung.aingcheck.core.stores.rummy.dismissResult
import com.yehsung.aingcheck.core.stores.rummy.markEngaged
import com.yehsung.aingcheck.core.stores.rummy.refreshLobby
import com.yehsung.aingcheck.core.stores.rummy.requestBack
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStoreTest
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.RummyLobby
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

@OptIn(ExperimentalCoroutinesApi::class)
class GamesRummyExitBlockTest {
    private companion object {
        const val MATCH = "7e7e0000-0000-4000-8000-000000000068"
        const val NOW_MS = 1_800_000_000_000L
        val WALL = SwiftDate(1_800_000_000.0)
    }

    /** 네 방향 입구. 큐브 판이 살면 셋이 막히고 자기 입구는 열린 채다. */
    private data class Blocks(val chess: GamesBusyGame?, val gomoku: GamesBusyGame?, val tetris: GamesBusyGame?, val rummy: GamesBusyGame?)

    private val open = Blocks(null, null, null, null)
    private val blocked = Blocks(GamesBusyGame.rummy, GamesBusyGame.rummy, GamesBusyGame.rummy, null)

    private fun GamesStore.blocks() = Blocks(chessEntryBlock, gomokuEntryBlock, tetrisEntryBlock, rummyEntryBlock)

    /** 스텁 서버. [active] 가 서버가 아는 내 판·방이다 — 로비는 시험이 줄 세운 답이 없으면 이 값을 말한다. */
    private class Server {
        var active: String? = null
        var leave: () -> Reply = { Reply.Offline }
        var state: Reply = Reply.Offline
        val lobbies = ArrayDeque<Reply>()
    }

    private class Rig(val h: StoreHarness, val games: GamesStore, val rummy: RummyStore, val server: Server)

    private fun seats(mine: String) =
        """[{"seat_no":0,"user_id":"${StoreFixtures.USER}","display_name":"나","state":"$mine"},{"seat_no":1,"user_id":"${StoreFixtures.PEER}","display_name":"비","state":"playing"},{"seat_no":2,"user_id":"7e7e0000-0000-4000-8000-0000000000c3","display_name":"다","state":"playing"}]"""

    private fun stateJson(status: String = "active", mine: String = if (status == "forming") "joined" else "playing", seq: Int = 1) =
        """{"id":"$MATCH","status":"$status","host_id":"${StoreFixtures.PEER}","seq":$seq,"server_now_ms":$NOW_MS,"seats":${seats(mine)},"my_seat_no":0,""" +
            """"my_rack":${if (status == "active" && mine == "playing") """["A1","B2"]""" else "null"},"table":[],"turn_seat_no":1,"turn_started_ms":$NOW_MS,"turn_deadline_ms":${NOW_MS + 60_000},"grace_ms":2000}"""

    private fun state(status: String = "active", mine: String = if (status == "forming") "joined" else "playing", seq: Int = 1): RummyMatchState =
        SwiftJson.decode(RummyMatchState.serializer(), stateJson(status, mine, seq))

    private fun lobbyJson(active: String?) =
        """{"status":"ok","server_now_ms":$NOW_MS,"stakes":[3,5,10],"me":{"ruby_balance":10,"active_match_id":${active?.let { "\"$it\"" } ?: "null"}},"invites":[],"public_rooms":[],"users":[]}"""

    private fun roomLobbyJson(room: String) =
        """{"status":"ok","server_now_ms":$NOW_MS,"stakes":[3,5,10],"me":{"ruby_balance":10,"active_match_id":null,"room":{"id":"$room","host":{"id":"${StoreFixtures.PEER}"},"stake":5,"expires_at_ms":${NOW_MS + 600_000}}},"invites":[],"public_rooms":[],"users":[]}"""

    private fun lobby(active: String?): RummyLobby = SwiftJson.decode(RummyLobby.serializer(), lobbyJson(active))

    private suspend fun TestScope.rig(): Rig {
        val server = Server()
        val h = StoreHarness(this, AppConfig(duelsEnabled = true)) { r ->
            when (r.rpcName) {
                "rummy_lobby" -> server.lobbies.removeFirstOrNull() ?: Reply.Json(lobbyJson(server.active))
                "rummy_state" -> server.state
                "rummy_leave" -> server.leave()
                "rummy_heartbeat" -> Reply.Json("""{"status":"ok"}""")
                "tetris_lobby" -> TetrisDuelStoreTest.lobby(incoming = false)
                else -> null
            }
        }
        h.signIn()
        val rummy = RummyStore(h.storeScope, TestRummyHost(h.sessionStore, AppConfig(duelsEnabled = true)) { WALL }).also {
            it.clock = { WALL }
            it.pollStepSeconds = Double.POSITIVE_INFINITY
            it.deadlineWakeEnabled = false
            it.heartbeatEnabled = false
        }
        h.rummyStore = rummy
        return Rig(h, GamesStore(h.context), rummy, server)
    }

    /** 이 기기가 쥔 판 중(서버 로비도 그 판을 말한다). 시작하며 나간 조회까지 끝낸 뒤다. */
    private suspend fun TestScope.inMatch(): Rig {
        val x = rig()
        x.server.active = MATCH
        x.rummy.markEngaged(com.yehsung.aingcheck.core.wire.SwiftUUID.parse(MATCH)!!)
        x.rummy.applyState(state())
        x.rummy.applyLobby(lobby(MATCH))
        runCurrent()
        assertEquals(blocked, x.games.blocks(), "판 중이면 셋이 막힌다")
        return x
    }

    /** 사람이 [기권하고 나가기]를 골랐다(뒤로 → 확인 → 이탈은 뒤에서 돈다). */
    private fun Rig.forfeit() {
        assertEquals(RummyCloseDecision.confirmForfeit, rummy.requestBack())
        assertNull(rummy.confirmBack(RummyCloseDecision.confirmForfeit))
    }

    /** ★ 재현 그대로: 기권이 서버에 닿고 판이 끝나면 네 방향이 곧바로 열린다. */
    @Test
    fun forfeitOpensAllFourWays() = runTest {
        val x = inMatch()
        val leave = CompletableDeferred<Unit>()
        x.server.leave = {
            x.server.active = null
            Reply.Gate(leave, Reply.Json("""{"status":"ok"}"""))
        }
        x.forfeit()
        runCurrent()
        assertEquals(blocked, x.games.blocks(), "서버 답 전에는 살아 있을 수 있다 — 안 닿으면 판이 남는다")
        leave.complete(Unit)
        runCurrent()
        assertNull(x.rummy.match)
        assertNull(x.rummy.activeMatchID)
        assertEquals(open, x.games.blocks())
    }

    /** ★ 기권 **전에** 나간 로비가 기권 **뒤에** 왔다 — 그 답의 `active_match_id` 가 입구를 다시 닫으면 안 된다(다음 로비까지 막힌다). */
    @Test
    fun aLobbyAskedBeforeTheForfeitDoesNotCloseTheEntrances() = runTest {
        val x = inMatch()
        val stale = CompletableDeferred<Unit>()
        val next = CompletableDeferred<Unit>()
        x.server.lobbies.addLast(Reply.Gate(stale, Reply.Json(lobbyJson(MATCH))))
        x.server.lobbies.addLast(Reply.Gate(next, Reply.Json(lobbyJson(null))))
        val first = launch { x.rummy.refreshLobby() }
        runCurrent()
        x.server.leave = {
            x.server.active = null
            Reply.Json("""{"status":"ok"}""")
        }
        x.forfeit()
        runCurrent()
        assertEquals(open, x.games.blocks())
        stale.complete(Unit)
        runCurrent()
        assertNull(x.rummy.activeMatchID, "기권 전에 읽힌 값이 되살아났다")
        assertEquals(open, x.games.blocks(), "늦은 로비가 입구를 다시 닫았다")
        next.complete(Unit)
        runCurrent()
        first.join()
        assertEquals(open, x.games.blocks())
    }

    /** ★ 기권이 못 닿았다(오프라인) — 서버엔 내 자리가 남았다. 로비까지 못 읽어도 **막는다**: 오목 쪽은 클라밖에 막는 데가 없다(시간패). */
    @Test
    fun anUnconfirmedForfeitKeepsBlockingEvenWithoutALobby() = runTest {
        val x = inMatch()
        x.server.leave = { Reply.Offline }
        x.server.lobbies.addLast(Reply.Offline)
        x.forfeit()
        runCurrent()
        assertNull(x.rummy.match, "이 기기에선 접는다")
        assertEquals(blocked, x.games.blocks(), "못 닿은 기권이 입구를 열었다 — 서버엔 판이 산다")
        // 다음 로비가 진실이다: 90초 끊김 기권이 끝낸 뒤.
        x.server.active = null
        x.rummy.refreshLobby()
        assertEquals(open, x.games.blocks())
    }

    /** 기권이 거절됐다(서버가 ok·not_found 가 아닌 답) — 로비가 그대로 판을 말하면 계속 막는다. */
    @Test
    fun aRefusedForfeitKeepsBlocking() = runTest {
        val x = inMatch()
        x.server.leave = { Reply.Json("""{"status":"invalid"}""") }
        x.forfeit()
        runCurrent()
        assertEquals(MATCH, x.rummy.activeMatchID?.lowercased)
        assertEquals(blocked, x.games.blocks())
    }

    /** ★ 2초 안에 답이 안 왔는데 그 뒤 서버가 확인했다 — 그 사이 로비가 '아직 판'이라 했어도 확인이 오면 열린다. */
    @Test
    fun aLateConfirmationOpensTheEntrances() = runTest {
        val x = inMatch()
        val leave = CompletableDeferred<Unit>()
        x.server.leave = { Reply.Gate(leave, Reply.Json("""{"status":"ok"}""")) }
        x.forfeit()
        runCurrent()
        advanceTimeBy(2_100)
        runCurrent()
        assertEquals(blocked, x.games.blocks(), "상한이 지났을 뿐 아직 모른다")
        x.server.active = null
        leave.complete(Unit)
        runCurrent()
        assertNull(x.rummy.activeMatchID)
        assertEquals(open, x.games.blocks(), "서버가 나감을 확인했는데 막혀 있다")
    }

    /** ★ 방을 나왔다: 나가기 전에 나간 로비의 `me.room` 이 입구를 다시 닫지 않는다. */
    @Test
    fun leavingARoomOpensAllFourWaysEvenWithALateLobby() = runTest {
        val x = rig()
        val room = com.yehsung.aingcheck.core.wire.SwiftUUID.parse(MATCH)!!
        x.rummy.markEngaged(room)
        x.rummy.applyState(state("forming"))
        runCurrent()
        assertEquals(blocked, x.games.blocks(), "모으는 방도 막는다")
        val stale = CompletableDeferred<Unit>()
        val next = CompletableDeferred<Unit>()
        x.server.lobbies.addLast(Reply.Gate(stale, Reply.Json(roomLobbyJson(MATCH))))
        x.server.lobbies.addLast(Reply.Gate(next, Reply.Json(lobbyJson(null))))
        val first = launch { x.rummy.refreshLobby() }
        runCurrent()
        x.server.state = Reply.Json("""{"status":"ok","state":${stateJson("forming")},"server_now_ms":$NOW_MS}""")
        x.server.leave = { Reply.Json("""{"status":"ok"}""") }
        x.games.rummyScreenDidAppear()
        x.games.leaveRummyRoomFromScreen(personIsLeaving = true)
        runCurrent()
        assertNull(x.rummy.match)
        assertEquals(open, x.games.blocks())
        stale.complete(Unit)
        runCurrent()
        assertEquals(open, x.games.blocks(), "나가기 전에 읽힌 방이 입구를 다시 닫았다")
        next.complete(Unit)
        runCurrent()
        first.join()
        assertEquals(open, x.games.blocks())
    }

    /** 방 나가기가 안 닿았다 — 자리가 남았으니 그대로 막는다(되돌린 방 · 판돈이 걷힐 수 있다). */
    @Test
    fun anUnconfirmedRoomLeaveKeepsBlocking() = runTest {
        val x = rig()
        val room = com.yehsung.aingcheck.core.wire.SwiftUUID.parse(MATCH)!!
        x.rummy.markEngaged(room)
        x.rummy.applyState(state("forming"))
        x.server.active = null
        x.server.state = Reply.Json("""{"status":"ok","state":${stateJson("forming")},"server_now_ms":$NOW_MS}""")
        x.server.leave = { Reply.Offline }
        x.games.rummyScreenDidAppear()
        x.games.leaveRummyRoomFromScreen()
        runCurrent()
        assertEquals(blocked, x.games.blocks())
    }

    /** ★ 상대 기권으로 끝난 판: 결과가 떠 있어도 열려 있고, 결과를 닫으면 끝나기 전에 나간 로비가 뒤늦게 와도 닫히지 않는다. */
    @Test
    fun closingTheResultOfAFinishedMatchStaysOpenAfterALateLobby() = runTest {
        val x = inMatch()
        val stale = CompletableDeferred<Unit>()
        val next = CompletableDeferred<Unit>()
        x.server.lobbies.addLast(Reply.Gate(stale, Reply.Json(lobbyJson(MATCH))))
        x.server.lobbies.addLast(Reply.Gate(next, Reply.Json(lobbyJson(null))))
        val first = launch { x.rummy.refreshLobby() }
        runCurrent()
        x.server.active = null
        x.rummy.applyState(state("finished", mine = "done", seq = 2))
        runCurrent()
        assertEquals(open, x.games.blocks(), "결과 화면은 판이 아니다")
        x.rummy.dismissResult()
        runCurrent()
        assertEquals(open, x.games.blocks())
        stale.complete(Unit)
        runCurrent()
        assertEquals(open, x.games.blocks(), "끝나기 전에 읽힌 로비가 입구를 다시 닫았다")
        next.complete(Unit)
        runCurrent()
        first.join()
    }

    /** ★ 앱을 내린 사이 90초 끊김으로 기권됐다(판은 다른 사람끼리 계속 — 내 자리만 forfeit). 돌아와 그 판을 읽으면 로비 답을 기다리지 않고 열린다. */
    @Test
    fun forfeitedWhileInTheBackgroundOpensOnTheStateAlone() = runTest {
        val x = inMatch()
        x.games.appDidEnterBackground()
        x.server.active = null
        x.server.state = Reply.Json("""{"status":"ok","state":${stateJson(mine = "forfeit", seq = 2)},"server_now_ms":$NOW_MS}""")
        val lobbyGate = CompletableDeferred<Unit>()
        x.server.lobbies.addLast(Reply.Gate(lobbyGate, Reply.Json(lobbyJson(null))))
        x.games.appDidBecomeActive()
        runCurrent()
        assertEquals(MATCH, x.rummy.match?.id?.lowercased)
        assertEquals(open, x.games.blocks(), "내 자리는 이미 기권인데 낡은 로비 id 로 막혀 있다")
        lobbyGate.complete(Unit)
        runCurrent()
        assertEquals(open, x.games.blocks())
    }

    /** 앱을 내렸다 돌아왔는데 판을 못 읽었다 — 끝났는지 모른다. 닫는 쪽으로 틀린다. */
    @Test
    fun backFromTheBackgroundWithoutAReadKeepsBlocking() = runTest {
        val x = inMatch()
        x.games.appDidEnterBackground()
        x.server.state = Reply.Offline
        x.server.lobbies.addLast(Reply.Offline)
        x.games.appDidBecomeActive()
        runCurrent()
        assertEquals(blocked, x.games.blocks())
    }

    /** 판이 정말 산다: 들고 있는 판이 있으면 나보다 늦게 온 '없음' 로비가 와도, 다른 기기가 쥔 판이면 id 만으로도 막는다. */
    @Test
    fun aLiveMatchKeepsBlocking() = runTest {
        val elsewhere = rig()
        elsewhere.rummy.applyLobby(lobby(MATCH))
        assertEquals(blocked, elsewhere.games.blocks(), "다른 기기가 쥔 판")

        val held = inMatch()
        held.rummy.applyLobby(lobby(null))
        assertEquals(blocked, held.games.blocks(), "로비가 '없음'이라도 쥔 판에 내 자리가 살아 있으면 막는다 — 그 판을 다시 읽어 안다")
    }

    /** ★ 값이 맞아도 화면이 모르면 막혀 보인다: 판을 쥐지 않은 채 로비 값만 풀릴 때 입구를 읽는 쪽이 다시 그려진다(1:1 카드는 `lobby` 를 안 읽는다). */
    @Test
    fun aReaderOfTheEntrancesIsWokenWhenOnlyTheServerIdClears() = runTest {
        val x = rig()
        x.rummy.applyLobby(lobby(MATCH))
        val seen = mutableListOf<GamesBusyGame?>()
        val observer = backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            snapshotFlow { x.games.chessEntryBlock }.collect { seen += it }
        }
        Snapshot.sendApplyNotifications()
        runCurrent()
        assertEquals(listOf<GamesBusyGame?>(GamesBusyGame.rummy), seen)
        x.rummy.applyLobby(lobby(null))
        Snapshot.sendApplyNotifications()
        runCurrent()
        assertEquals(listOf(GamesBusyGame.rummy, null), seen, "판이 끝났는데 카드가 그대로다")
        observer.cancel()
    }
}
