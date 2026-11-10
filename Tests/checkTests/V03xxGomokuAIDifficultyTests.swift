import Foundation
import Testing
@testable import CheckCore

// MARK: - 오목 AI 난이도 — 몇 수 앞까지 계산하는가(11-10 대표: "늘 최선의 수를 못두게 하는 방식이 아니라 몇수앞까지 계산할지에 제한")
//
// 어느 단계든 수평선 안에서는 최선을 둔다 — 그래서 '한 수 앞'으로 보이는 것(내 5목 · 상대 4 막기)은 쉬움도 놓치지 않는다.
// 단계 사이의 실제 세기 차이는 느린 자동 대국(GOMOKU_AI_SELFPLAY=1)이 잰다 — 표는 GOMOKU_AI_SELFPLAY_OUT 파일로.

@Suite struct GomokuAIDifficultyTests {
    @Test("단계마다 몇 수 앞까지 — 쉬움 2 · 보통 4 · 어려움 끝까지(예전 기본값 그대로)")
    func limitsFollowLookahead() {
        let easy = GomokuAIDifficulty.easy.limits
        #expect(easy.lookahead == GomokuAIDifficultyTuning.easyLookahead && easy.maxDepth == GomokuAIDifficultyTuning.easyLookahead)
        #expect(easy.vcfDepth == max(1, GomokuAIDifficultyTuning.easyLookahead / 2) && easy.defenseVcfDepth == easy.vcfDepth)
        #expect(easy.leafVcfDepth == 0)
        let normal = GomokuAIDifficulty.normal.limits
        #expect(normal.lookahead == GomokuAIDifficultyTuning.normalLookahead && normal.maxDepth == GomokuAIDifficultyTuning.normalLookahead)
        #expect(normal.vcfDepth == max(1, GomokuAIDifficultyTuning.normalLookahead / 2) && normal.leafVcfDepth == 0)
        #expect(GomokuAIDifficultyTuning.easyLookahead < GomokuAIDifficultyTuning.normalLookahead, "쉬움이 보통보다 깊다")
        let hard = GomokuAIDifficulty.hard.limits
        let old = GomokuAISearchLimits()
        #expect(hard.lookahead == nil && hard.maxDepth == old.maxDepth && hard.timeBudget == old.timeBudget)
        #expect(hard.vcfDepth == 16 && hard.defenseVcfDepth == 16 && hard.leafVcfDepth == 8, "어려움은 예전 단일 난이도와 같아야 한다")
        #expect(GomokuAIDifficulty.hard.lookahead == nil)
    }

