// 원본: Sources/CheckMobileKit/Games/GamesReversiWatch.swift:168-637(관전 절 뷰 — 판정 몫은 core/stores GamesReversiWatchPlan · WatchStatus · WatchBudget) @ ios-1017-int 3e5051ed
//
// 폰 아잉 뒤집기 **관전 절** — "지금 대결 중" 목록과 남의 진행 중인 판을 **읽기 전용**으로 보는 판. `reversi.spectating` 이 모양을 고른다.
// ── 자리 계약 ── 이 절은 **로비 스크롤 안의 한 절**이다(새 목적지도 새 화면도 아니다 — 목적지를 밀면 `reversiScreenDidDisappear()` 가 `stopWatching()` 을
//   불러 관전이 내려간다). 그래서 제 스크롤도, 떠 있는 아래 막대도 만들지 않는다. [관전]을 누른 자리가 그대로 판이 된다.
// ── 입력이 하나도 없다 ── 판의 탭 처리기·둘 수 있는 칸은 `GamesReversiWatchPlan` 에서 온다(늘 null · 빈 칸). [기권]·[도전]도 없다.
// ── 승자는 서버가 말한 것만 ── 마감이 지나도 결과를 지어내지 않는다(시계가 0 이면 주황으로 멈춰 보여 주고 상태는 여전히 "그 사람 차례"다).
//   끝난 판은 **3인칭**("구름빵(흑) 승리"). 이름은 서버가 말한 흑·백 사람에서만 고른다(로비 카드 a/b 는 uuid 순서라 색이 아니다).
package com.yehsung.aingcheck.ui.games.reversi

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiMatchChrome
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiWatchBudget
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiWatchPlan
import com.yehsung.aingcheck.core.stores.reversi.GamesReversiWatchStatus
import com.yehsung.aingcheck.core.stores.reversi.ReversiLiveMatch
import com.yehsung.aingcheck.core.stores.reversi.ReversiNoticeText
import com.yehsung.aingcheck.core.stores.reversi.ReversiPhoneText
import com.yehsung.aingcheck.core.stores.reversi.ReversiSpectating
import com.yehsung.aingcheck.core.stores.reversi.ReversiStore
import com.yehsung.aingcheck.core.stores.reversi.ReversiUser
import com.yehsung.aingcheck.core.stores.reversi.isMine
import com.yehsung.aingcheck.core.stores.reversi.leaveWatch
import com.yehsung.aingcheck.core.stores.reversi.startWatching
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ReversiColor
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

/** 관전 절. `reversi.spectating` 이 모양을 고른다. */
@Composable
internal fun ReversiWatchSection(reversi: ReversiStore, viewportHeight: Dp, columnWidth: Dp) {
    val watch = reversi.spectating
    if (watch != null) ReversiWatchPanel(reversi, watch, viewportHeight, columnWidth) else ReversiLiveSection(reversi)
}

/** "지금 대결 중" 절 — 남의 판 목록과 [관전] 입구. 목록은 **서버 순서 그대로**(최근 순). */
@Composable
private fun ReversiLiveSection(reversi: ReversiStore) {
    val colors = AingTheme.colors
    val lives = reversi.liveMatches
    BoardSectionHeader(ReversiPhoneText.liveTitle, trailing = if (lives.isEmpty()) null else ReversiPhoneText.liveCount(lives.size))
    BoardGroup {
        if (lives.isEmpty()) {
            BoardRow { Text(ReversiPhoneText.noLive, style = BoardText.subheadline(), color = colors.label2) }
        } else {
            lives.forEachIndexed { index, live -> ReversiLiveRow(reversi, live, isLast = index == lives.size - 1) }
        }
    }
}

