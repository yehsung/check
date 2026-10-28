// 원본: Sources/CheckMobileKit/Games/GamesChessWatch.swift:192-759(관전 절 뷰 — 판정 몫 1-191 은 core/stores GamesChessWatchPlan.kt) @ 3bd04bd
//
// 체스 관전 절. `chess.spectating` 이 모양을 고른다: 없으면 "지금 대결 중" 목록(관전 입구), 있으면 그 자리에서 관전 판으로 바뀐다(새 목적지도 새 화면도
// 아니다 — 로비 스크롤 안의 절이라 제 스크롤도 떠 있는 아래 막대도 두지 않고, [나가기]는 절 머리에 붙는다).
package com.yehsung.aingcheck.ui.games.chess

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.stores.chess.ChessLiveMatch
import com.yehsung.aingcheck.core.stores.chess.ChessNoticeText
import com.yehsung.aingcheck.core.stores.chess.ChessPhoneText
import com.yehsung.aingcheck.core.stores.chess.ChessSpectateState
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.chess.ChessUser
import com.yehsung.aingcheck.core.stores.chess.GamesChessBoardMetrics
import com.yehsung.aingcheck.core.stores.chess.GamesChessWatchBudget
import com.yehsung.aingcheck.core.stores.chess.GamesChessWatchPlan
import com.yehsung.aingcheck.core.stores.chess.GamesChessWatchStatus
import com.yehsung.aingcheck.core.stores.chess.isMine
import com.yehsung.aingcheck.core.stores.chess.leaveWatch
import com.yehsung.aingcheck.core.stores.chess.startWatching
import com.yehsung.aingcheck.core.stores.games.GamesWatcherCount
import com.yehsung.aingcheck.core.stores.gomoku.BoardSize
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.games.gomoku.BoardAvatar
import com.yehsung.aingcheck.ui.games.gomoku.BoardButton
import com.yehsung.aingcheck.ui.games.gomoku.BoardButtonKind
import com.yehsung.aingcheck.ui.games.gomoku.BoardCaption
import com.yehsung.aingcheck.ui.games.gomoku.BoardGroup
import com.yehsung.aingcheck.ui.games.gomoku.BoardLoading
import com.yehsung.aingcheck.ui.games.gomoku.BoardPersonName
import com.yehsung.aingcheck.ui.games.gomoku.BoardPortrait
import com.yehsung.aingcheck.ui.games.gomoku.BoardRow
import com.yehsung.aingcheck.ui.games.gomoku.BoardSectionHeader
import com.yehsung.aingcheck.ui.games.gomoku.BoardStakeLine
import com.yehsung.aingcheck.ui.games.gomoku.BoardText
import com.yehsung.aingcheck.ui.games.gomoku.WatcherBadge
import com.yehsung.aingcheck.ui.games.gomoku.rememberTicker
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

@Composable
internal fun ChessWatchSection(chess: ChessStore, state: ChessScreenState, viewportHeight: Dp, columnWidth: Dp) {
    val watch = chess.spectating
    if (watch != null) ChessWatchPanel(chess, watch, state, viewportHeight, columnWidth) else ChessLiveSection(chess)
}

/** "지금 대결 중" 절 — 남의 판 목록과 [관전] 입구. 목록은 **서버 순서 그대로**(accepted_at desc). */
@Composable
private fun ChessLiveSection(chess: ChessStore) {
    val colors = AingTheme.colors
    val lives = chess.liveMatches
    BoardSectionHeader(ChessPhoneText.liveTitle, trailing = if (lives.isEmpty()) null else ChessPhoneText.liveCount(lives.size))
    BoardGroup {
        if (lives.isEmpty()) {
            BoardRow { Text(ChessPhoneText.noLiveMatches, style = BoardText.subheadline(), color = colors.label2) }
        } else {
            lives.forEachIndexed { index, live -> ChessLiveRow(chess, live, isLast = index == lives.size - 1) }
        }
    }
}

