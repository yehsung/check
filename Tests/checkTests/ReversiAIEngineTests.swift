import Foundation
import Testing
@testable import CheckCore

// 아잉 뒤집기 AI 엔진 — **고르는 수**와 **돌아오는 시간**을 못 박는다(flip/SPEC.md §4.2 · §6.3 R 줄).
//
// "엔진이 수를 돌려준다"는 아무것도 재지 않는다(첫 합법 수만 내는 임시 몸통도 통과한다). 여기서 재는 건
// "이 국면의 최선 값은 **이 값**이고 · 최선과 똑같은 수는 **이 집합**이며 · **이 시간** 안에 돌아온다"다.
//
// ── 기준선은 AI 코드를 타지 않는다 ──
// 종반 정답은 `bruteValues`(아래)가 `ReversiRules` 공개 함수만으로 판 끝까지 전부 읽어 낸다. 고정 국면 여덟은 그 값을
// 파일에 글자로도 박았다 — 파이썬 참조 구현(research/reference.py)으로 따로 전수 탐색해 같은 값을 얻었다(Swift 규칙과
// 함께 틀리는 길을 막는다). 엔진의 값·동점 집합이 이 정답과 **글자 그대로** 같아야 한다.
//
// ── 한도는 시간이 아니라 깊이로 ──
// 값을 재는 시험은 `maxDepth` 로 끊고 시간 예산은 넉넉히 둔다(기계가 느린 날 결과가 바뀌지 않게). 시간 자체를 재는
// 시험(마감 · 취소 · 1.5초 상한)만 시간으로 돈다.
//
// ── 느린 것은 환경변수 뒤에 ──
// 1.5초 상한 실측 · 무작위 상대 200판 · 탐욕 상대 200판 · 빈칸 9~10 전수 대조 스무 국면 · 고정 국면 값 재확인은
// `REVERSI_AI_SLOW=1` 에서만 돈다.
// 시험은 Debug 빌드로 돈다(Release 보다 수십 배 느리다) — 그래서 승률 시험의 엔진은 깊이 상한으로 묶었고, 실측 숫자는
// 갈래 보고(flip/reports/R2.md)에 적었다.

private func reversiAISlowEnabled() -> Bool {
    ProcessInfo.processInfo.environment["REVERSI_AI_SLOW"] == "1"
}

/// 고정 종반 국면 — 두는 쪽 · 판 · 수마다 판 끝까지 읽은 최종 WOF 점수 차(두는 쪽 시점, 빈칸은 이긴 쪽에).
/// 값은 Swift 전수 탐색(이 파일 `bruteValues`)과 파이썬 참조 구현 전수 탐색이 둘 다 낸 것이다.
/// 고른 기준: 최선 동점이 둘 이상이거나(동점 무작위가 그 안에서만 도는가) 최선이 하나뿐이고(늘 그 수인가),
/// **최선보다 딱 2 낮은 수**가 있다(좁은 창·느슨한 동점 판정이 그 수를 동점으로 올리면 바로 갈린다).
struct ReversiAIEndgameFixture: Sendable, CustomStringConvertible {
    let label: String
    let color: ReversiColor
    let board: String
    let values: [Int: Int]

    var description: String { label }
    var best: Int { values.values.max() ?? Int.min }
    var bestMoves: [Int] { values.filter { $0.value == best }.map(\.key).sorted() }
}

let reversiAIEndgameFixtures: [ReversiAIEndgameFixture] = [
    .init(label: "흑 빈칸8 동점 둘", color: .black,
          board: "wwwwwbw.wbbbbb..wbbbwb.bwbwwwwwwwwwwwbwbwwwwww.b.wwbwwbb..wwwwwb",
          values: [7: -6, 48: -8, 56: -8, 57: -6]),
    .init(label: "흑 빈칸8 동점 둘(진 판)", color: .black,
          board: "..bwwwwbbbbbwwwwbbbwwwwwbbbbwwbbbwbbbbbbbwwwwwbbbwww..wbww..w..w",
          values: [52: -28, 53: -26, 58: -20, 59: -26, 61: -22, 62: -20]),
    .init(label: "흑 빈칸8 동점 둘(이긴 판)", color: .black,
          board: "wwwwwww...wwwwwwwwwbwww..wwwwww.wwwwwbwbwwwwwbwbbbbbb.wwwwwwwww.",
          values: [7: 8, 9: 0, 23: 8, 24: 16, 31: 12, 53: 14, 63: 16]),
    .init(label: "흑 빈칸10 동점 둘", color: .black,
          board: "wwb.bwwwwwbwbwwwwwbwbbwbwwbwbbb.wbbwbb..bbb.wb..bbwbbw..bbbwwww.",
          values: [31: -6, 43: -6, 54: -22, 63: -8]),
    .init(label: "흑 빈칸10 동점 셋", color: .black,
          board: "b.b.wwbbbb..wwbbb.wwwwbbbwwwwbwbbwwbww.wbww.bbw.bwwbbb.ww.bwwwww",
          values: [3: 8, 10: -2, 11: 0, 17: 6, 38: 8, 43: 8, 47: 6]),
    .init(label: "백 빈칸9 동점 넷", color: .white,
          board: "wwb.bwwwwwbwbbwwwwbwbbbbwwbwbbbbwbbwbb..bbb.wb..bbwbbw..bbbwwww.",
          values: [3: 6, 38: 6, 39: 6, 43: 6, 46: 4, 54: 4]),
    .init(label: "백 빈칸9 하나뿐(+8, 다음 +6)", color: .white,
          board: "wwwwwbw.wbbbbb..wbbbwb.bwbwwbbb.wwwwwbbbwwwwwb.b.wwbbwbb..wwwwwb",
          values: [14: 8, 22: -12, 31: 6, 46: 4]),
    .init(label: "백 빈칸9 하나뿐(+16, 다음 +14 둘)", color: .white,
          board: "...w..bwbw.wbbbwwwwbbbw.wwbwbwbbwwwbwbwww.bwbbwwwwwwbww.wwwwwwww",
          values: [0: 14, 4: 8, 5: 4, 10: 2, 23: 16, 41: 14]),
]

