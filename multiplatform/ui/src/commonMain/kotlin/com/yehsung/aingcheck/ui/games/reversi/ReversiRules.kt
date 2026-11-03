// 원본: Sources/CheckMobileKit/Games/GamesReversiRules.swift:61-169(규칙 시트 · 예시 판 한 장) @ ios-1017-int 3e5051ed
//
// 폰 아잉 뒤집기 **규칙 시트** — 줄 목록(`ReversiPhoneText.rules` — 열 줄, 마지막 줄 "리버시와 같은 규칙이에요") + 예시 판 네 장(`GamesReversiRuleExample.all` — 규칙
// 코어로 계산한 판). 숫자 셋은 **로비 응답 값**이다(상수를 베끼지 않는다). 시트의 주인은 화면 루트이고 코어 깃발 `isRulesVisible` 로 연다(로비·대국 화면의 책 버튼이
// 같은 깃발을 켠다 — 체스와 같은 관례). 보통명칭 '리버시'는 **설명으로만** 쓴다.
package com.yehsung.aingcheck.ui.games.reversi

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiRuleExample
import com.yehsung.aingcheck.core.stores.reversi.ReversiPhoneText
import com.yehsung.aingcheck.ui.games.gomoku.BoardGroup
import com.yehsung.aingcheck.ui.games.gomoku.BoardRow
import com.yehsung.aingcheck.ui.games.gomoku.BoardSectionHeader
import com.yehsung.aingcheck.ui.games.gomoku.BoardSheetOverlay
import com.yehsung.aingcheck.ui.games.gomoku.BoardText
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 규칙 시트 — 문구 표의 줄을 번호와 함께 그리고, 그 아래 예시 판 네 장(두 칸씩 · 큰 글자는 한 칸씩). 닫기는 왼쪽 위 ✕ 하나. */
@Composable
internal fun BoxScope.ReversiRulesSheet(turnSeconds: Int, lossStreak: Int, inviteTtlSeconds: Int, onClose: () -> Unit) {
    val colors = AingTheme.colors
    val lines = ReversiPhoneText.rules(turnSeconds, lossStreak, inviteTtlSeconds)
    BoardSheetOverlay(ReversiPhoneText.rulesTitle, onDismiss = onClose, testTag = ReversiScreenTags.rulesSheet) {
        Column(Modifier.fillMaxWidth().heightIn(max = 1300.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
            BoardGroup {
                lines.forEachIndexed { index, line ->
                    BoardRow(divider = index != lines.size - 1, modifier = Modifier.clearAndSetSemantics { contentDescription = line }) {
                        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text("${index + 1}", style = BoardText.digits(BoardText.caption()).copy(fontWeight = FontWeight.Bold), color = colors.accent,
                                modifier = Modifier.widthIn(min = 18.dp))
                            Text(line, style = BoardText.rowSubtitle(), color = colors.label, modifier = Modifier.weight(1f))
                        }
                    }
                }
            }
            BoardSectionHeader(ReversiPhoneText.rulesExamplesTitle)
            ReversiRuleExamples()
        }
    }
}

@Composable
private fun ReversiRuleExamples() {
    val examples = GamesReversiRuleExample.all
    val columns = if (reversiLargeFont()) 1 else 2
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val gap = 14.dp
        val tileWidth = (maxWidth - gap * (columns - 1)) / columns
        Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
            for (row in examples.chunked(columns)) {
                Row(horizontalArrangement = Arrangement.spacedBy(gap), verticalAlignment = Alignment.Top) {
                    for (example in row) ReversiRuleExampleTile(example, tileWidth)
                    repeat(columns - row.size) { Spacer(Modifier.width(tileWidth)) }
                }
            }
        }
    }
}

/** 예시 판 한 장 + 제목 + 설명. 판은 대국 판과 같은 그림이고 뒤집힌 돌에만 주황 고리를 얹는다. */
@Composable
private fun ReversiRuleExampleTile(example: GamesReversiRuleExample, width: Dp) {
    val colors = AingTheme.colors
    // 판은 폭(최대 220)에 맞춰 8 의 배수로 내린다(칸이 정수가 되게).
    val side = maxOf(8f, kotlin.math.floor(minOf(width.value, 220f) / 8f) * 8f).dp
    Column(Modifier.width(width).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        ReversiBoardCanvas(
            ReversiBoardPicture(board = example.board, legalTargets = example.dots, lastStoneIdx = example.lastStone, rings = example.flipped, ringColor = colors.pending),
            side = side,
        )
        Text(example.title, style = BoardText.rowTitle(), color = colors.accent)
        Text(example.detail, style = BoardText.rowSubtitle(), color = colors.label2)
    }
}
