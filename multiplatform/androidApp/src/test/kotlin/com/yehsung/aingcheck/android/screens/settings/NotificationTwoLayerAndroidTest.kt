// 원본: 없음 — E§6.5 두 겹 스위치(⑤)의 Android 몫. 판정 자체는 ui NotificationTwoLayer(공용 시험 SettingsCommonRulesTest).
//
// 여기서 재는 것(Robolectric — 진짜 NotificationManager):
//  - 둘째 겹을 **기기에서 읽는다**: IMPORTANCE_NONE 채널이 blockedChannels 에 잡히고, 앱 토글(첫 겹)을 바꿔도 채널 중요도는 그대로다.
//  - 첫 겹은 **서버 선호값만** 바꾼다: 저장 문(PushSettingsPort)에 한 칸만 바뀐 값이 한 번 간다. 권한이 없으면 저장하지 않는다.
//  - 권한 읽기: 묻기 전 NotDetermined · 허용 Granted · 허용했지만 앱 알림 스위치가 꺼짐 Denied.
//  - "설정 열기" Intent 가 그 채널(EXTRA_CHANNEL_ID)을 가리킨다.
//  - 저장 규약(iOS PushCoordinator.setPreference): 누른 값을 곧바로 그리고, 도는 저장이 있으면 쌓았다가 최신 값으로 한 번 더(겹침 0),
//    실패면 마지막 서버값으로 되돌리고 안내 한 줄.
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
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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

    /** 응답을 시험이 손으로 놓는 저장 문(true = 서버 ok · false = 실패). 겹친 요청 수를 잰다. */
    private class GatedPort(initial: PushPrefs) : PushSettingsPort {
        val sent = mutableListOf<PushPrefs>()
        val replies = Channel<Boolean>(Channel.UNLIMITED)
        var inFlight = 0
        var maxInFlight = 0
        private val flow = MutableStateFlow<PushPrefs?>(initial)
        override val prefs: StateFlow<PushPrefs?> get() = flow
        override suspend fun save(prefs: PushPrefs): PushPrefs? {
            sent += prefs
            inFlight += 1
            maxInFlight = maxOf(maxInFlight, inFlight)
            val ok = replies.receive()
            inFlight -= 1
            if (!ok) return null
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

    /**
     * 8차 e2e 결함(스위치가 서버값과 어긋남)의 규약 쪽. iOS setPreference 와 같이:
     *  ① 누르자마자 그 값을 그린다(낙관적) · ② 도는 저장 중 누른 값은 쌓았다가 **최신 값으로 한 번만** 더 보낸다(겹침 0 · 중간 값 생략)
     *  ③ 저장 중 표시는 다 끝나야 내린다 · ④ 실패면 마지막 서버값으로 되돌리고 안내 한 줄.
     */
    @Test
    fun togglesAreOptimisticSerialAndRevertOnFailure() = runTest {
        shadowOf(context as android.app.Application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        NotificationChannels.ensure(context)
        val allOn = PushPrefs(message = true, gomokuInvite = true, feedbackReply = true)
        val port = GatedPort(allOn)
        val model = AndroidNotificationSettings(context, port, this, launchPermissionRequest = {}, everAsked = { true }, startActivity = {})
        model.refreshSystemState()
        val kinds = NotificationTwoLayer.androidKinds.associateBy { it.raw }

        model.setEnabled(kinds.getValue("message"), false)
        runCurrent()
        assertEquals("① 누른 값을 곧바로 그린다", PushPrefs(message = false, gomokuInvite = true, feedbackReply = true), model.prefs)
        assertTrue(model.isSavingPrefs)
        assertEquals(1, port.sent.size)

        // 도는 동안 두 번 더 누른다 — 오목 끔, 메시지 다시 켬.
        model.setEnabled(kinds.getValue("gomoku_invite"), false)
        model.setEnabled(kinds.getValue("message"), true)
        runCurrent()
        val latest = PushPrefs(message = true, gomokuInvite = false, feedbackReply = true)
        assertEquals("② 앞 누름 위에 고친 최신 값을 그린다", latest, model.prefs)
        assertEquals("② 도는 저장이 끝나기 전에는 보내지 않는다", 1, port.sent.size)

        port.replies.send(true)
        runCurrent()
        assertEquals("② 끝난 뒤 최신 값으로 한 번 더", listOf(PushPrefs(message = false, gomokuInvite = true, feedbackReply = true), latest), port.sent)
        assertTrue("③ 보낼 것이 남았으니 저장 중", model.isSavingPrefs)
        port.replies.send(true)
        advanceUntilIdle()
        assertEquals("② 중간 값은 보내지 않는다", 2, port.sent.size)
        assertEquals("② 요청이 겹치지 않는다", 1, port.maxInFlight)
        assertFalse(model.isSavingPrefs)
        assertEquals(latest, model.prefs)
        assertNull(model.prefsNotice)

        model.setEnabled(kinds.getValue("feedback_reply"), false)
        runCurrent()
        assertFalse(model.prefs!!.feedbackReply)
        port.replies.send(false)
        advanceUntilIdle()
        assertEquals("④ 실패면 마지막 서버값으로 되돌린다", latest, model.prefs)
        assertEquals(SettingsText.pushSaveFailed, model.prefsNotice)
        assertFalse(model.isSavingPrefs)
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
