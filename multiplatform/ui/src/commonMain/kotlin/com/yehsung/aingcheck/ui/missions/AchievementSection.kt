// 원본: Sources/CheckMobileKit/Me/MeAchievementViews.swift @ 3bd04bd (MeAchievementsSection · MeAchievementRow)
//
// 「누적 미션」(도전 미션) 카드 — 머리(소제목 + 받을 보상 수 + [전부 받기]) + 계열마다 한 줄. 사장님 확정(2026-10-19): 달성하면 [받기]가
// 생기고 누르면 받아진다. 이 파일은 **그림만** 그린다 — 제목 · 보조 문장 · 보상 · 목표 · 순서는 전부 서버 응답이고(스토어 achievementSection),
// 판정도 스토어다. 그래서 이 파일에 미션 제목도, 50 · 20 · 10 같은 보상 숫자도 한 줄 없다.
//  · 받기 **실패는 그 줄 안**에서 말한다(토스트 · 알림창 · 절 위 안내줄 없음). [받기]는 그대로 남아 다시 누르는 것이 재시도다.
//  · 불러오는 중 · 실패에도 **자리를 지킨다**(MeAchievementLayout.reservedHeight — 답이 오기 전에 아래 카드가 내려앉지 않게).
//  · 루비는 💎 글자가 아니라 RubyIcon + "+N"(사용자 결정 v0.3.64).
package com.yehsung.aingcheck.ui.missions

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.achievements.AchievementStatus
import com.yehsung.aingcheck.core.stores.me.MeAchievementSection
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.achievementClaimDidFail
import com.yehsung.aingcheck.core.stores.me.achievementClaimableCount
import com.yehsung.aingcheck.core.stores.me.achievementClaimableRuby
import com.yehsung.aingcheck.core.stores.me.achievementSection
import com.yehsung.aingcheck.core.stores.me.claimAchievement
import com.yehsung.aingcheck.core.stores.me.claimAllAchievements
import com.yehsung.aingcheck.core.stores.me.claimBurst
import com.yehsung.aingcheck.core.stores.me.isClaimingAchievement
import com.yehsung.aingcheck.core.stores.me.retryAchievements
import com.yehsung.aingcheck.ui.components.RubyIcon
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.icons.SfSymbols
import com.yehsung.aingcheck.ui.shop.MeButton
import com.yehsung.aingcheck.ui.shop.MeButtonKind
import com.yehsung.aingcheck.ui.shop.MeButtonSize
import com.yehsung.aingcheck.ui.shop.MeLoadFailureRow
import com.yehsung.aingcheck.ui.shop.MeLoadingRow
import com.yehsung.aingcheck.ui.shop.MeProgressBar
import com.yehsung.aingcheck.ui.shop.MeType
import com.yehsung.aingcheck.ui.shop.MeType.digits
import com.yehsung.aingcheck.ui.shop.rememberRuby
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

object MissionTags {
    const val ACHIEVEMENTS = "missions.achievements"
    const val DAILY = "missions.daily"
    const val WEEKLY = "missions.weekly"
    const val EMPTY = "missions.empty"
    fun row(key: String) = "missions.row.$key"
}

/** 「누적 미션」 카드. 네 갈래: Hidden(카드째 없다) · Loading · Failed(자리를 지키고 [다시 시도]) · Loaded. */
@Composable
fun MeAchievementsSection(store: MeStore, reduceMotion: Boolean = false, frozenBurstProgress: Float? = null, modifier: Modifier = Modifier) {
    val section = store.achievementSection
    if (section == MeAchievementSection.Hidden) return
    MissionCard(modifier.testTag(MissionTags.ACHIEVEMENTS)) {
        Header(store)
        when (section) {
            MeAchievementSection.Hidden -> Unit
            MeAchievementSection.Loading, MeAchievementSection.Failed -> Column(Modifier.fillMaxWidth().heightIn(min = MeAchievementLayout.reservedHeight)) {
                if (section == MeAchievementSection.Failed) {
                    MeLoadFailureRow(MeText.missionsLoadFailed, isRetrying = store.achievementsState.isLoading) { store.retryAchievements() }
                } else {
                    MeLoadingRow(MeText.loading)
                }
            }
            is MeAchievementSection.Loaded -> Column(verticalArrangement = Arrangement.spacedBy(MeAchievementLayout.rowSpacing)) {
                section.rows.forEach { AchievementRow(store, it, reduceMotion, frozenBurstProgress) }
            }
        }
    }
}

/** 카드 판(표면 · 모서리 22 · 안쪽 16 · 줄 사이 12). */
@Composable
internal fun MissionCard(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .background(AingTheme.colors.surface, RoundedCornerShape(AingDimens.groupRadius))
            .padding(AingDimens.cardPadding),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
    ) { content() }
}

/** 소제목 + 오른쪽 "받을 보상 N개" · [전부 받기]. 받을 것이 **둘 이상**일 때만 전부 받기를 준다. */
@Composable
private fun Header(store: MeStore) {
    val c = AingTheme.colors
    val claimable = store.achievementClaimableCount
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        Text(MeText.missionsTitle, style = MeType.headline, color = c.label, maxLines = 1, modifier = Modifier.weight(1f).semantics { heading() })
        MeText.claimPendingHint(claimable)?.let {
            Text(it, style = MeType.footnote.copy(fontWeight = FontWeight.SemiBold).digits(), color = c.accent, maxLines = 1)
        }
        if (claimable > 1) {
            MeButton(
                MeText.claimAllButton, kind = MeButtonKind.Tinted, size = MeButtonSize.Sm,
                isBusy = store.isClaimingAchievement(MeStore.ACHIEVEMENT_CLAIM_ALL_SLOT),
                contentDescription = MeText.claimAllAccessibility(store.achievementClaimableRuby),
            ) { store.claimAllAchievements() }
        }
    }
}

