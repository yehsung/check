// 원본: Tests/CheckMobileKitTests/BaseSessionTests.swift:192-282·348-368 · BaseSessionHardeningTests.swift:319-358 @ 1b8260d
// (갱신을 띄운 호출의 취소 갈래 두 시험은 원본 없음 — Swift Task.value 는 부른 쪽 취소에 돌아오지 않아 그 창이 없다. W2-a 6차 검증 지적.)
// G §2-3 W2-a ②(동시 갱신 N → 요청 1) · ③(세대 가드) · ④(5xx·429 세션 유지) · C§4 #3·#4.
package com.yehsung.aingcheck.core.session

import com.yehsung.aingcheck.core.net.fetchMyInviteCode
import com.yehsung.aingcheck.core.session.SessionFixtures.auth
import com.yehsung.aingcheck.core.session.SessionFixtures.jwtExpired
import com.yehsung.aingcheck.core.session.SessionFixtures.membershipOK
import com.yehsung.aingcheck.core.session.SessionFixtures.registerOK
import com.yehsung.aingcheck.core.session.SessionFixtures.releaseOK
import com.yehsung.aingcheck.core.session.refresh.SessionRefreshCoordinator
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class SessionRefreshTest {
    /** 조정자 단위 시험의 스코프: 시험 디스패처 위 SupervisorJob(앱의 세션 스토어 스코프와 같은 모양 — 실패한 갱신이 형제를 죽이지 않는다). */
    private fun kotlinx.coroutines.test.TestScope.supervisorScope(): kotlinx.coroutines.CoroutineScope {
        val job = kotlinx.coroutines.SupervisorJob()
        backgroundScope.coroutineContext[kotlinx.coroutines.Job]!!.invokeOnCompletion { job.cancel() }
        return kotlinx.coroutines.CoroutineScope(coroutineContext.minusKey(kotlinx.coroutines.Job) + job)
    }

    /** 실행 복원으로 로그인한 하네스(만료가 먼 토큰 — 실행 직후 갱신 없음). [invite] 가 my_team_invite_code 응답을 고른다. */
    private suspend fun kotlinx.coroutines.test.TestScope.signedIn(
        access: String = "access-0",
        refresh: (RecordedRequest) -> Reply,
        invite: (RecordedRequest) -> Reply,
    ): SessionHarness {
        val h = SessionHarness(this) { r ->
            when {
                r.rpcName == "client_release" -> releaseOK
                r.rpcName == "register_device_fcm" -> registerOK
                r.path == "/rest/v1/memberships" -> membershipOK
                r.path == "/auth/v1/token" -> refresh(r)
                r.rpcName == "my_team_invite_code" -> invite(r)
                r.rpcName == "unregister_device" -> SessionFixtures.unregistered
                r.path == "/auth/v1/logout" -> SessionFixtures.emptyObject
                else -> null
            }
        }
        h.seed(access = access, refresh = "r0")
        h.store.launch()
        advanceUntilIdle()
        assertEquals(SessionPhase.SignedIn, h.store.phase)
        return h
    }

    /** ② 동시 401 다섯 → 갱신 요청 **1** · 다섯 모두 새 토큰으로 재시도 · 조정자 통과 1. */
    @Test
    fun concurrentExpiredCallsShareOneRefresh() = runTest {
        val gate = CompletableDeferred<Unit>()
        val h = signedIn(
            refresh = { Reply.Gate(gate, auth("access-1", "r1")) },
            invite = { r -> if (r.authorization == "Bearer access-1") Reply.Json("""[{"invite_code":"ABC123"}]""") else jwtExpired },
        )
        val calls = (1..5).map {
            async { h.store.withSessionRetry { s -> h.store.service.fetchMyInviteCode(s.accessToken) } }
        }
        runCurrent()
        assertEquals(1, h.server.count("/auth/v1/token"), "문이 닫힌 동안 갱신 요청은 하나")
        gate.complete(Unit)
        val codes = calls.awaitAll()
        assertEquals(List(5) { "ABC123" }, codes)
        assertEquals(1, h.server.count("/auth/v1/token"), "끝까지 하나")
        assertEquals(1, h.store.refreshCoordinator.completedRefreshCount)
        assertEquals(10, h.server.count("/rest/v1/rpc/my_team_invite_code"), "다섯 번 401 + 다섯 번 재시도")
        assertEquals("access-1", h.vaultAccess)
        assertEquals("r1", h.vaultRefresh)
        h.assertClean()
    }

    /** 조정자 ①: refresh token 은 **호출 시점에** 읽는다 — 앞선 갱신이 끝난 뒤의 순차 호출은 회전된 새 토큰을 쓴다. */
    @Test
    fun sequentialRefreshReadsRotatedTokenAtCallTime() = runTest {
        var n = 0
        val h = signedIn(
            refresh = { n += 1; auth("access-$n", "r$n") },
            invite = { r -> if (r.authorization == "Bearer access-0") jwtExpired else Reply.Json("""[{"invite_code":"X"}]""") },
        )
        h.store.withSessionRetry { s -> h.store.service.fetchMyInviteCode(s.accessToken) }
        assertEquals("r1", h.vaultRefresh)
        val first = h.server.requests.filter { it.path == "/auth/v1/token" }
        assertTrue(first.single().bodyText.contains("\"r0\""))
        // 두 번째 갱신(실시간 강제 갱신)은 r1 로 간다 — r0 을 다시 쓰면 GoTrue 재사용 감지가 터진다.
        val result = h.store.refreshForRealtime()
        assertEquals(RealtimeRefreshResult.Refreshed("access-2"), result)
        val grants = h.server.requests.filter { it.path == "/auth/v1/token" }.map { it.bodyText }
        assertEquals(2, grants.size)
        assertTrue(grants[1].contains("\"r1\""), "두 번째 갱신은 회전된 토큰: ${grants[1]}")
    }

    /** 조정자 단위: 같은 세대는 합류, 다른 세대는 합류하지 않는다(앞 계정의 결과를 새 계정에 쓰지 않게). */
    @Test
    fun coordinatorJoinsOnlyWithinGeneration() = runTest {
        val coordinator = SessionRefreshCoordinator(supervisorScope())
        val gate = CompletableDeferred<Unit>()
        var calls = 0
        val applied = mutableListOf<String>()
        suspend fun refresh(generation: Int, token: String) = coordinator.refresh(
            generation, { token },
            { t -> calls += 1; gate.await(); SupabaseSession("a-$t", "n-$t", "u") },
            { applied += it.accessToken },
        )
        val a = async { refresh(0, "x") }
        val b = async { refresh(0, "y") }
        val c = async { refresh(1, "z") }
        runCurrent()
        gate.complete(Unit)
        assertEquals("a-x", a.await().accessToken)
        assertEquals("a-x", b.await().accessToken, "같은 세대는 앞 갱신에 합류(토큰 y 를 읽지도 않는다)")
        assertEquals("a-z", c.await().accessToken, "다른 세대는 따로")
        assertEquals(2, calls)
        assertEquals(listOf("a-x", "a-z"), applied, "apply 는 갱신마다 정확히 한 번")
        assertEquals(2, coordinator.completedRefreshCount)
        assertEquals(false, coordinator.hasInFlight, "끝나면 슬롯이 빈다")
        // 토큰이 없으면 요청 없이 sessionExpired.
        assertFailsWith<SupabaseWorkServiceError.SessionExpired> { coordinator.refresh(2, { null }, { error("부르면 안 된다") }, {}) }
    }

    /**
     * ② 취소 갈래(Swift `try await task.value` 의미): 갱신을 **띄운** 호출이 취소돼도 갱신은 떠 있고 슬롯도 그 끝까지 남는다 —
     * 같은 세대의 다음 호출은 합류한다(회전 전 r0 으로 두 번째 grant 금지). 갱신이 끝나면 슬롯이 비어, 그 뒤 호출은 회전된 r1 으로 새로 간다.
     * 대조: 취소 없는 동시 호출은 [concurrentExpiredCallsShareOneRefresh] 가 잰다.
     */
    @Test
    fun creatorCancellationKeepsTheSlotUntilTheRefreshEnds() = runTest {
        val coordinator = SessionRefreshCoordinator(supervisorScope())
        val gate = CompletableDeferred<Unit>()
        var token = "r0"
        val used = mutableListOf<String>()
        val applied = mutableListOf<String>()
        var n = 0
        suspend fun refresh() = coordinator.refresh(
            0, { token },
            { t -> used += t; n += 1; val k = n; gate.await(); SupabaseSession("a$k", "r$k", "u") },
            { s -> applied += s.accessToken; token = s.refreshToken!! },
        )
        val creator = launch { refresh() }
        runCurrent()
        assertEquals(listOf("r0"), used)
        creator.cancel() // 화면을 떠났다(viewModelScope 취소)
        runCurrent()
        assertTrue(creator.isCancelled)
        assertTrue(coordinator.hasInFlight, "띄운 호출이 취소돼도 갱신은 떠 있다 — 슬롯을 비우면 다음 호출이 r0 을 다시 쓴다")
        val joiner = async { refresh() }
        runCurrent()
        assertEquals(listOf("r0"), used, "같은 세대의 다음 호출은 떠 있는 갱신에 합류한다")
        gate.complete(Unit)
        assertEquals("a1", joiner.await().accessToken)
        assertEquals(listOf("a1"), applied, "apply 는 정확히 한 번(띄운 호출이 취소돼도 갱신 자신이 쓴다)")
        assertEquals(1, coordinator.completedRefreshCount)
        assertEquals(false, coordinator.hasInFlight, "갱신이 끝나면 슬롯이 빈다")
        // 끝난 뒤의 호출은 끝난 갱신에 붙지 않고 회전된 토큰으로 새로 간다.
        assertEquals("a2", refresh().accessToken)
        assertEquals(listOf("r0", "r1"), used)
    }

    /**
     * 같은 결함의 세션 스토어 경로: 화면 코루틴의 401 재시도가 갱신을 띄운 뒤 취소되고, 이어 실시간 강제 갱신이 온다 →
     * grant 는 **하나**(r0), 실시간 쪽은 그 결과(access-1)를 받는다. 금고는 회전된 r1.
     */
    @Test
    fun cancelledScreenRetryLeavesRealtimeRefreshJoinedToTheSameGrant() = runTest {
        val gate = CompletableDeferred<Unit>()
        var n = 0
        val h = signedIn(
            refresh = { n += 1; Reply.Gate(gate, auth("access-$n", "r$n")) },
            invite = { r -> if (r.authorization == "Bearer access-0") jwtExpired else Reply.Json("""[{"invite_code":"X"}]""") },
        )
        val screen = launch { h.store.withSessionRetry { s -> h.store.service.fetchMyInviteCode(s.accessToken) } }
        runCurrent()
        assertEquals(1, h.server.count("/auth/v1/token"), "401 → 갱신 하나가 떴다")
        screen.cancel()
        runCurrent()
        val realtime = async { h.store.refreshForRealtime() }
        runCurrent()
        gate.complete(Unit)
        assertEquals(RealtimeRefreshResult.Refreshed("access-1"), realtime.await())
        val grants = h.server.requests.filter { it.path == "/auth/v1/token" }.map { it.bodyText }
        assertEquals(1, grants.size, "갱신 grant 는 하나여야 한다 — 실제: $grants")
        assertTrue(grants.single().contains("\"r0\""))
        assertEquals(1, h.store.refreshCoordinator.completedRefreshCount)
        assertEquals("r1", h.vaultRefresh)
        assertEquals(SessionPhase.SignedIn, h.store.phase)
    }

    /** 실패한 갱신 뒤에도 슬롯이 비어 다음 호출이 새로 갱신한다(성공·실패 두 갈래 모두 명시적으로 비운다 — INV af534e47). */
    @Test
    fun failedRefreshClearsSlotForNextCall() = runTest {
        val coordinator = SessionRefreshCoordinator(supervisorScope())
        var calls = 0
        assertFailsWith<SupabaseWorkServiceError.InvalidResponse> {
            coordinator.refresh(0, { "t" }, { calls += 1; throw SupabaseWorkServiceError.InvalidResponse(503) }, {})
        }
        assertEquals(false, coordinator.hasInFlight)
        val ok = coordinator.refresh(0, { "t" }, { calls += 1; SupabaseSession("ok", null, "u") }, {})
        assertEquals("ok", ok.accessToken)
        assertEquals(2, calls)
    }

    /**
     * ③ 세대 가드: 갱신이 떠 있는 동안 로그아웃 → 다른 계정으로 로그인 → 늦게 온 옛 갱신 결과는 **새 계정에 쓰이지 않는다**
     * (세션 · 금고 · 토큰 변경 알림 모두). 대조: 같은 응답이 로그아웃 없이 오면 그대로 쓴다(위 시험들).
     */
    @Test
    fun lateRefreshFromSignedOutAccountNeverReachesNewAccount() = runTest {
        val gate = CompletableDeferred<Unit>()
        val tokenChanges = mutableListOf<String>()
        val h = signedIn(
            refresh = { r ->
                if (r.queryValue("grant_type") == "password") auth("user2-access", "user2-refresh", "user-2")
                else Reply.Gate(gate, auth("stale-access", "stale-refresh", "user-1"))
            },
            invite = { jwtExpired },
        )
        h.store.onAccessTokenChanged = { tokenChanges += it }
        // logout 서버 정리 경로도 받아 준다.
        val realtime = async { h.store.refreshForRealtime() }
        runCurrent()
        assertTrue(h.store.refreshCoordinator.hasInFlight)
        launch { h.store.signOut() }
        runCurrent()
        h.store.signIn("b@c.co", "pw2")
        // 가상 시간을 움직이지 않는다(runCurrent 만): advanceUntilIdle 이면 문이 닫힌 옛 갱신이 HttpTimeout(30초)에 죽어
        // apply 까지 가지 못하고, 세대 가드를 빼도 이 시험이 초록이 된다(결함 심기 M2 실측).
        runCurrent()
        assertEquals("user-2", h.store.userID)
        assertEquals(0, h.store.refreshCoordinator.completedRefreshCount)
        gate.complete(Unit)
        assertEquals(RealtimeRefreshResult.Failed.Stale, realtime.await(), "옛 세대의 결과는 stale")
        assertEquals(1, h.store.refreshCoordinator.completedRefreshCount, "옛 갱신은 실제로 성공해 apply 까지 갔다 — 거기서 세대 가드가 막았다")
        runCurrent()
        assertEquals("user2-access", h.store.session?.accessToken)
        assertEquals("user2-access", h.vaultAccess)
        assertEquals("user2-refresh", h.vaultRefresh)
        assertEquals(emptyList(), tokenChanges, "옛 갱신이 새 세션의 소켓에 토큰을 밀지 않는다")
    }

    /** ④: 401 뒤 갱신이 일시(503 · 429 · 오프라인)면 세션을 유지하고 **원래 오류**(sessionExpired)를 던진다. 치명이면 로그아웃(세대 +1). */
    @Test
    fun retryRefreshTransientKeepsSessionFatalExpires() = runTest {
        for ((name, failure) in listOf("503" to SessionFixtures.serverDown, "429" to SessionFixtures.rateLimited, "offline" to Reply.Offline)) {
            val h = signedIn(refresh = { failure }, invite = { jwtExpired })
            val error = assertFailsWith<SupabaseWorkServiceError> {
                h.store.withSessionRetry { s -> h.store.service.fetchMyInviteCode(s.accessToken) }
            }
            assertEquals(SupabaseWorkServiceError.SessionExpired, error, name)
            assertEquals(SessionPhase.SignedIn, h.store.phase, "$name: 세션 유지")
            assertEquals(0, h.store.generation, name)
            assertEquals("access-0", h.vaultAccess, name)
        }
        val fatal = signedIn(refresh = { SessionFixtures.invalidGrant }, invite = { jwtExpired })
        assertFailsWith<SupabaseWorkServiceError> {
            fatal.store.withSessionRetry { s -> fatal.store.service.fetchMyInviteCode(s.accessToken) }
        }
        assertEquals(SessionPhase.SignedOut, fatal.store.phase)
        assertEquals(1, fatal.store.generation)
        assertNull(fatal.vaultAccess)
        assertEquals(SessionText.signInAgain, fatal.store.notice)
    }

    /** 일시 오류가 401 이 아니면 갱신하지 않는다 — 5xx 는 그대로 던지고 세션·세대 그대로. */
    @Test
    fun serverErrorWithoutExpiryNeverRefreshes() = runTest {
        val h = signedIn(refresh = { error("갱신하면 안 된다") }, invite = { SessionFixtures.serverDown })
        assertFailsWith<SupabaseWorkServiceError.InvalidResponse> {
            h.store.withSessionRetry { s -> h.store.service.fetchMyInviteCode(s.accessToken) }
        }
        assertEquals(0, h.server.count("/auth/v1/token"))
        assertEquals(SessionPhase.SignedIn, h.store.phase)
    }

    /** C§4 #1: 회전한 토큰을 금고가 못 쓰면 **낡은 토큰이 아니라 없음**이 남고, 다음 실행은 로그아웃 상태다(재사용 감지 사고 대신 재로그인). */
    @Test
    fun vaultWriteFailureLeavesNoStaleTokens() = runTest {
        var n = 0
        val h = signedIn(refresh = { n += 1; auth("access-$n", "r$n") }, invite = { r ->
            if (r.authorization == "Bearer access-0") jwtExpired else Reply.Json("""[{"invite_code":"X"}]""")
        })
        h.vault.failsWrites = true
        h.store.withSessionRetry { s -> h.store.service.fetchMyInviteCode(s.accessToken) }
        assertNull(h.vaultRefresh, "쓰기 실패 ⇒ 읽기 null(낡은 r0 이 남으면 안 된다)")
        assertNull(h.vaultAccess)
        // 다음 실행(같은 금고·설정)은 복원할 것이 없다.
        val next = SessionHarness(this, vault = h.vault, prefs = h.prefs) { r -> if (r.rpcName == "client_release") releaseOK else null }
        next.store.launch()
        assertEquals(SessionPhase.SignedOut, next.store.phase)
        assertEquals("user-1", h.prefs.getString(SessionPrefsKeys.userID), "설정은 그대로인데 금고가 비어 복원하지 않는다")
    }
}
