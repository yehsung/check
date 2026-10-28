// 원본: Sources/CheckMobileKit/Games/GamesGomokuWatch.swift @ 3bd04bd
//
// 관전 화면(0.3.41) — 남의 진행 중인 판을 **읽기 전용**으로 본다. `phase == lobby && spectating != null` 이면 로비 **대신** 선다(새 목적지가 아니다 —
// 자식 목적지를 밀면 화면 수명 훅이 `windowDidHide()` 를 불러 스토어 관전 폴링이 죽는다).
//
// 위에서부터: 받은 신청 · 보낸 신청(각각 있을 때만 — 관전이 로비를 통째로 덮으므로 여기 없으면 60초를 거둘 길이 없다) · 안내 · 흑 카드 · 판 · 백 카드 ·
// 상태 상자 · 판돈(+관전자 수)·수·경과 · 캡션, 아래 막대에 [나가기]. **입력이 하나도 없다**(판은 순수 그림 — 탭·미리보기·금수 표시 없음).
// 차례 링은 `watch.deadline` 을 **직접** 센다(스토어 `remainingSeconds` 는 내 판만 안다 — 쓰면 0초로 빨갛게 선다). 0초는 대기색(빨강 = "졌다"로 읽힌다).
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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuEndReason
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.games.GomokuPhoneText
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneWatchStatus
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneWatchText
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneWinLine
import com.yehsung.aingcheck.core.stores.gomoku.GomokuSpectateState
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuUser
import com.yehsung.aingcheck.core.stores.gomoku.leaveWatch
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 관전 첫 화면 세로 예산(Swift `GomokuPhoneWatchBudget` — 기본 글자 dp). 판을 이보다 작게는 줄이지 않는다(관전 판엔 탭이 없어 대국 바닥 240 보다 낮다). */
internal object GomokuWatchBudget {
    val leaveBar: Dp = AingDimens.hairline + AingDimens.minimumTarget + 20.dp
    val playerCard: Dp = 44.dp + 16.dp
    val statusBox: Dp = 20.dp * 2 + 20.dp
    val notice: Dp = 18.dp + 20.dp
    val sectionHeader: Dp = 22.dp + 24.dp + 8.dp
    val inviteCard: Dp = 14.dp + 44.dp + 10.dp + AingDimens.minimumTarget + AingDimens.cardPadding
    val outgoingRow: Dp = AingDimens.minimumTarget + 20.dp
    val boardFloor: Dp = 210.dp
}

@Composable
internal fun GomokuWatchView(games: GamesStore, gomoku: GomokuStore, watch: GomokuSpectateState, state: GomokuScreenState) {
    val colors = AingTheme.colors
    Column(Modifier.fillMaxSize().testTag(GomokuScreenTags.watch)) {
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val side = watchBoardSide(gomoku, maxWidth, maxHeight)
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState())
                    .padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space2, bottom = AingDimens.space3),
                verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
            ) {
                GomokuIncomingSection(gomoku)
                GomokuOutgoingSection(gomoku)
                gomoku.notice?.let { BoardNotice(it) }
                if (watch.hasServerState || watch.faces.isNotEmpty()) {
                    WatchPlayerRow(gomoku, watch, GomokuColor.black, 0)
                    WatchBoard(watch, side)
                    WatchPlayerRow(gomoku, watch, GomokuColor.white, 1)
                } else {
                    // 씨앗도 응답도 없다 — 빈 카드 두 장 대신 한 줄. **끝난 판에는 로딩을 말하지 않는다**(폴링이 멈춰 더 올 것이 없다).
                    BoardGroup { BoardRow { Text(if (watch.isFinished) GomokuPhoneWatchText.watchPlayersUnknown else GomokuPhoneWatchText.watchLoading, style = BoardText.subheadline(), color = colors.label2) } }
                    WatchBoard(watch, side)
                }
                WatchStatusBox(gomoku, watch)
                BoardGroup {
                    BoardRow {
                        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            // 판돈 **액수만** — 관전자는 이 판에서 한 푼도 얻지 못한다(접미사 없음). 관전자 수(0.3.65)는 판돈 칩 근처.
                            val stake = watch.stake
                            if (stake != null) BoardStakeLine(stake) else Text(GomokuPhoneWatchText.watchStakeUnknown, style = BoardText.rowSubtitle(), color = colors.label2)
                            WatcherBadge(gomoku.spectatorCount)
                        }
                        WatchMoveLine(gomoku, watch)
                    }
                }
                Column(Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin, vertical = AingDimens.space1).semantics(mergeDescendants = true) {}) {
                    Text(GomokuPhoneWatchText.watchNoChat, style = BoardText.rowSubtitle(), color = colors.label2)
                    if (watch.autoPoints.isNotEmpty()) Text(GomokuScreenText.autoPlacedCount(watch.autoPoints.size), style = BoardText.rowSubtitle(), color = colors.label2)
                }
            }
        }
        // [나가기]는 늘 보이는 아래 막대 — `leaveWatch()` 는 관전을 내리고 로비·받은함·순위를 다시 읽는다(`stopWatching()` 이면 낡은 목록으로 돌아온다).
        Column(Modifier.fillMaxWidth().background(colors.surface)) {
            Box(Modifier.fillMaxWidth().height(AingDimens.hairline).background(colors.separator))
            BoardButton(
                GomokuPhoneWatchText.leaveWatch, Modifier.padding(horizontal = AingDimens.sideMargin, vertical = 10.dp),
                kind = BoardButtonKind.Tinted, fillsWidth = true, icon = AppIcon.Undo, testTag = GomokuScreenTags.leaveWatch,
            ) { gomoku.leaveWatch() }
        }
    }
}