/** "지금 대결 중" 한 줄: 두 얼굴 vs · 이름 둘 · 판돈 · 경과 · 오른쪽 슬롯(관전자 수 + 관전 입구 — 좁은 폭에서는 글 아래 줄). */
@Composable
private fun ChessLiveRow(chess: ChessStore, live: ChessLiveMatch, isLast: Boolean) {
    val colors = AingTheme.colors
    val entry = GamesChessWatchPlan.entry(chess, chess.isMine(live))
    // INV-GamesChessWatch-17c3ac97 이식: 0.3.65 로 그 슬롯에 **관전자 수**가 같이 선다 — 이 술어가 둘을 **합쳐서** 답한다(수만 있고 입구가 없는 행도 슬롯이 서고,
    //   둘 다 없으면 슬롯을 두지 않는다 — 한 술어를 두 곳에 적지 않는다).
    val hasEntry = entry != GamesChessWatchPlan.Entry.absent || GamesWatcherCount.shows(live.watchers.toInt())
    rememberTicker()
    BoardRow(divider = !isLast) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                BoardAvatar(live.a.displayName, live.a.id, 30.dp)
                Text("vs", style = BoardText.rowSubtitle(), color = colors.label2)
                BoardAvatar(live.b.displayName, live.b.id, 30.dp)
            }
            Column(Modifier.semantics(mergeDescendants = true) {}) {
                Text(ChessPhoneText.livePair(live), style = BoardText.rowTitle(), color = colors.label)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    // INV-GamesChessWatch-e96411f9 이식: 남의 판이라 접미사를 붙이지 않는다(판돈 액수만).
                    BoardStakeLine(live.stake.rawValue)
                    Text(" · " + ChessPhoneText.elapsedPhrase(chess.clock().timeIntervalSince(live.startedAt)), style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label2)
                }
            }
            if (hasEntry) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    WatcherBadge(live.watchers)
                    when (entry) {
                        GamesChessWatchPlan.Entry.absent -> Unit
                        GamesChessWatchPlan.Entry.myMatch -> Text(ChessPhoneText.myMatch, style = BoardText.rowSubtitle(), color = colors.label2)
                        GamesChessWatchPlan.Entry.soon -> Text(ChessPhoneText.watchSoonCaption, style = BoardText.rowSubtitle(), color = colors.label2,
                            modifier = Modifier.semantics { contentDescription = ChessNoticeText.unavailable })
                        GamesChessWatchPlan.Entry.chip -> BoardButton(ChessPhoneText.watch, kind = BoardButtonKind.Tinted, small = true, testTag = ChessScreenTags.watch(live.id)) {
                            chess.startWatching(live.id)
                        }
                    }
                }
            }
        }
    }
}

/**
 * 관전 판 — "지금 대결 중" 절이 **그 자리에서** 이 모양으로 바뀐다. 위에서부터: 절 머리(+오른쪽 [나가기]) · 흑 카드 · 판 · 백 카드 · 상태 상자 · 판돈·N수·경과 · 캡션.
 * **입력이 하나도 없다** — 판은 순수 그림이고 탭 처리기는 `GamesChessWatchPlan.boardTapHandler`(늘 null).
 */
@Composable
private fun ChessWatchPanel(chess: ChessStore, watch: ChessSpectateState, state: ChessScreenState, viewportHeight: Dp, columnWidth: Dp) {
    val colors = AingTheme.colors
    Column(Modifier.fillMaxWidth().testTag("chess-watch"), verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        // [나가기]는 **머리**에 — 문은 하나다(`leaveWatch()` 는 관전을 내리고 로비·순위를 다시 읽는다).
        BoardSectionHeader(ChessPhoneText.watchTitle, action = ChessPhoneText.leaveWatch to { chess.leaveWatch() })
        if (watch.hasServerState || watch.faces.isNotEmpty()) {
            WatchPlayerRow(chess, watch, ChessColor.black, 0)
            WatchBoard(chess, watch, state, viewportHeight, columnWidth)
            WatchPlayerRow(chess, watch, ChessColor.white, 1)
        } else {
            BoardGroup {
                BoardRow {
                    // 끝난 판에는 로딩을 말하지 않는다(폴링이 멈춰 더 올 것이 없다).
                    if (watch.isFinished) Text(ChessPhoneText.playersUnknown, style = BoardText.subheadline(), color = colors.label2) else BoardLoading(ChessPhoneText.watchLoading)
                }
            }
            WatchBoard(chess, watch, state, viewportHeight, columnWidth)
        }
        WatchStatusBox(watch)
        BoardGroup {
            BoardRow {
                Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    // INV-GamesChessWatch-fa11bebe 이식: 판돈 **액수만** — 접미사를 붙이지 않는다(관전자는 이 판에서 한 푼도 얻지 못한다). 관전자 수는 판돈 칩 근처.
                    val stake = watch.stake
                    if (stake != null) BoardStakeLine(stake) else Text(ChessPhoneText.stakeUnknown, style = BoardText.rowSubtitle(), color = colors.label2)
                    WatcherBadge(chess.spectatorCount)
                }
                WatchMoveLine(chess, watch)
            }
        }
        Column(Modifier.semantics(mergeDescendants = true) {}) {
            BoardCaption(ChessPhoneText.watchCaption)
            if (watch.isFinished) BoardCaption(ChessPhoneText.watchTailCaption)
        }
    }
}

