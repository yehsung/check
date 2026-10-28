// 원본: Sources/CheckMobileKit/Me/MeFeedbackView.swift @ 3bd04bd (제보 — 쓰기(종류 · 본문 1000자 · 자동 첨부 안내) + 내가 보낸 제보(상태 · 답장) · 딥링크가 가리킨 제보를 펼쳐 보인다)
//
// 판정은 스토어(W2-c MeStoreFeedback — canSendFeedback · 초안은 전송 성공에서만 비운다 · 새 답장 점)와 와이어 규칙(FeedbackComposer · FeedbackText)이다.
// 이 화면은 그리기와 펼침 상태(저장 상태 — 프로세스가 죽어도 펼친 줄이 돌아온다)만 갖는다. 본문은 사용자가 쓴 글이라 어디에도 적지 않는다.
// 글자 수를 자르지 않는다(조합 중 한글이 깨진다 — E§8). 넘친 초안은 [보내기]가 막는다.
package com.yehsung.aingcheck.ui.screens.me

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.me.MeLoadState
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.canSendFeedback
import com.yehsung.aingcheck.core.stores.me.feedbackAutoAttachNotice
import com.yehsung.aingcheck.core.stores.me.feedbackDidAppear
import com.yehsung.aingcheck.core.stores.me.feedbackDidDisappear
import com.yehsung.aingcheck.core.stores.me.focusedReport
import com.yehsung.aingcheck.core.stores.me.isUnseenReply
import com.yehsung.aingcheck.core.stores.me.loadFeedback
import com.yehsung.aingcheck.core.stores.me.sendFeedback
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.FeedbackComposer
import com.yehsung.aingcheck.core.wire.models.FeedbackKind
import com.yehsung.aingcheck.core.wire.models.FeedbackReport
import com.yehsung.aingcheck.core.wire.models.FeedbackText
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.settingscommon.AingButton
import com.yehsung.aingcheck.ui.screens.settingscommon.AingButtonKind
import com.yehsung.aingcheck.ui.screens.settingscommon.AingCard
import com.yehsung.aingcheck.ui.screens.settingscommon.AingChipLabel
import com.yehsung.aingcheck.ui.screens.settingscommon.InlineNotice
import com.yehsung.aingcheck.ui.screens.settingscommon.LoadFailureRow
import com.yehsung.aingcheck.ui.screens.settingscommon.LoadingRow
import com.yehsung.aingcheck.ui.screens.settingscommon.NoticeKind
import com.yehsung.aingcheck.ui.screens.settingscommon.ScreenGraphemes
import com.yehsung.aingcheck.ui.screens.settingscommon.SectionTitle
import com.yehsung.aingcheck.ui.theme.AingColors
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

object FeedbackTags {
    const val LIST = "feedback-list"
    const val EDITOR = "feedback-editor"
    const val SEND = "feedback-send"
    const val COUNTER = "feedback-counter"
    fun kind(kind: FeedbackKind) = "feedback-kind:${kind.rawValue}"
    fun row(id: String) = "feedback-row:$id"
}

/** 내 제보 목록이 비었을 때의 카드(Swift listContent 의 세 갈래). */
enum class FeedbackEmptyCard { Loading, Failed, Empty }

object FeedbackScreenRules {
    fun emptyCard(state: MeLoadState): FeedbackEmptyCard = when {
        state.isLoading && !state.hasLoaded -> FeedbackEmptyCard.Loading
        state.hasFailed && !state.hasLoaded -> FeedbackEmptyCard.Failed
        else -> FeedbackEmptyCard.Empty
    }

    /** 보냄 성공 · 답장 보냄은 안내(파랑), 그 밖은 경고(앰버). */
    fun noticeKind(notice: String): NoticeKind = if (FeedbackText.isSuccessNotice(notice)) NoticeKind.Info else NoticeKind.Warning

    /** 줄 머리 글자: 종류는 칩이 아니라 시각 앞 글자로(한 카드에 칩 셋이던 것 — w14 비평 29). */
    fun headerLine(report: FeedbackReport, now: SwiftDate): String = "${report.kind.label} · ${FeedbackText.ageText(report.createdAt, now)}"

