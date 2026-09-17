import Foundation
import Testing
@testable import CheckCore

// v0.3.32 — 오목 AI 엔진(GomokuAI.bestMove) 계약. 설계: docs/plan/gomoku-ai.md §2.
//
// 사용자 결정: 단일 난이도 · **항상 최선의 수** · 공개 엔진(GPL) 없이 직접 작성. 그래서 이 시험은 "그럴듯한 수"가 아니라
// **놓치면 지는 수**를 본다 — 한 수 승 · 유일한 4 막기 · 열린 4 · 열린 3 막기 · VCF 승 · 상대 VCF 끊기 · 흑 금수로만 막히는 백 4.
//
// 결정성: 퍼즐·대국은 **깊이 제한 + 고정 씨앗**으로 돈다(시간은 넉넉히). 디버그 빌드가 느려도 결과가 같아야 한다.
// 시간 한도를 지키는지는 따로(중반 국면 5개, 디버그 기준 느슨한 상한) 본다.
//
// 퍼즐 픽스처 `Fixtures/gomoku-ai-puzzles.json`: expect(이 중 하나여야 한다) · reject(이건 안 된다) · winWithin(엔진 대 엔진으로
// 둘 쪽이 N수 안에 이긴다) · holdFor + loseAfter(엔진의 수 뒤엔 상대가 N수 안에 못 이기고, 엉뚱한 수 뒤엔 이긴다 — 위협이 진짜라는 대조군).

private struct AIPuzzle: Decodable {
    let id: String
    let note: String
    let black: [String]
    let white: [String]
    let toMove: String
    let expect: [String]?
    let reject: [String]?
    let winWithin: Int?
    let holdFor: Int?
    let loseAfter: String?
}

private struct AIMidgame: Decodable {
    let id: String
    let black: [String]
    let white: [String]
    let toMove: String
}

private struct AIFixture: Decodable {
    let puzzles: [AIPuzzle]
    let midgames: [AIMidgame]
}

private func loadAIFixture() throws -> AIFixture {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/gomoku-ai-puzzles.json")
    return try JSONDecoder().decode(AIFixture.self, from: Data(contentsOf: url))
}

private func aiBoard(black: [String], white: [String]) throws -> GomokuBoard {
    var board = GomokuBoard()
    for (list, color) in [(black, GomokuColor.black), (white, GomokuColor.white)] {
        for notation in list {
            let point = try #require(GomokuPoint(notation: notation), "좌표 \(notation)")
            #expect(board[point] == nil, "\(notation) 이 두 번 놓였다")
            board[point] = color
        }
    }
    return board
}

private func aiColor(_ raw: String) throws -> GomokuColor {
    try #require(GomokuColor(rawValue: raw))
}

/// 퍼즐·대국용 결정적 한도: 깊이 3, 시간은 사실상 무제한, 고정 씨앗.
private let aiPuzzleLimits = GomokuAISearchLimits(timeBudget: .seconds(600), maxDepth: 3, tieBreakSeed: 7)

private func isPlayable(_ judgement: GomokuJudgement) -> Bool {
    judgement == .legal || judgement == .win
}

/// 엔진 대 엔진으로 `plies` 수를 둔다. 모든 수가 합법인지 확인하고, 5목을 만든 색을 돌려준다(없으면 nil).
private func aiPlayOut(_ start: GomokuBoard, toMove: GomokuColor, plies: Int,
                       limits: GomokuAISearchLimits = aiPuzzleLimits) -> (winner: GomokuColor?, moves: [String]) {
    var board = start
    var color = toMove
    var moves: [String] = []
    for _ in 0..<plies {
        guard let move = GomokuAI.bestMove(board: board, toMove: color, limits: limits) else {
            moves.append("pass")
            color = color.opponent
            continue
        }
        let verdict = GomokuRules.judge(board: board, point: move, color: color)
        #expect(isPlayable(verdict), "\(color) 가 둘 수 없는 \(move.notation)(\(verdict))에 뒀다 — 수순 \(moves)")
        guard isPlayable(verdict) else { return (nil, moves) }
        board[move] = color
        moves.append(move.notation)
        if verdict == .win { return (color, moves) }
        color = color.opponent
    }
    return (nil, moves)
}

private func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}

