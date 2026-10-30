// 원본: Sources/check/CheckMenuView.swift:466-531(배너 슬롯 — 헤더 위) · 547-579(메인: 12시간 배너 → HeaderCard → 대결 신청 → 토큰·리밋 → 팀)
//       · 1579-1700(HeaderCard) · 1994-2163(TeamPanel) · CheckComponents.swift:7-46(WorkTogglePill) · 75-126(PresenceChip·CountChip)
//       · 210-300(TeamMemberRow) · 480-544(LongSessionBanner) · 551-(InlineActionBanner) · CheckAppNoticeCard.swift:64-105(공지 카드)
// W3-c2 — 플라이아웃 FlyoutRoute.Home 의 데스크톱 전용 페이지. 그리는 것은 [HomePageModel] 이 낸 [HomeUi] 뿐이고, 명령은
// [HomePageDeps.commands](WorkWiring.commands — 소셜 생명주기 포함)로만 낸다. 색은 AingTheme 토큰만(D5).
// 맥과 다른 곳: 캐릭터 입구 단추·연속 근무 칩·목표 편집 연필·업데이트 노트 목록·공지 QR 은 이 페이지에 없다(보고 unresolved).
package com.yehsung.aingcheck.desktop.pages.work

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.AppNotice
import com.yehsung.aingcheck.core.wire.models.MemberPresence
import com.yehsung.aingcheck.core.wire.models.TeamMemberStatus
import com.yehsung.aingcheck.desktop.pages.banners.BannerCandidates
import com.yehsung.aingcheck.desktop.pages.banners.BannerQueue
import com.yehsung.aingcheck.desktop.pages.banners.BannerText
import com.yehsung.aingcheck.desktop.pages.banners.DuelInviteBanner
import com.yehsung.aingcheck.desktop.pages.banners.TopBanner
import com.yehsung.aingcheck.desktop.pages.team.TeamPanelUi
import com.yehsung.aingcheck.desktop.pages.team.TeamRow
import com.yehsung.aingcheck.desktop.shellapi.DesktopUpdateState
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkCommands
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkState
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow

/** 배너 [보기]·[닫기]·[수락] 들. 기본값은 아무것도 안 한다(조립 전·시험). 맥 자리: 488-531 · 255-268 · 142-175. */
class HomeBannerActions(
    /** 회고 [보기] = openInsightsPanel(토글 아님) → 데스크톱 FlyoutRoute.Records. */
    val openRecords: () -> Unit = {},
    /** 회고 X = markRetroBannerSeen. */
    val dismissRetro: () -> Unit = {},
    /** 회고가 **그려진 순간** 그 주 몫을 쓴다(markRetroBannerDisplayed — 밀려 못 뜬 팝오버는 소비 안 함). */
    val retroDisplayed: () -> Unit = {},
    /** 답장 [보기] = openFeedbackPanel → FlyoutRoute.Feedback. */
    val openFeedback: () -> Unit = {},
    /** 답장 X = markFeedbackReplyBannerSeen(그려진 것만으로는 소비하지 않는다). */
    val dismissFeedbackReply: () -> Unit = {},
    /** 케이크 [고르기] = openCakeGiftWindow(창 먼저, 플라이아웃 나중). */
    val openCakeGift: () -> Unit = {},
    val installUpdate: () -> Unit = {},
    /** 공지 X = dismissAppNotice. */
    val dismissNotice: () -> Unit = {},
    val acceptDuel: (TopBanner, DuelInviteBanner) -> Unit = { _, _ -> },
    val declineDuel: (TopBanner, DuelInviteBanner) -> Unit = { _, _ -> },
    val openDuel: (TopBanner, DuelInviteBanner) -> Unit = { _, _ -> },
)

/** 배너 후보 중 근무 스냅숏 밖의 것들(스토어가 끝낸 판정). 12시간은 근무 스냅숏이 준다. */
data class HomeBannerFeed(
    val gomoku: DuelInviteBanner? = null,
    val chess: DuelInviteBanner? = null,
    val tetris: DuelInviteBanner? = null,
    val retroDue: Boolean = false,
    val feedbackReplyUnseen: Boolean = false,
    val cakeGiftOpen: Boolean = false,
)

