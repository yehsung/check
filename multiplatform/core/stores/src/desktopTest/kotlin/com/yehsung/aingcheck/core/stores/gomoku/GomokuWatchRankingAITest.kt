// 원본: Tests/checkTests/V0341GomokuWatchStoreTests.swift · V0341GomokuRankingStoreTests.swift · V0364ChessGomokuWatcherCountTests.swift · V0332GomokuAIMatchTests.swift(스토어 몫) @ 1b8260d
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuOutcome
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.wire.games.GomokuStatePayload
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** G §2-3 W2-d ④ 관전·순위·AI 동작(스토어 몫). 관전·순위는 주 스위치(`spectatorFeaturesEnabled`) 아래에서만 돈다. */
@OptIn(ExperimentalCoroutinesApi::class)
class GomokuWatchRankingAITest {
    private val watchID: String get() = gomokuUser("m_watch")

    private fun TestScope.rig(me: String = gomokuUser("C"), configure: DuelStubServer.() -> Unit = {}): Triple<GomokuStore, FakeDuelHost, DuelStubServer> {
        val server = DuelStubServer(this).apply(configure)
        val host = FakeDuelHost(server.service { contractClock }, me, clockNow = { contractClock })
        val store = GomokuStore(storeScope(), host)
        store.clock = { contractClock }
        store.spectatorFeaturesEnabled = true
        return Triple(store, host, server)
    }

    private fun watchFacts(name: String): JsonObject = fixtureJSON(GOMOKU_FIXTURES, name)

    // MARK: 관전

    @Test
    fun watchLiveFoldsOnceToOldWatchAndKeepsTheEntryOpen() = runTest {
        val (store, _, server) = rig {
            queue("gomoku_watch_live", StubReply.missingFunction("gomoku_watch_live"))
            queueFixtures("gomoku_watch", GOMOKU_FIXTURES, "gomoku_watch__ok_since0", "gomoku_watch__ok_since2")
        }
        store.startWatching(watchID)
        assertNotNull(store.spectating)
        assertFalse(store.spectating!!.hasServerState, "첫 응답 전에 흑·백을 지어냈다")
        store.refreshWatch()
        assertEquals(1, server.count("gomoku_watch_live"))
        assertEquals(1, server.count("gomoku_watch"), "관전자 수 함수가 없을 때 같은 바퀴 안에서 옛 관전으로 접지 않았다")
        assertTrue(store.spectatorCountUnavailable)
        assertFalse(store.watchUnavailable, "관전자 수가 없다는 이유로 관전 입구를 잠갔다(깃발 겸업)")
        assertEquals(0L, store.spectatorCount)
        val since0 = watchFacts("gomoku_watch__ok_since0")
        val watch = assertNotNull(store.spectating)
        assertEquals(since0.obj("black_user")!!.str("user_id"), watch.black?.id)
        assertEquals(since0.obj("white_user")!!.str("user_id"), watch.white?.id)
        assertEquals(since0.obj("match")!!.str("board"), watch.board.serverString)
        assertEquals(2, watch.moveCount)
        assertEquals(2, watch.appliedSeq)
        assertEquals(GomokuColor.black, watch.turn)
        assertNull(store.notice)
        // 둘째 바퀴: 접힘은 로그인 동안 한 번만 판정한다(폴링마다 404 를 더 쏘지 않는다) · 증분(since 2).
        store.refreshWatch()
        assertEquals(1, server.count("gomoku_watch_live"), "접힌 뒤에도 live 를 다시 불렀다")
        assertEquals(2L, server.lastBody("gomoku_watch").long("p_since_seq"))
        assertEquals(3, store.spectating?.moveCount)
        assertEquals(GomokuColor.white, store.spectating?.turn)
        // 로그아웃이 접힘을 푼다(다음 로그인은 서버가 올라왔을 수 있다).
        store.reset()
        assertFalse(store.spectatorCountUnavailable)
    }

    @Test
    fun watchMissingLocksTheEntryAndFoldsRankingOnlyWhenNeverLoaded() = runTest {
        val (store, _, server) = rig {
            queue("gomoku_watch_live", StubReply.missingFunction("gomoku_watch_live"))
            queue("gomoku_watch", StubReply.missingFunction("gomoku_watch"))
        }
        store.startWatching(watchID)
        store.refreshWatch()
        assertNull(store.spectating)
        assertTrue(store.watchUnavailable)
        assertEquals(GomokuNoticeText.watchUnavailable, store.notice)
        assertTrue(store.rankingUnavailable && store.hasLoadedRanking, "순위를 한 번도 못 받았으면 같은 배포 창으로 본다")
        // 문 앞에서 막는다 — 다시 눌러도 요청이 나가지 않는다.
        val before = server.calls.size
        store.startWatching(watchID)
        store.refreshWatch()
        assertNull(store.spectating)
        assertEquals(before, server.calls.size, "잠긴 관전 입구가 404 를 또 냈다")
    }

