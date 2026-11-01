// 원본: Sources/CheckMobileKit/Games/GamesRummyMatchChrome.swift:1 @ ios-1017-cube d5c9eeff · 맥 Sources/check/RummyPanelMatch.swift:842-1172 (버튼 · 자리 카드 · 판돈 · 더미) · Sources/check/RummyRackCues.swift:132,153 (배지 · [완료] 안 초) @ 1a5eeca6 · 설계서 §10
//
// 판 화면의 판 · 받침대 바깥 — 왼쪽 열(뒤로 · 규칙 · 자리 카드) · 오른쪽 열(판돈 · 더미 · 반응 · 전체 보기 · 동작 버튼) · 상태 줄 · 안내. 맥 위 띠 · 자리 카드 · 버튼을 가로 화면 양옆 열로 옮겼다.
// 칸 자리는 전부 GamesRummyMatchLayout 한 값이다. 높이가 낮아 큰 글자에서 스크롤 없이 들어가야 한다 — 글자 배율을 칸마다 자른다([GamesRummyCappedText]).
// 초 단위 값은 **잎**(링 · 초 글자)만 읽는다 — 화면이 매초 다시 조립되지 않게. 잎의 고리는 열쇠가 안 바뀌는 효과 하나다(재생성 고리 금지).
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasSize
import com.yehsung.aingcheck.core.rules.rummy.RummyRackSort
import com.yehsung.aingcheck.core.rules.rummy.RummyTurnEditor
import com.yehsung.aingcheck.core.rules.rummy.initialPlanPoints
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.drawTile
import com.yehsung.aingcheck.core.stores.rummy.resetTurn
import com.yehsung.aingcheck.core.stores.rummy.submitTurn
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.RummyMatchSeat
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.ui.components.RubyIcon
import com.yehsung.aingcheck.ui.components.rememberRubyArt
import com.yehsung.aingcheck.ui.games.gomoku.BoardAvatar
import com.yehsung.aingcheck.ui.games.minigame.kit.TNUM
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay
import kotlin.math.ceil

/** 글자 배율을 [max] 로 자른다 — 칸 높이가 정해진 줄이 큰 글자에서 잘리지 않게. */
@Composable
internal fun GamesRummyCappedText(max: Float, content: @Composable () -> Unit) {
    val density = LocalDensity.current
    if (density.fontScale <= max) {
        content()
    } else {
        CompositionLocalProvider(LocalDensity provides Density(density.density, max), content = content)
    }
}

/** 남은 초(그때그때 스토어에 묻는다). 열쇠가 안 바뀌는 고리 하나 — 값은 그리는 쪽만 읽는다. */
@Composable
private fun rememberTurnRemaining(rummy: RummyStore, now: () -> SwiftDate, stepMillis: Long): State<Double?> {
    val state = remember(rummy) { mutableStateOf(rummy.turnRemaining(now())) }
    val clock by rememberUpdatedState(now)
    LaunchedEffect(rummy, stepMillis) {
        while (true) {
            state.value = rummy.turnRemaining(clock())
            delay(stepMillis)
        }
    }
    return state
}

private fun wholeSeconds(remaining: Double): Int = maxOf(0, ceil(remaining).toInt())

/** 남은 시간 색(링 · 초). 평소는 null — 부르는 쪽 기본색. */
@Composable
private fun countdownTint(remaining: Double): Color? = when (GamesRummyCountdownTone.of(remaining)) {
    GamesRummyCountdownTone.normal -> null
    GamesRummyCountdownTone.warning -> AingTheme.colors.pending
    GamesRummyCountdownTone.danger -> AingTheme.colors.danger
}

// MARK: - 열 위쪽

