import Foundation

// 아잉 뒤집기(내부 이름 reversi) 규칙 — 리버시 표준(WOF·JOF): 8×8 · 흑 선 · 8방향 동시 뒤집기 · 하나 이상 끼워야 합법 ·
// 둘 곳이 없을 때만 자동 패스 · 둘 다 없으면 끝 · 빈칸은 이긴 쪽에 더한다 · 같으면 32:32 무승부.
// 설계: flip/SPEC.md §2 · §4.1. 규칙 정본 rules.md V-01~V-17, 정답지 cases.json · reference.py(파이썬 참조 구현).
//
// ── 쌍둥이 ──
// 서버(plpgsql `reversi_*`)·이 파일·reference.py 가 같은 판정을 따로 한다. 이름 대응은 SPEC §2.1 표가 정본이다:
// validate_board ↔ `ReversiBoard(string:)` · counts ↔ `ReversiBoard.counts` · flips ↔ `flips` · legal_moves ↔ `legalMoves` ·
// apply+next_turn+end_kind+score_wof ↔ `play` · next_turn ↔ `nextTurn` · end_kind ↔ `endKind` · score_wof ↔ `score` · perft ↔ `perft`.
// 공개 표면(이름·서명)은 다른 갈래(스토어·화면)와의 계약이다 — 바꾸려면 SPEC 부터 고친다.
//
// ── 표기(V-01~V-03) ──
// 칸은 정수 idx(0~63) 하나다: idx = row*8 + col, row 0 = 1행(위), col 0 = a열(왼쪽). 화면 표기만 "d3" 꼴 소문자.
// 판 문자열은 64자 '.bw'(빈칸 '.', '-' 금지), 칸 순서 = idx 순서. 목록(합법 수·뒤집힌 칸)은 idx 오름차순.
// 안 표현은 비트보드(ReversiBitboard.swift)다.

/// 돌 색. 와이어 값 `"black"`·`"white"`.
package nonisolated enum ReversiColor: String, Codable, Sendable, CaseIterable {
    case black, white

    package var opponent: ReversiColor { self == .black ? .white : .black }

    /// 판 문자열의 칸 글자: 흑 `b` · 백 `w`.
    package var cell: Character { self == .black ? "b" : "w" }
}

/// 8×8 판 한 장. Codable 은 64자 문자열 하나다(와이어 `board` 칸 그대로).
package nonisolated struct ReversiBoard: Hashable, Sendable, Codable, CustomStringConvertible {
    /// 흑 돌 비트(비트 i = idx i).
    internal let black: UInt64
    /// 백 돌 비트.
    internal let white: UInt64

    /// 비트에서 바로 만든다(규칙·엔진 내부). 두 색이 한 칸에 겹치면 안 된다.
    internal init(black: UInt64, white: UInt64) {
        assert(black & white == 0, "ReversiBoard: 흑·백이 한 칸에 겹쳤다")
        self.black = black
        self.white = white
    }

    /// 시작 배치(V-04): 백 d4(27)·e5(36), 흑 e4(28)·d5(35). 흑이 먼저 둔다.
    package static let start = ReversiBoard(
        black: (1 << 28) | (1 << 35),
        white: (1 << 27) | (1 << 36)
    )

    /// 64자 '.bw' 문자열에서 만든다(V-02). 길이·글자가 하나라도 어긋나면 nil — 대문자·'-'·공백도 받지 않는다.
    package init?(string: String) {
        var black: UInt64 = 0
        var white: UInt64 = 0
        var index = 0
        for byte in string.utf8 {
            guard index < 64 else { return nil }
            switch byte {
            case UInt8(ascii: "."): break
            case UInt8(ascii: "b"): black |= 1 << UInt64(index)
            case UInt8(ascii: "w"): white |= 1 << UInt64(index)
            default: return nil
            }
            index += 1
        }
        guard index == 64 else { return nil }
        self.init(black: black, white: white)
    }

    /// 64자 '.bw' 문자열(idx 순서).
    package var string: String {
        var bytes = [UInt8](repeating: UInt8(ascii: "."), count: 64)
        for idx in ReversiBits.indices(black) { bytes[idx] = UInt8(ascii: "b") }
        for idx in ReversiBits.indices(white) { bytes[idx] = UInt8(ascii: "w") }
        return String(decoding: bytes, as: UTF8.self)
    }

    package var description: String { string }

    /// 그 칸의 돌. nil = 빈칸 또는 범위 밖(0~63 이 아님).
    package subscript(idx: Int) -> ReversiColor? {
        guard (0..<64).contains(idx) else { return nil }
        let bit: UInt64 = 1 << UInt64(idx)
        if black & bit != 0 { return .black }
        if white & bit != 0 { return .white }
        return nil
    }

    /// 판 위 실제 돌 수(V-12).
    package var counts: ReversiCounts {
        let b = black.nonzeroBitCount
        let w = white.nonzeroBitCount
        return ReversiCounts(black: b, white: w, empty: 64 - b - w)
    }

    /// 그 색의 돌 비트.
    internal func bits(_ color: ReversiColor) -> UInt64 { color == .black ? black : white }

    /// `color` 쪽에서 본 (내 돌, 상대 돌).
    internal func sides(_ color: ReversiColor) -> (own: UInt64, opp: UInt64) {
        color == .black ? (black, white) : (white, black)
    }

    /// `color` 쪽 (내 돌, 상대 돌)에서 판을 다시 만든다.
    internal init(own: UInt64, opp: UInt64, color: ReversiColor) {
        if color == .black { self.init(black: own, white: opp) } else { self.init(black: opp, white: own) }
    }

    // Codable — 64자 문자열 하나.
    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let board = ReversiBoard(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "판은 64자 '.bw' 문자열이어야 한다(받은 길이 \(raw.count))")
        }
        self = board
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

