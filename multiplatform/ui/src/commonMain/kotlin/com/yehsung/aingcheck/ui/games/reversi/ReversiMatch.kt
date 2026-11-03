// 원본: Sources/CheckMobileKit/Games/GamesReversiMatch.swift:250-731(대국·결과 화면 · 두 사람 카드 · 30초 링 · 생각 중 · 차례 한 줄 · 수 기록 · 결과 카드) @ ios-1017-int 467aec40
//
// 폰 아잉 뒤집기 **대국·결과 화면**. 사람끼리 1:1 판과 로봇 연습 판이 **한 화면**이다(코어가 두 판을 같은 `match` 칸에 싣는다 — `match.isAI`). 판 종류별 차이와
// 돈이 갈리는 판정(결과 · 루비 · 무승부 환불 · 동작 줄)은 전부 core/stores [GamesReversiMatchChrome] 이 쥔다 — 이 파일은 배치만 한다.
//
// 지키는 계약(iOS 머리 그대로):
//  ① **서버가 권위다.** 판·차례·시계·결과는 코어 `match` 만 그린다 — 낙관적 착수·낙관적 루비가 없다.
//  ⑥ **초 단위 값은 잎만** 읽는다(30초 링 · 차례 한 줄 · 3초 테두리). 화면 루트는 시계를 읽지 않는다.
//  ⑦ **둘 수 있는 칸은 코어 `legalTargets` 하나**(1:1 은 서버 목록, 로봇 판은 로컬 규칙 — 화면은 어느 쪽인지 모른다).
//  ⑩ 30초가 지나면 서버(로봇 판은 코어)가 대신 두고, 연속 `autoAbandonStreak` 번이면 진다 — 화면은 그 사실을 **글자로** 말한다.
//  · 동작 줄은 **스크롤 밖**(아래 막대)이다 — 큰 글자에서 [기권]이 화면 마지막 줄에서 잘렸다(체스 실측). 본문 상자(weight)가 막대 높이를 뺀 높이를 받으므로 판 예산도 맞는다.
//  · 기권은 **불투명 확인 덮개**를 지난다(화면 루트가 쥔다). TalkBack: 차례 한 줄 · 결과 카드는 바뀌면 읽어 준다(정중한 실시간 영역).
package com.yehsung.aingcheck.ui.games.reversi

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneResignGuard
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiMatchChrome
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiMoveLog
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiBoardLayout
import com.yehsung.aingcheck.core.stores.reversi.ReversiMatchLine
import com.yehsung.aingcheck.core.stores.reversi.ReversiMatchState
import com.yehsung.aingcheck.core.stores.reversi.ReversiMatchTint
import com.yehsung.aingcheck.core.stores.reversi.ReversiPhoneText
import com.yehsung.aingcheck.core.stores.reversi.ReversiStore
import com.yehsung.aingcheck.core.stores.reversi.ReversiUser
import com.yehsung.aingcheck.core.stores.reversi.isAIThinking
import com.yehsung.aingcheck.core.stores.reversi.restartAIMatch
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiCounts
import com.yehsung.aingcheck.core.wire.games.ReversiPly
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

/** 표의 **뜻**을 토큰으로 옮기는 한 자리(글자 색). */
@Composable
internal fun ReversiMatchTint.color(): Color {
    val colors = AingTheme.colors
    return when (this) {
        ReversiMatchTint.good -> colors.working
        ReversiMatchTint.bad -> colors.danger
        ReversiMatchTint.warn -> colors.pending
        ReversiMatchTint.quiet -> colors.label2
    }
}

/** 링·점 색(iOS `GamesChessInk.dot`) — 채운 도형은 점 토큰. */
@Composable
internal fun ReversiMatchTint.dot(): Color {
    val colors = AingTheme.colors
    return when (this) {
        ReversiMatchTint.good -> colors.workingDot
        ReversiMatchTint.bad -> colors.danger
        ReversiMatchTint.warn -> colors.pendingDot
        ReversiMatchTint.quiet -> colors.label3
    }
}

/** 큰 글자 두 단계(iOS `typeSize >= .xLarge` · `isAccessibilitySize` 자리). 판 예산만 쓴다. */
@Composable
private fun reversiTextSizes(): Pair<Boolean, Boolean> {
    val scale = LocalDensity.current.fontScale
    return (scale >= 1.15f) to (scale >= 1.3f)
}

