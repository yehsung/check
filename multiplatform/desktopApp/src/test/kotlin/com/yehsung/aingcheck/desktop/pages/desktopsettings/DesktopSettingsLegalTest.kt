// W-13 #10 · W-12(11.12·10.5.1·10.5.2) — PC 설정에 이용약관·개인정보 처리방침 링크와 동의 철회 스위치가 보이고, 링크가 그 주소를 연다.
package com.yehsung.aingcheck.desktop.pages.desktopsettings

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.hasAnyDescendant
import androidx.compose.ui.test.hasAnySibling
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.runComposeUiTest
import com.yehsung.aingcheck.core.session.app.AppLinks
import com.yehsung.aingcheck.desktop.pages.aitokens.AiToolConsentText
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

@OptIn(ExperimentalTestApi::class)
class DesktopSettingsLegalTest {
    @Test
    fun `약관 링크 둘이 보이고 각자 제 주소를 연다`() = runComposeUiTest {
        val opened = mutableListOf<String>()
        val deps = DesktopSettingsDeps(DesktopSettingsStore(InMemoryDesktopKeyValueStore()), null, null, openUrl = { opened += it })
        setContent { AingTheme(dark = false) { DesktopSettingsPageContent(deps, onBack = {}) } }
        onNodeWithText(DesktopSettingsText.TITLE).assertExists()
        onNodeWithText(DesktopSettingsText.TERMS).performClick()
        onNodeWithText(DesktopSettingsText.PRIVACY).performClick()
        assertEquals(listOf(AppLinks.termsOfService, AppLinks.privacyPolicy), opened)
    }

    @Test
    fun `동의 철회 스위치 — 켠 동의를 설정에서 끄면 저장소가 거절로`() = runComposeUiTest {
        val settings = DesktopSettingsStore(InMemoryDesktopKeyValueStore())
        settings.setTokenUsageCollect(true)
        setContent { AingTheme(dark = false) { DesktopSettingsPageContent(DesktopSettingsDeps(settings, null, null), onBack = {}) } }
        onNodeWithText(AiToolConsentText.TITLE).assertExists()
        // 스위치는 제목 글자 묶음(Column)의 형제다(공용 ToggleRow).
        val consentSwitch = onNode(isToggleable() and hasAnySibling(hasAnyDescendant(hasText(AiToolConsentText.TITLE)) or hasText(AiToolConsentText.TITLE)))
        consentSwitch.assertIsOn()
        consentSwitch.performClick()
        waitForIdle()
        consentSwitch.assertIsOff()
        assertFalse(settings.tokenUsageCollect.value, "철회가 저장소에 안 닿았다")
    }
}