/// 칸 좌표. col 0 = a열(왼쪽), row 0 = 1행(위). 와이어는 idx 하나만 쓰고, 이 타입은 화면 표기("d3")용이다.
package nonisolated struct ReversiPoint: Hashable, Sendable {
    package let col: Int
    package let row: Int

    package init?(col: Int, row: Int) {
        guard (0..<8).contains(col), (0..<8).contains(row) else { return nil }
        self.col = col
        self.row = row
    }

    package init?(idx: Int) {
        guard (0..<64).contains(idx) else { return nil }
        self.col = idx % 8
        self.row = idx / 8
    }

    /// "d3"·"D3" → (col 3, row 2). 정확히 두 글자(열 a~h 대소문자 + 행 1~8)만 받는다.
    package init?(coord: String) {
        let bytes = Array(coord.utf8)
        guard bytes.count == 2 else { return nil }
        let letter = bytes[0] | 0x20 // ASCII 대문자 → 소문자(숫자·기호는 아래 범위 검사에서 걸러진다)
        guard (UInt8(ascii: "a")...UInt8(ascii: "h")).contains(letter),
              (UInt8(ascii: "1")...UInt8(ascii: "8")).contains(bytes[1]) else { return nil }
        self.col = Int(letter - UInt8(ascii: "a"))
        self.row = Int(bytes[1] - UInt8(ascii: "1"))
    }

    package var idx: Int { row * 8 + col }

    /// 소문자 좌표("d3").
    package var coord: String {
        let letter = Character(UnicodeScalar(UInt8(ascii: "a") + UInt8(col)))
        return "\(letter)\(row + 1)"
    }
}

/// 판 위 돌 수(와이어 `discs` 칸 `{black, white, empty}`).
package nonisolated struct ReversiCounts: Equatable, Hashable, Sendable, Codable {
    package var black: Int
    package var white: Int
    package var empty: Int

    package init(black: Int, white: Int, empty: Int) {
        self.black = black
        self.white = white
        self.empty = empty
    }
}

/// 결과(색 기준). 와이어 `black_win`·`white_win`·`draw`.
package nonisolated enum ReversiResult: String, Codable, Sendable {
    case blackWin = "black_win", whiteWin = "white_win", draw

    /// 이긴 색. 무승부면 nil.
    package var winner: ReversiColor? {
        switch self {
        case .blackWin: return .black
        case .whiteWin: return .white
        case .draw: return nil
        }
    }

    /// 그 색의 승리.
    package init(winner: ReversiColor) {
        self = winner == .black ? .blackWin : .whiteWin
    }
}

/// WOF 점수(V-11): 많은 쪽이 이기고 빈칸은 전부 이긴 쪽에 더한다. 같으면 32:32. 합은 늘 64. 끝난 판에만 있다.
package nonisolated struct ReversiScore: Equatable, Sendable {
    package let black: Int
    package let white: Int
    package let result: ReversiResult

    package init(black: Int, white: Int, result: ReversiResult) {
        self.black = black
        self.white = white
        self.result = result
    }
}

/// 판이 스스로 끝난 까닭(V-10). 분류 순서: 전멸 → 판 가득 → 둘 다 둘 곳 없음.
package nonisolated enum ReversiEndKind: String, Codable, Sendable {
    case boardFull = "board_full", wipeout, noMoves = "no_moves"
}

