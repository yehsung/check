// 원본: Sources/check/WorkTimerStore.swift @ db93317f — 3645-3656(canToggleWorkByShortcut = canSync && isSignedIn && !isTeamless)
//       · Sources/check/WorkShortcut.swift:326·398(단축키 누름은 이 게이트를 먼저 묻는다 — 거절이면 삑 소리만)
//
// W-13 #4 — 근무 토글 단축키 게이트의 순수 함수. ★ 맥 주석대로 **두 게이트는 짝**이다: 알약(홈 HeaderCard)이 그려지는 조건
// (로그인 + 소속 확정 — SharedRouter.resolve 가 홈을 내는 조건)과 같아야 한다. 하나만 바꾸면 로그아웃 상태의 누름이 버려질 로컬 근무를
// 시작하거나(재로그인 때 버려진다) 무소속의 누름이 영속 큐에 start 를 남긴다.
package com.yehsung.aingcheck.desktop.pages.work

import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionProfile

object WorkShortcutGate {
    /** 맥 canToggleWorkByShortcut 그대로: canSync && 로그인 && 팀 있음. */
    fun canToggle(isSignedIn: Boolean, hasTeam: Boolean, canSync: Boolean): Boolean = canSync && isSignedIn && hasTeam

    /**
     * 세션 값에서. 로그인 = 단계 SignedIn **이고** 프로필이 있다. 팀 있음 = 프로필의 teamID 가 있다 — 소속을 아직 못 읽은 동안(teamID null)은
     * 거절 쪽이다(알약도 아직 안 그려진다 — 홈은 소속 확정 뒤).
     */
    fun canToggle(phase: SessionPhase, profile: SessionProfile?, canSync: Boolean): Boolean =
        canToggle(isSignedIn = phase == SessionPhase.SignedIn && profile != null, hasTeam = profile?.teamID != null, canSync = canSync)
}
