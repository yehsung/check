// 원본: Sources/CheckMobileKit/Rankings/RankingsTab.swift @ 3bd04bd (큰 제목 + 판 부제 + 세그먼트 셋)
// 원본: Sources/CheckMobileKit/Rankings/RankingsBoardSections.swift @ 3bd04bd (팀 리그 · AI 토큰 · 미니게임 판, 행, 기간 넘기기, 게임 메뉴, 어제 1등, 상품 줄)
// 원본: Sources/CheckMobileKit/Components/RankBoardParts.swift @ 3bd04bd (행 문법 · ChampionRow) · MobileRankComponents.swift(RankBadge · 메달)
//
// 순위 탭(SPEC-ios §3.4 · 시안 B 05·06). 하위 화면은 없다. 딥링크 `aingcheck://rankings/<board>` 는 세그먼트를 고른다(RankingsBoardRestore).
// **오늘 순위만** — 미니게임 판에 [오늘|역대] 전환이 없다(G §8-18 #7). 미니게임 종류는 폰 목록만(길건너 숨김).
// 판정은 스토어(RankingsStore · RankingsText)와 RankingsScreenRules 에 있다. 이 파일은 그리기만 한다.
package com.yehsung.aingcheck.ui.screens.rankings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.rankings.RankingsBoard
import com.yehsung.aingcheck.core.stores.rankings.RankingsStore
import com.yehsung.aingcheck.core.stores.rankings.RankingsText
import com.yehsung.aingcheck.core.stores.rankings.isPastWeek
import com.yehsung.aingcheck.core.wire.CenterLabel
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardEntry
import com.yehsung.aingcheck.core.wire.models.MiniGameWinner
import com.yehsung.aingcheck.core.wire.models.TeamLeaderboardEntry
import com.yehsung.aingcheck.core.wire.models.TokenBoardEntry
import com.yehsung.aingcheck.ui.components.CharacterPortrait
import com.yehsung.aingcheck.ui.components.RubyIcon
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.settingscommon.AingChipLabel
import com.yehsung.aingcheck.ui.screens.settingscommon.CenterBadge
import com.yehsung.aingcheck.ui.screens.settingscommon.GroupRow
import com.yehsung.aingcheck.ui.screens.settingscommon.InitialAvatar
import com.yehsung.aingcheck.ui.screens.settingscommon.InlineNotice
import com.yehsung.aingcheck.ui.screens.settingscommon.InsetGroup
import com.yehsung.aingcheck.ui.screens.settingscommon.LargeTitle
import com.yehsung.aingcheck.ui.screens.settingscommon.LoadFailureRow
import com.yehsung.aingcheck.ui.screens.settingscommon.LoadingRow
import com.yehsung.aingcheck.ui.screens.settingscommon.LocalScreenArt
import com.yehsung.aingcheck.ui.screens.settingscommon.NoticeKind
import com.yehsung.aingcheck.ui.screens.settingscommon.RowDivider
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

object RankingsTags {
    const val SEGMENT_PREFIX = "rankings-segment:"
    const val SECTION_PREFIX = "rankings-section:"
}

/**
 * 순위 탭 화면.
 * @param me 내 행 얼굴(RankingsScreenRules.myFace — 나 탭·지금 탭·위젯 스냅숏이 이미 아는 값. 새 서버 호출 없음).
 * @param onSelectBoard 세그먼트를 바꿨다 — 스토어에 걸고, 껍데기는 저장 상태(프로세스 죽음 복원)에도 적는다.
 */
@Composable
fun RankingsScreen(
    store: RankingsStore,
    me: RankingsMyFace,
    scope: CoroutineScope,
    onSelectBoard: (RankingsBoard) -> Unit,
    modifier: Modifier = Modifier,
    scrollable: Boolean = true,
) {
    val colors = AingTheme.colors
    val scroll = if (scrollable) Modifier.verticalScroll(rememberScrollState()) else Modifier
    Column(
        modifier.background(colors.background).then(scroll).padding(horizontal = AingDimens.sideMargin).padding(bottom = AingDimens.space6),
    ) {
        LargeTitle(RankingsScreenText.tabTitle, RankingsText.boardSubtitle(store.board))
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(top = 14.dp)) {
            val boards = RankingsScreenRules.boards
            boards.forEachIndexed { index, board ->
                SegmentedButton(
                    selected = store.board == board,
                    onClick = { onSelectBoard(board) },
                    shape = SegmentedButtonDefaults.itemShape(index, boards.size),
                    modifier = Modifier.testTag(RankingsTags.SEGMENT_PREFIX + board.rawValue),
                    icon = {},
                ) { Text(RankingsText.segmentTitle(board), maxLines = 1) }
            }
        }
        Box(Modifier.testTag(RankingsTags.SECTION_PREFIX + store.board.rawValue)) {
            when (store.board) {
                RankingsBoard.league -> RankingsLeagueSection(store, scope)
                RankingsBoard.tokens -> RankingsTokenSection(store, me, scope)
                RankingsBoard.minigame -> RankingsMiniGameSection(store, me, scope)
            }
        }
    }
}

