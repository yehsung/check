// 원본: 없음 — G §8-17 #1(판돈 대결 빌드 깃발 duelsEnabled: 꺼짐 기본값 · 켜짐 주입) · Sources/CheckMobileKit/App/MobileAppInfo.swift(feedbackAppVersion) @ 1b8260d
package com.yehsung.aingcheck.core.session

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.context.SessionContext
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertSame
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class AppConfigTest {
    /** §8-17 #1: 깃발은 **기본 꺼짐**이다 — 앱 구성 값을 주지 않은 조립·문맥은 판돈 진입을 숨긴다. */
    @Test
    fun duelsAreOffByDefault() = runTest {
        assertFalse(AppConfig.DUELS_ENABLED_DEFAULT)
        assertFalse(AppConfig().duelsEnabled)
        val h = SessionHarness(this) { null }
        val context = SessionContext(h.store)
        assertFalse(context.appConfig.duelsEnabled, "문맥 기본값도 꺼짐")
    }

    /** 켜짐 주입: 조립 지점이 넣은 값이 스토어가 읽는 한 자리(SessionContext.appConfig)로 그대로 간다. */
    @Test
    fun injectedDuelsFlagReachesStoresThroughContext() = runTest {
        val h = SessionHarness(this) { null }
        val on = SessionContext(h.store, AppConfig(duelsEnabled = true))
        val off = SessionContext(h.store, AppConfig(duelsEnabled = false))
        assertTrue(on.appConfig.duelsEnabled)
        assertFalse(off.appConfig.duelsEnabled)
        // 같은 세션 위에서 깃발만 다르다 — 세션·서비스·시계·앱 정보는 세션 스토어 것을 그대로 지나 보낸다.
        assertSame(h.store.service, on.service)
        assertSame(h.store.clock, on.clock)
        assertEquals(h.store.appInfo, on.appInfo)
        assertSame(h.store.prefs, on.keyValueStore)
        assertEquals(h.store.generation, on.generation)
    }

    @Test
    fun appInfoComesFromClientIdentity() {
        val android = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 12, "1.0.3"), "Android 15")
        assertEquals("Android 1.0.3 (12)", android.feedbackAppVersion, "Swift \"iOS 0.1.0 (1)\" 과 같은 꼴")
        assertEquals(12L, android.build)
        val windows = AppInfo(ClientIdentity(ClientPlatform.WINDOWS, 3, "0.9.0"), "Windows 11")
        assertEquals("Windows 0.9.0 (3)", windows.feedbackAppVersion)
    }
}
