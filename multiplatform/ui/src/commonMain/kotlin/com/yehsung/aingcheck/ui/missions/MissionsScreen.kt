// 원본: Sources/CheckMobileKit/Me/MeMissionsView.swift @ 3bd04bd (MeMissionsRow · MeMissionsView)
//
// 「미션」 화면(폰 1.0.13) — 「일일 미션」 → 「이번 주 근무」 → 「누적 미션」 세 묶음. **맥 0.3.64 [미션] 화면과 같은 순서**다(오늘 → 이번 주 → 통산).
// 사용자 지시(2026-10-23): "나 탭에 미션들 쭈루룩 다 나열하니까 칸이 너무 길어져. 미션 창 버튼 두고 그거 누르면 미션 페이지 따로 있게 해줘".
// "미션"은 **루비를 받는 곳 전부**이고 들어가는 문은 하나다(루트 [미션] 줄 — 나 탭 루트는 W3-b 가 이 줄을 놓는다).
//
// INV-MeMissionsView-ea2bbdd7 이식: 세 묶음은 **서버에 기능이 없으면 자기 절이 통째로 빠진다** — 이 화면은 그 분기를 다시 쓰지 않는다
//   (일일 · 이번 주 · 누적 카드가 각자 숨는다). 줄을 세울지 · 화면이 비었는지도 스토어가 판정한다(showsMissionsRow · missionsPageIsEmpty).
//
// 받기 성공 햅틱은 **이 한 곳**이다(missionClaimBurstSerial). 주간 카드와 누적 절이 각자 달면 한 번 받을 때 두 번 운다(0.3.58 의 사고).
// 당겨서 새로 고치기는 **이 화면의 것만** 다시 읽는다(store.refreshMissions — 루트 새로고침이 아니다).
package com.yehsung.aingcheck.ui.missions

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.missionClaimableCount
import com.yehsung.aingcheck.core.stores.me.missionsPageIsEmpty
import com.yehsung.aingcheck.core.stores.me.refreshMissions
import com.yehsung.aingcheck.core.stores.me.showsMissionsRow
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.shop.BackButton
import com.yehsung.aingcheck.ui.shop.MeType
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import com.yehsung.aingcheck.ui.weekly.MeWeeklyWorkCard
import kotlinx.coroutines.launch

/**
 * 루트 [미션] 줄 — 누르면 「미션」 화면을 쌓는다. 자리는 루비 칩 바로 아래(루비가 어디서 오는지 머리 옆에서 보인다 — 나 탭 루트 W3-b 가 놓는다).
 * 서버에 주간 · 도전 미션이 **둘 다 없으면 줄이 아예 안 선다**(showsMissionsRow). 받을 보상 수는 **탭 막대 배지와 같은 함수**(missionClaimableCount)다.
 */
@Composable
fun MeMissionsRow(store: MeStore, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    if (!store.showsMissionsRow) return
    val c = AingTheme.colors
    val hint = MeText.claimPendingHint(store.missionClaimableCount)
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AingDimens.groupRadius))
            .background(c.surface)
            .clickable(role = Role.Button, onClick = onOpen)
            .clearAndSetSemantics {
                role = Role.Button
                contentDescription = listOfNotNull(MeText.missionsPageTitle, hint ?: MeText.missionsRowDetail).joinToString(", ")
            }
            .heightIn(min = 50.dp)
            .padding(horizontal = AingDimens.cardPadding, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AingDimens.space3),
    ) {
        // 기호는 맥 레일 [미션] 칸과 같은 checklist(같은 곳을 가리키는 그림은 두 기계에서 같아야 한다). 타일 색은 강조색.
        Box(Modifier.size(30.dp).background(c.accent, RoundedCornerShape(7.dp)), contentAlignment = Alignment.Center) {
            AingIcon(AppIcon.Checklist, contentDescription = null, size = 18.dp, tint = c.onAccentFill)
        }
        Text(MeText.missionsPageTitle, style = MeType.body, color = c.label, modifier = Modifier.weight(1f), maxLines = 1)
        if (hint != null) {
            // 배지는 버리지 않는다 — 받을 것이 있다는 사실이 이 줄을 누를 까닭이다. 글자 색은 onAccentFill(accentFill 위).
            Box(Modifier.background(c.accentFill, CircleShape).defaultMinSize(minHeight = 20.dp).padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
                Text(hint, style = MeType.caption.copy(fontWeight = FontWeight.Bold), color = c.onAccentFill)
            }
        } else {
            Text(MeText.missionsRowDetail, style = MeType.subheadline, color = c.label2, maxLines = 1)
        }
        AingIcon(AppIcon.ChevronRight, contentDescription = null, size = 16.dp, tint = c.label3)
    }
}

