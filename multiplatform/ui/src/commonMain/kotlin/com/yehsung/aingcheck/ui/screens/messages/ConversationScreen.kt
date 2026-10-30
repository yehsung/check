// 원본: Sources/CheckMobileKit/Messages/MessagesConversationView.swift @ 3bd04bd
// 원본: Sources/CheckMobileKit/Messages/MessagesPokeLogView.swift @ 3bd04bd (찌르기 기록 줄 — 말풍선이 아니다)
// 원본: Sources/CheckMobileKit/Messages/MessagesBubbleTextLayout.swift @ 3bd04bd (한글 어절 단위 줄바꿈 → Compose LineBreak.WordBreak.Phrase)
//
// 한 사람과의 대화(시안 B 04): 머리(뒤로 · 상대 얼굴 · ⋮) · 유리 이름표("근무 중 · 서울" · 상태메시지) · 맨 위 "⏱ 24시간이 지난 메시지는 사라져요" ·
// 날짜 줄 · 말풍선(받은 것 왼쪽 회색, 보낸 것 오른쪽 파랑) · 곁 "1 13:52"(같은 분 묶음의 마지막에만 시각) · 찌르기 줄 · 보내는 중 자리 말풍선 · 입력줄.
//
// 이 화면이 서 있는 동안 스토어는 "그 대화가 보인다"로 안다(conversationDidAppear/Disappear — 화면 인스턴스 표식). 읽음 처리·즉시 이력은 스토어가 판정한다.
// 줄은 LazyColumn(reverseLayout) — 짧은 대화는 입력칸 쪽(아래)에 붙고 처음부터 바닥이 보인다(E§4.3).
//
// 신고·차단 세 입구(E§4.3): ① 머리 ⋮ 메뉴(ReportBlockMenuButton) ② 받은 말풍선 길게 누르기 → [이 메시지 신고하기] ③ 오목 채팅 서랍 ⋮(W4-a 가 같은 단추).
// 신고는 **받은 말풍선만**이다 — 내 말을 내가 신고하는 길은 만들지 않는다.
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.text.AingStickerText
import com.yehsung.aingcheck.core.rules.text.BlockReportText
import com.yehsung.aingcheck.core.stores.messages.MessageEntry
import com.yehsung.aingcheck.core.stores.messages.MessagesBubbleLine
import com.yehsung.aingcheck.core.stores.messages.MessagesConversationHeader
import com.yehsung.aingcheck.core.stores.messages.MessagesConversationItem
import com.yehsung.aingcheck.core.stores.messages.MessagesConversationRules
import com.yehsung.aingcheck.core.stores.messages.MessagesPeerPresence
import com.yehsung.aingcheck.core.stores.messages.MessagesPendingOutgoing
import com.yehsung.aingcheck.core.stores.messages.MessagesPokeLogLine
import com.yehsung.aingcheck.core.stores.messages.MessagesPresenceRules
import com.yehsung.aingcheck.core.stores.messages.MessagesScrollFollow
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.MobileLoadText
import com.yehsung.aingcheck.core.stores.messages.PresenceStatus
import com.yehsung.aingcheck.core.stores.messages.blockPeer
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.session.kit.EmptyStateView
import com.yehsung.aingcheck.ui.screens.session.kit.InlineNotice
import com.yehsung.aingcheck.ui.screens.session.kit.NoticeKind
import com.yehsung.aingcheck.ui.screens.session.kit.PersonAvatar
import com.yehsung.aingcheck.ui.screens.session.kit.READABLE_WIDTH
import com.yehsung.aingcheck.ui.screens.session.kit.StatusDot
import com.yehsung.aingcheck.ui.screens.session.kit.StickerArt
import com.yehsung.aingcheck.ui.screens.session.kit.StickerArtState
import com.yehsung.aingcheck.ui.screens.session.kit.rememberNow
import com.yehsung.aingcheck.ui.screens.session.kit.rememberStickerArt
import com.yehsung.aingcheck.ui.screens.session.kit.sf
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import com.yehsung.aingcheck.ui.components.ModalPresenceMark
import kotlinx.coroutines.launch
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/** 대화 화면 글자(Swift 화면 리터럴). */
object ConversationText {
    const val back = "뒤로"
    const val newMessageJump = "새 메시지로 이동"
    const val copy = "복사"
    const val sending = "보내는 중"
    const val sent = "보냄"
}

