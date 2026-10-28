// 원본: Sources/CheckMobileKit/Games/GamesGomokuSheets.swift · Sources/CheckMobileKit/Games/GamesGomokuAIViews.swift(GamesGomokuAIColorSheet · GamesStoneDot) @ 3bd04bd
//
// 화면 안 시트 셋 — 판돈(신청) · 규칙(렌주) · AI 돌 색. 머리는 왼쪽 위 ✕ 하나(아래에 [취소]를 또 두지 않는다), 채운 단추는 화면당 하나.
//
// 판돈 시트(맥 `GomokuStakePrompt` 흐름): **아무것도 안 골라진 채** 열리고, 판돈 3·5·10(서버 CHECK — `GomokuStake` 열거)은 고르기만(다시 누르면 해제),
// 신청은 맨 아래 채운 단추 하나 — 고르기 전에는 "판돈을 고르세요"로 비활성이다. 잔액이 모자란 판돈은 흐린 가격 + 비활성, **잔액을 모르면 막지 않는다**
// (맥 0.3.29). 신청할 때 고른 값을 `selectedStake` 에 적는다(결과의 [다시 신청]이 쓴다).
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuJudgement
import com.yehsung.aingcheck.core.stores.games.GomokuPhoneText
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneRuleExample
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneStakeSelection
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStake
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuUser
import com.yehsung.aingcheck.core.stores.gomoku.canStartAIMatch
import com.yehsung.aingcheck.core.stores.gomoku.startAIMatch
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/** 판돈 시트. 공유 미러(나 탭 상점 구매도 적는다)를 먼저 읽는다 — `GamesStore.rubyBalance` 와 같은 순서. */
@Composable
internal fun BoxScope.GomokuStakeSheet(gomoku: GomokuStore, target: GomokuUser, onClose: () -> Unit) {
    val colors = AingTheme.colors
    var selected by remember(target.id) { mutableStateOf<GomokuStake?>(null) }
    val balance = gomoku.host?.rubyBalance ?: gomoku.rubyBalance
    val sendable = selected?.takeIf { GomokuPhoneStakeSelection.affordable(it, balance) && !gomoku.isBusy && !gomoku.duelsLocked }
    BoardSheetOverlay(GomokuPhoneText.stakeTitle, onDismiss = onClose, subtitle = GomokuPhoneText.stakePromptTitle(target.displayName), testTag = GomokuScreenTags.stakeSheet) {
        BoardGroup {
            BoardRow(minHeight = 64.dp) {
                BoardAvatar(target.displayName, target.id, 44.dp, working = target.isWorking)
                Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                    BoardPersonName(target.displayName, center = target.center)
                    Text(
                        selected?.let { GomokuPhoneText.stakePromptChosen(it.rawValue.toInt()) } ?: GomokuPhoneText.stakePromptCaption,
                        style = BoardText.digits(BoardText.rowSubtitle()),
                        color = if (selected == null) colors.label2 else colors.accent,
                    )
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            for (stake in GomokuStake.entries) {
                val isSelected = selected == stake
                val affordable = GomokuPhoneStakeSelection.affordable(stake, balance)
                val enabled = affordable && !gomoku.isBusy
                val shape = RoundedCornerShape(AingDimens.tileRadius)
                Column(
                    Modifier.weight(1f).defaultMinSize(minHeight = 72.dp)
                        .background(if (isSelected) colors.accentTint else colors.surface, shape)
                        .border(2.dp, if (isSelected) colors.accent else Color.Transparent, shape)
                        .clickable(enabled = enabled) { selected = GomokuPhoneStakeSelection.toggled(selected, stake) }
                        .padding(vertical = 12.dp)
                        .testTag(GomokuScreenTags.stakeOption(stake.rawValue))
                        .semantics(mergeDescendants = true) {
                            contentDescription = "판돈 루비 ${stake.rawValue}"
                            this.selected = isSelected
                        },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
                        BoardRuby(20.dp, Modifier.alpha(if (affordable) 1f else 0.5f))
                        Text("${stake.rawValue}", style = BoardText.digits(BoardText.title3()), color = if (affordable) colors.label else colors.label3Text)
                    }
                    Text(GomokuPhoneText.stakeGain(stake.rawValue.toInt()), style = BoardText.digits(BoardText.caption()), color = if (affordable) colors.label2 else colors.label3Text)
                    if (isSelected) AingIcon(AppIcon.CheckCircleFill, contentDescription = null, size = 16.dp, tint = colors.accent)
                }
            }
        }
        Column(Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(GomokuPhoneText.myRubyTitle, style = BoardText.rowSubtitle(), color = colors.label2)
                if (balance != null) {
                    BoardRuby(14.dp)
                    Text("$balance", style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label)
                } else {
                    Text("–", style = BoardText.rowSubtitle(), color = colors.label2)
                }
                if (GomokuStake.entries.any { !GomokuPhoneStakeSelection.affordable(it, balance) }) {
                    Text("· " + GomokuPhoneText.stakeShortfall, style = BoardText.rowSubtitle(), color = colors.label2)
                }
            }
            Text(GomokuPhoneText.stakeCaption, style = BoardText.rowSubtitle(), color = colors.label2)
        }
        BoardButton(
            selected?.let { GomokuPhoneText.challengeWithStake(it.rawValue.toInt()) } ?: GomokuPhoneText.stakePromptCaption,
            kind = BoardButtonKind.Filled, fillsWidth = true, enabled = sendable != null, testTag = GomokuScreenTags.stakeSend,
        ) {
            val stake = sendable ?: return@BoardButton
            gomoku.selectedStake = stake
            onClose()
            gomoku.scope.launch { gomoku.challenge(target.id) }
        }
    }
}

