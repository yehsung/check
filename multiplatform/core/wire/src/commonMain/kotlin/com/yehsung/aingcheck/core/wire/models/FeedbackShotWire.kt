// 원본: Sources/CheckCore/FeedbackShotWire.swift @ main 341eb4e3 (맥 0.3.86 제보 화면 캡처 · 계약 v2 §3) — 판 9(아이폰 1.0.19 6a6141ce 의 안드로이드 짝)
package com.yehsung.aingcheck.core.wire.models

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.messages.PrivateStorage
import com.yehsung.aingcheck.core.wire.text.WireScalars
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// 대표 #d_x5kYyOPOeLlH "제보에 화면 캡처 첨부하는것도 괜찮고" → 폰 #d_xygj8oZRFlfH 4번. **이 기능의 서버 어휘는 전부 이 파일에** 있다.
// 순서(서버가 강제한다): ① submit_feedback(예전 네 키) → 새 제보 id ② 캡처마다 저장소 `feedback-shots/<내 uid>/<제보 id>/<새 uuid>.jpg`
// (전부 소문자 · upsert 없음 · 내 제보 · 한 시간 안 · 3장 미만 · 문이 열렸을 때만) ③ 캡처마다 feedback_attach_shot.
// 목록: feedback_list 뒤 **한 번에** feedback_shots(p_report_ids). 캡처는 남의 이름 · 대화가 찍혀 있을 수 있다 — 바이트 · 경로 · 본문을 로그로 흘리지 마라.

/** 제보 캡처의 서버 어휘 한 벌. */
object FeedbackShotWire {
    const val bucket = "feedback-shots"
    const val attachPath = "/rest/v1/rpc/feedback_attach_shot"
    const val listPath = "/rest/v1/rpc/feedback_shots"
    /** 제보 하나에 붙는 캡처 상한(서버 `feedback_shots_per_report()` = 3). */
    const val maxPerReport = 3
    const val signedURLSeconds = 3600L

    /** `<내 uid>/<제보 id>/<새 uuid>.jpg` — 조각마다 소문자. 시도마다 새 uuid. */
    fun objectPath(userID: String, reportID: String, fileID: String): String = PrivateStorage.objectPath(listOf(userID, reportID), fileID, "jpg")

