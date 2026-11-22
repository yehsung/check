// 원본: Sources/CheckMobileKit/Messages/MessagesConversationView.swift @ 5b6ab3ac(폰 1.0.19 — MessagesPhotoBubble · MessagesPhotoViewer · MessagesPhotoPreviewSheet)
//
// 판 9 1:1 메시지 사진의 화면 셋. 그림은 스토어 캐시의 JPEG 바이트를 그릴 때 푼다(디스크에 남기지 않는다 · 로그 금지).
// 크게 보기에 저장 버튼은 없다(사진 보관함 권한을 묻지 않는다 — 아이폰과 같다). 받은 사진만 길게 눌러 [신고].
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.yehsung.aingcheck.core.stores.messages.MessagesComposerRules
import com.yehsung.aingcheck.core.stores.messages.MessagesPhotoDraft
import com.yehsung.aingcheck.core.stores.messages.MessagesPhotoLoadState
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.canSendPhoto
import com.yehsung.aingcheck.core.stores.messages.cancelPhotoDraftFromPreview
import com.yehsung.aingcheck.core.stores.messages.photoImage
import com.yehsung.aingcheck.core.stores.messages.photoLoadState
import com.yehsung.aingcheck.core.stores.messages.requestPhotoImage
import com.yehsung.aingcheck.core.stores.messages.retryPhotoImage
import com.yehsung.aingcheck.core.stores.messages.sendPhotoDraft
import com.yehsung.aingcheck.core.wire.messages.MessagePhotoLayout
import com.yehsung.aingcheck.core.wire.messages.MessagePhotoText
import com.yehsung.aingcheck.core.wire.models.MessagePhotoAttachment
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.session.kit.AingButton
import com.yehsung.aingcheck.ui.screens.session.kit.AingButtonKind
import com.yehsung.aingcheck.ui.screens.session.kit.InlineNotice
import com.yehsung.aingcheck.ui.screens.session.kit.NoticeKind
import com.yehsung.aingcheck.ui.screens.session.kit.SheetHeader
import com.yehsung.aingcheck.ui.screens.session.kit.sf
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import org.jetbrains.compose.resources.ExperimentalResourceApi
import org.jetbrains.compose.resources.decodeToImageBitmap

/** 말풍선이 사진을 그리는 묶음(뷰는 스토어 안쪽을 몰라도 된다). */
class MessagesPhotoHooks(
    val image: (String) -> ByteArray?,
    val state: (String) -> MessagesPhotoLoadState?,
    val request: (String) -> Unit,
    val retry: (String) -> Unit,
    val open: (MessagePhotoAttachment) -> Unit,
) {
    companion object {
        fun of(store: MessagesStore, open: (MessagePhotoAttachment) -> Unit) = MessagesPhotoHooks(
            image = { store.photoImage(it) }, state = { store.photoLoadState(it) },
            request = { store.requestPhotoImage(it) }, retry = { store.retryPhotoImage(it) }, open = open,
        )
    }
}

/** JPEG 바이트 → 그림(같은 바이트면 다시 풀지 않는다). 못 읽으면 null. */
@OptIn(ExperimentalResourceApi::class)
@Composable
internal fun rememberPhotoBitmap(bytes: ByteArray?): ImageBitmap? =
    remember(bytes) { bytes?.let { runCatching { it.decodeToImageBitmap() }.getOrNull() } }

private val PHOTO_CORNER = 14.dp

/** 사진 말풍선 — 그림(받는 중 · 실패면 눌러 다시) · 누르면 크게 · 길게 누르면 [onLongPress](받은 사진의 신고 메뉴). 크기는 코어 규칙(비율 · 하한 60 · 폰 상한 220×260). */
@Composable
internal fun MessagesPhotoBubble(photo: MessagePhotoAttachment, hooks: MessagesPhotoHooks, messageID: String, onLongPress: (() -> Unit)?) {
    val colors = AingTheme.colors
    val (w, h) = MessagePhotoLayout.bubbleSize(photo.width, photo.height, MessagePhotoLayout.phoneMaxWidth, MessagePhotoLayout.phoneMaxHeight)
    val state = hooks.state(photo.path)
    val bitmap = rememberPhotoBitmap(hooks.image(photo.path))
    LaunchedEffect(photo.path) { hooks.request(photo.path) }
    val shape = RoundedCornerShape(PHOTO_CORNER)
    Box(
        Modifier
            .size(w.dp, h.dp)
            .clip(shape)
            .background(colors.fill, shape)
            .combinedClickable(
                role = Role.Button,
                onClick = { if (state == MessagesPhotoLoadState.failed) hooks.retry(photo.path) else hooks.open(photo) },
                onLongClick = onLongPress,
            )
            .semantics { contentDescription = MessagePhotoText.openLabel }
            .testTag(MessagesTags.photoBubble(messageID)),
        contentAlignment = Alignment.Center,
    ) {
        when {
            bitmap != null -> Image(bitmap, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            state == MessagesPhotoLoadState.failed -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                AingIcon(sf("arrow.clockwise", AppIcon.Refresh), null, size = 16.dp, tint = colors.label2)
                Text(MessagePhotoText.unavailable, style = MaterialTheme.typography.labelSmall, color = colors.label2)
            }
            else -> CircularProgressIndicator(Modifier.size(18.dp).semantics { contentDescription = MessagePhotoText.loadingLabel }, strokeWidth = 2.dp)
        }
    }
}

