import Foundation

// 아잉 뒤집기 AI 탐색 엔진 본체. 공개 입구는 ReversiAI.swift 의 `ReversiAI.bestMove` 하나다(측정·시험용 `ReversiAI.decide` 는 모듈 안).
// 설계: flip/SPEC.md §4.2.
//
// 직접 작성, 외부 엔진 코드 없음 — GPL 엔진의 소스·평가표·정석 책을 보지도 베끼지도 않았다. 평가의 숫자는 이 파일이 정하고
// ReversiAIEngineTests 가 고정한다. 정석 책은 없다(v1).
//
// ── 규칙은 다시 적지 않는다 ──
// 합법 수·뒤집기는 규칙 코어의 비트보드(`ReversiBits.moves` · `ReversiBits.flips`)를 그대로 부른다. 두 벌을 두면 그 어긋남은
// 수 세기(perft)가 아니라 **대국 중 불법 수**로 드러난다. 판은 늘 "두는 쪽(own) · 상대(opp)" 두 비트로 들고 다닌다(negamax).
//
// ── 탐색 ──
// 반복 심화 negamax + 알파베타(fail-soft). 수 정렬은 **모서리 → 직전 최선(앞 깊이가 이 국면에서 고른 수) → 상대 이동성이
// 적은 순**이다(같은 이동성이면 칸 가중치가 높은 칸 먼저). 패스는 한 수(마디)로 다루되 깊이를 쓰지 않는다 — 패스는 연달아
// 두 번 올 수 없으므로(둘 다 못 두면 끝) 깊이를 안 써도 탐색이 끝난다.
//
// ── 종반 완전 탐색 ──
// 빈칸이 `endgameEmpties` 이하이고 깊이 상한이 빈칸 수 이상이면, 몸풀기 반복 심화(`endgameWarmupDepth` 까지) 뒤 판 끝까지
// 읽어 **최종 WOF 점수 차**(빈칸은 이긴 쪽에 — rules.md V-11)를 최대로 하는 수를 고른다. 예산 안에 못 끝나면 그 반복은 버리고
// 마친 반복 심화 결과를 쓴다. 문턱은 Release 실측으로 정했다(아래 상수 주석).
//
// ── 시간 ──
// 마감은 예산보다 조금 앞(틱 사이 간격 + 뿌리 마무리). 탐색 **안에서 256 노드마다** `ContinuousClock.now >= deadline ||
// isCancelled()` 를 본다 — 깊이 사이에서만 보면 종반 완전 탐색 한 번(= 한 반복)이 1.5초 상한을 넘기고 취소도 늦는다.
// 예산 절반을 넘겨 쓴 뒤에는 다음 깊이를 시작하지 않는다(시작만 하고 버리는 건 순손실). 끊긴 반복의 값은 버린다.
//
// ── 동점 ──
// 끝까지 마친 마지막 반복에서 **값이 최선과 똑같은 수끼리만** 고른다. 뿌리의 둘째 수부터는 창을 (최선−1, +∞) 로 연다 —
// 정수 점수라 최선 이상인 값은 창 안에서 정확하고, 최선 미만은 "최선보다 작다"는 경계만 나온다(동점 후보가 아니다).
// 좁은 창(최선, 최선+1)으로 보면 "최선과 같다"와 "최선보다 작다"가 갈리지 않아 더 나쁜 수가 동점으로 올라온다.
//
// 프라이버시·동시성: 판 숫자만 본다. 한 번의 호출 안에서만 살고 스레드를 넘나들지 않는다.

/// 한 번의 탐색 결과(측정·시험용). 앱은 `ReversiAI.bestMove` 로 수만 받는다.
nonisolated struct ReversiAIDecision: Sendable {
    /// 고른 칸(idx).
    let move: Int
    /// 두는 쪽 시점 값. `exact` 면 최종 WOF 점수 차(−64…64), 아니면 평가 단위(끝난 판은 ±`ReversiAIEngine.win` + 점수 차).
    let score: Int
    /// 판 끝까지 읽은 값인가(종반 완전 탐색을 끝까지 마쳤다).
    let exact: Bool
    /// 끝까지 마친 가장 깊은 반복(완전 탐색이면 빈칸 수, 중반 탐색이 모든 갈래에서 판 끝에 닿았으면 그 깊이).
    /// 수가 하나뿐이라 탐색하지 않았으면 0.
    let depth: Int
    /// 마지막으로 마친 반복에서 최선 값과 똑같은 수(오름차순). `move` 는 이 가운데 하나다.
    let tiedMoves: [Int]
    let nodes: Int
    let elapsed: Duration
    /// 마감·취소로 어떤 반복을 도중에 버렸는가.
    let aborted: Bool
}

