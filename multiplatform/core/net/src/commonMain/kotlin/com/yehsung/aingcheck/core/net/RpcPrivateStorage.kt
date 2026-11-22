// 원본: Sources/CheckCore/SupabaseWorkServicePrivateStorage.swift @ main 341eb4e3 (비공개 버킷 도우미 — 제보 캡처 · 메시지 사진이 같이 쓴다)
// 원본: Sources/CheckCore/FeedbackShotWire.swift:296-342(uploadFeedbackShot · attachFeedbackShot · fetchFeedbackShots)
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.json.swiftTry
import com.yehsung.aingcheck.core.wire.messages.PrivateStorage
import com.yehsung.aingcheck.core.wire.models.FeedbackAttachOutcome
import com.yehsung.aingcheck.core.wire.models.FeedbackAttachShotRequest
import com.yehsung.aingcheck.core.wire.models.FeedbackAttachShotResponse
import com.yehsung.aingcheck.core.wire.models.FeedbackShot
import com.yehsung.aingcheck.core.wire.models.FeedbackShotRow
import com.yehsung.aingcheck.core.wire.models.FeedbackShotWire
import com.yehsung.aingcheck.core.wire.models.FeedbackShotsRequest
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull

// 지키는 것(Swift 머리 그대로): ① 공용 오류 매핑을 지나지 않는다(저장소 409 의 "exists" 가 가입 오류로 접히지 않게) ② 만료 토큰은 SessionExpired
// 로 올린다(저장소는 400/403 + "exp claim" 으로 말하는 판이 있다) ③ 버킷이 없으면 DatabaseSchemaMissing("아직 안 열린 기능") · 개체 하나가 없는 것은
// objectMissing ④ 올린 · 받은 바이트를 로그로 흘리지 않는다.

/** 비공개 버킷 왕복이 사람 말로 갈려야 하는 실패들. 나머지(만료 · 버킷 없음 · 5xx · 429)는 공용 SupabaseWorkServiceError 로 올린다. */
sealed class PrivateStorageError(message: String) : Exception(message) {
    data object objectMissing : PrivateStorageError("objectMissing")
    data object alreadyExists : PrivateStorageError("alreadyExists")
    data object forbidden : PrivateStorageError("forbidden")
    data object tooLarge : PrivateStorageError("tooLarge")
    data object invalidPath : PrivateStorageError("invalidPath")
}

/** 오류를 가를 때 "무엇을 하던 중이었나". 올리기에서의 404 는 개체가 아니라 **버킷**이 없다는 뜻이다. */
enum class PrivateStorageOperation { upload, read, delete }

/** 저장소 실패 → 오류 값(순수 — 시험이 본문 모양별로 직접 묻는다). HTTP 가 400 이면 본문의 statusCode 를 믿는다. */
fun privateStorageError(statusCode: Int, data: ByteArray, operation: PrivateStorageOperation): Exception {
    val obj = swiftTry { SwiftJson.parse(data.decodeToString()) as? JsonObject }
    fun str(key: String): String? = (obj?.get(key) as? JsonPrimitive)?.contentOrNull
    val bodyStatus: Int? = (obj?.get("statusCode") as? JsonPrimitive)?.let { it.intOrNull ?: it.contentOrNull?.toIntOrNull() }
    val effective = (if (statusCode == 400) bodyStatus else null) ?: statusCode
    val text = listOfNotNull(str("error"), str("message"), str("code"), str("msg")).joinToString(" ").lowercase()
    val raw = if (obj == null) data.decodeToString().take(512).lowercase() else text
    if (statusCode >= 500 || effective >= 500) return SupabaseWorkServiceError.InvalidResponse(maxOf(statusCode, effective))
    if (statusCode == 429 || effective == 429) return SupabaseWorkServiceError.RateLimited(null)
    if (raw.contains("invalid api key")) return SupabaseWorkServiceError.InvalidAPIKey
    val jwtWords = raw.contains("jwt") || raw.contains("\"exp\" claim") || raw.contains("exp claim") || raw.contains("token is expired") || raw.contains("invalidjwt")
    if (jwtWords && (effective in setOf(400, 401, 403) || statusCode in setOf(400, 401, 403))) return SupabaseWorkServiceError.SessionExpired
    if (effective == 401) return SupabaseWorkServiceError.SessionExpired
    if (raw.contains("bucket not found") || raw.contains("nosuchbucket")) return SupabaseWorkServiceError.DatabaseSchemaMissing
    if (effective == 409 || raw.contains("already exists") || raw.contains("duplicate")) return PrivateStorageError.alreadyExists
    if (effective == 413 || raw.contains("payload too large") || raw.contains("entitytoolarge") || raw.contains("maximum allowed size")) return PrivateStorageError.tooLarge
    val notFound = effective == 404 || raw.contains("not_found") || raw.contains("not found") || raw.contains("nosuchkey")
    if (notFound) return if (operation == PrivateStorageOperation.upload) SupabaseWorkServiceError.DatabaseSchemaMissing else PrivateStorageError.objectMissing
    if (effective == 403) return PrivateStorageError.forbidden
    return SupabaseWorkServiceError.InvalidResponse(effective)
}

