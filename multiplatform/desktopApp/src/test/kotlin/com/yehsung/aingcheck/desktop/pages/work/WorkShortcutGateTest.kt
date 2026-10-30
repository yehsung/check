// W-13 #4 · W-14 #7 — 맥 WorkTimerStore.swift @ db93317f:3654-3656 canToggleWorkByShortcut = canSync && isSignedIn && !isTeamless ·
// :1896-1898 isTeamless = isSignedIn && currentTeamID == nil 의 진리표.
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

    /** 맥 식을 글자 그대로 옮긴 기준(teamID 는 currentTeamID). 게이트가 이것과 한 칸이라도 다르면 빨강. */
    private fun macFormula(canSync: Boolean, session: Boolean, currentTeamID: String?): Boolean {
        val isSignedIn = session
        val isTeamless = isSignedIn && currentTeamID == null
        return canSync && isSignedIn && !isTeamless
    }

    @Test
    fun `맥 식과 같은 진리표 — 로그인·소속 id·canSync 전 조합`() {
        for (signedIn in listOf(false, true)) for (team in listOf(null, "t1")) for (sync in listOf(false, true)) {
            assertEquals(macFormula(sync, signedIn, team), WorkShortcutGate.canToggle(signedIn, team, sync), "로그인=$signedIn 팀=$team canSync=$sync")
            assertEquals(signedIn && team == null, WorkShortcutGate.isTeamless(signedIn, team))
        }
        // 로그아웃은 무소속이 아니다(맥 isTeamless 는 로그인일 때만 참 — 팀 코드 패널 판정).
        assertFalse(WorkShortcutGate.isTeamless(isSignedIn = false, teamID = null))
    }

    @Test
    fun `소속 미확정(오프라인 부팅) — 맥처럼 거절, 소속 응답이 오면 허용`() {
        // SessionStore.enterSignedIn 직후·refreshProfile 실패: teamID 없는 프로필(맥 currentTeamID nil · membershipConfirmed false).
        val unconfirmed = SessionProfile("u1", "a@b.c")
        assertEquals(macFormula(canSync = true, session = true, currentTeamID = null), WorkShortcutGate.canToggle(SessionPhase.SignedIn, unconfirmed, canSync = true))
        assertFalse(WorkShortcutGate.canToggle(SessionPhase.SignedIn, unconfirmed, canSync = true), "맥은 미확정 동안 삑 — 큐 드레인도 팀 없이 throw")
        val confirmed = unconfirmed.copy(teamID = "t1")
        assertTrue(WorkShortcutGate.canToggle(SessionPhase.SignedIn, confirmed, canSync = true))
        // 음성 대조: 단계가 SignedIn 이 아니면(업데이트 필요·다른 실행) 팀이 있어도 거절 — 홈 알약이 안 그려지는 단계(짝).
        assertFalse(WorkShortcutGate.canToggle(SessionPhase.NeedsUpdate(99), confirmed, canSync = true))
        assertFalse(WorkShortcutGate.canToggle(SessionPhase.AnotherInstanceRunning, confirmed, canSync = true))
    }
}
