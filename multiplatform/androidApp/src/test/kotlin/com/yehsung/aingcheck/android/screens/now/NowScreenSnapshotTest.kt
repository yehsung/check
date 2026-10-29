// 원본: Sources/CheckMobileKit/Now/NowTab.swift @ 3bd04bd (데모 장면 now — 새벽(나) 폰에서 근무 중 · 우리 팀 · 다른 팀 · 할 일)
// 원본: Sources/CheckMobileKit/Demo/MobileDemo.swift @ 3bd04bd (데모 픽스처 규칙 — ui 시험 ScreenHarness 와 같은 규칙의 앱 모듈 판)
//
// G §2-3 W3-a ① Roborazzi: 지금 탭 — 폰(밝음 · 어두움) · sw600dp. 지금 탭은 Android 전용 화면(androidApp …/screens/now)이라 골든도
// 이 갈래 소유 자리(이 폴더의 golden/)에 둔다. 판정은 부품·화면 스냅숏과 같다: 두 번 그려 같다 · 골든과 같다(기록 기계 픽셀 그대로, 다른
// 러너 굵은 대조) · 한 군데 다른 장면(착용 캐릭터만 다른 카드)은 다르다. 기록은 AINGCHECK_SNAPSHOT_RECORD=1(그 실행은 실패로 끝난다).
package com.yehsung.aingcheck.android.screens.now

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
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
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.stores.characters.AppUserCharacterStore
import com.yehsung.aingcheck.core.stores.now.NowStore
import com.yehsung.aingcheck.core.stores.now.NowTodoStorage
import com.yehsung.aingcheck.core.stores.now.NowWorkOrigin
import com.yehsung.aingcheck.core.stores.now.todo.JvmTodoFileSystem
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.components.CharacterExpression
import com.yehsung.aingcheck.ui.screens.session.kit.LocalAppUserCharacters
import com.yehsung.aingcheck.ui.screens.session.kit.LocalScreenArt
import com.yehsung.aingcheck.ui.screens.session.kit.LocalScreenTicking
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenArt
import com.yehsung.aingcheck.ui.theme.AingTheme
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockEngineConfig
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.nio.file.Files
import java.util.Base64
import java.util.concurrent.Executors

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h800dp-xhdpi")
class NowScreenSnapshotTest {
    private val mpRoot = File(requireNotNull(System.getProperty("aingcheck.mpRoot")))
    private val repoRoot = mpRoot.parentFile
    private val demoUser = "d0000000-0000-4000-8000-000000000001"
    private val clock = SessionClock.fixed(SessionClock.demoInstant)
    private val executor = Executors.newSingleThreadExecutor { r -> Thread(r, "now-harness").apply { isDaemon = true } }
    private val dispatcher = executor.asCoroutineDispatcher()
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val todoDir: File = Files.createTempDirectory("aingcheck-now-todo").toFile()
    private val art = ScreenArt.bundledOnly()

    @Volatile
    private var frozen = false

    private val fixtures = File(repoRoot, "Sources/CheckMobileKit/Demo/Fixtures").walkTopDown().filter { it.isFile && it.name.endsWith(".json") }.map { f ->
        val rel = f.relativeTo(File(repoRoot, "Sources/CheckMobileKit/Demo/Fixtures")).invariantSeparatorsPath
        val scenario = rel.split('/').dropLast(1).lastOrNull { it.startsWith("_") }?.drop(1)
        val parts = f.name.removeSuffix(".json").split('@', limit = 2)
        Fixture(parts[0], parts.getOrNull(1), scenario, f.readText())
    }.toList()

    private data class Fixture(val key: String, val needle: String?, val scenario: String?, val text: String)

