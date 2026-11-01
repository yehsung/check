// 원본: Sources/CheckMobileKit/Now/NowTeamRosterScreen.swift:11 @ 23b91326 (NowTeamRosterScreen) · :102 (NowTeamRosterRowView)
//
// 우리 팀 전체 명단(지금 탭 [전체 보기] → push). 값과 정렬은 core 쪽 [NowTeamRosterRules] 다 — 이 화면은 그리기만 한다. 정본은 iOS 다(양쪽 폰이 같아야 한다).
// 값은 지금 탭이 받아 둔 것을 읽는다. 이 화면 때문에 도는 주기 조회는 없다 — 1분마다 다시 그리는 것은 폰이 세는 시간뿐이고, 서버는 기존 60초 주기와 당겨서 새로고침만 부른다.
// 읽기 전용이다 — 맥 팀 카드처럼 말 거는 입구가 없다(차단한 사람의 얼굴을 눌러 대화가 열리는 길도 그래서 없다).
package com.yehsung.aingcheck.android.screens.now

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.messages.MobileRelativeTime
import com.yehsung.aingcheck.core.stores.messages.PresenceStatus
import com.yehsung.aingcheck.core.stores.now.NowLoadState
import com.yehsung.aingcheck.core.stores.now.NowStore
import com.yehsung.aingcheck.core.stores.now.NowTeamRoster
import com.yehsung.aingcheck.core.stores.now.NowTeamRosterRow
import com.yehsung.aingcheck.core.stores.now.NowText
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.session.kit.EmptyStateView
import com.yehsung.aingcheck.ui.screens.session.kit.InlineNotice
import com.yehsung.aingcheck.ui.screens.session.kit.LoadFailureRow
import com.yehsung.aingcheck.ui.screens.session.kit.LoadingRow
import com.yehsung.aingcheck.ui.screens.session.kit.NoticeKind
import com.yehsung.aingcheck.ui.screens.session.kit.PersonAvatar
import com.yehsung.aingcheck.ui.screens.session.kit.PersonName
import com.yehsung.aingcheck.ui.screens.session.kit.READABLE_WIDTH
import com.yehsung.aingcheck.ui.screens.session.kit.SectionHeader
import com.yehsung.aingcheck.ui.screens.session.kit.rememberNow
import com.yehsung.aingcheck.ui.screens.session.kit.sf
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

object TeamRosterTags {
    const val SCREEN = "team-roster-screen"
    const val BACK = "team-roster-back"
    fun row(id: String): String = "team-roster-row-$id"
}

object TeamRosterLayout {
    /** 이 글꼴 배율부터 줄을 쌓는다(iOS `isAccessibilitySize` 자리 — 다른 화면의 쌓는 기준과 같은 값). */
    const val STACK_FONT_SCALE = 1.3f
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TeamRosterScreen(store: NowStore, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val now = rememberNow(store.context.clock, everySeconds = 60)
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    Column(modifier.fillMaxSize().background(colors.background).testTag(TeamRosterTags.SCREEN)) {
        TeamRosterTopBar(onBack)
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                scope.launch {
                    refreshing = true
                    try { store.refreshNow() } finally { refreshing = false }
                }
            },
            modifier = Modifier.fillMaxSize(),
        ) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                // 내용이 짧아도(빈 화면 · 실패) 화면 전체에서 당겨지게 스크롤 칸이 높이를 다 쓴다.
                Column(Modifier.widthIn(max = READABLE_WIDTH).fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = AingDimens.space8)) {
                    TeamRosterBody(store, now)
                }
            }
        }
    }
}

