// 원본: Sources/CheckMobileKit/Me/MeAccountDeletionView.swift @ 3bd04bd (시트 — 도는 중에는 닫히지 않는다 · confirm 은 Task 하나)
//
// 계정 삭제 껍데기(Android). 공용 화면(ui …/screens/settingscommon AccountDeletionScreen)의 [영구 삭제] 를 AccountDeletionFlow(스토어 삭제 → 성공이면
// Android 정리)로 잇는다. 도는 중에는 뒤로가기로도 닫히지 않는다(닫힌 뒤 성공하면 사용자는 왜 로그인 화면인지 모른다 — Swift interactiveDismissDisabled).
// 조립(K11)은 NavGraph 의 AccountDeletionPlaceholder 줄을 이 화면으로 바꾼다(assembly.md).
package com.yehsung.aingcheck.android.screens.account

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.ui.screens.settingscommon.AccountDeletionScreen
import kotlinx.coroutines.launch

@Composable
fun AccountDeletionRouteScreen(store: MeStore, cleanup: AndroidAccountCleanup, onClose: () -> Unit, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    val flow = remember(store, cleanup) { AccountDeletionFlow(store, cleanup) }
    // 도는 중에는 뒤로가기를 먹는다(아무 일도 안 한다).
    BackHandler(enabled = store.isDeletingAccount) {}
    AccountDeletionScreen(
        store = store,
        onDelete = { scope.launch { flow.run() } },
        onClose = onClose,
        modifier = modifier,
    )
}