object RankingsScreenText {
    /** 탭 이름(Swift `AingTab.rankings.title`). */
    const val tabTitle: String = "순위"
    const val gameMenuLabel: String = "게임 종류"
}

// ---------------------------------------------------------------- 공용 조각

/** 판 머리(제목 19~20 bold + 오른쪽 부속). 위 18 · 아래 8. */
@Composable
private fun SectionHeader(title: String, trailing: @Composable () -> Unit = {}) {
    Row(
        Modifier.fillMaxWidth().padding(start = 4.dp, end = 4.dp, top = 18.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.titleLarge, color = AingTheme.colors.label, modifier = Modifier.weight(1f).semantics { heading() })
        trailing()
    }
}

/** 빈 목록·불러오는 중·실패(인셋 그룹 한 장). */
@Composable
private fun EmptyCard(state: RankingsEmptyCardState, onRetry: () -> Unit) {
    InsetGroup {
        Box(Modifier.padding(AingDimens.cardPadding)) {
            when {
                state.isLoading -> LoadingRow(state.text)
                state.showsRetry -> LoadFailureRow(state.text, RankingsText.retry, onRetry = onRetry)
                else -> Text(state.text, style = MaterialTheme.typography.bodyMedium, color = AingTheme.colors.label2)
            }
        }
    }
}

/** 순위 원(1–3 메달 · 그 밖 숫자만). */
@Composable
internal fun RankBadge(rank: Int) {
    val colors = AingTheme.colors
    val medal = RankingsScreenRules.medal(rank)
    val (fill, ink) = when (medal) {
        RankingsMedal.Gold -> colors.gold to colors.goldInk
        RankingsMedal.Silver -> colors.silver to colors.silverInk
        RankingsMedal.Bronze -> colors.bronze to colors.bronzeInk
        null -> Color.Transparent to colors.label2
    }
    Box(Modifier.size(24.dp).background(fill, CircleShape), contentAlignment = Alignment.Center) {
        Text("$rank", style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = ink, maxLines = 1)
    }
}

/** 행 얼굴: 나 = 착용 캐릭터 초상(표정 = 상태), 그 밖 = 이니셜 원(사진은 이 판에서 읽지 않는다 — 네트워크 그림 0). */
@Composable
private fun RowFace(name: String, colorSeed: String, size: Dp, me: RankingsMyFace?) {
    if (me != null) {
        val art = LocalScreenArt.current.portrait(me.characterId ?: DEFAULT_CHARACTER, me.mood)
        CharacterPortrait(art, me.mood, size, ringGap = AingTheme.colors.accentTint)
    } else {
        InitialAvatar(name, size, colorSeed = colorSeed)
    }
}

private const val DEFAULT_CHARACTER = "aing"

/** 이름 + 센터 배지 + 칩. */
@Composable
private fun NameLine(name: String, centerServerValue: String?, chips: List<RankingsChip>, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(name, style = MaterialTheme.typography.titleSmall, color = colors.label, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
        CenterBadge(RankingsScreenRules.centerServerValue(centerServerValue))
        chips.forEach { chip ->
            when (chip) {
                RankingsChip.Me -> AingChipLabel(RankingsText.meChip, tint = colors.onAccentFill, background = colors.accentFill)
                RankingsChip.MyTeam -> AingChipLabel(RankingsText.myTeamChip, tint = colors.accent)
                RankingsChip.PrivateUsage -> AingChipLabel(RankingsText.privateChip, tint = colors.label2, background = colors.fill)
            }
        }
    }
}

/** 얇은 진행 막대(트랙 fill + 채움). */
@Composable
private fun ThinBar(fraction: Double, brush: Brush, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Box(modifier.fillMaxWidth().height(6.dp).background(colors.fill, CircleShape)) {
        val f = fraction.coerceIn(0.0, 1.0).toFloat()
        if (f > 0f) Box(Modifier.fillMaxWidth(f).height(6.dp).background(brush, CircleShape))
    }
}

