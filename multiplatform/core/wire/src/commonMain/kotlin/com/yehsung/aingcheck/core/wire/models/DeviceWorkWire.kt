// 원본: Sources/CheckMobileKit/Session/MobileDeviceService.swift:1-100 · Session/MobilePhoneWorkService.swift:1-107 · Me/MeProfileService.swift:1-9 · Me/MeAILimitsService.swift:38-51 · CheckCore/TodoSync.swift:20-210(전선 몫) · Achievements.swift:262-273 · WeeklyWorkReward.swift:362-380 · Megaphone.swift:27-35 @ 1b8260d
package com.yehsung.aingcheck.core.wire.models

import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.json.swiftTry
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// ---------------------------------------------------------------- 기기 등록 · 릴리스(폰)

/**
 * `client_release(p_platform)` 응답. 앞 다섯 칸은 Swift `ClientReleaseResponse` 그대로다.
 * 뒤 세 칸(`latest_version`·`download_url`·`updated_at`)은 서버가 마이그레이션 20261101100000 부터 더 주는 칸으로 **Kotlin 에만** 있다
 * (Swift 에 없어 Swift 골든 덤프와 맞출 때는 뺀다 — 디코드 골든·요청 골든 시험). 옛 서버(세 칸 없음)면 null 이다.
 * 시각은 이 파일의 다른 서버 시각 칸(`started_at`·`ended_at`)처럼 원문 문자열로 둔다.
 */
@Serializable
data class ClientReleaseResponse(
    @SerialName("status") val status: String? = null,
    @SerialName("platform") val platform: String? = null,
    @SerialName("min_build") val minBuild: Long? = null,
    @SerialName("latest_build") val latestBuild: Long? = null,
    @SerialName("notes") val notes: String? = null,
    @SerialName("latest_version") val latestVersion: String? = null,
    @SerialName("download_url") val downloadUrl: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
)

/** Swift `PushPrefs` — 읽을 때 칸마다 lossy, 없으면 **true**(알림은 기본 켬). 쓸 때는 셋 다 싣는다. */
@Serializable(with = PushPrefs.Serializer::class)
data class PushPrefs(val message: Boolean = true, val gomokuInvite: Boolean = true, val feedbackReply: Boolean = true) {
    object Serializer : KSerializer<PushPrefs> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("PushPrefs")
        override fun deserialize(decoder: Decoder): PushPrefs {
            val c = SwiftDecoding.keyed(decoder)
            return PushPrefs(
                message = c.lossyBool("message") ?: true,
                gomokuInvite = c.lossyBool("gomoku_invite") ?: true,
                feedbackReply = c.lossyBool("feedback_reply") ?: true,
            )
        }
        override fun serialize(encoder: Encoder, value: PushPrefs) {
            (encoder as JsonEncoder).encodeJsonElement(
                JsonObject(
                    mapOf(
                        "message" to JsonPrimitive(value.message),
                        "gomoku_invite" to JsonPrimitive(value.gomokuInvite),
                        "feedback_reply" to JsonPrimitive(value.feedbackReply),
                    ),
                ),
            )
        }
    }
}

@Serializable
data class RegisterDeviceResponse(
    @SerialName("status") val status: String? = null,
    @SerialName("device_id") val deviceId: String? = null,
    @SerialName("push_prefs") val pushPrefs: PushPrefs? = null,
)

@Serializable
data class UnregisterDeviceResponse(
    @SerialName("status") val status: String? = null,
    @SerialName("removed") val removed: Boolean? = null,
)

@Serializable
data class SetPushPrefsResponse(
    @SerialName("status") val status: String? = null,
    @SerialName("push_prefs") val pushPrefs: PushPrefs? = null,
)

/**
 * register_device 본문(iOS 모양 — `p_platform` 은 주입한다: C§3.2 C-2 "MobileDeviceRPC.platform = ios → AppInfo.platform").
 * nil 칸은 키를 뺀다(합성 인코더). Android 는 서버 ① 뒤 `register_device_fcm`(K5) 하나로 간다 — W2-a 몫.
 */