/** 열 안의 원형 버튼. 터치 자리는 칸 전체다(그림 지름 38 · 터치 자리 44×44 — [GamesRummyMatchLayout.navButton]). */
@Composable
private fun RowScope.ColumnButton(icon: AppIcon, label: String, tag: String, onClick: () -> Unit) {
    val colors = AingTheme.colors
    Box(
        Modifier
            .weight(1f)
            .fillMaxHeight()
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label }
            .testTag(tag),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.size(GamesRummyMatchLayout.navButtonDiameter.dp).background(colors.surface, CircleShape).border(0.8.dp, colors.separator, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            AingIcon(icon, contentDescription = null, size = 20.dp, tint = colors.label)
        }
    }
}

/** 왼쪽 열 위 — [나가기] · [규칙]. 판 안 칸이라 시스템 막대의 뒤로가 안 보인다. */
@Composable
internal fun GamesRummyNavButtons(onExit: () -> Unit, onRules: () -> Unit, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(GamesRummyMatchLayout.navGap.dp)) {
        ColumnButton(AppIcon.ChevronLeft, GamesRummyMatchText.leaveDescription, GamesRummyMatchTags.BACK, onExit)
        ColumnButton(AppIcon.MenuBook, RummyPhoneText.rules, GamesRummyMatchTags.RULES, onRules)
    }
}

/** 오른쪽 열 위 — 판돈 · 더미. */
@Composable
internal fun GamesRummyMatchInfo(match: RummyMatchState, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    GamesRummyCappedText(1.15f) {
        Column(modifier.testTag(GamesRummyMatchTags.INFO), verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                RubyIcon(rememberRubyArt(14f), size = 14.dp)
                Text(
                    RummyPhoneText.matchPot(match.stake, match.seatCount),
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = TNUM),
                    color = colors.label,
                    maxLines = 1,
                    softWrap = false,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                GamesRummyTileBack(RummyCanvasSize(10.0, 14.0))
                Text(
                    RummyPhoneText.pool(match.poolCount),
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = TNUM),
                    color = colors.label,
                    maxLines = 1,
                    softWrap = false,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.semantics { contentDescription = "${RummyPhoneText.poolLabel} ${match.poolCount ?: 0}" },
                )
            }
        }
    }
}

/** 오른쪽 열 — [반응] · [전체 보기]. */
@Composable
internal fun GamesRummyToolRow(model: GamesRummyMatchModel, onReaction: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceEvenly) {
        Box(
            Modifier.size(44.dp).clickable(role = Role.Button, onClick = onReaction)
                .semantics { contentDescription = RummyPhoneText.reactionButton }
                .testTag(GamesRummyReactionTags.BUTTON),
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(GamesRummyMatchLayout.navButtonDiameter.dp).background(colors.surface, CircleShape).border(0.8.dp, colors.separator, CircleShape), contentAlignment = Alignment.Center) {
                AingIcon(AppIcon.Mood, contentDescription = null, size = 20.dp, tint = colors.label)
            }
        }
        GamesRummyZoomButton(model)
    }
}

/** [전체 보기] 토글 — 오른쪽 열(판 위에 두면 타일을 가린다). 보기를 파생값으로만 읽는다 — 밀 때마다 다시 조립하지 않는다. */
@Composable
internal fun GamesRummyZoomButton(model: GamesRummyMatchModel, modifier: Modifier = Modifier, tag: String = GamesRummyMatchTags.ZOOM) {
    val colors = AingTheme.colors
    val isFull by remember(model) { derivedStateOf { model.viewport.isFullView } }
    Box(
        modifier.size(44.dp).clickable(role = Role.Button) { model.toggleFullView() }
            .semantics { contentDescription = if (isFull) RummyPhoneText.zoomIn else RummyPhoneText.zoomOut }
            .testTag(tag),
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(GamesRummyMatchLayout.navButtonDiameter.dp).background(colors.surface, CircleShape).border(0.8.dp, colors.separator, CircleShape), contentAlignment = Alignment.Center) {
            // 있는 기호 중 뜻이 맞는 것: 판이 다 보이면 늘려 보기(모서리로 뻗는 화살표), 아니면 한눈에(격자).
            AingIcon(if (isFull) AppIcon.NorthEast else AppIcon.GridViewFill, contentDescription = null, size = 20.dp, tint = colors.label)
        }
    }
}

