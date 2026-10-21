// 시험 감지가 늘 참이 되면 release 가 SKIP_RUNNING_TESTS 로 빠져 운영에서 FCM 이 영영 초기화되지 않는다. 판정을 순수 함수로 떼어
// "레지스트리 클래스 없음(출시 APK) · getInstrumentation 이 던짐(등록 전) · null → 거짓"과 그 짝(참)을 잰다.
package com.yehsung.aingcheck.android.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** 시험용 레지스트리 셋 — 진짜 InstrumentationRegistry 와 같은 모양(정적 getInstrumentation()). */
object PresentRegistry {
    @JvmStatic fun getInstrumentation(): Any = Any()
}

object ThrowingRegistry {
    @JvmStatic fun getInstrumentation(): Any = throw IllegalStateException("No instrumentation registered!")
}

object NullRegistry {
    @JvmStatic fun getInstrumentation(): Any? = null
}

class AndroidRunningTestsTest {
    private val device = "google/sdk_gphone64_arm64/emu64a:16/BP22.250325.006/13344233:user/release-keys"
    private fun detect(fingerprint: String, registry: String) =
        AndroidRunningTests.detect(fingerprint) { AndroidRunningTests.registeredInstrumentation(registry) }

    @Test
    fun releaseShapedProcessIsNotATest() {
        // 출시 APK: androidx.test 가 없다 → 레지스트리 클래스 없음 → 거짓.
        assertFalse(detect(device, "androidx.test.platform.app.DoesNotExistRegistry"))
        // 레지스트리는 있으나 계측이 등록되지 않았다(getInstrumentation 이 던진다) → 거짓.
        assertFalse(detect(device, ThrowingRegistry::class.java.name))
        // 등록된 계측이 null → 거짓.
        assertFalse(detect(device, NullRegistry::class.java.name))
    }

    @Test
    fun registeredInstrumentationOrRobolectricIsATest() {
        // 짝(같은 지문, 다른 레지스트리): 계측이 등록돼 있으면 참.
        assertTrue(detect(device, PresentRegistry::class.java.name))
        // Robolectric 지문은 레지스트리를 보지 않고 참.
        assertTrue(detect(AndroidRunningTests.ROBOLECTRIC_FINGERPRINT, "androidx.test.platform.app.DoesNotExistRegistry"))
    }

    @Test
    fun productionLooksUpTheAndroidxRegistry() {
        assertEquals("androidx.test.platform.app.InstrumentationRegistry", AndroidRunningTests.REGISTRY_CLASS)
        assertEquals("robolectric", AndroidRunningTests.ROBOLECTRIC_FINGERPRINT)
    }
}
