// 원본: Sources/check/WorkTimerStore.swift @ db93317f — 3654-3656(canToggleWorkByShortcut = canSync && isSignedIn && !isTeamless)
//       · 1896-1898(isTeamless = isSignedIn && currentTeamID == nil) · 1890-1892(isSignedIn = session != nil)
//       · Sources/check/WorkTimerStoreAuth.swift:249-296 @ 5ed8c128(currentTeamID 는 소속 확인 응답으로만 선다 — 오프라인 부팅이면 nil 로 남는다)
//       · Sources/check/WorkShortcut.swift:326·398(단축키 누름은 이 게이트를 먼저 묻는다 — 거절이면 삑 소리만)
//
// W-13 #4 · W-14 #7 — 근무 토글 단축키 게이트의 순수 함수. ★ 맥 주석대로 **두 게이트는 짝**이다: 알약(홈 HeaderCard)이 그려지는 조건
// (로그인 + !isTeamless — SharedRouter.resolve 가 홈을 내는 조건)과 같아야 한다. 하나만 바꾸면 로그아웃 상태의 누름이 버려질 로컬 근무를
// 시작하거나(재로그인 때 버려진다) 무소속의 누름이 영속 큐에 start 를 남긴다.
//
// 소속 미확정(오프라인 부팅 — 소속 읽기가 실패해 teamID 가 아직 null): 맥 isTeamless 는 membershipConfirmed 를 보지 않고
// currentTeamID == nil 만 본다 → **거절**(삑). 맥 큐 드레인도 그동안 currentTeamID 가 없어 throw 한다(WorkTimerStore.swift:3372-3375 @ 5ed8c128).
// 그래서 여기도 teamID null 이면 거절이다 — '미확정이면 허용' 은 맥에 없는 동작이다(W-14 #7 판정).
package com.yehsung.aingcheck.desktop.pages.work

import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionProfile

object WorkShortcutGate {
    /** 맥 isTeamless 그대로: 로그인했고 소속 팀 id 가 없다(확정 무소속 **과** 아직 못 읽음 둘 다). */
    fun isTeamless(isSignedIn: Boolean, teamID: String?): Boolean = isSignedIn && teamID == null

    /** 맥 canToggleWorkByShortcut 그대로: canSync && 로그인 && !isTeamless. */
    fun canToggle(isSignedIn: Boolean, teamID: String?, canSync: Boolean): Boolean =
        canSync && isSignedIn && !isTeamless(isSignedIn, teamID)

    /** 진리표 꼴(시험·옛 호출): 팀 있음 = teamID 있음. */
    fun canToggle(isSignedIn: Boolean, hasTeam: Boolean, canSync: Boolean): Boolean =
        canToggle(isSignedIn, if (hasTeam) "team" else null, canSync)

    /**
     * 세션 값에서. 로그인 = 단계 SignedIn **이고** 프로필이 있다(맥 session != nil 의 Windows 짝 — 실행 직후·업데이트 필요·다른 실행
     * 단계에서는 홈 알약이 안 그려지므로 거절 쪽이 짝이다). 소속 = 프로필의 teamID(SessionStore.refreshProfile 이 소속 응답으로만 채운다).
     */
    fun canToggle(phase: SessionPhase, profile: SessionProfile?, canSync: Boolean): Boolean =
        canToggle(isSignedIn = phase == SessionPhase.SignedIn && profile != null, teamID = profile?.teamID, canSync = canSync)
}