/** 판 한 변 — **가용 높이 예산**(두 상한 중 작은 쪽, 바닥 210). 관전에서 가장 중요한 상태(누구 차례 · 남은 초)가 판보다 먼저다. */
private fun watchBoardSide(gomoku: GomokuStore, width: Dp, height: Dp): Dp {
    val full = maxOf(GomokuWatchBudget.boardFloor, width - 24.dp)
    if (height <= 0.dp) return full
    var blocks = listOf(GomokuWatchBudget.playerCard, GomokuWatchBudget.playerCard, GomokuWatchBudget.statusBox)
    val pending = gomoku.pendingIncomingInvites
    if (pending.isNotEmpty()) blocks = blocks + GomokuWatchBudget.sectionHeader + GomokuWatchBudget.inviteCard * pending.size
    if (gomoku.outgoing != null) blocks = blocks + GomokuWatchBudget.sectionHeader + GomokuWatchBudget.outgoingRow
    if (gomoku.notice != null) blocks = blocks + GomokuWatchBudget.notice
    var sum = AingDimens.space2
    for (b in blocks) sum += b
    sum += AingDimens.space2 * blocks.size
    val side = minOf(full, height - GomokuWatchBudget.leaveBar - sum)
    return maxOf(GomokuWatchBudget.boardFloor, side)
}

@Composable
private fun WatchBoard(watch: GomokuSpectateState, side: Dp) {
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        GomokuBoardCanvas(
            GomokuBoardPicture(
                board = watch.board, lastMove = watch.lastMove, autoPoints = watch.autoPoints,
                winLine = if (watch.isFinished && watch.endReason == GomokuEndReason.five) GomokuPhoneWinLine.ends(watch.board, watch.lastMove) else null,
            ),
            side = side,
            modifier = Modifier.testTag(GomokuScreenTags.board).clearAndSetSemantics { contentDescription = GomokuPhoneWatchText.watchBoardAccessibility(watch) },
        )
    }
}

/**
 * 관전 플레이어 한 장. **흑·백을 추측하지 않는다**: `faces` 의 a/b 는 uuid 순서라 색이 아니므로 서버가 black/white 를 말하기 전에는 그 자리 얼굴만 그리고
 * 돌 배지도 차례 표시도 달지 않는다. 표정은 늘 기본(관전 응답에 `is_working` 이 없다 — 근무 표정은 단정이다).
 */
@Composable
private fun WatchPlayerRow(gomoku: GomokuStore, watch: GomokuSpectateState, color: GomokuColor, index: Int) {
    val colors = AingTheme.colors
    val known = watch.hasServerState
    val user: GomokuUser? = if (known) (if (color == GomokuColor.black) watch.black else watch.white) else watch.faces.getOrNull(index)
    val subtitle: String? = if (known) user?.let { GomokuPhoneWatchText.watchPlayerSubtitle(color) } else if (index == 0 && !watch.isFinished) GomokuPhoneWatchText.watchLoading else null
    val isTurn = known && !watch.isFinished && watch.turn == color
    val shape = RoundedCornerShape(AingDimens.groupRadius)
    val name = user?.displayName.orEmpty().ifEmpty { "—" }
    Row(
        Modifier.fillMaxWidth().background(colors.surface, shape).border(2.dp, if (isTurn) colors.workingDot else Color.Transparent, shape)
            .padding(horizontal = 14.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(AingDimens.space3),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BoardPortrait(user?.characterID, CharacterMood.Plain, 44.dp, stoneIsBlack = if (known) color == GomokuColor.black else null)
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
            BoardPersonName(name, center = user?.center)
            if (subtitle != null) Text(subtitle, style = BoardText.rowSubtitle(), color = colors.label2)
        }
        val deadline = watch.deadline
        if (isTurn && deadline != null) WatchClock(gomoku, deadline)
    }
}

