// 원본: Sources/CheckMobileKit/Messages/MessagesTab.swift @ 3bd04bd (MessagesListView · MessagesThreadRow · MessagesCountBadge · MessagesWorkingStrip · MessagesExpiryNote · MessagesListText)
//
// 메시지 탭 목록(시안 B 03): 큰 제목 + 부제("안 읽은 메시지 3") · 오른쪽 위 📢(확성기) · 새 대화 · 한 그룹 안의 대화 줄 · 보관 안내 ·
// "지금 근무 중 · 바로 말 걸기" 가로 줄.
//
// 줄 세우기·정렬은 스토어 규칙 하나(MessagesStore.threadItems → MessagesThreadListRules.rows — 네 무리 정렬: 근무중+안읽음 → 근무안함+안읽음 →
// 근무중+다읽음 → 근무안함+다읽음, 같은 무리 안은 최근순)다. **찌르기만 있는 사람도 줄이 선다.** 이 화면은 값을 그대로 그린다(배지·시각·안 읽음을
// 다시 세지 않는다 — iOS 1.0.14 와 같다).
//
// 집중(판 7 · 대표 답 #d_6A32rmcoJZZd "말 걸 수 있는 줄 전부" — iOS 1.0.17 1776440d 의 Android 짝): 상대가 집중이면 대화 목록 줄 이름 뒤 '집중' 칩 ·
// 얼굴 띠는 칩 없이 TalkBack 만 · 내가 집중이면 목록 위 한 줄(입력줄 사유와 같은 문장 — [집중 끄기] 단추는 없다, #d_ldP912RctnTt "안내만").
// 출처는 MessagesStore.focusedPeerIDs · myFocusMode 하나다. 게이트가 꺼진 조립(Windows 플라이아웃)은 둘 다 비어 판 7 전 그림 그대로다.
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.text.MessageNoticeText
import com.yehsung.aingcheck.core.stores.messages.MessagesFocusRules
import com.yehsung.aingcheck.core.stores.messages.MessagesListRules
import com.yehsung.aingcheck.core.stores.messages.MessagesPeerPresence
import com.yehsung.aingcheck.core.stores.messages.MessagesPresenceRules
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.MessagesThreadItem
import com.yehsung.aingcheck.core.stores.messages.MessagesThreadListRules
import com.yehsung.aingcheck.core.stores.messages.MessagesWorkingPerson
import com.yehsung.aingcheck.core.stores.messages.MobileLoadText
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.session.kit.AingCard
import com.yehsung.aingcheck.ui.screens.session.kit.EmptyStateView
import com.yehsung.aingcheck.ui.screens.session.kit.InlineNotice
import com.yehsung.aingcheck.ui.screens.session.kit.LoadingRow
import com.yehsung.aingcheck.ui.screens.session.kit.NoticeKind
import com.yehsung.aingcheck.ui.screens.session.kit.PersonAvatar
import com.yehsung.aingcheck.ui.screens.session.kit.PersonName
import com.yehsung.aingcheck.ui.screens.session.kit.personFocusChip
import com.yehsung.aingcheck.ui.screens.session.kit.READABLE_WIDTH
import com.yehsung.aingcheck.ui.screens.session.kit.rememberNow
import com.yehsung.aingcheck.ui.screens.session.kit.sf
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope

/** 메시지 탭 글자(Swift `MessagesListText`). */
object MessagesListText {
    const val title = "메시지"
    const val newConversation = "새 대화"
    const val megaphone = "확성기"
    const val workingTitle = "지금 근무 중"
    const val workingTrailing = "바로 말 걸기"
    const val nobodyWorking = "지금 근무 중인 사람이 없어요"
    const val historyFailedNotice = "새 메시지를 불러오지 못했어요. 당겨서 다시 시도해 주세요"
    const val loadFailedTitle = "메시지를 불러오지 못했어요"
    const val emptyTitle = "아직 주고받은 메시지가 없어요"
    val emptyMessage: String get() = "${MessageNoticeText.expiry}. 새 대화로 먼저 말을 걸어 보세요"
}

/**
 * 대화 목록 화면. [onOpen] 은 그 사람과의 대화를 연다(경로 push — 조립의 Dest.Conversation). [onNewConversation] · [onMegaphone] 은 시트를 연다.
 * 화면이 서 있는 동안 스토어는 "목록이 보인다"로 안다(listDidAppear · listDidDisappear).
 */
