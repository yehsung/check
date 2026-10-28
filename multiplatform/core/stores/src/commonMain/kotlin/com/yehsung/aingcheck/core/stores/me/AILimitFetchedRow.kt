// 원본: Sources/CheckMobileKit/Me/MeAILimitsService.swift:52-139(AILimitFetchedRow · fetchMyAILimits 의 행 → 값 정규화) @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceLabelContract
import com.yehsung.aingcheck.core.rules.ailimit.AILimitPlanLabelContract
import com.yehsung.aingcheck.core.rules.text.TextScalars
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftISO8601
import com.yehsung.aingcheck.core.wire.models.AILimitServerRow

/**
 * 파싱까지 끝난 내 AI 리밋 행(폰은 이 축에서 **읽기만** 한다). 스토어는 이 값만 본다 — 묶는 일(기기별 · 기기 안에서 제공자별)은 스토어가 한다.
 * 요청 · 행 디코드 · 행 거르기는 net `fetchMyAILimitRows`(W1-d), 이 파일은 Swift `fetchMyAILimits` 의 `compactMap` 몫(6차 c-fold 가 G5 골든
 * `fetchMyAILimits#data` 결과를 대조하려고 옮겼다 — 나 스토어 W2-c 는 이 함수를 부른다).
 *
 * INV-MeAILimitsService-ff53660f 이식: `device_id`·`device_label` 을 **받는다** — 서버 PK 가 (user_id, device_id, provider)라 행이 이미 기기별이다.
 * 제공자당 최신 행 하나로 접으면 맥 A 에서 끈 제공자가 맥 B 의 행에 밀려 되살아나고, 두 맥의 값이 누구 것인지 말하지 못한다. 그래서 [deviceID] 에는
 * **기본값이 없다**(기기 신원을 지어내지 않는다 — 비면 그 행을 버린다).
 */
data class AILimitFetchedRow(
    /** 이 행을 올린 맥. 기본값 없음 — 이 축이 비면 기기별 묶기가 조용히 한 묶음으로 접힌다. */
    val deviceID: String,
    /** 그 맥의 컴퓨터 이름(없으면 null → 묶음 머리는 `이름 모를 맥 ABCD`). */
    val deviceLabel: String?,
    val provider: String,
    val fiveHourPercent: Double?,
    val fiveHourResetsAt: SwiftDate?,
    val weeklyPercent: Double?,
    val weeklyResetsAt: SwiftDate?,
    val planLabel: String?,
    val observedAt: SwiftDate,
) {
    companion object {
        /**
         * 서버 행 하나 → 값. 버리는 행 둘(null): `observed_at` 을 못 읽은 행(신선도 축이 그 값 하나로 선다 — 0% 로 지어내지 않는다) ·
         * `device_id` 가 빈 행(어느 맥의 것인지 모른다). 날짜는 Swift `parseDate`(소수초 판 → 기본 판 — 앱의 날짜 파서 한 벌)로 푼다.
         */
        fun from(row: AILimitServerRow): AILimitFetchedRow? {
            val observed = SwiftISO8601.parse(row.observedAt) ?: return null
            val deviceID = TextScalars.trimmingWhitespacesAndNewlines(row.deviceId ?: "")
            if (deviceID.isEmpty()) return null
            return AILimitFetchedRow(
                deviceID = deviceID,
                // 이름은 올리는 쪽과 같은 규약으로 접는다 — 공백뿐이면 없는 것으로, 상한을 넘으면 잘라서.
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

        /** Swift `rows.compactMap { … }` — 서버 차례 그대로(정렬은 스토어가 한다 — 서버 정렬을 믿지 않는다). */
        fun fromRows(rows: List<AILimitServerRow>): List<AILimitFetchedRow> = rows.mapNotNull(::from)
    }
}
