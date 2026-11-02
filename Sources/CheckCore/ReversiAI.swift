import Foundation

// 아잉 뒤집기 AI(단일 난이도 — 일부러 틀리는 수 없음). 설계: flip/SPEC.md §4.2.
// 직접 작성, 외부 엔진 코드 없음(GPL 엔진의 소스·평가표·정석 책을 보지도 베끼지도 않는다).
//
// 공개 서명(`ReversiAISearchLimits` · `ReversiAI.bestMove`)은 스토어·화면 갈래와의 계약이다 — 바꾸려면 SPEC 부터 고친다.
// 오목 `GomokuAI` · 체스 `ChessAI` 와 같은 꼴: 시간 예산 · 깊이 상한 · 동점 씨앗 · 취소 문.

/// 한 수를 고를 때의 한도.
package nonisolated struct ReversiAISearchLimits: Sendable {
    /// 생각 시간 상한(사용자 결정 1.5초). 반복 심화가 이 시간에 끊긴다.
    package var timeBudget: Duration
    /// 탐색 깊이 상한. 앱은 넉넉히 두고 시간이 먼저 끊게 한다 — 테스트는 이 값으로 결정적으로 돌린다.
    package var maxDepth: Int
    /// 점수가 완전히 같은 최선의 수끼리 고를 때 쓰는 씨앗. nil 이면 시스템 무작위(앱), 테스트는 고정한다.
    package var tieBreakSeed: UInt64?

    package init(timeBudget: Duration = .milliseconds(1500), maxDepth: Int = 60, tieBreakSeed: UInt64? = nil) {
        self.timeBudget = timeBudget
        self.maxDepth = maxDepth
        self.tieBreakSeed = tieBreakSeed
    }

    /// 앱 기본값(1.5초 · 깊이 60 · 시스템 무작위).
    package static let standard = ReversiAISearchLimits()
}

package nonisolated enum ReversiAI {
    /// `toMove` 가 둘 최선의 수(idx). 둘 곳이 없을 때만 nil.
    /// `isCancelled` 가 true 가 되면 지금까지 찾은 최선(없으면 첫 합법 수)을 곧바로 돌려준다.
    package static func bestMove(
        board: ReversiBoard,
        toMove: ReversiColor,
        limits: ReversiAISearchLimits = .standard,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> Int? {
        // R2 가 엔진으로 바꾼다 — 지금은 계약 표면만 세운 임시 몸통(합법 수 가운데 idx 가 가장 작은 것).
        ReversiRules.legalMoves(board, color: toMove).first
    }
}
