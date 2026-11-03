import Foundation
import Testing
@testable import CheckCore

// 아잉 뒤집기 규칙(`ReversiRules`) — **판정 코퍼스 hand 48 의 합격선**.
//
// 기대값은 이 파일에 없다. `Fixtures/reversi/cases.json`(FLIP/research/cases.json 을 바이트 그대로 복사, schema reversi-cases/1)
// 한 곳에 있고, 서버 마이그레이션의 판정 함수와 파이썬 참조 구현이 **같은 파일**을 정답으로 쓴다. 셋 중 하나가 갈리면 그쪽이 틀렸다.
// 사례는 id 로 집는다 — 배열 인덱스로 집으면 코퍼스 줄 순서만 바뀌어도 "C04" 가 조용히 다른 판을 재게 된다.
//
// 여기서 재는 것: hand 의 kind 셋(legal 6 · move 33 · score 9)을 전부 · 판 끝 1차원 넘김(C04~C07)을 넘김 구현과 갈라서 ·
// 시작 흑 네 수의 불변식 · 비트보드 = 2차원 걷기(무작위 대국 차분) · 좌표 표기.

// MARK: - 코퍼스 픽스처(다른 Reversi*Tests 도 같이 쓴다)

struct ReversiCorpus: Decodable {
    let schema: String
    let perft: Perft
    let hand: [Hand]
    let streak: [Streak]
    let wthorSample: [Game]

    struct Perft: Decodable {
        let start: String
        let toMove: String
        let values: [String: Depth]
        let shortestGame: Shortest
    }

    struct Depth: Decodable {
        let plyPass: Int
        let known: Int
    }

    struct Shortest: Decodable {
        let moves: String
        let finalBoard: String
        let discs: Counts
        let score: Pair
        let result: String
        let end: String
    }

    struct Counts: Decodable, Equatable {
        let black: Int
        let white: Int
        let empty: Int
    }

    struct Pair: Decodable, Equatable {
        let black: Int
        let white: Int
    }

    struct Score: Decodable, Equatable {
        let black: Int
        let white: Int
        let result: String
    }

    struct Hand: Decodable {
        let id: String
        let kind: String
        let title: String
        let board: String
        let color: String?
        let idx: Int?
        let coord: String?
        let expected: Expected
    }

    /// kind 마다 쓰는 칸이 다르다(legal: legal_moves… · move: legal·flipped… · score: over·score…). 없는 칸은 nil.
    struct Expected: Decodable {
        let legalMoves: [Int]?
        let opponentLegalMoves: [Int]?
        let resolution: String?
        let legal: Bool?
        let reason: String?
        let flipped: [Int]?
        let boardAfter: String?
        let next: String?
        let passed: Bool?
        let over: Bool?
        let discs: Counts?
        let score: Score?
        let end: String?
    }

    struct Streak: Decodable {
        let id: String
        let title: String
        let events: [[Token]]
        let expected: StreakExpected
    }

    /// 사건 한 줄 `["auto", "black"]` · `["auto", "white", true]`(세 번째 = 그 수로 판이 자연히 끝남).
    enum Token: Decodable, Equatable {
        case text(String)
        case flag(Bool)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let flag = try? container.decode(Bool.self) {
                self = .flag(flag)
            } else {
                self = .text(try container.decode(String.self))
            }
        }

        var text: String? { if case .text(let value) = self { return value } else { return nil } }
    }

    struct StreakExpected: Decodable {
        let streak: [String: Int]
        let abandoned: String?
        let atEvent: Int?
        let result: String?
        let endReason: String?
    }

    struct Game: Decodable {
        let id: String
        let pickedFor: String
        let moves: String
        let plies: Int
        let passesBefore: [Int]
        let finalBoard: String
        let discs: Counts
        let score: Pair
        let result: String
        let end: String
        let officialBlackScore: Int
    }

    func hand(_ id: String) throws -> Hand {
        guard let found = hand.first(where: { $0.id == id }) else {
            throw ReversiFixtureError("cases.json 에 사례 \(id) 가 없다 — 조용히 건너뛰면 그 자리가 아무것도 안 재면서 초록이 된다")
        }
        return found
    }
}