/** 미션 기호(SF 이름 → Material — 모르는 이름은 별). */
internal fun missionIcon(sfName: String): AppIcon = SfSymbols.icon(sfName) ?: AppIcon.StarFill

/**
 * 도전 미션 한 줄(계열 하나) — 아이콘 · 제목 + 보상("+50") · 진행 막대 · 보조 문장 + 오른쪽 상태.
 *  · 진행 중 → 오른쪽 "23/50" · 받을 수 있음 → [받기 +N] · 받음 → "✓ 받음"(체크 기호는 화면이 그린다).
 */
@Composable
private fun AchievementRow(store: MeStore, mission: AchievementStatus.Mission, reduceMotion: Boolean, frozenBurstProgress: Float?) {
    val state = mission.state
    val failed = state == AchievementStatus.RowState.claimable && store.achievementClaimDidFail(mission.key)
    MissionRow(
        modifier = Modifier.testTag(MissionTags.row(mission.key)),
        icon = missionIcon(MeText.missionIcon(mission.key)),
        title = mission.title,
        rewardChip = if (state == AchievementStatus.RowState.claimable) null else MeText.missionReward(mission.reward),
        fraction = mission.fraction,
        isClaimed = state == AchievementStatus.RowState.claimed,
        caption = if (failed) MeText.claimFailed else mission.detail,
        showsFailure = failed,
        progress = if (state == AchievementStatus.RowState.inProgress) MeText.missionProgress(mission) else null,
        claimedMark = if (state == AchievementStatus.RowState.claimed) MeText.claimedMark else null,
        claimAmount = if (state == AchievementStatus.RowState.claimable) mission.reward else null,
        claimInFlight = store.isClaimingAchievement(mission.key),
        onClaim = { store.claimAchievement(mission.key) },
        accessibility = MeText.missionAccessibility(mission),
        burst = store.claimBurst(mission.series)?.let { it.serial to it.amount },
        reduceMotion = reduceMotion,
        frozenBurstProgress = frozenBurstProgress,
    )
}

/**
 * 미션 한 줄의 그림(누적 · 일일이 같은 모양). 받기 연출은 줄 자리(계열 · 키)에 선다 — 콕 10 을 받아 이 줄이 콕 50 으로 바뀌어도 "+5" 는 같은 자리에서
 * 떠오른다.
 */
@Composable
internal fun MissionRow(
    modifier: Modifier,
    icon: AppIcon,
    title: String,
    rewardChip: String?,
    fraction: Double,
    isClaimed: Boolean,
    caption: String,
    showsFailure: Boolean,
    progress: String?,
    claimedMark: String?,
    claimAmount: Long?,
    claimInFlight: Boolean,
    onClaim: () -> Unit,
    accessibility: String,
    burst: Pair<Int, Long>?,
    reduceMotion: Boolean,
    frozenBurstProgress: Float?,
) {
    val c = AingTheme.colors
    val tint = if (isClaimed) c.working else c.accent
    Box(modifier.fillMaxWidth().heightIn(min = MeAchievementLayout.rowMinHeight)) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(vertical = AingDimens.space1)
                .semantics(mergeDescendants = claimAmount == null) { contentDescription = accessibility },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AingDimens.space3),
        ) {
            Box(Modifier.size(30.dp).background(tint.copy(alpha = 0.14f), RoundedCornerShape(8.dp)).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
                AingIcon(icon, contentDescription = null, size = 17.dp, tint = tint)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AingDimens.space1)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
                    Text(title, style = MeType.rowTitle, color = c.label, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    // 받을 수 있는 줄은 버튼이 같은 숫자를 말하므로 칩을 감춘다(칩 "+50" 옆 버튼 "+50" 은 헷갈린다).
                    if (rewardChip != null) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                            RubyIcon(rememberRuby(14f), 14.dp)
                            Text(rewardChip, style = MeType.footnote.copy(fontWeight = FontWeight.Bold).digits(), color = tint)
                        }
                    }
                }
                MeProgressBar(fraction, done = isClaimed, thin = true)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
                    Text(caption, style = MeType.caption, color = if (showsFailure) c.pending else c.label3Text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    if (claimedMark != null) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                            AingIcon(AppIcon.Check, contentDescription = null, size = 12.dp, tint = c.working)
                            Text(claimedMark, style = MeType.caption.copy(fontWeight = FontWeight.Bold), color = c.working)
                        }
                    } else if (progress != null) {
                        Text(progress, style = MeType.caption.copy(fontWeight = FontWeight.SemiBold).digits(), color = c.label2)
                    }
                }
            }
            if (claimAmount != null) MeClaimButton(claimAmount, inFlight = claimInFlight, onClick = onClaim)
        }
        if (burst != null) {
            MeClaimBurstView(burst.second, burst.first, reduceMotion, Modifier.align(Alignment.CenterEnd), frozenBurstProgress)
        }
    }
}

