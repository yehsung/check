// 원본: Sources/CheckCore/MessageHistoryPaging.swift:226-345(fetchMessagePage · messagePage(from:) · messagePageEntry) @ main 341eb4e3
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.json.SwiftDecodingErrorKind
import com.yehsung.aingcheck.core.wire.json.SwiftDecodingException
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.json.swiftTry
import com.yehsung.aingcheck.core.wire.messages.MessagePage
import com.yehsung.aingcheck.core.wire.messages.MessagePageCursor
import com.yehsung.aingcheck.core.wire.messages.MessagePageRequest
import com.yehsung.aingcheck.core.wire.messages.MessagePageRow
import com.yehsung.aingcheck.core.wire.messages.MessagePhotoWire
import com.yehsung.aingcheck.core.wire.models.MessageHistoryEntry
import kotlinx.serialization.json.JsonArray

/** `message_page` 경로(맥 0.3.86 · 판 9). */
const val MESSAGE_PAGE_PATH = "/rest/v1/rpc/message_page"

/**
 * 지난 쪽 한 번. **버튼을 눌렀을 때만** 부른다(목록 열기 · 폴링 · 전송 어디에서도 안 부른다). 함수가 없는 서버(404/PGRST202)는 그대로
 * 던진다 — 버튼을 숨길지는 스토어가 정한다. 배열이 아닌 답은 디코드 오류로 던진다.
 * [peer] 응답 줄의 두 사람이 나와 이 사람이 아니면 버린다 · [me] 응답이 is_mine 을 안 실으면 보낸이 칸과 비교한다 ·
 * [before] null 이면 30일 안의 최신부터 · [peerName] · [peerAvatarURL] 행이 상대 이름 · 아바타를 안 싣는다.
 */
suspend fun SupabaseWorkService.fetchMessagePage(
    accessToken: String,
    peer: String,
    me: String,
    before: MessagePageCursor?,
    limit: Int,
    peerName: String? = null,
    peerAvatarURL: SwiftURL? = null,
): MessagePage {
    val clamped = minOf(100, maxOf(1, limit))
    val data = send(MESSAGE_PAGE_PATH, "POST", emptyList(), encode(MessagePageRequest.serializer(), MessagePageRequest(peer, before, clamped)), accessToken, null)
    return messagePage(data.decodeToString(), peer, me, clamped, peerName, peerAvatarURL)
}

/** 응답 글자 → 지난 쪽. 원소 하나가 깨져도 그 원소만 버린다(Swift `MessagePageLossyRow`). */
fun SupabaseWorkService.messagePage(
    json: String,
    peer: String,
    me: String,
    limit: Int,
    peerName: String? = null,
    peerAvatarURL: SwiftURL? = null,
): MessagePage {
    val array = SwiftJson.parse(json) as? JsonArray
        ?: throw SwiftDecodingException(SwiftDecodingErrorKind.typeMismatch, "$", "message_page 응답이 배열이 아니다")
    val rows = array.map { element -> swiftTry { SwiftJson.decode(MessagePageRow.serializer(), element) } }
    var oldest: MessagePageCursor? = null
    for (cursor in rows.mapNotNull { it?.cursor }) {
        if (oldest == null || cursor.isOlder(oldest)) oldest = cursor
    }
    val entries = rows.mapNotNull { row -> row?.let { messagePageEntry(it, peer, me, peerName, peerAvatarURL) } }
    // 서버는 최신부터 준다 — 오래된 것부터로 뒤집는다(같은 µs 의 선후도 서버 순서 그대로 뒤집힌다).
    return MessagePage(
        entries = entries.reversed(), rowCount = rows.size, oldestCursor = oldest, limit = limit,
        rowIDs = rows.mapNotNull { it?.id }.filter { it.isNotEmpty() },
    )
}

/**
 * 행 → 표시용 한 건. 버리는 줄: id 없음 · 확성기 줄 · 다른 대화 · 내 말인지 모름 · 보이는 글자 없음 · 시각 없음.
 * 글은 caption 이 있으면 그것, 없으면 body(사진만 보낸 줄은 '📷 사진'). 사진이 모양 규칙을 지나면 사진을 싣고 글은 설명만이다.
 * 받은 쪽 안 읽음(unread_for_me)은 **싣지 않는다**. 내가 보낸 말의 읽음(1)은 싣는다.
 */
fun SupabaseWorkService.messagePageEntry(
    row: MessagePageRow,
    peer: String,
    me: String,
    peerName: String? = null,
    peerAvatarURL: SwiftURL? = null,
): MessageHistoryEntry? {
    val id = row.id
    if (id.isNullOrEmpty()) return null
    if (row.isMegaphone == true) return null
    val peerKey = peer.lowercase()
    val meKey = me.lowercase()
    val from = row.fromUser?.takeIf { it.isNotEmpty() }?.lowercase()
    val to = row.toUser?.takeIf { it.isNotEmpty() }?.lowercase()
    if (from != null && to != null && !((from == meKey && to == peerKey) || (from == peerKey && to == meKey))) return null
    val flagged = row.isMine
    val isMine: Boolean = when {
        flagged != null -> flagged
        from != null && meKey.isNotEmpty() && (from == meKey || from == peerKey) -> from == meKey
        else -> return null
    }
    val caption = row.caption?.takeIf { text.hasVisibleContent(it) }
    val photo = MessagePhotoWire.attachment(row.photoPath, row.photoWidth, row.photoHeight)
    val raw = if (photo != null) caption ?: "" else caption ?: row.body ?: (if (row.photoPath == null) "" else MessagePhotoWire.photoFallbackBody)
    val body = text.sanitized(raw)
    if (photo == null && !text.hasVisibleContent(body)) return null
    val ms = row.createdEpochMs
    val us = row.createdEpochUs
    val createdAt = when {
        ms != null -> SwiftDate.fromEpochMillis(ms)
        us != null -> SwiftDate.fromEpochMillis(us / 1_000)
        else -> return null
    }
    return MessageHistoryEntry(
        id = id,
        peerUserID = peer,
        peerName = peerName?.ifEmpty { null } ?: "사용자",
        peerAvatarURL = peerAvatarURL,
        body = body,
        createdAt = createdAt,
        isMine = isMine,
        readByPeer = if (isMine) row.readByPeer else null,
        photo = photo,
    )
}
