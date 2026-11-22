// 원본: Sources/CheckMobileKit/Messages/MessagesStorePhotos.swift · MessagesPhotoImageCache.swift @ 5b6ab3ac(폰 1.0.19 — 맥 0.3.86 WorkTimerStoreMessagePhotos 의 폰 짝)
//
// 판 9(대표 #d_xygj8oZRFlfH 4번 메시지 묶음). 전선 이름 · 키 · 행 모양은 와이어 MessagePhotoWire · MessagePhotoSend 한 곳이다. 맥 · 아이폰과 같은 여섯 가지:
// ① 24시간 머리(history)는 그대로 — 사진은 따로 든 표(photoMeta)로 배우고 **그릴 때만** 얹는다(photoDisplayed). 안 읽음 점 · 읽음 경계는 사진을 모른다.
// ② 사진 칸을 묻는 자리는 둘뿐: 대화를 열 때 한 번(armPhotoMeta), 열린 대화의 머리에 사진 칸을 모르는 말이 생겼을 때(합쳐서 · 0.4초 · 상대마다 하나).
//    이 폰이 보낸 말은 보낸 자리에서 물어본 것으로 친다. 함수가 없는 서버면 다음 대화 열기까지 안 묻는다(사진 줄은 글 '📷 사진'으로 그린다).
// ③ 보내기는 올리기 → send_photo_message, 같은 소문자 uuid 가 파일 이름 · p_client_message_id 를 겸한다. 답을 못 받은 실패는 같은 이름 · 같은 키로
//    한 번 더. 올리기 409 는 우리 앞 시도가 올린 우리 파일이다(성공). 올리기가 거절되면 RPC 로 사유를 가른다.
// ④ 그림은 메모리에만(MessagesPhotoImageCache — 경로가 열쇠). 보이는 말풍선이 그때 한 장씩 받는다. 로그아웃이 통째로 비운다.
// ⑤ 화면을 찍지 않는다 — 사진은 사람이 시스템 사진 고르기로 고른 것뿐이다(사진 권한을 묻지 않는다).
// ⑥ 사진 · 경로 · 글은 사람이 보낸 것 — 로그 금지.
package com.yehsung.aingcheck.core.stores.messages

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.PrivateStorageError
import com.yehsung.aingcheck.core.net.fetchMessagePage
import com.yehsung.aingcheck.core.net.fetchMessagePhotoData
import com.yehsung.aingcheck.core.net.sendPhotoMessage
import com.yehsung.aingcheck.core.net.uploadMessagePhoto
import com.yehsung.aingcheck.core.rules.text.AingStickerText
import com.yehsung.aingcheck.core.rules.text.MessageBody
import com.yehsung.aingcheck.core.rules.text.MessageBodyValidation
import com.yehsung.aingcheck.core.rules.text.MessageNoticeText
import com.yehsung.aingcheck.core.stores.me.EncodedPhoto
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.messages.MessagePhotoSendOutcome
import com.yehsung.aingcheck.core.wire.messages.MessagePhotoText
import com.yehsung.aingcheck.core.wire.messages.MessagePhotoWire
import com.yehsung.aingcheck.core.wire.messages.SendPhotoMessageRequest
import com.yehsung.aingcheck.core.wire.messages.SendPhotoMessageResponse
import com.yehsung.aingcheck.core.wire.messages.withPhoto
import com.yehsung.aingcheck.core.wire.models.MessageHistoryEntry
import com.yehsung.aingcheck.core.wire.models.MessagePhotoAttachment
import com.yehsung.aingcheck.core.wire.models.MessageSendOutcome
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/** 사진 칸 한 줄 — 그 메시지의 사진과 설명(사진만 보냈으면 null). */
data class MessagesPhotoMeta(val attachment: MessagePhotoAttachment, val caption: String?)

