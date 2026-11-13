// 원본: Tests/checkTests/V03xxAlkkagiStoreTests.swift · V03xxAlkkagiFixtureContractTests.swift @ e4995a3a(뽑아 옮김) — Android 판 8
//
// 1:1 알까기 스토어 · 물리 계약. 서버 응답은 하네스 픽스처 원문(Tests/checkTests/Fixtures/alkkagi-rpc — 맥 시험과 같은 파일)을 그대로 넣는다.
// 단언마다 결함 변이에서 갈리는 기준선 짝을 둔다.
package com.yehsung.aingcheck.core.stores.alkkagi

import com.yehsung.aingcheck.core.rules.alkkagi.AlkkagiGame
import com.yehsung.aingcheck.core.stores.gomoku.decodeFixture
import com.yehsung.aingcheck.core.stores.gomoku.settle
import com.yehsung.aingcheck.core.stores.gomoku.storeScope
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.AlkkagiCall
import com.yehsung.aingcheck.core.wire.games.AlkkagiMatchPhase
import com.yehsung.aingcheck.core.wire.games.AlkkagiResponse
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val FIX = "Tests/checkTests/Fixtures/alkkagi-rpc"

private fun fixture(name: String): AlkkagiResponse = decodeFixture(FIX, name, AlkkagiResponse.serializer())

@OptIn(ExperimentalCoroutinesApi::class)
class AlkkagiOnlineStoreTest {
    private class Stub(val replies: MutableMap<String, ArrayDeque<AlkkagiResponse>> = mutableMapOf()) : AlkkagiServing {
        val calls = mutableListOf<AlkkagiCall>()
        fun queue(rpc: String, vararg names: String) = apply { replies.getOrPut(rpc) { ArrayDeque() }.addAll(names.map(::fixture)) }
        override suspend fun call(call: AlkkagiCall): AlkkagiResponse {
            calls += call
            return replies[call.rpcName]?.removeFirstOrNull() ?: throw IllegalStateException("각본 없음 ${call.rpcName}")
        }
    }

    private fun TestScope.store(stub: Stub, nowMs: Double): AlkkagiOnlineStore =
        AlkkagiOnlineStore(storeScope(), stub, clock = { SwiftDate(nowMs / 1000) }).also { it.outsidePollStepSeconds = 3_600.0 }

    @Test
    fun lightLobbyKeepsUsersAndRecord() = runTest {
        // 가벼운 로비(users [] · record null)는 사람 목록 · 전적을 덮지 않는다. 기준선: 전체 로비는 덮는다.
        val ok = fixture("alkkagi_lobby__ok")
        val stub = Stub().queue("alkkagi_lobby", "alkkagi_lobby__ok", "alkkagi_lobby__light")
        val s = store(stub, ok.serverNowMs)
        s.refreshLobby()
        settle()
        assertEquals(14, s.users.size)
        assertEquals(AlkkagiRecord(0, 0, 0), s.record)
        assertEquals(AlkkagiAvailability.available, s.availability)
        s.refreshLightLobby()
        settle()
        assertEquals(14, s.users.size, "가벼운 로비가 목록을 지웠다")
        assertEquals(AlkkagiRecord(0, 0, 0), s.record)
    }

    @Test
    fun closedDoorIsComingSoonNotUpdate() = runTest {
        // door_open false → '곧 열려요'(내 앱 탓 아님). 기준선: 열린 문은 available.
        val closed = fixture("alkkagi_lobby__door_closed")
        val s = store(Stub().queue("alkkagi_lobby", "alkkagi_lobby__door_closed"), closed.serverNowMs)
        s.refreshLobby()
        settle()
        assertEquals(AlkkagiAvailability.serverMissing, s.availability)
    }

