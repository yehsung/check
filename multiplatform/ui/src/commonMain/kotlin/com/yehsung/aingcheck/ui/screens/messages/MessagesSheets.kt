// 원본: Sources/CheckMobileKit/Messages/MessagesComposerView.swift @ 3bd04bd (MessagesStickerSheet · MessagesStickerCell)
// 원본: Sources/CheckMobileKit/Messages/MessagesNewConversationSheet.swift @ 3bd04bd
// 원본: Sources/CheckMobileKit/Messages/MessagesMegaphoneSheet.swift @ 3bd04bd
//
// 메시지 탭의 시트 셋: 아잉이 이모티콘 고르기 · 새 대화(사람 찾기) · 확성기(2단 확인). 시트 껍데기(ModalBottomSheet · 내비 대화상자)는
// 부르는 쪽(대화 화면 · Android 진입 함수)이 정하고, 여기는 내용만 그린다.
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.input.TextFieldLineLimits
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.text.AingSticker
import com.yehsung.aingcheck.core.rules.text.AingStickerText
import com.yehsung.aingcheck.core.rules.text.MegaphoneText
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.MobileLoadText
import com.yehsung.aingcheck.core.stores.messages.PresenceStatus
import com.yehsung.aingcheck.core.wire.CenterLabel
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryEntry
import com.yehsung.aingcheck.ui.components.RubyBalanceChip
import com.yehsung.aingcheck.ui.components.RubyChipStyle
import com.yehsung.aingcheck.ui.components.rememberRubyArt
import com.yehsung.aingcheck.ui.screens.session.kit.AingButton
import com.yehsung.aingcheck.ui.screens.session.kit.AingButtonKind
import com.yehsung.aingcheck.ui.screens.session.kit.AingTextInput
import com.yehsung.aingcheck.ui.screens.session.kit.EmptyStateView
import com.yehsung.aingcheck.ui.screens.session.kit.InlineNotice
import com.yehsung.aingcheck.ui.screens.session.kit.LoadingRow
import com.yehsung.aingcheck.ui.screens.session.kit.NoticeKind
import com.yehsung.aingcheck.ui.screens.session.kit.PersonAvatar
import com.yehsung.aingcheck.ui.screens.session.kit.PersonName
import com.yehsung.aingcheck.ui.screens.session.kit.SheetHeader
import com.yehsung.aingcheck.ui.screens.session.kit.StickerArtState
import com.yehsung.aingcheck.ui.screens.session.kit.hairlineBorder
import com.yehsung.aingcheck.ui.screens.session.kit.isComposing
import com.yehsung.aingcheck.ui.screens.session.kit.rememberNow
import com.yehsung.aingcheck.ui.screens.session.kit.rememberStickerArt
import com.yehsung.aingcheck.ui.screens.session.kit.sf
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

// ---------------------------------------------------------------- 이모티콘

