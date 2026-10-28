// 원본: Sources/CheckMobileKit/Games/GamesChessSheets.swift · Sources/CheckMobileKit/Games/GamesChessScreen.swift:534-689(GamesChessStakeSheet) @ 3bd04bd
//
// 1:1 체스 화면 안 시트 셋 — 승격 고르기 · 규칙 보기 · 판돈. 오목 짝과 같은 머리·바탕·단추 규약(왼쪽 위 ✕ 하나 · 채운 단추는 화면당 하나).
// **문구는 한 줄도 여기서 만들지 않는다** — 전부 core/stores 의 `ChessPhoneText`.
package com.yehsung.aingcheck.ui.games.chess

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.rules.chess.ChessPieceKind
import com.yehsung.aingcheck.core.stores.chess.ChessPhoneRuleLine
import com.yehsung.aingcheck.core.stores.chess.ChessPhoneText
import com.yehsung.aingcheck.core.stores.chess.ChessPromotionPrompt
import com.yehsung.aingcheck.core.stores.chess.ChessStake
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.chess.ChessUser
import com.yehsung.aingcheck.core.stores.games.GamesChessStakeSelection
import com.yehsung.aingcheck.core.stores.games.GamesChessStakeSend
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.ui.games.gomoku.BoardAvatar
import com.yehsung.aingcheck.ui.games.gomoku.BoardButton
import com.yehsung.aingcheck.ui.games.gomoku.BoardButtonKind
import com.yehsung.aingcheck.ui.games.gomoku.BoardGroup
import com.yehsung.aingcheck.ui.games.gomoku.BoardPersonName
import com.yehsung.aingcheck.ui.games.gomoku.BoardRow
import com.yehsung.aingcheck.ui.games.gomoku.BoardRuby
import com.yehsung.aingcheck.ui.games.gomoku.BoardSheetOverlay
import com.yehsung.aingcheck.ui.games.gomoku.BoardText
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/**
 * 승격 시트.
 * INV-GamesChessSheets-5cceae79 이식: 입력 2단의 **셋째 단**이다 — 도착 칸이 같은 합법 수가 넷일 때만 열린다(코어 `promotion` 이 섰는지만 본다). 고르기 전에는 수가
 *   나가지 않는다 — 네 말 중 하나를 눌러야 `chess_move` 가 떠난다.
 * INV-GamesChessSheets-907ac246 이식: 내려가는 길을 **둘로 묶어 뒀다** — 바깥 막을 눌러 닫는 길은 두지 않고([BoardSheetOverlay] 의 onDismiss 도 같은 문), ✕ 와
 *   [다른 수 두기] 둘 다 `chess.cancelPromotion()` 을 지난다. 그 문을 안 지나는 길이 있으면 스토어에 `promotion` 이 남아 폰이 도착 칸에 뜬 채 굳는다.
 * INV-GamesChessMatch-7c7cb75f 이식: 대국 화면은 **닫는 길을 따로 만들지 않는다** — 시트가 쥔 문 하나다(Android 뒤로가기도 같은 `cancelPromotion()` — ChessBackPlan).
 * INV-GamesChessAIViews-5ab9ca4c 이식: 로봇 화면도 같다 — 그 문을 **다시 지나기만** 한다(단계가 이미 접혔으면 아무것도 하지 않는다).
 */
@Composable
internal fun BoxScope.ChessPromotionSheet(chess: ChessStore, prompt: ChessPromotionPrompt, myColor: ChessColor) {
    val colors = AingTheme.colors
    val cancel = { if (chess.promotion != null) chess.cancelPromotion() }
    BoardSheetOverlay(ChessPhoneText.promotionTitle, onDismiss = cancel, subtitle = ChessPhoneText.promotionCaption, testTag = ChessScreenTags.promotionSheet) {
        prompt.choices.chunked(2).forEach { pair ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
                pair.forEach { kind ->
                    Column(
                        Modifier.weight(1f).defaultMinSize(minHeight = 104.dp).background(colors.surface, RoundedCornerShape(AingDimens.tileRadius))
                            .clickable(enabled = !chess.isBusy) { chess.scope.launch { chess.choosePromotion(kind) } }
                            .padding(vertical = 12.dp).testTag("chess-promote-${kind.rawValue}")
                            .semantics(mergeDescendants = true) { contentDescription = ChessPhoneText.pieceName(kind) },
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        ChessPieceTile(kind, myColor, 56.dp)
                        Text(ChessPhoneText.pieceName(kind), style = BoardText.subheadline().copy(fontWeight = FontWeight.Bold), color = colors.label)
                    }
                }
            }
        }
        BoardButton(ChessPhoneText.promotionCancel, kind = BoardButtonKind.Gray, fillsWidth = true, onClick = cancel)
    }
}

