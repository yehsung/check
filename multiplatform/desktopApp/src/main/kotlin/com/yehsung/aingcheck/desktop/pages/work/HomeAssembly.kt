// 원본: Sources/check/WorkTimerStoreInsights.swift @ db93317f — 207-261(회고 배너 판정 · 그려진 순간 소비 · X 로 봄) · Sources/check/CheckMenuView.swift:480-500
//       (X → markRetroBannerSeen, onAppear → markRetroBannerDisplayed)
//
// int-w2 배선(pages) — 홈 의존에 조립 때 들어오는 것을 덧씌운다: 회고 배너(공용 패치 19 — MeStore.showsRetroBanner·markRetroBannerSeen·
// markRetroBannerDisplayed, 조립 때 잇는다)와 헤더 아래 자리(AI 토큰·AI 리밋 입구). 이 파일은 공용 코어를 부르지 않는다 — 람다만 받는다.
package com.yehsung.aingcheck.desktop.pages.work

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 회고 배너 손잡이(공용 19). [due] 는 Compose 상태(MeStore.showsRetroBanner)를 읽는 람다여야 바로 다시 그린다. */
class HomeRetroBanner(val due: () -> Boolean, val seen: () -> Unit, val displayed: () -> Unit)

/** [retro] 가 있으면 배너 후보·동작에 회고를 싣고, [middle] 이 주어지면 헤더 아래 자리를 채운다(이미 있으면 그대로). 나머지는 그대로 옮긴다. */
fun HomePageDeps.assembled(retro: HomeRetroBanner?, middle: (@Composable () -> Unit)?): HomePageDeps {
    val base = this
    val a = base.actions
    val actions = if (retro == null) a else HomeBannerActions(
        openRecords = a.openRecords,
        dismissRetro = { retro.seen(); a.dismissRetro() },
        retroDisplayed = { retro.displayed(); a.retroDisplayed() },
        openFeedback = a.openFeedback,
        dismissFeedbackReply = a.dismissFeedbackReply,
        openCakeGift = a.openCakeGift,
        installUpdate = a.installUpdate,
        dismissNotice = a.dismissNotice,
        acceptDuel = a.acceptDuel,
        declineDuel = a.declineDuel,
        openDuel = a.openDuel,
    )
    return HomePageDeps(
        work = base.work,
        commands = base.commands,
        teamStatuses = base.teamStatuses,
        clock = base.clock,
        isSignedIn = base.isSignedIn,
        isTeamless = base.isTeamless,
        myUserId = base.myUserId,
        teamName = base.teamName,
        teamGoalSeconds = base.teamGoalSeconds,
        duelsEnabled = base.duelsEnabled,
        update = base.update,
        syncMessage = base.syncMessage,
        inviteCode = base.inviteCode,
        canSync = base.canSync,
        bannerFeed = if (retro == null) base.bannerFeed else { { base.bannerFeed().let { f -> f.copy(retroDue = f.retroDue || retro.due()) } } },
        actions = actions,
        tickMillis = base.tickMillis,
        middle = base.middle ?: middle,
    )
}

object HomeAiEntryText {
    const val TOKENS = "AI 토큰 ›"
    const val LIMITS = "AI 리밋 ›"
}

/**
 * 헤더 아래 AI 입구 한 줄(맥은 토큰 행 · AI 리밋 카드가 이 자리 — 여기는 그 화면으로 가는 링크만, 보고 unresolved). AI 리밋은 연동 도구가
 * 있을 때만([showsLimits] = AiLimitsRouteRule.showsRoute).
 */
@Composable
fun HomeAiEntryRow(showsLimits: Boolean, onTokens: () -> Unit, onLimits: () -> Unit) {
    val colors = AingTheme.colors
    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(HomeAiEntryText.TOKENS, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = colors.accent,
            modifier = Modifier.clickable(role = Role.Button, onClick = onTokens))
        if (showsLimits) {
            Text(HomeAiEntryText.LIMITS, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = colors.accent,
                modifier = Modifier.clickable(role = Role.Button, onClick = onLimits))
        }
    }
}