extension ReversiAI {
    /// `bestMove` 와 같은 탐색이지만 값·깊이·동점 후보·노드·걸린 시간까지 낸다. 둘 곳이 없으면 nil.
    static func decide(
        board: ReversiBoard,
        toMove: ReversiColor,
        limits: ReversiAISearchLimits = .standard,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> ReversiAIDecision? {
        let (own, opp) = board.sides(toMove)
        guard ReversiBits.moves(own: own, opp: opp) != 0 else { return nil }
        // 엔진은 이 호출 안에서만 산다 — 취소 문을 들고 있어도 호출 밖으로 새지 않는다.
        return withoutActuallyEscaping(isCancelled) { cancelled in
            let engine = ReversiAIEngine(budget: limits.timeBudget, isCancelled: cancelled)
            let depth = max(1, limits.maxDepth)
            if let seed = limits.tieBreakSeed {
                var rng = GomokuAISplitMix64(seed: seed)
                return engine.decide(own: own, opp: opp, maxDepth: depth, rng: &rng)
            }
            var rng = SystemRandomNumberGenerator()
            return engine.decide(own: own, opp: opp, maxDepth: depth, rng: &rng)
        }
    }
}

// MARK: - 평가표

/// 평가의 숫자. 전부 이 파일이 정한 값이다(외부 평가표 없음). 표는 **보이는 대로**(1행이 위, a열이 왼쪽 — idx 순서) 적는다.
nonisolated enum ReversiAIEval {
    /// 칸 가중치. 판의 8대칭(가로·세로·대각 뒤집기)에 대해 대칭이어야 한다 — 대칭 국면의 동점이 동점으로 남는다(시험이 잰다).
    /// X(b2 등)·C(b1·a2 등) 칸은 여기서는 가볍게만 깎고, 모서리가 **비었을 때**의 큰 벌점은 `xPenalty`·`cPenalty` 가 따로 준다.
    static let squareWeights: [Int] = [
        100, -10,  20,   8,   8,  20, -10, 100,
        -10, -15,  -4,  -3,  -3,  -4, -15, -10,
         20,  -4,   6,   3,   3,   6,  -4,  20,
          8,  -3,   3,   0,   0,   3,  -3,   8,
          8,  -3,   3,   0,   0,   3,  -3,   8,
         20,  -4,   6,   3,   3,   6,  -4,  20,
        -10, -15,  -4,  -3,  -3,  -4, -15, -10,
        100, -10,  20,   8,   8,  20, -10, 100,
    ]
    /// 이동성(내 합법 수 − 상대 합법 수) 한 칸당.
    static let mobility = 10
    /// 모서리가 비었을 때 그 X 칸(대각 이웃)에 내 돌이 있으면 깎는 값(상대 돌이면 그만큼 더한다).
    static let xPenalty = 40
    /// 모서리가 비었을 때 그 C 칸(변 위 이웃 둘)에 내 돌이 있으면 깎는 값.
    static let cPenalty = 15
    /// 경계 돌(빈칸에 닿은 돌) 하나당 — 적을수록 좋다(상대의 둘 곳이 된다).
    static let frontier = 4
    /// 변 위 안정 돌(모서리에서 이어진 돌 · 꽉 찬 변의 돌) 하나당.
    static let stable = 12

    /// 모서리 a1·h1·a8·h8.
    static let corners: [Int] = [0, 7, 56, 63]
    /// 모서리마다 X 칸.
    static let xSquares: [Int] = [9, 14, 49, 54]
    /// 모서리마다 C 칸 둘.
    static let cSquares: [(Int, Int)] = [(1, 8), (6, 15), (48, 57), (55, 62)]
    static let cornerMask: UInt64 = (1 << 0) | (1 << 7) | (1 << 56) | (1 << 63)

    /// 네 변(모서리에서 모서리로 가는 순서). 안정 돌 셈에 쓴다.
    static let edges: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7],
        [56, 57, 58, 59, 60, 61, 62, 63],
        [0, 8, 16, 24, 32, 40, 48, 56],
        [7, 15, 23, 31, 39, 47, 55, 63],
    ]
    static let edgeMasks: [UInt64] = edges.map { $0.reduce(UInt64(0)) { $0 | (1 << UInt64($1)) } }

    /// 같은 가중치 칸끼리 묶은 가면(평가가 칸마다 돌지 않고 묶음마다 popcount 로 센다).
    static let weightClasses: [(mask: UInt64, weight: Int)] = {
        var masks: [Int: UInt64] = [:]
        for (idx, weight) in squareWeights.enumerated() where weight != 0 {
            masks[weight, default: 0] |= 1 << UInt64(idx)
        }
        return masks.keys.sorted().map { (masks[$0]!, $0) }
    }()
}