// MARK: - 자리 카드

/** 왼쪽 열 — 상대를 내 다음 차례부터 위에서 아래로 · 내 자리는 맨 아래. **남의 패는 장수만** 보인다. 칸 자리는 값이고 인원과 무관하다(말풍선 닻도 카드다). */
@Composable
internal fun GamesRummySeatColumn(rummy: RummyStore, match: RummyMatchState, layout: GamesRummyMatchLayout, now: () -> SwiftDate) {
    val anchors = LocalGamesRummyReactionAnchors.current
    GamesRummyCappedText(1f) {
        GamesRummySeats.opponents(match).take(GamesRummyMatchLayout.maxOpponentCards).forEachIndexed { index, seat ->
            GamesRummySeatCard(rummy, match, seat, layout.isSeatCardCompact, now, Modifier.atRect(layout.opponentCard(index)).rummyReactionAnchor(anchors, seat.seatNo).testTag(GamesRummyMatchTags.seat(seat.seatNo)))
        }
        GamesRummySeats.mine(match)?.let { seat ->
            GamesRummySeatCard(rummy, match, seat, layout.isSeatCardCompact, now, Modifier.atRect(layout.mySeatCard).rummyReactionAnchor(anchors, seat.seatNo).testTag(GamesRummyMatchTags.MY_SEAT))
        }
    }
}

