// 원본: Sources/CheckCore/GomokuAI.swift · GomokuAIEngine.swift · GomokuAIGame.swift · ChessAIEngine.swift @ 1b8260d (골든 생성기 — W1-b)
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// W1-b 골든(AI): 혼자 두는 판 전용이라 C§5.1 은 **집합 동등**(정답 집합 안)을 요구한다 — renju/ai-puzzles · chess/ai-puzzles.
// 거기에 더해 씨앗·깊이를 박은 결정을 **비트**로 싣는다(renju/ai-trace · chess/ai-trace: 고른 수 · 점수 · 마친 깊이 · 노드 수).
// Kotlin 은 Swift 표준 라이브러리의 randomElement(using:) 알고리즘(Lemire next(upperBound:))까지 옮겼다 — 같은 씨앗이면 같은 수다.
// 시간 예산은 600초(사실상 무한)라 깊이가 먼저 끊는다 — 벽시계가 결과를 바꾸지 않는다.
//
//  · renju/ai-puzzles  gomoku-ai-puzzles.json 16퍼즐: expect · reject · winWithin · holdFor+loseAfter(엔진 대 엔진 수순)
//  · renju/ai-trace    줄 모양 표·Zobrist 지문 + 국면별 chooseMove(수·노드·마친 깊이) + bestMove 지름길(빈 판·꽉 찬 판)
//  · renju/ai-game     GomokuAIGame 대본(사람 착수·AI 착수·대리 착수·패스·시계 멈춤·기권) → 걸음마다 상태
//  · chess/ai-puzzles  ChessAIEngineTests 의 메이트·공짜 퀸·정지 탐색·스테일메이트·3회 반복 과제
//  · chess/ai-trace    Zobrist·칸 가치표 지문 + 국면별 decide(수·점수·깊이·노드) + 증분 해시 수순

@Suite("GoldenExport games-board — AI(renju/ai-* · chess/ai-*)")
struct GoldenExportGamesBoardAI {
    static let gomokuSources = ["Sources/CheckCore/GomokuAI.swift", "Sources/CheckCore/GomokuAIEngine.swift",
                                "Sources/CheckCore/GomokuRules.swift"]
    // GomokuAIEngine.swift: 체스 AI 도 GomokuAISplitMix64 로 Zobrist 키·동점 고르기를 만들고(ChessAIEngine.swift), 생성기의 무작위 걷기도 그 난수다.
    static let chessSources = ["Sources/CheckCore/ChessAIEngine.swift", "Sources/CheckCore/ChessRules.swift",
                               "Sources/CheckCore/ChessFEN.swift", "Sources/CheckCore/ChessNotation.swift",
                               "Sources/CheckCore/GomokuAIEngine.swift"]
    static let budget: Duration = .seconds(600)
    static let puzzleSeed: UInt64 = 7
    static let chessSeed: UInt64 = 0xC0FF_EE11

    // MARK: renju/ai-puzzles

    @Test("renju/ai-puzzles — 16퍼즐 집합 동등(expect · reject · winWithin · holdFor+loseAfter)")
    func renjuAIPuzzles() throws {
        let fixture = try Self.gomokuFixture()
        let puzzles = try #require(fixture["puzzles"] as? [[String: Any]])
        let limits = GomokuAISearchLimits(timeBudget: Self.budget, maxDepth: 3, tieBreakSeed: Self.puzzleSeed)
        var cases: [GoldenJSON] = []
        for puzzle in puzzles {
            let id = try #require(puzzle["id"] as? String)
            let black = try #require(puzzle["black"] as? [String])
            let white = try #require(puzzle["white"] as? [String])
            let toMoveText = try #require(puzzle["toMove"] as? String)
            let toMove = try #require(GomokuColor(rawValue: toMoveText))
            let expect = puzzle["expect"] as? [String]
            let reject = puzzle["reject"] as? [String]
            let winWithin = puzzle["winWithin"] as? Int
            let holdFor = puzzle["holdFor"] as? Int
            let loseAfter = puzzle["loseAfter"] as? String
            let board = try Self.board(black: black, white: white)
            let move = try #require(GomokuAI.bestMove(board: board, toMove: toMove, limits: limits), "\(id): 둘 곳이 없다")
            let verdict = GomokuRules.judge(board: board, point: move, color: toMove)
            #expect(verdict == .legal || verdict == .win, "\(id): 둘 수 없는 \(move.notation)")
            if let expect { #expect(expect.contains(move.notation), "\(id): \(move.notation) ∉ \(expect)") }
            if let reject { #expect(!reject.contains(move.notation), "\(id): \(move.notation) ∈ reject") }
            if let winWithin {
                #expect(Self.playOut(board, toMove: toMove, plies: 2 * winWithin - 1, limits: limits).winner == toMove, "\(id): \(winWithin)수 승 실패")
            }
            if let holdFor {
                var after = board
                after[move] = toMove
                #expect(Self.playOut(after, toMove: toMove.opponent, plies: 2 * holdFor - 1, limits: limits).winner != toMove.opponent,
                        "\(id): \(move.notation) 뒤 상대가 이겼다")
                if let loseAfter, let bad = GomokuPoint(notation: loseAfter) {
                    var wrong = board
                    wrong[bad] = toMove
                    #expect(Self.playOut(wrong, toMove: toMove.opponent, plies: 2 * holdFor - 1, limits: limits).winner == toMove.opponent,
                            "\(id): 대조군 \(loseAfter) 뒤에도 상대가 못 이겼다")
                }
            }
            cases.append([
                "id": .string(id),
                "black": .array(black.map(GoldenJSON.string)),
                "white": .array(white.map(GoldenJSON.string)),
                "toMove": .string(toMove.rawValue),
                "expect": expect.map { .array($0.map(GoldenJSON.string)) } ?? .null,
                "reject": reject.map { .array($0.map(GoldenJSON.string)) } ?? .null,
                "winWithin": winWithin.map(GoldenJSON.int) ?? .null,
                "holdFor": holdFor.map(GoldenJSON.int) ?? .null,
                "loseAfter": loseAfter.map(GoldenJSON.string) ?? .null,
                "maxDepth": 3,
                "seed": .hex64(Self.puzzleSeed),
                "swiftMove": .string(move.notation),
            ])
        }
        #expect(cases.count == 16)
        goldenEmit(GoldenFile(
            golden: "renju/ai-puzzles",
            equivalence: .set,
            swiftSources: Self.gomokuSources + ["Tests/checkTests/Fixtures/gomoku-ai-puzzles.json"],
            spec: [
                "limits": "GomokuAISearchLimits(timeBudget: 600초, maxDepth, tieBreakSeed: seed). 깊이가 먼저 끊는다.",
                "set": "Kotlin 의 bestMove 가 ① 둘 수 있는 수(legal·win) ② expect 가 있으면 그 안 ③ reject 가 있으면 밖. swiftMove 는 Swift 가 고른 수(참고 — 비트 대조는 renju/ai-trace).",
                "winWithin": "엔진 대 엔진(같은 한도)으로 toMove 부터 2n−1 수를 두면 toMove 가 5목을 만든다. 모든 수는 규칙상 둘 수 있어야 한다(아니면 실패).",
                "holdFor": "엔진의 수를 둔 뒤 상대부터 2n−1 수 안에 상대가 못 이긴다. loseAfter(엉뚱한 수)를 둔 뒤에는 상대가 이긴다 — 위협이 진짜라는 대조군.",
            ],
            cases: cases
        ))
    }