/**
 * 대화 화면. [onBack] 은 목록으로 돌아간다. [onLeave] 는 차단·"신고하면서 차단" 뒤에 부른다 — 그 대화는 이미 숨었으니 목록으로 빠져나온다.
 * [composerState] 는 계측 시험(IME 재생)이 입력칸 상태를 쥐려고 넘긴다.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalUuidApi::class)
@Composable
fun ConversationScreen(
    store: MessagesStore,
    peerID: String,
    onBack: () -> Unit,
    onLeave: () -> Unit = onBack,
    modifier: Modifier = Modifier,
    composerState: TextFieldState? = null,
) {
    val colors = AingTheme.colors
    val token = rememberSaveable(peerID) { Uuid.random().toString() }
    DisposableEffect(store, peerID, token) {
        store.conversationDidAppear(peerID, token)
        onDispose { store.conversationDidDisappear(token) }
    }
    var showsBlock by rememberSaveable(peerID) { mutableStateOf(false) }
    var reportTarget by remember(peerID) { mutableStateOf<MessagesReportTarget?>(null) }
    var showsStickers by rememberSaveable(peerID) { mutableStateOf(false) }

    val now = rememberNow(store.context.clock, everySeconds = 60)
    val items = store.conversationItems(peerID)
    val header = store.conversationHeader(peerID)
    val board = if (header.avatarName == null) null else store.presenceBoard(now)
    val presence = board?.peers?.get(peerID)
    val statusMessage = board?.statuses?.get(peerID)
    val peerDisplayName = store.peerName(peerID) ?: MessagesConversationHeader.fallbackTitle
    val stickerArt = rememberStickerArt()
    val scope = rememberCoroutineScope()

    Column(modifier.fillMaxSize().background(colors.background).imePadding().testTag(MessagesTags.CONVERSATION_SCREEN)) {
        ConversationTopBar(
            header = header,
            peerID = peerID,
            avatarURL = store.peerAvatarURL(peerID),
            presence = presence,
            onBack = onBack,
            onReport = { reportTarget = MessagesReportTarget(peerID, peerDisplayName) },
            onBlock = { showsBlock = true },
        )
        Nameplate(header, presence, statusMessage)
        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
            ConversationList(
                items = items,
                stickerArt = stickerArt,
                blockNotice = store.blockNotice,
                blockNoticeIsError = store.blockNoticeIsError,
                empty = if (items.isEmpty()) MessagesConversationRules.emptyState(store.historyLoaded, store.historyFailed) else null,
                onRetry = { scope.launch { store.retryConversation(peerID) } },
                onReportMessage = { entry -> reportTarget = MessagesReportTarget(peerID, entry.peerName, entry.id, entry.body) },
                modifier = Modifier.widthIn(max = READABLE_WIDTH),
            )
        }
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Box(Modifier.widthIn(max = READABLE_WIDTH)) {
                if (composerState != null) {
                    MessageComposer(store, peerID, onStickerSheet = { showsStickers = true }, state = composerState)
                } else {
                    MessageComposer(store, peerID, onStickerSheet = { showsStickers = true })
                }
            }
        }
    }

    if (showsBlock) {
        ModalPresenceMark()
        ModalBottomSheet(onDismissRequest = { showsBlock = false }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = colors.surface) {
            MessagesBlockConfirmSheet(
                peerName = peerDisplayName,
                onConfirm = {
                    // 차단을 부르는 곳은 이 시트 하나다. 낙관적으로 지우고(스토어) 목록으로 빠져나온다 — 서버 응답을 기다리지 않는다.
                    showsBlock = false
                    store.blockPeer(peerID)
                    onLeave()
                },
                onClose = { showsBlock = false },
            )
        }
    }
    reportTarget?.let { target ->
        ModalPresenceMark()
        ModalBottomSheet(onDismissRequest = { if (!store.isSendingReport) reportTarget = null },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = colors.surface) {
            MessagesReportSheet(
                store = store,
                target = target,
                onSent = { blocked ->
                    reportTarget = null
                    // 신고하면서 차단했으면 이 대화는 이미 사라졌다 — 목록으로 빠져나온다.
                    if (blocked) onLeave()
                },
                onClose = { reportTarget = null },
            )
        }
    }
    if (showsStickers) {
        ModalPresenceMark()
        ModalBottomSheet(onDismissRequest = { showsStickers = false }, containerColor = colors.background) {
            MessagesStickerSheet(store, peerID, onClose = { showsStickers = false })
        }
    }
}

/** 머리: 뒤로 · 가운데 상대 얼굴(이름을 모르면 일반 인물 기호 — 가짜 이니셜 금지) · ⋮(신고 · 차단). */
@Composable
private fun ConversationTopBar(
    header: MessagesConversationHeader,
    peerID: String,
    avatarURL: String?,
    presence: MessagesPeerPresence?,
    onBack: () -> Unit,
    onReport: () -> Unit,
    onBlock: () -> Unit,
) {
    val colors = AingTheme.colors
    Box(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 4.dp)) {
        Box(
            Modifier.align(Alignment.CenterStart).size(AingDimens.minimumTarget + 4.dp)
                .clickable(role = Role.Button, onClick = onBack)
                .semantics { contentDescription = ConversationText.back }
                .testTag(MessagesTags.BACK),
            contentAlignment = Alignment.Center,
        ) { AingIcon(sf("chevron.left", AppIcon.ChevronLeft), null, size = 26.dp, tint = colors.label) }
        Box(Modifier.align(Alignment.Center).clearAndSetSemantics { }) {
            val name = header.avatarName
            if (name != null) {
                PersonAvatar(name, peerID, avatarURL, 40.dp, status = presence?.status, ringColor = colors.background)
            } else {
                AingIcon(sf(MessagesConversationHeader.unknownAvatarSymbol, AppIcon.AccountCircle), null, size = 36.dp, tint = colors.label2)
            }
        }
        ReportBlockMenuButton(onReport, onBlock, Modifier.align(Alignment.CenterEnd))
    }
}

