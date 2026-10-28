// 원본: Sources/CheckMobileKit/Session/MobileSignUpView.swift @ 3bd04bd (팀 코드 정규화 — 바뀔 때만 되써 고리를 만들지 않는다 · 주간 목표 1~168)
package com.yehsung.aingcheck.ui.screens.session

import com.yehsung.aingcheck.core.session.signup.SignUpText
import com.yehsung.aingcheck.core.session.team.TeamJoinForm
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TeamFieldRulesTest {
    @Test
    fun codeIsNormalizedOnlyOutsideComposition() {
        assertEquals("AB12CD", TeamFieldRules.normalizedCodeToWrite("ab-12 cd", composing = false))
        // 이미 정규화된 글은 되쓰지 않는다(되쓰면 다시 바뀌어 고리가 된다).
        assertNull(TeamFieldRules.normalizedCodeToWrite("AB12CD", composing = false))
        // 조합 중에는 칸을 고치지 않는다(조합 중 편집은 IME 를 깬다 — E§8.2 ④).
        assertNull(TeamFieldRules.normalizedCodeToWrite("ab-12", composing = true))
    }

    @Test
    fun previewLineColor() {
        assertFalse(TeamFieldRules.previewIsError(TeamJoinForm.PreviewLine("팀 아잉 · 3명 · 주 40시간", isSuccess = true)))
        assertFalse(TeamFieldRules.previewIsError(TeamJoinForm.PreviewLine(SignUpText.previewChecking, isSuccess = false)))
        assertTrue(TeamFieldRules.previewIsError(TeamJoinForm.PreviewLine(SignUpText.previewMiss, isSuccess = false)))
    }

    @Test
    fun goalStepsStayInRange() {
        assertEquals(1L, TeamFieldRules.stepGoal(1, -1))
        assertEquals(168L, TeamFieldRules.stepGoal(168, 1))
        assertEquals(41L, TeamFieldRules.stepGoal(40, 1))
        assertEquals(39L, TeamFieldRules.stepGoal(40, -1))
    }
}
