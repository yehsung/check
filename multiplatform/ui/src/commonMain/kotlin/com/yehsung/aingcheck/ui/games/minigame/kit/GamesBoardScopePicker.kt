// 원본: Sources/CheckMobileKit/Games/GamesMiniGameBoardScope.swift @ 1a5eeca6 (맥 MiniGameBoardScopePicker 의 폰판)
//
// 미니게임 순위 머리의 [오늘 | 역대] 전환. 글자는 코어 한 벌(MiniGameBoardScope.label · boardTitle) — 두 자만 읽어 주면 무엇을 고르는지 안 들려 TalkBack 에는 판 이름을 준다.
//  · 한 캡슐 안의 두 칸이다. 떨어진 칩 둘이면 머리 오른쪽의 다른 알약(게임 고르기)과 같은 물건으로 읽혀, 누르면 목록이 열릴 것처럼 보인다.
//  · 겉 알약은 회색(fill) · 고른 칸만 틴트 채움 + 선 — "화면당 채운 버튼은 하나" 규약에서 전환은 주요 동작이 아니다.
//  · 누름 영역 44. 보이는 칸은 26 이다(머리글을 키우지 않으면서 손가락 몫을 준다).
//  · 비활성으로 만들지 않는다 — 같은 쪽을 다시 눌러도 받는 쪽이 아무 일도 안 하고, 비활성 요소는 TalkBack 목록에서 사라진다.
package com.yehsung.aingcheck.ui.games.minigame.kit

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardScope
import com.yehsung.aingcheck.ui.theme.AingTheme

object GamesBoardScopeTags {
    fun segment(scope: MiniGameBoardScope): String = "minigame.boardScope.${scope.rawValue}"
}

@Composable
fun GamesBoardScopePicker(selected: MiniGameBoardScope, modifier: Modifier = Modifier, select: (MiniGameBoardScope) -> Unit) {
    val colors = AingTheme.colors
    Row(
        modifier.background(colors.fill, CircleShape).padding(2.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        for (scope in MiniGameBoardScope.entries) {
            val isSelected = scope == selected
            Box(
                Modifier
                    .clip(CircleShape)
                    .background(if (isSelected) colors.accentTint else Color.Transparent, CircleShape)
                    .border(1.dp, if (isSelected) colors.accentLine else Color.Transparent, CircleShape)
                    .heightIn(min = 26.dp)
                    .clickable(role = Role.Button) { select(scope) }
                    .testTag(GamesBoardScopeTags.segment(scope))
                    .semantics {
                        contentDescription = scope.boardTitle
                        this.selected = isSelected
                    }
                    .padding(horizontal = 12.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    scope.label, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                    color = if (isSelected) colors.accent else colors.label2, maxLines = 1,
                )
            }
        }
    }
}