/**
 * 아잉 뒤집기 대국·결과 한 화면: (결과 카드) → 상대 카드 → 판 → 내 카드 → 차례·안내 줄 → 수 기록 → 아래 동작 막대.
 * 끝난 판은 **판을 그대로 두고** 위에 결과 카드가 선다(마지막 수가 뒤집히는 것까지 보여야 왜 끝났는지 안다).
 */
@Composable
internal fun ReversiMatchView(reversi: ReversiStore, me: BoardGameMe, state: ReversiScreenState) {
    val match = reversi.match ?: return
    val chrome = GamesReversiMatchChrome.make(match, reversi.notice, reversi.isBusy, reversi.turnSeconds)
    val (largeText, accessibilitySize) = reversiTextSizes()
    Column(Modifier.fillMaxSize().testTag(ReversiScreenTags.match)) {
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val side = GamesReversiBoardLayout.side(maxWidth.value.toDouble(), maxHeight.value.toDouble(), AingDimens.sideMargin.value.toDouble(), largeText, accessibilitySize).dp
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                    .padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space1, bottom = AingDimens.space4),
                verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
            ) {
                chrome.result?.let { ReversiResultCard(it, me, match.myColor) }
                val opponentColor = match.myColor.opponent
                ReversiPlayerCard(
                    reversi = reversi,
                    characterID = if (chrome.isAI) ReversiUser.reversiAI.characterID else match.opponent.characterID,
                    mood = if (chrome.isAI) CharacterMood.Plain else if (match.opponent.isWorking) CharacterMood.Working else CharacterMood.Off,
                    name = chrome.opponentName, center = if (chrome.isAI) null else match.opponent.center, isMe = false,
                    color = opponentColor,
                    subtitle = GamesReversiMatchChrome.cardSubtitle(opponentColor, match.counts, match.opponentAutoStreak, match.autoAbandonStreak),
                    isTurn = !match.isFinished && match.turn == opponentColor, isAI = chrome.isAI, turnSeconds = chrome.turnSeconds,
                )
                ReversiMatchBoard(reversi, match, side)
                ReversiPlayerCard(
                    reversi = reversi, characterID = me.characterID, mood = me.mood,
                    name = me.name ?: ReversiPhoneText.me, center = null, isMe = me.name != null,
                    color = match.myColor,
                    subtitle = GamesReversiMatchChrome.cardSubtitle(match.myColor, match.counts, match.myAutoStreak, match.autoAbandonStreak),
                    isTurn = !match.isFinished && match.turn == match.myColor, isAI = false, turnSeconds = chrome.turnSeconds,
                )
                ReversiStatusLines(reversi, match, chrome)
                ReversiMoveList(match.plies, match.counts)
            }
        }
        ReversiActionBar(reversi, chrome, state)
    }
}

/** 판 한 장. 둘 수 있는 칸은 코어 `legalTargets`(⑦). 끝난 판은 입력이 없다. 내 차례 마지막 3초에 판 안쪽 가장자리가 빨갛게 빛난다. */
@Composable
private fun ReversiMatchBoard(reversi: ReversiStore, match: ReversiMatchState, side: Dp) {
    val colors = AingTheme.colors
    val interactive = !match.isFinished
    val intensity = rememberReversiWarningIntensity(reversi)
    val shadow = if (colors.isDark) ReversiBoardInk.shadowDark else ReversiBoardInk.shadowLight
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        ReversiPlayBoard(
            store = reversi, matchID = match.id, board = match.board, side = side,
            legalTargets = if (interactive) reversi.legalTargets else emptySet(),
            lastStoneIdx = match.lastStoneIdx, autoStones = match.autoStones,
            turn = if (match.isFinished) null else match.turn,
            onTap = if (interactive) { idx -> reversi.scope.launch { reversi.place(idx) } } else null,
            warningIntensity = intensity,
            modifier = Modifier.shadow(9.dp, RoundedCornerShape(side * 0.025f), ambientColor = shadow, spotColor = shadow),
        )
    }
}

