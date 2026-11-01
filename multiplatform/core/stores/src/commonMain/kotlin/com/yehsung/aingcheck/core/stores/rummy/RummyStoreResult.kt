// 원본: Sources/check/RummyPanelResult.swift:85 (playAgain) · Sources/check/RummyPanel.swift:424 (onPlayAgain → createAndInvite) @ 1a5eeca6
package com.yehsung.aingcheck.core.stores.rummy

import com.yehsung.aingcheck.core.rules.rummy.RummyExitPolicy
import com.yehsung.aingcheck.core.rules.rummy.RummyPhase

/**
 * 결과 [한 판 더] — 같은 판돈 · 같은 공개 여부로 새 탁자를 열고 **끝까지 남은 사람**을 부른다(기권한 사람은 나간 사람이라 부르지 않는다).
 * 끝난 판이 아니거나 앞 동작이 도는 중이면 아무것도 안 한다 — 만들기가 무시된 채 결과만 접히면 사람들을 못 부른다.
 * 거절(루비 부족 등)은 줄을 버리고 로비 안내 자리(`notice`)에 뜬다.
 */
fun RummyStore.playAgain() {
    val finished = match ?: return
    if (phase != RummyPhase.finished || isWorking) return
    finished.stake?.let { selectedStake = it }
    createPublic = finished.isPublic ?: false
    val invitees = RummyExitPolicy.rematchInvitees(finished)
    dismissResult()
    createAndInvite(invitees)
}