/** 고른 사진(미리 보기 · 보내기 전). [id] 가 파일 이름이자 전송 멱등 키다(③). [jpeg] 를 화면이 미리 보기로 그린다. */
class MessagesPhotoDraft(
    val id: String,
    val peer: String,
    val encoded: EncodedPhoto,
    /** 이 이름으로 이미 올렸는가(다시 [보내기]를 누르면 올리기를 건너뛴다). */
    val uploaded: Boolean = false,
) {
    fun withUploaded(value: Boolean) = MessagesPhotoDraft(id, peer, encoded, value)
    override fun equals(other: Any?): Boolean = other is MessagesPhotoDraft && other.id == id && other.peer == peer && other.uploaded == uploaded
    override fun hashCode(): Int = id.hashCode() * 31 + peer.hashCode()
}

/** 사진 한 장의 받기 상태. */
enum class MessagesPhotoLoadState { loading, loaded, failed }

/**
 * 메시지 사진 그림 캐시(맥 0.3.86 MessagePhotoImageCache · 아이폰 MessagesPhotoImageCache 의 짝). **경로가 열쇠**이고 디스크에 남기지 않는다(메모리만 —
 * JPEG 바이트를 들고 화면이 그릴 때 푼다). 계정이 바뀌면 통째로 비운다. 경로마다 받기는 하나만 날고, 실패는 이 세션 동안 기억한다(사람이 실패 칸을 누를 때만 다시).
 */
class MessagesPhotoImageCache(private val capacity: Int = 60) {
    var states: Map<String, MessagesPhotoLoadState> by mutableStateOf(emptyMap())
        private set
    var owner: String? = null
        private set
    private val bytes = LinkedHashMap<String, ByteArray>(16, 0.75f, true)
    private val tasks = HashMap<String, Job>()
    private var epoch = 0

    val inFlightCount: Int get() = tasks.size

    /** 그 경로의 그림 바이트(이 계정 것만). 관찰 칸을 먼저 읽는다 — 받기가 끝나면 부른 화면이 다시 그려진다. */
    fun image(path: String, owner: String?): ByteArray? {
        val state = states[path]
        if (owner == null || owner != this.owner || state != MessagesPhotoLoadState.loaded) return null
        return bytes[path]
    }

    fun state(path: String, owner: String?): MessagesPhotoLoadState? {
        val state = states[path]
        if (owner == null || owner != this.owner) return null
        return state
    }

    /** 그림을 넣는다(보낸 내 사진 — 받지 않는다). */
    fun insert(jpeg: ByteArray, path: String, owner: String) {
        adopt(owner)
        tasks.remove(path)?.cancel()
        put(path, jpeg)
        if (states[path] != MessagesPhotoLoadState.loaded) states = states + (path to MessagesPhotoLoadState.loaded)
    }

    /** 그 경로를 받는다(경로마다 하나만 · 실패는 기억 · 이미 있으면 아무것도 안 한다). */
    fun load(path: String, owner: String, launch: (suspend () -> Unit) -> Job, fetch: suspend () -> ByteArray) {
        adopt(owner)
        when (states[path]) {
            MessagesPhotoLoadState.loaded -> if (bytes.containsKey(path)) return
            MessagesPhotoLoadState.failed -> return
            else -> Unit
        }
        if (tasks.containsKey(path)) return
        states = states + (path to MessagesPhotoLoadState.loading)
        val myEpoch = epoch
        tasks[path] = launch {
            val fetched = try {
                fetch().takeIf { it.isNotEmpty() }
            } catch (e: Throwable) {
                if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled && myEpoch != epoch) return@launch
                null
            }
            if (myEpoch != epoch) return@launch
            tasks.remove(path)
            if (fetched != null) {
                put(path, fetched)
                states = states + (path to MessagesPhotoLoadState.loaded)
            } else {
                states = states + (path to MessagesPhotoLoadState.failed)
            }
        }
    }

    /** 실패 기억을 지운다(사람이 실패 칸을 눌렀을 때만). */
    fun forgetFailure(path: String) {
        if (states[path] == MessagesPhotoLoadState.failed) states = states - path
    }

    /** 통째로 비운다(로그아웃 · 계정 바뀜). 날던 받기의 결과는 순번으로 버린다. */
    fun wipe() {
        epoch += 1
        for (task in tasks.values) task.cancel()
        tasks.clear()
        bytes.clear()
        if (states.isNotEmpty()) states = emptyMap()
        owner = null
    }

    private fun put(path: String, data: ByteArray) {
        bytes[path] = data
        while (bytes.size > capacity) {
            val eldest = bytes.keys.first()
            bytes.remove(eldest)
            states = states - eldest
        }
    }

    private fun adopt(owner: String) {
        if (this.owner == owner) return
        wipe()
        this.owner = owner
    }
}

