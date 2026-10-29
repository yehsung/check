// 원본: Sources/CheckMobileKit/Me/MeTab.swift @ 3bd04bd (MeHomeView · MeStageCard · MeMenuGroup · MeMenuRowContent)
// 원본: Sources/CheckMobileKit/Me/MeRecordsViews.swift @ 3bd04bd (MeRecordsCard · MeGrassCard · MeRhythmSection · MeRhythmGrid)
// 원본: Sources/CheckMobileKit/Me/MeMissionsView.swift:40-100 @ 3bd04bd (MeMissionsRow — 루트 [미션] 줄. 미션 화면 본문은 W4-c ui/missions)
//
// 나 탭 루트(SPEC-ios §3.6 · w15): **무대**(착용 캐릭터 · 이름 · 팀 · 센터 · 큰 루비 칩 · 근무 상태 · [캐릭터 바꾸기][상점]) → [미션] 줄 →
// **기록**(지난주 회고 + 근무 리듬) → **잔디**(12주 근무 · AI 토큰) → **AI 리밋** → 프로필 · 제보 · 설정 그룹.
// 하위 화면은 [open] 으로 연다(조립 K11 — Android 는 NavController, 데스크톱은 페이지). 화면은 판정을 품지 않는다(MeHomeRules).
// 무대 왼쪽 칸은 [MeStageContent] 자리다(W5-c 살아 있는 미리보기가 채운다 — MeStageSlot).
package com.yehsung.aingcheck.ui.screens.me

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.insights.WorkRhythmHeatmap
import com.yehsung.aingcheck.core.rules.insights.WorkDailyGrid
import com.yehsung.aingcheck.core.stores.me.MeDestination
import com.yehsung.aingcheck.core.stores.me.MeGrassAxis
import com.yehsung.aingcheck.core.stores.me.MeStageMood
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.equippedCharacterID
import com.yehsung.aingcheck.core.stores.me.hasUnseenFeedbackReply
import com.yehsung.aingcheck.core.stores.me.loadRecords
import com.yehsung.aingcheck.core.stores.me.missionClaimableCount
import com.yehsung.aingcheck.core.stores.me.retroForDisplay
import com.yehsung.aingcheck.core.stores.me.showsMissionsRow
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.ContributionAxis
import com.yehsung.aingcheck.ui.components.ContributionGridCanvas
import com.yehsung.aingcheck.ui.components.ContributionLevels
import com.yehsung.aingcheck.ui.components.RubyBalanceChip
import com.yehsung.aingcheck.ui.components.RubyChipStyle
import com.yehsung.aingcheck.ui.components.dotColor
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.settingscommon.AingChipLabel
import com.yehsung.aingcheck.ui.screens.settingscommon.CenterBadge
import com.yehsung.aingcheck.ui.screens.settingscommon.GroupRow
import com.yehsung.aingcheck.ui.screens.settingscommon.InsetGroup
import com.yehsung.aingcheck.ui.screens.settingscommon.LargeTitle
import com.yehsung.aingcheck.ui.screens.settingscommon.LoadFailureRow
import com.yehsung.aingcheck.ui.screens.settingscommon.LocalScreenArt
import com.yehsung.aingcheck.ui.screens.settingscommon.RowDivider
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlin.math.max

/**
 * 나 탭 루트.
 * @param presence 내 근무 상태(MeHomeRules.presence — 지금 탭 내 카드 → 위젯 스냅숏 → null). 조립이 NowStore 에서 넘긴다.
 * @param stage 무대 자리(기본 정지 초상 — W5-c 가 살아 있는 미리보기로 바꾼다).
 * @param open 하위 화면 열기(Swift `router.push(_, on: .me)`).
 * @param scope 다시 시도·당겨서 새로고침이 띄우는 자리(화면 수명 스코프 — rememberCoroutineScope).
 * @param cakeGiftRow 생일 선물 '다시 열기' 줄 자리(W4-c 몫 — 무대 바로 아래).
 */
