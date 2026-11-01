// 원본: Sources/CheckMobileKit/Games/GamesRummyMatchChrome.swift:1 @ ios-1017-cube 614d98bd · 맥 Sources/check/RummyPanelMatch.swift:842-1172 (버튼 · 자리 카드 · 판돈 · 더미) · Sources/check/RummyRackCues.swift:132,153 (배지 · [완료] 안 초) @ 1a5eeca6 · 설계서 §4
//
// 판 화면의 판 · 받침대 바깥 줄들 — 머리 줄 · 상대 줄 · 상태 줄 · 동작 줄 · 판 위 안내. 맥 위 띠 · 자리 카드 · 버튼을 세로로 옮겼다.
// 초 단위 값은 **잎**(링 · 초 글자)만 읽는다 — 화면이 매초 다시 조립되지 않게. 잎의 고리는 열쇠가 안 바뀌는 효과 하나다(재생성 고리 금지).
// 글자는 칸 높이가 정해져 있어 글자 배율을 칸마다 자른다(큰 글자에서 잘리지 않게) — [GamesRummyCappedText].
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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
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
import com.yehsung.aingcheck.ui.theme.AingDimens
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

// MARK: - 머리 줄

/** [나가기] · 판돈 · 더미 수 · [반응] · [규칙]. 44 칸 안에 든다. */
@Composable
internal fun GamesRummyMatchHeader(rummy: RummyStore, match: RummyMatchState, onExit: () -> Unit, onRules: () -> Unit, now: () -> SwiftDate, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    GamesRummyCappedText(1.3f) {
        Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            HeaderIcon(AppIcon.ChevronLeft, GamesRummyMatchText.leaveDescription, GamesRummyMatchTags.BACK, onExit)
            RubyIcon(rememberRubyArt(17f), size = 17.dp)
            Text(
                RummyPhoneText.matchPot(match.stake, match.seatCount),
                style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = TNUM),
                color = colors.label,
                maxLines = 1,
                softWrap = false,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
            Spacer(Modifier.weight(1f))
            GamesRummyTileBack(RummyCanvasSize(11.0, 15.0))
            Text(
                RummyPhoneText.pool(match.poolCount),
                style = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = TNUM),
                color = colors.label,
                maxLines = 1,
                softWrap = false,
                modifier = Modifier.semantics { contentDescription = "${RummyPhoneText.poolLabel} ${match.poolCount ?: 0}" },
            )
            GamesRummyReactionButton(rummy, now)
            HeaderIcon(AppIcon.Help, RummyPhoneText.rules, GamesRummyMatchTags.RULES, onRules)
        }
    }
}

@Composable
private fun HeaderIcon(icon: AppIcon, label: String, tag: String, onClick: () -> Unit) {
    Box(
        Modifier.size(AingDimens.minimumTarget).clickable(role = Role.Button, onClick = onClick).semantics { contentDescription = label }.testTag(tag),
        contentAlignment = Alignment.Center,
    ) {
        AingIcon(icon, contentDescription = null, size = 22.dp, tint = AingTheme.colors.label)
    }
}

// MARK: - 상대 줄

