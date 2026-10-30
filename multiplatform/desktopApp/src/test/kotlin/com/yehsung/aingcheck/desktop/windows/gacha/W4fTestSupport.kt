// W4-f 시험 도우미 — 창 0 손잡이 · 메모리 자리 저장소 · 진짜 나 탭 스토어(MeStore)를 합성 서버(로컬 MockWebServer)에 붙인 한 벌.
// 픽스처는 저장소의 데모 픽스처(Sources/CheckMobileKit/Demo/Fixtures/me — 합성 계정, 제자리 읽기)만 쓴다. 실제 홈·계정·운영 0.
// ui commonTest 의 MeScreenHarness(ktor MockEngine · coroutines-test) 를 desktopApp 시험이 볼 수 없어(조정자 C4 전) 같은 장면을
// 로컬 서버 + 실제 디스패처로 다시 세운다 — 조정자 C4(시험 기반 공유) 때 지운다.
package com.yehsung.aingcheck.desktop.windows.gacha

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.ImageBitmap
import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.stores.me.DrawableCharacterSource
import com.yehsung.aingcheck.core.stores.me.MeContext
import com.yehsung.aingcheck.core.stores.me.MeLinks
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.RubyBalanceCell
import com.yehsung.aingcheck.core.stores.me.loadAchievements
import com.yehsung.aingcheck.core.stores.me.loadCakeGift
import com.yehsung.aingcheck.core.stores.me.loadEquippedCharacter
import com.yehsung.aingcheck.core.stores.me.loadShop
import com.yehsung.aingcheck.core.stores.me.loadWeeklyWork
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.desktop.testsupport.DesktopSnapshots
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowHandle
import com.yehsung.aingcheck.desktop.windows.kit.WindowBoundsStore
import com.yehsung.aingcheck.ui.shop.LocalMeArt
import com.yehsung.aingcheck.ui.shop.MeArtSource
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import mockwebserver3.Dispatcher
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import org.jetbrains.compose.resources.ExperimentalResourceApi
import org.jetbrains.compose.resources.decodeToImageBitmap
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** 창 0 손잡이 — 사용자 화면에 아무것도 띄우지 않는다. */
class FakeWindowHandle : GameWindowHandle {
    override var isMinimized = false
    var visible = false
    var shows = 0
    var hides = 0
    var disposed = false
    private var rect = PxRect(0, 0, 0, 0)
    override val isOnScreen: Boolean get() = visible && !isMinimized
    override fun restoreFromMinimized() { isMinimized = false }
    override fun showAndFocus() { visible = true; shows++ }
    override fun hide() { visible = false; hides++ }
    override fun boundsPx(): PxRect = rect
    override fun setBoundsPx(rect: PxRect) { this.rect = rect }
    override fun dispose() { disposed = true }
}

class MemoryBounds : WindowBoundsStore {
    val saved = LinkedHashMap<String, PxRect>()
    override fun load(key: String): PxRect? = saved[key]
    override fun save(key: String, rect: PxRect) { saved[key] = rect }
}

val WORK_AREA = PxRect(0, 0, 1920, 1040)

/** 합성 서버 — 경로로 답한다. 받은 요청을 순서대로 적는다. [pullGate] 가 있으면 뽑기 답을 그 문이 열릴 때까지 쥔다(왕복 중 재현). */
class W4fServer(private val scene: W4fScene = W4fScene()) : AutoCloseable {
    private val server = MockWebServer()
    val calls = CopyOnWriteArrayList<String>()

    @Volatile
    var pullGate: CountDownLatch? = null

    init {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.url.encodedPath
                calls += "${request.method} $path"
                if (path == PULL) pullGate?.await(10, TimeUnit.SECONDS)
                val body = route(request.method, path)
                return MockResponse.Builder()
                    .code(if (body == null) 404 else 200)
                    .addHeader("Content-Type", "application/json")
                    .body(body ?: """{"message":"unrouted"}""")
                    .build()
            }
        }
        server.start()
    }

    val baseUrl: String get() = server.url("/").toString().trimEnd('/')

    fun count(path: String): Int = calls.count { it.endsWith(" $path") }

    private fun route(method: String, path: String): String? = when (path) {
        "/rest/v1/rpc/register_device_fcm" -> """{"status":"ok","device_id":"dev-1","push_prefs":{"message":true,"gomoku_invite":true,"feedback_reply":true}}"""
        "/rest/v1/memberships" -> "[]"
        "/rest/v1/rpc/shop_state" -> scene.shopState
        "/rest/v1/rpc/achievements_status" -> fixture("_me/rpc.achievements_status.json")
        "/rest/v1/rpc/weekly_work_status" -> fixture("_me/rpc.weekly_work_status.json")
        "/rest/v1/rpc/character_gift_pending" -> scene.giftPending
        PULL -> fixture("rpc.gacha_pull.json")
        "/rest/v1/profiles" -> if (method == "GET") fixture("rest.profiles.get@select=character.json") else null
        else -> null
    }

    override fun close() = server.close()

    companion object {
        const val PULL = "/rest/v1/rpc/gacha_pull"
        const val ME = "Sources/CheckMobileKit/Demo/Fixtures/me"

        /** 픽스처 글자(Windows 체크아웃의 CRLF 는 LF 로 접는다). */
        fun fixture(path: String): String = File(DesktopSnapshots.repoRoot, "$ME/$path").readText().replace("\r\n", "\n")
    }
}

