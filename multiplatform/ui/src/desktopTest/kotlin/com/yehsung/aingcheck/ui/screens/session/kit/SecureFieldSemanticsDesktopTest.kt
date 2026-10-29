// 원본: Sources/CheckMobileKit/Session/MobileSessionViews.swift @ 3bd04bd (비밀번호 칸 — SecureField 는 접근성에 평문을 내보내지 않는다)
//
// 8차 e2e: 로그인 비밀번호 칸 입력 뒤 uiautomator dump 의 EditText text 가 평문이었다(BasicSecureTextField 가 EditableText 에
// 평문을 싣는다 — Compose 1.12.1). AingTextInput(secure) 의 semantics 를 재서 접근성이 읽는 글(EditableText · Text ·
// ContentDescription)에 평문이 없고 비밀번호 표시(Password)는 남는지 본다(java.awt.headless=true).
// 기준선(다른 입력): 같은 글을 넣은 보통 칸(secure=false)은 EditableText 가 평문이다 — 두 결과가 갈려야 시험이 뜻이 있다.
package com.yehsung.aingcheck.ui.screens.session.kit

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.setTextAndPlaceCursorAtEnd
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsConfiguration
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class)
class SecureFieldSemanticsDesktopTest {
    @BeforeTest
    fun headless() {
        System.setProperty("java.awt.headless", "true")
    }

    private val secret = "aing2026"

    /** 접근성 서비스가 글로 읽는 자리 전부(EditableText · Text · ContentDescription)를 한 줄로. */
    private fun accessibleStrings(config: SemanticsConfiguration): List<String> =
        listOfNotNull(config.getOrNull(SemanticsProperties.EditableText)?.text) +
            config.getOrNull(SemanticsProperties.Text).orEmpty().map { it.text } +
            config.getOrNull(SemanticsProperties.ContentDescription).orEmpty()

    private fun fieldConfig(secure: Boolean, state: TextFieldState, block: (() -> SemanticsConfiguration) -> Unit) =
        runComposeUiTest {
            setContent {
                AingTheme(dark = false) {
                    Box(Modifier.size(360.dp, 80.dp)) {
                        AingTextInput(state = state, placeholder = "비밀번호", secure = secure, tag = "pw")
                    }
                }
            }
            block {
                waitForIdle()
                onNode(androidx.compose.ui.test.hasTestTag("pw")).fetchSemanticsNode().config
            }
        }

    @Test
    fun secureFieldNeverExposesPlaintextToAccessibility() {
        val state = TextFieldState(secret)
        fieldConfig(secure = true, state = state) { config ->
            val first = config()
            assertTrue(first.contains(SemanticsProperties.Password), "비밀번호 의미(password)는 남는다")
            assertEquals("•".repeat(secret.length), first.getOrNull(SemanticsProperties.EditableText)?.text)
            accessibleStrings(first).forEach { assertFalse(it.contains(secret), "접근성 글에 평문: $it") }

            // 글이 바뀌면 가린 글도 따라 바뀐다(semantics 읽기가 상태를 구독한다) — 한 칸 늘린 평문도 새지 않는다.
            state.setTextAndPlaceCursorAtEnd("${secret}x")
            val second = config()
            assertEquals("•".repeat(secret.length + 1), second.getOrNull(SemanticsProperties.EditableText)?.text)
            accessibleStrings(second).forEach { assertFalse(it.contains(secret), "접근성 글에 평문: $it") }
        }
    }

    @Test
    fun plainFieldBaselineExposesItsText() {
        fieldConfig(secure = false, state = TextFieldState(secret)) { config ->
            val c = config()
            assertFalse(c.contains(SemanticsProperties.Password))
            assertEquals(secret, c.getOrNull(SemanticsProperties.EditableText)?.text)
        }
    }

    @Test
    fun maskCountsCodePointsNotChars() {
        assertEquals("", secureAccessibilityText(""))
        assertEquals("••", secureAccessibilityText("a😀"))
        assertEquals("•".repeat(8), secureAccessibilityText(secret))
    }
}
