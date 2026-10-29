// 원본: 7차 로컬 앱 e2e 결함(중) — 나 → 설정 → 알림 '메시지' 스위치 1회 탭 → 서버 push_prefs.message=false 인데 화면은 켜짐으로 돌아가고,
//       다시 눌러도 서버가 true 로 안 왔다(켜짐으로 보이는 스위치를 누르면 또 false 를 보낸다).
//
// 진짜 세션 스토어(SessionPushSettingsPort) + 가짜 서버(set_push_prefs 를 메인 supabase/migrations 의 마지막 정의대로 흉내: 아는 키의 boolean 만
// 병합하고 `{"status":"ok","push_prefs":{…, "chess_invite":…}}` 로 돌려준다) 위에 설정 껍데기를 Robolectric Compose 로 띄워
// 스위치를 두 번 누르고 **화면 스위치 = 서버 행** 을 잰다. 원인은 모델이 서버값을 StateFlow.value 로 읽어 Compose 가 바뀜을 몰랐던 것이다.
package com.yehsung.aingcheck.android.screens.settings

import android.Manifest
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.core.app.ApplicationProvider
import com.yehsung.aingcheck.android.push.NotificationChannels
import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.stores.me.DrawableCharacterSource
import com.yehsung.aingcheck.core.stores.me.MeContext
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.models.PushPrefs
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import com.yehsung.aingcheck.ui.screens.settingscommon.AppearanceStore
import com.yehsung.aingcheck.ui.screens.settingscommon.NotificationTags
import com.yehsung.aingcheck.ui.theme.AingTheme
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.util.Collections

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h740dp-xhdpi")
class NotificationPrefsRoundTripTest {
    @get:Rule
    val compose = createComposeRule()

    private val me = "d0000000-0000-4000-8000-000000000001"

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

    /** client_devices.push_prefs 한 행(서버 기본 — 넷 다 켬). */
    private val serverRow = Collections.synchronizedMap(linkedMapOf("message" to true, "gomoku_invite" to true, "feedback_reply" to true, "chess_invite" to true))
    private val sentMessage = Collections.synchronizedList(mutableListOf<Boolean?>())

    private fun rowJson(): String = synchronized(serverRow) { JsonObject(serverRow.mapValues { JsonPrimitive(it.value) }).toString() }