    @Test
    fun watchNotFoundStopsAndSaysGone() = runTest {
        val (store, _, _) = rig { queueFixtures("gomoku_watch_live", GOMOKU_FIXTURES, "gomoku_watch__not_found") }
        store.startWatching(watchID)
        store.refreshWatch()
        assertNull(store.spectating)
        assertEquals(GomokuNoticeText.watchGone, store.notice)
        assertFalse(store.watchUnavailable, "판이 없다는 것과 함수가 없다는 것을 겸업했다")
    }

    @Test
    fun watchThrowFailuresDropOnlyAfterTheLimit() = runTest {
        val (store, _, server) = rig {
            queue("gomoku_watch_live", StubReply.Offline, StubReply.Offline, StubReply.Offline)
        }
        store.startWatching(watchID)
        repeat(GomokuStore.watchFailureLimit - 1) { store.refreshWatch() }
        assertNotNull(store.spectating, "한두 번의 흔들림에 관전을 내렸다")
        store.refreshWatch()
        assertNull(store.spectating, "빈 판 관전이 실패를 영영 돈다")
        assertEquals(GomokuNoticeText.checkConnection, store.notice)
        assertEquals(GomokuStore.watchFailureLimit, server.count("gomoku_watch_live"))
        assertFalse(store.spectatorCountUnavailable, "5xx·오프라인 한 번에 관전자 수를 영영 껐다")
    }

    @Test
    fun watcherCountRidesTheLiveResponseAndResetsWhenWatchingStops() = runTest {
        val withWatchers = JsonObject(watchFacts("gomoku_watch__ok_since0") + ("watchers" to JsonPrimitive(4)))
        val (store, _, _) = rig { queue("gomoku_watch_live", StubReply.Json(withWatchers.toString())) }
        store.startWatching(watchID)
        store.refreshWatch()
        assertEquals(4L, store.spectatorCount)
        store.stopWatching()
        assertEquals(0L, store.spectatorCount, "보던 판의 관전자 수가 로비로 따라왔다")
    }

    @Test
    fun ownMatchCarriesItsWatcherCountAndOpeningItDropsTheWatch() = runTest {
        val facts = GomokuServerFacts("flow_m1_k2_white_state_since2")
        val (store, _, _) = rig(me = facts.myID) { queueFixtures("gomoku_watch_live", GOMOKU_FIXTURES, "gomoku_watch__ok_since0") }
        store.startWatching(watchID)
        store.refreshWatch()
        assertNotNull(store.spectating)
        val generation = store.watchRuntime.watchGeneration
        val json = JsonObject(fixtureJSON(GOMOKU_FIXTURES, "flow_m1_k2_white_state_since2") - "state" + ("watchers" to JsonPrimitive(2)))
        store.applyState(decodeJson(json, GomokuStatePayload.serializer()))
        assertNull(store.spectating, "내 판이 섰는데 관전이 남았다")
        assertTrue(store.watchRuntime.watchGeneration > generation, "관전 세대를 안 올려 늦은 관전 응답이 내 판 위를 덮을 수 있다")
        assertEquals(2L, store.spectatorCount, "내 판의 관전자 수")
    }

    // MARK: 순위

    @Test
    fun rankingKeepsServerOrderAndMatchesTheRule() = runTest {
        val (store, _, server) = rig(me = gomokuUser("A")) { queueFixtures("gomoku_ranking", GOMOKU_FIXTURES, "gomoku_ranking__ok") }
        store.loadRanking()
        assertEquals(1, server.count("gomoku_ranking"))
        val board = assertNotNull(store.ranking)
        val rows = fixtureJSON(GOMOKU_FIXTURES, "gomoku_ranking__ok")["rows"]!!.jsonArray.map { it.jsonObject }
        assertEquals(rows.map { it.str("user_id")!!.lowercase() }, board.entries.map { it.id }, "서버 순서를 다시 정렬했다")
        assertEquals(listOf(1L, 2L, 3L, 3L, 5L), board.entries.map { it.rank })
        assertTrue(GomokuRankingOrder.isSorted(board.entries))
        assertTrue(GomokuRankingOrder.ranksMatchServerRule(board.entries))
        assertNull(board.recordSince, "record_since_ms null(컷 -infinity)인데 캡션 날짜를 지어냈다")
        assertEquals(board.me, store.myRankConsistentWithRecord, "로비를 못 받았으면 순위 응답이 유일한 출처다")
        store.record = GomokuRecord(99, 0, 0)
        assertNull(store.myRankConsistentWithRecord, "로비 전적과 다른 순위를 머리글에 냈다(자기모순 문장)")
        assertFalse(store.rankingLoadFailed)
        assertNull(store.notice)
    }

