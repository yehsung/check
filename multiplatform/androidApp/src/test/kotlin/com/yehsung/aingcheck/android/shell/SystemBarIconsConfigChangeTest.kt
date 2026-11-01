// 원본: 없음 — 운영 시험에서 찾은 결함: 다크 테마로 큐브 판에 들어가 가로로 돌면 앱 전체에서 상태 막대 글자가 어두운색으로 굳었다(OS 는 라이트).
// 원인: androidx.activity 1.13 enableEdgeToEdge 는 **첫 호출의 설정**을 숨은 View 에 물려 구성 변경마다 다시 돌리고, 둘째 호출부터는 그 View 를 갈지 않는다.
// 재는 것: 구성 변경(회전 · OS 다크 전환) 뒤에도 막대 글자색이 **앱 화면 모드**를 따른다 — 양쪽(앱 다크·OS 라이트, 앱 라이트·OS 다크) 다. 뽑기 기계의 흰 글자와 부딪히지 않는다.
package com.yehsung.aingcheck.android.shell

import android.content.res.Configuration
import android.view.ViewGroup
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.test.core.app.ApplicationProvider
import com.yehsung.aingcheck.android.app.AingApplication
import com.yehsung.aingcheck.android.screens.shop.LightSystemBarIcons
import com.yehsung.aingcheck.ui.theme.AingAppearanceMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
import org.robolectric.android.controller.ActivityController
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h740dp-port-notnight-xhdpi")
class SystemBarIconsConfigChangeTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private val container get() = ApplicationProvider.getApplicationContext<AingApplication>().container

    @Before
    fun placeholderShell() {
        container.usePlaceholderShell()
    }

    private fun launch(mode: AingAppearanceMode): ActivityController<MainActivity> {
        container.appearance.select(mode)
        val controller = Robolectric.buildActivity(MainActivity::class.java).setup()
        idle()
        return controller
    }

    private fun idle() {
        Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
        compose.waitForIdle()
    }

    private val ActivityController<MainActivity>.bars: WindowInsetsControllerCompat
        get() = WindowCompat.getInsetsController(get().window, get().window.decorView)

    /** 구성을 바꾼다. 실제 기기에선 시스템이 Activity 다음에 창의 뷰 나무로 내려보낸다(ViewRootImpl) — Robolectric 은 Activity 까지라 나무는 여기서 민다. */
    private fun ActivityController<MainActivity>.change(edit: (Configuration) -> Unit) {
        val next = Configuration(get().resources.configuration).also(edit)
        configurationChange(next)
        get().window.decorView.dispatchConfigurationChanged(get().resources.configuration)
        idle()
    }

    private fun rotate(to: Int): (Configuration) -> Unit = { config ->
        config.orientation = to
        val (w, h) = config.screenWidthDp to config.screenHeightDp
        config.screenWidthDp = h
        config.screenHeightDp = w
    }

    private fun night(on: Boolean): (Configuration) -> Unit = { config ->
        config.uiMode = (config.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
            (if (on) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO)
    }

    /** ★ 재현 그대로: 앱 다크 · OS 라이트에서 가로로 돌았다가 세로로 돌아와도 글자는 흰색이다. */
    @Test
    fun darkAppKeepsLightIconsAcrossRotation() {
        val c = launch(AingAppearanceMode.Dark)
        assertFalse("첫 화면부터 어두운 글자", c.bars.isAppearanceLightStatusBars)
        assertFalse(c.bars.isAppearanceLightNavigationBars)
        c.change(rotate(Configuration.ORIENTATION_LANDSCAPE))
        assertFalse("가로로 돌자 상태 막대 글자가 어두운색으로 굳었다", c.bars.isAppearanceLightStatusBars)
        assertFalse("가로로 돌자 내비 막대 글자가 어두운색으로 굳었다", c.bars.isAppearanceLightNavigationBars)
        c.change(rotate(Configuration.ORIENTATION_PORTRAIT))
        assertFalse("세로로 돌아와도 어둡다", c.bars.isAppearanceLightStatusBars)
        c.pause().stop().destroy()
    }

    /** 반대로도 굳지 않는다: 앱 라이트 · OS 다크에서 돌아도 글자는 어두운색이다. */
    @Test
    @Config(qualifiers = "w360dp-h740dp-port-night-xhdpi")
    fun lightAppKeepsDarkIconsAcrossRotationOnANightDevice() {
        val c = launch(AingAppearanceMode.Light)
        assertTrue(c.bars.isAppearanceLightStatusBars)
        c.change(rotate(Configuration.ORIENTATION_LANDSCAPE))
        assertTrue("OS 다크를 따라 흰 글자로 굳었다", c.bars.isAppearanceLightStatusBars)
        assertTrue(c.bars.isAppearanceLightNavigationBars)
        c.pause().stop().destroy()
    }

    /** OS 다크 전환(회전 아닌 구성 변경)도 같다: 고정 모드는 그대로 · 시스템 모드는 따라간다. */
    @Test
    fun aNightSwitchFollowsTheMode() {
        val dark = launch(AingAppearanceMode.Dark)
        dark.change(night(true))
        assertFalse(dark.bars.isAppearanceLightStatusBars)
        dark.change(night(false))
        assertFalse("OS 를 라이트로 돌리자 다크 앱의 글자가 어두워졌다", dark.bars.isAppearanceLightStatusBars)
        dark.pause().stop().destroy()

        val system = launch(AingAppearanceMode.System)
        assertTrue(system.bars.isAppearanceLightStatusBars)
        system.change(night(true))
        assertFalse("시스템 모드가 OS 다크를 안 따라온다", system.bars.isAppearanceLightStatusBars)
        system.change(night(false))
        assertTrue(system.bars.isAppearanceLightStatusBars)
        system.pause().stop().destroy()
    }

    /** 앱에서 모드를 고르면(구성 변경 없음) 바로 맞고, 그 뒤 돌아도 고른 값을 지킨다 — 처음 뜰 때 값으로 돌아가지 않는다. */
    @Test
    fun choosingAModeSurvivesALaterRotation() {
        val c = launch(AingAppearanceMode.Light)
        container.appearance.select(AingAppearanceMode.Dark)
        idle()
        assertFalse(c.bars.isAppearanceLightStatusBars)
        c.change(rotate(Configuration.ORIENTATION_LANDSCAPE))
        assertFalse("돌자 고른 모드를 잊었다", c.bars.isAppearanceLightStatusBars)
        container.appearance.select(AingAppearanceMode.Light)
        idle()
        assertTrue(c.bars.isAppearanceLightStatusBars)
        c.change(rotate(Configuration.ORIENTATION_PORTRAIT))
        assertTrue("돌자 고른 모드를 잊었다", c.bars.isAppearanceLightStatusBars)
        c.pause().stop().destroy()
    }

    /** 돌아도 3버튼 내비 막대에 시스템 칠이 끼지 않는다 — 기본값 재실행이 강제 대비를 켜면 가로 판 옆에 막대 칠이 앉는다. */
    @Test
    fun navigationContrastStaysOffAcrossRotation() {
        val c = launch(AingAppearanceMode.Dark)
        assertFalse(c.get().window.isNavigationBarContrastEnforced)
        c.change(rotate(Configuration.ORIENTATION_LANDSCAPE))
        assertFalse("돌자 내비 막대 강제 대비가 켜졌다", c.get().window.isNavigationBarContrastEnforced)
        c.pause().stop().destroy()
    }

    /** 뽑기 기계(ShopRoutes): 라이트 앱에서도 기계 위 글자는 흰색이고, 그 위에서 돌아도 그렇고, 떠나면 **지금** 모드로 돌아간다. */
    private fun machineOver(c: ActivityController<MainActivity>): (Boolean) -> Unit {
        var shown by mutableStateOf(false)
        val activity = c.get()
        val overlay = ComposeView(activity).apply {
            setContent { if (shown) LightSystemBarIcons(LocalView.current) }
        }
        activity.addContentView(overlay, ViewGroup.LayoutParams(1, 1))
        idle()
        return { shown = it; idle() }
    }

    @Test
    fun gachaMachineKeepsLightIconsAcrossRotationAndHandsBack() {
        val c = launch(AingAppearanceMode.Light)
        val machine = machineOver(c)
        assertTrue(c.bars.isAppearanceLightStatusBars)
        machine(true)
        assertFalse("기계 위 글자가 흰색이 아니다", c.bars.isAppearanceLightStatusBars)
        assertFalse(c.bars.isAppearanceLightNavigationBars)
        c.change(rotate(Configuration.ORIENTATION_LANDSCAPE))
        assertFalse("기계 위에서 돌자 글자가 어두워졌다", c.bars.isAppearanceLightStatusBars)
        assertFalse(c.bars.isAppearanceLightNavigationBars)
        machine(false)
        assertTrue("기계를 떠나도 흰 글자로 남았다", c.bars.isAppearanceLightStatusBars)
        assertTrue(c.bars.isAppearanceLightNavigationBars)
        c.pause().stop().destroy()
    }

    /** 기계에 있는 사이 모드가 바뀌었다 — 들어올 때 값으로 되돌리면 낡은 글자색이 굳는다. */
    @Test
    fun leavingTheMachineUsesTheCurrentMode() {
        val c = launch(AingAppearanceMode.Light)
        val machine = machineOver(c)
        machine(true)
        container.appearance.select(AingAppearanceMode.Dark)
        idle()
        assertFalse("기계 위에선 모드와 무관하게 흰 글자", c.bars.isAppearanceLightStatusBars)
        machine(false)
        assertEquals("들어올 때 값으로 되돌렸다", false, c.bars.isAppearanceLightStatusBars)

        val back = launch(AingAppearanceMode.Dark)
        val second = machineOver(back)
        second(true)
        container.appearance.select(AingAppearanceMode.Light)
        idle()
        assertFalse("기계 위에선 라이트로 골라도 흰 글자", back.bars.isAppearanceLightStatusBars)
        second(false)
        assertTrue("들어올 때 값(흰 글자)으로 되돌렸다", back.bars.isAppearanceLightStatusBars)
        c.pause().stop().destroy()
        back.pause().stop().destroy()
    }
}