@Serializable
data class RegisterDeviceRequest(
    @SerialName("p_installation_id") val pInstallationId: String,
    @SerialName("p_platform") val pPlatform: String,
    @SerialName("p_app_build") val pAppBuild: Long,
    @SerialName("p_app_version") val pAppVersion: String? = null,
    @SerialName("p_apns_token") val pApnsToken: String? = null,
    @SerialName("p_apns_env") val pApnsEnv: String? = null,
)

@Serializable
data class InstallationRequest(@SerialName("p_installation_id") val pInstallationId: String)

@Serializable
data class SetPushPrefsRequest(
    @SerialName("p_installation_id") val pInstallationId: String,
    @SerialName("p_prefs") val pPrefs: PushPrefs,
)

@Serializable
data class ClientReleaseRequest(@SerialName("p_platform") val pPlatform: String)

// ---------------------------------------------------------------- 폰 근무(work_phone_* — 본문에 시각·길이를 싣지 않는다, C§4 #12)

@Serializable
data class PhoneWorkSessionInfo(
    @SerialName("id") val id: String? = null,
    @SerialName("started_at") val startedAt: String? = null,
    @SerialName("ended_at") val endedAt: String? = null,
    @SerialName("origin") val origin: String? = null,
    @SerialName("reason") val reason: String? = null,
)

@Serializable
data class PhoneWorkWallet(@SerialName("ruby_balance") val rubyBalance: Long? = null)

/** Swift `PhoneWorkResponse` — 칸마다 lossy(`try?`). */
@Serializable(with = PhoneWorkResponse.Serializer::class)
data class PhoneWorkResponse(
    val status: String? = null,
    val session: PhoneWorkSessionInfo? = null,
    val last: PhoneWorkSessionInfo? = null,
    val serverNow: String? = null,
    val checkAt: String? = null,
    val checkAfterSeconds: Long? = null,
    val graceSeconds: Long? = null,
    val wallet: PhoneWorkWallet? = null,
) {
    object Serializer : SwiftDecodableSerializer<PhoneWorkResponse>("PhoneWorkResponse") {
        override fun deserialize(decoder: Decoder): PhoneWorkResponse {
            val c = SwiftDecoding.keyed(decoder)
            return PhoneWorkResponse(
                status = c.lossyString("status"),
                session = c.lossy("session", PhoneWorkSessionInfo.serializer()),
                last = c.lossy("last", PhoneWorkSessionInfo.serializer()),
                serverNow = c.lossyString("server_now"),
                checkAt = c.lossyString("check_at"),
                checkAfterSeconds = c.lossyLong("check_after_seconds"),
                graceSeconds = c.lossyLong("grace_seconds"),
                wallet = c.lossy("wallet", PhoneWorkWallet.serializer()),
            )
        }
    }
}

/**
 * 응답의 뜻(Swift `PhoneWorkOutcome` — MobilePhoneWorkService.swift:68-97). 스토어(W2-f NowStorePhoneWork)가 이것으로만 가른다.
 * 모르는 status 는 [Failed] — 지어내지 않는다.
 */
sealed interface PhoneWorkOutcome {
    /** 근무 중(시작 ok · 이미 근무 중 · touch ok). [alreadyWorking] = 시작을 눌렀는데 이미 열린 세션이 있었다. */
    data class Working(val session: PhoneWorkSessionInfo, val alreadyWorking: Boolean) : PhoneWorkOutcome
    /** 종료가 닫았다. */
    data class Stopped(val session: PhoneWorkSessionInfo?) : PhoneWorkOutcome
    /** 근무 중이 아니다. [last] = 최근 12시간 안에 닫힌 내 폰 세션. */
    data class NotWorking(val last: PhoneWorkSessionInfo?) : PhoneWorkOutcome
    /** 종료가 가리킨 세션이 지금 열린 세션이 아니다. */
    data object Mismatch : PhoneWorkOutcome
    data object NoTeam : PhoneWorkOutcome
    data object Unauthorized : PhoneWorkOutcome
    data object Failed : PhoneWorkOutcome