@Composable
fun MessagesListScreen(
    store: MessagesStore,
    onOpen: (String) -> Unit,
    onNewConversation: () -> Unit,
    onMegaphone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = AingTheme.colors
    DisposableEffect(store) {
        store.listDidAppear()
        onDispose { store.listDidDisappear() }
    }
    val now = rememberNow(store.context.clock, everySeconds = 30)
    val presence = store.presenceBoard(now)
    val rows = store.threadItems(now)
    // 집중 중인 상대는 **한 번** 받아 줄마다 묻는다 — 출처는 [보내기] 잠금과 같은 MessagesStore.focusedPeerIDs 하나다(차단 거르기도 거기서).
    val focused = store.focusedPeerIDs
    val scope = rememberCoroutineScope()

    Box(modifier.fillMaxSize().background(colors.background).testTag(MessagesTags.LIST_SCREEN), contentAlignment = Alignment.TopCenter) {
        LazyColumn(Modifier.widthIn(max = READABLE_WIDTH).fillMaxWidth()) {
            item("title") {
                ListTitleBar(
                    subtitle = MessagesListRules.subtitle(store.badgeCount),
                    onMegaphone = onMegaphone,
                    onNewConversation = onNewConversation,
                )
            }
            // 내가 집중 중이면 목록 위 한 줄 — 입력줄 사유 · 서버 거절과 같은 문장("맥에서 집중을 끄면 보낼 수 있어요"). 맥에서 끈 값을 받으면
            // 스스로 사라진다(목록이 설 때 · 앞으로 올 때 · 켜짐일 때 60초 틱이 내 집중을 다시 묻는다 — MessagesStore.myFocusMode).
            MessagesFocusRules.listNotice(store.myFocusMode)?.let { notice ->
                item("focus-notice") {
                    InlineNotice(notice, NoticeKind.Info,
                        Modifier.padding(horizontal = AingDimens.sideMargin, vertical = 4.dp).testTag(MessagesTags.LIST_FOCUS_NOTICE))
                }
            }
            store.blockNotice?.let { notice ->
                item("block-notice") {
                    InlineNotice(notice, if (store.blockNoticeIsError) NoticeKind.Error else NoticeKind.Info,
                        Modifier.padding(horizontal = AingDimens.sideMargin, vertical = 4.dp).testTag(MessagesTags.BLOCK_NOTICE))
                }
            }
            if (store.historyFailed && rows.isNotEmpty()) {
                item("history-failed") {
                    InlineNotice(MessagesListText.historyFailedNotice, NoticeKind.Error, Modifier.padding(horizontal = AingDimens.sideMargin, vertical = 4.dp))
                }
            }
            if (rows.isEmpty()) {
                item("empty") {
                    Box(Modifier.padding(horizontal = AingDimens.sideMargin, vertical = 4.dp)) {
                        AingCard {
                            when {
                                store.historyFailed -> EmptyStateView(
                                    sf("exclamationmark.triangle", AppIcon.Warning), MessagesListText.loadFailedTitle, MobileLoadText.checkConnection,
                                    MobileLoadText.retry, { scope.launch { store.refreshNow() } },
                                )
                                !store.historyLoaded -> LoadingRow()
                                else -> EmptyStateView(
                                    sf("bubble.left.and.bubble.right", AppIcon.Forum), MessagesListText.emptyTitle, MessagesListText.emptyMessage,
                                    MessagesListText.newConversation, onNewConversation,
                                )
                            }
                        }
                    }
                }
            } else {
                itemsIndexed(rows, key = { _, row -> "row-${row.id}" }) { index, row ->
                    ThreadRowCard(row, presence.peers[row.peerUserID], row.peerUserID in focused, index, rows.size) { onOpen(row.peerUserID) }
                }
                item("expiry") {
                    ExpiryNote(Modifier.padding(horizontal = AingDimens.titleMargin).padding(top = 8.dp, bottom = 4.dp))
                }
            }
            if (presence.isKnown) {
                item("working-header") {
                    Row(
                        Modifier.fillMaxWidth().padding(start = AingDimens.titleMargin, end = AingDimens.titleMargin, top = 16.dp, bottom = 8.dp),
                        verticalAlignment = Alignment.Bottom,
                    ) {
                        Text(MessagesListText.workingTitle, style = MaterialTheme.typography.titleLarge, color = colors.label,
                            modifier = Modifier.weight(1f).semantics { heading() })
                        Text(MessagesListText.workingTrailing, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
                    }
                }
                item("working-strip") {
                    Box(Modifier.padding(horizontal = AingDimens.sideMargin).padding(bottom = AingDimens.space6)) {
                        WorkingStrip(presence.working, focused, onOpen, onNewConversation)
                    }
                }
            }
        }
    }
}

/** 큰 제목 줄: "메시지" + 오른쪽 위 📢 · 새 대화 + 부제(안 읽은 메시지 N). */
@Composable
private fun ListTitleBar(subtitle: String?, onMegaphone: () -> Unit, onNewConversation: () -> Unit) {
    val colors = AingTheme.colors
    Column(Modifier.fillMaxWidth().padding(start = AingDimens.titleMargin, end = 8.dp, top = 8.dp, bottom = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(MessagesListText.title, style = MaterialTheme.typography.headlineLarge, color = colors.label,
                modifier = Modifier.weight(1f).semantics { heading() })
            ToolbarCircle(sf("megaphone", AppIcon.Campaign), MessagesListText.megaphone, MessagesTags.MEGAPHONE_BUTTON, onMegaphone)
            ToolbarCircle(sf("square.and.pencil", AppIcon.EditSquare), MessagesListText.newConversation, MessagesTags.NEW_CONVERSATION_BUTTON, onNewConversation)
        }
        if (subtitle != null) {
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = colors.label2, modifier = Modifier.testTag(MessagesTags.LIST_SUBTITLE))
        }
    }
}

