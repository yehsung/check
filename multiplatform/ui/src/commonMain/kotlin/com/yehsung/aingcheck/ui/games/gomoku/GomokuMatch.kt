// 원본: Sources/CheckMobileKit/Games/GamesGomokuMatch.swift · Sources/CheckMobileKit/Games/GamesGomokuAIViews.swift(AIPortrait · AIThinkingMark) @ 3bd04bd
//
// 대국 화면(시안 B 09): 상대 카드 · 판(화면 폭 − 24 · 큰 글자면 높이 예산) · 내 카드 · 판 아래 작은 줄 · 아래 반쯤 올라온 대화 서랍.
// 두 카드는 대칭이다 — 캐릭터 초상 + 돌 배지, 차례인 쪽만 초록 테두리 + 초 링(30초 — 서버 마감으로 코어가 계산한 남은 초).
// AI 판(1.0.1)도 이 화면이다 — 판 종류별 차이는 `GomokuPhoneMatchChrome` 표 하나가 정한다(판돈 부제 대신 "AI 대국 · 기록 없음" · 서랍 없음 ·
// AI 차례의 링 자리에 "생각 중" · 시계 안내 "떠나면 멈춰요").
//
// 결과(비평 26): 내 초상 · 결과 제목 · 끝난 이유 · 상대 · 오른쪽 루비 변화(이기면 초록 [보석]+N) · [같은 판돈으로 다시 신청] [로비로] · 승리선이 그어진 판.
// §8-17 #1: 깃발이 꺼진 빌드는 1:1 [다시 신청]을 숨긴다(재대결은 신청이다 — 스토어 `rematch` 도 짝으로 막는다). AI 판의 [같은 색으로 다시 두기]는 그대로다.
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuEndReason
import com.yehsung.aingcheck.core.rules.renju.GomokuOutcome
import com.yehsung.aingcheck.core.rules.renju.GomokuTurnWarning
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.games.GomokuPhoneText
import com.yehsung.aingcheck.core.stores.gomoku.GomokuMatchState
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneMatchChrome
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneWinLine
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuUser
import com.yehsung.aingcheck.core.stores.gomoku.restartAIMatch
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/** 사람 행 표정(Swift `GomokuUser.mood` — 근무 중이면 웃는 얼굴 + 초록 링). */
internal val GomokuUser.mood: CharacterMood get() = if (isWorking) CharacterMood.Working else CharacterMood.Off

/** 판 한 변(Swift `boardSide(in:)`): 기본은 화면 폭 − 24(최소 240). 높이가 좁으면(큰 글자 · 가로) 보이는 높이의 52% 로 줄인다 — 내 차례·남은 초가 판보다 먼저다. */
internal fun gomokuBoardSide(width: Dp, height: Dp, compactHeight: Boolean): Dp {
    val full = maxOf(240.dp, width - 24.dp)
    if (!compactHeight || height <= 0.dp) return full
    return maxOf(240.dp, minOf(full, height * 0.52f))
}