/// 판이 끝난 까닭(와이어·AI 판 공용). 자연 종료 셋 + 기권·시간 초과 연속 패. 모르는 값은 `.unknown` 으로 읽는다
/// (서버가 어휘를 넓혀도 옛 앱의 디코드가 통째로 깨지지 않게).
package nonisolated enum ReversiEndReason: String, Codable, Sendable {
    case boardFull = "board_full", wipeout, noMoves = "no_moves", resign, abandoned, unknown

    package init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ReversiEndReason(rawValue: raw) ?? .unknown
    }

    /// 자연 종료 분류 → 끝난 까닭.
    package init(_ kind: ReversiEndKind) {
        switch kind {
        case .boardFull: self = .boardFull
        case .wipeout: self = .wipeout
        case .noMoves: self = .noMoves
        }
    }
}

/// 불법 수의 까닭(V-06). 판정 순서: 범위 밖 → 이미 돌 → 끼울 돌 없음.
/// `Error` 는 `Result<_, ReversiIllegalReason>` 의 실패 칸이 되기 위해 붙인다.
package nonisolated enum ReversiIllegalReason: String, Codable, Sendable, Error {
    case outOfRange = "out_of_range", occupied, noFlip = "no_flip"
}

/// 합법 수 하나를 둔 결과(서버 `reversi_judge` 합법 갈래와 1:1).
package nonisolated struct ReversiMoveOutcome: Equatable, Sendable {
    /// 둔 뒤의 판.
    package let board: ReversiBoard
    /// 뒤집힌 칸(오름차순, 둔 칸은 빠진다).
    package let flipped: [Int]
    /// 다음 차례. nil = 끝.
    package let next: ReversiColor?
    /// 상대가 둘 곳이 없어 자동 패스됐고 둔 사람이 이어 둔다(V-09).
    package let passed: Bool
    package let isOver: Bool
    package let counts: ReversiCounts
    /// 끝났을 때만.
    package let score: ReversiScore?
    /// 끝났을 때만.
    package let end: ReversiEndKind?

    package init(
        board: ReversiBoard, flipped: [Int], next: ReversiColor?, passed: Bool,
        isOver: Bool, counts: ReversiCounts, score: ReversiScore?, end: ReversiEndKind?
    ) {
        self.board = board
        self.flipped = flipped
        self.next = next
        self.passed = passed
        self.isOver = isOver
        self.counts = counts
        self.score = score
        self.end = end
    }
}

/// 수 기록 한 줄(와이어 `reversi_moves` 행 · AI 판 공용). 패스는 `kind == .pass`, `idx == nil`, `flipped == []`, `auto == false`.
package nonisolated struct ReversiPly: Equatable, Hashable, Sendable {
    package enum Kind: String, Codable, Sendable { case stone, pass }

    /// 1 부터(패스 포함 기록 번호 — 서버 move_count 와 같은 눈금).
    package let seq: Int
    package let color: ReversiColor
    package let kind: Kind
    package let idx: Int?
    package let flipped: [Int]
    /// 시간 초과 자동 착수만 참. 패스 줄은 늘 거짓.
    package let auto: Bool

    package init(seq: Int, color: ReversiColor, kind: Kind, idx: Int?, flipped: [Int], auto: Bool) {
        self.seq = seq
        self.color = color
        self.kind = kind
        self.idx = idx
        self.flipped = flipped
        self.auto = auto
    }
}

