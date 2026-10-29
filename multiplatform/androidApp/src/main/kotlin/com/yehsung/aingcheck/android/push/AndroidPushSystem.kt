// 원본: Sources/CheckMobileKit/Push/PushNotificationCenterAdapter.swift(UNUserNotificationCenter · UIApplication 어댑터의 Android 판) @ 3bd04bd
// W2-f `PhonePushSystem` 의 Android 구현(조립 몫). 판단은 조정자(feature/phone)가 하고, 여기는 시스템에 시키기만 한다.
//   · 권한: API 33+ `POST_NOTIFICATIONS` 런타임 권한(E§6.5) — 미결정/거절은 "한 번 물었는가"를 앱 저장소에 적어 가른다(시스템은 둘을
//     같은 값으로 돌려준다). 26~32 는 기본 허락이고, 사용자가 앱 알림을 끄면(areNotificationsEnabled) 거절로 읽는다.
//   · 토큰: Firebase 가 초기화된 빌드(release 조립 지점 — FirebaseBootstrap)에서만 `FirebaseMessaging.getToken`. 아니면 실패로 알린다
//     (debug·stub·시험은 실제 제공자를 부르지 않는다 — E§12).
//   · 배지: Android 는 앱 아이콘 숫자를 적는 공식 API 가 없다(런처가 알림 수로 센다 — E§6.5). 받은 값만 기억한다.
package com.yehsung.aingcheck.android.push

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.feature.phone.push.PhonePushAuthorization
import com.yehsung.aingcheck.feature.phone.push.PhonePushSystem
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class AndroidPushSystem(
    private val context: Context,
    private val prefs: KeyValueStore,
    /** 기기 API 수준(시험이 26~32 와 33+ 갈래를 둘 다 잰다). */
    private val sdkInt: Int = Build.VERSION.SDK_INT,
    /** Firebase 가 초기화됐는가(release 조립 지점만 — 시험·debug 는 거짓). */
    private val firebaseReady: () -> Boolean = { FirebaseApp.getApps(context).isNotEmpty() },
) : PhonePushSystem {
    /** 토큰 받기 결과(조립이 `PhonePushCoordinator.didReceivePushToken` · `didFailToRegister` 로 잇는다). */
    var onToken: (String) -> Unit = {}
    var onTokenFailure: (String) -> Unit = {}

    /**
     * 권한 창을 띄우는 문(API 33+). Activity 의 `registerForActivityResult(RequestPermission)` 이 있어야 띄울 수 있어 셸(MainActivity)이
     * 단다. 없으면(Activity 가 없는 순간) 창 없이 false.
     */
    var permissionRequester: (suspend () -> Boolean)? = null

    private val primer = MutableStateFlow(false)

    /** 설명 시트를 그릴지(셸 NavGraph 가 `NotificationPrimerSheet` 로 그린다 — 시트의 두 단추는 조정자의 primerAllow · primerLater). */
    val isPrimerVisible: StateFlow<Boolean> = primer.asStateFlow()

    /** 마지막으로 받은 배지 숫자(공식 API 가 없어 적지 않는다 — 메시지 알림의 setNumber 재료). */
    var lastBadgeCount: Int? = null
        private set

    override suspend fun authorizationStatus(): PhonePushAuthorization {
        val appEnabled = NotificationManagerCompat.from(context).areNotificationsEnabled()
        if (sdkInt < TIRAMISU) return if (appEnabled) PhonePushAuthorization.authorized else PhonePushAuthorization.denied
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        return when {
            granted && appEnabled -> PhonePushAuthorization.authorized
            granted -> PhonePushAuthorization.denied
            prefs.getBoolean(ASKED_KEY) == true -> PhonePushAuthorization.denied
            else -> PhonePushAuthorization.notDetermined
        }
    }

    override suspend fun requestAuthorization(): Boolean {
        if (sdkInt < TIRAMISU) return authorizationStatus() == PhonePushAuthorization.authorized
        val requester = permissionRequester ?: return false
        prefs.putBoolean(ASKED_KEY, true)
        requester()
        return authorizationStatus() == PhonePushAuthorization.authorized
    }

    override fun registerForRemoteNotifications() {
        if (!firebaseReady()) {
            onTokenFailure(FAILURE_NO_FIREBASE)
            return
        }
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            val value = if (task.isSuccessful) task.result else null
            if (value.isNullOrEmpty()) onTokenFailure(task.exception?.let { it::class.simpleName } ?: FAILURE_EMPTY) else onToken(value)
        }
    }

    override fun unregisterForRemoteNotifications() {
        if (!firebaseReady()) return
        FirebaseMessaging.getInstance().deleteToken()
    }

    override fun removeAllDeliveredNotifications() {
        NotificationManagerCompat.from(context).cancelAll()
    }

    override fun setBadgeCount(count: Int) {
        lastBadgeCount = count
    }

    override fun openSystemSettings() {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    override fun presentPermissionPrimer() {
        primer.value = true
    }

    override fun dismissPermissionPrimer() {
        primer.value = false
    }

    companion object {
        /** Android 13(API 33) — `POST_NOTIFICATIONS` 런타임 권한이 생긴 판. */
        const val TIRAMISU: Int = 33

        /** 권한 창을 한 번이라도 띄웠는가(기기 값 — 로그아웃해도 남는다). 미결정과 거절을 가르는 유일한 재료다. */
        const val ASKED_KEY: String = "aingcheck.push.permissionAsked"

        const val FAILURE_NO_FIREBASE: String = "firebase-not-initialized"
        const val FAILURE_EMPTY: String = "empty-token"
    }
}
