// 원본: Tests/checkTests/V0327GomokuStoreTests.swift:770-860(안전망 폴링 주기) · V0341GomokuWatchStoreTests.swift:565-630(창 치우기·닫기 × 관전) · V0350GomokuExitChatTests.swift(끝난 판에서만 나가기) · Sources/CheckCore/GomokuStore.swift(GomokuChallengeGate) @ 1b8260d
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.net.realtime.RealtimeState
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonArray
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 창 수명 · 안전망 폴링 주기 · [도전] 게이트(검증 지적 V09·V14·V17·V18 — 첫 판에는 INV 주석 표기만 있고 시험이 없었다).
 *  · 최소화(`windowDidHide`)는 **진행 중** 관전을 남기고, 정말 닫기(`windowDidClose`)는 내린다(INV-GomokuStore-3b89d982). 어느 쪽도 요청을 내지 않는다.
 *  · 최소화는 진행 중인 내 판에 `gomoku_leave` 를 **절대** 내지 않는다(닫기는 기권이 아니다). 끝난 판이면 한 번 낸다.
 *  · 상대 차례 상태 조회는 구독 중 **3초** · 미구독 **1.5초**, 보낸 신청 받은함은 **5초**, 로비 목록은 **30초**(무료 플랜 예산 — 손으로 적은 수).
 *  · [도전] 은 깃발 · 가능 · 대국 아님 · 보낸 신청 없음 · 판 없음 · 바쁘지 않음 **여섯 조건이 모두** 맞을 때만 선다.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class GomokuWindowPollTest {
    private fun TestScope.rig(me: String = HAND_ME, configure: DuelStubServer.() -> Unit = {}): Triple<GomokuStore, FakeDuelHost, DuelStubServer> {
        val server = DuelStubServer(this).apply(configure)
        val host = FakeDuelHost(server.service { contractClock }, me, clockNow = { contractClock })
        val store = GomokuStore(storeScope(), host)
        store.clock = { contractClock }
        return Triple(store, host, server)
    }

    // MARK: 창 × 관전

    @Test
    fun minimizingKeepsAnInProgressWatchAndClosingDropsItWithoutARequest() = runTest {
        val (store, _, server) = rig(gomokuUser("C")) {
            queueFixtures("gomoku_watch_live", GOMOKU_FIXTURES, "gomoku_watch__ok_since0")
        }
        store.spectatorFeaturesEnabled = true
        store.startWatching(gomokuUser("m_watch"))
        store.refreshWatch()
        assertEquals(false, store.spectating?.isFinished)
        val requests = server.calls.size

        store.windowDidHide()
        assertNotNull(store.spectating, "최소화가 진행 중인 관전을 내렸다 — 되살리면 로비로 떨어진다")

        store.windowDidClose()
        assertNull(store.spectating, "창을 닫았는데 진행 중인 관전이 남았다 — 다음에 열면 로비가 아니라 남의 판이 선다")
        assertEquals(GomokuPhase.lobby, store.phase)
        // 관전이 없으면 닫기는 아무 일도 안 한다(멱등).
        store.windowDidClose()
        advanceUntilIdle()
        assertEquals(requests, server.calls.size, "창 치우기·닫기가 요청을 냈다")
    }

    @Test
    fun minimizingDropsAFinishedWatch() = runTest {
        val (store, _, server) = rig(gomokuUser("C")) {
            queueFixtures("gomoku_watch_live", GOMOKU_FIXTURES, "gomoku_watch__ok_finished")
        }
        store.spectatorFeaturesEnabled = true
        val finishedID = fixtureJSON(GOMOKU_FIXTURES, "gomoku_watch__ok_finished").obj("match")!!.str("id")!!
        store.startWatching(finishedID)
        store.refreshWatch()
        assertEquals(true, store.spectating?.isFinished)
        val requests = server.calls.size
        store.windowDidHide()
        assertNull(store.spectating, "끝난 판을 관전한 채 창을 치웠는데 관전이 남았다 — 한 시간 뒤에도 낡은 남의 판이 선다")
        advanceUntilIdle()
        assertEquals(requests, server.calls.size)
    }

    // MARK: 창 × 내 판

    @Test
    fun minimizingNeverLeavesAnActiveMatchButLeavesAFinishedOneOnce() = runTest {
        val (store, _, server) = rig {
            respondWith("gomoku_leave") { _, _ -> jsonReply("status" to "ok", "both_left" to false) }
        }
        store.applyState(handPayload(handState(turn = "white")))
        store.windowDidShow()
        store.windowDidHide()
        store.windowDidClose()
        advanceUntilIdle()
        assertEquals(0, server.count("gomoku_leave"), "진행 중인 판에서 나가기를 냈다 — 닫기는 기권이 아니다")
        assertNotNull(store.match, "창을 내렸는데 진행 중인 판이 내려갔다")
        assertEquals(GomokuPhase.playing, store.phase)
        store.stopPolling()

        // 기준선: 끝난 판이면 결과 화면을 떠난 것이다 — 한 번.
        store.applyState(handPayload(handState(finished = true)))
        assertEquals(GomokuPhase.result, store.phase)
        store.windowDidHide()
        store.windowDidHide()
        advanceUntilIdle()
        assertEquals(1, server.count("gomoku_leave"), "끝난 판 나가기는 판마다 한 번이다")
        assertEquals(HAND_MATCH, server.lastBody("gomoku_leave").str("p_match_id"))
        assertEquals(GomokuPhase.result, store.phase, "최소화는 결과 화면을 남긴다(닫기만 내린다)")
        store.windowDidClose()
        assertNull(store.match)
        assertEquals(GomokuPhase.lobby, store.phase)
    }

    // MARK: 안전망 폴링 주기

    @Test
    fun opponentTurnPollingIsThreeSecondsSubscribedAndOneAndAHalfUnsubscribed() = runTest {
        var now = contractClock
        val (store, host, server) = rig {
            respondWith("gomoku_state") { _, _ -> handReply(handState(turn = "white", moveCount = 1, moves = listOf(handMove(1, "black", 7, 7)))) }
            respondWith("gomoku_lobby") { _, _ -> jsonReply("status" to "ok", "users" to JsonArray(emptyList())) }
        }
        store.clock = { now }
        val t0 = now
        store.applyState(handPayload(handState(turn = "white", moveCount = 1, moves = listOf(handMove(1, "black", 7, 7)))))
        assertEquals(false, store.match?.turn == store.match?.myColor)
        suspend fun tick(offset: Double) {
            now = t0.addingTimeInterval(offset)
            store.pollTick(now)
        }
        // 창이 안 보이면 상대 차례여도 아무것도 안 나간다.
        tick(1_000.0)
        assertTrue(server.calls.isEmpty())
        store.isWindowVisible = true
        now = t0
        store.lastStateRequestAt = t0
        // 미구독: 1.5초.
        tick(1.4)
        assertEquals(0, server.count("gomoku_state"), "미구독 주기(1.5초)보다 일찍 물었다")
        tick(1.5)
        assertEquals(1, server.count("gomoku_state"))
        tick(2.9)
        assertEquals(1, server.count("gomoku_state"))
        tick(3.0)
        assertEquals(2, server.count("gomoku_state"))
        // 구독 중: 3초(무료 플랜 예산 — 신호가 주 경로다).
        host.realtimeState = RealtimeState.Subscribed(t0, t0)
        tick(5.9)
        assertEquals(2, server.count("gomoku_state"), "구독 중인데 3초보다 일찍 물었다")
        tick(6.0)
        assertEquals(3, server.count("gomoku_state"))
        // 대국 중엔 로비 목록을 돌리지 않는다.
        assertEquals(0, server.count("gomoku_lobby"))
        // 내 차례면(마감 전) 상태를 묻지 않는다.
        store.applyState(handPayload(handState(turn = "black", moveCount = 2, moves = listOf(handMove(1, "black", 7, 7), handMove(2, "white", 8, 8)))))
        tick(60.0)
        assertEquals(3, server.count("gomoku_state"))
    }

    @Test
    fun anOutgoingInviteRereadsTheInboxEveryFiveSecondsAndTheLobbyEveryThirty() = runTest {
        var now = contractClock
        val (store, _, server) = rig {
            respondWith("gomoku_inbox") { _, _ -> jsonReply("status" to "ok", "incoming" to JsonArray(emptyList()), "outgoing" to null) }
            respondWith("gomoku_lobby") { _, _ -> jsonReply("status" to "ok", "users" to JsonArray(emptyList())) }
        }
        store.clock = { now }
        val t0 = now
        store.isWindowVisible = true
        store.outgoing = GomokuInvite("o1", peerFor(HAND_RIVAL), 5, t0.addingTimeInterval(3_600.0))
        store.lastInboxRequestAt = t0
        store.lastLobbyRequestAt = t0
        suspend fun tick(offset: Double) {
            now = t0.addingTimeInterval(offset)
            store.pollTick(now)
        }
        tick(4.9)
        assertEquals(0, server.count("gomoku_inbox"), "보낸 신청 받은함을 5초보다 일찍 물었다")
        tick(5.0)
        assertEquals(1, server.count("gomoku_inbox"))
        tick(29.9)
        assertEquals(0, server.count("gomoku_lobby"), "로비 목록을 30초보다 일찍 물었다")
        tick(30.0)
        assertEquals(1, server.count("gomoku_lobby"))
        // 창을 내리면 다시 조용하다.
        store.windowDidHide()
        val quiet = server.calls.size
        tick(10_000.0)
        assertEquals(quiet, server.calls.size)
    }

    // MARK: [도전] 게이트

    @Test
    fun theChallengeGateNeedsAllSixConditions() = runTest {
        val (store, _, _) = rig()
        val open = GomokuUser("x", "x", null, null, isWorking = true, isCapable = true, inMatch = false)
        assertTrue(GomokuPhoneChallengeGate.isEnabled(open, store), "기준선: 여섯 조건이 다 맞으면 [도전]이 선다")
        // 근무 여부는 보지 않는다(맥 GomokuChallengeGate 와 같다).
        assertTrue(GomokuPhoneChallengeGate.isEnabled(open.copy(isWorking = false), store), "근무 밖 상대를 막았다(v0.3.30 뒤로 신청은 근무 밖에서도 된다)")
        assertFalse(GomokuPhoneChallengeGate.isEnabled(open.copy(isCapable = false), store), "옛 버전 상대에게 [도전]이 선다")
        assertFalse(GomokuPhoneChallengeGate.isEnabled(open.copy(inMatch = true), store), "대국 중인 상대에게 [도전]이 선다")

        store.outgoing = GomokuInvite("o1", peerFor(HAND_RIVAL), 5, contractClock.addingTimeInterval(60.0))
        assertFalse(GomokuPhoneChallengeGate.isEnabled(open, store), "보낸 신청이 있는데 [도전]이 또 선다(서버는 already_pending)")
        store.outgoing = null
        assertTrue(GomokuPhoneChallengeGate.isEnabled(open, store))

        store.isBusy = true
        assertFalse(GomokuPhoneChallengeGate.isEnabled(open, store), "왕복 중에 [도전]이 선다")
        store.isBusy = false

        store.applyState(handPayload(handState()))
        assertFalse(GomokuPhoneChallengeGate.isEnabled(open, store), "내 판이 있는데 [도전]이 선다")
    }
}
