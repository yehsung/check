// 원본: Sources/CheckCore/SupabaseWorkServiceAILimits.swift:1-425 @ a90d8623 (ai_limits 업로드 본문 · 기기 목록 · 메인 기기 쓰기)
// 읽기 둘(내 행 · 고른 기기)은 core/net 것을 쓴다(지시서 §3): `fetchMyAILimitRows` + core/stores `AILimitFetchedRow.fromRows`(행 거르기 한 자리) ·
// `fetchAILimitMainDeviceID`. 요청은 [SupabaseWorkService.sendNoBody] 위 이 패키지 확장 함수로 짠다(새 엔진 0 — 단일 팩토리 클라이언트 그대로).
// ai_limits 업로드는 **깃발 없이** 연다(W-3 #11 — 서버 ④·⑥ 대상 아님, device_id ≤128 CHECK 뿐). 토큰 축 표(token_usage_*)는 한 줄도 건드리지 않는다.
package com.yehsung.aingcheck.feature.desktop.ailimits

import com.yehsung.aingcheck.core.rules.text.codePointCountCompat
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.fetchMyAILimitRows
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDevice
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceLabelContract
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceObservation
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceRoster
import com.yehsung.aingcheck.core.rules.ailimit.AILimitPlanLabelContract
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProviderSnapshot
import com.yehsung.aingcheck.core.rules.ailimit.AILimitSnapshotBundle
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindow
import com.yehsung.aingcheck.core.rules.text.TextScalars
import com.yehsung.aingcheck.core.stores.me.AILimitFetchedRow
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftISO8601
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// INV-SupabaseWorkServiceAILimits-b737a494 이식: PGRST102 — 배열 본문의 키 집합이 행마다 다르면 400 으로 본문 전체가 거절된다(조용하다).
//   그래서 [AILimitUpsertRow.toJson] 은 열 칸 전부를 **명시적 null** 로 적는다(값 행·비우는 행이 글자까지 같은 키 집합).
// INV-SupabaseWorkServiceAILimits-8fa44215 이식: 계정 지문(`account_fingerprint`)은 **본문에 싣지 않는다**(처리방침 "계정 식별자는 올리지 않는다").
// INV-SupabaseWorkServiceAILimits-f345df3f 이식: 지문 **생성은 남는다** — 업로드 게이트(AILimitUploadLedger)의 로컬 비교에만 쓴다.
// INV-SupabaseWorkServiceAILimits-73189b0b 이식: 서버 칸·마이그레이션은 건드리지 않는다(안 보내면 null 로 남는다).
// INV-SupabaseWorkServiceAILimits-42ad8764 이식: 기기 이름(`device_label`)은 아홉 칸 옆의 **열째 칸**이다(Windows = COMPUTERNAME).
// INV-SupabaseWorkServiceAILimits-cc9c3ad1 이식: 값 행도 비우는 행도 이 칸을 적는다(null 이면 명시적 null).
// INV-SupabaseWorkServiceAILimits-e29d6d32 이식: 처리방침의 "올라가는 것" 열거에 기기 이름이 들어가야 한다 — Windows 출시 문구 검토 항목(코드 아님).

/** `ai_limits` 한 행. 키 순서·이름 = Swift CodingKeys. */
data class AILimitUpsertRow(
    val userId: String,
    val deviceId: String,
    /** INV-SupabaseWorkServiceAILimits-775b74ef 이식: **PK 가 아니다** — 가르는 것은 device_id 뿐, 이름은 사람이 알아보는 라벨. */
    val deviceLabel: String?,
    val provider: String,
    val fiveHourPercent: Double?,
    val fiveHourResetsAt: String?,
    val weeklyPercent: Double?,
    val weeklyResetsAt: String?,
    val planLabel: String?,
    val observedAt: String,
) {
    companion object {
        val keys: List<String> = listOf(
            "user_id", "device_id", "device_label", "provider", "five_hour_percent", "five_hour_resets_at",
            "weekly_percent", "weekly_resets_at", "plan_label", "observed_at",
        )
    }

    /** INV-SupabaseWorkServiceAILimits-b6fe573e 이식: **합성 인코더를 쓰지 않는다**(null 키를 빼면 PGRST102). 열 칸을 전부 적는다. */
    fun toJson(): JsonObject {
        fun s(v: String?) = v?.let(::JsonPrimitive) ?: JsonNull
        fun d(v: Double?) = v?.let(::JsonPrimitive) ?: JsonNull
        return JsonObject(
            linkedMapOf(
                "user_id" to JsonPrimitive(userId),
                "device_id" to JsonPrimitive(deviceId),
                "device_label" to s(deviceLabel),
                "provider" to JsonPrimitive(provider),
                "five_hour_percent" to d(fiveHourPercent),
                "five_hour_resets_at" to s(fiveHourResetsAt),
                "weekly_percent" to d(weeklyPercent),
                "weekly_resets_at" to s(weeklyResetsAt),
                "plan_label" to s(planLabel),
                "observed_at" to JsonPrimitive(observedAt),
            ),
        )
    }
}