    /** 펼쳤을 때만 버전 줄(앱 버전이 비면 없음). */
    fun versionLine(report: FeedbackReport, expanded: Boolean): String? {
        val version = report.appVersion
        if (!expanded || version.isNullOrEmpty()) return null
        return MeText.feedbackVersionLine(version, report.osVersion)
    }

    /** 목록 안 몇째 칸으로 스크롤할지(0 = 쓰기 카드 · 1 = 머리 · 2.. = 제보). 가리킨 제보가 목록에 없으면 null(목록이 오면 다시). */
    fun revealIndex(list: List<FeedbackReport>, focusedID: String?): Int? {
        if (focusedID == null) return null
        val index = list.indexOfFirst { it.id == focusedID }
        return if (index < 0) null else index + 2
    }

    /** 펼침 토글(순수 — 저장 상태는 id 목록). */
    fun toggled(expanded: List<String>, id: String): List<String> = if (id in expanded) expanded - id else expanded + id
}

/** 상태 칩 색(뜻 색 — 초록 금지): 미해결 = 앰버 · 진행 = 파랑 · 완료·보류 = 회색. */
private fun statusInk(colors: AingColors, tone: MeText.FeedbackStatusTone) = when (tone) {
    MeText.FeedbackStatusTone.pending -> colors.pending to colors.pendingTint
    MeText.FeedbackStatusTone.accent -> colors.accent to colors.accentTint
    MeText.FeedbackStatusTone.neutral -> colors.label2 to colors.fill
}

@Composable
fun FeedbackScreen(store: MeStore, scope: CoroutineScope, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    var expanded by rememberSaveable { mutableStateOf(listOf<String>()) }
    val list = rememberLazyListState()
    DisposableEffect(store) {
        store.feedbackDidAppear()
        onDispose { store.feedbackDidDisappear() }
    }
    // 두 계기 — 목록이 새로 왔다(처음 연 화면) · 딥링크·알림이 또 가리켰다(이미 떠 있는 화면, 목록은 그대로일 수 있다).
    LaunchedEffect(store.feedbackList, store.feedbackFocusSerial) {
        val focused = store.focusedReport ?: return@LaunchedEffect
        if (focused.id !in expanded) expanded = expanded + focused.id
        FeedbackScreenRules.revealIndex(store.feedbackList, focused.id)?.let { list.animateScrollToItem(it) }
    }
    val now = store.context.clock.now()
    LazyColumn(
        modifier.fillMaxWidth().background(colors.background).testTag(FeedbackTags.LIST),
        state = list,
        contentPadding = PaddingValues(horizontal = AingDimens.sideMargin, vertical = AingDimens.rowSpacing),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
    ) {
        item(key = "compose") { ComposeCard(store, scope) }
        item(key = "mine") { SectionTitle(FeedbackText.mineTitle, Modifier.padding(top = 8.dp)) }
        if (store.feedbackList.isEmpty()) {
            item(key = "empty") {
                AingCard {
                    when (FeedbackScreenRules.emptyCard(store.feedbackState)) {
                        FeedbackEmptyCard.Loading -> LoadingRow(FeedbackText.loading)
                        FeedbackEmptyCard.Failed -> LoadFailureRow(FeedbackText.failed, FeedbackText.retry, isRetrying = store.feedbackState.isLoading) {
                            scope.launch { store.loadFeedback() }
                        }
                        FeedbackEmptyCard.Empty -> Text(FeedbackText.mineEmpty, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
                    }
                }
            }
        } else {
            store.feedbackList.forEach { report ->
                item(key = report.id) {
                    FeedbackRow(
                        report = report,
                        now = now,
                        isExpanded = report.id in expanded,
                        isFocused = store.focusedReportID == report.id,
                        isUnseenReply = store.isUnseenReply(report),
                        toggle = { expanded = FeedbackScreenRules.toggled(expanded, report.id) },
                    )
                }
            }
        }
    }
}

@Composable
private fun ComposeCard(store: MeStore, scope: CoroutineScope) {
    val colors = AingTheme.colors
    AingCard {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            FeedbackKind.entries.forEachIndexed { index, kind ->
                SegmentedButton(
                    selected = store.feedbackKind == kind,
                    onClick = { store.feedbackKind = kind },
                    shape = SegmentedButtonDefaults.itemShape(index, FeedbackKind.entries.size),
                    modifier = Modifier.testTag(FeedbackTags.kind(kind)),
                    icon = {},
                ) { Text(kind.label) }
            }
        }
        Box(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 140.dp)
                .background(colors.fill, RoundedCornerShape(AingDimens.innerRadius))
                .padding(13.dp),
        ) {
            BasicTextField(
                value = store.feedbackDraft,
                onValueChange = { store.feedbackDraft = it },
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.label),
                cursorBrush = SolidColor(colors.accent),
                modifier = Modifier.fillMaxWidth().heightIn(min = 114.dp).testTag(FeedbackTags.EDITOR).semantics { contentDescription = "제보 내용" },
            )
            if (store.feedbackDraft.isEmpty()) Text(FeedbackText.placeholder, style = MaterialTheme.typography.bodyLarge, color = colors.label3Text)
        }
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(store.feedbackAutoAttachNotice, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = colors.label2, modifier = Modifier.weight(1f))
            Text(
                FeedbackComposer.counterText(store.feedbackDraft, ScreenGraphemes),
                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal),
                color = if (FeedbackComposer.isCounterWarning(store.feedbackDraft, ScreenGraphemes)) colors.pending else colors.label2,
                modifier = Modifier.testTag(FeedbackTags.COUNTER),
            )
        }
        store.feedbackNotice?.let { InlineNotice(it, FeedbackScreenRules.noticeKind(it)) }
        AingButton(
            if (store.isSendingFeedback) FeedbackText.sending else FeedbackText.sendAction,
            AingButtonKind.Filled,
            onClick = { scope.launch { store.sendFeedback() } },
            enabled = store.canSendFeedback,
            fillsWidth = true,
            icon = if (store.isSendingFeedback) null else AppIcon.SendFill,
            modifier = Modifier.testTag(FeedbackTags.SEND),
        )
    }
}