/** 사진 칸 조회의 비관찰 장부(로그아웃이 통째로 새것으로 바꾼다). */
internal class MessagesPhotoRuntime {
    var armedPeer: String? = null
    val coveredIDs = HashMap<String, MutableSet<String>>()
    /** 덮은 창의 아래 끝(1970 기준 초). */
    val coveredFloor = HashMap<String, Double>()
    val inFlight = HashSet<String>()
    val trailing = HashSet<String>()
    var scheduled: Job? = null
    var token = 0
    var prepareToken = 0
}

/** 머리 변화 뒤 사진 칸 조회를 모으는 시간(초). */
const val MESSAGE_PHOTO_META_DEBOUNCE_SECONDS = 0.4
/** 머리 시각은 초 단위 반올림이다 — 덮은 창의 아래 끝을 이만큼 너그럽게 본다. */
private const val PHOTO_COVER_SLACK_SECONDS = 1.0

// ---------------------------------------------------------------- 파생값

/** [사진] 버튼이 서는가 — 이 빌드가 사진을 줄일 수 있고 · 로그인 · 상대 있음 · 이 세션에 문이 닫혀 있지 않음. */
fun MessagesStore.showsPhotoButton(peerID: String): Boolean = photoEncoder != null && isSignedIn && peerID.isNotEmpty() && !photoSendClosed

/** 지금 사진을 고르거나 보낼 수 있는가 — 글과 같은 조건(왕복 중 아님 · 집중이 막지 않음) + 문 + 준비 중 아님. */
fun MessagesStore.canSendPhoto(peerID: String): Boolean = showsPhotoButton(peerID) && !isSending && focusBlock(peerID) == null && !photoPreparing

/** 그 대화의 고른 사진(다른 사람에게 고른 사진은 이 대화에 안 선다). */
fun MessagesStore.photoDraft(peerID: String): MessagesPhotoDraft? = photoDraft?.takeIf { it.peer == peerID }

/** 그릴 줄에 사진을 얹는다(①). 머리 줄은 사진 칸 표에서, 지난 쪽 줄은 이미 실려 있다. id · 순서 · 읽음은 그대로다. */
fun MessagesStore.photoDisplayed(entries: List<MessageEntry>, peer: String): List<MessageEntry> {
    val meta = photoMeta[peer]
    if (meta.isNullOrEmpty()) return entries
    return entries.map { entry ->
        val known = meta[entry.id]
        if (entry.wire.photo != null || known == null) entry else MessageEntry(entry.wire.withPhoto(known.attachment, known.caption))
    }
}

/** 사진 칸 조회가 쉬고 있는가(시험). */
val MessagesStore.photoMetaIdle: Boolean get() = photoRuntime.inFlight.isEmpty() && photoRuntime.scheduled == null

/** 말풍선이 그릴 그림(이 계정 것만). */
fun MessagesStore.photoImage(path: String): ByteArray? = photoImages.image(path, context.sessionStore.userID)

/** 말풍선의 받기 상태(이 계정 것만). */
fun MessagesStore.photoLoadState(path: String): MessagesPhotoLoadState? = photoImages.state(path, context.sessionStore.userID)