/**
 * 승격 시트의 말 한 칸 그림.
 * INV-GamesChessSheets-08fb10ff 이식: 유니코드 글리프 자리표시를 걷어낸 자리다 — 판은 벡터 실루엣인데 시트만 글리프면 **같은 말이 두 모양**이다. 판과 같은 한 벌
 *   ([ChessPieceArt])과 같은 색 상수(ChessBoardInk)로 그린다.
 */
@Composable
internal fun ChessPieceTile(kind: ChessPieceKind, color: ChessColor, side: Dp) {
    val colors = AingTheme.colors
    androidx.compose.foundation.Canvas(Modifier.size(side).background(colors.fill, RoundedCornerShape(8.dp))) {
        val path = ChessPieceArt.path(kind, Rect(0f, 0f, size.width, size.height))
        val white = color == ChessColor.white
        drawPath(path, if (white) ChessBoardInk.whitePiece else ChessBoardInk.blackPiece)
        drawPath(path, if (white) ChessBoardInk.whitePieceEdge else ChessBoardInk.blackPieceEdge, style = Stroke(maxOf(0.8f * density, size.minDimension * 0.035f)))
    }
}

/** 규칙 시트: FIDE 요약 여덟 줄(시간 수치는 **스토어가 서버에서 받은 값**). 예시 판은 두지 않는다(체스는 한 국면이 규칙 하나를 말해 주지 않는다). */
@Composable
internal fun BoxScope.ChessRulesSheet(initialMs: Long, incrementMs: Long, inviteTtlSeconds: Int, onClose: () -> Unit) {
    val colors = AingTheme.colors
    val lines = ChessPhoneRuleLine.all(initialMs, incrementMs, inviteTtlSeconds)
    BoardSheetOverlay(ChessPhoneText.rulesTitle, onDismiss = onClose, subtitle = ChessPhoneText.subtitle(initialMs, incrementMs), testTag = ChessScreenTags.rulesSheet) {
        Column(Modifier.fillMaxWidth().heightIn(max = 560.dp).verticalScroll(rememberScrollState())) {
            BoardGroup {
                lines.forEachIndexed { index, line ->
                    BoardRow(divider = index != lines.size - 1, dividerInset = AingDimens.cardPadding + 22.dp + AingDimens.space3, minHeight = 56.dp) {
                        Box(Modifier.size(22.dp).background(colors.accentTint, CircleShape), contentAlignment = Alignment.Center) {
                            Text("${index + 1}", style = BoardText.digits(BoardText.caption()).copy(fontWeight = FontWeight.Bold), color = colors.accent)
                        }
                        Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                            Text(line.title, style = BoardText.subheadline().copy(fontWeight = FontWeight.Bold), color = colors.label)
                            Text(line.detail, style = BoardText.rowSubtitle(), color = colors.label2)
                        }
                    }
                }
            }
        }
    }
}

/**
 * 판돈 시트 — **아무것도 안 골라진 채** 열리고, 판돈 3·5·10(서버 CHECK — `ChessStake`)은 고르기만, 신청은 맨 아래 채운 단추 하나.
 * INV-GamesChessScreen-a86d17f4 이식: 캡션이 **거짓말을 하지 않는 것**이 이 시트의 계약이다 — 신청만 한 상태에서는 0원도 안 움직이고 양쪽에서 빠지는 것은
 *   **수락하는 순간**이다(신청은 60초 뒤 만료되고 그때도 루비 이동이 없다). 캡션은 `ChessPhoneText.stakeCaption`(수락하는 순간 …) 그대로다.
 * 신청을 낼 수 있는가는 `GamesChessStakeSend.sendable` **한 곳**이다(요청이 나가는 마지막 문 — §8-17 깃발 · 잔액 · 다른 게임 판 · 내 판 · 보낸 신청).
 */
