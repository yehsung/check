import Foundation
import Testing
@testable import CheckCore

// 아잉 뒤집기 수 세기(perft) — **ReversiRules 의 합격선**(체스 `ChessPerftTests` 를 본뜬다).
//
// 기대값은 이 파일에 없다. `Fixtures/reversi-perft.json`(FLIP/fixtures/reversi-perft.json 복사, make_perft.py 가 reference.py 로 만든 것)
// 한 곳에 있고, **SQL 마이그레이션도 같은 파일을 베낀다**(`ReversiPerftFixtureSQLContractTests` 가 둘을 대조한다).
// 숫자를 Swift 와 SQL 이 각자 적으면 둘이 갈려도 아무도 모른다 — 그래서 숫자의 집은 하나다.
//
// 픽스처의 두 묶음:
//  · `positions` ① 시작 판 — 공표값(OEIS A124004, `ply_pass` 관례: 패스도 한 수, depth 전에 끝난 판은 안 셈) depth 1~10.
//    어긋나면 **우리 구현이 틀린 것이다** — 기대값은 고치지 마라. 어긋나면 `ReversiRules.perftDivide` 를 같이 찍는다.
//  · `leaves` ⓐ~ⓔ — 우리가 만든 자리. 합법 수가 0 인 국면(패스 · 빈칸 남은 끝 · 판 가득 · 전멸 · 자식에서 전멸)을 ms 안에 밟는다.
//    SQL 쪽 `array_length('{}',1)` = NULL 결함이 여기서 드러나고, Swift 쪽의 같은 모양 경계(빈 목록 · 0 전파 · 패스 깊이)도 같이 밟는다.
//
// ── 빠른 것과 깊은 것을 가른 기준 ──
// 기본 게이트는 **속도**로 가른다(--no-parallel 실측 100ms 미만). 시작 판은 depth 1~7(합쳐 65,004 잎)과 잎 다섯 전부를 기본에 두고,
// depth 8~10 은 `REVERSI_PERFT_DEEP=1` 에서만 돈다 — 규칙을 고칠 때 한 번 돌리는 그물이다.
// 실측(2026-11-03, 디버그 빌드 · --no-parallel): 기본 depth 7 0.014초(기본 perft 시험 전체 약 0.03초) ·
// DEEP depth 8 0.093초 · depth 9 0.642초 · depth 10 4.786초. depth 8 이 100ms 문턱에 붙어 있어 DEEP 에 둔다.

// MARK: - 픽스처

struct ReversiPerftItem: Sendable, Decodable {
    let label: String
    let board: String
    let color: String
    /// counts[0] 이 깊이 1.
    let counts: [Int]
    /// null(차례인 쪽이 둘 곳 있음) · "pass" · "wipeout"|"board_full"|"no_moves". 잎에만 있다.
    let outcome: String?
    let score: ReversiCorpus.Score?
    let discs: ReversiCorpus.Counts?
    /// 그 수를 두면 판이 끝나는 첫 수들. divide(깊이 2)에서 노드 0 으로 나와야 하는 줄이다.
    let terminalChildren: [Int]?

    /// 라벨 머리글자(①·ⓐ…). 번호로 집는다 — 배열 인덱스로 집으면 줄 순서만 바뀌어도 다른 국면을 잰다.
    var marker: String { label.isEmpty ? "" : String(label.first!) }
}

struct ReversiPerftFixture: Sendable, Decodable {
    let positions: [ReversiPerftItem]
    let leaves: [ReversiPerftItem]

    var all: [ReversiPerftItem] { positions + leaves }

    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/reversi-perft.json")

    /// 매번 읽는다(여섯 항목, ㎲ 단위).
    static func load() throws -> ReversiPerftFixture {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ReversiFixtureError("픽스처가 없다: \(url.path) — 기대값의 집이 하나뿐이라 이게 없으면 잴 것이 없다")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ReversiPerftFixture.self, from: Data(contentsOf: url))
    }

    static func item(_ marker: String) throws -> ReversiPerftItem {
        let fixture = try load()
        guard let found = fixture.all.first(where: { $0.marker == marker }) else {
            throw ReversiFixtureError("픽스처에 \(marker) 국면이 없다(있는 것: \(fixture.all.map(\.marker).joined(separator: " ")))")
        }
        return found
    }
}

