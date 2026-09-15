import Foundation
import Testing
@testable import check

// v0.3.27 — 렌주 판정(GomokuRules) 계약.
//
// 기대값을 손으로 적지 않는다. 규범은 조사 확정본(rules.final.md)이고, 기대값은 코퍼스
// `Fixtures/renju-cases.json`(cases.final.json 사본, 91개)이 **판정과 노드 수까지** 들고 있다.
//
// 노드 수를 같이 보는 이유: 판정 결과는 가지치기·평가 순서와 무관하게 같을 수 있지만 노드 수는 순서에 따라
// 달라진다. 노드 예산(10,000)의 초과 여부가 앱과 서버(gomoku_judge)에서 갈리면 앱은 둘 수 있다고 보여 주는
// 자리를 서버가 거절한다 — 그래서 §4.2 의 순서·계수를 코퍼스의 nodes 로 못 박는다.

private struct RenjuCase: Decodable {
    let id: String
    let black: [String]
    let white: [String]
    let player: String
    let point: String
    let expected: String
    let nodes: Int?
    let nodeBudget: Int?
}

private func loadCorpus() throws -> [RenjuCase] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/renju-cases.json")
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode([RenjuCase].self, from: Data(contentsOf: url))
}

/// 코퍼스 입력을 앱 타입으로 옮긴다. 입력 검증(§1.2)은 앱 타입의 실패 가능 생성자가 한다 —
/// 정규형 아닌 좌표·중복·흑백 겹침·player 철자는 여기서 nil 이 되어야 한다.
private func corpusBoard(of c: RenjuCase) -> (GomokuBoard, GomokuColor, GomokuPoint)? {
    guard let color = GomokuColor(rawValue: c.player) else { return nil }
    var board = GomokuBoard()
    for (list, stone) in [(c.black, GomokuColor.black), (c.white, GomokuColor.white)] {
        for notation in list {
            guard let point = GomokuPoint(notation: notation), board[point] == nil else { return nil }
            board[point] = stone
        }
    }
    guard let point = GomokuPoint(notation: c.point) else { return nil }
    return (board, color, point)
}

private func label(_ judgement: GomokuJudgement) -> String {
    switch judgement {
    case .legal: return "legal"
    case .win: return "win"
    case .forbidden(.budget): return "error:budget-exceeded"
    case .forbidden(let reason): return reason.rawValue
    case .occupied, .outOfRange: return "error:invalid-input"
    }
}

/// 결정적 난수(SplitMix64). 실패한 국면을 다시 만들 수 있어야 한다.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 국면 생성기 넷(균일·빽빽한 상자·군집 성장·중앙 쏠림). 빽빽한 상자는 재귀 3-3 을 부르려고 흑을 많이 둔다.
private func randomBoard(_ rng: inout SplitMix64, index: Int) -> GomokuBoard {
    var board = GomokuBoard()
    var stones: [(Int, Int)] = []
    func place(_ x: Int, _ y: Int, _ color: GomokuColor) {
        guard let point = GomokuPoint(x: x, y: y), board[point] == nil else { return }
        board[point] = color
        stones.append((x, y))
    }
    switch index % 4 {
    case 0:
        let count = Int.random(in: 8...110, using: &rng)
        let bias = Double.random(in: 0.5...0.65, using: &rng)
        var guardCount = 0
        while stones.count < count, guardCount < 5_000 {
            guardCount += 1
            place(Int.random(in: 0..<15, using: &rng), Int.random(in: 0..<15, using: &rng),
                  Double.random(in: 0..<1, using: &rng) < bias ? .black : .white)
        }
    case 1:
        let size = Int.random(in: 7...9, using: &rng)
        let ox = Int.random(in: 0...(15 - size), using: &rng)
        let oy = Int.random(in: 0...(15 - size), using: &rng)
        let fill = Double.random(in: 0.35...0.7, using: &rng)
        let bias = Double.random(in: 0.55...0.8, using: &rng)
        for y in oy..<(oy + size) {
            for x in ox..<(ox + size) where Double.random(in: 0..<1, using: &rng) < fill {
                place(x, y, Double.random(in: 0..<1, using: &rng) < bias ? .black : .white)
            }
        }
    case 2:
        let count = Int.random(in: 20...70, using: &rng)
        place(Int.random(in: 0..<15, using: &rng), Int.random(in: 0..<15, using: &rng), .black)
        var guardCount = 0
        while stones.count < count, guardCount < 10_000 {
            guardCount += 1
            let base = stones[Int.random(in: 0..<stones.count, using: &rng)]
            place(base.0 + Int.random(in: -2...2, using: &rng), base.1 + Int.random(in: -2...2, using: &rng),
                  Double.random(in: 0..<1, using: &rng) < 0.62 ? .black : .white)
        }
    default:
        let count = Int.random(in: 15...90, using: &rng)
        var guardCount = 0
        while stones.count < count, guardCount < 5_000 {
            guardCount += 1
            // 균일 셋의 합 = 가운데로 쏠린 분포.
            let x = (0..<3).reduce(0) { acc, _ in acc + Int.random(in: 0...4, using: &rng) } + 1
            let y = (0..<3).reduce(0) { acc, _ in acc + Int.random(in: 0...4, using: &rng) } + 1
            place(x, y, Double.random(in: 0..<1, using: &rng) < 0.6 ? .black : .white)
        }
    }
    return board
}

