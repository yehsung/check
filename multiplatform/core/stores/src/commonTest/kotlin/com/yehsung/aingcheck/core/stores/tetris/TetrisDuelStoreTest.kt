// 원본: Tests/checkTests/V0360TetrisDuelStoreTests.swift · Tests/CheckMobileKitTests/GamesTetrisWatchTests.swift ·
//       GamesTetrisLobbyTests.swift:76-117 @ 1b8260d (판돈 대결 빌드 깃발 시험은 원본 없음 — G §8-17 #1 의 Android 몫)
package com.yehsung.aingcheck.core.stores.tetris

import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.games.Reply
import com.yehsung.aingcheck.core.stores.games.StoreFixtures
import com.yehsung.aingcheck.core.stores.games.StoreHarness
import com.yehsung.aingcheck.core.wire.games.TetrisStatePayload
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class TetrisDuelStoreTest {
    companion object {
        const val NOW_MS: Long = 1_789_621_500_000
        val PEER = StoreFixtures.PEER
        val ME = StoreFixtures.USER

        fun lobby(incoming: Boolean = true, outgoing: String? = null, activeMatch: String? = null, matches: String = "[]", ruby: Long = 100): Reply = Reply.Json(
            """{"status":"ok","server_now_ms":$NOW_MS,"me":{"ruby_balance":$ruby,"wins":2,"losses":1,"draws":0""" +
                (activeMatch?.let { ""","active_match_id":"$it"""" } ?: "") +
                ""","incoming":[${if (incoming) """{"match_id":"inv-1","from":{"id":"$PEER","display_name":"구름빵"},"stake":5,"expires_at_ms":${NOW_MS + 60_000}}""" else ""}]""" +
                (outgoing?.let { ""","outgoing":{"match_id":"$it","to":{"id":"$PEER","display_name":"구름빵"},"stake":3,"expires_at_ms":${NOW_MS + 60_000}}""" } ?: "") +
                """},"users":[{"id":"$PEER","display_name":"구름빵","is_working":true,"in_match":false,"capable":true}],"matches":$matches}""",
        )

        /**
         * [myDevice] 기본값 'this' = **이 기기가 두는 판**(v0.3.69 서버 20261103124000 의 my_device — Swift `tdState` 와 같은 기본). 이 파일·게임 탭의
         * 한 기기 시험들은 그 전제로 판을 세운다. null 이면 키를 아예 안 싣는다(옛 서버) — 그때는 '이 기기가 연 판' 기록이 가른다.
         */
        fun activeState(
            id: String = "inv-1", startAtMs: Long? = null, mySeq: Int = 0, opponentSeq: Int = 0, finished: Boolean = false,
            myDevice: String? = "this",
        ): String =
            """{"match_id":"$id","status":"${if (finished) "finished" else "active"}","stake":5,"seed":77,"server_now_ms":$NOW_MS""" +
                (startAtMs?.let { ""","start_at_ms":$it""" } ?: "") +
                (myDevice?.let { ""","my_device":"$it"""" } ?: "") +
                ""","me":{"id":"$ME","seq":$mySeq,"ready":false},"opponent":{"id":"$PEER","display_name":"구름빵","seq":$opponentSeq,"ready":true}}"""

        /** 끝난 판 상태(승자 칸 · result 글자 · 판돈). [winner] 가 null 이면 승자 칸이 없다(무승부). */
        fun finishedState(id: String = "inv-1", stake: Int, winner: String?, result: String): String =
            """{"match_id":"$id","status":"finished","stake":$stake,"seed":77,"server_now_ms":$NOW_MS,"result":"$result",""" +
                (winner?.let { """"winner":"$it",""" } ?: "") +
                """"end_reason":"${if (winner == null) "time_cap" else "topout"}",""" +
                """"me":{"id":"$ME","seq":4,"ready":true},"opponent":{"id":"$PEER","display_name":"구름빵","seq":5,"ready":true}}"""

        fun action(status: String = "ok", state: String? = null, extra: String = ""): Reply =
            Reply.Json("""{"status":"$status"${state?.let { ""","state":$it""" } ?: ""}$extra,"server_now_ms":$NOW_MS}""")
    }

    private class Tetris {
        var lobbyReply: Reply = lobby()
        val reports = ArrayDeque<Reply>()
        var watchLive: Reply = Reply.pgrst202
        var watch: Reply = Reply.pgrst202
        var respondReply: Reply = action(state = activeState())
        fun route(r: RecordedRequest): Reply? = when (r.rpcName) {
            "tetris_lobby" -> lobbyReply
            "tetris_challenge" -> action(extra = ""","match_id":"out-1","expires_at_ms":${NOW_MS + 60_000}""")
            "tetris_respond" -> respondReply
            "tetris_cancel" -> action()
            "tetris_state" -> action(state = activeState())
            "tetris_report" -> reports.removeFirstOrNull() ?: action(state = activeState(mySeq = 1))
            "tetris_ranking" -> Reply.Json("""{"status":"ok","rows":[]}""")
            "tetris_watch_live" -> watchLive
            "tetris_watch" -> watch
            else -> null
        }
    }

    private suspend fun TestScope.harness(enabled: Boolean, stub: Tetris = Tetris()): StoreHarness {
        val h = StoreHarness(this, AppConfig(duelsEnabled = enabled), route = stub::route)
        h.signIn()
        // 단조 시계 = 가상 시간(판 시계·보고 간격이 시험 시계로 흐른다).
        h.tetris.uptime = { testScheduler.currentTime / 1000.0 }
        h.tetris.refreshLobby()
        // advanceUntilIdle 이 아니다 — 그것은 신청 만료 깨우기(60초 뒤)까지 당겨 받은 신청을 걷는다.
        runCurrent()
        return h
    }

    private fun StoreHarness.respondAccepts(): List<Boolean> =
        server.bodies("tetris_respond").map { it.contains("\"p_accept\":true") }

    /**
     * ★ G §8-17 #1: 판돈 대결의 **신청·수락**은 앱 구성 깃발 `duelsEnabled` 가 켜진 빌드에서만 나간다(서버 변경 없음 — 로비 `me.capable` 추가
     * 안 함). 짝으로 잰다: 같은 로비·같은 손짓에 깃발만 다르다. 꺼짐 → 화면 게이트 셋이 닫히고 스토어도 요청 **0건**, 켜짐 → 1건씩.
     */
    @Test
    fun challengeAndAcceptGoOutOnlyWhenTheBuildEnablesDuels() = runTest {
        for (enabled in listOf(false, true)) {
            val h = harness(enabled)
            val user = h.tetris.users.single()
            assertTrue(user.canBeChallenged, "상대는 신청할 수 있는 사람이다(깃발 말고는 막을 까닭이 없다)")
            assertEquals(enabled, GamesTetrisDuelChallengeGate.isEnabled(user, h.tetris, null), "신청 게이트 enabled=$enabled")
            assertEquals(if (enabled) TetrisDuelStake.five else null,
                GamesTetrisDuelStakeSend.sendable(TetrisDuelStake.five, h.tetris, 100, null), "판돈 보내기 enabled=$enabled")
            assertEquals(enabled, GamesTetrisDuelAcceptGate.isEnabled(h.tetris, null), "수락 게이트 enabled=$enabled")

            h.tetris.challenge(user.id, TetrisDuelStake.five)
            runCurrent()
            assertEquals(if (enabled) 1 else 0, h.server.count("tetris_challenge"), "신청 요청 enabled=$enabled")
            assertEquals(if (enabled) "out-1" else null, h.tetris.outgoing?.id)

            h.tetris.respond("inv-1", accept = true)
            runCurrent()
            assertEquals(if (enabled) listOf(true) else emptyList(), h.respondAccepts(), "수락 요청 enabled=$enabled")
            assertEquals(if (enabled) "inv-1" else null, h.tetris.match?.id, "수락한 판 enabled=$enabled")
            h.assertClean()
        }
    }

    /** 깃발은 기본이 꺼짐이다 — 조립 지점이 켜지 않은 빌드(기본 AppConfig)는 신청을 내지 않는다. [거절] 은 판돈이 움직이지 않아 막지 않는다. */
    @Test
    fun theDefaultBuildIsOffButDeclineStillWorks() = runTest {
        val h = StoreHarness(this, route = Tetris()::route)
        h.signIn()
        h.tetris.refreshLobby()
        runCurrent()
        assertFalse(h.tetris.duelsEnabled)
        h.tetris.challenge(PEER, TetrisDuelStake.three)
        h.tetris.respond("inv-1", accept = true)
        runCurrent()
        assertEquals(0, h.server.count("tetris_challenge"))
        assertEquals(0, h.server.count("tetris_respond"))
        h.tetris.respond("inv-1", accept = false)
        runCurrent()
        assertEquals(listOf(false), h.respondAccepts(), "거절은 나간다")
        assertTrue(h.tetris.incoming.isEmpty(), "거절한 신청 카드를 걷는다")
    }

    /** 게임 탭 카드는 수락할 수 없는 빌드에서 받은 신청을 칩으로 내세우지 않는다(눌러도 수락할 문이 없다) — 켜진 빌드는 칩이 선다. */
    @Test
    fun theCardOnlyAdvertisesAnInviteTheBuildCanAccept() = runTest {
        for (enabled in listOf(false, true)) {
            val h = harness(enabled)
            val games = GamesStore(h.context)
            assertNotNull(h.tetris.visibleIncoming)
            assertEquals(if (enabled) GamesTetrisDuelCard.Line.incoming else GamesTetrisDuelCard.Line.record,
                GamesTetrisDuelCard.line(games), "enabled=$enabled")
            assertEquals(if (enabled) TetrisPhoneText.incomingChip else null, GamesTetrisDuelCard.chip(games))
        }
    }

    /**
     * 준비 = 첫 보고. **창이 보일 때만** 나간다(머리말 ⑨) — 보이지 않는 판의 준비 보고가 나가면 사람은 못 보는 카운트다운에 끌려 들어가
     * 판돈을 잃는다. 기준선(창이 보임)은 같은 판에서 보고 1건이다.
     */
    @Test
    fun theReadyReportWaitsForTheWindow() = runTest {
        val h = harness(enabled = true)
        h.tetris.respond("inv-1", accept = true)
        runCurrent()
        assertEquals(TetrisDuelPhase.ready, h.tetris.phase)
        advanceTimeBy(1_000)
        h.tetris.tick()
        runCurrent()
        assertEquals(0, h.server.count("tetris_report"), "창이 안 보이면 준비 보고 0건")
        h.tetris.windowDidShow()
        runCurrent()
        assertEquals(1, h.server.count("tetris_report"), "창이 보이면 준비 보고 1건")
        assertTrue(h.server.bodies("tetris_report").single().contains("\"p_seq\":1"))
    }

    /** 보고가 두 번 연달아 실패하면 "연결 확인 중" — 다음 성공이 내린다. 3초 넘게 답이 없는 보고는 버리고 실패 한 번으로 센다(RV2). */
    @Test
    fun reportFailuresRaiseConnectionTroubleAndAStalledReportIsAbandoned() = runTest {
        val stub = Tetris()
        stub.reports += Reply.Offline
        stub.reports += Reply.Hang
        val h = harness(enabled = true, stub = stub)
        h.tetris.respond("inv-1", accept = true)
        runCurrent()
        h.tetris.windowDidShow()
        runCurrent()
        assertEquals(1, h.tetris.reportFailureStreak, "첫 보고 실패")
        assertFalse(h.tetris.connectionTrouble)
        advanceTimeBy(1_500)
        h.tetris.tick()
        runCurrent()
        assertTrue(h.tetris.reportInFlight, "두 번째 보고가 멎었다")
        advanceTimeBy(3_500)
        h.tetris.tick()
        assertTrue(h.tetris.connectionTrouble, "멎은 보고를 버리며 두 번째 실패로 센다")
        runCurrent()
        assertFalse(h.tetris.connectionTrouble, "새로 낸 보고가 성공하면 내린다")
        assertEquals(0, h.tetris.reportFailureStreak)
    }

    /** 방금 세운 보낸 신청보다 **먼저 나간** 로비 응답이 그 신청을 지우지 않는다(거절 안내도 없다). */
    @Test
    fun aLobbyResponseThatPredatesTheChallengeDoesNotEraseIt() = runTest {
        val stub = Tetris()
        val h = harness(enabled = true, stub = stub)
        val gate = CompletableDeferred<Unit>()
        stub.lobbyReply = Reply.Gate(gate, lobby(incoming = false))
        val lobbyJob = h.storeScope.launch { h.tetris.refreshLobby() }
        runCurrent()
        h.tetris.challenge(PEER, TetrisDuelStake.three)
        runCurrent()
        assertEquals("out-1", h.tetris.outgoing?.id)
        gate.complete(Unit)
        lobbyJob.join()
        runCurrent()
        assertEquals("out-1", h.tetris.outgoing?.id, "옛 로비 응답이 방금 보낸 신청을 지우지 않는다")
        assertEquals(TetrisDuelNoticeText.challenge(com.yehsung.aingcheck.core.wire.games.TetrisRPCStatus.ok), h.tetris.notice)
    }

    /**
     * 관전 깃발 둘은 **겸업하지 않는다**: `tetris_watch_live` 만 없으면 관전자 수 한 칸만 접고 옛 길로 곧바로 간다(입구는 열린 채) ·
     * `tetris_watch` 마저 없으면 그때 입구를 잠그고, 잠긴 입구는 요청을 0건 낸다 · 로비 주기(30초)가 한 번 풀어 준다.
     */
    @Test
    fun watchFlagsNeverDoubleUp() = runTest {
        val stub = Tetris()
        stub.lobbyReply = lobby(incoming = false, matches = """[{"id":"live-1","a":{"id":"$PEER","display_name":"구름빵"},"b":{"id":"${StoreFixtures.OTHER}","display_name":"달토끼"},"stake":5,"started_at_ms":${NOW_MS - 30_000},"watchers":4}]""")
        stub.watch = Reply.Json("""{"status":"ok","server_now_ms":$NOW_MS,"match":{"id":"live-1","stake":5,"status":"active","started_ms":${NOW_MS - 30_000}},"a":{"user":{"id":"$PEER"},"board":"${".".repeat(200)}","lines":3},"b":{"user":{"id":"${StoreFixtures.OTHER}"},"board":"bad","lines":1}}""")
        val h = harness(enabled = false, stub = stub)
        h.tetris.spectatorFeaturesEnabled = true
        h.tetris.windowDidShow()
        runCurrent()
        assertEquals(GamesTetrisWatchPlan.Entry.chip, GamesTetrisWatchPlan.entry(h.tetris, isMine = false), "관전은 깃발(판돈)과 무관하다")
        h.tetris.startWatching("live-1")
        runCurrent()
        assertEquals(listOf("tetris_watch_live", "tetris_watch"), h.gameRpcs().filter { it.startsWith("tetris_watch") })
        assertTrue(h.tetris.spectatorCountUnavailable)
        assertFalse(h.tetris.watchUnavailable, "관전자 수가 없다는 이유로 입구를 잠그지 않는다")
        assertEquals(0, h.tetris.spectatorCount)
        val watching = assertNotNull(h.tetris.spectating)
        assertEquals(3, watching.a.lines)
        assertNull(watching.b.cells, "깨진 판은 그 자리만 접는다")
        assertEquals(1, watching.b.lines, "반대쪽 숫자는 산다")

        stub.watch = Reply.pgrst202
        h.tetris.refreshWatch()
        runCurrent()
        assertTrue(h.tetris.watchUnavailable, "tetris_watch 마저 없으면 입구를 잠근다")
        assertNull(h.tetris.spectating)
        assertEquals(TetrisDuelAvailability.available, h.tetris.availability, "관전 함수 하나 때문에 1:1 전체를 잠그지 않는다")
        assertEquals(GamesTetrisWatchPlan.Entry.soon, GamesTetrisWatchPlan.entry(h.tetris, isMine = false))
        val before = h.server.requests.size
        h.tetris.startWatching("live-1")
        runCurrent()
        assertEquals(before, h.server.requests.size, "잠긴 입구는 문 앞에서 막는다(요청 0건)")
        advanceTimeBy(31_000)
        h.tetris.pollWatch(h.clock.now())
        assertFalse(h.tetris.watchUnavailable, "로비 주기에 한 번 풀어 준다")
    }

    /**
     * 겸업 금지의 다른 면: `tetris_watch_live` 가 없어 옛 길로 내려간 그 호출이 **일시 장애**(5xx)로 실패해도 입구는 잠그지 않는다 —
     * 성공 응답이 잠금을 풀어 주는 길이 없으니, 여기서 잠그면 관전자 수 칸 하나 때문에 관전이 30초씩 막힌다.
     */
    @Test
    fun aMissingCountFunctionNeverLocksTheWatchEvenWhenTheFallbackFails() = runTest {
        val stub = Tetris()
        stub.lobbyReply = lobby(incoming = false, matches = """[{"id":"live-1","a":{"id":"$PEER","display_name":"구름빵"},"b":{"id":"${StoreFixtures.OTHER}","display_name":"달토끼"},"stake":5,"started_at_ms":${NOW_MS - 30_000},"watchers":4}]""")
        stub.watch = Reply.serverDown
        val h = harness(enabled = false, stub = stub)
        h.tetris.spectatorFeaturesEnabled = true
        h.tetris.windowDidShow()
        runCurrent()
        h.tetris.startWatching("live-1")
        runCurrent()
        assertEquals(listOf("tetris_watch_live", "tetris_watch"), h.gameRpcs().filter { it.startsWith("tetris_watch") })
        assertTrue(h.tetris.spectatorCountUnavailable, "관전자 수 칸은 접는다")
        assertFalse(h.tetris.watchUnavailable, "관전 입구는 잠그지 않는다(5xx 는 '함수 없음'이 아니다)")
        assertEquals(GamesTetrisWatchPlan.Entry.chip, GamesTetrisWatchPlan.entry(h.tetris, isMine = false))
    }

    /**
     * 판 결과의 승패·루비(Swift V0360TetrisDuelStoreTests `rubyDeltaFollowsDuelFee` · `unknownStatus…` 의 끝 줄): 승 = 승자 칸이 **내 id**
     * (대소문자를 접는다 — 서버 uuid 표기와 세션 표기가 달라도 같은 사람이다) · 패 = 승자가 상대 · 무 = result 'draw'. 판돈 3·5·10 모두
     * 승 +순이익(DuelFee) · 패 −판돈 · 무 0. 골든 duel/resume 은 호스트가 없어(내 id 모름) '이겼다' 갈래를 못 잰다 — 로그인 하네스로 잰다.
     * 틀리면 이긴 사람에게 '졌어요'와 −판돈이 그려진다. 기준선(다른 입력): 같은 판에 승자만 상대로 바꾸면 패다.
     */
    @Test
    fun theOutcomeAndRubyFollowTheWinnerID() = runTest {
        val json = Json { ignoreUnknownKeys = true }
        for (stake in listOf(3, 5, 10)) {
            val cases = listOf(
                Triple(ME.uppercase(), "opponent_win", TetrisDuelOutcome.won to DuelFee.winnerNet(stake)),
                Triple(PEER.uppercase(), "challenger_win", TetrisDuelOutcome.lost to -stake),
                Triple(null, "draw", TetrisDuelOutcome.draw to 0),
            )
            for ((winner, result, want) in cases) {
                val h = harness(enabled = true)
                assertTrue(winner == null || winner != winner.lowercase(), "전제: 승자 칸은 세션 id 와 대소문자가 다르다")
                h.tetris.applyState(json.decodeFromString(TetrisStatePayload.serializer(), finishedState(stake = stake, winner = winner, result = result)), 0.0)
                val match = assertNotNull(h.tetris.match, "stake $stake $result")
                assertTrue(match.isFinished)
                assertEquals(want.first, match.outcome, "stake $stake $result")
                assertEquals(want.second, match.rubyDelta, "stake $stake $result")
                assertEquals(TetrisDuelPhase.finished, h.tetris.phase)
            }
        }
        assertEquals(10, DuelFee.winnerNet(10), "v0.3.64 수수료 0 — 판돈 10 승리 = +10")
    }

    /** 루비 칸 타입은 Long 하나(G §8-18 #4 · 8차 fold): Int 범위를 넘는 잔액도 와이어 → 스토어 → 호스트 칸 → 판돈 판정까지 자르지 않는다. */
    @Test
    fun rubyBalanceBeyondIntRangeIsNotClamped() = runTest {
        val big = 5_000_000_000L
        val h = harness(enabled = true, stub = Tetris().apply { lobbyReply = lobby(ruby = big) })
        assertEquals(big, h.tetris.rubyBalance, "로비 me.ruby_balance 가 Int 범위를 넘어도 그대로")
        assertEquals(big, h.tetrisHost.rubyBalance, "호스트(공유 루비 칸)에도 같은 값")
        assertTrue(GamesTetrisStakeSelection.affordable(TetrisDuelStake.ten, big), "큰 잔액이 음수로 감겨 판돈을 막지 않는다")
        assertFalse(GamesTetrisStakeSelection.affordable(TetrisDuelStake.ten, 9L))
    }

    /** 로그아웃: 판·신청·순위·루비·관전이 남지 않는다 — 배선 값(순위·관전 주 스위치)은 그대로 둔다. */
    @Test
    fun resetForgetsTheAccountButKeepsTheWiring() = runTest {
        val h = harness(enabled = true)
        h.tetris.rankingEnabled = true
        h.tetris.spectatorFeaturesEnabled = true
        h.tetris.respond("inv-1", accept = true)
        runCurrent()
        assertNotNull(h.tetris.match)
        h.tetris.reset()
        assertNull(h.tetris.match)
        assertNull(h.tetris.duel)
        assertTrue(h.tetris.users.isEmpty())
        assertNull(h.tetris.record)
        assertNull(h.tetris.rubyBalance)
        assertEquals(TetrisDuelPhase.lobby, h.tetris.phase)
        assertTrue(h.tetris.rankingEnabled)
        assertTrue(h.tetris.spectatorFeaturesEnabled)
    }
}
