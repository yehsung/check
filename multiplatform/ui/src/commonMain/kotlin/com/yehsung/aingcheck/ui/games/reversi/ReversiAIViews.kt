// 원본: Sources/CheckMobileKit/Games/GamesReversiAI.swift:72-198(입구 카드 · 돌 색 시트) @ ios-1017-int 467aec40
//
// 폰 아잉 뒤집기 **로봇 연습**(맥 [AI와 두기] 와 같은 단계·흐름): 입구 → 돌 색 고르기(흑 · 백 · 무작위) → **고르면 곧바로 판**(걸 것이 없어 확인 단계가 없다) →
// 대국 화면([ReversiMatchView] — 1:1 과 같은 화면, 판 종류별 차이는 `GamesReversiMatchChrome`) → 결과에서 [같은 색으로 다시 두기].
// 규칙·시계·AI·애니메이션은 **전부 코어**다(`ReversiStoreAI`). 사람 시계는 화면이 보이고 안 가려졌을 때만 돈다 — 그 깃발은 게임 탭 스토어의 화면 수명이 켠다.
// ★ 입구를 여는 판정은 코어 `canStartAIMatch` **하나**다. 이 파일은 닫혔을 때 **무엇을 말할지**만 고른다(`GamesReversiAIEntry.block`).
// 로봇 판은 서버를 안 타므로 비로그인·서버 준비 중·판돈 깃발 꺼짐에서도 연다(로그인을 보지 않는다).
package com.yehsung.aingcheck.ui.games.reversi

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiAIColorChoice
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiAIEntry
import com.yehsung.aingcheck.core.stores.reversi.ReversiPhoneText
import com.yehsung.aingcheck.core.stores.reversi.ReversiStore
import com.yehsung.aingcheck.core.stores.reversi.ReversiUser
import com.yehsung.aingcheck.core.stores.reversi.startAIMatch
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.games.gomoku.BoardGroup
import com.yehsung.aingcheck.ui.games.gomoku.BoardNotice
import com.yehsung.aingcheck.ui.games.gomoku.BoardPortrait
import com.yehsung.aingcheck.ui.games.gomoku.BoardRow
import com.yehsung.aingcheck.ui.games.gomoku.BoardSheetOverlay
import com.yehsung.aingcheck.ui.games.gomoku.BoardText
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 로비의 [로봇과 연습하기] 카드. 맥은 로비 머리글에만 버튼을 세운다(판 중에 새 판을 열 길을 두지 않는다) — 폰도 로비에만 있다. 누르면 돌 색 시트(주인은 화면 루트). */
@Composable
internal fun ReversiAIEntryCard(reversi: ReversiStore, onPlay: () -> Unit) {
    val colors = AingTheme.colors
    val entry = GamesReversiAIEntry.of(reversi)
    BoardGroup(
        Modifier.clickable(enabled = entry.canStart, role = Role.Button, onClickLabel = ReversiPhoneText.aiNoRecord, onClick = onPlay)
            .semantics(mergeDescendants = true) {}
            .testTag(ReversiScreenTags.aiEntry),
    ) {
        BoardRow(minHeight = AingDimens.rowHeightTwoLine) {
            BoardPortrait(ReversiUser.reversiAI.characterID, CharacterMood.Plain, 36.dp, stoneIsBlack = null, modifier = Modifier.alpha(if (entry.canStart) 1f else 0.5f))
            Column(Modifier.weight(1f)) {
                Text(ReversiPhoneText.aiButton, style = BoardText.rowTitle(), color = if (entry.canStart) colors.label else colors.label2)
                Text(entry.caption, style = BoardText.rowSubtitle(), color = colors.label2)
            }
            if (entry.canStart) AingIcon(AppIcon.ChevronRight, contentDescription = null, size = 18.dp, tint = colors.label3)
        }
    }
}

/**
 * 돌 색 시트(맥 `ReversiAIPrompt`): 흑 · 백 · 무작위 — 누르면 **곧바로 시작**한다. 닫기는 왼쪽 위 ✕ 하나. 시트가 떠 있는 동안 1:1 판이 서거나 신청을 보내면
 * 세 칸이 비활성으로 바뀐다(판정은 코어 `canStartAIMatch` 하나). 큰 글자에서는 세로로 — 세 칸을 한 줄에 두면 "나중에 둬요"가 낱글자로 꺾인다.
 */
@Composable
internal fun BoxScope.ReversiAIColorSheet(reversi: ReversiStore, onClose: () -> Unit) {
    val colors = AingTheme.colors
    val entry = GamesReversiAIEntry.of(reversi)
    BoardSheetOverlay(ReversiPhoneText.aiPromptTitle, onDismiss = onClose, subtitle = ReversiPhoneText.aiPromptCaption, testTag = ReversiScreenTags.aiColorSheet) {
        val option: @Composable (GamesReversiAIColorChoice, Modifier) -> Unit = { choice, m -> ReversiAIColorOption(choice, entry.canStart, m) {
            onClose()
            reversi.startAIMatch(choice.humanColor)
        } }
        if (LocalDensity.current.fontScale >= 1.15f) {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                for (choice in GamesReversiAIColorChoice.entries) option(choice, Modifier.fillMaxWidth())
            }
        } else {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for (choice in GamesReversiAIColorChoice.entries) option(choice, Modifier.weight(1f))
            }
        }
        entry.block?.let { BoardNotice(ReversiPhoneText.aiBlock(it)) }
        Row(Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            AingIcon(AppIcon.Memory, contentDescription = null, size = 15.dp, tint = colors.accent)
            Text(ReversiPhoneText.aiNoRecord, style = BoardText.rowSubtitle(), color = colors.label2)
        }
    }
}

@Composable
private fun ReversiAIColorOption(choice: GamesReversiAIColorChoice, enabled: Boolean, modifier: Modifier, onPick: () -> Unit) {
    val colors = AingTheme.colors
    Column(
        modifier.defaultMinSize(minHeight = 96.dp)
            .background(colors.surface, RoundedCornerShape(AingDimens.tileRadius))
            .clickable(enabled = enabled, role = Role.Button, onClickLabel = ReversiPhoneText.aiNoRecord, onClick = onPick)
            .padding(vertical = 14.dp, horizontal = 6.dp)
            .semantics(mergeDescendants = true) {}
            .testTag(ReversiScreenTags.aiColor(choice.name)),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        ReversiStoneDot(choice.humanColor, 30.dp)
        Text(choice.title, style = BoardText.subheadline().copy(fontWeight = FontWeight.SemiBold), color = if (enabled) colors.label else colors.label2, textAlign = TextAlign.Center)
    }
}