/** 장면 하나의 서버 답. */
data class W4fScene(
    val shopState: String = W4fServer.fixture("_me/rpc.shop_state.json"),
    val giftPending: String? = null,
)

/** 스토어 한 벌과 그 범위·서버. 끝나면 [close] — 범위를 닫아 화면이 부르는 읽기도 망에 닿지 않는다. */
class W4fStore(scene: W4fScene = W4fScene()) : AutoCloseable {
    val server = W4fServer(scene)
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    val store: MeStore

    init {
        val clock = SessionClock { SwiftDate(DEMO_EPOCH) }
        val service = SupabaseWorkService(
            projectURL = server.baseUrl,
            anonKey = "stub-anon-key",
            client = HttpClient(OkHttp) { SupabaseWorkService.clientConfig(this) },
            clock = { clock.now() },
            text = RulesWireTextRules,
            newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
        )
        val session = SessionStore(
            service = service,
            vault = MemoryVault(),
            prefs = MemoryPrefs(),
            appInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 15"),
            installationIdentity = object : InstallationIdentity {
                override fun installationId(): String = "11111111-2222-4333-8444-555555555555"
            },
            clock = clock,
            instanceGuard = object : SingleInstanceGuard {
                override fun tryAcquire(): Boolean = true
                override fun release() {}
            },
            parentScope = scope,
            newCleanupID = { "cleanup-1" },
        )
        store = MeStore(
            context = MeContext(session, AppConfig(), RubyBalanceCell(), MeLinks.None),
            parentScope = scope,
            drawableCharacters = DrawableCharacterSource.of(ALL_PORTRAITS),
            computeContext = Dispatchers.Default,
            newRequestID = { "AAAAAAAA-0000-4000-8000-000000000001" },
        )
        session.adoptSignedInSession(SupabaseSession("tok-user-1", "ref-user-1", "user-1"), "a@b.co")
        runBlocking {
            store.loadShop()
            store.loadEquippedCharacter()
            store.loadAchievements()
            store.loadWeeklyWork()
            if (scene.giftPending != null) store.loadCakeGift()
        }
    }

    override fun close() {
        scope.cancel()
        server.close()
    }

    companion object {
        /** 데모 기준 시각 2026-09-17 14:05:00 KST — 픽스처 server_now_ms 와 같은 순간. */
        const val DEMO_EPOCH: Double = 1_789_621_500.0
        val ALL_PORTRAITS: Set<String> = setOf(
            "aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco",
            "fox", "ghost", "jellyfish", "robot", "shiba", "squirrel",
        )
    }
}

/** 조건이 설 때까지 기다린다(실제 디스패처 — 상한 10초). */
fun waitUntil(what: String, cond: () -> Boolean) {
    val end = System.nanoTime() + 10_000_000_000L
    while (!cond()) {
        check(System.nanoTime() < end) { "기다림 시간 초과: $what" }
        Thread.sleep(5)
    }
}

/** 저장소 그림 창구(ui RepoMeArt 의 사본 — 조정자 C4 전 임시). */
class RepoArt : MeArtSource {
    private val cache = HashMap<String, ImageBitmap?>()

    @OptIn(ExperimentalResourceApi::class)
    override fun peek(path: String): ImageBitmap? = synchronized(cache) {
        cache.getOrPut(path) { repoPath(path)?.let { File(DesktopSnapshots.repoRoot, it) }?.takeIf { it.isFile }?.readBytes()?.decodeToImageBitmap() }
    }

    override suspend fun load(path: String): ImageBitmap? = peek(path)

    companion object {
        val shared by lazy { RepoArt() }
        private val aingFamily = setOf("aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco")
        private val portrait = Regex("^files/characters/([a-z0-9_]+)/portrait-([a-z]+)\\.png$")

        fun repoPath(resourcePath: String): String? {
            portrait.matchEntire(resourcePath)?.let { m ->
                val (id, expression) = m.destructured
                return if (id in aingFamily) "Sources/check/Resources/$id-$expression.png" else "Sources/check/Characters/$id/portrait-$expression.png"
            }
            if (resourcePath.startsWith("files/art/")) return "Sources/CheckMobileKit/Resources/Art/" + resourcePath.removePrefix("files/art/")
            if (resourcePath.startsWith("files/gacha/")) return "Sources/CheckCore/Resources/GachaMachine/" + resourcePath.removePrefix("files/gacha/")
            return null
        }
    }
}

@Composable
fun WithRepoArt(content: @Composable () -> Unit) = CompositionLocalProvider(LocalMeArt provides RepoArt.shared, content = content)

private class MemoryVault : TokenVault {
    private val values = HashMap<String, String>()
    override fun read(key: String): String? = values[key]
    override fun write(value: String, key: String) { values[key] = value }
    override fun delete(key: String) { values.remove(key) }
}

private class MemoryPrefs : KeyValueStore {
    val values = LinkedHashMap<String, Any>()
    override fun getString(key: String): String? = values[key] as? String
    override fun putString(key: String, value: String) { values[key] = value }
    override fun getLong(key: String): Long? = values[key] as? Long
    override fun putLong(key: String, value: Long) { values[key] = value }
    override fun getBoolean(key: String): Boolean? = values[key] as? Boolean
    override fun putBoolean(key: String, value: Boolean) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
}