    /** Swift `MobileDemoFixtures.response`(장면 `now`) — ui 시험 DemoFixtures 와 같은 규칙. */
    private fun respond(method: String, path: String, query: String, body: String): Pair<Int, String> {
        val m = method.lowercase()
        val seg = path.split('/').filter { it.isNotEmpty() }
        val key = when {
            seg.size >= 4 && seg[0] == "rest" && seg[2] == "rpc" -> "rpc.${seg[3]}"
            seg.size >= 3 && seg[0] == "rest" -> "rest.${seg[2]}.$m"
            seg.size >= 3 && seg[0] == "auth" -> (listOf("auth") + seg.drop(2) + m).joinToString(".")
            else -> "unknown.$m"
        }
        val hay = "$body&$query"
        val hit = fixtures.filter { it.key == key && (it.scenario == null || it.scenario == "now") && (it.needle == null || hay.contains(it.needle)) }
            .sortedWith(compareByDescending<Fixture> { if (it.scenario != null) 1 else 0 }.thenByDescending { it.needle?.length ?: -1 }).firstOrNull()
            ?: return 404 to """{"code":"PGRST202","message":"Could not find the function public.$key"}"""
        val parsed = runCatching { Json.parseToJsonElement(hit.text) }.getOrNull()
        if (parsed is JsonObject && parsed["__status"] != null) return (parsed["__status"]!!.jsonPrimitive.intOrNull ?: 500) to (parsed["__body"]?.toString() ?: "{}")
        return 200 to hit.text
    }

    private val engine = MockEngine(
        MockEngineConfig().apply {
            dispatcher = this@NowScreenSnapshotTest.dispatcher
            addHandler { request ->
                if (frozen) awaitCancellation()
                val body = (request.body as? OutgoingContent.ByteArrayContent)?.bytes()?.decodeToString() ?: ""
                val (status, text) = respond(request.method.value, request.url.encodedPath, request.url.encodedQuery, body)
                respond(text, HttpStatusCode.fromValue(status), headersOf(HttpHeaders.ContentType, "application/json"))
            }
        },
    )
    private val vault = InMemoryTokenVault()
    private val prefs = object : KeyValueStore {
        val values = HashMap<String, Any>()
        override fun getString(key: String) = values[key] as? String
        override fun putString(key: String, value: String) { values[key] = value }
        override fun getLong(key: String) = values[key] as? Long
        override fun putLong(key: String, value: Long) { values[key] = value }
        override fun getBoolean(key: String) = values[key] as? Boolean
        override fun putBoolean(key: String, value: Boolean) { values[key] = value }
        override fun remove(key: String) { values.remove(key) }
    }
    private val session = SessionStore(
        service = SupabaseWorkService("https://demo.invalid", "stub-anon-key", HttpClient(engine) { SupabaseWorkService.clientConfig(this) },
            { clock.now() }, RulesWireTextRules, { "ABCDEF12-0000-4000-8000-000000000000" }),
        vault = vault, prefs = prefs,
        appInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 16"),
        installationIdentity = object : InstallationIdentity { override fun installationId() = "d0000000-0000-4000-8000-0000000000aa" },
        clock = clock,
        instanceGuard = object : SingleInstanceGuard {
            override fun tryAcquire() = true
            override fun release() {}
        },
        parentScope = scope,
    )
    private val context = SessionContext(session)
    private lateinit var store: NowStore
    private lateinit var characters: AppUserCharacterStore

    /** 폰이 연 근무(데모 새벽) — 폰 근무 문(W2-f)의 값만 흉내 낸다. */
    private val phoneWork = object : NowWorkActions {
        override val showsWorkControl = true
        override val showsDisabledWorkControlForNoTeam = false
        override val isMyWorkOpen = true
        override val myWorkOrigin = NowWorkOrigin.phone
        override val isPushDenied = false
        override suspend fun clockIn() {}
        override suspend fun clockOut() {}
    }

    private fun <T> onStore(block: suspend CoroutineScope.() -> T): T = runBlocking(dispatcher) { block() }