    /** submit_feedback 이 돌려준 값 → 제보 id(소문자 uuid). uuid 모양이 아니면 null — 제보는 보낸 것으로 치고 캡처만 못 붙인다. */
    fun reportID(raw: String?): String? {
        val trimmed = raw?.let { WireScalars.trimSwiftWhitespaces(it) } ?: return null
        val groups = trimmed.split("-")
        if (groups.map { it.length } != listOf(8, 4, 4, 4, 12)) return null
        if (!groups.all { g -> g.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' } }) return null
        return trimmed.lowercase()
    }

    /** 목록 행이 준 경로를 믿어도 되는가(빈 값 · 이상한 글자 · `..` 는 버린다). */
    fun acceptedPath(raw: String?): String? = raw?.let { WireScalars.trimSwiftWhitespaces(it) }?.takeIf { PrivateStorage.isSafeObjectPath(it) }

    /** feedback_shots 행들 → 제보 id(소문자)별 캡처. 쓸 수 없는 행은 버리고, 붙인 순서(시각 → id)로 세운 뒤 **상한까지만**. */
    fun grouped(rows: List<FeedbackShotRow>): Map<String, List<FeedbackShot>> {
        val result = LinkedHashMap<String, MutableList<FeedbackShot>>()
        for (row in rows) {
            val report = row.reportId?.lowercase()?.takeIf { it.isNotEmpty() } ?: continue
            val path = acceptedPath(row.path) ?: continue
            val width = row.width ?: continue
            val height = row.height ?: continue
            if (width <= 0 || height <= 0) continue
            val shot = FeedbackShot((row.attachmentId ?: path).lowercase(), report, path, width, height, row.createdEpochMs?.let(SwiftDate::fromEpochMillis))
            val list = result.getOrPut(report) { ArrayList() }
            if (list.any { it.path == path }) continue
            list += shot
        }
        return result.mapValues { (_, shots) ->
            shots.sortedWith(compareBy<FeedbackShot> { it.createdAt?.timeIntervalSince1970 ?: Double.NEGATIVE_INFINITY }.thenBy { it.id }).take(maxPerReport)
        }
    }
}

/** feedback_attach_shot(p_report, p_path, p_width, p_height) — 키 넷을 언제나. */
@Serializable(with = FeedbackAttachShotRequest.Serializer::class)
data class FeedbackAttachShotRequest(val pReport: String, val pPath: String, val pWidth: Long, val pHeight: Long) {
    object Serializer : KSerializer<FeedbackAttachShotRequest> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("FeedbackAttachShotRequest")
        override fun serialize(encoder: Encoder, value: FeedbackAttachShotRequest) {
            (encoder as JsonEncoder).encodeJsonElement(JsonObject(linkedMapOf(
                "p_report" to JsonPrimitive(value.pReport), "p_path" to JsonPrimitive(value.pPath),
                "p_width" to JsonPrimitive(value.pWidth), "p_height" to JsonPrimitive(value.pHeight),
            )))
        }
        override fun deserialize(decoder: Decoder): FeedbackAttachShotRequest = throw UnsupportedOperationException("요청 본문은 읽지 않는다")
    }
}

/** feedback_shots(p_report_ids uuid[]). */
@Serializable(with = FeedbackShotsRequest.Serializer::class)
data class FeedbackShotsRequest(val pReportIds: List<String>) {
    object Serializer : KSerializer<FeedbackShotsRequest> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("FeedbackShotsRequest")
        override fun serialize(encoder: Encoder, value: FeedbackShotsRequest) {
            (encoder as JsonEncoder).encodeJsonElement(JsonObject(mapOf("p_report_ids" to JsonArray(value.pReportIds.map { JsonPrimitive(it) }))))
        }
        override fun deserialize(decoder: Decoder): FeedbackShotsRequest = throw UnsupportedOperationException("요청 본문은 읽지 않는다")
    }
}

/** feedback_attach_shot 응답 봉투. */
@Serializable(with = FeedbackAttachShotResponse.Serializer::class)
data class FeedbackAttachShotResponse(val status: String?, val attachmentId: String?, val duplicate: Boolean?, val doorOpen: Boolean?, val max: Long?) {
    object Serializer : SwiftDecodableSerializer<FeedbackAttachShotResponse>("FeedbackAttachShotResponse") {
        override fun deserialize(decoder: Decoder): FeedbackAttachShotResponse {
            val c = SwiftDecoding.keyed(decoder)
            return FeedbackAttachShotResponse(c.lossyString("status"), c.lossyString("attachment_id"), c.lossyBool("duplicate"), c.lossyBool("door_open"), c.lossyLong("max"))
        }
    }
}

/** 붙이기 한 번의 결과(서버 status 어휘 → 값). */
sealed interface FeedbackAttachOutcome {
    data class attached(val duplicate: Boolean) : FeedbackAttachOutcome
    /** 문이 닫혔다(unsupported_client). doorOpen = 서버 문 자체가 열렸는가(열렸는데 거절이면 이 앱 판이 아직 안 알려졌다). */
    data class doorClosed(val doorOpen: Boolean?) : FeedbackAttachOutcome
    data object invalid : FeedbackAttachOutcome
    data object invalidPhoto : FeedbackAttachOutcome
    data object photoMissing : FeedbackAttachOutcome
    data class tooMany(val max: Int) : FeedbackAttachOutcome
    data object unauthorized : FeedbackAttachOutcome
    data object unknown : FeedbackAttachOutcome