/** 행 한 줄(그룹 안 — 내 행·우리 팀은 강조 칠). */
@Composable
private fun RankRow(rank: Int, isMine: Boolean, isLast: Boolean, faceBase: Dp, minHeight: Dp = 0.dp, content: @Composable () -> Unit, face: @Composable () -> Unit, description: String) {
    val colors = AingTheme.colors
    val divider = if (isLast) RowDivider.None else RowDivider.Inset(AingDimens.cardPadding + 24.dp + 10.dp + faceBase + 10.dp)
    Box(Modifier.fillMaxWidth().background(if (isMine) colors.accentTint else Color.Transparent).clearAndSetSemantics { contentDescription = description }) {
        GroupRow(divider = divider, minHeight = minHeight, padding = androidx.compose.foundation.layout.PaddingValues(horizontal = AingDimens.cardPadding, vertical = 12.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                RankBadge(rank)
                face()
                Box(Modifier.weight(1f)) { content() }
            }
        }
    }
}

/** 기간 넘기기 알약(‹ ›). 보이는 높이 30 · 누름 영역 44. */
@Composable
private fun PeriodStepper(canStepBack: Boolean, canStepForward: Boolean, backLabel: String, forwardLabel: String, previous: () -> Unit, next: () -> Unit) {
    val colors = AingTheme.colors
    Row(Modifier.background(colors.fill, CircleShape), verticalAlignment = Alignment.CenterVertically) {
        StepperArrow(AppIcon.ChevronLeft, backLabel, canStepBack, previous)
        Box(Modifier.width(1.dp).height(16.dp).background(colors.separator))
        StepperArrow(AppIcon.ChevronRight, forwardLabel, canStepForward, next)
    }
}

@Composable
private fun StepperArrow(icon: AppIcon, label: String, enabled: Boolean, action: () -> Unit) {
    val colors = AingTheme.colors
    Box(
        Modifier
            .widthIn(min = 44.dp)
            .heightIn(min = 30.dp)
            .clickable(enabled = enabled, role = Role.Button, onClick = action)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        AingIcon(icon, contentDescription = null, size = 18.dp, tint = if (enabled) colors.label else colors.label3)
    }
}

// ---------------------------------------------------------------- 팀 리그

@Composable
private fun RankingsLeagueSection(store: RankingsStore, scope: CoroutineScope) {
    val colors = AingTheme.colors
    val now = store.leagueNow
    val page = store.leagueDisplayPage
    val entries = page.entries
    val state = store.leagueState
    val isPast = store.isLeaguePastWeek
    Column {
        SectionHeader(store.leagueTitle) {
            if (store.showsLeagueWeekNavigation) {
                PeriodStepper(
                    store.canStepLeagueWeekBack, store.canStepLeagueWeekForward, RankingsText.previousWeek, RankingsText.nextWeek,
                    previous = { store.stepLeagueWeek(-1) }, next = { store.stepLeagueWeek(1) },
                )
            }
        }
        // 머리와 목록 사이 한 줄은 이번 주에도 늘 그린다(과거 주에만 생기면 ‹ 를 누를 때마다 목록이 튄다).
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp).padding(bottom = 8.dp)) {
            val note = RankingsText.leagueWeekNote(isPast, page.myTeamMissing)
            Text(note ?: "", style = MaterialTheme.typography.bodySmall, color = colors.label2, modifier = Modifier.weight(1f))
            Text(RankingsText.leagueAverageHint, style = MaterialTheme.typography.bodySmall, color = colors.label2)
        }
        if (entries.isEmpty()) {
            EmptyCard(RankingsScreenRules.leagueEmpty(state, page.unfilteredCount.toInt(), isPast, store.league.isEmpty())) { scope.launch { store.loadLeague() } }
        } else {
            if (state.hasFailed) InlineNotice(RankingsText.leagueFailedText(isPast), NoticeKind.Warning, Modifier.padding(bottom = 8.dp))
            InsetGroup {
                entries.forEachIndexed { index, entry ->
                    LeagueRow(index + 1, entry, entry.id == store.myTeamID, index == entries.lastIndex, now)
                }
            }
        }
    }
}

