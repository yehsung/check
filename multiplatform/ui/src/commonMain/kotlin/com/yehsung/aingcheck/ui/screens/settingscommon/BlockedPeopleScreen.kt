// 원본: Sources/CheckMobileKit/Me/MeBlockedPeopleView.swift @ 3bd04bd (나 → 설정 → 차단한 사람 — 목록 · [차단 해제] 확인 · 서버 '아직')
//
// 차단은 되돌릴 수 있어야 한다(심사 지침 1.2). 목록·해제는 **메시지 스토어**가 쥔다(MessagesStore + MessagesBlockStore — 차단은 메시지 관계라
// 두 스토어가 나눠 가지면 한쪽이 낡는다). 이 화면은 그 값을 그리고 [차단 해제]만 부른다. 해제도 확인을 지난다 — 손가락이 스쳐 풀리면
// 사용자는 그 사실을 영영 모른다. 서버가 차단 RPC 를 모르면 "고장"이 아니라 "아직"이라고 말한다(스토어 blocksServerNotReady).
// 아바타 사진은 그리지 않는다(이미지 적재기가 아직 없다 — 이름 첫 글자 원, 보고).
package com.yehsung.aingcheck.ui.screens.settingscommon

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.text.BlockReportPlatform
import com.yehsung.aingcheck.core.rules.text.BlockReportText
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.blockedAtLine
import com.yehsung.aingcheck.core.stores.messages.blockedListDidAppear
import com.yehsung.aingcheck.core.stores.messages.loadBlocks
import com.yehsung.aingcheck.core.stores.messages.unblock
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.wire.models.BlockedUser
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import com.yehsung.aingcheck.ui.components.ModalPresenceMark

object BlockedPeopleTags {
    const val LIST = "blocked-list"
    fun unblock(userID: String) = "blocked-unblock:$userID"
    const val CONFIRM = "blocked-unblock-confirm"
}

/** 목록이 비었을 때 카드 안 모양(Swift emptyContent 의 세 갈래 — 순수). */
enum class BlockedEmptyCard { Loading, Failed, Empty }

object BlockedPeopleRules {
    /** 받은 값이 없는 채로 도는 중 → 불러오는 중 · 받은 값 없이 실패 → 다시 시도 · 그 밖 → 빈 안내. */
    fun emptyCard(loading: Boolean, failed: Boolean, loaded: Boolean): BlockedEmptyCard = when {
        loading && !loaded -> BlockedEmptyCard.Loading
        failed && !loaded -> BlockedEmptyCard.Failed
        else -> BlockedEmptyCard.Empty
    }

    /** 사람 줄 구분선 시작 = 안쪽 여백 16 + 아바타 40 + 사이 12. */
    const val AVATAR = 40
    const val DIVIDER_LEADING = 16 + AVATAR + 12
}

/**
 * @param messages 메시지 스토어(조립이 넘긴다). null 이면 빈 안내만 — 화면이 죽지 않게(Swift 약참조와 같은 안전망).
 */
@Composable
fun BlockedPeopleScreen(messages: MessagesStore?, modifier: Modifier = Modifier, scrollable: Boolean = true) {
    val colors = AingTheme.colors
    var pendingID by rememberSaveable { mutableStateOf<String?>(null) }
    if (messages != null) {
        DisposableEffect(messages) {
            messages.blockedListDidAppear()
            onDispose {}
        }
    }
    val scroll = if (scrollable) Modifier.verticalScroll(rememberScrollState()) else Modifier
    Column(
        modifier.fillMaxWidth().background(colors.background).then(scroll).padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.rowSpacing),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
    ) {
        Text(
            BlockReportText.blockedListLede(BlockReportPlatform.phone),
            style = MaterialTheme.typography.bodySmall,
            color = colors.label2,
            modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin),
        )
        if (messages == null) {
            AingCard { EmptyStateView(AppIcon.Block, BlockReportText.blockedEmptyTitle, BlockReportText.blockedEmptyMessage(BlockReportPlatform.phone)) }
            return@Column
        }
        messages.blockedListNotice?.let { InlineNotice(it, NoticeKind.Error) }
        if (messages.blocksServerNotReady) InlineNotice(BlockReportText.serverNotReady, NoticeKind.Info)
        val people = messages.blockedPeople
        if (people.isEmpty()) {
            AingCard {
                when (BlockedPeopleRules.emptyCard(messages.blocksLoading, messages.blocksFailed, messages.blocksLoaded)) {
                    BlockedEmptyCard.Loading -> LoadingRow(MeText.loading)
                    BlockedEmptyCard.Failed -> LoadFailureRow(BlockReportText.blockedListFailed, MeText.retry, isRetrying = messages.blocksLoading) {
                        messages.loadBlocks(force = true)
                    }
                    BlockedEmptyCard.Empty -> EmptyStateView(AppIcon.Block, BlockReportText.blockedEmptyTitle, BlockReportText.blockedEmptyMessage(BlockReportPlatform.phone))
                }
            }
        } else {
            InsetGroup(Modifier.testTag(BlockedPeopleTags.LIST)) {
                people.forEachIndexed { index, person ->
                    BlockedRow(messages, person, isLast = index == people.lastIndex) { pendingID = person.userID }
                }
            }
        }
    }

    val pending = pendingID?.let { id -> messages?.blockedPeople?.firstOrNull { it.userID == id } }
    if (messages != null && pending != null) {
        ModalPresenceMark()
        AlertDialog(
            onDismissRequest = { pendingID = null },
            title = { Text(BlockReportText.unblockConfirmTitle(pending.name)) },
            text = { Text(BlockReportText.unblockConfirmMessage) },
            confirmButton = {
                TextButton(onClick = {
                    pendingID = null
                    messages.unblock(pending.userID)
                }, modifier = Modifier.testTag(BlockedPeopleTags.CONFIRM)) { Text(BlockReportText.unblockConfirm) }
            },
            dismissButton = { TextButton(onClick = { pendingID = null }) { Text(BlockReportText.blockCancel) } },
        )
    }
}

/** 한 줄: 아바타 · 이름 · 차단한 시각 · [차단 해제](틴트 · 작게). */
@Composable
private fun BlockedRow(messages: MessagesStore, person: BlockedUser, isLast: Boolean, askUnblock: () -> Unit) {
    val colors = AingTheme.colors
    val busy = person.userID in messages.unblockingUserIDs
    GroupRow(
        divider = if (isLast) RowDivider.None else RowDivider.Inset(BlockedPeopleRules.DIVIDER_LEADING.dp),
        minHeight = AingDimens.rowHeightTwoLine,
    ) {
        InitialAvatar(person.name, BlockedPeopleRules.AVATAR.dp, colorSeed = person.userID)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(person.name, style = MaterialTheme.typography.bodyLarge, color = colors.label)
            person.blockedAt?.let { at ->
                Text(BlockReportText.blockedAtLine(at, messages.context.clock.now()), style = MaterialTheme.typography.bodySmall, color = colors.label2)
            }
        }
        Spacer(Modifier.width(AingDimens.space2))
        AingButton(
            BlockReportText.unblockAction,
            AingButtonKind.Tinted,
            onClick = askUnblock,
            small = true,
            busy = busy,
            modifier = Modifier.testTag(BlockedPeopleTags.unblock(person.userID)),
        )
    }
}
