import Foundation

// 오목 AI(렌주룰). 설계: docs/plan/gomoku-ai.md §2.
// 난이도(11-10 대표: "늘 최선의 수를 못두게 하는 방식이 아니라 몇수앞까지 계산할지에 제한") — 어느 단계든 **자기 수평선 안에서는
// 언제나 최선**을 둔다. 단계는 '몇 수 앞까지 보는가' 하나로 갈린다(알파베타 깊이 · 강제수 연장 · 4 로 몰기(VCF) 깊이 · 상대 몰기 끊기 깊이).
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

    /// 몇 수 앞까지 보는가(수 = 한 사람이 한 번 두는 것). nil 이면 끝없이(시간이 끊는다) — 알파베타의 강제수 연장도 이 수에서 멈춘다.
    package var lookahead: Int?
    /// 내가 4 로 몰아 이기는 수순(VCF)을 몇 번의 4 까지 찾는가. 한 번 = 내 4 + 상대 막기(두 수). 0 이면 찾지 않는다.
    package var vcfDepth: Int
    /// 상대의 4 몰이 수순을 몇 번의 4 까지 내다보고 끊는가. 0 이면 보지 않는다.
    package var defenseVcfDepth: Int
    /// 탐색 잎에서 두는 쪽의 4 몰이를 몇 번의 4 까지 확인하는가. 0 이면 확인하지 않는다.
    package var leafVcfDepth: Int

    package init(timeBudget: Duration = .milliseconds(1500), maxDepth: Int = 64, tieBreakSeed: UInt64? = nil,
                 lookahead: Int? = nil, vcfDepth: Int = 16, defenseVcfDepth: Int = 16, leafVcfDepth: Int = 8) {
        self.timeBudget = timeBudget
        self.maxDepth = maxDepth
        self.tieBreakSeed = tieBreakSeed
        self.lookahead = lookahead
        self.vcfDepth = vcfDepth
        self.defenseVcfDepth = defenseVcfDepth
        self.leafVcfDepth = leafVcfDepth
    }
}

/// AI 연습 난이도 — 몇 수 앞까지 계산하는가 하나로 나눈다(일부러 틀리게 두지 않는다).
package nonisolated enum GomokuAIDifficulty: String, CaseIterable, Codable, Sendable {
    case easy, normal, hard

    /// 몇 수 앞까지 보는가(화면 설명용). 어려움은 시간(1.5초)이 허락하는 데까지.
    package var lookahead: Int? {
        switch self {
        case .easy: return GomokuAIDifficultyTuning.easyLookahead
        case .normal: return GomokuAIDifficultyTuning.normalLookahead
        case .hard: return nil
        }
    }

    package var limits: GomokuAISearchLimits {
        guard let plies = lookahead else { return GomokuAISearchLimits() }
        return Self.limits(lookahead: plies)
    }

    /// 몇 수 앞(plies)에서 나오는 한도. 4 몰이 한 번 = 두 수라 수평선 안에 들어오는 만큼만 찾고, 잎 몰이 확인은 수평선 밖이라 끈다.
    package static func limits(lookahead plies: Int) -> GomokuAISearchLimits {
        let fours = max(1, plies / 2)
        return GomokuAISearchLimits(maxDepth: plies, lookahead: plies, vcfDepth: fours, defenseVcfDepth: fours, leafVcfDepth: 0)
    }
}

/// 단계별 수(자동 대국 승률로 정했다 — 시험 V03xxGomokuAIDifficultyTests 의 사다리, 최적화 빌드 11-10).
///   직접 대국 16판(색 번갈아): 2수 vs 6수 0:16 · 6수 vs 어려움 2:14. 4수는 2수에게 6:10 으로 져서 보통에서 뺐다.
///   한 수 시간(최적화): 2수 평균 0ms · 6수 평균 12ms(최대 0.13초) · 어려움 평균 0.5~0.7초(최대 1.5초 — 예전 그대로).
package nonisolated enum GomokuAIDifficultyTuning {
    package static let easyLookahead = 2
    package static let normalLookahead = 6
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
            let engine = GomokuAIEngine(board: board, budget: limits.timeBudget, isCancelled: cancelled, limits: limits)
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