/** 오른쪽 위 유리 원 단추(기호는 글자색 — 이모지는 다크 모드에서 혼자 튄다). */
@Composable
internal fun ToolbarCircle(icon: AppIcon, label: String, tag: String, onClick: () -> Unit) {
    val colors = AingTheme.colors
    Box(
        Modifier
            .size(AingDimens.minimumTarget + 4.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label }
            .testTag(tag),
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(38.dp).background(colors.glass, CircleShape), contentAlignment = Alignment.Center) {
            AingIcon(icon, contentDescription = null, size = 20.dp, tint = colors.label)
        }
    }
}

/** 한 그룹 안의 대화 줄(시안 B — 위아래 모서리는 첫·마지막 줄만 둥글다, 구분선은 이름 글자 시작점부터). */
@Composable
private fun ThreadRowCard(row: MessagesThreadItem, presence: MessagesPeerPresence?, isFocused: Boolean, index: Int, count: Int, onClick: () -> Unit) {
    val colors = AingTheme.colors
    val radius = AingDimens.groupRadius
    val shape = RoundedCornerShape(
        topStart = if (index == 0) radius else 0.dp, topEnd = if (index == 0) radius else 0.dp,
        bottomStart = if (index == count - 1) radius else 0.dp, bottomEnd = if (index == count - 1) radius else 0.dp,
    )
    Column(Modifier.padding(horizontal = AingDimens.sideMargin).background(colors.surface, shape)) {
        MessagesThreadRow(row, presence, isFocused, onClick)
        if (index < count - 1) {
            HorizontalDivider(Modifier.padding(start = AingDimens.cardPadding + THREAD_AVATAR + 12.dp), thickness = AingDimens.hairline, color = colors.separator)
        }
    }
}

private val THREAD_AVATAR = 48.dp

/**
 * 목록 한 줄(시안 B `.b-thread-row`). 값은 전부 MessagesThreadItem 이 미리 정한다 — 이 뷰는 조건을 세지 않는다.
 * [isFocused] = 상대가 집중 중(`MessagesStore.focusedPeerIDs`) — 이름 뒤 '집중' 칩 · TalkBack 한 마디. 줄은 그대로 눌려 대화가 열린다(대표 답 "대화는 열고 보내기만 막기").
 */
@Composable
fun MessagesThreadRow(row: MessagesThreadItem, presence: MessagesPeerPresence?, isFocused: Boolean, onClick: () -> Unit) {
    val colors = AingTheme.colors
    val description = MessagesThreadListRules.accessibilityText(row, MessagesPresenceRules.headerLine(presence), isFocused)
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .clearAndSetSemantics {
                contentDescription = description
                role = Role.Button
                onClick { onClick(); true }
                // 표식은 이 블록 안에 둔다 — 안쪽(뒤)에 단 testTag 는 clearAndSetSemantics 가 지운다(계측 시험이 잡은 결함).
                testTag = MessagesTags.threadRow(row.peerUserID)
            }
            .padding(horizontal = AingDimens.cardPadding, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        PersonAvatar(row.peerName, row.peerUserID, row.peerAvatarURL, THREAD_AVATAR, status = presence?.status)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                PersonName(
                    row.peerName, presence?.center, Modifier.weight(1f),
                    style = if (row.isUnread) MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Bold) else MaterialTheme.typography.titleSmall,
                    focusChip = personFocusChip(isFocused),
                )
                Text(
                    row.timeText,
                    style = if (row.isUnread) MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold) else MaterialTheme.typography.bodyMedium,
                    color = if (row.isUnread) colors.accent else colors.label2,
                    maxLines = 1,
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    (if (row.previewNeedsMinePrefix) "나: " else "") + row.previewText,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (row.isUnread) colors.label else colors.label2,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                row.countBadge?.let { CountBadge(it) }
            }
        }
    }
}

