// 원본: Sources/check/RummyExitFlow.swift:144 (RummyExitConfirmOverlay) · Sources/check/RummyPanel.swift:611 (RummyConfirmOverlay) @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §6
//
// 나가기 확인 — 판 중(이 기기가 쥔 판) 기권 · 방장 방 닫기. 묻는 판단과 고른 뒤의 일은 GamesRummyBackState → 스토어 confirmBack 한 곳이고 이 파일은 글자와 단추만 그린다.
// 놀던 기기 · 손님 나가기는 묻지 않으므로 여기 오지 않는다.
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.yehsung.aingcheck.core.rules.rummy.RummyCloseDecision
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.ui.components.ModalPresenceMark
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingTheme

/** [decision] = 스토어가 묻는 판단. 묻지 않는 판단이면 아무것도 그리지 않는다. */
@Composable
fun GamesRummyExitDialog(decision: RummyCloseDecision, onKeep: () -> Unit, onConfirm: () -> Unit) {
    val copy = RummyPhoneText.exit(decision) ?: return
    val colors = AingTheme.colors
    ModalPresenceMark()
    AlertDialog(
        onDismissRequest = onKeep,
        icon = {
            AingIcon(if (decision == RummyCloseDecision.confirmCloseRoom) AppIcon.Logout else AppIcon.FlagFill, contentDescription = null, tint = colors.danger)
        },
        title = { Text(copy.title) },
        text = { Text(copy.detail) },
        confirmButton = {
            TextButton(onClick = onConfirm, modifier = Modifier.testTag(GamesRummyTags.EXIT_CONFIRM)) { Text(copy.confirm, color = colors.danger) }
        },
        dismissButton = {
            TextButton(onClick = onKeep, modifier = Modifier.testTag(GamesRummyTags.EXIT_KEEP)) { Text(RummyPhoneText.keepPlaying) }
        },
        containerColor = colors.surface,
    )
}