/// 결정적 난수(SplitMix64) — 무작위 국면을 다시 만들 수 있어야 한다.
private struct AITestRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 돌 반경 2 안의 합법 빈칸(빈 판이면 H8) 중 무작위 하나. 없으면 nil.
/// 후보를 섞은 뒤 처음 만나는 합법 칸 — 합법 칸 중 균등하다. 후보는 놓인 돌 주변만 훑는다(디버그 빌드에서 판 전체×25칸을 돌지 않게).
private func randomLegalMove(_ board: GomokuBoard, _ color: GomokuColor, _ rng: inout AITestRandom) -> GomokuPoint? {
    var stones: [GomokuPoint] = []
    for index in 0..<GomokuBoard.cellCount {
        if let point = GomokuPoint(x: index % 15, y: index / 15), board[point] != nil { stones.append(point) }
    }
    guard !stones.isEmpty else { return GomokuPoint(x: 7, y: 7) }
    var near = Set<GomokuPoint>()
    for stone in stones {
        for dy in -2...2 {
            for dx in -2...2 {
                if let q = GomokuPoint(x: stone.x + dx, y: stone.y + dy), board[q] == nil { near.insert(q) }
            }
        }
    }
    var candidates = near.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    candidates.shuffle(using: &rng)
    return candidates.first { isPlayable(GomokuRules.judge(board: board, point: $0, color: color)) }
}

/// 벽시계 측정은 다른 작업(병렬 시험·시뮬레이터)에 밀리면 늘어난다. 한도 초과가 **진짜**면 세 번 모두 넘으므로, 가장 짧은 값을 본다.
private func shortestOfThree(_ body: () -> Void) -> Double {
    let clock = ContinuousClock()
    return (0..<3).map { _ in seconds(clock.measure(body)) }.min() ?? .infinity
}

// MARK: - 판정기 도우미

/// AI 가 흑 금수를 묻는 문(GomokuRenjuProbe)은 GomokuRules.judge 와 **같은 판정**이어야 한다 — 두 벌이면 AI 가 서버가 거절할 자리에 둔다.
@Test
func renjuProbeAgreesWithRulesOnRandomPositions() throws {
    var rng = AITestRandom(state: 0x0332_0001)
    var checked = 0
    var forbiddenSeen = 0
    let positions = 16
    for _ in 0..<positions {
        var board = GomokuBoard()
        var color = GomokuColor.black
        let stones = Int.random(in: 20...70, using: &rng)
        for _ in 0..<stones {
            guard let move = randomLegalMove(board, color, &rng) else { break }
            if GomokuRules.judge(board: board, point: move, color: color) == .win { break }
            board[move] = color
            color = color.opponent
        }
        var probe = GomokuRenjuProbe(board: board)
        for y in 0..<GomokuBoard.size {
            for x in 0..<GomokuBoard.size {
                let point = try #require(GomokuPoint(x: x, y: y))
                let expected = board[point] == nil ? GomokuRules.judge(board: board, point: point, color: .black) : .occupied
                let actual = probe.blackJudgement(x: x, y: y)
                #expect(actual == expected, "\(point.notation): 판정기 \(actual) ≠ 규칙 \(expected)")
                if case .forbidden = expected { forbiddenSeen += 1 }
                checked += 1
            }
        }
        // 제자리 고치기(setCell)도 복사본과 같은 판을 만든다.
        if let empty = (0..<GomokuBoard.cellCount).lazy.compactMap({ GomokuPoint(x: $0 % 15, y: $0 / 15) }).first(where: { board[$0] == nil }) {
            probe.setCell(x: empty.x, y: empty.y, to: .white)
            var copy = board
            copy[empty] = .white
            let fresh = GomokuRenjuProbe(board: copy)
            var fresh2 = fresh
            for y in 0..<GomokuBoard.size {
                for x in 0..<GomokuBoard.size {
                    #expect(probe.blackJudgement(x: x, y: y) == fresh2.blackJudgement(x: x, y: y))
                }
            }
        }
    }
    #expect(checked == positions * 225)
    #expect(forbiddenSeen > 0, "무작위 국면에 금수가 하나도 없었다 — 이 시험은 금수를 한 번도 대조하지 않았다")
}

// MARK: - 전술 퍼즐