/** 머리: 뒤로 · 가운데 "우리 팀"(팀 이름은 아래 요약 줄이 말한다). */
@Composable
private fun TeamRosterTopBar(onBack: () -> Unit) {
    val colors = AingTheme.colors
    Box(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 4.dp)) {
        IconButton(onClick = onBack, modifier = Modifier.align(Alignment.CenterStart).testTag(TeamRosterTags.BACK).semantics { contentDescription = "뒤로" }) {
            AingIcon(sf("chevron.left", AppIcon.ChevronLeft), null, size = 26.dp, tint = colors.label)
        }
        Text(
            NowText.ourTeam,
            style = MaterialTheme.typography.titleMedium,
            color = colors.label,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.align(Alignment.Center).padding(horizontal = 52.dp).semantics { heading() },
        )
    }
}

@Composable
private fun TeamRosterBody(store: NowStore, now: SwiftDate) {
    if (store.hasNoTeam) {
        EmptyStateView(sf("person.2", AppIcon.Group), NowText.noTeamTitle, NowText.teamRosterNoTeamBody, modifier = Modifier.padding(horizontal = AingDimens.sideMargin))
    } else {
        when (store.teamLoadState) {
            NowLoadState.loading -> TeamRosterCard(Modifier.padding(top = 8.dp)) { LoadingRow() }
            NowLoadState.failed -> TeamRosterCard(Modifier.padding(top = 8.dp)) {
                LoadFailureRow(NowText.teamRosterUnavailable, store.isRefreshing, retry = { store.refresh() })
            }
            NowLoadState.loaded -> TeamRosterLoaded(store, now)
        }
    }
}

@Composable
private fun TeamRosterLoaded(store: NowStore, now: SwiftDate) {
    val colors = AingTheme.colors
    // 받아 둔 명단 위로 새로고침이 실패했다 — 값은 두고, 낡았을 수 있다는 것만 말한다(지금 탭과 같은 띠).
    store.notice?.let { InlineNotice(it, NoticeKind.Warning, Modifier.padding(horizontal = AingDimens.sideMargin, vertical = 4.dp)) }
    Text(
        NowText.teamRosterSummary(store.membership?.teamName, store.goalHours),
        style = MaterialTheme.typography.bodyMedium,
        color = colors.label2,
        modifier = Modifier.padding(start = AingDimens.titleMargin, end = AingDimens.titleMargin, top = 12.dp, bottom = 8.dp),
    )
    val roster = store.teamRoster(now) ?: NowTeamRoster(emptyList(), emptyList())
    if (roster.isEmpty) {
        TeamRosterCard(Modifier.padding(top = 24.dp)) {
            Text(NowText.teamRosterEmpty, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
        }
    } else {
        TeamRosterGroup(NowText.teamRosterWorking, roster.working, now)
        TeamRosterGroup(NowText.teamRosterResting, roster.resting, now)
    }
}

/** 한 칸짜리 카드(불러오는 중 · 실패 · 빈 명단). */
@Composable
private fun TeamRosterCard(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier.padding(horizontal = AingDimens.sideMargin).fillMaxWidth()
            .background(AingTheme.colors.surface, RoundedCornerShape(AingDimens.groupRadius)).padding(horizontal = 16.dp, vertical = 10.dp),
    ) { content() }
}

/** 한 묶음(절 머리 "근무 중 · 4명" + 카드 한 장). 비었으면 머리도 없다. */
@Composable
private fun TeamRosterGroup(title: String, rows: List<NowTeamRosterRow>, now: SwiftDate) {
    if (rows.isEmpty()) return
    val colors = AingTheme.colors
    SectionHeader(title, NowText.peopleCount(rows.size))
    Column(Modifier.padding(horizontal = AingDimens.sideMargin).fillMaxWidth().background(colors.surface, RoundedCornerShape(AingDimens.groupRadius))) {
        rows.forEachIndexed { index, row ->
            key(row.id) {
                TeamRosterRow(row, now)
                if (index < rows.size - 1) HorizontalDivider(Modifier.padding(start = 64.dp), thickness = AingDimens.hairline, color = colors.separator)
            }
        }
    }
}