// ---------------------------------------------------------------- 사진 칸 — 묻기(②)

/** 사람이 대화를 열었다. 닫힌 문 · 함수 없음 숨김을 되돌리고, 다른 사람의 사진 상태를 걷고, 한 번 묻는다. */
fun MessagesStore.armPhotoMeta(peer: String) {
    if (photoSendClosed) photoSendClosed = false
    if (photoMetaAvailable == false) photoMetaAvailable = null
    if (photoRuntime.armedPeer != peer) clearPhotoConversation()
    // 사진을 다룰 수 없는 조립(Windows v1 기능 동결 · 줄이기 없음)은 사진 칸을 묻지 않는다 — 예전과 같은 요청 수 · 사진 줄은 글 '📷 사진'.
    if (photoEncoder == null) return
    photoRuntime.armedPeer = peer
    if (!isSignedIn) return
    startPhotoMetaFetch(peer)
}

/** 대화 화면을 떠난다 — 사진 칸 · 고른 사진을 걷고 날던 조회를 버린다. 그림 캐시는 남는다. */
fun MessagesStore.clearPhotoConversation() {
    val r = photoRuntime
    r.token += 1
    r.scheduled?.cancel()
    r.scheduled = null
    r.inFlight.clear()
    r.trailing.clear()
    r.coveredIDs.clear()
    r.coveredFloor.clear()
    r.armedPeer = null
    if (photoMeta.isNotEmpty()) photoMeta = emptyMap()
    cancelPhotoDraft()
}

/** 로그아웃. 사진 상태 전부 + 그림 캐시를 비운다. */
internal fun MessagesStore.resetPhotoState() {
    clearPhotoConversation()
    photoRuntime = MessagesPhotoRuntime()
    photoMetaAvailable = null
    photoSendClosed = false
    photoImages.wipe()
}

/** 열린 대화의 머리가 바뀌었다(이력 응답 · 실시간 도착). 사진 칸을 모르는 줄이 있으면 합쳐서 한 번 묻는다. */
internal fun MessagesStore.noteHeadChangedForPhotos() {
    val peer = photoRuntime.armedPeer ?: return
    if (!isSignedIn || openConversationPeerID != peer || photoMetaAvailable == false) return
    if (uncoveredPhotoCandidates(peer).isEmpty()) return
    if (peer in photoRuntime.inFlight) {
        photoRuntime.trailing += peer
        return
    }
    schedulePhotoMetaFetch(peer)
}

/** 머리 줄 중 아직 안 물어본 것(덮은 창 안의 것만). 내 말도 센다 — 같은 계정의 맥이 보낸 사진은 이 폰이 모른다. */
fun MessagesStore.uncoveredPhotoCandidates(peer: String): List<String> {
    val covered = photoRuntime.coveredIDs[peer] ?: emptySet()
    val floor = photoRuntime.coveredFloor[peer]?.let { it - PHOTO_COVER_SLACK_SECONDS }
    return history.mapNotNull { entry ->
        if (entry.peerUserID != peer || entry.id in covered) return@mapNotNull null
        if (floor != null && entry.createdAt < floor) return@mapNotNull null
        entry.id
    }
}

/** 이 폰이 보낸 말의 서버 id — 열린 대화의 것이면 물어본 것으로 친다. */
internal fun MessagesStore.noteMessageSentForPhotos(messageID: String?, peer: String) {
    if (messageID.isNullOrEmpty() || photoRuntime.armedPeer != peer) return
    photoRuntime.coveredIDs.getOrPut(peer) { HashSet() } += messageID
}

private fun MessagesStore.schedulePhotoMetaFetch(peer: String) {
    if (photoRuntime.scheduled != null) return
    val token = photoRuntime.token
    photoRuntime.scheduled = scope.launch {
        sleep(MESSAGE_PHOTO_META_DEBOUNCE_SECONDS)
        if (token != photoRuntime.token) return@launch
        photoRuntime.scheduled = null
        if (uncoveredPhotoCandidates(peer).isEmpty()) return@launch
        startPhotoMetaFetch(peer)
    }
}

