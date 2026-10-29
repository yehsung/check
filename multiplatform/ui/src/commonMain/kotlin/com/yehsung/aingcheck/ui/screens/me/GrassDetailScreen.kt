// 원본: Sources/CheckMobileKit/Me/MeGrassDetailView.swift @ 3bd04bd (잔디 상세 — 칸을 탭하면 아래 고정 막대에 그 날 값)
// 원본: Sources/CheckMobileKit/Components/MobileComponentModels.swift:249-335 @ 3bd04bd (ContributionCalendarLayout · MeGrassSelection — 화면 판정 몫)
//
// "맥에서 커서 올리면 상세 값 뜨는 것처럼, 폰에서는 칸을 탭하면 값이 뜬다"(0.3.31 사용자 요구). 값 문구 · 날짜 표기 · 분모 · 단계 규칙은 맥과 같다
// (MeText.grassValueLine · grassDetailDate — W2-c). 다른 것은 값이 서는 자리뿐: 손가락이 칸을 덮으므로 값은 화면 **아래 고정 막대**에 선다.
// 격자는 전치한다(홈은 가로 13열, 여기는 세로 13행) — 가로 13열이면 칸이 어떤 폭에서도 44 에 못 닿는다(전치하면 360 폭에서도 피치 ≈ 47).
// 상태(축 · 고른 칸)는 **이 화면의 저장 상태**다 — 스토어는 한 글자도 안 바꾼다. 큰 글자 목록 모드(iOS AX)·칸별 접근성 요소는 이번 판에 옮기지 않았다(보고).
package com.yehsung.aingcheck.ui.screens.me

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.insights.KstCalendar
import com.yehsung.aingcheck.core.rules.insights.TokenDailyGrid
import com.yehsung.aingcheck.core.rules.insights.WorkDailyGrid
import com.yehsung.aingcheck.core.rules.insights.WorkRhythmHeatmap
import com.yehsung.aingcheck.core.stores.me.MeGrassAxis
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.loadRecords
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.components.ContributionAxis
import com.yehsung.aingcheck.ui.components.ContributionLevels
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlin.math.max

/** 고른 칸(주 · 요일 0=월). */
data class GrassCell(val week: Int, val weekday: Int)

/** 달 묶음(머리 "9월" + 그 달에 일요일이 든 주들). */
data class GrassMonthSection(val month: Int, val weeks: IntRange)

/** 잔디 상세 판정(순수 — Swift ContributionCalendarLayout · MeGrassSelection). */
object GrassDetailRules {
    const val COLUMNS = WorkRhythmHeatmap.DAY_COUNT
    const val SPACING = 4f
    const val MINIMUM_PITCH = 44f

    fun pitch(width: Float): Float = if (width > 0) width / COLUMNS else 0f
    fun cell(width: Float): Float = max(0f, pitch(width) - SPACING)

    /** 가로 위치 → 요일(칸 밖이면 null). */
    fun weekday(x: Float, width: Float): Int? {
        val p = pitch(width)
        if (p <= 0 || x < 0 || x >= p * COLUMNS) return null
        return minOf(COLUMNS - 1, (x / p).toInt())
    }

    /** [cell] 에서 [days] 일 옮긴 칸. 창 밖이거나 미래(오프셋 ≥ dayCount)면 null → 단추 비활성. */
    fun stepped(cell: GrassCell, days: Int, weeks: Int, dayCount: Int): GrassCell? {
        val offset = cell.week * COLUMNS + cell.weekday + days
        if (offset < 0 || offset >= weeks * COLUMNS || offset >= dayCount) return null
        return GrassCell(offset / COLUMNS, offset % COLUMNS)
    }

    /** 화면을 열 때 미리 고를 칸 = 마지막 유효 칸(오늘). 날이 없으면 null. */
    fun latest(weeks: Int, dayCount: Int): GrassCell? {
        if (weeks <= 0 || dayCount <= 0) return null
        val offset = minOf(dayCount, weeks * COLUMNS) - 1
        return GrassCell(offset / COLUMNS, offset % COLUMNS)
    }

