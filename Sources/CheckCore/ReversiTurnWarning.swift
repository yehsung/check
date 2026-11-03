import Foundation

// 아잉 뒤집기 **내 차례 마지막 3초** 판 테두리 경고 — 판정 짝. 계약은 설계서 FLIP/SPEC.md §4.5.
//
// 숫자 함수(`isActive(remaining:)` · `intensity(remaining:)`)와 그림(`drawEdgeGlow(into:side:intensity:)`)은 오목
// `GomokuTurnWarning` 을 **그대로 부른다** — 문턱·세기·그림이 게임마다 갈리면 한쪽만 고쳐진다. 타입에 묶인
// `watchesMyClock` 짝만 리버시 판 값으로 새로 둔다.

/// 내 차례 마지막 몇 초의 판 테두리 경고 — 리버시 판 짝. 시계를 읽지 않는다(남은 초는 부르는 잎 뷰가 넘긴다).
package nonisolated enum ReversiTurnWarning {
    /// 이 판에서 경고가 **설 수 있는가** — 끝나지 않았고, 내 차례이고, 마감이 돈다.
    /// 마감이 nil 인 경우(AI 차례 · 창이 가려져 멈춘 AI 시계 · 끝난 판)와 상대 차례는 전부 false 다.
    /// 잎 뷰는 이 값으로 TimelineView 를 멈추고, **본문에서 한 번 더** 본다 — 멈춘 TimelineView 는 마지막 그림을 들고 있다.
    package static func watchesMyClock(_ match: ReversiMatchState?) -> Bool {
        guard let match, !match.isFinished, match.deadline != nil, let turn = match.turn else { return false }
        return turn == match.myColor
    }
}