    // MARK: renju/ai-trace

    @Test("renju/ai-trace — 표 지문 + 국면별 chooseMove(수 · 노드 · 마친 깊이) 비트 대조")
    func renjuAITrace() throws {
        var cases: [GoldenJSON] = []
        var tables = GoldenFNV1a64()
        for value in GomokuAITables.blackShapes { tables.add(UInt64(value)) }
        let black = tables.hex
        tables = GoldenFNV1a64()
        for value in GomokuAITables.whiteShapes { tables.add(UInt64(value)) }
        let white = tables.hex
        var categories = GoldenFNV1a64()
        for value in GomokuAITables.combos.categories { categories.add(UInt64(value)) }
        var values = GoldenFNV1a64()
        for value in GomokuAITables.combos.values { values.add(Int(value)) }
        var zobrist = GoldenFNV1a64()
        for value in GomokuAITables.zobrist { zobrist.add(value) }
        cases.append([
            "id": "tables",
            "blackShapes": .string(black),
            "whiteShapes": .string(white),
            "comboCategories": .string(categories.hex),
            "comboValues": .string(values.hex),
            "zobrist": .string(zobrist.hex),
            "zobristHead": .array(GomokuAITables.zobrist.prefix(4).map { .hex64($0) }),
            "counts": .array([.int(GomokuAITables.blackShapes.count), .int(GomokuAITables.combos.values.count), .int(GomokuAITables.zobrist.count)]),
            // 이름 붙은 탐색 상수. 이름 없는 예산(루트 VCF 30,000 · 상대 VCF 20,000 · 방어 확인 4,000 · 잎 120)은 budget-* 국면의 노드 수가 잰다.
            "engine": [
                "width": .int(GomokuAIEngine.width), "cellCount": .int(GomokuAIEngine.cellCount), "win": .int(GomokuAIEngine.win),
                "infinity": .int(GomokuAIEngine.infinity), "maxPly": .int(GomokuAIEngine.maxPly), "ttBits": .int(GomokuAIEngine.ttBits),
                "centralityWeight": .int(GomokuAIEngine.centralityWeight), "keyCount": .int(GomokuAITables.keyCount),
            ],
        ])

        var positions: [(String, GomokuBoard, GomokuColor, Int, UInt64)] = []
        let fixture = try Self.gomokuFixture()
        for puzzle in try #require(fixture["puzzles"] as? [[String: Any]]) {
            let board = try Self.board(black: puzzle["black"] as? [String] ?? [], white: puzzle["white"] as? [String] ?? [])
            let color = try #require(GomokuColor(rawValue: puzzle["toMove"] as? String ?? ""))
            positions.append(("puzzle-\(puzzle["id"] as? String ?? "?")", board, color, 3, Self.puzzleSeed))
        }
        for (index, game) in (try #require(fixture["midgames"] as? [[String: Any]])).enumerated() {
            let board = try Self.board(black: game["black"] as? [String] ?? [], white: game["white"] as? [String] ?? [])
            let color = try #require(GomokuColor(rawValue: game["toMove"] as? String ?? ""))
            let name = game["id"] as? String ?? "?"
            positions.append(("midgame-\(name)-d2", board, color, 2, 1))
            if index < 2 { positions.append(("midgame-\(name)-d3", board, color, 3, Self.puzzleSeed)) }
        }
        var tie = GomokuBoard()
        tie[GomokuPoint(notation: "H8")!] = .black
        for seed: UInt64 in 0..<24 { positions.append((String(format: "tie-%02d", Int(seed)), tie, .white, 1, seed)) }
        var rng = GomokuAISplitMix64(seed: 0x0B1B_A17E_2026_1028)
        for index in 0..<16 {
            var board = GomokuBoard()
            var color = GomokuColor.black
            let stones = Int.random(in: 6...40, using: &rng)
            for _ in 0..<stones {
                let legal = Self.nearLegal(board, color)
                guard !legal.isEmpty else { break }
                let move = legal[Int.random(in: 0..<legal.count, using: &rng)]
                if GomokuRules.judge(board: board, point: move, color: color) == .win { break }
                board[move] = color
                color = color.opponent
            }
            positions.append((String(format: "random-%02d", index), board, color, 2, UInt64(index) &* 0x9E37_79B9 &+ 3))
        }