// MARK: - 엔진

nonisolated final class ReversiAIEngine {
    /// 탐색 경로 길이 상한(수 60 + 패스 — 패스는 연달아 오지 않으므로 120 을 넘지 않는다).
    static let maxPly = 128
    /// 한 국면의 수 목록 칸(실제 최대 합법 수는 이보다 훨씬 적다).
    static let slots = 64
    static let ttBits = 16
    static let infinity = 1 << 28
    /// 끝난 판 점수의 바탕. 평가가 닿지 못하는 크기라 "이긴 판"은 어떤 평가보다 높다.
    static let win = 1 << 20
    /// 종반 완전 탐색 문턱(빈칸 수). Release 실측(이 맥, 무작위 대국 국면, 초당 약 1,900만 노드): 빈칸 14 는 20개 모두
    /// 0.3초 안 · 16 은 20개 모두 1.13초 안(중앙 0.18초) · 18 은 중앙 4.3초라 1.5초 예산으로는 대부분 못 끝낸다. 못 끝나면
    /// 그 시간을 통째로 버리므로 16 으로 둔다. Debug(시험)는 초당 약 60만 노드로 30배쯤 느려 같은 문턱에서 자주 끊기는데,
    /// 그때는 마친 반복 심화 결과를 쓴다(시험이 그 길을 잰다).
    static let endgameEmpties = 16
    /// 완전 탐색 전에 마칠 반복 심화 깊이 — 완전 탐색이 끊겼을 때 쓸 수와 뿌리 정렬을 만든다.
    static let endgameWarmupDepth = 4
    /// 완전 탐색에서 빈칸이 이 수 이하면 정렬하지 않는다(정렬 비용이 줄인 마디보다 크다).
    static let solveSortEmpties = 7

    private let isCancelled: () -> Bool
    private let started: ContinuousClock.Instant
    private let deadline: ContinuousClock.Instant
    private let budget: Duration
    private(set) var nodes = 0
    private(set) var aborted = false
    /// 이번 반복에서 평가(깊이 끝)에 닿은 마디가 있었나. 없으면 그 반복은 모든 갈래가 판 끝까지 읽힌 것이다.
    private var horizonHit = false

    // 국면마다 수 목록(ply * slots 부터): 칸 · 정렬 열쇠 · 뒤집힐 돌 · 둔 뒤 상대의 합법 수.
    private let moveSquare: UnsafeMutablePointer<Int32>
    private let moveKey: UnsafeMutablePointer<Int32>
    private let moveFlips: UnsafeMutablePointer<UInt64>
    private let moveReply: UnsafeMutablePointer<UInt64>
    // 직전 최선 표(국면 → 그 국면에서 마지막으로 고른 수). 값이 아니라 **정렬에만** 쓴다 — 값 재사용이 없어 탐색 값이
    // 표 충돌·깊이 섞임에 흔들리지 않는다.
    private let ttOwn: UnsafeMutablePointer<UInt64>
    private let ttOpp: UnsafeMutablePointer<UInt64>
    private let ttMove: UnsafeMutablePointer<Int8>
    private let ttMask: UInt64

    init(budget: Duration, isCancelled: @escaping () -> Bool) {
        self.isCancelled = isCancelled
        self.budget = budget
        let capacity = Self.maxPly * Self.slots
        moveSquare = .allocate(capacity: capacity)
        moveKey = .allocate(capacity: capacity)
        moveFlips = .allocate(capacity: capacity)
        moveReply = .allocate(capacity: capacity)
        let tableSize = 1 << Self.ttBits
        ttOwn = .allocate(capacity: tableSize)
        ttOpp = .allocate(capacity: tableSize)
        ttMove = .allocate(capacity: tableSize)
        ttOwn.initialize(repeating: 0, count: tableSize)
        ttOpp.initialize(repeating: 0, count: tableSize)
        ttMove.initialize(repeating: -1, count: tableSize)
        ttMask = UInt64(tableSize - 1)
        started = ContinuousClock.now
        // 마감을 예산보다 조금 앞에: 틱은 256 노드마다라 그 사이 간격과 뿌리 마무리가 남는다. 예산에 딱 맞추면 재 보면 넘는다.
        let margin = min(budget / 50, .milliseconds(20))
        deadline = started.advanced(by: budget - margin)
    }

    deinit {
        moveSquare.deallocate()
        moveKey.deallocate()
        moveFlips.deallocate()
        moveReply.deallocate()
        ttOwn.deallocate()
        ttOpp.deallocate()
        ttMove.deallocate()
    }

    // MARK: 시간

    @inline(__always)
    private func tick() {
        nodes &+= 1
        if nodes & 255 == 0, !aborted {
            if ContinuousClock.now >= deadline || isCancelled() { aborted = true }
        }
    }

    private func checkAbortNow() -> Bool {
        if !aborted, ContinuousClock.now >= deadline || isCancelled() { aborted = true }
        return aborted
    }

    private var elapsed: Duration { ContinuousClock.now - started }

    // MARK: 뿌리

    func decide(own: UInt64, opp: UInt64, maxDepth: Int, rng: inout some RandomNumberGenerator) -> ReversiAIDecision? {
        let rootBits = ReversiBits.moves(own: own, opp: opp)
        guard rootBits != 0 else { return nil }
        let legal = ReversiBits.indices(rootBits)
        if legal.count == 1 {
            // 고를 여지가 없다 — 탐색하지 않는다.
            return ReversiAIDecision(move: legal[0], score: 0, exact: false, depth: 0, tiedMoves: legal,
                                     nodes: 0, elapsed: elapsed, aborted: false)
        }
        let empties = 64 - (own | opp).nonzeroBitCount
        // 뿌리 정렬: 안쪽 마디와 같은 열쇠로 시작하고, 반복마다 앞 반복의 값 순으로 다시 세운다(직전 최선이 맨 앞).
        let generated = generate(own: own, opp: opp, moves: rootBits, ply: 0)
        var order: [Int] = (0..<generated).map { Int(moveSquare[$0]) }

        var bestMoves: [Int] = []
        var bestScore = 0
        var completedDepth = 0
        var exact = false
        var abortedIteration = false
        let canSolve = empties <= Self.endgameEmpties && empties <= maxDepth
        var depth = 1
        while true {
            let solving = depth >= empties || (canSolve && depth > Self.endgameWarmupDepth)
            var iterationBest = -Self.infinity
            var iterationMoves: [Int] = []
            var scores = [Int](repeating: -Self.infinity, count: order.count)
            horizonHit = false
            for (index, square) in order.enumerated() {
                let placed: UInt64 = 1 << UInt64(square)
                let flipped = ReversiBits.flips(own: own, opp: opp, square: square)
                let newOwn = own | flipped | placed
                let newOpp = opp & ~flipped
                let reply = ReversiBits.moves(own: newOpp, opp: newOwn)
                // 첫 수는 전 창, 둘째부터는 (최선−1, +∞): 최선 이상이면 정확한 값, 미만이면 경계뿐(동점 후보 아님).
                let alpha = iterationMoves.isEmpty ? -Self.infinity : iterationBest - 1
                let value: Int
                if solving {
                    value = -solve(own: newOpp, opp: newOwn, moves: reply, alpha: -Self.infinity, beta: -alpha, ply: 1)
                } else {
                    value = -search(own: newOpp, opp: newOwn, moves: reply, depth: depth - 1,
                                    alpha: -Self.infinity, beta: -alpha, ply: 1)
                }
                if aborted { break }
                scores[index] = value
                if value > iterationBest {
                    iterationBest = value
                    iterationMoves = [square]
                } else if value == iterationBest {
                    iterationMoves.append(square)
                }
            }
            if aborted || iterationMoves.isEmpty {
                abortedIteration = true
                break
            }
            completedDepth = solving ? empties : depth
            bestScore = iterationBest
            bestMoves = iterationMoves
            exact = solving
            if solving { break }
            if !horizonHit {
                // 평가에 한 번도 닿지 않았다 = 모든 갈래가 판 끝까지 읽혔다(일찍 끝나는 판). 값은 끝난 판 점수뿐이므로
                // ±win 을 걷어 최종 점수 차로 바꾼다(단조 변환이라 동점 집합은 그대로다). 더 깊이 볼 것이 없다.
                exact = true
                bestScore = bestScore > 0 ? bestScore - Self.win : (bestScore < 0 ? bestScore + Self.win : 0)
                break
            }
            // 다음 깊이는 직전 최선부터(값이 같으면 앞 순서 유지 — 정렬이 결정적이어야 씨앗 시험이 결정적이다).
            let ranked = order.indices.sorted { scores[$0] > scores[$1] || (scores[$0] == scores[$1] && $0 < $1) }
            order = ranked.map { order[$0] }
            if depth >= maxDepth { break }
            if checkAbortNow() {
                abortedIteration = true
                break
            }
            if elapsed > budget / 2 { break }
            depth += 1
        }

        if bestMoves.isEmpty {
            // 한 반복도 못 마쳤다(곧바로 취소) — 계약대로 첫 합법 수.
            return ReversiAIDecision(move: legal[0], score: 0, exact: false, depth: 0, tiedMoves: [legal[0]],
                                     nodes: nodes, elapsed: elapsed, aborted: true)
        }
        let tied = bestMoves.sorted()
        let chosen = tied.randomElement(using: &rng) ?? tied[0]
        return ReversiAIDecision(move: chosen, score: bestScore, exact: exact, depth: completedDepth, tiedMoves: tied,
                                 nodes: nodes, elapsed: elapsed, aborted: abortedIteration)
    }

    // MARK: 중반 탐색

    /// negamax 알파베타(fail-soft). `moves` = 두는 쪽(own)의 합법 수(부르는 쪽이 이미 셌다).
    private func search(own: UInt64, opp: UInt64, moves: UInt64, depth: Int, alpha: Int, beta: Int, ply: Int) -> Int {
        tick()
        if aborted { return 0 }
        if moves == 0 {
            let replies = ReversiBits.moves(own: opp, opp: own)
            if replies == 0 { return Self.terminal(own: own, opp: opp) }
            // 패스 — 한 마디지만 깊이는 쓰지 않는다.
            return -search(own: opp, opp: own, moves: replies, depth: depth, alpha: -beta, beta: -alpha, ply: ply + 1)
        }
        if depth <= 0 {
            horizonHit = true
            return evaluate(own: own, opp: opp, moves: moves)
        }
        let count = generate(own: own, opp: opp, moves: moves, ply: ply)
        let base = ply * Self.slots
        var best = -Self.infinity
        var bestSquare = -1
        var floor = alpha
        for offset in 0..<count {
            let slot = base + offset
            let square = Int(moveSquare[slot])
            let flipped = moveFlips[slot]
            let newOwn = own | flipped | (1 << UInt64(square))
            let newOpp = opp & ~flipped
            let value = -search(own: newOpp, opp: newOwn, moves: moveReply[slot], depth: depth - 1,
                                alpha: -beta, beta: -floor, ply: ply + 1)
            if aborted { return 0 }
            if value > best {
                best = value
                bestSquare = square
                if value > floor {
                    floor = value
                    if floor >= beta { break }
                }
            }
        }
        remember(own: own, opp: opp, square: bestSquare)
        return best
    }

    // MARK: 종반 완전 탐색

    /// 판 끝까지 읽은 최종 WOF 점수 차(두는 쪽 시점). fail-soft 알파베타.
    private func solve(own: UInt64, opp: UInt64, moves: UInt64, alpha: Int, beta: Int, ply: Int) -> Int {
        tick()
        if aborted { return 0 }
        if moves == 0 {
            let replies = ReversiBits.moves(own: opp, opp: own)
            if replies == 0 { return Self.finalDiff(own: own, opp: opp) }
            return -solve(own: opp, opp: own, moves: replies, alpha: -beta, beta: -alpha, ply: ply + 1)
        }
        let empties = 64 - (own | opp).nonzeroBitCount
        if empties == 1 {
            // 마지막 빈칸에 둔다 — 판이 가득 차 끝난다.
            let square = moves.trailingZeroBitCount
            let flipped = ReversiBits.flips(own: own, opp: opp, square: square)
            return Self.finalDiff(own: own | flipped | (1 << UInt64(square)), opp: opp & ~flipped)
        }
        var best = -Self.infinity
        var floor = alpha
        if empties > Self.solveSortEmpties {
            let count = generate(own: own, opp: opp, moves: moves, ply: ply)
            let base = ply * Self.slots
            var bestSquare = -1
            for offset in 0..<count {
                let slot = base + offset
                let square = Int(moveSquare[slot])
                let flipped = moveFlips[slot]
                let value = -solve(own: opp & ~flipped, opp: own | flipped | (1 << UInt64(square)), moves: moveReply[slot],
                                   alpha: -beta, beta: -floor, ply: ply + 1)
                if aborted { return 0 }
                if value > best {
                    best = value
                    bestSquare = square
                    if value > floor {
                        floor = value
                        if floor >= beta { break }
                    }
                }
            }
            remember(own: own, opp: opp, square: bestSquare)
            return best
        }
        var rest = moves
        while rest != 0 {
            let square = rest.trailingZeroBitCount
            rest &= rest - 1
            let flipped = ReversiBits.flips(own: own, opp: opp, square: square)
            let newOwn = own | flipped | (1 << UInt64(square))
            let newOpp = opp & ~flipped
            let value = -solve(own: newOpp, opp: newOwn, moves: ReversiBits.moves(own: newOpp, opp: newOwn),
                               alpha: -beta, beta: -floor, ply: ply + 1)
            if aborted { return 0 }
            if value > best {
                best = value
                if value > floor {
                    floor = value
                    if floor >= beta { break }
                }
            }
        }
        return best
    }

    // MARK: 수 정렬

    /// `ply` 칸에 수 목록을 정렬해 채우고 개수를 낸다. 열쇠가 작을수록 먼저:
    /// 모서리(상대 이동성) → 직전 최선 → 그 밖(상대 이동성 × 256 − 칸 가중치).
    private func generate(own: UInt64, opp: UInt64, moves: UInt64, ply: Int) -> Int {
        let base = ply * Self.slots
        let hint = recalled(own: own, opp: opp)
        var count = 0
        var rest = moves
        while rest != 0 {
            let square = rest.trailingZeroBitCount
            rest &= rest - 1
            let placed: UInt64 = 1 << UInt64(square)
            let flipped = ReversiBits.flips(own: own, opp: opp, square: square)
            let newOwn = own | flipped | placed
            let newOpp = opp & ~flipped
            let reply = ReversiBits.moves(own: newOpp, opp: newOwn)
            let mobility = reply.nonzeroBitCount
            let key: Int
            if placed & ReversiAIEval.cornerMask != 0 {
                key = mobility
            } else if square == hint {
                key = 1_000
            } else {
                key = 2_000 + mobility * 256 - ReversiAIEval.squareWeights[square]
            }
            // 넣으면서 정렬(삽입 정렬 — 목록이 짧다). 같은 열쇠는 들어온 순서(idx 오름차순)를 지킨다.
            var position = base + count
            while position > base, Int(moveKey[position - 1]) > key {
                moveSquare[position] = moveSquare[position - 1]
                moveKey[position] = moveKey[position - 1]
                moveFlips[position] = moveFlips[position - 1]
                moveReply[position] = moveReply[position - 1]
                position -= 1
            }
            moveSquare[position] = Int32(square)
            moveKey[position] = Int32(key)
            moveFlips[position] = flipped
            moveReply[position] = reply
            count += 1
        }
        return count
    }

    @inline(__always)
    private func slotIndex(own: UInt64, opp: UInt64) -> Int {
        var hash = (own &* 0x9E37_79B9_7F4A_7C15) ^ (opp &* 0xC2B2_AE3D_27D4_EB4F)
        hash ^= hash >> 31
        return Int(truncatingIfNeeded: hash & ttMask)
    }

    private func remember(own: UInt64, opp: UInt64, square: Int) {
        guard square >= 0 else { return }
        let slot = slotIndex(own: own, opp: opp)
        ttOwn[slot] = own
        ttOpp[slot] = opp
        ttMove[slot] = Int8(square)
    }

    private func recalled(own: UInt64, opp: UInt64) -> Int {
        let slot = slotIndex(own: own, opp: opp)
        guard ttOwn[slot] == own, ttOpp[slot] == opp else { return -1 }
        return Int(ttMove[slot])
    }

    // MARK: 점수

    /// 끝난 판의 최종 WOF 점수 차(두는 쪽 − 상대, 빈칸은 이긴 쪽에 — rules.md V-11). 같으면 0(32:32).
    static func finalDiff(own: UInt64, opp: UInt64) -> Int {
        let mine = own.nonzeroBitCount
        let theirs = opp.nonzeroBitCount
        let empty = 64 - mine - theirs
        if mine > theirs { return mine - theirs + empty }
        if mine < theirs { return mine - theirs - empty }
        return 0
    }

    /// 중반 탐색에서 만난 끝난 판: 이기면 `win` + 점수 차, 지면 −`win` + 점수 차, 비기면 0.
    static func terminal(own: UInt64, opp: UInt64) -> Int {
        let diff = finalDiff(own: own, opp: opp)
        if diff > 0 { return win + diff }
        if diff < 0 { return -win + diff }
        return 0
    }

    /// 중반 평가(두는 쪽 시점): 칸 가중치 + 이동성 + 모서리 빈 X·C 벌점 + 경계 + 변 안정 돌. 모서리 가치는 칸 가중치(100)에 있다.
    func evaluate(own: UInt64, opp: UInt64, moves: UInt64) -> Int {
        Self.evaluate(own: own, opp: opp, moves: moves)
    }

    static func evaluate(own: UInt64, opp: UInt64, moves: UInt64) -> Int {
        let replies = ReversiBits.moves(own: opp, opp: own)
        var score = 0
        for entry in ReversiAIEval.weightClasses {
            score += entry.weight * ((own & entry.mask).nonzeroBitCount - (opp & entry.mask).nonzeroBitCount)
        }
        score += ReversiAIEval.mobility * (moves.nonzeroBitCount - replies.nonzeroBitCount)
        let occupied = own | opp
        for corner in 0..<4 {
            guard occupied & (1 << UInt64(ReversiAIEval.corners[corner])) == 0 else { continue }
            let x: UInt64 = 1 << UInt64(ReversiAIEval.xSquares[corner])
            if own & x != 0 { score -= ReversiAIEval.xPenalty }
            if opp & x != 0 { score += ReversiAIEval.xPenalty }
            let (c1, c2) = ReversiAIEval.cSquares[corner]
            let cs: UInt64 = (1 << UInt64(c1)) | (1 << UInt64(c2))
            score -= ReversiAIEval.cPenalty * ((own & cs).nonzeroBitCount - (opp & cs).nonzeroBitCount)
        }
        let empty = ~occupied
        var touching: UInt64 = 0
        for direction in 0..<8 { touching |= ReversiBits.shift(empty, direction) }
        score += ReversiAIEval.frontier * ((opp & touching).nonzeroBitCount - (own & touching).nonzeroBitCount)
        score += ReversiAIEval.stable * (stableEdgeDiscs(own: own, opp: opp) - stableEdgeDiscs(own: opp, opp: own))
        return score
    }

    /// 변 위에서 다시 뒤집힐 수 없는 내 돌 수. 변의 돌은 **변 방향으로만** 끼일 수 있다(다른 방향은 한쪽이 판 밖) — 그래서
    /// ① 꽉 찬 변의 돌 ② 모서리에서 끊김 없이 이어진 내 돌은 끝까지 내 돌이다.
    static func stableEdgeDiscs(own: UInt64, opp: UInt64) -> Int {
        let occupied = own | opp
        var stable: UInt64 = 0
        for edge in 0..<4 {
            let mask = ReversiAIEval.edgeMasks[edge]
            if occupied & mask == mask {
                stable |= own & mask
                continue
            }
            let line = ReversiAIEval.edges[edge]
            var forward = 0
            while forward < 8, own & (1 << UInt64(line[forward])) != 0 {
                stable |= 1 << UInt64(line[forward])
                forward += 1
            }
            var backward = 7
            while backward >= 0, own & (1 << UInt64(line[backward])) != 0 {
                stable |= 1 << UInt64(line[backward])
                backward -= 1
            }
        }
        return stable.nonzeroBitCount
    }
}
