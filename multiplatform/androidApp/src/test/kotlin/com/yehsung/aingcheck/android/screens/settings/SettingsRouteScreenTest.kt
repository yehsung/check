// 원본: Sources/CheckMobileKit/Me/MeSettingsView.swift @ 3bd04bd (설정 화면 — 차단한 사람 · 계정 삭제는 화면만 연다 · 화면 모드 고르기 · 로그아웃 확인)
//
// 설정 껍데기(Android)를 Robolectric 위 Compose 로 띄워 누름이 제 길로 가는지 잰다: 차단한 사람 · 계정 삭제 행은 열기 콜백을 **한 번** 부른다
// (계정 삭제는 이 화면에서 삭제를 부르지 않는다) · 화면 모드 행은 저장값을 바꾼다 · 로그아웃은 확인 대화상자를 먼저 띄운다.
package com.yehsung.aingcheck.android.screens.settings

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.text.BlockReportText
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.stores.me.DrawableCharacterSource
import com.yehsung.aingcheck.core.stores.me.MeContext
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.wire.models.PushPrefs
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import com.yehsung.aingcheck.ui.screens.settingscommon.AppearanceStore
import com.yehsung.aingcheck.ui.screens.settingscommon.SettingsTags
import com.yehsung.aingcheck.ui.theme.AingAppearanceMode
import com.yehsung.aingcheck.ui.theme.AingTheme
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpStatusCode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h740dp-xhdpi")
class SettingsRouteScreenTest {
    @get:Rule
    val compose = createComposeRule()

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

    private fun meStore(): MeStore {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val session = SessionStore(
            service = SupabaseWorkService(
                projectURL = "https://golden.invalid",
                anonKey = "stub",
                client = HttpClient(MockEngine { respond("", HttpStatusCode.NotFound) }) { SupabaseWorkService.clientConfig(this) },
                clock = { SessionClock.demoInstant },
                text = RulesWireTextRules,
                newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
            ),
            vault = InMemoryTokenVault(),
            prefs = Prefs(),
            appInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 16"),
            installationIdentity = object : InstallationIdentity {
                override fun installationId(): String? = null
            },
            clock = SessionClock.fixed(SessionClock.demoInstant),
            instanceGuard = object : SingleInstanceGuard {
                override fun tryAcquire(): Boolean = true
                override fun release() {}
            },
            parentScope = scope,
        )
        return MeStore(MeContext(session), scope, DrawableCharacterSource.of(setOf("aing")))
    }

    private val port = object : PushSettingsPort {
        override val prefs: StateFlow<PushPrefs?> = MutableStateFlow(null)
        override suspend fun save(prefs: PushPrefs): PushPrefs? = null
    }

    @Test
    fun rowsOpenTheirScreensOnceAndAppearancePersists() {
        val prefs = Prefs()
        val appearance = AppearanceStore(prefs)
        var blocked = 0
        var deletion = 0
        compose.setContent {
            AingTheme(dark = false) {
                SettingsRouteScreen(meStore(), appearance, PushPrefsSaves(port, CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)), prefs, openBlockedPeople = { blocked += 1 }, openAccountDeletion = { deletion += 1 })
            }
        }
        compose.onNodeWithText(BlockReportText.blockedListTitle).performScrollTo().performClick()
        compose.onNodeWithTag(SettingsTags.ACCOUNT_DELETION_ROW).performScrollTo().performClick()
        compose.waitForIdle()
        assertEquals(1, blocked)
        assertEquals("계정 삭제 행은 삭제 화면을 열기만 한다", 1, deletion)

        compose.onNodeWithTag(SettingsTags.appearance(AingAppearanceMode.Light.storedValue)).performScrollTo().performClick()
        compose.waitForIdle()
        assertEquals(AingAppearanceMode.Light, appearance.mode)
        assertEquals("light", prefs.getString(AingAppearanceMode.STORAGE_KEY))

        // 로그아웃: 확인 대화상자를 먼저(되돌릴 수 없는 쪽은 아니지만 iOS 와 같이 한 번 묻는다).
        compose.onNodeWithTag(SettingsTags.SIGN_OUT).performScrollTo().performClick()
        compose.onNodeWithText(MeText.signOutConfirmTitle).assertExists()
    }
}