/**
 * 판 한 장(가운데 정렬).
 * INV-GamesChessWatch-1e2d0c8e 이식: **입력이 0건이다** — 값은 전부 `GamesChessWatchPlan` 에서 온다(탭 처리기 null · 선택 없음 · 도착 점 없음 · 백 아래).
 * INV-GamesChessWatch-099fda7d 이식: `isWindowVisible` 이 꺼진 배선에서는 애니메이션을 안 만든다 — 그 깃발은 게임 탭 스토어의 화면 수명 훅이 켠다(이 절은 깃발을
 *   건드리지 않는다). 관전 판 주인은 내 판 주인과 따로다(Swift 세 깔때기 중 관전 `applyWatch`).
 */
@Composable
private fun WatchBoard(chess: ChessStore, watch: ChessSpectateState, state: ChessScreenState, viewportHeight: Dp, columnWidth: Dp) {
    val position = watch.position ?: com.yehsung.aingcheck.core.rules.chess.ChessPosition.empty
    @Suppress("UNUSED_VARIABLE") val version = state.flightVersion
    if (!chess.isWindowVisible || chess.isWindowOccluded) state.watchFlight.clear()
    val flight = state.watchFlight.observe(watch.id, watch.plyCount, watch.position, watch.lastMove, chess.isWindowVisible, chess.isWindowOccluded, chess.clock())
    // 세로 상한(관전에서 가장 중요한 상태가 판보다 먼저 — GamesChessWatchBudget). 폭은 열 폭.
    val cap = GamesChessWatchBudget.boardCap(viewportHeight.value.toDouble())
    val widthSide = GamesChessBoardMetrics.side(BoardSize(columnWidth.value.toDouble(), Double.MAX_VALUE))
    val side = (if (cap != null) minOf(widthSide, maxOf(GamesChessBoardMetrics.minimumSide, cap)) else widthSide).dp
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        ChessBoard(
            position = position, flight = flight, whiteAtBottom = GamesChessWatchPlan.boardWhiteAtBottom,
            selection = GamesChessWatchPlan.boardSelection, legalTargets = GamesChessWatchPlan.boardLegalTargets,
            lastMove = watch.lastMove?.let { it.from to it.to }, checkSquare = GamesChessWatchPlan.boardCheckSquare(watch),
            onTapSquare = GamesChessWatchPlan.boardTapHandler,
            side = side,
            onFlightFinished = { generation -> state.watchFlight.expire(generation); state.flightVersion += 1 },
            accessibility = ChessPhoneText.boardAccessibility(watch),
            testTag = ChessScreenTags.watchBoard,
        )
    }
}

/** 관전 플레이어 한 장 — 초상 · 이름(+센터) · 돌 색 · 그쪽 시계. 색을 모르면(첫 응답 전) 돌 배지도 테두리도 시계도 없다. */
@Composable
private fun WatchPlayerRow(chess: ChessStore, watch: ChessSpectateState, color: ChessColor, index: Int) {
    val colors = AingTheme.colors
    val known = watch.hasServerState
    val user: ChessUser? = if (known) (if (color == ChessColor.black) watch.black else watch.white) else watch.faces.getOrNull(index)
    val subtitle: String? = if (known) user?.let { ChessPhoneText.stoneName(color) } else if (index == 0 && !watch.isFinished) ChessPhoneText.watchLoading else null
    val isTurn = known && !watch.isFinished && watch.turn == color
    val shape = RoundedCornerShape(AingDimens.groupRadius)
    val name = user?.displayName.orEmpty().ifEmpty { ChessPhoneText.unknownName }
    Row(
        Modifier.fillMaxWidth().background(colors.surface, shape).border(2.dp, if (isTurn) colors.workingDot else Color.Transparent, shape).padding(horizontal = 14.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(AingDimens.space3), verticalAlignment = Alignment.CenterVertically,
    ) {
        // 표정은 늘 기본(관전 응답에 is_working 키가 없다 — 근무 표정은 단정이다).
        BoardPortrait(user?.characterID, CharacterMood.Plain, 44.dp, stoneIsBlack = if (known) color == ChessColor.black else null)
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
            BoardPersonName(name, center = user?.center)
            if (subtitle != null) Text(subtitle, style = BoardText.rowSubtitle(), color = colors.label2)
        }
        if (known) WatchClock(chess, color, isTurn)
    }
}