@Composable
internal fun BoxScope.ChessStakeSheet(games: GamesStore, chess: ChessStore, target: ChessUser, onClose: () -> Unit) {
    val colors = AingTheme.colors
    var selected by remember(target.id) { mutableStateOf<ChessStake?>(null) }
    val balance: Int? = games.rubyBalance
    val facts = remember(chess) { ChessGateFacts(chess) }
    val sendable = GamesChessStakeSend.sendable(selected?.rawValue?.toInt(), facts, balance, games.chessEntryBlock, duelsEnabled = !chess.duelsLocked)
    BoardSheetOverlay(ChessPhoneText.stakeTitle, onDismiss = onClose, subtitle = ChessPhoneText.stakePromptTitle(target.displayName), testTag = ChessScreenTags.stakeSheet) {
        BoardGroup {
            BoardRow(minHeight = 64.dp) {
                BoardAvatar(target.displayName, target.id, 44.dp, working = target.isWorking)
                Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
                    BoardPersonName(target.displayName, center = target.center)
                    Text(selected?.let { ChessPhoneText.stakePromptChosen(it.rawValue) } ?: ChessPhoneText.stakePromptCaption,
                        style = BoardText.digits(BoardText.rowSubtitle()), color = if (selected == null) colors.label2 else colors.accent)
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            for (stake in ChessStake.entries) {
                val isSelected = selected == stake
                val affordable = GamesChessStakeSelection.affordable(stake.rawValue.toInt(), balance)
                val shape = RoundedCornerShape(AingDimens.tileRadius)
                Column(
                    Modifier.weight(1f).defaultMinSize(minHeight = 72.dp)
                        .background(if (isSelected) colors.accentTint else colors.surface, shape)
                        .border(2.dp, if (isSelected) colors.accent else Color.Transparent, shape)
                        .clickable(enabled = affordable && !chess.isBusy) {
                            val next = GamesChessStakeSelection.toggled(selected?.rawValue?.toInt(), stake.rawValue.toInt())
                            selected = next?.let { v -> ChessStake.entries.first { it.rawValue.toInt() == v } }
                        }
                        .padding(vertical = 12.dp).testTag(ChessScreenTags.stakeOption(stake.rawValue))
                        .semantics(mergeDescendants = true) { contentDescription = ChessPhoneText.stakeOptionAccessibility(stake.rawValue); this.selected = isSelected },
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
                        BoardRuby(20.dp, Modifier.alpha(if (affordable) 1f else 0.5f))
                        Text("${stake.rawValue}", style = BoardText.digits(BoardText.title3()), color = if (affordable) colors.label else colors.label3Text)
                    }
                    Text(ChessPhoneText.stakeGain(stake.rawValue), style = BoardText.digits(BoardText.caption()), color = if (affordable) colors.label2 else colors.label3Text)
                    if (isSelected) AingIcon(AppIcon.CheckCircleFill, contentDescription = null, size = 16.dp, tint = colors.accent)
                }
            }
        }
        Column(Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(ChessPhoneText.myRubyTitle, style = BoardText.rowSubtitle(), color = colors.label2)
                if (balance != null) { BoardRuby(14.dp); Text("$balance", style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label) }
                else Text(ChessPhoneText.unknownNumber, style = BoardText.rowSubtitle(), color = colors.label2)
                if (ChessStake.entries.any { !GamesChessStakeSelection.affordable(it.rawValue.toInt(), balance) }) {
                    Text(ChessPhoneText.bulletPrefix + ChessPhoneText.stakeShortfall, style = BoardText.rowSubtitle(), color = colors.label2)
                }
            }
            Text(ChessPhoneText.stakeCaption, style = BoardText.rowSubtitle(), color = colors.label2)
        }
        BoardButton(
            selected?.let { ChessPhoneText.challengeWithStake(it.rawValue) } ?: ChessPhoneText.stakePromptCaption,
            kind = BoardButtonKind.Filled, fillsWidth = true, enabled = sendable != null, testTag = ChessScreenTags.stakeSend,
        ) {
            val stake = sendable ?: return@BoardButton
            // 고른 값을 스토어에 적고(결과의 [다시 신청]이 쓴다) 신청은 여기 한 곳에서만 나간다.
            chess.selectedStake = ChessStake.entries.first { it.rawValue.toInt() == stake }
            onClose()
            chess.scope.launch { chess.challenge(target.id) }
        }
    }
}
