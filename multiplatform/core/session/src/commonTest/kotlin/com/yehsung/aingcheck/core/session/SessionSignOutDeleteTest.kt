// 원본: Tests/CheckMobileKitTests/BaseSessionTests.swift:283-346 · BaseSessionHardeningTests.swift:97-238 · MobileSessionStore.swift:238-354 @ 1b8260d
// C§4 #6(scope=local) · #7(로그아웃 순서 · 401 이면 장부 refresh 로 한 번) · #35 + G §2-3 W2-a ⑥(삭제 순서 시나리오).
package com.yehsung.aingcheck.core.session

import com.yehsung.aingcheck.core.session.SessionFixtures.auth
import com.yehsung.aingcheck.core.session.SessionFixtures.jwtExpired
import com.yehsung.aingcheck.core.session.SessionFixtures.membershipOK
import com.yehsung.aingcheck.core.session.SessionFixtures.registerOK
import com.yehsung.aingcheck.core.session.SessionFixtures.releaseOK
import com.yehsung.aingcheck.core.session.signout.SignOutCleanupLedger
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class SessionSignOutDeleteTest {
    private fun base(r: RecordedRequest): Reply? = when {
        r.rpcName == "client_release" -> releaseOK
        r.rpcName == "register_device_fcm" -> registerOK
        r.path == "/rest/v1/memberships" -> membershipOK
        else -> null
    }

    private suspend fun TestScope.signedIn(route: (RecordedRequest) -> Reply?): SessionHarness {
        val h = SessionHarness(this) { r -> route(r) ?: base(r) }
        h.seed(access = "access-0", refresh = "r0")
        h.store.launch()
        advanceUntilIdle()
        assertEquals(SessionPhase.SignedIn, h.store.phase)
        return h
    }

    /**
     * #6·#7: 로그아웃은 세대 +1 → 로컬(금고·사용자 칸·이메일)을 먼저 비우고 → unregister_device → logout?scope=local(옛 토큰) 순서.
     * 로컬이 비는 것은 첫 서버 요청이 나가기 **전**이다(요청 순간의 금고를 잰다).
     */
    @Test
    fun signOutClearsLocalFirstThenUnregistersThenLogsOutLocalScope() = runTest {
        var vaultAtUnregister: String? = "unset"
        var generationAtUnregister = -1
        lateinit var h: SessionHarness
        h = signedIn { r ->
            when {
                r.rpcName == "unregister_device" -> {
                    vaultAtUnregister = h.vaultAccess
                    generationAtUnregister = h.store.generation
                    SessionFixtures.unregistered
                }
                r.path == "/auth/v1/logout" -> SessionFixtures.emptyObject
                else -> null
            }
        }
        var signedOutCalls = 0
        var cleared = 0
        h.store.onSignedOut = { signedOutCalls += 1 }
        h.store.onLocalUserDataCleared = { cleared += 1 }
        val before = h.server.requests.size
        h.store.signOut()
        advanceUntilIdle()
        val after = h.server.requests.drop(before)
        assertEquals(listOf("rpc/unregister_device", "/auth/v1/logout"), after.map { it.rpcName?.let { n -> "rpc/$n" } ?: it.path })
        assertTrue(after.all { it.authorization == "Bearer access-0" }, "캡처한 옛 토큰으로 나간다")
        assertEquals(listOf("local"), after[1].query.filter { it.first == "scope" }.map { it.second }, "logout 은 scope=local(#6)")
        assertTrue(after[0].bodyText.contains(SessionFixtures.INSTALLATION), "이 설치의 행만")
        assertNull(vaultAtUnregister, "첫 서버 요청 전에 금고가 비었다")
        assertEquals(1, generationAtUnregister, "세대가 먼저 올랐다")
        assertEquals(SessionPhase.SignedOut, h.store.phase)
        assertNull(h.store.storedEmail, "스스로 로그아웃하면 이메일도 잊는다")
        assertNull(h.prefs.getString(SessionPrefsKeys.userID))
        assertEquals(1, signedOutCalls)
        assertEquals(1, cleared)
        assertFalse(h.store.hasPendingSignOutCleanup, "다 갚은 장부는 빈다")
        h.assertClean()
    }

    /** #7: access 가 만료(401)면 장부의 refresh 로 **한 번** 갱신해 unregister 를 다시, 새 토큰으로 logout. 회전한 토큰은 곧바로 장부에 쓴다. */
    @Test
    fun expiredAccessAtSignOutRefreshesOnceWithLedgerToken() = runTest {
        val h = signedIn { r ->
            when {
                r.rpcName == "unregister_device" -> if (r.authorization == "Bearer access-0") jwtExpired else SessionFixtures.unregistered
                r.path == "/auth/v1/token" -> auth("cleanup-access", "cleanup-refresh")
                r.path == "/auth/v1/logout" -> if (r.authorization == "Bearer cleanup-access") SessionFixtures.emptyObject else jwtExpired
                else -> null
            }
        }
        val before = h.server.requests.size
        h.store.signOut()
        advanceUntilIdle()
        val after = h.server.requests.drop(before)
        assertEquals(
            listOf("rpc/unregister_device", "/auth/v1/token", "rpc/unregister_device", "/auth/v1/logout"),
            after.map { it.rpcName?.let { n -> "rpc/$n" } ?: it.path },
        )
        assertTrue(after[1].bodyText.contains("\"r0\""), "장부의 refresh token 으로 갱신")
        assertEquals("Bearer cleanup-access", after[3].authorization)
        assertFalse(h.store.hasPendingSignOutCleanup)
        assertNull(h.vaultAccess, "정리 갱신은 스토어 세션·금고에 쓰지 않는다")
        assertEquals(0, h.store.refreshCoordinator.completedRefreshCount, "장부 갱신은 조정자 밖(결과를 세션에 안 쓴다)")
    }

    /** 오프라인 로그아웃은 장부에 남고, 다음 실행에서 옛 토큰으로 unregister → logout?scope=local 을 마친다. */
    @Test
    fun offlineSignOutIsSettledOnNextLaunch() = runTest {
        var online = false
        val h = signedIn { r ->
            when {
                r.rpcName == "unregister_device" -> if (online) SessionFixtures.unregistered else Reply.Offline
                r.path == "/auth/v1/logout" -> if (online) SessionFixtures.emptyObject else Reply.Offline
                else -> null
            }
        }
        h.store.signOut()
        advanceUntilIdle()
        assertTrue(h.store.hasPendingSignOutCleanup, "일시 실패는 장부에 남는다")
        val ledger = SignOutCleanupLedger.load(h.vault)
        assertEquals(listOf("access-0"), ledger.map { it.accessToken })
        online = true
        val before = h.server.requests.size
        h.store.launch()
        advanceUntilIdle()
        val after = h.server.requests.drop(before).map { it.rpcName?.let { n -> "rpc/$n" } ?: it.path }
        assertEquals(listOf("rpc/client_release", "rpc/unregister_device", "/auth/v1/logout"), after)
        assertFalse(h.store.hasPendingSignOutCleanup)
    }

    /** 장부의 갱신이 치명(invalid_grant)이면 빚을 버린다 — 알릴 방법이 없는 세션을 매 실행마다 두드리지 않는다. */
    @Test
    fun fatalCleanupRefreshDropsTheDebt() = runTest {
        val h = signedIn { r ->
            when {
                r.rpcName == "unregister_device" -> jwtExpired
                r.path == "/auth/v1/token" -> SessionFixtures.invalidGrant
                else -> null
            }
        }
        h.store.signOut()
        advanceUntilIdle()
        assertFalse(h.store.hasPendingSignOutCleanup)
        assertEquals(0, h.server.count("/auth/v1/logout"))
    }

    /** #7 "한 번": 갱신한 토큰으로도 401 이면 다시 갱신하지 않고 빚을 버린다(알릴 방법이 없다 — 같은 장부로 갱신을 되풀이하지 않는다). */
    @Test
    fun cleanupRefreshesAtMostOnce() = runTest {
        var refreshes = 0
        val h = signedIn { r ->
            when {
                r.rpcName == "unregister_device" -> jwtExpired
                // 두 번째 갱신 요청이 오면(결함) 치명으로 끊어 무한 반복 대신 수로 드러나게 한다.
                r.path == "/auth/v1/token" -> { refreshes += 1; if (refreshes == 1) auth("c1", "c1r") else SessionFixtures.invalidGrant }
                else -> null
            }
        }
        h.store.signOut()
        advanceUntilIdle()
        assertEquals(1, refreshes, "장부 갱신은 한 번")
        assertEquals(2, h.server.count("/rest/v1/rpc/unregister_device"), "옛 토큰 한 번 + 갱신한 토큰 한 번")
        assertFalse(h.store.hasPendingSignOutCleanup)
    }

    /**
     * ⑥ 삭제 순서: 재인증(저장된 이메일 + 입력 비밀번호, password grant) → 사진 지우기(재인증 토큰) → delete_my_account(재인증 토큰)
     * → 로컬 정리(장부 **없이** — 서버 행은 cascade 로 사라졌다). 기기 해제·logout 요청 0.
     */
    @Test
    fun deleteAccountRunsReauthPhotoRpcThenLocalCleanupWithoutLedger() = runTest {
        val h = signedIn { r ->
            when {
                r.path == "/auth/v1/token" && r.queryValue("grant_type") == "password" -> auth("reauth-access", "reauth-refresh")
                r.method == "DELETE" && r.path.startsWith("/storage/v1/object/avatars/") -> SessionFixtures.emptyObject
                r.path.startsWith("/rest/v1/profiles") -> Reply.Json("[]")
                r.rpcName == "delete_my_account" -> Reply.Json("null")
                else -> null
            }
        }
        var signedOut = 0
        h.store.onSignedOut = { signedOut += 1 }
        val before = h.server.requests.size
        val outcome = h.store.deleteAccount("pw")
        advanceUntilIdle()
        assertEquals(AccountDeletionOutcome.Deleted, outcome)
        val after = h.server.requests.drop(before)
        val token = after.indexOfFirst { it.path == "/auth/v1/token" }
        val rpc = after.indexOfFirst { it.rpcName == "delete_my_account" }
        val photo = after.indexOfFirst { it.path.startsWith("/storage/v1/object/avatars/") }
        assertEquals(0, token, "재인증이 먼저")
        assertTrue(after[0].bodyText.contains("a@b.co") && after[0].bodyText.contains("pw"), "저장된 이메일 + 입력 비밀번호")
        assertTrue(photo in (token + 1) until rpc, "사진이 RPC 보다 먼저: $after")
        assertEquals("Bearer reauth-access", after[rpc].authorization, "새 토큰으로 RPC")
        assertEquals(0, after.count { it.rpcName == "unregister_device" || it.path == "/auth/v1/logout" }, "기기 해제·logout 없음(cascade)")
        assertEquals(SessionPhase.SignedOut, h.store.phase)
        assertEquals(1, h.store.generation)
        assertFalse(h.store.hasPendingSignOutCleanup, "지운 계정의 refresh token 을 장부에 남기지 않는다")
        assertNull(h.vaultRefresh)
        assertEquals(1, signedOut)
        assertFalse(h.store.isDeletingAccount)
        h.assertClean()
    }

    /** 삭제 실패 갈래: 틀린 비밀번호는 RPC 0 · 로그인 그대로 / 서버 준비 안 됨(404)은 재인증 세션을 scope=local 로 닫고 로그인 그대로. */
    @Test
    fun deleteAccountFailuresKeepSignedIn() = runTest {
        val wrong = signedIn { r ->
            if (r.path == "/auth/v1/token") Reply.Json("""{"error":"invalid_grant","error_description":"Invalid login credentials"}""", 400) else null
        }
        assertEquals(AccountDeletionOutcome.Failed(AccountDeletionFailure.WrongPassword), wrong.store.deleteAccount("bad"))
        assertEquals(0, wrong.server.count("/rest/v1/rpc/delete_my_account"))
        assertEquals(SessionPhase.SignedIn, wrong.store.phase)

        val notReady = signedIn { r ->
            when {
                r.path == "/auth/v1/token" -> auth("reauth-access", "reauth-refresh")
                r.path.startsWith("/storage/v1/object/avatars/") -> SessionFixtures.emptyObject
                r.path.startsWith("/rest/v1/profiles") -> Reply.Json("[]")
                r.rpcName == "delete_my_account" -> SessionFixtures.pgrst202
                r.path == "/auth/v1/logout" -> SessionFixtures.emptyObject
                else -> null
            }
        }
        assertEquals(AccountDeletionOutcome.Failed(AccountDeletionFailure.ServerNotReady), notReady.store.deleteAccount("pw"))
        val logout = notReady.server.requests.single { it.path == "/auth/v1/logout" }
        assertEquals("Bearer reauth-access", logout.authorization, "재인증 세션만 닫는다")
        assertEquals(SessionPhase.SignedIn, notReady.store.phase)
        assertEquals("access-0", notReady.vaultAccess, "로그인 세션은 그대로")

        assertEquals(AccountDeletionOutcome.Failed(AccountDeletionFailure.PasswordRequired), notReady.store.deleteAccount(""))
    }
}