object AILimitUpload {
    const val aiLimitsPath = "/rest/v1/ai_limits"
    /** PK 그대로 — PC 두 대가 같은 계정을 읽어도 서로를 덮지 않는다. */
    const val conflictKey = "user_id,device_id,provider"
    const val prefsPath = "/rest/v1/ai_limits_prefs"
    const val prefsConflictKey = "user_id"
    const val prefer = "resolution=merge-duplicates,return=minimal"

    /** 서버 CHECK(0…100)에 맞게 다듬는다. NaN·무한은 버린다(null) — NaN 이 들어가면 폰의 응답 파싱이 세 제공자 모두 깨진다. */
    fun percent(value: Double?): Double? {
        if (value == null || !value.isFinite()) return null
        return minOf(100.0, maxOf(0.0, value))
    }

    private fun iso(seconds1970: Double): String = SwiftISO8601.format(SwiftDate(seconds1970))

    /** 제공자 스냅샷 하나 → 행 하나. 창이 없으면 null. `observed_at` 은 리더가 응답을 받은 시각(서버 기본값 없음 — 23502). */
    fun row(userID: String, deviceID: String, deviceLabel: String?, snapshot: AILimitProviderSnapshot): AILimitUpsertRow? {
        if (!snapshot.isLinked) return null
        val fiveHour = snapshot.window(AILimitWindow.fiveHour)
        val weekly = snapshot.window(AILimitWindow.weekly)
        val observed = snapshot.latestObservedAt ?: return null
        return AILimitUpsertRow(
            userId = userID,
            deviceId = deviceID,
            deviceLabel = AILimitDeviceLabelContract.normalized(deviceLabel),
            provider = snapshot.provider.rawValue,
            fiveHourPercent = percent(fiveHour?.usedPercent),
            fiveHourResetsAt = fiveHour?.resetsAt?.let(::iso),
            weeklyPercent = percent(weekly?.usedPercent),
            weeklyResetsAt = weekly?.resetsAt?.let(::iso),
            planLabel = AILimitPlanLabelContract.normalized(snapshot.planLabel),
            // INV-SupabaseWorkServiceAILimits-7979d4e7 이식: `snapshot.accountFingerprint` 는 의도적으로 싣지 않는다.
            observedAt = iso(observed),
        )
    }

    /**
     * 그 제공자의 행을 **비우는** 한 행(값 칸 전부 null, PK + observed_at = 지금). DELETE 권한이 없으므로 "비워서 올리기"가 유일한 길.
     * INV-SupabaseWorkServiceAILimits-5242e3c6 이식: 3일 유령 게이트에 기대지 않는다(끈 사람에게 사흘을 기다리게 하지 않는다).
     */
    fun clearingRow(userID: String, deviceID: String, deviceLabel: String?, provider: AILimitProvider, observedAt: SwiftDate): AILimitUpsertRow =
        AILimitUpsertRow(
            userId = userID,
            deviceId = deviceID,
            // INV-SupabaseWorkServiceAILimits-37348ee8 이식: 비우는 행도 이름을 **싣는다**(키 집합이 값 행과 글자까지 같아야 한다).
            deviceLabel = AILimitDeviceLabelContract.normalized(deviceLabel),
            provider = provider.rawValue,
            fiveHourPercent = null, fiveHourResetsAt = null, weeklyPercent = null, weeklyResetsAt = null, planLabel = null,
            observedAt = SwiftISO8601.format(observedAt),
        )