/// 규칙 판정(순수 함수). 서버 `reversi_*` 판정 함수와 cases.json 이 정답지다.
package nonisolated enum ReversiRules {
    /// `idx` 에 `color` 를 두면 뒤집힐 칸(오름차순). 범위 밖·빈칸 아님·하나도 못 끼움이면 [].
    package static func flips(_ board: ReversiBoard, color: ReversiColor, idx: Int) -> [Int] {
        guard (0..<64).contains(idx) else { return [] }
        let (own, opp) = board.sides(color)
        return ReversiBits.indices(ReversiBits.flips(own: own, opp: opp, square: idx))
    }

    /// `color` 의 합법 수(오름차순).
    package static func legalMoves(_ board: ReversiBoard, color: ReversiColor) -> [Int] {
        let (own, opp) = board.sides(color)
        return ReversiBits.indices(ReversiBits.moves(own: own, opp: opp))
    }

    package static func hasLegalMove(_ board: ReversiBoard, color: ReversiColor) -> Bool {
        let (own, opp) = board.sides(color)
        return ReversiBits.moves(own: own, opp: opp) != 0
    }

    /// 한 수를 둔다(V-06~V-11). 불법이면 까닭(범위 밖 → 이미 돌 → 끼울 돌 없음 순서)만 돌려주고 판은 그대로다.
    /// 차례 검사는 하지 않는다 — 누가 둘 차례인지는 판 문자열에 없다(서버·AI 판이 따로 본다).
    package static func play(_ board: ReversiBoard, color: ReversiColor, idx: Int) -> Result<ReversiMoveOutcome, ReversiIllegalReason> {
        guard (0..<64).contains(idx) else { return .failure(.outOfRange) }
        guard board[idx] == nil else { return .failure(.occupied) }
        let (own, opp) = board.sides(color)
        let flipped = ReversiBits.flips(own: own, opp: opp, square: idx)
        guard flipped != 0 else { return .failure(.noFlip) }
        let after = ReversiBoard(own: own | flipped | (1 << UInt64(idx)), opp: opp & ~flipped, color: color)
        let (next, passed) = nextTurn(after: after, mover: color)
        let isOver = next == nil
        return .success(ReversiMoveOutcome(
            board: after,
            flipped: ReversiBits.indices(flipped),
            next: next,
            passed: passed,
            isOver: isOver,
            counts: after.counts,
            score: isOver ? wofScore(after) : nil,
            end: isOver ? endKindOfFinished(after) : nil
        ))
    }

    /// `mover` 가 방금 둔 뒤 다음 차례(V-09): ① 상대에게 합법 수가 있으면 (상대, false) ② 없고 mover 에 있으면
    /// 상대 자동 패스 (mover, true) ③ 둘 다 없으면 끝 (nil, false).
    package static func nextTurn(after board: ReversiBoard, mover: ReversiColor) -> (next: ReversiColor?, passed: Bool) {
        if hasLegalMove(board, color: mover.opponent) { return (mover.opponent, false) }
        if hasLegalMove(board, color: mover) { return (mover, true) }
        return (nil, false)
    }

    /// 끝난 판의 분류(V-10). 안 끝났으면(어느 쪽이든 둘 곳이 있으면) nil.
    package static func endKind(_ board: ReversiBoard) -> ReversiEndKind? {
        guard isOver(board) else { return nil }
        return endKindOfFinished(board)
    }

    /// WOF 점수(V-11). 끝난 판에만 — 안 끝났으면 nil.
    package static func score(_ board: ReversiBoard) -> ReversiScore? {
        guard isOver(board) else { return nil }
        return wofScore(board)
    }

    /// 수 세기(V-17) — `ply_pass` 관례: 강제 패스도 한 수로 세고, depth 에 닿기 전에 끝난 판은 세지 않는다.
    /// depth 0 은 1(국면 자신), 음수는 0.
    package static func perft(_ board: ReversiBoard, toMove: ReversiColor, depth: Int) -> Int {
        guard depth >= 0 else { return 0 }
        let (own, opp) = board.sides(toMove)
        return ReversiBits.perft(own: own, opp: opp, depth: depth)
    }

    /// 실패 진단용 divide: 첫 수마다 그 아래 노드 수(idx 오름차순). 뿌리가 패스면 `(nil, 노드)` 한 줄, 끝난 판·depth < 1 이면 [].
    package static func perftDivide(_ board: ReversiBoard, toMove: ReversiColor, depth: Int) -> [(idx: Int?, nodes: Int)] {
        guard depth >= 1 else { return [] }
        let moves = legalMoves(board, color: toMove)
        if moves.isEmpty {
            guard hasLegalMove(board, color: toMove.opponent) else { return [] }
            return [(nil, perft(board, toMove: toMove.opponent, depth: depth - 1))]
        }
        return moves.map { idx in
            guard case .success(let outcome) = play(board, color: toMove, idx: idx) else { return (idx, 0) }
            return (idx, perft(outcome.board, toMove: toMove.opponent, depth: depth - 1))
        }
    }

    // MARK: 내부

    /// 둘 다 둘 곳이 없다(V-10).
    static func isOver(_ board: ReversiBoard) -> Bool {
        let black = board.black
        let white = board.white
        return ReversiBits.moves(own: black, opp: white) == 0 && ReversiBits.moves(own: white, opp: black) == 0
    }

    /// 끝났다고 이미 아는 판의 분류: 한쪽 0개 → wipeout(가득 차도 전멸 먼저) → 빈칸 0 → board_full → no_moves.
    static func endKindOfFinished(_ board: ReversiBoard) -> ReversiEndKind {
        let counts = board.counts
        if counts.black == 0 || counts.white == 0 { return .wipeout }
        if counts.empty == 0 { return .boardFull }
        return .noMoves
    }

    /// WOF 점수 계산(끝났는지는 보지 않는다).
    static func wofScore(_ board: ReversiBoard) -> ReversiScore {
        let counts = board.counts
        if counts.black > counts.white {
            return ReversiScore(black: counts.black + counts.empty, white: counts.white, result: .blackWin)
        }
        if counts.white > counts.black {
            return ReversiScore(black: counts.black, white: counts.white + counts.empty, result: .whiteWin)
        }
        return ReversiScore(black: 32, white: 32, result: .draw)
    }
}