/** [compact] = 낮은 칸([GamesRummyMatchLayout.isSeatCardCompact]) — 얼굴을 줄여 태그 줄까지 카드 안에 담는다. */
@Composable
private fun GamesRummySeatCard(rummy: RummyStore, match: RummyMatchState, seat: RummyMatchSeat, compact: Boolean, now: () -> SwiftDate, modifier: Modifier) {
    val colors = AingTheme.colors
    val ringDiameter = if (compact) 26.dp else 34.dp
    val isTurn = GamesRummySeats.isTurn(seat, match)
    val tags = GamesRummySeats.tags(seat)
    val name = seat.displayName ?: "?"
    val shape = RoundedCornerShape(12.dp)
    val summary = GamesRummyMatchText.seatSummary(name, seat.rackCount, isTurn, tags.map { it.text })
    Column(
        modifier
            .alpha(if (GamesRummySeats.isGone(seat)) 0.5f else 1f)
            .clip(shape)
            .background(if (isTurn) colors.accentTint else colors.surface, shape)
            .border(if (isTurn) 1.5.dp else 0.8.dp, if (isTurn) colors.accent else colors.separator, shape)
            .clearAndSetSemantics { contentDescription = summary }
            .padding(start = 4.dp, end = 4.dp, top = 3.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Box(Modifier.size(ringDiameter), contentAlignment = Alignment.Center) {
                if (isTurn) GamesRummyTurnRing(rummy, GamesRummySeats.turnTotal(match), now, Modifier.size(ringDiameter))
                BoardAvatar(name, seat.userId.lowercased, ringDiameter - 7.dp, url = seat.avatarUrl, characterHint = seat.character)
            }
            Column {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    GamesRummyTileBack(RummyCanvasSize(8.0, 11.0))
                    Text(
                        RummyPhoneText.rackCount(seat.rackCount),
                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, fontFeatureSettings = TNUM),
                        color = colors.label,
                        maxLines = 1,
                        softWrap = false,
                    )
                }
                if (isTurn) GamesRummySeatSeconds(rummy, now)
            }
        }
        Text(
            name,
            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
            color = colors.label,
            maxLines = 1,
            softWrap = false,
            overflow = TextOverflow.Ellipsis,
        )
        tags.firstOrNull()?.let { tag ->
            Text(
                tag.text,
                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                color = if (tag == GamesRummySeatTag.BeforeInitial) colors.pending else colors.danger,
                maxLines = 1,
                softWrap = false,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/** 차례 시간 링 — **잎**만 시계를 읽고, 값은 그리기 단계에서만 읽는다. */
@Composable
private fun GamesRummyTurnRing(rummy: RummyStore, total: Double, now: () -> SwiftDate, modifier: Modifier) {
    val colors = AingTheme.colors
    val remaining by rememberTurnRemaining(rummy, now, 500L)
    val warning = colors.pending
    val danger = colors.danger
    val accent = colors.accent
    val track = colors.fill
    Canvas(modifier.clearAndSetSemantics { }) {
        val left = remaining ?: total
        val fraction = (left / maxOf(total, 1.0)).coerceIn(0.0, 1.0).toFloat()
        val stroke = 3f * density
        val inset = stroke / 2
        val arc = Size(size.width - stroke, size.height - stroke)
        drawCircle(track, radius = arc.width / 2, center = center, style = Stroke(stroke))
        val tint = when (GamesRummyCountdownTone.of(left)) {
            GamesRummyCountdownTone.normal -> accent
            GamesRummyCountdownTone.warning -> warning
            GamesRummyCountdownTone.danger -> danger
        }
        drawArc(tint, -90f, 360f * fraction, useCenter = false, topLeft = Offset(inset, inset), size = arc, style = Stroke(stroke, cap = StrokeCap.Round))
    }
}

/** 남은 초 글자(자리 카드). */
@Composable
private fun GamesRummySeatSeconds(rummy: RummyStore, now: () -> SwiftDate) {
    val remaining by rememberTurnRemaining(rummy, now, 500L)
    val left = remaining ?: return
    Text(
        RummyPhoneText.seconds(wholeSeconds(left)),
        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, fontFeatureSettings = TNUM),
        color = countdownTint(left) ?: AingTheme.colors.label2,
        maxLines = 1,
        softWrap = false,
    )
}

// MARK: - 상태 줄

/** 코어 문구 한 줄(왼쪽) · 직전 사건 · 남의 차례 · 내 시간 초과 · 첫 등록 전 받침대 합(오른쪽). 자리가 모자라면 직전 사건부터 줄어든다(지금 할 일이 먼저다). */
@Composable
internal fun GamesRummyStatusRow(line: GamesRummyStatusLine, plan: String?, planReached: Boolean, tail: GamesRummyStatusTail, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val tint = when (line.tone) {
        GamesRummyStatusLine.Tone.notice -> colors.pending
        GamesRummyStatusLine.Tone.ready -> colors.working
        GamesRummyStatusLine.Tone.plain -> colors.label
        GamesRummyStatusLine.Tone.quiet -> colors.label2
    }
    val hasTail = tail.lastEvent != null || tail.turn != null || line.warning != null || plan != null
    GamesRummyCappedText(1f) {
        Row(modifier.padding(horizontal = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                line.text,
                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                color = tint,
                maxLines = 1,
                softWrap = false,
                overflow = TextOverflow.Ellipsis,
                modifier = (if (hasTail) Modifier.weight(GAMES_RUMMY_STATUS_SHARE, fill = false) else Modifier.weight(1f)).testTag(GamesRummyMatchTags.STATUS),
            )
            if (hasTail) {
                Row(
                    Modifier.weight(1f - GAMES_RUMMY_STATUS_SHARE, fill = false).padding(start = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.End),
                ) {
                    tail.lastEvent?.let { last ->
                        Text(
                            last,
                            style = MaterialTheme.typography.labelSmall,
                            color = colors.label2,
                            maxLines = 1,
                            softWrap = false,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f, fill = false).testTag(GamesRummyMatchTags.LAST_EVENT),
                        )
                    }
                    tail.turn?.let { turn ->
                        AingIcon(if (tail.isPlacing) AppIcon.TouchAppFill else AppIcon.HourglassEmpty, contentDescription = null, size = 12.dp, tint = colors.accent)
                        Text(turn, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = colors.accent, maxLines = 1, softWrap = false)
                    }
                    line.warning?.let { warning ->
                        Text(warning, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, fontFeatureSettings = TNUM), color = colors.danger, maxLines = 1, softWrap = false, modifier = Modifier.testTag(GamesRummyMatchTags.WARNING))
                    }
                    if (plan != null) {
                        Text(
                            plan,
                            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, fontFeatureSettings = TNUM),
                            color = if (planReached) colors.working else colors.label2,
                            maxLines = 1,
                            softWrap = false,
                        )
                    }
                }
            }
        }
    }
}