private fun requireSafe(bucket: String, path: String) {
    if (!PrivateStorage.isSafeBucket(bucket) || !PrivateStorage.isSafeObjectPath(path)) throw PrivateStorageError.invalidPath
}

/** 비공개 버킷에 올린다. POST /storage/v1/object/<bucket>/<path> · **x-upsert 없음**(같은 경로를 덮지 않는다). 시도마다 새 uuid 경로는 호출부 몫. */
suspend fun SupabaseWorkService.uploadPrivateObject(bucket: String, path: String, data: ByteArray, contentType: String, accessToken: String): String {
    requireSafe(bucket, path)
    val r = rawRequest("/storage/v1/object/$bucket/$path", "POST", emptyList(), data, contentType, accessToken, null, emptyMap())
    if (r.statusCode !in 200..299) throw privateStorageError(r.statusCode, r.body, PrivateStorageOperation.upload)
    return path
}

/** 캡처 한 장을 올린다(②). 경로는 FeedbackShotWire.objectPath 가 만든다. */
suspend fun SupabaseWorkService.uploadFeedbackShot(accessToken: String, path: String, jpeg: ByteArray) {
    uploadPrivateObject(FeedbackShotWire.bucket, path, jpeg, PrivateStorage.jpegContentType, accessToken)
}

/** 올린 캡처를 제보에 붙인다(③). 응답이 봉투 모양이 아니면 unknown(실패로 친다). */
suspend fun SupabaseWorkService.attachFeedbackShot(accessToken: String, reportID: String, path: String, width: Long, height: Long): FeedbackAttachOutcome {
    val data = send(FeedbackShotWire.attachPath, "POST", emptyList(), encode(FeedbackAttachShotRequest.serializer(), FeedbackAttachShotRequest(reportID, path, width, height)), accessToken, null)
    val response = swiftTry { decode(FeedbackAttachShotResponse.serializer(), data) } ?: return FeedbackAttachOutcome.unknown
    return FeedbackAttachOutcome.from(response)
}

/** 여러 제보의 캡처를 한 번에(목록 뒤 한 왕복). 내 제보만 온다(판정은 서버). */
suspend fun SupabaseWorkService.fetchFeedbackShots(accessToken: String, reportIDs: List<String>): Map<String, List<FeedbackShot>> {
    val data = send(FeedbackShotWire.listPath, "POST", emptyList(), encode(FeedbackShotsRequest.serializer(), FeedbackShotsRequest(reportIDs.map { it.lowercase() })), accessToken, null)
    return FeedbackShotWire.grouped(decode(ListSerializer(FeedbackShotRow.serializer()), data))
}
