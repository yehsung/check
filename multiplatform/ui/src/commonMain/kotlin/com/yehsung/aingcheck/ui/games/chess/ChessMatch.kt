// 원본: Sources/CheckMobileKit/Games/GamesChessMatch.swift:298-822(GamesChessMatchView · PlayerCard · ClockLeaf · TurnLeaf · MoveList · ResultCard) @ 3bd04bd
//
// 1:1 체스 대국·결과 한 화면(시안 B 09 오목 대국 문법): (결과 카드) → 상대 카드 → 판 → 내 카드 → 차례 한 줄 → 안내 → 기보 → 수 번호 → 시계 안내,
// 아래 막대에 동작 줄. 끝난 판은 **판을 그대로 두고** 위에 결과 카드가 선다(마지막 수가 보인다). 채팅은 없다(오목에만 있다).
package com.yehsung.aingcheck.ui.games.chess

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.rules.chess.ChessPosition
import com.yehsung.aingcheck.core.stores.chess.ChessMatchState
import com.yehsung.aingcheck.core.stores.chess.ChessMoveRecord
import com.yehsung.aingcheck.core.stores.chess.ChessPhoneText
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.chess.isAIThinking
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.games.gomoku.BoardButton
import com.yehsung.aingcheck.ui.games.gomoku.BoardButtonKind
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.games.gomoku.BoardGroup
import com.yehsung.aingcheck.ui.games.gomoku.BoardPersonName
import com.yehsung.aingcheck.ui.games.gomoku.BoardPortrait
import com.yehsung.aingcheck.ui.games.gomoku.BoardRubyDelta
import com.yehsung.aingcheck.ui.games.gomoku.BoardText
import com.yehsung.aingcheck.ui.games.gomoku.rememberTicker
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/** 표의 **뜻**을 토큰으로 옮기는 한 자리(뷰에 색 리터럴을 적지 않는다). */
@Composable
internal fun ChessMatchTint.color(): Color {
    val colors = AingTheme.colors
    return when (this) {
        ChessMatchTint.good -> colors.working
        ChessMatchTint.bad -> colors.danger
        ChessMatchTint.warn -> colors.pending
        ChessMatchTint.quiet -> colors.label2
    }
}

/**
 * 탭 막대를 숨기는 화면인가(Swift `TabBarPolicy.Screen.chessMatch`) — 대국·결과(몰입 화면 + 자체 동작 줄).
 * INV-GamesChessMatch-5a07d059 이식: 탭 막대를 숨긴다 — 이 한 줄이 없어서 iOS 에서 [무승부 수락]·[기권]이 탭 막대 뒤에 통째로 가렸다(제한 시간이 도는 판에서
 *   가장 급한 단추들). Android 탭 막대는 셸(AingShell — 조립 K11)이 그리므로 화면은 [ChessScreen] 의 `onTabBarHidden` 으로 이 값을 알린다(assembly.md).
 */
object ChessTabBarPolicy {
    fun hidesTabBar(hasHumanMatch: Boolean): Boolean = hasHumanMatch
}

@Composable
internal fun ChessMatchView(chess: ChessStore, me: BoardGameMe, state: ChessScreenState) {
    val match = chess.match ?: return
    val chrome = ChessMatchChrome.make(match, chess.promotion, chess.notice, chess.isBusy, isRobotMatch = false, initialMs = chess.initialMs)
    val colors = AingTheme.colors
    Column(Modifier.fillMaxSize().testTag(ChessScreenTags.match)) {
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val side = ChessMatchChrome.side(maxWidth, maxHeight, AingDimens.sideMargin, isLargeText = maxHeight < maxWidth * 1.3f, isAccessibilitySize = false)
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                    .padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space1, bottom = AingDimens.space4),
                verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
            ) {
                chrome.result?.let { ChessResultCard(it, me, match.myColor) }
                ChessPlayerCard(chess, match.opponent.displayName, match.opponent.center, match.opponent.characterID,
                    if (match.opponent.isWorking) CharacterMood.Working else CharacterMood.Off, isMe = false, isRobot = false,
                    color = match.myColor.opponent, isTurn = !match.isFinished && match.turn == match.myColor.opponent)
                if (chrome.drawsBoard) ChessMatchBoard(chess, match, chrome, state, side)
                ChessPlayerCard(chess, me.name ?: ChessPhoneText.me, null, me.characterID, me.mood, isMe = me.name != null, isRobot = false,
                    color = match.myColor, isTurn = !match.isFinished && match.turn == match.myColor)
                ChessTurnLeaf(chess)
                chrome.statusLine?.let { FootLine(it, bold = true) }
                ChessMoveList(match.moves)
                FootLine(ChessMatchLine(chrome.plyLine, ChessMatchTint.quiet))
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    AingIcon(AppIcon.Schedule, contentDescription = null, size = 15.dp, tint = colors.label2)
                    Text(chrome.clockLine, style = BoardText.rowSubtitle(), color = colors.label2)
                }
            }
        }
        // INV-GamesChessMatch-a4b43f95 이식: 동작 줄은 **스크롤 밖**이다(아래 막대). 본문 상자(weight)가 막대 높이를 뺀 높이를 받으므로 판 예산도 저절로 맞는다.
        // INV-GamesChessMatch-d7625074 이식: 왜 스크롤 밖인가 — 큰 글자에서 [기권]·[무승부 제안]이 화면 마지막 줄에 잘렸고, 무승부 제안을 받은 판은 [무승부 수락]이
        //   한 조각만 남았다. 제한 시간이 도는 판에서 "스크롤하면 닿는다"는 충분하지 않다.
        ChessActionBar(chess, match, chrome, state)
    }
}