/**
 * 관전 한쪽 시계 — **잎**. 시계가 둘이다(둘이 같은 값이면 한쪽이 안 그려진 것이다).
 * INV-GamesChessWatch-ec3868be 이식: **스토어에서 다시 읽는다**(`chess.spectating?.clock`) — 값으로 받아 두면 폴링이 깨우지 않는 동안 그 값이 굳는다(`chess_watch` 는
 *   상대가 생각하는 동안 응답이 매번 같아 관찰 대상이 안 바뀐다 — 보간은 여기서만 살아난다).
 * INV-GamesChessWatch-db860b39 이식: `now` 는 **스토어 시계**다(`turnStartedAt` 이 그 축으로 보정돼 있다 — 벽시계를 쓰면 시계를 꽂은 배선에서 늘 0.0 으로 떴다).
 */
@Composable
private fun WatchClock(chess: ChessStore, color: ChessColor, isTurn: Boolean) {
    val colors = AingTheme.colors
    val running = chess.spectating?.clock?.running == color
    val tick = rememberTicker(running = running, periodMillis = 200)
    val remaining = tick.let { chess.spectating?.clock?.remainingSeconds(color, chess.clock()) ?: 0.0 }
    val total = maxOf(1.0, chess.initialMs / 1000.0)
    val fraction = (remaining / total).coerceIn(0.0, 1.0).toFloat()
    // 0 은 **대기색**(빨강은 10초 아래 경고 자리 — 0 을 빨갛게 하면 색만으로 "졌다"로 읽힌다).
    val tint = when {
        remaining <= 0 -> colors.pending
        remaining <= 10 -> colors.danger
        remaining <= 30 -> colors.pending
        isTurn -> colors.working
        else -> colors.label2
    }
    Column(Modifier.width(64.dp).clearAndSetSemantics { contentDescription = ChessPhoneText.clockAccessibility(remaining) }, horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(ChessPhoneText.clock(remaining), style = BoardText.digits(BoardText.subheadline()).copy(fontWeight = FontWeight.Bold), color = tint, maxLines = 1)
        Box(Modifier.fillMaxWidth().height(4.dp).background(colors.fill, CircleShape)) {
            Box(Modifier.fillMaxWidth(fraction.coerceAtLeast(0.02f)).height(4.dp).background(tint, CircleShape))
        }
    }
}

/** 상태 상자 — 진행 중은 초록 · 끝은 청회색 · 모름은 회색. **빨강은 쓰지 않는다**(관전자에게 결과를 지어내는 색이다). */
@Composable
private fun WatchStatusBox(watch: ChessSpectateState) {
    val colors = AingTheme.colors
    val kind = GamesChessWatchStatus.kind(watch)
    val (tint, icon) = when (kind) {
        GamesChessWatchStatus.Kind.loading -> colors.label2 to AppIcon.HourglassEmpty
        is GamesChessWatchStatus.Kind.turn -> colors.working to AppIcon.Visibility
        GamesChessWatchStatus.Kind.ended -> colors.offWork to AppIcon.SportsScore
    }
    Column(
        Modifier.fillMaxWidth().background(tint.copy(alpha = 0.12f), RoundedCornerShape(AingDimens.innerRadius)).padding(horizontal = 12.dp, vertical = 10.dp)
            .semantics(mergeDescendants = true) {}.testTag("chess-watch-status"),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            AingIcon(icon, contentDescription = null, size = 18.dp, tint = tint)
            Text(GamesChessWatchStatus.headline(watch), style = BoardText.subheadline().copy(fontWeight = FontWeight.SemiBold), color = colors.label)
        }
        GamesChessWatchStatus.detail(watch)?.let { Text(it, style = BoardText.rowSubtitle(), color = colors.label2) }
    }
}

/** "12수 · 1분 35초째" — 잎. 끝난 판은 경과를 세지 않는다. */
@Composable
private fun WatchMoveLine(chess: ChessStore, watch: ChessSpectateState) {
    val colors = AingTheme.colors
    val startedAt = watch.startedAt
    val running = startedAt != null && !watch.isFinished
    val tick = rememberTicker(running = running)
    val text = tick.let {
        if (running && startedAt != null) ChessPhoneText.watchPly(watch.plyCount) + " · " + ChessPhoneText.elapsedPhrase(chess.clock().timeIntervalSince(startedAt))
        else ChessPhoneText.watchPly(watch.plyCount)
    }
    Text(text, style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label2)
}