@Composable
private fun LeagueRow(rank: Int, entry: TeamLeaderboardEntry, isMyTeam: Boolean, isLast: Boolean, now: com.yehsung.aingcheck.core.wire.SwiftDate) {
    val colors = AingTheme.colors
    RankRow(
        rank, isMine = isMyTeam, isLast = isLast, faceBase = 36.dp,
        description = RankingsText.leagueRowAccessibility(rank, entry, isMyTeam, now),
        face = { InitialAvatar(entry.name, 36.dp) },
        content = {
            Column {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    NameLine(entry.name, entry.center, if (isMyTeam) listOf(RankingsChip.MyTeam) else emptyList(), Modifier.weight(1f))
                    Spacer(Modifier.width(8.dp))
                    Text(RankingsText.leagueValue(entry), style = MaterialTheme.typography.labelLarge, color = colors.label, maxLines = 1)
                }
                Row(Modifier.padding(top = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (!entry.isPastWeek(now) && entry.workingCount > 0) {
                        Box(Modifier.size(6.dp).background(colors.workingDot, CircleShape))
                    }
                    Text(RankingsText.leagueSubtitle(entry, now), style = MaterialTheme.typography.bodySmall, color = colors.label2)
                }
                Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    val brush = when (RankingsText.leagueBarKind(entry, isMyTeam)) {
                        RankingsText.LeagueBarKind.done -> Brush.linearGradient(listOf(colors.workingDot, colors.workingDot))
                        RankingsText.LeagueBarKind.gauge -> Brush.horizontalGradient(colors.gaugeStops)
                        RankingsText.LeagueBarKind.accent -> Brush.linearGradient(listOf(colors.accentFill, colors.accentFill))
                    }
                    ThinBar(entry.goal.progress, brush, Modifier.weight(1f))
                    Text(RankingsText.leaguePercentText(entry), style = MaterialTheme.typography.labelMedium, color = colors.label2, modifier = Modifier.widthIn(min = 34.dp))
                }
            }
        },
    )
}

// ---------------------------------------------------------------- AI 토큰

@Composable
private fun RankingsTokenSection(store: RankingsStore, me: RankingsMyFace, scope: CoroutineScope) {
    val colors = AingTheme.colors
    val state = store.tokenState
    val entries = store.tokenBoard
    val isCurrent = store.isCurrentTokenMonth
    Column {
        SectionHeader(store.tokenTitle) {
            PeriodStepper(
                canStepBack = true, canStepForward = !isCurrent, RankingsText.previousMonth, RankingsText.nextMonth,
                previous = { store.stepTokenMonth(-1) }, next = { store.stepTokenMonth(1) },
            )
        }
        if (entries.isEmpty()) {
            EmptyCard(RankingsScreenRules.tokenEmpty(state, isCurrent)) { scope.launch { store.loadTokens() } }
        } else {
            if (state.hasFailed) InlineNotice(RankingsText.tokenFailed, NoticeKind.Warning, Modifier.padding(bottom = 8.dp))
            val todayKey = if (isCurrent) store.todayKey else null
            val top = entries.maxOfOrNull { it.total } ?: 0L
            InsetGroup {
                entries.forEachIndexed { index, entry ->
                    val isMe = RankingsScreenRules.isMe(entry.userID, store.myUserID)
                    TokenRow(
                        index + 1, entry, isMe, if (isMe) me else null,
                        RankingsScreenRules.tokenChips(isMe, store.myTokenUsagePublic), todayKey,
                        RankingsText.tokenBarFraction(entry.total, top), index == entries.lastIndex,
                    )
                }
            }
        }
    }
}

@Composable
private fun TokenRow(
    rank: Int,
    entry: TokenBoardEntry,
    isMe: Boolean,
    me: RankingsMyFace?,
    chips: List<RankingsChip>,
    todayKey: String?,
    barFraction: Double,
    isLast: Boolean,
) {
    val colors = AingTheme.colors
    RankRow(
        rank, isMine = isMe, isLast = isLast, faceBase = 36.dp,
        description = RankingsText.tokenRowAccessibility(rank, entry, isMe, RankingsChip.PrivateUsage in chips, todayKey),
        face = { RowFace(entry.name, entry.name, 36.dp, me) },
        content = {
            Column {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    NameLine(entry.name, entry.center, chips, Modifier.weight(1f))
                    Spacer(Modifier.width(8.dp))
                    Text(RankingsText.tokenTotalCompact(entry), style = MaterialTheme.typography.labelLarge, color = colors.label, maxLines = 1)
                }
                val tools = RankingsTokenCaption.toolUsageLabel(entry)
                if (tools != null || todayKey != null) {
                    // 한 줄에 다 들어가면 도구 줄 … 오늘 +N, 안 들어가면 오늘 +N 을 아래 줄로(iOS ViewThatFits — 한 줄 고정은 'Claude 44.3억 ·…' 로 잘렸다).
                    LineOrStack(Modifier.padding(top = 2.dp), gap = 8.dp) {
                        Text(tools ?: "", style = MaterialTheme.typography.bodySmall, color = colors.label2, maxLines = 1)
                        if (todayKey != null) {
                            val grew = entry.todayDelta(todayKey) > 0
                            Text(
                                RankingsText.tokenTodayCompact(entry, todayKey),
                                style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold),
                                color = if (grew) colors.aiToken else colors.label2,
                                maxLines = 1,
                            )
                        }
                    }
                }
                ThinBar(barFraction, Brush.linearGradient(listOf(colors.aiToken, colors.aiToken)), Modifier.padding(top = 8.dp))
            }
        },
    )
}