/**
 * 아잉이 이모티콘 고르는 시트(1.0.12). 여섯 칸은 `AingSticker.entries` **선언 순서 그대로**다(사용자가 보는 차례).
 * INV-MessagesComposerView-7534e297 이식: 이 시트는 입력칸 초안을 한 글자도 건드리지 않는다 — setDraft·drafts 를 부르지 않고, 보내는 문은
 *   store.sendSticker 하나다(그 안에서도 초안을 읽지도 쓰지도 않는다 — 맥에서 이모티콘을 보내면 쓰던 글이 사라진 결함). 키보드 포커스도 빼앗지 않는다.
 * INV-MessagesComposerView-8ec8793d 이식: 못 보내는 상태(왕복 중)에서 고르면 조용히 닫지 않는다 — 시트를 연 채 까닭 한 줄(sendingNowNotice)을 세운다.
 *   그 한 줄은 스토어가 아니라 이 시트가 든다(sendNotices 는 스토어 파일 안으로 닫혀 있고, 보여야 하는 자리는 손가락이 있는 이 시트다).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MessagesStickerSheet(store: MessagesStore, peerID: String, onClose: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    var notice by remember(peerID) { mutableStateOf<String?>(null) }
    val art = rememberStickerArt()
    Column(modifier.fillMaxWidth().background(colors.background).testTag(MessagesTags.STICKER_SHEET)) {
        SheetHeader(AingStickerText.gridTitle, onClose, closeLabel = AingStickerText.closeGridLabel)
        Column(Modifier.padding(horizontal = AingDimens.sideMargin).padding(bottom = AingDimens.space6), verticalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
            notice?.let { InlineNotice(it, NoticeKind.Warning) }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(AingDimens.space3), verticalArrangement = Arrangement.spacedBy(AingDimens.space3), maxItemsInEachRow = 3) {
                for (sticker in AingSticker.entries) {
                    StickerCell(sticker, art, Modifier.weight(1f)) {
                        if (store.sendSticker(sticker, peerID)) {
                            notice = null
                            onClose()
                        } else {
                            notice = AingStickerText.sendingNowNotice
                        }
                    }
                }
            }
        }
    }
}

/** 그리드 한 칸. 그림을 못 읽으면 **이름 글자**로 접는다(빈 칸 금지). 라벨은 칸(단추)이 든다 — 그림은 꾸밈용. */
@Composable
private fun StickerCell(sticker: AingSticker, art: StickerArtState, modifier: Modifier, onClick: () -> Unit) {
    val colors = AingTheme.colors
    val image = (art as? StickerArtState.Ready)?.art?.get(sticker)
    Box(
        modifier
            .height(88.dp)
            .background(colors.fill, RoundedCornerShape(AingDimens.innerRadius))
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = AingStickerText.accessibilityLabel(sticker) }
            .testTag(MessagesTags.stickerCell(sticker.rawValue)),
        contentAlignment = Alignment.Center,
    ) {
        when {
            image != null -> Image(image, contentDescription = null, modifier = Modifier.padding(4.dp).size(80.dp))
            art is StickerArtState.Ready -> Text(sticker.label, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = colors.label)
            else -> Unit
        }
    }
}

// ---------------------------------------------------------------- 새 대화

/** 새 대화 시트 글자(Swift 화면 리터럴). */
object NewConversationText {
    const val title = "새 대화"
    const val search = "이름 검색"
    const val loadFailed = "사람 목록을 불러오지 못했어요"
    const val nobody = "대화할 사람이 아직 없어요"
    fun notFound(query: String): String = "‘$query’ 이름을 찾지 못했어요"
    const val searchHint = "이름이나 초성(예: ㅎㄱ)으로 찾아보세요"
    fun workingGroup(count: Int): String = "근무 중 $count"
    const val othersGroup = "근무 안 함"
    const val footnote = "근무 중이 아니어도 메시지를 보낼 수 있어요"
}

