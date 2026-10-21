package com.yehsung.aingcheck.android.scaffold

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onRoot
import com.github.takahirom.roborazzi.captureRoboImage
import com.yehsung.aingcheck.ui.scaffold.ScaffoldProbe
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A-X5: Robolectric 4.17(NATIVE 그래픽) + Roborazzi 가 **봉인·오프라인**에서 돈다.
 * android-all 은 실행 중에 받지 않는다(robolectric.offline=true + 미리 받은 jar 폴더, aingcheck.test-seal).
 * 기본 실행은 캡처만 한다. 기록→대조 판정은 recordRoborazziDebug → verifyRoborazziDebug 를 두 번 돌려 PNG 바이트를 비교한다.
 * 골든 자리는 build/ 아래(커밋하지 않는 실험) — 제품 스냅숏 골든은 화면 갈래가 정한다.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h640dp-xhdpi")
class RobolectricRoborazziScaffoldTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun scaffoldProbeSnapshot() {
        compose.setContent { ScaffoldProbe() }
        compose.onRoot().captureRoboImage("build/aingcheck-scaffold/android/scaffold_probe.png")
    }
}