/**
 * 판 한 장.
 * INV-GamesChessMatch-0934db71 이식: position 은 **서버가 확인한 국면**이고, 갈 수 있는 칸은 코어가 합쳐 둔 `match.legalMoves` 에서 온 `selection` 이다 —
 *   화면은 합법 수를 만들지 않고 낙관적으로 고치지도 않는다.
 * INV-GamesChessMatch-8634816b 이식: 말이 미끄러지는 애니메이션은 **배선이 `windowDidShow()` 를 부른 뒤에만** 온다 — 애니메이션 주인이 창 가시성으로 막는다
 *   ([ChessFlightTracker.observe] 의 거절 ①). 이 화면은 그 깃발을 켜지 않는다(게임 탭 스토어의 화면 수명 훅이 켠다).
 * INV-GamesChessMatch-d29bfa63 이식: 판 레인에 넘기는 것은 **화면 폭이 아니라 열 폭**이다([ChessMatchChrome.side] 가 여백을 뺀 예산으로 잰다).
 * INV-GamesChessMatch-53cb25a7 이식: 판을 그리는 갈래는 `chrome.drawsBoard`(= position != null) 안에서만 서므로 빈 국면 대체는 **닿지 않는 갈래**다.
 */
@Composable
private fun ChessMatchBoard(chess: ChessStore, match: ChessMatchState, chrome: ChessMatchChrome, state: ChessScreenState, side: androidx.compose.ui.unit.Dp) {
    val position: ChessPosition = match.position ?: return
    @Suppress("UNUSED_VARIABLE") val version = state.flightVersion
    if (!chess.isWindowVisible || chess.isWindowOccluded) state.matchFlight.clear()
    val flight = state.matchFlight.observe(match.id, match.plyCount, position, match.lastMove, chess.isWindowVisible, chess.isWindowOccluded, chess.clock())
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        ChessBoard(
            position = position, flight = flight, whiteAtBottom = chrome.whiteAtBottom,
            selection = chess.selection?.from, legalTargets = chess.selection?.targets ?: emptySet(),
            lastMove = match.lastMove?.let { it.from to it.to }, checkSquare = chrome.checkSquare,
            onTapSquare = { square -> chess.scope.launch { chess.tap(square) } },
            side = side,
            onFlightFinished = { generation -> state.matchFlight.expire(generation); state.flightVersion += 1 },
            accessibility = ChessPhoneText.boardAccessibility(match.plyCount, match.turn, match.isInCheck),
            testTag = ChessScreenTags.board,
        )
    }
}

@Composable
private fun FootLine(line: ChessMatchLine, bold: Boolean = false) {
    Text(line.text, style = BoardText.rowSubtitle().copy(fontWeight = if (bold) FontWeight.SemiBold else FontWeight.Normal), color = line.tint.color(), modifier = Modifier.fillMaxWidth())
}