/** 차례 한 줄 · 안내(스토어 안내 → 패스) · 회색 점 뜻 · 3회 패 경고 · 시계 규칙. */
@Composable
private fun ReversiStatusLines(reversi: ReversiStore, match: ReversiMatchState, chrome: GamesReversiMatchChrome) {
    val colors = AingTheme.colors
    Column(Modifier.fillMaxWidth().padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (!match.isFinished) ReversiTurnLeaf(reversi)
        chrome.detailLine?.let { FootLine(it.text, it.tint.color(), bold = true) }
        chrome.autoPlacedLine?.let { FootLine(it, colors.label2) }
        chrome.autoStreakWarning?.let { FootLine(it, colors.danger, bold = true) }
        if (!match.isFinished) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                AingIcon(if (chrome.isAI) AppIcon.PauseCircle else AppIcon.Schedule, contentDescription = null, size = 15.dp, tint = colors.label2)
                Text(chrome.clockLine, style = BoardText.rowSubtitle(), color = colors.label2)
            }
        }
    }
}

@Composable
private fun FootLine(text: String, color: Color, bold: Boolean = false) {
    Text(text, style = BoardText.rowSubtitle().copy(fontWeight = if (bold) FontWeight.SemiBold else FontWeight.Normal), color = color, modifier = Modifier.fillMaxWidth())
}

/** 아래 막대: 두는 중 [기권] · 끝난 판 [로비로](+ 로봇 판 [같은 색으로 다시 두기]). */
@Composable
private fun ReversiActionBar(reversi: ReversiStore, chrome: GamesReversiMatchChrome, state: ReversiScreenState) {
    val colors = AingTheme.colors
    Column(Modifier.fillMaxWidth().background(colors.surface)) {
        Box(Modifier.fillMaxWidth().height(AingDimens.hairline).background(colors.separator))
        val padding = Modifier.fillMaxWidth().padding(horizontal = AingDimens.sideMargin, vertical = 10.dp)
        when (val row = chrome.actionRow) {
            is GamesReversiMatchChrome.ActionRow.playing -> Row(padding) {
                BoardButton(ReversiPhoneText.resign, Modifier.weight(1f), kind = BoardButtonKind.Destructive, enabled = row.canResign, fillsWidth = true,
                    icon = AppIcon.Flag, testTag = ReversiScreenTags.resign) {
                    if (GomokuPhoneResignGuard.acceptsTap(state.shownAt, reversi.clock())) state.confirmsResign = true
                }
            }
            is GamesReversiMatchChrome.ActionRow.finished -> {
                val lobby: @Composable (Modifier) -> Unit = { m ->
                    BoardButton(ReversiPhoneText.backToLobby, m, kind = BoardButtonKind.Gray, fillsWidth = true, testTag = ReversiScreenTags.backToLobby) { reversi.backToLobby() }
                }
                val again: @Composable (Modifier) -> Unit = { m ->
                    // 로봇 판의 "다시"는 같은 색의 새 로컬 판이다(맥 [다시 두기]와 같은 문 — 코어 `restartAIMatch`).
                    BoardButton(ReversiPhoneText.aiRematch, m, kind = BoardButtonKind.Filled, fillsWidth = true, icon = AppIcon.Refresh, testTag = ReversiScreenTags.rematch) {
                        reversi.restartAIMatch()
                    }
                }
                // 두 단추는 같은 높이 — 한 줄에 안 들어가는 큰 글자에서는 위아래로.
                if (row.showsPlayAgain && reversiLargeFont()) {
                    Column(padding, verticalArrangement = Arrangement.spacedBy(10.dp)) { again(Modifier); lobby(Modifier) }
                } else {
                    Row(padding, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        lobby(Modifier.weight(1f))
                        if (row.showsPlayAgain) again(Modifier.weight(1.4f))
                    }
                }
            }
        }
    }
}

// MARK: - 두 사람 카드

/** 플레이어 한 장: 캐릭터 초상(+ 돌 배지) · 이름(+ 센터 · '나') · 돌 수(+ 자동 n/3) · 오른쪽은 차례면 30초 링(로봇 차례면 "생각 중"). 차례인 카드만 초록 테두리. */
@Composable
private fun ReversiPlayerCard(
    reversi: ReversiStore,
    characterID: String?,
    mood: CharacterMood,
    name: String,
    center: String?,
    isMe: Boolean,
    color: ReversiColor,
    subtitle: String,
    isTurn: Boolean,
    isAI: Boolean,
    turnSeconds: Int,
) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(AingDimens.groupRadius)
    Row(
        Modifier.fillMaxWidth().background(colors.surface, shape).border(2.dp, if (isTurn) colors.workingDot else Color.Transparent, shape)
            .padding(horizontal = 14.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(AingDimens.space3), verticalAlignment = Alignment.CenterVertically,
    ) {
        BoardPortrait(characterID, mood, 44.dp, stoneIsBlack = color == ReversiColor.black)
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
            BoardPersonName(name, center = center, isMe = isMe)
            Text(subtitle, style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label2)
        }
        if (isTurn) {
            // 로봇 차례에는 시계가 없다(마감이 없어 링이 0초로 빨갛게 선다) — "생각 중" 표시가 그 자리에 선다(맥과 같다).
            if (isAI) ReversiThinkingMark() else ReversiTurnRing(reversi, turnSeconds)
        }
    }
}