private fun MessagesStore.startPhotoMetaFetch(peer: String) {
    if (!isSignedIn || photoMetaAvailable == false) return
    if (peer in photoRuntime.inFlight) {
        photoRuntime.trailing += peer
        return
    }
    photoRuntime.inFlight += peer
    val asked = uncoveredPhotoCandidates(peer)
    val token = photoRuntime.token
    val generation = context.generation
    scope.launch { performLoadPhotoMeta(peer, asked, token, generation) }
}

private fun MessagesStore.isCurrentPhotoRequest(peer: String, token: Int, generation: Int): Boolean =
    generation == context.generation && token == photoRuntime.token && photoRuntime.armedPeer == peer

/** `message_page(peer, null, null, 30)` 한 번 → 사진 칸을 배운다. */
private suspend fun MessagesStore.performLoadPhotoMeta(peer: String, asked: List<String>, token: Int, generation: Int) {
    val me = context.sessionStore.userID
    if (me == null) {
        if (token == photoRuntime.token) photoRuntime.inFlight -= peer
        return
    }
    val service = context.service
    try {
        val page = context.withSessionRetry { s -> service.fetchMessagePage(s.accessToken, peer, me, null, MessagePhotoWire.metaPageLimit) }
        if (!isCurrentPhotoRequest(peer, token, generation)) return
        photoRuntime.inFlight -= peer
        if (photoMetaAvailable != true) photoMetaAvailable = true
        absorbPhotoMeta(page.entries, peer)
        val covered = photoRuntime.coveredIDs.getOrPut(peer) { HashSet() }
        covered += page.rowIDs
        covered += asked
        val oldest = page.oldestCursor
        if (page.rowCount >= page.limit && oldest != null) {
            photoRuntime.coveredFloor[peer] = oldest.epochMicros / 1_000_000.0
        } else {
            photoRuntime.coveredFloor.remove(peer)
        }
        if (photoRuntime.trailing.remove(peer) && uncoveredPhotoCandidates(peer).isNotEmpty()) schedulePhotoMetaFetch(peer)
    } catch (e: Throwable) {
        if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) {
            if (token == photoRuntime.token) photoRuntime.inFlight -= peer
            return
        }
        if (!isCurrentPhotoRequest(peer, token, generation)) return
        photoRuntime.inFlight -= peer
        photoRuntime.trailing -= peer
        if (e is SupabaseWorkServiceError && MessagesStore.isMissingFunction(e)) {
            photoMetaAvailable = false
        } else {
            // 일시 실패 — 지금 아는 줄은 물어본 것으로 친다(같은 줄로 다시 묻는 고리가 없게). 다음 대화 열기가 다시 묻는다.
            val covered = photoRuntime.coveredIDs.getOrPut(peer) { HashSet() }
            covered += asked
            covered += uncoveredPhotoCandidates(peer)
        }
    }
}

/** 사진이 실린 줄(지난 쪽 · 사진 칸 조회)을 사진 칸 표에 넣는다. */
internal fun MessagesStore.absorbPhotoMeta(entries: List<MessageHistoryEntry>, peer: String) {
    val map = (photoMeta[peer] ?: emptyMap()).toMutableMap()
    var changed = false
    for (entry in entries) {
        val photo = entry.photo ?: continue
        val caption = entry.body.takeIf { MessageBody.hasVisibleContent(it) }
        val meta = MessagesPhotoMeta(photo, caption)
        if (map[entry.id] != meta) {
            map[entry.id] = meta
            changed = true
        }
    }
    if (changed) photoMeta = photoMeta + (peer to map)
}

// ---------------------------------------------------------------- 고르기(⑤)

