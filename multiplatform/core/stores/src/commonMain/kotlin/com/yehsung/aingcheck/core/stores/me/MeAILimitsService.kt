// 원본: Sources/CheckMobileKit/Me/MeAILimitsService.swift:37-139(AILimitFetchedRow · fetchMyAILimits 결과 정규화) · Sources/CheckCore/SupabaseWorkServiceAILimits.swift:252-270(AILimitPlanLabelContract — I 갈래 파일이지만 폰 읽기가 쓰는 정규화) @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.fetchMyAILimitRows
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceLabelContract
import com.yehsung.aingcheck.core.rules.text.TextScalars
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftISO8601
import com.yehsung.aingcheck.core.wire.models.AILimitServerRow

// 폰의 AI 리밋 읽기(ai_limits 표 · v0.3.45). 폰은 이 축에서 **읽기만** 한다 — 자격증명을 읽는 쪽은 맥(Windows 재개 뒤 PC) 하나뿐이고
// (2026-10-07 사용자 결정), 폰이 제공자 API 를 직접 부르는 길은 아예 없다. 그래서 여기 있는 것은 GET 하나(W1-d `fetchMyAILimitRows`)의
// **결과 정규화**다. RPC 가 아니라 표를 직접 읽는다(RLS 가 본인 행만 연다 — 읽기 RPC 는 서버가 0개로 못 박았다).
//
// INV-MeAILimitsService-ff53660f 이식: `device_id`·`device_label` 은 **받는다**(v0.3.47 — 기기 축). 0.3.46 까지는 "기기 식별자는 화면에 쓸 일이
//   없다"며 안 받았고 그 문장이 결함의 뿌리였다 — 서버 PK 가 (user_id, device_id, provider) 라 행이 이미 기기별인데 기기 칸 없이는
//   "제공자당 최신 행 하나"로 접을 수밖에 없어 ① 맥 A 에서 끈 제공자가 맥 B 의 더 새로운 행에 밀려 되살아나고 ② 누구 값인지 말하지 않았다.
// INV-MeAILimitsService-e8b002fa 이식: 이 `select`(W1-d 가 같은 칸 목록으로 보낸다)는 `device_label` 칸이 있는 서버를 요구한다
//   (20261008120000_ai_limits_devices.sql). 없는 칸을 적으면 PostgREST 가 400 으로 응답 전체를 거절해 카드가 통째로 빈다 — 운영 서버엔 이미
//   올라가 있다(Android 첫 판은 그 뒤에 나간다).
// 날짜는 두 모양(소수초 있음/없음)이 한 응답에 섞여 온다 — 문자열로 받아 Swift `parseDate` 와 같은 규칙(SwiftISO8601)으로 푼다.

/** 파싱까지 끝난 행. 스토어는 이 값만 본다. */
data class AILimitFetchedRow(
    /** 이 행을 올린 맥. **기본값이 없다** — 이 축이 비면 기기별 묶기가 한 묶음으로 접힌다(기기 신원을 지어내지 않는다). */
    val deviceID: String,
    /** 그 맥의 컴퓨터 이름(없으면 null → 묶음 머리는 `이름 모를 맥 ABCD`). */
    val deviceLabel: String? = null,
    val provider: String,
    val fiveHourPercent: Double?,
    val fiveHourResetsAt: SwiftDate?,
    val weeklyPercent: Double?,
    val weeklyResetsAt: SwiftDate?,
    val planLabel: String?,
    val observedAt: SwiftDate,
)

/**
 * 플랜 라벨의 단 하나의 규칙(1…32 **스칼라** — 서버 CHECK `char_length` 와 같은 눈금). 넘치면 **버린다**(잘라서 뜻이 반쯤 남은 라벨보다
 * 없는 쪽이 정직하다). 올리는 쪽(Windows 리더 — W2-h 보류)과 읽는 쪽이 같은 함수를 부른다.
 */
object AILimitPlanLabelContract {
    const val maxLength = 32

    fun normalized(raw: String?): String? {
        if (raw == null) return null
        val trimmed = TextScalars.trimmingWhitespacesAndNewlines(raw)
        if (trimmed.isEmpty() || MeText.scalarCount(trimmed) > maxLength) return null
        return trimmed
    }
}

object MeAILimitsService {
    /**
     * 서버 행 → 정규화한 행. 버리는 행 둘(서비스도 같은 자리에서 버린다 — 방어로 한 번 더):
     *  · `observed_at` 을 못 읽은 행 — 신선도 축이 그 값 하나로 서 있다(0% 로 지어내면 "하나도 안 썼다"는 단정이 된다).
     *  · `device_id` 가 빈 행 — **어느 맥의 것인지 모르는 값**(억지로 한 묶음에 몰면 v0.3.46 의 결함이다).
     * 이름은 **올리는 쪽과 같은 규약**으로 접는다(공백뿐이면 없는 것, 상한을 넘으면 자소 단위로 자른다).
     */
    fun normalized(rows: List<AILimitServerRow>): List<AILimitFetchedRow> = rows.mapNotNull { row ->
        val observed = SwiftISO8601.parse(row.observedAt) ?: return@mapNotNull null
        val deviceID = TextScalars.trimmingWhitespacesAndNewlines(row.deviceId ?: "")
        if (deviceID.isEmpty()) return@mapNotNull null
        AILimitFetchedRow(
            deviceID = deviceID,
            deviceLabel = AILimitDeviceLabelContract.normalized(row.deviceLabel),
            provider = row.provider,
            fiveHourPercent = row.fiveHourPercent,
            fiveHourResetsAt = row.fiveHourResetsAt?.let(SwiftISO8601::parse),
            weeklyPercent = row.weeklyPercent,
            weeklyResetsAt = row.weeklyResetsAt?.let(SwiftISO8601::parse),
            planLabel = AILimitPlanLabelContract.normalized(row.planLabel),
            observedAt = observed,
        )
    }

    /** 내 리밋 행 전부(제공자 × 기기). 묶는 일(기기별 · 기기 안에서 제공자별)은 스토어가 한다 — 서버 정렬을 믿지 않는다. */
    suspend fun fetchMyAILimits(service: SupabaseWorkService, accessToken: String, userID: String): List<AILimitFetchedRow> =
        normalized(service.fetchMyAILimitRows(accessToken, userID))
}