enum ReversiCorpusFile {
    /// 매번 읽는다(수 ms). 전역 캐시를 두면 그 캐시가 또 하나의 상태가 된다.
    static func load() throws -> ReversiCorpus {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/reversi/cases.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ReversiFixtureError("코퍼스가 없다: \(url.path) — 정답지의 집이 하나뿐이라 이게 없으면 잴 것이 없다")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ReversiCorpus.self, from: Data(contentsOf: url))
    }

    static func board(_ text: String, _ label: String) throws -> ReversiBoard {
        guard let board = ReversiBoard(string: text) else {
            throw ReversiFixtureError("\(label): 판 문자열을 못 읽었다 — \(text)")
        }
        return board
    }

    static func color(_ text: String?, _ label: String) throws -> ReversiColor {
        guard let text, let color = ReversiColor(rawValue: text) else {
            throw ReversiFixtureError("\(label): 색을 못 읽었다 — \(String(describing: text))")
        }
        return color
    }

    /// "f5f6e6…" → [37, 45, …].
    static func indices(_ moves: String, _ label: String) throws -> [Int] {
        let chars = Array(moves)
        guard chars.count % 2 == 0 else { throw ReversiFixtureError("\(label): 수 목록 길이가 홀수다") }
        return try stride(from: 0, to: chars.count, by: 2).map { offset in
            let coord = String(chars[offset..<offset + 2])
            guard let point = ReversiPoint(coord: coord) else { throw ReversiFixtureError("\(label): 좌표 \(coord) 를 못 읽었다") }
            return point.idx
        }
    }
}

struct ReversiFixtureError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

// MARK: - 시험

@Suite("아잉 뒤집기 규칙 — 판정 코퍼스")
struct ReversiRulesTests {
    // 없으면: 누가 코퍼스에서 사례를 지우거나 kind 를 바꿔도 아래 반복 시험들은 남은 것만 돌고 초록이다.
    @Test("코퍼스 모양 — schema · hand 48(legal 6 · move 33 · score 9) · streak 5 · 기보 200 · perft 1~10")
    func corpusShapeIsIntact() throws {
        let corpus = try ReversiCorpusFile.load()
        #expect(corpus.schema == "reversi-cases/1")
        #expect(corpus.hand.count == 48)
        #expect(Set(corpus.hand.map(\.id)).count == 48, "사례 id 가 겹친다")
        #expect(corpus.hand.filter { $0.kind == "legal" }.count == 6)
        #expect(corpus.hand.filter { $0.kind == "move" }.count == 33)
        #expect(corpus.hand.filter { $0.kind == "score" }.count == 9)
        #expect(corpus.streak.map(\.id) == ["S01", "S02", "S03", "S04", "S05"])
        #expect(corpus.wthorSample.count == 200)
        #expect(Set(corpus.perft.values.keys) == Set((1...10).map(String.init)))
        #expect(corpus.perft.start == ReversiBoard.start.string)
        #expect(corpus.perft.toMove == "black")
    }

    // 없으면: 합법 수 목록이 색을 뒤바꾸거나(A02) 빈 목록을 잘못 내도(E02·E05 의 패스·끝 판단) 착수 시험만으로는 안 드러난다.
    @Test("legal 사례 6 — 합법 수 · 상대 합법 수 · 차례 판단(move/pass/over)")
    func legalCasesMatch() throws {
        let cases = try ReversiCorpusFile.load().hand.filter { $0.kind == "legal" }
        #expect(cases.count == 6)
        for item in cases {
            let board = try ReversiCorpusFile.board(item.board, item.id)
            let color = try ReversiCorpusFile.color(item.color, item.id)
            let mine = ReversiRules.legalMoves(board, color: color)
            let theirs = ReversiRules.legalMoves(board, color: color.opponent)
            #expect(mine == item.expected.legalMoves, "\(item.id) \(item.title)")
            #expect(theirs == item.expected.opponentLegalMoves, "\(item.id) 상대 합법 수")
            #expect(ReversiRules.hasLegalMove(board, color: color) == !mine.isEmpty, "\(item.id)")
            let resolution = !mine.isEmpty ? "move" : (!theirs.isEmpty ? "pass" : "over")
            #expect(resolution == item.expected.resolution, "\(item.id) 차례 판단")
            #expect((ReversiRules.endKind(board) != nil) == (resolution == "over"), "\(item.id) 끝 판단")
        }
    }