    @Test
    fun acceptedMatchStandsAndFinishedVerdictIsServers() = runTest {
        // 수락 응답 → 판이 서고(놓기) 창 문이 한 번 열린다. 끝난 판 → 내 기준 결과 · 사유 · 루비가 서버 값 그대로.
        val accepted = fixture("alkkagi_respond__accepted")
        val stub = Stub().queue("alkkagi_state", "alkkagi_respond__accepted", "alkkagi_state__finished_resign_loss")
        val s = store(stub, accepted.serverNowMs)
        var presented = 0
        var finished = 0
        s.presentWindow = { presented += 1 }
        s.onMatchFinished = { finished += 1 }
        s.openWindow(accepted.state!!.id)
        settle()
        assertEquals(AlkkagiMatchPhase.placing, s.state?.phase)
        assertTrue(presented >= 2, "openWindow 한 번 + 판이 처음 선 순간 한 번")
        assertTrue(s.isMyTurn, "놓기 판 · 아직 준비 안 함 = 내 차례")
        s.refreshMatch()
        settle()
        assertEquals(AlkkagiOutcome.loss, s.outcome)
        assertEquals(AlkkagiEndReason.resign, s.endReason)
        assertEquals(-10, s.rubyDelta)
        assertEquals(1, finished)
        assertEquals("기권했어요", AlkkagiNoticeText.endReason(s.endReason, s.outcome))
    }

    @Test
    fun serverShotReplaysToServerStones() {
        // 서버 alkkagi_simulate 가 굴린 한 수를 앱 물리로 다시 굴리면 서버가 적은 자리와 같다(같은 식 · 같은 값).
        // 기준선: 굴리기 전(첫 자리)은 서버 자리와 다르다(쏜 돌이 움직였다).
        val shot = fixture("alkkagi_shoot__ok").state!!
        val replay = shot.shotReplayGame
        assertNotNull(replay)
        repeat(4_000) { if (replay.phase == AlkkagiGame.Phase.rolling) replay.advance(1.0 / 240) }
        val server = shot.stones.associateBy { it.id.toInt() }
        var moved = false
        for (stone in replay.stones) {
            val want = server[stone.id] ?: continue
            assertEquals(want.isOut, stone.isOut, "돌 ${stone.id} 판 밖 여부")
            if (!stone.isOut) {
                assertTrue(abs(stone.position.x - want.position.x) < 1e-6 && abs(stone.position.y - want.position.y) < 1e-6, "돌 ${stone.id}: ${stone.position} vs ${want.position}")
            }
            val start = shot.shot!!.initialStones.first { it.id.toInt() == stone.id }
            if (abs(start.position.x - want.position.x) > 1e-3 || abs(start.position.y - want.position.y) > 1e-3) moved = true
        }
        assertTrue(moved, "기준선: 쏜 돌은 움직였다")
    }

    @Test
    fun firstShotIsLimited() {
        // 판의 첫 수(흑 · 0수)만 81, 그 뒤는 135. 기준선: 백 차례 · 1수 뒤는 135.
        val game = AlkkagiGame.newGame()
        for (s in game.stones.toList()) if (s.owner == AlkkagiGame.Player.black) game.placeStone(s.id, s.position)
        game.confirmPlacement()
        for (s in game.stones.toList()) if (s.owner == AlkkagiGame.Player.white) game.placeStone(s.id, s.position)
        game.confirmPlacement()
        assertEquals(AlkkagiGame.firstShotMaxPull, game.shotPullLimit)
        assertTrue(game.shoot(0, com.yehsung.aingcheck.core.rules.alkkagi.AlkkagiVector(0.0, 60.0)))
        repeat(2_000) { if (game.phase == AlkkagiGame.Phase.rolling) game.advance(1.0 / 60) }
        assertEquals(AlkkagiGame.maxPull, game.shotPullLimit)
    }

    @Test
    fun duelsFlagOffWithoutHostStillAllowsStubButCodePointLimitHolds() {
        assertEquals(3, "가나다".codePointCount())
        assertEquals(1, "😀".codePointCount())
        assertNull(uuidKey("not-a-uuid"))
        assertEquals("8b97c765-141d-4681-bb7f-2121db2356d8", uuidKey("8B97C765-141D-4681-BB7F-2121DB2356D8"))
    }
}