/** 규칙 시트: 설명 일곱 줄 + 예시 판 여섯(맥 `GomokuRulesOverlay` 와 같은 내용 — 렌주: 흑 3-3·4-4·장목 금수, 백 장목 승). */
@Composable
internal fun BoxScope.GomokuRulesSheet(onClose: () -> Unit) {
    val colors = AingTheme.colors
    BoardSheetOverlay(GomokuPhoneText.rulesTitle, onDismiss = onClose, subtitle = GomokuPhoneText.subtitle, testTag = GomokuScreenTags.rulesSheet) {
        Column(Modifier.fillMaxWidth().heightIn(max = 560.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(AingDimens.space4)) {
            BoardGroup {
                val lines = GomokuPhoneRuleExample.ruleLines
                lines.forEachIndexed { index, line ->
                    BoardRow(divider = index != lines.size - 1, dividerInset = AingDimens.cardPadding + 22.dp + AingDimens.space3) {
                        Box(Modifier.size(22.dp).background(colors.accentTint, CircleShape), contentAlignment = Alignment.Center) {
                            Text("${index + 1}", style = BoardText.digits(BoardText.caption()).copy(fontWeight = FontWeight.Bold), color = colors.accent)
                        }
                        Text(line, style = BoardText.subheadline(), color = colors.label, modifier = Modifier.weight(1f))
                    }
                }
            }
            GomokuPhoneRuleExample.all.chunked(2).forEach { pair ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    pair.forEach { example -> RuleExampleTile(example, Modifier.weight(1f)) }
                    if (pair.size == 1) Box(Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun RuleExampleTile(example: GomokuPhoneRuleExample, modifier: Modifier) {
    val colors = AingTheme.colors
    val good = example.expected == GomokuJudgement.Win || example.expected == GomokuJudgement.Legal
    var widthPx by remember { mutableStateOf(0) }
    val density = LocalDensity.current
    Column(
        modifier.background(colors.surface, RoundedCornerShape(AingDimens.tileRadius)).padding(10.dp).semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.fillMaxWidth().aspectRatio(1f).onSizeChanged { widthPx = it.width }) {
            if (widthPx > 0) {
                GomokuBoardCanvas(
                    GomokuBoardPicture(
                        board = example.board, marks = example.marks, showsCoordinates = false,
                        lines = GomokuPhoneRuleExample.cropLines, originX = GomokuPhoneRuleExample.cropOriginX, originY = GomokuPhoneRuleExample.cropOriginY, insetRatio = 0.07,
                    ),
                    side = with(density) { widthPx.toDp() },
                )
            }
        }
        // 되는 수는 초록이 아니다(초록 = 근무 중·달성) — 기본 글자 + 체크, 금수만 빨강 + ✕.
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
            AingIcon(if (good) AppIcon.CheckCircleFill else AppIcon.CancelFill, contentDescription = null, size = 16.dp, tint = if (good) colors.label2 else colors.danger)
            Text(example.title, style = BoardText.subheadline().copy(fontWeight = FontWeight.Bold), color = if (good) colors.label else colors.danger)
        }
        Text(example.detail, style = BoardText.caption(), color = colors.label2)
    }
}

/** AI 돌 색 시트 — 고르면 바로 시작한다(걸 것이 없어 확인 단계를 두지 않는다 — 맥과 같다). */
@Composable
internal fun BoxScope.GomokuAIColorSheet(gomoku: GomokuStore, onClose: () -> Unit) {
    val colors = AingTheme.colors
    val enabled = gomoku.canStartAIMatch
    BoardSheetOverlay(GomokuPhoneText.aiPromptTitle, onDismiss = onClose, subtitle = GomokuPhoneText.aiPromptCaption, testTag = GomokuScreenTags.aiSheet) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            for (color in listOf(GomokuColor.black, GomokuColor.white)) {
                Column(
                    Modifier.weight(1f).defaultMinSize(minHeight = 96.dp)
                        .background(colors.surface, RoundedCornerShape(AingDimens.tileRadius))
                        .clickable(enabled = enabled) { onClose(); gomoku.startAIMatch(color) }
                        .padding(vertical = 14.dp, horizontal = 8.dp)
                        .testTag("gomoku-ai-${color.rawValue}"),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Box(Modifier.size(30.dp).background(if (color == GomokuColor.black) GomokuStoneInk.black else GomokuStoneInk.white, CircleShape).border(1.dp, colors.separator, CircleShape))
                    Text(if (color == GomokuColor.black) GomokuPhoneText.aiPlayBlack else GomokuPhoneText.aiPlayWhite,
                        style = BoardText.subheadline().copy(fontWeight = FontWeight.SemiBold), color = if (enabled) colors.label else colors.label2)
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin)) {
            AingIcon(AppIcon.Memory, contentDescription = null, size = 15.dp, tint = colors.accent)
            Text(GomokuPhoneText.aiNoRecord, style = BoardText.rowSubtitle(), color = colors.label2)
        }
    }
}