@Test(arguments: try loadAIFixture().puzzles.map(\.id))
func aiPuzzle(_ id: String) throws {
    let puzzle = try #require(try loadAIFixture().puzzles.first { $0.id == id })
    let board = try aiBoard(black: puzzle.black, white: puzzle.white)
    let color = try aiColor(puzzle.toMove)
    let move = try #require(GomokuAI.bestMove(board: board, toMove: color, limits: aiPuzzleLimits), "\(id): 둘 수가 없다고 했다")
    #expect(isPlayable(GomokuRules.judge(board: board, point: move, color: color)), "\(id): 둘 수 없는 \(move.notation)")
    if let expect = puzzle.expect {
        #expect(expect.contains(move.notation), "\(id): \(move.notation) — 기대 \(expect). \(puzzle.note)")
    }
    if let reject = puzzle.reject {
        #expect(!reject.contains(move.notation), "\(id): 두면 안 되는 \(move.notation). \(puzzle.note)")
    }
    if let n = puzzle.winWithin {
        let result = aiPlayOut(board, toMove: color, plies: 2 * n - 1)
        #expect(result.winner == color, "\(id): \(n)수 안에 못 이겼다 — 수순 \(result.moves)")
    }
    if let n = puzzle.holdFor {
        var after = board
        after[move] = color
        let held = aiPlayOut(after, toMove: color.opponent, plies: 2 * n - 1)
        #expect(held.winner != color.opponent, "\(id): \(move.notation) 뒤 상대가 \(n)수 안에 이겼다 — 수순 \(held.moves)")
        if let bad = puzzle.loseAfter {
            // 대조군: 위협이 진짜인가. 엉뚱한 수 뒤에는 상대가 이겨야 한다(안 그러면 위 확인은 아무것도 증명하지 않는다).
            let badPoint = try #require(GomokuPoint(notation: bad))
            var wrong = board
            wrong[badPoint] = color
            let lost = aiPlayOut(wrong, toMove: color.opponent, plies: 2 * n - 1)
            #expect(lost.winner == color.opponent, "\(id): 대조군 \(bad) 뒤에도 상대가 못 이겼다 — 위협이 가짜다. 수순 \(lost.moves)")
        }
    }
}

