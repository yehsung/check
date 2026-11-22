// 원본: Sources/CheckMobileKit/Messages/MessagesMegaphoneFeedView.swift @ 94975fa8 (폰 1.0.19 — 지난 확성기 페이지 · 맥 0.3.86 CheckMegaphoneFeedPanel 의 폰 짝)
//
// 문은 확성기 작성 시트의 설명 아래 '지난 확성기 ›' 하나다(MessagesMegaphoneSheet). 같은 시트 안에서 이 페이지로 넘어가고 [뒤로]로 돌아온다.
// 판정(문 세 갈래 · 커서 · 중복 · 세대 가드)은 전부 코어 MegaphoneFeedStore(맥 · 아이폰과 한 벌)에 있고, 이 파일은 그리기와 누름만 한다.
// 부르는 자리: 페이지가 서면 open()(첫 쪽) · [이전 확성기 더 보기] · [다시 시도] · 당겨서 새로 고침 · 떠 있는 동안 실시간 신호(폰 조립).
// 줄: 얼굴 · 이름 · '내가 보낸' · 시각 · 받은 사람 수 · 본문(마크다운 기호를 벗긴 글 3줄, 넘치면 [더 보기]/[접기]) · ···(남의 글: 신고 · 차단 —
// 시트를 **열기만** 한다). 줄에는 메시지 id 가 없어서 신고는 보낸 사람 신고다. 운영자 [내리기]는 폰에 없다(아이폰과 같다 — 맥에서만).
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.text.ChatMarkdown
import com.yehsung.aingcheck.core.rules.text.MegaphoneFeedItem
import com.yehsung.aingcheck.core.rules.text.MegaphoneFeedRules
import com.yehsung.aingcheck.core.rules.text.MegaphoneFeedText
import com.yehsung.aingcheck.core.stores.messages.MegaphoneFeedStore
import com.yehsung.aingcheck.core.stores.messages.MessagesMegaphoneFeedRules
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.MobileLoadText
import com.yehsung.aingcheck.core.stores.messages.blockPeer
import com.yehsung.aingcheck.ui.components.ModalPresenceMark
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.session.kit.EmptyStateView
import com.yehsung.aingcheck.ui.screens.session.kit.InlineNotice
import com.yehsung.aingcheck.ui.screens.session.kit.LoadingRow
import com.yehsung.aingcheck.ui.screens.session.kit.NoticeKind
import com.yehsung.aingcheck.ui.screens.session.kit.PersonAvatar
import com.yehsung.aingcheck.ui.screens.session.kit.SheetHeader
import com.yehsung.aingcheck.ui.screens.session.kit.rememberNow
import com.yehsung.aingcheck.ui.screens.session.kit.sf
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/** 지난 확성기 페이지(시트 안). [onBack] — 작성 시트로 돌아간다(머리의 ✕ 자리 · 낱말 '뒤로'). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MessagesMegaphoneFeedPage(store: MessagesStore, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val feed = store.megaphoneFeed
    val items = store.visibleMegaphoneFeed
    val now = rememberNow(store.context.clock, everySeconds = 30)
    var expanded by remember { mutableStateOf(emptySet<String>()) }
    var reportTarget by remember { mutableStateOf<MessagesReportTarget?>(null) }
    var blockTarget by remember { mutableStateOf<Pair<String, String>?>(null) }
    var refreshing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    DisposableEffect(feed) {
        feed.open()
        onDispose { feed.close() }
    }
    Column(modifier.fillMaxSize().background(colors.background).testTag(MessagesTags.MEGAPHONE_FEED_PAGE)) {
        SheetHeader(MegaphoneFeedText.title, onBack, closeLabel = "뒤로")
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                scope.launch {
                    refreshing = true
                    try { feed.refresh()?.join() } finally { refreshing = false }
                }
            },
            modifier = Modifier.fillMaxSize(),
        ) {
            LazyColumn(Modifier.fillMaxSize().padding(horizontal = AingDimens.sideMargin)) {
                item("window") {
                    Text(MegaphoneFeedText.windowNote, style = MaterialTheme.typography.bodySmall, color = colors.label2,
                        modifier = Modifier.padding(start = AingDimens.titleMargin - AingDimens.sideMargin, top = 8.dp, bottom = 4.dp))
                }
                store.blockNotice?.let { notice ->
                    item("block-notice") { InlineNotice(notice, if (store.blockNoticeIsError) NoticeKind.Error else NoticeKind.Info) }
                }
                if (items.isEmpty()) {
                    item("empty") { FeedEmptyState(feed) }
                } else {
                    itemsIndexed(items, key = { _, item -> item.id }) { index, item ->
                        val target = MessagesMegaphoneFeedRules.actionTarget(item, store.context.sessionStore.userID)
                        FeedRow(
                            item = item,
                            meta = MessagesMegaphoneFeedRules.metaText(item, now),
                            isExpanded = item.id in expanded,
                            onToggle = { expanded = if (item.id in expanded) expanded - item.id else expanded + item.id },
                            onReport = target?.let { t -> { reportTarget = MessagesReportTarget(t.peerID, t.peerName) } },
                            onBlock = target?.let { t -> { blockTarget = t.peerID to t.peerName } },
                            first = index == 0,
                            last = index == items.lastIndex,
                        )
                    }
                    item("footer") { FeedFooter(feed) }
                }
            }
        }
    }
    reportTarget?.let { target ->
        ModalPresenceMark()
        ModalBottomSheet(onDismissRequest = { if (!store.isSendingReport) reportTarget = null },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = colors.surface) {
            MessagesReportSheet(store = store, target = target, onSent = { reportTarget = null }, onClose = { reportTarget = null })
        }
    }
    blockTarget?.let { (peerID, peerName) ->
        ModalPresenceMark()
        ModalBottomSheet(onDismissRequest = { blockTarget = null }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = colors.surface) {
            MessagesBlockConfirmSheet(
                peerName = peerName,
                onConfirm = {
                    blockTarget = null
                    store.blockPeer(peerID)
                },
                onClose = { blockTarget = null },
            )
        }
    }
}

@Composable
private fun FeedEmptyState(feed: MegaphoneFeedStore) {
    when {
        feed.isAvailable == false -> EmptyStateView(sf("megaphone", AppIcon.Campaign), MegaphoneFeedText.unavailable)
        feed.loadFailed -> EmptyStateView(sf("exclamationmark.triangle", AppIcon.Warning), MegaphoneFeedText.failed, MobileLoadText.checkConnection,
            MobileLoadText.retry, { feed.refresh() })
        !feed.hasLoaded || feed.isLoading -> LoadingRow()
        else -> EmptyStateView(sf("megaphone", AppIcon.Campaign), MegaphoneFeedText.empty)
    }
}

@Composable
private fun FeedFooter(feed: MegaphoneFeedStore) {
    val colors = AingTheme.colors
    Box(Modifier.fillMaxWidth().heightIn(min = 28.dp).padding(top = 10.dp, bottom = 20.dp), contentAlignment = Alignment.Center) {
        when {
            feed.isLoadingMore -> CircularProgressIndicator(Modifier.width(20.dp), strokeWidth = 2.dp)
            feed.loadMoreFailed -> FooterButton(MegaphoneFeedText.loadMoreFailed, colors.pending) { feed.loadMore() }
            feed.hasMore -> FooterButton(MegaphoneFeedText.loadMore, colors.accent) { feed.loadMore() }
        }
    }
}

@Composable
private fun FooterButton(text: String, color: androidx.compose.ui.graphics.Color, onClick: () -> Unit) {
    Text(text, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold), color = color,
        modifier = Modifier.clickable(role = Role.Button, onClick = onClick).padding(8.dp).testTag(MessagesTags.MEGAPHONE_FEED_MORE))
}

private val AVATAR = 32.dp

@Composable
private fun FeedRow(
    item: MegaphoneFeedItem,
    meta: String,
    isExpanded: Boolean,
    onToggle: () -> Unit,
    onReport: (() -> Unit)?,
    onBlock: (() -> Unit)?,
    first: Boolean,
    last: Boolean,
) {
    val colors = AingTheme.colors
    val text = remember(item.body) { ChatMarkdown.plainPreview(item.body) }
    var overflows by remember(item.id) { mutableStateOf(false) }
    val r = AingDimens.groupRadius
    val shape = RoundedCornerShape(topStart = if (first) r else 0.dp, topEnd = if (first) r else 0.dp,
        bottomStart = if (last) r else 0.dp, bottomEnd = if (last) r else 0.dp)
    Column(Modifier.fillMaxWidth().background(colors.surface, shape).testTag(MessagesTags.megaphoneFeedRow(item.id))) {
        Row(Modifier.fillMaxWidth().padding(horizontal = AingDimens.cardPadding, vertical = 10.dp), verticalAlignment = Alignment.Top) {
            PersonAvatar(item.senderName, item.senderID, item.senderAvatarURL?.absoluteString, AVATAR)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(item.senderName, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = colors.label,
                        maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    if (item.isOwn) {
                        Spacer(Modifier.width(6.dp))
                        Text(MegaphoneFeedText.ownBadge, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                            color = colors.accent, maxLines = 1,
                            modifier = Modifier.background(colors.accentTint, RoundedCornerShape(50)).padding(horizontal = 6.dp, vertical = 1.dp))
                    }
                    Spacer(Modifier.weight(1f).width(4.dp))
                    Text(meta, style = MaterialTheme.typography.labelSmall, color = colors.label2, maxLines = 1)
                    if (onReport != null && onBlock != null) ReportBlockMenuButton(onReport, onBlock)
                }
                Text(
                    text, style = MaterialTheme.typography.bodyMedium, color = colors.label,
                    maxLines = if (isExpanded) Int.MAX_VALUE else MegaphoneFeedRules.collapsedLineLimit,
                    overflow = TextOverflow.Ellipsis,
                    // 넘침 판정: 접힌 동안의 글 배치가 줄 제한에 걸렸는가(아이폰은 쌍둥이 높이로 잰다 — Compose 는 배치 결과가 말한다).
                    onTextLayout = { layout -> if (!isExpanded && overflows != layout.hasVisualOverflow) overflows = layout.hasVisualOverflow },
                )
                if (isExpanded || overflows) {
                    Text(if (isExpanded) MegaphoneFeedText.collapse else MegaphoneFeedText.expand,
                        style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold), color = colors.accent,
                        modifier = Modifier.clickable(role = Role.Button, onClick = onToggle))
                }
            }
        }
        if (!last) HorizontalDivider(Modifier.padding(start = AingDimens.cardPadding + AVATAR + 10.dp), color = colors.separator)
    }
}
