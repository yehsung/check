// Firebase 는 release 조립 지점 + 온전한 설정 + 시험 아님일 때만 초기화한다(E§6.6, §8-5). 시험·debug·stub 은 0.
package com.yehsung.aingcheck.android.app

import androidx.test.core.app.ApplicationProvider
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** 진짜 값이 아니다(모양만 맞춘 더미). Google API 키 접두는 쓰지 않는다 — 비밀 검사기와 겹치지 않게. */
private val FAKE = FirebaseSettings.parse("1:123456789012:android:0123456789abcdef", "aingcheck-dev", "123456789012", "fake-api-key-0123456789abcdef0123")

class FirebaseDecisionTest {
    @Test
    fun onlyReleaseWithConfigOutsideTestsInitializes() {
        assertTrue(FAKE != null)
        for (variant in AppVariantKind.entries) for (tests in listOf(false, true)) for (settings in listOf(FAKE, null)) {
            val expected = when {
                variant != AppVariantKind.RELEASE -> FirebaseDecision.SKIP_NOT_RELEASE
                tests -> FirebaseDecision.SKIP_RUNNING_TESTS
                settings == null -> FirebaseDecision.SKIP_NO_CONFIG
                else -> FirebaseDecision.INITIALIZE
            }
            assertEquals("$variant tests=$tests settings=${settings != null}", expected, FirebaseBootstrap.decide(variant, settings, tests))
        }
        // 표의 단 하나의 INITIALIZE.
        assertEquals(FirebaseDecision.INITIALIZE, FirebaseBootstrap.decide(AppVariantKind.RELEASE, FAKE, runningTests = false))
    }

    @Test
    fun dummyOrMixedSettingsAreRejected() {
        assertNull("기본 더미(빈 값)", FirebaseSettings.parse("", "", "", ""))
        assertNull("발신자 번호가 앱 id 와 다르다", FirebaseSettings.parse("1:123456789012:android:0123456789abcdef", "aingcheck-dev", "999999999999", "fake-api-key-0123456789abcdef0123"))
        assertNull("공백", FirebaseSettings.parse("1:123456789012:android:0123456789abcdef", "aingcheck-dev", "123456789012", "fake key 0123456789abcdef0123"))
        assertNull("iOS 앱 id", FirebaseSettings.parse("1:123456789012:ios:0123456789abcdef", "aingcheck-dev", "123456789012", "fake-api-key-0123456789abcdef0123"))
        assertNull("debug 변형에는 Firebase 설정이 없다(§8-5 — 조정자 패치 w1g-02 뒤에도 debug 생성 상수는 빈 값)", FirebaseConfigSource.settings())
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class FirebaseNotInitializedInTestsTest {
    @Test
    fun testBuildStartsWithoutFirebase() {
        val app = ApplicationProvider.getApplicationContext<AingApplication>()
        assertEquals(AppVariantKind.DEBUG, AppVariant.kind)
        assertTrue("Robolectric 은 시험 실행으로 읽혀야 한다", app.container.runningTests.isRunningTests)
        assertEquals(FirebaseDecision.SKIP_NOT_RELEASE, app.firebaseDecision)
        assertEquals("시험 빌드가 Firebase 를 초기화했다", emptyList<FirebaseApp>(), FirebaseApp.getApps(app))
        // 기준선: 같은 판별(getApps)이 초기화된 앱은 본다 — 위 빈 목록이 늘 빈 판별이 아니다.
        val probe = FirebaseApp.initializeApp(
            app,
            FirebaseOptions.Builder().setApplicationId("1:1:android:1").setProjectId("probe-project").setApiKey("probe").build(),
            "probe",
        )
        try {
            assertEquals(1, FirebaseApp.getApps(app).size)
        } finally {
            probe.delete()
        }
    }
}
