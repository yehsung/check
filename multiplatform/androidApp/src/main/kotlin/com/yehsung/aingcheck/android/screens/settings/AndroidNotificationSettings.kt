// 원본: Sources/CheckMobileKit/Me/MeSettingsView.swift @ 3bd04bd (pushSection · refreshAuthorization — 설정 앱에서 돌아오면 바로 반영)
// 원본: Sources/CheckMobileKit/Push/PushCoordinator.swift @ 3bd04bd (authorization · knowsPrefs · setPreference(직렬 저장) · prefsNotice · openSystemSettings)
//
// 알림 절의 Android 판(⑤ 두 겹 스위치 — E§6.5). 첫 겹(앱 안 토글)은 **서버 선호값**만 바꾸고(set_push_prefs — 저장은 [PushSettingsPort] 한 문),
// 둘째 겹(시스템 채널)은 기기 설정이라 앱이 바꾸지 않는다 — 꺼진 채널은 그 행에 "시스템에서 꺼짐 · 설정 열기"(ACTION_CHANNEL_NOTIFICATION_SETTINGS).
// 플랫폼 상태(권한 · 채널 중요도)는 화면이 다시 보일 때(ON_RESUME — 설정 앱에서 돌아옴)마다 다시 읽는다([refreshSystemState]).
// 판정(두 겹 → 행 모양)은 ui NotificationTwoLayer(공용 시험), 이 파일은 읽기·부르기만 한다.
package com.yehsung.aingcheck.android.screens.settings

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.yehsung.aingcheck.android.push.AingChannel
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.wire.models.PushPrefs
import com.yehsung.aingcheck.ui.screens.settingscommon.NotificationKind
import com.yehsung.aingcheck.ui.screens.settingscommon.NotificationPermission
import com.yehsung.aingcheck.ui.screens.settingscommon.NotificationSettingsModel
import com.yehsung.aingcheck.ui.screens.settingscommon.NotificationTwoLayer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * 서버 선호값의 문(첫 겹). iOS 는 "알림 설정의 유일한 구현은 푸시 코디네이터"다 — Android 의 그 자리는 W2-f(feature/phone push)다. W2-f 병합 전이라
 * 기본 구현([SessionPushSettingsPort])은 세션 스토어(W2-a)의 기기 등록 응답 · savePushPrefs 에 대고 짰고, 조립이 W2-f 조정자로 바꿔 끼운다(assembly.md).
 */
interface PushSettingsPort {
    val prefs: StateFlow<PushPrefs?>

    /** 저장(성공하면 새 값, 아니면 null). */
    suspend fun save(prefs: PushPrefs): PushPrefs?
}

class SessionPushSettingsPort(private val session: SessionStore) : PushSettingsPort {
    override val prefs: StateFlow<PushPrefs?> get() = session.pushPrefsFlow
    override suspend fun save(prefs: PushPrefs): PushPrefs? = session.savePushPrefs(prefs)
}

/** 시스템 알림 상태 읽기(권한 · 채널). 시험은 Robolectric 위 실제 NotificationManager 로 잰다. */
object SystemNotificationState {
    /** API 33+ 은 런타임 권한, 26~32 는 앱 알림 스위치(areNotificationsEnabled) 하나. */
    fun permission(context: Context, everAsked: Boolean): NotificationPermission {
        val enabled = NotificationManagerCompat.from(context).areNotificationsEnabled()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return if (enabled) NotificationPermission.Granted else NotificationPermission.Denied
        }
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        return when {
            granted && enabled -> NotificationPermission.Granted
            granted -> NotificationPermission.Denied // 권한은 있는데 앱 알림 스위치가 꺼졌다 — 설정 앱에서만 켠다.
            everAsked -> NotificationPermission.Denied
            else -> NotificationPermission.NotDetermined
        }
    }

    /** 시스템에서 꺼진(IMPORTANCE_NONE) 채널 id(채널이 없으면 꺼진 것으로 치지 않는다 — Application 이 다섯을 만든다). */
    fun blockedChannels(context: Context): Set<String> =
        AingChannel.entries.filter { com.yehsung.aingcheck.android.push.NotificationChannels.isBlockedBySystem(context, it) == true }.map { it.id }.toSet()
}

