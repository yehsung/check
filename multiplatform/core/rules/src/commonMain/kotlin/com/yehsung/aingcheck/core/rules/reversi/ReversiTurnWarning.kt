// 원본: Sources/CheckCore/ReversiTurnWarning.swift @ 12624739 (판정식 몫 — 서명은 스토어 값 대신 원시 인자)
package com.yehsung.aingcheck.core.rules.reversi

import com.yehsung.aingcheck.core.wire.games.ReversiColor

// 아잉 뒤집기 **내 차례 마지막 3초** 판 테두리 경고 — 판정 짝. 계약은 설계서 FLIP/SPEC.md §4.5.
//
// 숫자 함수(`isActive(remaining:)` · `intensity(remaining:)`)와 그림 상수는 오목 [com.yehsung.aingcheck.core.rules.renju.GomokuTurnWarning] 을
// **그대로 부른다** — 문턱·세기·그림이 게임마다 갈리면 한쪽만 고쳐진다. 타입에 묶인 `watchesMyClock` 짝만 리버시 판 값으로 새로 둔다.
// Swift 서명 `watchesMyClock(_ match: ReversiMatchState?)` 의 ReversiMatchState 는 스토어 값(다음 단계)이라 rules 가 기댈 수 없다 —
// 오목 이식([GomokuTurnWarning.watchesMyClock])과 같은 꼴로 판정식을 원시 인자로 옮겼다. 판이 없으면 부르는 쪽이 false 로 접는다.

/** Swift `ReversiTurnWarning` — 내 차례 마지막 몇 초의 판 테두리 경고(리버시 판 짝). 시계를 읽지 않는다(남은 초는 부르는 잎 뷰가 넘긴다). */
object ReversiTurnWarning {
    /**
     * 이 판에서 경고가 **설 수 있는가** — 끝나지 않았고, 내 차례이고, 마감이 돈다.
     * 마감이 null 인 경우(AI 차례 · 화면이 가려져 멈춘 AI 시계 · 끝난 판)와 상대 차례는 전부 false 다.
     * [deadline] 은 마감 유무만 본다(1970 기준 초 — 값은 보지 않는다).
     */
    fun watchesMyClock(isFinished: Boolean, deadline: Double?, turn: ReversiColor?, myColor: ReversiColor): Boolean {
        if (isFinished || deadline == null || turn == null) return false
        return turn == myColor
    }
}
