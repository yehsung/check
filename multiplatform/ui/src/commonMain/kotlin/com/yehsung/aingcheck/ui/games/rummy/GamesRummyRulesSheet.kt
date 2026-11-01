// 원본: Sources/check/RummyPanel.swift:558 (RummyRulesOverlay) @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §6
// 자리표시 — 다음 갈래가 이 파일을 통째로 채운다(지금은 글자만 — 예시 타일 없음).
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesHeaderBar
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesSheet
import com.yehsung.aingcheck.ui.games.minigame.kit.rowSubtitleStyle
import com.yehsung.aingcheck.ui.games.minigame.kit.rowTitleStyle
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 규칙 시트 — 문구 표 [RummyPhoneText.ruleList] 를 그대로 그린다. */
@Composable
fun GamesRummyRulesSheet(onDismiss: () -> Unit) {
    val colors = AingTheme.colors
    GamesSheet(onDismiss) {
        GamesHeaderBar(RummyPhoneText.rulesTitle, onBack = onDismiss, backIcon = AppIcon.Close)
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.space3).testTag(GamesRummyTags.RULES),
            verticalArrangement = Arrangement.spacedBy(AingDimens.space3),
        ) {
            for (rule in RummyPhoneText.ruleList) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(rule.title, style = rowTitleStyle(), color = colors.label)
                    Text(rule.detail, style = rowSubtitleStyle(), color = colors.label2)
                }
            }
        }
    }
}