/** 꼬리가 있을 때 상태 글자가 차지할 수 있는 몫 — 지금 할 일이 먼저다. */
private const val GAMES_RUMMY_STATUS_SHARE: Float = 0.58f

/** 첫 등록 전 합 글자 — 판 쪽은 내 차례에만 센다(남의 차례 판은 내 것이 아니다). 랙 묶음이 없으면 null. */
internal fun gamesRummyPlanLine(editor: RummyTurnEditor?, isMyTurn: Boolean): Pair<String, Boolean>? {
    val planned = editor?.initialPlanPoints ?: return null
    if (planned.rack <= 0) return null
    val table = if (isMyTurn) planned.table else 0
    return RummyPhoneText.plan(table, planned.rack) to (table + planned.rack >= 30)
}

// MARK: - 동작 버튼

/** 오른쪽 열 아래 — [완료(남은 초)] 가장 크게 · [뽑기|넘기기] · [되돌리기] · [777|789]. 칸은 값으로 정해져 있다. [locked] = 손이 판을 쥐고 있다 — 눌러도 안 간다. [onSort] = 정렬(시차를 정하는 판 화면을 지난다). */
@Composable
internal fun GamesRummyActionColumn(rummy: RummyStore, match: RummyMatchState, editor: RummyTurnEditor?, isMyTurn: Boolean, layout: GamesRummyMatchLayout, locked: Boolean, now: () -> SwiftDate, onSort: (RummyRackSort) -> Unit) {
    val canEdit = isMyTurn && !rummy.isWorking
    val poolEmpty = (match.poolCount ?: 0L) == 0L
    val submitEnabled = canEdit && editor?.canSubmit == true
    val undoEnabled = canEdit && (editor?.isChanged == true || editor?.isLayoutChanged == true)
    GamesRummyCappedText(1.15f) {
        SubmitButton(rummy, isMyTurn, submitEnabled, locked, layout.submit.height, now, Modifier.atRect(layout.submit))
        DrawButton(rummy, poolEmpty, canEdit, locked, Modifier.atRect(layout.draw))
        UndoButton(rummy, undoEnabled, locked, Modifier.atRect(layout.undo))
        SortButtons(rummy, editor != null, locked, onSort, Modifier.atRect(layout.sort))
    }
}

/** 꺼져도 남은 초는 또렷해야 한다 — 전체를 흐리게 하지 않고 색만 바꾼다(꺼진 동안에도 시간은 간다). 칸이 낮으면 글자와 초를 한 줄로 놓는다. */
@Composable
private fun SubmitButton(rummy: RummyStore, isMyTurn: Boolean, enabled: Boolean, locked: Boolean, height: Double, now: () -> SwiftDate, modifier: Modifier) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(12.dp)
    val ink = if (enabled) colors.onAccentFill else colors.label3Text
    val body = modifier
        .clip(shape)
        .background(if (enabled) colors.accentFill else colors.fill, shape)
        .clickable(enabled = enabled && !locked, role = Role.Button) { rummy.submitTurn() }
        .testTag(GamesRummyMatchTags.SUBMIT)
    val title: @Composable () -> Unit = {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            AingIcon(AppIcon.Check, contentDescription = null, size = 15.dp, tint = ink)
            Text(RummyPhoneText.submit, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Black), color = ink, maxLines = 1, softWrap = false)
        }
    }
    if (height < GAMES_RUMMY_SUBMIT_STACK_HEIGHT) {
        Row(body, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally)) {
            title()
            if (isMyTurn) GamesRummySubmitSeconds(rummy, enabled, now)
        }
    } else {
        Column(body, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically)) {
            title()
            if (isMyTurn) GamesRummySubmitSeconds(rummy, enabled, now)
        }
    }
}

