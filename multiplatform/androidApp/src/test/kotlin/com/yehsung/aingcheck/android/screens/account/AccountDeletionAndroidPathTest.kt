// 원본: Tests/CheckMobileKitTests/MeAccountDeletionTests.swift @ 3bd04bd (순서 계약 · 실패면 로컬 그대로 · 소스 계약 — 삭제를 부르는 화면은 하나)
//
// ④ 계정 삭제 순서(Android 경로). 사건 기록기 하나에 서버 요청과 이 기기 정리를 차례로 적는다:
//   재인증(/auth/v1/token password) → 사진(DELETE storage) → delete_my_account(재인증 토큰) → 세션 로컬 정리(onLocalUserDataCleared)
//   → [Android] 알림 서랍 비우기 → FCM 토큰 지우기 → 위젯 다시 그리기.
// 실패(틀린 비밀번호 · RPC 404/5xx)면 RPC 뒤 단계가 하나도 없고 로그인 상태 그대로다(Android 정리 0 — 살아 있는 계정의 알림을 끊지 않는다).
package com.yehsung.aingcheck.android.screens.account

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionPrefsKeys
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.SessionVaultKeys
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.stores.me.DrawableCharacterSource
import com.yehsung.aingcheck.core.stores.me.MeContext
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockEngineConfig
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.job
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

@OptIn(ExperimentalCoroutinesApi::class)
class AccountDeletionAndroidPathTest {
    private val me = "d0000000-0000-4000-8000-000000000001"
    private val rightPassword = "correct-horse"

    private class Prefs : KeyValueStore {
        val values = HashMap<String, Any>()
        override fun getString(key: String): String? = values[key] as? String
        override fun putString(key: String, value: String) { values[key] = value }
        override fun getLong(key: String): Long? = values[key] as? Long
        override fun putLong(key: String, value: Long) { values[key] = value }
        override fun getBoolean(key: String): Boolean? = values[key] as? Boolean
        override fun putBoolean(key: String, value: Boolean) { values[key] = value }
        override fun remove(key: String) { values.remove(key) }
    }

    private inner class Harness(scope: TestScope, private val rpcStatus: Int = 200) {
        val events = mutableListOf<String>()
        val prefs = Prefs()
        val vault = InMemoryTokenVault()
        private val job = SupervisorJob()
        private val storeScope = CoroutineScope(scope.coroutineContext.minusKey(Job) + job)
        private val engine = MockEngine(
            MockEngineConfig().apply {
                dispatcher = StandardTestDispatcher(scope.testScheduler)
                addHandler { request ->
                    val path = request.url.encodedPath
                    val body = (request.body as? OutgoingContent.ByteArrayContent)?.bytes()?.decodeToString() ?: ""
                    val bearer = request.headers[HttpHeaders.Authorization]?.removePrefix("Bearer ")
                    fun json(text: String, status: Int = 200) = respond(text, HttpStatusCode.fromValue(status), headersOf(HttpHeaders.ContentType, "application/json"))
                    when {
                        path == "/auth/v1/token" -> {
                            events += "reauth"
                            if (body.contains("\"$rightPassword\"")) json("""{"access_token":"fresh-access","refresh_token":"fresh-refresh","user":{"id":"$me"}}""")
                            else json("""{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}""", 400)
                        }
                        path.startsWith("/storage/v1/object/avatars/") && request.method.value == "DELETE" -> {
                            events += "avatar:$bearer"
                            json("{}")
                        }
                        path == "/rest/v1/rpc/delete_my_account" -> {
                            events += "rpc:delete_my_account:$bearer"
                            if (rpcStatus == 200) json("null") else json("""{"code":"PGRST202","message":"x"}""", rpcStatus)
                        }
                        path == "/auth/v1/logout" -> {
                            events += "logout:$bearer"
                            json("{}", 204)
                        }
                        path == "/rest/v1/memberships" -> json("[]")
                        path == "/rest/v1/rpc/register_device_fcm" -> json("""{"status":"ok","device_id":"d","push_prefs":{"message":true,"gomoku_invite":true,"feedback_reply":true}}""")
                        else -> json("""{"message":"unrouted $path"}""", 418).also { events += "unrouted:$path" }
                    }
                }
            },
        )
        val service = SupabaseWorkService(
            projectURL = "https://golden.invalid",
            anonKey = "stub-anon-key",
            client = HttpClient(engine) { SupabaseWorkService.clientConfig(this) },
            clock = { SessionClock.demoInstant },
            text = RulesWireTextRules,
            newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
        )
        val session = SessionStore(
            service = service,
            vault = vault,
            prefs = prefs,
            appInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 16"),
            installationIdentity = object : InstallationIdentity {
                override fun installationId(): String = "11111111-2222-4333-8444-555555555555"
            },
            clock = SessionClock.fixed(SessionClock.demoInstant),
            instanceGuard = object : SingleInstanceGuard {
                override fun tryAcquire(): Boolean = true
                override fun release() {}
            },
            parentScope = storeScope,
        )
        val store = MeStore(MeContext(session), storeScope, DrawableCharacterSource.of(setOf("aing")), StandardTestDispatcher(scope.testScheduler))

        /** Android 정리 기록기(순서 그대로 적는다). */
        val cleanup = object : AndroidAccountCleanup {
            override fun cancelNotifications() { events += "android:notifications" }
            override suspend fun deletePushToken() { events += "android:fcm-token" }
            override suspend fun refreshWidgets() { events += "android:widgets" }
        }

        init {
            scope.backgroundScope.coroutineContext.job.invokeOnCompletion { job.cancel() }
            session.onLocalUserDataCleared = { events += "local:cleared" }
        }

        fun signIn() {
            session.adoptSignedInSession(SupabaseSession("old-access", "old-refresh", me), "rankme@example.invalid")
        }
    }