/** "지금 대결 중" 한 줄: 두 얼굴 · 이름 둘 · 판돈 액수 · 경과 · 관전자 수 + 관전 입구(좁은 폭에서도 잘리지 않게 글 아래 줄). */
@Composable
private fun ReversiLiveRow(reversi: ReversiStore, live: ReversiLiveMatch, isLast: Boolean) {
    val colors = AingTheme.colors
    val entry = GamesReversiWatchPlan.entry(reversi, reversi.isMine(live))
    val hasEntry = GamesReversiWatchPlan.hasTrailingContent(reversi, live)
    BoardRow(divider = !isLast) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            // 두 얼굴은 화면 읽기에서 숨는다(이름은 아래 글 묶음이 말한다).
            Row(Modifier.clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                BoardAvatar(live.a.displayName, live.a.id, 30.dp, url = live.a.avatarURL, characterHint = live.a.characterID)
                Text("vs", style = BoardText.rowSubtitle(), color = colors.label2)
                BoardAvatar(live.b.displayName, live.b.id, 30.dp, url = live.b.avatarURL, characterHint = live.b.characterID)
            }
            // 합치기는 **이 글 묶음에만** — 행 전체를 합치면 [관전]이 한 덩이에 삼켜져 화면 읽기가 누를 수 없다.
            Column(Modifier.semantics(mergeDescendants = true) {}) {
                Text(ReversiPhoneText.livePair(live), style = BoardText.rowTitle(), color = colors.label)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    // ★ 남의 판이라 꼬리('이기면 +N')를 붙이지 않는다(판돈 액수만).
                    BoardStakeLine(live.stake.toLong())
                    ElapsedText(reversi, live.startedAt)
                }
            }
            if (hasEntry) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    WatcherBadge(live.watchers.toLong())
                    when (entry) {
                        GamesReversiWatchPlan.Entry.absent -> Unit
                        GamesReversiWatchPlan.Entry.myMatch -> Text(ReversiPhoneText.myMatch, style = BoardText.rowSubtitle(), color = colors.label2)
                        GamesReversiWatchPlan.Entry.soon -> Text(ReversiPhoneText.watchSoonCaption, style = BoardText.rowSubtitle(), color = colors.label2,
                            modifier = Modifier.semantics { contentDescription = ReversiNoticeText.unavailable })
                        GamesReversiWatchPlan.Entry.chip -> BoardButton(ReversiPhoneText.watch, kind = BoardButtonKind.Tinted, small = true,
                            testTag = ReversiScreenTags.watchChip(live.id), hint = ReversiPhoneText.watchChipHint) { reversi.startWatching(live.id) }
                    }
                }
            }
        }
    }
}

/** " · 1분 35초째" — **잎**(절 루트가 시계를 읽으면 1초마다 목록이 다시 그려진다). */
@Composable
private fun ElapsedText(reversi: ReversiStore, startedAt: SwiftDate) {
    val tick = rememberTicker()
    val text = tick.let { " · " + ReversiPhoneText.elapsedPhrase(reversi.clock().timeIntervalSince(startedAt)) }
    Text(text, style = BoardText.digits(BoardText.rowSubtitle()), color = AingTheme.colors.label2)
}

/**
 * 관전 판 — "지금 대결 중" 절이 **그 자리에서** 이 모양으로 바뀐다. 위에서부터: 절 머리(+[나가기]) · 흑 카드 · 판 · 백 카드 · 상태 상자 · 판돈·관전자 | N수·경과 ·
 * 수 기록 · 캡션. **입력이 하나도 없다.**
 */
@Composable
private fun ReversiWatchPanel(reversi: ReversiStore, watch: ReversiSpectating, viewportHeight: Dp, columnWidth: Dp) {
    val colors = AingTheme.colors
    Column(Modifier.fillMaxWidth().testTag(ReversiScreenTags.watch), verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        // 문은 하나다 — `leaveWatch()` 는 관전을 내리고 로비·순위를 다시 읽는다(`stopWatching()` 은 낡은 목록을 남긴다).
        BoardSectionHeader(ReversiPhoneText.watchTitle, action = ReversiPhoneText.leaveWatch to { reversi.leaveWatch() }, actionHint = ReversiPhoneText.leaveWatchHint,
            actionTag = ReversiScreenTags.leaveWatch)
        if (watch.blackUser != null || watch.whiteUser != null || watch.faces.isNotEmpty()) {
            WatchPlayerRow(reversi, watch, ReversiColor.black, 0)
            WatchBoard(reversi, watch, viewportHeight, columnWidth)
            WatchPlayerRow(reversi, watch, ReversiColor.white, 1)
        } else {
            // 씨앗도 응답도 없다(로비 주기 사이 목록에서 빠진 판을 눌렀다) — 빈 카드 두 장 대신 한 줄이다.
            BoardGroup {
                BoardRow {
                    if (watch.isFinished) Text(ReversiPhoneText.playersUnknown, style = BoardText.subheadline(), color = colors.label2) else BoardLoading(ReversiPhoneText.watchLoading)
                }
            }
            WatchBoard(reversi, watch, viewportHeight, columnWidth)
        }
        WatchStatusBox(reversi, watch)
        BoardGroup {
            BoardRow {
                if (reversiLargeFont()) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        WatchStakeRow(reversi, watch)
                        WatchMoveLine(reversi, watch)
                    }
                } else {
                    Box(Modifier.weight(1f)) { WatchStakeRow(reversi, watch) }
                    WatchMoveLine(reversi, watch)
                }
            }
        }
        ReversiMoveList(watch.plies, watch.counts)
        Column(Modifier.semantics(mergeDescendants = true) {}) {
            BoardCaption(ReversiPhoneText.watchCaption)
            if (watch.isFinished) BoardCaption(ReversiPhoneText.watchTailCaption)
        }
    }
}