@Composable
fun MeHomeScreen(
    store: MeStore,
    presence: MeStageMood?,
    open: (MeDestination) -> Unit,
    scope: CoroutineScope,
    modifier: Modifier = Modifier,
    stage: MeStageContent = MeStageDefaults.Static,
    cakeGiftRow: @Composable () -> Unit = {},
    scrollable: Boolean = true,
) {
    val colors = AingTheme.colors
    val scroll = if (scrollable) Modifier.verticalScroll(rememberScrollState()) else Modifier
    Column(
        modifier
            .background(colors.background)
            .then(scroll)
            .padding(horizontal = AingDimens.sideMargin)
            .padding(top = AingDimens.space1, bottom = AingDimens.space6),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
    ) {
        LargeTitle(MeScreenText.tabTitle) {
            IconButton(onClick = { open(MeDestination.Settings) }) {
                AingIcon(AppIcon.Settings, contentDescription = MeText.settingsTitle, tint = colors.label)
            }
        }
        MeStageCard(store, MeHomeRules.characterMood(presence), stage, open, scope, Modifier.testTag(MeAnchor.Header.tag))
        cakeGiftRow()
        // INV-MeTab-1dd608f6 이식: 1.0.13 「일일 미션」 절은 **여기 두지 않는다**("나 탭에 미션들 쭈루룩 다 나열하니까 칸이 너무 길어져 —
        //   미션 창 버튼 두고 그거 누르면 미션 페이지 따로" 사용자 지시). 루트에는 [미션] 줄 하나만 남고, 받을 것은 줄의 배지가 말한다
        //   (missionClaimableCount = 일일 + 누적 + 주간). 자리는 [미션] 화면 안(W4-c), 맥 0.3.64 와 같은 일일 → 주간 → 누적 순서다.
        if (store.showsMissionsRow) MeMissionsRow(store.missionClaimableCount, onOpen = { open(MeDestination.Missions) }, modifier = Modifier.testTag(MeAnchor.Missions.tag))
        MeRecordsCard(store, scope, Modifier.testTag(MeAnchor.Records.tag))
        MeGrassCard(store, open, scope, Modifier.testTag(MeAnchor.TokenGrass.tag))
        MeAILimitsCard(store.aiLimits, MeText.retry, onRetry = { scope.launch { store.aiLimits.load() } }, modifier = Modifier.testTag(MeAnchor.AILimits.tag))
        MeMenuGroup(MeHomeRules.menuRows(store.hasUnseenFeedbackReply), open, Modifier.testTag(MeAnchor.Menu.tag))
    }
}

// ---------------------------------------------------------------- 무대

/** 무대 카드: [무대 자리][이름 · 팀+센터 · 큰 루비 칩 · 상태 줄] → (머리 실패면 다시 시도) → [캐릭터 바꾸기][상점]. */
@Composable
internal fun MeStageCard(store: MeStore, mood: CharacterMood?, stage: MeStageContent, open: (MeDestination) -> Unit, scope: CoroutineScope, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val spec = MeStageSpec(characterId = store.equippedCharacterID, mood = mood)
    Column(
        modifier
            .fillMaxWidth()
            .background(colors.surface, RoundedCornerShape(AingDimens.groupRadius))
            .padding(start = AingDimens.cardPadding, end = AingDimens.cardPadding, bottom = AingDimens.cardPadding, top = AingDimens.space2),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
            // 자리 크기는 계약(MeStageSpec)이 정한다 — 내용(정지 초상 · 살아 있는 미리보기)이 무엇이든 옆 배치가 흔들리지 않는다.
            stage(spec, Modifier.size(spec.slotWidth, spec.slotHeight).testTag(MeStageTags.SLOT))
            MeStageIdentity(store, mood, open, Modifier.weight(1f))
        }
        if (MeHomeRules.showsHeaderRetry(store.headerState)) {
            LoadFailureRow(MeText.headerLoadFailed, MeText.retry, isRetrying = store.headerState.isLoading) { scope.launch { store.loadHeader() } }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
            FilledTonalButton(onClick = { open(MeDestination.Characters) }, modifier = Modifier.weight(1f)) {
                AingIcon(AppIcon.AccountBox, contentDescription = null, size = 18.dp)
                Spacer(Modifier.width(6.dp))
                Text(MeText.changeCharacter, maxLines = 1)
            }
            FilledTonalButton(onClick = { open(MeDestination.Shop) }, modifier = Modifier.weight(1f)) {
                AingIcon(AppIcon.ShoppingBag, contentDescription = null, size = 18.dp)
                Spacer(Modifier.width(6.dp))
                Text(MeText.shopTitle, maxLines = 1)
            }
        }
    }
}

object MeStageTags {
    const val SLOT = "me-stage-slot"
}