    /** 본문 행들(값 행 + 비우는 행). 비면 빈 목록 = 요청을 보내지 않는다. */
    fun rows(
        userID: String, deviceID: String, deviceLabel: String?, bundle: AILimitSnapshotBundle,
        clearedProviders: List<AILimitProvider>, clearedAt: SwiftDate,
    ): List<AILimitUpsertRow> {
        val valueRows = bundle.visibleProviders.mapNotNull { row(userID, deviceID, deviceLabel, it) }
        // INV-SupabaseWorkServiceAILimits-fb974dde 이식: **같은 PK 를 한 본문에 두 번 담지 않는다**(21000 으로 본문 전체 거절). 중복 제공자도 접는다.
        val taken = valueRows.map { it.provider }.toSet()
        val seen = HashSet<AILimitProvider>()
        val clearing = clearedProviders.filter { it.rawValue !in taken && seen.add(it) }
            .map { clearingRow(userID, deviceID, deviceLabel, it, clearedAt) }
        return valueRows + clearing
    }

    fun body(rows: List<AILimitUpsertRow>): ByteArray = JsonArray(rows.map { it.toJson() }).toString().encodeToByteArray()
}

/** 내 리밋 행들을 올린다(제공자당 한 행). 빈 배열이면 요청을 아예 보내지 않는다. 실패는 던진다(호출측이 삼키고 백오프). */
suspend fun SupabaseWorkService.upsertAILimits(
    accessToken: String,
    userID: String,
    deviceID: String,
    deviceLabel: String?,
    bundle: AILimitSnapshotBundle,
    clearedProviders: List<AILimitProvider>,
    clearedAt: SwiftDate,
) {
    val rows = AILimitUpload.rows(userID, deviceID, deviceLabel, bundle, clearedProviders, clearedAt)
    if (rows.isEmpty()) return
    sendNoBody(
        AILimitUpload.aiLimitsPath, "POST", listOf("on_conflict" to AILimitUpload.conflictKey),
        AILimitUpload.body(rows), accessToken, AILimitUpload.prefer,
    )
}

/**
 * 서버에 행이 있는 내 PC 전부(최근 순). core/net `fetchMyAILimitRows` + core/stores `AILimitFetchedRow.fromRows`(행 거르기 한 자리)를 쓴다.
 * 맥 원본은 값 칸 없이 세 칸만 select 하고 observed_at 을 못 읽은 행도 '관측 없음'으로 남겼다 — 여기서는 공용 읽기를 쓰므로 그런 행은 빠진다(지시서 §3).
 * INV-SupabaseWorkServiceAILimits-23348d41 이식: 날짜는 글자로 받아 파싱한다(`SwiftISO8601.parse` — fromRows 안).
 */
suspend fun SupabaseWorkService.fetchAILimitDevices(accessToken: String, userID: String): List<AILimitDevice> =
    AILimitDeviceRoster.fold(
        AILimitFetchedRow.fromRows(fetchMyAILimitRows(accessToken, userID)).map {
            AILimitDeviceObservation(it.deviceID, it.deviceLabel, it.observedAt.timeIntervalSince1970)
        },
    )

/** `ai_limits_prefs.main_device_id` 의 규칙. INV-SupabaseWorkServiceAILimits-b58d17a4 이식: 상한은 `ai_limits.device_id` 와 같은 128. */
object AILimitMainDeviceIDContract {
    const val maxLength = 128

    fun normalized(raw: String?): String? {
        if (raw == null) return null
        val trimmed = TextScalars.trimmingWhitespacesAndNewlines(raw)
        // Swift `count` = 자소 묶음 수. device_id 는 ASCII(`win:`+hex·uuid)라 스칼라와 같다 — 넘치면 보내지 않고 null 로 접는다.
        if (trimmed.isEmpty() || trimmed.codePointCountCompat() > maxLength) return null
        return trimmed
    }

    /** INV-SupabaseWorkServiceAILimits-74747cf7 이식: `encodeIfPresent` 가 아니다 — null 을 적어야 "안 고른 상태로 되돌리기"가 닿는다. */
    fun body(userID: String, mainDeviceID: String?): ByteArray =
        JsonArray(listOf(JsonObject(linkedMapOf("user_id" to JsonPrimitive(userID), "main_device_id" to (normalized(mainDeviceID)?.let(::JsonPrimitive) ?: JsonNull)))))
            .toString().encodeToByteArray()
}

/** 메인 PC 를 고른다(또는 null 로 되돌린다). 계정당 한 행 upsert. */
suspend fun SupabaseWorkService.upsertAILimitMainDeviceID(accessToken: String, userID: String, mainDeviceID: String?) {
    sendNoBody(
        AILimitUpload.prefsPath, "POST", listOf("on_conflict" to AILimitUpload.prefsConflictKey),
        AILimitMainDeviceIDContract.body(userID, mainDeviceID), accessToken, AILimitUpload.prefer,
    )
}
