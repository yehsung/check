// 원본: Sources/CheckCore/SupabaseWorkModels.swift 1253-1400(Start/Stop/Completed/StatusDevice*Request) ·
//       2811-2990(AutoCloseReason · AwaySync* · WorkTickRequest/Response · WorkTickFailure) @ a90d8623
// H 이름(맥 전용 근무 쓰기)의 와이어 모델 — core/wire 에 넣지 않는다(WireRequestsGoldenTest 의 H 태그 · spec.excluded 가 빨개진다).
package com.yehsung.aingcheck.feature.desktop.work.wire

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.InviteCodeRow
import com.yehsung.aingcheck.core.wire.models.MembershipRow
import com.yehsung.aingcheck.core.wire.models.WorkSessionRow
import com.yehsung.aingcheck.core.wire.models.WorkStatusDeviceRow
import com.yehsung.aingcheck.core.wire.models.WorkStatusRow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Swift `StartSessionRequest`. */
@Serializable
data class StartSessionRequest(
    @SerialName("id") val id: String,
    @SerialName("team_id") val teamId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("started_at") val startedAt: String,
)

/** Swift `StopSessionRequest` — nil 사유 칸은 키째 빠진다(Swift 합성 Encodable 의 encodeIfPresent). */
@Serializable
data class StopSessionRequest(
    @SerialName("ended_at") val endedAt: String,
    @SerialName("duration_seconds") val durationSeconds: Long,
    @SerialName("auto_closed_at") val autoClosedAt: String? = null,
    @SerialName("auto_closed_reason") val autoClosedReason: String? = null,
)

/** Swift `AutoCloseReasonPatchRequest`. */
@Serializable
data class AutoCloseReasonPatchRequest(
    @SerialName("auto_closed_at") val autoClosedAt: String,
    @SerialName("auto_closed_reason") val autoClosedReason: String,
)

/** Swift `AutoCloseCorrectionRequest`. */
@Serializable
data class AutoCloseCorrectionRequest(
    @SerialName("ended_at") val endedAt: String,
    @SerialName("duration_seconds") val durationSeconds: Long,
    @SerialName("auto_closed_at") val autoClosedAt: String,
    @SerialName("auto_closed_reason") val autoClosedReason: String,
)

/** Swift `CompletedSessionRequest`. */
@Serializable
data class CompletedSessionRequest(
    @SerialName("id") val id: String,
    @SerialName("team_id") val teamId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("started_at") val startedAt: String,
    @SerialName("ended_at") val endedAt: String,
    @SerialName("duration_seconds") val durationSeconds: Long,
    @SerialName("auto_closed_at") val autoClosedAt: String? = null,
    @SerialName("auto_closed_reason") val autoClosedReason: String? = null,
)

/** Swift `StatusDeviceInputRequest` — ⑦ 키 넷뿐(session_id·last_seen_at·opened_session 금지: 소유 주장을 지우지 않는다). */
@Serializable
data class StatusDeviceInputRequest(
    @SerialName("team_id") val teamId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("device_id") val deviceId: String,
    @SerialName("last_input_at") val lastInputAt: String,
)

/** Swift `StatusUpsertRequest` — off_work 의 nil `active_session_id` 는 키째 빠진다(Swift 와 같은 바이트). */
@Serializable
data class StatusUpsertRequest(
    @SerialName("team_id") val teamId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("status") val status: String,
    @SerialName("active_session_id") val activeSessionId: String? = null,
    @SerialName("last_seen_at") val lastSeenAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("last_input_at") val lastInputAt: String? = null,
)

/** Swift `StatusDeviceUpsertRequest`. */
@Serializable
data class StatusDeviceUpsertRequest(
    @SerialName("team_id") val teamId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("device_id") val deviceId: String,
    @SerialName("session_id") val sessionId: String,
    @SerialName("last_seen_at") val lastSeenAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("last_input_at") val lastInputAt: String? = null,
    @SerialName("opened_session") val openedSession: Boolean,
)

/** Swift `ReopenSessionRequest` — **명시적 null**(encodeNil)이라 직렬화기가 아니라 손으로 짠다. */
object ReopenSessionBody {
    fun json(resetAutoClose: Boolean): JsonObject = JsonObject(
        buildMap {
            put("ended_at", JsonNull)
            put("duration_seconds", JsonNull)
            if (resetAutoClose) {
                put("auto_closed_at", JsonNull)
                put("auto_closed_reason", JsonNull)
            }
        },
    )
}

/** Swift `AwaySyncResponse`(Decodable). 모든 칸 선택. */
@Serializable
data class AwaySyncResponse(
    @SerialName("status") val status: String? = null,
    @SerialName("server_now") val serverNow: String? = null,
    @SerialName("close_threshold_seconds") val closeThresholdSeconds: Long? = null,
    @SerialName("backstop_seconds") val backstopSeconds: Long? = null,
    @SerialName("freeze_seconds") val freezeSeconds: Long? = null,
    @SerialName("open_session") val openSession: OpenSessionPayload? = null,
) {
    @Serializable
    data class OpenSessionPayload(
        @SerialName("id") val id: String? = null,
        @SerialName("team_id") val teamId: String? = null,
        @SerialName("started_at") val startedAt: String? = null,
        @SerialName("last_input_at") val lastInputAt: String? = null,
        @SerialName("close_eligible") val closeEligible: Boolean? = null,
        @SerialName("close_due_at") val closeDueAt: String? = null,
    )
}