/** 아래 막대: 끝난 판 [로비로] · 무승부 제안 [수락][거절] · 두는 중 [기권][무승부 제안]. */
@Composable
private fun ChessActionBar(chess: ChessStore, match: ChessMatchState, chrome: ChessMatchChrome, state: ChessScreenState) {
    val colors = AingTheme.colors
    Column(Modifier.fillMaxWidth().background(colors.surface)) {
        Box(Modifier.fillMaxWidth().height(AingDimens.hairline).background(colors.separator))
        Row(Modifier.fillMaxWidth().padding(horizontal = AingDimens.sideMargin, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            when (val row = chrome.actionRow) {
                is ChessMatchChrome.ActionRow.finished -> BoardButton(ChessPhoneText.backToLobby, Modifier.weight(1f), kind = BoardButtonKind.Gray, fillsWidth = true) { chess.backToLobby() }
                ChessMatchChrome.ActionRow.answerDrawOffer -> {
                    BoardButton(ChessPhoneText.acceptDraw, Modifier.weight(1f), kind = BoardButtonKind.Filled, enabled = !chess.isBusy, fillsWidth = true) { chess.scope.launch { chess.respondDraw(true) } }
                    BoardButton(ChessPhoneText.declineDraw, Modifier.weight(1f), kind = BoardButtonKind.Gray, enabled = !chess.isBusy, fillsWidth = true) { chess.scope.launch { chess.respondDraw(false) } }
                }
                is ChessMatchChrome.ActionRow.playing -> {
                    BoardButton(ChessPhoneText.resign, Modifier.weight(1f), kind = BoardButtonKind.Destructive, enabled = row.canResign, fillsWidth = true, icon = AppIcon.Flag, testTag = ChessScreenTags.resign) {
                        if (ChessMatchChrome.acceptsResignTap(state.shownAt, chess.clock())) state.confirmsResign = true
                    }
                    BoardButton(if (match.drawOfferedByMe) ChessPhoneText.drawOfferedByMe else ChessPhoneText.offerDraw, Modifier.weight(1f), kind = BoardButtonKind.Gray,
                        enabled = row.canOfferDraw, fillsWidth = true, icon = AppIcon.Equal, testTag = ChessScreenTags.offerDraw) { chess.scope.launch { chess.offerDraw() } }
                }
            }
        }
    }
}

/** 플레이어 한 장: 얼굴 · 이름(+센터 · 나) · 색 점 + 색 이름 · **자기 시계**. 차례인 카드만 초록 테두리. 시계가 **둘**인 것이 오목과 가장 다른 점이다. */
@Composable
internal fun ChessPlayerCard(chess: ChessStore, name: String, center: String?, characterID: String?, mood: CharacterMood, isMe: Boolean, isRobot: Boolean, color: ChessColor, isTurn: Boolean) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(AingDimens.groupRadius)
    Row(
        Modifier.fillMaxWidth().background(colors.surface, shape).border(2.dp, if (isTurn) colors.workingDot else Color.Transparent, shape).padding(horizontal = 14.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(AingDimens.space3), verticalAlignment = Alignment.CenterVertically,
    ) {
        BoardPortrait(characterID, mood, 44.dp, stoneIsBlack = color == ChessColor.black)
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
            BoardPersonName(name, center = center, isMe = isMe)
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                ChessColorDot(color, 10.dp)
                Text(ChessPhoneText.stoneName(color), style = BoardText.rowSubtitle(), color = colors.label2)
                if (isRobot) AingIcon(AppIcon.Memory, contentDescription = null, size = 12.dp, tint = colors.accent)
            }
        }
        ChessClockLeaf(chess, color, isTurn)
    }
}

/** 색 점(흰 · 검정 — 물건). */
@Composable
internal fun ChessColorDot(color: ChessColor, size: androidx.compose.ui.unit.Dp) {
    val colors = AingTheme.colors
    Box(Modifier.size(size).background(if (color == ChessColor.white) ChessBoardInk.whitePiece else ChessBoardInk.blackPiece, CircleShape).border(1.dp, colors.label3, CircleShape))
}

/**
 * 한쪽 시계 — **잎**.
 * INV-GamesChessMatch-ac0ff9f3 이식: **폰이 세지 않는다** — 서버가 준 네 칸(`white_ms_left`·`black_ms_left`·가산·차례 시작 시각)에서 파생한 초를 글자로 옮길
 *   뿐이고, 이 잎은 어떤 값도 증감시키지 않는다. 차례가 아니거나 화면이 안 보이면 한 틱도 돌지 않는다.
 * INV-GamesChessMatch-0f022ebc 이식: `now` 는 **스토어 시계**다(펌프는 다시 그리게 깨우기만 한다 — `turnStartedAt` 이 그 시계 축으로 보정돼 있다).
 */