    companion object {
        fun from(response: PhoneWorkResponse): PhoneWorkOutcome = when (response.status) {
            // 종료 응답은 ended_at 이 찍힌 세션을 싣는다. 시작 · touch 는 열린 세션이다.
            "ok" -> response.session?.let { if (it.endedAt == null) Working(it, alreadyWorking = false) else Stopped(it) } ?: Failed
            "already_working" -> response.session?.let { Working(it, alreadyWorking = true) } ?: Failed
            "not_working" -> NotWorking(response.last)
            "mismatch" -> Mismatch
            "no_team" -> NoTeam
            "unauthorized" -> Unauthorized
            else -> Failed
        }
    }
}

/** stop 본문 — 세션 id 는 소문자(nil 이면 키를 뺀다). start·touch 는 `{}`. */
@Serializable
data class PhoneWorkStopRequest(@SerialName("p_session_id") val pSessionId: String? = null)

// ---------------------------------------------------------------- 나(프로필 카드 · AI 리밋 읽기)

@Serializable
data class MeProfileCardRow(
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
)

/** Swift `AILimitPrefsServerRow`(`ai_limits_prefs?select=main_device_id` 한 행). */
@Serializable
data class AILimitPrefsServerRow(@SerialName("main_device_id") val mainDeviceId: String? = null)

/** Swift `AILimitServerRow`(ai_limits GET 행 — 폰은 읽기만, C§3.2 E-2). 정규화·접기는 W2-c `MeAILimitsService`. */
@Serializable
data class AILimitServerRow(
    @SerialName("device_id") val deviceId: String? = null,
    @SerialName("device_label") val deviceLabel: String? = null,
    @SerialName("provider") val provider: String,
    @SerialName("five_hour_percent") val fiveHourPercent: Double? = null,
    @SerialName("five_hour_resets_at") val fiveHourResetsAt: String? = null,
    @SerialName("weekly_percent") val weeklyPercent: Double? = null,
    @SerialName("weekly_resets_at") val weeklyResetsAt: String? = null,
    @SerialName("plan_label") val planLabel: String? = null,
    @SerialName("observed_at") val observedAt: String,
)

// ---------------------------------------------------------------- 할 일 동기화 전선(TodoSync.swift 의 와이어 몫 — LWW 병합은 W1-c)

/**
 * Swift `TodoSyncWireItem` — 읽을 때는 칸마다 lossy, 쓸 때는 **키 7개를 언제나**(nil 은 null — 모양이 갈리면 서버 검증이
 * 한쪽만 거절한다). 이 타입은 키를 그대로(`created_at_ms`) 쓴다 — 응답은 키 변환 없는 JSONDecoder 로 읽는다.
 */
@Serializable(with = TodoSyncWireItem.Serializer::class)
data class TodoSyncWireItem(
    val id: String?,
    val title: String?,
    val createdAtMs: Long?,
    val updatedAtMs: Long?,
    val completedAtMs: Long?,
    val deletedAtMs: Long?,
    val originDayKey: String?,
) {
    fun toJson(): JsonObject = JsonObject(
        mapOf(
            "id" to str(id), "title" to str(title),
            "created_at_ms" to num(createdAtMs), "updated_at_ms" to num(updatedAtMs),
            "completed_at_ms" to num(completedAtMs), "deleted_at_ms" to num(deletedAtMs),
            "origin_day_key" to str(originDayKey),
        ),
    )

    object Serializer : KSerializer<TodoSyncWireItem> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("TodoSyncWireItem")
        override fun deserialize(decoder: Decoder): TodoSyncWireItem {
            val c = SwiftDecoding.keyedPlain(decoder)
            return TodoSyncWireItem(
                id = c.lossyString("id"),
                title = c.lossyString("title"),
                createdAtMs = c.lossyLong("created_at_ms"),
                updatedAtMs = c.lossyLong("updated_at_ms"),
                completedAtMs = c.lossyLong("completed_at_ms"),
                deletedAtMs = c.lossyLong("deleted_at_ms"),
                originDayKey = c.lossyString("origin_day_key"),
            )
        }
        override fun serialize(encoder: Encoder, value: TodoSyncWireItem) = (encoder as JsonEncoder).encodeJsonElement(value.toJson())
    }
}

