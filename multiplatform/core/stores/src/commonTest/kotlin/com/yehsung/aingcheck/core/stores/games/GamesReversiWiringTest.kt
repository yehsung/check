// 원본: Tests/CheckMobileKitTests/GamesReversiWiringTests.swift(게임 탭 몫 — 다섯 방향 입구 · 배지 · 화면 수명 · 화면 꺼짐 · 판 시작 문 · 카드 서열) @ ios-1017-int 91ea495d
package com.yehsung.aingcheck.core.stores.games

import com.yehsung.aingcheck.core.rules.reversi.ReversiRules
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiCard
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiChallengeGate
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiStakeSend
import com.yehsung.aingcheck.core.stores.reversi.ReversiPhase
import com.yehsung.aingcheck.core.stores.reversi.ReversiPhoneText
import com.yehsung.aingcheck.core.stores.reversi.ReversiStake
import com.yehsung.aingcheck.core.stores.reversi.ReversiStore
import com.yehsung.aingcheck.core.stores.reversi.ReversiUser
import com.yehsung.aingcheck.core.stores.reversi.startAIMatch
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.applyState
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStoreTest
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiLobbyResponse
import com.yehsung.aingcheck.core.wire.games.ReversiStatePayload
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.games.TetrisStatePayload
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 게임 탭 스토어의 아잉 뒤집기 배선(판 7 — 폰 몫: **다섯 방향** 입구 · 배지 · 화면 수명 · 화면 꺼짐 · 판 시작 문 · 카드 서열). 각 시험은 결과가 갈리는
 * 기준선(리버시 스토어가 없는 문맥 · 판 없음)을 같은 시험 안에 둔다. 리버시 상태는 서버 응답 모양 그대로 손으로 짠 본문을 코어 문(`applyState`·`applyLobby`)으로 넣는다.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class GamesReversiWiringTest {
    private companion object {
        const val MATCH = "5e5e0000-0000-4000-8000-000000000071"
        const val RUMMY_MATCH = "7e7e0000-0000-4000-8000-000000000068"
        const val NOW_MS = 1_800_000_000_000L
        val WALL = SwiftDate(1_800_000_000.0)
        val lenient = Json { ignoreUnknownKeys = true }
    }

    private class Rig(val h: StoreHarness, val games: GamesStore, val reversi: ReversiStore)

    /** 서버 `reversi_state` 묶음(참가자 모양). 나는 [StoreFixtures.USER], 상대는 [StoreFixtures.PEER]. */
    private fun state(status: String = "active", myColor: String = "black", turn: String? = "black", moveCount: Int = 0): ReversiStatePayload {
        val finished = status == "finished"
        val black = if (myColor == "black") StoreFixtures.USER else StoreFixtures.PEER
        val white = if (myColor == "black") StoreFixtures.PEER else StoreFixtures.USER
        val legal = if (!finished && turn == myColor) "[19,26,37,44]" else "[]"
        return SwiftJson.decode(
            ReversiStatePayload.serializer(),
            """{"match":{"id":"$MATCH","status":"$status","stake":5,"challenger":"${StoreFixtures.PEER}","opponent":"${StoreFixtures.USER}",""" +
                """"black":"$black","white":"$white","move_count":$moveCount,"turn":${if (finished || turn == null) "null" else "\"$turn\""},""" +
                """"turn_started_ms":$NOW_MS,"deadline_ms":${NOW_MS + 30_000},"board":"${ReversiBoard.start.string}",""" +
                """"result":${if (finished) "\"black_win\"" else "null"},"end_reason":${if (finished) "\"resign\"" else "null"}},""" +
                """"moves":[],"my_color":"$myColor","legal_moves":$legal,"opponent":{"user_id":"${StoreFixtures.PEER}","display_name":"비"},"server_now_ms":$NOW_MS}""",
        )
    }

    private fun lobby(active: String? = null, incoming: Int = 0, outgoing: Boolean = false, fromPeer: String = StoreFixtures.PEER): ReversiLobbyResponse =
        SwiftJson.decode(
            ReversiLobbyResponse.serializer(),
            """{"status":"ok","server_now_ms":$NOW_MS,"stakes":[3,5,10],"turn_seconds":30,"invite_ttl_seconds":60,""" +
                """"me":{"ruby_balance":10,"wins":1,"losses":0,"draws":0,"active_match_id":${active?.let { "\"$it\"" } ?: "null"},""" +
                """"incoming":[${(0 until incoming).joinToString(",") { """{"match_id":"5e5e0000-0000-4000-8000-00000000009$it","from":{"id":"$fromPeer","display_name":"비"},"stake":5,"expires_at_ms":${NOW_MS + 60_000}}""" }}],""" +
                """"outgoing":${if (outgoing) """{"match_id":"5e5e0000-0000-4000-8000-000000000080","to":{"id":"${StoreFixtures.PEER}","display_name":"비"},"stake":3,"expires_at_ms":${NOW_MS + 60_000}}""" else "null"}},""" +
                """"users":[{"id":"${StoreFixtures.PEER}","display_name":"비","capable":true,"is_working":true}],"matches":[]}""",
        )

    private val reversiLobbyText =
        """{"status":"ok","server_now_ms":$NOW_MS,"stakes":[3,5,10],"me":{"ruby_balance":10,"wins":0,"losses":0,"draws":0,"active_match_id":null,"incoming":[],"outgoing":null},"users":[],"matches":[]}"""

    private fun rummyState(): RummyMatchState = SwiftJson.decode(
        RummyMatchState.serializer(),
        """{"id":"$RUMMY_MATCH","status":"active","host_id":"${StoreFixtures.USER}","seq":1,"server_now_ms":$NOW_MS,""" +
            """"seats":[{"seat_no":0,"user_id":"${StoreFixtures.USER}","state":"playing"},{"seat_no":1,"user_id":"${StoreFixtures.PEER}","state":"playing"}],"my_seat_no":0,""" +
            """"my_rack":["A1","B2"],"table":[],"turn_seat_no":0,"turn_started_ms":$NOW_MS,"turn_deadline_ms":${NOW_MS + 60_000},"grace_ms":2000}""",
    )

    private suspend fun TestScope.rig(duels: Boolean = true, withReversi: Boolean = true, withRummy: Boolean = false): Rig {
        val config = AppConfig(duelsEnabled = duels)
        val h = StoreHarness(this, config) { r ->
            when (r.rpcName) {
                "reversi_lobby" -> Reply.Json(reversiLobbyText)
                "reversi_state" -> Reply.Offline
                "rummy_lobby" -> Reply.Json("""{"status":"ok","server_now_ms":$NOW_MS,"stakes":[3,5,10],"me":{"ruby_balance":10},"invites":[],"public_rooms":[],"users":[]}""")
                "rummy_state" -> Reply.Offline
                "tetris_lobby" -> TetrisDuelStoreTest.lobby(incoming = false)
                else -> null
            }
        }
        h.signIn()
        // 시계는 시험 스케줄러와 함께 흐르는 조립 시계다 — 고정 시계면 받은 신청 만료 타이머가 걷지 못한 채 같은 자리에서 끝없이 다시 걸려, 다음 조립의
        // 로그인(advanceUntilIdle)이 돌아오지 않는다(측정).
        val reversi = ReversiStore(h.storeScope, TestRummyHost(h.sessionStore, config) { h.clock.now() }).also {
            it.clock = { h.clock.now() }
            it.pollStepSeconds = Double.POSITIVE_INFINITY
            it.aiRuntime.minimumThinkSeconds = 0.0
            // 엔진 대신 결정적 가짜(첫 합법 수) — 시험이 실제 탐색 스레드를 띄우지 않게.
            it.aiRuntime.chooser = { board, color -> ReversiRules.legalMoves(board, color).firstOrNull() }
        }
        if (withReversi) h.reversiStore = reversi
        if (withRummy) {
            h.rummyStore = RummyStore(h.storeScope, TestRummyHost(h.sessionStore, config) { WALL }).also {
                it.clock = { WALL }
                it.pollStepSeconds = Double.POSITIVE_INFINITY
                it.deadlineWakeEnabled = false
                it.heartbeatEnabled = false
            }
        }
        return Rig(h, GamesStore(h.context), reversi)
    }

    private data class Blocks(
        val chess: GamesBusyGame?,
        val gomoku: GamesBusyGame?,
        val tetris: GamesBusyGame?,
        val rummy: GamesBusyGame?,
        val reversi: GamesBusyGame?,
    )

    private fun GamesStore.blocks() = Blocks(chessEntryBlock, gomokuEntryBlock, tetrisEntryBlock, rummyEntryBlock, reversiEntryBlock)

    /** ★ 한 사람 한 판은 **다섯 방향**이다. 리버시 1:1 판(서버 id 만 알아도)이 흐르면 넷이 막히고 자기 입구는 열린다. AI 연습 · 끝난 판은 막지 않는다. */
    @Test
    fun oneMatchAtATimeBlocksFiveWays() = runTest {
        val v = GamesBusyGame.reversi
        val g = GamesBusyGame.gomoku
        val c = GamesBusyGame.chess
        val t = GamesBusyGame.tetris
        val r = GamesBusyGame.rummy
        val table: List<Triple<String, suspend (Rig) -> Unit, Blocks>> = listOf(
            Triple("판 없음", { _ -> }, Blocks(null, null, null, null, null)),
            Triple("리버시 1:1 판", { x -> x.reversi.applyState(state()) }, Blocks(v, v, v, v, null)),
            Triple("리버시 서버 id 만(판을 못 읽었다)", { x -> x.reversi.applyLobby(lobby(active = MATCH)) }, Blocks(v, v, v, v, null)),
            Triple("리버시 끝난 판", { x -> x.reversi.applyState(state("finished")) }, Blocks(null, null, null, null, null)),
            Triple("리버시 AI 연습", { x -> x.reversi.startAIMatch(ReversiColor.black) }, Blocks(null, null, null, null, null)),
            Triple("오목 사람 판", { x -> x.h.gomoku.holdMatch() }, Blocks(g, null, g, g, g)),
            Triple("체스 사람 판", { x -> x.h.chess.holdMatch() }, Blocks(null, c, c, c, c)),
            Triple("테트리스 판", { x ->
                x.h.tetris.applyState(lenient.decodeFromString(TetrisStatePayload.serializer(), TetrisDuelStoreTest.activeState()), 0.0)
            }, Blocks(t, t, null, t, t)),
            Triple("큐브 판", { x -> x.h.rummyStore!!.applyState(rummyState()) }, Blocks(r, r, r, null, r)),
            Triple("오목 + 리버시", { x -> x.h.gomoku.holdMatch(); x.reversi.applyState(state()) }, Blocks(g, v, g, g, g)),
        )
        for ((label, arrange, expected) in table) {
            val x = rig(withRummy = true)
            arrange(x)
            assertEquals(expected, x.games.blocks(), label)
        }
        // 막힌 입구 문구(두는 판의 이름과 언제 풀리는지) — iOS 1.0.17 과 같은 글자.
        assertEquals("아잉 뒤집기를 두는 중이에요", GamesBusyText.busyTitle(v))
        assertEquals("아잉 뒤집기 판이 끝나면 체스를 신청할 수 있어요", GamesBusyText.busyHint(v, c))
        assertEquals("오목 판이 끝나면 아잉 뒤집기를 신청할 수 있어요", GamesBusyText.busyHint(g, v))
    }

    /** 리버시 스토어가 없는 문맥(Windows · 떼어 내기 깃발 끔)은 리버시를 모른다 — 입구·배지·화면 꺼짐·카드·허브 요청이 판 7 이전과 같다. */
    @Test
    fun aContextWithoutReversiBehavesAsBefore() = runTest {
        val x = rig(withReversi = false)
        val games = x.games
        assertNull(games.reversi)
        // 리버시 스토어가 같은 판을 들고 있어도(문맥 밖) 게임 탭은 모른다.
        x.reversi.applyState(state())
        assertEquals(Blocks(null, null, null, null, null), games.blocks())
        assertFalse(games.hasLiveReversiMatch)
        assertEquals(0, games.badgeCount)
        assertEquals(GamesReversiCard.Line.idle, GamesReversiCard.line(games))
        games.appDidBecomeActive()
        games.hubDidAppear()
        runCurrent()
        assertTrue(x.h.gameRpcs().none { it.startsWith("reversi_") }, "스토어가 없는 문맥에서 리버시 요청이 나갔다: ${x.h.gameRpcs()}")
        games.reversiScreenDidAppear()
        assertFalse(games.isReversiScreenVisible, "스토어가 없으면 화면 수명도 서지 않는다")
        assertFalse(games.wantsIdleTimerDisabled)
        // 기준선: 스토어가 있으면 같은 판이 넷을 막는다.
        val base = rig()
        base.reversi.applyState(state())
        assertEquals(GamesBusyGame.reversi, base.games.gomokuEntryBlock)
    }

    @Test
    fun badgeAddsVisibleReversiInvites() = runTest {
        val open = rig()
        open.h.gomoku.pendingIncomingInviteCount = 1
        open.reversi.applyLobby(lobby(incoming = 2))
        assertEquals(3, open.games.badgeCount)
        assertEquals(ReversiPhoneText.incomingChip(2), GamesReversiCard.chip(open.games))
        // 차단 거울: 메시지 탭이 차단한 사람의 신청은 세지 않는다(허브가 거울을 맞춘다).
        open.h.hiddenBlocked = setOf(StoreFixtures.PEER.uppercase())
        open.games.hubDidAppear()
        assertEquals(1, open.games.badgeCount)

        val locked = rig(duels = false)
        locked.reversi.applyLobby(lobby(incoming = 2))
        assertEquals(0, locked.games.badgeCount, "잠긴 빌드는 수락할 수 없는 신청을 안 센다")
    }

    /** 화면 수명: 나타남 = 로비 읽기 + 창(폴링 주 스위치). 사라짐 = 관전 내림 → 숨김 → 끝난 판 접기(요청 0 · 진행 중 판은 그대로). */
    @Test
    fun screenLifecycleOpensWindowAndFoldsOnlyFinishedMatch() = runTest {
        val x = rig()
        val games = x.games
        games.appDidBecomeActive()
        runCurrent()
        val before = x.h.server.rpcs().count { it == "reversi_lobby" }
        games.reversiScreenDidAppear()
        runCurrent()
        assertTrue(games.isReversiScreenVisible)
        assertTrue(x.reversi.isWindowVisible, "windowDidShow 가 창 깃발(폴링·순위·관전·뒤집기 그림·AI 시계의 주 스위치)을 켠다")
        assertEquals(before + 1, x.h.server.rpcs().count { it == "reversi_lobby" }, "화면이 서면 로비를 한 번 읽는다(dedupe 로 한 번)")

        // 진행 중 판은 떠나도 남는다.
        x.reversi.applyState(state())
        val requests = x.h.server.rpcs().size
        games.reversiScreenDidDisappear()
        runCurrent()
        assertFalse(games.isReversiScreenVisible)
        assertFalse(x.reversi.isWindowVisible)
        assertEquals(MATCH, x.reversi.match?.id, "진행 중인 판을 접었다 — 닫기는 기권이 아니다")
        assertEquals(requests, x.h.server.rpcs().size, "떠나는 길에 요청이 나갔다")

        // 끝난 판은 떠나면 접힌다(다시 들어오면 로비).
        games.reversiScreenDidAppear()
        x.reversi.applyState(state("finished"))
        assertEquals(ReversiPhase.result, x.reversi.phase)
        games.reversiScreenDidDisappear()
        assertNull(x.reversi.match)
        assertEquals(ReversiPhase.lobby, x.reversi.phase)
    }

    /** 앱이 뒤로 가면 **가림**(폴링·AI 시계만 멈춘다 — 1:1 판은 서버 시계로 흐른다). 돌아오면 가림을 풀고 따라잡는다. 화면이 안 보이면 30초 스로틀 로비. */
    @Test
    fun backgroundOccludesAndForegroundCatchesUp() = runTest {
        val x = rig()
        val games = x.games
        games.appDidBecomeActive()
        games.reversiScreenDidAppear()
        runCurrent()
        games.appDidEnterBackground()
        assertTrue(x.reversi.isWindowOccluded)
        assertTrue(x.reversi.isWindowVisible, "가림은 창 깃발을 내리지 않는다(결과 화면·관전을 지킨다)")
        val lobbies = x.h.server.rpcs().count { it == "reversi_lobby" }
        games.appDidBecomeActive()
        runCurrent()
        assertFalse(x.reversi.isWindowOccluded)
        assertEquals(lobbies + 1, x.h.server.rpcs().count { it == "reversi_lobby" }, "돌아오면 따라잡기 한 번")
        // 화면이 안 보이면 스로틀 로비(30초 안에 다시 안 나간다).
        games.reversiScreenDidDisappear()
        val after = x.h.server.rpcs().count { it == "reversi_lobby" }
        games.appDidEnterBackground()
        games.appDidBecomeActive()
        runCurrent()
        assertEquals(after, x.h.server.rpcs().count { it == "reversi_lobby" }, "30초 스로틀 안에서 또 읽었다")
    }

    /** 판 시작 문: 코어가 `presentWindow` 를 부르면 게임 탭이 리버시 화면을 연다. 이미 떠 있으면 두 번 쌓지 않는다. 앱이 뒤에 있으면 열지 않는다. */
    @Test
    fun presentWindowOpensReversiScreenOnce() = runTest {
        val x = rig()
        val games = x.games
        x.reversi.presentWindow?.invoke()
        assertEquals(emptyList(), x.h.router.presented, "앱이 active 가 아닌데 열었다")
        games.appDidBecomeActive()
        x.reversi.applyState(state())
        assertEquals(listOf<GamesDestination>(GamesDestination.Reversi), x.h.router.presented)
        games.reversiScreenDidAppear()
        x.reversi.presentWindow?.invoke()
        assertEquals(1, x.h.router.presented.size, "이미 보이는데 또 쌓았다")
    }

    /** 화면 꺼짐: 1:1 판은 어느 화면에 있든 켜고, AI 연습은 화면이 보일 때만 켠다(체스 로봇과 같다). */
    @Test
    fun idleTimerFollowsReversiMatch() = runTest {
        val x = rig()
        val games = x.games
        games.appDidBecomeActive()
        assertFalse(games.wantsIdleTimerDisabled)
        x.reversi.applyState(state())
        assertTrue(games.wantsIdleTimerDisabled, "1:1 판(30초 · 자동 착수 3번이면 패)이 흐르는데 화면이 꺼진다")
        val ai = rig()
        ai.games.appDidBecomeActive()
        ai.reversi.startAIMatch(ReversiColor.black)
        assertFalse(ai.games.wantsIdleTimerDisabled, "화면 밖 AI 연습은 시계가 멈춰 있다 — 배터리만 탄다")
        ai.games.reversiScreenDidAppear()
        assertTrue(ai.games.wantsIdleTimerDisabled)
    }

    /** 확성기·생일 선물 미룸: 리버시 **화면**이 떠 있으면 미룬다(코어 phase 가 아니라 화면으로 — 같은 계정 맥 판으로 폰 배너가 멎지 않게). */
    @Test
    fun matchScreenDefersByScreenNotByPhase() = runTest {
        val x = rig()
        val games = x.games
        games.appDidBecomeActive()
        x.reversi.applyState(state())
        assertEquals(ReversiPhase.playing, x.reversi.phase)
        assertFalse(games.isAnyMatchScreenVisible, "판만 들고 있는데 미뤘다(같은 계정 맥 판에서 폰 배너가 멎는다)")
        games.reversiScreenDidAppear()
        assertTrue(games.isAnyMatchScreenVisible)
    }

    /** 카드 서열: 차단 > 진행 중 판 > 받은 신청 > 보낸 신청 > 전적 > 기본 한 줄. AI 연습 판은 받은 신청을 가리지 않는다. */
    @Test
    fun cardLineOrder() = runTest {
        val idle = rig()
        assertEquals(GamesReversiCard.Line.idle, GamesReversiCard.line(idle.games))
        assertEquals(ReversiPhoneText.idleLine, GamesReversiCard.detail(idle.games))

        val record = rig()
        record.reversi.applyLobby(lobby())
        assertEquals(GamesReversiCard.Line.record, GamesReversiCard.line(record.games))
        assertEquals("내 전적 1승 0패 0무", GamesReversiCard.detail(record.games))

        val outgoing = rig()
        outgoing.reversi.applyLobby(lobby(outgoing = true))
        assertEquals(GamesReversiCard.Line.outgoing, GamesReversiCard.line(outgoing.games))
        assertEquals(ReversiPhoneText.outgoingLine, GamesReversiCard.detail(outgoing.games))

        val incoming = rig()
        incoming.reversi.applyLobby(lobby(incoming = 1, outgoing = true))
        assertEquals(GamesReversiCard.Line.incoming, GamesReversiCard.line(incoming.games))

        val ai = rig()
        ai.reversi.startAIMatch(ReversiColor.white)
        assertEquals(GamesReversiCard.Line.activeMatch, GamesReversiCard.line(ai.games))
        ai.reversi.applyLobby(lobby(incoming = 1))
        assertEquals(GamesReversiCard.Line.incoming, GamesReversiCard.line(ai.games), "AI 연습 판이 사람의 신청을 가렸다")

        val live = rig()
        live.reversi.applyState(state())
        assertEquals(GamesReversiCard.Line.activeMatch, GamesReversiCard.line(live.games))
        assertEquals(GamesText.activeMatchChip, GamesReversiCard.chip(live.games))

        val blocked = rig()
        blocked.h.chess.holdMatch()
        assertEquals(GamesReversiCard.Line.blocked, GamesReversiCard.line(blocked.games))
        assertEquals("체스를 두는 중이에요", GamesReversiCard.chip(blocked.games))
        assertEquals("체스 판이 끝나면 아잉 뒤집기를 신청할 수 있어요", GamesReversiCard.detail(blocked.games))
    }

    /** [도전]·판돈 보내기 마지막 문: 내 판(AI 포함) · 보낸 신청 · 서버가 말한 진행 판 · 다른 게임 판 · 집중 · 능력 없음 · 잠긴 빌드면 닫힌다. */
    @Test
    fun challengeGateAndStakeSend() = runTest {
        val x = rig()
        val peer = ReversiUser(StoreFixtures.PEER, "비", isWorking = true, isCapable = true)
        assertTrue(GamesReversiChallengeGate.isEnabled(peer, x.reversi, null))
        assertEquals(ReversiStake.five, GamesReversiStakeSend.sendable(ReversiStake.five, x.reversi, 10, null))
        assertFalse(GamesReversiChallengeGate.isEnabled(peer.copy(isCapable = false), x.reversi, null), "능력 없는 상대(서버 min_build 닫힘)")
        assertFalse(GamesReversiChallengeGate.isEnabled(peer.copy(focusMode = true), x.reversi, null))
        assertFalse(GamesReversiChallengeGate.isEnabled(peer, x.reversi, GamesBusyGame.chess))
        assertNull(GamesReversiStakeSend.sendable(ReversiStake.ten, x.reversi, 9, null), "모자란 잔액")
        assertEquals(ReversiStake.ten, GamesReversiStakeSend.sendable(ReversiStake.ten, x.reversi, null, null), "잔액을 모르면 막지 않는다")
        x.reversi.startAIMatch(ReversiColor.black)
        assertFalse(GamesReversiChallengeGate.isEnabled(peer, x.reversi, null), "AI 연습 판 중 신청이 열리면 1:1 이 서는 순간 AI 판이 사라진다")
        assertNull(GamesReversiStakeSend.sendable(ReversiStake.five, x.reversi, 10, null))
        val locked = rig(duels = false)
        assertFalse(GamesReversiChallengeGate.isEnabled(peer, locked.reversi, null), "판돈 깃발이 꺼진 빌드")
        assertNull(GamesReversiStakeSend.sendable(ReversiStake.five, locked.reversi, 10, null))
    }

    /** 허브: 리버시 로비를 30초 스로틀로 한 번 당긴다(받은함 RPC 가 없다 — 카드 칩·배지·한 사람 한 판이 이 조회에 달려 있다). */
    @Test
    fun hubPullsReversiLobbyThrottled() = runTest {
        val x = rig()
        x.games.hubDidAppear()
        runCurrent()
        x.games.hubDidAppear()
        runCurrent()
        assertEquals(1, x.h.server.rpcs().count { it == "reversi_lobby" })
    }
}
