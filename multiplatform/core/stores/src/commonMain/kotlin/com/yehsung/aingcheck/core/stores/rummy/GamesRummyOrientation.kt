// 원본: Sources/CheckMobileKit/Games/GamesRummyOrientation.swift:17-37 @ ios-1017-cube 61d75d8c(설계서 §10.1 · 사용자 답 "이 화면만 가로")
//
// 폰 아잉 큐브 **판 화면만 가로**. 앱의 나머지는 세로다.
//
// ── 잠금이 가로에 남지 않는 까닭 ──
// 저장된 잠금이 **없다.** 방향은 언제나 지금 상태에서 계산한다(`GamesStore.rummyInterfaceOrientation` → [GamesRummyOrientationRule]). 그래서 '푸는 코드를 잊은 길'이 있을 수 없다:
// 화면이 사라졌거나(`isRummyScreenVisible`) · 판이 끝났거나 · 세션이 끝났으면(`reset`) 그 순간 답이 세로다. 시스템에 알리는 자리는 Activity 하나다(androidApp RummyOrientationDriver).
// 앱을 내려도 방향은 안 바뀐다(앱을 내리는 것은 화면을 떠나는 것이 아니다).
package com.yehsung.aingcheck.core.stores.rummy

import com.yehsung.aingcheck.core.rules.rummy.RummyPhase

enum class GamesRummyInterfaceOrientation { portrait, landscape }

/** 언제 가로인가. */
object GamesRummyOrientationRule {
    /** 판이 도는 판 화면 + 결과의 [최종 판]. 로비 · 방 · 등수 화면은 세로. */
    fun wants(phase: RummyPhase, isScreenVisible: Boolean, finalBoardShown: Boolean): Boolean {
        if (!isScreenVisible) return false
        return when (phase) {
            RummyPhase.playing -> true
            RummyPhase.finished -> finalBoardShown
            RummyPhase.lobby, RummyPhase.room -> false
        }
    }

    fun orientation(phase: RummyPhase, isScreenVisible: Boolean, finalBoardShown: Boolean): GamesRummyInterfaceOrientation =
        if (wants(phase, isScreenVisible, finalBoardShown)) GamesRummyInterfaceOrientation.landscape else GamesRummyInterfaceOrientation.portrait
}