    private fun session(): SessionStore {
        val engine = MockEngine { request ->
            val path = request.url.encodedPath
            val body = (request.body as? OutgoingContent.ByteArrayContent)?.bytes()?.decodeToString() ?: ""
            fun json(text: String, status: Int = 200) = respond(text, HttpStatusCode.fromValue(status), headersOf(HttpHeaders.ContentType, "application/json"))
            when (path) {
                "/rest/v1/rpc/register_device_fcm" -> json("""{"status":"ok","device_id":"d","push_prefs":${rowJson()}}""")
                "/rest/v1/rpc/set_push_prefs" -> {
                    // 서버 정본(20261005160000 set_push_prefs): 아는 키의 boolean 만 `push_prefs || patch` 로 병합, 행 전체를 돌려준다.
                    val patch = Json.parseToJsonElement(body).jsonObject.getValue("p_prefs").jsonObject
                    sentMessage += (patch["message"] as? JsonPrimitive)?.booleanOrNull
                    for ((key, value) in patch) {
                        val flag = (value as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull ?: continue
                        if (key in serverRow) serverRow[key] = flag
                    }
                    json("""{"status":"ok","push_prefs":${rowJson()}}""")
                }
                "/rest/v1/memberships" -> json("[]")
                else -> json("{}", 404)
            }
        }
        return SessionStore(
            service = SupabaseWorkService(
                projectURL = "https://golden.invalid",
                anonKey = "stub",
                client = HttpClient(engine) { SupabaseWorkService.clientConfig(this) },
                clock = { SessionClock.demoInstant },
                text = RulesWireTextRules,
                newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
            ),
            vault = InMemoryTokenVault(),
            prefs = Prefs(),
            appInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 16"),
            installationIdentity = object : InstallationIdentity {
                override fun installationId(): String = "11111111-2222-4333-8444-555555555555"
            },
            clock = SessionClock.fixed(SessionClock.demoInstant),
            instanceGuard = object : SingleInstanceGuard {
                override fun tryAcquire(): Boolean = true
                override fun release() {}
            },
            parentScope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )
    }

    @Test
    fun messageSwitchFollowsTheServerRowBothWays() {
        val app = ApplicationProvider.getApplicationContext<android.app.Application>()
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        NotificationChannels.ensure(app)
        val session = session()
        session.adoptSignedInSession(SupabaseSession("access", "refresh", me), "rankme@example.invalid")
        val store = MeStore(MeContext(session), CoroutineScope(SupervisorJob() + Dispatchers.Unconfined), DrawableCharacterSource.of(setOf("aing")))
        val prefs = Prefs()
        compose.setContent {
            AingTheme(dark = false) {
                SettingsRouteScreen(store, AppearanceStore(prefs), SessionPushSettingsPort(session), prefs, openBlockedPeople = {}, openAccountDeletion = {})
            }
        }
        val messageSwitch = hasAnyAncestor(hasTestTag(NotificationTags.row("message"))) and isToggleable()
        compose.waitUntil(5_000) { session.pushPrefs != null }
        compose.onNode(messageSwitch).performScrollTo().assertIsOn()

        // 1회 탭: 서버 행이 꺼지면 화면 스위치도 꺼져 있어야 한다.
        compose.onNode(messageSwitch).performClick()
        compose.waitUntil(5_000) { sentMessage.size == 1 && session.pushPrefs?.message == false }
        compose.waitForIdle()
        assertEquals(false, serverRow["message"])
        compose.onNode(messageSwitch).assertIsOff()

        // 다시 탭: 꺼진 스위치를 켜면 서버 행이 다시 켜진다(같은 false 를 또 보내지 않는다).
        compose.onNode(messageSwitch).performClick()
        compose.waitUntil(5_000) { sentMessage.size == 2 && session.pushPrefs?.message == true }
        compose.waitForIdle()
        assertEquals("두 번째 탭은 켬을 보낸다", listOf<Boolean?>(false, true), sentMessage.toList())
        assertEquals(true, serverRow["message"])
        compose.onNode(messageSwitch).assertIsOn()
    }

    /** 서버값이 화면이 뜬 **뒤에** 와도(기기 등록 응답이 늦음) 잠긴 스위치가 풀리고 그 값을 그린다 — 껍데기가 서버값을 관찰한다. */
    @Test
    fun lateServerPrefsUnlockTheSwitch() {
        val app = ApplicationProvider.getApplicationContext<android.app.Application>()
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        NotificationChannels.ensure(app)
        val flow = MutableStateFlow<PushPrefs?>(null)
        val port = object : PushSettingsPort {
            override val prefs: StateFlow<PushPrefs?> = flow
            override suspend fun save(prefs: PushPrefs): PushPrefs? = null
        }
        val store = MeStore(MeContext(session()), CoroutineScope(SupervisorJob() + Dispatchers.Unconfined), DrawableCharacterSource.of(setOf("aing")))
        val prefs = Prefs()
        compose.setContent {
            AingTheme(dark = false) {
                SettingsRouteScreen(store, AppearanceStore(prefs), port, prefs, openBlockedPeople = {}, openAccountDeletion = {})
            }
        }
        val messageSwitch = hasAnyAncestor(hasTestTag(NotificationTags.row("message"))) and isToggleable()
        compose.onNode(hasTestTag(NotificationTags.row("message"))).performScrollTo()
        // 서버값을 모르면 잠긴다(누를 거리가 없는 Switch — 토글 의미가 붙지 않는다).
        compose.onNode(messageSwitch).assertDoesNotExist()
        flow.value = PushPrefs(message = false, gomokuInvite = true, feedbackReply = true)
        compose.waitForIdle()
        compose.onNode(messageSwitch).assertIsEnabled().assertIsOff()
    }
}
