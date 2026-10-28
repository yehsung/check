// 원본: Sources/CheckMobileKit/Messages/MessagesBlockSheets.swift @ 3bd04bd
// 원본: Sources/CheckMobileKit/Messages/MessagesConversationView.swift @ 3bd04bd (moreMenu — [신고하기] · [차단하기] 는 시트만 연다)
//
// 차단 확인 시트와 신고 시트(Play UGC 정책 · E§4.3 "세 입구 그대로": 대화 ⋮ 메뉴 · 받은 말풍선 길게 누르기 · 오목 채팅 서랍 ⋮).
// 세 입구가 같은 두 시트를 쓴다 — 오목 채팅 서랍(W4-a)은 [ReportBlockMenuButton] 과 [MessagesReportSheet] · [MessagesBlockConfirmSheet] 를 그대로 단다.
//
// **차단을 부르는 곳은 확인 시트 하나다**(소스 계약 — 메뉴는 시트만 연다). 확인 없는 차단은 만들지 않는다: 차단은 상대에게 알리지 않는
// 조용한 동작이라, 잘못 눌러도 사용자가 알아채는 신호가 없다(스토어 MessagesBlockStore ② 와 같은 약속).
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.input.TextFieldLineLimits
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.text.AingStickerText
import com.yehsung.aingcheck.core.rules.text.BlockReportPlatform
import com.yehsung.aingcheck.core.rules.text.BlockReportRules
import com.yehsung.aingcheck.core.rules.text.BlockReportText
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.submitReport
import com.yehsung.aingcheck.core.stores.messages.reportSheetDidDisappear
import com.yehsung.aingcheck.core.wire.models.ContentReportReason
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.session.kit.AingButton
import com.yehsung.aingcheck.ui.screens.session.kit.AingButtonKind
import com.yehsung.aingcheck.ui.screens.session.kit.AingButtonSize
import com.yehsung.aingcheck.ui.screens.session.kit.AingTextInput
import com.yehsung.aingcheck.ui.screens.session.kit.GroupRow
import com.yehsung.aingcheck.ui.screens.session.kit.InlineNotice
import com.yehsung.aingcheck.ui.screens.session.kit.InsetGroup
import com.yehsung.aingcheck.ui.screens.session.kit.NoticeKind
import com.yehsung.aingcheck.ui.screens.session.kit.SheetHeader
import com.yehsung.aingcheck.ui.screens.session.kit.sf
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/**
 * 신고 대상(사람 하나 · 또는 그 사람이 보낸 메시지 한 건). [messageID] 가 null 이면 사람 신고.
 * [messageBody] 는 화면에 한 번 보여 줄 원문(서버로 가는 것은 id 다 — 운영자는 서버에서 원문을 본다).
 */
data class MessagesReportTarget(
    val peerID: String,
    val peerName: String,
    val messageID: String? = null,
    val messageBody: String? = null,
) {
    val id: String get() = messageID ?: peerID
}

/**
 * ⋮ 단추 + 메뉴([신고하기] · [차단하기]). 메뉴는 **시트만 연다** — 대화 머리 · 오목 채팅 서랍(W4-a)이 같은 것을 단다.
 */
@Composable
fun ReportBlockMenuButton(onReport: () -> Unit, onBlock: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    var expanded by remember { mutableStateOf(false) }
    Box(modifier) {
        Box(
            Modifier
                .size(AingDimens.minimumTarget)
                .clickable(role = Role.Button) { expanded = true }
                .semantics { contentDescription = BlockReportText.menuAccessibilityLabel }
                .testTag(MessagesTags.MORE_MENU),
            contentAlignment = Alignment.Center,
        ) {
            AingIcon(sf("ellipsis", AppIcon.MoreHoriz), null, size = 22.dp, tint = colors.label)
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(
                text = { Text(BlockReportText.reportAction) },
                leadingIcon = { AingIcon(sf("exclamationmark.bubble", AppIcon.Feedback), null, size = 20.dp) },
                onClick = { expanded = false; onReport() },
                modifier = Modifier.testTag(MessagesTags.MENU_REPORT),
            )
            DropdownMenuItem(
                text = { Text(BlockReportText.blockAction, color = colors.danger) },
                leadingIcon = { AingIcon(sf("nosign", AppIcon.Block), null, size = 20.dp, tint = colors.danger) },
                onClick = { expanded = false; onBlock() },
                modifier = Modifier.testTag(MessagesTags.MENU_BLOCK),
            )
        }
    }
}

