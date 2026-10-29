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
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

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
 * 저장 규약은 iOS PushCoordinator.setPreference 와 같다:
 *  - **낙관적**: 누른 값([desiredPrefs])을 곧바로 그린다. 다음 누름도 그 값 위에 한 칸을 고친다.
 *  - **직렬 + 최신 값 한 번 더**: 도는 저장이 있으면 누른 값을 쌓아 두고, 끝난 뒤 최신 값으로 한 번 더 보낸다(요청이 겹치지 않는다).
 *    [isSavingPrefs] 는 보낼 것이 모두 끝났을 때만 내린다.
 *  - **끝나면 서버값**: 다 끝나면 누른 값을 걷고 서버가 돌려준 값을 그린다 — 실패면 마지막 서버값으로 되돌아가고 안내 한 줄.
 * ⚠️ 서버값은 [serverPrefs](스냅숏 상태)로 비춰 그린다. StateFlow.value 를 그리기에서 바로 읽으면 Compose 가 바뀜을 모른다 —
 *   7차 로컬 앱 e2e 결함(서버는 message=false 인데 스위치는 켜짐에 머물러 다시 눌러도 false 만 보냈다)의 원인이 그것이었다.
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

    /** 서버가 마지막으로 알려 준 값의 거울(Compose 가 관찰한다). [observeServerPrefs] 가 붙들고, 저장이 끝날 때도 다시 읽는다. */
    private var serverPrefs: PushPrefs? by mutableStateOf(port.prefs.value)

    /** 사용자가 마지막으로 누른 값(저장이 끝날 때까지 화면이 이 값을 그린다 — Swift desiredPrefs). */
    private var desiredPrefs: PushPrefs? by mutableStateOf(null)

    /** 지금 그릴 값: 저장 중이면 누른 값, 아니면 서버값(모르면 null — 토글을 잠근다). */
    override val prefs: PushPrefs? get() = desiredPrefs ?: serverPrefs

    private var saveJob: Job? = null
    private var saveAgain = false

    /** 서버값 거울을 붙든다 — 껍데기가 화면이 떠 있는 동안 LaunchedEffect 로 부른다(기기 등록 응답이 늦게 와도 토글이 풀린다). */
    suspend fun observeServerPrefs() {
        port.prefs.collect { serverPrefs = it }
    }

    /** 화면이 다시 보일 때(ON_RESUME)마다 — 설정 앱에서 알림·채널을 바꾸고 돌아오면 바로 반영한다. */
    fun refreshSystemState() {
        permission = SystemNotificationState.permission(context, everAsked())
        blockedChannels = SystemNotificationState.blockedChannels(context)
    }

    override fun setEnabled(kind: NotificationKind, enabled: Boolean) {
        val key = kind.prefsKey ?: return
        if (!permission.allowsDelivery) return
        // 서버값을 모르면 보내지 않는다(Swift knowsPrefs) — 세 칸을 통째로 보내므로 모르는 칸을 기본값으로 채우면 꺼 둔 알림을 되살린다.
        val base = prefs ?: return
        desiredPrefs = NotificationTwoLayer.withValue(base, key, enabled) ?: return
        isSavingPrefs = true
        prefsNotice = null
        if (saveJob != null) {
            saveAgain = true
            return
        }
        // LAZY: 자리를 먼저 잡고 시작한다 — 즉시 실행 디스패처에서 저장이 끝난 뒤에 자리를 잡으면 다음 누름이 영영 쌓이기만 한다.
        val job = scope.launch(start = CoroutineStart.LAZY) { runSaves() }
        saveJob = job
        job.start()
    }

    private suspend fun runSaves() {
        var saved: PushPrefs? = null
        try {
            do {
                saveAgain = false
                val target = desiredPrefs ?: break
                saved = try {
                    port.save(target)
                } catch (error: Throwable) {
                    if (error is kotlinx.coroutines.CancellationException) throw error
                    null
                }
            } while (saveAgain)
        } finally {
            saveJob = null
            serverPrefs = port.prefs.value
            desiredPrefs = null
            isSavingPrefs = false
        }
        if (saved == null) prefsNotice = SettingsText.pushSaveFailed
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