private fun str(v: String?) = v?.let { JsonPrimitive(it) } ?: JsonNull
private fun num(v: Long?) = v?.let { JsonPrimitive(it) } ?: JsonNull

/**
 * Swift `TodoSyncRequest.rpcBody()` — `p_changes` + `p_since_ms` 를 **언제나** 싣는다(첫 동기화의 since 는 null 이어도 키가 있어야
 * 서버가 full 로 간다 — C§4 #10 · G §2-3 W1-d ⑥).
 */
data class TodoSyncRequest(val changes: List<TodoSyncWireItem>, val sinceMs: Long?) {
    fun rpcBody(): JsonObject = JsonObject(
        mapOf("p_changes" to JsonArray(changes.map { it.toJson() }), "p_since_ms" to num(sinceMs)),
    )
}

@Serializable(with = TodoSyncRejection.Serializer::class)
data class TodoSyncRejection(val id: String?, val reason: String?) {
    object Serializer : SwiftDecodableSerializer<TodoSyncRejection>("TodoSyncRejection") {
        override fun deserialize(decoder: Decoder): TodoSyncRejection {
            val c = SwiftDecoding.keyedPlain(decoder)
            return TodoSyncRejection(id = c.lossyString("id"), reason = c.lossyString("reason"))
        }
    }
}

/** Swift `TodoSyncResponse` — 칸마다 lossy. 병합 가능 판정(`mergeableResult`)은 W1-c(TodoItem 이 그쪽에 있다). */
@Serializable(with = TodoSyncResponse.Serializer::class)
data class TodoSyncResponse(
    val status: String? = null,
    val items: List<TodoSyncWireItem>? = null,
    val watermarkMs: Long? = null,
    val rejected: List<TodoSyncRejection>? = null,
    val full: Boolean? = null,
    val max: Long? = null,
) {
    object Serializer : SwiftDecodableSerializer<TodoSyncResponse>("TodoSyncResponse") {
        override fun deserialize(decoder: Decoder): TodoSyncResponse {
            val c = SwiftDecoding.keyedPlain(decoder)
            return TodoSyncResponse(
                status = c.lossyString("status"),
                items = c.lossy("items", ListSerializer(TodoSyncWireItem.serializer())),
                watermarkMs = c.lossyLong("watermark_ms"),
                rejected = c.lossy("rejected", ListSerializer(TodoSyncRejection.serializer())),
                full = c.lossyBool("full"),
                max = c.lossyLong("max"),
            )
        }
    }
}

// ---------------------------------------------------------------- W1-c 응답 타입을 받는 RPC 의 **요청** 모양

/** achievement_claim · daily_mission_claim 본문 — key 가 nil 이어도 `{"p_key": null}`(= 받을 수 있는 것 전부). */
fun achievementClaimBody(key: String?): JsonObject = JsonObject(mapOf("p_key" to str(key)))

/** weekly_work_claim 본문 — 두 키를 언제나(nil 은 null). */
fun weeklyWorkClaimBody(weekStart: String?, hours: Long?): JsonObject =
    JsonObject(mapOf("p_week_start" to str(weekStart), "p_hours" to num(hours)))

@Serializable
data class SendMegaphoneRequest(
    @SerialName("p_body") val pBody: String,
    @SerialName("p_request_id") val pRequestId: String,
)

@Suppress("unused")
private val keepSwiftTry = swiftTry { 0 }