/** 유리 이름표: 이름 + "● 근무 중 · 서울" + 상태메시지(있으면 한 줄). 보이스오버는 이 이름표가 읽는다. */
@Composable
private fun Nameplate(header: MessagesConversationHeader, presence: MessagesPeerPresence?, statusMessage: String?) {
    val colors = AingTheme.colors
    val line = MessagesPresenceRules.headerLine(presence)
    val label = listOfNotNull(header.accessibilityLabel, line, statusMessage?.let { "상태메시지 $it" }).joinToString(", ")
    Box(Modifier.fillMaxWidth().padding(bottom = 8.dp), contentAlignment = Alignment.Center) {
        Column(
            Modifier
                .background(colors.glass, RoundedCornerShape(16.dp))
                .padding(horizontal = 14.dp, vertical = 4.dp)
                .clearAndSetSemantics { contentDescription = label; heading() },
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(1.dp),
        ) {
            Text(header.title, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = colors.label, maxLines = 1)
            if (line != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    val status = presence?.status
                    if (status != null && status != PresenceStatus.off) StatusDot(status, 6.dp)
                    Text(line, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = colors.label2, maxLines = 1)
                }
            }
            if (statusMessage != null) {
                Text(statusMessage, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = colors.label2,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 260.dp))
            }
        }
    }
}

/**
 * 줄 목록. 맨 아래가 첫 항목(reverseLayout). 바닥 따라가기는 코어 MessagesScrollFollow(맥 v0.3.31 M4) 그대로:
 * 바닥 근처면 새 말을 따라 내려가고, 위로 올려 읽는 중이면 끌어내리지 않고 "새 메시지 ↓"를 세운다. 내가 보낸 말(찌르기 포함)은 언제나 따라간다.
 */