/// 흑 금수로만 막히는 백 4 — 퍼즐의 전제(J10 뒤 H8 이 흑에게 3-3 금수)를 규칙으로 못 박는다. 전제가 틀리면 퍼즐이 다른 것을 잰다.
@Test
func forbiddenTrapPuzzlePremiseHolds() throws {
    let puzzle = try #require(try loadAIFixture().puzzles.first { $0.id == "white-exploits-forbidden-block" })
    var board = try aiBoard(black: puzzle.black, white: puzzle.white)
    board[try #require(GomokuPoint(notation: "J10"))] = .white
    let block = try #require(GomokuPoint(notation: "H8"))
    #expect(GomokuRules.judge(board: board, point: block, color: .black) == .forbidden(.doubleThree))
    #expect(GomokuRules.judge(board: board, point: block, color: .white) == .win)
}

// MARK: - 빈 판 · 둘 곳 없음 · 동점

@Test
func emptyBoardOpensAtTheCenter() {
    for seed: UInt64 in [1, 2, 3] {
        for color in GomokuColor.allCases {
            let move = GomokuAI.bestMove(board: GomokuBoard(), toMove: color,
                                         limits: GomokuAISearchLimits(timeBudget: .seconds(5), tieBreakSeed: seed))
            #expect(move?.notation == "H8")
        }
    }
}

@Test
func noMoveWhenTheBoardIsFullOrBlackHasOnlyForbiddenCells() throws {
    // 판 가득.
    var full = GomokuBoard()
    for index in 0..<GomokuBoard.cellCount {
        let point = try #require(GomokuPoint(x: index % 15, y: index / 15))
        full[point] = (index / 15 + index % 15) % 2 == 0 ? .black : .white
    }
    #expect(GomokuAI.bestMove(board: full, toMove: .black) == nil)
    #expect(GomokuAI.bestMove(board: full, toMove: .white) == nil)

    // 빈칸이 H8 하나, 흑에게는 장목(E8 F8 G8 _ I8 J8) → 둘 곳 없음. 백에게는 그 칸이 5목이다.
    var board = GomokuBoard()
    for index in 0..<GomokuBoard.cellCount {
        let point = try #require(GomokuPoint(x: index % 15, y: index / 15))
        board[point] = .white
    }
    for notation in ["E8", "F8", "G8", "I8", "J8"] { board[try #require(GomokuPoint(notation: notation))] = .black }
    let hole = try #require(GomokuPoint(notation: "H8"))
    board[hole] = nil
    #expect(GomokuRules.judge(board: board, point: hole, color: .black) == .forbidden(.overline))
    #expect(GomokuAI.bestMove(board: board, toMove: .black, limits: aiPuzzleLimits) == nil)
    #expect(GomokuAI.bestMove(board: board, toMove: .white, limits: aiPuzzleLimits) == hole)
}

/// 같은 씨앗이면 같은 수, 대칭이라 점수가 **정확히 같은** 수들 사이에서는 씨앗에 따라 갈린다(세기는 같고 기보는 되풀이되지 않는다).
@Test
func exactTiesAreBrokenBySeedAndOnlyAmongTies() throws {
    var board = GomokuBoard()
    board[try #require(GomokuPoint(notation: "H8"))] = .black
    let shallow = { (seed: UInt64) in GomokuAISearchLimits(timeBudget: .seconds(600), maxDepth: 1, tieBreakSeed: seed) }
    let first = GomokuAI.bestMove(board: board, toMove: .white, limits: shallow(11))
    #expect(first == GomokuAI.bestMove(board: board, toMove: .white, limits: shallow(11)), "같은 씨앗인데 수가 달랐다")
    var seen = Set<String>()
    for seed: UInt64 in 0..<24 {
        let move = try #require(GomokuAI.bestMove(board: board, toMove: .white, limits: shallow(seed)))
        #expect(abs(move.x - 7) <= 1 && abs(move.y - 7) <= 1, "흑 한 점 옆이 아닌 \(move.notation)")
        seen.insert(move.notation)
    }
    #expect(seen.count >= 2, "대칭 동점인데 씨앗 24개가 모두 같은 수(\(seen))를 골랐다")
}

// MARK: - 렌주: 흑 AI 는 금수에 두지 않는다

@Test
func blackAINeverPlaysAForbiddenPoint() throws {
    var rng = AITestRandom(state: 0x0332_0002)
    var positions = 0
    var attempts = 0
    while positions < 200, attempts < 2_000 {
        attempts += 1
        var board = GomokuBoard()
        var color = GomokuColor.black
        let stones = 2 * Int.random(in: 4...30, using: &rng)   // 흑 차례가 되게 짝수
        var ended = false
        for _ in 0..<stones {
            guard let move = randomLegalMove(board, color, &rng),
                  GomokuRules.judge(board: board, point: move, color: color) != .win else { ended = true; break }
            board[move] = color
            color = color.opponent
        }
        guard !ended, color == .black else { continue }
        positions += 1
        // 합법성은 탐색 깊이·시간과 무관한 성질이라 짧은 한도로 돈다(디버그 빌드 200국면).
        let limits = GomokuAISearchLimits(timeBudget: .milliseconds(60), maxDepth: 2, tieBreakSeed: UInt64(positions))
        guard let move = GomokuAI.bestMove(board: board, toMove: .black, limits: limits) else {
            Issue.record("흑이 둘 곳이 없다고 했다(돌 \(board.stoneCount)개)")
            continue
        }
        let verdict = GomokuRules.judge(board: board, point: move, color: .black)
        #expect(isPlayable(verdict), "흑 AI 가 \(move.notation) 에 뒀는데 \(verdict) — 판 \(board.serverString)")
    }
    #expect(positions == 200)
}

// MARK: - 대국

/// 무작위 상대에게 흑·백 각 10판 전승, 모든 수 합법.
@Test
func aiBeatsARandomOpponentWithBothColors() throws {
    var rng = AITestRandom(state: 0x0332_0003)
    var results: [String] = []
    for game in 0..<20 {
        let aiColor: GomokuColor = game % 2 == 0 ? .black : .white
        let limits = GomokuAISearchLimits(timeBudget: .seconds(600), maxDepth: 2, tieBreakSeed: UInt64(game))
        var board = GomokuBoard()
        var color = GomokuColor.black
        var winner: GomokuColor?
        for _ in 0..<GomokuBoard.cellCount {
            let move = color == aiColor
                ? GomokuAI.bestMove(board: board, toMove: color, limits: limits)
                : randomLegalMove(board, color, &rng)
            guard let move else { color = color.opponent; continue }
            let verdict = GomokuRules.judge(board: board, point: move, color: color)
            #expect(isPlayable(verdict), "게임 \(game): \(color) \(move.notation) \(verdict)")
            board[move] = color
            if verdict == .win { winner = color; break }
            color = color.opponent
        }
        results.append("\(aiColor)→\(winner.map { "\($0)" } ?? "무승부")")
        #expect(winner == aiColor, "게임 \(game): AI(\(aiColor))가 무작위 상대에게 이기지 못했다")
    }
    #expect(results.count == 20)
}

/// AI 대 AI 한 판이 합법적으로 끝난다(5목 또는 판 가득).
@Test
func aiVersusAIFinishesLegally() {
    let limits = GomokuAISearchLimits(timeBudget: .seconds(600), maxDepth: 2, tieBreakSeed: 5)
    var board = GomokuBoard()
    var color = GomokuColor.black
    var finished = false
    var passes = 0
    for _ in 0..<(GomokuBoard.cellCount + 4) {
        guard let move = GomokuAI.bestMove(board: board, toMove: color, limits: limits) else {
            passes += 1
            if board.stoneCount == GomokuBoard.cellCount || passes >= 2 { finished = true; break }
            color = color.opponent
            continue
        }
        passes = 0
        let verdict = GomokuRules.judge(board: board, point: move, color: color)
        #expect(isPlayable(verdict), "\(color) \(move.notation) \(verdict)")
        board[move] = color
        if verdict == .win || board.stoneCount == GomokuBoard.cellCount { finished = true; break }
        color = color.opponent
    }
    #expect(finished, "225수가 넘도록 끝나지 않았다")
}

// MARK: - 시간 · 취소

@Test
func cancellationReturnsALegalMoveAlmostImmediately() throws {
    let fixture = try loadAIFixture()
    #expect(fixture.midgames.count == 5)
    // 표(줄 모양 3^10)를 먼저 데운다 — 한 번만 만드는 비용을 취소 반응 시간에 섞지 않는다.
    _ = GomokuAI.bestMove(board: try aiBoard(black: ["H8"], white: []), toMove: .white,
                          limits: GomokuAISearchLimits(timeBudget: .milliseconds(50), maxDepth: 1, tieBreakSeed: 1))
    for game in fixture.midgames {
        let board = try aiBoard(black: game.black, white: game.white)
        let color = try aiColor(game.toMove)
        var move: GomokuPoint?
        let elapsed = shortestOfThree {
            move = GomokuAI.bestMove(board: board, toMove: color,
                                     limits: GomokuAISearchLimits(timeBudget: .seconds(30), tieBreakSeed: 1),
                                     isCancelled: { true })
        }
        let point = try #require(move, "\(game.id): 취소했더니 수가 없다")
        #expect(isPlayable(GomokuRules.judge(board: board, point: point, color: color)), "\(game.id): 취소 뒤 둘 수 없는 \(point.notation)")
        #expect(elapsed < 0.2, "\(game.id): 취소 뒤 \(elapsed)초")
    }
}

/// 기본 한도(1.5초)를 지킨다 — 디버그 빌드 기준 느슨한 상한(+0.5초).
@Test
func defaultTimeBudgetIsRespectedOnMidgamePositions() throws {
    let fixture = try loadAIFixture()
    _ = GomokuAI.bestMove(board: try aiBoard(black: ["H8"], white: []), toMove: .white,
                          limits: GomokuAISearchLimits(timeBudget: .milliseconds(50), maxDepth: 1, tieBreakSeed: 1))
    for game in fixture.midgames {
        let board = try aiBoard(black: game.black, white: game.white)
        let color = try aiColor(game.toMove)
        var move: GomokuPoint?
        let elapsed = shortestOfThree {
            move = GomokuAI.bestMove(board: board, toMove: color, limits: GomokuAISearchLimits(tieBreakSeed: 1))
        }
        let point = try #require(move, "\(game.id): 수가 없다")
        #expect(isPlayable(GomokuRules.judge(board: board, point: point, color: color)))
        #expect(elapsed <= 2.0, "\(game.id): \(elapsed)초 — 한도 1.5초 + 0.5초를 넘었다")
    }
}

/// 공개 서명은 대국·화면 갈래와의 계약이다(docs/plan/gomoku-ai.md §2) — 기본값까지 여기서 못 박는다.
@Test
func publicSignatureAndDefaultsStayPut() {
    let limits = GomokuAISearchLimits()
    #expect(limits.timeBudget == .milliseconds(1500))
    #expect(limits.maxDepth == 64)
    #expect(limits.tieBreakSeed == nil)
    let chooser: (GomokuBoard, GomokuColor, GomokuAISearchLimits, @Sendable () -> Bool) -> GomokuPoint? = GomokuAI.bestMove
    #expect(chooser(GomokuBoard(), .black, limits, { false })?.notation == "H8")
}