/** 차례인 사람의 30초 링(44) — **잎**. 남은 시간은 코어가 서버 마감으로 계산한다(`remainingSeconds(now)`). 멈춘 로봇 시계(마감 없음)는 가득 찬 링이다. */
@Composable
private fun ReversiTurnRing(reversi: ReversiStore, turnSeconds: Int) {
    val tick = rememberTicker(running = reversi.isWindowVisible, periodMillis = 200)
    val remaining = tick.let { reversi.remainingSeconds(reversi.clock()) ?: turnSeconds.toDouble() }
    ReversiRing(remaining, GamesReversiMatchChrome.ringFraction(remaining, turnSeconds), GamesReversiMatchChrome.ringTint(remaining))
}

/** 링 그림 한 벌(내 판 링 · 관전 링 공용). 화면 읽기는 "남은 시간 12초" 한 덩이. */
@Composable
internal fun ReversiRing(remaining: Double, fraction: Double, tint: ReversiMatchTint) {
    val colors = AingTheme.colors
    val track = colors.fill
    val stroke = tint.dot()
    Box(Modifier.size(44.dp).padding(2.dp).clearAndSetSemantics { contentDescription = ReversiPhoneText.clockAccessibility(remaining) }, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val w = 4.dp.toPx()
            val inset = w / 2
            val arcSize = Size(size.width - w, size.height - w)
            drawArc(track, 0f, 360f, false, Offset(inset, inset), arcSize, style = Stroke(w))
            drawArc(stroke, -90f, (360 * fraction).toFloat(), false, Offset(inset, inset), arcSize, style = Stroke(w, cap = StrokeCap.Round))
        }
        Text(ReversiPhoneText.remaining(remaining), style = BoardText.digits(MaterialTheme.typography.labelMedium).copy(fontWeight = FontWeight.Bold, fontSize = 13.sp),
            color = tint.color(), maxLines = 1, overflow = TextOverflow.Clip)
    }
}

/** 로봇 차례에 링 자리(44)에 서는 "생각 중" 표시. 시계를 읽지 않는다(정지 그림 — iOS 동작 줄이기 모양). */
@Composable
private fun ReversiThinkingMark() {
    val colors = AingTheme.colors
    val accent = colors.accent
    Box(Modifier.size(44.dp).padding(2.dp).clearAndSetSemantics { contentDescription = ReversiPhoneText.aiThinking }, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val w = 4.dp.toPx()
            drawArc(accent.copy(alpha = 0.35f), 0f, 360f, false, Offset(w / 2, w / 2), Size(size.width - w, size.height - w), style = Stroke(w))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Canvas(Modifier.width(14.dp).height(5.dp)) {
                val r = size.height / 2
                for (i in 0 until 3) drawCircle(accent, r * 0.8f, Offset(r + i * (size.width - 2 * r) / 2, r))
            }
            Text(ReversiPhoneText.aiThinkingShort, style = MaterialTheme.typography.labelSmall.copy(fontSize = 9.sp, fontWeight = FontWeight.Bold), color = accent, maxLines = 1)
        }
    }
}

/**
 * 차례 한 줄(내 차례 · 상대 차례 · 생각 중 · 자동으로 놓이는 중). 마감+유예 판정이 시간에 달려 있어 잎이다. `now` 는 **스토어 시계**다.
 * TalkBack: 줄이 바뀌면 읽어 준다(차례 알림).
 */
@Composable
private fun ReversiTurnLeaf(reversi: ReversiStore) {
    val match = reversi.match ?: return
    val tick = rememberTicker(running = reversi.isWindowVisible, periodMillis = 500)
    val line: ReversiMatchLine = tick.let { GamesReversiMatchChrome.turnLine(match, reversi.clock(), reversi.graceSeconds, reversi.isAIThinking) }
    Text(line.text, style = BoardText.rowTitle(), color = line.tint.color(),
        modifier = Modifier.fillMaxWidth().testTag(ReversiScreenTags.turnLine).semantics { liveRegion = LiveRegionMode.Polite })
}