    /** 주 → 달 묶음(그 주의 **일요일**이 든 달 — Swift monthSections). */
    fun monthSections(weekStart: Double, weeks: Int): List<GrassMonthSection> {
        if (weeks <= 0 || !weekStart.isFinite()) return emptyList()
        val out = mutableListOf<GrassMonthSection>()
        for (week in 0 until weeks) {
            val sunday = KstCalendar.localDate(KstCalendar.addDays(weekStart, week * COLUMNS + COLUMNS - 1))
            val month = sunday.month.ordinal + 1
            val last = out.lastOrNull()
            if (last != null && last.month == month) out[out.lastIndex] = GrassMonthSection(month, last.weeks.first..week)
            else out += GrassMonthSection(month, week..week)
        }
        return out
    }

    /** 칸 단계(null = 미래 칸). */
    fun level(axis: MeGrassAxis, work: WorkDailyGrid, token: TokenDailyGrid, week: Int, weekday: Int): Int? = when (axis) {
        MeGrassAxis.work -> if (work.isFuture(week, weekday)) null else MeText.gridLevel(work.seconds[week][weekday], WorkDailyGrid.fullDaySeconds.toLong())
        MeGrassAxis.token -> if (token.isFuture(week, weekday) || week >= token.weeks) null else MeText.gridLevel(token.tokens[week][weekday], TokenDailyGrid.fullDayTokens)
    }

    /** 막대 값 줄의 구절(근무 · 토큰). 글자는 MeText.grassValueLine 한 곳에서 만든다 — 토큰 구절은 전체 줄에서 근무 구절을 뗀 나머지. */
    fun valueParts(workSeconds: Long, tokens: Long, showsToken: Boolean): List<String> {
        val workOnly = MeText.grassValueLine(workSeconds, 0L, false)
        if (!showsToken) return listOf(workOnly)
        val full = MeText.grassValueLine(workSeconds, tokens, true)
        val prefix = "$workOnly · "
        return if (full.startsWith(prefix)) listOf(workOnly, full.removePrefix(prefix)) else listOf(full)
    }

    /** 두 잔디의 창이 어긋나면(한쪽이 비었거나 주가 넘어가는 중) 토큰 값을 말하지 않는다 — 하루 밀린 값을 말하는 것보다 낫다. */
    fun tokenUsable(showsTokenGrid: Boolean, work: WorkDailyGrid, token: TokenDailyGrid): Boolean =
        showsTokenGrid && token.weeks == work.weeks && token.weekStart == work.weekStart
}

/** 막대 빈 줄 글자(Swift ContributionGridText — 이 화면 몫만). */
object GrassDetailText {
    const val empty = "최근 12주 기록이 없어요"

    fun emptyBar(phase: MeRecordsPhase): String = when (phase) {
        MeRecordsPhase.Loading -> MeText.loading
        MeRecordsPhase.Failed -> MeText.recordsFailed
        MeRecordsPhase.Ready -> empty
    }
}

object GrassDetailTags {
    const val VALUE_BAR = "grass-value-bar"
    const val GRID = "grass-grid"
    const val STEP_BACK = "grass-step-back"
    const val STEP_FORWARD = "grass-step-forward"
    fun row(week: Int) = "grass-row:$week"
}