    private fun load() {
        onStore {
            val exp = (clock.now().timeIntervalSince1970 + 3_600).toLong()
            val b64 = Base64.getUrlEncoder().withoutPadding()
            vault.write("hdr." + b64.encodeToString("""{"sub":"$demoUser","exp":$exp}""".toByteArray()) + ".sig", SessionVaultKeys.accessToken)
            vault.write("r0", SessionVaultKeys.refreshToken)
            prefs.putString(SessionPrefsKeys.userID, demoUser)
            session.launch()
            check(session.phase == SessionPhase.SignedIn)
            store = NowStore(context, scope, NowTodoStorage(todoDir.absolutePath, JvmTodoFileSystem()))
            characters = AppUserCharacterStore(context, scope, CharacterArt.portraitIds)
            store.appDidBecomeActive()
            characters.refresh()
            characters.inflight?.join()
            withTimeout(10_000) { while (!(store.hasFinishedRefreshAttempt && !store.isRefreshing && store.todos.items.isNotEmpty())) delay(10) }
        }
        frozen = true
    }

    @After
    fun close() {
        scope.cancel()
        executor.shutdownNow()
        todoDir.deleteRecursively()
    }

    @Composable
    private fun Frame(dark: Boolean, content: @Composable () -> Unit) {
        AingTheme(dark = dark) {
            CompositionLocalProvider(LocalScreenTicking provides false, LocalScreenArt provides art, LocalAppUserCharacters provides characters.directory, content = content)
        }
    }