@Composable
private fun FeedbackRow(report: FeedbackReport, now: SwiftDate, isExpanded: Boolean, isFocused: Boolean, isUnseenReply: Boolean, toggle: () -> Unit) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(AingDimens.groupRadius)
    val (ink, tint) = statusInk(colors, MeText.feedbackStatusTone(report.status))
    Column(
        Modifier
            .fillMaxWidth()
            .background(colors.surface, shape)
            .then(if (isFocused) Modifier.border(2.dp, colors.accent, shape) else Modifier)
            .clickable(role = Role.Button, onClick = toggle)
            .semantics { stateDescription = if (isExpanded) "눌러서 접기" else "눌러서 펼치기" }
            .padding(AingDimens.cardPadding)
            .testTag(FeedbackTags.row(report.id)),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            AingChipLabel(report.status.label, tint = ink, background = tint)
            Text(FeedbackScreenRules.headerLine(report, now), style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = colors.label2)
        }
        Text(
            report.body,
            style = MaterialTheme.typography.bodyMedium,
            color = colors.label,
            maxLines = if (isExpanded) Int.MAX_VALUE else 3,
            overflow = TextOverflow.Ellipsis,
        )
        FeedbackScreenRules.versionLine(report, isExpanded)?.let {
            Text(it, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = colors.label2)
        }
        report.reply?.let { reply ->
            // 카드 안 카드(파랑 틴트 상자) 대신 왼쪽 선 하나로 답장을 가른다.
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min).padding(top = 2.dp)) {
                Box(Modifier.width(3.dp).fillMaxHeight().background(colors.accentLine, RoundedCornerShape(2.dp)))
                Column(Modifier.padding(start = 12.dp).weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        AingIcon(AppIcon.ReplyFill, contentDescription = null, size = 12.dp, tint = colors.label2)
                        Text(FeedbackText.replyBlockTitle, style = MaterialTheme.typography.labelSmall, color = colors.label2)
                        if (isUnseenReply) AingChipLabel(MeText.feedbackReplyBadge, tint = colors.accent)
                        Box(Modifier.weight(1f))
                        report.adminNoteAt?.let { at ->
                            Text(FeedbackText.ageText(at, now), style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = colors.label2)
                        }
                    }
                    Text(reply, style = MaterialTheme.typography.bodyMedium, color = colors.label, maxLines = if (isExpanded) Int.MAX_VALUE else 3, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}