/** 고른 사진 원본을 메인 밖에서 줄인 뒤 미리 보기에 세운다. 못 보내는 상태면 사유를 한 줄 남기고 아무것도 안 한다. */
@OptIn(ExperimentalUuidApi::class)
fun MessagesStore.preparePhoto(data: ByteArray, peerID: String) {
    // 집중이 막으면 입력줄이 사유를 늘 띄운다 — 여기 적지 않는다(글 보내기와 같은 약속).
    if (!canSendPhoto(peerID)) {
        if (focusBlock(peerID) == null && isSending) noteSendNotice(peerID, AingStickerText.sendingNowNotice)
        return
    }
    val encoder = photoEncoder ?: return
    photoRuntime.prepareToken += 1
    val token = photoRuntime.prepareToken
    val generation = context.generation
    photoPreparing = true
    scope.launch {
        val prepared = withContext(photoComputeContext) { runCatching { encoder.encode(data) }.getOrNull() }
        if (generation != context.generation || token != photoRuntime.prepareToken) return@launch
        photoPreparing = false
        if (prepared == null) {
            noteSendNotice(peerID, MessagePhotoText.unreadableNotice)
            return@launch
        }
        photoDraft = MessagesPhotoDraft(newPhotoID(), peerID, prepared)
    }
}

/** 미리 보기의 [취소]. 보내는 중이면 아무것도 안 한다(날고 있는 올리기 · RPC 는 멈출 수 없다). */
fun MessagesStore.cancelPhotoDraftFromPreview() {
    if (isSending) return
    cancelPhotoDraft()
}

/** 고른 사진을 버린다(줄이던 작업의 결과도 버린다). */
fun MessagesStore.cancelPhotoDraft() {
    photoRuntime.prepareToken += 1
    if (photoPreparing) photoPreparing = false
    if (photoDraft != null) photoDraft = null
}

// ---------------------------------------------------------------- 보내기(③)

/** 미리 보기의 [보내기]. 설명은 **지금 입력칸의 글**이다(성공하면 글을 보낸 것처럼 비운다 · 실패하면 글과 사진이 남는다). */
fun MessagesStore.sendPhotoDraft(peerID: String) {
    val photo = photoDraft(peerID) ?: return
    val me = context.sessionStore.userID ?: return
    if (!canSendPhoto(peerID)) return
    val caption: String? = when (val v = MessageBody.validate(draft(peerID))) {
        is MessageBodyValidation.ok -> v.value
        is MessageBodyValidation.empty -> null
        is MessageBodyValidation.tooLong -> {
            // 설명이 너무 길다 — 글 보내기의 서버 거절과 같은 문장(입력칸 글은 그대로 남는다).
            noteSendNotice(peerID, MessagesSendRules.notice(MessageSendOutcome.TooLong, v.maxLength.toLong()))
            return
        }
    }
    noteSendNotice(peerID, null)
    markSending(true)
    val generation = context.generation
    val path = MessagePhotoWire.uploadPath(me, photo.id)
    scope.launch {
        try {
            val response = deliverPhoto(photo, path, caption, generation) ?: return@launch
            if (generation != context.generation) return@launch
            when (val outcome = MessagePhotoSendOutcome.of(response)) {
                is MessagePhotoSendOutcome.message -> {
                    val o = outcome.outcome
                    if (o == MessageSendOutcome.Ok) {
                        recordSentPhoto(photo, path, caption, response, me)
                        // 설명을 입력칸에서 가져갔을 때만 비운다(빈 칸이었으면 왕복 중에 친 글을 지우지 않는다).
                        if (caption != null) setDraft("", peerID)
                        noteMessageSentForPhotos(response.send.messageId, peerID)
                        requestActivityRefresh(includeHistory = true)
                    } else if (o == MessageSendOutcome.SenderFocused) {
                        // 내 집중으로 거절 — 켜짐으로 들인다(사유는 입력줄이 띄운다 · 글 보내기와 같다).
                        adoptServerSenderFocused()
                    } else {
                        MessagesSendRules.notice(o, response.send.maxLength)?.let { noteSendNotice(peerID, it) }
                    }
                }
                is MessagePhotoSendOutcome.unsupportedClient ->
                    if (outcome.doorOpen == true) {
                        // 문은 열렸는데 이 기기의 판 번호가 아직 서버에 안 닿았다(잠깐이다) — 고른 사진을 남긴다.
                        noteSendNotice(peerID, MessagePhotoText.doorOpenNotice)
                    } else {
                        closePhotoDoor(MessagePhotoText.doorClosedNotice, peerID)
                    }
                MessagePhotoSendOutcome.invalidPhoto -> {
                    renewPhotoDraft(photo)
                    noteSendNotice(peerID, MessagePhotoText.invalidPhotoNotice)
                }
                MessagePhotoSendOutcome.photoMissing -> {
                    markPhotoDraft(photo, uploaded = false)
                    noteSendNotice(peerID, MessagePhotoText.uploadFailedNotice)
                }
            }
        } finally {
            if (generation == context.generation) markSending(false)
        }
    }
}

