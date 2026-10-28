// 원본: Sources/CheckCore/DuelRPC.swift:11-47(교착 40P01 한 번 재시도) · Sources/CheckCore/SupabaseWorkModels.swift:3677-(GomokuWire p_protocol 2) @ 1b8260d
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.wire.games.GomokuStatePayload
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * G §2-3 W2-d ② 40P01 은 **정확히 한 번** 재시도한다(쓰기 RPC 만 — 읽기 전용 로비·받은함·판 조회는 재시도하지 않는다. 오목 `gomoku_state` 는
 * Swift 도 재시도하지 않는다) · ③ `p_protocol` 은 **언제나** 싣는다(오목 2). 스토어 문을 지나 실제로 나간 요청 수와 본문으로 잰다.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class GomokuWireContractTest {
    private fun TestScope.rig(me: String, configure: DuelStubServer.() -> Unit): Triple<GomokuStore, FakeDuelHost, DuelStubServer> {
        val server = DuelStubServer(this).apply(configure)
        val host = FakeDuelHost(server.service { contractClock }, me, clockNow = { contractClock })
        val store = GomokuStore(storeScope(), host)
        store.clock = { contractClock }
        return Triple(store, host, server)
    }

    private fun seed(store: GomokuStore, name: String) {
        val json = JsonObject(fixtureJSON(GOMOKU_FIXTURES, name) - "state")
        assertEquals(GomokuStore.StateApplyOutcome.applied, store.applyState(decodeJson(json, GomokuStatePayload.serializer())))
    }

    /** 흑 첫 수 자리의 판(기록 0, 흑 차례 — 흐름 m1 의 수락 응답) 위에서 둔다. */
    private val blackFirstSeed = "gomoku_respond__accept_ok"

    @Test
    fun deadlockOnMoveIsRetriedExactlyOnceThenApplied() = runTest {
        val seedFacts = GomokuServerFacts(blackFirstSeed)
        val (store, _, server) = rig(seedFacts.myID) {
            queue("gomoku_move", StubReply.deadlock)
            queueFixtures("gomoku_move", GOMOKU_FIXTURES, "gomoku_move__ok_black_first")
        }
        seed(store, blackFirstSeed)
        store.place(GomokuPoint.at(0, 0)!!)
        assertEquals(2, server.count("gomoku_move"), "교착 뒤 정확히 한 번 더 보낸다")
        // 재시도는 첫 시도와 **같은 요청**이다(교착으로 죽은 트랜잭션은 통째로 되돌려졌다).
        val bodies = server.bodies("gomoku_move")
        assertEquals(bodies[0], bodies[1])
        assertEquals(GomokuServerFacts("gomoku_move__ok_black_first").board, store.match?.board?.serverString)
        assertNull(store.notice, "재시도로 넘긴 교착이 안내로 샜다")
    }

    @Test
    fun secondDeadlockFailsWithoutAThirdAttempt() = runTest {
        val seedFacts = GomokuServerFacts(blackFirstSeed)
        val (store, _, server) = rig(seedFacts.myID) {
            queue("gomoku_move", StubReply.deadlock, StubReply.deadlock, StubReply.deadlock)
        }
        seed(store, blackFirstSeed)
        val before = store.match!!.board.serverString
        store.place(GomokuPoint.at(0, 0)!!)
        assertEquals(2, server.count("gomoku_move"), "두 번째 교착이면 그대로 던진다(무한 재시도 금지)")
        assertEquals(GomokuNoticeText.checkConnection, store.notice)
        assertEquals(before, store.match!!.board.serverString, "실패한 수가 판에 놓였다(낙관 착수 금지)")
        assertTrue(!store.isBusy)
    }

    /**
     * 표 시험(검증 V01·V03 — 첫 판은 쓰기 셋·읽기 셋만 쟀다): 오목 쓰기 RPC **여덟 전부**는 교착 둘 중 정확히 한 번 더(2회), 읽기 **여섯 전부**는
     * 다시 보내지 않는다(1회). 나머지 쓰기 셋(`gomoku_move` · `gomoku_chat_send` · `gomoku_leave`)은 위아래 시험이 같은 눈금으로 잰다.
     * 표는 Swift 원본에서 손으로 옮겼다(SupabaseWorkService.swift:1601-1771 — `retriesDeadlockOnce: true` 인 자리).
     */
    @Test
    fun deadlockRetryCoversEveryWriteRpcButNoRead() = runTest {
        val seedFacts = GomokuServerFacts(blackFirstSeed)
        val m1 = gomokuUser("m1")
        val writes = listOf("gomoku_challenge", "gomoku_cancel", "gomoku_respond", "gomoku_resign", "gomoku_chat_mute")
        val reads = listOf("gomoku_lobby", "gomoku_inbox", "gomoku_state", "gomoku_ranking", "gomoku_watch_live", "gomoku_watch")
        val (store, _, server) = rig(seedFacts.myID) {
            for (rpc in writes + reads) queue(rpc, StubReply.deadlock, StubReply.deadlock)
        }
        store.spectatorFeaturesEnabled = true
        // 쓰기 — 각 문이 실제로 RPC 를 내는 자리에 세워 둔다(보낸 신청 · 판).
        store.challenge(gomokuUser("B"))
        store.outgoing = GomokuInvite(m1, peerFor(gomokuUser("B")), 3, contractClock.addingTimeInterval(50.0))
        store.cancelChallenge()
        store.respond(m1, accept = false)
        seed(store, blackFirstSeed)
        store.setChatMuted(true)
        settle()
        store.resign()
        // 읽기 — 실패하면 다음 계기가 다시 읽는다.
        store.refreshLobby()
        store.loadInbox()
        store.refreshMatch(m1)
        store.loadRanking()
        // 관전 두 길: 관전자 수 길(`gomoku_watch_live`) → 옛 길(`gomoku_watch` — 이 로그인에서 접힌 뒤).
        store.match = null
        store.phase = GomokuPhase.lobby
        store.startWatching(gomokuUser("m_watch"))
        store.refreshWatch()
        store.spectatorCountUnavailable = true
        store.refreshWatch()
        settle()
        for (rpc in writes) assertEquals(2, server.count(rpc), "$rpc 는 쓰기다 — 교착 뒤 정확히 한 번 더 보낸다")
        for (rpc in reads) assertEquals(1, server.count(rpc), "$rpc 는 읽기다 — 교착을 다시 보내지 않는다(다음 계기가 다시 읽는다)")
        assertTrue(store.lobbyLoadFailed && store.inboxLoadFailed && store.rankingLoadFailed)
        assertNotNull(store.spectating, "교착 두 번(한도 3 아래)에 관전을 내렸다")
    }

    @Test
    fun deadlockOnChatSendAndLeaveIsRetriedOnce() = runTest {
        val finished = GomokuServerFacts("gomoku_state__finished_loser_since0")
        val (store, _, server) = rig(finished.myID) {
            queue("gomoku_chat_send", StubReply.deadlock)
            queueFixtures("gomoku_chat_send", GOMOKU_FIXTURES, "gomoku_chat_send__ok")
            queue("gomoku_leave", StubReply.deadlock)
            queueFixtures("gomoku_leave", GOMOKU_FIXTURES, "gomoku_leave__ok_one")
        }
        seed(store, "gomoku_state__finished_loser_since0")
        store.sendQuick(GomokuQuickPhrase.gg)
        settle()
        assertEquals(2, server.count("gomoku_chat_send"))
        assertEquals("quick", server.lastBody("gomoku_chat_send").str("p_kind"))
        assertEquals("gg", server.lastBody("gomoku_chat_send").str("p_body"))
        store.backToLobby()
        settle()
        assertEquals(2, server.count("gomoku_leave"), "결과 화면을 떠나는 나가기도 쓰기다")
    }

    @Test
    fun everyGomokuRequestCarriesProtocolTwo() = runTest {
        val seedFacts = GomokuServerFacts(blackFirstSeed)
        val m1 = gomokuUser("m1")
        val (store, _, server) = rig(seedFacts.myID) {
            queueFixtures("gomoku_lobby", GOMOKU_FIXTURES, "gomoku_lobby__ok")
            queueFixtures("gomoku_inbox", GOMOKU_FIXTURES, "gomoku_inbox__ok")
            queueFixtures("gomoku_challenge", GOMOKU_FIXTURES, "gomoku_challenge__ok")
            queueFixtures("gomoku_cancel", GOMOKU_FIXTURES, "gomoku_cancel__ok")
            queueFixtures("gomoku_respond", GOMOKU_FIXTURES, "gomoku_respond__decline_ok")
            queueFixtures("gomoku_move", GOMOKU_FIXTURES, "gomoku_move__ok_black_first")
            queueFixtures("gomoku_chat_mute", GOMOKU_FIXTURES, "gomoku_chat_mute__ok_on")
            queueFixtures("gomoku_ranking", GOMOKU_FIXTURES, "gomoku_ranking__ok")
            queueFixtures("gomoku_watch_live", GOMOKU_FIXTURES, "gomoku_watch__ok_since0")
        }
        store.spectatorFeaturesEnabled = true
        store.refreshLobby()
        store.loadInbox()
        store.challenge(gomokuUser("B"))
        store.cancelChallenge()
        store.respond(m1, accept = false)
        seed(store, blackFirstSeed)
        store.place(GomokuPoint.at(0, 0)!!)
        store.setChatMuted(true)
        settle()
        store.loadRanking()
        store.match = null
        store.phase = GomokuPhase.lobby
        store.startWatching(gomokuUser("m_watch"))
        store.refreshWatch()
        settle()
        val rpcs = server.calls.map { it.rpc }.toSet()
        for (expected in listOf(
            "gomoku_lobby", "gomoku_inbox", "gomoku_challenge", "gomoku_cancel", "gomoku_respond", "gomoku_move", "gomoku_chat_mute",
            "gomoku_state", "gomoku_ranking", "gomoku_watch_live",
        )) {
            assertTrue(expected in rpcs, "$expected 가 나가지 않았다 — 시험이 그 문을 지나지 않았다: $rpcs")
        }
        for (call in server.calls) {
            assertEquals(2L, call.body.long("p_protocol"), "${call.rpc} 본문에 p_protocol 2 가 없다: ${call.body}")
        }
        assertNotNull(store.spectating)
    }
}
