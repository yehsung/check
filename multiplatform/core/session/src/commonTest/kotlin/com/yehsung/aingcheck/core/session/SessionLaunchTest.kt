// 원본: Tests/CheckMobileKitTests/BaseSessionTests.swift:83-190 · BaseSessionHardeningTests.swift:360-400 @ 1b8260d
// G §2-3 W2-a ⑤(client_release 3초 상한 · unknown_platform·서버 준비 안 됨 통과) · ④ · ⑦(단일 실행 가드) · C§4 #34 · #40.
package com.yehsung.aingcheck.core.session

import com.yehsung.aingcheck.core.session.SessionFixtures.auth
import com.yehsung.aingcheck.core.session.SessionFixtures.membershipOK
import com.yehsung.aingcheck.core.session.SessionFixtures.registerOK
import com.yehsung.aingcheck.core.session.SessionFixtures.releaseOK
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class SessionLaunchTest {
    private fun signedInRoutes(release: Reply = releaseOK): (com.yehsung.aingcheck.testkit.mock.RecordedRequest) -> Reply? = { r ->
        when {
            r.rpcName == "client_release" -> release
            r.rpcName == "register_device_fcm" -> registerOK
            r.path == "/rest/v1/memberships" -> membershipOK
            else -> null
        }
    }

    @Test
    fun launchRestoresSessionReadsMembershipAndRegistersOnce() = runTest {
        val h = SessionHarness(this, route = signedInRoutes())
        h.seed(access = h.jwtIn(3600.0, "a"), refresh = "r0")
        h.store.launch()
        advanceUntilIdle()
        assertEquals(SessionPhase.SignedIn, h.store.phase)
        assertEquals("테스트팀", h.store.profile?.teamName)
        assertEquals(1, h.server.count("/rest/v1/rpc/register_device_fcm"), "기기 등록 한 번")
        assertEquals(0, h.server.count("/auth/v1/token"), "만료가 먼 토큰은 갱신하지 않는다")
        // client_release 는 anon 으로, 플랫폼은 앱 정보에서 주입(C§3.2 C-2 — iOS 의 "ios" 상수 자리).
        val release = h.server.requests.first { it.rpcName == "client_release" }
        assertEquals("Bearer ${StubServer.STUB_ANON}", release.authorization)
        assertEquals("android", (SwiftJson.parse(release.bodyText) as JsonObject)["p_platform"]!!.jsonPrimitive.content)
        assertFalse(h.server.requests.any { it.path.startsWith("/rest/v1/profiles") }, "app_build PATCH 없음")
        h.assertClean()
    }

    @Test
    fun buildBelowServerMinimumStopsAtUpdateWithoutTouchingAuth() = runTest {
        val h = SessionHarness(this, route = signedInRoutes(Reply.Json("""{"status":"ok","platform":"android","min_build":5,"latest_build":7}""")))
        h.seed(access = h.jwtIn(3600.0, "a"), refresh = "r0")
        h.store.launch()
        advanceUntilIdle()
        assertEquals(SessionPhase.NeedsUpdate(5), h.store.phase)
        assertEquals(7L, h.store.latestBuild)
        assertEquals(listOf("rpc/client_release"), h.server.paths(), "복원·인증 요청 0")
        assertEquals(listOf(SessionVaultKeys.signOutCleanup), h.vault.readKeys, "토큰 칸은 열지 않는다(장부만 — 못 한 로그아웃 정리)")
    }

    /** ⑤: `unknown_platform`(서버 ① 전 Android) · 함수 없음(404 PGRST202) · 오프라인 · 500 은 막지 않는다. 대조: 최소 빌드와 같으면 통과. */
    @Test
    fun unknownPlatformAndServerNotReadyDoNotBlock() = runTest {
        val cases = listOf(
            "unknown_platform" to Reply.Json("""{"status":"unknown_platform"}"""),
            "pgrst202" to SessionFixtures.pgrst202,
            "offline" to Reply.Offline,
            "500" to Reply.Json("""{"message":"boom"}""", 500),
            "minEqual" to Reply.Json("""{"status":"ok","platform":"android","min_build":1,"latest_build":1}"""),
        )
        for ((name, release) in cases) {
            val h = SessionHarness(this, route = signedInRoutes(release))
            h.seed(access = h.jwtIn(3600.0, "a"), refresh = "r0")
            h.store.launch()
            advanceUntilIdle()
            assertEquals(SessionPhase.SignedIn, h.store.phase, name)
            h.assertClean()
        }
    }

    /**
     * ⑤ 3초 상한(가상 시간): 응답이 없으면 정확히 3초에 '모름'으로 접고 복원으로 넘어간다 — 그 사이 금고는 열리지 않는다.
     * 대조(같은 응답, 2.9초에 도착): 최소 빌드가 높으면 여전히 막는다. 기준선이 다른 입력이다(도착 시각만 다르다).
     */
    @Test
    fun clientReleaseWaitsAtMostThreeSeconds() = runTest {
        val blocking = """{"status":"ok","platform":"android","min_build":9,"latest_build":9}"""
        // (가) 응답 없음 → 3초에 복원.
        val hung = SessionHarness(this, route = signedInRoutes(Reply.Hang))
        hung.seed(access = hung.jwtIn(3600.0, "a"), refresh = "r0")
        val job = launch { hung.store.launch() }
        advanceTimeBy(2_999)
        runCurrent()
        assertEquals(SessionPhase.Launching, hung.store.phase, "2.999초엔 아직 기다린다")
        assertTrue(SessionVaultKeys.accessToken !in hung.vault.readKeys, "기다리는 동안 금고 복원 없음")
        advanceTimeBy(2)
        runCurrent()
        assertEquals(SessionPhase.SignedIn, hung.store.phase, "3초에 '모름'으로 접고 복원")
        job.join()

        // (나) 같은 막는 응답이 2.9초에 오면 막는다.
        val gate = CompletableDeferred<Unit>()
        val slow = SessionHarness(this, route = signedInRoutes(Reply.Gate(gate, Reply.Json(blocking))))
        slow.seed(access = slow.jwtIn(3600.0, "a"), refresh = "r0")
        val job2 = launch { slow.store.launch() }
        advanceTimeBy(2_900)
        gate.complete(Unit)
        runCurrent()
        job2.join()
        assertEquals(SessionPhase.NeedsUpdate(9), slow.store.phase)

        // (다) 같은 막는 응답이 3.1초에 오면 늦었다 — 이미 복원했다(업데이트 화면으로 뒤집지 않는다).
        val lateGate = CompletableDeferred<Unit>()
        val late = SessionHarness(this, route = signedInRoutes(Reply.Gate(lateGate, Reply.Json(blocking))))
        late.seed(access = late.jwtIn(3600.0, "a"), refresh = "r0")
        val job3 = launch { late.store.launch() }
        advanceTimeBy(3_100)
        lateGate.complete(Unit)
        runCurrent()
        job3.join()
        advanceUntilIdle()
        assertEquals(SessionPhase.SignedIn, late.store.phase)
    }

    @Test
    fun noStoredTokensMeansSignedOut() = runTest {
        val h = SessionHarness(this, route = signedInRoutes())
        h.store.launch()
        assertEquals(SessionPhase.SignedOut, h.store.phase)
        assertEquals(listOf("rpc/client_release"), h.server.paths())
    }

    @Test
    fun nearlyExpiredTokenRefreshesOnceThroughCoordinatorAndPersists() = runTest {
        val fresh = "fresh-access"
        val h = SessionHarness(this) { r ->
            when {
                r.path == "/auth/v1/token" -> auth(fresh, "r1")
                else -> signedInRoutes()(r)
            }
        }
        h.seed(access = h.jwtIn(30.0, "old"), refresh = "r0")
        h.store.launch()
        advanceUntilIdle()
        assertEquals(SessionPhase.SignedIn, h.store.phase)
        assertEquals(1, h.server.count("/auth/v1/token"))
        assertEquals(1, h.store.refreshCoordinator.completedRefreshCount, "조정자를 통과했다")
        assertEquals(fresh, h.vaultAccess)
        assertEquals("r1", h.vaultRefresh)
        val grant = h.server.requests.first { it.path == "/auth/v1/token" }
        assertEquals("refresh_token", grant.queryValue("grant_type"))
        assertTrue(grant.bodyText.contains("\"r0\""), "금고의 refresh token 으로 갱신")
    }

    /** ④ · C§4 #40: 실행 직후 갱신이 일시(503 · 429 · 오프라인)면 세션 유지, 치명(invalid_grant)이면 로그아웃(세대 +1). */
    @Test
    fun launchRefreshTransientKeepsSessionFatalSignsOut() = runTest {
        val transient = listOf("503" to SessionFixtures.serverDown, "429" to SessionFixtures.rateLimited, "offline" to Reply.Offline)
        for ((name, failure) in transient) {
            val h = SessionHarness(this) { r -> if (r.path == "/auth/v1/token") failure else signedInRoutes()(r) }
            h.seed(access = h.jwtIn(10.0, "old"), refresh = "r0")
            h.store.launch()
            advanceUntilIdle()
            assertEquals(SessionPhase.SignedIn, h.store.phase, "$name: 세션 유지(비행기 모드로 켠 폰이 로그아웃되지 않는다)")
            assertEquals(0, h.store.generation, name)
            assertEquals("r0", h.vaultRefresh, name)
        }
        val fatal = SessionHarness(this) { r -> if (r.path == "/auth/v1/token") SessionFixtures.invalidGrant else signedInRoutes()(r) }
        fatal.seed(access = fatal.jwtIn(10.0, "old"), refresh = "r0")
        fatal.store.launch()
        advanceUntilIdle()
        assertEquals(SessionPhase.SignedOut, fatal.store.phase)
        assertEquals(1, fatal.store.generation)
        assertNull(fatal.vaultAccess)
        assertNull(fatal.vaultRefresh)
        assertEquals("a@b.co", fatal.store.storedEmail, "치명 만료는 같은 사람이 다시 들어온다 — 이메일은 남긴다")
    }

    /**
     * ⑦ 단일 실행 가드: 가드를 못 잡으면 세션을 시작하지 않는다 — 요청 0 · 금고 읽기 0 · 단계 AnotherInstanceRunning.
     * 로그인 시도도 거부한다. 대조: 가드를 잡으면 같은 금고로 복원한다.
     */
    @Test
    fun refusesToStartWithoutSingleInstanceGuard() = runTest {
        val h = SessionHarness(this, grants = false, route = signedInRoutes())
        h.seed(access = h.jwtIn(3600.0, "a"), refresh = "r0")
        h.store.launch()
        advanceUntilIdle()
        assertEquals(SessionPhase.AnotherInstanceRunning, h.store.phase)
        assertEquals(SessionText.anotherInstanceRunning, h.store.notice)
        assertEquals(emptyList(), h.server.paths(), "요청 0")
        assertEquals(0, h.vault.reads, "금고를 열지 않는다")
        h.store.signIn("a@b.co", "pw")
        advanceUntilIdle()
        assertEquals(emptyList(), h.server.paths(), "로그인도 거부")
        assertNull(h.store.session)

        val ok = SessionHarness(this, grants = true, route = signedInRoutes())
        ok.seed(access = ok.jwtIn(3600.0, "a"), refresh = "r0")
        ok.store.launch()
        advanceUntilIdle()
        assertEquals(SessionPhase.SignedIn, ok.store.phase)
        assertEquals(1, ok.guard.acquires)
        ok.store.releaseInstance()
        assertEquals(1, ok.guard.releases)
    }
}
