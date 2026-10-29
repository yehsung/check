// 원본: Sources/CheckMobileKit/Me/MeWeeklyWorkViews.swift @ 3bd04bd (MeWeeklyWorkCard · MeWeeklyTierChip)
//
// 「이번 주 근무」 카드(v0.3.55) — 게이지는 **지금 퀘스트 하나**다(코어 WeeklyWorkGauge — 맥 줄과 한 벌): 제목 "이번 주 근무 · 40시간 달성하기" →
// 값 "23시간 12분 / 40시간" + 보상 보석 "+50" → 막대(이번 주 누적 ÷ 퀘스트 시간) → 세 칸 칩 → [받기] 줄 → 규칙 한 줄.
// 값은 전부 서버(weekly_work_status())가 준 것이다 — 칸 시간 · 루비(20h 20 · 40h 50 · 60h 200, 기억 weekly-work-reward-decisions)를
// 이 파일에 박지 않는다. 서버에 함수가 없으면 카드가 통째로 빠진다(스토어 showsWeeklyWork).
//
// INV-MeWeeklyWorkViews-d92a4146 이식: ★ **v0.3.58 받기** — 받기 서버가 받을 것이 있다고 말하면(스토어 showsWeeklyClaim — 어느 주든) 칸 칩 아래에
//   [받기 +N] 이 서고 **한 번에 전부** 받는다. 도전 미션 줄과 같은 버튼 · 같은 연출(MeClaimButton · MeClaimBurstView)이고, **실패도 이 카드 안**에서
//   말한다(토스트 · 알림창을 쓰지 않는다). 햅틱은 「미션」 화면 한 곳 — 여기도 달면 한 번 받고 두 번 운다. 옛 서버(받기 칸 없음)는 버튼이 없고
//   cron 이 준 칸을 '+N 받음' 칩으로 알린다.
package com.yehsung.aingcheck.ui.weekly

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.weekly.WeeklyWorkGauge
import com.yehsung.aingcheck.core.rules.weekly.WeeklyWorkStatus
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.canClaimWeeklyWork
import com.yehsung.aingcheck.core.stores.me.claimWeeklyWork
import com.yehsung.aingcheck.core.stores.me.showsWeeklyClaim
import com.yehsung.aingcheck.core.stores.me.showsWeeklyWork
import com.yehsung.aingcheck.core.stores.me.weeklyClaimBurst
import com.yehsung.aingcheck.core.stores.me.weeklyClaimableRuby
import com.yehsung.aingcheck.ui.components.RubyGain
import com.yehsung.aingcheck.ui.components.RubyGainStyle
import com.yehsung.aingcheck.ui.components.RubyIcon
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.missions.MeClaimBurstView
import com.yehsung.aingcheck.ui.missions.MeClaimButton
import com.yehsung.aingcheck.ui.missions.MissionTags
import com.yehsung.aingcheck.ui.shop.MeProgressBar
import com.yehsung.aingcheck.ui.shop.MeType
import com.yehsung.aingcheck.ui.shop.MeType.digits
import com.yehsung.aingcheck.ui.shop.rememberRuby
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

@Composable
fun MeWeeklyWorkCard(store: MeStore, reduceMotion: Boolean = false, frozenBurstProgress: Float? = null, modifier: Modifier = Modifier) {
    if (!store.showsWeeklyWork) return
    val c = AingTheme.colors
    val status = store.weeklyWork
    val gauge = status?.gauge
    Column(
        modifier
            .testTag(MissionTags.WEEKLY)
            .fillMaxWidth()
            .background(c.surface, RoundedCornerShape(AingDimens.groupRadius))
            .padding(AingDimens.cardPadding),
        verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
    ) {
        Header(store, gauge)
        if (status != null && gauge != null) {
            ValueLine(status, gauge)
            // 보이스오버는 막대를 건너뛴다 — 같은 사실은 바로 위 값 줄이 정확히 읽는다(막대 백분율 반올림이 "100%" 라고 거짓말했다).
            MeProgressBar(gauge.fill, done = gauge.isComplete, modifier = Modifier.padding(vertical = 2.dp).clearAndSetSemantics { })
            TierChips(status)
            ClaimRow(store, reduceMotion, frozenBurstProgress)
        } else {
            Text(
                if (store.weeklyWorkState.hasFailed) MeText.weeklyLoadFailed else MeText.loading,
                style = MeType.footnote, color = if (store.weeklyWorkState.hasFailed) c.pending else c.label2,
            )
        }
        Text(MeText.weeklyRule, style = MeType.caption, color = c.label3Text)
    }
}

