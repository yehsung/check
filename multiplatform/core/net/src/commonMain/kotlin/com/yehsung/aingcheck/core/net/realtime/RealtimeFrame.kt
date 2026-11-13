// 원본: Sources/CheckCore/RealtimeTransport.swift:46-186(RealtimeFeature · RealtimeFrame) @ 1b8260d
package com.yehsung.aingcheck.core.net.realtime

import com.yehsung.aingcheck.core.wire.text.WireScalars
import io.ktor.http.URLBuilder
import io.ktor.http.URLProtocol
import io.ktor.http.Url
import io.ktor.http.encodedPath
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Supabase Realtime(Phoenix) 프레임 조립·해석(Swift `RealtimeFrame`). 골든: `contract/golden/realtime/frames.json`.
 *
 * C§4 #16: 조인은 `private=true`(RLS 가 사적 채널을 가린다). 조인 거절 사유는 **만료를 RLS 거절보다 먼저** 가른다 —
 * 만료 토큰을 권한 없음으로 읽으면 갱신 한 번으로 풀릴 것을 30초 고정 대기로 만든다.
 */
object RealtimeFrame {
    fun wireTopic(channel: String): String = "realtime:$channel"

    /** `wss://<프로젝트>/realtime/v1/websocket?apikey=…&vsn=1.0.0`(http 면 ws). 못 만들면 null. */
    fun socketURL(projectURL: String, apiKey: String): String? {
        val base = try { Url(projectURL) } catch (e: Exception) { return null }
        val builder = URLBuilder(base)
        builder.protocol = if (base.protocol.name == "http") URLProtocol.WS else URLProtocol.WSS
        builder.encodedPath = "/realtime/v1/websocket"
        builder.parameters.clear()
        builder.parameters.append("apikey", apiKey)
        builder.parameters.append("vsn", "1.0.0")
        return builder.buildString()
    }

    fun join(channel: String, accessToken: String, isPrivate: Boolean, ref: String): String {
        val payload = JsonObject(
            mapOf(
                "config" to JsonObject(
                    mapOf(
                        "broadcast" to JsonObject(mapOf("self" to JsonPrimitive(false), "ack" to JsonPrimitive(false))),
                        "presence" to JsonObject(mapOf("key" to JsonPrimitive(""))),
                        "postgres_changes" to JsonArray(emptyList()),
                        "private" to JsonPrimitive(isPrivate),
                    ),
                ),
                "access_token" to JsonPrimitive(accessToken),
            ),
        )
        return encode(wireTopic(channel), "phx_join", payload, ref, joinRef = ref)
    }

    fun heartbeat(ref: String): String = encode("phoenix", "heartbeat", JsonObject(emptyMap()), ref, joinRef = null)

    fun accessToken(channel: String, token: String, ref: String, joinRef: String): String =
        encode(wireTopic(channel), "access_token", JsonObject(mapOf("access_token" to JsonPrimitive(token))), ref, joinRef)

    /**
     * 클라 발신 브로드캐스트 1건(1:1 길건너 판 표시 프레임 — Swift `RealtimeFrame.broadcast`, 판 8). **`poke:` 채널에 싣지 마라.**
     * vsn 1.0.0 객체형: 바깥 `event` 는 "broadcast", 바깥 `payload` 에 `{type:"broadcast", event:<이름>, payload:<본문>}`.
     * [joinRef] 는 이 채널 phx_join 의 ref — Phoenix 는 join_ref 가 맞지 않는 push 를 그 채널 것으로 보지 않는다.
     */
    fun broadcast(channel: String, event: String, payload: JsonObject, ref: String, joinRef: String): String = encode(
        wireTopic(channel), "broadcast",
        JsonObject(linkedMapOf("type" to JsonPrimitive("broadcast"), "event" to JsonPrimitive(event), "payload" to payload)),
        ref, joinRef,
    )

    /**
     * 들어온 글자가 **우리 채널의 브로드캐스트**면 이름과 안쪽 본문(Swift `decodeBroadcastPayload`). 아니면 null(깨진 JSON · 다른 토픽 ·
     * 다른 이벤트 · 본문이 객체가 아님). 토픽은 **정확히** 맞아야 한다(누가 보낸 판인지 모르는 본문은 표시할 수 없다).
     */
    fun decodeBroadcastPayload(text: String, channel: String): Pair<String, JsonObject>? {
        val obj = try { parser.parseToJsonElement(text) as? JsonObject } catch (e: Exception) { null } ?: return null
        if (obj["event"].stringOrNull() != "broadcast") return null
        if (obj["topic"].stringOrNull() != wireTopic(channel)) return null
        val envelope = obj["payload"] as? JsonObject ?: return null
        val event = envelope["event"].stringOrNull() ?: return null
        val payload = envelope["payload"] as? JsonObject ?: return null
        return event to payload
    }