@Composable
private fun ConversationList(
    items: List<MessagesConversationItem>,
    stickerArt: StickerArtState,
    blockNotice: String?,
    blockNoticeIsError: Boolean,
    empty: com.yehsung.aingcheck.core.stores.messages.MessagesEmptyState?,
    onRetry: () -> Unit,
    onReportMessage: (MessageEntry) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = AingTheme.colors
    val listState = rememberLazyListState()
    val follow = remember { MessagesScrollFollow() }
    var showsNewButton by remember { mutableStateOf(false) }
    val density = LocalDensity.current.density
    val scope = rememberCoroutineScope()

    LaunchedEffect(listState) {
        var lastViewport = 0
        snapshotFlow { Triple(listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset, listState.layoutInfo.viewportSize.height to listState.layoutInfo.totalItemsCount) }
            .collect { (index, offset, sizes) ->
                val (viewport, count) = sizes
                val distance = if (index == 0) offset / density.toDouble() else 1e6
                follow.measured(contentHeight = count.toDouble() + 1.0, distanceToBottom = distance, viewportChanged = viewport != lastViewport)
                lastViewport = viewport
                showsNewButton = follow.showsNewMessageButton
            }
    }
    val last = items.lastOrNull()
    LaunchedEffect(last?.id) {
        if (last == null) return@LaunchedEffect
        if (follow.lastItemChanged(last.isMine)) listState.animateScrollToItem(0)
        showsNewButton = follow.showsNewMessageButton
    }

    Box(modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), state = listState, reverseLayout = true, contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.Bottom)) {
            items(items.asReversed(), key = { it.id }) { item ->
                when (item) {
                    is MessagesConversationItem.day -> DaySeparator(item.label)
                    is MessagesConversationItem.poke -> PokeLogRow(item.line)
                    is MessagesConversationItem.bubble -> BubbleRow(
                        item.line, stickerArt,
                        // 신고는 받은 말풍선만이다.
                        onReport = if (item.line.entry.isMine) null else ({ onReportMessage(item.line.entry) }),
                        modifier = Modifier.padding(top = if (item.line.startsGroup) 7.dp else 0.dp),
                    )
                    is MessagesConversationItem.pending -> PendingBubbleRow(item.item, stickerArt)
                }
            }
            if (empty != null) {
                item("empty") {
                    EmptyStateView(sf(empty.symbol, AppIcon.Forum), empty.title, empty.hint,
                        if (empty.showsRetry) MobileLoadText.retry else null, if (empty.showsRetry) onRetry else null, Modifier.padding(top = 40.dp))
                }
            }
            if (blockNotice != null) {
                item("block-notice") { InlineNotice(blockNotice, if (blockNoticeIsError) NoticeKind.Error else NoticeKind.Info, Modifier.padding(bottom = 4.dp)) }
            }
            item("expiry") { ExpiryNote(Modifier.padding(top = 8.dp, bottom = 2.dp), centered = true) }
        }
        if (showsNewButton) {
            Box(
                Modifier.align(Alignment.BottomCenter).padding(bottom = 8.dp)
                    .heightIn(min = MessagesScrollFollow.newMessageButtonMinHeight.dp)
                    .background(colors.glass, CircleShape)
                    .clickable {
                        follow.jumpedToBottom()
                        showsNewButton = false
                        scope.launch { listState.animateScrollToItem(0) }
                    }
                    .semantics { contentDescription = ConversationText.newMessageJump }
                    .padding(horizontal = 16.dp)
                    .testTag(MessagesTags.NEW_MESSAGE_BUTTON),
                contentAlignment = Alignment.Center,
            ) {
                Text(MessagesScrollFollow.newMessageButtonTitle, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold), color = colors.accent)
            }
        }
    }
}

/** 날짜 줄("오늘" / "어제" / "9월 8일") — 가운데 작은 글자. */
@Composable
private fun DaySeparator(label: String) {
    Text(label, style = MaterialTheme.typography.labelMedium, color = AingTheme.colors.label2, textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth().padding(top = 11.dp, bottom = 5.dp).semantics { heading() })
}

/** 찌르기 줄 — **말풍선이 아니다**(가운데 작은 회색 줄). 답장·읽음 표시·복사·신고 대상이 아니다(길게 눌러도 메뉴가 없다). */
@Composable
private fun PokeLogRow(line: MessagesPokeLogLine) {
    val colors = AingTheme.colors
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp).clearAndSetSemantics { contentDescription = line.text },
        horizontalArrangement = Arrangement.spacedBy(5.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AingIcon(sf(line.symbol, AppIcon.TouchAppFill), null, size = 12.dp, tint = colors.label2)
        Text(line.text, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Normal), color = colors.label2, textAlign = TextAlign.Center)
    }
}