/** 안 읽은 개수 배지(파랑 채움 캡슐 · 흰 13 · 최소 22). 시스템 빨강 배지는 탭 막대만 쓴다. */
@Composable
private fun CountBadge(text: String) {
    val colors = AingTheme.colors
    Box(
        Modifier.heightIn(min = 22.dp).widthIn(min = 22.dp).background(colors.accentFill, CircleShape).padding(horizontal = 7.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold), color = colors.onAccentFill)
    }
}

/** 보관 규칙 한 줄("⏱ 24시간이 지난 메시지는 사라져요") — 목록 그룹 아래 · 대화 맨 위가 같은 모양이다. */
@Composable
fun ExpiryNote(modifier: Modifier = Modifier, centered: Boolean = false) {
    val colors = AingTheme.colors
    Row(
        modifier.fillMaxWidth().semantics(mergeDescendants = true) {},
        horizontalArrangement = if (centered) Arrangement.Center else Arrangement.Start,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AingIcon(sf("timer", AppIcon.Timer), contentDescription = null, size = 14.dp, tint = colors.label2)
        Spacer(Modifier.size(4.dp))
        Text(MessageNoticeText.expiry, style = if (centered) MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Normal)
            else MaterialTheme.typography.bodySmall, color = colors.label2)
    }
}

/**
 * "지금 근무 중 · 바로 말 걸기" 가로 줄: 근무 중인 사람(점) + 이름 · 끝에 "새 대화". 아무도 없으면 한 줄 안내 + "새 대화".
 * [focused] = 집중 중인 사람(`MessagesStore.focusedPeerIDs`). 얼굴 띠는 52dp 얼굴과 이름뿐이라 칩을 달지 않고 **TalkBack 만** 잇는다
 * (대표 답 #d_6A32rmcoJZZd — 얼굴 띠는 보이스오버 말만).
 */
@Composable
private fun WorkingStrip(people: List<MessagesWorkingPerson>, focused: Set<String>, onOpen: (String) -> Unit, onNewConversation: () -> Unit) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(AingDimens.groupRadius)
    if (people.isEmpty()) {
        Row(
            Modifier.fillMaxWidth().background(colors.surface, shape).padding(horizontal = AingDimens.cardPadding, vertical = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            NewConversationTile(onNewConversation)
            Text(MessagesListText.nobodyWorking, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
        }
    } else {
        Row(
            Modifier.fillMaxWidth().background(colors.surface, shape).horizontalScroll(rememberScrollState())
                .padding(horizontal = AingDimens.cardPadding, vertical = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            for (person in people) {
                val label = MessagesPresenceRules.workingAccessibilityText(person, person.id in focused)
                Tile(person.name, colors.label, Modifier.clearAndSetSemantics {
                    contentDescription = label
                    role = Role.Button
                    onClick { onOpen(person.id); true }
                }.clickable { onOpen(person.id) }) {
                    PersonAvatar(person.name, person.id, person.avatarURL?.absoluteString, 52.dp, status = person.status)
                }
            }
            NewConversationTile(onNewConversation)
        }
    }
}

@Composable
private fun NewConversationTile(onClick: () -> Unit) {
    val colors = AingTheme.colors
    Tile(MessagesListText.newConversation, colors.label2, Modifier.clearAndSetSemantics {
        contentDescription = MessagesListText.newConversation
        role = Role.Button
        onClick { onClick(); true }
    }.clickable(onClick = onClick)) {
        Box(Modifier.size(52.dp).background(colors.fill, CircleShape), contentAlignment = Alignment.Center) {
            AingIcon(sf("plus", AppIcon.Add), null, size = 22.dp, tint = colors.label2)
        }
    }
}

@Composable
private fun Tile(title: String, titleColor: androidx.compose.ui.graphics.Color, modifier: Modifier, avatar: @Composable () -> Unit) {
    Column(modifier.widthIn(min = 56.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        avatar()
        Text(title, style = MaterialTheme.typography.bodySmall, color = titleColor, maxLines = 1)
    }
}