/** Swift `AwayPolicy` — 임계(초, TimeInterval = Double)가 서버에서 >0 일 때만 선다(㉒). */
data class AwayPolicy(val closeThresholdSeconds: Double, val serverNow: SwiftDate?)

/** Swift `AwayOpenSession` — closeEligible 키가 없으면 false(모르는 자격을 참으로 승격하지 않는다). id 는 서버 글자 그대로. */
data class AwayOpenSession(val sessionID: String, val startedAt: SwiftDate?, val lastInputAt: SwiftDate?, val closeEligible: Boolean)

/** Swift `AwaySync`. */
data class AwaySync(val isOK: Boolean, val policy: AwayPolicy?, val openSession: AwayOpenSession?)

/** Swift `AwaySyncUnavailable` — 함수 없음(databaseSchemaMissing) · 디코드 실패. */
class AwaySyncUnavailable : Exception("AwaySyncUnavailable") {
    override fun equals(other: Any?): Boolean = other is AwaySyncUnavailable
    override fun hashCode(): Int = 1
}

/** Swift `WorkTickRequest` — 선택 칸도 **null 로 싣는다**(encodeNil: PostgREST 가 키 집합으로 오버로드를 고른다). */
data class WorkTickRequest(
    val pTeamId: String?,
    val pHeartbeat: Boolean,
    val pSessionId: String?,
    val pDeviceId: String?,
    val pOpenedSession: Boolean,
    val pLastInputAt: String?,
    val pSeenAt: String,
    val pSince: String,
    val pIncludeMeta: Boolean,
) {
    fun json(): JsonObject = JsonObject(
        linkedMapOf(
            "p_team_id" to (pTeamId?.let(::JsonPrimitive) ?: JsonNull),
            "p_heartbeat" to JsonPrimitive(pHeartbeat),
            "p_session_id" to (pSessionId?.let(::JsonPrimitive) ?: JsonNull),
            "p_device_id" to (pDeviceId?.let(::JsonPrimitive) ?: JsonNull),
            "p_opened_session" to JsonPrimitive(pOpenedSession),
            "p_last_input_at" to (pLastInputAt?.let(::JsonPrimitive) ?: JsonNull),
            "p_seen_at" to JsonPrimitive(pSeenAt),
            "p_since" to JsonPrimitive(pSince),
            "p_include_meta" to JsonPrimitive(pIncludeMeta),
        ),
    )
}

/** Swift `WorkTickResponse`(Decodable) — 조각(statuses·sessionsActive·sessionsWeekly·devices)은 core/wire 행 그대로. */
@Serializable
data class WorkTickResponse(
    @SerialName("v") val v: Long? = null,
    @SerialName("server_now") val serverNow: String? = null,
    @SerialName("team_id") val teamId: String? = null,
    @SerialName("heartbeat") val heartbeat: Heartbeat? = null,
    @SerialName("statuses") val statuses: List<WorkStatusRow>? = null,
    @SerialName("sessions_active") val sessionsActive: List<WorkSessionRow>? = null,
    @SerialName("sessions_weekly") val sessionsWeekly: List<WorkSessionRow>? = null,
    @SerialName("sessions_since") val sessionsSince: String? = null,
    @SerialName("devices") val devices: List<WorkStatusDeviceRow>? = null,
    @SerialName("away") val away: AwaySyncResponse? = null,
    @SerialName("meta") val meta: Meta? = null,
) {
    @Serializable
    data class Heartbeat(
        @SerialName("mode") val mode: String? = null,
        @SerialName("status") val status: String? = null,
        @SerialName("active_session_id") val activeSessionId: String? = null,
        @SerialName("last_seen_at") val lastSeenAt: String? = null,
        @SerialName("device") val device: Boolean? = null,
    )

    @Serializable
    data class Meta(
        @SerialName("memberships") val memberships: List<MembershipRow>? = null,
        @SerialName("invite_code") val inviteCode: List<InviteCodeRow>? = null,
    )
}

/**
 * Swift `WorkTickFailure` — ⑨ 401 은 이것이 아니라 `SupabaseWorkServiceError.SessionExpired`.
 * 404·PGRST202(functionMissing) · 403·42501(forbidden) · v≠1(contractMismatch) · 디코드 실패(undecodable) → 이 실행 동안 끈다.
 * 5xx(serverError) · 그 밖(rejected) → 일시 실패(3연속이면 1시간, [com.yehsung.aingcheck.feature.desktop.work.service.WorkTickGate]).
 */
sealed class WorkTickFailure(message: String) : Exception(message) {
    data class FunctionMissing(val code: String?) : WorkTickFailure("functionMissing($code)")
    data class Forbidden(val code: String?) : WorkTickFailure("forbidden($code)")
    data class ContractMismatch(val version: Long?) : WorkTickFailure("contractMismatch($version)")
    data object Undecodable : WorkTickFailure("undecodable")
    data class ServerError(val status: Int) : WorkTickFailure("serverError($status)")
    data class Rejected(val status: Int, val code: String?) : WorkTickFailure("rejected($status,$code)")

    /** 이 실행 동안 끄는 갈래인가(⑨). */
    val disablesForRun: Boolean
        get() = this is FunctionMissing || this is Forbidden || this is ContractMismatch || this is Undecodable
}