/** 도구 줄(Claude · Codex). 서버값 그대로(공유 Codex 비율은 서버값만 — 기억 shared-codex-split-lives-only-in-the-server). */
internal object RankingsTokenCaption {
    fun toolUsageLabel(entry: TokenBoardEntry): String? = com.yehsung.aingcheck.core.stores.rankings.TokenBoardText.toolUsageLabel(entry)
}

// ---------------------------------------------------------------- 미니게임(오늘 순위만)

@Composable
private fun RankingsMiniGameSection(store: RankingsStore, me: RankingsMyFace, scope: CoroutineScope) {
    val colors = AingTheme.colors
    val state = store.miniGameState
    val entries = store.miniGameBoard
    Column {
        SectionHeader(RankingsText.miniGameRankTitle) {
            GameMenu(store.miniGameKind) { store.select(it) }
        }
        val winner = store.miniGameWinner
        if (winner != null) ChampionRow(winner, Modifier.padding(bottom = 12.dp))
        if (entries.isEmpty()) {
            EmptyCard(RankingsScreenRules.miniGameEmpty(state)) { scope.launch { store.loadMiniGame() } }
        } else {
            InsetGroup {
                entries.forEachIndexed { index, entry ->
                    val isMe = RankingsScreenRules.isMe(entry.userID, store.myUserID)
                    MiniGameRow(index + 1, entry, isMe, if (isMe) me else null, index == entries.lastIndex)
                }
            }
        }
        Column(Modifier.padding(horizontal = 4.dp).padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            PrizeLine()
            RankingsScreenRules.quorumLine(store.knowsMiniGamePlayerCount, store.miniGamePlayers)?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = colors.label2)
            }
        }
    }
}

/** 게임 고르기 메뉴 알약(회색 알약 30 · 누름 영역 44). 폰 목록만(길건너 숨김). */
@Composable
private fun GameMenu(selected: MiniGameKind, select: (MiniGameKind) -> Unit) {
    val colors = AingTheme.colors
    var expanded by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier
                .heightIn(min = 44.dp)
                .clickable(role = Role.DropdownList) { expanded = true }
                .semantics { contentDescription = "${RankingsScreenText.gameMenuLabel}, ${selected.title}" },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                Modifier.background(colors.fill, CircleShape).heightIn(min = 30.dp).padding(start = 12.dp, end = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(selected.title, style = MaterialTheme.typography.labelLarge, color = colors.label2, maxLines = 1)
                AingIcon(AppIcon.ExpandMore, contentDescription = null, size = 16.dp, tint = colors.label2)
            }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            RankingsScreenRules.miniGameKinds.forEach { kind ->
                DropdownMenuItem(text = { Text(kind.title) }, onClick = {
                    expanded = false
                    select(kind)
                })
            }
        }
    }
}

