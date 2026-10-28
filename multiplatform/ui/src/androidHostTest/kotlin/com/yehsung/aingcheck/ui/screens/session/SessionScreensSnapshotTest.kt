// 원본: Sources/CheckMobileKit/Session/MobileSessionViews.swift @ 3bd04bd (MobileLoginView — 데모 라우트 login 의 스크린샷 장면)
//
// G §2-3 W3-a ① Roborazzi: 로그인 화면 — 폰(밝음 · 어두움) · sw600dp. 세션은 진짜 SessionStore(데모 픽스처 · 로그아웃 단계 · 지난 이메일).
// 음성 기준선: 이메일 칸 글자만 다른 같은 화면.
package com.yehsung.aingcheck.ui.screens.session

import androidx.compose.foundation.text.input.rememberTextFieldState
import com.yehsung.aingcheck.ui.components.AndroidSnapshots
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenArt
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenFrame
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenHarness
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenSnapshots
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h800dp-xhdpi")
class SessionScreensSnapshotTest {
    private val harness = ScreenHarness(scenario = null, repoRoot = AndroidSnapshots.repoRoot).also { it.signedOut() }
    private val art = ScreenArt.bundledOnly()

    @After
    fun close() = harness.close()

    private fun login(dark: Boolean, frame: ScreenFrame, name: String) {
        harness.freeze()
        ScreenSnapshots.check(
            "screens/session", name, frame, art,
            scene = { ScreenSnapshots.Frame(dark, art, null) { LoginScreen(harness.session, {}, {}, {}) } },
            other = {
                ScreenSnapshots.Frame(dark, art, null) {
                    LoginScreen(harness.session, {}, {}, {}, email = rememberTextFieldState("other@aing-check.invalid"))
                }
            },
        )
    }

    @Test fun loginPhoneLight() = login(false, ScreenFrame.Phone, "login-phone-light")

    @Test fun loginPhoneDark() = login(true, ScreenFrame.Phone, "login-phone-dark")

    @Test @Config(qualifiers = "w600dp-h960dp-xhdpi")
    fun loginTabletLight() = login(false, ScreenFrame.Tablet, "login-sw600dp-light")
}
