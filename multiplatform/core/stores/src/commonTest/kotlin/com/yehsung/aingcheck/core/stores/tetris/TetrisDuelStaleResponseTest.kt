// 원본: Tests/checkTests/V0360TetrisDuelStoreTests.swift `TetrisDuelStaleResponseTests` @ b4d39f4e (11-23 — 늦은 응답의 루비 되감기 · 판이 선 뒤 남는 닫힌 받은 신청)
package com.yehsung.aingcheck.core.stores.tetris

import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.Reply
import com.yehsung.aingcheck.core.stores.games.StoreFixtures
import com.yehsung.aingcheck.core.stores.games.StoreHarness
import com.yehsung.aingcheck.core.wire.games.TetrisStatePayload
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 11-06 길건너 1:1 적대 검토(RV-C-2 · RV-C-4)에서 "테트리스도 같은 꼴"로 적어 둔 결함 둘(대표 #d_1ud0gpD3pncN '작은 정리'). 맥 · 폰은 b4d39f4e 로
 * 고쳤고, 안드로이드는 따로 옮긴 Kotlin 이라 같은 모양으로 옮긴다. 고치기 전(xplat/c-v8 0e8b4e97)에는 앞의 두 시험이 빨갛다.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class TetrisDuelStaleResponseTest {
    private val nowMs = TetrisDuelStoreTest.NOW_MS
    private val me = StoreFixtures.USER
    private val peer = StoreFixtures.PEER
    private val json = Json { ignoreUnknownKeys = true }

    private fun state(status: String, serverNowMs: Long, ruby: Long?, id: String = "m-1", winner: String? = null): TetrisStatePayload =
        json.decodeFromString(
            TetrisStatePayload.serializer(),
            """{"match_id":"$id","status":"$status","stake":3,"seed":77,"server_now_ms":$serverNowMs,"start_at_ms":${nowMs - 60_000},"my_device":"this",""" +
                (ruby?.let { """"ruby_balance":$it,""" } ?: "") +
                (if (status == "finished") """"result":"challenger_win","winner":"${winner ?: me}","end_reason":"topout",""" else "") +
                """"me":{"id":"$me","seq":4,"ready":true},"opponent":{"id":"$peer","display_name":"구름빵","seq":4,"ready":true}}""",
        )

    private fun lobby(ruby: Long, serverNowMs: Long, incoming: String = "", outgoing: String? = null): Reply = Reply.Json(
        """{"status":"ok","server_now_ms":$serverNowMs,"me":{"ruby_balance":$ruby,"wins":0,"losses":0,"draws":0,"incoming":[$incoming]""" +
            (outgoing?.let { ""","outgoing":{"match_id":"$it","to":{"id":"$peer","display_name":"구름빵"},"stake":3,"expires_at_ms":${nowMs + 60_000}}""" } ?: "") +
            """},"users":[],"matches":[]}""",
    )

    private val otherInvite =
        """{"match_id":"c0de0000-0000-4000-8000-0000000000ee","from":{"id":"00000000-0000-0000-0000-0000000000c3","display_name":"씨"},"stake":3,"expires_at_ms":${nowMs + 50_000}}"""

    private suspend fun TestScope.harness(lobbyReply: () -> Reply): StoreHarness {
        val h = StoreHarness(this, AppConfig(duelsEnabled = true), route = { r -> if (r.rpcName == "tetris_lobby") lobbyReply() else null })
        h.signIn()
        h.tetris.uptime = { testScheduler.currentTime / 1000.0 }
        return h
    }

    /** 정산 뒤 닿은 옛 상태(판 값은 ignored)·옛 로비가 루비 잔액(스토어 · 앱 미러)을 되감지 않는다. 기준선: 더 새 응답은 덮는다. */
    @Test
    fun staleResponsesDoNotRewindRuby() = runTest {
        val h = harness { lobby(ruby = 100, serverNowMs = nowMs) }
        val store = h.tetris
        val older = state("active", nowMs, ruby = 97)
        assertEquals(TetrisDuelStore.StateApplyOutcome.applied, store.applyState(older, 0.0))
        assertEquals(97L, store.rubyBalance)
        assertEquals(TetrisDuelStore.StateApplyOutcome.applied, store.applyState(state("finished", nowMs + 2_000, ruby = 103), 0.0))
        assertEquals(103L, store.rubyBalance)
        assertEquals(103L, h.tetrisHost.rubyBalance)
        // ① 늦게 닿은 옛 상태 — 판 값은 버려진다. 루비도 버려져야 한다.
        assertEquals(TetrisDuelStore.StateApplyOutcome.ignored, store.applyState(older, 0.0))
        assertEquals(103L, store.rubyBalance, "버린 옛 상태가 루비 잔액을 되감았다")
        assertEquals(103L, h.tetrisHost.rubyBalance, "버린 옛 상태가 앱 루비 미러를 되감았다")
        // ② 늦게 닿은 옛 로비(서버 시각 t0 · 잔액 100).
        store.refreshLobby()
        runCurrent()
        assertEquals(103L, store.rubyBalance, "정산 전 로비가 늦게 닿아 루비 잔액을 되감았다")
        assertEquals(103L, h.tetrisHost.rubyBalance)
        // 기준선: 더 새 응답(t0 + 4초 · 110)은 덮는다.
        assertEquals(TetrisDuelStore.StateApplyOutcome.applied, store.applyState(state("finished", nowMs + 4_000, ruby = 110), 0.0))
        assertEquals(110L, store.rubyBalance)
        assertEquals(110L, h.tetrisHost.rubyBalance)
        // 로그아웃(reset) 뒤에는 처음부터 — 다음 사람의 첫 응답이 옛 서버 시각이어도 옮긴다.
        store.reset()
        assertEquals(TetrisDuelStore.StateApplyOutcome.applied, store.applyState(older, 0.0))
        assertEquals(97L, store.rubyBalance)
    }

    /** 보낸 신청이 판이 되면 서버가 닫은 다른 받은 신청이 화면 값에 남지 않는다(기준선: 판 전엔 보인다). */
    @Test
    fun challengerDropsClosedIncomingWhenMatchStarts() = runTest {
        val h = harness { lobby(ruby = 100, serverNowMs = nowMs, incoming = otherInvite, outgoing = "m-1") }
        val store = h.tetris
        store.refreshLobby()
        runCurrent()
        assertEquals(1, store.incoming.size, "기준선: 판 전엔 받은 신청이 보인다")
        assertEquals("m-1", store.outgoing?.id)
        assertEquals(TetrisDuelStore.StateApplyOutcome.applied, store.applyState(state("active", nowMs + 1_000, ruby = 97), 0.0))
        assertEquals("m-1", store.match?.id)
        assertTrue(store.incoming.isEmpty(), "판이 선 순간 닫힌 받은 신청을 걷지 않았다")
        assertEquals(null, store.outgoing, "보낸 신청은 판이 되었다")
    }

    /** 대조: 끝난 판을 처음 받을 때(판이 끝난 뒤 앱을 연 경우 등)는 받은 신청을 걷지 않는다 — 판이 끝난 뒤 새로 온 신청일 수 있다. */
    @Test
    fun finishedMatchKeepsIncoming() = runTest {
        val h = harness { lobby(ruby = 100, serverNowMs = nowMs, incoming = otherInvite) }
        val store = h.tetris
        store.refreshLobby()
        runCurrent()
        assertEquals(1, store.incoming.size)
        assertEquals(TetrisDuelStore.StateApplyOutcome.applied, store.applyState(state("finished", nowMs + 1_000, ruby = 103), 0.0))
        assertTrue(store.match?.isFinished == true)
        assertEquals(1, store.incoming.size, "끝난 판을 받았다고 판 뒤에 온 신청까지 걷었다")
    }
}
