// 원본: Sources/CheckCore/MessagePhotoWire.swift @ main 341eb4e3(맥 0.3.86 · 아이폰 1.0.19 5b6ab3ac 가 같은 코어) — 판 9 1:1 메시지 사진
package com.yehsung.aingcheck.core.wire.messages

import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.models.MessageHistoryEntry
import com.yehsung.aingcheck.core.wire.models.MessagePhotoAttachment
import com.yehsung.aingcheck.core.wire.models.MessageSendOutcome
import com.yehsung.aingcheck.core.wire.models.PokeSendResponse
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

/** 사진 화면 글(맥 · 아이폰과 같은 글). 사진 · 경로 · 글은 사람이 보낸 것 — 로그 금지. */
object MessagePhotoText {
    const val buttonLabel = "사진 고르기"
    const val previewTitle = "이 사진을 보낼까요?"
    const val previewSend = "보내기"
    const val previewCancel = "취소"
    const val captionNote = "입력칸의 글도 함께 보내요"
    const val preparing = "사진을 준비하는 중…"
    const val sending = "보내는 중…"
    const val loadingLabel = "사진을 불러오는 중"
    const val unavailable = "사진을 볼 수 없어요"
    const val viewerClose = "닫기"
    const val openLabel = "사진 크게 보기"
    const val photoAccessibility = "사진"
    const val reportPhotoTitle = "신고할 사진"
    const val doorClosedNotice = "사진 보내기는 새 버전이 퍼진 뒤 열려요"
    const val doorOpenNotice = "사진 보내기를 준비하는 중이에요 · 잠시 후 다시 시도해 주세요"
    const val uploadFailedNotice = "사진을 올리지 못했어요"
    const val invalidPhotoNotice = "사진을 보내지 못했어요 · 다시 보내 주세요"
    const val unreadableNotice = "사진을 읽지 못했어요"
    const val tooLargeNotice = "사진이 너무 커요"
}

/** 말풍선 크기(dp) — 맥 · 아이폰과 같은 셈. 폰 말풍선은 상한 220×260(아이폰 1.0.19). */
object MessagePhotoLayout {
    const val maxSide = 200.0
    const val receivedMaxWidth = 170.0
    const val minSide = 60.0
    const val phoneMaxWidth = 220.0
    const val phoneMaxHeight = 260.0

    /** 픽셀 크기 → 말풍선 크기. 비율을 지키며 상자에 맞추고(키우지 않는다) 각 변을 하한까지 올린다(그때는 채워 자른다). 정수로 반올림. */
    fun bubbleSize(width: Long, height: Long, maxWidth: Double = maxSide, maxHeight: Double = maxSide): Pair<Double, Double> {
        val w = maxOf(1L, width).toDouble()
        val h = maxOf(1L, height).toDouble()
        val scale = minOf(1.0, maxWidth / w, maxHeight / h)
        val fw = minOf(maxWidth, maxOf(minSide, kotlin.math.round(w * scale)))
        val fh = minOf(maxHeight, maxOf(minSide, kotlin.math.round(h * scale)))
        return fw to fh
    }
}

/** 표시용 한 건에 사진을 붙인 사본 — 글은 **설명**이다(사진만 보낸 줄은 빈 글). 24시간 머리 줄에 message_page 에서 배운 사진을 얹을 때. */
fun MessageHistoryEntry.withPhoto(photo: MessagePhotoAttachment, caption: String?): MessageHistoryEntry =
    copy(body = caption ?: "", photo = photo)

/** `send_photo_message` 요청. **여섯 키를 언제나 싣는다** — 설명이 없으면 p_caption 을 JSON null 로. */
@Serializable(with = SendPhotoMessageRequest.Serializer::class)
data class SendPhotoMessageRequest(
    val pTo: String, val pPath: String, val pWidth: Long, val pHeight: Long, val pCaption: String?, val pClientMessageId: String,
) {
    object Serializer : KSerializer<SendPhotoMessageRequest> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("SendPhotoMessageRequest")
        override fun serialize(encoder: Encoder, value: SendPhotoMessageRequest) {
            (encoder as JsonEncoder).encodeJsonElement(JsonObject(linkedMapOf(
                "p_to" to JsonPrimitive(value.pTo), "p_path" to JsonPrimitive(value.pPath),
                "p_width" to JsonPrimitive(value.pWidth), "p_height" to JsonPrimitive(value.pHeight),
                "p_caption" to (value.pCaption?.let { JsonPrimitive(it) } ?: JsonNull),
                "p_client_message_id" to JsonPrimitive(value.pClientMessageId),
            )))
        }
        override fun deserialize(decoder: Decoder): SendPhotoMessageRequest = throw UnsupportedOperationException("요청 본문은 읽지 않는다")
    }
}

/** `send_photo_message` 응답 — send_message 와 같은 봉투(PokeSendResponse) + 사진 칸 + 문 칸. 칸 하나가 깨져도 응답 전체를 버리지 않는다. */
@Serializable(with = SendPhotoMessageResponse.Serializer::class)
data class SendPhotoMessageResponse(
    val send: PokeSendResponse,
    val doorOpen: Boolean? = null,
    val photoPath: String? = null,
    val photoWidth: Long? = null,
    val photoHeight: Long? = null,
) {
    val status: String get() = send.status
    /** ok 에 실려 온 사진(모양 규칙을 지날 때만). */
    val attachment: MessagePhotoAttachment? get() = MessagePhotoWire.attachment(photoPath, photoWidth, photoHeight)

    object Serializer : SwiftDecodableSerializer<SendPhotoMessageResponse>("SendPhotoMessageResponse") {
        override fun deserialize(decoder: Decoder): SendPhotoMessageResponse {
            // 같은 값 디코더를 두 번 읽는다(봉투 → 덤 칸) — Swift 가 같은 decoder 로 PokeSendResponse 를 먼저 읽는 것과 같다.
            val send = PokeSendResponse.Serializer.deserialize(decoder)
            val c = SwiftDecoding.keyed(decoder)
            return SendPhotoMessageResponse(send, c.lossyBool("door_open"), c.lossyString("photo_path"), c.lossyLong("photo_width"), c.lossyLong("photo_height"))
        }
    }
}

/** 사진 보내기 결과 — 공용 어휘는 [message] 로 그대로 지나고 사진만의 셋이 따로 선다. */
sealed interface MessagePhotoSendOutcome {
    data class message(val outcome: MessageSendOutcome) : MessagePhotoSendOutcome
    data class unsupportedClient(val doorOpen: Boolean?) : MessagePhotoSendOutcome
    data object invalidPhoto : MessagePhotoSendOutcome
    data object photoMissing : MessagePhotoSendOutcome

    companion object {
        fun of(response: SendPhotoMessageResponse): MessagePhotoSendOutcome = when (response.status) {
            "unsupported_client" -> unsupportedClient(response.doorOpen)
            "invalid_photo" -> invalidPhoto
            "photo_missing" -> photoMissing
            else -> message(MessageSendOutcome.of(response.send))
        }
    }
}
