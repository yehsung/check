// 원본: Sources/CheckCore/MegaphoneFeed.swift:107-292(전선 — 요청 · 줄 · 응답 · 운영자 내리기) @ main 341eb4e3
package com.yehsung.aingcheck.core.wire.messages

import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
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

// 지난 확성기(📢) — 최근 30일 모아 보기(맥 0.3.86 · 아이폰 1.0.19 · 판 9, 대표 "확성기 지난글 모아보기도 괜찮은듯").
// `POST /rest/v1/rpc/megaphone_feed` 본문 정확히 {"p_before_us": <정수 µs>|null, "p_limit": 30} — 키 둘을 **언제나** 싣는다.
// 응답은 줄 배열(봉투 · 문 없음 — 로그인만). 최신이 먼저, 받은 줄이 p_limit 보다 적으면 끝. 커서는 가장 오래된 줄의 created_epoch_us(정수 그대로).
// 줄의 body 는 서버가 머리말 '📢 ' 를 이미 뗐다 — 다시 떼지 않는다. 줄에는 메시지 id 가 없다.

/** `megaphone_feed(p_before_us, p_limit)` 요청 — 키 둘을 언제나(첫 쪽은 null). */
@Serializable(with = MegaphoneFeedRequest.Serializer::class)
data class MegaphoneFeedRequest(val pBeforeUs: Long?, val pLimit: Int) {
    object Serializer : KSerializer<MegaphoneFeedRequest> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("MegaphoneFeedRequest")
        override fun serialize(encoder: Encoder, value: MegaphoneFeedRequest) {
            (encoder as JsonEncoder).encodeJsonElement(
                JsonObject(linkedMapOf("p_before_us" to (value.pBeforeUs?.let { JsonPrimitive(it) } ?: JsonNull), "p_limit" to JsonPrimitive(value.pLimit))),
            )
        }
        override fun deserialize(decoder: Decoder): MegaphoneFeedRequest = throw UnsupportedOperationException("요청 본문은 읽지 않는다")
    }
}

/** 응답 한 줄. 전 필드 옵셔널 — 칸 하나가 깨져도 그 칸만 null. */
@Serializable(with = MegaphoneFeedRow.Serializer::class)
data class MegaphoneFeedRow(
    val megaphoneId: String? = null,
    val senderId: String? = null,
    val senderDisplayName: String? = null,
    val senderAvatarUrl: String? = null,
    val body: String? = null,
    val recipients: Long? = null,
    val isMine: Boolean? = null,
    val createdEpochMs: Long? = null,
    val createdEpochUs: Long? = null,
) {
    object Serializer : SwiftDecodableSerializer<MegaphoneFeedRow>("MegaphoneFeedRow") {
        override fun deserialize(decoder: Decoder): MegaphoneFeedRow {
            val c = SwiftDecoding.keyed(decoder)
            fun exact(key: String): Long? = c.lossyLong(key) ?: c.lossyString(key)?.toLongOrNull()
            return MegaphoneFeedRow(
                megaphoneId = c.lossyString("megaphone_id"),
                senderId = c.lossyString("sender_id"),
                senderDisplayName = c.lossyString("sender_display_name"),
                senderAvatarUrl = c.lossyString("sender_avatar_url"),
                body = c.lossyString("body"),
                recipients = c.lossyLong("recipients"),
                isMine = c.lossyBool("is_mine"),
                createdEpochMs = exact("created_epoch_ms"),
                createdEpochUs = exact("created_epoch_us"),
            )
        }
    }
}

/** `megaphone_admin_hide(p_id, p_hidden)` 요청. 키 둘을 언제나. */
@Serializable(with = MegaphoneAdminHideRequest.Serializer::class)
data class MegaphoneAdminHideRequest(val pId: String, val pHidden: Boolean = true) {
    object Serializer : KSerializer<MegaphoneAdminHideRequest> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("MegaphoneAdminHideRequest")
        override fun serialize(encoder: Encoder, value: MegaphoneAdminHideRequest) {
            (encoder as JsonEncoder).encodeJsonElement(JsonObject(linkedMapOf("p_id" to JsonPrimitive(value.pId), "p_hidden" to JsonPrimitive(value.pHidden))))
        }
        override fun deserialize(decoder: Decoder): MegaphoneAdminHideRequest = throw UnsupportedOperationException("요청 본문은 읽지 않는다")
    }
}

/** `megaphone_admin_hide` 응답 `{"status": ok|forbidden|not_found, "hidden": bool}`. */
@Serializable(with = MegaphoneAdminHideResponse.Serializer::class)
data class MegaphoneAdminHideResponse(val status: String? = null, val hidden: Boolean? = null) {
    enum class Outcome { hidden, forbidden, failed }

    /** ok · not_found → 내렸다(어느 쪽이든 목록에서 뺀다) · forbidden → 운영자가 아니다 · 그 밖 → 실패. */
    val outcome: Outcome
        get() = when (status) {
            "ok", "not_found" -> Outcome.hidden
            "forbidden" -> Outcome.forbidden
            else -> Outcome.failed
        }

    object Serializer : SwiftDecodableSerializer<MegaphoneAdminHideResponse>("MegaphoneAdminHideResponse") {
        override fun deserialize(decoder: Decoder): MegaphoneAdminHideResponse {
            val c = SwiftDecoding.keyed(decoder)
            return MegaphoneAdminHideResponse(c.lossyString("status"), c.lossyBool("hidden"))
        }
    }
}
