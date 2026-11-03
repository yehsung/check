import Foundation
import Testing
@testable import CheckCore

// 아잉 뒤집기 규칙 표면의 **성립 안 하는 입력** 계약과 와이어 어휘.
//
// 서버·와이어·화면은 판을 64자 '.bw' 문자열로, 칸을 idx(0~63)로, 결과·끝 사유·불법 까닭을 정해진 영어 낱말로 주고받는다(SPEC §2.2).
// 이 파일은 그 경계가 어긋난 입력(63자·'x'·'-'·idx −1/64·"i9")을 **조용히 받아들이지 않는지**, 그리고 어휘 글자가 서버와 같은지를 잰다.
// 각 단언에는 "한 글자만 다른 입력"을 기준선으로 같이 둔다 — 같은 입력이면 영원히 초록이라 결과가 갈리는 짝이 있어야 한다.

@Suite("아잉 뒤집기 규칙 계약 — 성립 안 하는 입력 · 와이어 어휘")
struct ReversiContractTests {
    static let start = "...........................wb......bw..........................."

    // 없으면: 63자·65자·다른 글자의 판을 받아들여 엉뚱한 칸에 돌이 놓인 채로 판정이 돈다(서버 reversi_board_ok 는 거절한다).
    @Test("판 문자열 — 64자 '.bw' 만 받는다(63·65자 · 'x' · '-' · 대문자 · 공백 · 다바이트 글자 거절)")
    func boardStringRejectsMalformed() {
        #expect(ReversiBoard(string: Self.start) == .start, "기준선: 시작 판 문자열")
        let sixtyThree = String(Self.start.dropLast())
        #expect(ReversiBoard(string: sixtyThree) == nil, "63자")
        #expect(ReversiBoard(string: sixtyThree + ".") != nil, "기준선: 한 글자 더하면 64자")
        #expect(ReversiBoard(string: Self.start + ".") == nil, "65자")
        #expect(ReversiBoard(string: "") == nil)
        for bad in ["x", "-", "B", "W", " ", "é", "흑"] {
            let text = bad + String(Self.start.dropFirst())
            #expect(ReversiBoard(string: text) == nil, "첫 칸 \(bad)")
        }
        #expect(ReversiBoard(string: "b" + String(Self.start.dropFirst())) != nil, "기준선: 첫 칸 b")
        // 64칸 모두 왕복.
        let mixed = String((0..<64).map { ["." as Character, "b", "w"][$0 % 3] })
        #expect(ReversiBoard(string: mixed)?.string == mixed)
        #expect(ReversiBoard(string: mixed)?.description == mixed)
    }

    // 없으면: 와이어 board 칸을 객체·배열로 내보내거나 잘못된 판을 디코드해 버리면 서버 state 와 왕복이 깨진다.
    @Test("판 Codable — 64자 문자열 하나로 왕복, 잘못된 문자열·숫자는 디코드 실패")
    func boardCodableIsSingleString() throws {
        let data = try JSONEncoder().encode([ReversiBoard.start])
        #expect(String(decoding: data, as: UTF8.self) == "[\"\(Self.start)\"]")
        #expect(try JSONDecoder().decode([ReversiBoard].self, from: data) == [.start])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([ReversiBoard].self, from: Data("[\"\(Self.start.dropLast())\"]".utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([ReversiBoard].self, from: Data("[64]".utf8)) }
        let counts = try JSONEncoder().encode(ReversiCounts(black: 3, white: 1, empty: 60))
        let keys = try #require(try JSONSerialization.jsonObject(with: counts) as? [String: Int])
        #expect(keys == ["black": 3, "white": 1, "empty": 60])
    }

    // 없으면: idx −1·64 가 판 밖 판정 없이 비트 이동(음수·64 이상 shift)으로 들어가 엉뚱한 칸을 뒤집거나 죽는다.
    @Test("판 밖 idx — subscript nil · flips [] · play out_of_range(이미 돌·못 뒤집음보다 먼저)")
    func outOfRangeIndexIsRejected() {
        let board = ReversiBoard.start
        for idx in [-1, 64, -64, 100, Int.min, Int.max] {
            #expect(board[idx] == nil, "\(idx)")
            #expect(ReversiRules.flips(board, color: .black, idx: idx).isEmpty, "\(idx)")
            #expect(ReversiRules.play(board, color: .black, idx: idx) == .failure(.outOfRange), "\(idx)")
        }
        // 기준선: 판 안의 같은 줄 — 까닭이 갈린다(이미 돌 · 못 뒤집음 · 합법).
        #expect(board[27] == .white && board[28] == .black && board[0] == nil)
        #expect(ReversiRules.play(board, color: .black, idx: 27) == .failure(.occupied))
        #expect(ReversiRules.play(board, color: .black, idx: 0) == .failure(.noFlip))
        #expect((try? ReversiRules.play(board, color: .black, idx: 19).get())?.flipped == [27])
    }

    // 없으면: "i1"·"a9"·"d10" 같은 좌표가 다른 칸으로 읽혀 화면 표기와 와이어 idx 가 갈린다.
    @Test("좌표 — 판 밖 col·row·idx · 잘못된 글자 거절, 기준선은 같은 자리의 올바른 글자")
    func pointRejectsMalformed() {
        #expect(ReversiPoint(col: 8, row: 0) == nil)
        #expect(ReversiPoint(col: 0, row: 8) == nil)
        #expect(ReversiPoint(col: -1, row: 0) == nil)
        #expect(ReversiPoint(col: 7, row: 7)?.idx == 63, "기준선")
        #expect(ReversiPoint(idx: -1) == nil)
        #expect(ReversiPoint(idx: 64) == nil)
        #expect(ReversiPoint(idx: 63)?.coord == "h8", "기준선")
        for bad in ["", "d", "i1", "a9", "a0", "d10", "d3 ", " d3", "3d", "@1", "`1", "é1", "dd"] {
            #expect(ReversiPoint(coord: bad) == nil, "\(bad)")
        }
        #expect(ReversiPoint(coord: "h1")?.idx == 7, "기준선")
        #expect(ReversiPoint(coord: "A8")?.coord == "a8", "읽기는 대문자도, 쓰기는 소문자")
    }