/**
 * 홈의 의존. 흐름 둘([work]·[teamStatuses]·[update])은 모아 보고, 나머지 공급자는 박자([tickMillis])마다 다시 읽는다.
 * @param tickMillis 화면 시계 박자(맥 displayNow 1초). null 이면 박자 없이 한 번만 그린다(스냅숏).
 */
class HomePageDeps(
    val work: DesktopWorkState,
    val commands: DesktopWorkCommands,
    val teamStatuses: StateFlow<List<TeamMemberStatus>>,
    val clock: () -> SwiftDate,
    val isSignedIn: () -> Boolean,
    val isTeamless: () -> Boolean,
    val myUserId: () -> String?,
    val teamName: () -> String,
    val teamGoalSeconds: () -> Long,
    val duelsEnabled: Boolean,
    val update: StateFlow<DesktopUpdateState>? = null,
    val syncMessage: () -> String? = { null },
    val inviteCode: () -> String? = { null },
    val canSync: () -> Boolean = { true },
    val bannerFeed: () -> HomeBannerFeed = { HomeBannerFeed() },
    val actions: HomeBannerActions = HomeBannerActions(),
    val tickMillis: Long? = 1000,
    /** 헤더 아래 · 팀 위 자리(맥 토큰 행 · AI 리밋 카드 — c4 몫). */
    val middle: (@Composable () -> Unit)? = null,
)

class HomePage(private val deps: HomePageDeps) : FlyoutPageHost {
    @Composable
    override fun Content(nav: FlyoutNavigator, widthDip: Double) {
        val snapshot by deps.work.snapshot.collectAsState()
        val members by deps.teamStatuses.collectAsState()
        val update = deps.update?.collectAsState()?.value
        var now by remember { mutableStateOf(deps.clock()) }
        val tick = deps.tickMillis
        if (tick != null) {
            LaunchedEffect(tick) {
                while (true) {
                    delay(tick)
                    now = deps.clock()
                }
            }
        }
        val feed = deps.bannerFeed()
        val inputs = HomeInputs(
            snapshot = snapshot,
            members = members,
            myUserId = deps.myUserId(),
            teamName = deps.teamName(),
            teamGoalSeconds = deps.teamGoalSeconds(),
            syncMessage = deps.syncMessage(),
            inviteCode = deps.inviteCode(),
            canSync = deps.canSync(),
            banners = BannerCandidates(
                isSignedIn = deps.isSignedIn(),
                isTeamless = deps.isTeamless(),
                gomoku = feed.gomoku,
                chess = feed.chess,
                tetris = feed.tetris,
                retroDue = feed.retroDue,
                feedbackReplyUnseen = feed.feedbackReplyUnseen,
                cakeGiftOpen = feed.cakeGiftOpen,
                updateAvailable = update?.updateAvailable == true,
                appNotice = update?.notice,
                duelsEnabled = deps.duelsEnabled,
            ),
        )
        val ui = HomePageModel.build(inputs, now)
        HomeScreen(
            ui = ui,
            update = update,
            appNotice = update?.notice,
            deps = deps,
            modifier = Modifier.width(widthDip.dp).fillMaxHeight(),
        )
    }

    companion object {
        val route: FlyoutRoute = FlyoutRoute.Home
    }
}