// MARK: - 수 기록

/** 수 기록 한 줄(가로 스크롤) + 머리의 돌 수. 세로 스크롤 안에 세로 스크롤을 두면 손가락이 둘 중 하나를 뺏긴다 — 수가 늘어나는 쪽은 가로다. */
@Composable
internal fun ReversiMoveList(plies: List<ReversiPly>, counts: ReversiCounts) {
    val colors = AingTheme.colors
    val chips = GamesReversiMoveLog.chips(plies)
    Column(
        Modifier.fillMaxWidth().padding(top = AingDimens.space1).clearAndSetSemantics { contentDescription = ReversiPhoneText.movesTitle + ", " + ReversiPhoneText.counts(counts) },
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(ReversiPhoneText.movesTitle, style = MaterialTheme.typography.labelSmall, color = colors.label2, modifier = Modifier.weight(1f))
            Text(ReversiPhoneText.counts(counts), style = BoardText.digits(BoardText.caption()).copy(fontWeight = FontWeight.SemiBold), color = colors.label2)
        }
        if (chips.isEmpty()) {
            Text(ReversiPhoneText.noMoves, style = BoardText.rowSubtitle(), color = colors.label2)
        } else {
            val scroll = rememberScrollState(Int.MAX_VALUE)
            LaunchedEffect(chips.last().id) { scroll.animateScrollTo(scroll.maxValue) }
            Row(Modifier.horizontalScroll(scroll).padding(vertical = 2.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                val lastID = chips.last().id
                for (chip in chips) {
                    val isLast = chip.id == lastID
                    Row(
                        Modifier.background(if (isLast) colors.accentTint else colors.fill, RoundedCornerShape(8.dp)).padding(horizontal = 7.dp, vertical = 4.dp),
                        horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically,
                    ) {
                        chip.number?.let { Text("$it.", style = MaterialTheme.typography.labelSmall, color = colors.label3Text) }
                        ReversiStoneDot(chip.color, 11.dp)
                        Text(chip.text, style = BoardText.digits(BoardText.rowSubtitle()).copy(fontWeight = if (isLast) FontWeight.Bold else FontWeight.Normal),
                            color = if (isLast) colors.label else colors.label2)
                    }
                }
            }
        }
    }
}

// MARK: - 결과 카드

/** 승/패/무 · 끝난 까닭 · 점수 줄 · 상대 줄 · 루비 변화(무승부는 ±0 + 환불 한 줄 · 로봇 판은 루비 없이 '기록 없음'). TalkBack 이 서는 순간 읽어 준다(결과 알림). */
@Composable
private fun ReversiResultCard(result: GamesReversiMatchChrome.Result, me: BoardGameMe, myColor: ReversiColor) {
    val colors = AingTheme.colors
    val portrait: @Composable () -> Unit = { BoardPortrait(me.characterID, me.mood, 60.dp, stoneIsBlack = myColor == ReversiColor.black) }
    val delta: @Composable () -> Unit = { if (result.showsRubyDelta) BoardRubyDelta(result.rubyDelta.toLong(), result.rubyDeltaText) }
    val texts: @Composable (Modifier) -> Unit = { m ->
        Column(m, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(result.title, style = BoardText.title2(), color = result.tint.color())
            Text(result.reason, style = BoardText.subheadline(), color = colors.label2)
            Text(result.scoreLine, style = BoardText.digits(BoardText.subheadline()).copy(fontWeight = FontWeight.SemiBold), color = colors.label)
            Text(result.opponentLine, style = BoardText.caption(), color = colors.label2)
            result.rubyNote?.let { Text(it, style = BoardText.caption(), color = colors.label2) }
        }
    }
    BoardGroup(Modifier.semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }.testTag(ReversiScreenTags.result)) {
        if (reversiLargeFont()) {
            // 큰 글자: 초상·루비 한 줄, 글은 그 아래 — 한 줄에 몰면 제목이 글자마다 꺾였다(오목 AX 실측).
            Column(Modifier.fillMaxWidth().padding(AingDimens.cardPadding), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    portrait()
                    Spacer(Modifier.weight(1f))
                    delta()
                }
                texts(Modifier.fillMaxWidth())
            }
        } else {
            Row(Modifier.fillMaxWidth().padding(AingDimens.cardPadding), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                portrait()
                texts(Modifier.weight(1f))
                delta()
            }
        }
    }
}