    @Test("쉬움 · 보통도 한 수 앞은 본다 — 내 5목은 두고 상대 4 는 막는다(일부러 틀리지 않는다)")
    func everyLevelTakesTheWinAndBlocksTheFour() throws {
        for difficulty in GomokuAIDifficulty.allCases {
            var limits = difficulty.limits
            limits.tieBreakSeed = 3
            // 백 차례: 백 F8 G8 H8 I8 · 흑 F9 G9 H9 I9 — 둘 다 4. 백은 자기 5목(E8 또는 J8)을 먼저 둔다.
            var win = GomokuBoard()
            for n in ["F8", "G8", "H8", "I8"] { win[try #require(GomokuPoint(notation: n))] = .white }
            for n in ["F9", "G9", "H9", "I9"] { win[try #require(GomokuPoint(notation: n))] = .black }
            let move = try #require(GomokuAI.bestMove(board: win, toMove: .white, limits: limits))
            #expect(GomokuRules.judge(board: win, point: move, color: .white) == .win, "\(difficulty) 이 5목을 안 뒀다(\(move.notation))")

            // 백 차례: 흑 F9 G9 H9 I9(막힘 없는 4 한쪽) · 백은 4 가 없다 → 흑의 5목 자리를 막는다.
            var block = GomokuBoard()
            for n in ["F9", "G9", "H9", "I9"] { block[try #require(GomokuPoint(notation: n))] = .black }
            block[try #require(GomokuPoint(notation: "E9"))] = .white
            block[try #require(GomokuPoint(notation: "H7"))] = .white
            let reply = try #require(GomokuAI.bestMove(board: block, toMove: .white, limits: limits))
            #expect(reply.notation == "J9", "\(difficulty) 이 4 를 안 막았다(\(reply.notation))")
        }
    }

    @Test("난이도 고르기는 기억되고 새 판 · [다시 두기]가 그 난이도로 선다")
    @MainActor
    func storeRemembersAndUsesTheDifficulty() throws {
        let suite = CheckTestScratch.uniqueSuitePath()   // ~/Library/Preferences 에 남지 않게(PreferencesLeakGateTests)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(GomokuStore.storedAIDifficulty(defaults) == .normal, "기억이 없으면 보통")
        #expect(GomokuStore.storedAIDifficulty(nil) == .normal)

        let store = GomokuStore()
        store.aiDifficultyDefaults = defaults
        store.aiRuntime.minimumThinkSeconds = 0
        store.setAIDifficulty(.easy)
        #expect(store.aiDifficulty == .easy)
        #expect(GomokuStore.storedAIDifficulty(defaults) == .easy, "고른 난이도를 기억하지 않았다")
        store.setAIDifficulty(.hard)
        #expect(GomokuStore.storedAIDifficulty(defaults) == .hard)
        defaults.set("bogus", forKey: GomokuStore.aiDifficultyKey)
        #expect(GomokuStore.storedAIDifficulty(defaults) == .normal, "모르는 값은 보통으로")
    }

    @Test("판 값은 난이도를 들고 다닌다 — 기본(시험 · 폰 경로)은 예전과 같은 어려움")
    func gameCarriesTheDifficulty() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(GomokuAIGame(humanColor: .black, now: now).difficulty == .hard)
        #expect(GomokuAIGame(humanColor: .white, difficulty: .easy, now: now).difficulty == .easy)
    }
}

// MARK: - 느린 자동 대국: 단계 사이 승률 · 한 수 시간(GOMOKU_AI_SELFPLAY=1, 판 수 GOMOKU_AI_SELFPLAY_GAMES 기본 10)

@Suite struct GomokuAIDifficultySelfPlayTests {
    private struct Pairing { let a: GomokuAIDifficulty; let b: GomokuAIDifficulty }

    /// 사다리 고르기용: `GOMOKU_AI_LADDER=1,2,3,4,6,8,hard` 면 이웃끼리 둔다(몇 수 앞 값을 고르는 측정 — 단계 상수와 무관).
    @Test("몇 수 앞 사다리 — 이웃끼리 승률(느림 — 환경 변수 뒤)",
          .enabled(if: ProcessInfo.processInfo.environment["GOMOKU_AI_LADDER"] != nil))
    func ladderTable() throws {
        let env = ProcessInfo.processInfo.environment
        let games = Int(env["GOMOKU_AI_SELFPLAY_GAMES"] ?? "") ?? 10
        let steps = (env["GOMOKU_AI_LADDER"] ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        func limits(_ step: String) -> GomokuAISearchLimits {
            if let n = Int(step) { return GomokuAIDifficulty.limits(lookahead: n) }
            return GomokuAISearchLimits()
        }
        var lines: [String] = []
        var timing: [String: [Double]] = [:]
        for i in 0..<(steps.count - 1) {
            let (a, b) = (steps[i], steps[i + 1])
            var winsA = 0, winsB = 0, draws = 0
            for g in 0..<games {
                let aIsBlack = g % 2 == 0
                let seed = UInt64(20_261_110 + g * 7919)
                let r = playOneLimits(black: limits(aIsBlack ? a : b), white: limits(aIsBlack ? b : a),
                                      blackName: aIsBlack ? a : b, whiteName: aIsBlack ? b : a, seed: seed, times: &timing)
                switch r {
                case .black?: if aIsBlack { winsA += 1 } else { winsB += 1 }
                case .white?: if aIsBlack { winsB += 1 } else { winsA += 1 }
                case nil: draws += 1
                }
            }
            let line = "\(a) vs \(b): \(winsA) : \(winsB) (무승부 \(draws))"
            lines.append(line)
            print("[gomoku-ai-ladder] " + line)
        }
        for (name, list) in timing.sorted(by: { $0.key < $1.key }) {
            let sorted = list.sorted()
            let avg = sorted.reduce(0, +) / Double(max(1, sorted.count))
            let line = "\(name) 한 수: 평균 \(Int(avg * 1000))ms · p95 \(Int(sorted[max(0, Int(Double(sorted.count) * 0.95) - 1)] * 1000))ms · 최대 \(Int((sorted.last ?? 0) * 1000))ms"
            lines.append(line)
            print("[gomoku-ai-ladder] " + line)
        }
        if let out = env["GOMOKU_AI_SELFPLAY_OUT"] { try lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8) }
    }

    private func playOneLimits(black: GomokuAISearchLimits, white: GomokuAISearchLimits, blackName: String, whiteName: String,
                               seed: UInt64, times: inout [String: [Double]]) -> GomokuColor? {
        var board = GomokuBoard()
        var rng = GomokuAISplitMix64(seed: seed)
        board[GomokuPoint(x: 7, y: 7)!] = .black
        let offsets = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
        let o = offsets[Int(rng.next() % UInt64(offsets.count))]
        board[GomokuPoint(x: 7 + o.0, y: 7 + o.1)!] = .white
        var color = GomokuColor.black
        var passes = 0
        for ply in 0..<GomokuBoard.cellCount {
            var limits = color == .black ? black : white
            limits.tieBreakSeed = seed &+ UInt64(ply)
            let started = ContinuousClock.now
            let move = GomokuAI.bestMove(board: board, toMove: color, limits: limits)
            let elapsed = ContinuousClock.now - started
            times[color == .black ? blackName : whiteName, default: []]
                .append(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
            guard let move else {
                passes += 1
                if passes >= 2 { return nil }
                color = color.opponent
                continue
            }
            passes = 0
            switch GomokuRules.judge(board: board, point: move, color: color) {
            case .win: return color
            case .forbidden, .occupied, .outOfRange: return color.opponent
            case .legal: board[move] = color
            }
            color = color.opponent
        }
        return nil
    }

    @Test("자동 대국 승률표 · 한 수 시간(느림 — 환경 변수 뒤)",
          .enabled(if: ProcessInfo.processInfo.environment["GOMOKU_AI_SELFPLAY"] == "1"))
    func selfPlayTable() throws {
        let env = ProcessInfo.processInfo.environment
        let games = Int(env["GOMOKU_AI_SELFPLAY_GAMES"] ?? "") ?? 10
        let pairings = [Pairing(a: .easy, b: .normal), Pairing(a: .normal, b: .hard), Pairing(a: .easy, b: .hard)]
        var times: [GomokuAIDifficulty: [Double]] = [:]
        var rows: [[String: Any]] = []
        for pairing in pairings {
            var winsA = 0, winsB = 0, draws = 0, forbidden = 0
            for g in 0..<games {
                // 색을 번갈아(렌주는 흑이 유리하다) · 판마다 씨앗을 바꿔 기보가 되풀이되지 않게.
                let aIsBlack = g % 2 == 0
                let seed = UInt64(20_261_110 + g * 7919)
                let result = playOne(black: aIsBlack ? pairing.a : pairing.b, white: aIsBlack ? pairing.b : pairing.a,
                                     seed: seed, times: &times)
                forbidden += result.forbidden
                switch result.winner {
                case .black?: if aIsBlack { winsA += 1 } else { winsB += 1 }
                case .white?: if aIsBlack { winsB += 1 } else { winsA += 1 }
                case nil: draws += 1
                }
            }
            #expect(forbidden == 0, "흑 AI 가 금수에 뒀다(\(pairing.a) vs \(pairing.b))")
            rows.append(["a": pairing.a.rawValue, "b": pairing.b.rawValue, "games": games, "a_wins": winsA, "b_wins": winsB, "draws": draws])
            print("[gomoku-ai-selfplay] \(pairing.a.rawValue) vs \(pairing.b.rawValue): \(winsA) : \(winsB) (무승부 \(draws))")
        }
        var timing: [String: Any] = [:]
        for (level, list) in times {
            let sorted = list.sorted()
            guard !sorted.isEmpty else { continue }
            let avg = sorted.reduce(0, +) / Double(sorted.count)
            let p95 = sorted[max(0, Int(Double(sorted.count) * 0.95) - 1)]
            timing[level.rawValue] = ["moves": sorted.count, "avg_ms": Int(avg * 1000), "p95_ms": Int(p95 * 1000), "max_ms": Int((sorted.last ?? 0) * 1000)]
            print("[gomoku-ai-selfplay] \(level.rawValue) 한 수: 평균 \(Int(avg * 1000))ms · p95 \(Int(p95 * 1000))ms · 최대 \(Int((sorted.last ?? 0) * 1000))ms (\(sorted.count)수)")
        }
        if let out = env["GOMOKU_AI_SELFPLAY_OUT"] {
            let data = try JSONSerialization.data(withJSONObject: ["pairings": rows, "timing": timing,
                                                                   "lookahead": ["easy": GomokuAIDifficultyTuning.easyLookahead,
                                                                                 "normal": GomokuAIDifficultyTuning.normalLookahead]],
                                                  options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: out))
        }
    }

    /// 한 판: 첫 두 수는 씨앗으로 가운데 근처에 흩어 두고(같은 기보 반복을 막는다), 그 뒤는 두 AI 가 번갈아 둔다.
    private func playOne(black: GomokuAIDifficulty, white: GomokuAIDifficulty, seed: UInt64,
                         times: inout [GomokuAIDifficulty: [Double]]) -> (winner: GomokuColor?, forbidden: Int) {
        var board = GomokuBoard()
        var rng = GomokuAISplitMix64(seed: seed)
        board[GomokuPoint(x: 7, y: 7)!] = .black
        let offsets = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
        let o = offsets[Int(rng.next() % UInt64(offsets.count))]
        board[GomokuPoint(x: 7 + o.0, y: 7 + o.1)!] = .white
        var color = GomokuColor.black
        var forbidden = 0
        var passes = 0
        for ply in 0..<GomokuBoard.cellCount {
            let level = color == .black ? black : white
            var limits = level.limits
            limits.tieBreakSeed = seed &+ UInt64(ply)
            let started = ContinuousClock.now
            let move = GomokuAI.bestMove(board: board, toMove: color, limits: limits)
            let elapsed = ContinuousClock.now - started
            times[level, default: []].append(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
            guard let move else {
                passes += 1
                if passes >= 2 || board.stoneCount >= GomokuBoard.cellCount { return (nil, forbidden) }
                color = color.opponent
                continue
            }
            passes = 0
            switch GomokuRules.judge(board: board, point: move, color: color) {
            case .win: return (color, forbidden)
            case .forbidden: forbidden += 1; return (color.opponent, forbidden)
            case .occupied, .outOfRange: return (color.opponent, forbidden + 1)
            case .legal: board[move] = color
            }
            color = color.opponent
        }
        return (nil, forbidden)
    }
}
