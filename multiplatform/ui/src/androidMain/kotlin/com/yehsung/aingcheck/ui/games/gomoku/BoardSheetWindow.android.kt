// 원본: Sources/CheckMobileKit/Games/GamesGomokuScreen.swift @ 3bd04bd (.sheet — 창 전체를 덮는다)
package com.yehsung.aingcheck.ui.games.gomoku

import android.view.WindowManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider

/** Android 앱: 판 시트는 창 전체(상태 바 · 탭 막대까지 어둡게 — iOS `.sheet`). */
internal actual val BoardSheetsInWindowByDefault: Boolean = true

/** Android 앱: 확인 카드는 대화상자 창. 막은 창의 뒤 어둡게(시스템이 상태 바 · 탭 막대까지 깐다) — 값은 판 시트 막과 같은 검정 × 0.32. */
@Composable
internal actual fun BoardConfirmWindow(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        val window = (LocalView.current.parent as? DialogWindowProvider)?.window
        SideEffect {
            window?.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            window?.setDimAmount(BoardSheetScrim.alpha)
        }
        content()
    }
}
