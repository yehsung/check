// 원본: Sources/check/RummyPanel.swift:558 (RummyRulesOverlay) @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §6
//
// 규칙 시트. 글자는 문구 표 RummyPhoneText.ruleList 한 곳(터치 기준으로 다시 쓴 글자) · 예시 타일은 그 줄의 면 글자로 그린다.
// 맥은 넓은 덮개에 두 단으로 놓았고 폰은 한 단이다 — 글자 아래 타일.
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.rummy.RummyTileSize
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesSheet
import com.yehsung.aingcheck.ui.games.minigame.kit.rowSubtitleStyle
import com.yehsung.aingcheck.ui.games.minigame.kit.rowTitleStyle
import com.yehsung.aingcheck.ui.screens.session.kit.SheetHeader
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 규칙 시트 — 그룹·런·첫 등록·조커·판 조작·조작·판 보기·받침대·시간·기권·끝과 점수·등수 분배. */
@Composable
fun GamesRummyRulesSheet(onDismiss: () -> Unit) {
    GamesSheet(onDismiss) {
        SheetHeader(RummyPhoneText.rulesTitle, onClose = onDismiss, closeLabel = RummyPhoneText.close)
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.space3).testTag(GamesRummyTags.RULES),
            verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
        ) {
            for (rule in RummyPhoneText.ruleList) RuleCard(rule)
        }
    }
}

@Composable
private fun RuleCard(rule: RummyPhoneText.Rule) {
    val colors = AingTheme.colors
    val faces = remember(rule) { rule.example.mapNotNull { RummyFace.of(it) } }
    val shape = RoundedCornerShape(AingDimens.innerRadius)
    Column(
        Modifier.fillMaxWidth().background(colors.surface, shape).padding(AingDimens.space3),
        verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(rule.title, style = rowTitleStyle(), color = colors.accent)
            Text(rule.detail, style = rowSubtitleStyle(), color = colors.label2)
        }
        if (faces.isNotEmpty()) {
            Row(
                Modifier.background(colors.fill, RoundedCornerShape(9.dp)).padding(5.dp),
                horizontalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                for (face in faces) GamesRummyTile(face, RummyTileSize.table)
            }
        }
    }
}