    // 없으면: 깊이 음수로 재귀가 끝나지 않거나, 깊이 0 divide 가 뭔가를 내서 진단이 거짓말한다.
    @Test("perft 경계 — 음수 0 · 깊이 0 은 1 · divide 깊이 0 은 빈 목록")
    func perftBoundaries() {
        #expect(ReversiRules.perft(.start, toMove: .black, depth: -5) == 0)
        #expect(ReversiRules.perft(.start, toMove: .black, depth: 0) == 1)
        #expect(ReversiRules.perft(.start, toMove: .black, depth: 1) == 4, "기준선")
        #expect(ReversiRules.perftDivide(.start, toMove: .black, depth: 0).isEmpty)
        #expect(ReversiRules.perftDivide(.start, toMove: .black, depth: -1).isEmpty)
        #expect(ReversiRules.perftDivide(.start, toMove: .black, depth: 1).map(\.idx) == [19, 26, 37, 44], "기준선")
    }

    // 없으면: 서버 어휘(black_win · board_full · no_flip …)와 글자가 하나라도 다르면 와이어 디코드가 실패하거나 다른 뜻으로 읽힌다.
    @Test("와이어 어휘 — 색 · 결과 · 끝 분류 · 끝 사유(모르는 값은 unknown) · 불법 까닭 · 수 종류")
    func wireVocabularyMatchesServer() throws {
        #expect(ReversiColor.allCases.map(\.rawValue) == ["black", "white"])
        #expect(ReversiColor.black.cell == "b" && ReversiColor.white.cell == "w")
        #expect(ReversiColor.black.opponent == .white && ReversiColor.white.opponent == .black)
        #expect([ReversiResult.blackWin, .whiteWin, .draw].map(\.rawValue) == ["black_win", "white_win", "draw"])
        #expect(ReversiResult.blackWin.winner == .black && ReversiResult.whiteWin.winner == .white && ReversiResult.draw.winner == nil)
        #expect([ReversiEndKind.boardFull, .wipeout, .noMoves].map(\.rawValue) == ["board_full", "wipeout", "no_moves"])
        #expect([ReversiEndReason.boardFull, .wipeout, .noMoves, .resign, .abandoned].map(\.rawValue)
                == ["board_full", "wipeout", "no_moves", "resign", "abandoned"])
        #expect([ReversiIllegalReason.outOfRange, .occupied, .noFlip].map(\.rawValue) == ["out_of_range", "occupied", "no_flip"])
        #expect([ReversiPly.Kind.stone, .pass].map(\.rawValue) == ["stone", "pass"])
        let decoded = try JSONDecoder().decode([ReversiEndReason].self, from: Data(#"["abandoned","resign","timeout","WIPEOUT"]"#.utf8))
        #expect(decoded == [.abandoned, .resign, .unknown, .unknown], "모르는 값(대문자 포함)은 unknown, 아는 값은 그대로")
        #expect(ReversiEndReason(.noMoves) == .noMoves && ReversiEndReason(.boardFull) == .boardFull && ReversiEndReason(.wipeout) == .wipeout)
    }

    // 없으면: 칸 하나의 차이를 판정이 못 본다(뒤집힘이 판의 다른 칸에 묶이지 않음). A09 c3 은 f6 이 빈칸이라 불법 —
    // f6 에 흑 하나를 놓으면 같은 c3 이 대각 두 개를 뒤집는 합법 수가 된다. 결과가 갈리는 기준선 짝.
    @Test("한 칸 차이 기준선 — A09 c3 불법, f6 에 흑을 놓으면 c3 이 d4·e5 를 뒤집는다")
    func oneCellChangesTheVerdict() throws {
        let item = try ReversiCorpusFile.load().hand("A09")
        let board = try ReversiCorpusFile.board(item.board, "A09")
        #expect(ReversiRules.play(board, color: .black, idx: 18) == .failure(.noFlip))
        var cells = Array(item.board)
        #expect(cells[45] == ".")
        cells[45] = "b"
        let changed = try #require(ReversiBoard(string: String(cells)))
        #expect(ReversiRules.flips(changed, color: .black, idx: 18) == [27, 36])
    }

    // 없으면: 코퍼스·기보의 판 문자열이 우리 표현을 거쳐 한 글자라도 바뀌면(칸 순서·글자) 서버와 대조할 때 갈린다.
    @Test("코퍼스 판 문자열 왕복 — hand 48 의 판 · 둔 뒤 판, 기보 200 의 마지막 판")
    func corpusBoardsRoundTrip() throws {
        let corpus = try ReversiCorpusFile.load()
        var count = 0
        for text in corpus.hand.flatMap({ [$0.board, $0.expected.boardAfter].compactMap { $0 } }) + corpus.wthorSample.map(\.finalBoard) {
            #expect(ReversiBoard(string: text)?.string == text, "\(text)")
            count += 1
        }
        #expect(count == 48 + 33 + 200)
    }
}
