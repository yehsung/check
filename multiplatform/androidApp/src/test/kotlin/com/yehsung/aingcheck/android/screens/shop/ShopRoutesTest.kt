// 원본: Sources/CheckMobileKit/Me/MeGachaHaptics.swift @ 3bd04bd (햅틱 짝 — 사건마다 한 번, 공개 · 반전은 성공)
//
// Android 껍데기의 순수 판정: 기계 햅틱 사건 → Android 햅틱 상수(API 30 경계) · 애니메이션 배율 0 = 동작 줄이기.
package com.yehsung.aingcheck.android.screens.shop

import android.view.HapticFeedbackConstants
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineHapticEvent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ShopRoutesTest {
    private val every: List<GachaMachineHapticEvent> = listOf(
        GachaMachineHapticEvent.Ratchet, GachaMachineHapticEvent.Refuse, GachaMachineHapticEvent.Commit, GachaMachineHapticEvent.Rumble,
        GachaMachineHapticEvent.Land, GachaMachineHapticEvent.Tap(1), GachaMachineHapticEvent.Tap(2), GachaMachineHapticEvent.Tap(3),
        GachaMachineHapticEvent.GoldFlip, GachaMachineHapticEvent.Reveal, GachaMachineHapticEvent.GoldReveal, GachaMachineHapticEvent.Shard,
    )

    @Test
    fun everyMachineBeatPlaysSomething() {
        for (sdk in listOf(26, 30, 36)) for (event in every) {
            assertTrue("$event @ $sdk 가 아무것도 안 낸다", AndroidGachaHapticMap.constants(event, sdk).isNotEmpty())
        }
    }

    @Test
    fun revealIsConfirmAndRefuseIsRejectFrom30() {
        assertEquals(listOf(HapticFeedbackConstants.CONFIRM), AndroidGachaHapticMap.constants(GachaMachineHapticEvent.Reveal, 36))
        assertEquals(listOf(HapticFeedbackConstants.REJECT), AndroidGachaHapticMap.constants(GachaMachineHapticEvent.Refuse, 36))
        // 30 미만엔 CONFIRM · REJECT 가 없다 — 그 상수를 내면 그 기기에선 조용하다(가까운 것으로 접는다).
        assertFalse(HapticFeedbackConstants.CONFIRM in AndroidGachaHapticMap.constants(GachaMachineHapticEvent.Reveal, 26))
        assertFalse(HapticFeedbackConstants.REJECT in AndroidGachaHapticMap.constants(GachaMachineHapticEvent.Refuse, 26))
        // 황금 공개는 묵직 + 성공 두 박(iOS heavy + success).
        assertEquals(2, AndroidGachaHapticMap.constants(GachaMachineHapticEvent.GoldReveal, 36).size)
        // 톡톡은 셋째만 확인(1 → 3 으로 세진다).
        assertEquals(listOf(HapticFeedbackConstants.KEYBOARD_TAP), AndroidGachaHapticMap.constants(GachaMachineHapticEvent.Tap(1), 36))
        assertEquals(listOf(HapticFeedbackConstants.CONFIRM), AndroidGachaHapticMap.constants(GachaMachineHapticEvent.Tap(3), 36))
    }

    @Test
    fun reduceMotionOnlyWhenAnimatorScaleIsZero() {
        assertTrue(ReduceMotion.isOn(0f))
        assertFalse(ReduceMotion.isOn(1f))
        assertFalse(ReduceMotion.isOn(0.5f))
    }
}