@Composable
internal fun HomeScreen(ui: HomeUi, update: DesktopUpdateState?, appNotice: AppNotice?, deps: HomePageDeps, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val actions = deps.actions
    Column(
        modifier = modifier.background(colors.background).verticalScroll(rememberScrollState()).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        val banner = ui.banner
        if (banner != null && BannerQueue.slotOf(banner) == BannerQueue.Slot.ABOVE_HEADER) {
            when (banner) {
                TopBanner.UPDATE -> UpdateBannerView(BannerText.versionText(update?.latestVersion), actions.installUpdate)
                TopBanner.APP_NOTICE -> if (appNotice != null) AppNoticeCardView(appNotice, actions.dismissNotice)
                TopBanner.RETRO -> {
                    InlineBanner(AppIcon.CalendarClock, BannerText.retroTitle, BannerText.view, actions.openRecords, actions.dismissRetro)
                    LaunchedEffect(Unit) { actions.retroDisplayed() }
                }
                TopBanner.FEEDBACK_REPLY ->
                    InlineBanner(AppIcon.ForumFill, BannerText.feedbackReplyTitle, BannerText.view, actions.openFeedback, actions.dismissFeedbackReply)
                TopBanner.CAKE_GIFT -> InlineBanner(AppIcon.RedeemFill, BannerText.cakeGiftTitle, BannerText.cakeGiftButton, actions.openCakeGift, null)
                else -> Unit
            }
        }
        if (banner == TopBanner.LONG_SESSION) {
            LongSessionBannerView(
                onConfirm = { TwelveHourConfirm.choose(TwelveHourConfirm.Choice.CONTINUE, deps.commands) },
                onStopNow = { TwelveHourConfirm.choose(TwelveHourConfirm.Choice.STOP_NOW, deps.commands) },
            )
        }
        HeaderCardView(ui.header, onToggle = { HomePageModel.pressWorkToggle(ui.header.pill.enabled, deps.commands) })
        val invite = ui.duelInvite
        if (banner != null && invite != null) DuelInviteBannerView(banner, invite, actions)
        deps.middle?.invoke()
        TeamPanelView(ui.team)
    }
}

@Composable
private fun Card(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val colors = AingTheme.colors
    Box(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(colors.surface)
            .border(1.dp, colors.separator, RoundedCornerShape(14.dp))
            .padding(12.dp),
    ) { content() }
}

