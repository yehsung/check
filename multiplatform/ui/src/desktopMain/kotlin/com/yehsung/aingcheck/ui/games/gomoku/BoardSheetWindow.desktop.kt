// 원본: 없음 — 데스크톱 창은 탭 막대 · 상태 바가 없어 화면 안 덮개로 충분하다(따로 뜬 OS 창을 만들지 않는다).
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.runtime.Composable

/** 데스크톱: 판 시트는 화면 안 덮개. */
internal actual val BoardSheetsInWindowByDefault: Boolean = false

/** 데스크톱은 이 창을 쓰지 않는다(판 시트 기본이 화면 안). 누가 참을 흘려도 내용은 그린다. */
@Composable
internal actual fun BoardConfirmWindow(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    content()
}