    @Test
    fun successOrderIsReauthAvatarRpcLocalThenAndroid() = runTest {
        val h = Harness(this)
        h.signIn()
        advanceUntilIdle()
        h.events.clear()
        h.store.accountDeletionPassword = rightPassword
        val deleted = AccountDeletionFlow(h.store, h.cleanup).run()
        advanceUntilIdle()
        assertTrue(deleted)
        assertEquals(
            listOf(
                "reauth",
                "avatar:fresh-access",
                "rpc:delete_my_account:fresh-access",
                "local:cleared",
                "android:notifications",
                "android:fcm-token",
                "android:widgets",
            ),
            h.events,
        )
        assertEquals(SessionPhase.SignedOut, h.session.phase)
        assertNull("금고 토큰이 남았다", h.vault.read(SessionVaultKeys.accessToken))
        assertNull(h.vault.read(SessionVaultKeys.refreshToken))
        assertNull("사용자 칸이 남았다(위젯이 지운 계정 파일을 고른다)", h.prefs.getString(SessionPrefsKeys.userID))
        assertNull("지운 계정 이메일이 로그인 칸에 남는다", h.session.storedEmail)
        assertFalse("지운 계정의 토큰이 정리 장부에 남았다", h.session.hasPendingSignOutCleanup)
    }

    @Test
    fun wrongPasswordStopsBeforeRpcAndTouchesNothingOnDevice() = runTest {
        val h = Harness(this)
        h.signIn()
        advanceUntilIdle()
        h.events.clear()
        h.store.accountDeletionPassword = "wrong"
        assertFalse(AccountDeletionFlow(h.store, h.cleanup).run())
        advanceUntilIdle()
        assertEquals(listOf("reauth"), h.events)
        assertEquals(SessionPhase.SignedIn, h.session.phase)
        assertEquals(me, h.prefs.getString(SessionPrefsKeys.userID))
        assertEquals("비밀번호가 맞지 않아요", h.store.accountDeletionNotice)
        assertEquals("실패했는데 입력을 지웠다", "wrong", h.store.accountDeletionPassword)
    }

