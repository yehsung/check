// W-13 #4 — 맥 WorkTimerStore.swift:3654-3656 canToggleWorkByShortcut = canSync && isSignedIn && !isTeamless 의 진리표.
package com.yehsung.aingcheck.desktop.pages.work

import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionProfile
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WorkShortcutGateTest {
    @Test
    fun `진리표 여덟 줄 — 셋이 다 참일 때만`() {
        for (signedIn in listOf(false, true)) for (team in listOf(false, true)) for (sync in listOf(false, true)) {
            assertEquals(signedIn && team && sync, WorkShortcutGate.canToggle(signedIn, team, sync), "로그인=$signedIn 팀=$team canSync=$sync")
        }
    }

    @Test
    fun `세션 값에서 — 소속을 아직 못 읽었거나 로그아웃이면 거절`() {
        val team = SessionProfile("u1", "a@b.c", teamID = "t1")
        val noTeam = SessionProfile("u1", "a@b.c", teamID = null)
        assertTrue(WorkShortcutGate.canToggle(SessionPhase.SignedIn, team, canSync = true))
        assertFalse(WorkShortcutGate.canToggle(SessionPhase.SignedIn, noTeam, canSync = true), "무소속의 누름이 큐에 start 를 남긴다")
        assertFalse(WorkShortcutGate.canToggle(SessionPhase.SignedOut, team, canSync = true), "로그아웃의 누름이 버려질 근무를 시작한다")
        assertFalse(WorkShortcutGate.canToggle(SessionPhase.Launching, team, canSync = true))
        assertFalse(WorkShortcutGate.canToggle(SessionPhase.SignedIn, null, canSync = true))
        assertFalse(WorkShortcutGate.canToggle(SessionPhase.SignedIn, team, canSync = false))
    }
}
