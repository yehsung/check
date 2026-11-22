// 원본: Tests/CheckMobileKitTests/V1019MissionClaimAllTests.swift @ a3d734c5 (폰 1.0.19 — 미션 모두 받기)
package com.yehsung.aingcheck.core.stores.me

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * 판 9 — 일일 미션 [모두 받기](맥 0.3.87 · 폰 1.0.19 · 제보 11-17 서울 "미션 루비 모두 수령" · 대표 #d_xygj8oZRFlfH).
 * 받는 길(`claimAllDailyMissions` → `daily_mission_claim(null)`)은 이미 스토어에 있었다([MeMissionClaimTest] 가 잰다) — 여기는 문턱과 낱말.
 */
class V9MissionClaimAllTest {
    @Test
    fun claimAllShowsOnlyForTwoOrMore() {
        assertTrue(MeDailyMissionSection.Loaded(emptyList(), 2, 10).showsClaimAll)
        assertTrue(MeDailyMissionSection.Loaded(emptyList(), 6, 30).showsClaimAll)
        assertFalse(MeDailyMissionSection.Loaded(emptyList(), 1, 5).showsClaimAll, "하나뿐인데 그 줄 [받기]와 같은 버튼이 하나 더 선다")
        assertFalse(MeDailyMissionSection.Loaded(emptyList(), 0, 0).showsClaimAll)
        assertFalse(MeDailyMissionSection.Hidden.showsClaimAll)
    }

    @Test
    fun copyMatchesMacAndIPhone() {
        assertEquals("모두 받기", MeText.claimAllButton)
        assertEquals("모두 받기, 루비 15개", MeText.claimAllAccessibility(15))
    }
}
