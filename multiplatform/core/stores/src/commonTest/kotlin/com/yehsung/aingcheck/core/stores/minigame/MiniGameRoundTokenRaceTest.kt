// 원본: Tests/CheckMobileKitTests/GamesTetrisWiringTests.swift:451-864(인편 · too_fast · token_used · 밀려난 인편) ·
//       GamesStoreScenarioTests.swift:134-220(토큰 선발급 · 늦은 응답) · Tests/checkTests/V0339MiniGamePendingSubmitTests.swift:250-260(되보낼·못 올릴 status 는 겹치지 않는다) @ 1b8260d · 기억 minigame-round-token-race
// G §2-3 W2-e ①: 라운드 토큰 경합 — **그 게임의 제출(인편)이 살아 있는 동안 그 게임의 `start_round` 는 나가지 않는다.**
package com.yehsung.aingcheck.core.stores.minigame

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.core.stores.games.Reply
import com.yehsung.aingcheck.core.stores.games.StoreHarness
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MiniGameRoundTokenRaceTest {
    /** 미니게임 스텁: start_round 는 차례로 t1·t2… 를 주고, submit 은 [submits] 큐(비면 ok), 공개 여부는 [public]. */
    private class Minigame {
        var tokens = 0
        val submits = ArrayDeque<Reply>()
        var startGate: CompletableDeferred<Unit>? = null
        var startReply: ((Int) -> Reply)? = null
        var public: Reply = Reply.Json("""[{"minigame_public":true}]""")

        fun route(r: RecordedRequest): Reply? = when {
            r.rpcName == "minigame_start_round" -> {
                tokens += 1
                val n = tokens
                val reply = startReply?.invoke(n) ?: Reply.Json("""{"status":"ok","token":"t$n"}""")
                val gate = startGate
                if (gate != null) {
                    startGate = null
                    Reply.Gate(gate, reply)
                } else reply
            }
            r.rpcName == "minigame_submit_score" -> submits.removeFirstOrNull() ?: ok()
            r.rpcName == "minigame_board" -> Reply.Json("[]")
            r.rpcName == "minigame_yesterday_winner" -> Reply.Json("[]")
            r.path == "/rest/v1/profiles" && r.method == "GET" -> public
            else -> null
        }

        companion object {
            fun ok(best: Int = 13) = Reply.Json("""{"status":"ok","best_score":$best,"plays":1,"improved":true}""")
            fun status(s: String) = Reply.Json("""{"status":"$s"}""")
        }
    }

    private suspend fun TestScope.open(stub: Minigame = Minigame()): Pair<StoreHarness, GamesMiniGameHub> {
        val h = StoreHarness(this, route = stub::route)
        h.signIn()
        val hub = GamesMiniGameHub(h.context)
        return h to hub
    }

    private fun StoreHarness.minigameRpcs(): List<String> = gameRpcs().filter { it == "minigame_start_round" || it == "minigame_submit_score" }

    private fun StoreHarness.submitTokens(): List<String> =
        server.bodies("minigame_submit_score").map { Regex("\"p_token\":\"([^\"]+)\"").find(it)!!.groupValues[1] }

    /**
     * ★ 핵심 경합: 제출이 왕복 중인 동안 사람이 결과 카드를 눌러 새 판을 시작해도(onStarted → beginRound) · 강제 선발급이 와도
     * `start_round` 는 **0건**이다 — 서버가 미사용 행을 갈아 끼워 제출이 든 토큰이 그 자리에서 죽기 때문이다(0.3.38 신고 여섯 판 no_token).
     * 제출이 끝난 **뒤에야** 다음 토큰을 받는다.
     */
    @Test
    fun startRoundNeverGoesOutWhileTheSubmitIsOnTheWire() = runTest {
        val stub = Minigame()
        val gate = CompletableDeferred<Unit>()
        stub.submits += Reply.Gate(gate, Minigame.ok())
        val (h, hub) = open(stub)
        hub.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        assertEquals("t1", hub.roundToken, "화면을 열면 토큰을 미리 받는다")

        hub.recordScore(MiniGameKind.flappy, 13)
        runCurrent()
        assertEquals(listOf("minigame_start_round", "minigame_submit_score"), h.minigameRpcs())
        assertNotNull(hub.pendingSubmit, "제출 전에 인편에 적는다")

        // 제출이 떠 있는 동안: 새 판 시작 · 강제 선발급 · (갈아 끼우는 게임이면) 판 도중 감시 — 셋 다 start_round 를 내지 않는다.
        hub.beginRound(MiniGameKind.flappy)
        hub.prefetchRoundToken(MiniGameKind.flappy, force = true)
        hub.keepRoundTokenFresh(MiniGameKind.flappy)
        advanceTimeBy(5_000)   // 요청 상한(15초)보다 짧게 — 그 사이 다른 일이 나가는지만 본다
        runCurrent()
        assertEquals(listOf("minigame_start_round", "minigame_submit_score"), h.minigameRpcs(), "인편이 살아 있는 동안 start_round 0건")
        assertNull(hub.roundToken)

        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(listOf("minigame_start_round", "minigame_submit_score", "minigame_start_round"), h.minigameRpcs(),
            "제출이 끝난 뒤에야 다음 토큰")
        assertNull(hub.pendingSubmit)
        assertEquals("t2", hub.roundToken)
        assertEquals(listOf("t1"), h.submitTokens(), "한 토큰에 한 점수")
        h.assertClean()
    }

    /** 기준선(다른 입력 — 인편 없음 · 토큰 없음): 같은 `beginRound` 가 이번에는 start_round 를 낸다. 위 시험의 0건은 인편 가드 덕이다. */
    @Test
    fun withoutAPendingSubmitBeginRoundRequestsAToken() = runTest {
        val stub = Minigame()
        stub.startReply = { n -> if (n == 1) Minigame.status("invalid") else Reply.Json("""{"status":"ok","token":"t$n"}""") }
        val (h, hub) = open(stub)
        hub.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        assertNull(hub.roundToken, "첫 토큰은 거절됐다")
        hub.beginRound(MiniGameKind.flappy)
        advanceUntilIdle()
        assertEquals(listOf("minigame_start_round", "minigame_start_round"), h.minigameRpcs())
        assertEquals("t2", hub.roundToken)
    }

    /** 네트워크로 실패한 제출은 **남는다** — 그 사이 선발급은 막히고, 앱이 다시 켜지면 **같은 토큰으로** 한 번 더 보낸다. */
    @Test
    fun aNetworkFailureKeepsThePendingSubmitAndBlocksTheNextTokenUntilItIsRetried() = runTest {
        val stub = Minigame()
        stub.submits += Reply.Offline
        val (h, hub) = open(stub)
        hub.openScreen(MiniGameKind.tetris)
        advanceUntilIdle()
        hub.recordScore(MiniGameKind.tetris, 4200)
        advanceUntilIdle()
        assertEquals(GamesMiniGameText.submitFailedConnection, hub.submitNotice)
        assertEquals("t1", hub.pendingSubmit?.token, "인편이 남는다")
        assertEquals(listOf("minigame_start_round", "minigame_submit_score"), h.minigameRpcs(),
            "실패 꼬리의 선발급도 인편 가드에 막힌다(받으면 인편의 토큰이 죽는다)")

        hub.retryPendingSubmitIfAny()   // 앱이 다시 active
        advanceUntilIdle()
        assertEquals(listOf("t1", "t1"), h.submitTokens(), "같은 토큰으로 한 번 더")
        assertNull(hub.pendingSubmit)
        assertEquals(listOf("minigame_start_round", "minigame_submit_score", "minigame_submit_score", "minigame_start_round"), h.minigameRpcs())
        assertEquals(listOf("tetris"), h.achievementRefreshes, "판이 서버에 남은 직후 일일 미션 한 번")
        h.assertClean()
    }

    /** `too_fast` 는 거절이 아니다 — 인편을 남기고 눈먼 지연(1.5 · 4초) 뒤 **같은 토큰으로** 되보낸다. 그 사이 start_round 0건. */
    @Test
    fun tooFastIsRetriedWithTheSameTokenAfterBlindDelays() = runTest {
        val stub = Minigame()
        stub.submits += Minigame.status("too_fast")
        stub.submits += Minigame.ok(best = 7)
        val (h, hub) = open(stub)
        hub.openScreen(MiniGameKind.timingBar)
        advanceUntilIdle()
        hub.recordScore(MiniGameKind.timingBar, 7)
        runCurrent()
        assertEquals(GamesMiniGameText.submitRetrying, hub.submitNotice, "기다리는 동안은 '올리는 중'")
        advanceTimeBy(1_400)
        runCurrent()
        assertEquals(1, h.server.count("minigame_submit_score"), "1.5초 전에는 안 보낸다")
        advanceTimeBy(200)
        advanceUntilIdle()
        assertEquals(listOf("t1", "t1"), h.submitTokens())
        assertNull(hub.pendingSubmit)
        assertNull(hub.submitNotice)
        assertEquals(listOf("minigame_start_round", "minigame_submit_score", "minigame_submit_score", "minigame_start_round"), h.minigameRpcs())
    }

    /** 되보내기는 **횟수가 묶여 있다**(두 번) — 다 쓰면 사실대로 "못 올렸어요" 를 말하고 인편을 놓아 준다(그때 비로소 다음 토큰). */
    @Test
    fun tooFastGivesUpAfterTwoRetriesAndThenReleasesThePending() = runTest {
        val stub = Minigame()
        repeat(3) { stub.submits += Minigame.status("too_fast") }
        val (h, hub) = open(stub)
        hub.openScreen(MiniGameKind.timingBar)
        advanceUntilIdle()
        hub.recordScore(MiniGameKind.timingBar, 7)
        advanceTimeBy(1_500)
        runCurrent()
        assertEquals(2, h.server.count("minigame_submit_score"))
        assertEquals(1, h.server.count("minigame_start_round"), "되보내는 동안 start_round 0건")
        advanceTimeBy(4_000)
        advanceUntilIdle()
        assertEquals(listOf("t1", "t1", "t1"), h.submitTokens())
        assertEquals(GamesMiniGameText.submitRefused, hub.submitNotice)
        assertNull(hub.pendingSubmit)
        assertEquals(2, h.server.count("minigame_start_round"), "포기한 뒤에 다음 토큰")
        advanceTimeBy(600_000)
        advanceUntilIdle()
        assertEquals(3, h.server.count("minigame_submit_score"), "세 번째 too_fast 뒤로는 더 보내지 않는다(무한 백오프 금지)")
    }

    /** `token_used` 는 **성공이다**(응답만 유실된 첫 제출의 재시도) — "못 올렸어요" 로 그리지 않는다. */
    @Test
    fun tokenUsedIsASuccess() = runTest {
        val stub = Minigame()
        stub.submits += Reply.Json("""{"status":"token_used","best_score":20}""")
        val (h, hub) = open(stub)
        hub.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        hub.recordScore(MiniGameKind.flappy, 13)
        advanceUntilIdle()
        assertNull(hub.submitNotice)
        assertNull(hub.pendingSubmit)
        assertEquals(20L, hub.best(MiniGameKind.flappy), "서버가 확정한 최고를 로컬에도 올린다")
        assertEquals(listOf("flappy"), h.achievementRefreshes)
    }

    /** 늦게 온 옛 토큰 응답은 새 토큰을 덮지 않는다(세대 가드) — 내 뒤에 나간 요청이 있었다면 내 토큰은 이미 죽었다. */
    @Test
    fun aLateTokenResponseNeverOverwritesTheNewerOne() = runTest {
        val stub = Minigame()
        val slow = CompletableDeferred<Unit>()
        stub.startGate = slow
        val (h, hub) = open(stub)
        // advanceUntilIdle 이 아니다 — 그것은 요청 상한(30초)까지 시간을 당겨 막힌 첫 왕복을 시간 초과로 끝낸다(늦은 응답이 안 온다).
        hub.openScreen(MiniGameKind.flappy)
        runCurrent()
        assertNull(hub.roundToken, "첫 왕복이 아직 안 끝났다")
        assertEquals(MiniGameKind.flappy, hub.roundTokenInFlightKind)
        // 판이 이미 끝났는데 토큰이 없다 — 강제로 새로 받는다(첫 왕복은 이번 판에 늦었다).
        hub.recordScore(MiniGameKind.flappy, 3)
        runCurrent()
        assertEquals(GamesMiniGameText.submitFailedConnection, hub.submitNotice)
        assertEquals("t2", hub.roundToken)
        slow.complete(Unit)
        runCurrent()
        assertEquals(2, h.server.count("minigame_start_round"))
        assertEquals("t2", hub.roundToken, "늦게 온 t1 은 버린다")
        assertEquals(0, h.server.count("minigame_submit_score"), "토큰 없이 끝난 판은 제출하지 않는다")
    }

    /** 되보낼 status 와 영영 못 올릴 status 는 **겹칠 수 없다** — 겹치면 앞선 갈래가 뒤를 조용히 삼킨다(Swift 짝 시험 그대로). */
    @Test
    fun retryableAndTerminalStatusesNeverOverlap() {
        assertEquals(emptySet(), GamesMiniGameHub.retryableSubmitStatuses intersect GamesMiniGameHub.terminalSubmitStatuses)
        assertEquals(emptySet(), GamesMiniGameHub.retryableSubmitStatuses intersect GamesMiniGameHub.deadTokenStatuses)
        assertTrue(GamesMiniGameHub.terminalSubmitStatuses.containsAll(GamesMiniGameHub.deadTokenStatuses), "죽은 토큰 거절은 인편도 지운다")
        assertTrue("token_used" !in GamesMiniGameHub.terminalSubmitStatuses, "token_used 는 성공이다")
        assertEquals(listOf(1.5, 4.0), GamesMiniGameHub.tooFastRetryDelaysSeconds, "눈먼 지연 두 번")
    }

    /** 호출자 쪽 거절(`unauthorized`·`no_profile`)도 인편을 지운다(안 지우면 앱을 켤 때마다 영원히 다시 보낸다) · 토큰이 죽은 거절은 문장을 가른다. */
    @Test
    fun terminalRefusalsReleaseThePendingAndDeadTokensSayWhatHappened() = runTest {
        for ((status, notice) in listOf(
            "unauthorized" to GamesMiniGameText.submitRefused,
            "no_profile" to GamesMiniGameText.submitRefused,
            "no_token" to GamesMiniGameText.submitTokenDead,
            "token_expired" to GamesMiniGameText.submitTokenDead,
        )) {
            val stub = Minigame()
            stub.submits += Minigame.status(status)
            val (h, hub) = open(stub)
            hub.openScreen(MiniGameKind.flappy)
            advanceUntilIdle()
            hub.recordScore(MiniGameKind.flappy, 5)
            advanceUntilIdle()
            assertEquals(notice, hub.submitNotice, status)
            assertNull(hub.pendingSubmit, "$status — 인편을 지운다")
            assertEquals(2, h.server.count("minigame_start_round"), "$status — 다음 토큰을 받는다")
            hub.retryPendingSubmitIfAny()
            advanceUntilIdle()
            assertEquals(1, h.server.count("minigame_submit_score"), "$status — 복귀해도 다시 보내지 않는다")
        }
    }

    /**
     * 인편 칸에서 **밀려나는** 앞 판을 조용히 버리지 않는다 — 다른 게임의 판이 인편을 갈아 끼우면 앞 판을 마지막으로 한 번 더 보낸다
     * (응답만 유실된 첫 제출이면 `token_used` 로 성공). 그 판의 거절 문구는 화면에 쓰지 않는다(지금 판의 자리다).
     */
    @Test
    fun aSupersededPendingIsSentOnceMoreBeforeItIsDropped() = runTest {
        val stub = Minigame()
        stub.submits += Reply.Offline                                            // 플래피 첫 제출 — 망 실패
        stub.submits += Reply.Offline                                            // 테트리스 화면을 열며 민 인편 — 또 실패
        stub.submits += Reply.Json("""{"status":"token_used","best_score":35}""") // 밀려난 플래피 — 이미 올라가 있었다
        stub.submits += Minigame.ok(best = 900)                                   // 테트리스
        val (h, hub) = open(stub)
        hub.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        hub.recordScore(MiniGameKind.flappy, 30)
        advanceUntilIdle()
        assertEquals("flappy", hub.pendingSubmit?.kind?.rawValue)
        hub.openScreen(MiniGameKind.tetris)
        advanceUntilIdle()
        assertEquals("flappy", hub.pendingSubmit?.kind?.rawValue, "화면을 열며 민 인편이 또 실패했다")
        assertEquals("t2", hub.roundToken, "다른 게임의 인편은 이 게임 토큰을 막지 않는다")
        hub.recordScore(MiniGameKind.tetris, 900)
        advanceUntilIdle()
        assertEquals(listOf("t1", "t1", "t1", "t2"), h.submitTokens(), "밀려나는 플래피를 마지막으로 한 번 더 보낸다")
        assertNull(hub.pendingSubmit)
        assertEquals(35L, hub.best(MiniGameKind.flappy), "밀려난 판의 확정 최고도 반영한다")
        assertNull(hub.submitNotice, "밀려난 판의 결과는 지금 판의 안내를 덮지 않는다")
    }

    /** 순위 공개를 끈 사람: 토큰도 제출도 없다(설정 문구 "올라가지도 않아요") — 로컬 최고만 오른다. 공개 여부 조회 실패는 아는 값을 지킨다. */
    @Test
    fun aPrivatePlayerNeverAsksForTokensAndAFailedLookupKeepsTheKnownValue() = runTest {
        val stub = Minigame()
        stub.public = Reply.Json("""[{"minigame_public":false}]""")
        val (h, hub) = open(stub)
        hub.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        assertEquals(false, hub.isPublic)
        hub.beginRound(MiniGameKind.flappy)
        hub.recordScore(MiniGameKind.flappy, 11)
        advanceUntilIdle()
        assertEquals(emptyList(), h.minigameRpcs(), "토큰 0 · 제출 0")
        assertEquals(11L, hub.best(MiniGameKind.flappy))
        stub.public = Reply.serverDown
        hub.refreshPublic()
        advanceUntilIdle()
        assertEquals(false, hub.isPublic, "조회 실패는 '모름 = 공개' 로 덮지 않는다")
        stub.public = Reply.pgrst202
        hub.refreshPublic()
        advanceUntilIdle()
        assertEquals(true, hub.isPublic, "표가 없는 서버는 공개로 접는다")
    }

    /**
     * 판 도중 토큰 갈아 끼우기(길건너 — 맥 `keepMiniGameRoundTokenFresh`): 20분이 지나야 새로 받고, 그 게임의 인편이 살아 있으면
     * 받지 않고 인편부터 민다. 갈아 끼우지 않는 게임은 아무 일도 안 한다.
     */
    @Test
    fun midRunRefreshHonoursTheAgeAndThePendingGuard() = runTest {
        val stub = Minigame()
        stub.submits += Reply.Offline
        val (h, hub) = open(stub)
        hub.prefetchRoundToken(MiniGameKind.crossy)
        advanceUntilIdle()
        assertEquals("t1", hub.roundToken)
        advanceTimeBy(10 * 60_000L)
        hub.keepRoundTokenFresh(MiniGameKind.crossy)
        advanceUntilIdle()
        assertEquals(1, h.server.count("minigame_start_round"), "20분 전에는 그대로 쓴다")
        advanceTimeBy(11 * 60_000L)
        hub.keepRoundTokenFresh(MiniGameKind.crossy)
        advanceUntilIdle()
        assertEquals("t2", hub.roundToken, "20분이 지나면 갈아 끼운다")
        hub.recordScore(MiniGameKind.crossy, 40)
        advanceUntilIdle()
        assertEquals("t2", hub.pendingSubmit?.token, "망 실패로 인편이 남았다")
        advanceTimeBy(25 * 60_000L)
        hub.keepRoundTokenFresh(MiniGameKind.crossy)
        advanceUntilIdle()
        assertEquals(
            listOf("minigame_start_round", "minigame_start_round", "minigame_submit_score", "minigame_submit_score", "minigame_start_round"),
            h.minigameRpcs(), "인편이 살아 있으면 갈아 끼우지 않고 인편부터 민다 — 새 토큰은 인편이 비워진 뒤 꼬리에서만",
        )
        assertEquals(listOf("t2", "t2"), h.submitTokens())
        hub.keepRoundTokenFresh(MiniGameKind.timingBar)
        advanceUntilIdle()
        assertEquals(3, h.server.count("minigame_start_round"), "갈아 끼우지 않는 게임(타이밍 바)의 감시는 아무 일도 안 한다")
    }

    /** Android(G §2-3 W2-e ④): 이 빌드에 보이지 않는 게임(길건너)은 화면을 열지 않는다 — 구동기 0 · 요청 0. */
    @Test
    fun anInvisibleGameNeverOpens() = runTest {
        val (h, hub) = open()
        hub.openScreen(MiniGameKind.crossy)
        advanceUntilIdle()
        assertNull(hub.controller)
        assertNull(hub.activeKind)
        assertEquals(emptyList(), h.gameRpcs())
        hub.refreshSummariesIfStale()
        advanceUntilIdle()
        assertEquals(MiniGameExposure.visible.size, h.server.count("minigame_board"), "첫 화면 카드도 보이는 게임만 읽는다")
        assertTrue(MiniGameKind.crossy !in MiniGameExposure.visible)
    }
}