@Composable
private fun HeaderCardView(h: HeaderUi, onToggle: () -> Unit) {
    val colors = AingTheme.colors
    val tint = when (h.tint) {
        HeaderTint.PENDING -> colors.pending
        HeaderTint.WORKING -> colors.working
        HeaderTint.OFF_WORK -> colors.offWork
    }
    Card {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(h.statusText, style = MaterialTheme.typography.labelLarge, color = tint, maxLines = 1)
                    Text(
                        h.todayText,
                        style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold),
                        color = colors.label,
                        maxLines = 1,
                    )
                }
                WorkPill(h.pill, onToggle)
            }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                ProgressBar(h.goalProgress, if (h.goalComplete) colors.working else colors.accent, 5)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(h.weeklyText, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = colors.label2, maxLines = 1)
                    Spacer(Modifier.weight(1f))
                    Text(h.percentText, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = colors.label2, maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun WorkPill(p: WorkPillUi, onToggle: () -> Unit) {
    val colors = AingTheme.colors
    val fill = if (p.isWorking) Brush.horizontalGradient(listOf(colors.pendingDot, colors.danger)) else Brush.horizontalGradient(colors.startStops)
    Row(
        Modifier
            .height(40.dp)
            .alpha(if (p.enabled) 1f else 0.45f)
            .clip(CircleShape)
            .background(fill)
            .clickable(enabled = p.enabled, onClick = onToggle)
            .padding(horizontal = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        AingIcon(if (p.isWorking) AppIcon.StopFill else AppIcon.PlayArrowFill, null, size = 13.dp, tint = colors.onAccentFill)
        Text(p.label, style = MaterialTheme.typography.labelLarge, color = colors.onAccentFill, maxLines = 1)
    }
}

@Composable
private fun ProgressBar(fraction: Double, fill: Color, heightDp: Int) {
    val colors = AingTheme.colors
    val f = fraction.coerceIn(0.0, 1.0).toFloat()
    Box(Modifier.fillMaxWidth().height(heightDp.dp).clip(CircleShape).background(colors.fill)) {
        if (f > 0f) Box(Modifier.fillMaxWidth(f).height(heightDp.dp).clip(CircleShape).background(fill))
    }
}

@Composable
private fun LongSessionBannerView(onConfirm: () -> Unit, onStopNow: () -> Unit) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(12.dp)
    Column(
        Modifier.fillMaxWidth().clip(shape).background(colors.pendingTint).border(1.dp, colors.pending.copy(alpha = 0.55f), shape)
            .padding(horizontal = 11.dp, vertical = 9.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            AingIcon(AppIcon.HourglassEmpty, null, size = 16.dp, tint = colors.pending)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(TwelveHourConfirm.title, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = colors.label, maxLines = 1)
                Text(TwelveHourConfirm.subtitle, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = colors.label2, maxLines = 1)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val btn = RoundedCornerShape(8.dp)
            Box(
                Modifier.weight(1f).height(28.dp).clip(btn).background(colors.pending).clickable(onClick = onConfirm),
                contentAlignment = Alignment.Center,
            ) { Text(TwelveHourConfirm.confirm, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = colors.onAccentFill) }
            Box(
                Modifier.weight(1f).height(28.dp).clip(btn).background(colors.pendingTint)
                    .border(1.dp, colors.pending.copy(alpha = 0.45f), btn).clickable(onClick = onStopNow),
                contentAlignment = Alignment.Center,
            ) { Text(TwelveHourConfirm.stopNow, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = colors.pending) }
        }
    }
}

@Composable
private fun InlineBanner(icon: AppIcon, title: String, actionTitle: String, onAction: () -> Unit, onDismiss: (() -> Unit)?) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(12.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(colors.accentTint).border(1.dp, colors.accentLine, shape)
            .padding(horizontal = 11.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        AingIcon(icon, null, size = 16.dp, tint = colors.accent)
        Text(
            title, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = colors.label,
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
        )
        Box(
            Modifier.height(24.dp).clip(RoundedCornerShape(7.dp)).background(colors.accent).clickable(onClick = onAction).padding(horizontal = 10.dp),
            contentAlignment = Alignment.Center,
        ) { Text(actionTitle, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = colors.onAccentFill) }
        if (onDismiss != null) {
            Box(Modifier.size(20.dp).clickable(onClick = onDismiss), contentAlignment = Alignment.Center) {
                AingIcon(AppIcon.Close, BannerText.dismiss, size = 12.dp, tint = colors.label2)
            }
        }
    }
}

@Composable
private fun UpdateBannerView(versionText: String, onInstall: () -> Unit) {
    val colors = AingTheme.colors
    Card {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(BannerText.updateTitle(versionText), style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = colors.label, maxLines = 1)
            Box(
                Modifier.fillMaxWidth().height(28.dp).clip(RoundedCornerShape(8.dp)).background(colors.accent).clickable(onClick = onInstall),
                contentAlignment = Alignment.Center,
            ) { Text(BannerText.updateNow, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = colors.onAccentFill) }
        }
    }
}

@Composable
private fun AppNoticeCardView(notice: AppNotice, onDismiss: () -> Unit) {
    val colors = AingTheme.colors
    Card {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AingIcon(AppIcon.Smartphone, null, size = 14.dp, tint = colors.accent)
                Text(
                    notice.title, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = colors.label,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                )
                Box(Modifier.size(20.dp).clickable(onClick = onDismiss), contentAlignment = Alignment.Center) {
                    AingIcon(AppIcon.Close, "공지 닫기", size = 12.dp, tint = colors.label2)
                }
            }
            Text(notice.body, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = colors.label2)
            notice.linkLabel?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = colors.label, maxLines = 2) }
        }
    }
}

