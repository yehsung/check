// K7 번역(시험 도우미): 서버 트리거 payload(APNs 모양, contract/push/payloads) → FCM data 전용 메시지의 `data` 맵.
// push-send 의 buildFcmMessage(xplat-staging/push-send/fcm.ts) data 몫과 같은 규칙이다 — 앱은 SQL payload 를 보지 않으므로
// 이 번역은 시험에만 있다.
//   · 최상위 키(aps · _apns · 예약 키 from/notification/message_type/collapse_key · google*/gcm* 접두 제외) → 문자열 값
//     (null 은 뺀다, 숫자·참거짓은 글자로, 객체는 JSON 글자로)
//   · type 이 없으면 kind
//   · aps.alert.title/body → title/body, aps.category → category, aps["thread-id"] → thread_id
package com.yehsung.aingcheck.android.push

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

object K7DataMessage {
    private val RESERVED = setOf("from", "notification", "message_type", "collapse_key")

    fun fromSqlPayload(payloadJson: String, kind: String): Map<String, String> {
        val payload = Json.parseToJsonElement(payloadJson).jsonObject
        val data = LinkedHashMap<String, String>()
        for ((k, v) in payload) {
            if (k == "aps" || k == "_apns" || k in RESERVED || k.startsWith("google") || k.startsWith("gcm")) continue
            when (v) {
                JsonNull -> Unit
                is JsonPrimitive -> data[k] = v.content
                else -> data[k] = v.toString()
            }
        }
        if (data["type"] == null) data["type"] = kind
        val aps = payload["aps"] as? JsonObject
        val alert = aps?.get("alert") as? JsonObject
        (alert?.get("title") as? JsonPrimitive)?.takeIf { it.isString }?.let { data["title"] = it.content }
        (alert?.get("body") as? JsonPrimitive)?.takeIf { it.isString }?.let { data["body"] = it.content }
        (aps?.get("category") as? JsonPrimitive)?.takeIf { it.isString }?.let { data["category"] = it.content }
        (aps?.get("thread-id") as? JsonPrimitive)?.takeIf { it.isString }?.let { data["thread_id"] = it.content }
        return data
    }
}