    @Test
    fun rankingSchemaMissingIsUnavailableNotAFailureAndNeverANotice() = runTest {
        val (store, _, _) = rig { queue("gomoku_ranking", StubReply.missingFunction("gomoku_ranking")) }
        store.loadRanking()
        assertTrue(store.rankingUnavailable)
        assertTrue(store.hasLoadedRanking)
        assertFalse(store.rankingLoadFailed)
        assertNull(store.notice, "순위 실패가 대국 상태줄로 샜다")
    }

    @Test
    fun spectatorSwitchOffSendsNoRankingAndNoWatch() = runTest {
        val (store, _, server) = rig()
        store.spectatorFeaturesEnabled = false
        store.loadRanking()
        store.startWatching(watchID)
        store.refreshWatch()
        store.windowDidShow()
        store.pollSpectatorFeatures(contractClock.addingTimeInterval(600.0))
        settle()
        store.stopPolling()
        assertEquals(0, server.count("gomoku_ranking"))
        assertEquals(0, server.count("gomoku_watch_live") + server.count("gomoku_watch"))
        assertNull(store.spectating)
    }

    // MARK: AI

    @Test
    fun aiMatchPlaysLocallyAndNeverHitsTheServer() = runTest {
        val (store, _, server) = rig()
        store.aiRuntime.minimumThinkSeconds = 0.0
        store.aiRuntime.randomIndex = { 0 }
        val center = GomokuPoint.at(7, 7)!!
        store.aiMoveChooser = { _, _ -> center } // 두 번째부터는 이미 돌이 있는 자리 — 스토어가 합법 수로 대신 둔다
        var finishedCalls = 0
        store.onMatchFinished = { finishedCalls += 1 }
        store.startAIMatch(GomokuColor.white)
        settle()
        assertTrue(store.isAIMatch)
        assertEquals(GomokuPhase.playing, store.phase)
        assertEquals(GomokuColor.black, store.match?.board?.get(center), "AI 가 흑 첫 수를 두지 않았다")
        assertEquals(GomokuColor.white, store.match?.turn)
        store.place(GomokuPoint.at(7, 8)!!)
        settle()
        assertEquals(3, store.match?.moveCount, "AI 가 답수를 두지 않았다(규칙 밖 수의 대타 포함)")
        assertEquals(2, store.aiRuntime.chooserCalls)
        // 거절 가드는 1:1 과 같은 순서다 — 이미 돌이 있는 자리.
        store.place(center)
        assertEquals(GomokuNoticeText.occupied, store.notice)
        store.resign()
        assertEquals(true, store.match?.isFinished)
        assertEquals(GomokuOutcome.lost, store.match?.outcome)
        assertEquals(0, finishedCalls, "AI 판 끝남이 일일 미션 고리를 불렀다(서버 판이 아니다)")
        assertEquals(GomokuPhase.result, store.phase)
        assertTrue(server.calls.isEmpty(), "AI 판이 서버로 나갔다: ${server.calls.map { it.rpc }}")
        store.backToLobby()
        settle()
        assertNull(store.match)
        assertNull(store.aiGame)
        assertEquals(GomokuPhase.lobby, store.phase)
        // [로비로]는 1:1 과 같은 길로 로비·받은함만 다시 읽는다 — AI 판 id 로 나가기·판 조회를 내지 않는다.
        assertEquals(setOf("gomoku_lobby", "gomoku_inbox"), server.calls.map { it.rpc }.toSet())
    }

    @Test
    fun aServerMatchAlwaysWinsOverTheAIGame() = runTest {
        val facts = GomokuServerFacts("flow_m1_k2_white_state_since2")
        val (store, _, _) = rig(me = facts.myID)
        store.aiRuntime.minimumThinkSeconds = 0.0
        store.aiMoveChooser = { _, _ -> null }
        store.startAIMatch(GomokuColor.black)
        assertTrue(store.isAIMatch)
        val generation = store.aiRuntime.generation
        store.applyState(decodeJson(JsonObject(fixtureJSON(GOMOKU_FIXTURES, "flow_m1_k2_white_state_since2") - "state"), GomokuStatePayload.serializer()))
        assertFalse(store.isAIMatch)
        assertNull(store.aiGame, "1:1 판이 열렸는데 AI 판이 남았다")
        assertTrue(store.aiRuntime.generation > generation, "늦게 끝난 AI 수를 버릴 세대가 안 올랐다")
        assertFalse(store.canStartAIMatch, "진행 중 1:1 판 위에 AI 판을 열 수 있다")
    }
}