private enum class PhotoUploadResult { uploaded, refused, handled }

/** 올리기(필요하면) → RPC. null 이면 문구까지 여기서 끝냈다(또는 취소 · 세대 변경). */
private suspend fun MessagesStore.deliverPhoto(draft: MessagesPhotoDraft, path: String, caption: String?, generation: Int): SendPhotoMessageResponse? {
    if (!draft.uploaded) {
        when (uploadPhotoForSend(draft, path, generation)) {
            PhotoUploadResult.uploaded -> markPhotoDraft(draft, uploaded = true)
            PhotoUploadResult.refused -> Unit
            PhotoUploadResult.handled -> return null
        }
    }
    val request = SendPhotoMessageRequest(draft.peer, path, draft.encoded.pixelWidth.toLong(), draft.encoded.pixelHeight.toLong(), caption, draft.id)
    val service = context.service
    var retried = false
    while (true) {
        try {
            return context.withSessionRetry { s -> service.sendPhotoMessage(s.accessToken, request) }
        } catch (e: Throwable) {
            if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return null
            if (generation != context.generation) return null
            if (MessagesSendRules.isAmbiguousFailure(e) && !retried) {
                retried = true
                sleep(sendRetryDelaySeconds)
                if (generation != context.generation) return null
                continue
            }
            if (e is SupabaseWorkServiceError && MessagesStore.isMissingFunction(e)) {
                closePhotoDoor(MessagePhotoText.doorClosedNotice, draft.peer)
            } else {
                noteSendNotice(draft.peer, MessagesSendRules.connectionNotice)
            }
            return null
        }
    }
}

/** 올리기 한 번(+ 답을 못 받으면 같은 이름으로 한 번 더). 409 는 우리 앞 시도가 올린 우리 파일이다(성공). */
private suspend fun MessagesStore.uploadPhotoForSend(draft: MessagesPhotoDraft, path: String, generation: Int): PhotoUploadResult {
    val service = context.service
    var retried = false
    while (true) {
        try {
            context.withSessionRetry { s -> service.uploadMessagePhoto(s.accessToken, path, draft.encoded.jpeg) }
            return PhotoUploadResult.uploaded
        } catch (e: PrivateStorageError.alreadyExists) {
            return PhotoUploadResult.uploaded
        } catch (e: Throwable) {
            if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return PhotoUploadResult.handled
            if (generation != context.generation) return PhotoUploadResult.handled
            if (MessagesSendRules.isAmbiguousFailure(e) && !retried) {
                retried = true
                sleep(sendRetryDelaySeconds)
                if (generation != context.generation) return PhotoUploadResult.handled
                continue
            }
            when (e) {
                PrivateStorageError.forbidden -> return PhotoUploadResult.refused
                PrivateStorageError.tooLarge -> noteSendNotice(draft.peer, MessagePhotoText.tooLargeNotice)
                SupabaseWorkServiceError.DatabaseSchemaMissing -> closePhotoDoor(MessagePhotoText.doorClosedNotice, draft.peer)
                else -> noteSendNotice(draft.peer, MessagesSendRules.connectionNotice)
            }
            return PhotoUploadResult.handled
        }
    }
}