/// 마감·취소 시험 국면(빈칸 14, 흑 차례). 무작위 대국에서 뽑은 30국면 가운데 완전 탐색이 가장 무거운 자리다
/// (Release 0.27초 · 556만 노드 — Debug 는 그 몇 십 배). 깊이 사이에서만 마감을 보는 엔진은 여기서 한 반복이 끝날 때까지 못 돌아온다.
let reversiAIHeavyBoard = "wb..w..bbbbwwwww..wbbbb..wbbbbb.wbwwbbbbb.wbbwb..wbbbbbb.b.wbwww"

@Suite("아잉 뒤집기 AI 엔진 — 합법 수 · 둘 곳 없음 · 최선 동점 · 종반 전수 대조 · 마감 · 평가 고정")
struct ReversiAIEngineTests {
    // MARK: 도우미

    static func board(_ text: String) throws -> ReversiBoard {
        try #require(ReversiBoard(string: text), "판 문자열을 못 읽었다: \(text)")
    }

    /// 깊이로 못 박은 한도. 시간은 넉넉히 둬서 **깊이가 먼저** 끊는다.
    static func limits(depth: Int, seed: UInt64 = 0x5EED, budget: Duration = .seconds(120)) -> ReversiAISearchLimits {
        ReversiAISearchLimits(timeBudget: budget, maxDepth: depth, tieBreakSeed: seed)
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// 시작 판에서 씨앗 무작위 대국으로 빈칸 `empties` 국면을 만든다. 그 자리의 두는 쪽이 둘 곳이 없거나 판이 먼저 끝나면 nil.
    static func randomPosition(empties: Int, seed: UInt64) -> (board: ReversiBoard, color: ReversiColor)? {
        var rng = GomokuAISplitMix64(seed: seed)
        var board = ReversiBoard.start
        var turn: ReversiColor = .black
        while board.counts.empty > empties {
            let moves = ReversiRules.legalMoves(board, color: turn)
            guard !moves.isEmpty else { return nil }   // play 의 next 가 패스를 접어 주므로 여기 오면 끝난 판이다
            let idx = moves[Int(rng.next() % UInt64(moves.count))]
            guard case .success(let outcome) = ReversiRules.play(board, color: turn, idx: idx),
                  let next = outcome.next else { return nil }
            board = outcome.board
            turn = next
        }
        guard ReversiRules.hasLegalMove(board, color: turn) else { return nil }
        return (board, turn)
    }

    /// 끝난 판의 WOF 점수 차(`color` 시점).
    static func scoreDiff(_ score: ReversiScore, _ color: ReversiColor) -> Int {
        color == .black ? score.black - score.white : score.white - score.black
    }

    /// 전수 탐색 — `ReversiRules` 공개 함수만 쓴다(엔진 코드를 한 줄도 부르지 않는다). 두는 쪽 시점 최종 WOF 점수 차.
    static func bruteValue(_ board: ReversiBoard, _ color: ReversiColor) -> Int {
        let moves = ReversiRules.legalMoves(board, color: color)
        if moves.isEmpty {
            guard ReversiRules.hasLegalMove(board, color: color.opponent) else {
                return scoreDiff(ReversiRules.score(board)!, color)
            }
            return -bruteValue(board, color.opponent)
        }
        return moves.map { bruteChild(board, color, $0) }.max()!
    }

    static func bruteChild(_ board: ReversiBoard, _ color: ReversiColor, _ idx: Int) -> Int {
        guard case .success(let outcome) = ReversiRules.play(board, color: color, idx: idx) else { return Int.min }
        if outcome.isOver { return scoreDiff(outcome.score!, color) }
        if outcome.next == color { return bruteValue(outcome.board, color) }   // 상대 자동 패스 — 내가 또 둔다
        return -bruteValue(outcome.board, color.opponent)
    }

    /// 뿌리의 수마다 전수 탐색 값.
    static func bruteValues(_ board: ReversiBoard, _ color: ReversiColor) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: ReversiRules.legalMoves(board, color: color).map { ($0, bruteChild(board, color, $0)) })
    }

    /// 판의 8대칭(가로·세로 뒤집기 · 전치)으로 칸을 옮긴다. `kind` 0…7.
    static func transform(_ idx: Int, _ kind: Int) -> Int {
        var row = idx / 8
        var col = idx % 8
        if kind & 1 != 0 { col = 7 - col }
        if kind & 2 != 0 { row = 7 - row }
        if kind & 4 != 0 { swap(&row, &col) }
        return row * 8 + col
    }

    static func transform(bits: UInt64, _ kind: Int) -> UInt64 {
        var result: UInt64 = 0
        for idx in ReversiBits.indices(bits) { result |= 1 << UInt64(transform(idx, kind)) }
        return result
    }

    /// 대국 한 판. 엔진의 수는 매번 규칙의 합법 수 안인지 본다. 결과(흑 기준)와 엔진 시점 최종 점수 차를 낸다.
    static func playGame(engine: ReversiColor, limits: ReversiAISearchLimits,
                         opponent: (ReversiBoard, ReversiColor) -> Int) throws -> (result: ReversiResult, diff: Int) {
        var board = ReversiBoard.start
        var turn: ReversiColor? = .black
        var plies = 0
        while let color = turn {
            let legal = ReversiRules.legalMoves(board, color: color)
            let idx: Int
            if color == engine {
                idx = try #require(ReversiAI.bestMove(board: board, toMove: color, limits: limits))
                try #require(legal.contains(idx), "\(plies)수: 엔진이 불법 수 \(idx) / \(board.string)")
            } else {
                idx = opponent(board, color)
            }
            guard case .success(let outcome) = ReversiRules.play(board, color: color, idx: idx) else {
                throw ReversiFixtureError("\(plies)수: 둘 수 없는 칸 \(idx)")
            }
            board = outcome.board
            turn = outcome.next
            plies += 1
        }
        let score = try #require(ReversiRules.score(board))
        return (score.result, scoreDiff(score, engine))
    }

    // MARK: 언제나 합법 수 · 둘 곳 없으면 nil

    // 없으면: 엔진이 비트 → 칸 번호를 잘못 옮기거나(전치·뒤집기) 상대 쪽 합법 수를 고르는 결함이 초록으로 지나간다.
    @Test("언제나 합법 수 — 빈칸 4~56 무작위 국면 42개에서 고른 수와 동점 후보가 모두 규칙의 합법 수 안")
    func alwaysLegal() throws {
        var checked = 0
        var seed: UInt64 = 0xA1_0000
        for empties in stride(from: 56, through: 4, by: -4) {
            var found = 0
            while found < 3 {
                seed += 1
                guard let (board, color) = Self.randomPosition(empties: empties, seed: seed) else { continue }
                found += 1
                let legal = ReversiRules.legalMoves(board, color: color)
                let decision = try #require(ReversiAI.decide(board: board, toMove: color, limits: Self.limits(depth: 2, seed: seed)))
                #expect(legal.contains(decision.move), "빈칸 \(empties) \(color): \(decision.move) ∉ \(legal) / \(board.string)")
                #expect(Set(decision.tiedMoves).isSubset(of: legal), "동점 후보 \(decision.tiedMoves) ⊄ \(legal)")
                #expect(decision.tiedMoves.contains(decision.move))
                // 공개 입구도 같은 수를 낸다(같은 씨앗).
                #expect(ReversiAI.bestMove(board: board, toMove: color, limits: Self.limits(depth: 2, seed: seed)) == decision.move)
                checked += 1
            }
        }
        #expect(checked == 42)
    }

    // 없으면: 둘 곳이 없는 차례에 아무 칸(상대의 합법 수 등)을 내서 스토어가 불법 수를 보내는 결함이 지나간다.
    @Test("둘 곳 없으면 nil — 자동 패스 자리(E02 흑)·끝난 판(E05)은 nil, 같은 판 상대 색(기준선)은 그 사람의 합법 수")
    func noMoveMeansNil() throws {
        let corpus = try ReversiCorpusFile.load()
        let pass = try corpus.hand("E02")
        let passBoard = try ReversiCorpusFile.board(pass.board, "E02")
        #expect(ReversiAI.bestMove(board: passBoard, toMove: .black, limits: Self.limits(depth: 4)) == nil)
        // 기준선: 같은 판 백은 c1(2) 하나뿐이라 그 수다.
        #expect(ReversiAI.bestMove(board: passBoard, toMove: .white, limits: Self.limits(depth: 4)) == 2)

        let over = try corpus.hand("E05")
        let overBoard = try ReversiCorpusFile.board(over.board, "E05")
        #expect(ReversiAI.bestMove(board: overBoard, toMove: .black, limits: Self.limits(depth: 4)) == nil)
        #expect(ReversiAI.bestMove(board: overBoard, toMove: .white, limits: Self.limits(depth: 4)) == nil)
        #expect(ReversiAI.bestMove(board: try Self.board(String(repeating: "b", count: 64)), toMove: .white) == nil)
    }

    // MARK: 최선 동점끼리만 무작위

    // 없으면: 동점 판정이 "모든 수"나 "최선 근처"를 고르는 결함, 같은 씨앗에 다른 수가 나오는 결함이 지나간다.
    @Test("시작 판 — 흑의 네 수는 대칭이라 값이 똑같다: 동점 후보 = [19, 26, 37, 44], 씨앗 32개가 넷을 다 고르고 같은 씨앗은 같은 수")
    func symmetricOpeningTies() throws {
        var picked = Set<Int>()
        for seed in UInt64(1)...32 {
            let decision = try #require(ReversiAI.decide(board: .start, toMove: .black, limits: Self.limits(depth: 3, seed: seed)))
            #expect(decision.tiedMoves == [19, 26, 37, 44], "씨앗 \(seed): \(decision.tiedMoves)")
            picked.insert(decision.move)
            let again = ReversiAI.bestMove(board: .start, toMove: .black, limits: Self.limits(depth: 3, seed: seed))
            #expect(again == decision.move, "씨앗 \(seed): 같은 씨앗인데 \(decision.move) → \(String(describing: again))")
        }
        #expect(picked == [19, 26, 37, 44], "씨앗 32개가 고른 수 \(picked.sorted())")
    }

    // 없으면: ① 최선보다 2 낮은 수를 동점에 넣는 결함 ② 뿌리를 좁은 창(최선, 최선+1)으로 보고 경계값을 동점으로 세는 결함
    // ③ 최선이 하나뿐인데 다른 수를 내는 결함이 지나간다. 기준선: 고정 국면 여덟 가운데 최선이 하나뿐인 자리(둘)와
    // 둘 이상인 자리(여섯)가 섞여 있어 "늘 첫 수" 엔진과 "아무 수" 엔진이 서로 다른 자리에서 빨개진다.
    // (값·동점 집합은 씨앗과 무관하다 — 씨앗 둘로 잰다. 씨앗이 집합을 다 덮는지는 아래 빈칸 8 세 자리와 SLOW 가 잰다.)
    @Test("종반 고정 국면 여덟 — 엔진 값·동점 집합 = 박아 둔 전수 탐색 값, 고른 수는 그 집합 안",
          arguments: reversiAIEndgameFixtures)
    func endgameFixtureTies(_ fixture: ReversiAIEndgameFixture) throws {
        let board = try Self.board(fixture.board)
        #expect(ReversiRules.legalMoves(board, color: fixture.color) == fixture.values.keys.sorted(), "\(fixture.label): 합법 수가 박아 둔 값의 칸과 다르다")
        for seed in UInt64(1)...2 {
            let decision = try #require(ReversiAI.decide(board: board, toMove: fixture.color, limits: Self.limits(depth: 60, seed: seed)))
            #expect(decision.exact, "\(fixture.label): 판 끝까지 못 읽었다(깊이 \(decision.depth))")
            #expect(decision.score == fixture.best, "\(fixture.label): 값 \(decision.score) ≠ 전수 \(fixture.best)")
            #expect(decision.tiedMoves == fixture.bestMoves, "\(fixture.label): 동점 \(decision.tiedMoves) ≠ 전수 \(fixture.bestMoves)")
            #expect(fixture.bestMoves.contains(decision.move), "\(fixture.label): 고른 수 \(decision.move) ∉ 최선 \(fixture.bestMoves)")
        }
    }

    // 없으면: 동점 후보는 맞게 세고도 늘 첫 후보만 내는 결함(앱에서 매판 같은 기보)이 지나간다.
    @Test("종반 동점 무작위 — 빈칸 8 고정 국면 셋에서 씨앗 8개가 최선 동점 둘을 다 고르고 그 밖은 안 고른다")
    func endgameTieCoverage() throws {
        try Self.checkTieCoverage(reversiAIEndgameFixtures.filter { $0.board.filter { $0 == "." }.count == 8 }, seeds: 8, expectFixtures: 3)
    }

    @Test("종반 동점 무작위 — 고정 국면 여덟 모두 씨앗 24개가 최선 동점을 다 덮는다 (REVERSI_AI_SLOW=1)", .enabled(if: reversiAISlowEnabled()))
    func endgameTieCoverageAll() throws {
        try Self.checkTieCoverage(reversiAIEndgameFixtures, seeds: 24, expectFixtures: 8)
    }

    static func checkTieCoverage(_ fixtures: [ReversiAIEndgameFixture], seeds: UInt64, expectFixtures: Int) throws {
        #expect(fixtures.count == expectFixtures)
        for fixture in fixtures {
            let board = try Self.board(fixture.board)
            var picked = Set<Int>()
            for seed in UInt64(1)...seeds {
                let move = try #require(ReversiAI.bestMove(board: board, toMove: fixture.color, limits: Self.limits(depth: 60, seed: seed)))
                picked.insert(move)
            }
            #expect(picked == Set(fixture.bestMoves), "\(fixture.label): 고른 수 \(picked.sorted()) ≠ 최선 \(fixture.bestMoves)")
        }
    }

    // 없으면: 규칙이 바뀌었는데 박아 둔 값이 옛 규칙의 정답으로 남아 위 시험이 엉뚱한 정답지로 재는 일이 지나간다.
    // (Debug 전수 탐색이 빈칸 10 에서 1~2초라 느린 묶음에 둔다.)
    @Test("고정 국면 여덟의 박아 둔 값 = 지금 규칙의 전수 탐색 (REVERSI_AI_SLOW=1)", .enabled(if: reversiAISlowEnabled()))
    func endgameFixtureValuesMatchRules() throws {
        for fixture in reversiAIEndgameFixtures {
            let board = try Self.board(fixture.board)
            #expect(Self.bruteValues(board, fixture.color) == fixture.values, "\(fixture.label): 박아 둔 값과 전수 탐색이 다르다")
        }
    }

    // MARK: 종반 완전 탐색 = 전수 탐색

    // 없으면: 완전 탐색의 패스 처리(한쪽만 못 둘 때 상대가 이어 둔다)·끝 점수(빈칸을 이긴 쪽에)·마지막 빈칸 지름길 결함이
    // 지나간다. 무작위 국면이라 패스·no_moves 끝이 섞인다.
    @Test("종반 완전 탐색 = 전수 탐색 — 빈칸 6~8 무작위 국면 6개(흑·백 섞임)의 값과 동점 집합")
    func endgameMatchesBruteForceSmall() throws {
        try Self.compareWithBruteForce(empties: [6, 7, 8], perEmpties: 2, seed: 0xE0_0000)
    }

    @Test("종반 완전 탐색 = 전수 탐색 — 빈칸 9~10 무작위 국면 20개 (REVERSI_AI_SLOW=1)", .enabled(if: reversiAISlowEnabled()))
    func endgameMatchesBruteForceLarge() throws {
        try Self.compareWithBruteForce(empties: [9, 10], perEmpties: 10, seed: 0xE1_0000)
    }

    static func compareWithBruteForce(empties list: [Int], perEmpties: Int, seed start: UInt64) throws {
        var seed = start
        var colors = Set<ReversiColor>()
        var compared = 0
        for empties in list {
            var found = 0
            while found < perEmpties {
                seed += 1
                guard let (board, color) = randomPosition(empties: empties, seed: seed) else { continue }
                guard ReversiRules.legalMoves(board, color: color).count >= 2 else { continue }   // 하나뿐이면 탐색하지 않는다
                found += 1
                let values = bruteValues(board, color)
                let best = values.values.max()!
                let bestMoves = values.filter { $0.value == best }.map(\.key).sorted()
                let decision = try #require(ReversiAI.decide(board: board, toMove: color, limits: limits(depth: 60, seed: seed)))
                #expect(decision.exact, "\(board.string) \(color): 판 끝까지 못 읽었다")
                #expect(decision.depth == empties)
                #expect(decision.score == best, "\(board.string) \(color): 값 \(decision.score) ≠ 전수 \(best) / \(values)")
                #expect(decision.tiedMoves == bestMoves, "\(board.string) \(color): 동점 \(decision.tiedMoves) ≠ 전수 \(bestMoves)")
                colors.insert(color)
                compared += 1
            }
        }
        #expect(compared == list.count * perEmpties)
        #expect(colors.count == 2, "흑·백이 섞이지 않았다: \(colors)")
    }

    // 없으면: 깊이 상한이 빈칸보다 작은데도 완전 탐색으로 뛰어 시험의 결정적 한도(`maxDepth`)를 넘는 결함이 지나간다.
    // 깊이 6 인 까닭: 완전 탐색은 몸풀기 깊이(4)를 마친 뒤에 뛰므로 상한이 4 이하면 이 결함이 있어도 뛸 틈이 없다.
    @Test("깊이 상한이 빈칸보다 작으면 완전 탐색하지 않는다 — 빈칸 8 국면, 깊이 6 은 exact 아님 · 깊이 8 은 exact(기준선)")
    func maxDepthBoundsSolve() throws {
        let fixture = reversiAIEndgameFixtures[0]
        let board = try Self.board(fixture.board)
        let shallow = try #require(ReversiAI.decide(board: board, toMove: fixture.color, limits: Self.limits(depth: 6)))
        #expect(!shallow.exact)
        #expect(shallow.depth == 6)
        let full = try #require(ReversiAI.decide(board: board, toMove: fixture.color, limits: Self.limits(depth: 8)))
        #expect(full.exact)
        #expect(full.depth == 8)
    }

    // 없으면: 끝 점수에서 남은 빈칸을 이긴 쪽에 안 더하는 결함(V-11)이 지나간다 — 판이 가득 차서 끝나는 국면만 보면
    // 빈칸이 0 이라 갈리지 않는다. 여기는 전멸로 빈칸 59 를 남기고 끝난다.
    @Test("끝 점수는 빈칸을 이긴 쪽에 — 전멸로 일찍 끝나는 판의 값 +64, 끝난 코퍼스 판의 점수 차 = 규칙 점수")
    func earlyEndScoresEmptiesToWinner() throws {
        // 흑 a1, 백 b1·a2. 흑 c1·a3 어느 쪽을 먼저 둬도 백은 둘 곳이 없고(자동 패스) 흑이 나머지로 백을 전멸시킨다 → 64:0.
        var text = Array(repeating: Character("."), count: 64)
        text[0] = "b"; text[1] = "w"; text[8] = "w"
        let board = try Self.board(String(text))
        #expect(Self.bruteValues(board, .black) == [2: 64, 16: 64])   // 기준선(규칙만으로 센 값)
        let decision = try #require(ReversiAI.decide(board: board, toMove: .black, limits: Self.limits(depth: 60)))
        #expect(decision.exact)
        #expect(decision.score == 64, "값 \(decision.score)")
        #expect(decision.tiedMoves == [2, 16])
        // 끝난 코퍼스 판(전멸·빈칸 남은 no_moves·판 가득 무승부)마다 엔진 점수 차 = 규칙 WOF 점수 차, 두 색 시점 모두.
        let corpus = try ReversiCorpusFile.load()
        var ended = 0
        for hand in corpus.hand {
            guard let handBoard = ReversiBoard(string: hand.board), let score = ReversiRules.score(handBoard) else { continue }
            let (black, white) = handBoard.sides(.black)
            #expect(ReversiAIEngine.finalDiff(own: black, opp: white) == score.black - score.white, "\(hand.id)")
            #expect(ReversiAIEngine.finalDiff(own: white, opp: black) == score.white - score.black, "\(hand.id)")
            if handBoard.counts.empty > 0 { ended += 1 }
        }
        #expect(ended >= 1, "빈칸이 남은 끝난 판이 코퍼스에 없다 — 이 줄이 아무것도 안 잰다")
    }

    // MARK: 마감 · 취소

    // 없으면(SPEC v1.1 CCT I10): 마감을 깊이 사이에서만 보는 엔진이 통과한다 — 그 엔진은 이 국면에서 완전 탐색 한 반복이
    // 끝날 때까지(Debug 수 초) 돌아오지 않는다. `aborted` 는 이 국면이 예산 안에 다 못 읽는 무거운 자리라는 확인이다
    // (엔진이 빨라져 다 읽게 되면 더 무거운 국면으로 바꾼다 — 그래야 이 시험이 계속 깊이 사이 마감을 가른다).
    @Test("마감은 탐색 안에서 — 빈칸 14 국면을 예산 0.2초로 부르면 0.3초 안에 합법 수로 돌아온다")
    func deadlineInsideSearch() throws {
        let board = try Self.board(reversiAIHeavyBoard)
        #expect(board.counts.empty == 14)
        let clock = ContinuousClock()
        var decision: ReversiAIDecision?
        let spent = clock.measure {
            decision = ReversiAI.decide(board: board, toMove: .black,
                                        limits: ReversiAISearchLimits(timeBudget: .milliseconds(200), maxDepth: 60, tieBreakSeed: 3))
        }
        let found = try #require(decision)
        #expect(spent <= .milliseconds(300), "벽시계 \(spent)")
        #expect(found.aborted, "예산 안에 다 읽었다 — 마감 시험으로 쓸 만큼 무겁지 않다")
        #expect(!found.exact)
        #expect(ReversiRules.legalMoves(board, color: .black).contains(found.move))
    }

    // 없으면: 탐색 안의 틱이 시계만 보고 취소 문을 안 보는 결함이 지나간다(창을 닫아도 1.5초 동안 계속 돈다).
    @Test("취소는 탐색 안에서 — 예산 60초여도 50ms 뒤 취소되면 0.3초 안에 합법 수로 돌아온다")
    func cancelInsideSearch() throws {
        let board = try Self.board(reversiAIHeavyBoard)
        let started = ContinuousClock.now
        let clock = ContinuousClock()
        var decision: ReversiAIDecision?
        let spent = clock.measure {
            decision = ReversiAI.decide(board: board, toMove: .black,
                                        limits: ReversiAISearchLimits(timeBudget: .seconds(60), maxDepth: 60, tieBreakSeed: 3),
                                        isCancelled: { ContinuousClock.now - started > .milliseconds(50) })
        }
        let found = try #require(decision)
        #expect(spent <= .milliseconds(300), "벽시계 \(spent)")
        #expect(found.aborted)
        #expect(ReversiRules.legalMoves(board, color: .black).contains(found.move))
    }

    // 없으면: 처음부터 취소된 호출이 nil 을 내거나(스토어가 둘 곳 없음으로 오해) 불법 수를 내는 결함이 지나간다.
    @Test("처음부터 취소 — 곧바로 합법 수(nil 아님)")
    func cancelledFromStart() throws {
        let board = try Self.board(reversiAIHeavyBoard)
        let clock = ContinuousClock()
        var move: Int?
        let spent = clock.measure {
            move = ReversiAI.bestMove(board: board, toMove: .black, limits: Self.limits(depth: 60, budget: .seconds(60)),
                                      isCancelled: { true })
        }
        let found = try #require(move)
        #expect(ReversiRules.legalMoves(board, color: .black).contains(found))
        #expect(spent <= .milliseconds(100), "벽시계 \(spent)")
    }

    // MARK: 평가 고정

    // 없으면: 가중치 숫자를 바꾸거나(엔진 세기가 조용히 변한다) 평가 항 하나를 빼는 결함이 지나간다. 값은 손으로 셌다.
    @Test("평가 숫자 고정 — 칸 가중치 표 · 항 가중치 · 손으로 센 두 국면(100 · −61)")
    func evaluationPinned() {
        #expect(ReversiAIEval.squareWeights == [
            100, -10, 20, 8, 8, 20, -10, 100,
            -10, -15, -4, -3, -3, -4, -15, -10,
            20, -4, 6, 3, 3, 6, -4, 20,
            8, -3, 3, 0, 0, 3, -3, 8,
            8, -3, 3, 0, 0, 3, -3, 8,
            20, -4, 6, 3, 3, 6, -4, 20,
            -10, -15, -4, -3, -3, -4, -15, -10,
            100, -10, 20, 8, 8, 20, -10, 100,
        ])
        let termWeights: [Int] = [ReversiAIEval.mobility, ReversiAIEval.xPenalty, ReversiAIEval.cPenalty,
                                  ReversiAIEval.frontier, ReversiAIEval.stable]
        #expect(termWeights == [10, 40, 15, 4, 12])
        // ① 내 돌 a1·b1, 상대 c1. 가중치 (100−10) − 20 = 70 · 이동성 (d1 하나 − 0) × 10 = 10 · X/C 0(a1 은 찼고 나머지 모서리 이웃은 비었다)
        //    · 경계 (1 − 2) × 4 = −4 · 안정 (a1·b1 둘 − 0) × 12 = 24 → 100.
        let own1: UInt64 = (1 << 0) | (1 << 1)
        let opp1: UInt64 = 1 << 2
        #expect(ReversiAIEngine.evaluate(own: own1, opp: opp1, moves: ReversiBits.moves(own: own1, opp: opp1)) == 100)
        // ② 내 돌 b2(X), 상대 c3. 가중치 −15 − 6 = −21 · 이동성 (d4 − a1) 0 · a1 이 빈 채 X 에 내 돌 −40 · 경계 0 · 안정 0 → −61.
        let own2: UInt64 = 1 << 9
        let opp2: UInt64 = 1 << 18
        #expect(ReversiAIEngine.evaluate(own: own2, opp: opp2, moves: ReversiBits.moves(own: own2, opp: opp2)) == -61)
        // 기준선: ② 에서 a1 을 내 돌로 채우면 X 벌점이 사라진다(값이 갈린다).
        let own3 = own2 | 1
        #expect(ReversiAIEngine.evaluate(own: own3, opp: opp2, moves: ReversiBits.moves(own: own3, opp: opp2)) != -61)
    }

    // 없으면: 가중치 표의 한 칸 오타(대칭 깨짐)가 지나간다 — 그러면 시작 판 같은 대칭 국면의 동점이 동점이 아니게 된다.
    @Test("평가는 판의 8대칭에 불변 — 무작위 국면 24개 × 대칭 7가지")
    func evaluationSymmetric() {
        var seed: UInt64 = 0xC0_0000
        var checked = 0
        while checked < 24 {
            seed += 1
            guard let (board, color) = Self.randomPosition(empties: 20 + Int(seed % 30), seed: seed) else { continue }
            let (own, opp) = board.sides(color)
            let base = ReversiAIEngine.evaluate(own: own, opp: opp, moves: ReversiBits.moves(own: own, opp: opp))
            for kind in 1..<8 {
                let tOwn = Self.transform(bits: own, kind)
                let tOpp = Self.transform(bits: opp, kind)
                let value = ReversiAIEngine.evaluate(own: tOwn, opp: tOpp, moves: ReversiBits.moves(own: tOwn, opp: tOpp))
                #expect(value == base, "대칭 \(kind): \(value) ≠ \(base) / \(board.string)")
            }
            checked += 1
        }
    }

    // 없으면: 꽉 찬 변 규칙이나 모서리에서 이어진 줄 규칙이 빠진 결함이 지나간다.
    @Test("변 안정 돌 — 모서리에서 이어진 줄 · 꽉 찬 변 · 모서리 없는 줄은 0(기준선)")
    func stableEdges() {
        // 1행 a1~c1 내 돌, d1 상대 → 내 안정 3(a1·b1·c1), 상대 0.
        let own: UInt64 = 0b0111
        let opp: UInt64 = 0b1000
        #expect(ReversiAIEngine.stableEdgeDiscs(own: own, opp: opp) == 3)
        #expect(ReversiAIEngine.stableEdgeDiscs(own: opp, opp: own) == 0)
        // 1행이 꽉 찼다: 내 b1·d1·f1·h1, 상대 나머지 → 각자 자기 돌 넷이 안정(h1 은 모서리이자 꽉 찬 변).
        let fullOwn: UInt64 = (1 << 1) | (1 << 3) | (1 << 5) | (1 << 7)
        let fullOpp: UInt64 = (1 << 0) | (1 << 2) | (1 << 4) | (1 << 6)
        #expect(ReversiAIEngine.stableEdgeDiscs(own: fullOwn, opp: fullOpp) == 4)
        #expect(ReversiAIEngine.stableEdgeDiscs(own: fullOpp, opp: fullOwn) == 4)
        // 기준선: 모서리 없이 b1~g1 내 돌(양끝 빈칸) → 0.
        #expect(ReversiAIEngine.stableEdgeDiscs(own: 0b0111_1110, opp: 0) == 0)
    }

    // MARK: 느린 것(REVERSI_AI_SLOW=1)

    @Test("1.5초 상한 — 앱 한도(1.5초 · 깊이 60)로 여섯 국면에서 벽시계가 1.5초를 넘지 않는다 (REVERSI_AI_SLOW=1)",
          .enabled(if: reversiAISlowEnabled()))
    func respectsOneAndAHalfSeconds() throws {
        var positions: [(String, ReversiBoard, ReversiColor)] = [("시작 판", .start, .black)]
        for (empties, seed) in [(44, UInt64(0x51)), (30, 0x52), (20, 0x53), (16, 0x54)] {
            var s = seed
            while true {
                s += 1
                if let (board, color) = Self.randomPosition(empties: empties, seed: s) {
                    positions.append(("빈칸 \(empties)", board, color))
                    break
                }
            }
        }
        positions.append(("빈칸 14 무거운 자리", try Self.board(reversiAIHeavyBoard), .black))
        for (label, board, color) in positions {
            let clock = ContinuousClock()
            var decision: ReversiAIDecision?
            let spent = clock.measure {
                decision = ReversiAI.decide(board: board, toMove: color, limits: ReversiAISearchLimits(tieBreakSeed: 7))
            }
            let found = try #require(decision)
            #expect(spent <= .milliseconds(1500), "\(label): 벽시계 \(spent)")
            #expect(found.depth >= 2, "\(label): 깊이 \(found.depth)")
            print("[1.5초] \(label) → \(found.move) 깊이 \(found.depth) exact \(found.exact) 노드 \(found.nodes) "
                  + "\(String(format: "%.3f", Self.seconds(spent)))초 끊김 \(found.aborted)")
        }
    }

    /// 승률 시험의 엔진 한도(깊이로 묶어 결정적 — Debug 에서 200판을 분 단위로 돌리려는 값). 앱(1.5초)보다 약하다.
    static let matchDepth = 4

    @Test("무작위 상대 200판 — 95% 이상 이긴다(색 번갈아, 무승부는 이김이 아니다) (REVERSI_AI_SLOW=1)",
          .enabled(if: reversiAISlowEnabled()))
    func beatsRandomOpponent() throws {
        var rng = GomokuAISplitMix64(seed: 0x00AB_CDEF)
        var wins = 0, draws = 0, losses = 0
        let clock = ContinuousClock()
        let spent = try clock.measure {
            for game in 0..<200 {
                let engine: ReversiColor = game % 2 == 0 ? .black : .white
                let (result, _) = try Self.playGame(engine: engine, limits: Self.limits(depth: Self.matchDepth, seed: UInt64(game) &+ 1)) { board, color in
                    let moves = ReversiRules.legalMoves(board, color: color)
                    return moves[Int(rng.next() % UInt64(moves.count))]
                }
                if result.winner == engine { wins += 1 } else if result == .draw { draws += 1 } else { losses += 1 }
            }
        }
        print("[무작위 200판] 깊이 \(Self.matchDepth): 승 \(wins) · 무 \(draws) · 패 \(losses) · \(String(format: "%.1f", Self.seconds(spent)))초")
        #expect(wins >= 190, "승 \(wins)/200")
    }

    @Test("탐욕(최다 뒤집기) 상대 200판 — 80% 이상 이긴다(탐욕의 동점은 씨앗 무작위) (REVERSI_AI_SLOW=1)",
          .enabled(if: reversiAISlowEnabled()))
    func beatsGreedyOpponent() throws {
        var rng = GomokuAISplitMix64(seed: 0x0067_4EED)
        var wins = 0, draws = 0, losses = 0
        let clock = ContinuousClock()
        let spent = try clock.measure {
            for game in 0..<200 {
                let engine: ReversiColor = game % 2 == 0 ? .black : .white
                let (result, _) = try Self.playGame(engine: engine, limits: Self.limits(depth: Self.matchDepth, seed: UInt64(game) &+ 1)) { board, color in
                    let moves = ReversiRules.legalMoves(board, color: color)
                    let counts = moves.map { ReversiRules.flips(board, color: color, idx: $0).count }
                    let most = counts.max()!
                    let greedy = zip(moves, counts).filter { $0.1 == most }.map(\.0)
                    return greedy[Int(rng.next() % UInt64(greedy.count))]
                }
                if result.winner == engine { wins += 1 } else if result == .draw { draws += 1 } else { losses += 1 }
            }
        }
        print("[탐욕 200판] 깊이 \(Self.matchDepth): 승 \(wins) · 무 \(draws) · 패 \(losses) · \(String(format: "%.1f", Self.seconds(spent)))초")
        #expect(wins >= 160, "승 \(wins)/200")
    }
}