@Composable
private fun MeStageIdentity(store: MeStore, mood: CharacterMood?, open: (MeDestination) -> Unit, modifier: Modifier) {
    val colors = AingTheme.colors
    val email = store.context.sessionStore.profile?.email
    val name = MeHomeRules.identityName(store.displayName, store.headerState.hasLoaded, email)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Text(name, style = MaterialTheme.typography.headlineMedium, color = colors.label, maxLines = 2)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(store.teamName ?: MeText.noTeam, style = MaterialTheme.typography.bodyMedium, color = colors.label2, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
            CenterBadge(store.centerServerValue)
        }
        RubyBalanceChip(
            count = store.rubyBalance?.toInt(),
            art = LocalScreenArt.current.ruby(RubyChipStyle.Large.gem.value),
            style = RubyChipStyle.Large,
            onClick = { open(MeDestination.Shop) },
        )
        MeStatusLine(store, mood)
    }
}

/** "● 근무 중 · 여우 착용 중". 착용값을 모르면 불러오는 중 · 실패 문구(실패는 주의색). */
@Composable
private fun MeStatusLine(store: MeStore, mood: CharacterMood?) {
    val colors = AingTheme.colors
    val (wear, kind) = MeHomeRules.wearLine(store.equippedLoaded, store.equippedLoadFailed, store.equippedCharacterID)
    val status = mood?.let { MeText.stageStatus(it.toStageMood()) }
    val statusColor = when (mood) {
        CharacterMood.Working -> colors.working
        CharacterMood.Lost -> colors.pending
        CharacterMood.Off -> colors.offWork
        CharacterMood.Plain, null -> colors.label2
    }
    val wearColor = if (kind == MeWearKind.Failed) colors.pending else colors.label2
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        val ring = mood?.ring
        if (ring != null) Box(Modifier.size(7.dp).background(ring.dotColor(colors), CircleShape))
        Text(
            buildAnnotatedString {
                if (status != null) {
                    withStyle(SpanStyle(color = statusColor, fontWeight = FontWeight.SemiBold)) { append(status) }
                    withStyle(SpanStyle(color = colors.label2)) { append(" · ") }
                }
                withStyle(SpanStyle(color = wearColor)) { append(wear) }
            },
            style = MaterialTheme.typography.bodySmall,
        )
    }
}

private fun CharacterMood.toStageMood(): MeStageMood = when (this) {
    CharacterMood.Working -> MeStageMood.working
    CharacterMood.Lost -> MeStageMood.lost
    CharacterMood.Off -> MeStageMood.off
    CharacterMood.Plain -> MeStageMood.plain
}

// ---------------------------------------------------------------- [미션] 줄

/** 루트 [미션] 줄 — 타일(체크리스트 · 강조색) · 제목 · 배지 또는 보조 글자 · ›. 받을 것이 있다는 사실(배지)은 큰 글자에서도 버리지 않는다. */
@Composable
internal fun MeMissionsRow(claimableCount: Int, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val (trailing, isBadge) = MeHomeRules.missionsTrailing(claimableCount)
    InsetGroup(modifier) {
        GroupRow(divider = RowDivider.None, minHeight = 50.dp, onClick = onOpen) {
            MenuTile(AppIcon.Checklist, colors.accentFill)
            Text(MeText.missionsPageTitle, style = MaterialTheme.typography.bodyLarge, color = colors.label, modifier = Modifier.weight(1f))
            if (isBadge) ReplyBadge(trailing) else Text(trailing, style = MaterialTheme.typography.bodyMedium, color = colors.label2, maxLines = 1)
            AingIcon(AppIcon.ChevronRight, contentDescription = null, size = 16.dp, tint = colors.label3)
        }
    }
}

@Composable
private fun MenuTile(icon: AppIcon, background: androidx.compose.ui.graphics.Color) {
    Box(Modifier.size(30.dp).background(background, RoundedCornerShape(7.dp)), contentAlignment = Alignment.Center) {
        AingIcon(icon, contentDescription = null, size = 18.dp, tint = AingTheme.colors.onAccentFill)
    }
}

@Composable
private fun ReplyBadge(text: String) {
    val colors = AingTheme.colors
    Box(Modifier.background(colors.accentFill, CircleShape).heightIn(min = 20.dp).padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
        Text(text, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = colors.onAccentFill, maxLines = 1)
    }
}

// ---------------------------------------------------------------- 기록(지난주 회고 + 리듬)