/**
 * 차단 확인: 무엇이 막히는지 세 줄 → 무엇이 안 막히는지 한 줄 → 되돌릴 수 있다는 한 줄 → [차단하기].
 * 불투명 시트(surface) — 뒤 화면 색이 빨간 글자 대비를 무너뜨리지 않게.
 */
@Composable
fun MessagesBlockConfirmSheet(peerName: String, onConfirm: () -> Unit, onClose: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val items = BlockReportText.blockConfirmItems(BlockReportPlatform.phone)
    Column(modifier.fillMaxWidth().background(colors.surface).testTag(MessagesTags.BLOCK_SHEET)) {
        SheetHeader(BlockReportText.blockAction, onClose)
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin).padding(top = 8.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
        ) {
            Text(BlockReportText.blockConfirmTitle(peerName), style = MaterialTheme.typography.titleMedium, color = colors.label,
                modifier = Modifier.padding(horizontal = 4.dp))
            InsetGroup(Modifier.background(colors.background, RoundedCornerShape(AingDimens.groupRadius)).semantics(mergeDescendants = true) {
                contentDescription = "차단하면: " + items.joinToString(", ")
            }) {
                items.forEachIndexed { index, item ->
                    GroupRow(dividerInset = if (index == items.size - 1) null else AingDimens.cardPadding + 36.dp) {
                        AingIcon(sf("nosign", AppIcon.Block), null, size = 22.dp, tint = colors.danger)
                        Text(item, style = MaterialTheme.typography.bodyLarge, color = colors.label, modifier = Modifier.weight(1f))
                    }
                }
            }
            Text(BlockReportText.blockConfirmScopeNote, style = MaterialTheme.typography.bodySmall, color = colors.label2, modifier = Modifier.padding(horizontal = 4.dp))
            Text(BlockReportText.blockConfirmUndoNote(BlockReportPlatform.phone), style = MaterialTheme.typography.bodySmall, color = colors.label2,
                modifier = Modifier.padding(horizontal = 4.dp))
            AingButton(
                BlockReportText.blockConfirm, onConfirm, Modifier.padding(top = 4.dp).testTag(MessagesTags.BLOCK_CONFIRM),
                kind = AingButtonKind.Destructive, size = AingButtonSize.Lg, fillsWidth = true,
            )
        }
    }
}

/**
 * 신고 시트: 사유 4개(필수) · 자유 입력(선택 · 상한은 자르지 않고 막는다) · [신고하면서 차단](기본 켬) · "24시간 안에 확인합니다" · [신고 보내기].
 * 보내는 문은 하나다(스토어 submitReport). 성공해야 시트가 닫힌다 — 실패하면 쓴 글을 쥔 채 이유 한 줄을 세운다.
 * [onSent] 의 blocked 면 대화 화면도 목록으로 빠져나온다(그 대화는 이미 숨었다).
 */
