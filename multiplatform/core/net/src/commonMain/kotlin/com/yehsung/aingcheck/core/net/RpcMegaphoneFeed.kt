// 원본: Sources/CheckCore/MegaphoneFeed.swift:297-330(fetchMegaphoneFeed · megaphoneAdminHide) @ main 341eb4e3
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.wire.json.SwiftDecodingErrorKind
import com.yehsung.aingcheck.core.wire.json.SwiftDecodingException
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.json.swiftTry
import com.yehsung.aingcheck.core.wire.messages.MegaphoneAdminHideRequest
import com.yehsung.aingcheck.core.wire.messages.MegaphoneAdminHideResponse
import com.yehsung.aingcheck.core.wire.messages.MegaphoneFeedRequest
import com.yehsung.aingcheck.core.wire.messages.MegaphoneFeedRow
import kotlinx.serialization.json.JsonArray

const val MEGAPHONE_FEED_PATH = "/rest/v1/rpc/megaphone_feed"
const val MEGAPHONE_ADMIN_HIDE_PATH = "/rest/v1/rpc/megaphone_admin_hide"

/** 지난 확성기 한 쪽의 전선 값 — 읽힌 줄(깨진 줄은 빠졌다)과 전선에 실려 온 줄 수(깨진 줄 포함). */
data class MegaphoneFeedResponse(val rows: List<MegaphoneFeedRow>, val wireRowCount: Int)

/**
 * 지난 확성기 한 쪽. [beforeUs] 는 이미 보이는 가장 오래된 줄의 created_epoch_us(첫 쪽은 null — null 로 실린다).
 * 함수가 없는 서버(PGRST202 · 404)는 던진다 — 스토어가 "문 닫힘"으로 접는다.
 */
suspend fun SupabaseWorkService.fetchMegaphoneFeed(accessToken: String, beforeUs: Long?, limit: Int): MegaphoneFeedResponse {
    val data = send(MEGAPHONE_FEED_PATH, "POST", emptyList(), encode(MegaphoneFeedRequest.serializer(), MegaphoneFeedRequest(beforeUs, limit)), accessToken, null)
    return megaphoneFeedResponse(data.decodeToString())
}

/** 응답 글자 → 줄(줄 하나가 깨져도 나머지는 살린다). 배열이 아니면 던진다. */
fun megaphoneFeedResponse(json: String): MegaphoneFeedResponse {
    val array = SwiftJson.parse(json) as? JsonArray
        ?: throw SwiftDecodingException(SwiftDecodingErrorKind.typeMismatch, "$", "megaphone_feed 응답이 배열이 아니다")
    val rows = array.mapNotNull { e -> swiftTry { SwiftJson.decode(MegaphoneFeedRow.serializer(), e) } }
    return MegaphoneFeedResponse(rows, array.size)
}

/** 운영자 [내리기]. 판정은 서버(`is_app_admin()`)가 한다 — 운영자가 아니면 forbidden. */
suspend fun SupabaseWorkService.megaphoneAdminHide(accessToken: String, megaphoneID: String, hidden: Boolean = true): MegaphoneAdminHideResponse {
    val data = send(MEGAPHONE_ADMIN_HIDE_PATH, "POST", emptyList(), encode(MegaphoneAdminHideRequest.serializer(), MegaphoneAdminHideRequest(megaphoneID, hidden)), accessToken, null)
    return decode(MegaphoneAdminHideResponse.serializer(), data)
}