@Composable
internal fun MeRecordsCard(store: MeStore, scope: CoroutineScope, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val state = store.recordsState
    val retro = if (state.hasLoaded) store.retroForDisplay else null
    val phase = MeHomeRules.recordsPhase(state)
    Column(
        modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(AingDimens.groupRadius)).padding(AingDimens.cardPadding),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(MeText.retroTitle, style = MaterialTheme.typography.titleMedium, color = colors.label, modifier = Modifier.weight(1f).semantics { heading() })
                if (retro != null) {
                    if (retro.metGoal) AingChipLabel(MeText.retroChip(retro), tint = colors.working)
                    else AingChipLabel(MeText.retroChip(retro), tint = colors.label2, background = colors.fill)
                }
            }
            if (retro != null) {
                Text(MeText.retroHeadline(retro), style = MaterialTheme.typography.headlineSmall, color = colors.label, modifier = Modifier.padding(top = 2.dp))
                Text(MeText.retroSummaryLine(retro), style = MaterialTheme.typography.bodySmall, color = colors.label2)
            } else if (state.hasLoaded) {
                Text(MeText.noRetro, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(colors.separator))
        Column(Modifier.testTag(MeAnchor.Rhythm.tag), verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
            Text(MeText.heatmapTitle, style = MaterialTheme.typography.titleMedium, color = colors.label, modifier = Modifier.semantics { heading() })
            MeRhythmGrid(if (state.hasLoaded) store.heatmap else WorkRhythmHeatmap.empty, dimmed = phase != MeRecordsPhase.Ready)
            Text(MeHomeRules.rhythmCaption(phase, store.heatmap), style = MaterialTheme.typography.bodySmall, color = colors.label2)
            if (phase == MeRecordsPhase.Failed) {
                LoadFailureRow(MeText.recordsFailed, MeText.retry, isRetrying = state.isLoading) { scope.launch { store.loadRecords() } }
            }
        }
    }
}

/** 지난주 근무 리듬(요일 7 × 시 24). 칸 농도는 잔디와 같은 사다리(한 칸 3600초가 가장 진하다). */
@Composable
internal fun MeRhythmGrid(heatmap: WorkRhythmHeatmap, dimmed: Boolean) {
    val colors = AingTheme.colors
    val type = MaterialTheme.typography.labelSmall
    val measurer = rememberTextMeasurer()
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val width = maxWidth.value
        val height = MeRhythmMetrics.height(width)
        Canvas(Modifier.fillMaxWidth().height(height.dp).semantics { }) {
            val d = density
            val cell = MeRhythmMetrics.cellSize(width) * d
            val gap = MeRhythmMetrics.GAP * d
            val left = MeRhythmMetrics.LABEL_WIDTH * d
            val top = MeRhythmMetrics.HOUR_LABEL_HEIGHT * d
            for (hour in MeRhythmMetrics.markedHours) {
                drawText(measurer.measure("$hour", type.copy(color = colors.label2)), topLeft = Offset(left + hour * (cell + gap), 0f))
            }
            for (day in 0 until WorkRhythmHeatmap.DAY_COUNT) {
                val y = top + day * (cell + gap)
                if (day % 2 == 0) {
                    val layout = measurer.measure(MeText.dayNames[day], type.copy(color = colors.label2))
                    drawText(layout, topLeft = Offset(0f, y + (cell - layout.size.height) / 2f))
                }
                for (hour in 0 until WorkRhythmHeatmap.HOUR_COUNT) {
                    val seconds = heatmap.buckets.getOrNull(day)?.getOrNull(hour) ?: 0L
                    val level = MeText.rhythmLevel(seconds)
                    val color = if (level == 0 || dimmed) colors.fill
                    else ContributionAxis.Work.tint(colors).let { it.copy(alpha = it.alpha * ContributionLevels.opacity(level)) }
                    drawRoundRect(color, Offset(left + hour * (cell + gap), y), Size(cell, cell), CornerRadius(max(1.5f * d, cell * 0.22f)))
                }
            }
        }
    }
}

// ---------------------------------------------------------------- 잔디(12주 근무 · AI 토큰)