/** 보낸 내 사진을 그 자리에서 그린다: 사진 칸 표에 넣고 올린 그림을 캐시에 넣는다(내 사진은 받지 않는다). 고른 사진은 내린다. */
private fun MessagesStore.recordSentPhoto(draft: MessagesPhotoDraft, path: String, caption: String?, response: SendPhotoMessageResponse, owner: String) {
    val attachment = response.attachment ?: MessagePhotoWire.attachment(path, draft.encoded.pixelWidth.toLong(), draft.encoded.pixelHeight.toLong())
    if (attachment != null) {
        photoImages.insert(draft.encoded.jpeg, attachment.path, owner)
        val id = response.send.messageId
        if (!id.isNullOrEmpty()) {
            val map = (photoMeta[draft.peer] ?: emptyMap()) + (id to MessagesPhotoMeta(attachment, sentPhotoCaption(response.send.body, caption)))
            photoMeta = photoMeta + (draft.peer to map)
            photoRuntime.coveredIDs.getOrPut(draft.peer) { HashSet() } += id
        }
    }
    if (photoDraft?.id == draft.id) photoDraft = null
}

/** 보낸 사진의 설명 — **서버가 저장한 본문**이 진실이다. 본문이 '📷 사진'이면 사진만 보낸 줄이다(맥과 같은 규칙). */
fun sentPhotoCaption(serverBody: String?, sent: String?): String? {
    if (serverBody == null) return sent
    val body = MessageBody.sanitized(serverBody)
    if (!MessageBody.hasVisibleContent(body) || body == MessageNoticeText.photoFallbackBody) return null
    return body
}

/** 문이 닫혀 있다(또는 함수 · 버킷이 없다) — 문구 한 줄, 고른 사진을 내리고 [사진] 버튼을 다음 대화 열기까지 숨긴다. 글 초안은 남는다. */
private fun MessagesStore.closePhotoDoor(notice: String, peer: String) {
    photoSendClosed = true
    cancelPhotoDraft()
    noteSendNotice(peer, notice)
}

private fun MessagesStore.markPhotoDraft(draft: MessagesPhotoDraft, uploaded: Boolean) {
    val current = photoDraft ?: return
    if (current.id != draft.id || current.uploaded == uploaded) return
    photoDraft = current.withUploaded(uploaded)
}

/** 같은 사진 · 새 이름(서버가 그 이름을 안 받는다 — invalid_photo). */
private fun MessagesStore.renewPhotoDraft(draft: MessagesPhotoDraft) {
    val current = photoDraft ?: return
    if (current.id != draft.id) return
    photoDraft = MessagesPhotoDraft(newPhotoID(), current.peer, current.encoded)
}

// ---------------------------------------------------------------- 그림 받기(④)

/** 말풍선이 보일 때 그 사진을 받는다(경로마다 하나 · 실패 기억). */
fun MessagesStore.requestPhotoImage(path: String) {
    val owner = context.sessionStore.userID ?: return
    if (!MessagePhotoWire.isServerShaped(path)) return
    val loader = photoDataLoader
    val generation = context.generation
    val service = context.service
    val launcher: (suspend () -> Unit) -> Job = { body -> scope.launch { body() } }
    photoImages.load(path, owner, launcher) {
        if (loader != null) return@load loader(path)
        if (generation != context.generation) throw kotlinx.coroutines.CancellationException("세대가 바뀌었다")
        context.withSessionRetry { s -> service.fetchMessagePhotoData(s.accessToken, path) }
    }
}

/** 실패 칸을 사람이 눌렀다 — 한 번 다시 받는다. */
fun MessagesStore.retryPhotoImage(path: String) {
    photoImages.forgetFailure(path)
    requestPhotoImage(path)
}