    // 없으면: 뒤집기·다음 차례·자동 패스·끝 사유·WOF 점수 가운데 하나가 틀려도 다른 갈래(서버·화면)가 먼저 밟을 때까지 모른다.
    @Test("move 사례 33 — play 결과 전부(뒤집힌 칸 · 판 · 다음 차례 · 패스 · 끝 · 돌 수 · 점수) 또는 불법 까닭")
    func moveCasesMatch() throws {
        let cases = try ReversiCorpusFile.load().hand.filter { $0.kind == "move" }
        var legalCount = 0
        var illegalCount = 0
        for item in cases {
            let board = try ReversiCorpusFile.board(item.board, item.id)
            let color = try ReversiCorpusFile.color(item.color, item.id)
            let idx = try #require(item.idx, "\(item.id): idx 가 없다")
            let expected = item.expected
            switch ReversiRules.play(board, color: color, idx: idx) {
            case .success(let outcome):
                legalCount += 1
                #expect(expected.legal == true, "\(item.id) \(item.title): 코퍼스는 불법(\(expected.reason ?? "?"))인데 두어졌다")
                #expect(outcome.flipped == expected.flipped, "\(item.id) 뒤집힌 칸")
                #expect(ReversiRules.flips(board, color: color, idx: idx) == expected.flipped, "\(item.id) flips")
                #expect(outcome.board.string == expected.boardAfter, "\(item.id) 둔 뒤 판")
                #expect(outcome.next?.rawValue == expected.next, "\(item.id) 다음 차례")
                #expect(outcome.passed == expected.passed, "\(item.id) 자동 패스")
                #expect(outcome.isOver == expected.over, "\(item.id) 끝")
                #expect(outcome.counts == expected.discs.map { ReversiCounts(black: $0.black, white: $0.white, empty: $0.empty) }, "\(item.id) 돌 수")
                #expect(outcome.score.map { ReversiCorpus.Score(black: $0.black, white: $0.white, result: $0.result.rawValue) } == expected.score, "\(item.id) 점수")
                #expect(outcome.end?.rawValue == expected.end, "\(item.id) 끝 사유")
                // 같은 판정을 낱개 함수로 다시 — play 안에서만 맞고 낱개가 갈리면 서버 쌍둥이와 대조할 때 어긋난다.
                let turn = ReversiRules.nextTurn(after: outcome.board, mover: color)
                #expect(turn.next == outcome.next && turn.passed == outcome.passed, "\(item.id) nextTurn")
                #expect(ReversiRules.endKind(outcome.board) == outcome.end, "\(item.id) endKind")
                #expect(ReversiRules.score(outcome.board) == outcome.score, "\(item.id) score")
            case .failure(let reason):
                illegalCount += 1
                #expect(expected.legal == false, "\(item.id) \(item.title): 코퍼스는 합법인데 \(reason.rawValue) 로 막혔다")
                #expect(reason.rawValue == expected.reason, "\(item.id) 불법 까닭")
                #expect(expected.boardAfter == item.board, "\(item.id): 코퍼스가 불법 수의 판을 바꿔 적었다")
                #expect(ReversiRules.flips(board, color: color, idx: idx).isEmpty, "\(item.id) 불법 칸에 뒤집힘이 있다")
                #expect(!ReversiRules.legalMoves(board, color: color).contains(idx), "\(item.id) 불법 칸이 합법 수 목록에 있다")
            }
        }
        // 갈래 수까지 못 박는다 — 한쪽이 통째로 비면(예: 전부 불법) 위 단언 절반이 안 돈다.
        #expect(legalCount == 21)
        #expect(illegalCount == 12)
    }

    // 없으면: 끝 분류 순서(전멸 → 판 가득 → no_moves)나 빈칸 몫(이긴 쪽에 전부, 같으면 32:32)이 틀려도 착수 사례가 다 못 잡는다(H03·H05·H09).
    @Test("score 사례 9 — 끝 판단 · 끝 사유 · WOF 점수 · 돌 수")
    func scoreCasesMatch() throws {
        let cases = try ReversiCorpusFile.load().hand.filter { $0.kind == "score" }
        #expect(cases.count == 9)
        for item in cases {
            let board = try ReversiCorpusFile.board(item.board, item.id)
            let expected = item.expected
            #expect((ReversiRules.endKind(board) != nil) == expected.over, "\(item.id) \(item.title)")
            #expect(ReversiRules.endKind(board)?.rawValue == expected.end, "\(item.id) 끝 사유")
            #expect(ReversiRules.score(board).map { ReversiCorpus.Score(black: $0.black, white: $0.white, result: $0.result.rawValue) } == expected.score, "\(item.id) 점수")
            #expect(board.counts == expected.discs.map { ReversiCounts(black: $0.black, white: $0.white, empty: $0.empty) }, "\(item.id) 돌 수")
            if let score = ReversiRules.score(board) { #expect(score.black + score.white == 64, "\(item.id) 점수 합") }
        }
    }

    // 없으면: 비트 이동의 행 끝 가면을 빠뜨린 구현(h4 +1 = a5)이 C04~C07 에서 뒤집어도 "그 사례들이 정말 그 결함을 밟는지"를 모른다.
    // 기준선: 1차원 idx 에 ±1·±7·±8·±9 를 더하고 64 로 감아 읽는 넘김 구현은 네 사례 모두에서 뭔가를 뒤집는다 — 결과가 갈린다.
    @Test("판 끝 1차원 넘김 C04~C07 — 우리 규칙은 불법(no_flip), 넘김 구현은 뒤집는다")
    func edgeWrapCasesDiscriminate() throws {
        let corpus = try ReversiCorpusFile.load()
        for id in ["C04", "C05", "C06", "C07"] {
            let item = try corpus.hand(id)
            let board = try ReversiCorpusFile.board(item.board, id)
            let color = try ReversiCorpusFile.color(item.color, id)
            let idx = try #require(item.idx)
            #expect(item.expected.reason == "no_flip", "\(id): 코퍼스 기대가 바뀌었다")
            #expect(ReversiRules.flips(board, color: color, idx: idx).isEmpty, "\(id) \(item.title)")
            #expect(ReversiRules.play(board, color: color, idx: idx) == .failure(.noFlip), "\(id)")
            #expect(!Self.wrappingFlips(item.board, color: color, idx: idx).isEmpty,
                    "\(id): 넘김 구현도 못 뒤집는다 — 이 사례는 판 끝 결함을 가르지 못한다")
        }
    }