    companion object {
        fun from(r: FeedbackAttachShotResponse): FeedbackAttachOutcome = when (r.status ?: "") {
            "ok" -> attached(r.duplicate ?: false)
            "unsupported_client" -> doorClosed(r.doorOpen)
            "invalid" -> invalid
            "invalid_photo" -> invalidPhoto
            "photo_missing" -> photoMissing
            "too_many" -> tooMany(r.max?.toInt() ?: FeedbackShotWire.maxPerReport)
            "unauthorized" -> unauthorized
            else -> unknown
        }
    }
}

/** feedback_shots 한 행 — 전부 옵셔널(칸 하나가 비어도 그 행만 버린다). */
@Serializable(with = FeedbackShotRow.Serializer::class)
data class FeedbackShotRow(
    val reportId: String? = null, val attachmentId: String? = null, val path: String? = null,
    val width: Long? = null, val height: Long? = null, val createdEpochMs: Long? = null,
) {
    object Serializer : SwiftDecodableSerializer<FeedbackShotRow>("FeedbackShotRow") {
        override fun deserialize(decoder: Decoder): FeedbackShotRow {
            val c = SwiftDecoding.keyed(decoder)
            return FeedbackShotRow(c.lossyString("report_id"), c.lossyString("attachment_id"), c.lossyString("path"),
                c.lossyLong("width"), c.lossyLong("height"), c.lossyLong("created_epoch_ms"))
        }
    }
}

/** 제보에 붙은 캡처 한 장(표시용). */
data class FeedbackShot(val id: String, val reportID: String, val path: String, val width: Long, val height: Long, val createdAt: SwiftDate?)

/** 제보 캡처 규칙(순수). */
object FeedbackShotRules {
    const val maxDraft = FeedbackShotWire.maxPerReport
    /** 줄이는 긴 변(px)과 JPEG 품질 — 계약 "긴 변 1600px 안팎 · JPEG · 약 0.3MB". */
    const val maxDimension = 1600
    const val jpegQuality = 80
    const val maxUploadBytes = 1_500_000
    const val fallbackJPEGQuality = 60
}

/** 제보 캡처 문구(맥 · 아이폰과 같은 글). 숫자는 상수에서 나온다. */
object FeedbackShotText {
    const val noticeTerm = "화면 캡처"
    const val rowTitle = "화면 캡처"
    val limitHint: String get() = "최대 ${FeedbackShotWire.maxPerReport}장"
    const val pickAction = "이미지 고르기"
    const val removeAction = "빼기"
    fun attachedCount(count: Int): String = "$count/${FeedbackShotWire.maxPerReport}"
    const val privacyWarning = "남의 이름·대화가 찍혔는지 확인해 주세요 · 나와 운영자만 봐요"
    const val preparing = "캡처를 준비하는 중…"
    const val unreadable = "이미지를 읽지 못했어요 — 다른 파일을 골라 주세요"
    const val tooLarge = "이미지가 너무 커요 — 다른 이미지를 골라 주세요"
    val full: String get() = "캡처는 ${FeedbackShotWire.maxPerReport}장까지 붙일 수 있어요"
    const val uploading = "제보는 보냈어요 · 캡처 올리는 중…"
    const val sentShotsFailed = "제보는 보냈어요 · 캡처는 못 붙였어요"
    fun sentSomeShotsFailed(failed: Int): String = "제보는 보냈어요 · 캡처 ${failed}장은 못 붙였어요"
    const val sentShotsDoorClosed = "제보는 보냈어요 · 캡처 붙이기는 아직 준비 중이에요"
    const val sentShotsAppOutdated = "제보는 보냈어요 · 캡처는 앱을 최신으로 다시 켜면 붙어요"
    fun sentShotsTooMany(max: Int): String = "제보는 보냈어요 · 캡처는 ${max}장까지만 붙어요"
    fun chip(count: Int): String = "캡처 ${count}장"
}
