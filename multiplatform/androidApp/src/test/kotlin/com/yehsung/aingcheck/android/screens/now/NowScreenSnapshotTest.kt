// 원본: Sources/CheckMobileKit/Now/NowTab.swift @ 3bd04bd (데모 장면 now — 새벽(나) 폰에서 근무 중 · 우리 팀 · 다른 팀 · 할 일)
// 원본: Sources/CheckMobileKit/Demo/MobileDemo.swift @ 3bd04bd (데모 픽스처 규칙 — ui 시험 ScreenHarness 와 같은 규칙의 앱 모듈 판)
//
// G §2-3 W3-a ① Roborazzi: 지금 탭 — 폰(밝음 · 어두움) · sw600dp. 지금 탭은 Android 전용 화면(androidApp …/screens/now)이라 골든도
// 이 갈래 소유 자리(이 폴더의 golden/)에 둔다. 판정은 부품·화면 스냅숏과 같다: 두 번 그려 같다 · 골든과 같다(기록 기계 픽셀 그대로, 다른
// 러너 굵은 대조) · 한 군데 다른 장면(착용 캐릭터만 다른 카드)은 다르다. 기록은 AINGCHECK_SNAPSHOT_RECORD=1(그 실행은 실패로 끝난다).
//
// 근무 중 줄 '집중' 칩(판 7 · 대표 답 #d_6A32rmcoJZZd "말 걸 수 있는 줄 전부" — ios-1017-int 1776440d NowWorkingRow): 민트(우리 팀 — 아이폰 데모와 같은
// 사람) · 하늘(다른 팀)이 집중을 켠 명부. 근무 중 절은 화면 한 장 아래라 절만 따로 찍는다. 출처는 폰 조립과 같은 줄(NowStore.focusedPeerIDsSource =
// MessagesStore.focusedPeerIDs)이고, 음성 기준선은 게이트가 꺼진 메시지 스토어(Windows 조립 — 같은 명부인데 칩이 없다)다.
package com.yehsung.aingcheck.android.screens.now

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.assertCountEquals
import com.yehsung.aingcheck.core.stores.messages.MessagesFocusText
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.filterToOne
import androidx.compose.ui.test.hasAnyDescendant
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import android.app.Application
import android.content.Intent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import androidx.test.core.app.ApplicationProvider
import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.achievements.HeaderStreakCopy
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionPrefsKeys
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.SessionVaultKeys
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.AppLinks
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.NaturalKoNameCollation
import com.yehsung.aingcheck.core.stores.characters.AppUserCharacterStore
import com.yehsung.aingcheck.core.stores.now.NowStore
import com.yehsung.aingcheck.core.stores.now.NowText
import com.yehsung.aingcheck.core.stores.now.NowTodoStorage
import com.yehsung.aingcheck.core.stores.now.NowWorkOrigin
import com.yehsung.aingcheck.core.stores.now.todo.JvmTodoFileSystem
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.nav.TabsNavHost
import com.yehsung.aingcheck.android.screens.session.W3aScreenDeps
import com.yehsung.aingcheck.core.wire.models.AppUserCharacterDirectory
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
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavHostController
import androidx.navigation.compose.rememberNavController
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
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

    /** 명단 장면: 데모 팀원 하나를 쉬는 사람으로 바꾼다(근무 쪽에 있던 팀원이 쉬는 묶음으로 옮겨 가는 것을 잰다). */
    private var offWorkMate: String? = null

    /** 입구 장면: 팀 전원을 쉬는 사람으로(iOS 데모 `now/team/entry-off`). */
    private var allOffWork = false

    /** 명단 상태 장면: 팀 상태 응답을 통째로 바꾼다(iOS 데모 `now/team/empty` · `failed`). */
    private var statusOverride: Pair<Int, String>? = null

    /** 무소속 장면(iOS 데모 `now/team/noteam`). */
    private var teamless = false

    /** 명부(app_user_directory)에서 집중을 켠 사람(판 7 — 저장소 데모 픽스처에는 아직 focus_mode 칸이 없어 여기서 얹는다). */
    private var focusIDs: Set<String> = emptySet()

    private val fixtures = File(repoRoot, "Sources/CheckMobileKit/Demo/Fixtures").walkTopDown().filter { it.isFile && it.name.endsWith(".json") }.map { f ->
        val rel = f.relativeTo(File(repoRoot, "Sources/CheckMobileKit/Demo/Fixtures")).invariantSeparatorsPath
        val scenario = rel.split('/').dropLast(1).lastOrNull { it.startsWith("_") }?.drop(1)
        val parts = f.name.removeSuffix(".json").split('@', limit = 2)
        Fixture(parts[0], parts.getOrNull(1), scenario, f.readText())
    }.toList()

    private data class Fixture(val key: String, val needle: String?, val scenario: String?, val text: String)

    /** client_release 의 최신 빌드를 덮는다(새 버전 안내 장면). null = 데모 픽스처(latest_build 1 = 이 빌드 — 안내 없음). */
    @Volatile
    private var latestBuildOverride: Long? = null

    /** Swift `MobileDemoFixtures.response`(장면 `now`) — ui 시험 DemoFixtures 와 같은 규칙. */
    private fun respond(method: String, path: String, query: String, body: String): Pair<Int, String> {
        if (path.endsWith("/rpc/client_release")) {
            latestBuildOverride?.let { return 200 to """{"status":"ok","platform":"android","min_build":1,"latest_build":$it}""" }
        }
        val m = method.lowercase()
        val seg = path.split('/').filter { it.isNotEmpty() }
        val key = when {
            seg.size >= 4 && seg[0] == "rest" && seg[2] == "rpc" -> "rpc.${seg[3]}"
            seg.size >= 3 && seg[0] == "rest" -> "rest.${seg[2]}.$m"
            seg.size >= 3 && seg[0] == "auth" -> (listOf("auth") + seg.drop(2) + m).joinToString(".")
            else -> "unknown.$m"
        }
        if (key == "rest.work_statuses.get") statusOverride?.let { return it }
        if (key == "rest.memberships.get" && teamless) return 200 to "[]"
        val hay = "$body&$query"
        val hit = fixtures.filter { it.key == key && (it.scenario == null || it.scenario == "now") && (it.needle == null || hay.contains(it.needle)) }
            .sortedWith(compareByDescending<Fixture> { if (it.scenario != null) 1 else 0 }.thenByDescending { it.needle?.length ?: -1 }).firstOrNull()
            ?: return 404 to """{"code":"PGRST202","message":"Could not find the function public.$key"}"""
        val parsed = runCatching { Json.parseToJsonElement(hit.text) }.getOrNull()
        if (parsed is JsonObject && parsed["__status"] != null) return (parsed["__status"]!!.jsonPrimitive.intOrNull ?: 500) to (parsed["__body"]?.toString() ?: "{}")
        if (key == "rpc.app_user_directory" && focusIDs.isNotEmpty()) {
            val rows = requireNotNull(parsed as? JsonArray).map { row ->
                val o = row.jsonObject
                JsonObject(o + ("focus_mode" to JsonPrimitive(o["user_id"]?.jsonPrimitive?.content in focusIDs)))
            }
            return 200 to JsonArray(rows).toString()
        }
        val mate = offWorkMate
        if (key == "rest.work_statuses.get" && (mate != null || allOffWork)) {
            val rows = requireNotNull(parsed as? JsonArray).map { row ->
                val o = row.jsonObject
                if (allOffWork || o["user_id"]?.jsonPrimitive?.content == mate) JsonObject(o + ("status" to JsonPrimitive("off_work"))) else row
            }
            return 200 to JsonArray(rows).toString()
        }
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

    private fun check(name: String, width: Dp, height: Dp, dark: Boolean, streakDays: Long? = null) {
        load()
        store.streakDaysSource = { streakDays }
        assertTrue("데모 장면: 새벽(나)이 근무 중이고 할 일이 서야 한다", store.myCard(clock.now())?.isWorking == true && store.todoRows().main.isNotEmpty())
        val scene: @Composable () -> Unit = { Frame(dark) { NowScreen(store, phoneWork, characterID = null, onTalk = {}, onEditGoal = {}, onOpenUpdate = {}) } }
        val other: @Composable () -> Unit = { Frame(dark) { NowScreen(store, phoneWork, characterID = "fox", onTalk = {}, onEditGoal = {}, onOpenUpdate = {}) } }
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

    /**
     * 명단 골든(밝음 · 어두움): 쉬는 사람 줄까지 그려져야 한다. 음성 기준선은 착용 캐릭터 표를 뺀 판 — 얼굴을 안 보는 비교면 같은 픽셀이 된다.
     */
    private fun checkRoster(name: String, dark: Boolean) {
        offWorkMate = ROSTER_OFF_MATE
        load()
        val roster = requireNotNull(store.teamRoster(clock.now()))
        assertTrue("쉬는 사람도 명단에 선다", roster.resting.any { it.id == ROSTER_OFF_MATE })
        assertFalse("지금 근무 중 절은 쉬는 사람을 뺀다", store.workingPeople(clock.now()).any { it.id == ROSTER_OFF_MATE })
        val scene: @Composable () -> Unit = { Frame(dark) { TeamRosterScreen(store, onBack = {}) } }
        val noFaces: @Composable () -> Unit = {
            AingTheme(dark = dark) {
                CompositionLocalProvider(LocalScreenTicking provides false, LocalScreenArt provides art, LocalAppUserCharacters provides AppUserCharacterDirectory(CharacterArt.portraitIds)) {
                    TeamRosterScreen(store, onBack = {})
                }
            }
        }
        val first = render(360.dp, 760.dp, scene)
        assertEquals("$name: 두 번 그린 장면이 다르다", 0, first.differing(render(360.dp, 760.dp, scene)))
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
        val baseline = render(360.dp, 760.dp, noFaces)
        val negative = first.differing(baseline)
        println("AINGCHECK-SNAPSHOT-NEGATIVE android now/$name diff=$negative block=${first.maxBlockDelta(baseline)}")
        assertTrue("$name: 얼굴을 뺀 판과 같은 픽셀 — 비교가 얼굴을 못 본다", negative > 0)
    }

    @Test fun teamRosterPhoneLight() = checkRoster("team-roster-phone-light", dark = false)

    @Test fun teamRosterPhoneDark() = checkRoster("team-roster-phone-dark", dark = true)

    /** 부르는 자리: 지금 탭 [전체 보기] → NavGraph 목적지 → 명단 줄 · 뒤로. 스토어만 있고 화면에 안 붙는 일을 막는다. 빠르게 두 번 눌러도 한 장만 쌓여 뒤로 한 번에 돌아온다. */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun teamRosterOpensFromNowTabThroughNavGraph() {
        offWorkMate = ROSTER_OFF_MATE
        load()
        val messages = MessagesStore(context, scope, NaturalKoNameCollation)
        val deps = W3aScreenDeps(session, messages, store, phoneWork, characterID = { null }, rubyBalance = { null }, currentBuild = 1)
        runComposeUiTest {
            lateinit var nav: NavHostController
            setContent { Frame(false) { nav = rememberNavController(); TabsNavHost(nav, screens = deps) } }
            waitForIdle()
            onAllNodes(hasScrollAction()).filterToOne(hasAnyDescendant(hasTestTag(NowTags.TEAM_ROSTER_ENTRY))).performScrollToNode(hasTestTag(NowTags.TEAM_ROSTER_ENTRY))
            onNodeWithTag(NowTags.TEAM_ROSTER_ENTRY).assertIsDisplayed()
            onNodeWithText(NowText.teamRosterSeeAll, useUnmergedTree = true).assertIsDisplayed()
            onNodeWithTag(TeamRosterTags.SCREEN).assertDoesNotExist()
            onNodeWithTag(NowTags.TEAM_ROSTER_ENTRY).performTouchInput {
                click()
                advanceEventTime(50)
                click()
            }
            waitForIdle()
            onNodeWithTag(TeamRosterTags.SCREEN).assertExists()
            // 줄은 톡백에 한 덩이다 — 글자 노드가 없어 문장으로 잰다(막대 · 글자 모양은 골든이 본다).
            onNodeWithTag(TeamRosterTags.row(ROSTER_OFF_MATE)).assert(hasContentDescription("쉬는 중", substring = true))
            assertEquals(true, nav.currentDestination?.hasRoute(Dest.TeamRoster::class))
            onNodeWithTag(TeamRosterTags.BACK).performClick()
            waitForIdle()
            onNodeWithTag(TeamRosterTags.SCREEN).assertDoesNotExist()
            assertEquals(true, nav.currentDestination?.hasRoute(Dest.NowHome::class))
        }
    }

    /** 우리 팀에 근무 중인 사람이 없으면 입구가 절 머리로 옮겨 "우리 팀 전체 보기"라고 말한다. "다른 팀" 줄에는 붙지 않는다. */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun teamRosterEntryMovesToSectionHeaderWhenNoTeammateWorks() {
        allOffWork = true
        load()
        assertTrue("장면: 근무 중인 팀원이 없다", store.workingPeople(clock.now()).none { it.isTeammate })
        var opened = 0
        runComposeUiTest {
            setContent { Frame(false) { NowScreen(store, phoneWork, characterID = null, onTalk = {}, onEditGoal = {}, onOpenUpdate = {}, onOpenTeamRoster = { opened += 1 }) } }
            waitForIdle()
            onAllNodes(hasScrollAction()).filterToOne(hasAnyDescendant(hasTestTag(NowTags.TEAM_ROSTER_ENTRY))).performScrollToNode(hasTestTag(NowTags.TEAM_ROSTER_ENTRY))
            onNodeWithText("우리 팀 전체 보기", useUnmergedTree = true).assertIsDisplayed()
            onNodeWithText("전체 보기", useUnmergedTree = true).assertDoesNotExist()
            onNodeWithTag(NowTags.TEAM_ROSTER_ENTRY).performClick()
            waitForIdle()
            assertEquals(1, opened)
        }
    }

    /** 입구는 명단을 받았을 때만 — 무소속이면 지금 탭에 입구가 없고, 명단 화면은 무소속 안내를 말한다. */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun teamRosterNoTeamState() {
        teamless = true
        load()
        assertTrue("장면: 무소속", store.hasNoTeam)
        runComposeUiTest {
            var showsRoster by mutableStateOf(false)
            setContent {
                Frame(false) {
                    if (showsRoster) TeamRosterScreen(store, onBack = {})
                    else NowScreen(store, phoneWork, characterID = null, onTalk = {}, onEditGoal = {}, onOpenUpdate = {})
                }
            }
            waitForIdle()
            onNodeWithTag(NowTags.TEAM_ROSTER_ENTRY).assertDoesNotExist()
            showsRoster = true
            waitForIdle()
            onNodeWithText("팀에 속해 있지 않아요").assertIsDisplayed()
            onNodeWithText("지금 탭에서 팀 코드로 합류하거나 새 팀을 만들 수 있어요").assertIsDisplayed()
        }
    }

    /** 팀원이 한 명도 없는 응답: 요약은 서고 빈 줄이 그 아래. */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun teamRosterEmptyState() {
        statusOverride = 200 to "[]"
        load()
        runComposeUiTest {
            setContent { Frame(false) { TeamRosterScreen(store, onBack = {}) } }
            waitForIdle()
            onNodeWithText("아잉 데모팀 · 1인당 주 40시간").assertIsDisplayed()
            onNodeWithText("아직 명단에 보일 팀원이 없어요").assertIsDisplayed()
            onNodeWithText("근무 중").assertDoesNotExist()
            onNodeWithText("쉬는 중").assertDoesNotExist()
        }
    }

    /** 팀 상태를 한 번도 못 받았다: 빈 명단이라 말하지 않고 실패 줄과 [다시 시도] · 지금 탭에 입구가 없다. */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun teamRosterFailedState() {
        statusOverride = 503 to """{"message":"upstream"}"""
        load()
        assertEquals(false, store.showsTeamRosterEntry)
        runComposeUiTest {
            setContent { Frame(false) { TeamRosterScreen(store, onBack = {}) } }
            waitForIdle()
            onNodeWithText("팀 명단을 불러오지 못했어요").assertIsDisplayed()
            onNodeWithText("다시 시도").assertIsDisplayed()
            onNodeWithText("아직 명단에 보일 팀원이 없어요").assertDoesNotExist()
        }
    }

    /** 절 머리 · 사람 수 · 내 줄이 "나"를 말한다. 차단은 조립 시험(feature/phone)과 스토어 시험이 잰다. */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun teamRosterGroupsAndSpokenRows() {
        offWorkMate = ROSTER_OFF_MATE
        load()
        val roster = requireNotNull(store.teamRoster(clock.now()))
        runComposeUiTest {
            setContent { Frame(false) { TeamRosterScreen(store, onBack = {}) } }
            waitForIdle()
            onNodeWithText("근무 중").assertIsDisplayed()
            onNodeWithText("${roster.working.size}명").assertExists()
            val mine = roster.working.first { it.isMe }
            onNodeWithTag(TeamRosterTags.row(mine.id)).assert(hasContentDescription("${mine.name}, 나, 근무 중", substring = true))
        }
    }

    /** 팀 만든 직후 코드 카드: 지금 탭 맨 위에 서고 코드 · 복사가 보이며 [확인]으로 사라진다. 스토어 값 없이는 안 선다. */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun createdTeamCardShowsTheCodeUntilConfirmed() {
        load()
        runComposeUiTest {
            setContent { Frame(false) { NowScreen(store, phoneWork, characterID = null, onTalk = {}, onEditGoal = {}, onOpenUpdate = {}) } }
            waitForIdle()
            onNodeWithTag(NowTags.CREATED_TEAM_CARD).assertDoesNotExist()
            runBlocking(dispatcher) { store.teamJoin.onTeamCreated!!.invoke("X7K2M9Q4") }
            waitForIdle()
            onNodeWithTag(NowTags.CREATED_TEAM_CARD).assertIsDisplayed()
            onNodeWithText("팀이 만들어졌어요").assertIsDisplayed()
            onNodeWithText("X7K2M9Q4").assertIsDisplayed()
            onNodeWithText("팀원에게 이 코드를 전달하세요").assertIsDisplayed()
            onNodeWithText("복사").assertIsDisplayed().performClick()
            waitForIdle()
            onNodeWithText("복사됨").assertIsDisplayed()
            onNodeWithTag(NowTags.CREATED_TEAM_CONFIRM).performClick()
            waitForIdle()
            onNodeWithTag(NowTags.CREATED_TEAM_CARD).assertDoesNotExist()
            assertEquals(null, store.createdTeamCode)
        }
    }

    // ---------------------------------------------------------------- 새 버전 안내(원본: Tests/CheckMobileKitTests/V1016UpdateNoticeTests.swift 소스 계약의 뜻 — 여기선 진짜 화면으로 잰다)

    private fun checkNotice(name: String, dark: Boolean) {
        latestBuildOverride = 2
        check(name, 360.dp, 760.dp, dark)
    }

    /** 맨 위 한 줄 · 틴트 단추 · X. 기준선(캐릭터만 다른 장면)은 check 가 잰다. */
    @Test fun nowUpdateNoticeLight() = checkNotice("now-update-notice-light", dark = false)

    @Test fun nowUpdateNoticeDark() = checkNotice("now-update-notice-dark", dark = true)

    /** 데모 픽스처(latest_build 1 = 이 빌드)는 안내를 띄우지 않는다. */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun demoFixtureShowsNoNotice() {
        load()
        assertFalse("데모 빌드에 안내가 떴다", store.showsUpdateNotice)
        runComposeUiTest {
            setContent { Frame(false) { NowScreen(store, phoneWork, characterID = null, onTalk = {}, onEditGoal = {}, onOpenUpdate = {}) } }
            waitForIdle()
            onNodeWithTag(NowTags.UPDATE_NOTICE).assertDoesNotExist()
        }
    }

    @OptIn(ExperimentalTestApi::class)
    private fun loadNewer() {
        latestBuildOverride = 2
        load()
        assertTrue("전제: 더 높은 최신 빌드면 안내가 보인다", store.showsUpdateNotice)
    }

    /** [업데이트] 는 부른 자리의 목적지를 열고 줄은 남는다 · X 는 줄을 내리고 그 빌드를 앱 단위로 적는다. */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun updateOpensAndDismissHides() {
        loadNewer()
        var opened = 0
        runComposeUiTest {
            setContent { Frame(false) { NowScreen(store, phoneWork, characterID = null, onTalk = {}, onEditGoal = {}, onOpenUpdate = { opened += 1 }) } }
            waitForIdle()
            onNodeWithTag(NowTags.UPDATE_NOTICE).assertExists()
            onNodeWithText(NowText.updateNoticeTitle).assertExists()
            val noticeTop = onNodeWithTag(NowTags.UPDATE_NOTICE).getBoundsInRoot().top
            val statusTop = onNodeWithTag(NowTags.STATUS_CARD).getBoundsInRoot().top
            assertTrue("안내 줄이 상태 카드 뒤로 갔다", noticeTop < statusTop)
            onNodeWithContentDescription(NowText.updateNoticeDismiss).assertExists()
            onNodeWithTag(NowTags.UPDATE_OPEN).performClick()
            waitForIdle()
            assertEquals(1, opened)
            onNodeWithTag(NowTags.UPDATE_NOTICE).assertExists()
            onNodeWithTag(NowTags.UPDATE_DISMISS).performClick()
            waitForIdle()
            onNodeWithTag(NowTags.UPDATE_NOTICE).assertDoesNotExist()
        }
        assertEquals(2L, store.dismissedUpdateBuild)
        assertEquals(2L, prefs.getLong(NowStore.dismissedUpdateBuildKey))
    }

    /** 부른 자리(지금 탭 뿌리 NowHomeEntry): [업데이트] 가 AppLinks 의 Play 주소를 ACTION_VIEW 로 연다. */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun homeEntryOpensThePlayStoreAddress() {
        loadNewer()
        runComposeUiTest {
            setContent { Frame(false) { NowHomeEntry(store, phoneWork, characterID = null, open = {}, openRoute = {}) } }
            waitForIdle()
            onNodeWithTag(NowTags.UPDATE_OPEN).performClick()
            waitForIdle()
        }
        val started = Shadows.shadowOf(ApplicationProvider.getApplicationContext<Application>()).nextStartedActivity
        assertEquals(Intent.ACTION_VIEW, started.action)
        assertEquals(AppLinks.playStore, started.dataString)
    }

    /** 큰 글자: [업데이트] 가 제목 아래로 내려가 제목이 잘리지 않는다 · 작은 글자: 한 줄(대조군 — 같은 재기로 갈려야 한다). */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun largeTypeStacksTheButtonUnderTheTitle() {
        loadNewer()
        fun layout(fontScale: Float): Pair<Boolean, Boolean> {
            var result = false to false
            runComposeUiTest {
                setContent {
                    val base = LocalDensity.current
                    CompositionLocalProvider(LocalDensity provides Density(base.density, fontScale)) {
                        Frame(false) { NowScreen(store, phoneWork, characterID = null, onTalk = {}, onEditGoal = {}, onOpenUpdate = {}) }
                    }
                }
                waitForIdle()
                val title = onNodeWithText(NowText.updateNoticeTitle).getBoundsInRoot()
                val button = onNodeWithTag(NowTags.UPDATE_OPEN).getBoundsInRoot()
                val dismiss = onNodeWithTag(NowTags.UPDATE_DISMISS).getBoundsInRoot()
                result = (button.top >= title.bottom) to (dismiss.width >= 44.dp && dismiss.height >= 44.dp)
            }
            return result
        }
        assertEquals("글꼴 배율 1 은 한 줄이다", false to true, layout(1f))
        assertEquals("큰 글자에서 [업데이트] 가 제목 옆에 남았다 · 닫기 누름 영역은 44dp", true to true, layout(NowUpdateNoticeLayout.STACK_FONT_SCALE))
    }

    @Test fun nowPhoneLight() = check("now-phone-light", 360.dp, 760.dp, dark = false)

    @Test fun nowPhoneDark() = check("now-phone-dark", 360.dp, 760.dp, dark = true)

    // 연속 근무 칩(Swift V1017StreakChipTests · 데모 장면 streak 의 12일 @ 43ee564a). 칩이 없는 위 장면은 그림이 그대로여야 한다(칩 없는 서버).
    @Test fun nowStreakPhoneLight() = check("now-streak-phone-light", 360.dp, 760.dp, dark = false, streakDays = 12)

    @Test fun nowStreakPhoneDark() = check("now-streak-phone-dark", 360.dp, 760.dp, dark = true, streakDays = 12)

    /** 칩이 있는 카드와 없는 카드(같은 폭 · 글꼴 배율 [fontScale])의 재기. 값 null 이면 칩을 찾지 않는다. */
    private class StreakBounds(
        val cardHeight: Dp,
        val timerTop: Dp, val timerBottom: Dp, val timerRight: Dp, val timerWidth: Dp,
        val chip: androidx.compose.ui.unit.DpRect?,
    )

    @OptIn(ExperimentalTestApi::class)
    private fun streakBounds(days: Long?, width: Dp, fontScale: Float = 1f): StreakBounds {
        store.streakDaysSource = { days }
        var out: StreakBounds? = null
        runComposeUiTest {
            setContent {
                val base = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(base.density, fontScale)) {
                    Box(Modifier.size(width, 1400.dp)) {
                        Frame(false) { NowScreen(store, phoneWork, characterID = null, onTalk = {}, onEditGoal = {}, onOpenUpdate = {}) }
                    }
                }
            }
            waitForIdle()
            val timer = onNodeWithTag(NowTags.TIMER).getBoundsInRoot()
            out = StreakBounds(
                onNodeWithTag(NowTags.STATUS_CARD).getBoundsInRoot().height,
                timer.top, timer.bottom, timer.right, timer.width,
                if (days != null) onNodeWithTag(NowTags.STREAK_CHIP).getBoundsInRoot() else null,
            )
            if (days == null) onNodeWithTag(NowTags.STREAK_CHIP).assertDoesNotExist()
        }
        return requireNotNull(out)
    }

    /** Swift `viewContract`: 새 줄 · 새 절 없이 타이머 오른쪽 빈자리에 선다 — 카드 높이 그대로, 타이머 크기 그대로, 칩이 카드 안. */
    @Test
    fun streakChipSitsBesideTheTimerWithoutGrowingTheCard() {
        load()
        val without = streakBounds(null, 360.dp)
        val with = streakBounds(12, 360.dp)
        val chip = requireNotNull(with.chip)
        assertEquals("칩이 카드 높이를 늘렸다", without.cardHeight, with.cardHeight)
        assertEquals("칩이 타이머를 줄였다", without.timerWidth, with.timerWidth)
        assertTrue("칩이 타이머 오른쪽 빈자리에 없다", chip.left >= with.timerRight + 8.dp)
        assertTrue("칩이 타이머 줄 높이 안에 없다", chip.top >= with.timerTop && chip.bottom <= with.timerBottom)
        assertTrue("칩 높이 22dp 이상", chip.bottom - chip.top >= 22.dp)
        assertTrue("칩이 카드 안쪽 여백 밖으로 나갔다", chip.right <= 360.dp - 16.dp)
    }

    /** Swift `ViewThatFits` 둘째 갈래: 큰 글자로 한 줄에 안 들어가면 그때만 아래로 — 타이머는 칩 때문에 줄어들지 않는다. 대조군은 위 시험(같은 칩, 작은 글자는 한 줄). */
    @Test
    fun streakChipDropsBelowTheTimerOnlyWhenItDoesNotFit() {
        load()
        val without = streakBounds(null, 360.dp, fontScale = 1.6f)
        val with = streakBounds(12, 360.dp, fontScale = 1.6f)
        val chip = requireNotNull(with.chip)
        assertEquals("칩이 타이머를 줄였다", without.timerWidth, with.timerWidth)
        assertTrue("한 줄에 안 들어가는데 타이머 옆에 남았다", chip.top >= with.timerBottom)
        assertTrue("내려간 칩은 왼쪽 정렬이다", chip.left <= 360.dp - chip.right)
        assertTrue("내려갔을 때만 카드가 는다", with.cardHeight > without.cardHeight)
    }

    /** 값이 나중에 와도 칩이 선다(나 탭 조회가 지금 탭보다 늦다) · 값이 사라지면 내려간다 · 톡백은 한 문장, 느낌표 없이. */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun streakChipFollowsTheStoreAndReadsAsOneSentence() {
        load()
        var days by mutableStateOf<Long?>(null)
        store.streakDaysSource = { days }
        runComposeUiTest {
            setContent { Frame(false) { NowScreen(store, phoneWork, characterID = null, onTalk = {}, onEditGoal = {}, onOpenUpdate = {}) } }
            waitForIdle()
            onNodeWithTag(NowTags.STREAK_CHIP).assertDoesNotExist()
            days = 0
            waitForIdle()
            onNodeWithTag(NowTags.STREAK_CHIP).assertIsDisplayed()
            onNodeWithTag(NowTags.STREAK_CHIP).assert(hasContentDescription(HeaderStreakCopy.accessibilityLabel(0)))
            days = 3
            waitForIdle()
            onNodeWithContentDescription("연속 3일 근무").assertIsDisplayed()
            onNodeWithText("연속 3일 근무!", useUnmergedTree = true).assertIsDisplayed()
            onNodeWithTag(NowTags.STREAK_CHIP).assert(SemanticsMatcher.keyNotDefined(SemanticsActions.OnClick))
            days = null
            waitForIdle()
            onNodeWithTag(NowTags.STREAK_CHIP).assertDoesNotExist()
        }
    }

    @Test @Config(qualifiers = "w600dp-h960dp-xhdpi")
    fun nowTabletLight() = check("now-sw600dp-light", 600.dp, 900.dp, dark = false)

    // ---------------------------------------------------------------- 근무 중 줄 '집중' 칩(판 7 · 대표 답 #d_6A32rmcoJZZd)

    /** 메시지 스토어 둘(게이트 켬 = 폰 · 끔 = Windows)을 지금 탭에 잇고, 지금 탭은 [focusSource] 의 집합을 읽는다(폰 조립과 같은 줄). */
    private lateinit var focusOn: MessagesStore
    private lateinit var focusOff: MessagesStore
    private var focusSource: MessagesStore? = null

    private fun loadFocus() {
        focusIDs = setOf(FOCUS_TEAMMATE, FOCUS_OTHER)
        load()
        focusOn = MessagesStore(context, scope, NaturalKoNameCollation, focusSendGate = true).also { it.nowStore = store }
        focusOff = MessagesStore(context, scope, NaturalKoNameCollation).also { it.nowStore = store }
        focusSource = focusOn
        store.focusedPeerIDsSource = { focusSource?.focusedPeerIDs ?: emptySet() }
        val people = store.workingPeople(clock.now())
        assertEquals("장면: 집중 둘이 우리 팀 · 다른 팀 줄에 하나씩", setOf(true, false), people.filter { it.id in focusOn.focusedPeerIDs }.map { it.isTeammate }.toSet())
        assertEquals(setOf(FOCUS_TEAMMATE, FOCUS_OTHER), focusOn.focusedPeerIDs)
        assertEquals("게이트 끈 스토어(Windows)가 집중 집합을 냈다", emptySet<String>(), focusOff.focusedPeerIDs)
    }

    @Composable
    private fun WorkingOnly(dark: Boolean, source: MessagesStore, fontScale: Float?) {
        // 지금 탭이 읽을 메시지 스토어를 고른다 — 그리기 전에 정한다(같은 지금 탭 스토어 · 같은 명부, 집합의 출처만 다르다).
        focusSource = source
        val body: @Composable () -> Unit = {
            Frame(dark) {
                Column(Modifier.fillMaxSize().background(AingTheme.colors.background)) {
                    WorkingSection(store, phoneWorkWired = true, now = clock.now(), onTalk = {}, onOpenTeamRoster = {})
                }
            }
        }
        if (fontScale == null) {
            body()
        } else {
            val base = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(base.density, fontScale), content = body)
        }
    }

    private fun checkWorkingFocus(name: String, dark: Boolean, fontScale: Float? = null) {
        loadFocus()
        val scene: @Composable () -> Unit = { WorkingOnly(dark, focusOn, fontScale) }
        val other: @Composable () -> Unit = { WorkingOnly(dark, focusOff, fontScale) }
        val first = render(360.dp, 760.dp, scene)
        assertEquals("$name: 두 번 그린 장면이 다르다", 0, first.differing(render(360.dp, 760.dp, scene)))
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
        // 음성 기준선: 게이트 끈 스토어(Windows) — 같은 명부인데 칩 두 개만 없다.
        val baseline = render(360.dp, 760.dp, other)
        val negative = first.differing(baseline)
        println("AINGCHECK-SNAPSHOT-NEGATIVE android now/$name diff=$negative block=${first.maxBlockDelta(baseline)}")
        assertFalse("$name: 칩만 다른 장면인데 같은 픽셀 — 비교가 칩을 못 본다", negative == 0)
        assertTrue("$name: 기준선 차이 ${negative}px — 칩 자리만 달라야 한다", negative in 1 until first.argb.size / 10)
        assertTrue("$name: 굵은 대조가 칩만 다른 장면을 못 잡는다", first.maxBlockDelta(baseline) > 64)
    }

    @Test fun workingFocusPhoneLight() = checkWorkingFocus("now-working-focus-phone-light", dark = false)

    @Test fun workingFocusPhoneDark() = checkWorkingFocus("now-working-focus-phone-dark", dark = true)

    @Test fun workingFocusPhoneLargeFont() = checkWorkingFocus("now-working-focus-phone-large-font", dark = false, fontScale = 1.6f)

    /** 글꼴 '크게'(1.3 — iOS xxxLarge 쯤): 아직 한 줄 모양이다(검토 F5). 칩 · 배지 · 경과가 있어도 이름이 말줄임표만 남지 않는지 사람이 PNG 를 연다. */
    @Test fun workingFocusPhoneFont130() = checkWorkingFocus("now-working-focus-phone-font-130", dark = false, fontScale = 1.3f)

    /**
     * 큰 글자 모양의 기준(검토 F5): 줄을 쌓는 것은 iOS `NowWorkingRow` 의 `isAccessibilitySize` 갈래(AX 크기부터)다 — 이 화면 새 버전 안내 ·
     * 나 탭 AI 한도와 같은 1.5 자리. 1.0 · 1.3('크게' · iOS xxxLarge 쯤)은 판 7 전과 같은 한 줄 모양(우리 팀 경과가 이름 줄 오른쪽),
     * 1.5 · 1.6 은 쌓은 모양(경과가 이름 아래 줄)이다. 잰다: 민트(우리 팀 · 집중) 줄에서 경과 글자의 윗변이 이름 글자의 아랫변 아래인가.
     */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun workingRowStacksOnlyFromAccessibilitySizes() {
        loadFocus()
        val name = store.workingPeople(clock.now()).first { it.id == FOCUS_TEAMMATE }.name
        val inRow = hasAnyAncestor(hasTestTag(NowTags.workingRow(FOCUS_TEAMMATE)))
        // 경과 글자 = "근무 …째"(얼굴의 상태 점 "근무 중"과 가른다).
        val elapsed = SemanticsMatcher("우리 팀 경과") { node ->
            node.config.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.ContentDescription).orEmpty().any { it.startsWith("근무 ") && it.endsWith("째") }
        }
        fun stackedAt(scale: Float): Boolean {
            var stacked: Boolean? = null
            runComposeUiTest {
                setContent { WorkingOnly(false, focusOn, scale) }
                waitForIdle()
                val nameBox = onNode(hasText(name) and inRow, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
                val elapsedBox = onNode(elapsed and inRow, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
                stacked = elapsedBox.top >= nameBox.bottom
            }
            return requireNotNull(stacked)
        }
        assertEquals("보통 글자(1.0)는 한 줄 모양", false, stackedAt(1.0f))
        assertEquals("'크게'(1.3 — iOS xxxLarge 쯤)는 아직 한 줄 모양이어야 한다(iOS 는 AX 크기부터 쌓는다)", false, stackedAt(1.3f))
        assertEquals("접근성 크기(1.5)부터 쌓는다", true, stackedAt(1.5f))
        assertEquals("1.6 은 쌓은 모양", true, stackedAt(1.6f))
    }

    /**
     * 부르는 자리: 집중인 줄(우리 팀 민트 · 다른 팀 하늘)에만 칩이 서고, 이 줄은 조각을 하나씩 읽으므로 칩 자신이 "집중"이 아니라 "집중 중"으로 읽힌다.
     * 기준선: 집중 아닌 줄(라임 · 코랄)엔 없다 · 게이트 끈 스토어(Windows)는 같은 명부에서도 칩이 하나도 없다.
     */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun workingRowChipSpeaksAndFollowsTheMessagesStore() {
        loadFocus()
        fun chipIn(id: String) = hasContentDescription(MessagesFocusText.accessibility) and hasAnyAncestor(hasTestTag(NowTags.workingRow(id)))
        runComposeUiTest {
            setContent { WorkingOnly(false, focusOn, null) }
            waitForIdle()
            onNode(chipIn(FOCUS_TEAMMATE)).assertExists()
            onNode(chipIn(FOCUS_OTHER)).assertExists()
            onNode(chipIn(PLAIN_TEAMMATE)).assertDoesNotExist()
            onNode(chipIn(PLAIN_OTHER)).assertDoesNotExist()
            // 칩 글자 '집중'은 따로 읽히지 않는다(칩이 "집중 중" 한 마디로 읽힌다). TalkBack 이 읽는 트리(병합 트리 — clearAndSetSemantics 가 걷은
            // 자식은 빠진다)로 잰다. 병합하지 않은 시험 트리는 걷힌 자식도 그대로 보여 준다.
            onAllNodes(hasText(MessagesFocusText.personChip)).assertCountEquals(0)
            onAllNodes(hasContentDescription(MessagesFocusText.accessibility)).assertCountEquals(2)
        }
        runComposeUiTest {
            setContent { WorkingOnly(false, focusOff, null) }
            waitForIdle()
            onNodeWithTag(NowTags.workingRow(FOCUS_TEAMMATE)).assertExists()
            onAllNodes(hasContentDescription(MessagesFocusText.accessibility)).assertCountEquals(0)
        }
    }

    private companion object {
        const val TAG = "aingcheck-now"
        const val ROSTER_OFF_MATE = "d0000000-0000-4000-8000-000000000103"

        /** 집중 장면: 민트(우리 팀) · 하늘(다른 팀)이 켰다. 라임(우리 팀) · 코랄(다른 팀)은 기준선. */
        const val FOCUS_TEAMMATE = "d0000000-0000-4000-8000-000000000102"
        const val FOCUS_OTHER = "d0000000-0000-4000-8000-000000000202"
        const val PLAIN_TEAMMATE = "d0000000-0000-4000-8000-000000000103"
        const val PLAIN_OTHER = "d0000000-0000-4000-8000-000000000201"
    }
}