    // 없으면: 시작 배치(V-04)나 첫 수 판정이 어긋나도 perft 1 = 4 만으로는 "네 수가 대칭인지"까지 못 본다(한 수만 두 개 뒤집어도 4).
    @Test("시작 흑 네 수 — d3·c4·f5·e6, 각자 정확히 한 개 뒤집어 4:1, 백의 응수는 늘 셋")
    func startPositionFourMovesInvariant() throws {
        let start = ReversiBoard.start
        #expect(start.string == "...........................wb......bw...........................")
        #expect(start.counts == ReversiCounts(black: 2, white: 2, empty: 60))
        #expect(ReversiRules.legalMoves(start, color: .black) == [19, 26, 37, 44])
        #expect(ReversiRules.legalMoves(start, color: .white) == [20, 29, 34, 43])
        #expect(ReversiRules.endKind(start) == nil)
        #expect(ReversiRules.score(start) == nil)
        for idx in [19, 26, 37, 44] {
            let outcome = try ReversiRules.play(start, color: .black, idx: idx).get()
            #expect(outcome.flipped.count == 1, "흑 \(idx)")
            #expect(outcome.counts == ReversiCounts(black: 4, white: 1, empty: 59), "흑 \(idx)")
            #expect(outcome.next == .white && !outcome.passed && !outcome.isOver, "흑 \(idx)")
            #expect(ReversiRules.legalMoves(outcome.board, color: .white).count == 3, "흑 \(idx) 뒤 백의 응수")
        }
    }

    // 없으면: 비트보드 가면·Kogge-Stone 밀기에 코퍼스 손 사례가 안 덮는 자리(긴 줄·여러 방향·판 끝 근처)의 결함이 남는다.
    // 무작위 대국의 모든 국면에서 두 색 × 64칸의 뒤집힘과 합법 수를 행·열 2차원 걷기(reference.py 를 옮긴 것)와 맞세운다.
    // 기본 게이트는 6판(디버그 빌드 100ms 미만), 규칙을 고칠 때는 `REVERSI_PERFT_DEEP=1` 로 200판(같은 깊은 그물).
    @Test("무작위 대국 6판 — 비트보드 = 2차원 걷기(뒤집힘 · 합법 수)")
    func bitboardMatchesTwoDimensionalWalk() throws {
        try Self.compareWithWalk(games: 6, seed: 0x5245_5645_5253_4931)
    }

    @Test("무작위 대국 200판 — 비트보드 = 2차원 걷기 (REVERSI_PERFT_DEEP=1)",
          .enabled(if: ProcessInfo.processInfo.environment["REVERSI_PERFT_DEEP"] == "1"))
    func deepBitboardMatchesTwoDimensionalWalk() throws {
        try Self.compareWithWalk(games: 200, seed: 0x5245_5645_5253_4932)
    }