/** 상대를 내 다음 차례부터 가로로. **남의 패는 장수만** 보인다. */
@Composable
internal fun GamesRummyOpponentRow(rummy: RummyStore, match: RummyMatchState, now: () -> SwiftDate, modifier: Modifier = Modifier) {
    val anchors = LocalGamesRummyReactionAnchors.current
    GamesRummyCappedText(1.15f) {
        Row(modifier.padding(horizontal = 8.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (seat in GamesRummySeats.opponents(match)) {
                GamesRummySeatCard(rummy, match, seat, now, Modifier.weight(1f).fillMaxHeight().rummyReactionAnchor(anchors, seat.seatNo))
            }
        }
    }
}

@Composable
private fun GamesRummySeatCard(rummy: RummyStore, match: RummyMatchState, seat: RummyMatchSeat, now: () -> SwiftDate, modifier: Modifier) {
    val colors = AingTheme.colors
    val isTurn = GamesRummySeats.isTurn(seat, match)
    val tags = GamesRummySeats.tags(seat)
    val name = seat.displayName ?: "?"
    val shape = RoundedCornerShape(12.dp)
    val summary = GamesRummyMatchText.seatSummary(name, seat.rackCount, isTurn, tags.map { it.text })
    Row(
        modifier
            .alpha(if (GamesRummySeats.isGone(seat)) 0.5f else 1f)
            .clip(shape)
            .background(if (isTurn) colors.accentTint else colors.surface, shape)
            .border(if (isTurn) 1.5.dp else 0.8.dp, if (isTurn) colors.accent else colors.separator, shape)
            .clearAndSetSemantics { contentDescription = summary }
            .padding(horizontal = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(38.dp), contentAlignment = Alignment.Center) {
            if (isTurn) GamesRummyTurnRing(rummy, GamesRummySeats.turnTotal(match), now, Modifier.size(35.dp))
            BoardAvatar(name, seat.userId.lowercased, 30.dp, url = seat.avatarUrl, characterHint = seat.character)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.Center) {
            Text(
                name,
                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                color = colors.label,
                maxLines = 1,
                softWrap = false,
                overflow = TextOverflow.Ellipsis,
            )
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                GamesRummyTileBack(RummyCanvasSize(8.0, 11.0))
                Text(
                    RummyPhoneText.rackCount(seat.rackCount),
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, fontFeatureSettings = TNUM),
                    color = colors.label,
                    maxLines = 1,
                    softWrap = false,
                )
            }
            // 셋째 줄: 차례면 남은 초, 아니면 표시(폭 320 에서 카드 글자 칸이 좁아 한 줄에 다 못 싣는다).
            val tag = tags.firstOrNull()
            if (isTurn) {
                GamesRummySeatSeconds(rummy, now)
            } else if (tag != null) {
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

/** 코어 문구 한 줄 + 첫 등록 전 받침대 합. [plan] 이 null 이면 안 보인다. */
@Composable
internal fun GamesRummyStatusRow(line: GamesRummyStatusLine, plan: String?, planReached: Boolean, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val tint = when (line.tone) {
        GamesRummyStatusLine.Tone.notice -> colors.pending
        GamesRummyStatusLine.Tone.ready -> colors.working
        GamesRummyStatusLine.Tone.plain -> colors.label
        GamesRummyStatusLine.Tone.quiet -> colors.label2
    }
    GamesRummyCappedText(1.15f) {
        Row(modifier.padding(horizontal = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                line.text,
                style = MaterialTheme.typography.labelMedium,
                color = tint,
                maxLines = 1,
                softWrap = false,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f).testTag(GamesRummyMatchTags.STATUS),
            )
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

/** 첫 등록 전 합 글자 — 판 쪽은 내 차례에만 센다(남의 차례 판은 내 것이 아니다). 랙 묶음이 없으면 null. */
internal fun gamesRummyPlanLine(editor: RummyTurnEditor?, isMyTurn: Boolean): Pair<String, Boolean>? {
    val planned = editor?.initialPlanPoints ?: return null
    if (planned.rack <= 0) return null
    val table = if (isMyTurn) planned.table else 0
    return RummyPhoneText.plan(table, planned.rack) to (table + planned.rack >= 30)
}

// MARK: - 동작 줄

/** [완료(남은 초)] 가장 크게 · [뽑기|넘기기] · [되돌리기] · [777|789]. 큰 글자면 두 줄로 나눈다(GamesRummyMatchLayout.actionRowCount). [onSort] = 정렬(시차를 정하는 판 화면을 지난다). */
@Composable
internal fun GamesRummyActionRow(rummy: RummyStore, match: RummyMatchState, editor: RummyTurnEditor?, isMyTurn: Boolean, width: Double, textScale: Double, now: () -> SwiftDate, onSort: (RummyRackSort) -> Unit, modifier: Modifier = Modifier) {
    val canEdit = isMyTurn && !rummy.isWorking
    val poolEmpty = (match.poolCount ?: 0L) == 0L
    val gap = GamesRummyMatchLayout.actionGap.dp
    val height = GamesRummyMatchLayout.actionButtonHeight(textScale).dp
    val submitEnabled = canEdit && editor?.canSubmit == true
    val undoEnabled = canEdit && (editor?.isChanged == true || editor?.isLayoutChanged == true)
    GamesRummyCappedText(GamesRummyMatchLayout.maxActionTextScale.toFloat()) {
        if (GamesRummyMatchLayout.actionRowCount(textScale) == 1) {
            val widths = GamesRummyMatchLayout.actionWidths(width)
            Row(modifier.padding(horizontal = gap), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(gap)) {
                SubmitButton(rummy, isMyTurn, submitEnabled, now, Modifier.width(widths.submit.dp).height(height))
                DrawButton(rummy, poolEmpty, canEdit, Modifier.width(widths.draw.dp).height(height))
                UndoButton(rummy, undoEnabled, Modifier.width(widths.undo.dp).height(height))
                SortButtons(rummy, editor != null, onSort, Modifier.width(widths.sort.dp).height(height))
            }
        } else {
            Column(modifier.padding(horizontal = gap), verticalArrangement = Arrangement.spacedBy(gap, Alignment.CenterVertically)) {
                SubmitButton(rummy, isMyTurn, submitEnabled, now, Modifier.fillMaxWidth().height(height))
                Row(Modifier.fillMaxWidth().height(height), horizontalArrangement = Arrangement.spacedBy(gap)) {
                    DrawButton(rummy, poolEmpty, canEdit, Modifier.weight(1f).fillMaxHeight())
                    UndoButton(rummy, undoEnabled, Modifier.weight(1f).fillMaxHeight())
                    SortButtons(rummy, editor != null, onSort, Modifier.weight(1f).fillMaxHeight())
                }
            }
        }
    }
}

/** 꺼져도 남은 초는 또렷해야 한다 — 전체를 흐리게 하지 않고 색만 바꾼다(꺼진 동안에도 시간은 간다). */
@Composable
private fun SubmitButton(rummy: RummyStore, isMyTurn: Boolean, enabled: Boolean, now: () -> SwiftDate, modifier: Modifier) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(12.dp)
    val ink = if (enabled) colors.onAccentFill else colors.label3Text
    Row(
        modifier
            .clip(shape)
            .background(if (enabled) colors.accentFill else colors.fill, shape)
            .clickable(enabled = enabled, role = Role.Button) { rummy.submitTurn() }
            .testTag(GamesRummyMatchTags.SUBMIT),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp, Alignment.CenterHorizontally),
    ) {
        AingIcon(AppIcon.Check, contentDescription = null, size = 15.dp, tint = ink)
        Text(RummyPhoneText.submit, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Black), color = ink, maxLines = 1, softWrap = false)
        if (isMyTurn) GamesRummySubmitSeconds(rummy, enabled, now)
    }
}

/** [완료] 안 남은 초(10초 이하 주황 · 5초 이하 빨강). */
@Composable
private fun GamesRummySubmitSeconds(rummy: RummyStore, enabled: Boolean, now: () -> SwiftDate) {
    val remaining by rememberTurnRemaining(rummy, now, 500L)
    val left = remaining ?: return
    val seconds = wholeSeconds(left)
    Box(
        Modifier
            .background(countdownTint(left) ?: Color.Black.copy(alpha = if (enabled) 0.28f else 0.5f), CircleShape)
            .padding(horizontal = 6.dp, vertical = 2.dp)
            .semantics { contentDescription = GamesRummyMatchText.remaining(seconds) },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            RummyPhoneText.seconds(seconds),
            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black, fontFeatureSettings = TNUM),
            color = Color.White,
            maxLines = 1,
            softWrap = false,
        )
    }
}