/// 수 세기 한 자리. 어긋나면 판과 divide 를 함께 남긴다 — 성공할 때는 divide 를 **계산하지 않는다**.
func expectReversiPerft(_ item: ReversiPerftItem, depth: Int) throws {
    let board = try ReversiCorpusFile.board(item.board, item.label)
    let color = try ReversiCorpusFile.color(item.color, item.label)
    guard depth >= 1, depth <= item.counts.count else {
        throw ReversiFixtureError("\(item.label): 픽스처에 깊이 \(depth) 기대값이 없다(있는 깊이 1…\(item.counts.count))")
    }
    let expected = item.counts[depth - 1]
    let actual = ReversiRules.perft(board, toMove: color, depth: depth)
    #expect(actual == expected, "\(item.label) 깊이 \(depth)")
    guard actual != expected else { return }
    let divide = ReversiRules.perftDivide(board, toMove: color, depth: depth)
        .map { "  \($0.idx.flatMap { ReversiPoint(idx: $0)?.coord } ?? "패스") \($0.nodes)" }
        .joined(separator: "\n")
    Issue.record("""
        \(item.label) 깊이 \(depth): \(actual) ≠ \(expected) (차 \(actual - expected))
        \(item.board) · \(item.color) 차례
        divide(깊이 \(depth)) — reference.py 로 같은 divide 를 찍어 나란히 놓고 갈린 첫 수를 찾아라:
        \(divide)
        """)
}

@Suite("아잉 뒤집기 수 세기(perft)")
struct ReversiPerftTests {

    // 없으면: depth 0 을 0 으로 세는 구현(재귀 바닥이 틀림)이 잎 depth 1 에서야 이상하게 드러난다.
    @Test("깊이 0 은 국면 자신 하나 · 음수 깊이는 0 · 끝난 판도 깊이 0 은 1")
    func depthZeroCountsThePositionItself() throws {
        #expect(ReversiRules.perft(.start, toMove: .black, depth: 0) == 1)
        #expect(ReversiRules.perft(.start, toMove: .black, depth: -1) == 0)
        let ended = try ReversiCorpusFile.board(try ReversiPerftFixture.item("ⓑ").board, "ⓑ")
        #expect(ReversiRules.perft(ended, toMove: .black, depth: 0) == 1)
        #expect(ReversiRules.perftDivide(.start, toMove: .black, depth: 0).isEmpty)
    }