@Composable
private fun ChessClockLeaf(chess: ChessStore, color: ChessColor, isTurn: Boolean) {
    val colors = AingTheme.colors
    val tick = rememberTicker(running = chess.isWindowVisible && isTurn, periodMillis = 200)
    val remaining = tick.let { chess.remainingSeconds(color, chess.clock()) ?: 0.0 }
    val face = ChessMatchChrome.clockFace(remaining, isTurn)
    Text(
        face.text, style = BoardText.digits(BoardText.title3()), color = face.tint.color(), maxLines = 1,
        modifier = Modifier.background(if (isTurn) colors.fill else colors.fill2, RoundedCornerShape(12.dp)).padding(horizontal = 10.dp, vertical = 6.dp)
            .clearAndSetSemantics { contentDescription = ChessPhoneText.clockAccessibility(remaining, color) }.testTag("chess-clock-${color.rawValue}"),
    )
}

/**
 * 차례 한 줄(내 차례 · 체크 · 결과 확인 중).
 * INV-GamesChessMatch-a1317808 이식: **`now` 는 `chess.clock()` 이다** — 깃발 판정이 비교하는 `turnStartedAt` 은 서버 epoch 을 그 시계 축으로 옮긴 값이라,
 *   기기 벽시계를 섞으면 어긋남만큼이 "흐른 시간"으로 계산된다(고정 시계 데모에서 진행 중 대국이 전부 "결과를 확인하고 있어요"로 떴다).
 * INV-GamesChessMatch-45c323eb 이식: 시각을 **주입하는 것이 아니다** — 운영 경로도 같은 한 줄을 지나고 그 시계가 벽시계다(분기 없음). 시계의 권위는 서버에 있다.
 */
@Composable
private fun ChessTurnLeaf(chess: ChessStore) {
    val match = chess.match ?: return
    val tick = rememberTicker(running = chess.isWindowVisible, periodMillis = 200)
    val line = tick.let { ChessMatchChrome.turnLine(match, chess.clock(), chess.graceSeconds, chess.isAIThinking) }
    Text(line.text, style = BoardText.rowTitle(), color = line.tint.color(), modifier = Modifier.fillMaxWidth().testTag("chess-turn-line"))
}

/** 기보 한 줄(가로 스크롤). SAN 은 **서버가 만든 것**을 그대로 쓴다(앱이 다시 만들면 두 벌이 갈린다). */
@Composable
private fun ChessMoveList(moves: List<ChessMoveRecord>) {
    val colors = AingTheme.colors
    Column(Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = ChessPhoneText.movesTitle }, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(ChessPhoneText.movesTitle, style = androidx.compose.material3.MaterialTheme.typography.labelSmall, color = colors.label2)
        if (moves.isEmpty()) {
            Text(ChessPhoneText.noMoves, style = BoardText.rowSubtitle(), color = colors.label2)
        } else {
            Row(Modifier.horizontalScroll(rememberScrollState(Int.MAX_VALUE)), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                val lastSeq = moves.last().seq
                for (record in moves) {
                    val isLast = record.seq == lastSeq
                    Row(Modifier.background(if (isLast) colors.accentTint else colors.fill, RoundedCornerShape(8.dp)).padding(horizontal = 7.dp, vertical = 4.dp),
                        horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        if (record.color == ChessColor.white) Text("${(record.seq + 1) / 2}.", style = androidx.compose.material3.MaterialTheme.typography.labelSmall, color = colors.label3Text)
                        Text(record.san, style = BoardText.digits(BoardText.rowSubtitle()).copy(fontWeight = if (isLast) FontWeight.Bold else FontWeight.Normal), color = if (isLast) colors.label else colors.label2)
                    }
                }
            }
        }
    }
}

/** 승/패/무 · 끝난 이유 · 루비 변화. 판은 그대로 아래 남는다(마지막 수가 보인다). */
@Composable
private fun ChessResultCard(result: ChessMatchChrome.Result, me: BoardGameMe, myColor: ChessColor) {
    val colors = AingTheme.colors
    BoardGroup(Modifier.semantics(mergeDescendants = true) {}.testTag("chess-result")) {
        Row(Modifier.fillMaxWidth().padding(AingDimens.cardPadding), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
            BoardPortrait(me.characterID, me.mood, 60.dp, stoneIsBlack = myColor == ChessColor.black)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(result.title, style = BoardText.title2(), color = result.tint.color())
                Text(result.reason, style = BoardText.subheadline(), color = colors.label2)
                result.rubyNote?.let { Text(it, style = BoardText.caption(), color = colors.label2) }
            }
            if (result.showsRubyDelta) BoardRubyDelta(result.rubyDelta, result.rubyDeltaText)
        }
    }
}