@Composable
internal fun GomokuMatchView(games: GamesStore, gomoku: GomokuStore, match: GomokuMatchState, me: BoardGameMe, state: GomokuScreenState, safety: BoardGameSafety?) {
    val chrome = GomokuPhoneMatchChrome(match)
    val forbidden = if (GomokuForbiddenMemo.shows(match)) state.forbiddenMemo.points(match.board) else emptyMap()
    val colors = AingTheme.colors
    Column(Modifier.fillMaxSize().testTag(GomokuScreenTags.match)) {
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val side = gomokuBoardSide(maxWidth, maxHeight, compactHeight = maxHeight < maxWidth * 1.45f)
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                    .padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space1, bottom = AingDimens.space3),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                GomokuPlayerCard(
                    gomoku = gomoku,
                    characterID = match.opponent.characterID, mood = match.opponent.mood,
                    name = match.opponent.displayName, center = match.opponent.center, isMe = false,
                    color = match.myColor.opponent,
                    subtitle = GomokuScreenText.opponentSubtitle(chrome, match.myColor.opponent, match.opponent.isWorking) to colors.label2,
                    isTurn = match.turn == match.myColor.opponent, isAI = chrome.isAI,
                )
                // 판 한 장(가운데 정렬). 내 차례 마지막 3초 — 판 안쪽 가장자리가 빨갛게 빛난다(0.3.51 · 맥과 같은 문턱·그림).
                val watches = gomoku.watchesMyClock()
                val tick = rememberTicker(running = gomoku.isWindowVisible && watches, periodMillis = 200)
                val remaining = tick.let { if (watches) gomoku.remainingSeconds(gomoku.clock()) else null }
                val intensity = if (GomokuTurnWarning.isActive(remaining)) GomokuTurnWarning.intensity(remaining) else 0.0
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    GomokuPlayBoard(
                        gomoku = gomoku, match = match, side = side, forbidden = forbidden, preview = state.preview,
                        onPreviewChanged = { state.previewVersion += 1 },
                        onFocusedForbidden = { state.focusedForbidden = it },
                        warningIntensity = intensity,
                        modifier = Modifier.shadow(9.dp, RoundedCornerShape(side * 0.025f), ambientColor = if (colors.isDark) GomokuBoardInk.shadowDark else GomokuBoardInk.shadowLight,
                            spotColor = if (colors.isDark) GomokuBoardInk.shadowDark else GomokuBoardInk.shadowLight),
                    )
                }
                @Suppress("UNUSED_VARIABLE") val version = state.previewVersion
                val previewPoint = state.preview.visiblePoint(match, gomoku.isBusy, forbidden)
                GomokuPlayerCard(
                    gomoku = gomoku,
                    characterID = me.characterID, mood = me.mood,
                    name = me.name ?: GomokuPhoneText.me, center = null, isMe = me.name != null,
                    color = match.myColor,
                    subtitle = myLine(gomoku, match, chrome, state, previewPoint),
                    isTurn = match.turn == match.myColor,
                )
                GomokuFootLines(gomoku, match, chrome)
            }
        }
        // AI 판에는 서랍이 없다 — 말을 나눌 상대도, 신고·차단할 사람도 없다.
        if (chrome.showsChatDrawer) GomokuChatDrawer(gomoku, match.opponent, safety, state)
    }
}

/** 내 카드 부제 — 우선순위: 금수 자리를 눌렀다(빨강) > 안내 한 줄(앰버) > 내 차례(초록 · 미리보기 칸) > 상대 차례(회색). */
@Composable
private fun myLine(gomoku: GomokuStore, match: GomokuMatchState, chrome: GomokuPhoneMatchChrome, state: GomokuScreenState, previewPoint: com.yehsung.aingcheck.core.rules.renju.GomokuPoint?): Pair<String, Color> {
    val colors = AingTheme.colors
    state.focusedForbidden?.let { return GomokuPhoneText.forbiddenStatus(it) to colors.danger }
    gomoku.notice?.let { return it to colors.pending }
    if (match.turn == match.myColor) return (GomokuPhoneText.myTurn + " · " + GomokuPhoneText.myTurnHint(previewPoint)) to colors.working
    return GomokuScreenText.waitingLine(chrome, match.myColor) to colors.label2
}

/** 판 아래 작은 줄: 흑 패스 · 자동 착수 · 연속 경고 · 시계 안내(사람 판은 "앱을 나가도 흘러요", AI 판은 "떠나면 멈춰요"). */
@Composable
private fun GomokuFootLines(gomoku: GomokuStore, match: GomokuMatchState, chrome: GomokuPhoneMatchChrome) {
    val colors = AingTheme.colors
    Column(Modifier.fillMaxWidth().padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (match.blackPassed) Text(GomokuPhoneText.blackPassed, style = BoardText.rowSubtitle(), color = colors.label2)
        if (match.autoPoints.isNotEmpty()) Text(GomokuScreenText.autoPlacedCount(match.autoPoints.size), style = BoardText.rowSubtitle(), color = colors.label2)
        gomoku.autoStreakWarning?.let { Text(it, style = BoardText.rowSubtitle().copy(fontWeight = FontWeight.SemiBold), color = colors.danger) }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Top) {
            AingIcon(AppIcon.Schedule, contentDescription = null, size = 15.dp, tint = colors.label2)
            Text(GomokuScreenText.clockLine(chrome), style = BoardText.rowSubtitle(), color = colors.label2)
        }
    }
}

/**
 * 플레이어 한 장(시안 `.b-player`): 캐릭터 초상 44 + 돌 배지 · 이름(+ 센터 · '나') · 부제 · 오른쪽은 차례면 초 링, 아니면 상대의 방금 한 말(8초).
 * 차례인 카드만 초록 2dp 테두리.
 */