// MARK: - 코퍼스

@Test
func 렌주_코퍼스_91개가_판정과_노드수까지_전부_맞는다() throws {
    let corpus = try loadCorpus()
    #expect(corpus.count == 91, "코퍼스 사본이 cases.final.json 과 다르다: \(corpus.count)개")

    var nodeChecks = 0
    for c in corpus {
        guard let parsed = corpusBoard(of: c) else {
            #expect(c.expected == "error:invalid-input", "\(c.id): 입력 검증에서 막혔는데 기대값은 \(c.expected)")
            continue
        }
        let (board, color, point) = parsed
        let budget = c.nodeBudget ?? GomokuRules.nodeBudget
        let (judgement, nodes) = GomokuRules.judgeCounting(board: board, point: point, color: color, budget: budget)
        #expect(label(judgement) == c.expected, "\(c.id): 판정 \(label(judgement)) ≠ 기대 \(c.expected)")
        if let expectedNodes = c.nodes {
            nodeChecks += 1
            #expect(nodes == expectedNodes, "\(c.id): 노드 \(nodes) ≠ 기대 \(expectedNodes) — §4.2 순서·계수가 어긋났다")
        }
    }
    // 노드 단언이 장식이 아님을 센다 — 흑 케이스 대부분이 nodes 를 들고 있다.
    #expect(nodeChecks >= 60, "노드 수를 비교한 케이스가 \(nodeChecks)개뿐이다")
}

@Test
func 기본_예산_judge_는_코퍼스_예산_판정과_같다() throws {
    for c in try loadCorpus() where c.nodeBudget == nil && !c.expected.hasPrefix("error") {
        guard let parsed = corpusBoard(of: c) else { continue }
        let (board, color, point) = parsed
        #expect(GomokuRules.judge(board: board, point: point, color: color)
                == GomokuRules.judgeCounting(board: board, point: point, color: color, budget: nil).judgement,
                "\(c.id)")
    }
    #expect(GomokuRules.nodeBudget == 10_000)
}

@Test
func 노드_예산_경계는_B01_B02_그대로다() throws {
    let corpus = try loadCorpus()
    let d01 = try #require(corpus.first { $0.id == "D01" })
    let (board, _, point) = try #require(corpusBoard(of: d01))
    // D01 은 8단 재귀, 노드 31. 예산 30 이면 초과(= 둘 수 없음), 31 이면 정상 판정.
    #expect(GomokuRules.judgeCounting(board: board, point: point, color: .black, budget: 30).judgement == .forbidden(.budget))
    let exact = GomokuRules.judgeCounting(board: board, point: point, color: .black, budget: 31)
    #expect(exact.judgement == .forbidden(.doubleThree))
    #expect(exact.nodes == 31)
    #expect(GomokuRules.judge(board: board, point: point, color: .black) == .forbidden(.doubleThree))
}

// MARK: - 입력 타입

@Test
func 좌표는_정규형만_받고_225칸이_왕복한다() {
    #expect(GomokuPoint(notation: "H8") == GomokuPoint(x: 7, y: 7))
    #expect(GomokuPoint(notation: "A1") == GomokuPoint(x: 0, y: 0))
    #expect(GomokuPoint(notation: "O15") == GomokuPoint(x: 14, y: 14))
    #expect(GomokuPoint(notation: "J10") == GomokuPoint(x: 9, y: 9))
    for bad in ["h8", "H08", " H8", "H8 ", "H8\n", "P8", "H16", "H0", "H", "", "8H", "H１", "Ｈ8", "HH8", "H100"] {
        #expect(GomokuPoint(notation: bad) == nil, "\(bad.debugDescription) 는 정규형이 아니다")
    }
    #expect(GomokuPoint(x: -1, y: 0) == nil)
    #expect(GomokuPoint(x: 0, y: 15) == nil)
    for y in 0..<15 {
        for x in 0..<15 {
            let point = GomokuPoint(x: x, y: y)!
            #expect(GomokuPoint(notation: point.notation) == point)
        }
    }
}