@Composable
fun MessagesReportSheet(
    store: MessagesStore,
    target: MessagesReportTarget,
    onSent: (blocked: Boolean) -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = AingTheme.colors
    var reasonRaw by rememberSaveable(target.id) { mutableStateOf<String?>(null) }
    val reason = reasonRaw?.let { raw -> ContentReportReason.entries.firstOrNull { it.rawValue == raw } }
    val detail = rememberTextFieldState()
    var alsoBlock by rememberSaveable(target.id) { mutableStateOf(true) }
    // 사유를 고르면 "사유를 골라 주세요"는 더 이상 참이 아니다 — 스토어 문구는 시트만 지울 수 없어(internal set) 다음 제출까지 가린다.
    var noticeMasked by remember(target.id) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    DisposableEffect(store) { onDispose { store.reportSheetDidDisappear() } }

    val detailText = detail.text.toString()
    val canSubmit = BlockReportRules.canSubmitReport(reason != null, detailText, store.isSendingReport)

    fun close() {
        if (!store.isSendingReport) onClose()
    }

    fun submit() {
        val blocked = alsoBlock
        noticeMasked = false
        scope.launch {
            val sent = store.submitReport(target.peerID, reason, detail.text.toString(), target.messageID, blocked)
            if (sent) onSent(blocked)
        }
    }

    Column(modifier.fillMaxWidth().background(colors.surface).testTag(MessagesTags.REPORT_SHEET)) {
        SheetHeader(BlockReportText.reportTitle, ::close, enabled = !store.isSendingReport)
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin).padding(top = 8.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
        ) {
            Text(
                if (target.messageID == null) BlockReportText.reportLede(target.peerName) else BlockReportText.reportMessageLede,
                style = MaterialTheme.typography.bodyMedium, color = colors.label, modifier = Modifier.padding(horizontal = 4.dp),
            )
            target.messageBody?.let { body ->
                // 이모티콘은 이름으로 읽힌다("아잉이 기쁨") — 날것 토큰은 신고하려는 사람에게 "깨진 메시지"로 보인다. 서버로 가는 것은 id 다.
                Text(
                    AingStickerText.preview(body), style = MaterialTheme.typography.bodyMedium, color = colors.label, maxLines = 3,
                    modifier = Modifier.fillMaxWidth().background(colors.bubbleIn, RoundedCornerShape(AingDimens.innerRadius)).padding(AingDimens.cardPadding),
                )
            }
            Header(BlockReportText.reportReasonHeader)
            InsetGroup(Modifier.background(colors.background, RoundedCornerShape(AingDimens.groupRadius))) {
                val reasons = ContentReportReason.entries
                reasons.forEachIndexed { index, value ->
                    val isSelected = reason == value
                    GroupRow(
                        Modifier
                            .clickable(enabled = !store.isSendingReport, role = Role.RadioButton) {
                                reasonRaw = value.rawValue
                                noticeMasked = true
                            }
                            .semantics { selected = isSelected }
                            .testTag(MessagesTags.reportReason(value.rawValue)),
                        dividerInset = if (index == reasons.size - 1) null else AingDimens.cardPadding,
                    ) {
                        Text(value.label, style = MaterialTheme.typography.bodyLarge, color = colors.label, modifier = Modifier.weight(1f))
                        AingIcon(
                            if (isSelected) sf("checkmark.circle.fill", AppIcon.CheckCircleFill) else sf("circle", AppIcon.Circle), null,
                            size = 22.dp, tint = if (isSelected) colors.accent else colors.label3,
                        )
                    }
                }
            }
            Header(BlockReportText.reportDetailHeader)
            AingTextInput(
                detail, BlockReportText.reportDetailPlaceholder,
                Modifier.fillMaxWidth().heightIn(min = 110.dp).background(colors.fill, RoundedCornerShape(AingDimens.innerRadius)).padding(12.dp),
                lineLimits = TextFieldLineLimits.MultiLine(minHeightInLines = 3, maxHeightInLines = 8),
                enabled = !store.isSendingReport,
                tag = MessagesTags.REPORT_DETAIL,
            )
            BlockReportRules.detailCounterText(detailText)?.let { counter ->
                Text(counter, style = MaterialTheme.typography.labelMedium,
                    color = if (BlockReportRules.isDetailOverflowing(detailText)) colors.danger else colors.label2,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp), textAlign = androidx.compose.ui.text.style.TextAlign.End)
            }
            InsetGroup(Modifier.background(colors.background, RoundedCornerShape(AingDimens.groupRadius))) {
                GroupRow(dividerInset = null, minHeight = AingDimens.rowHeightTwoLine) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(BlockReportText.reportAlsoBlock, style = MaterialTheme.typography.bodyLarge, color = colors.label)
                        Text(BlockReportText.reportAlsoBlockDetail, style = MaterialTheme.typography.bodySmall, color = colors.label2)
                    }
                    Switch(alsoBlock, { alsoBlock = it }, enabled = !store.isSendingReport, modifier = Modifier.testTag(MessagesTags.REPORT_ALSO_BLOCK))
                }
            }
            Text(BlockReportText.reviewPromise, style = MaterialTheme.typography.bodySmall, color = colors.label2, modifier = Modifier.padding(horizontal = 4.dp))
            val notice = store.reportNotice
            if (notice != null && !noticeMasked) InlineNotice(notice, NoticeKind.Error)
            AingButton(
                if (store.isSendingReport) BlockReportText.reportSending else BlockReportText.reportSubmit, ::submit,
                Modifier.padding(top = 4.dp).testTag(MessagesTags.REPORT_SUBMIT),
                size = AingButtonSize.Lg, fillsWidth = true, enabled = canSubmit, isBusy = store.isSendingReport,
            )
        }
    }
}

@Composable
private fun Header(title: String) {
    Text(title, style = MaterialTheme.typography.bodySmall, color = AingTheme.colors.label2, modifier = Modifier.padding(horizontal = 4.dp))
}