/**
 * 명단 한 줄: 얼굴(근무 초록 · 끊김 앰버 · 쉬면 점 없음) · 이름 뒤 센터 · '나' · 오른쪽 주간 누적 / 상태메시지 · 경과(또는 끊김) / 목표 막대.
 * 큰 글자에서는 얼굴 옆 좁은 칸에 두면 "주 13시간 10분"이 줄을 민다 — 첫 줄은 얼굴 · 이름, 나머지는 아랫줄에 카드 폭 전부를 쓴다.
 * 톡백은 줄을 한 덩이로 [NowTeamRosterRow.spokenSummary] 만 읽는다(testTag 는 지워지지 않게 clearAndSetSemantics 왼쪽에 둔다).
 */
@Composable
private fun TeamRosterRow(row: NowTeamRosterRow, now: SwiftDate) {
    val stacked = LocalDensity.current.fontScale >= TeamRosterLayout.STACK_FONT_SCALE
    val presence = when {
        !row.isWorking -> PresenceStatus.off
        row.isStale -> PresenceStatus.pending
        else -> PresenceStatus.working
    }
    val rowModifier = Modifier.fillMaxWidth()
        .testTag(TeamRosterTags.row(row.id))
        .clearAndSetSemantics { contentDescription = row.spokenSummary(now) }
        .padding(horizontal = 16.dp, vertical = 10.dp)
    if (stacked) {
        Column(rowModifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                PersonAvatar(row.name, row.id, row.avatarURL?.absoluteString, 36.dp, status = presence)
                PersonName(row.name, row.center, Modifier.weight(1f), isMe = row.isMe, stacked = true)
            }
            TeamRosterWeekText(row, wraps = true)
            TeamRosterDetails(row, now, statusLines = 3)
        }
    } else {
        Row(rowModifier, verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            PersonAvatar(row.name, row.id, row.avatarURL?.absoluteString, 36.dp, status = presence)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PersonName(row.name, row.center, Modifier.weight(1f), isMe = row.isMe)
                    TeamRosterWeekText(row, wraps = false)
                }
                TeamRosterDetails(row, now, statusLines = 1)
            }
        }
    }
}

/** 오른쪽 "주 8시간 5분". 목표를 넘기면 초록. 보통 크기는 이름 옆에서 줄지 않고, 큰 글자는 제 줄이 있으니 꺾인다. */
@Composable
private fun TeamRosterWeekText(row: NowTeamRosterRow, wraps: Boolean) {
    val colors = AingTheme.colors
    Text(
        NowText.teamRosterWeek(row.weekSeconds),
        style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"),
        color = if (row.isGoalMet) colors.working else colors.label,
        maxLines = if (wraps) Int.MAX_VALUE else 1,
        softWrap = wraps,
    )
}

/** 상태메시지 · 경과(또는 끊김) · 목표 막대. 시작 시각을 모르면 경과 줄이 없다(0 으로 지어내지 않는다). */
@Composable
private fun TeamRosterDetails(row: NowTeamRosterRow, now: SwiftDate, statusLines: Int) {
    val colors = AingTheme.colors
    row.statusMessage?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.label2, maxLines = statusLines, overflow = TextOverflow.Ellipsis) }
    val elapsed = row.elapsedSeconds
    if (row.isStale) {
        Text(NowText.staleLastSeen(row.lastSeenAt?.let { MobileRelativeTime.text(it, now) }), style = MaterialTheme.typography.bodySmall, color = colors.pending)
    } else if (elapsed != null) {
        Text(NowText.teamRosterElapsed(elapsed), style = MaterialTheme.typography.bodySmall.copy(fontFeatureSettings = "tnum"), color = colors.label2)
    }
    Box(Modifier.fillMaxWidth().padding(top = 2.dp)) {
        ProgressBar(row.goalProgress, if (row.isGoalMet) colors.workingDot else colors.accent, height = 4.dp)
    }
}