@Composable
internal fun MeGrassCard(store: MeStore, open: (MeDestination) -> Unit, scope: CoroutineScope, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val loaded = store.recordsState.hasLoaded
    Column(
        modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(AingDimens.groupRadius)).padding(AingDimens.cardPadding),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
            MeGrassBlock(
                title = MeText.workGrassTitle,
                axis = ContributionAxis.Work,
                levels = if (loaded) MeGrassLevels.work(store.dailyGrid) else MeGrassLevels.blank(),
                dimmed = !loaded,
                summary = if (loaded) MeText.workGrassAccessibility(store.dailyGrid) else null,
                onOpen = { open(MeHomeRules.grassDestination(MeGrassAxis.work)) },
                modifier = Modifier.weight(1f),
            )
            if (store.showsTokenGrid) {
                MeGrassBlock(
                    title = MeText.tokenGrassTitle,
                    axis = ContributionAxis.Token,
                    levels = if (loaded) MeGrassLevels.token(store.tokenGrid) else MeGrassLevels.blank(),
                    dimmed = !loaded,
                    summary = if (loaded) MeText.tokenGrassAccessibility(store.tokenGrid) else null,
                    onOpen = { open(MeHomeRules.grassDestination(MeGrassAxis.token)) },
                    modifier = Modifier.weight(1f),
                )
            }
        }
        Row(
            Modifier.fillMaxWidth().heightIn(min = AingDimens.minimumTarget).clickable(role = Role.Button) { open(MeHomeRules.grassDestination(MeGrassAxis.work)) },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(MeText.grassOpenRow, style = MaterialTheme.typography.labelLarge, color = colors.accent, modifier = Modifier.weight(1f))
            AingIcon(AppIcon.ChevronRight, contentDescription = null, size = 16.dp, tint = colors.label3)
        }
    }
}

@Composable
private fun MeGrassBlock(
    title: String,
    axis: ContributionAxis,
    levels: List<List<Int?>>,
    dimmed: Boolean,
    summary: String?,
    onOpen: () -> Unit,
    modifier: Modifier,
) {
    val colors = AingTheme.colors
    Column(
        modifier
            .clickable(role = Role.Button, onClick = onOpen)
            .semantics(mergeDescendants = true) { if (summary != null) contentDescription = summary },
        verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
    ) {
        Text(title, style = MaterialTheme.typography.labelLarge, color = colors.label)
        ContributionGridCanvas(levels, axis, Modifier.fillMaxWidth(), dimmed = dimmed)
    }
}

/** 잔디 단계(주 × 요일 — null = 미래 칸). 코어 격자(WorkDailyGrid · TokenDailyGrid)의 값을 사다리 단계로만 바꾼다. */
object MeGrassLevels {
    fun work(grid: WorkDailyGrid): List<List<Int?>> = List(grid.weeks) { week ->
        List(WorkRhythmHeatmap.DAY_COUNT) { day ->
            if (grid.isFuture(week, day)) null else MeText.gridLevel(grid.seconds[week][day], WorkDailyGrid.fullDaySeconds.toLong())
        }
    }

    fun token(grid: com.yehsung.aingcheck.core.rules.insights.TokenDailyGrid): List<List<Int?>> = List(grid.weeks) { week ->
        List(WorkRhythmHeatmap.DAY_COUNT) { day ->
            if (grid.isFuture(week, day)) null else MeText.gridLevel(grid.tokens[week][day], com.yehsung.aingcheck.core.rules.insights.TokenDailyGrid.fullDayTokens)
        }
    }

    /** 불러오기 전 빈 격자(13주 · 트랙만). */
    fun blank(weeks: Int = 13): List<List<Int?>> = List(weeks) { List(WorkRhythmHeatmap.DAY_COUNT) { 0 } }
}

// ---------------------------------------------------------------- 메뉴 그룹

@Composable
internal fun MeMenuGroup(rows: List<MeMenuRow>, open: (MeDestination) -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    InsetGroup(modifier) {
        rows.forEachIndexed { index, row ->
            GroupRow(
                divider = if (index == rows.lastIndex) RowDivider.None else RowDivider.Inset(AingDimens.cardPadding + 30.dp + AingDimens.space3),
                minHeight = 50.dp,
                onClick = { open(row.destination) },
            ) {
                MenuTile(row.icon, colors.label2)
                Text(row.title, style = MaterialTheme.typography.bodyLarge, color = colors.label, modifier = Modifier.weight(1f))
                if (row.showsReply) ReplyBadge(MeText.feedbackReplyBadge) else Text(row.detail, style = MaterialTheme.typography.bodyMedium, color = colors.label2, maxLines = 1)
                AingIcon(AppIcon.ChevronRight, contentDescription = null, size = 16.dp, tint = colors.label3)
            }
        }
    }
}
