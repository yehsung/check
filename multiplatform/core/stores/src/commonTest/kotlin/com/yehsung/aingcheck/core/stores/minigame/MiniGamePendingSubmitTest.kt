// 원본: Tests/checkTests/V0339MiniGamePendingSubmitTests.swift @ 1a5eeca6 (재시작 보존 · TTL · 계정별 · 토큰 대기 FIFO · 백오프 · 모르는 status · no_token 되살림 · 잃은 판 안내)
package com.yehsung.aingcheck.core.stores.minigame

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.games.MemoryPrefs
import com.yehsung.aingcheck.core.stores.games.Reply
import com.yehsung.aingcheck.core.stores.games.StoreFixtures
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
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MiniGamePendingSubmitTest {
    private class Stub {
        var tokens = 0
        val submits = ArrayDeque<Reply>()
        val starts = ArrayDeque<Reply>()
        fun route(r: RecordedRequest): Reply? = when {
            r.rpcName == "minigame_start_round" -> {
                tokens += 1
                starts.removeFirstOrNull() ?: Reply.Json("""{"status":"ok","token":"t$tokens"}""")
            }
            r.rpcName == "minigame_submit_score" -> submits.removeFirstOrNull() ?: ok
            r.rpcName == "minigame_board" || r.rpcName == "minigame_yesterday_winner" -> Reply.Json("[]")
            r.path == "/rest/v1/profiles" && r.method == "GET" -> Reply.Json("""[{"minigame_public":true}]""")
            else -> null
        }

        companion object {
            val ok = Reply.Json("""{"status":"ok","best_score":13,"plays":1,"improved":true}""")
            fun status(s: String) = Reply.Json("""{"status":"$s"}""")
        }
    }

    private suspend fun TestScope.make(stub: Stub = Stub(), prefs: MemoryPrefs = MemoryPrefs()): Pair<StoreHarness, GamesMiniGameHub> {
        val h = StoreHarness(this, prefs = prefs, route = stub::route)
        h.signIn()
        return h to GamesMiniGameHub(h.context)
    }

    private fun StoreHarness.submitTokens(): List<String> =
        server.bodies("minigame_submit_score").map { Regex("\"p_token\":\"([^\"]+)\"").find(it)!!.groupValues[1] }

    private fun StoreHarness.submitScores(): List<Int> =
        server.bodies("minigame_submit_score").map { Regex("\"p_score\":(\\d+)").find(it)!!.groupValues[1].toInt() }

    private val key = GamesMiniGameHub.pendingKey(StoreFixtures.USER)

    /** 망 실패로 인편을 남기고 앱이 죽은 자리(첫 허브는 거둔다 — 타이머·메모리가 사라진다). 토큰은 t1. */
    private suspend fun TestScope.leaveOnePendingBehind(prefs: MemoryPrefs): StoreHarness {
        val stub = Stub()
        stub.submits += Reply.Offline
        val (h, hub) = make(stub, prefs)
        hub.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        hub.recordScore(MiniGameKind.flappy, 11)
        runCurrent()
        assertEquals(listOf("t1"), hub.pendingSubmits.map { it.token }, "인편이 토큰과 함께 남지 않았다")
        assertNotNull(prefs.getString(key), "인편이 저장소에 없다 — 앱이 죽으면 점수가 사라진다")
        hub.reset()
        assertNotNull(prefs.getString(key), "reset 이 영속 인편을 지웠다")
        return h
    }

    @Test
    fun pendingSubmitsSurviveARestartAndResendWithTheSameToken() = runTest {
        val prefs = MemoryPrefs()
        leaveOnePendingBehind(prefs)
        val (h, restarted) = make(prefs = prefs)
        assertTrue(restarted.hasPendingSubmit(MiniGameKind.flappy), "재시작한 허브가 인편을 못 읽었다")
        assertEquals(11, restarted.pendingSubmit?.score)
        assertEquals(1, restarted.pendingSubmit?.attempts, "재시작이 백오프를 0 으로 되돌렸다")
        restarted.retryPendingSubmitIfAny()
        advanceUntilIdle()
        assertEquals(listOf("t1"), h.submitTokens(), "재시작 뒤 다른 토큰으로 나갔다 — 같은 토큰이어야 멱등이다")
        assertEquals(listOf(11), h.submitScores())
        assertEquals(emptyList(), restarted.pendingSubmits)
        assertNull(prefs.getString(key), "성공 뒤 저장소의 인편이 안 지워졌다")
        assertNull(restarted.submitNotice)
        // 인편이 비워진 뒤에야 다음 토큰.
        assertEquals(listOf("minigame_submit_score", "minigame_start_round"), h.gameRpcs().filter { it == "minigame_submit_score" || it == "minigame_start_round" })
    }

    /** 부르는 자리: 앱이 켜지면(GamesStore.appDidBecomeActive — PhoneAppModel.activateStores 가 부른다) 인편이 나간다. */
    @Test
    fun theAppBecomingActivePushesTheRestoredPending() = runTest {
        val prefs = MemoryPrefs()
        leaveOnePendingBehind(prefs)
        val stub = Stub()
        val h = StoreHarness(this, prefs = prefs, route = stub::route)
        h.signIn()
        val store = GamesStore(h.context)
        assertEquals(0, h.server.count("minigame_submit_score"), "전제: 아직 안 나갔다")
        store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(listOf("t1"), h.submitTokens())
        assertNull(prefs.getString(key))
    }

    /** 화면을 여는 것도 방아쇠다 — 선발급보다 먼저 인편이 나간다(반대면 인편의 토큰이 죽는다). */
    @Test
    fun openingTheScreenPushesThePendingBeforeAnyToken() = runTest {
        val prefs = MemoryPrefs()
        leaveOnePendingBehind(prefs)
        val (h, restarted) = make(prefs = prefs)
        restarted.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        assertEquals(listOf("minigame_submit_score", "minigame_start_round"), h.gameRpcs().filter { it == "minigame_submit_score" || it == "minigame_start_round" })
        assertEquals(listOf("t1"), h.submitTokens())
    }

    @Test
    fun aPendingOlderThanTheTokenTtlIsDroppedOnLoadAndToldOnce() = runTest {
        val prefs = MemoryPrefs()
        leaveOnePendingBehind(prefs)
        advanceTimeBy(31 * 60_000L)
        val (h, restarted) = make(prefs = prefs)
        restarted.retryPendingSubmitIfAny()
        advanceUntilIdle()
        assertEquals(emptyList(), restarted.pendingSubmits, "TTL 을 넘긴 인편이 살아 있다")
        assertEquals(0, h.server.count("minigame_submit_score"), "죽은 토큰을 보냈다")
        assertNull(prefs.getString(key), "저장소에 죽은 인편이 남았다")
        assertNull(restarted.submitNotice, "화면이 없는데 안내를 세웠다")
        // 화면을 닫아 둔 사이에 죽은 점수는 다음에 화면을 열 때 **한 번** 말한다.
        restarted.openScreen(MiniGameKind.flappy)
        assertEquals(GamesMiniGameText.submitExpired, restarted.submitNotice)
        restarted.closeScreen(MiniGameKind.flappy)
        restarted.openScreen(MiniGameKind.flappy)
        assertNull(restarted.submitNotice, "두 번 말했다")
    }

    /** 기준선: TTL 안(29분)이면 살아 있다 — 위 시험의 버림이 수명 때문임을 가른다. */
    @Test
    fun aPendingInsideTheTtlIsStillAlive() = runTest {
        val prefs = MemoryPrefs()
        leaveOnePendingBehind(prefs)
        advanceTimeBy(29 * 60_000L)
        val (h, restarted) = make(prefs = prefs)
        restarted.retryPendingSubmitIfAny()
        advanceUntilIdle()
        assertEquals(listOf("t1"), h.submitTokens())
    }

    /** ★ 다른 계정 인편을 제출하지 않는다: 앞 사람의 키에 인편이 있어도 지금 계정은 안 본다 · 앞 사람의 값은 지우지도 않는다 · 나중에 그 사람이 돌아오면 이어서 올린다. */
    @Test
    fun anotherAccountsPendingIsNeverSubmitted() = runTest {
        val prefs = MemoryPrefs()
        leaveOnePendingBehind(prefs)
        val stored = requireNotNull(prefs.getString(key))
        // 그 인편이 앞 사람(OTHER)의 것인 자리 — 지금 로그인은 USER 다.
        val otherKey = GamesMiniGameHub.pendingKey(StoreFixtures.OTHER)
        prefs.remove(key)
        prefs.putString(otherKey, stored)
        val (h, hub) = make(prefs = prefs)
        assertFalse(hub.hasPendingSubmit(MiniGameKind.flappy), "다른 계정 인편이 보인다 — 남의 점수를 내 이름으로 올린다")
        hub.retryPendingSubmitIfAny()
        hub.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        assertEquals(0, h.server.count("minigame_submit_score"), "남의 인편을 제출했다")
        assertEquals(stored, prefs.getString(otherKey), "남의 인편을 지웠다")
    }

    /** 로그아웃: 메모리·타이머는 비우고 영속본은 남긴다 · 떠 있던 응답은 상태를 안 건드린다 · 백오프 타이머가 다음 세션으로 밀지 않는다. */
    @Test
    fun signOutClearsMemoryKeepsTheStoreAndStopsTheTimer() = runTest {
        val stub = Stub()
        val prefs = MemoryPrefs()
        val gate = CompletableDeferred<Unit>()
        stub.submits += Reply.Gate(gate, Stub.ok)
        val (h, hub) = make(stub, prefs)
        hub.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        hub.recordScore(MiniGameKind.flappy, 5)
        runCurrent()
        assertEquals(1, h.server.count("minigame_submit_score"))
        h.sessionStore.signOut()
        runCurrent()
        hub.reset()
        assertEquals(emptyList(), hub.pendingSubmits, "로그아웃했는데 메모리에 앞 사람의 인편이 남았다")
        gate.complete(Unit)
        runCurrent()
        assertNotNull(prefs.getString(key), "늦게 온 응답이 reset 뒤 영속본을 건드렸다(같은 사람이 돌아오면 token_used 로 접힌다)")
        assertEquals(emptyList(), h.achievementRefreshes, "reset 뒤 닿은 응답이 상태를 건드렸다")
        advanceTimeBy(5 * 60_000L)
        runCurrent()
        assertEquals(1, h.server.count("minigame_submit_score"), "로그아웃 뒤에도 타이머가 밀었다")
    }

    /** 토큰을 기다리는 인편들은 순서대로 토큰을 받아 나간다 — 기다리는 인편마다 토큰을 청하면 서로의 토큰을 죽인다. 살아 있는 판 칸으로 가지 않는다. */
    @Test
    fun waitingScoresTakeArrivingTokensInOrder() = runTest {
        val stub = Stub()
        val first = CompletableDeferred<Unit>()
        stub.starts += Reply.Gate(first, Reply.Json("""{"status":"ok","token":"t1"}"""))
        val second = CompletableDeferred<Unit>()
        stub.starts += Reply.Gate(second, Reply.Json("""{"status":"ok","token":"t2"}"""))
        val submitGate = CompletableDeferred<Unit>()
        stub.submits += Reply.Gate(submitGate, Stub.ok)
        val (h, hub) = make(stub)
        hub.beginRound(MiniGameKind.flappy)
        runCurrent()
        assertEquals(1, h.server.count("minigame_start_round"), "전제: 판 시작이 토큰을 청했다")
        hub.recordScore(MiniGameKind.flappy, 4)
        hub.recordScore(MiniGameKind.flappy, 6)
        runCurrent()
        assertEquals(listOf(4, 6), hub.pendingSubmits.map { it.score })
        assertEquals(1, h.server.count("minigame_start_round"), "기다리는 인편마다 토큰을 청했다")
        first.complete(Unit)
        runCurrent()
        assertEquals(listOf(4), h.submitScores(), "도착한 토큰으로 앞 인편이 나가지 않았다")
        assertNull(hub.roundToken, "기다리는 점수가 있는데 토큰이 판 칸으로 갔다")
        assertEquals(1, h.server.count("minigame_start_round"), "앞 인편이 끝나기 전에 뒤 인편의 토큰을 청했다")
        submitGate.complete(Unit)
        runCurrent()
        assertEquals(2, h.server.count("minigame_start_round"), "앞 인편이 끝났는데 뒤 인편의 토큰을 안 청한다")
        second.complete(Unit)
        advanceUntilIdle()
        assertEquals(listOf("t1", "t2"), h.submitTokens())
        assertEquals(listOf(4, 6), h.submitScores())
        assertEquals(emptyList(), hub.pendingSubmits)
    }

    /** 토큰도 왕복도 없이 끝난 판: 인편으로 남고, 토큰 요청이 실패하면 백오프 뒤 다시 청해서 결국 올라간다. */
    @Test
    fun aRoundThatEndsWithNoTokenAndNoRequestInFlightStillGetsUploaded() = runTest {
        val stub = Stub()
        stub.starts += Reply.Offline
        val (h, hub) = make(stub)
        hub.recordScore(MiniGameKind.flappy, 8)
        assertEquals(GamesMiniGameText.submitRetrying, hub.submitNotice, "토큰 없는 판의 문구가 '올리는 중'이 아니다")
        runCurrent()
        assertEquals(1, h.server.count("minigame_start_round"), "기다리는 점수를 위해 토큰을 청하지 않는다")
        advanceTimeBy(1_900)
        runCurrent()
        assertEquals(1, h.server.count("minigame_start_round"), "백오프 전에 다시 청했다")
        advanceUntilIdle()
        assertEquals(listOf(8), h.submitScores(), "도착한 토큰으로 점수가 나가지 않았다")
        assertEquals(emptyList(), hub.pendingSubmits)
        assertNull(hub.submitNotice)
    }

    /** 모르는 status: 점수를 버리지 않되 타이머로 두드리지 않고, 방아쇠에서만 다시 보낸다. 꼬리도 방아쇠가 아니다. */
    @Test
    fun anUnknownStatusKeepsTheScoreButDoesNotHammer() = runTest {
        val stub = Stub()
        stub.submits += Stub.status("banana")
        val (h, hub) = make(stub)
        hub.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        hub.recordScore(MiniGameKind.flappy, 17)
        advanceUntilIdle()
        assertEquals(GamesMiniGameText.submitRetrying, hub.submitNotice)
        assertEquals(listOf("t1"), hub.pendingSubmits.map { it.token }, "모르는 status 에 점수를 버렸다")
        assertEquals(1, h.server.count("minigame_submit_score"), "모르는 status 를 타이머로 두드린다")
        assertEquals(1, h.server.count("minigame_start_round"))
        hub.retryPendingSubmitIfAny(fromTrigger = false)
        advanceUntilIdle()
        assertEquals(1, h.server.count("minigame_submit_score"), "꼬리가 붙든 인편을 풀었다 — 응답이 곧 다음 제출을 부르는 고리다")
        hub.retryPendingSubmitIfAny()
        advanceUntilIdle()
        assertEquals(listOf("t1", "t1"), h.submitTokens(), "방아쇠에서도 다시 안 나간다")
    }

    /** `no_token` 은 점수를 버리지 않고 새 토큰으로 한 번 다시 올린다 — 아직 올릴 수 있는데 못 올렸다고 말하지 않는다. */
    @Test
    fun aDeadTokenIsRecoveredOnceWithAFreshToken() = runTest {
        val stub = Stub()
        stub.submits += Stub.status("no_token")
        val gate = CompletableDeferred<Unit>()
        stub.submits += Reply.Gate(gate, Stub.ok)
        val (h, hub) = make(stub)
        hub.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        hub.recordScore(MiniGameKind.flappy, 13)
        runCurrent()
        assertEquals(listOf("t1", "t2"), h.submitTokens(), "새 토큰으로 다시 보내지 않았다")
        assertEquals(listOf(13, 13), h.submitScores())
        assertEquals(GamesMiniGameText.submitRetrying, hub.submitNotice, "아직 올릴 수 있는데 못 올렸다고 말했다")
        assertTrue(hub.pendingSubmit?.recoveredFromDeadTokenOnce == true)
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(emptyList(), hub.pendingSubmits)
        assertNull(hub.submitNotice, "올라갔는데 문구가 남았다")
    }

    /** 되살리기는 한 번뿐이고 재시작으로 새로 생기지 않는다 — 두 번째 `no_token` 은 인편을 놓아 주고 사실대로 말한다(안 놓으면 그 게임의 선발급이 영영 막힌다). */
    @Test
    fun aDeadTokenIsNotRecoveredTwiceEvenAcrossARestart() = runTest {
        val stub = Stub()
        val prefs = MemoryPrefs()
        stub.submits += Stub.status("no_token")
        stub.submits += Reply.Offline
        val (_, hub) = make(stub, prefs)
        hub.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        hub.recordScore(MiniGameKind.flappy, 9)
        runCurrent()
        assertTrue(hub.pendingSubmit?.recoveredFromDeadTokenOnce == true, "전제: 한 번 되살렸다")
        hub.reset()
        val second = Stub()
        second.submits += Stub.status("no_token")
        val (h2, restarted) = make(second, prefs)
        assertTrue(restarted.hasPendingSubmit(MiniGameKind.flappy))
        assertTrue(restarted.pendingSubmit?.recoveredFromDeadTokenOnce == true, "재시작이 되살리기 기회를 새로 줬다")
        restarted.retryPendingSubmitIfAny()
        advanceUntilIdle()
        assertEquals(1, h2.server.count("minigame_submit_score"))
        assertEquals(emptyList(), restarted.pendingSubmits, "두 번째 no_token 에도 인편을 붙들었다")
        assertEquals(GamesMiniGameText.submitTokenDead, restarted.submitNotice)
    }

    /** 죽자마자 다시 시작해도 앞 판의 토큰이 죽지 않는다(실사용에서 13점을 잃은 순서) · 토큰 없이 시작한 다음 판도 뒤따라 올라간다. */
    @Test
    fun replayingTheInstantYouDieNeverKillsThePreviousRoundsToken() = runTest {
        val stub = Stub()
        val gate = CompletableDeferred<Unit>()
        stub.submits += Reply.Gate(gate, Stub.ok)
        val (h, hub) = make(stub)
        hub.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        hub.recordScore(MiniGameKind.flappy, 13)
        runCurrent()
        hub.beginRound(MiniGameKind.flappy)
        runCurrent()
        assertEquals(1, h.server.count("minigame_start_round"), "제출이 왕복 중인데 start_round 가 나갔다")
        hub.recordScore(MiniGameKind.flappy, 20) // 다음 판도 즉사 — 토큰 없이 끝났다
        runCurrent()
        assertEquals(listOf(13, 20), hub.pendingSubmits.map { it.score })
        assertEquals(1, h.server.count("minigame_start_round"), "앞 인편이 살아 있는데 뒤 인편의 토큰을 청했다")
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(listOf(13, 20), h.submitScores())
        assertEquals(listOf("t1", "t2"), h.submitTokens())
        assertEquals(emptyList(), hub.pendingSubmits)
    }

    /** 깨진 저장값·모르는 게임 줄은 앱을 죽이지 않고 없는 것으로 친다. */
    @Test
    fun aBrokenStoreIsTreatedAsEmpty() = runTest {
        val prefs = MemoryPrefs()
        prefs.putString(key, "not json")
        val (h, hub) = make(prefs = prefs)
        assertFalse(hub.hasPendingSubmit(MiniGameKind.flappy))
        hub.retryPendingSubmitIfAny()
        advanceUntilIdle()
        assertEquals(0, h.server.count("minigame_submit_score"))
    }

    /** 공개를 끈 사람은 인편이 생기지 않는다 · 저장소도 그대로 비어 있다. */
    @Test
    fun aPrivatePlayerLeavesNoPending() = runTest {
        val prefs = MemoryPrefs()
        val h = StoreHarness(this, prefs = prefs) { r ->
            if (r.path == "/rest/v1/profiles" && r.method == "GET") Reply.Json("""[{"minigame_public":false}]""") else Stub().route(r)
        }
        h.signIn()
        val hub = GamesMiniGameHub(h.context)
        hub.openScreen(MiniGameKind.flappy)
        advanceUntilIdle()
        hub.recordScore(MiniGameKind.flappy, 7)
        advanceUntilIdle()
        assertEquals(emptyList(), hub.pendingSubmits)
        assertNull(prefs.getString(key))
    }
}
