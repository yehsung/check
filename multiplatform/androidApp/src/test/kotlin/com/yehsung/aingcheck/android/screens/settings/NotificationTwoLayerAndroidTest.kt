// 원본: 없음 — E§6.5 두 겹 스위치(⑤)의 Android 몫. 판정 자체는 ui NotificationTwoLayer(공용 시험 SettingsCommonRulesTest).
//
// 여기서 재는 것(Robolectric — 진짜 NotificationManager):
//  - 둘째 겹을 **기기에서 읽는다**: IMPORTANCE_NONE 채널이 blockedChannels 에 잡히고, 앱 토글(첫 겹)을 바꿔도 채널 중요도는 그대로다.
//  - 첫 겹은 **서버 선호값만** 바꾼다: 저장 문(PushSettingsPort)에 한 칸만 바뀐 값이 한 번 간다. 권한이 없으면 저장하지 않는다.
//  - 권한 읽기: 묻기 전 NotDetermined · 허용 Granted · 허용했지만 앱 알림 스위치가 꺼짐 Denied.
//  - "설정 열기" Intent 가 그 채널(EXTRA_CHANNEL_ID)을 가리킨다.
package com.yehsung.aingcheck.android.screens.settings

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.test.core.app.ApplicationProvider
import com.yehsung.aingcheck.android.push.NotificationChannels
import com.yehsung.aingcheck.core.wire.models.PushPrefs
import com.yehsung.aingcheck.ui.screens.settingscommon.NotificationPermission
import com.yehsung.aingcheck.ui.screens.settingscommon.NotificationTwoLayer
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
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
@OptIn(ExperimentalCoroutinesApi::class)
class NotificationTwoLayerAndroidTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val manager get() = context.getSystemService(NotificationManager::class.java)

    private class RecordingPort(initial: PushPrefs?) : PushSettingsPort {
        val saved = mutableListOf<PushPrefs>()
        private val flow = MutableStateFlow(initial)
        override val prefs: StateFlow<PushPrefs?> get() = flow
        override suspend fun save(prefs: PushPrefs): PushPrefs? {
            saved += prefs
            flow.value = prefs
            return prefs
        }
    }

    /** 사용자가 시스템 설정에서 꺼 둔 채널(앱은 중요도를 바꿀 수 없다 — 꺼진 채로 만든 뒤 앱의 ensure 가 덮지 못함을 같이 본다). */
    private fun blockMessageChannelBySystem() {
        manager.createNotificationChannel(NotificationChannel("message", "메시지", NotificationManager.IMPORTANCE_NONE))
        NotificationChannels.ensure(context)
    }

    @Test
    fun systemLayerIsReadFromTheDevice() {
        NotificationChannels.ensure(context)
        assertEquals("다섯 채널이 다 켜져 있으면 둘째 겹은 비었다", emptySet<String>(), SystemNotificationState.blockedChannels(context))
        blockMessageChannelBySystem()
        assertEquals(setOf("message"), SystemNotificationState.blockedChannels(context))
        assertEquals(NotificationManagerCompat.IMPORTANCE_NONE, NotificationManagerCompat.from(context).getNotificationChannelCompat("message")!!.importance)
    }

    @Test
    fun permissionStates() {
        val app = shadowOf(context as android.app.Application)
        app.denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        assertEquals(NotificationPermission.NotDetermined, SystemNotificationState.permission(context, everAsked = false))
        assertEquals("두 번 거절이면 시스템이 다시 묻지 않는다 — 설정 앱으로", NotificationPermission.Denied, SystemNotificationState.permission(context, everAsked = true))
        app.grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        assertEquals(NotificationPermission.Granted, SystemNotificationState.permission(context, everAsked = true))
        shadowOf(manager).setNotificationsEnabled(false)
        assertEquals("권한은 있는데 앱 알림 스위치가 꺼졌다", NotificationPermission.Denied, SystemNotificationState.permission(context, everAsked = true))
    }

    @Test
    fun appToggleChangesOnlyTheServerLayer() = runTest {
        shadowOf(context as android.app.Application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        blockMessageChannelBySystem()
        val port = RecordingPort(PushPrefs(message = true, gomokuInvite = true, feedbackReply = true))
        val opened = mutableListOf<android.content.Intent>()
        val model = AndroidNotificationSettings(context, port, this, launchPermissionRequest = {}, everAsked = { true }, startActivity = { opened += it })
        model.refreshSystemState()
        assertEquals(NotificationPermission.Granted, model.permission)
        assertEquals(setOf("message"), model.blockedChannels)
        val rows = NotificationTwoLayer.rows(model.kinds, model.permission, model.prefs, model.blockedChannels)
        val message = rows.single { it.kind.raw == "message" }
        assertTrue("서버는 켜짐 — 토글은 켜진 모양", message.appOn)
        assertTrue("기기에서 꺼짐 — 그 행에 시스템 안내", message.systemBlocked)

        model.setEnabled(message.kind, false)
        advanceUntilIdle()
        assertEquals(listOf(PushPrefs(message = false, gomokuInvite = true, feedbackReply = true)), port.saved)
        assertEquals("앱 토글이 시스템 채널을 건드렸다", NotificationManagerCompat.IMPORTANCE_NONE, NotificationManagerCompat.from(context).getNotificationChannelCompat("message")!!.importance)
        assertEquals(setOf("message"), SystemNotificationState.blockedChannels(context))

        // 둘째 겹으로 가는 길: 그 채널의 시스템 설정.
        model.openChannelSettings(message.kind)
        val intent = opened.single()
        assertEquals(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS, intent.action)
        assertEquals("message", intent.getStringExtra(Settings.EXTRA_CHANNEL_ID))
        assertEquals(context.packageName, intent.getStringExtra(Settings.EXTRA_APP_PACKAGE))
    }

    @Test
    fun withoutPermissionNothingIsSaved() = runTest {
        shadowOf(context as android.app.Application).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        NotificationChannels.ensure(context)
        val port = RecordingPort(PushPrefs())
        var asked = 0
        val opened = mutableListOf<android.content.Intent>()
        val model = AndroidNotificationSettings(context, port, this, launchPermissionRequest = { asked += 1 }, everAsked = { false }, startActivity = { opened += it })
        model.refreshSystemState()
        assertEquals(NotificationPermission.NotDetermined, model.permission)
        model.setEnabled(NotificationTwoLayer.androidKinds.first(), false)
        advanceUntilIdle()
        assertEquals("권한이 없으면 서버 선호값을 건드리지 않는다", emptyList<PushPrefs>(), port.saved)
        model.requestPermission()
        assertEquals(1, asked)
        assertTrue(model.isRequestingPermission)
        model.onPermissionResult()
        assertFalse(model.isRequestingPermission)
        model.openSystemSettings()
        assertEquals(Settings.ACTION_APP_NOTIFICATION_SETTINGS, opened.single().action)
        // 근무 확인·체스는 앱 토글이 없다 — 눌러도 저장 0.
        model.refreshSystemState()
        for (kind in NotificationTwoLayer.androidKinds.filter { it.prefsKey == null }) model.setEnabled(kind, false)
        advanceUntilIdle()
        assertEquals(emptyList<PushPrefs>(), port.saved)
    }
}
