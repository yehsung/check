// 원본: Sources/check/RummyExitFlow.swift:144 (RummyExitConfirmOverlay) · Sources/check/RummyPanel.swift:611 (RummyConfirmOverlay) @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §6
// 나가기 확인. 다음 갈래가 모양을 다듬을 수 있다(서명은 껍데기 GamesRummyScreen 이 부른다).
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
import com.yehsung.aingcheck.ui.theme.AingTheme

/** [decision] = 스토어가 묻는 판단. 묻지 않는 판단이면 아무것도 그리지 않는다. */
@Composable
fun GamesRummyExitDialog(decision: RummyCloseDecision, onKeep: () -> Unit, onConfirm: () -> Unit) {
    val copy = RummyPhoneText.exit(decision) ?: return
    val colors = AingTheme.colors
    ModalPresenceMark()
    AlertDialog(
        onDismissRequest = onKeep,
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
