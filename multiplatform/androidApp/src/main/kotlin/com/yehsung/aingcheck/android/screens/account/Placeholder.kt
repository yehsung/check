// 자리표시 — 계정 삭제(E§4.1: 재인증 → 아바타 삭제 → delete_my_account → 로컬 정리). 주인: W3-b. 셸(W1-g)이 둔다.
package com.yehsung.aingcheck.android.screens.account

import androidx.compose.runtime.Composable
import com.yehsung.aingcheck.android.shell.PlaceholderScreen

@Composable
fun AccountDeletionPlaceholder() = PlaceholderScreen("계정 삭제", "W3-b 계정", detail = "비밀번호 재인증 뒤에만")