@Test
func 서버_판_문자열은_y곱15더하기x_로_왕복한다() {
    var board = GomokuBoard()
    #expect(board.serverString == String(repeating: ".", count: 225))
    board[GomokuPoint(x: 7, y: 7)!] = .black        // H8 → 7*15+7 = 112
    board[GomokuPoint(x: 1, y: 0)!] = .white        // B1 → 1
    board[GomokuPoint(x: 0, y: 14)!] = .black       // A15 → 210
    let text = Array(board.serverString)
    #expect(text[112] == "b")
    #expect(text[1] == "w")
    #expect(text[210] == "b")
    #expect(board.stoneCount == 3)
    #expect(GomokuBoard(serverString: board.serverString) == board)
    #expect(GomokuBoard(serverString: String(repeating: ".", count: 224)) == nil)
    #expect(GomokuBoard(serverString: String(repeating: ".", count: 224) + "B") == nil)
    board[GomokuPoint(x: 7, y: 7)!] = nil
    #expect(board.stoneCount == 2)
    // 이미 돌이 있는 자리는 판정이 아니라 입력 오류다(노드를 세지 않는다).
    #expect(GomokuRules.judgeCounting(board: board, point: GomokuPoint(x: 1, y: 0)!, color: .black, budget: 10).nodes == 0)
    #expect(GomokuRules.judge(board: board, point: GomokuPoint(x: 1, y: 0)!, color: .white) == .occupied)
}

@Test
func 서버_금수_사유는_어휘_두_모양을_모두_읽는다() {
    #expect(GomokuForbiddenReason(serverReason: "double-three") == .doubleThree)
    #expect(GomokuForbiddenReason(serverReason: "forbidden-double-four") == .doubleFour)
    #expect(GomokuForbiddenReason(serverReason: "overline") == .overline)
    #expect(GomokuForbiddenReason(serverReason: "budget") == .budget)
    #expect(GomokuForbiddenReason(serverReason: "double_three") == .doubleThree)
    #expect(GomokuForbiddenReason(serverReason: "nonsense") == nil)
    #expect(GomokuForbiddenReason(serverReason: nil) == nil)
}

// MARK: - 금수 표시 = judge

@Test
func 금수_표시_칸은_judge_와_칸마다_같다() throws {
    var boards: [GomokuBoard] = []
    for c in try loadCorpus() {
        if let parsed = corpusBoard(of: c) { boards.append(parsed.0) }
    }
    var rng = SplitMix64(state: 0x0327)
    for index in 0..<300 { boards.append(randomBoard(&rng, index: index)) }

    var mismatches: [String] = []
    var forbiddenSeen = 0
    for (index, board) in boards.enumerated() {
        let shown = GomokuRules.forbiddenPoints(board: board)
        var expected: [GomokuPoint: GomokuForbiddenReason] = [:]
        for y in 0..<15 {
            for x in 0..<15 {
                let point = GomokuPoint(x: x, y: y)!
                guard board[point] == nil else { continue }
                if case .forbidden(let reason) = GomokuRules.judge(board: board, point: point, color: .black) {
                    expected[point] = reason
                }
            }
        }
        forbiddenSeen += expected.count
        if shown != expected, mismatches.count < 10 { mismatches.append("board#\(index)") }
    }
    #expect(mismatches.isEmpty, "금수 표시와 judge 가 갈린 판: \(mismatches)")
    #expect(forbiddenSeen > 0, "금수 칸이 한 번도 안 나왔다 — 비교가 공허하다")
}

// MARK: - 무작위 국면

@Test
func 무작위_국면_이천개가_예외없이_끝나고_결정적이다() {
    var rng = SplitMix64(state: 20_260_916)
    var problems: [String] = []
    var blackQueries = 0
    var whiteQueries = 0
    var maxNodes = 0
    var seen: [String: Int] = [:]
    for index in 0..<2_000 {
        let board = randomBoard(&rng, index: index)
        for y in 0..<15 {
            for x in 0..<15 {
                let point = GomokuPoint(x: x, y: y)!
                guard board[point] == nil else { continue }
                let (black, nodes) = GomokuRules.judgeCounting(
                    board: board, point: point, color: .black, budget: GomokuRules.nodeBudget)
                blackQueries += 1
                maxNodes = max(maxNodes, nodes)
                seen[label(black), default: 0] += 1
                if black == .occupied || black == .outOfRange || nodes < 1 || nodes > GomokuRules.nodeBudget + 1 {
                    if problems.count < 10 { problems.append("#\(index) \(point.notation) 흑 \(black) nodes=\(nodes)") }
                }
                let white = GomokuRules.judge(board: board, point: point, color: .white)
                whiteQueries += 1
                if white != .legal && white != .win, problems.count < 10 {
                    problems.append("#\(index) \(point.notation) 백에게 금수 \(white)")
                }
                if index % 50 == 0, problems.count < 10 {
                    let again = GomokuRules.judgeCounting(
                        board: board, point: point, color: .black, budget: GomokuRules.nodeBudget)
                    if again.judgement != black || again.nodes != nodes {
                        problems.append("#\(index) \(point.notation) 같은 입력에 다른 판정")
                    }
                }
            }
        }
    }
    #expect(problems.isEmpty, "\(problems)")
    #expect(blackQueries > 250_000, "질의 수가 너무 적다: \(blackQueries)")
    #expect(whiteQueries == blackQueries)
    // 생성기가 금수 셋과 승리를 전부 실제로 만들어야 이 테스트가 재귀·장목·4-4 경로를 지난다.
    for key in ["legal", "win", "forbidden-double-three", "forbidden-double-four", "forbidden-overline"] {
        #expect((seen[key] ?? 0) > 0, "무작위 국면에서 \(key) 가 한 번도 안 나왔다: \(seen)")
    }
    print("GOMOKU-RANDOM| black=\(blackQueries) white=\(whiteQueries) maxNodes=\(maxNodes) verdicts=\(seen)")
}