/** 시스템 설정으로 가는 Intent(순수 모양 — 시험이 action·extra 를 잰다). */
object NotificationSettingsIntents {
    /** 앱의 알림 설정(권한 거절 · 앱 알림 스위치 꺼짐). */
    fun app(packageName: String): Intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
        putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    /** 채널 하나의 설정(둘째 겹 — "시스템에서 꺼짐 · 설정 열기"). */
    fun channel(packageName: String, channelId: String): Intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
        putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
}

/**
 * 알림 절 모델(Android). 권한 요청 자체(ActivityResult)는 껍데기가 [requestPermission] 콜백으로 넘긴다 — 결과가 오면 [onPermissionResult].
 * 저장은 **직렬**(iOS 코디네이터 규약 — 연타가 순서를 뒤집지 않게): 앞 저장이 끝난 값 위에 다음 한 칸을 고친다.
 */
class AndroidNotificationSettings(
    private val context: Context,
    private val port: PushSettingsPort,
    private val scope: CoroutineScope,
    private val launchPermissionRequest: () -> Unit,
    /** 런타임 권한을 한 번이라도 물었는가(설정 저장소 — 두 번 거절이면 시스템이 다시 묻지 않으므로 설정 앱으로 보낸다). */
    private val everAsked: () -> Boolean,
    private val startActivity: (Intent) -> Unit = { context.startActivity(it) },
) : NotificationSettingsModel {
    override var permission: NotificationPermission by mutableStateOf(NotificationPermission.Unknown)
        private set
    override var blockedChannels: Set<String> by mutableStateOf(emptySet())
        private set
    override var isSavingPrefs: Boolean by mutableStateOf(false)
        private set
    override var isRequestingPermission: Boolean by mutableStateOf(false)
        private set
    override var prefsNotice: String? by mutableStateOf(null)
        private set
    override val prefs: PushPrefs? get() = port.prefs.value

    private val saving = Mutex()

    /** 화면이 다시 보일 때(ON_RESUME)마다 — 설정 앱에서 알림·채널을 바꾸고 돌아오면 바로 반영한다. */
    fun refreshSystemState() {
        permission = SystemNotificationState.permission(context, everAsked())
        blockedChannels = SystemNotificationState.blockedChannels(context)
    }

    override fun setEnabled(kind: NotificationKind, enabled: Boolean) {
        val key = kind.prefsKey ?: return
        if (!permission.allowsDelivery) return
        scope.launch {
            saving.withLock {
                val base = port.prefs.value ?: return@withLock
                val next = NotificationTwoLayer.withValue(base, key, enabled) ?: return@withLock
                isSavingPrefs = true
                prefsNotice = null
                val saved = try {
                    port.save(next)
                } catch (error: Throwable) {
                    if (error is kotlinx.coroutines.CancellationException) throw error
                    null
                }
                isSavingPrefs = false
                if (saved == null) prefsNotice = SettingsText.pushSaveFailed
            }
        }
    }

    override fun requestPermission() {
        isRequestingPermission = true
        launchPermissionRequest()
    }

    /** 권한 요청 결과가 왔다(껍데기의 ActivityResult). */
    fun onPermissionResult() {
        isRequestingPermission = false
        refreshSystemState()
    }

    override fun openSystemSettings() = startActivity(NotificationSettingsIntents.app(context.packageName))

    override fun openChannelSettings(kind: NotificationKind) = startActivity(NotificationSettingsIntents.channel(context.packageName, kind.raw))

    /** 설정 화면을 떠날 때 저장 안내를 걷는다(Swift settingsDidDisappear → push.prefsNotice = nil). */
    fun clearNotice() {
        prefsNotice = null
    }
}

object SettingsText {
    /** 저장 실패(Swift PushText.settingsSaveFailed). */
    const val pushSaveFailed = "알림 설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요"
    const val signOutCancel = "취소"
    val signOutConfirmTitle: String get() = MeText.signOutConfirmTitle
}