    @OptIn(ExperimentalTestApi::class)
    private fun render(width: Dp, height: Dp, content: @Composable () -> Unit): IntArrayImage {
        var out: IntArrayImage? = null
        runComposeUiTest {
            runBlocking {
                for (id in CharacterArt.portraitIds) for (e in CharacterExpression.entries) art.bundled.get(CharacterArt.portraitPath(id, e))
            }
            setContent { Box(Modifier.wrapContentSize(Alignment.TopStart, unbounded = true).testTag(TAG)) { Box(Modifier.size(width, height)) { content() } } }
            waitForIdle()
            val bitmap = onNodeWithTag(TAG).captureToImage().asAndroidBitmap().copy(Bitmap.Config.ARGB_8888, false)
            val px = IntArray(bitmap.width * bitmap.height)
            bitmap.getPixels(px, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
            out = IntArrayImage(bitmap.width, bitmap.height, px)
        }
        return requireNotNull(out)
    }

    private class IntArrayImage(val width: Int, val height: Int, val argb: IntArray) {
        fun differing(other: IntArrayImage): Int = if (width != other.width || height != other.height) -1 else argb.indices.count { argb[it] != other.argb[it] }

        /** 8px 칸 평균 RGB 차의 최댓값(굵은 대조 — 비기록 러너). */
        fun maxBlockDelta(other: IntArrayImage, block: Int = 8): Int {
            var max = 0
            for (by in 0 until (height + block - 1) / block) for (bx in 0 until (width + block - 1) / block) {
                val a = LongArray(3)
                val b = LongArray(3)
                var n = 0
                for (y in by * block until minOf(height, (by + 1) * block)) for (x in bx * block until minOf(width, (bx + 1) * block)) {
                    for (c in 0 until 3) {
                        a[c] += ((argb[y * width + x] ushr (16 - 8 * c)) and 0xFF).toLong()
                        b[c] += ((other.argb[y * width + x] ushr (16 - 8 * c)) and 0xFF).toLong()
                    }
                    n++
                }
                for (c in 0 until 3) max = maxOf(max, kotlin.math.abs(((a[c] - b[c]) / n).toInt()))
            }
            return max
        }

        fun writePng(file: File) {
            file.parentFile.mkdirs()
            val bitmap = Bitmap.createBitmap(argb, width, height, Bitmap.Config.ARGB_8888)
            file.outputStream().use { require(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
        }

        companion object {
            fun readPng(file: File): IntArrayImage {
                val options = BitmapFactory.Options().apply { inScaled = false; inPreferredConfig = Bitmap.Config.ARGB_8888; inPremultiplied = false }
                val bitmap = requireNotNull(BitmapFactory.decodeFile(file.path, options)) { "PNG 디코드 실패: $file" }
                val px = IntArray(bitmap.width * bitmap.height)
                bitmap.getPixels(px, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
                return IntArrayImage(bitmap.width, bitmap.height, px)
            }
        }
    }

    private fun check(name: String, width: Dp, height: Dp, dark: Boolean) {
        load()
        assertTrue("데모 장면: 새벽(나)이 근무 중이고 할 일이 서야 한다", store.myCard(clock.now())?.isWorking == true && store.todoRows().main.isNotEmpty())
        val scene: @Composable () -> Unit = { Frame(dark) { NowScreen(store, phoneWork, characterID = null, onTalk = {}, onEditGoal = {}) } }
        val other: @Composable () -> Unit = { Frame(dark) { NowScreen(store, phoneWork, characterID = "fox", onTalk = {}, onEditGoal = {}) } }
        val first = render(width, height, scene)
        val second = render(width, height, scene)
        assertEquals("$name: 두 번 그린 장면이 다르다 — 렌더가 굳지 않았다", 0, first.differing(second))
        assertTrue("$name: 장면이 그려지지 않았다", first.argb.toHashSet().size >= 64)
        System.getenv("AINGCHECK_EVIDENCE_DIR")?.let { runCatching { first.writePng(File(it, "android-$name.png")) } }
        val golden = File(mpRoot, "androidApp/src/test/kotlin/com/yehsung/aingcheck/android/screens/now/golden/$name.png")
        if (System.getenv("AINGCHECK_SNAPSHOT_RECORD") == "1") {
            first.writePng(golden)
            fail("$name: 골든을 기록했다(${golden.path}) — 기록 실행은 실패로 끝난다")
        }
        assertTrue("$name: 골든이 없다(${golden.path})", golden.isFile)
        val expected = IntArrayImage.readPng(golden)
        val exact = System.getProperty("os.name")?.startsWith("Mac") == true && System.getProperty("os.arch") == "aarch64"
        val diff = expected.differing(first)
        val block = expected.maxBlockDelta(first)
        println("AINGCHECK-SNAPSHOT android now/$name mode=${if (exact) "exact" else "coarse"} ${first.width}x${first.height} diff=$diff block=$block")
        if (if (exact) diff != 0 else (diff < 0 || block > 64)) {
            first.writePng(File(mpRoot, "androidApp/build/aingcheck-snapshots/$name-actual.png"))
            fail("$name: 골든과 다르다(diff=$diff block=$block)")
        }
        val baseline = render(width, height, other)
        val negative = first.differing(baseline)
        println("AINGCHECK-SNAPSHOT-NEGATIVE android now/$name diff=$negative block=${first.maxBlockDelta(baseline)}")
        assertFalse("$name: 캐릭터만 다른 카드인데 같은 픽셀 — 비교가 내용을 못 본다", negative == 0)
        assertTrue("$name: 기준선 차이 ${negative}px — 한 군데만 달라야 한다", negative in 1 until first.argb.size / 10)
        assertTrue("$name: 굵은 대조가 한 군데 다른 장면을 못 잡는다", first.maxBlockDelta(baseline) > 64)
    }

    @Test fun nowPhoneLight() = check("now-phone-light", 360.dp, 760.dp, dark = false)

    @Test fun nowPhoneDark() = check("now-phone-dark", 360.dp, 760.dp, dark = true)

    @Test @Config(qualifiers = "w600dp-h960dp-xhdpi")
    fun nowTabletLight() = check("now-sw600dp-light", 600.dp, 900.dp, dark = false)

    private companion object {
        const val TAG = "aingcheck-now"
    }
}