@Composable
private fun DuelInviteBannerView(banner: TopBanner, invite: DuelInviteBanner, actions: HomeBannerActions) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(12.dp)
    Column(
        Modifier.fillMaxWidth().clip(shape).background(colors.accentTint).border(1.dp, colors.accentLine, shape)
            .padding(horizontal = 11.dp, vertical = 9.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(BannerText.duelInviteTitle(banner, invite.peerName), style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = colors.label, maxLines = 1)
        Text(
            "${BannerText.stakeLabel} ${invite.stake} · ${BannerText.duelInviteSubtitle(banner)}",
            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = colors.label2, maxLines = 1,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val btn = RoundedCornerShape(8.dp)
            Box(Modifier.weight(1f).height(28.dp).clip(btn).background(colors.accent).clickable { actions.acceptDuel(banner, invite) }, contentAlignment = Alignment.Center) {
                Text(BannerText.accept, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = colors.onAccentFill)
            }
            Box(Modifier.weight(1f).height(28.dp).clip(btn).background(colors.fill).clickable { actions.declineDuel(banner, invite) }, contentAlignment = Alignment.Center) {
                Text(BannerText.decline, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = colors.label)
            }
            Box(Modifier.height(28.dp).clip(btn).clickable { actions.openDuel(banner, invite) }.padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
                Text(BannerText.view, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = colors.accent)
            }
        }
    }
}

@Composable
private fun TeamPanelView(t: TeamPanelUi) {
    val colors = AingTheme.colors
    var showsCode by remember { mutableStateOf(false) }
    Card {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.height(27.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    t.teamName, style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold), color = colors.label,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                )
                Row(
                    Modifier.clip(CircleShape).background(colors.workingTint).padding(horizontal = 9.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Box(Modifier.size(6.dp).clip(CircleShape).background(colors.working))
                    Text(t.workingCountLabel, style = MaterialTheme.typography.labelSmall, color = colors.working, maxLines = 1)
                }
                if (t.inviteCode != null) {
                    Box(Modifier.size(24.dp).clickable { showsCode = !showsCode }, contentAlignment = Alignment.Center) {
                        AingIcon(
                            if (showsCode) AppIcon.KeyFill else AppIcon.Key,
                            if (showsCode) "참여코드 숨기기" else "참여코드 보기",
                            size = 15.dp,
                            tint = if (showsCode) colors.accent else colors.label2,
                        )
                    }
                }
            }
            if (t.inviteCode != null && showsCode) {
                Text(t.inviteCode, style = MaterialTheme.typography.labelLarge.copy(fontFamily = FontFamily.Monospace), color = colors.label)
            }
            HorizontalDivider(color = colors.separator)
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                for (row in t.rows) TeamRowView(row)
            }
        }
    }
}

@Composable
private fun TeamRowView(r: TeamRow) {
    val colors = AingTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(26.dp).clip(CircleShape).background(if (r.isMe) colors.accentTint else colors.fill), contentAlignment = Alignment.Center) {
                Text(r.name.take(1), style = MaterialTheme.typography.labelSmall, color = colors.label)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(r.name, style = MaterialTheme.typography.labelLarge, color = colors.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(r.primaryDetail, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = colors.label2, maxLines = 1)
                    if (r.meetsWeeklyGoal) AingIcon(AppIcon.Check, "주간 목표 달성", size = 10.dp, tint = colors.working)
                }
                r.secondaryDetail?.let {
                    Text(it, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = colors.pending, maxLines = 1)
                }
            }
            PresenceChipView(r.presence, r.presenceLabel)
        }
        r.goalFraction?.let { f ->
            Box(Modifier.padding(start = 36.dp)) { ProgressBar(f, colors.accent, 4) }
        }
    }
}

@Composable
private fun PresenceChipView(p: MemberPresence, label: String) {
    val colors = AingTheme.colors
    val (bg, fg) = when (p) {
        MemberPresence.ActiveWorking -> colors.working to colors.onAccentFill
        is MemberPresence.StaleWorking -> colors.pending to colors.onAccentFill
        MemberPresence.OffWork -> colors.fill to colors.label2
    }
    Text(
        label,
        style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp),
        color = fg,
        maxLines = 1,
        modifier = Modifier.clip(CircleShape).background(bg).padding(horizontal = 9.dp, vertical = 4.dp),
    )
}