@Composable
private fun DrawButton(rummy: RummyStore, poolEmpty: Boolean, enabled: Boolean, modifier: Modifier) {
    SecondaryButton(
        if (poolEmpty) RummyPhoneText.pass else RummyPhoneText.draw,
        if (poolEmpty) AppIcon.ArrowRightFill else AppIcon.FilterNone,
        enabled,
        GamesRummyMatchTags.DRAW,
        modifier,
    ) { rummy.drawTile() }
}

@Composable
private fun UndoButton(rummy: RummyStore, enabled: Boolean, modifier: Modifier) {
    SecondaryButton(RummyPhoneText.undo, AppIcon.Undo, enabled, GamesRummyMatchTags.UNDO, modifier) { rummy.resetTurn() }
}

@Composable
private fun SecondaryButton(title: String, icon: AppIcon, enabled: Boolean, tag: String, modifier: Modifier, onClick: () -> Unit) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(12.dp)
    val ink = if (enabled) colors.label else colors.label3Text
    Column(
        modifier
            .clip(shape)
            .background(colors.surface, shape)
            .border(0.8.dp, colors.separator, shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .testTag(tag),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(1.dp, Alignment.CenterVertically),
    ) {
        AingIcon(icon, contentDescription = null, size = 15.dp, tint = ink)
        Text(title, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = ink, maxLines = 1, softWrap = false)
    }
}