    static func compareWithWalk(games: Int, seed: UInt64) throws {
        var rng = GomokuAISplitMix64(seed: seed)
        var positions = 0
        for _ in 0..<games {
            var board = ReversiBoard.start
            var turn: ReversiColor? = .black
            while let color = turn {
                let text = board.string
                let cells = Array(text.utf8)
                for side in ReversiColor.allCases {
                    // 국면마다 64칸을 한 번에 맞세운다(칸마다 #expect 를 부르면 디버그 빌드에서 시험 시간이 그 호출에 다 간다).
                    let walked = (0..<64).map { walkedFlips(cells, color: side, idx: $0) }
                    let ours = (0..<64).map { ReversiRules.flips(board, color: side, idx: $0) }
                    #expect(ours == walked, "\(text) \(side)")
                    #expect(ReversiRules.legalMoves(board, color: side) == (0..<64).filter { !walked[$0].isEmpty }, "\(text) \(side)")
                }
                positions += 1
                let moves = ReversiRules.legalMoves(board, color: color)
                let outcome = try ReversiRules.play(board, color: color, idx: moves[Int(rng.next() % UInt64(moves.count))]).get()
                board = outcome.board
                turn = outcome.next
            }
        }
        #expect(positions > games * 50, "대국이 너무 짧다(\(positions) 국면) — 무작위가 고장 났다")
    }

    // 없으면: 화면 표기(d3)와 와이어 idx 가 행·열을 뒤바꿔도(V-01 한계) 코퍼스의 coord·idx 쌍이 그것을 못 잡는다.
    @Test("좌표 — d3 = 19, 대문자 읽기, 64칸 왕복, 코퍼스 coord·idx 쌍")
    func coordinatesMatchCorpus() throws {
        #expect(ReversiPoint(coord: "d3")?.idx == 19)
        #expect(ReversiPoint(coord: "D3")?.idx == 19)
        #expect(ReversiPoint(coord: "a1")?.idx == 0)
        #expect(ReversiPoint(coord: "h1")?.idx == 7)
        #expect(ReversiPoint(coord: "a8")?.idx == 56)
        #expect(ReversiPoint(coord: "h8")?.idx == 63)
        #expect(ReversiPoint(idx: 19)?.coord == "d3")
        #expect(ReversiPoint(idx: 19) == ReversiPoint(col: 3, row: 2))
        for idx in 0..<64 {
            let point = try #require(ReversiPoint(idx: idx))
            #expect(ReversiPoint(coord: point.coord) == point, "\(idx)")
            #expect(ReversiPoint(coord: point.coord.uppercased()) == point, "\(idx) 대문자")
            #expect(point.idx == idx)
        }
        var paired = 0
        for item in try ReversiCorpusFile.load().hand {
            guard let coord = item.coord, let idx = item.idx else { continue }
            #expect(ReversiPoint(coord: coord)?.idx == idx, "\(item.id) \(coord)")
            paired += 1
        }
        #expect(paired == 32, "coord·idx 쌍이 있는 move 사례 수(A10 은 판 밖이라 coord 가 없다)")
    }

    // MARK: 비교용 구현(시험 안에서만)

    static let directions = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]

    /// reference.py `flips` 를 옮긴 행·열 2차원 걷기 — 비트보드와 맞세우는 정답.
    static func walkedFlips(_ cells: [UInt8], color: ReversiColor, idx: Int) -> [Int] {
        guard (0..<64).contains(idx), cells[idx] == UInt8(ascii: ".") else { return [] }
        let me = color == .black ? UInt8(ascii: "b") : UInt8(ascii: "w")
        let op = color == .black ? UInt8(ascii: "w") : UInt8(ascii: "b")
        var out: [Int] = []
        for (dr, dc) in directions {
            var r = idx / 8 + dr
            var c = idx % 8 + dc
            var line: [Int] = []
            while (0..<8).contains(r), (0..<8).contains(c), cells[r * 8 + c] == op {
                line.append(r * 8 + c)
                r += dr
                c += dc
            }
            if !line.isEmpty, (0..<8).contains(r), (0..<8).contains(c), cells[r * 8 + c] == me { out += line }
        }
        return out.sorted()
    }

    /// **틀린** 구현(기준선): 1차원 idx 에 방향 차를 더하고 64 로 감아 읽는다(행 끝·판 끝을 모른다). C04~C07 이 이것을 가른다.
    static func wrappingFlips(_ board: String, color: ReversiColor, idx: Int) -> [Int] {
        let cells = Array(board.utf8)
        guard (0..<64).contains(idx), cells[idx] == UInt8(ascii: ".") else { return [] }
        let me = color == .black ? UInt8(ascii: "b") : UInt8(ascii: "w")
        let op = color == .black ? UInt8(ascii: "w") : UInt8(ascii: "b")
        func cell(_ i: Int) -> UInt8 { cells[((i % 64) + 64) % 64] }
        var out: [Int] = []
        for step in [-9, -8, -7, -1, 1, 7, 8, 9] {
            var i = idx + step
            var line: [Int] = []
            while line.count < 7, cell(i) == op {
                line.append(((i % 64) + 64) % 64)
                i += step
            }
            if !line.isEmpty, cell(i) == me { out += line }
        }
        return out.sorted()
    }
}