    @Test
    fun rpcFailureKeepsLocalAndClosesOnlyTheReauthSession() = runTest {
        for (status in listOf(404, 503)) {
            val h = Harness(this, rpcStatus = status)
            h.signIn()
            advanceUntilIdle()
            h.events.clear()
            h.store.accountDeletionPassword = rightPassword
            assertFalse(AccountDeletionFlow(h.store, h.cleanup).run())
            advanceUntilIdle()
            assertEquals(
                "$status",
                listOf("reauth", "avatar:fresh-access", "rpc:delete_my_account:fresh-access", "logout:fresh-access"),
                h.events,
            )
            assertEquals(SessionPhase.SignedIn, h.session.phase)
            assertEquals("old-access", h.vault.read(SessionVaultKeys.accessToken))
            assertTrue(h.events.none { it.startsWith("android:") || it == "local:cleared" })
        }
    }

    /**
     * 소스 계약: 삭제를 부르는 Android·공용 화면 파일은 AccountDeletionFlow 하나뿐 · 설정 화면은 삭제 화면을 열기만 · 삭제 화면의 키보드 완료 키는
     * 포커스만 내린다(키보드 닫기 습관 한 번에 계정이 지워지면 안 된다).
     */
    @Test
    fun sourceContracts() {
        val mp = File(requireNotNull(System.getProperty("aingcheck.mpRoot")))
        val roots = listOf(File(mp, "androidApp/src/main"), File(mp, "ui/src/commonMain"))
        val callers = roots.flatMap { root -> root.walkTopDown().filter { it.isFile && it.name.endsWith(".kt") }.toList() }
            .filter { stripComments(it.readText()).contains(".deleteAccount()") }
            .map { it.relativeTo(mp).invariantSeparatorsPath }
        assertEquals(listOf("androidApp/src/main/kotlin/com/yehsung/aingcheck/android/screens/account/AccountDeletionFlow.kt"), callers)
        val settings = stripComments(File(mp, "ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/screens/settingscommon/SettingsScreen.kt").readText())
        assertFalse("설정 화면이 삭제를 부른다", settings.contains("deleteAccount("))
        assertTrue("설정 화면이 삭제 화면을 열지 않는다", settings.contains("actions::openAccountDeletion"))
        val screen = stripComments(File(mp, "ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/screens/settingscommon/AccountDeletionScreen.kt").readText())
        assertTrue("키보드 완료 키가 포커스 내리기 말고 다른 일을 한다", screen.contains("keyboardActions = KeyboardActions(onDone = { focus.clearFocus() })"))
        assertEquals("onDelete 는 매개변수와 [영구 삭제] 단추 두 곳뿐", 2, Regex("""\bonDelete\b""").findAll(screen).count())
        assertTrue("제출 가드가 비활성 하나뿐이다", screen.contains("if (!store.canDeleteAccount) return@Button"))
        // 순서 계약의 세션 쪽(W2-a): 재인증이 RPC 보다 먼저, 로컬 정리는 endSession 한 길.
        val session = stripComments(File(mp, "core/session/src/commonMain/kotlin/com/yehsung/aingcheck/core/session/SessionStore.kt").readText())
        val body = session.substringAfter("suspend fun deleteAccount(password: String)")
        val reauth = body.indexOf("service.signIn(email, password)")
        val rpc = body.indexOf("service.deleteMyAccount(reauth.accessToken)")
        val cleanup = body.indexOf("endSession(cleanup = null)")
        assertTrue("순서: 재인증($reauth) → RPC($rpc) → 로컬 정리($cleanup)", reauth in 0 until rpc && rpc < cleanup)
        // 공개 원문(Swift) 도 같은 순서다 — 두 기계가 같은 계약을 쓴다.
        val swift = RepoFiles.readText("Sources/CheckMobileKit/Session/MobileSessionStore.swift")
        assertTrue(swift.contains("service.deleteMyAccount(accessToken: reauth.accessToken)"))
    }

    private fun stripComments(src: String): String =
        src.replace(Regex("""/\*[\s\S]*?\*/"""), "").lines().joinToString("\n") { line ->
            val i = line.indexOf("//")
            if (i >= 0 && !line.substring(0, i).contains('"')) line.substring(0, i) else line
        }
}
