// 원본: 없음 — androidApp 호스트 시험(Robolectric) 조립: **실제 HTTP**(앱 단일 팩토리 HttpEngineFactory → OkHttp → 로컬 MockWebServer)
// 위의 세션 스토어 · 게임 탭 스토어. 스토어 범위는 메인 디스패처(조립이 주는 것과 같은 자리) — 시험은 메인 루퍼를 직접 돌린다.
// 망은 127.0.0.1 MockWebServer 뿐이다(운영 주소 0 — projectURL 은 server.url("/")).
package com.yehsung.aingcheck.android.screens.games.hub

import android.os.Looper
import androidx.compose.runtime.snapshots.Snapshot
import com.yehsung.aingcheck.android.http.HttpEngineFactory
import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.session.SessionPrefsKeys
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.SessionVaultKeys
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.stores.games.GamesBoardGameLink
import com.yehsung.aingcheck.core.stores.games.GamesContext
import com.yehsung.aingcheck.core.stores.games.GamesDestination
import com.yehsung.aingcheck.core.stores.games.GamesGomokuLink
import com.yehsung.aingcheck.core.stores.games.GamesRouter
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.tetris.StoreNaturalCollation
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStoreHost
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.WireTextRules
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import mockwebserver3.Dispatcher
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import org.robolectric.Shadows.shadowOf
import java.util.Base64
import java.util.Collections

internal class GamesAndroidRig(appConfig: AppConfig = AppConfig()) : AutoCloseable {
    /** (rpc 이름, 본문) — 받은 순서. */
    val calls: MutableList<Pair<String, String>> = Collections.synchronizedList(mutableListOf())
    private var issued = 0

