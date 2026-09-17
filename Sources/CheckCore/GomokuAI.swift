import Foundation

// 오목 AI(렌주룰, 단일 난이도 — 항상 최선의 수). 설계: docs/plan/gomoku-ai.md §2.
//
// ── 계약 스텁 ──
// 이 파일은 병렬 작업의 **서명 계약**이다. 대국·화면 쪽은 아래 서명만 믿고 짜고, 엔진 쪽이 몸통을 갈아 끼운다.
// 서명(이름·인자·반환)을 바꾸면 두 갈래가 병합에서 어긋난다 — 바꾸려면 설계 문서부터 고친다.
// 지금 몸통은 임시다: 천원에서 가장 가까운 합법 수를 둔다(흑은 금수 제외).

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
        let center = GomokuBoard.size / 2
        var candidates: [GomokuPoint] = []
        for y in 0..<GomokuBoard.size {
            for x in 0..<GomokuBoard.size {
                if let point = GomokuPoint(x: x, y: y), board[point] == nil { candidates.append(point) }
            }
        }
        candidates.sort {
            let a = abs($0.x - center) + abs($0.y - center)
            let b = abs($1.x - center) + abs($1.y - center)
            return a != b ? a < b : ($0.y, $0.x) < ($1.y, $1.x)
        }
        for point in candidates {
            switch GomokuRules.judge(board: board, point: point, color: toMove) {
            case .legal, .win: return point
            default: continue
            }
        }
        return nil
    }
}