/** 말풍선 반대쪽 최소 여백(시안 말풍선 최대 폭 약 73%). */
private val OPPOSITE_INSET = 64.dp

/** 말풍선 글자 반경(시안 `.b-bub` 19). */
private val BUBBLE_RADIUS = 19.dp

/** 이모티콘 그림 한 변(맥 MessagePanelLayout.stickerSide 와 같은 120 — 글자 크기를 따라 키우지 않는다). */
private val STICKER_SIDE = 120.dp

/**
 * 말풍선 한 줄. 받은 것은 왼쪽(bubbleIn), 보낸 것은 오른쪽(accentFill · 흰 글자). 곁 글자("1 13:52")는 말풍선 바깥 아래쪽에 가로로.
 * 길게 누르면 [복사](원문 그대로 — 붙여넣어 다시 보내면 그림이 된다) · 받은 말풍선이면 [이 메시지 신고하기].
 *
 * INV-MessagesConversationView-21fa1bf0 이식: 줄 전체 라벨(TalkBack)은 이모티콘이면 날것 토큰이 아니라 이름("아잉이 기쁨")으로 읽는다 —
 *   clearAndSetSemantics 라 그림 쪽 문구가 줄 라벨에 섞이지 않는다. 평범한 본문은 preview 가 한 글자도 바꾸지 않는다.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun BubbleRow(line: MessagesBubbleLine, stickerArt: StickerArtState, onReport: (() -> Unit)?, modifier: Modifier = Modifier) {
    val entry = line.entry
    val clipboard = LocalClipboardManager.current
    var menu by remember { mutableStateOf(false) }
    val description = buildList {
        add((if (entry.isMine) "나" else entry.peerName) + ": " + AingStickerText.preview(entry.body))
        add(line.clockText)
        if (line.showsUnreadOne) add(MessagesConversationRules.unreadOneAccessibilityLabel)
    }.joinToString(", ")
    val actions = buildList {
        add(CustomAccessibilityAction(ConversationText.copy) { clipboard.setText(AnnotatedString(entry.body)); true })
        if (onReport != null) add(CustomAccessibilityAction(BlockReportText.reportMessageAction) { onReport(); true })
    }
    Row(
        modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = description; customActions = actions; testTag = MessagesTags.bubble(entry.id) },
        horizontalArrangement = if (entry.isMine) Arrangement.End else Arrangement.Start,
        verticalAlignment = Alignment.Bottom,
    ) {
        if (entry.isMine) {
            Spacer(Modifier.size(OPPOSITE_INSET, 1.dp))
            BubbleMeta(line)
            Spacer(Modifier.size(6.dp, 1.dp))
        }
        Box(Modifier.weight(1f, fill = false)) {
            Box(Modifier.combinedClickable(onClick = {}, onLongClick = { menu = true })) {
                BubbleContent(entry.body, entry.isMine, stickerArt, isPending = false)
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(
                    text = { Text(ConversationText.copy) },
                    leadingIcon = { AingIcon(sf("doc.on.doc", AppIcon.ContentCopy), null, size = 20.dp) },
                    onClick = { menu = false; clipboard.setText(AnnotatedString(entry.body)) },
                    modifier = Modifier.testTag(MessagesTags.MENU_COPY),
                )
                if (onReport != null) {
                    DropdownMenuItem(
                        text = { Text(BlockReportText.reportMessageAction, color = AingTheme.colors.danger) },
                        leadingIcon = { AingIcon(sf("exclamationmark.bubble", AppIcon.Feedback), null, size = 20.dp, tint = AingTheme.colors.danger) },
                        onClick = { menu = false; onReport() },
                        modifier = Modifier.testTag(MessagesTags.MENU_REPORT_MESSAGE),
                    )
                }
            }
        }
        if (!entry.isMine) {
            Spacer(Modifier.size(6.dp, 1.dp))
            BubbleMeta(line)
            Spacer(Modifier.size(OPPOSITE_INSET, 1.dp))
        }
    }
}

/** 곁 글자: "1"(상대가 아직 안 읽음) · "13:52"(같은 분 묶음의 마지막에만). */
@Composable
private fun BubbleMeta(line: MessagesBubbleLine) {
    val colors = AingTheme.colors
    if (!line.showsUnreadOne && !line.showsTime) return
    Row(Modifier.padding(bottom = 2.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.Bottom) {
        if (line.showsUnreadOne) {
            Text(MessagesConversationRules.unreadOneText, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = colors.accent)
        }
        if (line.showsTime) {
            Text(line.clockText, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = colors.label2)
        }
    }
}

/**
 * 말풍선 속(글자 또는 이모티콘 그림).
 * INV-MessagesConversationView-f38e2916 이식: 판정하는 자리는 StickerArt.drawable 하나다(코어 AingStickerArtNames.drawable) — 자리 말풍선도
 *   같은 함수를 부른다. 한쪽이 parse 만 보면 그림이 깨진 배포본에서 두 자리가 갈리고, 보낸 순간엔 글자였다가 이력이 오면 그림이 된다.
 * INV-MessagesConversationView-f7222ee5 이식: 그림을 못 읽은 이모티콘은 날것 토큰이 아니라 "아잉이 기쁨"으로 접은 글자 말풍선이다
 *   (AingStickerText.preview — 평범한 본문은 손대지 않는다). 그림을 아직 읽는 중이면 같은 크기의 빈 자리를 잡아 둔다(높이가 튀지 않게).
 * INV-MessagesConversationView-dc9db4cd 이식: 이모티콘 그림 자체에는 라벨을 달지 않는다(contentDescription = null) — 읽는 것은 바깥 줄 라벨이다.
 */
@Composable
private fun BubbleContent(body: String, isMine: Boolean, stickerArt: StickerArtState, isPending: Boolean) {
    val colors = AingTheme.colors
    val drawn = StickerArt.drawable(body, stickerArt)
    when {
        drawn != null -> Image(drawn.second, contentDescription = null, modifier = Modifier.size(STICKER_SIDE).alpha(if (isPending) 0.6f else 1f))
        StickerArt.isPendingArt(body, stickerArt) -> Spacer(Modifier.size(STICKER_SIDE))
        else -> Box(
            Modifier
                .background((if (isMine) colors.accentFill else colors.bubbleIn).copy(alpha = if (isPending) 0.6f else 1f), RoundedCornerShape(BUBBLE_RADIUS))
                .padding(start = 13.dp, end = 13.dp, top = 8.dp, bottom = 9.dp),
        ) {
            Text(
                AingStickerText.preview(body),
                // 한글 어절 단위 줄바꿈(기본값은 음절 중간에서 끊겨 "두/었어요"가 된다 — iOS MessagesBubbleTextLayout 의 실측).
                style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Normal, lineBreak = BubbleLineBreak),
                color = if (isMine) colors.onAccentFill else colors.label,
            )
        }
    }
}

/** 보내는 중(또는 서버가 받았지만 이력이 아직 안 들고 온) 내 말풍선. 판정은 말풍선 행과 **같은 한 함수**다. */
@Composable
private fun PendingBubbleRow(item: MessagesPendingOutgoing, stickerArt: StickerArtState) {
    val sending = item.state == MessagesPendingOutgoing.State.sending
    val label = "나: ${AingStickerText.preview(item.body)}, " + if (sending) ConversationText.sending else ConversationText.sent
    Row(
        Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = label; testTag = MessagesTags.pending(item.id) },
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.End),
        verticalAlignment = Alignment.Bottom,
    ) {
        Spacer(Modifier.size(OPPOSITE_INSET, 1.dp))
        if (sending) CircularProgressIndicator(Modifier.size(12.dp), color = AingTheme.colors.label2, strokeWidth = 1.5.dp)
        Box(Modifier.weight(1f, fill = false)) { BubbleContent(item.body, isMine = true, stickerArt = stickerArt, isPending = true) }
    }
}

/** 시험·미리보기: 입력칸 상태 하나(바깥이 쥔다). */
@Composable
fun rememberComposerState(initial: String = ""): TextFieldState = rememberTextFieldState(initial)
