// 판 7 아잉 뒤집기 검토 수리(S-F1 · S-F2 · S-F5 · U-F4)를 재는 시험 — Swift 원본에는 없는 Android 몫이다.
package com.yehsung.aingcheck.core.stores.reversi

import com.yehsung.aingcheck.core.rules.reversi.ReversiRules
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.gomoku.DuelStubServer
import com.yehsung.aingcheck.core.stores.gomoku.FakeDuelHost
import com.yehsung.aingcheck.core.stores.gomoku.REVERSI_FIXTURES
import com.yehsung.aingcheck.core.stores.gomoku.StubReply
import com.yehsung.aingcheck.core.stores.gomoku.contractClock
import com.yehsung.aingcheck.core.stores.gomoku.decodeFixture
import com.yehsung.aingcheck.core.stores.gomoku.fixtureJSON
import com.yehsung.aingcheck.core.stores.gomoku.fixtureText
import com.yehsung.aingcheck.core.stores.gomoku.obj
import com.yehsung.aingcheck.core.stores.gomoku.storeScope
import com.yehsung.aingcheck.core.stores.gomoku.str
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ReversiActionResponse
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiStatePayload
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.job
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 판 7 검토 지적을 **결과로** 잰다. 각 시험의 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가"다(계약 시험과 같은 규약).
 * 앱 범위는 `Dispatchers.Main.immediate`(androidApp AppContainer)라 `launch` 가 그 자리에서 곧바로 돈다 — 그 성질이 필요한 시험은
 * [UnconfinedTestDispatcher] 범위로 흉내 낸다(계약 시험의 Standard 디스패처는 그 갈래를 못 본다).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ReversiStoreReviewTest {
    private val viewerA: String get() = fixtureJSON(REVERSI_FIXTURES, "_manifest").obj("viewers")!!.str("A")!!
    private val viewerB: String get() = fixtureJSON(REVERSI_FIXTURES, "_manifest").obj("viewers")!!.str("B")!!
    private val mainMatch: String get() = fixtureJSON(REVERSI_FIXTURES, "reversi_state__my_turn").obj("state")!!.obj("match")!!.str("id")!!

    /** 관전 픽스처의 판 id(남의 판 — 관전 응답이 실제로 옮겨지게). */
    private val watchedMatch: String get() = fixtureJSON(REVERSI_FIXTURES, "reversi_watch_live__ok").obj("state")!!.obj("match")!!.str("id")!!

    private fun json(name: String) = StubReply.Json(fixtureText(REVERSI_FIXTURES, name))

    private fun state(name: String): ReversiStatePayload = decodeFixture(REVERSI_FIXTURES, name, ReversiActionResponse.serializer()).state!!

    private class Rig(val store: ReversiStore, val server: DuelStubServer)

    /** [immediate] = 앱처럼 `launch` 가 곧바로 도는 범위. 시계는 시험 스케줄러의 가상 시간과 함께 흐른다. */
    private fun TestScope.rig(me: String, immediate: Boolean = false, bodies: Map<String, (Int) -> StubReply> = emptyMap()): Rig {
        val server = DuelStubServer(this)
        for ((rpc, reply) in bodies) server.respondWith(rpc) { _, index -> reply(index) }
        val now = { contractClock.addingTimeInterval(testScheduler.currentTime / 1000.0) }
        val host = FakeDuelHost(server.service(now), me, AppConfig(duelsEnabled = true), clockNow = now)
        val scope = if (immediate) {
            val job = SupervisorJob()
            backgroundScope.coroutineContext.job.invokeOnCompletion { job.cancel() }
            CoroutineScope(UnconfinedTestDispatcher(testScheduler) + job)
        } else {
            storeScope()
        }
        val store = ReversiStore(scope, host)
        store.clock = now
        store.pollStepSeconds = 3_600.0
        store.aiRuntime.minimumThinkSeconds = 0.0
        store.aiRuntime.randomIndex = { 0 }
        store.aiMoveChooser = { board, color -> ReversiRules.legalMoves(board, color).firstOrNull() }
        return Rig(store, server)
    }

    // MARK: S-F1 — 초인종 직렬화가 끝난 Job 으로 굳지 않는다

    @Test
    fun signalMergedIntoInFlightLobbyDoesNotFreezeLaterSignalsOnAnImmediateScope() = runTest {
        // 없으면: 앱 범위(Main.immediate)에서 로비가 도는 사이 온 초인종이 `syncTask` 를 끝난 Job 으로 굳혀, 그 뒤 초인종(받은 신청 · 수락 · 상대 수)이
        // 로그아웃 전까지 전부 버려져도 초록이다 — 받은 신청이 다음 허브 진입까지 안 서고, 보낸 신청의 수락이 판 화면을 못 연다.
        val r = rig(
            viewerB, immediate = true,
            bodies = mapOf(
                "reversi_lobby" to { index ->
                    when (index) {
                        0 -> StubReply.Delayed(1.0, json("reversi_lobby__ok")) // 허브 열기 · 폴링 같은 무거운 조회가 먼저 돈다
                        1 -> json("reversi_lobby__ok") // 그 조회에 합쳐진 초인종의 뒤따르는 한 번
                        else -> json("reversi_lobby__incoming") // 나중 초인종 — 신청이 왔다
                    }
                },
            ),
        )
        val store = r.store
        store.launch { store.refreshLobby() }
        runCurrent()
        assertEquals(1, r.server.count("reversi_lobby"))
        store.handleSignal() // 도는 로비에 합쳐진다(lobbyAgain) — 이 호출은 한 번도 멈추지 않고 끝난다
        advanceTimeBy(1_100)
        runCurrent()
        assertEquals(2, r.server.count("reversi_lobby"), "합쳐진 초인종의 뒤따르는 한 번")
        assertFalse(store.syncTask?.isActive == true, "도는 직렬화가 없는데 '도는 중'으로 남았다")
        assertTrue(store.incoming.isEmpty())
        // 나중 초인종 — 새 조회가 나가 신청이 서야 한다.
        store.handleSignal()
        runCurrent()
        assertEquals(3, r.server.count("reversi_lobby"), "나중 초인종이 굳은 직렬화에 막혀 버려졌다")
        assertEquals(listOf(mainMatch), store.incoming.map { it.id })
        // 기준선: 도는 중에 온 초인종 둘은 여전히 뒤따르는 **한 번**으로 합친다(폭주 없음).
        val base = rig(
            viewerB, immediate = true,
            bodies = mapOf("reversi_lobby" to { index -> if (index == 0) StubReply.Delayed(0.5, json("reversi_lobby__ok")) else json("reversi_lobby__incoming") }),
        )
        base.store.handleSignal()
        base.store.handleSignal()
        base.store.handleSignal()
        advanceTimeBy(600)
        runCurrent()
        assertEquals(2, base.server.count("reversi_lobby"))
        assertEquals(1, base.store.incoming.size)
    }

    // MARK: S-F2 — 관전 조회가 폴링 취소에 '도는 중'으로 굳지 않는다

    @Test
    fun watchPollCancelledByBackgroundDoesNotFreezeLaterWatchReads() = runTest {
        // 없으면: 관전 2초 폴링의 조회가 날던 중 앱이 뒤로 가면(stopPolling 의 취소) `watchInFlight` 가 참으로 남아, 앞으로 돌아와도 관전 판·시계·관전자 수가
        // 영영 멈춘 채여도 초록이다(관전을 나갔다 다시 들어가야 풀린다).
        val r = rig(
            viewerA,
            bodies = mapOf("reversi_watch_live" to { index -> if (index == 1) StubReply.Delayed(1.0, json("reversi_watch_live__ok")) else json("reversi_watch_live__ok") }),
        )
        val store = r.store
        store.spectatorFeaturesEnabled = true
        store.isWindowVisible = true
        store.pollStepSeconds = 0.5
        store.lastLobbyRequestAt = contractClock.addingTimeInterval(1_000_000.0) // 로비 30초 폴링은 이 시험 밖
        store.startWatching(watchedMatch)
        runCurrent()
        assertEquals(1, r.server.count("reversi_watch_live"))
        assertEquals(1, store.spectatorCount, "관전 응답이 옮겨지지 않았다(픽스처 판 id)")
        store.startPolling()
        advanceTimeBy(2_600) // 2초 주기 조회(둘째 — 1초 늦게 온다)가 날고 있다
        assertEquals(2, r.server.count("reversi_watch_live"))
        store.windowOcclusionDidChange(visible = false) // 앱이 뒤로 — 폴링 취소가 날던 조회에 닿는다
        runCurrent()
        store.windowOcclusionDidChange(visible = true)
        advanceTimeBy(10_000)
        runCurrent()
        assertTrue(r.server.count("reversi_watch_live") >= 4, "다시 앞으로 온 뒤 관전 조회가 나가지 않았다: ${r.server.count("reversi_watch_live")}건")
        assertNotNull(store.spectating)
    }

    // MARK: S-F5 — 로비가 진행 판이 없다고 하면 들고 있던 1:1 판을 한 번 다시 읽는다

    @Test
    fun lobbyWithoutActiveMatchRereadsTheHeldLiveMatchOnce() = runTest {
        // 없으면: 앱이 뒤에 있는 사이 서버가 닫은 판(자동 착수 3번)을 '진행 중'으로 들고 있어, 리버시 카드를 열 때까지 다른 네 게임 입구가 막히고 화면 꺼짐
        // 방지가 켜진 채여도 초록이다.
        val r = rig(
            viewerA,
            bodies = mapOf(
                "reversi_lobby" to { _ -> json("reversi_lobby__ok") }, // A 의 로비 — active_match_id null
                "reversi_state" to { _ -> json("reversi_state__finished") }, // 그 판은 이미 끝났다
            ),
        )
        val store = r.store
        store.applyState(state("reversi_state__their_turn"))
        assertEquals(false, store.match?.isFinished)
        store.refreshLobby()
        runCurrent()
        assertEquals(1, r.server.count("reversi_state"), "로비가 진행 판이 없다고 했는데 들고 있던 판을 다시 읽지 않았다")
        assertEquals(true, store.match?.isFinished)
        assertNull(store.activeMatchID)
        // 끝난 판을 들고 있으면 더 읽지 않는다(폭주 없음).
        store.refreshLobby()
        runCurrent()
        assertEquals(1, r.server.count("reversi_state"))
        // 기준선: 로비가 그 판을 진행 중이라 말하면 다시 읽지 않는다.
        val lobbyWithActive = fixtureText(REVERSI_FIXTURES, "reversi_lobby__ok").replace("\"active_match_id\": null", "\"active_match_id\": \"$mainMatch\"")
        assertTrue(lobbyWithActive.contains(mainMatch), "픽스처 모양이 바뀌었다")
        val base = rig(viewerA, bodies = mapOf("reversi_lobby" to { _ -> StubReply.Json(lobbyWithActive) }, "reversi_state" to { _ -> json("reversi_state__finished") }))
        base.store.applyState(state("reversi_state__their_turn"))
        base.store.refreshLobby()
        runCurrent()
        assertEquals(0, base.server.count("reversi_state"))
        assertEquals(false, base.store.match?.isFinished)
    }

    @Test
    fun lobbyThatPredatesAWriteDoesNotRereadTheHeldMatch() = runTest {
        // 없으면: 쓰기(기권)보다 먼저 나간 로비의 '진행 판 없음'까지 믿고 판을 또 읽어도 초록이다 — 그 응답은 그 뒤 사실을 모른다(writeRevision).
        val r = rig(
            viewerA,
            bodies = mapOf(
                "reversi_lobby" to { _ -> StubReply.Delayed(1.0, json("reversi_lobby__ok")) },
                "reversi_resign" to { _ -> StubReply.Json("""{"status":"not_active","server_now_ms":null,"ruby_balance":null}""") },
            ),
        )
        val store = r.store
        store.applyState(state("reversi_state__their_turn"))
        store.launch { store.refreshLobby() }
        runCurrent()
        store.resign() // 쓰기 응답이 먼저 돌아온다
        val statesAfterWrite = r.server.count("reversi_state")
        advanceTimeBy(1_100)
        runCurrent()
        assertEquals(statesAfterWrite, r.server.count("reversi_state"), "쓰기보다 먼저 나간 로비가 판 다시 읽기를 냈다")
    }

    // MARK: U-F4 — 내 차례가 돌아오면 '상대 차례예요'를 걷는다

    @Test
    fun notYourTurnNoticeClearsWhenTheTurnComesBack() = runTest {
        // 없으면: 로봇 판에서 칸을 빠르게 두 번 누른 뒤(둘째 누름 = 로봇 차례) 다시 내 차례가 와도 '상대 차례예요'가 '내 차례예요'와 함께 남아도 초록이다.
        val r = rig(viewerB)
        val store = r.store
        store.isWindowVisible = true
        store.startAIMatch(ReversiColor.black)
        runCurrent()
        assertTrue(store.match!!.isMyTurn)
        val first = store.legalTargets.first()
        store.place(first) // 첫 누름 — 바로 두어지고 로봇 차례
        assertFalse(store.match!!.isMyTurn)
        store.place(store.match!!.board.let { board -> (0 until 64).first { board[it] == null } }) // 둘째 누름
        assertEquals(ReversiNoticeText.notYourTurn, store.notice)
        runCurrent() // 로봇이 둔다
        assertTrue(store.match!!.isMyTurn, "로봇이 두지 않았다")
        assertNull(store.notice, "내 차례가 돌아왔는데 '상대 차례예요'가 남았다")
        // 기준선: 아직 상대 차례인 동안의 안내는 그대로다(로봇이 생각 중).
        val slow = rig(viewerB)
        slow.store.isWindowVisible = true
        slow.store.aiRuntime.minimumThinkSeconds = 5.0
        slow.store.startAIMatch(ReversiColor.black)
        runCurrent()
        slow.store.place(slow.store.legalTargets.first())
        slow.store.place(0)
        runCurrent()
        assertFalse(slow.store.match!!.isMyTurn)
        assertEquals(ReversiNoticeText.notYourTurn, slow.store.notice)
    }
}
