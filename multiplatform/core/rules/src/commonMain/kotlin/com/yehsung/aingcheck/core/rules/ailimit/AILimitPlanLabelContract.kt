// 원본: Sources/CheckCore/SupabaseWorkServiceAILimits.swift:253-271(AILimitPlanLabelContract — 플랫폼 무관, 폰·위젯도 같은 값을 읽는다) @ 1b8260d
package com.yehsung.aingcheck.core.rules.ailimit

import com.yehsung.aingcheck.core.rules.text.TextScalars
import com.yehsung.aingcheck.core.rules.text.codePointCountCompat

/**
 * 플랜 라벨의 단 하나의 규칙(1…32 스칼라). 읽는 쪽(폰 `AILimitFetchedRow` — core/stores me)과 올리는 쪽(맥 — Windows 보류)이 **같은 함수**를
 * 부른다 — 두 벌이 되면 읽는 쪽이 통과시킨 라벨이 올릴 때 서버 CHECK(23514)로 조용히 거절되는 조합이 생긴다.
 * 넘치면 **버린다**(잘라서 뜻이 반쯤 남은 라벨보다 없는 쪽이 정직하다). 눈금은 유니코드 스칼라(서버 `char_length`) — 그래핌이 아니다.
 */
object AILimitPlanLabelContract {
    const val maxLength = 32

    fun normalized(raw: String?): String? {
        if (raw == null) return null
        val trimmed = TextScalars.trimmingWhitespacesAndNewlines(raw)
        if (trimmed.isEmpty() || trimmed.codePointCountCompat() > maxLength) return null
        return trimmed
    }
}