/** 판돈 액수 + **관전자 수**(0 이면 눈 칸이 서지 않는다). ★ 꼬리를 붙이지 않는다(관전자는 한 푼도 못 얻는다). */
@Composable
private fun WatchStakeRow(reversi: ReversiStore, watch: ReversiSpectating) {
    val colors = AingTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        val stake = watch.stake
        if (stake != null) BoardStakeLine(stake.toLong()) else Text(ReversiPhoneText.stakeUnknown, style = BoardText.rowSubtitle(), color = colors.label2)
        WatcherBadge(reversi.spectatorCount.toLong())
    }
}

/** "12수 · 1분 35초째" — **잎**. 끝난 판은 경과를 세지 않는다. */
@Composable
private fun WatchMoveLine(reversi: ReversiStore, watch: ReversiSpectating) {
    val startedAt = watch.startedAt
    val running = startedAt != null && !watch.isFinished
    val tick = rememberTicker(running = running)
    val text = tick.let {
        if (running && startedAt != null) ReversiPhoneText.watchMoves(watch.moveCount) + " · " + ReversiPhoneText.elapsedPhrase(reversi.clock().timeIntervalSince(startedAt))
        else ReversiPhoneText.watchMoves(watch.moveCount)
    }
    Text(text, style = BoardText.digits(BoardText.rowSubtitle()), color = AingTheme.colors.label2)
}

/**
 * 판 한 장(가운데). ★ **입력이 0건이다** — 값은 전부 `GamesReversiWatchPlan` 에서 온다. 뒤집기 그림은 코어가 관전에도 붙인다(`applyWatch`).
 * 한 변은 열 폭과 스크롤 뷰포트 높이로 정한다(`GamesReversiWatchBudget`). 큰 글자에서는 예산 상수가 실제보다 작아져 상한이 낙관적이 된다 — 보이는 높이의 비율로 한 번 더 줄인다.
 */
@Composable
private fun WatchBoard(reversi: ReversiStore, watch: ReversiSpectating, viewportHeight: Dp, columnWidth: Dp) {
    val colors = AingTheme.colors
    val scale = LocalDensity.current.fontScale
    val viewport = viewportHeight.value.toDouble().let { h ->
        when {
            h <= 0 -> 0.0
            scale >= 1.3f -> GamesReversiWatchBudget.blocksAroundBoard() + h * 0.40
            scale >= 1.15f -> GamesReversiWatchBudget.blocksAroundBoard() + h * 0.52
            else -> h
        }
    }
    val side = GamesReversiWatchBudget.side(columnWidth.value.toDouble(), viewport).dp
    val shadow = if (colors.isDark) ReversiBoardInk.shadowDark else ReversiBoardInk.shadowLight
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        ReversiPlayBoard(
            store = reversi, matchID = watch.id, board = watch.board, side = side,
            legalTargets = GamesReversiWatchPlan.boardLegalTargets,
            lastStoneIdx = watch.lastStoneIdx, autoStones = watch.autoStones,
            turn = if (watch.isFinished) null else watch.turn,
            onTap = GamesReversiWatchPlan.boardTapHandler,
            modifier = Modifier.shadow(9.dp, RoundedCornerShape(side * 0.025f), ambientColor = shadow, spotColor = shadow),
            testTag = ReversiScreenTags.watchBoard,
        )
    }
}

