// 다크 모드 · 글꼴 크기 · 화면 크기 · 언어 변경이 Activity 를 다시 만들지 않는다(매니페스트 configChanges) — 다시 만들면 화면 수명이 끊겨 끝난 판의 결과가 접히고 미니게임 판이 끝난다.
// 다시 안 만들면 화면이 스스로 따라와야 한다: Compose 는 뷰의 구성 변경으로 LocalConfiguration · LocalDensity 를 갈고, 색은 isSystemInDarkTheme → AingTheme, 시스템 막대는 MainActivity 의 barStyle 이 잇는다(SystemBarIconsConfigChangeTest).
package com.yehsung.aingcheck.android.shell

import android.content.res.Configuration
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.test.core.app.ApplicationProvider
import com.yehsung.aingcheck.android.app.AingApplication
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h740dp-xhdpi")
class ActivityConfigChangeTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    @Before
    fun placeholderShell() {
        ApplicationProvider.getApplicationContext<AingApplication>().container.usePlaceholderShell()
    }

    /** 실제 매니페스트로 판정한다(Robolectric 이 configChanges 를 보고 다시 만들지 onConfigurationChanged 를 부를지 고른다). */
    @Test
    fun configurationChangesDoNotRecreateTheActivity() {
        val controller = Robolectric.buildActivity(MainActivity::class.java).setup()
        val activity = controller.get()
        val changes = listOf<(Configuration) -> Unit>(
            { it.uiMode = (it.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or Configuration.UI_MODE_NIGHT_YES },
            { it.fontScale = 1.3f },
            { it.densityDpi = 480 },
            { it.setLocale(Locale.ENGLISH) },
            { it.keyboard = Configuration.KEYBOARD_QWERTY },
            { it.hardKeyboardHidden = Configuration.HARDKEYBOARDHIDDEN_NO },
        )
        for (change in changes) {
            val next = Configuration(activity.resources.configuration).also(change)
            controller.configurationChange(next)
            assertSame("구성 변경이 Activity 를 다시 만들었다: $next", activity, controller.get())
            assertFalse("구성 변경이 Activity 를 끝냈다: $next", activity.isFinishing)
        }
        controller.pause().stop().destroy()
    }

    /** 다시 안 만들어도 Compose 가 따라온다: 뷰가 구성 변경을 받으면 시스템 다크 판정과 글자 배율이 바뀐다(자원은 시스템이 갱신한다). */
    @Test
    fun composeFollowsAConfigurationChangeWithoutRecreation() {
        val controller = Robolectric.buildActivity(ComponentActivity::class.java).setup()
        val activity = controller.get()
        var dark: Boolean? = null
        var fontScale: Float? = null
        activity.setContent {
            val systemDark = isSystemInDarkTheme()
            val scale = LocalDensity.current.fontScale
            SideEffect {
                dark = systemDark
                fontScale = scale
            }
        }
        Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
        compose.waitForIdle()
        assertEquals(false, dark)
        assertEquals(1f, fontScale)

        RuntimeEnvironment.setQualifiers("+night")
        RuntimeEnvironment.setFontScale(1.3f)
        activity.window.decorView.dispatchConfigurationChanged(activity.resources.configuration)
        Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
        compose.waitForIdle()
        assertTrue("시스템 다크 전환을 안 따라온다", dark == true)
        assertEquals("글자 배율을 안 따라온다", 1.3f, fontScale)
        controller.pause().stop().destroy()
    }
}