        // VCF 예산 국면 — 닫힌 3(O A A A _ _)을 흩어 놓아 4 로 미는 수순이 많지만 끝내 못 이기는 판(탐색 나무가 예산보다 크다).
        // 예산이 바닥나는 칸에서 노드 수가 예산 숫자를 그대로 드러낸다(30,000 을 29,000 으로 바꾸면 chooseMove 노드가 1,000 줄어든다).
        // 판은 Kotlin 탐색으로 찾은 글자를 박았고, 여기서 Swift 엔진으로 "예산이 정말 바닥난다"를 먼저 잰다(판이 공허해지면 빨강).
        for (id, text, attacker) in Self.budgetBoards {
            let board = try #require(GomokuBoard(serverString: text), "\(id)")
            let fresh = { GomokuAIEngine(board: board, budget: Self.budget, isCancelled: { false }) }
            switch id {
            case "budget-root":
                // 흰 차례 · 흰 VCF 가 30,000(루트 4단계)을 다 쓰고도 못 찾는다.
                let engine = fresh()
                #expect(!engine.hasVCF(attacker: attacker, depth: 16, budget: 30_000) && engine.nodes > 30_000, "\(id): 루트 VCF 예산이 안 바닥난다(\(engine.nodes))")
            case "budget-opponent":
                // 흰 차례 · 흑 VCF 가 20,000(5단계 상대 VCF)을 다 쓰고도 못 찾는다. 흰 VCF 는 바로 끝난다.
                let engine = fresh()
                #expect(!engine.hasVCF(attacker: attacker, depth: 16, budget: 20_000) && engine.nodes > 20_000, "\(id): 상대 VCF 예산이 안 바닥난다(\(engine.nodes))")
            default:
                // 흰 차례 · 흑 VCF 가 20,000 안에 있고, 흰 수 하나를 둔 뒤 다시 보는 방어 확인(4,000)이 바닥나는 칸이 있다.
                let engine = fresh()
                #expect(engine.hasVCF(attacker: attacker, depth: 16, budget: 20_000) && engine.nodes <= 20_000, "\(id): 상대 VCF 가 20,000 안에 없다")
                var exhausted = 0
                for index in 0..<GomokuBoard.cellCount {
                    let point = GomokuPoint(x: index % 15, y: index / 15)!
                    guard board[point] == nil else { continue }
                    var after = board
                    after[point] = .white
                    let probe = GomokuAIEngine(board: after, budget: Self.budget, isCancelled: { false })
                    _ = probe.hasVCF(attacker: attacker, depth: 16, budget: 4_000)
                    if probe.nodes > 4_000 { exhausted += 1 }
                }
                #expect(exhausted > 0, "\(id): 방어 확인 예산(4,000)이 바닥나는 칸이 없다")
            }
            positions.append((id, board, .white, 1, Self.puzzleSeed))
        }

        var distinctMoves = Set<String>()
        for (id, board, color, depth, seed) in positions {
            // 정적 평가(줄 모양 점수 합 + 중앙 가까움 × 2): 새 엔진에서 깊이 0 · 1 네가맥스 — 수가 같아도 평가식이 갈리면 여기서 잡힌다.
            let side = color == .black ? 1 : 2
            let eval0 = GomokuAIEngine(board: board, budget: Self.budget, isCancelled: { false })
                .negamax(0, -GomokuAIEngine.infinity, GomokuAIEngine.infinity, ply: 0, side: side)
            let eval1 = GomokuAIEngine(board: board, budget: Self.budget, isCancelled: { false })
                .negamax(1, -GomokuAIEngine.infinity, GomokuAIEngine.infinity, ply: 0, side: side)
            let engine = GomokuAIEngine(board: board, budget: Self.budget, isCancelled: { false })
            var rng = GomokuAISplitMix64(seed: seed)
            let raw = engine.chooseMove(side: color == .black ? 1 : 2, maxDepth: depth, rng: &rng)
            let point = raw.map { GomokuAIEngine.coordinates($0) }.flatMap { GomokuPoint(x: $0.x, y: $0.y) }
            let viaPublic = GomokuAI.bestMove(board: board, toMove: color,
                                              limits: GomokuAISearchLimits(timeBudget: Self.budget, maxDepth: depth, tieBreakSeed: seed))
            #expect(viaPublic == point, "\(id): bestMove \(viaPublic?.notation ?? "nil") ≠ chooseMove \(point?.notation ?? "nil")")
            #expect(!engine.aborted, "\(id): 시간 예산에 끊겼다 — 골든이 벽시계에 기댄다")
            if let point { distinctMoves.insert("\(id.prefix(3)):\(point.notation)") }
            cases.append([
                "id": .string(id),
                "board": .string(board.serverString),
                "toMove": .string(color.rawValue),
                "maxDepth": .int(depth),
                "seed": .hex64(seed),
                "move": point.map { .string($0.notation) } ?? .null,
                "nodes": .int(engine.nodes),
                "completedDepth": .int(engine.completedDepth),
                "eval0": .int(eval0),
                "eval1": .int(eval1),
            ])
        }
        // 동점 씨앗 24개가 한 수로 몰리면 동점 고르기를 못 잰다(Swift exactTiesAreBrokenBySeedAndOnlyAmongTies 와 같은 조건).
        #expect(distinctMoves.filter { $0.hasPrefix("tie") }.count >= 2, "동점 국면에서 씨앗이 수를 안 가른다")

