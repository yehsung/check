// 원본: Tests/CheckMobileKitTests/MeTestSupport.swift @ 3bd04bd (나 탭 스토어 조립 · 스텁 서버 · 고정 시계 — 화면 시험판)
//
// 화면 시험 도우미: **진짜 나 탭 스토어(W2-c MeStore)** 를 데모 픽스처(Sources/CheckMobileKit/Demo/Fixtures/me — 복사 0, 제자리 읽기)로 채운다.
// 화면은 스토어를 그대로 받으므로(K8 — 스토어 연결까지가 이 갈래 몫, G §8-18 8) 스냅숏이 스토어 → 화면 경로를 통째로 지난다.
// 스토어 범위는 runTest 가 끝날 때 닫힌다 — 그 뒤 화면이 부르는 `charactersDidAppear` 같은 읽기는 닫힌 범위라 망에 닿지 않는다(봉인과 별개로 0).
package com.yehsung.aingcheck.ui.shop

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
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
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
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
import kotlin.test.assertEquals

/** 데모 픽스처 자리와 기준 시각. */
object MeScreenFixtures {
    const val ME = "Sources/CheckMobileKit/Demo/Fixtures/me"

    /** 데모 기준 시각 2026-09-17 14:05:00 KST — 픽스처 server_now_ms(1789621500000)와 같은 순간. */
    const val DEMO_EPOCH: Double = 1_789_621_500.0

    /** 번들 초상이 다 있는 집합(상점 번호 4) — ui CharacterArt 가 싣는 열한 캐릭터. */
    val allPortraits: Set<String> = setOf(
        "aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco",
        "fox", "ghost", "jellyfish", "robot", "shiba", "squirrel",
    )

    fun fixture(path: String): String = RepoFiles.readText("$ME/$path")

    val shopState: String get() = fixture("_me/rpc.shop_state.json")
    val achievements: String get() = fixture("_me/rpc.achievements_status.json")
    val weekly: String get() = fixture("_me/rpc.weekly_work_status.json")
    val equipped: String get() = fixture("rest.profiles.get@select=character.json")
    val giftPending: String get() = fixture("rpc.character_gift_pending@demo-gift.json")

    const val registerOK = """{"status":"ok","device_id":"dev-1","push_prefs":{"message":true,"gomoku_invite":true,"feedback_reply":true}}"""
}

/** 화면 장면 하나의 서버 답(픽스처 글자 — null 이면 그 덩어리를 읽지 않는다). */
data class MeScene(
    val shopState: String? = MeScreenFixtures.shopState,
    val achievements: String? = MeScreenFixtures.achievements,
    val weekly: String? = MeScreenFixtures.weekly,
    val equipped: String? = MeScreenFixtures.equipped,
    val giftPending: String? = null,
)

/**
 * 장면을 실은 나 탭 스토어 한 벌. 로그인 → 상점 · 착용 · 미션 · 이번 주 근무(· 생일 선물)를 읽은 뒤 돌려준다.
 * 경로 없는 요청이 있으면 실패한다(장면이 모르는 망 호출 0).
 */
@OptIn(ExperimentalCoroutinesApi::class)
fun loadedMeStore(scene: MeScene, drawable: Set<String> = MeScreenFixtures.allPortraits): MeStore {
    var out: MeStore? = null
    runTest {
        val unrouted = mutableListOf<String>()
        val engine = MockEngine(
            MockEngineConfig().apply {
                dispatcher = StandardTestDispatcher(testScheduler)
                addHandler { request ->
                    val entry = RecordedRequest(
                        method = request.method.value,
                        path = request.url.encodedPath,
                        query = request.url.parameters.entries().flatMap { (k, vs) -> vs.map { k to it } },
                        headers = request.headers.entries().associate { it.key to it.value },
                        bodyText = (request.body as? OutgoingContent.ByteArrayContent)?.bytes()?.decodeToString() ?: "",
                    )
                    val body = route(scene, entry)
                    if (body == null) unrouted += entry.key
                    respond(body ?: """{"message":"unrouted"}""", if (body == null) HttpStatusCode.fromValue(418) else HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
                }
            },
        )
        val clock = SessionClock { SwiftDate(MeScreenFixtures.DEMO_EPOCH + testScheduler.currentTime / 1000.0) }
        val storeJob = SupervisorJob()
        val storeScope = CoroutineScope(coroutineContext.minusKey(Job) + storeJob)
        backgroundScope.coroutineContext.job.invokeOnCompletion { storeJob.cancel() }
        val service = SupabaseWorkService(
            projectURL = "https://golden.invalid",
            anonKey = "stub-anon-key",
            client = HttpClient(engine) { SupabaseWorkService.clientConfig(this) },
            clock = { clock.now() },
            text = RulesWireTextRules,
            newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
        )
        val session = SessionStore(
            service = service,
            vault = InMemoryTokenVault(),
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
            parentScope = storeScope,
            newCleanupID = { "cleanup-1" },
        )
        val store = MeStore(
            context = MeContext(session, AppConfig(), RubyBalanceCell(), MeLinks.None),
            parentScope = storeScope,
            drawableCharacters = DrawableCharacterSource.of(drawable),
            computeContext = StandardTestDispatcher(testScheduler),
            newRequestID = { "AAAAAAAA-0000-4000-8000-000000000001" },
        )
        session.adoptSignedInSession(SupabaseSession("tok-user-1", "ref-user-1", "user-1"), "a@b.co")
        advanceUntilIdle()
        if (scene.shopState != null) store.loadShop()
        if (scene.equipped != null) store.loadEquippedCharacter()
        if (scene.achievements != null) store.loadAchievements()
        if (scene.weekly != null) store.loadWeeklyWork()
        if (scene.giftPending != null) store.loadCakeGift()
        advanceUntilIdle()
        assertEquals(emptyList(), unrouted, "장면이 모르는 요청")
        out = store
    }
    return requireNotNull(out)
}

private fun route(scene: MeScene, r: RecordedRequest): String? = when {
    r.rpcName == "register_device_fcm" -> MeScreenFixtures.registerOK
    r.method == "GET" && r.path == "/rest/v1/memberships" -> "[]"
    r.rpcName == "shop_state" -> scene.shopState
    r.rpcName == "achievements_status" -> scene.achievements
    r.rpcName == "weekly_work_status" -> scene.weekly
    r.rpcName == "character_gift_pending" -> scene.giftPending
    r.method == "GET" && r.path == "/rest/v1/profiles" && r.queryValue("select") == "character" -> scene.equipped
    else -> null
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

/** 장면 바꾸기 도우미: JSON 글자에서 한 조각을 바꾼다(바꿀 조각이 없으면 실패 — 조용히 같은 장면이 되지 않게). */
fun String.replacingOnce(old: String, new: String): String {
    val i = indexOf(old)
    require(i >= 0) { "장면에 바꿀 조각이 없다: $old" }
    return substring(0, i) + new + substring(i + old.length)
}