/** 크게 보기 — 검은 바탕 · 화면에 맞춘 그림 · [닫기]. 저장 버튼은 없다(사진 보관함 쓰기 권한을 묻지 않는다). */
@Composable
internal fun MessagesPhotoViewer(photo: MessagePhotoAttachment, hooks: MessagesPhotoHooks, onClose: () -> Unit) {
    LaunchedEffect(photo.path) { hooks.request(photo.path) }
    val bitmap = rememberPhotoBitmap(hooks.image(photo.path))
    val state = hooks.state(photo.path)
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black).testTag(MessagesTags.PHOTO_VIEWER)) {
            Box(Modifier.fillMaxSize().semantics { contentDescription = MessagePhotoText.photoAccessibility }, contentAlignment = Alignment.Center) {
                when {
                    bitmap != null -> Image(bitmap, contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
                    state == MessagesPhotoLoadState.failed -> Text(MessagePhotoText.unavailable, color = Color.White)
                    else -> CircularProgressIndicator(color = Color.White)
                }
            }
            Box(
                Modifier
                    .padding(start = AingDimens.sideMargin, top = 8.dp)
                    .size(44.dp)
                    .background(Color.White.copy(alpha = 0.18f), CircleShape)
                    .clickable(role = Role.Button, onClick = onClose)
                    .semantics { contentDescription = MessagePhotoText.viewerClose }
                    .testTag(MessagesTags.PHOTO_VIEWER_CLOSE),
                contentAlignment = Alignment.Center,
            ) { AingIcon(sf("xmark", AppIcon.Close), null, size = 18.dp, tint = Color.White) }
        }
    }
}

/** 고른 사진 미리 보기 — 그림 · (입력칸에 글이 있으면) "입력칸의 글도 함께 보내요" + 그 글 · [보내기] · [취소]. */
@Composable
internal fun MessagesPhotoPreviewSheet(store: MessagesStore, peerID: String, draft: MessagesPhotoDraft) {
    val colors = AingTheme.colors
    val caption = store.draft(peerID).trim()
    val bitmap = rememberPhotoBitmap(draft.encoded.jpeg)
    Column(Modifier.fillMaxWidth().testTag(MessagesTags.PHOTO_PREVIEW)) {
        SheetHeader(MessagePhotoText.previewTitle, onClose = { store.cancelPhotoDraftFromPreview() }, enabled = !store.isSending)
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (bitmap != null) {
                Image(
                    bitmap, contentDescription = MessagePhotoText.photoAccessibility, contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxWidth().heightIn(max = 360.dp).clip(RoundedCornerShape(AingDimens.innerRadius)),
                )
            }
            if (caption.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(MessagePhotoText.captionNote, style = MaterialTheme.typography.labelSmall, color = colors.label2)
                    Text(caption, style = MaterialTheme.typography.bodyMedium, color = colors.label, maxLines = 4, overflow = TextOverflow.Ellipsis)
                }
            }
            MessagesComposerRules.noticeLine(store.focusBlock(peerID), store.sendNotices[peerID])?.let { InlineNotice(it, NoticeKind.Warning) }
            AingButton(
                if (store.isSending) MessagePhotoText.sending else MessagePhotoText.previewSend,
                onClick = { store.sendPhotoDraft(peerID) },
                modifier = Modifier.testTag(MessagesTags.PHOTO_PREVIEW_SEND),
                kind = AingButtonKind.Filled, fillsWidth = true, enabled = store.canSendPhoto(peerID), isBusy = store.isSending,
            )
            AingButton(
                MessagePhotoText.previewCancel,
                onClick = { store.cancelPhotoDraftFromPreview() },
                modifier = Modifier.testTag(MessagesTags.PHOTO_PREVIEW_CANCEL),
                kind = AingButtonKind.Gray, fillsWidth = true, enabled = !store.isSending,
            )
        }
    }
}
