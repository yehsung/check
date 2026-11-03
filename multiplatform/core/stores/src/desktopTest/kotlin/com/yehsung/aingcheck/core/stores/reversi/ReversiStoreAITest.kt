// 원본: Tests/checkTests/V03xxReversiAIStoreTests.swift @ 12624739
package com.yehsung.aingcheck.core.stores.reversi

import com.yehsung.aingcheck.core.rules.ai.ReversiAIGame
import com.yehsung.aingcheck.core.rules.reversi.ReversiRules
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.gomoku.DuelStubServer
import com.yehsung.aingcheck.core.stores.gomoku.FakeDuelHost
import com.yehsung.aingcheck.core.stores.gomoku.REVERSI_FIXTURES
import com.yehsung.aingcheck.core.stores.gomoku.contractClock
import com.yehsung.aingcheck.core.stores.gomoku.decodeFixture
import com.yehsung.aingcheck.core.stores.gomoku.storeScope
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ReversiActionResponse
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiEndReason
import com.yehsung.aingcheck.core.wire.games.ReversiMatchStatus
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * AI 연습 판(로컬) 흐름 — 서버와 섞이지 않는다(요청 0 · 미션 꼬리 없음 · `ai-` id 는 서버 경로를 못 지난다). 사람 시계는 화면이 보일 때만 돈다.
 * 선택기는 결정적 가짜(첫 합법 수)로 갈아 끼운다 — 엔진 품질은 core/rules 시험 몫이다.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ReversiStoreAITest {
    private class Rig(val store: ReversiStore, val server: DuelStubServer, val now: () -> SwiftDate, val setNow: (SwiftDate) -> Unit)

    private fun TestScope.rig(): Rig {
        var now = contractClock
        val server = DuelStubServer(this)
        val host = FakeDuelHost(server.service { now }, "b0000000-0000-4000-8000-000000000002", AppConfig(duelsEnabled = true), clockNow = { now })
        val store = ReversiStore(storeScope(), host)
        store.clock = { now }
        store.pollStepSeconds = 3_600.0
        store.aiRuntime.minimumThinkSeconds = 0.0
        store.aiRuntime.randomIndex = { 0 }
        store.aiMoveChooser = { board, color -> ReversiRules.legalMoves(board, color).firstOrNull() }
        return Rig(store, server, { now }, { now = it })
    }

    @Test
    fun aiMatchPlaysLocallyWithoutServerOrMissionTail() = runTest {
        // 없으면: AI 판이 서버로 요청을 내거나(없는 판 id) · 미션 꼬리를 울리거나 · AI 가 흑일 때 첫 수를 안 둬 판이 멈춰도 초록이다.
        val r = rig()
        val store = r.store
        var finished = 0
        store.onMatchFinished = { finished += 1 }
        store.isWindowVisible = true
        assertTrue(store.canStartAIMatch)
        store.startAIMatch(ReversiColor.white) // 사람이 백 — AI(흑)가 먼저 둔다
        val opened = assertNotNull(store.match)
        assertTrue(opened.isAI)
        assertTrue(ReversiAIGame.isAIMatchID(opened.id))
        assertEquals(ReversiUser.reversiAI, opened.opponent)
        assertTrue(store.isAIThinking)
        runCurrent()
        assertEquals(1, store.match?.moveCount, "AI(흑)가 첫 수를 안 뒀다")
        assertTrue(store.match!!.isMyTurn)
        assertNotNull(store.match?.deadline, "사람 차례 시계가 돈다(화면이 보인다)")
        val target = store.legalTargets.first()
        store.place(target)
        runCurrent()
        assertTrue(store.match!!.moveCount >= 3, "사람 수 뒤에 AI 가 이어 두지 않았다")
        // 서버 경로는 막힌다.
        store.refreshMatch(store.match!!.id)
        store.handleSignal()
        runCurrent()
        assertTrue(r.server.calls.none { it.rpc != "reversi_lobby" }, "AI 판이 서버로 나갔다: ${r.server.calls.map { it.rpc }}")
        // 기권 — 결과 화면이지만 미션 꼬리는 없다(서버가 AI 판을 안 센다).
        store.resign()
        assertEquals(ReversiPhase.result, store.phase)
        assertEquals(ReversiEndReason.resign, store.match?.endReason)
        assertEquals(ReversiMatchOutcome.lost, store.match?.outcome)
        assertEquals(0, finished)
        // [다시 두기] — 같은 색으로 새 판.
        store.restartAIMatch()
        assertEquals(ReversiColor.white, store.match?.myColor)
        assertFalse(store.match!!.isFinished)
        // [로비로] — AI 판은 접히고 요청은 안 나간다(1:1 결과의 [로비로]는 로비·순위를 다시 읽는다 — AI 판은 아니다).
        store.resign()
        val callsBefore = r.server.calls.size
        store.backToLobby()
        assertNull(store.match)
        assertNull(store.aiGame)
        runCurrent()
        assertEquals(callsBefore, r.server.calls.size)
    }

    @Test
    fun hiddenScreenPausesHumanClockAndResumes() = runTest {
        // 없으면: 화면을 떠난 사이 사람 시계가 흘러 돌아오면 자동 착수가 쌓여 있어도 초록이다(기다리는 상대가 없다).
        val r = rig()
        val store = r.store
        store.isWindowVisible = true
        store.startAIMatch(ReversiColor.black)
        assertNotNull(store.match?.deadline)
        store.windowDidHide()
        assertNull(store.match?.deadline, "숨김이 사람 시계를 멈추지 않았다")
        r.setNow(r.now().addingTimeInterval(120.0))
        store.handleAIClock(r.now())
        assertEquals(0, store.match?.moveCount, "멈춘 시계로 자동 착수했다")
        store.windowDidShow()
        val deadline = assertNotNull(store.match?.deadline)
        assertEquals(30.0, deadline.timeIntervalSince(r.now()), 0.01, "이어 간 시계가 남은 30초를 그대로 줘야 한다")
        // 가림(앱이 background)도 같다.
        store.windowOcclusionDidChange(visible = false)
        assertNull(store.match?.deadline)
        store.windowOcclusionDidChange(visible = true)
        assertNotNull(store.match?.deadline)
    }

    @Test
    fun humanClockExpiryAutoPlacesAndThreeStrikesLose() = runTest {
        // 없으면: 사람이 30초를 넘겨도 판이 멈춰 서거나 · 연속 3번 자동 착수에도 판이 안 끝나도 초록이다(서버 1:1 과 같은 규칙).
        val r = rig()
        val store = r.store
        store.isWindowVisible = true
        store.startAIMatch(ReversiColor.black)
        var strikes = 0
        while (store.match?.isFinished == false && strikes < 5) {
            r.setNow(r.now().addingTimeInterval(31.0))
            store.handleAIClock(r.now())
            runCurrent()
            strikes += 1
        }
        val done = assertNotNull(store.match)
        assertTrue(done.isFinished)
        assertEquals(ReversiEndReason.abandoned, done.endReason)
        assertEquals(3, strikes)
        assertEquals(ReversiNoticeText.autoPlaced, store.notice)
    }

    @Test
    fun oneOnOneMatchWinsOverAIAndStaleAIMoveIsDropped() = runTest {
        // 없으면: AI 가 생각하는 사이 1:1 판이 열려도 늦게 끝난 AI 수가 1:1 판 위에 놓이거나 AI 판이 남아도 초록이다.
        val r = rig()
        val store = r.store
        val gate = CompletableDeferred<Int?>()
        store.aiMoveChooser = { _, _ -> gate.await() }
        store.isWindowVisible = true
        store.startAIMatch(ReversiColor.white) // AI 가 생각을 시작한다
        runCurrent()
        assertTrue(store.isAIThinking)
        val payload = decodeFixture(REVERSI_FIXTURES, "reversi_state__my_turn", ReversiActionResponse.serializer()).state!!
        store.applyState(payload) // 1:1 판이 이긴다
        assertNull(store.aiGame, "1:1 판이 서면 AI 판은 버려진다")
        assertFalse(store.match!!.isAI)
        gate.complete(19)
        runCurrent()
        assertEquals(0, store.match?.moveCount, "늦게 끝난 AI 수가 1:1 판에 놓였다")
        assertEquals(ReversiMatchStatus.active, store.match?.status)
        // 1:1 판이 있으면 AI 판을 못 연다(두던 판이 사라진다).
        assertFalse(store.canStartAIMatch)
        store.startAIMatch(ReversiColor.black)
        assertEquals(ReversiNoticeText.busy, store.notice)
        assertFalse(store.match!!.isAI)
    }
}