/** 어제 1등 한 줄(왕관 원 + "어제 1등" / 이름·배지 · 점수 + 획득 칩). */
@Composable
private fun ChampionRow(winner: MiniGameWinner, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val award = RankingsScreenRules.championAward(winner.awarded)
    val description = buildList {
        add(RankingsText.yesterdayChampion)
        add(winner.name)
        CenterLabel.display(RankingsScreenRules.centerServerValue(winner.center))?.let { add(it) }
        add(RankingsText.score(winner.score))
        if (award != null) add("루비 ${award}개 받음")
    }.joinToString(", ")
    InsetGroup(modifier.clearAndSetSemantics { contentDescription = description }) {
        GroupRow(divider = RowDivider.None, padding = androidx.compose.foundation.layout.PaddingValues(horizontal = AingDimens.cardPadding, vertical = 12.dp)) {
            Box(Modifier.size(36.dp).background(colors.gold, CircleShape), contentAlignment = Alignment.Center) {
                AingIcon(AppIcon.CrownFill, contentDescription = null, size = 20.dp, tint = colors.crownInk)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(RankingsText.yesterdayChampion, style = MaterialTheme.typography.bodySmall, color = colors.label2)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(winner.name, style = MaterialTheme.typography.titleSmall, color = colors.label, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
                    CenterBadge(RankingsScreenRules.centerServerValue(winner.center))
                    Text(RankingsText.score(winner.score), style = MaterialTheme.typography.labelLarge, color = colors.label2, maxLines = 1)
                }
            }
            if (award != null) AingChipLabel("+$award ${RankingsScreenText.awardedSuffix}", tint = colors.working)
        }
    }
}

private val RankingsScreenText.awardedSuffix: String get() = "받음"

@Composable
private fun MiniGameRow(rank: Int, entry: MiniGameBoardEntry, isMe: Boolean, me: RankingsMyFace?, isLast: Boolean) {
    val colors = AingTheme.colors
    RankRow(
        rank, isMine = isMe, isLast = isLast, faceBase = 30.dp, minHeight = 48.dp,
        description = RankingsText.miniGameRowAccessibility(rank, entry, isMe),
        face = { RowFace(entry.name, entry.name, 30.dp, me) },
        content = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                NameLine(entry.name, entry.center, if (isMe) listOf(RankingsChip.Me) else emptyList(), Modifier.weight(1f))
                Spacer(Modifier.width(4.dp))
                Text(RankingsText.score(entry.bestScore), style = MaterialTheme.typography.labelLarge, color = colors.label, maxLines = 1)
            }
        },
    )
}

/** "자정에 1·2·3등에게 루비 [보석]20 · [보석]10 · [보석]5". 소리는 한 문장(prizeCaption). */
@Composable
private fun PrizeLine() {
    val colors = AingTheme.colors
    val gem = LocalScreenArt.current.ruby(14f)
    Row(
        Modifier.clearAndSetSemantics { contentDescription = RankingsText.prizeCaption },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Text(RankingsScreenText.prizeLead, style = MaterialTheme.typography.bodySmall, color = colors.label2)
        RankingsText.rubyPrizes.forEachIndexed { index, amount ->
            if (index > 0) Text("·", style = MaterialTheme.typography.bodySmall, color = colors.label2)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                RubyIcon(gem, 14.dp)
                Text("$amount", style = MaterialTheme.typography.bodySmall, color = colors.label2)
            }
        }
    }
}

private val RankingsScreenText.prizeLead: String get() = "자정에 1·2·3등에게 루비"

/**
 * 두 조각을 한 줄(왼쪽 · 오른쪽 끝)에 놓되, 둘의 제 폭 합 + [gap] 이 칸을 넘으면 세로로 쌓는다(iOS `ViewThatFits(in: .horizontal)` 자리).
 * 첫 조각이 그래도 넘치면 칸 폭으로 자른다(한 줄 · 말줄임 없음).
 */
@Composable
internal fun LineOrStack(modifier: Modifier = Modifier, gap: Dp, content: @Composable () -> Unit) {
    androidx.compose.ui.layout.Layout(content, modifier) { measurables, constraints ->
        val loose = constraints.copy(minWidth = 0, minHeight = 0)
        val natural = measurables.map { it.maxIntrinsicWidth(constraints.maxHeight.coerceAtMost(10_000)) }
        val gapPx = gap.roundToPx()
        val fits = natural.sum() + gapPx * (measurables.size - 1).coerceAtLeast(0) <= constraints.maxWidth
        val placeables = measurables.map { it.measure(loose) }
        if (fits || placeables.size < 2) {
            val height = placeables.maxOfOrNull { it.height } ?: 0
            layout(constraints.maxWidth, height) {
                placeables.firstOrNull()?.place(0, 0)
                if (placeables.size > 1) placeables.last().let { it.place(constraints.maxWidth - it.width, 0) }
            }
        } else {
            val height = placeables.sumOf { it.height } + 2.dp.roundToPx()
            layout(constraints.maxWidth, height) {
                var y = 0
                placeables.forEach { p ->
                    p.place(0, y)
                    y += p.height + 2.dp.roundToPx()
                }
            }
        }
    }
}