    private fun encode(topic: String, event: String, payload: JsonObject, ref: String, joinRef: String?): String {
        val fields = linkedMapOf<String, JsonElement>(
            "topic" to JsonPrimitive(topic), "event" to JsonPrimitive(event), "payload" to payload, "ref" to JsonPrimitive(ref),
        )
        if (joinRef != null) fields["join_ref"] = JsonPrimitive(joinRef)
        return JsonObject(fields).toString()
    }

    private val parser = Json { isLenient = false }

    private fun JsonElement?.stringOrNull(): String? = (this as? JsonPrimitive)?.takeIf { it.isString }?.content

    /**
     * 들어온 글자 → 전송자 사건(모르는 것은 null). `ref` 가 숫자면 글자가 아니라 nil 로 본다(Swift `as? String`).
     * topic 이 없거나 글자가 아니면 내 채널로 친다(Swift 와 같다).
     */
    fun decode(text: String, channel: String, joinRef: String?): RealtimeTransportEvent? {
        val obj = try { parser.parseToJsonElement(text) as? JsonObject } catch (e: Exception) { null } ?: return null
        val event = obj["event"].stringOrNull() ?: return null
        val topic = obj["topic"].stringOrNull()
        val payload = obj["payload"] as? JsonObject ?: JsonObject(emptyMap())
        if (topic == "phoenix" && event == "phx_reply") return RealtimeTransportEvent.HeartbeatAck
        if (!(topic == wireTopic(channel) || topic == null)) return null
        return when (event) {
            "phx_reply" -> {
                val ref = obj["ref"].stringOrNull()
                if (!(joinRef == null || ref == joinRef)) return null
                val status = payload["status"].stringOrNull()
                if (status == "ok") return RealtimeTransportEvent.Joined
                val response = payload["response"] as? JsonObject ?: JsonObject(emptyMap())
                val reason = response["reason"].stringOrNull() ?: response["error"].stringOrNull() ?: status ?: ""
                RealtimeTransportEvent.JoinRejected(classifyJoinError(reason))
            }
            "broadcast" -> RealtimeTransportEvent.Broadcast(payload["event"].stringOrNull() ?: "")
            "phx_error", "phx_close" -> RealtimeTransportEvent.Closed(null)
            "system" -> {
                if (payload["status"].stringOrNull() != "error") return null
                RealtimeTransportEvent.JoinRejected(classifyJoinError(payload["message"].stringOrNull() ?: ""))
            }
            else -> null
        }
    }

    /** 만료(expired · invalid jwt)가 권한 없음(unauthorized · permission · forbidden · rls)보다 먼저. */
    fun classifyJoinError(reason: String): RealtimeJoinRejection {
        val lowered = reason.lowercase()
        if (lowered.contains("expired") || lowered.contains("invalidjwt") || lowered.contains("invalid jwt")) {
            return RealtimeJoinRejection.ExpiredToken
        }
        if (lowered.contains("unauthorized") || lowered.contains("permission") || lowered.contains("not authorized") ||
            lowered.contains("forbidden") || lowered.contains("rls")
        ) {
            return RealtimeJoinRejection.Unauthorized
        }
        return RealtimeJoinRejection.Unknown(reason)
    }
}

/** Swift `RealtimeFeature` — 환경 변수가 이기고(1·true·yes), 없으면 저장된 값(기본 켬). */
object RealtimeFeature {
    const val defaultsKey = "check.realtimeEnabled"
    const val environmentName = "CHECK_REALTIME"

    fun isEnabled(stored: Boolean?, environment: Map<String, String>): Boolean {
        // Swift `trimmingCharacters(in: .whitespaces)` — 인자 없는 trim 은 줄바꿈까지 걷고 getType 이다(G §8-20 #3).
        val raw = environment[environmentName]?.let(WireScalars::trimSwiftWhitespaces)
        if (!raw.isNullOrEmpty()) return raw == "1" || raw.lowercase() == "true" || raw.lowercase() == "yes"
        return stored ?: true
    }
}