// MARK: - 참조 구현 교차 검증 (외부 파일이 있을 때만)

/// `CHECK_GOMOKU_CROSSCHECK=/경로/a.json:/경로/b.json` — 참조 구현(reference.py)이 판정한 무작위 국면 파일.
/// 형식: {"positions":[{"board":"<225자>","black":[[x,y,판정,노드|null],…],"white":[[x,y,판정],…]}]}.
/// 파일이 저장소 밖(스크래치)에 있으므로 게이트가 꺼진 실행은 SKIPPED 로 보고된다(통과가 아니다).
private enum GomokuCrosscheckEnv {
    static let name = "CHECK_GOMOKU_CROSSCHECK"
    static var paths: [String] {
        (ProcessInfo.processInfo.environment[name] ?? "").split(separator: ":").map(String.init).filter { !$0.isEmpty }
    }
}

@Test(.enabled(if: !GomokuCrosscheckEnv.paths.isEmpty))
func 참조구현과_무작위_국면_판정이_노드수까지_전부_같다() throws {
    var positions = 0
    var blackChecked = 0
    var whiteChecked = 0
    var nodeChecked = 0
    var mismatches: [String] = []
    func note(_ text: String) { if mismatches.count < 20 { mismatches.append(text) } else { mismatches.append("…") } }

    for path in GomokuCrosscheckEnv.paths {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(root["positions"] as? [[String: Any]])
        for entry in entries {
            let text = try #require(entry["board"] as? String)
            let board = try #require(GomokuBoard(serverString: text))
            positions += 1
            let shown = GomokuRules.forbiddenPoints(board: board)
            var expectedShown: [GomokuPoint: GomokuForbiddenReason] = [:]
            for row in (entry["black"] as? [[Any]]) ?? [] {
                guard let x = row[0] as? Int, let y = row[1] as? Int, let verdict = row[2] as? String,
                      let point = GomokuPoint(x: x, y: y) else { note("\(path): 행 해석 실패 \(row)"); continue }
                let (judgement, nodes) = GomokuRules.judgeCounting(
                    board: board, point: point, color: .black, budget: GomokuRules.nodeBudget)
                blackChecked += 1
                let mine: String
                if case .forbidden(let reason) = judgement { mine = reason.rawValue } else { mine = label(judgement) }
                if mine != verdict { note("흑 \(point.notation) 앱=\(mine) 참조=\(verdict) board=\(text)") }
                if let expectedNodes = row[3] as? Int {
                    nodeChecked += 1
                    if expectedNodes != nodes { note("흑 \(point.notation) 노드 앱=\(nodes) 참조=\(expectedNodes) board=\(text)") }
                }
                if let reason = GomokuForbiddenReason(rawValue: verdict) { expectedShown[point] = reason }
            }
            if shown != expectedShown { note("금수 표시 불일치 board=\(text)") }
            for row in (entry["white"] as? [[Any]]) ?? [] {
                guard let x = row[0] as? Int, let y = row[1] as? Int, let verdict = row[2] as? String,
                      let point = GomokuPoint(x: x, y: y) else { note("\(path): 행 해석 실패 \(row)"); continue }
                whiteChecked += 1
                let mine = label(GomokuRules.judge(board: board, point: point, color: .white))
                if mine != verdict { note("백 \(point.notation) 앱=\(mine) 참조=\(verdict) board=\(text)") }
            }
        }
    }
    print("GOMOKU-CROSSCHECK| files=\(GomokuCrosscheckEnv.paths.count) positions=\(positions) "
          + "black=\(blackChecked) white=\(whiteChecked) nodes=\(nodeChecked) mismatches=\(mismatches.count)")
    #expect(positions > 0)
    #expect(blackChecked > 0 && whiteChecked > 0)
    #expect(mismatches.isEmpty, "\(mismatches)")
}