private const val GAMES_RUMMY_SUBMIT_STACK_HEIGHT: Double = 54.0

/** [완료] 안 남은 초(10초 이하 주황 · 5초 이하 빨강). */
@Composable
private fun GamesRummySubmitSeconds(rummy: RummyStore, enabled: Boolean, now: () -> SwiftDate) {
    val remaining by rememberTurnRemaining(rummy, now, 500L)
    val left = remaining ?: return
    val seconds = wholeSeconds(left)
    Box(
        Modifier
            .background(countdownTint(left) ?: Color.Black.copy(alpha = if (enabled) 0.28f else 0.5f), CircleShape)
            .padding(horizontal = 6.dp, vertical = 1.dp)
            .semantics { contentDescription = GamesRummyMatchText.remaining(seconds) },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            RummyPhoneText.seconds(seconds),
            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, fontFeatureSettings = TNUM),
            color = Color.White,
            maxLines = 1,
            softWrap = false,
        )
    }
}

@Composable
private fun DrawButton(rummy: RummyStore, poolEmpty: Boolean, enabled: Boolean, locked: Boolean, modifier: Modifier) {
    SecondaryButton(
        if (poolEmpty) RummyPhoneText.pass else RummyPhoneText.draw,
        if (poolEmpty) AppIcon.ArrowRightFill else AppIcon.FilterNone,
        enabled,
        locked,
        GamesRummyMatchTags.DRAW,
        modifier,
    ) { rummy.drawTile() }
}

@Composable
private fun UndoButton(rummy: RummyStore, enabled: Boolean, locked: Boolean, modifier: Modifier) {
    SecondaryButton(RummyPhoneText.undo, AppIcon.Undo, enabled, locked, GamesRummyMatchTags.UNDO, modifier) { rummy.resetTurn() }
}

@Composable
private fun SecondaryButton(title: String, icon: AppIcon, enabled: Boolean, locked: Boolean, tag: String, modifier: Modifier, onClick: () -> Unit) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(12.dp)
    val ink = if (enabled) colors.label else colors.label3Text
    Column(
        modifier
            .clip(shape)
            .background(colors.surface, shape)
            .border(0.8.dp, colors.separator, shape)
            .clickable(enabled = enabled && !locked, role = Role.Button, onClick = onClick)
            .testTag(tag),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(1.dp, Alignment.CenterVertically),
    ) {
        AingIcon(icon, contentDescription = null, size = 15.dp, tint = ink)
        Text(title, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = ink, maxLines = 1, softWrap = false)
    }
}

@Composable
private fun SortButtons(rummy: RummyStore, enabled: Boolean, locked: Boolean, onSort: (RummyRackSort) -> Unit, modifier: Modifier) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(12.dp)
    val selected = rummy.rackSortMode
    Row(
        modifier
            .alpha(if (enabled) 1f else 0.45f)
            .clip(shape)
            .background(colors.surface, shape)
            .border(0.8.dp, colors.separator, shape),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SortSegment(onSort, RummyRackSort.number, RummyPhoneText.sortNumber, GamesRummyMatchText.sortNumberName, selected == RummyRackSort.number, enabled && !locked, GamesRummyMatchTags.SORT_NUMBER)
        Box(Modifier.width(GamesRummyMatchLayout.sortDividerWidth.dp).fillMaxHeight().padding(vertical = 8.dp).background(colors.separator))
        SortSegment(onSort, RummyRackSort.color, RummyPhoneText.sortColor, GamesRummyMatchText.sortColorName, selected == RummyRackSort.color, enabled && !locked, GamesRummyMatchTags.SORT_COLOR)
    }
}

