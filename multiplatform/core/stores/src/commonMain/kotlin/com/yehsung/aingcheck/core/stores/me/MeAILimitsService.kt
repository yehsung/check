// 원본: Sources/CheckMobileKit/Me/MeAILimitsService.swift:37-139(fetchMyAILimits — 행 타입·거르기는 같은 패키지 AILimitFetchedRow.kt, 플랜 라벨은 core/rules AILimitPlanLabelContract) @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.stores.service.fetchMyAILimits
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

// 6차 통합(int-h) 접기: 파싱한 행 타입 `AILimitFetchedRow` · 행 거르기(`AILimitFetchedRow.fromRows`)는 c-fold 가 같은 패키지
// `AILimitFetchedRow.kt` **한 자리**에 먼저 냈고, 플랜 라벨 규칙은 core/rules `AILimitPlanLabelContract`(골든 dates/ailimit plan-labels) 하나다.
// 이 파일은 그 둘을 다시 만들지 않고 부르기만 한다(lanes.yml 6차 c-fold 절 — 두 벌이면 한쪽 거름은 영영 돌지 않는다).

object MeAILimitsService {
    /**
     * 서버 행 → 정규화한 행 — [AILimitFetchedRow.fromRows] 그대로(버리는 행 둘: `observed_at` 을 못 읽은 행 · `device_id` 가 빈 행,
     * 이름·플랜 라벨은 올리는 쪽과 같은 규약으로 접는다). 서버 차례를 지킨다 — 묶는 일은 스토어가 한다.
     */
    fun normalized(rows: List<AILimitServerRow>): List<AILimitFetchedRow> = AILimitFetchedRow.fromRows(rows)

    /** 내 리밋 행 전부(제공자 × 기기) — core/stores `service.fetchMyAILimits`(G5 골든이 그대로 부르는 앱 함수) 한 벌. */
    suspend fun fetchMyAILimits(service: SupabaseWorkService, accessToken: String, userID: String): List<AILimitFetchedRow> =
        service.fetchMyAILimits(accessToken, userID)
}
