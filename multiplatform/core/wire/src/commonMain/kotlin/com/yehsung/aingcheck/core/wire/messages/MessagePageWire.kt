// 원본: Sources/CheckCore/MessageHistoryPaging.swift:66-224(MessagePageCursor · MessagePageRequest · MessagePageRow · MessagePage) @ main 341eb4e3
package com.yehsung.aingcheck.core.wire.messages

import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.models.MessageHistoryEntry
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// 이전 대화 더 보기(맥 0.3.86 · 아이폰 1.0.19 · 판 9 — 메시지 30일 보관, `message_page`). 대표 #d_IKem7qxZXc5b "메시지 30일로 늘리기".
// 옛 함수(24시간 머리)는 그대로, 새 앱만 `message_page(p_peer, p_before_us, p_before_id, p_limit)` 로 30일 안을 쪽으로 넘긴다. 문은 없다.
// 지키는 것(Swift 머리 그대로): ① 24시간 머리는 그대로 ② 지난 쪽은 안 읽음 재료가 아니다(unread_for_me 를 옮기지 않는다)
// ③ 확성기 줄은 버리되 커서는 된다 ④ 커서는 정수 마이크로초 + id(실수로 바꾸지 마라) ⑤ 디코드는 칸 하나로 죽지 않는다 ⑥ 본문을 로그로 흘리지 않는다.

/** 다음 쪽 커서: 지금까지 받은 줄 중 가장 오래된 줄의 (정수 마이크로초, id). 서버 정렬은 (created_at desc, id desc). */
data class MessagePageCursor(val epochMicros: Long, val id: String) {
    /** 서버 정렬에서 이 줄이 [other] 보다 오래됐는가(같은 µs 는 id 가 작은 쪽 — 서버 `m.id < p_before_id`, 소문자 16진 사전 순). */
    fun isOlder(than: MessagePageCursor): Boolean =
        if (epochMicros != than.epochMicros) epochMicros < than.epochMicros else id.lowercase() < than.id.lowercase()
}

/** `message_page` 요청 — **네 키를 언제나** 싣는다(커서가 없으면 두 커서 키를 JSON null). PostgREST 는 키 집합으로 함수를 고른다. */
@Serializable(with = MessagePageRequest.Serializer::class)
data class MessagePageRequest(val pPeer: String, val pBeforeUs: Long?, val pBeforeId: String?, val pLimit: Int) {
    constructor(peer: String, before: MessagePageCursor?, limit: Int) : this(peer, before?.epochMicros, before?.id, limit)

    object Serializer : KSerializer<MessagePageRequest> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("MessagePageRequest")
        override fun serialize(encoder: Encoder, value: MessagePageRequest) {
            (encoder as JsonEncoder).encodeJsonElement(
                JsonObject(
                    linkedMapOf(
                        "p_peer" to JsonPrimitive(value.pPeer),
                        "p_before_us" to (value.pBeforeUs?.let { JsonPrimitive(it) } ?: JsonNull),
                        "p_before_id" to (value.pBeforeId?.let { JsonPrimitive(it) } ?: JsonNull),
                        "p_limit" to JsonPrimitive(value.pLimit),
                    ),
                ),
            )
        }
        override fun deserialize(decoder: Decoder): MessagePageRequest = throw UnsupportedOperationException("요청 본문은 읽지 않는다")
    }
}

/** 응답 한 행(서버 최종 목록 §1의 열네 칸). **칸마다 따로 읽는다**(한 칸이 깨져도 그 칸만 null). */
@Serializable(with = MessagePageRow.Serializer::class)
data class MessagePageRow(
    val id: String? = null,
    val fromUser: String? = null,
    val toUser: String? = null,
    val body: String? = null,
    val caption: String? = null,
    val photoPath: String? = null,
    val photoWidth: Long? = null,
    val photoHeight: Long? = null,
    val isMegaphone: Boolean? = null,
    val isMine: Boolean? = null,
    val createdEpochMs: Long? = null,
    val createdEpochUs: Long? = null,
    val readByPeer: Boolean? = null,
    /** 받은 줄만: 내가 안 읽었나. **읽기만 하고 옮기지 않는다**. */
    val unreadForMe: Boolean? = null,
) {
    /** 이 줄의 커서(µs · id 둘 다 있을 때만). */
    val cursor: MessagePageCursor?
        get() {
            val id = id ?: return null
            if (id.isEmpty()) return null
            val us = createdEpochUs ?: return null
            return MessagePageCursor(us, id)
        }

    object Serializer : SwiftDecodableSerializer<MessagePageRow>("MessagePageRow") {
        override fun deserialize(decoder: Decoder): MessagePageRow {
            val c = SwiftDecoding.keyed(decoder)
            // 정수로만 읽는다(숫자 또는 숫자 글자) — 실수 갈래가 없다(커서가 실수를 지나면 경계 줄이 겹치거나 빠진다).
            fun exact(key: String): Long? = c.lossyLong(key) ?: c.lossyString(key)?.toLongOrNull()
            return MessagePageRow(
                id = c.lossyString("id"),
                fromUser = c.lossyString("from_user"),
                toUser = c.lossyString("to_user"),
                body = c.lossyString("body"),
                caption = c.lossyString("caption"),
                photoPath = c.lossyString("photo_path"),
                photoWidth = c.lossyLong("photo_width"),
                photoHeight = c.lossyLong("photo_height"),
                isMegaphone = c.lossyBool("is_megaphone"),
                isMine = c.lossyBool("is_mine"),
                createdEpochMs = exact("created_epoch_ms"),
                createdEpochUs = exact("created_epoch_us"),
                readByPeer = c.lossyBool("read_by_peer"),
                unreadForMe = c.lossyBool("unread_for_me"),
            )
        }
    }
}

/** 지난 쪽 한 번(옮긴 뒤). */
data class MessagePage(
    /** 그릴 줄(**오래된 것 → 최신**). 확성기 · 다른 대화 · 보이는 글자 없는 줄은 빠졌고, 받은 쪽 안 읽음 칸은 비어 있다. */
    val entries: List<MessageHistoryEntry>,
    /** 서버가 준 줄 수(버린 줄 · 깨진 원소 포함) — 쪽 끝 판정의 재료. */
    val rowCount: Int,
    /** 서버가 준 줄 중 가장 오래된 줄의 커서(버린 줄도 든다). 쓸 만한 줄이 하나도 없으면 null. */
    val oldestCursor: MessagePageCursor?,
    val limit: Int,
    /** 서버가 준 줄의 id 전부(버린 줄 포함 · 서버 순서). */
    val rowIDs: List<String> = emptyList(),
) {
    /** 더 이전 쪽이 있는가: 꽉 찬 쪽이고 다음 커서를 얻었다. 상한보다 적으면 끝이다(서버 계약). */
    val hasMore: Boolean get() = rowCount >= limit && oldestCursor != null
}