    val server = MockWebServer().apply {
        dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.url.encodedPath
                val rpc = path.removePrefix("/rest/v1/rpc/").takeIf { path.startsWith("/rest/v1/rpc/") } ?: path
                calls += rpc to (request.body?.utf8() ?: "")
                val body = when (rpc) {
                    "minigame_start_round" -> synchronized(this@GamesAndroidRig) { """{"status":"ok","token":"t${++issued}"}""" }
                    "minigame_submit_score" -> """{"status":"ok","best_score":1,"plays":1,"improved":true}"""
                    "minigame_board", "minigame_yesterday_winner" -> "[]"
                    "/rest/v1/profiles" -> """[{"minigame_public":true}]"""
                    else -> return MockResponse.Builder().code(404).body("""{"message":"no route $rpc"}""").build()
                }
                return MockResponse.Builder().code(200).addHeader("Content-Type", "application/json").body(body).build()
            }
        }
        start()
    }

    private val storeJob = SupervisorJob()
    val scope: CoroutineScope = CoroutineScope(Dispatchers.Main + storeJob)
    /** 세션 시계는 고정(벽시계는 조립 지점에서만 — 구조 규칙 R2). 토큰 만료·판 시각이 이 값 하나에서 나온다. */
    private val clock = SessionClock { NOW }
    private val vault = object : TokenVault {
        val values = HashMap<String, String>()
        override fun read(key: String): String? = values[key]
        override fun write(value: String, key: String) { values[key] = value }
        override fun delete(key: String) { values.remove(key) }
    }
    private val prefs = object : KeyValueStore {
        val values = HashMap<String, Any>()
        override fun getString(key: String): String? = values[key] as? String
        override fun putString(key: String, value: String) { values[key] = value }
        override fun getLong(key: String): Long? = values[key] as? Long
        override fun putLong(key: String, value: Long) { values[key] = value }
        override fun getBoolean(key: String): Boolean? = values[key] as? Boolean
        override fun putBoolean(key: String, value: Boolean) { values[key] = value }
        override fun remove(key: String) { values.remove(key) }
    }
    private val text = object : WireTextRules {
        override fun sanitized(raw: String): String = raw.trim()
        override fun hasVisibleContent(text: String): Boolean = text.any { !it.isWhitespace() }
        override fun statusMessageSanitized(raw: String): String = raw.trim()
    }
    private val http = HttpEngineFactory.ktorClient { SupabaseWorkService.clientConfig(this) }
    val sessionStore = SessionStore(
        service = SupabaseWorkService(
            projectURL = server.url("/").toString().trimEnd('/'),
            anonKey = "stub-anon-key",
            client = http,
            clock = { clock.now() },
            text = text,
            newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
        ),
        vault = vault,
        prefs = prefs,
        appInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 16"),
        installationIdentity = object : InstallationIdentity { override fun installationId(): String? = "11111111-2222-4333-8444-555555555555" },
        clock = clock,
        instanceGuard = object : SingleInstanceGuard {
            override fun tryAcquire(): Boolean = true
            override fun release() = Unit
        },
        parentScope = scope,
    )
    private val tetrisHost = object : TetrisDuelStoreHost {
        override val session: SupabaseSession? get() = sessionStore.session
        override val sessionGeneration: Int get() = sessionStore.sessionGeneration
        override val service: SupabaseWorkService get() = sessionStore.service
        override var rubyBalance: Int? = null
        override val appConfig: AppConfig = appConfig
        override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T = sessionStore.withSessionRetry(operation)
    }
    private val tetris = TetrisDuelStore(host = tetrisHost, scope = scope, clock = { clock.now() }).also {
        it.gameLoopStepSeconds = Double.POSITIVE_INFINITY
        it.pollStepSeconds = Double.POSITIVE_INFINITY
    }

    private open class Board : GamesBoardGameLink {
        override var activeMatchID: String? = null
        override var hasMatch: Boolean = false
        override var hasUnfinishedMatch: Boolean = false
        override var isAIMatch: Boolean = false
        override var isWindowVisible: Boolean = false
        override var presentWindow: (() -> Unit)? = null
        override fun openWindow(focusMatchID: String?) = Unit
        override fun windowDidShow() { isWindowVisible = true }
        override fun windowDidHide() { isWindowVisible = false }
        override fun windowDidClose() = Unit
        override fun windowOcclusionDidChange(visible: Boolean) = Unit
        override fun stopWatching() = Unit
        override suspend fun catchUp() = Unit
        override fun refreshLobbyIfStale() = Unit
    }

    private class Gomoku : Board(), GamesGomokuLink {
        override var pendingIncomingInviteCount: Int = 0
        override fun refreshInboxIfStale() = Unit
        override fun setAIThinkerAllowed(allowed: Boolean) = Unit
    }

    private val context: GamesContext = object : GamesContext {
        override val sessionStore: SessionStore get() = this@GamesAndroidRig.sessionStore
        override val appConfig: AppConfig = appConfig
        override val scope: CoroutineScope get() = this@GamesAndroidRig.scope
        override val collation: Collation = StoreNaturalCollation
        override fun refreshAchievementsAfterGameResult(game: String) = Unit
        override val tetris: TetrisDuelStore get() = this@GamesAndroidRig.tetris
        override val gomoku: GamesGomokuLink = Gomoku()
        override val chess: GamesBoardGameLink = Board()
        override val router: GamesRouter = object : GamesRouter {
            override fun present(destination: GamesDestination) = Unit
        }
        override val hiddenBlockedPeerIDs: Set<String> = emptySet()
        override val sharedRubyBalance: Int? = null
    }

    val store = GamesStore(context)

    /** 메인 루퍼와 스냅숏 적용 알림을 [condition] 이 참이 될 때까지 돌린다(상한 [timeoutMillis]). */
    fun pumpUntil(timeoutMillis: Long = 10_000, condition: () -> Boolean): Boolean {
        // 망 왕복은 진짜 스레드(OkHttp)라 실제 시간을 기다린다. 상한은 **바퀴 수**(한 바퀴 5ms 잠)로 잰다 — Robolectric 의 SystemClock 은
        // 멈춘 루퍼 모드에서 흐르지 않아(실측: 상한이 영영 안 와 시험이 멎었다) 시계로 재면 안 된다. 벽시계는 구조 규칙 R2 가 막는다.
        repeat((timeoutMillis / PUMP_STEP_MILLIS).toInt().coerceAtLeast(1)) {
            Snapshot.sendApplyNotifications()
            shadowOf(Looper.getMainLooper()).idle()
            if (condition()) return true
            Thread.sleep(PUMP_STEP_MILLIS)
        }
        Snapshot.sendApplyNotifications()
        shadowOf(Looper.getMainLooper()).idle()
        return condition()
    }

    /** 일이 가라앉을 때까지 잠깐 돌린다(조건 없는 펌프 — 망 왕복 몇 번이 끝날 시간). */
    fun settle(millis: Long = 300) {
        pumpUntil(millis) { false }
    }

    /** 금고에 세션을 심고 실행 복원 → SignedIn(client_release 는 404 — 모르면 막지 않는다). */
    fun signIn() {
        fun b64(s: String) = Base64.getUrlEncoder().withoutPadding().encodeToString(s.toByteArray())
        val exp = NOW.timeIntervalSince1970.toLong() + 3600
        vault.write("hdr." + b64("""{"sub":"$USER","exp":$exp}""") + ".sig", SessionVaultKeys.accessToken)
        vault.write("r0", SessionVaultKeys.refreshToken)
        prefs.putString(SessionPrefsKeys.userID, USER)
        prefs.putString(SessionPrefsKeys.email, "a@b.co")
        scope.launch { sessionStore.launch() }
        check(pumpUntil { sessionStore.isSignedIn }) { "로그인이 안 됐다: ${sessionStore.phase}" }
    }

    fun bodies(rpc: String): List<String> = synchronized(calls) { calls.filter { it.first == rpc }.map { it.second } }

    override fun close() {
        scope.cancel()
        http.close()
        server.close()
    }

    companion object {
        const val USER: String = "aaaaaaaa-0000-4000-8000-000000000001"
        val NOW: SwiftDate = SwiftDate(1_789_621_500.0)
        private const val PUMP_STEP_MILLIS = 5L
    }
}
