import Foundation

// 오목 AI(렌주룰, 단일 난이도 — 항상 최선의 수). 설계: docs/plan/gomoku-ai.md §2.
//
// 공개 서명(`GomokuAISearchLimits` · `GomokuAI.bestMove`)은 대국·화면 갈래와의 계약이다 — 바꾸려면 설계 문서부터 고친다.
// 몸통은 GomokuAIEngine.swift 에 있다: 줄 모양 증분 평가 · 즉결 판단 · VCF · 상대 VCF 끊기 · 반복 심화 알파베타 · 렌주 금수.

/// 한 수를 고를 때의 한도.
package nonisolated struct GomokuAISearchLimits: Sendable {
    /// 생각 시간 상한. 반복 심화가 이 시간에 끊긴다.
    package var timeBudget: Duration
    /// 탐색 깊이 상한. 앱은 넉넉히 두고 시간이 먼저 끊게 한다 — 테스트는 이 값으로 결정적으로 돌린다.
    package var maxDepth: Int
    /// 점수가 완전히 같은 최선의 수끼리 고를 때 쓰는 씨앗. nil 이면 시스템 무작위(앱), 테스트는 고정한다.
    package var tieBreakSeed: UInt64?

    package init(timeBudget: Duration = .milliseconds(1500), maxDepth: Int = 64, tieBreakSeed: UInt64? = nil) {
        self.timeBudget = timeBudget
        self.maxDepth = maxDepth
        self.tieBreakSeed = tieBreakSeed
    }
}

package nonisolated enum GomokuAI {
    /// `toMove` 가 둘 최선의 수. 둘 곳이 없으면(흑의 빈칸이 전부 금수 · 판 가득) nil.
    /// `isCancelled` 가 true 가 되면 지금까지 찾은 최선(없으면 첫 합법 수)을 곧바로 돌려준다.
    package static func bestMove(
        board: GomokuBoard,
        toMove: GomokuColor,
        limits: GomokuAISearchLimits = .init(),
        isCancelled: @Sendable () -> Bool = { false }
    ) -> GomokuPoint? {
        // 빈 판: 천원(H8). 흑 첫 수 자리이고 백이어도 가장 좋은 자리다.
        guard board.stoneCount > 0 else { return GomokuPoint(x: GomokuBoard.size / 2, y: GomokuBoard.size / 2) }
        guard board.stoneCount < GomokuBoard.cellCount else { return nil }
        let side = toMove == .black ? 1 : 2
        let depth = max(1, limits.maxDepth)
        // 엔진은 이 호출 안에서만 산다 — 취소 문을 들고 있어도 호출 밖으로 새지 않는다(블록 안에서 해제된다).
        let move: Int? = withoutActuallyEscaping(isCancelled) { cancelled in
            let engine = GomokuAIEngine(board: board, budget: limits.timeBudget, isCancelled: cancelled)
            if let seed = limits.tieBreakSeed {
                var rng = GomokuAISplitMix64(seed: seed)
                return engine.chooseMove(side: side, maxDepth: depth, rng: &rng)
            }
            var rng = SystemRandomNumberGenerator()
            return engine.chooseMove(side: side, maxDepth: depth, rng: &rng)
        }
        guard let move else { return nil }
        let (x, y) = GomokuAIEngine.coordinates(move)
        return GomokuPoint(x: x, y: y)
    }
}