/** 사람 찾기 시트(검색 · 근무 중 / 근무 안 함 두 묶음 · 정렬은 스토어 filteredDirectory — 네 무리 · 이름순). */
@Composable
fun MessagesNewConversationSheet(store: MessagesStore, onSelect: (String) -> Unit, onClose: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val query = rememberTextFieldState()
    LaunchedEffect(store) { store.loadDirectory() }
    val q = query.text.toString()
    val people = store.filteredDirectory(q)
    val working = people.filter { it.isWorking }
    val others = people.filter { !it.isWorking }
    Column(modifier.fillMaxWidth().background(colors.background).testTag(MessagesTags.NEW_CONVERSATION_SHEET)) {
        SheetHeader(NewConversationText.title, onClose)
        AingTextInput(
            query, NewConversationText.search,
            Modifier.padding(horizontal = AingDimens.sideMargin).fillMaxWidth()
                .background(colors.fill, RoundedCornerShape(AingDimens.innerRadius)).padding(horizontal = 12.dp, vertical = 10.dp),
            tag = MessagesTags.NEW_CONVERSATION_SEARCH,
        )
        LazyColumn(Modifier.fillMaxWidth().padding(top = 8.dp)) {
            when {
                store.directoryFailed && store.directory.isEmpty() -> item("failed") {
                    EmptyStateView(sf("exclamationmark.triangle", AppIcon.Warning), NewConversationText.loadFailed, MobileLoadText.checkConnection,
                        MobileLoadText.retry, { store.loadDirectory(force = true) })
                }
                !store.directoryLoaded -> item("loading") { Box(Modifier.padding(horizontal = AingDimens.sideMargin)) { LoadingRow() } }
                people.isEmpty() -> item("empty") {
                    EmptyStateView(sf("person.crop.circle.badge.questionmark", AppIcon.Help),
                        if (q.isEmpty()) NewConversationText.nobody else NewConversationText.notFound(q),
                        if (q.isEmpty()) null else NewConversationText.searchHint)
                }
                else -> {
                    if (working.isNotEmpty()) {
                        item("working-title") { GroupTitle(NewConversationText.workingGroup(working.size)) }
                        itemsIndexed(working, key = { _, p -> "w-${p.userID}" }) { index, person -> PersonRowCard(person, index, working.size, onSelect) }
                    }
                    if (others.isNotEmpty()) {
                        item("others-title") { GroupTitle(NewConversationText.othersGroup) }
                        itemsIndexed(others, key = { _, p -> "o-${p.userID}" }) { index, person -> PersonRowCard(person, index, others.size, onSelect) }
                    }
                    item("foot") {
                        Text(NewConversationText.footnote, style = MaterialTheme.typography.bodySmall, color = colors.label2,
                            modifier = Modifier.padding(horizontal = AingDimens.titleMargin, vertical = 12.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun GroupTitle(title: String) {
    Text(title, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold), color = AingTheme.colors.label2,
        modifier = Modifier.padding(start = AingDimens.titleMargin, end = AingDimens.titleMargin, top = 14.dp, bottom = 6.dp))
}

@Composable
private fun PersonRowCard(person: PokeDirectoryEntry, index: Int, count: Int, onSelect: (String) -> Unit) {
    val colors = AingTheme.colors
    val r = AingDimens.groupRadius
    val shape = RoundedCornerShape(if (index == 0) r else 0.dp, if (index == 0) r else 0.dp, if (index == count - 1) r else 0.dp, if (index == count - 1) r else 0.dp)
    val label = listOfNotNull(person.name, person.center?.let { "${it}센터" }, if (person.isWorking) "근무 중" else "근무 안 함",
        person.statusMessage?.let { "상태메시지 $it" }).joinToString(", ")
    Column(Modifier.padding(horizontal = AingDimens.sideMargin).background(colors.surface, shape)) {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = AingDimens.rowHeight)
                .clickable { onSelect(person.userID) }
                .clearAndSetSemantics {
                    contentDescription = label
                    role = Role.Button
                    onClick { onSelect(person.userID); true }
                    testTag = MessagesTags.person(person.userID)
                }
                .padding(horizontal = AingDimens.cardPadding, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            PersonAvatar(person.name, person.userID, person.avatarURL?.absoluteString, 40.dp, status = if (person.isWorking) PresenceStatus.working else null)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                PersonName(person.name, CenterLabel.serverValue(person.center))
                person.statusMessage?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.label2, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            }
        }
        if (index < count - 1) HorizontalDivider(Modifier.padding(start = AingDimens.cardPadding + 52.dp), thickness = AingDimens.hairline, color = colors.separator)
    }
}

// ---------------------------------------------------------------- 확성기

/**
 * 확성기(📢 1.0.7) 작성 시트 — 루비로 **앱을 쓰는 모두에게** 1:1 메시지를 한 줄씩 보낸다. 판정·문구·요청 id·잔량 미러는 코어 MegaphoneStore 에 있고
 * 이 화면은 그리기와 **조합 확정**만 한다.
 * 흐름(2단 확인): 글 → [보내기] → "루비 50개로 N명에게 보낼까요?" → [보내기] → 결과 한 줄.
 * 입력칸은 대화 입력줄과 같은 규칙이다 — 상한을 넘어도 자르지 않고(카운터 빨강) 조합 중이면 단추를 켜 둔다(누르면 조합 글을 확정 글로 친다).
 * [rubyBalance] 는 오목·체스·상점과 같은 미러(조립이 넘긴다 — null 이면 칩을 세우지 않는다).
 */
@Composable
fun MessagesMegaphoneSheet(store: MessagesStore, rubyBalance: Long?, onClose: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val mega = store.megaphone
    val now = rememberNow(store.context.clock, everySeconds = 30)
    val field: TextFieldState = remember { TextFieldState(mega.draft) }
    DisposableEffect(mega) {
        mega.open()
        onDispose { mega.close() }
    }
    // 칸 ↔ 확성기 초안(대화 입력줄과 같은 한 벌 — 조합 중에는 덮지 않는다 · 보내면 스토어가 비운 글이 칸에 선다).
    BindFieldToStore(field, rememberFieldStoreSync(mega), read = { mega.draft }, write = { mega.setDraft(it) })
    val ruby = rememberRubyArt(17f)

    fun commitThen(action: () -> Unit) {
        // 조합 글은 이미 글 안에 있다(Compose) — 확정 글로 싣고 동작한다.
        mega.setDraft(field.text.toString())
        action()
    }

    Column(modifier.fillMaxWidth().background(colors.background).testTag(MessagesTags.MEGAPHONE_SHEET)) {
        Box(Modifier.fillMaxWidth()) {
            SheetHeader(MegaphoneText.badgeTitle, onClose)
            if (rubyBalance != null) {
                Box(Modifier.align(Alignment.CenterEnd).padding(end = 12.dp)) {
                    RubyBalanceChip(rubyBalance, ruby, style = RubyChipStyle.Toolbar)
                }
            }
        }
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin).padding(top = 12.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(AingDimens.space3),
        ) {
            Text(MegaphoneText.explainer, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
            AingTextInput(
                field, MegaphoneText.placeholder,
                Modifier.fillMaxWidth().heightIn(min = 96.dp)
                    .background(colors.surface, RoundedCornerShape(AingDimens.innerRadius))
                    .hairlineBorder(if (mega.isOverLength) colors.danger else colors.separator, AingDimens.innerRadius, if (mega.isOverLength) 1.dp else AingDimens.hairline)
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                lineLimits = TextFieldLineLimits.MultiLine(minHeightInLines = 3, maxHeightInLines = 6),
                enabled = !mega.isSending,
                tag = MessagesTags.MEGAPHONE_FIELD,
            )
            Row(verticalAlignment = Alignment.Top) {
                Text(mega.infoLine(now), style = MaterialTheme.typography.bodySmall, color = colors.label2, modifier = Modifier.weight(1f))
                Text(mega.counterText, style = MaterialTheme.typography.labelSmall, color = if (mega.isOverLength) colors.danger else colors.label2,
                    modifier = Modifier.semantics { contentDescription = "${mega.draftLength}자 중 ${mega.maxLength}자" })
            }
            mega.notice?.let { InlineNotice(it, if (mega.noticeIsError) NoticeKind.Error else NoticeKind.Info) }
            val question = mega.confirmQuestion
            if (mega.isConfirming && question != null) {
                Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(AingDimens.tileRadius)).padding(AingDimens.cardPadding),
                    verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
                    Text(question, style = MaterialTheme.typography.titleMedium, color = colors.label)
                    Text("보내면 되돌릴 수 없어요", style = MaterialTheme.typography.bodySmall, color = colors.label2)
                    // INV-MessagesMegaphoneSheet-e185f735 이식: 실제 요청은 이 단추 하나뿐이다(confirmSend). 위의 [보내기]는 이 단계로 오기만 한다.
                    AingButton(MegaphoneText.sendButton, { commitThen { mega.confirmSend() } }, Modifier.padding(top = 4.dp).testTag(MessagesTags.MEGAPHONE_CONFIRM),
                        fillsWidth = true, isBusy = mega.isSending)
                    AingButton(MegaphoneText.cancelButton, { mega.cancelConfirm() }, kind = AingButtonKind.Gray, fillsWidth = true, enabled = !mega.isSending)
                }
            } else {
                val price = mega.price
                AingButton(
                    if (price == null) MegaphoneText.sendButton else "루비 ${price}개로 ${MegaphoneText.sendButton}",
                    { commitThen { mega.requestSend() } },
                    Modifier.testTag(MessagesTags.MEGAPHONE_SEND),
                    fillsWidth = true, isBusy = mega.isSending,
                    // 조합 중이면 켠다(누르면 확정한 뒤 판정한다 — 대화 입력줄과 같은 규칙).
                    enabled = field.isComposing || mega.canRequestSend,
                )
            }
        }
    }
}