        // bestMove 지름길: 빈 판은 천원, 꽉 찬 판은 nil, 흑이 금수뿐이면 nil · 백은 그 칸.
        var full = GomokuBoard()
        for index in 0..<GomokuBoard.cellCount {
            full[GomokuPoint(x: index % 15, y: index / 15)!] = (index / 15 + index % 15) % 2 == 0 ? .black : .white
        }
        var onlyForbidden = GomokuBoard()
        for index in 0..<GomokuBoard.cellCount { onlyForbidden[GomokuPoint(x: index % 15, y: index / 15)!] = .white }
        for notation in ["E8", "F8", "G8", "I8", "J8"] { onlyForbidden[GomokuPoint(notation: notation)!] = .black }
        onlyForbidden[GomokuPoint(notation: "H8")!] = nil
        let shortcuts: [(String, GomokuBoard, GomokuColor)] = [
            ("shortcut-empty-black", GomokuBoard(), .black), ("shortcut-empty-white", GomokuBoard(), .white),
            ("shortcut-full-black", full, .black), ("shortcut-full-white", full, .white),
            ("shortcut-forbidden-black", onlyForbidden, .black), ("shortcut-forbidden-white", onlyForbidden, .white),
        ]
        for (id, board, color) in shortcuts {
            let move = GomokuAI.bestMove(board: board, toMove: color,
                                         limits: GomokuAISearchLimits(timeBudget: Self.budget, maxDepth: 3, tieBreakSeed: Self.puzzleSeed))
            cases.append([
                "id": .string(id),
                "board": .string(board.serverString),
                "toMove": .string(color.rawValue),
                "maxDepth": 3,
                "seed": .hex64(Self.puzzleSeed),
                "bestMove": move.map { .string($0.notation) } ?? .null,
            ])
        }
        goldenEmit(GoldenFile(
            golden: "renju/ai-trace",
            equivalence: .bit,
            swiftSources: Self.gomokuSources,
            spec: [
                "tables": "줄 모양 표(흑 정확히 5 · 백 5 이상, 3^10 = 59049칸) · 네 방향 조합 표(4096칸 등급·점수) · Zobrist(625×2+1, SplitMix64 씨앗 0x6f6d6f6b75414921)를 FNV-1a 64 로 접은 값(칸 값 하나 = UInt64 하나, 점수는 Int64 비트). zobristHead 는 처음 넷.",
                "choice": "GomokuAIEngine(board:budget:600초).chooseMove(side:maxDepth:rng: SplitMix64(seed)) — move(좌표 또는 null) · nodes(틱 수) · completedDepth. bestMove(같은 한도)와 같은 수다. eval0·eval1 은 새 엔진의 negamax(깊이 0·1, ±infinity, ply 0, 두는 쪽) — 정적 평가식 대조. 동점 고르기는 Swift randomElement(using:) = Int.random(in: 0..<n) = Lemire next(upperBound:).",
                "engine": "tables 의 engine 칸 — 이름 붙은 탐색 상수(패딩 폭 25 · 칸 625 · 승 점수 · 무한 · 최대 반수 96 · TT 비트 17 · 중앙 가중치 2 · 줄 모양 키 3^10).",
                "budget": "budget-root(흰 VCF 가 루트 예산 30,000 을 다 쓴다) · budget-opponent(흑 VCF 가 상대 예산 20,000 을 다 쓴다) · budget-defense(흑 VCF 는 20,000 안에 있고 방어 확인 4,000 이 바닥나는 수가 있다) — 흰 차례 · 깊이 1 · 씨앗 7. nodes 가 이름 없는 VCF 예산 숫자를 잰다.",
                "shortcut": "GomokuAI.bestMove — 빈 판은 H8, 꽉 찬 판은 null, 흑이 둘 곳이 금수뿐이면 null.",
                "board": "serverString(225자). 무작위 국면(random-*)은 생성기 전용 걷기라 Kotlin 은 글자에서 읽는다.",
            ],
            cases: cases
        ))
    }

    // MARK: renju/ai-game

    @Test("renju/ai-game — GomokuAIGame 대본 → 걸음마다 상태(규칙 패스 · 무승부 · 대리 착수 · 시계 멈춤)")
    func renjuAIGame() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        func pt(_ notation: String) -> GomokuPoint { GomokuPoint(notation: notation)! }
        let doubleThree = try Self.board(black: ["F8", "G8", "H6", "H7"], white: ["C3", "M12", "K13", "B14"])
        var tiled = GomokuBoard()
        for y in 0..<15 { for x in 0..<15 { tiled[GomokuPoint(x: x, y: y)!] = (x + 2 * y) % 4 < 2 ? .black : .white } }
        for (notation, color) in [("D8", GomokuColor.white), ("E8", .black), ("F8", .black), ("G8", .black),
                                  ("I8", .black), ("J8", .black), ("K8", .white)] { tiled[pt(notation)] = color }
        tiled[pt("H8")] = nil
        tiled[pt("A1")] = nil
        var onlyH8 = tiled
        onlyH8[pt("A1")] = .white
        var empties: [GomokuPoint] = []
        for y in 0..<15 { for x in 0..<15 { let p = GomokuPoint(x: x, y: y)!; if doubleThree[p] == nil { empties.append(p) } } }
        let h8Index = try #require(empties.firstIndex(of: pt("H8")))
        let fiveBoard = try Self.board(black: ["A1", "B1", "C1", "D1"], white: ["A3", "B3", "C3", "D3"])
        let e1Index = try #require(GomokuAIGame.legalPoints(on: fiveBoard, color: .black).firstIndex(of: pt("E1")))

        struct Scenario {
            let id: String
            let human: GomokuColor
            let board: GomokuBoard?
            let turn: GomokuColor
            let streak: Int
            let lossStreak: Int
            let steps: [(String, Double, String?, Int?)]   // (op, t, point, index)
        }
        let scenarios: [Scenario] = [
            Scenario(id: "human-five", human: .black, board: try Self.board(black: ["D8", "E8", "F8", "G8"], white: ["D9", "E9", "F9", "G9"]),
                     turn: .black, streak: 0, lossStreak: 3,
                     steps: [("human", 1, "H8", nil), ("human", 2, "A1", nil), ("ai", 3, "A2", nil), ("auto", 4, nil, 0), ("resign", 5, nil, nil)]),
            Scenario(id: "ai-five", human: .white, board: try Self.board(black: ["D8", "E8", "F8", "G8"], white: ["D9", "E9", "F9", "G9"]),
                     turn: .black, streak: 0, lossStreak: 3, steps: [("ai", 0, "H8", nil), ("check", 1, nil, nil)]),
            Scenario(id: "white-overline", human: .white, board: try Self.board(black: ["C1", "D1", "E1", "G1", "H1"], white: ["C8", "D8", "E8", "G8", "H8"]),
                     turn: .white, streak: 0, lossStreak: 3, steps: [("human", 0, "F8", nil)]),
            Scenario(id: "refusals", human: .black, board: doubleThree, turn: .black, streak: 0, lossStreak: 3,
                     steps: [("human", 0, "H8", nil), ("human", 0, "F8", nil), ("human", 1, "A1", nil), ("human", 2, "A2", nil)]),
            Scenario(id: "ai-refusals", human: .white, board: doubleThree, turn: .black, streak: 0, lossStreak: 3,
                     steps: [("human", 0, "A1", nil), ("ai", 0, "H8", nil), ("ai", 0, "F8", nil), ("ai", 0, nil, nil),
                             ("fallback", 0, nil, 0), ("fallback", 0, nil, 999), ("fallback", 0, nil, -4), ("ai", 1, "H9", nil),
                             ("human", 2.5, "H10", nil)]),
            Scenario(id: "clock", human: .black, board: nil, turn: .black, streak: 0, lossStreak: 3,
                     steps: [("check", 29.9, nil, nil), ("check", 30, nil, nil), ("pause", 10, nil, nil), ("check", 10_000, nil, nil),
                             ("resume", 100, nil, nil), ("human", 101, "H8", nil), ("pause", 101.5, nil, nil), ("ai", 102, "I9", nil),
                             ("pause", 131.5, nil, nil), ("resume", 200, nil, nil), ("pause", 250, nil, nil), ("resume", 300, nil, nil),
                             ("check", 300, nil, nil), ("resume", 301, nil, nil)]),
            Scenario(id: "auto-skips-forbidden", human: .black, board: doubleThree, turn: .black, streak: 0, lossStreak: 3,
                     steps: [("auto", 31, nil, h8Index), ("ai", 32, "O15", nil), ("human", 33, "A15", nil)]),
            Scenario(id: "auto-streak-lose", human: .black, board: nil, turn: .black, streak: 0, lossStreak: 3,
                     steps: [("auto", 30, nil, 0), ("ai", 31, "O14", nil), ("auto", 61, nil, 0), ("ai", 62, "O13", nil), ("auto", 92, nil, 0),
                             ("auto", 93, nil, 0)]),
            Scenario(id: "auto-clamp", human: .black, board: nil, turn: .black, streak: 0, lossStreak: 5,
                     steps: [("auto", 30, nil, 10_000), ("ai", 31, "H8", nil), ("auto", 61, nil, -5), ("ai", 62, "H9", nil), ("human", 63, "G7", nil)]),
            Scenario(id: "third-auto-five", human: .black, board: fiveBoard, turn: .black, streak: 2, lossStreak: 3,
                     steps: [("auto", 30, nil, e1Index)]),
            Scenario(id: "pass-and-draw", human: .white, board: tiled, turn: .white, streak: 0, lossStreak: 3,
                     steps: [("human", 0, "A1", nil), ("check", 29.5, nil, nil), ("human", 1, "H8", nil)]),
            Scenario(id: "ai-black-pass", human: .white, board: onlyH8, turn: .black, streak: 0, lossStreak: 3,
                     steps: [("ai", 0, "H8", nil), ("fallback", 0, nil, 0), ("ai", 0, nil, nil), ("resign", 1, nil, nil), ("resign", 2, nil, nil)]),
            Scenario(id: "auto-pass", human: .black, board: onlyH8, turn: .black, streak: 0, lossStreak: 3,
                     steps: [("auto", 30, nil, 0), ("ai", 31, nil, nil), ("human", 32, "H8", nil)]),
            Scenario(id: "loss-streak-one", human: .black, board: nil, turn: .black, streak: 0, lossStreak: 1,
                     steps: [("auto", 30, nil, 7)]),
            Scenario(id: "loss-streak-zero", human: .white, board: nil, turn: .black, streak: 0, lossStreak: 0,
                     steps: [("ai", 0, "H8", nil), ("auto", 30, nil, 3), ("check", 31, nil, nil)]),
        ]

        var cases: [GoldenJSON] = []
        for scenario in scenarios {
            var game: GomokuAIGame
            if let board = scenario.board {
                game = GomokuAIGame(id: "ai-golden-\(scenario.id)", humanColor: scenario.human, board: board, turn: scenario.turn,
                                    humanAutoStreak: scenario.streak, autoLossStreak: scenario.lossStreak, now: t0)
            } else {
                game = GomokuAIGame(id: "ai-golden-\(scenario.id)", humanColor: scenario.human, autoLossStreak: scenario.lossStreak, now: t0)
            }
            var steps: [GoldenJSON] = [["op": "start", "tBits": .bits(0), "result": .null, "state": Self.state(game, t0: t0, now: t0)]]
            for (op, offset, notation, index) in scenario.steps {
                let now = t0.addingTimeInterval(offset)
                var result: GoldenJSON = .null
                switch op {
                case "human":
                    let refusal = game.humanPlace(pt(notation!), now: now)
                    result = refusal.map { .string($0.kind.rawValue + ($0.reason.map { ":" + $0.rawValue } ?? "")) } ?? .null
                case "ai":
                    result = .bool(game.applyAIMove(notation.map(pt), now: now))
                case "auto":
                    result = .bool(game.autoPlaceHuman(now: now, randomIndex: { _ in index! }))
                case "fallback":
                    result = game.randomAIFallback(randomIndex: { _ in index! }).map { .string($0.notation) } ?? .null
                case "pause": game.pause(now: now)
                case "resume": game.resume(now: now)
                case "resign": game.resign()
                case "check": break
                default: Issue.record("모르는 op \(op)")
                }
                steps.append([
                    "op": .string(op),
                    "tBits": .bits(offset),
                    "point": notation.map(GoldenJSON.string) ?? .null,
                    "index": index.map(GoldenJSON.int) ?? .null,
                    "result": result,
                    "state": Self.state(game, t0: t0, now: now),
                ])
            }
            cases.append([
                "id": .string(scenario.id),
                "humanColor": .string(scenario.human.rawValue),
                "board": scenario.board.map { .string($0.serverString) } ?? .null,
                "turn": .string(scenario.turn.rawValue),
                "humanAutoStreak": .int(scenario.streak),
                "autoLossStreak": .int(scenario.lossStreak),
                "turnSecondsBits": .bits(30),
                "steps": .array(steps),
            ])
        }
        cases.append([
            "id": "ids",
            "idPrefix": .string(GomokuAIGame.idPrefix),
            "matches": .array(["ai-", "ai-x", "AI-x", "", "abababab-2222-3333-4444-555555555555", "xai-1"].map {
                .array([.string($0), .bool(GomokuAIGame.isAIMatchID($0))])
            }),
            "nilMatches": .bool(GomokuAIGame.isAIMatchID(nil)),
            "freshPrefix": .bool(GomokuAIGame(humanColor: .black, now: t0).id.hasPrefix(GomokuAIGame.idPrefix)),
        ])
        goldenEmit(GoldenFile(
            golden: "renju/ai-game",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/GomokuAIGame.swift", "Sources/CheckCore/GomokuRules.swift",
                           "Sources/CheckCore/GomokuStore.swift", "Sources/CheckCore/GomokuTurnWarning.swift"],
            spec: [
                "start": "board 가 null 이면 새 판 init(id:humanColor:autoLossStreak:now:)(흑 차례), 아니면 init(id:humanColor:board:turn:humanAutoStreak:autoLossStreak:now:). 시작 시각 t0 = 1970 기준 1_800_000_000초, 걸음 시각은 t0 + tBits(초). turnSeconds 30.",
                "ops": "human(point) → humanPlace 의 거절('<kind>' 또는 '<kind>:<reason>', null = 받음) · ai(point|null) → applyAIMove 의 불 · auto(index) → autoPlaceHuman(randomIndex 는 언제나 index) 의 불 · fallback(index) → randomAIFallback 의 좌표|null(상태 불변) · pause · resume · resign · check(아무것도 안 함).",
                "state": "board(serverString) · moveCount · lastMove · turn · deadline(t0 기준 초 비트|null) · paused(남은 초 비트|null) · finished · outcome(won·lost·draw) · endReason(rawValue) · autoPoints(인덱스 순 좌표) · lastAuto · blackPassed · streak(humanAutoStreak) · expired(isHumanClockExpired(now: 그 걸음 시각)) · watches(GomokuTurnWarning.watchesMyClock(matchState()) — 안 끝남 · 마감 있음 · 차례 = 사람).",
            ],
            cases: cases
        ))
    }

    // MARK: chess/ai-puzzles

    @Test("chess/ai-puzzles — 메이트 · 공짜 퀸 · 정지 탐색 · 스테일메이트 · 3회 반복(집합 동등)")
    func chessAIPuzzles() throws {
        var cases: [GoldenJSON] = []
        for puzzle in chessMateInOne + chessMateInTwo {
            let plies = chessMateInOne.contains { $0.fen == puzzle.fen } ? 1 : 3
            cases.append(try Self.chessPuzzle(id: "mate\(plies)-\(cases.count)", label: puzzle.label, fen: puzzle.fen, depth: plies == 1 ? 4 : 5,
                                              expect: puzzle.mates.sorted(), mateInPlies: plies))
        }
        for puzzle in chessFreeQueenPuzzles {
            cases.append(try Self.chessPuzzle(id: "queen-\(cases.count)", label: puzzle.label, fen: puzzle.fen, depth: 4, expect: [puzzle.capture]))
        }
        cases.append(try Self.chessPuzzle(id: "quiescence", label: "깊이 1 에서 지켜지는 폰을 퀸으로 잡지 않는다",
                                          fen: "4k3/8/2p5/3p4/8/8/8/3QK3 w - - 0 1", depth: 1, reject: ["d1d5"], scoreAbove: 0))
        cases.append(try Self.chessPuzzle(id: "no-stalemate", label: "스테일메이트를 이기는 수로 착각하지 않는다",
                                          fen: "k7/8/1Q6/8/8/8/8/K7 w - - 0 1", depth: 5, reject: ["a1a2", "a1b1", "a1b2", "b6c7"], scoreAbove: 300))
        let winning = try #require(ChessPosition(fen: "7k/8/8/8/8/8/8/K1Q3R1 w - - 0 1"))
        let g1g2 = try #require(ChessMove(uci: "g1g2"))
        let winningKey = try #require(ChessRules.apply(g1g2, to: winning)).repetitionKey
        cases.append(try Self.chessPuzzle(id: "avoid-threefold", label: "이기는 판을 3회 반복으로 흘려보내지 않는다", fen: winning.fen, depth: 4,
                                          repetition: [winningKey: 2], reject: ["g1g2"], scoreAbove: 300))
        let losing = try #require(ChessPosition(fen: "7k/8/8/8/8/3q4/8/K3R3 w - - 0 1"))
        let e1e2 = try #require(ChessMove(uci: "e1e2"))
        let losingKey = try #require(ChessRules.apply(e1e2, to: losing)).repetitionKey
        cases.append(try Self.chessPuzzle(id: "take-threefold", label: "지는 판에서는 3회 반복(무승부)을 고른다", fen: losing.fen, depth: 5,
                                          repetition: [losingKey: 2], expect: ["e1e2"], scoreEquals: 0))
        cases.append(try Self.chessPuzzle(id: "take-threefold-blind", label: "장부가 없으면 지는 점수", fen: losing.fen, depth: 5, scoreBelow: 0))
        for (id, fen) in [("mated", "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3"), ("stalemated", "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")] {
            let position = try #require(ChessPosition(fen: fen))
            #expect(ChessAI.bestMove(position: position) == nil)
            cases.append(["id": .string(id), "label": "둘 수가 없다 → null", "fen": .string(fen), "depth": 3, "seed": .hex64(Self.chessSeed),
                          "repetition": [], "expectNone": true])
        }
        goldenEmit(GoldenFile(
            golden: "chess/ai-puzzles",
            equivalence: .set,
            swiftSources: Self.chessSources,
            spec: [
                "limits": "ChessAISearchLimits(timeBudget: 600초, maxDepth: depth, tieBreakSeed: seed). repetition 은 decide(repetitionCounts:) 에 넘기는 [반복 키, 횟수] 목록.",
                "set": "Kotlin decide 의 수가 expect 안(있으면) · reject 밖(있으면). mateInPlies 가 있으면 결정의 mateInPlies 가 그 값. scoreAbove/scoreBelow/scoreEquals 는 점수(두는 쪽 시점 센티폰) 조건. expectNone 이면 결정이 null.",
                "source": "과제는 Tests/checkTests/ChessAIEngineTests.swift(정답 집합은 그 파일이 ChessRules 전수 탐색으로 확인해 글자로 박았다). swiftMove·swiftScore 는 Swift 결과(참고 — 비트 대조는 chess/ai-trace).",
            ],
            cases: cases
        ))
    }

    // MARK: chess/ai-trace

    @Test("chess/ai-trace — 표 지문 + 국면별 decide(수 · 점수 · 깊이 · 노드) + 증분 Zobrist 수순")
    func chessAITrace() throws {
        var cases: [GoldenJSON] = []
        var pieces = GoldenFNV1a64()
        for value in ChessAITables.zobrist.pieces { pieces.add(value) }
        var rest = GoldenFNV1a64()
        for value in ChessAITables.zobrist.castling { rest.add(value) }
        for value in ChessAITables.zobrist.enPassant { rest.add(value) }
        rest.add(ChessAITables.zobrist.side)
        var squares = GoldenFNV1a64()
        for table in ChessAITables.midgame + ChessAITables.endgame { for value in table { squares.add(Int(value)) } }
        cases.append([
            "id": "tables",
            "zobristPieces": .string(pieces.hex),
            "zobristRest": .string(rest.hex),
            "zobristSide": .hex64(ChessAITables.zobrist.side),
            "squareTables": .string(squares.hex),
            "pieceValues": .array(ChessAIScore.piece.map(GoldenJSON.int)),
            "mate": .int(ChessAIScore.mate),
            "infinity": .int(ChessAIScore.infinity),
        ])

        var runs: [(String, String, Int, UInt64, [String: Int])] = []
        for (index, puzzle) in (chessMateInOne + chessMateInTwo).enumerated() {
            runs.append((String(format: "mate-%02d", index), puzzle.fen, chessMateInOne.contains { $0.fen == puzzle.fen } ? 4 : 5, Self.chessSeed, [:]))
        }
        for (index, puzzle) in chessFreeQueenPuzzles.enumerated() { runs.append(("queen-\(index)", puzzle.fen, 4, Self.chessSeed, [:])) }
        for (index, fen) in chessAITimingPositions.enumerated() {
            runs.append(("timing-\(index)-d3", fen, 3, Self.chessSeed, [:]))
            runs.append(("timing-\(index)-d4", fen, 4, Self.chessSeed, [:]))
        }
        runs.append(("seed-99", chessAITimingPositions[0], 4, 99, [:]))
        runs.append(("quiescence", "4k3/8/2p5/3p4/8/8/8/3QK3 w - - 0 1", 1, Self.chessSeed, [:]))
        runs.append(("no-stalemate", "k7/8/1Q6/8/8/8/8/K7 w - - 0 1", 5, Self.chessSeed, [:]))
        runs.append(("single-move", "7k/8/8/8/8/8/6q1/7K w - - 0 1", 3, Self.chessSeed, [:]))
        runs.append(("mated", "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3", 3, Self.chessSeed, [:]))
        let losing = try #require(ChessPosition(fen: "7k/8/8/8/8/3q4/8/K3R3 w - - 0 1"))
        let e1e2 = try #require(ChessMove(uci: "e1e2"))
        let losingKey = try #require(ChessRules.apply(e1e2, to: losing)).repetitionKey
        runs.append(("take-threefold", losing.fen, 5, Self.chessSeed, [losingKey: 2]))
        for (index, fen) in GoldenExportGamesBoardChess.walkFens(walks: 4, plies: 30, seed: 0xA1_2026_1028).enumerated() where index % 6 == 3 {
            runs.append((String(format: "walk-%03d", index), fen, 2, UInt64(index), [:]))
        }

        for (id, fen, depth, seed, repetition) in runs {
            let position = try #require(ChessPosition(fen: fen), "\(id)")
            let decision = ChessAI.decide(position: position, repetitionCounts: repetition,
                                          limits: ChessAISearchLimits(timeBudget: Self.budget, maxDepth: depth, tieBreakSeed: seed))
            if let decision { #expect(ChessRules.legalMoves(in: position).contains(decision.move), "\(id): 불법 수") }
            // 정적 평가(두는 쪽 시점 센티폰): 수가 같아도 평가식(칸 가치표·폰 구조·왕 안전·몰기)이 갈리면 여기서 잡힌다.
            let probeEngine = try #require(ChessEngine(position: position), "\(id)")
            let staticEval = ChessAISearch(engine: probeEngine, budget: Self.budget, isCancelled: { false }).evaluate()
            cases.append([
                "id": .string(id),
                "fen": .string(fen),
                "depth": .int(depth),
                "seed": .hex64(seed),
                "repetition": .array(repetition.sorted { $0.key < $1.key }.map { .array([.string($0.key), .int($0.value)]) }),
                "move": decision.map { .string($0.move.uci) } ?? .null,
                "score": decision.map { .int($0.score) } ?? .null,
                "completedDepth": decision.map { .int($0.depth) } ?? .null,
                "nodes": decision.map { .int($0.nodes) } ?? .null,
                "mateInPlies": decision?.mateInPlies.map(GoldenJSON.int) ?? .null,
                "eval": .int(staticEval),
            ])
        }

        // 증분 Zobrist: 수마다 makeMove 뒤 해시(= 전체 재계산 — 생성기가 단언한다).
        let lines: [(String, String, [String])] = [
            ("hash-ep-castle", ChessPosition.standard.fen, ["e2e4", "a7a6", "e4e5", "d7d5", "e5d6", "c7d6", "g1f3", "g8f6", "f1c4", "e7e6", "e1g1"]),
            ("hash-promo-castles", "4k2r/P7/8/8/8/8/8/R3K3 w Qk - 0 1", ["a7a8n", "e8g8", "e1c1"]),
            ("hash-black-ep", "rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", ["d4e3", "d2e3", "e7e5", "f1b5", "c7c6"]),
        ]
        for (id, fen, uci) in lines {
            let position = try #require(ChessPosition(fen: fen))
            let engine = try #require(ChessEngine(position: position))
            let search = ChessAISearch(engine: engine, budget: Self.budget, isCancelled: { false })
            var hashes: [GoldenJSON] = [.hex64(search.hash)]
            for text in uci {
                var probe = search.engine
                let parsed = try #require(ChessMove(uci: text))
                let candidate = probe.matchingLegalMove(parsed)
                let raw = try #require(candidate, "\(id): \(text) 불법")
                _ = search.makeMove(raw)
                #expect(search.hash == ChessAISearch.fullHash(search.engine), "\(id): \(text) 뒤 증분 해시가 어긋났다")
                hashes.append(.hex64(search.hash))
            }
            cases.append(["id": .string(id), "fen": .string(fen), "uci": .array(uci.map(GoldenJSON.string)), "hashes": .array(hashes)])
        }
        goldenEmit(GoldenFile(
            golden: "chess/ai-trace",
            equivalence: .bit,
            swiftSources: Self.chessSources,
            spec: [
                "tables": "Zobrist(SplitMix64 씨앗 0x6368657373414921 — 말·칸 16×64 → 캐슬링 16 → 앙파상 8 → 차례 1 순서로 뽑는다)과 칸 가치표(중반 6 · 끝내기 6, a1=0 칸 번호)를 FNV-1a 64 로 접은 값, 기물 가치, 메이트·무한 상수.",
                "decide": "ChessAI.decide(position:repetitionCounts:limits: 600초 · maxDepth: depth · tieBreakSeed: seed) — move(UCI|null) · score · completedDepth · nodes(틱 수) · mateInPlies · eval(새 ChessAISearch 의 evaluate(), 두는 쪽 시점). 반복 표는 [키, 횟수]. 동점 고르기는 Swift randomElement(using:) 알고리즘.",
                "hash": "ChessAISearch 를 세우고 수마다 makeMove 한 뒤의 해시(첫 값은 시작 국면). 증분 갱신 = 전체 재계산.",
            ],
            cases: cases
        ))
    }

    // MARK: - 도우미

    /// VCF 예산 국면(id, serverString, 예산을 쓰는 공격자 1=흑 · 2=흰). 닫힌 3 덩어리 8~9개를 흩어 놓은 판 — Kotlin 탐색(씨앗 SplitMix64)으로 찾았다.
    static let budgetBoards: [(String, String, Int)] = [
        ("budget-root", "..wwwb.....b..............w.b............w.w............w.w....wwwb......w...................wwwb............................b.............w....w........w....w....w...w....w.....w.......b......w..............b................", 2),
        ("budget-opponent", "...........bbbw.....w...............b...........b...b...........b...b...b.......b......b...b....w.....b...b..........w...b..............w........b...............b.......b.......b.....b.........w...b.............w......bbbw...", 1),
        ("budget-defense", "w......w.......b.....b........b....b.........b...b.....bbbw..............................w..........w..b...bbbw...b..b..........b..b....w.....b......w.b............b.b............b.b............b.....................bbbw.....", 1),
    ]

    static func gomokuFixture() throws -> [String: Any] {
        let data = try Data(contentsOf: GoldenRepo.url("Tests/checkTests/Fixtures/gomoku-ai-puzzles.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func board(black: [String], white: [String]) throws -> GomokuBoard {
        var board = GomokuBoard()
        for (list, color) in [(black, GomokuColor.black), (white, GomokuColor.white)] {
            for notation in list {
                let point = try #require(GomokuPoint(notation: notation), "좌표 \(notation)")
                board[point] = color
            }
        }
        return board
    }

    /// 돌 반경 2 안의 합법 빈칸(행→열 순서). 빈 판이면 H8.
    static func nearLegal(_ board: GomokuBoard, _ color: GomokuColor) -> [GomokuPoint] {
        guard board.stoneCount > 0 else { return [GomokuPoint(x: 7, y: 7)!] }
        var out: [GomokuPoint] = []
        for y in 0..<15 {
            for x in 0..<15 {
                let point = GomokuPoint(x: x, y: y)!
                guard board[point] == nil else { continue }
                var near = false
                for dy in -2...2 where !near {
                    for dx in -2...2 where !near {
                        if let q = GomokuPoint(x: x + dx, y: y + dy), board[q] != nil { near = true }
                    }
                }
                guard near else { continue }
                let verdict = GomokuRules.judge(board: board, point: point, color: color)
                if verdict == .legal || verdict == .win { out.append(point) }
            }
        }
        return out
    }

    /// 엔진 대 엔진으로 `plies` 수를 둔다. 5목을 만든 색(없으면 nil).
    static func playOut(_ start: GomokuBoard, toMove: GomokuColor, plies: Int, limits: GomokuAISearchLimits) -> (winner: GomokuColor?, moves: [String]) {
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
            guard verdict == .legal || verdict == .win else { return (nil, moves) }
            board[move] = color
            moves.append(move.notation)
            if verdict == .win { return (color, moves) }
            color = color.opponent
        }
        return (nil, moves)
    }

    static func state(_ game: GomokuAIGame, t0: Date, now: Date) -> GoldenJSON {
        let autos = game.autoPoints.sorted { ($0.y, $0.x) < ($1.y, $1.x) }.map { GoldenJSON.string($0.notation) }
        return [
            "board": .string(game.board.serverString),
            "moveCount": .int(game.moveCount),
            "lastMove": game.lastMove.map { .string($0.notation) } ?? .null,
            "turn": game.turn.map { .string($0.rawValue) } ?? .null,
            "deadlineBits": game.deadline.map { .bits($0.timeIntervalSince(t0)) } ?? .null,
            "pausedBits": game.pausedRemaining.map { .bits($0) } ?? .null,
            "finished": .bool(game.isFinished),
            "outcome": game.outcome.map { .string("\($0)") } ?? .null,
            "endReason": game.endReason.map { .string($0.rawValue) } ?? .null,
            "autoPoints": .array(autos),
            "lastAuto": .bool(game.lastMoveWasAuto),
            "blackPassed": .bool(game.blackPassed),
            "streak": .int(game.humanAutoStreak),
            "expired": .bool(game.isHumanClockExpired(now: now)),
            "watches": .bool(GomokuTurnWarning.watchesMyClock(game.matchState())),
        ]
    }

    static func chessPuzzle(id: String, label: String, fen: String, depth: Int, repetition: [String: Int] = [:],
                            expect: [String]? = nil, reject: [String]? = nil, mateInPlies: Int? = nil,
                            scoreAbove: Int? = nil, scoreBelow: Int? = nil, scoreEquals: Int? = nil) throws -> GoldenJSON {
        let position = try #require(ChessPosition(fen: fen), "\(id)")
        let decision = try #require(ChessAI.decide(position: position, repetitionCounts: repetition,
                                                   limits: ChessAISearchLimits(timeBudget: budget, maxDepth: depth, tieBreakSeed: chessSeed)), "\(id)")
        if let expect { #expect(expect.contains(decision.move.uci), "\(id): \(decision.move.uci) ∉ \(expect)") }
        if let reject { #expect(!reject.contains(decision.move.uci), "\(id): \(decision.move.uci) ∈ reject") }
        if let mateInPlies { #expect(decision.mateInPlies == mateInPlies, "\(id): mateInPlies \(String(describing: decision.mateInPlies))") }
        if let scoreAbove { #expect(decision.score > scoreAbove, "\(id): 점수 \(decision.score)") }
        if let scoreBelow { #expect(decision.score < scoreBelow, "\(id): 점수 \(decision.score)") }
        if let scoreEquals { #expect(decision.score == scoreEquals, "\(id): 점수 \(decision.score)") }
        return [
            "id": .string(id),
            "label": .string(label),
            "fen": .string(fen),
            "depth": .int(depth),
            "seed": .hex64(chessSeed),
            "repetition": .array(repetition.sorted { $0.key < $1.key }.map { .array([.string($0.key), .int($0.value)]) }),
            "expect": expect.map { .array($0.map(GoldenJSON.string)) } ?? .null,
            "reject": reject.map { .array($0.map(GoldenJSON.string)) } ?? .null,
            "mateInPlies": mateInPlies.map(GoldenJSON.int) ?? .null,
            "scoreAbove": scoreAbove.map(GoldenJSON.int) ?? .null,
            "scoreBelow": scoreBelow.map(GoldenJSON.int) ?? .null,
            "scoreEquals": scoreEquals.map(GoldenJSON.int) ?? .null,
            "swiftMove": .string(decision.move.uci),
            "swiftScore": .int(decision.score),
        ]
    }
}