@Composable
internal fun GomokuPlayerCard(
    gomoku: GomokuStore,
    characterID: String?,
    mood: CharacterMood,
    name: String,
    center: String?,
    isMe: Boolean,
    color: GomokuColor,
    subtitle: Pair<String, Color>,
    isTurn: Boolean,
    isAI: Boolean = false,
) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(AingDimens.groupRadius)
    Row(
        Modifier.fillMaxWidth().background(colors.surface, shape)
            .border(2.dp, if (isTurn) colors.workingDot else Color.Transparent, shape)
            .padding(horizontal = 14.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(AingDimens.space3),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (isAI) GomokuAIPortrait(44.dp, stoneIsBlack = color == GomokuColor.black)
        else BoardPortrait(characterID, mood, 44.dp, stoneIsBlack = color == GomokuColor.black)
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
            BoardPersonName(name, center = center, isMe = isMe)
            Text(
                subtitle.first,
                style = BoardText.rowSubtitle().copy(fontWeight = if (subtitle.second == colors.label2) FontWeight.Normal else FontWeight.SemiBold),
                color = subtitle.second,
            )
        }
        if (isTurn) {
            if (isAI) GomokuAIThinkingMark() else GomokuTurnRing(gomoku)
        } else if (!isMe && !isAI) {
            GomokuSayBubble(gomoku)
        }
    }
}

/**
 * 차례인 사람의 초 링(44dp) — **잎**. 남은 시간은 코어가 서버 마감으로 계산한다(`remainingSeconds(now)` — 시계는 스토어 시계).
 * 색: 넉넉하면 초록 · 10초 이하 앰버 · 5초 이하 빨강. 한 수 30초는 스토어 `turnSeconds`(서버 로비 값 — 상수를 베끼지 않는다).
 */
@Composable
internal fun GomokuTurnRing(gomoku: GomokuStore) {
    val colors = AingTheme.colors
    val tick = rememberTicker(running = gomoku.isWindowVisible, periodMillis = 200)
    val remaining = tick.let { gomoku.remainingSeconds(gomoku.clock()) ?: 0.0 }
    val total = maxOf(1L, gomoku.turnSeconds).toDouble()
    val fraction = (remaining / total).coerceIn(0.0, 1.0).toFloat()
    val ring = when {
        remaining <= 5 -> colors.danger
        remaining <= 10 -> colors.pendingDot
        else -> colors.workingDot
    }
    val ink = when {
        remaining <= 5 -> colors.danger
        remaining <= 10 -> colors.pending
        else -> colors.working
    }
    Box(
        Modifier.size(44.dp).padding(2.dp).clearAndSetSemantics { contentDescription = GomokuPhoneText.clockAccessibility(remaining) }.testTag("gomoku-turn-ring"),
        contentAlignment = Alignment.Center,
    ) {
        val fill = colors.fill
        Canvas(Modifier.fillMaxSize()) {
            val stroke = 4.dp.toPx()
            val inset = stroke / 2
            drawArc(fill, 0f, 360f, false, topLeft = Offset(inset, inset), size = Size(size.width - stroke, size.height - stroke), style = Stroke(stroke))
            drawArc(ring, -90f, 360f * fraction, false, topLeft = Offset(inset, inset), size = Size(size.width - stroke, size.height - stroke),
                style = Stroke(stroke, cap = StrokeCap.Round))
        }
        Text(GomokuPhoneText.remaining(remaining), style = BoardText.digits(BoardText.rowSubtitle()).copy(fontSize = 13.sp, fontWeight = FontWeight.Bold), color = ink, maxLines = 1)
    }
}

/** 상대가 방금 한 말(시안 `.b-saybub`) — 8초가 지나면 사라진다. 음소거 중이면 그리지 않는다. */
@Composable
private fun GomokuSayBubble(gomoku: GomokuStore) {
    if (gomoku.isMuted) return
    val last = gomoku.chat.lastOrNull { !it.isMine } ?: return
    val tick = rememberTicker()
    val fresh = tick.let { gomoku.clock().timeIntervalSince(last.sentAt) < 8.0 }
    if (!fresh) return
    val colors = AingTheme.colors
    Text(
        last.body,
        style = BoardText.rowSubtitle(),
        color = colors.label,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier.background(colors.bubbleIn, RoundedCornerShape(14.dp)).padding(horizontal = 10.dp, vertical = 5.dp)
            .semantics { contentDescription = "상대: " + last.body },
    )
}

/** AI 차례의 "생각 중" 표시(초 링 자리 — AI 차례에는 마감이 없어 링이 0초로 빨갛게 선다). 움직이지 않는다(스냅숏 결정성). */
@Composable
internal fun GomokuAIThinkingMark() {
    val colors = AingTheme.colors
    Box(
        Modifier.size(44.dp).padding(2.dp).border(4.dp, colors.accent.copy(alpha = 0.35f), CircleShape)
            .clearAndSetSemantics { contentDescription = GomokuPhoneText.aiThinking },
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            AingIcon(AppIcon.MoreHoriz, contentDescription = null, size = 14.dp, tint = colors.accent)
            Text(GomokuPhoneText.aiThinkingShort, color = colors.accent, fontSize = 9.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        }
    }
}