@Composable
private fun RowScope.SortSegment(onSort: (RummyRackSort) -> Unit, mode: RummyRackSort, title: String, name: String, on: Boolean, enabled: Boolean, tag: String) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(10.dp)
    Box(
        Modifier
            .weight(1f)
            .fillMaxHeight()
            // 안쪽 여백 없이 칸을 반씩 쓴다([GamesRummyMatchLayout.sortButton]) — 터치 자리가 44 아래로 안 내려가게. 켜진 표시만 안으로 들인다.
            .clickable(enabled = enabled, role = Role.Button) { onSort(mode) }
            .semantics { contentDescription = name }
            .testTag(tag)
            .padding(2.dp)
            .clip(shape)
            .background(if (on) colors.accentFill else Color.Transparent, shape),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title,
            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, fontFeatureSettings = TNUM),
            color = if (on) colors.onAccentFill else colors.label,
            maxLines = 1,
            softWrap = false,
        )
    }
}

// MARK: - 판 위 안내

/** 판 가운데 '내 차례' 배지. */
@Composable
internal fun GamesRummyTurnBadge(modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Row(
        modifier
            .height(40.dp)
            .background(colors.accentFill, CircleShape)
            .border(1.5.dp, Color.White.copy(alpha = 0.85f), CircleShape)
            .padding(horizontal = 18.dp)
            .testTag(GamesRummyMatchTags.TURN_BADGE),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        AingIcon(AppIcon.AutoAwesome, contentDescription = null, size = 18.dp, tint = colors.onAccentFill)
        Text(RummyPhoneText.myTurnBadge, style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Black), color = colors.onAccentFill, maxLines = 1, softWrap = false)
    }
}

/** 다른 기기 판 안내 — 읽기만 하는 동안. **입력은 막지 않는다**(맥과 같다 — 여기서 타일을 옮기면 이 폰에서 이어 한다). 같은 층의 다른 줄과 같은 글자 상한 — 없으면 큰 글자에서 카드가 판을 다 가린다. */
@Composable
internal fun GamesRummyElsewhereCard(modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(12.dp)
    GamesRummyCappedText(1.15f) {
        Column(
            modifier
                .padding(horizontal = 10.dp)
                .fillMaxWidth()
                .background(colors.surface, shape)
                .border(0.8.dp, colors.separator, shape)
                .padding(horizontal = 12.dp, vertical = 9.dp)
                .semantics(mergeDescendants = true) { }
                .testTag(GamesRummyMatchTags.ELSEWHERE),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                AingIcon(AppIcon.Smartphone, contentDescription = null, size = 15.dp, tint = colors.label)
                Text(RummyPhoneText.otherDevice, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold), color = colors.label)
            }
            Text(RummyPhoneText.otherDeviceDetail, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Normal), color = colors.label2)
        }
    }
}

/** 방향 전환 중 · 전환이 안 되는 동안의 그림. 차례 시간은 흐르니 [나가기]는 늘 닿아야 한다. */
@Composable
internal fun GamesRummyRotatingView(onExit: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Box(modifier.fillMaxSize().testTag(GamesRummyMatchTags.ROTATING)) {
        Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            CircularProgressIndicator(Modifier.size(28.dp), strokeWidth = 2.5.dp, color = colors.accent)
            Text(RummyPhoneText.rotating, style = MaterialTheme.typography.bodySmall, color = colors.label2)
        }
        Row(Modifier.align(Alignment.TopStart).padding(4.dp).size(44.dp)) {
            ColumnButton(AppIcon.ChevronLeft, GamesRummyMatchText.leaveDescription, GamesRummyMatchTags.BACK, onExit)
        }
    }
}
