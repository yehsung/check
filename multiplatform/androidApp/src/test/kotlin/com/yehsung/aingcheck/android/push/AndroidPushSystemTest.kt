// 원본: Sources/CheckMobileKit/Push/PushNotificationCenterAdapter.swift(권한 읽기 · 등록 · 지우기 · 설정 열기) @ 3bd04bd
// Android 권한 판정(API 33+ 런타임 권한 · 26~32 앱 알림 스위치)과 Firebase 없는 빌드의 토큰 실패를 잰다.
package com.yehsung.aingcheck.android.push

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.provider.Settings
import androidx.test.core.app.ApplicationProvider
import com.yehsung.aingcheck.android.app.AingApplication
import com.yehsung.aingcheck.feature.phone.push.PhonePushAuthorization
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class AndroidPushSystemTest {
    private val app get() = ApplicationProvider.getApplicationContext<AingApplication>()
    private val manager get() = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun system(sdk: Int = 36) = AndroidPushSystem(app, app.container.keyValueStore, sdkInt = sdk, firebaseReady = { false })

    @Test
    fun api33PlusSeparatesNotDeterminedFromDeniedByTheAskedFlag() = runBlocking {
        shadowOf(manager).setNotificationsEnabled(true)
        shadowOf(app).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        val system = system()
        assertEquals("한 번도 묻지 않았으면 미결정(설명 시트를 띄울 때)", PhonePushAuthorization.notDetermined, system.authorizationStatus())
        assertFalse("창을 띄울 Activity 가 없으면 창 없이 거짓", system.requestAuthorization())
        // 창을 띄울 문이 생겼다(셸) — 사용자가 거절한다.
        system.permissionRequester = { false }
        assertFalse(system.requestAuthorization())
        assertEquals("물었는데 허락이 없으면 거절(설정으로 보낸다)", PhonePushAuthorization.denied, system.authorizationStatus())
        // 허락 + 앱 알림 켜짐 = 허락. 허락이어도 앱 알림을 끄면 거절이다(받지 않으니 토큰을 거둔다).
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        assertEquals(PhonePushAuthorization.authorized, system.authorizationStatus())
        shadowOf(manager).setNotificationsEnabled(false)
        assertEquals(PhonePushAuthorization.denied, system.authorizationStatus())
    }

    @Test
    fun api26To32FollowTheAppNotificationSwitchOnly() = runBlocking {
        shadowOf(manager).setNotificationsEnabled(true)
        val system = system(sdk = 32)
        assertEquals("26~32 는 기본 허락", PhonePushAuthorization.authorized, system.authorizationStatus())
        assertTrue(system.requestAuthorization())
        shadowOf(manager).setNotificationsEnabled(false)
        assertEquals(PhonePushAuthorization.denied, system.authorizationStatus())
    }

    @Test
    fun withoutFirebaseTokenRequestFailsQuietlyAndSettingsOpenThisAppsNotifications() {
        val system = system()
        val failures = mutableListOf<String>()
        system.onTokenFailure = { failures += it }
        system.onToken = { error("Firebase 없는 빌드에서 토큰이 나왔다") }
        system.registerForRemoteNotifications()
        system.unregisterForRemoteNotifications()
        assertEquals("debug·시험 빌드는 실제 제공자를 부르지 않는다", listOf(AndroidPushSystem.FAILURE_NO_FIREBASE), failures)
        system.openSystemSettings()
        val started = shadowOf(app).nextStartedActivity
        assertEquals(Settings.ACTION_APP_NOTIFICATION_SETTINGS, started.action)
        assertEquals(app.packageName, started.getStringExtra(Settings.EXTRA_APP_PACKAGE))
        system.presentPermissionPrimer()
        assertTrue(system.isPrimerVisible.value)
        system.dismissPermissionPrimer()
        assertFalse(system.isPrimerVisible.value)
        system.setBadgeCount(3)
        assertEquals(3, system.lastBadgeCount)
    }
}