// MARK: - 결과

/** 결과 루비 변화(Swift `delta` — 서버 값이 있으면 그것, 없으면 승패에서: 이기면 `DuelFee.winnerNet`(수수료 0 → +판돈), 지면 −판돈, 비기면 0). */
internal fun gomokuResultDelta(match: GomokuMatchState): Long {
    match.rubyDelta?.let { return it }
    return when (match.outcome) {
        GomokuOutcome.won -> DuelFee.winnerNet(match.stake.toInt()).toLong()
        GomokuOutcome.lost -> -match.stake
        else -> 0L
    }
}

@Composable
internal fun GomokuResultView(games: GamesStore, gomoku: GomokuStore, match: GomokuMatchState, me: BoardGameMe, state: GomokuScreenState, safety: BoardGameSafety?) {
    val chrome = GomokuPhoneMatchChrome(match)
    val colors = AingTheme.colors
    val delta = gomokuResultDelta(match)
    Column(Modifier.fillMaxSize().testTag(GomokuScreenTags.result)) {
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val side = maxOf(240.dp, maxWidth - 24.dp)
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                    .padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space2, bottom = AingDimens.space4),
                verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
            ) {
                BoardGroup(Modifier.semantics(mergeDescendants = true) {}) {
                    Row(Modifier.fillMaxWidth().padding(AingDimens.cardPadding), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        BoardPortrait(me.characterID, me.mood, 60.dp, stoneIsBlack = match.myColor == GomokuColor.black)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(GomokuPhoneText.outcomeTitle(match.outcome), style = BoardText.title2(), color = colors.label)
                            Text(GomokuScreenText.endReason(chrome, match.endReason, match.outcome), style = BoardText.subheadline(), color = colors.label2)
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                if (chrome.isAI) GomokuAIPortrait(20.dp) else BoardAvatar(match.opponent.displayName, match.opponent.id, 20.dp)
                                Text(GomokuScreenText.opponentLine(chrome, match.opponent.displayName), style = BoardText.caption(), color = colors.label2)
                            }
                        }
                        if (chrome.showsStake) BoardRubyDelta(delta, GomokuPhoneText.rubyDelta(delta.toInt()))
                    }
                }
                gomoku.notice?.let { BoardNotice(it) }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    BoardButton(GomokuPhoneText.backToLobby, Modifier.weight(1f), kind = BoardButtonKind.Gray, fillsWidth = true, testTag = GomokuScreenTags.backToLobby) {
                        gomoku.backToLobby()
                    }
                    // AI 판의 "다시"는 신청이 아니라 같은 색의 새 로컬 판이다. 1:1 [다시 신청]은 §8-17 #1 깃발이 꺼지면 숨긴다.
                    if (chrome.isAI || !gomoku.duelsLocked) {
                        BoardButton(
                            GomokuScreenText.rematchTitle(chrome), Modifier.weight(1f), kind = BoardButtonKind.Filled, fillsWidth = true, icon = AppIcon.Refresh,
                            enabled = !gomoku.isBusy && gomoku.outgoing == null, testTag = GomokuScreenTags.rematch,
                        ) {
                            if (chrome.isAI) gomoku.restartAIMatch() else gomoku.scope.launch { gomoku.rematch() }
                        }
                    }
                }
                if (chrome.isAI) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        AingIcon(AppIcon.Memory, contentDescription = null, size = 15.dp, tint = colors.accent)
                        Text(GomokuPhoneText.aiNoRecord, style = BoardText.rowSubtitle(), color = colors.label2)
                    }
                }
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    GomokuBoardCanvas(
                        GomokuBoardPicture(
                            board = match.board, lastMove = match.lastMove, autoPoints = match.autoPoints,
                            winLine = if (match.endReason == GomokuEndReason.five) GomokuPhoneWinLine.ends(match.board, match.lastMove) else null,
                        ),
                        side = side,
                        modifier = Modifier.testTag(GomokuScreenTags.board).semantics { contentDescription = GomokuScreenText.boardAccessibility(match, 0) },
                    )
                }
            }
        }
        if (chrome.showsChatDrawer) GomokuChatDrawer(gomoku, match.opponent, safety, state)
    }
}
