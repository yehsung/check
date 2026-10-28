// 원본: Sources/CheckMobileKit/Me/MeDailyMissionViews.swift:122-274 @ 3bd04bd (MeDailyMissionsSection · MeDailyMissionRow)
//
// 「일일 미션」 카드 — 머리(소제목 + "받을 보상 N개") + 회색 안내 한 줄 + 일일 줄(서버 sort 순). 사용자 결정(2026-10-22): 게임마다 하루 1판
// = 루비 5, **자정(KST)까지 안 받으면 사라진다**. 줄 수 · 제목 · 보상은 **서버가 주는 대로**다(G §8-18 7 — 일곱 번째 줄도 서버가 주면 선다).
//  ① 제목 · 보상 · 순서는 서버 글자 — 이 파일에 "한 판 하기" 도 5 도 없다. ② 버튼 · 연출은 누적 미션과 같은 부품.
//  ③ 그리는 값은 순수 값(스토어 `MeDailyMissionRowContent`) — 화면은 배치만. ④ 날을 넘긴 줄에는 [받기]가 없다(코어가 판정).
//  ⑤ 일일의 떠 있음 · 실패는 누적과 따로 센다(장부가 두 벌 — 스토어). [전부 받기] 는 **없다**(맥도 없다 — 줄마다 받는 손맛이 요점).
// 갈래는 둘이다(스토어 MeDailyMissionSection): 그릴 것이 없으면 **카드째 없다**(모르는 동안 자리를 잡으면 옛 서버에서 빈 카드가 섰다 사라진다).
package com.yehsung.aingcheck.ui.missions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import com.yehsung.aingcheck.core.stores.me.MeDailyMissionRowContent
import com.yehsung.aingcheck.core.stores.me.MeDailyMissionSection
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.claimDailyMission
import com.yehsung.aingcheck.core.stores.me.dailyClaimBurst
import com.yehsung.aingcheck.core.stores.me.dailyMissionClaimDidFail
import com.yehsung.aingcheck.core.stores.me.dailyMissionSection
import com.yehsung.aingcheck.core.stores.me.isClaimingDailyMission
import com.yehsung.aingcheck.ui.shop.MeType
import com.yehsung.aingcheck.ui.shop.MeType.digits
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

@Composable
fun MeDailyMissionsSection(store: MeStore, reduceMotion: Boolean = false, frozenBurstProgress: Float? = null, modifier: Modifier = Modifier) {
    val section = store.dailyMissionSection as? MeDailyMissionSection.Loaded ?: return
    val c = AingTheme.colors
    MissionCard(modifier.testTag(MissionTags.DAILY)) {
        Column(verticalArrangement = Arrangement.spacedBy(AingDimens.space1)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
                Text(MeText.dailyMissionsTitle, style = MeType.headline, color = c.label, maxLines = 1, modifier = Modifier.weight(1f).semantics { heading() })
                MeText.claimPendingHint(section.claimableCount)?.let {
                    Text(it, style = MeType.footnote.copy(fontWeight = FontWeight.SemiBold).digits(), color = c.accent, maxLines = 1)
                }
            }
            Text(MeText.dailyMissionsResetNote, style = MeType.caption, color = c.label3Text, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Column(verticalArrangement = Arrangement.spacedBy(MeAchievementLayout.rowSpacing)) {
            for (mission in section.rows) {
                val content = MeDailyMissionRowContent.make(mission, store.dailyMissionClaimDidFail(mission.key))
                MissionRow(
                    modifier = Modifier.testTag(MissionTags.row(mission.key)),
                    icon = missionIcon(content.icon),
                    title = content.title,
                    rewardChip = content.rewardChip,
                    fraction = content.fraction,
                    isClaimed = content.isClaimed,
                    caption = content.caption,
                    showsFailure = content.showsFailure,
                    progress = content.progress,
                    claimedMark = content.claimedMark,
                    claimAmount = content.claimAmount,
                    claimInFlight = store.isClaimingDailyMission(mission.key),
                    onClaim = { store.claimDailyMission(mission.key) },
                    accessibility = content.accessibilityLabel,
                    burst = store.dailyClaimBurst(mission.key)?.let { it.serial to it.amount },
                    reduceMotion = reduceMotion,
                    frozenBurstProgress = frozenBurstProgress,
                )
            }
        }
    }
}
