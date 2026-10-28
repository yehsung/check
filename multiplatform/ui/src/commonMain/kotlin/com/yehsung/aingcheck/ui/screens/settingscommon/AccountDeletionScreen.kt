// 원본: Sources/CheckMobileKit/Me/MeAccountDeletionView.swift @ 3bd04bd (계정 삭제 시트)
//
// 계정 삭제(Play 계정 삭제 정책 · iOS 5.1.1(v) 와 같은 자리 — 앱 안에서 지울 수 있어야 한다).
// 위에서 아래로: 머리(✕ · 제목) → 무엇이 지워지는지 한 줄 + 목록 → 되돌릴 수 없음(경고) → 제보는 익명으로 남는다 → 비밀번호 재입력 →
// 실패 문구 → [영구 삭제](위험 색). **삭제를 부르는 곳은 이 파일뿐이고, 이 파일 안에서도 단추 하나뿐이다**(소스 계약 — 키보드 완료 키는
// 키보드만 내린다: 로그인 폼처럼 제출에 묶으면 키보드를 닫으려는 습관 한 번에 계정이 영구 삭제된다). 도는 중에는 ✕ 를 잠근다.
// 순서(재인증 → 사진 → delete_my_account → 로컬 정리)는 세션 스토어(W2-a deleteAccount)가 지킨다 — 이 화면은 [onDelete] 하나만 부른다.
// Android 경로(성공 뒤 이 기기 정리 · 로그인 화면)는 androidApp …/screens/account(AccountDeletionFlow)가 [onDelete] 로 넘긴다.
package com.yehsung.aingcheck.ui.screens.settingscommon

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.accountDeletionDidDisappear
import com.yehsung.aingcheck.core.stores.me.canDeleteAccount
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

object AccountDeletionTags {
    const val CLOSE = "account-deletion-close"
    const val PASSWORD = "account-deletion-password"
    const val CONFIRM = "account-deletion-confirm"
    const val NOTICE = "account-deletion-notice"
}

/**
 * @param onDelete [영구 삭제] — 껍데기가 `AccountDeletionFlow.run`(스토어 deleteAccount → 성공이면 Android 정리)을 띄운다. 이 화면에서 삭제로 가는 길은 이것 하나.
 * @param onClose ✕(도는 중이면 무시한다 — 닫힌 뒤 성공하면 사용자는 왜 로그인 화면인지 모른다).
 */
@Composable
fun AccountDeletionScreen(store: MeStore, onDelete: () -> Unit, onClose: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val focus = LocalFocusManager.current
    // 시트가 닫히면 비밀번호와 실패 문구를 비운다(Swift onDisappear → accountDeletionDidDisappear).
    DisposableEffect(store) { onDispose { store.accountDeletionDidDisappear() } }
    Column(modifier.background(colors.background)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(
                onClick = { if (!store.isDeletingAccount) onClose() },
                enabled = !store.isDeletingAccount,
                modifier = Modifier.testTag(AccountDeletionTags.CLOSE),
            ) { AingIcon(AppIcon.Close, contentDescription = AccountDeletionText.close, tint = colors.label) }
            Text(MeText.deleteAccountTitle, style = MaterialTheme.typography.titleMedium, color = colors.label)
        }
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space2, bottom = AingDimens.space6),
            verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
        ) {
            Text(MeText.deleteAccountLede, style = MaterialTheme.typography.bodyMedium, color = colors.label, modifier = Modifier.padding(horizontal = 4.dp))
            InsetGroup(Modifier.semantics(mergeDescendants = true) { contentDescription = "지워지는 것: ${MeText.deleteAccountItems.joinToString(", ")}" }) {
                MeText.deleteAccountItems.forEachIndexed { index, item ->
                    GroupRow(divider = if (index == MeText.deleteAccountItems.lastIndex) RowDivider.None else RowDivider.Inset(AingDimens.cardPadding + 24.dp + AingDimens.space3)) {
                        AingIcon(AppIcon.Delete, contentDescription = null, tint = colors.danger)
                        Text(item, style = MaterialTheme.typography.bodyLarge, color = colors.label, modifier = Modifier.weight(1f))
                    }
                }
            }
            InlineNotice(MeText.deleteAccountIrreversible, NoticeKind.Warning)
            Text(MeText.deleteAccountFeedbackNote, style = MaterialTheme.typography.bodySmall, color = colors.label2, modifier = Modifier.padding(horizontal = 4.dp))
            OutlinedTextField(
                value = store.accountDeletionPassword,
                onValueChange = { store.accountDeletionPassword = it },
                label = { Text(MeText.deleteAccountPasswordPrompt) },
                leadingIcon = { AingIcon(AppIcon.Lock, contentDescription = null, tint = colors.label2) },
                singleLine = true,
                enabled = !store.isDeletingAccount,
                visualTransformation = PasswordVisualTransformation(),
                // 완료 키는 키보드만 내린다 — 삭제는 [영구 삭제] 단추 하나로만 나간다(소스 계약).
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { focus.clearFocus() }),
                modifier = Modifier.fillMaxWidth().testTag(AccountDeletionTags.PASSWORD),
            )
            Text(MeText.deleteAccountPasswordHelp, style = MaterialTheme.typography.bodySmall, color = colors.label2, modifier = Modifier.padding(horizontal = 4.dp))
            store.accountDeletionNotice?.let { InlineNotice(it, NoticeKind.Error, Modifier.testTag(AccountDeletionTags.NOTICE)) }
            Button(
                onClick = {
                    if (!store.canDeleteAccount) return@Button
                    focus.clearFocus()
                    onDelete()
                },
                enabled = store.canDeleteAccount,
                colors = ButtonDefaults.buttonColors(containerColor = colors.danger, contentColor = colors.onAccentFill),
                modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp).padding(top = AingDimens.space1).testTag(AccountDeletionTags.CONFIRM),
            ) {
                if (store.isDeletingAccount) {
                    CircularProgressIndicator(Modifier.padding(end = 8.dp).heightIn(max = 18.dp), strokeWidth = 2.dp, color = colors.onAccentFill)
                }
                Text(if (store.isDeletingAccount) MeText.deletingAccount else MeText.deleteAccountConfirm)
            }
        }
    }
}

object AccountDeletionText {
    const val close = "닫기"
}