@Composable
private fun SortButtons(rummy: RummyStore, enabled: Boolean, onSort: (RummyRackSort) -> Unit, modifier: Modifier) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(12.dp)
    val selected = rummy.rackSortMode
    Row(
        modifier
            .alpha(if (enabled) 1f else 0.45f)
            .clip(shape)
            .background(colors.surface, shape)
            .border(0.8.dp, colors.separator, shape)
            .padding(2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SortSegment(onSort, RummyRackSort.number, RummyPhoneText.sortNumber, GamesRummyMatchText.sortNumberName, selected == RummyRackSort.number, enabled, GamesRummyMatchTags.SORT_NUMBER)
        Box(Modifier.width(0.8.dp).fillMaxHeight().padding(vertical = 8.dp).background(colors.separator))
        SortSegment(onSort, RummyRackSort.color, RummyPhoneText.sortColor, GamesRummyMatchText.sortColorName, selected == RummyRackSort.color, enabled, GamesRummyMatchTags.SORT_COLOR)
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
            .clip(shape)
            .background(if (on) colors.accentFill else Color.Transparent, shape)
            .clickable(enabled = enabled, role = Role.Button) { onSort(mode) }
            .semantics { contentDescription = name }
            .testTag(tag),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title,
            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black, fontFeatureSettings = TNUM),
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

/** 판 아래쪽 한 줄 — 직전 사건 · 남의 차례(작업 중이면 '놓는 중'). 손을 안 받는다. */
@Composable
internal fun GamesRummyTableStrip(match: RummyMatchState, isMyTurn: Boolean, hasOtherDraft: Boolean, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val turn = GamesRummySeats.turnSeat(match)
    val event = match.lastEvent
    val last = RummyPhoneText.lastEvent(event, match.seats?.firstOrNull { it.seatNo == event?.seatNo }?.displayName)
    GamesRummyCappedText(1.15f) {
        Row(modifier.padding(8.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (last != null) {
                Text(
                    last,
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White.copy(alpha = 0.92f),
                    maxLines = 1,
                    softWrap = false,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false).background(Color.Black.copy(alpha = 0.5f), CircleShape).padding(horizontal = 9.dp, vertical = 4.dp),
                )
            }
            Spacer(Modifier.weight(1f))
            val name = turn?.displayName
            if (!isMyTurn && name != null) {
                Row(
                    Modifier.background(colors.accentFill, CircleShape).padding(horizontal = 9.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    AingIcon(if (hasOtherDraft) AppIcon.TouchAppFill else AppIcon.HourglassEmpty, contentDescription = null, size = 13.dp, tint = colors.onAccentFill)
                    Text(
                        if (hasOtherDraft) RummyPhoneText.placing(name) else RummyPhoneText.turnOf(name),
                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                        color = colors.onAccentFill,
                        maxLines = 1,
                        softWrap = false,
                    )
                }
            }
        }
    }
}

/** 다른 기기 판 안내 — 읽기만 하는 동안. **입력은 막지 않는다**(맥과 같다 — 여기서 타일을 옮기면 이 폰에서 이어 한다). */
@Composable
internal fun GamesRummyElsewhereCard(modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(12.dp)
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