/** 「미션」 화면. [reduceMotion] 은 호스트(Android 애니메이션 배율 0)가 넘긴다. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MeMissionsScreen(store: MeStore, onBack: (() -> Unit)?, modifier: Modifier = Modifier, reduceMotion: Boolean = false) {
    val c = AingTheme.colors
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    MissionClaimHaptic(store)
    Scaffold(
        modifier,
        containerColor = c.background,
        topBar = {
            TopAppBar(
                title = { Text(MeText.missionsPageTitle, style = MeType.headline, color = c.label) },
                navigationIcon = { if (onBack != null) BackButton(onBack) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.background),
            )
        },
    ) { inner ->
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                scope.launch {
                    refreshing = true
                    try { store.refreshMissions() } finally { refreshing = false }
                }
            },
            modifier = Modifier.padding(inner).fillMaxSize(),
        ) { MeMissionsContent(store, reduceMotion = reduceMotion) }
    }
}

/** 받기 성공 햅틱 — 「미션」 화면 한 곳(missionClaimBurstSerial 이 오를 때 한 번). */
@Composable
private fun MissionClaimHaptic(store: MeStore) {
    val haptics = LocalHapticFeedback.current
    val last = remember { intArrayOf(store.missionClaimBurstSerial) }
    LaunchedEffect(store.missionClaimBurstSerial) {
        if (store.missionClaimBurstSerial > last[0]) haptics.performHapticFeedback(HapticFeedbackType.Confirm)
        last[0] = store.missionClaimBurstSerial
    }
}

/** 화면 본문(일일 → 이번 주 → 누적 · 빈 화면 한 줄). [frozenBurstProgress] 는 스냅숏이 받기 연출을 한 시점에 세울 때만. */
@Composable
fun MeMissionsContent(
    store: MeStore,
    modifier: Modifier = Modifier,
    reduceMotion: Boolean = false,
    scrolls: Boolean = true,
    contentPadding: PaddingValues = PaddingValues(0.dp),
    frozenBurstProgress: Float? = null,
) {
    val c = AingTheme.colors
    Column(
        modifier
            .fillMaxWidth()
            .then(if (scrolls) Modifier.fillMaxSize().verticalScroll(rememberScrollState()) else Modifier)
            .padding(contentPadding)
            .padding(start = AingDimens.sideMargin, end = AingDimens.sideMargin, top = AingDimens.space1, bottom = AingDimens.space6),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
    ) {
        MeDailyMissionsSection(store, reduceMotion, frozenBurstProgress)
        MeWeeklyWorkCard(store, reduceMotion, frozenBurstProgress)
        MeAchievementsSection(store, reduceMotion, frozenBurstProgress)
        if (store.missionsPageIsEmpty) {
            // 들어온 **뒤** 서버가 기능을 잃거나 세션이 끊길 수 있다 — 아무 말도 없는 흰 화면이 남지 않게 한 줄.
            Text(
                MeText.missionsEmpty, style = MeType.subheadline, color = c.label2, textAlign = TextAlign.Center,
                modifier = Modifier.testTag(MissionTags.EMPTY).fillMaxWidth().padding(vertical = AingDimens.space6),
            )
        }
    }
}