/**
 * 잔디 상세. [initialAxis] 는 연 칸(근무 · 토큰). 축·고른 칸은 저장 상태라 프로세스 죽음 뒤에도 돌아온다.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun GrassDetailScreen(store: MeStore, initialAxis: MeGrassAxis, scope: CoroutineScope, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    var axisRaw by rememberSaveable { mutableStateOf(initialAxis.name) }
    val axis = if (store.showsTokenGrid) MeGrassAxis.valueOf(axisRaw) else MeGrassAxis.work
    val loaded = store.recordsState.hasLoaded
    val work = store.dailyGrid
    val token = store.tokenGrid
    val phase = MeHomeRules.recordsPhase(store.recordsState)
    // 첫 프레임부터 오늘에 링이 서 있다(들어오자마자 막대에 값 — 안내 문구 없이 "누르면 값이 나온다"를 가르친다).
    val opening = GrassDetailRules.latest(work.weeks, work.days)
    var selWeek by rememberSaveable { mutableStateOf(opening?.week ?: -1) }
    var selDay by rememberSaveable { mutableStateOf(opening?.weekday ?: -1) }
    var selectedWindow by rememberSaveable { mutableStateOf(work.weekStart) }
    // 낡은 선택 가드: 주가 넘어가면 같은 (주, 요일)이 다른 날을 가리킨다 — 창이 바뀌면 오늘로 다시 고른다(저장 상태로 복원된 같은 창은 그대로).
    LaunchedEffect(work.weekStart, work.days) {
        if (selectedWindow == work.weekStart && selWeek in 0 until work.weeks) return@LaunchedEffect
        val latest = GrassDetailRules.latest(work.weeks, work.days)
        selWeek = latest?.week ?: -1
        selDay = latest?.weekday ?: -1
        selectedWindow = work.weekStart
    }
    val selection = if (selWeek >= 0 && selDay >= 0) GrassCell(selWeek, selDay) else null
    val tokenUsable = GrassDetailRules.tokenUsable(store.showsTokenGrid, work, token)

    Column(modifier.background(colors.background)) {
        Column(Modifier.fillMaxWidth().padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.space2), verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
            if (store.showsTokenGrid) {
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    listOf(MeGrassAxis.work to MeText.grassAxisWork, MeGrassAxis.token to MeText.grassAxisToken).forEachIndexed { index, (value, title) ->
                        SegmentedButton(selected = axis == value, onClick = { axisRaw = value.name }, shape = SegmentedButtonDefaults.itemShape(index, 2), icon = {}) { Text(title) }
                    }
                }
            }
            Row(Modifier.fillMaxWidth()) {
                MeText.dayNames.forEach { day ->
                    Text(day, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = colors.label2, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
                }
            }
        }
        // 들어오자마자 가장 궁금한 최근 주가 보인다(Swift defaultScrollAnchor(.bottom) — 처음 값이 최대면 배치가 끝 값으로 당긴다).
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState(Int.MAX_VALUE)).padding(horizontal = AingDimens.sideMargin).testTag(GrassDetailTags.GRID)) {
            if (loaded && work.weeks > 0) {
                GrassDetailRules.monthSections(work.weekStart, work.weeks).forEach { section ->
                    Text("${section.month}월", style = MaterialTheme.typography.labelMedium, color = colors.label2, modifier = Modifier.padding(vertical = 4.dp))
                    for (week in section.weeks) {
                        GrassWeekRow(
                            week = week,
                            levels = List(GrassDetailRules.COLUMNS) { d -> GrassDetailRules.level(axis, work, token, week, d) },
                            axis = axis,
                            selectedWeekday = if (selection?.week == week) selection.weekday else null,
                            label = MeText.grassWeekAccessibility(SwiftDate(work.weekStart), week),
                            onSelect = { d ->
                                // 미래 칸 탭은 선택을 유지한다(고정 막대가 비면 조준점이 흔들린다 — 맥이 미래 칸 호버를 무시하는 것과 같은 규칙).
                                if (GrassDetailRules.level(MeGrassAxis.work, work, token, week, d) != null) {
                                    selWeek = week
                                    selDay = d
                                }
                            },
                        )
                    }
                }
            }
            Text(MeText.grassScale(axis), style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = colors.label2, modifier = Modifier.padding(vertical = AingDimens.space3))
        }
        // 아래 고정 막대: [하루 전] 날짜 · 값 [하루 뒤].
        Row(
            Modifier.fillMaxWidth().background(colors.surface).padding(horizontal = AingDimens.space2, vertical = AingDimens.space2).testTag(GrassDetailTags.VALUE_BAR),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val back = selection?.let { GrassDetailRules.stepped(it, -1, work.weeks, work.days) }
            val forward = selection?.let { GrassDetailRules.stepped(it, 1, work.weeks, work.days) }
            IconButton(onClick = { back?.let { selWeek = it.week; selDay = it.weekday } }, enabled = back != null, modifier = Modifier.testTag(GrassDetailTags.STEP_BACK)) {
                AingIcon(AppIcon.ChevronLeft, contentDescription = MeText.grassStepBack, tint = if (back != null) colors.accent else colors.label3)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                // 저장 상태로 돌아온 칸이 지금 창 밖이면(창이 줄었다) 값을 말하지 않는다 — 다음 프레임에 오늘로 다시 고른다.
                if (selection != null && phase == MeRecordsPhase.Ready && work.weekStart.isFinite() && selection.week < work.weeks && selection.week < work.seconds.size) {
                    Text(MeText.grassDetailDate(SwiftDate(work.weekStart), selection.week, selection.weekday), style = MaterialTheme.typography.labelMedium, color = colors.label2)
                    // 값 줄은 구절 단위로 접는다(근무 · AI 토큰) — 글자 단위로 접으면 "토/큰"처럼 낱말이 갈린다.
                    val parts = GrassDetailRules.valueParts(work.seconds[selection.week][selection.weekday], if (tokenUsable) token.tokens[selection.week][selection.weekday] else 0L, tokenUsable)
                    FlowRow {
                        parts.forEachIndexed { index, part ->
                            Text(
                                if (index < parts.lastIndex) "$part · " else part,
                                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                                color = colors.label,
                                softWrap = false,
                            )
                        }
                    }
                } else {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(GrassDetailText.emptyBar(phase), style = MaterialTheme.typography.bodyMedium, color = colors.label2)
                        if (phase == MeRecordsPhase.Failed) TextButton(onClick = { scope.launch { store.loadRecords() } }) { Text(MeText.retry) }
                    }
                }
            }
            IconButton(onClick = { forward?.let { selWeek = it.week; selDay = it.weekday } }, enabled = forward != null, modifier = Modifier.testTag(GrassDetailTags.STEP_FORWARD)) {
                AingIcon(AppIcon.ChevronRight, contentDescription = MeText.grassStepForward, tint = if (forward != null) colors.accent else colors.label3)
            }
        }
    }
}

/** 주 한 줄(요일 7칸). 고른 칸은 글자색 2 링 + 바탕색 안쪽 링, 고른 줄은 옅은 받침. */
@Composable
private fun GrassWeekRow(week: Int, levels: List<Int?>, axis: MeGrassAxis, selectedWeekday: Int?, label: String, onSelect: (Int) -> Unit) {
    val colors = AingTheme.colors
    val tint = (if (axis == MeGrassAxis.token) ContributionAxis.Token else ContributionAxis.Work).tint(colors)
    // 탭 판정은 pointerInput 키(주 · 폭) 밖에서 바뀌는 최신 콜백을 불러야 한다(창이 넘어가면 콜백이 새 격자를 본다).
    val select by rememberUpdatedState(onSelect)
    BoxWithConstraints(Modifier.fillMaxWidth().testTag(GrassDetailTags.row(week)).semantics { contentDescription = label }) {
        val width = maxWidth.value
        val pitchDp = GrassDetailRules.pitch(width)
        Canvas(
            Modifier
                .fillMaxWidth()
                .height(pitchDp.dp)
                .pointerInput(week, width) {
                    detectTapGestures { offset -> GrassDetailRules.weekday(offset.x / density, width)?.let(select) }
                },
        ) {
            val p = pitchDp * density
            val c = max(0f, p - GrassDetailRules.SPACING * density)
            val radius = CornerRadius(max(2f * density, c * 0.22f))
            if (selectedWeekday != null) drawRoundRect(colors.fill2, Offset.Zero, size, radius)
            for (d in 0 until GrassDetailRules.COLUMNS) {
                val topLeft = Offset(d * p, 0f)
                val level = levels[d]
                when {
                    level == null -> drawRoundRect(colors.separator, topLeft + Offset(0.5f, 0.5f), Size(c - 1f, c - 1f), radius, style = Stroke(1f * density))
                    level <= 0 -> drawRoundRect(colors.fill, topLeft, Size(c, c), radius)
                    else -> drawRoundRect(tint.copy(alpha = tint.alpha * ContributionLevels.opacity(level)), topLeft, Size(c, c), radius)
                }
                if (d == selectedWeekday) {
                    drawRoundRect(colors.label, topLeft + Offset(1f * density, 1f * density), Size(c - 2f * density, c - 2f * density), radius, style = Stroke(2f * density))
                    drawRoundRect(colors.background, topLeft + Offset(3f * density, 3f * density), Size(c - 6f * density, c - 6f * density), radius, style = Stroke(1.5f * density))
                }
            }
        }
    }
}

/** 스크롤 칸 너비 등 치수 노출(시험이 피치 ≥ 44 를 잰다). */
object GrassDetailMetrics {
    fun pitchAt(screenWidthDp: Float): Float = GrassDetailRules.pitch(screenWidthDp - AingDimens.sideMargin.value * 2)
}