/** 관전 차례 링 — **잎**. 마감을 직접 받아 스토어 시계로 센다. 1초 눈금(남의 시계라 0.2초로 돌릴 까닭이 없다). 0초는 대기색. */
@Composable
private fun WatchClock(gomoku: GomokuStore, deadline: SwiftDate) {
    val colors = AingTheme.colors
    val tick = rememberTicker()
    val remaining = tick.let { maxOf(0.0, deadline.timeIntervalSince(gomoku.clock())) }
    val total = maxOf(1L, gomoku.turnSeconds).toDouble()
    val fraction = (remaining / total).coerceIn(0.0, 1.0).toFloat()
    val ring = when {
        remaining <= 0 -> colors.pendingDot
        remaining <= 5 -> colors.danger
        remaining <= 10 -> colors.pendingDot
        else -> colors.workingDot
    }
    val ink = when {
        remaining <= 0 -> colors.pending
        remaining <= 5 -> colors.danger
        remaining <= 10 -> colors.pending
        else -> colors.working
    }
    val fill = colors.fill
    Box(Modifier.size(44.dp).padding(2.dp).clearAndSetSemantics { contentDescription = GomokuPhoneText.clockAccessibility(remaining) }, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = 4.dp.toPx()
            val inset = stroke / 2
            drawArc(fill, 0f, 360f, false, topLeft = Offset(inset, inset), size = Size(size.width - stroke, size.height - stroke), style = Stroke(stroke))
            drawArc(ring, -90f, 360f * fraction, false, topLeft = Offset(inset, inset), size = Size(size.width - stroke, size.height - stroke), style = Stroke(stroke, cap = StrokeCap.Round))
        }
        Text(GomokuPhoneText.remaining(remaining), style = BoardText.digits(BoardText.rowSubtitle()).copy(fontSize = 13.sp, fontWeight = FontWeight.Bold), color = ink, maxLines = 1)
    }
}

/** 상태 상자 — **잎**. 문구·색은 `GomokuPhoneWatchStatus` 가 시각으로 고른다. 진행 중은 초록 · 마감 지남은 앰버(빨강 금지) · 끝은 청회색 · 모름은 회색. */
@Composable
private fun WatchStatusBox(gomoku: GomokuStore, watch: GomokuSpectateState) {
    val colors = AingTheme.colors
    val tick = rememberTicker(running = !watch.isFinished && watch.deadline != null)
    val now = tick.let { gomoku.clock() }
    val kind = GomokuPhoneWatchStatus.kind(watch, now)
    val (tint, icon) = when (kind) {
        GomokuPhoneWatchStatus.Kind.loading -> colors.label2 to AppIcon.HourglassEmpty
        is GomokuPhoneWatchStatus.Kind.turn -> colors.working to AppIcon.Visibility
        GomokuPhoneWatchStatus.Kind.overdue -> colors.pending to AppIcon.RunningWithErrors
        GomokuPhoneWatchStatus.Kind.ended -> colors.offWork to AppIcon.SportsScore
    }
    Column(
        Modifier.fillMaxWidth().background(tint.copy(alpha = 0.12f), RoundedCornerShape(AingDimens.innerRadius)).padding(horizontal = 12.dp, vertical = 10.dp)
            .semantics(mergeDescendants = true) {}.testTag("gomoku-watch-status"),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            AingIcon(icon, contentDescription = null, size = 18.dp, tint = tint)
            Text(GomokuPhoneWatchStatus.text(watch, now), style = BoardText.subheadline().copy(fontWeight = FontWeight.SemiBold), color = colors.label)
        }
        GomokuPhoneWatchStatus.streakWarning(watch, gomoku.autoAbandonStreak)?.let {
            Text(it, style = BoardText.rowSubtitle().copy(fontWeight = FontWeight.SemiBold), color = colors.danger)
        }
    }
}

/** "12수 · 1분 35초째" — **잎**. 끝난 판은 경과를 세지 않는다. */
@Composable
private fun WatchMoveLine(gomoku: GomokuStore, watch: GomokuSpectateState) {
    val colors = AingTheme.colors
    val startedAt = watch.startedAt
    val running = startedAt != null && !watch.isFinished
    val tick = rememberTicker(running = running)
    val text = tick.let {
        if (running && startedAt != null) GomokuPhoneWatchText.watchMoves(watch.moveCount) + " · " + GomokuPhoneText.elapsedPhrase(gomoku.clock().timeIntervalSince(startedAt))
        else GomokuPhoneWatchText.watchMoves(watch.moveCount)
    }
    Text(text, style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label2)
}
