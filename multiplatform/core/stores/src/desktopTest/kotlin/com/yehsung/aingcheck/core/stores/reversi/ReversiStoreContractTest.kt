// 원본: Tests/checkTests/V03xxReversiStoreTests.swift · V03xxReversiStoreRecheckTests.swift · V03xxReversiWatchTests.swift(스토어 몫) @ 12624739
package com.yehsung.aingcheck.core.stores.reversi

import com.yehsung.aingcheck.core.rules.reversi.ReversiRules
import com.yehsung.aingcheck.core.rules.reversi.ReversiScore
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.gomoku.DuelStubServer
import com.yehsung.aingcheck.core.stores.gomoku.FakeDuelHost
import com.yehsung.aingcheck.core.stores.gomoku.REVERSI_FIXTURES
import com.yehsung.aingcheck.core.stores.gomoku.StubReply
import com.yehsung.aingcheck.core.stores.gomoku.bool
import com.yehsung.aingcheck.core.stores.gomoku.contractClock
import com.yehsung.aingcheck.core.stores.gomoku.decodeFixture
import com.yehsung.aingcheck.core.stores.gomoku.fixtureJSON
import com.yehsung.aingcheck.core.stores.gomoku.fixtureText
import com.yehsung.aingcheck.core.stores.gomoku.long
import com.yehsung.aingcheck.core.stores.gomoku.obj
import com.yehsung.aingcheck.core.stores.gomoku.objects
import com.yehsung.aingcheck.core.stores.gomoku.storeScope
import com.yehsung.aingcheck.core.stores.gomoku.str
import com.yehsung.aingcheck.core.wire.games.ReversiActionResponse
import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiCounts
import com.yehsung.aingcheck.core.wire.games.ReversiEndReason
import com.yehsung.aingcheck.core.wire.games.ReversiIllegalReason
import com.yehsung.aingcheck.core.wire.games.ReversiLobbyResponse
import com.yehsung.aingcheck.core.wire.games.ReversiRPCStatus
import com.yehsung.aingcheck.core.wire.games.ReversiResult
import com.yehsung.aingcheck.core.wire.games.ReversiStatePayload
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 아잉 뒤집기 스토어 × 서버 픽스처 원문(`Tests/checkTests/Fixtures/reversi-rpc` — 하네스에서 RPC 를 실제로 부른 jsonb 51장). **모양이 아니라 결과를 잰다.**
 * 원문으로 못 만드는 장면(진부분집합 합법 수 · 늦은 응답)은 원문을 읽어 **한 칸만** 바꿔 쓴다 — 바꾼 칸은 시험마다 적었다.
 * 각 시험의 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가"다(Swift 원본과 같은 규약).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ReversiStoreContractTest {
    private val manifest: JsonObject get() = fixtureJSON(REVERSI_FIXTURES, "_manifest")
    private val viewerA: String get() = manifest.obj("viewers")!!.str("A")!!
    private val viewerB: String get() = manifest.obj("viewers")!!.str("B")!!

    /** 픽스처 b_flow 의 주 판 id(실행마다 바뀌는 값이라 원문에서 읽는다). */
    private val mainMatch: String get() = fixtureJSON(REVERSI_FIXTURES, "reversi_state__my_turn").obj("state")!!.obj("match")!!.str("id")!!

    private fun viewer(name: String): String =
        manifest["files"]!!.objects().first { it.str("file") == "$name.json" }.str("viewer") ?: viewerA

    private fun text(name: String): String = fixtureText(REVERSI_FIXTURES, name)

    private fun state(name: String): ReversiStatePayload = decodeFixture(REVERSI_FIXTURES, name, ReversiActionResponse.serializer()).state!!

    /** 원문의 `state` 봉투 안 한 칸만 바꾼 본문. */
    private fun mutatedState(name: String, edit: (MutableMap<String, kotlinx.serialization.json.JsonElement>) -> Unit): String {
        val top = Json.parseToJsonElement(text(name)).jsonObject.toMutableMap()
        val inner = top["state"]!!.jsonObject.toMutableMap()
        edit(inner)
        top["state"] = JsonObject(inner)
        return JsonObject(top).toString()
    }

    private fun stateText(body: String): ReversiStatePayload = SwiftJson.decode(ReversiActionResponse.serializer(), body).state!!

    private class Rig(val store: ReversiStore, val host: FakeDuelHost, val server: DuelStubServer)

    /** rpc 이름 → 응답 본문 목록(n 번째 호출이 n 번째 본문, 모자라면 마지막이 반복 — Swift `rvHandler` 와 같다). 표에 없는 rpc 는 500. */
    private fun TestScope.rig(me: String, appConfig: AppConfig = AppConfig(duelsEnabled = true), bodies: Map<String, List<StubReply>> = emptyMap()): Rig {
        val server = DuelStubServer(this)
        for ((rpc, list) in bodies) server.respondWith(rpc) { _, index -> list[minOf(index, list.size - 1)] }
        val host = FakeDuelHost(server.service { contractClock }, me, appConfig, clockNow = { contractClock })
        val store = ReversiStore(storeScope(), host)
        store.clock = { contractClock }
        store.pollStepSeconds = 3_600.0
        store.aiRuntime.minimumThinkSeconds = 0.0
        return Rig(store, host, server)
    }

    private fun json(name: String) = StubReply.Json(text(name))

    // MARK: ① 받은 쪽 흐름(Swift `로비_신청_수락_착수_신호_패스_끝_결과_로비`)

    @Test
    fun receiverFlowLobbyAcceptMoveSignalPassFinishResult() = runTest {
        // 없으면: 로비가 받은 신청을 안 세우거나 · 수락이 판을 안 열거나 · 착수가 응답 전에 판을 그리거나(낙관적) · 신호가 구멍 난 기록을 그대로 그리거나 ·
        // 패스를 말하지 않거나 · 끝난 판이 결과/미션 꼬리를 안 내도 초록이다. 전제: 받은 쪽(B)이 흑으로 뽑힌 원문이다.
        for (name in listOf("reversi_lobby__incoming", "reversi_respond__accepted", "reversi_move__ok", "reversi_move__ok_pass", "reversi_move__finished_board_full")) {
            assertEquals(viewerB, viewer(name), "$name: 시청자가 B 가 아니다")
        }
        assertEquals(ReversiColor.black, state("reversi_respond__accepted").myColor, "B 가 흑이 아닌 원문이다")
        val r = rig(
            viewerB,
            bodies = mapOf(
                // 둘째 로비(끝난 순간 전적 다시 읽기)는 남의(A) 로비 원문이라 잔액이 다르다 — 정산 단언 뒤에 닿게 늦춘다(요청은 보낸 순간 센다).
                "reversi_lobby" to listOf(json("reversi_lobby__incoming"), StubReply.Delayed(5.0, json("reversi_lobby__ok"))),
                "reversi_respond" to listOf(json("reversi_respond__accepted")),
                "reversi_move" to listOf(
                    StubReply.Delayed(0.3, json("reversi_move__ok")),
                    StubReply.Delayed(0.3, json("reversi_move__finished_board_full")),
                ),
                "reversi_state" to listOf(json("reversi_move__ok_pass")),
                "reversi_ranking" to listOf(json("reversi_ranking__ok")),
            ),
        )
        val store = r.store
        val arrived = mutableListOf<String>()
        var finished = 0
        store.onInviteArrived = { arrived += it.id }
        store.onMatchFinished = { finished += 1 }

        store.refreshLobby()
        assertEquals(ReversiPhase.lobby, store.phase)
        assertEquals(ReversiAvailability.available, store.availability)
        assertEquals(listOf(mainMatch), store.incoming.map { it.id })
        assertEquals(viewerA, store.visibleIncoming?.peer?.id)
        assertEquals(5, store.visibleIncoming?.stake)
        assertEquals(listOf(mainMatch), arrived)
        assertTrue(store.users.any { it.id == viewerA && it.isCapable })
        assertTrue(store.users.any { !it.isCapable }, "capable false 행도 그대로 실린다(화면이 잠근다)")
        assertEquals(ReversiRecord(0, 0, 0), store.record)
        assertEquals(100L, store.rubyBalance)
        assertTrue(store.hasLoadedLobby)

        store.respond(mainMatch, accept = true)
        assertEquals(ReversiPhase.playing, store.phase)
        val opened = assertNotNull(store.match)
        assertEquals(mainMatch, opened.id)
        assertEquals(ReversiColor.black, opened.myColor)
        assertTrue(opened.isMyTurn)
        assertEquals(setOf(19, 26, 37, 44), store.legalTargets)
        assertTrue(store.incoming.isEmpty())
        assertNull(store.visibleIncoming)
        assertEquals(95L, store.rubyBalance, "수락 순간 판돈 차감(서버 값)")
        assertEquals(95L, r.host.rubyBalance, "호스트 루비 미러도 서버 값")
        assertNull(store.notice, "수락 성공은 말하지 않는다(판이 답한다)")
        assertTrue(store.defersMegaphoneBanner)

        // 착수 — 응답(0.3초 지연)이 오기 **전에는** 판이 그대로다(낙관적 그림 없음).
        val placing = launch { store.place(19) }
        runCurrent()
        assertTrue(store.isBusy)
        assertEquals(ReversiBoard.start, store.match?.board)
        assertEquals(0, store.match?.moveCount)
        // 왕복 중에 또 누르면 요청 없이 "보내는 중".
        store.place(26)
        assertEquals(ReversiNoticeText.sending, store.notice)
        advanceTimeBy(400)
        runCurrent()
        placing.join()
        assertEquals(1, store.match?.moveCount)
        assertEquals(ReversiColor.black, store.match?.board?.get(19))
        assertEquals(ReversiColor.black, store.match?.board?.get(27), "뒤집힌 돌")
        assertEquals(19, store.match?.lastStoneIdx)
        assertEquals(false, store.match?.isMyTurn)
        assertTrue(store.legalTargets.isEmpty())
        assertFalse(store.isBusy)
        val moveBody = r.server.bodies("reversi_move").first()
        assertEquals(0L, moveBody.long("p_expected_seq"))
        assertEquals(19L, moveBody.long("p_idx"))
        assertEquals(1L, moveBody.long("p_protocol"))
        assertEquals(1, r.server.count("reversi_move"), "왕복 중에 누른 칸은 요청이 아니다")

        // 상대 차례에 또 누르면 요청 없이 문구만.
        store.place(26)
        assertEquals(ReversiNoticeText.notYourTurn, store.notice)
        assertEquals(1, r.server.count("reversi_move"))

        // 신호 → 그 판 조회(since=1). 온 기록이 seq 3 부터라 구멍 — 처음부터(since=0) 한 번 더 받아 다시 짓는다.
        store.handleSignal()
        runCurrent()
        assertEquals(listOf(1L, 0L), r.server.bodies("reversi_state").map { it.long("p_since_seq") })
        assertEquals(4, store.match?.moveCount)
        assertEquals(true, store.match?.isMyTurn)
        assertEquals(setOf(58), store.legalTargets)
        assertEquals(listOf(3L, 4L), store.match?.plies?.map { it.seq })
        // 상대(백)가 둘 곳이 없어 내 차례가 이어진다 — 상태줄이 말한다.
        val rivalName = fixtureJSON(REVERSI_FIXTURES, "reversi_move__ok_pass").obj("state")!!.obj("opponent")!!.str("display_name")!!
        assertEquals(ReversiNoticeText.opponentPassed(rivalName), store.notice)

        // 판을 끝내는 수 — 결과 화면 · 미션 꼬리 한 번 · 로비 다시 읽기.
        val ending = launch { store.place(58) }
        advanceTimeBy(400)
        runCurrent()
        ending.join()
        assertEquals(ReversiPhase.result, store.phase)
        val done = assertNotNull(store.match)
        assertTrue(done.isFinished)
        assertEquals(ReversiMatchOutcome.won, done.outcome)
        assertEquals(ReversiEndReason.boardFull, done.endReason)
        assertEquals(ReversiScore(41, 23, ReversiResult.blackWin), done.score)
        assertEquals(ReversiCounts(41, 23, 0), done.counts)
        assertNull(done.deadline)
        assertNull(store.remainingSeconds(contractClock))
        assertEquals(105L, store.rubyBalance, "승자 정산(서버 값)")
        assertEquals(1, finished)
        assertNull(store.notice, "지난 패스 안내는 다음 수가 오면 걷힌다")
        runCurrent()
        assertEquals(2, r.server.count("reversi_lobby"), "끝난 순간 전적을 다시 읽는다")

        store.backToLobby()
        assertEquals(ReversiPhase.lobby, store.phase)
        assertNull(store.match)
        assertFalse(store.defersMegaphoneBanner)
        // 접은 판의 늦은 끝난 응답은 결과 화면을 되살리지 않는다.
        assertEquals(ReversiStore.StateApplyOutcome.ignored, store.applyState(state("reversi_move__finished_board_full")))
        assertNull(store.match)
        assertEquals(1, finished)
        // p_protocol 은 언제나 1.
        for (call in r.server.calls) assertEquals(1L, call.body.long("p_protocol"), "${call.rpc}: ${call.body}")
    }

    // MARK: ② 보낸 신청 폴링

    @Test
    fun outgoingInvitePollsStateEveryFiveSecondsWithoutSignal() = runTest {
        // 없으면: 신청자가 초인종을 놓치면(재연결 중) 로비 30초 주기로만 수락을 알아 흑 첫 수가 자동 착수가 되는데도 초록이다.
        assertEquals(viewerA, viewer("reversi_challenge__ok"))
        assertEquals(viewerA, viewer("reversi_state__their_turn"))
        var now = contractClock
        val r = rig(
            viewerA,
            bodies = mapOf(
                "reversi_challenge" to listOf(json("reversi_challenge__ok")),
                "reversi_state" to listOf(json("reversi_state__their_turn")),
            ),
        )
        val store = r.store
        store.clock = { now }
        store.applyLobby(decodeFixture(REVERSI_FIXTURES, "reversi_lobby__ok", ReversiLobbyResponse.serializer()))
        store.selectedStake = ReversiStake.five
        store.challenge(viewerB)
        val sent = assertNotNull(store.outgoing)
        assertEquals(mainMatch, sent.id)
        assertEquals(viewerB, sent.peer.id)
        assertEquals(5, sent.stake)
        assertEquals(ReversiNoticeText.challenge(ReversiRPCStatus.ok), store.notice)
        val body = r.server.lastBody("reversi_challenge")
        assertEquals(viewerB, body.str("p_opponent"))
        assertEquals(5L, body.long("p_stake"))
        assertFalse(store.canStartAIMatch, "보낸 신청이 떠 있으면 AI 판을 못 연다")

        store.isWindowVisible = true
        store.lastLobbyRequestAt = now // 로비 30초 분기는 이 시험 밖
        store.lastMenuLobbyAt = now
        val t0 = now
        // 기준선: 5초 전에는 아무것도 안 묻는다.
        store.pollTick(t0.addingTimeInterval(4.9))
        assertEquals(0, r.server.count("reversi_state"))
        assertEquals(ReversiPhase.lobby, store.phase)
        now = t0.addingTimeInterval(5.0)
        store.pollTick(now)
        assertEquals(1, r.server.count("reversi_state"))
        assertEquals(mainMatch, r.server.lastBody("reversi_state").str("p_match_id"))
        assertEquals(ReversiPhase.playing, store.phase)
        assertNull(store.outgoing)
        assertEquals(ReversiColor.white, store.match?.myColor)
        assertEquals(false, store.match?.isMyTurn)
        assertTrue(store.legalTargets.isEmpty())
    }

    // MARK: ③ 합법 수는 서버 목록만

    @Test
    fun serverLegalSubsetBlocksRuleLegalCellWithoutRequest() = runTest {
        // 없으면: 스토어가 `ReversiRules.legalMoves` 로 점을 그리고 입력을 받아도 진짜 판에선 늘 같아 전부 초록이다.
        assertEquals(viewerB, viewer("reversi_state__my_turn"))
        val narrowed = mutatedState("reversi_state__my_turn") { it["legal_moves"] = JsonArray(listOf(JsonPrimitive(19))) } // 바꾼 칸: legal_moves
        val r = rig(viewerB, bodies = mapOf("reversi_move" to listOf(json("reversi_move__ok"))))
        assertEquals(ReversiStore.StateApplyOutcome.applied, r.store.applyState(stateText(narrowed)))
        assertEquals(setOf(19, 26, 37, 44), ReversiRules.legalMoves(ReversiBoard.start, ReversiColor.black).toSet(), "규칙은 넷")
        assertEquals(setOf(19), r.store.legalTargets, "화면은 서버 하나")
        r.store.place(26)
        assertEquals(0, r.server.count("reversi_move"))
        assertEquals(ReversiNoticeText.outOfRange, r.store.notice)
        assertEquals(0, r.store.match?.moveCount)

        // 기준선: 원문(넷)이면 같은 칸이 서버로 나간다.
        val wide = rig(viewerB, bodies = mapOf("reversi_move" to listOf(json("reversi_move__ok"))))
        wide.store.applyState(state("reversi_state__my_turn"))
        assertEquals(4, wide.store.legalTargets.size)
        wide.store.place(26)
        assertEquals(1, wide.server.count("reversi_move"))
    }

    @Test
    fun legalTargetsOnlyOnMyTurnAndWatchShapeIsIgnored() = runTest {
        // 없으면: 상대 차례 응답에 목록이 섞여 와도(서버 결함·관전 모양) 점이 그려지고 착수가 나가도 초록이다.
        val leaked = mutatedState("reversi_state__their_turn") { it["legal_moves"] = JsonArray(listOf(JsonPrimitive(19), JsonPrimitive(26))) }
        val r = rig(viewerA)
        r.store.applyState(stateText(leaked))
        assertEquals(false, r.store.match?.isMyTurn)
        assertEquals(emptyList<Int>(), r.store.match?.legalMoves)
        assertTrue(r.store.legalTargets.isEmpty())
        val mine = rig(viewerB)
        mine.store.applyState(state("reversi_state__my_turn"))
        assertEquals(4, mine.store.legalTargets.size)
        // 관전 모양(내 색 없음)은 대국으로 옮기지 않는다.
        assertEquals(ReversiStore.StateApplyOutcome.ignored, mine.store.applyState(state("reversi_watch_live__ok")))
    }

    // MARK: ④ 늦은 응답 가드

    @Test
    fun lateSnapshotWithSmallerMoveCountIsIgnored() = runTest {
        // 없으면: 착수보다 먼저 읽힌 옛 스냅숏이 늦게 와서 방금 둔 돌이 사라지고 차례가 되돌아가도 초록이다.
        val r = rig(viewerB)
        assertEquals(ReversiStore.StateApplyOutcome.applied, r.store.applyState(state("reversi_move__ok")))
        assertEquals(1, r.store.match?.moveCount)
        assertEquals(ReversiStore.StateApplyOutcome.ignored, r.store.applyState(state("reversi_state__my_turn"), requestedSince = 0))
        assertEquals(1, r.store.match?.moveCount)
        assertEquals(ReversiColor.black, r.store.match?.board?.get(19))
        // 기준선: 같은 수 번호(1)는 받는다.
        assertEquals(ReversiStore.StateApplyOutcome.applied, r.store.applyState(state("reversi_move__ok"), requestedSince = 1))
    }

    @Test
    fun progressResponseAfterFinishIsIgnored() = runTest {
        // 없으면: 끝나기 전에 나간 조회가 늦게 와서 결과 화면이 대국 화면으로 되돌아가도 초록이다.
        assertEquals(viewerA, viewer("reversi_state__finished"))
        val r = rig(viewerA)
        r.store.applyState(state("reversi_state__finished"))
        assertEquals(ReversiPhase.result, r.store.phase)
        assertEquals(ReversiMatchOutcome.lost, r.store.match?.outcome, "A 는 백, 흑 승")
        assertEquals(ReversiStore.StateApplyOutcome.ignored, r.store.applyState(state("reversi_state__their_turn")))
        assertEquals(ReversiPhase.result, r.store.phase)
        assertEquals(true, r.store.match?.isFinished)
    }

    @Test
    fun lobbyThatPredatesWriteDoesNotRestoreRuby() = runTest {
        // 없으면: 수락보다 먼저 나간 무거운 로비 응답이 늦게 와서 판돈이 빠진 95 가 100 으로 돌아가도 초록이다(writeRevision).
        val r = rig(
            viewerB,
            bodies = mapOf(
                "reversi_lobby" to listOf(StubReply.Delayed(1.0, json("reversi_lobby__incoming"))),
                "reversi_respond" to listOf(json("reversi_respond__accepted")),
            ),
        )
        val store = r.store
        store.applyLobby(decodeFixture(REVERSI_FIXTURES, "reversi_lobby__incoming", ReversiLobbyResponse.serializer()))
        val lobby = launch { store.refreshLobby() } // 로비가 먼저 나가 1초 걸린다
        runCurrent()
        store.respond(mainMatch, accept = true) // 그 사이 수락(쓰기)이 먼저 돌아온다
        assertEquals(95L, store.rubyBalance)
        advanceTimeBy(1_100)
        runCurrent()
        lobby.join()
        assertEquals(95L, store.rubyBalance, "쓰기보다 먼저 나간 로비가 잔액을 되돌렸다")
        assertTrue(store.incoming.none { it.id == mainMatch }, "답한 신청이 옛 로비로 되살아났다")
        assertEquals(mainMatch, store.match?.id)
    }

    // MARK: ⑤ 계정 경계

    @Test
    fun resetDropsLateResponsesAndClearsAccountState() = runTest {
        // 없으면: 로그아웃 직전에 나간 로비가 다음 사람의 화면에 앞 사람의 신청·루비를 세워도 초록이다.
        val r = rig(viewerB, bodies = mapOf("reversi_lobby" to listOf(StubReply.Delayed(1.0, json("reversi_lobby__incoming")))))
        val store = r.store
        store.applyState(state("reversi_state__my_turn"))
        store.hiddenPeerIDs = setOf("x")
        store.rankingEnabled = true
        store.spectatorFeaturesEnabled = true
        val lobby = launch { store.refreshLobby() }
        runCurrent()
        store.reset()
        advanceTimeBy(1_100)
        runCurrent()
        lobby.join()
        assertNull(store.match)
        assertTrue(store.incoming.isEmpty(), "늦은 로비가 앞 계정의 신청을 세웠다")
        assertNull(store.rubyBalance)
        assertNull(store.record)
        assertEquals(ReversiPhase.lobby, store.phase)
        assertTrue(store.hiddenPeerIDs.isEmpty())
        assertNull(store.activeMatchID)
        // 배선 값은 그대로다(조립이 다시 켜지 않는다).
        assertTrue(store.rankingEnabled)
        assertTrue(store.spectatorFeaturesEnabled)
        // 기준선: reset 없이 같은 응답이 오면 신청이 선다.
        val base = rig(viewerB, bodies = mapOf("reversi_lobby" to listOf(json("reversi_lobby__incoming"))))
        base.store.refreshLobby()
        assertEquals(1, base.store.incoming.size)
    }

    @Test
    fun sessionGenerationBumpDropsInFlightResponse() = runTest {
        // 없으면: 토큰 만료로 세션이 갈린 뒤 도착한 응답이 새 세션의 화면을 덮어도 초록이다.
        val r = rig(viewerB, bodies = mapOf("reversi_respond" to listOf(StubReply.Delayed(1.0, json("reversi_respond__accepted")))))
        val job = launch { r.store.respond(mainMatch, accept = true) }
        runCurrent()
        r.host.sessionGeneration += 1
        advanceTimeBy(1_100)
        runCurrent()
        job.join()
        assertNull(r.store.match)
        assertNull(r.store.rubyBalance)
    }

    // MARK: ⑥ 서버 판돈 정산 · 능력 협상 원문 처리

    @Test
    fun targetOutdatedIsSaidAndLobbyReread() = runTest {
        // 없으면: 서버 `reversi_android_min_build` 가 닫혀 있는 동안 상대가 옛 앱이라 거절돼도 화면이 엉뚱한 말을 하거나 칩을 안 고쳐도 초록이다.
        val r = rig(
            viewer("reversi_challenge__target_outdated"),
            bodies = mapOf(
                "reversi_challenge" to listOf(json("reversi_challenge__target_outdated")),
                "reversi_lobby" to listOf(json("reversi_lobby__ok")),
            ),
        )
        r.store.challenge(viewerB)
        assertEquals("상대 앱이 아잉 뒤집기를 아직 몰라요", r.store.notice)
        assertNull(r.store.outgoing)
        assertEquals(1, r.server.count("reversi_lobby"), "목록의 칩을 사실에 맞추려 로비를 다시 읽는다")
        assertFalse(r.store.isBusy)
    }

    @Test
    fun lobbyCapableNullIsNotCapable() {
        // 없으면: 서버가 능력을 안 실은 상대(옛 앱 · 닫힌 min_build)에게 [도전] 이 열려 `target_outdated` 만 받아도 초록이다.
        assertEquals(false, ReversiStore.user(com.yehsung.aingcheck.core.wire.games.ReversiLobbyUserRow(id = "AB", displayName = "x"))?.isCapable)
        assertEquals(true, ReversiStore.user(com.yehsung.aingcheck.core.wire.games.ReversiLobbyUserRow(id = "AB", capable = true))?.isCapable)
        assertEquals("ab", ReversiStore.user(com.yehsung.aingcheck.core.wire.games.ReversiLobbyUserRow(id = "AB"))?.id)
    }

    @Test
    fun drawRefundAndLossAreServerBalances() = runTest {
        // 없으면: 무승부 환불·패배 차감을 클라가 계산해 서버 값과 갈려도 초록이다(서버 판정만 따른다).
        for (name in listOf("reversi_move__finished_draw", "reversi_move__finished_wipeout", "reversi_move__finished_no_moves")) {
            val json = fixtureJSON(REVERSI_FIXTURES, name)
            val r = rig(viewer(name))
            r.store.applyState(state(name))
            assertEquals(json.obj("state")!!.long("ruby_balance"), r.store.rubyBalance, name)
            assertEquals(json.obj("state")!!.long("ruby_balance"), r.host.rubyBalance, "$name 호스트 미러")
            assertEquals(ReversiPhase.result, r.store.phase, name)
        }
        val draw = rig(viewer("reversi_move__finished_draw"))
        draw.store.applyState(state("reversi_move__finished_draw"))
        assertEquals(ReversiMatchOutcome.draw, draw.store.match?.outcome)
        assertNull(draw.store.match?.winner)
    }

    // MARK: ⑦ 서버 픽스처 51장 — 상태 전이 · 오류 문구

    @Test
    fun everyFixtureDrivesTheStoreThroughItsRpc() = runTest {
        // 없으면: 어느 status 하나가 엉뚱한 문구를 내거나(진단 어휘) · 상태 전이를 빠뜨려도(신청 카드가 남음 · 판이 안 섬) 그 원문만 초록이 아니다 —
        // 51장 전부를 실제 RPC 문으로 먹인다.
        val files = manifest["files"]!!.objects()
        assertEquals(51, files.size, "픽스처가 51장이 아니다 — 서버 갈래가 다시 뽑았으면 이 표를 맞춘다")
        var driven = 0
        for (entry in files) {
            val name = entry.str("file")!!.removeSuffix(".json")
            val rpc = entry.str("rpc")!!
            val status = ReversiRPCStatus.entries.first { it.rawValue == entry.str("status") }
            val me = entry.str("viewer") ?: viewerA
            val json = fixtureJSON(REVERSI_FIXTURES, name)
            val response = if (rpc == "reversi_lobby" || rpc == "reversi_ranking") null else decodeFixture(REVERSI_FIXTURES, name, ReversiActionResponse.serializer())
            val r = rig(me, bodies = mapOf(rpc to listOf(json(name))))
            val store = r.store
            when (rpc) {
                "reversi_lobby" -> {
                    store.refreshLobby()
                    when (status) {
                        ReversiRPCStatus.ok -> {
                            assertEquals(ReversiAvailability.available, store.availability, name)
                            assertTrue(store.hasLoadedLobby, name)
                            assertEquals(json.obj("me")?.long("ruby_balance"), store.rubyBalance, name)
                        }
                        ReversiRPCStatus.unauthorized -> assertEquals(ReversiNoticeText.signInAgain, store.notice, name)
                        ReversiRPCStatus.unsupportedClient -> {
                            assertEquals(ReversiAvailability.updateRequired, store.availability, name)
                            assertEquals(ReversiNoticeText.updateRequired, store.notice, name)
                        }
                        else -> error("$name: 모르는 로비 status")
                    }
                }
                "reversi_challenge" -> {
                    store.challenge(viewerB)
                    assertEquals(ReversiNoticeText.challenge(status, response!!.need, response.have), store.notice, name)
                    assertEquals(status == ReversiRPCStatus.ok, store.outgoing != null, "$name 보낸 신청")
                    assertFalse(store.isBusy, name)
                }
                "reversi_cancel" -> {
                    store.outgoing = ReversiOutgoing(mainMatch, ReversiUser(viewerB, ""), 5, contractClock.addingTimeInterval(50.0))
                    store.cancelChallenge()
                    assertEquals(ReversiNoticeText.cancel(status), store.notice, name)
                    assertNull(store.outgoing, "$name 보낸 신청이 남았다")
                    if (status == ReversiRPCStatus.notPending && response?.state?.match?.status == "active") {
                        assertEquals(ReversiPhase.playing, store.phase, "$name: 취소보다 수락이 먼저 닿았다 — 판이 선다")
                    }
                }
                "reversi_respond" -> {
                    val accept = !name.endsWith("declined")
                    store.incoming = listOf(ReversiInvite(mainMatch, ReversiUser(viewerA, ""), 5, contractClock.addingTimeInterval(50.0)))
                    store.respond(mainMatch, accept)
                    assertEquals(ReversiNoticeText.respond(accept, status, response!!.side, response.need, response.have), store.notice, name)
                    val alive = status == ReversiRPCStatus.busy || status == ReversiRPCStatus.targetBusy || status == ReversiRPCStatus.insufficient
                    assertEquals(alive, store.incoming.isNotEmpty(), "$name 받은 신청 카드(살아 있는 신청만 남는다)")
                    if (status == ReversiRPCStatus.ok && accept) assertEquals(ReversiPhase.playing, store.phase, name)
                }
                "reversi_move", "reversi_resign" -> {
                    val payload = response!!.state
                    val myColor = payload?.myColor ?: ReversiColor.black
                    val serverCount = payload?.match?.moveCount?.toInt() ?: 1
                    store.match = ReversiMatchState(
                        id = payload?.match?.id ?: mainMatch, stake = 5, myColor = myColor, opponent = ReversiUser(viewerA, ""),
                        moveCount = maxOf(0, serverCount - 1), turn = myColor, legalMoves = listOf(19),
                    )
                    store.phase = ReversiPhase.playing
                    if (rpc == "reversi_move") {
                        store.place(19)
                        // 새로 온 기록에 패스가 있으면 상태줄은 패스를 말한다(착수 문구가 null 인 성공 뒤 — 판 화면은 패스를 그리지 않는다).
                        val passed = payload?.moves?.any { it.kind == com.yehsung.aingcheck.core.wire.games.ReversiPly.Kind.pass } == true
                        val expected = ReversiNoticeText.move(status, response.illegalReason)
                        val passLines = setOf(ReversiNoticeText.myPass, payload?.opponent?.displayName?.let(ReversiNoticeText::opponentPassed))
                        assertTrue(store.notice == expected || (passed && expected == null && store.notice in passLines), "$name 문구: ${store.notice}")
                    } else {
                        store.resign()
                        assertEquals(ReversiNoticeText.resign(status), store.notice, name)
                    }
                    if (payload != null && payload.match?.status == "finished") {
                        assertEquals(ReversiPhase.result, store.phase, "$name 결과 화면")
                        assertEquals(payload.rubyBalance, store.rubyBalance, "$name 정산은 서버 값")
                    } else if (payload != null) {
                        assertEquals(serverCount, store.match?.moveCount, "$name 실려 온 state 로 맞춘다")
                    }
                    assertFalse(store.isBusy, name)
                }
                "reversi_state" -> {
                    store.refreshMatch(mainMatch)
                    when {
                        status == ReversiRPCStatus.notFound -> assertNull(store.match, name)
                        response!!.state?.match?.status == "pending" -> assertEquals(json.obj("state")!!.obj("match")!!.str("id"), store.outgoing?.id ?: store.incoming.firstOrNull()?.id, name)
                        else -> assertEquals(response.state?.match?.moveCount?.toInt(), store.match?.moveCount, name)
                    }
                }
                "reversi_ranking" -> {
                    store.rankingEnabled = true
                    store.refreshRanking()
                    val rows = json["rows"]!!.objects()
                    assertEquals<List<String?>?>(rows.map { it.str("user_id") }, store.ranking?.entries?.map { it.id }, "$name 서버 순서 그대로")
                    assertTrue(store.hasLoadedRanking)
                }
                "reversi_watch", "reversi_watch_live" -> {
                    // watch_live 가 없는 서버를 흉내 낼 때만 watch 로 접는다 — 여기서는 각 rpc 를 그 이름 그대로 부른다.
                    if (rpc == "reversi_watch") store.spectatorCountUnavailable = true
                    store.spectatorFeaturesEnabled = true
                    store.isWindowVisible = true
                    store.startWatching(response!!.state?.match?.id ?: mainMatch)
                    runCurrent()
                    if (status == ReversiRPCStatus.notFound) {
                        assertNull(store.spectating, name)
                        assertEquals(ReversiNoticeText.watchGone, store.notice, name)
                    } else {
                        val watched = assertNotNull(store.spectating, name)
                        assertEquals(response.state?.match?.board, watched.board, name)
                        assertEquals(maxOf(0L, response.state?.watchers ?: 0L).toInt(), store.spectatorCount, name)
                    }
                }
                else -> error("$name: 모르는 rpc")
            }
            // 진단 어휘는 사용자 문구에 없다.
            val notice = store.notice
            if (notice != null) for (word in listOf("서버", "동기화", "프로토콜", "status")) assertFalse(word in notice, "$name 문구에 진단 어휘: $notice")
            driven += 1
        }
        assertEquals(51, driven)
    }

    // MARK: ⑧ 판돈 대결 깃발(§8-17 #1)

    @Test
    fun duelsLockedBuildSendsNoChallengeOrAcceptButStillPlaysAI() = runTest {
        // 없으면: 판돈 깃발이 꺼진 Android 빌드가 리버시 신청·수락을 그대로 내 판돈이 걸려도 초록이다(오목·체스는 막는데 리버시만 샌다).
        val locked = rig(viewerB, appConfig = AppConfig(duelsEnabled = false), bodies = mapOf("reversi_lobby" to listOf(json("reversi_lobby__incoming"))))
        val arrived = mutableListOf<String>()
        locked.store.onInviteArrived = { arrived += it.id }
        locked.store.refreshLobby()
        assertEquals(1, locked.store.incoming.size, "서버 사실은 그대로 든다")
        assertTrue(locked.store.visibleIncomingInvites.isEmpty(), "잠긴 빌드는 받은 신청을 보이지 않는다")
        assertEquals(ReversiNoticeText.updateMine, locked.store.incomingFoldedNotice)
        assertTrue(arrived.isEmpty())
        locked.store.challenge(viewerA)
        locked.store.respond(mainMatch, accept = true)
        assertEquals(0, locked.server.count("reversi_challenge"))
        assertEquals(0, locked.server.count("reversi_respond"))
        assertEquals(ReversiNoticeText.updateMine, locked.store.notice)
        // AI 연습은 깃발과 무관하다.
        locked.store.startAIMatch(ReversiColor.black)
        assertEquals(true, locked.store.match?.isAI)
        // 기준선: 켜진 빌드는 같은 로비에서 신청이 보이고 배너 문이 운다.
        val open = rig(viewerB, bodies = mapOf("reversi_lobby" to listOf(json("reversi_lobby__incoming"))))
        val opened = mutableListOf<String>()
        open.store.onInviteArrived = { opened += it.id }
        open.store.refreshLobby()
        assertEquals(1, open.store.visibleIncomingInvites.size)
        assertNull(open.store.incomingFoldedNotice)
        assertEquals(listOf(mainMatch), opened)
    }

    // MARK: ⑨ 관전 · 순위 스위치

    @Test
    fun spectatorAndRankingSwitchesGateRequests() = runTest {
        // 없으면: 조립이 주 스위치를 안 켜도(기본 false) 순위·관전이 나가거나, 켜도 안 나가도 초록이다 — 둘은 **따로**다.
        val r = rig(viewerA, bodies = mapOf("reversi_ranking" to listOf(json("reversi_ranking__ok")), "reversi_watch_live" to listOf(json("reversi_watch_live__ok"))))
        r.store.isWindowVisible = true
        r.store.pollSpectatorFeatures(contractClock.addingTimeInterval(100.0))
        r.store.startWatching(mainMatch)
        runCurrent()
        assertEquals(0, r.server.count("reversi_ranking"))
        assertEquals(0, r.server.count("reversi_watch_live"))
        assertNull(r.store.spectating)
        r.store.rankingEnabled = true
        r.store.pollSpectatorFeatures(contractClock.addingTimeInterval(200.0))
        assertEquals(1, r.server.count("reversi_ranking"))
        assertEquals(0, r.server.count("reversi_watch_live"), "순위 스위치가 관전을 열지 않는다")
        r.store.spectatorFeaturesEnabled = true
        r.store.startWatching(mainMatch)
        runCurrent()
        assertEquals(1, r.server.count("reversi_watch_live"))
        assertNotNull(r.store.spectating)
    }

    @Test
    fun watchLiveMissingFoldsToWatchWithoutLockingEntrance() = runTest {
        // 없으면: watch_live 가 없는 서버(배포 중간 창)에서 관전 입구가 통째로 잠겨도 초록이다 — 잃는 것은 숫자 한 칸뿐이어야 한다.
        val r = rig(
            viewerA,
            bodies = mapOf(
                "reversi_watch_live" to listOf(StubReply.missingFunction("reversi_watch_live")),
                "reversi_watch" to listOf(json("reversi_watch__ok")),
            ),
        )
        r.store.spectatorFeaturesEnabled = true
        r.store.isWindowVisible = true
        r.store.startWatching(mainMatch)
        runCurrent()
        assertTrue(r.store.spectatorCountUnavailable)
        assertFalse(r.store.watchUnavailable)
        assertNotNull(r.store.spectating)
        assertEquals(1, r.server.count("reversi_watch"))
    }

    // MARK: ⑩ 서버에 함수가 없다(PGRST202)

    @Test
    fun missingServerFunctionsSayComingSoon() = runTest {
        // 없으면: 앱이 db push 보다 먼저 나간 창에서 로비가 오류 문구를 내거나 [도전] 이 열린 채 남아도 초록이다.
        val r = rig(viewerA, bodies = mapOf("reversi_lobby" to listOf(StubReply.missingFunction("reversi_lobby"))))
        r.store.refreshLobby()
        assertEquals(ReversiAvailability.serverMissing, r.store.availability)
        assertEquals(ReversiNoticeText.unavailable, r.store.notice)
        assertEquals(ReversiNoticeText.unavailable, GamesReversiUnavailable.title(r.store.availability))
    }

    // MARK: ⑪ 받은 신청 만료 · 신호 합치기

    @Test
    fun signalsCoalesceIntoOneTrailingLobbyRead() = runTest {
        // 없으면: 초인종이 몰려 올 때마다 로비가 겹쳐 나가거나(무거운 조회 폭주) · 도는 중에 온 신호를 버려 신청이 다음 계기까지 안 서도 초록이다.
        val r = rig(viewerB, bodies = mapOf("reversi_lobby" to listOf(StubReply.Delayed(0.5, json("reversi_lobby__ok")), json("reversi_lobby__incoming"))))
        r.store.handleSignal()
        runCurrent()
        r.store.handleSignal()
        r.store.handleSignal()
        advanceTimeBy(600)
        runCurrent()
        assertEquals(2, r.server.count("reversi_lobby"), "도는 중에 온 신호 둘은 뒤따르는 한 번으로 합친다")
        assertEquals(1, r.store.incoming.size, "뒤따르는 한 번이 그 사이 온 신청을 세운다")
    }

    @Test
    fun incomingInviteExpiresByStoreTimer() = runTest {
        // 없으면: 만료된 신청이 다음 무관한 갱신까지 배지·칩에 남아도 초록이다(계산 칸이 시계를 읽지 않는다).
        val r = rig(viewerB)
        val store = r.store
        var now = contractClock
        store.clock = { now }
        store.incoming = listOf(ReversiInvite(mainMatch, ReversiUser(viewerA, ""), 5, contractClock.addingTimeInterval(10.0)))
        store.scheduleInviteExpiry()
        now = contractClock.addingTimeInterval(11.0)
        advanceTimeBy(10_400)
        runCurrent()
        assertTrue(store.incoming.isEmpty())
    }
}
