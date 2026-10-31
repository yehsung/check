// 원본: Sources/check/CheckMenuView.swift:2069(TeamPanel — 머리 · 줄) · Sources/check/CheckComponents.swift:75(PresenceChip) · :210(TeamMemberRow — 얼굴 · 상세 · ✓ · 목표 막대)
//
// 우리 팀 전체 명단: 쉬는 팀원까지 줄마다 얼굴 · 상태 · '주 N시간' · 목표 막대. 값과 정렬은 core 쪽 [NowTeamRoster] 다 — 이 화면은 그리기만 한다.
// 맥 줄의 내 사진 바꾸기(마우스 올림 카메라)는 옮기지 않았다 — 폰은 나 탭 프로필이 그 자리다.
package com.yehsung.aingcheck.android.screens.now

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.now.NowLoadState
import com.yehsung.aingcheck.core.stores.now.NowStore
import com.yehsung.aingcheck.core.stores.now.NowTeamRoster
import com.yehsung.aingcheck.core.stores.now.NowTeamRosterRow
import com.yehsung.aingcheck.core.stores.now.NowText
import com.yehsung.aingcheck.core.wire.models.MemberPresence
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.session.kit.LoadFailureRow
import com.yehsung.aingcheck.ui.screens.session.kit.LoadingRow
import com.yehsung.aingcheck.ui.screens.session.kit.PersonAvatar
import com.yehsung.aingcheck.ui.screens.session.kit.PersonName
import com.yehsung.aingcheck.ui.screens.session.kit.READABLE_WIDTH
import com.yehsung.aingcheck.ui.screens.session.kit.rememberNow
import com.yehsung.aingcheck.ui.screens.session.kit.sf
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

object TeamRosterTags {
    const val SCREEN = "team-roster-screen"
    const val BACK = "team-roster-back"
    fun row(id: String): String = "team-roster-row-$id"
    fun goal(id: String): String = "team-roster-goal-$id"
}

@Composable
fun TeamRosterScreen(store: NowStore, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    LaunchedEffect(store) { store.tabDidAppear() }
    val now = rememberNow(store.context.clock, everySeconds = 1)
    val rows = store.teamRoster(now)
    Box(modifier.fillMaxSize().background(colors.background).testTag(TeamRosterTags.SCREEN), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = READABLE_WIDTH).fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = AingDimens.space8)) {
            Row(Modifier.fillMaxWidth().padding(end = AingDimens.titleMargin, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onBack, modifier = Modifier.testTag(TeamRosterTags.BACK).semantics { contentDescription = "뒤로" }) {
                    AingIcon(sf("chevron.left", AppIcon.ChevronLeft), null, size = 28.dp, tint = colors.accent)
                }
                Text(store.membership?.teamName ?: NowText.teamRosterTitle, style = MaterialTheme.typography.titleLarge, color = colors.label, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).semantics { heading() })
                if (rows.isNotEmpty()) {
                    Text(NowTeamRoster.workingCountLabel(NowTeamRoster.workingCount(rows)), style = MaterialTheme.typography.bodyMedium, color = colors.label2)
                }
            }
            Column(Modifier.padding(horizontal = AingDimens.sideMargin).fillMaxWidth().background(colors.surface, RoundedCornerShape(AingDimens.groupRadius))) {
                if (rows.isEmpty()) {
                    Box(Modifier.padding(16.dp)) {
                        when (store.teamLoadState) {
                            NowLoadState.loading -> LoadingRow()
                            NowLoadState.failed -> LoadFailureRow(NowText.teamRosterUnavailable, store.isRefreshing, retry = { store.refresh() })
                            NowLoadState.loaded -> Text(NowText.teamRosterEmpty, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
                        }
                    }
                } else {
                    rows.forEachIndexed { index, row ->
                        TeamRosterRow(row)
                        if (index < rows.size - 1) HorizontalDivider(Modifier.padding(start = 64.dp), thickness = AingDimens.hairline, color = colors.separator)
                    }
                }
            }
        }
    }
}

/** 한 줄: 얼굴 · 이름(+센터) · 상태메시지 · '주 N시간'(+✓) · 끊김 줄 · 상태 칩 / 글자 칸 밑에 목표 막대 + %. */
@Composable
private fun TeamRosterRow(row: NowTeamRosterRow) {
    val colors = AingTheme.colors
    Column(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 16.dp, vertical = 10.dp).semantics(mergeDescendants = true) {}.testTag(TeamRosterTags.row(row.id)), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            PersonAvatar(row.name, row.id, row.avatarURL?.absoluteString, 36.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                PersonName(row.name, row.center)
                row.statusMessage?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = colors.label2, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.semantics { contentDescription = "상태메시지 $it" })
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(row.primaryDetail, style = MaterialTheme.typography.bodySmall, color = colors.label2, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false))
                    if (row.meetsWeeklyGoal) AingIcon(sf("checkmark", AppIcon.Check), NowText.goalMet, size = 12.dp, tint = colors.working)
                }
                row.secondaryDetail?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.pending, maxLines = 1) }
            }
            PresenceChip(row.presence)
        }
        // 막대는 얼굴이 아니라 글자 칸 시작점부터 — "이 사람의 진행률"임을 자리로 말한다(맥 textColumnInset).
        Row(Modifier.padding(start = 48.dp).testTag(TeamRosterTags.goal(row.id)), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Box(Modifier.weight(1f)) { ProgressBar(row.goalFraction, if (row.goalFraction >= 1.0) colors.working else colors.accentFill, height = 4.dp) }
            // 칸 폭을 잡아 줄마다 막대 끝이 같은 자리에 선다(세 자리 100% 까지).
            Text("${row.goalPercent}%", style = MaterialTheme.typography.bodySmall, color = colors.label2, maxLines = 1, textAlign = TextAlign.End, modifier = Modifier.widthIn(min = 36.dp))
        }
    }
}

/** 맥 `PresenceChip`: 근무 = 초록 채움 · 끊김 = 앰버 채움 · 종료 = 테두리만. */
@Composable
private fun PresenceChip(presence: MemberPresence) {
    val colors = AingTheme.colors
    val fill: Color? = when (presence) {
        MemberPresence.ActiveWorking -> colors.working
        is MemberPresence.StaleWorking -> colors.pending
        MemberPresence.OffWork -> null
    }
    val shape = CircleShape
    val base = if (fill != null) Modifier.background(fill, shape) else Modifier.border(1.dp, colors.separator, shape)
    Text(
        NowTeamRoster.presenceLabel(presence),
        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
        color = if (fill != null) colors.onAccentFill else colors.label2,
        maxLines = 1,
        modifier = base.padding(horizontal = 9.dp, vertical = 4.dp),
    )
}