/** 관전 사람 한 장 — 초상(+ 돌 배지) · 이름(+ 센터) · 돌 수 · 차례면 마감 링. **흑·백을 추측하지 않는다**: 서버가 색을 말하기 전에는 씨앗 얼굴만 그리고 돌 배지·시계를 달지 않는다. */
@Composable
private fun WatchPlayerRow(reversi: ReversiStore, watch: ReversiSpectating, color: ReversiColor, index: Int) {
    val colors = AingTheme.colors
    val known = watch.blackUser != null && watch.whiteUser != null
    val user: ReversiUser?
    val subtitle: String?
    if (known) {
        user = if (color == ReversiColor.black) watch.blackUser else watch.whiteUser
        subtitle = GamesReversiMatchChrome.cardSubtitle(color, watch.counts, if (color == ReversiColor.black) watch.blackAutoStreak else watch.whiteAutoStreak, reversi.autoAbandonStreak)
    } else {
        user = watch.faces.getOrNull(index)
        subtitle = if (index == 0 && !watch.isFinished) ReversiPhoneText.watchLoading else null
    }
    val isTurn = known && !watch.isFinished && watch.turn == color
    val shape = RoundedCornerShape(AingDimens.groupRadius)
    Row(
        // 차례인 카드만 초록 테두리. 남은 시간이 0 이어도 초록이다 — 차례는 여전히 그 사람 것이다(결과가 아니다).
        Modifier.fillMaxWidth().background(colors.surface, shape).border(2.dp, if (isTurn) colors.workingDot else Color.Transparent, shape)
            .padding(horizontal = 14.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(AingDimens.space3), verticalAlignment = Alignment.CenterVertically,
    ) {
        // 표정은 늘 기본 — 관전 응답에 근무 칸이 없어 근무 표정을 쓰면 전원이 근무 중으로 보인다.
        BoardPortrait(user?.characterID, CharacterMood.Plain, 44.dp, stoneIsBlack = if (known) color == ReversiColor.black else null)
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
            BoardPersonName(GamesReversiWatchStatus.displayName(user), center = user?.center)
            if (subtitle != null) Text(subtitle, style = BoardText.digits(BoardText.rowSubtitle()), color = colors.label2)
        }
        val deadline = watch.deadline
        if (isTurn && deadline != null) WatchRing(reversi, deadline)
    }
}

/**
 * 관전 마감 링 — **잎**. 내 판 링은 `remainingSeconds`(**내 판 전용**)를 읽으므로 쓰지 않고, 관전 판의 마감 시각을 스토어 시계로 직접 센다.
 * 한 수 시간은 로비가 말한 값(`turnSeconds`). 0 은 주황(`clockTint`).
 */
@Composable
private fun WatchRing(reversi: ReversiStore, deadline: SwiftDate) {
    val tick = rememberTicker(running = reversi.isWindowVisible, periodMillis = 200)
    val remaining = tick.let { maxOf(0.0, deadline.timeIntervalSince(reversi.clock())) }
    ReversiRing(remaining, GamesReversiMatchChrome.ringFraction(remaining, reversi.turnSeconds), GamesReversiWatchStatus.clockTint(remaining))
}

/** 상태 상자 — 진행 중은 초록 · 끝은 청회색 · 모름은 회색. **빨강은 쓰지 않는다**(관전자에게 결과를 지어내는 색이다). */
@Composable
private fun WatchStatusBox(reversi: ReversiStore, watch: ReversiSpectating) {
    val colors = AingTheme.colors
    val kind = GamesReversiWatchStatus.kind(watch)
    val (tint, icon) = when (kind) {
        GamesReversiWatchStatus.Kind.loading -> colors.label2 to AppIcon.HourglassEmpty
        is GamesReversiWatchStatus.Kind.turn -> colors.working to AppIcon.Visibility
        GamesReversiWatchStatus.Kind.ended -> colors.offWork to AppIcon.SportsScore
    }
    Column(
        Modifier.fillMaxWidth().background(tint.copy(alpha = 0.12f), RoundedCornerShape(AingDimens.innerRadius)).padding(horizontal = 12.dp, vertical = 10.dp)
            .semantics(mergeDescendants = true) {}.testTag("reversi-watch-status"),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            AingIcon(icon, contentDescription = null, size = 18.dp, tint = tint)
            Text(GamesReversiWatchStatus.headline(watch), style = BoardText.subheadline().copy(fontWeight = FontWeight.SemiBold), color = colors.label)
        }
        GamesReversiWatchStatus.detail(watch, reversi.autoAbandonStreak)?.let { Text(it, style = BoardText.rowSubtitle(), color = colors.label2) }
    }
}
