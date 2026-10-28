// 원본: 없음(6차 c-fold 검증 지적 — AILimitFetchedRow 의 행 거르기를 net 을 거치지 않고 직접 잰다. Swift 짝: MeAILimitsService.swift:118-138 compactMap)
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.wire.models.AILimitServerRow
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * 행 거르기는 이 타입 한 자리다(net `fetchMyAILimitRows` 는 거르지 않는다 — Swift `compactMap` 하나). 값 정규화 · 날짜 결과는 G5 골든
 * `fetchMyAILimits#filters`·`#labels`(Swift 가 낸 결과)가 잰다. 여기서는 **버리는 행 · 남기는 행 · 서버 차례**만 net 없이 단언한다 —
 * net 이 다시 거르기 시작해도 이 함수의 거름이 살아 있는지 보이게.
 */
class AILimitFetchedRowTest {
    private fun row(deviceId: String?, observedAt: String, provider: String = "claude") =
        AILimitServerRow(deviceId = deviceId, provider = provider, observedAt = observedAt)

    @Test
    fun dropsRowsWithoutAttributableDeviceOrReadableObservation() {
        assertNull(AILimitFetchedRow.from(row(null, "2026-09-17T05:00:00Z")), "device_id 없음")
        assertNull(AILimitFetchedRow.from(row("", "2026-09-17T05:00:00Z")), "빈 device_id")
        assertNull(AILimitFetchedRow.from(row(" \n\t ", "2026-09-17T05:00:00Z")), "공백뿐인 device_id")
        assertNull(AILimitFetchedRow.from(row("mac-1", "bad")), "못 읽은 observed_at")
        assertNull(AILimitFetchedRow.from(row("mac-1", "")), "빈 observed_at")
    }

    @Test
    fun keepsServerOrderAndTrimsDeviceID() {
        val rows = listOf(
            row("mac-b", "2026-09-17T04:00:00Z"),
            row(" ", "2026-09-17T09:00:00Z"),
            row("\tmac-a\n", "2026-09-17T06:00:00Z", provider = "codex"),
            row("mac-c", "nope"),
            row("mac-b", "2026-09-17T05:00:00.5Z", provider = "antigravity"),
        )
        val got = AILimitFetchedRow.fromRows(rows)
        // 시각 순으로 다시 세우지 않는다(정렬은 스토어 몫 — 서버 정렬을 믿지 않는다) · 버린 행 둘만 빠진다.
        assertEquals(listOf("mac-b" to "claude", "mac-a" to "codex", "mac-b" to "antigravity"), got.map { it.deviceID to it.provider })
    }
}