/** 제목(지금 퀘스트 · 완료) + (방금 받았으면) '+N 받음'. */
@Composable
private fun Header(store: MeStore, gauge: WeeklyWorkGauge?) {
    val c = AingTheme.colors
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        Text(MeText.weeklyHeadline(gauge), style = MeType.headline, color = c.label, modifier = Modifier.weight(1f).semantics { heading() })
        store.weeklyGrantNotice?.let { RubyGain(it.ruby.toInt(), rememberRuby(17f), suffix = MeText.weeklyGrantSuffix, style = RubyGainStyle.Chip) }
    }
}

/** 값 한 줄: 진행 중 "23시간 12분 / 40시간" + 보석 "+50", 완료 "61시간 03분" + 보석 "+270 받았어요"(장부 합 · 0 이면 보석 없음). */
@Composable
private fun ValueLine(status: WeeklyWorkStatus, gauge: WeeklyWorkGauge) {
    val c = AingTheme.colors
    Row(
        Modifier.clearAndSetSemantics { contentDescription = MeText.weeklyGaugeAccessibility(status.displayWorkedSeconds, gauge) },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space2),
    ) {
        Text(
            MeText.weeklyGaugeValue(status.displayWorkedSeconds, gauge), style = MeType.headline.copy(fontWeight = FontWeight.Bold).digits(),
            color = c.label, modifier = Modifier.weight(1f),
        )
        MeText.weeklyGaugeGem(gauge)?.let { gem ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                RubyIcon(rememberRuby(14f), 14.dp)
                Text(gem, style = MeType.subheadline.copy(fontWeight = FontWeight.Bold).digits(), color = if (gauge.isComplete) c.working else c.label)
            }
        }
    }
}

/** 세 칸 칩(보조 — 게이지가 주인공) — 칩은 제 글자만큼 넓고 사이 틈이 줄을 채운다. 한 줄에 안 들어가면 다음 줄로. */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
private fun TierChips(status: WeeklyWorkStatus) {
    val tiers = status.tiers
    if (tiers.isEmpty()) return
    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalArrangement = Arrangement.spacedBy(AingDimens.space1)) {
        tiers.forEach { TierChip(it) }
    }
}

/** 칸 칩 하나 "20h 💎20". 세 모양: 받음(체크 + 초록) · 받을 수 있음(선물 기호 + 강조색) · 아직(회색). 옛 서버는 claimable 이 null 이라 가운데 모양이 없다. */
@Composable
private fun TierChip(tier: WeeklyWorkStatus.Tier) {
    val c = AingTheme.colors
    val isClaimable = tier.claimable == true && !tier.claimed
    val tint = if (tier.claimed) c.working else if (isClaimable) c.accent else c.label2
    Row(
        Modifier
            .background(if (tier.claimed) c.workingTint else if (isClaimable) c.accentTint else c.fill, CircleShape)
            .defaultMinSize(minHeight = 30.dp)
            .padding(horizontal = 10.dp)
            .clearAndSetSemantics { contentDescription = MeText.weeklyTierAccessibility(tier.hours, tier.ruby, tier.claimed, isClaimable) },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        if (tier.claimed) AingIcon(AppIcon.Check, contentDescription = null, size = 12.dp, tint = tint)
        else if (isClaimable) AingIcon(AppIcon.RedeemFill, contentDescription = null, size = 12.dp, tint = tint)
        Text(MeText.weeklyTierHours(tier.hours), style = MeType.footnote.copy(fontWeight = FontWeight.SemiBold), color = tint, maxLines = 1)
        RubyIcon(rememberRuby(14f), 14.dp, Modifier.alpha(if (tier.claimed || isClaimable) 1f else 0.75f))
        Text("${tier.ruby}", style = MeType.footnote.copy(fontWeight = FontWeight.SemiBold).digits(), color = tint, maxLines = 1)
    }
}

/** [받기 +N] 한 줄(v0.3.58) — 받을 것이 있을 때만. **한 번에 전부**라 버튼은 하나다. 실패는 이 줄 왼쪽이 말한다. */
@Composable
private fun ClaimRow(store: MeStore, reduceMotion: Boolean, frozenBurstProgress: Float?) {
    if (!store.showsWeeklyClaim) return
    val c = AingTheme.colors
    Box(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
            if (store.weeklyClaimFailed) {
                Text(MeText.claimFailed, style = MeType.caption.copy(fontWeight = FontWeight.SemiBold), color = c.pending, maxLines = 2, modifier = Modifier.weight(1f))
            } else {
                Spacer(Modifier.weight(1f))
            }
            MeClaimButton(store.weeklyClaimableRuby, inFlight = store.weeklyClaimInFlight, enabled = store.canClaimWeeklyWork) { store.claimWeeklyWork() }
        }
        store.weeklyClaimBurst?.let { burst ->
            MeClaimBurstView(burst.amount, burst.serial, reduceMotion, Modifier.align(Alignment.CenterEnd), frozenBurstProgress)
        }
    }
}
