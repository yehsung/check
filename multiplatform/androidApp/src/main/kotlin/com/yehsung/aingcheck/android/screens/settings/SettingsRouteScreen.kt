// 원본: Sources/CheckMobileKit/Me/MeSettingsView.swift @ 3bd04bd (설정 화면 — onAppear/onDisappear · scenePhase active 에서 권한 다시 읽기 · 로그아웃 확인 · 처리방침 열기 · 공유)
//
// 설정 껍데기(Android). 공용 화면(ui …/screens/settingscommon SettingsScreen)에 Android 몫을 꽂는다: 알림 절(두 겹 스위치 — AndroidNotificationSettings),
// 링크 열기(ACTION_VIEW), 공유 시트(ACTION_SEND), 로그아웃 확인 대화상자(M3 AlertDialog), POST_NOTIFICATIONS 요청(ActivityResult).
// 화면 모드는 AppearanceStore(셸이 AingTheme 에 건다 — assembly.md). 계정 삭제는 [openAccountDeletion] 으로 화면만 연다(삭제를 부르지 않는다).
package com.yehsung.aingcheck.android.screens.settings

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.settingsDidAppear
import com.yehsung.aingcheck.core.stores.me.settingsDidDisappear
import com.yehsung.aingcheck.core.stores.me.signOut
import com.yehsung.aingcheck.ui.screens.settingscommon.AppearanceStore
import com.yehsung.aingcheck.ui.screens.settingscommon.NotificationSettingsSection
import com.yehsung.aingcheck.ui.screens.settingscommon.SettingsActions
import com.yehsung.aingcheck.ui.screens.settingscommon.SettingsScreen
import kotlinx.coroutines.launch

/** 런타임 알림 권한을 한 번이라도 물었는가(설정 저장소 한 칸 — 기기 값, 로그아웃과 무관). */
object NotificationAskRecord {
    const val KEY = "aingcheck.push.permissionAsked"
    fun asked(store: KeyValueStore): Boolean = store.getBoolean(KEY) == true
    fun markAsked(store: KeyValueStore) = store.putBoolean(KEY, true)
}

/**
 * @param push 서버 선호값 문(기본 SessionPushSettingsPort — 조립이 W2-f 푸시 조정자로 바꿔 끼운다).
 * @param prefs 비밀 아닌 설정 저장소(권한을 물었는지 기록).
 */
@Composable
fun SettingsRouteScreen(
    store: MeStore,
    appearance: AppearanceStore,
    push: PushSettingsPort,
    prefs: KeyValueStore,
    openBlockedPeople: () -> Unit,
    openAccountDeletion: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var confirmingSignOut by rememberSaveable { mutableStateOf(false) }
    var notifications: AndroidNotificationSettings? = null
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        notifications?.onPermissionResult()
    }
    val model = remember(store, push) {
        AndroidNotificationSettings(
            context = context,
            port = push,
            scope = scope,
            launchPermissionRequest = {
                NotificationAskRecord.markAsked(prefs)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
            },
            everAsked = { NotificationAskRecord.asked(prefs) },
        )
    }
    notifications = model

    // 보일 때마다(설정 앱에서 돌아옴 포함) 권한·채널을 다시 읽는다 — Swift `scenePhase == .active → refreshAuthorization`.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle, model) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_RESUME) model.refreshSystemState() }
        lifecycle.addObserver(observer)
        model.refreshSystemState()
        onDispose { lifecycle.removeObserver(observer) }
    }
    DisposableEffect(store) {
        store.settingsDidAppear()
        onDispose {
            store.settingsDidDisappear()
            model.clearNotice()
        }
    }

    // 바깥 매개변수를 다른 이름으로 잡는다 — 익명 객체 안의 같은 이름 호출은 읽는 사람에게 자기 멤버 호출(재귀)로 보인다.
    // Kotlin 은 지역 이름(매개변수)을 먼저 풀어 실제로는 재귀가 아니다(결함 심기로 같은 이름으로 되돌려도 시험 초록 — 동치 확인). 읽기 쉬우라고 가른다.
    val goBlockedPeople = openBlockedPeople
    val goAccountDeletion = openAccountDeletion
    val actions = remember(store) {
        object : SettingsActions {
            override fun openBlockedPeople() = goBlockedPeople()
            override fun openAccountDeletion() = goAccountDeletion()
            override fun confirmSignOut() {
                confirmingSignOut = true
            }
            override fun openUrl(url: String) {
                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            override fun share(text: String) {
                val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
                context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        }
    }

    SettingsScreen(store, appearance, actions, modifier, notifications = { NotificationSettingsSection(model) })

    if (confirmingSignOut) {
        AlertDialog(
            onDismissRequest = { confirmingSignOut = false },
            title = { Text(MeText.signOutConfirmTitle) },
            text = { Text(MeText.signOutConfirmMessage) },
            confirmButton = {
                TextButton(onClick = {
                    confirmingSignOut = false
                    scope.launch { store.signOut() }
                }) { Text(MeText.signOut) }
            },
            dismissButton = { TextButton(onClick = { confirmingSignOut = false }) { Text(SettingsText.signOutCancel) } },
        )
    }
}