    // 없으면: 누가 픽스처에서 잎 하나를 지워도 아래 반복 시험은 남은 것만 돌고 초록이다. 또 cases.json 의 perft 값과 픽스처가
    // 따로 놀면(한쪽만 고침) Swift·SQL·파이썬이 서로 다른 정답을 재게 된다.
    @Test("픽스처 모양 — ① 시작 판 depth 1~10 = cases.json ply_pass · 잎 ⓐ~ⓔ depth 1·2 · 0 짜리와 0 아닌 잎이 섞였다")
    func fixtureShapeIsIntact() throws {
        let fixture = try ReversiPerftFixture.load()
        #expect(fixture.positions.map(\.marker) == ["①"])
        #expect(fixture.leaves.map(\.marker) == ["ⓐ", "ⓑ", "ⓒ", "ⓓ", "ⓔ"])
        let start = try #require(fixture.positions.first)
        #expect(start.board == ReversiBoard.start.string && start.color == "black")
        let corpus = try ReversiCorpusFile.load()
        let published = (1...10).map { corpus.perft.values[String($0)]?.plyPass ?? -1 }
        #expect(start.counts == published, "픽스처 ① 과 cases.json perft.values.ply_pass 가 갈렸다")
        #expect(start.counts == (1...10).map { corpus.perft.values[String($0)]?.known ?? -1 }, "공표값(known)과 갈렸다")
        #expect(start.counts[9] == 24_571_056, "depth 10 은 ply_pass 관례 값이다(24,571,284 는 ply_pass_ended)")
        for item in fixture.leaves {
            #expect(item.counts.count == 2, "\(item.label)")
            #expect(ReversiBoard(string: item.board) != nil, "\(item.label): 판을 못 읽었다")
            #expect(!item.board.contains("-"), "\(item.label): 빈칸은 '.' 이다")
        }
        // 0 짜리 잎과 0 아닌 잎이 둘 다 있어야 한다 — 전부 0 이면 "0 을 특별 취급"하는 구현이 통과하고, 0 이 없으면 NULL 결함을 못 밟는다.
        #expect(fixture.leaves.contains { $0.counts[0] == 0 })
        #expect(fixture.leaves.contains { $0.counts[0] > 0 })
        // 머리 키 여섯 — SQL 생성기와 대조 시험이 읽는 설명 칸이다.
        let raw = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: ReversiPerftFixture.url)) as? [String: Any])
        for key in ["about", "positions_source", "leaves_source", "leaves_why", "counts_note", "sql_contract"] {
            #expect(raw[key] is String, "머리 키 \(key) 가 없다")
        }
    }

    @Test("① 시작 판 깊이 1~4 — 4 · 12 · 56 · 244")
    func startShallow() throws {
        let item = try ReversiPerftFixture.item("①")
        for depth in 1...4 { try expectReversiPerft(item, depth: depth) }
    }

    @Test("① 시작 판 깊이 5 — 1,396")
    func startDepthFive() throws {
        try expectReversiPerft(try ReversiPerftFixture.item("①"), depth: 5)
    }

    @Test("① 시작 판 깊이 6 — 8,200")
    func startDepthSix() throws {
        try expectReversiPerft(try ReversiPerftFixture.item("①"), depth: 6)
    }

    @Test("① 시작 판 깊이 7 — 55,092")
    func startDepthSeven() throws {
        try expectReversiPerft(try ReversiPerftFixture.item("①"), depth: 7)
    }

    // 깊은 자리: 셋이 합쳐 2,797만 잎이다. 기본 게이트에 두면 게이트가 길어져 아무도 안 돌린다.
    // 셋을 따로 둔 까닭: 하나가 어긋났을 때 어느 깊이인지 이름이 바로 말해 주고, 각자의 소요 시간이 처리량(노드/초)이 된다.
    // depth 9 는 시작 판에서 첫 패스가 나오는 깊이다(ply_pass 3,005,288 · move_only 3,005,320 — 패스 관례가 여기서 처음 갈린다).
    @Test("깊은 수 세기 ① 깊이 8 — 390,216 (REVERSI_PERFT_DEEP=1)", .enabled(if: ProcessInfo.processInfo.environment["REVERSI_PERFT_DEEP"] == "1"))
    func deepStartDepthEight() throws {
        try expectReversiPerft(try ReversiPerftFixture.item("①"), depth: 8)
    }

    @Test("깊은 수 세기 ① 깊이 9 — 3,005,288 (REVERSI_PERFT_DEEP=1)", .enabled(if: ProcessInfo.processInfo.environment["REVERSI_PERFT_DEEP"] == "1"))
    func deepStartDepthNine() throws {
        try expectReversiPerft(try ReversiPerftFixture.item("①"), depth: 9)
    }

    @Test("깊은 수 세기 ① 깊이 10 — 24,571,056 (REVERSI_PERFT_DEEP=1)", .enabled(if: ProcessInfo.processInfo.environment["REVERSI_PERFT_DEEP"] == "1"))
    func deepStartDepthTen() throws {
        try expectReversiPerft(try ReversiPerftFixture.item("①"), depth: 10)
    }

    // 없으면: 패스를 깊이 없이 넘기거나(move_only) 끝난 판을 잎 1 로 세는(…_ended) 관례 혼동, 빈 합법 수 목록을 다루는 경계 결함이
    // 시작 판에선 depth 9 에야 우연히 드러난다. 잎 다섯은 그 경계를 depth 1·2 에서 바로 밟는다.
    @Test("잎 ⓐ~ⓔ 깊이 1·2 — 패스 · 둘 다 못 둠 · 판 가득 · 전멸 · 8방향 뒤 자식 전멸")
    func leavesDepthOneAndTwo() throws {
        let fixture = try ReversiPerftFixture.load()
        #expect(fixture.leaves.count == 5)
        for item in fixture.leaves {
            try expectReversiPerft(item, depth: 1)
            try expectReversiPerft(item, depth: 2)
        }
    }

    // 없으면: 픽스처의 outcome·score 가 말하는 국면 판단(패스냐 끝이냐, 끝 사유, WOF 점수)과 규칙이 갈려도 노드 수만으로는 모른다
    // (ⓑⓒⓓ 는 셋 다 [0, 0] 이라 끝 사유를 바꿔 적어도 노드 수는 같다).
    @Test("잎의 국면 판단 — outcome(null/pass/끝 사유) · 점수 · 돌 수가 규칙과 같다")
    func leafOutcomesMatchRules() throws {
        for item in try ReversiPerftFixture.load().leaves {
            let board = try ReversiCorpusFile.board(item.board, item.label)
            let color = try ReversiCorpusFile.color(item.color, item.label)
            let mine = ReversiRules.hasLegalMove(board, color: color)
            let theirs = ReversiRules.hasLegalMove(board, color: color.opponent)
            let actual: String? = mine ? nil : (theirs ? "pass" : ReversiRules.endKind(board)?.rawValue)
            #expect(actual == item.outcome, "\(item.label): 국면 판단")
            #expect(ReversiRules.score(board).map { ReversiCorpus.Score(black: $0.black, white: $0.white, result: $0.result.rawValue) } == item.score,
                    "\(item.label): 점수")
            if let discs = item.discs {
                #expect(board.counts == ReversiCounts(black: discs.black, white: discs.white, empty: discs.empty), "\(item.label): 돌 수")
            }
        }
    }

    // 없으면: divide 가 합계와 어긋나거나(진단 도구가 거짓말) 패스 뿌리를 빼먹어도, 실패할 때만 찍히는 도구라 아무도 모른다.
    @Test("divide — 합계 = perft · 끝나는 첫 수는 노드 0 · 패스 뿌리는 (nil, n) 한 줄 · 끝난 판은 빈 목록")
    func divideIsConsistent() throws {
        let fixture = try ReversiPerftFixture.load()
        for item in fixture.all {
            let board = try ReversiCorpusFile.board(item.board, item.label)
            let color = try ReversiCorpusFile.color(item.color, item.label)
            let depth = item.marker == "①" ? 4 : 2
            let divide = ReversiRules.perftDivide(board, toMove: color, depth: depth)
            #expect(divide.reduce(0) { $0 + $1.nodes } == ReversiRules.perft(board, toMove: color, depth: depth), "\(item.label)")
            for child in item.terminalChildren ?? [] {
                #expect(divide.first(where: { $0.idx == child })?.nodes == 0, "\(item.label): \(child) 는 판을 끝내는 수다")
            }
        }
        let pass = try ReversiPerftFixture.item("ⓐ")
        let passDivide = ReversiRules.perftDivide(try ReversiCorpusFile.board(pass.board, "ⓐ"), toMove: .black, depth: 2)
        #expect(passDivide.count == 1 && passDivide[0].idx == nil && passDivide[0].nodes == 1, "ⓐ 패스 뿌리")
        let over = try ReversiPerftFixture.item("ⓑ")
        #expect(ReversiRules.perftDivide(try ReversiCorpusFile.board(over.board, "ⓑ"), toMove: .black, depth: 2).isEmpty, "ⓑ 끝난 판")
        let eight = try ReversiPerftFixture.item("ⓔ")
        #expect(eight.terminalChildren == [36], "ⓔ 의 유일한 수 e5 는 백을 전멸시킨다")
    }
}
