// 원본: Sources/CheckMobileKit/Me/MeAccountDeletionView.swift @ 3bd04bd (confirm → store.deleteAccount)
// 원본: Sources/CheckMobileKit/Session/MobileSessionStore.swift:304-345 @ 3bd04bd (삭제 순서 — 재인증 → 사진 → delete_my_account → 로컬 정리)
//
// 계정 삭제의 Android 경로(④ — 6차 int-h unresolved '[착수 W3-b] 계정 삭제 Android 경로'). 순서가 계약이다:
//  1~4. 세션 스토어(W2-a deleteAccount): 비밀번호 재인증(signIn) → 사진 지우기(실패 무시) → `delete_my_account`(재인증 토큰) → 로컬 정리(금고 토큰 ·
//       사용자 칸 · 세션 고리 onLocalUserDataCleared — 위젯 스냅숏 비우기는 그 고리에 붙는 W2-f 몫). 실패면 **로그인 상태 그대로** 이유 한 줄.
//  5. 성공했을 때만 이 기기의 Android 흔적을 지운다(AndroidAccountCleanup — 아래 순서):
//     ① 알림 서랍의 남은 알림 전부 내리기(지운 계정의 메시지 본문·보낸 사람이 서랍에 남지 않게)
//     ② FCM 토큰 지우기(서버 행은 cascade 로 이미 없다 — 같은 토큰이 다음 계정에 그대로 옮겨 가지 않게. W2-f 푸시 몫이 꽂는다)
//     ③ 위젯 넷 다시 그리기(스냅숏이 비었으니 로그인 안내로)
//     로그인 화면으로 가는 일은 세션 단계(SignedOut)가 한다 — 셸이 SessionNavHost 로 바꾼다.
// 실패한 삭제는 5 를 하지 않는다(로그인 상태 그대로 — 알림·토큰·위젯을 건드리면 살아 있는 계정의 알림이 끊긴다).
package com.yehsung.aingcheck.android.screens.account

import android.content.Context
import androidx.core.app.NotificationManagerCompat
import com.yehsung.aingcheck.android.widget.AingWidgetUpdater
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.deleteAccount

/** 삭제가 끝난 뒤 이 기기에서 할 일(순서 그대로 부른다). */
interface AndroidAccountCleanup {
    /** ① 알림 서랍 비우기. */
    fun cancelNotifications()

    /** ② FCM 토큰 지우기(W2-f 푸시 몫 — FirebaseMessaging.deleteToken). 실패는 삼킨다(다음 로그인이 토큰을 옮긴다). */
    suspend fun deletePushToken()

    /** ③ 위젯 다시 그리기. */
    suspend fun refreshWidgets()
}

/** Android 기본 구현. [deletePushToken] 은 조립이 W2-f 푸시 조정자의 토큰 지우기를 꽂는다(Firebase 를 초기화하지 않는 변형은 아무것도 안 한다). */
class DefaultAndroidAccountCleanup(
    private val context: Context,
    private val pushTokenDeleter: suspend () -> Unit = {},
) : AndroidAccountCleanup {
    override fun cancelNotifications() = NotificationManagerCompat.from(context).cancelAll()

    override suspend fun deletePushToken() {
        try {
            pushTokenDeleter()
        } catch (error: Throwable) {
            if (error is kotlinx.coroutines.CancellationException) throw error
        }
    }

    override suspend fun refreshWidgets() = AingWidgetUpdater.updateAll(context)
}

/** [영구 삭제] 한 번. 화면(AccountDeletionScreen)의 onDelete 가 이것을 띄운다 — 삭제로 가는 길은 이것 하나. */
class AccountDeletionFlow(private val store: MeStore, private val cleanup: AndroidAccountCleanup) {
    /** 지웠으면 true(이 기기 정리까지 끝났다), 아니면 false(로그인 상태 그대로 — 이유는 store.accountDeletionNotice). */
    suspend fun run(): Boolean {
        val deleted = store.deleteAccount()
        if (!deleted) return false
        cleanup.cancelNotifications()
        cleanup.deletePushToken()
        cleanup.refreshWidgets()
        return true
    }
}
